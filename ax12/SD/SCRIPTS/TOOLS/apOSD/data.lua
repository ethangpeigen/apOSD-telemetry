-- apOSD data layer: reads ArduPilot telemetry (CRSF / ELRS) and works out what the OSD shows.
-- ArduPilot sends no home distance or bearing over CRSF, so they are computed here.
local cfg = ...

local floor, ceil, rad, deg, min = math.floor, math.ceil, math.rad, math.deg, math.min
local sin, cos, tan, sqrt = math.sin, math.cos, math.tan, math.sqrt
local atan2 = math.atan2 or math.atan -- Lua 5.2 has atan2; 5.3+ gives atan two arguments

local imp = cfg.imperial

local d = {
  alive = false, lq = 0, rss = 0, txv = 0,
  v = 0, a = 0, mah = 0, pct = 0, cells = cfg.cells, cv = 0, bat = 0, -- bat: 0 ok, 1 warn, 2 critical
  sats = 0, fix = false, lat = 0, lon = 0,
  spd = 0, alt = 0, hdg = 0, pitch = 0, roll = 0,
  mode = "", armed = false, armKnown = false, time = 0,
  home = false, dist = 0, rel = 0, -- rel: bearing to home relative to the vehicle's nose
  src = cfg.source == "log" and "log" or "link", -- where the numbers come from: "log" = the app's log file
  mgrs = nil,                      -- position as an MGRS string, nil without a fix
  page = false,                    -- ENTER flips the bottom OSD line between MGRS and current / mAh
  spdU = imp and "mph" or "km/h",
  altU = imp and "ft" or "m",
}

local ids = {}
local star, wasArmed, t0, nextBeep, nextMgrs = false, false, 0, 0, 0
local hlat, hlon, halt = 0, 0, 0

local logv = {} -- latest values from the app's log, under the usual sensor names (log source)
-- read a sensor by name; nil until the radio has discovered it
local function sv(name)
  if cfg.source == "log" then return logv[name] end
  local id = ids[name]
  if not id then
    local f = getFieldInfo(name)
    if not f then return nil end
    id = f.id
    ids[name] = id
  end
  return getValue(id)
end


-- The AX12 app does not pass telemetry to Lua, but it writes a log of it (about once a second) to
-- /<YYYY_MM_DD>.txt: "HH:MM:SS.mmm voltage:11.4v current:0 lat:38.9 lng:-77.0 pitch:.. roll:.. yaw:..".
-- cfg.source = "log" reads that file. Limits: no sats, speed, mode or link quality, and the position is rounded.
local useLog = cfg.source == "log"
local logfh, logname, logpos, logbuf, nextRead, lastSample, mah = nil, "", 0, "", 0, nil, 0

local function num(s)
  return tonumber(string.match(s or "", "^%-?[%d%.eE%+%-]+"))
end

local function closeLog()
  if logfh then io.close(logfh) end
  logfh = nil
end

-- file size by binary search (seek then try to read one byte); there is no size call in this Lua
local function fileEnd(fh)
  local function atEnd(p)
    io.seek(fh, p)
    local s = io.read(fh, 1)
    return s == nil or s == ""
  end
  if atEnd(0) then return 0 end
  local lo, hi = 0, 1024
  while not atEnd(hi) do lo, hi = hi, hi * 2 if hi > 67108864 then return lo end end
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if atEnd(mid) then hi = mid else lo = mid end
  end
  return hi
end

-- returns true while the log is fresh (a new line within cfg.maxAge seconds)
local function readLog(now)
  if now < nextRead then return d.alive end
  nextRead = now + 50
  local t = getDateTime()
  local name = cfg.logFile ~= "" and cfg.logFile or string.format("/%04d_%02d_%02d.txt", t.year, t.mon, t.day)
  if name ~= logname then closeLog(); logname = name; logbuf = "" end
  if not logfh then
    logfh = io.open(name, "r")
    if not logfh then return false end
    logpos = math.max(0, fileEnd(logfh) - 400) -- start near the end; the first, partial line is dropped below
    logbuf = ""
    lastSample = nil
  end
  io.seek(logfh, logpos)
  while true do
    local s = io.read(logfh, 512)
    if s == nil or s == "" then break end
    logpos = logpos + #s
    logbuf = logbuf .. s
  end
  local last
  while true do
    local nl = string.find(logbuf, "\n", 1, true)
    if not nl then break end
    last = string.sub(logbuf, 1, nl - 1)
    logbuf = string.sub(logbuf, nl + 1)
  end
  if last then
    local h, m, sec, v, c, la, lo, p, r, y = string.match(last,
      "^(%d+):(%d+):(%d+)%.%d+ voltage:(%S+) current:(%S+) lat:(%S+) lng:(%S+) pitch:(%S+) roll:(%S+) yaw:(%S+)")
    if h then
      local stamp = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) -- text to numbers explicitly (no string coercion)
      logv.RxBt, logv.Curr = num(v), num(c)
      logv.GPS = { lat = num(la) or 0, lon = num(lo) or 0 }
      logv.Ptch, logv.Roll, logv.Yaw = num(p), num(r), num(y)
      if lastSample and logv.Curr then -- used capacity: integrate the current between log lines
        local dt = (stamp - lastSample) % 86400
        if dt > 0 and dt < 30 then mah = mah + logv.Curr * dt / 3.6 end
      end
      logv.Capa = mah
      lastSample = stamp
      logv.stamp = stamp
    end
  end
  if not logv.stamp then return false end
  local age = (t.hour * 3600 + t.min * 60 + t.sec - logv.stamp) % 86400
  return age <= (cfg.maxAge or 8)
end

-- distance (m) and initial bearing (deg) from point 1 to point 2
local function geo(lat1, lon1, lat2, lon2)
  local p1, p2, dl = rad(lat1), rad(lat2), rad(lon2 - lon1)
  local a = sin((p2 - p1) / 2) ^ 2 + cos(p1) * cos(p2) * sin(dl / 2) ^ 2
  local dist = 12742000 * atan2(sqrt(a), sqrt(1 - a))
  local brg = deg(atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)))
  return dist, brg % 360
end

-- WGS84 latitude / longitude to MGRS, e.g. "18S UJ 23480 06470". digits = 1..5 per axis (5 = 1 m,
-- 4 = 10 m, truncated like real MGRS). nil outside 80S..84N, where MGRS uses a different grid.
local E2 = 0.0066943799901413
local EP2 = E2 / (1 - E2)
local E4, E6 = E2 * E2, E2 * E2 * E2
local M0 = 1 - E2 / 4 - 3 * E4 / 64 - 5 * E6 / 256
local M2 = 3 * E2 / 8 + 3 * E4 / 32 + 45 * E6 / 1024
local M4 = 15 * E4 / 256 + 45 * E6 / 1024
local M6 = 35 * E6 / 3072
local function toMgrs(lat, lon, digits)
  if lat < -80 or lat >= 84 then return nil end
  digits = floor(digits)
  local zone = floor((lon + 180) / 6) % 60 + 1
  if lat >= 56 and lat < 64 and lon >= 3 and lon < 12 then zone = 32 end -- Norway
  if lat >= 72 and lon >= 0 and lon < 42 then -- Svalbard
    zone = lon < 9 and 31 or lon < 21 and 33 or lon < 33 and 35 or 37
  end
  local p = rad(lat)
  local cp, tp = cos(p), tan(p)
  local nu = 6378137 / sqrt(1 - E2 * sin(p) ^ 2)
  local t, c = tp * tp, EP2 * cp * cp
  local a = rad(lon - ((zone - 1) * 6 - 177)) * cp
  local a2 = a * a
  local m = 6378137 * (M0 * p - M2 * sin(2 * p) + M4 * sin(4 * p) - M6 * sin(6 * p))
  local x = 500000 + 0.9996 * nu * a * (1 + a2 * ((1 - t + c) / 6 + a2 * (5 - 18 * t + t * t + 72 * c - 58 * EP2) / 120))
  local y = 0.9996 * (m + nu * tp * a2 * (0.5 + a2 * ((5 - t + 9 * c + 4 * c * c) / 24 + a2 * (61 - 58 * t + t * t + 600 * c - 330 * EP2) / 720)))
  if lat < 0 then y = y + 10000000 end
  local band = min(20, floor((lat + 80) / 8) + 1)
  local k = (zone - 1) % 3 * 8 + floor(x / 100000) -- column letter, 24 letters (no I, O), 8 per zone set
  local r = (floor(y / 100000) + (zone % 2 == 0 and 5 or 0)) % 20 + 1 -- row letter, 20 letters, even zones shifted
  local f, s = "%0" .. digits .. "d", 10 ^ (5 - digits)
  return string.format("%02d%s %s%s " .. f .. " " .. f, zone, string.sub("CDEFGHJKLMNPQRSTUVWX", band, band),
    string.sub("ABCDEFGHJKLMNPQRSTUVWXYZ", k, k), string.sub("ABCDEFGHJKLMNPQRSTUV", r, r),
    floor(x % 100000 / s), floor(y % 100000 / s))
end
d.toMgrs = toMgrs

function d.update()
  local now = getTime() -- 10 ms ticks
  local rssi
  if useLog then rssi = readLog(now) and 100 or 0 else rssi = getRSSI() end
  d.alive = rssi > 0
  if not d.alive then return end

  -- link
  d.lq = sv("RQly") or rssi
  d.rss = sv("1RSS") or 0
  d.txv = getValue("tx-voltage")

  -- battery
  d.v = sv("RxBt") or d.v
  d.a = sv("Curr") or d.a
  d.mah = sv("Capa") or d.mah
  d.pct = sv("Bat%") or d.pct
  if d.cells == 0 and d.v > 1 then d.cells = ceil(d.v / 4.35) end
  d.cv = d.cells > 0 and d.v / d.cells or 0
  d.bat = 0
  if d.cv > 0 then
    if d.cv <= cfg.cellCrit then d.bat = 2 elseif d.cv <= cfg.cellWarn then d.bat = 1 end
  end

  -- gps
  local sats = sv("Sats")
  local g = sv("GPS")
  d.sats = sats or 0
  d.fix = type(g) == "table" and (g.lat ~= 0 or g.lon ~= 0) and (sats == nil or sats >= cfg.minSats)
  if d.fix then
    d.lat, d.lon = g.lat, g.lon
    if cfg.mgrs and now >= nextMgrs then -- twice a second is plenty
      d.mgrs = toMgrs(d.lat, d.lon, cfg.mgrsDigits or 5)
      nextMgrs = now + 50
    end
  else
    d.mgrs = nil
  end

  -- motion (Yaw is the compass heading in rad; Hdg is GPS course and only a fallback)
  local spd = sv("GSpd") or 0
  local al = sv("Alt") or 0
  local yaw = sv("Yaw")
  if yaw then d.hdg = (deg(yaw) + 360) % 360 else d.hdg = sv("Hdg") or d.hdg end
  d.pitch = deg(sv("Ptch") or 0)
  d.roll = deg(sv("Roll") or 0)

  -- flight mode and arm state. ArduPilot only marks "disarmed" with a trailing '*' when
  -- RC_OPTIONS bit 12 is set, so the state is unknown until a '*' has been seen once.
  local fm = sv("FM")
  local armed
  if type(fm) == "string" and fm ~= "" then
    local s = string.sub(fm, -1) == "*" -- plain string.sub(): EdgeTX strings have no :sub() method
    if s then fm = string.sub(fm, 1, -2); star = true end
    d.mode = fm
    if star then armed = not s end
  end
  if armed == nil and cfg.armSwitch ~= "" then armed = getValue(cfg.armSwitch) > 0 end
  d.armKnown = armed ~= nil
  if armed == nil then armed = d.fix end -- unknown: treat "has a fix" as active
  d.armed = armed

  if d.armed and not wasArmed then
    t0 = now
    if d.armKnown then d.home = false end -- new trip: record home again
    if cfg.beeps and d.armKnown then playTone(1800, 150, 0) end
  elseif wasArmed and not d.armed and cfg.beeps then
    playTone(900, 200, 0)
  end
  if d.armed then d.time = floor((now - t0) / 100) end
  wasArmed = d.armed

  -- home
  if d.armed and d.fix and not d.home then
    hlat, hlon, halt = d.lat, d.lon, al
    d.hlat, d.hlon = hlat, hlon -- the map page draws the home marker
    d.home = true
  end
  if d.home and d.fix then
    local ds, b = geo(d.lat, d.lon, hlat, hlon)
    d.dist = ds * (imp and 3.28084 or 1)
    d.rel = (b - d.hdg) % 360
  end

  d.spd = spd * (imp and 0.621371 or 1)
  d.alt = (d.home and al - halt or al) * (imp and 3.28084 or 1)

  if cfg.beeps and d.bat == 2 and now > nextBeep then
    playTone(2200, 200, 0)
    nextBeep = now + 400
  end
end

function d.resetHome() d.home = false end
function d.flip() d.page = not d.page end

-- x is already in the display unit (m or ft)
function d.fmtDist(x)
  if x < 1000 then return string.format("%d%s", floor(x + 0.5), d.altU) end
  if imp then return string.format("%.2fmi", x / 5280) end
  return string.format("%.2fkm", x / 1000)
end

function d.fmtTime()
  return string.format("%02d:%02d", floor(d.time / 60), floor(d.time % 60))
end

return d

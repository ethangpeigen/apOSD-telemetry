-- apOSD layout for colour radios (TX16S, T16, Horus, TX15, NV14, ...)
local cfg, d = ...

local W, H = LCD_W, LCD_H
local cx, cy = math.floor(W / 2), math.floor(H / 2)
local floor, sin, cos, rad = math.floor, math.sin, math.cos, math.rad
local fmt = string.format

local BG, FG, DIM = lcd.RGB(10, 12, 16), lcd.RGB(240, 244, 248), lcd.RGB(130, 142, 155)
local GOOD, WARN, BAD = lcd.RGB(70, 225, 110), lcd.RGB(255, 200, 40), lcd.RGB(255, 70, 60)

-- small / medium / large fonts; one step bigger on 800x480 screens
local FS, FM, FL = SMLSIZE, MIDSIZE, DBLSIZE
if W >= 800 then FS, FM, FL = 0, DBLSIZE, XXLSIZE end
local _, hS = lcd.sizeText("0", FS)
local _, hM = lcd.sizeText("0", FM)
local _, hL = lcd.sizeText("0", FL)
local m = floor(W / 60) + 2 -- margin
local ty = floor(m / 2)     -- top row y

-- optional background picture, one file per screen size (see tools/make_bg.py);
-- if the file is missing the screen simply stays plain dark
local bg
if cfg.background then
  local ok, b = pcall(Bitmap.open, fmt("/SCRIPTS/TELEMETRY/apOSD/bg_%dx%d.png", W, H))
  if ok and b and Bitmap.getSize(b) > 0 then bg = b end
end

local v = {}

local function col(c)
  lcd.setColor(CUSTOM_COLOR, c)
  return CUSTOM_COLOR
end

-- a: "r" right aligned at x, "c" centred on x
local function put(x, y, s, f, c, a)
  if a then
    local w = lcd.sizeText(s, f)
    if a == "r" then x = x - w else x = x - floor(w / 2) end
  end
  lcd.drawText(x, y, s, f + col(c))
end

local function line(x1, y1, x2, y2, c)
  lcd.drawLine(floor(x1 + 0.5), floor(y1 + 0.5), floor(x2 + 0.5), floor(y2 + 0.5), SOLID, col(c))
end

local function label(n)
  if n == 0 then return "N" elseif n == 90 then return "E" elseif n == 180 then return "S" elseif n == 270 then return "W" end
  return fmt("%d", n)
end

-- heading tape: 90 degrees visible, baseline at y
local function tape(y, w)
  local x0 = cx - floor(w / 2)
  local ppd = w / 90
  line(x0, y, x0 + w, y, FG)
  local a = floor((d.hdg - 45) / 10) * 10
  while a <= d.hdg + 45 do
    local x = floor(cx + (a - d.hdg) * ppd + 0.5)
    if x >= x0 and x <= x0 + w then
      local n = a % 360
      if n % 30 == 0 then
        line(x, y - 7, x, y, FG)
        put(x, y - 8 - hS, label(n), FS, n % 90 == 0 and WARN or FG, "c")
      else
        line(x, y - 4, x, y, DIM)
      end
    end
    a = a + 10
  end
  line(cx, y + 3, cx - 5, y + 10, WARN); line(cx, y + 3, cx + 5, y + 10, WARN)
  line(cx - 5, y + 10, cx + 5, y + 10, WARN)
  put(cx, y + 12, fmt("%03d", floor(d.hdg + 0.5) % 360), FM, FG, "c")
end

-- arrow at (x, y), radius r, pointing ang degrees clockwise from straight up
local function arrow(x, y, r, ang, c)
  local function pt(len, off)
    local a = rad(ang + off)
    return x + len * sin(a), y - len * cos(a)
  end
  local tx, ty2 = pt(r, 0)
  local rx, ry = pt(r * 0.85, 145)
  local nx, ny = pt(r * 0.35, 180)
  local lx, ly = pt(r * 0.85, -145)
  for o = 0, 1 do -- drawn twice, one pixel apart, for weight
    line(tx + o, ty2, rx + o, ry, c); line(rx + o, ry, nx + o, ny, c)
    line(nx + o, ny, lx + o, ly, c); line(lx + o, ly, tx + o, ty2, c)
  end
end

local function horizon()
  local r = rad(d.roll)
  local ppd = H / 60 -- pixels per degree of pitch
  local lim = H * 0.3
  local function pl(off, len, c) -- horizon line (off = 0) or the rung "off" degrees above it
    local p = math.max(-lim, math.min(lim, (d.pitch - off) * ppd))
    local x1, y1 = cx - len * cos(r) + p * sin(r), cy + len * sin(r) + p * cos(r)
    local x2, y2 = cx + len * cos(r) + p * sin(r), cy - len * sin(r) + p * cos(r)
    line(x1, y1, x2, y2, c)
  end
  pl(0, W * 0.2, FG)
  for _, o in ipairs({ -20, -10, 10, 20 }) do pl(o, W * 0.06, DIM) end
end

function v.draw()
  local on = floor(getTime() / 50) % 2 == 0 -- ~0.5 s blink
  if bg then lcd.drawBitmap(bg, 0, 0) else lcd.drawFilledRectangle(0, 0, W, H, col(BG)) end

  if cfg.horizon then horizon() end
  -- crosshair
  line(cx - 28, cy, cx - 10, cy, FG); line(cx + 10, cy, cx + 28, cy, FG)
  line(cx, cy - 6, cx, cy + 6, FG)

  -- top left: battery
  local bc = d.bat == 2 and BAD or d.bat == 1 and WARN or FG
  if d.bat < 2 or on then put(m, ty, fmt("%.1fV", d.v), FM, bc) end
  if d.cells > 0 then put(m, ty + hM + 2, fmt("%.2fV/cell", d.cv), FS, d.bat == 0 and DIM or bc) end

  -- top right: satellites, link
  put(W - m, ty, fmt("%d SAT", d.sats), FM, d.fix and GOOD or WARN, "r")
  local lc = d.lq < 50 and BAD or d.lq < 70 and WARN or FG
  put(W - m, ty + hM + 2, fmt("LQ %d%%  %ddB", floor(d.lq), floor(d.rss)), FS, lc, "r")

  tape(ty + hS + 14, floor(W * 0.38))

  -- left: speed
  put(m, cy - floor(hL / 2), d.spd >= 10 and fmt("%d", floor(d.spd + 0.5)) or fmt("%.1f", d.spd), FL, FG)
  put(m, cy + floor(hL / 2) + 2, d.spdU, FS, DIM)

  -- right: current draw, used capacity, optional altitude
  put(W - m, cy - hM, fmt("%.1fA", d.a), FM, FG, "r")
  put(W - m, cy + 2, fmt("%d mAh", floor(d.mah)), FS, DIM, "r")
  if cfg.showAlt then put(W - m, cy + hS + 8, fmt("ALT %d%s", floor(d.alt + 0.5), d.altU), FS, FG, "r") end

  -- bottom: mode + arm state | home arrow + distance | timer + TX battery
  local by = H - hM - m
  put(m, by, d.mode, FM, FG)
  if d.armKnown then
    put(m, by - hS - 2, d.armed and "ARMED" or "DISARMED", FS, d.armed and GOOD or WARN)
  end
  if d.home and d.fix then
    arrow(cx - 36, by + floor(hM / 2), floor(hM * 0.8), d.rel, FG)
    put(cx - 8, by, d.fmtDist(d.dist), FM, FG)
  else
    put(cx - 36, by, "HOME --", FM, DIM)
  end
  put(W - m, by, d.fmtTime(), FM, FG, "r")
  put(W - m, by - hS - 2, fmt("TX %.1fV", d.txv), FS, DIM, "r")
  if cfg.mgrs then put(cx, by - hS - 2, d.mgrs or "MGRS --", FS, d.mgrs and FG or DIM, "c") end

  -- one banner for the most important problem
  local msg, mc
  if not d.alive then msg, mc = "NO TELEMETRY", BAD
  elseif d.bat == 2 then msg, mc = "BATTERY CRITICAL", BAD
  elseif not d.fix then msg, mc = "NO GPS FIX", WARN end
  if msg and (on or mc == WARN) then
    local w, h = lcd.sizeText(msg, FM)
    local y = cy + floor(H * 0.2)
    lcd.drawFilledRectangle(cx - floor(w / 2) - 8, y - 3, w + 16, h + 6, col(BG)) -- keeps it readable over the picture
    lcd.drawRectangle(cx - floor(w / 2) - 8, y - 3, w + 16, h + 6, col(mc))
    put(cx, y, msg, FM, mc, "c")
  end
end

return v

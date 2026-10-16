-- apOSD map page: offline map tiles under the vehicle, with heading arrow, home marker, trail and scale bar.
-- Tiles are made on a PC with tools/make_map.py and live in <mapDir>/<z>_<x>_<y>.jpg (256 px, standard web-map tiles).
-- Loaded by color.lua the first time the page is opened. No string methods (this Lua has none).
local cfg, d, mapDir, ui = ...

local floor, sin, cos, rad, log, pi, sqrt = math.floor, math.sin, math.cos, math.rad, math.log, math.pi, math.sqrt
local fmt = string.format
local W, H = LCD_W, LCD_H
local zmin, zmax = cfg.mapMin or 15, cfg.mapMax or 19
local zoom = cfg.mapZoom or 17
local cache, order, trail = {}, {}, {}
local lastTrail, opened = 0, false

local M = {}

-- Web Mercator world pixel of a position at a zoom level
local function world(lat, lon, z)
  local n = 256 * 2 ^ z
  local s = sin(rad(lat))
  return (lon + 180) / 360 * n, (0.5 - log((1 + s) / (1 - s)) / (4 * pi)) * n
end

-- a tile bitmap, or nil; at most one new file is opened per frame, and a tile that is missing is remembered
local function tile(z, x, y)
  local key = fmt("%d_%d_%d", z, x, y)
  local b = cache[key]
  if b ~= nil then return b or nil end
  if opened then return nil end
  opened = true
  local ok, bm = pcall(Bitmap.open, mapDir .. key .. ".jpg")
  if ok and bm and Bitmap.getSize(bm) > 0 then
    cache[key] = bm
    order[#order + 1] = key
    if #order > 12 then cache[table.remove(order, 1)] = nil end -- keep memory small
    return bm
  end
  cache[key] = false
  return nil
end

local function isKey(e, a, b, c, d2)
  return e ~= nil and (e == a or e == b or e == c or e == d2)
end

-- zoom with the radio's up / down keys (the AX12 on-screen Up / Down buttons)
function M.key(e)
  if isKey(e, EVT_VIRTUAL_PREV, EVT_ROT_LEFT, EVT_MINUS_BREAK, EVT_UP_BREAK) then zoom = math.min(zmax, zoom + 1)
  elseif isKey(e, EVT_VIRTUAL_NEXT, EVT_ROT_RIGHT, EVT_PLUS_BREAK, EVT_DOWN_BREAK) then zoom = math.max(zmin, zoom - 1) end
end

local function track()
  local now = getTime()
  if d.fix and now - lastTrail >= 200 then -- a trail point about every 2 seconds
    lastTrail = now
    local p = trail[#trail]
    if not p or p[1] ~= d.lat or p[2] ~= d.lon then
      trail[#trail + 1] = { d.lat, d.lon }
      if #trail > 150 then table.remove(trail, 1) end
    end
  end
end

function M.draw()
  opened = false
  track()
  local put, line = ui.put, ui.line
  if not d.fix then
    put(W / 2, H / 2 - ui.hM / 2, "NO GPS FIX", ui.FM, ui.WARN, "c")
    put(W / 2, H / 2 + ui.hM, "map needs a position", ui.FS, ui.DIM, "c")
    return
  end
  local cxw, cyw = world(d.lat, d.lon, zoom)
  local left, top = cxw - W / 2, cyw - H / 2
  local drawn = 0
  for ty = floor(top / 256), floor((top + H) / 256) do
    for tx = floor(left / 256), floor((left + W) / 256) do
      local b = tile(zoom, tx, ty)
      if b then
        lcd.drawBitmap(b, floor(tx * 256 - left), floor(ty * 256 - top), 100) -- the 4th argument is required on the AX12
        drawn = drawn + 1
      end
    end
  end
  local function xy(lat, lon)
    local wx, wy = world(lat, lon, zoom)
    return floor(wx - left + 0.5), floor(wy - top + 0.5)
  end
  -- everything below is drawn heavy, on dark panels or with a dark outline, so it stays readable over any imagery
  local function thick(x1, y1, x2, y2, c) -- a 3 px line
    line(x1, y1, x2, y2, c); line(x1 + 1, y1, x2 + 1, y2, c); line(x1, y1 + 1, x2, y2 + 1, c)
  end
  -- trail
  if cfg.mapTrail ~= false then
    local px, py
    for i = 1, #trail do
      local x, y = xy(trail[i][1], trail[i][2])
      if px and x > -W and x < 2 * W and y > -H and y < 2 * H then thick(px, py, x, y, ui.WARN) end
      px, py = x, y
    end
  end
  -- home: a big green cross with a dark outline and a lettered tag
  if d.home and d.hlat then
    local x, y = xy(d.hlat, d.hlon)
    if x > 14 and x < W - 14 and y > 40 and y < H - 30 then
      for _, o in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do
        thick(x - 10 + o[1], y + o[2], x + 10 + o[1], y + o[2], ui.BG); thick(x + o[1], y - 10 + o[2], x + o[1], y + 10 + o[2], ui.BG)
      end
      thick(x - 10, y, x + 10, y, ui.GOOD); thick(x, y - 10, x, y + 10, ui.GOOD)
      ui.fill(x + 12, y - 22, floor(ui.hM * 0.6) + 8, ui.hM + 2, ui.BG)
      put(x + 16, y - 21, "H", ui.FM, ui.GOOD)
    end
  end
  -- the vehicle: a large red arrow with a dark outline
  local ax, ay = floor(W / 2), floor(H / 2)
  for _, o in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 }, { -2, -2 }, { 2, 2 }, { -2, 2 }, { 2, -2 } }) do
    ui.arrow(ax + o[1], ay + o[2], 18, d.hdg, ui.BG)
  end
  ui.arrow(ax, ay, 18, d.hdg, ui.BAD)
  -- top bar: zoom, position, distance from home
  ui.fill(0, 0, W, ui.hM + 8, ui.BG)
  put(6, 4, fmt("Z%d", zoom), ui.FM, ui.WARN)
  put(64, 4 + floor((ui.hM - ui.hS) / 2), d.mgrs or "", ui.FS, ui.FG)
  if d.home and d.dist then put(W - 6, 4, d.fmtDist(d.dist) .. " home", ui.FM, ui.GOOD, "r") end
  -- scale bar on a dark panel
  local mpp = 156543.03 * cos(rad(d.lat)) / 2 ^ zoom -- metres per pixel
  local len, shown = 10, 10
  for _, m in ipairs({ 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 }) do
    if m / mpp <= 120 then len = m / mpp; shown = m end
  end
  local label = shown >= 1000 and fmt("%d km", shown / 1000) or fmt("%d m", shown)
  local lw = lcd.sizeText(label, ui.FS)
  ui.fill(0, H - 30, 22 + floor(len) + lw, 30, ui.BG)
  thick(8, H - 14, 8 + floor(len), H - 14, ui.FG); thick(8, H - 22, 8, H - 6, ui.FG); thick(8 + floor(len), H - 22, 8 + floor(len), H - 6, ui.FG)
  put(14 + floor(len), H - 14 - floor(ui.hS / 2), label, ui.FS, ui.FG)
  if drawn == 0 then put(W / 2, H - 50, "no map tiles for this spot (tools/make_map.py)", ui.FS, ui.DIM, "c") end
end

return M

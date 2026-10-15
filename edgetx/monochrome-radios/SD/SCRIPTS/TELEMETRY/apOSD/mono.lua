-- apOSD layout for monochrome radios (128x64 Q X7 / Zorro / Boxer / TX12, 212x64 X9D)
local cfg, d = ...

local W = LCD_W
local cx = math.floor(W / 2)
local floor, sin, cos, rad = math.floor, math.sin, math.cos, math.rad
local fmt = string.format

local v = {}

local function tw(s, f)
  if lcd.sizeText then return (lcd.sizeText(s, f)) end
  return #s * (f == MIDSIZE and 8 or f == SMLSIZE and 5 or 6)
end

-- a: "r" right aligned at x, "c" centred on x
local function put(x, y, s, f, a)
  if a == "r" then x = x - tw(s, f) elseif a == "c" then x = x - floor(tw(s, f) / 2) end
  lcd.drawText(x, y, s, f)
end

local function line(x1, y1, x2, y2)
  lcd.drawLine(floor(x1 + 0.5), floor(y1 + 0.5), floor(x2 + 0.5), floor(y2 + 0.5), SOLID, FORCE)
end

local function label(n)
  if n == 0 then return "N" elseif n == 90 then return "E" elseif n == 180 then return "S" elseif n == 270 then return "W" end
  return fmt("%d", n)
end

-- heading tape: 80 degrees visible, baseline at y
local function tape(y, w)
  local x0 = cx - floor(w / 2)
  local ppd = w / 80
  line(x0, y, x0 + w, y)
  local a = floor((d.hdg - 40) / 10) * 10
  while a <= d.hdg + 40 do
    local x = floor(cx + (a - d.hdg) * ppd + 0.5)
    if x >= x0 and x <= x0 + w then
      local n = a % 360
      if n % 30 == 0 then
        line(x, y - 4, x, y)
        put(x, y - 12, label(n), SMLSIZE, "c")
      else
        line(x, y - 2, x, y)
      end
    end
    a = a + 10
  end
  line(cx, y + 2, cx - 2, y + 5) -- pointer
  line(cx, y + 2, cx + 2, y + 5)
  line(cx - 2, y + 5, cx + 2, y + 5)
  put(cx, y + 7, fmt("%03d", floor(d.hdg + 0.5) % 360), SMLSIZE, "c")
end

-- arrow at (x, y), radius r, pointing ang degrees clockwise from straight up
local function arrow(x, y, r, ang)
  local function pt(len, off)
    local a = rad(ang + off)
    return x + len * sin(a), y - len * cos(a)
  end
  local tx, ty = pt(r, 0)
  local rx, ry = pt(r * 0.85, 145)
  local nx, ny = pt(r * 0.35, 180)
  local lx, ly = pt(r * 0.85, -145)
  line(tx, ty, rx, ry); line(rx, ry, nx, ny); line(nx, ny, lx, ly); line(lx, ly, tx, ty)
end

local function horizon(y, len)
  local r = rad(d.roll)
  local p = math.max(-12, math.min(12, d.pitch * 0.5))
  local function pt(px)
    return cx + px * cos(r) + p * sin(r), y - px * sin(r) + p * cos(r)
  end
  local x1, y1 = pt(-len)
  local x2, y2 = pt(len)
  line(x1, y1, x2, y2)
end

function v.draw()
  local on = floor(getTime() / 50) % 2 == 0 -- ~0.5 s blink

  -- row 0: battery | mode | satellites
  local bf = SMLSIZE
  if d.bat == 2 then bf = bf + INVERS end
  if d.bat < 2 or on then put(0, 0, fmt("%.1fV", d.v), bf) end
  put(cx, 0, d.mode, SMLSIZE, "c")
  put(W - 1, 0, fmt("%dS", d.sats), d.fix and SMLSIZE or SMLSIZE + INVERS, "r")

  tape(20, floor(W * 0.62))

  if cfg.horizon then horizon(39, floor(W * 0.14)) end
  -- crosshair
  line(cx - 9, 39, cx - 4, 39); line(cx + 4, 39, cx + 9, 39); line(cx, 36, cx, 42)

  -- speed (left) and home (right)
  put(1, 25, d.spd >= 10 and fmt("%d", floor(d.spd + 0.5)) or fmt("%.1f", d.spd), MIDSIZE)
  put(1, 38, d.spdU, SMLSIZE)
  if d.home and d.fix then
    arrow(W - 17, 31, 8, d.rel)
    put(W - 1, 43, d.fmtDist(d.dist), SMLSIZE, "r")
  else
    put(W - 17, 29, "--", SMLSIZE, "c")
    put(W - 1, 43, "HOME", SMLSIZE, "r")
  end
  if cfg.showAlt then put(W - 1, 25, fmt("%d%s", floor(d.alt + 0.5), d.altU), SMLSIZE, "r") end

  -- row 3: position as MGRS, or current / used (ENTER swaps them) | link quality
  if cfg.mgrs and not d.page then
    put(0, 50, d.mgrs or "MGRS --", SMLSIZE)
  else
    put(0, 50, fmt("%.1fA %dmAh", d.a, floor(d.mah)), SMLSIZE)
  end
  put(W - 1, 50, fmt("LQ%d", floor(d.lq)), d.lq < 50 and SMLSIZE + INVERS or SMLSIZE, "r")

  -- row 4: timer | status | signal
  put(0, 57, d.fmtTime(), SMLSIZE)
  local st, flag = nil, SMLSIZE
  if not d.alive then st, flag = "NO TELEM", SMLSIZE + INVERS
  elseif d.bat == 2 then st, flag = "BAT LOW", SMLSIZE + INVERS
  elseif not d.fix then st = "NO GPS"
  elseif d.armKnown then st = d.armed and "ARMED" or "DISARM" end
  if st and (flag == SMLSIZE or on) then put(cx, 57, st, flag, "c") end
  put(W - 1, 57, fmt("%ddB", floor(d.rss)), SMLSIZE, "r")
end

return v

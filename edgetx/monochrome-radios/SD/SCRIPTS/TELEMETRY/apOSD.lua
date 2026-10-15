-- apOSD: ArduPilot OSD mirror for EdgeTX / OpenTX radios (CRSF / ELRS telemetry)
-- Draws the same kind of screen your goggles show: battery, GPS, speed, heading tape,
-- home arrow + distance, flight mode, link quality, flight timer.
-- Files live in /SCRIPTS/TELEMETRY/apOSD/ (cfg = your settings, data = sensors, mono/color = layouts).
-- If anything fails to load or crashes, the real error text is shown on the screen (ENTER = retry).

local PATH = "/SCRIPTS/TELEMETRY/apOSD/"
local ELONG = EVT_VIRTUAL_ENTER_LONG or EVT_ENTER_LONG
local EENTER = EVT_VIRTUAL_ENTER or EVT_ENTER_BREAK

local cfg, d, view, err

-- load one module; on failure keep the real reason so it can be shown instead of a bare "Syntax error"
local function load(name, ...)
  collectgarbage() -- free memory first: a reload can run out of RAM on small radios
  local f, e = loadScript(PATH .. name)
  if type(f) ~= "function" then
    -- the radio keeps a compiled copy (.luac) of every script it loads; if that copy is bad,
    -- retry from the plain source ("t" = text, "x" = don't compile)
    f, e = loadScript(PATH .. name, "tx")
  end
  if type(f) ~= "function" then
    err = name .. ": " .. tostring(e or "could not load (file missing, or out of memory)")
    return nil
  end
  local ok, r = pcall(f, ...)
  if not ok then
    err = name .. ": " .. tostring(r)
    return nil
  end
  return r
end

local function init()
  cfg, d, view, err = nil, nil, nil, nil -- drop any previous copy before loading again
  cfg = load("cfg.lua")
  if cfg then d = load("data.lua", cfg) end
  if d then view = load(LCD_W > 212 and "color.lua" or "mono.lua", cfg, d) end
  collectgarbage()
end

local function fail(msg)
  lcd.clear()
  local color = LCD_W > 212
  local lh = color and 20 or 9
  local n = math.floor(LCD_W / (color and 9 or 5)) - 1 -- characters per line
  lcd.drawText(0, 0, "apOSD error ENTER=retry", color and 0 or SMLSIZE + INVERS)
  -- (EdgeTX strings have no methods, so no s:sub() / s:gsub() anywhere in this script)
  local s = string.gsub(tostring(msg), "/SCRIPTS/TELEMETRY/apOSD/", "")
  local y, i = lh + 2, 1
  while i <= #s and y < LCD_H - lh do
    lcd.drawText(0, y, string.sub(s, i, i + n - 1), color and 0 or SMLSIZE)
    i = i + n
    y = y + lh
  end
end

-- runs while another telemetry screen is showing, so home is still recorded
local function background()
  if d and not err then
    local ok, e = pcall(d.update)
    if not ok then err = tostring(e) end
  end
end

local function run(event)
  if err or not view then
    if event == EENTER then init() end
    fail(err or "script did not load")
    return 0
  end
  local ok, e = pcall(d.update)
  if ok then
    if ELONG and event == ELONG then d.resetHome() end -- long ENTER: home = here
    if EENTER and event == EENTER then d.flip() end -- ENTER: MGRS <-> current / mAh
    lcd.clear()
    ok, e = pcall(view.draw)
  end
  if not ok then
    err = tostring(e)
    fail(err)
  end
  return 0
end

return { init = init, run = run, background = background }

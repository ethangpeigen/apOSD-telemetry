-- apOSD for the RadioMaster AX12 (RadioMasterOS Lua): ArduPilot OSD mirror, CRSF / ELRS telemetry.
-- Runs as a TOOL: open it from the app's Lua tab; the Exit button closes it.
-- Files live in /SCRIPTS/TOOLS/apOSD/ (cfg = your settings, data = sensors, color = layout, bg_*.png = picture).
-- If anything fails to load or crashes, the real error text is shown on the screen (Enter = retry).
-- (This Lua has no string methods, so no s:sub() / s:gsub() anywhere in this script.)

local PATH = "/SCRIPTS/TOOLS/apOSD/"

-- the app may send either the newer or the older key-event names; accept both, and never match a nil event
local function isEvent(e, a, b) return e ~= nil and (e == a or e == b) end
local function isEnter(e) return isEvent(e, EVT_VIRTUAL_ENTER, EVT_ENTER_BREAK) end
local function isExit(e) return isEvent(e, EVT_VIRTUAL_EXIT, EVT_EXIT_BREAK) end
local function isLong(e) return isEvent(e, EVT_VIRTUAL_ENTER_LONG, EVT_ENTER_LONG) end

local cfg, d, view, err

-- load one module; on failure keep the real reason so it can be shown instead of a bare "Syntax error"
local function load(name, ...)
  collectgarbage()
  local f, e = loadScript(PATH .. name)
  if type(f) ~= "function" then
    -- the radio keeps a compiled copy (.luac) of scripts it loads; if that copy is bad, retry from the plain source
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
  cfg, d, view, err = nil, nil, nil, nil
  cfg = load("cfg.lua")
  if cfg then
    cfg.dir = PATH -- lets the layout find the background picture next to the scripts
    d = load("data.lua", cfg)
  end
  if d then view = load("color.lua", cfg, d) end
  collectgarbage()
end

local function fail(msg)
  lcd.clear()
  local lh = 20
  local n = math.floor(LCD_W / 9) - 1 -- characters per line
  lcd.drawText(0, 0, "apOSD error  Enter = retry  Exit = quit", 0)
  local s = string.gsub(tostring(msg), PATH, "")
  local y, i = lh + 2, 1
  while i <= #s and y < LCD_H - lh do
    lcd.drawText(0, y, string.sub(s, i, i + n - 1), 0)
    i = i + n
    y = y + lh
  end
end

local function run(event)
  if isExit(event) then return 2 end -- a tool script ends when run() returns non-zero
  if err or not view then
    if isEnter(event) then init() end
    fail(err or "script did not load")
    return 0
  end
  local ok, e = pcall(d.update)
  if ok then
    if isLong(event) then d.resetHome() end -- long Enter: home = here
    if isEnter(event) then d.flip() end
    lcd.clear()
    ok, e = pcall(view.draw)
  end
  if not ok then
    err = tostring(e)
    fail(err)
  end
  return 0
end

return { init = init, run = run }

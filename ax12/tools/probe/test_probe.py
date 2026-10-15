"""Run apProbe.lua against mock radios: full colour API, stripped-down API, and no file writing."""
import importlib, sys
from pathlib import Path
SRC = Path(__file__).with_name("apProbe.lua")

FULL = """
LCD_W, LCD_H = 1280, 720
SMLSIZE, MIDSIZE, DBLSIZE, XXLSIZE, RIGHT, CUSTOM_COLOR = 1, 2, 4, 8, 16, 32
EVT_EXIT_BREAK, EVT_ENTER_BREAK, EVT_VIRTUAL_ENTER = 100, 101, 102
DRAWN = {}
lcd = {
  clear = function() DRAWN = {} end,
  drawText = function(x, y, s, f) DRAWN[#DRAWN + 1] = s end,
  drawLine = function() end, drawRectangle = function() end, drawFilledRectangle = function() end,
  sizeText = function(s, f) return 10, 18 end,
  RGB = function(r, g, b) return r * 65536 + g * 256 + b end, setColor = function() end,
}
function getVersion() return "2.11.0", "ax12", 2, 11, 0, "EdgeTX" end
function getRSSI() return 88, 45, 42 end
function getTime() return 0 end
function playTone() end
function getFieldInfo(n)
  if type(n) == "number" then if n == 5 then return { id = 5, name = "voltage" } elseif n == 9 then return { id = 9, name = "lat" } end return nil end
  if n ~= "TPWR" and n ~= "Hdg" then return { id = n } end
end
function getValue(n)
  if n == "GPS" then return { lat = 11.1, lon = 22.2 } end   -- the probe must not print these
  if n == "FM" then return "HOLD*" end
  return 7.5
end
function loadScript(p) return function() end end
FILES = {}
io = { open = function(p, m) FILES[p] = {} return { path = p } end,
       write = function(fh, ...) for _, s in ipairs({...}) do FILES[fh.path][#FILES[fh.path] + 1] = s end end,
       close = function() end }
"""
STRIPPED = """
LCD_W, LCD_H = 128, 64
lcd = { clear = function() end, drawText = function() end }
function getValue() return 0 end
"""
NOWRITE = FULL.replace("io = {", "io_unused = {")

def run(name, env, ver="52", strip_strings=True):
    lua = importlib.import_module(f"lupa.lua{ver}").LuaRuntime(unpack_returned_tuples=True)
    lua.execute(env)
    if strip_strings: lua.execute('debug.setmetatable("", nil)')   # like EdgeTX: no string methods
    mod = lua.eval("loadfile")(str(SRC))()
    mod.init()
    for ev in (0, 0):
        assert mod.run(ev) == 0, "run() should keep going"
    assert mod.run(lua.globals().EVT_EXIT_BREAK or -1) in (0, 2)
    report = lua.eval("(function() local t = {} for k, v in pairs(FILES or {}) do t[#t+1] = table.concat(v) end return table.concat(t) end)")()
    print(f"[lua{ver}] {name}: init and run OK")
    return lua, report

for ver in ("52", "54"):
    lua, rep = run("full colour API", FULL, ver)
    assert "LCD 1280 x 720" in rep and "string methods s:sub(): NO" in rep, rep[:300]
    assert "11.1" not in rep and "22.2" not in rep, "GPS position leaked into the report"
    assert "count: 2" in rep and "voltage lat" in rep, "name enumeration missing"
    assert "GPS        found (table, value not recorded)" in rep, rep
    if ver == "52": print("---- sample of the saved report ----\n" + "\n".join(rep.splitlines()[:6] + ["..."] + rep.splitlines()[-8:]))
    run("stripped-down API", STRIPPED, ver)
    run("no file writing", NOWRITE, ver)
print("all probe tests passed")

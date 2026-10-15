"""Run apProbe5.lua against a mock radio (no string methods): it must list globals, save a report and quit on Exit."""
import importlib
from pathlib import Path
SRC = Path(__file__).with_name("apProbe5.lua")
ENV = """
LCD_W, LCD_H = 480, 272
SMLSIZE, RIGHT, EVT_EXIT_BREAK = 1, 16, 100
FILES, TICKS = {}, 0
lcd = { clear = function() end, drawText = function() end, sizeText = function() return 7, 17 end, RGB = function() return 0 end }
model = { getInfo = function() end, ax12SecretFunction = function() end }
function getTime() return TICKS end
function getValue() return 0 end
function axGetTelemetry() end
io = { open = function(p) FILES[p] = {} return { path = p } end,
       write = function(fh, ...) for _, s in ipairs({...}) do FILES[fh.path][#FILES[fh.path] + 1] = s end end, close = function() end }
"""
for ver in ("52", "54"):
    lua = importlib.import_module(f"lupa.lua{ver}").LuaRuntime(unpack_returned_tuples=True)
    lua.execute(ENV); lua.execute('debug.setmetatable("", nil)')
    mod = lua.eval("loadfile")(str(SRC))(); mod.init()
    for t in range(0, 2000, 400): lua.execute(f"TICKS = {t}"); assert mod.run(0) == 0
    assert mod.run(100) == 2
    rep = lua.eval("(function() local t = {} for k, v in pairs(FILES) do t[#t+1] = table.concat(v) end return table.concat(t) end)")()
    assert "axGetTelemetry()" in rep and "ax12SecretFunction" in rep, rep[:300]
    print(f"[lua{ver}] probe5 OK: finds extra globals and table members, saves its report")
print("probe5 test passed")

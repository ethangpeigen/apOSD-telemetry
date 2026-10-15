"""Run apProbe4.lua against mock radios: frames counted, the GPS bytes never recorded, and it survives a radio without the function."""
import importlib
from pathlib import Path
SRC = Path(__file__).with_name("apProbe4.lua")
GPS = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 0, 0, 0, 12]       # distinctive position-like bytes
ENV = """
LCD_W, LCD_H = 480, 272
SMLSIZE, EVT_EXIT_BREAK = 1, 100
FILES, TICKS, QUEUE = {}, 0, {}
lcd = { clear = function() end, drawText = function() end, sizeText = function() return 7, 17 end }
function getTime() return TICKS end
function crossfireTelemetryPush() end
function crossfireTelemetryPop()
  local f = table.remove(QUEUE, 1)
  if f then return f[1], f[2] end
end
io = { open = function(p) FILES[p] = {} return { path = p } end,
       write = function(fh, ...) for _, s in ipairs({...}) do FILES[fh.path][#FILES[fh.path] + 1] = s end end, close = function() end }
"""
for ver in ("52", "54"):
    lua = importlib.import_module(f"lupa.lua{ver}").LuaRuntime(unpack_returned_tuples=True)
    lua.execute(ENV); lua.execute('debug.setmetatable("", nil)')
    lua.globals().GPSBYTES = lua.table_from(GPS)
    lua.execute("""QUEUE = { {0x02, GPSBYTES}, {0x08, {0x00, 0x71, 0x00, 0x00, 0x00, 0x01, 0x9C, 0x50}}, {0x1E, {1, 2, 3, 4, 5, 6}},
                    {0x21, {72, 79, 76, 68, 0}}, {0x14, {40, 41, 100, 9, 1, 3, 4, 38, 100, 10}}, {0x02, GPSBYTES} }""")
    mod = lua.eval("loadfile")(str(SRC))(); mod.init()
    for t in (0, 100, 300, 500): lua.execute(f"TICKS = {t}"); assert mod.run(0) == 0
    rep = lua.eval("(function() local t = {} for k, v in pairs(FILES) do t[#t+1] = table.concat(v) end return table.concat(t) end)")()
    assert "frames received: 6" in rep, rep
    assert "type 0x02  count 2  length 15  (position bytes not recorded)" in rep, rep
    assert "type 0x08  count 1  length 8  last: 00 71 00 00 00 01 9C 50" in rep, rep
    assert "DE AD" not in rep and "BE EF" not in rep, "GPS bytes leaked"
    assert mod.run(100) == 2
    # a radio without the function
    lua2 = importlib.import_module(f"lupa.lua{ver}").LuaRuntime(unpack_returned_tuples=True)
    lua2.execute(ENV.replace("function crossfireTelemetryPop()", "function unused()")); lua2.execute("crossfireTelemetryPop = nil")
    lua2.execute('debug.setmetatable("", nil)')
    m2 = lua2.eval("loadfile")(str(SRC))(); m2.init()
    for t in (0, 300): lua2.execute(f"TICKS = {t}"); assert m2.run(0) == 0
    rep2 = lua2.eval("(function() local t = {} for k, v in pairs(FILES) do t[#t+1] = table.concat(v) end return table.concat(t) end)")()
    assert "NOT available" in rep2
    print(f"[lua{ver}] probe4 OK: frames counted, GPS bytes not recorded, works without the function")
print("probe4 test passed")

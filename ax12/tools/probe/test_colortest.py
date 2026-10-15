"""Run apColorTest.lua against a mock radio (no string methods): every page must draw without an error."""
import importlib
from pathlib import Path
SRC = Path(__file__).with_name("apColorTest.lua")
ENV = """
LCD_W, LCD_H = 480, 272
SMLSIZE, MIDSIZE, CUSTOM_COLOR, SOLID, EVT_EXIT_BREAK = 1, 2, 32, 0, 100
COLOR_THEME_PRIMARY1, COLOR_THEME_WARNING = 7, 9
CALLS, TICKS = {}, 0
lcd = { clear = function(c) CALLS[#CALLS + 1] = "clear" end,
        drawText = function() CALLS[#CALLS + 1] = "text" end, drawLine = function() end, drawRectangle = function() end,
        drawFilledRectangle = function(x, y, w, h, f, o) CALLS[#CALLS + 1] = "fill" end,
        drawBitmap = function() CALLS[#CALLS + 1] = "bitmap" end,
        RGB = function(r, g, b) return r * 65536 + g * 256 + b end, setColor = function() end }
Bitmap = { open = function() return { w = 480, h = 272 } end, getSize = function(b) return b.w, b.h end }
function getTime() return TICKS end
"""
for ver in ("52", "54"):
    lua = importlib.import_module(f"lupa.lua{ver}").LuaRuntime(unpack_returned_tuples=True)
    lua.execute(ENV)
    lua.execute('debug.setmetatable("", nil)')          # like the radio: no string methods
    mod = lua.eval("loadfile")(str(SRC))()
    mod.init()
    kinds = set()
    for page in range(6):
        lua.execute(f"TICKS = {page * 500}; CALLS = {{}}")
        assert mod.run(0) == 0
        kinds |= set(lua.eval("CALLS").values())
        txt = lua.execute("local n = 0 for _, c in ipairs(CALLS) do if c == 'text' then n = n + 1 end end return n")
        assert txt >= 2, f"page {page + 1} drew too little text"
    assert {"fill", "bitmap", "clear", "text"} <= kinds, kinds
    assert mod.run(100) == 2, "Exit must end the tool"
    print(f"[lua{ver}] all 6 pages drew without errors; Exit returns 2")
print("colour test tool passed")

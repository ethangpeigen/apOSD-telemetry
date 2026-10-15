"""Replay a real AX12 app log through the log reader (data.lua, source=log) and check every value it reports.
Usage: python test_reallog.py path/to/YYYY_MM_DD.txt   Prints only pass/fail counts, never positions."""
import importlib, math, re, sys
from pathlib import Path
DATA = Path(__file__).resolve().parents[2] / "SD/SCRIPTS/TOOLS/apOSD/data.lua"
lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
pat = re.compile(r"^(\d\d):(\d\d):(\d\d)\.\d+ voltage:(\S+)v current:(\S+) lat:(\S+) lng:(\S+) pitch:(\S+) roll:(\S+) yaw:(\S+)$")
rows = [pat.match(l) for l in lines]
assert all(rows), "log has lines of an unexpected shape"
ENV = """
CLOCK, NOW, CALLS = 0, 0, 0
function getTime() return NOW end
function getRSSI() return 0 end
function getValue() return 7.9 end
function playTone() end
function getFieldInfo() end
function getDateTime() return { year = 2026, mon = 10, day = 15, hour = CLOCK // 3600 % 24, min = CLOCK // 60 % 60, sec = CLOCK % 60 } end
io = { open = function(p) if p == "/real.txt" then return { pos = 0 } end end,
       seek = function(fh, off) fh.pos = off end,
       read = function(fh, n) local s = VF_READ(fh.pos, n) fh.pos = fh.pos + #s return s end, close = function() end }
"""
for ver in ("53", "54"):                                   # 5.3/5.4 have the // operator used by the clock mock
    ok = bad = 0
    for i in list(range(5, len(lines), 97)) + [len(lines) - 1]:
        content = ("\n".join(lines[: i + 1]) + "\n").encode()
        lua = importlib.import_module(f"lupa.lua{ver}").LuaRuntime(unpack_returned_tuples=True)
        lua.globals().VF_READ = lambda pos, n, c=content: c[int(pos):int(pos) + int(n)].decode("latin-1")
        lua.execute(ENV)
        cfg = lua.eval("{ source = 'log', logFile = '/real.txt', maxAge = 8, imperial = false, cells = 0, cellWarn = 3.5, cellCrit = 3.3, minSats = 6, mgrs = true, mgrsDigits = 3, beeps = false, armSwitch = '' }")
        lua.execute('debug.setmetatable("", nil)')
        d = lua.eval("loadfile")(str(DATA))(cfg)
        m = rows[i]
        t = int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3])
        lua.execute(f"CLOCK = {t + 1}; NOW = 100")          # one second after the line was written
        d.update()
        yaw = float(m[10]); hdg = math.degrees(yaw) % 360
        checks = [d.alive is True, abs(d.v - float(m[4])) < 1e-6, abs(d.a - float(m[5])) < 1e-6,
                  abs(d.hdg - hdg) < 1e-3, abs(d.pitch - math.degrees(float(m[8]))) < 1e-3]
        lat, lng = float(m[6]), float(m[7])
        if lat != 0 and lng != 0: checks.append(d.fix is True and d.mgrs is not None)
        if all(checks): ok += 1
        else: bad += 1; print(f"  line {i}: checks {checks}")
        # the same file seen 30 s later must count as no telemetry
        lua.execute(f"CLOCK = {t + 30}; NOW = 300")
        d.update()
        if d.alive: bad += 1; print(f"  line {i}: stale log still counted as alive")
    print(f"[lua{ver}] real log replay: {ok} sample points correct, {bad} wrong")
    assert bad == 0
print("real log test passed")

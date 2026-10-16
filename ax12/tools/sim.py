"""Mock EdgeTX radio for apOSD: runs the real Lua scripts and renders the LCD to a PNG.

Needs:  pip install lupa pillow
Usage:  python sim.py --screen 480x272 --scenario drive --out shot.png
        python sim.py --screen 128x64 --scenario lowbat --lua 54 --set horizon=true

Font shapes and sizes are approximations of the radio's fonts, so use the output to check
layout and logic, not exact pixels. Test on the EdgeTX Companion simulator or the radio too.
"""
import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SD = Path(__file__).resolve().parent.parent / "SD"
FONTS = Path("C:/Windows/Fonts")

FLAGS = dict(SMLSIZE=0x1, MIDSIZE=0x2, DBLSIZE=0x4, XXLSIZE=0x8, TINSIZE=0x10, INVERS=0x20, BLINK=0x40,
             RIGHT=0x80, CENTER=0x100, SHADOWED=0x200, BOLD=0x400, CUSTOM_COLOR=0x800, FORCE=0x1000,
             ERASE=0x2000, SOLID=0, DOTTED=0x4000)

# colour radios: nominal line height in px per font flag; mono radios: (char pitch, height)
COLOR_H = {0: 18, 0x1: 15, 0x2: 25, 0x4: 34, 0x8: 62, 0x10: 12}
MONO = {0: (6, 8), 0x1: (5, 7), 0x2: (8, 12), 0x4: (10, 16), 0x8: (16, 32), 0x10: (4, 6)}


def font_key(flags):
    for bit in (0x8, 0x4, 0x2, 0x1, 0x10):
        if flags & bit:
            return bit
    return 0


class Screen:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.color = w > 212
        self.custom = 0
        self.fonts = {}
        self.new()

    def new(self, bg=None):
        bg = (255, 255, 255) if bg is None else bg
        self.img = Image.new("RGB", (self.w, self.h), bg)
        self.dr = ImageDraw.Draw(self.img)
        self.dr.fontmode = "1" if not self.color else "L"

    def rgb(self, c):
        return ((c >> 16) & 255, (c >> 8) & 255, c & 255)

    def ink(self, flags):
        if self.color:
            return self.rgb(self.custom) if flags & FLAGS["CUSTOM_COLOR"] else (0, 0, 0)
        return (255, 255, 255) if flags & FLAGS["ERASE"] else (0, 0, 0)

    def font(self, flags):
        k = font_key(flags)
        if k not in self.fonts:
            if self.color:
                self.fonts[k] = ImageFont.truetype(str(FONTS / "arial.ttf"), round(COLOR_H[k] * 0.8))
            else:
                self.fonts[k] = ImageFont.truetype(str(FONTS / "consola.ttf"), round(MONO[k][0] / 0.55))
        return self.fonts[k], k

    def size(self, text, flags):
        f, k = self.font(flags)
        if self.color:
            return f.getlength(text), COLOR_H[k]
        return len(text) * MONO[k][0], MONO[k][1]

    def text(self, x, y, text, flags):
        f, k = self.font(flags)
        w, h = self.size(text, flags)
        if flags & FLAGS["RIGHT"]:
            x -= w
        if flags & FLAGS["CENTER"]:
            x -= w / 2
        fill = self.ink(flags)
        if not self.color and flags & FLAGS["INVERS"]:
            self.dr.rectangle([x - 1, y - 1, x + w, y + h - 1], fill=(0, 0, 0))
            fill = (255, 255, 255)
        self.dr.text((x, y - (1 if not self.color else 0)), text, font=f, fill=fill)


def run(args):
    import importlib
    SD = Path(args.sd).resolve() if args.sd else globals()["SD"]
    W, H = (int(n) for n in args.screen.split("x"))
    lua = importlib.import_module(f"lupa.lua{args.lua}").LuaRuntime(unpack_returned_tuples=True)
    scr = Screen(W, H)
    g = lua.globals()
    g.LCD_W, g.LCD_H, g.SDROOT = W, H, str(SD)
    for k, v in FLAGS.items():
        g[k] = v

    state = dict(sens={}, ticks=0, rssi=100, texts=[])

    def py_has(name):
        return name in state["sens"]

    def py_get(name):
        v = state["sens"].get(name, 0)
        if isinstance(v, tuple):
            return lua.table(lat=v[0], lon=v[1])
        return v

    g.HAS, g.GET = py_has, py_get
    g.STATE = lua.table()

    lcd = lua.table()
    def lcd_clear(*a):
        state["texts"] = []
        col = None
        if a and scr.color and int(a[0] or 0) & FLAGS["CUSTOM_COLOR"]:
            col = scr.rgb(scr.custom)  # lcd.clear(colour): fill the whole screen with it
        scr.new(col or (255, 255, 255))
    lcd["clear"] = lcd_clear
    lcd["RGB"] = lambda r, gg, b: (int(r) << 16) | (int(gg) << 8) | int(b)

    def set_color(which, c):
        scr.custom = int(c)
    lcd["setColor"] = set_color
    lcd["sizeText"] = lambda s, f=0: scr.size(str(s), int(f or 0))
    def draw_text(x, y, s, f=0, *a):
        state["texts"].append(str(s))
        scr.text(round(x), round(y), str(s), int(f or 0))
    lcd["drawText"] = draw_text

    def line(x1, y1, x2, y2, pat=0, f=0):
        if args.rterr == "draw":
            raise RuntimeError("boom while drawing")
        scr.dr.line([round(x1), round(y1), round(x2), round(y2)], fill=scr.ink(int(f or 0)), width=1)
    lcd["drawLine"] = line

    def frect(x, y, w, h, f=0):
        scr.dr.rectangle([round(x), round(y), round(x + w - 1), round(y + h - 1)], fill=scr.ink(int(f or 0)))
    lcd["drawFilledRectangle"] = frect

    def rect(x, y, w, h, f=0):
        scr.dr.rectangle([round(x), round(y), round(x + w - 1), round(y + h - 1)], outline=scr.ink(int(f or 0)))
    lcd["drawRectangle"] = rect

    def bm_open(path):  # like the radio: always returns an object, size 0x0 if the file is missing
        p = SD / str(path).lstrip("/")
        if args.nobg or not p.exists():
            return lua.table(w=0, h=0, path="")
        im = Image.open(p)
        return lua.table(w=im.width, h=im.height, path=str(p))
    g.BMOPEN = bm_open

    def draw_bitmap(bmp, x, y, *a):
        scr.img.paste(Image.open(bmp["path"]).convert("RGB"), (round(x), round(y)))
    lcd["drawBitmap"] = draw_bitmap
    g.lcd = lcd

    overrides = {}
    for kv in args.set or []:
        k, v = kv.split("=", 1)
        overrides[k] = {"true": True, "false": False}.get(v, None)
        if overrides[k] is None:
            try:
                overrides[k] = float(v)
            except ValueError:
                overrides[k] = v
    if args.log:
        overrides["source"] = "log"
    g.CFGO = lua.table(**overrides)
    g.TONES = lua.table()
    g.FAILFILE = args.fail  # make loadScript fail for this file name, like a radio out of memory
    g.RTERR = args.rterr    # crash in "update" (sensor reading) or "draw"
    g.FAILBIN = args.failbin  # simulate a bad cached .luac for this file

    BASE = 22 * 3600 + 5 * 60 + 30            # fake radio clock at the first frame: 22:05:30
    vfile = bytearray()
    def log_line(sec, k):
        h, m, sc = sec // 3600, sec // 60 % 60, sec % 60
        lat, lon = (0, 0) if args.nofix else (38.8895 + 0.00001 * k, -77.0353 + 0.00002 * k)
        return (f"{h:02d}:{m:02d}:{sc:02d}.532 voltage:{11.3 - 0.01 * k:.3g}v current:{3.4 if k % 2 else 3.5:g} "
                f"lat:{lat:.6g} lng:{lon:.6g} pitch:{-0.0064:.6g} roll:{0.00567:.6g} yaw:{0.1336 + 0.001 * k:.6g}\n")
    for k in range(60):                        # one line a second, the newest one --logage seconds before "now"
        vfile += log_line(BASE - args.logage - 59 + k, k).encode()
    state["logk"] = 60
    def vf_exists(path): return args.log and not args.nolog and str(path) == "/2026_10_15.txt"
    def vf_read(path, pos, n): return bytes(vfile[int(pos):int(pos) + int(n)]).decode("latin-1")
    g.VF_EXISTS, g.VF_READ, g.BASESECS = vf_exists, vf_read, BASE
    g.CLOCKSHIFT = args.clockshift * 3600
    g.EPOCH = args.epoch
    lua.execute("""
        function getDateTime()
          local s = BASESECS + CLOCKSHIFT + math.floor(((STATE.ticks or 2000) - 2000) / 100)
          local day = 15 + math.floor(s / 86400)  -- crossing midnight moves the date, like a real clock
          s = s % 86400
          if EPOCH then return { year = 1970, mon = 1, day = 1, hour = math.floor(s / 3600) % 24, min = math.floor(s / 60) % 60, sec = s % 60 } end
          return { year = 2026, mon = 10, day = day, hour = math.floor(s / 3600) % 24, min = math.floor(s / 60) % 60, sec = s % 60 }
        end
        io = { open = function(p, m) if VF_EXISTS(p) then return { path = p, pos = 0 } end return nil end,
               seek = function(fh, off) fh.pos = off end,
               read = function(fh, n) local s = VF_READ(fh.path, fh.pos, n) fh.pos = fh.pos + #s return s end,
               close = function() end }
        function getFieldInfo(n) if HAS(n) then return { id = n } end return nil end
        function getValue(id) return GET(id) end
        function getRSSI()
          if RTERR == "update" then error("boom while reading sensors") end
          return STATE.rssi or 100, 45, 42
        end
        function getTime() return STATE.ticks or 0 end
        function playTone(f, l, p) TONES[#TONES + 1] = f end
        Bitmap = { open = function(p) return BMOPEN(p) end, getSize = function(b) return b.w, b.h end }
        function loadScript(p, mode)
          if FAILFILE and string.find(p, FAILFILE, 1, true) then return nil, "not enough memory" end
          -- a bad cached .luac: the default load fails, a text-only load ("tx") works
          if FAILBIN and string.find(p, FAILBIN, 1, true) and mode == nil then return nil, "bad binary (simulated)" end
          local f = assert(loadfile(SDROOT .. p))
          if string.sub(p, -7) == "cfg.lua" then
            return function() local c = f(); for k, v in pairs(CFGO) do c[k] = v end return c end
          end
          return f
        end
    """)
    if not args.stringmeta:
        # EdgeTX's Lua gives strings no methods: s:sub(...) fails with "attempt to index a string value"
        lua.execute('debug.setmetatable("", nil)')

    g.EVT_VIRTUAL_ENTER, g.EVT_VIRTUAL_ENTER_LONG, g.EVT_EXIT_BREAK = 0x100, 0x101, 0x102
    tool = args.tool or not (SD / "SCRIPTS/TELEMETRY/apOSD.lua").exists()  # AX12 layout: a Tools script
    script = lua.eval("loadfile")(str(SD / ("SCRIPTS/TOOLS/apOSD.lua" if tool else "SCRIPTS/TELEMETRY/apOSD.lua")))()
    count = lua.eval("function() collectgarbage() return (collectgarbage('count')) end")
    mem = lambda: (lambda v: v[0] if isinstance(v, tuple) else v)(count())
    base = mem()
    script.init()
    first = mem()
    for _ in range(args.reinit):  # the radio running init again when the screen is re-entered
        script.init()
    if args.reinit:
        print(f"Lua memory: script uses {first - base:.1f} KB after init (64-bit desktop Lua, so the radio will differ); "
              f"after {args.reinit} more init calls: {mem() - base:.1f} KB")

    frames = args.frames
    for i in range(frames):
        last = i == frames - 1
        sens, rssi = scenario(args.scenario, i, frames)
        state["sens"] = sens
        g.STATE["rssi"] = rssi
        g.STATE["ticks"] = i * 10 + (2000 if args.phase == "on" else 2050)
        if args.log and not args.logage:
            while BASE + (i * 10) // 100 - args.logage >= BASE - args.logage - 59 + state["logk"]:
                vfile += log_line(BASE - args.logage - 59 + state["logk"], state["logk"]).encode(); state["logk"] += 1
        if last:
            for _ in range(args.enter):  # ENTER key presses before the final frame
                script.run(0x100)
            for _ in range(max(0, args.settle - 1)):  # extra frames, e.g. so the map page can load its tiles one by one
                script.run(0)
            script.run(0)
            if args.exit:
                g.EVT_EXIT_BREAK_MOCK = 0x102
                print(f"run(EXIT) returned {script.run(0x102)}")
        elif script.background:  # telemetry scripts run in the background between screens
            script.background()
        else:  # tool scripts have no background(): they simply keep running
            script.run(0)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    scale = 4 if not scr.color else args.scale
    img = scr.img
    if not scr.color:  # LCD look
        img = img.convert("L").point(lambda p: 0 if p < 128 else 255).convert("RGB")
        img = Image.eval(img, lambda p: p)
        px = img.load()
        for yy in range(img.height):
            for xx in range(img.width):
                px[xx, yy] = (28, 36, 30) if px[xx, yy][0] == 0 else (178, 196, 170)
    img = img.resize((W * scale, H * scale), Image.NEAREST)
    img.save(out)
    tones = [int(t) for t in g.TONES.values()]
    shown = state["texts"]
    if shown and shown[0].startswith("apOSD error"):
        print(f"{out.name}: ERROR SCREEN SHOWN: {' '.join(shown[1:])}")
    else:
        print(f"{out.name}: ok, tones played: {tones}")
    for want in args.expect or []:
        if want not in shown:
            print(f"   EXPECTED TEXT NOT ON SCREEN: {want!r}   (drawn: {shown})")
            raise SystemExit(3)
        print(f"   found on screen: {want!r}")


def scenario(name, i, n):
    """Sensor values per frame. Frames 0-5 are disarmed at 'home'; the last frame is ~70 m away."""
    home = (52.0000, -1.0000)
    far = (52.0005, -0.9993)
    s = {
        "RxBt": 7.62, "Curr": 3.4, "Capa": 412, "Bat%": 78, "Sats": 14, "GSpd": 12.4, "Alt": 31.0,
        "Yaw": math.radians(40), "Hdg": 41, "Ptch": math.radians(4), "Roll": math.radians(-8),
        "FM": "HOLD", "RQly": 100, "1RSS": -48, "TPWR": 100, "tx-voltage": 7.9,
    }
    rssi = 100
    pos = home if i < 6 else tuple(h + (f - h) * (i - 6) / (n - 7) for h, f in zip(home, far))
    if name == "wash":  # parked at the Washington Monument: MGRS 18S UJ 23478 06483
        pos = (38.8895, -77.0353)
    s["GPS"] = pos
    if name == "drive":
        s["FM"] = "HOLD*" if i < 6 else "AUTO"
    elif name == "wash":
        s["FM"] = "HOLD*" if i < 6 else "AUTO"
    elif name == "disarmed":
        s["FM"] = "HOLD*"
        s["GSpd"] = 0
    elif name == "nostar":  # ArduPilot with the '*' option left off
        s["FM"] = "MANU"
    elif name == "lowbat":
        s["FM"] = "HOLD*" if i < 6 else "RTL"
        s["RxBt"] = 6.5
    elif name == "warnbat":
        s["FM"] = "HOLD*" if i < 6 else "MANU"
        s["RxBt"] = 6.9
    elif name == "nolink":
        s["FM"] = "HOLD*" if i < 6 else "HOLD"
        rssi = 0 if i == n - 1 else 100
    elif name == "nogps":
        s["FM"] = "HOLD*" if i < 6 else "HOLD"
        s["Sats"] = 3
    elif name == "tilt":
        s["FM"] = "HOLD*" if i < 6 else "MANU"
        s["Ptch"], s["Roll"] = math.radians(12), math.radians(-25)
    elif name == "north":  # heading near 0/360 to check tape wrap
        s["FM"] = "HOLD*" if i < 6 else "MANU"
        s["Yaw"] = math.radians(-4)
    elif name == "fast":
        s["FM"] = "HOLD*" if i < 6 else "MANU"
        s["GSpd"] = 48.7
        s["Curr"] = 24.6
        s["Capa"] = 2840
    else:
        raise SystemExit(f"unknown scenario {name}")
    return s, rssi


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", default="480x272")
    ap.add_argument("--scenario", default="drive")
    ap.add_argument("--lua", default="52", choices=["52", "53", "54"])
    ap.add_argument("--set", action="append", help="override a cfg.lua value, e.g. horizon=true")
    ap.add_argument("--phase", default="on", choices=["on", "off"], help="blink phase for the shot")
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--nobg", action="store_true", help="pretend the background PNG is missing")
    ap.add_argument("--fail", help="make loading this file fail, e.g. data.lua (simulates out of memory)")
    ap.add_argument("--sd", help="use this folder as the radio's SD card instead of ../SD")
    ap.add_argument("--tool", action="store_true", help="run the launcher from SCRIPTS/TOOLS (AX12 style) instead of SCRIPTS/TELEMETRY")
    ap.add_argument("--exit", action="store_true", help="press EXIT after the last frame and report what run() returns")
    ap.add_argument("--settle", type=int, default=1, help="draw this many frames after the key presses")
    ap.add_argument("--enter", type=int, default=0, help="press ENTER this many times before the last frame")
    ap.add_argument("--expect", action="append", help="exit with an error unless this exact text is drawn on the last frame")
    ap.add_argument("--log", action="store_true", help="AX12 log source: fake the app's log file (source=log)")
    ap.add_argument("--logage", type=int, default=0, help="--log: how many seconds old the newest log line is")
    ap.add_argument("--nolog", action="store_true", help="--log: the log file does not exist")
    ap.add_argument("--frames", type=int, default=12, help="how many frames to run (10 ticks each) before the picture")
    ap.add_argument("--epoch", action="store_true", help="--log: the radio's Lua clock is not set and reports 1970-01-01")
    ap.add_argument("--clockshift", type=int, default=0, metavar="HOURS",
                    help="--log: the radio's Lua clock differs from the app's log clock by this many hours (e.g. -8 for UTC vs UTC+8)")
    ap.add_argument("--nofix", action="store_true", help="--log: the log lines carry lat/lng 0 (no GPS fix)")
    ap.add_argument("--stringmeta", action="store_true", help="allow s:sub() style calls (the real radio does NOT)")
    ap.add_argument("--failbin", help="simulate a bad cached .luac for this file; the text-only retry should recover")
    ap.add_argument("--rterr", choices=["update", "draw"], help="inject a crash while reading sensors or drawing")
    ap.add_argument("--reinit", type=int, default=0, help="call init() this many extra times and report memory")
    ap.add_argument("--out", default="out/shot.png")
    run(ap.parse_args())

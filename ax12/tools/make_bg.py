"""Make the optional apOSD background picture for the RadioMaster AX12 (480x272).

The source is fitted inside the screen (never cropped), centred on black and darkened so the
OSD text stays readable on top of it. The file is written as b.png because this radio failed to open
the longer name bg_480x272.png (short names work).

Usage:  python make_bg.py --src my_picture.jpg [--dim 0.30]
Writes: ../SD/SCRIPTS/TOOLS/apOSD/b.png
Needs:  pip install pillow
"""
import argparse
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
W, H = 480, 272  # the AX12's Lua canvas

ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True, help="the picture to use as background (only use pictures you may use)")
ap.add_argument("--dim", type=float, default=0.30, help="brightness 0-1 (lower = darker)")
ap.add_argument("--out", default=str(HERE.parent / "SD" / "SCRIPTS" / "TOOLS" / "apOSD"))
args = ap.parse_args()

src = Image.open(args.src).convert("L")
scale = min(W / src.width, H / src.height)
fit = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
fit = fit.point(lambda p: round(p * args.dim))
canvas = Image.new("L", (W, H), 0)
canvas.paste(fit, ((W - fit.width) // 2, (H - fit.height) // 2))
Path(args.out).mkdir(parents=True, exist_ok=True)
path = Path(args.out) / "b.png"
canvas.convert("RGB").save(path, optimize=True)
print(f"{path.name}: {path.stat().st_size // 1024} KB")

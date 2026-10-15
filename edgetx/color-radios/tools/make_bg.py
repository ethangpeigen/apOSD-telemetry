"""Make the apOSD background pictures, one PNG per colour-radio screen size.

The source is fitted inside the screen (never cropped), centred on black and darkened so the
OSD text stays readable on top of it.

Usage:  python make_bg.py --src my_picture.jpg [--dim 0.30]
Writes: ../SD/SCRIPTS/TELEMETRY/apOSD/bg_<W>x<H>.png
Needs:  pip install pillow
"""
import argparse
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SIZES = [(480, 272), (480, 320), (800, 480), (320, 480)]  # TX16S, TX15, TX16S Mk3, NV14

ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True, help="the picture to use as background")
ap.add_argument("--dim", type=float, default=0.30, help="brightness 0-1 (lower = darker)")
ap.add_argument("--out", default=str(HERE.parent / "SD" / "SCRIPTS" / "TELEMETRY" / "apOSD"))
args = ap.parse_args()

src = Image.open(args.src).convert("L")
for w, h in SIZES:
    scale = min(w / src.width, h / src.height)
    fit = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
    fit = fit.point(lambda p: round(p * args.dim))
    canvas = Image.new("L", (w, h), 0)
    canvas.paste(fit, ((w - fit.width) // 2, (h - fit.height) // 2))
    # RGB PNG: the most widely supported flavour on the radios
    Path(args.out).mkdir(parents=True, exist_ok=True)
    path = Path(args.out) / f"bg_{w}x{h}.png"
    canvas.convert("RGB").save(path, optimize=True)
    print(f"{path.name}: {path.stat().st_size // 1024} KB")

"""Make an offline map pack for the apOSD map page.

Tiles are standard web-map tiles (256 px, XYZ scheme) saved as <z>_<x>_<y>.jpg in the output folder, which you
copy to the radio next to the apOSD folder (AX12: AX12LUA/SCRIPTS/TOOLS/mp, EdgeTX: SD card SCRIPTS/TELEMETRY/mp).

  python make_map.py --demo --center 38.8895 -77.0353 --radius 1500 --zooms 16 17 18 --out ../mp
      Draws a SYNTHETIC test map (grid, fake roads). Needs no internet and no tile provider.

  python make_map.py --url "https://YOUR-TILE-SERVER/{z}/{x}/{y}.png" --center LAT LON --radius 1500 --zooms 16 17 --out ../mp
      Downloads tiles from a source YOU choose. You are responsible for that provider's terms: for example the public
      OpenStreetMap tile servers forbid bulk downloads, and most satellite imagery needs a licence or API key.
      The script is polite (one request at a time, a pause between them, a tile-count limit, your own User-Agent).

Needs: pip install pillow   (and the standard library for downloading)
"""
import argparse
import math
import time
import urllib.error
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw


def deg2tile(lat, lon, z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def tiles_for(lat, lon, radius_m, z):
    """All tiles whose area touches a square of +/- radius_m around the centre."""
    dlat = radius_m / 111320
    dlon = radius_m / (111320 * math.cos(math.radians(lat)))
    x0, y1 = deg2tile(lat - dlat, lon - dlon, z)
    x1, y0 = deg2tile(lat + dlat, lon + dlon, z)
    return [(int(x), int(y)) for x in range(int(x0), int(x1) + 1) for y in range(int(y0), int(y1) + 1)]


def demo_tile(z, x, y):
    """A synthetic map tile. Roads and blocks depend only on world position, so neighbouring tiles line up."""
    im = Image.new("RGB", (256, 256), (222, 226, 214))
    dr = ImageDraw.Draw(im)
    scale = 2 ** (z - 16)                      # features keep the same real-world size at every zoom
    step = int(64 * scale)
    for k in range(0, 256, max(8, step)):      # blocks
        for axis in (0, 1):
            wx, wy = x * 256 + k, y * 256 + k
            road = (wx if axis == 0 else wy) // max(8, step) % 3 == 0
            col, wd = ((250, 250, 250), max(2, int(5 * scale))) if road else ((205, 210, 198), 1)
            dr.line([(k, 0), (k, 255)] if axis == 0 else [(0, k), (255, k)], fill=col, width=wd)
    dr.rectangle([0, 0, 255, 255], outline=(150, 156, 142))
    dr.text((6, 6), f"DEMO z{z} {x}/{y}", fill=(90, 96, 84))
    return im


def fetch(url, user_agent, tries=3):
    """One tile as an image; None if the server says it has none (404); retries other errors a few times."""
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": user_agent})
            with urllib.request.urlopen(req, timeout=30) as r:
                return Image.open(BytesIO(r.read())).convert("RGB")
        except urllib.error.HTTPError as e:
            if e.code in (400, 404):
                return None
            err = e
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            err = e
        time.sleep(2 * (k + 1))
    raise SystemExit(f"giving up on {url}: {err}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--center", nargs=2, type=float, metavar=("LAT", "LON"), required=True)
    ap.add_argument("--radius", type=float, default=1500, help="metres around the centre (default 1500)")
    ap.add_argument("--zooms", nargs="+", type=int, default=[16, 17, 18])
    ap.add_argument("--out", required=True)
    ap.add_argument("--demo", action="store_true", help="draw synthetic tiles instead of downloading")
    ap.add_argument("--url", help="tile URL template with {z} {x} {y}, from a source you may use")
    ap.add_argument("--user-agent", default="apOSD-map-tool (personal use)")
    ap.add_argument("--delay", type=float, default=0.5, help="seconds between downloads")
    ap.add_argument("--max-tiles", type=int, default=1500)
    ap.add_argument("--quality", type=int, default=80)
    a = ap.parse_args()
    if not a.demo and not a.url:
        ap.error("give --demo, or --url with a tile source you are allowed to use")
    lat, lon = a.center
    plan = [(z, x, y) for z in a.zooms for x, y in tiles_for(lat, lon, a.radius, z)]
    print(f"{len(plan)} tiles for zooms {a.zooms}")
    if len(plan) > a.max_tiles:
        raise SystemExit(f"more than --max-tiles ({a.max_tiles}): lower --radius or --zooms (or raise the limit on purpose)")
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    missing = 0
    for i, (z, x, y) in enumerate(plan, 1):
        path = out / f"{z}_{x}_{y}.jpg"
        if path.exists():
            continue
        if a.demo:
            im = demo_tile(z, x, y)
        else:
            im = fetch(a.url.format(z=z, x=x, y=y), a.user_agent)
            time.sleep(a.delay)
            if im is None:  # the provider has no tile there (open water, outside its coverage): leave a gap
                missing += 1
                continue
        im.convert("RGB").resize((256, 256)).save(path, "JPEG", quality=a.quality, optimize=False, progressive=False)
        if i % 25 == 0 or i == len(plan):
            print(f"  {i}/{len(plan)}")
    total = sum(f.stat().st_size for f in out.glob("*.jpg"))
    print(f"done: {len(list(out.glob('*.jpg')))} tiles, {total // 1024} KB in {out}" + (f" ({missing} not available from the provider)" if missing else ""))


if __name__ == "__main__":
    main()

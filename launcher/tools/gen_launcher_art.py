#!/usr/bin/env python3
"""Art of the game launcher window (O339), made from the brand logo (docs/brand/).

  python3 -I launcher/tools/gen_launcher_art.py [--check] [--preview PNG]

Writes raw RGBA (no header; the size is fixed below and in launcher/src/art.rs), embedded with include_bytes!:
  launcher/assets/banner.rgba   960x300  hero strip: warm black, an ember glow, seeded sparks, the logo, a fade
                                         into the window colour at the bottom
  launcher/assets/icon.rgba     128x128  window icon (the brand icon)
No new art: only the brand logo, a gradient and seeded sparks. --check: fail when a file is missing or its mean
pixel difference from a fresh render is above 2 of 255 (resampling differs a little between Pillow versions).
--preview PNG: also save the banner as a PNG to look at.
"""
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "docs" / "brand" / "cinders_logo.png"
ICON = ROOT / "docs" / "brand" / "cinders_logo_icon.png"
OUT = ROOT / "launcher" / "assets"
BW, BH = 960, 300
IW = 128
BG = (14, 11, 10)  # the window colour of launcher/src/theme.rs (BG); the banner fades into it
TOL = 2.0


def banner():
    y, x = np.mgrid[0:BH, 0:BW].astype(np.float32)
    base = np.zeros((BH, BW, 3), np.float32)
    base[:] = BG
    # ember glow behind the logo, a second low one at the bottom
    d = np.sqrt(((x - BW / 2) / (BW * 0.42)) ** 2 + ((y - BH * 0.5) / (BH * 0.62)) ** 2)
    glow = np.clip(1.0 - d, 0, 1) ** 2.2
    base += glow[..., None] * np.array([120, 38, 10], np.float32)
    d2 = np.sqrt(((x - BW / 2) / (BW * 0.7)) ** 2 + ((y - BH * 1.05) / (BH * 0.45)) ** 2)
    base += (np.clip(1.0 - d2, 0, 1) ** 2)[..., None] * np.array([60, 18, 6], np.float32)
    # sparks
    rnd = random.Random(339)
    spark = np.zeros((BH, BW, 3), np.float32)
    for _ in range(120):
        sx, sy = rnd.uniform(0, BW), rnd.uniform(0, BH)
        r = rnd.choice((0.8, 1.0, 1.4, 1.8))
        a = rnd.uniform(0.25, 1.0) * (0.4 + 0.6 * (sy / BH))  # more at the bottom, like rising embers
        col = rnd.choice(((255, 150, 40), (255, 110, 30), (255, 200, 90)))
        dd = np.sqrt((x - sx) ** 2 + (y - sy) ** 2)
        k = np.clip(1.0 - dd / (r * 2.2), 0, 1) ** 1.5 * a
        for c in range(3):
            spark[..., c] += k * col[c]
    rgb = base + spark * 0.9
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")
    logo = Image.open(LOGO).convert("RGBA")
    # crop to the visible part, then fit the strip height
    box = logo.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    logo = logo.crop(box)
    h = 262
    w = round(logo.width * h / logo.height)
    logo = logo.resize((w, h), Image.LANCZOS)
    img.alpha_composite(logo, ((BW - w) // 2, 6))
    arr = np.asarray(img, np.float32)[..., :3]
    # fade into the window colour: bottom 70 px, and the left and right edges
    fade = np.ones((BH, BW), np.float32)
    fade *= np.clip((BH - 1 - y) / 70.0, 0, 1)
    fade *= np.clip(np.minimum(x, BW - 1 - x) / 90.0, 0, 1)
    arr = arr * fade[..., None] + np.array(BG, np.float32) * (1 - fade[..., None])
    out = np.dstack([np.clip(arr, 0, 255), np.full((BH, BW), 255.0)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def icon():
    return Image.open(ICON).convert("RGBA").resize((IW, IW), Image.LANCZOS)


def files():
    return {"banner.rgba": banner(), "icon.rgba": icon()}


def main():
    argv = sys.argv[1:]
    made = files()
    if "--preview" in argv:
        made["banner.rgba"].save(argv[argv.index("--preview") + 1])
    if "--check" in argv:
        bad = False
        for name, im in made.items():
            p = OUT / name
            want = np.asarray(im, np.int16)
            if not p.is_file() or p.stat().st_size != want.size:
                print("FAIL %s missing or wrong size" % p.relative_to(ROOT))
                bad = True
                continue
            got = np.frombuffer(p.read_bytes(), np.uint8).reshape(want.shape).astype(np.int16)
            diff = float(np.abs(got - want).mean())
            if diff > TOL:
                print("FAIL %s differs from a fresh render (mean %.2f)" % (p.relative_to(ROOT), diff))
                bad = True
        print("launcher art: %s" % ("stale" if bad else "ok"))
        return 1 if bad else 0
    OUT.mkdir(parents=True, exist_ok=True)
    for name, im in made.items():
        (OUT / name).write_bytes(im.tobytes())
        print("wrote launcher/assets/" + name)
    return 0


if __name__ == "__main__":
    sys.exit(main())

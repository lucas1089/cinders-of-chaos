#!/usr/bin/env python3
"""Art of the desktop admin window (O344), made from the brand icon (docs/brand/).

  python3 -I desktop/tools/gen_admin_art.py [--check] [--preview PNG]

Writes raw RGBA (no header; the sizes are fixed below and in desktop/src/theme.rs), embedded with include_bytes!:
  desktop/assets/icon.rgba     128x128   window icon and header icon (the brand icon)
  desktop/assets/header.rgba   1280x64   slim header strip: warm black, a low ember glow on the left, seeded sparks,
                                         faded into the window colour on the right and at the bottom
No new art: only the brand icon, a gradient and seeded sparks. Same palette as launcher/tools/gen_launcher_art.py.
--check: fail when a file is missing or its mean pixel difference from a fresh render is above 2 of 255
(resampling differs a little between Pillow versions). --preview PNG: also save the header as a PNG to look at.
"""
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ICON = ROOT / "docs" / "brand" / "cinders_logo_icon.png"
OUT = ROOT / "desktop" / "assets"
HW, HH = 1280, 64
IW = 128
BG = (14, 11, 10)  # the window colour of desktop/src/theme.rs (BG); the header fades into it
TOL = 2.0


def header():
    y, x = np.mgrid[0:HH, 0:HW].astype(np.float32)
    base = np.zeros((HH, HW, 3), np.float32)
    base[:] = BG
    # low ember glow behind the icon, a long dim one along the bottom edge
    d = np.sqrt(((x - 40) / 420.0) ** 2 + ((y - HH * 0.6) / (HH * 1.1)) ** 2)
    base += (np.clip(1.0 - d, 0, 1) ** 2.0)[..., None] * np.array([96, 30, 8], np.float32)
    d2 = np.sqrt(((x - HW * 0.35) / (HW * 0.6)) ** 2 + ((y - HH * 1.3) / (HH * 0.9)) ** 2)
    base += (np.clip(1.0 - d2, 0, 1) ** 2)[..., None] * np.array([46, 14, 4], np.float32)
    rnd = random.Random(344)
    spark = np.zeros((HH, HW, 3), np.float32)
    for _ in range(46):
        sx, sy = rnd.uniform(0, HW * 0.8), rnd.uniform(0, HH)
        r = rnd.choice((0.7, 0.9, 1.2, 1.5))
        a = rnd.uniform(0.2, 0.9) * (0.35 + 0.65 * (sy / HH)) * max(0.15, 1.0 - sx / (HW * 0.8))
        col = rnd.choice(((255, 150, 40), (255, 110, 30), (255, 200, 90)))
        dd = np.sqrt((x - sx) ** 2 + (y - sy) ** 2)
        k = np.clip(1.0 - dd / (r * 2.2), 0, 1) ** 1.5 * a
        for c in range(3):
            spark[..., c] += k * col[c]
    rgb = base + spark * 0.9
    fade = np.clip((HW - 1 - x) / 380.0, 0, 1) * np.clip((HH - 1 - y) / 14.0, 0, 1)
    rgb = rgb * fade[..., None] + np.array(BG, np.float32) * (1 - fade[..., None])
    out = np.dstack([np.clip(rgb, 0, 255), np.full((HH, HW), 255.0)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def icon():
    return Image.open(ICON).convert("RGBA").resize((IW, IW), Image.LANCZOS)


def files():
    return {"icon.rgba": icon(), "header.rgba": header()}


def main():
    argv = sys.argv[1:]
    made = files()
    if "--preview" in argv:
        made["header.rgba"].save(argv[argv.index("--preview") + 1])
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
        print("desktop art: %s" % ("stale" if bad else "ok"))
        return 1 if bad else 0
    OUT.mkdir(parents=True, exist_ok=True)
    for name, im in made.items():
        (OUT / name).write_bytes(im.tobytes())
        print("wrote desktop/assets/" + name)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Emission masks of the front-art test sprites (Unity front-art scene).

For every Resources/FrontArt/<figure>/<dir>.png it writes <dir>_e.png: a grey mask, white where the picture glows.
FrontArtSprite.shader adds the masked colour as light, so the glow ignores the night and feeds the bloom.

What glows:
- cool cyan pixels (the skeleton's eyes);
- the warm flame: bright orange to yellow pixels within 7 pixels of the densest cluster of near-white flame cores
  (the staff top; the robe trim is warm too, but has no dense core cluster);
- warm sparks that stand mostly alone in empty space (embers around the flame).

Usage: python3 -I unity/tools/gen_front_art_emission.py [--check]
--check: exit 1 when a mask on disk differs from what the rule gives.
"""
import colorsys
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Client", "Assets", "Chaos", "Unity", "Resources", "FrontArt")
DIRS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
FLAME_RADIUS2 = 49     # squared pixels around the flame centre
CORE_RADIUS2 = 25      # squared pixels for the core cluster count
MIN_CORES = 5          # fewer cores near the best one: no flame in this picture


def classify(r, g, b):
    """'c' cool glow, 'core' flame core, 'w' warm, None plain."""
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if 0.42 < h < 0.6 and s > 0.35 and v > 0.65:
        return "c"
    if (h < 0.17 or h > 0.95) and s > 0.45 and v > 0.7:
        return "core" if (v > 0.95 and g > 0.6 * r) else "w"
    return None


def mask(im):
    """The set of glowing (x, y) pixels of an RGBA picture."""
    px = im.load()
    w, h = im.size
    cand = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            k = classify(r, g, b)
            if k:
                cand[(x, y)] = k
    keep = {p for p, k in cand.items() if k == "c"}
    cores = [p for p, k in cand.items() if k == "core"]

    def near(p, q, r2):
        return (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 <= r2

    if cores:
        best = max(cores, key=lambda p: (sum(1 for q in cores if near(p, q, CORE_RADIUS2)), -p[1], -p[0]))
        if sum(1 for q in cores if near(best, q, CORE_RADIUS2)) >= MIN_CORES:
            keep |= {p for p, k in cand.items() if k != "c" and near(p, best, FLAME_RADIUS2)}

    def opaque(x, y):
        return 0 <= x < w and 0 <= y < h and px[x, y][3] >= 128

    for (x, y), k in cand.items():
        if k == "c":
            continue
        empty = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and not opaque(x + dx, y + dy))
        if empty >= 5:
            keep.add((x, y))
    return keep


def build(path):
    im = Image.open(path).convert("RGBA")
    out = Image.new("L", im.size, 0)
    opx = out.load()
    for p in mask(im):
        opx[p] = 255
    return out


def main(argv):
    check = "--check" in argv
    bad = 0
    count = 0
    for fig in sorted(os.listdir(ROOT)):
        d = os.path.join(ROOT, fig)
        if not os.path.isdir(d) or fig.startswith("pk_"):   # the pack monsters: front_art_packs.py makes their masks
            continue
        for name in DIRS:
            src = os.path.join(d, name + ".png")
            if not os.path.exists(src):
                continue
            dst = os.path.join(d, name + "_e.png")
            m = build(src)
            count += 1
            if check:
                if not os.path.exists(dst) or Image.open(dst).convert("L").tobytes() != m.tobytes():
                    print("stale: " + os.path.relpath(dst, ROOT))
                    bad += 1
            else:
                m.save(dst, optimize=True)
    print("%d masks %s" % (count, "checked" if check else "written"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
# Kept as the record of how the approved style sample (lich_soul_drain) was made: it ran in the sample's own work
# folder. gen_necro_fx.py build rebuilds the effect from soul_drain_paint.png (the one repaint it produced).
"""One PixelLab Edit images (Pro) repaint of the Soul Drain strip (8 frames, 512x64). Logs the balance."""
import json
import os
import random
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, "/home/user/project-chaos/client/tools/art_studio/kit")
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
import pixellab  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(HERE, "work")
LOG = os.path.join(WORK, "pixellab_log.txt")

PROMPT = """Improve and refine the texture quality of this existing pixel-art magic effect animation strip: 8 frames left to right, each 64x64, a dark-fantasy necromancer spell "Soul Drain".

Do NOT redesign it.
Do NOT move, resize or add shapes. Keep every frame in its own 64x64 cell, in the same place.

THE FRAMES:
1-2. a violet arcane rune circle draws itself on the ground; 3-4. sickly green soul wisps rise from the circle and spiral inward and upward; 5. they meet in a bright green-white soul orb; 6. the orb bursts with violet rays; 7. a pale ghost skull with glowing green eye sockets in a violet halo; 8. the skull fades, sparkles drift.

STYLE:
Tibia-style 45-degree oblique top-down 2.5D game effect. Light from the upper-left. Glowing arcane violet and sickly soul-green light, white-hot cores, small sparkles, rune marks, swirling wisps with bright heads and tapering trails. Thin dark violet or dark green outline around glowing shapes, not pure black.

PIXEL ART QUALITY:
Crisp fantasy game sprite effect, hue-shifted shading, readable pixel clusters. No blur, no smooth gradients, no anti-aliasing, no background.
"""


def log(msg):
    print(msg)
    with open(LOG, "a") as f:
        f.write(msg + "\n")


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    F = np.load(os.path.join(WORK, "soul_drain.npz"))["frames"]
    strip = np.concatenate(list(F), 1)
    Image.fromarray(strip, "RGBA").save(os.path.join(WORK, "fx_input.png"))
    log("effect: balance before %s" % json.dumps(pixellab.balance()))
    d = os.path.join(WORK, "fx_edit")
    os.makedirs(d, exist_ok=True)
    k0 = len([f for f in os.listdir(d) if f.startswith("v")]) + 1
    for k in range(k0, k0 + n):
        imgs = pixellab.edit_image_pro(strip, PROMPT, seed=random.randint(1, 2 ** 30), label="fx v%d" % k)
        for i, a in enumerate(imgs):
            Image.fromarray(a, "RGBA").save(os.path.join(d, "v%d_%d.png" % (k, i)))
        log("effect: call v%d -> %d image(s), %s" % (k, len(imgs), [a.shape for a in imgs]))
    log("effect: balance after %s" % json.dumps(pixellab.balance()))


if __name__ == "__main__":
    main()

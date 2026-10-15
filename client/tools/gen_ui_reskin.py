#!/usr/bin/env python3
"""Recolour the base client's UI textures to the Chaos palette.

usage: python3 gen_ui_reskin.py <base-client-dir> [overlay-dir] [--dry-run]

The stock interface is grey stone. Every grey pixel of the chrome textures (windows, mini windows, panels,
buttons, scroll bars, tabs, console, action bar, inventory, minimap frame...) is mapped by its brightness onto
the Chaos palette (blackened iron -> dried blood -> bronze -> parchment). Saturated pixels (item and skill
icons, health/mana bars, flags) keep their colour, and size, alpha and layout of every file stay the same, so
no .otui has to change. The results are written to <overlay>/data/images/<same path> and replace the base files
when the client is assembled. Files the overlay already provides (our own art) are never touched.

Which files: everything under images/ui, images/common_buttons, images/skin, images/options and
images/optionstab, plus the images/game files that the stock styles (data/styles) and the core game
interface modules reference. Deterministic; needs Pillow and numpy.
"""
import os
import re
import sys

import numpy as np
from PIL import Image

# brightness -> colour stops
STOPS = [
    (0.00, (6, 4, 5)),        # blackened iron
    (0.18, (20, 11, 12)),
    (0.35, (42, 20, 18)),     # dried blood
    (0.55, (88, 44, 32)),
    (0.75, (150, 98, 62)),    # bronze
    (1.00, (236, 214, 178)),  # parchment
]
GAMMA = 1.15
SAT_LOW, SAT_RANGE = 0.12, 0.18  # below SAT_LOW: fully recoloured; above SAT_LOW+SAT_RANGE: untouched

WHOLE_DIRS = ['ui', 'common_buttons', 'skin', 'options', 'optionstab']
# modules whose /images/game references are interface chrome
CHROME_MODULES = ['game_interface', 'game_console', 'game_inventory', 'game_minimap', 'game_skills',
                  'game_actionbar', 'game_containers', 'game_healthinfo', 'client_topmenu', 'game_topbar',
                  'game_battle', 'game_viplist', 'game_mainpanel', 'game_sidebars']
# English words baked into a texture, erased (each box filled with its most common colour): base patch 0054 draws
# them as tr() labels, so pt-BR shows them translated. (x0, y0, x1, y1), x1/y1 exclusive.
TEXT_FREE = {
    'ui/schedule.png': [(1, 1, 111, 15), (113, 1, 225, 15)],  # the login Event Schedule heads "Active", "Upcoming"
}
REF = re.compile(r'/images/([A-Za-z0-9_/.\- ]+?)(?:\.png)?(?=[\s\'")\],;]|$)')

_XS = np.array([s[0] for s in STOPS])
_CH = [np.array([s[1][c] for s in STOPS], dtype=np.float64) for c in range(3)]


def recolor(rgba):
    rgb = rgba[..., :3].astype(np.float64) / 255.0
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    lum = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]) ** GAMMA
    mapped = np.stack([np.interp(lum, _XS, _CH[c]) for c in range(3)], -1) / 255.0
    w = np.clip(1.0 - (sat - SAT_LOW) / SAT_RANGE, 0, 1)[..., None]
    out = rgba.copy()
    out[..., :3] = (np.clip(mapped * w + rgb * (1 - w), 0, 1) * 255).round().astype(np.uint8)
    return out, float((w[..., 0] * (rgba[..., 3] > 0)).sum())


def erase_text(rgba, boxes):
    """each box filled with the colour it holds most (the band behind the text)"""
    out = rgba.copy()
    for x0, y0, x1, y1 in boxes:
        region = out[y0:y1, x0:x1].reshape(-1, out.shape[-1])
        colours, counts = np.unique(region, axis=0, return_counts=True)
        out[y0:y1, x0:x1] = colours[counts.argmax()]
    return out


def wanted_files(base):
    images = os.path.join(base, 'data', 'images')
    files = set()
    for d in WHOLE_DIRS:
        for root, _, names in os.walk(os.path.join(images, d)):
            for n in names:
                if n.lower().endswith('.png'):
                    files.add(os.path.relpath(os.path.join(root, n), images))
    sources = [os.path.join(base, 'data', 'styles')]
    for m in CHROME_MODULES:
        for top in ('modules', 'mods'):
            sources.append(os.path.join(base, top, m))
    for src in sources:
        for root, _, names in os.walk(src):
            for n in names:
                if not n.endswith(('.otui', '.lua')):
                    continue
                text = open(os.path.join(root, n), encoding='utf-8', errors='ignore').read()
                for ref in REF.findall(text):
                    rel = ref.strip() + '.png'
                    if rel.startswith('game/') and os.path.isfile(os.path.join(images, rel)):
                        files.add(rel)
    return sorted(files)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    dry = '--dry-run' in sys.argv
    base = os.path.abspath(args[0])
    here = os.path.dirname(os.path.abspath(__file__))
    overlay = os.path.abspath(args[1] if len(args) > 1 else os.path.join(here, '..', 'overlay'))
    images = os.path.join(base, 'data', 'images')
    out_images = os.path.join(overlay, 'data', 'images')
    written = skipped = 0
    total = 0
    for rel in wanted_files(base):
        dst = os.path.join(out_images, rel)
        # our own art in the overlay wins; files this tool wrote itself are listed in RESKIN_FILES.txt
        if os.path.exists(dst) and rel not in previously_generated(overlay):
            skipped += 1
            continue
        im = Image.open(os.path.join(images, rel)).convert('RGBA')
        arr, touched = recolor(np.array(im))
        if touched < 1:
            continue
        arr = erase_text(arr, TEXT_FREE.get(rel.replace(os.sep, '/'), ()))
        written += 1
        if not dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            Image.fromarray(arr, 'RGBA').save(dst, optimize=True)
            total += os.path.getsize(dst)
        generated.add(rel)
    if not dry:
        with open(list_path(overlay), 'w') as f:
            f.write('# written by client/tools/gen_ui_reskin.py; regenerate instead of editing these files\n')
            for rel in sorted(generated):
                f.write(rel + '\n')
    print('%s%d textures recoloured (%.1f MB), %d kept from the overlay'
          % ('[dry-run] ' if dry else '', written, total / 1e6, skipped))


generated = set()
_previous = None


def list_path(overlay):
    return os.path.join(overlay, 'data', 'images', 'RESKIN_FILES.txt')


def previously_generated(overlay):
    global _previous
    if _previous is None:
        _previous = set()
        p = list_path(overlay)
        if os.path.isfile(p):
            _previous = {l.strip() for l in open(p) if l.strip() and not l.startswith('#')}
    return _previous


if __name__ == '__main__':
    main()

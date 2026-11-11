#!/usr/bin/env python3
"""Gem looks: the seven socket gems (server/data/lib/chaos_gems_config.lua) in five qualities each, animated.

The first looks (pairs 25 to 62) were built from the owner's Drive gem set (2026-10-14) and recoloured; pair 63 (O480)
replaced them with new art, so that set is no longer read here (docs/CREDITS.md keeps its entry).

New art (owner 2026-11-11, translated: "They are very ugly. Make new ones please."; then, on a sheet of seven styles: "It
can be A, but on the perfect use C.", A a cut jewel, C a jewel set in gold): 35 pixel art cells of 32 px made with the
tool named in docs/CREDITS.md "Tools" (PixelLab: one prompt a gem type and quality, candidates picked by hand, a few
colour nudges, trimmed and centred, alpha 0 / 255). The picks are committed as one sheet:

  art_import/gems_src.png    160 x 224 RGBA, alpha 0 / 255 only: 7 rows = the gem types in the order of the config
                             (ruby, sapphire, emerald, amethyst, topaz, diamond, onyx), 5 columns = the qualities
                             Chipped, Flawed, Polished, Flawless, Perfect, one static 32 x 32 cell each. Chipped is a
                             small chip, each quality is bigger, Flawless is the full cut jewel, Perfect the jewel set
                             in gold.

    python3 -I gen_gem_art.py build                 # write the outputs from art_import/gems_src.png
    python3 -I gen_gem_art.py build --check         # CI: rebuild, compare every output byte for byte
    python3 -I gen_gem_art.py preview --out DIR [--before-dat D --before-spr S]   # sheets and GIFs for review

Animation (nine phases at 110 ms, the same for every gem): Chipped, Flawed and Polished stand still (nine equal frames).
Flawless gets one white four-point twinkle on its brightest pixel (phases 1 to 5, arm length 0, 1, 2, 1, 0); Perfect gets
that one and a second, smaller one on its next brightest pixel at least 9 px away (phases 5 to 8, arm length 0, 1, 1, 0).
The twinkle only paints white pixels over the cell. Nothing is random.

Outputs (all committed):
  art_import/gems.png        the atlas import_art_things.py and redraw_items.py read: one row per gem (type order of the
                             config, qualities Chipped..Perfect), nine 32 px phases left to right (288 x 1120)
  art_import/gems.csv        the things file: client ids 33905-33939 (after the Everfull Ration 33904), flags copied
                             from the stock gem the item used so far (stackable, multi-use, light stay), mode replace
                             with the gem's server id 32001..32035 (install_gems.py with ownLook = true). Pair 63
                             draws the 35 items in place from the atlas instead (redraw_items.py --strip)
  client/overlay/data/images/game/gems/<key>.png   the five qualities side by side, phase 0, 2x (game_codex gem pages)
The website's wiki icons (gm-<key>-<tier>) are cut from the atlas by website/tools/gen_wiki_art.py.

Deterministic: numpy and Pillow only, no randomness (CI pins Pillow 12.3.0 / numpy 2.5.3).
"""
import argparse
import csv
import io
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SOURCE = os.path.join(ART, 'gems_src.png')
ATLAS = os.path.join(ART, 'gems.png')
THINGS = os.path.join(ART, 'gems.csv')
CODEX = os.path.join(REPO, 'client', 'overlay', 'data', 'images', 'game', 'gems')
CONFIG = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_gems_config.lua')

FIRST_CLIENT = 33905        # after the Everfull Ration (33904, art_import/store_food.csv)
PHASES = 9
MS = 110                    # frame time of every phase
TIERS = 5                   # Chipped, Flawed, Polished, Flawless, Perfect
KEYS = ('ruby', 'sapphire', 'emerald', 'amethyst', 'topaz', 'diamond', 'onyx')   # the row order of the source sheet
CODEX_SCALE, CODEX_GAP = 2, 12
GROW = (0, 1, 2, 1, 0)      # Flawless twinkle: arm length in phases 1 to 5
GROW2 = (0, 1, 1, 0)        # Perfect second twinkle: arm length in phases 5 to 8
SPOT_APART = 9              # the second twinkle sits at least this many px (Manhattan) from the first
SPOT_EDGE = 2               # twinkles stay this far from the cell border
# the twinkle spots of the cells that twinkle, (y, x) in the cell: the first of Flawless, the first and the second of Perfect.
# Each is one of the tied brightest pixels (spots() checks it); these are the ones of the sheet the owner was sent (2026-11-11).
PICKS = {
    ('ruby', 4): ((8, 13),), ('ruby', 5): ((7, 8), (11, 13)),
    ('sapphire', 4): ((10, 20),), ('sapphire', 5): ((14, 11), (8, 7)),
    ('emerald', 4): ((7, 12),), ('emerald', 5): ((4, 19), (11, 8)),
    ('amethyst', 4): ((14, 11),), ('amethyst', 5): ((7, 7), (12, 12)),
    ('topaz', 4): ((16, 11),), ('topaz', 5): ((15, 13), (19, 20)),
    ('diamond', 4): ((7, 16),), ('diamond', 5): ((12, 13), (18, 18)),
    ('onyx', 4): ((9, 13),), ('onyx', 5): ((11, 13), (7, 7)),
}


def config_types(path=CONFIG):
    """[(key, name, plural, clientId, clientIdHigh or None)] in config order; firstId; tier names"""
    text = re.sub(r'--[^\n]*', '', open(path, encoding='utf-8').read())
    first = int(re.search(r'firstId\s*=\s*(\d+)', text).group(1))
    high_from = int(re.search(r'highFrom\s*=\s*(\d+)', text).group(1))
    tiers = re.findall(r'"([^"]+)"', re.search(r'tiers\s*=\s*\{([^}]*)\}', text).group(1))
    out = []
    for m in re.finditer(r'\{key\s*=\s*"(\w+)",\s*name\s*=\s*"([^"]+)",\s*plural\s*=\s*"([^"]+)",\s*clientId\s*=\s*(\d+)'
                         r'(?:,\s*clientIdHigh\s*=\s*(\d+))?', text):
        out.append((m.group(1), m.group(2), m.group(3), int(m.group(4)), int(m.group(5)) if m.group(5) else None))
    return out, first, high_from, tiers


# ------------------------------------------------------------------------------------------------ build
def check_source(sheet):
    """the committed source sheet: 160 x 224 RGBA, alpha 0 / 255, no colour under alpha 0, every cell drawn"""
    assert sheet.shape == (32 * len(KEYS), 32 * TIERS, 4), 'gems_src.png is %d x %d, not %d x %d' % (
        sheet.shape[1], sheet.shape[0], 32 * TIERS, 32 * len(KEYS))
    assert set(np.unique(sheet[..., 3]).tolist()) <= {0, 255}, 'alpha must be 0 / 255'
    assert not sheet[sheet[..., 3] == 0].any(), 'colour under alpha 0 must be 0'
    for r in range(len(KEYS)):
        for k in range(TIERS):
            assert cell(sheet, r, k)[..., 3].any(), 'empty cell %s %d' % (KEYS[r], k)


def cell(sheet, row, tier):
    """the static 32 x 32 cell of gem row ROW, quality TIER (0 = Chipped)"""
    return sheet[row * 32:(row + 1) * 32, tier * 32:(tier + 1) * 32]


def spot_candidates(c, taken):
    """the pixels a twinkle may sit on after the pixels TAKEN: of the opaque pixels (sum of r, g, b) SPOT_EDGE from the
    border and at least SPOT_APART (Manhattan) from every taken one, those with the highest sum; reading order"""
    lum = c[..., :3].astype(int).sum(axis=2) * (c[..., 3] > 0)
    lum[:SPOT_EDGE] = lum[-SPOT_EDGE:] = 0
    lum[:, :SPOT_EDGE] = lum[:, -SPOT_EDGE:] = 0
    yy, xx = np.ogrid[:32, :32]
    for y, x in taken:
        lum[abs(yy - y) + abs(xx - x) < SPOT_APART] = 0
    top = lum.max()
    if top == 0:
        return []
    ys, xs = np.nonzero(lum == top)
    return [(int(y), int(x)) for y, x in zip(ys, xs)]


def spots(c, n, picks=()):
    """the n twinkle spots of one cell: each the brightest pixel left (spot_candidates). Flat highlights tie many pixels
    and a sort order must not decide between them, so PICKS names the chosen pixel of each (it must be a candidate,
    else this raises: change the source sheet and the table together); without a pick the first candidate in reading
    order is taken"""
    got = []
    for i in range(n):
        cand = spot_candidates(c, got)
        if not cand:
            break
        if i < len(picks):
            assert tuple(picks[i]) in cand, 'twinkle spot %s is not a brightest pixel of its cell (candidates %s)' % (
                tuple(picks[i]), cand)
            got.append(tuple(picks[i]))
        else:
            got.append(cand[0])
    return got


def star(c, y, x, size):
    """a white four-point twinkle on pixel (y, x), in place: size 0 one pixel, 1 a plus, 2 a plus with longer arms"""
    pts = [(0, 0)] if size == 0 else [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]
    if size >= 2:
        pts += [(2, 0), (-2, 0), (0, 2), (0, -2)]
    for dy, dx in pts:
        yy, xx = y + dy, x + dx
        if 0 <= yy < 32 and 0 <= xx < 32:
            c[yy, xx] = (255, 255, 255, 255)


def phases(c, tier, picks=()):
    """the PHASES frames of one cell; tier 1 = Chipped .. 5 = Perfect. Tiers 1 to 3 stand still, 4 twinkles once, 5 twice"""
    sp = spots(c, 2 if tier == 5 else 1, picks) if tier >= 4 else []
    out = []
    for p in range(PHASES):
        f = c.copy()
        if sp and 0 <= p - 1 < len(GROW):
            star(f, sp[0][0], sp[0][1], GROW[p - 1])
        if len(sp) > 1 and 0 <= p - 5 < len(GROW2):
            star(f, sp[1][0], sp[1][1], GROW2[p - 5])
        out.append(f)
    return out


def build_atlas(sheet):
    types, _first, _hf, tiers = config_types()
    assert [t[0] for t in types] == list(KEYS), 'gem types of the config: %s' % [t[0] for t in types]
    assert len(tiers) == TIERS
    check_source(sheet)
    atlas = np.zeros((32 * len(types) * TIERS, 32 * PHASES, 4), np.uint8)
    for r in range(len(types)):
        for k in range(TIERS):
            for p, f in enumerate(phases(cell(sheet, r, k), k + 1, PICKS.get((KEYS[r], k + 1), ()))):
                row = r * TIERS + k
                atlas[row * 32:(row + 1) * 32, p * 32:(p + 1) * 32] = f
    return atlas


def things_rows():
    types, first, high_from, tiers = config_types()
    rows = []
    n = len(tiers)
    for ti, (key, name, _plural, cid, cid_high) in enumerate(types):
        for tier in range(1, n + 1):
            i = ti * n + tier - 1
            stock = cid_high if (cid_high and tier >= high_from) else cid
            rows.append({'key': 'gem_%s_%d' % (key, tier), 'cat': 'item', 'kind': 'look',
                         'name': '%s %s' % (tiers[tier - 1].lower(), name), 'atlas': 'gems', 'x': 0, 'y': i * 32,
                         'w': 1, 'h': 1, 'patterns': 1, 'phases': PHASES, 'flags': 'copy:%d' % stock, 'mode': 'replace',
                         'server_id': first + i, 'extra': 'ms=%d' % MS})
    return rows


FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']


def things_text():
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    for r in things_rows():
        w.writerow(r)
    return buf.getvalue()


def codex_strips(atlas):
    types, *_ = config_types()
    n = TIERS
    out = {}
    cell = 32 * CODEX_SCALE
    for ti, (key, *_r) in enumerate(types):
        img = Image.new('RGBA', (n * cell + (n - 1) * CODEX_GAP, cell), (0, 0, 0, 0))
        for t in range(n):
            y = (ti * n + t) * 32
            fr = Image.fromarray(atlas[y:y + 32, 0:32]).resize((cell, cell), Image.NEAREST)
            img.paste(fr, (t * (cell + CODEX_GAP), 0))
        out[key] = img
    return out


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=False, compress_level=9)
    return buf.getvalue()


def check_rules(atlas):
    al = np.unique(atlas[..., 3])
    assert set(al.tolist()) <= {0, 255}, 'alpha must be 0 / 255'
    rows = atlas.shape[0] // 32
    for r in range(rows):
        for f in range(PHASES):
            assert atlas[r * 32:(r + 1) * 32, f * 32:(f + 1) * 32, 3].any(), ('empty frame', r, f)


def outputs(atlas):
    out = {ATLAS: png_bytes(Image.fromarray(atlas)), THINGS: things_text().encode()}
    for key, img in codex_strips(atlas).items():
        out[os.path.join(CODEX, key + '.png')] = png_bytes(img)
    return out


def cmd_build(a):
    if not os.path.exists(SOURCE):
        sys.exit('no %s' % os.path.relpath(SOURCE, REPO))
    atlas = build_atlas(np.asarray(Image.open(SOURCE).convert('RGBA')))
    check_rules(atlas)
    outs = outputs(atlas)
    bad = []
    for path, data in sorted(outs.items()):
        rel = os.path.relpath(path, REPO)
        if a.check:
            if not os.path.exists(path):
                bad.append(rel + ' missing')
            elif path.endswith('.png'):
                have = np.asarray(Image.open(path).convert('RGBA'))
                want = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
                if have.shape != want.shape or not (have == want).all():
                    bad.append(rel + ' differs')
            elif open(path, 'rb').read() != data:
                bad.append(rel + ' differs')
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'wb').write(data)
    if a.check:
        if bad:
            print('\n'.join(bad))
            sys.exit('gem art: %d file(s) out of date (python3 -I client/tools/sprites/gen_gem_art.py build)' % len(bad))
        print('gem art up to date (%d gems, %d frames each, %d files)' % (atlas.shape[0] // 32, PHASES, len(outs)))
    else:
        print('wrote %d files (%d gems, client ids %d-%d)' % (len(outs), atlas.shape[0] // 32, FIRST_CLIENT,
                                                             FIRST_CLIENT + atlas.shape[0] // 32 - 1))


# ------------------------------------------------------------------------------------------------ preview
def stock_icons(dat, spr):
    """client id -> phase 0 of the stock gem looks used so far (from a pair)"""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    types, _f, hf, tiers = config_types()
    out = {}
    for key, _n, _p, cid, cidh in types:
        for c in (cid, cidh):
            if c and c not in out:
                out[c] = np.asarray(render_item(d, s, c, box=32).convert('RGBA'))
    return out


def cmd_preview(a):
    atlas = np.asarray(Image.open(ATLAS).convert('RGBA'))
    os.makedirs(a.out, exist_ok=True)
    types, _f, hf, tiers = config_types()
    n = len(tiers)
    sc, pad = 3, 6
    bg = (36, 30, 26, 255)
    # sheet: one row per gem, its five tiers at phase 0, 3x
    cell = 32 * sc + pad
    sheet = Image.new('RGBA', (cell * n + pad, cell * len(types) + pad), bg)
    for ti in range(len(types)):
        for t in range(n):
            y = (ti * n + t) * 32
            fr = Image.fromarray(atlas[y:y + 32, 0:32]).resize((32 * sc, 32 * sc), Image.NEAREST)
            sheet.alpha_composite(fr, (pad + t * cell, pad + ti * cell))
    sheet.save(os.path.join(a.out, 'gems_after.png'))
    # GIF: every gem and tier animating, 2x
    frames = []
    for f in range(PHASES):
        im = Image.new('RGBA', (n * 72 + 8, len(types) * 72 + 8), bg)
        for ti in range(len(types)):
            for t in range(n):
                y = (ti * n + t) * 32
                fr = Image.fromarray(atlas[y:y + 32, f * 32:(f + 1) * 32]).resize((64, 64), Image.NEAREST)
                im.alpha_composite(fr, (8 + t * 72, 8 + ti * 72))
        frames.append(im.convert('RGB'))
    frames[0].save(os.path.join(a.out, 'gems_after.gif'), save_all=True, append_images=frames[1:], duration=MS, loop=0)
    if a.before_dat and a.before_spr:
        icons = stock_icons(a.before_dat, a.before_spr)
        before = Image.new('RGBA', sheet.size, bg)
        for ti, (key, _n, _p, cid, cidh) in enumerate(types):
            for t in range(n):
                c = cidh if (cidh and t + 1 >= hf) else cid
                fr = Image.fromarray(icons[c]).resize((32 * sc, 32 * sc), Image.NEAREST)
                before.alpha_composite(fr, (pad + t * cell, pad + ti * cell))
        both = Image.new('RGBA', (sheet.width * 2 + 24, sheet.height), bg)
        both.alpha_composite(before, (0, 0))
        both.alpha_composite(sheet, (sheet.width + 24, 0))
        both.save(os.path.join(a.out, 'gems_before_after.png'))
    print('preview in', a.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    p.add_argument('--before-dat')
    p.add_argument('--before-spr')
    a = ap.parse_args()
    (cmd_build if a.cmd == 'build' else cmd_preview)(a)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Gem looks: the seven socket gems (server/data/lib/chaos_gems_config.lua) in five tiers each, animated, from the
owner's gem set (Google Drive "ots/gems.zip", 2026-10-14: five gem families in ten tiers, each a 32 x 288 strip of
nine 32 px frames; the owner: "Pode usar eles abertamente onde forem cabiveis", use them openly where they fit; the
zip holds no licence or readme).

    python3 -I gen_gem_art.py build --src DIR       # DIR = the unzipped gems/ folder (<family>_tNN/<family>_tNN.png)
    python3 -I gen_gem_art.py build --check         # CI: rebuild from the committed atlas, compare every output
    python3 -I gen_gem_art.py build --src DIR --check   # rebuild from the set, compare byte for byte
    python3 -I gen_gem_art.py preview --out DIR [--before-dat D --before-spr S]   # sheets and GIFs for review

Outputs (all committed):
  art_import/gems.png        the atlas import_art_things.py reads: one row per gem (type order of the config, tiers
                             Chipped..Perfect), nine 32 px phases left to right (288 x 1120)
  art_import/gems.csv        the things file: client ids 33905-33939 (after the Everfull Ration 33904), flags copied
                             from the stock gem the item used so far (stackable, multi-use, light stay), mode replace
                             with the gem's server id 32001..32035 (install_gems.py with ownLook = true)
  client/overlay/data/images/game/gems/<key>.png   the five tiers side by side, phase 0, 2x (game_codex gem pages)
The website's wiki icons (gm-<key>-<tier>) are cut from the atlas by website/tools/gen_wiki_art.py.

Which family is which gem: the source tiers t02, t04, t06, t08, t10 are our five tiers. Four gems take a family's own
colours (emerald = jadecomb, sapphire = tidegem, amethyst = voidorb, topaz = sunshard warmed a little towards gold);
the other three are recoloured (hue / saturation / value per pixel, alpha and shading kept): ruby = bloomjade turned
red, diamond = tidegem drained to a pale ice white, onyx = voidorb drained to a warm black-grey. Every frame keeps
alpha 0 / 255 (checked). Deterministic: numpy and Pillow only, no randomness (CI pins Pillow 12.3.0 / numpy 2.5.3).
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
ATLAS = os.path.join(ART, 'gems.png')
THINGS = os.path.join(ART, 'gems.csv')
CODEX = os.path.join(REPO, 'client', 'overlay', 'data', 'images', 'game', 'gems')
CONFIG = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_gems_config.lua')

FIRST_CLIENT = 33905        # after the Everfull Ration (33904, art_import/store_food.csv)
PHASES = 9
MS = 110                    # the set's own frame time
SRC_TIERS = (2, 4, 6, 8, 10)
# gem key -> (source family, recolour)
GEMS = {
    'ruby': ('bloomjade', 'ruby'),
    'sapphire': ('tidegem', None),
    'emerald': ('jadecomb', None),
    'amethyst': ('voidorb', None),
    'topaz': ('sunshard', 'topaz'),
    'diamond': ('tidegem', 'diamond'),
    'onyx': ('voidorb', 'onyx'),
}
CODEX_SCALE, CODEX_GAP = 2, 12


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


# ------------------------------------------------------------------------------------------------ colour
def rgb_to_hsv(rgb):
    r, g, b = [rgb[..., i] for i in range(3)]
    mx = np.max(rgb, axis=-1); mn = np.min(rgb, axis=-1); d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 0
    rm = nz & (mx == r); gm = nz & (mx == g) & ~rm; bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h / 6.0
    s = np.where(mx > 0, d / np.where(mx > 0, mx, 1), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    h6 = (h % 1.0) * 6
    i = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    sel = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate(sel):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = a[m], b[m], c[m]
    return out


def recolour(img, kind):
    """img: H x W x 4 uint8 (alpha 0 / 255) -> the same shape, colours moved; None leaves it as it is"""
    if kind is None:
        return img.copy()
    rgb = img[..., :3].astype(np.float64) / 255.0
    h, s, v = rgb_to_hsv(rgb)
    if kind == 'ruby':        # green -> crimson: hues pulled together round 356 deg, more saturated, a touch deeper
        h = 356 / 360.0 + (((h - 125 / 360.0 + 0.5) % 1.0) - 0.5) * 0.30
        s = np.clip(s * 1.25 + 0.12, 0, 1)
        v = v * 0.90
    elif kind == 'topaz':     # amber -> gold
        h = h + 13 / 360.0
        s = np.clip(s * 0.95, 0, 1)
        v = np.clip(v * 1.04, 0, 1)
    elif kind == 'diamond':   # deep blue -> pale ice white, the outline stays dark
        s = s * 0.22
        v = np.where(v > 0.25, np.clip(0.30 + v * 0.75, 0, 1), v)
    elif kind == 'onyx':      # violet -> warm black-grey with pale highlights
        h = np.full_like(h, 0.0)
        s = s * 0.12
        v = np.where(v > 0.92, v * 0.80, v * 0.42)
    else:
        raise ValueError(kind)
    out = img.copy()
    out[..., :3] = np.clip(np.round(hsv_to_rgb(h, s, v) * 255), 0, 255).astype(np.uint8)
    out[img[..., 3] == 0] = 0
    return out


# ------------------------------------------------------------------------------------------------ build
def source_frames(src, family, tier):
    path = os.path.join(src, '%s_t%02d' % (family, tier), '%s_t%02d.png' % (family, tier))
    a = np.asarray(Image.open(path).convert('RGBA'))
    assert a.shape == (32 * PHASES, 32, 4), (path, a.shape)
    return [a[i * 32:(i + 1) * 32] for i in range(PHASES)]


def build_atlas(src):
    types, _first, _hf, tiers = config_types()
    assert [t[0] for t in types] == list(GEMS), 'gem types of the config: %s' % [t[0] for t in types]
    assert len(tiers) == len(SRC_TIERS)
    atlas = np.zeros((32 * len(types) * len(SRC_TIERS), 32 * PHASES, 4), np.uint8)
    row = 0
    for key, *_ in types:
        family, kind = GEMS[key]
        for tier in SRC_TIERS:
            for f, fr in enumerate(source_frames(src, family, tier)):
                fr = fr.copy()
                fr[fr[..., 3] < 128] = 0
                fr[..., 3] = np.where(fr[..., 3] > 0, 255, 0)
                atlas[row * 32:(row + 1) * 32, f * 32:(f + 1) * 32] = recolour(fr, kind)
            row += 1
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
    n = len(SRC_TIERS)
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
    if a.src:
        atlas = build_atlas(a.src)
    elif a.check:
        if not os.path.exists(ATLAS):
            sys.exit('no %s: run build --src DIR first' % os.path.relpath(ATLAS, REPO))
        atlas = np.asarray(Image.open(ATLAS).convert('RGBA'))
    else:
        sys.exit('build needs --src (the gem set); without it only --check runs')
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
            sys.exit('gem art: %d file(s) out of date (python3 -I client/tools/sprites/gen_gem_art.py build --src DIR)'
                     % len(bad))
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
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    p.add_argument('--before-dat')
    p.add_argument('--before-spr')
    a = ap.parse_args()
    (cmd_build if a.cmd == 'build' else cmd_preview)(a)


if __name__ == '__main__':
    main()

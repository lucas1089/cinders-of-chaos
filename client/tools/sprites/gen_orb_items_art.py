#!/usr/bin/env python3
"""Orb item looks drawn in code: currency orbs whose client sprite was a rune's get an orb of their own (pair 38,
client ids 38641..; client/MANIFEST.md "Orb looks").

    python3 -I gen_orb_items_art.py build [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

Owner, 2026-10-22: "Coloque arte de orb de verdade. Não use as runas para isso. Deixe os sprites de runa só para as
runas." The Orb of Sockets (server 24692) was an unused stackable rune stone of the base data, client 22036, and that
thing draws sprite 1317, the sprite of the great fireball rune (client 3191). Every other orb of the loot list and of
the crafting bench has a look no rune shares (checked against the 134 rune things of pair 37: no shared sprite, no
equal or near picture).

Each look is a sphere drawn per pixel (no source image): a glass body lit from the top, a little left
(docs/SPRITE_STYLE.md), a glow inside, a specular glint, the orb's own trim, a one-pixel near-black outline. The
colours are snapped to one theme palette (style_check.snap) and `build` refuses a tile that fails
`style_check.py` against its theme. Deterministic: integer maths after a float render with fixed inputs, numpy and
Pillow only, no randomness.
  Orb of Sockets  azurevigil  deep blue glass, a gold band round it holding three sockets that each catch a gem's
                              light (violet, cyan, green): the orb that rolls sockets for gems

Outputs (committed): art_import/orb_items.png (32 px tiles in LOOKS order) and art_import/orb_items.csv (the things
file of import_art_things.py: flags copied from the client thing the item used so far, so stackable and multi-use
stay; mode replace with the server id). The server points the item at the new client id: server/tools/install_gems.py
(socketOrb.look in data/lib/chaos_gems_config.lua). `--check` (CI) rebuilds and compares, writes nothing.
`--preview DIR` writes orb_items_before_after.png (the old look from a pair beside the new one, 4x, light and dark).
"""
import argparse, csv, io, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
ATLAS = os.path.join(ART, 'orb_items.png')
THINGS = os.path.join(ART, 'orb_items.csv')
FIRST_CLIENT_ID = 38641   # after the last item of pair 37 (38640)

# key, things name, theme, old client id (flags copied from it; the "before" of the preview), server id, design
LOOKS = (
    ('orb_sockets', 'orb of sockets', 'azurevigil', 22036, 24692, 'sockets'),
)
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']

CX, CY, R = 15.5, 15.5, 14.2          # sphere centre and radius in pixel units (box about 29 x 29)
LIGHT = np.array([-0.38, -0.80, 0.46])  # from the top, a little left, toward the viewer
TILT = np.radians(28)                  # the band's plane leans toward the viewer: its front half dips below the centre


def hexrgb(s):
    return np.array([int(s[i:i + 2], 16) for i in (1, 3, 5)], np.float64)


def ramp(stops, t):
    """t (array 0..1) -> RGB along the colour stops (evenly spaced)"""
    t = np.clip(t, 0, 1) * (len(stops) - 1)
    i = np.minimum(np.floor(t).astype(int), len(stops) - 2)
    f = (t - i)[..., None]
    a = np.array([hexrgb(s) for s in stops])
    return a[i] * (1 - f) + a[i + 1] * f


def sphere():
    """pixel grid -> (inside mask, normals x / y / z)"""
    yy, xx = np.mgrid[0:32, 0:32].astype(np.float64)
    dx, dy = (xx - CX) / R, (yy - CY) / R
    d2 = dx * dx + dy * dy
    inside = d2 <= 1.0
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    return inside, dx, dy, nz


def draw_sockets():
    inside, nx, ny, nz = sphere()
    L = LIGHT / np.linalg.norm(LIGHT)
    diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    # glass body: deep blue, lit top left; a soft cyan glow low in the core (light inside the glass)
    body = ramp(['#082e4c', '#183c58', '#1d537c', '#2271a5', '#398abd', '#59b0d6'], 0.05 + 0.80 * diff ** 1.1)
    gx, gy = (np.mgrid[0:32, 0:32][1] - 16.5) / R, (np.mgrid[0:32, 0:32][0] - 14.0) / R
    glow = np.exp(-(gx * gx + gy * gy) / 0.16)[..., None]
    body = body * (1 - 0.75 * glow) + ramp(['#3c85a6', '#6cd3dc', '#94e1ea'], glow[..., 0]) * 0.75 * glow
    # specular glint top left
    H = L + np.array([0, 0, 1.0]); H = H / np.linalg.norm(H)
    spec = np.clip(nx * H[0] + ny * H[1] + nz * H[2], 0, 1) ** 40
    body = body * (1 - spec[..., None]) + hexrgb('#f4fefb') * spec[..., None]
    # the gold band: points of the sphere near a great circle whose plane leans toward the viewer
    b = np.array([0.0, -np.cos(TILT), np.sin(TILT)])
    lat = nx * b[0] + ny * b[1] + nz * b[2]
    band = inside & (np.abs(lat) < 0.17)
    edge = inside & (np.abs(lat) >= 0.17) & (np.abs(lat) < 0.23)
    gold = ramp(['#3b2b14', '#815824', '#b27a22', '#d6a23d', '#f0cc6a', '#fcedbd'],
                0.10 + 0.90 * diff ** 0.8 + 0.25 * (0.17 - np.abs(lat)))
    rgb = np.where(band[..., None], gold, body)
    rgb = np.where(edge[..., None], ramp(['#3b2b14', '#584121'], diff), rgb)
    # three sockets on the front of the band: a dark cavity, a gem's light inside, a glint on its upper left
    yy, xx = np.mgrid[0:32, 0:32].astype(np.float64)
    w = np.array([0.0, np.sin(TILT), np.cos(TILT)])
    for phi, gem in ((-0.72, ('#6f1ab6', '#aa34e8', '#ef75f5')), (0.0, ('#2a6a8a', '#6cd3dc', '#caf5ec')),
                     (0.72, ('#0b6040', '#20d975', '#56f89b'))):
        p = np.sin(phi) * np.array([1.0, 0, 0]) + np.cos(phi) * w
        sx, sy = CX + R * p[0], CY + R * p[1]
        fx = max(np.cos(phi), 0.55)            # foreshortened toward the sides
        ex, ey = (xx - sx) / (3.1 * fx), (yy - sy) / 2.9
        e = np.sqrt(ex * ex + ey * ey)
        rgb = np.where((inside & (e <= 1.0))[..., None], hexrgb('#02020a'), rgb)
        gem_rgb = ramp(list(gem), np.clip(1.0 - e / 0.62 + 0.25 * (-(xx - sx) - (yy - sy)) / 3.0, 0, 1))
        rgb = np.where((inside & (e <= 0.62))[..., None], gem_rgb, rgb)
    # one-pixel outline: inside pixels with a 4-neighbour outside
    pad = np.pad(inside, 1)
    rim = inside & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    rgb = np.where(rim[..., None], hexrgb('#020205'), rgb)
    out = np.zeros((32, 32, 4), np.uint8)
    out[..., :3] = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    out[..., 3] = np.where(inside, 255, 0)
    out[~inside] = 0
    return out


DESIGNS = {'sockets': draw_sockets}


def build():
    """(atlas RGBA, things csv text, [(key, theme, reasons)])"""
    data = sc.load_palettes()
    tiles, report = [], []
    for key, _n, theme, _old, _sid, design in LOOKS:
        t = data['themes'][theme]
        pal = np.array([sc.unhex(x) for x in t['palette']], np.uint8)
        s = sc.snap(DESIGNS[design](), pal)
        bad, _warn = sc.judge(sc.measure(s), pal, t['light'], data['thresholds'])
        report.append((key, theme, bad))
        tiles.append(s)
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    for k, (key, name, _th, old, sid, _d) in enumerate(LOOKS):
        w.writerow([key, 'item', 'look', name, 'orb_items', k * 32, 0, 1, 1, 1, 1, 'copy:%d' % old, 'replace', sid, ''])
    return np.concatenate(tiles, axis=1), out.getvalue(), report


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(atlas, outdir, dat, spr):
    """orb_items_before_after.png: per look the old client thing (from the pair) and the new tile, 4x, light / dark"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    z, pad = 4, 8
    n = len(LOOKS)
    W, H = pad + 2 * n * (32 * z + pad), 2 * (32 * z + 2 * pad)
    im = Image.new('RGBA', (W, H))
    for row, bg in enumerate(((214, 200, 170, 255), (40, 36, 34, 255))):
        im.paste(Image.new('RGBA', (W, H // 2), bg), (0, row * H // 2))
        for k, (_key, _n, _t, old, _s, _d) in enumerate(LOOKS):
            before = render_item(d, s, old, box=32).convert('RGBA').resize((32 * z, 32 * z), Image.NEAREST)
            after = Image.fromarray(atlas[:, k * 32:(k + 1) * 32]).resize((32 * z, 32 * z), Image.NEAREST)
            for j, tile in enumerate((before, after)):
                im.alpha_composite(tile, (pad + (2 * k + j) * (32 * z + pad), row * H // 2 + pad))
    p = os.path.join(outdir, 'orb_items_before_after.png')
    im.convert('RGB').save(p)
    print('preview', p)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for orb_items_before_after.png (needs --dat / --spr)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    atlas, things, report = build()
    failed = False
    for key, theme, bad in report:
        print('%s %s: %s' % (key, theme, 'style PASS' if not bad else 'style FAIL'))
        for b in bad:
            print('  ' + b)
            failed = True
    if failed:
        return 1
    if a.check:
        ok = True
        if not os.path.exists(ATLAS) or not np.array_equal(np.array(Image.open(ATLAS).convert('RGBA')), atlas):
            print('stale:', os.path.relpath(ATLAS, HERE))
            ok = False
        if not os.path.exists(THINGS) or open(THINGS, encoding='utf-8').read() != things:
            print('stale:', os.path.relpath(THINGS, HERE))
            ok = False
        print('orb item looks up to date' if ok else 'run: python3 -I gen_orb_items_art.py build')
        return 0 if ok else 1
    with open(ATLAS, 'wb') as f:
        f.write(png_bytes(atlas))
    with open(THINGS, 'w', encoding='utf-8', newline='') as f:
        f.write(things)
    print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d..%d'
          % (FIRST_CLIENT_ID, FIRST_CLIENT_ID + len(LOOKS) - 1))
    print('things', THINGS)
    if a.preview:
        if not (a.dat and a.spr):
            sys.exit('--preview needs --dat and --spr (the pair with the old looks)')
        preview(atlas, a.preview, a.dat, a.spr)
    return 0


if __name__ == '__main__':
    sys.exit(main())

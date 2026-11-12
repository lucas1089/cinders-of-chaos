#!/usr/bin/env python3
"""Pair 66 effect: Eclipse of Ruin's blue nova, effect 4702 (ROADMAP O523).

python3 -I gen_pair66_fx.py build DAT SPR        # write art_import/pair66_fx/nova_radiant_blue.png from the pair's effect 713
python3 -I gen_pair66_fx.py build DAT SPR --check

Owner 2026-11-12, shown the pilot: Eclipse of Ruin (Mystic, Elementalist, Illusionist; ice) sent a frost nova and a storm ring, two
soft 7x7 effects; it sends one crisp nova now. The nova is effect 713 (Purging Nova, `nova_radiant`, gold) turned to blue: every colour
with a saturation over 0.12 gets its hue moved by +175 degrees (gold to blue), the grey and white stay. Effect 713 itself is not
changed (other spells send it); the blue one is a NEW effect appended to the pair by import_fx_art.py (spec art_import/pair66_fx.csv),
so every client on pair 65 or older has no effect 4702 and draws nothing for it (README "Pair 66"). The frames are read from the pair
that already has the dither taken out (clean_pack_dither.py), so the blue nova has no mesh. No pixel is drawn, no art is read from
outside the pair; alpha stays 0 / 255. The PNG is derived from purchased art: art_import/pair66_fx/ is ignored by git.
Deterministic. Run order of pair 66: client/MANIFEST.md "Pair 66".
"""
import argparse
import csv
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from datspr import Dat, Spr, sprite_index  # noqa: E402

ART = os.path.join(HERE, 'art_import')
OUT_DIR = os.path.join(ART, 'pair66_fx')
SPEC = os.path.join(ART, 'pair66_fx.csv')
SOURCE = 713                    # nova_radiant, 5x5, gold
NAME = 'nova_radiant_blue'
HUE = 175.0                     # degrees
SAT_MIN = 0.12                  # a pixel with less saturation keeps its colour (white core, grey)
GITIGNORE = '# frames of a recoloured purchased pack effect: not committed (gen_pair66_fx.py)\n*\n!.gitignore\n'


def hue_shift(img, deg):
    """RGBA uint8 -> RGBA uint8: hue + deg for the pixels with saturation > SAT_MIN, value and alpha kept"""
    a = img.astype(np.float64) / 255.0
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    df = mx - mn
    sat = np.where(mx > 0, df / np.maximum(mx, 1e-9), 0)
    safe = np.maximum(df, 1e-9)
    hr = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4))
    h = np.where(df > 0, hr / 6.0, 0)
    h2 = (h + deg / 360.0) % 1.0
    i = np.floor(h2 * 6).astype(int) % 6
    f = h2 * 6 - np.floor(h2 * 6)
    p = mx * (1 - sat)
    q = mx * (1 - f * sat)
    t = mx * (1 - (1 - f) * sat)
    out = np.stack([np.choose(i, [mx, q, p, p, t, mx]), np.choose(i, [t, mx, mx, q, p, p]), np.choose(i, [p, p, t, mx, mx, q]), al], -1)
    out = np.where((sat > SAT_MIN)[..., None], out, a)
    res = (out * 255 + 0.5).astype(np.uint8)
    res[res[..., 3] == 0] = 0
    return res


def frames_of(t, spr):
    """[RGBA canvas (h * 32, w * 32, 4)] one per phase; tile (0, 0) at the bottom right"""
    out = []
    for ph in range(t.phases):
        img = np.zeros((t.h * 32, t.w * 32, 4), np.uint8)
        for hh in range(t.h):
            for ww in range(t.w):
                a = spr.sprite(int(t.sprites[sprite_index(t, 0, 0, 0, 0, ph, ww, hh)]))
                if a is not None:
                    img[(t.h - 1 - hh) * 32:(t.h - hh) * 32, (t.w - 1 - ww) * 32:(t.w - ww) * 32] = a
        out.append(img)
    return out


def strip_of(dat, spr):
    t = dat.effects[SOURCE - 1]
    fr = [hue_shift(f, HUE) for f in frames_of(t, spr)]
    ms = t.anim[3][0] if len(t.anim) > 3 and t.anim[3] else 62
    return np.concatenate(fr, axis=1), t.w, t.h, len(fr), int(ms)


def spec_rows(w, h, n, ms):
    return [{'kind': 'effect', 'name': NAME, 'file': 'pair66_fx/%s.png' % NAME, 'w': w, 'h': h, 'phases': n, 'ms': ms,
             'dx': 2, 'dy': 2, 'note': 'Eclipse of Ruin: a blue Purging Nova (effect 713 with the hue turned +175 degrees)'}]


def spec_text(rows):
    cols = ['kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note']
    import io
    buf = io.StringIO()
    wr = csv.DictWriter(buf, cols, lineterminator='\n')
    wr.writeheader()
    wr.writerows(rows)
    return buf.getvalue()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('dat')
    b.add_argument('spr')
    b.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    dat, spr = Dat(a.dat), Spr(a.spr)
    strip, w, h, n, ms = strip_of(dat, spr)
    text = spec_text(spec_rows(w, h, n, ms))
    sha = hashlib.sha256(np.ascontiguousarray(strip).tobytes()).hexdigest()
    if a.check:
        have = open(SPEC).read() if os.path.exists(SPEC) else ''
        if have != text:
            print('%s is not what the pair gives' % SPEC)
            return 1
        print('pair 66 spec up to date (%dx%d tiles, %d frames, %d ms, strip sha256 %s)' % (w, h, n, ms, sha[:16]))
        return 0
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, '.gitignore'), 'w') as fh:
        fh.write(GITIGNORE)
    Image.fromarray(strip, 'RGBA').save(os.path.join(OUT_DIR, NAME + '.png'))
    with open(SPEC, 'w') as fh:
        fh.write(text)
    print('wrote %s (%dx%d tiles, %d frames, %d ms each, sha256 %s) and %s' % (NAME, w, h, n, ms, sha[:16], os.path.basename(SPEC)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

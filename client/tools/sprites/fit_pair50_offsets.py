#!/usr/bin/env python3
"""Send offsets of the pair 50 effects, fitted to where the art really is (O520).

    python3 -I client/tools/sprites/fit_pair50_offsets.py --check DAT SPR   # CI live-pair job: the csv holds the fit
    python3 -I client/tools/sprites/fit_pair50_offsets.py --write DAT SPR   # rewrite dx, dy in pair50_effects.csv
    python3 -I client/tools/sprites/gen_pair50_fx_ids.py                    # then the Lua table

import_pair50.py gives every effect the offset (w // 2, h // 2): the whole tiles past the target tile that bring the
MIDDLE OF THE CANVAS onto the target (the client draws the bottom-right tile on the tile it is sent to). That is right
only for art drawn in the middle of its canvas. Much of the pack art is not: the burst sits in the bottom-right tile,
so a 2x2 sent at +1, +1 landed a whole tile down and right of the target (Dreamrot 4579, Soulrend Beam 4574 / 4584).

This tool measures the alpha-weighted centre of the art over all phases and moves an axis to the whole-tile offset
that puts that centre nearest the target tile's middle, but only where the default is far off: at least 20 px
(over half a tile) away and the fit is at least 8 px closer. Everything else keeps (w // 2, h // 2).
Run it after import_pair50.py: the import writes the plain rule again. Needs numpy and Pillow (the fx venv of CI).
"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
CSV = os.path.join(ROOT, 'server', 'data', 'items', 'pair50_effects.csv')
FAR = 20      # px: the default must be at least this far off the target tile's middle
GAIN = 8      # px: and the fitted offset at least this much closer


def axis_error(c, n, d):
    """px from the target tile's middle to the art centre c (px from the canvas edge, n tiles) when the effect is
    sent d tiles past the target: the canvas starts n - 1 - d tiles up / left of it."""
    return c - ((n - 1 - d) * 32 + 16)


def fit_axis(c, n):
    """the offset for one axis: n // 2 unless the art centre c is far off it and another offset is clearly closer"""
    dflt = n // 2
    best = min(range(n), key=lambda d: (abs(axis_error(c, n, d)), d != dflt))
    far = abs(axis_error(c, n, dflt))
    if far >= FAR and far - abs(axis_error(c, n, best)) >= GAIN:
        return best
    return dflt


def fit(centre, w, h):
    """(dx, dy) for art of w x h tiles whose alpha-weighted centre is `centre` (x, y px), or the plain rule"""
    if centre is None:
        return (w // 2, h // 2)
    return (fit_axis(centre[0], w), fit_axis(centre[1], h))


def centre_of(frames):
    """alpha-weighted centre (x, y) in px of a list of RGBA numpy frames (all phases), or None when nothing shows"""
    import numpy as np
    total = cx = cy = 0.0
    for fr in frames:
        a = fr[..., 3].astype(float) / 255.0
        ys, xs = np.indices(a.shape)
        total += a.sum()
        cx += (a * xs).sum()
        cy += (a * ys).sum()
    return (cx / total, cy / total) if total > 0 else None


def fitted_rows(dat_path, spr_path, rows):
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from fxlib import render_frame
    dat, spr = Dat(dat_path), Spr(spr_path)
    out = []
    for r in rows:
        t = dat.effects[int(r['effect_id']) - 1]
        frames = [np.array(render_frame(t, spr, p, 0, 0)) for p in range(t.phases)]
        out.append(fit(centre_of(frames), t.w, t.h))
    return out


def main(argv):
    mode = argv[0] if argv else ''
    if mode not in ('--check', '--write') or len(argv) != 3:
        print(__doc__)
        return 2
    with open(CSV, newline='', encoding='utf-8') as fh:
        rdr = csv.DictReader(fh)
        cols = rdr.fieldnames
        rows = list(rdr)
    want = fitted_rows(argv[1], argv[2], rows)
    bad = [(r, w) for r, w in zip(rows, want) if (int(r['dx']), int(r['dy'])) != w]
    if mode == '--check':
        for r, w in bad[:20]:
            print('%s: csv %s,%s, fit %s,%s' % (r['key'], r['dx'], r['dy'], w[0], w[1]))
        print(CSV + (': up to date' if not bad else ': %d offsets differ (run fit_pair50_offsets.py --write)' % len(bad)))
        return 0 if not bad else 1
    for r, w in zip(rows, want):
        r['dx'], r['dy'] = str(w[0]), str(w[1])
    with open(CSV, 'w', newline='', encoding='utf-8') as fh:
        wr = csv.DictWriter(fh, fieldnames=cols, lineterminator='\n')
        wr.writeheader()
        wr.writerows(rows)
    print('wrote %s (%d offsets changed)' % (CSV, len(bad)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

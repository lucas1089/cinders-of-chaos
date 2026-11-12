#!/usr/bin/env python3
"""Monster recolour outfits: hue shifted copies of outfits that have no colour mask (O529; client/MANIFEST.md "Pair 69").

    python3 -I gen_monster_recolour.py check          # the table against the allow list (no pair needed)
    python3 -I gen_monster_recolour.py build DAT SPR  # waits: the pair that holds the copies is built after pair 68

Owner 2026-11-12 (translated): no two hunt monsters may share a look, and the way is a recolour. An outfit with a colour mask
(dat layers >= 2) is recoloured in the monster file (head, body, legs, feet; server/tools/tune_monsters.py). An outfit with no
mask cannot take a colour, so the second monster needs its own copy of the outfit with the hue shifted. The table
art_import/monster_recolour.csv names one row per such monster:

  look        the outfit the monster wears now (lookType in its XML)
  hue_shift   degrees added to the hue of every pixel (mode hue), or the target hue itself (mode tint)
  monster     the exact <monster name>
  mode        hue  = rotate the hue of each pixel, keep its saturation and value
              tint = the outfit is nearly grey (source_sat < 0.22): set the hue to hue_shift, lift the saturation to TINT_SAT
  theme       why the colour: fire, ice, poison, shadow, iron, gold, blood, arcane (the monster's name and element)
  source_hue  the outfit's dominant hue in degrees (saturation weighted), source_sat its mean saturation (informative)

The copy is appended to the pair as a new outfit (the next free outfit id after the pair 68 ones; same size, phases and
directions) and the monster's lookType then moves to it. Build is NOT done here: no pair is written, it waits for pair 68.
`recolour()` is the one pixel transform (numpy only); the O529 preview uses it too. Deterministic.
"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TABLE = os.path.join(HERE, 'art_import', 'monster_recolour.csv')
ALLOW = os.path.join(REPO, 'server', 'data', 'monster', 'shared_looks_allow.csv')
HEADER = ['look', 'hue_shift', 'monster', 'mode', 'theme', 'source_hue', 'source_sat']
TINT_SAT = 0.45
MIN_PAIR = 68   # the copies go after the last outfit of this pair
MIN_APART = 40  # degrees between two colours of one look


def recolour(rgba, hue_shift, mode='hue'):
    """RGBA uint8 array (H, W, 4) -> a new array with the hue moved. Alpha stays; a grey pixel has no hue and stays (mode hue)."""
    import numpy as np
    a = np.asarray(rgba)
    f = a[..., :3].astype(np.float64) / 255.0
    mx, mn = f.max(-1), f.min(-1)
    v, c = mx, mx - mn
    s = np.where(mx > 0, c / np.where(mx > 0, mx, 1), 0.0)
    safe = np.where(c > 0, c, 1)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    h = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) / 6.0
    h = np.where(c > 0, h, 0.0)
    if mode == 'tint':
        h = np.full_like(h, (hue_shift % 360) / 360.0)
        s = np.maximum(s, TINT_SAT)
    else:
        h = (h + hue_shift / 360.0) % 1.0
    i = np.floor(h * 6).astype(int) % 6
    ff = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - ff * s), v * (1 - (1 - ff) * s)
    out = np.stack([np.choose(i, [v, q, p, p, t, v]), np.choose(i, [t, v, v, q, p, p]), np.choose(i, [p, p, t, v, v, q])], -1)
    res = a.copy()
    res[..., :3] = np.clip(np.rint(out * 255), 0, 255).astype(np.uint8)
    return res


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def problems(table=None, allow=ALLOW):
    """What is wrong with the table: shift range, mode, one row per monster, the colours of one look MIN_APART degrees apart
    (the source hue counts as one of them in mode hue), a row for all but one monster of every `recolour pair` allow row."""
    t = rows() if table is None else table
    out, seen, by = [], set(), {}
    for r in t:
        sh = int(r['hue_shift'])
        if not 0 <= sh < 360:
            out.append('%s: hue_shift %d outside 0..359' % (r['monster'], sh))
        if r['mode'] not in ('hue', 'tint'):
            out.append('%s: mode %s' % (r['monster'], r['mode']))
        if r['monster'] in seen:
            out.append('%s is on two rows' % r['monster'])
        seen.add(r['monster'])
        by.setdefault(r['look'], []).append(r)
    for look, rs in by.items():
        hs = [(int(r['hue_shift']) + (int(r['source_hue']) if r['mode'] == 'hue' else 0)) % 360 for r in rs]
        if rs[0]['mode'] == 'hue':
            hs.append(int(rs[0]['source_hue']))
        for i, a in enumerate(hs):
            for b in hs[i + 1:]:
                d = abs(a - b) % 360
                if min(d, 360 - d) < MIN_APART:
                    out.append('look %s: two colours are less than %d degrees apart (%s)'
                               % (look, MIN_APART, ', '.join(r['monster'] for r in rs)))
                    break
    if t is not None and os.path.exists(allow) and table is None:
        with open(allow, newline='', encoding='utf-8') as f:
            for r in csv.DictReader(f):
                if r['status'] == 'recolour pair':
                    names = [n.strip() for n in r['names'].split('|')]
                    if sum(n in seen for n in names) < len(names) - 1:
                        out.append('allow row look %s (%s): fewer than all but one of them have a recolour row' % (r['look'], r['names']))
    return out


def main(argv):
    if argv[:1] == ['check']:
        p = problems()
        for line in p:
            print('PROBLEM', line)
        print('monster_recolour: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if argv[:1] == ['build']:
        print('the recolour pair waits for pair %d: nothing built' % MIN_PAIR)
        return 2
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

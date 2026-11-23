#!/usr/bin/env python3
"""Send offsets of the pair 36 effects redrawn IN PLACE (art_import/pack36_replace.csv) ->
server/data/lib/chaos_fx_send_offsets.lua.

    python3 -I client/tools/sprites/gen_fx_send_offsets.py           # write the Lua table
    python3 -I client/tools/sprites/gen_fx_send_offsets.py --check   # CI: the committed table is up to date
    python3 -I client/tools/sprites/gen_fx_send_offsets.py --pair Tibia.dat Tibia.spr   # also compare with a pair

The engine draws an effect bigger than a tile with its bottom-right tile on the tile it is sent to. gen_pack36_fx.py
rebuilt 141 stock and Chaos effect ids with pack art at a FIXED send offset 0,0: art reaching past the bottom-right
tile was moved up and left as a whole by (sx, sy) pixels (gen_pack36_fx.pull, 0 or negative). The effect's pivot (the
ring's middle, the spot the pack author meant: the tile centre or the feet) went with it, so it sits (sx, sy) up and
left of where it belongs. Position:sendMagicEffect (chaos_constants.lua) and the engine (src-patch 0060) send these
ids at the target tile + the offset below instead.

Offset per axis: the whole tiles that bring the pivot nearest to its place, (-sx + 16) // 32, from the pulls the build
records (art_import/pack36_replace_pivots.csv, written by `gen_pack36_fx.py build` from the pack art itself). The
pivot ends within 16 pixels of its place on each axis; a closer fit needs the art re-cut inside its tiles.

History. Owner 2026-10-22 ("a animação amarela está totalmente fora de centro": Banner Call's holy_spiral 405, a 5x5
pillar kept as 4x4, two tiles off): the first table sent every 3x3 and 4x4 art past its tile by the size of the art
(twin effects of the appended sets). Owner 2026-10-23 ("efeito fora de centro. mesma coisa com o efeito amarelo": the
blue teleport 11, streaks into a ring, drawn a tile down and right; the yellow holy 201 and 262 the same): a 3x3 art
whose pivot was pulled only a few pixels (the teleport's ring, 7 px) must not move at all, and the size of the art
says nothing about how far the pivot was pulled. An in-place effect whose pull is under 16 px on both axes is not
listed (2x2 art, the teleport 11 and summon portal 409 of 3x3 included).
Ids sent through ChaosVfx at their own offset (628 reflect_bubble) are not listed. Missiles are not shifted.

O736 (owner 2026-11-23: the pack effects "adaptados com a nossa qualidade"): pair_fixes/fx_send_offsets_extra.csv adds
effects of the appended packs whose art stands a tile off its target in a canvas too tight for recentre_effects.py to
move it (numbers only, measured on pair 81 and on the O734 form). A row is kept only when the whole-tile offset brings the
alpha centre under OFF_CENTRE px of the tile middle on the form the id has; `pair_from` holds a row until config.lua
`chaosClientPair` reaches that pair (the Lua table ChaosFxSendOffsetFrom, read by fx_send_offset_core.lua). An extra row
never names an in-place effect of the pack36 table, and its ChaosVfx entry sends at its own tile (dx = dy = 0, held by
server/tests/fx_send_offset_test.lua), so nothing is shifted twice.
Deterministic; stdlib only (--pair also needs numpy).
"""
import argparse
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'server', 'data', 'lib', 'chaos_fx_send_offsets.lua'))
MAX_RESIDUAL = 16  # px: the pivot is at most this far from its place after the whole-tile offset
EXTRA = os.path.join(HERE, 'pair_fixes', 'fx_send_offsets_extra.csv')
OFF_CENTRE = 16  # px: the O733 audit's off_centre limit; an extra row brings the alpha centre under it


def read(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def axis(pull):
    """whole tiles to send the effect past its target tile: the nearest to bringing a pivot pulled `pull` px
    (0 or negative) back; exactly half a tile rounds to the tile"""
    return (-pull + 16) // 32


def residual(pull, d):
    """pixels the pivot is still from its place after sending at +d tiles"""
    return pull + 32 * d


def pivots(art=ART):
    """{replace id: (pull_x, pull_y)} of the in-place effects"""
    return {int(r['replace']): (int(r['pull_x']), int(r['pull_y']))
            for r in read(os.path.join(art, 'pack36_replace_pivots.csv'))}


def offsets(art=ART):
    pv = pivots(art)
    out = []
    for r in read(os.path.join(art, 'pack36_replace.csv')):
        if r['kind'] != 'effect' or (int(r['dx']), int(r['dy'])) != (0, 0):
            continue
        i = int(r['replace'])
        if i not in pv:
            raise SystemExit(f"{r['name']} (effect {i}): no row in pack36_replace_pivots.csv; "
                             'run gen_pack36_fx.py build --src PACK_DIR')
        px, py = pv[i]
        dx, dy = axis(px), axis(py)
        if (dx, dy) != (0, 0):
            note = r['note'].replace('\n', ' ')
            out.append((i, dx, dy, f"{r['w']}x{r['h']}, {note}; pivot pulled {px},{py} px"))
    return sorted(out)


def check_table(art=ART):
    """problems of the in-place pivots and offsets (an empty list is fine): every in-place effect has its pivot row,
    no pull is positive or larger than its art, and the offset leaves every pivot within MAX_RESIDUAL px of its place"""
    try:
        pv = pivots(art)
    except OSError as e:
        return [f'pack36_replace_pivots.csv: {e}']
    errs = []
    listed = {i: (dx, dy) for i, dx, dy, _ in offsets(art)}
    for r in read(os.path.join(art, 'pack36_replace.csv')):
        if r['kind'] != 'effect' or (int(r['dx']), int(r['dy'])) != (0, 0):
            continue
        i = int(r['replace'])
        px, py = pv[i]
        if px > 0 or py > 0:
            errs.append(f"{r['name']}: a pull is 0 or negative, got {px},{py}")
        if -px > int(r['w']) * 32 or -py > int(r['h']) * 32:
            errs.append(f"{r['name']}: pull {px},{py} is larger than the art ({r['w']}x{r['h']} tiles)")
        d = listed.get(i, (0, 0))
        if abs(residual(px, d[0])) > MAX_RESIDUAL or abs(residual(py, d[1])) > MAX_RESIDUAL:
            errs.append(f"{r['name']}: offset {d} leaves the pivot {residual(px, d[0])},{residual(py, d[1])} px off")
    return errs


def extra(path=EXTRA):
    """[(id, dx, dy, pair_from or None, reason)] of pair_fixes/fx_send_offsets_extra.csv (O736), sorted by id"""
    out = []
    for r in read(path):
        pf = (r.get('pair_from') or '').strip()
        out.append((int(r['id']), int(r['dx']), int(r['dy']), int(pf) if pf else None, r['reason'].replace('\n', ' ')))
    return sorted(out)


def check_extra(art=ART, path=EXTRA):
    """problems of the extra rows (an empty list is fine): one row per id, no in-place effect of the pack36 table, a
    whole offset of 0..3 tiles that moves the effect, a pair gate of a real pair, a reason that gives the numbers"""
    try:
        rows = extra(path)
    except (OSError, KeyError, ValueError) as e:
        return [f'{os.path.basename(path)}: {e}']
    errs = []
    inplace = {int(r['replace']) for r in read(os.path.join(art, 'pack36_replace.csv')) if r['kind'] == 'effect'}
    seen = set()
    for i, dx, dy, pf, why in rows:
        if i in seen:
            errs.append(f'extra effect {i}: listed twice')
        seen.add(i)
        if i in inplace:
            errs.append(f'extra effect {i}: an in-place pack36 effect; its offset comes from its pivot')
        if not (0 <= dx <= 3 and 0 <= dy <= 3) or (dx, dy) == (0, 0):
            errs.append(f'extra effect {i}: offset {dx},{dy} is not 0..3 tiles that moves it')
        if pf is not None and not 27 <= pf <= 999:
            errs.append(f'extra effect {i}: pair_from {pf} is not a pair')
        if len(why.strip()) < 20:
            errs.append(f'extra effect {i}: the reason must give the numbers')
    return errs


def alpha_centre(t, s, dx, dy):
    """alpha centre of effect thing t (all phases and layers, pattern 0) in px from the middle of the tile it is meant
    for, sent dx, dy tiles past it (needs numpy and datspr.py)"""
    import numpy as np
    from datspr import sprite_index
    sx = sy = tot = 0.0
    for ph in range(t.phases):
        for ly in range(t.layers):
            for hh in range(t.h):
                for ww in range(t.w):
                    a = s.sprite(t.sprites[sprite_index(t, 0, 0, 0, ly, ph, ww, hh)])
                    if a is None:
                        continue
                    al = a[:, :, 3].astype(float)
                    ys, xs = np.nonzero(al)
                    if not len(xs):
                        continue
                    wt = al[ys, xs]  # tile (ww, hh) lies ww, hh tiles up and left of the sent tile
                    sx += float((xs + 0.5 - 32 * ww) @ wt)
                    sy += float((ys + 0.5 - 32 * hh) @ wt)
                    tot += float(wt.sum())
    if not tot:
        return None
    return sx / tot - 16 + 32 * dx, sy / tot - 16 + 32 * dy


def check_extra_pair(dat, spr, path=EXTRA):
    """the extra rows on a pair: an ungated row brings the alpha centre under OFF_CENTRE px; a gated row (its form comes
    with a later pair) is only printed. -> problems"""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    d, s = Dat(dat), Spr(spr)
    errs = []
    for i, dx, dy, pf, _ in extra(path):
        t = d.effects[i - 1]
        before, after = alpha_centre(t, s, 0, 0), alpha_centre(t, s, dx, dy)
        if after is None:
            errs.append(f'extra effect {i}: no art in this pair')
            continue
        dist = (after[0] ** 2 + after[1] ** 2) ** 0.5
        line = f'extra effect {i}: {before[0]:.1f},{before[1]:.1f} px -> {after[0]:.1f},{after[1]:.1f} px ({dist:.1f})'
        print(line + (f' (row from pair {pf})' if pf else ''))
        if pf is None and dist >= OFF_CENTRE:
            errs.append(line + f': not under {OFF_CENTRE} px')
    return errs


def check_pair(dat, spr, art=ART):
    """compare the pivots with the art of a pair (needs numpy and datspr.py): art pulled to the bottom-right tile ends
    exactly at that tile's right / bottom edge, art not pulled ends short of it. -> problems"""
    sys.path.insert(0, HERE)
    import numpy as np
    from datspr import Dat, Spr, sprite_index
    d, s = Dat(dat), Spr(spr)
    pv = pivots(art)
    errs = []
    for r in read(os.path.join(art, 'pack36_replace.csv')):
        if r['kind'] != 'effect' or (int(r['dx']), int(r['dy'])) != (0, 0):
            continue
        i = int(r['replace'])
        t = d.effects[i - 1]
        right = bottom = -1
        for ph in range(t.phases):
            for hh in range(t.h):
                for ww in range(t.w):
                    a = s.sprite(t.sprites[sprite_index(t, 0, 0, 0, 0, ph, ww, hh)])
                    if a is None:
                        continue
                    ys, xs = np.nonzero(a[:, :, 3] > 0)
                    if len(xs):  # tile (ww, hh) lies ww, hh tiles up and left of the sent tile
                        right = max(right, int(xs.max()) - ww * 32)
                        bottom = max(bottom, int(ys.max()) - hh * 32)
        px, py = pv[i]
        if (px < 0 and right != 31) or (px == 0 and right > 31) or (py < 0 and bottom != 31) or (py == 0 and bottom > 31):
            errs.append(f"{r['name']} (effect {i}): pivot pull {px},{py} but the art ends {right},{bottom} px from "
                        'the sent tile corner (31 when pulled)')
    return errs


def render(rows, extra_rows=()):
    L = ['-- GENERATED by client/tools/sprites/gen_fx_send_offsets.py from art_import/pack36_replace.csv,',
         '-- art_import/pack36_replace_pivots.csv and pair_fixes/fx_send_offsets_extra.csv.  Do not edit by hand.  Effect',
         '-- ids redrawn in place: the art keeps its bottom-right tile on the tile it is sent to and was moved up and left to',
         '-- fit, the effect\'s pivot with it, so Position:sendMagicEffect (chaos_constants.lua, fx_send_offset_core.lua)',
         '-- sends them at the target tile + {dx, dy} to bring the pivot back; an engine with src-patch 0060 takes this table',
         '-- (Game.setFxSendOffsets) and does it for every effect packet instead.  An id not listed is sent at the target',
         '-- tile.  O736 rows (pair_fixes/fx_send_offsets_extra.csv): pack effects whose art stands a tile off in a canvas',
         '-- too tight to move it; an id in ChaosFxSendOffsetFrom waits for config.lua chaosClientPair to reach that pair.',
         'ChaosFxSendOffset = {']
    allrows = list(rows) + [(i, dx, dy, why) for i, dx, dy, _pf, why in extra_rows]
    for i, dx, dy, note in sorted(allrows):
        L.append(f'\t[{i}] = {{{dx}, {dy}}},  -- {note}')
    L.append('}')
    L.append('ChaosFxSendOffsetFrom = {')
    for i, _dx, _dy, pf, _why in extra_rows:
        if pf is not None:
            L.append(f'\t[{i}] = {pf},')
    L.append('}')
    return '\n'.join(L) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--check', action='store_true', help='fail when the committed table differs')
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--pair', nargs=2, metavar=('DAT', 'SPR'), help='also compare the pivots with the art of a pair')
    a = ap.parse_args()
    errs = check_table() + check_extra() + (check_pair(*a.pair) + check_extra_pair(*a.pair) if a.pair else [])
    for e in errs:
        print(e, file=sys.stderr)
    if errs:
        return 1
    text = render(offsets(), extra())
    if a.check:
        try:
            with open(a.out, encoding='utf-8') as f:
                old = f.read()
        except OSError:
            old = None
        if old != text:
            print(f'{a.out} is out of date: run client/tools/sprites/gen_fx_send_offsets.py', file=sys.stderr)
            return 1
        print(f'{a.out}: up to date')
        return 0
    with open(a.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print(f'wrote {a.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

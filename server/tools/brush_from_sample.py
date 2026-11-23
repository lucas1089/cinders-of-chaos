#!/usr/bin/env python3
"""Map editor brush of a new ground from a painted sample map (O741).

    python3 -I server/tools/brush_from_sample.py SAMPLE.otbm --ground IDS --key SHORT [--name NAME] [--z ZORDER]
        [--under IDS] [--min-share 0.75] [--client-offset 3000] [--speed 150] [--json OUT] [--write [--art CSV]]

The owner paints the new ground (IDS: its server id, variants allowed, ranges like 36456-36458) in a small map, a few
shapes on any other ground (a blob, a 1-wide corridor, a notch, single tiles), and lays its border pieces by hand on
the lower tiles around it. This tool finds which item is which of the 12 pieces:

  - every tile of another ground (or of --under) whose 8 neighbours all exist gives a neighbour pattern: which of the
    8 neighbours are the new ground (one of 256)
  - the pieces a pattern needs come from our rule, ChaosAreaGenCore.borderPieces (areagen_core.lua; mirrored here as
    border_pieces, held equal on all 256 patterns by brush_from_sample_test.py in luajit and lua5.3); the map
    editor's own rule (editor_pieces, the rule gen_editor_brushes_test.py proves) differs on 80 patterns of three or
    four sides, so a tile is accepted under either rule and only the 176 patterns where both agree vote
  - a tile with one unknown piece votes for each item on it (the ground and the pieces already known left out); the
    most voted item wins the piece; rounds repeat until nothing changes, so a piece seen only beside another
    (a corner next to an edge) is still found
  - edges logic and the neighbour lookup are tools/map/derive_borders.py's (Grid, DIRS)

Report (stdout): tiles and patterns seen (of 256), each piece with its item, votes and share, then
  gaps       pieces no tile showed: paint the shape that needs them (an inner corner needs a notch)
  conflicts  a winner under --min-share, one item won by two pieces, an item that is also a ground, a tile whose
             items do not match its pattern (missing or extra piece, up to 10 positions each), a piece on a tile
             with no new-ground neighbour
Then, only when there is no gap and no conflict: the brush JSON in the format of gen_editor_brushes.py
(cinders_brushes.json: "borders" and "grounds", built by its own build_brushes) and the art_items.csv rows (the
columns and names of the pack rows; client id = server id - --client-offset, the pack's 3000). Exit 0 clean, 1 with
gaps or conflicts, 2 bad arguments.

--json OUT writes the brush JSON to OUT. --write appends the rows to server/data/items/art_items.csv (or --art);
it refuses a key or server id that is already there. Nothing is written without --write. Afterwards give the ground
a z order (EDITOR_Z of gen_editor_brushes.py or PACK of areaplan_build.lua) and run gen_editor_brushes.py.
The sample is only read. Deterministic. Needs numpy (tools/map/otbm.py)."""
import argparse
import collections
import csv
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))
import gen_editor_brushes as G  # noqa: E402

PIECES = G.SLOTS  # editor piece names: n e s w cnw cne csw cse dnw dne dse dsw
# order and words of the pack rows in art_items.csv (our piece names)
ROW_ORDER = ('n', 's', 'e', 'w', 'nw', 'ne', 'sw', 'se', 'in_nw', 'in_ne', 'in_sw', 'in_se')
WORDS = {'n': 'north edge', 's': 'south edge', 'e': 'east edge', 'w': 'west edge',
         'nw': 'north-west corner', 'ne': 'north-east corner', 'sw': 'south-west corner', 'se': 'south-east corner',
         'in_nw': 'north-west inner corner', 'in_ne': 'north-east inner corner',
         'in_sw': 'south-west inner corner', 'in_se': 'south-east inner corner'}
COLUMNS = ('client_id', 'server_id', 'key', 'kind', 'mode', 'name', 'size', 'otb_group', 'otb_flags', 'top_order',
           'speed', 'light_level', 'light_color', 'extra')
BITS = ('nw', 'n', 'ne', 'w', 'e', 'sw', 's', 'se')  # mask bit 0..7, as gen_editor_brushes_test.py
MAX_POS = 10


def border_pieces(n, e, s, w, ne, nw, se, sw):
    """ChaosAreaGenCore.borderPieces, line for line"""
    out, used = [], set()

    def pair(name, a, b):
        out.append(name)
        used.update((a, b))
    if n and w:
        pair('dnw', 'n', 'w')
    if n and e and 'n' not in used:
        pair('dne', 'n', 'e')
    if s and e and 'e' not in used:
        pair('dse', 's', 'e')
    if s and w and 's' not in used and 'w' not in used:
        pair('dsw', 's', 'w')
    for name, on in (('n', n), ('e', e), ('s', s), ('w', w)):
        if on and name not in used:
            out.append(name)
            used.add(name)
    for name, diag, a, b in (('cnw', nw, 'n', 'w'), ('cne', ne, 'n', 'e'), ('csw', sw, 's', 'w'),
                             ('cse', se, 's', 'e')):
        if diag and a not in used and b not in used:
            out.append(name)
    return out


def editor_pieces(v):
    """the map editor's rule (gen_editor_brushes_test.editor_pieces), v = {neighbour: bool}"""
    n, e, s, w = v['n'], v['e'], v['s'], v['w']
    pairs = (('dnw', n, w), ('dne', n, e), ('dse', s, e), ('dsw', s, w))
    if n + e + s + w == 2 and any(a and b for _, a, b in pairs):
        out = [name for name, a, b in pairs if a and b]
    else:
        out = [name for name, on in (('n', n), ('e', e), ('s', s), ('w', w)) if on]
    for name, diag, a, b in (('cnw', v['nw'], n, w), ('cne', v['ne'], n, e), ('csw', v['sw'], s, w),
                             ('cse', v['se'], s, e)):
        if diag and not a and not b:
            out.append(name)
    return out


def mask_of(v):
    return sum(1 << i for i, d in enumerate(BITS) if v[d])


def rules(v):
    """(ours, editor's) piece sets of one pattern"""
    ours = frozenset(border_pieces(v['n'], v['e'], v['s'], v['w'], v['ne'], v['nw'], v['se'], v['sw']))
    return ours, frozenset(editor_pieces(v))


def collect(m, over, under=None):
    """[(pos, mask, ours, editor's, ground, items above the ground)] of every lower tile next to the new ground,
    plus the same for lower tiles with no such neighbour (mask 0), and the set of ground ids seen"""
    import numpy as np
    from derive_borders import Grid, DIRS
    grid = Grid(m)
    over_a = np.array(sorted(over), np.int64)
    nb, present = {}, np.ones(len(grid.x), bool)
    for d, (dx, dy) in DIRS.items():
        gn = grid.ground_at(dx, dy)
        present &= gn >= 0
        nb[d] = np.isin(gn, over_a)
    lower = (grid.g > 0) & ~np.isin(grid.g, over_a)
    if under:
        lower &= np.isin(grid.g, np.array(sorted(under), np.int64))
    tiles = []
    for i in np.flatnonzero(lower & present):
        v = {d: bool(nb[d][i]) for d in DIRS}
        ours, ed = rules(v)
        stack = [int(s) for s in m.stack(i)]
        tiles.append(((int(grid.x[i]), int(grid.y[i]), int(grid.z[i])), mask_of(v), ours, ed, stack[0], stack[1:]))
    grounds = {int(x) for x in np.unique(grid.g) if x > 0}
    return tiles, grounds


def solve(tiles, over, grounds, min_share=0.75):
    """{piece: item}, stats, gaps, conflicts"""
    win, stats = {}, {}
    voting = [t for t in tiles if t[1] and t[2] == t[3]]
    while True:
        votes = collections.defaultdict(collections.Counter)
        nvote = collections.Counter()
        known_items = set(win.values())
        for pos, mask, ours, ed, ground, items in voting:
            unknown = [p for p in ours if p not in win]
            if len(unknown) != 1:
                continue
            p = unknown[0]
            nvote[p] += 1
            for it in set(items):
                if it not in known_items and it not in over and it not in grounds:
                    votes[p][it] += 1
        new = {}
        for p in PIECES:
            if p in win or not votes[p]:
                continue
            (it, n), = sorted(votes[p].items(), key=lambda kv: (-kv[1], kv[0]))[:1]
            new[p] = it
            stats[p] = (n, nvote[p], sorted(votes[p].items(), key=lambda kv: (-kv[1], kv[0]))[1:3])
        if not new:
            break
        win.update(new)
    gaps = [p for p in PIECES if p not in win]
    conflicts = []
    for p in PIECES:
        if p in stats:
            n, tot, rest = stats[p]
            if n < min_share * tot:
                conflicts.append('%s: item %d on %d of %d tiles (under %.0f%%), also %s'
                                 % (p, win[p], n, tot, 100 * min_share,
                                    ', '.join('%d x%d' % kv for kv in rest) or 'nothing'))
    by_item = collections.defaultdict(list)
    for p, it in win.items():
        by_item[it].append(p)
    for it, ps in sorted(by_item.items()):
        if len(ps) > 1:
            conflicts.append('item %d wins %d pieces: %s' % (it, len(ps), ' '.join(sorted(ps))))
    for p, it in sorted(win.items()):
        if it in grounds:
            conflicts.append('%s: item %d is also a ground of the sample' % (p, it))
    piece_of = {it: p for p, it in win.items()}
    bad = collections.defaultdict(list)
    for pos, mask, ours, ed, ground, items in tiles:
        have = {piece_of[it] for it in items if it in piece_of}
        if not mask:
            if have:
                bad['piece on a tile with no new-ground neighbour'].append((pos, sorted(have)))
            continue
        need_known = [r for r in (ours, ed)]
        if any(have == {p for p in r if p in win} for r in need_known):
            continue
        r = min(need_known, key=lambda r: len(have ^ set(r)))
        miss = sorted(p for p in r if p in win and p not in have)
        extra = sorted(have - set(r))
        what = []
        if miss:
            what.append('missing ' + ' '.join(miss))
        if extra:
            what.append('extra ' + ' '.join(extra))
        bad['pattern %d: %s' % (mask, ', '.join(what))].append((pos, None))
    for what, lst in sorted(bad.items()):
        poss = ' '.join('%d,%d,%d' % p for p, _ in lst[:MAX_POS])
        conflicts.append('%s on %d tile%s: %s%s' % (what, len(lst), '' if len(lst) == 1 else 's', poss,
                                                    ' ...' if len(lst) > MAX_POS else ''))
    return win, stats, gaps, conflicts


def art_rows(win, ground_id, key, name, client_offset=3000, speed=150):
    """art_items.csv rows (dicts of COLUMNS) of the ground and its 12 pieces"""
    ours = {G.PIECE_OF[p]: it for p, it in win.items()}
    rows = [dict(zip(COLUMNS, (ground_id - client_offset, ground_id, 'ground_' + key, 'ground', 'new', name, '1x1',
                               1, 0, 0, speed, 0, 0, '')))]
    for p in ROW_ORDER:
        it = ours[p]
        rows.append(dict(zip(COLUMNS, (it - client_offset, it, 'border_%s_%s' % (key, p), 'border', 'new',
                                       '%s (%s)' % (name, WORDS[p]), '1x1', 0, 8192, 1, 0, 0, 0, 'piece=' + p))))
    return rows


def csv_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=COLUMNS, lineterminator='\n')
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def brush(rows, key, z):
    """brush JSON (gen_editor_brushes.py format) from the rows, built by its own build_brushes"""
    items = []
    for r in rows:
        extra = {'piece': r['extra'][len('piece='):]} if r['extra'] else {}
        items.append({'key': r['key'], 'id': int(r['server_id']), 'kind': r['kind'], 'name': r['name'],
                      'extra': extra})
    return G.build_brushes(items, {key: z})


def append_rows(path, rows):
    """append rows to art_items.csv; refuses a key or server id already there"""
    with open(path, encoding='utf-8', newline='') as f:
        text = f.read()
    have = list(csv.DictReader(io.StringIO(text)))
    keys = {r['key'] for r in have}
    ids = {r['server_id'] for r in have}
    clash = [r['key'] for r in rows if r['key'] in keys] + ['id %s' % r['server_id'] for r in rows
                                                           if str(r['server_id']) in ids]
    if clash:
        raise SystemExit('%s already has: %s' % (path, ', '.join(clash)))
    if text and not text.endswith('\n'):
        text += '\n'
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text + csv_text(rows))


def run(a, out=sys.stdout):
    import otbm
    from derive_borders import parse_ids
    over = {int(i) for i in parse_ids(a.ground)}
    under = {int(i) for i in parse_ids(a.under)} if a.under else None
    m = otbm.load_map(a.sample)
    tiles, grounds = collect(m, over, under)
    win, stats, gaps, conflicts = solve(tiles, over, grounds, a.min_share)
    edged = [t for t in tiles if t[1]]
    p = lambda s='': print(s, file=out)  # noqa: E731
    p('sample %s: ground %s, %d lower tiles next to it, %d patterns of 256 seen (%d where both rules agree)'
      % (os.path.basename(a.sample), a.ground, len(edged), len({t[1] for t in edged}),
         len({t[1] for t in edged if t[2] == t[3]})))
    for piece in PIECES:
        if piece in win:
            n, tot, rest = stats[piece]
            p('  %-4s %-6s item %6d  %3d of %3d tiles %5.1f%%%s' % (
                piece, G.PIECE_OF[piece], win[piece], n, tot, 100.0 * n / max(1, tot),
                ('  also ' + ', '.join('%d x%d' % kv for kv in rest)) if rest else ''))
        else:
            p('  %-4s %-6s none' % (piece, G.PIECE_OF[piece]))
    if gaps:
        p('gaps: ' + ' '.join(gaps) + ' (paint a shape that needs them: an inner corner d.. needs a notch, an outer'
          ' corner c.. a convex corner)')
    for c in conflicts:
        p('conflict: ' + c)
    if gaps or conflicts:
        p('no brush: %d gap%s, %d conflict%s' % (len(gaps), '' if len(gaps) == 1 else 's', len(conflicts),
                                                  '' if len(conflicts) == 1 else 's'))
        return 1
    ground_id = min(over)
    rows = art_rows(win, ground_id, a.key, a.name, a.client_offset, a.speed)
    text = G.render(brush(rows, a.key, a.z))
    if a.json:
        with open(a.json, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        p('wrote ' + a.json)
    else:
        p('brush JSON:')
        out.write(text)
    p('art_items.csv rows:')
    out.write(csv_text(rows))
    if a.write:
        append_rows(a.art, rows)
        p('appended %d rows to %s' % (len(rows), a.art))
        p('next: z order %d into EDITOR_Z of gen_editor_brushes.py (or PACK of areaplan_build.lua), then run'
          ' python3 -I server/tools/gen_editor_brushes.py' % a.z)
    return 0


def main(argv, out=sys.stdout):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('sample')
    ap.add_argument('--ground', required=True, help='server id(s) of the new ground')
    ap.add_argument('--key', required=True, help='short name, a-z and _: ground_KEY, border_KEY_PIECE')
    ap.add_argument('--name', help='item name (default: KEY with spaces)')
    ap.add_argument('--z', type=int, default=3400, help='editor z order (default 3400)')
    ap.add_argument('--under', help='only these lower grounds count (default: every other ground)')
    ap.add_argument('--min-share', type=float, default=0.75)
    ap.add_argument('--client-offset', type=int, default=3000)
    ap.add_argument('--speed', type=int, default=150)
    ap.add_argument('--json', help='write the brush JSON here')
    ap.add_argument('--write', action='store_true', help='append the rows to --art')
    ap.add_argument('--art', default=G.ART_ITEMS)
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if not re.fullmatch(r'[a-z][a-z_]*', a.key):
        print('--key: lower case letters and _ only', file=sys.stderr)
        return 2
    a.name = a.name or a.key.replace('_', ' ')
    if not os.path.exists(a.sample):
        print('no sample map: ' + a.sample, file=sys.stderr)
        return 2
    return run(a, out)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

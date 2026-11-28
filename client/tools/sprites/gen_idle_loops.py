#!/usr/bin/env python3
"""The owner's 24 idle loops in the sprite pair (O787; joins client pair 92): each item animates in place.

    python3 -I gen_idle_loops.py recipe SRC.json OUT.json --pair DAT SPR [--keep-1x1]
                                                  # a loop json of idle_loop.py (made on another pair) -> a recipe on this
                                                  #   pair: the same layers, seed, frames and timing, the source digest of DAT
    python3 -I gen_idle_loops.py make DAT SPR [--write]   # pair 91: draw every recipe, every pattern; the house rules of
                                                  #   idle_loop.py on each; --write writes idle_loops.csv and .sums, else
                                                  #   both must be what the recipes draw
    python3 -I gen_idle_loops.py build DAT SPR OUT_DIR    # pair 91 -> OUT_DIR/Tibia.dat, Tibia.spr (the pair 92 step)
    python3 -I gen_idle_loops.py live DAT SPR             # the pair holds every loop at its item, pixel for pixel (pair 92);
                                                  #   the still form passes as pending while client_pair.PAIR_ASSETS < 92
    python3 -I gen_idle_loops.py check                    # CI, no pair: recipes, table, sums and the wire rows agree

Owner 2026-11-28 ("Todos a"): option A of the X1 preview for all 24 items (art_import/idle_loops/<client id>.json, the
loops of idle_loop.py: docs/SPRITE_FORGE.md). The recipes are text only: the art is drawn again from the pair by the tool
(the still is the item's first phase, base layer of each pattern of pair 91), so no picture is committed.

In place: the same client id and the same server item; the flags stay byte for byte (light, walkability, minimap, stack);
the entry gets the loop's phases, one duration a phase (the json's ms) and an animator that runs on its own (async 1, loop
0, start 0); new sprite records are appended to the spr, every other entry and record byte-identical.

Size: a recipe with `pad` draws on 64 x 64 with the still at the bottom right, so the thing becomes 2 x 2 (exact size 64).
The client anchors a thing at its bottom right tile, so the still stands on its own tile pixel for pixel and the flames or
motes rise over the tiles north and west, as our 2 x 2 braziers do; the size changes no flag, so walkability and what
blocks stay. A pickupable item is never padded: a container slot draws a 2 x 2 thing at half size in its corner (or spills
over the next slots), so these keep 1 x 1 and the loop is clamped to 32 x 32 (`--keep-1x1`; table column `kept_1x1`).
A thing with position patterns (px x py, the client picks one by the tile) gets one loop per pattern, drawn over that
pattern's still with the same recipe.

Wire bytes: a thing with more than one phase is read with a phase byte, so every server node of these client ids needs
FLAG_ANIMATION, but only once the client has pair 92: server/data/items/item_wire_idle.csv (install step `idleloops`,
server/tools/install_idle_loops.py, behind client_pair.PAIR_IDLE_LOOPS; check_item_wire.py --table-check reads it too).

Needs numpy and Pillow (the fx venv of CI).
"""
import argparse
import csv
import hashlib
import io
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))

import idle_loop as IL  # noqa: E402

RECIPES = os.path.join(HERE, 'art_import', 'idle_loops')
TABLE = os.path.join(HERE, 'art_import', 'idle_loops.csv')
SUMS = os.path.join(HERE, 'art_import', 'idle_loops.sums')
WIRE = os.path.join(REPO, 'server', 'data', 'items', 'item_wire_idle.csv')
PAIR = 92                                            # client_pair.PAIR_IDLE_LOOPS
SOURCE_PAIR = 91
SOURCE_DAT_MD5 = 'ab6f6fe60ca3697ec05df614a06a1ad8'  # pair 91 (client/MANIFEST.md "Pair 91")
CELL = 32
ANIM_HEAD = (1, 0, 0)                                # async, loop forever, start at phase 0
COLUMNS = ('n', 'client_id', 'name', 'tiles', 'pad', 'kept_1x1', 'patterns', 'frames', 'ms', 'exact', 'layers', 'clamp')


# ------------------------------------------------------------------------------------------------------------ recipes
def recipe_paths(folder=RECIPES):
    return sorted((os.path.join(folder, f) for f in os.listdir(folder) if f.endswith('.json')),
                  key=lambda p: json.load(open(p))['n'])


def recipes(folder=RECIPES):
    out = []
    for p in recipe_paths(folder):
        r = json.load(open(p))
        r['_path'] = p
        out.append(r)
    return out


def layer_text(r):
    return ' + '.join('%s%s' % (s['effect'], ' %d' % s['amount'] if s.get('amount') and s['effect'] in IL.AMOUNT else '')
                      + (' x%d' % s['repeats'] if s['repeats'] != 1 else '') for s in r['layers'])


def tiles_of_recipe(r):
    return r['size'][0] // CELL


# ----------------------------------------------------------------------------------------------------------- the pair
def file_md5(path):
    return IL.file_md5(path)


def open_pair(dat, spr):
    import datspr
    return datspr.Dat(dat), datspr.Spr(spr)


def thing_canvas(t, spr, x=0, y=0, phase=0):
    """the thing's picture of pattern (x, y) and phase, layer 0: tiles at the bottom right (datspr.render_thing), as the
    spr gives them back (a transparent pixel reads 0, 0, 0, 0)"""
    from datspr import sprite_index
    out = np.zeros((t.h * CELL, t.w * CELL, 4), np.uint8)
    for hh in range(t.h):
        for ww in range(t.w):
            a = spr.sprite(t.sprites[sprite_index(t, x, y, 0, 0, phase, ww, hh)])
            if a is not None:
                y0, x0 = (t.h - 1 - hh) * CELL, (t.w - 1 - ww) * CELL
                out[y0:y0 + CELL, x0:x0 + CELL] = a
    out[out[..., 3] == 0] = 0
    return out


def digest(frames):
    h = hashlib.sha256()
    for f in frames:
        f = np.ascontiguousarray(f, np.uint8)
        h.update(('%dx%d;' % (f.shape[1], f.shape[0])).encode())
        h.update(f.tobytes())
    return h.hexdigest()


def draw(r, t, spr):
    """{(x, y): (frames, problems)} of a recipe over each pattern still of thing t"""
    out = {}
    for y in range(t.py):
        for x in range(t.px):
            still = thing_canvas(t, spr, x, y)
            try:
                frames, errs, _meta = IL.build(still, r['layers'], r['frames'], r['ms'], r['seed'], r['soft'], r['theme'],
                                               r.get('clamp'), r.get('pad', False), r.get('element'))
            except ValueError as e:
                frames, errs = [], [str(e)]
            out[(x, y)] = (frames, errs, still)
    return out


def holds(t, r):
    """the thing can take the loop in place: one group of one layer, no z pattern, one phase, the recipe's canvas"""
    tiles = tiles_of_recipe(r)
    if len(t.groups) != 1 or t.layers != 1 or t.pz != 1 or t.phases != 1:
        return 'item %d: %d groups, %d layers, pz %d, %d phases (one of each expected)' % (t.id, len(t.groups), t.layers,
                                                                                         t.pz, t.phases)
    if t.w != t.h or (t.w != tiles and not (r.get('pad') and t.w == 1 and tiles == 2)):
        return 'item %d: %dx%d, the recipe draws %d x %d px' % (t.id, t.w, t.h, r['size'][0], r['size'][1])
    if r.get('pad') and 'pickupable' in t.flags:
        return 'item %d is pickupable: never padded (a container slot draws it at half size); keep it 1 x 1' % t.id
    return None


# ---------------------------------------------------------------------------------------------------------- recipe cmd
def cmd_recipe(args):
    src = json.load(open(args.src))
    d, s = open_pair(*args.pair)
    cid = src['pair']['item']
    t = d.items[cid - 100]
    r = {k: src[k] for k in ('frames', 'ms', 'seed', 'soft', 'theme', 'element', 'layers', 'clamp', 'pad')}
    if args.keep_1x1:
        r['pad'] = False
    r.update({'tool': 'gen_idle_loops.py (idle_loop.py layers)', 'n': args.n, 'name': args.name or src.get('name', ''),
              'client_id': cid, 'option': args.option, 'kept_1x1': bool(args.keep_1x1 and src.get('pad')),
              'patterns': [t.px, t.py], 'pair': {'item': cid, 'dat_md5': file_md5(args.pair[0])}})
    src_w = t.w * CELL
    r['size'] = [IL.PAD, IL.PAD] if r['pad'] else [src_w, src_w]
    why = holds(t, r)
    if why:
        raise SystemExit(why)
    bad = [(xy, e) for xy, (_f, e, _s) in draw(r, t, s).items() if e]
    with open(args.out, 'w') as f:
        json.dump(r, f, indent=1, sort_keys=True)
        f.write('\n')
    print('%s -> %s: item %d, %d pattern(s), %s' % (args.src, args.out, cid, t.px * t.py,
                                                    'PASS' if not bad else 'FAIL: %s' % bad))
    return 1 if bad else 0


# ------------------------------------------------------------------------------------------------------------ make
def table_rows(rs, things):
    rows = []
    for r in rs:
        t = things[r['client_id']]
        tiles = tiles_of_recipe(r)
        exact = t.exact if tiles == t.w else CELL * tiles
        rows.append({'n': r['n'], 'client_id': r['client_id'], 'name': r['name'], 'tiles': '%dx%d' % (tiles, tiles),
                     'pad': int(bool(r.get('pad'))), 'kept_1x1': int(bool(r.get('kept_1x1'))),
                     'patterns': '%dx%d' % tuple(r['patterns']), 'frames': r['frames'], 'ms': r['ms'], 'exact': exact,
                     'layers': layer_text(r), 'clamp': r.get('clamp') or ''})
    return rows


def table_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, COLUMNS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def sums_text(lines):
    head = ('# idle loops of pair %d (O787, gen_idle_loops.py make --write on pair %d, dat md5 %s)\n'
            '# client_id pattern_x pattern_y: sha256 of the still (pair %d, phase 0) and of the loop frames (gen_idle_loops.digest)\n'
            % (PAIR, SOURCE_PAIR, SOURCE_DAT_MD5, SOURCE_PAIR))
    return head + ''.join('%d %d %d before %s after %s\n' % ln for ln in lines)


def read_sums(path=SUMS):
    out = {}
    for ln in open(path, encoding='utf-8'):
        if ln.startswith('#') or not ln.strip():
            continue
        p = ln.split()
        out[(int(p[0]), int(p[1]), int(p[2]))] = (p[4], p[6])
    return out


def make(dat, spr, folder=RECIPES, source_md5=SOURCE_DAT_MD5, log=print):
    """(table rows, sums lines, {cid: {(x, y): frames}}, problems) of every recipe drawn on the source pair"""
    md5 = file_md5(dat)
    if md5 != source_md5:
        raise SystemExit('%s: dat md5 %s, the recipes are drawn on pair %d (%s)' % (dat, md5, SOURCE_PAIR, source_md5))
    d, s = open_pair(dat, spr)
    rs = recipes(folder)
    things, drawn, lines, bad = {}, {}, [], []
    for r in rs:
        cid = r['client_id']
        if r['pair']['dat_md5'] != source_md5:
            bad.append('%s: made on dat %s, not pair %d' % (os.path.basename(r['_path']), r['pair']['dat_md5'], SOURCE_PAIR))
        t = d.items[cid - 100]
        things[cid] = t
        why = holds(t, r)
        if why:
            bad.append(why)
            continue
        if [t.px, t.py] != r['patterns']:
            bad.append('item %d: patterns %dx%d, the recipe says %s' % (cid, t.px, t.py, r['patterns']))
        drawn[cid] = {}
        for (x, y), (frames, errs, still) in sorted(draw(r, t, s).items(), key=lambda kv: (kv[0][1], kv[0][0])):
            if errs:
                bad.append('item %d pattern %d,%d: %s' % (cid, x, y, '; '.join(errs)))
                continue
            drawn[cid][(x, y)] = frames
            lines.append((cid, x, y, digest([still]), digest(frames)))
        log('item %5d %-24s %s %d frame(s) of %d ms, %d pattern(s)%s' % (
            cid, r['name'][:24], '%dx%d' % (tiles_of_recipe(r), tiles_of_recipe(r)), r['frames'], r['ms'], t.px * t.py,
            ', kept 1x1' if r.get('kept_1x1') else ''))
    return table_rows(rs, things), lines, drawn, bad


def cmd_make(args):
    rows, lines, _drawn, bad = make(args.dat, args.spr)
    if bad:
        for b in bad:
            print('FAIL', b)
        return 1
    tt, st = table_text(rows), sums_text(lines)
    if args.write:
        open(TABLE, 'w', encoding='utf-8').write(tt)
        open(SUMS, 'w', encoding='utf-8').write(st)
        print('wrote %s (%d rows), %s (%d lines)' % (TABLE, len(rows), SUMS, len(lines)))
        return 0
    stale = [p for p, txt in ((TABLE, tt), (SUMS, st)) if open(p, encoding='utf-8').read() != txt]
    print('make: %d loops, %d patterns, all pass the house rules; %s' % (
        len(rows), len(lines), 'table and sums current' if not stale else 'STALE: %s (run --write)' % ', '.join(stale)))
    return 1 if stale else 0


# ------------------------------------------------------------------------------------------------------------ build
def build(dat, spr, out_dir, folder=RECIPES, sums=SUMS, source_md5=SOURCE_DAT_MD5, log=print):
    import import_art_things as iat
    import import_donor_things as idt
    from datspr import Dat, Spr, sprite_index
    if os.path.abspath(os.path.dirname(os.path.abspath(dat))) == os.path.abspath(out_dir):
        raise SystemExit('out-dir must differ from the input dir')
    _rows, lines, drawn, bad = make(dat, spr, folder, source_md5, log=lambda *_a: None)
    if bad:
        raise SystemExit('the loops do not pass on this pair:\n' + '\n'.join(bad))
    if sums:
        want = read_sums(sums)
        got = {(c, x, y): (b, a) for c, x, y, b, a in lines}
        if want != got:
            diff = sorted(k for k in set(want) | set(got) if want.get(k) != got.get(k))
            raise SystemExit('the loops differ from %s: %s' % (sums, diff[:8]))
    rs = {r['client_id']: r for r in recipes(folder)}
    od, ospr = Dat(dat), Spr(spr)
    d = od.data
    ours = idt.parse_dat(d, idt.OUR_KINDS)
    items = {t.id: t for t in ours['item']}
    newrecs, have, entries = [], {}, {}
    for cid in sorted(drawn):
        r, t, dt = rs[cid], items[cid], od.items[cid - 100]
        if idt.entry_bytes('item', t.flags, t.groups) != d[t.raw[0]:t.raw[1]] or len(t.groups) != 1:
            raise SystemExit('item %d: one group that round-trips is expected; refusing' % cid)
        tiles, n, ms = tiles_of_recipe(r), r['frames'], r['ms']
        px, py = dt.px, dt.py
        shp = iat.Shape(tiles, tiles, 1, px, py, n)
        sids = [0] * (tiles * tiles * px * py * n)
        for (x, y), frames in drawn[cid].items():
            for ph, cell in enumerate(frames):
                assert cell.shape == (tiles * CELL, tiles * CELL, 4)
                for (ww, hh), tile in iat.tiles_of(cell, tiles, tiles).items():
                    rec = iat.encode_sprite(tile)
                    if rec is None:
                        continue
                    if rec not in have:
                        newrecs.append(rec)
                        have[rec] = ospr.count + len(newrecs)
                    sids[sprite_index(shp, x, y, 0, 0, ph, ww, hh)] = have[rec]
        exact = dt.exact if tiles == dt.w else CELL * tiles
        g = dict(gtype=0, w=tiles, h=tiles, exact=exact, layers=1, px=px, py=py, pz=1, phases=n,
                 anim=(ANIM_HEAD, (ms,) * (2 * n)), sprites=tuple(sids))
        entries[cid] = (t.raw, idt.entry_bytes('item', t.flags, [g]))
    out = bytearray()
    pos = 0
    for cid in sorted(entries, key=lambda c: entries[c][0][0]):
        (a, b), e = entries[cid]
        out += d[pos:a] + e
        pos = b
    out += d[pos:]
    os.makedirs(out_dir, exist_ok=True)
    dat_path, spr_path = os.path.join(out_dir, 'Tibia.dat'), os.path.join(out_dir, 'Tibia.spr')
    with open(dat_path, 'wb') as f:
        f.write(out)
    idt.write_spr(spr_path, ospr.signature, ospr.m, ospr.count, newrecs)
    md, ms_ = Dat(dat_path), Spr(spr_path)
    assert md.counts == od.counts and ms_.count == ospr.count + len(newrecs)
    nt = idt.parse_dat(bytes(out), idt.OUR_KINDS)
    same = 0
    for cat in idt.CATS:
        assert len(nt[cat]) == len(ours[cat])
        for to, tn in zip(ours[cat], nt[cat]):
            if cat == 'item' and to.id in entries:
                assert tn.flags == to.flags, 'item %d: flags changed' % to.id
                continue
            assert bytes(out[tn.raw[0]:tn.raw[1]]) == d[to.raw[0]:to.raw[1]], (cat, to.id, 'entry changed')
            same += 1
    log('wrote %s (%s bytes, md5 %s), %s (%s bytes; %d sprite records appended, %d to %d); %d items rewritten in '
        'place, %d entries byte-identical' % (dat_path, f'{len(out):,}', hashlib.md5(out).hexdigest(), spr_path,
                                              f'{os.path.getsize(spr_path):,}', len(newrecs), ospr.count,
                                              ospr.count + len(newrecs), len(entries), same))
    probs, pend = live(dat_path, spr_path, folder, sums, pending_ok=False)
    if probs:
        raise SystemExit('live on the output:\n' + '\n'.join(probs))
    return dat_path, spr_path


# ------------------------------------------------------------------------------------------------------------- live
def live(dat, spr, folder=RECIPES, sums=SUMS, pending_ok=None):
    """(problems, pending items): every recipe's item in its loop form, pixel for pixel; the still form (one phase, the
    sums' `before` digest) counts as pending while pending_ok (default: client_pair.PAIR_ASSETS < PAIR)"""
    if pending_ok is None:
        import client_pair
        pending_ok = client_pair.PAIR_ASSETS < PAIR
    d, s = open_pair(dat, spr)
    want = read_sums(sums)
    bad, pend = [], []
    for r in recipes(folder):
        cid = r['client_id']
        if not 100 <= cid < 100 + len(d.items):
            bad.append('item %d is not in the pair' % cid)
            continue
        t = d.items[cid - 100]
        pats = [(x, y) for y in range(t.py) for x in range(t.px)]
        if [t.px, t.py] != r['patterns']:
            bad.append('item %d: patterns %dx%d, the recipe says %s' % (cid, t.px, t.py, r['patterns']))
            continue
        if t.phases == 1:
            stills = [digest([thing_canvas(t, s, x, y)]) == want.get((cid, x, y), ('', ''))[0] for x, y in pats]
            if all(stills) and pending_ok:
                pend.append(cid)
            elif all(stills):
                bad.append('item %d still has its one phase (pair %d form): the loop is not in this pair' % (cid, SOURCE_PAIR))
            else:
                bad.append('item %d: one phase and not the pair %d still' % (cid, SOURCE_PAIR))
            continue
        tiles, n = tiles_of_recipe(r), r['frames']
        if (len(t.groups), t.w, t.h, t.layers, t.pz, t.phases) != (1, tiles, tiles, 1, 1, n):
            bad.append('item %d: %dx%d, %d layers, pz %d, %d phases; the loop is %dx%d of %d' % (
                cid, t.w, t.h, t.layers, t.pz, t.phases, tiles, tiles, n))
            continue
        if t.anim is None or tuple(t.anim[:3]) != ANIM_HEAD or set(t.anim[3]) != {r['ms']}:
            bad.append('item %d: animator %s, want %s and %d ms a phase' % (cid, t.anim and t.anim[:3], ANIM_HEAD, r['ms']))
        for x, y in pats:
            got = digest([thing_canvas(t, s, x, y, ph) for ph in range(n)])
            if got != want.get((cid, x, y), ('', ''))[1]:
                bad.append('item %d pattern %d,%d: the frames differ from the sums' % (cid, x, y))
    return bad, pend


def cmd_live(args):
    bad, pend = live(args.dat, args.spr)
    for b in bad:
        print('FAIL', b)
    n = len(recipes())
    if pend and not bad:
        print('live: %d of %d items still in the pair %d form: pending (client_pair.PAIR_ASSETS < %d)' % (
            len(pend), n, SOURCE_PAIR, PAIR))
    print('live: %d items, %d problems' % (n, len(bad)))
    return 1 if bad else 0


# ------------------------------------------------------------------------------------------------------------ check
def wire_rows(path=WIRE):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def check(folder=RECIPES, table=TABLE, sums=SUMS, wire=WIRE, expect=24, source_md5=SOURCE_DAT_MD5):
    """problems of the committed files, without a pair"""
    bad = []
    rs = recipes(folder)
    if len(rs) != expect:
        bad.append('%d recipes, the owner picked %d' % (len(rs), expect))
    if [r['n'] for r in rs] != list(range(1, len(rs) + 1)):
        bad.append('recipes are not numbered 1..%d' % len(rs))
    if len({r['client_id'] for r in rs}) != len(rs):
        bad.append('a client id twice')
    rows = list(csv.DictReader(open(table, encoding='utf-8')))
    want = read_sums(sums)
    for r in rs:
        cid, name = r['client_id'], os.path.basename(r['_path'])
        if name != '%02d_%d.json' % (r['n'], cid):
            bad.append('%s: named %02d_%d.json' % (name, r['n'], cid))
        if r['pair']['dat_md5'] != source_md5 or r['pair']['item'] != cid:
            bad.append('%s: not drawn on item %d of pair %d' % (name, cid, SOURCE_PAIR))
        if not IL.FRAMES_MIN <= r['frames'] <= IL.FRAMES_MAX or not IL.MS_MIN <= r['ms'] <= IL.MS_MAX:
            bad.append('%s: %d frames of %d ms' % (name, r['frames'], r['ms']))
        if r['size'] not in ([32, 32], [64, 64]) or (r['pad'] and r['size'] != [64, 64]):
            bad.append('%s: canvas %s' % (name, r['size']))
        if r.get('kept_1x1') and r['pad']:
            bad.append('%s: kept 1x1 and padded' % name)
        for s in r['layers']:
            if s['effect'] not in IL.EFFECTS:
                bad.append('%s: effect %s' % (name, s['effect']))
        row = [x for x in rows if int(x['client_id']) == cid]
        if len(row) != 1:
            bad.append('item %d: %d table rows' % (cid, len(row)))
        else:
            row = row[0]
            exp = {'n': str(r['n']), 'name': r['name'], 'tiles': '%dx%d' % ((tiles_of_recipe(r),) * 2),
                   'pad': str(int(bool(r['pad']))), 'kept_1x1': str(int(bool(r.get('kept_1x1')))),
                   'patterns': '%dx%d' % tuple(r['patterns']), 'frames': str(r['frames']), 'ms': str(r['ms']),
                   'layers': layer_text(r), 'clamp': str(r.get('clamp') or '')}
            for k, v in exp.items():
                if row[k] != v:
                    bad.append('item %d: table %s %r, the recipe says %r' % (cid, k, row[k], v))
        pats = [(cid, x, y) for y in range(r['patterns'][1]) for x in range(r['patterns'][0])]
        if [k for k in want if k[0] == cid] != pats:
            bad.append('item %d: sums lines %s, want %s' % (cid, [k for k in want if k[0] == cid], pats))
    if len(rows) != len(rs):
        bad.append('%d table rows for %d recipes' % (len(rows), len(rs)))
    wired = {}
    for w in wire_rows(wire):
        wired.setdefault(int(w['client']), []).append(w)
        if w['animation'] != '1' or w['group'] != '':
            bad.append('item_wire_idle.csv server %s: animation %s group %r (1 and empty: the loop has phases)'
                       % (w['server'], w['animation'], w['group']))
    for r in rs:
        if r['client_id'] not in wired:
            bad.append('item %d: no server node in item_wire_idle.csv (the phase byte)' % r['client_id'])
    extra = sorted(set(wired) - {r['client_id'] for r in rs})
    if extra:
        bad.append('item_wire_idle.csv names client ids without a loop: %s' % extra)
    return bad


def cmd_check(_args):
    bad = check()
    for b in bad:
        print('FAIL', b)
    print('check: %d recipes, %d problems' % (len(recipes()), len(bad)))
    return 1 if bad else 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('recipe')
    r.add_argument('src')
    r.add_argument('out')
    r.add_argument('--pair', nargs=2, required=True, metavar=('DAT', 'SPR'))
    r.add_argument('--keep-1x1', action='store_true')
    r.add_argument('--n', type=int, required=True)
    r.add_argument('--name', default='')
    r.add_argument('--option', default='A')
    m = sub.add_parser('make')
    m.add_argument('dat')
    m.add_argument('spr')
    m.add_argument('--write', action='store_true')
    b = sub.add_parser('build')
    b.add_argument('dat')
    b.add_argument('spr')
    b.add_argument('out_dir')
    lv = sub.add_parser('live')
    lv.add_argument('dat')
    lv.add_argument('spr')
    sub.add_parser('check')
    a = p.parse_args(argv)
    if a.cmd == 'recipe':
        return cmd_recipe(a)
    if a.cmd == 'make':
        return cmd_make(a)
    if a.cmd == 'build':
        build(a.dat, a.spr, a.out_dir)
        return 0
    if a.cmd == 'live':
        return cmd_live(a)
    return cmd_check(a)


if __name__ == '__main__':
    sys.exit(main())

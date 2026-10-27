#!/usr/bin/env python3
"""Pair 50: append the owner-approved things of two purchased sprite sources (source G and source F) to COPIES of our
10.98 Tibia.dat / Tibia.spr in one pass, and write the server data for them.

python3 -I import_pair50.py --ours-dat pair49/Tibia.dat --ours-spr pair49/Tibia.spr --out-dir pair50 \
    --src-g-dat G.dat --src-g-spr G.spr --src-f-dat F.dat --src-f-spr F.spr \
    [--sel-g pair50_G_selection.csv --sel-f pair50_F_selection.csv] [--expect item=39197,outfit=2681,effect=4101] \
    [--manifest-out ../../../server/data/items/pair50_items.csv] [--outfits-out ../../../server/data/items/pair50_outfits.csv] \
    [--effects-out ../../../server/data/items/pair50_effects.csv] [--report-out pair50_import.csv] [--dry-run]

Input: the two selection files (category, src_kind, src_id, name, biome, size, notes: ground, wall, stairs, decoration
(decor in source G), monster, effect, missile), source G rows first, then source F, each in file order. Both sources are
10.98 pairs (u32 sprite ids, frame groups, animator); the F spr is not loaded, its records are read one by one through
a memory map. The pair 49 spr is streamed to the output (the offset table grows by 4 bytes per new sprite).

What is taken (the owner: "Pegue tudo que possamos usar. Inclusive chao, parede, escadas, decoracao e monstros"):
  items     ground, wall, stairs and decoration things become new items after the last item of the input, in selection
            order. The dat flags are the source's (ground speed, blocking, hangable, hooks, light, animation, top
            order, elevation, ...); not copied: the market block, wrappable / unwrappable (house furniture) and
            source bytes outside the 10.98 table. A decoration marked as a corpse gets the container and forceuse flags
            when it has none. Ladders get the usable flag (the use action of data/scripts/chaos/pair50_items.lua).
  monsters  become new outfits (looktypes) after the last outfit, with all their frame groups. Taken only when every group
            has the 4 directions and the groups agree on layers and patterns (check_pair.py's error); the flags are
            reduced to light, displacement and animate-always.
  effects   become new effects after the last effect (ids above 255 work: GameMagicEffectU16 and the 16 bit effect id of
            the server); the flags are reduced to light, displacement, animate-always and top effect.
  missiles  none: the protocol sends a missile as one byte, 254 is CONST_ANI_WEAPONTYPE and the pair already holds 253,
            so no id is free (check_pair.py warns above 254). Every missile row is reported as skipped.
Skipped too, with the reason in the report: a thing the source lacks (stops the run), things with no visible pixel, wider or
taller than 16 tiles, more than 8 layers, or a monster that lacks directions.

Server data: --manifest-out (items.otb / items.xml manifest for server/tools/install_pair50_items.py: client id, server id =
client id + 4000, key pair50_<category>_<client id>, otb group / flags / top order, ground speed, light, plus category,
role, floorchange, use, corpse, biome, source, src id), --outfits-out (look type, name, size, frames), --effects-out
(effect id, key, size, frames, ms, light, send offset), --report-out (every selection row: new id or skip reason).
Sprites already in the input spr (the same record bytes) are reused, the others are appended once; nothing of the sources
is committed (the repo holds this tool, the selections and the generated tables).

Verification (always): the output dat re-parses (same variant as ours) and every new entry has the expected flags, groups,
sizes, patterns, phases and animator; every sprite slot of every new thing decodes pixel-identical to its source slot;
composed frames are compared for every 10th thing; every old dat entry is byte-identical and 3000 sampled old sprites are
unchanged; then check_pair.py's append-only guard. Deterministic: the same inputs give byte-identical outputs.
"""
import argparse
import csv
import hashlib
import os
import random
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import import_donor_things as idt  # noqa: E402
from datspr import Dat, Spr, TABLE_NEW  # noqa: E402

CATS = idt.CATS
FIRST = idt.FIRST
NEW_BYTE = idt.NEW_BYTE
SERVER_OFFSET = 4000
CAT_KIND = {'ground': 'item', 'wall': 'item', 'stairs': 'item', 'decor': 'item', 'decoration': 'item',
            'monster': 'outfit', 'effect': 'effect', 'missile': 'missile'}
KEEP_NON_ITEM = {'outfit': {'light', 'displacement', 'animateAlways'},
                 'effect': {'light', 'displacement', 'animateAlways', 'topeffect'}, 'missile': {'light', 'displacement'}}
DROP_ITEM = {'market', 'wrappable', 'unwrappable'}
MAX_PHASES_MS = 1 << 31
# items.otb flag bits of the base server's itemloader (as install_pack_items / import_art_things)
SOLID, MISSILE, PATH, USEABLE, PICKUP, MOVE, STACK = 1, 2, 4, 16, 32, 64, 128
ONTOP, HANG, ANIM, FORCEUSE = 1 << 13, 1 << 16, 1 << 24, 1 << 26
MANIFEST_COLS = ['client_id', 'server_id', 'key', 'name', 'kind', 'piece', 'size', 'patterns', 'phases', 'frame_ms', 'speed',
                 'otb_group', 'otb_flags', 'top_order', 'light_level', 'light_color', 'minimap', 'dat_flags',
                 'category', 'role', 'floorchange', 'use', 'corpse', 'biome', 'source', 'src_id']
OUTFIT_COLS = ['look_type', 'key', 'name', 'size', 'frame_groups', 'biome', 'source', 'src_id']
EFFECT_COLS = ['effect_id', 'key', 'name', 'size', 'phases', 'ms', 'light_level', 'light_color', 'dx', 'dy', 'biome', 'source',
               'src_id']
REPORT_COLS = ['source', 'category', 'src_kind', 'src_id', 'name', 'status', 'new_id', 'server_id', 'reason']


# ------------------------------------------------------------------------------------------------ selection and rules
def read_selection(path, tag):
    rows = []
    with open(path, newline='', encoding='utf-8') as fh:
        for n, r in enumerate(csv.DictReader(fh), 2):
            cat = r['category'].strip()
            if cat not in CAT_KIND:
                raise SystemExit(f'{path}:{n}: unknown category {cat!r}')
            if CAT_KIND[cat] != r['src_kind']:
                raise SystemExit(f'{path}:{n}: category {cat} is a {CAT_KIND[cat]}, not a {r["src_kind"]}')
            rows.append({'tag': tag, 'cat': 'decor' if cat == 'decoration' else cat, 'kind': CAT_KIND[cat],
                         'src_id': int(r['src_id']), 'name': r['name'].strip(), 'biome': r['biome'].strip(),
                         'size': r['size'].strip(), 'notes': r['notes'].strip()})
    return rows


def dedupe(rows):
    """(kept rows, dropped [(row, kept row)]): a thing selected twice (source F lists eight skull step pieces as wall pieces
    and as stairs; their flags are those of walkable steps) is kept once, as stairs when one of its rows is stairs, else the
    first row"""
    best = {}
    for r in rows:
        k = (r['tag'], r['kind'], r['src_id'])
        if k not in best or (r['cat'] == 'stairs' and best[k]['cat'] != 'stairs'):
            best[k] = r
    kept = [r for r in rows if best[(r['tag'], r['kind'], r['src_id'])] is r]
    return kept, [(r, best[(r['tag'], r['kind'], r['src_id'])]) for r in rows if best[(r['tag'], r['kind'], r['src_id'])] is not r]


def note_role(notes):
    m = re.search(r'role=([A-Za-z_0-9]+)', notes)
    return m.group(1) if m else ''


def classify(row):
    """(category, role, floorchange, use, corpse) of an item row. category: ground, wall, stairs, decor or corpse.
    Stairs: the selection's role (stairs_up / stairs_down / ladder / hole). A stairs-up piece changes the floor towards
    the way its steps climb on screen: every set is drawn climbing up and to the left, so horizontal treads lead north
    and vertical treads west; stairs-down and holes go down. Source G rows carry no role: its ladders (named Ladder N) get
    the ladder use action, its other steps and pits no floor change (their direction and whether they go up or down is
    not in the selection)."""
    cat, notes, name = row['cat'], row['notes'], row['name']
    role = note_role(notes)
    corpse = cat == 'decor' and ('corpse' in notes.lower() or 'corpse' in name.lower())
    if cat == 'decor':
        return ('corpse' if corpse else 'decor'), role, '', '', corpse
    if cat != 'stairs':
        return cat, role, '', '', False
    if row['tag'] == 'G' and not role:
        role = 'ladder' if name.lower().startswith('ladder') else ''
    fc, use = '', ''
    if role in ('stairs_down', 'hole'):
        fc = 'down'
    elif role == 'stairs_up':
        fc = 'north' if 'treads horizontal' in notes else 'west' if 'treads vertical' in notes else ''
    elif role == 'ladder':
        use = 'ladder'
    return 'stairs', role, fc, use, False


def our_flags(t, cat, row_class=None):
    """our flag list [(byte, payload)] sorted by byte. Items keep the source's flags (not the market block, wrappable,
    unwrappable or bytes outside the 10.98 table); the others only the ones of KEEP_NON_ITEM. row_class: (category,
    role, floorchange, use, corpse) of an item: ladders get usable, corpses container and forceuse."""
    last = {}
    for b, v in t.flags:
        name = TABLE_NEW.get(b)
        if name is None:
            continue
        if t.cat == 'item':
            if name in DROP_ITEM:
                continue
        elif name not in KEEP_NON_ITEM[t.cat]:
            continue
        last[b] = v
    if row_class:
        category, role, fc, use, corpse = row_class
        if use == 'ladder':
            last.setdefault(NEW_BYTE['usable'], b'')
        if corpse:
            last.setdefault(NEW_BYTE['container'], b'')
            last.setdefault(NEW_BYTE['forceuse'], b'')
    return sorted(last.items())


def otb_of(names, phases, row_class):
    """(group, flags, top order) of an item: the rules of install_decor49_items / import_donor_things.otb_row (ground group 1,
    containers 2, notwalkable = solid + path, blockmissile, pickup / move / stack, top order from clip / bottom / top),
    but a dat blockpath alone only asks the path finder to avoid the tile (otb path), it does not block walking; wall
    decoration that hangs sets the hangable flag; ladders are useable; corpses are force-use containers."""
    category, role, fc, use, corpse = row_class
    group = 1 if 'ground' in names else 2 if ('container' in names or corpse) else 0
    fl = 0
    if 'notwalkable' in names:
        fl |= SOLID | PATH
    elif 'blockpath' in names:
        fl |= PATH
    if 'blockmissile' in names:
        fl |= MISSILE
    if 'pickupable' in names:
        fl |= PICKUP
        if 'notmoveable' not in names and 'ground' not in names:
            fl |= MOVE
    if 'stackable' in names:
        fl |= STACK
    top = 1 if 'clip' in names else 2 if 'bottom' in names else 3 if 'top' in names else 0
    if top:
        fl |= ONTOP
    if 'hangable' in names:
        fl |= HANG
    if phases > 1:
        fl |= ANIM
    if use == 'ladder':
        fl |= USEABLE
    if corpse:
        fl |= FORCEUSE
    return group, fl, top


def slug(s):
    return re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')[:40]


def fx_offset(w, h):
    """whole tiles to send an effect of w x h tiles past its target tile so its middle lands on the target (the engine draws
    the bottom-right tile on the target): the same rule as the ChaosVfx entries of the other pairs (1 for 2 and 3 tiles,
    2 for 4)"""
    return (w // 2, h // 2)


# ------------------------------------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--src-g-dat', required=True); ap.add_argument('--src-g-spr', required=True)
    ap.add_argument('--src-f-dat', required=True); ap.add_argument('--src-f-spr', required=True)
    ap.add_argument('--sel-g', default=os.path.join(HERE, 'pair50_G_selection.csv'))
    ap.add_argument('--sel-f', default=os.path.join(HERE, 'pair50_F_selection.csv'))
    ap.add_argument('--expect', default=None, help='e.g. item=39197,outfit=2681,effect=4101: the input must end there')
    ap.add_argument('--manifest-out', default=None); ap.add_argument('--outfits-out', default=None)
    ap.add_argument('--effects-out', default=None); ap.add_argument('--report-out', default=None)
    ap.add_argument('--dry-run', action='store_true', help='plan and count, write nothing')
    a = ap.parse_args()
    t0 = time.time()

    def log(s):
        print(s, flush=True)
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'

    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), f'expected our 10.98 dat: {od.variant}'
    assert ospr.u32count and ospr.alpha
    d = od.data
    ours = idt.parse_dat(d, idt.OUR_KINDS)
    n_old = {c: len(ours[c]) for c in CATS}
    last_old = {c: n_old[c] + FIRST[c] - 1 for c in CATS}
    log('ours: last ids ' + ', '.join(f'{c} {last_old[c]}' for c in CATS) + f'; spr {ospr.count} sprites')
    for spec in (a.expect or '').split(','):
        if spec:
            c, v = spec.split('=')
            if last_old[c] != int(v):
                raise SystemExit(f'the input ends at {c} {last_old[c]}, expected {v}: wrong input pair (or already imported)')

    sources = {}
    for tag, dp, sp in (('G', a.src_g_dat, a.src_g_spr), ('F', a.src_f_dat, a.src_f_spr)):
        data, things, spr, profile = idt.open_source(dp, sp, 'library')
        spr._cache = type('NoCache', (dict,), {'get': lambda s, k, dflt=None: None, '__setitem__': lambda s, k, v: None})()
        sources[tag] = ({c: {t.id: t for t in things[c]} for c in CATS}, spr)
        log(f'source {tag}: ' + ', '.join(f'{len(things[c])} {c}s' for c in CATS) + f'; spr {spr.count} sprites')
        del data, things
    rows = read_selection(a.sel_g, 'G') + read_selection(a.sel_f, 'F')
    rows, dropped = dedupe(rows)
    log(f'selection: {len(rows)} rows ({sum(r["tag"] == "G" for r in rows)} source G, {sum(r["tag"] == "F" for r in rows)} source F)')

    # --- choose things
    nxt = {c: last_old[c] + 1 for c in CATS}
    chosen = {c: [] for c in CATS}       # (row, thing, flags, new id, class)
    report = []
    skips = {}

    def skip(r, why):
        skips.setdefault((r['kind'], why), []).append(r)
        report.append([r['tag'], r['cat'], r['kind'], r['src_id'], r['name'], 'skipped', '', '', why])

    for r, kept in dropped:
        report.append([r['tag'], r['cat'], r['kind'], r['src_id'], r['name'], 'skipped', '', '',
                       f'selected twice, kept as {kept["cat"]}'])
    for r in rows:
        tmap, sspr = sources[r['tag']]
        if r['kind'] == 'missile':
            skip(r, 'no free missile id: the protocol sends one byte, 254 is CONST_ANI_WEAPONTYPE and the pair holds 253')
            continue
        t = tmap[r['kind']].get(r['src_id'])
        if t is None:
            raise SystemExit(f'source {r["tag"]} has no {r["kind"]} {r["src_id"]}')
        idt.drop_empty_groups(t)
        if any(g['w'] > idt.MAX_WH or g['h'] > idt.MAX_WH or g['layers'] > idt.MAX_LAYERS for g in t.groups):
            skip(r, 'wider or taller than 16 tiles, or more than 8 layers')
            continue
        if any(s and s > sspr.count for g in t.groups for s in g['sprites']):
            skip(r, 'sprite id beyond the source spr')
            continue
        if r['kind'] == 'outfit':
            if any(g['px'] != 4 for g in t.groups):
                skip(r, 'not 4 directions')
                continue
            if len({(g['layers'], g['px'], g['py'], g['pz']) for g in t.groups}) > 1:
                skip(r, 'frame groups differ in layers or patterns')
                continue
        # blank: not a single visible sprite
        if not any(idt.record(sspr, s) is not None for g in t.groups for s in set(g['sprites']) if s):
            skip(r, 'no visible pixel')
            continue
        for g in t.groups:                       # the client's rule (check_pair exact-size): 32 up to 32 x size
            if (g['w'] > 1 or g['h'] > 1) and g['exact'] < 32:
                g['exact'] = 32
        cls = classify(r) if r['kind'] == 'item' else None
        flags = our_flags(t, r['kind'], cls)
        nid = nxt[r['kind']]
        nxt[r['kind']] += 1
        chosen[r['kind']].append((r, t, flags, nid, cls))
        report.append([r['tag'], r['cat'], r['kind'], r['src_id'], r['name'], 'imported', nid,
                       nid + SERVER_OFFSET if r['kind'] == 'item' else '', ''])
    if nxt['item'] - 1 + SERVER_OFFSET > 0xFFFF or nxt['outfit'] - 1 > 0xFFFF or nxt['effect'] - 1 > 0xFFFF:
        raise SystemExit('ids above 65535')
    log('chosen: ' + ', '.join(f'{len(chosen[c])} {c}s ({chosen[c][0][3]}-{chosen[c][-1][3]})' if chosen[c] else f'0 {c}s'
                               for c in CATS))
    for (kind, why), lst in sorted(skips.items()):
        log(f'skipped {len(lst)} {kind}s: {why}')

    # --- sprites: reuse identical records of ours, append the rest once
    log('indexing our sprite records...')
    m = ospr.m
    ours_rec = {}
    offs = ospr.offs
    for sid in range(ospr.count, 0, -1):               # lowest id wins
        o = int(offs[sid - 1])
        if o:
            ln = struct.unpack_from('<H', m, o + 3)[0]
            ours_rec[hashlib.md5(m[o:o + 5 + ln]).digest()] = sid
    log(f'  {len(ours_rec)} distinct records')
    smaps = {'G': {0: 0}, 'F': {0: 0}}
    newrecs, newidx = [], {}
    reused = 0
    for cat in CATS:
        for r, t, flags, nid, cls in chosen[cat]:
            smap, sspr = smaps[r['tag']], sources[r['tag']][1]
            for g in t.groups:
                for s in g['sprites']:
                    if s in smap:
                        continue
                    rec = idt.record(sspr, s)
                    if rec is None:
                        smap[s] = 0
                        continue
                    h = hashlib.md5(rec).digest()
                    if h in ours_rec:
                        smap[s] = ours_rec[h]; reused += 1
                    else:
                        if h not in newidx:
                            newrecs.append(rec); newidx[h] = ospr.count + len(newrecs)
                        smap[s] = newidx[h]
    nbytes = sum(len(x) for x in newrecs)
    log(f'sprites: {len(newrecs)} new records ({nbytes:,} bytes), {reused} slots reuse records of ours')
    out_size = len(m) + 4 * len(newrecs) + nbytes
    log(f'output spr would be {out_size:,} bytes')
    if a.dry_run:
        log(f'dry run: nothing written ({time.time() - t0:.0f}s)')
        return
    st = os.statvfs(os.path.dirname(os.path.abspath(a.out_dir)) or '.')
    if st.f_bavail * st.f_frsize < out_size + (64 << 20):
        raise SystemExit(f'not enough disk space for the output spr ({out_size:,} bytes, free {st.f_bavail * st.f_frsize:,})')

    # --- dat: each category's new entries go right after its last old entry
    ends = {'item': ours['outfit'][0].raw[0], 'outfit': ours['effect'][0].raw[0], 'effect': ours['missile'][0].raw[0],
            'missile': len(d)}
    starts = {'item': 12, 'outfit': ends['item'], 'effect': ends['outfit'], 'missile': ends['effect']}
    out = bytearray(d[:12])
    for cat in CATS:
        blob = b''.join(idt.entry_bytes(cat, flags, t.groups, smaps[r['tag']]) for r, t, flags, nid, cls in chosen[cat])
        out += d[starts[cat]:ends[cat]] + blob
    cnt = tuple(nxt[c] - 1 for c in CATS)
    struct.pack_into('<HHHH', out, 4, *cnt)
    os.makedirs(a.out_dir, exist_ok=True)
    dat_path = os.path.join(a.out_dir, 'Tibia.dat'); spr_path = os.path.join(a.out_dir, 'Tibia.spr')
    open(dat_path, 'wb').write(out)
    idt.write_spr(spr_path, ospr.signature, m, ospr.count, newrecs)
    log(f'wrote {dat_path} ({len(out):,} bytes), {spr_path}')

    # --- verification
    md = Dat(dat_path); ms = Spr(spr_path)
    assert md.variant == od.variant, md.variant
    assert md.counts == cnt, md.counts
    assert ms.count == ospr.count + len(newrecs) and ms.signature == ospr.signature and md.max_sprite <= ms.count
    nt = idt.parse_dat(bytes(out), idt.OUR_KINDS)
    for cat in CATS:
        for to in ours[cat]:
            tn = nt[cat][to.id - FIRST[cat]]
            assert out[tn.raw[0]:tn.raw[1]] == d[to.raw[0]:to.raw[1]], (cat, to.id, 'old entry changed')
    nslots = nframes = 0
    for tag in ('G', 'F'):
        pairs = [(t, nt[cat][nid - FIRST[cat]], flags) for cat in CATS for r, t, flags, nid, cls in chosen[cat]
                 if r['tag'] == tag]
        s_, f_ = idt.verify_things(pairs, sources[tag][1], ms, log, sample_every=10)
        nslots += s_; nframes += f_
    random.seed(1)
    for sid in random.sample(range(1, ospr.count + 1), min(3000, ospr.count)) + [1, ospr.count]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log(f'verified: output parses (datspr {md.variant}) to EOF; {sum(len(v) for v in chosen.values())} new things: {nslots} '
        f'sprite slots pixel-identical to the source, {nframes} composed frames identical, flags as converted; every old '
        f'item, outfit, effect and missile byte-identical; 3000 sampled old sprites unchanged')
    from check_pair import check_append_only
    check_append_only(a.ours_dat, a.ours_spr, dat_path, spr_path, log=log)

    # --- tables
    if a.manifest_out:
        with open(a.manifest_out, 'w', newline='') as fh:
            w = csv.DictWriter(fh, MANIFEST_COLS, lineterminator='\n'); w.writeheader()
            for r, t, flags, nid, cls in chosen['item']:
                category, role, fc, use, corpse = cls
                row = idt.otb_row(nid, SERVER_OFFSET, r['name'], t, flags, 'pair50', category)
                names = {TABLE_NEW.get(b) for b, _ in flags}
                row['otb_group'], row['otb_flags'], row['top_order'] = otb_of(names, t.groups[0]['phases'], cls)
                row['kind'] = 'ground' if row['otb_group'] == 1 else 'object'
                row['key'] = f'pair50_{category}_{nid}'
                row.update({'category': category, 'role': role, 'floorchange': fc, 'use': use, 'corpse': int(corpse),
                            'biome': r['biome'], 'source': r['tag'], 'src_id': r['src_id']})
                w.writerow({k: row[k] for k in MANIFEST_COLS})
        log('manifest ' + a.manifest_out)
    if a.outfits_out:
        with open(a.outfits_out, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n'); w.writerow(OUTFIT_COLS)
            for r, t, flags, nid, cls in chosen['outfit']:
                w.writerow([nid, f'pair50_monster_{nid}', r['name'], idt.size_of(t), idt.frames_text(t), r['biome'], r['tag'],
                            r['src_id']])
        log('outfits ' + a.outfits_out)
    if a.effects_out:
        with open(a.effects_out, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n'); w.writerow(EFFECT_COLS)
            for r, t, flags, nid, cls in chosen['effect']:
                g = t.groups[0]
                ms_total = sum(g['anim'][1][1::2]) if g['anim'] else 0    # the long end of each phase
                ll, lc = 0, 0
                for b, v in flags:
                    if TABLE_NEW.get(b) == 'light':
                        ll, lc = struct.unpack('<HH', v)
                dx, dy = fx_offset(g['w'], g['h'])
                w.writerow([nid, f'p50_{slug(r["name"])}_{nid}', r['name'], idt.size_of(t), g['phases'], ms_total, ll, lc, dx, dy,
                            r['biome'], r['tag'], r['src_id']])
        log('effects ' + a.effects_out)
    if a.report_out:
        with open(a.report_out, 'w', newline='') as fh:
            w = csv.writer(fh, lineterminator='\n'); w.writerow(REPORT_COLS)
            w.writerows(report)
        log('report ' + a.report_out)
    log(f'done in {time.time() - t0:.0f}s')


if __name__ == '__main__':
    main()

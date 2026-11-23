#!/usr/bin/env python3
"""House audit fixer: the safe mechanical fixes of the house audit (server/README.md "House audit (O513)", fixer O742).

usage: python3 -I server/tools/fix_houses.py SERVER_DIR [--dry-run | --write] [--out FILE] [--houses FILE] [--known FILE]
                                             [--limit N]
       python3 -I server/tools/fix_houses.py --map FILE.otbm --items ITEMS.otb [--xml ITEMS.xml] --houses FILE [same options]

Runs audit_houses.py, then plans a fix for each finding that has one that needs no judgement, and lists the rest for a
human. The default is --dry-run: the plan and the counts by kind are printed, nothing is written. --write applies the
plan; --out FILE writes the fixed map there instead of over the world map.
Fix kinds (only tile flags change; the house id, the items and every other attribute of the tile stay byte for byte):
  PZ_ADD     HOUSE_FLAGS "protection zone on N of M tiles": the house tiles without the protection zone flag get it
             (the engine makes every house tile a protection zone anyway; the flag on the map only says so)
  PVP_CLEAR  HOUSE_FLAGS "PvP zone flag on N tile(s)": the PvP zone flag of those house tiles is cleared
For a human (listed, never touched; docs/MAP_GUIDE.md "Map editing rules": a house is never added, removed, resized or
moved by a tool): MULTI_FLOOR, NO_DOOR, DOOR_UNREACHABLE, ENTRY_BLOCKED, SIZE, ROOF_SHARE. The audit has no code for a
house tile outside the walls, a room tile inside the walls without the house id, an overlap or a door outside the house:
each of those would change the shape of a house, so there is no fix for them here either.
A finding of the known list (--known, default house_audit_known.csv, the audit's) was looked at and left: not fixed.
--write goes through map_write_guard.py (O512): only the planned tiles may differ, each must be exactly the bytes the
fixer meant, every other tile and node identical, or nothing is replaced (the new file stays at <map>.tmp). The old map
is kept as <map>.bak when there is none. Idempotent: after a write the audit has no fixable finding and a second run plans
nothing. The live run waits for the owner's go (README). Exit 0 on success, 1 on a refusal. Python 3 and numpy.
Test: fix_houses_test.py (synthetic map, a guard refusal case).
"""
import os
import shutil
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'map'))

import audit_houses as H  # noqa: E402
import audit_map_tiles as A  # noqa: E402
import map_write_guard as MG  # noqa: E402

FIX_KINDS = ('PZ_ADD', 'PVP_CLEAR')
HUMAN_CODES = ('MULTI_FLOOR', 'NO_DOOR', 'DOOR_UNREACHABLE', 'ENTRY_BLOCKED', 'SIZE', 'ROOF_SHARE')
T_AREA, T_TILE, T_HOUSETILE = 4, 5, 14
A_TILEFLAGS, A_ITEM = 3, 9


class FixError(Exception):
    pass


def plan(w, found, known=None):
    """-> ({pos: (old flags, new flags)}, {kind: [(house, pos)]}, [(house, code, detail)] for a human,
    [(house, code)] known and left)"""
    known = known or {}
    t = w.m.tiles
    hid = t['house'].astype(np.int64)
    fl = t['flags'].astype(np.int64)
    X, Y, Z = (t[k].astype(np.int64) for k in ('x', 'y', 'z'))
    tiles, by_kind, human, left = {}, {k: [] for k in FIX_KINDS}, [], []
    for h, rows in sorted(found.items()):
        for code, detail in rows:
            if (h, code) in known:
                left.append((h, code))
            elif code in HUMAN_CODES:
                human.append((h, code, detail))
        if (h, 'HOUSE_FLAGS') in known or not any(c == 'HOUSE_FLAGS' for c, _d in rows):
            continue
        idx = np.flatnonzero(hid == h)
        f = fl[idx]
        pz = (f & H.TF_PZ) > 0
        for k in idx[(~pz) & pz.any()].tolist():
            p = (int(X[k]), int(Y[k]), int(Z[k]))
            old = tiles.get(p, (int(fl[k]), int(fl[k])))
            tiles[p] = (old[0], old[1] | H.TF_PZ)
            by_kind['PZ_ADD'].append((h, p))
        for k in idx[(f & H.TF_PVP) > 0].tolist():
            p = (int(X[k]), int(Y[k]), int(Z[k]))
            old = tiles.get(p, (int(fl[k]), int(fl[k])))
            tiles[p] = (old[0], old[1] & ~H.TF_PVP)
            by_kind['PVP_CLEAR'].append((h, p))
    return tiles, by_kind, human, left


def _unesc(b):
    out, i = bytearray(), 0
    while i < len(b):
        if b[i] == MG.FD:
            i += 1
        out.append(b[i])
        i += 1
    return bytes(out)


def _esc(b):
    return b.replace(b'\xfd', b'\xfd\xfd').replace(b'\xfe', b'\xfd\xfe').replace(b'\xff', b'\xfd\xff')


def _new_payload(pl, kind, flags, pos):
    """the tile payload (unescaped, after the type byte) with its tile flags attribute set to `flags` (dropped at 0)"""
    head = 2 + (4 if kind == T_HOUSETILE else 0)
    if len(pl) < head:
        raise FixError('the tile %d,%d,%d is too short' % pos)
    attrs, q = [], head
    while q < len(pl):
        at = pl[q]
        if at == A_TILEFLAGS and q + 5 <= len(pl):
            q += 5
            continue
        if at == A_ITEM and q + 3 <= len(pl):
            attrs.append(pl[q:q + 3])
            q += 3
            continue
        raise FixError('the tile %d,%d,%d has an attribute %d this fixer does not know; nothing written' % (pos + (at,)))
    fb = bytes([A_TILEFLAGS]) + struct.pack('<I', flags) if flags else b''
    return pl[:head] + fb + b''.join(attrs)


def rewrite(data, tiles):
    """the map bytes with the tile flags of `tiles` ({pos: new flags}) set; -> (new bytes, {pos: new raw tile node})"""
    if not tiles:
        return data, {}
    a = np.frombuffer(data, np.uint8)
    mk, _esc_at = MG._markers(a)
    mk = mk[mk >= 4]
    is_start = a[mk] == MG.FE
    depth = np.cumsum(np.where(is_start, 1, -1))
    bases = {(x & 0xFF00, y & 0xFF00, z) for x, y, z in tiles}
    cuts, expect = [], {}
    s4 = np.flatnonzero(is_start & (depth == 4))
    e4 = np.flatnonzero(~is_start & (depth == 3))
    e3 = np.flatnonzero(~is_start & (depth == 2))
    for k in np.flatnonzero(is_start & (depth == 3)).tolist():
        off = int(mk[k])
        if a[off + 1] != T_AREA:
            continue
        head = MG._unesc_head(data, off + 2, 5)
        if len(head) < 5:
            continue
        bx, by, bz = struct.unpack('<HHB', bytes(head))
        if (bx, by, bz) not in bases:
            continue
        end = e3[np.searchsorted(e3, k)]
        for j in s4[np.searchsorted(s4, k):np.searchsorted(s4, end)].tolist():
            s = int(mk[j])
            kind = int(a[s + 1])
            if kind not in (T_TILE, T_HOUSETILE):
                continue
            xy = MG._unesc_head(data, s + 2, 2)
            pos = (bx + xy[0], by + xy[1], bz)
            if pos not in tiles:
                continue
            e = int(mk[e4[np.searchsorted(e4, j)]])
            pend = int(mk[j + 1])
            pl = _new_payload(_unesc(data[s + 2:pend]), kind, tiles[pos], pos)
            raw = data[s:s + 2] + _esc(pl) + data[pend:e + 1]
            cuts.append((s, e, raw))
            expect[pos] = raw
    gone = set(tiles) - set(expect)
    if gone:
        raise FixError('%d planned tile(s) not found in the map file (first %d,%d,%d)' % ((len(gone),) + sorted(gone)[0]))
    out, at = bytearray(), 0
    for s, e, raw in sorted(cuts):
        out += data[at:s] + raw
        at = e + 1
    out += data[at:]
    return bytes(out), expect


def report(tiles, by_kind, human, left, limit=20, log=print):
    for k in FIX_KINDS:
        log('%-16s %5d tile(s) in %d house(s)' % (k, len(by_kind[k]), len({h for h, _p in by_kind[k]})))
    log('%d tile(s) to rewrite; %d finding(s) for a human; %d known and left' % (len(tiles), len(human), len(left)))
    for k in FIX_KINDS:
        for n, (h, p) in enumerate(by_kind[k]):
            if n >= limit:
                log('  ... %d more %s (--limit N)' % (len(by_kind[k]) - n, k))
                break
            log('%s house=%d tile=%d,%d,%d: flags %d -> %d' % ((k, h) + p + tiles[p]))
    for n, (h, code, detail) in enumerate(human):
        if n >= limit:
            log('  ... %d more for a human (audit_houses.py --csv lists all)' % (len(human) - n))
            break
        log('HUMAN %s house=%d: %s' % (code, h, detail))


def run(server_dir=None, map_file=None, otb=None, xml=None, houses_file=None, known_path=H.KNOWN, write=False, out=None,
        limit=20, log=print):
    if server_dir:
        import patch_base_houses
        ddir = A.data_dir(server_dir)
        map_file = map_file or A.map_path(ddir)
        otb = otb or os.path.join(ddir, 'items', 'items.otb')
        xml = xml or os.path.join(ddir, 'items', 'items.xml')
        houses_file = houses_file or patch_base_houses.house_file(ddir)
    if not map_file or not os.path.isfile(map_file):
        raise FixError('no map (give SERVER_DIR with data/world/<map>.otbm, or --map)')
    if not houses_file or not os.path.isfile(houses_file):
        raise FixError('no house file (data/world/<mapName>-house.xml, or --houses)')
    data = open(map_file, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise FixError('the world map is compressed; unpack it first')
    w, _f = A.load_world(map_file, otb, xml, log=lambda *_: None, tables=dict(borders={}, grounds={}, walls={}))
    houses = H.read_houses(houses_file)
    found, _meta = H.audit(w, houses)
    tiles, by_kind, human, left = plan(w, found, H.read_known(known_path))
    report(tiles, by_kind, human, left, limit, log)
    summary = dict(tiles=len(tiles), kinds={k: len(v) for k, v in by_kind.items()}, human=len(human), known=len(left))
    if not tiles:
        log('house fixer: nothing to fix')
        return summary
    if not write and not out:
        log('house fixer: dry run, nothing written (--write applies the plan)')
        return summary
    new, expect = rewrite(data, {p: v[1] for p, v in tiles.items()})
    target = out or map_file
    tmp = target + '.tmp'
    with open(tmp, 'wb') as fh:
        fh.write(new)
    MG.verify(FixError, map_file, tmp, log=log, change=set(tiles), expect=expect)
    if not out:
        bak = map_file + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_file, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('house fixer: %d tile(s) rewritten in %s' % (len(tiles), target))
    return summary


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--houses', '--known', '--map', '--items', '--xml', '--limit', '--out'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--dry-run', '--write'):
            opts[a] = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            print('unknown option %s' % a)
            return 1
        else:
            pos.append(a)
        i += 1
    if len(pos) > 1 or (not pos and '--map' not in opts):
        print(__doc__)
        return 1
    if opts.get('--dry-run') and (opts.get('--write') or opts.get('--out')):
        print('--dry-run with --write or --out: choose one')
        return 1
    try:
        limit = int(opts.get('--limit', 20))
    except ValueError:
        print('bad --limit')
        return 1
    try:
        run(pos[0] if pos else None, opts.get('--map'), opts.get('--items'), opts.get('--xml'), opts.get('--houses'),
            opts.get('--known', H.KNOWN), bool(opts.get('--write')), opts.get('--out'), limit)
    except (FixError, H.HouseAuditError, A.AuditError, OSError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

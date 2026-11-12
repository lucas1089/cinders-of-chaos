#!/usr/bin/env python3
"""Splice guard for every tool that rewrites the world map (server/README.md "Map write guard (O512)").

A writer calls check() just before it replaces the map with its new file:

    import map_write_guard as G
    G.check(old_map, new_tmp, add=ADDED, change=CHANGED, remove=REMOVED, expect=NEW_TILE_BYTES)
    os.replace(new_tmp, old_map)

ADDED, CHANGED, REMOVED are sets of (x, y, z): the tiles the writer meant to add, rewrite and cut out. check() reads
both files in one streaming pass each (24 MiB chunks, numpy; no tile tree is built) and proves:
  1. both files parse to the end: identifier, one root node, balanced nodes, no stray bytes after the root, no
     dangling escape;
  2. every tile outside ADDED / CHANGED / REMOVED is byte for byte the same in both files (items, attributes, tile
     flags, house id: the raw bytes of the tile node), and exists in both;
  3. every tile of ADDED is new and written, of CHANGED exists in both, of REMOVED is gone; no tile is on the map
     twice; with `expect` ({pos: raw node bytes}) an added or changed tile is exactly the bytes the writer meant;
  4. the header (identifier, root and map data attributes) is the same, and every other node of the map data node
     (towns, waypoints, anything) is the same, node count and content, unless `allow_nodes` frees that type
     entirely or `allow_content` frees its content only (the count must stay).
`text_only=True` (patch_base_texts.py: it rewrites item texts over the whole map and cannot name tiles) lets a tile
differ outside the sets only in the text and description attributes of its items; nothing else may move.
On a failure check() raises GuardError naming the first 20 differing coordinates. The writer must not replace the
map then; the new file stays where it is for inspection. There is no switch to turn the guard off.
A tile's identity is the hash of its raw node bytes (Python's 64-bit string hash, one process, both files): a
collision would hide one wrong tile among millions with a chance of about 2^-64 per tile.
Python 3 and numpy. Test: server/tools/map_write_guard_test.py. Cost: README "Map write guard (O512)".
"""
import os
import sys
import time

FD, FE, FF = 0xFD, 0xFE, 0xFF
T_ROOT, T_MAPDATA, T_AREA, T_TILE, T_TOWNS, T_HOUSETILE, T_WAYPOINTS = 0, 2, 4, 5, 12, 14, 15
NODE_NAMES = {'towns': T_TOWNS, 'waypoints': T_WAYPOINTS}
CHUNK = 24 << 20
SHOW = 20
MASK64 = (1 << 64) - 1
TEXT_ATTRS = (6, 7)  # an item's text and description
TEXT_TILE_LIMIT = 200000  # a text-only change that touches more tiles than this is not one


class GuardError(Exception):
    pass


def key_of(p):
    return (int(p[2]) << 32) | (int(p[1]) << 16) | int(p[0])


def pos_of(k):
    k = int(k)
    return (k & 0xFFFF, (k >> 16) & 0xFFFF, k >> 32)


def _fmt(k):
    return '%d,%d,%d' % pos_of(k)


# ------------------------------------------------------------------------------------------------ reading
class Scan:
    """what one pass over a map file found"""

    def __init__(self, path):
        self.path = path
        self.size = 0
        self.ident = b''
        self.head = None          # (length, hash) of the bytes before the first node of the map data node
        self.keys = None          # numpy uint64, file order
        self.hashes = None        # numpy uint64
        self.others = {}          # node type -> [(hash, node count)] of the map data node's children that are not areas
        self.stray = {}           # (type) -> count of a depth 4 node under an area that is not a tile
        self.areas = 0
        self.grab = {}            # key -> raw tile bytes, for the keys asked for


def _unesc_head(buf, i, n):
    out = bytearray()
    while len(out) < n and i < len(buf):
        c = buf[i]
        if c == FD:
            if i + 1 >= len(buf):
                break
            out.append(buf[i + 1])
            i += 2
        elif c in (FE, FF):
            break
        else:
            out.append(c)
            i += 1
    return bytes(out)


def _markers(a):
    """(offsets of the node markers that are not escaped, offsets of the escape bytes) of a clean-starting byte array"""
    import numpy as np
    n = len(a)
    fd = np.flatnonzero(a == FD)
    if len(fd):
        new_run = np.empty(len(fd), bool)
        new_run[0] = True
        new_run[1:] = fd[1:] != fd[:-1] + 1
        run_start = fd[new_run][np.cumsum(new_run) - 1]
        esc = fd[((fd - run_start) & 1) == 0]
    else:
        esc = fd
    escaped = np.zeros(n + 1, bool)
    escaped[esc + 1] = True
    mk = np.flatnonzero(((a == FE) | (a == FF)) & ~escaped[:n])
    return mk, esc


def _scan_buf(sc, buf, depth0, final, first, grab_arr, where):
    """process the nodes of buf up to a clean cut (a depth 3 node closed) or, when final, to its end; returns
    (bytes used, depth after) or None when no cut is in buf yet"""
    import numpy as np
    n = len(buf)
    a = np.frombuffer(buf, np.uint8)
    mk, esc = _markers(a)
    if final and len(esc) and int(esc[-1]) == n - 1:
        raise GuardError('%s: the file ends inside an escape byte' % where)
    if not len(mk):
        if final:
            raise GuardError('%s: no node in the file' % where)
        return None
    is_start = a[mk] == FE
    d = depth0 + np.cumsum(np.where(is_start, 1, -1))
    if first and not is_start[0]:
        raise GuardError('%s: the file does not start with a node' % where)
    if int(d.min()) < 0:
        raise GuardError('%s: a node is closed that was never opened (byte %d)' % (where, int(mk[int(np.argmax(d < 0))]) + sc.size_done))
    zero = np.flatnonzero(d == 0)
    if len(zero):
        if int(zero[0]) != len(d) - 1:
            raise GuardError('%s: bytes after the root node closed (byte %d)' % (where, int(mk[int(zero[0])]) + sc.size_done))
        if not final:
            return None  # the root closes here: the file may end here, the next read says
    if final:
        if int(d[-1]) != 0:
            raise GuardError('%s: truncated: %d node(s) still open at the end of the file' % (where, int(d[-1])))
        if int(mk[-1]) != n - 1:
            raise GuardError('%s: %d byte(s) after the last node closed' % (where, n - 1 - int(mk[-1])))
        k = len(mk) - 1
        used = n
    else:
        cand = np.flatnonzero(~is_start & (d == 2))
        if not len(cand):
            return None
        k = int(cand[-1])
        used = int(mk[k]) + 1
    mk, is_start, d = mk[:k + 1], is_start[:k + 1], d[:k + 1]
    last = len(mk)
    # node types of the starts (the byte after the marker)
    typ = np.zeros(last, np.uint8)
    si = np.flatnonzero(is_start)
    nxt = np.minimum(mk[si] + 1, n - 1)
    typ[si] = a[nxt]
    s3 = np.flatnonzero(is_start & (d == 3))
    e3 = np.flatnonzero(~is_start & (d == 2))
    if len(s3) != len(e3):
        raise GuardError('%s: internal: unbalanced depth 3 nodes' % where)
    if first:
        cut = int(mk[s3[0]]) if len(s3) else used
        sc.head = (cut, hash(buf[:cut]) & MASK64)
    # areas and the other children of the map data node
    area_base, area_of_s3 = [], np.zeros(len(s3), bool)
    for j, (s, e) in enumerate(zip(s3.tolist(), e3.tolist())):
        t = int(typ[s])
        if t == T_AREA:
            area_of_s3[j] = True
            head = _unesc_head(buf, int(mk[s]) + 2, 5)
            if len(head) < 5:
                raise GuardError('%s: an area node is too short (byte %d)' % (where, int(mk[s]) + sc.size_done))
            area_base.append((head[0] | head[1] << 8, head[2] | head[3] << 8, head[4]))
        else:
            sc.others.setdefault(t, []).append((hash(buf[int(mk[s]):int(mk[e]) + 1]) & MASK64, (e - s + 1) // 2))
    sc.areas += int(area_of_s3.sum())
    s4 = np.flatnonzero(is_start & (d == 4))
    e4 = np.flatnonzero(~is_start & (d == 3))
    if len(s4) != len(e4):
        raise GuardError('%s: internal: unbalanced depth 4 nodes' % where)
    if not len(s4):
        return used, int(d[-1])
    par = np.searchsorted(s3, s4) - 1
    if int(par.min()) < 0:
        raise GuardError('%s: a depth 4 node outside any depth 3 node' % where)
    in_area = area_of_s3[par]
    t4 = typ[s4]
    is_tile = in_area & ((t4 == T_TILE) | (t4 == T_HOUSETILE))
    for t in t4[in_area & ~is_tile].tolist():
        sc.stray[t] = sc.stray.get(t, 0) + 1
    ti = np.flatnonzero(is_tile)
    if not len(ti):
        return used, int(d[-1])
    ss, ee = mk[s4[ti]], mk[e4[ti]]
    # the area of each tile: ordinal among the area nodes
    area_idx = np.cumsum(area_of_s3) - 1
    base = np.array(area_base, np.int64).reshape(-1, 3)
    ab = base[area_idx[par[ti]]]
    p0 = ss + 2
    e1 = a[p0] == FD
    xo = np.where(e1, a[np.minimum(p0 + 1, n - 1)], a[p0]).astype(np.int64)
    p1 = p0 + 1 + e1
    e2 = a[np.minimum(p1, n - 1)] == FD
    yo = np.where(e2, a[np.minimum(p1 + 1, n - 1)], a[np.minimum(p1, n - 1)]).astype(np.int64)
    keys = ((ab[:, 2] << 32) | ((ab[:, 1] + yo) << 16) | (ab[:, 0] + xo)).astype(np.uint64)
    hs = [hash(buf[s:e + 1]) & MASK64 for s, e in zip(ss.tolist(), ee.tolist())]
    sc.key_parts.append(keys)
    sc.hash_parts.append(np.array(hs, np.uint64))
    if grab_arr is not None and len(grab_arr):
        for j in np.flatnonzero(_in(grab_arr, keys)).tolist():
            sc.grab.setdefault(int(keys[j]), bytes(buf[int(ss[j]):int(ee[j]) + 1]))
    return used, int(d[-1])


def scan(path, grab=()):
    """Scan of the map file (one streaming pass); `grab`: tile keys whose raw bytes are kept in Scan.grab"""
    import numpy as np
    sc = Scan(path)
    sc.key_parts, sc.hash_parts, sc.size_done = [], [], 0
    grab_arr = np.array(sorted(grab), np.uint64) if grab else None
    where = os.path.basename(path)
    with open(path, 'rb') as f:
        head = f.read(4)
        if len(head) < 4:
            raise GuardError('%s: shorter than the 4 byte identifier' % where)
        if head[:2] == b'\x1f\x8b':
            raise GuardError('%s: compressed; unpack it first' % where)
        sc.ident = head
        sc.size = 4
        buf, depth, first, eof = b'', 0, True, False
        sc.size_done = 4
        while not eof:
            more = f.read(CHUNK)
            eof = len(more) < CHUNK
            if more:
                buf = buf + more if buf else more
                sc.size += len(more)
            if not buf:
                break
            res = _scan_buf(sc, buf, depth, eof, first, grab_arr, where)
            if res is None:
                if eof:
                    raise GuardError('%s: internal: no cut at the end of the file' % where)
                continue
            used, depth = res
            first = False
            sc.size_done += used
            buf = buf[used:]
        if first:
            raise GuardError('%s: no node in the file' % where)
    if depth != 0:
        raise GuardError('%s: truncated: nodes still open at the end of the file' % where)
    if sc.key_parts:
        sc.keys = np.concatenate(sc.key_parts)
        sc.hashes = np.concatenate(sc.hash_parts)
    else:
        sc.keys, sc.hashes = np.zeros(0, np.uint64), np.zeros(0, np.uint64)
    del sc.key_parts, sc.hash_parts
    return sc


# ------------------------------------------------------------------------------------------------ text only
ITEM_FIXED = {4: 2, 5: 2, 8: 5, 10: 2, 12: 1, 14: 1, 15: 1, 16: 4, 17: 1, 18: 4, 20: 4, 21: 4, 22: 2, 23: 4}
ITEM_STRINGS = {1, 6, 7, 19, 30, 31, 32}


def _strip_item(p):
    """an unescaped item node payload without its text and description attributes; unchanged when an attribute is
    not one we know the length of"""
    out, q = bytearray(p[:3]), 3
    while q < len(p):
        at = p[q]
        if at in ITEM_FIXED:
            n = 1 + ITEM_FIXED[at]
        elif at in ITEM_STRINGS:
            if q + 3 > len(p):
                return p
            n = 3 + (p[q + 1] | p[q + 2] << 8)
        else:
            return p
        if q + n > len(p):
            return p
        if at not in TEXT_ATTRS:
            out += p[q:q + n]
        q += n
    return bytes(out)


def strip_texts(raw):
    """the raw bytes of a tile node with the text and description attribute of every item taken out"""
    out, i, n = bytearray(), 0, len(raw)
    while i < n:
        c = raw[i]
        if c in (FE, FF):
            out.append(c)
            i += 1
            if c == FE:
                pay = bytearray()
                while i < n and raw[i] not in (FE, FF):
                    if raw[i] == FD and i + 1 < n:
                        pay.append(raw[i + 1])
                        i += 2
                    else:
                        pay.append(raw[i])
                        i += 1
                if pay and pay[0] == 6:
                    pay = bytearray(_strip_item(bytes(pay)))
                for b in pay:
                    if b in (FD, FE, FF):
                        out.append(FD)
                    out.append(b)
        else:
            out.append(c)
            i += 1
    return bytes(out)


# ------------------------------------------------------------------------------------------------ the proof
def _in(sorted_set, values):
    """bool array: which of values are in the sorted unique array sorted_set (binary search; np.isin sorts and hashes
    both sides, 30 s on 7 million tiles)"""
    import numpy as np
    if not len(sorted_set):
        return np.zeros(len(values), bool)
    at = np.minimum(np.searchsorted(sorted_set, values), len(sorted_set) - 1)
    return sorted_set[at] == values


def _keys(positions):
    import numpy as np
    return np.unique(np.fromiter((key_of(p) for p in positions), np.uint64))


def _nodes(allow):
    """node types named in allow ('towns', 'waypoints', a type number); 'header' is read by check() itself"""
    out = set()
    for a in allow or ():
        if a in NODE_NAMES:
            out.add(NODE_NAMES[a])
        elif isinstance(a, int):
            out.add(a)
        elif a != 'header':
            raise ValueError('map write guard: unknown node name %r' % (a,))
    return out


def check(old_path, new_path, add=(), change=(), remove=(), expect=None, allow_nodes=(), allow_content=(),
          text_only=False, allow_header=False, log=None):
    """prove that new_path is old_path with only the intended tiles (and nodes) changed; returns a stats dict, raises
    GuardError otherwise. See the module docstring."""
    import numpy as np
    t0 = time.time()
    A, C, R = _keys(add), _keys(change), _keys(remove)
    for x, y, nx, ny in ((A, C, 'add', 'change'), (A, R, 'add', 'remove'), (C, R, 'change', 'remove')):
        both = np.intersect1d(x, y)
        if len(both):
            raise GuardError('the writer\'s intended change is not consistent: %d tile(s) are in both %s and %s (first %s)'
                             % (len(both), nx, ny, _fmt(both[0])))
    free_all, free_content = _nodes(allow_nodes), _nodes(allow_content)
    old, new = scan(old_path), scan(new_path)
    diffs, more = [], [0]  # (key, reason) of the first few, and how many were left out

    def note(keys, reason):
        """keys: sorted numpy array of tile keys that differ for this reason; only the first SHOW are kept"""
        for k in keys[:SHOW].tolist():
            diffs.append((int(k), reason))
        more[0] += max(0, len(keys) - SHOW)

    if old.ident != new.ident:
        diffs.append((0, 'the 4 byte identifier of the file changed'))
    if old.head != new.head and not allow_header and 'header' not in (allow_nodes or ()):
        diffs.append((0, 'the header (root and map data attributes) changed'))
    for t in sorted(set(old.others) | set(new.others)):
        a, b = old.others.get(t, []), new.others.get(t, [])
        name = {v: k for k, v in NODE_NAMES.items()}.get(t, 'node type %d' % t)
        if t in free_all:
            continue
        if sum(c for _h, c in a) != sum(c for _h, c in b) or len(a) != len(b):
            diffs.append((0, 'the %s changed: %d node(s) in %d element(s) before, %d in %d after'
                          % (name, sum(c for _h, c in a), len(a), sum(c for _h, c in b), len(b))))
        elif a != b and t not in free_content:
            diffs.append((0, 'the %s changed content (node count equal)' % name))
    for t in sorted(set(old.stray) | set(new.stray)):
        if old.stray.get(t, 0) != new.stray.get(t, 0):
            diffs.append((0, 'nodes of type %d inside an area (not tiles) changed from %d to %d'
                          % (t, old.stray.get(t, 0), new.stray.get(t, 0))))
    ko, ho, kn, hn = old.keys, old.hashes, new.keys, new.hashes
    old.keys = old.hashes = new.keys = new.hashes = None
    n_old, n_new = len(ko), len(kn)
    oi = np.argsort(ko, kind='stable')
    ko_s, ho_s = ko[oi], ho[oi]
    del ko, ho, oi
    ni = np.argsort(kn, kind='stable')
    kn_s, hn_s = kn[ni], hn[ni]
    del kn, hn, ni
    # a tile on the map twice in the new file that was not so in the old one
    d_new = np.unique(kn_s[1:][kn_s[1:] == kn_s[:-1]])
    if len(d_new):
        d_old = np.unique(ko_s[1:][ko_s[1:] == ko_s[:-1]])
        note(d_new[~_in(d_old, d_new)], 'the new map holds this tile twice')
    CR = np.union1d(C, R)
    # old tiles: still there and the same, unless the writer meant them
    if len(kn_s):
        at = np.minimum(np.searchsorted(kn_s, ko_s), len(kn_s) - 1)
        in_new = kn_s[at] == ko_s
    else:
        at = np.zeros(len(ko_s), np.int64)
        in_new = np.zeros(len(ko_s), bool)
    intended_old = _in(CR, ko_s)
    note(ko_s[~in_new & ~intended_old], 'tile removed outside the intended change')
    differ = in_new & ~intended_old & (hn_s[at] != ho_s) if len(kn_s) else np.zeros(len(ko_s), bool)
    del at, in_new, intended_old
    text_changed = 0
    if text_only and differ.any():
        # only the text and description attributes of an item may differ: compare the two raw tiles with those cut out
        want = ko_s[differ]
        if len(want) > TEXT_TILE_LIMIT:
            note(want, 'tile changed outside the intended change (a text-only change touches at most %d tiles)' % TEXT_TILE_LIMIT)
            differ[:] = False
        else:
            so2, sn2 = scan(old_path, grab=want.tolist()), scan(new_path, grab=want.tolist())
            bad = []
            for k in want.tolist():
                a, b = so2.grab.get(int(k)), sn2.grab.get(int(k))
                if a is None or b is None or strip_texts(a) != strip_texts(b):
                    bad.append(k)
            differ = _in(np.array(sorted(bad), np.uint64), ko_s) if bad else np.zeros(len(ko_s), bool)
            text_changed = int(len(want) - len(bad))
    note(ko_s[differ], 'tile changed outside the intended change (items, attributes or flags differ)')
    del differ
    # new tiles the old file did not have: only the writer's own
    if len(ko_s):
        at2 = np.minimum(np.searchsorted(ko_s, kn_s), len(ko_s) - 1)
        fresh = ko_s[at2] != kn_s
        del at2
    else:
        fresh = np.ones(len(kn_s), bool)
    note(kn_s[fresh & ~_in(A, kn_s)], 'tile added outside the intended change')
    del fresh
    # the intended sets
    for name, S, need_old, need_new in (('add', A, False, True), ('change', C, True, True), ('remove', R, True, False)):
        if not len(S):
            continue
        s_old, s_new = _in(ko_s, S), _in(kn_s, S)
        if need_old and not s_old.all():
            note(S[~s_old], '%s: the tile is not on the old map' % name)
        if not need_old and s_old.any():
            note(S[s_old], '%s: the tile is on the old map already' % name)
        if need_new and not s_new.all():
            note(S[~s_new], '%s: the tile was not written' % name)
        if not need_new and s_new.any():
            note(S[s_new], '%s: the tile is still on the new map' % name)
    if expect:
        want = np.array(sorted(key_of(p) for p in expect), np.uint64)
        want = want[_in(kn_s, want)]
        got = {}
        if len(want):
            idx = np.searchsorted(kn_s, want)
            got = dict(zip(want.tolist(), hn_s[idx].tolist()))
        for p, raw in expect.items():
            k = key_of(p)
            if k in got and got[k] != hash(raw) & MASK64:
                diffs.append((k, 'the tile is not what the writer meant'))
    stats = dict(old_tiles=int(n_old), new_tiles=int(n_new), added=int(len(A)), changed=int(len(C)),
                 removed=int(len(R)), text_tiles=text_changed, areas=int(new.areas), seconds=round(time.time() - t0, 1))
    if diffs:
        seen, shown = set(), []
        for k, why in sorted(diffs):
            if (k, why) in seen:
                continue
            seen.add((k, why))
            shown.append('%s: %s' % (_fmt(k) if k else 'file', why))
        total = len(seen) + more[0]
        raise GuardError('map write guard refused %s: %d difference(s) from the intended change; first %d: %s'
                         % (os.path.basename(new_path), total, min(total, SHOW), '; '.join(shown[:SHOW])))
    if log:
        log('map write guard: %d tiles before, %d after: %d added, %d rewritten, %d removed%s, every other tile and node '
            'identical (%.1f s)' % (stats['old_tiles'], stats['new_tiles'], stats['added'], stats['changed'], stats['removed'],
                                    ', %d with a new item text' % text_changed if text_only else '', stats['seconds']))
    return stats


def verify(error, old_path, new_path, log=None, **kw):
    """check() for a writer: a refusal is raised as the writer's own exception type `error`, with what the owner needs
    to know added (the old map is untouched, the new file stays for inspection)"""
    try:
        return check(old_path, new_path, log=log, **kw)
    except GuardError as e:
        raise error('%s; the old map is untouched and the new file stays at %s' % (e, new_path))


def main(argv):
    if len(argv) < 2 or argv[0] in ('-h', '--help'):
        print('usage: python3 -I server/tools/map_write_guard.py OLD.otbm NEW.otbm [--text-only]\n'
              'proves NEW is OLD with no tile changed (the read-only half of the guard: a pure "same map" check;\n'
              'with --text-only item texts may differ). Exit 0 when it holds, 1 with the first differences.')
        return 0 if argv else 1
    try:
        check(argv[0], argv[1], text_only='--text-only' in argv, log=print)
    except GuardError as e:
        print(e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

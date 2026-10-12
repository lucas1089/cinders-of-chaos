"""OTBM map reader (numpy, vectorised).

    from otbm import load_map
    m = load_map('world.otbm')            # or a cached .npz written by save_cache()
    m.tiles: dict of arrays  x, y, z (uint16/uint8), flags (uint32), house (uint32), off, cnt
    m.items: uint16 array of item ids, the stack of tile i is m.items[off[i]:off[i]+cnt[i]]
             (the ground given inline as a tile attribute comes first, then the tile's top-level item
             nodes in file order; items inside containers are not included)
    m.towns: list of (id, name, (x, y, z))
    m.header: dict(version, width, height, items_major, items_minor, description, spawnfile, housefile)

Reads OTBM versions 1-3 (and the 4 tag used by newer editors when the node layout is the same).
Only the item id of each item node is decoded, not its attributes (except teleport targets, see
teleports()). Deterministic: the same file always gives the same arrays.
"""
import struct
import numpy as np

T_ROOT, T_MAPDATA, T_AREA, T_TILE, T_ITEM, T_TOWNS, T_TOWN, T_HOUSETILE = 0, 2, 4, 5, 6, 12, 13, 14
A_DESC, A_TILEFLAGS, A_ITEM, A_TELE, A_SPAWN, A_HOUSE = 1, 3, 9, 8, 11, 13
TF_PZ, TF_NOPVP, TF_NOLOGOUT, TF_PVP = 1, 4, 8, 16


class Map:
    def __init__(self, tiles, items, towns, header):
        self.tiles, self.items, self.towns, self.header = tiles, items, towns, header
        t = tiles
        self.key = (t['z'].astype(np.int64) << 32) | (t['y'].astype(np.int64) << 16) | t['x'].astype(np.int64)
        self.order = np.argsort(self.key, kind='stable')
        self.skey = self.key[self.order]

    def __len__(self):
        return len(self.tiles['x'])

    def find(self, x, y, z):
        """tile index or -1"""
        k = (int(z) << 32) | (int(y) << 16) | int(x)
        i = np.searchsorted(self.skey, k)
        return int(self.order[i]) if i < len(self.skey) and self.skey[i] == k else -1

    def rect(self, x0, y0, x1, y1, z):
        """indices of tiles in [x0..x1] x [y0..y1] on floor z (inclusive)"""
        out = []
        for y in range(y0, y1 + 1):
            a = np.searchsorted(self.skey, (z << 32) | (y << 16) | x0)
            b = np.searchsorted(self.skey, (z << 32) | (y << 16) | x1, side='right')
            out.append(self.order[a:b])
        return np.concatenate(out) if out else np.zeros(0, np.int64)

    def stack(self, i):
        o, c = int(self.tiles['off'][i]), int(self.tiles['cnt'][i])
        return self.items[o:o + c]


def _scan(d):
    """returns (unescaped stream du, node start offsets in du, node types, node depths, payload ends)"""
    a = np.frombuffer(d, np.uint8)
    fd = np.flatnonzero(a == 0xFD)
    if len(fd):
        # runs of consecutive 0xFD: even offsets inside a run are escape chars
        new_run = np.ones(len(fd), bool)
        new_run[1:] = fd[1:] != fd[:-1] + 1
        run_id = np.cumsum(new_run) - 1
        run_start = fd[new_run][run_id]
        esc = fd[((fd - run_start) & 1) == 0]
    else:
        esc = np.zeros(0, np.int64)
    escaped = np.zeros(len(a), bool)
    escaped[esc + 1] = True
    mk = np.flatnonzero(((a == 0xFE) | (a == 0xFF)) & ~escaped)
    mk = mk[mk >= 4]
    del escaped
    is_start = a[mk] == 0xFE
    # position in the unescaped stream
    newpos = mk - np.searchsorted(esc, mk)
    keep = np.ones(len(a), bool)
    keep[esc] = False
    du = a[keep]
    del keep
    depth = np.cumsum(np.where(is_start, 1, -1))
    starts = np.flatnonzero(is_start)
    s_new = newpos[starts]
    ntype = du[s_new + 1]
    # payload runs from s_new+2 to the next marker
    nxt = newpos[np.minimum(starts + 1, len(mk) - 1)]
    return du, s_new + 2, ntype, depth[starts], nxt


def _u16(du, p):
    return du[p].astype(np.uint32) | (du[p + 1].astype(np.uint32) << 8)


def _u32(du, p):
    return _u16(du, p) | (_u16(du, p + 2) << 16)


def load_otbm(path):
    d = open(path, 'rb').read()
    if d[:2] == b'\x1f\x8b':
        import gzip
        d = gzip.decompress(d)
    du, pay, ntype, depth, pend = _scan(d)
    n = len(du)
    # header (root node payload)
    p = int(pay[0])
    ver, w, h, maj, mnr = struct.unpack_from('<IHHII', bytes(du[p:p + 16]), 0)
    header = dict(version=ver, width=w, height=h, items_major=maj, items_minor=mnr)
    md = np.flatnonzero(ntype == T_MAPDATA)
    if len(md):
        q, e = int(pay[md[0]]), int(pend[md[0]])
        b = bytes(du[q:e]); k = 0
        while k + 3 <= len(b):
            at = b[k]; ln = struct.unpack_from('<H', b, k + 1)[0]
            s = b[k + 3:k + 3 + ln].decode('latin1'); k += 3 + ln
            header[{A_DESC: 'description', A_SPAWN: 'spawnfile', A_HOUSE: 'housefile'}.get(at, f'attr{at}')] = s
    # tile areas
    ai = np.flatnonzero(ntype == T_AREA)
    ap = pay[ai]
    ax, ay, az = _u16(du, ap), _u16(du, ap + 2), du[ap + 4]
    # tiles
    ti = np.flatnonzero((ntype == T_TILE) | (ntype == T_HOUSETILE))
    tp = pay[ti]; te = pend[ti]
    area_of = np.searchsorted(ai, ti) - 1
    ok = area_of >= 0
    ti, tp, te, area_of = ti[ok], tp[ok], te[ok], area_of[ok]
    x = (ax[area_of] + du[tp]).astype(np.uint16)
    y = (ay[area_of] + du[tp + 1]).astype(np.uint16)
    z = az[area_of].astype(np.uint8)
    ishouse = ntype[ti] == T_HOUSETILE
    house = np.zeros(len(ti), np.uint32)
    hp = tp[ishouse]
    house[ishouse] = _u32(du, hp + 2)
    q = tp + 2 + np.where(ishouse, 4, 0)
    flags = np.zeros(len(ti), np.uint32)
    ground = np.zeros(len(ti), np.uint16)
    for _ in range(2):
        live = q < te
        at = np.zeros(len(q), np.uint8)
        at[live] = du[q[live]]
        f = live & (at == A_TILEFLAGS) & (q + 5 <= te)
        flags[f] = _u32(du, q[f] + 1); q = np.where(f, q + 5, q)
        g = live & (at == A_ITEM) & (q + 3 <= te) & ~f
        ground[g] = _u16(du, q[g] + 1).astype(np.uint16); q = np.where(g, q + 3, q)
    # items: top-level children of tiles
    ii = np.flatnonzero(ntype == T_ITEM)
    tile_of = np.searchsorted(ti, ii) - 1
    v = tile_of >= 0
    ii, tile_of = ii[v], tile_of[v]
    top = depth[ii] == depth[ti[tile_of]] + 1
    ii, tile_of = ii[top], tile_of[top]
    iid = _u16(du, pay[ii]).astype(np.uint16)
    # merge inline grounds (first) with item nodes
    gt = np.flatnonzero(ground > 0)
    all_tile = np.concatenate([gt, tile_of])
    all_id = np.concatenate([ground[gt], iid])
    key = all_tile.astype(np.int64) * 2 + np.concatenate([np.zeros(len(gt), np.int64), np.ones(len(tile_of), np.int64)])
    o = np.argsort(key, kind='stable')
    items = all_id[o]
    cnt = np.bincount(all_tile, minlength=len(ti)).astype(np.uint16)
    off = (np.cumsum(cnt.astype(np.int64)) - cnt).astype(np.uint32)
    tiles = dict(x=x, y=y, z=z, flags=flags, house=house, off=off, cnt=cnt)
    # towns
    towns = []
    for k in np.flatnonzero(ntype == T_TOWN):
        b = bytes(du[int(pay[k]):int(pend[k])])
        try:
            tid, ln = struct.unpack_from('<IH', b, 0)
            name = b[6:6 + ln].decode('latin1')
            tx, ty, tz = struct.unpack_from('<HHB', b, 6 + ln)
            towns.append((tid, name, (tx, ty, tz)))
        except struct.error:
            pass
    m = Map(tiles, items, towns, header)
    m._raw = (du, pay, ntype, pend, ii, tile_of)   # kept for teleports(); dropped by drop_raw()
    return m


def teleports(m, tele_ids):
    """[(tile_index, item_id, (dx, dy, dz))] for items in tele_ids that carry a destination attribute"""
    du, pay, ntype, pend, ii, tile_of = m._raw
    iid = _u16(du, pay[ii])
    sel = np.flatnonzero(np.isin(iid, np.fromiter(tele_ids, np.uint32)))
    out = []
    for s in sel:
        b = bytes(du[int(pay[ii[s]]) + 2:int(pend[ii[s]])])
        k = 0
        while k < len(b):
            at = b[k]; k += 1
            if at == A_TELE and k + 5 <= len(b):
                out.append((int(tile_of[s]), int(iid[s]), struct.unpack_from('<HHB', b, k))); break
            elif at in (1, 2, 6, 7, 19):          # string attributes
                if k + 2 > len(b): break
                k += 2 + struct.unpack_from('<H', b, k)[0]
            elif at in (4, 5, 22, 10, 3, 18, 16, 20, 21, 23):
                k += {4: 2, 5: 2, 22: 2, 10: 2, 3: 4, 18: 4, 16: 4, 20: 4, 21: 4, 23: 4}[at]
            elif at in (12, 14, 15, 17):
                k += 1
            else:
                break
    return out


def save_cache(m, path):
    np.savez_compressed(path, items=m.items, towns=np.array(repr(m.towns)), header=np.array(repr(m.header)),
                        **{'t_' + k: v for k, v in m.tiles.items()})


def load_cache(path):
    import ast
    z = np.load(path)
    tiles = {k[2:]: z[k] for k in z.files if k.startswith('t_')}
    return Map(tiles, z['items'], ast.literal_eval(str(z['towns'])), ast.literal_eval(str(z['header'])))


def load_map(path):
    return load_cache(path) if path.endswith('.npz') else load_otbm(path)

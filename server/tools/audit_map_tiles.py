#!/usr/bin/env python3
"""Whole-map tile lint: structure faults of a tile, borders, walls, doors, teleports and roofs (server/README.md "Map tile audit (O511)").

usage: python3 -I server/tools/audit_map_tiles.py SERVER_DIR [--box x1,y1,x2,y2] [--floor Z] [--csv OUT] [--known FILE]
                                                  [--check] [--summary] [--limit N] [--max-items N] [--quiet]
       python3 -I server/tools/audit_map_tiles.py --map FILE.otbm --items ITEMS.otb [--xml ITEMS.xml] [same options]

Read only: it never writes the map. SERVER_DIR is an installed server folder (or its data folder): the map is
data/world/<mapName>.otbm (the mapName of config.lua, else the only .otbm), the items data/items/items.otb and items.xml.
--map / --items / --xml name the files instead. The map is read with tools/map/otbm.py into arrays (no object per tile) and
every code is found with whole-array maths; only the doors, the teleports and the findings that are printed are looked at
one by one. --box and --floor limit what is reported (the neighbours of a tile at the edge of the box are still read).

Codes (one line each: CODE x,y,z ids=A[,B] fix=CLASS: what)
  NO_GROUND         the tile holds items but none of them is a ground                                   fix add-ground
  GROUND_NOT_FIRST  a ground is not in the ground slot (first item), or a second ground lies on it       fix reorder
  DUP_ITEM          the same id twice on one tile where that is never normal: border pieces, walls, doors, tops,
                    floor changes and teleports (stackables, grounds and decoration are not looked at)      fix remove-dup
  UNKNOWN_ID        an id that items.otb does not know                                                    fix replace-id
  ORPHAN_BORDER     a border piece of one of our 12 piece sets (areagen_config.lua `pieces`) with none of the
                    neighbours it names carrying a ground of the higher family it borders                    fix fix-border
  WALL_MISMATCH     a wall piece of one of our wall brushes (areagen_config.lua `walls`) whose 4 neighbours
                    give another piece type by ChaosAreaGenCore.wallPiece                                    fix fix-wall
  BLOCKED_DOOR      a door with no walkable tile on any of its four sides                                  fix open-door
  BLOCKED_ON_SPECIAL a door or a teleport that shares its tile with another blocking item                  fix clear-tile
  BLOCKED_TELEPORT  the destination of a teleport is not a tile, or one nobody can stand on                  fix retarget
  ROOF_NO_SUPPORT   a roof (an item named roof, or one of the roof ids of patch_hunt_roofs.py) on floor 7 or
                    above with no walkable ground and nothing built on the tile under it                    fix support-or-remove-roof
  TOO_MANY_ITEMS    more than MAX_ITEMS items on one tile                                                 fix thin
--known FILE (default server/tools/map_tile_audit_known.csv, columns code,x,y,z,reason): findings that were looked at and
left. --check exits 1 when a finding is not listed there (listed ones that are gone are only printed, and not when --box /
--floor cut them out). --summary prints the counts per code and stops. --csv writes every finding (code,x,y,z,ids,fix).
The report prints the first --limit lines of each code (default 20); --csv has all of them. Exit 0 on success, 1 on a
refusal or a failed --check. Python 3 and numpy. Test: audit_map_tiles_test.py (synthetic map).
"""
import csv
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import map_tile_rules as R  # noqa: E402

KNOWN = os.path.join(HERE, 'map_tile_audit_known.csv')
AREAGEN_CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'areagen_config.lua')
DARK_TILES = os.path.join(SERVER, 'data', 'lib', 'chaos_dark_tiles.lua')

# ---- limits and rules: every number the audit sets, in one place
MAX_ITEMS = 12            # TOO_MANY_ITEMS: items on one tile (the guide keeps decoration under 3 per tile, a pile of loot fits)
DUP_CLASSES = ('border', 'wall', 'door', 'floorchg', 'top')    # itemdb classes whose id twice on a tile is never normal
DUP_GROUPS = (7,)         # otb groups that count too: teleports
DUP_OK_IDS = ()           # ids that may stand twice (known decor pairs): add an id here when a pair is meant
STACKABLE_FLAG = 1 << 7   # items.otb flag: stackables are never a duplicate
SOLID_FLAG = 1            # items.otb flag block solid
GROUND_GROUP = 1
DOOR_GROUP = 13           # items.otb group of doors; items.xml type="door" counts too
TELEPORT_GROUP = 7        # items.otb group of teleports; items.xml type="teleport" counts too
ROOF_NAME = re.compile(r'\broofs?\b', re.I)
ROOF_MAX_Z = 7            # a roof is looked at on this floor and above it (smaller z); below ground a roof is not a roof
KIND_ORDER = ('horizontal', 'vertical', 'corner', 'pole')

CODES = ('NO_GROUND', 'GROUND_NOT_FIRST', 'DUP_ITEM', 'UNKNOWN_ID', 'ORPHAN_BORDER', 'WALL_MISMATCH', 'BLOCKED_DOOR',
         'BLOCKED_ON_SPECIAL', 'BLOCKED_TELEPORT', 'ROOF_NO_SUPPORT', 'TOO_MANY_ITEMS')
FIX = {'NO_GROUND': 'add-ground', 'GROUND_NOT_FIRST': 'reorder', 'DUP_ITEM': 'remove-dup', 'UNKNOWN_ID': 'replace-id',
       'ORPHAN_BORDER': 'fix-border', 'WALL_MISMATCH': 'fix-wall', 'BLOCKED_DOOR': 'open-door',
       'BLOCKED_ON_SPECIAL': 'clear-tile', 'BLOCKED_TELEPORT': 'retarget', 'ROOF_NO_SUPPORT': 'support-or-remove-roof',
       'TOO_MANY_ITEMS': 'thin'}
WHAT = {'NO_GROUND': 'items on a tile with no ground', 'GROUND_NOT_FIRST': 'a ground is not the first item',
        'DUP_ITEM': 'the same id twice on one tile', 'UNKNOWN_ID': 'id not in items.otb',
        'ORPHAN_BORDER': 'border piece with no higher ground on the side it names',
        'WALL_MISMATCH': 'wall piece differs from the one its neighbours give',
        'BLOCKED_DOOR': 'no walkable tile on any side of the door',
        'BLOCKED_ON_SPECIAL': 'a blocking item on the tile of a door or teleport',
        'BLOCKED_TELEPORT': 'teleport destination is missing or not walkable',
        'ROOF_NO_SUPPORT': 'roof with nothing walkable or built under it', 'TOO_MANY_ITEMS': 'too many items on one tile'}


class AuditError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ our tables
class _Lua:
    """a reader of the plain table literals of our config files (no functions, no locals): enough for
    areagen_config.lua. Tables with only positional entries become lists, others dicts (positional keys 1, 2, ...)"""
    TOK = re.compile(r'\s+|--[^\n]*|"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|-?\d+\.?\d*(?:[eE][-+]?\d+)?|[A-Za-z_]\w*|[{}\[\]=,;]')

    def __init__(self, text):
        self.t = [m.group(0) for m in self.TOK.finditer(text) if not m.group(0).strip() == '' and not m.group(0).startswith('--')]
        self.p = 0

    def peek(self):
        return self.t[self.p] if self.p < len(self.t) else None

    def take(self, want=None):
        tok = self.peek()
        if tok is None or (want is not None and tok != want):
            raise AuditError('lua table: expected %s, got %s' % (want, tok))
        self.p += 1
        return tok

    def value(self):
        tok = self.take()
        if tok == '{':
            return self.table()
        if tok[0] in '"\'':
            return bytes(tok[1:-1], 'utf-8').decode('unicode_escape')
        if tok == 'true':
            return True
        if tok == 'false':
            return False
        if tok == 'nil':
            return None
        try:
            return float(tok) if re.search(r'[.eE]', tok) else int(tok)
        except ValueError:
            raise AuditError('lua table: cannot read %r' % tok)

    def table(self):
        pos, keyed = [], {}
        while self.peek() != '}':
            tok = self.peek()
            nxt = self.t[self.p + 1] if self.p + 1 < len(self.t) else None
            if tok == '[':
                self.take('[')
                k = self.value()
                self.take(']')
                self.take('=')
                keyed[k] = self.value()
            elif re.match(r'[A-Za-z_]\w*$', tok) and nxt == '=':
                self.take()
                self.take('=')
                keyed[tok] = self.value()
            else:
                pos.append(self.value())
            if self.peek() in (',', ';'):
                self.take()
        self.take('}')
        if keyed and not pos:
            return keyed
        if pos and not keyed:
            return pos
        out = dict(keyed)
        out.update({i + 1: v for i, v in enumerate(pos)})
        return out


def read_lua_return_table(path):
    text = open(path, encoding='utf-8').read()
    i = re.search(r'^return\s*\{', text, re.M)
    if not i:
        raise AuditError('%s: no `return {` table' % path)
    rd = _Lua(text[i.end() - 1:])
    return rd.value()


def dark_ids(path=DARK_TILES):
    """{name: server id} of the dark tile set (data/lib/chaos_dark_tiles.lua); {} when the file is not there"""
    if not os.path.isfile(path):
        return {}
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'^\s*(\w+)\s*=\s*(\d+)\s*,?\s*$', open(path, encoding='utf-8').read(), re.M)}


def load_tables(config=AREAGEN_CONFIG, dark=None):
    """our ground families, border sets and wall brushes, as ids:
       borders  {piece id: [(set name, piece name, {over family names})]}
       grounds  {family: set of ids}
       walls    {piece id: (brush, kind)}"""
    cfg = read_lua_return_table(config)
    dark = dark_ids() if dark is None else dark

    def ident(v):
        return v if isinstance(v, int) else dark.get(v)
    grounds = {}
    for fam, d in cfg['families'].items():
        grounds[fam] = {ident(g[0] if isinstance(g, list) else g) for g in d['grounds']} - {None}
    over_of = {}
    for over, rules in cfg['borders'].items():
        for _under, setname in rules.items():
            over_of.setdefault(setname, set()).add(over)
    borders = {}
    for setname, pieces in cfg['pieces'].items():
        for name, v in pieces.items():
            pid = ident(v)
            if pid is not None and name in R.PIECE_SIDES:
                borders.setdefault(pid, []).append((setname, name, over_of.get(setname, set())))
    walls = {}
    for brush, kinds in cfg['walls'].items():
        for kind, rows in kinds.items():
            for row in rows:
                pid = ident(row[0])
                if pid is not None:
                    walls[pid] = (brush, kind)
    return dict(borders=borders, grounds=grounds, walls=walls)


# ------------------------------------------------------------------------------------------------ items
def xml_type_ids(xml_path, type_name):
    """ids of the items.xml entries with attribute type = type_name (door, teleport)"""
    out = set()
    if xml_path and os.path.isfile(xml_path):
        text = open(xml_path, encoding='latin-1').read()
        for mm in re.finditer(r'<item\b([^>]*?)>(.*?)</item>', text, re.S):
            if re.search(r'key="type"\s+value="%s"' % type_name, mm.group(2)):
                a = dict(re.findall(r'(\w+)="([^"]*)"', mm.group(1)))
                if 'id' in a:
                    out.add(int(a['id']))
                elif 'fromid' in a and 'toid' in a:
                    out.update(range(int(a['fromid']), int(a['toid']) + 1))
    return out


def roof_ids_of_patch():
    """the roof ids patch_hunt_roofs.py lays: the old fill and edge pieces, the rusty tin kit"""
    try:
        import patch_hunt_roofs as P
    except Exception:       # a stripped install: the name rule alone
        return set()
    ids = set(P.FILL) | set(P.EDGES) | set(P.INNER) | set(P.INTERIOR) | set(P.PIECE.values())
    return ids


class World:
    """the map as arrays plus the lookup tables of the item database"""

    def __init__(self, m, db, doors=(), teles=(), roofs=(), tables=None, max_items=MAX_ITEMS):
        self.m, self.db = m, db
        t = m.tiles
        self.n = len(t['x'])
        self.max_items = max_items
        self.tables = tables or load_tables()
        N = 65536
        self.known_lut = np.asarray(db.known, bool)
        self.ground_lut = np.asarray(db.group == GROUND_GROUP)
        self.solid_lut = (np.asarray(db.flags) & SOLID_FLAG) > 0
        self.doors, self.teles = set(doors), set(teles)
        stack_lut = (np.asarray(db.flags) & STACKABLE_FLAG) > 0
        cls_names = None
        try:
            from itemdb import CLASSES
            cls_names = CLASSES
        except Exception:
            pass
        dup = np.zeros(N, bool)
        if cls_names:
            for c in DUP_CLASSES:
                dup |= np.asarray(db.cls) == cls_names.index(c)
        for g in DUP_GROUPS:
            dup |= np.asarray(db.group) == g
        for i in self.teles | self.doors:
            dup[i] = True
        dup &= ~stack_lut
        dup &= ~self.ground_lut
        for i in DUP_OK_IDS:
            dup[i] = False
        self.dup_lut = dup
        roof = np.zeros(N, bool)
        for i in range(N):
            if self.known_lut[i] and db.name[i] and ROOF_NAME.search(db.name[i]):
                roof[i] = True
        for i in roofs:
            if 0 <= i < N:
                roof[i] = True
        self.roof_lut = roof
        self.off = t['off'].astype(np.int64)
        self.cnt = t['cnt'].astype(np.int64)
        self.ends = self.off + self.cnt

    # ---- lookups
    def tile_of(self, pos):
        return np.searchsorted(self.ends, pos, side='right')

    def lookup(self, x, y, z):
        """tile index of each (x, y, z) or -1"""
        x, y, z = (np.asarray(a, np.int64) for a in (x, y, z))
        valid = (x >= 0) & (x < 65536) & (y >= 0) & (y < 65536) & (z >= 0) & (z < 256)
        k = (np.where(valid, z, 0) << 32) | (np.where(valid, y, 0) << 16) | np.where(valid, x, 0)
        sk = self.m.skey
        i = np.minimum(np.searchsorted(sk, k), len(sk) - 1)
        ok = valid & (sk[i] == k)
        return np.where(ok, self.m.order[i], -1)

    def first_ids(self, idx):
        """first item id of tiles idx (0 for an empty or missing tile)"""
        idx = np.asarray(idx, np.int64)
        out = np.zeros(len(idx), np.int64)
        ok = (idx >= 0)
        ok[ok] = self.cnt[idx[ok]] > 0
        out[ok] = self.m.items[self.off[idx[ok]]]
        return out

    def ground_at(self, idx, dx, dy):
        """ground id (first item when it is a ground, else 0) of the neighbour (dx, dy) of tiles idx"""
        t = self.m.tiles
        j = self.lookup(t['x'][idx].astype(np.int64) + dx, t['y'][idx].astype(np.int64) + dy, t['z'][idx])
        f = self.first_ids(j)
        return np.where(self.ground_lut[f], f, 0)

    def pos(self, i):
        t = self.m.tiles
        return int(t['x'][i]), int(t['y'][i]), int(t['z'][i])

    def stack(self, i):
        return [int(s) for s in self.m.stack(i)]

    def walkable_stack(self, ids):
        if not ids or not self.ground_lut[ids[0]] or self.solid_lut[ids[0]]:
            return False
        return not any(self.solid_lut[i] and i not in self.doors for i in ids[1:])

    def walk_at(self, x, y, z):
        i = self.m.find(x, y, z)
        return i >= 0 and self.walkable_stack(self.stack(i))


# ------------------------------------------------------------------------------------------------ detectors
# each returns (tile index array, a, b): a and b are ids (or a count / a packed value) shown in the report
def _empty():
    z = np.zeros(0, np.int64)
    return z, z, z


def d_ground(w):
    """NO_GROUND, GROUND_NOT_FIRST"""
    items = w.m.items
    has = w.cnt > 0
    isg = w.ground_lut[items]
    cs = np.zeros(len(items) + 1, np.int32)
    np.cumsum(isg, out=cs[1:])
    ng = cs[w.ends] - cs[w.off]
    first = np.zeros(w.n, np.int64)
    first[has] = items[w.off[has]]
    first_g = np.zeros(w.n, bool)
    first_g[has] = isg[w.off[has]]
    no = np.flatnonzero(has & (ng == 0))
    nf = np.flatnonzero(has & (ng > 0) & (~first_g | (ng > 1)))
    second = np.zeros(len(nf), np.int64)
    for k, i in enumerate(nf):
        ids = w.stack(i)
        for p, v in enumerate(ids):
            if w.ground_lut[v] and p > 0:
                second[k] = v
                break
    return (no, first[no], np.zeros(len(no), np.int64)), (nf, first[nf], second)


def d_dup(w):
    pos = np.flatnonzero(w.dup_lut[w.m.items])
    if not len(pos):
        return _empty()
    tile = w.tile_of(pos)
    key = np.sort(tile.astype(np.int64) * 65536 + w.m.items[pos].astype(np.int64))
    same = np.flatnonzero(key[1:] == key[:-1])
    key = np.unique(key[same])
    t, i = key // 65536, key % 65536
    first = np.unique(t, return_index=True)[1]
    return t[first], i[first], np.zeros(len(first), np.int64)


def d_unknown(w):
    pos = np.flatnonzero(~w.known_lut[w.m.items])
    if not len(pos):
        return _empty()
    tile = w.tile_of(pos)
    first = np.unique(tile, return_index=True)[1]
    return tile[first], w.m.items[pos[first]].astype(np.int64), np.zeros(len(first), np.int64)


def d_many(w):
    t = np.flatnonzero(w.cnt > w.max_items)
    return t, w.cnt[t], np.zeros(len(t), np.int64)


def d_orphan(w):
    borders = w.tables['borders']
    grounds = w.tables['grounds']
    fam = None
    if hasattr(w.db, 'ground_family'):
        fam = np.asarray(w.db.ground_family())
    lut = np.zeros(65536, bool)
    for pid in borders:
        lut[pid] = True
    pos = np.flatnonzero(lut[w.m.items])
    if not len(pos):
        return _empty()
    tile = w.tile_of(pos)
    pid = w.m.items[pos].astype(np.int64)
    over_cache = {}

    def over_ids(families):
        key = tuple(sorted(families))
        if key not in over_cache:
            ids = set()
            for f in families:
                ids |= grounds.get(f, set())
            if fam is not None:
                names = {int(fam[i]) for i in ids if 0 < i < len(fam) and fam[i] > 0}
                if names:
                    ids |= {int(i) for i in np.flatnonzero(np.isin(fam, list(names)))}
            over_cache[key] = np.array(sorted(ids), np.int64)
        return over_cache[key]
    bad_t, bad_a = [], []
    for p in np.unique(pid):
        sel = pid == p
        tt = tile[sel]
        found = np.zeros(len(tt), bool)
        for _setname, name, families in borders[int(p)]:
            ov = over_ids(families)
            f = np.zeros(len(tt), bool)
            for dx, dy in R.PIECE_SIDES[name]:
                f |= np.isin(w.ground_at(tt, dx, dy), ov)
            found |= f
        orphan = tt[~found]
        bad_t.append(orphan)
        bad_a.append(np.full(len(orphan), p, np.int64))
    if not bad_t:
        return _empty()
    t = np.concatenate(bad_t)
    a = np.concatenate(bad_a)
    o = np.argsort(t, kind='stable')
    t, a = t[o], a[o]
    first = np.unique(t, return_index=True)[1]
    return t[first], a[first], np.zeros(len(first), np.int64)


def d_wall(w):
    walls = w.tables['walls']
    brushes = sorted({b for b, _k in walls.values()})
    brush_lut = np.full(65536, -1, np.int64)
    kind_lut = np.zeros(65536, np.int64)
    for pid, (b, k) in walls.items():
        if pid < 65536:
            brush_lut[pid] = brushes.index(b)
            kind_lut[pid] = KIND_ORDER.index(k)
    pos = np.flatnonzero(brush_lut[w.m.items] >= 0)
    if not len(pos):
        return _empty()
    tile = w.tile_of(pos)
    pid = w.m.items[pos].astype(np.int64)
    brush = brush_lut[pid]
    is_wall = []                                           # per brush: the tiles that hold a piece of it
    for b in range(len(brushes)):
        m_ = np.zeros(w.n, bool)
        m_[tile[brush == b]] = True
        is_wall.append(m_)
    first = np.unique(tile, return_index=True)[1]          # the first wall piece of the tile decides
    tile, pid, brush = tile[first], pid[first], brush[first]
    kind = kind_lut[pid]
    t = w.m.tiles
    x, y, z = t['x'][tile].astype(np.int64), t['y'][tile].astype(np.int64), t['z'][tile].astype(np.int64)
    bit = np.zeros(len(tile), np.int64)
    for k, (dx, dy) in enumerate(((0, -1), (1, 0), (0, 1), (-1, 0))):
        j = w.lookup(x + dx, y + dy, z)
        same = np.zeros(len(tile), bool)
        for b in range(len(brushes)):
            sel = (brush == b) & (j >= 0)
            same[sel] = is_wall[b][j[sel]]
        bit |= same.astype(np.int64) << k
    lutk = np.zeros(16, np.int64)
    for m4 in range(16):
        lutk[m4] = KIND_ORDER.index(R.wall_piece(bool(m4 & 1), bool(m4 & 2), bool(m4 & 4), bool(m4 & 8)))
    want = lutk[bit]
    bad = np.flatnonzero(want != kind)
    return tile[bad], pid[bad], want[bad]


def _special_tiles(w, ids):
    lut = np.zeros(65536, bool)
    for i in ids:
        lut[i] = True
    pos = np.flatnonzero(lut[w.m.items])
    if not len(pos):
        return np.zeros(0, np.int64), np.zeros(0, np.int64)
    tile = w.tile_of(pos)
    return tile, w.m.items[pos].astype(np.int64)


def d_doors(w):
    """BLOCKED_DOOR, BLOCKED_ON_SPECIAL (doors and teleports)"""
    tile, ids = _special_tiles(w, w.doors)
    bd_t, bd_a = [], []
    done = set()
    for i, did in zip(tile, ids):
        if int(i) in done:
            continue
        done.add(int(i))
        x, y, z = w.pos(i)
        if not any(w.walk_at(x + dx, y + dy, z) for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0))):
            bd_t.append(int(i))
            bd_a.append(int(did))
    sp_t, sp_a, sp_b = [], [], []
    special = w.doors | w.teles
    stile, _sids = _special_tiles(w, special)
    done = set()
    for i in stile:
        if int(i) in done:
            continue
        done.add(int(i))
        got = R.blocking_on_special(w.stack(i), special, lambda v: bool(w.solid_lut[v]))
        if got:
            sp_t.append(int(i))
            sp_a.append(got[0][0])
            sp_b.append(got[0][1] or 0)
    arr = lambda v: np.array(v, np.int64)
    return (arr(bd_t), arr(bd_a), np.zeros(len(bd_t), np.int64)), (arr(sp_t), arr(sp_a), arr(sp_b))


def d_teleports(w, found):
    """BLOCKED_TELEPORT from [(tile index, item id, (x, y, z))]"""
    tt, aa, bb = [], [], []
    for i, iid, (dx, dy, dz) in found:
        if not w.walk_at(dx, dy, dz):
            tt.append(i)
            aa.append(iid)
            bb.append((dz << 32) | (dy << 16) | dx)
    arr = lambda v: np.array(v, np.int64)
    return arr(tt), arr(aa), arr(bb)


def d_roof(w):
    pos = np.flatnonzero(w.roof_lut[w.m.items])
    if not len(pos):
        return _empty()
    tile = w.tile_of(pos)
    first = np.unique(tile, return_index=True)[1]
    tile, rid = tile[first], w.m.items[pos[first]].astype(np.int64)
    t = w.m.tiles
    z = t['z'][tile].astype(np.int64)
    keep = z <= ROOF_MAX_Z
    tile, rid, z = tile[keep], rid[keep], z[keep]
    below = w.lookup(t['x'][tile].astype(np.int64), t['y'][tile].astype(np.int64), z + 1)
    ok = below >= 0
    supported = np.zeros(len(tile), bool)
    if ok.any():
        b = below[ok]
        items = w.m.items
        first_b = items[w.off[b]] if len(items) else np.zeros(len(b), items.dtype)
        has_b = w.cnt[b] > 0
        walk_ground = has_b & w.ground_lut[first_b] & ~w.solid_lut[first_b]
        built = has_b & ((w.cnt[b] > 1) | ~w.ground_lut[first_b])
        supported[ok] = walk_ground | built
    bad = np.flatnonzero(~supported)
    return tile[bad], rid[bad], np.zeros(len(bad), np.int64)


# ------------------------------------------------------------------------------------------------ the audit
class Findings:
    def __init__(self, w, sel=None):
        self.w = w
        self.sel = sel
        self.by = {c: (np.zeros(0, np.int64),) * 3 for c in CODES}

    def add(self, code, tile, a, b):
        tile, a, b = (np.asarray(v, np.int64) for v in (tile, a, b))
        if self.sel is not None and len(tile):
            keep = self.sel[tile]
            tile, a, b = tile[keep], a[keep], b[keep]
        o = np.lexsort((self.w.m.tiles['x'][tile], self.w.m.tiles['y'][tile], self.w.m.tiles['z'][tile])) if len(tile) else tile
        self.by[code] = (tile[o], a[o], b[o]) if len(tile) else (tile, a, b)

    def count(self, code):
        return len(self.by[code][0])

    def rows(self, code):
        """[(x, y, z, ids text)]"""
        t, a, b = self.by[code]
        for k in range(len(t)):
            x, y, z = self.w.pos(t[k])
            yield (x, y, z, self.ids_text(code, int(a[k]), int(b[k])))

    def keys(self, code):
        """the findings of a code as sorted int64 keys z << 32 | y << 16 | x (one per tile)"""
        t = self.by[code][0]
        if not len(t):
            return np.zeros(0, np.int64)
        m = self.w.m.tiles
        return np.unique((m['z'][t].astype(np.int64) << 32) | (m['y'][t].astype(np.int64) << 16) | m['x'][t].astype(np.int64))

    @staticmethod
    def ids_text(code, a, b):
        if code == 'GROUND_NOT_FIRST':
            return '%d,%d' % (a, b) if b else '%d' % a
        if code == 'BLOCKED_ON_SPECIAL':
            return '%d,%d' % (a, b) if b else '%d' % a
        if code == 'BLOCKED_TELEPORT':
            return '%d>%d,%d,%d' % (a, b & 0xFFFF, (b >> 16) & 0xFFFF, b >> 32)
        if code == 'WALL_MISMATCH':
            return '%d,%s' % (a, KIND_ORDER[b])
        if code == 'TOO_MANY_ITEMS':
            return 'count=%d' % a
        return '%d' % a


def audit(w, box=None, floor=None, teles_found=None):
    """-> Findings. box = (x1, y1, x2, y2); floor = z"""
    sel = None
    if box is not None or floor is not None:
        t = w.m.tiles
        sel = np.ones(w.n, bool)
        if floor is not None:
            sel &= t['z'] == floor
        if box is not None:
            sel &= (t['x'] >= box[0]) & (t['x'] <= box[2]) & (t['y'] >= box[1]) & (t['y'] <= box[3])
    f = Findings(w, sel)
    no, nf = d_ground(w)
    f.add('NO_GROUND', *no)
    f.add('GROUND_NOT_FIRST', *nf)
    f.add('DUP_ITEM', *d_dup(w))
    f.add('UNKNOWN_ID', *d_unknown(w))
    f.add('TOO_MANY_ITEMS', *d_many(w))
    f.add('ORPHAN_BORDER', *d_orphan(w))
    f.add('WALL_MISMATCH', *d_wall(w))
    bd, sp = d_doors(w)
    f.add('BLOCKED_DOOR', *bd)
    f.add('BLOCKED_ON_SPECIAL', *sp)
    f.add('BLOCKED_TELEPORT', *d_teleports(w, teles_found or []))
    f.add('ROOF_NO_SUPPORT', *d_roof(w))
    return f


# ------------------------------------------------------------------------------------------------ files and output
def data_dir(server_dir):
    d = os.path.join(server_dir, 'data')
    return d if os.path.isdir(d) else server_dir


def map_path(ddir):
    world = os.path.join(ddir, 'world')
    cfg = os.path.join(os.path.dirname(os.path.abspath(ddir)), 'config.lua')
    if os.path.isfile(cfg):
        m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', open(cfg, encoding='utf-8', errors='replace').read(), re.M)
        if m and os.path.isfile(os.path.join(world, m.group(1) + '.otbm')):
            return os.path.join(world, m.group(1) + '.otbm')
    maps = sorted(n for n in os.listdir(world) if n.endswith('.otbm')) if os.path.isdir(world) else []
    return os.path.join(world, maps[0]) if len(maps) == 1 else None


def load_world(map_file, otb, xml=None, max_items=MAX_ITEMS, log=print, db=None, tables=None):
    """-> (World, [(tile, id, dest)] of the teleports with a destination)"""
    import otbm
    from itemdb import ItemDB
    if db is None:
        if not otb or not os.path.isfile(otb):
            raise AuditError('no items.otb (%s)' % otb)
        db = ItemDB(otb, xml if xml and os.path.isfile(xml) else None)
    log('reading %s ...' % map_file)
    m = otbm.load_otbm(map_file)
    doors = {int(i) for i in np.flatnonzero(db.group == DOOR_GROUP)} | xml_type_ids(xml, 'door')
    teles = {int(i) for i in np.flatnonzero(db.group == TELEPORT_GROUP)} | xml_type_ids(xml, 'teleport')
    found = otbm.teleports(m, teles) if teles else []
    m._raw = None            # the node arrays are as big as the file: the audit needs the tiles only
    w = World(m, db, doors, teles, roof_ids_of_patch(), tables, max_items)
    log('%d tiles, %d items' % (w.n, len(m.items)))
    return w, found


def read_known(path=KNOWN):
    """{(code, x, y, z): reason}"""
    out = {}
    if path and os.path.isfile(path):
        for row in csv.DictReader(l for l in open(path, encoding='utf-8') if not l.startswith('#')):
            out[(row['code'], int(row['x']), int(row['y']), int(row['z']))] = row.get('reason', '')
    return out


def _known_keys(known):
    """{code: sorted int64 keys} of the known list"""
    by = {}
    for (c, x, y, z) in known:
        by.setdefault(c, []).append((z << 32) | (y << 16) | x)
    return {c: np.array(sorted(v), np.int64) for c, v in by.items()}


def write_csv(path, f):
    with open(path, 'w', encoding='utf-8', newline='') as fh:
        wr = csv.writer(fh, lineterminator='\n')
        wr.writerow(['code', 'x', 'y', 'z', 'ids', 'fix'])
        for c in CODES:
            for x, y, z, t in f.rows(c):
                wr.writerow([c, x, y, z, t, FIX[c]])


def report(f, known, limit=20, summary=False, log=print):
    """prints the report; -> (new findings count, stale known keys)"""
    new = total = 0
    kk = _known_keys(known)
    seen = {}
    for c in CODES:
        keys = f.keys(c)
        seen[c] = keys
        is_known = np.isin(keys, kk.get(c, np.zeros(0, np.int64)))
        n_new = int((~is_known).sum())
        new += n_new
        total += len(keys)
        log('%-18s %7d  (%d known, %d new)  %s' % (c, len(keys), len(keys) - n_new, n_new, WHAT[c]))
    log('total %d findings, %d not in the known list' % (total, new))
    if not summary:
        for c in CODES:
            shown = 0
            for x, y, z, t in f.rows(c):
                if shown >= limit:
                    log('  ... %d more %s (--csv has all of them, --limit N)' % (f.count(c) - shown, c))
                    break
                log('%s %d,%d,%d ids=%s fix=%s%s' % (c, x, y, z, t, FIX[c], ' (known)' if (c, x, y, z) in known else ''))
                shown += 1
    stale = []
    for (c, x, y, z) in known:
        key = (z << 32) | (y << 16) | x
        if c in seen:
            k = seen[c]
            i = np.searchsorted(k, key)
            if not (i < len(k) and k[i] == key):
                stale.append((c, x, y, z))
    return new, sorted(stale)


def run(server_dir=None, map_file=None, otb=None, xml=None, box=None, floor=None, csv_path=None, known_path=KNOWN,
        check=False, summary=False, limit=20, max_items=MAX_ITEMS, log=print, world=None):
    if world is None:
        if server_dir:
            ddir = data_dir(server_dir)
            map_file = map_file or map_path(ddir)
            otb = otb or os.path.join(ddir, 'items', 'items.otb')
            xml = xml or os.path.join(ddir, 'items', 'items.xml')
        if not map_file or not os.path.isfile(map_file):
            raise AuditError('no map (give SERVER_DIR with data/world/<map>.otbm, or --map)')
        world = load_world(map_file, otb, xml, max_items, log)
    w, found = world
    f = audit(w, box, floor, found)
    known = read_known(known_path)
    new, stale = report(f, known, limit, summary, log)
    stale = [k for k in stale if _inside(k, box, floor)]
    for k in stale[:limit]:
        log('known entry no longer found: %s %d,%d,%d' % k)
    if csv_path:
        write_csv(csv_path, f)
        log('wrote %s' % csv_path)
    if check and new:
        log('NEW findings: %d (not in %s)' % (new, os.path.basename(known_path or KNOWN)))
        return f, 1
    return f, 0


def _inside(k, box, floor):
    _c, x, y, z = k
    if floor is not None and z != floor:
        return False
    return box is None or (box[0] <= x <= box[2] and box[1] <= y <= box[3])


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--box', '--floor', '--csv', '--known', '--map', '--items', '--xml', '--limit', '--max-items'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--check', '--summary', '--quiet'):
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
    try:
        box = tuple(int(v) for v in opts['--box'].split(',')) if '--box' in opts else None
        if box is not None and (len(box) != 4 or box[0] > box[2] or box[1] > box[3]):
            raise ValueError
        floor = int(opts['--floor']) if '--floor' in opts else None
        limit = int(opts.get('--limit', 20))
        max_items = int(opts.get('--max-items', MAX_ITEMS))
    except ValueError:
        print('bad --box (x1,y1,x2,y2 with x1 <= x2, y1 <= y2), --floor, --limit or --max-items')
        return 1
    try:
        _f, rc = run(pos[0] if pos else None, opts.get('--map'), opts.get('--items'), opts.get('--xml'), box, floor,
                     opts.get('--csv'), opts.get('--known', KNOWN), bool(opts.get('--check')), bool(opts.get('--summary')), limit,
                     max_items, log=(lambda *_: None) if opts.get('--quiet') else print)
    except (AuditError, OSError) as e:
        print('refused: %s' % e)
        return 1
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

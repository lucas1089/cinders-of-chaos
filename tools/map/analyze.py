"""Per-tile features and area metrics for OTBM maps (shared by survey.py and score_area.py).

Terms used everywhere:
  open tile     - has a ground that does not block (not mountain/earth fill, deep water, lava pools...)
                  and no wall item: the area a player sees as terrain
  walkable      - open and nothing on it blocks movement (doors and floor changes count as walkable)
  deco          - items of class nature, furniture, other, light, top or splash (not ground, border,
                  wall, door, floor change)
  transition    - two 4-neighbour open-or-fill tiles whose grounds belong to different ground families
                  in the natural categories (grass, earth, sand, ice, swamp, lava, water, mountain, street)
  bordered      - at least one of the two tiles carries a border item
  walled        - at least one of the two tiles carries a wall item (cave walls, mountain sides)
  area type     - per 16x16 block of one floor, from its walkable tiles: town, building, dungeon, cave,
                  forest, grassland, desert, ice, swamp, lava, water, dirt, exotic (see block_type())
"""
import re
import numpy as np

GCATS = ['none', 'grass', 'earth', 'sand', 'ice', 'swamp', 'lava', 'water', 'mountain', 'street', 'floor', 'roof', 'exotic']
G = {c: i for i, c in enumerate(GCATS)}
NATURAL = np.zeros(len(GCATS), bool)
for c in ('grass', 'earth', 'sand', 'ice', 'swamp', 'lava', 'water', 'mountain', 'street'):
    NATURAL[G[c]] = True

_RULES = [
    ('roof', r'roof'),
    ('earth', r'^muddy floor$|^dry floor$|^mossy floor$|^dirt floor$|^rock soil$|^earth|^dried mud'),
    ('water', r'water|ocean floor|sea floor|brook|^kelp'),
    ('lava', r'lava|basalt|sulphur|magma|volcan|\bash\b'),
    ('swamp', r'swamp|\bmud\b|slime|\btar\b|poison|pestiferous|bog\b|marsh'),
    ('ice', r'snow|\bice\b|icy|frozen|frost|glacier'),
    ('floor', r'sandstone floor|sandstone tile|sandy tile'),
    ('sand', r'sand|desert'),
    ('grass', r'grass|forest floor|herbacea|leaves|flowers|lush|moss\b|meadow|turf'),
    ('street', r'pavement|cobble|\broad\b|paving|paved|street'),
    ('mountain', r'mountain|wall|\bgap\b|void|^rock$|^sandstone$|^stone$|grotto|cliff|chasm'),
    ('earth', r'earth|dirt|soil|gravel|stony|pebble|\bdry\b|\bmud|cave|rutted|clay|ground$'),
    ('floor', r'floor|tile|plank|carpet|parquet|marble|terracotta|ornament|plaster|timber|board|bridge|raft|deck|stairs|ramp'),
]
_RULES = [(c, re.compile(p, re.I)) for c, p in _RULES]


def ground_category(name):
    if not name:
        return G['exotic']
    for c, p in _RULES:
        if p.search(name):
            return G[c]
    return G['exotic']


AREA_TYPES = ['town', 'building', 'dungeon', 'cave', 'forest', 'grassland', 'dirt', 'desert', 'ice', 'swamp', 'lava', 'water', 'exotic']
A = {a: i for i, a in enumerate(AREA_TYPES)}


class ItemTables:
    """vectorised per-server-id lookups derived from an ItemDB"""
    def __init__(self, db):
        from itemdb import C
        self.db = db
        cls = db.cls
        self.is_ground = cls == C['ground']
        self.is_border = cls == C['border']
        self.is_wall = cls == C['wall']
        self.is_door = cls == C['door']
        self.is_fc = cls == C['floorchg']
        self.is_nature = cls == C['nature']
        self.is_furn = cls == C['furniture']
        self.is_deco = np.isin(cls, [C['nature'], C['furniture'], C['other'], C['light'], C['top'], C['splash']])
        self.is_light = db.light > 0
        # blocking grounds that are walls themselves (old-style cave walls: 'dirt wall', 'stone wall' grounds)
        wn = re.compile(r'wall', re.I)
        self.wallground = np.zeros(len(cls), bool)
        for sid in np.flatnonzero(self.is_ground & db.block):
            if wn.search(db.name[sid]):
                self.wallground[sid] = True
        self.block = db.block.copy()
        self.block[self.is_door | self.is_fc] = False
        self.known = db.known
        fam = db.ground_family()
        self.fam = fam
        gcat = np.zeros(len(cls), np.uint8)
        for sid in np.flatnonzero(self.is_ground):
            gcat[sid] = ground_category(db.name[sid])
        self.gcat = gcat
        n = db.name
        lad = re.compile(r'ladder', re.I); sta = re.compile(r'stair', re.I); ram = re.compile(r'ramp', re.I)
        hol = re.compile(r'hole|pitfall|trapdoor|sewer grate|grate', re.I); rope = re.compile(r'rope spot', re.I)
        fck = np.zeros(len(cls), np.uint8)    # 1 ladder 2 stairs 3 ramp 4 hole 5 rope spot 6 teleport 7 other
        for sid in np.flatnonzero(self.is_fc | (db.group == 7)):
            s = n[sid]
            fck[sid] = 1 if lad.search(s) else 2 if sta.search(s) else 3 if ram.search(s) else 5 if rope.search(s) \
                else 4 if hol.search(s) else 6 if db.group[sid] == 7 else 7
        self.fckind = fck


def tile_features(m, it):
    """per-tile arrays for map m (otbm.Map) using ItemTables it"""
    t = m.tiles
    n = len(t['x'])
    cnt = t['cnt'].astype(np.int64)
    owner = np.repeat(np.arange(n), cnt)
    ids = m.items.astype(np.int64)

    def per_tile(mask):
        return np.bincount(owner, weights=mask[ids], minlength=n).astype(np.int32)

    # ground = first ground-class item of the stack
    isg = it.is_ground[ids]
    gpos = np.flatnonzero(isg)
    first = np.full(n, -1, np.int64)
    o = owner[gpos]
    keep = np.ones(len(o), bool); keep[1:] = o[1:] != o[:-1]
    first[o[keep]] = gpos[keep]
    gid = np.where(first >= 0, ids[np.maximum(first, 0)], 0).astype(np.int32)
    f = dict(x=t['x'].astype(np.int32), y=t['y'].astype(np.int32), z=t['z'].astype(np.int32), gid=gid,
             fam=it.fam[gid], gcat=it.gcat[gid], house=t['house'] > 0, pz=(t['flags'] & 1) > 0)
    f['nb'] = per_tile(it.is_border); f['nw'] = per_tile(it.is_wall | it.wallground); f['nd'] = per_tile(it.is_deco)
    f['nn'] = per_tile(it.is_nature); f['nf'] = per_tile(it.is_furn); f['nl'] = per_tile(it.is_light & ~it.is_ground)
    f['ndoor'] = per_tile(it.is_door); f['nfc'] = per_tile(it.is_fc); f['nunk'] = per_tile(~it.known)
    f['nblk'] = per_tile(it.block)
    f['nitems'] = cnt.astype(np.int32)
    gblock = it.block[gid] & (gid > 0)
    f['open'] = (gid > 0) & ~gblock & (f['nw'] == 0)
    f['walk'] = f['open'] & (f['nblk'] == 0)
    f['fill'] = (gid > 0) & (gblock | (f['nw'] > 0))
    return f


def to_dense(f, sel, x0, y0, w, h):
    """dense (h, w) arrays of the features of tile indices sel inside the rectangle"""
    D = {}
    xi = f['x'][sel] - x0; yi = f['y'][sel] - y0
    for k in ('gid', 'fam', 'gcat', 'nb', 'nw', 'nd', 'nn', 'nf', 'nl', 'ndoor', 'nfc', 'nunk', 'nitems'):
        a = np.zeros((h, w), np.int32); a[yi, xi] = f[k][sel]; D[k] = a
    for k in ('house', 'pz', 'open', 'walk', 'fill'):
        a = np.zeros((h, w), bool); a[yi, xi] = f[k][sel]; D[k] = a
    D['present'] = np.zeros((h, w), bool); D['present'][yi, xi] = True
    return D


def transitions(D, water=False):
    """(transitions, bordered, walled) over horizontal and vertical neighbour pairs.
    Pairs with water on one side are left out (many shores are drawn with edge variants of the water
    ground itself, which no item test can see); water=True counts only those pairs instead."""
    tot = bor = wal = 0
    W = G['water']
    for a, b in (((slice(None), slice(None, -1)), (slice(None), slice(1, None))),
                 ((slice(None, -1), slice(None)), (slice(1, None), slice(None)))):
        fa, fb = D['fam'][a], D['fam'][b]
        ca, cb = D['gcat'][a], D['gcat'][b]
        tr = (fa > 0) & (fb > 0) & (fa != fb) & NATURAL[ca] & NATURAL[cb] & (D['open'][a] | D['open'][b])
        wat = (ca == W) | (cb == W)
        tr &= wat if water else ~wat
        nb = (D['nb'][a] > 0) | (D['nb'][b] > 0)
        nw = (D['nw'][a] > 0) | (D['nw'][b] > 0)
        tot += int(tr.sum()); bor += int((tr & nb).sum()); wal += int((tr & ~nb & nw).sum())
    return tot, bor, wal


def run_lengths(mask, axis):
    """length of the run of True cells through each cell along axis (0 = vertical, 1 = horizontal)"""
    a = mask if axis == 1 else mask.T
    h, w = a.shape
    pad = np.zeros((h, w + 2), bool); pad[:, 1:-1] = a
    d = np.diff(pad.astype(np.int8), axis=1)
    out = np.zeros((h, w), np.int32)
    rs, cs = np.nonzero(d == 1); re_, ce = np.nonzero(d == -1)
    for r0, c0, c1 in zip(rs, cs, ce):
        out[r0, c0:c1] = c1 - c0
    return out if axis == 1 else out.T


def block_type(D, z, sl):
    """area type of one block (slice) from its walkable tiles; None when < 40 open tiles"""
    op = D['open'][sl]
    n = int(op.sum())
    if n < 40:
        return None
    gc = D['gcat'][sl][op]
    share = np.bincount(gc, minlength=len(GCATS)) / n
    house = D['house'][sl][op].mean(); pz = D['pz'][sl][op].mean()
    built = share[G['floor']] + share[G['street']]
    if house >= 0.10 or (pz >= 0.30 and z <= 7) or (share[G['street']] >= 0.15 and z <= 7):
        return 'town'
    if built >= 0.5:
        return 'dungeon' if z >= 8 else 'building'
    nat = ['grass', 'earth', 'sand', 'ice', 'swamp', 'lava', 'water']
    best = max(nat, key=lambda c: share[G[c]])
    if share[G[best]] < 0.35:
        return 'exotic' if share[G['exotic']] >= 0.35 else ('dungeon' if z >= 8 else 'building') if built > 0.3 else 'exotic'
    if best == 'earth':
        return 'cave' if z >= 8 else 'dirt'
    if best == 'grass':
        trees = (D['nw'][sl] > 0) | (D['nn'][sl] > 0)
        return 'forest' if D['nn'][sl].sum() / n >= 0.25 else 'grassland'
    return {'sand': 'desert', 'ice': 'ice', 'swamp': 'swamp', 'lava': 'lava', 'water': 'water'}[best]


def block_metrics(D, sl):
    """sums for one block; ratios are formed later so blocks can be added up"""
    op = D['open'][sl]; wk = D['walk'][sl]
    n = int(op.sum())
    sub = {k: D[k][sl] for k in ('gid', 'fam', 'gcat', 'nb', 'nw', 'nd', 'nn', 'nf', 'nl', 'open')}
    tr, bo, wa = transitions(sub)
    wtr, wbo, wwa = transitions(sub, water=True)
    nd = D['nd'][sl][op]
    gids = D['gid'][sl][op]; fams = D['fam'][sl][op]
    # ground variation inside the dominant family
    if len(fams):
        fam0 = np.bincount(fams).argmax()
        g0 = gids[fams == fam0]
        u, c = np.unique(g0, return_counts=True)
        variants, topshare = len(u), c.max() / c.sum()
    else:
        variants, topshare = 0, 1.0
    return dict(open=n, walk=int(wk.sum()), deco=int(nd.sum()), nature=int(D['nn'][sl][op].sum()),
                furn=int(D['nf'][sl][op].sum()), light=int(D['nl'][sl].sum()), empty=int((nd == 0).sum()),
                heavy=int((nd >= 3).sum()), borders=int(D['nb'][sl].sum()), trans=tr, bordered=bo, walled=wa, wtrans=wtr, wbordered=wbo + wwa,
                variants=variants, topshare=float(topshare), unknown=int(D['nunk'][sl].sum()),
                items=int(D['nitems'][sl].sum()), fc=int(D['nfc'][sl].sum()))


def summarize(rows):
    """aggregate block metric dicts into ratios"""
    if not rows:
        return {}
    s = {k: sum(r[k] for r in rows) for k in ('open', 'walk', 'deco', 'nature', 'furn', 'light', 'empty', 'heavy',
                                               'borders', 'trans', 'bordered', 'walled', 'unknown', 'items', 'fc', 'wtrans', 'wbordered')}
    o = max(s['open'], 1)
    var = np.array([r['variants'] for r in rows]); top = np.array([r['topshare'] for r in rows])
    deco_b = np.array([r['deco'] / max(r['open'], 1) for r in rows])
    return dict(blocks=len(rows), open_tiles=s['open'],
                deco_per_tile=round(s['deco'] / o, 3), nature_per_tile=round(s['nature'] / o, 3),
                furniture_per_tile=round(s['furn'] / o, 3), lights_per_100=round(100 * s['light'] / o, 2),
                empty_share=round(s['empty'] / o, 3), heavy_share=round(s['heavy'] / o, 4),
                walkable_share=round(s['walk'] / o, 3),
                transitions_per_100=round(100 * s['trans'] / o, 2),
                border_coverage=round(s['bordered'] / s['trans'], 3) if s['trans'] else None,
                border_or_wall=round((s['bordered'] + s['walled']) / s['trans'], 3) if s['trans'] else None,
                borders_per_100=round(100 * s['borders'] / o, 2),
                water_edges_per_100=round(100 * s['wtrans'] / o, 2),
                water_edge_coverage=round(s['wbordered'] / s['wtrans'], 3) if s['wtrans'] else None,
                ground_variants_median=float(np.median(var)), flat_block_share=round(float((top >= 0.95).mean()), 3),
                deco_block_p25=round(float(np.percentile(deco_b, 25)), 3), deco_block_p75=round(float(np.percentile(deco_b, 75)), 3),
                unknown_items=s['unknown'], floorchanges_per_1000=round(1000 * s['fc'] / o, 2))

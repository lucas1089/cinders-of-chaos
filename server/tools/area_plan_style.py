#!/usr/bin/env python3
"""Style profiles of the area planner (O743; server/README.md "Style profile (O743)").

A style profile (`areaplan/styles/<key>.json`, schema `chaos-area-style/1`) holds shares and statistics of a painted
area, learned by area_style_learn.py: which ground families, wall brushes and decoration groups it uses and how much,
how dense the decoration is and how it groups. It never holds a position or a tile layout.

A plan names one with the field `style`. The compiler then takes from it:
  * the floor family, the room floors (dungeon) or the ground patches (cave, waste), and the wall brush (dungeon),
    passed to the area generator as `job.style` (areaplan_build.lua; a family or brush our tables lack is left out,
    a patch with no border rule against the floor too);
  * the decoration kit: in every category of the biome's kit, the profile's groups that some kit uses in that
    category, weighted by their share (a category with none keeps the biome's rows);
  * the decoration density (the profile's items per 100 walkable tiles against REF_PER100, times `decoration`) and
    the clusters (how many per 100 tiles, how many pieces round an anchor), drawn with the compile's seeded rng;
  * O745: the lights (light items per 100 walkable tiles against REF_LIGHT_PER100 of the layout kind), the debris
    share of the decoration in the kit categories that kept the biome's rows (against REF_DEBRIS_SHARE of the kind)
    and the width of a plan path that names none (the most common corridor width of 2-6 tiles, `path_width`).
Without `style` nothing here runs: every held plan compiles to the same bytes.

This module also holds the item catalogue the learner classifies with and the copy guard (`window_matches`).
"""
import csv
import json
import os
import re
import subprocess

import area_plan_core as C
import area_plan_decor as D

STYLE_DIR = os.path.join(C.PLANDIR, 'styles')
SCHEMA = 'chaos-area-style/1'
KEY_RE = re.compile(r'^[a-z][a-z0-9_]{1,39}$')
ART_CSV = os.path.join(C.SERVER, 'data', 'items', 'art_items.csv')
# decoration items (every item that is no ground, border piece, wall piece or link) per 100 walkable tiles of the six
# examples at decoration "normal" (area_style_learn.learn on each whole compiled area, 2026-11-23; temple_throne is
# "dense" and left out): the density a profile is measured against. They gave 33.5-46.8, mean 38.2.
REF_PER100 = 38.2
DENSITY_RANGE = (0.4, 2.5)
# O745: light and debris items per 100 walkable tiles of the same six examples by layout kind (area_style_learn.learn on
# each whole compiled area, 2026-11-23): dungeon crypt_boss; cave lava_cave and swamp_hunt; waste river_hunt,
# ruined_hamlet and village_square. Lights differ by kind far more than by plan (6.7 in the crypt, 0.3-0.6 in the
# open biomes), so a profile is measured against its own kind. Debris counts as a share of the decoration.
REF_LIGHT_PER100 = {'dungeon': 6.723, 'cave': 3.547, 'waste': 0.413}
REF_DECOR_PER100 = {'dungeon': 46.849, 'cave': 39.873, 'waste': 34.129}
REF_DEBRIS_PER100 = {'dungeon': 21.289, 'cave': 14.327, 'waste': 4.520}
LIGHT_RANGE = (0.4, 2.5)
DEBRIS_RANGE = (0.5, 2.0)
PATH_WIDTHS = (2, 3, 4, 5, 6)       # corridor widths a plan path takes (1: a seam, 7+: a room)
CLUSTER_PIECES = (1, 8)      # details round a cluster anchor drawn from the profile (the biome default is 2-5)
VEG_WORDS = ('tree', 'bush', 'grass', 'fern', 'plant', 'flower', 'reed', 'mushroom', 'moss', 'lichen', 'gnarl',
             'claw', 'thorn', 'corn', 'pumpkin', 'vine', 'leaf', 'leaves', 'shrub', 'cap')
DEBRIS_WORDS = ('bone', 'skeleton', 'debris', 'rubble', 'ash', 'coffin', 'sarcophag', 'grave', 'corpse', 'skull',
                'remains', 'pebble', 'stones', 'stone pile', 'crack', 'web')
_cat = {}


# ================================================================================================= catalogue
def styleids(pair24=False, dark=False):
    """the generator's own ids by role (areaplan_build.lua styleids)"""
    args = [C.lua_bin(), 'tools/areaplan_build.lua', 'styleids'] + (['pair24'] if pair24 else []) + (['dark'] if dark else [])
    return json.loads(subprocess.run(args, cwd=C.SERVER, check=True, capture_output=True, text=True).stdout)


def art_names(path=ART_CSV):
    """{server id: (key, name)} of data/items/art_items.csv"""
    out = {}
    with open(path, encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            try:
                out[int(r['server_id'])] = (r['key'], r['name'])
            except (TypeError, ValueError):
                continue
    return out


def catalogue(pair24=False, dark=False):
    """every id the planner knows, by role: ground -> family, wall piece -> brush and kind, decoration kit id ->
    group, the generator's border pieces, flat scatter, blocking pieces and lights, the art items; `legal` is their
    union (an id outside it is reported and dropped by the learner)"""
    key = (pair24, dark)
    if key in _cat:
        return _cat[key]
    mats = C.materials(pair24, dark)
    gen = styleids(pair24, dark)
    kit = D.kits()
    art = art_names()
    ground, fam_walk, fam_indoor = {}, {}, {}
    for name in sorted(mats['families']):
        f = mats['families'][name]
        fam_walk[name] = f['walk']
        fam_indoor[name] = f.get('indoor', False)
        for i in f['grounds']:
            ground.setdefault(i, name)
    for name in sorted(gen.get('water') or {}):       # rivers and lakes (O739): families only a def with water adds
        f = gen['water'][name]
        fam_walk[name] = f['walk']
        fam_indoor[name] = False
        for i in f['grounds']:
            ground.setdefault(i, name)
    wall, wall_kind = {}, {}
    for name in sorted(mats['walls']):
        for kind, ids in sorted(mats['walls'][name].items()):
            for i in ids:
                wall.setdefault(i, name)
                wall_kind.setdefault(i, kind)
    group = {}
    for name in sorted(kit['groups']):
        for i in kit['groups'][name]['ids']:
            group.setdefault(i, name)
    special = set(kit['brushes'].values()) | set(C.catalogue(pair24, dark)['items'].values())
    pieces = set(gen['pieces'])
    for i, (k, _n) in art.items():
        if k.startswith('border_'):
            pieces.add(i)
    legal = set(ground) | set(wall) | set(group) | pieces | special | set(gen['flat']) | set(gen['block']) | set(gen['light']) | set(art)
    cat = dict(ground=ground, fam_walk=fam_walk, fam_indoor=fam_indoor, wall=wall, wall_kind=wall_kind, group=group,
               groups=kit['groups'], pieces=pieces, special=special, rim=set(gen['rim']), flat=set(gen['flat']), block=set(gen['block']),
               light=set(gen['light']), art=art, legal=legal, walls=sorted(mats['walls']), families=mats['families'])
    _cat[key] = cat
    return cat


def _words(text, words):
    t = (text or '').lower()
    return any(w in t for w in words)


def item_class(cat, iid):
    """(role, flags) of an item that is not the tile's ground: role 'border', 'wall', 'special' (stairs,
    hole, ladder, portal, chest: counted nowhere), 'decor' or None (unknown);
    flags of a decoration item: block, light, vegetation, debris; a border piece of a family nobody walks on (a cliff
    edge) has block"""
    if iid in cat['pieces']:
        return 'border', {'block': iid in cat['rim']}
    if iid in cat['wall']:
        return 'wall', {}
    if iid in cat['special']:
        return 'special', {}
    if iid not in cat['legal']:
        return None, {}
    g = cat['group'].get(iid)
    if g:
        gd = cat['groups'][g]
        name = g + ' ' + gd.get('name', '')
        block, light = bool(gd['block']), bool(gd['light'])
    else:
        key, nm = cat['art'].get(iid, ('', ''))
        name = key + ' ' + nm
        block = iid in cat['block']
        light = iid in cat['light']
    return 'decor', dict(block=block, light=light, vegetation=_words(name, VEG_WORDS),
                         debris=_words(name, DEBRIS_WORDS), group=g)


# ================================================================================================= profiles
def path_of(key, style_dir=None):
    return os.path.join(style_dir or STYLE_DIR, key + '.json')


def problems(prof):
    """what is wrong with a profile dict ([] when it is usable)"""
    out = []
    if not isinstance(prof, dict) or prof.get('schema') != SCHEMA:
        return ['not a %s profile' % SCHEMA]
    for k in ('grounds', 'walls', 'decor', 'density', 'clusters'):
        if not isinstance(prof.get(k), dict):
            out.append('no %s' % k)
    def walk(v):
        if isinstance(v, dict):
            for k, x in v.items():
                if k in FORBIDDEN and isinstance(x, (dict, list)):
                    out.append('the profile has a "%s" field: a profile holds shares and statistics only' % k)
                walk(x)
        elif isinstance(v, list):
            for x in v:
                if isinstance(x, (list, dict)):
                    out.append('the profile holds a nested list: a profile holds shares and statistics only')
                    return
    walk(prof)
    return out


FORBIDDEN = ('positions', 'position', 'tiles', 'layout', 'cells', 'map', 'rows', 'grid')


def load(key, style_dir=None):
    """the profile of a key; ValueError when it is missing or broken"""
    if not isinstance(key, str) or not KEY_RE.match(key):
        raise ValueError('style key "%s": lower-case letters, digits and _' % key)
    p = path_of(key, style_dir)
    if not os.path.isfile(p):
        raise ValueError('no style profile %s' % os.path.relpath(p, C.SERVER))
    prof = json.load(open(p, encoding='utf-8'))
    bad = problems(prof)
    if bad:
        raise ValueError('style profile %s: %s' % (key, '; '.join(bad)))
    return prof


def keys(style_dir=None):
    d = style_dir or STYLE_DIR
    return sorted(f[:-5] for f in os.listdir(d) if f.endswith('.json')) if os.path.isdir(d) else []


def _ranked(shares, keep=None, least=0.0):
    rows = [(k, v) for k, v in shares.items() if v >= least and (keep is None or keep(k))]
    return sorted(rows, key=lambda kv: (-kv[1], kv[0]))


def job_style(prof, kind, mats):
    """the generator's job.style of a profile for a layout kind: floor, room floors (dungeon) or patches (cave and
    waste), wall brush (dungeon); None when the profile has no walkable family our tables know"""
    fams = mats['families']
    # a building's floor (indoor) is no ground of an open cave or waste
    usable = lambda f: f in fams and fams[f]['walk'] and (kind == 'dungeon' or not fams[f].get('indoor'))  # noqa: E731
    walk = _ranked(prof['grounds'].get('families', {}), usable)
    if not walk:
        return None
    out = dict(floor=walk[0][0])
    if kind == 'dungeon':
        rooms = []
        for f, s in walk[:4]:
            if s >= 0.08:
                rooms += [f] * max(1, int(round(s * 4)))
        out['roomFloors'] = rooms or [walk[0][0]]
        brushes = _ranked(prof['walls'].get('brushes', {}), lambda b: b in mats['walls'])
        if brushes:
            out['wall'] = brushes[0][0]
    else:
        out['patches'] = [dict(family=f, share=round(min(0.25, s), 4), radius=[2, 4]) for f, s in walk[1:5] if s >= 0.02]
    return out


def kit_categories(kits_doc=None):
    """{category: set of groups some kit uses in it} (lists of [group, weight] rows only)"""
    k = kits_doc or D.kits()
    out = {}
    for kit in k['kits'].values():
        for c, rows in kit.items():
            if isinstance(rows, list):
                out.setdefault(c, set()).update(r[0] for r in rows if isinstance(r, list) and r)
    return out


def styled_kit(prof, kit, kits_doc=None):
    """the biome's kit with every list category drawn from the profile's groups that fit it (weights from the
    shares, 1000 per whole share, at least 1); the hall pieces and the kit's rates stay"""
    if not kit:
        return kit
    k = kits_doc or D.kits()
    fits = kit_categories(k)
    shares = prof['decor'].get('groups', {})
    out = json.loads(json.dumps(kit))
    for c, rows in kit.items():
        if not isinstance(rows, list):
            continue
        mine = [[g, max(1, int(round(s * 1000)))] for g, s in _ranked(shares, lambda g: g in k['groups'] and g in fits.get(c, ()))]
        if mine:
            out[c] = mine
    return out


def density_factor(prof):
    lo, hi = DENSITY_RANGE
    return max(lo, min(hi, float(prof['density'].get('decor_per100', REF_PER100)) / REF_PER100))


def cluster_sizes(prof):
    """[(pieces round the anchor, weight)] from the profile's groups of 3+ decorated tiles"""
    lo, hi = CLUSTER_PIECES
    rows = []
    for s, w in sorted(prof['clusters'].get('sizes', {}).items()):
        n = int(s.rstrip('+'))
        if n >= 3 and w > 0:
            rows.append((max(lo, min(hi, n - 1)), w))
    return rows or [(2, 1), (3, 1), (4, 1), (5, 1)]


def pick_weighted(rng, rows):
    total = sum(w for _v, w in rows)
    x = rng.random() * total
    for v, w in rows:
        x -= w
        if x < 0:
            return v
    return rows[-1][0]


def light_factor(prof, kind):
    """O745: the profile's light items per 100 walkable tiles against REF_LIGHT_PER100 of the layout kind, clamped"""
    lo, hi = LIGHT_RANGE
    ref = REF_LIGHT_PER100.get(kind, REF_LIGHT_PER100['waste'])
    return max(lo, min(hi, float(prof['density'].get('light_per100', ref)) / ref))


def debris_factor(prof, kind):
    """O745: the profile's debris share of the decoration against REF_DEBRIS_SHARE of the layout kind, clamped"""
    lo, hi = DEBRIS_RANGE
    k = kind if kind in REF_DEBRIS_PER100 else 'waste'
    ref = REF_DEBRIS_PER100[k] / REF_DECOR_PER100[k]
    d = prof['density']
    if not d.get('decor_per100'):
        return 1.0
    return max(lo, min(hi, float(d.get('debris_per100', 0.0)) / float(d['decor_per100']) / ref))


def debris_groups(groups):
    """the kit groups whose name says debris (DEBRIS_WORDS, the learner's debris subset)"""
    return {g for g, gd in groups.items() if _words(g + ' ' + gd.get('name', ''), DEBRIS_WORDS)}


def path_width(prof):
    """O745: the width of a plan path that names none: the most common corridor width of 2-6 tiles in the profile
    (a tie goes to the width nearest 3); 3 (the planner's default) when it has none"""
    h = prof.get('corridor_width') or {}
    best = max((float(h.get(str(w), 0.0)), -abs(w - 3), -w, w) for w in PATH_WIDTHS)
    return best[3] if best[0] > 0 else 3


def apply_dresser(dresser, prof):
    """switch a Dresser to the profile: kit, density, clusters, lights and debris (area_plan_decor.Dresser(style=...))"""
    dresser.style = prof
    base = dresser.kit
    dresser.kit = styled_kit(prof, dresser.kit)
    dresser.dm = dresser.dm * density_factor(prof)
    per100 = float(prof['clusters'].get('per100_3plus', 0.0))
    dresser.style_rates = {'clusters_per100': per100 / max(0.4, dresser.dm)}
    dresser.style_sizes = cluster_sizes(prof)
    # O745: lights by the profile's light density; debris weight in the categories that kept the biome's rows (the
    # categories drawn from the profile carry its debris share already)
    dresser.style_light = light_factor(prof, dresser.kind)
    dresser.lm = dresser.lm * dresser.style_light
    dresser.style_debris = debris_factor(prof, dresser.kind)
    deb = debris_groups(dresser.groups)
    kept = sorted(c for c, rows in base.items() if isinstance(rows, list) and dresser.kit.get(c) == rows)
    dresser.style_debris_cats = []
    for c in kept:
        rows = dresser.kit[c]
        if any(isinstance(r, list) and r and r[0] in deb for r in rows):
            dresser.kit[c] = [[r[0], max(1, int(round(r[1] * dresser.style_debris)))] if isinstance(r, list) and r and r[0] in deb
                              else r for r in rows]
            dresser.style_debris_cats.append(c)


def manifest_entry(key, prof, job, dresser):
    return dict(key=key, source=prof.get('source', {}).get('name'), generator=job or {},
                density_factor=round(density_factor(prof), 4), kit_groups=sorted({g for c, rows in (dresser.kit or {}).items()
                                                                                  if isinstance(rows, list) for g, _w in rows}),
                light_factor=round(getattr(dresser, 'style_light', 1.0), 4),
                debris_factor=round(getattr(dresser, 'style_debris', 1.0), 4),
                debris_categories=list(getattr(dresser, 'style_debris_cats', [])), path_width=path_width(prof))


# ================================================================================================= copy guard
def windows(stacks, n=8, min_items=4):
    """{window content: first corner} of every n x n window of a {(x, y, z): (ground, item, ...)} map whose tiles
    carry min_items or more items above the ground (a window with nothing placed carries no layout); a missing tile
    is None"""
    out = {}
    by_floor = {}
    for (x, y, z) in stacks:
        by_floor.setdefault(z, []).append((x, y))
    for z, cells in by_floor.items():
        xs = [c[0] for c in cells]
        ys = [c[1] for c in cells]
        for y0 in range(min(ys), max(ys) - n + 2):
            for x0 in range(min(xs), max(xs) - n + 2):
                win = tuple(tuple(stacks[c]) if c in stacks else None
                            for c in ((x0 + dx, y0 + dy, z) for dy in range(n) for dx in range(n)))
                if sum(len(s) - 1 for s in win if s) < min_items:
                    continue
                out.setdefault(win, (x0, y0, z))
    return out


def window_matches(ref, out, n=8, min_items=4):
    """[(corner in ref, corner in out)] of the n x n windows of out that equal a window of ref, items by tile"""
    a = windows(ref, n, min_items)
    b = windows(out, n, min_items)
    return [(a[w], b[w]) for w in b if w in a]

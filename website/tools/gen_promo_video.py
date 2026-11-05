#!/usr/bin/env python3
"""Promo videos built from the game's own world: trailer 16:9 and 9:16, the class short and the world short (docs/PROMO.md
sections 1, 3 and 4; website/README.md "Promo kit").

There is no recorded gameplay yet, so the picture is real scenes drawn from the installed map with the game's own sprites:
the Cinderhold temple, dense hunts of different levels, an underground floor, a boss lair with a party of the seven classes
and a player clash. Nothing is invented but the camera: no spell effects, no animation (creatures stand in their idle
frame), the pan, the grade, the embers and the rain are added here. Captions use the poster font (gen_site_art.py), the music
is the game's own (client/overlay/modules/game_chaosmusic/music/, own work). Cuts fall on the beat of the track.

    python3 -I website/tools/gen_promo_video.py --server SERVER_DIR --pair PAIR_DIR --out OUT_DIR
        [--cache DIR] [--scenes FILE.json] [--only TEXT] [--stills DIR] [--jobs N] [--list-scenes]

  --server   an installed server folder (data/world/*.otbm and -spawn.xml, data/items/items.otb and items.xml,
             data/monster/); read only
  --pair     the folder with Tibia.dat and Tibia.spr; read only
  --out      the videos: trailer-1920x1080.pt-BR.mp4 and .en.mp4, trailer-1080x1920.pt-BR.mp4,
             short-classes-1080x1920.pt-BR.mp4 and .en.mp4, short-world-1080x1920.pt-BR.mp4 (H.264, AAC, faststart)
  --cache    scene pictures (default OUT_DIR/_cache). The map is read (about a minute) only when a scene is missing there.
  --scenes   JSON that overrides scene fields by name, e.g. {"town": {"x": 32369, "y": 32241, "z": 7}}; --list-scenes prints
             the chosen scenes (scenes.json in the cache has the full specs to copy from)
  --only     render only the videos whose file name contains TEXT
  --stills   also save 7 PNG frames of the pt-BR trailer to this folder

Scene choice is automatic and deterministic (choose_scenes): the main town from the map's town list, hunts at four health
bands (the densest windows of the spawn file), one underground hunt, the boss of bossspawns_config.lua with the most health,
seven class scenes, a clash ground. The class looks come from class_looks_core.lua (default look of each class with its start
colours). Player names are made up. Needs numpy, Pillow and ffmpeg. Test: gen_promo_video_test.py (synthetic data only).
"""
import argparse
import concurrent.futures as cf
import html
import json
import math
import os
import re
import subprocess
import sys
import zlib
from collections import Counter

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)

FPS = 30
TILE = 32
SCALE = 3                     # source pixel -> output pixels; 20 x 11.25 tiles fill 1920 x 1080
AREA_W, AREA_H = 60, 34       # tiles drawn once per scene
VERSION = 3                   # bumps the scene cache when the drawing changes
MUSIC_DIR = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosmusic', 'music')
CLASS_LOOKS_LUA = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'class_looks_core.lua')
BOSS_LUA = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bossspawns_config.lua')
CARDS = os.path.join(REPO, 'website', 'overlay', 'plugins', 'chaos', 'assets', 'promo', 'classes')
SOURCE = os.path.join(HERE, 'promo_source.json')

LANGS = ('pt-BR', 'en')
CLASS_ORDER = ('warrior', 'ranger', 'mystic', 'thief', 'monk', 'necromancer', 'templar')
CLASS_VOC = {'warrior': 4, 'ranger': 3, 'mystic': 1, 'thief': 11, 'monk': 17, 'necromancer': 20, 'templar': 23}
# made-up names, no real players
CLASS_CHAR = {'warrior': 'Ashen Warden', 'ranger': 'Ember Wren', 'mystic': 'Gloam Weaver', 'thief': 'Vesper Knife',
              'monk': 'Hollow Fist', 'necromancer': 'Grave Sallow', 'templar': 'Dawn Vigil'}
RIVAL_NAMES = ('Iron Maren', 'Cold Tarn', 'Rook Sundered', 'Mire Hollis')

TEXT = {
    'pt-BR': {
        'world': 'O mundo não acabou. Ele quebrou.', 'classes': '7 classes. 14 ascensões.', 'build': 'Monte sua build.',
        'loot': 'Loot que importa.', 'rift': 'Rifts. Torre Infinita.', 'raid': 'Raids e chefes de mundo.',
        'pvp': 'PvP quando quiser.', 'free': 'Grátis. PC e Android.', 'choose': 'Escolha sua classe',
        'hunts': 'Caçadas sem fim.', 'bosses': 'Chefes que não perdoam.',
    },
    'en': {
        'world': 'The world did not end. It broke.', 'classes': '7 classes. 14 ascensions.', 'build': 'Make your build.',
        'loot': 'Loot that matters.', 'rift': 'Rifts. Infinity Tower.', 'raid': 'Raids and world bosses.',
        'pvp': 'PvP when you want it.', 'free': 'Free. PC and Android.', 'choose': 'Choose your class',
        'hunts': 'Endless hunts.', 'bosses': 'Bosses show no mercy.',
    },
}

# grade: (r, g, b) multiplier, vignette strength
GRADES = {
    'dusk': ((1.00, 0.78, 0.66), 0.62), 'cave': ((0.80, 0.78, 0.96), 0.66), 'hunt': ((1.00, 0.90, 0.80), 0.55),
    'boss': ((1.05, 0.76, 0.70), 0.66), 'clash': ((1.00, 0.84, 0.72), 0.58),
}


# ------------------------------------------------------------------------------------------------ small maths
def clamp01(v):
    return 0.0 if v < 0 else 1.0 if v > 1 else v


def ramp(t, a, b):
    """0 before a, 1 after b, linear between"""
    return clamp01((t - a) / (b - a)) if b > a else (1.0 if t >= b else 0.0)


def snap(t, grid):
    return round(t / grid) * grid if grid > 0 else t


def build_timeline(parts, total, grid):
    """parts: [(seconds, payload)]. Returns [(t0, t1, payload)] contiguous from 0 to total. Inner boundaries sit on the beat
    grid and every part keeps at least one grid step; the last part ends at total."""
    scale = total / sum(p[0] for p in parts)
    if grid * len(parts) > total:
        raise ValueError('%d parts do not fit %.1f s at a %.2f s grid' % (len(parts), total, grid))
    bounds, acc = [0.0], 0.0
    for i, (sec, _) in enumerate(parts[:-1]):
        acc += sec * scale
        b = max(snap(acc, grid), bounds[-1] + grid)
        bounds.append(min(b, total - grid * (len(parts) - 1 - i)))
    bounds.append(total)
    return [(round(bounds[i], 6), round(bounds[i + 1], 6), parts[i][1]) for i in range(len(parts))]


def pan_path(a, b, n, ease=0.5):
    """n integer camera centres (pixels) from a to b, a mix of linear and smoothstep (ease 0 linear, 1 smoothstep);
    the first is a, the last is b"""
    out = []
    for i in range(n):
        u = i / (n - 1) if n > 1 else 1.0
        s = (1 - ease) * u + ease * (u * u * (3 - 2 * u))
        out.append((int(round(a[0] + (b[0] - a[0]) * s)), int(round(a[1] + (b[1] - a[1]) * s))))
    return out


def estimate_bpm(x, sr, lo=70.0, hi=175.0):
    """(bpm, offset seconds of the first beat) of a mono signal: onset envelope at 100 Hz, autocorrelation for the period,
    a comb over the onsets for the phase"""
    x = np.asarray(x, np.float64)
    hop = max(1, int(sr // 100))
    n = len(x) // hop
    if n < 400:
        return 120.0, 0.0
    e = np.sqrt((x[:n * hop].reshape(n, hop) ** 2).mean(axis=1)) + 1e-6
    on = np.maximum(0, np.diff(np.log(e), prepend=np.log(e[0])))
    on -= on.mean()
    f = np.fft.rfft(on, 2 * n)
    ac = np.fft.irfft(f * np.conj(f))[:n]
    rate = sr / hop
    best, bscore = 120.0, -1e18
    for bpm in np.arange(lo, hi, 0.25):
        lag = 60.0 / bpm * rate
        i = int(lag)
        if i + 1 >= n // 2:
            continue
        v = ac[i] * (1 - (lag - i)) + ac[i + 1] * (lag - i)
        v += 0.5 * (ac[int(2 * lag)] if int(2 * lag) < n else 0)
        if v > bscore:
            best, bscore = float(bpm), v

    def comb(bpm):
        p = 60.0 / bpm * rate
        ks = np.arange(0, int(n / p) - 1)
        scores = []
        for ph in np.arange(0, p, 1.0):
            idx = np.round(ph + ks * p).astype(int)
            idx = idx[idx < n]
            scores.append(on[idx].sum())
        j = int(np.argmax(scores))
        return scores[j], j / rate
    cand = [(comb(b)[0], b) for b in np.arange(best - 2.0, best + 2.01, 0.25) if lo <= b <= hi]
    sc, bpm = max(cand)
    return float(bpm), float(comb(bpm)[1])


# ------------------------------------------------------------------------------------------------ repository data
def read_class_looks(path=CLASS_LOOKS_LUA):
    """{class: {'look': male look type, 'female': look type, 'head','body','legs','feet'}} of the seven base classes:
    class_looks_core.lua L.looks, replaced by the pair 19 / 20 looks when their switches are on, with L.startColors"""
    with open(path, encoding='utf-8') as f:
        s = f.read()

    def block(a, b):
        i = s.index(a)
        return s[i:s.index(b, i)]
    row = re.compile(r'\[(\d+)\]\s*=\s*\{(?:name\s*=\s*"[^"]*",\s*)?male\s*=\s*(\d+),\s*female\s*=\s*(\d+)\}')
    looks = {int(v): (int(m), int(fm)) for v, m, fm in row.findall(block('L.looks = {', 'L.PAIR19_LOOKS'))}
    for flag, a, b in (('PAIR19_LOOKS', 'L.pair19Looks = {', 'L.PAIR20_LOOKS'), ('PAIR20_LOOKS', 'L.pair20Looks = {', 'L.retired')):
        m = re.search(r'L\.%s\s*=\s*(true|false)' % flag, s)
        if m and m.group(1) == 'true':
            for v, ml, fm in row.findall(block(a, b)):
                looks[int(v)] = (int(ml), int(fm))
    col = re.compile(r'\[(\d+)\]\s*=\s*\{head\s*=\s*(\d+),\s*body\s*=\s*(\d+),\s*legs\s*=\s*(\d+),\s*feet\s*=\s*(\d+)\}')
    cols = {int(v): tuple(int(x) for x in rest) for v, *rest in col.findall(block('L.startColors = {', 'L.OLD_COLORS'))}
    out = {}
    for name, voc in CLASS_VOC.items():
        h, b, l, f_ = cols[voc]
        out[name] = dict(look=looks[voc][0], female=looks[voc][1], head=h, body=b, legs=l, feet=f_)
    return out


def read_lair_bosses(path=BOSS_LUA):
    """[(monster name, (x, y, z))] of the lair bosses (map spawns) of bossspawns_config.lua"""
    with open(path, encoding='utf-8') as f:
        s = f.read()
    out = []
    for m in re.finditer(r'category\s*=\s*"lair"[^\n]*?monster\s*=\s*"([^"]+)"[^\n]*\n?[^\n]*?pos\s*=\s*\{x\s*=\s*(\d+),\s*y\s*=\s*(\d+),\s*z\s*=\s*(\d+)\}', s):
        out.append((m.group(1), (int(m.group(2)), int(m.group(3)), int(m.group(4)))))
    return out


SPAWN_RE = re.compile(r'<spawn\s+centerx="(\d+)"\s+centery="(\d+)"\s+centerz="(\d+)"[^>]*>(.*?)</spawn>', re.S)
MON_RE = re.compile(r'<monster\s+name="([^"]+)"\s+x="(-?\d+)"\s+y="(-?\d+)"(?:\s+z="(-?\d+)")?')


def parse_spawns(text):
    """[(x, y, z, name)] of every monster of a spawn file (absolute tile)"""
    out = []
    for m in SPAWN_RE.finditer(text):
        cx, cy, cz = int(m.group(1)), int(m.group(2)), int(m.group(3))
        for mm in MON_RE.finditer(m.group(4)):
            z = int(mm.group(4)) if mm.group(4) is not None else cz
            out.append((cx + int(mm.group(2)), cy + int(mm.group(3)), z, html.unescape(mm.group(1))))
    return out


def _attrs(tag):
    return {k: html.unescape(v) for k, v in re.findall(r'([\w-]+)="([^"]*)"', tag)}


def parse_monster_xml(text):
    """{'name', 'health', 'exp', 'look': {...}} of one monster file, or None without a name or a look"""
    m = re.search(r'<monster\b([^>]*)>', text)
    h = re.search(r'<health\b([^>]*)/?>', text)
    lk = re.search(r'<look\b([^>]*)/?>', text)
    if not (m and lk):
        return None
    a, la = _attrs(m.group(1)), _attrs(lk.group(1))
    if 'name' not in a:
        return None
    look = {k: int(la.get(k, 0) or 0) for k in ('type', 'typeex', 'head', 'body', 'legs', 'feet', 'addons')}
    if not look['type'] and not look['typeex']:
        return None
    ha = _attrs(h.group(1)) if h else {}
    return dict(name=a['name'], exp=int(a.get('experience', 0) or 0), health=int(ha.get('max', ha.get('now', 1)) or 1), look=look)


def read_monsters(mon_dir):
    """{lower name: info} of data/monster: names from monsters.xml (name -> file), looks and health from each file"""
    idx = open(os.path.join(mon_dir, 'monsters.xml'), encoding='utf-8', errors='replace').read()
    info = {}
    for tag in re.findall(r'<monster\b[^>]*/>', idx):
        a = _attrs(tag)
        if 'name' not in a or 'file' not in a:
            continue
        p = os.path.join(mon_dir, a['file'])
        if not os.path.isfile(p):
            continue
        d = parse_monster_xml(open(p, encoding='utf-8', errors='replace').read())
        if d:
            info[a['name'].lower()] = d
            info.setdefault(d['name'].lower(), d)
    return info


# ------------------------------------------------------------------------------------------------ scene choice
def dense_windows(mons, health, cell=(10, 6)):
    """windows of 3 x 3 cells (30 x 18 tiles) around every occupied cell of the monsters [(x, y, z, name)]: count, distinct
    names, median log health (health(name) -> number or None to skip a name), centre, spread, commonest name"""
    cells = {}
    for x, y, z, n in mons:
        h = health(n)
        if h is None:
            continue
        cells.setdefault((z, x // cell[0], y // cell[1]), []).append((x, y, n, math.log(max(1, h))))
    out = []
    for (z, cx, cy), _ in cells.items():
        mem = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                mem += cells.get((z, cx + dx, cy + dy), [])
        xs = sorted(m[0] for m in mem)
        ys = sorted(m[1] for m in mem)
        names = Counter(m[2] for m in mem)
        hs = sorted(m[3] for m in mem)
        out.append(dict(x=xs[len(xs) // 2], y=ys[len(ys) // 2], z=z, count=len(mem), distinct=len(names),
                        health=hs[len(hs) // 2], sx=float(np.std(xs)), sy=float(np.std(ys)),
                        top=sorted(names.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]))
    for w in out:
        w['score'] = w['count'] + 3 * w['distinct']
    out.sort(key=lambda w: (-w['score'], w['z'], w['x'], w['y']))
    return out


def _far(w, taken, d):
    return all(abs(w['z'] - t['z']) > 1 or max(abs(w['x'] - t['x']), abs(w['y'] - t['y'])) >= d for t in taken)


def choose_scenes(windows, towns, bosses, mon_health, main='Cinderhold', quality=None):
    """The scene specs, deterministic for the same inputs (the order of windows and towns does not matter).
    towns [(id, name, (x, y, z))]; bosses [(monster name, (x, y, z))]; mon_health(name) -> health or None;
    quality(kind, x, y, z) -> bool tells open ground worth filming from a void or a display row (kind 'hunt' or 'boss').
    Returns {name: spec}: town, hunt1..hunt4 (health bands, lowest first), dungeon, boss, clash, class_<class> x 7."""
    wins = sorted(windows, key=lambda w: (-w['score'], w['z'], w['x'], w['y']))
    towns = sorted(towns)
    tn = next((t for t in towns if t[1] == main), towns[0])
    tx, ty, tz = tn[2]
    out = {'town': dict(kind='town', x=tx, y=ty, z=tz, pan=[16, 0], grade='dusk', rain=True, label=tn[1])}
    pool = [w for w in wins if not (w['z'] == tz and max(abs(w['x'] - tx), abs(w['y'] - ty)) < 60)
            and not any(w['z'] == t[2][2] and max(abs(w['x'] - t[2][0]), abs(w['y'] - t[2][1])) < 40 for t in towns)]
    if not pool:
        raise ValueError('no hunt window')
    counts = sorted((w['count'] for w in pool), reverse=True)
    thr = counts[min(len(counts) - 1, max(150, len(counts) // 20) - 1)]
    pool = [w for w in pool if w['count'] >= thr] or pool
    memo = {}

    def ok(w):
        k = (w['x'], w['y'], w['z'])
        if k not in memo:
            memo[k] = quality is None or bool(quality('hunt', *k))
        return memo[k]
    hs = sorted(w['health'] for w in pool)
    cuts = [hs[(len(hs) * k) // 4] for k in (1, 2, 3)]
    band = lambda w: sum(w['health'] >= c for c in cuts)  # noqa: E731
    taken, tops = [], set()

    def add(name, w, **kw):
        sx, sy = w.get('sx', 1), w.get('sy', 0)
        spec = dict(kind='hunt', x=w['x'], y=w['y'], z=w['z'], pan=[14, 0] if sx >= sy else [0, 8], grade='hunt', rain=False,
                    top=w['top'], count=w['count'])
        spec.update(kw)
        out[name] = spec
        taken.append(w)
        tops.add(w['top'])

    for b in range(4):
        pick = next((w for w in pool if band(w) == b and w['top'] not in tops and _far(w, taken, 60) and ok(w)), None) \
            or next((w for w in pool if band(w) == b and _far(w, taken, 60) and ok(w)), None) \
            or next((w for w in pool if _far(w, taken, 60) and ok(w)), None)
        if pick:
            add('hunt%d' % (b + 1), pick)
    deep = next((w for w in pool if w['z'] >= 9 and _far(w, taken, 60) and ok(w)), None) \
        or next((w for w in pool if w['z'] > 7 and _far(w, taken, 60) and ok(w)), None) \
        or next((w for w in pool if _far(w, taken, 60) and ok(w)), None)
    if deep:
        add('dungeon', deep, grade='cave')
    i = 0
    for cl in CLASS_ORDER:
        pick = next((w for w in pool if band(w) >= 1 and _far(w, taken, 45) and ok(w)), None) \
            or next((w for w in pool if _far(w, taken, 45) and ok(w)), None)
        if not pick:
            pick = pool[i % len(pool)]
            i += 1
        add('class_' + cl, pick, kind='class', pan=[4, 0], cls=cl)
    # boss: the lair boss with the most health that has a look
    cands = sorted(((mon_health(n), n, p) for n, p in bosses if mon_health(n) is not None), key=lambda v: (-v[0], v[1]))
    cands = [c for c in cands if quality is None or quality('boss', c[2][0], c[2][1], c[2][2])]
    if cands:
        _, bn, bp = cands[0]
        out['boss'] = dict(kind='boss', x=bp[0], y=bp[1] + 4, z=bp[2], pan=[6, 0], grade='boss', rain=False, monster=bn,
                           boss_pos=list(bp))
    # clash ground: the second health band hunt, monsters cleared
    src = out.get('hunt2') or out.get('hunt1')
    out['clash'] = dict(kind='clash', x=src['x'], y=src['y'], z=src['z'], pan=[4, 0], grade='clash', rain=False, clear=14)
    return out


def apply_overrides(scenes, over):
    """--scenes FILE: dict name -> fields; a new name needs kind, x, y, z"""
    for name, fields in over.items():
        if name in scenes:
            scenes[name].update(fields)
        elif all(k in fields for k in ('kind', 'x', 'y', 'z')):
            scenes[name] = dict(fields)
    return scenes


def nearest_free(walk, occupied, tx, ty, maxr=10):
    """the free walkable tile (x, y) of the bool grid walk[y][x] closest to (tx, ty), rings outwards; None when none"""
    h, w = walk.shape
    for r in range(maxr + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                x, y = tx + dx, ty + dy
                if 0 <= x < w and 0 <= y < h and walk[y][x] and (x, y) not in occupied:
                    return x, y
    return None


def players_for(spec):
    """[(class, name, dx, dy, direction)] to place in a scene, offsets in tiles from its centre; direction 0 N, 1 E, 2 S, 3 W"""
    k = spec['kind']
    if k == 'class':
        return [(spec['cls'], CLASS_CHAR[spec['cls']], 0, 0, 1)]
    if k == 'town':
        return [('warrior', CLASS_CHAR['warrior'], -3, 2, 1), ('mystic', CLASS_CHAR['mystic'], 4, 3, 2),
                ('ranger', CLASS_CHAR['ranger'], 9, -1, 3), ('templar', CLASS_CHAR['templar'], -8, -2, 0)]
    if k == 'boss':
        xs = [-6, -4, -2, 0, 2, 4, 6]
        return [(c, CLASS_CHAR[c], xs[i], 1 + (i % 2), 0) for i, c in enumerate(CLASS_ORDER)]
    if k == 'clash':
        a = [('warrior', CLASS_CHAR['warrior']), ('mystic', CLASS_CHAR['mystic']), ('ranger', CLASS_CHAR['ranger']),
             ('templar', CLASS_CHAR['templar'])]
        b = [('thief', CLASS_CHAR['thief']), ('monk', CLASS_CHAR['monk']), ('necromancer', CLASS_CHAR['necromancer']),
             ('warrior', RIVAL_NAMES[0])]
        ys = [-3, -1, 1, 3]
        return [(c, n, -4 - (i % 2), ys[i], 1) for i, (c, n) in enumerate(a)] + \
               [(c, n, 4 + (i % 2), ys[i], 3) for i, (c, n) in enumerate(b)]
    return []


def scene_key(spec):
    blob = json.dumps(spec, sort_keys=True) + str(VERSION) + str(AREA_W) + str(AREA_H)
    return '%08x' % (zlib.crc32(blob.encode()) & 0xffffffff)


# ------------------------------------------------------------------------------------------------ the world (needs the map)
class World:
    """the installed map, items and sprites: draws a scene with spectate_render"""

    def __init__(self, server, pair, cache):
        sys.path[:0] = [os.path.join(REPO, 'server', 'tools'), os.path.join(REPO, 'tools', 'map'),
                        os.path.join(REPO, 'client', 'tools', 'sprites')]
        import otbm
        import itemdb
        import datspr
        import spectate_render as sr
        self.sr = sr
        dat, spr = os.path.join(pair, 'Tibia.dat'), os.path.join(pair, 'Tibia.spr')
        data = os.path.join(server, 'data')
        wdir = os.path.join(data, 'world')
        otb = next(f for f in sorted(os.listdir(wdir)) if f.endswith('.otbm'))
        print('reading the map', otb, '...', flush=True)
        self.m = otbm.load_map(os.path.join(wdir, otb))
        self.db = itemdb.ItemDB(os.path.join(data, 'items', 'items.otb'), os.path.join(data, 'items', 'items.xml'), dat)
        self.items, self.outfits = sr.load_index(dat, cache)
        self.spr = datspr.Spr(spr)
        self.looks = read_class_looks()

    def tile_data(self, x0, y0, w, h, z):
        m, db = self.m, self.db
        tiles = [[] for _ in range(w * h)]
        walk = np.zeros((h, w), bool)
        idx = m.rect(x0, y0, x0 + w - 1, y0 + h - 1, z)
        xs, ys = m.tiles['x'], m.tiles['y']
        for i in idx:
            tx, ty = int(xs[i]) - x0, int(ys[i]) - y0
            sids = m.stack(i)
            cids = [int(db.cid[s]) for s in sids if db.cid[s]]
            tiles[ty * w + tx] = cids
            ground = blocked = False
            for s in sids:
                ground |= bool(db.dground[s])
                blocked |= bool(db.flags[s] & 1) or bool(db.dblock[s])
            walk[ty, tx] = ground and not blocked
        return tiles, walk

    def window_stats(self, x, y, z, w=30, h=18):
        """(walkable share, empty share, distinct item ids) of the w x h tiles around (x, y): a hunt worth filming is open
        ground with something to look at, not a black void or a row of display alcoves"""
        tiles, walk = self.tile_data(x - w // 2, y - h // 2, w, h, z)
        empty = sum(1 for t in tiles if not t) / float(w * h)
        ids = {c for t in tiles for c in t}
        return float(walk.mean()), empty, len(ids)

    def quality(self, kind, x, y, z):
        walk, empty, _ = self.window_stats(x, y, z)
        return (walk >= 0.30 and empty <= 0.40) if kind == 'boss' else (walk >= 0.50 and empty <= 0.30)

    def best_town_window(self, x, y, z, radius=36, step=4, w=24, h=14):
        """the centre near the temple whose view has the most to look at: open streets (walkable, not void), many different items"""
        best, bc = -1.0, (x, y)
        for dy in range(-radius, radius + 1, step):
            for dx in range(-radius, radius + 1, step):
                walk, empty, ids = self.window_stats(x + dx, y + dy, z, w, h)
                if walk < 0.45 or empty > 0.05:
                    continue
                score = ids + 40 * walk - 0.5 * max(abs(dx), abs(dy))
                if score > best:
                    best, bc = score, (x + dx, y + dy)
        return bc

    def draw(self, snap):
        sr = self.sr
        sr.VIEW_W, sr.VIEW_H = snap['w'], snap['h']
        got, orig = [], sr.draw_infos
        sr.draw_infos = lambda img, infos: got.extend(infos)
        try:
            img = sr.render(snap, self.items, self.outfits, self.spr)
        finally:
            sr.draw_infos = orig
        return np.asarray(img.convert('RGB')), got


class SpawnIndex:
    def __init__(self, mons):
        self.x = np.array([m[0] for m in mons], np.int32)
        self.y = np.array([m[1] for m in mons], np.int32)
        self.z = np.array([m[2] for m in mons], np.int16)
        self.n = [m[3] for m in mons]

    def rect(self, x0, y0, x1, y1, z):
        sel = np.flatnonzero((self.z == z) & (self.x >= x0) & (self.x <= x1) & (self.y >= y0) & (self.y <= y1))
        return [(int(self.x[i]), int(self.y[i]), self.n[i]) for i in sel]


def creature_outfit(info):
    lk = info['look']
    if lk['type']:
        return dict(t=lk['type'], h=lk['head'], b=lk['body'], l=lk['legs'], f=lk['feet'], a=lk['addons'])
    return dict(t=0, x=lk['typeex'])


def build_scene(world, spec, spawns, mon_info, name):
    """renders one scene: (RGB array of AREA_W x AREA_H tiles, [info dict per creature])"""
    rng = np.random.RandomState(zlib.crc32(name.encode()) & 0x7fffffff)
    w, h = AREA_W, AREA_H
    cx, cy, z = spec['x'], spec['y'], spec['z']
    x0, y0 = cx - w // 2, cy - h // 2
    tiles, walk = world.tile_data(x0, y0, w, h, z)
    creatures, occupied = [], set()
    clear = spec.get('clear')
    for mx, my, n in spawns.rect(x0, y0, x0 + w - 1, y0 + h - 1, z):
        info = mon_info.get(n.lower())
        tx, ty = mx - x0, my - y0
        if not info or not walk[ty][tx] or (tx, ty) in occupied:
            continue
        if clear and max(abs(mx - cx), abs(my - cy)) <= clear:
            continue
        hp = 100 if rng.rand() < 0.45 else int(rng.uniform(25, 96))
        creatures.append(dict(x=mx, y=my, o=creature_outfit(info), d=int(rng.randint(0, 4)), name=info['name'], hp=hp, kind='monster'))
        occupied.add((tx, ty))
    if spec['kind'] == 'boss':
        bn = spec['monster']
        bx, by, bz = spec['boss_pos']
        if not any(c['name'].lower() == bn.lower() for c in creatures):
            free = nearest_free(walk, occupied, bx - x0, by - y0, 4)
            if free:
                creatures.append(dict(x=free[0] + x0, y=free[1] + y0, o=creature_outfit(mon_info[bn.lower()]), d=2,
                                      name=mon_info[bn.lower()]['name'], hp=100, kind='monster'))
                occupied.add(free)
    for cl, pname, dx, dy, d in players_for(spec):
        free = nearest_free(walk, occupied, cx + dx - x0, cy + dy - y0, 8)
        if not free:
            continue
        lk = world.looks[cl]
        creatures.append(dict(x=free[0] + x0, y=free[1] + y0, d=d, name=pname, hp=100, kind='player',
                              o=dict(t=lk['look'], h=lk['head'], b=lk['body'], l=lk['legs'], f=lk['feet'], a=3)))
        occupied.add(free)
    snap = dict(w=w, h=h, x0=x0, y0=y0, pos=dict(x=cx, y=cy, z=z), tiles=tiles, creatures=creatures)
    img, infos = world.draw(snap)
    out = [dict(cx=int(i[0]), ty=int(i[1]), name=i[2].get('name', ''), hp=int(i[2].get('hp', 0)), kind=i[2].get('kind', 'monster'))
           for i in infos]
    return img, out


# ------------------------------------------------------------------------------------------------ pictures and effects
_ART = {}


def art():
    if 'gsa' not in _ART:
        import gen_streamer_kit as gsk
        import gen_promo_kit as gpk
        _ART.update(gsk=gsk, gsa=gsk.load_art(), gpk=gpk)
        with open(SOURCE, encoding='utf-8') as f:
            _ART['src'] = json.load(f)
    return _ART


def blit_rgba(dst, src, x, y, alpha=1.0):
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x0 >= x1 or y0 >= y1 or alpha <= 0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:4].astype(np.float32) * (alpha / 255.0)
    d = dst[y0:y1, x0:x1]
    d[...] = (d * (1.0 - a) + s[..., :3] * a + 0.5).astype(np.uint8)


def caption_image(text, size, maxw, glow=0.5):
    """the caption in the poster font (gold, ember glow) as an RGBA array on a transparent canvas"""
    gsa = art()['gsa']
    fnt = gsa.fit(size, 'display', text, maxw)
    d = ImageDraw.Draw(Image.new('L', (1, 1)))
    tw = int(d.textlength(text, font=fnt)) + 2 * 60
    th = int(fnt.size * 1.9)
    img = Image.new('RGBA', (tw, th), (0, 0, 0, 0))
    gsa.gold_text(img, (tw // 2, th // 2), text, fnt, anchor='mm', glow=glow, spacing=3)
    return np.asarray(img)


def small_text(text, size, kind='heading', fill=(214, 201, 174), pad=20):
    gsa = art()['gsa']
    fnt = gsa.font(size, kind)
    d = ImageDraw.Draw(Image.new('L', (1, 1)))
    tw, th = int(d.textlength(text, font=fnt)) + 2 * pad, int(size * 1.7)
    img = Image.new('RGBA', (tw, th), (0, 0, 0, 0))
    gsa.plain_text(img, (tw // 2, th // 2), text, fnt, fill=fill, anchor='mm')
    return np.asarray(img)


def health_rgb(pct):
    if pct > 92:
        return (0x00, 0xBC, 0x00)
    if pct > 60:
        return (0x50, 0xA1, 0x50)
    if pct > 30:
        return (0xA1, 0xA1, 0x00)
    if pct > 8:
        return (0xBF, 0x0A, 0x0A)
    return (0x91, 0x0F, 0x0F)


def name_sprite(name, hp, size=19):
    """name over a health bar at output scale (RGBA array); the anchor is the bar's top-centre"""
    gsa = art()['gsa']
    fnt = gsa.font(size, 'heading')
    col = health_rgb(hp)
    d = ImageDraw.Draw(Image.new('L', (1, 1)))
    tw = int(d.textlength(name, font=fnt))
    bw, bh = 28 * SCALE, 4 * SCALE
    W = max(tw, bw) + 8
    H = size + 8 + bh + 4
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    tx = (W - tw) // 2
    for ox, oy in ((-2, 0), (2, 0), (0, -2), (0, 2), (-2, -2), (2, 2), (-2, 2), (2, -2), (0, 3)):
        dr.text((tx + ox, 2 + oy), name, font=fnt, fill=(0, 0, 0, 255))
    dr.text((tx, 2), name, font=fnt, fill=col + (255,))
    bx, by = (W - bw) // 2, size + 8
    dr.rectangle((bx, by, bx + bw - 1, by + bh - 1), fill=(0, 0, 0, 255))
    fill = int(round((28 - 2) * SCALE * hp / 100))
    if fill > 0:
        dr.rectangle((bx + SCALE, by + SCALE, bx + SCALE + fill - 1, by + bh - SCALE - 1), fill=col + (255,))
    return np.asarray(img), (W // 2, by)


class Embers:
    """rising ember squares, deterministic from the seed; draw() max-blends them on an RGB frame"""

    def __init__(self, w, h, n, seed, speed=1.0, size=1.0):
        r = np.random.RandomState(seed)
        self.w, self.h, self.n = w, h, n
        self.x0 = r.uniform(0, w, n)
        self.y0 = r.uniform(0, h + 80, n)
        self.v = r.uniform(40, 160, n) * speed * h / 1080
        self.amp = r.uniform(8, 40, n)
        self.fr = r.uniform(0.4, 1.6, n)
        self.ph = r.uniform(0, 6.28, n)
        self.s = np.where(r.rand(n) < 0.7, 3, 6) * size * h / 1080
        self.hot = r.rand(n)

    def draw(self, frame, t, strength=1.0):
        H, W = frame.shape[:2]
        for i in range(self.n):
            y = (self.y0[i] - self.v[i] * t) % (self.h + 80) - 40
            x = (self.x0[i] + self.amp[i] * math.sin(self.fr[i] * t + self.ph[i])) % self.w
            a = (0.55 + 0.45 * math.sin(t * 5.0 + self.ph[i] * 3)) * strength * clamp01(1.2 - (y / self.h) * 0.9)
            if a <= 0.02:
                continue
            s = max(2, int(round(self.s[i])))
            col = np.array((255, 120 + 100 * self.hot[i], 30 + 70 * self.hot[i]), np.float32) * a
            xi, yi = int(x), int(y)
            for k, f in ((2 * s, 0.22), (s, 1.0)):
                ox, oy = xi - (k - s) // 2, yi - (k - s) // 2
                x0, y0, x1, y1 = max(0, ox), max(0, oy), min(W, ox + k), min(H, oy + k)
                if x0 < x1 and y0 < y1:
                    reg = frame[y0:y1, x0:x1]
                    np.maximum(reg, (col * f).astype(np.uint8), out=reg)


class Rain:
    """two layers of slanted streaks that scroll down; a max-blend over a frame"""

    def __init__(self, w, h, seed=5):
        r = np.random.RandomState(seed)
        self.h = h
        self.layers = []
        for n, ln, wid, spd, br in ((260, 34, 2, 1500, 0.55), (180, 60, 3, 2300, 0.40)):
            im = Image.new('L', (w, h), 0)
            d = ImageDraw.Draw(im)
            for _ in range(int(n * w * h / (1920 * 1080))):
                x, y = r.uniform(0, w), r.uniform(0, h)
                for ox in (-w, 0, w):
                    for oy in (-h, 0, h):
                        d.line((x + ox, y + oy, x + ox - ln * 0.28, y + oy + ln), fill=int(255 * br), width=wid)
            a = np.asarray(im)
            self.layers.append((np.concatenate([a, a], axis=0), spd * h / 1080))

    def draw(self, frame, t, strength=1.0):
        H = self.h
        for tex, spd in self.layers:
            off = int(t * spd) % H
            win = tex[off:off + H]
            col = np.maximum(frame, (win[..., None] * np.array((0.62, 0.72, 0.86), np.float32) * strength).astype(np.uint8))
            frame[...] = col


def grade_mask(w, h, grade):
    tint, vig = GRADES[grade]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = (xs / w - 0.5) * 2, (ys / h - 0.5) * 2
    r = np.sqrt(nx * nx * 0.8 + ny * ny * 1.25)
    v = 1.0 - vig * np.clip((r - 0.35) / 0.95, 0, 1) ** 1.6
    return v[..., None] * np.array(tint, np.float32)[None, None, :]


class SceneAsset:
    def __init__(self, cache, name, key):
        base = os.path.join(cache, '%s-%s' % (name, key))
        self.img = np.asarray(Image.open(base + '.png').convert('RGB'))
        with open(base + '.json', encoding='utf-8') as f:
            self.infos = json.load(f)
        self.h, self.w = self.img.shape[:2]
        self._names = {}

    def crop(self, cx, cy, w, h):
        """the w x h window centred on (cx, cy), moved to stay inside the picture; (array, x, y of its corner)"""
        x = int(min(max(cx - w // 2, 0), max(0, self.w - w)))
        y = int(min(max(cy - h // 2, 0), max(0, self.h - h)))
        win = self.img[y:y + h, x:x + w]
        if win.shape[0] < h or win.shape[1] < w:
            pad = np.zeros((h, w, 3), np.uint8)
            pad[:win.shape[0], :win.shape[1]] = win
            win = pad
        return win, x, y

    def name_sprite(self, i):
        s = self._names.get(i)
        if s is None:
            inf = self.infos[i]
            s = name_sprite(inf['name'], inf['hp'])
            self._names[i] = s
        return s


# ------------------------------------------------------------------------------------------------ layouts
def layouts():
    return {
        'wide': dict(W=1920, H=1080, game=(0, 0, 1920, 1080), cap=(960, 925), cap_size=96, cap_w=1700, label=(960, 1005),
                     scrim=(700, 1080), logo_w=1100, end_logo=720, kind='wide'),
        'tall': dict(W=1080, H=1920, game=(0, 420, 1080, 1080), cap=(540, 1560), cap_size=84, cap_w=980, label=(540, 1700),
                     scrim=None, logo_w=900, end_logo=720, kind='tall', top_logo=560),
        'classes': dict(W=1080, H=1920, game=(0, 0, 1080, 960), cap=(540, 150), cap_size=76, cap_w=980, label=None,
                        scrim=(0, 330), logo_w=900, end_logo=720, kind='classes', card=(60, 960, 960)),
    }


def backdrop_rgb(W, H, seed=3):
    a = art()
    return np.asarray(a['gsk'].scene(a['gsa'], W, H, 0.5, 0.7, seed).convert('RGB'))


def end_card(lang, lay):
    """the end card as an RGB array: logo, BETA ABERTO, free line, site, class badges"""
    a = art()
    gsk, gsa, gpk, src = a['gsk'], a['gsa'], a['gpk'], a['src']
    W, H = lay['W'], lay['H']
    t = src['text'][lang]
    img = gsk.scene(gsa, W, H, 0.45, 0.55, 11)
    tall = H > W
    lg = gsk.wordmark(gsa, lay['end_logo'], tagline=False)
    top = int(H * (0.12 if tall else 0.06))
    img.alpha_composite(lg, ((W - lg.width) // 2, top))
    y = top + lg.height + int(H * (0.07 if tall else 0.05))
    gpk.headline(img, gsa, W // 2, y, t['beta'], 150 if not tall else 130, W - 160)
    y += int(H * (0.085 if tall else 0.13))
    sub = TEXT[lang]['free']
    gsa.plain_text(img, (W // 2, y), sub, gsa.fit(62 if not tall else 58, 'heading', sub, W - 160), fill=gsa.GOLD_3, anchor='mm')
    y += int(H * (0.05 if tall else 0.075))
    gsa.plain_text(img, (W // 2, y), a['src']['site'], gsa.font(54 if not tall else 50, 'heading'), fill=gsa.TEXT, anchor='mm')
    size = 120 if tall else 104
    gpk.badges_row(img, gsa, W // 2, H - size - int(H * 0.06), size, gap=12)
    return np.asarray(img.convert('RGB'))


def card_image(cls, lang, lay):
    """the class card of the promo kit fitted into the lower half of the class short"""
    x, y, s = lay['card']
    W, H = lay['W'], lay['H']
    card = Image.open(os.path.join(CARDS, '%s-1080.%s.jpg' % (cls, lang))).convert('RGB').resize((s, s), Image.LANCZOS)
    out = Image.new('RGB', (W, H - y), (8, 5, 5))
    out.paste(card, (x, 0))
    return np.asarray(out)


def logo_burn(lay):
    a = art()
    lg = a['gsk'].wordmark(a['gsa'], lay['logo_w'], tagline=False)
    r = np.random.RandomState(9)
    noise = Image.fromarray((r.rand(lg.height // 8 + 2, lg.width // 8 + 2) * 255).astype(np.uint8)).resize(lg.size, Image.BICUBIC)
    n = np.asarray(noise).astype(np.float32) / 255
    ys = np.linspace(0, 1, lg.height, dtype=np.float32)[:, None]
    n = np.clip(0.55 * n + 0.45 * (1 - ys) , 0, 1)       # burns from the bottom up, ragged
    return np.asarray(lg), n


def draw_logo_burn(frame, logo, noise, p, cx, cy):
    """p 0..1.2: the logo appears where the noise is below p, with a hot ember edge"""
    h, w = logo.shape[:2]
    a = logo[..., 3].astype(np.float32) / 255
    vis = np.clip((p - noise) * 9, 0, 1)
    edge = np.clip(1 - np.abs(p - noise) * 12, 0, 1) * (a > 0.05)
    x, y = cx - w // 2, cy - h // 2
    reg = frame[y:y + h, x:x + w].astype(np.float32)
    body = logo[..., :3].astype(np.float32)
    alpha = (a * vis)[..., None]
    out = reg * (1 - alpha) + body * alpha
    out = out + edge[..., None] * np.array((255, 120, 25), np.float32) * 0.85
    frame[y:y + h, x:x + w] = np.clip(out, 0, 255).astype(np.uint8)


# ------------------------------------------------------------------------------------------------ video plans
def trailer_parts():
    """docs/PROMO.md section 3: (seconds, shot) with the scene, the caption and the camera direction"""
    cls = [(8 / 7, dict(kind='scene', scene='class_' + c, label=c, rev=i % 2 == 1)) for i, c in enumerate(CLASS_ORDER)]
    return ([(4, dict(kind='intro')),
             (6, dict(kind='scene', scene='town', fade_in=True)),
             ] + cls + [
            (6, dict(kind='scene', scene='hunt1')),
            (4, dict(kind='scene', scene='hunt3')),
            (4, dict(kind='scene', scene='hunt4', rev=True)),
            (4, dict(kind='scene', scene='hunt2', rev=True)),
            (4, dict(kind='scene', scene='dungeon')),
            (8, dict(kind='scene', scene='boss')),
            (6, dict(kind='scene', scene='clash')),
            (6, dict(kind='end'))])


# caption windows: (first part index of the trailer parts, last part index, key)
def trailer_captions(tl):
    """tl: the built timeline of trailer_parts(); returns [(t0, t1, key)] following the docs/PROMO.md table"""
    idx = {}
    for i, (t0, t1, p) in enumerate(tl):
        idx.setdefault(p.get('scene', p['kind']), []).append(i)
    ti = lambda n: tl[idx[n][0]]  # noqa: E731
    cl = [tl[idx['class_' + c][0]] for c in CLASS_ORDER]
    return [(ti('town')[0] + 0.5, ti('town')[1] - 0.3, 'world'),
            (cl[0][0] + 0.1, cl[-1][1] - 0.1, 'classes'),
            (ti('hunt1')[0] + 0.3, ti('hunt1')[1] - 0.3, 'build'),
            (ti('hunt3')[0] + 0.3, ti('hunt4')[1] - 0.3, 'loot'),
            (ti('hunt2')[0] + 0.3, ti('dungeon')[1] - 0.3, 'rift'),
            (ti('boss')[0] + 0.3, ti('boss')[1] - 0.3, 'raid'),
            (ti('clash')[0] + 0.3, ti('clash')[1] - 0.3, 'pvp'),
            (tl[-1][0] + 0.5, tl[-1][1] - 0.4, 'free')]


def classes_parts():
    return ([(3, dict(kind='scene', scene='class_' + c, label=c, rev=i % 2 == 1, card=c)) for i, c in enumerate(CLASS_ORDER)]
            + [(3.5, dict(kind='end'))])


def world_parts():
    return [(4, dict(kind='scene', scene='hunt2')), (4, dict(kind='scene', scene='hunt3', rev=True)),
            (4, dict(kind='scene', scene='hunt4')), (5, dict(kind='scene', scene='boss', rev=True)), (3, dict(kind='end'))]


def video_specs():
    """[(file name, layout, lang, parts function, total seconds, music file)]"""
    out = []
    for lang in LANGS:
        out.append(('trailer-1920x1080.%s.mp4' % lang, 'wide', lang, 'trailer', 60.0, 'music_boss.ogg'))
    out.append(('trailer-1080x1920.pt-BR.mp4', 'tall', 'pt-BR', 'trailer', 60.0, 'music_boss.ogg'))
    for lang in LANGS:
        out.append(('short-classes-1080x1920.%s.mp4' % lang, 'classes', lang, 'classes', 24.5, 'music_login.ogg'))
    out.append(('short-world-1080x1920.pt-BR.mp4', 'tall', 'pt-BR', 'world', 20.0, 'music_hunt.ogg'))
    return out


# ------------------------------------------------------------------------------------------------ the frame
class Renderer:
    def __init__(self, cache, scenes, lay_name, lang, plan, bpm):
        self.cache, self.scenes, self.lang = cache, scenes, lang
        self.lay = layouts()[lay_name]
        L = self.lay
        self.W, self.H = L['W'], L['H']
        gx, gy, gw, gh = L['game']
        self.gw, self.gh = gw, gh
        self.sw, self.sh = gw // SCALE, gh // SCALE
        self.plan = plan
        self.assets, self.masks = {}, {}
        self.embers = Embers(gw, gh, 70, 1, speed=0.9)
        self.embers_bg = Embers(self.W, self.H, 90, 2, speed=0.8)
        self.rain = None
        self.caps = {}
        self.bg = None
        self.flash_frames = 5

    # --- assets
    def asset(self, name):
        a = self.assets.get(name)
        if a is None:
            a = SceneAsset(self.cache, name, scene_key(self.scenes[name]))
            self.assets[name] = a
        return a

    def mask(self, grade):
        m = self.masks.get(grade)
        if m is None:
            m = grade_mask(self.sw, self.sh, grade)
            self.masks[grade] = m
        return m

    def caption(self, key):
        c = self.caps.get(key)
        if c is None:
            L = self.lay
            c = caption_image(TEXT[self.lang][key], L['cap_size'], L['cap_w'])
            self.caps[key] = c
        return c

    def label(self, cls):
        k = ('label', cls, self.lang)
        c = self.caps.get(k)
        if c is None:
            title = art()['src']['classes'][cls][self.lang][0].upper()
            c = small_text(title, 50 if self.lay['kind'] != 'wide' else 46, 'heading', fill=art()['gsa'].GOLD_3)
            self.caps[k] = c
        return c

    def background(self):
        if self.bg is None:
            L = self.lay
            bg = backdrop_rgb(self.W, self.H) if L['kind'] != 'wide' else np.zeros((self.H, self.W, 3), np.uint8)
            if L['kind'] == 'tall':
                a = art()
                lg = a['gsk'].wordmark(a['gsa'], L['top_logo'], tagline=False)
                bg = bg.copy()
                blit_rgba(bg, np.asarray(lg), (self.W - lg.width) // 2, 30)
            self.bg = bg
        return self.bg

    # --- frame
    def camera(self, spec, shot, t, t0, t1):
        n = max(2, int(round((t1 - t0) * FPS)))
        key = ('cam', shot.get('scene'), t0)
        path = self.caps.get(key)
        if path is None:
            px, py = spec['x'], spec['y']
            dx, dy = spec['pan']
            ox, oy = spec.get('shift', [0, 0])
            a = ((-dx / 2 + ox) * TILE, (-dy / 2 + oy) * TILE)
            b = ((dx / 2 + ox) * TILE, (dy / 2 + oy) * TILE)
            if shot.get('rev'):
                a, b = b, a
            asset = self.asset(shot['scene'])
            cx0, cy0 = asset.w / 2 + TILE // 2, asset.h / 2 + TILE // 2
            path = pan_path((cx0 + a[0], cy0 + a[1]), (cx0 + b[0], cy0 + b[1]), n)
            self.caps[key] = path
        i = min(len(path) - 1, max(0, int(round((t - t0) * FPS))))
        return path[i]

    def game(self, shot, t, t0, t1, prev_kind):
        spec = self.scenes[shot['scene']]
        asset = self.asset(shot['scene'])
        cx, cy = self.camera(spec, shot, t, t0, t1)
        # the picture is centred on the scene's centre tile; class and boss scenes shift to frame their subject
        win, wx, wy = asset.crop(cx, cy + spec.get('dy', 0) * TILE, self.sw, self.sh)
        f = win.astype(np.float32) * self.mask(spec['grade'])
        age = t - t0
        fl = 1.0 - age * FPS / self.flash_frames if shot.get('flash', True) and prev_kind == 'scene' else 0.0
        if fl > 0:
            f += fl * np.array((120, 80, 40), np.float32)
        np.clip(f, 0, 255, out=f)
        g = np.repeat(np.repeat(f.astype(np.uint8), SCALE, axis=0), SCALE, axis=1)
        for i, inf in enumerate(asset.infos):
            bx, by = inf['cx'] - wx, inf['ty'] - 6 - wy
            if -40 < bx < self.sw + 40 and -20 < by < self.sh + 40:
                spr, (ax, ay) = asset.name_sprite(i)
                blit_rgba(g, spr, int(bx * SCALE) - ax, int(by * SCALE) - ay)
        if spec.get('rain'):
            if self.rain is None:
                self.rain = Rain(self.gw, self.gh)
            self.rain.draw(g, t)
        self.embers.draw(g, t, 0.8)
        return g

    def frame(self, t, tl, cap_windows):
        L = self.lay
        i = next((k for k, s in enumerate(tl) if s[0] <= t < s[1]), len(tl) - 1)
        t0, t1, shot = tl[i]
        prev = tl[i - 1][2]['kind'] if i else None
        gx, gy, gw, gh = L['game']
        kind = shot['kind']
        if kind == 'intro':
            canvas = np.zeros((self.H, self.W, 3), np.uint8)
            if 'logo' not in self.caps:
                self.caps['logo'] = logo_burn(L)
            logo, noise = self.caps['logo']
            p = ramp(t, 0.7, 2.7) * 1.2
            self.embers_bg.draw(canvas, t, 1.0 * ramp(t, 0.0, 0.8))
            cy = self.H // 2 if L['kind'] == 'wide' else gy + gh // 2 - 100
            draw_logo_burn(canvas, logo, noise, p, self.W // 2, cy)
            canvas = (canvas * (1 - ramp(t, t1 - 0.5, t1))).astype(np.uint8)
            return canvas
        if kind == 'end':
            if 'end' not in self.caps:
                self.caps['end'] = end_card(self.lang, L)
            canvas = self.caps['end'].copy()
            self.embers_bg.draw(canvas, t, 0.7)
            canvas = (canvas * ramp(t, t0, t0 + 0.5)).astype(np.uint8)
            return self._fade_out(canvas, t)
        # a scene
        canvas = self.background().copy() if L['kind'] != 'wide' else np.zeros((self.H, self.W, 3), np.uint8)
        g = self.game(shot, t, t0, t1, prev)
        if shot.get('fade_in'):
            g = (g * ramp(t, t0, t0 + 0.6)).astype(np.uint8)
        canvas[gy:gy + gh, gx:gx + gw] = g
        if L['kind'] == 'tall':
            self.embers_bg.draw(canvas[:gy], t, 0.6)
            self.embers_bg.draw(canvas[gy + gh:], t, 0.6)
        if L['scrim']:
            a, b = L['scrim']
            ys = np.linspace(0, 1, b - a, dtype=np.float32)
            ramp_ = (ys if a > 0 else 1 - ys)[:, None, None]
            canvas[a:b] = (canvas[a:b] * (1 - 0.62 * ramp_ ** 1.2)).astype(np.uint8)
        if shot.get('card'):
            card = self.caps.get(('card', shot['card'], self.lang))
            if card is None:
                card = card_image(shot['card'], self.lang, L)
                self.caps[('card', shot['card'], self.lang)] = card
            canvas[L['card'][1]:] = (card * ramp(t, t0 + 0.15, t0 + 0.45)).astype(np.uint8) + \
                (canvas[L['card'][1]:] * (1 - ramp(t, t0 + 0.15, t0 + 0.45))).astype(np.uint8)
        for c0, c1, key in cap_windows:
            if c0 <= t < c1:
                a = ramp(t, c0, c0 + 0.35) * (1 - ramp(t, c1 - 0.35, c1))
                img = self.caption(key)
                lift = int((1 - ramp(t, c0, c0 + 0.35)) * 16)
                blit_rgba(canvas, img, L['cap'][0] - img.shape[1] // 2, L['cap'][1] - img.shape[0] // 2 + lift, a)
        if shot.get('label') and L['label']:
            img = self.label(shot['label'])
            a = ramp(t, t0, t0 + 0.12)
            blit_rgba(canvas, img, L['label'][0] - img.shape[1] // 2, L['label'][1] - img.shape[0] // 2, a)
        return self._fade_out(canvas, t)

    def _fade_out(self, canvas, t):
        end = self.plan_end
        f = 1 - ramp(t, end - 0.6, end)
        return canvas if f >= 1 else (canvas * f).astype(np.uint8)


def render_video(job):
    (name, lay_name, lang, plan_name, total, music), cache, scenes, out_dir, bpm, offset, stills = job
    grid = 60.0 / bpm
    parts = {'trailer': trailer_parts, 'classes': classes_parts, 'world': world_parts}[plan_name]()
    tl = build_timeline(parts, total, grid)
    if plan_name == 'trailer':
        caps = trailer_captions(tl)
    elif plan_name == 'world':
        caps = [(tl[0][0] + 0.4, tl[2][1] - 0.3, 'hunts'), (tl[3][0] + 0.3, tl[3][1] - 0.3, 'bosses'), (tl[4][0] + 0.5, tl[4][1] - 0.3, 'free')]
    else:
        caps = [(0.0, tl[-2][1] - 0.2, 'choose')]
    r = Renderer(cache, scenes, lay_name, lang, plan_name, bpm)
    r.plan_end = total
    n = int(round(total * FPS))
    path = os.path.join(out_dir, name)
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (r.W, r.H), '-r', str(FPS),
           '-i', '-', '-stream_loop', '-1', '-ss', '%.3f' % offset, '-i', os.path.join(MUSIC_DIR, music), '-t', '%.3f' % total,
           '-map', '0:v', '-map', '1:a', '-af', 'afade=t=in:st=0:d=1.5,afade=t=out:st=%.3f:d=2.5,volume=0.9' % (total - 2.5),
           '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-maxrate', '5M', '-bufsize', '10M', '-pix_fmt', 'yuv420p',
           '-movflags', '+faststart', '-c:a', 'aac', '-b:a', '160k', path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    still_at = {int(round(t * FPS)): k for k, t in enumerate(stills)} if stills else {}
    for fi in range(n):
        fr = r.frame(fi / FPS, tl, caps)
        p.stdin.write(np.ascontiguousarray(fr).data)
        if fi in still_at:
            Image.fromarray(fr).save(os.path.join(stills_dir(out_dir), 'trailer-still-%d.png' % (still_at[fi] + 1)))
        if fi % 300 == 0:
            print('  %s %d/%d' % (name, fi, n), flush=True)
    p.stdin.close()
    if p.wait() != 0:
        raise RuntimeError('ffmpeg failed for ' + name)
    return name, os.path.getsize(path)


def stills_dir(out_dir):
    return os.environ.get('PROMO_STILLS') or out_dir


STILL_TIMES = (2.4, 7.0, 13.2, 21.0, 30.0, 44.0, 51.0)


def music_tempo(music):
    p = subprocess.run(['ffmpeg', '-v', 'error', '-i', os.path.join(MUSIC_DIR, music), '-t', '45', '-ac', '1', '-ar', '11025',
                        '-f', 's16le', '-'], capture_output=True, check=True)
    x = np.frombuffer(p.stdout, np.int16).astype(np.float64) / 32768
    return estimate_bpm(x, 11025)


# ------------------------------------------------------------------------------------------------ main
def prepare_scenes(a):
    print('reading monsters and spawns ...', flush=True)
    mon = read_monsters(os.path.join(a.server, 'data', 'monster'))
    wdir = os.path.join(a.server, 'data', 'world')
    spawn_file = next(f for f in sorted(os.listdir(wdir)) if f.endswith('-spawn.xml'))
    with open(os.path.join(wdir, spawn_file), encoding='utf-8', errors='replace') as f:
        mons = parse_spawns(f.read())
    health = lambda n: mon[n.lower()]['health'] if n.lower() in mon and not re.search(r'training|dummy', n, re.I) else None  # noqa: E731
    return mon, mons, health


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--server', required=True)
    ap.add_argument('--pair', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--cache')
    ap.add_argument('--scenes')
    ap.add_argument('--only')
    ap.add_argument('--stills')
    ap.add_argument('--jobs', type=int, default=min(4, os.cpu_count() or 1))
    ap.add_argument('--list-scenes', action='store_true')
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    cache = a.cache or os.path.join(a.out, '_cache')
    os.makedirs(cache, exist_ok=True)
    sc_path = os.path.join(cache, 'scenes.json')
    mon, mons, health = prepare_scenes(a)
    world = None
    if os.path.isfile(sc_path):
        scenes = json.load(open(sc_path, encoding='utf-8'))
    else:
        world = World(a.server, a.pair, cache)
        scenes = choose_scenes(dense_windows(mons, health), world.m.towns, read_lair_bosses(), health, quality=world.quality)
        t = scenes['town']
        t['temple'] = [t['x'], t['y']]
        t['x'], t['y'] = world.best_town_window(t['x'], t['y'], t['z'])
    if a.scenes:
        scenes = apply_overrides(scenes, json.load(open(a.scenes, encoding='utf-8')))
    with open(sc_path, 'w', encoding='utf-8') as f:
        json.dump(scenes, f, indent=1, sort_keys=True)
    for k, v in sorted(scenes.items()):
        print('scene %-18s %-6s at %d,%d,%d  %s' % (k, v['kind'], v['x'], v['y'], v['z'], {x: v[x] for x in ('top', 'count', 'monster', 'label') if x in v}))
    if a.list_scenes:
        return 0
    missing = [k for k, v in scenes.items() if not os.path.isfile(os.path.join(cache, '%s-%s.png' % (k, scene_key(v))))]
    if missing:
        world = world or World(a.server, a.pair, cache)
        spawns = SpawnIndex(mons)
        for k in missing:
            print('drawing scene', k, flush=True)
            img, infos = build_scene(world, scenes[k], spawns, mon, k)
            base = os.path.join(cache, '%s-%s' % (k, scene_key(scenes[k])))
            Image.fromarray(img).save(base + '.png')
            with open(base + '.json', 'w', encoding='utf-8') as f:
                json.dump(infos, f)
        del world
    todo = [v for v in video_specs() if not a.only or a.only in v[0]]
    tempos = {}
    for v in todo:
        if v[5] not in tempos:
            tempos[v[5]] = music_tempo(v[5])
            print('music %s: %.1f bpm, first beat at %.2f s' % (v[5], *tempos[v[5]]), flush=True)
    stills = STILL_TIMES if a.stills else None
    if a.stills:
        os.makedirs(a.stills, exist_ok=True)
        os.environ['PROMO_STILLS'] = a.stills
    jobs = [(v, cache, scenes, a.out, tempos[v[5]][0], tempos[v[5]][1], stills if v[0] == 'trailer-1920x1080.pt-BR.mp4' else None)
            for v in todo]
    with cf.ProcessPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        for name, size in ex.map(render_video, jobs):
            print('done %s %.1f MB' % (name, size / 1e6), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Tests of gen_promo_video.py on synthetic data only (no sprite pair, no map, no ffmpeg): caption layout, the timeline
sums to the target length and sits on the beat grid, the camera pan path, the tempo estimate on a click track, the scene
choice on a synthetic spawn list (deterministic, independent of the input order), the spawn and monster readers, and the
class looks read from class_looks_core.lua.

    python3 -I website/tools/gen_promo_video_test.py
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import gen_promo_video as g  # noqa: E402

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def test_timeline():
    for parts_fn, total in ((g.trailer_parts, 60.0), (g.classes_parts, 24.5), (g.world_parts, 20.0)):
        for bpm in (120.0, 105.0, 93.3, 160.0):
            grid = 60.0 / bpm
            tl = g.build_timeline(parts_fn(), total, grid)
            expect(abs(sum(b - a for a, b, _ in tl) - total) < 1e-4, '%s at %s bpm sums to %s' % (parts_fn.__name__, bpm, total))
            expect(tl[0][0] == 0 and abs(tl[-1][1] - total) < 1e-6, 'starts at 0 and ends at the total')
            expect(all(abs(tl[i][1] - tl[i + 1][0]) < 1e-9 for i in range(len(tl) - 1)), 'contiguous')
            expect(all(b - a >= grid - 1e-6 for a, b, _ in tl[:-1]), 'every cut keeps one beat')
            inner = [b for _, b, _ in tl[:-1]]
            expect(all(abs(b / grid - round(b / grid)) < 1e-4 for b in inner), 'inner cuts on the beat at %s bpm' % bpm)
            expect(len(tl) == len(parts_fn()), 'one entry per part')
    tl = g.build_timeline(g.trailer_parts(), 60.0, 0.5)
    expect([round(t[0], 3) for t in tl[:3]] == [0.0, 4.0, 10.0], 'trailer table: logo 0-4, town 4-10')
    expect(tl[-1][0] == 54.0, 'the end card starts at 54 s as in docs/PROMO.md')
    kinds = [p['kind'] for _, _, p in tl]
    expect(kinds[0] == 'intro' and kinds[-1] == 'end', 'intro first, end card last')
    try:
        g.build_timeline([(1, 'a')] * 10, 3.0, 0.5)
        expect(False, 'too many parts for the grid raise')
    except ValueError:
        pass


def test_captions():
    tl = g.build_timeline(g.trailer_parts(), 60.0, 0.5)
    caps = g.trailer_captions(tl)
    expect([c[2] for c in caps] == ['world', 'classes', 'build', 'loot', 'rift', 'raid', 'pvp', 'free'], 'caption order of the plan')
    expect(all(a < b for a, b, _ in caps), 'every caption lasts')
    expect(all(caps[i][1] <= caps[i + 1][0] + 1e-9 for i in range(len(caps) - 1)), 'captions do not overlap')
    expect(caps[0][0] >= 4.0 and caps[-1][1] <= 60.0, 'captions inside the video')
    for lang, t in g.TEXT.items():
        for key in ('world', 'classes', 'build', 'loot', 'rift', 'raid', 'pvp', 'free', 'choose', 'hunts', 'bosses'):
            expect(key in t and t[key], 'text %s/%s' % (lang, key))
        expect('—' not in ''.join(t.values()) and ' - ' not in ''.join(t.values()), 'no dashes in %s texts' % lang)
    expect(g.TEXT['pt-BR']['free'] == 'Grátis. PC e Android.' and g.TEXT['en']['free'] == 'Free. PC and Android.', 'end line')
    img = g.caption_image(g.TEXT['pt-BR']['world'], 96, 1700)
    expect(img.ndim == 3 and img.shape[2] == 4 and img[..., 3].max() == 255, 'caption image is RGBA with opaque letters')
    expect(img.shape[1] <= 1700 + 140, 'caption fits its width (%d)' % img.shape[1])
    ys, xs = np.nonzero(img[..., 3] > 40)
    expect(xs.min() > 0 and ys.min() > 0 and xs.max() < img.shape[1] - 1 and ys.max() < img.shape[0] - 1, 'caption not clipped')
    small = g.caption_image(g.TEXT['pt-BR']['raid'], 84, 980)
    expect(small.shape[1] <= 980 + 140, 'vertical caption fits')


def test_pan():
    p = g.pan_path((100, 200), (500, 260), 91)
    expect(len(p) == 91 and p[0] == (100, 200) and p[-1] == (500, 260), 'pan starts and ends on its points')
    xs = [q[0] for q in p]
    expect(all(b >= a for a, b in zip(xs, xs[1:])), 'pan moves one way')
    expect(all(isinstance(q[0], int) and isinstance(q[1], int) for q in p), 'integer pixel steps')
    steps = [b - a for a, b in zip(xs, xs[1:])]
    expect(max(steps) <= 8 and min(steps) >= 0, 'smooth: no jump over 8 px (%d)' % max(steps))
    r = g.pan_path((500, 260), (100, 200), 30)
    expect(r[0] == (500, 260) and r[-1] == (100, 200), 'reverse pan')
    expect(g.pan_path((5, 5), (9, 9), 1) == [(9, 9)], 'one frame pan')


def test_tempo():
    sr = 11025
    for bpm, off in ((120.0, 0.0), (100.0, 0.25), (140.0, 0.1)):
        x = np.zeros(sr * 40)
        step = 60.0 / bpm
        t = off
        k = 0
        while t < 39.5:
            i = int(t * sr)
            x[i:i + 400] += np.hanning(800)[:400] * (1.0 if k % 4 == 0 else 0.6) * np.sin(np.arange(400) * 0.3)
            t += step
            k += 1
        got, goff = g.estimate_bpm(x, sr)
        expect(abs(got - bpm) < 1.5, 'tempo %s estimated as %.2f' % (bpm, got))
        d = (goff - off) % step
        expect(min(d, step - d) < 0.06, 'first beat %.2f for %.2f at %s bpm' % (goff, off, bpm))


SPAWN = '''<?xml version="1.0"?>
<spawns>
	<spawn centerx="100" centery="200" centerz="7" radius="2">
		<monster name="Rat &amp; Co" x="1" y="-1" z="7" spawntime="60" />
		<monster name="Cave Rat" x="-2" y="0" spawntime="60" />
	</spawn>
	<spawn centerx="300" centery="400" centerz="9" radius="2"><monster name="Troll" x="0" y="0" z="9" spawntime="60" /></spawn>
</spawns>'''

MONSTER = '''<?xml version="1.0"?>
<monster name="Troll" nameDescription="a troll" race="blood" experience="20" speed="100">
	<health now="50" max="55" />
	<look type="15" head="1" body="2" legs="3" feet="4" addons="1" corpse="1" />
</monster>'''


def test_readers():
    sp = g.parse_spawns(SPAWN)
    expect(sp == [(101, 199, 7, 'Rat & Co'), (98, 200, 7, 'Cave Rat'), (300, 400, 9, 'Troll')], 'spawn offsets and entities: %s' % sp)
    m = g.parse_monster_xml(MONSTER)
    expect(m and m['name'] == 'Troll' and m['health'] == 55 and m['exp'] == 20, 'monster header')
    expect(m['look'] == dict(type=15, typeex=0, head=1, body=2, legs=3, feet=4, addons=1), 'monster look')
    expect(g.creature_outfit(m) == dict(t=15, h=1, b=2, l=3, f=4, a=1), 'outfit of a monster')
    ex = g.parse_monster_xml('<monster name="Chest"><health now="1" max="1"/><look typeex="1740"/></monster>')
    expect(g.creature_outfit(ex) == dict(t=0, x=1740), 'item look')
    expect(g.parse_monster_xml('<monster name="X"><health now="1" max="1"/></monster>') is None, 'no look, no monster')


def test_class_looks():
    looks = g.read_class_looks()
    expect(sorted(looks) == sorted(g.CLASS_ORDER), 'seven classes')
    ids = [v['look'] for v in looks.values()]
    expect(len(set(ids)) == 7 and all(2000 <= i <= 2300 for i in ids), 'seven different class looks: %s' % ids)
    expect(looks['warrior']['look'] == 2073 and looks['templar']['look'] == 2179, 'warrior and pair 20 templar look')
    expect(all(0 <= v[c] <= 132 for v in looks.values() for c in ('head', 'body', 'legs', 'feet')), 'palette colours')
    expect(len(set(g.CLASS_CHAR.values())) == 7 and set(g.CLASS_CHAR) == set(g.CLASS_ORDER), 'seven made-up names')
    bosses = g.read_lair_bosses()
    expect(len(bosses) >= 10 and all(len(p) == 3 for _, p in bosses), 'lair bosses read from bossspawns_config.lua')


def synthetic_spawns(seed=1):
    rnd = random.Random(seed)
    mons = []
    names = ['Rat', 'Wolf', 'Troll', 'Ogre', 'Wyrm', 'Lich', 'Imp', 'Golem']
    for k, (cx, cy, z, n) in enumerate([(1000, 1000, 7, 60), (1200, 1000, 7, 50), (1500, 1300, 7, 45), (1900, 900, 7, 40),
                                       (2300, 800, 10, 55), (2600, 1500, 12, 35), (3000, 400, 7, 30), (3300, 900, 9, 28),
                                       (3600, 700, 7, 26), (3900, 2000, 11, 24), (4200, 600, 7, 22), (4500, 1100, 7, 20),
                                       (4800, 1700, 8, 18), (5100, 300, 7, 16), (5400, 2500, 14, 15), (5700, 1900, 7, 14)]):
        for i in range(n):
            mons.append((cx + rnd.randint(-12, 12), cy + rnd.randint(-8, 8), z, names[(k + i % 3) % len(names)]))
    for i in range(10):
        mons.append((100 + i, 100, 7, 'Rat'))
    return mons


HEALTH = {'Rat': 20, 'Wolf': 120, 'Troll': 500, 'Ogre': 1500, 'Wyrm': 6000, 'Lich': 20000, 'Imp': 300, 'Golem': 3000}


def test_scene_choice():
    mons = synthetic_spawns()
    towns = [(2, 'Cinderhold', (950, 990, 7)), (1, 'Elsewhere', (10, 10, 7))]
    bosses = [('Lich', (4000, 4000, 7)), ('Rat', (4100, 4100, 7)), ('Nobody', (1, 1, 7))]
    health = lambda n: HEALTH.get(n)  # noqa: E731
    w1 = g.dense_windows(mons, health)
    sc1 = g.choose_scenes(w1, towns, bosses, health)
    sh = list(mons)
    random.Random(7).shuffle(sh)
    w2 = g.dense_windows(sh, health)
    sc2 = g.choose_scenes(list(reversed(w2)), list(reversed(towns)), list(reversed(bosses)), health)
    expect(sc1 == sc2, 'the choice does not depend on the input order')
    expect(sc1 == g.choose_scenes(w1, towns, bosses, health), 'same input, same choice')
    expect((sc1['town']['x'], sc1['town']['y'], sc1['town']['z']) == (950, 990, 7), 'the main town is Cinderhold')
    for name in ['town', 'hunt1', 'hunt2', 'hunt3', 'hunt4', 'dungeon', 'boss', 'clash'] + ['class_' + c for c in g.CLASS_ORDER]:
        expect(name in sc1, 'scene %s chosen' % name)
    expect(sc1['boss']['monster'] == 'Lich', 'the boss is the one with the most health')
    expect(sc1['dungeon']['z'] >= 9, 'the dungeon is underground (z %s)' % sc1['dungeon']['z'])
    hunts = [sc1['hunt%d' % i] for i in range(1, 5)]
    expect(len({(h['x'], h['y'], h['z']) for h in hunts}) == 4, 'four different hunts')
    for i, a in enumerate(hunts):
        for b in hunts[i + 1:]:
            expect(abs(a['z'] - b['z']) > 1 or max(abs(a['x'] - b['x']), abs(a['y'] - b['y'])) >= 60, 'hunts apart')
    expect(sc1['clash']['clear'] > 0, 'the clash ground is cleared of monsters')
    # a hand override
    over = g.apply_overrides({k: dict(v) for k, v in sc1.items()}, {'town': {'x': 5}, 'extra': dict(kind='hunt', x=1, y=2, z=3), 'bad': {'x': 1}})
    expect(over['town']['x'] == 5 and 'extra' in over and 'bad' not in over, 'overrides merge, new scenes need a kind and a place')
    expect(g.scene_key(sc1['town']) == g.scene_key(dict(sc1['town'])) and g.scene_key(sc1['town']) != g.scene_key(over['town']), 'cache key')


def test_players():
    for kind, n in (('class', 1), ('town', 4), ('boss', 7), ('clash', 8), ('hunt', 0)):
        spec = dict(kind=kind, cls='ranger')
        expect(len(g.players_for(spec)) == n, '%s has %d players' % (kind, n))
    expect(len({p[1] for p in g.players_for(dict(kind='clash'))}) == 8, 'eight different names in the clash')
    walk = np.ones((10, 10), bool)
    walk[5][5] = False
    expect(g.nearest_free(walk, set(), 5, 5) in {(4, 4), (5, 4), (6, 4), (4, 5), (6, 5), (4, 6), (5, 6), (6, 6)}, 'nearest free tile')
    expect(g.nearest_free(walk, {(1, 1)}, 1, 1) != (1, 1), 'occupied tile is skipped')
    expect(g.nearest_free(np.zeros((4, 4), bool), set(), 1, 1, 3) is None, 'no free tile')


def test_effects():
    e = g.Embers(320, 180, 30, 1)
    f = np.zeros((180, 320, 3), np.uint8)
    e.draw(f, 1.5)
    expect(f.any() and f[..., 0].max() > f[..., 2].max(), 'embers are warm')
    f2 = np.zeros_like(f)
    g.Embers(320, 180, 30, 1).draw(f2, 1.5)
    expect((f == f2).all(), 'embers are deterministic')
    m = g.grade_mask(64, 36, 'dusk')
    expect(m.shape == (36, 64, 3) and m[18, 32].min() > m[0, 0].max(), 'vignette darkens the corners')
    lg = np.zeros((20, 30, 4), np.uint8)
    lg[5:15, 5:25] = 255
    n = np.linspace(0, 1, 30, dtype=np.float32)[None, :].repeat(20, 0)
    fr = np.zeros((40, 50, 3), np.uint8)
    g.draw_logo_burn(fr, lg, n, 0.0, 25, 20)
    a0 = int(fr.sum())
    g.draw_logo_burn(fr, lg, n, 1.2, 25, 20)
    expect(fr.sum() > a0 and fr[20, 25].min() > 200, 'the logo burns in')
    c = np.zeros((30, 30, 3), np.uint8)
    spr = np.zeros((10, 10, 4), np.uint8)
    spr[..., 3] = 255
    spr[..., 0] = 200
    g.blit_rgba(c, spr, -5, 25, 0.5)
    expect(c[27, 2, 0] == 100 and c[2, 2, 0] == 0, 'blit clips and blends')


def main():
    for fn in (test_timeline, test_captions, test_pan, test_tempo, test_readers, test_class_looks, test_scene_choice, test_players,
               test_effects):
        fn()
    if FAILS:
        print(len(FAILS), 'failures')
        return 1
    print('gen_promo_video_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())

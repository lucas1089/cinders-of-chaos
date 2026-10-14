#!/usr/bin/env python3
"""Banners of the generated queue dungeons (client game_dungeons, the strip at the top of the queue window).

The five dungeons the server builds itself (server/data/scripts/chaos/areagen_config.lua: the Hollow Vault and the
dungeons 6-9) get a banner like the hand-made ones of the base dungeons (client/overlay/data/images/dungeons/*.png,
966 x 100, the map at 32 px a tile with the dungeon's creatures standing in it). Each is a render of the dungeon's own
map: the tiles come from the area generator itself (server/tools/areagen_dump.lua through areagen_export.py, with the
dark tile set the live server uses), drawn with our sprite pair the way tools/map/render.py draws a map, the boss and
the dungeon's monsters (their looks from server/data/monster) standing on the walkable tiles, the light sources glowing
and the ends of the strip a little darker. No picture is copied from anywhere: every pixel is a sprite of the pair.

    python3 -I client/tools/gen_dungeon_banners.py plan ITEMS.otb ITEMS.xml Tibia.dat
        choose each banner's window of the map and its creatures and write the plan
        (client/tools/dungeon_banners.json: per tile the server ids, the client ids in draw order, lights)
    python3 -I client/tools/gen_dungeon_banners.py build --dat Tibia.dat --spr Tibia.spr
        draw the banners from the plan (only the pair is needed) into client/overlay/data/images/dungeons/
    python3 -I client/tools/gen_dungeon_banners.py --check [--dat Tibia.dat --spr Tibia.spr]
        exit 1 when the plan no longer matches the dungeon (a fresh areagen dump: the window's tiles, the boss, the
        monsters and their looks), when a banner's pixels are not the ones the plan recorded, or (with the pair) when a
        fresh render differs from the files

`plan` needs LuaJIT, numpy and items.otb / items.xml of an installed server (server id -> client id, draw order, light);
`build` and the pixel check need numpy, Pillow and the pair; the plan check needs LuaJIT only. Deterministic: the same
plan and pair give the same pixels (the plan records their md5, of the RGBA pixels, not of the PNG bytes, so another
zlib or Pillow version does not matter).
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
SERVER = os.path.join(REPO, 'server')
OUT = os.path.join(REPO, 'client', 'overlay', 'data', 'images', 'dungeons')
PLAN = os.path.join(HERE, 'dungeon_banners.json')
MONSTERS = os.path.join(SERVER, 'data', 'monster')
sys.path.insert(0, os.path.join(SERVER, 'tools'))
sys.path.insert(0, os.path.join(HERE, 'sprites'))
sys.path.insert(0, os.path.join(REPO, 'tools', 'map'))

# areagen area id -> banner name (game_dungeons/dungeonsview.lua V.BANNERS maps the titles to these)
DUNGEONS = [
    ('vault', 'HollowVault'),
    ('marrow', 'MarrowCrypts'),
    ('crucible', 'IronCrucible'),
    ('sanctum', 'FallenSanctum'),
    ('throne', 'PyreThrone'),
]
W, H = 966, 100        # the banner (the hand-made ones have this size)
TW, TH = 31, 4         # tiles drawn: 992 x 128 px, cut to the banner around its centre
CUT_X, CUT_Y = (TW * 32 - W) // 2, (TH * 32 - H) // 2
STAND_ROW = 2          # creatures stand on this row of the window (a 2 x 2 look stays inside the 100 px)
MAX_MONSTERS = 5
PAD = 3                # tiles south-east of the window drawn too, so big sprites standing outside overlap it


# ------------------------------------------------------------------------------------------------ the model
def dump(area_id):
    import areagen_export as ax
    areas = ax.run_dump(area_id, dark=True)
    if len(areas) != 1:
        raise SystemExit('areagen_dump gave %d areas for %s' % (len(areas), area_id))
    return areas[0]


def monster_looks():
    """name (lower case) -> look type, from every monster file of the repository"""
    looks = {}
    for root, _, files in os.walk(MONSTERS):
        for f in sorted(files):
            if not f.endswith('.xml'):
                continue
            s = open(os.path.join(root, f), encoding='latin1').read()
            n = re.search(r'<monster\b[^>]*\bname="([^"]+)"', s)
            lk = re.search(r'<look\b[^>]*\btype="(\d+)"', s)
            if n and lk:
                looks.setdefault(n.group(1).lower(), int(lk.group(1)))
    return looks


def tiles_of(area):
    return {(t['x'], t['y']): t for t in area['tiles'] if t['z'] == area['origin'][2]}


def stack_sids(t):
    return [t['ground']] + t['items'] if t else []


def creature_names(area):
    """the boss (monster file, shown name) and the monster kinds of the run, most spawned first"""
    count = {}
    order = []
    for s in area['spawns']:
        if s['monster'] not in count:
            order.append(s['monster'])
            count[s['monster']] = 0
        count[s['monster']] += s['count']
    kinds = sorted(order, key=lambda m: (-count[m], order.index(m)))
    return area['boss'], kinds


# ------------------------------------------------------------------------------------------------ plan
def choose_window(area, tiles, db):
    """the 31 x 4 window with the most to see: walkable floor, the boss room, light sources"""
    ox, oy, _ = area['origin']
    boss = area['boss']
    best = None
    for y0 in range(oy - 1, oy + area['h'] - TH + 2):
        for x0 in range(ox - 1, ox + area['w'] - TW + 2):
            score = 0.0
            for dy in range(TH):
                wgt = 1.0 if dy in (1, 2) else 0.5
                walk_run = 0
                for dx in range(TW):
                    t = tiles.get((x0 + dx, y0 + dy))
                    if not t:
                        score -= 2.5 * wgt  # the black outside the map
                        walk_run = 0
                        continue
                    if t['walk']:
                        score += 2 * wgt
                        walk_run += 1
                    else:
                        score += 0.6 * wgt
                        walk_run = 0
                    if any(db.light[s] for s in t['items']):
                        score += 2.5 * wgt
            stand = sum(1 for dx in range(TW) if (tiles.get((x0 + dx, y0 + STAND_ROW)) or {}).get('walk'))
            score += stand * 1.5
            if boss and boss['y'] == y0 + STAND_ROW and x0 + 4 <= boss['x'] <= x0 + TW - 5:
                score += 40
            key = (score, -y0, -x0)
            if best is None or key > best[0]:
                best = (key, x0, y0)
    return best[1], best[2]


def place_creatures(area, tiles, x0, y0, looks, dat):
    """the boss on its own tile when the window holds it (else the middle), monsters spread over the stand row with
    room for their size (a 5 x 5 look takes more than a 2 x 2)"""
    boss, kinds = creature_names(area)
    row = y0 + STAND_ROW
    free = [x for x in range(x0 + 1, x0 + TW - 1) if (tiles.get((x, row)) or {}).get('walk')
            and len(tiles[(x, row)]['items']) <= 1]
    out = []
    taken = []  # (x, width in tiles)

    def width(look):
        t = dat.outfit(look)
        if t is None:
            raise SystemExit('look %d is not in the pair' % look)
        return t.w

    def fits(x, w):
        # a look reaches w - 1 tiles west of its tile
        return x - (w - 1) >= x0 and all(x - (w - 1) - 1 > tx or tx - (tw - 1) - 1 > x for tx, tw in taken)

    if boss:
        look = looks.get(boss['monster'].lower())
        if look is None:
            raise SystemExit('no monster file with the boss %r' % boss['monster'])
        w = width(look)
        bx = boss['x'] if boss['y'] == row and x0 + w <= boss['x'] <= x0 + TW - 3 else None
        if bx is None:
            mid = x0 + TW // 2 + w // 2
            near = [x for x in free if fits(x, w)]
            bx = min(near, key=lambda x: (abs(x - mid), x)) if near else None
        if bx is not None:
            out.append({'name': boss['name'], 'monster': boss['monster'], 'look': look, 'x': bx, 'y': row, 'boss': True})
            taken.append((bx, w))
    i = 0
    for x in free:
        if len(out) >= MAX_MONSTERS + 1 or not kinds:
            break
        m = kinds[i % len(kinds)]
        look = looks.get(m.lower())
        if look is None:
            raise SystemExit('no monster file with the monster %r' % m)
        w = width(look)
        if fits(x, w):
            out.append({'name': m, 'monster': m, 'look': look, 'x': x, 'y': row})
            taken.append((x, w))
            i += 1
    out.sort(key=lambda c: (c['y'], c['x']))
    return out


def tile_rows(tiles, x0, y0):
    """server id stacks of the window and its south-east pad, row by row"""
    rows = []
    for y in range(y0, y0 + TH + PAD):
        rows.append([stack_sids(tiles.get((x, y))) for x in range(x0, x0 + TW + PAD)])
    return rows


def draw_stack(sids, db):
    """client ids of a stack in the client's draw order: ground, borders, bottom (walls), common, top"""
    items = []
    for k, sid in enumerate(sids):
        c = int(db.cid[sid]) if sid < len(db.cid) else 0
        if not c:
            continue
        o = 0 if db.cls[sid] == 1 else int(db.order[sid]) if db.order[sid] in (1, 2, 3) else 4
        pr = {0: 0, 1: 1, 2: 2, 4: 3, 3: 4}[o]
        items.append((pr, k, c))
    items.sort()
    return [c for _, _, c in items]


def cmd_plan(otb, xml, dat):
    from itemdb import ItemDB
    db = ItemDB(otb, xml, dat)
    looks = monster_looks()
    plan = {'size': [W, H], 'tiles': [TW, TH], 'banners': []}
    for area_id, name in DUNGEONS:
        area = dump(area_id)
        tiles = tiles_of(area)
        x0, y0 = choose_window(area, tiles, db)
        rows = tile_rows(tiles, x0, y0)
        draw = [[draw_stack(s, db) for s in r] for r in rows]
        lights = [[x, y] for y, r in enumerate(rows) for x, s in enumerate(r) if any(db.light[i] for i in s[1:])]
        plan['banners'].append({
            'area': area_id, 'file': name + '.png', 'title': area['name'], 'window': [x0, y0, area['origin'][2]],
            'sids': rows, 'draw': draw, 'lights': lights,
            'creatures': place_creatures(area, tiles, x0, y0, looks, db.dat), 'pixels': None})
        print('%-9s window %d,%d  %d creatures' % (area_id, x0, y0, len(plan['banners'][-1]['creatures'])))
    old = load_plan(missing_ok=True)
    if old:  # keep the pixel sums of banners whose plan did not change
        for b in plan['banners']:
            for o in old['banners']:
                if o['area'] == b['area'] and strip(o) == strip(b):
                    b['pixels'] = o.get('pixels')
    save_plan(plan)
    print('wrote', os.path.relpath(PLAN, REPO), '(run build with the pair next)')


def strip(b):
    return {k: v for k, v in b.items() if k != 'pixels'}


def load_plan(missing_ok=False):
    if not os.path.exists(PLAN):
        if missing_ok:
            return None
        raise SystemExit('no plan: run  gen_dungeon_banners.py plan ITEMS.otb ITEMS.xml Tibia.dat')
    with open(PLAN, encoding='utf-8') as f:
        return json.load(f)


def save_plan(plan):
    text = json.dumps(plan, indent=1, sort_keys=True, separators=(',', ': '))
    # one tile row a line keeps the file readable and its diffs small
    text = re.sub(r'\[\s+([0-9,\s]*?)\s+\]', lambda m: '[' + re.sub(r'\s+', ' ', m.group(1)) + ']', text)
    with open(PLAN, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text + '\n')


# ------------------------------------------------------------------------------------------------ render
def render(b, dat, spr):
    import numpy as np
    from PIL import Image
    from datspr import render_thing
    things = dat.items
    canvas = Image.new('RGBA', ((TW + PAD) * 32, (TH + PAD) * 32), (0, 0, 0, 255))
    cache = {}

    def sprite(sid):
        im = cache.get(sid)
        if im is None:
            a = spr.sprite(sid)
            im = Image.fromarray(a, 'RGBA') if a is not None else False
            cache[sid] = im
        return im

    def put(im, dx, dy):
        if -im.width < dx < canvas.width and -im.height < dy < canvas.height:
            canvas.alpha_composite(im, (max(dx, 0), max(dy, 0)), (max(-dx, 0), max(-dy, 0)))

    x0, y0, z = b['window']
    creatures = {}
    for c in b['creatures']:
        creatures.setdefault((c['x'] - x0, c['y'] - y0), []).append(c)
    for ty, row in enumerate(b['draw']):
        for tx, cids in enumerate(row):
            x, y = x0 + tx, y0 + ty
            elev = 0
            for c in cids:
                if c - 100 >= len(things):
                    continue
                t = things[c - 100]
                px, py, pz = x % t.px, y % t.py, z % t.pz
                for hh in range(t.h):
                    for ww in range(t.w):
                        idx = (((((pz * t.py + py) * t.px + px) * t.layers + 0) * t.h + hh) * t.w + ww)
                        if idx >= len(t.sprites):
                            continue
                        im = sprite(t.sprites[idx])
                        if im:
                            put(im, (tx - ww) * 32 - elev, (ty - hh) * 32 - elev)
                if 'elevation' in t.flags:
                    elev = min(24, elev + t.flags['elevation'])
            # creatures stand on their tile, drawn with it (the next tiles' walls and tops go over them)
            for c in creatures.get((tx, ty), []):
                t = dat.outfit(c['look'])
                if t is None:
                    raise SystemExit('look %d is not in the pair' % c['look'])
                im = render_thing(t, spr, direction='south')
                ddx, ddy = signed_pair(t.flags.get('displacement'))
                bx, by = (tx + 1) * 32 - im.width - ddx - elev, (ty + 1) * 32 - im.height - ddy - elev
                put(im, bx, by + fit_shift(im, by))
    img = np.asarray(canvas, dtype=np.float64)[:TH * 32, :TW * 32, :3] / 255.0
    img = grade(img, b['lights'])
    out = np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8)
    full = Image.fromarray(out, 'RGB').convert('RGBA')
    return full.crop((CUT_X, CUT_Y, CUT_X + W, CUT_Y + H))


def signed_pair(v):
    """the dat's displacement (two u16: a negative one draws the look right / down), (0, 0) when the look has none"""
    if not isinstance(v, tuple):
        return 0, 0
    return tuple(a - 65536 if a > 32767 else a for a in v)


def fit_shift(im, y):
    """pixels to move a look down (+) or up (-) so its picture stays inside the banner: the feet above the bottom
    edge, and the head below the top edge first when it is too tall for both"""
    bb = im.getbbox()
    if not bb:
        return 0
    top, bottom = y + bb[1] - CUT_Y, y + bb[3] - CUT_Y
    shift = 0
    if bottom > H - 3:
        shift = H - 3 - bottom
    if top + shift < 2:
        shift = 2 - top
    return shift


def grade(img, lights):
    """warm glow around the light sources, the strip's ends and its top and bottom edge a little darker"""
    import numpy as np
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    glow = np.zeros((h, w))
    for lx, ly in lights:
        if lx >= TW + 1 or ly >= TH + 1:
            continue
        cx, cy = lx * 32 + 16, ly * 32 + 8
        d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (70.0 ** 2)
        glow += np.exp(-d2)
    glow = np.minimum(glow, 1.4)
    warm = np.array([1.0, 0.62, 0.28])
    img = img + glow[..., None] * warm * 0.16 * (0.35 + img)
    u = np.abs(xx - (w - 1) / 2.0) / ((w - 1) / 2.0)
    side = 1.0 - 0.38 * np.clip((u - 0.62) / 0.38, 0, 1) ** 1.6
    v = np.abs(yy - (h - 1) / 2.0) / ((h - 1) / 2.0)
    edge = 1.0 - 0.18 * np.clip((v - 0.55) / 0.45, 0, 1) ** 2
    return img * (side * edge)[..., None]


def pixel_md5(im):
    return hashlib.md5(im.convert('RGBA').tobytes()).hexdigest()


def load_pair(dat_path, spr_path):
    from datspr import Dat, Spr
    return Dat(dat_path), Spr(spr_path)


def cmd_build(dat_path, spr_path):
    plan = load_plan()
    dat, spr = load_pair(dat_path, spr_path)
    os.makedirs(OUT, exist_ok=True)
    for b in plan['banners']:
        im = render(b, dat, spr)
        path = os.path.join(OUT, b['file'])
        im.save(path, optimize=True)
        b['pixels'] = pixel_md5(im)
        print(os.path.relpath(path, REPO), im.size, b['pixels'])
    save_plan(plan)


# ------------------------------------------------------------------------------------------------ check
def cmd_check(dat_path=None, spr_path=None):
    plan = load_plan()
    looks = monster_looks()
    bad = []
    want = [a for a, _ in DUNGEONS]
    if [b['area'] for b in plan['banners']] != want:
        bad.append('the plan lists %s, the generator %s' % ([b['area'] for b in plan['banners']], want))
    for b in plan['banners']:
        area = dump(b['area'])
        tiles = tiles_of(area)
        x0, y0, _ = b['window']
        if tile_rows(tiles, x0, y0) != b['sids']:
            bad.append('%s: the map under the banner changed (areagen_config.lua): run plan and build' % b['area'])
        boss, kinds = creature_names(area)
        for c in b['creatures']:
            if looks.get(c['monster'].lower()) != c['look']:
                bad.append('%s: the look of %s changed: run plan and build' % (b['area'], c['monster']))
            if c.get('boss') and (not boss or boss['monster'] != c['monster'] or boss['name'] != c['name']):
                bad.append('%s: the boss changed: run plan and build' % b['area'])
            if not c.get('boss') and c['monster'] not in kinds:
                bad.append('%s: %s no longer runs in it: run plan and build' % (b['area'], c['monster']))
        path = os.path.join(OUT, b['file'])
        if not os.path.exists(path):
            bad.append('%s missing: run build' % os.path.relpath(path, REPO))
            continue
        from PIL import Image
        with Image.open(path) as im:
            if im.size != (W, H):
                bad.append('%s is %dx%d, not %dx%d' % (b['file'], im.size[0], im.size[1], W, H))
            got = pixel_md5(im)
        if got != b.get('pixels'):
            bad.append('%s: its pixels are not the ones the plan recorded: run build' % b['file'])
    if dat_path and spr_path:
        dat, spr = load_pair(dat_path, spr_path)
        for b in plan['banners']:
            if pixel_md5(render(b, dat, spr)) != b.get('pixels'):
                bad.append('%s: a fresh render from this pair differs' % b['file'])
    for line in bad:
        print('FAIL', line)
    print('dungeon banners: %d banners, %d problem(s)%s' % (len(plan['banners']), len(bad),
                                                             '' if dat_path else ' (plan and files; no pair given)'))
    return 1 if bad else 0


def main(argv):
    def opt(name):
        if name in argv:
            i = argv.index(name)
            return argv[i + 1] if i + 1 < len(argv) else None
        return None
    if argv[:1] == ['plan'] and len(argv) == 4:
        return cmd_plan(argv[1], argv[2], argv[3]) or 0
    if argv[:1] == ['build'] and opt('--dat') and opt('--spr'):
        return cmd_build(opt('--dat'), opt('--spr')) or 0
    if argv[:1] == ['--check']:
        return cmd_check(opt('--dat'), opt('--spr'))
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

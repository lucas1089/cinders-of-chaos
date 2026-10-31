#!/usr/bin/env python3
"""Painted icons (client setting "Painted icons", off by default): the buff bar, the spellbook's Chaos spells and the
passive tree's keystones and masteries, repainted from our own icons.

Run: python3 -I client/tools/gen_painted_icons.py            # build: writes every output below
     python3 -I client/tools/gen_painted_icons.py --check    # the committed outputs match the source sheet (CI)
     python3 -I client/tools/gen_painted_icons.py --sheet OUT.png [--scale 3]   # a labelled contact sheet
     python3 -I client/tools/gen_painted_icons.py pack --raw DIR [--jobs J1,J2,...]   # raw results -> source sheet

Source (committed, our own art): painted_icon_art/painted_64.png, one 64 x 64 cell per icon, 16 columns, in the order
of painted_icon_art/painted_icons.csv (index, kind, name, frame, element, job, seed). Each cell is a PixelLab
"Edit images (Pro)" result over our own current icon (the buff bar's 26 px icon, the spell sheet's 32 px cell, the
keystone sheet's 64 px cell, the mastery's atlas cell), its frame cut off and the art scaled to 58 px on a dark
plate; 16 icons per call, one generic prompt for all (the csv names the call). No other image went in. `pack` builds
the sheet from the raw call results (kept outside git) and classifies each icon's element once; the csv then fixes it.

Post-processing, deterministic (the same sheet gives the same files):
  1. the painted cell is scaled to the inner size of the target (Lanczos), lightly sharpened;
  2. palette clamp: every pixel snaps to the palette of the icon's element (fire, blood, holy, nature, frost, arcane,
     steel, mixed): the element's ramps from gen_buff_icons.R, with midpoints, plus shared dark and bone ramps; no
     dither, so the pixels stay crisp;
  3. our frame is drawn over it by this script: buff = ember gold (the bar's #b8923a outer line, a lit gold bevel, a
     hot spot on top, ember studs), debuff = blood red with thorns in the corners. Keystones and masteries get no
     frame: the tree draws its node frame over them.
Outputs:
  overlay/data/images/game/buffs_painted/<name>.png       26 x 26 (the bar's cell, drawn 1:1). The class buffs that
      show a Chaos spell's icon (gen_buff_icons.SPELL_ICONS) use that spell's painted art in the buff frame.
  overlay/data/images/game/spells_painted/<clientId>.png  32 x 32 (the spellbook's icon size)
  overlay/data/images/passivetree/painted_nodes.png       64 x 64 cells, keystones then masteries
  overlay/modules/game_passivetree/treedata/painted.lua   icon key -> clip of painted_nodes.png
  The 21 line spell quest spells (client ids 349-369, gen_quest_spell_icons.py) are not in the sheet: their finished 32 px
      art (quest_spell_art/quest_spell_32.png, centre 28 x 28, no repaint, no palette clamp) goes straight into our buff
      frame as spells_painted/<id>.png, and the 7 level 800 buffs as buffs_painted/<name>.png (box-reduced to 22 px).
      The same for the class spells repainted in O355 (class_spell_art/class_spell_32.png, the Necromancer line's
      cells 294-337): no painted cell existed for them, so the painted setting showed their plain drawings.
A name with no painted icon keeps its normal icon in the client (each module falls back). Needs Pillow."""
import csv, io, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from PIL import Image, ImageFilter  # noqa: E402
import gen_buff_icons as gb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(HERE, 'painted_icon_art')
SHEET = os.path.join(ART, 'painted_64.png')
CSV = os.path.join(ART, 'painted_icons.csv')
IMAGES = os.path.join(ROOT, 'client', 'overlay', 'data', 'images')
BUFF_DIR = os.path.join(IMAGES, 'game', 'buffs_painted')
SPELL_DIR = os.path.join(IMAGES, 'game', 'spells_painted')
NODES = os.path.join(IMAGES, 'passivetree', 'painted_nodes.png')
NODES_LUA = os.path.join(ROOT, 'client', 'overlay', 'modules', 'game_passivetree', 'treedata', 'painted.lua')
SPELLDATA = gb.SPELLDATA
CELL, COLS = 64, 16
QUEST_SRC = os.path.join(HERE, 'quest_spell_art', 'quest_spell_32.png')
QUEST_CSV = os.path.join(HERE, 'quest_spell_art', 'quest_spell_icons.csv')
CLASS_SRC = os.path.join(HERE, 'class_spell_art', 'class_spell_32.png')
CLASS_CSV = os.path.join(HERE, 'class_spell_art', 'class_spell_icons.csv')
FIELDS = ['index', 'kind', 'name', 'frame', 'element', 'job', 'seed']

# ---------------------------------------------------------------- palettes, one per element
R = gb.R
ELEMENT_RAMPS = {
    'fire': ['ember', 'gold'], 'blood': ['blood', 'ember'], 'holy': ['holy', 'gold'], 'nature': ['nature', 'poison'],
    'frost': ['frost', 'water'], 'arcane': ['arcane', 'energy', 'shadow'], 'steel': ['steel', 'gold'],
    'mixed': ['ember', 'gold', 'blood', 'holy', 'nature', 'poison', 'frost', 'water', 'arcane', 'energy'],
}
SHARED_RAMPS = ['coal', 'obsidian', 'bone', 'wood', 'steel']
ELEMENTS = sorted(ELEMENT_RAMPS)


def ramp9(r):
    """a 5-shade ramp with its midpoints, and a near-black below it"""
    out = [gb.mix((6, 4, 8), r[0], 0.5)]
    for i in range(4):
        out += [r[i], gb.mix(r[i], r[i + 1], 0.5)]
    return out + [r[4]]


def palette(element):
    cols = []
    for name in ELEMENT_RAMPS[element] + SHARED_RAMPS:
        for c in ramp9(R[name]):
            if c not in cols:
                cols.append(c)
    return cols


def palette_image(cols):
    p = Image.new('P', (1, 1))
    flat = []
    for c in cols:
        flat += list(c)
    flat += list(cols[0]) * (256 - len(cols))
    p.putpalette(flat)
    return p


def clamp(im, element):
    rgb = im.convert('RGB').quantize(palette=palette_image(palette(element)), dither=Image.Dither.NONE).convert('RGB')
    out = rgb.convert('RGBA')
    out.putalpha(im.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
    return out


# ---------------------------------------------------------------- our frame (any size)
FRAME = gb.FRAME


def frame(im, kind):
    """the buff bar's frame, drawn for any size: 1 px outer line, a lit top-left / shaded bottom-right bevel; buff: a
    hot spot on top and ember studs; debuff: veins and corner thorns"""
    f = FRAME[kind]
    N = im.width
    p = im.load()
    for i in range(N):
        for (x, y) in ((i, 0), (i, N - 1), (0, i), (N - 1, i)):
            p[x, y] = f['outer'] + (255,)
    for i in range(1, N - 1):
        p[i, 1] = f['lit'] + (255,)
        p[1, i] = f['lit'] + (255,)
        p[i, N - 2] = f['shade'] + (255,)
        p[N - 2, i] = f['shade'] + (255,)
    for c in ((0, 0), (N - 1, 0), (0, N - 1), (N - 1, N - 1)):
        p[c] = (0, 0, 0, 0)
    for i in range(2, N - 2):   # the frame's shadow on the art
        for (x, y) in ((i, 2), (2, i)):
            r, g, b, a = p[x, y]
            p[x, y] = (r * 11 // 20, g * 11 // 20, b * 11 // 20, a)
    if kind == 'buff':
        h = max(3, N * 6 // 26)
        x0 = (N - h) // 2
        for x in range(x0, x0 + h):
            p[x, 1] = f['hot'] + (255,)
        p[x0 - 1, 1] = p[x0 + h, 1] = gb.mix(f['hot'], f['lit'], 0.5) + (255,)
        for (x, y) in ((1, 1), (N - 2, 1), (1, N - 2), (N - 2, N - 2)):
            p[x, y] = f['stud'] + (255,)
        p[2, 2] = gb.mix(f['stud'], (0, 0, 0), 0.35) + (255,)
    else:
        s = N / 26.0
        for (x, y) in ((6, 1), (7, 1), (1, 17), (1, 18), (19, 24), (24, 8), (24, 9), (12, 24)):
            xx = min(N - 2, max(1, int(round(x * s)))) if x not in (1, 24) else (1 if x == 1 else N - 2)
            yy = min(N - 2, max(1, int(round(y * s)))) if y not in (1, 24) else (1 if y == 1 else N - 2)
            p[xx, yy] = f['hot'] + (255,)
        for (cx, cy, sx, sy) in ((2, 2, 1, 1), (N - 3, 2, -1, 1), (2, N - 3, 1, -1), (N - 3, N - 3, -1, -1)):
            for (dx, dy) in ((0, 0), (1, 0), (0, 1), (1, 1), (2, 0), (0, 2)):
                p[cx + sx * dx, cy + sy * dy] = (f['outer'] if dx + dy < 2 else f['lit']) + (255,)
            p[cx + sx * 2, cy + sy * 2] = f['hot'] + (255,)
    return im


# ---------------------------------------------------------------- building
def read_csv(path=CSV):
    with open(path, newline='', encoding='utf-8') as fh:
        rows = list(csv.DictReader(fh))
    for i, r in enumerate(rows):
        if int(r['index']) != i:
            raise SystemExit('painted_icons.csv: row %d has index %s' % (i, r['index']))
        if r['element'] not in ELEMENT_RAMPS:
            raise SystemExit('painted_icons.csv: %s has an unknown element %s' % (r['name'], r['element']))
        if r['frame'] not in ('buff', 'debuff', 'none'):
            raise SystemExit('painted_icons.csv: %s has an unknown frame %s' % (r['name'], r['frame']))
    return rows


def cell_of(sheet, i):
    return sheet.crop(((i % COLS) * CELL, (i // COLS) * CELL, (i % COLS) * CELL + CELL, (i // COLS) * CELL + CELL))


def painted(cell, size, element):
    """the painted cell at `size` px: scaled, sharpened, clamped to the element's palette"""
    im = cell.convert('RGBA').resize((size, size), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
    return clamp(im, element)


def framed(cell, size, kind, element):
    """the art in the inner (size - 4) px, our frame around it"""
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    art = painted(cell, size - 4, element)
    im.paste(art, (2, 2))
    return frame(im, kind)


def quest_art():
    """client id -> the centre 28 x 28 of the spell's finished 32 px art (gen_quest_spell_icons.py: the quest spells and
    the repainted class spells of class_spell_art/)"""
    ids = set(spell_ids().values())
    out = {}
    for src_path, csv_path in ((QUEST_SRC, QUEST_CSV), (CLASS_SRC, CLASS_CSV)):
        with open(csv_path, newline='', encoding='utf-8') as fh:
            rows = list(csv.DictReader(fh))
        src = Image.open(src_path).convert('RGBA')
        for i, r in enumerate(rows):
            cid = int(r['cell'])
            if cid not in ids:
                raise SystemExit('spell %s: no Chaos spell with client id %d' % (r['spell'], cid))
            if cid in out:
                raise SystemExit('spell %s: client id %d has art twice' % (r['spell'], cid))
            x, y = (i % 7) * 32, (i // 7) * 32
            out[cid] = src.crop((x + 2, y + 2, x + 30, y + 30))
    return out


def quest_framed(art, size):
    """the quest art as drawn (no repaint, no palette clamp: it is finished pixel art) in the buff frame; below 32 px
    the 28 x 28 art is box-reduced like gen_buff_icons.from_spell"""
    inner = size - 4
    if inner != art.width:
        art = art.resize((inner, inner), Image.BOX)
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    im.paste(art, (2, 2))
    return frame(im, 'buff')


def spell_ids():
    """the spell's words -> its client id (game_chaosspells/spelldata.lua)"""
    return gb.spell_cells()


def build(sheet=None, rows=None):
    """every output as {relative path: PIL image or text}"""
    sheet = sheet or Image.open(SHEET).convert('RGBA')
    rows = rows or read_csv()
    out = {}
    spells = {}
    nodes = []
    for r in rows:
        cell = cell_of(sheet, int(r['index']))
        if r['kind'] == 'buff':
            out[os.path.join(BUFF_DIR, r['name'] + '.png')] = framed(cell, gb.N, r['frame'], r['element'])
        elif r['kind'] == 'spell':
            spells[int(r['name'])] = (cell, r['element'])
            out[os.path.join(SPELL_DIR, r['name'] + '.png')] = framed(cell, 32, 'buff', r['element'])
        elif r['kind'] in ('keystone', 'mastery'):
            nodes.append((r['name'], painted(cell, CELL, r['element'])))
        else:
            raise SystemExit('painted_icons.csv: unknown kind %s' % r['kind'])
    quest = quest_art()
    for cid, art in sorted(quest.items()):
        out[os.path.join(SPELL_DIR, '%d.png' % cid)] = quest_framed(art, 32)
    ids = spell_ids()
    for name, words in sorted(gb.SPELL_ICONS.items()):
        cid = ids.get(words)
        if cid in quest:
            out[os.path.join(BUFF_DIR, name + '.png')] = quest_framed(quest[cid], gb.N)
        elif cid in spells:
            cell, element = spells[cid]
            out[os.path.join(BUFF_DIR, name + '.png')] = framed(cell, gb.N, 'buff', element)
    if nodes:
        im = Image.new('RGBA', (CELL * len(nodes), CELL), (0, 0, 0, 0))
        lines = ['-- GENERATED by client/tools/gen_painted_icons.py. Do not edit.',
                 '-- The passive tree\'s painted keystone and mastery icons (client setting "Painted icons"): icon key ->',
                 '-- its 64 x 64 cell of /images/passivetree/painted_nodes.png.',
                 'function getPaintedTreeIcons()', '\treturn {']
        for i, (name, art) in enumerate(nodes):
            im.paste(art, (i * CELL, 0))
            lines.append('\t\t%s = {file = "/images/passivetree/painted_nodes", x = %d, y = 0, w = %d, h = %d},'
                         % (name, i * CELL, CELL, CELL))
        lines += ['\t}', 'end', '']
        out[NODES] = im
        out[NODES_LUA] = '\n'.join(lines)
    return out


def same(path, want):
    if not os.path.exists(path):
        return False
    if isinstance(want, str):
        with open(path, encoding='utf-8') as fh:
            return fh.read() == want
    have = Image.open(path).convert('RGBA')
    return have.size == want.size and have.tobytes() == want.convert('RGBA').tobytes()


def check():
    rows = read_csv()
    errors = []
    buffs = os.path.join(IMAGES, 'game', 'buffs')
    ids = set(spell_ids().values())
    for r in rows:   # every painted icon still names a live icon
        if r['kind'] == 'buff' and not os.path.exists(os.path.join(buffs, r['name'] + '.png')):
            errors.append('buff %s: no icon of that name in images/game/buffs' % r['name'])
        if r['kind'] == 'spell' and int(r['name']) not in ids:
            errors.append('spell %s: no Chaos spell with that client id' % r['name'])
    out = build(rows=rows)
    for path, want in sorted(out.items()):
        if not same(path, want):
            errors.append('%s is not up to date (run client/tools/gen_painted_icons.py)' % os.path.relpath(path, ROOT))
    for d in (BUFF_DIR, SPELL_DIR):
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if os.path.join(d, f) not in out:
                errors.append('%s: no source row (stale file)' % os.path.relpath(os.path.join(d, f), ROOT))
    for e in errors:
        print(e)
    print('%d painted icons checked, %d outputs, %d errors' % (len(rows), len(out), len(errors)))
    return 1 if errors else 0


def write():
    out = build()
    for path, want in out.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if isinstance(want, str):
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(want)
        else:
            want.save(path, optimize=True)
    print(len(out), 'painted outputs written')
    return 0


def contact_sheet(path, scale=3):
    from PIL import ImageDraw
    out = build()
    items = [(os.path.basename(p)[:-4], im) for p, im in sorted(out.items()) if not isinstance(im, str) and p != NODES]
    nodes = out.get(NODES)
    if nodes:
        for i in range(nodes.width // CELL):
            items.append(('node%d' % i, nodes.crop((i * CELL, 0, i * CELL + CELL, CELL)).resize((32, 32), Image.LANCZOS)))
    cols, cw = 12, 32 * scale + 24
    ch = 32 * scale + 18
    im = Image.new('RGB', (cols * cw + 16, ((len(items) + cols - 1) // cols) * ch + 16), (22, 18, 20))
    d = ImageDraw.Draw(im)
    for i, (n, ic) in enumerate(items):
        x, y = 8 + (i % cols) * cw, 8 + (i // cols) * ch
        big = ic.resize((ic.width * scale, ic.height * scale), Image.NEAREST)
        im.paste(big, (x + (cw - big.width) // 2, y), big)
        d.text((x + 2, y + 32 * scale + 3), n[:16], fill=(240, 222, 180))
    im.save(path)


# ---------------------------------------------------------------- pack (raw results -> source sheet), not used by CI
def classify(im):
    """the element of a painted cell from its saturated hues (only at pack time; the csv then fixes it)"""
    import colorsys
    w = {}
    raw = im.convert('RGBA').tobytes()
    for r, g, b, a in zip(raw[0::4], raw[1::4], raw[2::4], raw[3::4]):
        if a < 128:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.4 or v < 0.3:
            continue
        deg = h * 360
        e = ('blood' if deg < 18 or deg >= 335 else 'fire' if deg < 40 else 'holy' if deg < 62 else 'nature' if deg < 160
             else 'frost' if deg < 245 else 'arcane')
        w[e] = w.get(e, 0) + s * v
    if not w or sum(w.values()) < 60:
        return 'steel'
    order = sorted(w.items(), key=lambda t: (-t[1], t[0]))
    if len(order) > 1 and order[1][1] > 0.5 * order[0][1] and {order[0][0], order[1][0]} not in (
            {'fire', 'holy'}, {'fire', 'blood'}, {'nature', 'holy'}, {'frost', 'arcane'}):
        return 'mixed'
    return order[0][0]


def pack(raw_dir, jobs, debuffs):
    import json, base64
    cells = []
    for job in jobs:
        res = json.load(open(os.path.join(raw_dir, job + '.json')))
        meta = json.load(open(os.path.join(raw_dir, job + '.meta.json')))
        images = res['last_response']['images']
        assert len(images) == len(meta['items']), job
        for (kind, name), o in zip(meta['items'], images):
            s = o['base64'] if isinstance(o, dict) else o
            im = Image.open(io.BytesIO(base64.b64decode(s.split(',', 1)[-1]))).convert('RGBA')
            cells.append((kind, name, im, job, meta['seed']))
    order = {'buff': 0, 'spell': 1, 'keystone': 2, 'mastery': 3}
    cells.sort(key=lambda c: (order[c[0]], int(c[1]) if c[0] == 'spell' else 0, c[1] if c[0] != 'keystone' else ''))
    if any(c[0] == 'keystone' for c in cells):   # keystones in the order of gen_keystone_icons.KEYSTONES
        import gen_keystone_icons as gk
        ko = {k: i for i, (k, _) in enumerate(gk.KEYSTONES)}
        cells.sort(key=lambda c: (order[c[0]], int(c[1]) if c[0] == 'spell' else ko.get(c[1], 0) if c[0] == 'keystone'
                                  else c[1]))
    sheet = Image.new('RGBA', (COLS * CELL, ((len(cells) + COLS - 1) // COLS) * CELL), (0, 0, 0, 0))
    rows = []
    for i, (kind, name, im, job, seed) in enumerate(cells):
        sheet.paste(im, ((i % COLS) * CELL, (i // COLS) * CELL))
        fr = 'none' if kind in ('keystone', 'mastery') else 'debuff' if (kind == 'buff' and name in debuffs) else 'buff'
        rows.append({'index': i, 'kind': kind, 'name': name, 'frame': fr, 'element': classify(im), 'job': job,
                     'seed': seed})
    os.makedirs(ART, exist_ok=True)
    sheet.save(SHEET, optimize=True)
    with open(CSV, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, FIELDS, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)
    print(len(rows), 'cells packed into', SHEET)


def current_debuffs():
    """the buff icons drawn with the debuff frame now (their outer line is the debuff red)"""
    d = os.path.join(IMAGES, 'game', 'buffs')
    out = set()
    for f in os.listdir(d):
        if f.endswith('.png') and Image.open(os.path.join(d, f)).convert('RGB').getpixel((5, 0)) == FRAME['debuff']['outer']:
            out.add(f[:-4])
    return out


def main(argv):
    if argv[:1] == ['--check']:
        return check()
    if argv[:1] == ['--sheet']:
        scale = int(argv[argv.index('--scale') + 1]) if '--scale' in argv else 3
        contact_sheet(argv[1], scale)
        return 0
    if argv[:1] == ['pack']:
        raw = argv[argv.index('--raw') + 1]
        jobs = argv[argv.index('--jobs') + 1].split(',')
        pack(raw, jobs, current_debuffs())
        return 0
    return write()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

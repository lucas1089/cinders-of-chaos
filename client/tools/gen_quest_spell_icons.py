#!/usr/bin/env python3
"""PixelLab art in the Chaos frame: the 21 line spell quest spells (cells 349-369 of the three spell icon sheets) and
the class spells repainted from plain drawings (class_spell_art/, O355: the Necromancer line).

Run: python3 -I client/tools/gen_quest_spell_icons.py            # build: art sheet cells and the three client sheets
     python3 -I client/tools/gen_quest_spell_icons.py --check    # the committed files match the source (CI)
     python3 -I client/tools/gen_quest_spell_icons.py --sheet OUT.png [--scale 4]   # labelled contact sheet
     python3 -I client/tools/gen_quest_spell_icons.py pack --raw DIR [--set quest|class]   # raw results -> source sheet

Source (committed, our own art): quest_spell_art/quest_spell_32.png, 7 columns x 3 rows of 32 x 32 cells in the order of
quest_spell_art/quest_spell_icons.csv (cell, spell, frame, job, candidate): row 1 the level 500 attacks (cells 349-355),
row 2 the level 1200 ultimates (356-362), row 3 the level 800 buffs (363-369). Each cell is one candidate of a PixelLab
"Create Image (Pro)" call at 32 x 32 (64 candidates per call, one call per spell, a description of the spell and no
other image); the csv names the call and the candidate. The raw results stay outside git.
Second source (O355, 2026-10-31): class_spell_art/class_spell_32.png, 7 columns of 32 x 32 cells in the order of
class_spell_art/class_spell_icons.csv (same columns; any Chaos spell cells outside 349-369, each once). The plain
drawings of gen_spell_icons.py there (the Necromancer line: summons, pack spells and attack kit, cells 294-337) looked
flat next to the painted cells; each is now one candidate of the same kind of call (a description of the spell).

Build, deterministic (the same sheet gives the same files):
  1. the art is the cell's centre 28 x 28 (a 2 px margin cut off, no resampling, so the pixels stay crisp);
  2. the frame is copied from the Chaos spell cells 201-279 of spell_icon_art/spell_icons_32.png: the first cell of the
     csv's frame colour (grey, orange, purple, red, green, cyan) lends its 2 px ring, the stud and the cut corners;
  3. 32 x 32 is that framed icon; 22 x 24 and 20 x 20 are redrawn from the inner art with a crisp 1 px frame
     (gen_all_spell_icons.art_small, the same step the other art cells take).
Outputs: spell_icon_art/spell_icons_32.png (the art sheet, the cells of both sources added; gen_all_spell_icons.py and
gen_buff_icons.py read it), overlay/data/images/game/spells/spell-icons-{32x32,22x24,20x20}.png (only those cells change;
the sheets need the base client's spells.lua to be drawn from scratch, so these cells are pasted). The buff bar icons
of the seven buffs come from gen_buff_icons.py (their spell's cell of the art sheet). build_spell_icon_art.py writes the
art sheet from scratch without these cells: run this tool after it. gen_painted_icons.py puts the same art into
spells_painted/. Needs Pillow."""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from PIL import Image, ImageDraw  # noqa: E402
import gen_all_spell_icons as ga  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
SRC_DIR = os.path.join(HERE, 'quest_spell_art')
SRC = os.path.join(SRC_DIR, 'quest_spell_32.png')
CSV = os.path.join(SRC_DIR, 'quest_spell_icons.csv')
CLASS_DIR = os.path.join(HERE, 'class_spell_art')
CLASS_SRC = os.path.join(CLASS_DIR, 'class_spell_32.png')
CLASS_CSV = os.path.join(CLASS_DIR, 'class_spell_icons.csv')
SETS = {'quest': (SRC, CSV), 'class': (CLASS_SRC, CLASS_CSV)}   # source sheet, csv
ART = os.path.join(HERE, 'spell_icon_art', 'spell_icons_32.png')
SHEET_DIR = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'spells')
FIRST, COUNT, COLS, ROWS = 349, 21, 20, 19
# frame colour name -> the outer ring colour of the Chaos spell frames
FRAMES = {'grey': (135, 135, 135), 'orange': (253, 116, 3), 'purple': (98, 36, 97), 'red': (138, 15, 30),
          'green': (39, 155, 67), 'cyan': (0, 155, 234)}


def read_csv(path=CSV):
    with open(path, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    cells = [int(r['cell']) for r in rows]
    if path == CSV and cells != list(range(FIRST, FIRST + COUNT)):
        raise SystemExit('%s: cells must be %d..%d in order' % (CSV, FIRST, FIRST + COUNT - 1))
    if path != CSV:
        if len(set(cells)) != len(cells) or any(FIRST <= n < FIRST + COUNT or not 201 <= n <= ROWS * COLS
                                                for n in cells):
            raise SystemExit('%s: each cell once, a Chaos cell (201-%d) outside %d..%d'
                             % (path, ROWS * COLS, FIRST, FIRST + COUNT - 1))
    for r in rows:
        if r['frame'] not in FRAMES:
            raise SystemExit('%s: unknown frame %s' % (r['spell'], r['frame']))
    return rows


def source_cells():
    """[(cell, csv row, 32 x 32 art)] of both source sheets"""
    out = []
    for src, path in SETS.values():
        if path != CSV and not os.path.exists(path):
            continue
        sheet = Image.open(src).convert('RGBA')
        for i, r in enumerate(read_csv(path)):
            x, y = (i % 7) * 32, (i // 7) * 32
            out.append((int(r['cell']), r, sheet.crop((x, y, x + 32, y + 32))))
    return out


def cell_of(sheet, n):
    x, y = ((n - 1) % COLS) * 32, ((n - 1) // COLS) * 32
    return sheet.crop((x, y, x + 32, y + 32))


def templates(art):
    """frame colour name -> the first Chaos spell cell (201-279) with that outer ring colour"""
    out = {}
    for n in range(201, 280):
        c = cell_of(art, n)
        for name, rgb in FRAMES.items():
            if name not in out and c.getpixel((1, 0))[:3] == rgb:
                out[name] = c
    if set(out) != set(FRAMES):
        raise SystemExit('no Chaos spell cell for the frames %s' % sorted(set(FRAMES) - set(out)))
    return out


def framed(art32, template):
    """the 28 x 28 centre of a 32 x 32 art cell inside the template's frame (its 2 px ring kept)"""
    out = template.copy()
    out.paste(art32.convert('RGBA').crop((2, 2, 30, 30)), (2, 2))
    return out


def build_icons(art=None):
    """cell -> {(w, h): RGBA icon}, the icons of both sources at the three sizes"""
    art = art or Image.open(ART).convert('RGBA')
    tpl = templates(art)
    out = {}
    for n, r, cell in source_cells():
        icon = framed(cell, tpl[r['frame']])
        out[n] = {(w, h): icon if (w, h) == (32, 32) else ga.art_small(icon, w, h) for _, w, h, _, _ in ga.SHEETS}
    return out


def paste(sheet, icons, size, mode):
    """a sheet image (RGBA or RGB) with the built cells replaced"""
    w, h = size
    sheet = sheet.convert('RGBA')
    if sheet.height < ROWS * h:
        grown = Image.new('RGBA', (sheet.width, ROWS * h), (0, 0, 0, 0))
        grown.paste(sheet, (0, 0))
        sheet = grown
    for n, smalls in icons.items():
        x, y = ((n - 1) % COLS) * w, ((n - 1) // COLS) * h
        sheet.paste(Image.new('RGBA', (w, h), (0, 0, 0, 0)), (x, y))
        sheet.alpha_composite(smalls[size], (x, y))
    if mode == 'RGB':
        base = Image.new('RGBA', sheet.size, (0, 0, 0, 255))
        base.alpha_composite(sheet)
        return base.convert('RGB')
    return sheet


def targets(icons):
    """path -> the image that file must hold: the art sheet and the three client sheets"""
    out = {ART: paste(Image.open(ART), icons, (32, 32), 'RGBA')}
    for suffix, w, h, mode, _ in ga.SHEETS:
        path = os.path.join(SHEET_DIR, 'spell-icons-%s.png' % suffix)
        out[path] = paste(Image.open(path), icons, (w, h), mode)
    return out


def same_cells(path, want, icons, size):
    """the built cells of the file equal the built ones (the rest of the sheet is not this tool's)"""
    have = Image.open(path).convert('RGBA')
    w, h = size
    for n in icons:
        box = (((n - 1) % COLS) * w, ((n - 1) // COLS) * h)
        if have.size[1] < box[1] + h:
            return False
        a = have.crop((box[0], box[1], box[0] + w, box[1] + h))
        b = want.convert('RGBA').crop((box[0], box[1], box[0] + w, box[1] + h))
        if a.tobytes() != b.tobytes():
            return False
    return True


def check():
    icons = build_icons()
    bad = []
    for path, want in targets(icons).items():
        size = (32, 32) if path == ART else next((w, h) for s, w, h, _, _ in ga.SHEETS if path.endswith('-%s.png' % s))
        if not same_cells(path, want, icons, size):
            bad.append(os.path.relpath(path, ROOT))
    if bad:
        raise SystemExit('quest spell icons out of date (run client/tools/gen_quest_spell_icons.py): ' + ', '.join(bad))
    print('quest and class spell icons: %d cells in 4 files match' % len(icons))


def write():
    icons = build_icons()
    for path, im in targets(icons).items():
        im.save(path, optimize=True)
    print('quest and class spell icons: %d cells written to the art sheet and 3 client sheets' % len(icons))


def contact_sheet(path, scale=4):
    cells = source_cells()
    icons = build_icons()
    cw, ch = 32 * scale + 12, 32 * scale + 34
    im = Image.new('RGB', (7 * cw + 12, ((len(cells) + 6) // 7) * ch + 12), (24, 20, 26))
    d = ImageDraw.Draw(im)
    for i, (n, r, _) in enumerate(cells):
        x, y = 12 + (i % 7) * cw, 12 + (i // 7) * ch
        big = icons[n][(32, 32)].resize((32 * scale, 32 * scale), Image.NEAREST)
        im.paste(big, (x, y), big)
        for k, (w, h) in enumerate(((32, 32), (22, 24), (20, 20))):
            s = icons[n][(w, h)]
            im.paste(s, (x + k * 38, y + 32 * scale + 4), s)
        d.text((x, y + 32 * scale + 4 + 26), str(n) + ' ' + r['spell'][:18], fill=(220, 210, 225))
    im.save(path)


def pack(raw, names=None):
    """the source sheets from the raw call results: DIR/<job>/<candidate:02d>.png (32 x 32, kept outside git)"""
    for name in names or sorted(SETS):
        src, path = SETS[name]
        rows = read_csv(path)
        sheet = Image.new('RGBA', (7 * 32, ((len(rows) + 6) // 7) * 32), (0, 0, 0, 0))
        for i, r in enumerate(rows):
            im = Image.open(os.path.join(raw, r['job'], '%02d.png' % int(r['candidate']))).convert('RGBA')
            if im.size != (32, 32):
                raise SystemExit('%s: candidate is %dx%d, not 32x32' % (r['spell'], im.width, im.height))
            sheet.paste(im, ((i % 7) * 32, (i // 7) * 32))
        sheet.save(src, optimize=True)
        print('source sheet written:', os.path.relpath(src, ROOT))


def main(argv):
    if argv[:1] == ['pack']:
        names = [argv[argv.index('--set') + 1]] if '--set' in argv else None
        pack(argv[argv.index('--raw') + 1], names)
    elif '--check' in argv:
        check()
    elif '--sheet' in argv:
        i = argv.index('--sheet')
        scale = int(argv[argv.index('--scale') + 1]) if '--scale' in argv else 4
        contact_sheet(argv[i + 1], scale)
    else:
        write()


if __name__ == '__main__':
    main(sys.argv[1:])

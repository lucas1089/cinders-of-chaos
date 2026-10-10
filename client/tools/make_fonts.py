#!/usr/bin/env python3
"""Turn a TTF/OTF font into OTClient bitmap fonts: one glyph sheet (.png) and one definition (.otfont) per size.

usage:
  python3 -I client/tools/make_fonts.py FONT.ttf --name fontin --sizes 14,16,20 --out DIR
          [--outline 1] [--outline-color 0,0,0,200] [--shadow 1,1] [--shadow-color 0,0,0,160]
          [--first 32] [--last 126] [--encoding cp1252] [--tracking 0]
  python3 -I client/tools/make_fonts.py --atlas-check CLIENT_DATA_FONTS_DIR [EXTRA_DIR ...]

Glyphs are white (the client tints a font with the widget's colour), with an optional dark outline and a baked drop
shadow. The client reads a glyph's width from its sheet (the last column with any pixel, BitmapFont::
calculateGlyphsWidthsAutomatically) and puts the next glyph right after it, so each glyph is drawn at the left of its
cell and its advance width is marked with one pixel of alpha 1 (invisible) in the top row: the spacing then follows
the font's own metrics. Glyphs first..last are byte values in `encoding` (the client draws bytes, cp1252 / Latin-1);
the default 32..126 keeps a sheet small (see the atlas below). Names: <name>-<size>px, files <name>-<size>px.png/.otfont.

The font atlas: the client copies every bitmap font into ONE 2048x2048 texture when it loads it (Atlas::cacheFont,
built without BIG_FONTS). Each sheet takes a power-of-two square slot of max(width, height) (32 .. 2048, a buddy
allocator) and the client stops with "[Atlas] Out of space for new fonts" (fatal) when none is left. --atlas-check
replays that allocator over the .otfont files of the given folders in load order (client_styles imports data/fonts
recursively, sorted) and prints the slots, what is left and whether everything fits; exit 1 when it does not. The
sheet layout here picks the column count that gives the smallest slot. Needs Pillow."""
import argparse, math, os, re, sys

SLOTS = [32, 64, 128, 256, 512, 1024, 2048]
ATLAS = 2048


# ---------------------------------------------------------------- pure parts (make_fonts_test.py)
def slot_size(width, height):
    """the atlas slot of a sheet: the smallest power-of-two square (32..2048) that holds it, None when too big"""
    s = max(width, height)
    for slot in SLOTS:
        if s <= slot:
            return slot
    return None


def layout(count, cell_w, cell_h, max_side=ATLAS):
    """columns for `count` cells of cell_w x cell_h: the smallest atlas slot, then the smallest area, then the widest.
    Returns (columns, rows, width, height, slot)."""
    best = None
    for cols in range(1, count + 1):
        rows = -(-count // cols)
        w, h = cols * cell_w, rows * cell_h
        slot = slot_size(w, h)
        if slot is None or w > max_side or h > max_side:
            continue
        key = (slot, w * h, -cols)
        if best is None or key < best[0]:
            best = (key, (cols, rows, w, h, slot))
    if best is None:
        raise ValueError('glyphs do not fit a 2048 x 2048 sheet')
    return best[1]


def glyph_chars(first, last, encoding='cp1252'):
    """[(byte, character)] for the bytes first..last; bytes the encoding leaves undefined give None"""
    out = []
    for b in range(first, last + 1):
        try:
            ch = bytes([b]).decode(encoding)
        except UnicodeDecodeError:
            ch = None
        out.append((b, ch))
    return out


def otfont_text(name, texture, height, cell_w, cell_h, space_width, first=32, y_offset=0, spacing=(0, 0)):
    return ('Font\n'
            '  name: %s\n'
            '  texture: %s\n'
            '  height: %d\n'
            '  glyph-size: %d %d\n'
            '  first-glyph: %d\n'
            '  y-offset: %d\n'
            '  spacing: %d %d\n'
            '  space-width: %d\n') % (name, texture, height, cell_w, cell_h, first, y_offset, spacing[0], spacing[1],
                                       space_width)


def parse_otfont(text):
    """{name, texture, glyph-size} of an .otfont (enough for the atlas check)"""
    out = {}
    for key in ('name', 'texture'):
        m = re.search(r'^\s*%s:\s*(.+?)\s*$' % key, text, re.M)
        out[key] = m.group(1) if m else None
    return out


class Atlas:
    """the client's font atlas (framework/graphics/atlas.cpp, location 1): a buddy allocator over one 2048 square"""

    def __init__(self, size=ATLAS):
        self.free = {s: [] for s in SLOTS}
        self.free[size] = [(0, 0)]
        self.used = []

    def _split(self, slot):
        i = SLOTS.index(slot)
        if i + 1 >= len(SLOTS):
            return False
        big = SLOTS[i + 1]
        if not self.free[big] and not self._split(big):
            return False
        x, y = self.free[big].pop(0)
        self.free[slot] += [(x, y), (x, y + slot), (x + slot, y), (x + slot, y + slot)]
        return True

    def place(self, width, height, label=''):
        slot = slot_size(width, height)
        if slot is None:
            return None
        if not self.free[slot] and not self._split(slot):
            return None
        pos = self.free[slot].pop(0)
        self.used.append((label, slot, pos))
        return pos

    def free_area(self):
        return sum(s * s * len(v) for s, v in self.free.items())


def load_order(folders):
    """the .otfont files of the folders in the order client_styles imports them (recursive, sorted, files and folders
    mixed)"""
    out = []

    def walk(d):
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n)
            if os.path.isdir(p):
                walk(p)
            elif n.endswith('.otfont'):
                out.append(p)
    for f in folders:
        if os.path.isdir(f):
            walk(f)
    return out


def texture_path(otfont_path, texture):
    t = texture if texture.endswith('.png') else texture + '.png'
    if t.startswith('/'):
        return None  # absolute resource path: not resolvable here
    return os.path.join(os.path.dirname(otfont_path), t)


# ---------------------------------------------------------------- rendering (Pillow)
def parse_rgba(text):
    parts = [int(x) for x in str(text).split(',')]
    while len(parts) < 4:
        parts.append(255)
    return tuple(parts[:4])


def render(font_file, size, name, out_dir, first=32, last=126, encoding='cp1252', outline=0,
           outline_color=(0, 0, 0, 200), shadow=(0, 0), shadow_color=(0, 0, 0, 160), tracking=0):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(font_file, size)
    ascent, descent = font.getmetrics()
    pad_l = outline + max(0, -shadow[0])
    pad_r = outline + max(0, shadow[0])
    pad_t = outline + max(0, -shadow[1])
    pad_b = outline + max(0, shadow[1])
    chars = glyph_chars(first, last, encoding)
    metrics = {}
    cell_w = 1
    for b, ch in chars:
        if not ch or not ch.isprintable():
            continue
        l, t, r, bt = font.getbbox(ch)
        adv = int(round(font.getlength(ch))) + tracking
        shift = max(0, -l)  # a glyph that starts left of its origin is moved right by that much
        ink_w = max(r + shift, adv + shift)
        metrics[b] = (shift, pad_l + shift + adv + outline, ink_w)  # spacing -outline in the .otfont
        cell_w = max(cell_w, pad_l + ink_w + pad_r)
    height = ascent + descent + pad_t + pad_b
    cell_h = height
    cols, rows, w, h, slot = layout(len(chars), cell_w, cell_h)
    sheet = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for i, (b, ch) in enumerate(chars):
        if b not in metrics:
            continue
        shift, adv, _ = metrics[b]
        cx, cy = (i % cols) * cell_w, (i // cols) * cell_h
        glyph = Image.new('RGBA', (cell_w, cell_h), (0, 0, 0, 0))
        mask = Image.new('L', (cell_w, cell_h), 0)
        ImageDraw.Draw(mask).text((pad_l + shift, pad_t), ch, font=font, fill=255)
        if shadow != (0, 0):
            sh = Image.new('L', (cell_w, cell_h), 0)
            sh.paste(mask, (shadow[0], shadow[1]))
            if outline:
                sh = _dilate(sh, outline)
            glyph.paste(Image.new('RGBA', (cell_w, cell_h), shadow_color), (0, 0), sh.point(lambda v: v * shadow_color[3] // 255))
        if outline:
            ring = _dilate(mask, outline)
            glyph = Image.alpha_composite(glyph, _colored(ring, outline_color))
        glyph = Image.alpha_composite(glyph, _colored(mask, (255, 255, 255, 255)))
        # the advance: one invisible pixel in the last column of the glyph's width
        px = glyph.load()
        x = min(cell_w - 1, max(1, adv) - 1)
        r_, g_, b_, a_ = px[x, 0]
        if a_ == 0:
            px[x, 0] = (255, 255, 255, 1)
        sheet.paste(glyph, (cx, cy))
    base = '%s-%dpx' % (name, size)
    os.makedirs(out_dir, exist_ok=True)
    sheet.save(os.path.join(out_dir, base + '.png'))
    space = int(round(font.getlength(' '))) + tracking + outline
    with open(os.path.join(out_dir, base + '.otfont'), 'w', encoding='utf-8') as f:
        f.write(otfont_text(base, base, height, cell_w, cell_h, max(1, space), first=first, spacing=(-outline, 0)))
    return {'name': base, 'size': (w, h), 'cell': (cell_w, cell_h), 'slot': slot, 'glyphs': len(metrics)}


def _dilate(mask, radius):
    from PIL import ImageFilter
    out = mask
    for _ in range(radius):
        out = out.filter(ImageFilter.MaxFilter(3))
    return out


def _colored(mask, rgba):
    from PIL import Image
    img = Image.new('RGBA', mask.size, rgba[:3] + (0,))
    img.putalpha(mask.point(lambda v: v * rgba[3] // 255))
    return img


# ---------------------------------------------------------------- atlas check
def atlas_check(folders, quiet=False):
    from PIL import Image
    atlas = Atlas()
    ok = True
    for p in load_order(folders):
        info = parse_otfont(open(p, encoding='latin-1').read())
        tex = texture_path(p, info['texture'] or '')
        if not tex or not os.path.exists(tex):
            if not quiet:
                print('  (no texture) %s' % p)
            continue
        w, h = Image.open(tex).size
        pos = atlas.place(w, h, info['name'])
        if not quiet:
            print('  %-44s %4dx%-4d slot %4d %s' % (info['name'], w, h, slot_size(w, h) or 0, 'OUT OF SPACE' if pos is None else ''))
        if pos is None:
            ok = False
    free = atlas.free_area()
    if quiet:
        return ok
    print('atlas: %d fonts, %.1f%% used, free %d px (= %d slots of 256x256)%s' % (
        len(atlas.used), 100.0 * (ATLAS * ATLAS - free) / (ATLAS * ATLAS), free, free // 65536,
        '' if ok else '  -> DOES NOT FIT: the client stops at start'))
    return ok


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('font', nargs='?')
    ap.add_argument('--name')
    ap.add_argument('--sizes', default='12')
    ap.add_argument('--out', default='.')
    ap.add_argument('--first', type=int, default=32)
    ap.add_argument('--last', type=int, default=126)
    ap.add_argument('--encoding', default='cp1252')
    ap.add_argument('--outline', type=int, default=0)
    ap.add_argument('--outline-color', default='0,0,0,200')
    ap.add_argument('--shadow', default='0,0')
    ap.add_argument('--shadow-color', default='0,0,0,160')
    ap.add_argument('--tracking', type=int, default=0)
    ap.add_argument('--atlas-check', nargs='+', metavar='DIR')
    a = ap.parse_args(argv)
    if a.atlas_check:
        return 0 if atlas_check(a.atlas_check) else 1
    if not a.font or not a.name:
        ap.error('FONT and --name are needed (or --atlas-check DIR)')
    shadow = tuple(int(x) for x in a.shadow.split(','))
    for size in [int(s) for s in a.sizes.split(',') if s.strip()]:
        r = render(a.font, size, a.name, a.out, a.first, a.last, a.encoding, a.outline, parse_rgba(a.outline_color),
                   shadow, parse_rgba(a.shadow_color), a.tracking)
        print('%s: %dx%d sheet, cell %dx%d, %d glyphs, atlas slot %d' % (r['name'], r['size'][0], r['size'][1],
              r['cell'][0], r['cell'][1], r['glyphs'], r['slot']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

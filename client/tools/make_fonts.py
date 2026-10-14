#!/usr/bin/env python3
"""Turn a TTF/OTF font into OTClient bitmap fonts: one glyph sheet (.png) and one definition (.otfont) per size.

usage:
  python3 -I client/tools/make_fonts.py FONT.ttf --name chaos-title --sizes 14,16,20 --out DIR
          [--outline 1] [--outline-color 0,0,0,200] [--shadow 1,1] [--shadow-color 0,0,0,160]
          [--first 32] [--last 255] [--encoding cp1252] [--tracking 0] [--weight 600]
          [--space-width 4] [--tight] [--border 1.2] [--border-color 0,0,0,230] [--max-cell-width 14]
          [--max-overhang 1]
  python3 -I client/tools/make_fonts.py --atlas-check CLIENT_DATA_FONTS_DIR [EXTRA_DIR ...]

Glyphs are white (the client tints a font with the widget's colour), with an optional dark outline and a baked drop
shadow. --outline N grows the glyph by N whole pixels (a square 3x3 step per pixel). --border R draws an antialiased
round border of R pixels (a fraction is fine, e.g. 1.2): the glyph's own antialiased mask is scaled up 4x, grown by a
disc of 4R and scaled back down with a box filter, so the ring has soft edges and round corners and stays aligned
with the hinted glyph. --max-cell-width squeezes the few glyphs wider than the cell (e.g. the per mille sign and the em dash)
horizontally to fit, so they do not decide the cell size of the whole sheet (and its atlas slot). The client reads a glyph's width from its sheet (the last column with any pixel, BitmapFont::
calculateGlyphsWidthsAutomatically) and puts the next glyph right after it, so each glyph is drawn at the left of its
cell and its advance width is marked with one pixel of alpha 1 (invisible) in the top row: the spacing then follows
the font's own metrics. The client also draws nothing right of that width, so a glyph cannot overhang the next one:
ink more than --max-overhang pixels (default 1, the antialiased edge) past the advance is cut (clip_width), else the
long tail of a Cinzel or IM Fell "Q" would become the glyph's width and leave a gap after it ("Q UALQ UER"). Glyphs first..last are byte values in `encoding`: the client draws a string byte by byte, each
byte the glyph of that number (BitmapFont, glyphs first-glyph..255, laid out row by row from the sheet's top left like
the stock 16x14-cell cp1252 Verdana sheets), so the default is the whole printable cp1252 range 32..255 (accents,
"€ – — ‘ ’ “ ” …"; the no-break space advances like a space, the soft hyphen is a hyphen, 127 and the 5 bytes cp1252
leaves undefined stay empty). A byte past the sheet has no glyph and is not drawn. The cell is as tall as all glyphs
need: an accented capital that reaches above the font's line box makes it taller (the text then sits that much
lower), empty rows above are cut and given back by the .otfont y-offset (the text does not move), --tight also cuts
the empty rows below (a smaller sheet, a one-line text box that much shorter). --weight picks the weight of a variable font (its
`wght` axis, e.g. Cinzel[wght].ttf 400..900); --space-width sets the space of a font whose own is very narrow.
Names: <name>-<size>px, files <name>-<size>px.png/.otfont.

The font atlas: the client copies every bitmap font into ONE 2048x2048 texture when it loads it (Atlas::cacheFont,
built without BIG_FONTS). Each sheet takes a power-of-two square slot of max(width, height) (32 .. 2048, a buddy
allocator) and the client stops with "[Atlas] Out of space for new fonts" (fatal) when none is left. --atlas-check
replays that allocator over the .otfont files of the given folders in load order (client_styles imports data/fonts
recursively, sorted; a font whose name is loaded already is skipped, FontManager::importFont) and prints the slots, what is left and whether everything fits; exit 1 when it does not. The
sheet layout here picks the column count that gives the smallest slot. Rendering needs Pillow, the check does not."""
import argparse, math, os, re, struct, sys

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


def png_size(path):
    """(width, height) of a PNG from its IHDR chunk (no Pillow needed); None when the file is not a PNG"""
    with open(path, 'rb') as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b'\x89PNG\r\n\x1a\n' or head[12:16] != b'IHDR':
        return None
    return struct.unpack('>II', head[16:24])


def texture_path(otfont_path, texture):
    t = texture if texture.endswith('.png') else texture + '.png'
    if t.startswith('/'):
        return None  # absolute resource path: not resolvable here
    return os.path.join(os.path.dirname(otfont_path), t)


def axis_values(axes, wanted):
    """the value list for Pillow's set_variation_by_axes: each axis its default, or the wanted value (by axis tag or
    name, clamped to the axis range); KeyError for a wanted axis the font does not have"""
    tags = {'wght': 'weight', 'wdth': 'width', 'slnt': 'slant', 'ital': 'italic', 'opsz': 'optical size'}
    out, used = [], set()
    for ax in axes:
        name = ax['name'].decode('latin-1') if isinstance(ax['name'], bytes) else str(ax['name'])
        value = ax['default']
        for key, v in wanted.items():
            if name.lower() in (key.lower(), tags.get(key, key).lower()):
                value = max(ax['minimum'], min(ax['maximum'], v))
                used.add(key)
        out.append(value)
    missing = set(wanted) - used
    if missing:
        raise KeyError('the font has no axis %s' % ', '.join(sorted(missing)))
    return out


# ---------------------------------------------------------------- rendering (Pillow)
def parse_rgba(text):
    parts = [int(x) for x in str(text).split(',')]
    while len(parts) < 4:
        parts.append(255)
    return tuple(parts[:4])


def clip_width(ink_w, shift, adv, max_overhang=1):
    """the ink width a glyph keeps: the client measures a glyph by its last painted column and draws nothing past
    it, so ink reaching more than `max_overhang` pixels past the advance (a "Q" tail) is cut there; None: no limit"""
    if max_overhang is None:
        return ink_w
    return min(ink_w, shift + adv + max(0, int(max_overhang)))


def glyph_text(ch):
    """what is drawn for a character: None for a cell left empty (control, undefined), '' for an invisible glyph that
    only advances (the no-break space), the soft hyphen as a hyphen (as Windows fonts show it)"""
    if ch is None:
        return None
    if ch == '\xa0':
        return ''
    if ch == '\xad':
        return '-'
    return ch if ch.isprintable() else None


def disc_offsets(radius):
    """the (dx, dy) integer offsets within `radius` of the origin (a filled disc, the origin included), sorted"""
    r = int(math.floor(radius))
    return sorted((dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1) if dx * dx + dy * dy <= radius * radius)


def ring_pad(outline=0, border=0.0):
    """the pixels a glyph's outline or border reaches past its ink on each side"""
    return max(int(outline), int(math.ceil(border)) if border > 0 else 0)


def squeeze(ink_w, pad_l, pad_r, max_cell_w):
    """the ink width a glyph is drawn at: its own, or what fits the cell when --max-cell-width is smaller"""
    if not max_cell_w:
        return ink_w
    room = max_cell_w - pad_l - pad_r
    if room < 1:
        raise ValueError('--max-cell-width %d leaves no room inside the outline and shadow' % max_cell_w)
    return min(ink_w, room)


def vertical_fit(rows_used, line_height, tight=False):
    """the cell rows of a sheet and the .otfont values that keep every glyph where the font puts it.
    rows_used: (top, bottom) of all painted rows, relative to the top of the font's line box of `line_height` rows
    (top < 0: a glyph reaches above it, e.g. an accented capital; bottom > line_height: below it).
    Empty rows above are cut and given back by y-offset (the text does not move); a glyph reaching above the line
    box makes it taller instead (the text moves down by that much, never cut). Empty rows below stay (a text box
    keeps its height) unless `tight` (a smaller sheet; a one-line text box is that much shorter). The line advance
    (height + spacing height) stays the line box, or grows by what is added. Returns (first_row, height, y_offset,
    spacing_height)."""
    top, bottom = rows_used
    if not tight:
        bottom = max(bottom, line_height)
    advance = max(line_height, bottom) - min(0, top)
    height = bottom - top
    return top, height, max(0, top), advance - height


def render(font_file, size, name, out_dir, first=32, last=255, encoding='cp1252', outline=0,
           outline_color=(0, 0, 0, 200), shadow=(0, 0), shadow_color=(0, 0, 0, 160), tracking=0, weight=None,
           space_width=None, tight=False, border=0.0, border_color=(0, 0, 0, 230), max_cell_width=None,
           max_overhang=1):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(font_file, size)
    if weight:
        font.set_variation_by_axes(axis_values(font.get_variation_axes(), {'wght': weight}))
    ascent, descent = font.getmetrics()
    ring = ring_pad(outline, border)
    pad_l = ring + max(0, -shadow[0])
    pad_r = ring + max(0, shadow[0])
    pad_t = ring + max(0, -shadow[1])
    pad_b = ring + max(0, shadow[1])
    # the outline ring and a shadow to the right reach past the advance: the advance marker is put that far out and
    # the .otfont spacing takes it back, so every glyph advances by its own width (else the client, which measures a
    # glyph by its last painted column, would space the letters by their shadow)
    right = ring + max(0, shadow[0])
    space = (space_width if space_width else int(round(font.getlength(' '))) + tracking)
    chars = glyph_chars(first, last, encoding)
    metrics, squeezed, clipped = {}, {}, {}
    cell_w = 1
    for b, ch in chars:
        text = glyph_text(ch)
        if text is None:
            continue
        if text == '':  # no-break space: only the advance of the space
            metrics[b] = (text, 0, pad_l + max(1, space) + right, 0)
            continue
        l, t, r, bt = font.getbbox(text)
        adv = int(round(font.getlength(text))) + tracking
        shift = max(0, -l)  # a glyph that starts left of its origin is moved right by that much
        ink_w = max(r + shift, adv + shift)
        cut_w = clip_width(ink_w, shift, adv, max_overhang)
        if cut_w < ink_w:  # a tail past the advance: cut (the client would space the next glyph after it)
            clipped[b] = ink_w - cut_w
            ink_w = cut_w
        fit_w = squeeze(ink_w, pad_l, pad_r, max_cell_width)
        if fit_w < ink_w:  # drawn narrower: the advance shrinks with it
            adv = max(1, int(round(adv * fit_w / float(ink_w))))
            squeezed[b] = (ink_w, fit_w)
            ink_w = fit_w
        metrics[b] = (text, shift, pad_l + shift + adv + right, ink_w)  # spacing -right in the .otfont
        cell_w = max(cell_w, pad_l + ink_w + pad_r)
    line_h = ascent + descent + pad_t + pad_b
    # each glyph is drawn into a tall canvas first: the rows all glyphs use decide the cell height (vertical_fit)
    margin = size + outline + abs(shadow[1]) + 2
    canvas_h = line_h + 2 * margin
    glyphs, top, bottom = {}, None, None
    for b, (text, shift, adv, _) in metrics.items():
        glyph = Image.new('RGBA', (cell_w, canvas_h), (0, 0, 0, 0))
        if text:
            if b in squeezed:  # drawn at its own width, then scaled to fit the cell
                full_w, fit_w = squeezed[b]
                wide = Image.new('L', (pad_l + full_w + pad_r + shift, canvas_h), 0)
                ImageDraw.Draw(wide).text((pad_l + shift, margin + pad_t), text, font=font, fill=255)
                ink = wide.crop((pad_l, 0, pad_l + full_w, canvas_h)).resize((fit_w, canvas_h), Image.LANCZOS)
                mask = Image.new('L', (cell_w, canvas_h), 0)
                mask.paste(ink, (pad_l, 0))
            else:
                mask = Image.new('L', (cell_w, canvas_h), 0)
                ImageDraw.Draw(mask).text((pad_l + shift, margin + pad_t), text, font=font, fill=255)
                if b in clipped:  # nothing past the kept ink width (the ring then closes the cut edge)
                    ImageDraw.Draw(mask).rectangle((pad_l + metrics[b][3], 0, cell_w, canvas_h), fill=0)
            if shadow != (0, 0):
                sh = Image.new('L', (cell_w, canvas_h), 0)
                sh.paste(mask, (shadow[0], shadow[1]))
                if border:
                    sh = _soft_dilate(sh, border)
                elif outline:
                    sh = _dilate(sh, outline)
                glyph.paste(Image.new('RGBA', (cell_w, canvas_h), shadow_color), (0, 0),
                            sh.point(lambda v: v * shadow_color[3] // 255))
            if border:
                glyph = Image.alpha_composite(glyph, _colored(_soft_dilate(mask, border), border_color))
            elif outline:
                glyph = Image.alpha_composite(glyph, _colored(_dilate(mask, outline), outline_color))
            glyph = Image.alpha_composite(glyph, _colored(mask, (255, 255, 255, 255)))
            box = glyph.getchannel('A').getbbox()
            if box:
                top = box[1] if top is None else min(top, box[1])
                bottom = box[3] if bottom is None else max(bottom, box[3])
        glyphs[b] = glyph
    if top is None:
        top, bottom = margin, margin + line_h
    first_row, cell_h, y_offset, spacing_h = vertical_fit((top - margin, bottom - margin), line_h, tight)
    cols, rows, w, h, slot = layout(len(chars), cell_w, cell_h)
    sheet = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for i, (b, ch) in enumerate(chars):
        if b not in glyphs:
            continue
        adv = metrics[b][2]
        glyph = glyphs[b].crop((0, margin + first_row, cell_w, margin + first_row + cell_h))
        # the advance: one invisible pixel in the last column of the glyph's width
        px = glyph.load()
        x = min(cell_w - 1, max(1, adv) - 1)
        if px[x, 0][3] == 0:
            px[x, 0] = (255, 255, 255, 1)
        sheet.paste(glyph, ((i % cols) * cell_w, (i // cols) * cell_h))
    base = '%s-%dpx' % (name, size)
    os.makedirs(out_dir, exist_ok=True)
    sheet.save(os.path.join(out_dir, base + '.png'), optimize=True)
    with open(os.path.join(out_dir, base + '.otfont'), 'w', encoding='utf-8') as f:
        f.write(otfont_text(base, base, cell_h, cell_w, cell_h, max(1, space + right), first=first,
                            y_offset=y_offset, spacing=(-right, spacing_h)))
    return {'name': base, 'size': (w, h), 'cell': (cell_w, cell_h), 'slot': slot,
            'glyphs': sum(1 for b in metrics if metrics[b][0]), 'range': (first, last), 'y_offset': y_offset,
            'squeezed': ''.join(metrics[b][0] for b in sorted(squeezed)),
            'clipped': ''.join(metrics[b][0] for b in sorted(clipped)),
            'line': cell_h + spacing_h, 'old_line': line_h}


def _dilate(mask, radius):
    from PIL import ImageFilter
    out = mask
    for _ in range(radius):
        out = out.filter(ImageFilter.MaxFilter(3))
    return out


def _soft_dilate(mask, radius, scale=4):
    """an antialiased round dilation of an 8-bit mask by `radius` pixels (may be fractional): each pixel's coverage
    is spread over a 4x4 block, the maximum taken over a disc of radius*4 sub-pixels and the blocks averaged back
    (box), so the ring is never wider than `radius` and its edge and corners come out soft. The mask is padded
    first, so the wrap-around of ImageChops.offset brings in nothing."""
    from PIL import Image, ImageChops
    w, h = mask.size
    pad = int(math.ceil(radius)) + 1
    padded = Image.new('L', (w + 2 * pad, h + 2 * pad), 0)
    padded.paste(mask, (pad, pad))
    big = padded.resize((padded.width * scale, padded.height * scale), Image.NEAREST)
    out = big
    for dx, dy in disc_offsets(radius * scale):
        if dx or dy:
            out = ImageChops.lighter(out, ImageChops.offset(big, dx, dy))
    return out.resize(padded.size, Image.BOX).crop((pad, pad, pad + w, pad + h))


def _colored(mask, rgba):
    from PIL import Image
    img = Image.new('RGBA', mask.size, rgba[:3] + (0,))
    img.putalpha(mask.point(lambda v: v * rgba[3] // 255))
    return img


# ---------------------------------------------------------------- atlas check
def atlas_check(folders, quiet=False):
    atlas = Atlas()
    ok = True
    names = set()
    for p in load_order(folders):
        info = parse_otfont(open(p, encoding='latin-1').read())
        if info['name'] in names:
            # FontManager::importFont returns before loading a font whose name is loaded already: no atlas slot
            if not quiet:
                print('  %-44s (name loaded already: skipped)' % info['name'])
            continue
        names.add(info['name'])
        tex = texture_path(p, info['texture'] or '')
        if not tex or not os.path.exists(tex):
            if not quiet:
                print('  (no texture) %s' % p)
            continue
        w, h = png_size(tex) or (0, 0)
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
    ap.add_argument('--last', type=int, default=255)
    ap.add_argument('--encoding', default='cp1252')
    ap.add_argument('--outline', type=int, default=0)
    ap.add_argument('--outline-color', default='0,0,0,200')
    ap.add_argument('--shadow', default='0,0')
    ap.add_argument('--shadow-color', default='0,0,0,160')
    ap.add_argument('--tracking', type=int, default=0)
    ap.add_argument('--weight', type=int, help='weight of a variable font (wght axis)')
    ap.add_argument('--space-width', type=int, help='width of the space in px (default: the font\'s own)')
    ap.add_argument('--tight', action='store_true', help='cut the empty rows below the glyphs too (a smaller sheet)')
    ap.add_argument('--border', type=float, default=0.0, help='antialiased round border of this many px (e.g. 1.2)')
    ap.add_argument('--border-color', default='0,0,0,230')
    ap.add_argument('--max-cell-width', type=int, help='squeeze glyphs wider than this cell (px, rings included)')
    ap.add_argument('--max-overhang', type=int, default=1,
                    help='px of ink kept past a glyph\'s advance; more (a "Q" tail) is cut (default 1)')
    ap.add_argument('--atlas-check', nargs='+', metavar='DIR')
    a = ap.parse_args(argv)
    if a.atlas_check:
        return 0 if atlas_check(a.atlas_check) else 1
    if not a.font or not a.name:
        ap.error('FONT and --name are needed (or --atlas-check DIR)')
    shadow = tuple(int(x) for x in a.shadow.split(','))
    for size in [int(s) for s in a.sizes.split(',') if s.strip()]:
        r = render(a.font, size, a.name, a.out, a.first, a.last, a.encoding, a.outline, parse_rgba(a.outline_color),
                   shadow, parse_rgba(a.shadow_color), a.tracking, a.weight, a.space_width, a.tight,
                   a.border, parse_rgba(a.border_color), a.max_cell_width, a.max_overhang)
        print('%s: %dx%d sheet, cell %dx%d, glyphs %d..%d (%d drawn), y-offset %d, line %d, atlas slot %d%s%s' % (
              r['name'], r['size'][0], r['size'][1], r['cell'][0], r['cell'][1], r['range'][0], r['range'][1],
              r['glyphs'], r['y_offset'], r['line'], r['slot'],
              ', %d squeezed' % len(r['squeezed']) if r['squeezed'] else '',
              ', cut past the advance: %s' % r['clipped'] if r['clipped'] else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

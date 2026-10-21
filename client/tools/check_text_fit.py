#!/usr/bin/env python3
"""Text fit: fixed-width labels whose words are measured in the bitmap font they are drawn in, English and pt-BR.

The client measures a text like BitmapFont does: each glyph is as wide as the last column of its cell with any alpha
(calculateGlyphsWidthsAutomatically), the space is the .otfont space-width, and each glyph adds the spacing's x.
Only fonts whose sheet is in the overlay can be measured here (data/fonts/*.otfont pointing into data/fonts/chaos/).

Checked now:
  Options menu sub-entries (base patch 0104, NOptionButton: 115 px, no icon, verdana-9px-bold): every name of the
  OPTION_LABELS table of base patch 0056 but the four top entries, and its pt-BR text (client_chaos_locale/pt_br.lua).
  The four top entries (Controls, Interface, Graphics, Misc.) keep $var-cip-font, a stock sheet not in the repo.

Usage: python3 client/tools/check_text_fit.py   (Pillow; exit 1 when a text does not fit)
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.dirname(HERE)
FONTS = os.path.join(CLIENT, 'overlay', 'data', 'fonts')
PT_BR = os.path.join(CLIENT, 'overlay', 'modules', 'client_chaos_locale', 'pt_br.lua')
PATCHES = os.path.join(CLIENT, 'base-patches')

MENU_TOP = {'controls', 'interface', 'graphics', 'misc'}
SUBENTRY_FONT = 'verdana-9px-bold'
SUBENTRY_WIDTH = 115
SUBENTRY_PAD = 4  # each side: the button's bevel


def otfont(path):
    """the .otfont's fields: texture, glyph-size, first-glyph, spacing x, space-width"""
    txt = open(path, encoding='utf-8').read()

    def field(key, default=None):
        m = re.search(r'^\s*' + re.escape(key) + r':\s*(.+?)\s*$', txt, re.M)
        return m.group(1) if m else default
    cw, ch = (int(v) for v in field('glyph-size').split())
    return {'texture': field('texture'), 'cell': (cw, ch), 'first': int(field('first-glyph', '32')),
            'spacing': int(field('spacing', '0 0').split()[0]), 'space': int(field('space-width', '4'))}


def glyph_widths(sheet, cell, first):
    """byte -> advance width from a glyph sheet (an RGBA image): the last column with any alpha, plus one"""
    cw, ch = cell
    cols = sheet.width // cw
    alpha = sheet.getchannel('A').load()
    widths = {}
    for b in range(first, 256):
        i = b - first
        x0, y0 = (i % cols) * cw, (i // cols) * ch
        if y0 + ch > sheet.height:
            break
        w = 0
        for x in range(cw - 1, -1, -1):
            if any(alpha[x0 + x, y0 + y] for y in range(ch)):
                w = x + 1
                break
        widths[b] = w
    return widths


def measurer(widths, spacing, space):
    """text -> pixel width, the text drawn byte by byte in cp1252 like the client"""
    def measure(text):
        data = text.encode('cp1252')
        total = sum((space if b == 32 else widths.get(b, 0)) + spacing for b in data)
        return total - spacing if data else 0
    return measure


def load_font(name):
    f = otfont(os.path.join(FONTS, name + '.otfont'))
    sheet = Image.open(os.path.join(FONTS, f['texture'] + '.png')).convert('RGBA')
    return measurer(glyph_widths(sheet, f['cell'], f['first']), f['spacing'], f['space'])


def lua_string(s):
    return s.replace('\\"', '"').replace("\\'", "'").replace('\\n', '\n').replace('\\\\', '\\')


def pt_br_table(text):
    """the pt-BR locale's ["English"] = "Portuguese" pairs"""
    pair = re.compile(r'\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"')
    return {lua_string(a): lua_string(b) for a, b in pair.findall(text)}


def option_labels(patch_text):
    """id -> English name from the OPTION_LABELS table base patch 0056 adds to client_settings/settings.lua"""
    m = re.search(r'OPTION_LABELS = \{(.*?)\n\+\}', patch_text, re.S)
    if not m:
        return {}
    return dict(re.findall(r"(\w+) = '([^']*)'", m.group(1)))


def subentry_font_in_patches():
    """the NOptionButton font the last base patch that sets it leaves (None when none does)"""
    font = None
    for name in sorted(os.listdir(PATCHES)):
        if not name.endswith('.patch'):
            continue
        text = open(os.path.join(PATCHES, name), encoding='utf-8').read()
        for block in re.split(r'^@@', text, flags=re.M):
            if 'image-clip: 0 0 115 20' in block or 'NOptionButton' in block.split('\n', 1)[0]:
                for line in block.splitlines():
                    m = re.match(r'^\+\s+font:\s*(\S+)', line)
                    if m:
                        font = m.group(1)
    return font


def check():
    problems = []
    patched = subentry_font_in_patches()
    if patched != SUBENTRY_FONT:
        problems.append('NOptionButton font in the base patches is %s, this check measures %s' % (patched, SUBENTRY_FONT))
    patch = [n for n in os.listdir(PATCHES) if n.startswith('0056-')]
    labels = option_labels(open(os.path.join(PATCHES, patch[0]), encoding='utf-8').read()) if patch else {}
    if not labels:
        problems.append('OPTION_LABELS not found in base patch 0056')
    tr = pt_br_table(open(PT_BR, encoding='utf-8').read())
    measure = load_font(SUBENTRY_FONT)
    room = SUBENTRY_WIDTH - 2 * SUBENTRY_PAD
    widest = (0, '')
    for key, english in sorted(labels.items()):
        if key in MENU_TOP:
            continue
        if english not in tr:
            problems.append('no pt-BR text for options menu entry "%s"' % english)
        for text in (english, tr.get(english)):
            if text is None:
                continue
            w = measure(text)
            widest = max(widest, (w, text))
            if w > room:
                problems.append('options menu sub-entry "%s" is %d px in %s, the button has %d' % (text, w, SUBENTRY_FONT, room))
    return problems, widest, room


def main():
    problems, widest, room = check()
    for p in problems:
        print('text fit:', p)
    if problems:
        return 1
    print('text fit: ok (options menu sub-entries: widest "%s" %d of %d px)' % (widest[1], widest[0], room))
    return 0


if __name__ == '__main__':
    sys.exit(main())

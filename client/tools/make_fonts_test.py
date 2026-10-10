#!/usr/bin/env python3
"""Tests of the pure parts of make_fonts.py (no Pillow needed): atlas slots, sheet layout, glyph range (cp1252
32..255), the cell rows (vertical_fit), the .otfont text, variable font axes, the font atlas allocator, and the
shipped sheets' glyph ranges. Run: python3 -I client/tools/make_fonts_test.py"""
import os, struct, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_fonts as M


class Slots(unittest.TestCase):
    def test_slot_size(self):
        self.assertEqual(M.slot_size(10, 20), 32)
        self.assertEqual(M.slot_size(121, 117), 128)
        self.assertEqual(M.slot_size(256, 114), 256)
        self.assertEqual(M.slot_size(257, 10), 512)
        self.assertEqual(M.slot_size(352, 210), 512)  # the base Verdana Bold-11px sheet
        self.assertIsNone(M.slot_size(2049, 1))

    def test_layout_prefers_the_smallest_slot(self):
        cols, rows, w, h, slot = M.layout(95, 11, 13)
        self.assertEqual(slot, 128)
        self.assertGreaterEqual(cols * rows, 95)
        self.assertLessEqual(max(w, h), 128)
        cols, rows, w, h, slot = M.layout(95, 22, 26)
        self.assertEqual(slot, 256)
        self.assertEqual((w, h), (cols * 22, rows * 26))

    def test_layout_too_big(self):
        with self.assertRaises(ValueError):
            M.layout(5000, 64, 64)

    def test_glyph_chars(self):
        g = M.glyph_chars(32, 126)
        self.assertEqual(len(g), 95)
        self.assertEqual(g[0], (32, ' '))
        self.assertEqual(g[-1], (126, '~'))
        self.assertEqual(dict(M.glyph_chars(128, 129))[128], '€')  # cp1252 euro
        self.assertIsNone(dict(M.glyph_chars(129, 129))[129])          # undefined in cp1252
        self.assertEqual(dict(M.glyph_chars(233, 233, 'latin-1'))[233], 'é')

    def test_glyph_text(self):
        # the client draws a byte per glyph, 32..255 as cp1252: what each cell gets
        self.assertEqual(M.glyph_text('A'), 'A')
        self.assertEqual(M.glyph_text('\xe7'), '\xe7')    # ç
        self.assertEqual(M.glyph_text('\u20ac'), '\u20ac')  # € (byte 128)
        self.assertEqual(M.glyph_text('\xa0'), '')         # no-break space: an advance only
        self.assertEqual(M.glyph_text('\xad'), '-')        # soft hyphen drawn as a hyphen
        self.assertIsNone(M.glyph_text('\x7f'))            # DEL: empty cell (the client gives it width 1)
        self.assertIsNone(M.glyph_text(None))              # undefined in cp1252 (129, 141, 143, 144, 157)
        full = M.glyph_chars(32, 255)
        self.assertEqual(len(full), 224)
        self.assertEqual(sum(1 for _, ch in full if M.glyph_text(ch)), 217)
        self.assertEqual(dict(full)[0x97], '\u2014')         # em dash
        self.assertEqual(dict(full)[0x93] + dict(full)[0x94], '\u201c\u201d')

    def test_vertical_fit(self):
        # rows 2..19 painted in a 21-row line box: the empty top rows are cut and given back by y-offset, the
        # bottom stays (same text box), the line advance stays 21
        self.assertEqual(M.vertical_fit((2, 19), 21), (2, 19, 2, 2))
        # tight: the empty bottom row goes too (one row shorter one-line box), advance still 21
        self.assertEqual(M.vertical_fit((2, 20), 21, tight=True), (2, 18, 2, 3))
        # an accented capital 2 rows above the line box: the cell grows, nothing is cut, the text moves down 2
        top, height, y_off, sp = M.vertical_fit((-2, 14), 13)
        self.assertEqual((top, height, y_off), (-2, 16, 0))
        self.assertEqual(height + sp, 16)  # line advance 13 + 2 above + 1 below
        # a box that is used to the edges: unchanged
        self.assertEqual(M.vertical_fit((0, 22), 22), (0, 22, 0, 0))

    def test_otfont_text(self):
        t = M.otfont_text('fontin-14px', 'fontin-14px', 19, 16, 19, 4, spacing=(-1, 0))
        self.assertIn('name: fontin-14px', t)
        self.assertIn('glyph-size: 16 19', t)
        self.assertIn('spacing: -1 0', t)
        self.assertIn('first-glyph: 32', t)
        self.assertEqual(M.parse_otfont(t), {'name': 'fontin-14px', 'texture': 'fontin-14px'})


class Shipped(unittest.TestCase):
    """the bitmap fonts in overlay/data/fonts/chaos/ (make_ofl_fonts.sh): their sheets hold every glyph from
    first-glyph to the end of the range (else the client draws nothing for the bytes past the sheet)"""
    DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'overlay', 'data', 'fonts', 'chaos')
    RANGE = {'chaos-splash-20px': 90}  # upper case only: a 256 slot (MANIFEST "OFL fonts")

    def test_ranges(self):
        import re
        names = [n[:-7] for n in sorted(os.listdir(self.DIR)) if n.endswith('.otfont')]
        self.assertEqual(len(names), 7)
        for n in names:
            text = open(os.path.join(self.DIR, n + '.otfont'), encoding='utf-8').read()
            gw, gh = [int(x) for x in re.search(r'glyph-size: (\d+) (\d+)', text).group(1, 2)]
            first = int(re.search(r'first-glyph: (\d+)', text).group(1))
            height = int(re.search(r'height: (\d+)', text).group(1))
            w, h = M.png_size(os.path.join(self.DIR, n + '.png'))
            cells = (w // gw) * (h // gh)
            last = self.RANGE.get(n, 255)
            self.assertEqual(first, 32, n)
            self.assertGreaterEqual(cells, last - first + 1, n)
            self.assertEqual(height, gh, n)  # the glyph rect is the whole cell
            self.assertLessEqual(M.slot_size(w, h), 512, n)

    def test_overrides_are_aliases(self):
        # the unused stock fonts the overlay replaces carry the name of a font loaded before them: no atlas slot
        fonts = os.path.join(self.DIR, '..')
        for n in ('Verdana-Strikethrough-11px', 'Verdana-11px-italic', 'Verdana Bold-10px', 'Verdana Bold-11px-low-space',
                  'Verdana-8px-antialiased-espaco', 'Verdana-8px', 'var-cip-font', 'verdana-9px-italic',
                  'terminus-10px'):
            info = M.parse_otfont(open(os.path.join(fonts, n + '.otfont'), encoding='utf-8').read())
            self.assertEqual(info['name'], 'Icon-VBold-11px', n)
            self.assertLess('Icon-VBold-11px.otfont', n + '.otfont')  # loads first (sorted)


class RenderTest(unittest.TestCase):
    """make_fonts.render on a shipped OFL font (needs Pillow, skipped without it)"""

    def test_full_range(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest('no Pillow')
        import re, shutil, tempfile
        font = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'fonts-src', 'AlegreyaSans',
                            'AlegreyaSans-Medium.ttf')
        d = tempfile.mkdtemp()
        try:
            r = M.render(font, 12, 't', d, shadow=(1, 1), space_width=3)
            self.assertEqual(r['range'], (32, 255))
            text = open(os.path.join(d, 't-12px.otfont')).read()
            gw, gh = [int(x) for x in re.search(r'glyph-size: (\d+) (\d+)', text).group(1, 2)]
            sx = int(re.search(r'spacing: (-?\d+)', text).group(1))
            img = Image.open(os.path.join(d, 't-12px.png'))
            cols = img.size[0] // gw
            alpha = img.getchannel('A').load()

            def width(byte):  # BitmapFont::calculateGlyphsWidthsAutomatically: the last column with any alpha
                i = byte - 32
                x0, y0 = (i % cols) * gw, (i // cols) * gh
                cols_used = [x for x in range(gw) if any(alpha[x0 + x, y0 + y] for y in range(gh))]
                return cols_used[-1] + 1 if cols_used else 0
            self.assertEqual(width(0xA0) + sx, 3)                # no-break space advances like the space
            self.assertGreater(width(0xC1), 0)                  # Á
            self.assertGreater(width(0x80), 0)                  # €
            self.assertEqual(width(0x81), 0)                    # undefined: empty
            self.assertEqual(width(ord('A')), width(0xC1))      # Á advances like A
            # Á reaches above the font's line box: the cell and the line get that room (y-offset 0, nothing cut)
            self.assertGreater(r['line'], r['old_line'])
            self.assertEqual(r['y_offset'], 0)
        finally:
            shutil.rmtree(d)


class AtlasTest(unittest.TestCase):
    def test_buddy_like_the_client(self):
        a = M.Atlas()
        self.assertEqual(a.place(300, 200, 'a'), (0, 0))      # 512: 2048 -> 1024 -> 512 split
        self.assertEqual(a.place(200, 100, 'b'), (0, 512))     # 256: the next 512 is split
        self.assertEqual(a.free_area(), 2048 * 2048 - 512 * 512 - 256 * 256)

    def test_out_of_space(self):
        a = M.Atlas()
        for i in range(16):
            self.assertIsNotNone(a.place(512, 512))
        self.assertIsNone(a.place(10, 10))
        self.assertEqual(a.free_area(), 0)

    def test_fragmentation(self):
        # 63 slots of 256 and one 512 request: a 256 left over cannot take a 512
        a = M.Atlas()
        for i in range(63):
            a.place(256, 256)
        self.assertEqual(a.free_area(), 65536)
        self.assertIsNone(a.place(300, 10))
        self.assertIsNotNone(a.place(200, 200))

    def test_png_size(self):
        import tempfile, zlib
        d = tempfile.mkdtemp()
        p = os.path.join(d, 'a.png')
        ihdr = struct.pack('>II5B', 300, 17, 8, 6, 0, 0, 0)
        with open(p, 'wb') as f:
            crc = struct.pack('>I', zlib.crc32(b'IHDR' + ihdr))
            f.write(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + ihdr + crc)
        self.assertEqual(M.png_size(p), (300, 17))
        open(p, 'wb').write(b'not a png at all, not at all')
        self.assertIsNone(M.png_size(p))

    def test_axis_values(self):
        axes = [{'name': b'Weight', 'minimum': 400, 'default': 400, 'maximum': 900},
                {'name': b'Width', 'minimum': 75, 'default': 100, 'maximum': 100}]
        self.assertEqual(M.axis_values(axes, {}), [400, 100])
        self.assertEqual(M.axis_values(axes, {'wght': 600}), [600, 100])
        self.assertEqual(M.axis_values(axes, {'wght': 1000, 'wdth': 50}), [900, 75])  # clamped to the range
        with self.assertRaises(KeyError):
            M.axis_values(axes, {'opsz': 12})

    def test_check_folder(self):
        import tempfile
        d = tempfile.mkdtemp()
        try:
            from PIL import Image
        except ImportError:
            return
        Image.new('RGBA', (300, 200)).save(os.path.join(d, 'x.png'))
        open(os.path.join(d, 'x.otfont'), 'w').write(M.otfont_text('x', 'x', 10, 10, 10, 3))
        os.mkdir(os.path.join(d, 'sub'))
        Image.new('RGBA', (100, 100)).save(os.path.join(d, 'sub', 'y.png'))
        open(os.path.join(d, 'sub', 'y.otfont'), 'w').write(M.otfont_text('y', 'y', 10, 10, 10, 3))
        self.assertEqual([os.path.basename(p) for p in M.load_order([d])], ['y.otfont', 'x.otfont'])
        self.assertTrue(M.atlas_check([d], quiet=True))
        # a second font of the same name is skipped by the client: it takes no slot, so 63 more 256 sheets still fit
        Image.new('RGBA', (2048, 2048)).save(os.path.join(d, 'big.png'))
        open(os.path.join(d, 'z.otfont'), 'w').write(M.otfont_text('x', 'big', 10, 10, 10, 3))
        self.assertTrue(M.atlas_check([d], quiet=True))


if __name__ == '__main__':
    unittest.main()

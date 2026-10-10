#!/usr/bin/env python3
"""Tests of the pure parts of make_fonts.py (no Pillow needed): atlas slots, sheet layout, glyph range, the .otfont
text, variable font axes and the font atlas allocator. Run: python3 -I client/tools/make_fonts_test.py"""
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

    def test_otfont_text(self):
        t = M.otfont_text('fontin-14px', 'fontin-14px', 19, 16, 19, 4, spacing=(-1, 0))
        self.assertIn('name: fontin-14px', t)
        self.assertIn('glyph-size: 16 19', t)
        self.assertIn('spacing: -1 0', t)
        self.assertIn('first-glyph: 32', t)
        self.assertEqual(M.parse_otfont(t), {'name': 'fontin-14px', 'texture': 'fontin-14px'})


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

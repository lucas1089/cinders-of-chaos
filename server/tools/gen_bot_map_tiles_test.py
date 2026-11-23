#!/usr/bin/env python3
"""python3 -I server/tools/gen_bot_map_tiles_test.py: the tile pyramid of the staff's bot map (gen_bot_map_tiles.py, O727) on a synthetic world map,
a synthetic items folder and a synthetic swatch atlas (made here, no committed art, no real map). Needs numpy and Pillow."""
import hashlib
import json
import warnings
import os
import shutil
import struct
import sys
import tempfile
import unittest

warnings.simplefilter('ignore', ResourceWarning)   # the map readers of tools/map leave files to the garbage collector
try:
    import numpy as np
    from PIL import Image
except ImportError:
    print('numpy and Pillow are needed (CI uses the fx venv): skipped')
    sys.exit(0)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools', 'map'))
import audit_map_synth as S  # noqa: E402
import gen_bot_map_tiles as G  # noqa: E402
import otbm  # noqa: E402
from itemdb import ItemDB  # noqa: E402

GRASS, SAND, EDGE, WALL, TREE, DROP, NOART, SPLASH = 100, 101, 102, 200, 300, 400, 500, 600
# server id -> (client id, colour of its swatch, alpha, cells wide, cells high, flags of the index)
SW = {
    GRASS: (GRASS, (10, 200, 10), 255, 1, 1, 0),
    SAND: (SAND, (200, 190, 60), 255, 1, 1, 0),
    EDGE: (EDGE, (255, 255, 255), 128, 1, 1, 0),
    WALL: (WALL, (90, 40, 20), 255, 1, 1, 1),
    TREE: (TREE, (0, 80, 0), 255, 2, 2, 1),
}


def make_atlas(folder):
    """swatches.png and index.txt in the client's format: one swatch of a flat colour per item"""
    os.makedirs(folder, exist_ok=True)
    img = np.zeros((64, 64, 4), np.uint8)
    lines = []
    x = 0
    for sid, (cid, rgb, alpha, w, h, flags) in SW.items():
        img[0:h * 8, x:x + w * 8] = (rgb[0], rgb[1], rgb[2], alpha)
        lines.append('%d %d %d %d%d %x' % (cid, x, 0, w, h, flags))
        x += w * 8
    Image.fromarray(img, 'RGBA').save(os.path.join(folder, 'swatches.png'))
    with open(os.path.join(folder, 'swatches.png'), 'rb') as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    with open(os.path.join(folder, 'index.txt'), 'w') as f:
        f.write('chaos-minimap-hd 1\natlas swatches.png 64 64 8 %s\n' % sha + '\n'.join(lines) + '\n')


def make_items(folder):
    S.write_items(folder, {
        GRASS: dict(name='grass', group=1),
        SAND: dict(name='sand', group=1),
        EDGE: dict(name='sand border', order=1),
        WALL: dict(name='stone wall', flags=1, order=2),
        TREE: dict(name='tree', flags=1),
        DROP: dict(name='coin', flags=32 | 64),            # pickable and movable: not part of the map picture
        NOART: dict(name='dirt', group=1),                 # a ground with no swatch
        SPLASH: dict(name='blood', group=11),
    })


def town_bytes(towns, tiles):
    raw = S.map_bytes(tiles)
    node = S._node(12, b'', [S._node(13, struct.pack('<IH', i, len(n)) + n.encode() + struct.pack('<HHB', *p)) for i, n, p in towns])
    empty = S._node(12)
    assert raw.count(empty) == 1
    return raw.replace(empty, node)


def px(path, x, y):
    with Image.open(path) as im:
        return tuple(int(v) for v in im.convert('RGBA').getpixel((x, y)))


class World(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp()
        cls.atlas_dir = os.path.join(cls.d, 'atlas')
        cls.items = os.path.join(cls.d, 'items')
        make_atlas(cls.atlas_dir)
        make_items(cls.items)
        cls.tiles = {}
        # floor 7: grass 40 x 40 from (1000, 2000); the tile column x = 1032.. is sand; a few specials
        for y in range(2000, 2040):
            for x in range(1000, 1040):
                cls.tiles[(x, y, 7)] = dict(items=[SAND if x >= 1032 else GRASS])
        cls.tiles[(1005, 2005, 7)]['items'] = [GRASS, EDGE]                  # a border over the grass
        cls.tiles[(1006, 2005, 7)]['items'] = [GRASS, WALL]                  # a wall
        cls.tiles[(1007, 2005, 7)]['items'] = [GRASS, WALL, DROP]            # a wall and a dropped coin: still the wall
        cls.tiles[(1008, 2005, 7)]['items'] = [GRASS, DROP]                  # a coin on grass: grass
        cls.tiles[(1009, 2005, 7)]['items'] = [NOART]                        # no swatch: the flat square
        cls.tiles[(1010, 2005, 7)]['items'] = [GRASS, SPLASH]                # a splash is not drawn
        cls.tiles[(1032, 2010, 7)]['items'] = [SAND, TREE]                   # a 2 x 2 tree on the first tile of the second map tile: spills left and up
        cls.tiles[(1039, 2039, 7)]['items'] = [SAND, TREE]                   # a tree at the south east corner of the floor
        # floor 8: a small room
        for y in range(2000, 2004):
            for x in range(1000, 1004):
                cls.tiles[(x, y, 8)] = dict(items=[SAND])
        cls.map = os.path.join(cls.d, 'world.otbm')
        with open(cls.map, 'wb') as f:
            f.write(town_bytes([(1, 'Ashford', (1010, 2010, 7)), (2, 'Cinderhold', (1020, 2020, 7))], cls.tiles))
        cls.out = os.path.join(cls.d, 'out')
        cls.m = otbm.load_otbm(cls.map)
        cls.db = ItemDB(os.path.join(cls.items, 'items.otb'), os.path.join(cls.items, 'items.xml'))
        cls.atlas = G.Atlas(cls.atlas_dir)
        cls.meta = G.build(cls.m, cls.db, cls.atlas, cls.out, levels=3, towns=G.towns_of(cls.m), log=lambda s: None)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.d, ignore_errors=True)

    def tile(self, z, zoom, tx, ty):
        return os.path.join(self.out, str(z), str(zoom), str(tx), '%d.png' % ty)

    # ---- geometry
    def test_meta(self):
        m = self.meta
        self.assertEqual(m['origin'], [992, 1984])            # 1000 and 2000 rounded down to a multiple of 32
        self.assertEqual((m['tile'], m['cell'], m['minZoom'], m['maxZoom'], m['span0']), (256, 8, 0, 2, 128))
        self.assertEqual(m['bbox'], [1000, 2000, 1039, 2039])
        self.assertEqual([f['z'] for f in m['floors']], [7, 8])
        self.assertEqual(m['floors'][1]['bbox'], [1000, 2000, 1003, 2003])
        self.assertEqual([t['name'] for t in m['towns']], ['Ashford', 'Cinderhold'])
        self.assertEqual(m['towns'][0]['x'], 1010)
        self.assertEqual(json.load(open(os.path.join(self.out, 'meta.json')))['origin'], m['origin'])

    def test_origin_is_a_multiple_of_32(self):
        self.assertEqual(self.meta['origin'][0] % 32, 0)
        self.assertEqual(self.meta['origin'][1] % 32, 0)
        self.assertLessEqual(self.meta['origin'][0], 1000)
        self.assertLessEqual(self.meta['origin'][1], 2000)

    def test_the_shared_vector_of_the_page_script(self):
        # website/tests/chaos_botmap_core_test.js holds the same numbers for the script's toLatLng
        meta = {'origin': [992, 1984], 'span0': 128}
        lat, lng = G.to_latlng(meta, 1000, 2000)
        self.assertAlmostEqual(lat, -0.12890625, places=12)
        self.assertAlmostEqual(lng, 0.06640625, places=12)

    def test_tile_maths(self):
        o = self.meta['origin']
        lat, lng = G.to_latlng(self.meta, o[0], o[1])
        self.assertAlmostEqual(lng, 0.5 / 128)
        self.assertAlmostEqual(lat, -0.5 / 128)
        self.assertEqual(G.tile_of(self.meta, o[0], o[1], 2), (0, 0, 0, 0))
        self.assertEqual(G.tile_of(self.meta, o[0] + 33, o[1] + 1, 2), (1, 0, 8, 8))
        self.assertEqual(G.tile_of(self.meta, o[0] + 33, o[1] + 1, 1), (0, 0, 33 * 4, 4))
        self.assertEqual(G.tile_of(self.meta, o[0] + 64, o[1] + 64, 1), (1, 1, 0, 0))
        self.assertEqual(G.tile_of(self.meta, o[0] + 127, o[1] + 127, 0), (0, 0, 254, 254))
        # a game tile lands on the pixel its swatch was drawn at
        tx, ty, ppx, ppy = G.tile_of(self.meta, 1000, 2000, 2)
        self.assertEqual(px(self.tile(7, 2, tx, ty), ppx + 3, ppy + 3), (10, 200, 10, 255))

    # ---- the files
    def test_folders(self):
        for z in (7, 8):
            for zoom in (0, 1, 2):
                self.assertTrue(os.path.isdir(os.path.join(self.out, str(z), str(zoom))), (z, zoom))
        self.assertTrue(os.path.isfile(self.tile(8, 2, 0, 0)))
        self.assertFalse(os.path.exists(self.tile(8, 2, 1, 0)), 'no tile where the floor has no game tile')
        self.assertTrue(os.path.isfile(self.tile(7, 0, 0, 0)))

    def test_tile_size_and_format(self):
        with Image.open(self.tile(7, 2, 0, 0)) as im:
            self.assertEqual(im.size, (256, 256))
            self.assertEqual(im.format, 'PNG')

    def test_the_swatches_are_drawn(self):
        o = self.meta['origin']
        p = self.tile(7, 2, 0, 0)
        # tile (1000, 2000) is grass: local game tile (8, 16) of the first map tile -> pixels 64.., 128..
        lx, ly = (1000 - o[0]) * 8, (2000 - o[1]) * 8
        self.assertEqual(px(p, lx + 2, ly + 2), (10, 200, 10, 255))
        # no game tile west of 1000: transparent
        self.assertEqual(px(p, lx - 3, ly + 2)[3], 0)
        self.assertEqual(px(p, lx + 2, ly - 3)[3], 0)

    def test_border_is_blended_over_the_ground(self):
        o = self.meta['origin']
        c = px(self.tile(7, 2, 0, 0), (1005 - o[0]) * 8 + 3, (2005 - o[1]) * 8 + 3)
        self.assertEqual(c[3], 255)
        self.assertTrue(10 < c[0] < 255 and 200 < c[1] <= 255, c)   # half way between the grass and white

    def test_solid_wall_and_dropped_items(self):
        o = self.meta['origin']
        p = self.tile(7, 2, 0, 0)
        y = (2005 - o[1]) * 8 + 3
        self.assertEqual(px(p, (1006 - o[0]) * 8 + 3, y), (90, 40, 20, 255))
        self.assertEqual(px(p, (1007 - o[0]) * 8 + 3, y), (90, 40, 20, 255), 'a coin on a wall: the wall shows')
        self.assertEqual(px(p, (1008 - o[0]) * 8 + 3, y), (10, 200, 10, 255), 'a coin on the grass: the grass')

    def test_ground_without_a_swatch_is_the_flat_square(self):
        o = self.meta['origin']
        self.assertEqual(px(self.tile(7, 2, 0, 0), (1009 - o[0]) * 8 + 3, (2005 - o[1]) * 8 + 3), (24, 24, 24, 255))

    def test_splash_is_not_drawn(self):
        o = self.meta['origin']
        self.assertEqual(px(self.tile(7, 2, 0, 0), (1010 - o[0]) * 8 + 3, (2005 - o[1]) * 8 + 3), (10, 200, 10, 255))

    def test_a_big_swatch_sits_on_its_bottom_right_tile_and_crosses_the_tile_edge(self):
        o = self.meta['origin']
        # the tree stands on game tile (1032, 2010): its picture covers (1031..1032, 2009..2010)
        tx, ty, ppx, ppy = G.tile_of(self.meta, 1032, 2010, 2)
        right = self.tile(7, 2, tx, ty)
        self.assertEqual(px(right, ppx + 3, ppy + 3), (0, 80, 0, 255), 'its own tile')
        left_tx, left_ty, lpx, lpy = G.tile_of(self.meta, 1031, 2009, 2)
        self.assertEqual(left_tx, tx - 1 if (1031 - o[0]) // 32 != (1032 - o[0]) // 32 else tx)
        self.assertEqual(px(self.tile(7, 2, left_tx, left_ty), lpx + 3, lpy + 3), (0, 80, 0, 255), 'the part on the neighbour tile')
        # a tile outside the picture is the sand
        tx2, ty2, qx, qy = G.tile_of(self.meta, 1033, 2010, 2)
        self.assertEqual(px(self.tile(7, 2, tx2, ty2), qx + 3, qy + 3), (200, 190, 60, 255))

    def test_a_big_swatch_at_the_edge_of_the_floor(self):
        tx, ty, ppx, ppy = G.tile_of(self.meta, 1039, 2039, 2)
        self.assertEqual(px(self.tile(7, 2, tx, ty), ppx + 3, ppy + 3), (0, 80, 0, 255))

    def test_zoom_levels_average_the_children(self):
        # grass everywhere under the first map tile of zoom 2: zoom 1 and 0 hold the same colour where all four children are land
        o = self.meta['origin']
        z1 = self.tile(7, 1, 0, 0)
        lx, ly = (1010 - o[0]) * 4, (2010 - o[1]) * 4
        c = px(z1, lx + 1, ly + 1)
        self.assertEqual(c[3], 255)
        self.assertTrue(abs(c[1] - 200) <= 2 and c[0] <= 20, c)
        # at the edge of the land the alpha falls between 0 and 255 or is 0, never a dark fringe
        edge = px(z1, (1000 - o[0]) * 4 - 1, ly + 1)
        self.assertEqual(edge[3], 0)

    def test_every_map_tile_has_its_parent(self):
        for z in (7, 8):
            for zoom in (2, 1):
                for tx in os.listdir(os.path.join(self.out, str(z), str(zoom))):
                    for f in os.listdir(os.path.join(self.out, str(z), str(zoom), tx)):
                        ty = int(f[:-4])
                        self.assertTrue(os.path.isfile(self.tile(z, zoom - 1, int(tx) >> 1, ty >> 1)), (z, zoom, tx, ty))

    def test_estimate_counts_every_tile(self):
        n = sum(f['tiles'] for f in self.meta['floors'])
        files = sum(len(fs) for _, _, fs in os.walk(self.out)) - 1
        self.assertEqual(n, files)


class Rules(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.items = os.path.join(self.d, 'items')
        self.atlas_dir = os.path.join(self.d, 'atlas')
        make_atlas(self.atlas_dir)
        make_items(self.items)
        self.tiles = {(x, y, 7): dict(items=[GRASS]) for y in range(100, 110) for x in range(100, 110)}
        self.map = os.path.join(self.d, 'w.otbm')
        with open(self.map, 'wb') as f:
            f.write(town_bytes([(1, 'Ashford', (105, 105, 7))], self.tiles))

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def build(self, out, **kw):
        m = otbm.load_otbm(self.map)
        db = ItemDB(os.path.join(self.items, 'items.otb'), os.path.join(self.items, 'items.xml'))
        return G.build(m, db, G.Atlas(self.atlas_dir), out, log=lambda s: None, **kw)

    def test_roles(self):
        db = ItemDB(os.path.join(self.items, 'items.otb'), os.path.join(self.items, 'items.xml'))
        role, cid = G.roles_of(db)
        self.assertEqual([int(role[i]) for i in (GRASS, EDGE, WALL, TREE, DROP, SPLASH, 9999)], [G.R_GROUND, G.R_BORDER, G.R_SOLID, G.R_SOLID, 0, 0, 0])

    def test_dry_run_writes_nothing(self):
        out = os.path.join(self.d, 'o')
        meta = self.build(out, levels=2, dry=True)
        self.assertFalse(os.path.exists(out))
        self.assertGreater(meta['estimate_mb'], 0)

    def test_a_folder_with_files_is_refused(self):
        out = os.path.join(self.d, 'o')
        os.makedirs(out)
        open(os.path.join(out, 'x'), 'w').close()
        with self.assertRaises(G.TileError):
            self.build(out)

    def test_levels_and_floors_are_checked(self):
        with self.assertRaises(G.TileError):
            self.build(os.path.join(self.d, 'o'), levels=0)
        with self.assertRaises(G.TileError):
            self.build(os.path.join(self.d, 'o'), floors={3})

    def test_floor_filter(self):
        out = os.path.join(self.d, 'o')
        meta = self.build(out, levels=1, floors={7})
        self.assertEqual([f['z'] for f in meta['floors']], [7])

    def test_full_colour_png_has_no_palette(self):
        out = os.path.join(self.d, 'o')
        meta = self.build(out, levels=1, quantise=False)
        tx, ty, _, _ = G.tile_of(meta, 100, 100, 0)
        with Image.open(os.path.join(out, '7', '0', str(tx), '%d.png' % ty)) as im:
            self.assertEqual(im.mode, 'RGBA')

    def test_quantised_png_is_a_palette_with_alpha(self):
        out = os.path.join(self.d, 'o')
        meta = self.build(out, levels=1)
        tx, ty, ppx, ppy = G.tile_of(meta, 100, 100, 0)
        p = os.path.join(out, '7', '0', str(tx), '%d.png' % ty)
        with Image.open(p) as im:
            self.assertEqual(im.mode, 'P')
        self.assertEqual(px(p, ppx + 1, ppy + 1)[3], 255)

    def test_reduce2_weights_by_alpha(self):
        img = np.zeros((512, 512, 4), np.uint8)
        img[:256, :256] = (200, 100, 50, 255)         # one quarter land, three quarters empty
        out = G.reduce2(img)
        self.assertEqual(tuple(int(v) for v in out[0, 0]), (200, 100, 50, 255))
        full = np.full((512, 512, 4), 255, np.uint8)
        self.assertEqual(tuple(int(v) for v in G.reduce2(full)[5, 5]), (255, 255, 255, 255))
        half = np.zeros((512, 512, 4), np.uint8)
        half[::2] = (100, 100, 100, 255)              # every second row: half the alpha, the colour stays
        r = G.reduce2(half)
        self.assertTrue(abs(int(r[3, 3, 3]) - 128) <= 1 and abs(int(r[3, 3, 0]) - 100) <= 1, r[3, 3])

    def test_command_line_writes_tiles_meta_and_pointer(self):
        out = os.path.join(self.d, 'site', 'botmap-abc')
        ptr = os.path.join(self.d, 'data', 'chaos_botmap.json')
        os.makedirs(os.path.dirname(ptr))
        rc = G.main(['--map', self.map, '--items', self.items, '--swatches', self.atlas_dir, '--out', out, '--levels', '2',
                     '--pointer', ptr, '--url', 'botmap-abc'])
        self.assertEqual(rc, 0)
        meta = json.load(open(os.path.join(out, 'meta.json')))
        doc = json.load(open(ptr))
        self.assertEqual(doc['url'], 'botmap-abc')
        self.assertEqual(doc['towns'], [{'id': 1, 'name': 'Ashford', 'x': 105, 'y': 105, 'z': 7}])
        self.assertEqual({k: v for k, v in doc.items() if k != 'url'}, {k: v for k, v in meta.items()})
        self.assertEqual(G.main(['--map', self.map, '--items', self.items, '--swatches', self.atlas_dir, '--out', out]), 1, 'a second build into the same folder is refused')

    def test_pointer_needs_a_clean_url(self):
        with self.assertRaises(SystemExit):
            G.parse(['--map', 'a', '--items', 'b', '--out', 'c', '--pointer', 'p', '--url', '../x y'])

    def test_server_dir_finds_the_map(self):
        srv = os.path.join(self.d, 'srv')
        os.makedirs(os.path.join(srv, 'data', 'world'))
        shutil.copy(self.map, os.path.join(srv, 'data', 'world', 'cinders.otbm'))
        self.assertTrue(G.find_map(srv).endswith('cinders.otbm'))
        shutil.copy(self.map, os.path.join(srv, 'data', 'world', 'other.otbm'))
        with self.assertRaises(G.TileError):
            G.find_map(srv)
        with open(os.path.join(srv, 'config.lua'), 'w') as f:
            f.write('mapName = "other"\n')
        self.assertTrue(G.find_map(srv).endswith('other.otbm'))

    def test_a_missing_atlas_is_an_error(self):
        with self.assertRaises(G.TileError):
            G.Atlas(os.path.join(self.d, 'nothing'))


if __name__ == '__main__':
    unittest.main(warnings='ignore')

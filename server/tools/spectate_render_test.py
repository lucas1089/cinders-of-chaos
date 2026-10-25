#!/usr/bin/env python3
"""Tests of spectate_render.py on a tiny synthetic pair (no real pair needed): the dat index and its cache, the
snapshot checks (another watch, too old, offline, malformed), the drawing (the view around the player, draw order on a
tile, elevation, a 2 x 2 item, stack patterns, outfit direction and colours, a mount), the JSON answer with its PNG,
and the pair archive (sums checked, only Tibia.dat / Tibia.spr taken out, nothing written outside the folder).

    python3 -I server/tools/spectate_render_test.py
"""
import base64
import contextlib
import io
import json
import lzma
import os
import struct
import sys
import tarfile
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
from PIL import Image  # noqa: E402
import spectate_render as sr  # noqa: E402
import check_pair_test as cpt  # noqa: E402  (synthetic dat / spr writers)

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def full(col):
    return cpt.record({k: col for k in range(1024)})


def square(col, x0, y0, x1, y1):
    return cpt.record({y * 32 + x: col for y in range(y0, y1) for x in range(x0, x1)})


GREEN, RED, BLUE, WHITE = (0, 160, 0, 255), (220, 0, 0, 255), (0, 0, 220, 255), (200, 200, 200, 255)
BROWN, PINK, GREY = (120, 80, 40, 255), (250, 120, 200, 255), (128, 128, 128, 255)
NORTH, EAST, SOUTH, WEST = (10, 10, 10, 255), (60, 60, 60, 255), (200, 100, 50, 255), (90, 90, 90, 255)
YELLOW_MASK = (255, 255, 0, 255)
MOUNTED, MOUNT = (30, 200, 200, 255), (200, 30, 200, 255)
STACK = [(k * 20 + 20, 0, 0, 255) for k in range(8)]


def make_pair(d):
    # sprites 1..
    recs = [full(GREEN),                       # 1 ground
            square(RED, 0, 0, 8, 8),           # 2 top item: the tile's top-left 8 x 8
            full(BLUE),                        # 3 common item A
            full(WHITE),                       # 4 common item B
            full(BROWN),                       # 5 elevation item
            full(PINK),                        # 6 the big item (each of its 4 cells)
            full(NORTH), full(EAST), full(SOUTH), full(WEST),   # 7-10 the look's art by direction
            full(YELLOW_MASK),                 # 11 its template: all head
            full(MOUNTED),                     # 12 the mounted art
            full(MOUNT),                       # 13 the mount
            full(GREY)]                        # 14 an item look
    recs += [full(c) for c in STACK]           # 15-22 stack patterns
    ground = bytes([0]) + struct.pack('<H', 100)
    elev = bytes([26]) + struct.pack('<H', 8)
    items = [cpt.entry(ground, [cpt.group([1])]),                                  # 100 ground
             cpt.entry(bytes([3]), [cpt.group([2])]),                              # 101 top
             cpt.entry(b'', [cpt.group([3])]),                                     # 102 common A
             cpt.entry(b'', [cpt.group([4])]),                                     # 103 common B
             cpt.entry(elev, [cpt.group([5])]),                                    # 104 elevation 8
             cpt.entry(b'', [cpt.group([6] * 4, w=2, h=2)]),                       # 105 2 x 2
             cpt.entry(bytes([5]), [cpt.group(list(range(15, 23)), px=4, py=2)]),  # 106 stackable
             cpt.entry(b'', [cpt.group([14])])]                                    # 107 item look
    disp = bytes([25]) + struct.pack('<HH', 8, 8)
    # look 1: 4 directions, art + template; z 0 on foot, z 1 mounted
    on_foot = [7, 11, 8, 11, 9, 11, 10, 11]
    mounted = [12, 11] * 4
    outfits = [cpt.entry(disp, [cpt.group(on_foot + mounted, layers=2, px=4, pz=2, gtype=0)], outfit=True),
               cpt.entry(b'', [cpt.group([13] * 16, w=2, h=2, px=4, gtype=0)], outfit=True)]   # 2 a 2 x 2 mount
    os.makedirs(d, exist_ok=True)
    dat, spr = os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')
    with open(dat, 'wb') as f:
        f.write(cpt.dat_bytes(items, outfits, [], []))
    with open(spr, 'wb') as f:
        f.write(cpt.spr_bytes(recs))
    return dat, spr


PX, PY, PZ = 1000, 1000, 7
X0, Y0, W, H = PX - 8, PY - 6, 18, 14


def snapshot(tiles=None, creatures=None, watch='Bob', t=None, **kw):
    ts = [[100] for _ in range(W * H)]
    for (x, y), stack in (tiles or {}).items():
        ts[(y - Y0) * W + (x - X0)] = stack
    s = {'v': 1, 'watch': watch, 't': int(time.time()) if t is None else t, 'online': True, 'name': 'Bob',
         'level': 42, 'voc': 'Warrior', 'hp': 150, 'maxhp': 200, 'mp': 10, 'maxmp': 20, 'cap': 300, 'soul': 100,
         'pos': {'x': PX, 'y': PY, 'z': PZ}, 'x0': X0, 'y0': Y0, 'w': W, 'h': H, 'tiles': ts,
         'creatures': creatures if creatures is not None else []}
    s.update(kw)
    return s


def look(t=1, d=2, x=PX, y=PY, name='Bob', hp=100, ex=0, **o):
    oo = {'t': t, 'h': 0, 'b': 0, 'l': 0, 'f': 0, 'a': 0, 'm': 0, 'x': ex}
    oo.update(o)
    return {'x': x, 'y': y, 'name': name, 'o': oo, 'd': d, 'hp': hp, 'skull': 0, 'k': 'player'}


def at(img, wx, wy, ox=16, oy=16):
    """the view's pixel at world tile (wx, wy) plus (ox, oy); the view's top-left is tile (PX - 7, PY - 5)"""
    return img.getpixel(((wx - (PX - 7)) * 32 + ox, (wy - (PY - 5)) * 32 + oy))


def rgb(c):
    return tuple(c[:3])


def test_index(tmp, dat):
    cache = os.path.join(tmp, 'cache')
    items, outfits = sr.load_index(dat, cache)
    expect(sorted(items) == list(range(100, 108)), f'items by client id: {sorted(items)}')
    expect(sorted(outfits) == [1, 2], 'looks by look type')
    expect(items[104].flags.get('elevation') == 8, 'elevation kept')
    expect(items[100].flags.get('ground') == 1, 'ground flag kept')
    expect(outfits[1].flags.get('displacement') == (8, 8), 'displacement kept')
    expect(outfits[1].pz == 2 and len(outfits[1].sprites) == 16, 'the look: both z patterns, frame 0')
    expect(os.path.isfile(os.path.join(cache, 'dat-index.json')), 'the index is cached')
    expect(oct(os.stat(cache).st_mode & 0o777) == oct(0o700), 'the cache folder is private')
    real = sr.build_index
    sr.build_index = lambda p: (_ for _ in ()).throw(AssertionError('parsed again'))
    try:
        items2, _ = sr.load_index(dat, cache)
        expect(sorted(items2) == sorted(items), 'the second load comes from the cache')
    except AssertionError:
        expect(False, 'the second load must not parse the dat')
    finally:
        sr.build_index = real
    st = os.stat(dat)
    os.utime(dat, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))
    called = []
    sr.build_index = lambda p: (called.append(p), real(p))[1]
    try:
        sr.load_index(dat, cache)
    finally:
        sr.build_index = real
    expect(called == [dat], 'a changed dat is parsed again')
    with open(os.path.join(cache, 'dat-index.json'), 'w') as f:
        f.write('{broken')
    items3, _ = sr.load_index(dat, cache)
    expect(len(items3) == 8, 'a broken cache is rebuilt')


def test_snapshot_checks(tmp):
    p = os.path.join(tmp, 'remote.spectate')

    def write(obj):
        with open(p, 'w') as f:
            f.write(obj if isinstance(obj, str) else json.dumps(obj))

    write(snapshot())
    s = sr.read_snapshot(p, 'Bob', 5)
    expect(s['online'] is True and s['w'] == 18, 'a good snapshot')
    for bad, what in ((snapshot(watch='Alice'), 'another watch'), (snapshot(t=int(time.time()) - 60), 'too old')):
        write(bad)
        try:
            sr.read_snapshot(p, 'Bob', 5)
            expect(False, what + ' is refused')
        except sr.BadSnapshot as e:
            expect(str(e).startswith('stale'), what + ': stale')
    write({'v': 1, 'watch': 'Bob', 't': int(time.time()), 'online': False})
    expect(sr.read_snapshot(p, 'Bob', 5)['online'] is False, 'offline')
    s = snapshot(creatures={})
    write(s)
    expect(sr.read_snapshot(p, 'Bob', 5)['creatures'] == [], 'an empty creature table ({}) is an empty list')
    bads = [('{"v": 1', 'not JSON'), ('[1]', 'not an object'), (snapshot(v=2), 'another version'),
            (snapshot(w=99), 'too wide'), (snapshot(tiles=None, w=17), 'tile count'),
            (snapshot(creatures=[{'x': 1}]), 'creature without look'),
            (snapshot(creatures=[look(d=9)]), 'bad direction'), (snapshot(creatures=[look(hp=101)]), 'bad health'),
            (snapshot(creatures=[look(name='x' * 41)]), 'long name'), (snapshot(pos={'x': 'a', 'y': 1, 'z': 7}), 'pos'),
            (snapshot(t=True), 't as a boolean')]
    bad_tiles = snapshot()
    bad_tiles['tiles'][0] = [[1, 2, 3]]
    bads.append((bad_tiles, 'an item of three numbers'))
    bad_tiles = snapshot()
    bad_tiles['tiles'][0] = ['x']
    bads.append((bad_tiles, 'an item that is text'))
    for obj, what in bads:
        write(obj)
        try:
            sr.read_snapshot(p, 'Bob', 5)
            expect(False, what + ' is refused')
        except sr.BadSnapshot:
            pass
    write('x' * (sr.MAX_SNAPSHOT_BYTES + 10))
    try:
        sr.read_snapshot(p, 'Bob', 5)
        expect(False, 'a huge file is refused')
    except sr.BadSnapshot as e:
        expect('too big' in str(e), 'a huge file: too big')
    try:
        sr.read_snapshot(os.path.join(tmp, 'none'), 'Bob', 5)
        expect(False, 'a missing file is refused')
    except sr.BadSnapshot:
        pass


def test_render(dat, spr_path):
    items, outfits = sr.load_index(dat)
    spr = sr.datspr.Spr(spr_path)
    img = sr.render(snapshot(), items, outfits, spr)
    expect(img.size == (480, 352), f'the view is 15 x 11 tiles: {img.size}')
    expect(rgb(at(img, PX, PY)) == rgb(GREEN), 'ground everywhere')

    # draw order: ground listed last is still drawn first; common items oldest first; the top item over a creature
    tiles = {(PX + 2, PY): [102, 103, 100], (PX - 2, PY): [101, 100, 102], (PX + 3, PY + 2): [100, 104, 102],
             (PX - 4, PY - 3): [100, 105], (PX + 5, PY - 2): [100, [106, 3]], (PX + 5, PY + 3): [100, [106, 50]],
             (PX + 6, PY + 4): [100, 999]}
    cres = [look(x=PX - 2, y=PY, name='Rat', hp=50, d=1)]
    img = sr.render(snapshot(tiles, cres), items, outfits, spr)
    expect(rgb(at(img, PX + 2, PY)) == rgb(WHITE), 'the newest common item on top, the ground under')
    expect(rgb(at(img, PX - 2, PY, 2, 2)) == rgb(RED), 'the top item is drawn over the creature')
    expect(rgb(at(img, PX - 2, PY, 12, 12)) == rgb(EAST), 'the creature faces east')
    expect(rgb(at(img, PX + 3, PY + 2, 28, 28)) == rgb(BROWN), 'the elevation item fills its tile')
    expect(rgb(at(img, PX + 3, PY + 2, 2, 2)) == rgb(BLUE), 'what stands on it is lifted 8 px')
    expect(rgb(at(img, PX + 3, PY + 2, 26, 26)) == rgb(BROWN), '... so its own corner shows the elevation item')
    expect(rgb(at(img, PX - 5, PY - 4)) == rgb(PINK), 'a 2 x 2 item reaches its north-west neighbour')
    expect(rgb(at(img, PX - 4, PY - 3)) == rgb(PINK), 'and covers its own tile')
    expect(rgb(at(img, PX + 5, PY - 2)) == rgb(STACK[2]), 'a stack of 3: pattern 3')
    expect(rgb(at(img, PX + 5, PY + 3)) == rgb(STACK[7]), 'a stack of 50: the last pattern')
    expect(rgb(at(img, PX + 6, PY + 4)) == rgb(GREEN), 'an unknown client id is skipped')

    # the player: facing south, colours, displacement 8 (it stands 8 px up and left of its tile)
    img = sr.render(snapshot(creatures=[look()]), items, outfits, spr)
    expect(rgb(at(img, PX, PY, 10, 10)) == rgb(SOUTH), 'the player faces south, at the centre of the view')
    expect(rgb(at(img, PX, PY, 28, 28)) == rgb(GREEN), 'displaced 8 px up and left')
    expect(rgb(at(img, PX - 1, PY - 1, 28, 28)) == rgb(SOUTH), 'and reaches into the north-west neighbour')
    img = sr.render(snapshot(creatures=[look(h=114)]), items, outfits, spr)
    want = tuple((v * 36 + 127) // 255 for v in SOUTH[:3])
    expect(rgb(at(img, PX, PY, 10, 10)) == want, f'head colour 114 multiplies the art: {at(img, PX, PY, 10, 10)} {want}')
    for d, col in ((0, NORTH), (3, WEST)):
        img = sr.render(snapshot(creatures=[look(d=d)]), items, outfits, spr)
        expect(rgb(at(img, PX, PY, 10, 10)) == rgb(col), f'direction {d}')
    img = sr.render(snapshot(creatures=[look(m=2)]), items, outfits, spr)
    expect(rgb(at(img, PX, PY, 10, 10)) == rgb(MOUNTED), 'mounted: the rider pattern')
    expect(rgb(at(img, PX - 1, PY - 1, 4, 4)) == rgb(MOUNT), 'and the 2 x 2 mount under it')
    img = sr.render(snapshot(creatures=[look(t=0, ex=107)]), items, outfits, spr)
    expect(rgb(at(img, PX, PY, 28, 28)) == rgb(GREY), 'a creature that looks like an item')
    img = sr.render(snapshot(creatures=[look(t=77)]), items, outfits, spr)
    expect(rgb(at(img, PX, PY, 28, 28)) == rgb(GREEN), 'an unknown look is skipped')
    # the health bar over a creature away from others: dark frame and the health colour
    img = sr.render(snapshot(creatures=[look(x=PX + 3, y=PY + 3, hp=100, name='')]), items, outfits, spr)
    bar = at(img, PX + 3, PY + 3, 16 - 8 - 14 + 2, -8 - 6 + 1)
    expect(rgb(bar) == sr.health_colour(100), f'the health bar in the client colour: {bar}')
    # a snapshot near the map edge (the view clamps to the area)
    img = sr.render(snapshot(w=6, h=4, tiles=None) | {'tiles': [[100]] * 24}, items, outfits, spr)
    expect(img.size == (480, 352), 'a small area still gives the full view')


def test_colours():
    expect(sr.health_colour(100) == (0, 0xBC, 0), 'full health: green')
    expect(sr.health_colour(61) == (0x50, 0xA1, 0x50), 'over 60: light green')
    expect(sr.health_colour(31) == (0xA1, 0xA1, 0), 'over 30: yellow')
    expect(sr.health_colour(9) == (0xBF, 0x0A, 0x0A), 'over 8: red')
    expect(sr.health_colour(4) == (0x91, 0x0F, 0x0F), 'over 3: dark red')
    expect(sr.health_colour(1) == (0x85, 0x0C, 0x0C), 'the rest: darkest red')
    expect(sr.item_patterns(sr.Look(1, 1, 1, 4, 2, 1, {'fluid': 1}, [0] * 8), 0, 0, 0, 5) == (1, 1, 0),
           'fluid kind 5 (blood) -> colour 5 -> pattern (1, 1)')
    expect(sr.item_patterns(sr.Look(1, 1, 1, 4, 2, 1, {'splash': 1}, [0] * 8), 0, 0, 0, 10) == (2, 0, 0),
           'fluid kind 10 (life) -> colour 2 (red)')
    expect(sr.item_patterns(sr.Look(1, 1, 1, 2, 2, 2, {}, [0] * 8), 3, 4, 7, None) == (1, 0, 1),
           'positional patterns by the world position')


def run_main(args):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = sr.main(args)
    return code, buf.getvalue()


def test_main(tmp, dat, spr):
    p = os.path.join(tmp, 'snap.json')
    with open(p, 'w') as f:
        json.dump(snapshot(creatures=[look()]), f)
    base = ['render', '--dat', dat, '--spr', spr, '--snapshot', p, '--cache-dir', os.path.join(tmp, 'c2')]
    code, out = run_main(base + ['--watch', 'Bob'])
    expect(code == 0 and out.count('\n') == 1, 'one line')
    a = json.loads(out)
    expect(a['ok'] is True and a['name'] == 'Bob' and a['level'] == 42 and a['hp'] == 150, 'the stats')
    expect(a['pos'] == [PX, PY, PZ] and a['w'] == 480 and a['h'] == 352, 'position and size')
    png = base64.b64decode(a['png'])
    expect(png[:8] == b'\x89PNG\r\n\x1a\n', 'a PNG')
    im = Image.open(io.BytesIO(png))
    expect(im.size == (480, 352), 'of the view')
    expect(rgb(im.convert('RGB').getpixel((7 * 32 + 10, 5 * 32 + 10))) == rgb(SOUTH), 'the player at the centre')
    expect(len(png) < 60000, f'small: {len(png)} bytes')
    code, out = run_main(base + ['--watch', 'Alice'])
    expect(code == 1 and json.loads(out)['error'] == 'stale', 'another watch: stale')
    code, out = run_main(base + ['--watch', 'Bob;rm'])
    expect(code == 1 and json.loads(out)['error'] == 'bad-name', 'a bad name')
    with open(p, 'w') as f:
        json.dump({'v': 1, 'watch': 'Bob', 't': int(time.time()), 'online': False}, f)
    code, out = run_main(base + ['--watch', 'Bob'])
    expect(code == 0 and json.loads(out)['error'] == 'offline', 'offline: exit 0, error offline')
    code, out = run_main(['render', '--dat', dat + '.x', '--spr', spr, '--snapshot', p, '--watch', 'Bob'])
    expect(code == 1 and json.loads(out)['error'] == 'no-pair', 'no pair')
    code, out = run_main(['info', '--dat', dat, '--spr', spr, '--cache-dir', os.path.join(tmp, 'c2')])
    expect('pair=yes' in out and 'index=yes' in out and 'dat_md5=' in out, 'info: ' + out)


def make_archive(tmp, members, part_size=700):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode='w') as tar:
        for name, data, kind in members:
            ti = tarfile.TarInfo(name)
            if kind == 'link':
                ti.type = tarfile.SYMTYPE
                ti.linkname = data
                tar.addfile(ti)
            else:
                ti.size = len(data)
                tar.addfile(ti, io.BytesIO(data))
    blob = lzma.compress(raw.getvalue(), format=lzma.FORMAT_XZ)
    d = os.path.join(tmp, 'things')
    os.makedirs(d, exist_ok=True)
    parts = []
    for i in range(0, len(blob), part_size):
        name = os.path.join(d, 'things-1098.tar.xz.part' + 'abcdefghijklmnopqrstuvwxyz'[i // part_size // 26]
                            + 'abcdefghijklmnopqrstuvwxyz'[i // part_size % 26])
        with open(name, 'wb') as f:
            f.write(blob[i:i + part_size])
        parts.append(name)
    import hashlib
    sums = os.path.join(tmp, 'SHA256SUMS.parts')
    with open(sums, 'w') as f:
        for p in parts:
            f.write(hashlib.sha256(open(p, 'rb').read()).hexdigest() + '  things/' + os.path.basename(p) + '\n')
    return parts, sums


def test_unpack(tmp):
    dat_bytes, spr_bytes = os.urandom(3000), os.urandom(5000)
    a = os.path.join(tmp, 'arch')
    parts, sums = make_archive(a, [('pair/../../evil', b'x', 'file'), ('./x/Tibia.dat', '/etc/passwd', 'link'),
                                   ('./Tibia.dat', dat_bytes, 'file'), ('./Tibia.spr', spr_bytes, 'file'),
                                   ('./other.txt', b'y', 'file')])
    expect(len(parts) > 2, 'the archive is split into parts')
    out = os.path.join(tmp, 'pair.new')
    got = sr.unpack_pair(list(reversed(parts)), sums, out)
    expect(open(got[0], 'rb').read() == dat_bytes and open(got[1], 'rb').read() == spr_bytes, 'both files, joined in order')
    expect(sorted(os.listdir(out)) == ['Tibia.dat', 'Tibia.spr'], 'nothing else in the folder')
    expect(not os.path.exists(os.path.join(tmp, 'evil')) and not os.path.exists(os.path.join(a, 'evil')),
           'nothing written outside it')
    expect(not os.path.islink(got[0]), 'a link named Tibia.dat is not followed')
    # a changed part, a part missing from the sums, an archive without the spr
    with open(parts[1], 'r+b') as f:
        first = f.read(1)
        f.seek(0)
        f.write(bytes([first[0] ^ 0xff]))  # always a different byte (writing a 0 left a part that began with 0 as it was)
    for args, what in (((parts, sums, os.path.join(tmp, 'p2')), 'a changed part'),):
        try:
            sr.unpack_pair(*args)
            expect(False, what + ' is refused')
        except SystemExit as e:
            expect('does not match' in str(e), what + ': ' + str(e))
    expect(not os.path.exists(os.path.join(tmp, 'p2')), 'nothing unpacked from a changed part')
    b = os.path.join(tmp, 'arch2')
    parts, sums = make_archive(b, [('Tibia.dat', b'd', 'file')])
    extra = os.path.join(b, 'things', 'things-1098.tar.xz.partzz')
    open(extra, 'wb').write(b'')
    try:
        sr.unpack_pair(parts + [extra], sums, os.path.join(tmp, 'p3'))
        expect(False, 'a part not in the sums is refused')
    except SystemExit as e:
        expect('not in' in str(e), 'not in the sums: ' + str(e))
    try:
        sr.unpack_pair(parts, sums, os.path.join(tmp, 'p4'))
        expect(False, 'an archive without Tibia.spr is refused')
    except SystemExit as e:
        expect('Tibia.spr' in str(e), 'no spr: ' + str(e))


def main():
    with tempfile.TemporaryDirectory() as tmp:
        dat, spr = make_pair(os.path.join(tmp, 'pair'))
        test_index(tmp, dat)
        test_snapshot_checks(tmp)
        test_render(dat, spr)
        test_colours()
        test_main(tmp, dat, spr)
        test_unpack(tmp)
    if FAILS:
        print(f'spectate_render_test: {len(FAILS)} failures')
        return 1
    print('spectate_render_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())

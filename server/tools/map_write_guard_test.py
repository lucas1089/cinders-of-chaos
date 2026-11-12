#!/usr/bin/env python3
"""python3 -I server/tools/map_write_guard_test.py : map_write_guard.py on synthetic OTBM pairs (server/README.md
"Map write guard (O512)"): identical maps; the intended change only (add, rewrite, remove) passes; one extra tile
changed outside the set, an item attribute changed outside, a tile removed outside, a tile added outside, a tile
written twice are refused with the coordinate named; a tile that is not what the writer meant; a towns node changed
without permission is refused and with permission passes (and its node count may not move under `allow_content`);
truncated files, stray bytes, a dangling escape, a compressed file; escaped bytes in coordinates and item ids; the
same verdicts when the file is read in many small chunks; the text-only mode; the first 20 coordinates are named."""
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import map_write_guard as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


from map_guard_testkit import esc, node, item, tile_node, text_attr, build, world  # noqa: E402


def write(d, name, data):
    p = os.path.join(d, name)
    open(p, 'wb').write(data)
    return p


def verdict(old, new, **kw):
    try:
        G.check(old, new, **kw)
        return None
    except G.GuardError as e:
        return str(e)


def main():
    d = tempfile.mkdtemp(prefix='map_guard_test_')
    base = world()
    old = write(d, 'old.otbm', build(base))
    # identical
    check(verdict(old, write(d, 'same.otbm', build(base))) is None, 'identical maps pass')
    # intended change only: one tile rewritten, one added, one removed
    p_chg, p_add, p_rem = (1003, 1003, 7), (2000, 2000, 7), (1007, 1002, 7)
    t2 = dict(base)
    t2[p_chg] = [item(555)]
    t2[p_add] = [item(556)]
    del t2[p_rem]
    new = write(d, 'new.otbm', build(t2))
    exp = {p_chg: tile_node(p_chg, [item(555)]), p_add: tile_node(p_add, [item(556)])}
    st = G.check(old, new, add=[p_add], change=[p_chg], remove=[p_rem], expect=exp)
    check(st['old_tiles'] == 41 and st['new_tiles'] == 41 and st['added'] == 1 and st['changed'] == 1 and st['removed'] == 1,
          'intended change passes with its counts: %s' % st)
    # the same change reported to the wrong sets
    check(verdict(old, new, add=[p_add], change=[p_chg]) is not None, 'a removed tile that is not in the sets is refused')
    check('1007,1002,7' in (verdict(old, new, add=[p_add], change=[p_chg]) or ''), 'the removed tile is named')
    check(verdict(old, new, add=[p_add, p_chg], remove=[p_rem]) is not None, 'a rewrite reported as an add is refused')
    check(verdict(old, new, add=[p_add], change=[p_chg, (1, 1, 1)], remove=[p_rem]) is not None, 'a change of a tile the old map lacks is refused')
    check('is not on the old map' in (verdict(old, new, add=[p_add], change=[p_chg, (1, 1, 1)], remove=[p_rem]) or ''), 'and says why')
    check(verdict(old, new, add=[p_add], change=[p_chg], remove=[p_rem, p_add]) is not None, 'overlapping sets are refused')
    # expect: the writer meant other bytes
    bad_exp = dict(exp)
    bad_exp[p_chg] = tile_node(p_chg, [item(777)])
    v = verdict(old, new, add=[p_add], change=[p_chg], remove=[p_rem], expect=bad_exp)
    check(v is not None and '1003,1003,7' in v and 'not what the writer meant' in v, 'a tile that is not what the writer meant: %s' % v)
    # one extra tile changed outside the set
    far = (1030, 1000, 7)
    t3 = dict(t2)
    t3[far] = [item(999)]
    v = verdict(old, write(d, 'far.otbm', build(t3)), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and '1030,1000,7: tile changed outside' in v, 'an extra changed tile is refused and named: %s' % v)
    # an item attribute changed outside (the action id)
    t4 = dict(t2)
    t4[(1010, 1000, 7)] = [item(110), item(2010, bytes([4]) + struct.pack('<H', 47999))]
    v = verdict(old, write(d, 'attr.otbm', build(t4)), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and '1010,1000,7' in v, 'a changed item attribute outside is refused: %s' % v)
    # an item text changed outside, text-only off and on
    t4b = dict(t2)
    t4b[(1005, 1000, 6)] = [item(300, text_attr(6, b'another sign text'))]
    pt = write(d, 'text.otbm', build(t4b))
    v = verdict(old, pt, add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and '1005,1000,6' in v, 'a changed text is refused by default: %s' % v)
    check(verdict(old, pt, add=[p_add], change=[p_chg], remove=[p_rem], text_only=True) is None, 'a changed text passes in text-only mode')
    t4c = dict(t4b)
    t4c[(1005, 1000, 6)] = [item(301, text_attr(6, b'another sign text'))]
    v = verdict(old, write(d, 'text_id.otbm', build(t4c)), add=[p_add], change=[p_chg], remove=[p_rem], text_only=True)
    check(v is not None and '1005,1000,6' in v, 'a changed item id is refused even in text-only mode: %s' % v)
    t4d = dict(t4b)
    t4d[(1005, 1000, 6)] = [item(300, text_attr(6, b'x') + bytes([4]) + struct.pack('<H', 1))]
    v = verdict(old, write(d, 'text_aid.otbm', build(t4d)), add=[p_add], change=[p_chg], remove=[p_rem], text_only=True)
    check(v is not None and '1005,1000,6' in v, 'an added action id is refused in text-only mode: %s' % v)
    # a tile removed outside the set
    t5 = dict(t2)
    del t5[(1011, 1001, 7)]
    v = verdict(old, write(d, 'gone.otbm', build(t5)), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and '1011,1001,7: tile removed outside' in v, 'a tile removed outside is refused and named: %s' % v)
    # a tile added outside the set
    t6 = dict(t2)
    t6[(3000, 3000, 7)] = [item(1)]
    v = verdict(old, write(d, 'extra.otbm', build(t6)), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and '3000,3000,7: tile added outside' in v, 'a tile added outside is refused and named: %s' % v)
    # a tile written twice
    dup = build(t2)
    twice = dict(t2)
    data = build(t2)
    # the same area twice: append the tile of p_add a second time inside its area by building it by hand
    twice[p_add] = tile_node(p_add, [item(556)]) + tile_node(p_add, [item(556)])
    v = verdict(old, write(d, 'twice.otbm', build(twice)), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and '2000,2000,7: the new map holds this tile twice' in v, 'a tile written twice is refused: %s' % v)
    # a tile of the add set that was not written
    v = verdict(old, new, add=[p_add, (5, 5, 5)], change=[p_chg], remove=[p_rem])
    check(v is not None and '5,5,5: add: the tile was not written' in v, 'an add that was not written is refused: %s' % v)
    # a tile of the remove set that is still there
    v = verdict(old, old, remove=[(1001, 1001, 7)])
    check(v is not None and 'still on the new map' in v, 'a remove that is still there is refused: %s' % v)
    # towns: changed without permission, with permission
    tw = write(d, 'towns.otbm', build(t2, towns=((1, b'Ashgate'),)))
    v = verdict(old, tw, add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and 'towns changed content' in v, 'a renamed town without permission is refused: %s' % v)
    check(verdict(old, tw, add=[p_add], change=[p_chg], remove=[p_rem], allow_nodes=['towns']) is None, 'a renamed town with permission passes')
    check(verdict(old, tw, add=[p_add], change=[p_chg], remove=[p_rem], allow_content=['towns']) is None,
          'content-only permission lets a name change')
    tw2 = write(d, 'towns2.otbm', build(t2, towns=((1, b'Cinderhold'), (2, b'Ashgate'))))
    v = verdict(old, tw2, add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and 'towns changed' in v, 'a new town without permission is refused: %s' % v)
    v = verdict(old, tw2, add=[p_add], change=[p_chg], remove=[p_rem], allow_content=['towns'])
    check(v is not None and 'towns changed' in v, 'content-only permission does not let the count move: %s' % v)
    check(verdict(old, tw2, add=[p_add], change=[p_chg], remove=[p_rem], allow_nodes=['towns']) is None, 'a new town with full permission passes')
    wp = write(d, 'way.otbm', build(t2, waypoints=(b'temple',)))
    v = verdict(old, wp, add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and 'waypoints' in v, 'a waypoints node appearing is refused: %s' % v)
    check(verdict(old, wp, add=[p_add], change=[p_chg], remove=[p_rem], allow_nodes=['waypoints']) is None, 'and passes with permission')
    # the header
    hd = build(t2).replace(b'test map', b'test mab', 1)
    v = verdict(old, write(d, 'head.otbm', hd), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and 'header' in v, 'a changed header is refused: %s' % v)
    # truncated, stray bytes, dangling escape, compressed, empty
    full = build(t2)
    for cut, name in ((len(full) - 1, 'one byte short'), (len(full) - 2, 'two bytes short'), (len(full) // 2, 'half'), (9, 'header only')):
        v = verdict(old, write(d, 'cut.otbm', full[:cut]), add=[p_add], change=[p_chg], remove=[p_rem])
        check(v is not None and ('truncated' in v or 'escape' in v or 'node' in v), 'truncated (%s) is refused: %s' % (name, v))
    v = verdict(old, write(d, 'stray.otbm', full + b'\x00'), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and 'after' in v, 'a stray byte after the root is refused: %s' % v)
    v = verdict(old, write(d, 'stray2.otbm', full + b'\xFF'), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and ('after' in v or 'never opened' in v), 'a stray close after the root is refused: %s' % v)
    v = verdict(old, write(d, 'dangle.otbm', full + b'\xFD'), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None, 'a dangling escape is refused: %s' % v)
    v = verdict(old, write(d, 'gz.otbm', b'\x1f\x8b' + full[2:]), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None and 'compressed' in v, 'a compressed file is refused: %s' % v)
    v = verdict(old, write(d, 'empty.otbm', b''), add=[p_add], change=[p_chg], remove=[p_rem])
    check(v is not None, 'an empty file is refused: %s' % v)
    v = verdict(write(d, 'oldcut.otbm', full[:-3]), new)
    check(v is not None and 'oldcut' in v, 'a truncated OLD map is refused and named: %s' % v)
    # escaped bytes: coordinates 253..255 inside the area, item ids whose bytes are 0xFD..0xFF
    esc_t = {(256 + 0xFD, 512 + 0xFE, 7): [item(0xFEFD)], (256 + 0xFF, 512 + 0xFF, 7): [item(0xFFFE, bytes([4, 0xFD, 0xFE]))],
             (256 + 0xFC, 512 + 0xFD, 7): [item(0xFDFF)], (256, 512, 7): [item(1)]}
    e_old = write(d, 'e_old.otbm', build(esc_t))
    check(verdict(e_old, write(d, 'e_same.otbm', build(esc_t))) is None, 'escaped coordinates and ids: identical passes')
    e_new = dict(esc_t)
    e_new[(256 + 0xFF, 512 + 0xFF, 7)] = [item(0xFFFE, bytes([4, 0xFD, 0xFD]))]
    v = verdict(e_old, write(d, 'e_new.otbm', build(e_new)))
    check(v is not None and '%d,%d,7' % (256 + 0xFF, 512 + 0xFF) in v, 'a change under escaped coordinates names the right tile: %s' % v)
    check(verdict(e_old, write(d, 'e_new2.otbm', build(e_new)), change=[(256 + 0xFF, 512 + 0xFF, 7)]) is None,
          'and passes when it is the intended one')
    # chunking: the same verdicts when the files are read in small pieces
    big = {}
    for i in range(2500):
        big[(1000 + i % 300, 1000 + i // 300, 7 + (i % 3))] = [item(100 + i % 50), item(3000 + i % 7, bytes([4]) + struct.pack('<H', i))]
    b_old = write(d, 'b_old.otbm', build(big))
    big2 = dict(big)
    big2[(1100, 1004, 8)] = [item(5)]
    del big2[(1003, 1000, 7)]
    big2[(2000, 2000, 7)] = [item(6)]
    b_new = write(d, 'b_new.otbm', build(big2))
    ok_args = dict(add=[(2000, 2000, 7)], change=[(1100, 1004, 8)], remove=[(1003, 1000, 7)])
    ref = G.CHUNK
    for chunk in (ref, 4096, 1000, 257, 64):
        G.CHUNK = chunk
        v = verdict(b_old, b_new, **ok_args)
        check(v is None, 'chunk %d: the intended change passes: %s' % (chunk, v))
        v = verdict(b_old, b_new, add=[(2000, 2000, 7)], change=[(1100, 1004, 8)])
        check(v is not None and '1003,1000,7' in v, 'chunk %d: a tile removed outside is named: %s' % (chunk, v))
        s1, s2 = G.scan(b_old), G.scan(b_new)
        check(len(s1.keys) == 2500 and len(s2.keys) == 2500, 'chunk %d: tile counts %d %d' % (chunk, len(s1.keys), len(s2.keys)))
        check(verdict(b_old, write(d, 'b_cut.otbm', open(b_new, 'rb').read()[:-5]), **ok_args) is not None, 'chunk %d: truncated is refused' % chunk)
    G.CHUNK = ref
    # the first 20 differences are named, the rest counted
    many = dict(base)
    for i in range(40):
        many[(1000 + i, 1000 + (i % 5), 7)] = [item(9000 + i)]
    v = verdict(old, write(d, 'many.otbm', build(many)))
    check(v is not None and '40 difference(s)' in v and 'first 20' in v and v.count('tile changed outside') == 20,
          'twenty coordinates are named of 40: %s' % (v or '')[:300])
    # the pure same-map check on the command line
    check(G.main([old, os.path.join(d, 'same.otbm')]) == 0, 'main: identical maps exit 0')
    check(G.main([old, new]) == 1, 'main: different maps exit 1')
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    os.rmdir(d)
    print('map_write_guard_test: %s' % ('FAILED %d' % failed if failed else 'ok'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

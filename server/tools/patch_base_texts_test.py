#!/usr/bin/env python3
"""python3 -I server/tools/patch_base_texts_test.py : the map part of patch_base_texts.py (--map-only) on a synthetic
map, and its map write guard (O512): the texts and descriptions of items get the new name, every tile stays where it
is with the same items and attributes, the .bak is made and no .tmp is left; a second run changes nothing; a writer
that also changes an item id on a far tile, and one that moves an action id, are refused before anything is written:
the map stays and the .tmp stays for inspection. No base server needed (numpy for the guard)."""
import io
import os
import shutil
import struct
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_texts as T  # noqa: E402
import base_rename_lib as L  # noqa: E402
import map_guard_testkit as K  # noqa: E402
import map_write_guard as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(argv):
    out = io.StringIO()
    with redirect_stdout(out):
        code = T.main(argv)
    return code, out.getvalue()


def own_blocks():
    """V44 (seen in a client, 2026-11-27): the store sold "Ananne Window Wings". The marked Chaos blocks our installers
    write into wings.xml / auras.xml are ours: a base line outside the block gets the new name, the block stays."""
    root = tempfile.mkdtemp(prefix='base_texts_blocks_')
    try:
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'XML'))
        wx = os.path.join(data, 'XML', 'wings.xml')
        block = ('\t<!-- Chaos wings (server/tools/install_outfits.py, do not edit by hand) -->\n'
                 '\t<wing id="96" clientid="2451" name="Zorgfell Window Wings" speed="20" />\n'
                 '\t<!-- end of the Chaos wings -->\n')
        open(wx, 'w').write('<?xml version="1.0"?>\n<wings>\n\t<wing id="1" clientid="937" name="Zorgfell Wings" />\n'
                            + block + '</wings>\n')
        ax = os.path.join(data, 'XML', 'auras.xml')
        ablock = ('\t<!-- Chaos auras (server/tools/install_auras.py, do not edit by hand) -->\n'
                  '\t<aura id="64" clientid="2508" name="Zorgfell Hairpin" speed="20" />\n'
                  '\t<!-- end of the Chaos auras -->\n')
        open(ax, 'w').write('<auras>\n' + ablock + '\t<aura id="2" clientid="9" name="Zorgfell Glow" />\n</auras>\n')
        names = os.path.join(root, 'names.csv')
        open(names, 'w').write('sha256,name,kind,match\n%s,Ashfell,place,word\n' % L.digest('Zorgfell'))
        npc = os.path.join(root, 'npc.csv')
        open(npc, 'w').write('sha256,name,kind,match\n')
        mon = os.path.join(root, 'mon.csv')
        open(mon, 'w').write('sha256,name,kind\n')
        args = [data, '--no-map', '--names', names, '--npc-names', npc, '--monster-names', mon]
        code, out = run(args)
        w, a = open(wx).read(), open(ax).read()
        check(code == 0 and 'name="Ashfell Wings"' in w and 'name="Ashfell Glow"' in a, 'base lines renamed: %s' % out)
        check(block in w and ablock in a, 'the Chaos blocks stay as written: %s %s' % (w, a))
        code, _out = run(args)
        check(code == 0 and open(wx).read() == w and open(ax).read() == a, 'a second run changes nothing')
        check(T.outside_own_blocks('x' + block + 'y', str.upper) == 'X' + block + 'Y', 'outside_own_blocks keeps the block')
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    root =tempfile.mkdtemp(prefix='base_texts_test_')
    try:
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        aid = bytes([4]) + struct.pack('<H', 4711)
        tiles = K.world(12)
        tiles[(2000, 2000, 7)] = [K.item(500, K.text_attr(6, b'Welcome to Zorgfell, traveller') + aid + bytes([15, 3]))]
        tiles[(2001, 2000, 7)] = [K.item(501, K.text_attr(7, b'The road to Zorgfell') + bytes([99, 1, 2]))]   # an unknown attribute: left alone
        tiles[(2002, 2000, 7)] = [K.item(502, K.text_attr(7, b'The road to Zorgfell'))]
        orig = K.build(tiles)
        open(mp, 'wb').write(orig)
        names = os.path.join(root, 'names.csv')
        open(names, 'w').write('sha256,name,kind,match\n%s,Ashfell,place,word\n' % L.digest('Zorgfell'))
        npc = os.path.join(root, 'npc.csv')
        open(npc, 'w').write('sha256,name,kind,match\n')
        mon = os.path.join(root, 'mon.csv')
        open(mon, 'w').write('sha256,name,kind\n')
        args = [data, '--map-only', '--map', mp, '--names', names, '--npc-names', npc, '--monster-names', mon]
        code, _out = run(args + ['--dry-run'])
        check(code == 0 and open(mp, 'rb').read() == orig and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        code, out = run(args)
        new = open(mp, 'rb').read()
        check(code == 0 and new != orig and b'Zorgfell' in new and b'Welcome to Ashfell, traveller' in new
              and b'The road to Ashfell' in new, 'the texts get the new name: %s' % out)
        check('map write guard' in out and '2 with a new item text' in out, 'the guard ran and said so: %s' % out)
        check(open(mp + '.bak', 'rb').read() == orig and not os.path.exists(mp + '.tmp'), '.bak made, no .tmp left')
        check(aid in new and bytes([99, 1, 2]) in new, 'the action id and the unknown attribute are kept')
        check(G.scan(mp).keys.tolist() == G.scan(mp + '.bak').keys.tolist(), 'the same tiles')
        code, out = run(args)
        check(code == 0 and open(mp, 'rb').read() == new, 'a second run changes nothing: %s' % out[-200:])
        # faults: refused before anything is written
        real = T.patch_map
        far = {}

        def with_far_tile(raw, ren):
            out_, n, u = real(raw, ren)
            bad, far['pos'] = K.corrupt_far_item(out_, {(2000, 2000, 7), (2002, 2000, 7)})
            return bad, n, u

        def with_aid_moved(raw, ren):
            out_, n, u = real(raw, ren)
            return out_.replace(aid, bytes([4]) + struct.pack('<H', 4712), 1), n, u

        for name, fault in (('a far tile', with_far_tile), ('a moved action id', with_aid_moved)):
            open(mp, 'wb').write(orig)
            if os.path.exists(mp + '.tmp'):
                os.remove(mp + '.tmp')
            T.patch_map = fault
            try:
                code, out = run(args)
            finally:
                T.patch_map = real
            check(code == 1 and 'tile changed outside' in out, '%s: refused: %s' % (name, out[-300:]))
            if name == 'a far tile':
                check('%d,%d,%d' % far['pos'] in out, '%s: the tile is named' % name)
            check(open(mp, 'rb').read() == orig and os.path.exists(mp + '.tmp'), '%s: the map is as it was, the .tmp stays' % name)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    own_blocks()
    print('patch_base_texts_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

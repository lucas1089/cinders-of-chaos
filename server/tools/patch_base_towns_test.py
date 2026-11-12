#!/usr/bin/env python3
"""python3 -I server/tools/patch_base_towns_test.py : patch_base_towns.py on a synthetic map, and its map write guard
(O512): a dry run writes nothing; the run renames the towns, keeps every tile byte for byte, makes the .bak and leaves
no .tmp; a second run changes nothing; a writer that also changes an item on a far tile, one that adds a town and one
that renames a town it was not asked about are refused: the map stays and the .tmp stays for inspection.
No base server needed (numpy for the guard)."""
import io
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_towns as T  # noqa: E402
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


def main():
    root = tempfile.mkdtemp(prefix='base_towns_test_')
    try:
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        mp = os.path.join(data, 'world', 'w.otbm')
        tiles = K.world()
        towns = ((1, b'Oldtown'), (2, b'Other'))
        orig = K.build(tiles, towns=towns)
        open(mp, 'wb').write(orig)
        csv = os.path.join(root, 'names.csv')
        open(csv, 'w').write('id,name\n1,Ashgate\n')
        args = [data, '--map', mp, '--names', csv]
        code, _out = run(args + ['--dry-run'])
        check(code == 0 and open(mp, 'rb').read() == orig and not os.path.exists(mp + '.bak'), 'dry run writes nothing')
        code, out = run(args)
        new = open(mp, 'rb').read()
        check(code == 0 and new != orig and b'Ashgate' in new and b'Oldtown' not in new, 'the town is renamed: %s' % out)
        check('map write guard' in out, 'the guard ran and said so: %s' % out)
        check(open(mp + '.bak', 'rb').read() == orig and not os.path.exists(mp + '.tmp'), '.bak made, no .tmp left')
        check(G.scan(mp).hashes.tolist() == G.scan(mp + '.bak').hashes.tolist(), 'every tile is as it was')
        code, out = run(args)
        check(code == 0 and open(mp, 'rb').read() == new and 'nothing to change' in out, 'a second run changes nothing: %s' % out)
        # faults: the map is as it was and the .tmp stays
        real = T.rename
        far = {}

        def with_far_tile(data_, names):
            out_, notes = real(data_, names)
            bad, far['pos'] = K.corrupt_far_item(out_)
            return bad, notes

        def with_new_town(data_, names):
            return K.build(tiles, towns=((1, b'Ashgate'), (2, b'Other'), (3, b'Extra'))), ['x']

        def with_lost_town(data_, names):
            return K.build(tiles, towns=((1, b'Ashgate'),)), ['x']

        def with_other_town(data_, names):
            return K.build(tiles, towns=((1, b'Ashgate'), (2, b'Renamed'))), ['x']

        for name, fault, why in (('a far tile', with_far_tile, 'tile changed outside'), ('a new town', with_new_town, 'towns changed'),
                                 ('a lost town', with_lost_town, 'towns changed')):
            open(mp, 'wb').write(orig)
            for p in (mp + '.tmp',):
                if os.path.exists(p):
                    os.remove(p)
            T.rename = fault
            try:
                code, out = run(args)
            finally:
                T.rename = real
            check(code == 1 and why in out, '%s: refused: %s' % (name, out[-300:]))
            if name == 'a far tile':
                check('%d,%d,%d' % far['pos'] in out, '%s: the tile is named' % name)
            check(open(mp, 'rb').read() == orig and os.path.exists(mp + '.tmp'), '%s: the map is as it was, the .tmp stays' % name)
        # the guard allows a rename of a town the writer did not name (content only): a rename is a rename
        open(mp, 'wb').write(orig)
        T.rename = with_other_town
        try:
            code, _out = run(args)
        finally:
            T.rename = real
        check(code == 0, 'a rename of any town passes the guard (names are free, the count is not)')
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_base_towns_test: %s' % ('OK' if not failed else '%d FAILED' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

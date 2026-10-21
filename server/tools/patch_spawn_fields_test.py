#!/usr/bin/env python3
"""python3 -I server/tools/patch_spawn_fields_test.py : patch_spawn_fields.py on a synthetic tiny map: the burning fire
fields on the listed spots become the small fire, every field off the spots and every other item stay, two fields on
one spot both change, a spot without a burning field is listed and left alone, a dry run writes nothing, --out writes
only the copy, a second run changes nothing, the map otherwise keeps its bytes, items.xml whose small fire does damage
(or whose burning field does not) is refused. Also: the tool's ids and spots are the ones of server/README.md "Spawns
on fire fields". No base server needed."""
import os, shutil, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_spawn_fields as T  # noqa: E402
import install_content_areas as IC  # noqa: E402
import gen_poi as G  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def otbm_file(tiles):
    esc = IC._esc
    root = b'\xFE' + esc(bytes([0]) + struct.pack('<IHHII', 2, 65000, 65000, 3, 57))
    md = b'\xFE' + esc(bytes([2]))
    towns = b'\xFE' + esc(bytes([12])) + b'\xFF'
    return b'\x00\x00\x00\x00' + root + md + IC.tile_nodes(tiles) + towns + b'\xFF\xFF'


ITEMS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<items>
	<item id="1487" article="a" name="fire">
		<attribute key="type" value="magicfield" />
		<attribute key="decayTo" value="1488" />
		<attribute key="field" value="fire">
			<attribute key="initdamage" value="20" />
			<attribute key="damage" value="10" />
		</attribute>
	</item>
	<item id="1488" article="a" name="fire">
		<attribute key="type" value="magicfield" />
		<attribute key="field" value="fire">
			<attribute key="damage" value="10" />
		</attribute>
	</item>
	<item id="1489" article="a" name="fire">
		<attribute key="type" value="magicfield" />
		<attribute key="decayTo" value="0" />
		<attribute key="field" value="fire" />
	</item>
	<item id="1490" name="poison gas">
		<attribute key="type" value="magicfield" />
		<attribute key="field" value="poison">
			<attribute key="damage" value="5" />
		</attribute>
	</item>
</items>
"""

GROUND, STONE = 100, 3622
SPOTS = ((10, 10, 7), (12, 10, 7), (300, 300, 6), (14, 10, 7))
tiles = {
    (10, 10, 7): dict(ground=GROUND, items=[(1487, {}), (STONE, {})], flags=0),   # a burning field on a spot
    (12, 10, 7): dict(ground=GROUND, items=[(1488, {}), (1487, {})], flags=0),    # two on one spot
    (300, 300, 6): dict(ground=GROUND, items=[(1487, {})], flags=0),              # another area node
    (14, 10, 7): dict(ground=GROUND, items=[(1489, {})], flags=0),                # a spot already harmless
    (11, 10, 7): dict(ground=GROUND, items=[(1487, {})], flags=0),                # off the spots: stays
    (16, 10, 7): dict(ground=GROUND, items=[(1490, {})], flags=0),                # poison off the spots: stays
    (10, 10, 6): dict(ground=GROUND, items=[(1488, {})], flags=0),                # a spot's x, y on another floor
}

tmp = tempfile.mkdtemp(prefix='chaos_spawnfields_')
try:
    data_dir = os.path.join(tmp, 'data')
    os.makedirs(os.path.join(data_dir, 'world'))
    os.makedirs(os.path.join(data_dir, 'items'))
    xml = os.path.join(data_dir, 'items', 'items.xml')
    open(xml, 'w', encoding='utf-8').write(ITEMS_XML)
    mp = os.path.join(data_dir, 'world', 'map.otbm')
    orig = otbm_file(tiles)
    open(mp, 'wb').write(orig)
    logs = []
    run = lambda **kw: T.run(data_dir, map_path=mp, spots=SPOTS, log=logs.append, **kw)

    # what is found
    found = T.find_fields(orig, T.FIELD_FROM, SPOTS)
    check(sorted(f[2] for f in found) == [(10, 10, 7), (12, 10, 7), (12, 10, 7), (300, 300, 6)],
          'four burning fields on three spots: %s' % [f[2] for f in found])
    check(T.fire_fields(xml) == {1487: True, 1488: True, 1489: False}, 'fire fields of items.xml: %s' % T.fire_fields(xml))

    # dry run: nothing written
    s = run(dry=True)
    check(s['changed'] == 4, 'dry run counts 4')
    check(open(mp, 'rb').read() == orig, 'dry run writes nothing')
    check(not os.path.exists(mp + '.bak'), 'dry run: no backup')
    check(any('14,10,7' in line for line in logs), 'the spot without a burning field is listed')

    # --out: the patched copy elsewhere, the map untouched
    out = os.path.join(tmp, 'copy.otbm')
    run(dry=True, out=out)
    check(open(mp, 'rb').read() == orig and os.path.isfile(out), '--out writes the copy only')

    # the run
    s = run()
    check(s['changed'] == 4 and s['spots'] == [(10, 10, 7), (12, 10, 7), (300, 300, 6)], 'four replaced: %s' % s)
    new = open(mp, 'rb').read()
    check(open(mp + '.bak', 'rb').read() == orig, 'backup of the old map')
    check(new == open(out, 'rb').read(), 'the same bytes as the --out copy')
    check(len(new) == len(orig), 'same length')
    want = dict(tiles)
    for p in ((10, 10, 7), (12, 10, 7), (300, 300, 6)):
        t = dict(tiles[p])
        t['items'] = [(T.FIELD_TO if i in T.FIELD_FROM else i, a) for i, a in t['items']]
        want[p] = t
    check(new == otbm_file(want), 'byte for byte the map with the small fire on the spots')
    got = sorted(G.find_items(new, [1487, 1488]))
    check(got == [(1487, (11, 10, 7)), (1488, (10, 10, 6))], 'fields off the spots stay: %s' % got)
    check(sorted(G.find_items(new, [STONE, 1490])) == [(1490, (16, 10, 7)), (STONE, (10, 10, 7))], 'other items stay')

    # second run: nothing
    s = run()
    check(s['changed'] == 0 and open(mp, 'rb').read() == new, 'second run changes nothing')

    # items.xml checks: the small fire must do no damage, the burning ones must
    open(mp, 'wb').write(orig)
    for bad in (ITEMS_XML.replace('<attribute key="field" value="fire" />',
                                  '<attribute key="field" value="fire"><attribute key="damage" value="1" /></attribute>'),
                ITEMS_XML.replace('<attribute key="damage" value="10" />\n\t\t</attribute>\n\t</item>\n\t<item id="1489"',
                                  '</attribute>\n\t</item>\n\t<item id="1489"')):
        check(bad != ITEMS_XML, 'the bad items.xml differs')
        open(xml, 'w', encoding='utf-8').write(bad)
        try:
            run()
            check(False, 'a bad items.xml: refused')
        except T.FieldError:
            check(open(mp, 'rb').read() == orig, 'refused: nothing written')
    os.remove(xml)
    try:
        run()
        check(False, 'no items.xml: refused')
    except T.FieldError:
        pass
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# the tool's numbers (server/README.md "Spawns on fire fields")
check(T.FIELD_FROM == (1487, 1488) and T.FIELD_TO == 1489, 'ids 1487, 1488 -> 1489')
check(len(T.SPOTS) == 9 and len(set(T.SPOTS)) == 9, 'nine spots, none twice')

if failed:
    print('patch_spawn_fields_test: %d check(s) failed' % failed)
    sys.exit(1)
print('patch_spawn_fields_test: all checks passed')

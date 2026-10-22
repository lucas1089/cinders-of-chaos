#!/usr/bin/env python3
"""Tests of install_outfits.py: the class outfits block and the replacement Archmage of pair 29.

    python3 -I server/tools/install_outfits_test.py

  - the shipped constants: the replacement outfit is read (male 2235, female 2236, "Archmage") with its switch off, and
    no outfits.xml line names it; the retired 1559 keeps its "(old)" line;
  - a copy of the constants with the switch on: one line per sex, type 1 the male look and type 0 the female look,
    both named "Archmage"; an outfit without `female` gets the same look for both sexes;
  - a run on a small base data folder writes the block and a second run changes nothing.
"""
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_outfits as IO  # noqa: E402

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


SHIPPED_ON = True   # Chaos.classes.outfitReplacement.enabled as shipped (the pair 29 switch)


def test_shipped():
    text = open(IO.CONSTANTS, encoding='utf-8').read()
    rep = IO.replacement_outfit(text)
    expect(rep == (2235, 'Archmage', SHIPPED_ON, 2236), 'shipped replacement: %r' % (rep,))
    found = IO.class_outfits()
    looks = {t for m, f, _ in found for t in (m, f)}
    if SHIPPED_ON:
        expect((2235, 2236, 'Archmage') in found, 'switch on: the Archmage per sex')
    else:
        expect(2235 not in looks and 2236 not in looks, 'switch off: no Archmage line')
    expect((1559, 1559, 'Archmage (old)') in found, '1559 keeps its (old) line')


def test_switch_on(tmp):
    text = open(IO.CONSTANTS, encoding='utf-8').read()
    on = re.sub(r'(\n\toutfitReplacement = \{\n\t\tenabled = )(?:false|true)', r'\1true', text)
    expect(re.search(r'\n\toutfitReplacement = \{\n\t\tenabled = true,', on), 'the switch line was found')
    path = os.path.join(tmp, 'chaos_constants_on.lua')
    open(path, 'w', encoding='utf-8').write(on)
    found = IO.class_outfits(path)
    expect((2235, 2236, 'Archmage') in found, 'switch on: the Archmage per sex: %r' % found[-3:])
    one = on.replace('outfit = {lookType = 2235, female = 2236, name = "Archmage", addons = 3}',
                     'outfit = {lookType = 2999, name = "Archmage"}')
    open(path, 'w', encoding='utf-8').write(one)
    expect(IO.replacement_outfit(one) == (2999, 'Archmage', True, 2999), 'one look for both sexes')
    expect((2999, 2999, 'Archmage') in IO.class_outfits(path), 'one look: both sexes')


BASE = {
    'outfits.xml': '<?xml version="1.0"?>\n<outfits>\n\t<outfit type="0" looktype="136" name="Citizen" premium="no" '
                   'unlocked="yes" enabled="yes" />\n</outfits>\n',
    'mounts.xml': '<?xml version="1.0"?>\n<mounts>\n</mounts>\n',
    'wings.xml': '<?xml version="1.0"?>\n<wings>\n</wings>\n',
    'shaders.xml': '<?xml version="1.0"?>\n<shaders>\n</shaders>\n',
}


def test_install(tmp):
    data = os.path.join(tmp, 'data')
    os.makedirs(os.path.join(data, 'XML'))
    for name, text in BASE.items():
        open(os.path.join(data, 'XML', name), 'w').write(text)
    IO.main([data])
    xml = open(os.path.join(data, 'XML', 'outfits.xml')).read()
    expect(IO.BEGIN in xml and 'name="Archmage (old)"' in xml, 'the class outfits block with 1559 (old)')
    arch = ('\t<outfit type="1" looktype="2235" name="Archmage"' in xml and
            '\t<outfit type="0" looktype="2236" name="Archmage"' in xml)
    if SHIPPED_ON:
        expect(arch, 'switch on: type 1 2235 and type 0 2236 in outfits.xml')
    else:
        expect('looktype="2235"' not in xml and 'looktype="2236"' not in xml, 'switch off: no Archmage in outfits.xml')
    IO.main([data])
    expect(open(os.path.join(data, 'XML', 'outfits.xml')).read() == xml, 'a second run changes nothing')
    lines = [line for line in xml.splitlines() if 'looktype="1559"' in line]
    expect(len(lines) == 2 and 'type="0"' in lines[0] and 'type="1"' in lines[1], '1559: one line per sex')
    # the pair 37 outfits: one locked line per sex in their own block while the switch is on
    p37 = IO.pack37_outfits()
    if IO.pair37_on():
        expect(len(p37) == 10 and (2668, 2669, 'Starweaver') in p37 and (2681, 2681, 'Fry Box Costume') in p37,
               'pair 37: ten outfits read from chaos_pack37_looks.lua')
        expect(IO.P37BEGIN in xml and IO.P37END in xml, 'pair 37: the block is written')
        for m, f, n in p37:
            expect('<outfit type="1" looktype="%d" name="%s" premium="no" unlocked="no"' % (m, n) in xml and
                   '<outfit type="0" looktype="%d" name="%s" premium="no" unlocked="no"' % (f, n) in xml,
                   'pair 37: %s locked for both sexes' % n)
    else:
        expect(p37 == [] and IO.P37BEGIN not in xml, 'pair 37 off: no lines')


def main():
    test_shipped()
    tmp = tempfile.mkdtemp()
    try:
        test_switch_on(tmp)
        test_install(tmp)
    finally:
        shutil.rmtree(tmp)
    if FAILS:
        print('%d failures' % len(FAILS))
        sys.exit(1)
    print('install_outfits_test: OK')


if __name__ == '__main__':
    main()

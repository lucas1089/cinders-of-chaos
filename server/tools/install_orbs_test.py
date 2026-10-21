#!/usr/bin/env python3
"""Tests of install_orbs.py's name references (step 3) on a synthetic data folder; no base server needed.

usage: python3 -I server/tools/install_orbs_test.py
Checks: the old names are replaced, whole words, case kept; a base item name that holds an old name ("blazing ember orb"
holds "Ember Orb") is kept; the form an older run made of it ("blazing ember shard") is put back; a second run changes
nothing; data/scripts/chaos is left alone."""
import os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_orbs as IO  # noqa: E402

failed = 0


def check(cond, what):
    global failed
    if not cond:
        failed += 1
        print('FAIL: ' + what)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8').write(text)


RENAMES = [{'id': 29852, 'name': 'Ember Shard', 'plural': 'Ember Shards', 'old': 'Ember Orb'},
           {'id': 29852, 'name': 'Ember Shard', 'plural': 'Ember Shards', 'old': 'Orb of Augmentation'},
           {'id': 32260, 'name': 'Orb of Upheaval', 'plural': 'Orbs of Upheaval', 'old': 'Chaos Orb'},
           {'id': 32261, 'name': 'Exalted Upheaval', 'plural': 'Exalted Upheavals', 'old': 'Greater Chaos Orb'}]
XML = ('<items>\n<item id="29852" article="an" name="Ember Shard" />\n'
       '<item id="29520" article="a" name="blazing ember orb" />\n'
       '<item id="29521" article="a" name="cracked ember orb charm" />\n'
       '<item id="32260" article="an" name="Orb of Upheaval" />\n<item id="32261" article="an" name="Exalted Upheaval" />\n'
       '</items>\n')

tmp = tempfile.mkdtemp(prefix='orbs_test_')
try:
    names = IO.item_names(XML)
    check('blazing ember orb' in names and 'ember shard' in names, 'item_names reads the names')
    boss = os.path.join(tmp, 'monster', 'boss.lua')
    write(boss, 'monster.loot = {\n'
                '\t{id = "Ember Orb", chance = 100},\n'
                '\t{id = "blazing ember orb", chance = 8000},\n'
                '\t{id = "blazing ember shard", chance = 8000},\n'
                '\t{id = "cracked ember orb charm", chance = 10},\n'
                '\t{id = "chaos orb", chance = 5},\n'
                '\t{id = "greater chaos orb", chance = 5},\n'
                '\t{id = "Orb of Augmentation", chance = 5},\n'
                '\t{id = "emberorbit", chance = 5},\n'
                '}\n')
    npc = os.path.join(tmp, 'npc', 'Khadin.xml')
    write(npc, '<parameter key="shop" value="Blazing Ember Shard,29520,500;Ember Orb,29852,10" />\n')
    ours = os.path.join(tmp, 'scripts', 'chaos', 'x.lua')
    write(ours, '-- Ember Orb stays in our own files\n')

    changed, total = IO.patch_references(tmp, RENAMES, False, names)
    text = open(boss, encoding='utf-8').read()
    check('{id = "Ember Shard", chance = 100}' in text, 'the old name renamed, case kept: ' + text)
    check(text.count('"blazing ember orb"') == 2, 'the base name kept and the made form put back: ' + text)
    check('blazing ember shard' not in text, 'no item named blazing ember shard is left')
    check('"cracked ember orb charm"' in text, 'a longer base name kept')
    check('{id = "orb of upheaval", chance = 5}' in text, 'lower case renamed in lower case')
    check('{id = "exalted upheaval", chance = 5}' in text, 'the longer old name gets its own rename, not the shorter one')
    check('"Ember Shard", chance = 5' in text, 'the second old name of an item renamed')
    check('"emberorbit"' in text, 'whole words only')
    shop = open(npc, encoding='utf-8').read()
    check(shop.startswith('<parameter key="shop" value="Blazing Ember Orb,29520,500;Ember Shard,29852,10"'),
          'the NPC list: the made form put back with its case, the old name renamed: ' + shop)
    check(open(ours, encoding='utf-8').read() == '-- Ember Orb stays in our own files\n', 'data/scripts/chaos left alone')
    check(total > 0 and len(changed) == 2, 'two files changed %r' % changed)

    before = (open(boss, encoding='utf-8').read(), open(npc, encoding='utf-8').read())
    changed, total = IO.patch_references(tmp, RENAMES, False, names)
    check(not changed and (open(boss, encoding='utf-8').read(), open(npc, encoding='utf-8').read()) == before,
          'a second run changes nothing %r' % changed)

    # dry run: nothing written
    write(boss, '{id = "Ember Orb"}\n')
    changed, _ = IO.patch_references(tmp, RENAMES, True, names)
    check(changed and open(boss, encoding='utf-8').read() == '{id = "Ember Orb"}\n', 'dry run writes nothing')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print('install_orbs_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)

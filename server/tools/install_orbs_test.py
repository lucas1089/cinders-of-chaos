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

# own looks (O482): the node of an orb with `look` carries it once the recorded pair is client_pair.PAIR_ORBS or more
import struct  # noqa: E402
import client_pair as CP  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_STACKABLE, FLAG_ANIMATION  # noqa: E402


def item_node(sid, cid, flags=FLAG_STACKABLE, extra=b''):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid)) + extra
    return bytes([START]) + escape(bytes([0])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


cfg = IO.read_config()
items = cfg['items']
withlook = [i for i in items if i['look']]
check(CP.PAIR_ORBS == 63 and CP.PAIR_ORBS <= CP.PAIR_ASSETS, 'the orb looks need pair 63')
check(len(items) == 10 and len(withlook) == 10, 'config: all ten orbs of this installer have a look')
check(sorted(i['look'] for i in withlook) == list(range(44550, 44560)), 'config: looks 44550..44559')
check(len({i['look'] for i in withlook} | {i['clientId'] for i in withlook}) == 20, 'config: look and stock ids are all different')
anim = struct.pack('<I', 0)
stock_nodes = [item_node(27000 + k, i['clientId'], FLAG_STACKABLE | (FLAG_ANIMATION if i['key'] == 'void' else 0), attr(0x14, b'\x07\x00'))
               for k, i in enumerate(withlook)]
base = otb(stock_nodes)
old_new, _n, w_old = IO.patch_otb(base, items, False)
IO.verify_otb(old_new, items, w_old)
ko = {k[2]: k for k in scan(old_new)[0]}
check(all(ko[i['id']][3] == i['clientId'] for i in items), 'below pair 63: every orb node keeps the stock client id (an old client draws the old look)')
new_new, notes, w_new = IO.patch_otb(old_new, items, True)
IO.verify_otb(new_new, items, w_new)
kn = {k[2]: k for k in scan(new_new)[0]}
check(all(kn[i['id']][3] == i['look'] for i in items), 'pair 63: every orb node carries its own look')
check(sum('rewritten' in n for n in notes) == 10, 'pair 63: the ten existing nodes are rewritten: %r' % notes)
check(all(not (kn[i['id']][5] & FLAG_ANIMATION) for i in items), 'pair 63: no orb node says animated (one phase looks)')
check(ko[32260][5] & FLAG_ANIMATION and not kn[32260][5] & FLAG_ANIMATION, 'the Void Orb: the stock gem is animated, its own look is not')
check(all((0x14, b'\x07\x00') in kn[i['id']][6] for i in items), 'pair 63: the other attributes of the stock node are kept')
check(all(ko[27000 + k][3] == i['clientId'] and kn[27000 + k][3] == i['clientId'] for k, i in enumerate(withlook)), 'the stock nodes are never touched')
again, notes2, _w = IO.patch_otb(new_new, items, True)
check(again == new_new and 'present' in notes2[0], 'a second run changes nothing')
back, _n3, _w3 = IO.patch_otb(new_new, items, False)
check(back == old_new, 'the record below 63 again: the stock client ids come back byte for byte')
try:
    IO.patch_otb(otb(stock_nodes + [item_node(32258, 9999)]), items, True)
    check(False, 'a server id on another client id stops the script')
except SystemExit as e:
    check('already belongs' in str(e), 'a server id on another client id stops the script')

# the run itself reads the record from config.lua: skipped without it, on with it
dd = tempfile.mkdtemp(prefix='orbs_pair_')
try:
    for rec, want in ((None, False), ('chaosClientPair = 62\n', False), ('chaosClientPair = 63\n', True)):
        srv = os.path.join(dd, 'srv%s' % (rec or 'none').strip().split()[-1])
        write(os.path.join(srv, 'config.lua'), rec or 'serverName = "x"\n')
        os.makedirs(os.path.join(srv, 'data'), exist_ok=True)
        ok, msg = CP.allows(os.path.join(srv, 'data'), CP.PAIR_ORBS, 'orb own looks')
        check(ok is want and (want or 'client pair 63' in msg), 'record %r -> own looks %s' % (rec, want))
finally:
    shutil.rmtree(dd, ignore_errors=True)

print('install_orbs_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)

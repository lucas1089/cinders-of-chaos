#!/usr/bin/env python3
"""python3 -I server/tools/install_relic_sets_test.py : install_relic_sets.py on the shipped manifest and on synthetic server files
(65 rows in five sets of 13, ids and client ids, every piece on the equipment sets' curve of its set's level, the class lists,
items.xml / movements.xml / weapons.xml blocks added / kept / rewritten, an outside entry refused, the client pair guard end to
end, the generated Lua up to date). No base server needed."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_relic_sets as T  # noqa: E402
import install_gear_sets as GS  # noqa: E402
from install_gems import scan, escape, attr, START, END, A_SERVERID, A_CLIENTID, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def raises(fn, what):
    try:
        fn()
    except (SystemExit, AssertionError):
        return
    check(False, what)


rows = T.rows_of()
by = {r['key']: r for r in rows}
check(len(rows) == 65 and len({r['server_id'] for r in rows}) == 65, '65 pieces, no duplicate id')
check(sorted(r['server_id'] for r in rows) == list(range(48446, 48511)), 'server ids 48446-48510')
check(all(r['server_id'] == r['client_id'] + 4000 and 44446 <= r['client_id'] <= 44510 for r in rows), 'server id = client id + 4000, client ids 44446-44510')
check(all(len([r for r in rows if r['ex']['set'] == s[0]]) == 13 for s in T.SETS), 'thirteen pieces in each of the five sets')
check(all(r['level'] == T.RELIC_BY_KEY[r['ex']['set']][2] for r in rows), 'one level per set')
check([s[2] for s in T.SETS] == [640, 860, 1400, 1700, 2050], 'levels 640, 860, 1400, 1700, 2050')
kinds = {}
for r in rows:
    kinds[r['kind']] = kinds.get(r['kind'], 0) + 1
check(kinds == {'helmet': 5, 'armor': 5, 'legs': 5, 'boots': 5, 'shield': 5, 'spellbook': 5, 'sword': 5, 'axe': 5, 'club': 5, 'bow': 5,
                'wand': 3, 'rod': 2, 'ring': 5, 'amulet': 5}, 'the mix of kinds: %r' % kinds)
for r in rows:
    check(r['ex'].get('description') and 'set (level %d)' % r['level'] in r['ex']['description'], r['key'] + ': a description naming the set')
# the class lists
check(by['venomcoil_helmet']['classes'] == [] and by['deepdirge_chest']['classes'] == [] and by['halogild_legs']['classes'] == [],
      'helmets, chest armours and legs: anyone (fit A)')
check(by['kilnforged_boots']['classes'] == [] and by['kilnforged_ring']['classes'] == [] and by['kilnforged_amulet']['classes'] == [],
      'boots, rings, amulets: anyone')
check(by['hoarglass_bow']['classes'] == ['Ranger', 'Deadeye', 'Beastmaster'], 'bows: Ranger, Deadeye, Beastmaster')
check(by['hoarglass_shield']['classes'] == ['Warrior', 'Juggernaut', 'Templar', 'Inquisitor', 'Sentinel'], 'shields: Warrior, Juggernaut, Templar line')
check(sorted(by['hoarglass_spellbook']['classes']) == sorted(GS.MYSTIC + GS.NECRO), 'spellbooks: the Mystic and Necromancer lines')
check(sorted(by['halogild_staff']['classes']) == sorted(GS.MYSTIC + GS.NECRO) and sorted(by['venomcoil_staff']['classes']) == sorted(GS.MYSTIC + GS.NECRO),
      'the wand or rod of a set: every caster')
check('Berserker' in by['kilnforged_axe']['classes'] and 'Berserker' not in by['kilnforged_sword']['classes']
      and 'Berserker' not in by['kilnforged_hammer']['classes'] and len(by['kilnforged_axe']['classes']) == 12,
      'the axe is two-handed for all twelve melee classes, the sword and hammer one-handed without the Berserker')

# the numbers of the sets' curve at each level


def stat(key, name):
    return dict(by[key]['stats']).get(name)


check([stat('venomcoil_bow', k) for k in ('attack', 'hitChance', 'skillDist', 'attackspeed', 'range')] == [75, 96, 3, 3000, 6], 'venomcoil bow: attack 75, hit 96, skill 3')
check(stat('venomcoil_bow', 'shootType') == 'poisonarrow' and stat('deepdirge_bow', 'shootType') == 'onyxarrow', 'missiles of the set')
check(by['venomcoil_staff']['wand'][:3] == (90, 122, 23) and by['venomcoil_staff']['wand'][3] == 'earth', 'venomcoil scepter: 90-122, mana 23, earth')
check(by['halogild_staff']['kind'] == 'rod' and by['halogild_staff']['wand'][3] == 'holy' and stat('halogild_staff', 'shootType') == 'smallholy', 'halogild staff is a rod, holy damage and missile')
check(stat('kilnforged_axe', 'attackspeed') == 3000 and stat('kilnforged_sword', 'attackspeed') is None, 'two-handed axe 3000 ms, sword none')
check(not any(k.startswith('lifeleech') for r in rows for k, _v in r['stats']), 'no leech: that is the Bloodmoon set alone')
check(stat('deepdirge_chest', 'absorbPercentDeath') is not None and stat('deepdirge_chest', 'absorbPercentHoly') is not None,
      'a chest resists the set element and is weak to the opposite')
# every piece is 100% of the curve at its set's level (the weapon audit's 80% rule, the gear audit's power column)
for r in rows:
    k, lvl = r['kind'], r['level']
    if k in ('wand', 'rod'):
        check(abs((r['wand'][0] + r['wand'][1]) / 2.0 - GS.curve('wand', lvl)) <= 1.0, '%s: wand power is the tier' % r['key'])
    elif k in ('bow', 'crossbow'):
        check(abs(stat(r['key'], 'attack') - GS.curve('bow', lvl)) <= 1.0, '%s: bow attack is the tier' % r['key'])
    elif k in ('sword', 'axe', 'club'):
        power = stat(r['key'], 'attack') + sum(v for kk, v in r['stats'] if kk.startswith('element'))
        tier = GS.curve('attack', lvl) + (3 if r['ex']['fit'] == '2' else 0)
        check(abs(power - tier) <= 1.0, '%s: power %.1f is the tier %.1f of level %d' % (r['key'], power, tier, lvl))

# ---- items.xml / movements.xml / weapons.xml blocks
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2400" name="x" />\n</items>\n'
new, note = T.patch_xml(xml, rows)
check('block added' in note and new.count('<item id=') == 66 and new.count('Chaos relic sets of pair 58') == 2, 'items.xml block added once')
check('Part of the Venomcoil set (level 640).' in new and 'slotType" value="two-handed"' in new and 'weaponType" value="distance"' in new
      and 'weaponType" value="wand"' in new and 'weaponType" value="shield"' in new, 'items.xml: descriptions, two-handed, weapon types')
check('slotType" value="head"' in new and 'slotType" value="body"' in new and 'slotType" value="legs"' in new and 'slotType" value="feet"' in new
      and 'slotType" value="necklace"' in new and 'slotType" value="ring"' in new, 'items.xml: the armour slots')
check('ammoType' not in new, 'launchers fire without ammunition')
again, note = T.patch_xml(new, rows)
check(again == new and 'up to date' in note, 'items.xml block up to date on a second run')
check(T.patch_xml(new.replace('value="75"', 'value="70"'), rows)[0] == new, 'items.xml block rewritten when a number changed')
raises(lambda: T.patch_xml(xml.replace('2400', '48446'), rows), 'an items.xml entry outside the block stops the script')
mv = '<movements>\n</movements>\n'
nm, note = T.patch_moves(mv, rows)
check(nm.count('event="Equip"') == 65 and nm.count('event="DeEquip"') == 65 and 'slot="hand"' in nm and 'slot="shield"' in nm
      and 'level="2050"' in nm and 'slot="head"' in nm, 'movements.xml: an Equip / DeEquip pair per piece')
check(T.patch_moves(nm, rows)[0] == nm, 'movements.xml idempotent')
raises(lambda: T.patch_moves('<movements>\n<movevent event="Equip" itemid="48446" slot="head" />\n</movements>\n', rows), 'a movements.xml entry outside the block stops the script')
wx = '<weapons>\n</weapons>\n'
nw, note = T.patch_weapons(wx, rows)
check(nw.count('<distance ') == 5 and nw.count('<wand ') == 5 and nw.count('<melee ') == 15, 'weapons.xml: 5 bows, 5 wands and rods, 15 melee')
check('<wand id="48456" level="640" mana="23" min="90" max="122" type="earth">' in nw, 'weapons.xml: a wand with its damage, mana and element')
check(T.patch_weapons(nw, rows)[0] == nw, 'weapons.xml idempotent')

# ---- the generated Lua is up to date
check(subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_relic_sets.py'), '--lua', '--check']).returncode == 0, 'chaos_relic_sets_items.lua up to date')

# ---- bad manifests
head = 'client_id,server_id,key,kind,mode,name,size,otb_group,otb_flags,top_order,speed,light_level,light_color,extra\n'


def manifest(line):
    d = tempfile.mkdtemp(prefix='relic_')
    p = os.path.join(d, 'm.csv')
    open(p, 'w').write(head + line + '\n')
    return p


good = '44446,48446,k1,bow,new,test bow,1x1,0,96,0,0,0,0,set=venomcoil|kind=bow|fit=|level=640|description=x'
check(len(T.rows_of(manifest(good))) == 1, 'a good synthetic row is read')
raises(lambda: T.rows_of(manifest(good.replace('48446', '48999'))), 'a server id that is not client id + 4000 is refused')
raises(lambda: T.rows_of(manifest(good.replace('level=640', 'level=700'))), 'a level that is not the set level is refused')
raises(lambda: T.rows_of(manifest(good.replace('set=venomcoil', 'set=nosuchset'))), 'an unknown set is refused')
raises(lambda: T.rows_of(manifest(good.replace('kind=bow', 'kind=spear'))), 'a kind that differs from the row kind is refused')
raises(lambda: T.rows_of(manifest(good.replace('44446,48446', '44446,40446'))), 'a server id outside the block is refused')


# ---- the whole tool on a synthetic server, with the client pair guard
def item_node(sid, cid, flags=FLAG_PICKUPABLE | FLAG_MOVEABLE, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


def server(config):
    d = tempfile.mkdtemp(prefix='relicsrv_')
    if config is not None:
        open(os.path.join(d, 'config.lua'), 'w').write(config)
    for sub in ('items', 'movements', 'weapons'):
        os.makedirs(os.path.join(d, 'data', sub))
    open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(2400, 2400)]))
    open(os.path.join(d, 'data', 'items', 'items.xml'), 'w').write('<?xml version="1.0"?>\n<items>\n</items>\n')
    open(os.path.join(d, 'data', 'movements', 'movements.xml'), 'w').write('<movements>\n</movements>\n')
    open(os.path.join(d, 'data', 'weapons', 'weapons.xml'), 'w').write('<weapons>\n</weapons>\n')
    return d


def snap(d):
    out = {}
    for root, _, files in os.walk(os.path.join(d, 'data')):
        for n in files:
            out[os.path.join(root, n)] = open(os.path.join(root, n), 'rb').read()
    return out


def run(d, *extra):
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_relic_sets.py'), os.path.join(d, 'data')] + list(extra),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


for cfg, label in ((None, 'no config.lua'), ('x = 1\n', 'no key'), ('chaosClientPair = 54\n', 'pair 54'), ('chaosClientPair = 57\n', 'pair 57')):
    d = server(cfg)
    before = snap(d)
    rc, out = run(d)
    check(rc == 0 and out.startswith('WARNING: relicsets skipped') and 'client pair 58' in out and snap(d) == before,
          'guard, %s: skipped with a message, nothing written (%s)' % (label, out.strip()[:100]))
d = server('chaosClientPair = 58\n')
rc, out = run(d, '--dry-run')
check(rc == 0 and 'dry run' in out and 'installing' in out, 'pair 58, dry run: reads and reports')
rc, out = run(d)
after = snap(d)
kids, _ = scan(after[os.path.join(d, 'data', 'items', 'items.otb')])
ids = {k[2]: k[3] for k in kids}
check(rc == 0 and all(ids.get(r['server_id']) == r['client_id'] for r in rows) and 2400 in ids, 'pair 58: 65 nodes with their client ids, the stock node kept (%s)' % out.strip()[-80:])
check(os.path.exists(os.path.join(d, 'data', 'items', 'items.otb.bak')), 'items.otb.bak kept')
check(b'id="48510"' in after[os.path.join(d, 'data', 'items', 'items.xml')] and b'itemid="48446"' in after[os.path.join(d, 'data', 'movements', 'movements.xml')]
      and b'<distance id="48455"' in after[os.path.join(d, 'data', 'weapons', 'weapons.xml')], 'pair 58: items.xml, movements.xml and weapons.xml written')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'pair 58: a second run changes nothing')
open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = 99\n')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'a higher pair installs the same')
# a node whose server id belongs to another item stops the install
d = server('chaosClientPair = 58\n')
open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(48446, 9999, 0, 1)]))
rc, out = run(d)
check(rc != 0, 'a server id that belongs to another item stops the script')

print('install_relic_sets_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)

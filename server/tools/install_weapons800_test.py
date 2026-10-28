#!/usr/bin/env python3
"""python3 -I server/tools/install_weapons800_test.py : install_weapons800.py on the shipped manifest and on synthetic server
files (34 rows, ids and client ids, every weapon on the equipment sets' curve of its level, the class lists, items.xml / movements.xml /
weapons.xml blocks added / kept / rewritten, an outside entry refused, the client pair guard end to end, the generated Lua up to date).
No base server needed."""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_weapons800 as T  # noqa: E402
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
check(len(rows) == 34 and len({r['server_id'] for r in rows}) == 34, '34 weapons, no duplicate id')
check(sorted(r['server_id'] for r in rows) == list(range(48412, 48446)), 'server ids 48412-48445')
check(all(r['server_id'] == r['client_id'] + 4000 and 44412 <= r['client_id'] <= 44445 for r in rows), 'server id = client id + 4000, client ids 44412-44445')
lv = [r['level'] for r in rows]
check(lv == sorted(lv) and lv[0] == 820 and lv[-1] == 2150, 'rows sorted by level, 820 to 2150')
count = {}
for r in rows:
    count[r['type']] = count.get(r['type'], 0) + 1
check(count == {'bow': 9, 'crossbow': 4, 'wand': 9, 'rod': 9, 'sword2': 1, 'axe2': 1, 'club2': 1}, 'the mix of types: %r' % count)
for r in rows:
    check(r['loot'] and all(0 < c <= 1200 for _m, c in r['loot']), r['key'] + ': monster loot rows')
    check(GS.weapon_type(r['kind']) is not None, r['key'] + ': a weapon type')
# the class lists (install_gear_sets.py FITS): launchers, casters, melee
check(by['w800_gravesong_bow']['classes'] == ['Ranger', 'Deadeye', 'Beastmaster'], 'bows: Ranger, Deadeye, Beastmaster')
check(by['w800_bonehinge_arbalest']['classes'] == ['Ranger', 'Deadeye'], 'crossbows: Ranger, Deadeye')
check('Elementalist' in by['w800_cinderbloom_wand']['classes'] and 'Illusionist' not in by['w800_cinderbloom_wand']['classes'], 'wands: not the Illusionist')
check('Illusionist' in by['w800_hushwood_rod']['classes'] and 'Elementalist' not in by['w800_hushwood_rod']['classes'], 'rods: not the Elementalist')
check('Lich' in by['w800_hushwood_rod']['classes'] and 'Bone Lord' in by['w800_cinderbloom_wand']['classes'], 'the Necromancer line wields both')
check(len(by['w800_gravewrought_greatsword']['classes']) == 12 and 'Berserker' in by['w800_ashmaw_greataxe']['classes'], 'two-handed melee: all twelve melee classes')

# numbers of the spec (the sets' curve at the weapon's level)
def stat(key, name):
    return dict(by[key]['stats']).get(name)


check([stat('w800_gravesong_bow', k) for k in ('attack', 'hitChance', 'skillDist', 'attackspeed', 'range')] == [77, 96, 3, 3000, 6], 'gravesong bow: attack 77, hit 96, skill 3')
check(stat('w800_gravesong_bow', 'shootType') == 'onyxarrow' and stat('w800_bonehinge_arbalest', 'shootType') == 'drillbolt', 'death missiles')
check([stat('w800_last_ember_recurve', k) for k in ('attack', 'hitChance', 'skillDist')] == [85, 98, 5], 'last-ember recurve: attack 85, hit 98, skill 5')
check(stat('w800_thornwarden_crossbow', 'attack') == 85, 'a crossbow is the bow curve + 3')
check(by['w800_cinderbloom_wand']['wand'] == (95, 129, 25, 'fire') and stat('w800_cinderbloom_wand', 'magiclevelpoints') == 3, 'cinderbloom wand: 95-129, mana 25, ML +3')
check(by['w800_wyrmtongue_focus']['wand'] == (117, 159, 33, 'energy') and stat('w800_wyrmtongue_focus', 'magiclevelpoints') == 4, 'wyrmtongue focus: 117-159, mana 33, ML +4')
check([stat('w800_gravewrought_greatsword', k) for k in ('attack', 'elementDeath', 'defense', 'skillSword', 'attackspeed')] == [40, 22, 37, 3, 3000], 'greatsword: 40 + death 22, defense 37')
check([stat('w800_dirgebell_maul', k) for k in ('attack', 'elementHoly', 'defense', 'skillClub')] == [42, 22, 38, 3], 'maul: 42 + holy 22, defense 38')
check(not any(k.startswith('lifeleech') for r in rows for k, _v in r['stats']), 'no leech: that is the Bloodmoon set alone')
# every weapon is 100% of the tier of its own level (the weapon audit's 80% rule, tools/weapon_coverage_config.lua)
for r in rows:
    k, lvl = r['kind'], r['level']
    if k in ('wand', 'rod'):
        power = (r['wand'][0] + r['wand'][1]) / 2.0
        tier = GS.curve('wand', lvl)
    elif k in ('bow', 'crossbow'):
        power = stat(r['key'], 'attack')
        tier = GS.curve('bow', lvl) + (3 if k == 'crossbow' else 0)
    else:
        power = stat(r['key'], 'attack') + sum(v for kk, v in r['stats'] if kk.startswith('element'))
        tier = GS.curve('attack', lvl) + 3
    check(abs(power - tier) <= 1.0, '%s: power %.1f is the tier %.1f of level %d' % (r['key'], power, tier, lvl))

# ---- items.xml / movements.xml / weapons.xml blocks
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2400" name="x" />\n</items>\n'
new, note = T.patch_xml(xml, rows)
check('block added' in note and new.count('<item id=') == 35 and new.count('Chaos weapons above level 800') == 2, 'items.xml block added once')
check('slotType" value="two-handed"' in new and 'weaponType" value="distance"' in new and 'weaponType" value="wand"' in new, 'items.xml: launchers two-handed, weapon types')
check('ammoType' not in new, 'launchers fire without ammunition')
again, note = T.patch_xml(new, rows)
check(again == new and 'up to date' in note, 'items.xml block up to date on a second run')
check(T.patch_xml(new.replace('value="77"', 'value="70"'), rows)[0] == new, 'items.xml block rewritten when a number changed')
raises(lambda: T.patch_xml(xml.replace('2400', '48412'), rows), 'an items.xml entry outside the block stops the script')
mv = '<movements>\n</movements>\n'
nm, note = T.patch_moves(mv, rows)
check(nm.count('event="Equip"') == 34 and nm.count('event="DeEquip"') == 34 and 'slot="hand"' in nm and 'level="820"' in nm, 'movements.xml: an Equip / DeEquip pair per weapon')
check(T.patch_moves(nm, rows)[0] == nm, 'movements.xml idempotent')
raises(lambda: T.patch_moves('<movements>\n<movevent event="Equip" itemid="48412" slot="hand" />\n</movements>\n', rows), 'a movements.xml entry outside the block stops the script')
wx = '<weapons>\n</weapons>\n'
nw, note = T.patch_weapons(wx, rows)
check(nw.count('<distance ') == 13 and nw.count('<wand ') == 18 and nw.count('<melee ') == 3, 'weapons.xml: 13 launchers, 18 wands and rods, 3 melee')
check('<wand id="48425" level="830" mana="25" min="95" max="129" type="fire">' in nw, 'weapons.xml: a wand with its damage, mana and element')
check(T.patch_weapons(nw, rows)[0] == nw, 'weapons.xml idempotent')

# ---- the generated Lua is up to date, and the class loot families carry the bases
check(subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_weapons800.py'), '--lua', '--check']).returncode == 0, 'chaos_weapons800.lua up to date')
text = open(os.path.join(HERE, '..', 'data', 'lib', 'chaos_class_loot.lua')).read()
for r in rows:
    check('{%d, %d}' % (r['server_id'], r['level']) in text, '%s is a class loot base of its family' % r['key'])

# ---- bad manifests
head = 'client_id,server_id,key,kind,mode,name,size,otb_group,otb_flags,top_order,speed,light_level,light_color,extra\n'


def manifest(line):
    d = tempfile.mkdtemp(prefix='w800_')
    p = os.path.join(d, 'm.csv')
    open(p, 'w').write(head + line + '\n')
    return p


good = '44412,48412,k1,bow,new,test bow,1x1,0,96,0,0,0,0,type=bow|level=900|element=fire|loot=Frost Maiden:150|description=x'
check(len(T.rows_of(manifest(good))) == 1, 'a good synthetic row is read')
raises(lambda: T.rows_of(manifest(good.replace('48412', '48999'))), 'a server id that is not client id + 4000 is refused')
raises(lambda: T.rows_of(manifest(good.replace('level=900', 'level=700'))), 'a level at or below 800 is refused')
raises(lambda: T.rows_of(manifest(good.replace('element=fire', 'element=lava'))), 'an unknown element is refused')
raises(lambda: T.rows_of(manifest(good.replace('type=bow', 'type=spear'))), 'an unknown type is refused')
raises(lambda: T.rows_of(manifest(good.replace('loot=Frost Maiden:150|', ''))), 'a weapon with no monster loot is refused')
raises(lambda: T.rows_of(manifest(good.replace('44412,48412', '44412,40412'))), 'a server id outside the block is refused')


# ---- the whole tool on a synthetic server, with the client pair guard
def item_node(sid, cid, flags=FLAG_PICKUPABLE | FLAG_MOVEABLE, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


def server(config):
    d = tempfile.mkdtemp(prefix='w800srv_')
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
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_weapons800.py'), os.path.join(d, 'data')] + list(extra),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


for cfg, label in ((None, 'no config.lua'), ('x = 1\n', 'no key'), ('chaosClientPair = 54\n', 'pair 54'), ('chaosClientPair = 55\n', 'pair 55')):
    d = server(cfg)
    before = snap(d)
    rc, out = run(d)
    check(rc == 0 and out.startswith('WARNING: weapons800 skipped') and 'client pair 56' in out and snap(d) == before,
          'guard, %s: skipped with a message, nothing written (%s)' % (label, out.strip()[:100]))
d = server('chaosClientPair = 56\n')
rc, out = run(d, '--dry-run')
check(rc == 0 and 'dry run' in out and 'installing' in out, 'pair 56, dry run: reads and reports')
rc, out = run(d)
after = snap(d)
kids, _ = scan(after[os.path.join(d, 'data', 'items', 'items.otb')])
ids = {k[2]: k[3] for k in kids}
check(rc == 0 and all(ids.get(r['server_id']) == r['client_id'] for r in rows) and 2400 in ids, 'pair 56: 34 nodes with their client ids, the stock node kept (%s)' % out.strip()[-80:])
check(os.path.exists(os.path.join(d, 'data', 'items', 'items.otb.bak')), 'items.otb.bak kept')
check(b'id="48445"' in after[os.path.join(d, 'data', 'items', 'items.xml')] and b'itemid="48412"' in after[os.path.join(d, 'data', 'movements', 'movements.xml')]
      and b'<distance id="48412"' in after[os.path.join(d, 'data', 'weapons', 'weapons.xml')], 'pair 56: items.xml, movements.xml and weapons.xml written')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'pair 56: a second run changes nothing')
open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = 99\n')
rc, out = run(d)
check(rc == 0 and snap(d) == after, 'a higher pair installs the same')
# a node whose server id belongs to another item stops the install
d = server('chaosClientPair = 56\n')
open(os.path.join(d, 'data', 'items', 'items.otb'), 'wb').write(otb([item_node(48412, 9999, 0, 1)]))
rc, out = run(d)
check(rc != 0, 'a server id that belongs to another item stops the script')

print('install_weapons800_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)

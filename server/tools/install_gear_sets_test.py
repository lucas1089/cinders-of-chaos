#!/usr/bin/env python3
"""python3 -I server/tools/install_gear_sets_test.py : install_gear_sets.py on a synthetic items.otb / items.xml /
movements.xml / weapons.xml (the shipped manifest: 448 rows and ids, plus 192 pieces of the later-tier sets that copy the looks of three art sets; levels spread over each band; the curves and a
few stats; the nodes added and verified, idempotent; each block added once, kept, refused when an id is taken outside
it; equip slots and class lists; the generated Lua up to date; the switch off). No base server needed."""
import os, struct, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_gear_sets as T  # noqa: E402
from install_pack_items import patch_otb, verify_otb  # noqa: E402
from install_gems import escape, attr, START, END, A_SERVERID, A_CLIENTID  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def item_node(sid, cid, flags=0, group=0):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


rows = T.rows_of(T.DEFAULT_MANIFEST)
by = {r['key']: r for r in rows}
check(len(rows) == 640, 'manifest: 448 art pieces + 192 later-tier pieces')
check([r['server_id'] for r in rows[:448]] == list(range(36995, 37443)), 'manifest: server ids 36995..37442 in order')
check([r['server_id'] for r in rows[448:]] == list(range(52000, 52192)), 'later tiers: server ids 52000..52191 in order')
orig = {r['server_id']: r for r in rows[:448]}
by_cid = {}
for r in rows:
    by_cid.setdefault(r['client_id'], []).append(r)
for key, name, _band, *_x, source, first in T.TIER2:
    own = [r for r in rows if r['ex']['set'] == key]
    src = [r for r in rows[:448] if r['ex']['set'] == source]
    check(len(own) == 64 and [r['client_id'] for r in own] == [r['client_id'] for r in src],
          key + ': 64 pieces with the client ids (the looks) of ' + source)
    check(all(r['server_id'] != r['client_id'] + 3000 for r in own), key + ': ids of their own, not client id + 3000')
    check(all(r['name'].startswith(name.lower() + ' ') for r in own), key + ': named for the set')
    check(all(r['ex']['fit'] == 'A' for r in own if r['kind'] == 'legs'), key + ': legs fit anyone')
check(all(len(v) in (1, 2) for v in by_cid.values()), 'a look is worn by at most one copy')
check(len({r['key'] for r in rows}) == 640, 'keys are unique')
check(T.pair28_on(), 'switch ChaosGearSets.PAIR28 is on as shipped (pair 28 is live)')
with tempfile.TemporaryDirectory() as td:
    off = os.path.join(td, 'chaos_gear_sets.lua')
    open(off, 'w').write(open(T.SWITCH).read().replace('M.PAIR28 = true', 'M.PAIR28 = false'))
    check(not T.pair28_on(off) and not T.pair28_on(os.path.join(td, 'missing.lua')), 'switch read as off when false or missing')

# curves and levels
check(T.curve('armor', 8) == 7 and T.curve('armor', 5000) == 31 and T.curve('armor', 150) == 14.5, 'curve: ends and between')
check(T.steps('skill', 49) == 0 and T.steps('skill', 50) == 1 and T.steps('skill', 2000) == 5, 'steps')
for key, _name, (lo, hi), *_r in T.SETS:
    own = [r for r in rows if r['ex']['set'] == key]
    check(len(own) == 64, key + ': 64 pieces')
    check(min(r['level'] for r in own) == lo and max(r['level'] for r in own) == hi, key + ': levels span the band')
    check(all(r['level'] % 5 == 0 or r['level'] == lo for r in own), key + ': levels rounded to 5')
h = [by['blightfang_helmet_%d' % i] for i in (1, 3, 6)]
check([r['level'] for r in h] == [8, 80, 150] and all(r['ex']['fit'] == 'H' for r in h), 'heavy helmets 8, 80, 150')

# stats
st = dict(by['cinderwrought_sword_1']['stats'])
check(st.get('attackspeed') == 3000 and 'elementFire' in st, 'a two-handed fire sword: slower, a fire share')
check(st['attack'] + st['elementFire'] == T.rnd(T.curve('attack', by['cinderwrought_sword_1']['level'])) + 3,
      'melee: physical + element = the curve (+3 two-handed)')
robe = dict(by['cinderwrought_armor_2']['stats'])
check(robe.get('absorbPercentFire', 0) > 0 and robe.get('absorbPercentIce', 0) < 0, 'body: resists its element, weak to one')
wand = by['bloodmoon_wand_1']
check(wand['wand'][3] == 'death' and dict(wand['stats']).get('lifeleechchance') == 2 + T.steps('leech', wand['level']), 'Bloodmoon wand: death, life leech')
check(all('attackspeed' not in dict(r['stats']) for r in rows if r['ex']['fit'] == '1'), 'one-handed: stock speed')

# classes and slots
check(by['cinderwrought_helmet_5']['classes'] == T.MYSTIC + T.NECRO, 'a cloth hood: Mystic and Necromancer lines')
check(T.equip_slot(by['cinderwrought_shield_1']) == 'shield' and T.equip_slot(by['cinderwrought_bow_1']) == 'two-handed',
      'equip slots')
check('Berserker' not in by['cinderwrought_shield_1']['classes'], 'no shield for the Berserker')
check('Beastmaster' not in by['cinderwrought_crossbow_1']['classes'], 'no crossbow for the Beastmaster')
voc = T.vocation_lines(T.WARRIOR + T.TEMPLAR)
check(voc.count('showInDescription="0"') == 4, 'ascended classes hidden next to their base class')

# items.otb
base = otb([item_node(2671, 3582)])
new, c = patch_otb(base, rows)
check(c['new'] == 640 and verify_otb(new, rows) >= 640, 'otb: 640 nodes added and verified')
again, c2 = patch_otb(new, rows)
check(again == new and c2['new'] == 0, 'otb: a second run changes nothing')

# items.xml, movements.xml, weapons.xml
xml = '<?xml version="1.0"?>\n<items>\n\t<item id="2671" name="a ham" />\n</items>\n'
x1, note = T.patch_xml(xml, rows)
check('added' in note and x1.count('<item id="3') == 448 and x1.count('<item id="52') == 192, 'xml: block added')
check(T.patch_xml(x1, rows) == (x1, 'items.xml: equipment set block up to date'), 'xml: a second run keeps it')
check('<item id="37011" name="cinderwrought legplates">' in x1, 'xml: no article for a plural noun')
try:
    T.patch_xml(xml.replace('</items>', '\t<item id="37000" name="taken" />\n</items>'), rows)
    check(False, 'xml: a taken id stops the script')
except SystemExit as e:
    check('equipment set block' in str(e), 'xml: the refusal names the block')
mv = '<?xml version="1.0"?>\n<movements>\n</movements>\n'
m1, _n = T.patch_moves(mv, rows)
check(m1.count('event="Equip"') == 640 and m1.count('event="DeEquip"') == 640, 'movements: a pair per piece')
check('itemid="36995" slot="head" level="120"' in m1, 'movements: slot and level')
wp = '<?xml version="1.0"?>\n<weapons>\n</weapons>\n'
w1, _n = T.patch_weapons(wp, rows)
nw = len(T.weapon_rows(rows))
check(w1.count('<melee ') + w1.count('<distance ') + w1.count('<wand ') == nw and nw > 100, 'weapons: an entry per weapon')
check(T.patch_weapons(w1, rows)[0] == w1, 'weapons: a second run keeps the block')
check(open(T.LUA_OUT).read() == T.lua_text(rows), 'chaos_gear_sets_items.lua is up to date (install_gear_sets.py --lua)')

print('install_gear_sets_test:', 'OK' if not failed else '%d failure(s)' % failed)
sys.exit(1 if failed else 0)

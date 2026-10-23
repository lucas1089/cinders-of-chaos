#!/usr/bin/env python3
"""python3 -I server/tools/install_fist_weapons_test.py : install_fist_weapons.py on the shipped manifests and on synthetic
text (rows sorted by level, both id offsets checked, duplicate ids refused, items.xml block added / kept / rewritten, the donor
step's bare claw entries taken over, movements for the Monk line, the generated Lua up to date, uniques and prices of the
claw manifest). No base server needed."""
import os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_fist_weapons as T  # noqa: E402
import install_donor_items as D  # noqa: E402

failed = 0
HEAD = 'client_id,server_id,key,kind,mode,name,size,otb_group,otb_flags,top_order,speed,light_level,light_color,extra\n'


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


rows = T.rows_of(T.DEFAULT_MANIFESTS)
ids = [r['server_id'] for r in rows]
by_id = {r['server_id']: r for r in rows}
check(len(rows) == 19 and len(set(ids)) == 19, 'nineteen fist weapons, no duplicate id')
lv = [int(r['ex']['level']) for r in rows]
check(lv == sorted(lv), 'rows sorted by level')
check(lv[0] == 1 and lv[-1] >= 2000, 'a fist weapon from level 1 to the endgame')
check(sum(1 for r in rows if r['mode'] == 'donor') == 13, 'thirteen claw rows')
for r in rows:
    check(r['server_id'] == r['client_id'] + T.ID_OFFSET[r['mode']], 'id offset of ' + r['key'])
uniq = [r for r in rows if r['ex'].get('unique')]
check(len(uniq) == 5, 'five uniques (Pyre plus four)')
for r in uniq:
    check(not r['loot'] and not r['ex'].get('buy'), r['key'] + ': a unique base is in no shop and no loot')
for r in rows:
    check(41 <= int(r['ex']['attack']) <= 70, r['key'] + ': attack in band')
    if not r['ex'].get('unique'):
        check(int(r['ex']['attack']) <= 67, r['key'] + ': a plain claw stays under the uniques')
    if r['ex'].get('buy') and r['ex'].get('sell'):
        check(int(r['ex']['buy']) >= 2 * int(r['ex']['sell']), r['key'] + ': NPC buy at least twice the sell')
    if r['mode'] == 'donor':
        check(28000 <= r['client_id'] <= 28014, r['key'] + ': a look the pair already has (donor B claws)')

with tempfile.TemporaryDirectory() as td:
    a, b = os.path.join(td, 'a.csv'), os.path.join(td, 'b.csv')
    base = '%d,%d,k%d,weapon,%s,w%d,1x1,0,96,0,0,0,0,article=a|weight=500|attack=41|defense=2|level=%d\n'
    open(a, 'w').write(HEAD + base % (28000, 40000, 1, 'donor', 1, 50) + base % (28001, 40001, 2, 'donor', 2, 5))
    open(b, 'w').write(HEAD + base % (28000, 40000, 3, 'donor', 3, 9))
    got = T.rows_of([a])
    check([r['key'] for r in got] == ['k2', 'k1'], 'sorted by level')
    raises(lambda: T.rows_of([a, b]), 'duplicate server ids refused')
    check(len(T.rows_of([a, os.path.join(td, 'missing.csv')])) == 2, 'a missing manifest is skipped')
    open(b, 'w').write(HEAD + base % (28005, 99999, 4, 'donor', 4, 9))
    raises(lambda: T.rows_of([b]), 'a wrong id offset refused')
    open(b, 'w').write(HEAD + base % (33654, 36654, 5, 'new', 5, 9))
    check(T.rows_of([b])[0]['server_id'] == 36654, 'mode new: +3000')

# items.xml: add, keep, rewrite
two = rows[:2]
xml = '<items>\n\t<item id="1" name="x" />\n</items>\n'
out, note = T.patch_xml(xml, two)
check('added' in note and T.XML_BEGIN in out and 'weaponType' in out, 'block added')
out2, note2 = T.patch_xml(out, two)
check(out2 == out and 'up to date' in note2, 'idempotent')
out3, note3 = T.patch_xml(out, two[:1])
check('rewritten' in note3 and out3.count('<item id=') == 2, 'rewritten when the rows change')

# the donor step's bare entry of a claw is taken over, other donor entries stay
bare = '<items>\n\t<item id="40000" name="claw 1" />\n\t<item id="40100" name="other" />\n</items>\n'
out4, _ = T.patch_xml(bare, [by_id[40000]])
check('name="claw 1"' not in out4 and 'id="40100"' in out4 and out4.count('id="40000"') == 1,
      'bare donor entry taken over, others kept')
raises(lambda: T.patch_xml('<items>\n\t<item id="36654" name="y" />\n</items>\n', [by_id[36654]]),
       'an id taken outside the block is refused')

# movements: the level and the Monk line
mv, _ = T.patch_moves('<movements>\n</movements>\n', [by_id[40001]])
check('itemid="40001"' in mv and 'level="35"' in mv and mv.count('<vocation') == 6 // 2 and 'Iron Sage' in mv,
      'Monk line only, at the level')

# the donor step leaves the claimed ids to this tool
check(D.claimed_ids() == {r['server_id'] for r in rows if r['mode'] == 'donor'}, 'donor step claims the claw ids')
dx, _ = D.patch_xml('<items>\n</items>\n', [{'server_id': 40000, 'name': 'claw 1'}, {'server_id': 40014, 'name': 'claw 15'}])
check('id="40000"' not in dx and 'id="40014"' in dx, 'donor xml skips the claimed ids')

# the claws' items.otb node is the same bytes from the donor step and from this tool (no tug of war between the two steps)
import csv  # noqa: E402
from install_pack_items import otb_row, node_bytes as pack_node  # noqa: E402
from install_dark_tiles import node_bytes as donor_node  # noqa: E402
with open(os.path.join(HERE, '..', 'data', 'items', 'donor_items.csv'), newline='') as f:
    donor = {int(r['server_id']): r for r in csv.DictReader(f)}
for r in rows:
    if r['mode'] != 'donor':
        continue
    d = donor.get(r['server_id'])
    check(d is not None and int(d['client_id']) == r['client_id'], r['key'] + ': a donor B look in donor_items.csv')
    if d is not None:
        want = donor_node({'otb_flags': int(d['otb_flags']), 'server_id': int(d['server_id']), 'client_id': int(d['client_id']),
                           'otb_group': int(d['otb_group']), 'speed': int(d['speed'] or 0), 'light_level': int(d['light_level'] or 0),
                           'light_color': int(d['light_color'] or 0), 'top_order': int(d['top_order'] or 0)})
        check(pack_node(otb_row(r)) == want, r['key'] + ': same items.otb node from both steps')

# the shipped generated Lua is up to date
lua = open(os.path.join(HERE, '..', 'data', 'lib', 'chaos_fist_weapons.lua')).read()
check(lua == T.lua_text(rows), 'chaos_fist_weapons.lua is up to date (run install_fist_weapons.py --lua)')

if failed:
    sys.exit(1)
print('install_fist_weapons_test: all ok')

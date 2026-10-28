#!/usr/bin/env python3
"""Test of patch_exercise_weapons.py on stock-shaped snippets (no game data; CI runs it).

    python3 -I server/tools/patch_exercise_weapons_test.py

The 21 stock action lines are commented out once; an item gets its description (added, or replaced), CRLF line ends
are kept; the retired chests leave an NPC list and nothing else does; a second run changes nothing; the item ids and
the retired chests of the tool are the ones of data/scripts/chaos/exercise_config.lua.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_exercise_weapons as P  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


# ---------------------------------------------------------------- actions.xml
IDS = [27732, 27733, 27734, 27735, 27736, 27737, 27738, 27739, 27740, 27741, 27742, 27743, 27744, 27745, 27746, 27747,
       27748, 27749, 27758, 27759, 27760]
ACTIONS = '<actions>\n' + ''.join(
    '\t<action itemid="%d" script="other/exercise_weapons.lua"%s/>\n' % (i, ' allowfaruse="1"' if i in (27735, 27736) else '')
    for i in IDS) + '\t<action itemid="2160" script="other/money.lua" />\n</actions>\n'
new, status = P.patch_actions(ACTIONS)
check(status == 'patched', 'actions patched (%s)' % status)
check(new.count(P.MARK) == 21, '21 lines commented out')
check('<action itemid="2160" script="other/money.lua" />' in new, 'other actions stay')
check(not re.search(r'^\s*<action[^\n]*exercise_weapons', new, re.M), 'no live exercise action is left')
again, status2 = P.patch_actions(new)
check(status2 == 'already' and again == new, 'a second run changes nothing')
check(P.patch_actions('<actions/>')[1].startswith('no '), 'a file without the lines is reported')
crlf, status3 = P.patch_actions(ACTIONS.replace('\n', '\r\n'))
check(status3 == 'patched' and '\r\n' in crlf and '\n\n' not in crlf.replace('\r\n', ''), 'CRLF kept')

# ---------------------------------------------------------------- items.xml
ITEMS = ('<items>\n\t<item id="27732" article="an" name="exercise sword">\n\t\t<attribute key="showCharges" value="1"/>\n'
         '\t\t<attribute key="weight" value="1000"/>\n\t</item>\n'
         '\t<item id="27761" article="a" name="Exercise Sword Chest">\n\t\t<attribute key="weight" value="1000"/>\n'
         '\t\t<attribute key="description" value="Use the chest to obtain 1 exercise weapon." />\n\t</item>\n')
for i in sorted(P.DESCRIPTIONS):
    if i not in (27732, 27761):
        ITEMS += '\t<item id="%d" name="x%d">\n\t\t<attribute key="weight" value="1000"/>\n\t</item>\n' % (i, i)
ITEMS += '</items>\n'
out, problems, changed = P.patch_items(ITEMS)
check(not problems, 'no problems: %s' % problems)
check(changed == len(P.DESCRIPTIONS) == 27, '27 descriptions (%d)' % changed)
fist_part = out.split('id="27733"')[1].split('</item>')[0]
check('Trains fist fighting' in fist_part and 'Monk' in fist_part, 'the fist weapon is described')
check('Monk' not in out.split('id="27732"')[1].split('</item>')[0], 'the sword weapon does not name the Monk')
check('fist training weapon' in out.split('id="27762"')[1].split('</item>')[0], 'the fist chest is described')
check('Trains the melee skill' in out.split('id="27733"')[0].split('id="27732"')[1], 'the sword weapon is described')
check(out.count('key="description"') == 27, 'one description each')
check('Use the chest to obtain 1 exercise weapon.' not in out, 'the old chest text is replaced')
out2, problems2, changed2 = P.patch_items(out)
check(changed2 == 0 and out2 == out, 'a second run changes nothing')
crlf_items, _, c3 = P.patch_items(ITEMS.replace('\n', '\r\n'))
check(c3 == 27 and '\r\n\r\n' not in crlf_items and '\n' not in crlf_items.replace('\r\n', ''), 'CRLF kept in items.xml')
_, problems3, _ = P.patch_items('<items></items>')
check(len(problems3) == 27, 'every missing item is reported')

# ---------------------------------------------------------------- an NPC list
NPC = '''<parameter key="shop_buyable" value="
\tsword,2376,25;
\texercise sword chest, 27761, 100000;
\texercise axe chest, 27762, 100000;
\texercise club chest, 27763, 100000;
\texercise bow chest, 27764, 100000;
\tdurable exercise axe chest, 27769, 360000;
\tdurable exercise club chest, 27770, 360000;
\tlasting exercise axe chest, 27776, 2800000;
\tlasting exercise club chest, 27777, 2800000;
\tlasting exercise shield chest, 27781, 2800000;" />
'''
out, n = P.patch_npc(NPC)
check(n == 6, 'six retired chests removed (%d)' % n)
for keep in ('sword,2376,25;', '27761', '27764', '27781'):
    check(keep in out, keep + ' stays')
for gone in ('27762', '27763', '27769', '27770', '27776', '27777'):
    check(gone not in out, gone + ' is gone')
check(out.endswith('27781, 2800000;" />\n'), 'the list still closes')
check(P.patch_npc(out) == (out, 0), 'a second run changes nothing')
out_crlf, n_crlf = P.patch_npc(NPC.replace('\n', '\r\n'))
check(n_crlf == 6 and '\n' not in out_crlf.replace('\r\n', ''), 'CRLF kept in NPC files')

# ---------------------------------------------------------------- items.otb: the fist weapons take the wraps look
from install_pack_items import scan, node_bytes, otb_row, START, END  # noqa: E402
OTB_ROWS = [{'server_id': sid, 'client_id': cid, 'otb_group': 0, 'otb_flags': 96, 'speed': 0, 'light_level': 0,
             'light_color': 0, 'top_order': 0}
            for sid, cid in ((27732, 27000), (27733, 27001), (27739, 27002), (27745, 27003), (27735, 27004))]
RAW = bytes(4) + bytes([START]) + bytes(6) + b''.join(node_bytes(otb_row(r)) for r in OTB_ROWS) + bytes([END])
out, n = P.patch_otb_looks(RAW)
check(n == 3, 'three fist weapons got a new look (%d)' % n)
kids = {k[2]: k[3] for k in scan(out)[0]}
check(kids[27733] == 33654 and kids[27739] == 33655 and kids[27745] == 33656, 'the wraps, cestus and ember knuckles looks')
check(kids[27732] == 27000 and kids[27735] == 27004, 'the sword weapon and the bow keep their look')
out2, n2 = P.patch_otb_looks(out)
check(n2 == 0 and out2 == out, 'a second run changes nothing')
try:
    P.patch_otb_looks(bytes(4) + bytes([START]) + bytes(6) + node_bytes(otb_row(OTB_ROWS[0])) + bytes([END]))
    check(False, 'a missing fist weapon node is an error')
except SystemExit:
    pass

# ---------------------------------------------------------------- the same lists as the Lua config
with open(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'exercise_config.lua'), encoding='utf-8') as f:
    lua = f.read()
items_block = lua[lua.index('items = {'):lua.index('tiers = {')]
kinds = {int(a): b for a, b in re.findall(r'\[(\d+)\] = "(\w+)"', items_block)}
check(sorted(kinds) == sorted(IDS), 'the tool and exercise_config.lua list the same 21 weapons')
for iid, kind in kinds.items():
    want = {'melee': P.MELEE, 'fist': P.FIST, 'ranged': P.RANGED, 'rod': P.MAGIC, 'wand': P.MAGIC, 'shield': P.SHIELD}[kind]
    check(P.WEAPONS.get(iid) == want, 'description of %d matches its kind %s' % (iid, kind))
retired = [int(x) for x in re.search(r'retiredChests = \{([^}]*)\}', lua).group(1).replace(' ', '').split(',')]
check(set(retired) <= set(P.RETIRED_CHESTS), 'the retired chests are among the ones no NPC sells')
check(set(P.RETIRED_CHESTS) - set(retired) == {27762, 27769, 27776}, 'the other NPC-less chests are the fist ones')
with open(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'commands_ui_core.lua'), encoding='utf-8') as f:
    ui = f.read()
hidden = sorted(int(x) for x in re.findall(r'\[(\d+)\] = true', ui[ui.index('retiredItems'):ui.index('retiredItems') + 400]))
check(hidden == sorted(retired), 'the Ancestral Store hides the same chests')
check(set(P.CHESTS) == {27761, 27768, 27775, 27762, 27769, 27776}, 'the three melee and the three fist chests')
check(P.FIST_LOOKS == {27733: 33654, 27739: 33655, 27745: 33656}, 'the fist weapon looks')

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('patch_exercise_weapons_test: OK')

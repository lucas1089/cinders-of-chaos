"""Test of audit_equip_tooltips.py, equip_rules.py and install_equip_rules.py on small synthetic files, one per mismatch kind
(run: python3 -I server/tools/audit_equip_tooltips_test.py; needs luajit or lua5.3, as the server tests do)."""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import contextlib
import io
import audit_equip_tooltips as A
import equip_rules as R
import install_equip_rules as I

fails = 0


def quiet(fn, *args):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*args)


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


# ---- the reading of the class chips
check(R.read_chips('Mystic') == frozenset(('Mystic', 'Elementalist', 'Illusionist')), 'a base class alone is its whole line')
check(R.read_chips('Mystic, Illusionist, Necromancer') == frozenset(('Mystic', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord')),
      'a line named class by class and a line named by its base')
check(R.read_chips('Mystic only') == frozenset(('Mystic',)), 'Name only is that class alone')
check(R.read_chips('Deadeye, Ninja') == frozenset(('Deadeye', 'Ninja')), 'ascended classes without their base')
check(R.read_chips('all classes') == R.ALL_SET and R.read_chips(None) == R.ALL_SET and len(R.ALL_SET) == 21, 'all classes')
check(R.read_chips('Warrior, Juggernaut, Berserker') == R.read_chips('Warrior'), 'a base and both ascended classes is the whole line')
check(R.read_chips('knights') == frozenset(('knights',)), 'a name the table does not know stays as it is')
check(R.vocation_string([('Mystic', True), ('Illusionist', False), ('Necromancer', True)]) == 'mystics and necromancers',
      'the engine string holds the shown vocations only')
check(R.vocation_string([('Thief', True), ('Monk', True), ('Templar', True)]) == 'thiefs, monks and templars', 'three names')

# ---- a synthetic installed folder
VOCS = {'Mystic': 1, 'Ranger': 3, 'Warrior': 4, 'Elementalist': 5, 'Deadeye': 7, 'Juggernaut': 8, 'Illusionist': 10, 'Thief': 11,
        'Ninja': 12, 'Samurai': 13, 'Berserker': 14, 'Beastmaster': 15, 'Monk': 17, 'Shadowfist': 18, 'Iron Sage': 19,
        'Necromancer': 20, 'Lich': 21, 'Bone Lord': 22, 'Templar': 23, 'Inquisitor': 24, 'Sentinel': 25}
MYSTIC_NECRO = ['Mystic', 'Elementalist', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord']
NO_ELEMENTALIST = ['Mystic', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord']
RANGER_LINE = ['Ranger', 'Deadeye', 'Beastmaster']


def voc_nodes(names, shown):
    out = ''
    for n in names:
        out += '\t\t<vocation name="%s"%s />\n' % (n, '' if n in shown else ' showInDescription="0"')
    return out


def equip(iid, slot, level=0, magic=0, names=(), shown=(), script=''):
    head = '\t<movevent event="Equip" itemid="%d" slot="%s"%s%s function="onEquipItem"%s' % (
        iid, slot, ' level="%d"' % level if level else '', ' maglevel="%d"' % magic if magic else '',
        ' script="%s"' % script if script else '')
    if names:
        return head + '>\n' + voc_nodes(names, shown) + '\t</movevent>\n'
    return head + ' />\n'


def weapon(tag, iid, level=0, magic=0, names=(), shown=(), unproperly=False):
    head = '\t<%s id="%d"%s%s%s' % (tag, iid, ' level="%d"' % level if level else '', ' maglv="%d"' % magic if magic else '',
                                    ' unproperly="1"' if unproperly else '')
    if names:
        return head + '>\n' + voc_nodes(names, shown) + '\t</%s>\n' % tag
    return head + ' />\n'


# one item per kind (ids: 100 wand, 101 sword, 102 sword, 103 axe, 104 club, 105 bow, 106 helmet, 107 helmet, 3961 unique staff)
ITEMS = [(100, 'test wand', 'wand', ''), (101, 'test sword', 'sword', ''), (102, 'test mace', 'club', ''),
         (103, 'test axe', 'axe', ''), (104, 'test club', 'club', ''), (105, 'test bow', 'distance', ''),
         (106, 'test helmet', '', 'head'), (107, 'test cap', '', 'head'), (3961, 'lichfang test', 'club', '')]


def make_folder(root):
    for sub in ('XML', 'items', 'movements/scripts', 'weapons'):
        os.makedirs(os.path.join(root, sub), exist_ok=True)
    with open(os.path.join(root, 'XML', 'vocations.xml'), 'w') as f:
        f.write('<vocations>\n\t<vocation id="0" name="None" />\n' + ''.join(
            '\t<vocation id="%d" name="%s" />\n' % (i, n) for n, i in VOCS.items()) + '</vocations>\n')
    with open(os.path.join(root, 'items', 'items.xml'), 'w') as f:
        f.write('<items>\n')
        for iid, name, wt, st in ITEMS:
            f.write('\t<item id="%d" name="%s">\n' % (iid, name))
            if wt:
                f.write('\t\t<attribute key="weaponType" value="%s" />\n' % wt)
            if st:
                f.write('\t\t<attribute key="slotType" value="%s" />\n' % st)
            if iid == 105:
                f.write('\t\t<attribute key="slotType" value="two-handed" />\n')
            f.write('\t</item>\n')
        f.write('</items>\n')
    mv = ['<movements>\n',
          # 100: the wand of the Mystic and the Illusionist (the Elementalist is refused), the ascended classes hidden
          equip(100, 'hand', 10, 0, NO_ELEMENTALIST, ['Mystic', 'Necromancer']),
          # 101: refused at 100, the weapon entry asks 50
          equip(101, 'hand', 100),
          # 102: refused for magic level 20, the weapon entry asks none
          equip(102, 'hand', 5, 20),
          # 103, 104: the Equip entry asks less than the weapon entry
          equip(103, 'hand', 10), equip(104, 'hand', 1),
          # 105: a bow of the Ranger line (the ascended classes hidden)
          equip(105, 'hand', 30, 0, RANGER_LINE, ['Ranger']),
          equip(106, 'head', 30), equip(107, 'head', 5),
          equip(3961, 'hand'),
          '</movements>\n']
    with open(os.path.join(root, 'movements', 'movements.xml'), 'w') as f:
        f.write(''.join(mv))
    wp = ['<weapons>\n',
          weapon('wand', 100, 10, 0, NO_ELEMENTALIST, ['Mystic', 'Necromancer']),
          weapon('melee', 101, 50, 0, (), (), True),
          weapon('melee', 102, 5, 0, (), (), True),
          weapon('melee', 103, 40, 0, (), (), True),
          weapon('melee', 104, 1, 15, (), (), True),
          '</weapons>\n']
    with open(os.path.join(root, 'weapons', 'weapons.xml'), 'w') as f:
        f.write(''.join(wp))


tmp = tempfile.mkdtemp(prefix='equipauditest')
try:
    folder = os.path.join(tmp, 'data')
    make_folder(folder)

    # ---- the rules
    rules = R.Rules(folder)
    check(rules.refusal(100)['set'] == frozenset(NO_ELEMENTALIST), 'refusal: the whole list, shown or hidden')
    check(rules.weapon(100)['set'] == frozenset(NO_ELEMENTALIST) and rules.weapon(101)['unproperly'], 'weapon rule')
    check(rules.effective(101)['level'] == 100 and rules.effective(103)['level'] == 40, 'effective: the higher level')
    check(rules.effective(106)['set'] is None and rules.weapon(106) is None, 'an Equip entry alone')
    check(rules.item_type(101, True)[0] == 50 and rules.item_type(101, False)[0] == 100, 'the entry read last wins')
    check(rules.item_type(100)[2] == 'mystics and necromancers', 'the item type holds the shown vocations only')

    # ---- before: no rules file; the tooltip reads the engine's item type
    res = A.audit(folder)
    found = {k: v for k, v in res['found'].items()}

    def kinds(copy, iid):
        return found.get((copy, iid), [])

    check('refused: class' in kinds('P', 100) and 'weapon check: class' in kinds('P', 100),
          'a wand whose list hides the Illusionist and has no Elementalist: refused and penalty (%r)' % kinds('P', 100))
    check(res['shown'][('P', 100)]['voc'] == 'Mystic, Necromancer', 'the old text of that wand')
    check('refused: level' in kinds('P', 101), 'the item type holds the weapon entry\'s 50, the Equip entry refuses under 100 (%r)' % kinds('P', 101))
    check('refused: magic level' in kinds('P', 102), 'the Equip entry\'s magic level is not shown (%r)' % kinds('P', 102))
    check('tooltip stricter: class' in kinds('P', 105), 'a bow of the Ranger line shows no Beastmaster (%r)' % kinds('P', 105))
    check(kinds('P', 106) == [] and kinds('P', 107) == [], 'a plain Equip entry is shown right')
    check(('U', 3961) in found and found[('U', 3961)] == ['tooltip stricter: level'],
          'a unique copy shows its own level, the server does not ask it (%r)' % found.get(('U', 3961)))
    check(res['longest'][0] > 0, 'the longest class row is measured')
    text = '\n'.join(A.report(res))
    check('Mismatches by kind' in text and 'refused: class' in text and 'Longest class row' in text, 'the report')
    check(quiet(A.main, [folder, "--check"]) == 1, '--check fails on a refused kind')

    # the other order of the two entries: the Equip entry's numbers are shown, the weapon entry's are penalties
    res_last = A.audit(folder, weapons_last=False)
    check('weapon check: level' in res_last['found'].get(('P', 103), []), 'movements last: the weapon level is not shown (%r)' % res_last['found'].get(('P', 103)))
    check('weapon check: magic level' in res_last['found'].get(('P', 104), []), 'movements last: the weapon magic level is not shown')

    # ---- the install step: the same folder, then the audit again
    text_a, n = I.build(folder)
    check(n >= 5, 'rules written for the ids with a class list or a disagreement (%d)' % n)
    check('[106]' not in text_a and '[100]' in text_a and '[101]' in text_a, 'an Equip entry alone with no class list is left out')
    check(quiet(I.main, [folder, "--dry-run"]) == 0 and not os.path.exists(os.path.join(folder, 'lib', 'chaos_equip_rules.lua')), 'dry run writes nothing')
    check(quiet(I.main, [folder]) == 0, 'the step runs')
    path = os.path.join(folder, 'lib', 'chaos_equip_rules.lua')
    first = R.read(path)
    check(quiet(I.main, [folder]) == 0 and R.read(path) == first, 'a second run changes nothing')
    res2 = A.audit(folder)
    refusals = {k: v for k, v in res2['found'].items() if any(x in A.FAIL_KINDS for x in v)}
    check(not refusals, 'after the step no tooltip says yes to a refused item (%r)' % refusals)
    check(res2['shown'][('P', 100)]['voc'] == 'Mystic, Illusionist, Necromancer', 'the wand names the Mystic, the Illusionist and the Necromancer line')
    check(res2['shown'][('P', 101)]['level'] == 100 and res2['shown'][('P', 102)]['magic'] == 20, 'the Equip entry\'s level and magic level show')
    check(res2['shown'][('P', 105)]['voc'] == 'Ranger', 'the bow names the whole Ranger line')
    check(quiet(A.main, [folder, "--check"]) == 0, '--check passes after the step')
    other = A.audit(folder, weapons_last=False)
    check(not other['found'].get(('P', 103)) and not other['found'].get(('P', 104)), 'the rule does not depend on the order the engine read the files in')

    # ---- a stale rules file: the tooltip says no where the server says yes
    def with_rule(row):
        # a later key wins in a Lua table constructor: the row goes in at the end
        head, tail = first.rsplit('\t},\n}', 1)
        with open(path, 'w') as f:
            f.write(head + '\t\t' + row + ',\n\t},\n}' + tail)

    with_rule('[107] = {99, 0, 7}')
    res3 = A.audit(folder)
    k107 = res3['found'].get(('P', 107), [])
    check('tooltip stricter: level' in k107 and 'tooltip stricter: magic level' in k107, 'a stale level and magic level are found (%r)' % k107)
    # a stale file that names too few classes
    with_rule('[106] = {30, 1}')
    res4 = A.audit(folder)
    check('refused: class' not in res4['found'].get(('P', 106), []) and 'tooltip stricter: class' in res4['found'].get(('P', 106), []),
          'a stale class list that is too small is the lesser kind (%r)' % res4['found'].get(('P', 106)))
    # a stale file that names too many classes
    with_rule('[105] = {10, 0}')
    res5 = A.audit(folder)
    k105 = res5['found'].get(('P', 105), [])
    check('refused: level' in k105 and 'refused: class' in k105, 'a stale level and a stale every-class list are refusals (%r)' % k105)
    # the longest row never reaches the cut
    check(res['longest'][0] < A.ROW_LIMIT, 'no class row reaches the limit')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print('audit_equip_tooltips_test: %s' % ('ok' if not fails else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)

#!/usr/bin/env python3
"""Tests of patch_stock_weapon_types.py and of the table that feeds it (O500, server/README.md "Stock weapon types (O500)"):
python3 -I server/tools/patch_stock_weapon_types_test.py

Part 1, the tool on synthetic items.xml files (written here in the stock shape, LF and CRLF, made-up items): a dry run writes nothing;
the old type becomes the new one and nothing else changes (a byte diff of one attribute value per item); a second run says "right" and
changes no byte; an item that already has the new type is "already done"; an item with a third type is reported and left; an item
that is not there is reported; a row with new = old is a decision to keep and writes nothing; a self-closing item in front of a table
item does not swallow it; an item without a weaponType is left alone; a bad table (a kind that is no melee kind, an id twice) is
refused; the install step is wired before every step that reads a weapon type.
Part 2, the repository: the committed table is well formed (a reason on every row, ids once, at most 15 moves), Twin Hooks is a two-handed
sword in it, the committed base_weapons.csv (the survey of an installed server) has the NEW kind on every row of the table (the survey of a
copy patched by this tool gives exactly that file: the proof of O500), the keep rows have their old kind there, the step and its docs
and CI line exist."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
import patch_stock_weapon_types as P

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


def read(path):
    with open(path, 'rb') as f:
        return f.read().decode('utf-8')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8'))


def run(data, *flags):
    proc = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_stock_weapon_types.py'), data] + list(flags),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return proc.returncode, proc.stdout


def item(wid, name, wt, two=False, extra=''):
    lines = ['\t<item id="%d" name="%s">' % (wid, name), '\t\t<attribute key="weight" value="5000" />']
    if wt:
        lines.append('\t\t<attribute key="weaponType" value="%s" />' % wt)
    if two:
        lines.append('\t\t<attribute key="slotType" value="two-handed" />')
    lines.append('\t\t<attribute key="attackspeed" value="3000" />')
    if extra:
        lines.append(extra)
    lines.append('\t</item>')
    return '\n'.join(lines)


TABLE = '''id,name,old,new,reason
100,made up hooks,axe,sword,"hooked blades, held like swords"
101,made up great axe,sword,axe,the name says axe
102,made up crusher,sword,club,the name says club
103,made up lance,axe,axe,kept: a polearm
104,made up scythe,axe,sword,a long curved blade
105,made up third,axe,sword,the item has a third type here
106,made up missing,axe,sword,not in the file
'''


def items_xml(eol):
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>', '<items>',
        item(100, 'made up hooks', 'axe', True),
        item(101, 'made up great axe', 'sword', True),
        item(102, 'made up crusher', 'club', True),           # table: sword -> club; it is already a club: already done
        item(103, 'made up lance', 'axe', True),
        '\t<item id="99" name="made up self closing" />',      # a self-closing item right before a table item
        item(104, 'made up scythe', 'axe', True),
        item(105, 'made up third', 'club', True),             # third type
        item(107, 'made up shield', None),                    # no weaponType; not in the table
        item(108, 'made up bystander', 'axe', True),          # an axe the table does not name
        '</items>', ''
    ]
    return eol.join('\n'.join(parts).split('\n'))


def changed_lines(a, b):
    al, bl = a.split('\n'), b.split('\n')
    check(len(al) == len(bl), 'the line count is kept')
    return [(x, y) for x, y in zip(al, bl) if x != y]


tmp = tempfile.mkdtemp(prefix='o500test_')
try:
    table = os.path.join(tmp, 'table.csv')
    write(table, TABLE)
    for eol, label in (('\n', 'LF'), ('\r\n', 'CRLF')):
        data = os.path.join(tmp, 'data_' + label)
        path = os.path.join(data, 'items', 'items.xml')
        text = items_xml(eol)
        write(path, text)
        # dry run: nothing written
        rc, out = run(data, '--dry-run', '--table', table)
        check(rc == 0 and read(path) == text, label + ': a dry run writes nothing')
        check('made up hooks: axe -> sword' in out, label + ': the dry run says what it would do: ' + out)
        # first run
        rc, out = run(data, '--table', table)
        new = read(path)
        check(rc == 0, label + ': first run succeeds')
        diff = changed_lines(text.replace('\r\n', '\n'), new.replace('\r\n', '\n'))
        check(len(diff) == 3, label + ': three items move (100, 101 and 104), %d lines changed' % len(diff))
        check(all(re.sub(r'value="\w+"', '', x) == re.sub(r'value="\w+"', '', y) for x, y in diff), label + ': only a value changes')
        check(('\r\n' in new) == (eol == '\r\n'), label + ': the line ends are kept')
        check(re.search(r'id="100"[^>]*>\s*<attribute key="weight" value="5000" />\s*<attribute key="weaponType" value="sword"', new) is not None,
              label + ': the hooks are a sword')
        check(re.search(r'id="104"[^>]*>\s*<attribute key="weight" value="5000" />\s*<attribute key="weaponType" value="sword"', new) is not None,
              label + ': the scythe after a self-closing item is a sword')
        check(re.search(r'id="105".*?weaponType" value="club"', new, re.S) is not None, label + ': a third type is left')
        check(re.search(r'id="108".*?weaponType" value="axe"', new, re.S) is not None, label + ': an item not in the table is left')
        check(re.search(r'id="103".*?weaponType" value="axe"', new, re.S) is not None, label + ': a keep row writes nothing')
        check(re.search(r'id="101"[^>]*>\s*<attribute key="weight" value="5000" />\s*<attribute key="weaponType" value="axe"', new) is not None,
              label + ': 101 was a sword, the table says sword -> axe: it moved')
        check(re.search(r'id="102"[^>]*>\s*<attribute key="weight" value="5000" />\s*<attribute key="weaponType" value="club"', new) is not None,
              label + ': 102 was a club already: left')
        check('WARNING: 105 made up third has the type club' in out, label + ': the third type is reported: ' + out)
        check('WARNING: 106 made up missing is not in items.xml' in out, label + ': a missing item is reported')
        check('3 stock weapon(s)' in out and '1 already done' in out and '1 kept on purpose' in out, label + ': the counts are named: ' + out)
        # second run: nothing to do
        rc, out2 = run(data, '--table', table)
        check(rc == 0 and read(path) == new, label + ': a second run changes no byte')
        check('the stock weapon types are right' in out2 and 'already done' in out2, label + ': it says so: ' + out2)
    # pin the exact number of moves of the first run
    data = os.path.join(tmp, 'data_count')
    write(os.path.join(data, 'items', 'items.xml'), items_xml('\n'))
    rc, out = run(data, '--table', table)
    check(len(re.findall(r'^  \d+ [^\n]*: \w+ -> \w+$', out, re.M)) == 3, 'three moves (100, 101, 104): ' + out)
    # a tool run with no items.xml
    rc, out = run(os.path.join(tmp, 'nothing'), '--table', table)
    check(rc == 1 and 'not found' in out, 'no items.xml: refused')
    # a bad table
    bad = os.path.join(tmp, 'bad.csv')
    write(bad, 'id,name,old,new,reason\n1,x,axe,spear,why\n')
    try:
        P.read_table(bad)
        check(False, 'a kind that is no melee kind is refused')
    except SystemExit as e:
        check('sword, axe or club' in str(e), 'the refusal says why')
    write(bad, 'id,name,old,new,reason\n1,x,axe,sword,why\n1,y,axe,sword,why\n')
    try:
        P.read_table(bad)
        check(False, 'an id twice is refused')
    except SystemExit as e:
        check('twice' in str(e), 'the refusal names the id')
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# ------------------------------------------------------------------------------------------------ part 2, the repository
rows = P.read_table()
moves = [r for r in rows if r['old'] != r['new']]
keeps = [r for r in rows if r['old'] == r['new']]
check(len(moves) > 0 and len(moves) <= 15, 'at most 15 silent moves: %d' % len(moves))
check(all(len(r['reason'].strip()) > 10 for r in rows), 'a reason on every row')
twin = [r for r in rows if r['id'] == 11309]
check(len(twin) == 1 and twin[0]['old'] == 'axe' and twin[0]['new'] == 'sword', 'Twin Hooks: axe -> sword')
# base_weapons.csv: the survey of an installed server (patched by this tool); the kind column says what the game sees
csv_kind = {}
two_hands = {}
with open(os.path.join(SERVER, 'data', 'items', 'base_weapons.csv'), encoding='utf-8') as f:
    for line in f.read().split('\n')[1:]:
        c = line.split(',')
        if len(c) > 2 and c[0].isdigit():
            csv_kind[int(c[0])] = c[1]
            two_hands[int(c[0])] = c[2]
for r in moves:
    check(csv_kind.get(r['id']) == r['new'], 'base_weapons.csv has the new kind %s on %d %s (has %s)' % (r['new'], r['id'], r['name'], csv_kind.get(r['id'])))
for r in keeps:
    check(csv_kind.get(r['id']) == r['old'], 'base_weapons.csv has the kept kind on %d %s' % (r['id'], r['name']))
check(two_hands.get(11309) == '2', 'Twin Hooks stay two-handed')

# the step: before vocations (add_vocations reads the weapon types) and every later reader
src = read(os.path.join(HERE, 'install_all.py'))
m = re.search(r"STEPS\s*=\s*\[([^\]]*)\]", src)
base_steps = re.findall(r"'(\w+)'", m.group(1))
check('monsternames' in base_steps, 'the base step list names monsternames')
check("STEPS.insert(STEPS.index('monsternames') + 1, 'weapontypes')" in src, 'weapontypes is inserted right after monsternames')
check('def step_weapontypes(' in src and "patch_stock_weapon_types.py" in src, 'the step runs the tool')
check(src.index("'weapontypes'") < src.index("def step_vocations("), 'the step is defined before vocations')
check(re.search(r"^  weapontypes  tools/patch_stock_weapon_types\.py", src, re.M) is not None, 'the docstring lists the step')
check("--dry-run'] if ctx['dry']" in src[src.index('def step_weapontypes('):src.index('def step_vocations(')], 'the step passes --dry-run')
doc_start = src.index('"""') + 3
doc_steps = re.findall(r"^  (\w+)\s+tools/", src[doc_start:src.index('"""', doc_start)], re.M)
check(doc_steps.index('weapontypes') < doc_steps.index('vocations'), 'the docstring lists it before vocations')
check('weapongrowth' in doc_steps and doc_steps.index('weapontypes') < doc_steps.index('weapongrowth'), 'and before the weapon growth')
readme = read(os.path.join(SERVER, 'README.md'))
check('Stock weapon types (O500)' in readme and 'patch_stock_weapon_types.py' in readme, 'README: the section and the step')
ci = read(os.path.join(ROOT, '.github', 'workflows', 'ci.yml'))
check('patch_stock_weapon_types_test.py' in ci and 'audit_weapon_types_test.py' in ci, 'ci.yml runs both tests')
check('patch_stock_weapon_types_test.py' in read(os.path.join(ROOT, 'CLAUDE.md')), 'CLAUDE.md: the command line')

if fails:
    print('%d check(s) failed' % fails)
    sys.exit(1)
print('patch_stock_weapon_types_test: ok (%d rows, %d moves, %d kept)' % (len(rows), len(moves), len(keeps)))

#!/usr/bin/env python3
"""Test of monster_spells.py (owner report 2026-10-21: "Unknown spell name: arc bolt" / "dread" after the spell cap)
and of the monster-safe retirement in retire_cure_spells.py and patch_spell_cap.py:
  * references(): XML <attack>/<defense> names and Lua monster.attacks / monster.defenses names, without built-ins,
    script entries, unregistered XML (unless all_xml), disabled ("#") Lua files; names with an apostrophe;
  * monster_only(): "###chaos" words, needlearn="1", no <vocation>, no spellid; idempotent;
  * both retire tools: a spell a monster names (stock or Chaos name) gets the monster-only form instead of the
    comment, a comment of an earlier run comes back in that form, a spell no monster names is still commented out,
    a monster-only spell no monster names any more is commented out (its marker goes too), a second run changes
    nothing; the command line (needed_names on a data folder) repairs an installed spells.xml;
  * unknown() / the command line: exit 1 and the name while a monster names a missing spell, 0 after the repair;
  * rename_spells.py --sql deletes the learned rows of the monster-only spells.
Run: python3 -I server/tools/monster_spells_test.py"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import monster_spells as M  # noqa: E402
import patch_spell_cap as C  # noqa: E402
import retire_cure_spells as R  # noqa: E402

fails = []


def check(c, what):
    if not c:
        fails.append(what)
        print('FAIL ' + what)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8', newline='').write(text)


def tool(name, *args):
    return subprocess.run([sys.executable, '-I', os.path.join(HERE, name)] + list(args), capture_output=True, text=True)


ARC = ('\t<instant group="attack" spellid="88" name="Arc Bolt" words="kah zhul" level="12" mana="20" range="3" '
       'needlearn="0" script="attack/energy_strike.lua">\n\t\t<vocation name="Mystic" />\n'
       '\t\t<vocation name="Elementalist" showInDescription="0" />\n\t</instant>\n')
DREAD = ('\t<instant group="support" spellid="60" name="Dread" words="drai skre" level="80" mana="200" '
         'script="custom/illusionist_class/fear.lua">\n\t\t<vocation name="Illusionist" />\n\t</instant>\n')
GAZE = ('\t<instant group="attack" spellid="87" name="Gravetouch" words="mor zhul" level="16" '
        'script="attack/death_strike.lua">\n\t\t<vocation name="Mystic" />\n\t</instant>\n')
HAWK = ('\t<instant group="support" spellid="135" name="Hawkeye" words="vyr ira sol" level="60" '
        'script="support/sharpshooter.lua">\n\t\t<vocation name="Ranger" />\n\t</instant>\n')
POISON = ('\t<instant group="healing" spellid="29" name="Purge Venom" words="exana pox" level="10" '
          'script="healing/cure_poison.lua">\n\t\t<vocation name="Ranger" />\n\t</instant>\n')
CHAOS = '\t<!-- BEGIN chaos spells (x) -->\n\t<instant group="attack" spellid="250" name="Cinderstorm" words="a b" ' \
        'script="chaos/x.lua">\n\t\t<vocation name="Mystic" />\n\t</instant>\n\t<!-- END chaos spells -->\n'
XML = '<spells>\n' + ARC + DREAD + GAZE + HAWK + POISON + CHAOS + '</spells>\n'

# ------------------------------------------------------------------ monster_only()
mo = M.monster_only(ARC.strip())
check(mo.startswith('<instant ') and mo.endswith('/>') and '<vocation' not in mo, 'monster-only: self-closing, no vocation')
check('words="###chaos energy_strike"' in mo and 'needlearn="1"' in mo and 'spellid' not in mo, 'monster-only: ' + mo)
check('name="Arc Bolt"' in mo and 'script="attack/energy_strike.lua"' in mo, 'monster-only keeps name and script')
check(M.monster_only(mo) == mo and M.is_monster_only(mo) and not M.is_monster_only(ARC), 'monster-only is idempotent')
short = M.monster_only('<instant name="X" words="y" script="a/b.lua" />')
check(short == '<instant name="X" words="###chaos b" script="a/b.lua" needlearn="1" />', 'short tag: ' + short)

# ------------------------------------------------------------------ references()
with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    write(os.path.join(data, 'monster', 'monsters.xml'), '<monsters>\n<monster name="A" file="monsters/a.xml" />\n'
          '<!-- <monster name="C" file="monsters/c.xml" /> -->\n</monsters>\n')
    write(os.path.join(data, 'monster', 'monsters', 'a.xml'),
          '<monster name="A"><attacks><attack name="melee" /><attack name="Arc Bolt" chance="10" />'
          '<attack name="firecondition" /><attack name="x" script="x.lua" /><!-- <attack name="old" /> -->'
          '</attacks><defenses><defense name="healing" /><defense name="dread" /></defenses></monster>\n')
    write(os.path.join(data, 'monster', 'monsters', 'c.xml'),
          '<monster name="C"><attacks><attack name="Gravetouch" /></attacks></monster>\n')
    write(os.path.join(data, 'monster', 'lua', 'b.lua'),
          'local monster = {}\nmonster.attacks = {\n\t{name ="melee", interval = 2000},\n'
          '\t{name ="combat", type = COMBAT_FIREDAMAGE, condition = {type = CONDITION_FIRE, name = "inner"}},\n'
          '\t{name ="reaver\'s spin", interval = 2000, chance = 20},\n'
          '\t{name = "scripted", script = "s.lua"},\n'
          '\t-- {name = "commented"},\n}\nmonster.defenses = {\n\tdefense = 5,\n\t{name ="Frostbite", chance = 5}\n}\n'
          'monster.loot = {\n\t{name = "gold coin", chance = 100}\n}\n')
    write(os.path.join(data, 'monster', 'lua', '#off.lua'), 'monster.attacks = {\n\t{name ="off spell"}\n}\n')
    write(os.path.join(data, 'monster', 'lua', 'lib', 'x.lua'), 'monster.attacks = {\n\t{name ="lib spell"}\n}\n')
    refs = M.references(data)
    check(sorted(refs) == ['arc bolt', 'dread', 'frostbite', "reaver's spin"], 'references: %s' % sorted(refs))
    check('gravetouch' in M.references(data, all_xml=True), 'all_xml: unregistered files count')
    extra = os.path.join(tmp, 'repo')
    write(os.path.join(extra, 'm.xml'), '<monster name="M"><attacks><attack name="Stormlance" /></attacks></monster>')
    check('stormlance' in M.references(data, extra_dirs=[extra]), 'extra_dirs: the repo monsters count')
    want = M.wanted(refs)
    check({'arc bolt', 'energy strike', 'dread', 'fear', 'frostbite', 'ice strike'} <= want,
          'wanted: stock and Chaos names: %s' % sorted(want))

    # ------------------------------------------------------------------ the two retire tools on a small spells.xml
    needed = M.wanted({'arc bolt': [], 'dread': [], 'hawkeye': []})
    new, removed, retired, kept = C.patch(XML, needed)
    check((retired, kept) == (1, 2), 'cap: Gravetouch retired, Arc Bolt and Dread kept: %d %d' % (retired, kept))
    check('<!-- ' + C.MARK + '<instant group="attack" spellid="87" name="Gravetouch"' in new, 'cap: Gravetouch commented')
    arc = re.search(r'<instant[^>]*name="Arc Bolt"[^>]*/>', new)
    check(arc and 'needlearn="1"' in arc.group(0) and 'spellid' not in arc.group(0) and 'words="###chaos ' in arc.group(0),
          'cap: Arc Bolt monster-only')
    check('<!-- %sArc Bolt -->\n\t<instant' % M.MONSTER_ONLY_MARK in new, 'cap: the marker before Arc Bolt, same indent')
    check(re.sub(r'<!--.*?-->', '', new, flags=re.S).count('<vocation') == 3 and 'name="Cinderstorm"' in new, 'cap: only Hawkeye, Purge Venom, Chaos keep classes')
    check(C.patch(new, needed) == (new, 0, 0, 0), 'cap: a second run changes nothing')
    new2, n, kept2 = R.patch(new, needed)
    check((n, kept2) == (1, 1) and '<!-- ' + R.MARK + '<instant group="healing" spellid="29"' in new2
          and re.search(r'<instant[^>]*name="Hawkeye"[^>]*words="###chaos sharpshooter"', new2), 'cure: %d %d' % (n, kept2))
    check(R.patch(new2, needed) == (new2, 0, 0), 'cure: a second run changes nothing')

    # the old behaviour (commented out) is repaired by either tool
    old, _, retired_old, _ = C.patch(XML)
    old, _, _ = R.patch(old)
    check(retired_old == 3 and 'words="###chaos' not in old, 'without monsters: everything commented out')
    rep, n, kept3 = R.patch(old, needed)
    check(n == 0 and kept3 == 3, 'cure tool brings back Arc Bolt, Dread and Hawkeye: %d %d' % (n, kept3))
    check(C.patch(rep, needed)[0] == rep and R.patch(rep, needed)[0] == rep, 'repair: idempotent')
    rep2 = C.patch(old, needed)[0]
    check(rep2.count('words="###chaos') == 3, 'cap tool brings back the same three')
    check(rep == new2, 'repaired == installed with the fix')
    # no monster names it any more: commented out again, its marker goes
    gone, _, retired4, kept4 = C.patch(new2, M.wanted({'dread': []}))
    active = re.sub(r'<!--.*?-->', '', gone, flags=re.S)
    check(retired4 == 1 and 'name="Arc Bolt"' not in active and C.MARK + '<instant group="attack" name="Arc Bolt"' in gone
          and '%sArc Bolt' % M.MONSTER_ONLY_MARK not in gone and '%sDread' % M.MONSTER_ONLY_MARK in gone,
          'a monster-only spell no monster needs is commented out')

    # ------------------------------------------------------------------ command line: repair of an installed server
    write(os.path.join(data, 'spells', 'spells.xml'), old)
    r = tool('monster_spells.py', data)
    check(r.returncode == 1 and '"arc bolt"' in r.stdout and '"dread"' in r.stdout, 'check finds the lost spells: ' + r.stdout)
    r1 = tool('retire_cure_spells.py', data)
    r2 = tool('patch_spell_cap.py', data)
    fixed = open(os.path.join(data, 'spells', 'spells.xml'), encoding='utf-8').read()
    check('brought back' in r1.stdout and 'words="###chaos energy_strike"' in fixed and 'words="###chaos fear"' in fixed,
          'command line repair: ' + r1.stdout + r2.stdout)
    r = tool('monster_spells.py', data)
    check('"arc bolt"' not in r.stdout and '"dread"' not in r.stdout, 'check after the repair: ' + r.stdout)
    os.remove(os.path.join(data, 'monster', 'lua', 'b.lua'))  # frostbite and reaver's spin: not in this spells.xml
    r = tool('monster_spells.py', data)
    check(r.returncode == 0 and '0 unknown' in r.stdout, 'check, every name known: ' + r.stdout)
    check('nothing' in tool('retire_cure_spells.py', data).stdout and 'nothing' in tool('patch_spell_cap.py', data).stdout,
          'second command line run changes nothing')
    sql = os.path.join(tmp, 'r.sql')
    tool('rename_spells.py', data, '--dry-run', '--sql', sql)
    r = tool('rename_spells.py', data, '--dry-run', '--sql', sql)
    text = open(sql, encoding='utf-8').read() if os.path.exists(sql) else r.stdout + r.stderr
    check("DELETE FROM player_spells WHERE name = 'Arc Bolt';" in text and "name = 'Dread';" in text
          and "name = 'Gravetouch';" in text  # the unregistered c.xml names it: kept too (all_xml)
          and "'Purge Venom'" not in text.split('DELETE', 1)[-1], 'rename_spells --sql deletes learned rows: ' + text[-400:])

if fails:
    print('%d failure(s)' % len(fails))
    sys.exit(1)
print('monster_spells_test: OK')

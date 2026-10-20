#!/usr/bin/env python3
"""Test of retire_cure_spells.py: the seven stock cure instants and Hawkeye (stock Sharpshooter) are commented out (found by script, any name), the Chaos
block, Lightward and every other spell stay, a second run changes nothing, --dry-run writes nothing.
Run: python3 -I server/tools/retire_cure_spells_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import retire_cure_spells as R  # noqa: E402

fails = []


def check(c, what):
    if not c:
        fails.append(what)
        print('FAIL ' + what)


def spell(name, script, sid):
    return '\t<instant group="healing" spellid="%d" name="%s" words="x %d" level="10" script="%s">\n\t\t<vocation name="Warrior" />\n\t</instant>\n' % (sid, name, sid, script)


XML = '<spells>\n'
for script, (sid, name) in R.CURES.items():
    XML += spell('Renamed ' + name, script, sid)
XML += spell('Hawkeye', 'support/sharpshooter.lua', 135)
XML += spell('Light', 'support/light.lua', 10)
XML += '\t<instant group="healing" spellid="29" name="Short" words="y" script="healing/cure_poison.lua" />\n'
XML += '\t<!-- BEGIN chaos spells (x) -->\n' + spell('Lightward', 'chaos/paladin/divine_ward.lua', 217)
XML += spell('Chaos Cure', 'healing/cure_poison.lua', 250) + '\t<!-- END chaos spells -->\n</spells>\n'

new, n = R.patch(XML)
check(n == 9, 'seven cures, Hawkeye and the self-closing one: %d' % n)
check(new.count(R.MARK) == 8, 'each cure in a marked comment')
check(new.count(R.OTHER_MARK) == 1 and new.count('name="Hawkeye"') == 1
      and '<!-- ' + R.OTHER_MARK + '<instant group="healing" spellid="135" name="Hawkeye"' in new, 'Hawkeye retired')
check('<instant group="healing" spellid="10" name="Light"' in new, 'Light stays a tag')
check('name="Lightward"' in new and '<!-- Chaos: cure' not in new[new.index('BEGIN chaos'):], 'the Chaos block is untouched')
check(R.patch(new) == (new, 0), 'a second run changes nothing')
check(sorted(R.FREED_IDS) == [29, 58, 135, 144, 145, 146, 147, 164], 'the freed ids')

with tempfile.TemporaryDirectory() as tmp:
    p = os.path.join(tmp, 'spells')
    os.makedirs(p)
    open(os.path.join(p, 'spells.xml'), 'w', newline='').write(XML)
    tool = os.path.join(HERE, 'retire_cure_spells.py')
    r = subprocess.run([sys.executable, '-I', tool, tmp, '--dry-run'], capture_output=True, text=True)
    check(r.returncode == 0 and open(os.path.join(p, 'spells.xml')).read() == XML, 'dry run writes nothing')
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check('9 retired' in r.stdout and open(os.path.join(p, 'spells.xml')).read() == new, 'run: ' + r.stdout)
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check('nothing to retire' in r.stdout, 'second run: ' + r.stdout)
    check(subprocess.run([sys.executable, '-I', tool], capture_output=True).returncode == 1, 'no args: usage')

if fails:
    sys.exit(1)
print('retire_cure_spells_test: ok')

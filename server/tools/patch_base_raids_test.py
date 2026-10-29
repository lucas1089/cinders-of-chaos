#!/usr/bin/env python3
"""Test of patch_base_raids.py on a synthetic data folder: the three unknown names of the Thais orc raid get the Orc
Leader, a known name is kept, a missing new monster takes the line out, idempotent, --dry-run, bad args, and the
install_all.py step is wired.
Run: python3 -I server/tools/patch_base_raids_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_raids.py')
sys.path.insert(0, HERE)
import patch_base_raids as P  # noqa: E402

RAID = '''<?xml version="1.0" encoding="utf-8"?>
<raid>
	<announce delay="1000" type="Event" message="Orc activity reported! Beware!" />
	<singlespawn delay="120000" name="Orc Helmet" x="32368" y="32162" z="7" />
	<singlespawn delay="120000" name="Orc Shield" x="32344" y="32287" z="7" />
	<singlespawn delay="120000" name="Orc Armor" x="32271" y="32282" z="7" />
	<singlespawn delay="120000" name="Orc" x="1" y="2" z="7" />
	<areaspawn delay="60000" fromx="1" fromy="1" fromz="7" tox="2" toy="2" toz="7">
		<monster name="Orc Armor" amount="3" />
	</areaspawn>
</raid>
'''
MONSTERS = '<monsters>\n\t<monster name="Orc" file="monsters/orc.xml" />\n\t<monster name="Orc Leader" file="monsters/orc_leader.xml" />\n</monsters>\n'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(folder, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, folder] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


fixes = P.FIXES['raids/thais/orcs.xml']
known = {'orc', 'orc leader'}
new, done = P.patch(RAID, fixes, known)
check(len(done) == 3 and all(r == 'Orc Leader' for _, r in done), 'three spawns renamed: %r' % done)
check(new.count('name="Orc Leader"') == 3 and 'singlespawn delay="120000" name="Orc" ' in new, 'the Orc spawn is kept')
check('<monster name="Orc Armor" amount="3" />' in new, 'only single spawns are touched')
check(P.patch(new, fixes, known) == (new, []), 'idempotent')
check(P.patch(RAID, fixes, known | {'orc armor'})[1] == [('Orc Helmet', 'Orc Leader'), ('Orc Shield', 'Orc Leader')],
      'a name the server knows is kept')
gone, done = P.patch(RAID, fixes, {'orc'})
check(len(done) == 3 and all(r is None for _, r in done) and gone.count('<!-- <singlespawn') == 3
      and '--' not in gone.replace('<!--', '').replace('-->', '').replace('<?xml', '').replace('?>', ''), 'no new monster: lines out as comments')

with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'raids', 'thais'))
    os.makedirs(os.path.join(d, 'monster'))
    raid = os.path.join(d, 'raids', 'thais', 'orcs.xml')
    with open(raid, 'w', encoding='utf-8', newline='') as f:
        f.write(RAID)
    with open(os.path.join(d, 'monster', 'monsters.xml'), 'w', encoding='utf-8') as f:
        f.write(MONSTERS)
    code, text = run(d, '--dry-run')
    check(code == 0 and 'dry run' in text and open(raid, encoding='utf-8').read() == RAID, 'dry run reports, writes nothing')
    code, text = run(d)
    check(code == 0 and 'Orc Armor -> Orc Leader' in text, 'first run: ' + text)
    after = open(raid, encoding='utf-8').read()
    check(after == new, 'the file is the patched text')
    code, text = run(d)
    check(code == 0 and 'nothing to change' in text and open(raid, encoding='utf-8').read() == after, 'second run changes nothing')
    os.makedirs(os.path.join(d, 'monster', 'lua'))
    check(run(os.path.join(d, 'nope'))[0] == 1 and run(d, 'a', 'b')[0] == 1, 'bad args')
    os.remove(raid)
    check(run(d)[0] == 0 and 'skipped' in run(d)[1], 'a missing raid file is skipped')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    inst = f.read()
check('def step_baseraids(' in inst and 'patch_base_raids.py' in inst, 'install_all.py has the step')
check("'baseraids'" in inst and '  baseraids ' in inst, 'the step is in the docstring and the order')

print('patch_base_raids_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)

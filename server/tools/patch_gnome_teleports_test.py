#!/usr/bin/env python3
"""Tests of patch_gnome_teleports.py (the base scripts' text is synthetic, written from the structure of the real ones)."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_gnome_teleports as P  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


GCTS = '''local destination = {
	[4121] = {position = Position(1, 2, 9), storageValue = 1, needCrystal = true},
	[3128] = {position = Position(3, 4, 13), storageValue = 14},
	[3132] = {position = Position(5, 6, 9), storageValue = 15}, -- Gnomebase Alpha
	[3136] = {position = Position(7, 8, 13), storageValue = 16},
	[35669] = {position = Position(9, 9, 9), storageValue = 1}
}
function onStepIn(creature, item, position, fromPosition)
	if teleportCrystal.storageValue == 2 then return true end
end
'''
WZ = '''function onStepIn(creature, item, position, fromPosition)
	local destination = destinations[item.uid]
	if player:getStorageValue(destination.storage) ~= destination.value then
		player:teleportTo(fromPosition)
		return true
	end
	player:teleportTo(destination.teleportPosition)
end
'''
t, ch = P.patch_gcts(GCTS)
check(t.startswith(P.MARKER), 'marker on the first line')
check('storageValue = 14' not in t and 'storageValue = 15' not in t and 'storageValue = 16' not in t and
      'storageValue = 1}' not in t and 'storageValue = 1,' not in t, 'every storage value is -1')
check('storageValue = -1' in t and 'needCrystal = false' in t and 'needCrystal = true' not in t, 'values and crystal')
check('storageValue == 2' in t, 'the comparison of the old branch stays')
t2, ch2 = P.patch_gcts(t)
check(t2 == t and not ch2, 'second run changes nothing')

w, ch = P.patch_warzone(WZ)
check('if false then' in w and P.MARKER in w and ch, 'the warzone refusal is skipped')
w2, ch2 = P.patch_warzone(w)
check(w2 == w and not ch2, 'warzone: second run changes nothing')

with tempfile.TemporaryDirectory() as d:
    base = os.path.join(d, 'movements', 'scripts', 'quests', 'bigfoot burden')
    os.makedirs(base)
    with open(os.path.join(base, 'GCTS.lua'), 'w') as f:
        f.write(GCTS)
    with open(os.path.join(base, 'warzoneTeleports.lua'), 'w') as f:
        f.write(WZ)
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_gnome_teleports.py'), d, '--dry-run'],
                       stdout=subprocess.PIPE, universal_newlines=True)
    check('would change' in r.stdout and open(os.path.join(base, 'GCTS.lua')).read() == GCTS, 'dry run changes nothing')
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_gnome_teleports.py'), d],
                       stdout=subprocess.PIPE, universal_newlines=True)
    check(r.returncode == 0 and '2 file(s) changed' in r.stdout, 'run changes both files')
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_gnome_teleports.py'), d],
                       stdout=subprocess.PIPE, universal_newlines=True)
    check('nothing to change' in r.stdout, 'idempotent through the command line')
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_gnome_teleports.py'), os.path.join(d, 'nope')],
                       stdout=subprocess.PIPE, universal_newlines=True)
    check(r.returncode == 0 and 'not found' in r.stdout, 'missing files are skipped')
if fails:
    sys.exit(1)
print('patch_gnome_teleports_test: all checks passed')

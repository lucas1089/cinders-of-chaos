#!/usr/bin/env python3
"""Test of patch_loot_explosion.py (run: python3 -I server/tools/patch_loot_explosion_test.py) on a small data folder: the
ChaosLootExplosion.onMoveItem call goes first into Player:onMoveItem (LF and CRLF files, the rest of the file untouched), a
second run changes nothing, --dry-run writes nothing, a file without the function and a missing file are refused, the hook
sits before the hooks of the other steps (they insert at the same place), and the call matches the function the Lua glue
defines (loot_explosion.lua)."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_loot_explosion as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))

PLAYER = '''function Player:onLook(thing, position, distance)
	return true
end

function Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if hasEventCallback(EVENT_CALLBACK_ONMOVEITEM) then
		return EventCallback.onMoveItem(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	end
	return RETURNVALUE_NOERROR
end

function Player:onItemMoved(item, count, fromPosition, toPosition, fromCylinder, toCylinder)
end
'''

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def run(data, *flags):
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_loot_explosion.py'), data] + list(flags),
                       capture_output=True, text=True)
    return p.returncode, p.stdout


def write(data, text):
    d = os.path.join(data, 'events', 'scripts')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'player.lua'), 'w', newline='') as f:
        f.write(text)


def read(data):
    with open(os.path.join(data, 'events', 'scripts', 'player.lua'), newline='') as f:
        return f.read()


# the pure function
new, st = P.patch_player(PLAYER)
check(st == 'patched', 'patched: %s' % st)
check(P.MARKER in new, 'marker written')
check(new.count('ChaosLootExplosion.onMoveItem(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)') == 1,
      'one call')
head = new.index('function Player:onMoveItem')
check(new.index(P.MARKER) > head and new.index(P.MARKER) < new.index('hasEventCallback'), 'the hook is the first thing of the function')
check(new.replace(P.HOOK, '') == PLAYER, 'nothing else changed')
again, st = P.patch_player(new)
check(st == 'already' and again == new, 'a second run changes nothing')
bad, st = P.patch_player('function Player:onLook() end\n')
check(st.endswith('not found'), 'no function: refused')

# another step's hook already sits there: ours goes in front of the base code, theirs stay
other = PLAYER.replace('toCylinder)\n\tif hasEvent', 'toCylinder)\n\t-- Chaos: season isolation (patch_season_events.py)\n\tif ChaosSeason then end\n\tif hasEvent', 1)
mixed, st = P.patch_player(other)
check(st == 'patched' and '-- Chaos: season isolation' in mixed and P.MARKER in mixed, 'other hooks stay')

with tempfile.TemporaryDirectory() as d:
    # LF
    write(d, PLAYER)
    code, out = run(d, '--dry-run')
    check(code == 0 and 'dry run' in out and read(d) == PLAYER, 'dry run writes nothing: %s' % out)
    code, out = run(d)
    check(code == 0 and 'patched' in out and P.MARKER in read(d), 'patched on disk: %s' % out)
    first = read(d)
    code, out = run(d)
    check(code == 0 and 'already' in out and read(d) == first, 'idempotent on disk')
    # CRLF
    write(d, PLAYER.replace('\n', '\r\n'))
    code, out = run(d)
    text = read(d)
    check(code == 0 and P.MARKER in text and '\n' not in text.replace('\r\n', ''), 'CRLF kept')
    # refusals
    write(d, 'return true\n')
    code, out = run(d)
    check(code == 1 and 'not found' in out, 'no function: exit 1')
    os.remove(os.path.join(d, 'events', 'scripts', 'player.lua'))
    code, out = run(d)
    check(code == 1, 'no file: exit 1')
    code, out = run(d, '--dry-run', 'extra')
    check(code == 2 or code == 1, 'extra argument refused')

# the call matches the glue
with open(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'loot_explosion.lua')) as f:
    glue = f.read()
check('function X.onMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)' in glue,
      'loot_explosion.lua defines onMoveItem with the same arguments')

# the install step is wired
with open(os.path.join(HERE, 'install_all.py')) as f:
    inst = f.read()
check("def step_lootexplosion(" in inst and "'lootexplosion')" in inst, 'install_all.py has the step')

if failures:
    for m in failures:
        print('FAIL:', m)
    sys.exit(1)
print('patch_loot_explosion_test: ok')

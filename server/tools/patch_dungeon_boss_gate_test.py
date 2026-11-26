#!/usr/bin/env python3
"""Test of patch_dungeon_boss_gate.py on a copy of the stock master_of_the_elements.lua: the line goes first in
onStepIn with the handler's own argument names, nothing else changes, idempotent, CRLF, an unknown shape is left alone,
--dry-run, --check, a missing file; and the install_all.py step is wired (O183 seen in a client).
Run: python3 -I server/tools/patch_dungeon_boss_gate_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_dungeon_boss_gate.py')
sys.path.insert(0, HERE)
import patch_dungeon_boss_gate as P  # noqa: E402

STOCK = '''local masterOfTheElements = MoveEvent()

local bossName = "Master of the Elements"
local bossInterval = 3
local function createBoss()

    addEvent(function()
        Game.createMonster(bossName, {x = 31716, y = 32563, z = 8})
    end, bossInterval * 1000)
end

function masterOfTheElements.onStepIn(player, item, position, fromPosition)
    if player:getStorageValue(248500) < 0 then
    createBoss()
    player:setStorageValue(248500, os.time() + 1500)
    else
        return true
    end
end

masterOfTheElements:aid(63457)
masterOfTheElements:type("StepIn")
masterOfTheElements:register()
'''

LINE = ('    if ChaosDungeons and ChaosDungeons.bossStep and ChaosDungeons.bossStep(player, position) then return true end '
        + P.MARK)
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(folder, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, folder] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


new, note = P.patch(STOCK)
check(note.startswith('patched'), 'patched: ' + note)
check('fromPosition)\n' + LINE + '\n    if player:getStorageValue(248500) < 0 then' in new, 'the line first in onStepIn')
check(new.replace(LINE + '\n', '') == STOCK, 'nothing else changed')
check(P.patch(new) == (new, 'already patched'), 'idempotent')
crlf = STOCK.replace('\n', '\r\n')
out = P.patch(crlf)[0]
check(LINE + '\r\n' in out and out.count('\r\n') == crlf.count('\r\n') + 1 and out.count('\n') == out.count('\r\n'),
      'CRLF kept')
other = STOCK.replace('onStepIn(player, item, position, fromPosition)', 'onStepIn(creature, item, pos, fromPos)')
check('ChaosDungeons.bossStep(creature, pos)' in P.patch(other)[0], 'the handler\'s own argument names')
two = STOCK + STOCK.replace('masterOfTheElements', 'other')
check(P.patch(two)[0] == two and 'unrecognised' in P.patch(two)[1], 'two handlers: left alone')
check(P.patch('return true\n')[0] == 'return true\n', 'no handler: left alone')

with tempfile.TemporaryDirectory() as d:
    rc, out = run(d)
    check(rc == 0 and 'not found, skipped' in out, 'a missing script is skipped: ' + out)
    path = os.path.join(d, P.SCRIPT)
    os.makedirs(os.path.dirname(path))
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(STOCK)
    rc, out = run(d, '--check')
    check(rc == 1 and 'still to patch' in out, '--check exits 1 before: ' + out)
    rc, out = run(d, '--dry-run')
    check(rc == 0 and open(path, encoding='utf-8', newline='').read() == STOCK, '--dry-run writes nothing')
    rc, out = run(d)
    check(rc == 0 and LINE in open(path, encoding='utf-8', newline='').read(), 'written')
    rc, out = run(d, '--check')
    check(rc == 0 and 'nothing to do' in out, '--check after: ' + out)
    rc, out = run(d, 'x', 'y')
    check(rc == 2, 'bad args')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    ia = f.read()
check("def step_dungeonbossgate(" in ia and "'patch_dungeon_boss_gate.py'" in ia, 'install_all step defined')
check("STEPS.insert(STEPS.index('dungeonentry') + 1, 'dungeonbossgate')" in ia, 'install_all step wired')
check('  dungeonbossgate ' in ia, 'install_all docstring names the step')

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('patch_dungeon_boss_gate_test: all passed')

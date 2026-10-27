#!/usr/bin/env python3
"""Tests of patch_astro_door.py (the base script's text is the real one, shortened)."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_astro_door as P  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


DOOR = '''local astroClock = Action()

function astroClock.onUse(player, item, fromPosition, target, toPosition, isHotkey)

    if player:getStorageValue(Quests.astroClock) == -1 or player:getStorageValue(Quests.astroClock) == 0 then
        player:sendTextMessage(MESSAGE_INFO_DESCR, "You need find the Astro Clock.")
    else
        player:teleportTo(Position(31568, 33003, 7), true)
    end
    return true
end

astroClock:aid(13690)
astroClock:register()'''
CLOCK = DOOR.replace('13690', '13689').replace('You need find the Astro Clock.', 'You have found the clock.')

t, st = P.patch(DOOR)
check(st == 'patched', 'door patched: ' + st)
check(t.count(P.MARK) == 1, 'one marker')
first = t.split('\n')[3]
check('if true then' in first and P.MARK in first, 'block is the first line of onUse')
check('player:teleportTo(dest, true)' in t and 'item:getPosition()' in t, 'uses the signature names')
check('You need find the Astro Clock' in t, 'the old body stays')
check(t.index('return true') < t.index('Quests.astroClock'), 'the block returns before the storage check')
t2, st2 = P.patch(t)
check(st2 == 'already patched' and t2 == t, 'second run changes nothing')
check(P.patch(CLOCK)[1] == 'none', 'the clock script is not the door')
check(P.patch('local x = 1')[1] == 'none', 'other script is not the door')
crlf, st3 = P.patch(DOOR.replace('\n', '\r\n'))
check(st3 == 'patched' and '\r\n' in crlf and '\n' not in crlf.replace('\r\n', ''), 'CRLF kept')
check(P.patch(DOOR.replace('onUse(player, item, fromPosition, target, toPosition, isHotkey)', 'onUse(player)'))[1].startswith('unrecognised'), 'odd signature refused')
check(P.patch(DOOR + '\nfunction astroClock.onUse(a, b)\nend\n')[1].startswith('unrecognised'), 'two onUse refused')

with tempfile.TemporaryDirectory() as d:
    p = os.path.join(d, P.REL)
    os.makedirs(os.path.dirname(p))
    open(p, 'w').write(DOOR)
    run = lambda *a: subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_astro_door.py'), d] + list(a),
                                    capture_output=True, text=True)
    r = run('--dry-run')
    check(r.returncode == 0 and 'patched' in r.stdout and open(p).read() == DOOR, 'dry run writes nothing')
    r = run()
    check(r.returncode == 0 and P.MARK in open(p).read(), 'run patches')
    after = open(p).read()
    r = run()
    check(r.returncode == 0 and 'nothing to change' in r.stdout and open(p).read() == after, 'run twice: unchanged')
    # moved script: found by the message
    q = os.path.join(d, 'scripts', 'other')
    os.makedirs(q)
    os.remove(p)
    open(os.path.join(q, 'door2.lua'), 'w').write(DOOR)
    r = run()
    check('door2.lua: patched' in r.stdout, 'found by message when moved')

print('patch_astro_door_test: %s' % ('FAIL' if fails else 'ok'))
sys.exit(1 if fails else 0)

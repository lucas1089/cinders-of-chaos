#!/usr/bin/env python3
"""Tests of the change report of tools/install_all.py (snapshot / diff): the map counts as a changed file.

Playtest 2026-10-16: the summary said "towns - 0 file(s) changed" although the towns step renamed the map's towns,
because the map was never compared. Now the map (.otbm) is compared by size and modification time (its tools write
it only when it changes); its .bak / .tmp copies, logs and reports stay out of the report.

Run: python3 -I server/tools/install_all_snapshot_test.py (standard library only)."""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import install_all as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)  # as patch_base_towns.py writes the map


root = tempfile.mkdtemp(prefix='install_snapshot_test_')
try:
    world = os.path.join(root, 'data', 'world')
    mp = os.path.join(world, 'map.otbm')
    write(os.path.join(root, 'config.lua'), b'mapName = "map"\n')
    write(mp, b'OTBM\x00towns: Oldtown')
    write(os.path.join(root, 'data', 'lib', 'x.lua'), b'-- x\n')
    write(os.path.join(root, 'data', 'logs', 'a.log'), b'log\n')

    snap = I.snapshot(root)
    check('data/world/map.otbm' in snap, 'the map is in the snapshot: %s' % sorted(snap))
    check(not any('logs/' in k for k in snap), 'no logs')

    # the towns step renames a town: the map is written again (and its backup made)
    os.utime(mp, ns=(1, 1))
    snap = I.snapshot(root)
    write(mp + '.bak', b'OTBM\x00towns: Oldtown')
    write(mp, b'OTBM\x00towns: Ashtown')  # same size, new content
    after = I.snapshot(root)
    added, changed, removed = I.diff(snap, after)
    check(changed == ['data/world/map.otbm'], 'the renamed map is a changed file: %s' % changed)
    check(added == [] and removed == [], 'the backup is not reported: %s %s' % (added, removed))
    check(len(added) + len(changed) + len(removed) == 1, '"towns - 1 file(s) changed"')

    # run again: nothing written, nothing reported
    again = I.snapshot(root)
    check(I.diff(after, again) == ([], [], []), 'an unchanged map is not reported')
    check(I.SKIP_HASH.search('data/world/map.otbm') is None and I.SKIP_HASH.search('data/world/map.otbm.bak'),
          'SKIP_HASH skips the backup, not the map')
finally:
    shutil.rmtree(root, ignore_errors=True)

# the pair 30 item step sits right after the equipment sets and has its step function
check(I.STEPS.index('pack30items') == I.STEPS.index('gearsets') + 1, 'step pack30items follows gearsets')
check(callable(getattr(I, 'step_pack30items', None)), 'step_pack30items exists')
check(len(I.STEPS) == len(set(I.STEPS)), 'no step twice')

print('install_all_snapshot_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)

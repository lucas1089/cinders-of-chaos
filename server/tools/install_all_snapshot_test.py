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
check(I.STEPS.index('rewardchests') + 1 == I.STEPS.index('contentareas'), 'step rewardchests right before contentareas')
check(callable(getattr(I, 'step_rewardchests', None)), 'step_rewardchests exists')
check(len(I.STEPS) == len(set(I.STEPS)), 'no step twice')
check(I.STEPS.index('huntannexes') == I.STEPS.index('huntgates') + 1, 'step huntannexes follows huntgates (after contentareas, before poi)')
check(callable(getattr(I, 'step_huntannexes', None)), 'step_huntannexes exists')

# the restore marker (O337): <map>.otbm.restore puts <map>.otbm.bak back before the first step, once
root = tempfile.mkdtemp(prefix='install_restore_test_')
try:
    mp = os.path.join(root, 'data', 'world', 'map.otbm')
    write(os.path.join(root, 'config.lua'), b'mapName = "map"\n')
    write(mp, b'installed map')
    write(mp + '.bak', b'base map')
    data = os.path.join(root, 'data')
    log = []
    check(I.restore_map(data, False, log.append) is None and open(mp, 'rb').read() == b'installed map', 'no marker: the map stays')
    write(mp + I.RESTORE_SUFFIX, b'')
    log = []
    check(I.restore_map(data, True, log.append) is None and open(mp, 'rb').read() == b'installed map', 'a dry run restores nothing')
    check(any('would be restored' in l for l in log), 'a dry run says so: %s' % log)
    log = []
    marker = I.restore_map(data, False, log.append)
    check(marker == mp + I.RESTORE_SUFFIX and open(mp, 'rb').read() == b'base map', 'the marker puts the backup back: %s' % log)
    check(open(mp + '.bak', 'rb').read() == b'base map' and not os.path.exists(mp + '.restore.tmp'), 'the backup stays, no temporary file')
    os.remove(mp + '.bak')
    write(mp, b'installed map')
    log = []
    check(I.restore_map(data, False, log.append) is None and open(mp, 'rb').read() == b'installed map', 'a marker without a backup leaves the map')
    check(any('no ' in l for l in log), 'and says so: %s' % log)
finally:
    shutil.rmtree(root, ignore_errors=True)

print('install_all_snapshot_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)

#!/usr/bin/env python3
"""Tests for server/deploy/chaos_stage_sync.py (the staging copy of chaos_kit_update.sh).

A live folder, its manifest, a copy the "install" changes, then what the "game" changed in the live folder: a file
the install did not touch comes over (new, changed, removed), a rewrite with the same content is no change, a file both
sides changed is a conflict (nothing written, exit 3), the same content on both sides is none, --ignore, links, the logs
and reports folders and temporary map files are not looked at.

usage: python3 -I server/deploy/chaos_stage_sync_test.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'chaos_stage_sync.py')
FAILS = []


def check(cond, what, out=''):
    if not cond:
        FAILS.append(what)
        print('FAIL: ' + what)
        if out:
            print(out[-2000:])


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def read(path):
    with open(path) as f:
        return f.read()


def run(*args):
    r = subprocess.run([sys.executable, '-I', TOOL] + list(args), capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def copy_tree(src, dst):
    subprocess.run(['cp', '-a', src, dst], check=True)


def main():
    tmp = tempfile.mkdtemp(prefix='chaos_stage_sync_test_')
    try:
        live, stage, man = (os.path.join(tmp, n) for n in ('live', 'stage', 'manifest.json'))
        write(live + '/config.lua', 'a = 1\n')
        write(live + '/tfs', 'engine\n')
        for name in ('same', 'game_changes', 'game_removes', 'both', 'both_same', 'rewrite', 'install_only'):
            write(live + '/data/' + name + '.txt', name + ' v0\n')
        write(live + '/data/world/map.otbm', 'map\n')
        write(live + '/data/logs/server.log', 'log\n')
        write(live + '/data/reports/r.txt', 'report\n')
        write(live + '/data/world/map.otbm.tmp', 'half\n')
        os.symlink('tfs', live + '/tfs.link')
        old = time.time() - 100
        for base, _d, files in os.walk(live):
            for f in files:
                if not os.path.islink(os.path.join(base, f)):
                    os.utime(os.path.join(base, f), (old, old))
        rc, out = run('manifest', live, man)
        check(rc == 0 and 'manifest: 11 file(s)' in out, 'manifest counts', out)
        import json
        m = json.load(open(man))
        check(not any(k.startswith(('data/logs', 'data/reports')) or k.endswith('.tmp') for k in m),
              'manifest: no logs, reports, temporary map files', sorted(m))
        check(m['tfs.link'] == ['L', 'tfs'] and m['data/world/map.otbm'][2] == '' and len(m['tfs'][2]) == 40,
              'manifest: links by target, maps without a hash, files with one', m)

        copy_tree(live, stage)
        # the install writes in the copy
        write(stage + '/data/both.txt', 'both install\n')
        write(stage + '/data/both_same.txt', 'same new\n')
        write(stage + '/data/install_only.txt', 'install v1\n')
        write(stage + '/data/new_from_install.txt', 'x\n')
        write(stage + '/config.lua', 'a = 2\n')
        # the game writes in the live folder
        time.sleep(0.01)
        write(live + '/data/game_changes.txt', 'game v1\n')
        os.remove(live + '/data/game_removes.txt')
        write(live + '/data/both.txt', 'both game\n')
        write(live + '/data/both_same.txt', 'same new\n')
        write(live + '/data/rewrite.txt', 'rewrite v0\n')  # same content, new time
        write(live + '/data/new_from_game.txt', 'new\n')
        write(live + '/data/logs/server.log', 'more log\n')
        write(live + '/config.lua', 'a = 3\n')
        os.remove(live + '/tfs.link')
        os.symlink('tfs2', live + '/tfs.link')

        rc, out = run('sync', live, stage, man, '--ignore', 'config.lua', '--dry-run')
        check(rc == 3 and 'conflict data/both.txt' in out and 'conflict data/both_same.txt' not in out
              and 'conflict data/install_only.txt' not in out, 'sync: the file both changed is the only conflict', out)
        check(read(stage + '/data/game_changes.txt') == 'game_changes v0\n', 'sync: a conflict writes nothing')

        os.remove(live + '/data/both.txt')  # the game removes it: a removed file the install changed is a conflict too
        rc, out = run('sync', live, stage, man, '--ignore', 'config.lua')
        check(rc == 3 and 'conflict data/both.txt' in out, 'sync: removed by the game, changed by the install: conflict', out)
        write(live + '/data/both.txt', 'both install\n')  # the same content on both sides
        rc, out = run('sync', live, stage, man, '--ignore', 'config.lua')
        check(rc == 0 and 'ignored config.lua' in out, 'sync: ok once the content is the same', out)
        check(read(stage + '/data/game_changes.txt') == 'game v1\n', 'sync: a changed file comes over')
        check(not os.path.exists(stage + '/data/game_removes.txt'), 'sync: a removed file goes')
        check(read(stage + '/data/new_from_game.txt') == 'new\n', 'sync: a new file comes over')
        check(read(stage + '/data/install_only.txt') == 'install v1\n' and read(stage + '/data/new_from_install.txt') == 'x\n',
              'sync: the install\'s own files stay')
        check('rewrite' not in out and 'logs' not in out, 'sync: a rewrite with the same content and the logs are no change', out)
        check(read(stage + '/config.lua') == 'a = 2\n', 'sync: an ignored file is left to the caller')
        check(os.path.islink(stage + '/tfs.link') and os.readlink(stage + '/tfs.link') == 'tfs2', 'sync: a changed link comes over')
        check('synced 4 file(s)' in out, 'sync: the count', out)
        rc, out = run('sync', live, stage, man, '--ignore', 'config.lua')
        check(rc == 0 and 'synced 0 file(s)' in out, 'sync: a second run is harmless', out)
        check(run('sync', live)[0] != 0 and run('bogus')[0] != 0, 'usage errors')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('chaos_stage_sync_test: %d failures' % len(FAILS))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())

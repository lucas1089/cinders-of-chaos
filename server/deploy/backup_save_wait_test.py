#!/usr/bin/env python3
"""Test of the save wait of server/tools/backup.sh (--save-pid with --save-log): the wait ends when the engine prints
"> Saved in steps:" after the signal (not after the fixed --save-wait), a line from before the signal does not count,
without the line the wait is the whole --save-wait, and without --save-log it is the fixed wait as before.

usage: python3 -I server/deploy/backup_save_wait_test.py"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BACKUP = os.path.join(os.path.dirname(HERE), 'tools', 'backup.sh')
FAILS = []


def check(cond, what, out=''):
    if not cond:
        FAILS.append(what)
        print('FAIL: ' + what)
        if out:
            print(out[-1500:])


# a stand-in engine: on SIGUSR1 it prints the save line after DELAY seconds (DELAY < 0: never)
ENGINE = r'''#!/usr/bin/env bash
log=$1; delay=$2
trap 'if [ "$delay" != never ]; then ( sleep "$delay"; echo "> Saved in steps: 3 players (0 logged out before, 0 failed)" >> "$log" ) & fi' USR1
echo ready > "$log.ready"
while :; do sleep 0.1; done
'''
DUMP = '#!/usr/bin/env bash\necho "-- Dump completed on now"\n'


def run(tmp, delay, wait, with_log=True, stale_line=False):
    log = os.path.join(tmp, 'server.log')
    open(log, 'w').write('> Saved in steps: 1 players (an old save)\n' if stale_line else 'booted\n')
    for f in (log + '.ready',):
        if os.path.exists(f):
            os.remove(f)
    eng_path = os.path.join(tmp, 'engine.sh')
    eng = subprocess.Popen(['bash', eng_path, log, delay], start_new_session=True)
    try:
        for _ in range(100):
            if os.path.exists(log + '.ready'):
                break
            time.sleep(0.05)
        env = dict(os.environ, PATH=os.path.join(tmp, 'bin') + os.pathsep + os.environ['PATH'], CHAOS_DB_NAME='chaos',
                   CHAOS_BACKUP_DIR=os.path.join(tmp, 'bk'))
        cmd = ['bash', BACKUP, '--save-pid', str(eng.pid), '--save-wait', str(wait), '--no-data']
        if with_log:
            cmd += ['--save-log', log]
        t0 = time.time()
        r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=60)
        return r.returncode, time.time() - t0, r.stdout + r.stderr
    finally:
        eng.send_signal(signal.SIGTERM)
        eng.wait()


def main():
    tmp = tempfile.mkdtemp(prefix='backup_save_wait_test_')
    try:
        os.makedirs(os.path.join(tmp, 'bin'))
        for name in ('mysqldump', 'mariadb-dump'):
            p = os.path.join(tmp, 'bin', name)
            open(p, 'w').write(DUMP)
            os.chmod(p, 0o755)
        open(os.path.join(tmp, 'engine.sh'), 'w').write(ENGINE)
        rc, took, out = run(tmp, '1', 20)
        check(rc == 0 and took < 8 and 'finished the save' in out, 'the wait ends with the engine\'s line (%.1f s)' % took, out)
        rc, took, out = run(tmp, '1', 20, stale_line=True)
        check(rc == 0 and took < 8 and 'finished the save' in out, 'an old save line does not end the wait early or late (%.1f s)' % took, out)
        rc, took, out = run(tmp, 'never', 3, stale_line=True)
        check(rc == 0 and 3 <= took < 10 and 'no \'Saved in steps\' line' in out, 'no line: the whole --save-wait, an old line does not count (%.1f s)' % took, out)
        rc, took, out = run(tmp, '0', 3, with_log=False)
        check(rc == 0 and took >= 3, 'without --save-log: the fixed wait (%.1f s)' % took, out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('backup_save_wait_test: %d failures' % len(FAILS))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())

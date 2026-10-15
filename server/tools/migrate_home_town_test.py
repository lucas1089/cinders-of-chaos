#!/usr/bin/env python3
"""Tests of migrate_home_town.py: the SQL, the defaults from newplayer_config.lua, the refusals.

usage: python3 -I server/tools/migrate_home_town_test.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's folder off sys.path

import migrate_home_town as M  # noqa: E402

checks = fails = 0


def check(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL ' + what)


# the configured main city is Cinderhold (town 2)
check(M.configured_home() == 2, 'homeTown.id of newplayer_config.lua is 2')
check(M.configured_home('/nonexistent/newplayer_config.lua') is None, 'no config: None')

sql = M.build_sql(2)
check('UPDATE `players` SET `town_id` = 2 WHERE `town_id` <> 2;' in sql, 'every other town by default')
check(sql.index('START TRANSACTION;') < sql.index('UPDATE') < sql.index('COMMIT;'), 'one transaction')
check('SELECT `town_id`, COUNT(*)' in sql, 'the counts before the update')

sql = M.build_sql(2, [1, 2, 4], 50)
check('WHERE `town_id` <> 2 AND `town_id` IN (1, 4) AND `level` <= 50;' in sql, 'from list without the target, level cap')


def refused(fn):
    try:
        fn()
    except M.UsageError:
        return True
    return False


check(refused(lambda: M.build_sql(0)), 'no target refused')
check(refused(lambda: M.build_sql(None)), 'no target (None) refused')
check(refused(lambda: M.build_sql(2, [2])), 'only the target in --from refused')
check(refused(lambda: M.build_sql(2, None, 0)), 'level 0 refused')
check(refused(lambda: M.ids('1,x')), 'bad id refused')
check(M.ids('1, 4,1') == [1, 4], 'ids parsed, duplicates dropped')

# the command line: standard output, --out, a usage error exits 2
tool = os.path.join(HERE, 'migrate_home_town.py')
r = subprocess.run([sys.executable, '-I', tool, '--from', '1'], capture_output=True, text=True)
check(r.returncode == 0 and '`town_id` IN (1)' in r.stdout and '= 2 WHERE' in r.stdout, 'cli: stdout')
with tempfile.TemporaryDirectory() as d:
    out = os.path.join(d, 'home.sql')
    r = subprocess.run([sys.executable, '-I', tool, '--to', '3', '--out', out], capture_output=True, text=True)
    check(r.returncode == 0 and r.stdout == '' and 'SET `town_id` = 3' in open(out, encoding='utf-8').read(), 'cli: --out')
r = subprocess.run([sys.executable, '-I', tool, '--bogus', '1'], capture_output=True, text=True)
check(r.returncode == 2 and 'unknown' in r.stderr, 'cli: unknown option exits 2')

print('migrate_home_town_test: %d checks, %d failures' % (checks, fails))
sys.exit(1 if fails else 0)

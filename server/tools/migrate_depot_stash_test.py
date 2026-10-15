#!/usr/bin/env python3
"""Tests of migrate_depot_stash.py (CI: python3 -I server/tools/migrate_depot_stash_test.py).

The SQL of one run (the tables, one transaction, the depot tab boxes kept, the attributes copied as lower case hex),
the refusal without --server-stopped, --dry-run, --sql, and a full run against a stub mysql client that records what
it gets."""
import importlib.util
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('migrate_depot_stash', os.path.join(HERE, 'migrate_depot_stash.py'))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)

checks = 0


def ok(cond, label):
    global checks
    checks += 1
    if not cond:
        raise SystemExit('FAIL ' + label)


boxes = M.box_ids()
ok(len(boxes) == 17 and boxes[0] == 25453 and boxes[-1] == 25469, 'the 17 depot tab boxes of depot_config.lua')
ok(M.box_ids('boxIds = {1, 2,\n 3}') == [1, 2, 3], 'box ids over lines')
try:
    M.box_ids('nothing here')
    ok(False, 'no boxIds raises')
except ValueError:
    ok(True, 'no boxIds raises')

schema, tx = M.migration_sql(boxes)
ok('CREATE TABLE IF NOT EXISTS `chaos_stash_items`' in schema, 'the tables first')
ok(tx.startswith('START TRANSACTION;') and tx.rstrip().endswith('COMMIT;'), 'one transaction')
keep = '`itemtype` NOT IN (%s)' % ', '.join(str(b) for b in boxes)
ok(tx.count(keep) == 3, 'log, copy and delete all keep the boxes')
order = [tx.index('INSERT INTO `chaos_stash_log`'), tx.index('INSERT INTO `chaos_stash_items`'),
         tx.index('DELETE FROM `player_depotitems`')]
ok(order == sorted(order), 'log, copy, then delete')
ok("LOWER(HEX(`attributes`))" in tx and "'blob'" in tx and "'depot'" in tx, 'the engine attributes as hex, codec blob, source depot')
ok('GREATEST(`count`, 1)' in tx, 'a count of at least 1')
ok('player_inboxitems' not in tx and 'market' not in tx, 'the inbox and the market are not touched')

args = M.parse_args(['/srv', '--dry-run', '--db', 'x'])
ok(args['server'] == '/srv' and args['--dry-run'] and args['--db'] == 'x', 'arguments')
for bad in (['/srv', '--nope'], ['/a', '/b'], ['/srv', '--db']):
    try:
        M.parse_args(bad)
        ok(False, 'bad arguments refused: %s' % bad)
    except SystemExit:
        ok(True, 'bad arguments refused')

ok(M.config_value('mysqlDatabase = "chaos" -- db', 'mysqlDatabase') == 'chaos', 'config.lua value')
os.environ['CHAOS_TEST_DB'] = 'fromenv'
ok(M.config_value('mysqlDatabase = os.getenv("CHAOS_TEST_DB") or "x"', 'mysqlDatabase') == 'fromenv', 'config.lua env value')

with tempfile.TemporaryDirectory() as d:
    out = os.path.join(d, 'm.sql')
    ok(M.main(['/nowhere', '--sql', out]) == 0, '--sql writes a file')
    text = open(out).read()
    ok('START TRANSACTION;' in text and 'chaos_stash_items' in text, '--sql: the statements')

    # a stub mysql client: records each stdin, answers the count query
    log = os.path.join(d, 'calls.log')
    stub = os.path.join(d, 'mysql')
    with open(stub, 'w') as f:
        f.write('#!/bin/sh\n')
        f.write('input=$(cat)\n')
        f.write('printf "%%s\\n----\\n" "$input" >> "%s"\n' % log)
        f.write('case "$input" in *COUNT\\(DISTINCT*) printf "3\\t42\\n";; esac\n')
        f.write('for a in "$@"; do case "$a" in --defaults-extra-file=*) grep -q "password" "${a#*=}" && echo PWFILE >> "%s";; esac; done\n' % log)
        f.write('exit 0\n')
    os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC)
    server = os.path.join(d, 'server')
    os.makedirs(server)
    with open(os.path.join(server, 'config.lua'), 'w') as f:
        f.write('mysqlDatabase = "chaos"\nmysqlUser = "u"\nmysqlPass = "secret"\n')
    env = dict(os.environ)
    env.pop('CHAOS_DB_PASS', None)
    env.pop('MYSQL_PWD', None)

    def run(*extra):
        if os.path.exists(log):
            os.unlink(log)
        p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'migrate_depot_stash.py'), server, '--mysql', stub] + list(extra),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        calls = open(log).read() if os.path.exists(log) else ''
        return p.returncode, p.stdout.decode(), calls

    code, text, calls = run()
    ok(code == 0 and '3, 42' in text, 'counts shown: %s' % text)
    ok('stop the game server first' in text, 'refused without --server-stopped')
    ok('START TRANSACTION' not in calls, 'nothing changed without --server-stopped')
    ok('secret' not in text and 'PWFILE' in calls, 'the password goes through the option file only')
    code, text, calls = run('--server-stopped', '--dry-run')
    ok(code == 0 and 'START TRANSACTION' not in calls, '--dry-run changes nothing')
    code, text, calls = run('--server-stopped')
    ok(code == 0 and calls.count('----') == 3, 'a full run: count, tables, transaction (%s)' % text)
    ok('DELETE FROM `player_depotitems`' in calls, 'the transaction ran')

print('migrate_depot_stash_test: %d checks OK' % checks)

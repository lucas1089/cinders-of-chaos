#!/usr/bin/env python3
"""Tests for server/tools/journey_setup.py (server/README.md "Journey bots (O542)"): the class wheel, the statements of fresh level 1
tester characters (tester name, marker storage, group 1, account type 1, level 1, no hunt spot storage), the refusal of an unsafe name,
the env lines and the list lines (no password in the list), the usage errors. No database: the SQL is only built.

usage: python3 -I server/tools/journey_setup_test.py
"""
import contextlib
import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import journey_setup as js  # noqa: E402
import testers as T  # noqa: E402
import tester_core as TC  # noqa: E402

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


def main():
    check(js.plan(5, [('Warrior', 1), ('Ranger', 1), ('Mystic', 1)]) == ['Warrior', 'Ranger', 'Mystic', 'Warrior', 'Ranger'], 'classes in turn')
    bots = [{'account': 'tstbotabcdef1234', 'password': 'pw_Abc-123', 'name': 'Tester Aaa', 'class': 'Warrior', 'vocation': 4, 'town': 2},
            {'account': 'tstbot0123456789', 'password': 'pw2', 'name': 'Tester Aab', 'class': 'Mystic', 'vocation': 1}]
    st = js.new_bot_statements(bots, lambda b: 'HASH-' + b['account'])
    check(len(st) == 6, 'three statements per bot')
    check(st[0].startswith("INSERT INTO `accounts`") and "'HASH-tstbotabcdef1234', '', 1)" in st[0], 'account of type 1 with the hash')
    check("SELECT 'Tester Aaa', `id`, 1, 4, 1, 0, 150, 150, 0, 0, 400, 100" in st[1] and 'UNIX_TIMESTAMP' not in st[1] and st[1].endswith("WHERE `name` = 'tstbotabcdef1234';"), 'fresh level 1 character: group 1, vocation, 150 health, 400 capacity, last login 0')
    check(", 3, 2, 0, 0, 0, 0 FROM" in st[1] and ", 3, 2, 0, 0, 0, 0 FROM" in js.new_bot_statements(bots[1:], lambda b: 'x')[1], 'town 2, position 0,0,0 (the temple), last login 0')
    check(st[2] == "INSERT INTO `player_storage` (`player_id`, `key`, `value`) SELECT `id`, %d, 1 FROM `players` WHERE `name` = 'Tester Aaa';" % TC.TESTER_STORAGE, 'the tester marker storage only')
    check(not any(str(TC.TESTER_STORAGE + off) in s for s in st for off in (2, 3, 4)), 'no hunt spot storage (the bot walks)')
    try:
        js.new_bot_statements([dict(bots[0], name="Tester A'; DROP")], lambda b: 'x')
        check(False, 'an unsafe name is refused')
    except AssertionError:
        check(True, 'an unsafe name is refused')
    try:
        js.new_bot_statements([dict(bots[0], account="x'; DROP")], lambda b: 'x')
        check(False, 'an unsafe account is refused')
    except AssertionError:
        check(True, 'an unsafe account is refused')

    env = js.env_lines(bots[0])
    check(env == ['export CHAOS_LIVE_ACCOUNT=tstbotabcdef1234', 'export CHAOS_LIVE_PASSWORD=pw_Abc-123', "export JOURNEY_CHARACTER='Tester Aaa'", "export JOURNEY_CLASS='Warrior'"], 'env lines')
    try:
        js.env_lines(dict(bots[0], password='a b; rm'))
        check(False, 'an unsafe password is not exported')
    except AssertionError:
        check(True, 'an unsafe password is not exported')
    lst = js.list_lines({'bots': bots})
    check(lst == ['bots=2', 'bot0=Tester Aaa;Warrior', 'bot1=Tester Aab;Mystic'] and not any('pw' in x for x in lst), 'list lines carry no password')

    d = tempfile.mkdtemp()
    try:
        T.save_state(d, {'bots': bots})
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ok = js.main(['list', '--state', d]) == 0 and js.main(['env', '--state', d, '--index', '1']) == 0
        check(ok and 'bot1=Tester Aab;Mystic' in buf.getvalue() and 'CHAOS_LIVE_PASSWORD=pw2' in buf.getvalue(), 'list and env read the state')
        for argv in (['env', '--state', d, '--index', '9'], ['setup', '--state', d], ['setup', '--state', d, '--count', 'x', '--server-dir', d], ['list'], ['env', '--state', d, '--bogus']):
            try:
                js.main(argv)
                check(False, 'usage error: ' + ' '.join(argv))
            except SystemExit as e:
                check(e.code not in (0, None), 'usage error: ' + ' '.join(argv))
        try:
            js.setup(11, d, d)
            check(False, 'more than 10 bots refused')
        except SystemExit:
            check(True, 'more than 10 bots refused')
        try:
            js.setup(2, d, d)
            check(False, 'setup over an existing state refused')
        except SystemExit:
            check(True, 'setup over an existing state refused')
    finally:
        import shutil
        shutil.rmtree(d)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

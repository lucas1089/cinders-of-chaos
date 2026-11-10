#!/usr/bin/env python3
"""Tests for launch_check.py (O440, `chaos-ctl.sh launch-check`): the tolerant Lua reader, the decision of each check from its
inputs (OK / WARN / FAIL), the report text, the JSON, the exit code, a whole run on a temporary server folder with a fake
git and fake facts, and that the client key is never printed. Fixtures are made up: no real account, name, key or log.

usage: python3 -I server/deploy/launch_check_test.py
"""
import contextlib
import datetime
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import launch_check as L  # noqa: E402

checks = 0


def ok(cond, what):
    global checks
    checks += 1
    if not cond:
        print('FAIL: ' + what)
        sys.exit(1)


def status(r):
    return r[0]


# an example launch (O463): the shipped one is "open", and the owner's date is never pinned in a test
LAUNCH = datetime.datetime(2031, 3, 14, 18, 0)
LATER = datetime.datetime(2031, 4, 4, 18, 0)
FAKE_KEY = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff'   # made up, never printed anywhere

# ------------------------------------------------------------------ the Lua reader
t = L.strip_comments('a = 1 -- note\nb = "x -- y" -- tail\n--[[ block\nc = 2 ]] d = 3\n--[==[ more\n]==] e = 4\n')
ok('note' not in t and 'tail' not in t and 'x -- y' in t and 'c = 2' not in t and 'd = 3' in t and 'e = 4' in t,
   'comments are cut, a -- inside a string stays: ' + repr(t))
ok(L.lua_value('enabled = true,', 'enabled') is True and L.lua_value('enabled = false', 'enabled') is False, 'booleans')
ok(L.lua_value('\tmaxPlayers = 400,\n', 'maxPlayers') == 400, 'integer')
ok(L.lua_value('x = -3', 'x') == -3 and L.lua_value('x = 1.5', 'x') == 1.5, 'negative and float')
ok(L.lua_value('mode = "enforce",', 'mode') == 'enforce' and L.lua_value("mode = 'log'", 'mode') == 'log', 'strings')
ok(L.lua_value('{year = 2031, month = 3, day = 14, hour = 18}', 'hour') == 18, 'keys inside a one line table')
ok(L.lua_value('config.enabled = true\nxenabled = true\n', 'enabled') is None, 'a dotted or longer key is another key')
ok(L.lua_value('key = os.getenv("K") or ""', 'key') is None, 'an expression is not a scalar')
ok(L.lua_value('n = 400 + 1', 'n') is None, 'a sum is not read as its first number')
ok(L.lua_value('a = 1\nb = 2', 'b') == 2 and L.lua_value('a = 1\nb = 2\nb = 3', 'b') == 2, 'the first assignment wins')
ok(L.lua_table('x = {a = {b = "}"}, c = 1}\ny = 2', 'x') == '{a = {b = "}"}, c = 1}', 'balanced table with a brace in a string')
ok(L.lua_table('x = 1', 'x') is None, 'no table')
ok(L.to_datetime(20310314, 18) == LAUNCH and L.to_datetime('2031-03-14 18:00') == LAUNCH
   and L.to_datetime('2031-03-14', 18) == LAUNCH, 'dates: YYYYMMDD with hour, string, string with hour')
ok(L.to_datetime(20261399, 0) is None and L.to_datetime('soon') is None and L.to_datetime(True) is None
   and L.to_datetime(5) is None and L.to_datetime(None) is None, 'bad dates are None')
os.environ['TZ'] = 'UTC'
time.tzset()
ok(L.to_datetime(1795186800) == datetime.datetime.fromtimestamp(1795186800), 'a unix time is read as local time')

# ------------------------------------------------------------------ the facts of the shell tool
f = L.parse_facts('db\tplayers\t12\ndb\taccounts\tERR:no-table\ndb\tx\tabc\npay\tpix_provider\tmercadopago\nbogus\n\nfoo\ta\tb\n')
ok(f['db'] == {'players': 12, 'accounts': 'ERR:no-table', 'x': 'ERR:database'} and f['pay'] == {'pix_provider': 'mercadopago'},
   'facts: ' + repr(f))
ok(L.parse_facts('') == {'db': {}, 'pay': {}} and L.parse_facts(None) == {'db': {}, 'pay': {}}, 'no facts')

# ------------------------------------------------------------------ beta switches
ok(status(L.check_beta_config('return {\n\tenabled = false, -- the open beta is on; false at launch\n\tstarterCoins = 5000\n}')) == 'OK',
   'beta_config false is OK')
r = L.check_beta_config('return {\n\tenabled = true, -- beta\n}')
ok(status(r) == 'FAIL' and 'free starter coins' in r[2], 'beta_config true is FAIL')
ok(status(L.check_beta_config('-- enabled = true\nreturn {enabled = false}')) == 'OK', 'a commented enabled = true does not count')
r = L.check_beta_config('return {starterCoins = 1}')
ok(status(r) == 'FAIL' and 'cannot read' in r[2], 'no enabled line: cannot read')
r = L.check_beta_config(None)
ok(status(r) == 'FAIL' and 'cannot read' in r[2], 'missing file: cannot read')
ok(status(L.check_beta_mode('return {\n\tenabled = false,\n\tstoreOfferKeys = {}\n}')) == 'OK', 'beta_mode false is OK')
ok(status(L.check_beta_mode('return {enabled = true}')) == 'FAIL', 'beta_mode true is FAIL')
ok(status(L.check_beta_mode(None)) == 'FAIL' and status(L.check_beta_mode('return {}')) == 'FAIL', 'beta_mode unreadable is FAIL')
ok(status(L.check_beta_cron(False)) == 'OK' and status(L.check_beta_cron(True)) == 'FAIL', 'the beta coins cron: absent OK, present FAIL')

# ------------------------------------------------------------------ payments
LIVE = {'pix_provider': 'mercadopago', 'paypal_provider': 'off', 'mock': 'no', 'mp_token': 'live'}
ok(status(L.check_payments(LIVE)) == 'OK', 'a live provider is OK')
ok(status(L.check_payments(dict(LIVE, pix_provider='off', paypal_provider='paypal'))) == 'OK', 'PayPal alone is live')
ok(status(L.check_payments(dict(LIVE, pix_provider='mock'))) == 'FAIL', 'a mock Pix provider is FAIL')
ok(status(L.check_payments(dict(LIVE, paypal_provider='mock', mock='yes'))) == 'FAIL', 'a mock PayPal provider is FAIL')
ok(status(L.check_payments(dict(LIVE, mock='yes'))) == 'FAIL', 'the mock flag of pay-status is FAIL')
r = L.check_payments(dict(LIVE, pix_provider='off'))
ok(status(r) == 'WARN' and 'no live payment provider' in r[2], 'no live provider is WARN')
ok(status(L.check_payments(dict(LIVE, mp_token='test'))) == 'WARN', 'a Mercado Pago test token is WARN')
ok(status(L.check_payments({})) == 'FAIL' and status(L.check_payments(None)) == 'FAIL', 'no payments status is FAIL')
ok(status(L.check_payments(dict(LIVE, pix_provider='invalid'))) == 'WARN', 'an invalid provider value is not live: WARN')

# ------------------------------------------------------------------ test files
tmp = tempfile.mkdtemp(prefix='chaos-launch-test-')
try:
    server = os.path.join(tmp, 'server')
    scripts = os.path.join(server, 'data', 'scripts')
    os.makedirs(os.path.join(scripts, 'chaos'))
    os.makedirs(os.path.join(scripts, 'talkactions'))
    os.makedirs(os.path.join(server, 'data', 'patchnotes'))
    ok(status(L.check_test_files(os.path.join(tmp, 'nothing'))) == 'FAIL', 'no data/scripts: cannot read')
    ok(status(L.check_test_files(server)) == 'OK', 'a clean scripts folder is OK')
    for n in range(7):
        open(os.path.join(scripts, 'zz_probe%d.lua' % n), 'w').close()
    open(os.path.join(scripts, 'talkactions', 'ztest_x.lua'), 'w').close()
    open(os.path.join(scripts, 'chaos', 'zebra.lua'), 'w').close()       # starts with z, is not a test file
    open(os.path.join(scripts, 'chaos', 'zz.lua'), 'w').close()           # not zz_
    r = L.check_test_files(server)
    ok(status(r) == 'FAIL' and '8 test only' in r[2] and r[2].count('zz_probe') + r[2].count('ztest_x') == 5
       and 'and 3 more' in r[2] and 'zebra' not in r[2], 'test files are listed, at most 5: ' + r[2])
    for n in os.listdir(scripts):
        p = os.path.join(scripts, n)
        if os.path.isfile(p):
            os.remove(p)
    os.remove(os.path.join(scripts, 'talkactions', 'ztest_x.lua'))
    ok(status(L.check_test_files(server)) == 'OK', 'cleaned up: OK again')
    os.makedirs(os.path.join(server, 'ztest'))
    r = L.check_test_files(server)
    ok(status(r) == 'FAIL' and 'ztest' in r[2], 'a ztest folder in the server folder is FAIL')
    shutil.rmtree(os.path.join(server, 'ztest'))

    # --------------------------------------------------------------- timezone
    SP = [('timedatectl', 'America/Sao_Paulo'), ('/etc/timezone', 'America/Sao_Paulo')]
    ok(status(L.check_timezone(SP, -180, 'America/Sao_Paulo', -180)) == 'OK', 'timezone: Sao Paulo is OK')
    r = L.check_timezone([('timedatectl', 'Etc/UTC')], 0, 'America/Sao_Paulo', -180)
    ok(status(r) == 'FAIL' and 'Etc/UTC' in r[2] and 'UTC+00:00' in r[2] and 'chaos-ctl.sh timezone set' in r[2],
       'timezone: UTC is FAIL with the zone, the offset and the fix: ' + r[2])

    # --------------------------------------------------------------- maxPlayers
    cfg_lua = 'worldName = "x"\nmaxPlayers = 400 -- the launch cap\nclientGuardMode = "enforce"\n'
    r = L.check_max_players(cfg_lua, None)
    ok(status(r) == 'WARN' and '400' in r[2] and 'owner decision: 300 or 400' in r[2], 'maxPlayers: always WARN without the flag')
    ok(status(L.check_max_players(cfg_lua, 400)) == 'OK', 'maxPlayers equal to the flag is OK')
    r = L.check_max_players(cfg_lua, 300)
    ok(status(r) == 'FAIL' and '400' in r[2] and '300' in r[2], 'maxPlayers different from the flag is FAIL')
    ok(status(L.check_max_players('x = 1', None)) == 'FAIL' and status(L.check_max_players(None, None)) == 'FAIL',
       'maxPlayers unreadable is FAIL')
    ok(status(L.check_max_players('maxPlayers = os.getenv("N")', None)) == 'FAIL', 'maxPlayers as an expression: cannot read')

    # --------------------------------------------------------------- the one launch value (launch_config.lua, O463)
    LCFG_OPEN = 'return {\n\tlaunch = "open", -- no date\n\toffsets = {freeze = -5, wipe = -2, rehearsal = -1, founderEnd = 28}\n}\n'
    LCFG_SET = LCFG_OPEN.replace('"open"', '"2031-03-14 18:00"')
    c = L.read_launch_config(LCFG_OPEN)
    ok(c['open'] and c['launch'] is None and c['raw'] == 'open' and c['offsets'] == L.OFFSETS, 'the reader: open')
    c = L.read_launch_config(LCFG_SET)
    ok(not c['open'] and c['launch'] == LAUNCH and c['raw'] == '2031-03-14 18:00', 'the reader: a date')
    c = L.read_launch_config(LCFG_SET.replace('founderEnd = 28', 'founderEnd = 30'))
    ok(c['offsets']['founderEnd'] == 30 and c['offsets']['wipe'] == -2, 'the reader: an offset moves')
    c = L.read_launch_config('return {launch = "soon"}')
    ok(not c['open'] and c['launch'] is None and c['raw'] == 'soon', 'the reader: a value that is neither')
    ok(L.read_launch_config(None) is None, 'the reader: no file')
    ok(L.read_launch_config('return {}')['raw'] is None, 'the reader: no value')
    ok(L.read_launch_config('-- launch = "2031-03-14 18:00"\nreturn {launch = "open"}')['open'], 'the reader: a commented date does not count')
    # launch_date: open = WARN with a clear sentence; a date = OK; broken = FAIL
    r = L.check_launch_date(LCFG_OPEN, None)
    ok(status(r) == 'WARN' and 'no launch date is set' in r[2] and 'skipped' in r[2], 'launch_date open: WARN, says no date is set: ' + r[2])
    r = L.check_launch_date(LCFG_OPEN, LAUNCH)
    ok(status(r) == 'WARN' and '--launch 2031-03-14 18:00' in r[2], 'launch_date open with --launch: WARN, names both')
    r = L.check_launch_date(LCFG_SET, None)
    ok(status(r) == 'OK' and '2031-03-14 18:00' in r[2], 'launch_date set: OK: ' + r[2])
    ok(status(L.check_launch_date(LCFG_SET, LAUNCH)) == 'OK', 'launch_date set, --launch the same: OK')
    r = L.check_launch_date(LCFG_SET, LATER)
    ok(status(r) == 'FAIL' and '2031-03-14 18:00' in r[2] and '2031-04-04 18:00' in r[2], 'launch_date set, --launch different: FAIL')
    ok(status(L.check_launch_date(LCFG_OPEN.replace('"open"', '"2031-03-14 18:30"'), None)) == 'FAIL', 'launch_date off the hour: FAIL')
    ok(status(L.check_launch_date(LCFG_OPEN.replace('"open"', '"soon"'), None)) == 'FAIL', 'launch_date not a date: FAIL')
    ok(status(L.check_launch_date(LCFG_OPEN.replace('"open"', '"2031-02-30 18:00"'), None)) == 'FAIL', 'launch_date not a real day: FAIL')
    ok(status(L.check_launch_date('return {}', None)) == 'FAIL' and status(L.check_launch_date(None, None)) == 'FAIL',
       'launch_date: no value or no file is cannot read (FAIL)')
    ok(L.effective_launch(LCFG_OPEN, None) == (None, None) and L.effective_launch(LCFG_SET, None) == (LAUNCH, LAUNCH)
       and L.effective_launch(LCFG_SET, LATER) == (LATER, LAUNCH) and L.effective_launch(LCFG_OPEN, LATER) == (LATER, None),
       'effective launch: --launch wins, the file is the default')

    # --------------------------------------------------------------- dates: configs that read the one value (the shipped form)
    F_SEASON = 'local LC = dofile("data/scripts/chaos/launch_core.lua")\nreturn {seasons = {{id = 1, open = LC.isOpen() or nil, start = LC.ymd(0)}}}\n'
    F_PVP = 'return {season = {weeks = 8, epoch = dofile("data/scripts/chaos/launch_core.lua").parts(0)}}\n'
    F_FOUNDER = 'local LC = dofile("data/scripts/chaos/launch_core.lua")\nlocal START = LC.stamp(0)\nreturn {start = START}\n'
    F_CREATOR = 'return {launchBonusPct = 15, launchBonusStart = dofile("data/scripts/chaos/launch_core.lua").stamp(0), launchBonusDays = 30}\n'
    for fn, text, what in ((L.check_dates_season, F_SEASON, 'season'), (L.check_dates_pvp, F_PVP, 'pvp'),
                           (L.check_dates_founder, F_FOUNDER, 'founder'), (L.check_dates_creator, F_CREATOR, 'creator')):
        r = fn(text, None)
        ok(status(r) == 'OK' and 'open' in r[2] and '20' not in r[2].replace('2026-11-10', ''), 'open, %s follows: OK, no date printed: %s' % (what, r[2]))
        r = fn(text, LAUNCH)
        ok(status(r) == 'OK' and '2031-03-14 18:00' in r[2], 'set, %s follows: OK with the date: %s' % (what, r[2]))
        bad = 'FAIL' if what in ('season', 'founder') else 'WARN'
        r = fn(text, LATER, cfg_launch=LAUNCH)
        ok(status(r) == bad and '2031-03-14 18:00' in r[2] and '2031-04-04 18:00' in r[2], '--launch moves the expectation, %s %s: %s' % (what, bad, r[2]))
        r = fn(text, LAUNCH, cfg_launch=None)
        ok(status(r) == bad and 'open' in r[2], 'the file is open but the launch is set, %s %s' % (what, bad))
        ok(status(fn(None, LAUNCH)) == 'FAIL', 'no %s file: cannot read' % what)
    r = L.check_dates_season(F_SEASON, LAUNCH)
    ok('2031-06-13 18:00' in r[2], 'season end = launch + 91 days: ' + r[2])
    r = L.check_dates_founder(F_FOUNDER, LAUNCH)
    ok('2031-04-11 18:00' in r[2], 'Founder end = launch + 28 days: ' + r[2])
    r = L.check_dates_founder(F_FOUNDER, LAUNCH, offsets=dict(L.OFFSETS, founderEnd=30))
    ok('2031-04-13 18:00' in r[2], 'Founder end follows the offset of the file: ' + r[2])
    r = L.check_dates_creator(F_CREATOR, LAUNCH)
    ok('2031-04-13 18:00' in r[2], 'creator bonus = launch + 30 days: ' + r[2])
    r = L.check_dates_pvp(F_PVP, LAUNCH)
    ok('2031-05-09 18:00' in r[2], 'PvP season end = launch + 8 weeks: ' + r[2])
    ok(status(L.check_dates_creator('return {launchBonusStart = dofile("data/scripts/chaos/launch_core.lua").stamp(0)}', LAUNCH)) == 'FAIL',
       'creator follows but launchBonusDays is missing: cannot read')
    ok(status(L.check_dates_season('-- launch_core.lua in a comment only\nreturn {seasons = {{id = 1, start = 20310314, finish = 20310613, hour = 18}}}', None)) == 'FAIL',
       'a comment that names launch_core.lua does not count as reading it')

    # --------------------------------------------------------------- dates: a config with its own date (hand edited, the old form)
    SEASON = ('return {\n\tseasons = {\n\t\t{\n\t\t\tid = 1,\n\t\t\tname = "Season of Ash",\n\t\t\tstart = 20310314, -- the launch\n'
              '\t\t\tfinish = 20310613,\n\t\t\thour = 18,\n\t\t\tmodifier = {name = "A", expMult = 1.1}\n\t\t},\n'
              '\t\t{\n\t\t\tid = 2,\n\t\t\tstart = 20310614,\n\t\t\tfinish = 20310914,\n\t\t\thour = 12\n\t\t}\n\t},\n\tjoin = {maxLevel = 7}\n}\n')
    r = L.check_dates_season(SEASON, LAUNCH)
    ok(status(r) == 'OK' and '2031-03-14 18:00' in r[2] and '2031-06-13 18:00' in r[2], 'Season 1 at the launch is OK: ' + r[2])
    r = L.check_dates_season(SEASON.replace('start = 20310314', 'start = 20310315'), LAUNCH)
    ok(status(r) == 'FAIL' and '2031-03-15 18:00' in r[2] and '2031-03-14 18:00' in r[2], 'Season 1 one day late is FAIL: ' + r[2])
    ok(status(L.check_dates_season(SEASON.replace('hour = 18', 'hour = 12'), LAUNCH)) == 'FAIL', 'Season 1 at the wrong hour is FAIL')
    ok(status(L.check_dates_season(SEASON, LATER)) == 'FAIL', '--launch moves the expected start')
    ok(status(L.check_dates_season(SEASON.replace('id = 1', 'id = 9'), LAUNCH)) == 'FAIL', 'no Season 1: cannot read')
    r = L.check_dates_season(SEASON.replace('start = 20310314', 'start = soon'), LAUNCH)
    ok(status(r) == 'FAIL' and 'cannot read' in r[2], 'a start that is not a date: cannot read')
    ok(status(L.check_dates_season(None, LAUNCH)) == 'FAIL', 'no season file: cannot read')
    ok(status(L.check_dates_season('return {}', LAUNCH)) == 'FAIL', 'an empty season file: cannot read')
    r = L.check_dates_season(SEASON.replace('start = 20310314', 'start = "2031-03-14"'), LAUNCH)
    ok(status(r) == 'OK', 'a string date uses the hour too')
    r = L.check_dates_season(SEASON, None)
    ok(status(r) == 'FAIL' and 'launch is open' in r[2] and 'start by itself' in r[2], 'open launch, a season with its own date: FAIL (it would start): ' + r[2])

    PVP = 'return {\n\tseason = {\n\t\tweeks = 8,\n\t\tepoch = {year = 2031, month = 3, day = 14, hour = 18},\n\t\tbrackets = {"1v1"}\n\t}\n}\n'
    r = L.check_dates_pvp(PVP, LAUNCH)
    ok(status(r) == 'OK' and '2031-03-14 18:00' in r[2] and '2031-05-09 18:00' in r[2], 'PvP season at the launch: ' + r[2])
    ok(status(L.check_dates_pvp(PVP.replace('day = 14', 'day = 15'), LAUNCH)) == 'WARN', 'PvP epoch off the launch is WARN')
    ok(status(L.check_dates_pvp('return {season = {weeks = 8}}', LAUNCH)) == 'FAIL', 'no epoch: cannot read')
    ok(status(L.check_dates_pvp(None, LAUNCH)) == 'FAIL', 'no PvP file: cannot read')
    ok(status(L.check_dates_pvp(PVP, None)) == 'WARN', 'open launch, a PvP epoch of its own: WARN')

    FOUNDER = ('local START = "2031-03-14 18:00" -- launch, server time\nlocal END = "2031-04-11 18:00" -- four weeks\n'
               'local cfg = {\n\tstart = START,\n\t["end"] = END\n}\nreturn cfg\n')
    r = L.check_dates_founder(FOUNDER, LAUNCH)
    ok(status(r) == 'OK' and '2031-04-11 18:00' in r[2], 'Founder window at the launch: ' + r[2])
    r = L.check_dates_founder(FOUNDER.replace('2031-03-14 18:00', '2031-03-14 12:00'), LAUNCH)
    ok(status(r) == 'FAIL' and '2031-03-14 12:00' in r[2], 'Founder start 6 hours early is FAIL: ' + r[2])
    ok(status(L.check_dates_founder('return {}', LAUNCH)) == 'FAIL', 'Founder: cannot read')
    ok(status(L.check_dates_founder(None, LAUNCH)) == 'FAIL', 'Founder: no file')
    ok(status(L.check_dates_founder('local cfg = {start = "2031-03-14 18:00", ["end"] = "x"}', LAUNCH)) == 'FAIL',
       'Founder: an end that is not a date is cannot read')
    r = L.check_dates_founder(FOUNDER, None)
    ok(status(r) == 'FAIL' and 'launch is open' in r[2] and 'go on sale by itself' in r[2], 'open launch, a Founder window of its own: FAIL (it would sell): ' + r[2])

    CREATOR = 'return {\n\tlaunchBonusPct = 15,\n\tlaunchBonusStart = "2031-03-14 18:00",\n\tlaunchBonusDays = 30,\n}\n'
    r = L.check_dates_creator(CREATOR, LAUNCH)
    ok(status(r) == 'OK' and '2031-04-13 18:00' in r[2], 'creator bonus window at the launch: ' + r[2])
    ok(status(L.check_dates_creator(CREATOR.replace('03-14', '03-21'), LAUNCH)) == 'WARN', 'creator bonus off the launch is WARN')
    ok(status(L.check_dates_creator('return {}', LAUNCH)) == 'FAIL' and status(L.check_dates_creator(None, LAUNCH)) == 'FAIL',
       'creator bonus: cannot read')
    ok(status(L.check_dates_creator(CREATOR, None)) == 'WARN', 'open launch, a bonus start of its own: WARN')

    # --------------------------------------------------------------- client guard
    GUARD = 'clientGuardMode = "enforce"\nclientGuardKey = os.getenv("CHAOS_CLIENT_KEY") or ""\nclientGuardAllowDevKey = false\n'
    ENV_KEY = 'CHAOS_DB_USER=x\nCHAOS_CLIENT_KEY=%s\n' % FAKE_KEY
    r = L.check_client_guard(GUARD, ENV_KEY, False)
    ok(status(r) == 'OK' and FAKE_KEY not in r[2] and 'enforce' in r[2], 'enforce with the key in the env file is OK, no key printed')
    ok(status(L.check_client_guard(GUARD, 'CHAOS_CLIENT_KEY="%s"  # secret\n' % FAKE_KEY, False)) == 'OK', 'a quoted key counts')
    r = L.check_client_guard(GUARD, 'CHAOS_DB_USER=x\nCHAOS_CLIENT_KEY=\n', False)
    ok(status(r) == 'FAIL' and 'no client key' in r[2], 'an empty key is FAIL')
    ok(status(L.check_client_guard(GUARD, None, False)) == 'FAIL', 'no env file and no other key is FAIL')
    ok(status(L.check_client_guard(GUARD, None, True)) == 'OK', 'a key file counts')
    ok(status(L.check_client_guard(GUARD.replace('os.getenv("CHAOS_CLIENT_KEY") or ""', '"%s"' % FAKE_KEY), None, False)) == 'OK',
       'a literal key in config.lua counts')
    r = L.check_client_guard(GUARD.replace('"enforce"', '"log"'), ENV_KEY, False)
    ok(status(r) == 'WARN' and 'log' in r[2] and FAKE_KEY not in r[2], 'log mode is WARN')
    ok(status(L.check_client_guard(GUARD.replace('"enforce"', '"off"'), ENV_KEY, False)) == 'FAIL', 'mode off is FAIL')
    ok(status(L.check_client_guard(GUARD.replace('false', 'true'), ENV_KEY, False)) == 'FAIL', 'a dev key allowed is FAIL')
    ok(status(L.check_client_guard('maxPlayers = 400\n', ENV_KEY, False)) == 'FAIL', 'no mode at all (engine default off) is FAIL')
    ok(status(L.check_client_guard(GUARD.replace('"enforce"', '"anything"'), ENV_KEY, False)) == 'OK',
       'any other mode value counts as enforce, like the engine')
    ok(status(L.check_client_guard(None, ENV_KEY, False)) == 'FAIL', 'no config.lua: cannot read')

    # --------------------------------------------------------------- patch notes
    r = L.check_patch_notes(server, None)
    ok(status(r) == 'OK' and 'not checked' in r[2] and 'no launch date' in r[2], 'patch notes with no launch date: OK, says not checked: ' + r[2])
    r = L.check_patch_notes(server, LAUNCH)
    ok(status(r) == 'WARN' and '2031-03-14.md' in r[2] and '2031-03-14.pt-br.md' in r[2], 'patch notes missing: WARN names both files')
    open(os.path.join(server, 'data', 'patchnotes', '2031-03-14.md'), 'w').close()
    r = L.check_patch_notes(server, LAUNCH)
    ok(status(r) == 'WARN' and '2031-03-14.pt-br.md' in r[2] and '2031-03-14.md,' not in r[2], 'only the pt-BR twin missing: WARN')
    open(os.path.join(server, 'data', 'patchnotes', '2031-03-14.pt-br.md'), 'w').close()
    ok(status(L.check_patch_notes(server, LAUNCH)) == 'OK', 'both patch notes there: OK')
    ok(status(L.check_patch_notes(server, LATER)) == 'WARN', 'the date follows --launch')

    # --------------------------------------------------------------- database
    DB0 = {'players': 0, 'accounts': 0, 'accounts_with_coins': 0, 'players_online': 0, 'beta_testers': 0}
    ok(status(L.check_database(DB0)) == 'OK', 'an empty database is OK')
    r = L.check_database(dict(DB0, players=12, accounts=9))
    ok(status(r) == 'WARN' and 'players 12' in r[2] and 'Expected before the wipe' in r[2], 'players are WARN: ' + r[2])
    ok(status(L.check_database(dict(DB0, accounts=4, accounts_with_coins=3))) == 'WARN', 'accounts with coins are WARN')
    ok(status(L.check_database(dict(DB0, accounts=4, players_online=1, beta_testers=2))) == 'OK',
       'online and beta tester rows alone are only printed')
    r = L.check_database(dict(DB0, beta_testers='ERR:no-table'))
    ok(status(r) == 'FAIL' and 'beta_testers (no-table)' in r[2], 'a count that cannot be read is FAIL: ' + r[2])
    ok(status(L.check_database({})) == 'FAIL', 'no counts at all is FAIL')
    r = L.check_database({'players': 1})
    ok(status(r) == 'FAIL' and 'accounts (missing)' in r[2], 'missing counts are FAIL')

    # --------------------------------------------------------------- backup
    bdir = os.path.join(tmp, 'backups')
    NOW = time.time()
    r = L.check_backup(os.path.join(tmp, 'nobackups'), NOW)
    ok(status(r) == 'FAIL' and 'cannot read the backup folder' in r[2], 'no backup folder is FAIL')
    os.makedirs(os.path.join(bdir, 'db'))
    ok(status(L.check_backup(bdir, NOW)) == 'FAIL' and 'no backup file' in L.check_backup(bdir, NOW)[2], 'an empty backup folder is FAIL')

    def stamp(path, hours):
        open(path, 'w').close()
        os.utime(path, (NOW - hours * 3600, NOW - hours * 3600))
    stamp(os.path.join(bdir, 'db', 'chaos-db-x-1.sql.gz'), 30)
    stamp(os.path.join(bdir, '.offsite_last'), 1)           # a hidden stamp file is not a backup
    r = L.check_backup(bdir, NOW)
    ok(status(r) == 'WARN' and '30.0 hours' in r[2], 'a 30 hour old backup is WARN: ' + r[2])
    stamp(os.path.join(bdir, 'db', 'chaos-db-x-2.sql.gz'), 23.5)
    ok(status(L.check_backup(bdir, NOW)) == 'OK', 'a 23.5 hour old backup is OK')
    stamp(os.path.join(bdir, 'db', 'chaos-db-x-3.sql.gz'), 24.5)
    ok(status(L.check_backup(bdir, NOW)) == 'OK', 'the newest file decides')
    os.remove(os.path.join(bdir, 'db', 'chaos-db-x-2.sql.gz'))
    ok(status(L.check_backup(bdir, NOW)) == 'WARN', 'at 24 hours and more: WARN')

    # --------------------------------------------------------------- checkout
    def fake_git(branch='main', dirty='', head='abc1234deadbeef', main_head=None, describe='winpkg-50-3-gabc1234', fail=False):
        def run(cmd):
            if fail:
                return 128, ''
            sub = cmd[5:]
            if sub[:2] == ['rev-parse', '--short']:
                return 0, head[:7] + '\n'
            if sub[:2] == ['symbolic-ref', '--short']:
                return (0, branch + '\n') if branch else (1, '')
            if sub[0] == 'status':
                return 0, dirty
            if sub == ['rev-parse', 'HEAD']:
                return 0, head + '\n'
            if sub[:3] == ['rev-parse', '-q', '--verify']:
                return (0, (main_head or 'f' * 15) + '\n') if sub[3] in ('refs/heads/main', 'refs/remotes/origin/main') else (1, '')
            if sub[0] == 'describe':
                return 0, describe + '\n'
            return 1, ''
        return run
    r = L.check_checkout(L.git_facts('/r', fake_git()), '/r')
    ok(status(r) == 'OK' and 'branch main' in r[2] and 'abc1234' in r[2] and 'clean' in r[2], 'main and clean is OK: ' + r[2])
    r = L.check_checkout(L.git_facts('/r', fake_git(dirty=' M a.lua\n?? b.lua\n')), '/r')
    ok(status(r) == 'WARN' and 'dirty (2 changed' in r[2] and 'not on main' not in r[2], 'dirty is WARN: ' + r[2])
    r = L.check_checkout(L.git_facts('/r', fake_git(branch='feature')), '/r')
    ok(status(r) == 'WARN' and 'branch feature' in r[2] and 'not on main' in r[2], 'another branch is WARN')
    r = L.check_checkout(L.git_facts('/r', fake_git(branch='')), '/r')
    ok(status(r) == 'WARN' and 'detached at winpkg-50-3-gabc1234' in r[2] and 'not on main' in r[2], 'detached off main is WARN: ' + r[2])
    r = L.check_checkout(L.git_facts('/r', fake_git(branch='', main_head='abc1234deadbeef')), '/r')
    ok(status(r) == 'OK', 'detached at the commit main points to is on main')
    r = L.check_checkout(L.git_facts('/r', fake_git(branch='', dirty=' M x\n')), '/r')
    ok(status(r) == 'WARN' and 'dirty' in r[2] and 'not on main' in r[2], 'both problems are named')
    ok(status(L.check_checkout(L.git_facts('/r', fake_git(fail=True)), '/r')) == 'FAIL', 'not a checkout is FAIL')
    ok(status(L.check_checkout(None, '')) == 'FAIL', 'no checkout given is FAIL')

    # --------------------------------------------------------------- the report
    res = [('OK', 'a', 'fine.'), ('WARN', 'b', 'hm.'), ('FAIL', 'c', 'bad.'), ('FAIL', 'd', 'worse.')]
    ok(L.exit_code(res) == 1 and L.exit_code(res[:2]) == 0 and L.exit_code([]) == 0, 'exit 1 only with a FAIL')
    ok(L.counts(res) == {'FAIL': 2, 'WARN': 1, 'OK': 1}, 'counts')
    txt = L.report_text(res)
    lines = txt.split('\n')
    ok(lines[0] == 'OK   a              fine.' and lines[2].startswith('FAIL c ') and lines[-1] == 'launch check: 2 FAIL, 1 WARN, 1 OK',
       'report text: ' + txt)
    js = json.loads(L.report_json(res, '2031-03-14 18:00'))
    ok(js['ok'] is False and js['fail'] == 2 and js['warn'] == 1 and js['okCount'] == 1 and js['launch'] == '2031-03-14 18:00'
       and js['launchOpen'] is False and js['checks'][2] == {'status': 'FAIL', 'name': 'c', 'text': 'bad.'}, 'json: ' + str(js))
    js = json.loads(L.report_json(res, None))
    ok(js['launch'] is None and js['launchOpen'] is True, 'json: no launch date is null and launchOpen')
    ok(json.loads(L.report_json(res[:2], 'x'))['ok'] is True, 'json ok without FAIL')

    # --------------------------------------------------------------- a whole run on a temporary server
    cfg = os.path.join(server, 'data', 'scripts', 'chaos')
    envf = os.path.join(tmp, 'chaos.env')
    cron = os.path.join(tmp, 'chaos-beta-coins')

    def write(path, text):
        with open(path, 'w') as fh:
            fh.write(text)
    write(os.path.join(cfg, 'beta_config.lua'), 'return {enabled = false}\n')
    write(os.path.join(cfg, 'beta_mode_config.lua'), 'return {enabled = false}\n')
    write(os.path.join(cfg, 'launch_config.lua'), LCFG_SET)
    write(os.path.join(cfg, 'season_config.lua'), F_SEASON)
    write(os.path.join(cfg, 'battleground_config.lua'), F_PVP)
    write(os.path.join(cfg, 'founder_config.lua'), F_FOUNDER)
    write(os.path.join(cfg, 'creator_codes_config.lua'), F_CREATOR)
    for n in ('2031-03-14.md', '2031-03-14.pt-br.md'):
        write(os.path.join(server, 'data', 'patchnotes', n), 'x\n')
    write(os.path.join(server, 'config.lua'), cfg_lua + 'clientGuardKey = os.getenv("CHAOS_CLIENT_KEY") or ""\n')
    write(envf, ENV_KEY)
    stamp(os.path.join(bdir, 'db', 'chaos-db-x-9.sql.gz'), 2)
    for n in os.listdir(os.path.join(bdir, 'db')):
        if n != 'chaos-db-x-9.sql.gz':
            os.remove(os.path.join(bdir, 'db', n))
    FACTS = ''.join('db\t%s\t0\n' % k for k in L.DB_COUNTS) + ''.join(
        'pay\t%s\t%s\n' % kv for kv in LIVE.items())
    ARGS = ['--server', server, '--env-file', envf, '--backup-dir', bdir, '--repo', '/r', '--cron-file', cron,
            '--max-players', '400']
    ZONE = {'names': SP, 'offset': -180}

    def go(extra=(), facts=FACTS, zone=ZONE, runner=None):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = L.main(ARGS + list(extra), stdin_text=facts, now=NOW, zone_info=zone, runner=runner or fake_git())
        return rc, buf.getvalue()

    def by_name(out):
        d = {}
        for line in out.splitlines()[:-1]:
            s, n = line.split()[:2]
            d[n] = s
        return d

    rc, out = go()
    st = by_name(out)
    ok(rc == 0 and set(st.values()) == {'OK'} and len(st) == 17, 'a good installation with a launch date: 17 checks, all OK, exit 0: ' + out)
    ok(out.splitlines()[-1] == 'launch check: 0 FAIL, 0 WARN, 17 OK', 'the summary line: ' + out.splitlines()[-1])
    ok(FAKE_KEY not in out, 'the client key is never printed')
    rc, out = go(['--json'])
    js = json.loads(out)
    ok(rc == 0 and js['ok'] and js['launch'] == '2031-03-14 18:00' and len(js['checks']) == 17 and [c['name'] for c in js['checks']][:3] == ['beta_config', 'beta_mode', 'beta_cron']
       and FAKE_KEY not in out, 'json run')
    rc, out = go(['--launch', '2031-04-04 18:00'])
    st = by_name(out)
    ok(rc == 1 and st['launch_date'] == 'FAIL' and st['dates_season'] == 'FAIL' and st['dates_founder'] == 'FAIL'
       and st['dates_pvp'] == 'WARN' and st['dates_creator'] == 'WARN' and st['patch_notes'] == 'WARN',
       '--launch moves the expected date: ' + out)
    # the launch is open (O463): one WARN says no date is set, everything that needs no date still runs and is decided
    write(os.path.join(cfg, 'launch_config.lua'), LCFG_OPEN)
    rc, out = go()
    st = by_name(out)
    ok(rc == 0 and st['launch_date'] == 'WARN' and len(st) == 17 and sorted(set(st.values())) == ['OK', 'WARN']
       and [n for n, v in st.items() if v == 'WARN'] == ['launch_date'], 'open: only launch_date is WARN, exit 0: ' + out)
    ok('no launch date is set' in out and out.splitlines()[-1] == 'launch check: 0 FAIL, 1 WARN, 16 OK', 'open: the sentence and the summary: ' + out)
    ok(all(st[n] == 'OK' for n in ('dates_season', 'dates_pvp', 'dates_founder', 'dates_creator', 'patch_notes')), 'open: the date checks are OK, they wait')
    rc, out = go(['--json'])
    js = json.loads(out)
    ok(js['ok'] and js['launch'] is None and js['launchOpen'] is True, 'open: json launch null')
    rc, out = go(['--launch', '2031-03-14 18:00'])
    st = by_name(out)
    ok(rc == 1 and st['launch_date'] == 'WARN' and st['dates_season'] == 'FAIL' and st['dates_founder'] == 'FAIL',
       'open file, --launch given: the configs that follow the file are not at that date: ' + out)
    # a season and a Founder window with their own dates while the launch is open: they would start by themselves
    write(os.path.join(cfg, 'season_config.lua'), SEASON)
    write(os.path.join(cfg, 'founder_config.lua'), FOUNDER)
    rc, out = go()
    st = by_name(out)
    ok(rc == 1 and st['dates_season'] == 'FAIL' and st['dates_founder'] == 'FAIL', 'open: literal dates in the configs are FAIL: ' + out)
    write(os.path.join(cfg, 'season_config.lua'), F_SEASON)
    write(os.path.join(cfg, 'founder_config.lua'), F_FOUNDER)
    write(os.path.join(cfg, 'launch_config.lua'), LCFG_SET)
    os.remove(os.path.join(cfg, 'launch_config.lua'))
    rc, out = go()
    ok(rc == 1 and by_name(out)['launch_date'] == 'FAIL' and 'cannot read' in out, 'no launch_config.lua: cannot read, exit 1, no crash')
    write(os.path.join(cfg, 'launch_config.lua'), LCFG_SET)
    rc, out = go(['--max-players', '300'])
    ok(rc == 1 and by_name(out)['max_players'] == 'FAIL', '--max-players 300 against 400 is FAIL')
    # without --max-players the owner decision is a WARN, not a FAIL
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = L.main(ARGS[:-2], stdin_text=FACTS, now=NOW, zone_info=ZONE, runner=fake_git())
    ok(rc == 0 and by_name(buf.getvalue())['max_players'] == 'WARN' and 'owner decision: 300 or 400' in buf.getvalue(),
       'no --max-players: WARN, exit 0')

    # break one thing at a time
    write(os.path.join(cfg, 'beta_config.lua'), 'return {enabled = true}\n')
    rc, out = go()
    ok(rc == 1 and by_name(out)['beta_config'] == 'FAIL', 'beta_config true: exit 1')
    write(os.path.join(cfg, 'beta_config.lua'), 'return {enabled = false}\n')
    write(cron, '* * * * * root true\n')
    rc, out = go()
    ok(rc == 1 and by_name(out)['beta_cron'] == 'FAIL', 'the cron file present: exit 1')
    os.remove(cron)
    rc, out = go(facts=FACTS.replace('mercadopago', 'mock'))
    ok(rc == 1 and by_name(out)['payments'] == 'FAIL', 'a mock provider: exit 1')
    rc, out = go(facts=''.join(l + '\n' for l in FACTS.splitlines() if l.startswith('db')))
    ok(rc == 1 and by_name(out)['payments'] == 'FAIL' and by_name(out)['database'] == 'OK', 'no payments facts: FAIL')
    rc, out = go(facts=FACTS.replace('db\tplayers_online\t0', 'db\tplayers_online\tERR:database'))
    ok(rc == 1 and by_name(out)['database'] == 'FAIL', 'a count that failed: FAIL, no crash')
    rc, out = go(facts='')
    ok(rc == 1 and by_name(out)['database'] == 'FAIL' and by_name(out)['payments'] == 'FAIL', 'no facts at all: both FAIL, no crash')
    rc, out = go(facts=FACTS.replace('db\tplayers\t0', 'db\tplayers\t5'))
    ok(rc == 0 and by_name(out)['database'] == 'WARN', 'players before the wipe: WARN, exit 0')
    rc, out = go(zone={'names': [('timedatectl', 'Etc/UTC')], 'offset': 0})
    ok(rc == 1 and by_name(out)['timezone'] == 'FAIL', 'a UTC machine: exit 1')
    rc, out = go(runner=fake_git(dirty=' M x\n'))
    ok(rc == 0 and by_name(out)['checkout'] == 'WARN', 'a dirty checkout: WARN, exit 0')
    write(os.path.join(server, 'config.lua'), cfg_lua.replace('"enforce"', '"log"'))
    rc, out = go()
    ok(rc == 0 and by_name(out)['client_guard'] == 'WARN', 'log mode: WARN, exit 0')
    write(os.path.join(server, 'config.lua'), cfg_lua)
    write(envf, 'CHAOS_DB_USER=x\n')
    rc, out = go()
    ok(rc == 1 and by_name(out)['client_guard'] == 'FAIL', 'no key anywhere: exit 1')
    write(envf, ENV_KEY)
    os.remove(os.path.join(cfg, 'season_config.lua'))
    rc, out = go()
    ok(rc == 1 and by_name(out)['dates_season'] == 'FAIL' and 'cannot read' in out, 'a missing config: cannot read, exit 1, no crash')
    write(os.path.join(cfg, 'season_config.lua'), F_SEASON)
    os.remove(os.path.join(server, 'config.lua'))
    rc, out = go()
    st = by_name(out)
    ok(rc == 1 and st['max_players'] == 'FAIL' and st['client_guard'] == 'FAIL', 'no config.lua: both FAIL, no crash')

    # the command line: a bad --launch is refused, the script runs under python3 -I
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'launch_check.py'), '--server', server, '--launch', 'soon'],
                       capture_output=True, text=True)
    ok(p.returncode == 2 and '--launch' in p.stderr, 'a bad --launch is refused')
    write(os.path.join(server, 'config.lua'), cfg_lua)
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'launch_check.py'), '--server', server, '--env-file', envf,
                        '--backup-dir', bdir, '--cron-file', cron, '--max-players', '400'],
                       input=FACTS, capture_output=True, text=True, env={'PATH': os.environ.get('PATH', ''), 'TZ': 'UTC'})
    outl = p.stdout.splitlines()
    ok(p.returncode in (0, 1) and len(outl) == 18 and all(l.split()[0] in ('OK', 'WARN', 'FAIL') for l in outl[:-1])
       and outl[-1].startswith('launch check: '), 'the script runs under -I: ' + p.stdout + p.stderr)
    ok((p.returncode == 1) == any(l.startswith('FAIL') for l in outl), 'the exit code follows the FAIL lines')
    ok(FAKE_KEY not in p.stdout + p.stderr, 'the client key is not in the output of a real run')
finally:
    shutil.rmtree(tmp)

# the shipped configs are readable by the reader (the dates themselves are not asserted: the owner may move them)
repo = os.path.dirname(os.path.dirname(HERE))
cfgdir = os.path.join(repo, 'server', 'data', 'scripts', 'chaos')
for fn, name in ((L.check_beta_config, 'beta_config.lua'), (L.check_beta_mode, 'beta_mode_config.lua')):
    r = fn(L.read_text(os.path.join(cfgdir, name)))
    ok('cannot read' not in r[2], 'the shipped %s is readable: %s' % (name, r[2]))
shipped_launch = L.read_launch_config(L.read_text(os.path.join(cfgdir, 'launch_config.lua')))
ok(shipped_launch is not None and shipped_launch['raw'] is not None, 'the shipped launch_config.lua is readable')
ok(shipped_launch['open'] and shipped_launch['launch'] is None, 'the owner put the launch on hold (2026-11-10): the shipped value is open')
ok(shipped_launch['offsets'] == L.OFFSETS, 'the offsets of launch_config.lua are the ones of the tool')
r = L.check_launch_date(L.read_text(os.path.join(cfgdir, 'launch_config.lua')), None)
ok(status(r) == 'WARN' and 'no launch date is set' in r[2], 'the shipped launch_date check: WARN, no date set: ' + r[2])
for fn, name in ((L.check_dates_season, 'season_config.lua'), (L.check_dates_pvp, 'battleground_config.lua'),
                 (L.check_dates_founder, 'founder_config.lua'), (L.check_dates_creator, 'creator_codes_config.lua')):
    text = L.read_text(os.path.join(cfgdir, name))
    ok(L.follows_launch(L.strip_comments(text)), 'the shipped %s reads the one launch value' % name)
    r = fn(text, None)
    ok(r[0] == 'OK', 'the shipped %s waits while the launch is open: %s' % (name, r[2]))
    r = fn(text, LAUNCH)
    ok('cannot read' not in r[2] and r[0] == 'OK', 'the shipped %s follows an example launch: %s' % (name, r[2]))
ok(L.CRON_FILE == '/etc/cron.d/chaos-beta-coins', 'the cron file of docs/BETA.md section 4')

print('launch_check: %d checks passed' % checks)

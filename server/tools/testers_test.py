#!/usr/bin/env python3
"""Tests of the tester bots (tester_core.py, testers.py; server/README.md "Tester bots"): the behaviour scheduling, the
anomaly rules, the texts the bots read, the server log parsing and the report, the client key file rules, the setup
rows and the cleanup that deletes only testers by exact ids, a bot's reading of health, death and shop packets.

Run: python3 -I server/tools/testers_test.py (standard library only; no database, no server)."""
import contextlib
import io
import json
import os
import random
import struct
import sys
import tempfile
import time as _time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import loadtest as LT  # noqa: E402
import tester_core as TC  # noqa: E402
import testers as T  # noqa: E402

FAILS = []
CHECKS = [0]


def eq(got, want, what):
    CHECKS[0] += 1
    if got != want:
        FAILS.append('%s: got %r, want %r' % (what, got, want))


def ok(cond, what):
    eq(bool(cond), True, what)


# ---------------------------------------------------------------- scheduling
eq(TC.pick({'a': 1, 'b': 0}, random.Random(1), {'a', 'b'}), 'a', 'a zero weight is never picked')
eq(TC.pick({'a': 5}, random.Random(1), set()), None, 'nothing ready: None')
s = TC.Scheduler(7)
seen = {}
now = 0.0
for _ in range(4000):
    name = s.next(now)
    seen[name] = seen.get(name, 0) + 1
    now += 10
ok(set(seen) == set(TC.BEHAVIOURS), 'every behaviour runs in a long run')
ok(seen['hunt'] > seen['town'] * 3, 'hunting is far more common than going to town')
eq(seen['relog'] <= 4000 * 10 // 600 + 1, True, 'relog honours its cooldown')
s = TC.Scheduler(1, {'relog': (1, 600)})
eq([s.next(0), s.next(1), s.next(599), s.next(600)], ['relog', None, None, 'relog'], 'cooldowns')
first = (lambda sc: [sc.next(0), sc.next(30), sc.next(60)])
eq(first(TC.Scheduler(3)), first(TC.Scheduler(3)), 'a seed gives the same choices')

# ---------------------------------------------------------------- texts and anomaly rules
eq(TC.classify('[tester-helper] info {"cid":5,"level":30}'), ('helper', ('info', {'cid': 5, 'level': 30})), 'helper')
eq(TC.classify('Lua Script Error: [Action Interface] data/x.lua:12: attempt to index a nil value')[0], 'lua_error',
   'a Lua error text')
eq(TC.classify('You are exhausted.'), ('failure', 'exhausted'), 'a failure text')
eq(TC.classify('You gained 1500 experience points.'), ('xp', 1500), 'experience')
eq(TC.classify('Loot of a dragon: 120 gold coins, 3 platinum coins, a dragon shield'), ('loot', ('dragon', 420)),
   'loot gold')
eq(TC.classify('You advanced from Level 30 to Level 31.'), ('advance', (30, 31)), 'level up')
eq(TC.classify('You are dead.'), ('death', None), 'death text')
eq(TC.classify('Hello there'), (None, None), 'any other text')
eq(TC.xp_anomaly(100, -3), 'negative experience gain', 'negative xp')
eq(TC.xp_anomaly(100, 10 ** 12), 'absurd experience gain', 'absurd xp')
eq(TC.xp_anomaly(100, 5000), None, 'normal xp')
eq(TC.gold_anomaly(100, -1), 'negative gold', 'negative gold')
eq(TC.gold_anomaly(100, 10 ** 9), 'absurd gold in one corpse', 'absurd gold')
eq(TC.gold_anomaly(100, 300), None, 'normal gold')
eq(TC.health_anomaly(100, 0, True, 0.1), 'death within one hit from full health', 'one hit from full')
eq(TC.health_anomaly(100, 0, True), None, 'no health ever seen (age unknown): the 100 is the start value, no anomaly')
eq(TC.health_anomaly(100, 0, True, 0.1, seen=False), None, 'not seen: none')
eq(TC.health_anomaly(100, 0, True, 12.0), None, 'full health seen 12 s ago says nothing about the last hit')
eq(TC.health_anomaly(60, 0, True, 0.1), None, 'a death after damage')
eq(TC.health_anomaly(100, 70, False, 0.1), None, 'a hit')
eq(TC.health_anomaly(100, 0, False, 0.1), 'death within one hit from full health', 'the update to 0 %')

# where a tester hunts: the whole band, in hunting levels (twice the pool level the marks print), at or under the level
HUNTS = [(1, 10, 1, 1, 7), (10, 20, 2, 2, 7), (20, 30, 3, 3, 7), (20, 90, 4, 4, 7), (40, 60, 5, 5, 7), (1, 20, 6, 6, 7)]
eq([h[:2] for h in TC.safe_hunts(HUNTS, 30)], [(1, 10)], 'level 30: bands up to 15 (not 20-30, not 20-90)')
eq([h[:2] for h in TC.safe_hunts(HUNTS, 45)], [(10, 20), (1, 20)], 'level 45: bands up to 22, the highest ones')
eq([h[:2] for h in TC.safe_hunts(HUNTS, 100)], [(20, 30)], 'level 100: up to 50, the highest top')
eq([h[:2] for h in TC.safe_hunts(HUNTS, 4)], [(1, 10)], 'nothing that low: the lowest bands')
eq(all(2 * h[1] <= 45 for h in TC.safe_hunts(HUNTS, 45)), True, 'never a band over the level')

# resting in the temple after a death: 20 s, doubled for each death in a row, at most 5 minutes, forgotten after 5 minutes
eq(TC.death_rest([100.0], 100.0), 20.0, 'first death: 20 s')
eq(TC.death_rest([100.0, 130.0], 130.0), 40.0, 'second within 5 minutes: 40 s')
eq(TC.death_rest([100.0, 130.0, 170.0, 200.0], 200.0), 160.0, 'fourth: 160 s')
eq(TC.death_rest([0.0] + [float(i) for i in range(100, 110)], 110.0), 300.0, 'at most 300 s')
eq(TC.death_rest([0.0, 1000.0], 1000.0), 20.0, 'a death long ago is not in a row')


t = b'Hello world'
msg = b'\xb4\x16' + struct.pack('<H', len(t)) + t + b'\x8c\x01\x02'
eq(TC.strings_of(msg), ['Hello world'], 'protocol strings by their length')
eq(TC.strings_of(b'\x41\x00' + b'x' * 10), [], 'a length that does not fit is not a string')

# ---------------------------------------------------------------- the server log and the report
log = [
    '[2026-10-20 10:00:00] Lua Script Error: [Scripts Interface]',
    'data/scripts/chaos/x.lua:callback',
    'data/scripts/chaos/x.lua:5: attempt to index a nil value',
    'some info line',
    '[2026-10-20 10:00:05] Lua Script Error: [Scripts Interface]',
    'data/scripts/chaos/x.lua:callback',
    'data/scripts/chaos/x.lua:5: attempt to index a nil value',
    '[2026-10-20 10:00:06] [Warning - Npc::loadFromXml] something odd',
    '[tester-anomaly] {"rule":"hit taken over 3x max health","who":"Tester Abc","damage":130000000}',
    '[tester-event] {"kind":"death","who":"Tester Abc"}',
    '[tester-anomaly] {broken',
    '[Error - mysql_real_query] Query: SELECT 1',
]
p = TC.parse_log(log)
eq(p['errors'], {'Lua Script Error: [Scripts Interface] | data/scripts/chaos/x.lua:callback | '
                 'data/scripts/chaos/x.lua:5: attempt to index a nil value': 2,
                 '[Error - mysql_real_query] Query: SELECT 1': 1}, 'errors grouped as chaos-ctl errors')
eq(list(p['warnings'].values()), [1], 'a warning')
eq([a['rule'] for a in p['anomalies']], ['hit taken over 3x max health'], 'the anomaly line (a broken one skipped)')
eq(p['anomalies'][0]['line'], 9, 'with its line')
eq(p['events'][0]['kind'], 'death', 'the death event')
run = {'started': 'a', 'ended': 'b', 'bots': 3, 'logins': 4, 'deaths': 1,
       'behaviours': {'shop': {'tried': 2, 'ok': 1, 'failed': 1}},
       'failures': {'exhausted': 9, 'cannot use object': 2}, 'lua_errors': {'x.lua:5: boom': 1},
       'kicks': {'You have been idle': 1},
       'anomalies': [{'rule': 'death within one hit from full health', 'who': 'Tester Abd'}],
       'first': {'fail:cannot use object': {'bot': 'Tester Abd', 'did': 'depot'},
                 'lua:x.lua:5: boom': {'bot': 'Tester Abe', 'did': 'opcodes'}},
       'coverage': {'autoloot': {'tried': 3, 'ok': 3, 'errors': 0}, 'arena': {'why': 'needs two parties'},
                    'bazaar': {'why': 'out of scope: trades with real players'},
                    'charms': {'tried': 29, 'ok': 0, 'errors': 0},
                    'veiled': {'tried': 4, 'ok': 0, 'errors': 0, 'refused': 2}}}
r = TC.build_report(run, p)
for want in ('2x Lua Script Error', 'Anomalies (2)', 'hit taken over 3x max health', '9x exhausted (expected in play)',
             '2x cannot use object (first: Tester Abd after depot)', '1x x.lua:5: boom (first: Tester Abe after opcodes)',
             '1x You have been idle', 'shop', 'never reached: needs two parties'):
    ok(want in r, 'the report has %r' % want)
ok('autoloot' not in r, 'fine systems are not listed')
ok('no answer, no error: charms' in r, 'sent but never answered: one line')
ok('veiled' in r and 'veiled' not in r.split('no answer, no error:')[1], 'a refused system keeps its own line')
ok('never reached: out of scope: trades with real players: bazaar' in r, 'out of scope systems share one line per reason')
ok('charms' in r and '(1 systems fine: not listed)' in r, 'a system never ok is; the count')

# a monster named "Terror Bird" is no error; the bots' own records stay out of the error list; a guard warning keeps
# its stack traceback; the deaths the server logged, by killer, beside the bots' own count
p2 = TC.parse_log([
    '[tester-event] {"kind":"death","who":"Tester Aad","level":30,"killer":"Terror Bird"}',
    '[tester-event] {"kind":"death","who":"Tester Aas","level":30,"killer":"Terror Bird"}',
    '[2026-10-22 21:00:00] [Warning - Chaos] Position:sendMagicEffect with effect nil refused',
    'stack traceback:',
    '\t[C]: in function \'sendMagicEffect\'',
    '\tdata/scripts/chaos/raid.lua:907: in function \'fxAt\'',
    '\tdata/scripts/chaos/raid.lua:950: in function <x>',
    'Loading map done',
    '> Warning: run as root',
    'Server online',
])
eq(p2['errors'], {}, 'no error in death records of a "Terror" monster')
eq(len(p2['events']), 2, 'both deaths are events')
ok(any('raid.lua:907' in w for w in p2['warnings']), 'the warning keeps its traceback')
ok(not any('raid.lua:950' in w for w in p2['warnings']), 'three lines of it')
ok('> Warning: run as root' in p2['warnings'], 'a warning without a traceback stands alone')
eq(TC.is_error('[Error - mysql_real_query] x'), True, 'Error is an error')
eq(TC.is_error('Terror Bird killed Tester Aad'), False, 'Terror is not')
r2 = TC.build_report({'deaths': 9}, p2)
ok('== Deaths on the server (2; the bots counted 9)' in r2, 'server deaths beside the bots count')
ok('by killer: Terror Bird 2' in r2 and 'by tester: Tester Aad 1, Tester Aas 1' in r2, 'deaths by killer and tester')

# ---------------------------------------------------------------- names, accounts, the key file
eq([T.tester_name(i) for i in (0, 1, 26, 150)], ['Tester Aaa', 'Tester Aab', 'Tester Aba', 'Tester Afu'], 'names')
ok(all(T.safe_name(T.tester_name(i)) for i in range(T.TC.MAX_BOTS * 3)), 'every generated name fits the pattern')
ok(T.safe_account(T.new_account_name()) and T.new_account_name() != T.new_account_name(), 'random account names')
ok(not T.safe_account('tstbot') and not T.safe_account('tstbot0123456789x') and not T.safe_account("tstbot' OR 1"),
   'account name pattern')
ok(not T.safe_name("Tester A'b") and not T.safe_name('Ana'), 'name pattern')
eq(T.dev_key_allowed('clientGuardAllowDevKey = true\n'), True, 'dev key on')
eq(T.dev_key_allowed('-- clientGuardAllowDevKey = true\nclientGuardAllowDevKey = false\n'), False, 'dev key off')
eq(T.dev_key_allowed(''), False, 'no setting')
eq(T.binds_only_global('bindOnlyGlobalAddress = true'), True, 'bind only global')

# the client build the bots announce (the engine's ClientGuard::gateReason refuses a build below min_package)
MAN = '{"payload": "{\\"version\\": 9, \\"min_package\\": 16, \\"files\\": []}", "signature": "ab"}'
eq(T.manifest_floor(MAN), 16, 'min_package inside the escaped payload')
eq(T.manifest_floor('{"min_package": 3}'), 3, 'plain min_package')
eq(T.manifest_floor('{}'), None, 'no min_package')
reader = lambda path: {'/m.json': MAN}[path]  # noqa: E731
eq(T.guard_build('', reader), 1, 'no guard settings: build 1')
eq(T.guard_build('clientGuardManifest = "/m.json"\n', reader), 16, 'the manifest floor')
eq(T.guard_build('-- clientGuardManifest = "/m.json"\n', reader), 1, 'a comment is no setting')
eq(T.guard_build('clientGuardManifest = "/missing.json"\n', lambda p: open(p).read()), 1, 'unreadable manifest: build 1')
eq(T.guard_build('clientGuardBuilds = "14, 15,17"\nclientGuardManifest = "/m.json"\n', reader), 17,
   'the newest listed build at or above the floor')
eq(T.guard_build('clientGuardBuilds = "12 13"\n', reader), 13, 'the newest listed build')
eq(T.guard_build('clientGuardManifest = os.getenv("X") or ""\n', reader), 1, 'an expression is no path')

# the login key: rsaKeyFile as the engine reads it (patch 0046), not always key.pem
PROD = 'rsaKeyFile = os.getenv("CHAOS_RSA_KEY_FILE") or "key.pem"\n'
eq(T.login_key_file('', '/srv', {}), ('/srv/key.pem', False), 'no setting: key.pem of the server folder')
eq(T.login_key_file(PROD, '/srv', {'CHAOS_RSA_KEY_FILE': '/etc/chaos/rsa/login.pem'}),
   ('/etc/chaos/rsa/login.pem', True), 'the chaos.env key')
eq(T.login_key_file(PROD, '/srv', {'CHAOS_RSA_KEY_FILE': ' /k/new.pem , /k/old.pem'}), ('/k/new.pem', True),
   'a rotation: the first key')
eq(T.login_key_file(PROD, '/srv', {'CHAOS_RSA_KEY_FILE': ''}), ('/srv/key.pem', False), 'empty env: key.pem')
eq(T.login_key_file(PROD, '/srv', {}), ('/srv/key.pem', False), 'no env: key.pem')
eq(T.login_key_file('rsaKeyFile = "keys/a.pem"\n', '/srv', {}), ('/srv/keys/a.pem', True), 'a relative path')
eq(T.login_key_file('-- rsaKeyFile = "/x.pem"\n', '/srv', {}), ('/srv/key.pem', False), 'a comment is no setting')

tmp = tempfile.mkdtemp()
key = os.path.join(tmp, 'key')


def key_error(text, mode=0o600):
    with open(key, 'w') as f:
        f.write(text)
    os.chmod(key, mode)
    try:
        T.read_key_file(key)
    except SystemExit as e:
        return str(e)
    return None


eq(key_error('ab' * 32), None, 'a 64 hex key in a 0600 file')
ok('group or others' in key_error('ab' * 32, 0o644), 'a readable file is refused')
ok('not 64 hex' in key_error('abc'), 'a short key is refused')
ok('development key' in key_error(LT.GUARD_DEV_KEY.hex()), 'the dev key is refused')
try:
    T.read_key_file(os.path.join(tmp, 'none'))
    eq(True, False, 'a missing key file is refused')
except SystemExit as e:
    ok('README' in str(e), 'a missing key file points to the README')
for flag in ('--client-key', '--dev-key'):
    try:
        T.parse(['run', flag, 'ab' * 32])
        eq(True, False, '%s is refused' % flag)
    except SystemExit as e:
        ok('never the command line' in str(e), '%s: the key never on the command line' % flag)
try:
    T.parse(['run', '--server-dir', tmp])
    eq(True, False, 'run needs --key-file')
except SystemExit as e:
    ok('--key-file' in str(e), 'run needs --key-file')

# ---------------------------------------------------------------- password hashes: salted PBKDF2 only
h = T.pbkdf2_hash('pw', 1000)
ok(h.startswith('pbkdf2-sha256$1000$'), 'a tester password is PBKDF2')
ok(h != T.pbkdf2_hash('pw', 1000), 'with its own salt')
try:
    T.parse(['setup', '--server-dir', '/x', '--hash-iterations', '0'])
    ok(False, '--hash-iterations 0 is refused')
except SystemExit as e:
    ok('SHA-1' in str(e), '--hash-iterations 0 is refused')

# ---------------------------------------------------------------- setup rows
bot = {'account': 'tstbot0123456789', 'password': 'x', 'name': 'Tester Aaa', 'vocation': 4, 'level': 100, 'hp': 900,
       'mana': 400, 'ml': 9, 'skill': 70, 'town': 1, 'pos': [100, 200, 7]}
st = T.setup_statements([bot], lambda b: 'HASH')
ok("VALUES ('tstbot0123456789', 'HASH', '', 1)" in st[0], 'the account: type 1 (a player)')
ok("SELECT 'Tester Aaa', `id`, 1, 4, 100" in st[1], 'the character: group 1 (a player), never staff')
ok("SELECT `id`, 7102900, 1 FROM `players` WHERE `name` = 'Tester Aaa'" in st[2], 'the tester storage')
eq(len(st), 6, 'account, character, marker and hunt spot rows')
try:
    T.setup_statements([dict(bot, name="Tester A'a")], lambda b: 'HASH')
    eq(True, False, 'a bad name never reaches SQL')
except AssertionError:
    pass

# ---------------------------------------------------------------- cleanup: exact ids of testers only
cand = [
    ('10', 'Tester Aaa', '5', 'tstbot0123456789', '1'),   # a tester
    ('11', 'Tester Aab', '6', 'tstbotabcdefabcd', '1'),   # a tester the state lost (orphan)
    ('12', 'Tester Aac', '7', 'realplayer', '1'),         # storage and name, a real account: kept
    ('13', 'Ana', '8', 'tstbot0123456788', '1'),          # a real name: kept
    ('14', 'Tester Aad', '9', 'tstbot0123456787', '0'),   # no marker: kept
]
players, accounts = T.cleanup_targets([], cand)
eq(sorted(players), [10, 11], 'only rows that pass every rule')
eq(sorted(accounts), [5, 6], 'their accounts')
stmts = T.cleanup_statements([('player_deaths', 'player_id'), ('chaos_bank', 'account_id'),
                              ('chaos_x', 'buyer_account_id'), ('chaos_y', 'gift_player_id'), ('bad`t', 'player_id'),
                              ('chaos_z', 'player_name')], players, accounts, True)
eq(stmts[0], 'DELETE FROM `player_deaths` WHERE `player_id` IN (10,11);', 'child rows by player id')
eq(stmts[1], 'DELETE FROM `chaos_bank` WHERE `account_id` IN (5,6);', 'child rows by account id')
eq(stmts[2], 'DELETE FROM `chaos_x` WHERE `buyer_account_id` IN (5,6);', 'an *_account_id column')
eq(stmts[3], 'DELETE FROM `chaos_y` WHERE `gift_player_id` IN (10,11);', 'a *_player_id column')
ok(not any('bad' in x or 'player_name' in x for x in stmts), 'odd table or column names are skipped')
ok('UPDATE `houses` SET `owner` = 0 WHERE `owner` IN (10,11);' in stmts, 'a house of a tester goes back')
ok(any(x.startswith('UPDATE `houses` SET `bid` = 0') and 'WHERE `highest_bidder` IN (10,11)' in x for x in stmts),
   'a bid of a tester is dropped, the owner of that house kept')
eq(stmts[-2], 'DELETE FROM `players` WHERE `id` IN (10,11);', 'the characters')
ok(stmts[-1].startswith('DELETE FROM `accounts` WHERE `id` IN (5,6) AND NOT EXISTS'), 'the accounts, when empty')
ok(not any('LIKE' in x for x in stmts), 'no LIKE in the cleanup')
eq(T.cleanup_statements([], set(), set())[0], 'DELETE FROM `players` WHERE `id` IN (NULL);', 'nothing: deletes nothing')

# ---------------------------------------------------------------- the private state file
sp = os.path.join(tmp, 'state')
T.save_state(sp, {'bots': [bot]})
eq(oct(os.stat(T.state_path(sp)).st_mode & 0o777), '0o600', 'state.json is 0600')
eq(T.load_state(sp)['bots'][0]['name'], 'Tester Aaa', 'the state reads back')
eq(T.load_state(os.path.join(tmp, 'nothing')), {'bots': []}, 'no state: no bots')

# ---------------------------------------------------------------- what a bot reads
shop = (b'\x7a' + LT.string('Ulla') + struct.pack('<H', 2) + struct.pack('<HB', 7876, 0) + LT.string('health potion')
        + struct.pack('<III', 50, 45, 0) + struct.pack('<HB', 3000, 1) + LT.string('rope') + struct.pack('<III', 100, 0, 8))
items = T.parse_shop(b'\x10' + shop + b'\x00', 'Ulla')
eq([(i['id'], i['name'], i['buy'], i['sell']) for i in items], [(7876, 'health potion', 45, 0), (3000, 'rope', 0, 8)],
   'the NPC trade window')
eq(T.parse_shop(shop, 'Other'), None, 'another NPC')
payload = json.dumps({'action': 'kill', 'data': {'k': 3, 'items': [{'id': 1, 'n': 1}]}})
eq(T.extended_messages(b'\x32\xee' + LT.string(payload)), [(0xee, payload)], 'an extended opcode message')


class A:
    host = '10.0.0.1'
    ops = {'lootfilter': 238}
    after_login = ''
    on_answer = None


res = T.Results(1)
b = T.TesterBot(0, dict(bot), A(), 1, res, {'rotation': [], 'heal': None})
b.cid = 0x10000001
b.read(b'\x8c' + struct.pack('<I', b.cid) + b'\x64')
eq(b.health, 100, 'health from the creature health packet')
b.read(b'\x28\x00')
eq(res.d['deaths'], 1, 'the death window counts a death')
eq(res.d['anomalies'][0]['rule'], 'death within one hit from full health', 'dead from full health')
b.read(b'\xb4\x16' + LT.string('You are dead.'))

# a death at once after the login, health never seen: no anomaly (the first run filed 500 of them)
res0 = T.Results(1)
b0 = T.TesterBot(5, dict(bot), A(), 1, res0, {'rotation': [], 'heal': None})
b0.read(b'\x28\x00')
eq(res0.d['anomalies'], [], 'dead one second after the login: no anomaly from the bot (the helper has the exact rule)')
eq(len(b0.deaths_at), 1, 'the death time is kept')
b0.after_death = True
eq(round(TC.death_rest(b0.deaths_at, _time.monotonic())), 20, 'and the rest it asks for')

# the bot learns its own creature id from the helper's info (the login answer may come after the guard's challenge)
b2 = T.TesterBot(1, dict(bot), A(), 1, res, {'rotation': [], 'heal': None})
eq(b2.cid, 0, 'no creature id before the info')
b2.on_text('[tester-helper] info {"cid":268435999,"level":30}')
eq((b2.cid, T.ONLINE.get(268435999)), (268435999, b2), 'the creature id from the info, online under it')
b2.read(b'\x8c' + struct.pack('<I', 268435999) + b'\x37')
eq(b2.health, 55, 'and its health packets are read')
T.ONLINE.pop(268435999, None)
eq(res.d['deaths'], 1, 'the death text after the window is the same death')
b.on_extended(238, payload)
eq(b.kills[0]['k'], 3, 'a loot filter kill is kept for a take')
b.on_extended(238, 'S{"action":"kill","data":')
b.on_extended(238, 'E{"k":4,"items":[{"id":2}]}}')
eq(b.kills[-1]['k'], 4, 'a chunked message is joined')
b.read(b'\xb4\x16' + LT.string('You gained -50 experience points.'))
eq(res.d['anomalies'][-1]['rule'], 'negative experience gain', 'negative xp seen by a bot')
b.read(b'\xb4\x16' + LT.string('You cannot use this object.'))
eq(res.d['failures'], {'cannot use object': 1}, 'a failure text counted')
eq(res.d['first']['fail:cannot use object']['bot'], 'Tester Aaa', 'with its first bot')
eq(b.source, None, 'no loopback source address for another host')
A.host = '127.0.0.1'
eq(T.TesterBot(260, dict(bot), A(), 1, res, {'rotation': [], 'heal': None}).source, '127.1.2.11', 'its own 127.1.x.y')

# ---------------------------------------------------------------- keep alive: heal, potion, flee
class C:
    def __init__(self):
        self.sent = []

    def send(self, data):
        self.sent.append(data)


heal = {'words': 'exura x', 'group': 'healing', 'cooldown': 1000, 'groupcooldown': 1000}
hit = {'words': 'exori x', 'group': 'attack', 'cooldown': 2000, 'groupcooldown': 2000}
r3 = T.Results(1)
k = T.TesterBot(2, dict(bot), A(), 1, r3, {'rotation': [hit], 'heal': heal})
k.conn, k.cid = C(), 0x10000002
k.helper['info'] = {'potions': {'health': 266}}
said = []
k.say = lambda text, kind=1: said.append(text)
k.read(b'\x8c' + struct.pack('<I', k.cid) + b'\x23')  # 35 %
k.keep_alive(100.0)
eq(said, ['exura x'], 'under 50 %: the heal, no attack spell (mana for the heal)')
eq(len(k.conn.sent), 1, 'under 40 %: a potion')
eq(sorted(k.pending), ['heal_spell', 'potion'], 'both wait for a health rise')
k.read(b'\x8c' + struct.pack('<I', k.cid) + b'\x41')  # 65 %
eq((r3.d['behaviours']['heal_spell']['ok'], r3.d['behaviours']['potion']['ok']), (1, 1), 'the rise counts both ok')
eq(k.pending, {}, 'nothing pending after it')
k.keep_alive(100.5)
eq(said[-1], 'exori x', 'over 50 %: the rotation')
k.read(b'\x8c' + struct.pack('<I', k.cid) + b'\x0f')  # 15 %
k.keep_alive(100.6)
eq(said[-1], '!tester town', 'at 15 % with the heal and the potion on cooldown: flee to the temple')
eq(r3.d['behaviours']['flee']['tried'], 1, 'a flee counted')
k.keep_alive(101.2)
eq(said[-1], 'exura x', 'the heal again once its cooldown is over')
k.keep_alive(104.5)
eq(r3.d['behaviours']['heal_spell']['failed'], 1, 'no rise within 3 seconds: the heal failed')
k.keep_alive(115.7)
eq('!tester hunt' in said, True, 'back to the hunt after the rest')
eq(said.count('!tester town'), 1, 'one flee a minute')

# the shop failure says whether the NPC answered at all (a creature speak packet with its name)
k.shop_npc, k.npc_spoke = 'Material Broker', False
k.read(b'\x61' + LT.string('Material Broker'))
eq(k.npc_spoke, False, 'its name in a creature update is no answer')
k.read(b'\xaa' + struct.pack('<I', 7) + LT.string('Material Broker') + b'\x0c' + LT.string('Ore, herbs...'))
eq(k.npc_spoke, True, 'its speech is an answer')
k.shop_npc = None

# ---------------------------------------------------------------- first live run: what is expected in play (O262)
import asyncio  # noqa: E402
r5 = T.Results(1)
q = T.TesterBot(3, dict(bot), A(), 1, r5, {'rotation': [], 'heal': heal})
q.conn, q.cid = C(), 0x10000003
q.pending = {'heal_spell': 1e12, 'potion': 1e12 + 1}
q.on_text('You do not have enough mana.')
eq(sorted(q.pending), ['potion'], 'no mana: the heal spell was not cast, the potion still waits')
eq(r5.d['behaviours']['heal_spell']['expected'], 1, 'the heal spell: expected, not failed')
q.on_text('You are exhausted.')
eq(q.pending, {}, 'exhausted: the newest pending one was not used')
eq(r5.d['behaviours']['potion']['expected'], 1, 'the potion: expected')
q.pending = {'heal_spell': 1e12, 'potion': 1e12}
q.on_death()
eq((r5.d['behaviours']['heal_spell']['expected'], r5.d['behaviours']['potion']['expected']), (2, 2),
   'dead before the heal or the potion could work: expected')
q.died = False
q.walk(2)
q.on_text('Sorry, not possible.')
eq(r5.d['failures'].get(T.WALKED_INTO), 1, 'a "not possible" after a blind walk is the step into an obstacle')
q.walk_until = 0.0
q.on_text('Sorry, not possible.')
eq(r5.d['failures'].get('not possible'), 1, 'any other "not possible" stays')
ok(T.WALKED_INTO in TC.EXPECTED and 'not enough room' in TC.EXPECTED, 'both are expected in play')
ok(T.ROOM_AFTER_BAG not in TC.EXPECTED, 'no room right after the bag was emptied is not')
q.on_text('There is not enough room.')
eq(q.room_fails, 1, 'a missing room is counted for the clean-up')
q.bag_at = __import__('time').monotonic()
q.on_text('There is not enough room.')
eq(r5.d['failures'].get(T.ROOM_AFTER_BAG), 1, 'right after the clean-up it is a finding')

# the bag clean-up asks the helper and resets the count; a dead bot's missing answer is not a failure
q.alive, q.died = True, False
q.say = lambda text, kind=1: said.append((text, kind))
q.helper['bag'] = {'removed': 3, 'topped': 1}


async def _says_q(command, kind, wait=4.0):
    return q.helper.get(kind)
q.helper_says = _says_q
q.room_fails = 5
eq(asyncio.run(q.tidy_bag()), True, 'the clean-up worked')
eq((q.room_fails, r5.d['behaviours']['bag']['ok']), (0, 1), 'and the count starts again')
q.helper = {}
q.died = True
eq(asyncio.run(q.tidy_bag()), False, 'the helper did not answer a dead bot')
eq(r5.d['behaviours']['bag']['expected'], 1, 'expected, not failed')
eq(r5.d['failures'].get('bag: no helper answer'), None, 'no failure counted for a dead bot')

# the shop: "hi" is a plain say; "trade" and "bye" go in the NPC channel (a focused NPC hears only that); amounts are bytes
q2 = T.TesterBot(4, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None})
q2.conn, q2.cid, q2.alive = C(), 0x10000004, True
q2.helper['shop'] = {'npc': 'Material Broker'}


async def _says_q2(command, kind, wait=4.0):
    return q2.helper.get(kind)
q2.helper_says = _says_q2
sleeps = []


async def _nap(t):
    sleeps.append(t)
    if len(sleeps) == 2:  # the window arrives after "trade"
        q2.shop = [{'id': 7618, 'sub': 0, 'name': 'health potion', 'buy': 45, 'sell': 0},
                   {'id': 2553, 'sub': 0, 'name': 'pick', 'buy': 0, 'sell': 10}]
T_sleep, T.asyncio.sleep = T.asyncio.sleep, _nap
try:
    random_state = T.random.getstate()
    T.random.seed(1)
    eq(asyncio.run(q2.do_shop({})), True, 'a shop visit with a trade window')
finally:
    T.asyncio.sleep = T_sleep
sent_ = q2.conn.sent
eq(sent_[0], b'\x96\x01' + LT.string('hi'), 'hi: a plain say')
eq(sent_[1], b'\x96\x0c' + LT.string('trade'), 'trade: in the NPC channel (TALKTYPE_PRIVATE_PN)')
eq(sent_[-1], b'\x96\x0c' + LT.string('bye'), 'bye: in the NPC channel')
buys = [m for m in sent_ if m[:1] == b'\x7a']
eq(buys, [b'\x7a' + struct.pack('<HBBBB', 7618, 0, 1, 0, 0)], 'the purchase: u16 id, sub type, u8 amount, two flags')
# the Loot Buyer without anything to buy: his answer is the right one
q3 = T.TesterBot(5, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None})
q3.conn, q3.cid, q3.alive = C(), 0x10000005, True
q3.helper['shop'] = {'npc': 'Loot Buyer'}


async def _says_q3(command, kind, wait=4.0):
    return q3.helper.get(kind)
q3.helper_says = _says_q3


async def _nap2(t):
    q3.nothing_to_sell = True
T.asyncio.sleep = _nap2
try:
    eq(asyncio.run(q3.do_shop({})), True, 'the Loot Buyer has nothing to buy of a tester: fine')
finally:
    T.asyncio.sleep = T_sleep
eq(q3.results.d['failures'], {T.SHOP_NOTHING: 1}, 'counted under its own (expected) key')
ok(T.SHOP_NOTHING in TC.EXPECTED, 'and it is expected in play')

# the pings of a session are sent by the guard task too (the engine logs out 60 s after the last one, no message)
q4 = T.TesterBot(6, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None})
q4.conn, q4.alive = C(), True


async def _guard_once():
    task = asyncio.ensure_future(q4.guard())
    await T_sleep(0.1)
    q4.alive = False
    await task
asyncio.run(_guard_once())
eq(q4.conn.sent[:1], [b'\x1E'], 'the guard pings while a long behaviour runs')

# ---------------------------------------------------------------- healing spells
spells = [{'words': 'heal a', 'group': 'healing', 'level': 10, 'needlearn': False, 'params': False, 'vocations': set()},
          {'words': 'heal b', 'group': 'healing', 'level': 50, 'needlearn': False, 'params': False,
           'vocations': {'Knight'}},
          {'words': 'heal c', 'group': 'healing', 'level': 80, 'needlearn': False, 'params': False, 'vocations': set()}]
eq(T.class_spells(spells, {}, 'Knight', 60)['heal']['words'], 'heal b', 'the best healing spell of the level')
eq(T.class_spells(spells, {}, 'Mystic', 60)['heal']['words'], 'heal a', 'of the class')

# ---------------------------------------------------------------- level bands
eq(T.LEVELS, (30, 100, 250, 500, 750, 1000, 1250, 1500, 1750, 2000), 'the level bands up to 2000')
eq(T.parse(['setup', '--server-dir', '/x']).levels, '30,100,250,500,750,1000,1250,1500,1750,2000',
   'setup: every band by default')
cls15 = [('C%d' % k, 1) for k in range(15)]
plan = T.plan_bots(100, cls15, list(T.LEVELS))
for lv in T.LEVELS:
    band = [c for c, l in plan if l == lv]
    eq(len(band), 10, 'band %d: 10 of 100 testers' % lv)
    ok(len(set(band)) == 10, 'band %d: 10 different classes' % lv)
eq(len({c for c, _ in plan}), 15, 'every class plays')
eq(T.plan_bots(3, [('A', 1)], [30, 100]), [('A', 30), ('A', 100), ('A', 30)], 'one class: the bands in turn')

# ---------------------------------------------------------------- the activity log of a run

_d = tempfile.mkdtemp()
_path = os.path.join(_d, 'runs', 'run-20261022-120000.log')
_r = T.Results(2, _path)


class _B:
    name, level, cls, last = 'Tester Aaa', 750, 'Knight', 'hunt'


_r.log(_B(), 'login', 'in game')
_r.behaviour('hunt', 'tried', _B())
_r.behaviour('hunt', 'ok', _B())
_r.count('lua_errors', 'Lua Script Error: boom', _B())
_r.anomaly('one_shot', _B(), health_before=100)
_r.close()
_lines = open(_path).read().splitlines()
eq(len(_lines), 4, 'activity: login, the outcome (not the try), the error, the anomaly')
ok('Tester Aaa (L750 Knight) login' in _lines[0] and _lines[0].endswith('in game'), 'who, level, class: ' + _lines[0])
ok(_lines[1].endswith('hunt ok'), 'the outcome: ' + _lines[1])
ok('LUAERROR' in _lines[2] and 'boom' in _lines[2], 'the error: ' + _lines[2])
ok('ANOMALY' in _lines[3] and 'one_shot while hunt' in _lines[3] and '"health_before": 100' in _lines[3], _lines[3])
eq(oct(os.stat(_path).st_mode & 0o777), '0o600', 'activity log: owner only')
eq(oct(os.stat(os.path.dirname(_path)).st_mode & 0o777), '0o700', 'runs/: owner only')
_runs = os.path.join(_d, 'runs')
for _k in range(5):
    for _n in ('run-2026102%d-100000.log' % _k, 'run-2026102%d-100000-report.txt' % _k):
        open(os.path.join(_runs, _n), 'w').close()
open(os.path.join(_runs, 'notes.txt'), 'w').close()
T.prune_runs(_runs, 2)
eq(sorted(os.listdir(_runs)), ['notes.txt', 'run-20261023-100000-report.txt', 'run-20261023-100000.log',
                               'run-20261024-100000-report.txt', 'run-20261024-100000.log'],
   'prune: the newest runs kept, other files untouched')
_r2 = T.Results(1)
_r2.log(_B(), 'login', 'x')  # no activity path: nothing written, no error
eq(T.Results(1).lines, 0, 'no activity log without a path')

# online: save_results writes the count of testers in game; status shows it only while the run keeps saving
_sd = tempfile.mkdtemp()
_a = T.Args()
_a.state = _sd
_res = T.Results(3)
T.ONLINE.clear()
T.ONLINE.update({1: 'a', 2: 'b'})
T.save_results(_a, _res)
T.ONLINE.pop(2)
T.save_results(_a, _res)
T.ONLINE.clear()


def _status():
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        T.status(_a)
    return dict(l.split('=', 1) for l in out.getvalue().splitlines())


_st = _status()
eq(_st['online'], '1', 'status: testers in game now')
eq(_st['online_peak'], '2', 'status: the peak of the run')
with open(os.path.join(_sd, 'run.json')) as _f:
    _j = json.load(_f)
_j['online_at'] = int(_time.time()) - T.ONLINE_FRESH - 5
T.write_private(os.path.join(_sd, 'run.json'), json.dumps(_j))
eq(_status()['online'], '0', 'status: a stale count (the run stopped saving) is 0')

# ---------------------------------------------------------------- placement and the death report (first live run, 2026-10-27)
POOL = 'return { hunt = {\n{name = "Rat", level = 5, exp = 1}, {name = "Terror Bird", level = 20, exp = 150},\n' \
       '{name = "Juggernaut", level = 284, exp = 1}, }, bosses = {{name = "Rat", level = 900}} }'
eq(LT.pool_levels(POOL), {'rat': 5, 'terror bird': 20, 'juggernaut': 284}, 'pool levels: the hunting part only')
SP = ('<spawn centerx="100" centery="100" centerz="7" radius="3">\n<monster name="Rat" x="1" y="1"/>\n</spawn>\n'
      '<spawn centerx="104" centery="100" centerz="7" radius="3">\n<monster name="Rat" x="1" y="1"/>'
      '<monster name="Terror Bird" x="2" y="2"/>\n</spawn>\n'
      '<spawn centerx="108" centery="100" centerz="7" radius="3">\n<monster name="Juggernaut" x="1" y="1"/>\n</spawn>\n'
      '<spawn centerx="112" centery="100" centerz="7" radius="3">\n<monster name="Nameless" x="1" y="1"/>\n</spawn>\n')
CL = LT.spawn_levels(SP, LT.pool_levels(POOL))
eq(CL, {(100, 100, 7): 10, (104, 100, 7): 40, (108, 100, 7): 568, (112, 100, 7): 10 ** 9},
   'a spawn centre counts at its highest monster, twice the pool level; an unknown monster never safe')
IDX = LT.spawn_index(SP)
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12, centre_levels=CL, max_level=30), (100, 100, 7),
   'level 30 passes the Terror Bird (40) and the Juggernaut: the quiet centre')
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12, centre_levels=CL, max_level=45), (104, 100, 7), 'level 45: the Terror Bird one')
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12), (108, 100, 7), 'no levels: the nearest, as before')
HUNTS2 = [(1, 10, 100, 100, 7), (20, 30, 108, 100, 7)]
pos = T.place_testers([30, 45], HUNTS2, [(50, 50, 7)], IDX, CL)
ok(all(CL.get(p, 10 ** 9) <= lv for p, lv in zip(pos, [30, 45])), 'no tester on a spawn above its level: %r' % pos)
eq(T.place_testers([30], HUNTS2, [(50, 50, 7)], LT.spawn_index('<spawn centerx="108" centery="100" centerz="7" radius="3">'),
                   {(108, 100, 7): 568}), [(50, 50, 7)], 'no safe spawn within reach: the temple')
eq(T.place_testers([30], [], [(50, 50, 7)])[0][2], 7, 'no hunting marks: round the temple')
dead = [{'kind': 'death', 'who': 'Tester Aaa', 'level': 30, 'killer': 'Wiggler', 'hits': 4, 'damage': 300, 'damagePct': 75,
         'biggest': 90, 'biggestPct': 22, 'online': 3},
        {'kind': 'death', 'who': 'Tester Aab', 'level': 30, 'killer': 'Wiggler', 'hits': 1, 'damage': 700, 'damagePct': 140,
         'biggest': 700, 'biggestPct': 140, 'online': 90}]
rd = TC.build_report({'deaths': 2}, {'errors': {}, 'warnings': {}, 'anomalies': [], 'events': dead, 'first': {}})
ok('2 records' in rd and '1 deaths by one hit of 100% or more, 1 within 5 s of the login' in rd, 'the death record line: ' + rd[:700])

# the keystone scenario of a bot goes on after a death: results reach the run's results once, with the reason for the rest
resk = T.Results(1)
bk = T.TesterBot(7, dict(bot), A(), 1, resk, {'rotation': [], 'heal': None})
bk.keytest = T.TK.KeyTest({'classes': {'thief': [{'id': 1, 'kind': 'keystone', 'flag': 'ksX', 'path': []}]}}, bk.name, 0)
bk.flush_keytest()
eq(resk.d.get('keytest'), None, 'a KeyTest that is not through is not flushed without a reason')
bk.flush_keytest('the run ended')
eq([r['status'] for r in resk.d['keytest']], ['not tested'], 'flushed at the end of the run: not tested, with the reason')
bk.flush_keytest('again')
eq(len(resk.d['keytest']), 1, 'and only once')

for f in FAILS:
    print('FAIL ' + f)
print('testers_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)

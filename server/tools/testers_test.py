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
import shutil
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

# where a tester hunts: the whole band (the marks print hunting levels since 2026-10-27) at or under the level
HUNTS = [(1, 20, 1, 1, 7), (20, 40, 2, 2, 7), (40, 60, 3, 3, 7), (40, 180, 4, 4, 7), (80, 120, 5, 5, 7), (1, 40, 6, 6, 7)]
eq([h[:2] for h in TC.safe_hunts(HUNTS, 30)], [(1, 20)], 'level 30: bands up to 30 (not 20-40, not 40-180)')
eq([h[:2] for h in TC.safe_hunts(HUNTS, 45)], [(20, 40), (1, 40)], 'level 45: bands up to 45, the highest ones')
eq([h[:2] for h in TC.safe_hunts(HUNTS, 100)], [(40, 60)], 'level 100: up to 100, the highest top')
eq([h[:2] for h in TC.safe_hunts(HUNTS, 4)], [(1, 20)], 'nothing that low: the lowest band')
eq(all(h[1] <= 45 for h in TC.safe_hunts(HUNTS, 45)), True, 'never a band over the level (no second doubling)')

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
ok(', 3000, 1, 100, 200, 7' in st[1], 'O656: a bot with no cap keeps the old 3000')
st2 = T.setup_statements([dict(bot, cap=17970 + 92 * 25)], lambda b: 'HASH')
ok(', 20270, 1, 100, 200, 7' in st2[1], 'O656: the capacity of the bot is the real one of its level (17970 + gaincap a level)')
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

# a tester still in game is kicked (and saved) before its rows go: a deleted `players` row makes the engine's save fail
eq(T.kick_lines(['Tester Aab', "Tester A'a", 'Ana', 'Tester Aaa', 'Tester Aab']), ['kick Tester Aaa', 'kick Tester Aab'],
   'only exact tester names, once, sorted')
eq(T.kick_online('', ['Tester Aaa'], 0), 0, 'no server folder: nothing written')
with tempfile.TemporaryDirectory() as d:
    eq(T.kick_online(d, ['Tester Aaa', 'Ana'], 0), 1, 'one kick queued')
    with open(os.path.join(d, 'remote.cmd')) as f:
        eq(f.read(), 'kick Tester Aaa\n', 'remote.cmd line')
    eq(T.kick_online(d, [], 0), 0, 'no names: nothing')

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
# -1 as u32 is no price: not bought / not sold; flagged so the visit reports the unpatched server
shop2 = (b'\x7a' + LT.string('Ulla') + struct.pack('<H', 2) + struct.pack('<HB', 2553, 0) + LT.string('pick')
         + struct.pack('<III', 50, 50, 0xFFFFFFFF) + struct.pack('<HB', 3000, 0) + LT.string('rope') + struct.pack('<III', 100, 0xFFFFFFFF, 8))
items2 = T.parse_shop(shop2, 'Ulla')
eq([(i['buy'], i['sell'], i['unset']) for i in items2], [(50, 0, True), (0, 8, True)], '4294967295 is no price')
eq([i['unset'] for i in items], [False, False], 'a clean window is not flagged')
payload = json.dumps({'action': 'kill', 'data': {'k': 3, 'items': [{'id': 1, 'n': 1}]}})
eq(T.extended_messages(b'\x32\xee' + LT.string(payload)), [(0xee, payload)], 'an extended opcode message')
# O661: a 0x32 byte that ends a map update (an item id) right before a real message must not swallow its header
res = json.dumps({'action': 'result', 'data': {'ok': True, 'text': 'Ashen Throne placed.'}})
eq(T.extended_messages(b'\x6a\x10\x00\x20\x00\x07\x01\x55\x32' + b'\x32\xc0' + LT.string(res)), [(0xc0, res)],
   'a real extended message right after a stray 0x32 byte is found')
eq(T.extended_messages(b'\x32\x32\x32\xc0' + LT.string(res)), [(0xc0, res)], 'two stray 0x32 bytes before it')
two = json.dumps({'action': 'state', 'data': {'n': 2}})
eq(T.extended_messages(b'\x32\xc0' + LT.string(res) + b'\x32\xc0' + LT.string(two)), [(0xc0, res), (0xc0, two)], 'two messages in one packet')
eq(T.extended_messages(b'\x32\xc0\xff\x7f{'), [], 'a header whose length runs past the packet is no message')


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
eq((q.room_fails, r5.d['behaviours']['bag']['ok']), (5, 1), 'the look does not clear the count of missing room: only a keep round does (O584)')
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
eq(q2.results.d['failures'], {}, 'a clean window: no failure')
buys = [m for m in sent_ if m[:1] == b'\x7a']
eq(buys, [b'\x7a' + struct.pack('<HBBBB', 7618, 0, 1, 0, 0)], 'the purchase: u16 id, sub type, u8 amount, two flags')
# an unpatched server (prices -1 as 4294967295): no purchase of a sell-only item, no sale of a buy-only one, one failure
q2b = T.TesterBot(7, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None})
q2b.conn, q2b.cid, q2b.alive = C(), 0x10000007, True
q2b.helper['shop'] = {'npc': 'Loot Buyer'}


async def _says_q2b(command, kind, wait=4.0):
    return q2b.helper.get(kind)
q2b.helper_says = _says_q2b
naps = []


async def _nap3(t):
    naps.append(t)
    if len(naps) == 2:
        q2b.shop = T.parse_shop(b'\x7a' + LT.string('Loot Buyer') + struct.pack('<H', 1) + struct.pack('<HB', 3000, 0)
                                + LT.string('rope') + struct.pack('<III', 100, 0xFFFFFFFF, 8), 'Loot Buyer')
T.asyncio.sleep = _nap3
try:
    asyncio.run(q2b.do_shop({}))
finally:
    T.asyncio.sleep = T_sleep
eq([m for m in q2b.conn.sent if m[:1] == b'\x7a'], [], 'no purchase of an item with no buy price')
eq(q2b.results.d['failures'], {T.SHOP_UNSET: 1}, 'the unpatched window is one failure')
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
eq(CL, {(100, 100, 7): 5, (104, 100, 7): 20, (108, 100, 7): 284, (112, 100, 7): 10 ** 9},
   'a spawn centre counts at its highest monster, the pool level (baseLevelMult 1); an unknown monster never safe')
eq(LT.base_level_mult(), 1, 'baseLevelMult read from pace_config.lua (1 since 2026-10-28, O285)')
eq(LT.spawn_levels(SP, LT.pool_levels(POOL), 3)[(104, 100, 7)], 60, 'the multiplier is a parameter')
WCFG = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'scripts', 'chaos',
                         'waystone_tiers_config.lua')).read()
WA = LT.waystone_areas(WCFG)
eq(len(WA), 12, 'the twelve waystone tier maps of waystone_tiers_config.lua')
ok((33124, 33376, 33395, 33582, 7) in WA, 'a map rect as (x1, y1, x2, y2, z): %r' % WA[-1:])
eq(LT.spawn_levels(SP, LT.pool_levels(POOL), blocked=[(103, 99, 105, 101, 7)])[(104, 100, 7)], 10 ** 9,
   'a centre inside a waystone map is never safe (its monsters count at the run tier, 1100+; live run 2026-11-01)')
eq(LT.spawn_levels(SP, LT.pool_levels(POOL), blocked=[(103, 99, 105, 101, 8)])[(104, 100, 7)], 20, 'another floor: as before')
IDX = LT.spawn_index(SP)
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12, centre_levels=CL, max_level=15), (100, 100, 7),
   'level 15 passes the Terror Bird (20) and the Juggernaut (284): the quiet centre')
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12, centre_levels=CL, max_level=30), (104, 100, 7), 'level 30: the Terror Bird one')
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12), (108, 100, 7), 'no levels: the nearest, as before')
eq(LT.snap_to_spawn((107, 100, 7), IDX, reach=12, centre_levels=CL, max_level=30, clear=6), (100, 100, 7),
   'level 30, clear 6: the Terror Bird centre has the Juggernaut spawn 4 sqm away, so the Rat one (8 away from it)')
eq(LT.snap_to_spawn((101, 100, 7), IDX, reach=3, centre_levels=CL, max_level=30, clear=3), (100, 100, 7), 'a quiet corner passes the clearance')
HUNTS2 = [(1, 10, 100, 100, 7), (20, 30, 108, 100, 7)]
pos = T.place_testers([15, 30], HUNTS2, [(50, 50, 7)], IDX, CL)
ok(all(CL.get(p, 0) <= lv for p, lv in zip(pos, [15, 30])), 'no tester on a spawn above its level: %r' % pos)
eq(pos[1], (50, 50, 7), 'level 30: the Terror Bird centre has the Juggernaut spawn 4 sqm off, so the temple')
eq(T.place_testers([30], HUNTS2, [(50, 50, 7)], LT.spawn_index('<spawn centerx="108" centery="100" centerz="7" radius="3">'),
                   {(108, 100, 7): 284}), [(50, 50, 7)], 'no safe spawn within reach: the temple')
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

# --checks (O110, tester_checks.py): the flag, the BUG line in the report, the waiter wildcard, the checks flush
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k', '--checks']).checks, True, '--checks is a flag')
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k']).checks, False, 'off by default')
rc = TC.build_report({'checks': [{'check': 'beastmaster_wolf', 'bot': 'Tester Abc', 'class': 'Beastmaster', 'status': 'fail',
                                  'detail': 'war wolf #1 targets its owner'},
                                 {'check': 'pets', 'bot': 'Tester Abd', 'class': 'Ninja', 'status': 'skip', 'detail': 'the bot owns no pet'}]},
                     {'errors': {}, 'warnings': {}, 'anomalies': [], 'events': [], 'first': {}})
ok('BUG beastmaster_wolf: war wolf #1 targets its owner (Tester Abc, Beastmaster)' in rc, 'the report prints the BUG line')
ok('skip pets' in rc and '== System checks' in rc, 'and the skips with their reason')
resc = T.Results(1)
bc = T.TesterBot(8, dict(bot), A(), 1, resc, {'rotation': [], 'heal': None})
bc.checks = T.TX.CheckRun(bc.name, bc.cls, bc.level, only=['waystone'])
bc.flush_checks()
eq(resc.d.get('checks'), None, 'checks that are not through are not flushed')
bc.checks.done.add('waystone')
bc.checks.results.append(T.TX.Result('waystone', bc.name, bc.cls, T.TX.PASS, 'x'))
bc.flush_checks(); bc.flush_checks()
eq([r['status'] for r in resc.d['checks']], ['pass'], 'flushed once when through')
sp = T.load_check_spells(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'), {'Beastmaster': {'id': 15}, 'Ninja': {'id': 12}})
eq(sp.get(248, {}).get('name'), 'Wild Bond', 'load_check_spells: a Chaos spell by its spellid')
# a server folder without data/spells/stock_spells.csv (no install step copies it): the repo's table
_empty = tempfile.mkdtemp()
sp2 = T.load_check_spells(_empty, {'Ranger': {'id': 2}})
eq(sp2.get(111, {}).get('name'), 'Phantom Javelin', 'load_check_spells: a stock spell from the repo table when the server has none')
shutil.rmtree(_empty)
eq(sp.get(248, {}).get('vocations'), [15], 'its class')
ok(236 in sp and 12 in sp[236]['vocations'], 'Shuriken Toss is open to the Ninja')

# party partners: bots that start the party check together pick distinct free partners; leave frees both
class _PB:
    def __init__(self, cid, name):
        self.cid, self.name, self.alive, self.died = cid, name, True, False
T.ONLINE.clear(); T.PARTY_BUSY.clear()
_pbs = [_PB(i, 'P%d' % i) for i in (1, 2, 3, 4)]
T.ONLINE.update({b.cid: b for b in _pbs})
_ios = [T.CheckIO.__new__(T.CheckIO) for _ in _pbs]
for _io, _b in zip(_ios, _pbs):
    _io.bot, _io.clock = _b, {'stop': False}
_ios[1].formed = ('P1', 1, 2)
ok(_ios[1].partner_kept('P1'), 'partner_kept: both in game with the creature ids of the form')
_pbs[0].cid_was, _pbs[0].cid = _pbs[0].cid, 99
ok(not _ios[1].partner_kept('P1'), 'partner_kept: the partner logged in again (a new creature id)')
_pbs[0].cid = _pbs[0].cid_was
_pbs[0].died = True
ok(not _ios[1].partner_kept('P1'), 'partner_kept: the partner died')
_pbs[0].died = False
_wait = T.PARTNER_WAIT_S
T.PARTNER_WAIT_S = 0.0
_picks = [asyncio.run(_io.partner()) for _io in _ios]
eq(_picks, ['P2', None, 'P4', None], 'party partners: two pairs, nobody picked twice')
_snap = dict(T.PARTY_BUSY.until)


async def _freed_while_waiting():
    T.PARTY_BUSY.clear()
    T.PARTY_BUSY.update(('P1', 'P2', 'P3', 'P4'))
    T.PARTY_BUSY.discard('P1')
    asyncio.get_running_loop().call_later(0.1, T.release_party, 'P3')
    return await _ios[0].partner()

T.PARTNER_WAIT_S = 1.0
eq(asyncio.run(_freed_while_waiting()), 'P3', 'partner() waits for a bot that a party check frees (PARTNER_WAIT_S)')
T.PARTNER_WAIT_S = _wait
T.PARTY_BUSY.until = _snap
_ios[0].alive = lambda: False
eq(asyncio.run(_ios[0].party('leave', 'P2')), False, 'party leave of a dead bot sends nothing')
eq(sorted(T.PARTY_BUSY), ['P3', 'P4'], 'party leave frees both bots even when nothing was sent')
T.release_party('P3', 'P4')
eq(sorted(T.PARTY_BUSY), [], 'release_party frees the bots of a left party (called PARTY_RELEASE_S after a leave)')
_hold = T.PARTY_HOLD_S
T.PARTY_HOLD_S = -1.0
T.PARTY_BUSY.update(('P5', 'P6'))
ok('P5' not in T.PARTY_BUSY and list(T.PARTY_BUSY) == [], 'a busy name frees itself after PARTY_HOLD_S (a check cut off by a death)')
T.PARTY_HOLD_S = _hold
T.PARTY_BUSY.clear()
T.PARTY_BUSY.update(('P3', 'P4'))
_tb = T.TesterBot.__new__(T.TesterBot)
_tb.name, _stepped = 'P3', []
_tb.party_step = lambda: _stepped.append(1)
eq(asyncio.run(_tb.do_party(None)), False, 'a bot in a party check skips the random party behaviour')
_tb.name = 'P9'
eq((asyncio.run(_tb.do_party(None)), len(_stepped)), (True, 1), 'a free bot does its party step')
T.ONLINE.clear(); T.PARTY_BUSY.clear()

# ---------------------------------------------------------------- numbered helper commands (O579)
# live run 2026-11-15: 4 % of the helper commands read "no answer" on a busy server, and a late answer was taken for the answer of
# the next command of the same kind ("spawned chest is 'none'"). Every command now ends in " #N"; an answer carries N.
r6 = T.Results(1)
h = T.TesterBot(4, dict(bot), A(), 1, r6, {'rotation': [], 'heal': heal})
h.conn, h.alive, h.died = C(), True, False
said6 = []
h.say = lambda text, kind=1: said6.append(text)


async def _answered(delay, text):
    await asyncio.sleep(delay)
    h.on_text(text)


async def _ask(command, kind, wait, *answers):
    tasks = [asyncio.ensure_future(_answered(d, t)) for d, t in answers]
    r = await h.helper_says(command, kind, wait)
    for t in tasks:
        await t
    return r


r = asyncio.run(_ask('chest spawn', 'chest', 2.0, (0.1, '[tester-helper] chest {"seq":1,"state":"idle"}')))
eq((said6[-1], r and r.get('state')), ('!tester chest spawn #1', 'idle'), 'the command carries its number, the answer with it is taken')
# the answer of command 2 comes after its wait; command 3 of the same kind must not take it
r = asyncio.run(_ask('chest use', 'chest', 0.3))
eq((said6[-1], r), ('!tester chest use #2', None), 'no answer in time: None')
r = asyncio.run(_ask('chest state', 'chest', 2.0, (0.1, '[tester-helper] chest {"seq":2,"state":"none"}'),
                     (0.5, '[tester-helper] chest {"seq":3,"state":"running"}')))
eq((said6[-1], r and r.get('state')), ('!tester chest state #3', 'running'), 'a late answer (older number) is dropped, not read as the new one')
eq(r6.d['helper']['late'], 1, 'and counted')
eq(r6.d['helper']['lost'], 1, 'the missing answer is counted as lost')
eq(r6.d['helper']['answered'], 2, 'answers counted')
# an answer with no number (an old helper, a command typed without one) is taken as before
r = asyncio.run(_ask('town', 'town', 2.0, (0.1, '[tester-helper] town {"pos":{"x":1,"y":2,"z":7}}')))
eq(r and r.get('pos', {}).get('x'), 1, 'an answer without a number is taken')
# the helper's error answer for this command is the answer: a failed command is not "no answer"
r = asyncio.run(_ask('spellquest kill 3', 'spellquest', 2.0, (0.1, '[tester-helper] error {"seq":5,"err":"boom","cmd":"spellquest"}')))
eq(r and r.get('err'), 'boom', 'the error answer of this command comes back')
eq(r6.d['failures'].get('helper: boom'), 1, 'and is counted as a failure with its reason')
eq(h.helper.get('error'), None, 'taken once')
# the login answer ("info") has no number to match and is always kept
h.on_text('[tester-helper] info {"cid":77,"level":9,"seq":1,"potions":{}}')
eq(h.helper['info']['level'], 9, 'info is kept whatever its number')
rep6 = TC.build_report(r6.d, {'errors': {}, 'warnings': {}, 'events': [], 'anomalies': []})
ok('== Helper answers (' in rep6, 'the report has a helper answers line')
ok('1 late and dropped' in rep6 and 'slowest' in rep6, 'with the late answers and the slowest answer')

# ---------------------------------------------------------------- report v2 (O584 item 15)
W = TC.HUNT_WINDOW
eq(TC.hunt_outcome(100.0, None, None), 'expected', 'hunt: away from the hunt spot is not judged')
eq(TC.hunt_outcome(100.0, 50.0, None), 'expected', 'hunt: not there a window yet is not judged')
eq(TC.hunt_outcome(1000.0, 0.0, None), 'failed', 'hunt: a window at the spot and no experience is failed')
eq(TC.hunt_outcome(1000.0, 0.0, 950.0), 'ok', 'hunt: experience within the window is ok')
eq(TC.hunt_outcome(1000.0, 0.0, 100.0), 'failed', 'hunt: experience long ago is failed')
eq(TC.hunt_outcome(1000.0, 500.0, 400.0), 'failed', 'hunt: experience from before the return is not this hunt')
eq(TC.flee_outcome(30, 30, False, {'pos': {}}), ('ok', ''), 'flee: alive, health not lower, the helper answered')
eq(TC.flee_outcome(30, 20, False, {'pos': {}})[0], 'failed', 'flee: health fell')
eq(TC.flee_outcome(30, 30, True, {'pos': {}})[0], 'failed', 'flee: died')
eq(TC.flee_outcome(30, 30, False, None)[0], 'failed', 'flee: no helper answer')
eq(TC.flee_outcome(30, 30, False, {'err': 'x'})[0], 'failed', 'flee: the helper refused')

# a bot at its hunt: the experience message is progress, the hunt pick says so
rh = T.Results(1)
hb = T.TesterBot(6, dict(bot), A(), 1, rh, {'rotation': [], 'heal': None})
hb.alive, hb.died = True, False
hb.hunt_since = _time.monotonic() - 1000
eq(asyncio.run(hb.do_hunt(None)), False, 'a bot that gained nothing for a window fails its hunt')
ok(any('hunt: no experience' in k for k in rh.d['failures']), 'and the failure says so')
hb.on_text('You gained 120 experience points.')
hb.hunt_since = _time.monotonic() - 1000
eq(asyncio.run(hb.do_hunt(None)), True, 'experience since: the hunt is ok')
hb.hunt_since = _time.monotonic() - 3
eq(asyncio.run(hb.do_hunt(None)), None, 'just arrived: not judged')
hb.on_text('[tester-helper] town {"pos":{"x":1,"y":2,"z":7},"seq":0}')
eq(hb.hunt_since, None, 'the town answer ends the hunt stay')
hb.on_text('[tester-helper] hunt {"pos":{"x":1,"y":2,"z":7},"seq":0}')
ok(hb.hunt_since is not None, 'the hunt answer starts it')

# a flee is judged FLEE_LOOK seconds later; a death in between fails it
rf = T.Results(1)
fb = T.TesterBot(7, dict(bot), A(), 1, rf, {'rotation': [], 'heal': None})
fb.conn, fb.alive, fb.died, fb.cid = C(), True, False, 0
fb.say = lambda text, kind=1: None
fb.health, fb.heal = 20, None
fb.ready = {'heal': 9e9, 'potion': 9e9}
fb.keep_alive(1000.0)
eq(rf.d['behaviours']['flee']['tried'], 1, 'the flee is tried')
ok(fb.flee_check is not None, 'and waits to be judged')
fb.on_text('[tester-helper] town {"pos":{"x":1,"y":2,"z":7},"seq":0}')
fb.health = 25
fb.keep_alive(1000.0 + TC.FLEE_LOOK + 1)
eq(rf.d['behaviours']['flee'].get('ok'), 1, 'a flee that reached the temple alive counts ok (it read 0 before)')
fb.flee_check = (5000.0, 20)
fb.on_death()
eq(rf.d['behaviours']['flee'].get('failed'), 1, 'a death before the look fails the flee')
ok(any(k.startswith('flee: died') for k in rf.d['failures']), 'with its reason')

# the raid in closed test mode (O588): no flight to the temple inside it, the walk steps of a person, the loot, the party's level
class _W:
    async def drain(self):
        pass


class _CW(C):
    def __init__(self):
        super().__init__()
        self.w = _W()


rr = T.Results(1)
ri = T.TesterBot(8, dict(bot, name='Tester Rra'), A(), 1, rr, {'rotation': [], 'heal': None})
ri.conn, ri.alive, ri.died, ri.cid, ri.level = _CW(), True, False, 777, 900
said_r = []
ri.say = lambda text, kind=1: said_r.append(text)
ri.health, ri.heal = 20, None
ri.ready = {'heal': 9e9, 'potion': 9e9}
eq(ri.in_raid, False, 'a bot is not in the raid at first')
ri.in_raid = True
ri.keep_alive(1000.0)
ok('!tester town' not in said_r and ri.flee_check is None, 'inside the raid a bot does not flee to the temple (the engine catches a lethal hit)')
ri.in_raid = False
ri.keep_alive(1000.0)
ok('!tester town' in said_r, 'outside it, the flee at 20 percent is as before')
T.ONLINE.clear()
T.ONLINE[777] = ri
rio = T.CheckIO(ri, {'stop': False})
for step, byte in (((0, -1), 0x65), ((1, 0), 0x66), ((0, 1), 0x67), ((-1, 0), 0x68)):
    eq(asyncio.run(rio.step(*step)), True, 'step %s is sent' % (step,))
    eq(ri.conn.sent[-1], bytes([byte]), 'step %s is the client walk packet %#x' % (step, byte))
n_sent = len(ri.conn.sent)
eq(asyncio.run(rio.step(1, 1)), False, 'a diagonal is no step of ours')
eq(asyncio.run(rio.step_of('Tester Nobody', 1, 0)), False, 'a bot that is not in game takes no step')
eq(len(ri.conn.sent), n_sent, 'and nothing was sent')
ok(ri.walk_until > _time.monotonic(), 'a step marks the walk, so "not possible" is a blocked step and not a failure')
rio.raid_mode(['Tester Rra', 'Tester Nobody'], True)
eq((ri.in_raid, ri.stay), (True, True), 'raid_mode on: no flight, stays out of the walk back to the hunt')
rio.raid_mode(['Tester Rra'], False)
eq((ri.in_raid, ri.stay), (False, False), 'raid_mode off')
ri.kills = [{'k': 3, 'items': [{'n': 1, 'id': 2160}]}]
ri.args.ops = {'lootfilter': 41}
ri.args.backpack_client_id = 0
asyncio.run(rio.loot())
ok(any(m[:2] == b'\x32\x29' for m in ri.conn.sent), 'the loot step takes the items of the last kill through the loot filter window')
T.ONLINE.clear()
_lo, _hi = _PB(31, 'Tester Lo1'), _PB(32, 'Tester Hi1')
_lo.level, _hi.level = 30, 900
_me = _PB(30, 'Tester Me1')
T.ONLINE.update({b.cid: b for b in (_me, _lo, _hi)})
_pio = T.CheckIO.__new__(T.CheckIO)
_pio.bot, _pio.clock = _me, {'stop': False}
_wait2, T.PARTNER_WAIT_S = T.PARTNER_WAIT_S, 0.0
T.PARTY_BUSY.clear()
eq(asyncio.run(_pio.partner(min_level=800)), 'Tester Hi1', 'partner(min_level): a bot of the level, not the first free one')
T.PARTY_BUSY.clear()
eq(asyncio.run(_pio.partner(min_level=1500)), None, 'partner(min_level): nobody of that level, no partner')
T.PARTY_BUSY.clear()
eq(asyncio.run(_pio.partner()), 'Tester Lo1', 'partner(): the old rule, the first free bot')
T.PARTNER_WAIT_S = _wait2
T.ONLINE.clear(); T.PARTY_BUSY.clear()

# the proof table and the diff against the previous run
cov = {'bank': {'tried': 5, 'ok': 4, 'errors': 0, 'real': 2, 'ans': 2, 'help': 0, 'failed': 0, 'refused': 0},
       'rift': {'tried': 3, 'ok': 3, 'errors': 0, 'real': 0, 'ans': 0, 'help': 3, 'failed': 0, 'refused': 0},
       'charms': {'tried': 4, 'ok': 4, 'errors': 0, 'real': 0, 'ans': 4, 'help': 0, 'failed': 0, 'refused': 0},
       'daily': {'tried': 2, 'ok': 1, 'errors': 0, 'real': 0, 'ans': 0, 'help': 0, 'failed': 1, 'refused': 0}}
empty_log = {'errors': {}, 'warnings': {}, 'anomalies': [], 'events': [], 'first': {}}
run1 = {'logins': 100, 'deaths': 40, 'relogs': 2, 'reconnects': 0, 'coverage': cov, 'failures': {'depot: no locker': 5},
        'behaviours': {'hunt': {'tried': 500, 'ok': 400, 'failed': 50, 'expected': 50}},
        'effects': [{'effect': 'daily_claim_sets_day', 'step': 'calim', 'why': 'TakenReward is 0', 'bot': 'Tester Abc'}],
        'keep': {'sold_units': 9, 'sold_gold': 700, 'sell_visits': 3, 'equipped': 2, 'dropped': 1}}
rep1 = TC.build_report(run1, empty_log)
ok('== Proof by system' in rep1 and 'bank' in rep1.split('== Proof by system')[1], 'the proof table lists the systems reached')
ok('(4 systems reached: 1 with REAL proof, 1 with ANS only, 1 with HELP only)' in rep1, 'with the summary')
ok('== Effects that did not hold (1' in rep1 and 'FAIL daily_claim_sets_day calim' in rep1, 'failed effects are listed as FAIL')
ok('== Bag keeping (sold 9 items for 700 gold in 3 visits, equipped 2, dropped 1' in rep1, 'the bag keeping line')
eq(TC.report_diff('', rep1), [], 'no previous report: no diff section')
ok('Against the previous run' not in rep1, 'and none in the report')
back = TC.read_report(rep1)
eq(back['proof']['bank'], (2, 2, 0, 0), 'a report reads back: proof')
eq(back['behaviours']['hunt'], (500, 400, 50, 50), 'a report reads back: behaviours')
eq(back['failures']['depot: no locker'], 5, 'a report reads back: failures')
eq(back['head']['deaths'], 40, 'a report reads back: the head line')
cov2 = json.loads(json.dumps(cov))
cov2['bank']['real'] = 0
cov2['daily']['real'] = 3
cov2['daily']['failed'] = 0
cov2['charms']['failed'] = 2
run2 = dict(run1, deaths=10, coverage=cov2, failures={'shop: no window': 7}, effects=[],
            behaviours={'hunt': {'tried': 500, 'ok': 100, 'failed': 350, 'expected': 50}})
rep2 = TC.build_report(run2, empty_log, rep1, ' of 20261115-100000')
ok('== Against the previous run of 20261115-100000 (' in rep2, 'the diff names the previous run')
for want in ('deaths 40 -> 10', 'bank: REAL proof lost (was 2)', 'daily: REAL proof now (3)', 'charms: failed effects 0 -> 2',
             'new failure: 7x shop: no window', 'failure gone: depot: no locker', 'behaviour hunt ok 400 -> 100, failed 50 -> 350'):
    ok(want in rep2, 'the diff says %r' % want)
ok(rep2.index('Against the previous run') < rep2.index('== Server log: errors'), 'the diff comes first, after the header')
rep3 = TC.build_report(run1, empty_log, rep1, ' of x')
ok('nothing moved' in rep3, 'the same run twice: nothing moved')
# the previous report file: the newest one older than this run
_d = tempfile.mkdtemp()
os.makedirs(os.path.join(_d, 'runs'))
for st_, txt in (('20261101-000000', 'old'), ('20261110-000000', 'newer'), ('20261120-000000', 'later')):
    with open(os.path.join(_d, 'runs', 'run-%s-report.txt' % st_), 'w') as f_:
        f_.write(txt)
eq(T.previous_report(_d, '/x/runs/run-20261115-120000.log'), ('newer', ' of 20261110-000000'), 'the newest report older than the run')
eq(T.previous_report(_d, '/x/runs/run-20261101-000000.log'), ('', ''), 'no older report: none')
shutil.rmtree(_d)

# ---------------------------------------------------------------- keeping the drops (O584 item 2)
eq(TC.classify('Sold 3x item 5 for 1,200 gold.'), ('sold', (3, 1200)), 'the Loot Buyer sale text')
eq(TC.classify('Sold item 5 for 40 gold.'), ('sold', (1, 40)), 'a single copy')
eq(TC.move_packet((0xFFFF, 0x40, 2), 0x1234, 2, (0xFFFF, 1, 0), 1),
   b'\x78' + struct.pack('<HHB', 0xFFFF, 0x40, 2) + struct.pack('<HB', 0x1234, 2) + struct.pack('<HHB', 0xFFFF, 1, 0) + b'\x01',
   'the move packet: from the backpack slot to the equipment slot')
eq(len(TC.move_packet((1, 2, 3), 4, 5, (6, 7, 8), 300)), 1 + 5 + 3 + 5 + 1, 'the move packet is 15 bytes')
eq(TC.move_packet((1, 2, 3), 4, 5, (6, 7, 8), 300)[-1], 255, 'a count is one byte')
eq(TC.sale_packet(2400, 0, 100), b'\x7b' + struct.pack('<HBBB', 2400, 0, 100, 1), 'the sale packet')
eq(TC.use_packet((0xFFFF, 3, 0), 1988), b'\x82' + struct.pack('<HHB', 0xFFFF, 3, 0) + struct.pack('<HBB', 1988, 0, 0), 'the use packet')
rep0 = {'used': 16, 'size': 20, 'sell': 2, 'better': 3, 'junk': [5, 9, 11, 12, 13],
        'rows': [{'i': 3, 'id': 3001, 'cid': 13001, 'n': 1, 'k': 'sell', 's': 1, 'sc': 90},
                 {'i': 5, 'id': 3003, 'cid': 13003, 'n': 4, 'k': 'junk'}, {'i': 9, 'id': 3004, 'cid': 13004, 'n': 1, 'k': 'junk'},
                 {'i': 11, 'id': 3005, 'cid': 13005, 'n': 1, 'k': 'junk'}, {'i': 12, 'id': 3006, 'cid': 13006, 'n': 1, 'k': 'junk'}]}
pl = TC.keep_plan(rep0)
eq((pl['equip']['id'], pl['sell']), (3001, True), 'plan: a better piece to wear, a full bag to sell')
eq(TC.keep_plan(rep0, refused={3001})['equip'], None, 'plan: a refused piece is not tried again')
eq(TC.keep_plan(dict(rep0, used=5))['sell'], False, 'plan: an empty bag and two things to sell: no trip')
eq(TC.keep_plan(dict(rep0, used=5), room_fails=1)['sell'], True, 'plan: pickups with no room: sell')
eq(TC.keep_plan(dict(rep0, sell=0))['sell'], False, 'plan: nothing the Loot Buyer buys: no trip')
eq([r['i'] for r in TC.drop_rows(rep0)], [5, 9, 11], 'drop: at most three junk rows')
eq(TC.drop_rows({'rows': [], 'junk': [4]}), [], 'drop: a junk index with no row')

class KC:
    def __init__(self):
        self.out = []

        class W:
            async def drain(self):
                return None
        self.w = W()

    def send(self, b):
        self.out.append(b)


# a bot keeps its bag: scripted reports, real packets
rk = T.Results(1)
kb = T.TesterBot(8, dict(bot), A(), 1, rk, {'rotation': [], 'heal': None})
kb.conn, kb.cid, kb.alive, kb.died = KC(), 0x10000008, True, False
kb.say = lambda text, kind=1: None
jam = {'used': 19, 'size': 20, 'sell': 0, 'better': 3, 'junk': [5], 'pos': {'x': 10, 'y': 20, 'z': 7}, 'bagClientId': 1988,
       'rows': [{'i': 3, 'id': 3001, 'cid': 13001, 'n': 1, 'k': 'sell', 's': 1, 'sc': 90},
                {'i': 5, 'id': 3003, 'cid': 13003, 'n': 4, 'k': 'junk'}]}
calm = {'used': 17, 'size': 20, 'sell': 0, 'better': None, 'junk': [], 'pos': jam['pos'], 'bagClientId': 1988, 'rows': []}
script = [jam, jam, calm]  # first look, after the wear (the piece is gone but one junk is left), after the drop
said_k = []


async def _says_k(command, kind, wait=4.0):
    said_k.append(command)
    if command.startswith('bag'):
        return script.pop(0) if script else calm
    return {'pos': {}}
kb.helper_says = _says_k
_sleep = asyncio.sleep


async def _fast(_s, *a, **k):
    return None
asyncio.sleep = _fast
try:
    jam['rows'][0]['i'] = 3
    after_wear = dict(jam, rows=[jam['rows'][1]], better=None)
    script[:] = [jam, after_wear, after_wear, calm]  # look, check of the wear, look after it, look after the drop
    eq(asyncio.run(kb.do_keep(None)), True, 'a keep round ends ok')
finally:
    asyncio.sleep = _sleep
sent_k = kb.conn.out
moves = [b for b in sent_k if b[:1] == b'\x78']
eq(moves[0], TC.move_packet((0xFFFF, 0x40, 3), 13001, 3, (0xFFFF, 1, 0), 1), 'the better piece is moved to its equipment slot')
eq(moves[1], TC.move_packet((0xFFFF, 0x40, 5), 13003, 5, (10, 20, 7), 4), 'the junk is moved to the floor of the own tile')
ok(sent_k[0][:1] == b'\x82', 'the backpack is opened first (use packet)')
eq((rk.d['keep'].get('equipped'), rk.d['keep'].get('dropped')), (1, 1), 'counted: one worn, one dropped')
ok(not any(c.startswith('bag wipe') for c in said_k), 'the helper did not wipe')
# a piece the server will not let it wear: remembered
rk2 = T.Results(1)
kc = T.TesterBot(9, dict(bot), A(), 1, rk2, {'rotation': [], 'heal': None})
kc.conn, kc.cid, kc.alive, kc.died = KC(), 0x10000009, True, False
kc.say = lambda text, kind=1: None
same = dict(jam, junk=[])
script2 = [same, same]


async def _says_c(command, kind, wait=4.0):
    return script2.pop(0) if script2 else same
kc.helper_says = _says_c
asyncio.sleep = _fast
try:
    asyncio.run(kc.do_keep(None))
finally:
    asyncio.sleep = _sleep
ok(3001 in kc.equip_refused and rk2.d['keep'].get('equip_refused') == 1, 'a piece still in its slot after the move is refused, and remembered')
# a bag jammed with what cannot go: three rounds, then the helper wipes it, as a counted failure
rk3 = T.Results(1)
kd = T.TesterBot(10, dict(bot), A(), 1, rk3, {'rotation': [], 'heal': None})
kd.conn, kd.cid, kd.alive, kd.died = KC(), 0x1000000a, True, False
kd.say = lambda text, kind=1: None
stuck = {'used': 19, 'size': 20, 'sell': 0, 'better': None, 'junk': [], 'pos': jam['pos'], 'bagClientId': 1988, 'rows': []}
cmds = []


async def _says_d(command, kind, wait=4.0):
    cmds.append(command)
    return stuck
kd.helper_says = _says_d
asyncio.sleep = _fast
try:
    for _ in range(3):
        asyncio.run(kd.do_keep(None))
finally:
    asyncio.sleep = _sleep
ok('bag wipe' in cmds and rk3.d['keep'].get('wiped') == 1, 'a bag jammed three rounds in a row is wiped by the helper')
ok(any(k.startswith('keep: the bag stayed jammed') for k in rk3.d['failures']), 'and the wipe is a counted failure')
# a calm bag does not touch anything
rk4 = T.Results(1)
ke = T.TesterBot(11, dict(bot), A(), 1, rk4, {'rotation': [], 'heal': None})
ke.conn, ke.cid, ke.alive, ke.died = KC(), 0x1000000b, True, False
ke.say = lambda text, kind=1: None


async def _says_e(command, kind, wait=4.0):
    return calm
ke.helper_says = _says_e
asyncio.sleep = _fast
try:
    asyncio.run(ke.do_keep(None))
finally:
    asyncio.sleep = _sleep
eq([b for b in ke.conn.out if b[:1] in (b'\x78', b'\x7b')], [], 'a calm bag: no move, no sale')
ok('keep' in TC.BEHAVIOURS, 'keep is a behaviour of the scheduler')

# the use-with packet and the check io's open_bag / use_with (O584 item 3)
eq(TC.use_with_packet((0xFFFF, 0x40, 1), 500, 1, (0xFFFF, 0x40, 2), 600, 2),
   b'\x83' + struct.pack('<HHB', 0xFFFF, 0x40, 1) + struct.pack('<HB', 500, 1) + struct.pack('<HHB', 0xFFFF, 0x40, 2) + struct.pack('<HB', 600, 2),
   'the use-with packet: item, then target')
rio = T.Results(1)
ib = T.TesterBot(12, dict(bot), A(), 1, rio, {'rotation': [], 'heal': None})
ib.conn, ib.cid, ib.alive, ib.died = KC(), 0x1000000c, True, False
cio = T.CheckIO(ib, {'stop': False, 'until': 1e12})
asyncio.run(cio.open_bag(1988))
asyncio.run(cio.use_with(0, 111, 1, 222))
eq(ib.conn.out[0], TC.use_packet((0xFFFF, 3, 0), 1988), 'open_bag uses the backpack slot')
eq(ib.conn.out[1][:1], b'\x83', 'use_with sends the use-with packet')
asyncio.run(cio.open_bag(0))
eq(len(ib.conn.out), 2, 'no client id: nothing sent')
# O592: an item used by its client id as a hotkey does (the rift key of the walked rift)
ok(asyncio.run(cio.use_item(20155)) is True, 'use_item: sent')
eq(ib.conn.out[2], TC.use_packet((0xFFFF, 0, 0), 20155), 'use_item: the hotkey packet (position 0xFFFF, slot 0)')
ok(asyncio.run(cio.use_item(0)) is False and len(ib.conn.out) == 3, 'use_item: no client id, nothing sent')

# ---------------------------------------------------------------- closed test mode (O582)
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k', '--closed']).closed, True, '--closed is a flag of run')
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k']).closed, False, 'closed mode is off by default')
with tempfile.TemporaryDirectory() as _d:
    os.makedirs(os.path.join(_d, 'data'))
    _a = T.Args()
    _a.server_dir, _a.state = _d, os.path.join(_d, 'state')
    _entries = [{'player_id': 100 + i, 'name': 'Tester Aa%s' % c} for i, c in enumerate('bcdefg')]
    _ran, _real_sql, _real_rows = [], T.sql, T.rows
    T.sql = lambda statements, db=None: _ran.append(list(statements)) or ''
    T.rows = lambda out: [['guilds'], ['chaos_market_orders'], ['chaos_arena_matches'], ['chaos_arena_match_players']]
    try:
        try:
            T.closed_start(_a, _entries, {})
            ok(False, 'the switch off: the run is refused')
        except SystemExit as e:
            ok('closed test mode is off' in str(e.code), 'the switch off: the run is refused')
        eq(_ran, [], 'nothing was written with the switch off')
        with open(os.path.join(_d, 'data', 'chaos_testers_closed'), 'w') as f:
            f.write('on\n')
        _st = {}
        with contextlib.redirect_stdout(io.StringIO()):
            T.closed_start(_a, _entries, _st)
        ok(_a.closed_plan['guilds'] and len(_a.closed_plan['guilds']) == 2, 'with the switch on: two tester guilds are planned')
        _flat = '\n'.join('\n'.join(x) for x in _ran)
        ok('INSERT INTO `guilds`' in _flat and 'DELETE FROM `guilds`' in _flat, 'old leftovers go, then the guilds are made')
        ok(_flat.index('DELETE FROM `guilds`') < _flat.index('INSERT INTO `guilds`'), 'in that order')
        ok(_st['closed']['guilds'] == ['Tester Guild Alfa', 'Tester Guild Bravo'], 'the state remembers the guilds')
        _ran.clear()
        with contextlib.redirect_stdout(io.StringIO()):
            T.closed_finish(_a, _entries)
        ok(any('DELETE FROM `chaos_market_orders`' in s for batch in _ran for s in batch), 'the end of a run removes the tester book')
        T.sql = lambda statements, db=None: (_ for _ in ()).throw(SystemExit('database: gone'))
        with contextlib.redirect_stdout(io.StringIO()) as _out:
            T.closed_finish(_a, _entries)
        ok('testers cleanup --yes' in _out.getvalue(), 'a failed clean-up says what removes it')
    finally:
        T.sql, T.rows = _real_sql, _real_rows
# the cleanup statements of closed mode come before the players go
_cs = T.cleanup_statements([('chaos_arena_ratings', 'player_id')], {5}, {7})
ok(_cs[0].startswith('DELETE FROM `chaos_arena_ratings`'), 'the generic cleanup is keyed by the ids (arena ratings)')
_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testers.py'), encoding='utf-8').read()
ok('stmts = closed_clean(players) + cleanup_statements(' in _src, 'cleanup removes the closed-mode rows first')

# ---------------------------------------------------------------- O589: the bot walks to a place by the engine path
class _WConn:
    def __init__(self):
        self.out = []

        class _Drain:
            async def drain(self):
                return None
        self.w = _Drain()

    def send(self, b):
        self.out.append(b)


def _walker(answers):
    """a TesterBot whose helper answers `path ...` from a list (None = no answer) and `enter ...` with a teleport"""
    b = T.TesterBot.__new__(T.TesterBot)
    b.conn, b.alive, b.died, b.helper, b.walk_until = _WConn(), True, False, {}, 0.0
    b.cmds, queue = [], list(answers)

    async def says(command, kind, wait=4.0):
        b.cmds.append(command)
        if command.startswith('path '):
            ans = queue.pop(0) if queue else None
            if ans is not None:
                b.helper['path'] = ans
            return ans
        ans = {'kind': 'x', 'pos': {'x': 1, 'y': 1, 'z': 7}}
        b.helper['enter'] = ans
        return ans
    b.helper_says = says
    return b


async def _no_sleep(*a, **k):
    return None
_real_sleep = asyncio.sleep
asyncio.sleep = _no_sleep
try:
    _clock = {'stop': False}
    _b = _walker([{'path': [1, 1, 2], 'dist': 3}, {'here': True, 'dist': 1}])
    eq(asyncio.run(_b.walk_to('depot', _clock)), 'foot', 'walk: asked again until the answer says it is there')
    eq(_b.conn.out, [bytes([0x66]), bytes([0x66]), bytes([0x67])], 'walk: the steps of the path as walk packets (east, east, south)')
    eq(asyncio.run(_walker([{'here': True}]).walk_to('depot', _clock)), 'foot', 'walk: already there')
    eq(asyncio.run(_walker([{'err': 'no path'}]).walk_to('depot', _clock)), 'no path', 'walk: the helper\'s reason')
    eq(asyncio.run(_walker([None]).walk_to('depot', _clock)), 'no answer', 'walk: no answer')
    eq(asyncio.run(_walker([{'path': [], 'dist': 5}]).walk_to('depot', _clock)), 'an empty path', 'walk: an empty path')
    eq(asyncio.run(_walker([{'path': [1], 'dist': 9}] * 5).walk_to('depot', _clock)), 'blocked', 'walk: the steps bring it no nearer: blocked')
    eq(asyncio.run(_walker([{'path': [1], 'dist': 50 - i} for i in range(20)]).walk_to('depot', _clock)), 'far',
       'walk: still on the way after the rounds')
    eq(asyncio.run(_walker([{'path': [1], 'dist': 9}]).walk_to('depot', {'stop': True})), 'gone', 'walk: the run is over')
    # walk_to_place: on foot, no teleport; else the teleport with its reason
    _b = _walker([{'here': True}])
    ok(asyncio.run(_b.walk_to_place('depot', _clock)), 'place: done')
    eq(_b.helper['enter'], {'walked': True, 'kind': 'depot'}, 'place: a walked arrival is recorded as walked')
    ok(not any(c.startswith('enter ') for c in _b.cmds), 'place: no teleport on foot')
    _b = _walker([{'err': 'no path'}])
    ok(asyncio.run(_b.walk_to_place('npc Archivist Odrenna', _clock)), 'place: done by the fallback')
    eq(_b.cmds, ['path npc Archivist Odrenna', 'enter npc Archivist Odrenna'], 'place: the path first, then the teleport')
    eq(_b.helper['enter'].get('fallback'), 'enter npc Archivist Odrenna: no path', 'place: the teleport answer names its reason')
    ok(not _b.helper['enter'].get('walked'), 'place: not recorded as walked')
    eq(_b.helper.get('walk'), {'fallback': 'enter npc Archivist Odrenna: no path'}, 'place: the walk outcome is kept for a later step (the rift key, O592)')
    _b = _walker([{'here': True}])
    asyncio.run(_b.walk_to_place('temple', _clock))
    eq(_b.helper.get('walk'), {'foot': True}, 'place: a walked arrival is kept as walked too')
    _b = _walker([None])
    asyncio.run(_b.walk_to_place('boss', _clock))
    eq(_b.helper['enter'].get('fallback'), 'enter boss: no answer', 'place: no answer to the path asks for the teleport too')
    ok(not asyncio.run(_walker([{'path': [1], 'dist': 9}]).walk_to_place('boss', {'stop': True})), 'place: a stopped run does nothing more')
finally:
    asyncio.sleep = _real_sleep

# ---------------------------------------------------------------- O655: modal windows, the buy packet, the text lines a check reads
eq(TC.buy_packet(2405, 0, 1), b'\x7a' + struct.pack('<HBBBB', 2405, 0, 1, 0, 0), 'the buy packet')
eq(TC.buy_packet(2405, 0, 500)[4], 100, 'the buy amount is at most 100')
eq(TC.modal_answer_packet(7101, 1, 0), b'\xf9' + struct.pack('<IBB', 7101, 1, 0), 'the modal answer packet: window, button, choice')
eq(TC.modal_answer_packet(7170, 2, 255)[-1], 255, 'no choice is 255')


def modal_bytes(wid, title, message, buttons, choices, escape, enter):
    out = b'\xfa' + struct.pack('<I', wid) + LT.string(title) + LT.string(message) + bytes([len(buttons)])
    for bid, text in buttons:
        out += LT.string(text) + bytes([bid])
    out += bytes([len(choices)])
    for cid, text in choices:
        out += LT.string(text) + bytes([cid])
    return out + bytes([escape, enter, 0])


win = modal_bytes(7170, 'Tales', 'Pick one', [(1, 'Read'), (2, 'Close')], [(1, 'The Hollow Road'), (2, 'Ash')], 2, 1)
got = T.parse_modal(b'\x10\x20' + win + b'\x30', T.MODAL_IDS)
eq(len(got), 1, 'a modal window of a known id is found in the middle of a message')
eq((got[0]['id'], got[0]['title'], got[0]['message']), (7170, 'Tales', 'Pick one'), 'its id, title and text')
eq(got[0]['buttons'], [(1, 'Read'), (2, 'Close')], 'the buttons: id and text')
eq(got[0]['choices'], [(1, 'The Hollow Road'), (2, 'Ash')], 'the choices: id and text')
eq((got[0]['escape'], got[0]['enter']), (2, 1), 'the escape and the enter button')
eq(T.parse_modal(win, (7171,)), [], 'another id is not looked for')
eq(T.parse_modal(win[:-9], T.MODAL_IDS), [], 'a window cut short is no window')
two = modal_bytes(7101, 'Trial', 'x', [(1, 'Enter'), (2, 'Not yet')], [], 2, 1) + modal_bytes(7102, 'Choice', 'y', [(1, 'Choose')], [(1, 'A'), (2, 'B')], 1, 1)
eq([w['id'] for w in T.parse_modal(two, T.MODAL_IDS)], [7101, 7102], 'two windows of one message')
ok(7101 in T.MODAL_IDS and 7102 in T.MODAL_IDS and 7125 in T.MODAL_IDS and 7170 in T.MODAL_IDS and 7171 in T.MODAL_IDS and 7110 not in T.MODAL_IDS,
   'the ids: the Oracle trial, choice and confirm windows (7111-7149), the tales')

# the bot keeps the windows and the text lines for the checks
mb = T.TesterBot(0, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None, 'all': [{'words': 'exura', 'level': 1}]})
mb.read(win)
eq([w['id'] for w in mb.modals], [7170], 'the bot keeps the window the server opened')
n0 = mb.recent_n
for i in range(70):
    mb.on_text('line %d' % i)
eq((len(mb.recent), mb.recent[-1], mb.recent_n - n0), (60, 'line 69', 70), 'the last 60 text lines, and how many came in all')
eq(mb.all_spells, [{'words': 'exura', 'level': 1}], 'the spells of the class for the support check')
eq(T.TesterBot(1, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None}).all_spells, [], 'a bot made without the list has none')
eq([s['words'] for s in T.class_spells([{'words': 'a', 'name': 'a', 'group': 'support', 'level': 5, 'needlearn': False, 'params': False, 'vocations': {'Knight'}},
                                       {'words': 'b', 'name': 'b', 'group': 'support', 'level': 5, 'needlearn': False, 'params': False, 'vocations': {'Mystic'}},
                                       {'words': 'c', 'name': 'c', 'group': 'support', 'level': 500, 'needlearn': False, 'params': False, 'vocations': set()}],
                                      {}, 'Knight', 60)['all']], ['a'], 'class_spells: `all` holds the class\'s spells at the level (a spell of every vocation too)')

# ---------------------------------------------------------------- O657: a tool used on a thing of the map, the mount button
class _RB:
    """the part of a TesterBot the two IO calls use: the socket, the text lines, the state"""
    def __init__(self):
        self.conn, self.alive, self.died = _WConn(), True, False
        self.recent, self.recent_n = [], 0


_rb = _RB()
_rio = T.CheckIO(_rb, {'stop': False})
asyncio.sleep = _no_sleep
try:
    _texts = asyncio.run(_rio.use_item_with(5908, {'x': 100, 'y': 101, 'z': 7}, 2300, 2, 0.1))
    eq(_rb.conn.out[-1], TC.use_with_packet((0xFFFF, 0, 0), 5908, 0, (100, 101, 7), 2300, 2), 'a tool on the map: the use-with packet from the hotkey place')
    eq(_rb.conn.out[-1][:1], b'\x83', 'the use-with packet is 0x83')
    eq(_texts, [], 'no text line, no answer')
    eq(asyncio.run(_rio.use_item_with(0, {'x': 1, 'y': 1, 'z': 7}, 1, 0)), [], 'no tool, nothing is sent')
    eq(len(_rb.conn.out), 1, 'nothing was sent for it')
    eq(asyncio.run(_rio.use_item_with(5908, None, 1, 0)), [], 'no target place, nothing is sent')
    asyncio.run(_rio.toggle_mount(True, 0.1))
    eq(_rb.conn.out[-1], b'\xD4\x01', 'the mount button: mount')
    asyncio.run(_rio.toggle_mount(False, 0.1))
    eq(_rb.conn.out[-1], b'\xD4\x00', 'the mount button: dismount')
    _rb.alive = False
    eq(asyncio.run(_rio.toggle_mount(True, 0.1)), [], 'a bot that is gone sends nothing')
    eq(len(_rb.conn.out), 3, 'nothing more was sent')
finally:
    asyncio.sleep = _real_sleep

# ---------------------------------------------------------------- O658: the retreat's reads and heals, --no-gear
_r8 = T.Results(1)
_hb = T.TesterBot(13, dict(bot), A(), 1, _r8, {'rotation': [], 'heal': {'words': 'exura', 'group': 2, 'cooldown': 1000, 'groupcooldown': 1000}})
_hb.conn, _hb.cid, _hb.alive, _hb.died = KC(), 0x1000000d, True, False
_said = []
_hb.say = lambda text, kind=1: _said.append(text)
_hio = T.CheckIO(_hb, {'stop': False})
eq(_hio.health, None, 'health: none seen yet is None, not a full bar')
_hb.health, _hb.health_at = 22, _time.monotonic()
eq(_hio.health, 22, "health: the bot's own, in percent")
eq(asyncio.run(_hio.heal_now()), 'spell', 'heal_now: the heal spell first, whatever the health threshold of the rule')
eq(_said, ['exura'], 'heal_now: the words are said')
eq(asyncio.run(_hio.heal_now()), None, 'heal_now: the spell is on cooldown and there is no potion id: nothing')
_hb.helper['info'] = {'potions': {'health': 2160}}
eq(asyncio.run(_hio.heal_now()), 'potion', 'heal_now: then the stock health potion, the packet of the heal rule')
eq(_hb.conn.out[-1], b'\x84' + struct.pack('<HHB', 0xFFFF, 0, 0) + struct.pack('<HB', 2160, 0) + struct.pack('<I', 0x1000000d),
   'heal_now: use on its own creature')
eq(asyncio.run(_hio.heal_now()), None, 'heal_now: both on cooldown')
ok(_hb.pending.get('heal_spell') and _hb.pending.get('potion'), 'heal_now: the bot counts the heal and the potion as the heal rule does')
_hb.alive = False
eq(asyncio.run(_hio.heal_now()), None, 'heal_now: a bot that is gone does nothing')
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k', '--checks']).no_gear, False, 'the gear-up is on by default')
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k', '--checks', '--no-gear']).no_gear, True, '--no-gear is a flag of run')
ok(T.TX.CheckRun('Tester Aaa', 'Warrior', 100).gear is True, 'a CheckRun gears up by default')

# ---------------------------------------------------------------- O660: the checks run from the temple, a dead bot rests
class A660:
    host = '10.0.0.1'
    ops = {'lootfilter': 238}
    after_login = ''
    on_answer = None
    checks = True
    closed = False
    journey = False
    keystones = False


_b660 = T.TesterBot(14, dict(bot), A660(), 1, T.Results(1), {'rotation': [], 'heal': None})
ok(_b660.checks_stay(), 'a checks run keeps the bot in town while checks are left')
_b660.checks_done = True
ok(not _b660.checks_stay(), 'no checks left: the bot hunts again')
_b660.checks_done = False
A660.closed, A660.checks = True, False
ok(_b660.checks_stay(), 'a closed-only run is a checks run too')
A660.journey = True
ok(not _b660.checks_stay(), 'a journey is its own run: it walks, the checks do not hold the bot')
A660.journey, A660.keystones = False, True
ok(not _b660.checks_stay(), 'the keystone round keeps its own place first')
_b660.keytest_done = True
ok(_b660.checks_stay(), 'after the keystone round the checks hold the bot in town')
A660.closed, A660.checks, A660.keystones = False, True, False

_real_sleep660 = asyncio.sleep
_ticks660 = []


async def _fake_sleep660(seconds, *a, **k):
    _ticks660.append(seconds)
    _b660.back_at = None   # the rest is over after the first wait
    await _real_sleep660(0)

asyncio.sleep = _fake_sleep660
try:
    _b660.alive, _b660.died = True, False
    _b660.back_at = _time.monotonic() + 100
    asyncio.run(_b660.check_rest())
    eq(_ticks660, [1.0], 'a dead bot waits in the temple until its rest is over')
    _ticks660.clear()
    _b660.back_at = None
    asyncio.run(_b660.check_rest())
    eq(_ticks660, [], 'no rest: no wait')
    _b660.back_at = _time.monotonic() + 100
    _b660.died = True
    asyncio.run(_b660.check_rest())
    eq(_ticks660, [], 'a bot that died again does not wait here: the next login does')
finally:
    asyncio.sleep = _real_sleep660

# a request that follows another of the same window within the server's rate limit is dropped unanswered: the bot waits like a person
_b661 = T.TesterBot(15, dict(bot), A(), 1, T.Results(1), {'rotation': [], 'heal': None})
_b661.conn, _b661.cid, _b661.alive, _b661.died = KC(), 0x1000000e, True, False
_b661.args.ops = {'gamble': 240, 'hideout': 192}
_io661 = T.KeyIO(_b661, {'stop': False})
_slept661 = []
_real_sleep661 = asyncio.sleep


async def _fake_sleep661(seconds, *a, **k):
    _slept661.append(round(seconds, 2))
    await _real_sleep661(0)

asyncio.sleep = _fake_sleep661
try:
    asyncio.run(_io661.request('gamble', 'open', {}, [], 1.0))
    eq(_slept661, [], 'the first request of a window goes at once')
    asyncio.run(_io661.request('gamble', 'buy', {}, [], 1.0))
    ok(len(_slept661) == 1 and 0.0 < _slept661[0] <= T.REQUEST_GAP, 'the next request of the same window waits for the gap: %s' % _slept661)
    _slept661.clear()
    asyncio.run(_io661.request('hideout', 'open', {}, [], 1.0))
    eq(_slept661, [], 'another window is not held back')
    ok(T.REQUEST_GAP > 0.30, 'the gap is above the 300 ms rate limit of the Gambler')
finally:
    asyncio.sleep = _real_sleep661

# ---------------------------------------------------------------- the fight a person plays (O663): attack with the heal on cooldown, the mana potion, the mana read from the stats packet
_stats663 = b'\x00\x01' + b'\xa0' + struct.pack('<IIII', 150, 200, 12345, 40000) + struct.pack('<Q', 999) + struct.pack('<H', 30) + b'\x32' + bytes(10) \
    + struct.pack('<II', 70, 90) + bytes(20)
eq(TC.parse_stats(_stats663), (70, 90), 'the mana and the max mana of the stats packet (cast_relay.py op_stats layout)')
eq(TC.parse_stats(b'\xa0\x01\x02'), None, 'a short or foreign 0xA0 byte is not a stats packet')
eq(TC.parse_stats(b'\xa0' + struct.pack('<IIII', 300, 200, 1, 2) + bytes(40)), None, 'health above its maximum: not a stats packet')
eq(TC.hold_attack(35, {'words': 'x'}, True), True, 'under 50 % with the heal ready: the beat is the heal')
eq(TC.hold_attack(35, {'words': 'x'}, False), False, 'under 50 % with the heal on cooldown: the attack goes (two spell groups)')
eq(TC.hold_attack(35, None, True), False, 'no heal spell: the attack goes')
eq(TC.hold_attack(80, {'words': 'x'}, True), False, 'over 50 %: the attack')
eq(TC.mana_potion_due(100, 30, 100), True, 'under 40 % mana: the potion')
eq(TC.mana_potion_due(100, 40, 100), False, 'at 40 % mana: not yet')
eq(TC.mana_potion_due(30, 10, 100), False, 'the health needs the potion first')
eq(TC.mana_potion_due(100, None, None), False, 'mana unknown: no mana rule (the old behaviour)')
_hit663 = {'words': 'exori big', 'group': 'attack', 'cooldown': 2000, 'groupcooldown': 2000, 'mana': 500}
_cheap663 = {'words': 'exori small', 'group': 'attack', 'cooldown': 2000, 'groupcooldown': 2000, 'mana': 20}
eq(LT.next_spell([_hit663, _cheap663], {}, 10.0, mana=100)['words'], 'exori small', 'a spell the mana cannot pay is left for a cheaper one')
eq(LT.next_spell([_hit663, _cheap663], {}, 10.0)['words'], 'exori big', 'mana unknown: the first ready spell as before')
_r663 = T.Results(1)
_k663 = T.TesterBot(16, dict(bot), A(), 1, _r663, {'rotation': [_hit663, _cheap663], 'heal': heal})
_k663.conn, _k663.cid = C(), 0x10000010
_k663.helper['info'] = {'potions': {'health': 266, 'mana': 268}}
_said663 = []
_k663.say = lambda text, kind=1: _said663.append(text)
_k663.read(b'\x8c' + struct.pack('<I', _k663.cid) + b'\x1e')   # 30 %
_k663.keep_alive(200.0)
eq(_said663, ['exura x'], 'under 50 %, the heal ready: the heal, no attack this beat')
_k663.read(b'\x8c' + struct.pack('<I', _k663.cid) + b'\x2d')   # 45 %: the heal is on cooldown for a second, the potion too
_k663.keep_alive(200.3)
eq(_said663[-1], 'exori big', 'the heal on cooldown at 45 %: the attack goes (before O663 the bot never attacked under 50 %)')
_k663.read(b'\x8c' + struct.pack('<I', _k663.cid) + b'\x64')
_k663.read(_stats663)   # 70 of 90 mana: 77 %
_k663.keep_alive(205.0)
eq(len(_k663.conn.sent), 1, 'mana at 77 %: no mana potion (the one packet is the health potion of the 30 % beat)')
_k663.mana, _k663.mana_max = 20, 100
_k663.ready.pop('potion', None)
_sent663 = len(_k663.conn.sent)
_k663.keep_alive(210.0)
eq(len(_k663.conn.sent), _sent663 + 1, 'mana at 20 %, health full: a mana potion')
eq(struct.unpack('<H', _k663.conn.sent[-1][6:8])[0], 268, 'it is the mana potion of the helper info')
_k663.ready.pop('potion', None)
_k663.mana, _k663.mana_max = 20, 100
_said663.clear()
_k663.ready.clear()
_k663.keep_alive(220.0)
eq(_said663[-1], 'exori small', 'with 20 mana the spell of 500 is left and the cheap one is cast')

# ---------------------------------------------------------------- the Auto setup rotation (O663): the bots cast the preset a player with Auto setup casts
def _sp663(words, name, level=1, group='attack', needlearn=False, cooldown=2000, mana=10):
    return {'words': words, 'name': name, 'group': group, 'level': level, 'needlearn': needlearn, 'params': False, 'cooldown': cooldown,
            'groupcooldown': 2000, 'mana': mana, 'needtarget': False, 'vocations': set()}


_spells663 = [_sp663('a', 'Area Slam', 20), _sp663('b', 'Single Cut', 8), _sp663('c', 'Big One', 300), _sp663('d', 'Learned Only', 100, needlearn=True),
              _sp663('e', 'Extra Jab', 10), _sp663('f', 'Rage Cry', 5, group='support'), _sp663('g', 'Ultimate', 1200, needlearn=True)]
_names663 = {1: 'Area Slam', 2: 'Single Cut', 3: 'Big One', 4: 'Learned Only', 5: 'Extra Jab', 6: 'Rage Cry', 7: 'Ultimate'}
_by_name663 = {s['name']: s for s in _spells663}
_base663 = [dict(_spells663[5], group='support'), dict(_spells663[0], t5=5.0), dict(_spells663[1], t5=1.0), dict(_spells663[4], t5=1.0)]
_row663 = {'presets': [{'level': 8, 'spells': [2]}, {'level': 20, 'spells': [1, 2]}, {'level': 300, 'spells': [3, 4, 1, 2]}], 'extras': [5], 'ultimate': 7}
_got663 = TC.preset_rotation(_row663, 20, _names663, _by_name663, _base663)
eq([s['name'] for s in _got663], ['Rage Cry', 'Area Slam', 'Single Cut', 'Extra Jab'], 'level 20: the support spell stays in front, the preset in its order, the extras last')
_got663 = TC.preset_rotation(_row663, 400, _names663, _by_name663, _base663)
eq([s['name'] for s in _got663], ['Rage Cry', 'Big One', 'Area Slam', 'Single Cut', 'Extra Jab'], 'level 400: a spell that must be learned (the quest spell, the ultimate under its level) is left out')
eq([s['name'] for s in TC.preset_rotation(_row663, 8, _names663, _by_name663, _base663)], ['Rage Cry', 'Single Cut'], 'level 8: the first preset (the extra of level 10 is not open yet)')
eq(TC.preset_rotation(_row663, 5, _names663, _by_name663, _base663), _base663, 'under the first preset: the old rotation')
eq(TC.preset_rotation(None, 400, _names663, _by_name663, _base663), _base663, 'a class with no row: the old rotation')
eq(TC.preset_rotation({'presets': [{'level': 1, 'spells': [99]}]}, 400, _names663, _by_name663, _base663), _base663, 'no spell of the preset on the server: the old rotation')
eq(_got663[2]['t5'], 5.0, 'a spell the old rotation held keeps its fields')
_cs663 = T.class_spells(_spells663, {}, 'Warrior', 400, ({'Warrior': _row663}, _names663))
eq([s['name'] for s in _cs663['rotation']][:3], ['Big One', 'Area Slam', 'Single Cut'], 'class_spells casts the preset when it has the table')
_cs663 = T.class_spells(_spells663, {}, 'Warrior', 400)
eq('Learned Only' in [s['name'] for s in _cs663['rotation']], False, 'class_spells without the table: the old rotation (a quest spell is left out as before)')

for f in FAILS:
    print('FAIL ' + f)
print('testers_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)

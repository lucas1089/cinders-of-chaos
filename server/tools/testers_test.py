#!/usr/bin/env python3
"""Tests of the tester bots (tester_core.py, testers.py; server/README.md "Tester bots"): the behaviour scheduling, the
anomaly rules, the texts the bots read, the server log parsing and the report, the client key file rules, the setup
rows and the cleanup that deletes only testers by exact ids, a bot's reading of health, death and shop packets.

Run: python3 -I server/tools/testers_test.py (standard library only; no database, no server)."""
import json
import os
import random
import struct
import sys
import tempfile

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
eq(TC.health_anomaly(100, 0, True), 'death within one hit from full health', 'one hit from full')
eq(TC.health_anomaly(60, 0, True), None, 'a death after damage')
eq(TC.health_anomaly(100, 70, False), None, 'a hit')
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
       'coverage': {'autoloot': {'tried': 3, 'ok': 3, 'errors': 0}, 'arena': {'why': 'needs two parties'}}}
r = TC.build_report(run, p)
for want in ('2x Lua Script Error', 'Anomalies (2)', 'hit taken over 3x max health', '9x exhausted (expected in play)',
             '2x cannot use object (first: Tester Abd after depot)', '1x x.lua:5: boom (first: Tester Abe after opcodes)',
             '1x You have been idle', 'shop', 'never reached: needs two parties'):
    ok(want in r, 'the report has %r' % want)

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

# ---------------------------------------------------------------- healing spells
spells = [{'words': 'heal a', 'group': 'healing', 'level': 10, 'needlearn': False, 'params': False, 'vocations': set()},
          {'words': 'heal b', 'group': 'healing', 'level': 50, 'needlearn': False, 'params': False,
           'vocations': {'Knight'}},
          {'words': 'heal c', 'group': 'healing', 'level': 80, 'needlearn': False, 'params': False, 'vocations': set()}]
eq(T.class_spells(spells, {}, 'Knight', 60)['heal']['words'], 'heal b', 'the best healing spell of the level')
eq(T.class_spells(spells, {}, 'Mystic', 60)['heal']['words'], 'heal a', 'of the class')

for f in FAILS:
    print('FAIL ' + f)
print('testers_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)

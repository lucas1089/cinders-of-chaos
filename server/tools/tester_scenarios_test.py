#!/usr/bin/env python3
"""Tests of the tester bots' coverage layer (gen_tester_scenarios.py, tester_scenarios.json, tester_scenarios.py;
server/README.md "Tester bots", Coverage): the generated table is up to date and never offers what is out of scope,
staff only, money or a world action; a scenario's steps; payload data filled only from the bot's own answers, and a
character key only ever with a tester; the coverage counts; the report merge with log errors and the never-reached why.

Run: python3 -I server/tools/tester_scenarios_test.py (standard library only; no server)."""
import asyncio
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tester_scenarios as G  # noqa: E402
import tester_core as TC  # noqa: E402
import tester_scenarios as TS  # noqa: E402
import testers as T  # noqa: E402

FAILS = []
CHECKS = [0]


def eq(got, want, what):
    CHECKS[0] += 1
    if got != want:
        FAILS.append('%s: got %r, want %r' % (what, got, want))


def ok(cond, what):
    eq(bool(cond), True, what)


# ---------------------------------------------------------------- the generated table
table = G.build()
eq(G.render(table), G.read(G.OUT), 'tester_scenarios.json is up to date (run gen_tester_scenarios.py)')
kinds = {s['kind'] for s in table['systems'].values()}
ok(kinds <= {'opcode', 'out', 'passive', 'place', 'staff'}, 'known kinds: %s' % sorted(kinds))
for name, s in table['systems'].items():
    if s['kind'] in ('out', 'staff', 'passive'):
        ok(s.get('why'), name + ': a reason why the bots do not send it')
for name in G.OUT_OF_SCOPE:
    eq(table['systems'].get(name, {}).get('kind'), 'out', name + ' is out of scope')
for o in ('autoloot', 'crafting', 'spellbook', 'dungeons'):
    ok(not {'i18n', 'item_codec'} & set(table['opcodes'][o]['systems']), o + ': a library loaded by a file is not its owner')
sendable = TS.Scenarios(table)
for num, (name, e) in sendable.opcodes.items():
    ok(not e['out'], name + ': no out-of-scope opcode is sent')
    for act in e['actions']:
        ok(act not in G.ADMIN and not G.DENY_RE.search(act), '%s: %s is never sent' % (name, act))
    ok(not set(e['actions']) & set(e.get('skip', [])), name + ': skipped actions are not offered')
shop = table['opcodes'].get('shop', {})
ok(shop and not any(a.startswith('pay_') for a in shop['actions']), 'the payment actions of the shop are skipped')
for o in ('market', 'guild', 'antibot'):
    ok(table['opcodes'].get(o, {}).get('out'), o + ': an out-of-scope opcode')
staff = [n for n, s in table['systems'].items() if s['kind'] == 'staff']
ok(staff and all(table['systems'][n]['talkactions'] for n in staff), 'staff systems: their talkactions are listed')
inv = table['opcodes'].get('invasion', {})
ok(inv and 'start' not in inv['actions'], 'a bot never starts an invasion')
# only what the client really sends: the item tooltip asks with "get" (its `kind == "slot"` is no action)
eq(table['opcodes']['itemTooltip']['actions'], ['get'], 'the item tooltip: the action the client sends')
eq(table['opcodes']['nemesis']['actions'], ['get'], 'nemesis: its guard `action ~= "get"` is read')
ok('Open' in table['opcodes']['stash']['sub']['make'], 'the stash: its sub-actions (make)')
for name, (sysname, place, op) in [(p[0], p) for p in sendable.places]:
    ok(table['systems'][sysname]['kind'] not in ('out', 'staff'), name + ': a place of an allowed system')

# ---------------------------------------------------------------- a synthetic table: the scenarios
syn = {
    'opcodes': {
        'bounty': {'opcode': 223, 'actions': ['open', 'accept', 'abandon'], 'skip': [], 'out': False,
                   'dataKeys': ['key', 'name', 'gift', 'cid'], 'systems': ['bounty']},
        'market': {'opcode': 200, 'actions': ['buy'], 'skip': [], 'out': True, 'dataKeys': [], 'systems': ['market']},
        'loose': {'opcode': 201, 'actions': ['get'], 'skip': [], 'out': False, 'dataKeys': [], 'systems': []},
    },
    'systems': {
        'bounty': {'kind': 'opcode', 'opcodes': ['bounty'], 'files': ['bounty.lua'], 'talkactions': []},
        'market': {'kind': 'out', 'why': 'needs real players', 'opcodes': ['market'], 'files': ['market.lua'],
                   'talkactions': []},
        'rift': {'kind': 'place', 'place': 'rift', 'opcodes': [], 'files': ['rift.lua'], 'talkactions': []},
        'loot': {'kind': 'passive', 'why': 'play', 'opcodes': [], 'files': ['loot.lua'], 'talkactions': []},
        'trials': {'kind': 'staff', 'why': 'staff command only (/trial)', 'opcodes': [], 'files': ['trials.lua'],
                   'talkactions': ['/trial']},
    },
    'npcs': [{'npc': 'Archivist Maelis', 'keywords': ['lore', 'tales']}],
}
S = TS.Scenarios(syn, {'bounty': 224}, random.Random(3))
eq(sorted(S.opcodes), [201, 224], 'the installed opcode number wins; out-of-scope opcodes are left out')
eq([p[0] for p in S.places], ['rift'], 'the places')


class Res:
    def __init__(self):
        self.d = {'coverage': {}}


class Bot:
    def __init__(self, name, cid):
        self.name, self.cid, self.results, self.helper = name, cid, Res(), {}


me, other = Bot('Tester Abc', 0x10000001), Bot('Tester Abd', 0x10000002)
online = {me.cid: me, other.cid: other}
for _ in range(200):
    steps = S.next_request(me)
    ok(steps, 'a scenario')
    for st in steps:
        ok(st[0] in ('op', 'say', 'check', 'usekey'), 'a known step: %r' % (st,))
        if st[0] == 'op':
            ok(st[1] != 200, 'never the out-of-scope opcode')
        if st[0] == 'say':
            ok(st[1] in ('hi', 'bye', 'lore', 'tales') or st[1].startswith('!tester '), 'only helper words and NPC words')
ops = S.opcode_steps(224)
eq(ops[0], ('op', 224, 'open'), 'open first')
ok([a for _, _, a in ops][1:] == [a for a in ['accept', 'abandon'] if a in [x for _, _, x in ops]], 'client order kept')

sent, said, used = [], [], []
send = (lambda op, p: sent.append((op, json.loads(p))))
S.run_step(me, ('op', 224, 'accept'), online, send, said.append, used.append)
eq(sent[-1][1]['action'], 'accept', 'the action')
ok('key' not in sent[-1][1]['data'], 'no answer yet: the key is not invented')
eq(sent[-1][1]['data'].get('name'), 'Tester Abd', 'a character key: another tester')
eq(sent[-1][1]['data'].get('cid'), other.cid, 'a creature id: another tester')
ok('gift' not in sent[-1][1]['data'], 'never a gift')
eq(me.results.d['coverage']['bounty']['tried'], 1, 'tried counted under the system')
S.on_answer(me, 224, {'action': 'board', 'data': {'offers': [{'key': 'k7', 'name': 'Ana', 'cid': 5}],
                                                   'gift': 'Ana'}})
eq(me.results.d['coverage']['bounty']['ok'], 1, 'the answer counts ok')
for _ in range(20):
    S.run_step(me, ('op', 224, 'accept'), online, send, said.append, used.append)
    d = sent[-1][1]['data']
    eq(d.get('key'), 'k7', 'the key from the bot\'s own answer')
    ok(d.get('name') != 'Ana' and d.get('cid') != 5, 'a name or id from an answer is never used')
S.on_answer(me, 224, {'action': 'error', 'data': {'err': 'no such contract'}})
eq(me.results.d['coverage']['bounty']['refused'], 1, 'a refusal is counted apart')
S.on_answer(me, 224, {'action': 'board', 'data': {}})
eq(me.results.d['coverage']['bounty']['ok'], 1, 'an answer without a request pending is not counted')
alone = {me.cid: me}
S.run_step(me, ('op', 224, 'accept'), alone, send, said.append, used.append)
eq(sent[-1][1]['data'].get('name'), 'Tester Abc', 'alone: its own name, never another character')
S.run_step(me, ('op', 201, 'get'), online, send, said.append, used.append)
ok('loose' in me.results.d['coverage'], 'an opcode without a system: its own key')

me.helper['enter'] = {'kind': 'rift', 'tier': 2, 'keyClientId': 20155}
S.run_step(me, ('check', 'place:rift'), online, send, said.append, used.append)
eq(me.results.d['coverage']['place:rift']['ok'], 1, 'an enter answer counts ok')
S.run_step(me, ('usekey',), online, send, said.append, used.append)
eq(used, [20155], 'the rift key used by its client id')
me.helper['enter'] = {'kind': 'boss', 'err': 'no such place'}
S.run_step(me, ('check', 'place:rift'), online, send, said.append, used.append)
eq(me.results.d['coverage']['place:rift']['refused'], 1, 'an enter error counts refused')
ok('enter' not in me.helper, 'the answer is used once')
used.clear()
S.run_step(me, ('usekey',), online, send, said.append, used.append)
eq(used, [], 'after a refused enter no key is used')
S.run_step(me, ('check', 'npc:Archivist Maelis'), online, send, said.append, used.append)
eq(me.results.d['coverage']['npc:Archivist Maelis'], {'tried': 1, 'ok': 0, 'refused': 0, 'actions': {}},
   'no answer: tried only')
S.run_step(me, ('say', 'hi'), online, send, said.append, used.append)
eq(said, ['hi'], 'say')

# ---------------------------------------------------------------- the report merge
log = TC.parse_log([
    '[2026-10-22 10:00:00] Lua Script Error: [Event Interface]',
    'data/scripts/chaos/bounty.lua:44: attempt to index a nil value',
    'stack traceback:',
    '',
    '[2026-10-22 10:00:01] [Error - x] data/scripts/chaos/loot.lua:9: bad',
])
m = TS.merge(syn, me.results.d['coverage'], log)
eq(m['bounty']['tried'], 22, 'bounty tried')
eq(m['bounty']['errors'], 1, 'a log error naming bounty.lua counts for bounty')
eq(m['loot']['errors'], 1, 'and a passive system gets its log errors')
ok(m['loot']['why'].startswith('passive'), 'passive why')
ok(m['market']['why'].startswith('out of scope: needs real players'), 'out of scope with the reason')
ok(m['trials']['why'].startswith('out of scope: staff command'), 'staff: out of scope')
eq(m['rift']['tried'], 2, 'the place enters count for the system')
ok('npc:Archivist Maelis' in m and 'loose' in m, 'NPC dialogs and system-less opcodes are listed')
text = TC.build_report({'coverage': m}, log)
ok('never reached: out of scope: needs real players' in text, 'the report lists what bots cannot do, with why')

# ---------------------------------------------------------------- a bot runs a scenario (TesterBot.do_opcodes)


class Conn:
    def __init__(self):
        self.out = []

        class W:
            async def drain(self):
                return None
        self.w = W()

    def send(self, b):
        self.out.append(b)


class Args:
    pass


a = Args()
a.ops = {}
TS.attach(a, G.OUT)
a.scenarios_runner.pause = 0
a.scenarios_runner.rand = random.Random(5)
bot = T.TesterBot.__new__(T.TesterBot)
bot.args, bot.conn, bot.alive, bot.died, bot.helper, bot.name, bot.cid = a, Conn(), True, False, {}, 'Tester Abc', 1
bot.results, bot.last = Res(), ''
bot.say = lambda text, kind=1: bot.conn.send(b'\x96' + bytes([kind]) + text.encode())
for _ in range(30):
    ok(asyncio.run(bot.do_opcodes({'stop': False})), 'a scenario ran')
kinds_sent = {b[0] for b in bot.conn.out}
ok(kinds_sent <= {0x32, 0x96, 0x82}, 'only extended opcodes, says and the hotkey use: %r' % kinds_sent)
ok(0x32 in kinds_sent, 'extended opcodes were sent')
out_nums = {e['opcode'] for e in table['opcodes'].values() if e['out']}
ok(not any(b[0] == 0x32 and b[1] in out_nums for b in bot.conn.out), 'never an out-of-scope opcode on the wire')
a2 = Args()
a2.next_request, a2.scenarios_runner = None, None
bot.args = a2
eq(asyncio.run(bot.do_opcodes({'stop': False})), False, 'without --scenarios the behaviour does nothing')

# a sub-action goes into the data (the stash: make)
sub = TS.Scenarios({'opcodes': {'stash': {'opcode': 110, 'actions': ['Stash'], 'dataKeys': ['make'], 'out': False,
                                          'sub': {'make': ['Open']}}}, 'systems': {}, 'npcs': []}, {}, random.Random(1))
eq(json.loads(sub.payload(Bot('Tester S', 9), 110, 'Stash', {})), {'action': 'Stash', 'data': {'make': 'Open'}},
   'a stash request names its make')

for f in FAILS:
    print('FAIL ' + f)
print('tester_scenarios_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)

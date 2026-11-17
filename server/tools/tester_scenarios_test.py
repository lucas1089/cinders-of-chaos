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
ok(kinds <= {'closed', 'opcode', 'out', 'passive', 'place', 'staff'}, 'known kinds: %s' % sorted(kinds))
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
        ok(not G.DENY_RE.search(act), '%s: %s is never sent' % (name, act))
        ok(act not in G.ADMIN or act in G.ADMIN_ALLOW.get(name, {}), '%s: %s is a staff word, never sent (O584)' % (name, act))
    ok(not set(e['actions']) & set(e.get('skip', [])), name + ': skipped actions are not offered')
shop = table['opcodes'].get('shop', {})
ok(shop and not any(a.startswith('pay_') for a in shop['actions']), 'the payment actions of the shop are skipped')
for o in ('market', 'guild', 'antibot'):
    ok(table['opcodes'].get(o, {}).get('out'), o + ': an out-of-scope opcode')
for n in ('arena', 'battleground', 'pvpzone', 'guild', 'guildwar', 'market', 'market_orders', 'market_history', 'market_notify', 'bazaar', 'raid',
          'groupqueue', 'party_finder'):
    ok(table['systems'][n]['kind'] == 'closed', n + ': reached only in closed test mode (O582)')
ok('groupqueue' not in G.OUT_OF_SCOPE and 'party_finder' not in G.OUT_OF_SCOPE, 'the group queue and the party finder are closed-mode systems (O589)')
for o in ('groupQueue', 'partyFinder'):
    ok(table['opcodes'][o]['actions'] == [] and table['opcodes'][o]['skip'] and table['opcodes'][o]['out'],
       o + ': never sent by the random request behaviour, only by its closed check (O589)')
staff = [n for n, s in table['systems'].items() if s['kind'] == 'staff']
ok(staff and all(table['systems'][n]['talkactions'] for n in staff), 'staff systems: their talkactions are listed')
inv = table['opcodes'].get('invasion', {})
ok(inv and 'start' not in inv['actions'], 'a bot never starts an invasion')
# O584 item 1: the player's own start of a run, the reset of the filters and meters; conquest is a solo vendor
for o, acts in (('descent', ['start']), ('raid', ['start']), ('combatLog', ['reset']), ('hunt', ['reset']),
                ('lootfilter', ['reset']), ('trainerMeter', ['reset'])):
    for a in acts:
        if not table['opcodes'][o]['out']:  # the raid is out of scope since O582 (the server refuses testers): allowed by name only
            ok(a in table['opcodes'][o]['actions'] and a not in table['opcodes'][o]['skip'], '%s: %s is sent (ADMIN_ALLOW)' % (o, a))
        ok(a in G.ADMIN and a in G.ADMIN_ALLOW[o], '%s: %s is allowed by name, not by dropping it from ADMIN' % (o, a))
for o in ('invasion', 'riftAtlas', 'waystoneAtlas', 'daily'):  # the same word on another opcode stays a staff word
    ok(not set(table['opcodes'][o]['actions']) & {'start', 'reset', 'shift', 'grant'}, o + ': no staff word is sent')
ok('raid' not in G.OUT_OF_SCOPE and 'raid' in G.CLOSED_MODE, 'the raid is a closed-mode system, no longer out of scope (O588)')
ok(table['opcodes']['raid']['actions'] == [] and 'start' in table['opcodes']['raid']['skip'],
   'the raid window is never sent by the random request behaviour: only the closed check closed_raid starts it (O588)')
ok(table['opcodes']['dungeons']['actions'] == ['fetch'] and table['opcodes']['dungeons']['skip'] == ['queue'],
   'the dungeons window is fetched at random; only the closed check closed_dungeon queues (O589)')
ok(all(a in table['opcodes'][o]['skip'] for o, acts in G.CLOSED_ONLY.items() for a in acts), 'every closed-only action is skipped from the random behaviour')
ok(table['systems']['dungeons']['kind'] == 'opcode' and 'dungeons.lua' in table['systems']['dungeons']['files'], 'dungeons is a system with its own core (O589)')
ok('conquest' not in G.OUT_OF_SCOPE and table['systems']['conquest']['kind'] == 'opcode', 'conquest is a solo token vendor, not out of scope')
eq(sorted(table['opcodes']['conquest']['actions']), ['buy', 'close', 'open'], 'conquest: the vendor window actions are sent')
# every skipped action with its reason: nothing is skipped without one, and the reason names the rule that skipped it
rows = G.skipped(table)
ok(rows, 'there are skipped actions')
for o, a, why in rows:
    ok(why, '%s %s: a reason why the bots never send it' % (o, a))
    ok(why.startswith(('out of scope', 'staff or world action', 'money, report', 'only an out-of-scope', 'only the closed check')),
       '%s %s: a known reason: %s' % (o, a, why))
    if a in G.ADMIN and not why.startswith('out of scope'):
        ok(a not in G.ADMIN_ALLOW.get(o, {}), '%s %s: an allowed word is not skipped' % (o, a))
eq(sum(len(t['skip']) for t in table['opcodes'].values()), len(rows), 'the list holds every skipped action')
eq(sorted(len(t['skip']) for t in table['opcodes'].values()), sorted(len(t['skipWhy']) for t in table['opcodes'].values()),
   'a reason for each skipped action of each opcode')
ok(any(why.startswith('money, report') for _, _, why in rows) or any(why.startswith('staff') for _, _, why in rows),
   'staff and money words are in the list')
# a run the bot starts is left again
rs = TS.Scenarios(table, {}, random.Random(5))
for o in ('descent',):  # the raid would do the same, but O582 keeps it out of scope
    num = table['opcodes'][o]['opcode']
    seen_start = 0
    for _ in range(300):
        st = [a for _, _, a in rs.opcode_steps(num)]
        if 'start' in st:
            seen_start += 1
            ok(st[-1] == 'leave' and st.index('start') < st.index('leave') and st.count('leave') == 1, o + ': a start is followed by a leave: %s' % st)
    ok(seen_start > 0, o + ': a start comes up')
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
        ok(st[0] in ('op', 'say', 'npc', 'check', 'usekey', 'walk'), 'a known step: %r' % (st,))
        if st[0] == 'walk':
            ok(not st[1].startswith('rift'), 'a rift key is no place to walk to (the rift scenario keeps its enter): %r' % (st,))
        if st[0] == 'say' and st[1].startswith('!tester enter '):
            ok(st[1].startswith('!tester enter rift'), 'the only teleport left in a scenario is the rift key: %r' % (st,))
        if st[0] == 'op':
            ok(st[1] != 200, 'never the out-of-scope opcode')
        if st[0] in ('say', 'npc'):
            ok(st[1] in ('hi', 'bye', 'lore', 'tales') or st[1].startswith('!tester '), 'only helper words and NPC words')
        if st[0] == 'npc':
            ok(steps.index(st) > steps.index(('say', 'hi')), 'words to the NPC only after the greeting')
        if st[0] == 'say':
            ok(st[1] in ('hi',) or st[1].startswith('!tester '), 'the greeting and the helper are plain says')
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
# O589: a walked arrival is a walk, no helper shortcut; a teleport fallback is counted as help and named
wb = Bot('Tester Wlk', 0x10000009)
wb.helper['enter'] = {'walked': True, 'kind': 'depot'}
S.run_step(wb, ('check', 'place:bank'), online, send, said.append, used.append)
cw = wb.results.d['coverage']['place:bank']
eq((cw['ok'], cw['walk'], cw.get('help')), (1, 1, 0), 'a walked arrival counts ok and walk, never help')
wb.helper['enter'] = {'kind': 'bank', 'pos': {'x': 1, 'y': 2, 'z': 7}, 'fallback': 'enter bank: no path'}
S.run_step(wb, ('check', 'place:bank'), online, send, said.append, used.append)
eq((cw['ok'], cw['walk'], cw['help']), (2, 1, 1), 'a teleport fallback counts ok and help')
eq(cw['actions'], {'teleport: enter bank: no path': 1}, 'and its reason is named in the actions')
wsys = dict(syn)
mw = TS.merge(wsys, wb.results.d['coverage'], TC.parse_log([]))
eq((mw['place:bank']['help'], mw['place:bank']['ans']), (1, 1), 'the report row: one helper shortcut, one walked arrival (ANS)')
said_before = list(said)
S.run_step(wb, ('walk', 'depot'), online, send, said.append, used.append)
eq(said[len(said_before):], ['!tester enter depot'], 'a driver that cannot walk falls back to the helper word')
S.run_step(me, ('check', 'npc:Archivist Maelis'), online, send, said.append, used.append)
eq(me.results.d['coverage']['npc:Archivist Maelis'], {'tried': 1, 'ok': 0, 'refused': 0, 'actions': {}},
   'no answer: tried only')
S.run_step(me, ('say', 'hi'), online, send, said.append, used.append)
eq(said[-1:], ['hi'], 'say')
said_kinds = []
S.run_step(me, ('npc', 'lore'), online, send, lambda text, kind=1: said_kinds.append((text, kind)), used.append)
eq(said_kinds, [('lore', 12)], 'words to a focused NPC go in the NPC channel (TALKTYPE_PRIVATE_PN 12)')

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
# the helper of the walk (O589): `path <place>` answers a path, then "here"; an NPC has no path (the fallback: the teleport, named)
cmds, pending = [], {}


async def fake_says(command, kind, wait=4.0):
    cmds.append(command)
    if command.startswith('path '):
        args = command[5:]
        if args.startswith('npc '):
            ans = {'err': 'no path', 'name': args}
        elif args in pending:
            pending.pop(args)
            ans = {'here': True, 'dist': 1, 'pos': {'x': 5, 'y': 5, 'z': 7}}
        else:
            pending[args] = True
            ans = {'path': [1, 1, 2], 'dist': 3, 'pos': {'x': 1, 'y': 1, 'z': 7}}
        bot.helper['path'] = ans
        return ans
    ans = {'kind': command.split(' ')[1], 'pos': {'x': 9, 'y': 9, 'z': 7}}
    bot.helper['enter'] = ans
    return ans
bot.helper_says = fake_says
bot.walk_until = 0.0
for _ in range(30):
    ok(asyncio.run(bot.do_opcodes({'stop': False})), 'a scenario ran')
kinds_sent = {b[0] for b in bot.conn.out}
ok(kinds_sent <= {0x32, 0x96, 0x82, 0x65, 0x66, 0x67, 0x68}, 'only extended opcodes, says, the hotkey use and walk steps: %r' % kinds_sent)
ok(0x66 in kinds_sent and 0x67 in kinds_sent, 'the bot walked the steps of the path (east, south)')
ok(any(c.startswith('path ') for c in cmds), 'a place is asked for as a path first')
ok(not any(c.startswith('enter ') and not c.startswith('enter npc ') and not c.startswith('enter rift') for c in cmds),
   'a place the path reached is not teleported to: %r' % [c for c in cmds if c.startswith('enter ')][:3])
ok(any(c.startswith('enter npc ') for c in cmds) and not any(c.startswith('enter npc ') and ('path ' + c[6:]) not in cmds for c in cmds),
   'an NPC with no path: the teleport only after the path was asked')
cov = bot.results.d['coverage']
ok(any(k.startswith('place:') and v.get('walk') for k, v in cov.items()), 'a walked arrival is counted as walk')
ok(all(v.get('help', 0) == 0 for k, v in cov.items() if k.startswith('place:') and v.get('walk')), 'walks are no helper shortcut')
ok(any(k.startswith('npc:') and v.get('help') and any(a.startswith('teleport: enter npc') and 'no path' in a for a in v['actions']) for k, v in cov.items()),
   'the teleport fallback is counted (help) and named (teleport: enter npc ...: no path)')
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

# O262: dispatch tables, silent actions, expected refusals, switches and hints (the first live run: "no answer, no error")
ops_ = table['opcodes']
eq(sorted(ops_['pact']['actions']), sorted(['open', 'sync', 'claim', 'buildSave', 'buildLoad', 'buildDelete', 'marksBuy']),
   'pact: the keys of its ACTIONS table, not the words of the file')
ok({'open', 'place', 'take'} <= set(ops_['charms']['actions']), 'charms: the keys of its actions table')
ok({'open', 'save', 'load'} <= set(ops_['loadouts']['actions']), 'loadouts: `actions.name = function` assignments')
eq(G.dispatch_actions('local actions = {\n\topen = function() end,\n\tput = {1, {a = 2}},\n}\nlocal x = actions[msg.action]\n'),
   ['open', 'put'], 'a dispatch table: its top-level keys only')
eq(G.dispatch_actions('local t = {a = 1}\nlocal y = other[action]\n'), [], 'no `x[msg.action]`: no dispatch table')
eq(ops_['castbar']['silent'], {'cancel': ops_['castbar']['silent']['cancel']}, 'castbar cancel is silent by design')
eq(ops_['mapmarks']['flags'], ['on'], 'the map overlay switch is sent as true')
eq(ops_['mapMarkers']['flags'], ['party', 'poi'], 'the party and poi switches are sent as true')
ok('veiled' in ops_ and 'choose' in ops_['veiled']['refuses'], 'veiled: the refusal is the right answer')
cap = TS.Scenarios(table, {}, random.Random(2))
b2 = Bot('Tester Abe', 0x10000003)
sent2 = []
snd = (lambda op, p: sent2.append((op, json.loads(p))))
cap.run_step(b2, ('op', ops_['mapmarks']['opcode'], 'watch'), {}, snd, None, None)
eq(sent2[-1][1], {'action': 'watch', 'data': {'on': True}}, 'watch: on')
cap.run_step(b2, ('op', ops_['castbar']['opcode'], 'cancel'), {}, snd, None, None)
eq(b2.results.d['coverage']['castbar']['ok'], 1, 'a silent request counts ok when sent')
ok((b2.results.d['coverage']['castbar']['tried'], (b2.results.d['coverage']['castbar']['refused'])) == (1, 0), 'and is tried once')
cap.run_step(b2, ('op', ops_['itemTooltip']['opcode'], 'get'), {}, snd, None, None)
eq([i['pos']['y'] for i in sent2[-1][1]['data']['items']], [6, 7, 4], 'item tooltip: three worn slots')
n_before = len(sent2)
cap.run_step(b2, ('op', ops_['groundLoot']['opcode'], 'look'), {}, snd, None, None)
eq(len(sent2), n_before, 'ground loot look: no known position, nothing sent, nothing counted')
b2.helper['hunt'] = {'pos': {'x': 100, 'y': 200, 'z': 7}}
cap.run_step(b2, ('op', ops_['groundLoot']['opcode'], 'look'), {}, snd, None, None)
eq(len(sent2[-1][1]['data']['t']), 9, 'ground loot look: the 3 x 3 tiles around the hunt spot')
eq([100, 200, 7] in sent2[-1][1]['data']['t'], True, 'including the bot\'s own tile')
n_before = len(sent2)
cap.run_step(b2, ('op', ops_['groundLoot']['opcode'], 'tip'), {}, snd, None, None)
eq(len(sent2), n_before, 'tip: no pile seen yet, nothing sent')
cap.on_answer(b2, ops_['groundLoot']['opcode'], {'action': 'tiles', 'data': {'t': [
    {'p': {'x': 100, 'y': 201, 'z': 7}, 'i': [{'s': 1, 'id': 2160, 'c': 3, 'nm': 'gold'}]}]}})
cap.run_step(b2, ('op', ops_['groundLoot']['opcode'], 'tip'), {}, snd, None, None)
eq(sent2[-1][1], {'action': 'tip', 'data': {'p': {'x': 100, 'y': 201, 'z': 7}, 's': 1, 'id': 2160, 'c': 3}},
   'tip: an item of a pile the look was answered with')
cap.run_step(b2, ('op', ops_['veiled']['opcode'], 'choose'), {}, snd, None, None)
cap.on_answer(b2, ops_['veiled']['opcode'], {'action': 'result', 'data': {'ok': False, 'text': 'The item moved'}})
eq(b2.results.d['coverage']['veiled']['refused'], 0, 'veiled: the expected refusal is not counted refused')
eq(b2.results.d['coverage']['veiled']['ok'], 1, 'veiled: it counts ok')

# ---------------------------------------------------------------- effects (O584 item 4): an answer without its effect is a FAIL
EF = TS.Scenarios(table, {}, random.Random(9))
eq(sorted(EF.effects), sorted(e['name'] for e in table['effects']), 'every effect of the table runs')
for e in table['effects']:
    ok(e['system'] in table['systems'], e['name'] + ': a system of the table')
    ok(any(st.get('expect') for st in e['steps']), e['name'] + ': at least one step states an effect')


class FxRes(Res):
    def log(self, bot, kind, text):
        self.d.setdefault('log', []).append((kind, text))


class FxBot(Bot):
    def __init__(self, name, cid):
        Bot.__init__(self, name, cid)
        self.results = FxRes()


def play(effect, answers, bot=None):
    """runs the steps of an effect; answers[i] is the answer message(s) to step i (None: no answer). -> (bot, sent)"""
    bot = bot or FxBot('Tester Fxa', 0x10000009)
    sent_ = []
    op = table['opcodes'][next(e for e in table['effects'] if e['name'] == effect)['opcode']]['opcode']
    snd = (lambda o, p: sent_.append(json.loads(p)))
    n = len(next(e for e in table['effects'] if e['name'] == effect)['steps'])
    for i in range(n):
        EF.run_step(bot, ('fx', effect, i), {}, snd, None, None)
        for m in (answers[i] if i < len(answers) and answers[i] else []):
            EF.on_answer(bot, op, m)
    return bot, sent_


def bank_msg(money, bank):
    return {'action': 'open', 'data': [money, bank, 0, 0]}


b, s_ = play('bank_gold_moves', [[bank_msg(100, 20000)], [bank_msg(600, 19500)], [bank_msg(100, 20000)]])
eq([x['action'] for x in s_], ['openBank', 'withdraw', 'deposit'], 'the bank effect sends its three steps')
eq(s_[1]['data'], ['gold', 500], 'the withdraw amount')
c = b.results.d['coverage']['bank']
eq((c['real'], c.get('failed', 0), c['tried']), (2, 0, 3), 'bank: two effects seen, none failed')
eq(c['ans'], 1, 'the opening answer is an answer only')
# the bank answers but the gold did not move: FAIL, not ok
b, s_ = play('bank_gold_moves', [[bank_msg(100, 20000)], [bank_msg(100, 20000)], None])
c = b.results.d['coverage']['bank']
eq((c.get('real', 0), c['failed']), (0, 1), 'bank: an answer with no effect is a failure')
ok(b.results.d['effects'][0]['effect'] == 'bank_gold_moves' and 'moved by 0' in b.results.d['effects'][0]['why'], 'with its reason')
ok(any(k == 'EFFECT' for k, _ in b.results.d['log']), 'and a log line')
eq(len(s_), 2, 'a failed effect ends the chain')
# a balance under 500: nothing to show, skipped
b, s_ = play('bank_gold_moves', [[bank_msg(0, 100)]])
c = b.results.d['coverage']['bank']
eq((c.get('skipped'), c.get('failed', 0), len(s_)), (1, 0, 1), 'bank: too little gold is a skip')
# a refusal ends it as refused
b, _ = play('bank_gold_moves', [[bank_msg(10, 900)], [{'action': 'error', 'data': {'error': 'no'}}]])
eq(b.results.d['coverage']['bank']['refused'], 1, 'a refusal is counted refused')

# the daily claim: the value of the client's map comes from the day of the window
day = {'action': 'OpenDailyWindow', 'data': {'Day': 1, 'TakenReward': 0}}
done = {'action': 'OpenDailyWindow', 'data': {'Day': 1, 'TakenReward': 1}}
b, s_ = play('daily_claim_sets_day', [[day], [done]])
eq(s_[1], {'action': 'calim', 'data': 1}, 'Day 1 is slot 3, the client sends map[3] = 1')
eq(b.results.d['coverage']['daily']['real'], 1, 'daily: the day is taken')
b, s_ = play('daily_claim_sets_day', [[day], [day]])
eq(b.results.d['coverage']['daily']['failed'], 1, 'daily: a claim that leaves the day open fails')
b, s_ = play('daily_claim_sets_day', [[done]])
eq(b.results.d['coverage']['daily'].get('skipped'), 1, 'daily: already taken is a skip')

# the hunt meter: a push of the watcher may come first; the second answer decides
hz = {'action': 'state', 'data': {'xp': 0, 'kc': 0, 'dmg': 0, 'heal': 0, 'lv': 0, 'sv': 0}}
hs = {'action': 'state', 'data': {'xp': 5, 'kc': 1, 'dmg': 40, 'heal': 0, 'lv': 3, 'sv': 0}}
b, _ = play('hunt_session_reset', [[hs], [hs, hz]])
eq((b.results.d['coverage']['hunt'].get('real'), b.results.d['coverage']['hunt'].get('failed', 0)), (1, 0), 'hunt: the second state shows the reset')
b, _ = play('hunt_session_reset', [[hs], [hs, hs]])
eq(b.results.d['coverage']['hunt']['failed'], 1, 'hunt: a meter that keeps its numbers fails')
b, _ = play('hunt_session_reset', [[hz]])
eq(b.results.d['coverage']['hunt'].get('skipped'), 1, 'hunt: nothing to reset is a skip')

# the filter counters, the loadout slot, the tooltip
lf = {'action': 'counts', 'data': {'session': {'a': 0}, 'total': {'a': 0, 'b': 0}}}
b, _ = play('lootfilter_counts_reset', [[lf]])
eq(b.results.d['coverage']['lootfilter']['real'], 1, 'lootfilter: counters at 0')
b, _ = play('lootfilter_counts_reset', [[{'action': 'counts', 'data': {'session': {'a': 2}, 'total': {}}}]])
eq(b.results.d['coverage']['lootfilter']['failed'], 1, 'lootfilter: a counter left')


def slots(**kw):
    return {'action': 'state', 'data': {'slots': [dict({'slot': 1, 'locked': False}, **kw)]}}


b, s_ = play('loadout_save_delete', [[slots(empty=True)], [slots(name='Bot build')], [slots(empty=True)]])
eq(b.results.d['coverage']['loadouts']['real'], 2, 'loadouts: saved, then deleted')
b, s_ = play('loadout_save_delete', [[slots(empty=True)], [slots(empty=True)]])
eq(b.results.d['coverage']['loadouts']['failed'], 1, 'loadouts: a save that left the slot empty fails')
b, s_ = play('loadout_save_delete', [[slots(name='Mine')]])
eq((b.results.d['coverage']['loadouts'].get('skipped'), len(s_)), (1, 1), 'loadouts: a used slot 1 is never touched')
b, _ = play('tooltip_of_backpack', [[{'action': 'tips', 'data': {'items': [{'tip': {'name': 'backpack'}}]}}]])
eq(b.results.d['coverage']['item_tooltip']['real'], 1, 'tooltip: names the item')
b, _ = play('tooltip_of_backpack', [[{'action': 'tips', 'data': {'items': [{'gone': True}]}}]])
eq(b.results.d['coverage']['item_tooltip']['failed'], 1, 'tooltip: gone is a failure')
# no answer: the next chain finds the old one waiting and counts it silent, judges nothing
b = FxBot('Tester Fxb', 0x1000000a)
EF.run_step(b, ('fx', 'bank_gold_moves', 0), {}, lambda o, p: None, None, None)
EF.run_step(b, ('fx', 'bank_gold_moves', 1), {}, lambda o, p: None, None, None)
eq((b.results.d['coverage']['bank'].get('silent'), b.results.d['coverage']['bank'].get('failed', 0)), (1, 0), 'no answer: silent, not failed')

# the condition language
M = TS.MISSING
eq(TS.path_get({'data': [1, {'a': 2}]}, ['data', 1, 'a']), 2, 'path: list index and key')
ok(TS.path_get({'data': []}, ['data', 0]) is M, 'path: missing')
ok(TS.cond_holds(['zero', ['d']], {'d': {'x': 0, 'y': [0, 0]}})[0], 'zero walks tables')
ok(not TS.cond_holds(['zero', ['d']], {'d': {'x': 0, 'y': [0, 1]}})[0], 'zero finds a number')
ok(not TS.cond_holds(['delta', ['d'], 1], {'d': 5})[0], 'delta needs a before')
ok(TS.cond_holds(['delta', ['d'], 1], {'d': 5}, {'d': 4})[0], 'delta 1')
eq(TS.resolve_data({'$answer': ['d'], 'plus': 2, 'table': [6, 7, 1]}, {'x': {'d': 0}}), (7, True), 'a value from a table, 1-based')
eq(TS.resolve_data({'$answer': ['d']}, {}), (None, False), 'no answer, no value')

# the report merge: REAL / ANS / HELP per system, and the system checks
syn_cov = {'bank': {'tried': 5, 'ok': 4, 'refused': 0, 'real': 2, 'ans': 2, 'failed': 1, 'actions': {}},
           'place:rift': {'tried': 2, 'ok': 2, 'refused': 0, 'actions': {}, 'help': 2}}
real_table = {'systems': {'bank': {'kind': 'opcode', 'files': ['bank.lua']}, 'rift': {'kind': 'place', 'files': ['rift.lua']},
                          'pets': {'kind': 'opcode', 'files': []}}}
mm = TS.merge(real_table, syn_cov, {'errors': {}}, [{'check': 'pets', 'status': 'pass'}, {'check': 'dual_fists', 'status': 'fail'},
                                                    {'check': 'rift', 'status': 'skip'}])
eq((mm['bank']['real'], mm['bank']['ans'], mm['bank']['failed']), (2, 2, 1), 'merge: real, ans, failed')
eq((mm['rift']['help'], mm['rift']['real']), (2, 0), 'merge: a helper teleport is HELP')
eq((mm['pets']['real'], mm['pets']['help'], mm['pets']['ok']), (1, 1, 1), 'merge: a passed check is REAL and HELP')
eq((mm['check:dual_fists']['failed'], mm['check:dual_fists']['real']), (1, 0), 'merge: a failed check is failed')
for k in TS.CHECK_SYSTEMS.values():
    ok(k.startswith('check:') or k in table['systems'], 'CHECK_SYSTEMS names a system of the table: ' + k)

for f in FAILS:
    print('FAIL ' + f)
print('tester_scenarios_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)

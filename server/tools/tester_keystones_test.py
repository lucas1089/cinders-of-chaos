#!/usr/bin/env python3
"""Tests of the keystone and mastery scenario of the tester bots (tester_keystones.py, tester_keytree.py, the keytest section
of tester_scenarios.json; O249; server/README.md "Tester bots", Keystones and masteries), against a mocked server:
  * a node whose effect appears -> pass; the effect missing -> fail; an effect no client can see -> "not observable"
  * the reset is always sent after a plan, also after a refusal, a failure and an error; a reset the character cannot pay is
    reported and every later node is "not tested"
  * the data: every class of the server has its nodes, every route is valid by the server's own rules, every keystone flag has
    a probe or a reason
  * the bot side: the request waits for its answer, --keystones is parsed, the report carries the section

Run: python3 -I server/tools/tester_keystones_test.py (standard library only; no server)."""
import asyncio
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tester_core as TC  # noqa: E402
import tester_keystones as TK  # noqa: E402
import tester_keytree as KT  # noqa: E402
import testers as T  # noqa: E402

FAILS = []
CHECKS = [0]
HERE = os.path.dirname(os.path.abspath(__file__))
CHAOS = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos')


def eq(got, want, what):
    CHECKS[0] += 1
    if got != want:
        FAILS.append('%s: got %r, want %r' % (what, got, want))


def ok(cond, what):
    eq(bool(cond), True, what)


# ---------------------------------------------------------------- the mocked server
class FakeServer:
    """the tree window and the DPS meter of one tester: saved nodes, points, gold, the totals the nodes give, a combat log"""

    def __init__(self, cls='thief', points=60, gold=10 ** 9, apply_effects=True, procs=True, node_stats=None):
        self.cls, self.points, self.gold = cls, points, gold
        self.apply_effects, self.procs = apply_effects, procs
        self.nodes, self.choice = [], {}
        self.mastery_effects = {}   # node -> [stats of effect 1, ...]
        self.node_stats = node_stats or {}
        self.clock = 0.0
        self.proc_hits = 0
        self.row_key, self.row_tab = 'p:Keystone: Shadow Twin', 0   # the combat log row the mocked server grows, and its tab
        self.requests = []          # (opname, action, data) in order
        self.alive = True
        self.reset_cost = 5000
        self.refuse_plan = None
        self.none_for = ()          # actions that get no answer

    # -- the totals the saved nodes give
    def stats(self):
        out = {}
        for n in self.nodes:
            for k, v in (self.node_stats.get(n) or {'strength': 1}).items():
                out[k] = out.get(k, 0) + v
        if self.apply_effects:
            for n, c in self.choice.items():
                if n in self.nodes:
                    for k, v in self.mastery_effects[n][c - 1].items():
                        out[k] = out.get(k, 0) + v
        return out

    def totals_msg(self):
        s = self.stats()
        attributes = [{'k': k, 'raw': s[k]} for k in KT.ATTRIBUTES if s.get(k, 0) > 0]
        elements = {k: s.get(k, 0) + s.get('multiIncrement', 0) for k in KT.ELEMENTS}
        damage = [{'k': k, 'raw': (elements[k] if k in elements else s.get(k, 0))} for k in KT.DAMAGE
                  if (elements[k] if k in elements else s.get(k, 0)) > 0]
        return {'action': 'statTotals', 'data': {'attributes': attributes, 'damage': damage, 'crit': {
            'chance': {'total': s.get('criticalHitChance', 0), 'tree': s.get('criticalHitChance', 0)},
            'amount': {'total': s.get('criticalHitAmount', 0), 'tree': s.get('criticalHitAmount', 0)}}}}

    def handle(self, opname, action, data):
        self.requests.append((opname, action, data))
        if action in self.none_for:
            return None
        if opname == 'passivetree':
            if action == 'requestNodesUnlocked':
                return {'action': 'sendNodes', 'data': {'preset': 1, 'nodes': sorted(self.nodes), 'cls': self.cls}}
            if action == 'requestPoints':
                return {'action': 'sendPoints', 'data': self.points - len(self.nodes)}
            if action == 'statTotals':
                return self.totals_msg()
            if action == 'planApply':
                if self.refuse_plan:
                    return {'action': 'planResult', 'data': {'ok': False, 'message': self.refuse_plan}}
                add = [n for n in data['nodes'] if n not in self.nodes]
                if len(self.nodes) + len(add) > self.points:
                    return {'action': 'planResult', 'data': {'ok': False, 'message': 'The plan needs more points'}}
                self.nodes += add
                for m in data.get('masteries') or []:
                    self.choice[m['id']] = m['choice']
                return {'action': 'planResult', 'data': {'ok': True, 'message': ''}}
            if action == 'masteryChoose':
                if self.gold < 1000:
                    return {'action': 'planResult', 'data': {'ok': False, 'message': 'You need 1,000 gold coins to change the effect.'}}
                self.gold -= 1000
                self.choice[data['id']] = data['choice']
                return {'action': 'planResult', 'data': {'ok': True, 'message': 'changed'}}
            if action == 'resetPreset':
                if not self.nodes:
                    return {'action': 'sendMessage', 'data': {'title': 'Reset', 'message': 'There is nothing to reset.'}}
                if self.gold < self.reset_cost:
                    return {'action': 'sendMessage', 'data': {'title': 'Reset',
                                                              'message': 'You need %d gold coins (carried or in the bank) to reset your passive tree.' % self.reset_cost}}
                self.gold -= self.reset_cost
                self.nodes, self.choice = [], {}
                return {'action': 'sendNodes', 'data': {'preset': 1, 'nodes': [], 'cls': self.cls}}
        if opname == 'combatLog':
            if action in ('open', 'seg'):
                rows = [[self.row_key, 'p', 'x', 'keystone', self.proc_hits * 40, self.proc_hits, 0, 40, 0]] if self.proc_hits else []
                tabs = [{'tot': 0, 'r': []} for _ in range(4)]
                tabs[self.row_tab]['r'] = rows
                return {'action': 'state', 'data': {'sel': 's', 'v': {'t': tabs}}}
        return None


class FakeIO:
    def __init__(self, server, proc_after=None):
        self.s, self.proc_after = server, proc_after
        self.leave_after = None

    def alive(self):
        return self.s.alive

    async def sleep(self, seconds):
        self.s.clock += seconds
        if self.proc_after is not None and self.s.clock >= self.proc_after and self.s.procs and self.s.nodes:
            self.s.proc_hits += 3
        if self.leave_after is not None and self.s.clock >= self.leave_after:
            self.s.alive = False

    async def request(self, opname, action, data, expect, timeout):
        a = self.s.handle(opname, action, data)
        if a is not None and expect and a.get('action') not in expect:
            return None
        return a


def run(table, server, index=0, io=None, **kw):
    t = TK.KeyTest(table, 'Tester Aaa', index, **kw)
    asyncio.run(t.run(io or FakeIO(server)))
    return t


def by(t, what):
    rows = [r for r in t.results if r['what'] == what]
    return rows[0] if rows else None


# ---------------------------------------------------------------- the pure parts
eq(TK.class_key('Bone Lord'), 'bonelord', 'class key of a vocation name')
eq(TK.totals_of({'attributes': [{'k': 'strength', 'raw': 4.0}], 'damage': [{'k': 'incrementFire', 'raw': 6}],
                 'crit': {'chance': {'tree': 2}, 'amount': {'tree': 5}}}),
   {'strength': 4.0, 'incrementFire': 6.0, 'criticalHitChance': 2.0, 'criticalHitAmount': 5.0}, 'totals_of')
eq(TK.totals_of(None), {}, 'totals_of nothing')
eq(TK.expected_delta({'multiIncrement': 2, 'strength': 1}, ['incrementFire', 'incrementIce']),
   {'incrementFire': 2, 'incrementIce': 2, 'strength': 1}, 'multiIncrement raises every element')
eq(TK.compare({'strength': 1}, {'strength': 3}, {'strength': 2}), [], 'compare: the effect is there')
ok(TK.compare({'strength': 1}, {'strength': 1}, {'strength': 2}), 'compare: the effect is missing')
eq(TK.compare({}, {'incrementFire': 6}, {'incrementFire': 6}), [], 'compare: a stat that was absent counts 0 before')
eq(TK.proc_hits({'v': {'t': [{'r': [['p:Keystones', 'p', 'Keystones', 'k', 90, 3, 0, 40, 0]]}]}}), (3, 90), 'proc_hits finds the row')
eq(TK.proc_hits({'v': {'t': [{'r': []}]}}), (0, 0), 'proc_hits: no row')
eq(TK.proc_hits(None), (0, 0), 'proc_hits: no state')

# ---------------------------------------------------------------- masteries
MASTERY = {'id': 665, 'kind': 'mastery', 'path': [10, 11], 'effects': [
    {'choice': 1, 'observable': {'criticalHitAmount': 5, 'criticalHitChance': 2}, 'other': []},
    {'choice': 2, 'observable': {'dexterity': 3}, 'other': ['speed']},
    {'choice': 3, 'observable': {}, 'other': ['absorbPhysical']},
    {'choice': 4, 'observable': {'multiIncrement': 2}, 'other': []}]}
MEFF = [{'criticalHitAmount': 5, 'criticalHitChance': 2}, {'dexterity': 3, 'speed': 200}, {'absorbPhysical': 2},
        {'multiIncrement': 2}]
TABLE = {'classes': {'thief': [MASTERY]}, 'elements': KT.ELEMENTS}

s = FakeServer()
s.mastery_effects[665] = MEFF
t = run(TABLE, s)
eq([r['status'] for r in t.results], [TK.PASS, TK.PASS, TK.NOT_OBSERVABLE, TK.PASS], 'mastery: effects that show pass, one that cannot be seen says so')
ok('speed' not in by(t, 'mastery 665 effect 2')['detail'].split('(')[0] and 'not observable: speed' in by(t, 'mastery 665 effect 2')['detail'],
   'the stat no client sees is named')
ok('absorbPhysical' in by(t, 'mastery 665 effect 3')['detail'], 'not observable names the stat')
eq(s.nodes, [], 'the tree is left clean')
eq([x[1] for x in s.requests].count('resetPreset'), 1, 'one reset sent')
eq(s.requests[-1][1], 'resetPreset', 'the reset is the last request')
eq(t.resets[-1]['ok'], True, 'the reset is read back as done')

# the effect does not appear in the totals
s = FakeServer(apply_effects=False)
s.mastery_effects[665] = MEFF
t = run(TABLE, s)
eq(by(t, 'mastery 665 effect 1')['status'], TK.FAIL, 'mastery: the effect missing from the totals fails')
ok('criticalHitAmount' in by(t, 'mastery 665 effect 1')['detail'], 'the failure names the stat')
eq(by(t, 'mastery 665 effect 3')['status'], TK.NOT_OBSERVABLE, 'an unobservable effect stays so')
eq(s.requests[-1][1], 'resetPreset', 'reset sent after failures')
eq(s.nodes, [], 'tree clean after failures')

# a wrong amount (the node gives 1 where 2 is promised)
s = FakeServer()
s.mastery_effects[665] = [dict(MEFF[0], criticalHitChance=1)] + MEFF[1:]
t = run(TABLE, s)
eq(by(t, 'mastery 665 effect 1')['status'], TK.FAIL, 'mastery: a wrong amount fails')

# changing the effect costs gold the character does not have: not tested, not faked
s = FakeServer(gold=500)
s.mastery_effects[665] = MEFF
t = run(TABLE, s)
eq(by(t, 'mastery 665 effect 1')['status'], TK.PASS, 'the first effect is free')
eq(by(t, 'mastery 665 effect 2')['status'], TK.NOT_TESTED, 'a change of effect the gold cannot pay is not tested')
ok('You need' in by(t, 'mastery 665 effect 2')['detail'], 'with the server message')
eq(by(t, 'mastery 665 effect 3')['status'], TK.NOT_OBSERVABLE, 'no gold needed to say an effect is not observable')

# not enough points
s = FakeServer(points=2)
s.mastery_effects[665] = MEFF
t = run(TABLE, s)
eq({r['status'] for r in t.results}, {TK.NOT_TESTED}, 'points: not tested')
ok('needs 3 points' in t.results[0]['detail'], 'points: says what was needed')
eq([x[1] for x in s.requests if x[1] in ('planApply', 'resetPreset')], [], 'points: nothing was planned, nothing to reset')

# the server refuses the route: a failure, and the reset is sent
s = FakeServer()
s.mastery_effects[665] = MEFF
s.refuse_plan = 'Node 10 belongs to another class.'
t = run(TABLE, s)
eq({r['status'] for r in t.results}, {TK.FAIL}, 'a refused plan fails every effect')
ok('another class' in t.results[0]['detail'], 'with the server text')
eq(s.requests[-1][1], 'resetPreset', 'the reset is sent after a refused plan')

# no answer to the totals
s = FakeServer()
s.mastery_effects[665] = MEFF
s.none_for = ('statTotals',)
t = run(TABLE, s)
eq(by(t, 'mastery 665 effect 1')['status'], TK.FAIL, 'no answer to statTotals fails')
eq(s.requests[-1][1], 'resetPreset', 'reset sent after a missing answer')

# ---------------------------------------------------------------- keystones
def key_row(nid, flag, mode='combatlog', path=(5, 6)):
    probe = ({'mode': 'combatlog', 'row': 'p:Keystone: Shadow Twin', 'tab': 'dealt', 'needs': 'a second enemy'} if mode == 'combatlog'
             else {'mode': 'none', 'why': 'a damage factor'})
    return {'id': nid, 'kind': 'keystone', 'flag': flag, 'path': list(path), 'probe': probe}


KTABLE = {'classes': {'thief': [key_row(631, 'ksShadowTwin'), key_row(383, 'ksBlackbloodCreed', 'none', (7,)),
                                key_row(900, 'ksCleavingArc', path=list(range(20, 90)))]}, 'elements': []}

s = FakeServer(points=30)
t = run(KTABLE, s, io=FakeIO(s, proc_after=40), window=100, poll=10)
eq(by(t, 'keystone 631 ksShadowTwin')['status'], TK.PASS, 'keystone: its own row grows -> pass')
ok('grew' in by(t, 'keystone 631 ksShadowTwin')['detail'], 'pass says what was seen')
eq(by(t, 'keystone 383 ksBlackbloodCreed')['status'], TK.NOT_OBSERVABLE, 'keystone: no probe -> not observable')
ok('a damage factor' in by(t, 'keystone 383 ksBlackbloodCreed')['detail'], 'with the reason')
ok('allocated' in by(t, 'keystone 383 ksBlackbloodCreed')['detail'], 'and the node was saved')
eq(by(t, 'keystone 900 ksCleavingArc')['status'], TK.NOT_TESTED, 'keystone: more points than the character has -> not tested')
eq(s.nodes, [], 'tree clean after the keystones')

resets = [x for x in s.requests if x[1] == 'resetPreset']
eq(len(resets), 2, 'a reset after each node that was planned')
eq(len(t.resets), 2, 'the resets are recorded')

# the old shared row is not the keystone's: a labelled flag needs its own row, in its own tab
s2 = FakeServer(points=30)
s2.row_key = 'p:Keystones'
t2 = run(KTABLE, s2, io=FakeIO(s2, proc_after=40), window=100, poll=10)
eq(by(t2, 'keystone 631 ksShadowTwin')['status'], TK.FAIL, 'keystone: only the shared "Keystones" row grew -> fail')
ok('p:Keystone: Shadow Twin' in by(t2, 'keystone 631 ksShadowTwin')['detail'], 'the failure names the row it looked for')
s2 = FakeServer(points=30)
s2.row_tab = 1
t2 = run(KTABLE, s2, io=FakeIO(s2, proc_after=40), window=100, poll=10)
eq(by(t2, 'keystone 631 ksShadowTwin')['status'], TK.FAIL, 'keystone: the row grew in another tab -> fail')
HEAL_TABLE = {'classes': {'thief': [dict(key_row(631, 'ksUndyingRage'), probe={'mode': 'combatlog', 'row': 'p:Keystone: Undying Rage',
                                                                                   'tab': 'healing', 'needs': 'melee hits'})]}, 'elements': []}
s2 = FakeServer(points=30)
s2.row_key, s2.row_tab = 'p:Keystone: Undying Rage', 1
t2 = run(HEAL_TABLE, s2, io=FakeIO(s2, proc_after=40), window=100, poll=10)
eq(by(t2, 'keystone 631 ksUndyingRage')['status'], TK.PASS, 'keystone: a row of the healing tab is read from that tab')

# nothing shows in the combat log
s = FakeServer(points=30, procs=False)
t = run(KTABLE, s, io=FakeIO(s, proc_after=40), window=60, poll=10)
r = by(t, 'keystone 631 ksShadowTwin')
eq(r['status'], TK.FAIL, 'keystone: the effect missing -> fail')
ok('needs: a second enemy' in r['detail'], 'the failure says what the hunt needs')
eq(s.nodes, [], 'tree clean after a failed keystone')
eq([x[1] for x in s.requests if x[1] == 'resetPreset'], ['resetPreset', 'resetPreset'], 'reset after the failed one too')

# the bot leaves the game while watching: that says nothing about the node. Its partial results are dropped, the run is not
# finished, and after the new login the same KeyTest goes on at the same node (the 1240 "not tested: the bot left the game"
# of the first live run came from bots that died and never resumed)
s = FakeServer(points=30)
io = FakeIO(s, proc_after=10 ** 6)
io.leave_after = 30
t = TK.KeyTest(KTABLE, 'Tester Aaa', 0, window=100, poll=10)
asyncio.run(t.run(io))
eq(t.finished, False, 'cut off: not finished')
eq(by(t, 'keystone 631 ksShadowTwin'), None, 'the cut-off node has no result')
eq(t.pos, 0, 'and is still the one to do')
eq(t.resets, [], 'a reset from a bot out of the game is no result either')
s.alive, s.clock = True, 0
asyncio.run(t.run(FakeIO(s, proc_after=40)))
eq(t.finished, True, 'after the new login the run goes on and ends')
eq(by(t, 'keystone 631 ksShadowTwin')['status'], TK.PASS, 'the cut-off node is done again')
eq(s.nodes, [], 'tree clean')

# the run ends for good while a bot is cut off: the nodes it did not get to are not tested, with the reason
s = FakeServer(points=30)
io = FakeIO(s)
io.leave_after = 0
t = TK.KeyTest(KTABLE, 'Tester Aaa', 0)
asyncio.run(t.run(io))
t.finish('the run ended')
eq(t.finished, True, 'finish ends it')
eq(by(t, 'keystone 631 ksShadowTwin')['status'], TK.NOT_TESTED, 'a node never reached: not tested')
eq(by(t, 'keystone 383 ksBlackbloodCreed')['detail'], 'the run ended', 'with the reason')

# no answer to planApply while the bot is in the game: the tree is read back to say what happened
for saved, want in ((True, 'the reply was lost'), (False, 'nothing saved')):
    s = FakeServer(points=30)
    orig = s.handle

    def silent(opname, action, data, s=s, orig=orig, saved=saved):
        if action == 'planApply':
            s.requests.append((opname, action, data))
            if saved:
                s.nodes = list(data['nodes'])
            return None
        return orig(opname, action, data)

    s.handle = silent
    t = run(KTABLE, s, io=FakeIO(s, proc_after=40), window=30, poll=10)
    r = by(t, 'keystone 631 ksShadowTwin')
    eq(r['status'], TK.FAIL, 'no answer to planApply fails (%s)' % want)
    ok(want in r['detail'], 'and says %s: %s' % (want, r['detail']))

# statTotals unanswered once: asked again
s = FakeServer(points=60)
s.mastery_effects[665] = MEFF
orig = s.handle
calls = {'n': 0}


def flaky(opname, action, data):
    if action == 'statTotals':
        calls['n'] += 1
        if calls['n'] == 1:
            return None
    return orig(opname, action, data)


s.handle = flaky
t = run(TABLE, s)
eq(by(t, 'mastery 665 effect 1')['status'], TK.PASS, 'statTotals asked a second time')

# the server refuses the keystone plan
s = FakeServer(points=30)
s.refuse_plan = 'Node 631 belongs to another class.'
t = run(KTABLE, s, io=FakeIO(s, proc_after=40), window=30, poll=10)
eq(by(t, 'keystone 631 ksShadowTwin')['status'], TK.FAIL, 'a refused keystone plan fails')
eq(s.requests[-1][1], 'resetPreset', 'reset sent after the refusal')

# a plan the server said ok to but did not save
s = FakeServer(points=30)
orig = s.handle


def lying(opname, action, data):
    if action == 'planApply':
        s.requests.append((opname, action, data))
        return {'action': 'planResult', 'data': {'ok': True, 'message': ''}}
    return orig(opname, action, data)


s.handle = lying
t = run(KTABLE, s, io=FakeIO(s, proc_after=40), window=30, poll=10)
eq(by(t, 'keystone 631 ksShadowTwin')['status'], TK.FAIL, 'a plan accepted but not saved fails')

# ---------------------------------------------------------------- the reset the character cannot pay
s = FakeServer(points=60, gold=100)
s.mastery_effects[665] = MEFF
both = {'classes': {'thief': [MASTERY, key_row(631, 'ksShadowTwin'), key_row(383, 'ksBlackbloodCreed', 'none', (7,))]},
        'elements': KT.ELEMENTS}
t = run(both, s, io=FakeIO(s, proc_after=40), window=30, poll=10)
eq(by(t, 'mastery 665 effect 1')['status'], TK.PASS, 'the first node is tested')
eq(t.resets[0]['ok'], False, 'the reset the gold cannot pay is recorded as not done')
ok('You need' in t.resets[0]['detail'], 'with the server message')
eq(by(t, 'keystone 631 ksShadowTwin')['status'], TK.NOT_TESTED, 'later nodes are not tested')
ok('could not be cleared' in by(t, 'keystone 631 ksShadowTwin')['detail'], 'because the tree could not be cleared')
eq([x[1] for x in s.requests if x[1] == 'resetPreset'], ['resetPreset'], 'no second reset is sent at a refusal')
text = '\n'.join(TK.report_lines(t.results, t.resets))
ok('reset not done: You need' in text, 'the report says the reset was not done')

# leftovers on the tree at the start are cleared first
s = FakeServer(points=60)
s.nodes = [1001, 1002]
s.mastery_effects[665] = MEFF
t = run(TABLE, s)
eq(s.requests[2][1], 'resetPreset', 'a tree left from earlier is reset before the test')
eq(by(t, 'mastery 665 effect 1')['status'], TK.PASS, 'and the node is tested on a clean tree')

# the class is not in the table / no answer
t = run({'classes': {}}, FakeServer(cls='lich'))
eq(t.results[0]['status'], TK.NOT_TESTED, 'a class without nodes is not tested')
s = FakeServer()
s.none_for = ('requestNodesUnlocked',)
eq(run(TABLE, s).results[0]['status'], TK.FAIL, 'no answer to the tree request fails')

# the bots of one class start at different nodes
two = {'classes': {'thief': [key_row(1, 'ksShadowTwin', 'none'), key_row(2, 'ksBlackbloodCreed', 'none'),
                             key_row(3, 'ksLivingShadow', 'none')]}, 'elements': []}
eq([r['node'] for r in run(two, FakeServer(points=30), index=0).results], [1, 2, 3], 'first bot: from the first node')
eq([r['node'] for r in run(two, FakeServer(points=30), index=1).results], [2, 3, 1], 'second bot: from the second')
eq([r['node'] for r in run(two, FakeServer(points=30), index=4).results], [2, 3, 1], 'the start wraps around')

# ---------------------------------------------------------------- the generated data
sc = json.load(open(os.path.join(HERE, 'tester_scenarios.json')))['keytest']
keys = KT.class_keys(os.path.join(CHAOS, 'chaos_constants.lua'))
eq(sorted(sc['classes']), sorted(keys), 'every class of the server has a list')
tree = KT.load_tree(os.path.join(CHAOS, 'passivetree_data.lua'))
ok(len(tree['nodes']) > 600, 'the tree was read (%d nodes)' % len(tree['nodes']))
for cls, rows in sc['classes'].items():
    ok(rows, cls + ': has nodes')
    ok(any(r['kind'] == 'keystone' for r in rows), cls + ': has a keystone')
    for r in rows:
        chain = [tree['root']] + r['path'] + [r['id']]
        for a, b in zip(chain, chain[1:]):
            ok(b in tree['nodes'][a]['n'], '%s %d: %d-%d are neighbours' % (cls, r['id'], a, b))
        ok(all(KT.allowed(tree['nodes'][n], cls) for n in chain[1:]), '%s %d: the route is the class\'s' % (cls, r['id']))
        ok(len(set(chain)) == len(chain), '%s %d: the route has no loop' % (cls, r['id']))
        if r['kind'] == 'mastery':
            eq(len(r['effects']), len(tree['nodes'][r['id']]['m']), '%s %d: every effect listed' % (cls, r['id']))
        else:
            ok(r['probe'] and r['probe']['mode'] in ('combatlog', 'none'), '%s %d: a probe or a reason' % (cls, r['id']))
            if r['probe']['mode'] == 'none':
                ok(r['probe']['why'], '%s %d: the reason' % (cls, r['id']))
total = sum(len(v) for v in sc['classes'].values())
masteries = sum(1 for v in sc['classes'].values() for r in v if r['kind'] == 'mastery')
ok(masteries >= 4, 'the four mastery nodes are listed for their classes')
ok(total > 100, 'the table lists %d nodes' % total)
# the stats the table calls observable are the ones the totals window sends (passivetree_totals_core.lua)
totals_src = open(os.path.join(CHAOS, 'passivetree_totals_core.lua')).read()
for stat in KT.ATTRIBUTES:
    ok('"%s"' % stat in totals_src, 'totals_core lists the attribute ' + stat)
tot_lua = open(os.path.join(CHAOS, 'passivetree_totals.lua')).read()
for stat in KT.DAMAGE:
    ok('"%s"' % stat in tot_lua, 'the totals window lists ' + stat)
ok('criticalHitChance' in totals_src and 'criticalHitAmount' in totals_src, 'the totals carry the tree crit')
# every flag with a combat log row of its own is wired in the server: its name is passed to the labels in one of the files
labels = KT.load_labels(os.path.join(CHAOS, 'keystone_labels_config.lua'))
wired = ''.join(open(os.path.join(CHAOS, f)).read() for f in ('passivetree_keystones.lua', 'archetypes.lua', 'templar_combat.lua',
                                                              'monk_combat.lua'))
for flag, label in sorted(labels.items()):
    ok('"%s"' % flag in wired, flag + ' is passed to ChaosKeystoneLabels in the keystone scripts')
    ok(label['tab'] in KT.TABS, flag + ' has a known tab')
eq(sorted(KT.NEEDS), sorted(f for f, d in labels.items() if d['observe']), 'NEEDS = the observable labels')
eq(labels['ksCleavingArc']['row'], 'p:Keystone: Cleaving Arc', 'a proc row key: kind, prefix, name')
eq(labels['ksDeadeye']['row'], 'k:Keystone: Deadeye', 'a note row key')
eq(labels['ksUndyingRage']['tab'], 'healing', 'a heal is in the healing tab')
ok(labels['ksOvergrowth']['observe'] is False and labels['ksOvergrowth']['why'], 'a flag a bot cannot make fire says why')
# the observable count the report names (O255): flags with a row of their own, over the nodes of the table
shown = sum(1 for v in sc['classes'].values() for r in v if r['kind'] == 'keystone' and r['probe']['mode'] == 'combatlog')
allks = sum(1 for v in sc['classes'].values() for r in v if r['kind'] == 'keystone')
ok(shown >= 190 and allks == 242, 'observable keystone nodes: %d of %d' % (shown, allks))
print('observable keystone nodes: %d of %d' % (shown, allks))
log_cfg = open(os.path.join(CHAOS, 'combatlog_config.lua')).read()
ok('["passivetree_keystones.lua"] = {name = "Keystones", kind = "p"' in log_cfg, 'the combat log keeps the "Keystones" fallback label')
# a flag that is neither probed nor explained stops the generator
bad_dir = None
try:
    import tempfile
    import shutil
    bad_dir = tempfile.mkdtemp()
    for f in ('passivetree_data.lua', 'chaos_constants.lua', 'keystone_labels_config.lua'):
        shutil.copy(os.path.join(CHAOS, f), bad_dir)
    p = os.path.join(bad_dir, 'passivetree_data.lua')
    text = open(p).read().replace('{ksGraveCovenant=1}', '{ksBrandNewOne=1}', 1)
    open(p, 'w').write(text)
    try:
        KT.build(bad_dir)
        ok(False, 'a keystone flag without a probe or a reason must stop the generator')
    except SystemExit as e:
        ok('ksBrandNewOne' in str(e), 'the generator names the flag it has no probe for')
finally:
    if bad_dir:
        shutil.rmtree(bad_dir, ignore_errors=True)

# ---------------------------------------------------------------- the bot side
class Conn:
    def __init__(self):
        self.sent = []
        self.w = self

    def send(self, data):
        self.sent.append(data)

    async def drain(self):
        pass


class Args:
    host = '10.0.0.1'
    ops = {'passivetree': 65, 'combatLog': 204}
    keystones = True
    keytest_table = TABLE


res = T.Results(1)
entry = {'account': 'tstbot0123456789', 'password': 'x', 'name': 'Tester Aaa', 'class': 'Thief', 'level': 300}
bot = T.TesterBot(0, entry, Args(), 1, res, {'rotation': [], 'heal': None})
bot.conn, bot.alive = Conn(), True


async def ask():
    io = T.KeyIO(bot, {'stop': False})
    task = asyncio.ensure_future(io.request('passivetree', 'statTotals', {}, ['statTotals'], 2))
    await asyncio.sleep(0.05)
    sent = bot.conn.sent[-1]
    eq((sent[0], sent[1]), (0x32, 65), 'the request goes out as an extended opcode 65')
    ok(b'"action":"statTotals"' in sent, 'with its action')
    bot.on_extended(65, json.dumps({'action': 'sendPoints', 'data': 3}))   # another answer: ignored
    bot.on_extended(66, json.dumps({'action': 'statTotals', 'data': {}}))  # another opcode: ignored
    await asyncio.sleep(0.01)
    ok(not task.done(), 'other answers do not end the wait')
    bot.on_extended(65, json.dumps({'action': 'statTotals', 'data': {'crit': {}}}))
    got = await task
    eq(got['action'], 'statTotals', 'the awaited answer is returned')
    eq(bot.waiters, [], 'the waiter is gone')
    eq(await io.request('passivetree', 'statTotals', {}, ['statTotals'], 0.05), None, 'no answer in time: None')
    eq(bot.waiters, [], 'the waiter is gone after a timeout')
    n = len(bot.conn.sent)
    eq(await io.request('combatLog', 'close', {}, [], 0), None, 'a request nobody answers returns at once')
    eq(len(bot.conn.sent), n + 1, 'but is sent')
    eq(await io.request('nosuchop', 'x', {}, ['x'], 0.05), None, 'an opcode the server does not have: None')
    bot.alive = False
    eq(await io.request('passivetree', 'statTotals', {}, ['statTotals'], 0.05), None, 'a bot out of the game sends nothing')
    bot.alive = True


asyncio.run(ask())

# do_keytest on a bot with a mocked connection: the results land in the run's results and the report
srv = FakeServer(points=60)
srv.mastery_effects[665] = MEFF


async def play():
    b = T.TesterBot(1, dict(entry), Args(), 1, res, {'rotation': [], 'heal': None})
    b.conn, b.alive = Conn(), True
    real_sleep = asyncio.sleep

    async def fast(sec, *a, **k):
        await real_sleep(0)

    class Io(T.KeyIO):
        async def request(self, opname, action, data, expect, timeout):
            return await FakeIO(srv).request(opname, action, data, expect, timeout)

        async def sleep(self, seconds):
            await real_sleep(0)

        async def go(self, place):
            self.bot.stay = place == 'town'
            return True

    orig_io, orig_sleep = T.KeyIO, T.asyncio.sleep
    T.KeyIO, T.asyncio.sleep = Io, fast
    try:
        return await b.do_keytest({'stop': False})
    finally:
        T.KeyIO, T.asyncio.sleep = orig_io, orig_sleep


eq(asyncio.run(play()), True, 'do_keytest: no node failed')
eq(len(res.d['keytest']), 4, 'four mastery effects recorded')
eq(len(res.d['keytest_resets']), 1, 'and the reset')
report = TC.build_report(res.d, TC.parse_log([]))
ok('== Passive tree keystones and masteries (4 nodes: 3 pass, 0 fail, 1 not observable, 0 not tested)' in report,
   'the report section with the counts: ' + report[-900:])
ok('PASS' in report and 'NOT OBSERVABLE' in report, 'the report lists the nodes')
eq(T.Results(1).d.get('keytest'), None, 'a run without --keystones has no section')
ok('Passive tree keystones' not in TC.build_report(T.Results(1).d, TC.parse_log([])), 'and the report has none')

# a failure comes first in the report
rows = [{'bot': 'A', 'cls': 'thief', 'node': 2, 'kind': 'keystone', 'what': 'keystone 2 x', 'status': TK.PASS, 'detail': 'd'},
        {'bot': 'A', 'cls': 'thief', 'node': 1, 'kind': 'keystone', 'what': 'keystone 1 y', 'status': TK.FAIL, 'detail': 'd'}]
lines = TK.report_lines(rows, [{'bot': 'A', 'ok': True, 'detail': 'reset'}])
ok(lines[1].lstrip().startswith('FAIL'), 'failures are listed first')
ok(lines[-1].startswith('  tree resets: 1 sent, 0 refused'), 'the reset count')

# the options
a = T.parse(['run', '--server-dir', '/x', '--key-file', '/k', '--keystones'])
eq(a.keystones, True, '--keystones is parsed')
eq(T.parse(['run', '--server-dir', '/x', '--key-file', '/k']).keystones, False, 'off by default')
eq(T.parse(['setup', '--server-dir', '/x']).keystones, False, 'setup does not have it on')

for f in FAILS:
    print('FAIL ' + f)
print('tester_keystones_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)

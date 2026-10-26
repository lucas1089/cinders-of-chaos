#!/usr/bin/env python3
"""The keystone and mastery scenario of the tester bots (O249; server/README.md "Tester bots", Keystones and masteries).

testers.py run --scenarios FILE --keystones: each bot, once per run, takes the nodes of its class from the "keytest"
section of tester_scenarios.json (tester_keytree.py: every keystone and mastery the class may hold, the route to it, how a
bot can see that it works) and for each node, as a player does it (extended opcode 65, the tree window's requests):
  1. clears the tree if something is left on it (resetPreset)
  2. plans the route (planApply), reads the totals of the tree window (statTotals)
  3. mastery: plans the node with its first effect, reads the totals again; the stats the totals show must grow by exactly
     what the effect gives; every other effect is chosen with masteryChoose (priced: refused for lack of gold = not tested)
     keystone: plans route and node together; a flag with its own row in the combat log (opcode 204, "Keystone: <name>",
     keystone_labels_config.lua) must make that row grow while the bot hunts; any other flag is "not observable", with the reason
  4. resets the tree (resetPreset), always, also after an error, and reads it back
Result per node: pass | fail | not observable | not tested (not enough points, a reset or a change of effect the character
cannot pay, the bot left the game). Nothing is faked: a node whose effect a client cannot see is reported as that.
No god command, no development key: only the requests of the tree window and the DPS meter.

The pure flow lives here and talks to the game through an `io` object (testers.py KeyIO): async request(opname, action, data,
expect, timeout) -> the first answer with one of the `expect` actions, or None; async sleep(seconds); alive(). The tests
(tester_keystones_test.py) give it a mocked server. Standard library only.
"""
import json

PASS, FAIL, NOT_OBSERVABLE, NOT_TESTED = 'pass', 'fail', 'not observable', 'not tested'
STATUSES = (FAIL, PASS, NOT_OBSERVABLE, NOT_TESTED)
TREE, LOG = 'passivetree', 'combatLog'
GAP = 1.2         # seconds before each saving request: the server answers one plan, choice or reset a second per player
ANSWER = 8.0      # seconds a request waits for its answer
WINDOW = 150.0    # seconds a keystone with extra hits may take to show its first one
POLL = 15.0       # seconds between two looks at the combat log
TOLERANCE = 0.15  # totals are rounded to one decimal
PROC_ROW = 'p:Keystones'   # the row of a keystone proc that has no label of its own (the fallback of combatlog_config.lua)
TABS = {'dealt': 0, 'healing': 1, 'taken': 2, 'received': 3}   # tab of the combat log state (v.t)


def class_key(name):
    """'Bone Lord' -> 'bonelord': the class key of a vocation name (the answer of the tree says it itself, sendNodes cls)"""
    return ''.join(ch for ch in str(name or '').lower() if ch.isalnum())


def totals_of(data):
    """the answer of statTotals -> {stat: raw tree sum} for the stats a client can read: the attributes and the damage
    percents (raw), the critical chance and amount of the tree"""
    out = {}
    if not isinstance(data, dict):
        return out
    for row in data.get('attributes') or []:
        if isinstance(row, dict) and 'k' in row:
            out[row['k']] = float(row.get('raw') or 0)
    for row in data.get('damage') or []:
        if isinstance(row, dict) and 'k' in row:
            out[row['k']] = float(row.get('raw') or 0)
    crit = data.get('crit') if isinstance(data.get('crit'), dict) else {}
    for key, part in (('criticalHitChance', 'chance'), ('criticalHitAmount', 'amount')):
        sub = crit.get(part)
        if isinstance(sub, dict):
            out[key] = float(sub.get('tree') or 0)
    return out


def expected_delta(observable, elements):
    """the change of totals_of() an effect must make: multiIncrement raises every element's damage percent"""
    out = {}
    for stat, value in observable.items():
        if stat == 'multiIncrement':
            for el in elements:
                out[el] = out.get(el, 0) + value
        else:
            out[stat] = out.get(stat, 0) + value
    return out


def compare(before, after, expected):
    """[] when every expected stat grew by its value (a stat missing from the totals is 0), else one text per mismatch"""
    bad = []
    for stat, want in sorted(expected.items()):
        got = after.get(stat, 0) - before.get(stat, 0)
        if abs(got - want) > TOLERANCE:
            bad.append('%s changed by %g, the effect gives %g' % (stat, round(got, 2), want))
    return bad


def proc_hits(state, row_key=PROC_ROW, tab=0):
    """the hits of one row of the damage dealt tab in a combat log state (v.t[0].r = [[key, kind, name, icon, total, hits,
    crits, max, over]]); (hits, total), (0, 0) without the row"""
    try:
        rows = state['v']['t'][tab]['r']
    except (KeyError, IndexError, TypeError):
        return 0, 0
    for row in rows or []:
        if isinstance(row, list) and row and row[0] == row_key:
            return int(row[5] or 0), int(row[4] or 0)
    return 0, 0


class KeyTest:
    def __init__(self, keytest, bot_name='?', index=0, window=WINDOW, poll=POLL, gap=GAP):
        self.table = keytest or {}
        self.bot = bot_name
        self.index = index
        self.window, self.poll, self.gap = window, poll, gap
        self.results = []   # [{bot, cls, node, kind, what, status, detail}]
        self.resets = []    # [{ok, detail}] every reset sent
        self.cls = None
        self.preset = 1
        self.free = 0
        self.nodes = []
        self.dirty = False  # something may be on the tree (a plan was accepted, or nodes were there at the start)
        self.stuck = None   # why the tree could not be cleared: every node after it is not tested

    # ------------------------------------------------------------------ results
    def add(self, node, kind, what, status, detail):
        self.results.append({'bot': self.bot, 'cls': self.cls, 'node': node, 'kind': kind, 'what': what,
                             'status': status, 'detail': detail})

    # ------------------------------------------------------------------ the tree window's requests
    async def read_tree(self, io):
        """sendNodes + sendPoints: class, preset, saved nodes, free points; False when no answer"""
        a = await io.request(TREE, 'requestNodesUnlocked', {}, ['sendNodes'], ANSWER)
        if not a:
            return False
        d = a.get('data') or {}
        self.cls = d.get('cls') or self.cls or None
        self.preset = d.get('preset') or self.preset or 1
        self.nodes = [n for n in d.get('nodes') or [] if isinstance(n, int)]
        p = await io.request(TREE, 'requestPoints', {}, ['sendPoints'], ANSWER)
        if p is not None and isinstance(p.get('data'), (int, float)):
            self.free = int(p['data'])
        return True

    async def totals(self, io):
        await io.sleep(0.4)
        a = await io.request(TREE, 'statTotals', {}, ['statTotals'], ANSWER)
        return totals_of(a.get('data')) if a else None

    async def plan(self, io, nodes, masteries=None):
        """planApply -> (ok, message)"""
        await io.sleep(self.gap)
        a = await io.request(TREE, 'planApply', {'nodes': list(nodes), 'masteries': masteries or []}, ['planResult'], ANSWER)
        if not a:
            return False, 'no answer to planApply'
        d = a.get('data') or {}
        if d.get('ok'):
            self.dirty = True
        return bool(d.get('ok')), str(d.get('message') or '')

    async def reset(self, io):
        """resetPreset (always sent when the character is in game): True when the tree reads back empty"""
        if not io.alive():
            self.resets.append({'bot': self.bot, 'ok': False, 'detail': 'the bot was out of the game'})
            return False
        await io.sleep(self.gap)
        a = await io.request(TREE, 'resetPreset', self.preset, ['sendNodes', 'sendMessage'], ANSWER)
        if not a:
            self.resets.append({'bot': self.bot, 'ok': False, 'detail': 'no answer to resetPreset'})
            return False
        d = a.get('data') or {}
        if a.get('action') == 'sendNodes':
            left = [n for n in d.get('nodes') or []]
            self.nodes = left
            ok = not left
            self.dirty = not ok
            self.resets.append({'bot': self.bot, 'ok': ok, 'detail': 'reset' if ok else '%d nodes left after the reset' % len(left)})
            return ok
        text = str(d.get('message') or '')
        # "There is nothing to reset." is an empty tree: clean
        ok = 'nothing to reset' in text
        self.resets.append({'bot': self.bot, 'ok': ok, 'detail': text or 'refused'})
        if ok:
            self.nodes, self.dirty = [], False
        else:
            self.stuck = text or 'refused'  # every later node is not tested: they would need a clean tree
        return ok

    # ------------------------------------------------------------------ one node
    async def clean(self, io):
        """True when the tree is empty (a reset is sent when it is not)"""
        if self.stuck:
            return False
        if self.dirty and not await self.reset(io):
            self.stuck = self.stuck or self.resets[-1]['detail']
            return False
        return True

    def stuck_text(self):
        return 'not tested: the tree could not be cleared (%s)' % self.stuck

    async def keystone(self, io, row):
        nid, flag = row['id'], row['flag']
        what = 'keystone %d %s' % (nid, flag)
        need = len(row['path']) + 1
        if not await self.clean(io):
            return self.add(nid, 'keystone', what, NOT_TESTED, self.stuck_text()[len('not tested: '):])
        if need > self.free:
            return self.add(nid, 'keystone', what, NOT_TESTED, 'needs %d points, the character has %d' % (need, self.free))
        try:
            ok, msg = await self.plan(io, row['path'] + [nid])
            if not ok:
                return self.add(nid, 'keystone', what, FAIL, 'the server refused the plan: %s' % (msg or 'no message'))
            if not await self.read_tree(io) or nid not in self.nodes:
                return self.add(nid, 'keystone', what, FAIL, 'the plan was accepted but the node is not in the saved tree')
            probe = row.get('probe') or {}
            if probe.get('mode') != 'combatlog':
                return self.add(nid, 'keystone', what, NOT_OBSERVABLE,
                                'allocated (%d nodes saved); effect not observable: %s' % (len(self.nodes), probe.get('why', '?')))
            await self.watch_log(io, nid, what, probe)
        finally:
            await self.reset(io)

    async def watch_log(self, io, nid, what, probe):
        """the keystone's row of the combat log (its own tab) must grow while the bot hunts"""
        row_key = probe.get('row') or PROC_ROW
        tab = TABS.get(probe.get('tab'), 0)
        a = await io.request(LOG, 'open', {'seg': 's'}, ['state'], ANSWER)
        if not a:
            return self.add(nid, 'keystone', what, NOT_TESTED, 'the combat log did not answer')
        base, _ = proc_hits(a.get('data'), row_key, tab)
        waited, seen = 0.0, (0, 0)
        while waited < self.window and io.alive():
            await io.sleep(self.poll)
            waited += self.poll
            s = await io.request(LOG, 'seg', {'id': 's'}, ['state'], ANSWER)
            if s:
                seen = proc_hits(s.get('data'), row_key, tab)
                if seen[0] > base:
                    await io.request(LOG, 'close', {}, [], 0)
                    return self.add(nid, 'keystone', what, PASS, 'the "%s" row of the combat log grew: %d hits (%d before), %d damage'
                                    % (row_key, seen[0], base, seen[1]))
        await io.request(LOG, 'close', {}, [], 0)
        if not io.alive():
            return self.add(nid, 'keystone', what, NOT_TESTED, 'the bot left the game before a hit showed')
        return self.add(nid, 'keystone', what, FAIL, 'no "%s" row growth in %d s of hunting (%d hits before, %d after); the hunt '
                        'needs: %s' % (row_key, int(waited), base, seen[0], probe.get('needs', '?')))

    async def mastery(self, io, row, elements):
        nid = row['id']
        effects = row['effects']
        label = lambda e: 'mastery %d effect %d' % (nid, e['choice'])  # noqa: E731
        need = len(row['path']) + 1
        if not await self.clean(io):
            for e in effects:
                self.add(nid, 'mastery', label(e), NOT_TESTED, self.stuck_text()[len('not tested: '):])
            return
        if need > self.free:
            for e in effects:
                self.add(nid, 'mastery', label(e), NOT_TESTED, 'needs %d points, the character has %d' % (need, self.free))
            return
        try:
            if row['path']:
                ok, msg = await self.plan(io, row['path'])
                if not ok:
                    return self._all(nid, effects, label, FAIL, 'the server refused the route: %s' % (msg or 'no message'))
            base = await self.totals(io)
            if base is None:
                return self._all(nid, effects, label, FAIL, 'no answer to statTotals')
            ok, msg = await self.plan(io, [nid], [{'id': nid, 'choice': 1}])
            if not ok:
                return self._all(nid, effects, label, FAIL, 'the server refused the node: %s' % (msg or 'no message'))
            for e in effects:
                if e['choice'] > 1 and e['observable']:
                    await io.sleep(self.gap)
                    c = await io.request(TREE, 'masteryChoose', {'id': nid, 'choice': e['choice']}, ['planResult'], ANSWER)
                    d = (c or {}).get('data') or {}
                    if not c or not d.get('ok'):
                        self.add(nid, 'mastery', label(e), NOT_TESTED,
                                 'the change of effect was not made: %s' % (d.get('message') or 'no answer'))
                        continue
                if e['choice'] > 1 and not e['observable']:
                    self.add(nid, 'mastery', label(e), NOT_OBSERVABLE, 'effect not observable: ' + ', '.join(e['other']))
                    continue
                after = await self.totals(io)
                if after is None:
                    self.add(nid, 'mastery', label(e), FAIL, 'no answer to statTotals')
                elif not e['observable']:
                    self.add(nid, 'mastery', label(e), NOT_OBSERVABLE, 'effect not observable: ' + ', '.join(e['other']))
                else:
                    bad = compare(base, after, expected_delta(e['observable'], elements))
                    seen = ', '.join('%s %+g' % kv for kv in sorted(e['observable'].items()))
                    if bad:
                        self.add(nid, 'mastery', label(e), FAIL, 'the totals do not show the effect (%s): %s' % (seen, '; '.join(bad)))
                    else:
                        extra = '; not observable: ' + ', '.join(e['other']) if e['other'] else ''
                        self.add(nid, 'mastery', label(e), PASS, 'the totals grew by the effect (%s)%s' % (seen, extra))
        finally:
            await self.reset(io)

    def _all(self, nid, effects, label, status, detail):
        for e in effects:
            self.add(nid, 'mastery', label(e), status, detail)

    # ------------------------------------------------------------------ the run
    async def run(self, io):
        """every node of the bot's class, from its own start (self.index) around the list, so the bots of one class test
        different nodes first"""
        if not await self.read_tree(io):
            self.add(0, 'tree', 'passive tree', FAIL, 'no answer to requestNodesUnlocked')
            return self.results
        self.dirty = bool(self.nodes)
        rows = (self.table.get('classes') or {}).get(self.cls) or (self.table.get('classes') or {}).get(class_key(self.cls))
        if not rows:
            self.add(0, 'tree', 'passive tree', NOT_TESTED, 'no keystone or mastery in the table for the class %r' % self.cls)
            return self.results
        start = self.index % len(rows)
        order = rows[start:] + rows[:start]
        elements = self.table.get('elements') or []
        for i, row in enumerate(order):
            if not io.alive():
                for r in order[i:]:
                    self.skip(r, 'the bot left the game')
                break
            if self.stuck:
                self.skip(row, self.stuck_text()[len('not tested: '):])
                continue
            if row['kind'] == 'mastery':
                await self.mastery(io, row, elements)
            else:
                await self.keystone(io, row)
        return self.results

    def skip(self, row, why):
        if row['kind'] == 'mastery':
            for e in row['effects']:
                self.add(row['id'], 'mastery', 'mastery %d effect %d' % (row['id'], e['choice']), NOT_TESTED, why)
        else:
            self.add(row['id'], 'keystone', 'keystone %d %s' % (row['id'], row['flag']), NOT_TESTED, why)

    def summary(self):
        counts = {s: 0 for s in STATUSES}
        for r in self.results:
            counts[r['status']] += 1
        return counts


def report_lines(rows, resets=None):
    """the section of the bug report: the counts, every failure first, then the others; rows = every bot's results"""
    counts = {s: 0 for s in STATUSES}
    for r in rows:
        counts[r['status']] = counts.get(r['status'], 0) + 1
    L = ['== Passive tree keystones and masteries (%d nodes: %d pass, %d fail, %d not observable, %d not tested)' % (
        len(rows), counts[PASS], counts[FAIL], counts[NOT_OBSERVABLE], counts[NOT_TESTED])]
    order = {s: i for i, s in enumerate(STATUSES)}
    for r in sorted(rows, key=lambda r: (order.get(r['status'], 9), str(r.get('cls')), r.get('node', 0), r.get('what', ''))):
        L.append('  %-14s %-12s %-26s %s [%s]' % (r['status'].upper(), r.get('cls') or '?', r.get('what', '?'),
                                                  r.get('detail', ''), r.get('bot', '?')))
    bad = [x for x in (resets or []) if not x.get('ok')]
    L.append('  tree resets: %d sent, %d refused or not read back' % (len(resets or []), len(bad)))
    seen = set()
    for x in bad:
        text = '%s [%s]' % (x.get('detail'), x.get('bot', '?'))
        if text not in seen:
            seen.add(text)
            L.append('    reset not done: ' + text)
    return L


def dump(results):
    return json.dumps(results, sort_keys=True)

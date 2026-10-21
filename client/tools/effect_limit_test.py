#!/usr/bin/env python3
"""Model test of base patch 0116 (a busy tile drew its oldest effects and dropped the newest).

The engine is not built in CI, so this checks the patch text and runs a model of what Tile draws:
  * the ids that always draw (chaosAlwaysDrawEffect, read from the patch) are exactly the combat feedback of the
    server: crit_burst, dodge_whoosh, reflect_aegis and the six imbue_* of server/data/lib/chaos_fx.lua, and
    reflect_bubble of server/data/lib/chaos_pack_fx_ids.lua. A renumbered effect fails here;
  * both draw loops (drawTop, drawGroundEffects) skip an older effect only when it is not one of those, the budget is
    effetsLimit() + 1 (what the stock loop drew), and addThing drops a running copy of the same id;
  * a tile of a fighting creature: condition auras re-sent as each copy ends, blasts and splashes on every hit, then a
    crit, a dodge and a reflect. With the stock rules (append, draw index limit..0) none of the three draws at the auto
    limit of 10 or below (the bug); with the rules of 0116 each one draws at every limit {20, 10, 7, 4, 2}, the newest
    effects draw, and a re-sent aura never holds two copies.
Run: python3 -I client/tools/effect_limit_test.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH = os.path.join(ROOT, 'client', 'base-patches', '0116-newest-effects-first.patch')
CHAOS_FX = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_fx.lua')
PACK_IDS = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pack_fx_ids.lua')
LIMITS = (20, 10, 7, 4, 2)  # AdaptiveRenderer::effetsLimit() by render speed

checks = 0


def ok(cond, msg):
    global checks
    if not cond:
        print('FAIL: ' + msg)
        sys.exit(1)
    checks += 1


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def added(patch_text):
    return '\n'.join(line[1:] for line in patch_text.splitlines() if line.startswith('+') and not line.startswith('+++'))


def priority_ids(code):
    """the ids of chaosAlwaysDrawEffect: its `id >= a && id <= b` ranges and `id == n` terms"""
    m = re.search(r'static bool chaosAlwaysDrawEffect\([^)]*\)\s*\{(.*?)\n\}', code, re.S)
    ok(m is not None, 'patch 0116 defines chaosAlwaysDrawEffect')
    body = m.group(1)
    ids = set()
    for a, b in re.findall(r'id >= (\d+) && id <= (\d+)', body):
        ids.update(range(int(a), int(b) + 1))
    body = re.sub(r'id >= \d+ && id <= \d+', '', body)
    ids.update(int(n) for n in re.findall(r'id == (\d+)', body))
    ok('isTopEffect()' in body, 'top effects keep drawing first (they were index 0, always inside the stock limit)')
    return ids


def lua_id(text, name):
    m = re.search(r'\b' + name + r'\s*=\s*\{?\s*(?:id\s*=\s*)?(\d+)', text)
    ok(m is not None, 'id of ' + name)
    return int(m.group(1))


# ------------------------------------------------------------------------------------------------ the patch text
patch = read(PATCH)
code = added(patch)
ok('+++ b/src/client/tile.cpp' in patch, 'patch 0116 changes src/client/tile.cpp')
ok('effetsLimit() + 1' in code, 'the budget is effetsLimit() + 1 effects, what the stock loop drew')
loops = re.findall(r'int first = chaosFirstDrawnEffect\(m_effects\);.*?\n\s*for \(int i = \(int\)m_effects\.size\(\) - 1; '
                   r'i >= 0; --i\) \{\n\s*if \(i < first && !chaosAlwaysDrawEffect\(m_effects\[i\]\)\)', code)
ok(len(loops) == 2, 'drawTop and drawGroundEffects both draw the newest (found %d loops)' % len(loops))
removed = [line for line in patch.splitlines() if line.startswith('-') and not line.startswith('---')]
ok(sum('for (int i = limit; i >= 0; --i)' in line for line in removed) == 2, 'both stock oldest-first loops are gone')
ok(re.search(r'm_effects\.erase\(std::remove_if\(.*?e->getId\(\) == effectId', code, re.S) is not None,
   'addThing drops a running copy of the same effect id')

fx, pack = read(CHAOS_FX), read(PACK_IDS)
feedback = {n: lua_id(fx, n) for n in ('crit_burst', 'dodge_whoosh', 'reflect_aegis', 'imbue_fire', 'imbue_ice',
                                       'imbue_energy', 'imbue_earth', 'imbue_death', 'imbue_holy')}
feedback['reflect_bubble'] = lua_id(pack, 'reflect_bubble')
prio = priority_ids(code)
for name, i in sorted(feedback.items()):
    ok(i in prio, '%s (%d) always draws' % (name, i))
ok(prio == set(feedback.values()), 'nothing else is forced over the limit: %s' % sorted(prio - set(feedback.values())))


# ------------------------------------------------------------------------------------------------ the model
class Effect:
    def __init__(self, eid, name, born, ms):
        self.id, self.name, self.born, self.ends = eid, name, born, born + ms


class Tile:
    def __init__(self, patched):
        self.patched, self.effects = patched, []

    def add(self, e):  # Tile::addThing (no top effects in this scene)
        if self.patched:
            self.effects = [x for x in self.effects if x.id != e.id]
        self.effects.append(e)

    def expire(self, t):  # Effect::onAppear scheduled g_map.removeThing(self)
        self.effects = [x for x in self.effects if x.ends > t]

    def drawn(self, limit):
        n = len(self.effects)
        if not self.patched:
            return [self.effects[i] for i in range(min(n - 1, limit), -1, -1)]
        first = max(0, n - (limit + 1))
        return [self.effects[i] for i in range(n - 1, -1, -1) if i >= first or self.effects[i].id in prio]


AURA_MS = 1079  # cond_* of chaos_pack29_vfx_ids.lua


def fight(patched):
    """a tile under a creature for 3 s; returns (tile at the moment of the feedback, the most copies of one aura)"""
    tile, most = Tile(patched), 0
    sends = []
    for k, state in enumerate((780, 782, 787)):  # burning, frozen, stunned: held, re-sent as each copy ends
        sends += [(k * 10 + j * AURA_MS, state, 'aura', AURA_MS) for j in range(3)]
    sends += [(t, 780, 'aura tick', AURA_MS) for t in range(0, 3000, 1000)]  # a condition tick of burning, 1 s
    for t in range(0, 3000, 125):  # a party: eight hits a second, a blast and a splash each
        sends += [(t, 800 + (t // 125) % 6, 'blast', 630), (t + 5, 828, 'hit_blood', 585)]
    sends.sort(key=lambda s: s[0])
    for t, eid, name, ms in sends:
        tile.expire(t)
        tile.add(Effect(eid, name, t, ms))
        most = max(most, max(sum(1 for x in tile.effects if x.id == a) for a in (780, 782, 787)))
    t = 3000
    tile.expire(t)
    for name in ('crit_burst', 'dodge_whoosh', 'reflect_bubble', 'imbue_fire'):
        tile.add(Effect(feedback[name], name, t, 600))
    return tile, most


stock, stock_most = fight(False)
fixed, fixed_most = fight(True)
ok(len(stock.effects) > 11, 'the scene is busy: %d effects on the tile' % len(stock.effects))
names = ('crit_burst', 'dodge_whoosh', 'reflect_bubble', 'imbue_fire')
for limit in LIMITS:
    s = {e.name for e in stock.drawn(limit)}
    f = fixed.drawn(limit)
    fn = {e.name for e in f}
    if limit <= 10:
        ok(not any(n in s for n in names), 'stock, limit %d: the combat feedback is dropped (the bug)' % limit)
    for n in names:
        ok(n in fn, '0116, limit %d: %s draws' % (limit, n))
    newest = sorted(fixed.effects, key=lambda e: e.born)[-(limit + 1):]
    ok(all(e in f for e in newest), '0116, limit %d: the newest effects draw' % limit)
    ok(len([e for e in f if e.id not in prio]) <= limit + 1,
       '0116, limit %d: at most limit + 1 effects that are not combat feedback' % limit)
    if limit == 2:
        ok('crit_burst' not in {e.name for e in newest}, 'limit 2: the crit is not among the newest (priority draws it)')
    ok([fixed.effects.index(e) for e in f] == sorted((fixed.effects.index(e) for e in f), reverse=True),
       '0116, limit %d: the stock draw order (back to front)' % limit)
ok(stock_most >= 2, 'stock: a re-sent aura stacks (%d copies)' % stock_most)
ok(fixed_most == 1, '0116: a re-sent aura replaces its copy (%d)' % fixed_most)
ok(len(fixed.effects) < len(stock.effects), '0116: fewer effects on the tile (%d, stock %d)'
   % (len(fixed.effects), len(stock.effects)))

print('effect_limit_test: %d checks OK' % checks)

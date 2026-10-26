#!/usr/bin/env python3
"""The keystone and mastery table of the tester bots (O249; server/README.md "Tester bots", Keystones and masteries).

GENERATED into server/tools/tester_scenarios.json under "keytest" by gen_tester_scenarios.py, from the same files the
server runs: passivetree_data.lua (the tree: neighbours, class marks `c`, per-class keystone variants `v`, mastery
effects `m`) and Chaos.classes.ids of chaos_constants.lua (the class keys). Per class key it lists every keystone and
mastery the class may hold, the cheapest route to it (node ids from the root, only nodes of that class, no other
keystone or mastery on the way when there is another route) and how the bots can see that it works:
  * mastery effect: the stats it gives that the totals of the tree window show (opcode 65 statTotals: the five
    attributes, the damage percent per type, the critical chance and amount of the tree); the rest are named as not
    observable
  * keystone: a proc row "Keystones" in the combat log (opcode 204, the DPS meter) that grows while the bot hunts, for
    the flags whose extra hits passivetree_keystones.lua deals; every other flag says why a bot cannot see it
Standard library only. Pure: tester_keytree.build(chaos_dir) -> dict.
"""
import os
import re
from collections import deque

# ------------------------------------------------------------------------------------------------ what a bot can see
# statTotals (passivetree_totals.lua): the stats whose raw tree sum the answer carries
ATTRIBUTES = ('strength', 'intelligence', 'dexterity', 'vitality', 'spirit')
DAMAGE = ('incrementPhysical', 'incrementFire', 'incrementIce', 'incrementEnergy', 'incrementEarth', 'incrementDeath',
          'incrementHoly', 'incrementArcane', 'incrementWater')
CRIT = ('criticalHitChance', 'criticalHitAmount')
# multiIncrement is added to every element row of the totals (not physical)
ELEMENTS = tuple(k for k in DAMAGE if k != 'incrementPhysical')
OBSERVABLE_STATS = ATTRIBUTES + DAMAGE + CRIT + ('multiIncrement',)

# keystone flags whose effect is an extra hit (doTargetCombat from passivetree_keystones.lua, ORIGIN_SPELL), which the
# combat log attributes to the source "Keystones" (combatlog_config.lua procLabels): flag -> what the hunt needs
PROC = {
    'ksCleavingArc': 'a two-handed melee weapon and a second enemy next to the target',
    'ksBulwark': 'a shield and an enemy that hits the character in melee (30% of the hit comes back)',
    'ksRicochet': 'a bow or crossbow and a second enemy within 4 sqm of the target',
    'ksArcaneEcho': 'a spell that hits 2 or more enemies (35% chance, 3 s cooldown)',
    'ksThorns': 'an enemy that hits the character in melee or at range',
    'ksShadowTwin': 'weapon hits (30% chance)',
    'ksCorpseBlast': 'a monster killed by the character or its minions',
    'ksSeventhPalm': 'melee hits (every 5th one) and a second enemy next to the target',
    'ksPiercingPalm': 'melee hits and a second enemy right behind the target',
    'ksRadiantRebuke': 'a shield and an enemy that hits the character (20% blocked)',
    'ksDawnchain': 'melee weapon hits and a second enemy within 3 sqm of the target',
}
# every other keystone flag: why no bot can see it work (the report prints this as "not observable")
NO_PROBE = {
    'ksOverload': 'a +20% on the next spell of another element: a damage factor, no row of its own in the combat log',
    'ksOvergrowth': 'needs another player healed by the character: heals on others, bots never heal real players',
    'ksImmovable': 'less damage taken: a factor on each hit, no row or total a client can read',
    'ksUndyingRage': 'a heal of 4% of the damage dealt (plain health, no combat log row)',
    'ksHuntersFocus': 'damage +4% per hit on the same target: a factor on the hit itself',
    'ksDeadeye': 'double damage on 15% of the crossbow shots: a factor on the hit itself',
    'ksPackAlpha': 'companion damage and damage taken: factors, no row of their own',
    'ksSharedPhantasm': 'needs a party: it buffs the other members, never the illusionist',
    'ksInspiringIllusion': 'needs a party: it buffs the other members, never the illusionist',
    'ksViperVerdict': 'a damage factor on weapon hits (x2 on a poisoned target, x0.85 otherwise)',
    'ksReapersToll': 'a damage factor on hits at 40% health or less (x2, otherwise x0.92)',
    'ksGraveCovenant': 'a change of the minions and corpses, no row or total a client can read',
    'ksPenitentWrath': 'a change of the Templar combat rules, no row or total a client can read',
    'ksBlackbloodCreed': 'a change of the Thief combat rules, no row or total a client can read',
    'ksScarredDiscipline': 'a change of the Monk chi rules, no row or total a client can read',
    'ksLivingShadow': 'a change of the Thief combat rules, no row or total a client can read',
    'ksWayOfTheBlade': 'a change of the Thief combat rules, no row or total a client can read',
    'ksHoardedSouls': 'a change of the necromancer soul rules, no row or total a client can read',
    'ksBoneColossus': 'a change of the minions, no row or total a client can read',
    'ksHundredHands': 'a change of the Monk combat rules, no row or total a client can read',
    'ksFlowingMercy': 'a change of the healing rules, no row or total a client can read',
    'ksDivineVerdict': 'a change of the Templar combat rules, no row or total a client can read',
    'ksBastion': 'a change of the Templar defence rules, no row or total a client can read',
}
ARCHETYPE_WHY = ('a build archetype keystone (archetypes.lua): its hits carry no label of their own in the combat log '
                 'and its other effects are factors or reservations, so no bot can read them')

FLAG_RE = re.compile(r'^(ks|ar)[A-Z]')
# classes whose vocation has another key in the keystone variants (classes.lua KEYSTONE_KEY, by class key)
KEYSTONE_KEY = {'warrior': 'knight', 'ranger': 'paladin', 'mystic': 'sorcerer', 'elementalist': 'sorcerer'}


# ------------------------------------------------------------------------------------------------ the Lua tables
class LuaError(ValueError):
    pass


TOKEN_RE = re.compile(r'\s*(?:(\[\s*-?\d+\s*\])|([A-Za-z_]\w*)|(-?\d+(?:\.\d+)?)|(.))', re.S)


def parse_table(text, pos=0):
    """a Lua table constructor of numbers, names, true/false and nested tables -> (python value, end position).
    A table with only positional values is a list; else a dict (an [n] key is an int, a name a str)."""
    def tok(p):
        m = TOKEN_RE.match(text, p)
        if not m:
            raise LuaError('unexpected end at %d' % p)
        return m, m.end()

    def value(p):
        m, p2 = tok(p)
        if m.group(4) == '{':
            return table(p2)
        if m.group(3) is not None:
            n = float(m.group(3))
            return (int(n) if n == int(n) else n), p2
        if m.group(2) in ('true', 'false'):
            return m.group(2) == 'true', p2
        raise LuaError('unexpected %r at %d' % (m.group(0).strip(), p))

    def table(p):
        items, keyed = [], {}
        while True:
            m, p2 = tok(p)
            if m.group(4) == '}':
                break
            if m.group(4) == ',':
                p = p2
                continue
            key = None
            if m.group(1):
                key = int(m.group(1).strip('[] \t\n'))
                m2, p3 = tok(p2)
                if m2.group(4) != '=':
                    raise LuaError('= expected at %d' % p2)
                p = p3
            elif m.group(2) and m.group(2) not in ('true', 'false'):
                m2, p3 = tok(p2)
                if m2.group(4) == '=':
                    key, p = m.group(2), p3
            if key is not None:
                keyed[key], p = value(p)
            else:
                v, p = value(p)
                items.append(v)
        if keyed and items:
            raise LuaError('mixed table at %d' % p)
        return (keyed if keyed or not items else items), p2

    if text[pos:].lstrip()[:1] != '{':
        raise LuaError('a table is expected at %d' % pos)
    return value(pos)


def load_tree(path):
    """passivetree_data.lua -> {root, nodes: {id: {n, s, v, c, m}}}"""
    with open(path, encoding='utf-8') as f:
        text = re.sub(r'--[^\n]*', '', f.read())
    start = text.index('ChaosPassiveTreeData = ') + len('ChaosPassiveTreeData = ')
    data, _ = parse_table(text, start)
    nodes = data['nodes']
    return {'root': data['root'], 'nodes': nodes if isinstance(nodes, dict) else {i + 1: n for i, n in enumerate(nodes)}}


def class_keys(constants_path):
    """the keys of Chaos.classes.ids in id order"""
    with open(constants_path, encoding='utf-8') as f:
        text = re.sub(r'--[^\n]*', '', f.read())
    i = text.index('\tids = {', text.index('Chaos.classes'))
    body, _ = parse_table(text, i + len('\tids = '))
    return [k for k, _ in sorted(body.items(), key=lambda kv: kv[1])]


# ------------------------------------------------------------------------------------------------ the table
def allowed(node, key):
    return not node.get('c') or node['c'].get(key) is True


def stats_for(node, key):
    """the stats a node gives a class (passivetree_core.lua nodeStats): its variant, else the shared stats"""
    v = node.get('v') or {}
    return v.get(KEYSTONE_KEY.get(key, key)) or node.get('s') or {}


def flag_of(stats):
    return sorted(k for k in stats if FLAG_RE.match(k))


def route(tree, key, target, avoid):
    """the shortest list of node ids from the root to `target` (the target last) through nodes the class may hold;
    nodes in `avoid` only when no route exists without them. None without any route."""
    nodes = tree['nodes']
    for blocked in (avoid, set()):
        prev, queue = {tree['root']: None}, deque([tree['root']])
        while queue:
            cur = queue.popleft()
            if cur == target:
                break
            for nb in sorted(nodes[cur].get('n', [])):
                if nb in prev or nb not in nodes or not allowed(nodes[nb], key):
                    continue
                if nb in blocked and nb != target:
                    continue
                prev[nb] = cur
                queue.append(nb)
        if target in prev:
            out, cur = [], target
            while cur != tree['root']:
                out.append(cur)
                cur = prev[cur]
            return out[::-1]
    return None


def mastery_effects(node):
    """[{observable: {stat: value}, other: [stat, ...]}] per effect of a mastery node"""
    out = []
    for i, eff in enumerate(node['m'], 1):
        out.append({'choice': i, 'observable': {k: eff[k] for k in sorted(eff) if k in OBSERVABLE_STATS},
                    'other': sorted(k for k in eff if k not in OBSERVABLE_STATS)})
    return out


def probe_of(flag):
    """how the bots check a keystone flag: {mode: 'combatlog', row, tab, needs} or {mode: 'none', why}"""
    if flag in PROC:
        return {'mode': 'combatlog', 'row': 'p:Keystones', 'tab': 'dealt', 'needs': PROC[flag]}
    if flag in NO_PROBE:
        return {'mode': 'none', 'why': NO_PROBE[flag]}
    if flag.startswith('ar'):
        return {'mode': 'none', 'why': ARCHETYPE_WHY}
    return None


def build(chaos_dir):
    """the "keytest" section of tester_scenarios.json"""
    tree = load_tree(os.path.join(chaos_dir, 'passivetree_data.lua'))
    keys = class_keys(os.path.join(chaos_dir, 'chaos_constants.lua'))
    nodes = tree['nodes']
    special = {i for i, n in nodes.items() if n.get('m') or any(flag_of(s) for s in [n.get('s') or {}] + list((n.get('v') or {}).values()))}
    classes, flags, unknown = {}, set(), set()
    for key in keys:
        rows = []
        for nid in sorted(nodes):
            node = nodes[nid]
            if nid == tree['root'] or not allowed(node, key):
                continue
            if node.get('m'):
                path = route(tree, key, nid, special - {nid})
                if path is None:
                    continue
                rows.append({'id': nid, 'kind': 'mastery', 'path': path[:-1], 'effects': mastery_effects(node)})
                continue
            fl = flag_of(stats_for(node, key))
            if not fl:
                continue
            path = route(tree, key, nid, special - {nid})
            if path is None:
                continue
            for f in fl:
                flags.add(f)
                if probe_of(f) is None:
                    unknown.add(f)
            rows.append({'id': nid, 'kind': 'keystone', 'flag': fl[0], 'path': path[:-1], 'probe': probe_of(fl[0])})
        if unknown:
            raise SystemExit('tester_keytree: keystone flags without a probe or a reason (add them to PROC or NO_PROBE): '
                             + ', '.join(sorted(unknown)))
        # cheapest first: the bots test what their points allow
        rows.sort(key=lambda r: (len(r['path']), r['id']))
        classes[key] = rows
    for f in PROC:
        if f not in flags:
            raise SystemExit('tester_keytree: PROC names %s, which no keystone of the tree has' % f)
    for f in NO_PROBE:
        if f not in flags:
            raise SystemExit('tester_keytree: NO_PROBE names %s, which no keystone of the tree has' % f)
    return {'classes': classes, 'observableStats': list(OBSERVABLE_STATS), 'elements': list(ELEMENTS)}

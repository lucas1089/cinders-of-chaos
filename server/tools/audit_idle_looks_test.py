#!/usr/bin/env python3
"""Tests for audit_idle_looks.py (O533): the idle rule on fake outfits, the allow list and look_idle.csv rules on synthetic
files, the CLI on a synthetic monster folder, and the committed pool, facts, allow list and picks.

usage: python3 -I server/tools/audit_idle_looks_test.py
"""
import csv
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import audit_idle_looks as I  # noqa: E402

TOOL = os.path.join(HERE, 'audit_idle_looks.py')


class Thing:
    """The part of datspr.Thing the rule reads: id, flags, groups."""

    def __init__(self, id, groups, always=False):
        self.id, self.groups, self.flags = id, groups, {'animateAlways': True} if always else {}


def group(phases, same=False, px=4):
    """A 1x1 frame group of `phases` phases, 4 directions, one layer; every phase one picture when same, else its own."""
    sprites = []
    for ph in range(phases):
        for x in range(px):
            sprites.append(1 + x if same else 1 + ph * 10 + x)
    return (1, 1, 32, 1, px, 1, 1, phases, sprites, None)


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def main():
    # the rule
    check(I.idle_info(Thing(1, [group(1), group(8)])) == (False, 1, 1, 'none'), 'idle 1 phase, walk 8: stands as one picture')
    check(I.idle_info(Thing(2, [group(4), group(8)])) == (True, 4, 4, 'idle group'), 'idle group of 4 phases')
    check(I.idle_info(Thing(3, [group(6)], always=True)) == (True, 6, 6, 'animateAlways'), 'one group, animateAlways')
    check(I.idle_info(Thing(4, [group(6)]))[0] is False, 'one group of walk phases without the attribute stands still')
    check(I.idle_info(Thing(5, [group(1), group(8)], always=True)) == (True, 8, 8, 'animateAlways'),
          'animateAlways plays the walk phases of a two group outfit on a clock')
    check(I.idle_info(Thing(6, [group(4, same=True), group(8)])) == (False, 4, 1, 'idle group'), 'phases that all draw one picture are no animation')
    check(I.idle_info(Thing(7, [group(1)], always=True)) == (False, 1, 1, 'none'), 'animateAlways with one phase')
    check(I.idle_info(Thing(8, [group(7)]), listed={8}) == (True, 7, 7, 'client list'), 'a look of the game_bossanimate list')
    check(I.idle_info(Thing(9, [group(7)]), listed={8})[0] is False, 'a look that is not on the list')
    check(1534 in I.client_list(), 'the client list is read from game_bossanimate (Skaldra, 1534)')
    check(I.distinct_frames(group(3)) == 3 and I.distinct_frames(group(3, same=True)) == 1, 'distinct frames')

    # gen_bounty_pool.py --relook: only the look fields change
    import gen_bounty_pool as G
    text = ('return {\n\thunt = {\n'
            '\t\t{name = "Sandy", level = 5, exp = 1, health = 9, spawns = 9, look = 100, head = 1, body = 2, legs = 3, feet = 4, addons = 0},\n'
            '\t\t{name = "O\'Neil \\"X\\"", level = 6, exp = 1, health = 9, spawns = 9, look = 100},\n'
            '\t\t{name = "Gone", level = 7, exp = 1, health = 9, spawns = 9, look = 100},\n'
            '\t},\n\tbosses = {\n\t\t{name = "Boss", level = 9, exp = 1, health = 9, spawns = 1, look = 7},\n\t}\n}\n')
    mons = {'sandy': {'look': 300}, 'o\'neil "x"': {'look': 301, 'look_head': 5, 'look_body': 0, 'look_legs': 0, 'look_feet': 0, 'look_addons': 0},
            'boss': {'look': 7}}
    new, n = G.relook(text, mons)
    check(n == 2, 'two lines change, got %d' % n)
    check('look = 300},' in new and 'head = 1' not in new, 'colours go with the old look')
    check('look = 301, head = 5, body = 0, legs = 0, feet = 0, addons = 0},' in new, 'a new look with colours')
    check('"Gone", level = 7, exp = 1, health = 9, spawns = 9, look = 100},' in new and 'look = 7},' in new, 'unknown monsters and equal looks stay')
    check(G.relook(new, mons) == (new, 0), 'idempotent')

    with tempfile.TemporaryDirectory() as t:
        crowd = os.path.join(t, 'crowded.csv')
        open(crowd, 'w').write('look,names,reason\n')
        check(I.crowded_problems({5: ['A', 'B']}, crowd) == [], 'two monsters on a look are fine')
        probs = I.crowded_problems({5: ['A', 'B', 'C']}, crowd)
        check(len(probs) == 1 and 'worn by 3 monsters' in probs[0], probs)
        open(crowd, 'w').write('look,names,reason\n5,A | B | C | D,twins by design\n')
        check(I.crowded_problems({5: ['A', 'B', 'C']}, crowd) == [], 'a row that names them all')
        check(len(I.crowded_problems({5: ['A', 'B', 'E']}, crowd)) == 1, 'a row that misses one name')
        check(len(I.crowded_problems({6: ['A', 'B', 'C']}, crowd)) == 1, 'a row of another look')
        pool = os.path.join(t, 'pool.lua')
        open(pool, 'w').write('return {\n\thunt = {\n'
                              '\t\t{name = "Mover", level = 5, exp = 1, health = 9, spawns = 9, look = 100},\n'
                              '\t\t{name = "Still", level = 5, exp = 1, health = 9, spawns = 9, look = 200},\n'
                              '\t\t{name = "Unknown", level = 5, exp = 1, health = 9, spawns = 9, look = 300},\n'
                              '\t},\n\tbosses = {\n\t\t{name = "Boss", level = 5, exp = 1, health = 9, spawns = 1, look = 200},\n\t},\n}\n')
        idle = {100: (True, 8, 8, 'idle group'), 200: (False, 1, 1, 'none'), 300: (False, 1, 1, 'none')}
        allow = os.path.join(t, 'allow.csv')
        open(allow, 'w').write('name,look,reason\n')
        probs = I.check_pool(pool, allow, idle)
        check(len(probs) == 2 and 'Still wears look 200' in probs[0] and 'Unknown wears look 300' in probs[1], probs)
        check('Mover' not in ' '.join(probs) and 'Boss' not in ' '.join(probs), 'a mover and a boss are no problem')
        open(allow, 'w').write('name,look,reason\nStill,200,a reason\nUnknown,300,a reason\n')
        check(I.check_pool(pool, allow, idle) == [], 'allowed with a reason')
        open(allow, 'w').write('name,look,reason\nStill,201,a reason\nUnknown,300,a reason\n')
        probs = I.check_pool(pool, allow, idle)
        check(len(probs) == 1 and 'names look 201' in probs[0], 'a row names the look the monster wears: %s' % probs)
        open(allow, 'w').write('name,look,reason\nStill,200,r\nUnknown,300,r\nMover,100,r\n')
        probs = I.check_pool(pool, allow, idle)
        check(len(probs) == 1 and 'Mover' in probs[0] and 'remove its row' in probs[0], 'a stale row: %s' % probs)
        open(allow, 'w').write('name,look,reason\nStill,200,r\nUnknown,300,r\nSomeone Far Away,5,r\n')
        check(I.check_pool(pool, allow, idle) == [], 'a row of a monster that is not in the pool (3 to 5 spawn points) is not judged')
        probs = I.check_pool(pool, allow, {100: idle[100]})
        check(len(probs) == 2 and 'not in server/data/monster/look_idle.csv' in probs[0], 'a pool look without facts: %s' % probs)

        # the CLI on a synthetic folder
        md = os.path.join(t, 'monster')
        os.makedirs(os.path.join(md, 'monsters'))
        names = {'Mover': 100, 'Still': 200, 'Rare': 200, 'Mine': 200}
        reg = '<monsters>\n'
        for n, look in names.items():
            reg += '<monster name="%s" file="monsters/%s.xml" />\n' % (n, n.lower())
            open(os.path.join(md, 'monsters', n.lower() + '.xml'), 'w').write(
                '<monster name="%s"><look type="%d" corpse="1"/></monster>\n' % (n, look))
        open(os.path.join(md, 'monsters.xml'), 'w').write(reg + '</monsters>\n')
        spawn = os.path.join(t, 'spawn.xml')
        open(spawn, 'w').write('<spawns>' + ''.join('<monster name="%s"/>' % n for n in ('Mover',) * 4 + ('Still',) * 3 + ('Rare',) * 2) + '</spawns>')
        facts = os.path.join(t, 'idle.csv')
        open(facts, 'w').write('look,idle,phases,frames,how\n100,yes,8,8,idle group\n200,no,1,1,none\n')
        open(allow, 'w').write('name,look,reason\n')

        def run(*a):
            r = subprocess.run([sys.executable, '-I', TOOL, md, '--spawn', spawn, '--idle', facts, '--allow', allow, *a],
                               capture_output=True, text=True)
            return r.returncode, r.stdout
        code, out = run('--check')
        check(code == 1 and 'Still (look 200, spawns 3): NO IDLE' in out and '1 without an idle animation, 1 not allowed' in out, out)
        check('Rare' not in out and 'Mine' not in out, 'only a met monster (3 spawn points) is judged: ' + out)
        open(allow, 'w').write('name,look,reason\nStill,200,twins by design\n')
        out_csv = os.path.join(t, 'out.csv')
        code, out = run('--check', '--csv', out_csv)
        check(code == 0 and '0 not allowed' in out, out)
        rows = list(csv.reader(open(out_csv)))
        check(rows[1][:2] == ['Still', '200'] and rows[1][4] == 'kept' and rows[1][5] == 'twins by design', rows)

    # the repo itself: committed pool, facts, allow list, picks
    probs = I.check_pool() + I.check_crowded()
    check(not probs, probs[:3])
    for look, names, why in I.load_crowded():
        check(why.strip() and len(names) > I.MAX_ON_LOOK, 'crowded row %d needs a reason and more than %d names' % (look, I.MAX_ON_LOOK))
    idle = I.load_idle()
    allow = I.load_allow()
    check(idle and allow, 'look_idle.csv and no_idle_allow.csv have rows')
    for r in csv.DictReader(open(I.ALLOW, newline='', encoding='utf-8')):
        check(r['reason'].strip(), '%s: an allow row needs a reason' % r['name'])
    for name, (look, _) in allow.items():
        check(look not in idle or not idle[look][0], '%s: look %d has an idle animation, drop the row' % (name, look))
    for look, (yes, phases, frames, how) in idle.items():
        check(yes == (how != 'none' and frames > 1), 'look %d: idle %s, how %s, frames %d' % (look, yes, how, frames))
    # the O533 picks: each monster of the rows wears its new look, which moves while it stands
    from audit_shared_looks import pool_rows
    pool = {r['name']: r['look'] for r in pool_rows()}
    picks = os.path.join(I.REPO, 'client', 'tools', 'sprites', 'monster_looks', 'picks.csv')
    n = 0
    for r in csv.DictReader(open(picks, newline='')):
        if not r['key'].startswith('idle_'):
            continue
        n += 1
        check(r['family'] in ('hunt', 'base'), '%s: a hunt or base row' % r['key'])
        check(r['monsters'] not in allow, '%s: on the no-idle list' % r['monsters'])
        if r['monsters'] not in pool:   # a monster without experience (the Calamary) is no pool row
            continue
        check(pool[r['monsters']] == int(r['look']), '%s: the pool look of %s is %s' % (r['key'], r['monsters'], r['look']))
        check(idle[int(r['look'])][0], '%s: look %s has no idle animation' % (r['key'], r['look']))
    check(n >= 90, 'the O533 rows of picks.csv (%d)' % n)
    # a look of a new row is not worn by a second monster of the pool
    by = {}
    for name, look in pool.items():
        by.setdefault(look, []).append(name)
    for r in csv.DictReader(open(picks, newline='')):
        if r['key'].startswith('idle_') and r['monsters'] in pool:
            check(by[int(r['look'])] == [r['monsters']], '%s: look %s is worn by %s' % (r['key'], r['look'], by[int(r['look'])]))
    print('audit_idle_looks_test: OK')


if __name__ == '__main__':
    main()

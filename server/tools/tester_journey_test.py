#!/usr/bin/env python3
"""python3 -I server/tools/tester_journey_test.py: the levelling journey of the tester bots (tester_journey.py, O654) on a mocked game: the temple,
its teleport into the teleport room, the hall's floors and stairs, hunt teleports with a level rule, hunts with monsters, the Town Portal, the
shops of the market. Every helper teleport the bot uses is counted; the proof that the bot walks is that a whole journey ends with none."""
import asyncio
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tester_journey as J  # noqa: E402
import tester_checks as TX  # noqa: E402

TEMPLE = (50, 50, 7)
GATE = (50, 45, 7)
HALL_IN = (60, 20, 7)       # the hub the gate leads to (the real one is 31648,32233,7: the mock keeps its own small map)
STAIRS_UP = (70, 25, 7)     # floor 7 -> 6
STAIRS_DOWN = (66, 26, 6)   # the stairs on floor 6 (down again)
UP_LANDS = (70, 26, 6)
LOCKER_SPOT = (53, 51, 7)


def run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def hunt(i, lo, hi, z=7, x=None):
    x = x if x is not None else 80 + lo
    return {'i': i, 'n': i.title(), 'l': (lo, hi), 't': (x, 20, z), 'f': (x, 21, z), 'a': (5000 + lo, 60, 7), 'b': (5000 + lo, 62, 7)}


HUNTS = [hunt('rats', 1, 20), hunt('cave', 15, 40), hunt('bog', 40, 90, z=6), hunt('keep', 60, 120), hunt('ruin', 90, 200)]


def mid(h):
    return (h['l'][0] + h['l'][1]) / 2.0


def xyz(p):
    return {'x': p[0], 'y': p[1], 'z': p[2]} if p else None


class World:
    """one bot in a mocked game; time passes in sleep() and in every helper answer. The rules are the real ones in small: the pick is the
    window of the helper (0.8-1.1 x level, widened), a hunt teleport refuses a level under its band, the town portal appears beside the caster"""

    def __init__(self, level=8, lvl_s=30.0, hunts=None, **opts):
        self.t = 0.0
        self.up = True
        self.pos = TEMPLE
        self.level = level
        self.lvl_s = lvl_s            # seconds of fighting per level
        self.fight = 0.0
        self.hunts = hunts or HUNTS
        self.opts = dict(gate=True, stairs=True, locker=True, portal=True, path_to_hunt=True, camp=True, refuse=False, npcs=True,
                         gate_walk=True, monsters=True)
        self.opts.update(opts)
        self.hunt = None
        self.mon = None
        self.portal = None
        self.helpers, self.said, self.steps, self.shopped, self.requests = [], [], 0, [], []
        self.lockers, self.keeps, self.loots = 0, 0, 0
        self.sell_flag = False
        self.blocked = set(opts.get('blocked', ()))
        self.teleports = []           # (kind, why) of every helper teleport the world did
        self.die_at = None
        self.flee_at = None

    # ---- the world
    def zone(self):
        x, y, z = self.pos
        if 55 <= x <= 400 and 0 <= y <= 40 and z in (6, 7):
            return 'hall'
        if z == 7 and abs(x - TEMPLE[0]) <= 24 and abs(y - TEMPLE[1]) <= 24:
            return 'temple'
        return 'other'

    def pick(self, keep=None, skip=()):
        pool = [h for h in self.hunts if h['i'] not in skip]
        L = self.level
        for k in range(0, 41):
            lo, hi = (0.8 - 0.05 * k) * L, (1.1 + 0.05 * k) * L
            fit = [h for h in pool if h['l'][0] <= L and lo <= mid(h) <= hi]
            if fit:
                for h in fit:
                    if h['i'] == keep:
                        return h, True, k
                fit.sort(key=lambda h: (abs(mid(h) - 0.95 * L), h['i']))
                return fit[0], False, k
        return None, False, -1

    def state(self, keep=None, skip=()):
        h, stay, k = self.pick(keep, skip)
        zone = self.zone()
        s = {'level': self.level, 'zone': zone, 'pos': xyz(self.pos), 'pz': zone != 'other'}
        if h:
            s['pick'] = {'id': h['i'], 'n': h['n'], 'lo': h['l'][0], 'hi': h['l'][1], 't': xyz(h['t']), 'f': xyz(h['f']), 'a': xyz(h['a']),
                         'b': xyz(h['b']) if self.opts['camp'] else None, 'widen': k, 'z': h['t'][2]}
            if stay:
                s['stay'] = True
        if zone == 'temple':
            if self.opts['gate']:
                s['gate'] = xyz(GATE)
            if self.opts['locker']:
                s['locker'] = {'x': 53, 'y': 52, 'z': 7, 'cid': 12589, 'sp': 1, 'spot': xyz(LOCKER_SPOT)}
        if zone == 'hall' and self.opts['stairs']:
            s['stairs'] = {'up': xyz(STAIRS_UP)} if self.pos[2] == 7 else {'down': xyz(STAIRS_DOWN)}
        if self.portal and abs(self.portal[0] - self.pos[0]) <= 4 and abs(self.portal[1] - self.pos[1]) <= 4 and self.portal[2] == self.pos[2]:
            s['portal'] = xyz(self.portal)
        if zone == 'other' and self.mon:
            d = max(abs(self.mon[0] - self.pos[0]), abs(self.mon[1] - self.pos[1]))
            s['monster'] = {'name': 'rat', 'level': 5, 'x': self.mon[0], 'y': self.mon[1], 'z': self.mon[2], 'dist': d}
        return s

    def at_hunt(self, h):
        self.hunt = h
        self.pos = h['a']
        self.mon = (h['a'][0] + 8, h['a'][1], h['a'][2]) if self.opts['monsters'] else None

    def move_to(self, p):
        if p == GATE and self.zone() == 'temple' and self.opts['gate']:
            self.pos = HALL_IN
        elif p == STAIRS_UP and self.pos[2] == 7:
            self.pos = UP_LANDS
        elif p == STAIRS_DOWN and self.pos[2] == 6:
            self.pos = (STAIRS_UP[0], STAIRS_UP[1] + 1, 7)   # down the stairs, onto the next tile of the floor below
        elif self.portal and p == self.portal:
            self.pos = TEMPLE
            self.portal = None
            self.hunt, self.mon = None, None
        elif self.zone() == 'other' and any(p == h['b'] for h in self.hunts) and self.opts['camp']:
            self.pos = next(h['f'] for h in self.hunts if p == h['b'])   # the camp portal: back to the front of the hunt's teleport
            self.hunt, self.mon = None, None
        else:
            for h in self.hunts:
                if p == h['t'] and self.zone() == 'hall':
                    if self.level >= h['l'][0] and not self.opts['refuse']:
                        self.at_hunt(h)
                    return
            if p in self.blocked:
                return
            self.pos = p

    # ---- the io of tester_checks / testers.py
    def alive(self):
        return self.up

    def now(self):
        return self.t

    async def sleep(self, seconds):
        self.t += seconds
        if self.zone() == 'other' and self.mon:
            d = max(abs(self.mon[0] - self.pos[0]), abs(self.mon[1] - self.pos[1]))
            if d <= J.FIGHT_RANGE:
                self.fight += seconds
                while self.fight >= self.lvl_s:
                    self.fight -= self.lvl_s
                    self.level += 1
        if self.die_at is not None and self.t >= self.die_at:
            self.die_at = None
            self.up = False
        if self.flee_at is not None and self.t >= self.flee_at and self.zone() == 'other':
            self.flee_at = None
            self.pos, self.hunt, self.mon = TEMPLE, None, None

    async def say(self, text):
        self.said.append(text)
        if text == J.TOWN_WORDS and self.zone() == 'other' and self.opts['portal']:
            self.portal = (self.pos[0] + 1, self.pos[1], self.pos[2])

    def step_sync(self, dx, dy):
        self.steps += 1
        self.move_to((self.pos[0] + dx, self.pos[1] + dy, self.pos[2]))

    async def step(self, dx, dy):
        self.step_sync(dx, dy)
        return True

    async def loot(self):
        self.loots += 1

    async def open_locker(self, locker):
        self.lockers += 1

    async def shop_here(self, name):
        self.shopped.append(name)
        return {'sold': 3, 'bought': 5, 'window': True}

    async def keep(self):
        self.keeps += 1
        return {'sell': self.sell_flag}

    async def request(self, opname, action, data, expect, timeout):
        self.requests.append((opname, action, data))
        return None

    def path(self, dest, near_name=None):
        if dest[2] != self.pos[2]:
            return {'err': 'another floor', 'pos': xyz(self.pos), 'dest': xyz(dest)}
        if not self.opts['path_to_hunt'] and self.zone() == 'hall' and dest[1] in (20, 21) and dest[0] >= 80:
            return {'err': 'no path', 'pos': xyz(self.pos), 'dest': xyz(dest)}
        if not self.opts['gate_walk'] and dest == GATE and max(abs(self.pos[0] - dest[0]), abs(self.pos[1] - dest[1])) > 1:
            return {'err': 'no path', 'pos': xyz(self.pos), 'dest': xyz(dest)}
        here, dirs = list(self.pos), []
        while max(abs(here[0] - dest[0]), abs(here[1] - dest[1])) > 1 and len(dirs) < 80:
            if here[0] != dest[0]:
                dirs.append(1 if dest[0] > here[0] else 3)
                here[0] += 1 if dest[0] > here[0] else -1
            else:
                dirs.append(2 if dest[1] > here[1] else 0)
                here[1] += 1 if dest[1] > here[1] else -1
        d = max(abs(self.pos[0] - dest[0]), abs(self.pos[1] - dest[1]))
        out = {'pos': xyz(self.pos), 'dest': xyz(dest), 'path': dirs, 'dist': d}
        if d <= 1:
            out['here'] = True
            out['path'] = []
        return out

    async def helper(self, command, kind, wait=4.0):
        self.t += 0.2
        self.helpers.append(command)
        words = command.split()
        if words[0] == 'journey':
            keep, skip = None, set()
            if 'keep' in words:
                keep = words[words.index('keep') + 1]
            if 'skip' in words:
                skip = set(words[words.index('skip') + 1].split(','))
            if len(words) > 1 and words[1] == 'hall':
                self.pos = HALL_IN
                self.teleports.append(('hall', ''))
                return dict(self.state(), jumped='hall')
            if len(words) > 1 and words[1] == 'jump':
                h, _, _ = self.pick(keep, skip)
                self.at_hunt(h)
                self.teleports.append(('jump', h['i']))
                return dict(self.state(), jumped='jump')
            return self.state(keep, skip)
        if words[0] == 'path' and words[1] == 'pos':
            return self.path((int(words[2]), int(words[3]), int(words[4])))
        if words[0] == 'path' and words[1] == 'npc':
            if not self.opts['npcs']:
                return {'err': 'no path', 'pos': xyz(self.pos)}
            return self.path((64, 20, 7))
        if words[0] == 'bag':
            return {'used': 5, 'size': 20, 'sell': 0, 'better': None, 'rows': [], 'junk': []}
        if words[0] == 'town':
            self.pos, self.hunt, self.mon = TEMPLE, None, None
            self.teleports.append(('town', ''))
            return {'pos': xyz(self.pos)}
        if words[0] == 'enter' and words[1] == 'npc':
            self.pos = (64, 22, 7)
            return {'npc': ' '.join(words[2:]), 'pos': xyz(self.pos)}
        return None


def new_journey(level=8, name='Tester Jny'):
    return J.Journey(name, 'Knight', level)


class Pure(unittest.TestCase):
    def test_state_command(self):
        self.assertEqual(J.state_command(None, []), 'journey')
        self.assertEqual(J.state_command('cave', ['b', 'a']), 'journey keep cave skip a,b')
        self.assertEqual(J.state_command('bad id!', ['ok', 'x y']), 'journey skip ok')   # an id the helper would refuse is left out
        self.assertEqual(len(J.state_command(None, ['h%d' % i for i in range(40)]).split(' ')[2].split(',')), 24)

    def test_step_toward(self):
        self.assertEqual(J.step_toward((1, 1, 7), (2, 1, 7)), [(1, 0)])
        self.assertEqual(J.step_toward((1, 1, 7), (0, 0, 7)), [(-1, 0), (0, -1)])   # a diagonal is two steps
        self.assertEqual(J.step_toward((1, 1, 7), (1, 1, 7)), [])
        self.assertEqual(J.step_toward((1, 1, 7), (4, 1, 7)), [])                    # not adjacent
        self.assertEqual(J.step_toward((1, 1, 7), (2, 1, 6)), [])                    # another floor
        self.assertEqual(J.step_toward(None, (2, 1, 7)), [])

    def test_levels(self):
        j = new_journey(8)
        j.seen(0.0)
        j.level_seen(8, 0.0)
        j.level_seen(9, 600.0)       # the level it began in is not complete: nothing is logged for it
        self.assertEqual(j.per_level, {})
        j.level_seen(10, 1200.0)      # 10 minutes for level 9
        self.assertEqual(j.per_level, {9: 10.0})
        j.level_seen(12, 1800.0)      # two levels at once: split evenly
        self.assertEqual(j.per_level[10], 5.0)
        self.assertEqual(j.per_level[11], 5.0)
        j.level_seen(11, 1900.0)      # a death took a level: the level is 11, nothing is logged
        self.assertEqual((j.level, j.top), (11, 12))
        j.level_seen(12, 2500.0)      # won back: not completed twice
        self.assertEqual(sorted(j.per_level), [9, 10, 11])
        j.level_seen(0, 1.0)
        j.level_seen('x', 1.0)
        self.assertEqual(j.level, 12)

    def test_resumed_gap_is_not_levelling_time(self):
        j = new_journey(8)
        j.seen(0.0)
        j.level_seen(8, 0.0)
        j.level_seen(9, 100.0)
        j.seen(110.0)
        j.resumed(410.0)              # five minutes offline (death, a new login): 295 s are taken off
        j.level_seen(10, 500.0)
        self.assertAlmostEqual(j.per_level[9], (500.0 - 100.0 - 295.0) / 60.0, places=2)

    def test_deaths(self):
        j = new_journey(100)
        j.hunt = {'id': 'bog', 'n': 'Bog', 'lo': 40, 'hi': 90, 'at': 0}
        j.deaths_seen(1, 100.0)
        self.assertEqual((j.deaths, j.hunt), (1, None))
        self.assertNotIn('bog', j.active_skip(101.0))
        j.hunt = {'id': 'bog', 'n': 'Bog', 'lo': 40, 'hi': 90, 'at': 0}
        j.deaths_seen(1, 400.0)       # the second death at it within 20 minutes
        self.assertIn('bog', j.active_skip(401.0))
        self.assertNotIn('bog', j.active_skip(401.0 + J.SKIP_FOR['deaths'] + 1))
        j.hunt = {'id': 'cave', 'at': 0}
        j.deaths_seen(1, 5000.0)      # one death long after the last: no skip
        j.hunt = {'id': 'cave', 'at': 0}
        j.deaths_seen(1, 9000.0)
        self.assertNotIn('cave', j.active_skip(9001.0))

    def test_fallbacks_are_counted(self):
        j = new_journey()
        j.fall('hall', 'no gate')
        j.fall('hall', 'no gate')
        j.fall('jump', 'no path')
        self.assertEqual(j.fallback_counts, {'hall': 2, 'jump': 1})
        self.assertEqual(j.fallbacks[-1], 'jump (no path)')
        for i in range(50):
            j.fall('x', str(i))
        self.assertLessEqual(len(j.fallbacks), J.FALLBACK_LIST)

    def test_report(self):
        j = new_journey(8)
        j.seen(0.0)
        j.level_seen(8, 0.0)
        for lv in range(9, 20):
            j.level_seen(lv, (lv - 8) * 600.0)
        d = {j.name: j.as_dict(6600.0)}
        curve = {lv: 10.0 for lv in range(1, 40)}
        text = '\n'.join(J.report_lines(d, curve))
        self.assertIn('Levelling journey on foot (O654)', text)
        self.assertIn('Tester Jny (Knight): level 8 to 19', text)
        self.assertIn('levels 9-14: 50.0 min (model 50.0, x1.0) ok', text)
        self.assertIn('helper teleports in place of walking: 0', text)
        slow = {lv: 1.0 for lv in range(1, 40)}
        self.assertIn('slow', '\n'.join(J.report_lines(d, slow)))
        self.assertIn('no model', '\n'.join(J.report_lines(d, None)))
        self.assertEqual(J.report_lines({}, curve), [])
        json.dumps(d)                 # run.json takes it

    def test_report_counts_fallbacks(self):
        j = new_journey()
        j.fall('hall', 'no gate')
        j.fall('town', 'no portal')
        text = '\n'.join(J.report_lines({j.name: j.as_dict(0.0)}, None))
        self.assertIn('helper teleports in place of walking: 2 (hall 1, town 1)', text)

    def test_the_model_is_read(self):
        curve = J.curve_for(40)       # luajit or lua5.3 on this checkout; None only where neither is installed
        if curve is not None:
            self.assertTrue(curve and all(v > 0 for v in curve.values()))


class Journey(unittest.TestCase):
    def play(self, w, seconds, j=None):
        j = j or new_journey(w.level)
        why = run(j.play(w, seconds))
        return j, why

    def test_a_whole_journey_on_foot(self):
        w = World(level=8, lvl_s=30.0)
        j, why = self.play(w, 3 * 3600)
        self.assertEqual(why, 'time')
        self.assertEqual(w.teleports, [], 'no helper teleport: %r' % w.teleports)
        self.assertGreater(w.level, 60, 'the bot levelled by fighting (level %d)' % w.level)
        ids = [h['id'] for h in j.hunts]
        self.assertEqual(ids[0], 'rats', ids)                       # level 8: the first hunt, found by widening the window
        self.assertIn('bog', ids)                                   # a hunt on floor 6: the stairs were walked
        self.assertIn('keep', ids)                                  # and the stairs back down
        order = [HUNT_ORDER.index(i) for i in ids if i in HUNT_ORDER]
        self.assertEqual(order, sorted(order), 'the bot only moves on: %r' % ids)
        self.assertGreater(j.moves, 2)
        self.assertEqual(j.fallback_counts, {})
        self.assertGreater(j.steps, 100)
        self.assertGreater(len(j.per_level), 40)
        mins = sorted(v for lv, v in j.per_level.items() if lv > 9)
        self.assertTrue(0.45 <= mins[len(mins) // 2] <= 0.7, 'median minutes per level %.2f (30 s of fighting a level)' % mins[len(mins) // 2])
        self.assertLess(mins[-1], 8.0, 'the longest level, with a trip or a move in it, %.1f min' % mins[-1])
        self.assertIn(J.TOWN_WORDS, w.said, 'it left by the town portal')
        self.assertGreater(w.loots, 5)
        self.assertGreater(w.keeps, 2)
        json.dumps(j.as_dict(w.t))

    def test_trips_sell_buy_and_open_the_depot(self):
        w = World(level=8, lvl_s=60.0)
        j, _ = self.play(w, 2 * 3600)
        self.assertGreaterEqual(j.trips, 2)
        buyer, apo = w.shopped.count('Loot Buyer'), w.shopped.count('Veyra the Apothecary')
        self.assertIn(buyer, (j.trips, j.trips - 1))                # the last trip may be under way when the time is over
        self.assertIn(apo, (buyer, buyer - 1))
        self.assertIn(w.lockers, (j.trips, j.trips - 1))            # the locker beside the temple, at the start of every trip
        self.assertEqual((j.sold, j.bought), (3 * len(w.shopped), 5 * len(w.shopped)))
        self.assertEqual(w.teleports, [])
        # a full bag calls the trip at once, not after TRIP_EVERY
        w = World(level=8, lvl_s=600.0)
        w.sell_flag = True
        j, _ = self.play(w, 900)
        self.assertGreaterEqual(j.trips, 1)
        self.assertLess(w.t, J.TRIP_EVERY)

    def test_no_gate_is_the_counted_fallback(self):
        w = World(level=8, gate=False)
        j, _ = self.play(w, 600)
        self.assertEqual(w.teleports[0][0], 'hall')
        self.assertIn('hall', j.fallback_counts)
        self.assertIn('no teleport to the hall near the temple', j.fallbacks[0])
        self.assertTrue(j.hunts, 'and it goes on on foot from the hall')

    def test_a_gate_that_cannot_be_walked_to_is_a_fallback_after_two_tries(self):
        w = World(level=8, gate_walk=False)
        j, _ = self.play(w, 600)
        self.assertEqual(w.teleports[0][0], 'hall')
        self.assertIn('the walk to the teleport failed 2 times', j.fallbacks[0])
        self.assertGreaterEqual(len(j.stuck), 2, 'each failed walk is a stuck event with its reason')
        self.assertIn('no path', j.stuck[0])

    def test_a_hunt_that_cannot_be_walked_to_is_a_jump(self):
        w = World(level=8, path_to_hunt=False)
        j, _ = self.play(w, 600)
        self.assertIn('jump', j.fallback_counts)
        self.assertTrue(any('the walk to the teleport of' in f for f in j.fallbacks))
        self.assertEqual(j.hunts[0]['id'], 'rats')

    def test_no_stairs_is_a_jump_too(self):
        w = World(level=60, stairs=False, lvl_s=1000.0)
        j, _ = self.play(w, 900)
        self.assertIn('jump', j.fallback_counts)
        self.assertTrue(any('no way to floor 6' in f for f in j.fallbacks), j.fallbacks)

    def test_a_refusing_teleport_is_left_alone(self):
        w = World(level=8, refuse=True)
        j, _ = self.play(w, 900)
        self.assertEqual(j.hunts, [])
        self.assertTrue(j.skip, 'the refused hunt is skipped for a while')
        self.assertTrue(any(w.helpers[i].startswith('journey') and 'skip' in w.helpers[i] for i in range(len(w.helpers))), 'and told to the helper')

    def test_no_town_portal_falls_back_to_the_camp_then_town(self):
        w = World(level=8, lvl_s=30.0, portal=False, camp=False)
        j, _ = self.play(w, 2 * 3600)
        self.assertIn('town', j.fallback_counts)
        self.assertTrue(any('no town portal beside the bot' in f for f in j.fallbacks))

    def test_no_town_portal_but_a_camp_portal(self):
        w = World(level=8, lvl_s=30.0, portal=False, camp=True)
        j, _ = self.play(w, 1800)
        self.assertEqual(w.teleports, [], 'the camp portal is a way a person walks: %r' % w.teleports)
        self.assertGreaterEqual(len(j.hunts), 2)
        self.assertEqual(j.fallback_counts, {})

    def test_a_flee_is_counted(self):
        w = World(level=8, lvl_s=600.0)
        w.flee_at = 600.0            # the bot's own flee: the helper's town teleport, not the journey's
        j, _ = self.play(w, 900)
        self.assertEqual(j.fallback_counts.get('flee'), 1)
        self.assertGreaterEqual(len(j.hunts), 1)

    def test_death_and_the_way_back(self):
        w = World(level=8, lvl_s=60.0)
        j = new_journey(8)
        w.die_at = 500.0
        why = run(j.play(w, 3000))
        self.assertEqual(why, 'gone')
        self.assertEqual(w.zone(), 'other')
        # the server puts a dead character in the temple; the bot logs in again and the journey goes on
        w.up, w.pos, w.hunt, w.mon = True, TEMPLE, None, None
        w.t += 60.0
        j.deaths_seen(1, w.t)
        self.assertEqual((j.deaths, j.hunt, j.target), (1, None, None))
        run(j.play(w, 1800))
        self.assertGreaterEqual(len(j.hunts), 2, 'it walked to a hunt again')
        self.assertEqual(w.teleports, [])
        self.assertEqual(j.as_dict(w.t)['deaths'], 1)

    def test_a_hunt_without_monsters_is_given_up(self):
        w = World(level=30, lvl_s=1.0e9, monsters=False)
        j, _ = self.play(w, 2400)
        self.assertGreaterEqual(len(j.hunts), 1)
        self.assertTrue(any('no monster in sight' in x for x in j.log), j.log[-6:])
        self.assertIn(j.hunts[0]['id'], j.skip)

    def test_no_helper_ends_it(self):
        class Deaf(World):
            async def helper(self, command, kind, wait=4.0):
                self.t += 0.2
                return None
        w = Deaf()
        j, why = self.play(w, 600)
        self.assertEqual(why, 'no helper')

    def test_a_hunt_that_fits_is_kept(self):
        w = World(level=100, lvl_s=1.0e9)
        j, _ = self.play(w, 1200)
        self.assertEqual([h['id'] for h in j.hunts], ['keep'])      # no hop to another hunt while the level still fits it
        self.assertEqual(j.moves, 0)

    def test_emit_sees_every_look(self):
        w = World(level=8)
        seen = []
        run(new_journey(8).play(w, 120, emit=lambda j: seen.append(j.level)))
        self.assertGreater(len(seen), 3)


HUNT_ORDER = ['rats', 'cave', 'bog', 'keep', 'ruin']


# ------------------------------------------------------------------------------------------------ the bot of testers.py on the same world
import testers as T  # noqa: E402
import time as _real_time  # noqa: E402


class _Drain:
    async def drain(self):
        pass

    def close(self):
        pass


class Conn:
    """the bot's connection: walk packets move the world's bot, the locker use, the sale and the purchase packets are kept"""
    WALK = {b'\x65': (0, -1), b'\x66': (1, 0), b'\x67': (0, 1), b'\x68': (-1, 0)}

    def __init__(self, world):
        self.world, self.sent, self.w = world, [], _Drain()

    def send(self, data):
        self.sent.append(bytes(data))
        if data in self.WALK:
            self.world.step_sync(*self.WALK[data])


class FakeTime:
    """testers.time: the clock is the world's"""

    def __init__(self, world):
        self.world = world

    def monotonic(self):
        return self.world.t

    def __getattr__(self, name):
        return getattr(_real_time, name)


class Args:
    host = '127.0.0.1'
    ops = {'lootfilter': 41}
    backpack_client_id = 0
    journey = True
    keystones = checks = closed = False
    after_login = ''
    scenarios_runner = None
    next_request = None
    on_answer = None


ENTRY = {'account': 'tstbot0123456789', 'password': 'x', 'name': 'Tester Jny', 'class': 'Knight', 'level': 8, 'vocation': 4}


class Integration(unittest.TestCase):
    def bot(self, world):
        bot = T.TesterBot(3, dict(ENTRY), Args(), 1, T.Results(1), {'rotation': [], 'heal': None})
        bot.conn, bot.alive, bot.died, bot.cid, bot.level = Conn(world), True, False, 777, 8
        bot.said = []
        T.ONLINE.clear()
        T.ONLINE[777] = bot   # CheckIO.step_of walks the bots of ONLINE
        self.addCleanup(T.ONLINE.clear)

        def say(text, kind=1):
            bot.said.append((text, kind))
            if text == 'trade':
                bot.shop = [{'id': 7618, 'sub': 0, 'name': 'health potion', 'buy': 50, 'sell': 0},
                            {'id': 7620, 'sub': 0, 'name': 'mana potion', 'buy': 60, 'sell': 0},
                            {'id': 2148, 'sub': 0, 'name': 'bones', 'buy': 0, 'sell': 5}]
            asyncio.get_event_loop_policy()   # no loop needed: the say of the world is a plain call
            world.said.append(text)
            if text == J.TOWN_WORDS and world.zone() == 'other' and world.opts['portal']:
                world.portal = (world.pos[0] + 1, world.pos[1], world.pos[2])
        bot.say = say

        async def helper_says(command, kind, wait=4.0):
            return await world.helper(command, kind, wait)
        bot.helper_says = helper_says
        return bot

    def patched(self, world, fn):
        real_sleep, real_time = asyncio.sleep, T.time
        T.time = FakeTime(world)

        async def adv(seconds, *a, **k):
            await world.sleep(seconds)
        asyncio.sleep = adv
        try:
            return fn()
        finally:
            asyncio.sleep, T.time = real_sleep, real_time

    def test_the_flags(self):
        a = T.parse(['run', '--journey', '--server-dir', 'x', '--key-file', 'y'])
        self.assertTrue(a.journey)
        self.assertFalse(T.parse(['run', '--server-dir', 'x', '--key-file', 'y']).journey)
        for other in ('--checks', '--closed', '--keystones'):
            with self.assertRaises(SystemExit):
                T.parse(['run', '--journey', other, '--server-dir', 'x', '--key-file', 'y'])
        s = T.parse(['setup', '--journey', '--levels', '8', '--server-dir', 'x'])
        self.assertEqual((s.town, s.levels), (J.TOWN, '8'))

    def test_start_position(self):
        self.assertEqual(J.start_position([[1, 2, 7], [32370, 32240, 7], [32369, 32241, 8]]), (32370, 32240, 7))
        self.assertEqual(J.start_position([]), J.TEMPLE)
        self.assertEqual(J.start_position(None), J.TEMPLE)

    def test_the_bot_plays_a_journey(self):
        w = World(level=8, lvl_s=40.0)
        bot = self.bot(w)
        clock = {'stop': False, 'until': 4000.0}
        ok = self.patched(w, lambda: asyncio.run(bot.do_journey(clock)))
        self.assertTrue(ok)
        self.assertTrue(bot.stay and bot.back_at is None, 'the helper walk back to a hunt spot is off')
        d = bot.results.d['journey']['Tester Jny']
        self.assertGreater(d['level'], 30)
        self.assertEqual(d['fallback_counts'], {})
        self.assertGreaterEqual(len(d['hunts']), 3)
        self.assertGreater(d['legs']['steps'], 50)
        self.assertEqual(w.teleports, [])
        self.assertTrue(any(m[:1] == b'\x82' for m in bot.conn.sent) or d['trips'] == 0)
        json.dumps(bot.results.d)
        # the same Journey goes on after a death and a new login
        j1 = bot.journey
        bot.on_death()
        bot.died, w.up, w.pos, w.hunt, w.mon, w.t = False, True, TEMPLE, None, None, 4500.0
        clock['until'] = 6500.0
        self.patched(w, lambda: asyncio.run(bot.do_journey(clock)))
        self.assertIs(bot.journey, j1)
        self.assertEqual(bot.results.d['journey']['Tester Jny']['deaths'], 1)

    def test_the_shop_and_the_locker(self):
        w = World()
        bot = self.bot(w)
        io = T.JourneyIO(bot, {'stop': False, 'until': 1e9})
        r = self.patched(w, lambda: asyncio.run(io.shop_here('Veyra the Apothecary')))
        self.assertEqual(r, {'sold': 0, 'bought': 2 * J.POTION_BUY, 'window': True} if False else r)
        self.assertTrue(r['window'] and r['bought'] == 2 * J.POTION_BUY and r['sold'] == 1)
        sent = bot.conn.sent
        self.assertEqual(sum(1 for m in sent if m[:1] == b'\x7a'), 2)        # a purchase of each potion
        self.assertEqual(sum(1 for m in sent if m[:1] == b'\x7b'), 1)        # the sale of what the window buys
        self.assertEqual(sent[-1], b'\x7c')                                  # the window closed
        self.assertEqual([t for t, _ in bot.said], ['hi', 'trade', 'bye'])
        self.assertEqual(bot.said[1][1], T.NPC_CHANNEL)
        lk = {'x': 53, 'y': 52, 'z': 7, 'cid': 12589, 'sp': 1}
        self.assertTrue(self.patched(w, lambda: asyncio.run(io.open_locker(lk))))
        self.assertTrue(any(m[:1] == b'\x82' for m in bot.conn.sent) and bot.conn.sent[-1] == b'\x87\x00')
        self.assertFalse(self.patched(w, lambda: asyncio.run(io.open_locker({'x': 1}))))

    def test_the_report_has_the_journey(self):
        import tempfile
        d = tempfile.mkdtemp()
        j = new_journey(8)
        j.seen(0.0)
        j.level_seen(8, 0.0)
        for lv in range(9, 15):
            j.level_seen(lv, (lv - 8) * 300.0)
        j.fall('hall', 'no gate')
        with open(os.path.join(d, 'state.json'), 'w') as f:
            json.dump({'bots': [], 'run': {'started': 1, 'minutes': 5, 'count': 1}}, f)
        with open(os.path.join(d, 'run.json'), 'w') as f:
            json.dump({'journey': {j.name: j.as_dict(1800.0)}, 'bots': 1, 'behaviours': {}, 'failures': {}, 'lua_errors': {}, 'kicks': {},
                       'anomalies': [], 'first': {}, 'coverage': {}}, f)
        a = T.Args()
        a.state, a.log, a.scenarios = d, '', ''
        text = T.report_text(a)
        self.assertIn('Levelling journey on foot (O654)', text)
        self.assertIn('Tester Jny (Knight): level 8 to 14', text)
        self.assertIn('helper teleports in place of walking: 1 (hall 1)', text)

if __name__ == '__main__':
    unittest.main()

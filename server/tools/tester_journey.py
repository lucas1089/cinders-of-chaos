#!/usr/bin/env python3
"""The levelling journey of the tester bots (O654, server/README.md "The levelling journey on foot (O654)"; tests: tester_journey_test.py).

A bot of this mode levels from its level onward the way a person does: it reads the next hunt of its level (the helper's `!tester journey`:
the hunts of the teleport room and the window of progression_config.lua, the temple's great teleport, the stairs of the hall), WALKS there by
the engine's own path (`!tester path pos X Y Z`), steps onto the temple's teleport and the hunt's teleport itself, hunts there (walks to the
nearest monster, fights with its own rotation), moves on when its level has outgrown the hunt, goes back to town by the Town Portal spell (the
camp portal, then the helper's `town`, only as a counted fallback), and on a trip sells at the Loot Buyer, buys potions at the Apothecary and opens the
depot locker. It dies and goes on from the temple. Minutes per level are logged for tools/progression_model.lua --curve-json.

Every helper teleport (`journey hall`, `journey jump`, `town`, a flee) is a counted fallback with its reason (`fallbacks` in run.json and the
report: "helper teleports in place of walking"). The helper only reads the screen and gives the path; the steps, the speech, the fights, the
sales and the walks are the bot's own.

The pure parts (level log, report text) and the play loop on an `io` (the interface of tester_checks: alive, sleep, helper, say, step, loot,
request; plus now, open_locker, shop_here, keep). testers.py `JourneyIO` is the real one, the test has a mocked world.
"""
import json
import os

import tester_checks as TX

LOOK = 1.0              # seconds between two looks at the screen while the bot hunts
ANSWER = 6.0            # seconds to wait for the helper's answer
HELPER_WAIT = 15.0      # the helper's teleports (the fallbacks)
SETTLE = 3.0            # seconds after a step onto a teleport or a stair before the next look
PORTAL_CAST = 3.6       # the Town Portal channel is 3 s (townportal_config.lua castMs)
TOWN_WORDS = 'ash domh'  # spells_chaos.xml Town Portal, every class from level 1
TRIP_EVERY = 1500.0     # seconds between two trips to town (sell, buy, depot) when nothing calls one earlier
KEEP_EVERY = 240.0      # seconds between two looks at the bag (the potion top-up, a better piece, junk)
MIN_HUNT = 120.0        # seconds at a hunt before the band may move the bot on
MOVE_LOOKS = 3          # looks in a row that say "this hunt no longer fits" before it leaves
IDLE_LEAVE = 120.0      # seconds with no monster in sight at a hunt: the hunt is given up for a while
FIGHT_RANGE = 5         # tiles: the helper's own target (its loop) takes a monster this near, the bot fights
CHASE_ROUNDS = 2        # asks for a path to a monster in sight before the next look
LOOT_EVERY = 20.0       # seconds between two loot takes at a hunt
MISSES = 8              # looks without an answer in a row: the helper is not there
GATE_TRIES = 2          # walks to a teleport that did not take the bot before it uses the helper's teleport
SKIP_FOR = {'idle': 600.0, 'hot': 900.0, 'refused': 900.0, 'deaths': 1800.0, 'blocked': 900.0}
DEATH_SKIP = 2          # deaths at one hunt in DEATH_WINDOW seconds: the hunt is left alone for SKIP_FOR['deaths']
DEATH_WINDOW = 1200.0
TRIP_NPCS = (('Loot Buyer', 'lootbuyer'), ('Veyra the Apothecary', 'apothecary'))   # npc_travel_config.lua npcs
KEEP_LIST = 40          # rows of a list in run.json
FALLBACK_LIST = 30
POTION_BUY = 20         # potions bought in a visit of the Apothecary

TOWN = 2                        # Cinderhold: where every character starts and where the teleport room is (newplayer_config.lua homeTown)
TEMPLE = (32369, 32241, 7)      # its temple (temple_portals_config.lua)

# what the report's levels block is held to: 3x each way as journey_report.py (the model counts no walking, no loot and no trips)
TOLERANCE = 3.0
BLOCK = 5


# ------------------------------------------------------------------------------------------------ pure parts
def pos_of(d):
    """(x, y, z) of a {x, y, z} answer, None when it is not one"""
    if isinstance(d, dict) and all(isinstance(d.get(k), int) and not isinstance(d.get(k), bool) for k in 'xyz'):
        return d['x'], d['y'], d['z']
    return None


def start_position(temples):
    """where a journey character begins: the temple of Cinderhold (the temple mark of data/chaos_poi.lua nearest to it; the constant when the
    list is empty)"""
    marks = [tuple(t) for t in temples or [] if len(t) >= 3]
    if not marks:
        return TEMPLE
    return min(marks, key=lambda t: (abs(t[0] - TEMPLE[0]) + abs(t[1] - TEMPLE[1]) + 100 * abs(t[2] - TEMPLE[2]), t))


def state_command(keep, skip):
    """`journey [keep ID] [skip ID,ID]`: the hunt it is at stays while it fits; hunts that hurt it are left out. An id the helper would refuse
    (not plain) is dropped here, so a bad id never makes the whole command fail"""
    def ok(i):
        return isinstance(i, str) and 0 < len(i) <= 48 and all(c.isalnum() or c in '_.-' for c in i)
    cmd = 'journey'
    if ok(keep):
        cmd += ' keep ' + keep
    ids = [i for i in sorted(skip or []) if ok(i)][:24]
    if ids:
        cmd += ' skip ' + ','.join(ids)
    return cmd


def step_toward(src, dst, avoid=None):
    """the cardinal steps from tile src onto the adjacent tile dst (a diagonal is two steps: along x, then along y, or the other way when
    the first way crosses the tile `avoid`, a teleport the bot must not step on yet); [] when it is the same tile or not adjacent"""
    if src is None or dst is None or src[2] != dst[2]:
        return []
    dx, dy = dst[0] - src[0], dst[1] - src[1]
    if (dx, dy) == (0, 0) or abs(dx) > 1 or abs(dy) > 1:
        return []
    if dx and dy:
        if avoid is not None and (src[0] + dx, src[1], src[2]) == tuple(avoid):
            return [(0, dy), (dx, 0)]
        return [(dx, 0), (0, dy)]
    return [(dx, 0)] if dx else [(0, dy)]


def blocks_of(per_level, expected, tolerance=TOLERANCE, block=BLOCK):
    """the minutes per level of a bot against the model by blocks of levels: journey_report.compare (rows with levels, actual, expected,
    ratio, status). Without a model every row is "no model"."""
    import journey_report as JR
    pl = {int(k): float(v) for k, v in (per_level or {}).items()}
    return JR.compare(pl, expected or {}, tolerance, block)


def curve_for(levels_top):
    """{level: minutes} of the model up to `levels_top` (journey_report.expected_curve on this checkout's server folder), None without Lua"""
    import journey_report as JR
    here = os.path.dirname(os.path.abspath(__file__))
    return JR.expected_curve(os.path.normpath(os.path.join(here, '..')), max(2, int(levels_top)))


def report_lines(journeys, curve=None):
    """the "Journey" section of the report: per bot the levels, the minutes per block of levels against the model, the hunts, the trips,
    the deaths and the helper teleports in place of walking. `journeys` is run.json's `journey` ({bot: as_dict})"""
    out = []
    if not journeys:
        return out
    total_fb, kinds = 0, {}
    out.append('== Levelling journey on foot (O654)')
    for name in sorted(journeys):
        j = journeys[name]
        fb = j.get('fallback_counts') or {}
        total_fb += sum(fb.values())
        for k, n in fb.items():
            kinds[k] = kinds.get(k, 0) + n
        out.append('  %s (%s): level %s to %s in %.1f minutes; %d hunts, %d trips, %d deaths, %d stuck; walked %d legs (%d steps); '
                   'helper teleports %d' % (name, j.get('class', '?'), j.get('start_level'), j.get('level'), j.get('minutes', 0.0),
                                             len(j.get('hunts') or []), j.get('trips', 0), j.get('deaths', 0), len(j.get('stuck') or []),
                                             (j.get('legs') or {}).get('walks', 0), (j.get('legs') or {}).get('steps', 0), sum(fb.values())))
        rows = blocks_of(j.get('per_level'), curve)
        if not rows:
            out.append('    no level completed yet')
        for r in rows:
            exp = '-' if r['expected'] is None else '%.1f' % r['expected']
            ratio = '-' if r['ratio'] is None else 'x%.1f' % r['ratio']
            out.append('    levels %d-%d: %.1f min (model %s, %s) %s' % (r['levels'][0], r['levels'][1], r['actual'], exp, ratio, r['status']))
        for s in (j.get('stuck') or [])[:3]:
            out.append('    stuck: %s' % s)
    out.append('  helper teleports in place of walking: %d%s' % (total_fb, (' (%s)' % ', '.join('%s %d' % (k, kinds[k]) for k in sorted(kinds))) if kinds else ''))
    return out


# ------------------------------------------------------------------------------------------------ the journey of one bot
class Journey:
    """the state of one bot's levelling journey; survives a death and a new login (the TesterBot keeps it, as it keeps its CheckRun)"""

    def __init__(self, name, cls, level, seed=0):
        self.name, self.cls, self.start_level, self.level = name, cls, level, level
        self.seed = seed
        self.t0 = None              # the clock of the first look
        self.since = None           # the clock when the current level began (None until a level is crossed)
        self.last_seen = None       # the clock of the last look (the gap of a new login is not played time)
        self.per_level = {}         # completed level -> minutes
        self.hunt = None            # {id, n, lo, hi, at} of the hunt the bot hunts at
        self.target = None          # the pick it walks to
        self.hunts = []             # every hunt it went to: {id, n, lo, hi, level, at}
        self.skip = {}              # hunt id -> until
        self.deaths_at = {}         # hunt id -> clocks of the deaths there
        self.deaths = 0
        self.top = level            # the highest level seen: a level lost by a death and won again is not a level completed twice
        self.floor = None
        self.pos = None             # O727: (x, y, z) of the last look, for the staff's live map
        self.trips = 0
        self.last_trip = None
        self.sell_due = False
        self.todo = []              # the steps of the trip under way
        self.zone = None
        self.expect = None          # the zone a leg of its own is to end in ('temple' for the Town Portal)
        self.tries = {}
        self.misses = 0
        self.more = 0               # looks in a row that say "move on"
        self.idle_since = None
        self.last_loot = 0.0
        self.last_keep = 0.0
        self.fallbacks = []
        self.fallback_counts = {}
        self.stuck = []
        self.walks = 0
        self.steps = 0
        self.sold = 0
        self.bought = 0
        self.moves = 0
        self.fights = 0
        self.stage = 'start'
        self.log = []               # notable events of this run
        self.sink = None            # a function of one text: the TesterBot writes them to the activity log as they happen
        self.died_seen = 0.0

    # ---- bookkeeping
    def note(self, text):
        if len(self.log) < 400:
            self.log.append(text)
        if self.sink:
            self.sink(text)

    def fall(self, kind, why):
        """a helper teleport in place of walking (or a flee): counted with its reason"""
        self.fallback_counts[kind] = self.fallback_counts.get(kind, 0) + 1
        self.fallbacks.append('%s (%s)' % (kind, str(why or 'no reason')[:60]))
        del self.fallbacks[:-FALLBACK_LIST]
        self.note('fallback %s: %s' % (kind, why))

    def stuck_at(self, now, what, why, pos=None):
        self.stuck.append('%s: %s%s at %.0f s' % (what, str(why)[:60], ' (%s)' % ','.join(str(v) for v in pos) if pos else '', now - (self.t0 or now)))
        del self.stuck[:-KEEP_LIST]
        self.note('stuck %s: %s' % (what, why))

    def active_skip(self, now):
        return {i for i, until in self.skip.items() if until > now}

    def avoid(self, hid, kind, now):
        if hid:
            self.skip[hid] = now + SKIP_FOR[kind]
            self.note('leaves hunt %s alone for %d s (%s)' % (hid, SKIP_FOR[kind], kind))

    def seen(self, now):
        """a look at the screen: the clock of the journey"""
        if self.t0 is None:
            self.t0 = self.last_seen = self.last_trip = now
            return
        self.last_seen = now

    def resumed(self, now):
        """the bot is in game again after a death or a new login: the gap is not time spent levelling (a character offline levels no level)"""
        if self.last_seen is not None and now - self.last_seen > 5.0 and self.since is not None:
            self.since += now - self.last_seen - 5.0
        self.last_seen = now

    def deaths_seen(self, count, now):
        """`count` new deaths since the last call: the hunt it died at is left alone after DEATH_SKIP of them close together; the route starts again at the temple"""
        for _ in range(max(0, count)):
            self.deaths += 1
            hid = (self.hunt or {}).get('id')
            if hid:
                ds = [t for t in self.deaths_at.get(hid, []) if now - t <= DEATH_WINDOW] + [now]
                self.deaths_at[hid] = ds
                if len(ds) >= DEATH_SKIP:
                    self.avoid(hid, 'deaths', now)
            self.note('died at %s' % ((self.hunt or {}).get('n') or 'a hunt'))
            self.hunt = None
            self.target = None
            self.todo = []
            self.expect = None

    def level_seen(self, level, now):
        """the level read off the screen: minutes of each level the bot completed. The level the journey began in is not completed by the
        bot (it began part way): its time is left out; a jump of several levels at once splits the time evenly"""
        if not isinstance(level, int) or level < 1:
            return
        if level > self.top:
            if self.since is not None:
                minutes = (now - self.since) / 60.0 / (level - self.top)
                for lv in range(self.top, level):
                    self.per_level[lv] = round(self.per_level.get(lv, 0.0) + minutes, 3)
            self.since = now
            self.note('level %d -> %d' % (self.top, level))
            self.top = level
        self.level = level

    def minutes(self, now):
        return 0.0 if self.t0 is None else round((now - self.t0) / 60.0, 2)

    def as_dict(self, now=None):
        return {'name': self.name, 'class': self.cls, 'start_level': self.start_level, 'level': self.level,
                'minutes': self.minutes(now if now is not None else (self.last_seen or 0.0)),
                'per_level': {str(k): v for k, v in sorted(self.per_level.items())}, 'deaths': self.deaths, 'trips': self.trips,
                'hunts': self.hunts[-KEEP_LIST:], 'stuck': self.stuck[-KEEP_LIST:], 'stage': self.stage,
                'legs': {'walks': self.walks, 'steps': self.steps}, 'sold': self.sold, 'bought': self.bought, 'moves': self.moves,
                'fallback_counts': dict(self.fallback_counts), 'fallbacks': self.fallbacks[-FALLBACK_LIST:]}

    # ---- the play loop
    async def play(self, io, seconds=None, emit=None):
        """plays until the bot is gone or `seconds` of the io's clock are over; `emit(journey)` is called after each look (the results
        file); returns why it stopped: 'gone', 'time' or 'no helper'"""
        t_end = None if seconds is None else io.now() + seconds
        self.resumed(io.now())
        while io.alive():
            if t_end is not None and io.now() >= t_end:
                return 'time'
            s = await self.look(io)
            if s is False:
                return 'no helper'
            if s is None:
                continue
            if emit:
                emit(self)
            await self.act(io, s)
        return 'gone'

    async def look(self, io):
        s = await io.helper(state_command((self.hunt or {}).get('id'), self.active_skip(io.now())), 'journey', ANSWER)
        if not isinstance(s, dict) or s.get('err') or pos_of(s.get('pos')) is None:
            self.misses += 1
            if self.misses >= MISSES:
                self.note('no answer of the helper to `journey`: %s' % (s or {}).get('err', 'none') if isinstance(s, dict) else 'none')
                return False
            await io.sleep(LOOK)
            return None
        self.misses = 0
        now = io.now()
        self.pos = list(pos_of(s.get('pos')))
        self.seen(now)
        self.level_seen(s.get('level'), now)
        self.arrive(s, now)
        return s

    def arrive(self, s, now):
        """what the zone says about where the bot has got to: a hunt reached, the temple reached (by the portal it cast, or by a teleport
        it did not ask for: a flee), a floor of the hall"""
        zone = s.get('zone')
        floor = (pos_of(s.get('pos')) or (0, 0, 0))[2]
        if floor != self.floor:
            self.floor = floor
            self.tries = {}
        if zone == self.zone:
            return
        before, self.zone = self.zone, zone
        self.tries = {}
        self.more = 0
        self.idle_since = None
        if zone == 'other' and before in ('hall', 'temple') and self.target:
            h = self.target
            self.hunt = {'id': h.get('id'), 'n': h.get('n'), 'lo': h.get('lo'), 'hi': h.get('hi'), 'b': h.get('b'), 'at': now}
            self.hunts.append({'id': h.get('id'), 'n': h.get('n'), 'lo': h.get('lo'), 'hi': h.get('hi'), 'level': self.level,
                               'at': round((now - (self.t0 or now)) / 60.0, 1)})
            del self.hunts[:-KEEP_LIST]
            self.target = None
            self.stage = 'hunt'
            self.note('at hunt %s (levels %s-%s) at level %s' % (h.get('n'), h.get('lo'), h.get('hi'), self.level))
        elif zone == 'temple':
            if before == 'other' and self.expect != 'temple':
                self.fall('flee', 'a teleport to the temple the bot did not ask for')
            self.expect = None
            self.hunt = None
            self.target = None
            self.stage = 'town'
        elif zone == 'hall':
            self.hunt = None
            self.expect = None   # the camp portal brought it to the hall: the leg to the temple is over
            self.stage = 'hall'

    async def act(self, io, s):
        zone = s.get('zone')
        if zone == 'temple':
            await self.at_temple(io, s)
        elif zone == 'hall':
            await self.at_hall(io, s)
        else:
            await self.in_field(io, s)
        await io.sleep(LOOK)   # a look a second at most, whatever the leg did (and a walk that fails at once never spins)

    # ---- walking
    async def walk(self, io, command, near, what):
        """on foot by the engine path: -> (how, got) of tester_checks.walk_by_path ('foot', 'err', 'far'); a failed walk is a stuck event"""
        r = {'lead': True, 'name': self.name}
        self.walks += 1
        how, got = await TX.walk_by_path(Counting(io, self), r, command, 'path', near)
        if how != 'foot':
            self.stuck_at(io.now(), what, (got or {}).get('err') or 'the walk did not arrive', pos_of((got or {}).get('pos')))
        return how, got

    async def onto(self, io, dest, got=None, avoid=None):
        """the steps from where the bot stands onto the next tile `dest` (a teleport, a stair, a portal): the last answer of the walk knows
        where the bot stands; otherwise the helper is asked"""
        here = pos_of((got or {}).get('pos'))
        if here is None:
            a = await io.helper('journey', 'journey', ANSWER)
            here = pos_of((a or {}).get('pos')) if isinstance(a, dict) else None
        for dx, dy in step_toward(here, pos_of(dest), avoid):
            await io.step(dx, dy)
            self.steps += 1
            await io.sleep(TX.RAID_STEP)
        await io.sleep(SETTLE)

    async def step_on(self, io, goal, what, near=1, avoid=None):
        """walks next to `goal` ({x, y, z} of a teleport, a stair or a portal) and steps onto it; -> True when it did the steps"""
        how, got = await self.walk(io, 'path pos %d %d %d' % pos_of(goal), near, what)
        if how != 'foot':
            return False
        here = pos_of((got or {}).get('pos'))
        want = pos_of(goal)
        if here is not None and here != want and max(abs(here[0] - want[0]), abs(here[1] - want[1])) > 1:
            return False
        await self.onto(io, goal, got, avoid)
        return True

    async def helper_teleport(self, io, command, kind, why):
        a = await io.helper(command, 'journey', HELPER_WAIT)
        if isinstance(a, dict) and not a.get('err'):
            self.fall(kind, why)
            await io.sleep(SETTLE)
            return True
        self.stuck_at(io.now(), kind, (a or {}).get('err') if isinstance(a, dict) else 'no answer', None)
        return False

    # ---- the temple
    def trip_wanted(self, now):
        return self.sell_due or now - (self.last_trip if self.last_trip is not None else now) >= TRIP_EVERY

    async def at_temple(self, io, s):
        now = io.now()
        if not self.todo and self.hunt is None and self.target is None and self.trip_wanted(now):
            self.todo = ['depot', 'gate'] + ['npc:' + n for n, _ in TRIP_NPCS]
            self.trips += 1
            self.stage = 'trip'
            self.note('trip to town: depot, Loot Buyer, Apothecary')
        if self.todo and self.todo[0] == 'depot':
            self.todo.pop(0)
            await self.depot(io, s)
            return
        if self.todo and self.todo[0] == 'gate':
            self.todo.pop(0)
        await self.take_gate(io, s)

    async def depot(self, io, s):
        """walks to the depot locker next to the temple and opens it, as a person does for the stash"""
        lk = s.get('locker')
        spot = lk.get('spot') if isinstance(lk, dict) else None
        if not spot:
            self.note('no depot locker near the temple: the depot is left out of the trip')
            return
        how, got = await self.walk(io, 'path pos %d %d %d' % pos_of(spot), 0, 'the depot locker')
        if how != 'foot':
            return
        await io.open_locker(lk)
        await io.sleep(SETTLE)

    async def take_gate(self, io, s):
        """the temple's great teleport into the teleport room: on foot, then the step onto it; the helper's `journey hall` is the fallback"""
        gate = s.get('gate')
        n = self.tries['gate'] = self.tries.get('gate', 0) + 1
        if n > GATE_TRIES or not gate:
            why = 'no teleport to the hall near the temple' if not gate else 'the walk to the teleport failed %d times' % GATE_TRIES
            self.tries['gate'] = 0
            if not await self.helper_teleport(io, 'journey hall', 'hall', why):
                await io.sleep(5.0)
            return
        if not await self.step_on(io, gate, 'the temple teleport'):
            return
        await io.sleep(SETTLE)

    # ---- the teleport room
    async def at_hall(self, io, s):
        now = io.now()
        if self.todo and self.todo[0].startswith('npc:'):
            name = self.todo.pop(0)[4:]
            await self.visit(io, name)
            if not self.todo:
                self.last_trip, self.sell_due, self.stage = now, False, 'hall'
                self.note('back from town')
            return
        if self.todo:
            self.todo.pop(0)
        pick = s.get('pick')
        if not isinstance(pick, dict) or not pick.get('t') or s.get('above'):
            self.note('no hunt this level may enter (%s)' % (pick or {}).get('n'))
            self.stage = 'wait'
            await io.sleep(10.0)
            return
        self.target = pick
        pos = pos_of(s.get('pos'))
        tz = pos_of(pick.get('t'))[2]
        if pos[2] != tz:
            await self.stairs(io, s, tz)
            return
        n = self.tries['hunt'] = self.tries.get('hunt', 0) + 1
        if n > GATE_TRIES + 1:
            self.avoid(pick.get('id'), 'refused', now)
            self.tries['hunt'] = 0
            self.target = None
            return
        front = pick.get('f')
        if front and pos_of(front) != pos:
            # the tile in front of the teleport first (its alcove is entered from there), then the step onto the teleport itself
            if not await self.step_on(io, front, 'the hunt teleport %s' % pick.get('n'), avoid=pos_of(pick.get('t'))):
                if n > GATE_TRIES:
                    await self.jump(io, pick, 'the walk to the teleport of %s failed' % pick.get('n'))
                return
        if not await self.step_on(io, pick.get('t'), 'the hunt teleport %s' % pick.get('n')) and n > GATE_TRIES:
            await self.jump(io, pick, 'the walk to the teleport of %s failed' % pick.get('n'))

    async def stairs(self, io, s, want_z):
        """a floor of the hall up or down on foot: the stairs of the floor the helper found"""
        st = s.get('stairs') or {}
        pos = pos_of(s.get('pos'))
        goal = st.get('up') if want_z < pos[2] else st.get('down')
        n = self.tries['stairs'] = self.tries.get('stairs', 0) + 1
        if not goal or n > GATE_TRIES + 1:
            self.tries['stairs'] = 0
            await self.jump(io, s.get('pick') or {}, 'no way to floor %d on foot' % want_z)
            return
        await self.step_on(io, goal, 'the stairs to floor %d' % want_z)

    async def jump(self, io, pick, why):
        """the counted fallback to a hunt: the helper puts the bot at the hunt's arrival"""
        if await self.helper_teleport(io, 'journey jump', 'jump', why):
            self.target = pick or self.target
            await io.sleep(SETTLE)
        else:
            self.avoid((pick or {}).get('id'), 'blocked', io.now())   # the helper cannot put it there either: another hunt

    async def visit(self, io, name):
        """a shop of the market on foot: the Loot Buyer buys what the bag holds, the Apothecary sells potions; the Go to NPC button of the
        window (npc travel) when the walk does not arrive, the helper's `enter npc` after that"""
        how, got = await self.walk(io, 'path npc ' + name, 2, 'the walk to ' + name)
        if how != 'foot':
            key = dict(TRIP_NPCS).get(name)
            if key:
                await io.request('npcTravel', 'travel', {'k': key}, [], 0)
                await io.sleep(SETTLE)
                a = await io.helper('path npc ' + name, 'path', ANSWER)
                if isinstance(a, dict) and (a.get('here') or (a.get('dist') is not None and a['dist'] <= 2)):
                    self.note('Go to NPC took the bot to %s' % name)
                    how = 'foot'
            if how != 'foot':
                a = await io.helper('enter npc ' + name, 'enter', HELPER_WAIT)
                if not isinstance(a, dict) or a.get('err'):
                    return
                self.fall('npc', 'enter npc %s: the walk did not arrive' % name)
        res = await io.shop_here(name)
        if isinstance(res, dict):
            self.sold += int(res.get('sold') or 0)
            self.bought += int(res.get('bought') or 0)
            self.note('%s: sold %s, bought %s%s' % (name, res.get('sold', 0), res.get('bought', 0), '' if res.get('window') else ' (no trade window)'))

    # ---- the hunt
    async def in_field(self, io, s):
        now = io.now()
        h = self.hunt
        if h is None:
            await self.leave(io, s, 'not at a hunt it knows: the way back to town')
            return
        if not s.get('stay') and not s.get('above'):
            self.more += 1
        else:
            self.more = 0
        reason = None
        if self.more >= MOVE_LOOKS and now - h['at'] >= MIN_HUNT:
            reason = 'moves on: level %s outgrew %s (levels %s-%s)' % (self.level, h.get('n'), h.get('lo'), h.get('hi'))
            self.moves += 1
        elif s.get('hot') and (s['hot'].get('l') or 0) > 0:
            reason = 'a monster of level %s (%s) is far above it' % (s['hot'].get('l'), s['hot'].get('n'))
            self.avoid(h.get('id'), 'hot', now)
        elif now - self.last_keep >= KEEP_EVERY:
            self.last_keep = now
            k = await io.keep()
            if isinstance(k, dict) and k.get('sell'):
                self.sell_due = True
            if self.sell_due or now - (self.last_trip or now) >= TRIP_EVERY:
                reason = 'a trip to town: the bag is full' if self.sell_due else 'a trip to town: potions and the depot'
        if reason is None and self.idle_since is not None and now - self.idle_since >= IDLE_LEAVE:
            reason = 'no monster in sight for %d s' % IDLE_LEAVE
            self.avoid(h.get('id'), 'idle', now)
        if reason:
            await self.leave(io, s, reason)
            return
        await self.hunt_step(io, s)

    async def hunt_step(self, io, s):
        now = io.now()
        m = s.get('monster')
        if isinstance(m, dict) and pos_of(m):
            self.idle_since = None
            if (m.get('dist') or 0) <= FIGHT_RANGE:
                self.fights += 1
                await io.sleep(LOOK)   # the helper's loop has it as its target; the bot's own rotation casts
            else:
                how, _ = await TX.walk_by_path(Counting(io, self), {'lead': True, 'name': self.name}, 'path pos %d %d %d' % pos_of(m), 'path',
                                               FIGHT_RANGE - 1, rounds=CHASE_ROUNDS)
                if how == 'err':   # no way to it (water, a wall): another way round, then the next look
                    await self.wander(io)
        else:
            if self.idle_since is None:
                self.idle_since = now
            await io.sleep(LOOK)
            await self.wander(io)
        if now - self.last_loot >= LOOT_EVERY:
            self.last_loot = now
            await io.loot()

    async def wander(self, io):
        """no monster in sight: a few steps along the way a person explores (every look another quarter turn)"""
        n = self.tries['wander'] = self.tries.get('wander', 0) + 1
        dx, dy = ((1, 0), (0, 1), (-1, 0), (0, -1))[n % 4]
        for _ in range(4):
            await io.step(dx, dy)
            self.steps += 1
            await io.sleep(TX.RAID_STEP)

    async def leave(self, io, s, reason):
        """back to town: the Town Portal spell (the portal beside the bot is walked into), the camp portal of the hunt, the helper's `town` last"""
        self.note('leaves the hunt: ' + reason)
        self.expect = 'temple'
        self.stage = 'leave'
        await io.say(TOWN_WORDS)
        await io.sleep(PORTAL_CAST)
        for _ in range(2):
            a = await io.helper('journey', 'journey', ANSWER)
            portal = a.get('portal') if isinstance(a, dict) else None
            if portal:
                if await self.step_on(io, portal, 'the town portal'):
                    return
                break
            await io.say(TOWN_WORDS)
            await io.sleep(PORTAL_CAST)
        camp = (self.hunt or {}).get('b') or None
        if camp and await self.step_on(io, camp, 'the camp portal'):
            return
        if await self.helper_teleport(io, 'town', 'town', 'no town portal beside the bot'):
            return


class Counting:
    """the io of a walk, counting the steps the bot took"""

    def __init__(self, io, journey):
        self.io, self.journey = io, journey

    def __getattr__(self, name):
        return getattr(self.io, name)

    async def step(self, dx, dy):
        self.journey.steps += 1
        return await self.io.step(dx, dy)


def dump(journeys):
    """the journeys of all bots as the JSON of run.json's `journey`"""
    return json.dumps({n: j.as_dict() for n, j in journeys.items()}, sort_keys=True)

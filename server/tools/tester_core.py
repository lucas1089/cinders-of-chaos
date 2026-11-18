#!/usr/bin/env python3
"""Tester bots, pure parts (server/tools/testers.py; server/README.md "Tester bots"; tests: testers_test.py).

No I/O here: the behaviour scheduler, the anomaly rules of what a bot sees, the classification of the server's text
messages, the server log parsing (the same grouping as chaos-ctl.sh errors) and the report.
"""
import json
import random
import re
import struct

TESTER_STORAGE = 7102900          # Chaos.storage.tester (chaos_constants.lua), src-patch 0059 CHAOS_TESTER_STORAGE
NAME_RE = re.compile(r'^Tester [A-Z][a-z][a-z]$')
ACCOUNT_RE = re.compile(r'^tstbot[0-9a-f]{10}$')
MAX_BOTS = 150
DEFAULT_BOTS = 100
DEFAULT_MINUTES = 60
HELPER_MARK = '[tester-helper]'
ANOMALY_MARK = '[tester-anomaly]'
EVENT_MARK = '[tester-event]'

# ------------------------------------------------------------------------------------------------ behaviours
# what a bot does next: weight (how often it is picked when its cooldown is over) and cooldown in seconds
BEHAVIOURS = {
    'hunt':     (40, 0),     # stay: fight the helper's target, cast the rotation (the default)
    'wander':   (12, 0),     # a few random steps
    'town':     (4, 240),    # back to the temple (helper teleport), walk a bit, then back to the hunt
    'depot':    (4, 300),    # to a depot locker, open it, back
    'shop':     (5, 300),    # to an NPC: hi, trade, buy potions, sell, bye
    'party':    (5, 120),    # invite / join / leave
    'pm':       (6, 60),     # a private message to another tester
    'opcodes':  (10, 20),    # a client module request (a scenario step, --opcodes)
    'loot':     (8, 30),     # loot filter take, open the backpack
    'relog':    (2, 600),    # log out and in again
    'keep':     (6, 150),    # the bag the way a player keeps it: wear a better piece, sell at the Loot Buyer, drop junk (O584)
}


def pick(weights, rng, ready):
    """a weighted choice among the behaviours whose cooldown is over (ready: set of names); None if none is"""
    items = [(k, w) for k, w in sorted(weights.items()) if k in ready and w > 0]
    total = sum(w for _, w in items)
    if total <= 0:
        return None
    r = rng.random() * total
    for k, w in items:
        r -= w
        if r < 0:
            return k
    return items[-1][0]


class Scheduler:
    """per bot: which behaviour next, honouring each behaviour's cooldown"""

    def __init__(self, seed, behaviours=None):
        self.rng = random.Random(seed)
        self.table = dict(behaviours or BEHAVIOURS)
        self.ready_at = {k: 0.0 for k in self.table}

    def ready(self, now):
        return {k for k, t in self.ready_at.items() if t <= now}

    def next(self, now):
        name = pick({k: w for k, (w, _) in self.table.items()}, self.rng, self.ready(now))
        if name:
            self.ready_at[name] = now + self.table[name][1]
        return name


# ------------------------------------------------------------------------------------------------ text messages
FAILURES = [
    ('not possible', re.compile(r'Sorry, not possible\.')),
    ('no way', re.compile(r'There is no way\.')),
    ('exhausted', re.compile(r'You are exhausted\.')),
    ('no mana', re.compile(r'You do not have enough mana\.')),
    ('no soul', re.compile(r'You do not have enough soul\.')),
    ('need weapon', re.compile(r'You need to equip a weapon|You need a weapon', re.I)),
    ('no target', re.compile(r'You can only use (this rune|it) on creatures\.|A target is required', re.I)),
    ('too far', re.compile(r'Destination is out of range\.|Too far away\.', re.I)),
    ('not enough room', re.compile(r'There is not enough room\.|You cannot put more objects in this container\.')),
    ('no capacity', re.compile(r'This object is too heavy for you to carry\.')),
    ('first go downstairs', re.compile(r'First go (down|up)stairs\.')),
    ('not learned', re.compile(r'You need to learn this spell first\.')),
    ('level too low', re.compile(r'You do not have enough level\.')),
    ('wrong vocation', re.compile(r'Your vocation cannot use this spell\.')),
    ('not enough money', re.compile(r'You do not have enough money|not enough gold', re.I)),
    ('cannot use object', re.compile(r'You cannot use this object\.')),
]
# expected in normal play: counted, not reported as bugs
EXPECTED = {'exhausted', 'no mana', 'no soul', 'no target', 'too far', 'first go downstairs', 'level too low',
            'not enough money', 'shop: Loot Buyer buys nothing the tester carries',
            'not possible (a blind step into an obstacle)', 'not enough room'}
LUA_ERROR = re.compile(r'Lua Script Error|stack traceback|attempt to (index|call|compare|perform|concatenate)'
                       r'|bad argument #\d|\.lua:\d+:', re.I)
XP_RE = re.compile(r'You gained (-?\d+) experience points?\.')
LOOT_RE = re.compile(r'^Loot of (?:an? )?([^:]+): (.*)$')
GOLD_RE = re.compile(r'(\d+) (gold|platinum|crystal) coins?')
SOLD_RE = re.compile(r'^Sold (?:(\d+)x )?(.+) for ([\d,]+) gold\.$')  # loot_buyer.lua onSell: "Sold 3x item for 120 gold."
ADVANCE_RE = re.compile(r'You advanced from Level (\d+) to Level (\d+)\.')
DEATH_RE = re.compile(r'You are dead\.')
HELPER_RE = re.compile(r'^\[tester-helper\] ([a-z]+) (\{.*\})$')


TEXT_RE = re.compile(rb'[\x20-\x7e\xa0-\xff\n]+')


def strings_of(plain, minimum=6):
    """the protocol strings (u16 length, then that many printable bytes) of a decrypted server message; bytes -> [str].
    The length must match exactly, so a length byte that happens to be printable never sticks to the text"""
    out, i, n = [], 0, len(plain)
    while i + 2 + minimum <= n:
        size = plain[i] | plain[i + 1] << 8
        if minimum <= size <= n - i - 2 and TEXT_RE.fullmatch(plain, i + 2, i + 2 + size):
            out.append(plain[i + 2:i + 2 + size].decode('latin-1'))
            i += 2 + size
        else:
            i += 1
    return out


def classify(text):
    """one text the server sent -> (kind, detail):
    ('helper', (kind, data)), ('lua_error', text), ('failure', key), ('xp', n), ('loot', (monster, gold)),
    ('advance', (old, new)), ('death', None) or (None, None)"""
    m = HELPER_RE.match(text)
    if m:
        try:
            return 'helper', (m.group(1), json.loads(m.group(2)))
        except ValueError:
            return 'helper', (m.group(1), {})
    if LUA_ERROR.search(text):
        return 'lua_error', text
    for key, rx in FAILURES:
        if rx.search(text):
            return 'failure', key
    m = XP_RE.search(text)
    if m:
        return 'xp', int(m.group(1))
    m = LOOT_RE.match(text)
    if m:
        gold = 0
        for n, kind in GOLD_RE.findall(m.group(2)):
            gold += int(n) * {'gold': 1, 'platinum': 100, 'crystal': 10000}[kind]
        return 'loot', (m.group(1), gold)
    m = SOLD_RE.match(text)
    if m:
        return 'sold', (int(m.group(1) or 1), int(m.group(3).replace(',', '')))
    m = ADVANCE_RE.search(text)
    if m:
        return 'advance', (int(m.group(1)), int(m.group(2)))
    if DEATH_RE.search(text):
        return 'death', None
    return None, None


# ------------------------------------------------------------------------------------------------ anomaly rules
LIMITS = {
    'xp_per_level': 2000000,      # one gain larger than this x level
    'gold_per_level': 50000,      # gold in one corpse larger than this x level (+ 100000)
    'gold_base': 100000,
}


def xp_anomaly(level, gained):
    if gained < 0:
        return 'negative experience gain'
    if gained > LIMITS['xp_per_level'] * max(1, level):
        return 'absurd experience gain'
    return None


def gold_anomaly(level, gold):
    if gold < 0:
        return 'negative gold'
    if gold > LIMITS['gold_base'] + LIMITS['gold_per_level'] * max(1, level):
        return 'absurd gold in one corpse'
    return None


FRESH = 0.5  # seconds: the health the bot saw must be this young for "one hit from full health"


def health_anomaly(before_pct, after_pct, died, age=None, seen=True):
    """a bot at full health dead (or at 0 %) at the next health update: one hit from full. Only on health the bot really
    saw (seen: an update of its own creature arrived) and saw just before (age: seconds since it; None = unknown = no):
    the first live run (2026-10-27) filed 500 of these for bots that died one second after logging in, whose "100" was
    the value they start with. The exact rule is the helper's (tester_helper_core.lua hitAnomaly: health, maximum and
    damage of one hit on the server)."""
    if not seen or age is None or age > FRESH:
        return None
    if before_pct >= 100 and (died or after_pct <= 0):
        return 'death within one hit from full health'
    return None


# ------------------------------------------------------------------------------------------------ where a bot hunts
# Since 2026-10-27 the map marks print the HUNTING level (gen_poi.py: pool level x pace_config.lua baseLevelMult, which is 1 since
# 2026-10-28, O285: the pool level), so a
# band is compared with the character level as it is; only pool levels (bounty_pool.lua) still need baseLevelMult.
DEATH_REST = 20.0     # seconds in the temple after the first death in a row, doubled for each one that follows
DEATH_REST_MAX = 300.0
DEATH_WINDOW = 300.0  # deaths this close together are "in a row"


def safe_hunts(hunts, level):
    """the hunts a tester of this level may be placed in: [(low, high, x, y, z)] of the map marks (loadtest.hunt_marks;
    their band is in hunting levels since 2026-10-27, before that in pool levels; baseLevelMult is 1 since 2026-10-28, O285, so both scales are the same) whose whole
    band is at or under the level. The first live run put level 30-45 testers into bands such as 20-30 or 20-90 (read as
    pool levels: hunting level 40 to 180): 2998 deaths in 20 minutes, killers with a pool level of 20 to 284. Of those the ones with the highest top (at least 0.8 x the highest),
    else, when no band is that low, the lowest ones."""
    fit = [h for h in hunts if h[1] <= level]
    if fit:
        top = max(h[1] for h in fit)
        return [h for h in fit if h[1] >= top * 0.8]
    low = min(h[1] for h in hunts)
    return [h for h in hunts if h[1] == low]


def death_rest(deaths, now):
    """seconds a tester waits in the temple before it goes back to its hunt, from the times (monotonic) of its deaths so
    far (the last one is now): DEATH_REST, doubled for each death within DEATH_WINDOW before it, at most DEATH_REST_MAX
    (a player walks back from the temple; the first run's testers were teleported to the same pack at once, 17-35 s
    between two deaths)"""
    recent = [t for t in deaths if now - t <= DEATH_WINDOW]
    return min(DEATH_REST_MAX, DEATH_REST * 2 ** max(0, len(recent) - 1))


# ------------------------------------------------------------------------------------------------ the server log
TS_RE = re.compile(r'^\[?\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d[^ ]*\]?[ :-]*')


def is_error(line):
    # whole words: a monster name such as "Terror Bird" in a death line is no error
    return 'Lua Script Error' in line or re.search(r'\berrors?\b|\bexception\b|segfault', line, re.I) is not None


def is_warning(line):
    return re.search(r'\bwarn(ing)?\b', line, re.I) is not None


def parse_log(lines):
    """the server console lines of the run -> {'errors': {text: count}, 'warnings': {text: count},
    'anomalies': [dict], 'events': [dict], 'first': {text: line number}}. Errors are grouped as chaos-ctl.sh errors does:
    the timestamp stripped, a Lua Script Error joined with its next two lines (" | ")."""
    out = {'errors': {}, 'warnings': {}, 'anomalies': [], 'events': [], 'first': {}}

    def add(kind, text, n):
        text = TS_RE.sub('', text)
        out[kind][text] = out[kind].get(text, 0) + 1
        out['first'].setdefault(text, n)

    cur, join, cur_n, cur_kind = None, 0, 0, 'errors'
    for n, raw in enumerate(lines, 1):
        line = raw.rstrip('\r\n')
        for mark, key in ((ANOMALY_MARK, 'anomalies'), (EVENT_MARK, 'events')):
            i = line.find(mark)
            if i >= 0:
                try:
                    data = json.loads(line[i + len(mark):].strip())
                    data['line'] = n
                    out[key].append(data)
                except ValueError:
                    pass
        if join > 0:
            # a Lua error, or a warning with its stack traceback (the guards print one): the next lines join it
            more = line.strip() and (cur_kind == 'errors' and not is_error(line)
                                     or cur_kind == 'warnings' and (line[:1] in ' \t' or line.startswith('stack traceback')))
            if not more:
                add(cur_kind, cur, cur_n)
                cur, join = None, 0
            else:
                cur += ' | ' + line.strip()
                join -= 1
                if join == 0:
                    add(cur_kind, cur, cur_n)
                    cur = None
                continue
        if 'Lua Script Error' in line:
            cur, join, cur_n, cur_kind = line, 2, n, 'errors'
            continue
        if ANOMALY_MARK in line or EVENT_MARK in line:
            continue  # the bots' own records: reported apart (anomalies, deaths)
        if is_error(line):
            add('errors', line, n)
        elif is_warning(line):
            cur, join, cur_n, cur_kind = line, 3, n, 'warnings'
    if cur is not None:
        add(cur_kind, cur, cur_n)
    return out


# ------------------------------------------------------------------------------------------------ outcomes that mean something
HUNT_WINDOW = 90.0   # seconds a bot may hunt without one experience message before "hunt" counts as failed
FLEE_LOOK = 5.0      # seconds after the flee at which its result is judged


def hunt_outcome(now, hunt_since, last_progress, window=HUNT_WINDOW):
    """what one pick of "hunt" proved (O584: it always said ok): 'ok' when the bot gained experience or took a loot message
    within the window, 'failed' when it stood at its hunt that long and gained nothing, 'expected' (not judged) while it has
    not been at the hunt for a window yet (just logged in, in the temple, back from a flee)"""
    if hunt_since is None or now - hunt_since < window:
        return 'expected'
    if last_progress is not None and now - last_progress <= window and last_progress >= hunt_since:
        return 'ok'
    return 'failed'


def flee_outcome(health_at_flee, health_now, died, helper_answer):
    """what a flee (the helper's town teleport at low health) proved, FLEE_LOOK seconds later: 'ok' when the helper brought the
    bot to the temple without an error and it is alive with no less health, else 'failed' with the reason"""
    if helper_answer is None:
        return 'failed', 'no helper answer to the town teleport'
    if isinstance(helper_answer, dict) and helper_answer.get('err'):
        return 'failed', 'the town teleport was refused: %s' % str(helper_answer['err'])[:60]
    if died:
        return 'failed', 'died within %d s of the flee' % FLEE_LOOK
    if health_now < health_at_flee:
        return 'failed', 'health fell from %d to %d after the flee' % (health_at_flee, health_now)
    return 'ok', ''


# ------------------------------------------------------------------------------------------------ keeping the bag (O584)
BAG_FULL = 0.7     # tester_helper_core.lua H.BAG_FULL: the share of the slots that sends a bot to sell
BAG_JAM = 0.9      # H.BAG_JAM: the share that makes it drop junk
MAX_DROPS = 3      # a player drops a few things, not the whole bag in one go
MAX_JAMS = 3       # rounds a bag stays jammed with what cannot be sold or dropped before the helper wipes it (a counted failure)
SELL_AMOUNT = 100  # the u8 amount of a sale packet: the Loot Buyer sells at most what the bot carries
SELL_ITEMS = 12    # kinds sold in one visit


def move_packet(src, sprite, stackpos, dst, count=1):
    """the client's move item packet (0x78): u16 x, u16 y, u8 z of the item, u16 sprite id, u8 stack position, the target
    position, u8 count. A backpack slot is (0xFFFF, 0x40 + container id, slot), an equipment slot (0xFFFF, slot, 0), the floor
    a map position"""
    return (b'\x78' + struct.pack('<HHB', *src) + struct.pack('<HB', sprite, stackpos) + struct.pack('<HHB', *dst)
            + struct.pack('<B', max(1, min(255, count))))


def use_packet(pos, sprite, stackpos=0, index=0):
    """use an item (0x82); index: the container id the item opens as"""
    return b'\x82' + struct.pack('<HHB', *pos) + struct.pack('<HBB', sprite, stackpos, index)


def use_with_packet(src, sprite, stackpos, dst, dst_sprite, dst_stackpos):
    """use an item on another (0x83): the item's position, sprite id and stack position, then the target's"""
    return (b'\x83' + struct.pack('<HHB', *src) + struct.pack('<HB', sprite, stackpos)
            + struct.pack('<HHB', *dst) + struct.pack('<HB', dst_sprite, dst_stackpos))


def sale_packet(item_id, sub, amount):
    """sell to the NPC of the open trade window (0x7b): u16 id, u8 sub type, u8 amount, u8 ignore equipped"""
    return b'\x7b' + struct.pack('<HBBB', item_id, sub, max(1, min(255, amount)), 1)


def buy_packet(item_id, sub, amount, ignore_capacity=False, in_backpacks=False):
    """buy from the NPC of the open trade window (0x7a, O655): u16 id, u8 sub type, u8 amount, u8 ignore capacity, u8 in backpacks"""
    return b'\x7a' + struct.pack('<HBBBB', item_id, sub, max(1, min(100, amount)), 1 if ignore_capacity else 0, 1 if in_backpacks else 0)


def modal_answer_packet(window_id, button, choice):
    """the answer to a modal window (0xf9, O655): u32 window id, u8 button id, u8 choice id (what a person presses in the window)"""
    return b'\xf9' + struct.pack('<IBB', window_id, button & 0xFF, choice & 0xFF)


def bag_fill(report):
    return (report.get('used') or 0) / max(1, report.get('size') or 1)


def row_at(report, index):
    for r in report.get('rows') or []:
        if r.get('i') == index:
            return r
    return None


def keep_plan(report, refused=(), room_fails=0):
    """what a bot does with the `!tester bag` report: {'equip': row or None, 'sell': bool}. Equip a piece the helper found
    better than the worn one (never one the server refused before); sell when the bag is BAG_FULL full, when pickups said
    there is no room, or when there is enough to make the trip worth it, and the Loot Buyer buys something"""
    better = row_at(report, report.get('better')) if report.get('better') is not None else None
    if better and better.get('id') in refused:
        better = None
    sells = report.get('sell') or 0
    sell = sells > 0 and (bag_fill(report) >= BAG_FULL or room_fails > 0 or sells >= 4)
    return {'equip': better, 'sell': sell}


def drop_rows(report):
    """the junk rows to drop from a report (the helper listed their container indexes: only at BAG_JAM or more), at most MAX_DROPS"""
    out = []
    for i in report.get('junk') or []:
        r = row_at(report, i)
        if r:
            out.append(r)
    return out[:MAX_DROPS]


DIFF_MIN = 10     # a counter must move by this many ...
DIFF_SHARE = 0.25  # ... and by this share to show in the "against the previous run" section
SECTION_RE = re.compile(r'^== (.*?)(?: \(.*)?$')
FAIL_ROW_RE = re.compile(r'^\s*(\d+)x (.+?)(?: \(expected in play\))?(?: \(first: .*)?$')
BEHAVIOUR_ROW_RE = re.compile(r'^  ([a-z_]+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$')
PROOF_ROW_RE = re.compile(r'^  (\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$')
CHECK_ROW_RE = re.compile(r'^  ([a-z_]+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$')


def read_report(text):
    """the numbers of a report text (this format or an older one) -> {'head': {name: n}, 'failures': {text: n}, 'behaviours':
    {name: (tried, ok, failed, expected)}, 'proof': {system: (real, ans, help, failed)}, 'checks': {name: (pass, fail, skip)},
    'bugs': set(text), 'effects': set(text)}"""
    out = {'head': {}, 'failures': {}, 'behaviours': {}, 'proof': {}, 'checks': {}, 'bugs': set(), 'effects': set()}
    section = ''
    for line in (text or '').splitlines():
        m = re.match(r'^logins (\d+), deaths (\d+), relogs (\d+), reconnects (\d+)', line)
        if m:
            out['head'] = dict(zip(('logins', 'deaths', 'relogs', 'reconnects'), (int(x) for x in m.groups())))
            continue
        m = SECTION_RE.match(line)
        if m:
            section = m.group(1)
            continue
        if line.strip().startswith('BUG '):
            out['bugs'].add(line.strip()[:160])
            continue
        if section.startswith('Failure messages'):
            m = FAIL_ROW_RE.match(line)
            if m:
                out['failures'][m.group(2).strip()] = int(m.group(1))
        elif section.startswith('Behaviours'):
            m = BEHAVIOUR_ROW_RE.match(line)
            if m:
                out['behaviours'][m.group(1)] = tuple(int(x) for x in m.groups()[1:])
        elif section.startswith('Proof by system'):
            m = PROOF_ROW_RE.match(line)
            if m:
                v = tuple(int(x) for x in m.groups()[1:])
                out['proof'][m.group(1)] = (v[0], v[1], v[2], v[3])
        elif section.startswith('System checks'):
            m = CHECK_ROW_RE.match(line)
            if m:
                out['checks'][m.group(1)] = tuple(int(x) for x in m.groups()[1:])
        elif section.startswith('Effects that did not hold'):
            if line.startswith('  FAIL '):
                out['effects'].add(line.strip()[:160])
    return out


def moved(a, b):
    return abs(b - a) >= DIFF_MIN and abs(b - a) >= DIFF_SHARE * max(1, a, b)


def report_diff(previous, current, title=''):
    """lines of the "against the previous run" section: what changed between two report texts (O584). Counters that moved by
    DIFF_MIN and DIFF_SHARE, failure kinds that are new or gone, BUG lines that are new or gone, systems whose REAL proof
    appeared or vanished, checks that started failing. [] when there is no previous report or nothing moved"""
    if not previous or not previous.strip():
        return []
    a, b = read_report(previous), read_report(current)
    L = []
    for k, v in sorted(b['head'].items()):
        old = a['head'].get(k)
        if old is not None and moved(old, v):
            L.append('  %s %d -> %d' % (k, old, v))
    for name, v in sorted(b['behaviours'].items()):
        old = a['behaviours'].get(name)
        if old is None:
            L.append('  behaviour %s is new: %d tried, %d ok' % (name, v[0], v[1]))
        elif moved(old[2], v[2]) or moved(old[1], v[1]):
            L.append('  behaviour %s ok %d -> %d, failed %d -> %d' % (name, old[1], v[1], old[2], v[2]))
    for name in sorted(set(a['behaviours']) - set(b['behaviours'])):
        L.append('  behaviour %s is gone' % name)
    for text, n in sorted(b['failures'].items()):
        if text not in a['failures']:
            L.append('  new failure: %dx %s' % (n, text[:100]))
        elif moved(a['failures'][text], n):
            L.append('  failure %s: %d -> %d' % (text[:80], a['failures'][text], n))
    for text in sorted(set(a['failures']) - set(b['failures'])):
        L.append('  failure gone: %s' % text[:100])
    for name, v in sorted(b['proof'].items()):
        old = a['proof'].get(name)
        if old is None:
            continue
        if v[0] > 0 and old[0] == 0:
            L.append('  %s: REAL proof now (%d)' % (name, v[0]))
        elif v[0] == 0 and old[0] > 0:
            L.append('  %s: REAL proof lost (was %d)' % (name, old[0]))
        if v[3] > old[3]:
            L.append('  %s: failed effects %d -> %d' % (name, old[3], v[3]))
    for name, v in sorted(b['checks'].items()):
        old = a['checks'].get(name)
        if old is not None and v[1] > old[1]:
            L.append('  check %s: fail %d -> %d' % (name, old[1], v[1]))
    for text in sorted(b['bugs'] - a['bugs']):
        L.append('  new ' + text)
    for text in sorted(a['bugs'] - b['bugs']):
        L.append('  gone ' + text)
    for text in sorted(b['effects'] - a['effects']):
        L.append('  new effect failure: ' + text[7:])
    if not L:
        return ['== Against the previous run%s: nothing moved by %d and %d%%' % (title, DIFF_MIN, int(DIFF_SHARE * 100))]
    return ['== Against the previous run%s (%d changes)' % (title, len(L))] + L[:60]


# ------------------------------------------------------------------------------------------------ the report
def group(counts, top=40):
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:top]


def build_report(run, log, previous=None, previous_title=''):
    """run: the run's results (testers.py writes them to the state folder) {started, ended, bots, behaviours: {name:
    {tried, ok, failed}}, failures: {key: count}, lua_errors: {text: count}, kicks: {text: count}, deaths, relogs,
    reconnects, anomalies: [dict], first: {key: {bot, did, at}}}; log: parse_log of the server log of the run.
    Returns the report text."""
    L = []
    L.append('Tester bots report')
    L.append('run: %s to %s, %d bots' % (run.get('started', '?'), run.get('ended', 'running'), run.get('bots', 0)))
    L.append('logins %d, deaths %d, relogs %d, reconnects %d' % (
        run.get('logins', 0), run.get('deaths', 0), run.get('relogs', 0), run.get('reconnects', 0)))
    first = run.get('first', {})

    def ctx(key):
        f = first.get(key)
        return ' (first: %s after %s)' % (f.get('bot', '?'), f.get('did', '?')) if f else ''

    L.append('')
    L.append('== Server log: errors (%d kinds)' % len(log['errors']))
    for text, n in group(log['errors']):
        L.append('%5dx %s' % (n, text))
    L.append('== Server log: warnings (%d kinds)' % len(log['warnings']))
    for text, n in group(log['warnings'], 20):
        L.append('%5dx %s' % (n, text))
    deaths = [e for e in log['events'] if e.get('kind') == 'death']
    L.append('== Deaths on the server (%d; the bots counted %d)' % (len(deaths), run.get('deaths', 0)))
    for title, key in (('killer', 'killer'), ('level', 'level'), ('tester', 'who')) if deaths else ():
        counts = {}
        for e in deaths:
            k = str(e.get(key, '?'))
            counts[k] = counts.get(k, 0) + 1
        L.append('  by %s: %s' % (title, ', '.join('%s %d' % kv for kv in group(counts, 10))))
    rec = [e for e in deaths if 'hits' in e]
    if rec:
        # what killed: one hit or many (the helper's death record: the last 5 seconds, as a percent of the maximum health)
        def med(key):
            v = sorted(e.get(key) or 0 for e in rec)
            return v[len(v) // 2]
        one = sum(1 for e in rec if (e.get('biggestPct') or 0) >= 100)
        def secs(e):  # 'online' of the first run was the seconds since the login, not a player count
            return e.get('secsOnline', e.get('online'))
        quick = sum(1 for e in rec if secs(e) is not None and secs(e) <= 5)
        L.append('  last 5 s before the death (%d records): median %d hits, %d%% of the maximum health in all, the biggest hit '
                 '%d%%; %d deaths by one hit of 100%% or more, %d within 5 s of the login' % (
                     len(rec), med('hits'), med('damagePct'), med('biggestPct'), one, quick))
    anomalies = list(log['anomalies']) + list(run.get('anomalies', []))
    L.append('== Anomalies (%d)' % len(anomalies))
    by_rule = {}
    for a in anomalies:
        by_rule.setdefault(a.get('rule', '?'), []).append(a)
    for rule, rows in sorted(by_rule.items(), key=lambda kv: -len(kv[1])):
        L.append('%5dx %s; first: %s' % (len(rows), rule, json.dumps(rows[0], sort_keys=True)))
    L.append('== Lua errors the bots received (%d kinds)' % len(run.get('lua_errors', {})))
    for text, n in group(run.get('lua_errors', {})):
        L.append('%5dx %s%s' % (n, text, ctx('lua:' + text)))
    L.append('== Failure messages the bots received')
    for key, n in group(run.get('failures', {})):
        L.append('%5dx %s%s%s' % (n, key, ' (expected in play)' if key in EXPECTED else '', ctx('fail:' + key)))
    L.append('== Kicks and disconnects')
    for text, n in group(run.get('kicks', {})):
        L.append('%5dx %s%s' % (n, text, ctx('kick:' + text)))
    L.append('== Behaviours (tried / ok / failed / expected: cut short by the bot\'s own death, no cast through exhaustion or mana)')
    for name, b in sorted(run.get('behaviours', {}).items()):
        L.append('  %-10s %6d %6d %6d %6d' % (name, b.get('tried', 0), b.get('ok', 0), b.get('failed', 0),
                                              b.get('expected', 0)))
    h = run.get('helper')
    if h:
        # O579: how fast the helper answered the bots' numbered commands; a busy server shows here (answers over 4 s, late
        # ones) before it shows as "no helper answer" in the failures above
        slow = (list(h.get('slow') or []) + [0] * 5)[:5]
        L.append('== Helper answers (%d commands: %d answered, %d with no answer in time, %d late and dropped; seconds to answer: '
                 'under 1 %d, 1-2 %d, 2-4 %d, 4-8 %d, over 8 %d; slowest %.1f s)' % (
                     h.get('answered', 0) + h.get('lost', 0), h.get('answered', 0), h.get('lost', 0), h.get('late', 0),
                     slow[0], slow[1], slow[2], slow[3], slow[4], float(h.get('max_s', 0) or 0)))
    if run.get('keytest') or run.get('keytest_resets'):
        import tester_keystones as TK  # the per-node results of the keystone and mastery scenario (O249)
        L.extend(TK.report_lines(run.get('keytest') or [], run.get('keytest_resets') or []))
    if run.get('checks'):
        import tester_checks as TX  # the system checks, BUG lines first-class (O110)
        L.extend(TX.report_lines(run.get('checks') or []))
    cov = run.get('coverage')
    if cov:
        # short enough to paste: only what needs a look; the fine, out of scope and passive systems are counted
        L.append('== System coverage, what needs a look (tried / ok / errors; never reached)')
        fine, skipped, silent = 0, {}, []
        for system, c in sorted(cov.items()):
            tried, okn, err, why = c.get('tried', 0), c.get('ok', 0), c.get('errors', 0), c.get('why') or ''
            if tried and okn and not err:
                fine += 1
                continue
            if not tried and why.startswith(('out of scope', 'passive', 'closed test mode')):
                skipped.setdefault(why, []).append(system)
                continue
            if tried and not okn and not err and not c.get('refused', 0):
                silent.append(system)
                continue
            L.append('  %-22s %5d %5d %5d%s' % (system, tried, okn, err,
                                                '  never reached: ' + why if not tried and why else ''))
        # one line per reason: what bots cannot do stays visible, but short
        for why, names in sorted(skipped.items()):
            L.append('  never reached: %s: %s' % (why, ', '.join(names)))
        if silent:
            # sent, never answered and no log error: the request needs data the bot does not have (an item id, a
            # choice); a bug shows as a log error or a refusal
            L.append('  no answer, no error: %s' % ', '.join(silent))
        L.append('  (%d systems fine: not listed)' % fine)
        L.extend(proof_lines(cov))
    fx = run.get('effects')
    if fx:
        L.append('== Effects that did not hold (%d: the server answered, the effect was not there)' % len(fx))
        for e in fx[:40]:
            L.append('  FAIL %s %s: %s (%s)' % (e.get('effect'), e.get('step'), e.get('why'), e.get('bot')))
    keep = run.get('keep')
    if keep:
        L.append('== Bag keeping (sold %d items for %d gold in %d visits, equipped %d, dropped %d, helper wipes %d, '
                 'sell visits with nothing to sell %d)' % (
                     keep.get('sold_units', 0), keep.get('sold_gold', 0), keep.get('sell_visits', 0), keep.get('equipped', 0),
                     keep.get('dropped', 0), keep.get('wiped', 0), keep.get('nothing', 0)))
    text = '\n'.join(L) + '\n'
    diff = report_diff(previous, text, previous_title)
    if diff:
        # after the three header lines: what moved is the first thing the owner reads
        lines = text.split('\n')
        text = '\n'.join(lines[:3] + [''] + diff + lines[3:])
    return text


def proof_lines(cov):
    """the proof table: for every system the bots reached, what kind of proof there is (O584 item 15)
    REAL: an effect the bot saw (an effect scenario that held, a system check that passed); ANS: an answer, no effect checked;
    HELP: the helper's shortcut (teleport, item); fail: an answer without its effect or a failed check"""
    rows = []
    for system, c in sorted(cov.items()):
        real, ans, helped, failed = c.get('real', 0), c.get('ans', 0), c.get('help', 0), c.get('failed', 0)
        if real or ans or helped or failed:
            rows.append((system, real, ans, helped, failed, c.get('refused', 0), c.get('errors', 0)))
    if not rows:
        return []
    only = lambda i: sum(1 for r in rows if r[i] and not any(r[j] for j in (1, 2, 3) if j != i))
    L = ['== Proof by system (REAL: an effect the bot saw; ANS: an answer, no effect checked; HELP: the helper\'s shortcut)',
         '  %-24s %5s %5s %5s %5s %5s %5s' % ('system', 'real', 'ans', 'help', 'fail', 'refus', 'errs')]
    for r in rows:
        L.append('  %-24s %5d %5d %5d %5d %5d %5d' % r)
    L.append('  (%d systems reached: %d with REAL proof, %d with ANS only, %d with HELP only)' % (
        len(rows), sum(1 for r in rows if r[1]), only(2), only(3)))
    return L

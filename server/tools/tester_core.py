#!/usr/bin/env python3
"""Tester bots, pure parts (server/tools/testers.py; server/README.md "Tester bots"; tests: testers_test.py).

No I/O here: the behaviour scheduler, the anomaly rules of what a bot sees, the classification of the server's text
messages, the server log parsing (the same grouping as chaos-ctl.sh errors) and the report.
"""
import json
import random
import re

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
# Since 2026-10-27 the map marks print the HUNTING level (gen_poi.py: pool level x pace_config.lua baseLevelMult), so a
# band is compared with the character level as it is; only pool levels (bounty_pool.lua) still need baseLevelMult.
DEATH_REST = 20.0     # seconds in the temple after the first death in a row, doubled for each one that follows
DEATH_REST_MAX = 300.0
DEATH_WINDOW = 300.0  # deaths this close together are "in a row"


def safe_hunts(hunts, level):
    """the hunts a tester of this level may be placed in: [(low, high, x, y, z)] of the map marks (loadtest.hunt_marks;
    their band is in hunting levels since 2026-10-27, before that in pool levels, twice it in hunting levels) whose whole
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


# ------------------------------------------------------------------------------------------------ the report
def group(counts, top=40):
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:top]


def build_report(run, log):
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
        quick = sum(1 for e in rec if e.get('online') is not None and e['online'] <= 5)
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
            if not tried and why.startswith(('out of scope', 'passive')):
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
    return '\n'.join(L) + '\n'

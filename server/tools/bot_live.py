#!/usr/bin/env python3
"""Live state of our tester bots for the staff map (O727, server/README.md "Bot live map (O727)"). Standard library only.

Every tester bot (testers.py runs, and the C# journey bot with the same file format, unity/Core/BotLive.cs) publishes what it does as
ONE JSON line in its own file: <live dir>/<slug>.json, for example <server>/data/chaos_botlive/tester-abc.json. The staff page reads
the folder (website/overlay/plugins/chaos/botmap_lib.php). The writer is atomic (a temp file, then rename), writes a file at most every
WRITE_EVERY seconds and only when something changed (or every HEARTBEAT seconds, so the page sees the bot is there), and never holds
anything but the bot's own facts: no account, no password, no address.

The line (VERSION 1):
  {"v": 1, "name": "Tester Abc", "class": "Ranger", "level": 120, "pos": [x, y, z] or null, "goal": "Hunt", "goal_since": epoch s,
   "why": "...", "spot": "...", "now": "...", "plan": ["step", ...], "log": [[epoch s, "text"], ...50, oldest first], "t": epoch s, "src": "py"}

The decision texts are the bots' own: the reason a journey bot gives a hunt comes from the hunt it picked (its band and the level), the
reasons of its fallbacks and stuck events are logged as they are. Nothing here chooses anything.

Staleness (the page and the tests use the same rule, PHP twin: botmap_lib.php): a file whose `t` is older than GREY_AFTER seconds is shown
greyed, one older than DROP_AFTER seconds is dropped.

  python3 -I bot_live.py show DIR        the live entries of a folder, one line each (a quick look on the VPS)
"""
import json
import os
import re
import sys
import tempfile
import time

VERSION = 1
NAME_RE = re.compile(r'^Tester [A-Z][a-z][a-z]$')   # tester_core.NAME_RE: the rule that marks a tester
LOG_MAX = 50            # lines of the log kept in a file
PLAN_MAX = 8            # steps of the plan
TEXT_MAX = 160          # characters of a log line
FIELD_MAX = 240         # characters of why / spot / now / a plan step
WRITE_EVERY = 3.0       # seconds between two writes of one bot (when it changed)
HEARTBEAT = 15.0        # seconds between two writes of a bot that did not change
GREY_AFTER = 120.0      # no update for this long: shown greyed (stale)
DROP_AFTER = 600.0      # no update for this long: dropped
SUFFIX = '.json'

# the goal label of a scheduler behaviour (tester_core.BEHAVIOURS) and a sentence for what it is
GOALS = {
    'hunt': ('Hunt', 'stay at the hunt spot, fight the helper\'s target and cast the class rotation'),
    'wander': ('Wander', 'a few random steps'),
    'town': ('Town', 'back to the temple, walk a bit, then back to the hunt'),
    'depot': ('Depot', 'open the depot locker next to the temple'),
    'shop': ('Shop', 'hi, trade, buy potions, sell, bye at an NPC'),
    'party': ('Party', 'invite, join or leave a party with another tester'),
    'pm': ('Message', 'a private message to another tester'),
    'opcodes': ('Client request', 'a client module request of the scenario table'),
    'loot': ('Loot', 'take loot by the loot filter, open the backpack'),
    'relog': ('Relog', 'log out and in again'),
    'keep': ('Bag', 'keep the bag: wear a better piece, sell at the Loot Buyer, drop junk'),
    'keytest': ('Keystones', 'the keystone and mastery scenario of its class'),
    'checks': ('System checks', 'the system checks of its class'),
    'journey': ('Journey', 'the levelling journey on foot'),
    'hold': ('Wait', 'waits in the temple (video run)'),
}


# ------------------------------------------------------------------------------------------------ pure parts
def clean(text, limit=FIELD_MAX):
    """one line of printable text: control characters and runs of spaces become one space, cut to `limit`"""
    t = ' '.join(re.sub(r'[\x00-\x1f\x7f]', ' ', str(text if text is not None else '')).split())
    return t[:limit]


def slug(name):
    """file name part of a tester name: lower case letters, digits and dashes; '' for a name that is not a tester's"""
    if not NAME_RE.match(name or ''):
        return ''
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def age_state(t, now):
    """'live' | 'stale' | 'gone' of an entry last updated at `t` (epoch seconds), seen at `now`"""
    try:
        age = float(now) - float(t)
    except (TypeError, ValueError):
        return 'gone'
    if age > DROP_AFTER:
        return 'gone'
    if age > GREY_AFTER:
        return 'stale'
    return 'live'


def exp_for_level(level):
    """total experience of a level, the engine's curve (TFS getExpForLevel; the site's level_to_experience is the same)"""
    level = int(level)
    if level <= 1:
        return 0
    return ((((level - 6) * level + 17) * level - 12) // 6) * 100


def exp_per_hour(level, curve):
    """experience an hour the progression model expects of a character of `level` (the experience of the next level over the minutes the
    model gives that level); None without the model (curve = {level: minutes}, tester_journey.curve_for)"""
    try:
        minutes = (curve or {}).get(int(level))
        if not minutes or minutes <= 0:
            return None
        return int(round((exp_for_level(int(level) + 1) - exp_for_level(int(level))) / float(minutes) * 60.0))
    except (TypeError, ValueError):
        return None


def spaced(n):
    return '{:,}'.format(int(n)).replace(',', ' ')


def pos_list(p):
    """[x, y, z] of a {x, y, z} dict or a 3-sequence of ints, None otherwise"""
    if isinstance(p, dict):
        p = [p.get('x'), p.get('y'), p.get('z')]
    if isinstance(p, (list, tuple)) and len(p) == 3 and all(isinstance(v, int) and not isinstance(v, bool) for v in p):
        return [int(p[0]), int(p[1]), int(p[2])]
    return None


JOURNEY_GOALS = {'start': 'Start', 'hunt': 'Hunt', 'town': 'Town', 'trip': 'Town trip', 'hall': 'Walk to a hunt', 'leave': 'Back to town',
                 'wait': 'Wait'}


def journey_view(j, level=None, curve=None, now=None):
    """goal, why, spot, plan of a tester_journey.Journey (duck typed: stage, hunt, target, todo, level, fallbacks, stuck, hunts). The reasons are the
    journey's own facts: the hunt it picked (the band its level fits), the trip it called, the fallback it counted"""
    stage = getattr(j, 'stage', 'start')
    lv = int(level if level is not None else getattr(j, 'level', 0) or 0)
    hunt = getattr(j, 'hunt', None) or {}
    target = getattr(j, 'target', None) or {}
    pick = hunt or target
    goal = JOURNEY_GOALS.get(stage, stage.capitalize() if stage else 'Journey')
    xph = exp_per_hour(lv, curve)
    why, spot, plan = '', '', []
    if pick.get('n'):
        band = 'levels %s-%s' % (pick.get('lo'), pick.get('hi'))
        why = 'level %d is inside %s of %s, the hunt of the teleport room whose band middle is nearest to the level it aims at' % (lv, band, pick['n'])
        if xph:
            why += '; the model expects about %s exp/h at this level' % spaced(xph)
        spot = '%s (%s)' % (pick['n'], band)
    if stage == 'hunt':
        plan = ['Keep hunting %s while its band holds the level' % (pick.get('n') or 'here'),
                'Look at the bag every 4 minutes: wear a better piece, drop junk',
                'Trip to town (Town Portal) when the bag is full or every 25 minutes',
                'Move on to the next hunt when level %s outgrows it' % (pick.get('hi') if pick.get('hi') is not None else 'the band')]
    elif stage in ('trip', 'hall', 'town', 'start', 'wait'):
        names = {'depot': 'Depot locker', 'gate': 'Temple teleport to the hall'}
        steps = [names.get(t, t[4:] if str(t).startswith('npc:') else str(t)) for t in (getattr(j, 'todo', None) or [])]
        plan = steps + (['Walk to the hunt %s' % target['n']] if target.get('n') else ['Pick the hunt of its level in the teleport room'])
        if stage == 'trip':
            why = 'a trip to town: the bag is full or %d minutes passed since the last one (sell, potions, depot)' % 25
        elif stage == 'wait':
            why = 'no hunt in the teleport room may be entered at this level'
        elif not why:
            fb = getattr(j, 'fallbacks', None) or []
            why = ('fallback: ' + fb[-1]) if fb and stage == 'start' else 'back in town: next the hunt of its level'
    elif stage == 'leave':
        plan = ['Cast Town Portal and step into it', 'Camp portal of the hunt if that fails', 'Helper town teleport as the last fallback (counted)']
    return {'goal': goal, 'why': clean(why), 'spot': clean(spot), 'plan': [clean(p) for p in plan][:PLAN_MAX]}


def behaviour_view(name, checks_todo=None, level=None, class_name=None):
    """goal, why, plan of a scheduler behaviour: the label and sentence of GOALS; for the system checks the checks still to run"""
    label, what = GOALS.get(name, (name.capitalize(), ''))
    plan = []
    if name == 'checks' and checks_todo:
        plan = ['Check: %s' % k for k in list(checks_todo)[:PLAN_MAX]]
        why = 'system checks of its class: %d still to run' % len(checks_todo)
    elif name == 'journey':
        why = what
    else:
        why = 'picked by the scheduler (weights of tester_core.BEHAVIOURS): ' + what if what else 'picked by the scheduler'
    if name not in ('checks', 'journey'):
        plan = ['Finish: ' + what if what else 'Finish', 'Then the scheduler picks the next behaviour after 5 to 15 seconds']
    return {'goal': label, 'why': clean(why), 'plan': [clean(p) for p in plan][:PLAN_MAX]}


# ------------------------------------------------------------------------------------------------ the writer
class BotBoard:
    """the live state of the bots of one process; `flush()` writes the files (call it about once a second)"""

    def __init__(self, folder, clock=time.time, src='py'):
        self.folder = folder
        self.clock = clock
        self.src = src
        self.bots = {}      # name -> entry dict
        self.dirty = set()
        self.written = {}   # name -> clock of the last write
        os.makedirs(folder, mode=0o755, exist_ok=True)

    def entry(self, name):
        e = self.bots.get(name)
        if e is None:
            if not slug(name):
                return None
            now = int(self.clock())
            e = {'v': VERSION, 'name': name, 'class': '', 'level': 0, 'pos': None, 'goal': '', 'goal_since': now, 'why': '', 'spot': '',
                 'now': '', 'plan': [], 'log': [], 't': now, 'src': self.src}
            self.bots[name] = e
        return e

    def set(self, name, **f):
        """change fields of a bot: class_ / cls, level, pos, goal, why, spot, now, plan. A new goal restarts goal_since"""
        e = self.entry(name)
        if e is None:
            return False
        changed = False
        for key, val in f.items():
            key = {'cls': 'class', 'class_': 'class'}.get(key, key)
            if key == 'level':
                val = int(val) if isinstance(val, int) and not isinstance(val, bool) and val >= 0 else e['level']
            elif key == 'pos':
                val = pos_list(val) or e['pos']
            elif key == 'plan':
                val = [clean(p) for p in (val or [])][:PLAN_MAX]
            elif key in ('goal', 'class'):
                val = clean(val, 60)
            elif key in ('why', 'spot', 'now'):
                val = clean(val)
            else:
                continue
            if e.get(key) != val:
                if key == 'goal':
                    e['goal_since'] = int(self.clock())
                e[key] = val
                changed = True
        if changed:
            self.dirty.add(name)
        return changed

    def log(self, name, text, kind=None):
        """one line at the end of the bot's log (newest last), and the bot's `now` becomes it"""
        e = self.entry(name)
        if e is None:
            return False
        line = clean(('%s: %s' % (kind, text)) if kind else text, TEXT_MAX)
        if not line:
            return False
        e['log'].append([int(self.clock()), line])
        del e['log'][:-LOG_MAX]
        e['now'] = line
        self.dirty.add(name)
        return True

    def drop(self, name):
        self.bots.pop(name, None)
        self.dirty.discard(name)
        self.written.pop(name, None)
        s = slug(name)
        if s:
            try:
                os.unlink(os.path.join(self.folder, s + SUFFIX))
            except OSError:
                pass

    def line(self, name, now=None):
        e = self.bots[name]
        e['t'] = int(now if now is not None else self.clock())
        return json.dumps(e, separators=(',', ':'), ensure_ascii=True) + '\n'

    def write(self, name, now):
        path = os.path.join(self.folder, slug(name) + SUFFIX)
        text = self.line(name, now)
        fd, tmp = tempfile.mkstemp(prefix='.tmp', dir=self.folder)
        try:
            os.fchmod(fd, 0o644)
            with os.fdopen(fd, 'w') as f:
                f.write(text)
            os.replace(tmp, path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
        self.written[name] = now

    def flush(self, force=False):
        """write the files that are due: a changed bot at most every WRITE_EVERY seconds, any bot at least every HEARTBEAT seconds.
        -> number of files written. An unwritable folder is not an error of the bots (the map just does not move)"""
        now = float(self.clock())
        n = 0
        for name in list(self.bots):
            last = self.written.get(name)
            due = force or last is None or (name in self.dirty and now - last >= WRITE_EVERY) or now - last >= HEARTBEAT
            if not due:
                continue
            try:
                self.write(name, now)
            except OSError:
                continue
            self.dirty.discard(name)
            n += 1
        return n

    def close(self):
        """the run is over: the bots' files go (a file the process cannot remove goes stale and is dropped by the page)"""
        for name in list(self.bots):
            self.drop(name)

    def clear_folder(self):
        """files left by an earlier run (a killed process): removed at the start of a run"""
        clear_folder(self.folder)


def clear_folder(folder):
    n = 0
    try:
        names = os.listdir(folder)
    except OSError:
        return 0
    for f in names:
        if f.endswith(SUFFIX) or f.startswith('.tmp'):
            try:
                os.unlink(os.path.join(folder, f))
                n += 1
            except OSError:
                pass
    return n


def read_folder(folder, now=None):
    """[(entry, 'live' | 'stale')] of a folder, the dropped and the broken left out, ordered by name (the python twin of botmap_lib.php)"""
    now = time.time() if now is None else now
    out = []
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return out
    for f in names:
        if not f.endswith(SUFFIX) or f.startswith('.'):
            continue
        try:
            with open(os.path.join(folder, f), encoding='utf-8') as fh:
                e = json.loads(fh.read(65536))
        except (OSError, ValueError):
            continue
        if not isinstance(e, dict) or not NAME_RE.match(str(e.get('name', ''))):
            continue
        st = age_state(e.get('t'), now)
        if st != 'gone':
            out.append((e, st))
    return out


def main(argv):
    if len(argv) == 2 and argv[0] == 'show':
        rows = read_folder(argv[1])
        for e, st in rows:
            print('%s;%s;L%s;%s;%s;%s;%s' % (e['name'], e.get('class', ''), e.get('level', 0), ','.join(str(v) for v in (e.get('pos') or [])) or '-',
                                              e.get('goal', ''), st, e.get('now', '')))
        print('bots=%d' % len(rows))
        print('stale=%d' % sum(1 for _, st in rows if st == 'stale'))
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

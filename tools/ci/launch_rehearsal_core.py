#!/usr/bin/env python3
"""Launch rehearsal (O441), the pure part: no server, no database, no network.

tools/ci/launch_rehearsal.sh runs the real server under a shifted clock (libfaketime, TZ America/Sao_Paulo) and this file
holds what needs no server:
  * the boundary table, read from the REAL committed configs with the readers of server/deploy/launch_check.py
    (season_config.lua, founder_config.lua, battleground_config.lua, creator_codes_config.lua, weekend_config.lua)
  * the plan: which fake start time each server run gets, and when the probe samples
  * the decision of every check from its observed inputs (booleans, counts, state words, seconds), and the report text
  * parse_start_line / parse_log: facts out of the server log, as counts and numbers only (never a log line)

Observations of one run are JSON: {"facts": {...}, "samples": [{"at": s, "fake": epoch, ...}, ...]}. The probe
(tools/ci/launch_rehearsal_probe.py) writes the samples; the shell adds the facts. Nothing secret is ever an observation.

usage (the shell tool):
  launch_rehearsal_core.py plan --server DIR [--save-time HH:MM]         the runs, one TSV line each
  launch_rehearsal_core.py startline LOG | logfacts LOG                  JSON facts of a server log, numbers only
  launch_rehearsal_core.py setfact FILE KEY JSON                         add a fact to an observation file
  launch_rehearsal_core.py creator-instants --server DIR                 four unix times at the edges of the creator window
  launch_rehearsal_core.py lcfacts < launch_check.py --json              {check name: OK | WARN | FAIL}
  launch_rehearsal_core.py decide --server DIR --obs DIR --report FILE   one OK / FAIL line per check, report, exit code
Lua 5.1 / LuaJIT readers are the tolerant ones of launch_check.py; this file only reads.
"""
import datetime
import json
import os
import re
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'server', 'deploy'))
import launch_check as LC  # noqa: E402

LAUNCH = LC.LAUNCH            # '2026-11-20 15:00', Brasilia
EXPECT_OFFSET = -180          # minutes east of UTC
LEAD = 120                    # seconds before a boundary the server is started (fake clock)
READY = 55                    # real seconds after the start of tfs: first sample, the server is up
SETTLE = 80                   # real seconds past a boundary before the sample "after" (the season check runs every 60 s)
TOLERANCE = 90                # seconds: the server's countdowns against the planned fake clock
NOTIFY_MINUTES = 5            # config.lua serverSaveNotifyDuration of the stock config

CHECKS = ('start_line', 'founder', 'season', 'season_once', 'pvp', 'creator', 'weekend', 'save', 'launch_check')


# ------------------------------------------------------------------ the boundary table, from the real configs
def _read(path):
    text = LC.read_text(path)
    if text is None:
        raise ValueError('cannot read %s' % os.path.basename(path))
    return LC.strip_comments(text)


def _cfg_dir(server):
    return os.path.join(server, 'data', 'scripts', 'chaos')


def _need(value, what):
    if value is None:
        raise ValueError('cannot read %s' % what)
    return value


def read_boundaries(server):
    """Every date of the launch systems as a naive local datetime, from the configs of the server folder."""
    d = _cfg_dir(server)
    out = {}
    # Season 1: the first entry of `seasons` (its id is checked)
    t = _read(os.path.join(d, 'season_config.lua'))
    block = _need(LC.lua_table(t, 'seasons'), 'seasons in season_config.lua')
    if LC.lua_value(block, 'id') != 1:
        raise ValueError('the first season of season_config.lua is not id 1')
    hour = LC.lua_value(block, 'hour')
    hour = hour if isinstance(hour, int) and not isinstance(hour, bool) else 0
    out['season_start'] = _need(LC.to_datetime(LC.lua_value(block, 'start'), hour), 'Season 1 start')
    out['season_end'] = _need(LC.to_datetime(LC.lua_value(block, 'finish'), hour), 'Season 1 finish')
    # PvP Season 1: the epoch and the weeks
    t = _read(os.path.join(d, 'battleground_config.lua'))
    season = _need(LC.lua_table(t, 'season'), 'season in battleground_config.lua')
    epoch = _need(LC.lua_table(season, 'epoch'), 'the PvP season epoch')
    parts = {k: LC.lua_value(epoch, k) for k in ('year', 'month', 'day', 'hour')}
    weeks = LC.lua_value(season, 'weeks')
    if not isinstance(weeks, int) or isinstance(weeks, bool) or weeks < 1 or None in (parts['year'], parts['month'], parts['day']):
        raise ValueError('cannot read the PvP season epoch')
    out['pvp_start'] = datetime.datetime(parts['year'], parts['month'], parts['day'], parts['hour'] or 0, 0)
    out['pvp_weeks'] = weeks
    out['pvp_end'] = out['pvp_start'] + datetime.timedelta(weeks=weeks)
    # Founder Pack: local START / END of founder_config.lua (the same two lines launch_check.py reads)
    t = _read(os.path.join(d, 'founder_config.lua'))
    ms = re.search(r'(?m)^[ \t]*local[ \t]+START[ \t]*=[ \t]*"([^"\n]*)"', t)
    me = re.search(r'(?m)^[ \t]*local[ \t]+END[ \t]*=[ \t]*"([^"\n]*)"', t)
    out['founder_start'] = _need(LC.to_datetime(ms.group(1) if ms else None), 'the Founder Pack start')
    out['founder_end'] = _need(LC.to_datetime(me.group(1) if me else None), 'the Founder Pack end')
    # creator launch bonus
    t = _read(os.path.join(d, 'creator_codes_config.lua'))
    start = _need(LC.to_datetime(LC.lua_value(t, 'launchBonusStart')), 'launchBonusStart')
    days = LC.lua_value(t, 'launchBonusDays')
    pct = LC.lua_value(t, 'launchBonusPct')
    base = LC.lua_value(t, 'sharePct')
    if any(not isinstance(v, int) or isinstance(v, bool) for v in (days, pct, base)):
        raise ValueError('cannot read the creator launch bonus')
    out['creator_start'] = start
    out['creator_end'] = start + datetime.timedelta(days=days)   # the last second of the window is one second before
    out['creator_pct'] = pct
    out['creator_base'] = base
    # weekend ritual: C.schedule {start, finish}, the theme rotation
    t = re.sub(r'\bC\.', '', _read(os.path.join(d, 'weekend_config.lua')))
    sched = _need(LC.lua_table(t, 'schedule'), 'schedule in weekend_config.lua')
    for key in ('start', 'finish'):
        row = _need(LC.lua_table(sched, key), 'schedule.%s' % key)
        vals = [LC.lua_value(row, k) for k in ('weekday', 'hour', 'minute')]
        if any(not isinstance(v, int) or isinstance(v, bool) for v in vals):
            raise ValueError('cannot read schedule.%s' % key)
        out['weekend_' + key] = tuple(vals)
    out['weekend_epoch'] = _need(LC.to_datetime(LC.lua_value(t, 'epoch')), 'the weekend epoch')
    rot = re.search(r'rotation\s*=\s*\{([^}]*)\}', t)
    out['weekend_rotation'] = re.findall(r'"([^"]+)"', rot.group(1)) if rot else []
    out['weekend_themes'] = {m.group(1): m.group(2) for m in re.finditer(r'(\w+)\s*=\s*\{name\s*=\s*"([^"]+)"', t)}
    if not out['weekend_rotation']:
        raise ValueError('cannot read the weekend rotation')
    return out


def lua_wday(dt):
    """os.date("*t").wday: 1 = Sunday ... 7 = Saturday"""
    return (dt.weekday() + 1) % 7 + 1


def next_at(after, wday, hour, minute):
    """The first datetime at or after `after` on Lua weekday `wday` at hour:minute."""
    dt = after.replace(hour=hour, minute=minute, second=0, microsecond=0)
    for _ in range(9):
        if lua_wday(dt) == wday and dt >= after:
            return dt
        dt += datetime.timedelta(days=1)
    raise ValueError('no such weekday')


def weekend_window(b, after):
    """(start, end) of the first Weekend Ritual that starts at or after `after`. `finish` is the last minute."""
    sw, sh, sm = b['weekend_start']
    fw, fh, fm = b['weekend_finish']
    start = next_at(after, sw, sh, sm)
    end = next_at(start, fw, fh, fm) + datetime.timedelta(minutes=1)
    return start, end


def weekend_theme(b, start):
    """The theme name of the weekend that starts at `start` (weekend_config.lua: the epoch's weekend has the first)."""
    weeks = (start.date() - b['weekend_epoch'].date()).days // 7
    key = b['weekend_rotation'][weeks % len(b['weekend_rotation'])]
    return b['weekend_themes'].get(key, key)


# ------------------------------------------------------------------ the plan
def stamp(dt):
    return dt.strftime('%Y-%m-%d %H:%M:%S')


def parse_hhmm(s):
    m = re.match(r'^(\d{1,2}):(\d{2})$', s.strip())
    if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59:
        raise ValueError('time must be HH:MM')
    return int(m.group(1)), int(m.group(2))


def make_run(rid, boundary, title, after=True):
    """A run: tfs starts LEAD seconds before `boundary` on the fake clock; samples at READY and just past the boundary."""
    start = boundary - datetime.timedelta(seconds=LEAD)
    cross = LEAD + 0                       # real seconds from the start to the boundary (the clock runs at rate 1)
    samples = [READY] + ([cross + SETTLE] if after else [])
    return {'id': rid, 'title': title, 'start': start, 'boundary': boundary, 'cross': cross, 'samples': samples}


def plan(b, save_time=(6, 0)):
    """The server runs, in order. Every run is a real start of tfs on a fake clock."""
    launch = LC.parse_launch(LAUNCH)
    runs = []
    r = make_run('launch', b['season_start'], 'launch minute, Season 1, Founder, PvP, creator')
    r['expect_boundaries'] = {'season': b['season_start'], 'founder': b['founder_start'], 'pvp': b['pvp_start']}
    runs.append(r)
    r = make_run('again', b['season_start'] + datetime.timedelta(minutes=4), 'restart after the start', after=False)
    r['cross'] = None
    r['samples'] = [READY]
    runs.append(r)
    ws, we = weekend_window(b, launch)
    runs.append(make_run('weekend_on', ws, 'weekend ritual starts'))
    runs.append(make_run('weekend_off', we, 'weekend ritual ends'))
    day = we.replace(hour=0, minute=0) + datetime.timedelta(days=0)
    save = day.replace(hour=save_time[0], minute=save_time[1])
    if save <= we:
        save += datetime.timedelta(days=1)
    r = make_run('save', save, 'daily save')
    r['wait_exit'] = NOTIFY_MINUTES * 60 + 150      # real seconds past the boundary the process may take to stop
    runs.append(r)
    runs.append(make_run('founder_end', b['founder_end'], 'Founder Pack closes'))
    # chronological: the database keeps the last logout of the probe character, and a clock that goes back before it makes
    # the offline training of the next login negative (a rehearsal artefact, never the launch)
    runs.sort(key=lambda x: x['start'])
    return runs


def plan_tsv(runs):
    """id, fake start (local), samples (real seconds, comma), boundary real seconds or -, exit wait or 0"""
    out = []
    for r in runs:
        out.append('\t'.join([r['id'], stamp(r['start']), ','.join(str(s) for s in r['samples']),
                              '-' if r['cross'] is None else str(r['cross']), str(r.get('wait_exit', 0))]))
    return '\n'.join(out)


# ------------------------------------------------------------------ facts out of a server log, numbers only
START_RE = re.compile(r'>> Timezone: local time (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}), UTC([+-])(\d{2}):(\d{2})')


def parse_start_line(text):
    """The O439 line: {"time": "YYYY-MM-DD HH:MM:SS", "offset": minutes, "lines": n, "warnings": n}; None fields when absent."""
    m = START_RE.search(text or '')
    res = {'time': None, 'offset': None, 'lines': len(START_RE.findall(text or '')),
           'warnings': len(re.findall(r'TIMEZONE WARNING', text or ''))}
    if m:
        res['time'] = m.group(1)
        res['offset'] = (1 if m.group(2) == '+' else -1) * (int(m.group(3)) * 60 + int(m.group(4)))
    return res


def parse_log(text):
    """Counts only: the automatic season start lines, the season character count of the start line, Lua errors."""
    text = text or ''
    running = re.search(r'\[Chaos season\] .* running, (\d+) season character\(s\)', text)
    return {
        'season_start_lines': len(re.findall(r'\[Chaos season\] start: season 1,', text)),
        'season_end_lines': len(re.findall(r'\[Chaos season\] end: season 1,', text)),
        'season_running_line': 1 if running else 0,
        'season_members': int(running.group(1)) if running else None,
        'weekend_begin_lines': len(re.findall(r'\[Chaos weekend\] WEEKEND RITUAL: the weekend begins!', text)),
        'lua_errors': len(re.findall(r'\[Error - |Lua Script Error', text)),
    }


def creator_instants(b):
    """Unix times of the four donations credited at the edges of the creator launch bonus window: one second before it
    opens, its first second, its last second, one second after it closes. The window is Brasilia time (UTC-3, no daylight
    saving time), so the offset is fixed here: the server converts with its own zone and must land on the same seconds."""
    def unix(dt):
        return int((dt - datetime.datetime(1970, 1, 1)).total_seconds()) + 3 * 3600
    one = datetime.timedelta(seconds=1)
    return [('before', unix(b['creator_start'] - one)), ('start', unix(b['creator_start'])),
            ('last', unix(b['creator_end'] - one)), ('after', unix(b['creator_end']))]


def lc_facts(report):
    """{check name: status} out of the JSON of `launch_check.py --json`"""
    return {c['name']: c['status'] for c in report.get('checks', []) if 'name' in c and 'status' in c}


# ------------------------------------------------------------------ decisions
def res(name, ok, text):
    return {'name': name, 'ok': bool(ok), 'text': text}


def yn(v):
    return 'yes' if v else 'no'


def pick(samples, which):
    """first / last sample of a run, or None"""
    if not samples:
        return None
    return samples[0] if which == 'before' else samples[-1]


def decide_start_line(facts, planned_start):
    """O439: the line shows the shifted local time and offset -180, and no warning."""
    t = facts.get('time')
    off = facts.get('offset')
    warn = facts.get('warnings')
    delta = None
    if t:
        try:
            delta = (datetime.datetime.strptime(t, '%Y-%m-%d %H:%M:%S') - planned_start).total_seconds()
        except ValueError:
            delta = None
    good = (t is not None and off == EXPECT_OFFSET and warn == 0 and delta is not None and -5 <= delta <= 240)
    shown = 'none' if delta is None else '%+.0f s' % delta
    return res('start_line', good, 'time %s (planned %s, %s), offset %s, warnings %s' %
               (t or 'missing', stamp(planned_start), shown, off, warn))


def countdown_ok(value, expected):
    return isinstance(value, (int, float)) and abs(value - expected) <= TOLERANCE


def decide_founder(runs_obs, b):
    """Closed before 20 Nov 15:00, open after; open before 18 Dec 15:00, closed after (the store category the client gets)."""
    parts = []
    for rid, key, want in (('launch', 'founder_start', (False, True)), ('founder_end', 'founder_end', (True, False))):
        o = runs_obs.get(rid)
        label = 'Founder Pack listed in the store at %s' % stamp(b[key])[:16]
        if not o or len(o['samples']) < 2:
            parts.append(res('founder', False, '%s: no run' % label))
            continue
        before = o['samples'][0].get('founder', {}).get('listed')
        after = o['samples'][-1].get('founder', {}).get('listed')
        parts.append(res('founder', (before, after) == want, '%s: before %s after %s (want %s then %s)' % (
            label, yn(before), yn(after), yn(want[0]), yn(want[1]))))
    return _merge('founder', parts)


def _merge(name, parts):
    if not parts:
        return res(name, False, 'no run')
    return res(name, all(p['ok'] for p in parts), '; '.join(p['text'] for p in parts))


def decide_season(o, b):
    """Season 1: upcoming before the start, active after, the countdowns match the fake clock, the start line logged once."""
    if not o or len(o['samples']) < 2:
        return res('season', False, 'no run')
    s0, s1 = o['samples'][0], o['samples'][-1]
    a, c = s0.get('season', {}), s1.get('season', {})
    exp_starts = (b['season_start'] - _fake(s0)).total_seconds() if _fake(s0) else None
    exp_ends = (b['season_end'] - _fake(s1)).total_seconds() if _fake(s1) else None
    good = (a.get('status') == 'upcoming' and c.get('status') == 'active' and a.get('id') == 1 and c.get('id') == 1
            and exp_starts is not None and countdown_ok(a.get('startsIn'), exp_starts)
            and exp_ends is not None and countdown_ok(c.get('endsIn'), exp_ends)
            and (s1.get('broadcasts', {}).get('season_begun') == 1)
            and o['facts'].get('season_start_lines') == 1)
    return res('season', good, 'before %s (startsIn off by %s s), after %s (endsIn off by %s s), begun broadcast %s, start log lines %s' % (
        a.get('status'), _off(a.get('startsIn'), exp_starts), c.get('status'), _off(c.get('endsIn'), exp_ends),
        s1.get('broadcasts', {}).get('season_begun'), o['facts'].get('season_start_lines')))


def _fake(sample):
    """the shifted local time of a sample, written by the probe as "YYYY-MM-DD HH:MM:SS" (no time zone in it)"""
    try:
        return datetime.datetime.strptime(sample.get('fake'), '%Y-%m-%d %H:%M:%S')
    except (TypeError, ValueError):
        return None


def _off(value, expected):
    if not isinstance(value, (int, float)) or expected is None:
        return 'n/a'
    return '%+.0f' % (value - expected)


def decide_season_once(first, again):
    """After a restart past the start: still active, no second start (log and database), the season characters and their
    progress are untouched."""
    if not first or not again or not again['samples']:
        return res('season_once', False, 'no run')
    f1, f2 = first['facts'], again['facts']
    st = again['samples'][0].get('season', {})
    good = (st.get('status') == 'active'
            and f2.get('season_start_lines') == 0 and f2.get('season_running_line') == 1
            and f1.get('db_start_rows') == 1 and f2.get('db_start_rows') == 1
            and f2.get('db_end_rows') == 0 and f2.get('db_migrated_rows') == 0
            and f1.get('sentinel_rows') == 1 and f2.get('sentinel_rows') == 1
            and f1.get('sentinel_value') == f2.get('sentinel_value') and f2.get('sentinel_value') is not None
            and f2.get('season_members') is not None and f2.get('season_members') == f2.get('db_members'))
    return res('season_once', good, 'after the restart: status %s, start log lines %s, start rows %s then %s, end rows %s, '
               'migrated rows %s, sentinel rows %s then %s, progress kept %s' % (
                   st.get('status'), f2.get('season_start_lines'), f1.get('db_start_rows'), f2.get('db_start_rows'),
                   f2.get('db_end_rows'), f2.get('db_migrated_rows'), f1.get('sentinel_rows'), f2.get('sentinel_rows'),
                   yn(f1.get('sentinel_value') == f2.get('sentinel_value') and f2.get('sentinel_value') is not None)))


def decide_pvp(o, b):
    """PvP Season 1: the window the client gets: season 1, not started before the epoch, running after, ends in the weeks."""
    if not o or len(o['samples']) < 2:
        return res('pvp', False, 'no run')
    s0, s1 = o['samples'][0], o['samples'][-1]
    a, c = s0.get('pvp', {}), s1.get('pvp', {})
    full = b['pvp_weeks'] * 7 * 86400
    exp0 = (b['pvp_end'] - _fake(s0)).total_seconds() if _fake(s0) else None
    exp1 = (b['pvp_end'] - _fake(s1)).total_seconds() if _fake(s1) else None
    before = isinstance(a.get('endsIn'), (int, float)) and a['endsIn'] > full
    after = isinstance(c.get('endsIn'), (int, float)) and 0 < c['endsIn'] <= full
    good = (before and after and a.get('id') == 1 and c.get('id') == 1 and exp0 is not None and countdown_ok(a.get('endsIn'), exp0)
            and exp1 is not None and countdown_ok(c.get('endsIn'), exp1))
    return res('pvp', good, 'before: started %s (endsIn off by %s s), after: started %s (endsIn off by %s s), weeks %d' % (
        yn(not before), _off(a.get('endsIn'), exp0), yn(after), _off(c.get('endsIn'), exp1), b['pvp_weeks']))


def decide_creator(facts, b):
    """The share a donation earns by the instant it was credited: before the window the base, inside the launch pct, the
    last second inside, the first second after the base again. Rows are the shares the server wrote for 1000 coins."""
    rows = facts.get('creator_shares') or {}
    want = {'before': b['creator_base'] * 10, 'start': b['creator_pct'] * 10, 'last': b['creator_pct'] * 10,
            'after': b['creator_base'] * 10}
    good = all(rows.get(k) == v for k, v in want.items())
    return res('creator', good, 'share of 1000 coins: 1 s before %s, first second %s, last second %s, 1 s after %s (window %s to %s)' % (
        rows.get('before'), rows.get('start'), rows.get('last'), rows.get('after'),
        stamp(b['creator_start'])[:16], stamp(b['creator_end'])[:16]))


def decide_weekend(on_run, off_run, b):
    """off before Fri 18:00, on after (the start announced once), on before Sun 23:59, off after"""
    parts = []
    for rid, o, want in (('weekend_on', on_run, (False, True)), ('weekend_off', off_run, (True, False))):
        if not o or len(o['samples']) < 2:
            parts.append(res('weekend', False, '%s: no run' % rid))
            continue
        s0, s1 = o['samples'][0], o['samples'][-1]
        r0 = s0.get('weekend', {}).get('running')
        r1 = s1.get('weekend', {}).get('running')
        extra = ''
        good = (r0, r1) == want
        if rid == 'weekend_on':
            n = s1.get('broadcasts', {}).get('weekend_begins')
            lines = o['facts'].get('weekend_begin_lines')
            pre = s0.get('weekend', {}).get('preview')
            # one announcement in the server log; the client gets its text twice (the broadcast and the toast)
            good = good and lines == 1 and isinstance(n, int) and n >= 1 and pre is True
            extra = ', announced %s time(s) by the server and seen %s time(s) by the client, login preview %s' % (lines, n, yn(pre))
        parts.append(res('weekend', good, '%s running %s then %s (want %s then %s)%s' % (
            'start' if rid == 'weekend_on' else 'end', yn(r0), yn(r1), yn(want[0]), yn(want[1]), extra)))
    return _merge('weekend', parts)


def decide_save(o):
    """The save notice fires once when the clock crosses it, then the engine stops once, a notice period later."""
    if not o or len(o['samples']) < 2:
        return res('save', False, 'no run')
    s0, s1 = o['samples'][0], o['samples'][-1]
    n0 = s0.get('broadcasts', {}).get('save_first', 0)
    n1 = s1.get('broadcasts', {}).get('save_first')
    exit_after = o['facts'].get('exit_after')
    good = (n0 == 0 and n1 == 1 and isinstance(exit_after, (int, float)) and
            NOTIFY_MINUTES * 60 - 30 <= exit_after <= NOTIFY_MINUTES * 60 + 60)
    return res('save', good, 'first notice before %s, after %s time(s); the process stopped %s s after the boundary (notice period %d s)' % (
        n0, n1, 'never' if exit_after is None else '%.0f' % exit_after, NOTIFY_MINUTES * 60))


def decide_launch_check(facts):
    """launch_check.py under the shifted clock: the four date checks and the timezone check are OK"""
    got = facts.get('launch_check') or {}
    names = ('dates_season', 'dates_pvp', 'dates_founder', 'dates_creator', 'timezone')
    good = all(got.get(n) == 'OK' for n in names)
    return res('launch_check', good, ', '.join('%s %s' % (n, got.get(n, 'missing')) for n in names))


def decide_all(b, runs, obs):
    """Every check as a list of results. obs: {run id: observation}."""
    by = {r['id']: r for r in runs}
    out = []
    first = obs.get('launch')
    out.append(decide_start_line((first or {}).get('facts', {}).get('start_line', {}), by['launch']['start'])
               if first else res('start_line', False, 'no run'))
    out.append(decide_founder(obs, b))
    out.append(decide_season(first, b))
    out.append(decide_season_once(first, obs.get('again')))
    out.append(decide_pvp(first, b))
    out.append(decide_creator((first or {}).get('facts', {}), b))
    out.append(decide_weekend(obs.get('weekend_on'), obs.get('weekend_off'), b))
    out.append(decide_save(obs.get('save')))
    out.append(decide_launch_check((first or {}).get('facts', {})))
    return out


def report_text(b, results, launch=LAUNCH):
    lines = ['Launch rehearsal (O441): the real server under a shifted clock, TZ America/Sao_Paulo',
             'launch %s, Season 1 %s to %s, Founder %s to %s, creator bonus %d%% to %s, weekend theme at launch: %s' % (
                 launch, stamp(b['season_start'])[:16], stamp(b['season_end'])[:10], stamp(b['founder_start'])[:16],
                 stamp(b['founder_end'])[:16], b['creator_pct'], stamp(b['creator_end'])[:16],
                 weekend_theme(b, weekend_window(b, LC.parse_launch(launch))[0])), '']
    for r in results:
        lines.append('%s %s: %s' % ('OK  ' if r['ok'] else 'FAIL', r['name'], r['text']))
    bad = sum(1 for r in results if not r['ok'])
    lines.append('')
    lines.append('launch rehearsal: %d FAIL, %d OK' % (bad, len(results) - bad))
    return '\n'.join(lines)


def exit_code(results):
    return 1 if any(not r['ok'] for r in results) else 0


# ------------------------------------------------------------------ command line
def load_obs(folder, runs):
    obs = {}
    for r in runs:
        p = os.path.join(folder, r['id'] + '.json')
        if os.path.isfile(p):
            with open(p) as f:
                try:
                    obs[r['id']] = json.load(f)
                except ValueError:
                    pass
    return obs


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]

    def opt(name, default=None):
        return rest[rest.index(name) + 1] if name in rest else default

    if cmd == 'plan':
        b = read_boundaries(opt('--server'))
        print(plan_tsv(plan(b, parse_hhmm(opt('--save-time', '06:00')))))
        return 0
    if cmd in ('startline', 'logfacts'):
        with open(rest[0], errors='replace') as f:
            text = f.read()
        print(json.dumps(parse_start_line(text) if cmd == 'startline' else parse_log(text)))
        return 0
    if cmd == 'setfact':
        path, key, val = rest[0], rest[1], json.loads(rest[2])
        data = {'facts': {}, 'samples': []}
        if os.path.isfile(path):
            with open(path) as f:
                data = json.load(f)
        data.setdefault('facts', {})[key] = val
        with open(path, 'w') as f:
            json.dump(data, f)
        return 0
    if cmd == 'creator-instants':
        for name, epoch in creator_instants(read_boundaries(opt('--server'))):
            print('%s %d' % (name, epoch))
        return 0
    if cmd == 'lcfacts':
        try:
            print(json.dumps(lc_facts(json.load(sys.stdin))))
        except ValueError:
            print('{}')
        return 0
    if cmd == 'decide':
        b = read_boundaries(opt('--server'))
        runs = plan(b, parse_hhmm(opt('--save-time', '06:00')))
        results = decide_all(b, runs, load_obs(opt('--obs'), runs))
        text = report_text(b, results)
        print(text)
        if opt('--report'):
            with open(opt('--report'), 'w') as f:
                f.write(text + '\n')
        return exit_code(results)
    print('unknown command %s' % cmd, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

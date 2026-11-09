#!/usr/bin/env python3
"""Launch check (O440): are the launch switches of the INSTALLED server right? `chaos-ctl.sh launch-check [--json]`.

Reads the installed server folder, the env files, the backup folder, the checkout and counts from the database. Changes
NOTHING. One line per check: OK, WARN or FAIL, a short name and one sentence; the last line sums them up. Exit 1 when any
check is FAIL, else 0. A check that cannot run (a file is missing, the database is down, a Lua config does not read) is a
FAIL that says why, never a crash and never a silent OK. The Lua configs are read with a small tolerant reader (a regex on
the known keys); what it cannot read is "cannot read", never a guess. The key of the client guard is only tested for
presence: it is never printed, logged or hashed.

Checks (name: FAIL / WARN rule), server/README.md "Launch check (O440)":
  beta_config     beta_config.lua enabled: FAIL when true or unreadable
  beta_mode       beta_mode_config.lua enabled (beta test mode, file only: it is read at the start): FAIL when true
  beta_cron       /etc/cron.d/chaos-beta-coins (docs/BETA.md section 4): FAIL when the file exists
  payments        payments env: FAIL on a mock provider; WARN with no live provider (Mercado Pago, PayPal) or a test token
  test_files      zz_* / ztest* under data/scripts, ztest* in the server folder: FAIL, at most 5 listed
  timezone        chaos_timezone.py: FAIL when the machine is not on America/Sao_Paulo (UTC-3), or CHAOS_TIMEZONE
  max_players     config.lua maxPlayers: WARN "owner decision: 300 or 400"; with --max-players N: FAIL when different
  dates_season    season_config.lua Season 1 start and end: FAIL when the start is not the launch (LAUNCH, --launch)
  dates_pvp       battleground_config.lua PvP season epoch: WARN when it is not the launch
  dates_founder   founder_config.lua window: FAIL when the start is not the launch
  dates_creator   creator_codes_config.lua launch bonus window: WARN when it does not start at the launch
  client_guard    config.lua clientGuardMode and the key (CHAOS_CLIENT_KEY of the env file, clientGuardKey, a key file):
                  FAIL without a key, with mode off or a dev key allowed; WARN in log mode
  patch_notes     data/patchnotes/LAUNCHDATE.md and .pt-br.md: WARN when missing
  database        counts only: players, accounts, accounts with coins, players_online, chaos_beta_testers: WARN when
                  there are players or coins (expected before the wipe, not after it)
  backup          newest file of the backup folder: FAIL when none, WARN when 24 hours old or more
  checkout        git checkout the server was installed from: WARN when dirty or not on main

The shell tool feeds the facts it can only get as root, on stdin, tab separated: `db NAME COUNT|ERR:reason` (one query
per count) and `pay NAME VALUE` (the pay-status lines). Nothing here runs SQL or reads the payment env itself.

usage: python3 -I server/deploy/launch_check.py --server DIR [--env-file F] [--backup-dir D] [--repo D] [--cron-file F]
           [--launch "YYYY-MM-DD HH:MM"] [--max-players N] [--env-file F] [--json] < facts
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True   # read only: no __pycache__ in the checkout
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import chaos_timezone  # noqa: E402

# the launch, local time of the server (Brasilia, UTC-3): Fri 2026-11-20 15:00. --launch changes it.
LAUNCH = '2026-11-20 15:00'
BACKUP_MAX_HOURS = 24
LIST_MAX = 5
CRON_FILE = '/etc/cron.d/chaos-beta-coins'
DB_COUNTS = ('players', 'accounts', 'accounts_with_coins', 'players_online', 'beta_testers')


# ------------------------------------------------------------------ a small tolerant Lua reader
def cut_line_comment(line):
    """The line without its `--` comment (quotes respected)."""
    q = None
    i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == '\\':
                i += 2
                continue
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        elif line.startswith('--', i):
            return line[:i]
        i += 1
    return line


def strip_comments(text):
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', '', text, flags=re.S)
    return '\n'.join(cut_line_comment(line) for line in text.split('\n'))


SCALAR = r'(true|false|-?\d+(?:\.\d+)?|"[^"\n]*"|\'[^\'\n]*\')(?=\s*(?:[,;}]|$))'


def scalar(token):
    if token == 'true':
        return True
    if token == 'false':
        return False
    if token[0] in '"\'':
        return token[1:-1]
    return float(token) if '.' in token else int(token)


def lua_value(text, key, start=0):
    """The first `key = scalar` (bool, int, float or string) at or after `start`, or None. A key that follows a dot or a
    word character is another key. Comments are not part of `text` (strip_comments first)."""
    m = re.compile(r'(?<![\w.])%s\s*=\s*%s' % (re.escape(key), SCALAR), re.M).search(text, start)
    return scalar(m.group(1)) if m else None


def lua_table(text, key):
    """The text of the first `key = { ... }` (balanced braces, strings skipped), or None."""
    m = re.compile(r'(?<![\w.])%s\s*=\s*\{' % re.escape(key)).search(text)
    if not m:
        return None
    depth = 0
    q = None
    i = m.end() - 1
    start = i
    while i < len(text):
        c = text[i]
        if q:
            if c == '\\':
                i += 1
            elif c == q:
                q = None
        elif c in '"\'':
            q = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    return None


def to_datetime(v, hour=0):
    """A Lua date value as a naive local datetime: YYYYMMDD at `hour`, "YYYY-MM-DD [HH:MM]", or a unix time (local
    time of this machine). None when it is none of these."""
    try:
        if isinstance(v, bool) or v is None:
            return None
        if isinstance(v, int):
            if 19000101 <= v <= 99991231:
                return datetime.datetime(v // 10000, v // 100 % 100, v % 100, int(hour or 0), 0)
            if v >= 10 ** 9:
                return datetime.datetime.fromtimestamp(v)
            return None
        if isinstance(v, str):
            m = re.match(r'^(\d{4})-(\d{2})-(\d{2})(?: (\d{1,2}):(\d{2}))?$', v.strip())
            if m:
                h = int(m.group(4)) if m.group(4) is not None else int(hour or 0)
                return datetime.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)), h,
                                         int(m.group(5) or 0))
    except (ValueError, OverflowError, OSError):
        return None
    return None


def fmt(dt):
    return dt.strftime('%Y-%m-%d %H:%M')


def parse_launch(s):
    return datetime.datetime.strptime(s.strip(), '%Y-%m-%d %H:%M')


def env_has(text, key):
    """True when the env file's text sets KEY to a non-empty value. The value is never returned."""
    value = chaos_timezone.env_file_value(text, key)
    return bool(value.strip())


# ------------------------------------------------------------------ the facts of the shell tool
def parse_facts(text):
    """{'db': {name: int | 'ERR:reason'}, 'pay': {name: value}} from the shell tool's tab separated lines."""
    facts = {'db': {}, 'pay': {}}
    for line in (text or '').splitlines():
        p = line.rstrip('\r\n').split('\t')
        if len(p) < 3 or p[0] not in facts:
            continue
        name, value = p[1].strip(), p[2].strip()
        if p[0] == 'db':
            facts['db'][name] = int(value) if re.fullmatch(r'\d{1,12}', value) else (
                value if value.startswith('ERR:') else 'ERR:database')
        else:
            facts['pay'][name] = value
    return facts


# ------------------------------------------------------------------ one function per check: inputs in, (status, name, text) out
def ok(name, text):
    return ('OK', name, text)


def warn(name, text):
    return ('WARN', name, text)


def fail(name, text):
    return ('FAIL', name, text)


def unreadable(name, what):
    return fail(name, 'cannot read %s' % what)


def check_beta_config(text, path='beta_config.lua'):
    name = 'beta_config'
    if text is None:
        return unreadable(name, path)
    v = lua_value(strip_comments(text), 'enabled')
    if v is True:
        return fail(name, '%s has enabled = true: every new account gets free starter coins. Set enabled = false.' % path)
    if v is False:
        return ok(name, '%s enabled = false: no free starter coins.' % path)
    return unreadable(name, "'enabled' in %s" % path)


def check_beta_mode(text, path='beta_mode_config.lua'):
    name = 'beta_mode'
    if text is None:
        return unreadable(name, path)
    v = lua_value(strip_comments(text), 'enabled')
    if v is True:
        return fail(name, '%s has enabled = true: the weekly and daily gameplay limits are lifted. '
                    'chaos-ctl.sh beta-mode off, then restart.' % path)
    if v is False:
        return ok(name, '%s enabled = false: the gameplay limits hold (read at the start of the scripts).' % path)
    return unreadable(name, "'enabled' in %s" % path)


def check_beta_cron(exists, path=CRON_FILE):
    name = 'beta_cron'
    if exists:
        return fail(name, '%s exists: it refills every account with coins every minute. Remove it (docs/BETA.md section 4).' % path)
    return ok(name, 'no beta coins cron (%s).' % path)


def check_payments(pay):
    name = 'payments'
    if not pay or 'pix_provider' not in pay or 'paypal_provider' not in pay:
        return fail(name, 'cannot read the payments status (chaos-ctl.sh pay-status gave nothing)')
    pix, ppl = pay.get('pix_provider', 'off'), pay.get('paypal_provider', 'off')
    if pay.get('mock') == 'yes' or pix == 'mock' or ppl == 'mock':
        return fail(name, 'a mock payment provider is on: it approves every donation for free. Use mercadopago, paypal or off.')
    live = []
    if pix == 'mercadopago':
        live.append('Pix (Mercado Pago)')
    if ppl == 'paypal':
        live.append('PayPal')
    if not live:
        return warn(name, 'no live payment provider (Pix %s, PayPal %s): donations are off. Fine only if that is the plan.' % (pix, ppl))
    if pix == 'mercadopago' and pay.get('mp_token') == 'test':
        return warn(name, 'Pix is on, but the Mercado Pago token is a TEST token.')
    return ok(name, 'live provider: %s, no mock.' % ', '.join(live))


def find_test_files(server):
    """Relative paths of zz_* and ztest* files under data/scripts, and ztest* entries in the server folder."""
    found = []
    base = os.path.join(server, 'data', 'scripts')
    for root, _dirs, files in os.walk(base):
        for f in files:
            if f.startswith('zz_') or f.startswith('ztest'):
                found.append(os.path.relpath(os.path.join(root, f), server))
    try:
        for entry in os.listdir(server):
            if entry.startswith('ztest'):
                found.append(entry)
    except OSError:
        pass
    return sorted(found)


def check_test_files(server):
    name = 'test_files'
    if not os.path.isdir(os.path.join(server, 'data', 'scripts')):
        return unreadable(name, '%s (no data/scripts)' % server)
    found = find_test_files(server)
    if not found:
        return ok(name, 'no zz_* or ztest* file in data/scripts or the server folder.')
    shown = ', '.join(found[:LIST_MAX])
    more = ' and %d more' % (len(found) - LIST_MAX) if len(found) > LIST_MAX else ''
    return fail(name, '%d test only file(s): %s%s. Remove them (docs/LAUNCH.md section 11).' % (len(found), shown, more))


def check_timezone(names, offset, zone, exp_offset):
    r = chaos_timezone.evaluate(names, offset, zone, exp_offset)
    if r['ok']:
        return ok('timezone', r['detail'] + '.')
    return fail('timezone', r['detail'])


def check_max_players(text, want, path='config.lua'):
    name = 'max_players'
    if text is None:
        return unreadable(name, path)
    v = lua_value(strip_comments(text), 'maxPlayers')
    if not isinstance(v, int) or isinstance(v, bool):
        return unreadable(name, "'maxPlayers' in %s" % path)
    if want is None:
        return warn(name, 'maxPlayers = %d (owner decision: 300 or 400).' % v)
    if v != want:
        return fail(name, 'maxPlayers = %d, expected %d.' % (v, want))
    return ok(name, 'maxPlayers = %d, as expected.' % v)


def check_dates_season(text, launch, path='season_config.lua'):
    name = 'dates_season'
    if text is None:
        return unreadable(name, path)
    t = strip_comments(text)
    block = lua_table(t, 'seasons')
    chunk = None
    if block:
        ids = [m for m in re.finditer(r'(?<![\w.])id\s*=\s*(\d+)', block)]
        for i, m in enumerate(ids):
            if int(m.group(1)) == 1:
                chunk = block[m.end():ids[i + 1].start() if i + 1 < len(ids) else len(block)]
                break
    if chunk is None:
        return unreadable(name, 'Season 1 in %s' % path)
    hour = lua_value(chunk, 'hour')
    hour = hour if isinstance(hour, int) and not isinstance(hour, bool) else 0
    start = to_datetime(lua_value(chunk, 'start'), hour)
    finish = to_datetime(lua_value(chunk, 'finish'), hour)
    if start is None or finish is None:
        return unreadable(name, 'start and finish of Season 1 in %s' % path)
    text_ = 'Season 1 runs %s to %s (server local time).' % (fmt(start), fmt(finish))
    if start != launch:
        return fail(name, 'Season 1 starts %s, not at the launch %s. Season 1 to %s (server local time).'
                    % (fmt(start), fmt(launch), fmt(finish)))
    return ok(name, text_)


def check_dates_pvp(text, launch, path='battleground_config.lua'):
    name = 'dates_pvp'
    if text is None:
        return unreadable(name, path)
    t = strip_comments(text)
    season = lua_table(t, 'season')
    epoch = lua_table(season, 'epoch') if season else None
    weeks = lua_value(season, 'weeks') if season else None
    if not epoch:
        return unreadable(name, 'the PvP season epoch in %s' % path)
    parts = {k: lua_value(epoch, k) for k in ('year', 'month', 'day', 'hour')}
    try:
        start = datetime.datetime(parts['year'], parts['month'], parts['day'], parts['hour'] or 0, 0)
    except (TypeError, ValueError):
        return unreadable(name, 'the PvP season epoch in %s' % path)
    end = ''
    if isinstance(weeks, int) and not isinstance(weeks, bool) and weeks > 0:
        end = ' to %s' % fmt(start + datetime.timedelta(weeks=weeks))
    if start != launch:
        return warn(name, 'PvP Season 1 starts %s%s, not at the launch %s.' % (fmt(start), end, fmt(launch)))
    return ok(name, 'PvP Season 1 runs %s%s (server local time).' % (fmt(start), end))


def check_dates_founder(text, launch, path='founder_config.lua'):
    name = 'dates_founder'
    if text is None:
        return unreadable(name, path)
    t = strip_comments(text)
    m = re.search(r'(?m)^[ \t]*local[ \t]+START[ \t]*=[ \t]*"([^"\n]*)"', t)
    sv = m.group(1) if m else lua_value(t, 'start')
    m = re.search(r'(?m)^[ \t]*local[ \t]+END[ \t]*=[ \t]*"([^"\n]*)"', t)
    ev = m.group(1) if m else lua_value(t, 'end')
    start, end = to_datetime(sv), to_datetime(ev)
    if start is None or end is None:
        return unreadable(name, 'the Founder Pack window in %s' % path)
    if start != launch:
        return fail(name, 'the Founder Pack starts %s, not at the launch %s (ends %s).' % (fmt(start), fmt(launch), fmt(end)))
    return ok(name, 'the Founder Pack is on sale %s to %s (server local time).' % (fmt(start), fmt(end)))


def check_dates_creator(text, launch, path='creator_codes_config.lua'):
    name = 'dates_creator'
    if text is None:
        return unreadable(name, path)
    t = strip_comments(text)
    start = to_datetime(lua_value(t, 'launchBonusStart'))
    days = lua_value(t, 'launchBonusDays')
    if start is None or not isinstance(days, int) or isinstance(days, bool):
        return unreadable(name, 'the creator launch bonus window in %s' % path)
    end = start + datetime.timedelta(days=days)
    if start != launch:
        return warn(name, 'the creator launch bonus starts %s, not at the launch %s (%d days).' % (fmt(start), fmt(launch), days))
    return ok(name, 'the creator launch bonus runs %s to %s (server local time).' % (fmt(start), fmt(end)))


def check_client_guard(config_text, env_text, key_file_ok, path='config.lua'):
    """config_text: config.lua or None; env_text: the env file or None; key_file_ok: the clientGuardKeyFile exists and
    is not empty. The key value is never looked at beyond "is something there"."""
    name = 'client_guard'
    if config_text is None:
        return unreadable(name, path)
    t = strip_comments(config_text)
    mode = lua_value(t, 'clientGuardMode')
    if mode is None:
        return fail(name, "clientGuardMode is not set in %s: the engine default is off, anyone's client may play." % path)
    if not isinstance(mode, str):
        return unreadable(name, "'clientGuardMode' in %s" % path)
    if lua_value(t, 'clientGuardAllowDevKey') is True:
        return fail(name, 'clientGuardAllowDevKey = true: the public development key would be accepted.')
    literal = lua_value(t, 'clientGuardKey')
    env_key = env_text is not None and env_has(env_text, 'CHAOS_CLIENT_KEY')
    key_set = (isinstance(literal, str) and literal != '') or env_key or key_file_ok
    if mode.lower() == 'off':
        return fail(name, 'clientGuardMode = "off": any client may play. Use "enforce".')
    if not key_set:
        return fail(name, 'no client key (CHAOS_CLIENT_KEY of the env file, clientGuardKey or clientGuardKeyFile): every login would fail.')
    if mode.lower() == 'log':
        return warn(name, 'clientGuardMode = "log": the guard only logs. Use "enforce" for the launch.')
    return ok(name, 'clientGuardMode = "%s", a client key is set.' % mode)


def patch_note_names(launch):
    d = launch.strftime('%Y-%m-%d')
    return ['%s.md' % d, '%s.pt-br.md' % d]


def check_patch_notes(server, launch):
    name = 'patch_notes'
    folder = os.path.join(server, 'data', 'patchnotes')
    names = patch_note_names(launch)
    missing = [n for n in names if not os.path.isfile(os.path.join(folder, n))]
    if missing:
        return warn(name, 'missing in data/patchnotes: %s.' % ', '.join(missing))
    return ok(name, 'data/patchnotes has %s.' % ' and '.join(names))


def check_database(db):
    name = 'database'
    if not db:
        return fail(name, 'cannot read the database (no counts from chaos-ctl.sh)')
    bad = [k for k in DB_COUNTS if not isinstance(db.get(k), int)]
    if bad:
        reasons = []
        for k in bad:
            v = db.get(k)
            reasons.append('%s (%s)' % (k, v[4:] if isinstance(v, str) and v.startswith('ERR:') else 'missing'))
        return fail(name, 'cannot read: %s.' % ', '.join(reasons))
    line = 'players %d, accounts %d, accounts with coins %d, online %d, beta testers %d' % tuple(db[k] for k in DB_COUNTS)
    if db['players'] > 0 or db['accounts_with_coins'] > 0:
        return warn(name, line + ' (counts only). Expected before the wipe, not after it.')
    return ok(name, line + ' (counts only).')


def newest_file(folder):
    """(mtime, relative path) of the newest regular file of folder and of its direct subfolders, or None."""
    best = None
    for root, dirs, files in os.walk(folder):
        rel = os.path.relpath(root, folder)
        if rel != '.':
            dirs[:] = []           # the folder itself and its direct subfolders (db/, data/), no deeper
        for f in files:
            if f.startswith('.'):
                continue
            p = os.path.join(root, f)
            try:
                if os.path.islink(p) or not os.path.isfile(p):
                    continue
                m = os.path.getmtime(p)
            except OSError:
                continue
            if best is None or m > best[0]:
                best = (m, os.path.relpath(p, folder))
    return best


def check_backup(folder, now, max_hours=BACKUP_MAX_HOURS):
    name = 'backup'
    if not folder or not os.path.isdir(folder):
        return fail(name, 'cannot read the backup folder %s' % (folder or '(none)'))
    best = newest_file(folder)
    if best is None:
        return fail(name, 'no backup file in %s. Run chaos-ctl.sh backup.' % folder)
    hours = (now - best[0]) / 3600.0
    if hours >= max_hours:
        return warn(name, 'the newest backup is %.1f hours old (limit %d). Run chaos-ctl.sh backup.' % (hours, max_hours))
    return ok(name, 'the newest backup is %.1f hours old.' % max(hours, 0.0))


def git_facts(repo, run):
    """{branch, commit, dirty, on_main, describe} of the checkout, or None. run(args) -> (code, stdout)."""
    g = ['git', '-C', repo, '-c', 'safe.directory=' + repo]
    code, out = run(g + ['rev-parse', '--short', 'HEAD'])
    if code != 0 or not out.strip():
        return None
    commit = out.strip()
    code, out = run(g + ['symbolic-ref', '--short', '-q', 'HEAD'])
    branch = out.strip() if code == 0 and out.strip() else ''
    code, out = run(g + ['status', '--porcelain', '--untracked-files=all'])
    if code != 0:
        return None
    dirty = len([line for line in out.splitlines() if line.strip()])
    head = run(g + ['rev-parse', 'HEAD'])[1].strip()
    on_main = branch == 'main'
    if not on_main and head:
        for ref in ('refs/heads/main', 'refs/remotes/origin/main'):
            code, out = run(g + ['rev-parse', '-q', '--verify', ref])
            if code == 0 and out.strip() == head:
                on_main = True
    code, out = run(g + ['describe', '--tags', '--always'])
    return {'branch': branch, 'commit': commit, 'dirty': dirty, 'on_main': on_main,
            'describe': out.strip() if code == 0 else commit}


def check_checkout(facts, repo=''):
    name = 'checkout'
    if facts is None:
        return fail(name, 'cannot read the git checkout %s' % (repo or '(none)'))
    where = ('branch %s' % facts['branch']) if facts['branch'] else 'detached at %s' % facts['describe']
    line = '%s, commit %s' % (where, facts['commit'])
    problems = []
    if facts['dirty']:
        problems.append('dirty (%d changed or untracked file(s))' % facts['dirty'])
    if not facts['on_main']:
        problems.append('not on main')
    if problems:
        return warn(name, '%s: %s.' % (line, ' and '.join(problems)))
    return ok(name, '%s, clean, on main.' % line)


# ------------------------------------------------------------------ the whole run
def read_text(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return None


def git_runner(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError):
        return 1, ''


def run_all(opts, facts, now, zone_info=None, runner=None):
    """Every check, in order, as a list of (status, name, text). zone_info: {'names', 'offset'} (the machine's)."""
    cfg = os.path.join(opts.server, 'data', 'scripts', 'chaos')
    launch = parse_launch(opts.launch)
    env_text = read_text(opts.env_file) if opts.env_file else None
    config_text = read_text(os.path.join(opts.server, 'config.lua'))
    res = [
        check_beta_config(read_text(os.path.join(cfg, 'beta_config.lua'))),
        check_beta_mode(read_text(os.path.join(cfg, 'beta_mode_config.lua'))),
        check_beta_cron(os.path.exists(opts.cron_file), opts.cron_file),
        check_payments(facts['pay']),
        check_test_files(opts.server),
    ]
    zone = chaos_timezone.expected_zone(env_text=env_text or '')
    if zone_info is None:
        zone_info = {'names': chaos_timezone.read_zone_names(), 'offset': chaos_timezone.local_offset(now)}
    res.append(check_timezone(zone_info['names'], zone_info['offset'], zone, chaos_timezone.expected_offset(zone, now)))
    res.append(check_max_players(config_text, opts.max_players))
    res.append(check_dates_season(read_text(os.path.join(cfg, 'season_config.lua')), launch))
    res.append(check_dates_pvp(read_text(os.path.join(cfg, 'battleground_config.lua')), launch))
    res.append(check_dates_founder(read_text(os.path.join(cfg, 'founder_config.lua')), launch))
    res.append(check_dates_creator(read_text(os.path.join(cfg, 'creator_codes_config.lua')), launch))
    key_file_ok = False
    if config_text is not None:
        kf = lua_value(strip_comments(config_text), 'clientGuardKeyFile')
        if isinstance(kf, str) and kf:
            p = kf if os.path.isabs(kf) else os.path.join(opts.server, kf)
            key_file_ok = os.path.isfile(p) and os.path.getsize(p) > 0
    res.append(check_client_guard(config_text, env_text, key_file_ok))
    res.append(check_patch_notes(opts.server, launch))
    res.append(check_database(facts['db']))
    res.append(check_backup(opts.backup_dir, now))
    res.append(check_checkout(git_facts(opts.repo, runner or git_runner) if opts.repo else None, opts.repo))
    return res


def counts(results):
    return {s: sum(1 for r in results if r[0] == s) for s in ('FAIL', 'WARN', 'OK')}


def exit_code(results):
    return 1 if any(r[0] == 'FAIL' for r in results) else 0


def summary_line(results):
    c = counts(results)
    return 'launch check: %d FAIL, %d WARN, %d OK' % (c['FAIL'], c['WARN'], c['OK'])


def report_text(results):
    lines = ['%-4s %-14s %s' % (s, n, t) for s, n, t in results]
    lines.append(summary_line(results))
    return '\n'.join(lines)


def report_json(results, launch):
    c = counts(results)
    return json.dumps({'ok': c['FAIL'] == 0, 'launch': launch, 'fail': c['FAIL'], 'warn': c['WARN'], 'okCount': c['OK'],
                       'checks': [{'status': s, 'name': n, 'text': t} for s, n, t in results]}, ensure_ascii=False)


def parse_args(argv):
    p = argparse.ArgumentParser(description='Launch check (O440): the installed server against the launch list. Read only.')
    p.add_argument('--server', required=True, help='the installed server folder (config.lua, data/)')
    p.add_argument('--env-file', default='', help='the game env file (/etc/chaos/chaos.env)')
    p.add_argument('--backup-dir', default='/var/backups/chaos')
    p.add_argument('--repo', default='', help='the checkout the server was installed from')
    p.add_argument('--cron-file', default=CRON_FILE)
    p.add_argument('--launch', default=LAUNCH, help='the launch, server local time "YYYY-MM-DD HH:MM" (default %s)' % LAUNCH)
    p.add_argument('--max-players', type=int, default=None, help='the maxPlayers the owner decided: FAIL when config.lua differs')
    p.add_argument('--json', action='store_true')
    a = p.parse_args(argv)
    try:
        parse_launch(a.launch)
    except ValueError:
        p.error('--launch must be "YYYY-MM-DD HH:MM"')
    return a


def main(argv, stdin_text=None, now=None, zone_info=None, runner=None):
    opts = parse_args(argv)
    if stdin_text is None:
        stdin_text = '' if sys.stdin is None or sys.stdin.isatty() else sys.stdin.read()
    now = time.time() if now is None else now
    results = run_all(opts, parse_facts(stdin_text), now, zone_info, runner)
    print(report_json(results, opts.launch) if opts.json else report_text(results))
    return exit_code(results)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

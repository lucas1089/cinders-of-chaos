#!/usr/bin/env python3
"""The VPS clock zone guard (O439): one place on the deploy side for the zone the game needs.

The game reads the machine's LOCAL time for the Founder Pack window, Season 1, the creator launch bonus, the weekend
ritual and the 06:00 save (weekend_config.lua, founder_config.lua, season_config.lua, creator_codes_config.lua). The
launch is at 15:00 Brasilia time, UTC-3 (the date is on hold, launch_config.lua). A machine left in UTC starts all of it 3 hours off, silently.

Expected zone: America/Sao_Paulo, UTC offset -180 minutes, or CHAOS_TIMEZONE from the environment / the env file
(/etc/chaos/chaos.env). The Lua side has its own copy in server/data/scripts/chaos/timezone_config.lua: the two must
agree (server/tools/chaos_health_test.py compares them). Used by chaos_health.py (check "timezone"), by
server/deploy/launch_check.py and by `chaos-ctl.sh timezone [set]`.

The machine's zone is read three ways, because a zone name can be read in more than one way: `timedatectl`,
/etc/timezone and the link /etc/localtime. The UTC offset now comes from the C library (time.localtime), so it is the
offset the game process gets. A zone is right when its offset is the expected one AND, when any name can be read, the
expected name is one of them.

usage: python3 -I server/tools/chaos_timezone.py status [--env-file FILE] [--zone ZONE]   key=value lines, exit 1 when WRONG
       python3 -I server/tools/chaos_timezone.py expected [--env-file FILE] [--zone ZONE]  the expected zone name only
Test hooks: CHAOS_TZ_ETC_TIMEZONE and CHAOS_TZ_LOCALTIME name other files than /etc/timezone and /etc/localtime.
"""
import argparse
import os
import re
import subprocess
import sys
import time

DEFAULT_ZONE = 'America/Sao_Paulo'
DEFAULT_OFFSET_MIN = -180     # minutes east of UTC; Brazil has had no daylight saving time since 2019
ZONE_RE = re.compile(r'^[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+){0,2}$')
FIX = 'chaos-ctl.sh timezone set, then restart the game server'


def env_file_value(text, key):
    """The last KEY=VALUE of an env file's text (quotes and a trailing comment stripped), '' when absent."""
    value = ''
    for line in (text or '').splitlines():
        m = re.match(r'^\s*(?:export\s+)?%s\s*=\s*(.*?)\s*$' % re.escape(key), line)
        if not m:
            continue
        v = m.group(1)
        q = re.match(r'^(["\'])(.*?)\1', v)
        v = q.group(2) if q else v.split('#', 1)[0].strip()
        value = v
    return value


def zone_name_ok(name):
    return bool(name) and bool(ZONE_RE.match(name)) and '..' not in name


def expected_zone(env=None, env_text=None, override=None):
    """The expected zone name: an override, else CHAOS_TIMEZONE of the environment, else of the env file, else the default.
    A value that is not a zone name is ignored (the default holds)."""
    env = os.environ if env is None else env
    for cand in (override, env.get('CHAOS_TIMEZONE'), env_file_value(env_text, 'CHAOS_TIMEZONE')):
        cand = (cand or '').strip()
        if zone_name_ok(cand):
            return cand
    return DEFAULT_ZONE


def expected_offset(zone, now=None):
    """UTC offset in minutes of `zone` now: the constant for the default zone, else from the zoneinfo database,
    None when it cannot be told (then only the name is compared)."""
    if zone == DEFAULT_ZONE:
        return DEFAULT_OFFSET_MIN
    try:
        import datetime
        import zoneinfo
        t = time.time() if now is None else now
        off = datetime.datetime.fromtimestamp(t, zoneinfo.ZoneInfo(zone)).utcoffset()
        return int(off.total_seconds() // 60) if off is not None else None
    except Exception:  # noqa: BLE001 - no zoneinfo module, no tz database, an unknown zone: name only
        return None


def local_offset(now=None):
    """The UTC offset in minutes of this process's local time at `now` (east is positive)."""
    return int(time.localtime(now).tm_gmtoff // 60)


def format_offset(minutes):
    if minutes is None:
        return 'unknown'
    sign = '-' if minutes < 0 else '+'
    m = abs(int(minutes))
    return '%s%02d:%02d' % (sign, m // 60, m % 60)


def zone_from_link(target):
    """'America/Sao_Paulo' from a /etc/localtime link target like ../usr/share/zoneinfo/America/Sao_Paulo."""
    m = re.search(r'zoneinfo/(?:posix/|right/)?(.+)$', target or '')
    name = m.group(1) if m else ''
    return name if zone_name_ok(name) else ''


def _timedatectl(run):
    out = run(['timedatectl', 'show', '-p', 'Timezone', '--value'])
    name = (out or '').strip()
    if zone_name_ok(name):
        return name
    out = run(['timedatectl', 'status'])      # older systemd: "Time zone: Etc/UTC (UTC, +0000)"
    m = re.search(r'Time zone:\s*(\S+)', out or '')
    return m.group(1) if m and zone_name_ok(m.group(1)) else ''


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def read_zone_names(run=None, etc_timezone=None, localtime=None):
    """[(source, name)] of every way the zone can be read; a source that gives nothing is left out."""
    run = run or _run
    etc_timezone = etc_timezone or os.environ.get('CHAOS_TZ_ETC_TIMEZONE') or '/etc/timezone'
    localtime = localtime or os.environ.get('CHAOS_TZ_LOCALTIME') or '/etc/localtime'
    names = []
    try:
        n = _timedatectl(run)
        if n:
            names.append(('timedatectl', n))
    except Exception:  # noqa: BLE001 - a broken helper is one source less, never a crash
        pass
    try:
        with open(etc_timezone, encoding='utf-8', errors='replace') as f:
            n = f.readline().strip()
        if zone_name_ok(n):
            names.append(('/etc/timezone', n))
    except OSError:
        pass
    try:
        n = zone_from_link(os.readlink(localtime))
        if n:
            names.append(('/etc/localtime', n))
    except OSError:
        pass
    return names


def evaluate(names, offset, zone, exp_offset):
    """The decision, from plain inputs. names: [(source, name)], offset: minutes now, zone: expected name, exp_offset:
    expected minutes or None. Returns a dict: ok, found (the zone read, first source wins, or 'unknown'), offset,
    offset_text, expected, expected_offset_text, detail."""
    found_names = [n for _, n in names]
    found = found_names[0] if found_names else 'unknown'
    offset_ok = exp_offset is None or offset == exp_offset
    name_ok = (not found_names) or zone in found_names
    ok = offset_ok and name_ok
    exp_text = format_offset(exp_offset) if exp_offset is not None else 'any'
    if ok:
        detail = 'zone %s, UTC%s' % (found, format_offset(offset))
        if not found_names:
            detail += ' (the zone name cannot be read; the offset is right)'
    else:
        why = []
        if not offset_ok:
            why.append('UTC%s, expected UTC%s' % (format_offset(offset), exp_text))
        if not name_ok:
            why.append('zone %s, expected %s' % (' / '.join(sorted(set(found_names))), zone))
        detail = 'wrong clock zone: %s. Fix: %s' % ('; '.join(why), FIX)
    return {'ok': ok, 'found': found, 'offset': offset, 'offset_text': format_offset(offset), 'expected': zone,
            'expected_offset_text': exp_text, 'detail': detail}


def health_result(info, zone, exp_offset):
    """chaos_health.py's check: ('ok' | 'fail', detail) from {'names': [...], 'offset': minutes}."""
    r = evaluate(info.get('names', []), info.get('offset'), zone, exp_offset)
    return ('ok' if r['ok'] else 'fail', r['detail'])


def status_lines(result, now):
    """The key=value lines of `chaos-ctl.sh timezone`."""
    return [
        'zone=%s' % result['found'],
        'local_time=%s' % time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(now)),
        'utc_offset=%s' % result['offset_text'],
        'expected_zone=%s' % result['expected'],
        'expected_offset=%s' % result['expected_offset_text'],
        'result=%s' % ('OK' if result['ok'] else 'WRONG'),
        'detail=%s' % result['detail'],
    ]


def read_env_text(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except (OSError, TypeError):
        return ''


def main(argv, now=None, run=None):
    p = argparse.ArgumentParser(description='The VPS clock zone guard (O439).')
    p.add_argument('command', choices=('status', 'expected'))
    p.add_argument('--env-file', default='')
    p.add_argument('--zone', default='')
    a = p.parse_args(argv)
    zone = expected_zone(env_text=read_env_text(a.env_file) if a.env_file else '', override=a.zone)
    if a.command == 'expected':
        print(zone)
        return 0
    now = time.time() if now is None else now
    result = evaluate(read_zone_names(run=run), local_offset(now), zone, expected_offset(zone, now))
    print('\n'.join(status_lines(result, now)))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Game health panel (O397, server/README.md "Game health panel (O397)"): chaos-ctl.sh game-health.

One read-only look at how the game is doing, from tables the server already fills:
  online   characters online per hour of the last N days (chaos_telemetry_online, band 'all': the mean of the 5 minute
           samples and the peak), the busiest and the quietest hour of the day
  deaths   deaths per hour (chaos_telemetry_deaths), per hour of play (deaths / character-hours online)
  hunts    the most and the least used hunts (chaos_telemetry_area, O397: hunting samples per hunt; every hunt marker of
           data/chaos_poi.lua is listed, so a hunt nobody visited shows with 0), with kills and deaths there
  economy  gold in (loot, Loot Bag sales, Auto Seller) and out (supplies, respec) of the window (chaos_telemetry_economy)
  funnel   the new player funnel of the last 30 days (server/tools/newplayer_report.py, O374): levels reached and where
           the ones who stopped stopped
No row read holds a name, an account, an id or an IP. Counts of characters of 1 to 4 are written "<5" (as O374).

  game_health.py --sql [--days N] [--now T]          the SELECT script (one mysql call, every row tagged)
  game_health.py [--kv | --json] [--pt] [--days N] [--now T] [--poi FILE] < rows
  game_health.py [--kv | --json] [--pt] --error CODE

--kv: key=value lines for the admin apps (android GameHealthInfo, desktop health::Health); --json: one JSON line; else a
text report (--pt: Brazilian Portuguese). Run with python3 -I.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import newplayer_report as npr  # noqa: E402

DEFAULT_DAYS = 7
MAX_DAYS = 90          # telemetry_config.lua hourlyDays: hourly rows older than that are daily rows
FUNNEL_DAYS = 30
TOP = 10
NAME_BYTES = 64        # telemetry_core.lua clip(): area names are cut to 64 bytes
TABLES = {'online': 'chaos_telemetry_online', 'deaths': 'chaos_telemetry_deaths', 'area': 'chaos_telemetry_area',
          'economy': 'chaos_telemetry_economy'}
MIN_SHOWN = npr.MIN_SHOWN
SMALL = npr.SMALL

SOURCES = {
    'en': {'loot': 'loot', 'lootbag': 'Loot Bag sales', 'autoseller': 'Auto Seller', 'supplies': 'supplies',
           'respec': 'respec and resets'},
    'pt': {'loot': 'loot', 'lootbag': 'vendas da Loot Bag', 'autoseller': 'Auto Seller', 'supplies': 'suprimentos',
           'respec': 'respec e resets'},
}

WORDS = {
    'en': {
        'title': 'Game health: the last %d days (server time)',
        'online': 'Online: mean %s, peak %s (%s); busiest hour %s, quietest %s',
        'online_none': 'Online: no samples yet (the telemetry writes one row per hour).',
        'deaths': 'Deaths: %d (%s per hour, %s per hour of play)',
        'hunts_top': 'Most used hunts (character-hours, hunting hours, kills, deaths):',
        'hunts_low': 'Least used hunts:',
        'hunts_none': 'No hunting samples yet (chaos_telemetry_area fills from the O397 update on).',
        'hunts_count': 'Hunts: %d known, %d without a visit in the window',
        'hunt_row': '  %-40s %5s  %7sh  %8s kills  %5s deaths',
        'economy': 'Gold: in %s, out %s, net %s',
        'economy_row': '  %-4s %-20s %14s  (%d events)',
        'in': 'in', 'out': 'out',
        'funnel': 'New players (last %d days): %s characters; reached level %s',
        'stopped': 'Stopped (no login for %d+ days): %s of %s; most at level %s, after %s',
        'error': 'Error: %s',
        'hour': '%02dh',
    },
    'pt': {
        'title': 'Saúde do jogo: últimos %d dias (hora do servidor)',
        'online': 'Online: média %s, pico %s (%s); hora mais cheia %s, mais vazia %s',
        'online_none': 'Online: ainda sem amostras (a telemetria grava uma linha por hora).',
        'deaths': 'Mortes: %d (%s por hora, %s por hora de jogo)',
        'hunts_top': 'Hunts mais usadas (personagem-horas, horas caçando, abates, mortes):',
        'hunts_low': 'Hunts menos usadas:',
        'hunts_none': 'Ainda sem amostras de caça (chaos_telemetry_area se enche a partir da atualização O397).',
        'hunts_count': 'Hunts: %d conhecidas, %d sem visita no período',
        'hunt_row': '  %-40s %5s  %7sh  %8s abates  %5s mortes',
        'economy': 'Ouro: entrou %s, saiu %s, saldo %s',
        'economy_row': '  %-6s %-20s %14s  (%d eventos)',
        'in': 'entra', 'out': 'sai',
        'funnel': 'Novos jogadores (últimos %d dias): %s personagens; chegaram ao nível %s',
        'stopped': 'Pararam (sem login há %d+ dias): %s de %s; mais no nível %s, depois de %s',
        'error': 'Erro: %s',
        'hour': '%02dh',
    },
}


def num(s, default=0):
    try:
        return int(s)
    except (TypeError, ValueError):
        return default


def check_days(days):
    days = int(days)
    if days < 1 or days > MAX_DAYS:
        raise ValueError('days must be 1 to %d' % MAX_DAYS)
    return days


def hour_of(t):
    return int(t) - int(t) % 3600


def since_of(days, now):
    return hour_of(now) - days * 24 * 3600 + 3600


def clip(name):
    b = name.encode('utf-8')[:NAME_BYTES]
    return b.decode('utf-8', 'ignore')


# ---------------------------------------------------------------- SQL
def build_sql(days, now):
    """The SELECT script. Every number comes from this file or is a checked integer; no text from outside."""
    days = check_days(days)
    since = since_of(days, int(now))
    t = TABLES
    parts = [
        "SELECT 'on', `at`, `samples`, `online_sum`, `online_max` FROM `%s` WHERE `span` = 'h' AND `band` = 'all' "
        "AND `voc` = 0 AND `at` >= %d ORDER BY `at`" % (t['online'], since),
        "SELECT 'de', `at`, SUM(`deaths`) FROM `%s` WHERE `span` = 'h' AND `at` >= %d GROUP BY `at` ORDER BY `at`"
        % (t['deaths'], since),
        "SELECT 'hu', `area`, SUM(`players`), SUM(`hunt_seconds`), SUM(`kills`) FROM `%s` WHERE `at` >= %d "
        "GROUP BY `area`" % (t['area'], since),
        "SELECT 'da', `area`, SUM(`deaths`) FROM `%s` WHERE `at` >= %d GROUP BY `area`" % (t['deaths'], since),
        "SELECT 'ec', `flow`, `source`, SUM(`gold`), SUM(`events`) FROM `%s` WHERE `at` >= %d GROUP BY `flow`, `source`"
        % (t['economy'], since),
        "SELECT 'fn', `f`.* FROM (%s) `f`" % npr.funnel_sql(FUNNEL_DAYS, now),
    ]
    return ';\n'.join(parts) + ';'


def parse(lines):
    """rows of the script by tag (mysql -N -B: tab separated, \\t \\n \\\\ escaped)"""
    out = {'on': [], 'de': [], 'hu': [], 'da': [], 'ec': [], 'fn': []}
    for line in lines:
        parts = line.rstrip('\r\n').split('\t')
        if len(parts) < 2 or parts[0] not in out:
            continue
        out[parts[0]].append([npr.unescape_mysql(p) for p in parts[1:]])
    return out


# ---------------------------------------------------------------- the report
def poi_hunts(path):
    """the hunt marker names of data/chaos_poi.lua (tools/gen_poi.py render), cut as the server cuts them"""
    if not path:
        return []
    try:
        with open(path, encoding='utf-8') as f:
            text = f.read()
    except OSError:
        return []
    names = []
    for m in re.finditer(r'\{k = "hunt",[^\n]*?\bn = "((?:[^"\\]|\\.)*)"', text):
        n = clip(m.group(1).replace('\\"', '"').replace('\\\\', '\\'))
        if n not in names:
            names.append(n)
    return names


def hide(n):
    return SMALL if 0 < n < MIN_SHOWN else n


def report(rows, days, now, hunts_known=()):
    now = int(now)
    since = since_of(days, now)
    # online: every hour of the window, None where no sample was written (server down, or the hour still running)
    on = {}
    for r in rows['on']:
        at, samples, total, peak = num(r[0]), num(r[1]), num(r[2]), num(r[3])
        if samples > 0:
            on[at] = (total / float(samples), peak)
    hours = []
    t = since
    while t <= hour_of(now):
        lt = time.localtime(t)
        v = on.get(t)
        hours.append({'at': t, 'day': time.strftime('%d/%m', lt), 'hour': lt.tm_hour,
                      'avg': round(v[0], 1) if v else None, 'max': v[1] if v else None})
        t += 3600
    seen = [h for h in hours if h['avg'] is not None]
    by_hour = {}
    for h in seen:
        by_hour.setdefault(h['hour'], []).append(h['avg'])
    hod = {k: sum(v) / len(v) for k, v in by_hour.items()}
    peak = max(seen, key=lambda h: (h['max'], h['at'])) if seen else None
    online = {
        'hours': hours,
        'sampledHours': len(seen),
        'mean': round(sum(h['avg'] for h in seen) / len(seen), 1) if seen else None,
        'peak': peak['max'] if peak else None,
        'peakAt': peak['at'] if peak else None,
        'busiestHour': max(hod, key=lambda k: (hod[k], -k)) if hod else None,
        'quietestHour': min(hod, key=lambda k: (hod[k], k)) if hod else None,
    }
    # deaths per hour
    de = {num(r[0]): num(r[1]) for r in rows['de']}
    death_hours = [{'at': h['at'], 'deaths': de.get(h['at'], 0)} for h in hours]
    dtotal = sum(de.get(h['at'], 0) for h in hours)
    char_hours = sum(h['avg'] for h in seen)
    deaths = {
        'hours': death_hours, 'total': dtotal,
        'perHour': round(dtotal / float(len(seen)), 2) if seen else None,
        'perPlayHour': round(dtotal / char_hours, 3) if char_hours > 0 else None,
    }
    # hunts: the markers (0 visits) and every area with samples; deaths by area name
    area_deaths = {}
    for r in rows['da']:
        if len(r) >= 2:
            area_deaths[r[0]] = area_deaths.get(r[0], 0) + num(r[1])
    hunts = {}
    for name in hunts_known:
        hunts[name] = {'name': name, 'visits': 0, 'seconds': 0, 'kills': 0}
    for r in rows['hu']:
        if len(r) < 4:
            continue
        h = hunts.setdefault(r[0], {'name': r[0], 'visits': 0, 'seconds': 0, 'kills': 0})
        h['visits'] += num(r[1])
        h['seconds'] += num(r[2])
        h['kills'] += num(r[3])
    hlist = []
    for h in hunts.values():
        hlist.append({'name': h['name'], 'visits': hide(h['visits']), 'hours': round(h['seconds'] / 3600.0, 1),
                      'kills': h['kills'], 'deaths': area_deaths.get(h['name'], 0), '_s': h['seconds']})
    hlist.sort(key=lambda x: (-x['_s'], x['name']))
    top = [x for x in hlist if x['_s'] > 0][:TOP]
    # the least used: the other end of the list, never a hunt already in the top list
    low = [x for x in sorted(hlist, key=lambda x: (x['_s'], x['name'])) if x not in top][:TOP]
    for x in hlist:
        x.pop('_s', None)
    hunt = {'known': len(hlist), 'unvisited': sum(1 for x in hlist if x['hours'] == 0 and x['visits'] == 0),
            'top': top, 'low': low}
    # economy
    eco = []
    gin = gout = 0
    for r in rows['ec']:
        if len(r) < 4:
            continue
        flow, gold, events = r[0], num(r[2]), num(r[3])
        if flow not in ('faucet', 'sink'):
            continue
        eco.append({'flow': flow, 'source': r[1], 'gold': gold, 'events': events})
        if flow == 'faucet':
            gin += gold
        else:
            gout += gold
    eco.sort(key=lambda e: (e['flow'], -e['gold'], e['source']))
    economy = {'in': gin, 'out': gout, 'net': gin - gout, 'rows': eco}
    # the new player funnel (O374)
    frows = npr.parse_funnel(['\t'.join(r) for r in rows['fn']])
    funnel = npr.funnel(frows, FUNNEL_DAYS)
    return {'ok': True, 'days': days, 'since': since, 'now': now, 'online': online, 'deaths': deaths, 'hunts': hunt,
            'economy': economy, 'funnel': funnel}


# ---------------------------------------------------------------- output
def n_or(v, fmt='%s'):
    return '-' if v is None else fmt % v


def gold(v):
    s = '{:,}'.format(int(v))
    return s


def top_of(items, key):
    best = None
    for x in items:
        c = x['characters']
        c = c if isinstance(c, int) else 0
        if c > 0 and (best is None or c > best[1]):
            best = (x[key], c)
    return best[0] if best else '-'


def funnel_reached(f):
    return ', '.join('%s: %s%s' % (r['level'], r['characters'], npr.share(r['pct'])) for r in f['reached'])


def kv(res, lang):
    out = []
    if not res.get('ok'):
        return 'ok=0\nerror=%s' % res.get('error', 'error')
    names = SOURCES[lang]
    o, d, h, e, f = res['online'], res['deaths'], res['hunts'], res['economy'], res['funnel']
    out += ['ok=1', 'days=%d' % res['days'], 'now=%d' % res['now'], 'since=%d' % res['since'],
            'online_mean=%s' % n_or(o['mean']), 'online_peak=%s' % n_or(o['peak']),
            'online_peak_at=%s' % (time.strftime('%d/%m %Hh', time.localtime(o['peakAt'])) if o['peakAt'] else '-'),
            'online_busiest_hour=%s' % n_or(o['busiestHour']), 'online_quietest_hour=%s' % n_or(o['quietestHour']),
            'online_sampled_hours=%d' % o['sampledHours'],
            'deaths_total=%d' % d['total'], 'deaths_per_hour=%s' % n_or(d['perHour']),
            'deaths_per_play_hour=%s' % n_or(d['perPlayHour'])]
    # one line per hour: EPOCH DD/MM HH MEAN PEAK DEATHS ("-" for an hour without a sample)
    for hr, dh in zip(o['hours'], d['hours']):
        out.append('hour=%d %s %d %s %s %d' % (hr['at'], hr['day'], hr['hour'], n_or(hr['avg']), n_or(hr['max']),
                                              dh['deaths']))
    out += ['hunts_known=%d' % h['known'], 'hunts_unvisited=%d' % h['unvisited']]
    for k in ('top', 'low'):
        for x in h[k]:
            out.append('hunt_%s=%s %s %d %d %s' % (k, x['visits'], x['hours'], x['kills'], x['deaths'], x['name']))
    out += ['gold_in=%d' % e['in'], 'gold_out=%d' % e['out'], 'gold_net=%d' % e['net']]
    for x in e['rows']:
        out.append('gold=%s %d %d %s' % (x['flow'], x['gold'], x['events'], names.get(x['source'], x['source'])))
    out += ['funnel_days=%d' % f['days'], 'funnel_characters=%s' % f['characters']]
    for r in f['reached']:
        out.append('funnel_reached=%d %s %s' % (r['level'], r['characters'], n_or(r['pct'])))
    s = f['stopped']
    out.append('funnel_stopped=%s %s %s' % (s['characters'], s['eligible'], n_or(s['pct'])))
    for r in f['stopLevel']:
        out.append('funnel_stop_level=%s %s %s' % (r['characters'], n_or(r['pct']), r['band']))
    sysnames = npr.SYSTEM_NAMES[lang]
    for r in f['stopSystem']:
        out.append('funnel_stop_system=%s %s %s' % (r['characters'], n_or(r['pct']),
                                                     sysnames.get(r['system'], r['system'])))
    return '\n'.join(out)


def text(res, lang):
    w = WORDS[lang]
    if not res.get('ok'):
        return w['error'] % res.get('error', 'error')
    o, d, h, e, f = res['online'], res['deaths'], res['hunts'], res['economy'], res['funnel']
    out = [w['title'] % res['days'], '']
    if o['mean'] is None:
        out.append(w['online_none'])
    else:
        out.append(w['online'] % (o['mean'], o['peak'], time.strftime('%d/%m %Hh', time.localtime(o['peakAt'])),
                                  w['hour'] % o['busiestHour'], w['hour'] % o['quietestHour']))
    out.append(w['deaths'] % (d['total'], n_or(d['perHour']), n_or(d['perPlayHour'])))
    out.append('')
    out.append(w['hunts_count'] % (h['known'], h['unvisited']))
    if not h['top']:
        out.append(w['hunts_none'])
    else:
        out.append(w['hunts_top'])
        for x in h['top']:
            out.append(w['hunt_row'] % (x['name'][:40], x['visits'], x['hours'], x['kills'], x['deaths']))
    if h['low']:
        out.append(w['hunts_low'])
        for x in h['low']:
            out.append(w['hunt_row'] % (x['name'][:40], x['visits'], x['hours'], x['kills'], x['deaths']))
    out.append('')
    out.append(w['economy'] % (gold(e['in']), gold(e['out']), gold(e['net'])))
    names = SOURCES[lang]
    for x in e['rows']:
        out.append(w['economy_row'] % (w['in'] if x['flow'] == 'faucet' else w['out'],
                                       names.get(x['source'], x['source']), gold(x['gold']), x['events']))
    out.append('')
    out.append(w['funnel'] % (f['days'], f['characters'], funnel_reached(f)))
    s = f['stopped']
    sysnames = npr.SYSTEM_NAMES[lang]
    sys_top = top_of(f['stopSystem'], 'system')
    out.append(w['stopped'] % (f['stopDays'], s['characters'], s['eligible'], top_of(f['stopLevel'], 'band'),
                               sysnames.get(sys_top, sys_top)))
    return '\n'.join(out)


# ---------------------------------------------------------------- main
def main(argv):
    mode = 'text'
    lang = 'en'
    want_sql = False
    days, now, err, poi = DEFAULT_DAYS, int(time.time()), None, None
    i = 0
    try:
        while i < len(argv):
            a = argv[i]
            if a in ('--json', '--kv'):
                mode = a[2:]
            elif a == '--pt':
                lang = 'pt'
            elif a == '--sql':
                want_sql = True
            elif a in ('--days', '--now', '--error', '--poi') and i + 1 < len(argv):
                i += 1
                if a == '--days':
                    days = check_days(argv[i])
                elif a == '--now':
                    now = int(argv[i])
                elif a == '--poi':
                    poi = argv[i]
                else:
                    err = ''.join(c for c in argv[i] if c.isalnum() or c in '-_')[:32] or 'error'
            else:
                raise ValueError('unknown argument ' + a)
            i += 1
    except ValueError as e:
        sys.stderr.write('game_health: %s\n' % e)
        return 2
    if want_sql:
        print(build_sql(days, now))
        return 0
    if err:
        res = {'ok': False, 'error': err}
    else:
        res = report(parse(sys.stdin.read().splitlines()), days, now, poi_hunts(poi))
    if mode == 'json':
        print(json.dumps(res, ensure_ascii=False))
    elif mode == 'kv':
        print(kv(res, lang))
    else:
        print(text(res, lang))
    return 0 if res.get('ok') else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

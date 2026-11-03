#!/usr/bin/env python3
"""Tests of game_health.py (O397) on synthetic rows: the SELECT script, online per hour, deaths, hunts (with the
markers nobody visited), economy, the funnel, the small groups rule, the key=value lines the admin apps read.
  python3 -I server/tools/game_health_test.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import game_health as gh  # noqa: E402

failures = 0


def check(ok, what):
    global failures
    if not ok:
        failures += 1
        print('FAIL', what)


NOW = 1791000000 + 1800          # half past an hour
H = gh.hour_of(NOW)


def rows():
    r = []
    # online: three sampled hours, one hour missing (server down)
    r.append('on\t%d\t12\t120\t14' % (H - 3 * 3600))
    r.append('on\t%d\t12\t240\t25' % (H - 2 * 3600))
    r.append('on\t%d\t6\t30\t6' % H)
    r.append('on\t%d\t0\t0\t0' % (H - 3600))          # no samples: ignored
    r.append('de\t%d\t4' % (H - 3 * 3600))
    r.append('de\t%d\t6' % (H - 2 * 3600))
    r.append('de\t%d\t99' % (H - 30 * 24 * 3600))     # outside the window: ignored
    r.append('hu\tAshen Caves\t40\t36000\t900')
    r.append('hu\tRift\t3\t1200\t50')
    r.append('hu\tFrost\\tHold\t10\t7200\t300')       # an escaped tab in a name
    r.append('da\tAshen Caves\t7')
    r.append('da\tnear Cinderhold\t2')
    r.append('ec\tfaucet\tloot\t500000\t300')
    r.append('ec\tsink\tsupplies\t120000\t280')
    r.append('ec\tfaucet\tlootbag\t20000\t4')
    r.append('ec\tbogus\tx\t1\t1')
    r.append('fn\t0\t0\t1\t1\t1\t1\t0\t40')
    r.append('fn\t2\t1\t1\t1\t5\t4\t2\t8')
    r.append('fn\t3\t2\t0\t1\t0\t0\t0\t12')
    r.append('zz\tnot a tag')
    return r


def main():
    sql = gh.build_sql(7, NOW)
    since = gh.since_of(7, NOW)
    check(sql.count(';') == 6, 'six statements: ' + sql[:200])
    for tag in ("'on'", "'de'", "'hu'", "'da'", "'ec'", "'fn'"):
        check(tag in sql, 'tag %s in the script' % tag)
    check('`at` >= %d' % since in sql, 'the window start')
    check('chaos_telemetry_area' in sql and 'GROUP BY `reach`' in sql, 'hunts and the O374 funnel')
    for word in ('`name`', 'account', 'lastip', 'email'):
        check(word not in sql, 'the script never reads ' + word)
    for bad in (0, 91, 'x'):
        try:
            gh.build_sql(bad, NOW)
            check(False, 'days %r refused' % (bad,))
        except ValueError:
            pass

    with tempfile.TemporaryDirectory() as tmp:
        poi = os.path.join(tmp, 'chaos_poi.lua')
        with open(poi, 'w') as f:
            f.write('return {version = "x", marks = {\n'
                    '\t\t{k = "temple", x = 1, y = 1, z = 7, n = "Temple of Cinderhold", r = 0},\n'
                    '\t\t{k = "hunt", x = 2, y = 2, z = 8, n = "Ashen Caves", r = 1},\n'
                    '\t\t{k = "hunt", x = 3, y = 3, z = 8, n = "Bone Pits", r = 1},\n'
                    '\t\t{k = "hunt", x = 4, y = 4, z = 8, n = "' + 'L' * 80 + '", r = 1},\n'
                    '}}\n')
        known = gh.poi_hunts(poi)
        check(known == ['Ashen Caves', 'Bone Pits', 'L' * 64], 'hunt markers, cut to 64 bytes: %r' % known)
        check(gh.poi_hunts(os.path.join(tmp, 'missing.lua')) == [], 'no marker file: no list')

        res = gh.report(gh.parse(rows()), 7, NOW, known)
        o = res['online']
        check(len(o['hours']) == 7 * 24, 'every hour of the window: %d' % len(o['hours']))
        check(o['sampledHours'] == 3 and o['mean'] == round((10 + 20 + 5) / 3.0, 1), 'mean of the sampled hours: %r' % o)
        check(o['peak'] == 25 and o['peakAt'] == H - 2 * 3600, 'the peak and its hour')
        check(o['hours'][-2]['avg'] is None, 'an hour without samples stays empty')
        d = res['deaths']
        check(d['total'] == 10 and d['perHour'] == round(10 / 3.0, 2), 'deaths in the window only: %r' % d['total'])
        check(d['perPlayHour'] == round(10 / 35.0, 3), 'deaths per character-hour online')
        h = res['hunts']
        names = [x['name'] for x in h['top']]
        check(names == ['Ashen Caves', 'Frost Hold', 'Rift'], 'most used by hunting time: %r' % names)
        check(h['top'][0]['hours'] == 10.0 and h['top'][0]['deaths'] == 7 and h['top'][0]['kills'] == 900, 'hunt row')
        check(h['top'][2]['visits'] == '<5', 'small groups: 3 character-hours are "<5"')
        low = [x['name'] for x in h['low']]
        check(low == ['Bone Pits', 'L' * 64], 'least used: the markers nobody visited, not the top ones: %r' % low)
        check(h['known'] == 5 and h['unvisited'] == 2, 'hunts known and unvisited: %r' % h)
        e = res['economy']
        check(e['in'] == 520000 and e['out'] == 120000 and e['net'] == 400000 and len(e['rows']) == 3, 'economy')
        f = res['funnel']
        check(f['characters'] == 60 and f['days'] == 30, 'the O374 funnel inside')

        kv = gh.kv(res, 'pt')
        lines = kv.splitlines()
        check(lines[0] == 'ok=1' and 'days=7' in lines, 'kv head')
        check(sum(1 for x in lines if x.startswith('hour=')) == 7 * 24, 'one hour line per hour')
        check('hour=%d ' % (H - 3600) in kv and any(x.startswith('hour=%d ' % (H - 3600)) and ' - - ' in x
                                                    for x in lines), 'an empty hour: "-"')
        check('hunt_top=<5 0.3 50 0 Rift' in lines, 'hunt line, name last: %r' % [x for x in lines if 'Rift' in x])
        check('gold=faucet 20000 4 vendas da Loot Bag' in lines, 'gold line in Portuguese')
        check('funnel_characters=60' in lines and any(x.startswith('funnel_stop_system=') for x in lines), 'funnel lines')
        for x in lines:
            check('=' in x and '\t' not in x, 'a plain key=value line: %r' % x)
        txt = gh.text(res, 'pt')
        check(txt.startswith('Saúde do jogo: últimos 7 dias') and 'Hunts mais usadas' in txt, 'text in Portuguese')
        check('Ashen Caves' in gh.text(res, 'en'), 'text in English')

        empty = gh.report(gh.parse([]), 1, NOW, [])
        check(empty['online']['mean'] is None and empty['hunts']['top'] == [] and empty['funnel']['characters'] == 0,
              'no rows: empty report')
        check('ainda sem amostras' in gh.text(empty, 'pt').lower(), 'no rows: a sentence, no crash')
        check(gh.kv(empty, 'en').startswith('ok=1'), 'no rows: kv')

        script = os.path.join(HERE, 'game_health.py')
        r = subprocess.run([sys.executable, '-I', script, '--kv', '--days', '7', '--now', str(NOW), '--poi', poi],
                           input='\n'.join(rows()) + '\n', capture_output=True, text=True)
        check(r.returncode == 0 and 'hunt_low=0 0.0 0 0 Bone Pits' in r.stdout, 'command line --kv: ' + r.stderr)
        r = subprocess.run([sys.executable, '-I', script, '--json', '--error', 'no-table'], capture_output=True, text=True)
        check(r.returncode == 1 and json.loads(r.stdout) == {'ok': False, 'error': 'no-table'}, 'error JSON')
        r = subprocess.run([sys.executable, '-I', script, '--kv', '--error', 'no;table'], capture_output=True, text=True)
        check(r.stdout.strip() == 'ok=0\nerror=notable', 'error kv, cleaned: %r' % r.stdout)
        r = subprocess.run([sys.executable, '-I', script, '--sql', '--days', '91'], capture_output=True, text=True)
        check(r.returncode == 2, 'days over 90 refused')
    print('game_health_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

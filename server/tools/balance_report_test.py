#!/usr/bin/env python3
"""Tests of balance_report.py (O398) on synthetic data: minutes per level from experience per hunting second, medians
per band, the flags and their suggested change, the small groups rule, season windows with the /season overrides, the
due check of the timer, the saved files.
  python3 -I server/tools/balance_report_test.py
"""
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import balance_report as br  # noqa: E402

failures = 0


def check(ok, what):
    global failures
    if not ok:
        failures += 1
        print('FAIL', what)


CFG = br.load_config()
SEASONS = '''return {
	tables = {players = "x"},
	seasons = {
		{
			id = 1,
			name = "Season of Ash",
			tag = "[S1]",
			start = 20261120,
			finish = 20270219,
			hour = 15,
			modifier = {name = "Ashfall", expMult = 1.10}
		},
		{
			id = 2,
			name = "Season Two",
			tag = "[S2]",
			start = 20270220,
			finish = 20270521,
			hour = 15
		}
	},
	join = {maxLevel = 7}
}
'''


def hunt_row(band, voc, char_hours, hours, exp_per_min, kills=100):
    secs = int(hours * 3600)
    return 'hu\t%s\t%d\t%d\t%d\t%d\t%d' % (band, voc, char_hours, secs, int(exp_per_min * secs / 60), kills)


def rows():
    level = CFG['bandLevel']['300-499']
    need = br.exp_to_next(level)
    # exp per minute so that minutes per level is 30 (median), 45 (slow), 20 (fast), 31, 29
    r = [hunt_row('300-499', 1, 40, 10, need / 30.0), hunt_row('300-499', 3, 40, 10, need / 45.0),
         hunt_row('300-499', 4, 40, 10, need / 20.0), hunt_row('300-499', 5, 40, 10, need / 31.0),
         hunt_row('300-499', 7, 40, 10, need / 29.0),
         hunt_row('300-499', 8, 3, 9, need / 90.0),       # 3 character-hours: "<5", never compared
         hunt_row('300-499', 10, 20, 2, need / 90.0),     # 2 hunting hours: below minHuntHours
         hunt_row('1-99', 1, 10, 6, 100.0), hunt_row('1-99', 3, 10, 6, 100.0)]  # 2 classes: no median
    r += ['cl\t300-499\t1\t5\t1000000', 'cl\t300-499\t3\t5\t1000000', 'cl\t300-499\t4\t5\t1000000',
          'cl\t300-499\t5\t20\t600000', 'cl\t300-499\t7\t4\t1050000', 'cl\t300-499\t8\t9\t1']
    r += ['ca\t3\tArrow Rain\t900', 'ca\t3\tPiercing Shot\t1200', 'ca\t3\tHaste\t50', 'ca\t3\tQuick Draw\t300',
          'ca\t1\tFlame Burst\t10', 'xx\tignored']
    return r


def main():
    check(br.exp_to_next(1) == 100 and br.exp_to_next(100) == 485200, 'the engine curve')
    sql = br.build_sql(1000, 2000)
    check(sql.count(';') == 3 and '`at` >= 1000 AND `at` < 2000' in sql, 'three statements, the window')
    check('chaos_telemetry_class' in sql and 'chaos_telemetry_casts' in sql, 'class and casts tables')
    for word in ('`name`', 'account', 'player_id'):
        check(word not in sql, 'the script never reads ' + word)
    for bad in ((2000, 1000), (-1, 5)):
        try:
            br.build_sql(*bad)
            check(False, 'window %r refused' % (bad,))
        except ValueError:
            pass

    cells, casts = br.parse_rows(rows())
    a = br.analyse(cells, casts, CFG)
    bands = [b['band'] for b in a['bands']]
    check(bands == ['1-99', '300-499'], 'bands in level order: %r' % bands)
    b = a['bands'][1]
    check(b['median']['minutesPerLevel'] == 30.0, 'median of the compared classes: %r' % b['median'])
    by = {r['voc']: r for r in b['classes']}
    check(by[3]['minutesPerLevel'] == 45.0 and by[4]['minutesPerLevel'] == 20.0, 'minutes per level')
    check(by[8]['charHours'] == '<5' and not by[8]['compared'], 'small groups: "<5", not compared')
    check(not by[10]['compared'] and by[10]['charHours'] == 20, 'too few hunting hours: not compared')
    check(by[5]['deathsPerHour'] == 2.0 and by[1]['deathsPerHour'] == 0.5, 'deaths per hunting hour')
    check(by[1]['damageShare'] == round(100 * 1000000 / 4650000.0, 1), 'damage share of the compared classes')
    check(a['bands'][0]['median']['minutesPerLevel'] is None, 'two classes: no median, nothing flagged')
    check([s['spell'] for s in a['spells'][3]] == ['Piercing Shot', 'Arrow Rain', 'Quick Draw'], 'top 3 spells')

    fl = br.flags(a, CFG)
    kinds = {(f['kind'], f['voc']) for f in fl}
    check(('slow', 3) in kinds and ('fast', 4) in kinds, 'slow and fast classes: %r' % kinds)
    check(('deaths', 5) in kinds and ('damage_low', 5) in kinds, 'dies often, low damage: %r' % kinds)
    check(not any(v in (1, 7, 8, 10) for _, v in kinds), 'classes inside the thresholds or not compared: no flag')
    slow = [f for f in fl if f['kind'] == 'slow'][0]
    check(slow['gapPct'] == 50 and slow['suggestPct'] == 15, 'gap 50%%: suggestion capped at 15%%: %r' % slow)
    fast = [f for f in fl if f['kind'] == 'fast'][0]
    check(fast['gapPct'] == 33 and fast['suggestPct'] == 15, 'fast: %r' % fast)
    check(fl[0]['gapPct'] >= fl[-1]['gapPct'], 'largest gaps first')
    check(br.suggested(1.2, CFG) == 10 and br.suggested(1.01, CFG) == 1, 'half the gap, at least 1%')

    vocs = br.vocations('1:Mystic,3:Ranger,4:Warrior,5:Elementalist,7:Deadeye,19:Iron Sage,x:Bad,9:')
    check(vocs == {1: 'Mystic', 3: 'Ranger', 4: 'Warrior', 5: 'Elementalist', 7: 'Deadeye', 19: 'Iron Sage'}, 'vocations')
    res = br.build(cells, casts, CFG, 1790000000, 1792592000, 'Season of Ash [S1]', vocs)
    pt = br.text(res, 'pt')
    check(pt.startswith('# Relatório de equilíbrio: Season of Ash [S1]'), 'title in Portuguese')
    check('Ranger, nível 300-499: sobe de nível 50% mais devagar que a mediana (45,0 contra 30,0 min por nível). '
          'Sugestão: cerca de +15% de dano ou experiência.' in pt, 'a suggestion in Portuguese:\n' + pt)
    check('classe 8' in pt and 'fora da comparação' in pt, 'an unknown id and a class out of the comparison')
    check('Ranger: Piercing Shot (1200), Arrow Rain (900), Quick Draw (300)' in pt, 'most used spells')
    check('—' not in pt and '—' not in br.text(res, 'en'), 'no em-dash in the text')
    en = br.text(res, 'en')
    check('Warrior, level 300-499: levels 33% faster than the median' in en, 'a suggestion in English')
    empty = br.build({}, {}, CFG, 1, 2, 'x', {})
    check('Ainda não há dados suficientes' in br.text(empty, 'pt'), 'no data: a sentence')

    with tempfile.TemporaryDirectory() as tmp:
        sfile = os.path.join(tmp, 'season_config.lua')
        with open(sfile, 'w') as f:
            f.write(SEASONS)
        seasons = br.read_seasons(sfile)
        check([s['id'] for s in seasons] == [1, 2] and seasons[0]['name'] == 'Season of Ash', 'seasons read')
        start1 = int(time.mktime((2026, 11, 20, 15, 0, 0, 0, 0, -1)))
        check(seasons[0]['start'] == start1, 'YYYYMMDD at the hour, server local time')
        # the launch date is open (O463): the shipped season config has no start and no finish (it reads the one launch value);
        # the season is not a window, and a /season start override gives it lengthDays
        ofile = os.path.join(tmp, 'season_open.lua')
        with open(ofile, 'w') as f:
            f.write('local LC = dofile("data/scripts/chaos/launch_core.lua")\nreturn {seasons = {{id = 1, name = "Season of Ash", tag = "[S1]",\n'
                    '\t\topen = LC.isOpen() or nil, start = LC.ymd(0), finish = LC.ymd(91), lengthDays = 91, hour = LC.hour()}}}\n')
        oseasons = br.read_seasons(ofile)
        check(len(oseasons) == 1 and oseasons[0]['start'] is None and oseasons[0]['finish'] is None and oseasons[0]['length'] == 91,
              'open: no dates, lengthDays read: ' + repr(oseasons))
        owins = br.parse_windows(['sw\t1\t0\t0'], oseasons)
        check(br.pick_season(owins, 'current', 4102444800) is None and br.due(owins, 4102444800, tmp, 30) == [],
              'open: no window, nothing due')
        owins = br.parse_windows(['sw\t1\t1800000000\t0'], oseasons)
        check(owins[0]['finish'] == 1800000000 + 91 * 86400 and br.pick_season(owins, 'current', 1800000000 + 86400)['id'] == 1,
              'open: a season started by hand runs lengthDays')
        wsql = br.windows_sql(seasons)
        check("`config` = 'chaos_season_1_end'" in wsql and 'UNION ALL' in wsql, 'the overrides in the windows query')
        early_end = start1 + 30 * 86400
        lines = ['sw\t1\t%d\t%d' % (start1, early_end), 'sw\t2\t%d\t%d' % (seasons[1]['start'], seasons[1]['finish'])]
        wins = br.parse_windows(lines, seasons)
        check(wins[0]['finish'] == early_end, '/season end wins over the file')
        now = early_end + 3 * 86400
        check(br.pick_season(wins, 'current', now)['id'] == 1, 'current: the last one that started')
        check(br.pick_season(wins, '2', now)['id'] == 2 and br.pick_season(wins, '9', now) is None, 'by id')
        saved = os.path.join(tmp, 'saved')
        os.makedirs(saved)
        check(br.due(wins, now, saved, CFG['autoDays']) == [1], 'an ended season with no report is due')
        check(br.due(wins, early_end + 20 * 86400, saved, CFG['autoDays']) == [], 'too long ago: not due')
        check(br.due(wins, early_end - 60, saved, CFG['autoDays']) == [], 'still running: not due')
        path = br.save(res, 'pt', saved, 'season-1', CFG['keep'])
        check(os.path.exists(path) and os.path.exists(os.path.join(saved, 'season-1.json')), 'saved .md and .json')
        check(open(os.path.join(saved, 'latest.md')).read().startswith('# Relatório'), 'latest.md')
        check(br.due(wins, now, saved, CFG['autoDays']) == [], 'a saved season is not due again')
        for k in range(CFG['keep'] + 3):
            br.save(res, 'en', saved, 'balance-20270101-%06d' % k, CFG['keep'])
        kept = [f for f in os.listdir(saved) if f.startswith('balance-') and f.endswith('.md')]
        check(len(kept) == CFG['keep'] and 'balance-20270101-000000.md' not in kept, 'the newest %d kept' % CFG['keep'])
        try:
            br.save(res, 'en', saved, '../x', 5)
            check(False, 'a bad name is refused')
        except ValueError:
            pass

        script = os.path.join(HERE, 'balance_report.py')

        def run(*args, stdin=''):
            return subprocess.run([sys.executable, '-I', script] + list(args), input=stdin, capture_output=True, text=True)
        r = run('window', '--season', 'current', '--seasons', sfile, '--now', str(now), stdin='\n'.join(lines))
        check(r.returncode == 0 and r.stdout.split()[:3] == [str(start1), str(early_end), '1'] and 'Season of Ash' in r.stdout,
              'window: ' + r.stdout + r.stderr)
        r = run('window', '--season', '2', '--seasons', sfile, '--now', str(now), stdin='\n'.join(lines))
        check(r.returncode == 3, 'a season that has not started: exit 3')
        r = run('due', '--seasons', sfile, '--dir', os.path.join(tmp, 'none'), '--now', str(now), stdin='\n'.join(lines))
        check(r.stdout.strip() == '1', 'due on the command line: ' + r.stdout + r.stderr)
        r = run('report', '--since', '1790000000', '--until', '1792592000', '--pt', '--vocations', '3:Ranger',
                '--title', 'Teste; rm -rf', stdin='\n'.join(rows()))
        check(r.returncode == 0 and r.stdout.startswith('# Relatório de equilíbrio: Teste rm -rf'), 'report: ' + r.stderr)
        r = run('report', '--since', '1790000000', '--until', '1792592000', '--json', stdin='\n'.join(rows()))
        d = json.loads(r.stdout or '{}')
        check(d.get('ok') and len(d.get('flags', [])) >= 4, 'report --json')
        r = run('report', '--json', '--error', 'no-table')
        check(r.returncode == 1 and json.loads(r.stdout) == {'ok': False, 'error': 'no-table'}, 'error JSON')
        r = run('report', '--since', '5', '--until', '5')
        check(r.returncode == 2, 'an empty window is refused')
        r = run('sql', '--since', '1', '--until', 'x')
        check(r.returncode == 2, 'a window that is no number is refused')
    print('balance_report_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

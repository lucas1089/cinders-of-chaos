#!/usr/bin/env python3
"""Tests for server/tools/progress_metrics.py (server/README.md "Progress metrics (O253)"): parsing, bands in level
order, churn shares, top 10 with ties, the median read from time buckets (interpolation, open bucket, empty), the first
session buckets, the text and JSON output, the error answer. All rows are synthetic.

usage: python3 -I server/tools/progress_metrics_test.py
"""
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import progress_metrics as pm  # noqa: E402

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


def main():
    check(pm.parse(['a\tb\tc\t5\n', 'bad\n', 'x\ty\tz\tnope\n']) == [('a', 'b', 'c', 5), ('x', 'y', 'z', 0)], 'parse')
    check(pm.band_start('1-5') == 1 and pm.band_start('901+') == 901 and pm.band_start('?') > 10 ** 6, 'band_start')
    check(pm.bucket_limit('45') == 45 and pm.bucket_limit('inf') is None, 'bucket_limit')

    # median: 10 characters in 0-10 and 10 in 10-20 -> the edge, 10
    check(pm.median([(10, 10), (20, 10)]) == (10.0, 20), 'median at a bucket edge')
    check(pm.median([(10, 0), (20, 10)]) == (15.0, 10), 'median inside the second bucket')
    check(pm.median([(60, 3), (30, 1)]) == (40.0, 4), 'buckets in any order: the median lies in 30-60')
    check(pm.median([(30, 1), (None, 3)]) == (30.0, 4), 'the open bucket gives its lower limit')
    check(pm.median([]) == (None, 0), 'empty')
    check(pm.median([(10, 0)]) == (None, 0), 'zero counts')
    check(pm.median([(10, 1)]) == (5.0, 1), 'one character')

    rows = [('churn', b, k, n) for b, k, n in (('11-15', 'gone', 2), ('11-15', 'active', 6), ('1-5', 'gone', 3), ('1-5', 'active', 1),
                                              ('901+', 'gone', 1), ('901+', 'active', 0), ('6-10', 'gone', 0), ('6-10', 'active', 0))]
    rows += [('meta', 'churn_days', '', 14), ('meta', 'churn_at', '', 1700000000)]
    for i in range(12):
        rows.append(('death_area', 'Area %02d' % i, '1-5', 12 - i))
    rows += [('death_area', 'Area 11', '6-10', 5), ('death_area', 'Tie A', '1-5', 1), ('death_area', 'Tie B', '1-5', 1)]
    rows += [('death_monster', 'Rat', '1-5', 3), ('death_monster', 'Rat', '6-10', 3), ('death_monster', 'Bat', '6-10', 0)]
    rows += [('session1', '10', '', 4), ('session1', '5', '', 1), ('session1', 'inf', '', 5)]
    rows += [('ttl', '25', '30', 2), ('ttl', '10', '5', 2), ('ttl', '10', '10', 2)]
    pm.MIN_SHOWN = 1  # the fixture is small; suppression has its own checks below
    rep = pm.report(rows)
    pm.MIN_SHOWN = 5
    check(rep['ok'] and not rep['empty'], 'ok')
    check([b['band'] for b in rep['churn']['bands']] == ['1-5', '6-10', '11-15', '901+'], 'bands in level order')
    check(rep['churn']['bands'][0]['gonePct'] == 75.0 and rep['churn']['bands'][1]['gonePct'] == 0.0
          and rep['churn']['bands'][2]['gonePct'] == 25.0, 'gone shares, an empty band is 0')
    check(rep['churn']['gone'] == 6 and rep['churn']['active'] == 7 and rep['churn']['days'] == 14
          and rep['churn']['at'] == 1700000000, 'churn totals and meta')
    names = [e['name'] for e in rep['deathAreas']]
    check(len(names) == 10 and names[0] == 'Area 00' and 'Tie A' not in names, 'top 10 areas: %r' % (names,))
    a11 = [e for e in rep['deathAreas'] if e['name'] == 'Area 11']
    check(a11 and a11[0]['deaths'] == 6 and a11[0]['topBand'] == '6-10', 'area totals over bands')
    check(len(pm.report(rows, 3)['deathAreas']) == 3, '--top')
    mon = rep['deathMonsters']
    check(len(mon) == 1 and mon[0]['deaths'] == 6 and mon[0]['topBand'] == '1-5', 'a tie of bands goes to the lower band; zero rows dropped: %r' % (mon,))
    check([e['bucket'] for e in rep['firstSession']] == ['5', '10', 'inf'], 'first session buckets in order')
    check(rep['firstSession'][2]['pct'] == 50.0 and rep['firstSessionCharacters'] == 10, 'first session shares')
    ms = {m['level']: m for m in rep['milestones']}
    check(ms[10]['medianMinutes'] == 5.0 and ms[10]['characters'] == 4, 'median level 10: %r' % (ms[10],))
    check(ms[25]['medianMinutes'] == 15.0, 'median level 25 (0-30, all in one bucket): %r' % (ms[25],))
    check(list(ms) == [10, 25], 'milestones ascending')
    # small-number suppression: 1 to 4 is "<5" in the report and the JSON, with its share, median and band left out
    small = [('churn', '1-5', 'gone', 3), ('churn', '1-5', 'active', 1),          # band of 4: all hidden
             ('churn', '6-10', 'gone', 2), ('churn', '6-10', 'active', 30),       # one side hidden: no share
             ('churn', '11-15', 'gone', 10), ('churn', '11-15', 'active', 0),     # exact, a zero stays 0
             ('death_area', 'Cave', '1-5', 4), ('death_area', 'Deep', '901+', 7), ('death_area', 'Deep', '1-5', 2),
             ('session1', '5', '', 3), ('session1', '10', '', 40),
             ('ttl', '10', '10', 4), ('ttl', '25', '10', 6)]
    sr = pm.report(small)
    bands = {b['band']: b for b in sr['churn']['bands']}
    check(bands['1-5']['gone'] == '<5' and bands['1-5']['active'] == '<5' and bands['1-5']['total'] == '<5'
          and bands['1-5']['gonePct'] is None, 'band of 4 hidden: %r' % (bands['1-5'],))
    check(bands['6-10']['gone'] == '<5' and bands['6-10']['active'] == 30 and bands['6-10']['gonePct'] is None, 'one side hidden')
    check(bands['11-15']['gone'] == 10 and bands['11-15']['active'] == 0 and bands['11-15']['gonePct'] == 100.0, 'exact and zero kept')
    check(sr['churn']['gone'] == 15 and sr['churn']['active'] == 31, 'totals of 5 and more are exact')
    areas = {e['name']: e for e in sr['deathAreas']}
    check(areas['Cave']['deaths'] == '<5' and areas['Cave']['topBand'] == '' and areas['Cave']['topBandDeaths'] == '<5', 'area of 4 deaths')
    check(areas['Deep']['deaths'] == 9 and areas['Deep']['topBand'] == '901+' and areas['Deep']['topBandDeaths'] == 7, 'area of 9 shown')
    fs = {e['bucket']: e for e in sr['firstSession']}
    check(fs['5']['characters'] == '<5' and fs['5']['pct'] is None and fs['10']['characters'] == 40, 'first session bucket of 3')
    check(sr['firstSessionCharacters'] == 43, 'first session total')
    ms2 = {m['level']: m for m in sr['milestones']}
    check(ms2[10]['characters'] == '<5' and ms2[10]['medianMinutes'] is None and ms2[25]['characters'] == 6
          and ms2[25]['medianMinutes'] is not None, 'milestone of 4 hides its median')
    txt = pm.text(sr)
    check('<5' in txt and '(most at level )' not in txt and 'n/a' in txt, 'text output shows <5: ' + txt)
    check('"<5"' in json.dumps(sr) and pm.hide(0) == 0 and pm.hide(4) == '<5' and pm.hide(5) == 5, 'hide()')
    check(pm.report([('death_monster', 'Rat', '1-5', 4)])['deathMonsters'][0]['deaths'] == '<5', 'monster of 4 deaths')

    # O258 funnel: returns by cohort week, first use, where they stop
    import datetime
    d = datetime.date
    check(pm.parse_day('20241004') == d(2024, 10, 4) and pm.parse_day('nope') is None and pm.parse_day('20241399') is None, 'parse_day')
    fr = [('cohort', '20241007', '', 10), ('cohort', '20241009', '', 20), ('cohort', '20241014', '', 3),   # weeks of Oct 7 and Oct 14
          ('return', 'd1', '20241007', 6), ('return', 'd1', '20241009', 9), ('return', 'd3', '20241009', 8),
          ('return', 'd7', '20241009', 3),
          ('return', 'd1', '20241014', 1), ('cohort', 'garbage', '', 5)]
    wk = pm.returns(fr, d(2024, 10, 30))
    check([w['week'] for w in wk] == ['2024-10-07', '2024-10-14'], 'weeks ordered by Monday: %r' % (wk,))
    w0, w1 = wk
    check(w0['cohort'] == 30 and w0['d1'] == 15 and w0['d1Pct'] == 50.0 and w0['d3Pct'] == 26.7, 'week 1 shares: %r' % (w0,))
    check(w0['d7'] == '<5' and w0['d7Pct'] is None, 'a hidden d7 has no share')
    check(w1['cohort'] == '<5' and w1['d1'] == '<5' and w1['d1Pct'] is None, 'a cohort of 3 is hidden')
    young = pm.returns(fr, d(2024, 10, 13))[0]
    check(young['d1Pct'] is None and young['d3Pct'] is None, 'a week not yet old enough has no share')
    mid = pm.returns(fr, d(2024, 10, 14))[0]  # Sunday Oct 13 + 1 day = Oct 14: d1 mature, d3 not
    check(mid['d1Pct'] == 50.0 and mid['d3Pct'] is None, 'maturity per day')
    check(pm.returns([], d(2024, 10, 30)) == [], 'no cohorts')

    ff = [('first', 'dungeon', '11-15|60', 30), ('first', 'dungeon', '16-20|120', 10), ('first', 'rift', '31-40|45', 4),
          ('first', 'guild', '1-5|10', 50), ('first', 'bad', 'no-pipe', 7), ('first', 'tower', '1-5|5', 0)]
    fu = pm.first_use(ff, 200)
    names = [e['system'] for e in fu]
    check(names[0] == 'guild' and names[1] == 'dungeon' and names.index('rift') == len(names) - 1 and 'tower' not in names,
          'first use order: biggest first, hidden last: %r' % (names,))
    dg = [e for e in fu if e['system'] == 'dungeon'][0]
    check(dg['characters'] == 40 and dg['pct'] == 20.0 and dg['topBand'] == '11-15', 'dungeon row: %r' % (dg,))
    check(dg['medianMinutes'] is not None and 0 < dg['medianMinutes'] <= 60, 'dungeon median inside its buckets: %r' % (dg,))
    rf = [e for e in fu if e['system'] == 'rift'][0]
    check(rf['characters'] == '<5' and rf['pct'] is None and rf['medianMinutes'] is None and rf['topBand'] == '', 'rift of 4 hidden')
    check(pm.first_use(ff, 0)[0]['pct'] is None, 'no population: no share')

    sr2 = pm.report([('stop', 'Ember Caves', '1-5', 12), ('stop', 'Ember Caves', '6-10', 30), ('stop', 'Marsh', '1-5', 4),
                     ('stop', 'Cave', '1-5', 0), ('churn', '1-5', 'gone', 46), ('churn', '1-5', 'active', 154),
                     ('first', 'dungeon', '1-5|10', 20)], today=d(2024, 10, 30))
    check([e['name'] for e in sr2['stops']] == ['Ember Caves', 'Marsh'], 'stops: zero rows dropped')
    check(sr2['stops'][0]['gone'] == 42 and sr2['stops'][0]['topBand'] == '6-10', 'stops: area total and top band')
    check(sr2['stops'][1]['gone'] == '<5' and sr2['stops'][1]['topBand'] == '', 'stops: a handful hidden with its band')
    check(sr2['firstUse'][0]['pct'] == 10.0, 'first use share of the churn population (46 + 154 = 200)')
    t2 = pm.text(sr2)
    check('Where they stop' in t2 and 'First use of a system' in t2 and 'Return (' in t2 and 'Ember Caves' in t2, 'text has the new sections')
    check(all(k in sr2 for k in ('returns', 'firstUse', 'stops')), 'json keys')
    check(pm.report([])['returns'] == [] and pm.report([])['firstUse'] == [] and pm.report([])['stops'] == [], 'empty table, new sections')

    e = pm.report([])
    check(e['ok'] and e['empty'] and e['churn']['bands'] == [] and e['milestones'] == [], 'empty table')

    # command line
    class Stdin(io.StringIO):
        pass
    old_in, old_out = sys.stdin, sys.stdout
    try:
        sys.stdin = io.StringIO('churn\t1-5\tgone\t30\nchurn\t1-5\tactive\t1000\n')
        sys.stdout = io.StringIO()
        rc = pm.main(['--json'])
        out = sys.stdout.getvalue()
        sys.stdin = io.StringIO('')
        sys.stdout = io.StringIO()
        rc2 = pm.main(['--json', '--error', 'database'])
        out2 = sys.stdout.getvalue()
        sys.stdin = io.StringIO('churn\t1-5\tgone\t30\n')
        sys.stdout = io.StringIO()
        rc3 = pm.main([])
        out3 = sys.stdout.getvalue()
        sys.stderr, old_err = io.StringIO(), sys.stderr
        rc4 = pm.main(['--bogus'])
        sys.stderr = old_err
    finally:
        sys.stdin, sys.stdout = old_in, old_out
    check(rc == 0 and json.loads(out)['churn']['gone'] == 30 and out.count('\n') == 1, 'json output, one line')
    check(rc2 == 1 and json.loads(out2) == {'ok': False, 'error': 'database'}, 'error answer')
    check(rc3 == 0 and out3.startswith('Churn (gone = no login for 0 days'), 'text output: ' + out3)
    check(rc4 == 2, 'unknown option')
    check('no data' == pm.minutes_text(None) and pm.minutes_text(30) == '30 min' and pm.minutes_text(180) == '3.0 h'
          and pm.minutes_text(60 * 72) == '3.0 days', 'minutes_text')
    print('progress_metrics_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

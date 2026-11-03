#!/usr/bin/env python3
"""Tests of newplayer_report.py (O374): the funnel SELECT (fixed numbers, grouped, no name, the storages of
metrics_config.lua), the funnel maths on synthetic grouped rows (reach, hours, stopped, small numbers), the survey rows
(mysql -B escapes, control and bidi characters, stage summary) and the command line. Synthetic data only.

  python3 -I server/tools/newplayer_report_test.py
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import newplayer_report as R  # noqa: E402

TOOL = os.path.join(HERE, 'newplayer_report.py')
SERVER = os.path.dirname(HERE)
failures = 0
checks = 0


def check(cond, label):
    global failures, checks
    checks += 1
    if not cond:
        failures += 1
        print('FAIL ' + label)


def run(*args, stdin=''):
    return subprocess.run([sys.executable, '-I', TOOL] + list(args), input=stdin, capture_output=True, text=True,
                          timeout=30)


def lua_number(text, key):
    m = re.search(r'^\s*%s\s*=\s*(\d+)' % key, text, re.M)
    return int(m.group(1)) if m else None


def test_mirrors():
    cfg = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'metrics_config.lua'), encoding='utf-8').read()
    check(lua_number(cfg, 'storage') == R.MILESTONE_STORAGE, 'milestone storage = metrics_config storage')
    check(lua_number(cfg, 'returnStorage') == R.RETURN_STORAGE, 'return storage')
    check(lua_number(cfg, 'lastSystemStorage') == R.LAST_SYSTEM_STORAGE, 'last system storage')
    check(lua_number(cfg, 'maxGroupId') == R.MAX_GROUP_ID, 'max group id')
    m = re.search(r'milestones\s*=\s*\{([^}]*)\}', cfg)
    check(m and [int(x) for x in m.group(1).split(',')][:4] == [10, 25, 50, 100], 'milestone bits 0-3 = 10 / 25 / 50 / 100')
    m = re.search(r'systems\s*=\s*\{([^}]*)\}', cfg, re.S)
    check(m and re.findall(r'"([a-z]+)"', m.group(1)) == R.SYSTEMS, 'systems in the same order')
    const = open(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'chaos_constants.lua'), encoding='utf-8').read()
    check('Chaos.storage.tester = %d' % R.TESTER_STORAGE in const, 'tester storage')
    for k in R.SYSTEMS + ['none']:
        check(k in R.SYSTEM_NAMES['en'] and k in R.SYSTEM_NAMES['pt'], 'system name ' + k)
    check(set(R.WORDS['en']) == set(R.WORDS['pt']), 'every text in both languages')
    for k, v in R.WORDS['en'].items():
        check(v.count('%') == R.WORDS['pt'][k].count('%'), 'same formats: ' + k)


def test_sql():
    now = 1790000000
    q = R.funnel_sql(30, now)
    check(q.startswith('SELECT ') and 'GROUP BY `reach`, `hours`, `gone`, `old`, `band`, `mins`, `sys`' in q, 'grouped')
    day = R.day_number(now)
    check('`rs`.`key` = 7102831 AND `rs`.`value` >= %d' % ((day - 30) * 8) in q, 'window on the first-login day')
    check('`p`.`lastlogin` < %d' % (now - 7 * 86400) in q, 'stopped: no login for 7 days')
    check('`ls`.`key` = 7102834' in q and '`ms`.`key` = 7102830' in q, 'joins the milestone and last system storages')
    check('`ts`.`key` = 7102900 AND `ts`.`value` = 1' in q and '`p`.`group_id` <= 1' in q, 'testers and staff left out')
    for bad in ('`name`', 'account', 'lastip', 'email'):
        check(bad not in q, 'the funnel never reads ' + bad)
    check(';' not in q and '--' not in q, 'one statement, no comment')
    s = R.survey_sql(7, now)
    check('FROM `chaos_survey` WHERE `created_at` >= %d' % (now - 7 * 86400) in s and 'LIMIT 1000' in s, 'survey window')
    check('account_id' not in s and '`name`' not in s, 'the survey report never reads the account or a name')
    for bad in (0, -1, 3651, 'x'):
        try:
            R.funnel_sql(bad, now)
            check(False, 'refuses days %r' % (bad,))
        except ValueError:
            check(True, 'refuses days')
    check(R.case_sql('x', [5, 10]) == 'CASE WHEN x <= 5 THEN 1 WHEN x <= 10 THEN 2 ELSE 3 END', 'case_sql')


# synthetic grouped rows: reach, hours, gone, old, band, mins, sys, n
ROWS = [
    (0, 0, 1, 1, 1, 1, 0, 40),   # stopped at level 1-5 in the first 10 minutes, no system
    (1, 0, 1, 1, 2, 3, 0, 20),   # reached 10, stopped at 6-10 after up to 60 min
    (2, 1, 1, 1, 5, 4, 2, 8),    # reached 20 (25), 1h, stopped at 21-25, last system rift
    (3, 2, 0, 1, 0, 0, 0, 12),   # reached 30, 5h, still playing
    (5, 3, 0, 1, 0, 0, 0, 3),    # reached 100, 10h: a small group
    (1, 0, 0, 0, 0, 0, 0, 17),   # young characters, not old enough to count as stopped
]


def lines(rows):
    return ['\t'.join(str(x) for x in r) for r in rows]


def test_funnel():
    rows = R.parse_funnel(lines(ROWS) + ['junk', '1\t2', '0\t0\t0\t0\t0\t0\t0\t0'])
    check(len(rows) == 6, 'parse: junk and zero counts dropped')
    f = R.funnel(rows, 30)
    check(f['characters'] == 100, 'total')
    reached = {r['level']: r for r in f['reached']}
    check(reached[10]['characters'] == 60 and reached[10]['pct'] == 60.0, 'reached 10: 60')
    check(reached[20]['characters'] == 23 and reached[30]['characters'] == 15, 'reached 20 / 30')
    check(reached[50]['characters'] == '<5' and reached[50]['pct'] is None, 'reached 50: small, hidden')
    check(reached[100]['characters'] == '<5', 'reached 100: small')
    played = {r['hours']: r for r in f['played']}
    check(played[1]['characters'] == 23 and played[5]['characters'] == 15 and played[10]['characters'] == '<5', 'played')
    st = f['stopped']
    check(st['characters'] == 68 and st['eligible'] == 83 and st['pct'] == round(6800 / 83.0, 1), 'stopped of old enough')
    levels = {r['band']: r['characters'] for r in f['stopLevel']}
    check(levels == {'1-5': 40, '6-10': 20, '21-25': 8}, 'stopped at level: %r' % levels)
    mins = {r['bucket']: r['characters'] for r in f['stopMinutes']}
    check(mins == {'10': 40, '60': 20, '120': 8}, 'stopped after minutes: %r' % mins)
    sys_ = [(r['system'], r['characters']) for r in f['stopSystem']]
    check(sys_ == [('none', 60), ('rift', 8)], 'last system, most first: %r' % sys_)
    check(R.system_key(99) == 'none' and R.system_key(1) == 'dungeon', 'system_key')
    t = R.funnel_text(f, 'en')
    check('Characters: 100' in t and '  10     60 (60.0%)' in t and '  50     <5' in t, 'text: ' + t)
    check('none (hunting only)' in t and 'Rift' in t and 'up to 10 min' in t, 'text: system and minute labels')
    p = R.funnel_text(f, 'pt')
    check('Personagens: 100' in p and 'Fenda' in p and 'Chegaram ao nível' in p, 'pt text')
    empty = R.funnel([], 30)
    check(empty['characters'] == 0 and 'No new characters' in R.funnel_text(empty, 'en'), 'empty window')
    small = R.funnel(R.parse_funnel(['1\t0\t1\t1\t1\t1\t0\t3']), 30)
    check(small['characters'] == '<5' and small['stopped']['pct'] is None, 'a tiny window is hidden')
    t = R.funnel_text(small, 'en')
    check('Characters: <5' in t, 'tiny window text')
    over = R.funnel(R.parse_funnel(['1\t0\t1\t1\t12\t8\t0\t9']), 30)
    check(over['stopLevel'][0]['band'] == '101+' and over['stopMinutes'][0]['bucket'] == 'inf', 'open band and bucket')
    check('over 1200 min' in R.funnel_text(over, 'en'), 'open minutes label')


def test_survey():
    raw = [
        '20\tanswered\t4\t1\t21\t95\t1790000000\tWhere is the bank?\\nAnd the depot',
        '20\tanswered\t2\t0\t20\t70\t1789990000\tspells \\\\ runes\x07 ‮ok',
        '20\tskipped\t0\t-1\t22\t130\t1789980000\t',
        '50\tanswered\t5\t-1\t50\t900\t1789970000\tNULL',
        '50\tanswered\t0\t1\t51\t960\t1789960000\t' + 'x' * 400,
        'bad line',
        '77\tweird\tx\ty\t1\t1\t1\thello\tthere',
    ]
    rows = R.parse_survey(raw)
    check(len(rows) == 6, 'parse: a short line dropped')
    check(rows[0]['text'] == 'Where is the bank? And the depot', 'mysql \\n unescaped to a space')
    check(rows[1]['text'] == 'spells \\ runes ok', 'backslash, control and bidi characters: %r' % rows[1]['text'])
    check(rows[3]['text'] == '' and len(rows[4]['text']) == 200, 'NULL is empty, long text capped')
    check(rows[5]['status'] == 'skipped' and rows[5]['text'] == 'hello\tthere'.replace('\t', ' '), 'odd status and a tab in the text')
    s = R.survey(rows, 30)
    by = {x['stage']: x for x in s['stages']}
    check(by[20]['answered'] == 2 and by[20]['skipped'] == 1, 'stage 20 counts')
    check(by[20]['funMean'] == 3.0 and by[20]['fun'] == [0, 1, 0, 1, 0], 'fun mean and spread')
    check(by[20]['yes'] == 1 and by[20]['no'] == 1 and by[20]['yesPct'] == 50.0, 'recommend')
    check(by[50]['funMean'] == 5.0 and by[50]['yes'] == 1 and by[50]['no'] == 0, 'stage 50: a 0 score is not counted')
    check(len(by[50]['texts']) == 1, 'stage 50: the empty text is not listed')
    check(77 in by and by[77]['skipped'] == 1, 'an unknown stage is shown, not lost')
    t = R.survey_text(s, 'en', texts=1)
    check('Level 20 survey: 2 answered, 1 skipped' in t and 'mean 3.00' in t and 'yes 1, no 1 (50.0%)' in t, 'text: ' + t)
    check('(newest first, 1 of 2)' in t and 'Where is the bank? And the depot (level 21, 1h35 played, ' in t, 'text rows')
    p = R.survey_text(s, 'pt')
    check('Pesquisa do nível 20: 2 responderam, 1 pularam' in p and 'Recomendaria? sim 1' in p, 'pt text')
    e = R.survey([], 30)
    check(e['answers'] == 0 and 'No survey answers' in R.survey_text(e, 'en'), 'no answers')
    check([x['stage'] for x in e['stages']] == [20, 50], 'both stages listed when empty')


def test_cli():
    r = run('funnel', '--sql', '--days', '7', '--now', '1790000000')
    check(r.returncode == 0 and r.stdout.startswith('SELECT') and r.stdout.count('\n') == 1, 'cli: --sql prints one line')
    r = run('funnel', '--json', stdin='\n'.join(lines(ROWS)) + '\n')
    d = json.loads(r.stdout)
    check(r.returncode == 0 and d['ok'] and d['characters'] == 100 and d['days'] == 30, 'cli: funnel json')
    r = run('funnel', '--pt', '--days', '90', stdin='')
    check(r.returncode == 0 and 'últimos 90 dias' in r.stdout, 'cli: pt text, days')
    r = run('survey', '--json', '--error', 'no-table')
    check(r.returncode == 1 and json.loads(r.stdout) == {'ok': False, 'error': 'no-table'}, 'cli: error json')
    r = run('survey', '--error', 'x;$(id)')
    check(r.returncode == 1 and r.stdout.strip() == 'Error: xid', 'cli: error code cleaned')
    for bad in (('funnel', '--days', '0'), ('funnel', '--days', 'x'), ('funnel', '--bogus'), ('nope',), ()):
        check(run(*bad).returncode == 2, 'cli refuses %r' % (bad,))
    r = run('survey', '--texts', '0', stdin='20\tanswered\t3\t1\t20\t60\t1790000000\thi\n')
    check(r.returncode == 0 and '(newest first, 0 of 1)' in r.stdout, 'cli: --texts 0')


def main():
    test_mirrors()
    test_sql()
    test_funnel()
    test_survey()
    test_cli()
    print('newplayer_report_test: %d checks, %d failures' % (checks, failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

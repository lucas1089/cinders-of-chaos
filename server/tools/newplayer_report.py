#!/usr/bin/env python3
"""New player reports (server/README.md "New player funnel and survey (O374)"): chaos-ctl.sh newplayer-funnel and survey.

funnel  Of the characters whose first login was in the last N days (default 30): how many reached level 10 / 20 / 30 /
        50 / 100, how many played 1 / 5 / 10 hours, and of those with no login for 7+ days ("stopped"), at which level
        band, after how many played minutes and after which system they stopped.
        Data the server already stores: `players` (level, onlinetime, lastlogin) and the player storages of the
        progress metrics (data/scripts/chaos/metrics_config.lua): +1 the first-login day (O258), +0 the milestone mask
        (10 / 25 / 50 / 100, so a level lost at a death still counts), +4 the last system used (O374). The SELECT
        groups in the database: one row per (reach, hours, stopped, band, minutes, system) and a count. No name,
        account, id or IP is read.
survey  The answers of the in-game survey (data/scripts/chaos/survey.lua, table chaos_survey) of the last N days: per
        stage (level 20 / 50) answered and skipped, "How fun is it?" 1-5 (mean and spread), "Would you recommend it?",
        and the free texts ("What confused you so far?") newest first with level and played minutes. No account id or
        name is read (the account id is only the unique key of the table).

  newplayer_report.py funnel --sql [--days N] [--now T]       print the SELECT (chaos-ctl.sh runs it)
  newplayer_report.py funnel [--json] [--pt] [--days N] < rows
  newplayer_report.py survey --sql [--days N] [--now T]
  newplayer_report.py survey [--json] [--pt] [--days N] [--texts N] < rows
  newplayer_report.py MODE [--json] [--pt] --error CODE        {"ok": false, "error": CODE} (the database could not be read)

Rows are what mysql -N -B prints (tab separated). --pt writes the text in Brazilian Portuguese (the admin apps).
Small numbers in the funnel: a count of 1 to 4 is written "<5" (text and JSON), with its share left out, as in
progress_metrics.py. Run with python3 -I.
"""
import json
import sys
import time
import unicodedata

# ---------------------------------------------------------------- mirrors of metrics_config.lua (newplayer_report_test.py
# compares them with the Lua file)
MILESTONE_STORAGE = 7102830   # cfg.storage: bit 0 = 10, bit 1 = 25, bit 2 = 50, bit 3 = 100
RETURN_STORAGE = 7102831      # cfg.returnStorage: day * 8 + flags, day = first login (whole days, server time)
LAST_SYSTEM_STORAGE = 7102834  # cfg.lastSystemStorage (O374): index in SYSTEMS, 1-based
TESTER_STORAGE = 7102900      # Chaos.storage.tester
MAX_GROUP_ID = 1              # cfg.maxGroupId
SYSTEMS = ["dungeon", "rift", "waystone", "tower", "pocketboss", "worldboss", "invasion", "party", "guild",
           "market", "bounty", "craft"]
# ---------------------------------------------------------------- the funnel's own numbers
REACH = [10, 20, 30, 50, 100]          # levels; index k = reached REACH[0..k-1]
HOURS = [1, 5, 10]                     # played hours
STOP_DAYS = 7                          # no login for this many days = stopped
BANDS = [5, 10, 15, 20, 25, 30, 40, 50, 60, 80, 100]  # stopped at level band (upper limits; "101+" last)
MINUTES = [10, 30, 60, 120, 300, 600, 1200]           # stopped after played minutes (upper limits; "inf" last)
DEFAULT_DAYS = 30
MAX_DAYS = 3650
TEXTS = 50                             # survey free texts in the text report (--texts N; the JSON has up to 500)
TEXT_MAX = 200
SURVEY_TABLE = "chaos_survey"
STAGES = [20, 50]

MIN_SHOWN = 5
SMALL = '<%d' % MIN_SHOWN

SYSTEM_NAMES = {
    'en': {"dungeon": "Dungeon", "rift": "Rift", "waystone": "Waystone map", "tower": "Infinity Tower",
           "pocketboss": "Pocket Boss", "worldboss": "World boss", "invasion": "Invasion", "party": "Party",
           "guild": "Guild", "market": "Market", "bounty": "Bounty", "craft": "Crafting", "none": "none (hunting only)"},
    'pt': {"dungeon": "Masmorra", "rift": "Fenda", "waystone": "Mapa de waystone", "tower": "Infinity Tower",
           "pocketboss": "Pocket Boss", "worldboss": "Boss mundial", "invasion": "Invasão", "party": "Grupo",
           "guild": "Guilda", "market": "Mercado", "bounty": "Bounty", "craft": "Criação", "none": "nenhum (só caçou)"},
}

WORDS = {
    'en': {
        'funnel_title': 'New player funnel: characters whose first login was in the last %d days',
        'created': 'Characters: %s',
        'none': 'No new characters in the window yet (only first logins after the O258 install count).',
        'reached': 'Reached level',
        'played': 'Played',
        'hours': '%dh',
        'stopped': 'Stopped (no login for %d+ days): %s of %s old enough%s',
        'stop_level': 'Stopped at level',
        'stop_minutes': 'Stopped after played minutes',
        'stop_system': 'Last system used before stopping',
        'level': 'level %s',
        'minutes_upto': 'up to %s min',
        'minutes_over': 'over %s min',
        'young': 'Characters younger than %d days cannot count as stopped yet.',
        'survey_title': 'In-game survey: answers of the last %d days',
        'stage': 'Level %d survey: %d answered, %d skipped',
        'fun': 'How fun is it? mean %s (1: %d, 2: %d, 3: %d, 4: %d, 5: %d)',
        'recommend': 'Would you recommend it? yes %d, no %d%s',
        'texts': 'What confused you so far? (newest first, %d of %d)',
        'text_row': '- %s (level %d, %s played, %s)',
        'no_answers': 'No survey answers in the window yet.',
        'no_texts': '(no texts)',
        'error': 'Error: %s',
    },
    'pt': {
        'funnel_title': 'Funil de novos jogadores: personagens que entraram pela primeira vez nos últimos %d dias',
        'created': 'Personagens: %s',
        'none': 'Ainda não há personagens novos no período (só contam os primeiros logins depois do O258).',
        'reached': 'Chegaram ao nível',
        'played': 'Jogaram',
        'hours': '%dh',
        'stopped': 'Pararam (sem login há %d+ dias): %s de %s com idade para contar%s',
        'stop_level': 'Pararam no nível',
        'stop_minutes': 'Pararam depois de jogar (minutos)',
        'stop_system': 'Último sistema usado antes de parar',
        'level': 'nível %s',
        'minutes_upto': 'até %s min',
        'minutes_over': 'mais de %s min',
        'young': 'Personagens com menos de %d dias ainda não contam como parados.',
        'survey_title': 'Pesquisa no jogo: respostas dos últimos %d dias',
        'stage': 'Pesquisa do nível %d: %d responderam, %d pularam',
        'fun': 'Quão divertido é? média %s (1: %d, 2: %d, 3: %d, 4: %d, 5: %d)',
        'recommend': 'Recomendaria? sim %d, não %d%s',
        'texts': 'O que confundiu até agora? (mais novos primeiro, %d de %d)',
        'text_row': '- %s (nível %d, %s jogados, %s)',
        'no_answers': 'Ainda não há respostas da pesquisa no período.',
        'no_texts': '(sem textos)',
        'error': 'Erro: %s',
    },
}


def hide(n):
    return SMALL if 0 < n < MIN_SHOWN else n


def num(s, default=0):
    try:
        return int(s)
    except (TypeError, ValueError):
        return default


def pct(part, whole):
    """share in percent with one decimal, None when hidden or nothing to divide"""
    if whole <= 0 or 0 < part < MIN_SHOWN or 0 < whole < MIN_SHOWN:
        return None
    return round(100.0 * part / whole, 1)


def day_number(now):
    """whole days since the epoch in the server's local time (metrics_core.lua M.dayNumber with the server offset)"""
    offset = time.localtime(now).tm_gmtoff or 0
    return int((now + offset) // 86400)


def band_label(i, edges):
    if i > len(edges):
        return '%d+' % (edges[-1] + 1)
    lo = 1 if i == 1 else edges[i - 2] + 1
    return '%d-%d' % (lo, edges[i - 1])


def bucket_label(i, edges):
    return 'inf' if i > len(edges) else str(edges[i - 1])


def case_sql(expr, edges):
    """CASE WHEN expr <= e1 THEN 1 ... ELSE n END (numbers of this file only)"""
    parts = ['CASE']
    for i, hi in enumerate(edges, 1):
        parts.append('WHEN %s <= %d THEN %d' % (expr, hi, i))
    parts.append('ELSE %d END' % (len(edges) + 1))
    return ' '.join(parts)


def check_days(days):
    days = int(days)
    if days < 1 or days > MAX_DAYS:
        raise ValueError('days must be 1 to %d' % MAX_DAYS)
    return days


# ---------------------------------------------------------------- funnel
def funnel_sql(days, now):
    """The one SELECT of the funnel. Every number comes from this file or from checked integers."""
    days = check_days(days)
    now = int(now)
    start = (day_number(now) - days) * 8
    cutoff = now - STOP_DAYS * 86400
    mask = 'COALESCE(`ms`.`value`, 0)'
    lvl = '`p`.`level`'
    # bits of the milestone mask: 1 = 10, 2 = 25, 4 = 50, 8 = 100 (a level lost at a death still counts)
    reach = ('CASE WHEN %(l)s >= 100 OR (%(m)s & 8) <> 0 THEN 5 WHEN %(l)s >= 50 OR (%(m)s & 4) <> 0 THEN 4 '
             'WHEN %(l)s >= 30 THEN 3 WHEN %(l)s >= 20 OR (%(m)s & 2) <> 0 THEN 2 '
             'WHEN %(l)s >= 10 OR (%(m)s & 1) <> 0 THEN 1 ELSE 0 END') % {'l': lvl, 'm': mask}
    hours = 'CASE WHEN `p`.`onlinetime` >= 36000 THEN 3 WHEN `p`.`onlinetime` >= 18000 THEN 2 ' \
            'WHEN `p`.`onlinetime` >= 3600 THEN 1 ELSE 0 END'
    gone = '(`p`.`lastlogin` < %d)' % cutoff
    old = '(`rs`.`value` < %d)' % ((day_number(now) - STOP_DAYS + 1) * 8)
    band = case_sql(lvl, BANDS)
    mins = case_sql('FLOOR(`p`.`onlinetime` / 60)', MINUTES)
    system = 'COALESCE(`ls`.`value`, 0)'
    return (
        'SELECT %(reach)s AS `reach`, %(hours)s AS `hours`, IF(%(gone)s, 1, 0) AS `gone`, IF(%(old)s, 1, 0) AS `old`, '
        'IF(%(gone)s, %(band)s, 0) AS `band`, IF(%(gone)s, %(mins)s, 0) AS `mins`, IF(%(gone)s, %(sys)s, 0) AS `sys`, '
        'COUNT(*) AS `n` FROM `players` `p` '
        'JOIN `player_storage` `rs` ON `rs`.`player_id` = `p`.`id` AND `rs`.`key` = %(rk)d AND `rs`.`value` >= %(start)d '
        'LEFT JOIN `player_storage` `ms` ON `ms`.`player_id` = `p`.`id` AND `ms`.`key` = %(mk)d '
        'LEFT JOIN `player_storage` `ls` ON `ls`.`player_id` = `p`.`id` AND `ls`.`key` = %(lk)d '
        'WHERE `p`.`group_id` <= %(grp)d AND `p`.`lastlogin` > 0 AND NOT EXISTS (SELECT 1 FROM `player_storage` `ts` '
        'WHERE `ts`.`player_id` = `p`.`id` AND `ts`.`key` = %(tk)d AND `ts`.`value` = 1) '
        'GROUP BY `reach`, `hours`, `gone`, `old`, `band`, `mins`, `sys`'
    ) % {'reach': reach, 'hours': hours, 'gone': gone, 'old': old, 'band': band, 'mins': mins, 'sys': system,
         'rk': RETURN_STORAGE, 'start': start, 'mk': MILESTONE_STORAGE, 'lk': LAST_SYSTEM_STORAGE,
         'grp': MAX_GROUP_ID, 'tk': TESTER_STORAGE}


def parse_funnel(lines):
    rows = []
    for line in lines:
        parts = line.rstrip('\r\n').split('\t')
        if len(parts) < 8:
            continue
        v = [num(x) for x in parts[:8]]
        if v[7] > 0:
            rows.append(dict(zip(('reach', 'hours', 'gone', 'old', 'band', 'mins', 'sys', 'n'), v)))
    return rows


def system_key(i):
    return SYSTEMS[i - 1] if 1 <= i <= len(SYSTEMS) else 'none'


def funnel(rows, days):
    total = sum(r['n'] for r in rows)
    reached = []
    for k, level in enumerate(REACH, 1):
        n = sum(r['n'] for r in rows if r['reach'] >= k)
        reached.append({'level': level, 'characters': hide(n), 'pct': pct(n, total)})
    played = []
    for k, h in enumerate(HOURS, 1):
        n = sum(r['n'] for r in rows if r['hours'] >= k)
        played.append({'hours': h, 'characters': hide(n), 'pct': pct(n, total)})
    eligible = sum(r['n'] for r in rows if r['old'])
    gone_rows = [r for r in rows if r['gone']]
    gone = sum(r['n'] for r in gone_rows)

    def grouped(field, label):
        sums = {}
        for r in gone_rows:
            sums[r[field]] = sums.get(r[field], 0) + r['n']
        out = []
        for key in sorted(sums):
            n = sums[key]
            out.append(dict(label(key), characters=hide(n), pct=pct(n, gone)))
        return out

    return {
        'ok': True, 'days': days, 'stopDays': STOP_DAYS, 'characters': hide(total),
        'reached': reached, 'played': played,
        'stopped': {'characters': hide(gone), 'eligible': hide(eligible), 'pct': pct(gone, eligible)},
        'stopLevel': grouped('band', lambda b: {'band': band_label(max(1, b), BANDS)}),
        'stopMinutes': grouped('mins', lambda m: {'bucket': bucket_label(max(1, m), MINUTES)}),
        'stopSystem': sorted(grouped('sys', lambda s: {'system': system_key(s)}),
                             key=lambda x: -(x['characters'] if isinstance(x['characters'], int) else 0)),
    }


def share(p):
    return '' if p is None else ' (%s%%)' % p


def funnel_text(f, lang):
    w = WORDS[lang]
    names = SYSTEM_NAMES[lang]
    out = [w['funnel_title'] % f['days'], w['created'] % f['characters']]
    if f['characters'] == 0:
        out.append(w['none'])
        return '\n'.join(out)
    out.append('')
    out.append(w['reached'] + ':')
    for r in f['reached']:
        out.append('  %-6s %s%s' % (r['level'], r['characters'], share(r['pct'])))
    out.append(w['played'] + ':')
    for r in f['played']:
        out.append('  %-6s %s%s' % (w['hours'] % r['hours'], r['characters'], share(r['pct'])))
    s = f['stopped']
    out.append('')
    out.append(w['stopped'] % (f['stopDays'], s['characters'], s['eligible'], share(s['pct'])))
    out.append(w['young'] % f['stopDays'])
    if f['stopLevel']:
        out.append(w['stop_level'] + ':')
        for r in f['stopLevel']:
            out.append('  %-8s %s%s' % (r['band'], r['characters'], share(r['pct'])))
        out.append(w['stop_minutes'] + ':')
        for r in f['stopMinutes']:
            label = w['minutes_over'] % MINUTES[-1] if r['bucket'] == 'inf' else w['minutes_upto'] % r['bucket']
            out.append('  %-14s %s%s' % (label, r['characters'], share(r['pct'])))
        out.append(w['stop_system'] + ':')
        for r in f['stopSystem']:
            out.append('  %-20s %s%s' % (names.get(r['system'], r['system']), r['characters'], share(r['pct'])))
    return '\n'.join(out)


# ---------------------------------------------------------------- survey
def survey_sql(days, now):
    days = check_days(days)
    since = int(now) - days * 86400
    return ('SELECT `stage`, `status`, `fun`, `recommend`, `level`, `minutes`, `created_at`, `confused` FROM `%s` '
            'WHERE `created_at` >= %d ORDER BY `id` DESC LIMIT 1000') % (SURVEY_TABLE, since)


def unescape_mysql(s):
    """mysql -B writes \\n, \\t, \\0 and \\\\ for those bytes"""
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': ' ', 't': ' ', '0': '', '\\': '\\'}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def clean_text(s):
    """one line, no control or format characters, at most TEXT_MAX characters (the server cleaned it already)"""
    s = unescape_mysql(s or '')
    s = ''.join(' ' if c in '\r\n\t' else c for c in s)
    s = ''.join(c for c in s if unicodedata.category(c) not in ('Cc', 'Cf', 'Cs', 'Co', 'Cn'))
    s = ' '.join(s.split())
    return s[:TEXT_MAX]


def parse_survey(lines):
    rows = []
    for line in lines:
        parts = line.rstrip('\r\n').split('\t', 7)
        if len(parts) < 7:
            continue
        text = parts[7] if len(parts) > 7 else ''
        if text == 'NULL':
            text = ''
        rows.append({'stage': num(parts[0]), 'status': parts[1] if parts[1] in ('answered', 'skipped') else 'skipped',
                     'fun': num(parts[2]), 'recommend': num(parts[3], -1), 'level': num(parts[4]),
                     'minutes': num(parts[5]), 'at': num(parts[6]), 'text': clean_text(text)})
    return rows


def survey(rows, days):
    stages = []
    for st in sorted(set(STAGES) | {r['stage'] for r in rows}):
        rs = [r for r in rows if r['stage'] == st]
        if not rs and st not in STAGES:
            continue
        ans = [r for r in rs if r['status'] == 'answered']
        funs = [r['fun'] for r in ans if 1 <= r['fun'] <= 5]
        spread = [sum(1 for x in funs if x == k) for k in range(1, 6)]
        yes = sum(1 for r in ans if r['recommend'] == 1)
        no = sum(1 for r in ans if r['recommend'] == 0)
        texts = [{'text': r['text'], 'level': r['level'], 'minutes': r['minutes'], 'at': r['at']}
                 for r in ans if r['text']]
        stages.append({'stage': st, 'answered': len(ans), 'skipped': len(rs) - len(ans),
                       'funMean': round(sum(funs) / float(len(funs)), 2) if funs else None, 'fun': spread,
                       'yes': yes, 'no': no, 'yesPct': round(100.0 * yes / (yes + no), 1) if yes + no else None,
                       'texts': texts[:500]})
    return {'ok': True, 'days': days, 'answers': len(rows), 'stages': stages}


def played(minutes):
    return '%dh%02d' % (minutes // 60, minutes % 60)


def when(t):
    return time.strftime('%Y-%m-%d', time.localtime(t)) if t > 0 else '-'


def survey_text(s, lang, texts=TEXTS):
    w = WORDS[lang]
    out = [w['survey_title'] % s['days']]
    if s['answers'] == 0:
        out.append(w['no_answers'])
        return '\n'.join(out)
    for st in s['stages']:
        out.append('')
        out.append(w['stage'] % (st['stage'], st['answered'], st['skipped']))
        if st['answered'] == 0:
            continue
        mean = '-' if st['funMean'] is None else ('%.2f' % st['funMean'])
        out.append('  ' + w['fun'] % tuple([mean] + st['fun']))
        out.append('  ' + w['recommend'] % (st['yes'], st['no'], share(st['yesPct'])))
        shown = st['texts'][:texts]
        out.append('  ' + w['texts'] % (len(shown), len(st['texts'])))
        if not shown:
            out.append('    ' + w['no_texts'])
        for t in shown:
            out.append('    ' + w['text_row'] % (t['text'], t['level'], played(t['minutes']), when(t['at'])))
    return '\n'.join(out)


# ---------------------------------------------------------------- main
def main(argv):
    if not argv or argv[0] not in ('funnel', 'survey'):
        sys.stderr.write(__doc__)
        return 2
    mode, args = argv[0], argv[1:]
    as_json = lang_pt = want_sql = False
    days, now, err, texts = DEFAULT_DAYS, int(time.time()), None, TEXTS
    i = 0
    try:
        while i < len(args):
            a = args[i]
            if a == '--json':
                as_json = True
            elif a == '--pt':
                lang_pt = True
            elif a == '--sql':
                want_sql = True
            elif a in ('--days', '--now', '--error', '--texts') and i + 1 < len(args):
                i += 1
                if a == '--days':
                    days = check_days(args[i])
                elif a == '--now':
                    now = int(args[i])
                elif a == '--texts':
                    texts = max(0, min(500, int(args[i])))
                else:
                    err = ''.join(c for c in args[i] if c.isalnum() or c in '-_')[:32] or 'error'
            else:
                raise ValueError('unknown argument ' + a)
            i += 1
    except ValueError as e:
        sys.stderr.write('newplayer_report: %s\n' % e)
        return 2
    lang = 'pt' if lang_pt else 'en'
    if want_sql:
        print(funnel_sql(days, now) if mode == 'funnel' else survey_sql(days, now))
        return 0
    if err:
        if as_json:
            print(json.dumps({'ok': False, 'error': err}))
        else:
            print(WORDS[lang]['error'] % err)
        return 1
    lines = sys.stdin.read().splitlines()
    if mode == 'funnel':
        res = funnel(parse_funnel(lines), days)
        print(json.dumps(res, ensure_ascii=False) if as_json else funnel_text(res, lang))
    else:
        res = survey(parse_survey(lines), days)
        print(json.dumps(res, ensure_ascii=False) if as_json else survey_text(res, lang, texts))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

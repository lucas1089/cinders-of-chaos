#!/usr/bin/env python3
"""Season balance report (O398, server/README.md "Season balance report (O398)"): chaos-ctl.sh balance-report.

Compares the classes over a window (a season, or the last N days) from the balance telemetry (telemetry.lua):
  chaos_telemetry_hunt   experience and hunting seconds per level band and class -> minutes per level at the band's
                         level (balance_report_config.json bandLevel; the engine's experience curve)
  chaos_telemetry_class  deaths and damage dealt to monsters per level band and class (O398) -> deaths per hunting
                         hour, damage per hunting hour and the class's share of its band's damage
  chaos_telemetry_casts  casts per class and spell -> the most used spells
flags (pure: flags()) every class whose numbers sit outside the thresholds of balance_report_config.json around the
median of its band, with a suggested change. Aggregates only: no name, account or id is read. A class and band with
fewer than minCharacterHours character-hours is shown as "<5" and never compared (the small groups rule of O374).

  balance_report.py windows-sql --seasons FILE           the season windows with the /season start|end overrides
  balance_report.py window --season ID|current --seasons FILE [--now T] < rows     "SINCE UNTIL ID" of one season
  balance_report.py due --seasons FILE --dir DIR [--now T] < rows                  the id of an ended season with no
                                                                                    saved report yet, or nothing
  balance_report.py sql --since T --until T              the SELECT script (one mysql call, rows tagged)
  balance_report.py report --since T --until T [--title TEXT] [--vocations "1:Mystic,..."] [--pt] [--json]
                    [--save DIR --name NAME] < rows      the report; --save also writes DIR/NAME.md, DIR/NAME.json and
                                                         DIR/latest.md (the newest `keep` reports are kept)
  balance_report.py report ... --error CODE              {"ok": false, "error": CODE}
Run with python3 -I.
"""
import json
import os
import re
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, 'balance_report_config.json')
TABLES = {'hunt': 'chaos_telemetry_hunt', 'class': 'chaos_telemetry_class', 'casts': 'chaos_telemetry_casts'}
SEASON_PREFIX = 'chaos_season_'   # season_config.lua configPrefix: server_config rows of /season start|end
MIN_SHOWN = 5
SMALL = '<%d' % MIN_SHOWN
NAME_RE = re.compile(r'^[A-Za-z0-9_-]{1,64}$')

WORDS = {
    'en': {
        'title': 'Balance report: %s',
        'days': 'the last %d days',
        'period': 'Window: %s to %s (server time). Thresholds: %d%% around the median of the level band (deaths %d%%), '
                  'at least %s hunting hours per class and band.',
        'suggestions': 'Suggestions',
        'none': 'No class outside the thresholds.',
        'nodata': 'Not enough data yet: the telemetry fills as people hunt (classes with at least %s hunting hours '
                  'per band are compared).',
        'band': 'Level %s (median: %s min per level, %s deaths per hour, %s damage per hour)',
        'row': '- %s: %s min per level, %s deaths/h, %s damage/h (%s of the band), %s h hunting, %s character-hours%s',
        'not_compared': ' (not compared: too little data)',
        'spells': 'Most used spells',
        'spell_row': '- %s: %s',
        'damage_note': 'Damage counts the hits of the combat log (on while it is enabled), from the O398 update on.',
        'slow': '%s, level %s: levels %d%% slower than the median (%s against %s min per level). Suggestion: about '
                '+%d%% damage or experience.',
        'fast': '%s, level %s: levels %d%% faster than the median (%s against %s min per level). Suggestion: about '
                '-%d%% damage or experience.',
        'deaths': '%s, level %s: dies %d%% more often than the median (%s against %s deaths per hunting hour). '
                  'Suggestion: about +%d%% defense or healing.',
        'damage_low': '%s, level %s: deals %d%% less damage than the median (%s against %s per hour). Suggestion: '
                      'about +%d%% damage.',
        'damage_high': '%s, level %s: deals %d%% more damage than the median (%s against %s per hour). Suggestion: '
                       'about -%d%% damage.',
        'error': 'Error: %s',
        'class': 'class %d',
    },
    'pt': {
        'title': 'Relatório de equilíbrio: %s',
        'days': 'últimos %d dias',
        'period': 'Período: %s a %s (hora do servidor). Limites: %d%% em volta da mediana da faixa de nível (mortes '
                  '%d%%), no mínimo %s horas de caça por classe e faixa.',
        'suggestions': 'Sugestões',
        'none': 'Nenhuma classe fora dos limites.',
        'nodata': 'Ainda não há dados suficientes: a telemetria se enche com as caçadas (entram na comparação as '
                  'classes com pelo menos %s horas de caça na faixa).',
        'band': 'Nível %s (mediana: %s min por nível, %s mortes por hora, %s de dano por hora)',
        'row': '- %s: %s min por nível, %s mortes/h, %s de dano/h (%s da faixa), %s h caçando, %s personagem-horas%s',
        'not_compared': ' (fora da comparação: poucos dados)',
        'spells': 'Feitiços mais usados',
        'spell_row': '- %s: %s',
        'damage_note': 'O dano conta os acertos do combat log (quando ligado), a partir da atualização O398.',
        'slow': '%s, nível %s: sobe de nível %d%% mais devagar que a mediana (%s contra %s min por nível). Sugestão: '
                'cerca de +%d%% de dano ou experiência.',
        'fast': '%s, nível %s: sobe de nível %d%% mais rápido que a mediana (%s contra %s min por nível). Sugestão: '
                'cerca de -%d%% de dano ou experiência.',
        'deaths': '%s, nível %s: morre %d%% mais que a mediana (%s contra %s mortes por hora de caça). Sugestão: '
                  'cerca de +%d%% de defesa ou cura.',
        'damage_low': '%s, nível %s: causa %d%% menos dano que a mediana (%s contra %s por hora). Sugestão: cerca de '
                      '+%d%% de dano.',
        'damage_high': '%s, nível %s: causa %d%% mais dano que a mediana (%s contra %s por hora). Sugestão: cerca de '
                       '-%d%% de dano.',
        'error': 'Erro: %s',
        'class': 'classe %d',
    },
}


def load_config(path=CONFIG):
    with open(path, encoding='utf-8') as f:
        cfg = json.load(f)
    cfg.pop('comment', None)
    return cfg


def num(s, default=0):
    try:
        return int(s)
    except (TypeError, ValueError):
        return default


def exp_to_next(level):
    """experience from level L to L + 1 (the engine: Player::getExpForLevel; tools/progression_model.lua expToNext)"""
    return 50 * level * level - 150 * level + 200


# ---------------------------------------------------------------- seasons
def lua_block(text, name):
    m = re.search(r'\b' + re.escape(name) + r'\s*=\s*\{', text)
    if not m:
        return ''
    depth, i = 1, m.end()
    while i < len(text) and depth:
        depth += {'{': 1, '}': -1}.get(text[i], 0)
        i += 1
    return text[m.end():i - 1]


def lua_field(text, name):
    m = re.search(r'\b' + re.escape(name) + r'\s*=\s*("[^"]*"|[0-9]+)', text)
    if not m:
        return None
    v = m.group(1)
    return v.strip('"') if v.startswith('"') else int(v)


def to_unix(v, hour):
    """season_core.lua S.toUnix: YYYYMMDD at `hour` server local time, or a unix time"""
    if v is None:
        return None
    if 19000101 <= v <= 99991231:
        y, mo, d = v // 10000, v // 100 % 100, v % 100
        return int(time.mktime((y, mo, d, hour, 0, 0, 0, 0, -1)))
    return v


def read_seasons(path):
    """[{id, name, tag, start, finish}] of season_config.lua (the dates of the file; the overrides come from the DB)"""
    with open(path, encoding='utf-8') as f:
        text = f.read()
    body = lua_block(text, 'seasons')
    out = []
    for part in re.split(r'(?=\bid\s*=\s*\d+\s*,)', body)[1:]:
        sid = lua_field(part, 'id')
        if sid is None:
            continue
        hour = lua_field(part, 'hour') or 0
        # start and finish are None while the launch date is open (O463: the config reads the one launch value); a season
        # started by hand (/season start) then runs lengthDays from its start, like season_core.lua S.times
        out.append({'id': sid, 'name': lua_field(part, 'name') or ('Season %d' % sid), 'tag': lua_field(part, 'tag') or '',
                    'start': to_unix(lua_field(part, 'start'), hour), 'finish': to_unix(lua_field(part, 'finish'), hour),
                    'length': lua_field(part, 'lengthDays')})
    return out


def windows_sql(seasons):
    """one row per season: id, start, finish, the /season start|end overrides of server_config winning"""
    parts = []
    for s in seasons:
        sid = int(s['id'])

        def pick(key, default):
            return ("COALESCE((SELECT CAST(`value` AS SIGNED) FROM `server_config` WHERE `config` = '%s%d_%s' LIMIT 1), %d)"
                    % (SEASON_PREFIX, sid, key, int(default or 0)))
        parts.append("SELECT 'sw', %d, %s, %s" % (sid, pick('start', s['start']), pick('end', s['finish'])))
    return ' UNION ALL '.join(parts) + ';' if parts else "SELECT 'sw', 0, 0, 0 FROM DUAL WHERE 1 = 0;"


def parse_windows(lines, seasons):
    by_id = {s['id']: dict(s) for s in seasons}
    for line in lines:
        p = line.rstrip('\r\n').split('\t')
        if len(p) >= 4 and p[0] == 'sw' and num(p[1]) in by_id:
            w = by_id[num(p[1])]
            w['start'], w['finish'] = num(p[2], w['start']), num(p[3], w['finish'])
    for w in by_id.values():
        if w['start'] and not w['finish'] and isinstance(w.get('length'), int) and w['length'] > 0:
            w['finish'] = w['start'] + w['length'] * 86400
    return [by_id[k] for k in sorted(by_id)]


def pick_season(wins, want, now):
    """the season `want` (an id), or "current": the running one, else the last one that started"""
    valid = [w for w in wins if w['start'] and w['finish'] and w['finish'] > w['start']]
    if want == 'current':
        started = [w for w in valid if w['start'] <= now]
        return max(started, key=lambda w: w['start']) if started else None
    for w in valid:
        if w['id'] == num(want, -1):
            return w
    return None


def due(wins, now, saved_dir, auto_days):
    """seasons that ended within auto_days and have no saved report (season-ID.md) yet, oldest first"""
    out = []
    for w in wins:
        if not w['start'] or not w['finish'] or w['finish'] <= w['start']:
            continue
        if w['finish'] <= now < w['finish'] + auto_days * 86400 and \
                not os.path.exists(os.path.join(saved_dir, 'season-%d.md' % w['id'])):
            out.append(w['id'])
    return out


# ---------------------------------------------------------------- SQL and rows
def build_sql(since, until):
    since, until = int(since), int(until)
    if since < 0 or until <= since:
        raise ValueError('the window must have since < until')
    w = '`at` >= %d AND `at` < %d' % (since, until)
    t = TABLES
    return ';\n'.join([
        "SELECT 'hu', `band`, `voc`, SUM(`players`), SUM(`hunt_seconds`), SUM(`exp`), SUM(`kills`) FROM `%s` WHERE %s "
        "AND `voc` > 0 GROUP BY `band`, `voc`" % (t['hunt'], w),
        "SELECT 'cl', `band`, `voc`, SUM(`deaths`), SUM(`damage`) FROM `%s` WHERE %s AND `voc` > 0 GROUP BY `band`, `voc`"
        % (t['class'], w),
        "SELECT 'ca', `voc`, `spell`, SUM(`casts`) FROM `%s` WHERE %s AND `voc` > 0 GROUP BY `voc`, `spell`"
        % (t['casts'], w),
    ]) + ';'


def parse_rows(lines):
    cells = {}
    casts = {}
    for line in lines:
        p = line.rstrip('\r\n').split('\t')
        if not p or p[0] not in ('hu', 'cl', 'ca'):
            continue
        if p[0] == 'hu' and len(p) >= 7:
            c = cells.setdefault((p[1], num(p[2])), {})
            c.update(charHours=num(p[3]), seconds=num(p[4]), exp=num(p[5]), kills=num(p[6]))
        elif p[0] == 'cl' and len(p) >= 5:
            c = cells.setdefault((p[1], num(p[2])), {})
            c.update(deaths=num(p[3]), damage=num(p[4]))
        elif p[0] == 'ca' and len(p) >= 4:
            casts.setdefault(num(p[1]), []).append((p[2].replace('\\t', ' ').replace('\\n', ' ')[:64], num(p[3])))
    return cells, casts


def band_key(band):
    m = re.match(r'^(\d+)', band or '')
    return int(m.group(1)) if m else 10 ** 9


def vocations(spec):
    """"1:Mystic,3:Ranger,19:Iron Sage" (chaos-ctl.sh VOCATIONS) -> {1: "Mystic", ...}"""
    out = {}
    for part in (spec or '').split(','):
        if ':' in part:
            k, v = part.split(':', 1)
            if k.strip().isdigit() and v.strip():
                out[int(k)] = ''.join(c for c in v.strip() if c.isalnum() or c in " '-")[:32]
    return out


# ---------------------------------------------------------------- the analysis (pure)
def analyse(cells, casts, cfg):
    """-> {bands: [{band, median: {mpl, dph, dmg}, classes: [...]}], spells: {voc: [(spell, casts)]}}"""
    bands = {}
    for (band, voc), c in cells.items():
        secs = c.get('seconds', 0)
        hours = secs / 3600.0
        ch = c.get('charHours', 0)
        level = cfg['bandLevel'].get(band)
        exp = c.get('exp', 0)
        mpl = None
        if level and exp > 0 and secs > 0:
            mpl = exp_to_next(level) / (exp / (secs / 60.0))
        row = {'voc': voc, 'hours': round(hours, 1), 'charHours': SMALL if 0 < ch < MIN_SHOWN else ch,
               'minutesPerLevel': round(mpl, 1) if mpl is not None else None,
               'deathsPerHour': round(c.get('deaths', 0) / hours, 2) if hours > 0 else None,
               'damagePerHour': int(c.get('damage', 0) / hours) if hours > 0 else None,
               'damage': c.get('damage', 0), 'kills': c.get('kills', 0), 'deaths': c.get('deaths', 0)}
        row['compared'] = hours >= cfg['minHuntHours'] and ch >= max(MIN_SHOWN, cfg['minCharacterHours'])
        bands.setdefault(band, []).append(row)
    out = []
    for band in sorted(bands, key=band_key):
        rows = sorted(bands[band], key=lambda r: r['voc'])
        total_damage = sum(r['damage'] for r in rows if r['compared'])
        for r in rows:
            r['damageShare'] = round(100.0 * r['damage'] / total_damage, 1) if r['compared'] and total_damage > 0 else None
        cmp_rows = [r for r in rows if r['compared']]

        def med(key):
            vals = [r[key] for r in cmp_rows if r[key] is not None and (key != 'damagePerHour' or r[key] > 0)]
            return statistics.median(vals) if len(vals) >= cfg['minClasses'] else None
        out.append({'band': band, 'median': {'minutesPerLevel': med('minutesPerLevel'), 'deathsPerHour': med('deathsPerHour'),
                                             'damagePerHour': med('damagePerHour')}, 'classes': rows})
    spells = {}
    for voc, lst in casts.items():
        lst = sorted(lst, key=lambda x: (-x[1], x[0]))[:cfg['topSpells']]
        spells[voc] = [{'spell': s, 'casts': n} for s, n in lst if n > 0]
    return {'bands': out, 'spells': spells}


def suggested(ratio, cfg):
    """the change to suggest for a class `ratio` away from the median: a share of the gap, capped, in whole percent"""
    return max(1, int(round(100 * min(cfg['suggestMax'], abs(ratio - 1) * cfg['suggestShare']))))


def flags(analysis, cfg):
    """every compared class outside the thresholds: [{kind, band, voc, value, median, gapPct, suggestPct}]"""
    out = []
    tol, dtol = cfg['tolerance'], cfg['deathTolerance']
    for b in analysis['bands']:
        m = b['median']
        for r in b['classes']:
            if not r['compared']:
                continue

            def add(kind, value, median):
                ratio = value / median
                out.append({'kind': kind, 'band': b['band'], 'voc': r['voc'], 'value': value, 'median': median,
                            'gapPct': int(round(abs(ratio - 1) * 100)), 'suggestPct': suggested(ratio, cfg)})
            mpl, mm = r['minutesPerLevel'], m['minutesPerLevel']
            if mpl is not None and mm:
                if mpl > mm * (1 + tol):
                    add('slow', mpl, mm)
                elif mpl < mm * (1 - tol):
                    add('fast', mpl, mm)
            d, dm = r['deathsPerHour'], m['deathsPerHour']
            if d is not None and dm is not None and d >= cfg['minDeathsPerHour'] and d > max(dm, 1e-9) * (1 + dtol):
                add('deaths', d, max(dm, cfg['minDeathsPerHour']))
            g, gm = r['damagePerHour'], m['damagePerHour']
            if g and gm:
                if g < gm * (1 - tol):
                    add('damage_low', g, gm)
                elif g > gm * (1 + tol):
                    add('damage_high', g, gm)
    order = {'slow': 0, 'fast': 1, 'deaths': 2, 'damage_low': 3, 'damage_high': 4}
    out.sort(key=lambda f: (-f['gapPct'], order[f['kind']], band_key(f['band']), f['voc']))
    return out


# ---------------------------------------------------------------- output
def fmt_num(v, lang, digits=1):
    if v is None:
        return '-'
    s = ('%.' + str(digits) + 'f') % v if isinstance(v, float) else str(v)
    return s.replace('.', ',') if lang == 'pt' else s


def fmt_big(v, lang):
    if v is None:
        return '-'
    v = float(v)
    for div, suf in ((1e9, ' G'), (1e6, ' M'), (1e3, ' k')):
        if v >= div:
            return fmt_num(v / div, lang) + suf
    return fmt_num(int(v), lang)


def when(t):
    return time.strftime('%d/%m/%Y %Hh', time.localtime(t))


def build(cells, casts, cfg, since, until, title, vocs):
    a = analyse(cells, casts, cfg)
    return {'ok': True, 'title': title, 'since': int(since), 'until': int(until), 'thresholds': {
        'tolerance': cfg['tolerance'], 'deathTolerance': cfg['deathTolerance'], 'minHuntHours': cfg['minHuntHours']},
        'bands': a['bands'], 'spells': {str(k): v for k, v in sorted(a['spells'].items())}, 'flags': flags(a, cfg),
        'vocations': {str(k): v for k, v in sorted(vocs.items())}}


def text(res, lang):
    w = WORDS[lang]
    if not res.get('ok'):
        return w['error'] % res.get('error', 'error')
    names = {int(k): v for k, v in res.get('vocations', {}).items()}

    def cname(voc):
        return names.get(voc, w['class'] % voc)
    t = res['thresholds']
    out = ['# ' + w['title'] % res['title'], '',
           w['period'] % (when(res['since']), when(res['until']), int(round(t['tolerance'] * 100)),
                          int(round(t['deathTolerance'] * 100)), fmt_num(t['minHuntHours'], lang, 0)), '',
           '## ' + w['suggestions']]
    compared = any(r['compared'] for b in res['bands'] for r in b['classes'])
    if not compared:
        out.append(w['nodata'] % fmt_num(t['minHuntHours'], lang, 0))
    elif not res['flags']:
        out.append(w['none'])
    for f in res['flags']:
        if f['kind'] in ('slow', 'fast'):
            v, m = fmt_num(f['value'], lang), fmt_num(f['median'], lang)
        elif f['kind'] == 'deaths':
            v, m = fmt_num(f['value'], lang, 2), fmt_num(f['median'], lang, 2)
        else:
            v, m = fmt_big(f['value'], lang), fmt_big(f['median'], lang)
        out.append('- ' + w[f['kind']] % (cname(f['voc']), f['band'], f['gapPct'], v, m, f['suggestPct']))
    for b in res['bands']:
        m = b['median']
        out += ['', '## ' + w['band'] % (b['band'], fmt_num(m['minutesPerLevel'], lang),
                                         fmt_num(m['deathsPerHour'], lang, 2), fmt_big(m['damagePerHour'], lang))]
        for r in sorted(b['classes'], key=lambda r: (not r['compared'], cname(r['voc']))):
            share = '-' if r['damageShare'] is None else fmt_num(r['damageShare'], lang) + '%'
            out.append(w['row'] % (cname(r['voc']), fmt_num(r['minutesPerLevel'], lang),
                                   fmt_num(r['deathsPerHour'], lang, 2), fmt_big(r['damagePerHour'], lang), share,
                                   fmt_num(r['hours'], lang), r['charHours'], '' if r['compared'] else w['not_compared']))
    if res['spells']:
        out += ['', '## ' + w['spells']]
        for voc, lst in sorted(((int(k), v) for k, v in res['spells'].items()), key=lambda kv: cname(kv[0])):
            if lst:
                out.append(w['spell_row'] % (cname(voc), ', '.join('%s (%d)' % (s['spell'], s['casts']) for s in lst)))
    out += ['', w['damage_note']]
    return '\n'.join(out)


def save(res, lang, folder, name, keep):
    """NAME.md, NAME.json and latest.md in folder (written to a temporary file first); old balance-*.md beyond keep go"""
    if not NAME_RE.match(name):
        raise ValueError('bad name')
    os.makedirs(folder, mode=0o750, exist_ok=True)
    body = text(res, lang) + '\n'
    for fname, data in ((name + '.md', body), (name + '.json', json.dumps(res, ensure_ascii=False) + '\n'),
                        ('latest.md', body)):
        path = os.path.join(folder, fname)
        tmp = path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(data)
        os.replace(tmp, path)
    olds = sorted((f for f in os.listdir(folder) if f.startswith('balance-') and f.endswith('.md')), reverse=True)
    for f in olds[keep:]:
        for ext in ('.md', '.json'):
            p = os.path.join(folder, f[:-3] + ext)
            if os.path.exists(p):
                os.unlink(p)
    return os.path.join(folder, name + '.md')


# ---------------------------------------------------------------- main
def main(argv):
    if not argv or argv[0] not in ('windows-sql', 'window', 'due', 'sql', 'report'):
        sys.stderr.write(__doc__)
        return 2
    mode, args = argv[0], argv[1:]
    o = {'lang': 'en', 'json': False, 'now': int(time.time()), 'since': None, 'until': None, 'title': '',
         'vocations': '', 'seasons': None, 'season': None, 'dir': None, 'save': None, 'name': None, 'error': None,
         'config': CONFIG}
    i = 0
    try:
        while i < len(args):
            a = args[i]
            if a == '--pt':
                o['lang'] = 'pt'
            elif a == '--json':
                o['json'] = True
            elif a in ('--now', '--since', '--until') and i + 1 < len(args):
                i += 1
                o[a[2:]] = int(args[i])
            elif a in ('--title', '--vocations', '--seasons', '--season', '--dir', '--save', '--name', '--error',
                       '--config') and i + 1 < len(args):
                i += 1
                o[a[2:]] = args[i]
            else:
                raise ValueError('unknown argument ' + a)
            i += 1
        cfg = load_config(o['config'])
        if mode == 'windows-sql':
            print(windows_sql(read_seasons(o['seasons'])))
            return 0
        if mode in ('window', 'due'):
            wins = parse_windows(sys.stdin.read().splitlines(), read_seasons(o['seasons']))
            if mode == 'due':
                for sid in due(wins, o['now'], o['dir'], cfg['autoDays']):
                    print(sid)
                return 0
            w = pick_season(wins, o['season'] or 'current', o['now'])
            if not w or w['start'] > o['now']:
                sys.stderr.write('balance_report: no such season (or it has not started)\n')
                return 3
            name = ''.join(c for c in '%s %s' % (w['name'], w['tag']) if c.isalnum() or c in ' []-')[:60].strip()
            print('%d %d %d %s' % (w['start'], min(w['finish'], o['now']), w['id'], name))
            return 0
        if mode == 'sql':
            print(build_sql(o['since'], o['until']))
            return 0
    except (ValueError, OSError, TypeError) as e:
        sys.stderr.write('balance_report: %s\n' % e)
        return 2
    # report
    lang = o['lang']
    if o['error']:
        err = ''.join(c for c in o['error'] if c.isalnum() or c in '-_')[:32] or 'error'
        res = {'ok': False, 'error': err}
        print(json.dumps(res) if o['json'] else WORDS[lang]['error'] % err)
        return 1
    try:
        if o['since'] is None or o['until'] is None or o['until'] <= o['since']:
            raise ValueError('report needs --since and --until')
        title = ''.join(c for c in o['title'] if c.isalnum() or c in ' []-')[:60].strip()
        if not title:
            title = WORDS[lang]['days'] % max(1, int(round((o['until'] - o['since']) / 86400.0)))
        cells, casts = parse_rows(sys.stdin.read().splitlines())
        res = build(cells, casts, cfg, o['since'], o['until'], title, vocations(o['vocations']))
        if o['save']:
            save(res, lang, o['save'], o['name'] or time.strftime('balance-%Y%m%d-%H%M%S', time.localtime(o['now'])),
                 int(cfg['keep']))
    except (ValueError, OSError) as e:
        sys.stderr.write('balance_report: %s\n' % e)
        return 2
    print(json.dumps(res, ensure_ascii=False) if o['json'] else text(res, lang))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

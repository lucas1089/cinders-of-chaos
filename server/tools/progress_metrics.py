#!/usr/bin/env python3
"""Progress metrics report (server/README.md "Progress metrics (O253)"): chaos-ctl.sh metrics.

Reads the rows of the table chaos_progress_metrics from stdin (tab separated: kind, k1, k2, n; what
`SELECT kind, k1, k2, n FROM chaos_progress_metrics` prints with mysql -N -B) and writes one JSON object (--json) or a
text summary. The rows are aggregate counters; no name, account or IP is in them (data/scripts/chaos/metrics_core.lua).

  churn          per level band: characters gone (last login older than churn days) and active
  deathAreas     the 10 areas with the most deaths (top level band of each)
  deathMonsters  the 10 killers with the most deaths (top level band of each)
  firstSession   characters per minutes bucket of the first session
  milestones     median played minutes to reach each milestone level, read from the time buckets by interpolation

Small numbers: a count of 1 to 4 (a band, an area, a monster, a bucket, a milestone) is written "<5" in the text and as
the string "<5" in the JSON, with its percentage, median and top band left out (null or empty). 0 stays 0.

usage: progress_metrics.py [--json] [--top N] [--error CODE]  < rows
       --error CODE writes {"ok": false, "error": CODE} (the database could not be read)
"""
import json
import sys

TOP = 10
# small-number suppression: a count of 1 to MIN_SHOWN - 1 is shown as SMALL (text and JSON), never exactly. Zero is
# shown as 0 (nobody there). The percentages and medians of a hidden count are hidden with it (null in JSON).
MIN_SHOWN = 5
SMALL = '<%d' % MIN_SHOWN


def hide(n):
    """n, or SMALL when 0 < n < MIN_SHOWN"""
    return SMALL if 0 < n < MIN_SHOWN else n


def num(s, default=0):
    try:
        return int(s)
    except (TypeError, ValueError):
        return default


def band_start(label):
    """1 for '1-5', 901 for '901+'; unknown labels last"""
    head = ''.join(ch for ch in str(label).split('-')[0].split('+')[0] if ch.isdigit())
    return int(head) if head else 10 ** 9


def bucket_limit(label):
    """minutes of a bucket's upper limit; 'inf' (open) is None"""
    return None if label == 'inf' else num(label, None)


def parse(lines):
    rows = []
    for line in lines:
        parts = line.rstrip('\r\n').split('\t')
        if len(parts) < 4:
            continue
        rows.append((parts[0], parts[1], parts[2], num(parts[3])))
    return rows


def median(buckets):
    """buckets: [(upper limit in minutes or None for open, count)] -> (median minutes or None, total)

    The lower limit of a bucket is the upper limit of the one before; the median is placed inside its bucket by linear
    interpolation. The open bucket has no upper limit: its median is its lower limit (a lower bound).
    """
    ordered = sorted(buckets, key=lambda b: (b[0] is None, b[0] or 0))
    total = sum(c for _, c in ordered)
    if total <= 0:
        return None, 0
    half = total / 2.0
    seen = 0
    lo = 0
    for hi, count in ordered:
        if count > 0 and seen + count >= half:
            if hi is None:
                return float(lo), total
            return round(lo + (hi - lo) * (half - seen) / count, 1), total
        seen += count
        if hi is not None:
            lo = hi
    return None, total


def top(rows, kind, limit):
    by = {}
    for k, k1, k2, n in rows:
        if k == kind and n > 0:
            e = by.setdefault(k1, {'name': k1, 'deaths': 0, 'bands': {}})
            e['deaths'] += n
            e['bands'][k2] = e['bands'].get(k2, 0) + n
    out = []
    for e in by.values():
        best = sorted(e['bands'].items(), key=lambda kv: (-kv[1], band_start(kv[0])))[0]
        out.append({'name': e['name'], 'deaths': e['deaths'], 'topBand': best[0], 'topBandDeaths': best[1]})
    out.sort(key=lambda e: (-e['deaths'], e['name']))
    out = out[:limit]
    for e in out:
        if hide(e['deaths']) == SMALL:
            # a handful of deaths in one level band can point at one character: no band either
            e['topBand'] = ''
            e['topBandDeaths'] = SMALL
        else:
            e['topBandDeaths'] = hide(e['topBandDeaths'])
        e['deaths'] = hide(e['deaths'])
    return out


def report(rows, limit=TOP):
    meta = {k1: n for k, k1, k2, n in rows if k == 'meta'}
    bands = {}
    for k, k1, k2, n in rows:
        if k == 'churn' and k2 in ('gone', 'active'):
            bands.setdefault(k1, {'band': k1, 'gone': 0, 'active': 0})[k2] += n
    churn_rows = []
    for b in sorted(bands.values(), key=lambda b: band_start(b['band'])):
        total = b['gone'] + b['active']
        b['total'] = total
        b['gonePct'] = round(100.0 * b['gone'] / total, 1) if total else 0.0
        churn_rows.append(b)
    gone = sum(b['gone'] for b in churn_rows)
    active = sum(b['active'] for b in churn_rows)
    for b in churn_rows:
        # a band of fewer than 5, or one side of it, is not shown; the share would give it away
        if hide(b['total']) == SMALL or hide(b['gone']) == SMALL or hide(b['active']) == SMALL:
            b['gonePct'] = None
        b['gone'], b['active'], b['total'] = hide(b['gone']), hide(b['active']), hide(b['total'])
    gone, active = hide(gone), hide(active)

    sess = {}
    for k, k1, k2, n in rows:
        if k == 'session1':
            sess[k1] = sess.get(k1, 0) + n
    sess_total = sum(sess.values())
    first = []
    for label in sorted(sess, key=lambda s: (bucket_limit(s) is None, bucket_limit(s) or 0)):
        small = hide(sess[label]) == SMALL
        first.append({'bucket': label, 'characters': hide(sess[label]),
                      'pct': None if small else (round(100.0 * sess[label] / sess_total, 1) if sess_total else 0.0)})

    ttl = {}
    for k, k1, k2, n in rows:
        if k == 'ttl':
            ttl.setdefault(num(k1), []).append((bucket_limit(k2), n))
    milestones = []
    for level in sorted(ttl):
        med, total = median(ttl[level])
        small = hide(total) == SMALL
        milestones.append({'level': level, 'medianMinutes': None if small else med, 'characters': hide(total)})

    return {
        'ok': True,
        'churn': {'days': meta.get('churn_days', 0), 'at': meta.get('churn_at', 0), 'gone': gone, 'active': active,
                  'bands': churn_rows},
        'deathAreas': top(rows, 'death_area', limit),
        'deathMonsters': top(rows, 'death_monster', limit),
        'firstSession': first,
        'firstSessionCharacters': hide(sess_total),
        'milestones': milestones,
        'empty': not rows,
    }


def minutes_text(m):
    if m is None:
        return 'no data'
    m = float(m)
    if m < 90:
        return '%d min' % round(m)
    if m < 48 * 60:
        return '%.1f h' % (m / 60.0)
    return '%.1f days' % (m / 1440.0)


def text(rep):
    if not rep.get('ok'):
        return 'metrics: %s\n' % rep.get('error', 'error')
    out = []
    c = rep['churn']
    out.append('Churn (gone = no login for %d days; %s gone, %s active)' % (c['days'], c['gone'], c['active']))
    for b in c['bands']:
        pct = '%5.1f%% gone' % b['gonePct'] if b['gonePct'] is not None else '   n/a'
        out.append('  %-9s gone %5s  active %5s  %s' % (b['band'], b['gone'], b['active'], pct))
    for title, key in (('Deaths by area', 'deathAreas'), ('Deaths by monster', 'deathMonsters')):
        out.append(title)
        for e in rep[key]:
            where = ' (most at level %s)' % e['topBand'] if e['topBand'] else ''
            out.append('  %6s  %s%s' % (e['deaths'], e['name'], where))
    out.append('First session (%s new characters)' % rep['firstSessionCharacters'])
    for e in rep['firstSession']:
        label = 'longer' if e['bucket'] == 'inf' else 'up to %s min' % e['bucket']
        share = '%.1f%%' % e['pct'] if e['pct'] is not None else SMALL
        out.append('  %s: %s (%s)' % (label, e['characters'], share))
    out.append('Median time to level')
    for m in rep['milestones']:
        out.append('  level %d: %s (%s characters)' % (m['level'], minutes_text(m['medianMinutes']), m['characters']))
    return '\n'.join(out) + '\n'


def main(argv):
    as_json, limit, error = False, TOP, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--json':
            as_json = True
        elif a == '--top' and i + 1 < len(argv):
            i += 1
            limit = max(1, min(50, num(argv[i], TOP)))
        elif a == '--error' and i + 1 < len(argv):
            i += 1
            error = argv[i][:40]
        else:
            sys.stderr.write('usage: progress_metrics.py [--json] [--top N] [--error CODE]\n')
            return 2
        i += 1
    rep = {'ok': False, 'error': error} if error else report(parse(sys.stdin), limit)
    sys.stdout.write((json.dumps(rep, sort_keys=True) + '\n') if as_json else text(rep))
    return 1 if error else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

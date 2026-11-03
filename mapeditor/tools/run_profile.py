#!/usr/bin/env python3
"""Timing runs of our map editor builds on one map: load time, memory and frame times while panning.

    python3 -I mapeditor/tools/run_profile.py --build LABEL=EXE [--build LABEL=EXE ...] --map MAP.otbm
        --client CLIENT_DIR [--version 1098] [--runs 3] [--pan-seconds 8] [--timeout 600]
        [--scenario NAME=ARGS ...] [--logs DIR] [--markdown OUT.md] [--json OUT.json]
    python3 -I mapeditor/tools/run_profile.py --parse LOG     # one log: the parsed record as JSON

Each run starts EXE with the editor's load profile (--load-profile, --profile-map/-client/-version, --profile-exit)
and the pan mode of patch 0001 (--profile-pan SECONDS plus the scenario's view options), reads the timing records the
editor writes on stderr (lines "<TAG>_LOAD elapsed_ms=.. duration_ms=.. peak_ram_bytes=.. stage=.. details") and
reports the median of the runs per build and scenario. Builds run in turn (A, B, A, B, ...) so a slow minute of the
runner hits both. QSG_NO_VSYNC=1 is set so frame times are not capped by the display.

Scenarios (--scenario replaces the defaults):
  surface   floor 7, the settings' zoom, lighting and item animation on
  zoomedout tile size 8 (a quarter of the 32 px zoom), floor 5 with the lower floors, lighting and animation on

Exit status 0 when every build has at least one complete run of every scenario, 1 otherwise, 2 usage.
Test: mapeditor/tools/run_profile_test.py."""
import json
import os
import re
import statistics
import subprocess
import sys
import time

LINE = re.compile(r'^[A-Z]+_LOAD elapsed_ms=(\d+) duration_ms=(-?\d+) peak_ram_bytes=(\d+) stage=(\S+) ?(.*)$')
PAIR = re.compile(r'(\w+)=(\S+)')
DEFAULT_SCENARIOS = [
    ('surface', ['--profile-floor', '7', '--profile-lighting', '1', '--profile-animations', '1']),
    ('zoomedout', ['--profile-tile-size', '8', '--profile-floor', '5', '--profile-lower-floors', '1',
                   '--profile-lighting', '1', '--profile-animations', '1']),
]
PAN_KEYS = ('frames', 'fps', 'avg_ms', 'p50_ms', 'p95_ms', 'p99_ms', 'worst_ms')


def parse_log(text):
    """the records of one run: stages (name -> duration ms, the first one), ready time, peak RAM, pan numbers"""
    out = {'stages': {}, 'ready_ms': None, 'peak_ram_bytes': 0, 'pan': None, 'counts': {}, 'errors': []}
    for raw in text.splitlines():
        m = LINE.match(raw.strip())
        if not m:
            if re.search(r'Device loss detected|Graphics device lost|Failed to create buffer', raw):
                out['errors'].append(raw.strip())
            continue
        elapsed, duration, peak, stage, details = int(m[1]), int(m[2]), int(m[3]), m[4], m[5]
        out['peak_ram_bytes'] = max(out['peak_ram_bytes'], peak)
        if duration >= 0 and stage not in out['stages'] and stage != 'map_pan_complete':
            out['stages'][stage] = duration
        if stage == 'first_complete_frame' and out['ready_ms'] is None:
            out['ready_ms'] = elapsed
        if stage in ('map_counts', 'map_sprite_counts', 'atlas_counts') and stage not in out['counts']:
            out['counts'][stage] = dict(PAIR.findall(details))
        if stage == 'map_pan_complete':
            values = dict(PAIR.findall(details))
            pan = {k: float(values[k]) for k in PAN_KEYS if k in values}
            pan['peak_ram_bytes'] = peak
            out['pan'] = pan
        if stage == 'readiness_timeout':
            out['errors'].append('readiness timeout')
    return out


def median(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def summarize(runs):
    """runs: parsed records of one build and scenario -> medians"""
    done = [r for r in runs if r['ready_ms'] is not None and r['pan'] and not r['errors']]
    result = {'runs': len(runs), 'complete': len(done)}
    if not done:
        return result
    result['ready_ms'] = median([r['ready_ms'] for r in done])
    result['peak_ram_bytes'] = median([r['peak_ram_bytes'] for r in done])
    for key in PAN_KEYS:
        result[key] = median([r['pan'].get(key) for r in done])
    stages = {}
    for r in done:
        for name, ms in r['stages'].items():
            stages.setdefault(name, []).append(ms)
    result['stages'] = {name: median(v) for name, v in stages.items()}
    result['counts'] = done[0]['counts']
    return result


def fmt(value, digits=0):
    if value is None:
        return '-'
    return ('%.' + str(digits) + 'f') % value


def change(base, new, lower_is_better=True):
    if base in (None, 0) or new is None:
        return ''
    pct = (new - base) * 100.0 / base
    better = pct < 0 if lower_is_better else pct > 0
    return ' (%+.0f%%%s)' % (pct, '' if abs(pct) < 1 else (' better' if better else ' worse'))


def markdown(summary, labels, scenarios, meta):
    lines = ['## Map editor profile', '']
    for key, value in meta:
        lines.append('- %s: %s' % (key, value))
    lines.append('')
    base = labels[0]
    for name, _args in scenarios:
        lines += ['### Scenario %s' % name, '',
                  '| build | runs ok | ready s | peak RAM MiB | frames | fps | avg ms | p50 ms | p95 ms | p99 ms | worst ms |',
                  '|---|---|---|---|---|---|---|---|---|---|---|']
        for label in labels:
            s = summary[label][name]
            b = summary[base][name] if label != base else {}
            ram = s.get('peak_ram_bytes')
            lines.append('| %s | %d/%d | %s%s | %s%s | %s | %s%s | %s%s | %s | %s%s | %s | %s%s |' % (
                label, s['complete'], s['runs'],
                fmt(s.get('ready_ms') and s['ready_ms'] / 1000.0, 2), change(b.get('ready_ms'), s.get('ready_ms')),
                fmt(ram and ram / 1048576.0), change(b.get('peak_ram_bytes'), ram),
                fmt(s.get('frames')),
                fmt(s.get('fps'), 1), change(b.get('fps'), s.get('fps'), lower_is_better=False),
                fmt(s.get('avg_ms'), 2), change(b.get('avg_ms'), s.get('avg_ms')),
                fmt(s.get('p50_ms'), 2),
                fmt(s.get('p95_ms'), 2), change(b.get('p95_ms'), s.get('p95_ms')),
                fmt(s.get('p99_ms'), 2),
                fmt(s.get('worst_ms'), 2), change(b.get('worst_ms'), s.get('worst_ms'))))
        lines.append('')
    first = scenarios[0][0]
    names = sorted({n for label in labels for n in summary[label][first].get('stages', {})})
    if names:
        lines += ['### Load stages (ms, median, scenario %s)' % first, '',
                  '| stage | ' + ' | '.join(labels) + ' |', '|---|' + '---|' * len(labels)]
        for n in names:
            lines.append('| %s | %s |' % (n, ' | '.join(
                fmt(summary[label][first].get('stages', {}).get(n)) for label in labels)))
        lines.append('')
    counts = summary[labels[-1]][first].get('counts') or {}
    if counts:
        lines += ['### Map and atlas counts (%s)' % labels[-1], '']
        for stage, values in sorted(counts.items()):
            lines.append('- %s: %s' % (stage, ', '.join('%s=%s' % kv for kv in sorted(values.items()))))
        lines.append('')
    return '\n'.join(lines) + '\n'


def run_once(exe, args, timeout, log_path):
    env = dict(os.environ)
    env['QSG_NO_VSYNC'] = '1'
    env.setdefault('QT_FORCE_STDERR_LOGGING', '1')
    started = time.monotonic()
    try:
        proc = subprocess.run([exe] + args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                              env=env, timeout=timeout, cwd=os.path.dirname(os.path.abspath(exe)))
        text, code = proc.stderr.decode('utf-8', 'replace'), proc.returncode
    except subprocess.TimeoutExpired as e:
        text, code = (e.stderr or b'').decode('utf-8', 'replace'), 'timeout'
    except OSError as e:
        text, code = '', 'not started (%s)' % e
    with open(log_path, 'w', encoding='utf-8') as f:
        f.write(text)
    record = parse_log(text)
    if code != 0:
        record['errors'].append('exit %s' % code)
    record['seconds'] = round(time.monotonic() - started, 1)
    return record


def main(argv):
    opts = {'--version': '1098', '--runs': '3', '--pan-seconds': '8', '--timeout': '600', '--logs': 'profile-logs'}
    builds, scenarios = [], []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--parse' and i + 1 < len(argv):
            with open(argv[i + 1], encoding='utf-8', errors='replace') as f:
                print(json.dumps(parse_log(f.read()), indent=1))
            return 0
        if i + 1 >= len(argv):
            print(__doc__, file=sys.stderr)
            return 2
        value = argv[i + 1]
        if a == '--build':
            label, _, exe = value.partition('=')
            builds.append((label, exe))
        elif a == '--scenario':
            name, _, args = value.partition('=')
            scenarios.append((name, args.split()))
        elif a in ('--map', '--client', '--version', '--runs', '--pan-seconds', '--timeout', '--logs',
                   '--markdown', '--json'):
            opts[a] = value
        else:
            print('unknown option %s\n%s' % (a, __doc__), file=sys.stderr)
            return 2
        i += 2
    if not builds or '--map' not in opts or '--client' not in opts:
        print(__doc__, file=sys.stderr)
        return 2
    scenarios = scenarios or DEFAULT_SCENARIOS
    os.makedirs(opts['--logs'], exist_ok=True)
    records = {label: {name: [] for name, _a in scenarios} for label, _e in builds}
    for run in range(int(opts['--runs'])):
        for name, extra in scenarios:
            for label, exe in builds:
                args = ['--load-profile', '--profile-map', os.path.abspath(opts['--map']),
                        '--profile-client', os.path.abspath(opts['--client']),
                        '--profile-version', opts['--version'], '--profile-pan', opts['--pan-seconds'],
                        '--profile-timeout', opts['--timeout'], '--profile-exit'] + extra
                log = os.path.join(opts['--logs'], '%s-%s-%d.log' % (label, name, run + 1))
                r = run_once(exe, args, int(opts['--timeout']) + 60, log)
                records[label][name].append(r)
                print('%s %s run %d: ready_ms=%s pan=%s errors=%s (%ss)' % (
                    label, name, run + 1, r['ready_ms'], r['pan'], r['errors'], r['seconds']), flush=True)
    summary = {label: {name: summarize(records[label][name]) for name, _a in scenarios} for label, _e in builds}
    meta = [('map', os.path.basename(opts['--map'])), ('client version', opts['--version']),
            ('runs per build and scenario', opts['--runs']), ('pan', '%s s per run' % opts['--pan-seconds']),
            ('scenarios', '; '.join('%s: %s' % (n, ' '.join(a)) for n, a in scenarios))]
    text = markdown(summary, [label for label, _e in builds], scenarios, meta)
    print(text)
    if '--markdown' in opts:
        with open(opts['--markdown'], 'w', encoding='utf-8') as f:
            f.write(text)
    if '--json' in opts:
        with open(opts['--json'], 'w', encoding='utf-8') as f:
            json.dump(summary, f, indent=1, sort_keys=True)
    ok = all(summary[label][name]['complete'] > 0 for label, _e in builds for name, _a in scenarios)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

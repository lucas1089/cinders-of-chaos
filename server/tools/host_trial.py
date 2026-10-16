#!/usr/bin/env python3
"""Host trial: decide in one day whether a rented VPS stays (KEEP), needs a bigger plan (UPGRADE) or goes back (REFUND).

Standard library only (Python 3.7+). Run through server/tools/host_trial.sh as root on the fresh VPS (docs/HOST_TRIAL.md).
Commands:
  run          the host check: CPU, steal time, single-core speed, RAM, disk fsync, memory bandwidth, network
                 python3 -I server/tools/host_trial.py run [--window-min 30] [--step-s 10] [--out DIR] ...
                 (--help lists every threshold; each has a default below)
  sample FILE  the load test's sampler: one JSON line every --step-s s with /proc/stat, /proc/meminfo and the CPU
               time of --exclude-pid (the bots); host_trial_load.sh starts and stops it
  load-report  the verdict of one load test run: the loadtest.py output, the sampler file and the server log
                 python3 -I server/tools/host_trial.py load-report --count 300 --loadtest-out F --samples F
                     [--server-log F --since T] [--out DIR]
  proxy-probe HOST PORT  send one PROXY v2 header to our own game server and say whether it answered (a check
               for the gateways, docs/HOST_TRIAL.md); touches only HOST
  bench-py N   internal: the single-core Python workload (host_trial.sh pins it with taskset)

Safety: the run command reads /proc and /sys, runs a CPU loop on each vCPU of this machine, writes only into a temp
dir that it deletes at the end, and sends ping (ICMP) to a few public hosts in Brazil. No other traffic leaves the box.

Verdicts per item: KEEP, BORDERLINE, UPGRADE (the plan is too small: RAM or vCPU count; the bigger plan of the same
host keeps the same machine type), REFUND (bad CPU or disk), INFO (shown, not judged). Overall: REFUND when a CPU or
disk item says REFUND; UPGRADE when an item says UPGRADE and every CPU item says KEEP; else the worst of the rest.
"""
import json
import os
import re
import shutil
import signal
import socket
import statistics
import struct
import subprocess
import sys
import tempfile
import time

KEEP, BORDERLINE, UPGRADE, REFUND, INFO = 'KEEP', 'BORDERLINE', 'UPGRADE', 'REFUND', 'INFO'
RANK = {INFO: -1, KEEP: 0, BORDERLINE: 1, UPGRADE: 2, REFUND: 3}

# Default plan: Hypehost "Magic Sword" (6 vCPU Ryzen 9, 16 GB, 200 GB NVMe). Golden Boots is 10 vCPU, 32 GB, 340 GB.
PLANS = {
    'magic-sword': {'vcpu': 6, 'ram_gb': 16, 'disk_gb': 200},
    'golden-boots': {'vcpu': 10, 'ram_gb': 32, 'disk_gb': 340},
}

DEFAULTS = {
    'plan': 'magic-sword',
    'window_min': 30.0,       # steal sampling window
    'step_s': 10.0,           # one /proc/stat sample per step
    'bench_runs': 7,          # single-core runs spread over the window
    'steal_mean_max': 2.0,    # % of CPU time, whole machine, mean of the steps
    'steal_p95_max': 5.0,     # % p95 of the steps; also the limit for the worst single vCPU's mean
    'single_min': 0.85,       # median single-core speed as a share of a Ryzen 9 7950X; KEEP at or above
    'single_borderline': 0.70,  # BORDERLINE at or above, REFUND below
    'noise_max': 15.0,        # worst run at most this % slower than the median (noisy neighbours)
    'fsync_p99_max': 5.0,     # ms
    'seq_min_mbs': 300.0,     # MB/s sequential write; below: BORDERLINE
    'mem_min_gbs': 4.0,       # GB/s single-thread memcpy; below: BORDERLINE
    'ping_max_ms': 15.0,      # avg RTT to the nearest Brazilian anchor
    'min_vcpu': 4,            # fewer vCPU than this cannot run game, database, logins and services side by side
    'game_ram_gb': 6.0,       # engine RSS: 4.65-4.8 GB at 300-400 bots, 4.7 GB at 700, plus room
    'os_ram_gb': 2.0,         # system, client services, pay worker, web, backups
    'min_pool_gb': 1.0,       # smallest sensible MariaDB buffer pool
    'max_pool_gb': 8.0,       # the game database is small; more pool than this buys nothing
    'ram_min_free_gb': 2.0,   # load test: MemAvailable must stay above this plus the pool still to be given
    'swap_growth_mb': 256.0,  # load test: more swap use than this during the run means RAM is short
    'cpu_busy_max': 85.0,     # load test: whole machine busy p95 (bots excluded); above: the vCPU count is the limit
    'lag_avg_max': 65.0,      # load test: probe lag avg at full load, ms (the engine's timer floor is about 50)
    'thread_max': 85.0,       # load test: game loop thread avg % of one core
    'login_min_share': 0.95,  # load test: share of the bots that must enter the game
    'fio_runtime': 60,
    'seq_mb': 2048,
    'ping_count': 20,
}

PING_HOSTS = ['registro.br', 'www.usp.br', 'www.unicamp.br', 'www.ufrj.br', 'www.ufrgs.br']

# Single-core workloads. Checksums prove the run did the full work. CAL_S: seconds on the calibration machine (cloud
# Intel Xeon, Cascade Lake class, 2.8 GHz, Python 3.13, LuaJIT 2.1, Lua 5.3; measured 2026-10-16).
# CAL_TO_7950X: how much faster a Ryzen 9 7950X core is than that core. Approximate, from public single-thread
# benchmark ratios; calibrate it once on a known machine if the verdict matters at the edge.
BENCH = {
    'python': {'n': 6000000, 'sum': 14353390, 'cal_s': 2.36},
    'luajit': {'n': 60000000, 'sum': 143503781, 'cal_s': 1.88},
    'lua': {'n': 15000000, 'sum': 35878158, 'cal_s': 1.96},
}
CAL_TO_7950X = 1.8

# Approximate single-thread speed relative to a Ryzen 9 7950X (public single-thread benchmark ratios, rounded;
# Python and Lua loops follow them only roughly). Used to tell a 5900X from a 9950X.
CPU_RATIO = [
    ('9950X3D', 1.09), ('9950X', 1.10), ('9900X3D', 1.08), ('9900X', 1.09), ('9700X', 1.07), ('9600X', 1.05),
    ('7950X3D', 0.97), ('7950X', 1.00), ('7900X3D', 0.96), ('7900X', 0.98), ('7900', 0.93), ('7700X', 0.98),
    ('5950X', 0.82), ('5900XT', 0.82), ('5900X', 0.81), ('5900', 0.78), ('5800X3D', 0.76), ('5800X', 0.81),
    ('5700X', 0.78), ('5600X', 0.79), ('5500', 0.71),
]
REF_LINES = [
    ('Ryzen 9 9950X (Zen 5)', 1.10), ('Ryzen 9 7950X (Zen 4)', 1.00), ('Ryzen 9 5900X (Zen 3)', 0.81),
    ('Ryzen 5 5500 (Zen 3)', 0.71), ('calibration Xeon 2.8 GHz', round(1 / CAL_TO_7950X, 2)),
    ('earlier load test box, Xeon 2.1 GHz', 0.50),
]

# ---------------------------------------------------------------- pure helpers (host_trial_test.py)


def percentile(values, p):
    """Linear interpolation between closest ranks; 0 for an empty list."""
    if not values:
        return 0.0
    s = sorted(values)
    if len(s) == 1:
        return float(s[0])
    k = (len(s) - 1) * p / 100.0
    lo = int(k)
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def parse_proc_stat(text):
    """{'cpu': [user, nice, system, idle, iowait, irq, softirq, steal], 'cpu0': [...], ...} (guest time is already
    in user, so the guest columns are left out)."""
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if parts and parts[0].startswith('cpu'):
            vals = [int(v) for v in parts[1:9]]
            vals += [0] * (8 - len(vals))
            out[parts[0]] = vals
    return out


def steal_pct(prev, cur):
    """{cpu: steal % of the time between two parse_proc_stat() samples}"""
    out = {}
    for name, c in cur.items():
        p = prev.get(name)
        if not p:
            continue
        total = sum(c) - sum(p)
        out[name] = 100.0 * (c[7] - p[7]) / total if total > 0 else 0.0
    return out


def busy_pct(prev, cur, name='cpu'):
    """% of the time not idle and not iowait, of one /proc/stat line between two samples"""
    p, c = prev.get(name), cur.get(name)
    if not p or not c:
        return 0.0
    total = sum(c) - sum(p)
    idle = (c[3] + c[4]) - (p[3] + p[4])
    return 100.0 * (total - idle) / total if total > 0 else 0.0


def summarize(values):
    return {'mean': statistics.mean(values) if values else 0.0, 'p95': percentile(values, 95),
            'max': max(values) if values else 0.0, 'n': len(values)}


def summarize_steal(samples):
    """samples: parse_proc_stat() dicts in time order -> {'cpu': summary, 'cpu0': summary, ...}"""
    per = {}
    for a, b in zip(samples, samples[1:]):
        for name, v in steal_pct(a, b).items():
            per.setdefault(name, []).append(v)
    return {name: summarize(v) for name, v in per.items()}


def parse_cpuinfo(text):
    """{'model', 'vendor', 'family', 'model_id', 'mhz': [..], 'flags': set, 'count'} of the first processor block"""
    info = {'model': '', 'vendor': '', 'family': None, 'model_id': None, 'mhz': [], 'flags': set(), 'count': 0}
    for line in text.splitlines():
        if ':' not in line:
            continue
        key, val = [x.strip() for x in line.split(':', 1)]
        if key == 'processor':
            info['count'] += 1
        elif key == 'model name' and not info['model']:
            info['model'] = val
        elif key == 'vendor_id' and not info['vendor']:
            info['vendor'] = val
        elif key == 'cpu family' and info['family'] is None:
            info['family'] = int(val) if val.isdigit() else None
        elif key == 'model' and info['model_id'] is None:
            info['model_id'] = int(val) if val.isdigit() else None
        elif key == 'cpu MHz':
            try:
                info['mhz'].append(float(val))
            except ValueError:
                pass
        elif key == 'flags' and not info['flags']:
            info['flags'] = set(val.split())
    return info


GENERIC_MODEL = re.compile(r'qemu|kvm|virtual|common|generic|host cpu', re.I)


def passthrough(info):
    """True when the guest sees the real CPU model name (not a generic QEMU / KVM model)"""
    return bool(info['model']) and not GENERIC_MODEL.search(info['model'])


def amd_generation(info):
    """Zen generation from family/model/flags (works when the model name is hidden): 'Zen 5', 'Zen 4', 'Zen 3' or ''"""
    fam, mod, flags = info.get('family'), info.get('model_id'), info.get('flags') or set()
    if info.get('vendor') not in ('AuthenticAMD', ''):
        return ''
    if fam == 26:
        return 'Zen 5'
    if fam == 25:
        if mod is not None and 0x60 <= mod <= 0x7f or 'avx512f' in flags:
            return 'Zen 4'
        return 'Zen 3'
    return ''


def expected_ratio(model):
    """(name, approximate single-core ratio to a 7950X) for a known model name, else (None, None)"""
    for name, ratio in CPU_RATIO:
        if re.search(r'\b%s\b' % re.escape(name), model or '', re.I):
            return name, ratio
    return None, None


def parse_meminfo(text):
    """{key: kB} of /proc/meminfo"""
    out = {}
    for line in text.splitlines():
        m = re.match(r'(\w+):\s+(\d+)', line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def buffer_pool_gb(total_gb, t=DEFAULTS):
    """innodb_buffer_pool_size that fits next to the game server: half of what the engine and the system leave,
    between min_pool_gb and max_pool_gb, rounded down to 0.5 GB. 0 when not even min_pool_gb fits."""
    left = total_gb - t['game_ram_gb'] - t['os_ram_gb']
    if left < t['min_pool_gb'] * 2:
        return 0.0
    pool = min(t['max_pool_gb'], max(t['min_pool_gb'], left / 2.0))
    return int(pool * 2) / 2.0


def lower_better(value, limit, factor=2.0, bad=REFUND):
    """KEEP at or under limit, BORDERLINE up to limit * factor, else bad"""
    if value <= limit:
        return KEEP
    return BORDERLINE if value <= limit * factor else bad


def worst(*verdicts):
    vs = [v for v in verdicts if v != INFO]
    return max(vs, key=lambda v: RANK[v]) if vs else INFO


def verdict_steal(summary, t=DEFAULTS):
    allc = summary.get('cpu', summarize([]))
    per = [s['mean'] for k, s in summary.items() if k != 'cpu']
    return worst(lower_better(allc['mean'], t['steal_mean_max']), lower_better(allc['p95'], t['steal_p95_max']),
                 lower_better(max(per or [0]), t['steal_p95_max']))


def verdict_single(ratio, noise_pct, t=DEFAULTS):
    """ratio: median speed as a share of a 7950X; noise_pct: how much slower the worst run was than the median"""
    if ratio is None:
        return INFO
    v = KEEP if ratio >= t['single_min'] else BORDERLINE if ratio >= t['single_borderline'] else REFUND
    return worst(v, lower_better(noise_pct, t['noise_max']))


def verdict_fsync(p99_ms, t=DEFAULTS):
    return INFO if p99_ms is None else lower_better(p99_ms, t['fsync_p99_max'])


def verdict_vcpu(n, expect, t=DEFAULTS):
    """fewer than min_vcpu: the plan is too small (UPGRADE); fewer than the plan promises: BORDERLINE (ask support)"""
    if n < t['min_vcpu']:
        return UPGRADE
    return BORDERLINE if n < expect else KEEP


def verdict_ram(total_gb, expect_gb, t=DEFAULTS):
    """UPGRADE when the game server, the system and a minimal buffer pool do not fit; BORDERLINE when the machine
    has clearly less than the plan promises (the kernel keeps a few hundred MB, so 90% is the bar)"""
    if buffer_pool_gb(total_gb, t) == 0:
        return UPGRADE
    return BORDERLINE if total_gb < expect_gb * 0.9 else KEEP


def overall(items):
    """items: [{'kind': 'cpu'|'disk'|'capacity'|'other', 'verdict': ...}]. REFUND only for CPU or disk; UPGRADE only
    when every CPU item is KEEP (a bigger plan of the same machine type would not fix a slow or stolen core)."""
    def of(kind):
        return [i['verdict'] for i in items if i['kind'] == kind and i['verdict'] != INFO]
    hard = of('cpu') + of('disk')
    if REFUND in hard:
        return REFUND
    cpu_ok = all(v == KEEP for v in of('cpu'))
    rest = [i['verdict'] for i in items if i['verdict'] not in (INFO, UPGRADE)]
    if any(i['verdict'] == UPGRADE for i in items):
        return UPGRADE if cpu_ok else BORDERLINE
    return worst(KEEP, *[v if v != REFUND else BORDERLINE for v in rest])


def _fio_json(text):
    """fio may print warnings before its JSON"""
    i = text.find('{')
    if i < 0:
        raise ValueError('no JSON in the fio output')
    return json.loads(text[i:])


def _lat_ms(section):
    """(p50, p99, mean) in ms of a fio latency block (lat_ns in fio 3, lat in usec in old versions)"""
    if 'lat_ns' in section:
        block, div = section['lat_ns'], 1e6
    elif 'clat_ns' in section:
        block, div = section['clat_ns'], 1e6
    elif 'lat' in section:
        block, div = section['lat'], 1e3
    else:
        return None
    pc = block.get('percentile') or {}

    def at(p):
        for k, v in pc.items():
            if abs(float(k) - p) < 1e-6:
                return v / div
        return None
    return at(50.0), at(99.0), block.get('mean', 0) / div


def parse_fio_fsync(text):
    """{'p50_ms', 'p99_ms', 'mean_ms', 'iops'} of the fsync of a --fsync=1 write job. fio puts the fsync latency in the
    job's 'sync' block; without percentiles there, the write completion latency is used (each write waits for its
    fsync with --fsync=1 only in 'sync', so this is a fallback)."""
    job = _fio_json(text)['jobs'][0]
    lat = _lat_ms(job.get('sync') or {})
    if not lat or lat[1] is None:
        lat = _lat_ms(job['write'])
    if not lat:
        raise ValueError('no latency in the fio output')
    return {'p50_ms': lat[0], 'p99_ms': lat[1], 'mean_ms': lat[2], 'iops': job['write'].get('iops', 0)}


def parse_fio_seq(text):
    """MB/s of a sequential write job (fio 'bw' is in KiB/s)"""
    job = _fio_json(text)['jobs'][0]
    return job['write']['bw'] * 1024 / 1e6


def parse_ping(text):
    """{'loss_pct', 'min', 'avg', 'max'} of the summary of iputils / busybox ping, or None without replies"""
    m = re.search(r'([\d.]+)% packet loss', text)
    loss = float(m.group(1)) if m else 100.0
    m = re.search(r'(?:rtt|round-trip) min/avg/max(?:/mdev)? = ([\d.]+)/([\d.]+)/([\d.]+)', text)
    if not m:
        return {'loss_pct': loss, 'min': None, 'avg': None, 'max': None}
    return {'loss_pct': loss, 'min': float(m.group(1)), 'avg': float(m.group(2)), 'max': float(m.group(3))}


def verdict_ping(results, t=DEFAULTS):
    """best anchor's average RTT and loss; never REFUND (the filter check with a real client decides)"""
    ok = [r for r in results.values() if r and r.get('avg') is not None]
    if not ok:
        return BORDERLINE
    best = min(ok, key=lambda r: r['avg'])
    if best['avg'] <= t['ping_max_ms'] and best['loss_pct'] <= 1:
        return KEEP
    return BORDERLINE


def bench_stats(times, cal_s):
    """{'median_s', 'worst_s', 'noise_pct', 'ratio'}: ratio is the median speed as a share of a 7950X"""
    if not times:
        return None
    med, bad = statistics.median(times), max(times)
    ref = cal_s / CAL_TO_7950X
    return {'median_s': med, 'worst_s': bad, 'noise_pct': 100.0 * (bad - med) / med, 'ratio': ref / med,
            'runs': len(times)}


# ---------------------------------------------------------------- load test parsing

LT_ENTERED = re.compile(r'entered the game (\d+) / (\d+); failed (\d+)')
LT_LAG = re.compile(r'game loop lag at (\d+)\+ players \(probe, (\d+) reports\): avg ([\d.]+) ms, worst 5 s avg '
                    r'([\d.]+) ms, max (\d+) ms')
LT_SERVER = re.compile(r'server full load\s+CPU avg\s+([\d.]+)%.*RSS avg (\d+) MB, max (\d+) MB')
LT_THREADS = re.compile(r'busiest threads: (.*)')
LT_THREAD = re.compile(r'([^,]+?) avg ([\d.]+)% p95 ([\d.]+)%')
PROBE = re.compile(r'\[loadtest-probe\] t=(\d+) players=(\d+) lag_avg_ms=([\d.]+) lag_max_ms=(\d+)')


def parse_loadtest(text):
    """the numbers of a loadtest.py run report"""
    out = {'entered': None, 'count': None, 'failed': None, 'lag_avg': None, 'lag_worst5': None, 'lag_max': None,
           'cpu_avg': None, 'rss_avg_mb': None, 'rss_max_mb': None, 'thread': None, 'thread_avg': None,
           'thread_p95': None}
    full = False
    for line in text.splitlines():
        m = LT_ENTERED.search(line)
        if m:
            out['entered'], out['count'], out['failed'] = int(m.group(1)), int(m.group(2)), int(m.group(3))
        m = LT_LAG.search(line)
        if m:
            out['lag_avg'], out['lag_worst5'], out['lag_max'] = float(m.group(3)), float(m.group(4)), int(m.group(5))
        m = LT_SERVER.search(line)
        if m:
            out['cpu_avg'], out['rss_avg_mb'], out['rss_max_mb'] = float(m.group(1)), int(m.group(2)), int(m.group(3))
            full = True
            continue
        m = LT_THREADS.search(line)
        if m and full:
            first = LT_THREAD.search(m.group(1))
            if first:
                out['thread'], out['thread_avg'], out['thread_p95'] = (first.group(1).strip(), float(first.group(2)),
                                                                       float(first.group(3)))
            full = False
    return out


def probe_stalls(text, since, until, min_players=1):
    """probe reports between two unix times: (reports, windows with a lag of 500 ms or more)"""
    n = stalls = 0
    for m in PROBE.finditer(text):
        t, players, lag_max = int(m.group(1)), int(m.group(2)), int(m.group(4))
        if since <= t <= until and players >= min_players:
            n += 1
            stalls += lag_max >= 500
    return n, stalls


SLOW_TASK = re.compile(r'\[slow task\] (\d+) ms\b')


def slow_tasks(lines, commit_re):
    """(slow task lines, of them >= 100 ms, slow COMMIT lines) of the server log lines of a run"""
    n = n100 = commits = 0
    for line in lines:
        m = SLOW_TASK.search(line)
        if not m:
            continue
        n += 1
        n100 += int(m.group(1)) >= 100
        commits += bool(commit_re.search(line))
    return n, n100, commits


def summarize_samples(rows):
    """sampler rows -> machine busy % (bots excluded), steal, MemAvailable and swap"""
    busy, steal = [], []
    for a, b in zip(rows, rows[1:]):
        pa, pb = {'cpu': a['cpu']}, {'cpu': b['cpu']}
        total = sum(b['cpu']) - sum(a['cpu'])
        if total <= 0:
            continue
        excl = 100.0 * (b.get('excl', 0) - a.get('excl', 0)) / total
        busy.append(max(0.0, busy_pct(pa, pb) - excl))
        steal.append(steal_pct(pa, pb)['cpu'])
    avail = [r['avail_kb'] / 1048576.0 for r in rows]
    swap = [r['swap_used_kb'] / 1024.0 for r in rows]
    return {'busy': summarize(busy), 'steal': summarize(steal),
            'avail_min_gb': min(avail) if avail else None, 'avail_start_gb': avail[0] if avail else None,
            'swap_growth_mb': (max(swap) - swap[0]) if swap else 0.0, 'swap_max_mb': max(swap) if swap else 0.0}


def load_items(lt, smp, stalls, slow, pool_gb, t=DEFAULTS):
    """verdict items of one load test run"""
    items = []
    count = lt.get('count') or 0
    entered = lt.get('entered') or 0
    v = KEEP if count and entered >= count * t['login_min_share'] else BORDERLINE
    items.append(item('logins', 'other', v, '%d of %d bots entered the game' % (entered, count)))
    if lt.get('lag_avg') is None:
        items.append(item('game loop lag', 'other', INFO, 'no probe lines (is zz_loadtest_probe.lua installed?)'))
    else:
        v = worst(lower_better(lt['lag_avg'], t['lag_avg_max'], 80.0 / 65.0, BORDERLINE),
                  KEEP if stalls == 0 else BORDERLINE)
        items.append(item('game loop lag', 'other', v, 'avg %.1f ms, worst 5 s %.1f ms, max %d ms, stalls (500 ms+) %d'
                          % (lt['lag_avg'], lt['lag_worst5'], lt['lag_max'], stalls)))
    if lt.get('thread_avg') is not None:
        v = lower_better(lt['thread_avg'], t['thread_max'], 92.0 / 85.0, BORDERLINE)
        items.append(item('game loop thread', 'other', v, '%s avg %.1f%% p95 %.1f%% of one core'
                          % (lt['thread'], lt['thread_avg'], lt['thread_p95'])))
    s = smp['steal']
    v = worst(lower_better(s['mean'], t['steal_mean_max']), lower_better(s['p95'], t['steal_p95_max']))
    items.append(item('steal under load', 'cpu', v, 'mean %.2f%%, p95 %.2f%%, max %.2f%%' % (s['mean'], s['p95'], s['max'])))
    b = smp['busy']
    v = UPGRADE if b['p95'] > t['cpu_busy_max'] else KEEP
    items.append(item('vCPU headroom', 'capacity', v, 'machine busy without the bots: avg %.1f%%, p95 %.1f%%'
                      % (b['mean'], b['p95'])))
    need = t['ram_min_free_gb'] + max(0.0, pool_gb - 0.25)
    v = KEEP
    if smp['avail_min_gb'] is not None and smp['avail_min_gb'] < need or smp['swap_growth_mb'] > t['swap_growth_mb']:
        v = UPGRADE
    items.append(item('RAM under load', 'capacity', v, 'MemAvailable min %.1f GB (needs %.1f: %.1f free + the %.1f GB '
                      'buffer pool still to give MariaDB); swap grew %.0f MB' % (
                          smp['avail_min_gb'] or 0, need, t['ram_min_free_gb'], pool_gb, smp['swap_growth_mb'])))
    items.append(item('slow tasks', 'other', KEEP if slow[2] < 3 else BORDERLINE,
                      '%d slow task lines, %d of 100 ms+, %d slow COMMITs' % slow))
    return items


def item(name, kind, verdict, detail):
    return {'name': name, 'kind': kind, 'verdict': verdict, 'detail': detail}


# ---------------------------------------------------------------- probes (side effects: temp dir, CPU loops, ping)

def read(path, default=''):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def log(msg):
    print('[host-trial %s] %s' % (time.strftime('%H:%M:%S'), msg), flush=True)


def fs_type(path):
    """file system type of the mount that holds path (/proc/mounts, longest prefix)"""
    path = os.path.realpath(path)
    best, kind = '', '?'
    for line in read('/proc/mounts').splitlines():
        parts = line.split()
        if len(parts) >= 3 and (path == parts[1] or path.startswith(parts[1].rstrip('/') + '/')) and \
                len(parts[1]) >= len(best):
            best, kind = parts[1], parts[2]
    return kind


def pin_cmd(core, cmd):
    taskset = shutil.which('taskset')
    return ([taskset, '-c', str(core)] + cmd) if taskset else cmd


class Loaders:
    """one niced busy loop per vCPU: an idle guest hides steal (a vCPU that does not want to run is never kept
    waiting), so steal is measured while every vCPU wants to run"""

    def __init__(self, cores):
        self.procs = {}
        for c in cores:
            def pre(c=c):
                os.nice(19)
                os.sched_setaffinity(0, {c})
            self.procs[c] = subprocess.Popen([sys.executable, '-I', '-c', 'while True: pass'], preexec_fn=pre,
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def pause(self, core, stop=True):
        p = self.procs.get(core)
        if p and p.poll() is None:
            p.send_signal(signal.SIGSTOP if stop else signal.SIGCONT)

    def close(self):
        for p in self.procs.values():
            if p.poll() is None:
                p.send_signal(signal.SIGCONT)
                p.kill()
        for p in self.procs.values():
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                pass


def bench_py(n):
    """the Python single-core workload: integer maths, a dict and string formatting (an interpreter's daily work)"""
    x, d, acc = 12345, {}, 0
    for i in range(n):
        x = (x * 69069 + 1) % 4294967296
        k = x % 4096
        d[k] = d.get(k, 0) + 1
        if i % 7 == 0:
            acc += len(str(x))
    v = sorted(d.values())
    return acc + sum(v) + len(v)


LUA_BENCH = '''local x, d, acc = 12345, {}, 0
for i = 0, %d - 1 do
  x = (x * 69069 + 1) %% 4294967296
  local k = x %% 4096
  d[k] = (d[k] or 0) + 1
  if i %% 7 == 0 then acc = acc + #string.format("%%d", x) end
end
local s, n = 0, 0
for _, v in pairs(d) do s = s + v; n = n + 1 end
print(string.format("%%d", acc + s + n))
'''


def lua_interpreters():
    """[(bench key, path)]: LuaJIT and one PUC Lua 5.x when installed"""
    out = []
    if shutil.which('luajit'):
        out.append(('luajit', shutil.which('luajit')))
    for name in ('lua5.4', 'lua5.3', 'lua'):
        path = shutil.which(name)
        if path:
            ver = subprocess.run([path, '-v'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 universal_newlines=True).stdout
            if re.search(r'Lua 5\.[34]', ver):
                out.append(('lua', path))
                break
    return out


def run_bench(kind, core, tmp, interp=None):
    """seconds of one pinned run, or None when the checksum is wrong"""
    spec = BENCH[kind]
    if kind == 'python':
        cmd = pin_cmd(core, [sys.executable, '-I', os.path.abspath(__file__), 'bench-py', str(spec['n'])])
    else:
        path = os.path.join(tmp, 'bench_%d.lua' % spec['n'])
        if not os.path.exists(path):
            with open(path, 'w') as f:
                f.write(LUA_BENCH % spec['n'])
        cmd = pin_cmd(core, [interp, path])
    t0 = time.perf_counter()
    out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True).stdout
    wall = time.perf_counter() - t0
    parts = out.split()
    if not parts or int(parts[0]) != spec['sum']:
        return None
    return float(parts[1]) if kind == 'python' else wall


def disk_check(tmp, t, use_fio):
    res = {'tool': 'fio' if use_fio else 'python', 'fs': fs_type(tmp)}
    if use_fio:
        base = ['fio', '--directory=' + tmp, '--output-format=json', '--runtime=%d' % t['fio_runtime']]
        out = subprocess.run(base + ['--name=fsync', '--rw=write', '--bs=4k', '--size=64m', '--fsync=1',
                                     '--ioengine=sync'], stdout=subprocess.PIPE, universal_newlines=True).stdout
        res.update(parse_fio_fsync(out))
        _clean(tmp)
        size = _seq_size(tmp, t)
        out = subprocess.run(base + ['--name=seq', '--rw=write', '--bs=1m', '--size=%dm' % size, '--direct=1',
                                     '--ioengine=psync', '--end_fsync=1'], stdout=subprocess.PIPE,
                             universal_newlines=True).stdout
        res['seq_mbs'] = parse_fio_seq(out)
        _clean(tmp)
        return res
    # fallback: 4 KiB write + fsync in a loop, the shape of a database commit
    lat, path, block = [], os.path.join(tmp, 'fsync.bin'), b'\x5a' * 4096
    fd = os.open(path, os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        end = time.monotonic() + min(t['fio_runtime'], 30)
        while len(lat) < 4000 and time.monotonic() < end:
            t0 = time.perf_counter()
            os.write(fd, block)
            os.fsync(fd)
            lat.append((time.perf_counter() - t0) * 1000)
    finally:
        os.close(fd)
    res.update({'p50_ms': percentile(lat, 50), 'p99_ms': percentile(lat, 99), 'mean_ms': statistics.mean(lat),
                'iops': len(lat) / (sum(lat) / 1000.0)})
    _clean(tmp)
    size, chunk = _seq_size(tmp, t), b'\xa5' * 1048576
    t0 = time.perf_counter()
    with open(os.path.join(tmp, 'seq.bin'), 'wb') as f:
        for _ in range(size):
            f.write(chunk)
        f.flush()
        os.fsync(f.fileno())
    res['seq_mbs'] = size * 1048576 / 1e6 / (time.perf_counter() - t0)
    _clean(tmp)
    return res


def _seq_size(tmp, t):
    free_mb = shutil.disk_usage(tmp).free // 1048576
    return max(64, min(t['seq_mb'], free_mb // 4))


def _clean(tmp):
    for name in os.listdir(tmp):
        if not name.endswith('.lua'):
            try:
                os.remove(os.path.join(tmp, name))
            except OSError:
                pass


def mem_bandwidth(mb=256, rounds=5):
    """best single-thread memcpy GB/s of a buffer far larger than any cache"""
    src = bytearray(b'\x01') * (mb * 1048576)
    dst = bytearray(len(src))
    best = None
    for _ in range(rounds):
        t0 = time.perf_counter()
        dst[:] = src
        dt = time.perf_counter() - t0
        best = dt if best is None else min(best, dt)
    return len(src) / 1e9 / best


def network_info(hosts, count):
    iface = ''
    for line in read('/proc/net/route').splitlines()[1:]:
        parts = line.split()
        if len(parts) > 2 and parts[1] == '00000000':
            iface = parts[0]
            break
    speed = read('/sys/class/net/%s/speed' % iface).strip() if iface else ''
    driver = os.path.basename(os.path.realpath('/sys/class/net/%s/device/driver' % iface)) if iface else ''
    pings = {}
    if shutil.which('ping'):
        for h in hosts:
            try:
                out = subprocess.run(['ping', '-n', '-c', str(count), '-i', '0.5', '-W', '2', h],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                                     timeout=count * 0.5 + 15).stdout
            except subprocess.TimeoutExpired:
                out = ''
            pings[h] = parse_ping(out)
    return {'iface': iface, 'speed_mbit': speed if speed and speed != '-1' else 'not shown (virtio)',
            'driver': driver, 'ping': pings}


# ---------------------------------------------------------------- the run command

def window_phase(t, tmp, cores, bench_core, load):
    """steal samples every step_s for window_min, single-core runs spread over it"""
    steps = max(2, int(t['window_min'] * 60 / t['step_s']))
    runs = max(1, t['bench_runs'])
    at = {int(i * (steps - 1) / max(1, runs - 1)) if runs > 1 else 0 for i in range(runs)}
    luas = lua_interpreters()
    times = {'python': []}
    times.update({k: [] for k, _ in luas})
    samples, stopped = [], False
    loaders = Loaders(cores) if load else None
    try:
        nxt = time.monotonic()
        for step in range(steps):
            samples.append(parse_proc_stat(read('/proc/stat')))
            if step in at:
                if loaders:
                    loaders.pause(bench_core)
                try:
                    v = run_bench('python', bench_core, tmp)
                    if v:
                        times['python'].append(v)
                    for key, path in luas:
                        v = run_bench(key, bench_core, tmp, path)
                        if v:
                            times[key].append(v)
                finally:
                    if loaders:
                        loaders.pause(bench_core, stop=False)
            if step % max(1, int(60 / t['step_s'])) == 0:
                s = summarize_steal(samples).get('cpu', summarize([]))
                log('window %d/%d min: steal mean %.2f%% max %.2f%%, single-core runs %d' % (
                    int(step * t['step_s'] / 60), int(t['window_min']), s['mean'], s['max'], len(times['python'])))
            nxt += t['step_s']
            time.sleep(max(0.0, nxt - time.monotonic()))
    except KeyboardInterrupt:
        stopped = True
        log('stopped early: the report covers what was measured')
    finally:
        if loaders:
            loaders.close()
    return samples, times, stopped


def run(t, out_dir, tmp_parent, load, use_fio):
    t0 = time.time()
    cpu = parse_cpuinfo(read('/proc/cpuinfo'))
    ncpu = os.cpu_count() or 1
    cores = sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else list(range(ncpu))
    bench_core = cores[-1]
    plan = PLANS[t['plan']]
    mem = parse_meminfo(read('/proc/meminfo'))
    ram_gb = mem.get('MemTotal', 0) / 1048576.0
    swap_used_mb = (mem.get('SwapTotal', 0) - mem.get('SwapFree', 0)) / 1024.0
    disk_gb = shutil.disk_usage('/').total / 1e9
    tmp = tempfile.mkdtemp(prefix='host_trial.', dir=tmp_parent)
    rep = {'started': time.strftime('%Y-%m-%d %H:%M:%S %z'), 'plan': t['plan'], 'thresholds': t,
           'kernel': os.uname().release, 'python': sys.version.split()[0]}
    try:
        log('CPU: %s, %d vCPU; temp dir %s (%s)' % (cpu['model'] or '?', ncpu, tmp, fs_type(tmp)))
        log('memory bandwidth ...')
        rep['mem_gbs'] = mem_bandwidth()
        log('disk: fsync latency and sequential write (%s) ...' % ('fio' if use_fio else 'python loop'))
        rep['disk'] = disk_check(tmp, t, use_fio)
        log('network: ping %d Brazilian anchors ...' % len(t['ping_hosts']))
        rep['net'] = network_info(t['ping_hosts'], t['ping_count'])
        log('steal and single-core window: %.0f min, one sample every %.0f s, %s' % (
            t['window_min'], t['step_s'], 'a niced CPU loop on every vCPU' if load else 'machine idle'))
        samples, times, stopped = window_phase(t, tmp, cores, bench_core, load)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    rep['stopped_early'] = stopped
    rep['minutes'] = (time.time() - t0) / 60.0
    rep['steal'] = summarize_steal(samples)
    rep['bench'] = {k: bench_stats(v, BENCH[k]['cal_s']) for k, v in times.items()}
    rep['cpu'] = {'model': cpu['model'], 'vendor': cpu['vendor'], 'family': cpu['family'], 'model_id': cpu['model_id'],
                  'mhz_min': min(cpu['mhz'] or [0]), 'mhz_max': max(cpu['mhz'] or [0]), 'vcpu': ncpu,
                  'passthrough': passthrough(cpu), 'generation': amd_generation(cpu),
                  'flags': sorted(f for f in cpu['flags'] if f in ('avx2', 'avx512f', 'avx512_vp2intersect', 'aes',
                                                                   'sha_ni', 'hypervisor', 'constant_tsc', 'svm')),
                  'bench_core': bench_core}
    rep['cpu']['known_as'], rep['cpu']['expected_ratio'] = expected_ratio(cpu['model'])
    rep['ram'] = {'total_gb': ram_gb, 'available_gb': mem.get('MemAvailable', 0) / 1048576.0,
                  'swap_total_mb': mem.get('SwapTotal', 0) / 1024.0, 'swap_used_mb': swap_used_mb,
                  'buffer_pool_gb': buffer_pool_gb(ram_gb, t)}
    rep['disk_gb'] = disk_gb
    rep['items'] = host_items(rep, t, plan)
    rep['overall'] = overall(rep['items'])
    write_report(out_dir, 'host_trial_report', rep, host_text(rep, plan))
    return rep


def main_bench(rep):
    """the bench result the verdict uses: LuaJIT (stable across versions, the engine's own Lua), else Lua, else
    Python"""
    for k in ('luajit', 'lua', 'python'):
        if rep['bench'].get(k):
            return k, rep['bench'][k]
    return None, None


def host_items(rep, t, plan):
    items = []
    c = rep['cpu']
    detail = '%s; %s' % (c['model'] or '?', 'model passed through' if c['passthrough'] else
                         'generic model (not passed through): judge by the benchmark')
    if c['generation']:
        detail += '; family %s model %s looks like %s' % (c['family'], c['model_id'], c['generation'])
    items.append(item('CPU model', 'cpu', INFO, detail))
    s = rep['steal']
    allc = s.get('cpu', summarize([]))
    per = sorted(((k, v['mean']) for k, v in s.items() if k != 'cpu'), key=lambda kv: -kv[1])
    items.append(item('steal time', 'cpu', verdict_steal(s, t) if allc['n'] else INFO,
                      'mean %.2f%%, p95 %.2f%%, max %.2f%%; worst vCPU %s mean %.2f%%' % (
                          allc['mean'], allc['p95'], allc['max'], per[0][0] if per else '-', per[0][1] if per else 0)))
    key, b = main_bench(rep)
    if b:
        items.append(item('single-core', 'cpu', verdict_single(b['ratio'], b['noise_pct'], t),
                          '%s median %.2f s = %.2f of a 7950X (approx.); worst run %.0f%% slower than the median'
                          % (key, b['median_s'], b['ratio'], b['noise_pct'])))
    else:
        items.append(item('single-core', 'cpu', INFO, 'no benchmark result'))
    items.append(item('vCPU count', 'capacity', verdict_vcpu(c['vcpu'], plan['vcpu'], t),
                      '%d (plan %d, at least %d needed)' % (c['vcpu'], plan['vcpu'], t['min_vcpu'])))
    r = rep['ram']
    items.append(item('RAM', 'capacity', verdict_ram(r['total_gb'], plan['ram_gb'], t),
                      '%.1f GB (plan %d); buffer pool that fits: %s; swap used %.0f MB' % (
                          r['total_gb'], plan['ram_gb'], ('%.1f GB' % r['buffer_pool_gb']) if r['buffer_pool_gb']
                          else 'none', r['swap_used_mb'])))
    d = rep['disk']
    items.append(item('disk fsync', 'disk', verdict_fsync(d.get('p99_ms'), t),
                      'p50 %.2f ms, p99 %.2f ms (%s, %s)' % (d['p50_ms'] or 0, d['p99_ms'] or 0, d['tool'], d['fs'])))
    items.append(item('disk sequential', 'disk', KEEP if d['seq_mbs'] >= t['seq_min_mbs'] else BORDERLINE,
                      '%.0f MB/s write' % d['seq_mbs']))
    items.append(item('disk size', 'capacity', BORDERLINE if rep['disk_gb'] < plan['disk_gb'] * 0.9 else KEEP,
                      '%.0f GB on / (plan %d)' % (rep['disk_gb'], plan['disk_gb'])))
    items.append(item('memory bandwidth', 'other', KEEP if rep['mem_gbs'] >= t['mem_min_gbs'] else BORDERLINE,
                      '%.1f GB/s single-thread copy' % rep['mem_gbs']))
    n = rep['net']
    best = min((r['avg'] for r in n['ping'].values() if r and r['avg'] is not None), default=None)
    items.append(item('network', 'other', verdict_ping(n['ping'], t),
                      'port %s, driver %s; best ping %s' % (n['speed_mbit'], n['driver'] or '?',
                                                           '%.1f ms' % best if best is not None else 'no reply')))
    return items


# ---------------------------------------------------------------- reports

DECISION_PT = {
    KEEP: 'FICAR com o plano',
    BORDERLINE: 'LIMITE: repetir o teste em outro horario e decidir pela tabela (docs/HOST_TRIAL.md)',
    UPGRADE: 'FAZER UPGRADE para o Golden Boots (CPU e disco bons, falta RAM ou vCPU)',
    REFUND: 'PEDIR REEMBOLSO antes do dia 7 (CPU ou disco ruim)',
}


def items_text(items):
    lines = ['%-18s %-10s %s' % ('item', 'verdict', 'detail')]
    for i in items:
        lines.append('%-18s %-10s %s' % (i['name'], i['verdict'], i['detail']))
    return lines


def host_text(rep, plan):
    t = rep['thresholds']
    c, r, d, n = rep['cpu'], rep['ram'], rep['disk'], rep['net']
    out = ['Host trial report (server/tools/host_trial.sh)', '',
           'started %s, %.0f min%s; plan %s (%d vCPU, %d GB, %d GB disk); kernel %s; Python %s' % (
               rep['started'], rep['minutes'], ', STOPPED EARLY' if rep['stopped_early'] else '', rep['plan'],
               plan['vcpu'], plan['ram_gb'], plan['disk_gb'], rep['kernel'], rep['python']), '']
    out += items_text(rep['items'])
    out += ['', 'OVERALL: %s' % rep['overall'], 'DECISAO: %s' % DECISION_PT[rep['overall']], '']
    out += ['CPU', '  model: %s (vendor %s, family %s, model %s)' % (c['model'], c['vendor'], c['family'], c['model_id']),
            '  passed through: %s; generation guess: %s; flags: %s' % (
                'yes' if c['passthrough'] else 'no', c['generation'] or '-', ' '.join(c['flags'])),
            '  MHz shown: %.0f-%.0f (a VM often shows the base clock, not the boost)' % (c['mhz_min'], c['mhz_max']),
            '  vCPU: %d; benchmark pinned to vCPU %d' % (c['vcpu'], c['bench_core'])]
    if c['known_as']:
        out.append('  a %s should score about %.2f of a 7950X (approximate)' % (c['known_as'], c['expected_ratio']))
    out += ['', 'Single-core (seconds per run, lower is faster; ratio = share of a Ryzen 9 7950X core, approximate)']
    for k, b in rep['bench'].items():
        if b:
            out.append('  %-7s runs %d, median %.3f s, worst %.3f s (+%.0f%%), ratio %.2f' % (
                k, b['runs'], b['median_s'], b['worst_s'], b['noise_pct'], b['ratio']))
    out.append('  expected ratios (public single-thread benchmarks, approximate): ' +
               ', '.join('%s %.2f' % kv for kv in REF_LINES))
    out += ['', 'Steal time (%% of CPU time, one sample every %.0f s)' % t['step_s']]
    for k in sorted(rep['steal'], key=lambda k: (k != 'cpu', len(k), k)):
        s = rep['steal'][k]
        out.append('  %-6s mean %5.2f%%  p95 %5.2f%%  max %5.2f%%' % ('all' if k == 'cpu' else k, s['mean'], s['p95'],
                                                                    s['max']))
    out += ['', 'RAM', '  total %.1f GB, available %.1f GB, swap %.0f MB (%.0f MB used)' % (
        r['total_gb'], r['available_gb'], r['swap_total_mb'], r['swap_used_mb']),
        '  budget: game server %.1f GB + system and services %.1f GB; MariaDB innodb_buffer_pool_size = %s' % (
            t['game_ram_gb'], t['os_ram_gb'], ('%gG' % r['buffer_pool_gb']) if r['buffer_pool_gb'] else 'does not fit'),
        '', 'Disk', '  fsync (4 KiB write + fsync, as a database commit): p50 %.2f ms, p99 %.2f ms, mean %.2f ms, '
        '%.0f per second' % (d['p50_ms'] or 0, d['p99_ms'] or 0, d['mean_ms'] or 0, d['iops'] or 0),
        '  sequential write %.0f MB/s; tool %s; file system %s; / is %.0f GB' % (d['seq_mbs'], d['tool'], d['fs'],
                                                                            rep['disk_gb']),
        '', 'Memory bandwidth: %.1f GB/s single-thread copy' % rep['mem_gbs'],
        '', 'Network: interface port speed %s, driver %s' % (n['speed_mbit'], n['driver'] or '?')]
    for h, p in n['ping'].items():
        out.append('  ping %-16s %s' % (h, 'no reply' if not p or p['avg'] is None else
                                        'avg %.1f ms (min %.1f, max %.1f), loss %.0f%%' % (p['avg'], p['min'], p['max'],
                                                                                          p['loss_pct'])))
    out += ['', 'Thresholds: steal mean <= %g%% and p95 <= %g%%; single-core >= %.2f of a 7950X (BORDERLINE >= %.2f), '
            'worst run <= %g%% slower; fsync p99 <= %g ms; BORDERLINE up to twice a limit' % (
                t['steal_mean_max'], t['steal_p95_max'], t['single_min'], t['single_borderline'], t['noise_max'],
                t['fsync_p99_max']),
            'This report holds no IP address or password. Send this file and the .json beside it.']
    return '\n'.join(out) + '\n'


def write_report(out_dir, base, rep, text):
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, base + '.txt'), 'w') as f:
        f.write(text)
    with open(os.path.join(out_dir, base + '.json'), 'w') as f:
        json.dump(rep, f, indent=1, sort_keys=True, default=list)
    print(text)
    log('written: %s.txt and %s.json in %s' % (base, base, os.path.abspath(out_dir)))


# ---------------------------------------------------------------- sampler and load report

def proc_jiffies(pid):
    raw = read('/proc/%d/stat' % pid) if pid else ''
    if not raw:
        return 0
    fields = raw.rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])


def sample_loop(path, step, exclude_pid):
    stop = []
    signal.signal(signal.SIGTERM, lambda *a: stop.append(1))
    with open(path, 'a') as f:
        while not stop:
            mem = parse_meminfo(read('/proc/meminfo'))
            row = {'t': time.time(), 'cpu': parse_proc_stat(read('/proc/stat'))['cpu'],
                   'excl': proc_jiffies(exclude_pid), 'avail_kb': mem.get('MemAvailable', 0),
                   'swap_used_kb': mem.get('SwapTotal', 0) - mem.get('SwapFree', 0)}
            f.write(json.dumps(row) + '\n')
            f.flush()
            try:
                time.sleep(step)
            except KeyboardInterrupt:
                break


def load_report(t, count, lt_path, smp_path, log_path, since, out_dir):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import chaos_health  # the slow COMMIT pattern of the live alerts
    lt = parse_loadtest(read(lt_path))
    rows = [json.loads(line) for line in read(smp_path).splitlines() if line.strip()]
    smp = summarize_samples(rows)
    until = int(rows[-1]['t']) if rows else int(time.time())
    text = ''
    if log_path:
        text = read(log_path)
        start = text.find('[host-trial-mark %d]' % since)
        text = text[start:] if start >= 0 else text
    reports, stalls = probe_stalls(text, since, until, int((lt.get('entered') or 0) * 0.9) or 1)
    slow = slow_tasks(text.splitlines(), chaos_health.SLOW_COMMIT_RE)
    ram_gb = parse_meminfo(read('/proc/meminfo')).get('MemTotal', 0) / 1048576.0
    pool = buffer_pool_gb(ram_gb, t)
    items = load_items(lt, smp, stalls, slow, pool, t)
    rep = {'count': count, 'loadtest': lt, 'samples': smp, 'probe_reports': reports, 'stalls': stalls,
           'slow_tasks': slow, 'buffer_pool_gb': pool, 'items': items, 'overall': overall(items), 'thresholds': t}
    lines = ['Load test at %d bots (server/tools/host_trial_load.sh)' % count, '']
    lines += items_text(items)
    lines += ['', 'OVERALL at %d: %s' % (count, rep['overall']), 'DECISAO: %s' % DECISION_PT[rep['overall']],
              '  RSS of the engine: avg %s MB, max %s MB; probe reports %d' % (lt['rss_avg_mb'], lt['rss_max_mb'],
                                                                             reports), '']
    write_report(out_dir, 'host_trial_load_%d' % count, rep, '\n'.join(lines) + '\n')
    return rep


# ---------------------------------------------------------------- PROXY v2 probe

def proxy_header(src, dst, sport, dport):
    """a PROXY protocol v2 header, command PROXY, TCP over IPv4"""
    sig = b'\r\n\r\n\x00\r\nQUIT\n'
    addr = socket.inet_aton(src) + socket.inet_aton(dst) + struct.pack('!HH', sport, dport)
    return sig + bytes([0x21, 0x11]) + struct.pack('!H', len(addr)) + addr


def proxy_probe(host, port, timeout=5.0):
    """send a PROXY v2 header to our own game server and report what came back; the server console says whether the
    header reached the engine (docs/HOST_TRIAL.md)"""
    with socket.create_connection((host, port), timeout=timeout) as s:
        local = s.getsockname()
        s.sendall(proxy_header('203.0.113.7', local[0] if ':' not in local[0] else '127.0.0.1', 40000, port))
        s.settimeout(timeout)
        try:
            data = s.recv(64)
        except socket.timeout:
            return 'no answer within %.0f s (connection still open)' % timeout
    if not data:
        return 'closed by the server without data (expected when the sender is not in proxyProtocolTrusted)'
    return 'answered with %d bytes: the header passed the filter and the engine accepted it' % len(data)


# ---------------------------------------------------------------- command line

def parse_args(argv):
    import argparse
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = p.add_subparsers(dest='cmd')
    r = sub.add_parser('run', help='the host check')
    r.add_argument('--out', default='.', help='folder for host_trial_report.txt and .json')
    r.add_argument('--tmp', default='/var/tmp', help='parent of the temp dir; must be on the disk MariaDB will use')
    r.add_argument('--no-load', action='store_true', help='sample steal on an idle machine (no CPU loop per vCPU)')
    r.add_argument('--no-fio', action='store_true', help='use the Python fsync loop even when fio is installed')
    r.add_argument('--ping-hosts', default=','.join(PING_HOSTS))
    r.add_argument('--plan', choices=sorted(PLANS), default=DEFAULTS['plan'])
    lr = sub.add_parser('load-report', help='the verdict of one load test run')
    lr.add_argument('--count', type=int, required=True)
    lr.add_argument('--loadtest-out', required=True)
    lr.add_argument('--samples', required=True)
    lr.add_argument('--server-log', default='')
    lr.add_argument('--since', type=int, default=0, help='unix time of the run start (the log mark)')
    lr.add_argument('--out', default='.')
    for q in (r, lr):
        for k, v in DEFAULTS.items():
            if k != 'plan' and isinstance(v, (int, float)):
                q.add_argument('--' + k.replace('_', '-'), type=type(v), default=v)
    s = sub.add_parser('sample', help='the load test sampler')
    s.add_argument('file')
    s.add_argument('--step-s', type=float, default=5.0)
    s.add_argument('--exclude-pid', type=int, default=0)
    pp = sub.add_parser('proxy-probe', help='send one PROXY v2 header to our own game server')
    pp.add_argument('host')
    pp.add_argument('port', type=int)
    b = sub.add_parser('bench-py')
    b.add_argument('n', type=int)
    return p, p.parse_args(argv)


def thresholds(a):
    t = dict(DEFAULTS)
    for k in DEFAULTS:
        if hasattr(a, k):
            t[k] = getattr(a, k)
    return t


def main(argv):
    p, a = parse_args(argv)
    if a.cmd == 'bench-py':
        t0 = time.perf_counter()
        c = bench_py(a.n)
        print(c, '%.6f' % (time.perf_counter() - t0))
    elif a.cmd == 'run':
        t = thresholds(a)
        t['ping_hosts'] = [h.strip() for h in a.ping_hosts.split(',') if h.strip()]
        use_fio = bool(shutil.which('fio')) and not a.no_fio
        signal.signal(signal.SIGTERM, lambda *x: (_ for _ in ()).throw(KeyboardInterrupt()))
        rep = run(t, a.out, a.tmp, not a.no_load, use_fio)
        return {KEEP: 0, BORDERLINE: 1, UPGRADE: 2, REFUND: 3}[rep['overall']]
    elif a.cmd == 'load-report':
        rep = load_report(thresholds(a), a.count, a.loadtest_out, a.samples, a.server_log, a.since, a.out)
        return {KEEP: 0, BORDERLINE: 1, UPGRADE: 2, REFUND: 3}[rep['overall']]
    elif a.cmd == 'sample':
        sample_loop(a.file, a.step_s, a.exclude_pid)
    elif a.cmd == 'proxy-probe':
        print(proxy_probe(a.host, a.port))
    else:
        p.print_help()
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

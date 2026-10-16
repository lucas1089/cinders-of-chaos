#!/usr/bin/env python3
"""Tests for host_trial.py: /proc/stat steal parsing, cpuinfo, fio and ping output, the single-core maths, the RAM
budget, the verdicts per item and overall (KEEP, BORDERLINE, UPGRADE, REFUND), the load test report parsing and the
sampler summary, on synthetic inputs. Also bash -n of host_trial.sh and host_trial_load.sh.
Run: python3 -I server/tools/host_trial_test.py"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import host_trial as H  # noqa: E402

checks = 0


def ok(cond, what):
    global checks
    checks += 1
    if not cond:
        print('FAIL: ' + what)
        sys.exit(1)


def near(a, b, eps=1e-6):
    return a is not None and abs(a - b) <= eps


def stat(rows):
    """a /proc/stat text: rows = {name: (user, system, idle, steal)}"""
    lines = []
    for name, (u, s, i, st) in rows.items():
        lines.append('%s %d 0 %d %d 0 0 0 %d 7 0' % (name, u, s, i, st))
    lines.append('intr 12345 0 0')
    lines.append('ctxt 999')
    return '\n'.join(lines) + '\n'


# --- percentile and /proc/stat
ok(near(H.percentile([1, 2, 3, 4, 5], 50), 3) and near(H.percentile([1, 2, 3, 4, 5], 95), 4.8), 'percentile')
ok(H.percentile([], 95) == 0 and H.percentile([7], 95) == 7, 'percentile edges')
a = H.parse_proc_stat(stat({'cpu': (100, 50, 800, 50), 'cpu0': (50, 25, 400, 25), 'cpu1': (50, 25, 400, 25)}))
ok(a['cpu'] == [100, 0, 50, 800, 0, 0, 0, 50] and 'intr' not in a, 'parse /proc/stat, guest columns dropped')
b = H.parse_proc_stat(stat({'cpu': (200, 100, 1600, 100), 'cpu0': (100, 50, 800, 50), 'cpu1': (50, 25, 990, 25)}))
st = H.steal_pct(a, b)
ok(near(st['cpu0'], 5.0) and near(st['cpu1'], 0), 'steal per vCPU')
ok(near(st['cpu'], 5.0), 'steal of the whole machine')
ok(near(H.busy_pct(a, b), 20.0), 'busy: everything but idle and iowait (steal counts as busy)')

# a 3-sample series: 1% then 10% steal on cpu1
s0 = H.parse_proc_stat(stat({'cpu': (0, 0, 0, 0), 'cpu0': (0, 0, 0, 0), 'cpu1': (0, 0, 0, 0)}))
s1 = H.parse_proc_stat(stat({'cpu': (100, 0, 99, 1), 'cpu0': (50, 0, 50, 0), 'cpu1': (50, 0, 49, 1)}))
s2 = H.parse_proc_stat(stat({'cpu': (200, 0, 189, 11), 'cpu0': (100, 0, 100, 0), 'cpu1': (100, 0, 89, 11)}))
summ = H.summarize_steal([s0, s1, s2])
ok(near(summ['cpu1']['mean'], 5.5) and near(summ['cpu1']['max'], 10.0), 'steal summary per vCPU')
ok(near(summ['cpu']['mean'], 2.75) and summ['cpu']['n'] == 2, 'steal summary overall')
ok(H.verdict_steal(summ) == H.BORDERLINE, 'a stolen vCPU (mean 5.5%) makes it BORDERLINE')
quiet = H.summarize_steal([s0, H.parse_proc_stat(stat({'cpu': (100, 0, 99, 1), 'cpu0': (50, 0, 50, 0),
                                                       'cpu1': (50, 0, 49, 1)}))])
ok(H.verdict_steal(quiet) == H.KEEP, 'low steal is KEEP')
bad = {'cpu': H.summarize([12.0, 14.0]), 'cpu0': H.summarize([12.0, 14.0])}
ok(H.verdict_steal(bad) == H.REFUND, 'heavy steal is REFUND')

# --- cpuinfo
CPUINFO = '''processor\t: 0
vendor_id\t: AuthenticAMD
cpu family\t: 25
model\t\t: 97
model name\t: AMD Ryzen 9 7950X 16-Core Processor
cpu MHz\t\t: 4491.540
flags\t\t: fpu sse2 avx2 avx512f aes hypervisor

processor\t: 1
vendor_id\t: AuthenticAMD
cpu family\t: 25
model\t\t: 97
model name\t: AMD Ryzen 9 7950X 16-Core Processor
cpu MHz\t\t: 4491.000
flags\t\t: fpu sse2 avx2 avx512f aes hypervisor
'''
c = H.parse_cpuinfo(CPUINFO)
ok(c['count'] == 2 and c['family'] == 25 and c['model_id'] == 97 and len(c['mhz']) == 2, 'parse cpuinfo')
ok(H.passthrough(c) and H.amd_generation(c) == 'Zen 4', 'passed through, Zen 4')
ok(H.expected_ratio(c['model']) == ('7950X', 1.00), 'known 7950X')
ok(H.expected_ratio('AMD Ryzen 9 5900X 12-Core Processor')[0] == '5900X', '5900X, not 5900XT')
ok(H.expected_ratio('AMD Ryzen 9 5900XT 16-Core Processor')[0] == '5900XT', '5900XT')
ok(H.expected_ratio('AMD Ryzen 9 9950X 16-Core Processor') == ('9950X', 1.10), '9950X')
ok(H.expected_ratio('QEMU Virtual CPU version 2.5+') == (None, None), 'generic model unknown')
hidden = H.parse_cpuinfo(CPUINFO.replace('AMD Ryzen 9 7950X 16-Core Processor', 'QEMU Virtual CPU version 2.5+')
                         .replace('cpu family\t: 25', 'cpu family\t: 26').replace('model\t\t: 97', 'model\t\t: 68'))
ok(not H.passthrough(hidden) and H.amd_generation(hidden) == 'Zen 5', 'hidden model, Zen 5 from the family')
zen3 = H.parse_cpuinfo(CPUINFO.replace(' avx512f', '').replace('model\t\t: 97', 'model\t\t: 33'))
ok(H.amd_generation(zen3) == 'Zen 3', 'Zen 3: family 25 without AVX-512')

# --- single core
b = H.bench_stats([1.0, 1.1, 1.0, 1.3, 1.0], 1.8)
ok(near(b['median_s'], 1.0) and near(b['worst_s'], 1.3) and near(b['noise_pct'], 30.0), 'bench median, worst, noise')
ok(near(b['ratio'], 1.8 / H.CAL_TO_7950X / 1.0), 'bench ratio to a 7950X')
ok(H.bench_stats([], 1.0) is None, 'no runs')
ok(H.verdict_single(0.95, 5) == H.KEEP, '7950X class, steady: KEEP')
ok(H.verdict_single(0.81, 5) == H.BORDERLINE, '5900X class: BORDERLINE')
ok(H.verdict_single(0.55, 5) == H.REFUND, 'old Xeon class: REFUND')
ok(H.verdict_single(1.05, 25) == H.BORDERLINE, 'fast but noisy neighbours: BORDERLINE')
ok(H.verdict_single(1.05, 40) == H.REFUND, 'very noisy: REFUND')
ok(H.bench_py(1000) == H.bench_py(1000), 'deterministic workload')

# --- fio
FIO = {'fio version': 'fio-3.36', 'jobs': [{'jobname': 'fsync',
       'write': {'iops': 812.5, 'bw': 3250, 'clat_ns': {'mean': 20000.0, 'percentile': {'50.000000': 18000,
                                                                                        '99.000000': 40000}}},
       'sync': {'total_ios': 16384, 'lat_ns': {'mean': 1150000.0, 'percentile': {
           '1.000000': 700000, '50.000000': 1012000, '99.000000': 3489000, '99.900000': 9000000}}}}]}
f = H.parse_fio_fsync('note: both iodepth >= 1 and synchronous I/O engine are selected\n' + json.dumps(FIO))
ok(near(f['p50_ms'], 1.012) and near(f['p99_ms'], 3.489) and near(f['mean_ms'], 1.15), 'fio fsync percentiles')
ok(H.verdict_fsync(f['p99_ms']) == H.KEEP, 'fsync p99 3.5 ms: KEEP')
ok(H.verdict_fsync(7.0) == H.BORDERLINE and H.verdict_fsync(25.0) == H.REFUND, 'fsync limits')
nosync = json.loads(json.dumps(FIO))
del nosync['jobs'][0]['sync']
f2 = H.parse_fio_fsync(json.dumps(nosync))
ok(near(f2['p99_ms'], 0.04), 'no sync block: the write latency')
old = {'jobs': [{'write': {'iops': 1, 'bw': 1, 'lat': {'mean': 2500.0, 'percentile': {'50.000000': 2000,
                                                                                      '99.000000': 12000}}}}]}
ok(near(H.parse_fio_fsync(json.dumps(old))['p99_ms'], 12.0), 'old fio: usec')
SEQ = {'jobs': [{'write': {'bw': 1953125, 'iops': 1907}}]}
ok(near(H.parse_fio_seq(json.dumps(SEQ)), 2000.0), 'sequential MB/s from KiB/s')

# --- ping
PING = '''PING registro.br (200.160.2.3) 56(84) bytes of data.
64 bytes from 200.160.2.3: icmp_seq=1 ttl=58 time=2.31 ms

--- registro.br ping statistics ---
20 packets transmitted, 20 received, 0% packet loss, time 9512ms
rtt min/avg/max/mdev = 2.101/2.400/3.020/0.210 ms
'''
p = H.parse_ping(PING)
ok(p['loss_pct'] == 0 and near(p['avg'], 2.4) and near(p['max'], 3.02), 'ping summary')
lost = H.parse_ping('5 packets transmitted, 0 received, 100% packet loss, time 4093ms\n')
ok(lost['avg'] is None and lost['loss_pct'] == 100, 'no replies')
ok(H.verdict_ping({'a': p, 'b': lost}) == H.KEEP, 'best anchor counts')
ok(H.verdict_ping({'a': lost}) == H.BORDERLINE, 'no anchor answers: BORDERLINE, never REFUND')
far = dict(p, avg=40.0)
ok(H.verdict_ping({'a': far}) == H.BORDERLINE, 'far anchor')

# --- RAM budget and capacity verdicts
ok(H.buffer_pool_gb(16) == 4.0, '16 GB: 4 GB buffer pool')
ok(H.buffer_pool_gb(15.6) == 3.5, '15.6 GB usable: 3.5 GB')
ok(H.buffer_pool_gb(32) == 8.0, '32 GB: capped at 8 GB')
ok(H.buffer_pool_gb(9) == 0, '9 GB: nothing fits')
ok(H.verdict_ram(15.6, 16) == H.KEEP, '16 GB plan: KEEP')
ok(H.verdict_ram(12, 16) == H.BORDERLINE, 'less RAM than promised: BORDERLINE')
ok(H.verdict_ram(8, 8) == H.UPGRADE, 'too little for game + DB: UPGRADE')
ok(H.verdict_vcpu(6, 6) == H.KEEP and H.verdict_vcpu(5, 6) == H.BORDERLINE and H.verdict_vcpu(2, 2) == H.UPGRADE,
   'vCPU count')
ok(H.PLANS['magic-sword']['vcpu'] == 6 and H.PLANS['golden-boots']['vcpu'] == 10, 'plans')


# --- overall
def it(kind, v):
    return H.item('x', kind, v, '')


ok(H.overall([it('cpu', H.KEEP), it('disk', H.KEEP), it('other', H.KEEP)]) == H.KEEP, 'all good: KEEP')
ok(H.overall([it('cpu', H.KEEP), it('capacity', H.UPGRADE), it('disk', H.KEEP)]) == H.UPGRADE,
   'good CPU, RAM short: UPGRADE')
ok(H.overall([it('cpu', H.BORDERLINE), it('capacity', H.UPGRADE)]) == H.BORDERLINE,
   'upgrade does not fix a borderline core')
ok(H.overall([it('cpu', H.REFUND), it('capacity', H.UPGRADE)]) == H.REFUND, 'bad CPU: REFUND')
ok(H.overall([it('cpu', H.KEEP), it('disk', H.REFUND)]) == H.REFUND, 'bad disk: REFUND')
ok(H.overall([it('cpu', H.KEEP), it('other', H.REFUND)]) == H.BORDERLINE, 'only CPU or disk can refund')
ok(H.overall([it('cpu', H.INFO), it('cpu', H.KEEP), it('other', H.BORDERLINE)]) == H.BORDERLINE, 'INFO ignored')

# --- load test report
LT = '''Load test: 300 bots, 600s at full load, walk every 1.0s, say every 20.0s
  entered the game 298 / 300; failed 2; kicked within 10 s of entering 0
  login time p50 310 ms, p90 600 ms, p95 700 ms, max 900 ms (connect to in game)
  server idle (before)  CPU avg   3.0%  p95   4.0%  max   6.0% of one core; RSS avg 4650 MB, max 4651 MB
    busiest threads: tfs/100 avg 2.0% p95 3.0%
  server full load      CPU avg  80.5%  p95  95.0%  max 120.0% of one core; RSS avg 4820 MB, max 4870 MB
    busiest threads: tfs/100 avg 55.5% p95 70.1%, tfs/101 avg 9.0% p95 12.0%
  game loop lag before the run (probe, 12 reports): avg 50.2 ms, max 61 ms (the engine timer floor)
  game loop lag at 270+ players (probe, 110 reports): avg 58.9 ms, worst 5 s avg 75.0 ms, max 506 ms
'''
lt = H.parse_loadtest(LT)
ok(lt['entered'] == 298 and lt['count'] == 300 and lt['failed'] == 2, 'loadtest logins')
ok(near(lt['lag_avg'], 58.9) and lt['lag_max'] == 506, 'loadtest lag')
ok(lt['rss_max_mb'] == 4870 and near(lt['cpu_avg'], 80.5), 'loadtest full load CPU and RSS, not the idle line')
ok(lt['thread'] == 'tfs/100' and near(lt['thread_avg'], 55.5) and near(lt['thread_p95'], 70.1), 'busiest thread')
LOG = ('[host-trial-mark 1000] load test\n'
       '[loadtest-probe] t=1001 players=290 lag_avg_ms=55.0 lag_max_ms=120 samples=90\n'
       '[loadtest-probe] t=1006 players=295 lag_avg_ms=70.0 lag_max_ms=640 samples=80\n'
       '[loadtest-probe] t=1011 players=5 lag_avg_ms=50.0 lag_max_ms=900 samples=99\n'
       '[loadtest-probe] t=2000 players=295 lag_avg_ms=70.0 lag_max_ms=640 samples=80\n')
ok(H.probe_stalls(LOG, 1000, 1500, 270) == (2, 1), 'probe reports and stalls at full load, in the window')
import re  # noqa: E402
commit = re.compile(r'\[slow task\] \d+ ms\b.*\| db \d+ ms in .*, longest (\d+) ms: COMMIT\b')
slow = ['[slow task] 120 ms creature.lua:22', '[slow task] 60 ms x.lua:1',
        '[slow task] 310 ms Game::saveIncrementalStep | db 300 ms in 1 queries, longest 300 ms: COMMIT', 'other']
ok(H.slow_tasks(slow, commit) == (3, 2, 1), 'slow task lines, 100 ms+, COMMITs')


def row(t, user, idle, steal, excl, avail_gb, swap_mb):
    return {'t': t, 'cpu': [user, 0, 0, idle, 0, 0, 0, steal], 'excl': excl, 'avail_kb': int(avail_gb * 1048576),
            'swap_used_kb': int(swap_mb * 1024)}


rows = [row(0, 0, 0, 0, 0, 9.0, 0), row(5, 400, 600, 0, 100, 7.0, 0), row(10, 800, 1190, 10, 200, 6.5, 10)]
smp = H.summarize_samples(rows)
ok(near(smp['busy']['mean'], 30.5) and near(smp['busy']['max'], 31.0) and near(smp['avail_min_gb'], 6.5) and near(smp['swap_growth_mb'], 10.0),
   'machine busy without the bots, MemAvailable, swap growth')
ok(near(smp['steal']['max'], 1.0), 'steal under load')
items = H.load_items(lt, smp, 1, (3, 2, 1), 4.0)
v = {i['name']: i['verdict'] for i in items}
ok(v['logins'] == H.KEEP and v['game loop lag'] == H.BORDERLINE and v['RAM under load'] == H.KEEP,
   'load items: one stall makes the lag BORDERLINE; 6.5 GB free holds a 4 GB pool')
ok(v['vCPU headroom'] == H.KEEP and v['steal under load'] == H.KEEP, 'load items: CPU headroom, steal')
ok(H.overall(items) == H.BORDERLINE, 'load overall')
tight = dict(smp, avail_min_gb=3.0)
v2 = {i['name']: i['verdict'] for i in H.load_items(lt, tight, 0, (0, 0, 0), 4.0)}
ok(v2['RAM under load'] == H.UPGRADE and v2['game loop lag'] == H.KEEP, 'little free RAM under load: UPGRADE')
ok(H.overall(H.load_items(lt, tight, 0, (0, 0, 0), 4.0)) == H.UPGRADE, 'load overall UPGRADE')
busy = dict(smp, busy=H.summarize([90.0, 95.0]))
v3 = {i['name']: i['verdict'] for i in H.load_items(lt, busy, 0, (0, 0, 0), 4.0)}
ok(v3['vCPU headroom'] == H.UPGRADE, 'all vCPUs busy without the bots: UPGRADE')

# --- PROXY v2 header
hdr = H.proxy_header('203.0.113.7', '10.0.0.2', 40000, 7172)
ok(hdr[:12] == b'\r\n\r\n\x00\r\nQUIT\n' and hdr[12] == 0x21 and hdr[13] == 0x11 and len(hdr) == 28,
   'PROXY v2 header: signature, PROXY command, TCP4, 12 address bytes')

# --- the shell scripts parse
for sh in ('host_trial.sh', 'host_trial_load.sh'):
    r = subprocess.run(['bash', '-n', os.path.join(HERE, sh)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    ok(r.returncode == 0, 'bash -n %s: %s' % (sh, r.stdout.decode(errors='replace')))

print('host_trial: %d checks passed' % checks)

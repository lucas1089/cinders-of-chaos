#!/usr/bin/env python3
"""Tests of run_profile.py: log parsing, medians, the summary table, and a whole run against a fake editor.

    python3 -I mapeditor/tools/run_profile_test.py"""
import os
import stat
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_profile  # noqa: E402

LOG = """qt.qpa: something unrelated
EDT_LOAD elapsed_ms=10 duration_ms=-1 peak_ram_bytes=1000 stage=process_start
EDT_LOAD elapsed_ms=900 duration_ms=850 peak_ram_bytes=50000 stage=qml_startup
EDT_LOAD elapsed_ms=2500 duration_ms=1500 peak_ram_bytes=900000 stage=otbm
EDT_LOAD elapsed_ms=2600 duration_ms=-1 peak_ram_bytes=900000 stage=map_sprite_counts unique_sprites=70000 retained_sprites=0 atlas_bytes=0
EDT_LOAD elapsed_ms=4000 duration_ms=-1 peak_ram_bytes=1200000 stage=first_complete_frame
EDT_LOAD elapsed_ms=4001 duration_ms=-1 peak_ram_bytes=1200000 stage=map_pan_begin tile_size=32 floor=7
EDT_LOAD elapsed_ms=12001 duration_ms=8000 peak_ram_bytes=1300000 stage=map_pan_complete frames=400 fps=50.0 avg_ms=20.00 p50_ms=18.00 p95_ms=30.00 p99_ms=40.00 worst_ms=55.00 tile_size=32
"""

FAKE = r'''#!/usr/bin/env python3
import sys
args = sys.argv[1:]
slow = 2.0 if 'base' in sys.argv[0] else 1.0
assert '--profile-pan' in args and '--profile-exit' in args and '--load-profile' in args
sys.stderr.write("EDT_LOAD elapsed_ms=10 duration_ms=5 peak_ram_bytes=100 stage=otbm\n")
sys.stderr.write("EDT_LOAD elapsed_ms=%d duration_ms=-1 peak_ram_bytes=2097152 stage=first_complete_frame\n" % (1000 * slow))
sys.stderr.write("EDT_LOAD elapsed_ms=9000 duration_ms=8000 peak_ram_bytes=3145728 stage=map_pan_complete "
                 "frames=100 fps=%.1f avg_ms=%.2f p50_ms=1 p95_ms=%.2f p99_ms=3 worst_ms=4\n" % (60 / slow, 16 * slow, 20 * slow))
'''

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print('FAIL', what)


r = run_profile.parse_log(LOG)
check(r['ready_ms'] == 4000, 'ready time is the first complete frame since process start')
check(r['stages'] == {'qml_startup': 850, 'otbm': 1500}, 'stage durations: %r' % r['stages'])
check(r['peak_ram_bytes'] == 1300000, 'peak RAM is the largest record')
check(r['pan']['p95_ms'] == 30.0 and r['pan']['frames'] == 400.0, 'pan numbers')
check(r['counts']['map_sprite_counts']['unique_sprites'] == '70000', 'sprite counts')
check(not r['errors'], 'no errors')
check(run_profile.parse_log(LOG + 'EDT_LOAD elapsed_ms=1 duration_ms=-1 peak_ram_bytes=1 stage=readiness_timeout\n')
      ['errors'] == ['readiness timeout'], 'timeout is an error')

bad = run_profile.parse_log('nothing')
s = run_profile.summarize([r, dict(r, ready_ms=6000), bad])
check(s['runs'] == 3 and s['complete'] == 2, 'an incomplete run is counted but not used')
check(s['ready_ms'] == 5000, 'median ready time')
check(run_profile.summarize([bad]) == {'runs': 1, 'complete': 0}, 'no complete run')
check(run_profile.change(100, 80) == ' (-20% better)', 'lower is better')
check(run_profile.change(50, 60, lower_is_better=False) == ' (+20% better)', 'higher fps is better')

with tempfile.TemporaryDirectory() as tmp:
    exes = []
    for label in ('base', 'ours'):
        path = os.path.join(tmp, label + '-editor')
        with open(path, 'w') as f:
            f.write(FAKE)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        exes.append('%s=%s' % (label, path))
    md = os.path.join(tmp, 'out.md')
    code = run_profile.main(['--build', exes[0], '--build', exes[1], '--map', os.path.join(tmp, 'm.otbm'),
                             '--client', tmp, '--runs', '2', '--pan-seconds', '1', '--logs', os.path.join(tmp, 'logs'),
                             '--markdown', md, '--scenario', 'surface=--profile-floor 7'])
    check(code == 0, 'complete runs exit 0')
    text = open(md).read()
    check('| ours | 2/2 | 1.00 (-50% better) | 3 (+0%) |' in text, 'the table compares with the first build:\n' + text)
    check('fps' in text and '30.0' in text and '60.0 (+100% better)' in text, 'fps column')
    check(len(os.listdir(os.path.join(tmp, 'logs'))) == 4, 'one log per run')
    check(run_profile.main(['--build', 'x=' + os.path.join(tmp, 'missing'), '--map', 'm', '--client', tmp, '--runs', '1',
                            '--logs', os.path.join(tmp, 'logs2')]) == 1,
          'a build without complete runs fails')

if failures:
    sys.exit('%d failure(s)' % failures)
print('run_profile tests passed')

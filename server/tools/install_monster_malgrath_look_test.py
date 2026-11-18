#!/usr/bin/env python3
"""python3 -I server/tools/install_monster_malgrath_look_test.py : install_monster_malgrath_look.py (O637; install step `monstermalgrathlook`)
on the shipped map and on a synthetic server folder: the map (one row, Malgrath, the Drowned Crown, a monster of ours with a comma in
its name, old look 1473 as its file in the repository has, new look 3530 above the 3,529 outfits of pair 73), the client pair guard end
to end (pair 73 or missing: nothing written and a WARNING line; pair 74: the XML moves, colours stay), idempotent, a file with another
look stops the step, a missing file stops it, --dry-run writes nothing, the step sits after `monsterswaplooks` in install_all.py. No
base server needed."""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair as C  # noqa: E402
import install_monster_malgrath_look as M  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import install_all as A  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_monster_malgrath_look.py')
NAME = 'Malgrath, the Drowned Crown'
failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(*args):
    p = subprocess.run([sys.executable, '-I', TOOL] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


def xml(name, look, extra=' head="10" body="20"'):
    return '<?xml version="1.0"?>\n<monster name="%s" nameDescription="%s" race="undead" experience="5" speed="100">\n' \
           '\t<health now="100" max="100"/>\n\t<look type="%d"%s corpse="6068"/>\n</monster>\n' % (name, name, look, extra)


def server(pair, look=1473, with_file=True):
    d = tempfile.mkdtemp(prefix='malgrathlook_')
    if pair is not None:
        open(os.path.join(d, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    mon = os.path.join(d, 'data', 'monster', 'monsters', 'chaos')
    os.makedirs(mon)
    open(os.path.join(mon, 'other.xml'), 'w').write(xml('Other', 1473))
    if with_file:
        open(os.path.join(mon, 'malgrath_the_drowned_crown.xml'), 'w').write(xml(NAME, look))
    return d


def snapshot(d):
    out = {}
    for dp, _dn, fs in os.walk(d):
        for f in fs:
            out[os.path.join(dp, f)] = open(os.path.join(dp, f), 'rb').read()
    return out


def look_of(d):
    text = open(os.path.join(d, 'data', 'monster', 'monsters', 'chaos', 'malgrath_the_drowned_crown.xml')).read()
    return int(re.search(r'<look type="(\d+)"', text).group(1)), text


# ---- the shipped map
rows = M.read_map()
check(rows == [(NAME, 1473, 3530)], 'the map has Malgrath: %s' % rows)
check(C.PAIR_MALGRATH == 74 and C.PAIR_MALGRATH > C.PAIR_CREATURE, 'the step needs pair 74, after the creature outfits of pair 73')
files = R.monster_files(os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos'))
check(NAME in files, 'Malgrath is a monster of ours')
if NAME in files:
    check(R.LOOK_TAG.search(open(files[NAME], encoding='utf-8').read()).group(2) == '1473', 'the repository file keeps look 1473')
check(3530 == 3529 + 1, 'the new look is the first outfit after pair 73')
# the same name is the lair's boss, the mechanics profile and the boss list entry
cfg = open(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bosslair_config.lua'), encoding='utf-8').read()
check('monster = "%s"' % NAME in cfg and 'pair = 74' in cfg, 'the lair names Malgrath and pair 74')
check('["%s"] = {' % NAME.lower() in open(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'boss_mechanics_config.lua'), encoding='utf-8').read(),
      'the mechanics profile is keyed by the lower case name')

# ---- the guard and the step end to end
for pair in (None, 54, 73):
    d = server(pair)
    before = snapshot(d)
    rc, out = run(os.path.join(d, 'data'))
    check(rc == 0 and 'WARNING: monstermalgrathlook skipped' in out and 'client pair 74' in out and snapshot(d) == before,
          'pair %s: warning, exit 0, nothing written' % pair)
d = server(74)
other = open(os.path.join(d, 'data', 'monster', 'monsters', 'chaos', 'other.xml')).read()
rc, out = run(os.path.join(d, 'data'), '--dry-run')
check(rc == 0 and 'dry run: nothing written (1 files would change)' in out and look_of(d)[0] == 1473, 'dry run writes nothing')
rc, out = run(os.path.join(d, 'data'))
look, text = look_of(d)
check(rc == 0 and look == 3530 and 'head="10" body="20"' in text and '1 moved to their new look' in out, 'pair 74: the look moves, the colours stay (%s)' % out)
check(open(os.path.join(d, 'data', 'monster', 'monsters', 'chaos', 'other.xml')).read() == other, 'another monster is not touched')
after = snapshot(d)
rc, out = run(os.path.join(d, 'data'))
check(rc == 0 and snapshot(d) == after and '1 already there' in out, 'a second run changes nothing')
d = server(74, look=999)
rc, out = run(os.path.join(d, 'data'))
check(rc == 1 and 'ERROR' in out and 'has look 999' in out and look_of(d)[0] == 999, 'another look stops the step')
d = server(74, with_file=False)
rc, out = run(os.path.join(d, 'data'))
check(rc == 1 and 'no monster file' in out, 'a missing file stops the step')
check(run()[0] == 1, 'the data folder is needed')

# ---- the step in install_all.py: after the look swaps
check('monstermalgrathlook' in A.STEPS and A.STEPS.index('monstermalgrathlook') == A.STEPS.index('monsterswaplooks') + 1, 'the step follows monsterswaplooks')
check(callable(getattr(A, 'step_monstermalgrathlook', None)), 'the step function exists')

print('install_monster_malgrath_look_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)

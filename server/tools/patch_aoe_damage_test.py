#!/usr/bin/env python3
"""Tests for patch_aoe_damage.py on synthetic copies of the base area spell scripts (LF and CRLF)."""
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_aoe_damage.py')
sys.path.insert(0, HERE)
import patch_aoe_damage as P

fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + msg)


def script(spec):
    """a base-like script made of the lines the patch expects"""
    _, reps = spec
    lines = ['local combat = Combat()', 'combat:setArea(createCombatArea(AREA_WAVE4))', '']
    times = max(r[3] for r in reps)
    for i in range(times):
        lines.append('function onGetFormulaValues%d(player, level, magicLevel)' % i)
        for which, old, _, t in reps:
            if i < t:
                lines.append('\tlocal %s = %s' % (which, old))
        lines += ['\treturn -min, -max', 'end', '']
    return lines


def build(root, eol):
    d = os.path.join(root, 'spells', 'scripts', 'attack')
    os.makedirs(d)
    for name, spec in P.SCRIPTS.items():
        with open(os.path.join(d, name), 'w', newline='') as f:
            f.write(eol.join(script(spec)) + eol)
    return d


def run(root, *extra):
    r = subprocess.run([sys.executable, '-I', TOOL, root] + list(extra), capture_output=True, text=True)
    return r.returncode, r.stdout


def read(d, name):
    with open(os.path.join(d, name), newline='') as f:
        return f.read()


for eol in ('\n', '\r\n'):
    tag = 'CRLF' if eol == '\r\n' else 'LF'
    root = tempfile.mkdtemp()
    try:
        d = build(root, eol)
        before = {n: read(d, n) for n in P.SCRIPTS}
        code, out = run(root, '--dry-run')
        check(code == 0, tag + ': dry run exits 0')
        check(all(read(d, n) == before[n] for n in P.SCRIPTS), tag + ': dry run changes nothing')
        code, out = run(root)
        check(code == 0, tag + ': patch exits 0: ' + out)
        for name in P.SCRIPTS:
            t = read(d, name)
            check(t.startswith(P.MARK + eol), tag + ' %s: marker first' % name)
            check(eol == '\r\n' or '\r' not in t, tag + ' %s: no CR added' % name)
            check(eol == '\n' or len(re.findall(r'(?<!\r)\n', t)) == 0, tag + ' %s: every line keeps CRLF' % name)
            for which, old, new, times in P.SCRIPTS[name][1]:
                check(t.count('local %s = %s' % (which, new)) == times, tag + ' %s: %s patched %d times' % (name, which, times))
                check(old not in t.replace(new, ''), tag + ' %s: base %s line gone' % (name, which))
        check('chaosAoeFloor' in read(d, 'divine_caldera.lua') and 'chaosAoeFloor' not in read(d, 'ice_wave.lua'),
              tag + ': the floor function only where needed')
        after = {n: read(d, n) for n in P.SCRIPTS}
        code, out = run(root)
        check(code == 0 and 'patch_aoe_damage: 0 change(s)' in out, tag + ': second run changes nothing')
        check(all(read(d, n) == after[n] for n in P.SCRIPTS), tag + ': second run leaves the files')
    finally:
        shutil.rmtree(root)

# refuses, changing nothing, when an expected line is missing or a file is gone
root = tempfile.mkdtemp()
try:
    d = build(root, '\n')
    p = os.path.join(d, 'groundshaker.lua')
    text = read(d, 'groundshaker.lua').replace('0.03) + 6', '0.03) + 7', 1)
    with open(p, 'w', newline='') as f:
        f.write(text)
    snap = {n: read(d, n) for n in P.SCRIPTS}
    code, out = run(root)
    check(code == 1 and 'groundshaker.lua' in out, 'refuses when a groundshaker line differs: ' + out)
    check(all(read(d, n) == snap[n] for n in P.SCRIPTS), 'a refused run changes no file')
    os.remove(os.path.join(d, 'scorch.lua'))
    code, out = run(root)
    check(code == 1 and 'missing' in out, 'refuses when a script is missing')
finally:
    shutil.rmtree(root)

# the numbers: each patched hit is not under the single-target spell of its tier
sing = {'ice_wave.lua': (1.4, 2.2, 8, 14), 'fire_wave.lua': (1.4, 2.2, 8, 14), 'scorch.lua': (0.4, 0.8, 2, 5),
        'chill_out.lua': (0.4, 0.8, 2, 5)}
for name, (a, b, c, d_) in sing.items():
    reps = {w: new for w, _, new, _ in P.SCRIPTS[name][1]}
    check('* %s)' % a in reps['min'] and '+ %d' % c in reps['min'], name + ': min = the single-target formula')
    check('* %s)' % b in reps['max'] and '+ %d' % d_ in reps['max'], name + ': max = the single-target formula')
check('0.04) + 9' in P.SCRIPTS['groundshaker.lua'][1][0][2], 'Earthrend max = the Bonebreaker formula')

print('patch_aoe_damage_test: %s' % ('OK' if not fails else '%d failure(s)' % fails))
sys.exit(1 if fails else 0)

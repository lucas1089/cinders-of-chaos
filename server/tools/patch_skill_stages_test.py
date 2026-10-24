#!/usr/bin/env python3
"""Test of patch_skill_stages.py on synthetic skills_stages.lua copies, and on the real base copy when /tmp/wk has one
(no game data in the repo; CI runs the synthetic part).

    python3 -I server/tools/patch_skill_stages_test.py

Stages from 101 up get the factor, stages up to 100 stay, a row that spans 100/101 is split, a second run changes nothing, a
changed factor derives from the original values, CRLF is kept, an unknown shape is refused and left alone, the config file
says x5 from 101, and the model (tools/skill_model.lua) reads the same two numbers.
"""
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_skill_stages as P  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


STOCK_ROWS = [(1, 60, 20), (61, 80, 15), (81, 100, 11), (101, 110, 9), (111, 125, 8), (126, 149, 7), (150, None, 4)]


def block(name, rows, spaced=True):
    out = '    [%s] = {\n' % name
    for i, (a, b, m) in enumerate(rows):
        rng = '%3d, %3d' % (a, b) if b is not None else '%d' % a
        out += '        [{%s}] = {multiplier = %s}%s\n' % (rng, m, ',' if i < len(rows) - 1 else '')
    return out + '    }'


def stock(rows=STOCK_ROWS, names=('SKILL_FIST', 'SKILL_SWORD', 'SKILL_MAGLEVEL')):
    body = ',\n'.join(block(n, rows) for n in names)
    return ('local skillStages = {\n' + body + '\n}\n\n\nlocal ec = EventCallback\n\n'
            'ec.onGainSkillTries = function(self, skill, tries)\n    return tries\nend\n')


def mults(text):
    """[(a, b, m)] of every row of the first skill block"""
    out = []
    for m in re.finditer(r'\[\{\s*(\d+)\s*(?:,\s*(\d+)\s*)?\}\]\s*=\s*\{multiplier = ([\d.]+)\}', text):
        out.append((int(m.group(1)), int(m.group(2)) if m.group(2) else None, float(m.group(3))))
    return out


# ---------------------------------------------------------------- the stock shape
src = stock()
new, status = P.patch_text(src, 101, 5)
check(status == 'patched', 'patched (%s)' % status)
got = mults(new)
check(len(got) == 21, '21 rows, three skills of seven (%d)' % len(got))
for i, (a, b, m) in enumerate(STOCK_ROWS):
    for k in range(3):
        g = got[k * 7 + i]
        want = m * 5 if a >= 101 else m
        check(g == (a, b, want), 'row %d-%s: %s, want %s' % (a, b, g, want))
check(new.splitlines()[0].startswith(P.MARK), 'header on top')
check(new.count('-- Chaos: was') == 12, '12 changed rows say what they were (%d)' % new.count('-- Chaos: was'))
check('[{150}] = {multiplier = 20} -- Chaos: was 4' in new, 'the open last row, no comma')
check('[{101, 110}] = {multiplier = 45}, -- Chaos: was 9' in new, 'a row with its comma')
check(new.endswith('end\n') and 'ec.onGainSkillTries' in new, 'the rest of the file stays')

again, status = P.patch_text(new, 101, 5)
check(status == 'already' and again == new, 'a second run changes nothing')

# a changed factor derives from the originals
f2, status = P.patch_text(new, 101, 10)
check(status == 'patched' and mults(f2)[3] == (101, 110, 90.0) and mults(f2)[2] == (81, 100, 11.0), 'factor 10 from the original 9')
back, _ = P.patch_text(f2, 101, 5)
check(back == new, 'back to 5 gives the same file as a first run')
one, _ = P.patch_text(new, 101, 1)
check([m for _, _, m in mults(one)] == [m for _, _, m in mults(src)], 'factor 1 restores every multiplier')
check(P.patch_text(src, 101, 2.5)[0].count('-- Chaos: was') == 12 and mults(P.patch_text(src, 101, 2.5)[0])[3][2] == 22.5,
      'a fractional factor gives a fractional multiplier')

# a row that spans 100 / 101 is split
wide = stock(rows=[(1, 60, 20), (61, 130, 10), (131, None, 4)], names=('SKILL_FIST',))
w, status = P.patch_text(wide, 101, 5)
check(mults(w) == [(1, 60, 20.0), (61, 100, 10.0), (101, 130, 50.0), (131, None, 20.0)], 'split at 101: %s' % mults(w))
check(P.patch_text(w, 101, 5) == (w, 'already'), 'a split file is stable')
openw = stock(rows=[(1, 60, 20), (61, None, 10)], names=('SKILL_FIST',))
o, _ = P.patch_text(openw, 101, 5)
check(mults(o) == [(1, 60, 20.0), (61, 100, 10.0), (101, None, 50.0)], 'an open row is split too: %s' % mults(o))
low = stock(rows=[(1, 100, 20)], names=('SKILL_FIST',))
check(P.patch_text(low, 101, 5)[0].count('-- Chaos: was') == 0, 'nothing from 101 up: no changed row')

# CRLF kept, no bare LF added
crlf, status = P.patch_text(src.replace('\n', '\r\n'), 101, 5)
check(status == 'patched' and '\r\n' in crlf and '\n' not in crlf.replace('\r\n', ''), 'CRLF kept')
check(P.patch_text(crlf, 101, 5) == (crlf, 'already'), 'a CRLF file is stable')
check(crlf.replace('\r\n', '\n') == new, 'CRLF and LF give the same lines')

# unknown shapes are refused
for label, text in (
        ('no table', 'print("hello")\n'),
        ('no callback', stock().replace('onGainSkillTries', 'onSomething')),
        ('other line in a block', stock().replace('        [{ 61,  80}] = {multiplier = 15},\n', '        local x = 1\n')),
        ('other row shape', stock().replace('{multiplier = 15}', '{multiplier = 15, extra = 1}')),
        ('overlap', stock(rows=[(1, 60, 20), (50, 100, 10)])),
        ('backwards', stock(rows=[(1, 60, 20), (90, 80, 10)])),
        ('never closed', 'local skillStages = {\n    [SKILL_FIST] = {\n        [{1}] = {multiplier = 2}\n    }\n'
                         'ec.onGainSkillTries = 1\n'),
        ('no rows', 'local skillStages = {\n}\nec.onGainSkillTries = 1\n')):
    try:
        P.patch_text(text, 101, 5)
        check(False, 'refused: %s' % label)
    except P.Refused:
        pass
# a marked file with a hand-edited row has no original to derive from
hand = new.replace(' -- Chaos: was 9', '', 1)
try:
    P.patch_text(hand, 101, 5)
    check(False, 'a marked row without "was" is refused')
except P.Refused:
    pass

# ---------------------------------------------------------------- the command line
with tempfile.TemporaryDirectory() as tmp:
    d = os.path.join(tmp, 'data')
    path = os.path.join(d, P.TARGET)
    os.makedirs(os.path.dirname(path))
    check(P.main([d]) == 0, 'no file: skipped, not an error')
    with open(path, 'w', newline='') as f:
        f.write(src)
    check(P.main([d, '--dry-run']) == 0 and open(path, newline='').read() == src, '--dry-run writes nothing')
    check(P.main([d]) == 0 and open(path, newline='').read() == new, 'written')
    stat = os.stat(path).st_mtime_ns
    check(P.main([d]) == 0 and os.stat(path).st_mtime_ns == stat, 'a second run does not write')
    with open(path, 'w', newline='') as f:
        f.write('print(1)\n')
    check(P.main([d]) == 1 and open(path, newline='').read() == 'print(1)\n', 'an unknown file is refused and left alone')

# ---------------------------------------------------------------- the config and the model
check(P.read_config() == (101, 5), 'skill_stages_config.lua: x5 from 101 (%s)' % (P.read_config(),))
model = open(os.path.join(HERE, 'skill_model.lua')).read()
check('skill_stages_config.lua' in model, 'skill_model.lua reads the same config file')

# ---------------------------------------------------------------- the real base copy
real = '/tmp/wk/srv/data/scripts/customs/skills/skills_stages.lua'
if os.path.isfile(real):
    with open(real, newline='') as f:
        text = f.read()
    if P.MARK in text:
        print('real copy already patched: only the idempotence is checked')
    r, status = P.patch_text(text, 101, 5)
    check(P.patch_text(r, 101, 5) == (r, 'already'), 'real copy: second run changes nothing')
    before, after = mults(text), mults(r)
    check(len(before) == len(after) == 56, 'real copy: eight skills of seven rows (%d)' % len(after))
    if P.MARK not in text:
        check(all(x[:2] == y[:2] and y[2] == (x[2] * 5 if x[0] >= 101 else x[2]) for x, y in zip(before, after)),
              'real copy: stages from 101 x5, the others as they were')
    check(r.count('onGainSkillTries') == text.count('onGainSkillTries'), 'real copy: the callback is untouched')
else:
    print('no real base copy at %s (skipped)' % real)

if fails:
    print('patch_skill_stages_test: %d FAILED' % len(fails))
    for f in fails:
        print('  - ' + f)
    sys.exit(1)
print('patch_skill_stages_test: OK')

#!/usr/bin/env python3
"""Tests of patch_base_json_guards.py on synthetic copies of the six base handlers (LF and CRLF), and on a real base
data folder when CHAOS_BASE_DATA names one.

Run: python3 -I server/tools/patch_base_json_guards_test.py (standard library only)."""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_json_guards as P  # noqa: E402

BASE = os.environ.get('CHAOS_BASE_DATA', '')
fails = []


def ok(cond, what):
    if not cond:
        fails.append(what)


def synthetic(edits):
    return 'local x = 1\nfunction onExtendedOpcode(player, opcode, buffer)\n' + ''.join(old for old, _ in edits) + '  return true\nend\n'


# the edit of each file: guard added, marker on top, idempotent
for rel, edits in P.FILES:
    text = synthetic(edits)
    new, changed, err = P.patch(text, edits)
    ok(changed and err is None and new.startswith(P.MARKER + '\n'), rel + ': patched')
    ok('-- Chaos: JSON object guard\n' in new or 'json.decode, buffer) -- Chaos: JSON object guard\n' in new, rel + ': guard line')
    ok('type(' in new and '~= "table"' in new, rel + ': type check')
    again, changed2, err2 = P.patch(new, edits)
    ok(again == new and not changed2 and err2 is None, rel + ': idempotent')
    _, changed3, err3 = P.patch('function onExtendedOpcode() end\n', edits)
    ok(not changed3 and err3 and err3.startswith('REFUSED'), rel + ': refused on unknown code')
    _, _, err4 = P.patch(text + text, edits)
    ok(err4 and 'found 2 times' in err4, rel + ': refused when the code is there twice')

# the tier maps handler no longer lets a decode error through
tier = P.patch(synthetic(P.FILES[-1][1]), P.FILES[-1][1])[0]
ok('pcall(json.decode, buffer)' in tier and 'local data = json.decode(buffer)' not in tier, 'tier maps: decode in pcall')

# main: dry run, write, CRLF kept, second run, a missing file skipped, a refusal writes nothing
d = tempfile.mkdtemp()
try:
    for i, (rel, edits) in enumerate(P.FILES):
        path = os.path.join(d, *rel.split('/'))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        text = synthetic(edits)
        with open(path, 'w', newline='') as f:
            f.write(text.replace('\n', '\r\n') if i % 2 else text)
    ok(P.main([d, '--dry-run']) == 0, 'dry run')
    ok(all(P.MARKER not in open(os.path.join(d, *rel.split('/'))).read() for rel, _ in P.FILES), 'dry run writes nothing')
    ok(P.main([d]) == 0, 'writes')
    for i, (rel, _) in enumerate(P.FILES):
        raw = open(os.path.join(d, *rel.split('/')), newline='').read()
        ok(P.MARKER in raw, rel + ': written')
        ok(('\r\n' in raw) == bool(i % 2) and ('\n' not in raw.replace('\r\n', '') if i % 2 else True), rel + ': line ends kept')
    snapshot = {rel: open(os.path.join(d, *rel.split('/')), newline='').read() for rel, _ in P.FILES}
    ok(P.main([d]) == 0, 'second run')
    ok(all(open(os.path.join(d, *rel.split('/')), newline='').read() == snapshot[rel] for rel, _ in P.FILES),
       'second run changes nothing')
    os.remove(os.path.join(d, *P.FILES[0][0].split('/')))
    bad = os.path.join(d, *P.FILES[1][0].split('/'))
    with open(bad, 'w') as f:
        f.write('function x() end\n')
    third = os.path.join(d, *P.FILES[2][0].split('/'))
    before = open(third, newline='').read()
    ok(P.main([d]) == 1, 'unknown code: exit 1')
    ok(open(third, newline='').read() == before, 'a refusal writes nothing')
    ok(P.main([os.path.join(d, 'none')]) == 0, 'missing folder: every file skipped')
finally:
    shutil.rmtree(d)

if BASE:
    for rel, edits in P.FILES:
        path = os.path.join(BASE, *rel.split('/'))
        if os.path.isfile(path):
            _, changed, err = P.patch(open(path, newline='').read().replace('\r\n', '\n'), edits)
            ok(changed and err is None, rel + ': applies to the real base file')

if fails:
    print('\n'.join('FAIL ' + f for f in fails))
    print('patch_base_json_guards_test: %d FAILED' % len(fails))
    sys.exit(1)
print('patch_base_json_guards_test: all checks passed')

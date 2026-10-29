#!/usr/bin/env python3
"""Tests of patch_base_opcode_inputs.py on synthetic excerpts of the seven base handlers (LF and CRLF), and on a real
base data folder when CHAOS_BASE_DATA names one (read only: the files are patched in memory).

Run: python3 -I server/tools/patch_base_opcode_inputs_test.py (standard library only)."""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_opcode_inputs as P  # noqa: E402

BASE = os.environ.get('CHAOS_BASE_DATA', '')
fails = []


def ok(cond, what):
    if not cond:
        fails.append(what)


def synthetic(edits):
    return 'local x = 1\n' + ''.join(old + '-- between\n' for old, _ in edits) + 'return true\n'


# every file: patched, marker on top, idempotent, refuses unknown text and a doubled anchor
for rel, edits in P.FILES:
    text = synthetic(edits)
    new, changed, err = P.patch(text, edits)
    ok(changed and err is None and new.startswith(P.MARKER + '\n'), rel + ': patched')
    ok(new.count(P.MARKER) == 1, rel + ': one marker')
    ok(P.TAG in new, rel + ': tagged')
    for old, repl in edits:
        ok(repl in new, rel + ': edit applied: ' + old.strip()[:40])
    again, changed2, err2 = P.patch(new, edits)
    ok(again == new and not changed2 and err2 is None, rel + ': idempotent')
    _, changed3, err3 = P.patch('function onExtendedOpcode() end\n', edits)
    ok(not changed3 and err3 and err3.startswith('REFUSED'), rel + ': refused on unknown code')
    _, _, err4 = P.patch(text + text, edits)
    ok(err4 and 'found 2 times' in err4, rel + ': refused when the code is there twice')
    # one anchor missing: nothing is returned patched
    part = text.replace(edits[-1][0], '')
    out5, changed5, err5 = P.patch(part, edits)
    ok(not changed5 and err5 and out5 == part, rel + ': refused when one anchor is missing')

# the checks themselves, by their text
by = dict(P.FILES)
store = P.patch(synthetic(by['creaturescripts/scripts/game_store.lua']), by['creaturescripts/scripts/game_store.lua'])[0]
ok('amount ~= math.floor(amount)' in store and '`points` >= " .. amount' in store, 'store: whole amounts, conditional debit')
ok(store.count('SELECT ROW_COUNT()') == 2, 'store: debit and credit read back')
ok('type(data) ~= "table"' in store, 'store: data must be an object')
hs = P.patch(synthetic(by['scripts/customs/highscores/highscores.lua']), by['scripts/customs/highscores/highscores.lua'])[0]
ok('error("invalid category")' not in hs and 'chaosInt(req.entriesPerPage, 1, 100, 10)' in hs, 'highscores: category, page size')
ok('table.concat(chaosSafe' in hs and 'table.concat(vocs' not in hs, 'highscores: numbers only in the SQL')
ok('canSeeCreature' in hs, 'highscores: hidden player is not online')
ins = P.patch(synthetic(by['scripts/customs/stats_inspect/inspect.lua']), by['scripts/customs/stats_inspect/inspect.lua'])[0]
ok('canSeeCreature' in ins and 'type(targetName) ~= "string"' in ins, 'inspect: string name, hidden is not found')
upg = P.patch(synthetic(by['scripts/customs/waystone_system/character_upgrades.lua']),
              by['scripts/customs/waystone_system/character_upgrades.lua'])[0]
ok('onUpgradesUpdatePoints' not in upg and 'gameUpgradesUpdatePoints(player)' in upg, 'upgrades: points call exists')

# a file already carrying the json guard marker of the other tool still takes these edits (both markers kept)
guarded = '-- Chaos: JSON object guard (patch_base_json_guards.py)\n' + synthetic(by['scripts/customs/tasks/tasks.lua'])
g, changed, err = P.patch(guarded, by['scripts/customs/tasks/tasks.lua'])
ok(changed and err is None and 'JSON object guard' in g and g.startswith(P.MARKER), 'tasks: after the json guard')

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
    with open(third, 'w') as f:
        f.write(synthetic(P.FILES[2][1]))
    before = open(third, newline='').read()
    ok(P.main([d]) == 1, 'unknown code: exit 1')
    ok(open(third, newline='').read() == before, 'a refusal writes nothing')
    ok(P.main([os.path.join(d, 'none')]) == 0, 'missing folder: every file skipped')
    ok(P.main([]) == 1 and P.main(['--bogus']) == 1, 'usage')
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
    print('patch_base_opcode_inputs_test: %d FAILED' % len(fails))
    sys.exit(1)
print('patch_base_opcode_inputs_test: all checks passed')

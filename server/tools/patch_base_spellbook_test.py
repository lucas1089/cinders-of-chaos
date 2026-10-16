#!/usr/bin/env python3
"""Test of patch_base_spellbook.py on a copy of the base server's spellbook action script: the hook is the first
statement of onUse, the stock text stays below it, idempotent, CRLF, an old-style XML action script, other scripts
untouched, --dry-run, bad args. Run: python3 -I server/tools/patch_base_spellbook_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_spellbook.py')
sys.path.insert(0, HERE)
import patch_base_spellbook as P  # noqa: E402

STOCK = '''local spellbook = Action()

function spellbook.onUse(player, item, fromPosition, target, toPosition, isHotkey)
\tlocal text = {}
\tlocal spells = {}
\tfor _, spell in ipairs(player:getInstantSpells()) do
\t\tif spell.level ~= 0 then
\t\t\tspells[#spells + 1] = spell
\t\tend
\tend
\tfor i, spell in ipairs(spells) do
\t\ttext[#text+1] = "Spells for Level "
\tend
\tplayer:showTextDialog(item:getId(), table.concat(text))
\treturn true
end

spellbook:id(2175, 6120, 8900, 8901, 8902, 8903, 8904, 8918, 16112, 18401, 22422, 22423, 22424, 23771)
spellbook:register()
'''

OLD = '''function onUse(cid, item, fromPosition, itemEx, toPosition)
    local t = "Spells for Level "
    doShowTextDialog(cid, item.itemid, t)
    return true
end
'''

checks = 0


def ok(cond, msg):
    global checks
    checks += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


new, st = P.patch(STOCK)
ok(st == 'patched', 'patched')
lines = new.split('\n')
i = lines.index('function spellbook.onUse(player, item, fromPosition, target, toPosition, isHotkey)')
ok(lines[i + 1].startswith('\t-- ' + P.MARKER), 'marker right after the function line')
ok(lines[i + 3] == '\tif ChaosSpellbook and ChaosSpellbook.openWindow and ChaosSpellbook.openWindow(player) then',
   'the hook, with the player argument')
ok(lines[i + 4] == '\t\treturn true' and lines[i + 5] == '\tend', 'returns before the text')
ok(lines[i + 6] == '\tlocal text = {}', 'the stock body follows')
ok(new.replace(''.join(l + '\n' for l in lines[i + 1:i + 6]), '') == STOCK, 'nothing else changed')
again, st2 = P.patch(new)
ok(st2 == 'already' and again == new, 'idempotent')

crlf = STOCK.replace('\n', '\r\n')
newc, stc = P.patch(crlf)
ok(stc == 'patched' and '\n' not in newc.replace('\r\n', ''), 'CRLF kept')

newo, sto = P.patch(OLD)
ok(sto == 'patched' and 'ChaosSpellbook.openWindow(cid) then' in newo, 'old XML action script: its own argument name')
ok('\n    if ChaosSpellbook' in newo, 'indent of the body kept')

other = 'local a = Action()\nfunction a.onUse(player, item)\n\treturn true\nend\n'
ok(P.patch(other) == (other, 'not a spellbook script'), 'other scripts untouched')

with tempfile.TemporaryDirectory() as d:
    data = os.path.join(d, 'data')
    os.makedirs(os.path.join(data, 'scripts', 'actions', 'others'))
    os.makedirs(os.path.join(data, 'actions', 'scripts'))
    book = os.path.join(data, 'scripts', 'actions', 'others', 'spellbook.lua')
    door = os.path.join(data, 'actions', 'scripts', 'door.lua')
    with open(book, 'w', newline='') as f:
        f.write(STOCK)
    with open(door, 'w', newline='') as f:
        f.write(other)

    def run(*a):
        return subprocess.run([sys.executable, '-I', TOOL] + list(a), capture_output=True, text=True)

    r = run(data, '--dry-run')
    ok(r.returncode == 0 and 'dry run' in r.stdout, 'dry run reports')
    ok(open(book, newline='').read() == STOCK, 'dry run writes nothing')
    r = run(data)
    ok(r.returncode == 0 and 'others/spellbook.lua: patched' in r.stdout.replace(os.sep, '/'), 'patched on disk')
    ok(P.MARKER in open(book, newline='').read(), 'file has the hook')
    ok(open(door, newline='').read() == other, 'other script untouched on disk')
    r = run(data)
    ok(r.returncode == 0 and 'already' in r.stdout, 'second run: already')
    r = run()
    ok(r.returncode == 2, 'no args')
    r = run(os.path.join(d, 'missing'))
    ok(r.returncode == 1, 'missing folder')
    empty = os.path.join(d, 'empty')
    os.makedirs(empty)
    r = run(empty)
    ok(r.returncode == 0 and 'nothing to do' in r.stdout, 'no spellbook script: nothing to do')

print('patch_base_spellbook_test: %d checks ok' % checks)

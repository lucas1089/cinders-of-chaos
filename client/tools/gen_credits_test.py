#!/usr/bin/env python3
"""python3 -I client/tools/gen_credits_test.py: gen_credits.py on small CREDITS texts (parse, refusals, Lua escapes,
JSON) and on the real docs/CREDITS.md (both generated files up to date)."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_credits as G  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        print('FAIL', what)
        fails += 1


def refused(text, what):
    try:
        G.parse(text)
    except G.CreditsError:
        return
    ok(False, 'refused: ' + what)


def doc(body):
    return 'intro\n\n' + G.BEGIN + '\n' + body + '\n' + G.END + '\n\n## Internal\n\n- **Hidden thing**\n'


SAMPLE = doc('''
## First part {pt-BR: Primeira parte}

A note that runs
over two lines with `code`.

- **Alpha Pack**
  - Author: Some Author
  - Credit: Alpha Pack - Some Author
  - Used for: spells
- **Béta "quoted" \\ pack**
  - Licence: free to use
  - Source: https://example.org/x

## Second {pt-BR: Segunda é}

- **Gamma**
''')

sections = G.parse(SAMPLE)
ok(len(sections) == 2, 'two sections, the internal part left out')
s1, s2 = sections
ok(s1['title'] == 'First part' and s1['pt'] == 'Primeira parte', 'heading and pt-BR heading')
ok(s1['note'] == 'A note that runs over two lines with code.', 'note joined, inline code marks dropped: ' + s1['note'])
ok([e['name'] for e in s1['entries']] == ['Alpha Pack', 'Béta "quoted" \\ pack'], 'entry names')
ok(s1['entries'][0] == {'name': 'Alpha Pack', 'author': 'Some Author', 'credit': 'Alpha Pack - Some Author', 'use': 'spells'},
   'entry fields')
ok(s2['entries'] == [{'name': 'Gamma'}] and s2['note'] == '', 'entry without fields')

lua = G.lua_data(sections)
ok(lua.isascii(), 'Lua data is ASCII')
ok('"B\\233ta \\"quoted\\" \\\\ pack"' in lua, 'cp1252 decimal escape, quotes and backslash escaped')
ok('pt = "Segunda \\233"' in lua, 'pt-BR heading escaped')
ok('{ name = "Alpha Pack", author = "Some Author", credit = "Alpha Pack - Some Author", use = "spells" },' in lua,
   'fields in a fixed order')
for interp in ('luajit', 'lua5.3'):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'data.lua')
        with open(path, 'w') as f:
            f.write(lua + 'io.write(ChaosCreditsData[1].entries[2].name, "|", #ChaosCreditsData)\n')
        try:
            out = subprocess.run([interp, path], capture_output=True, check=True).stdout
        except FileNotFoundError:
            continue
        ok(out == 'Béta "quoted" \\ pack|2'.encode('cp1252'), f'{interp} reads the cp1252 bytes: {out!r}')

data = json.loads(G.json_data(sections))
ok(data['source'] == 'docs/CREDITS.md' and len(data['sections']) == 2, 'JSON sections')
ok(data['sections'][0]['entries'][1]['source'] == 'https://example.org/x', 'JSON field')
ok('Béta' in G.json_data(sections), 'JSON keeps UTF-8 text')

refused('no markers', 'no markers')
refused(G.END + G.BEGIN, 'markers in the wrong order')
refused(doc('## Missing pt\n\n- **X**'), 'heading without pt-BR')
refused(doc('- **X**'), 'entry before a heading')
refused(doc('## A {pt-BR: B}\n\n- **X**\n  - Colour: red'), 'unknown field')
refused(doc('## A {pt-BR: B}\n\n- **X**\n  - Author: a\n  - Author: b'), 'field twice')
refused(doc('## A {pt-BR: B}'), 'empty section')
refused(doc(''), 'no section')
try:
    G.lua_data(G.parse(doc('## A {pt-BR: B}\n\n- **X☃**')))
    ok(False, 'a character without a cp1252 code is refused')
except G.CreditsError:
    pass

# the real file: both outputs up to date
with open(G.SOURCE, encoding='utf-8') as f:
    files = G.outputs(f.read())
for path, content in files.items():
    with open(path, encoding='utf-8') as f:
        ok(f.read() == content, os.path.relpath(path, G.ROOT) + ' is up to date (run gen_credits.py)')

print('gen_credits_test:', 'OK' if not fails else f'{fails} failure(s)')
sys.exit(1 if fails else 0)

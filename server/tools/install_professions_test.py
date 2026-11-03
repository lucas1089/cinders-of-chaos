#!/usr/bin/env python3
"""Tests of install_professions.py step 5 (O395): the refining recipe loader in the base crafting books.

usage: python3 -I server/tools/install_professions_test.py

The loader is written into a book of a temporary data folder (twice: the second run changes nothing; CRLF kept; a missing
book is skipped), then the patched book runs under LuaJIT and Lua 5.3 (from server/, as the engine runs it) with the real
data/lib/chaos_profession_recipes.lua: the recipes are added once, and a second load adds nothing.
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import install_professions as ip  # noqa: E402

checks = fails = 0


def ok(cond, what):
    global checks, fails
    checks += 1
    if not cond:
        fails += 1
        print('FAIL', what)


books = ip.refine_books()
ok(books == ['mining', 'herbalist', 'armorsmith'], 'books from the config: %r' % books)

STOCK = 'Crafting = Crafting or {}\nCrafting.mining = {\n    {id = 26413, name = "Stock", level = 10, cost = 1, count = 1, materials = {}},\n}\n'

tmp = tempfile.mkdtemp()
try:
    book_dir = os.path.join(tmp, 'scripts', 'customs', 'crafting')
    os.makedirs(book_dir)
    path = os.path.join(book_dir, 'mining.lua')
    open(path, 'w', newline='').write(STOCK)
    notes = ip.patch_recipe_loaders(tmp, False, ['mining', 'herbalist'])
    ok(any('mining.lua loader added' in n for n in notes), 'loader added: %r' % notes)
    ok(any('no crafting book herbalist.lua' in n for n in notes), 'missing book skipped: %r' % notes)
    once = open(path, newline='').read()
    ok(once.count(ip.RECIPE_MARK) == 1 and once.startswith(STOCK), 'block appended after the stock book')
    notes = ip.patch_recipe_loaders(tmp, False, ['mining'])
    ok(open(path, newline='').read() == once and any('present' in n for n in notes), 'second run changes nothing')
    dry = os.path.join(book_dir, 'herbalist.lua')
    open(dry, 'w', newline='').write(STOCK.replace('mining', 'herbalist'))
    ip.patch_recipe_loaders(tmp, True, ['herbalist'])
    ok(ip.RECIPE_MARK not in open(dry, newline='').read(), 'dry run writes nothing')
    crlf = os.path.join(book_dir, 'armorsmith.lua')
    open(crlf, 'w', newline='').write(STOCK.replace('mining', 'armorsmith').replace('\n', '\r\n'))
    ip.patch_recipe_loaders(tmp, False, ['armorsmith'])
    text = open(crlf, newline='').read()
    ok(ip.RECIPE_MARK in text and '\n' not in text.replace('\r\n', ''), 'CRLF kept')

    # run the patched book twice (a /reload) under both interpreters, from server/
    probe = os.path.join(tmp, 'probe.lua')
    open(probe, 'w').write('dofile(%r)\nlocal n1 = #Crafting.mining\ndofile(%r)\nlocal n2 = #Crafting.mining\n'
                           'local last = Crafting.mining[n2]\n'
                           'print(n1, n2, Crafting.mining[2].id, Crafting.mining[2].materials[1].id, '
                           'Crafting.mining[2].materials[1].count, last.chaosProfession and "tagged" or "plain")\n'
                           % (path, path))
    for interp in ('luajit', 'lua5.3'):
        if not shutil.which(interp):
            print('skip', interp)
            continue
        r = subprocess.run([interp, probe], cwd=SERVER, capture_output=True, text=True)
        ok(r.returncode == 0, '%s ran: %s' % (interp, r.stderr.strip()))
        parts = r.stdout.split()
        # each load builds the book again and gets the 5 delving recipes once (addRecipes twice on one list: professions_test)
        ok(parts[:6] == ['6', '6', '26398', '32351', '2', 'tagged'], '%s: 1 stock + 5 delving recipes, once: %r'
           % (interp, parts))
finally:
    shutil.rmtree(tmp)

print('install_professions_test: %d checks, %d failures' % (checks, fails))
sys.exit(1 if fails else 0)

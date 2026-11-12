#!/usr/bin/env python3
"""Test of audit_shared_looks.py (O529): python3 -I server/tools/audit_shared_looks_test.py

Synthetic monster folder, spawn file, pool and allow list: shared look found, colours that differ are no duplicate,
a mask-less outfit ignores colours, bosses (few spawns) are not met, the allow list covers or fails a group, the CI
pool rule (a masked look with colours that differ passes, the same colours need a row), the pool colours, and the tool's exit
code. Then the real repo: the committed pool passes the rule, every `recolour pair` row has its recolour table rows, and the
monsters recoloured by mask (O529) have colours that differ.
"""
import csv
import os
import subprocess
import sys
import tempfile
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import audit_shared_looks as A  # noqa: E402

TOOL = os.path.join(HERE, 'audit_shared_looks.py')


def xml(name, look, **c):
    col = ''.join(' %s="%d"' % (k, v) for k, v in c.items())
    return '<monster name="%s"><look type="%d"%s corpse="6068"/></monster>' % (name, look, col)


def main():
    with tempfile.TemporaryDirectory() as t:
        md = os.path.join(t, 'monster')
        os.makedirs(os.path.join(md, 'monsters'))
        os.makedirs(os.path.join(md, 'lua', 'x'))
        files = {'a': xml('Alpha', 100, head=10, body=20, legs=30, feet=40),
                 'b': xml('Bravo', 100, head=10, body=20, legs=30, feet=40),      # same look, same colours
                 'c': xml('Charlie', 100, head=94, body=20, legs=30, feet=40),    # colours differ: no duplicate
                 'd': xml('Delta', 200), 'e': xml('Echo', 200)}                    # no colours at all: shared
        reg = ['<monsters>']
        for k, v in files.items():
            open(os.path.join(md, 'monsters', k + '.xml'), 'w').write(v)
            reg.append('<monster name="%s" file="monsters/%s.xml" />' % (v.split('"')[1], k))
        reg.append('</monsters>')
        open(os.path.join(md, 'monsters.xml'), 'w').write('\n'.join(reg))
        open(os.path.join(md, 'lua', 'x', 'f.lua'), 'w').write(
            'local mType = Game.createMonsterType("Foxtrot")\nmonster.outfit = {\n\tlookType = 200,\n\tlookHead = 0,\n}\n')
        mons = A.load_monsters(md)
        assert [m['name'] for m in mons] == ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot'], mons
        gs = [sorted(m['name'] for m in g) for g in A.groups(mons)]
        assert ['Alpha', 'Bravo'] in gs and ['Charlie'] not in gs and ['Delta', 'Echo', 'Foxtrot'] in gs, gs
        assert A.colour_differs(10, 94) and not A.colour_differs(10, 10)
        # spawn file and the tool
        spawn = os.path.join(t, 'spawn.xml')
        open(spawn, 'w').write('<spawns><spawn>' + ''.join('<monster name="%s" x="0" y="0" z="0"/>' % n
                                                           for n in ['Alpha'] * 3 + ['Bravo'] * 3 + ['Delta'] * 5 + ['Echo'] * 1 + ['Foxtrot'] * 1)
                               + '</spawn></spawns>')
        allow = os.path.join(t, 'allow.csv')
        open(allow, 'w').write('look,names,status,reason\n')

        def run(*a):
            r = subprocess.run([sys.executable, '-I', TOOL, md, '--spawn', spawn, '--allow', allow, *a], capture_output=True, text=True)
            return r.returncode, r.stdout
        code, out = run('--check')
        assert code == 1 and 'look 100: Alpha | Bravo' in out and '1 not allowed' in out, out   # Delta alone is met (Echo, Foxtrot: 1 spawn)
        open(allow, 'w').write('look,names,status,reason\n100,Alpha | Bravo,kept,twins by design\n')
        code, out = run('--check')
        assert code == 0 and '0 not allowed' in out, out
        # pool rule
        pool = os.path.join(t, 'pool.lua')
        open(pool, 'w').write('return {\n\thunt = {\n\t\t{name = "Alpha", level = 5, exp = 1, health = 9, spawns = 9, look = 100},\n'
                              '\t\t{name = "Bravo", level = 5, exp = 1, health = 9, spawns = 9, look = 100},\n'
                              '\t\t{name = "Delta", level = 5, exp = 1, health = 9, spawns = 9, look = 200},\n\t},\n\tbosses = {\n'
                              '\t\t{name = "Echo", level = 5, exp = 1, health = 9, spawns = 1, look = 200},\n\t},\n}\n')
        assert A.pool_looks(pool) == [('Alpha', 9, 100), ('Bravo', 9, 100), ('Delta', 9, 200)]
        open(allow, 'w').write('look,names,status,reason\n')
        probs = A.check_pool(pool, allow)
        assert len(probs) == 1 and 'look 100 is shared by Alpha, Bravo' in probs[0], probs
        open(allow, 'w').write('look,names,status,reason\n100,Alpha | Bravo | Zulu,kept,r\n')
        assert A.check_pool(pool, allow) == []
        open(allow, 'w').write('look,names,status,reason\n101,Alpha | Bravo,kept,wrong look\n')
        assert len(A.check_pool(pool, allow)) == 1
        # a masked look: colours from the pool tell two monsters apart, equal colours need a row; the pool reads the colours
        open(pool, 'w').write('return {\n\thunt = {\n\t\t{name = "Alpha", level = 5, exp = 1, health = 9, spawns = 9, look = 100, head = 10, body = 20, legs = 30, feet = 40, addons = 0},\n'
                              '\t\t{name = "Bravo", level = 5, exp = 1, health = 9, spawns = 9, look = 100, head = 94, body = 20, legs = 30, feet = 40, addons = 0},\n'
                              '\t\t{name = "Charlie", level = 5, exp = 1, health = 9, spawns = 9, look = 100, head = 10, body = 20, legs = 30, feet = 40, addons = 0},\n\t},\n\tbosses = {\n\t},\n}\n')
        assert A.pool_rows(pool)[1]['head'] == 94 and A.pool_rows(pool)[0]['look'] == 100
        open(allow, 'w').write('look,names,status,reason\n')
        masks = {100: {'head', 'body', 'legs', 'feet'}}
        probs = A.check_pool(pool, allow, masks)
        assert len(probs) == 1 and 'Alpha, Charlie' in probs[0] and 'Bravo' not in probs[0], probs   # Bravo differs, the twins do not
        assert A.check_pool(pool, allow, {})   # without the mask all three share the look
        open(allow, 'w').write('look,names,status,reason\n100,Alpha | Charlie,kept,twins\n')
        assert A.check_pool(pool, allow, masks) == []
    # the repo itself
    probs = A.check_pool()
    assert not probs, probs
    allow_rows = A.load_allow()
    assert allow_rows and all(s in ('kept', 'recolour pair') and why for _, _, s, why in allow_rows), 'allow rows need a status and a reason'
    # the pool rows of the monsters recoloured by mask are the colours of their files (tune_monsters.py)
    rows = {r['name']: r for r in A.pool_rows()}
    for n in ('Blightcrown Matron', 'Limb Hoarder', 'Nailcrown Regent', 'Bloom Husk', 'Rustguard', 'Grave Lantern', 'Leechwing'):
        assert rows[n]['head'] not in (0, 133), n
    assert 1468 in A.load_masks() and 1501 in A.load_masks()
    print('audit_shared_looks_test: OK')


if __name__ == '__main__':
    main()

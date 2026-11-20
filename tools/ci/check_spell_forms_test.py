#!/usr/bin/env python3
"""python3 -I tools/ci/check_spell_forms_test.py: check_spell_forms.py on synthetic spell lists and Form rows (a missing spell, a
wrong kind for a tier, twin kinds, a conversion to the spell's own element, a bad override, a missing name, a spell that is no spell,
a row that differs from the doc) and on the repository (passes)."""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_spell_forms as C  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        print('FAIL', what)
        fails += 1


k1, k2, h1, h2, numbers = C.read_core()
LISTS = (k1, k2, h1, h2)
ok(len(k1) == 9 and len(k2) == 8 and len(h1) == 4 and len(h2) == 4, 'the core lists: 9 + 8 + 4 + 4 kinds: %s' % [len(k1), len(k2), len(h1), len(h2)])
ok('SPLIT' in numbers and 'pct' in numbers['SPLIT'] and 'cdcut' in numbers['SECONDWIND'], 'the numbers are read from the core')

SPELLS = {200: {'name': 'Bolt', 'group': 'attack', 'vocations': ['Mystic']},
          208: {'name': 'Mend', 'group': 'healing', 'vocations': ['Mystic']}}
EL = {200: 'fire', 208: ''}


def rows(spell=200, name='Bolt', role='damage', el='fire', kinds=('SPLIT', 'CHAIN', 'TWIN', 'SPREAD')):
    out = []
    for i, (tier, pick) in enumerate((('I', '1'), ('I', '2'), ('II', '1'), ('II', '2'))):
        out.append({'id': str(spell), 'spell': name, 'tier': tier, 'pick': pick, 'role': role, 'element': el, 'kind': kinds[i],
                    'over': '', 'name_en': 'N', 'name_pt': 'P'})
    return out


GOOD = rows() + rows(208, 'Mend', 'heal', '', ('RIPPLE', 'BLOOM', 'SECONDWIND', 'LINK'))


def check(rs, spells=SPELLS, doc=None):
    return C.problems(rs, spells, EL, LISTS, numbers, doc)


ok(check(GOOD) == [], 'a complete table passes: %s' % check(GOOD))

bad = check(rows())
ok(any('Mend (208): no Forms' in b for b in bad), 'a spell with no row is named')

bad = check(GOOD + rows(999, 'Ghost'))
ok(any('999' in b and 'not an attack or healing' in b for b in bad), 'a row of a spell that is none is named')

g = copy.deepcopy(GOOD)
g[0]['kind'] = 'TWIN'
bad = check(g)
ok(any('not a damage Form I' in b for b in bad), 'a Form II kind in tier I fails')

g = copy.deepcopy(GOOD)
g[4]['kind'] = 'SPLIT'
ok(any('not a heal Form I' in b for b in check(g)), 'a damage kind on a heal fails')

g = copy.deepcopy(GOOD)
g[1]['kind'] = 'SPLIT'
ok(any('both SPLIT' in b for b in check(g)), 'twin kinds in a tier fail')

g = copy.deepcopy(GOOD)
g[1]['kind'] = 'SHIFT:fire'
ok(any("own element" in b for b in check(g)), 'a conversion to the spell\'s own element fails')
g[1]['kind'] = 'SHIFT'
ok(any('needs an element' in b for b in check(g)), 'a conversion with no element fails')
g[1]['kind'] = 'SHIFT:plasma'
ok(any('unknown element' in b for b in check(g)), 'an unknown element fails')
g[1]['kind'] = 'SHIFT:weakest'
ok(any('weakest is for ASCEND' in b for b in check(g)), 'weakest is for tier II')
g[1]['kind'] = 'SHIFT:ice'
ok(check(g) == [], 'a good conversion passes')
g[3]['kind'] = 'ASCEND:weakest'
ok(check(g) == [], 'ASCEND:weakest passes')

g = copy.deepcopy(GOOD)
g[0]['over'] = 'pct=20'
ok(check(g) == [], 'a good override passes')
g[0]['over'] = 'bogus=1'
ok(any('bad override' in b for b in check(g)), 'an unknown override key fails')
g[0]['over'] = 'pct'
ok(any('bad override' in b for b in check(g)), 'an override with no value fails')

g = copy.deepcopy(GOOD)
g[2]['name_pt'] = ' '
ok(any('pt-BR name' in b for b in check(g)), 'a missing pt-BR name fails')

g = copy.deepcopy(GOOD)
g[3]['pick'] = '1'
ok(any('twice' in b for b in check(g)), 'a pick twice fails')

g = copy.deepcopy(GOOD)
g[0]['element'] = 'ice'
ok(any('the spell list says fire' in b for b in check(g)), 'an element that differs from the spell list fails')

g = copy.deepcopy(GOOD)
g[0]['role'] = 'heal'
ok(any('the role is heal' in b for b in check(g)), 'a wrong role fails')

doc = {'Bolt': ('SPLIT', 'CHAIN', 'TWIN', 'SPREAD')}
ok(check(GOOD, doc=doc) == [], 'a row equal to the doc passes')
doc = {'Bolt': ('SPLIT', 'CHAIN', 'TWIN', 'SIPHON')}
ok(any('differs from docs 2.5' in b for b in check(GOOD, doc=doc)), 'a row that differs from the doc fails')
doc = {'Nothing': ('SPLIT', 'CHAIN', 'TWIN', 'SIPHON')}
ok(any('not a spell of a class' in b for b in check(GOOD, doc=doc)), 'a doc spell that is none fails')

# the repository
spells = C.game_spells()
bad = C.problems(C.read_rows(), spells, C.spell_elements(), LISTS, numbers, C.doc_rows())
ok(bad == [], 'the repository passes: %s' % bad[:5])
ok(len(spells) == 149, '149 attack and healing spells: %d' % len(spells))
ok(len(C.doc_rows()) == 91, 'the doc wrote 91 spell rows (85 attack, 6 heal): %d' % len(C.doc_rows()))

if fails:
    print('%d failures' % fails)
    sys.exit(1)
print('check_spell_forms_test: ok')

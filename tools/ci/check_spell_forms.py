#!/usr/bin/env python3
"""Every attack and heal spell of every class has its Forms (O686 phase 4, docs/SPELL_UPGRADES.md section 2).

server/data/spells/forms.csv has one row per spell id, tier (I at rank 10, II at rank 20) and pick (1, 2): two Form I and two Form II
for every attack and healing spell of server/data/spells/chaos/spells_chaos.xml and stock_spells.csv, once for the spell however
many classes share it. Columns: id, spell, tier, pick, role (damage | heal), element (the spell's own, empty when it has none),
kind, over (overrides `key=number;key=number` of the kind's numbers in server/data/scripts/chaos/spell_forms_core.lua),
name_en, name_pt.

Checks:
 - every attack / healing spell with a class has exactly the four rows, no row for another spell, the name and the role match;
 - every kind is legal for its tier and role (the lists are read from spell_forms_core.lua: no second copy to drift), the two kinds of a
   tier differ, a conversion (SHIFT:E, ASCEND:E) names an element other than the spell's own, ASCEND:weakest only on tier II;
 - every override key exists in the kind's numbers;
 - an English and a pt-BR name on every row;
 - the element column equals the one of the client spell list (spelldata.lua) when it has one;
 - the Form tables of docs/SPELL_UPGRADES.md 2.5 (the rows the design wrote) are in the csv word for word.

    python3 -I tools/ci/check_spell_forms.py            # the check (CI)
    python3 -I tools/ci/check_spell_forms.py --table    # rows per class
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
import rotation_sim as R  # noqa: E402

FORMS = os.path.join(REPO, 'server', 'data', 'spells', 'forms.csv')
CORE = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'spell_forms_core.lua')
SPELLDATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosspells', 'spelldata.lua')
DOC = os.path.join(REPO, 'docs', 'SPELL_UPGRADES.md')
COLUMNS = ['id', 'spell', 'tier', 'pick', 'role', 'element', 'kind', 'over', 'name_en', 'name_pt']
ELEMENTS = ('physical', 'fire', 'ice', 'energy', 'earth', 'holy', 'death')


def read_core(path=CORE):
    """(kinds1, kinds2, heal1, heal2, numbers) from spell_forms_core.lua"""
    text = open(path, encoding='utf-8').read()

    def lst(name):
        m = re.search(r'F\.%s = \{([^}]*)\}' % name, text)
        return re.findall(r'"(\w+)"', m.group(1)) if m else []
    block = text[text.index('F.numbers = {'):]
    block = block[:block.index('\n}\n')]
    numbers = {}
    for m in re.finditer(r'^\t(\w+) = \{([^}]*)\},', block, re.M):
        numbers[m.group(1)] = set(re.findall(r'(\w+) =', m.group(2)))
    return lst('kinds1'), lst('kinds2'), lst('heal1'), lst('heal2'), numbers


def read_rows(path=FORMS):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def spell_elements(path=SPELLDATA):
    text = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)"[^\n]*', text):
        el = re.search(r'element = "(\w+)"', m.group(0))
        out[int(m.group(1))] = el.group(1) if el else ''
    return out


def game_spells():
    """{id: spell row} of the attack and healing spells that a class has"""
    out = {}
    for s in R.load_chaos() + R.load_stock():
        if s['group'] in ('attack', 'healing') and s['vocations'] and s['id'] not in out:
            out[s['id']] = s
    return out


def doc_rows(path=DOC):
    """{spell name: (I1, I2, II1, II2)} from the tables of section 2.5"""
    text = open(path, encoding='utf-8').read()
    sec = text[text.index('### 2.5 Examples'):text.index('## 3. Awakening')]
    out = {}
    for line in sec.split('\n'):
        if not line.startswith('|') or line.startswith('| Spell') or line.startswith('|---'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) != 3 or '/' not in cells[1] or '/' not in cells[2]:
            continue
        name = re.split(r' \[|, shared|, heal', cells[0])[0].strip()
        a, b = [x.strip().replace('SECOND WIND', 'SECONDWIND') for x in cells[1].split('/')]
        c, d = [x.strip().replace('SECOND WIND', 'SECONDWIND') for x in cells[2].split('/')]
        out.setdefault(name, (a, b, c, d))
    return out


def parse_kind(text):
    m = re.match(r'^([A-Z]+):(\w+)$', text)
    return (m.group(1), m.group(2)) if m else (text, None)


def kind_problem(kind, tier, heal, lists):
    kinds1, kinds2, heal1, heal2 = lists
    base, el = parse_kind(kind)
    legal = (heal1 if tier == 'I' else heal2) if heal else (kinds1 if tier == 'I' else kinds2)
    if base not in legal:
        return 'kind %s is not a %s Form %s' % (kind, 'heal' if heal else 'damage', tier)
    if base in ('SHIFT', 'ASCEND'):
        if el is None:
            return '%s needs an element' % base
        if el == 'weakest':
            return None if base == 'ASCEND' else 'weakest is for ASCEND'
        if el not in ELEMENTS:
            return 'unknown element %s' % el
    elif el is not None:
        return '%s takes no element' % base
    return None


def problems(rows, spells, elements, lists, numbers, doc=None):
    bad = []
    by_spell = {}
    for r in rows:
        if list(r.keys()) != COLUMNS:
            bad.append('columns are not %s' % ','.join(COLUMNS))
            return bad
        by_spell.setdefault(int(r['id']), []).append(r)
    for sid, s in sorted(spells.items()):
        if sid not in by_spell:
            bad.append('%s (%d): no Forms' % (s['name'], sid))
    for sid, rs in sorted(by_spell.items()):
        s = spells.get(sid)
        if not s:
            bad.append('spell %d (%s): not an attack or healing spell of a class' % (sid, rs[0]['spell']))
            continue
        heal = s['group'] == 'healing'
        seen = {}
        for r in rs:
            where = '%s (%d) %s%s' % (s['name'], sid, r['tier'], r['pick'])
            if r['spell'] != s['name']:
                bad.append('%s: the name is %s' % (where, r['spell']))
            if r['role'] != ('heal' if heal else 'damage'):
                bad.append('%s: the role is %s' % (where, r['role']))
            if r['tier'] not in ('I', 'II') or r['pick'] not in ('1', '2'):
                bad.append('%s: bad tier or pick' % where)
                continue
            key = (r['tier'], r['pick'])
            if key in seen:
                bad.append('%s: twice' % where)
            seen[key] = r
            msg = kind_problem(r['kind'], r['tier'], heal, lists)
            if msg:
                bad.append('%s: %s' % (where, msg))
            base, el = parse_kind(r['kind'])
            if el and el != 'weakest' and el == (r['element'] or elements.get(sid, '')) and el:
                bad.append('%s: %s converts to the spell\'s own element' % (where, r['kind']))
            if r['over']:
                keys = numbers.get(base, set())
                for part in r['over'].split(';'):
                    m = re.match(r'^\s*(\w+)\s*=\s*-?[\d.]+\s*$', part)
                    if not m or m.group(1) not in keys:
                        bad.append('%s: bad override %s' % (where, part))
            if not r['name_en'].strip() or not r['name_pt'].strip():
                bad.append('%s: an English and a pt-BR name are needed' % where)
            known = elements.get(sid)
            if known is not None and known != '' and r['element'] != known:
                bad.append('%s: the element is %s, the spell list says %s' % (where, r['element'], known))
            if r['element'] and r['element'] not in ELEMENTS:
                bad.append('%s: unknown element %s' % (where, r['element']))
        for tier in ('I', 'II'):
            a, b = seen.get((tier, '1')), seen.get((tier, '2'))
            if not a or not b:
                bad.append('%s (%d): Form %s needs picks 1 and 2' % (s['name'], sid, tier))
            elif a['kind'] == b['kind']:
                bad.append('%s (%d): the two Form %s are both %s' % (s['name'], sid, tier, a['kind']))
    if doc:
        names = {s['name']: sid for sid, s in spells.items()}
        for name, kinds in sorted(doc.items()):
            sid = names.get(name)
            if sid is None:
                bad.append('docs 2.5 names %s: not a spell of a class' % name)
                continue
            have = {(r['tier'], r['pick']): r['kind'] for r in by_spell.get(sid, [])}
            want = {('I', '1'): kinds[0], ('I', '2'): kinds[1], ('II', '1'): kinds[2], ('II', '2'): kinds[3]}
            if have != want:
                bad.append('%s: forms.csv %s differs from docs 2.5 %s' % (name, [have.get(k) for k in sorted(want)], [want[k] for k in sorted(want)]))
    return bad


def per_class(spells):
    out = {c: 0 for c, _, _ in R.CLASSES}
    for s in spells.values():
        for v in s['vocations']:
            if v in out:
                out[v] += 1
    return out


def main(argv):
    lists = read_core()[:4]
    numbers = read_core()[4]
    rows = read_rows()
    spells = game_spells()
    if '--table' in argv:
        n = per_class(spells)
        for cls, line, _ in R.CLASSES:
            print('%-13s %-12s %3d spells %4d Form rows' % (cls, line, n[cls], 4 * n[cls]))
    bad = problems(rows, spells, spell_elements(), lists, numbers, doc_rows())
    for b in bad:
        print('FAIL', b)
    if bad:
        return 1
    print('check_spell_forms: %d spells, %d Form rows, %d rows written in docs 2.5' % (
        len(spells), len(rows), 4 * len(doc_rows())))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

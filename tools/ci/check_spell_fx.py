#!/usr/bin/env python3
"""A spell does not show an effect of another element (O457).

The spell list of the client (client/overlay/modules/game_chaosspells/spelldata.lua) gives most spells an element.
Each effect id a spell can send has an element tag in server/data/spells/spell_fx_elements.csv (physical fire ice
energy earth holy death arcane, or `any` for dust, smoke, plain rings and other effects with no element). The rule: a
spell with element X sends only effects tagged X or `any`. The cases that are right by design are rows of
server/data/spells/spell_fx_allow.csv, each with its reason (a holy fire, a frost and lightning spell, a shadow mist).

What a spell sends is measured, not read from names: tools/ci/spell_fx_probe.lua runs the real script of every chaos
spell against a recording mock of the engine, once per vocation of the spell, with the real libraries (so the swap
layers of the effects pass, pair 29, pair 36 and the class effects decide the ids, as in the game). Spells whose cast
sends nothing in the mock (they need a corpse, a minion, a mine or a state) are counted in UNPROBED_MAX: the count may
only fall. The Monk finishers are given chi by the probe.

    python3 -I tools/ci/check_spell_fx.py            # the check (CI)
    python3 -I tools/ci/check_spell_fx.py --list     # also print what every spell sends, with names and tags
    python3 -I tools/ci/check_spell_fx.py --ids      # the effect ids sent by spells that the table does not know

Needs lua5.3 (CI has it). Deterministic; stdlib only.
"""
import concurrent.futures
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SPELLDATA = os.path.join(ROOT, 'client/overlay/modules/game_chaosspells/spelldata.lua')
SPELLS_XML = os.path.join(ROOT, 'server/data/spells/chaos/spells_chaos.xml')
TAGS = os.path.join(ROOT, 'server/data/spells/spell_fx_elements.csv')
ALLOW = os.path.join(ROOT, 'server/data/spells/spell_fx_allow.csv')
PROBE = os.path.join(ROOT, 'tools/ci/spell_fx_probe.lua')

ELEMENTS = ('physical', 'fire', 'ice', 'energy', 'earth', 'holy', 'death', 'arcane')
ANY = 'any'
VOC = {'Mystic': 1, 'Ranger': 3, 'Warrior': 4, 'Elementalist': 5, 'Deadeye': 7, 'Juggernaut': 8, 'Illusionist': 10,
       'Thief': 11, 'Ninja': 12, 'Samurai': 13, 'Berserker': 14, 'Beastmaster': 15, 'Monk': 17, 'Shadowfist': 18,
       'Iron Sage': 19, 'Necromancer': 20, 'Lich': 21, 'Bone Lord': 22, 'Templar': 23, 'Inquisitor': 24,
       'Sentinel': 25}
# spells with an element whose cast sends no effect in the mock (state dependent); may only fall
UNPROBED_MAX = 3


def spell_elements(path=SPELLDATA):
    """{spell id: (name, element)} of the spells of the client list that have an element"""
    with open(path, encoding='utf-8') as f:
        text = f.read()
    out = {}
    for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)"[^\n]*?element = "(\w+)"', text):
        out[int(m.group(1))] = (m.group(2), m.group(3))
    return out


def chaos_spells(path=SPELLS_XML):
    """[{id, name, script, vocs}] of the instant spells of spells_chaos.xml"""
    with open(path, encoding='utf-8') as f:
        text = re.sub(r'<!--.*?-->', '', f.read(), flags=re.S)
    out = []
    for m in re.finditer(r'<instant\s([^>]*)>(.*?)</instant>', text, re.S):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        vocs = re.findall(r'vocation name="([^"]*)"', m.group(2))
        out.append({'id': int(a['spellid']), 'name': a['name'], 'script': a['script'], 'vocs': vocs})
    return out


def read_csv(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def load_tags(path=TAGS):
    """{effect id: (name, element)}"""
    out = {}
    for r in read_csv(path):
        out[int(r['id'])] = (r['name'], r['element'])
    return out


def load_allow(path=ALLOW):
    """{(spell id, effect id): reason}"""
    out = {}
    for r in read_csv(path):
        out[(int(r['spell_id']), int(r['effect_id']))] = r['reason']
    return out


def element_ok(spell_element, effect_element):
    return effect_element == ANY or effect_element == spell_element


def violations(sent, spells, tags, allow):
    """sent: {spell id: set of effect ids}. Returns (errors, used allow keys). An id without a tag is an error too."""
    errors, used = [], set()
    for sid in sorted(sent):
        if sid not in spells:
            continue
        name, element = spells[sid]
        for eid in sorted(sent[sid]):
            tag = tags.get(eid)
            if tag is None:
                errors.append('%s (%d, %s): effect %d has no element tag in spell_fx_elements.csv' % (name, sid, element, eid))
            elif not element_ok(element, tag[1]):
                if (sid, eid) in allow:
                    used.add((sid, eid))
                else:
                    errors.append('%s (%d, %s) sends %s (%d, %s): another element; pick an effect of its own element or add '
                                  'a reason row to spell_fx_allow.csv' % (name, sid, element, tag[0], eid, tag[1]))
    return errors, used


def make_root():
    root = tempfile.mkdtemp(prefix='spellfx_')
    for sub in ('data/scripts', 'data/spells/scripts'):
        os.makedirs(os.path.join(root, sub))
    os.symlink(os.path.join(ROOT, 'server/data/lib'), os.path.join(root, 'data/lib'))
    os.symlink(os.path.join(ROOT, 'server/data/scripts/chaos'), os.path.join(root, 'data/scripts/chaos'))
    os.symlink(os.path.join(ROOT, 'server/data/spells/chaos'), os.path.join(root, 'data/spells/scripts/chaos'))
    return root


def parse_probe(lines):
    """the effect ids of the ME lines; a puff after a CANCEL line is the cancel puff, not a cast effect"""
    ids = []
    cancel = False
    for line in lines:
        p = line.split('\t')
        if p[0] == 'CANCEL':
            cancel = True
        elif p[0] == 'ME' and len(p) > 1 and p[1].isdigit():
            if cancel and p[1] == '3':
                continue
            ids.append(int(p[1]))
    return ids


def run_probe(root, spell, voc, dx):
    p = subprocess.run(['lua5.3', PROBE, str(VOC[voc]), str(spell['id']), spell['script'], '300', str(dx)], cwd=root,
                       capture_output=True, text=True, timeout=60)
    return p.stdout.strip().split('\n') if p.stdout.strip() else []


def probe_spell(root, spell):
    """effect ids over every vocation of the spell (the class swaps differ by vocation); a target out of reach is
    tried again close"""
    ids = set()
    for voc in spell['vocs']:
        if voc not in VOC:
            continue
        lines = run_probe(root, spell, voc, 5)
        if any(l.startswith('CANCEL') for l in lines):
            more = run_probe(root, spell, voc, 1)
            if len(parse_probe(more)) > len(parse_probe(lines)):
                lines = more
        ids.update(parse_probe(lines))
    return ids


def probe_all(spells, wanted):
    root = make_root()
    try:
        todo = [s for s in spells if s['id'] in wanted]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
            results = list(ex.map(lambda s: probe_spell(root, s), todo))
        return {s['id']: r for s, r in zip(todo, results)}
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main(argv):
    if shutil.which('lua5.3') is None:
        print('check_spell_fx: lua5.3 not found')
        return 1
    elements = spell_elements()
    spells = chaos_spells()
    tags = load_tags()
    allow = load_allow()
    problems = []
    for eid, (name, el) in tags.items():
        if el != ANY and el not in ELEMENTS:
            problems.append('tag of effect %d (%s): unknown element %s' % (eid, name, el))
    for (sid, eid), reason in allow.items():
        if sid not in elements:
            problems.append('allow row of spell %d: the spell has no element in spelldata' % sid)
        if eid not in tags:
            problems.append('allow row of effect %d: no tag' % eid)
        if not reason.strip():
            problems.append('allow row %d / %d: a reason is needed' % (sid, eid))
    sent = probe_all(spells, set(elements))
    unprobed = sorted(s for s in elements if not sent.get(s))
    if '--ids' in argv:
        unknown = sorted(set(i for ids in sent.values() for i in ids) - set(tags))
        print(' '.join(str(i) for i in unknown))
        return 0
    errors, used = violations(sent, elements, tags, allow)
    problems.extend(errors)
    for key in sorted(set(allow) - used):
        problems.append('allow row %d / %d is not needed any more: remove it' % key)
    if len(unprobed) > UNPROBED_MAX:
        problems.append('%d spells send nothing in the probe, at most %d: %s' % (
            len(unprobed), UNPROBED_MAX, ', '.join(elements[s][0] for s in unprobed)))
    if '--list' in argv:
        for sid in sorted(sent):
            print('%d %s (%s): %s' % (sid, elements[sid][0], elements[sid][1], ', '.join(
                '%d %s %s' % (i, tags.get(i, ('?', '?'))[0], tags.get(i, ('?', '?'))[1]) for i in sorted(sent[sid]))))
    if problems:
        print('check_spell_fx FAILED:')
        for p in problems:
            print('  ' + p)
        return 1
    print('check_spell_fx: ok (%d spells with an element, %d probed, %d not probed, %d effect ids tagged, %d reasons)' % (
        len(elements), len(elements) - len(unprobed), len(unprobed), len(tags), len(allow)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

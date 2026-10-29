#!/usr/bin/env python3
"""Auto setup knows every attack spell of the server's attack kit, with a sensible area / single rule (O157).

Owner report 2026-10-24: the helper's Auto setup gave a Thief only Blade Flurry, Fan of Knives and Shuriken Toss; the
Thief line's Gutting Slash, Razor Rain, Venom Spiral, Crescent Cut and Last Breath were not in its rotation. The helper
reads client/overlay/modules/game_helperrotation/autorotation_data.lua (written by server/tools/rotation_sim.py
--write): per class the presets (the best rotation per level) and the table `spells` that says which spell number is
an area spell. The helper's click tops a short preset up from the class's other presets and then its `extras` (the
attack spells no preset holds), so a spell in neither is never cast by Auto setup.

Checks:
 - every attack spell of server/data/scripts/chaos/attack_kit_config.lua is in the `spells` table, with the same name
   and words, and `area` true exactly for the shapes that hit a pack (circle, around, wave) and false for single, dot
   and line;
 - every attack spell of every class and ascension the rotation model can use (no skip / utility flag) is in the
   table, and in at least one preset or in the extras of each class that has it, so Auto setup can reach it;
 - every class with an ultimate (line spell quest 3, flag `ultimate` in rotation_model.csv) lists it as `ultimate = id`, and
   no preset or extras holds it (it takes no slot of the 5);
 - every preset spell belongs to its class (no spell of another class).
usage: python3 -I tools/ci/check_rotation_kit.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
import rotation_sim as R  # noqa: E402

KIT = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'attack_kit_config.lua')
DATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_helperrotation', 'autorotation_data.lua')
AREA_SHAPES = {'circle', 'around', 'wave'}
POINT_SHAPES = {'single', 'dot', 'line'}


def load_kit(path=KIT):
    text = open(path, encoding='utf-8').read()
    out = []
    for m in re.finditer(r'id = (\d+), name = "([^"]+)", words = "([^"]+)".*?shape = "(\w+)"', text, re.S):
        out.append({'id': int(m.group(1)), 'name': m.group(2), 'words': m.group(3), 'shape': m.group(4)})
    return out


def load_data(path=DATA):
    """(spells {id: {name, words, area}}, classes {server vocation id: {name, spells: set of the preset spells}})"""
    text = open(path, encoding='utf-8').read()
    head, _, table = text.partition('  spells = {')
    spells = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", words = "([^"]+)".*?area = (true|false)', table):
        spells[int(m.group(1))] = {'name': m.group(2), 'words': m.group(3), 'area': m.group(4) == 'true'}
    classes = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", presets = \{(.*?)\}, (?:extras = \{ ([\d, ]*) \}, )?(?:ultimate = (\d+), )?heals', head, re.S):
        ids = set()
        if m.group(4):
            ids.update(int(x) for x in m.group(4).split(','))
        ult = int(m.group(5)) if m.group(5) else None  # the class's ultimate (line spell quest 3): the helper casts it on top of the 5
        for p in re.finditer(r'spells = \{ ([\d, ]+) \}', m.group(3)):
            ids.update(int(x) for x in p.group(1).split(','))
        classes[m.group(2)] = {'voc': int(m.group(1)), 'spells': ids | ({ult} if ult else set()), 'slots': ids, 'ultimate': ult}
    return spells, classes


def problems(kit, spells, classes, model_spells, model):
    bad = []
    for k in kit:
        s = spells.get(k['id'])
        if not s:
            bad.append('%s (%d) is in the attack kit but not in autorotation_data.lua spells' % (k['name'], k['id']))
            continue
        if (s['name'], s['words']) != (k['name'], k['words']):
            bad.append('%s (%d): the rotation data has "%s" / "%s"' % (k['name'], k['id'], s['name'], s['words']))
        if k['shape'] in AREA_SHAPES and not s['area']:
            bad.append('%s: shape %s hits a pack but the rotation data says single target' % (k['name'], k['shape']))
        elif k['shape'] in POINT_SHAPES and s['area']:
            bad.append('%s: shape %s hits one target but the rotation data says area' % (k['name'], k['shape']))
        elif k['shape'] not in AREA_SHAPES | POINT_SHAPES:
            bad.append('%s: unknown shape %s (add it to AREA_SHAPES or POINT_SHAPES)' % (k['name'], k['shape']))
    for cls, _, _ in R.CLASSES:
        have = classes.get(cls)
        if not have:
            bad.append('class %s has no rotation data' % cls)
            continue
        mine = {s['id']: s for s in model_spells if s['group'] == 'attack' and cls in s['vocations'] and
                not model[s['words']]['flags'] & set(R.NO_PRESET)}
        for sid, s in sorted(mine.items()):
            if sid not in spells:
                bad.append('%s (%d, %s) is not in the rotation data spells' % (s['name'], sid, cls))
            elif sid not in have['spells']:
                bad.append('%s (%d) is in no preset or extras of %s: Auto setup never casts it' % (s['name'], sid, cls))
        ults = {sid for sid, s in mine.items() if R.ULTIMATE in model[s['words']]['flags']}
        if ults != ({have['ultimate']} if have['ultimate'] else set()):
            bad.append('%s: the rotation data ultimate is %s, the model has %s' % (cls, have['ultimate'], sorted(ults) or None))
        for sid in have['slots'] & ults:
            bad.append('%s: the ultimate %d is in a preset or the extras: it takes no slot of the 5' % (cls, sid))
        for sid in have['spells']:
            if sid not in mine:
                bad.append('%s preset holds spell %d, which is not an attack spell of %s' % (cls, sid, cls))
    return bad


def main():
    kit = load_kit()
    spells, classes = load_data()
    model_spells, model = R.load_all()
    bad = problems(kit, spells, classes, model_spells, model)
    for b in bad:
        print('FAIL ' + b)
    if bad:
        return 1
    print('rotation kit: %d kit spells, %d spells, %d classes: all known to Auto setup' % (len(kit), len(spells), len(classes)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

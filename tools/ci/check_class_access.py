#!/usr/bin/env python3
"""A class is offered exactly the spells its server lets it cast (O329).

Tester report (Beastmaster, level 750, 2026-10-29): the spell pickers listed Hail of Dawn, Twin Verdict, Final Verdict and
Skewering Line, which the server refuses ("not for your class"); he asked whether the other classes have the same hole. The
cause was client logic: the spell pickers also accepted the base client's translateVocation fold, which maps sibling
classes onto one id. The logic half is client/overlay/modules/game_spellbook/spellbook_access_test.lua (all 21 classes against
the server lists, with the real fold) and server/tools/weapon_coverage.lua --access (weapons). This check is the data half;
it reads only files of the repo:

 - every vocation name of spells_chaos.xml and stock_spells.csv is one of the 21 classes, every spell has at least one class,
   and no vocation list names a class twice;
 - the client's copy of the Chaos spells (game_chaosspells/spelldata.lua) has the server's name, words, level and class list for
   every spell id, and nothing else (check_rotation_kit.py also compares the vocations; this names the field that differs);
 - the 15-spell cap table the installer applies (server/tools/patch_spell_cap.py CAP) is what stock_spells.csv, the snapshot of
   the installed spells.xml, lists for each capped spell, and what the client cuts its stock entries to (ChaosCappedSpells);
 - every spell Auto setup casts (presets, extras, ultimate, heals) can be cast by the class that holds it: the server's class
   list of that spell id names the class;
 - every class has attack, healing and support spells to learn up to level 1500.
usage: python3 -I tools/ci/check_class_access.py [--table]      (--table prints how many spells each class can cast)
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
sys.path.insert(0, os.path.join(REPO, 'client', 'tools'))
import rotation_sim as R  # noqa: E402
from gen_spell_data import VOC  # noqa: E402

XML = os.path.join(REPO, 'server', 'data', 'spells', 'chaos', 'spells_chaos.xml')
CSV = os.path.join(REPO, 'server', 'data', 'spells', 'stock_spells.csv')
SPELLDATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosspells', 'spelldata.lua')
ROTATION = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_helperrotation', 'autorotation_data.lua')
CLASSES = [c for c, _, _ in R.CLASSES]


def load_chaos(path=XML):
    """{spell id: {name, words, level, group, vocations (names, in file order)}} of spells_chaos.xml"""
    text = re.sub(r'<!--.*?-->', '', open(path, encoding='utf-8').read(), flags=re.S)
    out = {}
    for m in re.finditer(r'<instant ([^>]*)>(.*?)</instant>', text, re.S):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        out[int(a['spellid'])] = {'name': a['name'], 'words': a['words'], 'level': int(a.get('level', '0')),
                                  'group': a.get('group', ''), 'vocations': re.findall(r'<vocation name="([^"]+)"', m.group(2))}
    return out


def load_stock(path=CSV):
    out = {}
    for r in csv.DictReader(open(path, encoding='utf-8')):
        out[int(r['id'])] = {'name': r['name'], 'words': r['words'], 'level': int(r['level']), 'group': r['group'],
                             'vocations': [v for v in r['vocations'].split(';') if v]}
    return out


def load_client(path=SPELLDATA):
    """{spell id: {name, words, level, vocations (ids)}} of ChaosSpellData, and ChaosCappedSpells {words: ids}"""
    text = open(path, encoding='utf-8').read()
    head, _, tail = text.partition('ChaosCappedSpells = {')
    data = {}
    for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)", words = "([^"]+)", level = (\d+).*?vocations = \{ ([\d, ]*) \}', head.split('ChaosSpellNames')[0]):
        data[int(m.group(1))] = {'name': m.group(2), 'words': m.group(3), 'level': int(m.group(4)),
                                 'vocations': {int(x) for x in m.group(5).split(',') if x.strip()}}
    capped = {}
    for m in re.finditer(r'\["([^"]+)"\] = \{ ?([\d, ]*)\}', tail):
        capped[m.group(1)] = {int(x) for x in m.group(2).split(',') if x.strip()}
    return data, capped


def load_rotation(path=ROTATION):
    """{class name: set of spell ids Auto setup casts or heals with}"""
    text = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", presets = \{(.*?)\}, (?:extras = \{ ([\d, ]*) \}, )?(?:ultimate = (\d+), )?heals = \{(.*?)\n    \} \}', text, re.S):
        ids = set()
        for p in re.finditer(r'spells = \{ ([\d, ]+) \}', m.group(3)):
            ids.update(int(x) for x in p.group(1).split(','))
        if m.group(4):
            ids.update(int(x) for x in m.group(4).split(','))
        if m.group(5):
            ids.add(int(m.group(5)))
        for h in re.finditer(r'\{ id = (\d+), level = \d+ \}', m.group(6)):
            ids.add(int(h.group(1)))
        out[m.group(2)] = ids
    return out


def problems(chaos, stock, client, capped_client, cap, rotation, levels=(1, 1500)):
    bad = []
    known = set(CLASSES)
    for label, table in (('spells_chaos.xml', chaos), ('stock_spells.csv', stock)):
        for sid, s in sorted(table.items()):
            if not s['vocations']:
                bad.append('%s: %s (%d) has no class' % (label, s['name'], sid))
            for v in s['vocations']:
                if v not in known:
                    bad.append('%s: %s (%d) names the unknown class %s' % (label, s['name'], sid, v))
            dup = sorted({v for v in s['vocations'] if s['vocations'].count(v) > 1})
            if dup:
                bad.append('%s: %s (%d) lists %s twice' % (label, s['name'], sid, ', '.join(dup)))
    # the client's copy of the Chaos spells
    for sid, s in sorted(chaos.items()):
        c = client.get(sid)
        if c is None:
            bad.append('%s (%d) is in the server spell XML but not in spelldata.lua (python3 -I client/tools/gen_spell_data.py)' % (s['name'], sid))
            continue
        want = {VOC[v] for v in s['vocations'] if v in VOC}
        for field in ('name', 'words', 'level'):
            if c[field] != s[field]:
                bad.append('%s (%d): the client has %s "%s", the server "%s"' % (s['name'], sid, field, c[field], s[field]))
        if c['vocations'] != want:
            bad.append('%s (%d): the client lists classes %s, the server %s' % (s['name'], sid, sorted(c['vocations']), sorted(want)))
    for sid, c in sorted(client.items()):
        if sid not in chaos:
            bad.append('%s (%d) is in spelldata.lua but not in the server spell XML' % (c['name'], sid))
    # the cap: the installer's table against the installed snapshot and the client's cut
    for script, (sid, name, keep) in sorted(cap.items(), key=lambda kv: kv[1][0]):
        row = stock.get(sid)
        if row is not None and set(row['vocations']) != set(keep):
            bad.append('cap: %s (%d) keeps %s in patch_spell_cap.py but stock_spells.csv lists %s' % (
                name, sid, sorted(keep), sorted(row['vocations'])))
        if row is not None and not keep:
            bad.append('cap: %s (%d) is retired but stock_spells.csv still lists it' % (name, sid))
    cap_ids = {tuple(sorted(VOC[v] for v in keep)) for _, (_, _, keep) in cap.items()}
    for words, ids in sorted(capped_client.items()):
        if tuple(sorted(ids)) not in cap_ids:
            bad.append('ChaosCappedSpells "%s" keeps %s, which no cap entry of patch_spell_cap.py has (run gen_spell_data.py)' % (words, sorted(ids)))
    # Auto setup casts only what the class can cast
    all_spells = dict(stock)
    all_spells.update(chaos)
    for cls, ids in sorted(rotation.items()):
        for sid in sorted(ids):
            s = all_spells.get(sid)
            if s is None:
                bad.append('%s: Auto setup holds spell %d, which the server does not have' % (cls, sid))
            elif cls not in s['vocations']:
                bad.append('%s: Auto setup holds %s (%d), which the server does not let this class cast' % (cls, s['name'], sid))
    # every class has something to learn in every group
    for cls in CLASSES:
        mine = [s for s in all_spells.values() if cls in s['vocations'] and s['level'] <= levels[1]]
        for group in ('attack', 'healing', 'support'):
            if not any(s['group'] == group for s in mine):
                bad.append('%s has no %s spell at all (levels %d-%d)' % (cls, group, levels[0], levels[1]))
    return bad


def main(argv):
    chaos, stock = load_chaos(), load_stock()
    client, capped_client = load_client()
    from patch_spell_cap import CAP
    rotation = load_rotation()
    if len(rotation) != len(CLASSES):
        print('FAIL autorotation_data.lua: read %d classes, expected %d' % (len(rotation), len(CLASSES)))
        return 1
    if '--table' in argv:
        for cls in CLASSES:
            n = sum(1 for s in list(chaos.values()) + list(stock.values()) if cls in s['vocations'])
            print('%-13s %3d spells (Chaos and stock attack / healing / support listed in the repo)' % (cls, n))
    bad = problems(chaos, stock, client, capped_client, CAP, rotation)
    for b in bad:
        print('FAIL', b)
    if bad:
        return 1
    print('check_class_access: %d Chaos spells and %d stock spells, %d classes: the client offers what the server casts' % (
        len(chaos), len(stock), len(CLASSES)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

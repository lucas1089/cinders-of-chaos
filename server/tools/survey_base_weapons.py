#!/usr/bin/env python3
"""Snapshot of the base server's weapons for the weapon coverage audit (server/README.md "Weapon coverage").

usage: python3 -I server/tools/survey_base_weapons.py INSTALLED_DATA        write server/data/items/base_weapons.csv
       python3 -I server/tools/survey_base_weapons.py INSTALLED_DATA --check  exit 1 when the committed file differs

INSTALLED_DATA is the data/ folder of a base server after `install_all.py` (the classes are in the vocation lists and
the launchers have their ammunition attack built in, so the numbers are what the game uses). Only the stock items are
kept (server id below FIRST_CHAOS_ID); everything Chaos adds (the fist weapons, the equipment sets, the pack art) is read
from its own data by tools/weapon_coverage.lua. No names are kept: the base names are not ours (the same rule as
data/items/base_item_values.csv); the audit joins the sources (shops, loot, recipes) by id from that file.

One row per weapon item of items.xml (weaponType sword, axe, club, distance or wand) that has an entry in weapons.xml:
  id, kind (sword, axe, club, bow, crossbow, throw, wand), hands (1 or 2), level (weapons.xml), attack (physical),
  element (the element damage added to it), defense, hit (hitChance, 0 = none), range, wmin / wmax / mana (wands),
  charges (a weapon with charges is used up or trains: training weapons, one-shot elemental swords; the audit skips it),
  classes ('*' = every class, else the class names of the vocation list joined with '|').
A launcher without an ammunition type is a bow or a crossbow (a name with a crossbow word is a crossbow: the config of
data/lib/chaos_archery_config.lua names them by id, `launchers`).
"""
import csv
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
OUT = os.path.join(SERVER, 'data', 'items', 'base_weapons.csv')
CONFIG = os.path.join(SERVER, 'data', 'lib', 'chaos_archery_config.lua')
FIRST_CHAOS_ID = 36654   # the fist weapons are the first item the repo adds (data/items/fist_items.csv)
COLS = ['id', 'kind', 'hands', 'level', 'attack', 'element', 'defense', 'hit', 'range', 'wmin', 'wmax', 'mana', 'charges', 'classes']
ELEMENTS = ('elementfire', 'elementice', 'elementearth', 'elementenergy', 'elementdeath', 'elementholy',
            'elementphysical')

KEYVAL = re.compile(r'<attribute\s+key\s*=\s*"([^"]+)"\s+value\s*=\s*"([^"]*)"', re.I)
ITEM = re.compile(r'<item\s+([^>]*?)(/?)>(.*?)(?:</item>|(?=<item\s))', re.S)
ENTRY = re.compile(r'<(melee|distance|wand)\b([^>]*?)(?:/>|>(.*?)</\1>)', re.S)
ATTR = re.compile(r'(\w+)\s*=\s*"([^"]*)"')


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def launcher_kinds():
    """id -> 'bow' | 'crossbow' from the archery config (the launchers table)"""
    text = re.sub(r'--[^\n]*', '', read(CONFIG))
    return {int(i): k for i, k, _lv in re.findall(r'\[(\d+)\]\s*=\s*\{"(\w+)",\s*(\d+)\}', text)}


def crossbow_word_list():
    text = re.sub(r'--[^\n]*', '', read(CONFIG))
    m = re.search(r'crossbowWords\s*=\s*\{([^}]*)\}', text)
    return re.findall(r'"([^"]+)"', m.group(1))


def weapon_items(items_xml):
    """id -> {name, attrs} for the items with a weaponType"""
    out = {}
    for m in ITEM.finditer(items_xml):
        head = dict(ATTR.findall(m.group(1)))
        if m.group(2) or not head.get('id', '').isdigit():
            continue
        attrs = {k.lower(): v for k, v in KEYVAL.findall(m.group(3))}
        if 'weapontype' in attrs:
            out[int(head['id'])] = {'name': head.get('name', ''), 'attrs': attrs}
    return out


def weapon_entries(weapons_xml):
    """id -> {tag, level, mana, min, max, classes} for the weapons.xml entries that name one item"""
    out = {}
    for m in ENTRY.finditer(weapons_xml):
        head = dict(ATTR.findall(m.group(2)))
        if not head.get('id', '').isdigit():
            continue
        names = re.findall(r'<vocation\s+name="([^"]+)"', m.group(3) or '')
        out[int(head['id'])] = {'tag': m.group(1), 'level': int(head.get('level', 0) or 0), 'mana': int(head.get('mana', 0) or 0),
                                'min': int(head.get('min', 0) or 0), 'max': int(head.get('max', 0) or 0),
                                'classes': names, 'action': head.get('action', '')}
    return out


MOVEVENT = re.compile(r'<movevent\b([^>]*?)(?:/>|>(.*?)</movevent>)', re.S)


def equip_rules(movements_xml):
    """id -> {level, classes} of the Equip events (movements.xml) that name an item; the unique equip block (it holds the
    rule of a unique, not of the stock item) is left out"""
    out = {}
    for m in MOVEVENT.finditer(movements_xml):
        head = dict(ATTR.findall(m.group(1)))
        if head.get('event', '').lower() != 'equip' or 'chaos_unique_equip' in head.get('script', ''):
            continue
        if head.get('itemid', '').isdigit():
            ids = [int(head['itemid'])]
        elif head.get('fromid', '').isdigit() and head.get('toid', '').isdigit():
            ids = range(int(head['fromid']), int(head['toid']) + 1)
        else:
            continue
        names = re.findall(r'<vocation\s+name="([^"]+)"', m.group(2) or '')
        for i in ids:
            out[i] = {'level': int(head.get('level', 0) or 0), 'classes': names}
    return out


def survey(data_dir):
    items = weapon_items(read(os.path.join(data_dir, 'items', 'items.xml')))
    entries = weapon_entries(read(os.path.join(data_dir, 'weapons', 'weapons.xml')))
    equips = equip_rules(read(os.path.join(data_dir, 'movements', 'movements.xml')))
    launchers = launcher_kinds()
    crossbow_words = crossbow_word_list()
    rows = []
    for wid in sorted(items):
        if wid >= FIRST_CHAOS_ID:
            continue
        a = items[wid]['attrs']
        wt = a['weapontype'].lower()
        if wt not in ('sword', 'axe', 'club', 'distance', 'wand'):
            continue
        # no weapons.xml entry: the engine's default weapon (no level, no class list); a wand has no damage then
        e = entries.get(wid) or {'tag': 'wand' if wt == 'wand' else 'melee', 'level': 0, 'mana': 0, 'min': 0, 'max': 0,
                                 'classes': [], 'action': 'default'}
        if wt == 'wand' and wid not in entries:
            continue
        eq = equips.get(wid)
        if eq:
            e = dict(e)
            e['level'] = max(e['level'], eq['level'])
            if eq['classes']:
                both = [c for c in e['classes'] if c in eq['classes']] if e['classes'] else eq['classes']
                e['classes'] = both or ['(nobody)']
        two = a.get('slottype', '') == 'two-handed'
        attack = int(a.get('attack', 0) or 0)
        element = sum(int(a.get(k, 0) or 0) for k in ELEMENTS)
        if wt == 'distance':
            if wid in launchers:
                kind = launchers[wid]
            elif two:
                low = items[wid]['name'].lower()
                kind = 'crossbow' if any(w in low for w in crossbow_words) else 'bow'
            else:
                kind = 'throw'
        elif wt == 'wand':
            kind = 'wand'
        else:
            kind = wt
        if kind == 'wand' and e['tag'] != 'wand':
            continue
        if kind in ('sword', 'axe', 'club', 'bow', 'crossbow', 'throw') and attack <= 0 and not element:
            continue
        rows.append({'id': wid, 'kind': kind, 'hands': 2 if two else 1, 'level': e['level'], 'attack': attack,
                     'element': element, 'defense': int(a.get('defense', 0) or 0), 'hit': int(a.get('hitchance', 0) or 0),
                     'range': int(a.get('range', 0) or 0), 'charges': int(a.get('charges', 0) or 0), 'wmin': e['min'], 'wmax': e['max'], 'mana': e['mana'],
                     'classes': '|'.join(e['classes']) if e['classes'] else '*'})
    buf = io.StringIO()
    w = csv.DictWriter(buf, COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue(), rows


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    text, rows = survey(args[0])
    if '--check' in argv:
        if read(OUT) != text:
            print('%s is out of date: python3 -I server/tools/survey_base_weapons.py INSTALLED_DATA' % OUT)
            return 1
        return 0
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    kinds = {}
    for r in rows:
        kinds[r['kind']] = kinds.get(r['kind'], 0) + 1
    print('%s: %d weapons %s' % (os.path.relpath(OUT, SERVER), len(rows), sorted(kinds.items())))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

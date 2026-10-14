#!/usr/bin/env python3
"""Readers of the base server's data for the item price table (server/tools/gen_item_prices.py; README "Item prices").

Only `gen_item_prices.py survey BASE_DATA` reads the base server: it writes the committed snapshot
server/data/items/base_item_values.csv (one row per base item that a monster drops, a recipe makes or an NPC trades)
and server/data/items/base_recipes.csv (the base crafting recipes). Everything else runs on the snapshot, so CI needs no
game data. No monster or NPC names are kept: only ids, numbers and the item names.

  items(data)            id -> {name, attrs}: items.xml (fromid/toid ranges expanded)
  levels(data)           id -> level requirement: movements.xml Equip and weapons.xml entries
  shops(data)            id -> {'sell': [(npc file, price)], 'buy': [(npc file, price)]}: data/npc XML parameters,
                         Lua addSellableItem / addBuyableItem and {id = n, buy = n, sell = n} tables (only in scripts
                         that pay in gold: a table shop of a script without removeMoney / addMoney trades in a coin of
                         its own); staff test NPCs and fluid subtypes left out
  monsters(data)         [{'level', 'loot': [(id, countmax, chance)]}]: monsters.xml (files that exist) and data/monster/lua
  recipes(data)          [{'id', 'count', 'cost', 'level', 'materials': [(id, count)], 'book'}]: scripts/customs/crafting
"""
import glob
import math
import os
import re

ATTR = re.compile(r'(\w+)\s*=\s*"([^"]*)"')
ITEM = re.compile(r'<item\s+([^>]*?)(/?)>(.*?)(?:</item>|(?=<item\s))', re.S)
KEYVAL = re.compile(r'<attribute\s+key\s*=\s*"([^"]+)"\s+value\s*=\s*"([^"]*)"')

XML_SELL = re.compile(r'key\s*=\s*"shop_sellable"\s+value\s*=\s*"([^"]*)"', re.S)
XML_BUY = re.compile(r'key\s*=\s*"shop_buyable"\s+value\s*=\s*"([^"]*)"', re.S)
LUA_SELL = re.compile(r'addSellableItem\s*\(\s*(?:\{[^}]*\}|nil|"[^"]*"|\'[^\']*\')\s*,\s*(\d+)\s*,\s*(\d+)')
LUA_BUY = re.compile(r'addBuyableItem\s*\(\s*(?:\{[^}]*\}|nil|"[^"]*"|\'[^\']*\')\s*,\s*(\d+)\s*,\s*(\d+)')
LUA_TABLE = re.compile(r'\{[^{}]*?\b(?:id|itemId)\s*=\s*(\d+)[^{}]*\}')
LUA_TBUY = re.compile(r'\b(?:buy|buyPrice)\s*=\s*(\d+)')
LUA_TSELL = re.compile(r'\b(?:sell|sellPrice)\s*=\s*(\d+)')
GOLD = re.compile(r'removeMoney|removeTotalMoney|addMoney')


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def items(data):
    out = {}
    for m in ITEM.finditer(read(os.path.join(data, 'items', 'items.xml'))):
        head = dict(ATTR.findall(m.group(1)))
        body = '' if m.group(2) else m.group(3)
        attrs = {k.lower(): v for k, v in KEYVAL.findall(body)}
        name = head.get('name', '').strip()
        if head.get('id', '').isdigit():
            ids = [int(head['id'])]
        elif head.get('fromid', '').isdigit() and head.get('toid', '').isdigit():
            ids = range(int(head['fromid']), int(head['toid']) + 1)
        else:
            continue
        for i in ids:
            out.setdefault(i, {'name': name, 'attrs': attrs})
    return out


def levels(data):
    out = {}

    def put(i, lv):
        if lv > out.get(i, 0):
            out[i] = lv

    mv = os.path.join(data, 'movements', 'movements.xml')
    if os.path.exists(mv):
        for tag in re.findall(r'<movevent\s[^>]*>', read(mv)):
            a = dict(ATTR.findall(tag))
            if a.get('event', '').lower() != 'equip' or not a.get('level', '').isdigit():
                continue
            lv = int(a['level'])
            if a.get('itemid', '').isdigit():
                put(int(a['itemid']), lv)
            elif a.get('fromid', '').isdigit() and a.get('toid', '').isdigit():
                for i in range(int(a['fromid']), int(a['toid']) + 1):
                    put(i, lv)
    wp = os.path.join(data, 'weapons', 'weapons.xml')
    if os.path.exists(wp):
        for tag in re.findall(r'<(?:melee|distance|wand)\s[^>]*>', read(wp)):
            a = dict(ATTR.findall(tag))
            if a.get('id', '').isdigit() and a.get('level', '').isdigit():
                put(int(a['id']), int(a['level']))
            elif a.get('fromid', '').isdigit() and a.get('toid', '').isdigit() and a.get('level', '').isdigit():
                for i in range(int(a['fromid']), int(a['toid']) + 1):
                    put(i, int(a['level']))
    return out


def npc_files(data, pattern):
    """NPC files without the staff test NPCs (a file name containing "test" trades at token prices)."""
    return [p for p in sorted(glob.glob(os.path.join(data, 'npc', pattern)))
            if 'test' not in os.path.basename(p).lower()]


def _xml_entries(value):
    for entry in value.split(';'):
        parts = [p.strip() for p in entry.split(',')]
        if len(parts) < 3 or not parts[1].isdigit() or not parts[2].isdigit():
            continue
        if len(parts) >= 4 and parts[3] not in ('', '0', '1'):
            continue  # fluid subtype (1 is a count on a few lists)
        yield int(parts[1]), int(parts[2])


def active_npcs(data):
    """NPC files of the NPCs that are in the game: named in the map's spawn file or created by a script
    (Game.createNpc("name")). Returns (xml file names, Lua script file names) or None when there is no spawn file."""
    spawns = glob.glob(os.path.join(data, 'world', '*-spawn.xml'))
    if not spawns:
        return None
    names = set()
    for p in spawns:
        names.update(n.lower() for n in re.findall(r'<npc\s+name="([^"]+)"', read(p)))
    for root, _, fs in os.walk(data):
        for f in fs:
            if f.endswith('.lua'):
                names.update(n.lower() for n in re.findall(r'createNpc\(\s*"([^"]+)"', read(os.path.join(root, f))))
    xml, lua = set(), set()
    for p in glob.glob(os.path.join(data, 'npc', '*.xml')):
        m = re.search(r'<npc\s([^>]*)>', read(p))
        a = dict(ATTR.findall(m.group(1))) if m else {}
        stem = os.path.splitext(os.path.basename(p))[0].lower()  # a spawn names the NPC file, a script the NPC
        if a.get('name', '').lower() in names or stem in names:
            xml.add(os.path.basename(p))
            if a.get('script'):
                lua.add(os.path.basename(a['script']))
    return xml, lua


def shops(data, active_only=False):
    """active_only: only the NPCs in the game (active_npcs); the others are skipped"""
    out = {}
    active = active_npcs(data) if active_only else None

    def put(side, i, price, who):
        if i > 0 and price > 0:
            out.setdefault(i, {'sell': [], 'buy': []})[side].append((who, price))

    for path in npc_files(data, '*.xml'):
        text, who = read(path), os.path.basename(path)
        if active and who not in active[0]:
            continue
        for value in XML_SELL.findall(text):
            for i, p in _xml_entries(value):
                put('sell', i, p, who)
        for value in XML_BUY.findall(text):
            for i, p in _xml_entries(value):
                put('buy', i, p, who)
    for path in npc_files(data, os.path.join('scripts', '*.lua')):
        text, who = read(path), os.path.basename(path)
        if active and who not in active[1]:
            continue
        for i, p in LUA_SELL.findall(text):
            put('sell', int(i), int(p), who)
        for i, p in LUA_BUY.findall(text):
            put('buy', int(i), int(p), who)
        for m in (LUA_TABLE.finditer(text) if GOLD.search(text) else ()):  # a table shop in another currency: skipped
            body = m.group(0)
            b, s = LUA_TBUY.search(body), LUA_TSELL.search(body)
            if b:
                put('buy', int(m.group(1)), int(b.group(1)), who)
            if s:
                put('sell', int(m.group(1)), int(s.group(1)), who)
    return out


def estimate_level(experience, health):
    """ChaosItemMods.estimateMonsterLevel (data/lib/chaos_item_mods.lua): the hunting level of a monster"""
    by_exp = 1.6 * math.sqrt(max(experience, 1))
    by_hp = health / 60.0
    return max(1, int(math.floor(max(by_exp, min(by_hp, by_exp * 1.5)) + 0.5)))


def parse_monster(text, lua, names):
    """{'level', 'loot': [(id, countmax, chance)]} or None"""
    loot = []
    if not lua:
        h = re.search(r'<health\s+now="(\d+)"', text)
        e = re.search(r'<monster\s[^>]*experience="(\d+)"', text)
        if not h:
            return None
        health, exp = int(h.group(1)), int(e.group(1)) if e else 0
        block = re.search(r'<loot>(.*?)</loot>', text, re.S)
        for tag in re.findall(r'<item\s[^>]*>', block.group(1) if block else ''):
            iid = re.search(r'\bid="(\d+)"', tag)
            if iid:
                iid = int(iid.group(1))
            else:
                n = re.search(r'\bname="([^"]+)"', tag)
                iid = n and names.get(n.group(1).lower())
            if not iid:
                continue
            cmax = re.search(r'countmax="(\d+)"', tag)
            chance = re.search(r'chance="(\d+)"', tag)
            loot.append((iid, int(cmax.group(1)) if cmax else 1, int(chance.group(1)) if chance else 0))
    else:
        h = re.search(r'monster\.health\s*=\s*(\d+)', text)
        e = re.search(r'monster\.experience\s*=\s*(\d+)', text)
        if not h:
            return None
        health, exp = int(h.group(1)), int(e.group(1)) if e else 0
        block = re.search(r'monster\.loot\s*=\s*\{(.*?)\n\}', text, re.S)
        for entry in re.findall(r'\{([^{}]*)\}', block.group(1) if block else ''):
            iid = re.search(r'\bid\s*=\s*(\d+)', entry) or re.search(r'itemId\s*=\s*(\d+)', entry)
            if iid:
                iid = int(iid.group(1))
            else:
                n = re.search(r'\bid\s*=\s*"([^"]+)"', entry) or re.search(r'name\s*=\s*"([^"]+)"', entry)
                iid = n and names.get(n.group(1).lower())
            if not iid:
                continue
            cmax = re.search(r'maxCount\s*=\s*(\d+)', entry)
            chance = re.search(r'chance\s*=\s*(\d+)', entry)
            loot.append((iid, int(cmax.group(1)) if cmax else 1, int(chance.group(1)) if chance else 0))
    lv = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', text) if not lua else None
    level = (int(lv.group(1)) + int(lv.group(2))) // 2 if lv else estimate_level(exp, health)
    return {'level': level, 'experience': exp, 'loot': loot}


def monsters(data, names):
    out = []
    mdir = os.path.join(data, 'monster')
    seen = set()
    xml = os.path.join(mdir, 'monsters.xml')
    if os.path.exists(xml):
        for name, f in re.findall(r'<monster\s+name="([^"]+)"\s+file="([^"]+)"', read(xml)):
            p = os.path.join(mdir, f)
            if not os.path.exists(p) or name.lower() in seen:
                continue
            m = parse_monster(read(p), False, names)
            if m:
                seen.add(name.lower())
                out.append(m)
    for root, _, fs in os.walk(os.path.join(mdir, 'lua')):
        for f in sorted(fs):
            if not f.endswith('.lua'):
                continue
            text = read(os.path.join(root, f))
            n = re.search(r'createMonsterType\("([^"]+)"\)', text)
            if not n or n.group(1).lower() in seen:
                continue
            m = parse_monster(text, True, names)
            if m:
                seen.add(n.group(1).lower())
                out.append(m)
    return out


def recipes(data):
    out = []
    for path in sorted(glob.glob(os.path.join(data, 'scripts', 'customs', 'crafting', '*.lua'))):
        book = os.path.splitext(os.path.basename(path))[0]
        text = read(path)
        for m in re.finditer(r'\{\s*id\s*=\s*(\d+),(.*?)materials\s*=\s*\{(.*?)\}\s*,?\s*\}', text, re.S):
            head = m.group(2)
            cost = re.search(r'\bcost\s*=\s*(\d+)', head)
            count = re.search(r'\bcount\s*=\s*(\d+)', head)
            level = re.search(r'\blevel\s*=\s*(\d+)', head)
            mats = [(int(a), int(b)) for a, b in re.findall(r'id\s*=\s*(\d+)\s*,\s*count\s*=\s*(\d+)', m.group(3))]
            if not mats:
                continue
            out.append({'id': int(m.group(1)), 'count': int(count.group(1)) if count else 1,
                        'cost': int(cost.group(1)) if cost else 0, 'level': int(level.group(1)) if level else 0,
                        'materials': mats, 'book': book})
    return out

#!/usr/bin/env python3
"""Write client/overlay/modules/game_chaosspells/spelldata.lua from the server spell definitions, so the
client's spell list and action bar know the same words, levels, mana and cooldowns.
usage (from the repo root): python3 -I client/tools/gen_spell_data.py"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_spell_icons import ICONS

FIRST_ICON = 201  # Chaos cells in the spell icon sheets (client/tools/gen_all_spell_icons.py draws them)
VOC = {'Mystic': 1, 'Ranger': 3, 'Warrior': 4, 'Elementalist': 5, 'Deadeye': 7, 'Juggernaut': 8, 'Illusionist': 10,
       'Thief': 11, 'Ninja': 12, 'Samurai': 13, 'Berserker': 14, 'Beastmaster': 15,
       'Monk': 17, 'Shadowfist': 18, 'Iron Sage': 19, 'Necromancer': 20, 'Lich': 21, 'Bone Lord': 22,
       'Templar': 23, 'Inquisitor': 24, 'Sentinel': 25}  # server vocation ids (docs/CLASSES.md)
GROUP = {'attack': 1, 'healing': 2, 'support': 3}
# stale stock entries of the client that no server spell has: hidden from the spell list with the removed spells
# (old words, client name). "Conjure Wand of Darkness" carries spell id 92, the server's Enchant Staff id; no rune shares it.
CLIENT_ONLY_REMOVED = [('exevo gran mort', 'Conjure Wand of Darkness')]
# stock spells the server retired (server/tools/retire_cure_spells.py OTHERS; old words, client name). Unlike the removed
# ones they keep no id: spellfix.lua moves them off the server's ids like every stock entry the server does not know
# (Tautstring has Hawkeye's id 135 now, Ironhold Bulwark's 132, Wildstride Windrunner's 134). The spell list leaves them out (chaosspells.lua hideRemovedSpells).
RETIRED_STOCK = [('utito tempo san', 'Sharpshooter'), ('utamo tempo', 'Protector'), ('utamo tempo san', 'Swift Foot'),
                 ('utevo lux', 'Lantern'), ('utevo gran lux', 'Greater Lantern'), ('utevo vis lux', 'Radiant Lantern')]

KIT_CFG = 'server/data/scripts/chaos/attack_kit_config.lua'
AREAS_CFG = 'server/data/scripts/chaos/spellbook_areas_config.lua'
ELEMENT = {'PHYSICALDAMAGE': 'physical', 'FIREDAMAGE': 'fire', 'ICEDAMAGE': 'ice', 'ENERGYDAMAGE': 'energy',
           'EARTHDAMAGE': 'earth', 'DEATHDAMAGE': 'death', 'HOLYDAMAGE': 'holy', 'DROWNDAMAGE': 'drown'}
# a stock-style area constant of a spell script -> (shape, size): AREA_CIRCLE3X3 is the 3x3 disc (radius 1), AREA_SQUARE1X1 the
# 3x3 square around the caster, AREA_BEAMn a line of n tiles
AREA_SHAPE = re.compile(r'AREA_(CIRCLE|SQUARE|BEAM|WAVE)(\d+)(?:X\d+)?$')

def _lua_rows(path, row_re):
    """{spell name: {field: value}} of the one-line rows / blocks of a server Lua config (numbers and strings only)"""
    out = {}
    text = open(path, encoding='utf-8').read()
    for m in re.finditer(row_re, text, re.S):
        block = m.group('body')
        fields = {}
        for k, v in re.findall(r'(\w+) = ("[^"]*"|-?[\d.]+)', block):
            fields[k] = v.strip('"') if v.startswith('"') else float(v)
        out[m.group('name')] = fields
    return out

def area_hints():
    """{spell name: {shape, radius/length/depth/halfWidth, ctype}}: the attack kit (shape, radius, length, ctype) and the
    Spellbook's area rows (spellbook_areas_config.lua), the same sources server/data/scripts/chaos/spellbook.lua reads"""
    kit = _lua_rows(KIT_CFG, r'\n\t\t\w+ = \{(?P<body>\s+id = \d+, name = "(?P<name>[^"]+)".*?)\n\t\t\}')
    rows = _lua_rows(AREAS_CFG, r'\["(?P<name>[^"]+)"\] = \{(?P<body>[^}]*)\}')
    out = dict(kit)
    out.update({k: v for k, v in rows.items()})
    return out

def spell_area(a, script_text, hints):
    """(shape, size, width) of a spell: shape single | self | circle | around | wave | line, size = radius / length /
    depth, width = the wave's tiles across; None when the data does not say"""
    h = hints.get(a['name'])
    if h and 'shape' in h:
        shape = h['shape']
        if shape == 'dot':
            return 'single', 0, 0
        if shape in ('circle', 'around'):
            return shape, int(h.get('radius', 1)), 0
        if shape == 'line':
            return 'line', int(h.get('length', 1)), 0
        if shape == 'wave':
            return 'wave', int(h.get('depth', 2)), 2 * int(h.get('halfWidth', 1)) + 1
        if shape == 'single':
            return 'single', 0, 0
    m = re.search(r'createCombatArea\((AREA_[A-Z0-9_]+)\)', script_text or '')
    if m:
        am = AREA_SHAPE.match(m.group(1))
        if am:
            kind, n = am.group(1), int(am.group(2))
            if kind == 'CIRCLE':
                return ('circle' if a.get('needtarget') == '1' or a.get('selftarget') != '1' else 'around'), max(1, n // 2), 0
            if kind == 'SQUARE':
                return 'around', n, 0
            return 'line', n, 0  # BEAM / WAVE
    # a matrix written in the script: 1 hit, 3 the caster / centre (spellbook.lua reads the same)
    m = re.search(r'createCombatArea\(\{(.*?)\n?\}\s*\)', script_text or '', re.S)
    rows = [[int(x) for x in r.split(',') if x.strip()] for r in re.findall(r'\{([\d,\s]+)\}', m.group(1))] if m else []
    if rows and len({len(r) for r in rows}) == 1 and sum(map(sum, rows)) > 3:
        h, w = len(rows), len(rows[0])
        if w == 1:
            return 'line', h - 1, 0
        if 3 in rows[-1] and h > 1 and 3 not in sum(rows[:-1], []):
            return 'wave', h - 1, w
        return ('circle' if a.get('needtarget') == '1' else 'around'), max(h, w) // 2, 0
    if a.get('needtarget') == '1' or int(a.get('range', '0') or 0) > 0:
        return 'single', 0, 0
    if a.get('selftarget') == '1' or a.get('group') != 'attack':
        return 'self', 0, 0
    return None

def spell_element(name, script_text, hints):
    """the element word of a spell: the kit's ctype, else the damage type its script sets (COMBAT_PARAM_TYPE first)"""
    h = hints.get(name)
    if h and h.get('ctype') in ELEMENT.values():
        return h['ctype']
    text = script_text or ''
    m = re.search(r'COMBAT_PARAM_TYPE,\s*COMBAT_([A-Z]+DAMAGE)', text) or re.search(r'COMBAT_([A-Z]+DAMAGE)', text)
    return ELEMENT.get(m.group(1)) if m else None

def quest_numbers():
    """{spell name: 1..3} of the line spell quests' spells (server spellquest_config.lua `spells = {quest 1, 2, 3}` per line)"""
    text = open('server/data/scripts/chaos/spellquest_config.lua', encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'spells = \{"([^"]+)", "([^"]+)", "([^"]+)"\}', text):
        for i in (1, 2, 3):
            out[m.group(i)] = i
    return out

def main():
    quests = quest_numbers()
    xml = open('server/data/spells/chaos/spells_chaos.xml', encoding='utf-8').read()
    icon_of = {name: i for i, (name, _, _) in enumerate(ICONS)}
    hints = area_hints()
    out = ['-- GENERATED by client/tools/gen_spell_data.py from server/data/spells/chaos/spells_chaos.xml. Do not edit.',
           '-- first icon cell: %d (see client/tools/gen_all_spell_icons.py)' % FIRST_ICON, 'ChaosSpellData = {']
    for m in re.finditer(r'<instant ([^>]*)>(.*?)</instant>', xml, re.S):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        name = a['name']
        voc = [VOC[v] for v in re.findall(r'<vocation name="([^"]+)"', m.group(2))]
        idx = icon_of[name]
        # direction="1": the spell hits along the caster's facing (a wave or beam). The helper turns the character toward its
        # target before it (ChaosHelperRotation.turnDirection), and the area the script uses lets it count monsters in the
        # beam (areaName: a SpellAreas key of the client's gamelib, found in the spell script's createCombatArea call)
        directional = ''
        if a.get('direction') == '1':
            directional = ', directional = true'
            script = os.path.join('server', 'data', 'spells', a['script'])
            am = re.search(r'createCombatArea\((AREA_[A-Z0-9_]+)\)', open(script, encoding='utf-8').read())
            if am:
                directional += ', areaName = "%s"' % am.group(1)
        # the helper's spell list shows where a spell hits and what it is made of (game_helper/spellinfo_logic.lua): the
        # area shape (areaShape single | self | circle | around | wave | line; areaSize = radius, length or depth; areaWidth =
        # tiles across a wave) and the damage element, from the attack kit, the Spellbook's area rows and the spell script
        try:
            script_text = open(os.path.join('server', 'data', 'spells', a['script']), encoding='utf-8').read()
        except OSError:
            script_text = ''
        extra = ''
        area = spell_area(a, script_text, hints)
        if area:
            extra += ', areaShape = "%s"' % area[0]
            if area[1]:
                extra += ', areaSize = %d' % area[1]
            if area[2]:
                extra += ', areaWidth = %d' % area[2]
        element = spell_element(name, script_text, hints)
        if element:
            extra += ', element = "%s"' % element
        directional += extra
        out.append('  {{ id = {id}, name = "{name}", words = "{words}", level = {level}, mana = {mana}, '
                   'group = {g}, groupCooldown = {gcd}, cooldown = {cd}, premium = {prem}, '
                   'needTarget = {nt}, range = {rng}, vocations = {{ {voc} }}, iconKey = "chaos_{key}", clientId = {cid}{pct}{dr}{qs} }},'.format(
                       dr=directional, qs=', quest = %d' % quests[name] if name in quests else '',
                       id=a['spellid'], name=name.replace('"', '\\"'), words=a['words'], level=a['level'], mana=a.get('mana', '0'),
                       # manapercent: the cost is that percentage of the maximum mana (the server's Spell::getManaCost
                       # reads it when mana is 0); chaosspells.lua keeps the entry's mana at the player's current cost
                       pct=', manaPercent = %s' % a['manapercent'] if a.get('manapercent') and a.get('mana', '0') == '0' else '',
                       g=GROUP[a['group']], gcd=a['groupcooldown'], cd=a['cooldown'], prem='true' if a.get('premium') == '1' else 'false',
                       nt='true' if a.get('needtarget') == '1' else 'false', rng=a.get('range', '0'),
                       voc=', '.join(map(str, voc)), key=re.sub(r'[^a-z0-9]+', '', name.lower()), cid=FIRST_ICON + idx))
    out.append('}')
    # stock spells: Chaos names by words (server/data/spells/spell_names.csv, applied to the server by
    # server/tools/rename_spells.py); chaosspells.lua renames the client's own spell entries with it
    import csv
    parts = {r['old']: r['new'] for r in csv.DictReader(open('server/data/spells/spell_words.csv', encoding='utf-8'))}
    out += ['', '-- stock spells: old words -> Chaos name and words (server/data/spells/spell_names.csv, spell_words.csv)',
            'ChaosSpellNames = {']
    rows = list(csv.DictReader(open('server/data/spells/spell_names.csv', encoding='utf-8')))
    for r in rows:
        if r['words']:
            words = ' '.join(parts[t] for t in r['words'].split())
            out.append('  ["%s"] = { name = "%s", words = "%s" },' % (r['words'], r['new_name'].replace('"', '\\"'), words))
    out.append('}')
    # stock spells the server no longer has (spell_names.csv "removed": the conjure spells, server/README.md
    # "Rune supply"), and CLIENT_ONLY_REMOVED. Their client entries stay renamed in SpellInfo: a rune's cooldown icon is
    # found by the rune's spell id, which only the conjure entry of that rune carries (game_cooldown
    # Spells.getSpellByIcon), and keeping the Chaos words keeps their ids where they are (spellfix.lua moves the ids of
    # words the server does not know). The spell list only should leave them out.
    out += ['', '-- stock spells the server removed: old words -> Chaos words (server/data/spells/spell_names.csv, "removed")',
            'ChaosRemovedSpells = {']
    for r in rows:
        if r['words'] and r.get('removed'):
            words = ' '.join(parts[t] for t in r['words'].split())
            out.append('  ["%s"] = "%s", -- %s (%s)' % (r['words'], words, r['new_name'].replace('"', '\\"'), r['removed']))
    for old, name in CLIENT_ONLY_REMOVED:
        out.append('  ["%s"] = "%s", -- %s (client only, no server spell)' % (old, old, name))
    out.append('}')
    out += ['', '-- stock spells the server retired: old words, out of the spell list, off the server ids (gen_spell_data.py '
            'RETIRED_STOCK)', 'ChaosRetiredSpells = {']
    for old, name in RETIRED_STOCK:
        out.append('  ["%s"] = true, -- %s' % (old, name))
    out.append('}')
    # stock spells class lines get on the server (server/tools/add_vocations.py, LINE_STOCK_SPELLS: the utility spells
    # of the Thief, Monk and Templar lines, Ward of the Mind of the Mystic, Necromancer and Ranger lines); chaosspells.lua adds the
    # ids to the client's stock entries, keyed by the Chaos words
    sys.path.insert(0, os.path.join('server', 'tools'))
    from add_vocations import LINE_STOCK_SPELLS
    out += ['', '-- stock spells class lines get on the server: Chaos words -> class ids '
            '(server/tools/add_vocations.py, LINE_STOCK_SPELLS)', 'ChaosStockSpellLines = {']
    for _, stock, lines in LINE_STOCK_SPELLS:
        words = ' '.join(parts[t] for t in stock.split())
        out.append('  ["%s"] = { %s },' % (words, ', '.join(str(VOC[v]) for line in lines for v in line)))
    out.append('}')
    # the 15-spell cap (server/tools/patch_spell_cap.py CAP): Chaos words -> the class ids that keep the stock spell;
    # an empty list: the server retired it. chaosspells.lua cuts the stock entries' class lists to these and hides the
    # retired ones like the removed spells (no id of the server any more)
    from patch_spell_cap import CAP
    out += ['', '-- the 15-spell cap: stock spell (Chaos words) -> the classes that keep it, {} = retired '
            '(server/tools/patch_spell_cap.py CAP)', 'ChaosCappedSpells = {']
    by_words = {}
    for r in rows:
        if r['words'] and not r.get('removed'):
            by_words[r['new_name']] = ' '.join(parts[t] for t in r['words'].split())
    for script, (sid, name, keep) in sorted(CAP.items(), key=lambda kv: kv[1][0]):
        ids = '{ %s }' % ', '.join(str(VOC[v]) for v in keep) if keep else '{}'
        out.append('  ["%s"] = %s, -- %s (%d)' % (by_words[name], ids, name.replace('"', '\\"'), sid))
    out.append('}')
    path = 'client/overlay/modules/game_chaosspells/spelldata.lua'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(sum(1 for l in out if l.startswith('  { id = ')), 'spells written to', path)

if __name__ == '__main__':
    main()

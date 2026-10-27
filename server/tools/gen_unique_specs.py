#!/usr/bin/env python3
"""Turn data/items/chaos_items.xml into data/lib/chaos_unique_specs.lua.

The unique items are NOT installed by rewriting items.xml (stock monsters, shops and scripts look items up by their
stock name, so renaming a stock id breaks their loot). Instead each dropped or given copy of the base item gets its
own name, description and stats as item attributes when it is created (ChaosMakeUnique in chaos_unique_items.lua).
Stats the engine cannot store per item are dropped and listed as "skipped" in the generated file.
The passive of each unique (O278, data/scripts/chaos/unique_passives_*.lua) is written into its description before the
"(Requires level N" part: tools/dump_unique_passives.lua renders the line from the config, so a number changed in
unique_passives_config.lua changes the item text after one run of this tool. The same run keeps the pt-BR Codex texts of
the uniques in the client's pt_br.lua (between the GENERATED UNIQUE DESCRIPTIONS markers) from the pt-BR text of each
description in data/items/unique_flavor_pt.tsv plus the pt-BR passive line.
usage (from server/): python3 -I tools/gen_unique_specs.py"""
import re
import subprocess

PT_PATH = '../client/overlay/modules/client_chaos_locale/pt_br.lua'
PT_BEGIN = '  -- BEGIN GENERATED UNIQUE DESCRIPTIONS (server/tools/gen_unique_specs.py; do not edit by hand)\n'
PT_END = '  -- END GENERATED UNIQUE DESCRIPTIONS\n'
REQ = ' (Requires level '
REQ_PT = ' (Requer nível '


def passive_lines():
    """{item id: (English line, pt-BR line)} from tools/dump_unique_passives.lua"""
    out = subprocess.run(['luajit', 'tools/dump_unique_passives.lua'], check=True, capture_output=True, text=True,
                         encoding='utf-8').stdout
    lines = {}
    for row in out.splitlines():
        iid, en, pt = row.split('\t')
        lines[iid] = (en, pt)
    return lines


def with_passive(desc, line):
    """desc with the passive line before its "(Requires level" part"""
    i = desc.find(REQ)
    if i < 0:
        return desc + ' ' + line
    return desc[:i] + ' ' + line + desc[i:]


def key(text):
    """the Codex key of a text (client codextext.lua C.key): % -> %%, every number -> %s"""
    return re.sub(r'\d+\.?\d*', lambda m: '%s' + ('.' if m.group(0).endswith('.') else ''), text.replace('%', '%%'))


def flavor_pt():
    """{item id: pt-BR format string of the description without the passive}"""
    out = {}
    for row in open('data/items/unique_flavor_pt.tsv', encoding='utf-8').read().splitlines():
        if row and not row.startswith('#'):
            iid, _, text = row.partition('\t')
            out[iid] = text
    return out


def pt_block(descs):
    """the generated lines of pt_br.lua: [(English description, passive English, passive pt-BR, item id)] -> text"""
    pt = flavor_pt()
    esc = lambda s: s.replace('\\', '\\\\').replace('"', '\\"')
    rows = []
    for iid, desc, line_en, line_pt in descs:
        old = pt.get(iid, '')
        new_key = key(with_passive(desc, line_en))
        passive_fmt = key(line_pt)
        if old:
            i = old.find(REQ_PT)
            value = (old + ' ' + passive_fmt) if i < 0 else (old[:i] + ' ' + passive_fmt + old[i:])
        else:
            # no translation of the flavor yet: the English description with the pt-BR passive line
            value = key(with_passive(desc, line_pt))
        rows.append('  ["%s"] = "%s",\n' % (esc(new_key), value if old else esc(value)))
    return PT_BEGIN + ''.join(sorted(set(rows))) + PT_END

ITEM_ATTR = {'attack': 'ITEM_ATTRIBUTE_ATTACK', 'defense': 'ITEM_ATTRIBUTE_DEFENSE', 'extraDef': 'ITEM_ATTRIBUTE_EXTRADEFENSE',
             'armor': 'ITEM_ATTRIBUTE_ARMOR', 'hitChance': 'ITEM_ATTRIBUTE_HITCHANCE', 'range': 'ITEM_ATTRIBUTE_SHOOTRANGE'}
# keys read on equip by the stock rarity scripts (scripts/customs/rarity/base_rarity.lua)
CUSTOM = {'skillFist': 'rarity_fistSkill', 'skillSword': 'rarity_swordSkill', 'skillAxe': 'rarity_axeSkill', 'skillClub': 'rarity_clubSkill',
          'skillDist': 'rarity_distanceSkill', 'skillShield': 'rarity_shieldSkill', 'magicPoints': 'rarity_maglevelSkill',
          'criticalHitChance': 'rarity_criticalHitChance', 'criticalHitAmount': 'rarity_criticalHitAmount',
          'lifeLeechChance': 'rarity_lifeLeechChance', 'lifeLeechAmount': 'rarity_lifeLeechAmount',
          'manaLeechChance': 'rarity_manaLeechChance', 'manaLeechAmount': 'rarity_manaLeechAmount',
          'absorbPercentFire': 'rarity_FireAbsorb', 'absorbPercentPhysical': 'rarity_physicalAbsorb',
          'absorbPercentEnergy': 'rarity_energyAbsorb', 'absorbPercentEarth': 'rarity_earthAbsorb',
          'absorbPercentPoison': 'rarity_earthAbsorb', 'absorbPercentDrown': 'rarity_drownAbsorb',
          'absorbPercentIce': 'rarity_iceAbsorb', 'absorbPercentHoly': 'rarity_holyAbsorb',
          'absorbPercentDeath': 'rarity_deathAbsorb'}
STRUCTURAL = {'weight', 'description', 'showattributes', 'slotType', 'weaponType', 'shootType', 'ammoType', 'set',
              'archetype', 'equipLevel', 'equipLines', 'mods'}
# equipLines names class lines (docs/CLASSES.md); a line is its base class and both ascended classes, as the engine
# names them in vocations.xml (tools/install_unique_equip.py writes the same names into movements.xml)
LINES = {
    'Warrior': ['Warrior', 'Juggernaut', 'Berserker'],
    'Ranger': ['Ranger', 'Deadeye', 'Beastmaster'],
    'Mystic': ['Mystic', 'Elementalist', 'Illusionist'],
    'Thief': ['Thief', 'Ninja', 'Samurai'],
    'Monk': ['Monk', 'Shadowfist', 'Iron Sage'],
    'Necromancer': ['Necromancer', 'Lich', 'Bone Lord'],
    'Templar': ['Templar', 'Inquisitor', 'Sentinel'],
}


def equip_rule(attrs):
    """(level, [line], [vocation name]) of a unique's own equip rule (equipLevel / equipLines), or None"""
    if 'equipLevel' not in attrs and 'equipLines' not in attrs:
        return None
    lines = [x.strip() for x in attrs.get('equipLines', '').split(',') if x.strip()]
    for line in lines:
        if line not in LINES:
            raise SystemExit('unknown class line in equipLines: %r' % line)
    return int(attrs.get('equipLevel', '0')), lines, [v for line in lines for v in LINES[line]]


def mod_keys():
    """the Chaos modifier and legendary power keys (data/lib/chaos_item_mods.lua, data/lib/chaos_powers.lua)"""
    keys = set()
    for path in ('data/lib/chaos_item_mods.lua', 'data/lib/chaos_powers.lua'):
        keys.update(re.findall(r'\{key = "(\w+)"', open(path, encoding='utf-8').read()))
    return keys


def built_in_mods(attrs, keys):
    """[(key, value)] of a unique's built-in Chaos modifiers (attribute mods="lifeonkill:12,attackspeed:6")"""
    out = []
    for part in [x.strip() for x in attrs.get('mods', '').split(',') if x.strip()]:
        m = re.fullmatch(r'(\w+):(\d+)', part)
        if not m or m.group(1) not in keys:
            raise SystemExit('bad unique modifier %r (key:value, a key of chaos_item_mods.lua / chaos_powers.lua)' % part)
        if any(k == m.group(1) for k, _ in out):
            raise SystemExit('unique modifier %r given twice' % m.group(1))
        out.append((m.group(1), int(m.group(2))))
    return out


def items(xml):
    """(id, head, attrs) of every <item> of chaos_items.xml"""
    for m in re.finditer(r'<item id="(\d+)"([^>]*)>(.*?)</item>', xml, re.S):
        yield m.group(1), m.group(2), dict(re.findall(r'<attribute key="(\w+)" value="([^"]*)"', m.group(3)))

def main():
    xml = open('data/items/chaos_items.xml', encoding='utf-8').read()
    keys = mod_keys()
    passives = passive_lines()
    descs = []
    out = ['-- GENERATED by tools/gen_unique_specs.py from data/items/chaos_items.xml. Do not edit by hand.',
           '-- ChaosUniqueSpecs[base server id] = {name, article, description, attributes, custom, skipped, set, archetype, mods, equip}',
           'ChaosUniqueSpecs = {']
    for m in re.finditer(r'<item id="(\d+)"([^>]*)>(.*?)</item>', xml, re.S):
        iid, head, body = m.group(1), m.group(2), m.group(3)
        name = re.search(r'name="([^"]+)"', head).group(1)
        art = re.search(r'article="([^"]*)"', head)
        attrs = dict(re.findall(r'<attribute key="(\w+)" value="([^"]*)"', body))
        desc = attrs.get('description', '')
        if iid in passives:
            descs.append((iid, desc, passives[iid][0], passives[iid][1]))
            desc = with_passive(desc, passives[iid][0])
        a, c, skipped = [], {}, []
        for k, v in attrs.items():
            if k in ITEM_ATTR:
                a.append('[%s] = %s' % (ITEM_ATTR[k], v))
            elif k in CUSTOM:
                c[CUSTOM[k]] = c.get(CUSTOM[k], 0) + int(v)
            elif k not in STRUCTURAL:
                skipped.append(k)
        esc = lambda s: s.replace('\\', '\\\\').replace('"', '\\"')
        out.append('\t[%s] = { name = "%s", article = "%s", description = "%s",' % (iid, esc(name), art.group(1) if art else '', esc(desc)))
        out.append('\t\tattributes = { %s },' % ', '.join(a))
        out.append('\t\tcustom = { %s },' % ', '.join('%s = %d' % kv for kv in sorted(c.items())))
        # set: the item set the piece belongs to (data/lib/chaos_item_sets_config.lua; ChaosMakeUnique writes chaos_set)
        tail = (', set = "%s"' % attrs['set']) if attrs.get('set') else ''
        # archetype: the build archetype effect of the unique (data/scripts/chaos/archetypes.lua reads it on the worn copy)
        tail += (', archetype = "%s"' % attrs['archetype']) if attrs.get('archetype') else ''
        # equip: the unique copy's own equip rule (data/lib/chaos_unique_equip.lua; the movements.xml entry of the base
        # item from tools/install_unique_equip.py sends the check there)
        # mods: built-in Chaos modifiers and legendary powers (ChaosMakeUnique writes them as T8 modifiers; the
        # equipped totals stay capped per modifier, chaos_item_mods.lua)
        mods = built_in_mods(attrs, keys)
        if mods:
            tail += ',\n\t\tmods = { %s }' % ', '.join('{ "%s", %d }' % kv for kv in mods)
        rule = equip_rule(attrs)
        if rule:
            tail += (',\n\t\tequip = { level = %d, lines = { %s },\n\t\t\tvocations = { %s } }'
                     % (rule[0], ', '.join('"%s"' % x for x in rule[1]), ', '.join('"%s"' % x for x in rule[2])))
        out.append('\t\tskipped = { %s }%s },' % (', '.join('"%s"' % s for s in sorted(skipped)), tail))
    out.append('}')
    open('data/lib/chaos_unique_specs.lua', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(len(re.findall(r'<item id=', xml)), 'unique specs written to data/lib/chaos_unique_specs.lua')
    write_pt(descs)


def write_pt(descs):
    """the pt-BR Codex texts of the uniques: the old per-description entries (before the passive line) give way to the block"""
    text = open(PT_PATH, encoding='utf-8').read()
    block = pt_block(descs)
    if PT_BEGIN in text:
        a = text.index(PT_BEGIN)
        b = text.index(PT_END) + len(PT_END)
        text = text[:a] + block + text[b:]
    else:
        # first run: the entries of the descriptions without a passive line leave, the block takes the first one's place
        xml = open('data/items/chaos_items.xml', encoding='utf-8').read()
        esc = lambda t: t.replace('\\', '\\\\').replace('"', '\\"')
        placed = False
        for m in re.finditer(r'<item id="(\d+)"[^>]*>(.*?)</item>', xml, re.S):
            d = re.search(r'key="description" value="([^"]*)"', m.group(2))
            if not d:
                continue
            line = re.search(r'^  \["' + re.escape(esc(key(d.group(1)))) + r'"\] = "(?:[^"\\]|\\.)*",\n', text, re.M)
            if line:
                text = text.replace(line.group(0), '' if placed else block, 1)
                placed = True
        if not placed:
            raise SystemExit('no place for the unique descriptions in pt_br.lua')
    open(PT_PATH, 'w', encoding='utf-8').write(text)
    print(len(descs), 'unique description texts written to', PT_PATH)

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Install the Chaos classes (docs/CLASSES.md) into a base server data folder (idempotent).

usage: python3 -I add_vocations.py DATA_DIR [--dry-run]

1. data/XML/vocations.xml: the entries of server/data/XML/chaos_vocations.xml (the reviewable table: ids, names,
   gains, attack speed, skills) and of the class fragments next to it, chaos_vocations_monk.xml (17-19),
   chaos_vocations_necro.xml (20-22) and chaos_vocations_templar.xml (23-25), go between "BEGIN chaos vocations" /
   "END chaos vocations" markers before </vocations>. A "BEGIN chaos necromancer" block an older tool wrote is dropped.
   An entry of the table replaces the base server's entry with the same id (Knight 4 -> Warrior, ...), the retired ids
   2, 6 and 9 (Druid, Elder Druid, Illusionist) are removed. Re-running rebuilds the block from the table. Stops with
   an error, changing nothing, when a name of the table is used by an entry it does not replace.
2. The vocation lists of data/spells/spells.xml (not the Chaos block, which register_spells.py writes),
   data/weapons/weapons.xml and data/movements/movements.xml are converted once to the new classes (a marker comment
   after the root tag records it):
     Knight -> Warrior, Juggernaut, Berserker        Elite Knight -> Juggernaut, Berserker
     Paladin -> Ranger, Deadeye, Beastmaster         Royal Paladin -> Deadeye, Beastmaster
     Sorcerer -> Mystic, Elementalist                Master Sorcerer -> Elementalist
     Druid -> Mystic, Illusionist                    Elder Druid -> Illusionist
     Illusionist (the old 9) -> Mystic, Illusionist  Arch Illusionist -> Illusionist
   The Berserker fights with two-handed weapons: in weapons.xml and in the hand equip events it is only added to
   two-handed swords, axes and clubs, and never to shields. The Beastmaster fights with a bow: on weapons, hand items
   and ammunition it is only added to bows and arrows. Spells and every other piece of equipment get both.
   An ascended class gets showInDescription="0" when its base class is in the same list (items then read "warriors").
3. MELEE ITEMS SERVE EVERY MELEE CLASS (owner debug item 46, 2026-10-17: "Itens de melee servem a todas as classes de
   melee"; server/README.md "One melee skill"). A weapon entry that lists vocations and is a sword, axe or club of any
   size (items.xml weaponType; one- or two-handed) gets the Thief line (Thief, Ninja, Samurai), the Monk line (Monk,
   Shadowfist, Iron Sage) and the Templar line (Templar, Inquisitor, Sentinel), on top of the Warrior line the Knight's
   list converts to. So do the equip events of the hand slot for those items. The Berserker stays two-handed only (the
   conversion above). The Thief line also gets throwing weapons (weaponType "distance" without ammoType: throwing stars,
   assassin stars, knives, spears). Equip events that list vocations get the Thief line when the slot is not a hand and
   the Ranger may wear it, or the slot is a hand and the item is a melee weapon or a throwing weapon. A list that names
   "Thief" already is left as it is. The Monk line also wears the fist weapons (items.xml weaponType "shield" with an
   attack: no stock shield has one; the fist weapons and their Monk-only equip entries come from install_fist_weapons.py)
   and, for the other slots, what the Ranger may wear (light armour). The Templar line also gets every non-hand equip
   entry (shields too) that the Warrior may wear. (Before: the Thief line one-handed swords, the Monk line two-handed
   clubs, the Templar line one-handed swords and clubs.)
   The Necromancer line (Necromancer, Lich, Bone Lord) wields and wears what the Mystic does: every <wand> and every
   equip event whose list names a caster (Mystic, Elementalist, Illusionist). The stock healing and support instants
   of the Mystic in spells.xml get it too (healing, haste, light, cures, party spells; not rune conjuring, not the
   stock summon, which would bypass the minion caps, not the magic shield, not other classes' custom spells).
   A list that already names the line's base class is left as it is, so every run after the first changes nothing.
   The quiver block of movements.xml (patch_base_archery.py) is left alone: only the launcher classes wear a quiver.
   So is the unique equip block (install_unique_equip.py): its lists come from the uniques' own rules.
   The Thief, Monk and Templar lines get the stock utility spells every other class has (LINE_STOCK_SPELLS: light, great
   light, haste, find person, levitate, magic rope, the poison / splash / bewitched cures); the Thief and Monk lines also
   strong haste, the Monk and Templar lines cure bleeding (as the Warrior), the Templar line cure curse (as the Ranger).
   The magic shield (Ward of the Mind) gets the Mystic, Necromancer and Ranger lines (owner 2026-10-21; the
   Necromancer counts as a mage), through LINE_STOCK_SPELLS only.
4. data/actions/scripts/other/potions.lua: every class drinks the potions of its role (docs/CLASSES.md, POTION_RULES):
   a list that names the Elite Knight (8) also gets the Berserker (14), one that names the Royal Paladin (7) the
   Beastmaster (15), the Thief line (11, 12, 13) and the Monk line (17, 18, 19), one that names either the Templar line
   (23, 24, 25), one that names the Elementalist (5) the Necromancer line (20, 21, 22); lists are sorted, so a re-run
   (also on an install of the former rule) changes nothing. Each refusal text is rebuilt from its list with our class
   names ("Only Warriors and Templars of level 80 or above may drink this fluid."; a line by its base class when all
   three are in the list; "Only characters of level 50 or above ..." when every class is).
   data/spells/spells.xml: every rune gets level="1" (no level requirement, owner 2026-10-17; the magic level stays).
   data/actions/scripts/other/strengthening_potions.lua: the mastermind potion asks Player.isMage (Sorcerer and Druid
   ids only); it gets the stock mastermind list plus the Necromancer line (Mystic, Elementalist, Illusionist,
   Necromancer, Lich, Bone Lord) and the text "Only Mystics and Necromancers may drink this fluid.".
   data/lib/core/player.lua: Player.isKnight also counts the
   Berserker and Player.isPaladin the Beastmaster (base scripts and NPCs ask them). Each file is skipped when missing.

The engine adds a promoted vocation to a weapon's list by itself only for the first vocation that names the base one
as its fromvoc, so every class is written out.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, '..', 'data', 'XML', 'chaos_vocations.xml')
# the class fragments (one file per line, ids in the line's own config), installed in the same block
FRAGMENTS = [os.path.join(HERE, '..', 'data', 'XML', 'chaos_vocations_%s.xml' % k) for k in ('monk', 'necro', 'templar')]
# a block of the former separate tool for the Necromancer: dropped, the entries are in the main block now
OLD_BLOCKS = [('<!-- BEGIN chaos necromancer (server/tools/add_necromancer.py) -->', '<!-- END chaos necromancer -->')]
BEGIN = '<!-- BEGIN chaos vocations (server/tools/add_vocations.py) -->'
END = '<!-- END chaos vocations -->'
CONVERTED = '<!-- chaos classes: vocation lists converted (server/tools/add_vocations.py) -->'
RETIRED = {'2', '6', '9'}
LINE = ['Thief', 'Ninja', 'Samurai']
MONK_LINE = ['Monk', 'Shadowfist', 'Iron Sage']
NECRO_LINE = ['Necromancer', 'Lich', 'Bone Lord']
TEMPLAR_LINE = ['Templar', 'Inquisitor', 'Sentinel']
MYSTIC_LINE = ['Mystic', 'Elementalist', 'Illusionist']
RANGER_LINE = ['Ranger', 'Deadeye', 'Beastmaster']
CASTERS = ('Mystic', 'Elementalist', 'Illusionist', 'Sorcerer', 'Master Sorcerer', 'Druid', 'Elder Druid')
# the Necromancer's stock spells: the Mystic's healing / support instants, never these scripts
NECRO_SPELL_FROM = ('Mystic', 'Sorcerer')
NECRO_SPELL_SKIP = ('conjuring/', 'summon_creature', 'custom/', 'magic_shield')  # magic shield: LINE_STOCK_SPELLS
# the stock utility spells of the Thief, Monk and Templar lines (the Warrior, Ranger, Mystic and Necromancer all have
# the first six; the cure spells were retired, retire_cure_spells.py): (spells.xml script, stock words, lines). client/tools/gen_spell_data.py writes the same table into
# the client's spelldata.lua (ChaosStockSpellLines), so the client's spell list shows them for the three lines.
THIEF_MONK_TEMPLAR = (LINE, MONK_LINE, TEMPLAR_LINE)
LINE_STOCK_SPELLS = [
    ('support/light.lua', 'utevo lux', THIEF_MONK_TEMPLAR),
    ('support/great_light.lua', 'utevo gran lux', THIEF_MONK_TEMPLAR),
    ('support/haste.lua', 'utani hur', THIEF_MONK_TEMPLAR),
    ('support/find_person.lua', 'exiva', THIEF_MONK_TEMPLAR),
    ('support/levitate.lua', 'exani hur', THIEF_MONK_TEMPLAR),
    ('support/magic_rope.lua', 'exani tera', THIEF_MONK_TEMPLAR),
    ('support/strong_haste.lua', 'utani gran hur', (LINE, MONK_LINE)),       # the mobile lines
    # Ward of the Mind, the classic mana shield (owner 2026-10-21: "somente pra mages e rangers"; the Necromancer counts
    # as a mage): the Mystic and Necromancer lines keep it (an install the 15-spell cap already cut gets it back) and
    # the Ranger line gets it; patch_spell_cap.py CAP keeps exactly these nine. The Necromancer conversion skips it
    # (NECRO_SPELL_SKIP), this entry adds the line. server/README.md "Magic Shield".
    ('support/magic_shield.lua', 'utamo vita', (MYSTIC_LINE, NECRO_LINE, RANGER_LINE)),
]

# old name -> new names; 'B' / 'BM' mark the Berserker / Beastmaster, added only where the item allows it
CONVERT = {
    'Knight': ['Warrior', 'Juggernaut', 'B'], 'Elite Knight': ['Juggernaut', 'B'],
    'Paladin': ['Ranger', 'Deadeye', 'BM'], 'Royal Paladin': ['Deadeye', 'BM'],
    'Sorcerer': ['Mystic', 'Elementalist'], 'Master Sorcerer': ['Elementalist'],
    'Druid': ['Mystic', 'Illusionist'], 'Elder Druid': ['Illusionist'],
    'Illusionist': ['Mystic', 'Illusionist'], 'Arch Illusionist': ['Illusionist'],
}
BASE_OF = {'Juggernaut': 'Warrior', 'Berserker': 'Warrior', 'Deadeye': 'Ranger', 'Beastmaster': 'Ranger',
           'Elementalist': 'Mystic', 'Illusionist': 'Mystic', 'Ninja': 'Thief', 'Samurai': 'Thief',
           'Shadowfist': 'Monk', 'Iron Sage': 'Monk', 'Lich': 'Necromancer', 'Bone Lord': 'Necromancer',
           'Inquisitor': 'Templar', 'Sentinel': 'Templar'}
ORDER = ['Warrior', 'Juggernaut', 'Berserker', 'Ranger', 'Deadeye', 'Beastmaster', 'Mystic', 'Elementalist',
         'Illusionist', 'Thief', 'Ninja', 'Samurai', 'Monk', 'Shadowfist', 'Iron Sage', 'Necromancer', 'Lich',
         'Bone Lord', 'Templar', 'Inquisitor', 'Sentinel']
# the quiver block of movements.xml belongs to patch_base_archery.py (its MOVE_BEGIN / MOVE_END): its lists are the
# classes that may fire a launcher, rebuilt on every archery run, so the class lines are never added there (else the
# two tools rewrite the block back and forth on every install)
QUIVER_BLOCK = re.compile(re.escape('<!-- Chaos quivers (server/tools/patch_base_archery.py, do not edit by hand) -->')
                          + r'.*?' + re.escape('<!-- end of the Chaos quivers -->'), re.S)
# the same for the unique equip block (install_unique_equip.py rebuilds its lists from the uniques' rules and the stock
# entries it recorded)
UNIQUE_EQUIP_BLOCK = re.compile(re.escape('<!-- Chaos unique equip rules (server/tools/install_unique_equip.py')
                                + r'.*?' + re.escape('<!-- end of the Chaos unique equip rules -->'), re.S)


def read(path):
    return open(path, encoding='utf-8', errors='surrogateescape', newline='').read()


def write(path, text):
    open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(text)


def table_entries():
    """the <vocation> elements of the table and the fragments, as text, and their (id, name) pairs"""
    entries = []
    for path in [TABLE] + [f for f in FRAGMENTS if os.path.exists(f)]:
        t = re.sub(r'<!--.*?-->', '', read(path), flags=re.S)
        entries += re.findall(r'[ \t]*<vocation\s.*?</vocation>', t, re.S)
    ids = [(re.search(r'\bid="(\d+)"', e).group(1), re.search(r'\bname="([^"]+)"', e).group(1)) for e in entries]
    return entries, ids


def patch_vocations(text, entries, ids):
    """returns (new text, status)"""
    outside = text
    for begin, end in [(BEGIN, END)] + OLD_BLOCKS:
        outside = re.sub(r'[ \t]*' + re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', '', outside, flags=re.S)
    replace = {vid for vid, _ in ids} | RETIRED

    def drop(m):
        vid = re.search(r'\bid="(\d+)"', m.group(0)).group(1)
        return '' if vid in replace else m.group(0)
    outside = re.sub(r'[ \t]*<vocation\s[^>]*?(?:/>|>.*?</vocation>)[ \t]*\n?', drop, outside, flags=re.S)
    for vid, name in ids:
        for m in re.finditer(r'<vocation\s[^>]*>', outside):
            tag = m.group(0)
            if re.search(r'\bname="%s"' % re.escape(name), tag, re.I):
                return text, 'vocation name %s is already used by an entry the table does not replace: %s' % (name, tag[:80])
    if '</vocations>' not in outside:
        return text, '</vocations> not found'
    block = '\t' + BEGIN + '\n' + '\n'.join(e.rstrip() for e in entries) + '\n\t' + END + '\n'
    new = outside.replace('</vocations>', block + '</vocations>', 1)
    return new, ('already' if new == text else 'patched')


def item_info(items_xml):
    """item id -> set of flags: sword1h, throwing (the Thief line), melee2h (Berserker), bow, arrow (Beastmaster)"""
    info = {}
    for m in re.finditer(r'<item\s([^>]*?)(?:/>|>(.*?)</item>)', items_xml, re.S):
        head, body = m.group(1), m.group(2) or ''
        wt = re.search(r'key="weaponType"\s+value="([^"]+)"', body, re.I)
        if not wt:
            continue
        wt = wt.group(1).lower()
        two = re.search(r'key="slotType"\s+value="two-handed"', body, re.I) is not None
        ammo = re.search(r'key="ammoType"\s+value="([^"]+)"', body, re.I)
        ammo = ammo.group(1).lower() if ammo else None
        flags = set()
        if wt in ('sword', 'axe', 'club'):
            flags.add('melee')           # any sword, axe or club: every melee class may wield it
        if wt == 'sword' and not two:
            flags.add('sword1h')
        if wt == 'club' and not two:
            flags.add('club1h')
        if wt == 'club' and two:
            flags.add('staff')
        if wt in ('sword', 'axe', 'club') and two:
            flags.add('melee2h')
        # a bow or crossbow fires without ammunition once tools/patch_base_archery.py ran (no ammoType, a missile of
        # its own): it is two-handed, a throwing weapon is not
        if not ammo and wt == 'distance' and two:
            shoot = re.search(r'key="shootType"\s+value="([^"]+)"', body, re.I)
            ammo = 'bolt' if shoot and 'bolt' in shoot.group(1).lower() else 'arrow'
        if wt == 'distance' and not ammo:
            flags.add('throwing')
        if wt == 'shield' and re.search(r'key="attack"\s+value="[1-9]', body, re.I):
            flags.add('fist')            # a shield with an attack: the Monk line's fist weapons (install_fist_weapons.py)
        if wt == 'distance' and ammo == 'arrow':
            flags.add('bow')
        if wt == 'ammunition' and ammo == 'arrow':
            flags.add('arrow')
        if not flags:
            continue
        ids = []
        one = re.search(r'\bid="(\d+)"', head)
        if one:
            ids = [int(one.group(1))]
        else:
            fr, to = re.search(r'\bfromid="(\d+)"', head), re.search(r'\btoid="(\d+)"', head)
            if fr and to:
                ids = list(range(int(fr.group(1)), int(to.group(1)) + 1))
        for i in ids:
            info.setdefault(i, set()).update(flags)
    return info


def ids_of(tag):
    """item ids an XML tag covers: id / itemid, or fromid..toid"""
    one = re.search(r'\b(?:id|itemid)="(\d+)"', tag)
    if one:
        return [int(one.group(1))]
    fr, to = re.search(r'\bfromid="(\d+)"', tag), re.search(r'\btoid="(\d+)"', tag)
    if fr and to:
        return list(range(int(fr.group(1)), int(to.group(1)) + 1))
    return []


def flags_of(tag, info):
    out = set()
    for i in ids_of(tag):
        out |= info.get(i, set())
    return out


# ------------------------------------------------------------------------------------------------ list conversion
VOC_LINE = re.compile(r'\n([ \t]*)<vocation\s+name="([^"]+)"([^>]*?)\s*/>')


def convert_list(element, allow_b, allow_bm):
    """rewrite the <vocation> lines of one element (text) to the new classes"""
    lines = list(VOC_LINE.finditer(element))
    if not lines:
        return element
    indent = lines[0].group(1)
    names, hidden = [], {}
    for m in lines:
        old, attrs = m.group(2), m.group(3)
        for new in CONVERT.get(old, [old]):
            if new == 'B':
                if not allow_b:
                    continue
                new = 'Berserker'
            elif new == 'BM':
                if not allow_bm:
                    continue
                new = 'Beastmaster'
            if new not in names:
                names.append(new)
                hidden[new] = 'showInDescription="0"' in attrs
    names.sort(key=lambda n: ORDER.index(n) if n in ORDER else 100)
    out = ''
    for n in names:
        hide = hidden[n] or (BASE_OF.get(n) in names)
        out += '\n%s<vocation name="%s"%s />' % (indent, n, ' showInDescription="0"' if hide else '')
    start, end = lines[0].start(), lines[-1].end()
    middle = element[start:end]
    # keep anything between the vocation lines that is not a vocation line (comments)
    rest = VOC_LINE.sub('', middle)
    return element[:start] + out + rest + element[end:]


def convert_file(text, kind, info):
    """kind: spells | weapons | movements. Returns (new text, count)."""
    if CONVERTED in text:
        return text, 0
    count = [0]
    skip = None
    if kind == 'spells':
        m = re.search(r'<!-- BEGIN chaos spells -->.*?<!-- END chaos spells -->', text, re.S)
        skip = m.span() if m else None

    def repl(m):
        if skip and skip[0] <= m.start() < skip[1]:
            return m.group(0)
        el, tag, head = m.group(0), m.group(1), m.group(2)
        if '<vocation' not in el:
            return el
        allow_b = allow_bm = True
        if kind in ('weapons', 'movements'):
            fl = flags_of(head, info)
            slot = re.search(r'\bslot="([^"]+)"', head)
            slot = slot.group(1).lower() if slot else ''
            if kind == 'weapons' or slot == 'hand':
                allow_b = 'melee2h' in fl
                allow_bm = 'bow' in fl or 'arrow' in fl
            elif slot == 'shield':
                allow_b = False
            elif slot == 'ammo':
                allow_bm = 'arrow' in fl
        new = convert_list(el, allow_b, allow_bm)
        if new != el:
            count[0] += 1
        return new
    new = re.sub(r'<(instant|rune|conjure|melee|distance|wand|movevent)\b([^>]*[^/])>.*?</\1>', repl, text, flags=re.S)
    root = {'spells': '<spells>', 'weapons': '<weapons>', 'movements': '<movements>'}[kind]
    if root in new:
        new = new.replace(root, root + '\n\t' + CONVERTED, 1)
    return new, count[0]


# ------------------------------------------------------------------------------------------------ the class lines
def add_lines(element, line=None):
    """append a class line (default the Thief line) to the <vocation> list of one XML element (text), keeping its
    indentation; the base class is shown in descriptions, the ascended classes are not. A list that names the base
    class already is left as it is; a list that names some of its ascended classes but not the base class (the 15-spell
    cap left the Elementalist alone) gets the missing ones only."""
    line = line or LINE
    if re.search(r'<vocation\s+name="%s"' % re.escape(line[0]), element):
        return element
    last = list(re.finditer(r'\n([ \t]*)<vocation\s[^>]*/>', element))
    if not last:
        return element
    indent = last[-1].group(1)
    at = last[-1].end()
    have = set(names_in(element))
    lines = ''.join('\n%s<vocation name="%s"%s />' % (indent, v, '' if v == line[0] else ' showInDescription="0"')
                    for v in line if v not in have)
    return element[:at] + lines + element[at:]


def names_in(element):
    return re.findall(r'<vocation\s+name="([^"]+)"', element)


def thief_ok(fl):
    return 'melee' in fl or 'throwing' in fl


def monk_ok(fl):
    return 'melee' in fl or 'fist' in fl


def templar_ok(fl):
    return 'melee' in fl


def caster_list(element):
    return any(n in CASTERS for n in names_in(element))


def patch_weapons(text, info):
    """returns (new text, {line base name: entries changed})"""
    count = {'Thief': 0, 'Monk': 0, 'Templar': 0, 'Necromancer': 0}

    def add(el, line, ok):
        if not ok:
            return el
        new = add_lines(el, line)
        if new != el:
            count[line[0]] += 1
        return new

    def repl(m):
        el = m.group(0)
        if '<vocation' not in el:
            return el
        fl = flags_of(m.group(2), info)
        el = add(el, LINE, thief_ok(fl))
        el = add(el, MONK_LINE, monk_ok(fl))
        el = add(el, TEMPLAR_LINE, m.group(1) == 'melee' and templar_ok(fl))
        return el

    def wand(m):
        el = m.group(0)
        if '<vocation' not in el:
            return el
        return add(el, NECRO_LINE, caster_list(el))
    new = re.sub(r'<(melee|distance)\s([^>]*[^/])>.*?</\1>', repl, text, flags=re.S)
    new = re.sub(r'<wand\b([^>]*[^/])>.*?</wand>', wand, new, flags=re.S)
    return new, count


def patch_movements(text, info):
    """returns (new text, {line base name: equip entries changed})"""
    count = {'Thief': 0, 'Monk': 0, 'Templar': 0, 'Necromancer': 0}

    def add(el, line, ok):
        if not ok:
            return el
        new = add_lines(el, line)
        if new != el:
            count[line[0]] += 1
        return new

    skip = [b.span() for b in QUIVER_BLOCK.finditer(text)] + [b.span() for b in UNIQUE_EQUIP_BLOCK.finditer(text)]

    def repl(m):
        el, tag = m.group(0), m.group(1)
        if '<vocation' not in el or any(a <= m.start() < b for a, b in skip):
            return el
        slot = re.search(r'\bslot="([^"]+)"', tag)
        slot = slot.group(1).lower() if slot else ''
        light = re.search(r'<vocation\s+name="(?:Paladin|Ranger)"', el) is not None
        heavy = re.search(r'<vocation\s+name="(?:Knight|Warrior)"', el) is not None
        caster = caster_list(el)
        fl = flags_of(tag, info)
        if slot == 'hand' or 'fist' in fl:          # fist weapons are equipped in the shield slot
            thief, monk, templar = thief_ok(fl), monk_ok(fl), templar_ok(fl)
        else:
            thief = monk = light
            templar = heavy
        el = add(el, LINE, thief)
        el = add(el, MONK_LINE, monk)
        el = add(el, TEMPLAR_LINE, templar)
        el = add(el, NECRO_LINE, caster)
        return el
    new = re.sub(r'<movevent\s+event="Equip"([^>]*[^/])>.*?</movevent>', repl, text, flags=re.S)
    return new, count


def patch_spells_necro(text):
    """the Mystic's stock healing and support instants get the Necromancer line (not the Chaos block)"""
    m = re.search(r'<!-- BEGIN chaos spells.*?<!-- END chaos spells -->', text, re.S)
    skip = m.span() if m else None
    count = [0]

    def repl(m):
        if skip and skip[0] <= m.start() < skip[1]:
            return m.group(0)
        el, head = m.group(0), m.group(1)
        group = re.search(r'\bgroup="([^"]+)"', head)
        group = group.group(1).lower() if group else ''
        script = re.search(r'\bscript="([^"]+)"', head)
        script = script.group(1).lower() if script else ''
        if any(s in script for s in NECRO_SPELL_SKIP) or group not in ('healing', 'support'):
            return el
        if not any(n in NECRO_SPELL_FROM for n in names_in(el)):
            return el
        new = add_lines(el, NECRO_LINE)
        if new != el:
            count[0] += 1
        return new
    return re.sub(r'<instant\b([^>]*[^/])>.*?</instant>', repl, text, flags=re.S), count[0]


def patch_spells_lines(text):
    """the stock utility spells of LINE_STOCK_SPELLS get their class lines (not the Chaos block); returns (text, count)"""
    m = re.search(r'<!-- BEGIN chaos spells.*?<!-- END chaos spells -->', text, re.S)
    skip = m.span() if m else None
    lines_of = {script: lines for script, _, lines in LINE_STOCK_SPELLS}
    count = [0]

    def repl(m):
        if skip and skip[0] <= m.start() < skip[1]:
            return m.group(0)
        el = m.group(0)
        script = re.search(r'\bscript="([^"]+)"', m.group(1))
        lines = lines_of.get(script.group(1).lower().replace('\\', '/') if script else '')
        if not lines or '<vocation' not in el:
            return el
        new = el
        for line in lines:
            new = add_lines(new, line)
        if new != el:
            count[0] += 1
        return new
    return re.sub(r'<instant\b([^>]*[^/])>.*?</instant>', repl, text, flags=re.S), count[0]


# ------------------------------------------------------------------------------------------------ base scripts
# potions.lua: the stock vocation whose potions a class drinks (docs/CLASSES.md): a list that names the stock id gets the
# class ids. Melee lines drink the knight's, hybrids the paladin's, casters the mage's.
POTION_RULES = [
    (('8',), ('14',)),                 # Berserker: the Elite Knight's
    (('7',), ('15',)),                 # Beastmaster: the Royal Paladin's
    (('7',), ('11', '12', '13')),      # Thief line: the Royal Paladin's (it wears what the Paladin wears)
    (('7',), ('17', '18', '19')),      # Monk line: the Royal Paladin's
    (('7', '8'), ('23', '24', '25')),  # Templar line: the Elite Knight's and the Royal Paladin's
    (('5',), ('20', '21', '22')),      # Necromancer line: the Elementalist's (the casters' mana potions)
]
PLURAL = {'Thief': 'Thieves', 'Samurai': 'Samurai', 'Lich': 'Liches'}
POTION_ENTRY = re.compile(r'(\n[ \t]*\[\d+\]\s*=\s*\{)')
POTION_LIST = re.compile(r'vocations\s*=\s*\{([\d,\s]*)\}')
POTION_TEXT = re.compile(r'(description\s*=\s*")Only .*?( of level \d+ or above)? may drink this (fluid|potion)\.(")')


def potion_names(ids, names):
    """the classes of a potion's vocation list in words: a whole line by its base class ("Warriors"), else each class"""
    have = {names[i] for i in ids if i in names}
    lines = [n for n in ORDER if n not in BASE_OF]
    out = []
    for base in lines:
        members = [base] + [n for n in ORDER if BASE_OF.get(n) == base]
        present = [n for n in members if n in have]
        if len(present) == len(members):
            out.append(base)
        else:
            out += present
    words = [PLURAL.get(n, n + 's') for n in out]
    if out == lines:
        return None  # every class
    if len(words) > 1:
        return ', '.join(words[:-1]) + ' and ' + words[-1]
    return words[0] if words else 'nobody'


def patch_potions(text, names=None):
    """per potion entry: the vocation list gets the class ids of POTION_RULES (sorted, so a re-run changes nothing), and
    the refusal text names the classes of the list ("Only Warriors, Rangers and Templars of level 50 or above ...")"""
    if names is None:
        names = dict(table_entries()[1])
    count = [0]

    def patch_list(m):
        ids = [x.strip() for x in m.group(1).split(',') if x.strip()]
        new = set(ids)
        for keys, add in POTION_RULES:
            if any(k in ids for k in keys):
                new.update(add)
        new = sorted(new, key=int)
        return 'vocations = {' + ', '.join(new) + '}'

    parts = POTION_ENTRY.split(text)
    for i in range(2, len(parts), 2):
        chunk = POTION_LIST.sub(patch_list, parts[i], count=1)
        m = POTION_LIST.search(chunk)
        if m:
            ids = [x.strip() for x in m.group(1).split(',') if x.strip()]
            who = potion_names(ids, names)

            def text_repl(t):
                level = t.group(2) or ''
                if who is None:
                    return '%s%s may drink this %s.%s' % (
                        t.group(1), ('Only characters' + level) if level else 'Anyone', t.group(3), t.group(4))
                return '%sOnly %s%s may drink this %s.%s' % (t.group(1), who, level, t.group(3), t.group(4))
            chunk = POTION_TEXT.sub(text_repl, chunk, count=1)
        if chunk != parts[i]:
            count[0] += 1
            parts[i] = chunk
    return ''.join(parts), count[0]


# spells.xml: the runes have no level requirement (owner 2026-10-17: "remover o level requirement das runas"); the
# magic level of a rune stays. level="1" is what the engine reads as "none".
RUNE_ELEMENT = re.compile(r'<rune\b[^>]*>')
RUNE_LEVEL = re.compile(r'(\blevel=")(\d+)(")')


def patch_rune_levels(spells_text):
    """every <rune ...> of spells.xml gets level="1"; returns (new text, number of runes changed); a re-run changes nothing"""
    count = [0]

    def one(m):
        tag = m.group(0)

        def level(l):
            if l.group(2) == '1':
                return l.group(0)
            count[0] += 1
            return l.group(1) + '1' + l.group(3)
        return RUNE_LEVEL.sub(level, tag, count=1)
    return RUNE_ELEMENT.sub(one, spells_text), count[0]


# items.xml: the Look text of a potion ("This potion can only be consumed by knights of level 80 or higher.") names the stock
# classes. It gets the classes of the potion's refusal text in potions.lua (patch_potions), so both say the same.
ITEM_POTION_TEXT = re.compile(r'(value=")This potion can only be consumed by [^"]*?( of level \d+ or higher)?\.(")')
POTION_REFUSAL = re.compile(r'description\s*=\s*"(?:Only (.*?)|Anyone)( of level (\d+) or above)? may drink this (?:fluid|potion)\.')


def patch_item_potion_texts(items_text, potions_text):
    """the Look text of every potion of potions.lua that items.xml describes as "can only be consumed by": the classes of
    its refusal text. Returns (new items.xml text, number of items changed); a re-run changes nothing"""
    new_text = {}
    parts = POTION_ENTRY.split(potions_text)
    for i in range(1, len(parts) - 1, 2):
        item_id = re.search(r'\[(\d+)\]', parts[i]).group(1)
        m = POTION_REFUSAL.search(parts[i + 1])
        if not m or not m.group(1):
            continue
        level = int(m.group(3)) if m.group(3) else 0
        new_text[item_id] = 'This potion can only be consumed by %s%s.' % (
            m.group(1), (' of level %d or higher' % level) if level else '')
    count = [0]

    def item_block(m):
        item_id = re.search(r'id="(\d+)"', m.group(0))
        if not item_id or item_id.group(1) not in new_text:
            return m.group(0)
        sentence = new_text[item_id.group(1)]
        block = re.sub(r'(value=")This potion can only be consumed by [^"]*(")',
                       lambda t: t.group(1) + sentence + t.group(2), m.group(0), count=1)
        if block != m.group(0):
            count[0] += 1
        return block
    # an item with a body: not a self-closing <item ... /> (that one would swallow the next item)
    out = re.sub(r'<item\s[^>]*\bid="\d+"[^>]*[^/>]>(?:(?!<item\s).)*?</item>', item_block, items_text, flags=re.S)
    return out, count[0]


# strengthening_potions.lua: the mastermind potion (7440) asks Player.isMage, which knows the Sorcerer and the Druid
# ids only (1, 2, 5, 6): the Illusionist (10) and the Necromancer line were refused. The stock mastermind list of
# potions.lua with the Necromancer line instead, and our class names in the text.
MASTERMIND_IDS = ['1', '2', '5', '6', '9', '10', '20', '21', '22']


def patch_strengthening(text, names=None):
    """the mastermind check: player:isMage() -> the mage ids and the Necromancer line; the refusal text"""
    if names is None:
        names = dict(table_entries()[1])
    count = 0
    check = 'table.contains({%s}, player:getVocation():getId())' % ', '.join(MASTERMIND_IDS)
    if 'not player:isMage()' in text:
        text = text.replace('not player:isMage()', 'not ' + check, 1)
        count += 1
    words = 'Only %s may drink this fluid.' % potion_names(MASTERMIND_IDS, names)
    new, n = re.subn(r"'Only [^'\n]* may drink this fluid\.'", "'%s'" % words, text, count=1)
    if n and new != text:
        text = new
        count += 1
    return text, count


def patch_player_lib(text):
    count = 0
    for old, add in (('VOCATION.ID.ELITE_KNIGHT}', 'VOCATION.ID.ELITE_KNIGHT, 14}'),
                     ('VOCATION.ID.ROYAL_PALADIN}', 'VOCATION.ID.ROYAL_PALADIN, 15}')):
        if old in text:
            text = text.replace(old, add)
            count += 1
    return text, count


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    data = args[0]
    paths = {k: os.path.join(data, *p) for k, p in {
        'voc': ('XML', 'vocations.xml'), 'items': ('items', 'items.xml'), 'spells': ('spells', 'spells.xml'),
        'weapons': ('weapons', 'weapons.xml'), 'moves': ('movements', 'movements.xml')}.items()}
    for k, p in paths.items():
        if not os.path.exists(p):
            print('missing', p)
            sys.exit(1)
    entries, ids = table_entries()
    voc, status = patch_vocations(read(paths['voc']), entries, ids)
    if status not in ('patched', 'already'):
        print('vocations.xml:', status, '- nothing changed')
        sys.exit(1)
    info = item_info(read(paths['items']))
    changes = {}
    spells, ns = convert_file(read(paths['spells']), 'spells', info)
    weapons, nwc = convert_file(read(paths['weapons']), 'weapons', info)
    moves, nmc = convert_file(read(paths['moves']), 'movements', info)
    weapons, cw = patch_weapons(weapons, info)
    moves, cm = patch_movements(moves, info)
    spells, nsn = patch_spells_necro(spells)
    spells, nsl = patch_spells_lines(spells)
    spells, nrl = patch_rune_levels(spells)
    nw, nm = sum(cw.values()), sum(cm.values())
    ns += nsn + nsl

    def per_line(c):
        return ', '.join('%d the %s line' % (n, k) for k, n in c.items())
    print('vocations.xml: %s (%s; retired %s)' % (status, ', '.join('%s %s' % i for i in ids), ', '.join(sorted(RETIRED))))
    print('spells.xml: %d vocation lists converted, %d stock healing / support spells get the Necromancer line'
          % (ns - nsn - nsl, nsn))
    print('spells.xml: %d stock utility spells get the Thief / Monk / Templar lines' % nsl)
    print('spells.xml: %d runes lose their level requirement' % nrl)
    print('weapons.xml: %d vocation lists converted; weapon entries: %s' % (nwc, per_line(cw)))
    print('movements.xml: %d vocation lists converted; equip entries: %s' % (nmc, per_line(cm)))
    if status == 'patched':
        changes[paths['voc']] = voc
    if ns or nrl or CONVERTED in spells and CONVERTED not in read(paths['spells']):
        changes[paths['spells']] = spells
    if nwc or nw or (CONVERTED in weapons and CONVERTED not in read(paths['weapons'])):
        changes[paths['weapons']] = weapons
    if nmc or nm or (CONVERTED in moves and CONVERTED not in read(paths['moves'])):
        changes[paths['moves']] = moves
    for what, rel, fn in (('the Berserker / Beastmaster / the new class lines', ('actions', 'scripts', 'other', 'potions.lua'),
                           patch_potions),
                          ('the Illusionist and the Necromancer line (mastermind)',
                           ('actions', 'scripts', 'other', 'strengthening_potions.lua'), patch_strengthening),
                          ('the Berserker / Beastmaster', ('lib', 'core', 'player.lua'), patch_player_lib)):
        p = os.path.join(data, *rel)
        if os.path.exists(p):
            new, n = fn(read(p))
            print('%s: %d lists get %s' % ('/'.join(rel), n, what))
            if n:
                changes[p] = new
        else:
            print('%s: not found, skipped' % '/'.join(rel))
    # the Look text of the potions in items.xml names the same classes as the refusal text of potions.lua
    pot = os.path.join(data, 'actions', 'scripts', 'other', 'potions.lua')
    if os.path.exists(pot):
        items_now = changes.get(paths['items'], read(paths['items']))
        items_new, nit = patch_item_potion_texts(items_now, changes.get(pot, read(pot)))
        print('items.xml: %d potion descriptions name the new classes' % nit)
        if nit:
            changes[paths['items']] = items_new
    if dry:
        print('dry run: nothing written')
        return
    for p, text in changes.items():
        write(p, text)


if __name__ == '__main__':
    main()

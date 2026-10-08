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
3. The Thief line may wield what it is built for. Weapon entries that list vocations get Thief, Ninja and Samurai when
   the item is a one-handed sword (daggers and light swords; items.xml weaponType "sword", not two-handed) or a throwing
   weapon (weaponType "distance" without ammoType: throwing stars, assassin stars, knives, spears). Equip events that
   list vocations get the three when the slot is not a hand and the Ranger may wear it, or the slot is a hand and the
   item is a one-handed sword or a throwing weapon. A list that names "Thief" already is left as it is.
   The Monk line (Monk, Shadowfist, Iron Sage) fights unarmed or with a staff: weapon entries of two-handed clubs get
   the three; equip events get them when the slot is not a hand and the Ranger may wear it (light armour), or the slot
   is a hand and the item is a two-handed club.
   The Templar line (Templar, Inquisitor, Sentinel) gets one-handed swords and clubs, and every non-hand equip entry
   (shields too) that the Warrior may wear.
   The Necromancer line (Necromancer, Lich, Bone Lord) wields and wears what the Mystic does: every <wand> and every
   equip event whose list names a caster (Mystic, Elementalist, Illusionist). The stock healing and support instants
   of the Mystic in spells.xml get it too (healing, haste, magic shield, light, cures, party spells; not rune
   conjuring, not the stock summon, which would bypass the minion caps, not other classes' custom spells).
   A list that already names the line's base class is left as it is, so every run after the first changes nothing.
4. data/actions/scripts/other/potions.lua: a potion that the Elite Knight (8) may drink also lists the Berserker (14),
   one the Royal Paladin (7) may drink the Beastmaster (15) and the Monk line (17, 18, 19), one the Elite Knight or
   the Royal Paladin may drink the Templar line (23, 24, 25), one the Elementalist (5) may drink the Necromancer line
   (20, 21, 22). data/lib/core/player.lua: Player.isKnight also counts the
   Berserker and Player.isPaladin the Beastmaster (base scripts and NPCs ask them). Both are skipped when missing.

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
CASTERS = ('Mystic', 'Elementalist', 'Illusionist', 'Sorcerer', 'Master Sorcerer', 'Druid', 'Elder Druid')
# the Necromancer's stock spells: the Mystic's healing / support instants, never these scripts
NECRO_SPELL_FROM = ('Mystic', 'Sorcerer')
NECRO_SPELL_SKIP = ('conjuring/', 'summon_creature', 'custom/')

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
        if wt == 'sword' and not two:
            flags.add('sword1h')
        if wt == 'club' and not two:
            flags.add('club1h')
        if wt == 'club' and two:
            flags.add('staff')
        if wt in ('sword', 'axe', 'club') and two:
            flags.add('melee2h')
        if wt == 'distance' and not ammo:
            flags.add('throwing')
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
    class already is left as it is."""
    line = line or LINE
    if re.search(r'<vocation\s+name="%s"' % re.escape(line[0]), element):
        return element
    last = list(re.finditer(r'\n([ \t]*)<vocation\s[^>]*/>', element))
    if not last:
        return element
    indent = last[-1].group(1)
    at = last[-1].end()
    lines = ''.join('\n%s<vocation name="%s"%s />' % (indent, v, '' if v == line[0] else ' showInDescription="0"')
                    for v in line)
    return element[:at] + lines + element[at:]


def names_in(element):
    return re.findall(r'<vocation\s+name="([^"]+)"', element)


def thief_ok(fl):
    return 'sword1h' in fl or 'throwing' in fl


def monk_ok(fl):
    return 'staff' in fl


def templar_ok(fl):
    return 'sword1h' in fl or 'club1h' in fl


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

    def repl(m):
        el, tag = m.group(0), m.group(1)
        if '<vocation' not in el:
            return el
        slot = re.search(r'\bslot="([^"]+)"', tag)
        slot = slot.group(1).lower() if slot else ''
        light = re.search(r'<vocation\s+name="(?:Paladin|Ranger)"', el) is not None
        heavy = re.search(r'<vocation\s+name="(?:Knight|Warrior)"', el) is not None
        caster = caster_list(el)
        if slot == 'hand':
            fl = flags_of(tag, info)
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


# ------------------------------------------------------------------------------------------------ base scripts
def patch_potions(text):
    """vocations = {...} lists: + 14 where 8 is, + 15 and the Monk line where 7 is, the Templar line where 7 or 8 is,
    the Necromancer line where 5 is"""
    count = [0]

    def repl(m):
        ids = [x.strip() for x in m.group(1).split(',') if x.strip()]
        new = list(ids)
        if '8' in ids and '14' not in ids:
            new.append('14')
        if '7' in ids and '15' not in ids:
            new.append('15')
        if '7' in ids and '17' not in ids:
            new += ['17', '18', '19']
        if ('8' in ids or '7' in ids) and '23' not in ids:
            new += ['23', '24', '25']
        if '5' in ids and '20' not in ids:
            new += ['20', '21', '22']
        if new == ids:
            return m.group(0)
        count[0] += 1
        return 'vocations = {' + ', '.join(new) + '}'
    return re.sub(r'vocations\s*=\s*\{([\d,\s]*)\}', repl, text), count[0]


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
    nw, nm = sum(cw.values()), sum(cm.values())
    ns += nsn

    def per_line(c):
        return ', '.join('%d the %s line' % (n, k) for k, n in c.items())
    print('vocations.xml: %s (%s; retired %s)' % (status, ', '.join('%s %s' % i for i in ids), ', '.join(sorted(RETIRED))))
    print('spells.xml: %d vocation lists converted, %d stock healing / support spells get the Necromancer line'
          % (ns - nsn, nsn))
    print('weapons.xml: %d vocation lists converted; weapon entries: %s' % (nwc, per_line(cw)))
    print('movements.xml: %d vocation lists converted; equip entries: %s' % (nmc, per_line(cm)))
    if status == 'patched':
        changes[paths['voc']] = voc
    if ns or CONVERTED in spells and CONVERTED not in read(paths['spells']):
        changes[paths['spells']] = spells
    if nwc or nw or (CONVERTED in weapons and CONVERTED not in read(paths['weapons'])):
        changes[paths['weapons']] = weapons
    if nmc or nm or (CONVERTED in moves and CONVERTED not in read(paths['moves'])):
        changes[paths['moves']] = moves
    for what, rel, fn in (('the Berserker / Beastmaster / the new class lines', ('actions', 'scripts', 'other', 'potions.lua'),
                           patch_potions),
                          ('the Berserker / Beastmaster', ('lib', 'core', 'player.lua'), patch_player_lib)):
        p = os.path.join(data, *rel)
        if os.path.exists(p):
            new, n = fn(read(p))
            print('%s: %d lists get %s' % ('/'.join(rel), n, what))
            if n:
                changes[p] = new
        else:
            print('%s: not found, skipped' % '/'.join(rel))
    if dry:
        print('dry run: nothing written')
        return
    for p, text in changes.items():
        write(p, text)


if __name__ == '__main__':
    main()

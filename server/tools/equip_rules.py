"""Who may wear or wield what, read from the installed XML (O490; server/README.md "Equip rules in the tooltip (O490)").

Shared by install_equip_rules.py (writes data/lib/chaos_equip_rules.lua for the item tooltip) and audit_equip_tooltips.py
(compares the tooltip with the rule). Pure functions over text; nothing here writes a file.

The rule of an item (what the server holds a character to)
  Equip entry   movements.xml `<movevent event="Equip" itemid=.. | fromid=.. toid=..>`: level, maglevel, every `<vocation>` (shown
                or hidden: showInDescription="0" only hides the name from the look text). An unmet rule REFUSES the item
                ("You cannot dress this object there.", engine MoveEvent::EquipItem through Player::queryAdd). An entry with
                script="chaos_unique_equip.lua" (install_unique_equip.py) is held to the STOCK rule recorded in the comment
                `<!-- stock ID: ... -->` for a plain copy, as ChaosUniqueEquip.onEquip does.
  Weapon entry  weapons.xml wand / melee / distance: level, maglv, every `<vocation>`. An unmet rule does NOT refuse the item
                (it can be equipped): the weapon check (Weapon::playerWeaponCheck of the base engine, not in this repository)
                gives no hit for a class that is not listed and for a level or magic level below the entry, or half the hit
                when the entry says unproperly="1" (level and magic level only).
  Effective     what a character needs to wear it and use it properly: the higher level, the higher magic level, the classes
                of both rules.
The engine's look text: the vocation string of the item type holds only the SHOWN vocations, lower case, plural, joined with
commas and "and"; the level and magic level of the item type are the ones of the entry the engine read last (the Equip
entry or the weapon entry; which one is last is not in this repository: Rules.item_type takes it as a parameter).
"""
import os
import re
import xml.etree.ElementTree as ET

# the class lines: base class, then its two ascended classes (docs/CLASSES.md; server/tools/add_vocations.py)
LINES = [('Warrior', 'Juggernaut', 'Berserker'), ('Ranger', 'Deadeye', 'Beastmaster'), ('Mystic', 'Elementalist', 'Illusionist'),
         ('Thief', 'Ninja', 'Samurai'), ('Necromancer', 'Lich', 'Bone Lord'), ('Monk', 'Shadowfist', 'Iron Sage'),
         ('Templar', 'Inquisitor', 'Sentinel')]
ALL = [name for line in LINES for name in line]
ALL_SET = frozenset(ALL)
ORDER = {name: i for i, name in enumerate(ALL)}
NO_CLASS = 'no class'  # the chip of a rule that lists only the vocation None (id 0): no class of the game can meet it
UNIQUE_SCRIPT = 'chaos_unique_equip.lua'
STOCK_RE = re.compile(r'\t<!-- stock (\d+): (.*?) -->\n')


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def as_bool(value, default=True):
    if value is None:
        return default
    return value.strip().lower() not in ('0', 'false', 'no', '')


def as_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def vocation_names(text):
    """the names of vocations.xml (the engine ignores a name it does not know)"""
    return {v.get('name') for v in ET.fromstring(text).iter('vocation') if v.get('name')}


def vocations_of(node, known):
    """[(name, shown)] of the <vocation> children the engine keeps (names of vocations.xml)"""
    out = []
    for v in node.findall('vocation'):
        name = v.get('name')
        if name in known:
            out.append((name, as_bool(v.get('showInDescription'), True)))
    return out


def parse_movements(text, known):
    """[{ids, slot, level, magic, vocs [(name, shown)], script}] of the Equip entries, in file order"""
    out = []
    for e in ET.fromstring(text).iter('movevent'):
        if e.get('event') != 'Equip':
            continue
        if e.get('itemid') is not None:
            ids = [as_int(e.get('itemid'))]
        elif e.get('fromid') is not None and e.get('toid') is not None:
            ids = list(range(as_int(e.get('fromid')), as_int(e.get('toid')) + 1))
        else:
            continue
        out.append({'ids': ids, 'slot': e.get('slot') or '', 'level': as_int(e.get('level')), 'magic': as_int(e.get('maglevel')),
                    'vocs': vocations_of(e, known), 'script': e.get('script') or ''})
    return out


def parse_weapons(text, known):
    """{id: {tag, level, magic, unproperly, vocs}} of the weapon entries (the last entry of an id wins)"""
    out = {}
    for e in ET.fromstring(text):
        if not isinstance(e.tag, str) or e.get('id') is None:
            continue
        out[as_int(e.get('id'))] = {'tag': e.tag, 'level': as_int(e.get('level')), 'magic': as_int(e.get('maglv')),
                                    'unproperly': as_bool(e.get('unproperly'), False), 'vocs': vocations_of(e, known)}
    return out


def parse_stock(text):
    """{id: None (no stock rule) | {level, vocations (list, None = everyone)}} of the recorded stock rules"""
    out = {}
    for m in STOCK_RE.finditer(text):
        body = m.group(2)
        if body == 'none':
            out[int(m.group(1))] = None
            continue
        d = dict(re.findall(r'(\w+)="([^"]*)"', body))
        voc = d.get('vocations', '*')
        out[int(m.group(1))] = {'level': as_int(d.get('level')), 'vocations': None if voc == '*' else voc.split('|')}
    return out


def class_set(vocs):
    """frozenset of the class names of a vocation list, None when the list is empty (every class)"""
    return frozenset(n for n, _ in vocs) if vocs else None


def meet(a, b):
    """both class sets must allow it (None = every class)"""
    if a is None:
        return b
    if b is None:
        return a
    return a & b


def vocation_string(vocs):
    """the engine's vocation string of an item type: shown names, lower case plural, 'a, b and c'"""
    names = [n.lower() + 's' for n, shown in vocs if shown]
    if len(names) <= 1:
        return ''.join(names)
    return ', '.join(names[:-1]) + ' and ' + names[-1]


class Rules:
    """the rules of one installed data folder"""

    def __init__(self, data_dir):
        voc = os.path.join(data_dir, 'XML', 'vocations.xml')
        self.known = vocation_names(read(voc)) if os.path.exists(voc) else set(ALL)
        mtext = read(os.path.join(data_dir, 'movements', 'movements.xml'))
        self.entries = parse_movements(mtext, self.known)
        self.equip = {}  # id -> [entry, ...] in file order
        for e in self.entries:
            for i in e['ids']:
                self.equip.setdefault(i, []).append(e)
        self.stock = parse_stock(mtext)
        wpath = os.path.join(data_dir, 'weapons', 'weapons.xml')
        self.weapons = parse_weapons(read(wpath), self.known) if os.path.exists(wpath) else {}

    def ids(self):
        return sorted(set(self.equip) | set(self.weapons))

    def entry_rule(self, iid):
        """the Equip entry itself, as the engine checks it (the looser rule when a unique shares the id): {level, magic, set}"""
        found = self.equip.get(iid)
        if not found:
            return None
        e = found[0]
        return {'level': e['level'], 'magic': e['magic'], 'set': class_set(e['vocs'])}

    def refusal(self, iid):
        """what the Equip entry refuses for a PLAIN copy: {level, magic, set (None = every class), script} or None.
        An entry held by chaos_unique_equip.lua is held to its stock rule as well (the entry itself is the looser one)."""
        found = self.equip.get(iid)
        if not found:
            return None
        e = found[0]
        rule = {'level': e['level'], 'magic': e['magic'], 'set': class_set(e['vocs']), 'script': e['script']}
        if e['script'] == UNIQUE_SCRIPT and iid in self.stock:
            st = self.stock[iid]
            if st is None:
                return rule
            rule['level'] = max(rule['level'], st['level'])
            rule['set'] = meet(rule['set'], frozenset(st['vocations']) if st['vocations'] else None)
        return rule

    def weapon(self, iid):
        """the weapon entry's rule {level, magic, set, unproperly} or None"""
        w = self.weapons.get(iid)
        if not w:
            return None
        return {'level': w['level'], 'magic': w['magic'], 'set': class_set(w['vocs']), 'unproperly': w['unproperly']}

    def effective(self, iid):
        """what a character needs to wear it and use it properly: {level, magic, set}; None when no rule at all"""
        r, w = self.refusal(iid), self.weapon(iid)
        if r is None and w is None:
            return None
        parts = [p for p in (r, w) if p is not None]
        out = {'level': max(p['level'] for p in parts), 'magic': max(p['magic'] for p in parts), 'set': None}
        for p in parts:
            out['set'] = meet(out['set'], p['set'])
        return out

    def item_type(self, iid, weapons_last=True):
        """(level, magic level, vocation string) the engine's item type holds: the entry it read last wins. An Equip
        entry always sets them; a weapon entry only when it has a level, a magic level or a shown vocation."""
        level = magic = 0
        voc = ''
        e = self.equip.get(iid)
        w = self.weapons.get(iid)

        def from_equip():
            return e[-1]['level'], e[-1]['magic'], vocation_string(e[-1]['vocs'])

        def from_weapon():
            vs = vocation_string(w['vocs'])
            if w['level'] > 0 or w['magic'] > 0 or vs:
                return w['level'], w['magic'], vs
            return None

        if weapons_last:
            if e:
                level, magic, voc = from_equip()
            if w and from_weapon():
                level, magic, voc = from_weapon()
        else:
            if w and from_weapon():
                level, magic, voc = from_weapon()
            if e:
                level, magic, voc = from_equip()
        return level, magic, voc


def set_text(names):
    """a class set as the sorted name list the Lua file stores"""
    return sorted(names, key=lambda n: ORDER.get(n, 99))


def lua_text(rules):
    """data/lib/chaos_equip_rules.lua: id -> {level, set index (0 = every class)[, magic level]} of the effective rule of
    every id with a class list, or whose Equip and weapon entries disagree on the level"""
    sets, index, rows = [], {}, []
    for iid in rules.ids():
        eff = rules.effective(iid)
        r, w = rules.refusal(iid), rules.weapon(iid)
        disagree = r is not None and w is not None and (r['level'] != w['level'] or r['magic'] != w['magic'])
        if eff['set'] is None and not disagree:
            continue
        key = None
        if eff['set'] is not None:
            names = tuple(set_text(eff['set']))
            if names not in index:
                index[names] = len(sets) + 1
                sets.append(names)
            key = index[names]
        row = '[%d] = {%d, %d%s}' % (iid, eff['level'], key or 0, ', %d' % eff['magic'] if eff['magic'] else '')
        rows.append(row)
    out = ['-- GENERATED by server/tools/install_equip_rules.py from movements.xml and weapons.xml; a re-run rewrites it, do not',
           '-- edit by hand. The rule each id is held to (server/README.md "Equip rules in the tooltip (O490)"): level, the index',
           '-- of the class list in `sets` (0 = every class) and the magic level when there is one. The item tooltip',
           '-- (item_tooltip_core.lua) names these classes; without this file it reads the engine\'s item type as before.',
           'return {', '\tsets = {']
    for names in sets:
        out.append('\t\t{%s},' % ', '.join('"%s"' % n for n in names))
    out += ['\t},', '\trules = {']
    for i in range(0, len(rows), 4):
        out.append('\t\t' + ', '.join(rows[i:i + 4]) + ',')
    out += ['\t},', '}', '']
    return '\n'.join(out)


# ------------------------------------------------------------ the reading of the class chips (the audit holds the tooltip to it)
def read_chips(text):
    """the set of classes the chip text of the tooltip stands for (None text or 'all classes': every class).
    A base class named alone stands for its whole line (the class and its two ascended classes); 'Name only' stands for that
    one class; a line named class by class (an ascended class beside the base, or without it) stands for those classes."""
    if text is None:
        return ALL_SET
    text = text.strip()
    if text == '' or text.lower() == 'all classes':
        return ALL_SET
    if text.lower() == NO_CLASS:
        return frozenset(('None',))
    named, alone = set(), set()
    for part in text.split(','):
        part = part.strip()
        if part.endswith(' only'):
            alone.add(part[:-5].strip())
        elif part:
            named.add(part)
    out = set(alone)
    for base, a1, a2 in LINES:
        got = {n for n in (base, a1, a2) if n in named}
        if got == {base}:
            out.update((base, a1, a2))
        else:
            out.update(got)
    out.update(n for n in named if n not in ALL_SET)  # a name the table does not know stays as it is
    return frozenset(out)

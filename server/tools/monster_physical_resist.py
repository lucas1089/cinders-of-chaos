#!/usr/bin/env python3
"""No hunt monster is immune to physical damage (bug 2026-11-02): a monster that was immune gets a physical resistance.

The Thief line (Thief, Ninja, Samurai), the Barbarian line and the Monk line deal almost only physical damage: weapon
hits, ChaosSpell.weaponStrike (data/spells/chaos/_common.lua) and the attack kit's physical spells. The Thief line's
poison comes from the hit (thief_combat.lua), so it is lost too. Against a physical-immune monster (base Phantasm in
Infinity Tower band 5, Ghost, Burster Spectre of the bounty pool, ...) those classes did no damage at all. The same
rule as fire (owner decision C7, tools/monster_fire_resist.py): the immunity becomes a resistance of
PHYSICAL_RESIST_PERCENT.

PHYSICAL_RESIST_PERCENT is the engine's element percent: 30 means 30% of the physical damage is stopped, the monster
takes 70%. (XML <element physicalPercent="30"/>, Lua {type = COMBAT_PHYSICALDAMAGE, percent = 30}.) Change it here only.

What counts as "immune to physical" (xml / lua below rewrite all of them, idempotent):
  XML  <immunity physical="1"/> or <immunity name="physical"/>, and physicalPercent="100" or more
  Lua  {type = "physical", combat = true} in monster.immunities and {type = COMBAT_PHYSICALDAMAGE, percent = 100 or more}
The engine's physical immunity also stops bleeding. That part stays: XML physical="1" becomes bleed="1", Lua
combat = true becomes combat = false (a condition = true there stays).
Left alone, as nobody could kill them before either:
  * a monster that is not attackable (flag attackable="0" / attackable = false: traps, throwers, quest objects)
  * a monster immune to every damage type but fire (physical, energy, earth, ice, holy, death): event and quest
    creatures that are invulnerable by design. Fire is left out of that test because C7 already turned every fire
    immunity into a resistance, so the test reads the same before and after the fire rule.
User: patch_base_monsters.py (the base server's monsters). Our own monsters: tests/monster_physical_resist_test.lua.
Test: tools/monster_physical_resist_test.py.
"""
import re
import sys

PHYSICAL_RESIST_PERCENT = 30

TRUE = r'(?:1|true|yes)'
# the damage types of the "invulnerable by design" test: (XML immunity names, XML percent names, Lua type names,
# Lua COMBAT_ constant)
KINDS = (
    (('physical',), ('physicalPercent',), ('physical',), 'COMBAT_PHYSICALDAMAGE'),
    (('energy',), ('energyPercent',), ('energy',), 'COMBAT_ENERGYDAMAGE'),
    (('earth', 'poison'), ('earthPercent', 'poisonPercent'), ('earth', 'poison'), 'COMBAT_EARTHDAMAGE'),
    (('ice',), ('icePercent',), ('ice',), 'COMBAT_ICEDAMAGE'),
    (('holy',), ('holyPercent',), ('holy',), 'COMBAT_HOLYDAMAGE'),
    (('death',), ('deathPercent',), ('death',), 'COMBAT_DEATHDAMAGE'),
)

_PHYS_ATTR = re.compile(r'(\s)physical(\s*=\s*")' + TRUE + '"', re.I)
_PHYS_NAME = re.compile(r'(\sname\s*=\s*")physical(")', re.I)
_PHYS_PCT = re.compile(r'(\bphysicalPercent\s*=\s*")(-?\d+)(")')
_XML_NOATTACK = re.compile(r'<flag\s+attackable\s*=\s*"(?:0|false|no)"', re.I)

_LUA_ENTRY = re.compile(r'\{[^{}]*\}')
_LUA_PHYS = re.compile(r'(\{\s*type\s*=\s*COMBAT_PHYSICALDAMAGE\s*,\s*percent\s*=\s*)(-?\d+)')
_LUA_NOATTACK = re.compile(r'\battackable\s*=\s*false\b')


def _strip_xml_comments(text):
    return re.sub(r'<!--.*?-->', '', text, flags=re.S)


def _xml_immune(text, names, pcts):
    for n in names:
        if re.search(r'<immunity\b[^>]*\s%s\s*=\s*"%s"' % (n, TRUE), text, re.I):
            return True
        if re.search(r'<immunity\b[^>]*\sname\s*=\s*"%s"' % n, text, re.I):
            return True
    for p in pcts:
        if any(int(v) >= 100 for v in re.findall(r'\b%s\s*=\s*"(-?\d+)"' % p, text)):
            return True
    return False


def xml_left_alone(text):
    """True when the monster is not attackable or immune to every damage type but fire (see the docstring)"""
    t = _strip_xml_comments(text)
    if _XML_NOATTACK.search(t):
        return True
    return all(_xml_immune(t, names, pcts) for names, pcts, _, _ in KINDS)


def xml(text, percent=PHYSICAL_RESIST_PERCENT):
    """(new text, was immune): physical immunity of one monster XML turned into a physical resistance of `percent`"""
    if xml_left_alone(text):
        return text, False
    immune = False

    def tag(m):
        nonlocal immune
        t = m.group(0)
        new = _PHYS_ATTR.sub(lambda a: a.group(1) + 'bleed' + a.group(2) + '1"', t)
        new = _PHYS_NAME.sub(lambda a: a.group(1) + 'bleed' + a.group(2), new)
        if new != t:
            immune = True
        return new
    new = re.sub(r'<immunity\b[^>]*?/?>', tag, text)
    if any(int(m.group(2)) >= 100 for m in _PHYS_PCT.finditer(new)):
        immune = True
        new = _PHYS_PCT.sub(lambda m: m.group(1) + str(percent) + m.group(3) if int(m.group(2)) >= 100 else m.group(0),
                            new)
    if not immune:
        return text, False
    if _PHYS_PCT.search(new):
        # an element row of its own stays when it is already above the resistance
        new = _PHYS_PCT.sub(lambda m: m.group(1) + str(max(int(m.group(2)), percent)) + m.group(3), new)
        return new, True
    el = re.search(r'([ \t]*)<elements>[ \t]*\r?\n', new)
    if el:
        new = new[:el.end()] + '%s\t<element physicalPercent="%d"/>\n' % (el.group(1), percent) + new[el.end():]
        return new, True
    block = '\t<elements>\n\t\t<element physicalPercent="%d"/>\n\t</elements>\n' % percent
    for b in ('immunities', 'summons', 'voices', 'loot'):
        n = re.search(r'[ \t]*<%s\b' % b, new)
        if n:
            return new[:n.start()] + block + new[n.start():], True
    n = new.rindex('</monster>')
    return new[:n] + block + new[n:], True


def _lua_entry_immune(entry, names):
    m = re.search(r'\btype\s*=\s*"(\w+)"', entry)
    return bool(m and m.group(1) in names and re.search(r'\bcombat\s*=\s*true\b', entry))


def lua_left_alone(text):
    t = re.sub(r'--[^\n]*', '', text)
    if _LUA_NOATTACK.search(t):
        return True
    entries = _LUA_ENTRY.findall(t)
    for names, _, lnames, const in KINDS:
        imm = any(_lua_entry_immune(e, lnames) for e in entries)
        pct = re.findall(r'\{\s*type\s*=\s*%s\s*,\s*percent\s*=\s*(-?\d+)' % const, t)
        if not imm and not any(int(v) >= 100 for v in pct):
            return False
    return True


def lua(text, percent=PHYSICAL_RESIST_PERCENT):
    """(new text, was immune) for a Lua monster file"""
    if lua_left_alone(text):
        return text, False
    immune = False

    def entry(m):
        nonlocal immune
        e = m.group(0)
        if not _lua_entry_immune(e, ('physical',)):
            return e
        immune = True
        return re.sub(r'\bcombat\s*=\s*true\b', 'combat = false', e)
    new = _LUA_ENTRY.sub(entry, text)
    if any(int(m.group(2)) >= 100 for m in _LUA_PHYS.finditer(new)):
        immune = True
        new = _LUA_PHYS.sub(lambda m: m.group(1) + str(percent) if int(m.group(2)) >= 100 else m.group(0), new)
    if not immune:
        return text, False
    if _LUA_PHYS.search(new):
        new = _LUA_PHYS.sub(lambda m: m.group(1) + str(max(int(m.group(2)), percent)), new)
        return new, True
    row = '\t{type = COMBAT_PHYSICALDAMAGE, percent = %d},\n' % percent
    el = re.search(r'monster\.elements\s*=\s*\{[ \t]*\r?\n', new)
    if el:
        return new[:el.end()] + row + new[el.end():], True
    n = re.search(r'monster\.immunities\s*=|mType:register', new)
    pos = n.start() if n else len(new)
    return new[:pos] + 'monster.elements = {\n' + row + '}\n\n' + new[pos:], True


if __name__ == '__main__':
    print(__doc__)
    sys.exit(0)

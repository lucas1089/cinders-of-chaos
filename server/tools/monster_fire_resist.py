#!/usr/bin/env python3
"""No monster is immune to fire (owner decision 2026-10, C7): a monster that was immune gets a fire resistance instead.

Pyre Oath (the Righteous Fire style archetype, data/scripts/chaos/archetypes.lua) burns the player for a share of the
maximum health every second and the enemies in reach for fire damage. Against a fire-immune monster the player paid the
burn for nothing. Owner: the monsters that are fire-immune today get a fire resistance of FIRE_RESIST_PERCENT.

FIRE_RESIST_PERCENT is the engine's element percent: 30 means 30% of the fire damage is stopped, the monster takes 70%.
(XML <element firePercent="30"/>, Lua {type = COMBAT_FIREDAMAGE, percent = 30}.) Change the number here only.

What counts as "immune to fire" (xml / lua below rewrite all of them, idempotent):
  XML  <immunity fire="1"/> (the attribute goes; the tag goes when it has no other) and firePercent="100" or more
  Lua  {type = "fire", ...} in monster.immunities and {type = COMBAT_FIREDAMAGE, percent = 100 or more}
The users: tune_monsters.py (our monsters, row key fire_resist; the pets under monsters/chaos/pets are allies, never
targets of the aura, and keep their immunity) and patch_base_monsters.py (the base server's monsters).
Test: tests/monster_fire_resist_test.lua, tools/monster_fire_resist_test.py.
"""
import re
import sys

FIRE_RESIST_PERCENT = 30

_FIRE_ATTR = re.compile(r'\s+fire\s*=\s*"(?:1|true|yes)"', re.I)
_FIRE_PCT = re.compile(r'(\bfirePercent\s*=\s*")(-?\d+)(")')


def xml(text, percent=FIRE_RESIST_PERCENT):
    """(new text, was immune): fire immunity of one monster XML turned into a fire resistance of `percent`"""
    immune = False

    def line(m):
        nonlocal immune
        lead, tag, tail = m.group(1), m.group(2), m.group(3)
        if not _FIRE_ATTR.search(tag):
            return m.group(0)
        immune = True
        rest = _FIRE_ATTR.sub('', tag)
        if not re.search(r'\s\w+\s*=', rest):
            return ''  # a tag with only the fire attribute goes with its line
        return lead + rest + tail
    new = re.sub(r'([ \t]*)(<immunity\b[^>]*?/?>)([ \t]*(?:\r?\n)?)', line, text)
    if immune:
        new = re.sub(r'[ \t]*<immunities>\s*</immunities>[ \t]*(?:\r?\n)?', '', new)
    if any(int(m.group(2)) >= 100 for m in _FIRE_PCT.finditer(new)):
        immune = True
        new = _FIRE_PCT.sub(lambda m: m.group(1) + str(percent) + m.group(3) if int(m.group(2)) >= 100 else m.group(0), new)
    if not immune:
        return text, False
    if _FIRE_PCT.search(new):
        # an element row of its own stays when it is already above the resistance
        new = _FIRE_PCT.sub(lambda m: m.group(1) + str(max(int(m.group(2)), percent)) + m.group(3), new)
        return new, True
    el = re.search(r'([ \t]*)<elements>[ \t]*\r?\n', new)
    if el:
        new = new[:el.end()] + '%s\t<element firePercent="%d"/>\n' % (el.group(1), percent) + new[el.end():]
        return new, True
    block = '\t<elements>\n\t\t<element firePercent="%d"/>\n\t</elements>\n' % percent
    for b in ('immunities', 'summons', 'voices', 'loot'):
        n = re.search(r'[ \t]*<%s\b' % b, new)
        if n:
            return new[:n.start()] + block + new[n.start():], True
    n = new.rindex('</monster>')
    return new[:n] + block + new[n:], True


_LUA_IMM = re.compile(r'^[ \t]*\{\s*type\s*=\s*"fire"[^}]*\}\s*,?[ \t]*\r?\n', re.M)
_LUA_FIRE = re.compile(r'(\{\s*type\s*=\s*COMBAT_FIREDAMAGE\s*,\s*percent\s*=\s*)(-?\d+)')


def lua(text, percent=FIRE_RESIST_PERCENT):
    """(new text, was immune) for a Lua monster file"""
    immune = bool(_LUA_IMM.search(text))
    new = _LUA_IMM.sub('', text)
    big = [m for m in _LUA_FIRE.finditer(new) if int(m.group(2)) >= 100]
    if big:
        immune = True
        new = _LUA_FIRE.sub(lambda m: m.group(1) + str(percent) if int(m.group(2)) >= 100 else m.group(0), new)
    if not immune:
        return text, False
    if not _LUA_FIRE.search(new):
        row = '\t{type = COMBAT_FIREDAMAGE, percent = %d},\n' % percent
        el = re.search(r'monster\.elements\s*=\s*\{[ \t]*\r?\n', new)
        if el:
            new = new[:el.end()] + row + new[el.end():]
        else:
            n = re.search(r'monster\.immunities\s*=|mType:register', new)
            new = new[:n.start()] + 'monster.elements = {\n' + row + '}\n\n' + new[n.start():]
    return new, True


if __name__ == '__main__':
    print(__doc__)
    sys.exit(0)

#!/usr/bin/env python3
"""Area damage of the base attack spells equals the single-target hit of their tier (idempotent).

usage: python3 -I patch_aoe_damage.py DATA_DIR [--dry-run]

Owner decision (2026-10-20, server/data/spells/README.md "Area damage is uniform"): the damage of an area spell is the
same on every target of the area and the same as the single-target hit of its tier; no falloff per target, jump or
distance, no area discount. The Chaos spells were fixed in their own scripts. This patch does the base scripts under
data/spells/scripts/attack whose per-target hit was under the single-target spell of the same tier:
  * ice_wave (Glacier Fan) and fire_wave (Cinder Fan): the ice_strike / flame_strike formula (1.4 / 2.2 magic level,
    +8 / +14; was 0.8 / 2, +5 / +12 and 1.2 / 2, +7 / +12);
  * scorch (Searing Gust) and chill_out (Rime Breath): the formula of the level 1 single spells Static Sting and Bog
    Splatter (0.4 / 0.8, +2 / +5; was 0.3 / 0.45, +2 / +3), their level and magic level cap of 20 kept;
  * groundshaker (Earthrend), the five blocks: the Bonebreaker formula (skill x attack 0.02 / 0.04, +4 / +9; the
    maximum was 0.03, +6);
  * divine_caldera (Sanctum Burst) and divine_grenade (Radiant Shard), the Ranger line's two area spells, which scale
    with the magic level alone: never under Dawnpiercer, the line's single-target filler (distance skill x the weapon's
    attack 0.042 / 0.065, magic level 1.0 / 1.6, +20 / +40), through a small function at the top of the script that
    asks ChaosSpell.distanceAttack when the Chaos spell library is loaded (the old formula alone otherwise).
Every other base area spell already deals at least the single-target hit of its tier (Greater Glacier Fan, Tempest Fan,
Pyre Torrent, Bramble Fan, the beams, Quakeburst, Shatterfrost, Reaver's Spin, Scything Arc, Butcher's Gyre).
Mana, cooldowns, areas and effects stay. The files keep their line endings (LF or CRLF). A patched script has the
marker line below at its top, so a second run changes nothing. Refuses (exit 1), changing nothing, when a script is
missing or a line to change is not there (as many times as expected).
"""
import os
import re
import sys

MARK = '-- chaos aoe uniform (server/tools/patch_aoe_damage.py)'
ATTACK = os.path.join('spells', 'scripts', 'attack')

HELPER = [
    MARK,
    'local function chaosAoeFloor(player, level, magicLevel, isMax)',
    '\tlocal power = 0',
    '\tif ChaosSpell and ChaosSpell.distanceAttack then',
    '\t\tpower = player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player)',
    '\tend',
    '\tif isMax then',
    '\t\treturn (level / 5) + (power * 0.065) + (magicLevel * 1.6) + 40',
    '\tend',
    '\treturn (level / 5) + (power * 0.042) + (magicLevel * 1.0) + 20',
    'end',
]

# script -> (needs the floor function, [(which line: min or max, the base expression, the new expression, times)])
SCRIPTS = {
    'ice_wave.lua': (False, [
        ('min', '(level / 5) + (magicLevel * 0.8) + 5', '(level / 5) + (magicLevel * 1.4) + 8', 1),
        ('max', '(level / 5) + (magicLevel * 2) + 12', '(level / 5) + (magicLevel * 2.2) + 14', 1)]),
    'fire_wave.lua': (False, [
        ('min', '(level / 5) + (magicLevel * 1.2) + 7', '(level / 5) + (magicLevel * 1.4) + 8', 1),
        ('max', '(level / 5) + (magicLevel * 2) + 12', '(level / 5) + (magicLevel * 2.2) + 14', 1)]),
    'scorch.lua': (False, [
        ('min', '(level / 5) + (magicLevel * 0.3) + 2', '(level / 5) + (magicLevel * 0.4) + 2', 1),
        ('max', '(level / 5) + (magicLevel * 0.45) + 3', '(level / 5) + (magicLevel * 0.8) + 5', 1)]),
    'chill_out.lua': (False, [
        ('min', '(level / 5) + (magicLevel * 0.3) + 2', '(level / 5) + (magicLevel * 0.4) + 2', 1),
        ('max', '(level / 5) + (magicLevel * 0.45) + 3', '(level / 5) + (magicLevel * 0.8) + 5', 1)]),
    'groundshaker.lua': (False, [
        ('max', '(player:getLevel() / 5) + (skill * attack * 0.03) + 6',
         '(player:getLevel() / 5) + (skill * attack * 0.04) + 9', 5)]),
    'divine_caldera.lua': (True, [
        ('min', '(level / 5) + (magicLevel * 5) + 25',
         'math.max((level / 5) + (magicLevel * 5) + 25, chaosAoeFloor(player, level, magicLevel, false))', 5),
        ('max', '(level / 5) + (magicLevel * 6.2) + 45',
         'math.max((level / 5) + (magicLevel * 6.2) + 45, chaosAoeFloor(player, level, magicLevel, true))', 5)]),
    'divine_grenade.lua': (True, [
        ('min', '(level / 5) + (maglevel * 4)',
         'math.max((level / 5) + (maglevel * 4), chaosAoeFloor(player, level, maglevel, false))', 1),
        ('max', '(level / 5) + (maglevel * 6)',
         'math.max((level / 5) + (maglevel * 6), chaosAoeFloor(player, level, maglevel, true))', 1)]),
}


def line_re(which, expr):
    return re.compile(r'^([ \t]*local %s = )%s([ \t]*\r?)$' % (which, re.escape(expr)), re.M)


def patch_text(text, spec):
    """-> (new text, number of changes, error)"""
    needs_floor, reps = spec
    if MARK in text:
        return text, 0, None
    new, n = text, 0
    for which, old, repl, times in reps:
        rx = line_re(which, old)
        found = len(rx.findall(new))
        if found != times:
            return text, 0, 'expected %d line(s) "local %s = %s", found %d' % (times, which, old, found)
        new = rx.sub(lambda m: m.group(1) + repl + m.group(2), new)
        n += found
    eol = '\r\n' if '\r\n' in text else '\n'
    head = HELPER if needs_floor else [MARK]
    new = eol.join(head) + eol + new
    return new, n + 1, None


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    base = os.path.join(args[0], ATTACK)
    out, total = {}, 0
    for name, spec in SCRIPTS.items():
        path = os.path.join(base, name)
        if not os.path.isfile(path):
            print('patch_aoe_damage: %s is missing' % path)
            return 1
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, n, err = patch_text(text, spec)
        if err:
            print('patch_aoe_damage: %s: %s' % (name, err))
            return 1
        if n:
            print('  %s: %d change(s)' % (name, n))
        total += n
        out[path] = (text, new)
    if '--dry-run' not in argv:
        for path, (text, new) in out.items():
            if new != text:
                with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                    f.write(new)
    print('patch_aoe_damage: %d change(s)%s' % (total, ' (dry run)' if '--dry-run' in argv else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

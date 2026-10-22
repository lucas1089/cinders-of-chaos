#!/usr/bin/env python3
"""The base server's waystone tier bosses (server/README.md "Waystone tiers"), idempotent.

usage: python3 -I patch_waystone_bosses.py DATA_DIR [--dry-run]

Player reports of 2026-10-22, checked against the base files and map:
  * entrance  data/scripts/customs/waystone_system/waystone_bosses/boss_waystone_3_map_1.lua (Waystone III, the
              Frostreaver room): its entrancePos 32965,33236,7 is a tar tile (a ground that blocks). The group goes to
              32964,33236,7 next to it, inside the same room (sand). data/scripts/chaos/instance_limits.lua also brings a
              group in that a lever's teleport left outside (ChaosBossRooms.bringIn).
  * pillars   data/monster/lua/waystone_portals/bosses/morgrath_the_umbral_archmage.lua (tier V) takes no damage at
              all unless it stands next to a Katoi Pillar (one pillar every 45 s for 30 s, somewhere in the room), and
              nyxdrath_the_midnight_terror.lua (tier VI) only the element of the pillar next to it: "health bar stays at
              100%". Its health event now keeps a share of such a hit (ChaosWaystoneTiers.shielded,
              waystone_tiers.lua: waystone_tiers_config.lua shieldedShare, 0.25) and tells the attacker the rule;
              next to the right pillar a hit counts in full as before. Without the Chaos scripts loaded the rule is the
              base one (nothing).
Each change carries the marker; a file that has it is left alone (a second run changes nothing). Refuses (exit 1),
writing nothing, when a file is missing or is not the text this patch knows. Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

MARK = '-- Chaos (patch_waystone_bosses.py)'

ROOM = 'scripts/customs/waystone_system/waystone_bosses/boss_waystone_3_map_1.lua'
ENTRANCE_OLD = re.compile(r'^([ \t]*entrancePos = )Position\(32965, 33236, 7\),([ \t]*)(\r?)$', re.M)
ENTRANCE_NEW = r'\1Position(32964, 33236, 7), ' + MARK + r': the stock 32965,33236 is tar (blocks)\3'

BOSSES = 'monster/lua/waystone_portals/bosses/'
MORGRATH = BOSSES + 'morgrath_the_umbral_archmage.lua'
NYXDRATH = BOSSES + 'nyxdrath_the_midnight_terror.lua'
ZERO = re.compile(r'^([ \t]*)return 0, primaryType, 0, secondaryType[ \t]*(\r?)$', re.M)
SHARE = ('{i}local chaosP, chaosS = 0, 0 ' + MARK + ': a share away from the pillar, not nothing{nl}'
         '{i}if ChaosWaystoneTiers and ChaosWaystoneTiers.shielded then ' + MARK + '{nl}'
         '{i}  chaosP, chaosS = ChaosWaystoneTiers.shielded(target, source, primaryDamage, secondaryDamage) ' + MARK + '{nl}'
         '{i}end ' + MARK + '{nl}'
         '{i}return chaosP, primaryType, chaosS, secondaryType ' + MARK)
ELEMENT = re.compile(r'^([ \t]*local (pd|sd) = \((primary|secondary)Type == allowedType\) and (primary|secondary)Damage) or 0'
                     r'[ \t]*(\r?)$', re.M)
SHIELD = r'\1 or (ChaosWaystoneTiers and ChaosWaystoneTiers.shielded and (ChaosWaystoneTiers.shielded(target, nil, \4Damage, 0)) or 0) ' + MARK + r'\5'


class Refused(Exception):
    pass


def patch_room(text):
    if MARK in text:
        return text, False
    new, n = ENTRANCE_OLD.subn(ENTRANCE_NEW, text)
    if n != 1:
        raise Refused('%s: the entrancePos line 32965, 33236, 7 is not there once (%d)' % (ROOM, n))
    return new, True


def patch_zero(text, name):
    m = ZERO.search(text)
    if not m or len(ZERO.findall(text)) != 1:
        raise Refused('%s: "return 0, primaryType, 0, secondaryType" is not there once' % name)
    nl = '\r\n' if m.group(2) else '\n'
    block = SHARE.format(i=m.group(1), nl=nl) + m.group(2)
    return text[:m.start()] + block + text[m.end():]


def patch_morgrath(text):
    if MARK in text:
        return text, False
    if 'archmageNearPillar(target)' not in text:
        raise Refused('%s: no archmageNearPillar(target) check' % MORGRATH)
    return patch_zero(text, MORGRATH), True


def patch_nyxdrath(text):
    if MARK in text:
        return text, False
    if 'pillarTypeAdjacentToBoss(target)' not in text:
        raise Refused('%s: no pillarTypeAdjacentToBoss(target) check' % NYXDRATH)
    text = patch_zero(text, NYXDRATH)
    new, n = ELEMENT.subn(SHIELD, text)
    if n != 2:
        raise Refused('%s: the two "local pd / sd = (...Type == allowedType) and ...Damage or 0" lines (%d)' % (NYXDRATH, n))
    return new, True


FILES = ((ROOM, patch_room), (MORGRATH, patch_morgrath), (NYXDRATH, patch_nyxdrath))


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    out = []
    try:
        for rel, fn in FILES:
            path = os.path.join(data, rel)
            if not os.path.isfile(path):
                raise Refused('data/%s is missing' % rel)
            new, changed = fn(read(path))
            out.append((rel, path, new, changed))
    except Refused as e:
        print('refused, nothing written: %s' % e)
        return 1
    for rel, path, new, changed in out:
        if changed and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('data/%s: %s' % (rel, ('patched' + (' (dry run, not written)' if dry else '')) if changed
                                  else 'already patched'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

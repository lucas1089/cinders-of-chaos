#!/usr/bin/env python3
"""Guard for engine src-patch 0087: a Monk's fist weapon goes in either hand, two at once included (server/README.md
"Fist weapons", O360).

Checks that 0087 is the only patch of its number, touches player.cpp only, that the weapon hand (CONST_SLOT_LEFT) takes
a fist weapon (a shield type with an attack) before it refuses shield types, never next to a quiver or a two-handed
item, and that the fist weapons' Equip events cover both hands (slot "shield" is read as both hands by the engine) and
keep them to the Monk line, so only a Monk holds two.

Run: python3 -I server/tools/fist_either_hand_patch_test.py (standard library only)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
sys.path.insert(0, HERE)
import install_fist_weapons as F  # noqa: E402


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    mine = [n for n in sorted(os.listdir(PATCHES)) if n.startswith('0087-')]
    check(mine == ['0087-fist-weapon-either-hand.patch'], 'one patch 0087: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = sorted(line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/'))
    check(files == ['src/player.cpp'], 'files: %s' % files)
    plus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))
    minus = [line for line in text.splitlines() if line.startswith('-') and not line.startswith('---')]
    check(len(minus) == 1 and 'if (type == WEAPON_NONE || type == WEAPON_SHIELD' in minus[0],
          'only the shield-type refusal line changes (it becomes an else if): %s' % minus)
    check('item->getWeaponType() == WEAPON_SHIELD && item->getAttack() > 0' in plus, 'a fist weapon: shield type with an attack')
    fist = plus.find('if (chaosIsFistWeapon(item)) {')
    refuse = plus.find('} else if (type == WEAPON_NONE || type == WEAPON_SHIELD')
    check(fist >= 0 and refuse > fist, 'the weapon hand takes a fist weapon before it refuses shield types')
    check('chaosIsQuiver(rightItem)' in plus[fist:refuse], 'never next to a quiver')
    check('SLOTP_TWO_HAND' in plus[fist:refuse] and 'RETURNVALUE_BOTHHANDSNEEDTOBEFREE' in plus[fist:refuse],
          'never next to a two-handed item')

    row = {'server_id': 36656, 'ex': {'level': '150'}}
    move = F.move_entries(row)
    check(move.count('slot="shield"') == 2 or move.count('slot="hand"') == 2, 'Equip and DeEquip cover both hands')
    for voc in F.MONK_LINE:
        check('<vocation name="%s"' % voc in move, 'the Monk line only: %s' % voc)

    if failures:
        print('fist_either_hand_patch_test: %d failure(s)' % len(failures))
        return 1
    print('fist_either_hand_patch_test: all ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())

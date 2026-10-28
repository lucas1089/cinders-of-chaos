#!/usr/bin/env python3
"""Guard for engine src-patch 0078: the player attack speed bonus (passive tree and worn pieces).

Owner 2026-10-28: "no attack speed node on the passive tree, few on items", and "the maximum attack speed is 1 attack per
second". The patch adds Player::attackSpeedBonus (Lua Player:getAttackSpeedBonus / setAttackSpeedBonus), counted with the
dexterity points inside Player::getAttackSpeed, so patch 0011's rules still hold on top. This test reads the patch text and
checks that
  * it is the only patch numbered 0078 and touches player.h / player.cpp / luascript.h / luascript.cpp only,
  * the bonus is clamped to 0 .. 100 in the setter and in the Lua binding, and is not saved (iologindata untouched),
  * getAttackSpeed adds it to the dexterity points BEFORE the cap and the floor lines of 0011 (it does not replace them),
  * the patch never touches the floor (minPlayerAttackInterval, 1000 ms) or the 25% cap numbers,
  * 0011 still has the floor default of 1000 ms and no later patch changes it.

Run: python3 -I server/tools/attack_speed_bonus_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')


def files_of(text):
    return [line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/')]


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0078-')]
    check(mine == ['0078-player-attack-speed-bonus.patch'], 'one patch 0078: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    check(sorted(files_of(text)) == ['src/luascript.cpp', 'src/luascript.h', 'src/player.cpp', 'src/player.h'],
          'files: %s' % files_of(text))
    added = '\n'.join(l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++'))
    check('std::min<int16_t>(100, std::max<int16_t>(0, value))' in added, 'setter clamps 0 .. 100')
    check('std::min<int32_t>(100, std::max<int32_t>(0, getNumber<int32_t>(L, 2)))' in added, 'binding clamps 0 .. 100')
    check('"getAttackSpeedBonus"' in added and '"setAttackSpeedBonus"' in added, 'both methods registered')
    check('iologindata' not in text, 'not saved')
    # the bonus line sits right after the dexterity clamp line, which sits before the 0011 cap lines
    check(re.search(r'dexterity = std::min<int32_t>\(100, std::max<int32_t>\(0, getCharacterStat\(CHARSTAT_DEXTERITY\)\)\);\n'
                    r'\+\tdexterity = std::min<int32_t>\(100, dexterity \+ attackSpeedBonus\);', text) is not None,
          'the bonus is added to the dexterity points (still at most 100)')
    check('MIN_PLAYER_ATTACK_INTERVAL' not in added and 'MAX_PLAYER_ATTACK_SPEED_BONUS' not in added
          and 'minPlayerAttackInterval' not in added, 'the floor and the cap numbers are not touched')
    # the floor stays one attack per second
    p11 = open(os.path.join(PATCHES, '0011-attack-speed-cap.patch'), encoding='utf-8').read()
    check('"minPlayerAttackInterval", 1000)' in p11, '0011 floor default is 1000 ms')
    check('interval = std::max<double>(interval, std::max<int32_t>(0, g_config.getNumber(ConfigManager::MIN_PLAYER_ATTACK_INTERVAL)));' in p11,
          '0011 applies the floor last')
    for n in names:
        if n > '0011-z' and n != mine[0]:
            body = open(os.path.join(PATCHES, n), encoding='utf-8').read()
            code = [l for l in body.splitlines() if l.startswith(('+', '-')) and not l.startswith(('+++', '---'))]
            check(not any('integer[MIN_PLAYER_ATTACK_INTERVAL]' in l or 'getGlobalNumber(L, "minPlayerAttackInterval"' in l
                          for l in code), 'no other patch changes the floor: ' + n)
    if failures:
        return 1
    print('attack speed bonus patch test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())

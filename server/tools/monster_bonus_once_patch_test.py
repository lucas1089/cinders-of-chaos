#!/usr/bin/env python3
"""Guard for engine src-patch 0090: the monster level damage bonus is added once per hit (O477).

Game::combatChangeHealth (damage branch) and Game::combatChangeMana add monsterBonusDamage * monster level to the hit of
a monster. A target with onHealthChange (onManaChange) events gets the hit run through them and the function is called
again with origin ORIGIN_NONE, so the block ran twice. The patch skips the block on that re-entry: origin == ORIGIN_NONE
and firstOrigin != ORIGIN_NONE (patch 0051 sets firstOrigin only right before the re-entry). This test reads the patch
text and checks that
  * it is the only patch numbered 0090 and touches src/game.cpp only (no new CombatDamage field, enums.h untouched),
  * it changes exactly two lines, the two bonus blocks (health and mana), and adds the guard to both,
  * it removes no bonus line: the block, MLVL_BONUSDMG and the std::round lines stay as they are,
  * it touches no config key,
  * no later patch removes the guard.
It also computes the arithmetic of the fix, a fixed hit of 40 once and twice, in the engine's float and rounding.
Applying it on a copy of the patched source tree: patch -p1 --dry-run (server/README.md "Monster level bonus once").
Run: python3 -I server/tools/monster_bonus_once_patch_test.py (standard library only)."""
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')

BONUS = 0.0015  # config.lua monsterBonusDamage
BASE_HIT = 40
GUARD = '!(damage.origin == ORIGIN_NONE && damage.firstOrigin != ORIGIN_NONE)'
# level: (once, twice) for a fixed hit of 40; 10 and 950 are measured on the local server (SP o460 before, o477 after)
TABLE = {
    10: (41, 42),
    100: (46, 53),
    300: (58, 84),
    500: (70, 123),
    950: (97, 235),
    1000: (100, 250),
}


def f32(x):
    return struct.unpack('f', struct.pack('f', x))[0]


def c_round(x):
    """std::round: half away from zero"""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def one_pass(value, level):
    """the engine block on a negative hit: value += std::round(value * bonus), bonus a float"""
    bonus = f32(f32(BONUS) * level)
    return value + c_round(f32(value * bonus))


def hit(level, passes):
    value = -BASE_HIT
    for _ in range(passes):
        value = one_pass(value, level)
    return -value


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0090-')]
    check(mine == ['0090-monster-level-bonus-once.patch'], 'one patch 0090: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = [l[6:].split()[0] for l in text.splitlines() if l.startswith('+++ b/')]
    check(files == ['src/game.cpp'], 'files: %s' % files)
    check('enums.h' not in files, 'no new CombatDamage field')
    removed = [l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---')]
    added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
    code_added = [l for l in added if not l.strip().startswith('//')]
    comments_added = [l for l in added if l.strip().startswith('//')]
    check(len(removed) == 2 and len(code_added) == 2, 'two lines changed: %d removed, %d added' % (len(removed), len(code_added)))
    old_cond = 'if (attackerMonster && attackerMonster->getLevel() > 0) {'
    check(all(l.strip() == old_cond for l in removed), 'removes only the condition of the bonus block')
    check(all(l.strip() == old_cond[:-3] + ' && ' + GUARD + ') {' for l in code_added),
          'adds the same condition with the guard')
    check(sum('patch 0090' in l for l in comments_added) == 2, 'both blocks carry a patch 0090 comment')
    # one block in combatChangeHealth (damage branch, 2 tab stops) and one in combatChangeMana (1 tab stop)
    check(sorted(l.count('\t') for l in code_added) == [1, 2], 'one guard in each function')
    for keep in ('MLVL_BONUSDMG', 'std::round', 'bonusDmg', 'firstOrigin = '):
        check(not any(keep in l for l in removed), 'removes no line with ' + keep)
    check('ConfigManager::' not in '\n'.join(code_added) and 'configmanager' not in ''.join(files), 'touches no config key')
    check('getFloat' not in '\n'.join(added), 'adds no config read')
    check(text.count('@@') == 4, 'two hunks')
    for n in names:
        if n > mine[0]:
            body = open(os.path.join(PATCHES, n), encoding='utf-8').read()
            gone = [l for l in body.splitlines() if l.startswith('-') and not l.startswith('---')]
            check(not any('firstOrigin != ORIGIN_NONE' in l or 'patch 0090' in l for l in gone),
                  'no later patch removes the guard: ' + n)
    # arithmetic: the table documents the fix (server/README.md "Monster level bonus once (O477, engine patch 0090)")
    for level, (once, twice) in sorted(TABLE.items()):
        got = (hit(level, 1), hit(level, 2))
        check(got == (once, twice), 'fixed hit %d at level %d: once / twice %s, table %s' % (BASE_HIT, level, got, (once, twice)))
    check(hit(10, 1) == 41 and hit(10, 2) == 42, 'level 10: 41 once, 42 twice')
    check(hit(950, 1) == 97 and hit(950, 2) == 235, 'level 950: 97 once, 235 twice')
    # the factor the live server hit with against the factor the models count
    for level, twice_factor in ((100, 1.15), (300, 1.45), (500, 1.75), (1000, 2.5)):
        old = (1 + BONUS * level) ** 2
        once = 1 + BONUS * level
        check(abs(old / once - twice_factor) < 0.012, 'level %d: extra factor %.3f against %.2f' % (level, old / once, twice_factor))
    for level, share in ((100, 0.87), (300, 0.69), (500, 0.57), (1000, 0.40)):
        got = 1 / (1 + BONUS * level)
        check(abs(got - share) < 0.006, 'level %d: hit falls to %.3f of the old one, text says %.2f' % (level, got, share))
    if failures:
        return 1
    print('monster bonus once patch test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Guard for engine src-patch 0082: monster level, no skull and no spread (O326).

The patch changes Monster::Monster only: it removes the six skull assignments by level and replaces the uniform roll of
the level by the middle of the type's <level> range. This test reads the patch text and checks that
  * it is the only patch numbered 0082 and touches src/monster.cpp only,
  * it removes the six level skulls (white, green, yellow, orange, red, black) and adds no skull assignment,
  * it removes the roll (std::rand) and adds the middle (min + max) / 2, only for a type with both ends set,
  * it keeps `skull = mType->info.skull`, the health / speed bonus lines (MLVL_BONUSHP / MLVL_BONUSSPEED) and the display
    level of patches 0040 / 0044, and touches no config key (the bonus numbers stay in config.lua),
  * no later patch brings the level skull back.
It also simulates the arithmetic: the old roll and the middle give the same mean health bonus.
Applying it on a copy of the patched source tree: patch -p1 --dry-run (server/README.md "Monster level: no skull, no spread").
Run: python3 -I server/tools/monster_level_patch_test.py (standard library only)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0082-')]
    check(mine == ['0082-monster-level-no-skull-no-spread.patch'], 'one patch 0082: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = [l[6:].split()[0] for l in text.splitlines() if l.startswith('+++ b/')]
    check(files == ['src/monster.cpp'], 'files: %s' % files)
    removed = '\n'.join(l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---'))
    added = '\n'.join(l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++'))
    code_added = '\n'.join(l for l in added.splitlines() if not l.strip().startswith('//'))
    for colour in ('WHITE', 'GREEN', 'YELLOW', 'ORANGE', 'RED', 'BLACK'):
        check('skull = SKULL_%s;' % colour in removed, 'removes the %s skull' % colour)
    check(removed.count('skull = ') == 6, 'removes exactly the six level skulls')
    check('skull' not in code_added and 'SKULL_' not in code_added, 'adds no skull code')
    check('std::rand()' in removed and 'std::rand' not in code_added, 'removes the roll')
    check('level = (mType->info.minLevel + mType->info.maxLevel) / 2;' in code_added, 'level is the middle of the range')
    check('if (mType->info.minLevel != 0 && mType->info.maxLevel != 0) {' in text, 'only a type with both ends set')
    for keep in ('mType->info.skull', 'MLVL_BONUS', 'displayLevel', 'g_config'):
        check(keep not in removed and keep not in code_added, 'does not touch ' + keep)
    for n in names:
        if n > mine[0]:
            body = open(os.path.join(PATCHES, n), encoding='utf-8').read()
            code = [l for l in body.splitlines() if l.startswith('+') and not l.startswith('+++')]
            check(not any('skull = SKULL_' in l and 'level' in l for l in code), 'no later patch restores the skull: ' + n)
    # same mean: uniform roll min..max against the middle, health factor 1 + 0.0074 x level
    for lo, hi in ((920, 960), (100, 200), (1, 10), (1980, 2020)):
        rolled = sum(1 + 0.0074 * L for L in range(lo, hi + 1)) / (hi - lo + 1)
        mid = 1 + 0.0074 * ((lo + hi) // 2)
        check(abs(rolled - mid) / rolled < 0.005, 'mean health factor %d-%d: %.4f against %.4f' % (lo, hi, rolled, mid))
    if failures:
        return 1
    print('monster level patch test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())

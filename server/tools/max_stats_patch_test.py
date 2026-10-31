#!/usr/bin/env python3
"""Guard for engine src-patch 0085: maximum health and mana stay inside int32 (server/README.md "Vigil reservation and
maximum overflow (O358)").

Checks that 0085 is the only patch of its number, touches player.h and iologindata.cpp only, that getMaxHealth /
getMaxMana no longer cast the stat share through uint32_t, clamp the stat at 0 and the sum at INT32_MAX, that savePlayer
clamps `health` and `mana`, and that vigils.lua re-reads the true maximum and clamps its reservation.

Run: python3 -I server/tools/max_stats_patch_test.py (standard library only)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
VIGILS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'vigils.lua')


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    mine = [n for n in sorted(os.listdir(PATCHES)) if n.startswith('0085-')]
    check(mine == ['0085-max-health-mana-int32.patch'], 'one patch 0085: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = sorted(line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/'))
    check(files == ['src/iologindata.cpp', 'src/player.h'], 'files: %s' % files)
    plus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))
    minus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('-') and not line.startswith('---'))
    check('static_cast<uint32_t>(healthMax *' in minus and 'static_cast<uint32_t>(manaMax *' in minus, 'the uint32 casts go')
    check('std::max<int16_t>(0, charStats[CHARSTAT_VITALITY])' in plus, 'vitality never negative')
    check('std::max<int16_t>(0, charStats[CHARSTAT_SPIRIT])' in plus, 'spirit never negative')
    check(plus.count('std::numeric_limits<int32_t>::max()') >= 3, 'sums and the saved mana clamped to INT32_MAX')
    check('std::max<int32_t>(0, player->health)' in plus, 'saved health not below 0')
    lua = open(VIGILS, encoding='utf-8').read()
    check('INT32_MAX' in lua and 'did not lower the maximum' in lua, 'vigils.lua clamps and re-reads')
    print('max_stats_patch_test: %s' % ('FAIL' if failures else 'ok'))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

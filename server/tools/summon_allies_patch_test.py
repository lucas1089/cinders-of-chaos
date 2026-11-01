#!/usr/bin/env python3
"""Guard for engine src-patch 0086: a player's summon takes no ally as an opponent (server/README.md "Summons: targets,
walk-through, levels", O86 third pass).

Checks that 0086 is the only patch of its number, touches monster.cpp only, that Monster::isOpponent of a player's
summon returns false for the owner's side (the owner, its summons, its party and their summons) and that
Monster::updateTargetList drops a listed creature that is no opponent any more. The Lua purge of summons_core.lua stays
(a second line for a base without the patch).

Run: python3 -I server/tools/summon_allies_patch_test.py (standard library only)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
CORE = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'summons_core.lua')


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    mine = [n for n in sorted(os.listdir(PATCHES)) if n.startswith('0086-')]
    check(mine == ['0086-summon-allies-not-opponents.patch'], 'one patch 0086: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = sorted(line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/'))
    check(files == ['src/monster.cpp'], 'files: %s' % files)
    plus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))
    minus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('-') and not line.startswith('---'))
    check('if (creature != getMaster()) {' in minus, 'the stock "everybody but the master" goes')
    check('creature->getMaster() ? creature->getMaster() : creature' in plus, 'a summon counts as its master')
    check('if (side == owner) {' in plus, 'the owner and its summons are no opponents')
    check('sidePlayer->getParty() == party' in plus and 'party &&' in plus, 'the party (when there is one) is no opponent')
    check('|| !isOpponent(creature))' in plus, 'updateTargetList drops a creature that is no opponent any more')
    lua = open(CORE, encoding='utf-8').read()
    check('function M.purge(' in lua, 'the Lua purge stays as a second line')
    print('summon_allies_patch_test: %s' % ('FAIL' if failures else 'ok'))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

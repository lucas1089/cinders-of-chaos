#!/usr/bin/env python3
"""Guard for engine src-patch 0083: a creature refresh on a tile cannot strand a creature (server/README.md "Creature
refresh on a tile (src-patch 0083)").

sendUpdateTileCreature wrote a 0x6B with the tile position and the stack position as one byte, then the creature in full
with "remove 0". This test reads 0083 and checks that
  * it is the only patch numbered 0083 and touches protocolgame.cpp, protocolgame.h and player.h only,
  * the byte stack position and the position form are gone from the function and the id form (0xFFFF + creature id) is in,
  * a stack position under 0, a position the player cannot see and a creature not in knownCreatureSet send nothing,
  * the creature is written with "remove = its own id" (the client keeps its object) and checkCreatureAsKnown is not
    called any more (the refresh must not make a creature known),
  * the stack position is a signed int32_t from player.h to the packet (-1 is not 0xFF) and a creature without a tile is refused,
  * the Lua patch 0056 and Monster::setName still go through Player::sendUpdateTileCreature(creature) (no other caller form).

Run: python3 -I server/tools/creature_refresh_patch_test.py (standard library only)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')


def files_of(text):
    return [line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/')]


def lines(text, sign):
    return [line[1:] for line in text.splitlines() if line.startswith(sign) and not line.startswith(sign * 3)]


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0083-')]
    check(mine == ['0083-creature-refresh-by-id.patch'], 'one patch 0083: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    check(sorted(files_of(text)) == ['src/player.h', 'src/protocolgame.cpp', 'src/protocolgame.h'], 'files: %s' % files_of(text))
    plus, minus = '\n'.join(lines(text, '+')), '\n'.join(lines(text, '-'))

    check('msg.addPosition(pos);' in minus and 'msg.addByte(stackpos);' in minus, 'the position form with a byte stack position is removed')
    check('msg.addPosition(pos)' not in plus and 'addByte(stackpos)' not in plus, 'the new function writes no position and no byte index')
    check('msg.add<uint16_t>(0xFFFF);' in plus and 'msg.add<uint32_t>(creature->getID());' in plus, 'the id form is written')
    check('stackpos < 0' in plus and '!canSee(pos)' in plus, 'no stack position and no sight: nothing is sent')
    check('knownCreatureSet.find(creature->getID()) == knownCreatureSet.end()' in plus, 'a creature the client never got is not sent')
    check('AddCreature(msg, creature, false, creature->getID());' in plus, 'the creature is written in full with remove = its own id')
    check('checkCreatureAsKnown' in minus and 'checkCreatureAsKnown' not in plus, 'the refresh no longer marks a creature known')
    check('uint32_t stackpos' in minus and 'int32_t stackpos' in plus, 'the stack position is signed')
    check('creature->getTile()' in plus, 'Player::sendUpdateTileCreature refuses a creature without a tile')
    check(text.find('0x6B') == -1 or 'msg.addByte(0x6B);' not in minus or 'msg.addByte(0x6B);' in plus,
          'the 0x6B opcode is kept')
    check(minus.count('known') >= 1, 'the known-creature code left the function')

    # no caller passes an unsigned stack position
    callers = []
    for n in names:
        t = open(os.path.join(PATCHES, n), encoding='utf-8').read()
        if n != mine[0] and 'sendUpdateTileCreature(' in t:
            callers.append(n)
    check(callers == ['0056-summon-display-level-refresh.patch'], 'other patches that call it: %s' % callers)
    check('->sendUpdateTileCreature(monster);' in open(os.path.join(PATCHES, callers[0]), encoding='utf-8').read(),
          '0056 calls the creature form')
    later = [n for n in names if n > mine[0] and 'sendUpdateTileCreature' in open(os.path.join(PATCHES, n), encoding='utf-8').read()]
    check(not later, 'no later patch edits the function: %s' % later)

    print('creature_refresh_patch_test: %s' % ('OK' if not failures else '%d FAILED' % len(failures)))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

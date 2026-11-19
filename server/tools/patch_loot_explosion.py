#!/usr/bin/env python3
"""Hooks the loot explosion's ownership rule (data/scripts/chaos/loot_explosion.lua, O669) into the base server.

usage: python3 -I patch_loot_explosion.py DATA_DIR [--dry-run]

data/events/scripts/player.lua: Player:onMoveItem asks ChaosLootExplosion.onMoveItem first. A script callback cannot refuse
an item move reliably here (the base EventCallback dispatcher keeps only the return value of the LAST onMoveItem callback,
and treats only `false` as a stop, which the engine reads as 0 = "no error"), so the loose loot of a kill (custom attribute
chaos_loot) is guarded by this call, as the season isolation and the pouches are. The hook returns early only when the
rule refuses the move (another player's loot, before the owner time ran out); otherwise the base function runs exactly as
before. When the item goes into a container (the backpack) the hook also takes the loot attribute off it first, so it stacks
with its like.

Idempotent: the change carries a marker and is not made twice. Run it again after replacing the base file.
"""
import os
import re
import sys

MARKER = '-- Chaos: loot explosion ownership (patch_loot_explosion.py)'
HOOK = (
    '\t' + MARKER + '\n'
    '\tif ChaosLootExplosion and ChaosLootExplosion.onMoveItem then\n'
    '\t\tlocal chaosLootRet = ChaosLootExplosion.onMoveItem(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)\n'
    '\t\tif chaosLootRet and chaosLootRet ~= RETURNVALUE_NOERROR then\n'
    '\t\t\treturn chaosLootRet\n'
    '\t\tend\n'
    '\tend\n'
)
HEADER = re.compile(r'function Player:onMoveItem\(item, count, fromPosition, toPosition, fromCylinder, toCylinder\)[ \t]*(\r?\n)')


def patch_player(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    m = HEADER.search(text)
    if not m:
        return text, 'Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder) not found'
    hook = HOOK.replace('\n', m.group(1))
    return text[:m.end()] + hook + text[m.end():], 'patched'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    path = os.path.join(args[0], 'events', 'scripts', 'player.lua')
    if not os.path.isfile(path):
        print('%s: not found' % path)
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, st = patch_player(text)
    if st not in ('patched', 'already'):
        print('events/scripts/player.lua: %s' % st)
        return 1
    if st == 'patched' and not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('events/scripts/player.lua: %s%s' % (st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

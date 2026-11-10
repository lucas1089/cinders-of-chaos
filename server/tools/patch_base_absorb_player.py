#!/usr/bin/env python3
"""The base absorb event leaves a player's hit alone when the player defence layer is on (O464), idempotent.
install_all.py step `absorbplayer`.

usage: python3 -I patch_base_absorb_player.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. scripts/customs/rarity/rarity_onCombat_absorbs.lua (event
rarity_onHealthChangeAbsorb, registered on every player at login) is the LAST healthchange event of a player: it adds the
two absorb storages of each damage type (gear rarity rolls 977544.., passive tree and Paragon 977562..) and takes the sum off
the hit. Since O464 data/scripts/chaos/player_defence.lua reads the same storages as sources of its resistances and its
physical reduction and applies them first, so the event must not take them a second time. The patch makes the event return
the hit unchanged for a player while `ChaosPlayerDefence.active()` is true; with the layer missing or switched off
(player_defence_config.lua `enabled`) the event works as before. Marker:
`-- Chaos: the absorb is the player defence layer's (patch_base_absorb_player.py)`. A second run changes nothing.
"""
import os
import sys

MARKER = "-- Chaos: the absorb is the player defence layer's (patch_base_absorb_player.py)"
TARGET = os.path.join('scripts', 'customs', 'rarity', 'rarity_onCombat_absorbs.lua')

ANCHOR = '''    if not target or not target:isPlayer() then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
'''
INSERT = '''    %s
    if ChaosPlayerDefence and ChaosPlayerDefence.active() then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end
''' % MARKER


def patch(text):
    """(new text, [change, ...])"""
    if MARKER in text:
        return text, []
    if text.count(ANCHOR) != 1:
        return text, ['REFUSED: expected code not found (the player check of rarity_onHealthChangeAbsorb)']
    return text.replace(ANCHOR, ANCHOR + INSERT), ["a player's hit is left to the player defence layer"]


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    path = os.path.join(args[0], TARGET)
    name = TARGET.replace(os.sep, '/')
    if not os.path.isfile(path):
        print('%s: not found (skipped)' % name)
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    new, changes = patch(text.replace('\r\n', '\n'))
    if changes and changes[0].startswith('REFUSED'):
        print('%s: %s' % (name, changes[0]))
        return 1
    if not changes:
        print('absorb for players: nothing to change')
        return 0
    if crlf:
        new = new.replace('\n', '\r\n')
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('%s: %s' % (name, ', '.join(changes)))
    print('absorb for players: 1 file %s' % ('would change' if dry else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

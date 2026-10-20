#!/usr/bin/env python3
"""Makes the Annihilator quest soloable (idempotent). install_all.py step `annihilatorsolo`.

usage: python3 -I patch_annihilator_solo.py DATA_DIR [--dry-run]

Owner 2026-10-18: "faça a annihilator ser solável".
DATA_DIR is the base server's data folder. actions/scripts/quests/annihilator/lever.lua wants four players of level 100 on
the four tiles in front of the lever and always spawns six demons. The patch lets one to four players go in: the players
standing on the tiles are taken (any tile, in order) and at least one must stand there. The demons scale with the team,
`DEMONS_PER_PLAYER` (2) each up to the six positions, so a solo player meets two demons. The level rule (100) stays.
Marker: `-- Chaos: annihilator solo (patch_annihilator_solo.py)`. A second run changes nothing.
"""
import os
import sys

MARKER = '-- Chaos: annihilator solo (patch_annihilator_solo.py)'
LEVER = os.path.join('actions', 'scripts', 'quests', 'annihilator', 'lever.lua')
DEMONS_PER_PLAYER = 2

OLD_LOOP = '''		for i = 1, #config.playerPositions do
			playerTile = Tile(config.playerPositions[i]):getTopCreature()
			if not playerTile or not playerTile:isPlayer() then
				player:sendTextMessage(MESSAGE_STATUS_SMALL, "You need 4 players.")
				return true
			end

			if playerTile:getLevel() < config.requiredLevel then
				player:sendTextMessage(MESSAGE_STATUS_SMALL, "All the players need to be level ".. config.requiredLevel .." or higher.")
				return true
			end

			storePlayers[#storePlayers + 1] = playerTile
		end
'''
NEW_LOOP = '''		for i = 1, #config.playerPositions do
			playerTile = Tile(config.playerPositions[i]):getTopCreature()
			if playerTile and playerTile:isPlayer() then
				if playerTile:getLevel() < config.requiredLevel then
					player:sendTextMessage(MESSAGE_STATUS_SMALL, "All the players need to be level ".. config.requiredLevel .." or higher.")
					return true
				end

				storePlayers[#storePlayers + 1] = playerTile
			end
		end
		if #storePlayers == 0 then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, "You need at least 1 player on the tiles.")
			return true
		end
'''
OLD_DEMONS = '''		for i = 1, #config.demonPositions do
			Game.createMonster("Demon", config.demonPositions[i])
		end
'''
NEW_DEMONS = '''		for i = 1, math.min(#config.demonPositions, #storePlayers * %d) do
			Game.createMonster("Demon", config.demonPositions[i])
		end
''' % DEMONS_PER_PLAYER


def patch(text):
    """(new text, [change, ...])"""
    if MARKER in text:
        return text, []
    changes = []
    for old, new, what in ((OLD_LOOP, NEW_LOOP, 'one to four players'), (OLD_DEMONS, NEW_DEMONS, 'demons scale with the team')):
        if old not in text:
            return text, ['REFUSED: expected code not found (%s)' % what]
        text = text.replace(old, new)
        changes.append(what)
    return MARKER + '\n' + text, changes


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    path = os.path.join(args[0], LEVER)
    if not os.path.isfile(path):
        print('%s: not found (skipped)' % LEVER.replace(os.sep, '/'))
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    new, changes = patch(text.replace('\r\n', '\n'))
    if changes and changes[0].startswith('REFUSED'):
        print('%s: %s' % (LEVER.replace(os.sep, '/'), changes[0]))
        return 1
    if not changes:
        print('annihilator solo: nothing to change')
        return 0
    if crlf:
        new = new.replace('\n', '\r\n')
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('%s: %s' % (LEVER.replace(os.sep, '/'), ', '.join(changes)))
    print('annihilator solo: 1 file %s' % ('would change' if dry else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

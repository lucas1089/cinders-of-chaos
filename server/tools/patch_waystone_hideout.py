#!/usr/bin/env python3
"""The base server's waystone device works in the owner's hideout, not only in a house (idempotent).

usage: python3 -I patch_waystone_hideout.py DATA_DIR [--dry-run]

The base waystone system (data/scripts/customs/waystone_system/tier_maps.lua) is made for houses: the device (item
29624 / 29626, action id 42707) refuses unless its tile is a house tile ("You may only use Waystone Portal inside a
House."), and the portal pads that open next to it are made only on tiles of a house the player owns ("There is no
space in your house to spawn portals."). The Chaos hideout (server/README.md "Hideouts") is a runtime room with no
engine house, so the device would never work there. Patched in tier_maps.lua:
  * a helper chaosWaystonePlace(player, pos, ownerOnly) after the PAD_AID line: true on a house tile (an owned one when
    ownerOnly), or on a tile of the player's own hideout (ChaosHideout.isOwnRoomTile(player, pos), data/scripts/chaos/
    hideout.lua; read when used, so the load order does not matter);
  * the use check and the pad tile check call the helper (a house keeps working exactly as before);
  * the "wrap" answer refuses the device that is a fixture of a hideout (ChaosHideout.isFixture);
  * the texts: "You may only use the Waystone Portal in your hideout or inside a house." and "There is no space in your
    hideout or house to spawn portals."
and in data/items/items.xml the descriptions of the six Waystone Tier items ("... on waystone device at house ...")
say "... on the waystone device in your hideout or house ...". The portal kit (29628) stays "in your house": building a
device from a kit needs a house, the hideout has its own device built in. Every change is made once (a second run changes
nothing). Refuses (exit 1), changing nothing, when tier_maps.lua or items.xml is missing or is not the text this patch
knows (a line to change not there). Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

MARK = '-- Chaos: waystone device in the hideout (patch_waystone_hideout.py)'
USE_OLD = re.compile(r'if not fromPosition:getTile\(\):getHouse\(\) then(\r?\n)(\s*)player:sendTextMessage\(MESSAGE_INFO_DESCR, '
                     r'"You may only use Waystone Portal inside a House\."\)')
USE_NEW = ('if not chaosWaystonePlace(player, fromPosition, false) then', 'You may only use the Waystone Portal in your hideout or inside a house.')
PAD_OLD = re.compile(r'local tileHouse = tile:getHouse\(\)(\r?\n)(\s*)if tileHouse and tileHouse:getOwnerGuid\(\) == player:getGuid\(\) '
                     r'and tile:isWalkable\(\) then')
PAD_NEW = 'if chaosWaystonePlace(player, spawnPos, true) and tile:isWalkable() then'
MSG_OLD = '"There is no space in your house to spawn portals."'
MSG_NEW = '"There is no space in your hideout or house to spawn portals."'
PAD_ANCHOR = re.compile(r'^local PAD_AID = \d+[ \t]*\r?$', re.M)
WRAP_ANCHOR = re.compile(r'^([ \t]*)waystoneDevice:transform\(29628\)[ \t]*\r?$', re.M)

HELPER = [
    MARK,
    '-- true on a house tile (one the player owns when ownerOnly), or on a tile of the player\'s own hideout',
    'local function chaosWaystonePlace(player, pos, ownerOnly)',
    '  local tile = Tile(pos)',
    '  local house = tile and tile:getHouse()',
    '  if house and (not ownerOnly or house:getOwnerGuid() == player:getGuid()) then',
    '    return true',
    '  end',
    '  return ChaosHideout ~= nil and ChaosHideout.isOwnRoomTile ~= nil and ChaosHideout.isOwnRoomTile(player, pos) == true',
    'end',
]

DESC_OLD = re.compile(r'Use This waystone on waystone device at house to teleport to a random tier (\d+) map\.')
DESC_NEW = 'Use this waystone on the waystone device in your hideout or house to teleport to a random tier %s map.'
DESC_DONE = re.compile(r'Use this waystone on the waystone device in your hideout or house to teleport to a random tier (\d+) map\.')


def nl_of(text):
    return '\r\n' if '\r\n' in text else '\n'


def patch_lua(text):
    """-> (new text, changes, error)"""
    if MARK in text:
        # patched before: all the pieces must be there
        for need in ('chaosWaystonePlace(player, fromPosition, false)', 'chaosWaystonePlace(player, spawnPos, true)',
                     'ChaosHideout.isFixture(waystoneDevice)', MSG_NEW):
            if need not in text:
                return text, [], 'marker present but "%s" is missing' % need
        return text, [], None
    nl = nl_of(text)
    if not USE_OLD.search(text):
        return text, [], 'the use check (fromPosition:getTile():getHouse() with its message) is not as expected'
    if not PAD_OLD.search(text):
        return text, [], 'the pad tile check (tile:getHouse() owned by the player) is not as expected'
    if text.count(MSG_OLD) != 1:
        return text, [], 'the "no space in your house" message is not as expected'
    if len(PAD_ANCHOR.findall(text)) != 1 or len(WRAP_ANCHOR.findall(text)) != 1:
        return text, [], 'the PAD_AID line or the wrap answer is not as expected'
    new = USE_OLD.sub(lambda m: '%s%s%s%splayer:sendTextMessage(MESSAGE_INFO_DESCR, "%s")' % (
        USE_NEW[0], m.group(1), m.group(2), '', USE_NEW[1]), text, count=1)
    new = PAD_OLD.sub(lambda m: PAD_NEW, new, count=1)
    new = new.replace(MSG_OLD, MSG_NEW, 1)
    new = WRAP_ANCHOR.sub(lambda m: nl.join([
        '%sif ChaosHideout and ChaosHideout.isFixture and ChaosHideout.isFixture(waystoneDevice) then' % m.group(1),
        '%s  player:sendExtendedOpcode(OPCODE, json.encode{' % m.group(1),
        '%s    action = "wrap_error",' % m.group(1),
        '%s    text   = "The waystone portal of your hideout cannot be wrapped."' % m.group(1),
        '%s  })' % m.group(1),
        '%s  return true' % m.group(1),
        '%send' % m.group(1),
        m.group(0).rstrip('\r')]) + ('\r' if m.group(0).endswith('\r') else ''), new, count=1)
    new = PAD_ANCHOR.sub(lambda m: m.group(0).rstrip('\r') + nl + nl.join(HELPER) + ('\r' if m.group(0).endswith('\r') else ''),
                         new, count=1)
    return new, ['helper chaosWaystonePlace', 'use check', 'pad tile check', 'wrap refusal', 'two messages'], None


def patch_items(text):
    """-> (new text, changes, error): the six Waystone Tier descriptions"""
    old = DESC_OLD.findall(text)
    done = DESC_DONE.findall(text)
    if len(old) + len(done) != 6:
        return text, [], 'expected 6 Waystone Tier descriptions, found %d' % (len(old) + len(done))
    if not old:
        return text, [], None
    new = DESC_OLD.sub(lambda m: DESC_NEW % m.group(1), text)
    return new, ['%d Waystone Tier description(s)' % len(old)], None


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    dry = '--dry-run' in argv
    jobs = [('scripts/customs/waystone_system/tier_maps.lua', patch_lua), ('items/items.xml', patch_items)]
    out, total = [], 0
    for rel, fn in jobs:
        path = os.path.join(args[0], *rel.split('/'))
        if not os.path.isfile(path):
            print('patch_waystone_hideout: %s is missing' % path)
            return 1
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, changes, err = fn(text)
        if err:
            print('patch_waystone_hideout: %s: %s' % (rel, err))
            return 1
        for c in changes:
            print('  %s: %s' % (rel, c))
        total += len(changes)
        out.append((path, text, new))
    if not dry:
        for path, text, new in out:
            if new != text:
                with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                    f.write(new)
    print('patch_waystone_hideout: %d change(s)%s' % (total, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

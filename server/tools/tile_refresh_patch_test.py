#!/usr/bin/env python3
"""Guard for engine src-patch 0084: tile:refresh() from Lua (server/README.md "Tile refresh (src-patch 0084)", O349).

A pickup taken in onStepIn is removed with a 0x6C by stack position; on a client whose tile holds a thing the server's
does not, that index named the own character (invisible) and the globe stayed. This test reads 0084 and checks that
  * it is the only patch numbered 0084 and touches luascript.cpp and luascript.h only,
  * Tile:refresh is registered and declared, and sends the whole tile (Player::sendUpdateTile) to the players around,
  * pickups.lua calls tile:refresh after a drop and after every removal, guarded for an engine without the patch.

Run: python3 -I server/tools/tile_refresh_patch_test.py (standard library only)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
PICKUPS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'pickups.lua')


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    mine = [n for n in sorted(os.listdir(PATCHES)) if n.startswith('0084-')]
    check(mine == ['0084-tile-refresh.patch'], 'one patch 0084: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = sorted(line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/'))
    check(files == ['src/luascript.cpp', 'src/luascript.h'], 'files: %s' % files)
    plus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))
    minus = [line for line in text.splitlines() if line.startswith('-') and not line.startswith('---')]
    check(not minus, 'only additions')
    check('registerMethod("Tile", "refresh", LuaScriptInterface::luaTileRefresh);' in plus, 'Tile:refresh registered')
    check('static int luaTileRefresh(lua_State* L);' in plus, 'declared')
    check('getSpectators(spectators, pos, true, true)' in plus, 'the players around, every floor')
    check('player->sendUpdateTile(tile, pos);' in plus, 'the whole tile goes out (0x69)')

    lua = open(PICKUPS, encoding='utf-8').read()
    check('if tile and tile.refresh then' in lua, 'pickups.lua guards an engine without the patch')
    check(lua.count('refreshAt(') >= 5 and 'X.refreshAt(pos)' in lua, 'pickups.lua refreshes after the drop and the removals')
    print('tile_refresh_patch_test: %s' % ('FAIL' if failures else 'ok'))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

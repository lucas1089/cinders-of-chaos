#!/usr/bin/env python3
"""Guard for engine src-patch 0092: the Rune Bag in the purse (O509; server/README.md "Using a rune from the bag").

The purse is the store inbox, outside inventory slots 1-10. The patch lets a player's search, count and removal BY ITEM
TYPE also look into the Rune Bag that lies in it, and nothing else of the purse. This test reads the patch text and checks
that
  * it is the only patch numbered 0092 and touches exactly game.cpp, luascript.cpp, luascript.h, player.cpp and the new
    header chaosrunebag.h (no config key, no new protocol, no save format),
  * every place that reaches into the purse goes through ChaosRuneBag::forEachItem (the one narrow rule): the added code
    never walks the store inbox itself (no iterator over it, no findItemOfType on it, no getStoreInbox()->getItemList),
  * the six places are there: Game::findItemOfType (a player, depthSearch, after the inventory walk, so the backpack is
    preferred), Player::getItemTypeCount, countRemovableItemsOfType (which removeItemOfType, the NPC sell checks and
    player:getItemCount use), getAllUnlockedItemTypeCount, getAllItemTypeCount, and Game.setRuneBagContainer,
  * the removal walk honours the lock and the limit as the inventory walk does,
  * the header is one pure template and holds no engine include,
  * the Lua side names the same things: pouches.lua calls Game.setRuneBagContainer with the id of kinds.runes of
    pouches_config.lua (no id in C++), tests the function's presence as the capability, and no later patch removes the hooks.
With an argument (a source tree after 0001-0090) it also dry-runs the patch with --fuzz=0 on a copy.
Run: python3 -I server/tools/rune_bag_purse_patch_test.py [SOURCE_TREE]   (standard library only; patch for the dry run)"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, '..')
PATCHES = os.path.join(SERVER, 'src-patches')
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0092-')]
    check(mine == ['0092-rune-bag-in-purse.patch'], 'one patch 0092: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    files = [l[6:].split()[0] for l in text.splitlines() if l.startswith('+++ b/')]
    check(sorted(files) == ['src/chaosrunebag.h', 'src/game.cpp', 'src/luascript.cpp', 'src/luascript.h', 'src/player.cpp'],
          'files: %s' % files)
    added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
    removed = [l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---')]
    check(not removed, 'the patch only adds lines (removed: %d)' % len(removed))
    code = '\n'.join(l for l in added if not l.strip().startswith('//'))
    check('ConfigManager::' not in code and 'g_config' not in code, 'no config key')
    check('configmanager' not in ''.join(files) and 'protocol' not in ''.join(files), 'no protocol, no config file')

    # split the patch by file
    per = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r'^\+\+\+ b/(\S+)', line)
        if m:
            cur = m.group(1)
            per[cur] = []
        elif cur and line.startswith('+') and not line.startswith('+++'):
            per[cur].append(line[1:])
    body = {k: '\n'.join(v) for k, v in per.items()}

    # the one rule: the purse is only reached through forEachItem
    for f in ('src/game.cpp', 'src/player.cpp', 'src/luascript.cpp'):
        c = '\n'.join(l for l in per.get(f, []) if not l.strip().startswith('//'))
        check('iterator()' not in c and 'ContainerIterator' not in c, f + ': no iterator over a container added')
        check('findItemOfType' not in c, f + ': no second search by type added')
        check('getItemList' not in c and 'getItems(' not in c, f + ': the purse is not walked by hand')
    check(body['src/game.cpp'].count('ChaosRuneBag::forEachItem(player->getStoreInbox()') == 1,
          'game.cpp: one walk, the player\'s store inbox')
    check('depthSearch' in body['src/game.cpp'] and 'dynamic_cast<Player*>(cylinder)' in body['src/game.cpp'],
          'game.cpp: only a deep search of a player')
    check(body['src/player.cpp'].count('ChaosRuneBag::forEachItem(storeInbox') == 4,
          'player.cpp: four walks (type count, removable count, unlocked map, count map)')
    for fn in ('getItemTypeCount', 'countRemovableItemsOfType', 'getAllUnlockedItemTypeCount', 'getAllItemTypeCount'):
        check(('@@' in text) and fn in text, 'the hunk of ' + fn + ' is there (context)')
    # the removal walk: lock and limit as the inventory walk
    check('includeLocked || !bagItem->holdsChaosLocked()' in body['src/player.cpp'], 'player.cpp: a locked item is skipped')
    check('count >= limit' in body['src/player.cpp'] and 'itemList->push_back(bagItem)' in body['src/player.cpp'],
          'player.cpp: the limit and the list as the inventory walk')
    check(body['src/player.cpp'].count('holdsChaosLocked') == 2, 'player.cpp: the two lock checks (removable, unlocked map)')
    # the search order: the new walk is the tail of findItemOfType, after the whole container walk (its closing brace is the
    # context just before it) and before the final return nullptr, so the backpack is always preferred
    g = text[text.index('diff --git a/src/game.cpp'):text.index('diff --git a/src/luascript.cpp')]
    lines = g.splitlines()
    first = next(i for i, l in enumerate(lines) if l.startswith('+') and "a player's search by type ends in the Rune Bag" in l)
    check(lines[first - 2] == ' \t}' and lines[first - 1] == '+', 'game.cpp: added right after the closing brace of the container walk')
    after = next(i for i, l in enumerate(lines[first:], first) if not l.startswith('+'))
    check(lines[after].strip() == 'return nullptr;', 'game.cpp: the old final return nullptr follows the new block')
    check('Game", "setRuneBagContainer"' in body['src/luascript.cpp'] and 'setBagType(itemId)' in body['src/luascript.cpp'],
          'luascript.cpp: Game.setRuneBagContainer sets the type')
    check('it.isContainer()' in body['src/luascript.cpp'], 'luascript.cpp: only a container type')
    check('luaGameSetRuneBagContainer' in body['src/luascript.h'], 'luascript.h: declared')

    # the header: pure
    h = body['src/chaosrunebag.h']
    check('#include' in h and h.count('#include') == 1 and '<cstdint>' in h, 'header: only <cstdint>')
    check('template <class Inbox, class Fn>' in h and 'bool forEachItem' in h, 'header: one pure template')
    check('entry->getID() != type' in h and 'entry->getContainer()' in h, 'header: only a bag of the type, only a container')
    check(h.count('for (auto*') == 2, 'header: two levels only (the inbox, the bag): nothing deeper')
    check('getContainer' in h and 'getContainer()' not in h.split('for (auto* item')[1], 'header: the bag\'s items are not descended into')

    # Lua side
    po = open(os.path.join(CHAOS, 'pouches.lua'), encoding='utf-8').read()
    cfg = open(os.path.join(CHAOS, 'pouches_config.lua'), encoding='utf-8').read()
    check('Game.setRuneBagContainer' in po, 'pouches.lua calls Game.setRuneBagContainer')
    check(re.search(r'Game\.setRuneBagContainer\(\s*k\.id\s*\)|Game\.setRuneBagContainer\(\s*cfg\(\)\.kinds\.runes\.id\s*\)', po),
          'pouches.lua passes the id of kinds.runes (no id in C++)')
    check(re.search(r'runes = \{id = (\d+)', cfg) is not None, 'pouches_config.lua has the runes kind')
    check('Game.setRuneBagContainer ~= nil' in po or 'Game.setRuneBagContainer then' in po or
          'not (Game and Game.setRuneBagContainer)' in po, 'pouches.lua tests the function as the capability')
    ids = re.findall(r'\b\d{5}\b', code)
    rune_id = re.search(r'runes = \{id = (\d+)', cfg).group(1)
    check(rune_id not in ids, 'no Rune Bag id in the C++ added')
    for n in names:
        if n > mine[0]:
            b = open(os.path.join(PATCHES, n), encoding='utf-8').read()
            gone = [l for l in b.splitlines() if l.startswith('-') and not l.startswith('---')]
            check(not any('ChaosRuneBag' in l or 'patch 0092' in l for l in gone), 'no later patch removes the hooks: ' + n)

    # optional: a dry run on a copy of a source tree
    if len(sys.argv) > 1:
        tree = sys.argv[1]
        tmp = tempfile.mkdtemp(prefix='o509_')
        try:
            os.makedirs(os.path.join(tmp, 'src'))
            for f in ('game.cpp', 'luascript.cpp', 'luascript.h', 'player.cpp'):
                shutil.copy(os.path.join(tree, 'src', f), os.path.join(tmp, 'src', f))
            r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, mine[0])], cwd=tmp,
                               capture_output=True, text=True)
            check(r.returncode == 0, 'patch --fuzz=0 --dry-run on %s: %s' % (tree, r.stdout + r.stderr))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        return 1
    print('rune bag in purse patch test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())

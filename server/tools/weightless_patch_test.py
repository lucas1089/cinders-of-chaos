#!/usr/bin/env python3
"""Guard for engine src-patch 0038: weightless containers (the store's Loot Bag).

Owner 2026-10-13: the Loot Bag is "uma bag sem fundo que pode carregar todo o loot que o jogador recebe
automaticamente". The engine part: a container type registered with Game.setWeightlessContainer(itemId) weighs only
itself, the weight of its contents stops at it, and an item put into it skips the holder's capacity check. This test
reads 0038 and checks that
  * it is the only patch numbered 0038 and it touches container.h / container.cpp / luascript.h / luascript.cpp only,
  * Container::updateItemWeight stops at a weightless container before it reaches the parent,
  * Container::getWeight returns the item's own weight for a weightless container,
  * Container::queryAdd asks the top parent with FLAG_NOLIMIT when the target lies in a weightless container,
  * Game.setWeightlessContainer is registered, declared and refuses an item type that is not a container,
  * no later patch rewrites these functions back,
and that the Lua side matches: pouches_config.lua marks the Loot Bag weightless with up to 1000 slots (over 255: paged, src-patch 0081), pouches.lua registers it only where the engine has the function.

Run: python3 -I server/tools/weightless_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
PATCHES = os.path.join(ROOT, 'src-patches')
CHAOS = os.path.join(ROOT, 'data', 'scripts', 'chaos')


def files_of(text):
    return [line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/')]


def added(text):
    return '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0038-')]
    check(mine == ['0038-weightless-containers.patch'], 'one patch 0038: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    check(sorted(files_of(text)) == ['src/container.cpp', 'src/container.h', 'src/luascript.cpp', 'src/luascript.h'],
          'files: %s' % files_of(text))
    plus = added(text)

    # updateItemWeight: the early return sits inside the function, before the parent call
    m = re.search(r'void Container::updateItemWeight\(int32_t diff\)\n.\{\n(.*?)\n.\}', text, re.S)
    body = m.group(1) if m else ''
    check('+\tif (isWeightless()) {' in body and '+\t\treturn;' in body, 'updateItemWeight stops at a weightless bag')
    check(body.find('isWeightless()') < body.find('getParentContainer()'), 'before the parent is updated')
    check('totalWeight += diff;' in body.split('isWeightless')[0], 'its own total still counts (shown on look)')

    m = re.search(r'uint32_t Container::getWeight\(\) const\n.\{\n(.*?)\n.\}', text, re.S)
    body = m.group(1) if m else ''
    check('+\t\treturn Item::getWeight();' in body, 'getWeight: the bag itself only')

    check('ownerFlags |= FLAG_NOLIMIT;' in plus and 'if (insideWeightless()) {' in plus, 'queryAdd: FLAG_NOLIMIT inside')
    check('return topParent->queryAdd(INDEX_WHEREEVER, *item, count, ownerFlags, actor);' in plus,
          'queryAdd: the flags reach the holder')
    check('c = c->getParentContainer()' in plus, 'insideWeightless walks up the parents')

    check('registerMethod("Game", "setWeightlessContainer", LuaScriptInterface::luaGameSetWeightlessContainer);' in plus,
          'Lua function registered')
    check('static int luaGameSetWeightlessContainer(lua_State* L);' in plus, 'Lua function declared')
    check('!it.isContainer()' in plus, 'only container types')
    check('static void setWeightlessType(uint16_t itemId, bool on);' in plus, 'type setter declared')

    # no later patch puts the stock lines back
    for name in names:
        if name > mine[0] and name.endswith('.patch'):
            later = open(os.path.join(PATCHES, name), encoding='utf-8').read()
            later_plus = added(later)
            check('return Item::getWeight() + totalWeight;' not in later_plus, name + ' rewrites getWeight')
            check('flags | FLAG_CHILDISOWNER, actor);' not in later_plus, name + ' rewrites queryAdd')

    cfg = open(os.path.join(CHAOS, 'pouches_config.lua'), encoding='utf-8').read()
    m = re.search(r'\n\t\tloot = \{(.*?)\},\n\t\torbs', cfg, re.S)
    loot = m.group(1) if m else ''
    check('weightless = true' in loot, 'the Loot Bag is weightless')
    cap = re.search(r'capacity = (\d+)', loot)
    check(cap is not None and 0 < int(cap.group(1)) <= 1000, 'Loot Bag slots at most 1000 (over 255 needs src-patch 0081)')
    for kind in ('orbs', 'keys'):
        m = re.search(r'\n\t\t%s = \{(.*?)\}' % kind, cfg, re.S)
        check(m is not None and 'weightless' not in m.group(1), kind + ' pouch keeps its weight')

    po = open(os.path.join(CHAOS, 'pouches.lua'), encoding='utf-8').read()
    check('if not (Game and Game.setWeightlessContainer) then' in po, 'pouches.lua: an engine without 0038 is fine')
    check('pcall(PO.registerWeightless)' in po, 'pouches.lua registers at load')

    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('weightless_patch_test: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())

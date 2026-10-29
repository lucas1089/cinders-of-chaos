#!/usr/bin/env python3
"""Guard for engine src-patch 0081: paged containers over 250 slots (the Loot Bag with 500 slots).

The container packet writes the capacity in ONE byte, so a container could have 255 slots at most. Owner 2026-10-29: the
Loot Bag holds 500. Containers over Container::CHAOS_PAGE_SIZE (250) have pagination and are sent in pages of 250. This
test reads 0081 and checks that
  * it is the only patch numbered 0081 and touches container.h, game.cpp, player.cpp and protocolgame.cpp only,
  * hasPagination() is also true over the page size and pageSize() is capped at it,
  * the packet byte, the items per packet, the seek, the add / update / remove updates and the batch refresh use pageSize(),
  * no line of the patch changes the real capacity() (queryAdd and the free-slot maths keep the 500),
  * pouches_config.lua gives the Loot Bag more than 250 slots only with this patch present, and install_pouches.py
    refuses a capacity over 250 without the file.

Run: python3 -I server/tools/container_pages_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
PATCHES = os.path.join(ROOT, 'src-patches')
CHAOS = os.path.join(ROOT, 'data', 'scripts', 'chaos')


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
    mine = [n for n in names if n.startswith('0081-')]
    check(mine == ['0081-container-pages.patch'], 'one patch 0081: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    check(sorted(files_of(text)) == ['src/container.h', 'src/game.cpp', 'src/player.cpp', 'src/protocolgame.cpp'],
          'files: %s' % files_of(text))
    plus = '\n'.join(lines(text, '+'))
    minus = '\n'.join(lines(text, '-'))

    check('static constexpr uint32_t CHAOS_PAGE_SIZE = 250;' in plus, 'page size 250')
    check('return pagination || capacity() > CHAOS_PAGE_SIZE;' in plus, 'hasPagination over the page size')
    check('return capacity() > CHAOS_PAGE_SIZE ? CHAOS_PAGE_SIZE : capacity();' in plus, 'pageSize capped')
    check('msg.addByte(container->getName() == "Quiver" ? 4 : container->pageSize());' in plus, 'packet byte is the page size')
    check('std::min<uint32_t>(container->pageSize(), containerSize - firstIndex)' in plus, 'items per packet')
    check('(index % container->pageSize()) != 0' in plus, 'seek in whole pages')
    check(plus.count('container->pageSize()') >= 8, 'player.cpp / game.cpp / protocolgame.cpp use pageSize: %d' % plus.count('container->pageSize()'))
    # every removed line was a capacity() use that became pageSize(), except hasPagination's body
    removed_caps = [l for l in minus.splitlines() if 'capacity()' in l]
    check(len(removed_caps) >= 8, 'the page maths moved off capacity(): %d lines' % len(removed_caps))
    check('queryAdd' not in plus and 'queryMaxCount' not in plus, 'the real capacity checks are untouched')

    # no later patch puts the stock lines back
    for name in names:
        if name > mine[0] and name.endswith('.patch'):
            later = '\n'.join(lines(open(os.path.join(PATCHES, name), encoding='utf-8').read(), '+'))
            check('(index % container->capacity())' not in later, name + ' rewrites the seek')
            check('container->getName() == "Quiver" ? 4 : container->capacity()' not in later, name + ' rewrites the packet byte')

    cfg = open(os.path.join(CHAOS, 'pouches_config.lua'), encoding='utf-8').read()
    for kind, cap in re.findall(r'\n\t\t(loot|orbs|keys|gems) = \{.*?capacity = (\d+)', cfg, re.S):
        c = int(cap)
        check(c <= 250 or (kind == 'loot' and c <= 1000), 'only the Loot Bag is paged: %s %d' % (kind, c))
    inst = open(os.path.join(HERE, 'install_pouches.py'), encoding='utf-8').read()
    check('0081-container-pages.patch' in inst and "cfg['capacity'] <= 250 or os.path.exists(PAGES_PATCH)" in inst,
          'install_pouches.py needs the patch file over 250 slots')

    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('container_pages_patch_test: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())

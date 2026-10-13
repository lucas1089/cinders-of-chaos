#!/usr/bin/env python3
"""Guard for engine src-patch 0033: a decay that cannot change the item ends instead of looping forever.

Game::startDecay() of an item with no time left calls Game::internalDecayItem(), which transformed the item to its
decayTo and called startDecay() again. An item that transformItem() returns unchanged (the base items.xml has item 23827
"dead dawnfly" decaying to 23827) made the two call each other forever: the stress test's server froze 15 minutes after a
Dawnfly was killed (server/README.md "Stress test"). This test reads the patch chain in order and checks that the last
patch that writes Game::internalDecayItem in src/game.cpp
  * transforms only to another id (decayTo > 0 and not the item's own id),
  * stops the decay when transformItem() left the item as it was (same object, same id),
  * removes the item for its own id or 0, and stops the decay for a negative decayTo,
and that no later patch puts the stock unconditional "transformItem(item, item->getDecayTo()); startDecay(newItem);"
back. It also checks the reason with a model of the two functions: the stock rule loops on 23827, the patched one ends.

Run: python3 -I server/tools/decay_loop_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')


def added_function(text, name):
    """the '+' and ' ' lines of the hunks of src/game.cpp that hold `name`, as one string (empty when none)"""
    out, inside, hunk = [], False, []
    for line in text.splitlines() + ['@@ end']:
        if line.startswith('+++ '):
            inside = line[4:].split()[0].endswith('src/game.cpp')
            continue
        if line.startswith('--- '):
            continue
        if line.startswith('@@'):
            body = '\n'.join(hunk)
            if name in body:
                out.append(body)
            hunk = []
            continue
        if inside and (line.startswith('+') or line.startswith(' ')):
            hunk.append(line[1:])
    return '\n'.join(out)


def model(decay_to_of, item_id, patched, limit=1000):
    """internalDecayItem / startDecay of an item with no time left: the ids it goes through, or None when it never
    ends (more than `limit` calls). decay_to_of: id -> decayTo; an id that is not in it has a duration (stops)."""
    seen, cur = [], item_id
    for _ in range(limit):
        seen.append(cur)
        to = decay_to_of.get(cur)
        if to is None:
            return seen  # the next stage has its own time: decays later, no loop
        if not patched:
            # stock: transformItem(item, to) returns the item unchanged for its own id, and startDecay() comes back
            cur = to if to != cur else cur
            if to == 0:
                return seen + ['removed']
            continue
        if to > 0 and to != cur:
            cur = to
            continue
        return seen + (['stopped'] if to < 0 else ['removed'])
    return None


def main():
    fails = []
    last = None
    for name in sorted(os.listdir(PATCHES)):
        if not re.match(r'^\d{4}-.*\.patch$', name):
            continue
        with open(os.path.join(PATCHES, name), errors='replace') as f:
            body = added_function(f.read(), 'Game::internalDecayItem')
        if body:
            last = (name, body)
    if last is None:
        fails.append('no patch writes Game::internalDecayItem (0033 is missing): a self-decaying item freezes the game loop')
    else:
        name, body = last
        checks = [
            (r'decayTo\s*>\s*0\s*&&\s*decayTo\s*!=\s*oldId', 'transforms only to another id'),
            (r'newItem\s*==\s*item\s*&&\s*newItem->getID\(\)\s*==\s*oldId[\s\S]{0,80}stopDecay\(item\)',
             'stops when transformItem() left the item as it was'),
            (r'decayTo\s*<\s*0[\s\S]{0,60}stopDecay\(item\)', 'stops for a negative decayTo'),
            (r'internalRemoveItem\(item\)', 'removes the item for its own id or 0'),
        ]
        for pattern, what in checks:
            if not re.search(pattern, body):
                fails.append('%s: Game::internalDecayItem no longer %s' % (name, what))
        if re.search(r'transformItem\(item,\s*item->getDecayTo\(\)\);\s*\n\s*startDecay\(newItem\);', body):
            fails.append('%s: the stock unconditional transform + startDecay is back' % name)
    # the model: why the guard is needed (base items.xml: 23826 -> 23827 -> 23827, 23828 never reached)
    base = {23826: 23827, 23827: 23827}
    if model(base, 23826, patched=False) is not None:
        fails.append('model: the stock rule should loop on 23827')
    if model(base, 23826, patched=True) != [23826, 23827, 'removed']:
        fails.append('model: the patched rule should remove 23827, got %r' % (model(base, 23826, patched=True),))
    if model({100: 101}, 100, patched=True) != [100, 101]:
        fails.append('model: an ordinary decay changed')
    if model({7: -1}, 7, patched=True) != [7, 'stopped']:
        fails.append('model: a negative decayTo should stop')
    for f in fails:
        print('FAIL ' + f)
    print('decay_loop_patch_test: Game::internalDecayItem last written by %s, %d failure(s)'
          % (last[0] if last else '-', len(fails)))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())

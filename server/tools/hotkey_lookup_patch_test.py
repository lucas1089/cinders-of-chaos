#!/usr/bin/env python3
"""Guard for engine src-patch 0043: a hotkey (an inventory use by client id) finds an item of another type with the same
look (the Everfull potions share the stock potions' client ids), and prefers one that is never used up.

Reads the patch chain in order and checks that the last patch writing the hotkey branch of Game::internalGetThing
(src/game.cpp, `pos.y == 0 && pos.z == 0`) tries, in order, an item of that look that is never used up
(findItemOfClientId(..., true)), the stock lookup (findItemOfType of the mapped type), then any item of that look
(findItemOfClientId(..., false)); that findItemOfClientId compares getClientID() with the same subType rule and walks
the inventory before the containers; that "never used up" is stackable and store-bound (chaos_storebound); that the
actions.cpp hotkey message says "(never runs out)" for such an item instead of "Using the last ..."; and a model of
the rules: stock finds nothing for an Everfull-only backpack, the patch finds the Everfull potion, and with stock
potions carried as well the patch uses the Everfull potion first (the stock rule the stock one).

Run: python3 -I server/tools/hotkey_lookup_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')


def hunks_with(text, name, path='src/game.cpp'):
    """the '+' and ' ' lines of the `path` hunks that hold `name`, as one string"""
    out, inside, hunk = [], False, []
    for line in text.splitlines() + ['@@ end']:
        if line.startswith('+++ '):
            inside = line[4:].split()[0].endswith(path)
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


def lookup(carried, client_to_server, client_id, patched):
    """carried: [(server id, client id, never used up)] in search order; the server id the hotkey uses, or None"""
    if patched:
        for sid, cid, free in carried:
            if cid == client_id and free:
                return sid
    mapped = client_to_server.get(client_id)
    for sid, _cid, _free in carried:
        if sid == mapped:
            return sid
    if patched:
        for sid, cid, _free in carried:
            if cid == client_id:
                return sid
    return None


def main():
    fails = []
    last = None
    actions = None
    for name in sorted(os.listdir(PATCHES)):
        if not re.match(r'^\d{4}-.*\.patch$', name):
            continue
        with open(os.path.join(PATCHES, name), errors='replace') as f:
            text = f.read()
        body = hunks_with(text, 'findItemOfClientId')
        if body:
            last = (name, body)
        msg = hunks_with(text, 'showUseHotkeyMessage', 'src/actions.cpp')
        if msg:
            actions = (name, msg)
    if last is None:
        fails.append('no patch adds findItemOfClientId (0043 missing): a hotkey cannot use an Everfull potion')
    else:
        name, body = last
        checks = [
            (r'Item\* found = findItemOfClientId\(player, spriteId, subType, true\);\s*'
             r'if \(!found\) \{\s*found = findItemOfType\(player, it\.id, true, subType\);\s*\}\s*'
             r'if \(!found\) \{\s*found = findItemOfClientId\(player, spriteId, subType, false\);',
             'the never-used-up item of the look first, then the stock lookup, then any item of the look'),
            (r'static Item\* findItemOfClientId\(Cylinder\* cylinder, uint16_t clientId, int32_t subType, bool neverUsedUp\)',
             'the helper'),
            (r'item->getClientID\(\) == clientId && \(subType == -1 \|\| subType == item->getSubType\(\)\) &&\s*'
             r'\(!neverUsedUp \|\| chaosNeverUsedUp\(item\)\)', 'same look, the same subType rule, the never-used-up filter'),
            (r'static bool chaosNeverUsedUp\(Item\* item\)\s*\{\s*return item && item->isStackable\(\) && '
             r'item->getCustomAttribute\("chaos_storebound"\) != nullptr;', 'never used up: stackable and store-bound'),
        ]
        for pat, what in checks:
            if not re.search(pat, body, re.S):
                fails.append('%s: %s' % (name, what))
        if body.find('cylinder->getFirstIndex()') > body.find('containers[i]->getItemList()'):
            fails.append('%s: the inventory must be searched before the containers' % name)
    if actions is None or 'chaosNeverUsedUp' not in actions[1]:
        fails.append('no patch changes showUseHotkeyMessage: an Everfull potion reads "Using the last ..."')
    else:
        name, msg = actions
        m = re.search(r'if \(chaosNeverUsedUp\(item\)\) \{(.*?)\} else if \(!it\.showCount\)', msg, re.S)
        if not m or '(never runs out).' not in m.group(1) or 'last' in m.group(1).replace('"Using the last', ''):
            fails.append('%s: the never-used-up branch comes first and says "(never runs out)", not "the last"' % name)
        if not re.search(r'static bool chaosNeverUsedUp\(const Item\* item\)\s*\{\s*return item && item->isStackable\(\) && '
                         r'const_cast<Item\*>\(item\)->getCustomAttribute\("chaos_storebound"\) != nullptr;', msg):
            fails.append('%s: actions.cpp uses the same never-used-up rule as game.cpp' % name)
    # the model: client id 266 maps to the stock health potion 7618; the Everfull 32085 has the same look
    cmap = {266: 7618}
    only_everfull = [(1988, 2854, False), (32085, 266, True)]
    both = [(1988, 2854, False), (7618, 266, False), (32085, 266, True)]
    only_stock = [(1988, 2854, False), (7618, 266, False)]
    if lookup(only_everfull, cmap, 266, False) is not None:
        fails.append('model: the stock rule should find nothing (the bug the patch fixes)')
    if lookup(only_everfull, cmap, 266, True) != 32085:
        fails.append('model: the patch should find the Everfull potion')
    if lookup(both, cmap, 266, True) != 32085:
        fails.append('model: with stock potions carried too the patch uses the Everfull potion first (free, infinite)')
    if lookup(both, cmap, 266, False) != 7618:
        fails.append('model: the stock rule uses the stock potion')
    if lookup(only_stock, cmap, 266, True) != 7618:
        fails.append('model: without an Everfull potion the stock one is used')
    for f in fails:
        print('FAIL: ' + f)
    print('hotkey_lookup_patch_test: %s' % ('ok' if not fails else '%d failed' % len(fails)))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())

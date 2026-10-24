#!/usr/bin/env python3
"""NPCs that trade for something other than gold (idempotent). install_all.py step `npccurrency`.

usage: python3 -I patch_npc_currency.py DATA_DIR [--dry-run]

Owner beta 2026-10-24 (server/README.md "NPC currencies"): at the azure NPC the trade window said "Currency: Gold Coin"
and priced the set pieces "30" with no unit, next to the player's gold. Eight base NPC scripts (the azure NPC, the
five mining-crafting NPCs that pay in town coins kept in a player storage, the sweets NPC, the token NPC) open the stock
shop window, whose 10.98 packet carries no currency, and told the old client the currency by two extended opcodes
(`ServerOpcodes.currencyType` 125 with a code such as "AZ", `ServerOpcodes.coinAmount` 126 with the amount) that our
client never read; 125 is also the monster bar's opcode. This tool changes, in data/npc/scripts/*.lua:

1. the three lines that sent the code, counted the currency (an item count or a storage) and sent the amount become
       local chaosCurrency = {code = "AZ", item = 26780}            (a storage: {code = "H", storage = 48079, name = "..."})
       ChaosNpcCurrency.announce(player, chaosCurrency)
   (data/lib/chaos_npc_currency.lua, JSON on opcode 113 `npcCurrency`; the client module game_npctradewindow shows
   the currency's name and icon, the balance and readable rows). A storage currency's name is read from the script's
   own "Bought ... for N <name> coins." message.
2. the next `openShopWindow(cid, shop, onBuy, onSell)` wraps both callbacks, so the balance is sent again after every
   purchase and sale.
3. a sell message that names another currency than the one it pays ("... for 15 <old name> Coins.") names the
   item's own plural.
4. the azure NPC's reply to "azure" ("Stuff for all vocations, A and B for knights, C for sorcerers and druids and D
   for paladins.") names our classes and says where the coins drop, in the player's language (ChaosNpcCurrency.setsReply).
5. data/global.lua: ServerOpcodes 125 / 126 become 126 / 127, so a script this tool does not know no longer talks to the
   monster bar.
A file gets one line at the top that loads the library. Files are found by their stock lines, not by name. Exact match on
the stock lines; anything else is reported and left alone. Marker `Chaos: npc currency (patch_npc_currency.py)`;
a second run changes nothing.
"""
import os
import re
import sys

MARK = 'Chaos: npc currency (patch_npc_currency.py)'
LOAD = 'if not ChaosNpcCurrency then pcall(dofile, "data/lib/chaos_npc_currency.lua") end -- ' + MARK

BLOCK = re.compile(
    r'^(?P<ind>[ \t]*)player:sendExtendedOpcode\(ServerOpcodes\.currencyType,\s*"(?P<code>[^"]*)"\)[ \t]*\n'
    r'[ \t]*local coinAmount = player:(?:getStorageValue\((?P<st>\d+)\)|getItemCount\((?P<it>\d+)\)) or 0[ \t]*\n'
    r'[ \t]*player:sendExtendedOpcode\(ServerOpcodes\.coinAmount,\s*tostring\(coinAmount\)\)[ \t]*\n',
    re.M)
OPEN = re.compile(r'openShopWindow\(cid,\s*shop,\s*onBuy,\s*onSell\)')
OPEN_NEW = 'openShopWindow(cid, shop, ChaosNpcCurrency.wrap(onBuy, chaosCurrency), ChaosNpcCurrency.wrap(onSell, chaosCurrency))'
# the name of a storage currency: "... for "..totalCost.." hallowfall coins.")
NAME = re.compile(r'\.\.\s*"\s+([A-Za-z\' -]+?)\s+coins?\.', re.I)
# the sell message of an item currency, which names another currency than the item it pays
SELL_MSG = re.compile(r'(" for "\.\.\s*amount\s*\*\s*itemsTable\[item\]\.sell\s*\.\.\s*)" \w+ Coins\."')
# "Stuff for all vocations, A and B for knights, C, for sorcerers and druids and D for paladins."
SETS = re.compile(
    r'npcHandler:say\(\s*\{?\s*"Stuff for all vocations, (\w+) and (\w+) for knights, (\w+),? for sorcerers and druids '
    r'and (\w+) for paladins\."\s*\}?\s*,\s*cid\)', re.I)
GLOBAL_OLD = re.compile(r'(ServerOpcodes\s*=\s*\{\s*currencyType\s*=\s*)125(\s*,\s*coinAmount\s*=\s*)126(\s*\})')


def is_currency_script(text):
    return 'ServerOpcodes.currencyType' in text


def patch_script(text):
    """(new text, [change, ...]); a first change starting with REFUSED is an error. text has \\n line ends."""
    if MARK in text:
        return text, []
    changes = []
    out = text
    m = BLOCK.search(out)
    if not m:
        return text, ['REFUSED: the stock currency lines were not found']
    tail = out[m.end():]
    om = OPEN.search(tail)
    if not om:
        return text, ['REFUSED: no openShopWindow(cid, shop, onBuy, onSell) after the currency lines']
    code = m.group('code')
    if m.group('it'):
        spec = '{code = "%s", item = %s}' % (code, m.group('it'))
    else:
        nm = NAME.search(out)
        name = nm.group(1).strip().lower() + ' coins' if nm else code
        spec = '{code = "%s", storage = %s, name = "%s"}' % (code, m.group('st'), name)
    ind = m.group('ind')
    repl = '%slocal chaosCurrency = %s -- %s\n%sChaosNpcCurrency.announce(player, chaosCurrency)\n' % (ind, spec, MARK, ind)
    tail = tail[:om.start()] + OPEN_NEW + tail[om.end():]
    out = out[:m.start()] + repl + tail
    changes.append('announces the currency (%s) and its balance' % code)
    changes.append('the shop callbacks send the balance again')
    out, n = SELL_MSG.subn(lambda sm: sm.group(1) + '" "..ItemType(%s):getPluralName().."."' % m.group('it'), out) \
        if m.group('it') else (out, 0)
    if n:
        changes.append('the sell message names the currency it pays')
    out, n = SETS.subn(lambda sm: 'npcHandler:say(ChaosNpcCurrency.setsReply(cid, "%s", "%s", "%s", "%s"), cid)' %
                       (sm.group(1), sm.group(2), sm.group(3), sm.group(4)), out)
    if n:
        changes.append('the sets reply names our classes and where the coins drop')
    return LOAD + '\n' + out, changes


def patch_global(text):
    if MARK in text:
        return text, []
    new, n = GLOBAL_OLD.subn(lambda m: m.group(1) + '126' + m.group(2) + '127' + m.group(3) + ' -- ' + MARK, text, count=1)
    if not n:
        return text, []
    return new, ['ServerOpcodes 125 / 126 became 126 / 127 (125 is the monster bar)']


def lua_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.endswith('.lua'):
                yield os.path.join(dirpath, fn)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    changed, bad, found = 0, 0, 0
    jobs = [(p, is_currency_script, patch_script) for p in lua_files(os.path.join(data, 'npc', 'scripts'))]
    glob = os.path.join(data, 'global.lua')
    if os.path.isfile(glob):
        jobs.append((glob, lambda t: 'ServerOpcodes' in t, patch_global))
    for path, test, patch in jobs:
        text = read(path)
        if MARK not in text and not test(text):
            continue
        if path != glob:
            found += 1
        crlf = '\r\n' in text
        new, changes = patch(text.replace('\r\n', '\n'))
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        if changes and changes[0].startswith('REFUSED'):
            print('%s: %s' % (rel, changes[0]))
            bad += 1
            continue
        if not changes:
            continue
        if crlf:
            new = new.replace('\n', '\r\n')
        if not dry:
            write(path, new)
        print('%s: %s' % (rel, ', '.join(changes)))
        changed += 1
    if not found:
        print('npc currency: no NPC script with a custom currency found')
    print('npc currency: %d file(s) %s' % (changed, 'would change' if dry else 'changed') if changed
          else 'npc currency: nothing to change')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Hooks the season isolation (data/scripts/chaos/season.lua) into two base server files.

usage: python3 -I patch_season_events.py DATA_DIR [--dry-run]

1. data/events/events.xml: enables Player onTradeRequest and onTradeAccept. The base server ships them disabled, so the
   script callbacks (EventCallback onTradeRequest / onTradeAccept) never run. Player:onTradeRequest and
   Player:onTradeAccept in data/events/scripts/player.lua already dispatch to the callbacks; nothing else changes for
   standard characters (the callbacks allow every trade outside a season, and the base activated-card check of
   onTradeRequest starts to apply, as its author intended).

2. data/events/scripts/player.lua: Player:onMoveItem asks ChaosSeason.onMoveItem first. A script callback cannot
   refuse an item move reliably here: the base EventCallback dispatcher only keeps the return value of the LAST
   onMoveItem callback (and treats only `false` as a stop, which the engine then reads as 0 = "no error"). The hook
   returns early only when the season rules refuse the move; otherwise the base function runs exactly as before.

3. data/lib/core/player.lua: Player.transferMoneyTo (the money transfer of every NPC bank) asks
   ChaosSeason.npcTransferBlocked first, so gold cannot go from a season character to a standard one or back while the
   season runs (the NPC then says "You cannot transfer money to this account." and the player gets the season reason).
   The patched file also sets ChaosSeasonTransferPatched = true; season.lua wraps the function at runtime only when
   that flag is missing (an unpatched lib, or a lib reloaded from an unpatched copy).

Idempotent: every change carries a marker and is not made twice. Run it again after replacing the base files.
"""
import os, re, sys

MARKER = '-- Chaos: season isolation (patch_season_events.py)'
HOOK = (
    '\t' + MARKER + '\n'
    '\tif ChaosSeason and ChaosSeason.onMoveItem then\n'
    '\t\tlocal chaosSeasonRet = ChaosSeason.onMoveItem(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)\n'
    '\t\tif chaosSeasonRet and chaosSeasonRet ~= RETURNVALUE_NOERROR then\n'
    '\t\t\treturn chaosSeasonRet\n'
    '\t\tend\n'
    '\tend\n'
)


TRANSFER_MARKER = '-- Chaos: season isolation of the NPC bank transfer (patch_season_events.py)'


def patch_lib_player(text):
    """returns (new text, status): the guard at the top of Player.transferMoneyTo"""
    if TRANSFER_MARKER in text:
        return text, 'already'
    m = re.search(r'function Player\.transferMoneyTo\(self, target, amount\)[ \t]*(\r?\n)', text)
    if not m:
        return text, 'Player.transferMoneyTo(self, target, amount) not found'
    nl = m.group(1)
    guard = nl.join([
        '\t' + TRANSFER_MARKER,
        '\tif target and ChaosSeason and ChaosSeason.npcTransferBlocked and ChaosSeason.npcTransferBlocked(self, target.guid) then',
        '\t\treturn false',
        '\tend',
        ''])
    flag = nl + 'ChaosSeasonTransferPatched = true ' + TRANSFER_MARKER + nl
    return text[:m.end()] + guard + text[m.end():].rstrip('\r\n') + nl + flag, 'patched'


def patch_player(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    m = re.search(r'function Player:onMoveItem\(item, count, fromPosition, toPosition, fromCylinder, toCylinder\)[ \t]*\n',
                  text)
    if not m:
        return text, 'Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder) not found'
    return text[:m.end()] + HOOK + text[m.end():], 'patched'


def patch_events(text):
    """returns (new text, status)"""
    out, changed = text, False
    for method in ('onTradeRequest', 'onTradeAccept'):
        pat = re.compile(r'(<event class="Player" method="%s" enabled=")(\d)(" */>)' % method)
        m = pat.search(out)
        if not m:
            return text, 'Player %s not found in events.xml' % method
        if m.group(2) != '1':
            out = out[:m.start()] + m.group(1) + '1' + m.group(3) + out[m.end():]
            changed = True
    return out, 'patched' if changed else 'already'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    status = 0
    for rel, fn in (('events/events.xml', patch_events), ('events/scripts/player.lua', patch_player),
                    ('lib/core/player.lua', patch_lib_player)):
        path = os.path.join(data, rel)
        if not os.path.isfile(path):
            print('%s: not found' % path)
            status = 1
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = fn(text)
        if st not in ('patched', 'already'):
            print('%s: %s' % (rel, st))
            status = 1
            continue
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

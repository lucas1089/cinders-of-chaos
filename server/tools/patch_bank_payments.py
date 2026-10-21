#!/usr/bin/env python3
"""Every gold price of the base server is paid from the carried coins and then the bank (owner 2026-10-22: "todas as
lojas que usam gold aceitam o dinheiro diretamente do banco"; server/README.md "Gold payments: carried coins, then the
bank"). Every kill's coins go to the bank (autoloot.lua), so a price checked against the carried coins only was out of
reach for most players.

usage: python3 -I server/tools/patch_bank_payments.py DATA_DIR [--dry-run]

1. data/lib/lib.lua and data/npc/lib/npc.lua load data/lib/chaos_pay.lua at their end. It makes Player.getTotalMoney
   (carried + bank) and Player.removeTotalMoney (carried first, then the bank; all or nothing; says in the player's
   language what came from the bank) the Chaos ones. The base defines both twice, in data/lib/core/player.lua and again
   in data/npc/lib/npc.lua (loaded with the first NPC), so both files load it after their own definition. The stock NPC
   library (trade window, travel, blessings, spells, promotions, doPlayerBuyItemContainer) already pays with
   removeTotalMoney and checks getTotalMoney, and the engine sends carried + bank as the money of the trade window.

2. The scripts that check and take the carried coins only (about 75 NPC scripts: boat captains, carpets, horse
   renters, ferrymen, the outfit and addon sellers, table shops with their own trade code, the blessing priest, the
   crafting table, ...) in data/npc/scripts, actions, talkactions, movements, creaturescripts, globalevents, scripts
   (not scripts/chaos) and data/spells:
     X:removeMoney(...)          -> X:removeTotalMoney(...)
     doPlayerRemoveMoney(c, ...) -> ChaosPay.payCid(c, ...)
     X:getMoney()                -> X:getTotalMoney()         (not in a bank script)
     getPlayerMoney(c)           -> ChaosPay.totalCid(c)       (not in a bank script)
   A bank script (one that deposits, withdraws or transfers: the bankers, the coin changers) keeps
   its getMoney: there it means the coins a deposit takes. Its other payments (a wagon ticket) are rewritten. A
   removeMoney with a bank balance change in the next lines (a deposit written in Lua) is left alone, and so is a
   commented line. Refunds and payouts (addMoney) are unchanged.

Idempotent: a rewritten call no longer matches, the lib lines carry a marker. Reports every file it changed.
"""
import os
import re
import sys

MARK = '-- Chaos: gold payments from carried coins, then the bank (patch_bank_payments.py)'
LOAD = "dofile('data/lib/chaos_pay.lua')"

SCAN_DIRS = ('npc/scripts', 'actions', 'talkactions', 'movements', 'creaturescripts', 'globalevents', 'scripts',
             'spells')
SKIP_DIRS = ('scripts/chaos', 'spells/chaos')

BANK_RE = re.compile(r'depositMoney|withdrawMoney|transferMoneyTo|DepositMoney|WithdrawMoney|TransferMoney|'
                     r'PlayerBalance|SetBalance|getTrueOnHand')
NEAR_BANK_RE = re.compile(r'BankBalance|Balance\(|depositMoney|DepositMoney')

REMOVE_RE = re.compile(r'(\b[A-Za-z_][\w.]*(?:\([^()\n]*\))?):removeMoney\(')
DO_REMOVE_RE = re.compile(r'\bdoPlayerRemoveMoney\(')
GET_RE = re.compile(r'(\b[A-Za-z_][\w.]*(?:\([^()\n]*\))?):getMoney\(\s*\)')
DO_GET_RE = re.compile(r'\bgetPlayerMoney\(')


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def is_bank(text):
    return BANK_RE.search(text) is not None


def _code(line):
    """the part of a line before a comment (a `--` outside a string, good enough for these scripts)"""
    i = line.find('--')
    return line if i < 0 else line[:i]


def rewrite(text):
    """-> (new text, number of calls changed). Pure."""
    bank = is_bank(text)
    lines = text.split('\n')
    n = 0
    for i, line in enumerate(lines):
        code = _code(line)
        rest = line[len(code):]
        if 'Money' not in code:
            continue
        new = code
        if REMOVE_RE.search(new) or DO_REMOVE_RE.search(new):
            window = '\n'.join(_code(x) for x in lines[i:i + 4])
            if not NEAR_BANK_RE.search(window):
                new, a = REMOVE_RE.subn(lambda m: m.group(1) + ':removeTotalMoney(', new)
                new, b = DO_REMOVE_RE.subn('ChaosPay.payCid(', new)
                n += a + b
        if not bank:
            new, c = GET_RE.subn(lambda m: m.group(1) + ':getTotalMoney()', new)
            new, d = DO_GET_RE.subn('ChaosPay.totalCid(', new)
            n += c + d
        lines[i] = new + rest
    return '\n'.join(lines), n


def patch_loader(text):
    """lib.lua / npc.lua: load chaos_pay.lua at the end. -> (new text, status)"""
    if MARK in text:
        return text, 'already'
    sep = '' if text.endswith('\n') or text == '' else '\n'
    return text + sep + MARK + '\n' + LOAD + '\n', 'patched'


def scripts(data):
    for sub in SCAN_DIRS:
        root = os.path.join(data, sub)
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, files in os.walk(root):
            rel = os.path.relpath(dirpath, data).replace(os.sep, '/')
            dirnames[:] = sorted(d for d in dirnames
                                 if not any((rel + '/' + d) == s or (rel + '/' + d).startswith(s + '/')
                                            for s in SKIP_DIRS))
            for name in sorted(files):
                if name.endswith('.lua'):
                    yield os.path.join(dirpath, name)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    dry = '--dry-run' in argv
    data = args[0]
    ok = True
    for rel in ('lib/lib.lua', 'npc/lib/npc.lua'):
        path = os.path.join(data, rel)
        if not os.path.isfile(path):
            print('%s: missing' % path)
            ok = False
            continue
        new, status = patch_loader(read(path))
        if status == 'patched' and not dry:
            write(path, new)
        print('%s: %s' % (rel, status))
    if not os.path.isfile(os.path.join(data, 'lib', 'chaos_pay.lua')):
        print('lib/chaos_pay.lua: missing (the files step copies it)')
        ok = False
    files = calls = 0
    for path in scripts(data):
        text = read(path)
        if 'Money' not in text:
            continue
        new, n = rewrite(text)
        if n and new != text:
            files += 1
            calls += n
            if not dry:
                write(path, new)
            print('%s: %d call(s) pay from the bank too' % (os.path.relpath(path, data), n))
    print('%d script(s), %d call(s) changed%s' % (files, calls, ' (dry run)' if dry else ''))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Tests of tools/patch_bank_payments.py: the coin-only charges of the base scripts pay from the bank too, bank
scripts keep their deposit counts, the lib files load chaos_pay.lua once, a second run changes nothing."""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_bank_payments as P  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


BOAT = (
    'local function creatureSayCallback(cid, type, msg)\n'
    '\tlocal player = Player(cid)\n'
    '\tif player:getMoney() >= 111 then\n'
    '\t\tplayer:removeMoney(111)\n'
    '\tend\n'
    '\tif not Player(cid):removeMoney(50) then return end\n'
    '\t-- player:removeMoney(1) stays: a comment\n'
    '\tif getPlayerMoney(cid) >= 5 then doPlayerRemoveMoney(cid, 5) end\n'
    'end\n'
)
new, n = P.rewrite(BOAT)
check(n == 5, 'five calls: %d' % n)
check('player:getTotalMoney() >= 111' in new, 'the check counts the bank')
check('player:removeTotalMoney(111)' in new, 'the charge takes the bank')
check('Player(cid):removeTotalMoney(50)' in new, 'a call result as receiver')
check('-- player:removeMoney(1) stays' in new, 'a comment is left alone')
check('ChaosPay.totalCid(cid) >= 5 then ChaosPay.payCid(cid, 5)' in new, 'old style calls')
check(P.rewrite(new) == (new, 0), 'idempotent')

BANK = (
    'if msgcontains(msg, "deposit all") then\n'
    '\tcount[cid] = player:getMoney()\n'
    '\tplayer:depositMoney(count[cid])\n'
    'elseif msgcontains(msg, "ticket") then\n'
    '\tif player:removeMoney(250) then\n'
    '\t\tplayer:setStorageValue(1, 1)\n'
    '\tend\n'
    'end\n'
)
new, n = P.rewrite(BANK)
check('count[cid] = player:getMoney()' in new, 'a bank script keeps its deposit count')
check('player:removeTotalMoney(250)' in new, 'its wagon ticket pays from the bank too')
check(n == 1, 'one call: %d' % n)

LUADEPOSIT = (
    'if player:removeMoney(amount) then\n'
    '\tplayer:setBankBalance(player:getBankBalance() + amount)\n'
    'end\n'
)
new, n = P.rewrite(LUADEPOSIT)
check(n == 0 and new == LUADEPOSIT, 'a deposit written in Lua is left alone')

text, st = P.patch_loader('dofile("x")\n')
check(st == 'patched' and text.endswith(P.LOAD + '\n') and P.MARK in text, 'loader added')
check(P.patch_loader(text) == (text, 'already'), 'loader once')

root = tempfile.mkdtemp(prefix='bankpay_test_')
try:
    for d in ('lib', 'npc/lib', 'npc/scripts', 'scripts/chaos', 'scripts/customs'):
        os.makedirs(os.path.join(root, d))
    open(os.path.join(root, 'lib', 'lib.lua'), 'w').write("dofile('data/lib/core/core.lua')\n")
    open(os.path.join(root, 'lib', 'chaos_pay.lua'), 'w').write('-- x\n')
    open(os.path.join(root, 'npc', 'lib', 'npc.lua'), 'w').write('function Player.removeTotalMoney() end')
    open(os.path.join(root, 'npc', 'scripts', 'Boat.lua'), 'w').write(BOAT)
    open(os.path.join(root, 'scripts', 'chaos', 'bank.lua'), 'w').write(BOAT)
    open(os.path.join(root, 'scripts', 'customs', 'craft.lua'), 'w').write(BOAT)
    check(P.main([root, '--dry-run']) == 0, 'dry run ok')
    check(open(os.path.join(root, 'npc', 'scripts', 'Boat.lua')).read() == BOAT, 'dry run writes nothing')
    check(P.main([root]) == 0, 'run ok')
    check('removeTotalMoney(111)' in open(os.path.join(root, 'npc', 'scripts', 'Boat.lua')).read(), 'NPC script')
    check('removeTotalMoney(111)' in open(os.path.join(root, 'scripts', 'customs', 'craft.lua')).read(), 'custom script')
    check(open(os.path.join(root, 'scripts', 'chaos', 'bank.lua')).read() == BOAT, 'scripts/chaos is ours: untouched')
    npc = open(os.path.join(root, 'npc', 'lib', 'npc.lua')).read()
    check(npc.endswith(P.LOAD + '\n') and npc.count(P.MARK) == 1, 'npc.lua loads it after its own definition')
    snap = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            snap[os.path.join(dp, f)] = open(os.path.join(dp, f)).read()
    P.main([root])
    check(all(open(p).read() == t for p, t in snap.items()), 'a second run changes nothing')
finally:
    shutil.rmtree(root)

print('patch_bank_payments_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
sys.exit(1 if failed else 0)

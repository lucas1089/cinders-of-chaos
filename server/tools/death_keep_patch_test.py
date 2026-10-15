#!/usr/bin/env python3
"""Guard for patch_base_events.py step 15: store-bound items never drop on death.

Live test 2026-10-14: a death on shallow water left no corpse and the Loot Bag and the Everfull Ration were lost. The
stock death script data/creaturescripts/scripts/droploot.lua (not in this repository; its text is below, as the base
ships it) moves each dropped slot item into the corpse and removes it when that fails. This test patches a copy, checks
the result is idempotent and refuses an unknown text, then runs the stock and the patched script with luajit (or
lua5.3) on a tiny mocked engine with data/scripts/chaos/death_keep.lua: a red-skulled character dies without a corpse.
Stock: the Loot Bag and the ration are gone. Patched: both are in the inbox, the rest of the backpack still dropped.

Run: python3 -I server/tools/death_keep_patch_test.py (standard library; luajit or lua5.3 for the run part)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import patch_base_events as P  # noqa: E402

STOCK = (
    "function onDeath(player, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)\n"
    "\tif player:hasFlag(PlayerFlag_NotGenerateLoot) or player:getVocation():getId() == VOCATION_NONE then\n"
    "\t\treturn true\n"
    "\tend\n"
    "\n"
    "\tlocal amulet = player:getSlotItem(CONST_SLOT_NECKLACE)\n"
    "\tlocal isRedOrBlack = table.contains({SKULL_RED, SKULL_BLACK}, player:getSkull())\n"
    "\tif amulet and amulet.itemid == ITEM_AMULETOFLOSS and not isRedOrBlack then\n"
    "\t\tplayer:removeItem(ITEM_AMULETOFLOSS, 1, -1, false)\n"
    "\telse\n"
    "\t\tfor i = CONST_SLOT_HEAD, CONST_SLOT_AMMO do\n"
    "\t\t\tlocal item = player:getSlotItem(i)\n"
    "\t\t\tlocal lossPercent = player:getLossPercent()\n"
    "\t\t\tif item then\n"
    "\t\t\t\tif isRedOrBlack or math.random(item:isContainer() and 100 or 1000) <= lossPercent then\n"
    "\t\t\t\t\tif (isRedOrBlack or lossPercent ~= 0) and not item:moveTo(corpse) then\n"
    "\t\t\t\t\t\titem:remove()\n"
    "\t\t\t\t\tend\n"
    "\t\t\t\tend\n"
    "\t\t\tend\n"
    "\t\tend\n"
    "\tend\n"
    "\n"
    "\tif not player:getSlotItem(CONST_SLOT_BACKPACK) then\n"
    "\t\tplayer:addItem(ITEM_BAG, 1, false, CONST_SLOT_BACKPACK)\n"
    "\tend\n"
    "\treturn true\n"
    "end\n")

HARNESS = r'''
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_AMMO = 1, 2, 3, 10
SKULL_RED, SKULL_BLACK, VOCATION_NONE, ITEM_AMULETOFLOSS, ITEM_BAG, MESSAGE_EVENT_ADVANCE = 4, 5, 0, 2173, 1987, 19
PlayerFlag_NotGenerateLoot = 1
function table.contains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CreatureEvent() return {type = function() end, register = function() end} end
local Item = {}
Item.__index = Item
local function newItem(id, name, attrs, kids)
  local it = setmetatable({id = id, name = name, attrs = attrs or {}, kids = {}}, Item)
  for _, k in ipairs(kids or {}) do k.parent = it; it.kids[#it.kids + 1] = k end
  return it
end
function Item:getId() return self.id end
function Item:getName() return self.name end
function Item:isContainer() return self.id == 1988 or self.id == 32081 or self.id == 1990 end
function Item:getItems() local o = {} for i, k in ipairs(self.kids) do o[i] = k end return o end
function Item:getCustomAttribute(k) return self.attrs[k] end
function Item:setCustomAttribute(k, v) self.attrs[k] = v end
function Item:removeCustomAttribute(k) self.attrs[k] = nil end
local function detach(it)
  local p = it.parent
  if p and p.kids then for i, k in ipairs(p.kids) do if k == it then table.remove(p.kids, i) break end end end
  if p and p.slots then for s, k in pairs(p.slots) do if k == it then p.slots[s] = nil end end end
  it.parent = nil
end
function Item:remove() detach(self); self.removed = true end
function Item:moveTo(dest) if not dest then return nil end detach(self); self.parent = dest; dest.kids[#dest.kids + 1] = self; return true end
local function gone(it) while it do if it.removed then return true end it = it.parent end return false end
local inbox = newItem(1990, "inbox")
local bag = newItem(32081, "loot bag", {chaos_storebound = 1}, {newItem(2148, "gold coin")})
local food = newItem(32084, "everfull ration", {chaos_storebound = 1})
local sword = newItem(2400, "sword")
local player = {slots = {[CONST_SLOT_BACKPACK] = newItem(1988, "backpack", {}, {sword, bag, food})}}
player.slots[CONST_SLOT_BACKPACK].parent = player
function player:hasFlag() return false end
function player:getVocation() return {getId = function() return 1 end} end
function player:getSlotItem(s) return self.slots[s] end
function player:getSkull() return SKULL_RED end
function player:getLossPercent() return 100 end
function player:getInbox() return inbox end
function player:getName() return "Tester" end
function player:addItem() self.slots[CONST_SLOT_BACKPACK] = newItem(1988, "bag") end
if KEEP then dofile("data/scripts/chaos/death_keep.lua") end
dofile(SCRIPT)
onDeath(player, nil)
local kept = (not gone(bag) and bag.parent == inbox and 1 or 0) + (not gone(food) and food.parent == inbox and 1 or 0)
print(string.format("kept=%d sword=%s", kept, gone(sword) and "gone" or "here"))
'''


def lua():
    for name in ('luajit', 'lua5.3', 'lua'):
        path = shutil.which(name)
        if path:
            return path
    return None


def run(interp, script, keep):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'droploot.lua')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(script)
        code = 'SCRIPT = %r\nKEEP = %s\n' % (path, 'true' if keep else 'false') + HARNESS
        out = subprocess.run([interp, '-e', code], cwd=SERVER, capture_output=True, text=True, timeout=60)
        if out.returncode != 0:
            raise AssertionError('lua failed: ' + out.stderr)
        return out.stdout.strip().splitlines()[-1]


def main():
    new, status = P.patch_death_keep(STOCK)
    assert status == 'patched', status
    assert P.DEATHKEEP_MARKER in new
    assert 'ChaosDeathKeep.beforeDrop(player, item, corpse)' in new
    again, status2 = P.patch_death_keep(new)
    assert status2 == 'already' and again == new, 'idempotent'
    _, bad = P.patch_death_keep(STOCK.replace('item:moveTo(corpse)', 'item:moveTo(somewhere)'))
    assert bad.startswith('unexpected'), bad
    crlf, status3 = P.patch_death_keep(STOCK.replace('\n', '\r\n'))
    assert status3 == 'patched' and '\r\n' + '\t' * 5 + 'if' in crlf, 'CRLF kept'

    interp = lua()
    if not interp:
        print('death_keep_patch_test: patch checks passed (no lua interpreter: run part skipped)')
        return 0
    assert run(interp, STOCK, False) == 'kept=0 sword=gone', 'stock: the store items are lost on water (the bug)'
    assert run(interp, new, False) == 'kept=0 sword=gone', 'patched without death_keep.lua: the stock rule'
    got = run(interp, new, True)
    assert got == 'kept=2 sword=gone', 'patched: both store items kept, the loot still drops: ' + got
    print('death_keep_patch_test: all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())

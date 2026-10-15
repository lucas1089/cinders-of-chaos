#!/usr/bin/env python3
"""Guard for patch_base_events.py steps 18 and 19: gentle deaths (data/scripts/chaos/gentledeath.lua).

Patches copies of the stock Player:onLoseExperience (as TFS 1.4 ships it, with its EventCallback dispatch), a player.lua
without the function, and events.xml (missing entry, entry off, entry on), checks the results are idempotent and an
unknown signature is refused, then runs the patched player.lua with luajit (or lua5.3) on a tiny mock with
gentledeath.lua: a level 10 character loses nothing, a level 400 character the first death of the day half and the
second the full loss, and without the script the stock loss is kept. Step 19: the stock droploot.lua (the copy of
death_keep_patch_test.py) patched by steps 15 and 19 keeps every item and the amulet of loss of a character without a
skull, and drops as before with a red skull.

Run: python3 -I server/tools/gentle_death_patch_test.py (standard library; luajit or lua5.3 for the run part)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import patch_base_events as P  # noqa: E402
import death_keep_patch_test as DKT  # noqa: E402

STOCK = (
    "function Player:onGainExperience(source, exp, rawExp)\n"
    "\treturn exp\n"
    "end\n"
    "\n"
    "function Player:onLoseExperience(exp)\n"
    "\tif hasEventCallback(EVENT_CALLBACK_ONLOSEEXPERIENCE) then\n"
    "\t\treturn EventCallback(EVENT_CALLBACK_ONLOSEEXPERIENCE, self, exp)\n"
    "\tend\n"
    "\treturn exp\n"
    "end\n")

EVENTS_OFF = ('<?xml version="1.0" encoding="UTF-8"?>\n<events>\n'
              '\t<event class="Player" method="onLoseExperience" enabled="0" />\n'
              '\t<!-- Monster methods -->\n</events>\n')
EVENTS_NONE = '<?xml version="1.0" encoding="UTF-8"?>\n<events>\n\t<!-- Monster methods -->\n</events>\n'

HARNESS = r'''
MESSAGE_EVENT_ADVANCE = 19
local function ev() return {type = function() end, register = function() end} end
CreatureEvent, GlobalEvent, TalkAction = ev, ev, ev
function hasEventCallback() return false end
Player = {}
Player.__index = Player
local function player(level)
	return setmetatable({level = level, st = {}, said = {}}, Player)
end
function Player:getLevel() return self.level end
function Player:getSkull() return 0 end
function Player:getId() return 1 end
function Player:getStorageValue(k) return self.st[k] or -1 end
function Player:setStorageValue(k, v) self.st[k] = v end
function Player:sendTextMessage(t, m) self.said[#self.said + 1] = m end
dofile(PATCHED)
local low, high = player(10), player(400)
assert(Player.onLoseExperience(low, 1000) == 1000, "stock loss without the script")
dofile("data/scripts/chaos/gentledeath.lua")
assert(Player.onLoseExperience(low, 1000) == 0, "level 10 loses nothing")
local first = Player.onLoseExperience(high, 1000)
assert(first == 500, "first death of the day: half, got " .. tostring(first))
local second = Player.onLoseExperience(high, 1000)
assert(second == 1000, "second death: full, got " .. tostring(second))
assert(#high.said >= 1, "told")
print("run ok")
'''


DROP_HARNESS = r'''
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_AMMO = 1, 2, 3, 10
SKULL_NONE, SKULL_RED, SKULL_BLACK, VOCATION_NONE, ITEM_AMULETOFLOSS, ITEM_BAG, MESSAGE_EVENT_ADVANCE = 0, 4, 5, 0, 2173, 1987, 19
PlayerFlag_NotGenerateLoot = 1
function table.contains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CreatureEvent() return {type = function() end, register = function() end} end
function GlobalEvent() return {register = function() end} end
function TalkAction() return {register = function() end} end
local function item(id)
  local it = {id = id, itemid = id}
  function it:getId() return self.id end
  function it:isContainer() return self.id == 1988 end
  function it:getItems() return {} end
  function it:getCustomAttribute() return nil end
  function it:moveTo() self.dropped = true return true end
  function it:remove() self.removed = true end
  return it
end
local slots = {[CONST_SLOT_NECKLACE] = item(ITEM_AMULETOFLOSS), [CONST_SLOT_BACKPACK] = item(1988), [CONST_SLOT_HEAD] = item(2457)}
local player = {skull = SKULL}
function player:hasFlag() return false end
function player:getVocation() return {getId = function() return 1 end} end
function player:getSlotItem(s) return slots[s] end
function player:getSkull() return self.skull end
function player:getLossPercent() return 1000 end
function player:getLevel() return 400 end
function player:removeItem(id) slots[CONST_SLOT_NECKLACE].removed = true end
function player:addItem() end
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/gentledeath.lua")
dofile(SCRIPT)
onDeath(player, {})
local lost = 0
for _, it in pairs(slots) do if it.dropped or it.removed then lost = lost + 1 end end
print("lost=" .. lost)
'''


def check(cond, label):
    if not cond:
        print('FAIL ' + label)
        sys.exit(1)


def main():
    out, status = P.patch_lose_experience(STOCK)
    check(status == 'patched', 'stock patched')
    check(P.LOSE_MARKER in out and 'ChaosGentleDeath.onLoseExperience(self, exp)' in out, 'hook inserted')
    check(out.index(P.LOSE_MARKER) < out.index('hasEventCallback(EVENT_CALLBACK_ONLOSEEXPERIENCE)'), 'before the stock body')
    check(P.patch_lose_experience(out) == (out, 'already'), 'idempotent')
    bare, status = P.patch_lose_experience('function Player:onGainExperience(source, exp)\n\treturn exp\nend\n')
    check(status == 'patched' and 'function Player:onLoseExperience(exp)' in bare, 'missing function added')
    check(P.patch_lose_experience(bare)[1] == 'already', 'added function idempotent')
    check(P.patch_lose_experience('function Player:onLoseExperience(a, b)\nend\n')[1].startswith('unexpected'),
          'unknown signature refused')
    crlf, status = P.patch_lose_experience(STOCK.replace('\n', '\r\n'))
    check(status == 'patched' and '\r\n\tif ChaosGentleDeath' in crlf, 'CRLF kept')

    ev, status = P.patch_lose_event(EVENTS_OFF)
    check(status == 'patched' and 'method="onLoseExperience" enabled="1"' in ev, 'event turned on')
    check(P.patch_lose_event(ev)[1] == 'already', 'event idempotent')
    ev, status = P.patch_lose_event(EVENTS_NONE)
    check(status == 'patched' and ev.index('onLoseExperience') < ev.index('Monster methods'), 'event added')
    check(P.patch_lose_event('<x/>')[1].startswith('</events>'), 'bad events.xml refused')

    drop, status = P.patch_keep_all(DKT.STOCK)
    check(status == 'patched' and P.KEEPALL_MARKER in drop, 'droploot patched')
    check(drop.index(P.KEEPALL_MARKER) < drop.index('ITEM_AMULETOFLOSS'), 'before the amulet of loss')
    check(P.patch_keep_all(drop)[1] == 'already', 'droploot idempotent')
    check(P.patch_keep_all('function onDeath() end')[1].startswith('unexpected'), 'unknown droploot refused')
    both = P.patch_death_keep(drop)[0]
    check(P.DEATHKEEP_MARKER in both and P.KEEPALL_MARKER in both, 'steps 15 and 19 together')

    lua = shutil.which('luajit') or shutil.which('lua5.3')
    if not lua:
        print('gentle_death_patch_test: patch checks ok (no Lua interpreter for the run part)')
        return 0
    d = tempfile.mkdtemp()
    try:
        patched = os.path.join(d, 'player.lua')
        open(patched, 'w', encoding='utf-8').write(out)
        harness = os.path.join(d, 'harness.lua')
        open(harness, 'w', encoding='utf-8').write('PATCHED = %r\n' % patched + HARNESS)
        r = subprocess.run([lua, harness], cwd=SERVER, capture_output=True, text=True)
        check(r.returncode == 0 and 'run ok' in r.stdout, 'run: ' + r.stdout + r.stderr)
        dl = os.path.join(d, 'droploot.lua')
        open(dl, 'w', encoding='utf-8').write(both)
        for skull, want in (('0', 'lost=0'), ('4', 'lost=3')):
            h = os.path.join(d, 'drop.lua')
            open(h, 'w', encoding='utf-8').write('SCRIPT = %r\nSKULL = %s\n' % (dl, skull) + DROP_HARNESS)
            r = subprocess.run([lua, h], cwd=SERVER, capture_output=True, text=True)
            check(r.returncode == 0 and want in r.stdout, 'drop run skull ' + skull + ': ' + r.stdout + r.stderr)
    finally:
        shutil.rmtree(d)
    print('gentle_death_patch_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())

-- Run from the server/ folder: luajit tests/veyra_upgrade_test.lua (and lua5.3; CI runs both)
-- Veyra the Apothecary's Everfull upgrade task (O245, server/README.md "Potions", "Higher tiers"): the dialog of
-- data/npc/scripts/veyra_the_apothecary.lua on a mocked NPC library and engine. The swap itself is tested in
-- potions_test.lua; here: what she offers, the choice between the health and the spirit line, yes / no, the materials,
-- the lost flask, and that a word she does not know changes nothing.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then failures = failures + 1 print("FAIL " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")") end

RETURNVALUE_NOERROR, RETURNVALUE_NOTENOUGHROOM = 0, 4
CONST_SLOT_FIRST, CONST_SLOT_LAST, CONST_SLOT_BACKPACK = 1, 10, 3
MESSAGE_INFO_DESCR, MESSAGE_STATUS_SMALL = 22, 21
CALLBACK_MESSAGE_DEFAULT, CALLBACK_ONBUY = 1, 2
dofile("data/scripts/chaos/chaos_constants.lua")

local said, callbacks = {}, {}
KeywordHandler = {new = function() return {} end}
NpcHandler = {new = function()
	local h = {}
	function h:setCallback(kind, fn) callbacks[kind] = fn end
	function h:say(text) said[#said + 1] = text end
	function h:isFocused() return true end
	function h:addModule() end
	function h:onCreatureAppear() end
	function h:onCreatureDisappear() end
	function h:onCreatureSay() end
	function h:onThink() end
	return h
end}
NpcSystem = {parseParameters = function() end}
FocusModule = {new = function() return {} end}
ChaosNpcFocus = {hears = function() return true end}
ChaosI18n = {
	npcText = function(_, key, ...) return select("#", ...) > 0 and string.format(key, ...) or key end,
	npcMessages = function() end
}

local function mkItem(id, n, kids)
	local it = {id = id, count = n or 1, attrs = {}, kids = kids}
	function it:getId() return self.id end
	function it:isContainer() return self.kids ~= nil end
	function it:getItems() return self.kids or {} end
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:remove(c)
		if (c == nil or c >= self.count) and self.parent then
			for i, k in ipairs(self.parent.kids) do if k == self then table.remove(self.parent.kids, i) break end end
			self.parent = nil
		end
		return true
	end
	function it:addItemEx(item)
		if not self.kids then return RETURNVALUE_NOTENOUGHROOM end
		self.kids[#self.kids + 1] = item
		item.parent = self
		return RETURNVALUE_NOERROR
	end
	return it
end
Game = {createItem = function(id, n) return mkItem(id, n) end, getTowns = function() return {} end}
ItemType = function(id) return {getId = function() return id end} end

local player = {id = 1, st = {}, level = 100, money = 0, bank = 0}
player.bp, player.inbox = mkItem(1988, 1, {}), mkItem(14404, 1, {})
function player:getId() return self.id end
function player:getName() return "Tester" end
function player:getLevel() return self.level end
function player:getStorageValue(k) return self.st[k] or -1 end
function player:setStorageValue(k, v) self.st[k] = v end
function player:getSlotItem(slot) return slot == CONST_SLOT_BACKPACK and self.bp or nil end
function player:getInbox() return self.inbox end
function player:getDepotChest() return nil end
function player:addItemEx(item) return self.bp:addItemEx(item) end
function player:sendTextMessage() end
function player:getItemCount(id) local n = 0 for _, k in ipairs(self.bp.kids) do if k.id == id then n = n + k.count end end return n end
function player:removeItem(id, n)
	if self:getItemCount(id) < n then return false end
	local snapshot = {}
	for i, k in ipairs(self.bp.kids) do snapshot[i] = k end
	for _, k in ipairs(snapshot) do
		if k.id == id and n > 0 then
			local take = math.min(n, k.count)
			k.count, n = k.count - take, n - take
			if k.count == 0 then k:remove() end
		end
	end
	return true
end
function player:addItem(id, n) local it = mkItem(id, n) self.bp:addItemEx(it) return it end
function player:getBankBalance() return self.bank end
function player:setBankBalance(n) self.bank = n return true end
function player:getMoney() return self.money end
function player:removeMoney(n) if n > self.money then return false end self.money = self.money - n return true end
function player:removeTotalMoney(n)
	local hand = math.min(n, self.money)
	self.money, self.bank = self.money - hand, self.bank - (n - hand)
	return true
end
Player = function() return player end

dofile("data/npc/scripts/veyra_the_apothecary.lua")
local talk = callbacks[CALLBACK_MESSAGE_DEFAULT]
check(type(talk) == "function", "the talk callback")
local cfg = ChaosPotionsConfig
local function say(msg)
	said = {}
	talk(1, 1, msg)
	return said[#said]
end
local function hold(id) local it = mkItem(id) it.attrs.chaos_storebound, it.attrs.chaos_locked = 1, 2 player.bp:addItemEx(it) return it end
local function stock(id, n) player.bp:addItemEx(mkItem(id, n)) end

-- nothing to upgrade: no flask, a flask she cannot upgrade yet
player.level = 100
eq(say("upgrade"):find("I have no upgrade", 1, true) ~= nil, true, "no flask: nothing to offer")
local base = hold(32085)
player.level = 79
eq(say("upgrade"):find("level 80", 1, true) ~= nil, true, "level 79: the great tier is offered, with its level")
player.level = 100
-- two ways from the starting health flask at level 80: health or spirit
local r = say("I want an upgrade")
check(r:find("{health}", 1, true) ~= nil and r:find("{spirit}", 1, true) ~= nil, "two lines offered: " .. tostring(r))
eq(say("yes"), nil, "yes alone does not pick one of two (she waits)")
check(player.bp.kids[1] == base, "nothing changed")
r = say("spirit")
check(r:find("Bring me 40 great spirit potions", 1, true) ~= nil, "no materials: she asks for them: " .. tostring(r))
eq(player.st[7102510], nil, "no flag, nothing taken")
eq(base.parent, player.bp, "the flask is still there")
-- with the materials: pick the spirit line, the swap is done
say("upgrade") stock(8472, 40)
r = say("spirit")
check(r:find("Done", 1, true) ~= nil, "done: " .. tostring(r))
eq(player.bp.kids[1].id ~= nil and player:getItemCount(32263), 1, "the great spirit flask is in the backpack")
eq(player:getItemCount(32085), 0, "the starting flask is gone") eq(player:getItemCount(8472), 0, "the 40 potions are gone")
eq(player.bp.kids[#player.bp.kids].attrs.chaos_locked, 2, "its lock value")
eq(player.st[cfg.storage.upgradeBase + 2], 1, "the great spirit flag (3rd tier)")
eq(say("yes"), nil, "yes with nothing pending does nothing")
eq(player:getItemCount(32263), 1, "still one")

-- no: cancels; the next tier at level 130 needs ultimate spirit potions
player.level = 130
r = say("upgrade")
check(r:find("ultimate spirit", 1, true) ~= nil and r:find("level 130", 1, true) ~= nil, "the next tier is offered: " .. tostring(r))
eq(say("no"), "As you wish.", "no cancels")
eq(say("yes"), nil, "and yes after no does nothing")
eq(player:getItemCount(32263), 1, "the flask is unchanged")
-- a word that contains yes / no is not an answer
say("upgrade") stock(26030, 40)
r = say("I do not know")
check(r == nil, "'know' is not 'no'")
eq(say("yesterday"), nil, "'yesterday' is not 'yes'")
eq(player:getItemCount(32263), 1, "unchanged")
r = say("yes")
check(r:find("Done", 1, true) ~= nil, "yes: " .. tostring(r))
eq(player:getItemCount(32266), 1, "ultimate spirit")

-- a lost flask: she gives back the highest tier of the slot for gold, once
for i = #player.bp.kids, 1, -1 do if player.bp.kids[i].id == 32266 then player.bp.kids[i]:remove() end end
eq(player:getItemCount(32266), 0, "lost")
check(say("I lost my flask"):find("32") == nil and say("lost"):find("ultimate spirit", 1, true) ~= nil, "she offers the ultimate spirit one back")
r = say("yes")
check(r == "You do not have enough money.", "too poor: " .. tostring(r))
say("lost") player.money = cfg.everfull[8].price + 5
r = say("yes")
check(r:find("Here is your", 1, true) ~= nil, "given back: " .. tostring(r))
eq(player:getItemCount(32266), 1, "the flask is back") eq(player.money, 5, "for its price")
eq(say("lost"), "You have lost nothing I can give back.", "not twice")

print(string.format("veyra_upgrade_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end

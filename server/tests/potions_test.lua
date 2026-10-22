-- Run from the server/ folder: luajit tests/potions_test.lua (and lua5.3; CI runs both)
-- Potions (server/README.md "Potions"): potions_core.lua and potions_config.lua; potions.lua and
-- data/lib/chaos_potions.lua on a mocked engine (an Everfull potion heals, is never used up, leaves no flask and keeps
-- the potion exhaust; the kit / login grant; a potion seller's replacement); the stock potions.lua as
-- tools/install_potions.py patches it (no flask, a higher tier still used up, the exhaust unchanged).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/potions_core.lua")
local cfg = dofile("data/scripts/chaos/potions_config.lua")
local K = ChaosPotionsCore

-- ---------------------------------------------------------------- config
local HEALTH, MANA = cfg.everfull[1], cfg.everfull[2]
eq(HEALTH.sourceId, 7618, "the first health potion (level 1) is the Everfull one")
eq(MANA.sourceId, 7620, "the first mana potion (level 1) is the Everfull one")
eq(#cfg.everfull, 2, "no spirit potion: the first one is the great spirit potion (level 80)")
check(HEALTH.id > 32084 and HEALTH.id <= 32090 and MANA.id > 32084 and MANA.id <= 32090,
	"server ids in the free range after the Everfull Ration, before the faction tokens")
check(HEALTH.id ~= MANA.id, "two ids")
check(HEALTH.description:find("^Never runs out") ~= nil and MANA.description:find("^Never runs out") ~= nil,
	"the descriptions say so")
check(HEALTH.price > 0 and HEALTH.price <= 200 and MANA.price > 0 and MANA.price <= 200, "a cheap replacement")
check(cfg.storage.granted >= 7102480 and cfg.storage.granted <= 7102489, "storage in its block")
eq(cfg.attr.storebound, "chaos_storebound", "store-bound like the Everfull Ration")
eq(cfg.attr.lock, "chaos_locked", "locked: no NPC buys it (engine patch 0009)")
eq(#cfg.flasks, 3, "the three flasks")

-- ---------------------------------------------------------------- core
local r = K.drink(cfg, {id = HEALTH.id, target = "self"})
eq(r.ok, true, "drinks")
eq(r.consume, false, "never used up")
eq(r.flask, nil, "no flask")
eq(r.health, HEALTH.health, "the health roll")
eq(r.mana, nil, "no mana from the health potion")
r = K.drink(cfg, {id = MANA.id, target = "player"})
eq(r.ok and r.mana == MANA.mana, true, "mana potion on another player")
r = K.drink(cfg, {id = HEALTH.id, target = "self", exhausted = true})
eq(r.why, "exhausted", "the exhaust still applies")
eq(K.drink(cfg, {id = HEALTH.id, target = "creature"}).why, "target", "not on a monster")
eq(K.drink(cfg, {id = 7591, target = "self"}).why, "unknown", "a stock potion is not Everfull")
eq(K.everfull(cfg, 7618), nil, "the stock health potion stays a consumable")
check(K.isFlask(cfg, 7636) and K.isFlask(cfg, 7634) and not K.isFlask(cfg, 7618), "flask ids")

eq(K.npcBuy(cfg, {id = HEALTH.id, owned = false, money = 1000}).price, HEALTH.price, "a replacement")
eq(K.npcBuy(cfg, {id = HEALTH.id, owned = true, money = 1000}).why, "owned", "one per character")
eq(K.npcBuy(cfg, {id = HEALTH.id, owned = false, money = HEALTH.price - 1}).why, "money", "money")
eq(K.npcBuy(cfg, {id = 7618, money = 1000}).why, "unknown", "not an Everfull id")

eq(K.grantDue(cfg, {granted = false, lastLogin = 0}), false, "brand new: the starter kit gives them")
eq(K.grantDue(cfg, {granted = false, lastLogin = 1700000000}), true, "an older character: once at login")
eq(K.grantDue(cfg, {granted = true, lastLogin = 1700000000}), false, "only once")

-- ---------------------------------------------------------------- potions.lua and the lib on a mocked engine
MESSAGE_EVENT_ADVANCE, MESSAGE_STATUS_SMALL, MESSAGE_INFO_DESCR, TALKTYPE_MONSTER_SAY = 19, 21, 22, 36
RETURNVALUE_NOERROR, RETURNVALUE_NOTENOUGHROOM, RETURNVALUE_YOUAREEXHAUSTED = 0, 4, 66
CONST_SLOT_FIRST, CONST_SLOT_LAST, CONST_SLOT_BACKPACK = 1, 10, 3
CONDITION_EXHAUST_HEAL, CONDITION_PARAM_TICKS, COMBAT_HEALING, COMBAT_MANADRAIN = 0x8000, 1, 128, 64
dofile("data/scripts/chaos/chaos_constants.lua")
local registered, actions = {}, {}
local installed = true
ItemType = function(id) return {getId = function() return installed and id or 0 end} end
local function event(name)
	local e = {name = name}
	function e:register() registered[name or "action"] = self end
	function e:type() end
	function e:id(id) actions[id] = self end
	return e
end
CreatureEvent, GlobalEvent = event, event
Action = function() return event(nil) end
local exhaustTicks
Condition = function(kind)
	local c = {kind = kind}
	function c:setParameter(k, v) if k == CONDITION_PARAM_TICKS then exhaustTicks = v end end
	return c
end
configKeys = {EX_ACTIONS_DELAY_INTERVAL = 1}
configManager = {getNumber = function() return 1000 end}

local function mkItem(id, count, kids)
	local it = {id = id, count = count or 1, attrs = {}, kids = kids, removed = 0}
	function it:getId() return self.id end
	function it:isContainer() return self.kids ~= nil end
	function it:getItems() return self.kids or {} end
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:remove(n) self.removed = self.removed + (n or self.count) return true end
	function it:addItemEx(item)
		if not self.kids or #self.kids >= (self.cap or 20) then return RETURNVALUE_NOTENOUGHROOM end
		self.kids[#self.kids + 1] = item
		return RETURNVALUE_NOERROR
	end
	return it
end
local created = {}
Game = {
	createItem = function(id, n) local it = mkItem(id, n) created[#created + 1] = it return it end,
	getTowns = function() return {} end,
	getReturnMessage = function() return "You are exhausted." end
}
local heals = {}
function doTargetCombat(source, target, kind, a, b)
	heals[#heals + 1] = {source = source, target = target, kind = kind, a = a, b = b}
	return true
end

local players = {}
local function mkPlayer(id, lastLogin)
	local p = {id = id, st = {}, msgs = {}, said = {}, conds = {}, money = 0, bank = 0, last = lastLogin or 1700000000}
	p.bp = mkItem(1988, 1, {})
	p.inbox = mkItem(14404, 1, {})
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:isCreature() return true end
	function p:isPlayer() return true end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:getLastLoginSaved() return self.last end
	function p:getMaxHealth() return 1000 end
	function p:getMaxMana() return 2000 end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:say(text) self.said[#self.said + 1] = text end
	function p:getCondition(kind) return self.conds[kind] end
	function p:addCondition(c) self.conds[c.kind] = c end
	function p:getSlotItem(slot) return slot == CONST_SLOT_BACKPACK and self.bp or nil end
	function p:getInbox() return self.inbox end
	function p:getDepotChest() return nil end
	function p:addItemEx(item) return self.bp:addItemEx(item) end
	function p:getMoney() return self.money end
	function p:getBankBalance() return self.bank end
	function p:removeMoney(n)
		if n > self.money then return false end
		self.money = self.money - n
		return true
	end
	function p:setBankBalance(n) self.bank = n return true end
	function p:removeTotalMoney(n)
		local fromHand = math.min(n, self.money)
		self.money, self.bank = self.money - fromHand, self.bank - (n - fromHand)
		return true
	end
	players[id] = p
	return p
end
Player = function(cid) return players[cid] end

dofile("data/scripts/chaos/potions.lua")
local PT = ChaosPotions
local drink = actions[HEALTH.id]
check(drink ~= nil and actions[MANA.id] == drink, "one action for both Everfull ids")
eq(actions[7618], nil, "the stock potions keep the base script")
eq(exhaustTicks, nil, "no CONDITION_EXHAUST_HEAL is built any more")
check(registered.ChaosPotionsLogin ~= nil, "login grant registered")

-- drinking: healed, not used up, no flask, exhaust set; a second drink while exhausted is refused
local ann = mkPlayer(1)
local pot = mkItem(HEALTH.id)
heals, created = {}, {}
eq(drink.onUse(ann, pot, {}, ann, {}, true), true, "drinks")
eq(#heals, 1, "one heal")
eq(heals[1].kind, COMBAT_HEALING, "healing")
check(heals[1].a == heals[1].b and heals[1].a >= 155 and heals[1].a <= 205,
	"the health potion's roll 125-175 + 3% of 1,000 health")
eq(heals[1].target, ann, "on the drinker")
eq(pot.removed, 0, "the Everfull potion is not consumed")
eq(#created, 0, "no flask")
eq(#ann.bp.kids, 0, "nothing new in the backpack")
check(ann.conds[CONDITION_EXHAUST_HEAL] == nil, "no shared exhaust condition")
eq(ann.said[#ann.said], "Aaaah...", "the stock sound")
eq(drink.onUse(ann, pot, {}, ann, {}, true), true, "exhausted: handled")
eq(#heals, 1, "no second heal while exhausted")
eq(ann.msgs[#ann.msgs], "You are exhausted.", "the exhaust message")
-- the mana potion has its own wait: right after the health potion it works
local manaPot = mkItem(MANA.id)
local bob = mkPlayer(2)
drink.onUse(ann, manaPot, {}, bob, {}, false)
eq(heals[2].kind, COMBAT_MANADRAIN, "mana")
eq(heals[2].target, bob, "on another player")
eq(manaPot.removed, 0, "the mana one is not consumed either")
ann.conds = {}
local monster = {isCreature = function() return true end, isPlayer = function() return false end}
eq(drink.onUse(ann, pot, {}, monster, {}, false), false, "not on a monster")
eq(#heals, 2, "no heal on a monster")

-- the starter kit and the login grant: one of each, store-bound and locked, once
local cara = mkPlayer(3)
local kitBag = mkItem(1988, 1, {})
eq(PT.giveAll(cara, kitBag), 2, "the kit: both Everfull potions")
eq(#kitBag.kids, 2, "into the kit backpack")
eq(kitBag.kids[1].attrs.chaos_storebound, 1, "store-bound")
eq(kitBag.kids[1].attrs.chaos_locked, cfg.bindLock, "locked with the bind value")
check(cfg.bindLock ~= 0 and cfg.bindLock ~= 1, "bound for every lock check (not 0), not the client's grey player lock (1)")
-- a potion given before 2026-10-16 (lock 1: drawn as a dark flask) gets the bind value at the next login
local gus = mkPlayer(7)
local oldPot = mkItem(HEALTH.id, 1)
oldPot.attrs.chaos_locked, oldPot.attrs.chaos_storebound = 1, 1
local sent = 0
function oldPot:sendUpdate() sent = sent + 1 end
gus.bp.kids[1] = oldPot
gus.bp.kids[2] = mkItem(7618, 5)
eq(PT.rebind(gus), 1, "one old Everfull potion rebound")
eq(oldPot.attrs.chaos_locked, cfg.bindLock, "its lock value") eq(sent, 1, "sent again to the client")
eq(gus.bp.kids[2].attrs.chaos_locked, nil, "stock potions untouched")
eq(PT.rebind(gus), 0, "idempotent")
check(K.needsRebind(cfg, 1) and not K.needsRebind(cfg, cfg.bindLock), "needsRebind")
eq(cara.st[cfg.storage.granted], 1, "flag set")
cara.bp.kids[1] = kitBag
eq(PT.giveAll(cara), 0, "never a second one while it has them")
eq(registered.ChaosPotionsLogin.onLogin(cara), true, "login")
eq(#cara.bp.kids, 1, "the login grant gives nothing to a kit character")
local dan = mkPlayer(4)
registered.ChaosPotionsLogin.onLogin(dan)
eq(#dan.bp.kids, 2, "an older character gets both at login")
eq(dan.st[cfg.storage.granted], 1, "once")
dan.bp.kids = {}
registered.ChaosPotionsLogin.onLogin(dan)
eq(#dan.bp.kids, 0, "not again (a lost one is bought from a potion seller)")
local eve = mkPlayer(5, 0)
registered.ChaosPotionsLogin.onLogin(eve)
eq(#eve.bp.kids, 0, "a brand-new character waits for its kit")
installed = false
local fay = mkPlayer(6)
eq(PT.giveAll(fay), 0, "not installed: nothing")
installed = true

-- a potion seller's replacement (ShopModule hook): one copy, paid, refused while owned or too poor
dan.money, dan.bank = 50, 100
eq(PT.npcBuy(dan.id, HEALTH.id), true, "bought")
eq(#dan.bp.kids, 1, "one copy")
eq(dan.bp.kids[1].count, 1, "count 1 whatever amount was asked")
eq(dan.bp.kids[1].attrs.chaos_storebound, 1, "the bought copy is store-bound too")
eq(dan.money + dan.bank, 150 - HEALTH.price, "paid, the bank too")
eq(PT.npcBuy(dan.id, HEALTH.id), false, "a second one refused")
eq(dan.msgs[#dan.msgs], "You already have one. It never runs out.", "told why")
eq(PT.npcBuy(dan.id, MANA.id), false, "too poor for the mana one")
eq(#dan.bp.kids, 1, "nothing given")
eq(PT.npcBuy(999, MANA.id), false, "no such player")

-- ---------------------------------------------------------------- the stock potions.lua, patched by install_potions.py
-- condensed from the stock script: the exhaust, a potion of each tier with its flask, the stock onUse
local STOCK = table.concat({
	"local exhaust = Condition(CONDITION_EXHAUST_HEAL)",
	"exhaust:setParameter(CONDITION_PARAM_TICKS, (configManager.getNumber(configKeys.EX_ACTIONS_DELAY_INTERVAL) - 100))",
	"local potions = {",
	"\t[7591] = {health = {425, 575}, level = 80, flask = 7635, description = \"Only of level 80 or above.\"},",
	"\t[7618] = {health = {125, 175}, flask = 7636},",
	"\t[7620] = {mana = {75, 125}, flask = 7636},",
	"\t[28076] = {health = {600, 800}, level = 100, flask = 7635, description = \"Only of level 100 or above.\"}",
	"}",
	"function onUse(player, item, fromPosition, target, toPosition, isHotkey)",
	"\tif type(target) == \"table\" and not target:isPlayer() then",
	"\t\treturn false",
	"\tend",
	"\tif player:getCondition(CONDITION_EXHAUST_HEAL) then",
	"\t\tplayer:sendTextMessage(MESSAGE_STATUS_SMALL, Game.getReturnMessage(RETURNVALUE_YOUAREEXHAUSTED))",
	"\t\treturn true",
	"\tend",
	"\tlocal potion = potions[item:getId()]",
	"\tif potion.level and player:getLevel() < potion.level then",
	"\t\tplayer:say(potion.description, TALKTYPE_MONSTER_SAY)",
	"\t\treturn true",
	"\tend",
	"\tif potion.health then",
	"\t\tdoTargetCombat(player, target, COMBAT_HEALING, potion.health[1], potion.health[2])",
	"\tend",
	"\tif potion.mana then",
	"\t\tdoTargetCombat(player, target, COMBAT_MANADRAIN, potion.mana[1], potion.mana[2])",
	"\tend",
	"\ttarget:say(\"Aaaah...\", TALKTYPE_MONSTER_SAY)",
	"\tplayer:addItem(potion.flask, 1)",
	"\tif potion.flask then player:addItem(potion.flask, 1) end",
	"\tlocal extra = player:addItem(potion.flask, 1) and 1 or 0 -- a flask inside an expression",
	"\tplayer:sendTextMessage(MESSAGE_STATUS_SMALL, \"You have an empty flask. Return it to a potion store for your deposit.\")",
	"\tplayer:addCondition(exhaust)",
	"\titem:remove(1)",
	"\treturn true",
	"end",
	""
}, "\r\n")

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("potions_test: python3 not found, the stock script part skipped")
else
	local function runPatch(text, fn)
		local path = os.tmpname()
		local f = assert(io.open(path, "wb"))
		f:write(text)
		f:close()
		local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import install_potions as a; "
			.. "c = a.read_config(); t = a.read(sys.argv[1]); n, k = a." .. fn .. "(t, c); a.write(sys.argv[1], n); "
			.. "print(k)\" " .. path
		local h = assert(io.popen(cmd))
		local k = tonumber((h:read("*a") or ""):match("%d+"))
		h:close()
		f = assert(io.open(path, "rb"))
		local out = f:read("*a")
		f:close()
		os.remove(path)
		return out, k
	end
	local patched, n = runPatch(STOCK, "patch_no_flasks")
	eq(n, 3, "three flask calls switched off")
	local again, n2 = runPatch(patched, "patch_no_flasks")
	eq(n2, 0, "second run: nothing to do")
	eq(again, patched, "second run changes nothing")
	patched = runPatch(patched, "patch_lua_deposits")
	check(not patched:find("deposit", 1, true), "the deposit text is gone")
	check(patched:find("Potions no longer leave an empty flask.", 1, true) ~= nil, "replaced by the config's text")
	check(not patched:gsub("\r\n", ""):find("\n", 1, true), "CRLF line ends kept")

	local env = setmetatable({}, {__index = _G})
	local chunk = assert((loadstring or load)(patched, "potions.lua", "t", env))
	if setfenv then
		setfenv(chunk, env)
	end
	chunk()
	local function stockDrink(p, id, level)
		local it = mkItem(id, 10)
		p.getLevel = function() return level or 300 end
		p.addItem = function(_, fid, c) created[#created + 1] = mkItem(fid, c) return created[#created] end
		local before = #heals
		env.onUse(p, it, {}, p, {}, true)
		return it, #heals - before
	end
	local gil = mkPlayer(7)
	created = {}
	local great, healed = stockDrink(gil, 7591)
	eq(healed, 1, "a higher tier heals")
	eq(great.removed, 1, "a higher tier is consumed")
	eq(#created, 0, "drinking leaves no flask")
	check(gil.conds[CONDITION_EXHAUST_HEAL] ~= nil, "the stock exhaust still applies")
	great, healed = stockDrink(gil, 7591)
	eq(healed, 0, "exhausted: no second potion")
	eq(great.removed, 0, "exhausted: not consumed")
	gil.conds = {}
	local first = stockDrink(gil, 7618)
	eq(first.removed, 1, "a stock Health Potion stays a consumable")
	gil.conds = {}
	local herbal = stockDrink(gil, 28076)
	eq(herbal.removed, 1, "a herbalist potion of the fork: consumed")
	eq(#created, 0, "and no flask from any of them")
end

-- the amount: fixed roll + percent of the maximum (owner 2026-10-22), tree Healing on top
do
	local lo = function(a) return a end
	eq(K.percent(cfg, 0), 3, "a level 0 potion: 3% of the maximum")
	eq(K.percent(cfg, 200), 5, "level 200: 5%")
	eq(K.percent(cfg, 5000), 10, "capped at 10%")
	eq(K.amount(cfg, {150, 250}, 80, 0, 0, lo), 150, "no pool: the roll alone")
	eq(K.amount(cfg, {150, 250}, 80, 10000, 0, lo), 530, "great mana potion on 10,000 mana: 150 + 3.8%")
	eq(K.amount(cfg, {150, 250}, 80, 10000, 20, lo), 636, "and +20% tree Healing")
	check(K.amount(cfg, {150, 250}, 80, 50000, 0, lo) > K.amount(cfg, {150, 250}, 80, 10000, 0, lo),
		"a larger pool gets more from the same potion")
	eq(K.amount(cfg, {75, 75}, 0, 1000, 0), 105, "a fixed roll without rand range")
end

print(string.format("potions_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

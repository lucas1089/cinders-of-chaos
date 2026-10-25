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
eq(#cfg.everfull, 9, "two starting potions and seven upgrade tiers (O245)")
eq(K.poolsOf(cfg, HEALTH)[1], "health", "a tier spends its key's pool")
check(HEALTH.id > 32084 and HEALTH.id <= 32090 and MANA.id > 32084 and MANA.id <= 32090,
	"server ids in the free range after the Everfull Ration, before the faction tokens")
check(HEALTH.id ~= MANA.id, "two ids")
check(HEALTH.description:find("^A flask") ~= nil and MANA.description:find("^A flask") ~= nil,
	"the descriptions say they are flasks")
check(HEALTH.price > 0 and HEALTH.price <= 200 and MANA.price > 0 and MANA.price <= 200, "a cheap replacement")
for k, v in pairs(cfg.storage) do
	if k == "upgradeBase" then
		check(v == 7102510 and v + #K.upgradeTargets(cfg) - 1 <= 7102519, "the upgrade flags in their own block 7102510 - 7102519")
	else
		check(v >= 7102480 and v <= 7102489, "storage " .. k .. " in its block")
	end
end
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
	function it:remove(n)
		self.removed = self.removed + (n or self.count)
		if (n == nil or n >= self.count) and self.parent then -- a whole item leaves its container
			for i, k in ipairs(self.parent.kids) do
				if k == self then table.remove(self.parent.kids, i) break end
			end
			self.parent = nil
		end
		return true
	end
	function it:addItemEx(item)
		if not self.kids or #self.kids >= (self.cap or 20) then return RETURNVALUE_NOTENOUGHROOM end
		self.kids[#self.kids + 1] = item
		item.parent = self
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
	function p:getLevel() return self.level or 1 end
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
eq(dan.msgs[#dan.msgs], "You already have one. It refills as you kill monsters.", "told why")
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

-- ---------------------------------------------------------------- flask charges (O242)
do
	local F = cfg.flask
	local keys = {}
	for _, v in pairs(cfg.storage) do
		check(not keys[v], "storage keys are distinct (" .. v .. ")") keys[v] = true
	end
	-- core
	eq(K.maxCharges(cfg, "health", 0), 5, "health flask max") eq(K.maxCharges(cfg, "mana", 0), 8, "mana flask max")
	eq(K.maxCharges(cfg, "health", 2), 7, "tree: two extra charges")
	eq(K.maxCharges(cfg, "health", 999), 5 + F.tree.maxExtra, "tree: extra charges are capped")
	eq(K.maxCharges(cfg, "health", -3), 5, "tree: never negative") eq(K.maxCharges(cfg, "spirit", 0), 0, "no such flask")
	eq(K.read(cfg, "health", -1), 500, "never set = full") eq(K.read(cfg, "health", nil), 500, "nil = full")
	eq(K.read(cfg, "health", 230), 230, "stored hundredths") eq(K.read(cfg, "health", 99999), 500, "above the maximum: clamped")
	eq(K.read(cfg, "health", 0), 0, "empty is empty (0 is not unset)")
	eq(K.read(cfg, "health", 0 / 0), 500, "NaN is not trusted")
	check(K.canDrink(cfg, 100) and not K.canDrink(cfg, 99) and not K.canDrink(cfg, 0), "a drink costs one charge")
	eq(K.spend(cfg, 250), 150, "spend") eq(K.spend(cfg, 40), 0, "never below zero")
	local order = {"normal", "magic", "rare", "legendary", "boss"}
	for i = 2, #order do
		check(F.perKill[order[i]] > F.perKill[order[i - 1]], order[i] .. " refills more than " .. order[i - 1])
	end
	for _, t in ipairs(order) do
		check(K.killGain(cfg, {tier = t, xp = 100000, kind = "health"}) <= F.killCap, t .. " respects the cap per kill")
	end
	eq(K.killGain(cfg, {tier = "normal", xp = 200, kind = "health"}), 8, "normal at the reference experience")
	eq(K.killGain(cfg, {tier = "normal", xp = 5, kind = "health"}), 2, "a rat: a quarter")
	eq(K.killGain(cfg, {tier = "normal", xp = 1e9, kind = "health"}), 24, "experience factor is capped")
	eq(K.killGain(cfg, {tier = "boss", xp = 1, kind = "health"}), 300, "a boss ignores the experience factor")
	eq(K.killGain(cfg, {tier = "normal", xp = 200, kind = "mana"}), 12, "the mana flask gets 1.5x")
	eq(K.killGain(cfg, {tier = "normal", xp = 200, kind = "health", treeGainPct = 50}), 12, "tree charge gain")
	eq(K.killGain(cfg, {tier = "normal", xp = 200, kind = "health", treeGainPct = 5000}), 16, "tree gain is capped at 100%")
	eq(K.killGain(cfg, {tier = "mythic", xp = 200, kind = "health"}), 0, "unknown tier: nothing")
	eq(K.killGain(cfg, {tier = "boss", xp = 1, kind = "mana", treeGainPct = 100}), F.killCap, "the cap holds with everything on")
	eq(K.add(cfg, "health", 480, 300, 0), 500, "refill stops at the maximum") eq(K.add(cfg, "health", 0, -50, 0), 0, "no negative gain")
	eq(K.label(cfg, "health", 399, 0), "3/5", "label shows whole charges")
	check(K.eligibleKill(cfg, {name = "Dragon"}), "a monster refills")
	check(not K.eligibleKill(cfg, {name = "Dragon", summon = true}), "no summon")
	check(not K.eligibleKill(cfg, {name = "Dragon", husk = true}), "no husk")
	check(not K.eligibleKill(cfg, {name = "Dragon", player = true}), "no PvP refill")
	check(not K.eligibleKill(cfg, {name = "Training Dummy"}) and not K.eligibleKill(cfg, {name = ""}), "no dummy, no nameless")
	check(K.safeRefill(cfg, {safe = true, fighting = false}) and not K.safeRefill(cfg, {safe = false})
		and not K.safeRefill(cfg, {safe = true, fighting = true}), "safe zone, not in a fight")
	local ex, gn = K.treeValues(cfg, {flaskMaxCharges = 2, flaskChargeGain = 30})
	eq(ex, 2, "tree extra") eq(gn, 30, "tree gain")
	ex, gn = K.treeValues(cfg, {flaskMaxCharges = 99, flaskChargeGain = 999})
	eq(ex, F.tree.maxExtra, "tree extra capped") eq(gn, F.tree.gainPctCap, "tree gain capped")
	ex, gn = K.treeValues(cfg, nil) eq(ex, 0, "no tree bonus") eq(gn, 0, "no tree gain")
	check(K.noticeDue(cfg, nil, 0) and not K.noticeDue(cfg, 1000, 1000 + F.noticeMs - 1) and K.noticeDue(cfg, 1000, 1000 + F.noticeMs),
		"notice rate limit")
	eq(K.drink(cfg, {id = HEALTH.id, target = "self", charges = 0}).why, "empty", "an empty flask")
	eq(K.drink(cfg, {id = HEALTH.id, target = "self", charges = 0, exhausted = true}).why, "empty", "empty before exhausted")
	eq(K.drink(cfg, {id = HEALTH.id, target = "self", charges = 100}).ok, true, "one charge drinks")

	-- drinking on the mocked engine
	local gwen = mkPlayer(30)
	local flaskItem = mkItem(HEALTH.id)
	heals = {}
	eq(PT.charges(gwen, "health"), 500, "a new character has a full flask")
	for i = 1, 5 do
		os.mtime = function() return 100000 * i end -- the exhaust has passed between drinks
		drink.onUse(gwen, flaskItem, {}, gwen, {}, true)
	end
	eq(#heals, 5, "five charges, five drinks")
	eq(PT.charges(gwen, "health"), 0, "empty")
	eq(gwen.st[cfg.storage.healthCharges], 0, "stored as 0, not as unset")
	eq(PT.charges(gwen, "mana"), 800, "the mana flask is its own")
	eq(gwen.msgs[#gwen.msgs], "Health flask: 0/5", "the status line after a drink")
	os.mtime = function() return 900000 end
	eq(drink.onUse(gwen, flaskItem, {}, gwen, {}, true), true, "an empty flask is handled")
	eq(#heals, 5, "an empty flask does not heal")
	eq(gwen.msgs[#gwen.msgs], "Your health flask is empty. Kill monsters or visit a temple to refill it.", "the empty message")
	eq(flaskItem.removed, 0, "the flask item is never removed, empty or not")
	-- stock fallback: a carried stock potion of the kind is drunk instead
	local stockPot = mkItem(7618, 10)
	gwen.bp.kids[#gwen.bp.kids + 1] = stockPot
	os.mtime = function() return 950000 end
	drink.onUse(gwen, flaskItem, {}, gwen, {}, true)
	eq(#heals, 6, "the stock potion heals") eq(stockPot.removed, 1, "and is used up")
	eq(PT.charges(gwen, "health"), 0, "the flask stays empty")
	eq(gwen.msgs[#gwen.msgs], "Your health flask is empty: you drank a health potion from your backpack.", "told")
	-- a second drink inside the exhaust (empty, with stock) is refused
	drink.onUse(gwen, flaskItem, {}, gwen, {}, true)
	eq(#heals, 6, "exhaust still applies to the fallback")
	-- a drink on another player costs the drinker's charge
	local hal = mkPlayer(31) local hanna = mkPlayer(32)
	os.mtime = function() return 2000000 end
	drink.onUse(hal, flaskItem, {}, hanna, {}, false)
	eq(PT.charges(hal, "health"), 400, "the drinker pays") eq(PT.charges(hanna, "health"), 500, "the target does not")
	-- relog / item identity: a second flask item (a split or a copy) shares the same pool
	local copy = mkItem(HEALTH.id, 3)
	os.mtime = function() return 3000000 end
	drink.onUse(hal, copy, {}, hal, {}, false)
	eq(PT.charges(hal, "health"), 300, "another item of the same id uses the same character pool")
	-- never above the maximum, hand-edited storage clamps
	hal.st[cfg.storage.healthCharges] = 10 ^ 9
	eq(PT.charges(hal, "health"), 500, "an absurd stored value reads as the maximum")
	-- the tree's extra charge raises the maximum
	hal.st[cfg.storage.treeMaxCharges] = 2
	eq(PT.maxCharges(hal, "health"), 7, "tree extra charges") PT.fill(hal) eq(PT.charges(hal, "health"), 700, "fill to the new maximum")
	os.mtime = nil
end

-- kills, the safe zone and the look (potion_flasks.lua on the mocked engine)
do
	local callbacks, gevents, deathEvents = {}, {}, {}
	EventCallback = {register = function(self)
		callbacks[#callbacks + 1] = {onSpawn = self.onSpawn, onLook = self.onLook}
		self.onSpawn, self.onLook = nil, nil
	end}
	local baseEvent = event
	function GlobalEvent(name)
		local e = baseEvent(name)
		function e:interval(ms) self.ms = ms end
		function e:register() gevents[name] = self end
		return e
	end
	function CreatureEvent(name)
		local e = baseEvent(name)
		function e:register() deathEvents[name] = self end
		return e
	end
	TILESTATE_PROTECTIONZONE, CONDITION_INFIGHT, CONDITIONID_DEFAULT = 1, 2, 3
	local monsters = {}
	Creature = function(id) return monsters[id] or players[id] end
	local partyOf = {}
	local function addParty(a, b)
		local members = {a, b}
		local party = {getMembers = function() local out = {} for _, m in ipairs(members) do out[#out + 1] = m end return out end,
			getLeader = function() return a end}
		partyOf[a], partyOf[b] = party, party
	end
	local function setup(p, x, pz, fighting)
		p.pos = {x = x, y = 100, z = 7}
		p.pz, p.fighting = pz, fighting
		p.getPosition = function(self) return self.pos end
		p.getParty = function(self) return partyOf[self] end
		p.getTile = function(self) return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE and self.pz end} end
		p.getCondition = function(self, c) if c == CONDITION_INFIGHT and self.fighting then return {} end return self.conds[c] end
		p.registerEvent = function() end
		p.getTopParent = nil
	end
	dofile("data/scripts/chaos/potion_flasks.lua")
	local F = ChaosPotionFlasks
	local spawnCb, lookCb
	for _, c in ipairs(callbacks) do spawnCb = spawnCb or c.onSpawn lookCb = lookCb or c.onLook end
	check(spawnCb ~= nil and lookCb ~= nil and deathEvents.ChaosFlaskDeath ~= nil, "death event, spawn and look registered")
	eq(gevents.ChaosFlaskSafeThink.ms, cfg.flask.safeMs, "the safe zone think interval")
	local registeredOn = {}
	local function mkMonster(id, name, xp, master)
		local m = {id = id, name = name, dmg = {}, events = registeredOn}
		function m:getId() return self.id end
		function m:isPlayer() return false end
		function m:isMonster() return true end
		function m:getMaster() return master end
		function m:getName() return self.name end
		function m:getType() return {name = function() return name end, getExperience = function() return xp end} end
		function m:getDamageMap() return self.dmg end
		function m:registerEvent(e) registeredOn[#registeredOn + 1] = e end
		monsters[id] = m
		return m
	end
	local function kill(m, killer, most)
		return deathEvents.ChaosFlaskDeath.onDeath(m, nil, killer, most)
	end
	local ivy = mkPlayer(40) local jon = mkPlayer(41) local kai = mkPlayer(42) local lou = mkPlayer(43)
	for i, p in ipairs({ivy, jon, kai, lou}) do setup(p, 100 + (i == 4 and 90 or 0), false, false) end
	addParty(ivy, kai) addParty(jon, lou)
	for _, p in ipairs({ivy, jon, kai, lou}) do
		p.st[cfg.storage.healthCharges] = 0 p.st[cfg.storage.manaCharges] = 0
	end
	-- spawn: a monster carries the event, a summon does not
	spawnCb(mkMonster(900, "Rat", 5), {}, false, false)
	eq(registeredOn[1], "ChaosFlaskDeath", "a spawned monster gets the death event")
	local tamed = mkMonster(901, "Rat", 5, ivy) spawnCb(tamed, {}, false, false)
	eq(#registeredOn, 1, "a summon does not")
	-- a normal kill: killer + near party member + damage map; not a far party member
	local ogre = mkMonster(902, "Ogre", 200)
	ogre.dmg = {[jon.id] = 50}
	kill(ogre, ivy, ivy)
	eq(PT.charges(ivy, "health"), 8, "the killer: 8 hundredths (normal at the reference experience)")
	eq(PT.charges(kai, "health"), 8, "a party member of the killer, near")
	eq(PT.charges(jon, "health"), 8, "someone in the damage map")
	eq(PT.charges(lou, "health"), 0, "the damage dealer's party member 90 tiles away gets nothing")
	eq(PT.charges(ivy, "mana"), 12, "mana flask 1.5x")
	-- a boss and a rare
	local boss = mkMonster(903, "Big Boss", 1)
	ChaosTierOf = function(c) return c.id == 903 and "boss" or c.id == 904 and "rare" or "normal" end
	kill(boss, ivy, ivy)
	eq(PT.charges(ivy, "health"), 308, "a boss: 300 more")
	ivy.st[cfg.storage.healthCharges] = 0
	kill(mkMonster(904, "Ogre", 200), ivy, ivy)
	eq(PT.charges(ivy, "health"), 60, "a rare: 60")
	-- no refill: a summon's death, a training dummy, a player's death (no PvP refill)
	ivy.st[cfg.storage.healthCharges] = 0
	kill(mkMonster(905, "Rat", 200, jon), ivy, ivy) kill(mkMonster(906, "Training Dummy", 200), ivy, ivy)
	local victim = mkPlayer(44) setup(victim, 100, false, false)
	victim.isMonster = function() return false end
	kill(victim, ivy, ivy)
	eq(PT.charges(ivy, "health"), 0, "summon, dummy and a player's death refill nothing")
	-- a rift husk refills nothing
	ChaosRift = {isHusk = function(c) return c.id == 907 end}
	kill(mkMonster(907, "Ogre", 200), ivy, ivy)
	eq(PT.charges(ivy, "health"), 0, "a husk refills nothing")
	ChaosRift = nil
	-- full flask stays full; a kill by a non-player (a monster killed by another) does nothing
	ivy.st[cfg.storage.healthCharges] = -1
	kill(mkMonster(908, "Ogre", 200), ivy, ivy)
	eq(PT.charges(ivy, "health"), 500, "a full flask stays at the maximum")
	local env = mkMonster(909, "Ogre", 200)
	kill(env, nil, nil) kill(env, monsters[900], monsters[900])
	-- the notice: a whole charge more, rate limited
	local mia = mkPlayer(45) setup(mia, 100, false, false)
	mia.st[cfg.storage.healthCharges] = 95 mia.st[cfg.storage.manaCharges] = 0
	os.mtime = function() return 10000 end
	kill(mkMonster(910, "Ogre", 200), mia, mia)
	eq(mia.msgs[#mia.msgs], "Flasks: health 1/5, mana 0/8", "the refill line when a whole charge came")
	local n = #mia.msgs
	mia.st[cfg.storage.healthCharges] = 95
	os.mtime = function() return 10000 + 1000 end
	kill(mkMonster(911, "Ogre", 200), mia, mia)
	eq(#mia.msgs, n, "at most one refill line per noticeMs")
	os.mtime = function() return 10000 + cfg.flask.noticeMs + 1 end
	mia.st[cfg.storage.healthCharges] = 95
	kill(mkMonster(912, "Ogre", 200), mia, mia)
	eq(#mia.msgs, n + 1, "and one again later")
	-- the safe zone
	local nan = mkPlayer(46) setup(nan, 100, true, false)
	nan.st[cfg.storage.healthCharges] = 0 nan.st[cfg.storage.manaCharges] = 100
	local oto = mkPlayer(47) setup(oto, 100, false, false) oto.st[cfg.storage.healthCharges] = 0
	local pam = mkPlayer(48) setup(pam, 100, true, true) pam.st[cfg.storage.healthCharges] = 0
	eq(F.safePass({nan, oto, pam}), 1, "only the player in the zone and out of a fight is filled")
	eq(PT.charges(nan, "health"), 500, "health full") eq(PT.charges(nan, "mana"), 800, "mana full")
	eq(PT.charges(oto, "health"), 0, "outside: nothing") eq(PT.charges(pam, "health"), 0, "in the zone but fighting: nothing")
	eq(nan.msgs[#nan.msgs], "Your flasks are full again.", "told")
	eq(F.safePass({nan}), 0, "already full: no second message")
	-- look: your own flask only
	local own = mkItem(HEALTH.id)
	own.isItem = function() return true end
	own.getTopParent = function() return ivy end
	ivy.isPlayer = function() return true end
	ivy.st[cfg.storage.healthCharges] = 230
	eq(lookCb(ivy, own, {}, 1, "You see an everfull health potion."), "You see an everfull health potion.\nCharges: 2/5",
		"look shows your charges")
	eq(lookCb(jon, own, {}, 1, "You see x."), "You see x.", "somebody else's flask shows none of yours")
	local other = mkItem(7618) other.isItem = function() return true end other.getTopParent = function() return ivy end
	eq(lookCb(ivy, other, {}, 1, "You see y."), "You see y.", "a stock potion is untouched")
	os.mtime = nil
end

-- ---------------------------------------------------------------- higher tiers (O245)
do
	local apo = dofile("data/scripts/chaos/apothecary_config.lua")
	local askOf, levelOf = {}, {}
	for _, x in ipairs(apo.potions) do askOf[x.id], levelOf[x.id] = x.price, x.level end
	local up = K.upgradeTargets(cfg)
	eq(#up, 7, "seven upgrade tiers") eq(#K.upgradeTargets({everfull = {}}), 0, "none without entries")
	local seenId, seenSrc = {}, {}
	for _, e in ipairs(up) do
		check(e.id >= 32261 and e.id <= 32280, e.name .. ": server id in the reserved range 32261..32280")
		check(not seenId[e.id] and not seenSrc[e.sourceId], e.name .. ": own id and own source")
		seenId[e.id], seenSrc[e.sourceId] = true, true
		eq(e.level, levelOf[e.sourceId], e.name .. ": the stock potion's level (apothecary_config.lua)")
		eq(e.price, cfg.upgrade.materials * askOf[e.sourceId], e.name .. ": a lost flask costs the materials' worth")
		check(e.description:find("^A flask") ~= nil and e.description:find("level " .. e.level, 1, true) ~= nil, e.name .. ": description")
		check(e.name:find("^everfull ") ~= nil and e.plural == e.name .. "s", e.name .. ": name and plural")
		check(K.upgradeStorage(cfg, e.id) >= 7102510 and K.upgradeStorage(cfg, e.id) <= 7102519, e.name .. ": its flag in the block")
		check(cfg.upgrade.coins[e.tier] ~= nil and K.upgradeCoins(cfg, e.id) == cfg.upgrade.coins[e.tier], e.name .. ": a store price")
		local pools = K.poolsOf(cfg, e)
		eq(#pools, e.line == "spirit" and 2 or 1, e.name .. ": pools")
		check(e.from ~= nil and K.everfull(cfg, e.from[1]) ~= nil and K.everfull(cfg, e.from[1]).tier == e.tier - 1, e.name .. ": made from the previous tier")
	end
	local byId = {}
	for _, e in ipairs(cfg.everfull) do byId[e.id] = e end
	eq(byId[32261].health[1], 425, "great health roll") eq(byId[32264].health[2], 850, "ultimate health roll")
	eq(byId[32267].level, 200, "supreme health level") eq(byId[32265].mana[1], 425, "ultimate mana roll")
	eq(byId[32263].mana[2], 200, "great spirit mana roll") eq(byId[32266].health[1], 420, "ultimate spirit health roll")
	eq(K.upgradeStorage(cfg, 32085), nil, "a starting potion has no flag") eq(K.upgradeCoins(cfg, 32086), nil, "and no price")
	check(cfg.upgrade.coins[2] < cfg.upgrade.coins[3] and cfg.upgrade.coins[3] < cfg.upgrade.coins[4], "the price grows by tier")

	-- the drink core
	r = K.drink(cfg, {id = 32261, target = "self", level = 79, charges = 500})
	eq(r.why, "level", "below the stock potion's level: refused") eq(r.args[1], 80, "with its level")
	eq(K.drink(cfg, {id = 32261, target = "self", level = 80, charges = 500}).ok, true, "at the level")
	eq(K.drink(cfg, {id = 32261, target = "self", charges = 500}).ok, true, "no level given: not checked (the old callers)")
	r = K.drink(cfg, {id = 32263, target = "self", level = 100, charges = {health = 500, mana = 50}})
	eq(r.why, "empty", "a spirit drink needs a charge in BOTH pools") eq(r.kind, "mana", "and says which pool is short")
	r = K.drink(cfg, {id = 32263, target = "self", level = 100, charges = {health = 500, mana = 100}})
	check(r.ok and #r.pools == 2 and r.health ~= nil and r.mana ~= nil, "a spirit potion heals and restores mana, two pools")

	-- the check
	local function chk(over)
		local s = {id = 32261, installed = true, level = 100, held = {32085}, mode = "quest", materials = 40, materialName = "great health potions"}
		for k, v in pairs(over or {}) do s[k] = v end
		return K.upgradeCheck(cfg, s)
	end
	eq(chk().ok, true, "the happy path") eq(chk().from, 32085, "from the starting potion") eq(chk().materials, 40, "40 stock potions")
	eq(chk({mode = "store", materials = 0}).ok, true, "the store needs no materials") eq(chk({mode = "store"}).materials, 0, "and takes none")
	eq(chk({id = 32085}).why, "unknown", "a starting potion is not an upgrade") eq(chk({id = 7591}).why, "unknown", "nor a stock one")
	eq(chk({installed = false}).why, "installed", "not installed") eq(chk({level = 79}).why, "level", "the level")
	eq(chk({done = true}).why, "done", "once per tier") eq(chk({held = {}}).why, "missing", "no flask")
	eq(chk({held = {32086}}).why, "missing", "the other slot's flask does not count")
	eq(chk({held = {32085, 32085}}).why, "duplicate", "two flasks of the slot")
	eq(chk({held = {32085, 32261}}).why, "duplicate", "two tiers of the slot")
	eq(chk({id = 32264, level = 200, held = {32085}}).why, "tier", "a tier cannot be skipped")
	eq(chk({id = 32264, level = 200, held = {32263}}).why, "tier", "the spirit line does not turn into the health line")
	eq(chk({id = 32266, level = 200, held = {32261}}).why, "tier", "nor the health line into the spirit line")
	eq(chk({id = 32263, held = {32085}}).ok, true, "the spirit line starts from the health flask")
	eq(chk({materials = 39}).why, "materials", "one short") eq(chk({materials = 39}).args[1], 40, "says how many")
	eq(chk({materials = false}).why, "materials", "unknown count: refused")
	eq(chk({level = "x"}).why, "level", "a bad level is not trusted") eq(chk({held = {99999}}).why, "missing", "unknown ids are not flasks")

	-- the restore rule
	local earned = {byId[32261], byId[32264], byId[32262]}
	eq(K.restoreFor(cfg, "health", {}, earned).id, 32264, "the highest earned tier of the slot comes back")
	eq(K.restoreFor(cfg, "mana", {}, earned).id, 32262, "per slot")
	eq(K.restoreFor(cfg, "health", {32261}, earned), nil, "nothing while the slot holds a flask")
	eq(K.restoreFor(cfg, "mana", {}, {}), nil, "nothing earned: nothing back")
	eq(K.npcBuy(cfg, {id = 32261, owned = false, money = 1e9}).why, "unknown", "a seller never sells a higher tier")
	eq(K.npcBuy(cfg, {id = HEALTH.id, owned = false, better = true, money = 1000}).why, "better", "nor the starting one over an earned tier")

	-- the engine side
	local function bound(id, lock) local it = mkItem(id) it.attrs.chaos_storebound, it.attrs.chaos_locked = 1, lock or cfg.bindLock return it end
	local function stockStack(player, n) local st = mkItem(7591, n) player.bp.kids[#player.bp.kids + 1] = st st.parent = player.bp return st end
	local function ext(pl)
		function pl:getName() return "P" .. self.id end
		function pl:getItemCount(id) local n = 0 for _, k in ipairs(self.bp.kids) do if k.id == id then n = n + k.count end end return n end
		function pl:removeItem(id, n)
			if self:getItemCount(id) < n then return false end
			local snapshot = {}
			for i, k in ipairs(self.bp.kids) do snapshot[i] = k end
			for _, k in ipairs(snapshot) do
				if k.id == id and n > 0 then
					local take = math.min(n, k.count)
					k.count = k.count - take n = n - take
					if k.count == 0 then k:remove() end
				end
			end
			return true
		end
		function pl:addItem(id, n) local it = mkItem(id, n) self.bp:addItemEx(it) return it end
		return pl
	end
	local function holder(id, level, lockv, ...)
		local pl = ext(mkPlayer(id)) pl.level = level or 100
		local fl = bound(HEALTH.id, lockv) pl.bp.kids[1] = fl fl.parent = pl.bp
		return pl, fl
	end
	local flagH = K.upgradeStorage(cfg, 32261)

	-- Veyra's task: the swap, atomic, the attributes and the charges kept
	local pl, fl = holder(60, 100, 5)
	pl.st[cfg.storage.healthCharges] = 230 pl.st[cfg.storage.manaCharges] = 40
	local st = stockStack(pl, 45)
	eq(PT.upgradeCheck(pl, 32261, "quest").ok, true, "check: ready")
	local ok, why, args = PT.upgrade(pl, 32261, "quest")
	eq(ok, true, "the quest swap")
	local ids = {}
	for _, k in ipairs(pl.bp.kids) do ids[#ids + 1] = k.id end
	check(#ids == 2 and ids[1] == 7591 and ids[2] == 32261, "the old flask is gone, the new one is there (and the leftover stock)")
	eq(fl.removed, 1, "the old item was removed") eq(st.count, 5, "40 of the 45 stock potions were taken")
	local new = pl.bp.kids[2]
	eq(new.attrs.chaos_storebound, 1, "bound kept") eq(new.attrs.chaos_locked, 5, "the lock value kept")
	eq(pl.st[flagH], 1, "the tier is marked done")
	eq(pl.st[cfg.storage.healthCharges], 230, "the health charges are untouched") eq(pl.st[cfg.storage.manaCharges], 40, "and the mana ones")
	ok, why = PT.upgrade(pl, 32261, "quest")
	eq(ok, false, "a second time: refused") eq(why, "You already have this upgrade.", "because it is done")
	ok, why = PT.upgrade(pl, 32261, "store")
	eq(ok, false, "not by the store either")
	eq(PT.ownedSlot(pl, "health"), true, "the slot holds the new tier") eq(PT.owned(pl, 32085), false, "and not the old")
	-- the next tier needs its level and its materials
	pl.level = 100
	ok, why = PT.upgrade(pl, 32264, "quest")
	eq(ok, false, "ultimate at level 100: refused") eq(why, "This flask is for level %d and up, and you are not there yet.", "the level")
	pl.level = 130
	ok, why, args = PT.upgrade(pl, 32264, "quest")
	eq(ok, false, "ultimate without materials: refused") eq(args[1], 40, "needs 40") eq(args[2], "ultimate health potions", "of its own tier")
	eq(#pl.bp.kids, 2, "nothing changed")
	-- the store does the same swap without the materials
	ok = PT.upgrade(pl, 32264, "store")
	eq(ok, true, "the store swap") eq(pl.bp.kids[2].id, 32264, "the new tier") eq(pl.bp.kids[2].attrs.chaos_locked, 5, "attributes kept again")
	eq(pl.st[K.upgradeStorage(cfg, 32264)], 1, "marked") eq(st.count, 5, "no materials taken by the store")

	-- refusals change nothing
	local function untouched(pl2, label, id, mode)
		local before = #pl2.bp.kids
		local ok2 = PT.upgrade(pl2, id or 32261, mode or "quest")
		eq(ok2, false, label) eq(#pl2.bp.kids, before, label .. ": nothing moved")
		eq(pl2.st[K.upgradeStorage(cfg, id or 32261)], nil, label .. ": no flag")
	end
	local lo = holder(61, 79) stockStack(lo, 40) untouched(lo, "level 79")
	local poor = holder(62, 100) stockStack(poor, 39) untouched(poor, "39 materials")
	eq(poor.bp.kids[2].count, 39, "the 39 are still there")
	local none = ext(mkPlayer(63)) none.level = 100 stockStack(none, 40) untouched(none, "no flask at all")
	local twin = holder(64, 100) twin.bp.kids[2] = bound(HEALTH.id) twin.bp.kids[2].parent = twin.bp stockStack(twin, 40) untouched(twin, "two flasks")
	local wrongTier = holder(65, 200) stockStack(wrongTier, 40) untouched(wrongTier, "skipping a tier", 32264)

	-- no room: the new flask finds no place, nothing is taken
	local full = holder(66, 100) stockStack(full, 40)
	full.bp.cap, full.inbox.cap = #full.bp.kids, 0
	local nOk, nWhy = PT.upgrade(full, 32261, "quest")
	eq(nOk, false, "no room: refused") eq(nWhy, "You have no room for it.", "says so")
	eq(full.bp.kids[1].id, HEALTH.id, "the old flask is still there") eq(full.bp.kids[2].count, 40, "the materials are still there")
	eq(full.st[flagH], nil, "no flag")

	-- the flask in the inbox is found and swapped in place of the search (it must not be lost)
	local inb = ext(mkPlayer(67)) inb.level = 100
	local boxed = bound(HEALTH.id) inb.inbox.kids[1] = boxed boxed.parent = inb.inbox
	eq(PT.upgrade(inb, 32261, "store"), true, "a flask in the inbox is found")
	eq(#inb.inbox.kids, 0, "the old one left the inbox") eq(inb.bp.kids[1].id, 32261, "the new one is in the backpack")

	-- an error in the middle undoes everything (the old flask stays, no flag, materials back)
	local boom = holder(68, 100) stockStack(boom, 40)
	local realSet = boom.setStorageValue
	boom.setStorageValue = function(self, k, v) if k == flagH and v == 1 then error("boom") end return realSet(self, k, v) end
	local silent = print print = function() end
	local bOk = PT.upgrade(boom, 32261, "quest")
	print = silent
	eq(bOk, false, "an error: refused") eq(boom.bp.kids[1].id, HEALTH.id, "the old flask is kept")
	eq(boom:getItemCount(7591), 40, "the materials are given back") eq(boom:getItemCount(32261), 0, "no new flask is left")
	boom.setStorageValue = realSet
	eq(boom.st[flagH], nil, "no flag")
	-- the old flask cannot be removed: undone as well
	local stuck = holder(69, 100) stockStack(stuck, 40)
	stuck.bp.kids[1].remove = function() return false end
	eq(PT.upgrade(stuck, 32261, "quest"), false, "a flask that will not go: refused")
	eq(stuck:getItemCount(7591), 40, "materials back") eq(stuck.st[flagH], 0, "flag back") eq(#stuck.bp.kids, 2, "no new flask left")

	-- two clicks: the second finds the swap done
	local dbl = holder(70, 100)
	eq(PT.upgrade(dbl, 32261, "store"), true, "first click") eq(PT.upgrade(dbl, 32261, "store"), false, "second click")
	eq(PT.owned(dbl, 32261), true, "one new flask") eq(#dbl.bp.kids, 1, "and only one item")

	-- the spirit line: from the health flask, spends both pools
	local sp = holder(71, 100)
	eq(PT.upgrade(sp, 32263, "store"), true, "health flask -> great spirit")
	eq(PT.upgrade(sp, 32261, "store"), false, "then the health line is closed to it (no health flask)")
	sp.level = 130
	eq(PT.upgrade(sp, 32266, "store"), true, "great spirit -> ultimate spirit")
	eq(sp.bp.kids[1].id, 32266, "one item in the slot")
	local heal = {}
	local action = actions[32266]
	check(action ~= nil, "the new ids have the drink action")
	sp.st[cfg.storage.healthCharges], sp.st[cfg.storage.manaCharges] = 300, 300
	heals = {}
	eq(action.onUse(sp, sp.bp.kids[1], {}, sp, {}, false), true, "a spirit drink")
	eq(#heals, 2, "health and mana") eq(PT.charges(sp, "health"), 200, "one health charge") eq(PT.charges(sp, "mana"), 200, "and one mana charge")
	eq(PT.labelOf(sp, byId[32266]), "2/5 + 2/8", "the label shows both pools")
	sp.st[cfg.storage.manaCharges] = 50
	heals = {}
	action.onUse(sp, sp.bp.kids[1], {}, sp, {}, false)
	eq(#heals, 0, "no mana charge: no drink") eq(PT.charges(sp, "health"), 200, "and the health charge is not spent either")
	-- a drink below the potion's level
	local young = holder(72, 100)
	PT.upgrade(young, 32261, "store")
	young.level = 79
	heals = {}
	action.onUse(young, young.bp.kids[1], {}, young, {}, false)
	eq(#heals, 0, "below the stock potion's level: no drink") eq(young.msgs[#young.msgs], "Only characters of level 80 or above may drink this fluid.", "told")

	-- charges are per pool: one kill refills each pool once, whatever flasks are held
	local kill = holder(73, 100)
	kill.st[cfg.storage.healthCharges], kill.st[cfg.storage.manaCharges] = 0, 0
	PT.upgrade(kill, 32263, "store")
	local gained, any = PT.addKill(kill, "normal", 200)
	eq(PT.charges(kill, "health"), 8, "one kill refill for the health pool") eq(PT.charges(kill, "mana"), 12, "and the mana pool")
	eq(any, true, "refilled")

	-- the seller and the starter kit never make a second flask
	local up2 = holder(74, 100)
	PT.upgrade(up2, 32261, "store")
	up2.money, up2.bank = 500, 0
	eq(PT.npcBuy(up2.id, HEALTH.id), false, "the seller will not sell a second health flask") eq(up2.money, 500, "no gold taken")
	eq(PT.giveAll(up2), 1, "giveAll only fills the mana slot") eq(PT.ownedSlot(up2, "mana"), true, "the mana flask came") 
	eq(PT.owned(up2, HEALTH.id), false, "and no starting health flask beside the great one")

	-- a lost flask: the highest earned tier comes back for its price, once
	local lost = holder(75, 130)
	PT.upgrade(lost, 32261, "store") PT.upgrade(lost, 32264, "store")
	for i = #lost.bp.kids, 1, -1 do lost.bp.kids[i]:remove() end
	eq(PT.ownedSlot(lost, "health"), false, "the flask is gone")
	lost.money, lost.bank = 100, 0
	lost.msgs = {}
	eq(PT.npcBuy(lost.id, HEALTH.id), false, "the seller refuses the starting one") eq(lost.msgs[#lost.msgs],
		"You earned a better flask than that. Ask Veyra the Apothecary to give it back.", "and points to Veyra")
	local rOk, rWhy = PT.restore(lost.id, "health")
	eq(rOk, false, "too poor") eq(rWhy, "You do not have enough money.", "says so")
	lost.money, lost.bank = 10000, 5000
	rOk, rWhy = PT.restore(lost.id, "health")
	eq(rOk, true, "restored") eq(rWhy.id, 32264, "the ultimate flask") eq(lost.money + lost.bank, 15000 - byId[32264].price, "for its price")
	eq(lost.bp.kids[1].attrs.chaos_storebound, 1, "bound")
	eq(PT.restore(lost.id, "health"), false, "not again while it holds one")
	eq(select(2, PT.restore(lost.id, "mana")), "I have nothing to give back.", "nothing earned for the mana slot")

	-- the store service
	ChaosShopServices = {services = {}}
	PT.registerService()
	local svc = ChaosShopServices.services.everfullUpgrade
	check(svc ~= nil, "registered into the store's services")
	local offer = {kind = "service", service = "everfullUpgrade", upgrade = 32262, cost = cfg.upgrade.coins[2]}
	local buyer = ext(mkPlayer(80)) buyer.level = 100
	local mana = bound(MANA.id) buyer.bp.kids[1] = mana mana.parent = buyer.bp
	eq(svc.check(buyer, offer), nil, "check: can buy")
	eq(svc.check(buyer, {upgrade = 32262, cost = 1}), "This offer cannot be bought.", "a price that is not the config's: refused")
	eq(svc.check(buyer, {upgrade = 32085, cost = 30}), "This offer cannot be bought.", "not a tier")
	eq(svc.check(buyer, {upgrade = "32262; drop", cost = 30}), "This offer cannot be bought.", "garbage")
	eq(svc.check(buyer, {cost = 30}), "This offer cannot be bought.", "no tier")
	eq(svc.check(buyer, {upgrade = 32264, cost = 50}) ~= nil, true, "ultimate: not yet (wrong tier)")
	eq(svc.apply(buyer, offer), true, "apply") eq(buyer.bp.kids[1].id, 32262, "swapped")
	check(svc.check(buyer, offer) ~= nil, "check: already done")
	local refused = svc.apply(buyer, offer)
	check(type(refused) == "string" and refused:find("Your coins were refunded.", 1, true) ~= nil, "a failed apply says the coins come back")
	eq(#buyer.bp.kids, 1, "still one flask")
	-- the upgrade reaches the shop's offer key and every offer has its price
	local shopCfg = dofile("data/scripts/chaos/shop_config.lua")
	local n = 0
	for _, cat in ipairs(shopCfg.categories) do
		for _, o in ipairs(cat.offers or {}) do
			if o.service == "everfullUpgrade" then
				n = n + 1
				eq(o.cost, K.upgradeCoins(cfg, o.upgrade), "store price of " .. o.name .. " is the config's")
				eq(o.icon, o.upgrade, "its icon is the item")
			end
		end
	end
	eq(n, 7, "one store offer per tier")
end
print(string.format("potions_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

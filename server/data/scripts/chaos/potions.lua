-- Potions (server/README.md "Potions"): the Everfull health and mana potions (potions_config.lua; rules
-- potions_core.lua; helpers data/lib/chaos_potions.lua; items, flask removal and NPC shops by
-- server/tools/install_potions.py).
--
-- An Everfull potion drinks like the stock Health / Mana Potion (the same roll, on yourself or another player) and is
-- never used up and never leaves a flask. Since O242 it is a flask with charges (potion_flasks.lua refills them). The health and the mana potion each have their own wait (the action
-- interval - 100 ms), so a mana potion right after a health potion works (owner 2026-10-17: it said "You are
-- exhausted"); no CONDITION_EXHAUST_HEAL is added any more, so healing spells are not held up either. Each kind is
-- not faster than a stack of stock potions. Store-bound and locked like the Everfull Ration:
-- not traded, sold, dropped or lost on death (pouches.lua, engine patch 0009, death_keep.lua).
-- Sources: the starter kit (newplayer.lua calls ChaosPotions.giveAll), a one-time grant at login for characters made
-- before them, and every potion seller's trade window (one copy, ChaosPotions.npcBuy). Stock potions of every tier
-- stay consumables; the base potions.lua no longer gives an empty flask (install_potions.py).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/potions_core.lua")
dofile("data/scripts/chaos/potions_config.lua")
dofile("data/lib/chaos_potions.lua")

local PT = ChaosPotions
local K = ChaosPotionsCore

local function exhaustMs()
	local ok, ms = pcall(function()
		return configManager.getNumber(configKeys.EX_ACTIONS_DELAY_INTERVAL) - 100
	end)
	if ok and type(ms) == "number" and ms > 0 then
		return ms
	end
	return PT.cfg().exhaustMs
end

-- the wait of each kind of potion, per player: [playerId .. ":" .. kind] = the time of the last drink in ms
local lastDrink = {}
local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

local function kindOf(id)
	for _, e in ipairs(PT.cfg().everfull) do
		if e.id == id then
			return e.key
		end
	end
	return "health"
end

local function targetKind(player, target)
	if type(target) ~= "userdata" and type(target) ~= "table" then
		return "self", player
	end
	local ok, isCreature = pcall(function() return target:isCreature() end)
	if not ok or not isCreature then
		return "self", player
	end
	if target:isPlayer() then
		return "player", target
	end
	return "creature", nil
end

-- ---------------------------------------------------------------- drinking
-- The Everfull potions are flasks with charges (README "Flask charges"): a drink costs one, an empty flask cannot be
-- drunk (a carried stock potion of the same kind is drunk instead, used up), kills and the temple refill them
-- (potion_flasks.lua). The charges are the character's storage, not the item's.
local function flaskStatus(player, kind)
	if kind == "mana" then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "Mana flask: %s", PT.label(player, kind)))
	else
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "Health flask: %s", PT.label(player, kind)))
	end
end

local drink = Action()
function drink.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local kind, who = targetKind(player, target)
	local flask = kindOf(item:getId())
	local slot = player:getId() .. ":" .. flask
	local waiting = lastDrink[slot] ~= nil and nowMs() - lastDrink[slot] < exhaustMs()
	local r = K.drink(PT.cfg(), {id = item:getId(), exhausted = waiting, target = kind,
		charges = PT.charges(player, flask)})
	local stock
	if not r.ok then
		if r.why == "exhausted" then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Game.getReturnMessage(RETURNVALUE_YOUAREEXHAUSTED))
			return true
		end
		if r.why ~= "empty" then
			return false
		end
		if waiting then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Game.getReturnMessage(RETURNVALUE_YOUAREEXHAUSTED))
			return true
		end
		local e = PT.everfull(item:getId())
		stock = PT.cfg().flask.stockFallback and PT.findStock(player, e.sourceId) or nil
		if not stock then
			if flask == "mana" then
				player:sendTextMessage(MESSAGE_STATUS_SMALL,
					Chaos.t(player, "Your mana flask is empty. Kill monsters or visit a temple to refill it."))
			else
				player:sendTextMessage(MESSAGE_STATUS_SMALL,
					Chaos.t(player, "Your health flask is empty. Kill monsters or visit a temple to refill it."))
			end
			return true
		end
		r = {ok = true, health = e.health, mana = e.mana}
	end
	if stock then
		stock:remove(1) -- the empty flask drinks a stock potion of its kind from the backpack
	elseif not PT.spend(player, flask) then
		return true
	end
	if r.health then
		local v = ChaosPotions.amount(player, who, "health", r.health, 0)
		doTargetCombat(player, who, COMBAT_HEALING, v, v)
	end
	if r.mana then
		local v = ChaosPotions.amount(player, who, "mana", r.mana, 0)
		doTargetCombat(player, who, COMBAT_MANADRAIN, v, v)
	end
	who:say(PT.cfg().sound, TALKTYPE_MONSTER_SAY)
	lastDrink[slot] = nowMs()
	if stock then
		if flask == "mana" then
			player:sendTextMessage(MESSAGE_STATUS_SMALL,
				Chaos.t(player, "Your mana flask is empty: you drank a mana potion from your backpack."))
		else
			player:sendTextMessage(MESSAGE_STATUS_SMALL,
				Chaos.t(player, "Your health flask is empty: you drank a health potion from your backpack."))
		end
	else
		flaskStatus(player, flask)
	end
	return true -- the flask is never used up
end
local registered = 0
for _, e in ipairs(PT.cfg().everfull) do
	if PT.installed(e.id) then
		drink:id(e.id)
		registered = registered + 1
	end
end
if registered > 0 then
	drink:register()
end

-- ---------------------------------------------------------------- the one-time grant
local login = CreatureEvent("ChaosPotionsLogin")
function login.onLogin(player)
	local c = PT.cfg()
	local okR, errR = pcall(PT.rebind, player)
	if not okR then
		print("[potions] rebind of " .. player:getName() .. " failed: " .. tostring(errR))
	end
	if not K.grantDue(c, {granted = player:getStorageValue(c.storage.granted) == 1,
		lastLogin = player:getLastLoginSaved()}) then
		return true
	end
	if PT.giveAll(player) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"You received an Everfull Health Potion and an Everfull Mana Potion. They refill as you kill monsters."))
	end
	return true
end
login:type("login")
login:register()

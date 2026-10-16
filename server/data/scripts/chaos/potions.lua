-- Potions (server/README.md "Potions"): the Everfull health and mana potions (potions_config.lua; rules
-- potions_core.lua; helpers data/lib/chaos_potions.lua; items, flask removal and NPC shops by
-- server/tools/install_potions.py).
--
-- An Everfull potion drinks like the stock Health / Mana Potion (the same roll, on yourself or another player) and is
-- never used up and never leaves a flask. It shares the stock potions' exhaust (CONDITION_EXHAUST_HEAL, the action
-- interval - 100 ms), so it is not faster than a stack of stock potions. Store-bound and locked like the Everfull Ration:
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

local exhaust = Condition(CONDITION_EXHAUST_HEAL)
if exhaust and exhaust.setParameter then
	exhaust:setParameter(CONDITION_PARAM_TICKS, exhaustMs())
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
local drink = Action()
function drink.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local kind, who = targetKind(player, target)
	local r = K.drink(PT.cfg(), {id = item:getId(), exhausted = player:getCondition(CONDITION_EXHAUST_HEAL) ~= nil,
		target = kind})
	if not r.ok then
		if r.why == "exhausted" then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Game.getReturnMessage(RETURNVALUE_YOUAREEXHAUSTED))
			return true
		end
		return false
	end
	if r.health then
		doTargetCombat(player, who, COMBAT_HEALING, r.health[1], r.health[2])
	end
	if r.mana then
		doTargetCombat(player, who, COMBAT_MANADRAIN, r.mana[1], r.mana[2])
	end
	who:say(PT.cfg().sound, TALKTYPE_MONSTER_SAY)
	player:addCondition(exhaust)
	return true -- never used up, no flask
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
	if not K.grantDue(c, {granted = player:getStorageValue(c.storage.granted) == 1,
		lastLogin = player:getLastLoginSaved()}) then
		return true
	end
	if PT.giveAll(player) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"You received an Everfull Health Potion and an Everfull Mana Potion. They never run out."))
	end
	return true
end
login:type("login")
login:register()

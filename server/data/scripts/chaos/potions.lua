-- Potions (server/README.md "Potions"): the Everfull health and mana potions (potions_config.lua; rules
-- potions_core.lua; helpers data/lib/chaos_potions.lua; items, flask removal and NPC shop cleanup by
-- server/tools/install_potions.py).
--
-- An Everfull potion drinks like the stock Health / Mana Potion (the same roll, on yourself or another player) and is
-- never used up, never leaves a flask and never runs out: it has no charges (O242 gave it some, O273 took them away
-- again: "deixe-as ilimitadas"). The health and the mana potion each have their own wait (the action
-- interval - 100 ms), so a mana potion right after a health potion works (owner 2026-10-17: it said "You are
-- exhausted"); no CONDITION_EXHAUST_HEAL is added any more, so healing spells are not held up either. Each kind is
-- not faster than a stack of stock potions. Store-bound and locked like the Everfull Ration:
-- not traded, sold, dropped or lost on death (pouches.lua, engine patch 0009, death_keep.lua).
-- Sources: the starter kit (newplayer.lua calls ChaosPotions.giveAll), a one-time grant at login for characters made
-- before them, and Veyra the Apothecary's {lost} (a lost flask comes back for gold). No NPC sells them (O273). Stock
-- potions of every tier stay consumables; the base potions.lua no longer gives an empty flask (install_potions.py).
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
local unpack = table.unpack or unpack

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
-- Unlimited (O273): a drink needs the level of the potion and the wait of its kinds, nothing else, and spends nothing.
local drink = Action()
function drink.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local kind, who = targetKind(player, target)
	local e = PT.everfull(item:getId())
	if not e then
		return false
	end
	local pools = K.poolsOf(PT.cfg(), e)
	-- the wait: a drink waits on every kind it sets (a spirit drink is no faster than a health and a mana drink)
	local waiting = false
	for _, pool in ipairs(pools) do
		local last = lastDrink[player:getId() .. ":" .. pool]
		if last ~= nil and nowMs() - last < exhaustMs() then
			waiting = true
		end
	end
	local r = K.drink(PT.cfg(), {id = item:getId(), exhausted = waiting, target = kind, level = player:getLevel()})
	if not r.ok then
		if r.why == "exhausted" then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Game.getReturnMessage(RETURNVALUE_YOUAREEXHAUSTED))
			return true
		end
		if r.why == "level" then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, r.text, unpack(r.args)))
			return true
		end
		return false
	end
	local tier = e.tier or 1 -- the Everfull percent of its tier
	if r.health then
		local v = ChaosPotions.amount(player, who, "health", r.health, e.level or 0, tier)
		doTargetCombat(player, who, COMBAT_HEALING, v, v)
	end
	if r.mana then
		local v = ChaosPotions.amount(player, who, "mana", r.mana, e.level or 0, tier)
		doTargetCombat(player, who, COMBAT_MANADRAIN, v, v)
	end
	who:say(PT.cfg().sound, TALKTYPE_MONSTER_SAY)
	for _, pool in ipairs(pools) do
		lastDrink[player:getId() .. ":" .. pool] = nowMs()
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
-- a logged-out player's waits go (the table is keyed by creature id, which is never reused: it would only grow)
local forget = CreatureEvent("ChaosPotionsForget")
function forget.onLogout(player)
	for _, pool in ipairs(PT.cfg().pools) do
		lastDrink[player:getId() .. ":" .. pool] = nil
	end
	return true
end
forget:type("logout")
forget:register()

local login = CreatureEvent("ChaosPotionsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPotionsForget")
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
			"You received an Everfull Health Potion and an Everfull Mana Potion. They never run out."))
	end
	return true
end
login:type("login")
login:register()

-- ---------------------------------------------------------------- the store sells the same upgrade (O245)
-- {kind = "service", service = "everfullUpgrade", upgrade = <server id of the tier>, cost = coins} (shop_config.lua,
-- Consumables > Convenience). Registered into ChaosShopServices.services here (no edit of shop_services.lua). The swap is
-- ChaosPotions.upgrade(player, id, "store"), the code Veyra's task runs; the store takes the coins before apply and gives
-- them back on any result but true, apply changes nothing unless it returns true. Services are not giftable.
local function upgradeId(offer)
	local id = tonumber(offer and offer.upgrade)
	if not id or K.upgradeCoins(PT.cfg(), id) ~= tonumber(offer.cost) then -- a price that differs from the config: refused
		return nil
	end
	return id
end

local function problem(player, text, args)
	return Chaos.t(player, text, unpack(args or {}))
end

function PT.registerService()
	local S = ChaosShopServices
	if S and S.services and not S.services.everfullUpgrade then
		S.services.everfullUpgrade = {
			check = function(player, offer)
				local id = upgradeId(offer)
				if not id then
					return Chaos.t(player, "This offer cannot be bought.")
				end
				local r = PT.upgradeCheck(player, id, "store")
				if not r.ok then
					return problem(player, r.text, r.args)
				end
				return nil
			end,
			apply = function(player, offer)
				local id = upgradeId(offer)
				if not id then
					return Chaos.t(player, "This offer cannot be bought.")
				end
				local ok, text, args = PT.upgrade(player, id, "store")
				if not ok then
					return Chaos.t(player, "%s Your coins were refunded.", problem(player, text, args))
				end
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your Everfull potion is now an %s.",
					PT.everfull(id).name))
				return true
			end
		}
	end
end
PT.registerService()

local svcStartup = GlobalEvent("ChaosPotionUpgradeStartup")
function svcStartup.onStartup()
	PT.registerService()
	return true
end
svcStartup:register()

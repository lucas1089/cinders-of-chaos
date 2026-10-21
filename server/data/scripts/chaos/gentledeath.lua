-- Gentle deaths and the classic blessings (server/README.md "Gentle deaths and blessings"): nobody loses items on death
-- except with a red or black skull; a death of a new character costs little or no experience, and the first death of
-- each day costs half the experience for everyone (the base formula, blessings included, then this softening).
-- !bless buys the missing classic blessings for gold (owner exception to the no-commands rule); the store's Eternal
-- Blessing keeps them for good on one character. Rules: gentledeath_core.lua (pure,
-- tests/gentledeath_test.lua); numbers: gentledeath_config.lua.
--
-- Hooks (both written into base scripts by tools/patch_base_events.py, which keeps the stock rule when this file is
-- missing):
--   step 18  data/events/scripts/player.lua Player:onLoseExperience asks ChaosGentleDeath.onLoseExperience(player, exp)
--            first (and data/events/events.xml has the event on). The engine calls it once per death with the loss it
--            computed (blessings and promotion included); the eased loss goes back to the engine.
--   step 19  data/creaturescripts/scripts/droploot.lua returns before the item loss when ChaosGentleDeath.keepAll(player)
--            (so an amulet of loss is not used up); step 15's hook (ChaosDeathKeep.beforeDrop, death_keep.lua) asks
--            keepAll too, as a second guard.
-- Blessings: TalkAction cfg.bless.words; the store service cfg.eternal.service, put into ChaosShopServices.services at
-- startup (shop_config.lua offer "Eternal Blessing"); a login gives an Eternal Blessing owner the missing blessings.
-- Assumed engine API (TFS 1.4): Player:getLevel/getSkull/getStorageValue/setStorageValue/sendTextMessage, hasBlessing,
-- addBlessing, isPzLocked, hasCondition(CONDITION_INFIGHT), getMoney, getBankBalance, removeMoney, setBankBalance (Chaos.pay), TalkAction.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/gentledeath_core.lua")
ChaosGentleDeathConfig = dofile("data/scripts/chaos/gentledeath_config.lua")

ChaosGentleDeath = ChaosGentleDeath or {}
local GD = ChaosGentleDeath
local G = ChaosGentleDeathCore

local function cfg()
	return ChaosGentleDeathConfig
end

local function log(text)
	print("[Chaos gentle death] " .. text)
end

local function redOrBlack(player)
	local ok, skull = pcall(function() return player:getSkull() end)
	return ok and ((SKULL_RED and skull == SKULL_RED) or (SKULL_BLACK and skull == SKULL_BLACK)) or false
end

local function hardcore(player)
	local S = ChaosSeason
	if S and S.modesOf then
		local ok, f = pcall(S.modesOf, player)
		return ok and type(f) == "table" and f.hc == true
	end
	return false
end

local function tell(player, key, ...)
	if cfg().tell then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, Chaos.t(player, key, ...))
	end
end

-- true when this character keeps every item on this death
function GD.keepAll(player)
	local c = cfg()
	if not c or not c.enabled or not player then
		return false
	end
	return G.keepItems(c, player:getLevel(), redOrBlack(player), hardcore(player))
end

-- the eased experience loss of a death
function GD.ease(player, exp)
	local c = cfg()
	if not c or not c.enabled or not player or (tonumber(exp) or 0) <= 0 then
		return exp
	end
	if hardcore(player) then
		return exp
	end
	local key = c.storage.base + c.storage.firstDeathDay
	local today = G.day(os.time(), c.resetHour)
	local first = player:getStorageValue(key) ~= today and (tonumber(c.firstDeathOfDay) or 1) < 1
	local level = player:getLevel()
	local mult = G.mult(c, level, first)
	local out = G.ease(exp, mult)
	if first then
		player:setStorageValue(key, today)
	end
	if out < exp then
		if out == 0 then
			tell(player, "Gentle death: you lost no experience.")
		elseif first then
			tell(player, "Gentle death: first death of the day, you lost %d%% of the usual experience.", G.percent(mult))
		else
			tell(player, "Gentle death: you lost %d%% of the usual experience.", G.percent(mult))
		end
	end
	if G.keepItems(c, level, redOrBlack(player), false) then
		tell(player, "Gentle death: you keep all your items (only a red or black skull drops them).")
	end
	return out
end

-- Player:onLoseExperience (patch_base_events.py step 18). The engine runs the event for a death (health 0) and for
-- every script's player:removeExperience (health above 0): only a death is eased. Before (playtest 2026-10-16) the
-- tutorial reset could not take the island's experience back below level 30 and told "Gentle death" without a death.
function GD.onLoseExperience(player, exp)
	if player and player.getHealth and (tonumber(player:getHealth()) or 0) > 0 then
		return exp
	end
	local ok, res = pcall(GD.ease, player, exp)
	if not ok then
		log("lose experience: " .. tostring(res))
		return exp
	end
	return res
end

-- ---------------------------------------------------------------- the classic blessings
local function blessIds()
	return (Chaos.shopServices and Chaos.shopServices.blessings) or {1, 2, 3, 4, 5}
end

local function missingOf(player)
	return G.missing(blessIds(), function(id) return player:hasBlessing(id) end)
end

local function inCombat(player)
	return player:isPzLocked() or (CONDITION_INFIGHT ~= nil and player:hasCondition(CONDITION_INFIGHT))
end

local function moneyOf(player)
	return Chaos.totalMoney(player)
end

local function pay(player, gold)
	if gold <= 0 then
		return true
	end
	return Chaos.pay(player, gold) and true or false
end

local function blessAll(player, list)
	for _, id in ipairs(list) do
		player:addBlessing(id)
	end
	pcall(function() player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA) end)
end

-- !bless: true when the blessings were bought
function GD.buyBlessings(player)
	local c = cfg()
	local missing = missingOf(player)
	local each = G.blessCost(c.bless, player:getLevel())
	local gold = each * #missing
	local why = G.blessProblem({inCombat = inCombat(player), missing = #missing, gold = gold, money = moneyOf(player)})
	if why then
		player:sendCancelMessage(Chaos.t(player, why, gold, #missing))
		return false
	end
	if not pay(player, gold) then
		player:sendCancelMessage(Chaos.t(player, "Blessings: you need %d gold (carried or in the bank) for %d blessing(s).",
			gold, #missing))
		return false
	end
	blessAll(player, missing)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR,
		Chaos.t(player, "The gods bless you: %d blessing(s) for %d gold. You have all blessings.", #missing, gold))
	return true
end

local function eternalKey()
	local s = cfg().storage
	return s.base + s.eternal
end

function GD.hasEternal(player)
	return player:getStorageValue(eternalKey()) == 1
end

-- the store service (ChaosShopServices.services[cfg.eternal.service])
GD.eternalService = {
	check = function(player)
		if GD.hasEternal(player) then
			return Chaos.t(player, "You already have the Eternal Blessing.")
		end
		return nil
	end,
	apply = function(player)
		player:setStorageValue(eternalKey(), 1)
		blessAll(player, missingOf(player))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR,
			Chaos.t(player, "The Eternal Blessing is yours: this character keeps all blessings for good."))
		return true
	end
}

function GD.registerService()
	local S = ChaosShopServices
	if S and type(S.services) == "table" then
		S.services[cfg().eternal.service] = GD.eternalService
		return true
	end
	return false
end

-- login: an Eternal Blessing owner gets back the blessings a death took
function GD.login(player)
	if GD.hasEternal(player) then
		local missing = missingOf(player)
		if #missing > 0 then
			blessAll(player, missing)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR,
				Chaos.t(player, "Eternal Blessing: your blessings are back."))
		end
	end
end

local talk = TalkAction(cfg().bless.words)
function talk.onSay(player, words, param)
	if Chaos.limited and Chaos.limited(player, "bless", cfg().bless.rateMs or 2000) then
		return false
	end
	local ok, err = pcall(GD.buyBlessings, player)
	if not ok then
		log("bless: " .. tostring(err))
	end
	return false
end
talk:register()

local login = CreatureEvent("ChaosGentleDeathLogin")
function login.onLogin(player)
	local ok, err = pcall(GD.login, player)
	if not ok then
		log("login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local startup = GlobalEvent("ChaosGentleDeathStartup")
function startup.onStartup()
	if not GD.registerService() then
		log("store service not registered (no ChaosShopServices)")
	end
	return true
end
startup:register()
GD.registerService() -- a /reload after the store is loaded

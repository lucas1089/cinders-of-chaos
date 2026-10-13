-- Chaos Pact (VIP) perks (pact_config.lua perks; rules pact_perks_core.lua; tests server/tests/pact_perks_test.lua).
-- The Pact is the server's VIP subscription (pact.lua: days on the account, sold in the store). While it is active:
--   * one more loadout slot (loadouts.lua asks ChaosPactPerks.loadoutBonus) and the limits of pact_config.lua (one more
--     depot tab, two stash tabs, listings, builds, loot rules)
--   * the Auto Seller and Rarity Autoloot work for every character of the account (their storages set to 2; a bought
--     unlock is 1 and is never touched; the store still sells them: S.unlocks owned = storage 1)
--   * the Pactbound chat colour (taken back when the Pact ends) and the cosmetic of the month (kept for good)
-- No experience bonus. No priority login queue: the engine has no login queue.
-- Applied at login, right after a Pact purchase (ChaosPact.grantDays is wrapped, no edit there) and once a minute for
-- the characters online (a Pact that ran out). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/pact_perks_core.lua")

ChaosPactPerks = ChaosPactPerks or {}
local PP = ChaosPactPerks
local K = ChaosPactPerksCore

local function perks()
	local cfg = Chaos.pactConfig or dofile("data/scripts/chaos/pact_config.lua")
	return cfg.perks
end

local function log(text)
	print("[Chaos pact perks] " .. text)
end

function PP.active(player)
	local P = ChaosPact
	if not (P and P.active) then
		return false
	end
	local ok, active = pcall(P.active, player)
	return ok and active == true
end

function PP.loadoutBonus(player)
	return K.loadoutBonus(perks(), PP.active(player))
end

local function storageOf(name)
	local S = ChaosShopServices
	local u = S and S.unlocks and S.unlocks[name]
	return u and u.storage or nil
end

function PP.apply(player)
	local pk = perks()
	if type(pk) ~= "table" then
		return nil
	end
	local C = ChaosCosmetics
	local acc = player:getAccountId()
	local storages = {}
	for _, name in ipairs(pk.unlocks or {}) do
		local st = storageOf(name)
		if st then
			storages[name] = player:getStorageValue(st)
		end
	end
	local monthlyOwned = {}
	for _, key in pairs(pk.monthly or {}) do
		monthlyOwned[key] = C and C.owns and C.owns(acc, key) or false
	end
	local plan = K.plan(pk, {active = PP.active(player), month = K.month(os.time()), storages = storages,
		chatOwned = C and C.owns and pk.chatColor and C.owns(acc, pk.chatColor) or false, monthlyOwned = monthlyOwned})
	for _, key in ipairs(plan.grant) do
		if C and C.grant then
			C.grant(acc, key, "pact")
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Chaos Pact: a cosmetic for you, see Character > Cosmetics.")
		end
	end
	for _, key in ipairs(plan.revoke) do
		if C and C.revoke then
			C.revoke(acc, key)
		end
	end
	for _, s in ipairs(plan.setStorage) do
		local st = storageOf(s[1])
		if st then
			player:setStorageValue(st, s[2])
		end
	end
	return plan
end

-- the store sells an unlock the Pact lends (storage 2) as not owned yet: only a bought one (1) counts
function PP.installHooks()
	local S = ChaosShopServices
	for _, name in ipairs((perks() or {}).unlocks or {}) do
		local u = S and S.unlocks and S.unlocks[name]
		if u and not u.owned then
			local st = u.storage
			u.owned = function(player)
				return player:getStorageValue(st) == 1
			end
		end
	end
	local P = ChaosPact
	if P and P.grantDays and not P.perksWrapped then
		local original = P.grantDays
		P.grantDays = function(player, days, source)
			local r = {original(player, days, source)}
			if type(player) == "userdata" or type(player) == "table" then
				local ok, err = pcall(PP.apply, player)
				if not ok then
					log("after a purchase: " .. tostring(err))
				end
			end
			return (table.unpack or unpack)(r)
		end
		P.perksWrapped = true
	end
end
PP.installHooks()

local login = CreatureEvent("ChaosPactPerksLogin")
function login.onLogin(player)
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			local ok, err = pcall(PP.apply, p)
			if not ok then
				log("login: " .. tostring(err))
			end
		end
	end, 1500, player:getId())
	return true
end
login:type("login")
login:register()

local think = GlobalEvent("ChaosPactPerksThink")
function think.onThink(interval)
	PP.installHooks()
	for _, p in ipairs(Game.getPlayers()) do
		pcall(PP.apply, p)
	end
	return true
end
think:interval(60000)
think:register()

local startup = GlobalEvent("ChaosPactPerksStartup")
function startup.onStartup()
	PP.installHooks()
	return true
end
startup:register()

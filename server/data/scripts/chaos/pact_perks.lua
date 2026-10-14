-- Chaos Pact (VIP) perks (pact_config.lua perks; rules pact_perks_core.lua; tests server/tests/pact_perks_test.lua).
-- The Pact is the server's VIP subscription (pact.lua: days on the account, sold in the store). While it is active:
--   * +10% experience from monsters (perks.expBonus; EventCallback onGainExperience at perks.expIndex, multiplied like
--     every Chaos bonus and capped by xpcap.lua at index 85; not for season characters)
--   * stamina back x1.5 faster (perks.staminaRegen): offline (base regeneratestamina.lua) and on the stamina trainer
--     tile (base trainer_tile_stamina.lua); tools/patch_base_events.py makes both ask PP.staminaMult / PP.staminaRestMs
--   * one more loadout slot (loadouts.lua asks ChaosPactPerks.loadoutBonus) and the limits of pact_config.lua (one more
--     depot tab, two stash tabs, listings, builds, loot rules)
--   * the Auto Seller works for every character of the account (its storage set to 2; a bought unlock is 1 and is
--     never touched; the store still sells it: S.unlocks owned = storage 1). Rarity Autoloot is no longer lent
--     (perks.retired, owner 2026-10-13): a lent one (2) is taken back, a bought one stays
--   * the Pactbound chat colour (taken back when the Pact ends) and the cosmetic of the month (kept for good)
-- No priority login queue: the engine has no login queue.
-- Applied at login, right after a Pact purchase (ChaosPact.grantDays is wrapped, no edit there) and once a minute for
-- the characters online (a Pact that ran out). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
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

-- a season character (season.lua realm > 0) gets no account-wide boost, as the store's World Experience
local function seasonal(player)
	local S = ChaosSeason
	if not (S and S.realmOf) then
		return false
	end
	local ok, realm = pcall(S.realmOf, player)
	return ok and (tonumber(realm) or 0) > 0
end

function PP.expMult(player)
	if seasonal(player) then
		return 1
	end
	return K.expMult(perks(), PP.active(player))
end

-- read by the base regeneratestamina.lua (offline time x this) and trainer_tile_stamina.lua (patch_base_events.py)
function PP.staminaMult(player)
	local ok, active = pcall(PP.active, player)
	return K.staminaMult(perks(), ok and active)
end

function PP.staminaRestMs(player, ms)
	local ok, active = pcall(PP.active, player)
	return K.restMs(perks(), ok and active, ms)
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
	for _, list in ipairs({pk.unlocks or {}, pk.retired or {}}) do
		for _, name in ipairs(list) do
			local st = storageOf(name)
			if st then
				storages[name] = player:getStorageValue(st)
			end
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
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Chaos Pact: a cosmetic for you, see Character > Cosmetics."))
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

-- the store sells an unlock the Pact lends (storage 2) as not owned yet: only a bought one (1) counts (also for the
-- retired ones, until the next apply takes a lent one back)
function PP.installHooks()
	local S = ChaosShopServices
	local pk = perks() or {}
	local names = {}
	for _, list in ipairs({pk.unlocks or {}, pk.retired or {}}) do
		for _, name in ipairs(list) do
			names[#names + 1] = name
		end
	end
	for _, name in ipairs(names) do
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

-- +10% monster experience while active (index perks.expIndex: after World Experience 5 and the blessing 6, before the
-- experience cap 85)
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if (exp or 0) <= 0 or not source or not source.isMonster or not source:isMonster() then
		return exp
	end
	local ok, mult = pcall(PP.expMult, self)
	if ok and mult and mult ~= 1 then
		return math.floor(exp * mult)
	end
	return exp
end
xpCb:register((perks() or {}).expIndex or 7)

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

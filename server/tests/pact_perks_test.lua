-- Run from the server/ folder: luajit tests/pact_perks_test.lua (and lua5.3; CI runs both)
-- Chaos Pact (VIP) perks (pact_perks_core.lua with the real pact_config.lua, pact_perks.lua on a mocked engine): the
-- plan (chat colour while active, the monthly cosmetic kept, the lent unlocks set to 2 and taken back, a bought unlock
-- never touched), the loadout bonus, the store's owned check (only a bought unlock), the purchase hook.
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

dofile("data/scripts/chaos/pact_perks_core.lua")
local K = ChaosPactPerksCore
local cfg = dofile("data/scripts/chaos/pact_config.lua")
local pk = cfg.perks

-- ---------------------------------------------------------------- config: comfort and cosmetics only
eq(cfg.pact.premiumDays, 0, "no premium days: no experience bonus")
eq(pk.loadoutSlots, 1, "+1 loadout slot")
eq(cfg.limits.depotTabs.pact, 1, "+1 depot tab while active")
eq(pk.chatColor, "chat_pactbound", "the Pact chat colour")
local loadouts = dofile("data/scripts/chaos/loadouts_config.lua") or ChaosLoadoutsConfig
eq((loadouts or ChaosLoadoutsConfig).pactSlots, pk.loadoutSlots, "loadouts_config.lua pactSlots matches")
for k in pairs(pk) do
	check(k ~= "expBonus" and k ~= "damage" and k ~= "lootBonus", "no power perk: " .. k)
end

-- ---------------------------------------------------------------- month and loadouts
eq(K.month(os.time({year = 2026, month = 11, day = 20, hour = 12})), 202611, "month key")
eq(K.loadoutBonus(pk, true), 1, "bonus while active")
eq(K.loadoutBonus(pk, false), 0, "none without")

-- ---------------------------------------------------------------- the plan
local function has(list, x)
	for _, v in ipairs(list) do
		if v == x or (type(v) == "table" and v[1] == x[1] and v[2] == x[2]) then
			return true
		end
	end
	return false
end
local p = K.plan(pk, {active = true, month = 202611, storages = {autoSeller = -1, rarityAutoloot = 1}})
check(has(p.grant, "chat_pactbound"), "active: the chat colour")
check(has(p.grant, "kill_pact_ember"), "active in November 2026: its cosmetic")
check(has(p.setStorage, {"autoSeller", 2}), "the Auto Seller lent (2)")
eq(#p.setStorage, 1, "a bought Rarity Autoloot (1) is not touched")
p = K.plan(pk, {active = true, month = 202611, chatOwned = true, monthlyOwned = {kill_pact_ember = true},
	storages = {autoSeller = 2, rarityAutoloot = 2}})
eq(#p.grant + #p.revoke + #p.setStorage, 0, "nothing to do twice")
p = K.plan(pk, {active = false, month = 202612, chatOwned = true, monthlyOwned = {kill_pact_ember = true},
	storages = {autoSeller = 2, rarityAutoloot = 1}})
check(has(p.revoke, "chat_pactbound"), "ended: the chat colour taken back")
eq(#p.grant, 0, "ended: no monthly cosmetic")
check(has(p.setStorage, {"autoSeller", -1}), "ended: the lent Auto Seller taken back")
eq(#p.setStorage, 1, "the bought one stays")
eq(#p.revoke, 1, "the monthly cosmetic of an earlier month is kept")
p = K.plan(pk, {active = true, month = 203001, chatOwned = true, storages = {}})
eq(#p.grant, 0, "a month without a planned cosmetic: nothing")

-- ---------------------------------------------------------------- pact_perks.lua on a mocked engine
do
	MESSAGE_EVENT_ADVANCE = 19
	dofile("data/scripts/chaos/chaos_constants.lua")
	local registered = {}
	local function event()
		return function(name)
			local e = {name = name}
			function e:register() registered[name] = self end
			function e:type() end
			function e:interval() end
			return e
		end
	end
	CreatureEvent, GlobalEvent = event(), event()
	addEvent = function(fn, _, ...) fn(...) end
	local owned, granted = {}, {}
	ChaosCosmetics = {owns = function(acc, key) return owned[key] == true end,
		grant = function(acc, key, src) owned[key] = true granted[#granted + 1] = key .. ":" .. src end,
		revoke = function(acc, key) owned[key] = nil end}
	ChaosShopServices = {unlocks = {autoSeller = {storage = 7100101}, rarityAutoloot = {storage = 7100106}}}
	local activeUntil = 0
	local purchases = 0
	ChaosPact = {active = function(player) return activeUntil > os.time() end,
		grantDays = function(player, days) purchases = purchases + 1 activeUntil = os.time() + days * 86400 return true end}
	local pl = {st = {}, msgs = {}}
	function pl:getAccountId() return 5 end
	function pl:getId() return 1 end
	function pl:getStorageValue(k) return self.st[k] or -1 end
	function pl:setStorageValue(k, v) self.st[k] = v end
	function pl:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	Player = function() return pl end
	Game = {getPlayers = function() return {pl} end}
	dofile("data/scripts/chaos/pact_perks.lua")
	local PP = ChaosPactPerks
	eq(PP.loadoutBonus(pl), 0, "no Pact: no bonus")
	eq(ChaosShopServices.unlocks.autoSeller.owned(pl), false, "store: not owned")
	-- a Pact purchase applies the perks at once (grantDays wrapped)
	eq(ChaosPact.grantDays(pl, 30, "store"), true, "the wrapped grantDays returns its value")
	eq(purchases, 1, "the original ran")
	eq(PP.loadoutBonus(pl), 1, "Pact: +1 loadout")
	eq(pl.st[7100101], 2, "Auto Seller lent")
	eq(pl.st[7100106], 2, "Rarity Autoloot lent")
	eq(ChaosShopServices.unlocks.autoSeller.owned(pl), false, "a lent unlock can still be bought")
	check(owned.chat_pactbound, "the chat colour granted")
	-- buying the Auto Seller for good while the Pact runs (storage 1)
	pl.st[7100101] = 1
	eq(ChaosShopServices.unlocks.autoSeller.owned(pl), true, "a bought unlock is owned")
	-- the Pact runs out: the minute check takes the lent things back
	activeUntil = 0
	registered.ChaosPactPerksThink.onThink(60000)
	eq(pl.st[7100101], 1, "the bought Auto Seller stays")
	eq(pl.st[7100106], -1, "the lent Rarity Autoloot is taken back")
	eq(owned.chat_pactbound, nil, "the chat colour is taken back")
	-- login with an active Pact again
	activeUntil = os.time() + 3600
	registered.ChaosPactPerksLogin.onLogin(pl)
	eq(pl.st[7100106], 2, "lent again at login")
	check(owned.chat_pactbound, "chat colour again")
end

if failures > 0 then
	error(failures .. " of " .. count .. " checks failed")
end
print("pact_perks_test: " .. count .. " checks OK")

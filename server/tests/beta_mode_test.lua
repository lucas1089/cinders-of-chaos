-- Run from the server/ folder: luajit tests/beta_mode_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Beta test mode (beta_mode_core.lua, beta_mode_config.lua; server/README.md "Beta test mode"): the config is off by
-- default; with it on, every limit of ChaosBetaMode.LIMITS is lifted at the place that enforces it (raid lockout, guild
-- boss, kill tasks, Candlemarks, faction offers, battleground honor, community caps) and back when it is off; the store's
-- weeklyLimit offers (real money) are never in the list. The dungeon cooldown is tested in dungeons_area_test.lua and
-- the store in shop_test.lua.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/chaos_constants.lua")
local B = ChaosBetaMode
ok(B ~= nil, "chaos_constants.lua loads ChaosBetaMode")

-- ---------------------------------------------------------------- the config and the switch
local cfgFile = dofile("data/scripts/chaos/beta_mode_config.lua")
eq(cfgFile.enabled, false, "the shipped config is off")
eq(#cfgFile.storeOfferKeys, 1, "the shipped config names one store offer")
eq(cfgFile.storeOfferKeys[1], "item:32252x1", "the owner lifted the Orb of Binding (2026-10-23)")
eq(Chaos.betaMode.enabled, false, "Chaos.betaMode is off after the start")
ok(not B.enabled(), "B.enabled() is false")
for _, l in ipairs(B.LIMITS) do
	ok(not B.lifted(l.key), l.key .. " is not lifted while off")
end
local function setMode(on, keys)
	Chaos.betaMode = {enabled = on, storeOfferKeys = keys or {}}
end
setMode(true)
ok(B.enabled(), "on")
for _, l in ipairs(B.LIMITS) do
	ok(B.lifted(l.key), l.key .. " is lifted while on")
end
ok(not B.lifted("not_a_limit"), "an unknown key is never lifted")
ok(not B.lifted("store_weekly"), "there is no store key in the list")
eq(#B.LIMITS, 8, "eight limits are lifted (README lists them)")
setMode(false)

-- the store: no weeklyLimit offer is lifted unless the owner names its key
local shop = dofile("data/scripts/chaos/shop_config.lua")
dofile("data/scripts/chaos/shop_core.lua")
local sawLimit = 0
local function walk(cats)
	for _, cat in ipairs(cats or {}) do
		for _, o in ipairs(cat.offers or {}) do
			if o.weeklyLimit then
				sawLimit = sawLimit + 1
				local key = o.key or ChaosShopCore.offerKey(o)
				setMode(true)
				ok(not B.storeLifted(key), "beta mode on: the store limit of " .. key .. " stays")
				setMode(true, {key})
				ok(B.storeLifted(key), "only when the owner names " .. key)
				setMode(false, {key})
				ok(not B.storeLifted(key), "off: even a named offer is capped")
			end
		end
		walk(cat.children or cat.groups or cat.categories)
	end
end
walk(shop.categories or shop.storefront and shop.storefront.categories or shop)
ok(sawLimit >= 5, "the store has weekly limit offers to check: " .. sawLimit)
setMode(false)

-- ---------------------------------------------------------------- raid lockout (raid_core.lua)
dofile("data/scripts/chaos/raid_core.lua")
local RK = ChaosRaidCore
local set = {ulthar = true}
setMode(false)
ok(not RK.eligible(set, "ulthar"), "raid: a looted boss is locked")
setMode(true)
ok(RK.eligible(set, "ulthar"), "raid: beta mode loots every kill")
local split = RK.splitKill("ulthar", {{guid = 1, locked = {ulthar = true}}})
eq(#split.eligible, 1, "raid: splitKill makes a locked player eligible")
setMode(false)

-- ---------------------------------------------------------------- guild boss (guildboss_core.lua)
dofile("data/scripts/chaos/uber_core.lua")
dofile("data/scripts/chaos/guildboss_core.lua")
local GB = ChaosGuildBossCore
local gcfg = dofile("data/scripts/chaos/guildboss_config.lua")
local function ginfo(over)
	local i = {enabled = true, guildId = 4, rank = 3, hasHall = true, rentLocked = false, inHall = true, fuel = 800, need = 750,
		killed = false, attempts = 0, players = 5, running = false}
	for k, v in pairs(over or {}) do i[k] = v end
	return i
end
ok(GB.summonError(ginfo({killed = true}), gcfg) ~= nil, "guild boss: slain this week is refused")
ok(GB.summonError(ginfo({attempts = gcfg.maxAttempts}), gcfg) ~= nil, "guild boss: summons used is refused")
setMode(true)
eq(GB.summonError(ginfo({killed = true}), gcfg), nil, "guild boss: beta mode summons again after the kill")
eq(GB.summonError(ginfo({attempts = gcfg.maxAttempts}), gcfg), nil, "guild boss: beta mode has no summon cap")
ok(GB.summonError(ginfo({fuel = 1}), gcfg) ~= nil, "guild boss: fuel still counts in beta mode")
ok(GB.summonError(ginfo({rank = 1}), gcfg) ~= nil, "guild boss: rank still counts in beta mode")
setMode(false)

-- ---------------------------------------------------------------- kill tasks (bestiary_core.lua)
dofile("data/scripts/chaos/bestiary_core.lua")
local BC = ChaosBestiaryCore or ChaosBestiary
local bcfg = dofile("data/scripts/chaos/bestiary_config.lua")
local C = BC
local function task(key) return {key = key, kind = "hunt", target = key, required = 10} end
local st = {tasks = {}, doneDay = bcfg.dailyLimit, doneWeek = 0, doneKeys = {}}
ok(not C.canAccept(task("h:y"), st, bcfg), "tasks: the daily limit refuses")
st.doneDay, st.doneWeek = 0, bcfg.weeklyLimit
ok(not C.canAccept(task("h:y"), st, bcfg), "tasks: the weekly limit refuses")
setMode(true)
ok(C.canAccept(task("h:y"), st, bcfg), "tasks: beta mode lifts the weekly limit")
st.doneDay, st.doneWeek = bcfg.dailyLimit, 0
ok(C.canAccept(task("h:y"), st, bcfg), "tasks: beta mode lifts the daily limit")
st.tasks = {}
for i = 1, bcfg.maxActive do st.tasks["h:" .. i] = {status = 0} end
ok(not C.canAccept(task("h:z"), st, bcfg), "tasks: the active cap stays in beta mode")
setMode(false)

-- ---------------------------------------------------------------- Candlemarks (candlemarks_core.lua)
local ccfg = dofile("data/scripts/chaos/candlemarks_config.lua")
dofile("data/scripts/chaos/candlemarks_core.lua")
local CK = ChaosCandlemarksCore or ChaosCandlemarks
local offer = {key = "x", kind = "item", price = 1, weekly = 2, minLevel = 1}
local function cctx(used) return {enabled = true, balance = 100, level = 100, used = used, near = true} end
local good, why = CK.checkBuy(offer, cctx(2), ccfg)
ok(not good and why == "weekly", "Candlemarks: the weekly limit refuses")
setMode(true)
ok(CK.checkBuy(offer, cctx(2), ccfg), "Candlemarks: beta mode lifts the weekly limit")
good, why = CK.checkBuy(offer, {enabled = true, balance = 0, level = 100, used = 9, near = true}, ccfg)
ok(not good and why == "balance", "Candlemarks: the price still counts in beta mode")
setMode(false)

-- ---------------------------------------------------------------- faction offers (factions_core.lua)
dofile("data/lib/chaos_item_mods.lua")
local fcfg = dofile("data/scripts/chaos/factions_config.lua")
dofile("data/scripts/chaos/factions_core.lua")
local FK = ChaosFactionsCore
local idx = FK.index(fcfg)
local orbs = idx.offers.vigil_ash5
local full = {ranks = {vigil = 4}, weekly = {vigil_ash5 = orbs.weekly}}
eq((FK.offerState(fcfg, idx, orbs, full)), "soldout", "factions: the weekly limit sells out")
setMode(true)
eq((FK.offerState(fcfg, idx, orbs, full)), "ok", "factions: beta mode sells again")
eq((FK.offerState(fcfg, idx, orbs, {ranks = {vigil = 1}, weekly = {}})), "locked", "factions: the rank still counts")
setMode(false)

-- ---------------------------------------------------------------- battleground honor (battleground_core.lua)
local bgcfg = dofile("data/scripts/chaos/battleground_config.lua")
dofile("data/scripts/chaos/battleground_core.lua")
local BG = ChaosBattlegroundCore
local h = bgcfg.honor
local capped = BG.honorFor(bgcfg, {result = "win", kills = 3, captures = 2}, {earned = h.weeklyCap, firstWinDone = true})
eq(capped, 0, "battleground: the weekly cap pays nothing more")
setMode(true)
local lifted = BG.honorFor(bgcfg, {result = "win", kills = 3, captures = 2}, {earned = h.weeklyCap, firstWinDone = true})
ok(lifted > 0, "battleground: beta mode pays past the cap")
setMode(false)

-- ---------------------------------------------------------------- community goal (community_core.lua)
local comcfg = dofile("data/scripts/chaos/community_config.lua")
dofile("data/scripts/chaos/community_core.lua")
local CM = ChaosCommunityCore
local e = CM.newEntry()
local g1 = CM.credit(comcfg, e, "kill", 3990, 20261010, 100)
local g2 = CM.credit(comcfg, e, "kill", 500, 20261010, 101)
ok(g1 == 3990 and g2 == 10, "community: the kill source stops at its daily cap (" .. tostring(g2) .. ")")
ok(CM.roomToday(comcfg, e, "kill", 20261010) == 0, "community: no room left today")
setMode(true)
eq(CM.credit(comcfg, e, "kill", 500, 20261010, 102), 500, "community: beta mode has no daily cap")
ok(CM.roomToday(comcfg, e, "kill", 20261010) > 1e9, "community: beta mode shows unlimited room")
setMode(false)

print(string.format("beta_mode_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/hunt_test.lua (and lua5.3; CI runs both)
-- Pure logic of the hunt tracker (hunt_core.lua): the session clock with pause / resume / offline / reset, the
-- counters, the corpse snapshot merge, used supplies from two inventory counts, the rates, the time to the next level
-- and the state sent to the client. Uses the real hunt_config.lua and the generated hunt_supplies.lua.
dofile("data/scripts/chaos/hunt_core.lua")
local H = ChaosHunt
local cfg = dofile("data/scripts/chaos/hunt_config.lua")
local supplies = dofile("data/scripts/chaos/hunt_supplies.lua")
local prices = dofile("data/scripts/chaos/sell_prices.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config and price data
eq(type(cfg.coins), "table", "coin values")
eq(cfg.coins[2160], 10000, "crystal coin")
assert(cfg.lootBeforeIndex < 2 and cfg.lootAfterIndex > 2 and cfg.lootAfterIndex < 2.5,
	"corpse read around the index-2 callbacks and before the loot filter snapshot")
assert(cfg.expIndex > 100, "experience read after every bonus")
eq(supplies[7618], 45, "health potion price from the NPCs")
eq(supplies[2389], 2, "spear: the cheapest NPC")
eq(supplies[2544], nil, "no arrows: bows fire without ammunition")
eq(supplies[2260], nil, "unscribed runes are not supplies")
eq(prices[2148], nil, "no NPC buys gold coins: the coin table values them")
for id, price in pairs(supplies) do
	assert(type(id) == "number" and type(price) == "number" and price > 0, "supply price " .. tostring(id))
end

-- ---------------------------------------------------------------- clock
local s = H.new(1000)
eq(H.running(s), true, "starts running")
eq(H.elapsed(s, 1060), 60, "60 s")
H.pause(s, 1060)
eq(H.running(s), false, "paused")
eq(H.elapsed(s, 2000), 60, "paused: the clock stops")
H.resume(s, 2000)
eq(H.elapsed(s, 2030), 90, "resumed")
H.setOnline(s, false, 2030)
eq(H.elapsed(s, 5000), 90, "offline: the clock stops")
eq(s.offlineAt, 2030, "offline since")
H.setOnline(s, true, 5000)
eq(H.elapsed(s, 5010), 100, "back online")
-- paused, then logout and login: stays paused
H.pause(s, 5010)
H.setOnline(s, false, 5010)
H.setOnline(s, true, 6000)
eq(H.running(s), false, "a paused session stays paused after a relog")
eq(H.elapsed(s, 7000), 100, "and its clock stays stopped")
H.resume(s, 7000)
eq(H.elapsed(s, 7005), 105, "resume after relog")
-- resume while offline does not start the clock
H.setOnline(s, false, 7005)
H.resume(s, 7010)
eq(H.running(s), false, "resume while offline")
H.setOnline(s, true, 8000)
eq(H.running(s), true, "runs at login")

-- ---------------------------------------------------------------- counters only while running
s = H.new(0)
H.addExp(s, 1500.7)
H.addKill(s, "Dragon")
H.addKill(s, "Dragon")
H.addKill(s, "Dragon Lord")
H.addDamage(s, 900)
H.addHealing(s, 300)
H.addExp(s, -5)
H.addKill(s, "")
H.pause(s, 10)
H.addExp(s, 999)
H.addKill(s, "Dragon")
H.addDamage(s, 999)
H.addHealing(s, 999)
eq(s.exp, 1500, "experience (floored, negative ignored)")
eq(s.kills["Dragon"], 2, "kills per monster")
eq(s.killCount, 3, "kills total, nothing while paused")
eq(s.damage, 900, "damage")
eq(s.healing, 300, "healing")
H.resume(s, 10)

-- ---------------------------------------------------------------- loot
local function unit(id)
	return H.unitValue(id, prices, cfg.coins, cfg.extraValues)
end
eq(unit(2152), 100, "platinum coin")
eq(unit(7618), 0, "health potion: no NPC buys it")
eq(H.unitValue(5, {[5] = 7}, cfg.coins, {[5] = 9}), 9, "extra value before the NPC price")
eq(H.itemKey(2160, 0, false), "2160:0:0", "key")
eq(H.itemKey(2160, 5, true), "2160:5:1", "key with rarity / unique")

-- first read (before the auto seller): 30 gold, a dragon ham kept, a sold dragon scale mail
local before = {
	["2148:0:0"] = {id = 2148, cid = 3031, name = "gold coin", n = 30},
	["2492:0:0"] = {id = 2492, cid = 3386, name = "dragon scale mail", n = 1}
}
-- second read (after): scale mail sold, paragon gold added coins, a rift key appeared
local after = {
	["2148:0:0"] = {id = 2148, cid = 3031, name = "gold coin", n = 36},
	["9000:0:0"] = {id = 9000, cid = 9001, name = "rift key", n = 1}
}
local merged = H.mergeMax(before, after)
eq(merged["2148:0:0"].n, 36, "larger coin count")
eq(merged["2492:0:0"].n, 1, "sold item still counts")
eq(merged["9000:0:0"].n, 1, "added item counts")
local gold = H.addLoot(s, merged, unit)
eq(gold, 36 + prices[2492], "loot value")
eq(s.lootValue, gold, "session loot value")
H.addLoot(s, {["2148:0:0"] = {id = 2148, name = "gold coin", n = 4}}, unit)
eq(s.loot["2148:0:0"].n, 40, "counts add up")
eq(s.loot["2148:0:0"].cid, 3031, "client id kept")
H.addLoot(s, {["29856:0:0"] = {id = 29856, cid = 1, name = "orb of upheaval", n = 2, o = true},
	["2400:7:0"] = {id = 2400, cid = 2, name = "magic sword", n = 1, r = 7},
	["2400:0:1"] = {id = 2400, cid = 2, name = "soulreaper", n = 1, u = true}}, unit)
eq(H.isSpecial(s.loot["29856:0:0"]), true, "orb is a Chaos drop")
eq(H.isSpecial(s.loot["2400:7:0"]), true, "rarity item is a Chaos drop")
eq(H.isSpecial(s.loot["2148:0:0"]), false, "coins are not")
eq(s.loot["2400:7:0"].value, prices[2400] or 0, "rarity item: NPC price of the base item")
H.pause(s, 10)
eq(H.addLoot(s, merged, unit), 0, "no loot while paused")
H.resume(s, 10)

-- ---------------------------------------------------------------- supplies
local used = H.supplyUsed({[7618] = 50, [2389] = 200, [7620] = 10}, {[7618] = 42, [2389] = 300})
eq(used[7618], 8, "8 potions used")
eq(used[2389], nil, "bought spears are not used")
eq(used[7620], 10, "last mana potions used")
eq(next(H.supplyUsed(nil, {[7618] = 3})), nil, "first count: nothing used")
eq(H.addSupply(s, 7618, 8, supplies[7618], 266, "health potion"), 8 * 45, "supply value")
H.addSupply(s, 7618, 2, supplies[7618], 266, "health potion")
H.addSupply(s, 2268, 3, 50 / 3, 3155, "reaper's rune")
eq(s.supplies[7618].n, 10, "supply count")
eq(s.supplies[2268].value, 50, "per-charge price rounds")
eq(s.supplyValue, 450 + 50, "supply total")
eq(H.addSupply(s, 7618, 0, 45), 0, "zero used")

-- ---------------------------------------------------------------- levels and rates
local function tfsExp(lv) -- the engine formula, Player::getExpForLevel
	lv = lv - 1
	return math.floor(((50 * lv * lv * lv) - (150 * lv * lv) + (400 * lv)) / 3)
end
for _, lv in ipairs({1, 2, 8, 50, 100, 499, 500, 1000, 1500}) do
	eq(H.expForLevel(lv), tfsExp(lv), "exp for level " .. lv)
end
eq(H.perHour(1000, 1800, 30), 2000, "per hour")
eq(H.perHour(1000, 20, 30), 0, "too early for a rate")
eq(H.perHour(-500, 3600, 30), -500, "negative rate (profit)")
eq(H.timeToLevel(1000, 2000), 1800, "half an hour to level")
eq(H.timeToLevel(1000, 0), -1, "no rate")

-- ---------------------------------------------------------------- state
local st = H.state(s, 3600, {exp = H.expForLevel(100) + 10, level = 100, minRateSeconds = 30, maxKills = 1,
	maxLoot = 2, maxSupplies = 5, maxSpecials = 2})
eq(st.t, 3600, "session time")
eq(st.p, 0, "not paused")
eq(st.xp, 1500, "exp")
eq(st.xph, 1500, "exp/h")
eq(st.left, H.expForLevel(101) - H.expForLevel(100) - 10, "exp left")
eq(st.ttl, math.ceil(st.left * 3600 / 1500), "time to level")
eq(st.lv, s.lootValue, "loot value")
eq(st.pf, s.lootValue - 500, "profit")
eq(st.pfh, s.lootValue - 500, "profit/h after one hour")
eq(st.kc, 3, "kills total")
eq(#st.k, 1, "kill rows capped")
eq(st.k[1][1], "Dragon", "most killed first")
eq(st.k[1][2], 2, "its count")
eq(#st.l, 2, "loot rows capped")
assert(st.l[1][3] >= st.l[2][3], "loot sorted by value")
eq(st.s[1][4], "health potion", "most expensive supply first")
eq(#st.x, 2, "Chaos drops capped")
eq(st.x[1][3], "soulreaper", "uniques first")
eq(st.x[2][3], "magic sword", "then by rarity")
eq(st.dps, math.floor(900 / 3600), "damage per second")

-- ---------------------------------------------------------------- reset and sweep
H.reset(s, 4000)
eq(s.exp, 0, "reset exp")
eq(s.lootValue, 0, "reset loot")
eq(next(s.kills), nil, "reset kills")
eq(H.elapsed(s, 4010), 10, "reset clock")
H.pause(s, 4010)
H.reset(s, 4020)
eq(H.running(s), false, "a paused session stays paused after a reset")
eq(H.elapsed(s, 5000), 0, "at zero")

local sessions = {a = H.new(0), b = H.new(0), c = H.new(0)}
H.setOnline(sessions.a, false, 100)
H.setOnline(sessions.b, false, 1500)
eq(H.sweep(sessions, 2000, 1800), 1, "one dropped")
eq(sessions.a, nil, "offline for too long")
assert(sessions.b and sessions.c, "recent and online kept")

print("hunt_test: OK")

-- Run from the server/ folder: luajit tests/unique_hunt_test.lua (and lua5.3; CI runs both)
-- O148: do Rare and Legendary monsters drop uniques in the level-scaled hunts? Beta 2026-10-23: about 1000 Rare and
-- Legendary kills standing in hunts, never a unique. Root causes found with this test:
--   1. the endgame uniques (minMonsterLevel 1000) listed twelve waystone monsters, so no hunt monster could drop one;
--   2. the unique roll read the thin per-kill loot factor of the pack (0.15-0.2 in the late sets) while every other
--      notable drop keeps the "notable" share (1 from monster level 700);
--   3. processKill passed the monster's own getMonsterLevel (0 for a base or waystone monster) to the minMonsterLevel gate.
-- Fixes: loot_config.lua unique.open (an entry with a minMonsterLevel drops from any monster of that level, at mult x),
-- L.uniquePace (the notable share), the level of the orb gate. The numbers below are exact sums over the entries of
-- ChaosUniqueItems (L.rollUniques sampled with a fixed generator agrees within the tolerance).

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

Chaos = {}
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
setmetatable(_G, {__index = function(_, k)
	if type(k) == "string" and k:match("^ITEM_ATTRIBUTE_") then return k end
end})
dofile("data/lib/chaos_item_mods.lua")
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
dofile("data/scripts/chaos/loot.lua")
dofile("data/scripts/chaos/pace_core.lua")
local L, C = ChaosLoot, ChaosLootConfig
local PC = dofile("data/scripts/chaos/pace_config.lua")
local P = ChaosPaceCore
local u = C.unique

-- hunt monsters of the level-scaled late sets (tools/late_game_spawns.csv) and a name no list knows
local HUNT = {"Azure Dragon", "Golden Lord", "Dawn Strayer", "Blazebringer", "Garack", "Frost Maiden", "Tundra Troll",
	"Shaper Matriarch", "Orclops Ravager", "Dreamgorger", "Loricate Orger", "Swamp Snapper"}
local LEVEL = 1500

-- exact expected uniques per kill: at most one drops (maxPerKill 1), so 1 - prod(1 - p) of the entries' chances
local function perKill(tier, name, level, pace, openEnabled, openMult)
	local saved = u.open
	u.open = {enabled = openEnabled, mult = openMult or 1}
	local mult = u.tierMult[tier]
	local rank = u.tierRank[tier]
	local none, n = 1, 0
	for _, e in ipairs(L.uniqueList()) do
		local good = rank >= (u.tierRank[e.minTier] or 0) and not (e.bossOnly and tier ~= "boss")
		if good and e.minMonsterLevel and level < e.minMonsterLevel then good = false end
		local open = false
		if good then
			local listed = false
			if type(e.monsters) ~= "table" or next(e.monsters) == nil then
				listed = true
			else
				for _, m in ipairs(e.monsters) do
					if m:lower() == name:lower() then listed = true end
				end
			end
			if not listed then
				if e.minMonsterLevel and openEnabled and not e.bossOnly then open = true else good = false end
			end
		end
		if good and not e.season then
			local p = math.min(u.maxChance, e.chance * mult * pace * (open and (openMult or 1) or 1)) / 10000
			none = none * (1 - p)
			n = n + 1
		end
	end
	u.open = saved
	return 1 - none, n
end

-- the loot factor of a level 1500 scaled monster (pace_core.lua P.factors) and its notable share
local f = P.factors(PC, LEVEL, true, false)
ok(f.loot > 0.1 and f.loot < 0.3, "the level 1500 loot factor is thin: " .. f.loot)
ok(f.notable == 1, "the notable share is 1 from monster level 700")
ok(L.uniquePace(f.loot, {notable = f.notable}) == 1, "a unique keeps the notable share of a paced corpse")
ok(L.uniquePace(0.2, nil) == 0.2, "no corpse factors: the loot factor")
ok(L.uniquePace(0.2, {notable = 0.1}) == 0.2, "never below the loot factor")
ok(L.uniquePace(nil, nil) == 1, "no pace: 1")

-- the rare / legendary mix of the kills: spawns 150 : 25 of 10000 (monster_tiers.lua spawnChance)
local RARE_W, LEG_W = 150, 25
local function per1000(openEnabled, openMult, pace)
	local sum, total = 0, 0
	for _, name in ipairs(HUNT) do
		local pr = perKill("rare", name, LEVEL, pace, openEnabled, openMult)
		local pl = perKill("legendary", name, LEVEL, pace, openEnabled, openMult)
		sum = sum + (pr * RARE_W + pl * LEG_W) / (RARE_W + LEG_W)
		total = total + 1
	end
	return sum / total * 1000
end

local before = per1000(false, 1, f.loot)
local afterOpenOnly = per1000(true, 1, f.loot)
local after = per1000(true, u.open.mult, 1)
print(string.format("level %d, per 1000 Rare / Legendary kills (mix %d:%d): before %.2f, open only %.2f, now %.2f",
	LEVEL, RARE_W, LEG_W, before, afterOpenOnly, after))
ok(before < 1, "before: the hunt monsters of level 1500 dropped (almost) no unique: " .. before)
-- a dedicated farmer: about 17 Rare / Legendary kills an hour in the late sets (kills per hour x the spawn chance), one
-- unique every 2-5 hours = 8.5-20 per 1000 kills... counted per 1000 kills of ONE hunter's Rare+ kills
local perHour = 17
local hours = 1000 / after / perHour
print(string.format("expected: one unique every %.1f Rare / Legendary kills, every %.1f hours at %d an hour",
	1000 / after, hours, perHour))
ok(after >= 10 and after <= 25, "now: " .. after .. " uniques per 1000 Rare / Legendary kills (10-25)")
ok(hours >= 2.5 and hours <= 6, "a dedicated farmer sees one every 1.5-7 hours: " .. hours)

-- a magic or normal kill: normal never, magic a fraction
ok(perKill("normal", "Azure Dragon", LEVEL, 1, true, u.open.mult) == 0, "normal monsters drop no unique")
ok(perKill("legendary", "Azure Dragon", 999, 1, true, u.open.mult) < perKill("legendary", "Azure Dragon", LEVEL, 1, true, u.open.mult),
	"below the entries' minimum level the open drops are gone")

-- the real function agrees with the exact sum (fixed generator): Rare, level 1500, an unlisted name
do
	local seed = 7
	math.randomseed(seed)
	L.setRandom(function(a, b) return math.random(a, b) end)
	local want, got, kills = perKill("rare", "Swamp Snapper", LEVEL, 1, true, u.open.mult), 0, 12000
	for _ = 1, kills do
		got = got + #L.rollUniques("rare", "Swamp Snapper", LEVEL, 1, nil, nil)
	end
	got = got / kills
	ok(math.abs(got - want) < 0.35 * want + 0.0005, string.format("rollUniques %.5f vs exact %.5f", got, want))
	L.setRandom(nil)
end

-- the open rule: boss-only entries and entries without a minimum level keep their lists
do
	local list = {
		{id = 9101, name = "Hunt Blade", minTier = "rare", chance = 100, minMonsterLevel = 1000, monsters = {"Waystone Thing"}},
		{id = 9102, name = "Listed Blade", minTier = "rare", chance = 100, monsters = {"Waystone Thing"}},
		{id = 9103, name = "Boss Crown", minTier = "boss", chance = 100, bossOnly = true, minMonsterLevel = 1000,
			monsters = {"Waystone Thing"}}
	}
	L.setRandom(function(a, b) return a end) -- every roll hits
	local hits = L.rollUniques("boss", "Azure Dragon", 1500, 1, list, nil)
	ok(#hits == 1 and hits[1].id == 9101, "an unlisted boss: only the open entry can drop")
	hits = L.rollUniques("rare", "Azure Dragon", 999, 1, list, nil)
	ok(#hits == 0, "below its minimum level an open entry stays home")
	hits = L.rollUniques("rare", "Waystone Thing", 1500, 1, list, nil)
	ok(#hits == 1, "a listed monster still drops (one per kill)")
	local saved = u.open
	u.open = {enabled = false, mult = 1}
	hits = L.rollUniques("rare", "Azure Dragon", 1500, 1, list, nil)
	ok(#hits == 0, "open disabled: the lists hold again")
	u.open = saved
	L.setRandom(nil)
end

-- the endgame uniques that come open: at least ten drop at level 1500, none below 800
do
	local n = 0
	for _, e in ipairs(L.uniqueList()) do
		if e.minMonsterLevel and not e.bossOnly and e.minMonsterLevel <= LEVEL then n = n + 1 end
	end
	ok(n >= 10, "ten or more open uniques at level 1500: " .. n)
end

print(string.format("unique_hunt_test: %d of %d failed", fails, checks))
os.exit(fails == 0 and 0 or 1)

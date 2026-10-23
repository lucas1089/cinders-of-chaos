-- Run from the server/ folder: luajit tests/content_rewards_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Content rewards (content_rewards_core.lua / _config.lua, server/README.md "Content rewards") and the rift key ladder
-- (rift_core.lua R.keyGuarantee / R.rollKeyDrop with a receiver: the pity counter and the outlevelled fast step).
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/content_rewards_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local K, R = ChaosContentRewardsCore, ChaosRiftCore
local cfg = dofile("data/scripts/chaos/content_rewards_config.lua")
local rcfg = dofile("data/scripts/chaos/rift_config.lua")
local wcfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
local G = dofile("data/lib/chaos_gear_sets_items.lua")
local crafting = io.open("data/lib/chaos_crafting.lua"):read("*a")

math.randomseed(7)
local rand = math.random

-- ================================================================ waystones: gear
for t = 1, #wcfg.tiers do
	local level = wcfg.tiers[t].level
	local piece = K.pickPiece(cfg, G.pieces, level, rand)
	ok(piece ~= nil, "tier " .. t .. ": a set piece for level " .. level)
	if piece then
		ok(piece.level <= level or t > 10, "tier " .. t .. ": piece level " .. piece.level .. " not above the run's")
	end
	if t > 1 then
		ok(K.waystoneGearChance(cfg, t, "normal", 1) > K.waystoneGearChance(cfg, t - 1, "normal", 1), "gear chance rises with the tier")
		ok(K.waystoneRarityFind(cfg, t) > K.waystoneRarityFind(cfg, t - 1), "rarity find rises with the tier")
		ok(K.waystoneQuantity(cfg, t) > K.waystoneQuantity(cfg, t - 1), "quantity rises with the tier")
	end
end
eq(K.waystoneGearChance(cfg, 1, "normal", 1), 250, "tier 1 normal: 2.5%")
eq(K.waystoneGearChance(cfg, 15, "legendary", 5), cfg.waystone.gear.maxChance, "the chance is capped")
ok(K.waystoneGearChance(cfg, 1, "rare", 1) == 5 * K.waystoneGearChance(cfg, 1, "normal", 1), "rare monsters x5")

-- every set of the config exists and has pieces
for _, s in ipairs(cfg.waystone.sets) do
	ok(G.sets[s] ~= nil, "set " .. s)
end
-- a trickle piece is always Rare or better, the boss table Legendary or better
for _ = 1, 500 do
	ok(K.pickRarity(cfg.waystone.rarity, rand, 3) >= 4, "waystone pieces are Rare or better")
	local r = K.pickRarity(cfg.waystone.boss.rarity, rand, 3)
	ok(r == 5 or r == 10, "boss pieces are Legendary or Divine")
end

-- the boss table: always pieces, unique rolls, the orbs of 100% always, the same-tier waystone
for t = 1, 15 do
	local plan = K.waystoneBoss(cfg, t, 1, rand)
	ok(plan.pieces >= 3 and plan.pieces <= 9, "tier " .. t .. ": boss pieces " .. plan.pieces)
	ok(plan.uniqueRolls >= 2, "tier " .. t .. ": unique rolls")
	eq(plan.waystones, 1, "tier " .. t .. ": a same-tier waystone")
	local seen = {}
	for _, o in ipairs(plan.orbs) do
		seen[o.id] = o.count
		ok(o.count >= 1, "orb count")
	end
	ok(seen[29851] and seen[24691], "tier " .. t .. ": Awakening and Gilding always")
end
ok(K.waystoneBoss(cfg, 15, 1, rand).pieces >= K.waystoneBoss(cfg, 1, 1, rand).pieces, "a higher tier boss pays no less")

-- the orbs exist in the crafting library (the ids of the config)
for _, list in ipairs({cfg.waystone.boss.orbs, cfg.rift.orbs}) do
	for _, o in ipairs(list) do
		ok(crafting:find("id = " .. o.id .. ",", 1, true) ~= nil, "orb " .. o.name .. " (" .. o.id .. ") is in chaos_crafting.lua")
	end
end

-- the trickle keeps the loop going: over 100000 normal kills of a tier 5 run, some waystones, far fewer than kills
local ways, pieces = 0, 0
for _ = 1, 100000 do
	local p = K.waystoneKill(cfg, 5, "normal", 1, rand)
	ways = ways + (p.waystone and 1 or 0)
	pieces = pieces + (p.piece and 1 or 0)
end
ok(ways > 200 and ways < 800, "trickle waystones per 100000 kills: " .. ways)
ok(pieces > 2000 and pieces < 4500, "pieces per 100000 normal kills at tier 5: " .. pieces)

-- ================================================================ rifts: orbs
for t = 1, 15 do
	ok(K.riftOrbChance(cfg, t, "normal", 1) > 0, "rift tier " .. t .. ": orb chance")
	local g = K.riftGuardian(cfg, t, 1, rand)
	local n = 0
	for _, o in ipairs(g.orbs) do
		n = n + o.count
	end
	ok(n >= 4, "rift tier " .. t .. ": the guardian pays at least 4 orbs (" .. n .. ")")
end
local hits = 0
for _ = 1, 100000 do
	hits = hits + (K.riftKill(cfg, 10, "normal", 1, rand) and 1 or 0)
end
ok(hits > 3000 and hits < 5000, "tier 10 orb kills per 100000: " .. hits)
-- rifts pay no gear and waystones no trickle orbs: the identity is separate
ok(cfg.rift.guardian ~= nil and cfg.waystone.boss.orbs[1].id == 29851, "waystone boss orbs are the waystone orbs")

-- ================================================================ the rift key ladder
local kd = rcfg.keyDrop
ok(kd.pity and kd.pity.runs >= 1 and kd.pity.outlevel > 1 and kd.pity.maxJump >= 1, "keyDrop.pity configured")
eq(R.fitTier(rcfg, 50), 1, "fit tier of level 50")
eq(R.fitTier(rcfg, 900), 10, "fit tier of level 900 is the highest key tier whose entry level it has")
eq(R.fitTier(rcfg, 1500), 15, "fit tier of level 1500: the last tier")
eq(R.fitTier(rcfg, 925), 11, "fit tier past the table (beyond.minLevelStep)")
-- no receiver: the plain roll; a pity of 0 or 1 and a fitting level: the plain roll
ok(R.keyGuarantee(rcfg, 1, 100, 0) == nil, "no guarantee at the entry level")
ok(R.keyGuarantee(rcfg, 1, 100, 1) == nil, "no guarantee after one miss")
eq(R.keyGuarantee(rcfg, 1, 100, kd.pity.runs), 2, "the third run is guaranteed tier + 1 (pity)")
-- the player report: level 1000 in a tier 1 rift
local fast = R.keyGuarantee(rcfg, 1, 1000, 0)
eq(fast, 1 + kd.pity.maxJump, "a level 1000 character in tier 1 jumps maxJump tiers")
eq(R.keyGuarantee(rcfg, 8, 1000, 0), nil, "tier 8 at level 1000 is no fast step")
eq(R.keyGuarantee(rcfg, 15, 5000, 0), nil, "no key above the last tier")
ok(R.keyGuarantee(rcfg, 1, 1000, 5, {keyChanceMult = 0.5}) == nil, "the Ashen Ascent keystone turns the guarantee off")
-- six tier 1 runs never leave the player without a stronger key
for level in pairs({[100] = true, [800] = true, [1500] = true}) do
	local pity, got = 0, false
	for run = 1, 3 do
		local key = R.rollKeyDrop(rcfg, 1, 1, rand, nil, {level = level, pity = pity})
		if key and key.tier > 1 then
			got = true
			break
		end
		pity = pity + 1
	end
	ok(got, "level " .. level .. ": a stronger key within three tier 1 runs")
end
local key = R.rollKeyDrop(rcfg, 1, 1, rand, nil, {level = 1500, pity = 0})
ok(key and key.tier == 4 and key.guaranteed, "level 1500 in tier 1: a tier 4 key, guaranteed")
-- without a receiver the old RNG rule holds (55% x 70% = 38.5% tier + 1 for a three-tier key with one modifier)
local up = 0
for _ = 1, 20000 do
	local k = R.rollKeyDrop(rcfg, 3, 1, rand)
	up = up + ((k and k.tier == 4) and 1 or 0)
end
ok(up > 20000 * 0.34 and up < 20000 * 0.43, "the plain tier + 1 rate about 38%: " .. up / 200 .. "%")

-- ================================================================ the engine file against a mocked loot layer
do
	local added, attrs = {}, {}
	local L = {
		addToCorpse = function(_, id, n)
			added[#added + 1] = {id = id, n = n}
			local item = {}
			function item:setCustomAttribute(k, v) attrs[#attrs + 1] = {k, v} end
			return item, n
		end,
		rollUniques = function() return {} end
	}
	ChaosGearSets = {items = G}
	local entry = {run = 5, boss = false}
	ChaosWaystoneTiers = {config = wcfg, entryOf = function() return entry end,
		addWaystone = function(_, t) added[#added + 1] = {waystone = t} end}
	ChaosWaystoneMods = {lootMult = function() return 1 end}
	ChaosContentRewards = nil
	dofile("data/scripts/chaos/content_rewards.lua")
	local CRe = ChaosContentRewards
	local monster = {getMaster = function() return nil end, getName = function() return "Test" end}
	local corpse = {}
	local ctx = {tier = "rare", orbLevel = 1500, itemFind = 1}
	-- a boss kill: pieces, the same-tier waystone, Awakening and Gilding
	entry.boss = true
	local bonus = {}
	ok(CRe.onKill(monster, corpse, {}, ctx, L, bonus) == true, "a boss kill pays")
	local ids, ways = {}, 0
	for _, a in ipairs(added) do
		if a.waystone then ways = ways + 1 else ids[a.id] = (ids[a.id] or 0) + a.n end
	end
	ok(ids[29851] and ids[24691], "the boss corpse gets Awakening and Gilding")
	eq(ways, 1, "the boss corpse gets a same-tier waystone")
	ok(#attrs >= 3, "the boss pieces get a rarity (" .. #attrs .. ")")
	for _, a in ipairs(attrs) do
		ok(a[1] == "rarity" and (a[2] == 5 or a[2] == 10), "boss piece rarity " .. tostring(a[2]))
	end
	ok(#bonus >= 3, "the loot line names them")
	-- a summon pays nothing
	added, attrs = {}, {}
	monster.getMaster = function() return {} end
	ok(CRe.onKill(monster, corpse, {}, ctx, L, {}) == false and #added == 0, "a summon pays nothing")
	-- outside any content nothing is paid
	monster.getMaster = function() return nil end
	ChaosWaystoneTiers.entryOf = function() return nil end
	ChaosRift = nil
	ok(CRe.onKill(monster, corpse, {}, ctx, L, {}) == false and #added == 0, "no content: nothing")
	-- a rift guardian
	ChaosRift = {contentOf = function() return {tier = 10, quantity = 1, guardian = true, omen = false} end}
	local n = 0
	CRe.onKill(monster, corpse, {}, ctx, L, {})
	for _, a in ipairs(added) do n = n + (a.n or 0) end
	ok(n >= 4, "the rift guardian drops orbs (" .. n .. ")")
	-- an omen arena pays nothing here
	added = {}
	ChaosRift = {contentOf = function() return {tier = 10, quantity = 1, guardian = true, omen = true} end}
	ok(CRe.onKill(monster, corpse, {}, ctx, L, {}) == false and #added == 0, "an omen arena keeps its own chest")
	-- the run tier's own bonus
	ChaosWaystoneTiers.entryOf = function() return {run = 15, boss = false} end
	ok(CRe.waystoneQuantity(monster) > 1.2 and CRe.waystoneRarityFind(monster) > 60, "the run tier's own quantity and rarity find")
end

print(string.format("content_rewards_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

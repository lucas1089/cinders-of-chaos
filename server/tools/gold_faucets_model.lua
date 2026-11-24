-- The gold faucets against the one gold curve (O754; server/README.md "Gold faucets against the curve (O754)").
-- Every content that pays gold of its own (a chest, the bank, bonus coins) at the levels it is played: its gold an hour,
-- the corpse gold of its kills (a share of a hunt's), and the sum against hunt_gold_config.lua `hunting` at that level.
--
--     cd server && luajit tools/gold_faucets_model.lua            the table (also lua5.3)
--     cd server && luajit tools/gold_faucets_model.lua --check    exit 1 when a faucet pays more than `limit` x the curve
--
-- Inputs and limits: data/scripts/chaos/gold_faucets_balance_config.lua (the reason of every number). The gold comes from
-- the content's own configs and pure cores (rift_core R.reward / R.omenReward / R.greater*, uber_core U.reward, descent_core
-- D.reward, trials_core M.clearOutcome, bounty_core B.reward, dungeons_difficulty D.chest), so a resized faucet moves here.
-- Expected values, no random numbers. Computed, not measured in game.
-- A test can load it as a library: ChaosGoldFaucetsLib = true; local M = dofile("tools/gold_faucets_model.lua").

local floor, max, min = math.floor, math.max, math.min

local BC = dofile("data/scripts/chaos/gold_faucets_balance_config.lua")
local HUNT = dofile("data/scripts/chaos/hunt_gold_config.lua").hunting

dofile("data/scripts/chaos/chaos_constants.lua")
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/scripts/chaos/rift_core.lua")
local R = ChaosRiftCore
local uberCfg = dofile("data/scripts/chaos/uber_config.lua")
dofile("data/scripts/chaos/uber_core.lua")
local U = ChaosUberCore
local raidCfg = dofile("data/scripts/chaos/raid_config.lua")
local invCfg = dofile("data/scripts/chaos/invasion_config.lua")
local bountyCfg = dofile("data/scripts/chaos/bounty_config.lua")
local B = dofile("data/scripts/chaos/bounty_core.lua")
local bestCfg = dofile("data/scripts/chaos/bestiary_config.lua")
local descCfg = dofile("data/scripts/chaos/descent_config.lua")
dofile("data/scripts/chaos/descent_core.lua")
local DC = ChaosDescentCore
Chaos.trials = Chaos.trials or dofile("data/scripts/chaos/trials_config.lua")
dofile("data/scripts/chaos/trials_core.lua")
local T = ChaosTrialsCore
local DD = dofile("data/scripts/chaos/dungeons_difficulty.lua")
local areaCfg = dofile("data/scripts/chaos/areagen_config.lua")
local siegeCfg = dofile("data/scripts/chaos/siege_config.lua")
local gobCfg = dofile("data/scripts/chaos/treasure_goblin_config.lua")
local towerCfg = dofile("data/scripts/chaos/infinitytower_balance_config.lua")

local M = {}

-- linear between the points, flat beyond
local function lerp(points, x)
	if x <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end
M.lerp = lerp

function M.hunt(level)
	return lerp(HUNT, level)
end

local function levelsFrom(lo, hi)
	local out = {}
	for _, L in ipairs(BC.levels) do
		if L >= lo and L <= (hi or math.huge) then
			out[#out + 1] = L
		end
	end
	if #out == 0 or out[1] > lo then
		table.insert(out, 1, lo)
	end
	return out
end

local function rand0(a)
	return a -- the low end of every roll (the gold of the cores below is not rolled)
end

-- a row: {group, name, level, own gold an hour, kills (share of a hunt), ratio, note}
local rows = {}
local function add(group, name, level, own, kills, note)
	local h = M.hunt(level)
	rows[#rows + 1] = {group = group, name = name, level = level, own = own, kills = kills, hunt = h,
		ratio = own / h + kills, note = note}
end

-- ------------------------------------------------------------------ rifts
local rc = BC.rift

-- one finisher's chest gold at tier t with the checked key and atlas, n players
local function riftChest(t, n)
	local r = R.reward(riftCfg, t, {quantity = rc.quantity}, rand0)
	R.atlasReward(riftCfg, r, rc.atlas.own, rc.atlas.run, rand0)
	R.partyReward(riftCfg, r, n, rand0)
	return r.gold
end

local function riftRunSeconds(t, n)
	return R.clearSeconds(riftCfg, t, n, n > 1 and rc.partyDps or 1) + rc.around
end

function M.rifts()
	for t = 1, riftCfg.maxTier do
		local L = R.tierInfo(riftCfg, t).minLevel
		for _, n in ipairs({1, BC.party}) do
			local runs = 3600 / riftRunSeconds(t, n)
			add("rift", string.format("Rift tier %d, %s", t, n == 1 and "solo" or "party of " .. n), L,
				riftChest(t, n) * runs, rc.kills, "orbs, keys, uniques, Omen Fragments")
		end
	end
end

-- the tier 15 loop: rift runs, and the Omen keys, Ascended Sigils and Cinderheart Sigils they drop, spent as they come.
-- Per rift run: f fragments (chest.base + perTier x (15 - minTier), x quantity, x party; the elites' fragments left out),
-- f / keyCost Omen kills, shards (the rift's chance and the Omen's), shards / shardCost Ascended kills, a third of those
-- Cinderheart kills (three relics). Kills pay corpse gold only during the rift runs.
function M.loop(L, n)
	local t = riftCfg.maxTier
	local o = riftCfg.omen
	local party = R.party(riftCfg, n).reward
	local q = 1 + rc.quantity / 100
	local frag = (o.chest.base + o.chest.perTier * (t - o.minTier)) * q * party
	local omens = frag / o.keyCost
	local up = U.party(uberCfg, n).reward
	local shards = uberCfg.shardChance.rift[t] / 100 * up + omens * uberCfg.shardChance.omen / 100 * up
	local asc = shards / uberCfg.shardCost
	local cinder = asc / 3
	local runS = riftRunSeconds(t, n)
	local omenGold = R.omenReward(riftCfg, L).gold * party
	local ascGold = U.reward(uberCfg, {final = false}, n, rand0).gold
	local cinderGold = U.reward(uberCfg, {final = true}, n, rand0).gold
	local gold = riftChest(t, n) + omens * omenGold + asc * ascGold + cinder * cinderGold
	local seconds = runS + omens * rc.omenSeconds + asc * rc.ascendedSeconds + cinder * rc.cinderSeconds
	local tierLevel = R.tierInfo(riftCfg, t).minLevel
	-- the kills pay a hunt of the tier's monsters (their level), over the share of the time spent in rift runs
	local kills = rc.kills * runS / seconds * M.hunt(math.min(L, tierLevel)) / M.hunt(L)
	return gold * 3600 / seconds, kills, {omens = omens, asc = asc, cinder = cinder}
end

function M.loops()
	for _, L in ipairs(levelsFrom(R.tierInfo(riftCfg, riftCfg.maxTier).minLevel)) do
		for _, n in ipairs({1, BC.party}) do
			local own, kills, k = M.loop(L, n)
			add("rift", string.format("Tier 15 loop with Omen, Ascended, Cinderheart, %s", n == 1 and "solo" or "party of " .. n),
				L, own, kills, string.format("per run %.2f Omen, %.3f Ascended, %.3f Cinderheart kills", k.omens, k.asc, k.cinder))
		end
	end
end

-- the Greater Rift at the shown tier the median class reaches: the tier 15 chest x the gold factor, and while climbing the
-- personal-best gold (at most maxPerRun tiers a run)
function M.greater()
	local g = riftCfg.greater
	for _, p in ipairs(rc.greaterReach) do
		local L, shown, s = p[1], p[2], p[3]
		local gg = shown - riftCfg.maxTier
		for _, n in ipairs({1, BC.party}) do
			local r = R.reward(riftCfg, riftCfg.maxTier, {quantity = rc.quantity}, rand0)
			R.atlasReward(riftCfg, r, rc.atlas.own, rc.atlas.run, rand0)
			R.greaterReward(riftCfg, r, gg, rand0)
			R.partyReward(riftCfg, r, n, rand0)
			local runs = 3600 / (s + rc.around)
			add("rift", string.format("Greater Rift tier %d, %s", shown, n == 1 and "solo" or "party of " .. n), L,
				r.gold * runs, rc.kills, "orbs, keys, pinnacle fragments")
		end
		local best = 0
		for _, b in ipairs(R.greaterBestRewards(riftCfg, shown - g.rewards.maxPerRun, shown)) do
			best = best + b.gold
		end
		add("rift", string.format("Greater Rift climb (best tiers %d-%d in one run)", shown - g.rewards.maxPerRun + 1, shown),
			L, best * 3600 / (s + rc.around), rc.kills, "once per tier and season; orbs, fragments")
	end
end

-- ------------------------------------------------------------------ waystones
function M.waystones()
	for _, L in ipairs(levelsFrom(BC.waystone.from)) do
		add("map", "Waystone maps", L, 0, BC.waystone.kills, "gear, atlas points; no gold of their own")
	end
end

-- ------------------------------------------------------------------ the Ember Descent
function M.descent()
	local d = BC.descent
	for _, L in ipairs(levelsFrom(d.from)) do
		local r = DC.reward(descCfg, d.depth, true, L, d.cursePercent)
		local t = descCfg.treasure.gold
		local gold = r.gold + t.base + t.perDepth * floor(d.depth / 2) -- one treasure room about half way
		add("run", "Ember Descent, full clear, every curse", L, gold * 60 / d.minutes, d.kills,
			"orbs, embers, Descent uniques")
	end
end

-- ------------------------------------------------------------------ the Infinity Tower
function M.tower()
	local t = BC.tower
	local floorGold = 50 -- infinitytower_run.lua cfg.floorGold
	local maxFloor = towerCfg.maxFloor or t.floor
	add("run", string.format("Infinity Tower, floor %d", t.floor), t.level, floorGold * min(t.floor, maxFloor) * t.floorsPerHour,
		t.kills, "orbs and Crystal Coins on milestone floors")
end

-- ------------------------------------------------------------------ the generated dungeons
function M.dungeons()
	local dc = BC.dungeons
	for _, a in ipairs(areaCfg.areas or {}) do
		local d = a.dungeon
		if a.kind == "dungeon" and d and d.chest and a.enabled ~= false then
			local L = d.level
			for diff = 1, #dc.minutes do
				local lv = DD.levels[diff]
				local hours = dc.minutes[diff] / 60
				local kills = dc.monsters / hours / lerp(BC.huntKills, L)
				local share = lerp(BC.coinShare, L)
				kills = kills * (1 + share * lv.gold / 100 + dc.itemShare * lv.loot / 100)
				add("run", string.format("%s, difficulty %d", d.title or a.name, diff), L, DD.chest(d.chest, diff).gold / hours,
					kills, "gear pieces of the boss")
			end
		end
	end
end

-- ------------------------------------------------------------------ the weekly raid
function M.raid()
	local loot = raidCfg.loot
	local gold = 0
	for _, b in ipairs(raidCfg.bosses) do
		gold = gold + (b.final and loot.final.gold or loot.boss.gold)
	end
	for _, L in ipairs(levelsFrom(raidCfg.minLevel)) do
		add("event", "The Ashen Sepulchre (weekly raid)", L, gold * 60 / BC.raid.minutes, BC.raid.kills,
			"orbs, raid marks, raid uniques")
	end
end

-- ------------------------------------------------------------------ the world boss
function M.worldboss()
	local w = Chaos.worldBoss
	local r = w.reward
	local n = BC.party
	for _, L in ipairs(levelsFrom(w.minLevel)) do
		add("event", string.format("World boss, %d players, equal shares", n), L,
			(r.bankGold + r.bankGoldPool / n) * 60 / BC.worldboss.minutes, BC.worldboss.kills, "orbs, gear, uniques, titles")
	end
end

-- ------------------------------------------------------------------ invasions
function M.invasion()
	local r = invCfg.rewards
	local iv = BC.invasion
	for _, n in ipairs(iv.defenders) do
		for _, L in ipairs(levelsFrom(BC.levels[1])) do
			add("event", string.format("Invasion, %d defender%s", n, n == 1 and "" or "s"), L,
				L * (r.goldBase + r.goldPool / n) * 60 / iv.minutes, iv.kills, "orbs, a unique chance")
		end
	end
end

-- ------------------------------------------------------------------ bounties and bestiary tasks (on top of a hunt)
function M.bounty()
	local b = BC.bounty
	for i, band in ipairs(bountyCfg.bands) do
		for _, L in ipairs(levelsFrom(max(band.min, 40), band.max)) do
			local kph = lerp(BC.huntKills, L)
			local kills = (band.kills[1] + band.kills[2]) / 2
			local hours = kills / (kph * b.targetShare)
			local hunt = B.reward({band = i, type = "hunt"}, bountyCfg, L).gold
			local task = B.bandGold and B.bandGold(bountyCfg, i, L) or band.reward.gold
			task = task * bestCfg.reward.hunt.goldMult
			add("hunt", string.format("Bounty hunt contract and a bestiary task, band %d-%s", band.min,
				band.max >= 999999 and "" or band.max), L, (hunt + task) / hours, 1, "Orbs of Upheaval, experience")
			-- an elite contract: count x eliteSearch kills of the type (the magic row, 70% of them)
			local e = bountyCfg.elite[1]
			local eHours = (e.count[1] + e.count[2]) / 2 * bountyCfg.eliteSearch[e.tier] / (kph * b.targetShare)
			add("hunt", string.format("Bounty elite contract, band %d-%s", band.min, band.max >= 999999 and "" or band.max), L,
				B.reward({band = i, type = "elite"}, bountyCfg, L).gold / eHours, 1, "Orbs of Upheaval, experience")
			add("hunt", string.format("Bounty boss contract, band %d-%s", band.min, band.max >= 999999 and "" or band.max), L,
				B.reward({band = i, type = "boss"}, bountyCfg, L).gold * 60 / b.bossMinutes, 0.5, "Orbs of Upheaval, experience")
		end
	end
end

-- ------------------------------------------------------------------ Vocation Trials (the repeat rewards, 5 a week)
function M.trials()
	for i, tier in ipairs(Chaos.trials.tiers) do
		for _, L in ipairs(levelsFrom(tier.minLevel)) do
			local o = T.clearOutcome(i, L, i, 0, 0, 1)
			add("event", string.format("Vocation Trial %s, a repeat clear", tier.name), L, o.gold * 60 / BC.trials.minutes,
				BC.trials.kills, "a Trial Token, orbs")
		end
	end
end

-- ------------------------------------------------------------------ the guild siege (weekly)
function M.siege()
	for _, L in ipairs(levelsFrom(siegeCfg.minLevel)) do
		add("event", "Guild siege, the winners", L, siegeCfg.reward.winner.bankGold * 60 / BC.siege.minutes, BC.siege.kills,
			"orbs, the title and buff")
	end
end

-- ------------------------------------------------------------------ treasure goblins (while hunting)
function M.goblin()
	local g = gobCfg.loot and gobCfg.loot.gold
	if not g then
		return
	end
	local gc = BC.goblin
	for _, L in ipairs(levelsFrom(BC.levels[1])) do
		local perHour = lerp(BC.huntKills, L) / gobCfg.spawn.oneIn
		local gold = (g.base + g.perLevel * L) * gc.variantGold * gc.rollMean
		add("hunt", "Treasure goblins while hunting", L, gold * perHour, 1, "orbs, gems, rune shards, gear")
	end
end

function M.build()
	rows = {}
	M.rifts()
	M.loops()
	M.greater()
	M.waystones()
	M.descent()
	M.tower()
	M.dungeons()
	M.raid()
	M.worldboss()
	M.invasion()
	M.bounty()
	M.trials()
	M.siege()
	M.goblin()
	return rows
end

local function fmt(n)
	local s = string.format("%d", floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
M.fmt = fmt

function M.main(args)
	local check = false
	for _, a in ipairs(args) do
		if a == "--check" then
			check = true
		end
	end
	M.build()
	local bad = {}
	if not check then
		print("| Faucet | Level | Own gold / h | Kills (x hunt) | Hunt curve / h | Total / curve | Pays besides |")
		print("|---|---|---|---|---|---|---|")
	end
	for _, r in ipairs(rows) do
		if not check then
			print(string.format("| %s | %d | %s | %.2f | %s | %.2f%s | %s |", r.name, r.level, fmt(r.own), r.kills, fmt(r.hunt),
				r.ratio, r.ratio > BC.limit + 1e-9 and " OVER" or (r.ratio < BC.low and " low" or ""), r.note))
		end
		if r.ratio > BC.limit + 1e-9 then
			bad[#bad + 1] = string.format("%s at level %d: %.2f x the curve (own %s an hour, kills %.2f)", r.name, r.level,
				r.ratio, fmt(r.own), r.kills)
		end
	end
	if check then
		for _, b in ipairs(bad) do
			print("FAIL " .. b)
		end
		print(string.format("gold faucets: %d rows, %d above %.2f x the curve", #rows, #bad, BC.limit))
		return #bad == 0 and 0 or 1
	end
	return 0
end

if ChaosGoldFaucetsLib then
	return M
end
os.exit(M.main(arg or {}))

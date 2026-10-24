-- The roulette model (server/README.md "Roulette prizes against token drops", O151): what one spin of each roulette is
-- worth against the hunting time its token costs.
--
--     cd server && luajit tools/roulette_model.lua            the tables (also lua5.3)
--     cd server && luajit tools/roulette_model.lua --check    exit 1 when a spin leaves the band of roulette_value_config.lua
--
-- Inputs, all in the repository: boss_roulette_config.lua and roulette_{exercise,premium,crystal}_config.lua (the pools),
-- roulette_value_config.lua (the token drops, the pace, the band), loot_config.lua (the orbs: kills of a level 100+ monster
-- that the loot layer needs for the same drops), data/items/base_item_values.csv (the price of an exercise chest). Expected
-- values, no random numbers; computed, not measured on a server. The assumptions are listed in roulette_value_config.lua.
-- A test can load it as a library: ChaosRouletteModelLib = true; local M = dofile("tools/roulette_model.lua").

dofile("data/scripts/chaos/prizes_core.lua")
local K = ChaosPrizesCore
local V = dofile("data/scripts/chaos/roulette_value_config.lua")
local lootCfg = dofile("data/scripts/chaos/loot_config.lua")

local M = {V = V}
M.KEYS = {"boss", "exercise", "premium", "crystal"}
M.FILES = {boss = "boss_roulette_config.lua", exercise = "roulette_exercise_config.lua",
	premium = "roulette_premium_config.lua", crystal = "roulette_crystal_config.lua"}

function M.load(key)
	return dofile("data/scripts/chaos/" .. M.FILES[key])
end

-- kills of a level 100+ monster that the loot layer needs for one drop of the orb (the normal tier; none: its magic chance / 3)
local orbKills = {}
for _, e in ipairs(lootCfg.currency.entries) do
	local n = e.chance.normal
	if not n or n == 0 then
		n = (e.chance.magic or 0) / 3
	end
	orbKills[e.id] = 10000 / n
end
function M.orbKills(id)
	return orbKills[id]
end

-- price of an item for a player at an NPC (base_item_values.csv buy_med); nil when unknown
local prices
function M.price(id)
	if not prices then
		prices = {}
		local f = assert(io.open("data/items/base_item_values.csv", "r"))
		for line in f:lines() do
			local i, med = line:match("^(%d+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(%d+),")
			if i then
				prices[tonumber(i)] = tonumber(med)
			end
		end
		f:close()
	end
	return prices[id]
end

function M.kph(level)
	return K.curve(V.kph, level)
end

-- the hunting gold per hour of the level (the Boss Roulette's curve, the same as gamble_config.lua balance.hunting)
function M.goldPerHour(level)
	return K.curve(M.load("boss").gold.hunting, level)
end

-- the odds of each pool entry (the base draw)
function M.odds(cfg)
	local pool = {}
	for i, e in ipairs(cfg.pool) do
		pool[i] = {itemId = e.id, chance = e.chance}
	end
	return K.odds(pool)
end

-- the minutes of hunting one entry is worth at this level (0: not counted)
function M.entryMinutes(cfg, e, level)
	local avg = (e.count[1] + e.count[2]) / 2
	if e.kind == "orb" or e.kind == "material" then
		return avg * assert(orbKills[e.id], "no loot entry for " .. e.id) / M.kph(level) * 60
	elseif e.kind == "gold" then
		return e.count[1] * cfg.gold.perUnit * 60
	elseif e.kind == "chest" then
		return assert(M.price(e.id), "no price for " .. e.id) / (M.goldPerHour(level) / 60)
	elseif e.kind == "unique" then
		return V.uniqueMinutes
	end
	return 0
end

-- one spin at a level: {minutes, by = {kind = minutes}, share = {kind = share of the spins}, orbs = orbs per spin}
function M.spin(cfg, level)
	local o = M.odds(cfg)
	local out = {minutes = 0, by = {}, share = {}, orbs = 0, gold = 0}
	for i, e in ipairs(cfg.pool) do
		local m = M.entryMinutes(cfg, e, level)
		out.minutes = out.minutes + o[i] * m
		out.by[e.kind] = (out.by[e.kind] or 0) + o[i] * m
		out.share[e.kind] = (out.share[e.kind] or 0) + o[i]
		if e.kind == "orb" or e.kind == "material" then
			out.orbs = out.orbs + o[i] * (e.count[1] + e.count[2]) / 2
		elseif e.kind == "gold" then
			out.gold = out.gold + o[i] * K.goldFor(cfg, e.count[1], level)
		end
	end
	return out
end

-- minutes of hunting the tokens of one spin cost
function M.cost(key, cfg)
	local t = V.tokens[key]
	if t.perRun then
		return cfg.tokenCount / t.perRun * V.minutesPerRun
	end
	return cfg.tokenCount / (t.chance * t.count) * V.minutesPerBossKill
end

-- {key, level, value, cost, ratio, spin} for every roulette and level
function M.rows()
	local rows = {}
	for _, key in ipairs(M.KEYS) do
		local cfg = M.load(key)
		local cost = M.cost(key, cfg)
		for _, level in ipairs(V.levels) do
			local s = M.spin(cfg, level)
			rows[#rows + 1] = {key = key, level = level, value = s.minutes, cost = cost, ratio = s.minutes / cost, spin = s}
		end
	end
	return rows
end

if ChaosRouletteModelLib then
	return M
end

local rows = M.rows()
print("Roulette spin against its token (minutes of hunting at the level; orbs, sockets, gold, exercise chests and unique "
	.. "chests counted)")
print(string.format("  boss kill %d min, Tower Defense run %d min; band %.2f - %.2f", V.minutesPerBossKill, V.minutesPerRun,
	V.band.min, V.band.max))
print(string.format("%-9s %5s  %-26s %7s %7s %6s  %s", "roulette", "level", "tokens per spin / kills or runs", "cost", "value",
	"ratio", "orbs + gold per spin"))
local fails = 0
for _, r in ipairs(rows) do
	local cfg = M.load(r.key)
	local t = V.tokens[r.key]
	local what
	if t.perRun then
		what = string.format("%d tokens = %.1f runs", cfg.tokenCount, cfg.tokenCount / t.perRun)
	else
		what = string.format("%d token = %.1f kills", cfg.tokenCount, cfg.tokenCount / (t.chance * t.count))
	end
	local bad = r.ratio < V.band.min or r.ratio > V.band.max
	if bad then
		fails = fails + 1
	end
	print(string.format("%-9s %5d  %-26s %6.1fm %6.1fm %6.2f  %.2f orbs + %.0f gold%s", r.key, r.level, what, r.cost, r.value,
		r.ratio, r.spin.orbs, r.spin.gold, bad and "  OUT OF BAND" or ""))
end
if arg and arg[1] == "--check" then
	print(fails == 0 and "roulette_model: ok" or string.format("roulette_model: %d row(s) out of band", fails))
	os.exit(fails == 0 and 0 or 1)
end

-- The unique pace model (O342; server/README.md "Unique pace"): how many kills of a hunt of the right level a typical
-- player needs for one leveling unique, with the open-by-level rule of loot_config.lua unique.openLevel.
--
--     cd server && luajit tools/unique_pace_model.lua            the tables (also lua5.3)
--     cd server && luajit tools/unique_pace_model.lua --derive   the open multiplier per level that hits `aim`
--     cd server && luajit tools/unique_pace_model.lua --legacy   the same tables without the rule (the numbers before)
--     cd server && luajit tools/unique_pace_model.lua --check    exit 1 when a band or a hall hunt leaves the limits (CI)
--
-- Inputs, all in the repository: data/lib/chaos_unique_items.lua (the entries), loot.lua (L.uniqueList, L.openLevelMult:
-- the rule itself), loot_config.lua (tierMult, tierRank, maxChance, openLevel), monster_tiers.lua (spawnChance, ambush,
-- ambushTier, maxChain: read from the file text), pace_config.lua (the pack factor of the unique roll: the larger of `loot`
-- and `notable`), bounty_pool.lua (hunt monsters: level, spawns), tools/hall_hunts.csv, conquest_config.lua (pity),
-- unique_pace_config.lua (the limits). Expected values, no random numbers; tests/unique_open_level_test.lua checks the rule
-- against L.rollUniques. Assumptions: a paced hunt (the pack factor applies), no item find, season uniques left out (they
-- drop for the season's characters only), maxPerKill 1 (it only trims two drops of one kill; at these chances negligible).
-- A test can load it as a library: ChaosUniquePaceLib = true; local M = dofile("tools/unique_pace_model.lua").

Chaos = Chaos or {}
MAX_LOOTCHANCE = MAX_LOOTCHANCE or 100000
EventCallback = EventCallback or setmetatable({register = function() end}, {__newindex = rawset})
if not ItemType then
	function ItemType(id)
		return {isStackable = function() return false end, getName = function() return "item " .. id end}
	end
end
local savedMeta = getmetatable(_G)
setmetatable(_G, {__index = function(_, k)
	if type(k) == "string" and k:match("^ITEM_ATTRIBUTE_") then return k end
end})
dofile("data/lib/chaos_item_mods.lua")
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
dofile("data/scripts/chaos/loot.lua")
dofile("data/scripts/chaos/pace_core.lua")
setmetatable(_G, savedMeta)

local L, P = ChaosLoot, ChaosPaceCore
local C = L.config or ChaosLootConfig
local PC = dofile("data/scripts/chaos/pace_config.lua")
local V = dofile("data/scripts/chaos/unique_pace_config.lua")
local CQ = dofile("data/scripts/chaos/conquest_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")

local M = {V = V}

local function readFile(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

-- ---------------------------------------------------------------- the tier mix of the kills
-- monster_tiers.lua: a spawned monster rolls 1..10000 once; <= legendary is legendary, <= rare rare, <= magic magic (the three
-- numbers are cumulative thresholds). A kill brings an ambush copy with ambush[tier] x the pack factor `loot` (per 10000),
-- of a tier by ambushTier, down to maxChain generations.
function M.tierConfig()
	local text = readFile("data/scripts/chaos/monster_tiers.lua")
	local function tbl(key)
		local body = text:match("\n%s*" .. key .. "%s*=%s*(%b{})")
		assert(body, "monster_tiers.lua: no " .. key)
		local t = {}
		for k, v in body:gmatch("(%a+)%s*=%s*([%d%.]+)") do
			t[k] = tonumber(v)
		end
		return t
	end
	return {spawn = tbl("spawnChance"), ambush = tbl("ambush"), ambushTier = tbl("ambushTier"),
		maxChain = tonumber(text:match("maxChain%s*=%s*(%d+)"))}
end
local TC = M.tierConfig()

-- the share of all kills (natural and ambush copies) by tier at the pack factor `loot`
function M.tierShares(loot)
	local s = TC.spawn
	local nat = {legendary = s.legendary / 10000, rare = (s.rare - s.legendary) / 10000,
		magic = (s.magic - s.rare) / 10000}
	nat.normal = 1 - nat.legendary - nat.rare - nat.magic
	local wsum = 0
	for _, w in pairs(TC.ambushTier) do
		wsum = wsum + w
	end
	local kills = {}
	for t, v in pairs(nat) do
		kills[t] = v
	end
	local gen = nat
	for _ = 1, TC.maxChain do
		local nextGen = {normal = 0, magic = 0, rare = 0, legendary = 0}
		for t, v in pairs(gen) do
			local a = math.min(1, (TC.ambush[t] or 0) * loot / 10000)
			for t2, w in pairs(TC.ambushTier) do
				nextGen[t2] = nextGen[t2] + v * a * w / wsum
			end
		end
		for t, v in pairs(nextGen) do
			kills[t] = kills[t] + v
		end
		gen = nextGen
	end
	local total = 0
	for _, v in pairs(kills) do
		total = total + v
	end
	local out = {}
	for t, v in pairs(kills) do
		out[t] = v / total
	end
	return out
end

-- ---------------------------------------------------------------- pace factor of the unique roll
function M.pace(level, scaled)
	local f = P.factors(PC, level, scaled and true or false, false)
	return L.uniquePace(f.loot, {notable = f.notable}), f
end

-- ---------------------------------------------------------------- the entries
local entries
local function leveling()
	if not entries then
		entries = {}
		for _, e in ipairs(L.uniqueList()) do
			if not e.bossOnly and not e.minMonsterLevel and not e.season then
				entries[#entries + 1] = e
			end
		end
	end
	return entries
end
M.leveling = leveling

local function listed(e, name)
	if type(e.monsters) ~= "table" or next(e.monsters) == nil then
		return true
	end
	name = name:lower()
	for _, m in ipairs(e.monsters) do
		if tostring(m):lower() == name then
			return true
		end
	end
	return false
end

-- Chance (0..1) per kill of a tier-t monster `name` of `level`, by group: {monster = q, set = q}. opts.mult overrides the
-- open multiplier (a number), opts.legacy turns the rule off.
function M.tierChance(tier, name, level, pace, opts)
	opts = opts or {}
	local u = C.unique
	local mult, rank = u.tierMult[tier], u.tierRank[tier]
	local none = {monster = 1, set = 1}
	local any = {monster = false, set = false}
	for _, e in ipairs(leveling()) do
		if rank >= (u.tierRank[e.minTier] or 0) then
			local mod
			if listed(e, name) then
				mod = 1
			elseif not opts.legacy then
				mod = opts.mult and (L.openLevelMult(e, level) and opts.mult) or L.openLevelMult(e, level)
			end
			if mod then
				local g = L.pityGroup(e)
				local c = math.min(u.maxChance, e.chance * mult * pace * mod)
				none[g] = none[g] * (1 - c / 10000)
				any[g] = true
			end
		end
	end
	return {monster = 1 - none.monster, set = 1 - none.set}, any
end

-- unique per kill of a monster (no pity)
function M.perKill(name, level, opts)
	local pace = M.pace(level)
	local loot = select(2, M.pace(level)).loot
	local shares = M.tierShares(loot)
	local sum = 0
	for _, tier in ipairs({"magic", "rare", "legendary"}) do
		local q = M.tierChance(tier, name, level, pace, opts)
		sum = sum + shares[tier] * (1 - (1 - q.monster) * (1 - q.set))
	end
	return sum
end

-- ---------------------------------------------------------------- the bad-luck protection
-- the rate of one group with the protection: a roll that misses raises the next chances to x(1 + step x misses), at most x cap
-- (conquest_config.lua pity); rolls = the kills of tiers that have an eligible entry. rows = {{share, q}, ...} by tier.
function M.pityKills(rows, group)
	local g = CQ.pity[group]
	local rolls, hit = 0, 0
	for _, r in ipairs(rows) do
		rolls = rolls + r.share
	end
	if rolls <= 0 then
		return math.huge
	end
	local expected, surv, n = 0, 1, 0
	while surv > 1e-9 and n < 100000 do
		expected = expected + surv
		local mult = math.min(g.cap, 1 + g.step * n)
		local h = 0
		for _, r in ipairs(rows) do
			h = h + r.share / rolls * math.min(1, r.q * mult)
		end
		surv = surv * (1 - h)
		n = n + 1
	end
	return expected / rolls
end

-- ---------------------------------------------------------------- hunts
-- hunt monsters of the pool within +- share of the level, with their spawn counts as weights
function M.bandMonsters(level)
	local lo, hi = level * (1 - V.share), level * (1 + V.share)
	local out = {}
	for _, m in ipairs(pool.hunt) do
		if m.level >= lo and m.level <= hi then
			out[#out + 1] = {name = m.name, level = m.level, w = m.spawns or 1}
		end
	end
	return out
end

local function avgPerKill(mons, opts)
	local sum, wsum, lo, hi = 0, 0, math.huge, 0
	for _, m in ipairs(mons) do
		local p = M.perKill(m.name, m.level, opts)
		sum = sum + p * m.w
		wsum = wsum + m.w
		lo, hi = math.min(lo, p), math.max(hi, p)
	end
	return sum / wsum, lo, hi
end

-- the pity pace of a monster list: kills per unique with the protection, groups added
local function pityKillsPerUnique(mons, opts)
	local total = 0
	for _, group in ipairs({"monster", "set"}) do
		local rows, wsum = {}, 0
		for _, tier in ipairs({"magic", "rare", "legendary"}) do
			local share, q, n = 0, 0, 0
			for _, m in ipairs(mons) do
				local pace, f = M.pace(m.level)
				local qq, any = M.tierChance(tier, m.name, m.level, pace, opts)
				if any[group] then
					local s = M.tierShares(f.loot)[tier]
					share = share + s * m.w
					q = q + qq[group] * s * m.w
				end
				n = n + m.w
			end
			wsum = n
			if share > 0 then
				rows[#rows + 1] = {share = share / n, q = q / share}
			end
		end
		local kpu = M.pityKills(rows, group)
		if kpu < math.huge then
			total = total + 1 / kpu
		end
	end
	return total > 0 and 1 / total or math.huge
end

function M.band(level, opts)
	local mons = M.bandMonsters(level)
	if #mons == 0 then
		return nil
	end
	local p, lo, hi = avgPerKill(mons, opts)
	return {level = level, n = #mons, perKill = p, kills = 1 / p, worst = 1 / lo, best = 1 / hi,
		pity = pityKillsPerUnique(mons, opts)}
end

-- the pool level of a monster by name (lower case)
local poolLevel
local function levelOfMonster(name)
	if not poolLevel then
		poolLevel = {}
		for _, m in ipairs(pool.hunt) do
			poolLevel[m.name:lower()] = m.level
		end
	end
	return poolLevel[name:lower()]
end

function M.hallHunts()
	local out = {}
	local f = assert(io.open("tools/hall_hunts.csv", "r"))
	for line in f:lines() do
		if line:sub(1, 1) ~= "#" and not line:match("^id,") then
			local cols = {}
			for c in (line .. ","):gmatch("([^,]*),") do
				cols[#cols + 1] = c
			end
			-- id,z,x,y,dest_x,dest_y,dest_z,kind,name,level,lo,hi,display,spawntime,monsters,note
			if cols[8] == "hunt" and (tonumber(cols[10]) or 0) >= V.hall.minLevel then
				local mons = {}
				for name in (cols[15] or ""):gmatch("[^|]+") do
					mons[#mons + 1] = {name = name, level = levelOfMonster(name) or tonumber(cols[10]), w = 1}
				end
				if #mons > 0 then
					out[#out + 1] = {name = cols[9], level = tonumber(cols[10]), monsters = mons}
				end
			end
		end
	end
	f:close()
	return out
end

-- ---------------------------------------------------------------- --derive
-- the open multiplier that makes the band of a level hit `aim` (bisection, one multiplier for the whole band)
function M.deriveMult(level, aim)
	local mons = M.bandMonsters(level)
	if #mons == 0 then
		return nil
	end
	local lo, hi = 0.0001, 200
	for _ = 1, 60 do
		local mid = math.sqrt(lo * hi)
		local p = avgPerKill(mons, {mult = mid})
		if 1 / p > aim then
			lo = mid
		else
			hi = mid
		end
	end
	return math.sqrt(lo * hi)
end

if ChaosUniquePaceLib then
	return M
end

-- ---------------------------------------------------------------- output
local mode = arg and arg[1]

if mode == "--derive" then
	print(string.format("open multiplier per band level for %d kills per unique (loot_config.lua unique.openLevel.mult points)",
		V.aim))
	for _, lv in ipairs({8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 175, 200, 225, 250, 300, 350, 400, 450,
			500, 550, 600, 650}) do
		local m = M.deriveMult(lv, V.aim)
		print(string.format("  {%d, %.3f}%s", lv, m or 0, m and "" or "  (no monster)"))
	end
	return
end

local legacy = mode == "--legacy"
local opts = {legacy = legacy}
print(string.format("Leveling uniques: %d entries, kills per unique, no item find%s (target %d - %d)", #leveling(),
	legacy and ", WITHOUT the open rule" or "", V.target.min, V.target.max))
print(string.format("%5s %5s %9s %9s %9s %10s", "band", "mons", "kills", "worst", "best", "with pity"))
local fails = 0
for _, b in ipairs(V.bands) do
	local r = M.band(b.level, opts)
	if r then
		local bad = r.kills < b.min or r.kills > b.max
		fails = fails + (bad and 1 or 0)
		print(string.format("%5d %5d %9.0f %9.0f %9.0f %10.0f%s", b.level, r.n, r.kills, r.worst, r.best, r.pity,
			bad and "  OUT OF LIMITS" or ""))
		local speed = r.kills / r.pity
		if not legacy and (speed > V.pity.maxSpeedup or speed < V.pity.minSpeedup) then
			fails = fails + 1
			print(string.format("      pity speed-up %.2f outside %.1f - %.1f", speed, V.pity.minSpeedup, V.pity.maxSpeedup))
		end
	else
		fails = fails + 1
		print(string.format("%5d  no monster in the pool", b.level))
	end
end
print("Hall hunts (average over the monsters of the hunt):")
local hunts = M.hallHunts()
table.sort(hunts, function(a, b) return a.level < b.level end)
for _, h in ipairs(hunts) do
	local p = avgPerKill(h.monsters, opts)
	local kills = 1 / p
	local min = h.level < V.hall.starterUpTo and V.hall.starterMin or V.hall.min
	local max = h.level < V.hall.starterUpTo and V.hall.starterMax or V.hall.max
	local bad = kills < min or kills > max
	fails = fails + (bad and 1 or 0)
	print(string.format("  %-28s level %4d  %8.0f kills%s", h.name, h.level, kills, bad and "  OUT OF LIMITS" or ""))
end
if mode == "--check" then
	print(fails == 0 and "unique_pace_model: ok" or string.format("unique_pace_model: %d value(s) out of limits", fails))
	os.exit(fails == 0 and 0 or 1)
end

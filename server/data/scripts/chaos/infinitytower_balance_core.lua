-- Infinity Tower balance and floor rewards: pure logic (no engine API). infinitytower_run.lua and infinitytower.lua use it,
-- tests/infinitytower_balance_test.lua checks it. Numbers: infinitytower_balance_config.lua. Overview: server/README.md
-- "Infinity Tower balance and floor rewards" (O144).
--   B.curve(points, x)                 linear between {x, y} points, flat beyond the ends
--   B.count(cfg, floor, players)       monsters of a floor (rounded; + perPlayer for every player after the first)
--   B.sawtooth(cfg, floor)             the health factor of the floor in its climb of milestoneEvery floors
--   B.health(cfg, floor)               maximum health of a normal monster of the floor (curve x sawtooth)
--   B.bossHealth(cfg, floor)           maximum health of the floor's boss
--   B.damage(cfg, floor)               damage factor of the floor's monsters (never a boss)
--   B.bossAt(cfg, floor)               the boss of a boss floor: {name, heal}
--   B.poolAt(cfg, floor)               the species of the floor's band
--   B.tierRoll(cfg, floor, roll)       "legendary" | "rare" | "magic" | nil for a roll of 1..100
--   B.preTierHealth(cfg, health, tier, stockHp)   the health to set before the stock tier multiplies by stockHp
--   B.plan(cfg, floor, players, rng)   {floor, boss, spawns = {{name, tier, health, damage, boss}}}
--   B.rewardItems(rules, floor)        the items a rule list gives on the floor ({id, name, count}, same item added up)
--   B.isMilestone(cfg, floor)          floor % milestoneEvery == 0
--   B.nextMilestone(cfg, floor)        the first milestone floor above `floor`
--   B.itemsText(items)                 "3 Orb of Upheaval, 1 Orb of Fate"
--   B.stored(value, season)            the highest milestone floor paid this season (storage value season x 1000 + floor)
--   B.encode(season, floor)            the storage value
--   B.firstClear(cfg, value, season, floor)   -> items to pay, new storage value (nil when the floor pays nothing now)
--   B.dropRolls(cfg, floor, tier, rng) the tower drops of one kill: {{id, name, count}}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTowerBalanceCore = ChaosTowerBalanceCore or {}
local B = ChaosTowerBalanceCore

local function floorNum(x)
	return math.floor(x + 1e-9)
end

function B.curve(points, x)
	local first = points[1]
	if x <= first[1] then
		return first[2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

function B.count(cfg, floor, players)
	players = math.max(1, players or 1)
	return floorNum(B.curve(cfg.count, floor) + 0.5) + (players - 1) * cfg.perPlayer
end

function B.sawtooth(cfg, floor)
	local s = cfg.sawtooth
	return s[(floor - 1) % #s + 1]
end

function B.isMilestone(cfg, floor)
	return floor > 0 and floor % cfg.milestoneEvery == 0
end

function B.isBoss(cfg, floor)
	return floor > 0 and floor % cfg.bossEvery == 0
end

function B.health(cfg, floor)
	return math.max(1, floorNum(B.curve(cfg.health, floor) * B.sawtooth(cfg, floor)))
end

-- the boss floors of cfg.bossHealth in order; above the last one the boss grows 8% for every boss floor more
function B.bossHealth(cfg, floor)
	local keys = {}
	for k in pairs(cfg.bossHealth) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local best = keys[1]
	for _, k in ipairs(keys) do
		if k <= floor then
			best = k
		end
	end
	local value = cfg.bossHealth[best]
	if floor > keys[#keys] then
		value = value * (1 + 0.08 * (floor - keys[#keys]) / cfg.bossEvery)
	end
	return floorNum(value)
end

-- the level shown after the name of a monster of the floor ("[level]"): the level the floor is meant for (cfg.level),
-- the one the health curve is derived from; monster_levels.lua shows it through Chaos.spawnLevel (O168)
function B.level(cfg, floor)
	if not cfg.level then
		return nil
	end
	return math.max(1, floorNum(B.curve(cfg.level, floor) + 0.5))
end

function B.damage(cfg, floor)
	return B.curve(cfg.damage, floor)
end

function B.bossAt(cfg, floor)
	local n = #cfg.bosses
	return cfg.bosses[(floorNum(floor / cfg.bossEvery) - 1) % n + 1]
end

function B.poolAt(cfg, floor)
	return cfg.pools[math.min(#cfg.pools, floorNum(floor / cfg.bandFloors) + 1)]
end

function B.tierChances(cfg, floor)
	return B.curve(cfg.magic, floor), B.curve(cfg.rare, floor), B.curve(cfg.legendary, floor)
end

-- roll: a whole number 1..100. Legendary first, then rare, then magic (the chances are percents and add up)
function B.tierRoll(cfg, floor, roll)
	local magic, rare, legendary = B.tierChances(cfg, floor)
	if roll <= legendary then
		return "legendary"
	elseif roll <= legendary + rare then
		return "rare"
	elseif roll <= legendary + rare + magic then
		return "magic"
	end
	return nil
end

-- the stock tier (monster_tiers.lua ChaosTiers) multiplies the health by stockHp when it is applied; the tower wants
-- health x cfg.tierHealth[tier]
function B.preTierHealth(cfg, health, tier, stockHp)
	local want = health * (cfg.tierHealth[tier] or 1)
	return math.max(1, floorNum(want / (stockHp or 1)))
end

function B.tierMaxHealth(cfg, health, tier)
	return math.max(1, floorNum(health * (cfg.tierHealth[tier] or 1)))
end

function B.plan(cfg, floor, players, rng)
	rng = rng or math.random
	players = math.max(1, players or 1)
	local pool = B.poolAt(cfg, floor)
	local count = B.count(cfg, floor, players)
	local boss = B.isBoss(cfg, floor)
	local plan = {floor = floor, boss = boss, spawns = {}}
	if boss then
		plan.spawns[1] = {name = B.bossAt(cfg, floor).name, boss = true, health = B.bossHealth(cfg, floor), damage = 1,
			level = B.level(cfg, floor)}
		count = floorNum(count / cfg.bossHelperDivisor)
	end
	local health, damage, level = B.health(cfg, floor), B.damage(cfg, floor), B.level(cfg, floor)
	for _ = 1, count do
		local tier = B.tierRoll(cfg, floor, rng(100))
		plan.spawns[#plan.spawns + 1] = {name = pool[rng(#pool)], tier = tier, health = health, damage = damage,
			level = level}
	end
	return plan
end

-- ------------------------------------------------------------------------------------------------ rewards
function B.rewardItems(rules, floor)
	local out, byId = {}, {}
	for _, r in ipairs(rules) do
		if floor > 0 and floor % r.every == 0 then
			local n = math.max(r.min or 0, floorNum((r.base or 0) + (r.perFloor or 0) * floor))
			if n > 0 then
				local at = byId[r.id]
				if at then
					out[at].count = out[at].count + n
				else
					out[#out + 1] = {id = r.id, name = r.name, count = n}
					byId[r.id] = #out
				end
			end
		end
	end
	return out
end

-- the first floor above `floor` (0 = none yet) that the rules pay on; nil when there is none within maxFloor
function B.nextMilestone(cfg, floor)
	local f = floor + 1
	while f <= cfg.maxFloor do
		if B.isMilestone(cfg, f) and #B.rewardItems(cfg.rewards.firstClear, f) > 0 then
			return f
		end
		f = f + 1
	end
	return nil
end

function B.itemsText(items)
	local parts = {}
	for _, it in ipairs(items) do
		parts[#parts + 1] = it.count .. " " .. (it.name or ("item " .. it.id))
	end
	return table.concat(parts, ", ")
end

-- storage value = season x 1000 + the highest milestone floor paid in that season
function B.encode(season, floor)
	return season * 1000 + floor
end

function B.stored(value, season)
	value = tonumber(value) or 0
	if value <= 0 or math.floor(value / 1000) ~= season then
		return 0
	end
	return value % 1000
end

-- the first clear of `floor` in `season` for a character whose storage holds `value`: the items now and the new value
function B.firstClear(cfg, value, season, floor)
	if not B.isMilestone(cfg, floor) or floor >= 1000 then
		return nil
	end
	if floor <= B.stored(value, season) then
		return nil
	end
	local items = B.rewardItems(cfg.rewards.firstClear, floor)
	if #items == 0 then
		return nil
	end
	return items, B.encode(season, floor)
end

-- ------------------------------------------------------------------------------------------------ drops
function B.dropRolls(cfg, floor, tier, rng)
	rng = rng or math.random
	local mult = tier and cfg.drops.tierMult[tier] or 1
	local out = {}
	for _, d in ipairs(cfg.drops.items) do
		if floor >= (d.from or 1) and rng(10000) <= d.chance * mult then
			local top = d.max + floorNum((d.perFloor or 0) * floor)
			out[#out + 1] = {id = d.id, name = d.name, count = rng(d.min, math.max(d.min, top))}
		end
	end
	return out
end

return B

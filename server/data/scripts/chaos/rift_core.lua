-- Rifts: the pure part (no engine calls), shared by rift.lua and tests/rift_test.lua.
--   keys       rollModCount / rollMods / rollKey, encode / decode of the "rift_mods" attribute, name, description
--   effects    what the modifiers do to the monsters and the players, and the reward bonuses they give
--   plan       monster types from the bounty pool window of the tier, packs, elites, the boss threshold
--   rewards    the chest of one player, the next-key roll, the tier-1 key chance of a normal kill
--   instance   slot grid, slot allocation, the room layout of a slot (floor, walls, doorways)
--   run        timer / kill / boss / success / fail bookkeeping
--   exp        the experience cap (rate of the leveling model per minute in the rift)
-- Every random number comes from the `rand(a, b)` argument (integer in [a, b]).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosRiftCore = ChaosRiftCore or {}
local R = ChaosRiftCore

local floor = math.floor

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function weighted(rows, rand) -- rows = {{value, weight}, ...}
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return rows[1] and rows[1][1]
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end
R.weighted = weighted

-- true with probability p percent (resolution 1/10000 %)
local function chance(p, rand)
	if not p or p <= 0 then
		return false
	end
	if p >= 100 then
		return true
	end
	return rand(1, 1000000) <= floor(p * 10000 + 0.5)
end
R.chance = chance

-- ===================================================================== keys
function R.modDef(cfg, key)
	for i, m in ipairs(cfg.mods) do
		if m.key == key then
			return m, i
		end
	end
	return nil
end

function R.clampTier(cfg, tier)
	tier = floor(tonumber(tier) or 1)
	return clamp(tier, 1, cfg.maxTier)
end

function R.rollModCount(cfg, rand, better)
	return weighted(better and cfg.modCountBetter or cfg.modCount, rand)
end

-- `count` different modifiers, each {key =, value =}, in the order of cfg.mods
function R.rollMods(cfg, count, rand)
	local pool = {}
	for i = 1, #cfg.mods do
		pool[i] = i
	end
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		picked[#picked + 1] = table.remove(pool, rand(1, #pool))
	end
	table.sort(picked)
	local mods = {}
	for _, i in ipairs(picked) do
		local m = cfg.mods[i]
		local steps = floor((m.range[2] - m.range[1]) / m.step)
		mods[#mods + 1] = {key = m.key, value = m.range[1] + rand(0, steps) * m.step}
	end
	return mods
end

function R.rollKey(cfg, tier, rand, better)
	return {tier = R.clampTier(cfg, tier), mods = R.rollMods(cfg, R.rollModCount(cfg, rand, better), rand)}
end

function R.encodeMods(mods)
	local parts = {}
	for _, m in ipairs(mods or {}) do
		parts[#parts + 1] = m.key .. ":" .. m.value
	end
	return table.concat(parts, ",")
end

-- parses and validates (unknown keys dropped, values clamped to the range, duplicates dropped, at most cfg.key.maxMods)
function R.decodeMods(cfg, text)
	local mods, seen = {}, {}
	if type(text) ~= "string" then
		return mods
	end
	local max = cfg.key and cfg.key.maxMods or 3
	for key, value in text:gmatch("([%a_]+):(%-?%d+)") do
		local def = R.modDef(cfg, key)
		if def and not seen[key] and #mods < max then
			seen[key] = true
			mods[#mods + 1] = {key = key, value = clamp(tonumber(value), def.range[1], def.range[2])}
		end
	end
	table.sort(mods, function(a, b)
		local _, ia = R.modDef(cfg, a.key)
		local _, ib = R.modDef(cfg, b.key)
		return ia < ib
	end)
	return mods
end

-- packed storage value of one modifier (index x 1000 + value) and back; used by the crash refund marker
function R.packMod(cfg, m)
	local _, i = R.modDef(cfg, m.key)
	return i and (i * 1000 + m.value) or 0
end

function R.unpackMod(cfg, n)
	n = tonumber(n) or 0
	local def = cfg.mods[floor(n / 1000)]
	if n <= 0 or not def then
		return nil
	end
	return {key = def.key, value = clamp(n % 1000, def.range[1], def.range[2])}
end

function R.keyName(cfg, tier)
	return string.format(cfg.key.nameFormat, tier)
end

function R.modText(cfg, m)
	local def = R.modDef(cfg, m.key)
	if not def then
		return m.key
	end
	return (def.text:find("%%d") and string.format(def.text, m.value) or def.text)
end

-- reward bonuses in percent {quantity, rarity, experience} from the modifiers (+ tiers above the table)
function R.bonuses(cfg, mods, tier)
	local b = {quantity = 0, rarity = 0, experience = 0}
	for _, m in ipairs(mods or {}) do
		local def = R.modDef(cfg, m.key)
		if def and def.reward then
			for k, per in pairs(def.reward) do
				if k == "fixed" then
					for fk, fv in pairs(per) do
						b[fk] = b[fk] + fv
					end
				elseif b[k] then
					b[k] = b[k] + per * m.value
				end
			end
		end
	end
	for k, v in pairs(b) do
		b[k] = floor(v + 0.5)
	end
	return b
end

function R.describe(cfg, key)
	local lines = {}
	for _, m in ipairs(key.mods or {}) do
		lines[#lines + 1] = R.modText(cfg, m)
	end
	local b = R.bonuses(cfg, key.mods, key.tier)
	local bonus = {}
	if b.quantity > 0 then
		bonus[#bonus + 1] = "+" .. b.quantity .. "% item quantity"
	end
	if b.rarity > 0 then
		bonus[#bonus + 1] = "+" .. b.rarity .. "% item rarity"
	end
	if b.experience > 0 then
		bonus[#bonus + 1] = "+" .. b.experience .. "% experience"
	end
	local t = R.tierInfo(cfg, key.tier)
	return string.format("Modifiers: %s. Rewards: %s. Opens a rift of tier %d (level %d+). Use it in a protection zone; your party within %d sqm comes along.",
		#lines > 0 and table.concat(lines, "; ") or "none", #bonus > 0 and table.concat(bonus, ", ") or "normal",
		key.tier, t.minLevel, cfg.partyRange)
end

-- ===================================================================== effects
function R.tierInfo(cfg, tier)
	tier = R.clampTier(cfg, tier)
	local n = #cfg.tiers
	local base = cfg.tiers[math.min(tier, n)]
	local over = math.max(0, tier - n)
	return {
		tier = tier,
		minLevel = base.minLevel + over * cfg.beyond.minLevelStep,
		pick = {base.pick[1], base.pick[2]},
		health = 1 + over * cfg.beyond.health,
		damage = 1 + over * cfg.beyond.damage,
		reward = 1 + over * cfg.beyond.reward
	}
end

-- what the modifiers do: multipliers / additions used by rift.lua
function R.effects(cfg, mods, tier)
	local t = R.tierInfo(cfg, tier)
	local fx = {health = t.health, damage = t.damage, speed = 0, elite = 1, reflect = 0, resist = 0, noRegen = false, packBonus = 0}
	for _, m in ipairs(mods or {}) do
		local v = m.value
		if m.key == "vitality" then
			fx.health = fx.health * (1 + v / 100)
		elseif m.key == "brutality" then
			fx.damage = fx.damage * (1 + v / 100)
		elseif m.key == "haste" then
			fx.speed = fx.speed + v
		elseif m.key == "elites" then
			fx.elite = fx.elite * (1 + v / 100)
		elseif m.key == "reflection" then
			fx.reflect = fx.reflect + v / 100
		elseif m.key == "warding" then
			fx.resist = fx.resist + v / 100
		elseif m.key == "withering" then
			fx.noRegen = true
		elseif m.key == "swarm" then
			fx.packBonus = fx.packBonus + v
		end
	end
	return fx
end

-- ===================================================================== plan
-- pool entries of the window (hunt list of bounty_pool.lua), filtered by `known(name)` when given
function R.candidates(cfg, pool, window, known)
	local list = {}
	for _, e in ipairs(pool or {}) do
		if e.level >= window[1] and e.level <= window[2] and (e.health or 0) >= cfg.minPoolHealth
				and (not known or known(e.name)) then
			list[#list + 1] = e
		end
	end
	return list
end

-- `cfg.packs.types` different monster types for a tier (window widened when too few)
function R.pickTypes(cfg, pool, tier, rand, known)
	local t = R.tierInfo(cfg, tier)
	local want = cfg.packs.types
	local window = {t.pick[1], t.pick[2]}
	local list = R.candidates(cfg, pool, window, known)
	local widen = 0
	while #list < want and widen < 5 do
		widen = widen + 1
		window = {window[1] - cfg.widenStep, window[2] + cfg.widenStep}
		list = R.candidates(cfg, pool, window, known)
	end
	local picked = {}
	for _ = 1, math.min(want, #list) do
		picked[#picked + 1] = table.remove(list, rand(1, #list))
	end
	table.sort(picked, function(a, b)
		if a.level == b.level then
			return a.name < b.name
		end
		return a.level < b.level
	end)
	return picked
end

local function eliteTier(cfg, fx, tier, rand)
	local mult = fx.elite * (1 + cfg.elite.perTier * tier)
	local roll = rand(1, 1000000)
	local acc = 0
	for _, name in ipairs({"legendary", "rare", "magic"}) do
		acc = acc + floor(cfg.elite[name] * mult * 10000)
		if roll <= acc then
			return name
		end
	end
	return nil
end
R.eliteTier = eliteTier

-- the run plan: {types, packs = {{room, name, count, elites = {tier or false, ...}}}, total, bossAt, boss}
-- rooms = list of room names the packs may use (open side rooms; "hub" gets at most one pack)
function R.plan(cfg, tier, fx, players, types, rooms, rand)
	players = math.max(1, players or 1)
	local plan = {types = types, packs = {}, total = 0}
	if #types == 0 then
		return plan
	end
	local count = cfg.packs.base + floor(tier / cfg.packs.perTiers) + cfg.packs.perExtraPlayer * (players - 1)
	local areas = {}
	for _, r in ipairs(rooms) do
		areas[#areas + 1] = r
	end
	for i = 1, count do
		local room
		if i == 1 or #areas == 0 then
			room = "hub"
		else
			room = areas[(i - 2) % #areas + 1]
		end
		local size = rand(cfg.packs.size[1], cfg.packs.size[2]) + (fx.packBonus or 0)
		local name = types[rand(1, #types)].name
		local elites = {}
		for k = 1, size do
			elites[k] = eliteTier(cfg, fx, tier, rand) or false
		end
		plan.packs[#plan.packs + 1] = {room = room, name = name, count = size, elites = elites}
		plan.total = plan.total + size
	end
	plan.bossAt = math.max(1, math.ceil(plan.total * cfg.bossAt / 100))
	plan.boss = types[#types].name -- the strongest type (types are sorted by level)
	return plan
end

-- ===================================================================== rewards
function R.lootTier(cfg, tier)
	for _, row in ipairs(cfg.reward.lootTier) do
		if tier <= row[1] then
			return row[2]
		end
	end
	return "boss"
end

-- whole number with a chance for the fraction: 2.3 -> 2, 30% 3
local function roundChance(x, rand)
	local n = floor(x)
	local frac = x - n
	if frac > 0 and rand(1, 10000) <= floor(frac * 10000 + 0.5) then
		n = n + 1
	end
	return n
end
R.roundChance = roundChance

-- one player's chest (without the item rolls' contents): {gold, chaos, divine, rolls, lootTier, rarityMult}
function R.reward(cfg, tier, bonus, rand)
	local t = R.tierInfo(cfg, tier)
	local q = 1 + (bonus and bonus.quantity or 0) / 100
	local scale = q * t.reward
	local r = cfg.reward
	return {
		gold = floor(r.goldPerTier2 * t.tier * t.tier * scale),
		chaos = roundChance((r.chaos.base + r.chaos.perTier * t.tier) * scale, rand),
		divine = roundChance((r.divine.base + r.divine.perTier * t.tier) * scale, rand),
		rolls = math.max(1, roundChance((r.rolls.base + r.rolls.perTier * t.tier) * scale, rand)),
		countMult = q, -- stack size of a rolled item
		lootTier = R.lootTier(cfg, t.tier),
		rarityMult = 1 + (bonus and bonus.rarity or 0) / 100
	}
end

-- odds of the next key: {chance = percent of a key, nextTier = percent of those that are tier + 1}
function R.keyOdds(cfg, modCount)
	local k = cfg.keyDrop
	modCount = modCount or 0
	return {
		chance = math.min(k.max, k.base + k.perMod * modCount),
		nextTier = math.min(100, k.nextTier + k.nextPerMod * modCount)
	}
end

-- nil, or the new key {tier, mods}
function R.rollKeyDrop(cfg, tier, modCount, rand)
	local odds = R.keyOdds(cfg, modCount)
	if not chance(odds.chance, rand) then
		return nil
	end
	local up = chance(odds.nextTier, rand) and tier < cfg.maxTier
	return R.rollKey(cfg, up and tier + 1 or tier, rand, up)
end

-- per 100000 chance of a tier-1 key from a normal kill (0 when the kill does not qualify)
function R.monsterKeyChance(cfg, monsterLevel, killerLevel, tierName)
	local mk = cfg.monsterKey
	if not monsterLevel or not killerLevel then
		return 0
	end
	if killerLevel < cfg.tiers[1].minLevel then
		return 0
	end
	if monsterLevel < math.max(mk.minMonsterLevel, killerLevel * mk.levelShare) then
		return 0
	end
	return mk.chance * (mk.tierMult[tierName or "normal"] or 1)
end

-- ===================================================================== instance
function R.slotCount(cfg)
	return cfg.grid.cols * cfg.grid.rows
end

function R.slotCenter(cfg, slot)
	local g = cfg.grid
	local col, row = slot % g.cols, floor(slot / g.cols)
	local half = floor(g.spacing / 2)
	return {x = g.origin.x + col * g.spacing + half, y = g.origin.y + row * g.spacing + half, z = g.origin.z}
end

-- first slot that is neither busy nor bad (busy[slot] / bad[slot] = true), or nil
function R.allocSlot(cfg, busy, bad)
	for slot = 0, R.slotCount(cfg) - 1 do
		if not (busy and busy[slot]) and not (bad and bad[slot]) then
			return slot
		end
	end
	return nil
end

-- the slot whose square contains pos, or nil
function R.slotOfPos(cfg, pos)
	local g = cfg.grid
	if not pos or pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / g.spacing), floor(dy / g.spacing)
	if col >= g.cols or row >= g.rows then
		return nil
	end
	return row * g.cols + col
end

R.DIRS = {
	{name = "north", dx = 0, dy = -1},
	{name = "east", dx = 1, dy = 0},
	{name = "south", dx = 0, dy = 1},
	{name = "west", dx = -1, dy = 0}
}

-- layout of a slot, all rooms: {center, hub = rect, rooms = {name = {center, rect}}, doors = {name = {pos...}},
-- floor = {[key] = pos}, walls = {[key] = pos}, floorList, wallList}. rect = inner floor {x1, y1, x2, y2}.
function R.layout(cfg, slot)
	local c = R.slotCenter(cfg, slot)
	local rm = cfg.room
	local z = c.z
	local L = {center = c, rooms = {}, doors = {}, floor = {}, walls = {}, floorList = {}, wallList = {}}
	local function key(x, y)
		return x .. "," .. y
	end
	local function addFloor(x, y)
		local k = key(x, y)
		if not L.floor[k] then
			L.floor[k] = {x = x, y = y, z = z}
			L.floorList[#L.floorList + 1] = L.floor[k]
		end
	end
	local hi = rm.hubHalf - 1
	L.hub = {x1 = c.x - hi, y1 = c.y - hi, x2 = c.x + hi, y2 = c.y + hi}
	for x = L.hub.x1, L.hub.x2 do
		for y = L.hub.y1, L.hub.y2 do
			addFloor(x, y)
		end
	end
	local reach = rm.hubHalf + rm.corridor + 1 + rm.sideHalf -- hub centre -> side room centre
	for _, d in ipairs(R.DIRS) do
		local rc = {x = c.x + d.dx * reach, y = c.y + d.dy * reach, z = z}
		local si = rm.sideHalf - 1
		local rect = {x1 = rc.x - si, y1 = rc.y - si, x2 = rc.x + si, y2 = rc.y + si}
		L.rooms[d.name] = {center = rc, rect = rect}
		for x = rect.x1, rect.x2 do
			for y = rect.y1, rect.y2 do
				addFloor(x, y)
			end
		end
		-- corridor from the hub wall to the room wall (both included: the doorways)
		local door = {}
		for s = rm.hubHalf, rm.hubHalf + rm.corridor + 1 do
			for w = -rm.corridorHalf, rm.corridorHalf do
				local x = c.x + d.dx * s + (d.dx == 0 and w or 0)
				local y = c.y + d.dy * s + (d.dy == 0 and w or 0)
				addFloor(x, y)
				if s == rm.hubHalf then
					door[#door + 1] = {x = x, y = y, z = z}
				end
			end
		end
		L.doors[d.name] = door
	end
	-- walls: every non-floor tile next to a floor tile (8 neighbours)
	for _, p in ipairs(L.floorList) do
		for ox = -1, 1 do
			for oy = -1, 1 do
				local k = key(p.x + ox, p.y + oy)
				if not L.floor[k] and not L.walls[k] then
					L.walls[k] = {x = p.x + ox, y = p.y + oy, z = z}
					L.wallList[#L.wallList + 1] = L.walls[k]
				end
			end
		end
	end
	table.sort(L.wallList, function(a, b)
		return a.y == b.y and a.x < b.x or a.y < b.y
	end)
	L.start = {x = c.x, y = c.y + rm.hubHalf - 3, z = z} -- players arrive at the south part of the hub
	L.bossSpawn = {x = c.x, y = c.y, z = z}
	L.basins = {
		{x = L.hub.x1, y = L.hub.y1, z = z}, {x = L.hub.x2, y = L.hub.y1, z = z},
		{x = L.hub.x1, y = L.hub.y2, z = z}, {x = L.hub.x2, y = L.hub.y2, z = z}
	}
	return L
end

-- which side rooms a run opens: a list of names (rand picks 2-4 of them)
function R.pickRooms(cfg, rand)
	local names = {}
	for _, d in ipairs(R.DIRS) do
		names[#names + 1] = d.name
	end
	local n = rand(cfg.openRooms[1], cfg.openRooms[2])
	local open = {}
	for _ = 1, math.min(n, #names) do
		open[#open + 1] = table.remove(names, rand(1, #names))
	end
	table.sort(open)
	return open
end

-- ===================================================================== run state
-- run = R.newRun(cfg, now, total, bossAt): {state = "running", startTime, deadline, total, killed, bossAt, boss = "waiting"}
function R.newRun(cfg, now, total, bossAt)
	return {state = "running", startTime = now, deadline = now + cfg.timeLimit, total = total, killed = 0,
		bossAt = bossAt or total, boss = "waiting"}
end

function R.timeLeft(run, now)
	if run.state ~= "running" then
		return 0
	end
	return math.max(0, run.deadline - now)
end

-- a rift monster died: "boss" when the boss must appear now, else nil
function R.onKill(run)
	if run.state ~= "running" then
		return nil
	end
	run.killed = math.min(run.total, run.killed + 1)
	if run.boss == "waiting" and run.killed >= run.bossAt then
		run.boss = "alive"
		return "boss"
	end
	return nil
end

-- the boss died: "success" (only while running and before the deadline)
function R.onBossKilled(run, now)
	if run.state ~= "running" or run.boss ~= "alive" then
		return nil
	end
	if now > run.deadline then
		run.state = "failed"
		return "fail"
	end
	run.boss = "dead"
	run.state = "success"
	run.endTime = now
	return "success"
end

-- the periodic check: "fail" once the time is up while the run is still going, else nil
function R.tick(run, now)
	if run.state == "running" and now >= run.deadline then
		run.state = "failed"
		run.endTime = now
		return "fail"
	end
	return nil
end

-- ===================================================================== experience cap
-- experience needed for a level (the engine's formula)
function R.expForLevel(level)
	level = level - 1
	return floor((50 * level * level * level - 150 * level * level + 400 * level) / 3)
end

-- base experience per minute of the leveling model at a level
function R.expRatePerMinute(cfg, level)
	local model = cfg.exp.model
	for _, b in ipairs(model) do
		if level >= b[1] and level < b[2] then
			return (R.expForLevel(b[2]) - R.expForLevel(b[1])) / (b[3] * 60)
		end
	end
	-- past the model: hours per level grow with the experience per level, so the rate stays the last band's
	local b = level < model[1][1] and model[1] or model[#model]
	return (R.expForLevel(b[2]) - R.expForLevel(b[1])) / (b[3] * 60)
end

-- how much of a kill's experience a player keeps: the factor (0..1) and the state updated.
-- st = {base = base experience already credited at full rate}; minutes = time in the run
function R.capFactor(cfg, st, level, base, minutes)
	if base <= 0 then
		return 1
	end
	local e = cfg.exp
	local allowed = R.expRatePerMinute(cfg, level) * math.max(minutes, e.capMinMinutes) * e.capFactor
	local room = allowed - (st.base or 0)
	if room >= base then
		st.base = (st.base or 0) + base
		return 1
	end
	if room > 0 then
		st.base = (st.base or 0) + room
		return (room + (base - room) * e.overCapMult) / base
	end
	return e.overCapMult
end

return R

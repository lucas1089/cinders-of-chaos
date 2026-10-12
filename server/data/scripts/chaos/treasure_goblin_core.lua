-- Treasure Goblin pure logic (no engine calls): spawn roll and exclusions, the Treasure Goblin Chance bonus, variants,
-- area level, health, escape / blink timers, loot amounts. Used by treasure_goblin.lua and tested by server/tests/treasure_goblin_test.lua.
-- Every function takes the config table and, where it rolls, a random function rand(a, b) -> integer in [a, b].
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTreasureGoblinCore = ChaosTreasureGoblinCore or {}
local G = ChaosTreasureGoblinCore

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
G.clamp = clamp

-- ------------------------------------------------------------------ spawn
-- area cell key of a position (one cooldown per cell)
function G.cellKey(cfg, pos)
	local size = cfg.spawn.cellSize or 64
	return string.format("%d:%d:%d", floor(pos.x / size), floor(pos.y / size), pos.z)
end

function G.inRects(rects, pos)
	for _, r in ipairs(rects or {}) do
		if (r[5] == nil or r[5] == pos.z) and pos.x >= r[1] and pos.x <= r[3] and pos.y >= r[2] and pos.y <= r[4] then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------ variants
-- the variant list (a config without `variants` has the one goblin of cfg.name)
function G.variants(cfg)
	if cfg.variants and #cfg.variants > 0 then
		return cfg.variants
	end
	return {{key = "hoarder", name = cfg.name, weight = 1}}
end

-- variant by key or by monster name (any case); nil when none
function G.variant(cfg, keyOrName)
	local k = tostring(keyOrName or ""):lower()
	for _, v in ipairs(G.variants(cfg)) do
		if v.key == k or v.name:lower() == k then
			return v
		end
	end
	return nil
end

function G.isGoblinName(cfg, name)
	name = tostring(name or ""):lower()
	if name == cfg.name:lower() then
		return true
	end
	for _, v in ipairs(G.variants(cfg)) do
		if v.name:lower() == name then
			return true
		end
	end
	return false
end

-- weighted pick of a variant
function G.pickVariant(cfg, rand)
	local list = G.variants(cfg)
	local total = 0
	for _, v in ipairs(list) do
		total = total + (v.weight or 0)
	end
	if total <= 0 then
		return list[1]
	end
	local roll, acc = rand(1, total), 0
	for _, v in ipairs(list) do
		acc = acc + (v.weight or 0)
		if roll <= acc then
			return v
		end
	end
	return list[#list]
end

-- a config view for one variant: cfg with `loot` = the shared loot table with the variant's overrides on top
-- (only the keys the variant gives). Cached on the variant.
function G.forVariant(cfg, variant)
	if not variant or not variant.loot then
		return cfg
	end
	if variant._view and variant._viewOf == cfg then
		return variant._view
	end
	local loot = {}
	for k, v in pairs(cfg.loot) do
		loot[k] = v
	end
	for k, v in pairs(variant.loot) do
		loot[k] = v
	end
	local view = setmetatable({loot = loot}, {__index = cfg})
	variant._view, variant._viewOf = view, cfg
	return view
end

-- ------------------------------------------------------------------ Treasure Goblin Chance
-- the multiplier a respawn's roll gets from the players near it: bonuses = the "goblinchance" totals (percent) of
-- the players within cfg.spoor.radius; the highest counts, at most cfg.spoor.cap. Returns mult (>= 1), best percent.
function G.spoorMult(cfg, bonuses)
	local sp = cfg.spoor or {}
	local best = 0
	for _, b in ipairs(bonuses or {}) do
		b = tonumber(b) or 0
		if b > best then
			best = b
		end
	end
	best = clamp(floor(best), 0, sp.cap or 100)
	return 1 + best / 100, best
end

-- Whether a spawn may become a goblin, before the dice. info = {
--   name, pos, natural (map respawn, not a script's Game.createMonster), startup, summon, boss, hostile,
--   maxHealth, excluded (an engine-side area check said no: protection zone, rift, arena, world boss ...)}
-- state = {alive = n, lastByCell = {[cellKey] = os.time}}. Returns ok, reason.
function G.eligible(cfg, info, state, now)
	local s = cfg.spawn
	if (s.oneIn or 0) <= 0 then
		return false, "disabled"
	end
	if not info.natural then
		return false, "artificial"
	end
	if info.startup and not s.atStartup then
		return false, "startup"
	end
	local name = tostring(info.name or ""):lower()
	if G.isGoblinName(cfg, name) then
		return false, "goblin"
	end
	if info.summon then
		return false, "summon"
	end
	if info.boss then
		return false, "boss"
	end
	if info.hostile == false then
		return false, "critter"
	end
	if (s.skipNames or {})[name] then
		return false, "skipped"
	end
	if (info.maxHealth or 0) < (s.minMaxHealth or 0) then
		return false, "weak"
	end
	if info.excluded then
		return false, "area"
	end
	if info.pos and G.inRects(s.excludedAreas, info.pos) then
		return false, "area"
	end
	if (state.alive or 0) >= (s.maxAlive or 1) then
		return false, "max alive"
	end
	if info.pos then
		local last = state.lastByCell and state.lastByCell[G.cellKey(cfg, info.pos)]
		if last and now - last < (s.areaCooldown or 0) then
			return false, "cooldown"
		end
	end
	return true
end

-- The dice: 1 in cfg.spawn.oneIn (mult > 1 makes it likelier, e.g. an event).
function G.rollSpawn(cfg, rand, mult)
	local n = cfg.spawn.oneIn or 0
	if n <= 0 then
		return false
	end
	n = n / (mult or 1)
	if n <= 1 then
		return true
	end
	return rand(1, floor(n + 0.5)) == 1
end

-- The dice with the Treasure Goblin Chance bonus, without looking for players on every respawn: a first roll as
-- G.rollSpawn with the highest possible bonus (eventMult x (1 + cap%)); only on its hit spoorFn() -> mult (>= 1),
-- percent is asked and the hit kept with chance (wanted odds) / (first roll's odds), wanted = min(1, eventMult x
-- mult / oneIn). Same odds as G.rollSpawn(cfg, rand, eventMult x mult) up to its rounding.
-- Returns hit, the effective 1-in-N (nil when spoorFn was not needed), the bonus percent.
function G.rollWithSpoor(cfg, rand, eventMult, spoorFn)
	eventMult = eventMult or 1
	local oneIn = cfg.spawn.oneIn or 0
	if oneIn <= 0 then
		return false, nil, 0
	end
	local maxMult = 1 + ((cfg.spoor and cfg.spoor.cap) or 0) / 100
	local n1 = oneIn / (eventMult * maxMult)
	local p1 = 1
	if n1 > 1 then
		local sides = floor(n1 + 0.5)
		if rand(1, sides) ~= 1 then
			return false, nil, 0
		end
		p1 = 1 / sides
	end
	local mult, pct = 1, 0
	if spoorFn then
		mult, pct = spoorFn()
	end
	mult = clamp(mult or 1, 1, maxMult)
	local want = math.min(1, eventMult * mult / oneIn)
	local keep = floor(math.min(1, want / p1) * 10000 + 0.5)
	return keep >= 10000 or rand(1, 10000) <= keep, oneIn / (eventMult * mult), pct
end

function G.markSpawn(cfg, state, pos, now)
	state.lastByCell = state.lastByCell or {}
	state.lastByCell[G.cellKey(cfg, pos)] = now
end

-- ------------------------------------------------------------------ level and health
-- monsterLevel: Monster:getMonsterLevel() of the replaced monster (0 = none), playerLevels: levels of nearby players
function G.areaLevel(cfg, monsterLevel, playerLevels, maxHealth)
	local l = cfg.level
	local level
	if (monsterLevel or 0) > 0 then
		level = monsterLevel
	elseif playerLevels and #playerLevels > 0 then
		local sum = 0
		for _, v in ipairs(playerLevels) do
			sum = sum + v
		end
		level = sum / #playerLevels
	else
		level = (maxHealth or 0) / (l.healthPerLevel or 20)
	end
	return clamp(floor(level), l.min or 1, l.max or 1500)
end

function G.realHealth(cfg, level, replacedMaxHealth)
	local h = cfg.health
	local hp = (h.base or 0) + (h.perLevel or 0) * level
	local fromMonster = floor((replacedMaxHealth or 0) * (h.monsterMult or 0))
	if fromMonster > hp then
		hp = fromMonster
	end
	return clamp(floor(hp), 1, h.max or 2000000)
end

-- health shown before the first hit (above the XML runonhealth, so the engine does not flee yet)
function G.dormantHealth(cfg, real)
	return cfg.runThreshold + real
end

-- ------------------------------------------------------------------ timers
-- st = per goblin state. Called on every hit; returns true on the first one.
function G.onHit(cfg, st, nowMs)
	if st.hitAt then
		return false
	end
	st.hitAt = nowMs
	st.escapeAt = nowMs + cfg.behaviour.escapeSeconds * 1000
	return true
end

-- "escape" (first hit + escapeSeconds passed), "expire" (never hit, lifetime over) or nil
function G.due(cfg, st, nowMs)
	if st.hitAt then
		if nowMs >= st.escapeAt then
			return "escape"
		end
	elseif nowMs - (st.bornAt or nowMs) >= cfg.behaviour.lifetimeSeconds * 1000 then
		return "expire"
	end
	return nil
end

-- blink: only while fleeing; returns true when a blink should happen now and schedules the next one
function G.blinkDue(cfg, st, nowMs, rand)
	if not st.hitAt then
		return false
	end
	local b = cfg.behaviour
	if not st.nextBlink then
		st.nextBlink = nowMs + rand(b.blinkEveryMs[1], b.blinkEveryMs[2])
		return false
	end
	if nowMs < st.nextBlink then
		return false
	end
	st.nextBlink = nowMs + rand(b.blinkEveryMs[1], b.blinkEveryMs[2])
	return rand(1, 100) <= b.blinkChance
end

function G.tauntDue(cfg, st, nowMs, rand)
	local b = cfg.behaviour
	if st.lastTaunt and nowMs - st.lastTaunt < b.tauntCooldownMs then
		return false
	end
	if rand(1, 100) > b.tauntChance then
		return false
	end
	st.lastTaunt = nowMs
	return true
end

-- the speed delta (for Creature:changeSpeed) that makes the goblin run at attacker speed x mult
function G.fleeSpeedDelta(cfg, ownSpeed, attackerSpeed)
	local b = cfg.behaviour
	local target = floor((attackerSpeed or 0) * b.fleeSpeedMult)
	if target < ownSpeed + b.minBoost then
		target = ownSpeed + b.minBoost
	end
	if target > b.maxSpeed then
		target = b.maxSpeed
	end
	return math.max(0, target - ownSpeed)
end

-- best blink destination: of the candidate positions, the one farthest (sum of squared distances) from the attackers
function G.bestBlink(candidates, attackers)
	local best, bestScore
	for _, c in ipairs(candidates) do
		local score = 0
		for _, a in ipairs(attackers) do
			local dx, dy = c.x - a.x, c.y - a.y
			score = score + dx * dx + dy * dy
		end
		if not bestScore or score > bestScore then
			best, bestScore = c, score
		end
	end
	return best
end

-- ------------------------------------------------------------------ loot
function G.goldValue(cfg, level, rand)
	local g = cfg.loot.gold
	local base = (g.base or 0) + (g.perLevel or 0) * level
	return floor(base * rand(g.minMult, g.maxMult) / 100 * (cfg.loot.goldMult or 100) / 100)
end

-- gold value -> {{id, count}, ...} in crystal (2160), platinum (2152) and gold (2148) coins, stacks of at most 100
function G.coins(value)
	local out = {}
	local function add(id, n)
		while n > 0 do
			local c = math.min(100, n)
			out[#out + 1] = {id = id, count = c}
			n = n - c
		end
	end
	add(2160, floor(value / 10000))
	value = value % 10000
	add(2152, floor(value / 100))
	add(2148, value % 100)
	return out
end

function G.chaosOrbs(cfg, level, rand)
	local o = cfg.loot.chaosOrb
	if (o.cap or 1) <= 0 then
		return 0
	end
	local n = rand(o.min, o.max) + floor(level / (o.perLevels or 1000000))
	return math.min(n, o.cap or n)
end

-- Gem Goblin: number of gems (0 when the variant has none)
function G.gemCount(cfg, level, rand)
	local g = cfg.loot.gems
	if not g then
		return 0
	end
	local n = rand(g.min, g.max) + floor(level / (g.perLevels or 1000000))
	return math.min(n, g.cap or n)
end

-- Gem Goblin: Orbs of Sockets
function G.socketOrbs(cfg, rand)
	local o = cfg.loot.socketOrb
	if not o then
		return 0
	end
	local n = o.count or 0
	if (o.extraChance or 0) > 0 and rand(1, 100) <= o.extraChance then
		n = n + 1
	end
	return n
end

-- Shard Goblin: Rune Shards
function G.shardCount(cfg, level, rand)
	local s = cfg.loot.shards
	if not s then
		return 0
	end
	local base = (s.base or 0) + level / (s.perLevel or 1000000)
	local n = floor(base * rand(s.minMult or 100, s.maxMult or 100) / 100)
	return clamp(n, 0, s.cap or n)
end

-- Shard Goblin: crafting orb keys (ChaosCrafting orb keys), picked by weight
function G.orbKeys(cfg, rand)
	local o = cfg.loot.orbs
	local out = {}
	if not o or not o.weights or #o.weights == 0 then
		return out
	end
	local total = 0
	for _, w in ipairs(o.weights) do
		total = total + w[2]
	end
	for i = 1, o.count or 0 do
		local roll, acc = rand(1, total), 0
		for _, w in ipairs(o.weights) do
			acc = acc + w[2]
			if roll <= acc then
				out[i] = w[1]
				break
			end
		end
	end
	return out
end

-- itemFind: ChaosLoot.itemFindMult (1 = none)
function G.divineOrb(cfg, itemFind, rand)
	local chance = cfg.loot.divineOrb.chance * (itemFind or 1)
	return rand(1, 10000) <= chance * 100
end

function G.itemCount(cfg, rand)
	return rand(cfg.loot.items.min, cfg.loot.items.max)
end

function G.pickItemTier(cfg, rand)
	local total = 0
	for _, t in ipairs(cfg.loot.itemTiers) do
		total = total + t.weight
	end
	local roll, acc = rand(1, total), 0
	for _, t in ipairs(cfg.loot.itemTiers) do
		acc = acc + t.weight
		if roll <= acc then
			return t
		end
	end
	return cfg.loot.itemTiers[#cfg.loot.itemTiers]
end

-- fallback gear ids for an area level: the highest band whose minimum the level reaches
function G.poolFor(cfg, level)
	local best
	for _, band in ipairs(cfg.loot.pool) do
		if level >= band[1] then
			best = band[2]
		end
	end
	return best or {}
end

-- n gear ids: from `gear` (the replaced monster's gear ids) when it has any, otherwise from the pool
function G.pickGear(cfg, level, gear, n, rand)
	local src = (gear and #gear > 0) and gear or G.poolFor(cfg, level)
	local out = {}
	if #src == 0 then
		return out
	end
	for i = 1, n do
		out[i] = src[rand(1, #src)]
	end
	return out
end

function G.experience(cfg, replacedExp, level)
	local e = cfg.experience
	local xp = floor((replacedExp or 0) * e.mult)
	if xp < e.min then
		xp = e.min
	end
	local cap = math.max(e.min, level * e.capPerLevel)
	if xp > cap then
		xp = cap
	end
	return xp
end

-- uniques eligible for the hoard roll (list from ChaosLoot.uniqueList: {name, id, bossOnly, level})
function G.hoardCandidates(cfg, list, level)
	local out = {}
	local slack = cfg.loot.uniqueHoard.levelSlack or 0
	for _, e in ipairs(list or {}) do
		local seasonBlocked = e.season and ChaosSeason and ChaosSeason.uniqueBlocked and ChaosSeason.uniqueBlocked(e.season)
		if not e.bossOnly and not seasonBlocked and (tonumber(e.level) or 0) <= level + slack then
			out[#out + 1] = e
		end
	end
	return out
end

return G

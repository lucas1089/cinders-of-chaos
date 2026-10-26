-- The Ascended Omens and the Cinderheart: the pure part (no engine calls), shared by uber.lua and tests/uber_test.lua.
-- ("uber" in the file names only; players read "Ascended" and "Cinderheart".)
--   kinds      lookup by key / index, names of the sigils, relics and shards
--   chain      shard drops (Omen kills, high rifts), shards -> sigil, relics -> the Cinderheart sigil
--   scaling    health of the boss and its adds by party size, the party's damage and reward bonus, shared lives
--   fight      the phase machine (health thresholds, each phase once and in order), enrage and time limit, the
--              telegraph timing, adds per wave, the Harvest heal, the caught lethal hit
--   geometry   the arena slots (layout, slot of a position) and the telegraph / hazard shapes
--   rewards    one finisher's spoils, the leaderboard of a party size, the balance model
-- Every random number comes from the `rand(a, b)` argument (integer in [a, b]). Lua 5.1 / LuaJIT and Lua 5.3.

ChaosUberCore = ChaosUberCore or {}
local U = ChaosUberCore

-- the telegraph shapes, the mark plan and the warning pulses are the shared boss mechanics core's
-- (boss_mechanics_core.lua, server/README.md "Boss mechanics")
if not ChaosBossMechCore then
	dofile("data/scripts/chaos/boss_mechanics_core.lua")
end
local G = ChaosBossMechCore

local floor, abs, sqrt = math.floor, math.abs, math.sqrt

-- the text in `lang` (ChaosI18n when it is loaded, English otherwise); uber.lua passes the language of the reader
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local function key(x, y)
	return x .. "," .. y
end
U.key = key

-- ===================================================================== kinds
-- a kind by key ("bloodmoon") or index; returns def, index
function U.kind(cfg, k)
	for i, d in ipairs(cfg.kinds) do
		if d.key == k or i == k then
			return d, i
		end
	end
	return nil
end

-- the three Ascended Omens (every kind but the final one), in order
function U.ascendedKinds(cfg)
	local out = {}
	for _, d in ipairs(cfg.kinds) do
		if not d.final then
			out[#out + 1] = d
		end
	end
	return out
end

function U.finalKind(cfg)
	for _, d in ipairs(cfg.kinds) do
		if d.final then
			return d
		end
	end
	return nil
end

-- the kind of a boss name (case-insensitive), or nil
function U.kindOfBoss(cfg, name)
	name = tostring(name or ""):lower()
	for _, d in ipairs(cfg.kinds) do
		if d.boss:lower() == name then
			return d
		end
	end
	return nil
end

function U.sigilName(cfg, kind)
	local d = U.kind(cfg, kind)
	if not d then
		return "Ascended Sigil"
	end
	if d.final then
		return "Cinderheart Sigil"
	end
	return "Ascended Sigil of the " .. d.name
end

function U.relicName(cfg, kind)
	local d = U.kind(cfg, kind)
	return "Ascended Relic of the " .. (d and d.name or "?")
end

-- the shard item id -> kind key, or nil
function U.shardKind(cfg, id)
	for k, s in pairs(cfg.items.shards) do
		if s.id == id then
			return k
		end
	end
	return nil
end

-- ===================================================================== chain
-- a shard chance (percent) x the party bonus of `players` (who entered), rounded to a whole percent, at most 100
function U.shardChance(cfg, chance, players)
	chance = chance or 0
	local m = U.party(cfg, players).reward
	if m == 1 or chance <= 0 then
		return chance
	end
	return math.min(100, floor(chance * m + 0.5))
end

-- one finisher of an Omen guardian kill of `omenKind` (the rift's kind keys are ours): the shard kind or nil.
-- players = who entered the arena (the party bonus on the chance; nil = solo)
function U.shardFromOmen(cfg, omenKind, rand, players)
	if not cfg.items.shards[omenKind or ""] then
		return nil
	end
	if rand(1, 100) <= U.shardChance(cfg, cfg.shardChance.omen, players) then
		return omenKind
	end
	return nil
end

-- one finisher of a sealed rift of `tier`: the shard kind (a random Ascended Omen) or nil; players as above
function U.shardFromRift(cfg, tier, rand, players)
	local chance = U.shardChance(cfg, cfg.shardChance.rift[tonumber(tier) or 0], players)
	if chance <= 0 or rand(1, 100) > chance then
		return nil
	end
	local list = U.ascendedKinds(cfg)
	return list[rand(1, #list)].key
end

-- shards -> sigils: how many sigils `have` shards bind and how many shards that takes
function U.bindShards(cfg, have)
	local n = floor((tonumber(have) or 0) / cfg.shardCost)
	if n < 1 then
		return 0, 0
	end
	return 1, cfg.shardCost -- one sigil per use
end

-- relics carried ({kind key, ...}, one entry per relic) -> true and the list of kinds to take (one of each Ascended
-- Omen), or false and the missing kinds
function U.relicsComplete(cfg, carried)
	local have = {}
	for _, k in ipairs(carried or {}) do
		have[k] = true
	end
	local take, missing = {}, {}
	for _, d in ipairs(U.ascendedKinds(cfg)) do
		if have[d.key] then
			take[#take + 1] = d.key
		else
			missing[#missing + 1] = d.key
		end
	end
	if #missing > 0 then
		return false, missing
	end
	return true, take
end

-- the crash refund marker: the index of the sigil's kind (0 / unset = no run)
function U.marker(cfg, kind)
	local _, i = U.kind(cfg, kind)
	return i or 0
end

function U.markerKind(cfg, value)
	local d = U.kind(cfg, tonumber(value) or 0)
	return d and d.key or nil
end

-- ===================================================================== scaling
function U.healthMult(def, players)
	return 1 + (def.healthPerExtraPlayer or 0) * (math.max(1, tonumber(players) or 1) - 1)
end

function U.addHealthMult(cfg, players)
	return 1 + (cfg.addHealthPerExtraPlayer or 0) * (math.max(1, tonumber(players) or 1) - 1)
end

-- cfg.party (uber_config.lua), n players who entered: damage = the boss's and adds' hits x (1 + damagePerExtraPlayer x
-- (n - 1)); reward = the spoils x (1 + min(rewardCap, rewardPerExtraPlayer x (n - 1)) / 100); loot = the unique find x
-- (1 + min(lootCap, lootPerExtraPlayer x (n - 1)) / 100). Solo (or no cfg.party): every value 1.
function U.party(cfg, players)
	local p = cfg and cfg.party
	local extra = math.max(1, floor(tonumber(players) or 1)) - 1
	if not p or extra == 0 then
		return {players = extra + 1, damage = 1, reward = 1, loot = 1}
	end
	return {
		players = extra + 1,
		damage = 1 + (p.damagePerExtraPlayer or 0) * extra,
		reward = 1 + math.min(p.rewardCap or 0, (p.rewardPerExtraPlayer or 0) * extra) / 100,
		loot = 1 + math.min(p.lootCap or 0, (p.lootPerExtraPlayer or 0) * extra) / 100
	}
end

-- the chat line of a party's scaling ("Party of 3: boss health x3, damage +20%; spoils +20%."), nil solo
function U.partyNote(cfg, def, players, lang)
	local ps = U.party(cfg, players)
	if ps.players <= 1 then
		return nil
	end
	return T(lang, "Party of %d: boss health x%s, damage +%d%%; spoils +%d%%.", ps.players,
		tostring(floor(U.healthMult(def, ps.players) * 100 + 0.5) / 100), floor((ps.damage - 1) * 100 + 0.5),
		floor((ps.reward - 1) * 100 + 0.5))
end

-- x with a chance for the fraction (2.4 -> 2, 40% 3); no rand: rounded down
local function roundChance(x, rand)
	local n = floor(x)
	local frac = x - n
	if frac > 0 and rand and rand(1, 10000) <= floor(frac * 10000 + 0.5) then
		n = n + 1
	end
	return n
end
U.roundChance = roundChance

function U.livesFor(def, players)
	local l = def.lives or {base = 3, perExtraPlayer = 1}
	return math.max(1, l.base + l.perExtraPlayer * (math.max(1, tonumber(players) or 1) - 1))
end

-- one life less; returns the lives left
function U.loseLife(run)
	run.deaths = (run.deaths or 0) + 1
	run.lives = math.max(0, (run.lives or 1) - 1)
	return run.lives
end

-- ===================================================================== fight
-- the phase index for a health fraction: the last phase whose `at` the fraction has reached (at or below)
function U.phaseIndex(def, frac)
	local idx = 1
	for i, p in ipairs(def.phases) do
		if frac <= p.at then
			idx = i
		end
	end
	return idx
end

-- moves run.phase forward to the phase of `frac` (never back); returns the list of phases entered, in order (a big
-- hit through two thresholds enters both, so every phase start - yell, adds, hazard - happens once)
function U.advancePhase(run, def, frac)
	local want = U.phaseIndex(def, frac)
	local entered = {}
	local cur = run.phase or 0
	while cur < want do
		cur = cur + 1
		entered[#entered + 1] = cur
	end
	run.phase = math.max(run.phase or 0, want)
	return entered
end

-- elapsed = seconds since the boss appeared -> enraged (bool), seconds to the enrage (0 once enraged), seconds to the
-- time limit (0 = time is up)
function U.clock(def, elapsed)
	elapsed = math.max(0, elapsed or 0)
	return elapsed >= def.enrageAt, math.max(0, def.enrageAt - elapsed), math.max(0, def.limit - elapsed)
end

-- ms between two telegraphs of a phase
function U.patternEvery(cfg, phase, enraged)
	local every = phase.every or 9000
	if enraged then
		every = floor(every * (cfg.enrage.everyMult or 1))
	end
	return math.max(1500, every)
end

-- the telegraph timing: the danger mark pulses from 0 until the hit (boss_mechanics_core.lua G.pulses; kinds[i] =
-- "zone" or "fill", the filling mark in the last turn), the hit at warnMs (never under 1.5 s); share of max health
function U.telegraphTiming(cfg, enraged)
	local t = cfg.telegraph
	local warn = math.max(G.MIN_WARN, enraged and t.enragedWarnMs or t.warnMs)
	local marks, kinds = {}, {}
	for _, p in ipairs(G.pulses(warn, t.pulseMs or t.turnMs, t.fillMs)) do
		marks[#marks + 1] = p.at
		kinds[#kinds + 1] = p.kind
	end
	return {marks = marks, kinds = kinds, hitMs = warn, share = enraged and t.enragedShare or t.share}
end

-- damage of a share of max health (at least 1)
function U.shareDamage(maxHealth, share)
	return math.max(1, floor((tonumber(maxHealth) or 0) * (share or 0) + 0.5))
end

-- the damage multiplier of a hit by the boss or an add: the enrage x the party's damage (players = who entered)
function U.damageMult(cfg, enraged, players)
	return (enraged and cfg.enrage.damageMult or 1) * U.party(cfg, players).damage
end

-- adds of one wave
function U.addCount(adds, players)
	if not adds then
		return 0
	end
	return math.max(0, floor((adds.base or 0) + (adds.perPlayer or 0) * math.max(1, players or 1)))
end

-- the Harvest heal of one 5 s step: perAdd x max health per living add
function U.harvestHeal(heal, liveAdds, maxHealth)
	if not heal or (liveAdds or 0) <= 0 then
		return 0
	end
	return floor((heal.perAdd or 0) * liveAdds * (maxHealth or 0))
end

-- a hit on a player inside the arena: the damage that is lethal past health + energy shield is cut to leave 1 health;
-- returns primary, secondary (absolute values) and whether it was caught
function U.catchDamage(pool, p, s)
	p, s = abs(p or 0), abs(s or 0)
	if p + s < pool then
		return p, s, false
	end
	local room = math.max(0, pool - 1)
	if p >= room then
		return room, 0, true
	end
	return p, room - p, true
end

-- ===================================================================== geometry
function U.slotCenter(cfg, slot)
	local g = cfg.grid
	local i = slot - 1
	local h = floor(g.spacing / 2)
	return {x = g.origin.x + (i % g.cols) * g.spacing + h, y = g.origin.y + floor(i / g.cols) * g.spacing + h - 6,
		z = g.origin.z}
end

-- the slot of a position (its whole footprint, antechamber included), or nil
function U.slotAt(cfg, pos)
	local g = cfg.grid
	if not pos or pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / g.spacing), floor(dy / g.spacing)
	if col >= g.cols then
		return nil
	end
	local slot = row * g.cols + col + 1
	if slot > g.slots then
		return nil
	end
	return slot
end

-- the layout of a slot: the arena (floor half-size `half`), the antechamber south of it, the walls (every non-floor
-- tile next to a floor tile), the Ember Gate (portal) in the antechamber, the arena entry, the boss spawn, the starts
-- of the players and the corner basins
function U.layout(cfg, slot)
	local a = cfg.arena
	local c = U.slotCenter(cfg, slot)
	local z = c.z
	local L = {center = c, half = a.half, floor = {}, floorList = {}, ante = {}, anteList = {}, walls = {}, wallList = {}}
	L.rect = {x1 = c.x - a.half, y1 = c.y - a.half, x2 = c.x + a.half, y2 = c.y + a.half}
	for y = L.rect.y1, L.rect.y2 do
		for x = L.rect.x1, L.rect.x2 do
			local t = {x = x, y = y, z = z}
			L.floor[key(x, y)] = t
			L.floorList[#L.floorList + 1] = t
		end
	end
	-- the antechamber: anteGap rows of wall below the arena, then (2 anteHalfH + 1) rows
	local acy = L.rect.y2 + a.anteGap + a.anteHalfH + 1
	L.anteRect = {x1 = c.x - a.anteHalfW, y1 = acy - a.anteHalfH, x2 = c.x + a.anteHalfW, y2 = acy + a.anteHalfH}
	for y = L.anteRect.y1, L.anteRect.y2 do
		for x = L.anteRect.x1, L.anteRect.x2 do
			local t = {x = x, y = y, z = z}
			L.ante[key(x, y)] = t
			L.anteList[#L.anteList + 1] = t
		end
	end
	for _, list in ipairs({L.floorList, L.anteList}) do
		for _, p in ipairs(list) do
			for ox = -1, 1 do
				for oy = -1, 1 do
					local k = key(p.x + ox, p.y + oy)
					if not L.floor[k] and not L.ante[k] and not L.walls[k] then
						L.walls[k] = {x = p.x + ox, y = p.y + oy, z = z}
						L.wallList[#L.wallList + 1] = L.walls[k]
					end
				end
			end
		end
	end
	-- the gap rows between the two rooms are wall too (solid, no tile without a wall between them)
	for y = L.rect.y2 + 1, L.anteRect.y1 - 1 do
		for x = L.anteRect.x1 - 1, L.anteRect.x2 + 1 do
			local k = key(x, y)
			if not L.walls[k] then
				L.walls[k] = {x = x, y = y, z = z}
				L.wallList[#L.wallList + 1] = L.walls[k]
			end
		end
	end
	table.sort(L.wallList, function(p, q)
		return p.y == q.y and p.x < q.x or p.y < q.y
	end)
	L.portal = {x = c.x, y = acy, z = z}
	L.anteStart = {x = c.x - 2, y = acy, z = z}
	L.entry = {x = c.x, y = L.rect.y2 - 1, z = z}
	L.bossSpawn = {x = c.x, y = c.y - 3, z = z}
	L.starts = {}
	for _, o in ipairs({{0, 0}, {-1, 0}, {1, 0}, {-2, 0}, {2, 0}}) do
		L.starts[#L.starts + 1] = {x = L.entry.x + o[1], y = L.entry.y + o[2], z = z}
	end
	L.basins = {{x = L.rect.x1, y = L.rect.y1, z = z}, {x = L.rect.x2, y = L.rect.y1, z = z},
		{x = L.rect.x1, y = L.rect.y2, z = z}, {x = L.rect.x2, y = L.rect.y2, z = z}}
	L.z = z
	return L
end

function U.inArena(L, pos)
	return pos ~= nil and pos.z == L.z and L.floor[key(pos.x, pos.y)] ~= nil
end

function U.inAnte(L, pos)
	return pos ~= nil and pos.z == L.z and L.ante[key(pos.x, pos.y)] ~= nil
end

-- a free slot: the first one not busy and not bad
function U.allocSlot(cfg, busy, bad)
	for slot = 1, cfg.grid.slots do
		if not busy[slot] and not (bad and bad[slot]) then
			return slot
		end
	end
	return nil
end

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end
U.dist = dist

-- collects tiles of the arena for which want(x, y) is true (arena order: rows north to south)
local function collect(L, want)
	local out = {}
	for _, t in ipairs(L.floorList) do
		if want(t.x, t.y) then
			out[#out + 1] = t
		end
	end
	return out
end

-- the main direction from a to b: dx, dy in {-1, 0, 1}, one of them 0 (south when equal)
U.direction = G.direction

-- a telegraph shape (boss_mechanics_core.lua G.shape over the arena floor). ctx = {L, boss = pos, target = pos,
-- players = {pos, ...}, rand, size}. Returns the tiles (arena only) and info ({side = "n" | ..., safe = pos,
-- lines = {...}}). size (the boss's footprint, 1 by default) widens the shape (G.scaleShape).
function U.pattern(name, cfg, ctx)
	local spec = {kind = name}
	for k, v in pairs(cfg.patterns[name] or {}) do
		spec[k] = v
	end
	if (ctx.size or 1) > 1 then
		spec = G.scaleShape(spec, ctx.size)
	end
	return G.shape(spec, {list = ctx.L.floorList, rect = ctx.L.rect, z = ctx.L.z, boss = ctx.boss or ctx.L.center,
		target = ctx.target, players = ctx.players, rand = ctx.rand, size = ctx.size})
end

-- hazard tiles of a phase. h = the phase's hazard; ctx as U.pattern plus depth (edge). pools: count + perPlayer x
-- players circles of `radius` at random arena tiles away from the entry; columns: single random tiles; edge: every tile
-- within `depth` of the arena's wall.
function U.hazardTiles(h, ctx)
	local L, rand = ctx.L, ctx.rand
	if h.kind == "edge" then
		local d = ctx.depth or 1
		return collect(L, function(x, y)
			return x - L.rect.x1 < d or L.rect.x2 - x < d or y - L.rect.y1 < d or L.rect.y2 - y < d
		end)
	end
	local n = (h.count or 1) + (h.perPlayer or 0) * math.max(1, ctx.playerCount or 1)
	local centers = {}
	for _ = 1, n do
		centers[#centers + 1] = {x = rand(L.rect.x1 + 1, L.rect.x2 - 1), y = rand(L.rect.y1 + 1, L.rect.y2 - 2), z = L.z}
	end
	local r = h.radius or 0
	return collect(L, function(x, y)
		for _, c in ipairs(centers) do
			if dist({x = x, y = y}, c) <= r then
				return true
			end
		end
		return false
	end)
end

-- the set (key -> true) of a tile list
U.tileSet = G.tileSet

-- how to show a telegraph's tiles (boss_mechanics_core.lua G.markPlan): 3x3 warning pictures only where they cannot
-- spill onto a safe tile, a one-tile effect on the rest. Returns {big = tiles, small = tiles}.
U.markPlan = G.markPlan

-- ===================================================================== rewards
-- one finisher's spoils: {gold, chaos, divine, exalted, uniqueRolls, uniqueFind, gearRolls, relic = kind or nil,
-- partyMult}. players = who entered: gold, orbs and gear rolls x the party bonus (fractions a chance of one more with
-- rand, else rounded down), uniqueFind x the loot bonus; the relic stays one. Solo: the config's numbers.
function U.reward(cfg, def, players, rand)
	local r = def.final and cfg.reward.cinder or cfg.reward.ascended
	local ps = U.party(cfg, players)
	local m = ps.reward
	return {gold = floor(r.gold * m), chaos = roundChance(r.chaos * m, rand), divine = roundChance(r.divine * m, rand),
		exalted = roundChance((r.exalted or 0) * m, rand), uniqueRolls = r.uniqueRolls, uniqueFind = r.uniqueFind * ps.loot,
		gearRolls = roundChance(r.gearRolls * m, rand), relic = (r.relic and not def.final) and def.key or nil,
		partyMult = m}
end

-- the leaderboard of a Cinderheart kill by party size
function U.boardFor(cfg, players)
	for _, b in ipairs(cfg.boards) do
		if (players or 1) <= b.max then
			return b.key
		end
	end
	return cfg.boards[#cfg.boards].key
end

-- the achievement stats of a kill: list of {stat, amount}
function U.killStats(def, info)
	local out = {}
	if def.final then
		out[#out + 1] = {"cinder_kills", 1}
		if (info.players or 1) == 1 then
			out[#out + 1] = {"cinder_solo", 1}
		end
		if (info.deaths or 0) == 0 then
			out[#out + 1] = {"cinder_flawless", 1}
		end
	else
		out[#out + 1] = {"ascended_kills", 1}
		out[#out + 1] = {"ascended_" .. def.key, 1}
	end
	return out
end

function U.clockText(secs)
	secs = math.max(0, floor(secs or 0))
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

-- the balance model: seconds to kill def's boss with `players` well-geared level 1000 characters (one of them the
-- healer when players > 1): health x healthMult / (sum of dps x uptime)
function U.killTime(cfg, def, players, health)
	local m = cfg.model
	players = math.max(1, players or 1)
	local dps = players == 1 and m.refDps or (m.refDps * (players - 1) + m.healerDps)
	local uptime = players == 1 and m.uptimeSolo or m.uptimeParty
	return health * U.healthMult(def, players) / (dps * uptime)
end

-- the HUD (rift HUD, opcode 228) of a run: the same fields as a rift's, the boss state in `notes`
-- s = {def, phase, phaseName, phases, left, limit, enraged, toEnrage, lives, livesMax, boss = waiting|alive|dead,
--      state, hp (0..100), adds}
function U.hud(s, lang)
	local notes = {}
	if s.boss == "alive" then
		notes[#notes + 1] = T(lang, "Phase %d of %d: %s", s.phase or 1, s.phases or 1, s.phaseName or "")
		notes[#notes + 1] = T(lang, "Health: %d%%", s.hp or 100)
		if s.enraged then
			notes[#notes + 1] = T(lang, "ENRAGED: every hit is far stronger.")
		else
			notes[#notes + 1] = T(lang, "Enrage in %s", U.clockText(s.toEnrage))
		end
		if (s.adds or 0) > 0 then
			notes[#notes + 1] = T(lang, "Adds: %d", s.adds)
		end
	end
	if (s.waiting or 0) > 0 then
		notes[#notes + 1] = T(lang, "%d at the Ember Gate.", s.waiting)
	end
	return {tier = 15, theme = s.def.final and "The Cinderheart" or ("Ascended " .. s.def.name), left = s.left, limit = s.limit,
		total = 0, killed = 0, bossAt = 0, boss = s.boss, state = s.state, bossName = s.def.boss, mods = {}, notes = notes,
		lives = s.lives, livesMax = s.livesMax, omen = s.def.final and "the Cinderheart" or ("Ascended " .. s.def.name),
		title = s.def.final and "The Cinderheart" or T(lang, "Ascended Omen - %s", s.def.name)}
end

return U

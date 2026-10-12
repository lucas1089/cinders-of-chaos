-- Run from the server/ folder: luajit tests/uber_test.lua (or lua5.3; CI runs both)
-- The Ascended Omens and the Cinderheart: uber_core.lua (pure: kinds, the shard / sigil / relic chain, scaling, the
-- phase machine, enrage, telegraph timing and shapes, hazards, the caught lethal hit, rewards, the balance model) and
-- uber.lua against a mocked engine (shards bind a sigil, the sigil opens an arena for the party, the boss comes,
-- phases at the thresholds, a telegraph hits the player left on its tiles, a caught lethal hit and the Ember Gate,
-- the last life, the kill and its spoils, relics -> the Cinderheart Sigil, the rift hook, the crash refund).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
CONST_SLOT_HEAD, CONST_SLOT_BACKPACK, CONST_SLOT_AMMO = 1, 3, 10

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/uber_config.lua")
dofile("data/scripts/chaos/uber_core.lua")
local U = ChaosUberCore

local function seq(list)
	local i = 0
	return function(a, b)
		i = i + 1
		local v = list[(i - 1) % #list + 1]
		if v == "max" then
			return b
		end
		return math.max(a, math.min(b, v))
	end
end

-- ================================================================== the config
local asc = U.ascendedKinds(cfg)
eq(#asc, 3, "three Ascended Omens")
local final = U.finalKind(cfg)
check(final and final.key == "cinder", "the Cinderheart is the final kind")
local omenCfg = dofile("data/scripts/chaos/rift_config.lua").omen
for i, d in ipairs(asc) do
	eq(d.key, omenCfg.kinds[i].key, "the Ascended kinds use the omen kind keys: " .. d.key)
	eq(d.omenBoss, omenCfg.kinds[i].boss, "the omen of " .. d.key)
	check(cfg.items.shards[d.key] ~= nil, "a shard per omen: " .. d.key)
end
local ids, seenIds = {}, {}
for _, s in pairs(cfg.items.shards) do
	ids[#ids + 1] = s.id
end
ids[#ids + 1] = cfg.items.sigil.id
ids[#ids + 1] = cfg.items.relic.id
for _, id in ipairs(ids) do
	check(not seenIds[id], "item ids distinct: " .. id)
	seenIds[id] = true
	check(id >= 32073 and id <= 32077, "item id in 32073..32077 (omens 32071..72, pouches 32081..83): " .. id)
end
for _, d in ipairs(cfg.kinds) do
	local last = 2
	eq(d.phases[1].at, 1.0, d.key .. ": the first phase starts at full health")
	for _, ph in ipairs(d.phases) do
		check(ph.at < last, d.key .. ": phases in falling order")
		last = ph.at
		for _, p in ipairs(ph.patterns) do
			check(cfg.patterns[p] ~= nil, d.key .. ": pattern " .. p .. " is known")
		end
		if ph.hazard then
			check(ph.hazard.kind == "pools" or ph.hazard.kind == "columns" or ph.hazard.kind == "edge", d.key .. ": hazard kind")
		end
	end
	check(d.enrageAt < d.limit, d.key .. ": the enrage comes before the time limit")
	check(cfg.kinds[1].boss ~= d.add, d.key .. ": the add is no boss")
	-- the monster files exist with the names, and the boss looks are in the client pair (picks.csv)
	local fn = "data/monster/monsters/chaos/ascended/" .. d.boss:lower():gsub(" ", "_") .. ".xml"
	local f = io.open(fn)
	check(f ~= nil, "boss XML " .. fn)
	if f then
		local t = f:read("*a")
		f:close()
		check(t:find('<monster name="' .. d.boss .. '"', 1, true) ~= nil, "boss name in " .. fn)
		check(t:find('<flag isboss="1" />', 1, true) ~= nil, "isboss in " .. fn)
		check(not t:find('radius="6"', 1, true), "no untelegraphed radius 6 hit in " .. fn)
		check(not t:find('name="healing"', 1, true), "no self-heal in " .. fn)
		local look = tonumber(t:match('<look type="(%d+)"'))
		if d.final then
			eq(look, 2126, "the Cinderheart's own look")
		else
			check(look and look >= 2116 and look <= 2118, "an Ascended Omen wears its omen's look")
		end
	end
	local af = io.open("data/monster/monsters/chaos/ascended/" .. d.add:lower():gsub(" ", "_") .. ".xml")
	check(af ~= nil, "add XML of " .. d.add)
	if af then
		check(af:read("*a"):find('<monster name="' .. d.add .. '"', 1, true) ~= nil, "add name " .. d.add)
		af:close()
	end
end
local picks = io.open("../client/tools/sprites/monster_looks/picks.csv")
if picks then
	local t = picks:read("*a")
	picks:close()
	check(t:find("\ncinderheart,2126,", 1, true) ~= nil, "look 2126 in picks.csv")
end

-- ================================================================== kinds and names
eq(U.kind(cfg, "hollow").boss, "Ascended Morvane", "kind by key")
eq(select(2, U.kind(cfg, "storm")), 3, "kind index")
eq(U.kind(cfg, 4).key, "cinder", "kind by index")
eq(U.kind(cfg, "nope"), nil, "unknown kind")
eq(U.kindOfBoss(cfg, "ascended sangrith").key, "bloodmoon", "kind of a boss name, any case")
eq(U.sigilName(cfg, "bloodmoon"), "Ascended Sigil of the Bloodmoon", "sigil name")
eq(U.sigilName(cfg, "cinder"), "Cinderheart Sigil", "the final sigil")
eq(U.relicName(cfg, "storm"), "Ascended Relic of the Storm", "relic name")
eq(U.shardKind(cfg, 32074), "hollow", "shard id -> kind")
eq(U.shardKind(cfg, 1), nil, "no shard")
for i, d in ipairs(cfg.kinds) do
	eq(U.markerKind(cfg, U.marker(cfg, d.key)), d.key, "marker round trip " .. d.key)
	eq(U.marker(cfg, d.key), i, "marker = index")
end
eq(U.markerKind(cfg, 0), nil, "no marker")
eq(U.markerKind(cfg, -1), nil, "unset marker")

-- ================================================================== the chain
eq(U.shardFromOmen(cfg, "storm", seq({cfg.shardChance.omen})), "storm", "omen kill: a shard at the chance")
eq(U.shardFromOmen(cfg, "storm", seq({cfg.shardChance.omen + 1})), nil, "omen kill: above the chance")
eq(U.shardFromOmen(cfg, "nope", seq({1})), nil, "unknown omen")
eq(U.shardFromRift(cfg, 12, seq({1, 1})), nil, "no shard below tier 13")
eq(U.shardFromRift(cfg, 15, seq({cfg.shardChance.rift[15], 2})), "hollow", "tier 15: a random omen's shard")
eq(U.shardFromRift(cfg, 13, seq({cfg.shardChance.rift[13] + 1})), nil, "tier 13 above the chance")
check(cfg.shardChance.rift[13] < cfg.shardChance.rift[14] and cfg.shardChance.rift[14] < cfg.shardChance.rift[15],
	"higher tiers drop more shards")
local hits, trials = 0, 20000
math.randomseed(7)
for _ = 1, trials do
	if U.shardFromOmen(cfg, "bloodmoon", math.random) then
		hits = hits + 1
	end
end
check(math.abs(hits / trials * 100 - cfg.shardChance.omen) < 2, "omen shard rate near the config: " .. hits / trials)
local nb, cost = U.bindShards(cfg, 3)
eq(nb, 0, "3 shards bind nothing")
nb, cost = U.bindShards(cfg, 9)
eq(nb, 1, "one sigil per use")
eq(cost, 4, "4 shards a sigil")
local ok, take = U.relicsComplete(cfg, {"storm", "bloodmoon", "storm", "hollow"})
check(ok and #take == 3, "three different relics wake the Cinderheart")
ok, take = U.relicsComplete(cfg, {"storm", "storm", "hollow"})
check(not ok and #take == 1 and take[1] == "bloodmoon", "a missing relic is named")

-- ================================================================== scaling and lives
local sang = U.kind(cfg, "bloodmoon")
eq(U.healthMult(sang, 1), 1, "solo health x1")
check(math.abs(U.healthMult(sang, 5) - (1 + 4 * sang.healthPerExtraPlayer)) < 1e-9, "5 players")
eq(U.livesFor(sang, 1), 3, "Ascended: 3 lives solo")
eq(U.livesFor(sang, 5), 7, "+1 per extra player")
eq(U.livesFor(final, 1), 2, "the Cinderheart: 2 lives solo")
check(U.addHealthMult(cfg, 3) > U.addHealthMult(cfg, 1), "adds scale too")
local run = {lives = 2}
eq(U.loseLife(run), 1, "a life lost")
eq(U.loseLife(run), 0, "the last life")
eq(U.loseLife(run), 0, "never below 0")
eq(run.deaths, 3, "deaths counted")

-- ================================================================== the phase machine
eq(U.phaseIndex(sang, 1), 1, "full health: phase 1")
eq(U.phaseIndex(sang, 0.71), 1, "above the first threshold")
eq(U.phaseIndex(sang, 0.70), 2, "at the threshold")
eq(U.phaseIndex(sang, 0.2), 3, "low health: the last phase")
local pr = {phase = 0}
local e = U.advancePhase(pr, sang, 1)
eq(#e, 1, "the first phase is entered once")
eq(#U.advancePhase(pr, sang, 0.9), 0, "nothing new above the threshold")
e = U.advancePhase(pr, sang, 0.3)
eq(#e, 2, "a big hit through two thresholds enters both")
eq(e[1] .. "," .. e[2], "2,3", "in order")
eq(#U.advancePhase(pr, sang, 0.9), 0, "a heal never goes back")
eq(pr.phase, 3, "phase kept")
local fin = {phase = 0}
U.advancePhase(fin, final, 1)
eq(#U.advancePhase(fin, final, 0.24), 3, "the Cinderheart has four phases")

-- ================================================================== clock, telegraphs, damage
local en, te, tl = U.clock(sang, 100)
check(not en and te == sang.enrageAt - 100 and tl == sang.limit - 100, "before the enrage")
en, te, tl = U.clock(sang, sang.enrageAt)
check(en and te == 0 and tl > 0, "enraged at enrageAt")
en, te, tl = U.clock(sang, sang.limit + 5)
check(en and tl == 0, "time is up")
local tm = U.telegraphTiming(cfg, false)
eq(#tm.marks, 2, "two warning turns")
eq(tm.marks[1], 0, "marked at once")
eq(tm.hitMs, cfg.telegraph.warnMs, "the hit two turns later")
eq(tm.share, cfg.telegraph.share, "share")
local tme = U.telegraphTiming(cfg, true)
eq(#tme.marks, 1, "enraged: one warning turn")
check(tme.hitMs < tm.hitMs and tme.share > tm.share, "enraged: sooner and harder")
check(U.patternEvery(cfg, sang.phases[1], true) < U.patternEvery(cfg, sang.phases[1], false), "enraged: faster telegraphs")
eq(U.shareDamage(10000, 0.55), 5500, "share of max health")
eq(U.damageMult(cfg, false), 1, "not enraged: x1")
eq(U.damageMult(cfg, true), cfg.enrage.damageMult, "enraged multiplier")
check(math.abs(U.damageMult(cfg, false, 3) - (1 + 2 * cfg.party.damagePerExtraPlayer)) < 1e-9, "3 players hit harder")
check(math.abs(U.damageMult(cfg, true, 3) - cfg.enrage.damageMult * (1 + 2 * cfg.party.damagePerExtraPlayer)) < 1e-9,
	"enrage x party")
eq(U.addCount({base = 1, perPlayer = 1}, 4), 5, "adds: base + per player")
eq(U.addCount(nil, 4), 0, "no adds")
eq(U.harvestHeal({perAdd = 0.01}, 3, 1000000), 30000, "Harvest: 1% per add")
eq(U.harvestHeal({perAdd = 0.01}, 0, 1000000), 0, "Harvest: no adds, no heal")
local p, s, caught = U.catchDamage(1000, -500, -200)
check(p == 500 and s == 200 and not caught, "a hit that is not lethal is unchanged")
p, s, caught = U.catchDamage(1000, -900, -300)
check(caught and p + s == 999, "a lethal hit leaves 1 health")
p, s, caught = U.catchDamage(1000, -5000, 0)
check(caught and p == 999 and s == 0, "a huge hit leaves 1 health")

-- ================================================================== geometry
local L = U.layout(cfg, 1)
local side = 2 * cfg.arena.half + 1
eq(#L.floorList, side * side, "arena floor")
check(U.inArena(L, L.entry) and U.inArena(L, L.bossSpawn), "entry and boss spawn inside")
check(U.inAnte(L, L.portal) and U.inAnte(L, L.anteStart), "gate and the waiting spot in the antechamber")
check(not U.inArena(L, L.portal), "the antechamber is no arena tile")
for _, w in ipairs(L.wallList) do
	check(not U.inArena(L, w) and not U.inAnte(L, w), "walls are no floor")
end
-- no floor tile of the antechamber touches the arena floor (walls between them)
local touching = false
for _, a in ipairs(L.anteList) do
	for ox = -1, 1 do
		for oy = -1, 1 do
			if L.floor[U.key(a.x + ox, a.y + oy)] then
				touching = true
			end
		end
	end
end
check(not touching, "a wall between the arena and the antechamber")
for slot = 1, cfg.grid.slots do
	local l = U.layout(cfg, slot)
	eq(U.slotAt(cfg, l.center), slot, "slot of the centre " .. slot)
	eq(U.slotAt(cfg, l.portal), slot, "slot of the gate " .. slot)
	for _, w in ipairs(l.wallList) do
		if U.slotAt(cfg, w) ~= slot then
			check(false, "slot " .. slot .. " fits its grid cell")
			break
		end
	end
	check(l.center.x == math.floor(l.center.x), "integer coordinates")
end
check(cfg.grid.origin.x + cfg.grid.cols * cfg.grid.spacing < 8192, "clear of the rift grid")
check(cfg.grid.origin.x >= 7100, "clear of the ascension trial grid")
eq(U.slotAt(cfg, {x = 100, y = 100, z = 7}), nil, "outside the grid")
eq(U.allocSlot(cfg, {[1] = true}, {[2] = "bad"}), 3, "first free good slot")

local boss = {x = L.center.x, y = L.center.y, z = L.z}
local function ctx(extra)
	local c = {L = L, boss = boss, target = {x = boss.x, y = boss.y + 3, z = L.z}, players = {{x = boss.x + 5, y = boss.y, z = L.z}},
		rand = seq({1, 2, 3, 4, 5})}
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	return c
end
local function has(tiles, x, y)
	for _, t in ipairs(tiles) do
		if t.x == x and t.y == y then
			return true
		end
	end
	return false
end
for name in pairs(cfg.patterns) do
	local tiles = U.pattern(name, cfg, ctx())
	check(#tiles > 0, "pattern " .. name .. " marks tiles")
	check(#tiles < #L.floorList, "pattern " .. name .. " leaves a safe tile")
	for _, t in ipairs(tiles) do
		if not U.inArena(L, t) then
			check(false, "pattern " .. name .. " stays in the arena")
			break
		end
	end
end
local cone = U.pattern("cone", cfg, ctx())
check(has(cone, boss.x, boss.y + 1) and not has(cone, boss.x, boss.y - 1), "the cone points at the target (south)")
local ring = U.pattern("ring", cfg, ctx())
check(not has(ring, boss.x + 1, boss.y) and has(ring, boss.x + 4, boss.y), "the ring: safe next to the boss")
local marks = U.pattern("marks", cfg, ctx())
check(has(marks, boss.x + 5, boss.y) and not has(marks, boss.x, boss.y), "marks under the players")
local cross = U.pattern("cross", cfg, ctx())
check(has(cross, L.rect.x1, boss.y) and not has(cross, boss.x + 3, boss.y + 3), "the cross: wall to wall, not the diagonals")
local eye, info = U.pattern("eye", cfg, ctx())
check(info.safe and not has(eye, info.safe.x, info.safe.y), "the eye leaves its safe spot")
local half, hinfo = U.pattern("half", cfg, ctx({rand = seq({1})}))
eq(hinfo.side, "n", "half: side by rand")
check(has(half, boss.x, boss.y - 1) and not has(half, boss.x, boss.y + 1), "half: the north half")
local edge1 = U.hazardTiles({kind = "edge"}, ctx({depth = 1}))
local edge3 = U.hazardTiles({kind = "edge"}, ctx({depth = 3}))
eq(#edge1, side * side - (side - 2) * (side - 2), "edge depth 1: the outer ring")
check(#edge3 > #edge1 and not has(edge3, boss.x, boss.y), "the dark creeps in, the middle stays")
local pools = U.hazardTiles({kind = "pools", count = 2, perPlayer = 1, radius = 1}, ctx({playerCount = 1, rand = seq({"max"})}))
check(#pools > 0 and #pools <= 3 * 9, "pools: circles")
check(not has(pools, L.entry.x, L.entry.y + 1), "pools stay off the entry row")

-- the warning marks never spill onto a safe tile, and every marked tile is shown
for name in pairs(cfg.patterns) do
	local tiles = U.pattern(name, cfg, ctx())
	local set, plan = U.tileSet(tiles), U.markPlan(tiles)
	local shown, spill = {}, false
	for _, t in ipairs(plan.big) do
		for ox = -1, 1 do
			for oy = -1, 1 do
				if not set[U.key(t.x + ox, t.y + oy)] then
					spill = true
				end
				shown[U.key(t.x + ox, t.y + oy)] = true
			end
		end
	end
	for _, t in ipairs(plan.small) do
		shown[U.key(t.x, t.y)] = true
	end
	local all = true
	for _, t in ipairs(tiles) do
		all = all and shown[U.key(t.x, t.y)] == true
	end
	check(not spill, "marks of " .. name .. " stay on its tiles")
	check(all, "every tile of " .. name .. " is marked")
	if name == "circle" or name == "eye" then
		check(#plan.big > 0 and #plan.big + #plan.small < #tiles, name .. ": big marks save effects")
	end
end

-- ================================================================== rewards, boards, balance
local ra = U.reward(cfg, sang)
eq(ra.relic, "bloodmoon", "an Ascended kill gives its relic")
local rf = U.reward(cfg, final)
eq(rf.relic, nil, "the Cinderheart gives no relic")
check(rf.gold > ra.gold and rf.uniqueRolls >= ra.uniqueRolls, "the Cinderheart pays more")
local omenReward = omenCfg.reward
check(ra.gold > omenReward.goldPerLevel * sang.minLevel and ra.chaos > omenReward.chaos,
	"an Ascended Omen pays more than its omen (gold at the Ascended level)")
-- the party bonus (uber_config.lua party): solo the config's numbers, a party more per finisher, bounded
local pc = cfg.party
local ps1, ps5 = U.party(cfg, 1), U.party(cfg, 5)
check(ps1.damage == 1 and ps1.reward == 1 and ps1.loot == 1, "solo: no party scaling")
check(U.party({}, 5).reward == 1, "no party block: neutral")
check(math.abs(ps5.damage - (1 + 4 * pc.damagePerExtraPlayer)) < 1e-9, "5 players: damage")
check(ps5.reward >= 1.4 and ps5.reward <= 1 + pc.rewardCap / 100 + 1e-9, "5 players: +40-50% spoils")
check(math.abs(U.party(cfg, 8).reward - ps5.reward) < 1e-9, "capped at 5")
local rsolo = U.reward(cfg, sang, 1)
eq(rsolo.gold, cfg.reward.ascended.gold, "solo gold unchanged")
eq(rsolo.chaos, cfg.reward.ascended.chaos, "solo orbs unchanged")
local r5 = U.reward(cfg, sang, 5, function(a) return a end)
eq(r5.gold, math.floor(cfg.reward.ascended.gold * ps5.reward), "party gold per finisher")
eq(r5.chaos, math.ceil(cfg.reward.ascended.chaos * ps5.reward), "party orbs (the fraction rolled in)")
check(r5.gearRolls >= cfg.reward.ascended.gearRolls and r5.uniqueFind > cfg.reward.ascended.uniqueFind, "party gear rolls and find")
eq(r5.uniqueRolls, cfg.reward.ascended.uniqueRolls, "unique rolls stay")
eq(r5.relic, "bloodmoon", "the relic stays one per finisher")
eq(U.reward(cfg, sang, 5).chaos, math.floor(cfg.reward.ascended.chaos * ps5.reward), "no rand: rounded down")
eq(U.shardChance(cfg, 40, 1), 40, "solo shard chance")
eq(U.shardChance(cfg, 40, 5), math.floor(40 * ps5.reward + 0.5), "party shard chance")
eq(U.shardChance(cfg, 90, 5), 100, "a chance never passes 100")
eq(U.shardChance(cfg, 0, 5), 0, "no chance stays none")
check(U.partyNote(cfg, sang, 1) == nil, "no party note solo")
local pn = U.partyNote(cfg, sang, 5)
check(pn and pn:find("Party of 5", 1, true) and pn:find("x" .. tostring(U.healthMult(sang, 5)), 1, true), "party note: " .. tostring(pn))
for _, d in ipairs(cfg.kinds) do
	check(d.healthPerExtraPlayer >= 1.0, d.key .. ": boss health +100% or more per extra player")
end
eq(U.boardFor(cfg, 1), "cinder_solo", "solo board")
eq(U.boardFor(cfg, 2), "cinder_small", "2 players")
eq(U.boardFor(cfg, 3), "cinder_small", "3 players")
eq(U.boardFor(cfg, 5), "cinder_party", "5 players")
local lbc = dofile("data/scripts/chaos/leaderboard_config.lua")
for _, b in ipairs(cfg.boards) do
	local found
	for _, x in ipairs(lbc.boards) do
		if x.key == b.key then
			found = x
		end
	end
	check(found and found.mode == "min", "leaderboard " .. b.key .. " exists with mode min")
end
local ks = U.killStats(final, {players = 1, deaths = 0})
eq(#ks, 3, "a flawless solo Cinderheart kill: three stats")
eq(#U.killStats(final, {players = 3, deaths = 2}), 1, "a party kill with deaths: one stat")
eq(U.killStats(sang, {})[2][1], "ascended_bloodmoon", "Ascended stat per kind")
local ach = dofile("data/scripts/chaos/achievements_data.lua")
local stats = {}
for _, a in ipairs(ach.list) do
	if a.stat then
		stats[a.stat] = true
	end
end
for _, d in ipairs(cfg.kinds) do
	for _, st in ipairs(U.killStats(d, {players = 1, deaths = 0})) do
		check(stats[st[1]], "an achievement reads " .. st[1])
	end
end
eq(U.clockText(305), "5:05", "clock text")
-- the balance targets (README "Ascended Omens and the Cinderheart"): within 5%
local function near(a, b)
	return math.abs(a - b) <= b * 0.05
end
local function xmlHealth(d)
	local f = io.open("data/monster/monsters/chaos/ascended/" .. d.boss:lower():gsub(" ", "_") .. ".xml")
	local t = f:read("*a")
	f:close()
	return tonumber(t:match('<health now="%d+" max="(%d+)"'))
end
for _, d in ipairs(cfg.kinds) do
	local tg = d.final and cfg.targets.cinder or cfg.targets.ascended
	local hp = xmlHealth(d)
	local solo, party = U.killTime(cfg, d, 1, hp), U.killTime(cfg, d, 5, hp)
	check(near(solo, tg.solo), string.format("%s solo kill time %.0f s near %d", d.key, solo, tg.solo))
	check(near(party, tg.party5), string.format("%s party kill time %.0f s near %d", d.key, party, tg.party5))
	check(solo < d.enrageAt, d.key .. ": a well-geared solo player kills before the enrage")
	check(party >= solo * 0.95, d.key .. ": a full party is not faster than one (health +100% per extra player)")
end

-- the HUD (the rift HUD's fields)
local hud = U.hud({def = sang, phase = 2, phases = 3, phaseName = "Blood Pools", left = 300, limit = 780, enraged = false,
	toEnrage = 125, lives = 2, livesMax = 3, boss = "alive", state = "running", hp = 64, adds = 2, waiting = 1})
eq(hud.title, "Ascended Omen - Bloodmoon", "HUD title")
eq(hud.notes[1], "Phase 2 of 3: Blood Pools", "HUD phase line")
eq(hud.notes[2], "Health: 64%", "HUD health")
eq(hud.notes[3], "Enrage in 2:05", "HUD enrage")
eq(#hud.notes, 5, "HUD adds and the waiting player")
check(hud.omen ~= nil and hud.lives == 2, "HUD omen line and lives")

-- ================================================================== uber.lua against a mocked engine
local T = 0 -- ms
os.mtime = function() return T end
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return 1800000000 + math.floor(T / 1000) end
local queue = {}
function addEvent(fn, ms, ...)
	queue[#queue + 1] = {at = T + (ms or 0), fn = fn, args = {...}, n = select("#", ...)}
	return #queue
end
local unpack = table.unpack or unpack
local function runTo(t)
	while true do
		local best, bi
		for i, q in ipairs(queue) do
			if q.at <= t and (not best or q.at < best.at) then
				best, bi = q, i
			end
		end
		if not best then
			break
		end
		table.remove(queue, bi)
		T = math.max(T, best.at)
		best.fn(unpack(best.args, 1, best.n))
	end
	T = t
end

local effects = {}
local tiles = {}
local function tkey(p)
	return p.x .. "," .. p.y .. "," .. p.z
end
local Pos = {}
Pos.__index = Pos
function Position(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return setmetatable({x = x, y = y, z = z}, Pos)
end
function Pos:sendMagicEffect(e)
	effects[#effects + 1] = {pos = tkey(self), e = e}
end
function Pos:getDistance(o)
	return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y))
end

local creatures = {}
local nextCid = 1000
local items = {}
local known = {[32073] = "ascended shard of the bloodmoon", [32074] = "ascended shard of the hollow crown",
	[32075] = "ascended shard of the storm", [32076] = "ascended sigil", [32077] = "ascended relic", [407] = "black marble",
	[5648] = "wall", [1481] = "basin", [1387] = "forcefield", [29856] = "orb of upheaval", [29857] = "orb of fate",
	[29855] = "exalted orb"}
local stackable = {[32073] = true, [32074] = true, [32075] = true, [29856] = true, [29857] = true, [29855] = true}
function ItemType(id)
	return {getId = function() return known[id] and id or 0 end, getName = function() return known[id] or "?" end}
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	local it = setmetatable({id = id, count = count or 1, attrs = {}, custom = {}}, Item)
	items[#items + 1] = it
	return it
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:setActionId(a) self.aid = a end
function Item:getActionId() return self.aid or 0 end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:setCustomAttribute(k, v) self.custom[k] = v end
function Item:getCustomAttribute(k) return self.custom[k] end
function Item:isContainer() return false end
function Item:remove(n)
	self.removed = true
	if self.owner then
		for i, x in ipairs(self.owner.bag) do
			if x == self then
				table.remove(self.owner.bag, i)
				break
			end
		end
	end
	return true
end

local Tl = {}
Tl.__index = Tl
function Tile(p)
	return tiles[tkey(p)]
end
Game = {}
function Game.createTile(p)
	local t = setmetatable({pos = Position(p), items = {}, flags = {}}, Tl)
	tiles[tkey(p)] = t
	return t
end
function Tl:getGround() return self.ground end
function Tl:getItemById(id)
	for _, it in ipairs(self.items) do
		if it.id == id and not it.removed then
			return it
		end
	end
	if self.ground and self.ground.id == id then
		return self.ground
	end
end
function Tl:getItems()
	local out = {}
	for _, it in ipairs(self.items) do
		if not it.removed then
			out[#out + 1] = it
		end
	end
	return out
end
function Tl:getCreatures()
	local out = {}
	for _, c in pairs(creatures) do
		if tkey(c.pos) == tkey(self.pos) then
			out[#out + 1] = c
		end
	end
	return out
end
function Tl:getTopCreature() return self:getCreatures()[1] end
function Tl:hasFlag(f) return self.flags[f] end
function Tl:getHouse() return nil end
function Game.createItem(id, count, pos)
	local it = newItem(id, count)
	if pos then
		local t = tiles[tkey(pos)]
		if t then
			if id == 407 and not t.ground then
				t.ground = it
			else
				t.items[#t.items + 1] = it
			end
		end
	end
	return it
end
function Game.broadcastMessage(text) Game.lastBroadcast = text end
function Game.getGameState() return 0 end

local registered = {}
local function eventObj(name)
	return {name = name, register = function(self) registered[self.name or name] = self end, type = function() end,
		id = function(self, i) self.ids = self.ids or {}; self.ids[#self.ids + 1] = i end, aid = function(self, a) self.aidv = a end,
		separator = function() end}
end
function CreatureEvent(name) return eventObj(name) end
function GlobalEvent(name) return eventObj(name) end
local actions, moves = {}, {}
function Action()
	local a = eventObj("action")
	a.register = function(self) actions[#actions + 1] = self end
	return a
end
function MoveEvent()
	local m = eventObj("move")
	m.register = function(self) moves[#moves + 1] = self end
	return m
end
function TalkAction(w) return eventObj(w) end

local C = {}
C.__index = C
local function newCreature(o)
	nextCid = nextCid + 1
	o.id = nextCid
	o.events = {}
	o.texts = o.texts or {}
	creatures[o.id] = setmetatable(o, C)
	return o
end
function C:getId() return self.id end
function C:getName() return self.name end
function C:getPosition() return Position(self.pos) end
function C:teleportTo(p) self.pos = Position(p) end
function C:getHealth() return self.hp end
function C:getMaxHealth() return self.maxhp end
function C:setMaxHealth(v) self.maxhp = v end
function C:addHealth(a, b)
	if type(a) == "string" then
		a = b
	end
	self.hp = math.max(0, math.min(self.maxhp, self.hp + a))
end
function C:registerEvent(e) self.events[e] = true end
function C:unregisterEvent(e) self.events[e] = nil end
function C:isPlayer() return self.player == true end
function C:isMonster() return self.player ~= true end
function C:getPlayer() return self.player and self or nil end
function C:getMaster() return nil end
function C:say(t) self.said = t end
function C:getTarget() return self.target end
function C:remove() creatures[self.id] = nil end
function C:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
function C:sendCancelMessage(t) self.texts[#self.texts + 1] = "CANCEL " .. t end
function C:getStorageValue(k) return self.storage[k] or -1 end
function C:setStorageValue(k, v) self.storage[k] = v end
function C:save() end
function C:getLevel() return self.level end
function C:getGuid() return self.guid end
function C:getParty() return self.party end
function C:isPzLocked() return false end
function C:hasCondition() return false end
function C:removeCondition() end
function C:getVocation() return {getId = function() return 4 end} end
function C:getTown() return {getTemplePosition = function() return Position(1000, 1000, 7) end} end
function C:getMana() return 0 end
function C:getMaxMana() return 0 end
function C:addMana() end
function C:getBankBalance() return self.bank or 0 end
function C:setBankBalance(v) self.bank = v end
function C:getInbox() return {addItemEx = function() end, addItem = function() end} end
function C:getEnergyShield() return 0 end
function C:getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
function C:getSlotItem() return nil end
function C:getItemCount(id)
	local c = 0
	for _, it in ipairs(self.bag) do
		if it.id == id then
			c = c + it.count
		end
	end
	return c
end
function C:addItem(id, count)
	count = count or 1
	for _, it in ipairs(self.bag) do
		if it.id == id and stackable[id] then
			it.count = it.count + count
			return it
		end
	end
	local it = newItem(id, count)
	it.owner = self
	self.bag[#self.bag + 1] = it
	return it
end
function C:addItemEx(it)
	it.owner = self
	self.bag[#self.bag + 1] = it
	return RETURNVALUE_NOERROR
end
function C:removeItem(id, count)
	for i, it in ipairs(self.bag) do
		if it.id == id then
			if it.count < count then
				return false
			end
			it.count = it.count - count
			if it.count == 0 then
				table.remove(self.bag, i)
			end
			return true
		end
	end
	return false
end
function Player(x)
	if type(x) == "string" then
		for _, c in pairs(creatures) do
			if c.player and c.name == x then
				return c
			end
		end
		return nil
	end
	local c = type(x) == "table" and x or creatures[x]
	return c and c.player and c or nil
end
function Monster(id)
	local c = creatures[id]
	return c and not c.player and c or nil
end
function Creature(id) return creatures[id] end
local monsterHp = {["Ascended Sangrith"] = 1200000, ["Bloodmoon Thrall"] = 60000, ["Ysgrath the Cinderheart"] = 1650000}
function Game.createMonster(name, pos)
	if not monsterHp[name] then
		return nil
	end
	local m = newCreature({name = name, pos = Position(pos), hp = monsterHp[name], maxhp = monsterHp[name]})
	return m
end
function MonsterType(name) return {getLoot = function() return {} end} end

-- a hit like the engine's doTargetCombat: the target's healthchange events, then the damage
function doTargetCombat(attackerId, target, ctype, min, max, effect, origin)
	local dmg = min
	local pd, pt, sd, st = dmg, ctype, 0, COMBAT_NONE
	if target.events.ChaosAscendedPlayerHit then
		pd, pt, sd, st = registered.ChaosAscendedPlayerHit.onHealthChange(target, creatures[attackerId], pd, pt, sd, st, origin)
	end
	target.hp = math.max(0, target.hp + pd + sd)
	target.lastHit = -(pd + sd)
end

Chaos.send = function(p, opcode, action, data)
	p.sent = p.sent or {}
	p.sent[#p.sent + 1] = {action = action, data = data}
end
Chaos.isMultiClient = function() return false end
Chaos.giveItem = function(player, id, count)
	player:addItem(id, count)
	return count
end
db = {query = function() end}
ChaosAchievements = {got = {}, progress = function(p, k, a) ChaosAchievements.got[p.name .. ":" .. k] = a end}
ChaosLeaderboard = {rec = {}, record = function(b, who, v) ChaosLeaderboard.rec[#ChaosLeaderboard.rec + 1] = {b, who.name, v} end}

dofile("data/scripts/chaos/uber.lua")
local A = ChaosAscended
check(#actions == 3, "sigil, relic and shard actions registered: " .. #actions)
check(#moves == 1 and moves[1].aidv == cfg.portalActionId, "the Ember Gate move event")
local sigilUse, relicUse, shardUse
for _, a in ipairs(actions) do
	if a.ids[1] == cfg.items.sigil.id then
		sigilUse = a
	elseif a.ids[1] == cfg.items.relic.id then
		relicUse = a
	else
		shardUse = a
	end
end
eq(#shardUse.ids, 3, "the three shard ids")

local town = Game.createTile({x = 100, y = 100, z = 7})
town.flags[TILESTATE_PROTECTIONZONE] = true
Game.createTile({x = 101, y = 100, z = 7}).flags[TILESTATE_PROTECTIONZONE] = true
local function newPlayer(name, guid, level, x)
	return newCreature({player = true, name = name, guid = guid, level = level, pos = Position(x or 100, 100, 7), hp = 10000,
		maxhp = 10000, storage = {}, bag = {}})
end
local hero = newPlayer("Hero", 11, 1000)
local friend = newPlayer("Friend", 12, 1000, 101)
local party = {getLeader = function() return hero end, getMembers = function() return {friend} end}
hero.party, friend.party = party, party

-- shards -> sigil
hero:addItem(32073, 3)
local shard = hero.bag[1]
shardUse.onUse(hero, shard)
check(hero.texts[#hero.texts]:find("need 4", 1, true) ~= nil, "3 shards: not enough")
hero:addItem(32073, 2)
shardUse.onUse(hero, shard)
eq(hero:getItemCount(32073), 1, "4 shards taken")
local sigil
for _, it in ipairs(hero.bag) do
	if it.id == cfg.items.sigil.id then
		sigil = it
	end
end
check(sigil and sigil.custom.ascended_kind == "bloodmoon", "a Bloodmoon sigil")
eq(sigil.attrs[ITEM_ATTRIBUTE_NAME], "Ascended Sigil of the Bloodmoon", "sigil named")

-- the rift hook: an omen kill and a tier 15 rift
math.randomseed(3)
local before = hero:getItemCount(32074)
for _ = 1, 50 do
	A.onRiftSealed({tier = 15, omen = "hollow", finishers = {[11] = {name = "Hero"}}})
end
local got = hero:getItemCount(32074) - before
check(got > 5 and got < 40, "omen kills give shards of that omen at about the chance: " .. got)
A.onRiftSealed({tier = 9, finishers = {[11] = {name = "Hero"}}})

-- the sigil opens the arena for the party
hero.pos = Position(200, 200, 7) -- out of the protection zone
sigilUse.onUse(hero, sigil)
check(hero.texts[#hero.texts]:find("protection zone", 1, true) ~= nil, "a sigil needs a protection zone")
hero.pos = Position(100, 100, 7)
hero.storage[Chaos.storage.ascendedRun + 2] = nil
T = T + 5000
sigilUse.onUse(hero, sigil)
local run = A.runOf[hero.id]
check(run ~= nil and A.runOf[friend.id] == run, "both in the run")
check(sigil.removed, "the sigil is spent")
eq(hero.storage[Chaos.storage.ascendedRun], 1, "the crash marker holds the kind")
eq(run.lives, 4, "3 lives + 1 for the friend")
check(U.inArena(run.L, hero.pos) and U.inArena(run.L, friend.pos), "teleported into the arena")
check(Tile(run.L.portal):getItemById(cfg.portalId).aid == cfg.portalActionId, "the Ember Gate is placed")
eq(hero.sent[#hero.sent].action, "start", "the rift HUD starts")

-- the boss comes after startDelay
runTo(T + cfg.startDelay * 1000 + 500)
local b = run.bossId and Monster(run.bossId)
check(b ~= nil and run.boss == "alive", "the boss answers")
eq(b.maxhp, math.floor(1200000 * U.healthMult(sang, 2)), "boss health x the party size")
eq(run.phase, 1, "phase 1")
check(hero.sent[#hero.sent].data.notes[1]:find("Phase 1 of 3", 1, true) ~= nil, "HUD phase note")

-- a telegraph: the hero stands in it, the friend steps out of the cone
b.target = hero
hero.pos = Position(b.pos.x, b.pos.y + 2, b.pos.z)
friend.pos = Position(b.pos.x, b.pos.y - 3, b.pos.z)
math.randomseed(1)
run.nextPattern = T
local function patternIs(name)
	local saved = math.random
	math.random = function(a, c)
		if a == 1 and c == #sang.phases[1].patterns then
			for i, p in ipairs(sang.phases[1].patterns) do
				if p == name then
					return i
				end
			end
		end
		return saved(a, c)
	end
	return function() math.random = saved end
end
local restore = patternIs("cone")
runTo(T + 300)
restore()
local hpBefore, fBefore = hero.hp, friend.hp
runTo(T + cfg.telegraph.warnMs + 100)
eq(hpBefore - hero.hp, U.shareDamage(hero.maxhp, cfg.telegraph.share), "the hero in the cone takes the share")
eq(friend.hp, fBefore, "the friend behind the boss is safe")
local warned = 0
for _, e in ipairs(effects) do
	if e.e == CONST_ME_MAGIC_RED then
		warned = warned + 1
	end
end
check(warned > 0, "the tiles were marked before the hit")

-- a lethal hit is caught: the antechamber, one life less, the gate after reenterSeconds
hero.hp = 100
doTargetCombat(b.id, hero, COMBAT_PHYSICALDAMAGE, -5000, -5000)
eq(hero.hp, 1, "the lethal hit leaves 1 health")
runTo(T + 10)
check(run.players[hero.id].down and U.inAnte(run.L, hero.pos), "fallen: in the antechamber")
eq(run.lives, 3, "a life lost")
eq(hero.hp, hero.maxhp, "healed in the antechamber")
local hpGate = hero.hp
doTargetCombat(b.id, hero, COMBAT_PHYSICALDAMAGE, -500, -500)
eq(hero.hp, hpGate, "no damage while down")
A.gate(hero)
check(U.inAnte(run.L, hero.pos), "the gate is shut at first")
runTo(T + cfg.lives.reenterSeconds * 1000 + 100)
A.gate(hero)
check(U.inArena(run.L, hero.pos) and not run.players[hero.id].down, "back through the gate")
doTargetCombat(b.id, hero, COMBAT_PHYSICALDAMAGE, -500, -500)
eq(hero.hp, hpGate, "shielded right after the gate")

-- phases: 70% -> Blood Pools (adds and pools), a big hit to 30% enters both
b.hp = math.floor(b.maxhp * 0.69)
runTo(T + 300)
eq(run.phase, 2, "phase 2 at 70%")
local adds = 0
for _ in pairs(run.adds) do
	adds = adds + 1
end
eq(adds, U.addCount(sang.phases[2].adds, 2), "phase 2 adds")
check(run.hazard and #run.hazard.tiles > 0, "blood pools")
eq(b.said, sang.phases[2].yell, "the phase yell")
b.hp = math.floor(b.maxhp * 0.30)
runTo(T + 300)
eq(run.phase, 3, "phase 3")
-- Harvest: the boss heals per living add
local hb = b.hp
runTo(T + 5300)
check(b.hp > hb or b.hp == b.maxhp, "the Harvest heals the boss while the adds live")

-- the enrage: harder monster hits
run.bossAt = T - sang.enrageAt * 1000 - 10
runTo(T + 300)
check(run.enraged, "enraged")
hero.hp = hero.maxhp
run.players[hero.id].shieldUntil = 0
local addId = next(run.adds)
doTargetCombat(addId, hero, COMBAT_PHYSICALDAMAGE, -1000, -1000)
eq(hero.lastHit, math.abs(math.floor(-1000 * U.damageMult(cfg, true, 2))), "enraged adds hit harder (x the party of 2)")
hero.hp = hero.maxhp

-- the kill: spoils, relic, achievements, the end
local bank = hero:getBankBalance()
registered.ChaosAscendedBossDeath.onDeath(b)
b:remove()
runTo(T + 10)
eq(run.state, "success", "the boss is slain")
-- the hero and the friend entered: the party bonus of 2
local pm2 = U.party(cfg, 2).reward
eq(hero:getBankBalance() - bank, math.floor(cfg.reward.ascended.gold * pm2), "gold to the bank (x the party of 2)")
local orbs2 = hero:getItemCount(29856)
check(orbs2 == math.floor(cfg.reward.ascended.chaos * pm2) or orbs2 == math.ceil(cfg.reward.ascended.chaos * pm2),
	"orbs (x the party of 2): " .. orbs2)
local relic
for _, it in ipairs(hero.bag) do
	if it.id == cfg.items.relic.id then
		relic = it
	end
end
check(relic and relic.custom.ascended_kind == "bloodmoon", "the Bloodmoon relic")
eq(ChaosAchievements.got["Hero:ascended_bloodmoon"], 1, "achievement stat")
eq(#ChaosLeaderboard.rec, 0, "Ascended kills are not on the Cinderheart boards")
eq(hero.storage[Chaos.storage.ascendedRun], 0, "the marker is cleared")
runTo(T + cfg.exitDelay * 1000 + 100)
check(A.runs[run.slot] == nil and not A.runOf[hero.id], "the run is over after the exit delay")
eq(hero.pos.x, 100, "back where the hero came from")
check(next(run.adds) == nil or Monster(next(run.adds)) == nil, "the adds are gone")

-- relics -> the Cinderheart Sigil (the mock's backpack slot returns the flat bag)
hero.getSlotItem = function(self, slot)
	if slot == CONST_SLOT_BACKPACK then
		return {getId = function() return 1988 end, isContainer = function() return true end,
			getItems = function() return self.bag end}
	end
end
relicUse.onUse(hero, relic)
check(hero.texts[#hero.texts]:find("Missing: Hollow Crown, Storm", 1, true) ~= nil, "two relics missing")
A.giveRelic(hero, "hollow")
A.giveRelic(hero, "storm")
relicUse.onUse(hero, relic)
local cind
local relics = 0
for _, it in ipairs(hero.bag) do
	if it.id == cfg.items.sigil.id and it.custom.ascended_kind == "cinder" then
		cind = it
	end
	if it.id == cfg.items.relic.id then
		relics = relics + 1
	end
end
check(cind ~= nil, "three relics bind a Cinderheart Sigil")
eq(relics, 0, "the relics are taken")

-- the Cinderheart, solo: the last life ends the run and the sigil is spent
hero.party, friend.party = nil, nil
hero.pos = Position(100, 100, 7)
T = T + 5000
sigilUse.onUse(hero, cind)
local r2 = A.runOf[hero.id]
check(r2 and r2.def.final and r2.size == 1, "the Cinderheart run, solo")
eq(r2.lives, 2, "two lives")
runTo(T + cfg.startDelay * 1000 + 500)
local cb = Monster(r2.bossId)
check(cb ~= nil and cb.maxhp == 1650000, "the Cinderheart answers, solo health")
hero.hp = 10
doTargetCombat(cb.id, hero, COMBAT_FIREDAMAGE, -999, -999)
runTo(T + 10)
eq(r2.lives, 1, "one life left")
runTo(T + cfg.lives.reenterSeconds * 1000 + 100)
A.gate(hero)
hero.hp = 10
run = r2
run.players[hero.id].shieldUntil = 0
doTargetCombat(cb.id, hero, COMBAT_FIREDAMAGE, -999, -999)
runTo(T + 10)
eq(r2.state, "failed", "the last life ends the run")
check(A.runs[r2.slot] == nil, "the arena is free again")
eq(hero.storage[Chaos.storage.ascendedRun], 0, "no refund for a lost run")

-- a crash: the marker gives the sigil back at the next login
hero.storage[Chaos.storage.ascendedRun] = 2
local sigils = 0
registered.ChaosAscendedLogin.onLogin(hero)
for _, it in ipairs(hero.bag) do
	if it.id == cfg.items.sigil.id and it.custom.ascended_kind == "hollow" and not it.removed then
		sigils = sigils + 1
	end
end
eq(sigils, 1, "the sigil comes back after a crash")
eq(hero.storage[Chaos.storage.ascendedRun], 0, "once")
registered.ChaosAscendedLogin.onLogin(hero)

-- the Cinderheart kill goes on the board of its party size
local k = Player("Hero")
hero.pos = Position(100, 100, 7)
T = T + 5000
local cs
for _, it in ipairs(hero.bag) do
	if it.id == cfg.items.sigil.id and it.custom.ascended_kind == "hollow" then
		cs = it
	end
end
A.giveSigil(hero, "cinder")
for _, it in ipairs(hero.bag) do
	if it.id == cfg.items.sigil.id and it.custom.ascended_kind == "cinder" and not it.removed then
		cs = it
	end
end
sigilUse.onUse(k, cs)
local r3 = A.runOf[hero.id]
runTo(T + cfg.startDelay * 1000 + 500)
runTo(T + 60000)
local cb3 = Monster(r3.bossId)
registered.ChaosAscendedBossDeath.onDeath(cb3)
cb3:remove()
runTo(T + 10)
eq(r3.state, "success", "the Cinderheart falls")
local rec = ChaosLeaderboard.rec[#ChaosLeaderboard.rec]
check(rec and rec[1] == "cinder_solo" and rec[2] == "Hero" and rec[3] >= 59 and rec[3] <= 61, "the solo board gets the time")
eq(ChaosAchievements.got["Hero:cinder_solo"], 1, "the solo achievement stat")
check(Game.lastBroadcast and Game.lastBroadcast:find("extinguished the Cinderheart", 1, true) ~= nil, "the broadcast")

-- ================================================================== instance limits (instance_limits.lua)
-- warnings before the boss's limit, the cap with the wait and the waiting line, the staff list and close (the sigil is
-- spent, as when the time runs out)
do
	dofile("data/scripts/chaos/instance_limits.lua")
	A.interruptAll()
	local function told(p, text)
		for _, t in ipairs(p.texts) do
			if t:find(text, 1, true) then
				return true
			end
		end
		return false
	end
	hero.party, friend.party = nil, nil
	hero.pos, friend.pos = Position(100, 100, 7), Position(101, 100, 7)
	hero.hp, friend.hp = hero.maxhp, friend.maxhp
	local function sigilFor(p)
		local it = p:addItem(cfg.items.sigil.id, 1)
		it.custom.ascended_kind = "bloodmoon"
		return it
	end
	T = T + 5000
	sigilUse.onUse(hero, sigilFor(hero))
	local r = A.runOf[hero.id]
	check(r ~= nil, "limits: a run")
	runTo(T + cfg.startDelay * 1000 + 500)
	check(r.bossAt ~= nil, "limits: the boss is up")
	r.bossAt = T - (r.def.limit - 300) * 1000
	runTo(T + 300)
	check(told(hero, r.def.boss .. ": 5 minutes left"), "limits: the 5 minute warning")
	-- the cap
	ChaosUberConfig.limits.maxRuns = 1
	T = T + 5000
	friend.texts = {}
	sigilUse.onUse(friend, sigilFor(friend))
	check(A.runOf[friend.id] == nil, "limits: the cap refuses a second arena")
	check(told(friend, "All Ascended arenas are busy. Try again in ~5 min. You are 1st in line"), "limits: busy text")
	ChaosUberConfig.limits.maxRuns = 4
	local found
	for _, x in ipairs(ChaosInstanceLimits.runs()) do
		if x.key == "ascended" then found = x end
	end
	check(found and found.id == r.id and found.players == 1 and found.left <= 300 and found.left >= 290, "limits: listed: " ..
		tostring(found and (found.id .. " " .. found.players .. " " .. tostring(found.left))))
	-- staff close
	local okC = Chaos.instances.ascended.close(r.id)
	check(okC and r.state == "failed" and A.runs[r.slot] == nil, "limits: a staff close fails the run")
	eq(hero.storage[Chaos.storage.ascendedRun], 0, "limits: the sigil is spent (no refund marker)")
	check(told(friend, "A place in the Ascended arenas is free now"), "limits: the first in line is told")
end

print(string.format("uber_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

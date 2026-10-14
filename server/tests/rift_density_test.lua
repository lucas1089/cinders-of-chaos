-- Run from the server/ folder: luajit tests/rift_density_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- rift.lua against a mocked engine: the dense rift (server/README.md "Rifts", Density) and the third set of modifiers.
-- The first packs up to the live cap, the queue, the budget health, husks (no loot, no kill credit), reinforcements in
-- the room away from the players, the guardian at the threshold of the whole plan, Veilbreach extras, the ground and
-- the storm, the Wrathful Guardian, Parched Veins and a brand on a monster's hit.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ------------------------------------------------------------------ engine mocks
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
GAME_STATE_NORMAL = 1
db = {query = function() return true end, storeQuery = function() return false end, escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
local function pos(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = pos
local timers = {}
addEvent = function(f, ms, ...)
	timers[#timers + 1] = {f = f, args = {...}}
	return #timers
end
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t.f((table.unpack or unpack)(t.args))
	end
end
local hits = {}
doTargetCombatHealth = function(attacker, target, ctype, a, b, eff)
	hits[#hits + 1] = {target = target, type = ctype, amount = a}
end
local conditions = {}
Condition = function(kind)
	local c = {kind = kind, params = {}, damage = nil}
	function c:setParameter(k, v) self.params[k] = v end
	function c:setTicks(v) self.ticks = v end
	function c:setFormula(...) self.formula = {...} end
	function c:addDamage(r, i, v) self.damage = {r, i, v} end
	return c
end
local monsters, nextMid = {}, 5000
local function newMonster(name, p)
	nextMid = nextMid + 1
	local m = {id = nextMid, name = name, max = 10000, hp = 10000, at = pos(p.x, p.y, p.z), drop = true, events = {}}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:getMaxHealth() return self.max end
	function m:setMaxHealth(v) self.max = v end
	function m:setHealth(v) self.hp = v end
	function m:getHealth() return self.hp end
	function m:setOutfit() end
	function m:changeSpeed() end
	function m:registerEvent(e) self.events[e] = true end
	function m:setDropLoot(v) self.drop = v end
	function m:getPosition() return self.at end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return nil end
	monsters[m.id] = m
	return m
end
Game = {
	getGameState = function() return 1 end,
	createItem = function() return nil end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
	createMonster = function(name, p) return newMonster(name, p) end,
}
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
local players = {}
Player = function(id)
	if type(id) == "table" then return id end
	return players[id]
end
Monster = function(id) return monsters[id] end
json = {encode = function() return "{}" end, decode = function() return {} end}
Tile = function() return nil end

dofile("data/scripts/chaos/rift.lua")
local RF, R = ChaosRift, ChaosRiftCore
local cfg = ChaosRiftConfig
-- a tier 1 monster (monster_tiers.lua) doubles the health of a magic one in this mock
ChaosApplyTier = function(m, tier)
	local mult = ({magic = 2, rare = 3.5, legendary = 6})[tier] or 1
	m.max = math.floor(m.max * mult)
	m.tier = tier
end

local nextPid = 0
local function newPlayer(name, at)
	nextPid = nextPid + 1
	local p = {id = 100 + nextPid, guid = nextPid, name = name, at = at, maxHp = 15000, msgs = {}}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getPosition = function() return p.at end
	p.getMaxHealth = function() return p.maxHp end
	p.sendTextMessage = function(_, _, t) p.msgs[#p.msgs + 1] = t end
	p.sendExtendedOpcode = function() end
	p.addCondition = function(_, c) conditions[#conditions + 1] = {who = p, c = c} end
	p.isPlayer = function() return true end
	p.getMaster = function() return nil end
	players[p.id] = p
	return p
end

-- one generated layout (rift_layout_core.lua) of slot 3, band 2, as the slot pool builds it (the tiles are not built)
local RL = ChaosRiftLayout
local layoutL = RL.generate(cfg, dofile("data/scripts/chaos/areagen_config.lua"),
	{theme = "Abyssal Rift", band = 2, seed = 4242, origin = RF.slotOrigin(3)}, {})
layoutL.tiles = nil

-- a dense run as RF.open builds it (no slot build): tier 8, solo, three kinds
local function newRun(mods, players1)
	local tier = 8
	local fx = R.applyParty(cfg, R.effects(cfg, mods or {}, tier), 1, tier)
	local types = {{name = "Low", level = 700}, {name = "Mid", level = 720}, {name = "High", level = 760}}
	local seed = 12345
	local function rnd(a, b)
		seed = (seed * 16807) % 2147483647
		return a + seed % (b - a + 1)
	end
	local L = layoutL
	local rooms = RL.sectionOrder(L, rnd)
	local first = table.remove(rooms, 1)
	local plan = R.plan(cfg, tier, fx, 1, types, rooms, rnd, {first = first, area = L.walkable})
	local run = R.newRun(cfg, os.time(), plan.total, plan.bossAt, fx, R.timeLimit(cfg, tier))
	run.id, run.slot, run.L, run.key, run.fx, run.plan = 1, 3, L, {tier = tier, mods = mods or {}}, fx, plan
	run.bonus, run.players, run.size, run.themeName, run.rooms = {quantity = 0, rarity = 0, experience = 0}, {}, 1, "Abyssal Rift", rooms
	run.lives, run.livesMax, run.deaths, run.revive = 3, 3, 0, {}
	run.typeNames = {"Low", "Mid", "High"}
	run.density = plan.density
	run.density.packHealth = R.packHealth(cfg, tier, L.walkable)
	run.healthRatio = {low = 0.8, mid = 1.0, high = 1.2}
	run.alive, run.aliveIds, run.extra, run.visited = 0, {}, {}, {}
	RF.runs[3] = run
	for _, p in ipairs(players1 or {}) do
		run.players[p.id] = {id = p.id, guid = p.guid, name = p.name, entry = pos(1, 1, 7), xp = {base = 0}}
		RF.runOf[p.id] = run
	end
	return run
end

local death = events.ChaosRiftMonsterDeath.onDeath
local function kill(m)
	death(m, nil, nil, nil)
	monsters[m.id] = nil
end

-- 1. the first packs up to the live cap, the queue, the budget health, husks
do
	local hero = newPlayer("Hero", pos(0, 0, 7))
	local run = newRun({}, {})
	hero.at = pos(run.L.start.x, run.L.start.y, 7)
	run.players[hero.id] = {id = hero.id, guid = hero.guid, name = hero.name, entry = pos(1, 1, 7), xp = {base = 0}}
	RF.runOf[hero.id] = run
	ok(run.density.live > 100, "the live cap grows with the layout: " .. run.density.live)
	ok(run.plan.total > 2 * run.density.live * 0.8, "the plan of the big layout: " .. run.plan.total)
	-- the populate steps: the first step now, the rest by timer (perStep monsters a step)
	local first = RF._spawnPacks(run)
	ok(first <= cfg.density.populate.perStep + cfg.density.size[2] + 1, "first populate step: " .. first)
	ok(#run.populate > 0, "the rest of the first packs come in steps")
	local guard = 0
	while #run.populate > 0 and guard < 100 do
		guard = guard + 1
		local list = timers
		timers = {}
		for _, t in ipairs(list) do
			t.f((table.unpack or unpack)(t.args))
		end
	end
	local spawned = run.alive
	-- every monster on a walkable cell of the layout, none in the arrival's safe radius
	local onFloor, inSafe, sectionsUsed = 0, 0, {}
	for id, m in pairs(monsters) do
		if RF.monsterRun[id] == run then
			if RL.isFloor(run.L, m.at.x, m.at.y, m.at.z) then
				onFloor = onFloor + 1
			end
			if m.at.z == run.L.start.z and math.max(math.abs(m.at.x - run.L.start.x), math.abs(m.at.y - run.L.start.y)) < cfg.layout.safeRadius - cfg.density.spread then
				inSafe = inSafe + 1
			end
			sectionsUsed[math.floor((m.at.x - run.L.origin.x) / 40) .. ":" .. math.floor((m.at.y - run.L.origin.y) / 40)] = true
		end
	end
	eq(onFloor, spawned, "every monster on a walkable cell")
	eq(inSafe, 0, "none near the arrival")
	local quarters = 0
	for _ in pairs(sectionsUsed) do
		quarters = quarters + 1
	end
	ok(quarters >= 15, "the first packs spread over the map: " .. quarters .. " of 25 squares")
	run.total = run.plan.total - (run.planMissing or 0)
	run.bossAt = math.ceil(run.total * cfg.bossAt / 100)
	ok(spawned <= run.density.live and spawned >= run.density.live - cfg.density.size[2] - 1, "first packs fill the live cap: " .. spawned)
	eq(run.alive, spawned, "alive counted")
	ok(#run.queue > 5, "the rest waits in the queue: " .. #run.queue)
	local queued = 0
	for _, p in ipairs(run.queue) do
		queued = queued + p.count
	end
	eq(spawned + queued, run.plan.total, "nothing lost between the first packs and the queue")
	local husks, laden, checked = 0, 0, false
	for id, m in pairs(monsters) do
		if RF.monsterRun[id] == run then
			if RF.isHusk(m) then
				husks = husks + 1
				eq(m.drop, false, "a husk drops no loot")
			else
				laden = laden + 1
				eq(m.drop, true, "a laden monster drops loot")
			end
			if not m.tier and not checked then
				checked = true
				local ratio = run.healthRatio[m.name:lower()]
				eq(m.max, math.floor(run.density.packHealth * ratio * run.fx.health), "a normal monster has the budget health x its kind")
			end
		end
	end
	ok(husks > laden, "most monsters are husks: " .. husks .. " / " .. laden)
	ok(checked, "a normal monster was checked")
	-- reinforcements: none while every pack fits nowhere; after kills they come in the room away from the hero
	local before = run.alive
	RF._reinforce(run)
	eq(run.alive, before, "no room: no reinforcement")
	local killed = 0
	for id, m in pairs(monsters) do
		if RF.monsterRun[id] == run and killed < 20 then
			kill(m)
			killed = killed + 1
		end
	end
	eq(run.alive, before - 20, "kills free the cap")
	eq(run.killed, 20, "kills counted")
	-- the husk flag stays through the death (bounty / bestiary ask then) and goes a moment later
	runTimers()
	local leftHusk = 0
	for id in pairs(RF.husk) do
		if not monsters[id] then
			leftHusk = leftHusk + 1
		end
	end
	eq(leftHusk, 0, "husk flags of the dead are gone")
	-- a husk drops no loot, and the engine then runs no death event for it: its kill comes from the killer's kill
	-- event (once, even when a death event follows), and a husk that vanished is counted by the tick's sweep
	local husk1, husk2
	for id, m in pairs(monsters) do
		if RF.monsterRun[id] == run and RF.isHusk(m) then
			if not husk1 then
				husk1 = m
			elseif not husk2 then
				husk2 = m
			end
		end
	end
	local k0, a0 = run.killed, run.alive
	events.ChaosRiftPlayerKill.onKill(hero, husk1)
	eq(run.killed, k0 + 1, "a husk's kill event counts it")
	eq(run.alive, a0 - 1, "and frees its place")
	death(husk1, nil, nil, nil)
	monsters[husk1.id] = nil
	eq(run.killed, k0 + 1, "a death event after it does not count it twice")
	monsters[husk2.id] = nil -- gone without any event
	hero.getTown = function() return {getTemplePosition = function() return pos(1, 1, 7) end} end
	RF._tick(3, run.id)
	eq(run.killed, k0 + 2, "the tick's sweep counts a monster that vanished")
	timers = {}
	local q0 = #run.queue
	local seen = {}
	local newIds = {}
	for id in pairs(monsters) do
		seen[id] = true
	end
	RF._reinforce(run)
	ok(#run.queue < q0 and #run.queue >= q0 - cfg.density.reinforce.perTick, "reinforce: up to perTick packs")
	for id, m in pairs(monsters) do
		if not seen[id] then
			newIds[#newIds + 1] = id
			local d = math.max(math.abs(m.at.x - hero.at.x), math.abs(m.at.y - hero.at.y))
			ok(d >= cfg.density.reinforce.minDistance - 4, "reinforcement away from the hero: " .. d)
		end
	end
	ok(#newIds > 0, "reinforcements came")
	-- every section reached (visited): nothing comes
	local saved = run.visited
	local all = {}
	for _, sec in ipairs(run.L.sections) do
		all[sec.name] = true
	end
	run.visited = all
	for i = 1, 30 do -- make room
		for id, m in pairs(monsters) do
			if RF.monsterRun[id] == run then
				kill(m)
				break
			end
		end
	end
	local q1 = #run.queue
	-- RL.visit marks only sections near the players: the hero stands at the arrival
	RF._reinforce(run)
	eq(#run.queue, q1, "every section reached: the queue waits")
	run.visited = saved
	-- the guardian at the threshold of the whole plan
	local spawnedBoss = false
	for _ = 1, 400 do
		if run.boss ~= "waiting" then
			break
		end
		local any = false
		for id, m in pairs(monsters) do
			if RF.monsterRun[id] == run and not (run.bossIds and run.bossIds[id]) then
				kill(m)
				any = true
				break
			end
		end
		if not any then
			run.visited = {}
			RF._reinforce(run)
		end
	end
	eq(run.boss, "alive", "the guardian came")
	eq(run.killed, run.bossAt, "at the threshold of the whole plan (" .. run.bossAt .. " of " .. run.total .. ")")
	ok(run.bossAt > run.density.live, "more kills than the live cap before the guardian")
	local bossId = next(run.bossIds)
	local g = monsters[bossId]
	eq(g.max, math.floor(R.guardianBase(cfg, 8) * R.guardianHealthMult(cfg, run.fx, 1)), "the guardian's budget health")
	local q2 = #run.queue
	run.alive = 0
	RF._reinforce(run)
	eq(#run.queue, q2, "no reinforcement after the guardian came")
	RF.runs[3] = nil
end

-- 2. Veilbreach: two extra monsters that do not count towards the guardian
do
	monsters = {}
	local hero = newPlayer("Breacher", pos(0, 0, 7))
	local run = newRun({{key = "breach", value = 25}}, {hero})
	run.fx.breach = 100
	RF._spawnPacks(run, true)
	run.total = run.plan.total
	run.bossAt = math.ceil(run.total * cfg.bossAt / 100)
	local victim
	for id, m in pairs(monsters) do
		if RF.monsterRun[id] == run then
			victim = m
			break
		end
	end
	local alive0 = run.alive
	kill(victim)
	eq(run.killed, 1, "the breaching kill counts")
	runTimers()
	eq(run.alive, alive0 - 1 + cfg.breach.count, "two came through the breach")
	local extras = {}
	for id in pairs(run.extra) do
		extras[#extras + 1] = monsters[id]
	end
	eq(#extras, cfg.breach.count, "flagged as extra")
	run.fx.breach = 100
	local alive1 = run.alive
	kill(extras[1])
	eq(run.killed, 1, "an extra kill does not count towards the guardian")
	runTimers()
	eq(run.alive, alive1 - 1, "an extra never opens a breach")
	RF.runs[3] = nil
end

-- 3. ground and storm: patches near the players hurt who stands in them; the storm is marked first
do
	monsters, hits, conditions = {}, {}, {}
	local hero = newPlayer("Walker", pos(0, 0, 7))
	local run = newRun({{key = "rimefloor", value = 4}, {key = "veilstorm", value = 20}}, {hero})
	hero.at = pos(run.L.start.x, run.L.start.y, 7)
	RF._groundTick(run, 1000)
	local n0 = 0
	for _ in pairs(run.hazards) do
		n0 = n0 + 1
	end
	ok(n0 >= 3 and n0 <= 5, "a patch of up to five tiles: " .. n0)
	-- stand on one
	local k, h = next(run.hazards)
	hero.at = pos(h.x, h.y, 7)
	hits, conditions = {}, {}
	RF._groundTick(run, 1001)
	eq(#hits, 1, "standing in it hurts")
	eq(hits[1] and hits[1].amount, -R.percentHit(15000, 0.04), "4% of max health")
	eq(hits[1] and hits[1].type, COMBAT_ICEDAMAGE, "ice")
	ok(#conditions == 1 and conditions[1].c.kind == CONDITION_PARALYZE, "rimefloor slows: " .. #conditions .. " " .. tostring(conditions[1] and conditions[1].c.kind) .. " " .. tostring(CONDITION_PARALYZE))
	-- the patch is gone after its time
	hits = {}
	RF._groundTick(run, 1001 + cfg.ground.lastSeconds + cfg.ground.every)
	local stale = 0
	for _, hz in pairs(run.hazards) do
		if hz.untilAt <= 1001 + cfg.ground.lastSeconds then
			stale = stale + 1
		end
	end
	eq(stale, 0, "old patches expire")
	-- the storm: a mark now, the hit warnMs later only within its radius
	hits, timers = {}, {}
	RF._stormTick(run, 2000)
	eq(#hits, 0, "the mark first")
	eq(#timers, 1, "one strike per player")
	hero.at = pos(hero.at.x + 10, hero.at.y, 7) -- stepped away
	runTimers()
	eq(#hits, 0, "dodged")
	RF._stormTick(run, 2001)
	eq(#timers, 0, "not again before `every`")
	RF._stormTick(run, 2000 + cfg.veilstorm.every)
	local strikeAt
	hero.at = pos(hero.at.x, hero.at.y, 7)
	runTimers()
	ok(#hits <= 1, "at most one hit per strike")
	RF.runs[3] = nil
end

-- 4. Wrathful Guardian: a nova around the guardian and thralls (husks, extra)
do
	monsters, hits, timers = {}, {}, {}
	local hero = newPlayer("Wrath", pos(0, 0, 7))
	local run = newRun({{key = "wrath", value = 20}}, {hero})
	local g = newMonster("High", run.L.bossSpawn)
	run.boss, run.bossIds = "alive", {[g.id] = true}
	hero.at = pos(run.L.bossSpawn.x + 2, run.L.bossSpawn.y, 7)
	RF._wrathTick(run, 100)
	eq(#timers, 0, "first nova one period later")
	RF._wrathTick(run, 100 + cfg.wrath.thrallEvery)
	eq(#timers, 1, "a nova")
	local thralls = 0
	for id in pairs(run.thrallIds or {}) do
		thralls = thralls + 1
		ok(RF.isHusk(monsters[id]) and run.extra[id], "a thrall is a husk and extra")
	end
	eq(thralls, cfg.wrath.thralls, "thralls called")
	runTimers()
	eq(#hits, 1, "the nova hits within its radius")
	eq(hits[1] and hits[1].amount, -R.percentHit(15000, 0.2), "20% of max health")
	RF.runs[3] = nil
end

-- 5. Parched Veins keeps health regeneration and stops mana; Withering the other way round
do
	local made
	local p = newPlayer("Dry", pos(0, 0, 7))
	p.getCondition = function() return {getTicks = function() return 60000 end} end
	p.removeCondition = function() end
	p.getVocation = function()
		return {getManaGainAmount = function() return 50 end, getManaGainTicks = function() return 2 end,
			getHealthGainAmount = function() return 30 end, getHealthGainTicks = function() return 3 end}
	end
	p.addCondition = function(_, c) made = c end
	local entry = {}
	RF._wither(p, entry, {noMana = true})
	eq(made.params[CONDITION_PARAM_MANAGAIN], 0, "parched: no mana")
	eq(made.params[CONDITION_PARAM_HEALTHGAIN], 30, "parched: health kept")
	entry = {}
	RF._wither(p, entry, {noRegen = true})
	eq(made.params[CONDITION_PARAM_HEALTHGAIN], 0, "withering: no health")
	eq(made.params[CONDITION_PARAM_MANAGAIN], 50, "withering: mana kept")
end

-- 6. a brand on a monster's hit (the player's health event)
do
	monsters = {}
	local p = newPlayer("Branded", pos(0, 0, 7))
	local run = newRun({{key = "emberbrand", value = 40}}, {p})
	local m = newMonster("Mid", pos(0, 0, 7))
	RF.monsterRun[m.id] = run
	local onHit = events.ChaosRiftPlayerHit.onHealthChange
	local a, at, b, bt = onHit(p, m, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 0)
	eq(a, math.floor(-1000 * cfg.density.damage), "the pack monster's hit, density-softened")
	eq(bt, COMBAT_FIREDAMAGE, "the brand's fire in the free slot")
	eq(b, math.floor(a * 0.4), "40% of it as fire")
	RF.runs[3] = nil
end

print(string.format("rift_density_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

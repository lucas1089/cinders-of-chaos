-- Run from the server/ folder: luajit tests/rift_hitcap_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- O478: one hit of a rift guardian takes at most 60% of the victim's pool (rift_config.lua guardian.hitCap, rift_core.lua
-- R.hitPool / R.capHit, rift.lua capHit and the two events ChaosRiftHitCapHealth / ChaosRiftHitCapMana, RF.capLast).
-- rift.lua against a mocked engine, in the order of the real one: the run's scaling (ChaosRiftPlayerHit), the later events,
-- then the cap.
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
local function flush()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t.f((table.unpack or unpack)(t.args))
	end
end
doTargetCombatHealth = function() end
Condition = function(kind)
	local c = {kind = kind}
	function c:setParameter() end
	function c:addDamage() end
	return c
end
local monsters, nextMid = {}, 5000
local function newMonster(name, p)
	nextMid = nextMid + 1
	local m = {id = nextMid, name = name, at = pos(p.x, p.y, p.z)}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getPosition() return self.at end
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

local nextPid = 0
-- a player with maximum health and mana, current values, an optional mana shield and a registered-events list
local function newPlayer(maxHp, maxMana, hp, mana, shield)
	nextPid = nextPid + 1
	local p = {id = 100 + nextPid, guid = nextPid, name = "P" .. nextPid, level = 300, msgs = {}, hp = hp or maxHp,
		maxHp = maxHp, mana = mana or maxMana, maxMana = maxMana, shield = shield or false, ev = {}}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getLevel = function() return p.level end
	p.getHealth = function() return p.hp end
	p.getMaxHealth = function() return p.maxHp end
	p.getMana = function() return p.mana end
	p.getMaxMana = function() return p.maxMana end
	p.hasCondition = function(_, c) return c == CONDITION_MANASHIELD and p.shield end
	p.getPosition = function() return pos(0, 0, 7) end
	p.sendTextMessage = function() end
	p.isPlayer = function() return true end
	p.registerEvent = function(_, name)
		for _, e in ipairs(p.ev) do
			if e == name then return false end
		end
		p.ev[#p.ev + 1] = name
		return true
	end
	p.unregisterEvent = function(_, name)
		for i, e in ipairs(p.ev) do
			if e == name then table.remove(p.ev, i) return true end
		end
		return false
	end
	players[p.id] = p
	return p
end

local tier = 3
local fx = R.applyParty(cfg, R.effects(cfg, {}, tier), 1, tier)
local run = {fx = fx, players = {}, bossIds = {}, key = {tier = tier, mods = {}}}
local g = newMonster("Guardian", pos(0, 0, 7))
local twin = newMonster("Twin", pos(0, 0, 7))
local pk = newMonster("Pack", pos(0, 0, 7))
run.bossIds[g.id], run.bossIds[twin.id] = true, true
RF.monsterRun[g.id], RF.monsterRun[twin.id], RF.monsterRun[pk.id] = run, run, run
local mult = fx.damage * (fx.boss or 1) * fx.guardian
local packMult = fx.damage * (fx.packDamage or 1)

local scaleH = events.ChaosRiftPlayerHit.onHealthChange
local scaleM = events.ChaosRiftPlayerMana.onManaChange
local capH = events.ChaosRiftHitCapHealth.onHealthChange
local capM = events.ChaosRiftHitCapMana.onManaChange
ok(capH and capM, "the two cap events are registered")

-- the engine's order for a hit with no mana shield: the run's scaling, a later raising event (factor `later`), the cap.
-- Returns what the health events leave (what the energy shield and the health take together).
local function healthHit(p, attacker, raw, later, ptype)
	local pd, pt, sd, st = scaleH(p, attacker, -raw, ptype or COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	if later then
		pd, sd = math.floor(pd * later), math.floor(sd * later)
	end
	pd, pt, sd, st = capH(p, attacker, pd, pt, sd, st, 1)
	return math.abs(pd) + math.abs(sd)
end

-- what the run's scaling (and a later raise) makes of a hit, before the cap
local function scaledOf(p, attacker, raw, later)
	local pd, _, sd = scaleH(p, attacker, -raw, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	if later then
		pd, sd = math.floor(pd * later), math.floor(sd * later)
	end
	return math.abs(pd) + math.abs(sd)
end

-- the engine's order with a mana shield (Game::combatChangeHealth): the mana events on the whole hit (the run's scaling, the
-- later raise, the cap), the mana pays, the health events on the rest. Returns mana paid, health part, total
local function shieldHit(p, attacker, raw, later)
	local pd, pt, sd, st = scaleM(p, attacker, raw, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	if later then
		pd, sd = math.floor(pd * later), math.floor(sd * later)
	end
	pd, pt, sd, st = capM(p, attacker, pd, pt, sd, st, 1)
	local total = math.abs(pd) + math.abs(sd)
	local paid = math.min(p.mana, total)
	p.mana = p.mana - paid
	local rest = total - paid
	local healthPart = 0
	if rest > 0 then
		local hd, ht, hs, hst = scaleH(p, attacker, -rest, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
		if later then -- a raising event that is no mana shield provider acts on the rest
			hd, hs = math.floor(hd * later), math.floor(hs * later)
		end
		hd, ht, hs, hst = capH(p, attacker, hd, ht, hs, hst, 1)
		healthPart = math.abs(hd) + math.abs(hs)
	end
	flush()
	return paid, healthPart, total
end

-- ------------------------------------------------------------------ the config and the pure rule
do
	local c = cfg.guardian.hitCap
	ok(c and c.enabled == true, "the cap is on")
	eq(c.share, 0.60, "the share is 60%")
	eq(R.hitPool(1000, 500, false), 1000, "no mana shield: the pool is the health")
	eq(R.hitPool(1000, 500, true), 1500, "a mana shield up: health plus mana")
	eq(R.hitPool(nil, nil, true), 0, "nothing: 0")
	local p, s, limit, capped = R.capHit(cfg, -500, 0, 1000, 0)
	ok(not capped and p == -500 and s == 0 and limit == 600, "under the cap: untouched, limit 600")
	p, s, limit, capped = R.capHit(cfg, -600, 0, 1000, 0)
	ok(not capped and p == -600, "exactly at the cap: untouched")
	p, s, limit, capped = R.capHit(cfg, -601, 0, 1000, 0)
	ok(capped and p == -600 and s == 0, "one over: cut to 600")
	p, s, limit, capped = R.capHit(cfg, -3000, -1000, 1000, 0)
	ok(capped and math.abs(p) + math.abs(s) <= 600 and p == -450 and s == -150, "two parts keep their ratio: " .. p .. "/" .. s)
	ok(p < 0 and s < 0, "the sign is kept")
	p, s, limit, capped = R.capHit(cfg, 4000, 0, 1000, 0)
	ok(capped and p == 600, "a positive magnitude is cut the same")
	p, s, limit, capped = R.capHit(cfg, -400, 0, 1000, 300)
	ok(capped and p == -300 and limit == 300, "what an earlier part took is counted: 600 - 300")
	p, s, limit, capped = R.capHit(cfg, -100, 0, 1000, 700)
	ok(capped and p == 0 and limit == 0, "an earlier part over the ceiling leaves nothing")
	p, s, limit, capped = R.capHit(cfg, -9999, 0, 0, 0)
	ok(not capped and p == -9999, "no pool known: untouched")
	local off = {guardian = {hitCap = {enabled = false, share = 0.6}}}
	p, s, limit, capped = R.capHit(off, -9999, 0, 1000, 0)
	ok(not capped and p == -9999, "switched off: untouched")
	p, s, limit, capped = R.capHit({}, -9999, 0, 1000, 0)
	ok(not capped and p == -9999, "no block: untouched")
end

-- ------------------------------------------------------------------ one hit, no mana shield
do
	local p = newPlayer(3000, 2000) -- no mana shield: the pool is 3000, the cap 1800
	local raw = 1000
	local scaled = math.floor(raw * mult)
	ok(scaled > 1800, "the guardian's scaled hit is over the cap: " .. scaled)
	eq(healthHit(p, g, raw), 1800, "over the cap: cut to 60% of the pool (the mana is not in it)")
	eq(healthHit(p, g, 100), scaledOf(p, g, 100), "under the cap: as scaled")
	-- exactly at the cap: -raw such that the scaled hit is 1800
	local at = scaled > 1800 and 1800 / mult or 0
	local exact = scaleH(p, g, -math.floor(at), COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	local out = capH(p, g, -1800, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(out, -1800, "exactly the cap: untouched")
	ok(exact ~= nil, "the scaling ran")
	-- the cap uses maximum values: a player near death has the same ceiling
	local low = newPlayer(3000, 2000, 50)
	eq(healthHit(low, g, raw), 1800, "current health 50 of 3000: the cap is the same (it does not shrink)")
	-- a hit of a pack monster is not capped, the same hit of the guardian is
	local big = 5000
	eq(healthHit(p, pk, big), scaledOf(p, pk, big), "a pack monster's hit: not capped")
	ok(math.floor(big * packMult) > 1800, "(and it is over the guardian's ceiling)")
	eq(healthHit(p, twin, raw), 1800, "an extra guardian (Twin): capped")
	-- an event after the run's scaling that raises the hit (the rank x1.7, Shadow Twin, the fight's stacks): the final number is bounded
	eq(healthHit(p, g, 300, 1.7), math.min(1800, scaledOf(p, g, 300, 1.7)), "a later x1.7: the cap sees the final hit")
	eq(healthHit(p, g, 900, 1.7), 1800, "a later x1.7 on a hit already near the cap: bounded at the end")
	ok(healthHit(p, g, 900, 3.0) <= 1800, "a later x3: still bounded")
	-- party scaling and the modifiers are in the hit before the cap (the run's multiplier is applied, then the cut)
	local pfx = R.applyParty(cfg, R.effects(cfg, {{key = "brutality", value = 40}}, tier), 4, tier)
	local prun = {fx = pfx, players = {}, bossIds = {}, key = {tier = tier, mods = {}}}
	local pg = newMonster("PartyGuardian", pos(0, 0, 7))
	prun.bossIds[pg.id] = true
	RF.monsterRun[pg.id] = prun
	local pm = pfx.damage * (pfx.boss or 1) * pfx.guardian
	ok(pm > mult, "party and Brutality raise the multiplier: " .. pm .. " > " .. mult)
	local small = 200
	eq(healthHit(p, pg, small), math.min(1800, scaledOf(p, pg, small)), "scaled with party and modifiers, then capped if over")
	eq(healthHit(p, pg, 5000), 1800, "a big hit under the party multiplier: cut to the same 60%")
	-- a damage over time tick and a marked attack are guardian hits too: capped like any
	eq(healthHit(p, g, 4000, nil, COMBAT_FIREDAMAGE), 1800, "another damage type: capped")
	-- two parts of a hit: the sum is held
	local pd, pt, sd, st = capH(p, g, -3000, COMBAT_PHYSICALDAMAGE, -1000, COMBAT_FIREDAMAGE, 1)
	ok(math.abs(pd) + math.abs(sd) <= 1800 and st == COMBAT_FIREDAMAGE, "primary and secondary: the sum is under the cap, the type is kept")
	-- healing, a reflect (no attacker), a victim that is no player: untouched
	pd = capH(p, g, 5000, COMBAT_HEALING, 0, COMBAT_NONE, 1)
	eq(pd, 5000, "healing is untouched")
	pd = capH(p, nil, -9000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(pd, -9000, "no attacker (a reflect, a field): untouched")
	local summon = newMonster("Summon", pos(0, 0, 7))
	pd = capH(summon, g, -9000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(pd, -9000, "a summon is not the victim here")
	local stranger = newMonster("Stranger", pos(0, 0, 7))
	pd = capH(p, stranger, -9000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(pd, -9000, "a monster of no run: untouched")
end

-- ------------------------------------------------------------------ the mana shield
do
	-- pool = 3000 health + 2000 mana = 5000, cap 3000
	local raw = 2000
	local scaled = math.floor(raw * mult)
	ok(scaled > 3000, "the scaled hit is over the cap: " .. scaled)
	local p = newPlayer(3000, 2000, 3000, 2000, true)
	local paid, healthPart, total = shieldHit(p, g, raw)
	eq(total, 3000, "the mana event cut the whole hit to 60% of health + mana")
	eq(paid, 2000, "the mana pays what it has")
	eq(healthPart, 1000, "the health part is the rest, not cut a second time")
	ok(paid + healthPart <= 3000, "the parts together are at most the cap")
	ok(next(RF._capMark) == nil, "no mark left when the engine call ends")
	-- the mana holds only 500: the health part is cap - 500
	local q = newPlayer(3000, 2000, 3000, 500, true)
	paid, healthPart = shieldHit(q, g, raw)
	eq(paid, 500, "500 mana")
	eq(healthPart, 2500, "the health pays the rest of the cap")
	ok(paid + healthPart <= 3000, "the sum holds")
	-- a raising event that acts on the rest only (no mana shield provider): the health event holds cap - paid
	local r = newPlayer(3000, 2000, 3000, 500, true)
	paid, healthPart = shieldHit(r, g, raw, 1.5)
	ok(paid + healthPart <= 3000, "a later raise on the rest: the sum is still at most the cap: " .. paid .. " + " .. healthPart)
	-- the mana takes it whole: no health event; the mark does not leak into the next hit
	local s = newPlayer(3000, 100000, 3000, 100000, true)
	paid, healthPart, total = shieldHit(s, g, 100)
	eq(paid, total, "the mana takes it all")
	eq(healthPart, 0, "no health part")
	ok(next(RF._capMark) == nil, "no mark left")
	-- a hit under the cap that overflows the mana: neither part cut, the scaling happened once
	local u = newPlayer(30000, 20000, 30000, 100, true)
	paid, healthPart, total = shieldHit(u, g, 1000)
	eq(total, math.floor(1000 * mult), "a hit under the cap: its multiplier once")
	eq(paid + healthPart, math.floor(1000 * mult), "mana plus health is the whole hit")
	-- no mana at all: the mana events do not run, the health event caps against the whole pool (mana counted while the shield is up)
	local z = newPlayer(3000, 2000, 3000, 0, true)
	eq(healthHit(z, g, raw), 3000, "shield up, no mana left: the ceiling is still 60% of health + mana")
	-- the shield is down: mana is not in the pool
	local d = newPlayer(3000, 2000, 3000, 2000, false)
	eq(healthHit(d, g, raw), 1800, "no shield up: the pool is the health")
	-- the energy shield is not in the pool: what it and the health take together is what the health event leaves (<= cap)
	local es = newPlayer(3000, 2000)
	es.getEnergyShield = function() return 5000 end
	eq(healthHit(es, g, raw), 1800, "an energy shield does not raise the ceiling: shield + health lose at most 1800")
	-- another attacker right after a marked hit is not held by the mark
	local m = newPlayer(3000, 2000, 3000, 500, true)
	local pd = scaleM(m, g, 2000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	capM(m, g, pd, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	m.mana = 0
	local out = capH(m, pk, -5000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 1)
	eq(out, -5000, "a pack monster is never capped, mark or not")
	flush()
end

-- ------------------------------------------------------------------ the switch
do
	local c = cfg.guardian.hitCap
	c.enabled = false
	local p = newPlayer(3000, 2000)
	eq(healthHit(p, g, 1000), scaledOf(p, g, 1000), "switched off: the hit is as scaled")
	c.enabled = true
	eq(healthHit(p, g, 1000), 1800, "back on")
end

-- ------------------------------------------------------------------ the place in the event order
do
	local p = newPlayer(3000, 2000)
	-- a fresh login: the late registrars have not run yet; entering a run puts the cap behind them
	p:registerEvent("ChaosRiftPlayerHit")
	p:registerEvent("ChaosRiftHitCapHealth") -- an early registration (a first call, a reload)
	p:registerEvent("ChaosBossMechTaken")
	RF.capLast(p)
	local pos2 = {}
	for i, name in ipairs(p.ev) do
		pos2[name] = i
	end
	for _, late in ipairs(RF.CAP_AFTER) do
		ok(pos2[late], late .. " is registered")
		ok(pos2["ChaosRiftHitCapHealth"] > pos2[late] and pos2["ChaosRiftHitCapMana"] > pos2[late], "the cap runs after " .. late)
	end
	for _, after in ipairs(RF.CAP_BEFORE) do
		ok(pos2[after] and pos2[after] > pos2["ChaosRiftHitCapMana"], after .. " runs after the cap")
	end
	ok(pos2["ChaosRiftHitCapMana"] == #p.ev - #RF.CAP_BEFORE and pos2["ChaosRiftHitCapHealth"] == #p.ev - #RF.CAP_BEFORE - 1,
		"the cap events come right before the events that must see the capped hit")
	-- twice: the same order, no duplicates
	RF.capLast(p)
	local seen, dup = {}, false
	for _, name in ipairs(p.ev) do
		if seen[name] then dup = true end
		seen[name] = true
	end
	ok(not dup, "no event twice")
	eq(p.ev[#p.ev], "ChaosPowersLastBreath", "Last Breath still last")
	eq(p.ev[#p.ev - 1], "ChaosRiftHitCapMana", "the cap right before it")
	-- something registered after a run entry is moved behind by the next entry
	p:registerEvent("ChaosMentorHealth")
	RF.capLast(p)
	eq(p.ev[#p.ev - 1], "ChaosRiftHitCapMana", "and behind it again after the next entry")
end

print(string.format("rift_hitcap_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

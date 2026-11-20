-- Run from the server/ folder: luajit tests/spell_forms_test.lua && lua5.3 tests/spell_forms_test.lua (CI runs both)
-- O686 phase 4: the spell Forms. Part A: the pure core (every kind of Form I, Form II and the heals on a synthetic cast, the PvP half rule,
-- the pick / change / price rules, the table forms.csv, the model band of docs/SPELL_UPGRADES.md 2.1). Part B: spell_forms.lua on a
-- mocked engine (off when the switch is off, the rank gate, the hit factor and the element, the extra hits run as hits of the spell inside
-- the cast context under the proc guard, nothing for a Form hit again, PvP numbers, pick / change / price on the wire, a Form hit reads
-- the level and magic level through the hit it is a share of).

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(type(a) == "number" and math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

dofile("data/scripts/chaos/spell_forms_core.lua")
local F = ChaosSpellFormsCore
local cfg = dofile("data/scripts/chaos/spell_ranks_config.lua")

-- ================================================================ Part A: the core
-- kinds
eq(#F.kinds1, 9, "9 Form I kinds")
eq(#F.kinds2, 8, "8 Form II kinds")
eq(#F.heal1, 4, "4 heal Form I kinds")
eq(#F.heal2, 4, "4 heal Form II kinds")
for _, k in ipairs(F.kinds1) do
	ok(F.numbers[k], "numbers for Form I " .. k)
	ok(F.situation[k] and F.scope[k], "situation and scope for " .. k)
end
for _, k in ipairs(F.kinds2) do
	ok(F.numbers[k], "numbers for Form II " .. k)
end
for _, k in ipairs(F.heal1) do
	ok(F.numbers[k], "numbers for heal I " .. k)
end
for _, k in ipairs(F.heal2) do
	ok(F.numbers[k], "numbers for heal II " .. k)
end
eq(select(1, F.parseKind("SHIFT:ice")), "SHIFT", "parseKind base")
eq(select(2, F.parseKind("SHIFT:ice")), "ice", "parseKind element")
eq(select(2, F.parseKind("SPLIT")), nil, "parseKind plain")
ok(F.validKind("SPLIT", 1, false), "SPLIT is Form I")
ok(not F.validKind("SPLIT", 2, false), "SPLIT is not Form II")
ok(F.validKind("SHIFT:ice", 1, false), "SHIFT:ice")
ok(not F.validKind("SHIFT", 1, false), "SHIFT needs an element")
ok(not F.validKind("SHIFT:weakest", 1, false), "weakest is for ASCEND")
ok(F.validKind("ASCEND:weakest", 2, false), "ASCEND:weakest")
ok(not F.validKind("SPLIT:fire", 1, false), "SPLIT takes no element")
ok(F.validKind("RIPPLE", 1, true) and not F.validKind("RIPPLE", 1, false), "heal kinds are for heals")
ok(not F.validKind("ASCEND:plasma", 2, false), "unknown element")

-- overrides
do
	local o = F.parseOver("pct=40;count=2", "SPLIT")
	eq(o.pct, 40, "override pct")
	eq(o.count, 2, "override count")
	ok(F.parseOver("bogus=1", "SPLIT") == nil, "unknown key refused")
	ok(F.parseOver("pct", "SPLIT") == nil, "bad text refused")
	eq(F.params("SPLIT", {pct = 20}).pct, 20, "params take the override")
	eq(F.params("SPLIT", {zzz = 20}).zzz, nil, "params ignore an unknown key")
	eq(F.params("SPLIT").pct, 35, "params default")
end

-- a synthetic cast: the main hit on enemy 1 at (100,100), enemies 2..5 packed near it
local function cast(opts)
	opts = opts or {}
	local hits = {{id = 1, pos = {x = 100, y = 100, z = 7}, amount = 1000, kill = opts.kill, health = opts.health and opts.health[1] or 5000,
		maxHealth = 10000}}
	for i = 2, (opts.hit or 1) do
		hits[#hits + 1] = {id = i, pos = {x = 100 + i, y = 100, z = 7}, amount = 1000, health = 5000, maxHealth = 10000}
	end
	local foes = {}
	for i = 1, (opts.foes or 5) do
		foes[#foes + 1] = {id = i, pos = {x = 100 + (i - 1), y = 100, z = 7}, health = opts.health and opts.health[i] or 5000,
			maxHealth = 10000}
	end
	local line = {}
	for i = 2, (opts.line or 3) do
		line[#line + 1] = {id = i, pos = {x = 100 + i, y = 100, z = 7}}
	end
	return {hits = hits, foes = foes, allies = foes, line = line, pvp = opts.pvp, pvpShare = 0.5,
		resist = opts.resist or function() return 0 end}
end
local function spec(kind, tier, element, over)
	return {tier = tier or 1, kind = kind, element = element, over = over or {}}
end
local function sum(plan, t)
	local n = 0
	for _, a in ipairs(plan.actions) do
		if not t or a.t == t then
			n = n + (a.amount or 0)
		end
	end
	return n
end
local function count(plan, t)
	local n = 0
	for _, a in ipairs(plan.actions) do
		if not t or a.t == t then
			n = n + 1
		end
	end
	return n
end

-- Form I
do
	local p = F.plan(spec("SPLIT"), cast())
	eq(p.factors[1], 0.35, "SPLIT: the main hit is 35%")
	eq(count(p, "hit"), 2, "SPLIT: two more hits")
	eq(sum(p, "hit"), 700, "SPLIT: 35% each")
	local single = F.plan(spec("SPLIT"), cast({foes = 1}))
	eq(count(single, "hit"), 2, "SPLIT on one enemy: the hits fall on it in turn")
	eq(single.actions[1].id, 1, "SPLIT on one enemy: its own id")

	p = F.plan(spec("CHAIN"), cast())
	eq(p.factors[1], 0.95, "CHAIN: main 95%")
	eq(count(p, "hit"), 2, "CHAIN: two jumps")
	eq(p.actions[1].amount, 70, "CHAIN: first jump 7%")
	eq(p.actions[2].amount, 50, "CHAIN: second jump 5%")
	ok(p.actions[1].id ~= 1 and p.actions[2].id ~= 1, "CHAIN: never back on the main target")
	eq(count(F.plan(spec("CHAIN"), cast({foes = 1})), "hit"), 0, "CHAIN with nobody near: no jump")

	p = F.plan(spec("PIERCE"), cast())
	eq(p.factors[1], 1, "PIERCE: the main hit stays whole")
	eq(count(p, "hit"), 2, "PIERCE: the two enemies behind on the line")
	eq(p.actions[1].amount, 30, "PIERCE: 3% each")
	eq(count(F.plan(spec("PIERCE"), cast({line = 1})), "hit"), 0, "PIERCE with nothing behind: nothing")

	p = F.plan(spec("REND"), cast())
	eq(p.factors[1], 0.7, "REND: 70% now")
	eq(count(p, "dot"), 1, "REND: a damage over time")
	eq(p.actions[1].amount * p.actions[1].ticks, 400, "REND: 40% over the ticks")

	p = F.plan(spec("DELAY"), cast())
	eq(p.factors[1], 0, "DELAY: no hit now")
	eq(p.actions[1].delay, 1500, "DELAY: after 1.5 s")
	eq(p.actions[1].amount, 1100, "DELAY: the burst")
	ok(p.actions[1].telegraph, "DELAY: with a telegraph")

	p = F.plan(spec("PULL"), cast({hit = 3}))
	eq(p.factors[1], 0.95, "PULL: 95%")
	eq(p.factors[3], 0.95, "PULL: every hit")
	eq(count(p, "pull"), 2, "PULL: the two enemies away from the centre are pulled")
	local pl = cast({hit = 2})
	pl.hits[2].player = true
	eq(count(F.plan(spec("PULL"), pl), "pull"), 0, "PULL never moves a player")

	p = F.plan(spec("GROUND"), cast())
	eq(count(p, "ground"), 1, "GROUND: one ground")
	eq(p.actions[1].seconds, 4, "GROUND: 4 s")
	eq(p.actions[1].amount, 30, "GROUND: 3% a second")
	eq(count(F.plan(spec("GROUND"), cast({hit = 5})), "ground"), 3, "GROUND: at most three grounds")

	p = F.plan(spec("ECHO"), cast())
	eq(p.factors[1], 0.85, "ECHO: main 85%")
	eq(p.actions[1].amount, 220, "ECHO: a second hit")
	eq(p.actions[1].delay, 1000, "ECHO: after 1 s")

	p = F.plan(spec("SHIFT", 1, "ice"), cast())
	eq(p.convert, "ice", "SHIFT: the element")
	eq(count(p, "dot"), 1, "SHIFT: a status")
	eq(p.actions[1].element, "ice", "SHIFT: the status is of the element")
end

-- Form II
do
	local p = F.plan(spec("TWIN", 2), cast())
	eq(p.factors[1], 0.75, "TWIN: the first cast 75%")
	eq(p.actions[1].amount, 300, "TWIN: the second 30%")
	eq(p.actions[1].delay, 400, "TWIN: 0.4 s later")
	eq(p.cooldownAddMs, 400, "TWIN: the cooldown starts after the second")

	p = F.plan(spec("CASCADE", 2), cast({kill = true}))
	eq(count(p, "hit"), 1, "CASCADE: a kill gives a free hit")
	eq(p.actions[1].amount, 250, "CASCADE: 25%")
	ok(p.actions[1].id ~= 1, "CASCADE: on another enemy")
	eq(count(F.plan(spec("CASCADE", 2), cast()), "hit"), 0, "CASCADE: no kill, no hit")
	eq(count(F.plan(spec("CASCADE", 2), cast({kill = true, foes = 1})), "hit"), 0, "CASCADE: nobody else near")

	p = F.plan(spec("AFTERMATH", 2), cast())
	eq(p.actions[1].t, "burst", "AFTERMATH: a burst")
	eq(p.actions[1].amount, 75, "AFTERMATH: 7.5%")

	p = F.plan(spec("OVERCHARGE", 2), cast())
	eq(p.factors[1], 0, "OVERCHARGE: nothing now")
	eq(p.actions[1].delay, 600, "OVERCHARGE: 0.6 s later")
	eq(p.actions[1].amount, 1120, "OVERCHARGE: stronger")
	ok(p.actions[1].telegraph, "OVERCHARGE: telegraph")

	p = F.plan(spec("SIPHON", 2), cast())
	eq(p.actions[1].t, "selfheal", "SIPHON: heals")
	eq(p.actions[1].amount, 40, "SIPHON: 4% of the damage")
	eq(p.actions[1].capPct, 5, "SIPHON: at most 5% of max health")
	eq(p.actions[2].t, "selfmana", "SIPHON: mana")
	eq(p.actions[2].amount, 30, "SIPHON: 3% as mana")

	p = F.plan(spec("SEEK", 2), cast({health = {5000, 900, 3000, 4000, 5000}}))
	eq(p.factors[1], 0, "SEEK: the main hit moves")
	eq(p.actions[1].id, 2, "SEEK: to the weakest enemy in reach")
	eq(p.actions[1].amount, 1020, "SEEK: with the hit")
	p = F.plan(spec("SEEK", 2), cast({health = {100, 900, 3000}}))
	eq(p.factors[1], 1.02, "SEEK: the target is already the weakest")
	eq(count(p, "hit"), 0, "SEEK: no redirect")

	p = F.plan(spec("SPREAD", 2), cast())
	eq(count(p, "dot"), 2, "SPREAD: two enemies")
	ok(p.actions[1].id ~= 1, "SPREAD: not the target")

	p = F.plan(spec("ASCEND", 2, "fire"), cast())
	eq(p.convert, "fire", "ASCEND: the element")
	eq(p.factors[1], 1.02, "ASCEND: a stronger hit")
	local res = {fire = 80, ice = 10, energy = 50, earth = 0, holy = 30, death = 90}
	p = F.plan(spec("ASCEND", 2, "weakest"), cast({resist = function(e) return res[e] or 0 end}))
	eq(p.convert, "earth", "ASCEND:weakest picks the element the target resists least")
	res.earth = 90
	p = F.plan(spec("ASCEND", 2, "weakest"), cast({resist = function(e) return res[e] or 0 end}))
	eq(p.convert, "ice", "ASCEND:weakest follows the resistances")
	p = F.plan(spec("ASCEND", 2, "weakest"), cast())
	eq(p.convert, "fire", "ASCEND:weakest: a tie goes in the fixed order")
end

-- heals: the hit is a heal of 1000 on ally 1 with 4000 of 10000 health
do
	local function healCast(o)
		o = o or {}
		local c = cast({foes = o.allies or 5})
		c.hits[1].health = o.health or 4000
		c.hits[1].maxHealth = 10000
		c.hits[1].overheal = o.overheal or 0
		c.heal = true
		return c
	end
	local p = F.plan(spec("RIPPLE"), healCast())
	eq(p.factors[1], 0.95, "RIPPLE: main 95%")
	eq(count(p, "heal"), 2, "RIPPLE: two allies")
	eq(p.actions[1].amount, 60, "RIPPLE: 6%")
	p = F.plan(spec("BLOOM"), healCast())
	eq(p.factors[1], 0.75, "BLOOM: less now")
	eq(p.actions[1].t, "hot", "BLOOM: a heal over time")
	near(p.actions[1].amount * p.actions[1].ticks, 350, 10, "BLOOM: 35% over 6 s")
	p = F.plan(spec("WARD"), healCast({overheal = 800}))
	eq(p.actions[1].t, "shield", "WARD: a shield")
	eq(p.actions[1].amount, 800, "WARD: the overheal")
	p = F.plan(spec("WARD"), healCast({overheal = 5000}))
	eq(p.actions[1].amount, 1000, "WARD: at most 10% of max health")
	eq(count(F.plan(spec("WARD"), healCast()), "shield"), 0, "WARD: no overheal, no shield")
	p = F.plan(spec("PULSE"), healCast())
	eq(count(p, "heal"), 3, "PULSE: the allies within 3 sqm")
	eq(p.actions[1].amount, 30, "PULSE: 3%")
	p = F.plan(spec("SECONDWIND", 2), healCast({health = 3000}))
	eq(p.factors[1], 1.25, "SECOND WIND: a low target gets more")
	eq(p.cooldownCutPct, 20, "SECOND WIND: and the cooldown is cut")
	p = F.plan(spec("SECONDWIND", 2), healCast({health = 6000}))
	eq(p.factors[1], nil, "SECOND WIND: a healthy target: nothing")
	p = F.plan(spec("LINK", 2), healCast({health = 3000}))
	eq(p.actions[1].delay, 2000, "LINK: after 2 s")
	eq(p.actions[1].amount, 300, "LINK: 30%")
	eq(count(F.plan(spec("LINK", 2), healCast({health = 6000})), "heal"), 0, "LINK: over 50%: nothing")
	p = F.plan(spec("SANCTUARY", 2), healCast())
	eq(p.actions[1].t, "groundheal", "SANCTUARY: a ground that heals")
	eq(p.actions[1].seconds, 5, "SANCTUARY: 5 s")
	p = F.plan(spec("CLEANSE", 2), healCast())
	eq(count(p, "cleanse"), 1, "CLEANSE: a debuff")
	eq(p.actions[2].amount, 50, "CLEANSE: a 5% shield")
end

-- two Forms of one cast and the PvP half rule
do
	local both = F.planAll({spec("SPLIT"), spec("ASCEND", 2, "fire")}, cast())
	near(both.factors[1], 0.35 * 1.02, 1e-9, "planAll: the factors multiply")
	eq(both.convert, "fire", "planAll: the conversion")
	ok(#both.actions >= 3, "planAll: the actions join")
	local solo = F.plan(spec("REND"), cast())
	local pv = F.plan(spec("REND"), cast({pvp = true}))
	near(pv.factors[1], 0.85, 1e-9, "PvP: the main factor moves half the way (70% -> 85%)")
	eq(pv.actions[1].amount, math.floor(solo.actions[1].amount * 0.5), "PvP: extra amounts at the half rule")
	local d = F.plan(spec("DELAY"), cast({pvp = true}))
	eq(d.factors[1], 0.5, "PvP: DELAY: half of the hit now")
	eq(d.actions[1].amount, 550, "PvP: DELAY: half the burst")
	local s = F.plan(spec("SHIFT", 1, "ice"), cast({pvp = true}))
	eq(s.convert, "ice", "PvP: the shape stays: the element still converts")
end

-- the factor on one hit at the moment it lands
do
	local hit = {id = 1, pos = {x = 100, y = 100, z = 7}, amount = 1000}
	near(F.hitFactor({spec("SPLIT")}, hit, true, false, 0.5), 0.35, 1e-9, "hitFactor: the first hit of a main kind")
	eq(F.hitFactor({spec("SPLIT")}, hit, false, false, 0.5), 1, "hitFactor: a later hit of a main kind: untouched")
	eq(F.hitFactor({spec("REND")}, hit, false, false, 0.5), 0.7, "hitFactor: an all kind reaches every hit")
	near(F.hitFactor({spec("SPLIT"), spec("TWIN", 2)}, hit, true, false, 0.5), 0.35 * 0.75, 1e-9, "hitFactor: Form I and Form II multiply")
end

-- pick, change, price
do
	local st = {rank = 9, f1 = 0, f2 = 0, level = 1000, spellId = 200, now = 1000000, lastAt = -1, lastWhat = -1}
	eq(F.decide(st, 1, 1, cfg).why, "rank", "Form I needs rank 10")
	st.rank = 10
	local d = F.decide(st, 1, 1, cfg)
	ok(d.ok and d.free and d.why == "first", "the first pick is free")
	eq(F.decide(st, 2, 1, cfg).why, "rank", "Form II needs rank 20")
	st.rank = 20
	eq(F.decide(st, 2, 1, cfg).why, "form1", "Form II needs a Form I first")
	st.f1 = 1
	ok(F.decide(st, 2, 2, cfg).free, "the first Form II pick is free")
	ok(F.decide(st, 1, 1, cfg).noop, "the same pick again is a no-op")
	eq(F.decide(st, 3, 1, cfg).why, "tier", "bad tier")
	eq(F.decide(st, 1, 3, cfg).why, "pick", "bad pick")
	d = F.decide(st, 1, 2, cfg)
	ok(d.ok and not d.free and d.price == 150000, "a change at level 1000 costs 150,000 gold")
	st.level = 20
	eq(F.decide(st, 1, 2, cfg).price, 10000, "the price has a floor of 10,000")
	eq(F.price(100, cfg), 15000, "level 100: 15,000")
	eq(F.price(66, cfg), 10000, "level 66: the floor")
	eq(F.price(67, cfg), 10050, "level 67: 150 x 67")
	st.lastWhat, st.lastAt = 2001, st.now - 1700
	d = F.decide(st, 1, 2, cfg)
	ok(d.ok and d.free and d.why == "window", "within 30 minutes of the last pick of that spell and tier: free")
	st.lastAt = st.now - 1801
	ok(not F.decide(st, 1, 2, cfg).free, "after 30 minutes: paid")
	st.lastAt, st.lastWhat = st.now - 10, 2012
	ok(not F.decide(st, 1, 2, cfg).free, "the window is for the last pick only (another tier)")
	local s = F.split(150000, 100000, 80000)
	eq(s.fromBank, 100000, "the bank first")
	eq(s.fromCoins, 50000, "then the coins")
	eq(F.split(150000, 200000, 0).fromBank, 150000, "all from the bank when it holds enough")
	ok(F.split(150000, 100000, 40000) == nil, "short: nothing taken")
end

-- the table forms.csv
local FormsLib
do
	dofile("data/lib/chaos_spell_forms.lua")
	FormsLib = ChaosSpellForms
	local f = assert(io.open("data/spells/forms.csv", "r"))
	local text = f:read("*a")
	f:close()
	local rows, err = FormsLib.parse(text)
	ok(rows, "forms.csv parses " .. tostring(err))
	local n, rowsN = 0, 0
	for id, s in pairs(rows or {}) do
		n = n + 1
		for tier = 1, 2 do
			for pick = 1, 2 do
				local sp = s[tier][pick]
				ok(sp, string.format("spell %d tier %d pick %d has a row", id, tier, pick))
				if sp then
					rowsN = rowsN + 1
					ok(F.validKind(sp.row.kind, tier, s.heal), string.format("%s: kind %s is valid for tier %d", s.name, sp.row.kind, tier))
					ok(sp.nameEn ~= "" and sp.namePt ~= "", s.name .. ": names")
				end
			end
			ok(s[tier][1] and s[tier][2] and s[tier][1].kind ~= s[tier][2].kind, string.format("%s tier %d: two different kinds", s.name, tier))
		end
	end
	eq(n, 149, "149 spells have Forms")
	eq(rowsN, 596, "596 rows")
	-- every row sits in the model band (docs/SPELL_UPGRADES.md 2.1): one target -5..+8%, five targets -5..+12%
	for id, s in pairs(rows or {}) do
		for tier = 1, 2 do
			for pick = 1, 2 do
				local sp = s[tier][pick]
				if sp then
					local g1 = F.gain(sp, 1, 1)
					local g5 = F.gain(sp, 5, 1)
					ok(g1 >= 0.95 - 1e-9 and g1 <= 1.08 + 1e-9, string.format("%s %s: one target %.3f in band", s.name, sp.row.kind, g1))
					ok(g5 >= 0.95 - 1e-9 and g5 <= 1.12 + 1e-9, string.format("%s %s: five targets %.3f in band", s.name, sp.row.kind, g5))
				end
			end
		end
	end
end

-- ================================================================ Part B: the engine file on a mocked engine
local registered = {events = {}, callbacks = {}}
local function evObj()
	return function(name)
		local o = {name = name}
		function o:type(t) self.t = t end
		function o:register() registered.events[name] = self end
		function o:interval() end
		return o
	end
end
CreatureEvent = evObj()
GlobalEvent = evObj()
TalkAction = evObj()
EventCallback = {register = function(self, index) registered.callbacks[#registered.callbacks + 1] = {onTargetCombat = self.onTargetCombat, index = index} end}
MESSAGE_STATUS_DEFAULT, MESSAGE_INFO_DESCR = 1, 2
ORIGIN_SPELL, ORIGIN_CONDITION, ORIGIN_MELEE, COMBAT_HEALING, COMBAT_NONE = 3, 4, 1, 9, 0
COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_ENERGYDAMAGE = 1, 2, 4, 8
COMBAT_EARTHDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 16, 32, 64
CONST_ME_NONE = 0
RETURNVALUE_NOERROR = 0
TILESTATE_PROTECTIONZONE, TILESTATE_BLOCKSOLID = 1, 2
CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT = 50, 0
CONST_ANI_FIRE, CONST_ANI_ICE, CONST_ANI_ENERGY, CONST_ANI_EARTH, CONST_ANI_HOLY, CONST_ANI_DEATH, CONST_ANI_THROWINGKNIFE = 4, 29, 5, 30, 31, 11, 9

local clock = 1000000
os.mtime = function() return clock end
local scheduled = {}
function addEvent(fn, delay, ...) scheduled[#scheduled + 1] = {fn = fn, delay = delay, args = {...}, n = select("#", ...)} return #scheduled end
local function runScheduled(maxDelay)
	local i = 1
	while i <= #scheduled do
		local e = scheduled[i]
		if not e.done and (not maxDelay or e.delay <= maxDelay) then
			e.done = true
			e.fn((table.unpack or unpack)(e.args, 1, e.n))
		end
		i = i + 1
	end
end
local function clearScheduled() scheduled = {} end

json = {encode = function(t) return "json" end, decode = function(s) return nil end}
db = {query = function() return true end, asyncQuery = function() end, storeQuery = function() return nil end}
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data} return true end
Chaos.t = function(player, fmt, ...) return string.format(fmt, ...) end

-- positions
local Pmt = {}
local effects = {}
local function Position(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z or 7}, Pmt)
end
Pmt.__index = {
	sendMagicEffect = function(self, id) effects[#effects + 1] = {id = id, x = self.x, y = self.y} end,
	sendDistanceEffect = function(self, to, id) effects[#effects + 1] = {ani = id} end,
}
_G.Position = Position

-- the world
local world = {creatures = {}}
local storages = {}
local calls = {}      -- doTargetCombat calls
local guardSeen = {}  -- the guards seen during a doTargetCombat
local messages = {}

local function newCreature(id, kind, x, y, health, max)
	storages[id] = storages[id] or {}
	local c = {id = id, kind = kind, x = x, y = y, health = health or 5000, max = max or 10000, level = 500, ml = 100, mana = 5000,
		bank = 0, coins = 0, conditions = {}, name = "C" .. id}
	function c:getId() return self.id end
	function c:isPlayer() return self.kind == "player" end
	function c:isMonster() return self.kind == "monster" end
	function c:getPosition() return Position(self.x, self.y, 7) end
	function c:getHealth() return self.health end
	function c:getMaxHealth() return self.max end
	function c:getMana() return self.mana end
	function c:getMaxMana() return 10000 end
	function c:addMana(n) self.mana = self.mana + n self.manaAdded = (self.manaAdded or 0) + n end
	function c:addHealth(a, b) local n = b or a self.health = math.min(self.max, self.health + n) end
	function c:getMaster() return self.master end
	function c:getTile() return {hasFlag = function(_, f) return self.pz == true and f == TILESTATE_PROTECTIONZONE end, getTopCreature = function() return nil end} end
	function c:getParty() return self.party end
	function c:getName() return self.name end
	function c:getLevel() return self.level end
	function c:getMagicLevel() return self.ml end
	function c:getType() return {getElementList = function() return self.elements or {} end} end
	function c:registerEvent() end
	function c:hasCondition(t) return self.conditions[t] == true end
	function c:removeCondition(t) self.conditions[t] = nil end
	function c:getCondition() return nil end
	function c:teleportTo(pos) self.x, self.y = pos.x, pos.y self.teleported = true end
	function c:getStorageValue(k) local v = storages[self.id][k] return v == nil and -1 or v end
	function c:setStorageValue(k, v) storages[self.id][k] = v end
	function c:sendTextMessage(t, text) messages[#messages + 1] = text end
	function c:getGroup() return {getAccess = function() return false end} end
	function c:getBankBalance() return self.bank end
	function c:setBankBalance(n) self.bank = n return true end
	function c:getMoney() return self.coins end
	function c:removeMoney(n) if self.coins >= n then self.coins = self.coins - n return true end return false end
	function c:getAccountId() return self.id * 10 end
	world.creatures[id] = c
	return c
end
function Creature(id) return type(id) == "table" and id or world.creatures[id] end
function Player(id) local c = type(id) == "table" and id or world.creatures[id] return c and c.kind == "player" and c or nil end
function Tile(pos) return {getTopCreature = function() return nil end, hasFlag = function() return false end} end
Game = {getSpectators = function(center, multifloor, onlyPlayers, rx, ry)
	local out = {}
	for _, c in pairs(world.creatures) do
		if math.max(math.abs(c.x - center.x), math.abs(c.y - center.y)) <= rx and c.health > 0 then
			out[#out + 1] = c
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end}
function doTargetCombat(attacker, target, ctype, a, b, effect, origin)
	local K = rawget(_G, "ChaosKeystones")
	calls[#calls + 1] = {attacker = attacker.id, target = target.id, ctype = ctype, amount = a, origin = origin,
		ctx = storages[attacker.id][7109990], keystones = K and K.depth or 0, formDepth = ChaosSupports.formDepth,
		depth = ChaosSpellForms.depth}
	if ctype == COMBAT_HEALING then
		target.health = math.min(target.max, target.health + a)
	else
		target.health = target.health + a
	end
	return true
end
ChaosKeystones = {depth = 0}

dofile("data/scripts/chaos/spell_forms.lua")
local FE = ChaosSpellForms
local S = ChaosSupports
local C = ChaosSpellRanksConfig
local P = ChaosSpellRanksCore
ok(registered.events.ChaosSpellFormsHit and registered.events.ChaosSpellFormsShield, "the hit and shield events are registered")
eq(registered.callbacks[#registered.callbacks].index, 2, "the target callback runs after the supports (1) and the passive tree (0)")
ok(ChaosSpellEvents.handlers.cooldown[#ChaosSpellEvents.handlers.cooldown].key == "spellforms", "a cooldown handler")

-- the Forms table of the mock: spell 200 (single target damage), 201 (area), 208 (heal)
local function row(tier, pick, kind, over)
	local sp = F.specOf({tier = tier == 1 and "I" or "II", kind = kind, over = over or ""})
	sp.nameEn, sp.namePt, sp.row = kind, kind, {kind = kind}
	return sp
end
FE.setTable({
	[200] = {id = 200, name = "Bolt", heal = false, element = "fire", [1] = {row(1, 1, "SPLIT"), row(1, 2, "SHIFT:ice")},
		[2] = {row(2, 1, "TWIN"), row(2, 2, "ASCEND:holy")}},
	[201] = {id = 201, name = "Wave", heal = false, element = "ice", [1] = {row(1, 1, "REND"), row(1, 2, "CHAIN")},
		[2] = {row(2, 1, "SIPHON"), row(2, 2, "AFTERMATH")}},
	[208] = {id = 208, name = "Mend", heal = true, [1] = {row(1, 1, "RIPPLE"), row(1, 2, "WARD")},
		[2] = {row(2, 1, "SECONDWIND"), row(2, 2, "LINK")}},
})

local function setPacked(c, spell, rank, f1, f2)
	c:setStorageValue(C.storage.rankBase + spell, P.pack(rank, f1, f2, false))
end
local function cast_(player, spellId, serial)
	player:setStorageValue(7109990, (serial or 1) * 1000 + spellId)
end
local hitEv = registered.events.ChaosSpellFormsHit
local function hit(target, attacker, dmg, ctype)
	return hitEv.onHealthChange(target, attacker, -dmg, ctype or COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL, false)
end

local me = newCreature(1, "player", 100, 100)
local m1 = newCreature(11, "monster", 103, 100)
local m2 = newCreature(12, "monster", 104, 100)
local m3 = newCreature(13, "monster", 103, 101)
local m4 = newCreature(14, "monster", 102, 99)
setPacked(me, 200, 10, 1, 0)

-- off: nothing changes
C.enabled = false
cast_(me, 200)
do
	local a, b, c, d = hit(m1, me, 1000)
	eq(a, -1000, "off: the hit is untouched")
	runScheduled()
	eq(#calls, 0, "off: no extra hits")
	eq(#FE.active(me, 200), 0, "off: no Form is active")
end
C.enabled = true

-- the rank gate and the pick gate
do
	setPacked(me, 200, 9, 1, 0)
	eq(#FE.active(me, 200), 0, "rank 9: no Form I yet")
	setPacked(me, 200, 10, 0, 0)
	eq(#FE.active(me, 200), 0, "rank 10 with no pick: nothing")
	setPacked(me, 200, 10, 1, 2)
	eq(#FE.active(me, 200), 1, "rank 10 with a Form II pick stored: Form II waits for rank 20")
	setPacked(me, 200, 20, 1, 2)
	eq(#FE.active(me, 200), 2, "rank 20: both")
	setPacked(me, 200, 10, 1, 0)
end

-- a spell without a Form row: untouched
do
	cast_(me, 230)
	local a = hit(m1, me, 1000)
	eq(a, -1000, "a spell with no row: untouched")
	cast_(me, 200)
end

-- SPLIT: the first hit is 35%, two more hits of 35% run as hits of the spell
do
	clearScheduled()
	calls = {}
	cast_(me, 200, 7)
	local a, pt = hit(m1, me, 1000, COMBAT_FIREDAMAGE)
	eq(a, -350, "SPLIT: the main hit is 35%")
	eq(pt, COMBAT_FIREDAMAGE, "SPLIT: the element stays")
	eq(#calls, 0, "nothing is dealt before the cast is over")
	runScheduled()
	eq(#calls, 2, "SPLIT: two extra hits at the end of the cast")
	for _, c in ipairs(calls) do
		eq(c.amount, -350, "SPLIT: 35% each")
		eq(c.origin, ORIGIN_SPELL, "an extra hit is a hit of the spell")
		eq(c.ctx, 7 * 1000 + 200, "an extra hit runs inside the cast context of the spell")
		ok(c.keystones > 0, "the proc guard of the keystones is up")
		ok(c.formDepth > 0 and c.depth > 0, "the supports are told: a Form hit (formDepth)")
		ok(c.target ~= 11, "the extra hits go to the nearest other enemies")
	end
	eq(S.formDepth, 0, "the guards are down again")
	eq(ChaosKeystones.depth, 0, "the keystone guard is down again")
	eq(storages[1][7109990], 7 * 1000 + 200, "the cast context is restored")
end

-- a Form hit never starts a Form again (the guard)
do
	FE.depth = 1
	local a = hit(m1, me, 1000)
	eq(a, -1000, "a Form hit passes the Form event untouched")
	FE.depth = 0
	ChaosKeystones.depth = 1
	a = hit(m1, me, 1000)
	eq(a, -1000, "a proc inside the keystone guard passes untouched")
	ChaosKeystones.depth = 0
	S.depth = 1
	a = hit(m1, me, 1000)
	eq(a, -1000, "a supports proc passes untouched")
	S.depth = 0
	clearScheduled()
end

-- the hit factor is applied once for the first hit; a second hit of an area cast keeps its damage
do
	clearScheduled()
	calls = {}
	setPacked(me, 200, 10, 1, 0)
	cast_(me, 200, 8)
	local a1 = hit(m1, me, 1000)
	local a2 = hit(m2, me, 1000)
	eq(a1, -350, "first hit 35%")
	eq(a2, -1000, "second hit of the same cast: a main kind leaves it alone")
	runScheduled()
	clearScheduled()
end

-- Form I SHIFT: the element of the hit changes
do
	clearScheduled()
	calls = {}
	setPacked(me, 200, 10, 2, 0)
	cast_(me, 200, 9)
	local a, pt = hit(m1, me, 1000, COMBAT_FIREDAMAGE)
	eq(a, -1000, "SHIFT: the hit keeps its size")
	eq(pt, COMBAT_ICEDAMAGE, "SHIFT:ice: the hit is ice")
	runScheduled(0) -- the end of the cast: the status dot is scheduled
	ok(#calls == 0, "SHIFT: the status ticks later")
	local dots = 0
	for _, e in ipairs(scheduled) do
		if e.delay == 1000 then
			dots = dots + 1
		end
	end
	ok(dots >= 1, "SHIFT: a status is scheduled")
	clearScheduled()
	setPacked(me, 200, 10, 1, 0)
end

-- Form II TWIN and the cooldown
do
	clearScheduled()
	calls = {}
	setPacked(me, 200, 20, 1, 1)
	cast_(me, 200, 10)
	local a = hit(m1, me, 1000)
	near(a, -262, 1, "SPLIT and TWIN: 35% x 75%")
	runScheduled(0) -- the end of the cast
	ok(#calls >= 2, "the split hits are dealt")
	local fn = ChaosSpellEvents.handlers.cooldown[#ChaosSpellEvents.handlers.cooldown].fn
	eq(fn(me, "Bolt", 200, 1, true, "spell", 7000), 7400, "TWIN: the cooldown starts after the second cast")
	eq(fn(me, "Bolt", 200, 1, true, "group", 2000), 2000, "TWIN: the group cooldown is not touched")
	local before = #calls
	runScheduled()
	ok(#calls > before, "TWIN: the second cast lands later")
	clearScheduled()
	setPacked(me, 200, 10, 1, 0)
end

-- ASCEND:holy and the mana of SIPHON are checked on the model; here: the weakest element on resistances
do
	clearScheduled()
	calls = {}
	setPacked(me, 200, 20, 1, 2)
	m1.elements = {[COMBAT_FIREDAMAGE] = 50}
	cast_(me, 200, 11)
	local a, pt = hit(m1, me, 1000, COMBAT_FIREDAMAGE)
	eq(pt, COMBAT_HOLYDAMAGE, "ASCEND:holy overrides SHIFT: the later conversion wins")
	runScheduled()
	clearScheduled()
	m1.elements = nil
	setPacked(me, 200, 10, 1, 0)
end

-- REND on spell 201: the hit is 70% and a damage over time is scheduled
do
	clearScheduled()
	calls = {}
	setPacked(me, 201, 10, 1, 0)
	cast_(me, 201, 12)
	local a = hit(m1, me, 1000, COMBAT_ICEDAMAGE)
	eq(a, -700, "REND: 70% now")
	runScheduled(0)
	local dot
	for _, e in ipairs(scheduled) do
		if e.delay == 1000 then
			dot = e
		end
	end
	ok(dot, "REND: the damage over time is scheduled")
	for i = 1, 4 do
		runScheduled()
	end
	local n = 0
	for _, c in ipairs(calls) do
		if c.target == 11 then n = n + 1 end
	end
	eq(n, 4, "REND: four ticks")
	eq(calls[1].amount, -100, "REND: 10% of the hit a tick")
	clearScheduled()
	calls = {}
end

-- CHAIN on spell 201: the jumps are hits of the spell on the nearest other enemies
do
	clearScheduled()
	calls = {}
	setPacked(me, 201, 10, 2, 0)
	cast_(me, 201, 13)
	local a = hit(m1, me, 1000, COMBAT_ICEDAMAGE)
	eq(a, -950, "CHAIN: the main hit is 95%")
	runScheduled()
	eq(#calls, 2, "CHAIN: two jumps")
	eq(calls[1].amount, -70, "CHAIN: 7%")
	ok(calls[1].target ~= 11 and calls[2].target ~= 11 and calls[1].target ~= calls[2].target, "CHAIN: two other enemies")
	clearScheduled()
	calls = {}
	setPacked(me, 201, 10, 1, 0)
end

-- SIPHON (Form II): a share of the damage back as health and mana, at most 5% / 3% of the maxima per cast
do
	clearScheduled()
	calls = {}
	setPacked(me, 201, 20, 1, 1)
	me.health = 5000
	cast_(me, 201, 14)
	hit(m1, me, 100000, COMBAT_ICEDAMAGE)
	runScheduled(0)
	eq(me.health, 5000 + 500, "SIPHON: the heal is capped at 5% of max health")
	eq(me.manaAdded, 300, "SIPHON: mana capped at 3% of max mana")
	clearScheduled()
	calls = {}
	setPacked(me, 201, 10, 1, 0)
end

-- PvP: the numbers count at half and only players are targets
do
	clearScheduled()
	calls = {}
	local foe = newCreature(21, "player", 103, 100)
	local foe2 = newCreature(22, "player", 104, 100)
	setPacked(me, 200, 10, 1, 0)
	cast_(me, 200, 15)
	local a = hit(foe, me, 1000)
	near(a, -675, 1, "PvP: SPLIT's main factor moves half the way (35% -> 67.5%)")
	runScheduled()
	local hitPlayers = 0
	for _, c in ipairs(calls) do
		ok(c.target == 22 or c.target == 21, "PvP: the extra hits go to players only")
		hitPlayers = hitPlayers + 1
	end
	eq(#calls, 2, "PvP: the shape works: two extra hits")
	near(-calls[1].amount, 175, 1, "PvP: an extra hit counts at half (35% -> 17.5%)")
	foe.party, foe2.party = nil, nil
	world.creatures[21], world.creatures[22] = nil, nil
	clearScheduled()
	calls = {}
end

-- a monster's summon or a player's summon is no target
do
	clearScheduled()
	calls = {}
	local pet = newCreature(31, "monster", 102, 100)
	pet.master = me
	cast_(me, 200, 16)
	hit(m1, me, 1000)
	runScheduled()
	for _, c in ipairs(calls) do
		ok(c.target ~= 31, "a player's summon is never hit by a Form")
	end
	world.creatures[31] = nil
	clearScheduled()
	calls = {}
end

-- a heal Form: RIPPLE and the heal event
do
	clearScheduled()
	calls = {}
	local ally = newCreature(41, "player", 101, 100, 4000, 10000)
	local ally2 = newCreature(42, "player", 102, 100, 4000, 10000)
	me.party = {}
	ally.party, ally2.party = me.party, me.party
	setPacked(me, 208, 10, 1, 0)
	cast_(me, 208, 17)
	ally.health = 4000
	local a = hitEv.onHealthChange(ally, me, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL, false)
	eq(a, 950, "RIPPLE: the main heal is 95%")
	runScheduled()
	local heals = 0
	for _, c in ipairs(calls) do
		if c.ctype == COMBAT_HEALING then heals = heals + 1 end
	end
	ok(heals >= 1, "RIPPLE: heals jump to allies")
	for _, c in ipairs(calls) do
		ok(c.target ~= 41, "RIPPLE: not back on the target")
	end
	-- a damage hit with a heal spell's context is ignored, a heal with a damage spell's context too
	local dmg = hit(m1, me, 1000)
	eq(dmg, -1000, "a damage hit under a heal spell's context is untouched")
	clearScheduled()
	calls = {}
	world.creatures[41], world.creatures[42] = nil, nil
	me.party = nil
end

-- Ward: an overheal becomes a shield that absorbs damage
do
	clearScheduled()
	calls = {}
	local ally = newCreature(43, "player", 101, 100, 9500, 10000)
	setPacked(me, 208, 10, 2, 0)
	cast_(me, 208, 18)
	hitEv.onHealthChange(ally, me, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL, false)
	runScheduled()
	local sh = FE.shields[43]
	ok(sh and sh.amount == 500, "WARD: the 500 that did not fit became a shield")
	local shieldEv = registered.events.ChaosSpellFormsShield
	local d = shieldEv.onHealthChange(ally, nil, -300, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, false)
	eq(d, 0, "the shield takes the hit")
	eq(sh.amount, 200, "the shield shrinks")
	d = shieldEv.onHealthChange(ally, nil, -300, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE, false)
	eq(d, -100, "the rest goes through")
	world.creatures[43] = nil
	clearScheduled()
	calls = {}
	setPacked(me, 208, 10, 1, 0)
end

-- pick, change, price on the wire
do
	local k = C.storage
	local p = newCreature(51, "player", 110, 110)
	p.level = 1000
	setPacked(p, 200, 9, 0, 0)
	local r = FE.pick(p, 200, 1, 1)
	ok(not r.ok and r.why == "rank", "a pick under the rank is refused")
	setPacked(p, 200, 10, 0, 0)
	r = FE.pick(p, 200, 1, 1)
	ok(r.ok and r.price == 0 and r.why == "first", "the first pick is free")
	eq(select(2, P.unpack(p:getStorageValue(k.rankBase + 200))), 1, "the pick is in the packed state")
	eq(select(1, P.unpack(p:getStorageValue(k.rankBase + 200))), 10, "the rank stays")
	-- change inside the window: free
	r = FE.pick(p, 200, 1, 2)
	ok(r.ok and r.free and r.why == "window", "a change right after the pick is free")
	-- an hour later: paid, bank first
	p:setStorageValue(k.lastPickAt, os.time() - 3600)
	p.bank, p.coins = 100000, 60000
	r = FE.pick(p, 200, 1, 1)
	ok(r.ok and r.price == 150000, "a change costs 150 x 1000 gold")
	eq(p.bank, 0, "the bank is paid first")
	eq(p.coins, 10000, "then the coins")
	eq(p:getStorageValue(k.formChanges), 1, "the change is counted")
	-- not enough gold: nothing is taken, nothing changes
	p:setStorageValue(k.lastPickAt, os.time() - 3600)
	p.bank, p.coins = 1000, 1000
	local before = select(2, P.unpack(p:getStorageValue(k.rankBase + 200)))
	r = FE.pick(p, 200, 1, 2)
	ok(not r.ok and r.why == "gold", "short of gold: refused")
	eq(p.bank + p.coins, 2000, "nothing taken")
	eq(select(2, P.unpack(p:getStorageValue(k.rankBase + 200))), before, "the pick stays")
	-- Form II needs rank 20 and the opcode answers
	r = FE.pick(p, 200, 2, 1)
	ok(not r.ok and r.why == "rank", "Form II needs rank 20")
	setPacked(p, 200, 20, 1, 0)
	r = FE.pick(p, 200, 2, 2)
	ok(r.ok and r.why == "first", "the first Form II is free")
	-- the switch off: the pick is refused (nothing changes in play)
	C.enabled = false
	r = FE.pick(p, 200, 1, 2)
	ok(not r.ok and r.why == "off", "off: no pick")
	C.enabled = true
	-- unknown spell, bad input
	ok(not FE.pick(p, 999, 1, 1).ok, "an unknown spell")
	ok(not FE.pick(p, 200, 1, 7).ok, "a bad pick")
	-- the message
	sent = {}
	ok(FE.receive(p, {action = "pick", data = {spell = 200, tier = 1, pick = 1}}), "the message is answered")
	eq(sent[1].action, "pick", "the answer is a pick message")
	ok(sent[1].data.ok ~= nil, "the answer carries the result")
	ok(not FE.receive(p, {action = "open"}), "other actions are not the Forms'")
	local list = FE.picksOf(p)
	eq(list[1][1], 200, "the picks list names the spell")
end

-- O468: a Form hit reads the level and magic level through the hit it is a share of: the same cast of a stronger caster gives bigger extras
do
	clearScheduled()
	calls = {}
	setPacked(me, 200, 10, 1, 0)
	cast_(me, 200, 20)
	hit(m1, me, 1000)
	runScheduled()
	local weak = calls[1] and -calls[1].amount or 0
	clearScheduled()
	calls = {}
	cast_(me, 200, 21)
	hit(m1, me, 3000) -- the hit of a caster with a higher level and magic level is bigger: the Form is a share of it
	runScheduled()
	local strong = calls[1] and -calls[1].amount or 0
	eq(strong, weak * 3, "a Form hit is a share of the spell's hit: it grows with level and magic level")
	clearScheduled()
	calls = {}
end

print(string.format("spell_forms_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/unique_passives_test.lua (and lua5.3; CI runs both)
-- The unique item passives (O278): data/scripts/chaos/unique_passives_core.lua (rules), _config.lua (numbers), _text.lua
-- (tooltip lines) and the engine glue unique_passives.lua against a mocked engine. Per family: the trigger, the cap or
-- cooldown, the trade-off and that a proc starts no other passive. Over all: every unique has a passive, the item text
-- matches the config, every class line has enough passives in every level band, the pt-BR line carries the same numbers.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end
local function near(a, b, m)
	checks = checks + 1
	if math.abs(a - b) > 1e-6 then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

dofile("data/scripts/chaos/unique_passives_config.lua")
dofile("data/scripts/chaos/unique_passives_text.lua")
dofile("data/scripts/chaos/unique_passives_core.lua")
local C, CFG = ChaosUniquePassivesCore, ChaosUniquePassivesConfig

-- a test entry of a family with the family's defaults and some overrides
local seq = 900000
local function mk(family, over, lines)
	seq = seq + 1
	local raw = {lv = 100, name = "T" .. seq, family = family, lines = lines or "WRMTKNP"}
	for k, v in pairs(over or {}) do
		raw[k] = v
	end
	CFG.passives[seq] = raw
	return C.entry(CFG, seq)
end
local function ctxOf(over)
	local c = {now = 10000, origin = "melee", elem = "physical", crit = false, proc = false, dot = false, targetId = 1,
		targetPlayer = false, targetPct = 100, selfPct = 100, manaPct = 50, others = 0, damage = 100, maxHealth = 1000,
		health = 1000, maxMana = 500, mana = 250, level = 100, stats = {maxMana = 500, level = 100}}
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

-- ---------------------------------------------------------------- the data: every unique has a passive
local xml = io.open("data/items/chaos_items.xml", "rb"):read("*a")
local items, count = {}, 0
for id, body in xml:gmatch('<item id="(%d+)"[^>]*>(.-)</item>') do
	local lv = body:match('key="description" value="[^"]*%(Requires level (%d+)')
	items[tonumber(id)] = tonumber(lv)
	count = count + 1
end
ok(count >= 183, "the unique list was read")
local seen = 0
for id in pairs(CFG.passives) do
	if id < 900000 then
		seen = seen + 1
	end
end
-- (test entries are added below this point; count the real ones first)
local real = {}
for id, raw in pairs(CFG.passives) do
	real[id] = raw
end
for id, lv in pairs(items) do
	local raw = real[id]
	ok(raw, "unique " .. id .. " has a passive")
	eq(raw.lv, lv, "the level of unique " .. id)
end
for id in pairs(real) do
	ok(items[id] ~= nil, "passive " .. id .. " belongs to a unique")
end
local names = {}
for id, raw in pairs(real) do
	ok(ChaosUniquePassivesText.family[raw.family], "family " .. tostring(raw.family) .. " has a text")
	ok(CFG.families[raw.family], "family " .. tostring(raw.family) .. " has defaults")
	ok(raw.name and raw.name ~= "", "passive " .. id .. " has a name")
	ok(not names[raw.name], "name " .. raw.name .. " is used once")
	names[raw.name] = true
	ok(raw.lines == "ALL" or raw.lines:match("^[WRMTKNP]+$"), "lines of " .. id)
end

-- the generated item texts carry the line of the config (dofile the specs)
for i, n in ipairs({"ATTACK", "DEFENSE", "EXTRADEFENSE", "ARMOR", "HITCHANCE", "SHOOTRANGE"}) do
	_G["ITEM_ATTRIBUTE_" .. n] = i
end
dofile("data/lib/chaos_unique_specs.lua")
for id in pairs(real) do
	local e = C.entry(CFG, id)
	local en, pt = C.text(CFG, e, "en"), C.text(CFG, e, "pt-BR")
	ok(en ~= "" and pt ~= "", "text of " .. id)
	ok(ChaosUniqueSpecs[id].description:find(en, 1, true), "the description of " .. id .. " carries its passive line (run tools/gen_unique_specs.py)")
	local a, b = table.concat(C.numbers(en), ","), table.concat(C.numbers(pt), ",")
	eq(a, b, "the numbers of the pt-BR line of " .. id .. " are in the English order")
	ok(#en < 330, "the line of " .. id .. " is short enough for the tooltip: " .. #en)
	ok(pt ~= en, "the pt-BR line of " .. id .. " is translated")
end

-- coverage: every class line has enough passives in every level band
local BANDS = {{1, 100}, {101, 400}, {401, 900}, {901, 1600}, {1601, 99999}}
for _, line in ipairs(CFG.lineOrder) do
	local letter = C.letterOf(CFG, line)
	for _, band in ipairs(BANDS) do
		local n = 0
		for id, raw in pairs(real) do
			local e = C.entry(CFG, id)
			if e.lv >= band[1] and e.lv <= band[2] and e.lines:find(letter, 1, true) then
				n = n + 1
			end
		end
		ok(n >= 3, line .. " has " .. n .. " passives in levels " .. band[1] .. "-" .. band[2])
	end
end

-- ---------------------------------------------------------------- active sets
do
	local a = mk("lowlife", {lv = 50}, "W")
	local b = mk("lowlife", {lv = 90}, "WR")
	local c = mk("focus", {lv = 10}, "R")
	local set = C.activeSet(CFG, {a.id, b.id, c.id}, "warrior")
	eq(#set, 1, "one family once, other lines asleep")
	eq(set[1].id, b.id, "the higher level wins its family")
	eq(#C.activeSet(CFG, {a.id, b.id, c.id}, "ranger"), 2, "the ranger has two")
	eq(#C.activeSet(CFG, {a.id, a.id}, "warrior"), 1, "the same item twice is one")
	local ids = {}
	for _, f in ipairs({"convert", "lowlife", "overflow", "opener", "focus", "statscale", "critrule", "crowd"}) do
		ids[#ids + 1] = mk(f).id
	end
	eq(#C.activeSet(CFG, ids, "mystic"), CFG.maxActive, "at most maxActive")
	eq(#C.activeSet(CFG, {a.id}, "nonsense"), 0, "an unknown line has none")
end

-- ---------------------------------------------------------------- damage you deal
do
	local S = C.newState()
	local e = mk("convert", {elem = "fire", share = 50, bonus = 20, other = 10})
	local act = {e}
	near(C.dealt(CFG, S, act, ctxOf()), 1, "a physical hit is unchanged (the converted part has its own plan)")
	near(C.convertPlan(act, ctxOf()).mult, 1.2, "the converted part deals more")
	near(C.dealt(CFG, S, act, ctxOf({elem = "ice"})), 0.9, "another element deals less")
	near(C.dealt(CFG, S, act, ctxOf({elem = "fire"})), 1, "the converted element is unchanged")
	eq(C.dealt(CFG, S, act, ctxOf({proc = true})), 1, "a proc gets no multiplier")
	eq(C.dealt(CFG, S, act, ctxOf({dot = true})), 1, "a condition tick gets no multiplier")
	local plan = C.convertPlan(act, ctxOf())
	near(plan.share, 0.5, "convert share")
	eq(C.convertPlan(act, ctxOf({proc = true})), nil, "a proc is not converted")
	eq(C.convertPlan(act, ctxOf({targetPlayer = true})), nil, "a player is not converted")
end
do
	local S = C.newState()
	local e = mk("lowlife", {at = 35, bonus = 40, malusAt = 70, malus = 15})
	near(C.dealt(CFG, S, {e}, ctxOf({selfPct = 20})), 1.4, "low life bonus")
	near(C.dealt(CFG, S, {e}, ctxOf({selfPct = 50})), 1, "between: neutral")
	near(C.dealt(CFG, S, {e}, ctxOf({selfPct = 90})), 0.85, "high life price")
end
do
	local S = C.newState()
	local e = mk("overflow", {at = 70, bonus = 35, malusAt = 30, malus = 15})
	near(C.dealt(CFG, S, {e}, ctxOf({manaPct = 80})), 1.35, "full mana bonus")
	near(C.dealt(CFG, S, {e}, ctxOf({manaPct = 20})), 0.85, "empty mana price")
end
do
	local S = C.newState()
	local e = mk("opener", {side = "above", at = 90, bonus = 60, malusAt = 25, malus = 10})
	near(C.dealt(CFG, S, {e}, ctxOf({targetPct = 100})), 1.6, "opener bonus")
	near(C.dealt(CFG, S, {e}, ctxOf({targetPct = 10})), 0.9, "opener price")
	local f = mk("opener", {side = "below", at = 30, bonus = 50, malusAt = 90, malus = 10})
	near(C.dealt(CFG, S, {f}, ctxOf({targetPct = 20})), 1.5, "finisher bonus")
	near(C.dealt(CFG, S, {f}, ctxOf({targetPct = 95})), 0.9, "finisher price")
end
do
	local S = C.newState()
	local e = mk("focus", {perStack = 10, max = 3, resetMs = 3000, first = 20})
	near(C.dealt(CFG, S, {e}, ctxOf({now = 1000})), 0.8, "the first hit on a target is weaker")
	near(C.dealt(CFG, S, {e}, ctxOf({now = 1500})), 1.1, "second hit")
	C.dealt(CFG, S, {e}, ctxOf({now = 2000}))
	C.dealt(CFG, S, {e}, ctxOf({now = 2500}))
	near(C.dealt(CFG, S, {e}, ctxOf({now = 3000})), 1.3, "capped at max stacks")
	near(C.dealt(CFG, S, {e}, ctxOf({now = 3500, targetId = 2})), 0.8, "a new target starts over")
	near(C.dealt(CFG, S, {e}, ctxOf({now = 9000, targetId = 2})), 0.8, "the chain resets after resetMs")
end
do
	local S = C.newState()
	local e = mk("statscale", {stat = "maxMana", from = 0, per = 100, bonusPer = 1, cap = 40, origin = "any"})
	near(C.dealt(CFG, S, {e}, ctxOf({stats = {maxMana = 1500}})), 1.15, "per 100 points")
	near(C.dealt(CFG, S, {e}, ctxOf({stats = {maxMana = 99999}})), 1.4, "capped")
	local r = mk("statscale", {stat = "speed", from = 200, per = 10, bonusPer = 1, cap = 20, origin = "ranged"})
	near(C.dealt(CFG, S, {r}, ctxOf({stats = {speed = 300}})), 1, "another origin gets nothing")
	near(C.dealt(CFG, S, {r}, ctxOf({stats = {speed = 300}, origin = "ranged"})), 1.1, "above `from`")
end
do
	local S = C.newState()
	local e = mk("critrule", {crit = 45, plain = 10, heal = 5, healIcdMs = 1500})
	near(C.dealt(CFG, S, {e}, ctxOf({crit = true})), 1.45, "critical bonus")
	near(C.dealt(CFG, S, {e}, ctxOf()), 0.9, "plain price")
	local h = C.critHeal(CFG, S, {e}, ctxOf({crit = true, damage = 400, now = 5000}))
	eq(h, 20, "a critical hit heals its share")
	eq(C.critHeal(CFG, S, {e}, ctxOf({crit = true, damage = 400, now = 5500})), 0, "cooldown")
	eq(C.critHeal(CFG, S, {e}, ctxOf({crit = true, damage = 400, now = 7000})), 20, "ready again")
	eq(C.critHeal(CFG, S, {e}, ctxOf({crit = true, damage = 400, now = 9000, proc = true})), 0, "no heal from a proc")
	local big = C.critHeal(CFG, S, {e}, ctxOf({crit = true, damage = 1e7, now = 99000}))
	eq(big, math.floor(1000 * CFG.healCapPct / 100), "the heal is capped by the maximum health")
end
do
	local S = C.newState()
	local e = mk("crowd", {mode = "pack", radius = 3, per = 6, max = 5, alone = 15})
	near(C.dealt(CFG, S, {e}, ctxOf({others = 0})), 0.85, "alone price")
	near(C.dealt(CFG, S, {e}, ctxOf({others = 2})), 1.12, "per monster")
	near(C.dealt(CFG, S, {e}, ctxOf({others = 40})), 1.3, "capped at max")
	local d = mk("crowd", {mode = "duel", bonus = 35, malus = 20, many = 3})
	near(C.dealt(CFG, S, {d}, ctxOf({others = 0})), 1.35, "duel bonus")
	near(C.dealt(CFG, S, {d}, ctxOf({others = 1})), 1, "duel neutral")
	near(C.dealt(CFG, S, {d}, ctxOf({others = 3})), 0.8, "duel price")
end
do
	local S = C.newState()
	local e = mk("mark", {max = 2, bonus = 30, ms = 6000, unmarked = 12})
	near(C.dealt(CFG, S, {e}, ctxOf({targetId = 1})), 0.88, "unmarked price")
	C.landed(CFG, S, {e}, ctxOf({targetId = 1}))
	near(C.dealt(CFG, S, {e}, ctxOf({targetId = 1, now = 12000})), 1.3, "marked bonus")
	C.landed(CFG, S, {e}, ctxOf({targetId = 2}))
	C.landed(CFG, S, {e}, ctxOf({targetId = 3}))
	near(C.dealt(CFG, S, {e}, ctxOf({targetId = 3})), 0.88, "only max marks at once")
	near(C.dealt(CFG, S, {e}, ctxOf({targetId = 1, now = 17500})), 0.88, "marks expire")
	C.landed(CFG, S, {e}, ctxOf({targetId = 4, proc = true}))
	near(C.dealt(CFG, S, {e}, ctxOf({targetId = 4, now = 17600})), 0.88, "a proc marks nothing")
end
do
	local S = C.newState()
	local e = mk("stacks", {trigger = "kill", perStack = 6, max = 5, windowMs = 6000, takenPerStack = 4})
	for i = 1, 9 do
		C.kill(CFG, S, {e}, ctxOf({now = 1000 + i}))
	end
	near(C.dealt(CFG, S, {e}, ctxOf({now = 2000})), 1.3, "stacks capped at max")
	local inc = C.incoming(CFG, S, {e}, ctxOf({now = 2000, dmg = 100, fromMonster = true}))
	eq(inc.dmg, 120, "each stack adds damage taken")
	near(C.dealt(CFG, S, {e}, ctxOf({now = 20000})), 1, "stacks expire")
	local c = mk("stacks", {trigger = "crit", perStack = 5, max = 2, windowMs = 5000, takenPerStack = 0})
	local S2 = C.newState()
	C.landed(CFG, S2, {c}, ctxOf({crit = true}))
	C.landed(CFG, S2, {c}, ctxOf({crit = true}))
	C.landed(CFG, S2, {c}, ctxOf({crit = true}))
	near(C.dealt(CFG, S2, {c}, ctxOf()), 1.1, "crit stacks")
	C.kill(CFG, S2, {c}, ctxOf())
	near(C.dealt(CFG, S2, {c}, ctxOf()), 1.1, "a kill is no crit stack")
end
do
	-- the clamps: every multiplier at once
	local S = C.newState()
	local act = {}
	for _, spec in ipairs({{"convert", {bonus = 100, share = 100}}, {"lowlife", {bonus = 100}}, {"opener", {bonus = 100}},
			{"critrule", {crit = 100}}, {"statscale", {cap = 100, per = 1}}}) do
		act[#act + 1] = mk(spec[1], spec[2])
	end
	local m = C.dealt(CFG, S, act, ctxOf({selfPct = 1, crit = true, stats = {maxMana = 99999}}))
	eq(m, CFG.dealtCap, "the damage dealt is capped")
	local low = {mk("critrule", {crit = 0, plain = 90}), mk("convert", {other = 90, elem = "fire"})}
	eq(C.dealt(CFG, S, low, ctxOf({elem = "ice"})), CFG.dealtFloor, "the damage dealt has a floor")
	near(C.dealt(CFG, S, act, ctxOf({selfPct = 1, crit = true, stats = {maxMana = 99999}, targetPlayer = true})),
		1 + (CFG.dealtCap - 1) * CFG.pvpScale, "a player takes the capped bonus scaled by pvpScale")
	ok(C.dealt(CFG, S, act, ctxOf({selfPct = 1, crit = true, stats = {maxMana = 99999}, targetPlayer = true}))
		< C.dealt(CFG, S, act, ctxOf({selfPct = 1, crit = true, stats = {maxMana = 99999}})), "less against players")
end

-- ---------------------------------------------------------------- extra hits
do
	local S = C.newState()
	local e = mk("extra", {origin = "ranged", pct = 50, targets = 2, radius = 3, cost = "health", costPct = 1, minHealth = 35, icdMs = 600})
	local p = C.extraPlan(CFG, S, {e}, ctxOf({origin = "ranged", damage = 200, now = 1000}))
	eq(p.damage, 100, "a share of the hit")
	eq(p.cost, 10, "the price in health")
	eq(C.extraPlan(CFG, S, {e}, ctxOf({origin = "ranged", damage = 200, now = 1300})), nil, "cooldown")
	ok(C.extraPlan(CFG, S, {e}, ctxOf({origin = "ranged", damage = 200, now = 1700})), "ready again")
	eq(C.extraPlan(CFG, S, {e}, ctxOf({origin = "melee", damage = 200, now = 9000})), nil, "another origin")
	eq(C.extraPlan(CFG, S, {e}, ctxOf({origin = "ranged", damage = 200, now = 9000, proc = true})), nil, "a proc starts none")
	eq(C.extraPlan(CFG, S, {e}, ctxOf({origin = "ranged", damage = 200, now = 9000, targetPlayer = true})), nil, "never at a player")
	eq(C.extraPlan(CFG, S, {e}, ctxOf({origin = "ranged", damage = 200, now = 20000, health = 360})), nil, "the price never takes it under minHealth")
	local m = mk("extra", {origin = "any", cost = "mana", costPct = 2, icdMs = 100})
	eq(C.extraPlan(CFG, C.newState(), {m}, ctxOf({damage = 100, mana = 5})), nil, "no mana, no hit")
	eq(C.extraPlan(CFG, C.newState(), {m}, ctxOf({damage = 100, mana = 400})).cost, 10, "a mana price")
end
do
	local S = C.newState()
	local e = mk("nova", {on = "kill", elem = "fire", base = 60, perLevel = 1, radius = 2, targets = 5, icdMs = 3000, selfCost = 1, minHealth = 35})
	local p = C.novaPlan(CFG, S, {e}, "kill", ctxOf({now = 1000, level = 40}))
	eq(p.damage, 100, "base plus level")
	eq(p.cost, 10, "price")
	eq(C.novaPlan(CFG, S, {e}, "kill", ctxOf({now = 2000})), nil, "cooldown")
	eq(C.novaPlan(CFG, S, {e}, "crit", ctxOf({now = 9000})), nil, "another trigger")
	eq(C.novaPlan(CFG, S, {e}, "kill", ctxOf({now = 9000, health = 350})), nil, "never under minHealth")
	local h = mk("nova", {on = "hurt", minHit = 5, icdMs = 1000, selfCost = 0})
	eq(C.novaPlan(CFG, C.newState(), {h}, "hurt", ctxOf({fromMonster = true, dmg = 10})), nil, "a small hit is no trigger")
	ok(C.novaPlan(CFG, C.newState(), {h}, "hurt", ctxOf({fromMonster = true, dmg = 60})), "a hard hit is")
	eq(C.novaPlan(CFG, C.newState(), {h}, "hurt", ctxOf({fromMonster = false, dmg = 60})), nil, "not from a player or trap")
end
do
	local S = C.newState()
	local e = mk("riposte", {elem = "physical", pct = 50, minHit = 3, icdMs = 2500, capBase = 60, capPerLevel = 1})
	eq(C.ripostePlan(CFG, S, {e}, ctxOf({fromMonster = true, dmg = 20, now = 1000})), nil, "too small")
	eq(C.ripostePlan(CFG, S, {e}, ctxOf({fromMonster = true, dmg = 100, now = 1000})).damage, 50, "a share")
	eq(C.ripostePlan(CFG, S, {e}, ctxOf({fromMonster = true, dmg = 100, now = 2000})), nil, "cooldown")
	eq(C.ripostePlan(CFG, S, {e}, ctxOf({fromMonster = true, dmg = 90000, now = 9000, level = 40})).damage, 100, "capped by level")
end
do
	local S = C.newState()
	local e = mk("spread", {elem = "poison", targets = 3, radius = 2, share = 50, ticks = 4, tickMs = 1000, recentMs = 4000, dealtLess = 12})
	C.noteAfflict(CFG, S, {e}, 7, 80, 1000)
	local plan = C.spreadPlan(CFG, S, {e}, S.afflict[7], 3000)
	eq(plan.damage, 40, "a share of the last tick")
	eq(plan.ticks, 4, "ticks")
	eq(C.spreadPlan(CFG, S, {e}, S.afflict[7], 9000), nil, "an old affliction does not spread")
	eq(C.spreadPlan(CFG, S, {e}, nil, 3000), nil, "none")
	for i = 1, 400 do
		C.noteAfflict(CFG, S, {e}, 1000 + i, 5, 1000)
	end
	local n = 0
	for _ in pairs(S.afflict) do
		n = n + 1
	end
	ok(n <= CFG.afflictKeep + 1, "the afflicted monsters are bounded: " .. n)
	near(C.dealt(CFG, S, {e}, ctxOf()), 0.88, "the price on direct hits")
end

-- ---------------------------------------------------------------- damage you take
do
	local S = C.newState()
	local e = mk("hitcap", {cap = 30, healLess = 25})
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 900, fromMonster = true})).dmg, 300, "a hit is cut")
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 200, fromMonster = true})).dmg, 200, "a small hit passes")
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 900, fromMonster = false})).dmg, 900, "only monster hits")
	near(C.healMult(S, {e}, 1), 0.75, "the healing price")
	near(C.healMult(S, {}, 1), 1, "no price without it")
end
do
	local S = C.newState()
	local e = mk("immunity", {kind = "fire", more = 15})
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 50, elem = "fire", dot = true})).dmg, 0, "immune to burning")
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 100, elem = "fire"})).dmg, 115, "direct fire hurts more")
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 100, elem = "ice"})).dmg, 100, "others unchanged")
	local b = mk("immunity", {kind = "bleed", more = 10})
	eq(C.incoming(CFG, S, {b}, ctxOf({now = 1, dmg = 40, elem = "physical", dot = true})).dmg, 0, "immune to bleeding")
	eq(C.incoming(CFG, S, {b}, ctxOf({now = 1, dmg = 100, elem = "physical"})).dmg, 110, "direct physical price")
	local p = mk("immunity", {kind = "poison", more = 10})
	eq(C.incoming(CFG, S, {p}, ctxOf({now = 1, dmg = 40, elem = "earth", dot = true})).dmg, 0, "poison is earth")
end
do
	local S = C.newState()
	local e = mk("panic", {below = 30, reduce = 45, ms = 5000, icdMs = 60000})
	local r = C.incoming(CFG, S, {e}, ctxOf({now = 1000, dmg = 600, fromMonster = true, health = 800}))
	ok(r.panic, "a hit that leaves under 30% starts the guard")
	eq(r.dmg, 600, "that hit lands in full")
	eq(C.healMult(S, {e}, 2000), 0, "healing is blocked meanwhile")
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 2000, dmg = 100, fromMonster = true, health = 200})).dmg, 55, "less damage meanwhile")
	near(C.healMult(S, {e}, 7000), 1, "the guard ends")
	local r2 = C.incoming(CFG, S, {e}, ctxOf({now = 8000, dmg = 150, fromMonster = true, health = 200}))
	ok(not r2.panic, "once per icd")
	eq(C.incoming(CFG, C.newState(), {e}, ctxOf({now = 1, dmg = 5000, fromMonster = true, health = 100})).panic, false, "no guard for a lethal hit")
end
do
	local S = C.newState()
	local e = mk("manashield", {share = 30, reserve = 5, dealtLess = 10})
	local r = C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 100, fromMonster = true, mana = 400, maxMana = 500}))
	eq(r.mana, 30, "a share is paid from mana")
	eq(r.dmg, 70, "the rest from health")
	local low = C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 100, fromMonster = true, mana = 30, maxMana = 500}))
	eq(low.mana, 5, "never under the reserve")
	eq(low.dmg, 95, "the rest is health")
	eq(C.incoming(CFG, S, {e}, ctxOf({now = 1, dmg = 100, fromMonster = true, mana = 10, maxMana = 500})).mana, 0, "no mana, no shield")
	near(C.dealt(CFG, S, {e}, ctxOf()), 0.9, "the price on hits")
end
do
	local S = C.newState()
	local e = mk("ward", {onHit = 10, onKill = 5, cap = 20, decayAfterMs = 6000, decayPct = 25, reflect = 50, healLess = 30})
	local g = C.wardGain(CFG, S, {e}, "hit", 100000, 1000, 1000)
	eq(g, 1000 * CFG.wardHitMax / 100, "one hit adds at most wardHitMax")
	for i = 1, 20 do
		C.wardGain(CFG, S, {e}, "hit", 100000, 1000, 1000 + i)
	end
	eq(S.ward, 200, "the ward is capped")
	eq(C.wardGain(CFG, S, {e}, "kill", 0, 1000, 2000), 0, "full: no more")
	local r = C.incoming(CFG, S, {e}, ctxOf({now = 2000, dmg = 150, fromMonster = true}))
	eq(r.dmg, 0, "the ward absorbs")
	eq(r.absorbed, 150, "absorbed")
	eq(r.reflect, 75, "a share goes back")
	eq(S.ward, 50, "ward left")
	local r2 = C.incoming(CFG, S, {e}, ctxOf({now = 2100, dmg = 150, fromMonster = false}))
	eq(r2.dmg, 100, "the rest is health")
	eq(r2.reflect, 0, "no reflect from a non monster")
	local S2 = C.newState()
	C.wardGain(CFG, S2, {e}, "kill", 0, 1000, 1000)
	eq(S2.ward, 50, "a kill gives its share")
	C.wardFade(CFG, S2, {e}, 1000, 2000)
	eq(S2.ward, 50, "no fade right after a gain")
	C.wardFade(CFG, S2, {e}, 1000, 8000)
	eq(S2.ward, 0, "it fades (25% of the cap a second, 50 left)")
	eq(C.wardGain(CFG, S2, {}, "hit", 100, 1000, 1000), 0, "no ward without the passive")
	C.wardFade(CFG, S2, {}, 1000, 9000)
	eq(S2.ward, 0, "no ward without the passive")
end
do
	-- the damage taken ceiling and floor
	local S = C.newState()
	local act = {mk("immunity", {kind = "fire", more = 90}), mk("stacks", {takenPerStack = 90, max = 5})}
	for i = 1, 5 do
		C.addStack(S, act[2], 1000 + i)
	end
	eq(C.incoming(CFG, S, act, ctxOf({now = 1100, dmg = 100, elem = "fire", fromMonster = true})).dmg, 150, "taken is capped at takenCeil")
end

-- ---------------------------------------------------------------- kills, feast, mend
do
	local S = C.newState()
	local e = mk("feast", {res = "health", onKill = 3, capPerSec = 5, healLess = 40})
	local o = C.kill(CFG, S, {e}, ctxOf({now = 1000}))
	eq(o.heal, math.floor(30 * 0.6), "a kill heals, with the price")
	local o2 = C.kill(CFG, S, {e}, ctxOf({now = 1100}))
	eq(o2.heal, math.floor(20 * 0.6), "capped per second")
	eq(C.kill(CFG, S, {e}, ctxOf({now = 1200})).heal, 0, "nothing more this second")
	ok(C.kill(CFG, S, {e}, ctxOf({now = 2500})).heal > 0, "a new second")
	local m = mk("feast", {res = "mana", onKill = 4, capPerSec = 10, healLess = 0})
	eq(C.kill(CFG, C.newState(), {m}, ctxOf()).mana, 20, "mana")
	eq(C.kill(CFG, C.newState(), {}, ctxOf()).heal, 0, "none without it")
end
do
	local S = C.newState()
	local e = mk("mend", {heal = 1.5, radius = 3, tickMs = 2000, fightMs = 5000, healLess = 30})
	eq(C.mendPlan(CFG, S, {e}, 1000), nil, "no mend before a fight")
	S.fightAt = 900
	near(C.mendPlan(CFG, S, {e}, 1000).pct, 1.5, "mend heals")
	eq(C.mendPlan(CFG, S, {e}, 2000), nil, "one per tick")
	ok(C.mendPlan(CFG, S, {e}, 3500), "next tick")
	eq(C.mendPlan(CFG, S, {e}, 20000), nil, "not after the fight")
	local big = mk("mend", {heal = 50, tickMs = 100})
	S.fightAt = 30000
	eq(C.mendPlan(CFG, S, {big}, 30100).pct, CFG.mendMaxPct, "a mend is capped")
end
do
	local a, b, c = C.minion({}), nil, nil
	eq(a, 1, "no pact")
	local e = mk("minionPact", {hit = 30, health = 40, own = 25}, "N")
	local hit, health, own = C.minion({e})
	near(hit, 1.3, "minion hit")
	near(health, 1.4, "minion health")
	near(own, 0.75, "own spells")
	near(C.dealt(CFG, C.newState(), {e}, ctxOf({origin = "spell"})), 0.75, "the own spell price")
	near(C.dealt(CFG, C.newState(), {e}, ctxOf({origin = "melee"})), 1, "melee is unchanged")
end

-- ---------------------------------------------------------------- text
do
	local e = mk("lowlife", {at = 33, bonus = 41, malusAt = 71, malus = 0}, "W")
	local en = C.text(CFG, e, "en")
	ok(en:find("33%%") and en:find("41%%"), "the line carries the numbers: " .. en)
	ok(not en:find("less"), "a price of 0 is not written")
	ok(en:find("For: Warrior"), "the lines are named")
	ok(C.text(CFG, e, "pt-BR"):find("Só para: Guerreiro"), "pt-BR lines")
	local all = mk("lowlife", {}, "ALL")
	ok(not C.text(CFG, all, "en"):find("For:"), "a passive of every line names none")
end

-- ---------------------------------------------------------------- the engine glue against a mock
do
	-- a small mock engine: one player wearing a unique, one monster; the events the glue registers are called by hand
	local events, globals = {}, {}
	CreatureEvent = function(name)
		local o = {name = name}
		o.register = function(self)
			events[name] = self
		end
		return setmetatable(o, {__newindex = function(t, k, v)
			rawset(t, k, v)
		end})
	end
	GlobalEvent = CreatureEvent
	EventCallback = {register = function() end}
	CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 2, 4, 5, 6
	CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING = 7, 8, 9
	COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_FIREDAMAGE, COMBAT_HEALING = 1, 2, 8, 128
	ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 1, 2, 3, 4
	CONST_ME_NONE, RETURNVALUE_NOERROR = 0, 0
	Chaos = {heal = function(c, n)
		c.health = math.min(c.maxHealth, c.health + n)
		return n
	end}
	local struck = {}
	doTargetCombatHealth = function(pid, tid, ctype, a, b, fx)
		struck[#struck + 1] = {tid = tid, ctype = ctype, amount = a, depth = ChaosKeystones and ChaosKeystones.depth}
	end
	local function creature(o)
		o.getId = function(s) return s.id end
		o.isPlayer = function(s) return s.player == true end
		o.isMonster = function(s) return not s.player end
		o.getMaster = function() return nil end
		o.getHealth = function(s) return s.health end
		o.getMaxHealth = function(s) return s.maxHealth end
		o.getMana = function(s) return s.mana or 0 end
		o.getMaxMana = function(s) return s.maxMana or 0 end
		o.getLevel = function(s) return s.level or 100 end
		o.getMagicLevel = function() return 50 end
		o.getPosition = function() return {x = 1, y = 1, z = 7, sendMagicEffect = function() end} end
		o.addHealth = function(s, a, b)
			s.health = math.max(0, s.health - (b or 0))
		end
		o.addMana = function(s, n) s.mana = (s.mana or 0) + n end
		o.getVocation = function() return {getId = function() return 1 end} end
		o.getSlotItem = function(s, slot) return s.items[slot] end
		o.registerEvent = function() end
		return o
	end
	local item = {getId = function() return 28693 end, getCustomAttribute = function(_, k) return k == "chaos_unique" and 1 or nil end}
	local player = creature({id = 1, player = true, health = 1000, maxHealth = 1000, mana = 300, maxMana = 300, items = {[CONST_SLOT_RIGHT] = item}})
	local mon = creature({id = 2, health = 5000, maxHealth = 5000, items = {}})
	Player = function(id) return id == 1 and player or nil end
	Creature = function(id) return id == 2 and mon or (id == 1 and player or nil) end
	Game = {getPlayers = function() return {player} end, getSpectators = function() return {} end}
	addEvent = function() end
	os.mtime = function() return 50000 end
	ChaosClasses = {lineKey = function() return "ranger" end}
	Chaos.registerOnce = function() return true end
	Chaos.eventKnown = function() return false end
	Chaos.lang = function() return "en" end
	ChaosKeystones = {depth = 0}
	-- load the glue
	dofile("data/scripts/chaos/unique_passives.lua")
	ok(events.ChaosUPDealt and events.ChaosUPTaken and events.ChaosUPKill and events.ChaosUPLogin, "the events are registered")
	eq(ChaosUniquePassives.refresh(player).key, "28693", "the worn unique is found")
	-- First Quarry (opener): +30% on a target at 90% or more
	local p1, t1, p2, t2 = events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, false)
	eq(p1, -130, "the opener bonus lands")
	-- a proc of another system (keystone depth) gets nothing
	ChaosKeystones.depth = 1
	eq((events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, false)), -100, "no bonus on a proc")
	ChaosKeystones.depth = 0
	-- a player that wears it as a plain (non unique) copy gets nothing
	item.getCustomAttribute = function() return nil end
	ChaosUniquePassives.refresh(player)
	eq((events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, false)), -100, "a plain copy has no passive")
	item.getCustomAttribute = function(_, k) return k == "chaos_unique" and 1 or nil end
	-- another class line: the passive sleeps
	ChaosClasses.lineKey = function() return "warrior" end
	ChaosUniquePassives.refresh(player)
	eq((events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, false)), -100, "asleep for another line")
	-- a player target (the monster event is never on players, but the guard holds): attacker must be a player
	eq((events.ChaosUPDealt.onHealthChange(mon, mon, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, false)), -100, "a monster attacker is ignored")
	-- the damage taken event passes through without a taken passive
	local a1 = events.ChaosUPTaken.onHealthChange(player, mon, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
	eq(a1, -50, "no taken passive: unchanged")
	-- convert: a share of a physical hit is struck as the element, as a proc (depth up, no passive on it)
	ChaosClasses.lineKey = function() return "ranger" end
	local function wear(family, over)
		local e = mk(family, over, "R")
		item.getId = function() return e.id end
		item.getCustomAttribute = function(_, k) return k == "chaos_unique" and 1 or nil end
		ChaosUniquePassives.refresh(player)
		return e
	end
	wear("convert", {elem = "fire", share = 50, bonus = 20, other = 10})
	local before = #struck
	local q = events.ChaosUPDealt.onHealthChange(mon, player, -200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, false)
	eq(#struck, before + 1, "the converted part is struck")
	eq(struck[#struck].ctype, COMBAT_FIREDAMAGE, "as fire")
	eq(struck[#struck].amount, -120, "with the bonus")
	ok(struck[#struck].depth > 0, "as a proc")
	eq(q, -100, "the rest stays physical")
	-- extra: a ranged hit sends a share at another monster; the price is paid in health, never below the floor
	local other = creature({id = 3, health = 900, maxHealth = 900, items = {}})
	Game.getSpectators = function() return {mon, other} end
	wear("extra", {origin = "ranged", pct = 50, targets = 1, radius = 3, cost = "health", costPct = 1, minHealth = 35, icdMs = 600})
	before = #struck
	events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED, false)
	eq(#struck, before + 1, "one extra hit")
	eq(struck[#struck].tid, 3, "at the other monster")
	eq(struck[#struck].amount, -50, "half of the hit")
	eq(player.health, 990, "the price in health")
	-- the same hit again right away: cooldown
	before = #struck
	events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED, false)
	eq(#struck, before, "the cooldown holds")
	-- the lethal blow gets no extra hit (the kill event handles that)
	mon.health = 50
	os.mtime = function() return 90000 end
	before = #struck
	events.ChaosUPDealt.onHealthChange(mon, player, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED, false)
	eq(#struck, before, "none on the lethal blow")
	mon.health = 5000
	-- hit cap on the player: a monster hit is cut
	wear("hitcap", {cap = 30, healLess = 25})
	local d = events.ChaosUPTaken.onHealthChange(player, mon, -900, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
	eq(d, -300, "the hit is cut to 30% of the maximum health")
	-- the healing price: a heal from the game is lowered, our own heal is not scaled twice
	local h = events.ChaosUPTaken.onHealthChange(player, nil, 100, COMBAT_HEALING, 0, COMBAT_HEALING, 0)
	eq(h, 75, "healing on the player is 25% lower")
	-- a kill with a monster that is a summon of somebody is ignored
	local summon = creature({id = 9, health = 10, maxHealth = 10, items = {}})
	summon.getMaster = function() return player end
	wear("feast", {res = "health", onKill = 3, capPerSec = 12, healLess = 0})
	player.health = 500
	events.ChaosUPKill.onKill(player, summon)
	eq(player.health, 500, "a summon's death feeds nothing")
	events.ChaosUPKill.onKill(player, mon)
	eq(player.health, 530, "a kill heals 3%")
	events.ChaosUPLogout.onLogout(player)
	eq(ChaosUniquePassives.states[1], nil, "logout clears the state")
end

print("unique_passives_test: " .. checks .. " checks ok")

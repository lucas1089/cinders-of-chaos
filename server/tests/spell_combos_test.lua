-- Run from the server/ folder: luajit tests/spell_combos_test.lua && lua5.3 tests/spell_combos_test.lua (CI runs both)
-- O686 phase 6: spell combos. Part A: spell_combos_core.lua and spell_combos_config.lua (every row fires, the window, the limits, the
-- element, the band 10..20%, the model numbers, the pt-BR names). Part B: spell_combos.lua with the real ChaosPassiveDealt of
-- passivetree_effects.lua on a mocked engine (the bonus on the hit of the second spell, PvP off, switch off, the Form conversion, the
-- heal combo, the credit stays with the second spell, the client message). Phase 6b: part A also holds the riders' config, counted gain
-- and marks (core), the combo masteries; part C runs every rider and the masteries on the mocked engine.

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

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/spell_combos_core.lua")
local C = ChaosSpellCombosCore
local cfg = dofile("data/scripts/chaos/spell_combos_config.lua")

-- ---------------------------------------------------------------- A1. the config
eq(#C.check(cfg), 0, "the config is sound: " .. table.concat(C.check(cfg), "; "))
eq(#cfg.rows, 13, "13 rows: 6 reactions, 6 signature combos, 1 heal combo")
local kinds = {reaction = 0, class = 0, heal = 0}
local names, ids = {}, {}
for _, r in ipairs(cfg.rows) do
	kinds[r.kind] = kinds[r.kind] + 1
	ok(r.bonus >= 0.10 - 1e-9 and r.bonus <= 0.20 + 1e-9, r.id .. ": the bonus is +10% to +20% (owner 2026-11-20)")
	ok(not names[r.name] and not ids[r.id], r.id .. ": name and id are unique")
	names[r.name], ids[r.id] = true, true
end
eq(kinds.reaction, 6, "6 element reactions")
eq(kinds.class, 6, "6 signature combos")
eq(kinds.heal, 1, "1 heal combo")
-- the design's table (4.2), row by row
local design = {
	steam_burst = 0.10, thermal_shock = 0.12, overload = 0.12, pyre_of_the_dead = 0.15, mudslide = 0.10, consecrated_ash = 0.15,
	pinned_shot = 0.20, meat_grinder = 0.20, anvil_chain = 0.18, backstab = 0.20, rotting_curse = 0.18, psychic_shatter = 0.20,
	echoing_mend = 0.15,
}
for id, bonus in pairs(design) do
	local r = C.row(cfg, id)
	ok(r ~= nil, id .. " is a row")
	if r then
		near(r.bonus, bonus, 1e-9, id .. " bonus")
	end
end
-- a bonus outside the band is refused by the check
do
	local bad = {band = cfg.band, rows = {{id = "x", name = "X", pt = "X", kind = "reaction", first = {element = "ice"},
		second = {element = "fire"}, bonus = 0.25, weight = 1}}}
	ok(#C.check(bad) >= 1, "a 25% row fails the check")
	bad.rows[1].bonus = 0.09
	ok(#C.check(bad) >= 1, "a 9% row fails the check")
end

-- the spell ids name the spells of the design (data/spells/forms.csv: id, spell)
local formName = {}
for line in readFile("data/spells/forms.csv"):gmatch("[^\r\n]+") do
	local id, name = line:match('^(%d+),("?[^",]+"?),')
	if id then
		formName[tonumber(id)] = (name:gsub('"', ""))
	end
end
local want = {
	pinned_shot = {{[99] = "Snare Trap", [100] = "Seeker Mine"}, {[218] = "Final Verdict", [144] = "Twin Verdict", [19] = "Sunspear"}},
	meat_grinder = {{[2] = "Gorehook"}, {[220] = "Reaping Gyre", [105] = "Butcher's Gyre", [221] = "Earthbreaker"}},
	anvil_chain = {{[196] = "Iron Chain"}, {[84] = "Quaking Stomp"}},
	backstab = {{[240] = "Shadow Step"}, {[45] = "Gutting Slash", [157] = "Death Between Heartbeats"}},
	rotting_curse = {{[182] = "Withering Curse"}, {[183] = "Soul Rot", [113] = "Blightbrand", [185] = "Corpse Explosion"}},
	psychic_shatter = {{[53] = "Bewitching Hex"}, {[228] = "Shattered Psyche", [43] = "Dreamrot"}},
	echoing_mend = {{[96] = "Mirror Mend"}, {[97] = "Lucid Reverie"}},
}
for id, sides in pairs(want) do
	local r = C.row(cfg, id)
	for s, side in ipairs({r.first.spells, r.second.spells}) do
		local n = 0
		for _, sid in ipairs(side) do
			n = n + 1
			eq(formName[sid], sides[s][sid], id .. ": spell id " .. sid .. " is " .. tostring(sides[s][sid]))
		end
		local expected = 0
		for _ in pairs(sides[s]) do
			expected = expected + 1
		end
		eq(n, expected, id .. ": side " .. s .. " lists every spell of the design")
		-- the Codex text (`show`) names every spell of the side
		for _, sid in ipairs(side) do
			ok(r.show and r.show:find(formName[sid], 1, true) ~= nil, id .. ": the Codex text names " .. tostring(formName[sid]))
		end
	end
end

-- the pt-BR text of every name is in the client's locale file, equal to `pt`
do
	local pt = readFile("../client/overlay/modules/client_chaos_locale/pt_br.lua")
	for _, r in ipairs(cfg.rows) do
		local want = '["' .. r.name .. '"] = "' .. r.pt .. '"'
		ok(pt:find(want, 1, true) ~= nil, r.name .. ": pt_br.lua has " .. want)
	end
end

-- ---------------------------------------------------------------- A2. the model numbers
near(C.meanBonus(cfg), 0.151, 0.001, "the weighted mean bonus is about 15%")
near(C.typicalGain(cfg), 0.06, 0.002, "the typical rotation gains about +6% (design 5.1)")
ok(C.typicalGain(cfg) <= cfg.model.typicalMax, "the typical gain is inside its limit")
near(C.bestGain(cfg), 0.08, 1e-9, "the best legal rotation gains +8% (design 4.1)")
ok(C.bestGain(cfg) <= cfg.model.bestMax + 1e-9, "the best gain is inside its limit")

-- ---------------------------------------------------------------- A2b. the riders (phase 6b): the config
eq(#C.checkRiders(cfg), 0, "the riders are sound: " .. table.concat(C.checkRiders(cfg), "; "))
do
	-- the kind of each row (design 4.2 `rider` text) and the numbers the design states
	local kind = {
		steam_burst = "burst", thermal_shock = "brittle", overload = "chain", pyre_of_the_dead = "deathburst", mudslide = "slow",
		consecrated_ash = "holyamp", pinned_shot = "text", meat_grinder = "hooked", anvil_chain = "stun", backstab = "text",
		rotting_curse = "burst", psychic_shatter = "hexrenew", echoing_mend = "hot",
	}
	local text = 0
	for _, r in ipairs(cfg.rows) do
		eq(r.fx and r.fx.kind, kind[r.id], r.id .. ": rider kind")
		if r.fx.kind == "text" then
			text = text + 1
			eq(r.fx.why, "critical", r.id .. ": the reason a rider is text")
		end
		if C.DAMAGE_KINDS[r.fx.kind] then
			ok(r.fx.share <= r.bonus + 1e-9, r.id .. ": a damage rider never deals more than its row's share")
			ok(r.fx.share <= cfg.riders.maxShare + 1e-9, r.id .. ": and at most riders.maxShare of the hit")
		end
	end
	eq(text, 2, "two riders are text (the critical roll needs an engine patch): Pinned Shot and Backstab")
	local function fx(id) return C.row(cfg, id).fx end
	eq(fx("steam_burst").radius, 1, "Steam Burst: a burst in 1 sqm")
	eq(fx("thermal_shock").ms, 3000, "Thermal Shock: brittle for 3 s")
	eq(fx("overload").targets, 3, "Overload: the same energy to 3 enemies")
	eq(fx("overload").element, "energy", "Overload: energy")
	eq(fx("pyre_of_the_dead").ms, 3000, "Pyre of the Dead: kills in the next 3 s burst")
	eq(fx("mudslide").pct, 30, "Mudslide: slowed 30%")
	eq(fx("mudslide").ms, 3000, "Mudslide: for 3 s")
	near(fx("consecrated_ash").pct, 0.15, 1e-9, "Consecrated Ash: 15% more holy")
	eq(fx("consecrated_ash").ms, 3000, "Consecrated Ash: for 3 s")
	eq(fx("anvil_chain").ms, 500, "Anvil Chain: stuns 0.5 s")
	eq(fx("rotting_curse").element, "death", "Rotting Curse: the curse bursts as death damage")
	near(fx("echoing_mend").pct, 0.15, 1e-9, "Echoing Mend: +15% heal over time")
	eq(fx("echoing_mend").ms, 6000, "Echoing Mend: for 6 s")
	-- the stun is the weapon families' stun: the same sub ids and immunity timer
	local daze = dofile("data/scripts/chaos/weapon_families_config.lua").families.club.daze
	eq(cfg.riders.stun.subId, daze.stunSubId, "the stun sub id is the weapon families'")
	eq(cfg.riders.stun.immuneSubId, daze.immuneSubId, "and so is the immunity timer")
	eq(cfg.riders.stun.bossHealth, daze.bossHealth, "and the boss rule")
	-- a rider over its row's share, a missing kind and a text without a reason are refused
	local bad = {band = cfg.band, riders = cfg.riders, rows = {{id = "x", bonus = 0.10, fx = {kind = "burst", radius = 1, share = 0.2, cap = 3}}}}
	ok(#C.checkRiders(bad) >= 1, "a rider that deals more than its row's share fails the check")
	bad.rows[1].fx = {kind = "burst", radius = 1, share = 0.08, cap = 3}
	ok(#C.checkRiders(bad) >= 1, "a rider above riders.maxShare fails the check")
	bad.rows[1].fx = {kind = "nothing"}
	ok(#C.checkRiders(bad) >= 1, "an unknown kind fails the check")
	bad.rows[1].fx = {kind = "text", why = "whatever"}
	ok(#C.checkRiders(bad) >= 1, "a text rider with no reason fails the check")
end

-- the counted gain of the riders, held inside the caps with the owner's bonuses untouched
do
	local sumTypical = C.typicalWithRiders(cfg)
	ok(sumTypical <= cfg.model.typicalMax + 1e-9, "bonus and riders: the typical rotation stays inside its limit: " .. sumTypical)
	ok(C.meanRider(cfg) > 0, "the riders count for something")
	ok(C.typicalWithRiders(cfg) - C.typicalGain(cfg) < 0.0045, "the riders add under 0.45 points to the typical gain")
	ok(C.bestWithRiders(cfg) <= cfg.model.bestMax + 1e-9, "the best legal rotation (one target) with the riders stays inside its limit: " .. C.bestWithRiders(cfg))
	local g = {}
	for _, r in ipairs(cfg.rows) do
		g[r.id] = C.riderGain(cfg, r)
	end
	near(g.steam_burst, 0.02 * 0.4, 1e-9, "Steam Burst counts its share on the enemies near (model.near)")
	near(g.overload, 0.015 * 1.2, 1e-9, "Overload counts up to 3 enemies, 1.2 are near")
	near(g.thermal_shock, 0.02 * 2, 1e-9, "brittle counts the hits of 3 s (every 1.5 s)")
	near(g.consecrated_ash, 0.15 * 2 * 0.1, 1e-9, "holy counts the holy share of the hits")
	eq(g.mudslide, 0, "a slow adds no damage to the model")
	eq(g.anvil_chain, 0, "a stun adds no damage to the model")
	eq(g.echoing_mend, 0, "a heal over time adds no damage to the model")
	eq(g.pinned_shot, 0, "a text rider counts nothing")
	-- the best rotation is one target: a burst counts nothing there
	local one = {}
	for k, v in pairs(cfg) do one[k] = v end
	ok(C.bestWithRiders(cfg) >= C.bestGain(cfg), "the best gain is at least the bonus alone")
end

-- ---------------------------------------------------------------- A2c. the combo masteries (phase 6b): the config and the effective rules
do
	local M = cfg.masteries
	eq(#M.choices, 7, "one combo mastery for each of the seven mastery nodes")
	local nodes, seen = {}, {}
	for i, c in ipairs(M.choices) do
		eq(c.id, i, "ids 1.. in order, never reused")
		ok(not nodes[c.node], "a node has one combo mastery")
		nodes[c.node] = true
		local n = (c.windowMs and 1 or 0) + (c.repeatMs and 1 or 0) + (c.globalMs and 1 or 0)
		eq(n, 1, c.name .. ": changes one number")
		ok(c.shareGain > 0 and c.shareGain <= 0.15, c.name .. ": the model's share gain is small")
		ok(C.masteryGain(cfg, c) <= M.maxGain + 1e-9, c.name .. ": at most maxGain of the spell damage: " .. C.masteryGain(cfg, c))
		seen[c.windowMs and "window" or (c.repeatMs and "repeat" or "pause")] = true
	end
	ok(seen.window and seen["repeat"] and seen.pause, "all three kinds are offered")
	eq(C.masteryChoice(cfg, 99), nil, "an unknown id is no choice")
	eq(C.masteryChoice(cfg, nil), nil, "no id is no choice")
	eq(C.effective(cfg, nil), cfg, "no choice: the config itself")
	local e = C.effective(cfg, C.masteryChoice(cfg, 2))
	eq(e.window.windowMs, 5500, "window +1.5 s")
	eq(e.limits.repeatMs, 6000, "the repeat pause unchanged")
	e = C.effective(cfg, C.masteryChoice(cfg, 1))
	eq(e.limits.repeatMs, 4000, "repeat pause -2 s")
	eq(e.window.windowMs, 4000, "the window unchanged")
	e = C.effective(cfg, C.masteryChoice(cfg, 3))
	eq(e.limits.globalMs, 800, "pause between combos -0.4 s")
	e = C.effective(cfg, {repeatMs = -9000, globalMs = -9000})
	eq(e.limits.repeatMs, M.floor.repeatMs, "never under the repeat floor")
	eq(e.limits.globalMs, M.floor.globalMs, "never under the pause floor")
	eq(cfg.window.windowMs, 4000, "the shared config is not changed")
	-- the effective window opens a pair the plain one refuses
	local function gapFires(c, gap)
		local st = C.newState()
		local a = C.cast(st, c, 1, 1000, 50, pos and nil)
		a.hit, a.element = true, "ice"
		C.cast(st, c, 2, 1000 + gap, 50, nil)
		local row = C.onHit(st, c, {spell = 2, now = 1000 + gap + 50, element = "fire", target = 50, pos = {x = 1, y = 1, z = 7}, rankOf = function() return 0 end})
		return row ~= nil
	end
	eq(gapFires(cfg, 5000), false, "5 s apart: no combo without the mastery")
	eq(gapFires(C.effective(cfg, C.masteryChoice(cfg, 2)), 5000), true, "5 s apart: a combo with the window mastery")
	eq(gapFires(C.effective(cfg, C.masteryChoice(cfg, 2)), 5600), false, "5.6 s apart: outside even the long window")
end

-- ---------------------------------------------------------------- A2d. marks, the hooked set, the death marks, the heal window (core)
do
	local marks = {}
	C.setMark(marks, "brittle", 1000, 3000, 0.02)
	near(C.markFactor(marks, 2000, false), 1.02, 1e-9, "brittle: +2% of everything")
	near(C.markFactor(marks, 2000, true), 1.02, 1e-9, "brittle counts for a holy part too")
	C.setMark(marks, "holy", 1000, 3000, 0.15)
	near(C.markFactor(marks, 2000, false), 1.02, 1e-9, "holy: nothing on a part that is not holy")
	near(C.markFactor(marks, 2000, true), 1.02 * 1.15, 1e-9, "holy: +15% on a holy part, with brittle")
	eq(C.markFactor(marks, 4001, true), 1, "both end after 3 s")
	eq(next(marks), nil, "an expired mark is dropped")
	C.setMark(marks, "holy", 1000, 3000, 0.15)
	C.setMark(marks, "holy", 2000, 3000, 0.10)
	near(marks.holy.pct, 0.15, 1e-9, "a weaker mark does not replace a stronger live one")
	eq(marks.holy.untilMs, 4000, "and does not extend it")
	eq(C.markFactor(nil, 1, true), 1, "no marks")

	local st = C.newState()
	local e = C.cast(st, cfg, 2, 1000, 50, nil)
	C.noteHit(st, 2, 1010, 50, 4000)
	C.noteHit(st, 2, 1020, 51, 4000)
	C.noteHit(st, 2, 1030, 51 + 100000, 4000)
	for i = 1, 20 do C.noteHit(st, 2, 1040, 200 + i, 4000) end
	eq(#e.ids, 8, "at most 8 hit ids are kept")
	C.noteHit(st, 77, 1040, 60, 4000)
	eq(#e.ids, 8, "a hit of another spell is not noted")
	local row = C.row(cfg, "meat_grinder")
	e.target = 50
	C.hook(st, row, e, 220, 2000, 1000)
	eq(C.hookedFactor(st, 220, 50, 2100), 1.20, "the hooked enemy: +20%")
	eq(C.hookedFactor(st, 220, 50, 2100), 1, "once for each enemy")
	eq(C.hookedFactor(st, 220, 51, 2100), 1.20, "another hooked enemy: +20%")
	eq(C.hookedFactor(st, 220, 999, 2100), 1, "an enemy the hook did not hit: plain")
	eq(C.hookedFactor(st, 221, 52, 2100), 1, "another spell: plain")
	eq(C.hookedFactor(st, 220, 52, 3200), 1, "after the window: plain, and the set is dropped")
	eq(st.hooked, nil, "dropped")

	local fx = C.row(cfg, "pyre_of_the_dead").fx
	local m = C.deathMark(st, fx, 5000, 1100, 7)
	eq(m.left, 3, "three bursts")
	ok(C.deathDue(st, 6000) ~= nil, "a kill inside the window bursts")
	ok(C.deathDue(st, 6100) ~= nil, "a second kill bursts")
	ok(C.deathDue(st, 6200) ~= nil, "a third kill bursts")
	eq(C.deathDue(st, 6300), nil, "the fourth does not (cap)")
	C.deathMark(st, fx, 5000, 1100, 7)
	eq(C.deathDue(st, 8001), nil, "a kill after 3 s does not")
	eq(C.riderAmount(0.03, -1100), 33, "the amount of a rider hit")
	eq(C.riderAmount(0.03, 10), 1, "at least 1 for a hit that deals anything")
	eq(C.riderAmount(0.03, 0), 0, "nothing for a hit that deals nothing")

	local hrow = C.row(cfg, "echoing_mend")
	C.hotStart(st, hrow, 97, 10000)
	near(C.hotFactor(st, 97, 12000), 1.15, 1e-9, "the heal over time: +15%")
	eq(C.hotFactor(st, 96, 12000), 1, "another spell's heal: plain")
	eq(C.hotFactor(st, 97, 16001), 1, "after 6 s: plain")
	eq(st.hot, nil, "dropped")
end

-- ---------------------------------------------------------------- A3. the rules
local function pos(x, y)
	return {x = x, y = y, z = 7}
end
local function rank5() return 5 end
local function rank4() return 4 end
local function rank0() return 0 end

-- one scenario: a first cast (element or spell id), the second hit; returns the id of the row that fired or nil
local function scenario(first, second, o)
	o = o or {}
	local st = o.state or C.newState()
	local t0 = o.t0 or 100000
	local e = C.cast(st, cfg, first.spell or 1, t0, o.firstTarget or 50, o.firstPos or pos(10, 10))
	if first.element then
		e.hit, e.element = true, first.element
	end
	local t1 = t0 + (o.gap or 1500)
	C.cast(st, cfg, second.spell or 2, t1, o.secondTarget or 50, pos(10, 10))
	local row, factor = C.onHit(st, cfg, {spell = second.spell or 2, now = (o.hitAt or t1 + 50), element = second.element, heal = second.heal,
		target = o.hitTarget or 50, pos = o.hitPos or pos(10, 10), pvp = o.pvp, rankOf = o.rank or rank5})
	return row and row.id or nil, factor, st
end

-- every reaction fires, by the elements of the two hits
for _, r in ipairs(cfg.rows) do
	if r.kind == "reaction" then
		local id, factor = scenario({element = r.first.element, spell = 1}, {element = r.second.element, spell = 2}, {rank = rank0})
		eq(id, r.id, r.id .. ": " .. r.first.element .. " then " .. r.second.element .. " fires with no rank (free for every class)")
		near(factor, 1 + r.bonus, 1e-9, r.id .. ": the factor is 1 + the bonus")
	end
end
-- the order matters, and a pair that is no reaction does nothing
eq((scenario({element = "fire", spell = 1}, {element = "fire", spell = 2})), nil, "fire then fire is no combo")
eq((scenario({element = "ice", spell = 1}, {element = "ice", spell = 2})), nil, "ice then ice is no combo")
eq((scenario({element = "fire", spell = 1}, {element = "energy", spell = 2})), nil, "fire then energy is no combo")
eq((scenario({element = "holy", spell = 1}, {element = "fire", spell = 2})), nil, "holy then fire is no combo (only fire then holy)")
eq((scenario({element = "physical", spell = 1}, {element = "fire", spell = 2})), nil, "physical then fire is no combo")
eq((scenario({spell = 1}, {element = "fire", spell = 2})), nil, "a first cast that never hit has no element: no reaction")

-- every signature and heal combo fires for every pair of its spell lists at rank 5, and only then
for _, r in ipairs(cfg.rows) do
	if r.kind ~= "reaction" then
		for _, a in ipairs(r.first.spells) do
			for _, b in ipairs(r.second.spells) do
				local heal = r.kind == "heal"
				local id, factor = scenario({spell = a}, {spell = b, heal = heal, element = (not heal) and "physical" or nil})
				eq(id, r.id, r.id .. ": " .. a .. " then " .. b .. " at rank 5")
				near(factor, 1 + r.bonus, 1e-9, r.id .. ": factor")
				eq((scenario({spell = a}, {spell = b, heal = heal}, {rank = rank4})), nil, r.id .. ": rank 4 opens nothing (design 4.2: rank 5)")
				eq((scenario({spell = b}, {spell = a, heal = heal})), nil, r.id .. ": the order matters (" .. b .. " then " .. a .. ")")
			end
		end
	end
end
-- a heal combo needs a heal, a damage combo a damage hit
eq((scenario({spell = 96}, {spell = 97, heal = false, element = "holy"})), nil, "Echoing Mend needs the second hit to be a heal")
eq((scenario({spell = 99}, {spell = 218, heal = true})), nil, "Pinned Shot needs a damage hit")
-- one of the two spells at rank 5 is not enough
do
	local function oneOnly(id)
		return function(sid) return sid == id and 5 or 0 end
	end
	eq((scenario({spell = 99}, {spell = 218, element = "holy"}, {rank = oneOnly(99)})), nil, "only the first spell at rank 5: no signature combo")
	eq((scenario({spell = 99}, {spell = 218, element = "holy"}, {rank = oneOnly(218)})), nil, "only the second spell at rank 5: no signature combo")
end

-- the window: 4 s from the first cast to the second
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {gap = 4000})), "steam_burst", "4000 ms: inside the window")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {gap = 4001})), nil, "4001 ms: outside the window")
-- the same target, or within 2 sqm of where the first spell hit
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 51, hitPos = pos(12, 10)})),
	"steam_burst", "another target 2 sqm away: inside")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 51, hitPos = pos(13, 10)})),
	nil, "another target 3 sqm away: outside")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 50, hitPos = pos(40, 40)})),
	"steam_burst", "the same target: always near")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 51, hitPos = {x = 10, y = 10, z = 8}})),
	nil, "another floor is never near")
-- the pending combo expires after 2.5 s without a hit (1 s in phase 6; O686 phase 8: a cast-time spell hits up to 2 s after its precast)
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {hitAt = 100000 + 1500 + 1000})), "steam_burst", "a hit 1000 ms after the cast: still counts")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {hitAt = 100000 + 1500 + 2501})), nil, "a hit 2501 ms after the cast: the cast missed")

-- only the first hit of a cast asks: an area spell's second target gets nothing
do
	local id, _, st = scenario({element = "ice", spell = 1}, {element = "fire", spell = 2})
	eq(id, "steam_burst", "the first hit of the cast")
	local row, f = C.onHit(st, cfg, {spell = 2, now = 101600, element = "fire", target = 51, pos = pos(10, 11), rankOf = rank0})
	eq(row, nil, "the second hit of the same cast: no combo")
	eq(f, 1, "factor 1")
	-- a tick of a spell nobody cast just now never combos
	row = C.onHit(st, cfg, {spell = 77, now = 101600, element = "fire", target = 51, pos = pos(10, 11), rankOf = rank0})
	eq(row, nil, "a hit of a spell with no fresh cast: no combo")
end

-- the limits: the same combo on the same target waits 6 s, a player has a pause of 1.2 s between combos
do
	local st = C.newState()
	local function pair(t, target, first, second)
		C.cast(st, cfg, 1, t, target, pos(10, 10)).hit = true
		local e = st.ring[#st.ring]
		e.element = first
		C.cast(st, cfg, 2, t + 100, target, pos(10, 10))
		local row = C.onHit(st, cfg, {spell = 2, now = t + 150, element = second, target = target, pos = pos(10, 10), rankOf = rank0})
		return row and row.id or nil
	end
	eq(pair(1000, 50, "ice", "fire"), "steam_burst", "the first combo fires")
	eq(pair(2000, 50, "ice", "fire"), nil, "the same combo on the same target 1 s later: no (global pause and repeat)")
	eq(pair(3000, 50, "ice", "fire"), nil, "the same combo on the same target 2 s later: no (repeat 6 s)")
	eq(pair(3000, 51, "ice", "fire"), "steam_burst", "the same combo on another target after the pause: yes")
	eq(pair(3500, 52, "ice", "fire"), nil, "a combo 0.5 s after another: no (global pause 1.2 s)")
	eq(pair(7000, 50, "ice", "fire"), "steam_burst", "the same combo on the first target after 6 s: yes")
end

-- at most one combo a cast: the best row of the matches (the highest bonus)
do
	local st = C.newState()
	local a = C.cast(st, cfg, 1, 1000, 50, pos(10, 10))
	a.hit, a.element = true, "ice"
	local b = C.cast(st, cfg, 3, 1200, 50, pos(10, 10))
	b.hit, b.element = true, "death"
	C.cast(st, cfg, 2, 1500, 50, pos(10, 10))
	local row, f = C.onHit(st, cfg, {spell = 2, now = 1550, element = "fire", target = 50, pos = pos(10, 10), rankOf = rank0})
	eq(row and row.id, "pyre_of_the_dead", "ice and death before fire: one combo, the better one (15% over 10%)")
	near(f, 1.15, 1e-9, "its factor")
end

-- PvP: no combo, and the entry of the cast is closed
do
	local id, factor, st = scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {pvp = true})
	eq(id, nil, "PvP: no combo")
	eq(factor, 1, "PvP: factor 1")
	eq(st.lastAt, nil, "PvP: no pause started")
end

-- the ring keeps the last four casts
do
	local st = C.newState()
	for i = 1, 7 do
		C.cast(st, cfg, i, i * 100, nil, nil)
	end
	eq(#st.ring, 4, "the ring holds 4 casts")
	eq(st.ring[1].spell, 4, "the oldest are gone")
end

-- the element of a hit
eq(C.elementOf("fire", 100, nil, 0, cfg), "fire", "one part")
eq(C.elementOf("physical", 100, "fire", 0, cfg), "physical", "an empty part is no part")
eq(C.elementOf("physical", 100, "ice", 30, cfg), "ice", "a weapon line spell: the element part at 30% wins over physical")
eq(C.elementOf("physical", 100, "ice", 20, cfg), "physical", "the element part at 20% does not")
eq(C.elementOf("fire", 50, "ice", 100, cfg), "ice", "two elements: the larger part")
eq(C.elementOf(nil, 0, nil, 0, cfg), nil, "no parts")
eq(C.apply(-1000, 1.1), -1100, "apply rounds a damage")
eq(C.apply(1000, 1.15), 1150, "apply rounds a heal")
eq(C.apply(-7, 1), -7, "factor 1 keeps the amount")

-- ---------------------------------------------------------------- B. the engine side on a mocked engine
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {spellRanks = 168}
local sent = {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data} return true end
-- O692: the burst of a combo, sent by the global Vfx helper (data/lib/chaos_vfx.lua) with the raw flag
local bursts = {}
function Vfx(pos, name, raw) bursts[#bursts + 1] = {x = pos.x, y = pos.y, z = pos.z, name = name, raw = raw} return true end
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name)
	local o = {}
	function o:register() registered[name] = o end
	function o:type() end
	return o
end
function Condition() local c = {p = {}}; function c:setTicks() end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end
local clock = 5000000
os.mtime = function() return clock end
local dealtCalls = 0
function doTargetCombat() dealtCalls = dealtCalls + 1 end

dofile("data/scripts/chaos/passivetree_effects.lua")
local ev = registered["ChaosPassiveDealt"]
dofile("data/scripts/chaos/spell_ranks_core.lua")
local RC = dofile("data/scripts/chaos/spell_ranks_config.lua")
ChaosSpellRanksConfig = RC
dofile("data/scripts/chaos/spell_combos.lua")
local M = ChaosSpellCombos
local P = ChaosSpellRanksCore
local R = ChaosSpellRanks
ok(registered["ChaosSpellCombosLogout"] and registered["ChaosSpellCombosLogin"], "login and logout events")

local storage = {}
local castSpell
ChaosSupportsSpell = {cast = function(pid) return 900, castSpell end}
local function newPlayer(voc)
	local p = {pos = {x = 100, y = 100, z = 7}}
	function p:getId() return 900 end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getVocation() return {getId = function() return voc or 2 end} end
	function p:getLevel() return 300 end
	function p:getStorageValue(k) return storage[k] or -1 end
	function p:getPosition() return self.pos end
	function p:getTarget() return self.target end
	function p:registerEvent() end
	return p
end
local function newMonster(id, x, y)
	local m = {id = id, pos = {x = x or 101, y = y or 100, z = 7}}
	function m:getId() return id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return self.master end
	function m:getPosition() return self.pos end
	function m:getName() return "Troll" end
	return m
end
local function setRank(id, rank)
	storage[RC.storage.rankBase + id] = P.pack(rank, 0, 0, false)
end
local function cast(p, id, aggressive)
	ChaosSpellEvents.onSpellPreCast(p, "S" .. id, id, 1, aggressive ~= false, 0, 0)
	castSpell = id
end
local function hit(p, target, ctype, amount, ctype2, amount2)
	local d1, _, d2 = ev.onHealthChange(target, p, amount, ctype, amount2 or 0, ctype2 or COMBAT_NONE, ORIGIN_SPELL)
	return d1, d2
end
local function tick(ms)
	clock = clock + ms
end

local p = newPlayer(2) -- vocation 2: the class spell factor is 1
local troll = newMonster(501)
p.target = troll
RC.track = false

-- switched off (the shipped state until O709; the loaded config is switched off here): a fire spell after an ice spell is plain
eq(RC.enabled, true, "the ranks ship switched on (O709, owner 2026-11-21)")
RC.enabled = false
cast(p, 300)
eq(M.states[900], nil, "switch off: no ring is kept")
eq((hit(p, troll, COMBAT_ICEDAMAGE, -1000)), -1000, "switch off: an ice hit is plain")
tick(1500)
cast(p, 301)
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1000, "switch off: ice then fire gives nothing")
eq(#sent, 0, "switch off: no message")

-- ranks on, combos off by their own switch
RC.enabled = true
cfg = ChaosSpellCombosConfig
cfg.enabled = false
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1000, "combos off: ice then fire gives nothing")
cfg.enabled = true
eq(#sent, 0, "combos off: no message")

-- Steam Burst: ice then fire, free for every class, rank 0
tick(10000)
cast(p, 300)
eq((hit(p, troll, COMBAT_ICEDAMAGE, -1000)), -1000, "the first spell of a pair is plain")
tick(1500)
cast(p, 301)
local d1, d2 = hit(p, troll, COMBAT_FIREDAMAGE, -1000, COMBAT_NONE, 0)
eq(d1, -1100, "ice then fire: Steam Burst +10% on the hit of the second spell")
eq(#sent, 1, "one message to the client")
eq(sent[1].action, "combo", "a combo message")
eq(sent[1].opcode, 168, "on opcode 168")
eq(sent[1].data.id, "steam_burst", "its id")
eq(sent[1].data.n, "Steam Burst", "its English name")
eq(sent[1].data.x, 101, "the target's x")
eq(sent[1].data.z, 7, "the target's floor")
-- O692: the burst on the target tile, existing effects of ice then fire, raw
eq(#bursts, 2, "Steam Burst: two effects on the target")
eq(bursts[1].name, "frost_nova", "the ice effect first")
eq(bursts[2].name, "fire_explosion", "then the fire effect")
eq(bursts[1].x, 101, "on the target's tile")
eq(bursts[1].raw, true, "sent raw (no Form swap)")
-- the credit: the bonus is inside the hit of the second spell, in its cast context; no extra hit exists
eq(select(2, ChaosSupportsSpell.cast()), 301, "the combat log reads the SECOND spell for the hit (it gets the credit, bonus included)")
eq(dealtCalls, 0, "no extra hit was dealt (nothing else can be credited)")
-- the second hit of the same cast (an area spell's next target) gets nothing
local troll2 = newMonster(502, 102, 100)
eq((hit(p, troll2, COMBAT_FIREDAMAGE, -1000)), -1000, "the second target of the same cast: plain")
-- the secondary part is scaled with the primary
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
d1, d2 = hit(p, troll, COMBAT_FIREDAMAGE, -1000, COMBAT_FIREDAMAGE, -200)
eq(d1, -1100, "primary +10%")
eq(d2, -220, "secondary +10% too")

-- the rank multiplies first, the combo on the ranked hit: rank 20 is +18% then +12% (Thermal Shock, fire then ice)
tick(10000)
cast(p, 301)
hit(p, troll, COMBAT_FIREDAMAGE, -1000)
tick(1500)
setRank(302, 20)
cast(p, 302)
d1 = hit(p, troll, COMBAT_ICEDAMAGE, -1000)
near(d1, -math.floor(1000 * 1.18 * 1.12 + 0.5), 2, "rank 20 +18% and Thermal Shock +12% on the ranked hit (the bonus grows with the rank)")
eq(sent[#sent].data.id, "thermal_shock", "Thermal Shock")

-- the element after a Form conversion counts: a physical spell that converts to ice, after fire
tick(10000)
cast(p, 301)
hit(p, troll, COMBAT_FIREDAMAGE, -1000)
tick(1500)
local FE = ChaosSpellForms
local oldActive, oldConv = FE.active, FE.conversion
FE.active = function() return {{kind = "SHIFT", element = "ice"}} end
FE.conversion = function() return "ice" end
cast(p, 303)
d1 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
eq(d1, -1120, "fire then a spell converted to ice: Thermal Shock (the Form's element counts)")
FE.active, FE.conversion = oldActive, oldConv
tick(10000)
cast(p, 301)
hit(p, troll, COMBAT_FIREDAMAGE, -1000)
tick(1500)
cast(p, 303)
eq((hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)), -1000, "the same physical spell with no Form: no reaction")

-- PvP: never
tick(10000)
local rival = newMonster(600)
function rival:isPlayer() return true end
function rival:isMonster() return false end
sent = {}
cast(p, 305)
local pvpBase = hit(p, rival, COMBAT_FIREDAMAGE, -1000) -- the level scaling of damage between players, no combo in it
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
eq((hit(p, rival, COMBAT_FIREDAMAGE, -1000)), pvpBase, "PvP: ice then fire on another player gives nothing (the hit is the plain PvP hit)")
eq(#sent, 0, "PvP: no message")
-- a summon of a player is no target either
tick(10000)
local pet = newMonster(601)
pet.master = newPlayer(2)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
eq((hit(p, pet, COMBAT_FIREDAMAGE, -1000)), -1000, "a player's summon is no target")

-- a weapon hit, a proc and another player's cast are never touched
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
local w = ev.onHealthChange(troll, p, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(w, -1000, "a weapon hit has no combo")
ChaosKeystones = {depth = 1}
w = hit(p, troll, COMBAT_FIREDAMAGE, -1000)
eq(w, -1000, "a hit inside the proc guard (every extra hit of a Form) has no combo")
ChaosKeystones = nil
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1100, "the real first hit still has it (the guarded hit did not close the cast)")

-- a Signature combo: Gorehook (2) then Reaping Gyre (220), both rank 5
tick(10000)
setRank(2, 5)
setRank(220, 5)
cast(p, 2)
hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
tick(2000)
cast(p, 220)
d1 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
near(d1, -math.floor(1000 * R.factor(p, 220, false, false) * 1.20 + 0.5), 2, "Meat Grinder +20% on the ranked hit")
eq(sent[#sent].data.id, "meat_grinder", "Meat Grinder")
tick(10000)
setRank(2, 4)
cast(p, 2)
hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
tick(2000)
cast(p, 220)
d1 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
near(d1, -math.floor(1000 * R.factor(p, 220, false, false) + 0.5), 2, "rank 4 on the hook: no Meat Grinder")

-- the heal combo: Mirror Mend (96) then Lucid Reverie (97), a heal on an ally, +15%
tick(10000)
setRank(96, 5)
setRank(97, 5)
local ally = newMonster(700)
function ally:isPlayer() return true end
function ally:isMonster() return false end
p.target = nil
cast(p, 96)
hit(p, ally, COMBAT_HEALING, 1000)
tick(1500)
cast(p, 97)
local h1 = hit(p, ally, COMBAT_HEALING, 1000)
near(h1, math.floor(1000 * R.factor(p, 97, true, false) * 1.15 + 0.5), 2, "Echoing Mend +15% on the heal")
eq(sent[#sent].data.id, "echoing_mend", "Echoing Mend")
eq(bursts[#bursts].name, "aura_burst_gold", "Echoing Mend: a gold burst")

-- a stale ring: a cast that is not followed by a hit within the window is forgotten, and logout clears the state
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(4500)
cast(p, 301)
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1000, "the ice cast is older than 4 s: no combo")
registered["ChaosSpellCombosLogout"].onLogout(p)
eq(M.states[900], nil, "logout drops the state")

-- O686 phase 8 (the live pass): the engine's order is precast, the spell's hits, then `cast` (engine patch 0008: "after the spell ran"). The ring
-- entry was made by the `cast` handler, after the hit it was meant for, so no combo ever fired for an instant spell; it is made by `precast` now.
-- A cast-time spell (ChaosCasting, 1 to 2 s) hits long after its precast: the entry lives ring.expireMs.
do
	local E = ChaosSpellEvents
	local function engineCast(id, ctype, amount, delayMs)
		E.onSpellPreCast(p, "S" .. id, id, 1, true, 0, 0)
		castSpell = id
		if delayMs then
			tick(delayMs) -- a cast-time spell: the hit comes when the bar is full
		end
		local d = hit(p, troll, ctype, amount)
		E.onSpellCast(p, "S" .. id, id, 1, true, 0, 0)
		return d
	end
	tick(10000)
	eq((engineCast(300, COMBAT_ICEDAMAGE, -1000)), -1000, "engine order: the first spell is plain")
	tick(1500)
	eq((engineCast(301, COMBAT_FIREDAMAGE, -1000)), -1100, "engine order precast, hit, cast: ice then fire gives Steam Burst +10%")
	eq(#M.states[900].ring, 2, "the `cast` event after the hit made no second entry")
	-- a cast-time spell: 2 s between its precast and its hit
	tick(10000)
	eq((engineCast(300, COMBAT_ICEDAMAGE, -1000, 2000)), -1000, "a 2 s cast-time ice spell is plain")
	tick(500)
	eq((engineCast(301, COMBAT_FIREDAMAGE, -1000, 2000)), -1100, "a 2 s cast-time fire spell after it: its hit meets its own entry, Steam Burst")
	tick(10000)
end

-- ---------------------------------------------------------------- C. the riders and the masteries (phase 6b), the engine side
do
	RC.enabled = true
	cfg = ChaosSpellCombosConfig
	cfg.enabled = true
	-- the engine: a world of monsters, the proc guard globals, the scheduler, the conditions
	local world, players = {}, {p}
	players[900] = p
	local dealt = {} -- the rider hits: {target, ctype, amount, origin, K, FE, S, ctx}
	local events = {}
	local guardK = {depth = 0}
	ChaosKeystones = guardK
	ChaosSpellForms.depth = 0
	ChaosSupports = ChaosSupports or {}
	ChaosSupports.formDepth = 0
	local renewed = {}
	ChaosSupports.renewHex = function(c) renewed[#renewed + 1] = c:getId() return true end
	Player = function(id) return players[id] end
	Creature = function(id) return world[id] end
	Position = function(x, y, z) return {x = x, y = y, z = z} end
	function addEvent(fn, ms, ...) events[#events + 1] = {fn = fn, n = select("#", ...), args = {...}} end
	local function flush()
		local list = events
		events = {}
		for _, e in ipairs(list) do
			e.fn((table.unpack or unpack)(e.args, 1, e.n))
		end
	end
	function doTargetCombat(attacker, target, ctype, a, b, fx, origin)
		dealt[#dealt + 1] = {target = target:getId(), ctype = ctype, amount = a, origin = origin, K = guardK.depth, FE = ChaosSpellForms.depth,
			S = ChaosSupports.formDepth}
		return true
	end
	Game = {getSpectators = function(center, _, _, rx)
		local out = {}
		local ids = {}
		for id in pairs(world) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local c = world[id]
			if c.pos.z == center.z and math.max(math.abs(c.pos.x - center.x), math.abs(c.pos.y - center.y)) <= rx then
				out[#out + 1] = c
			end
		end
		return out
	end}
	local function mon(id, x, y, o)
		local m = newMonster(id, x, y)
		m.health, m.maxHealth, m.conds = 5000, 5000, {}
		function m:getHealth() return self.health end
		function m:getMaxHealth() return self.maxHealth end
		function m:getTile() return nil end
		function m:getType() return {isBoss = function() return false end} end
		function m:getCondition(ctype, cid, sub)
			for _, c in ipairs(self.conds) do
				if c.ctype == ctype and (sub == nil or c.p[CONDITION_PARAM_SUBID] == sub) then return c end
			end
			return nil
		end
		function m:addCondition(c) self.conds[#self.conds + 1] = c return true end
		function m:registerEvent() end
		world[id] = m
		return m
	end
	function Condition(ctype)
		local c = {ctype = ctype, p = {}}
		function c:setParameter(k, v) self.p[k] = v end
		function c:setFormula(a, b, c2, d) self.formula = {a, b, c2, d} end
		function c:setTicks() end
		return c
	end
	-- a fresh fight: the player's target, a ring and the limits cleared
	local function fresh()
		world = {}
		dealt, renewed, events = {}, {}, {}
		for k in pairs(ChaosSpellCombos.marks) do ChaosSpellCombos.marks[k] = nil end
		ChaosSpellCombos.pending = nil
		ChaosSpellCombos.states = {}
		sent = {}
		tick(20000)
		storage = {}
		ChaosPassiveCache[900] = nil
	end
	-- a hit: returns the final primary damage (what the pool and the factors left) after afterHit has been told
	local function strike(target, ctype, amount, ctype2, amount2)
		return (hit(p, target, ctype, amount, ctype2, amount2))
	end

	-- Steam Burst: ice then fire, a burst of 2% of the hit on the enemies within 1 sqm of the target, never the target, never far ones
	fresh()
	local t1 = mon(501, 101, 100)
	local near1, near2, far = mon(502, 101, 101), mon(503, 100, 100), mon(504, 105, 105)
	local ally = mon(505, 102, 100)
	function ally:isPlayer() return true end
	function ally:isMonster() return false end
	local pet = mon(506, 100, 101)
	pet.master = p
	p.target = t1
	cast(p, 300)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	local d1 = strike(t1, COMBAT_FIREDAMAGE, -1000)
	eq(d1, -1100, "Steam Burst still gives its +10% on the hit")
	eq(#dealt, 0, "the rider hits come one tick later, never inside the hit")
	ok(ChaosSpellCombos.pending == nil, "the hit took the pending rider (afterHit)")
	eq(#events, 1, "one scheduled rider")
	flush()
	eq(#dealt, 2, "the burst hits the two enemies within 1 sqm of the target")
	table.sort(dealt, function(a, b) return a.target < b.target end)
	eq(dealt[1].target, 502, "the near enemy")
	eq(dealt[2].target, 503, "the other near enemy")
	eq(dealt[1].amount, -22, "2% of the hit of 1100")
	eq(dealt[1].ctype, COMBAT_FIREDAMAGE, "the element of the hit")
	eq(dealt[1].origin, ORIGIN_SPELL, "ORIGIN_SPELL, a hit of the spell")
	eq(dealt[1].K, 1, "inside the keystone proc guard: no passive tree bonus twice, no combo")
	eq(dealt[1].FE, 1, "no Form on it")
	eq(dealt[1].S, 1, "no support effect on it")
	eq(guardK.depth, 0, "the guard is down again")
	-- a rider never combos again: its hits did not reach the combo hook (they are dealt with the proc guard up), and the ring is untouched
	eq(#sent, 1, "no second combo message")
	-- never the far enemy, the target, a player or a player's summon
	for _, d in ipairs(dealt) do
		ok(d.target ~= 501 and d.target ~= 504 and d.target ~= 505 and d.target ~= 506, "the burst spares the target, far enemies, players and summons: " .. d.target)
	end

	-- the cap: five enemies within 1 sqm, the burst hits three
	fresh()
	t1 = mon(501, 101, 100)
	for i = 1, 5 do mon(510 + i, 101 + (i % 2), 99 + (i % 3)) end
	p.target = t1
	cast(p, 300)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	flush()
	eq(#dealt, 3, "a burst hits at most `cap` enemies")

	-- Overload: energy then fire, the same energy to 3 enemies near (within 3 sqm), 1.5% of the hit
	fresh()
	t1 = mon(501, 101, 100)
	for i = 1, 4 do mon(520 + i, 101 + i - 1, 102) end
	p.target = t1
	cast(p, 300)
	strike(t1, COMBAT_ENERGYDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	d1 = strike(t1, COMBAT_FIREDAMAGE, -1000)
	eq(d1, -1120, "Overload +12%")
	flush()
	eq(#dealt, 3, "the energy chain reaches 3 enemies")
	eq(dealt[1].ctype, COMBAT_ENERGYDAMAGE, "the same energy")
	eq(dealt[1].amount, -17, "1.5% of 1120")

	-- Rotting Curse (death burst of the curse): rank 5 both, death damage on the enemies within 2 sqm
	fresh()
	t1 = mon(501, 101, 100)
	local a, b = mon(530, 103, 100), mon(531, 104, 100)
	p.target = t1
	setRank(182, 5)
	setRank(183, 5)
	cast(p, 182)
	strike(t1, COMBAT_DEATHDAMAGE, -1000)
	tick(2000)
	cast(p, 183)
	d1 = strike(t1, COMBAT_DEATHDAMAGE, -1000)
	near(d1, -math.floor(1000 * R.factor(p, 183, false, false) * 1.18 + 0.5), 2, "Rotting Curse +18%")
	flush()
	eq(#dealt, 1, "the curse bursts on the enemy within 2 sqm (the one 3 sqm off is out)")
	eq(dealt[1].target, 530, "the near enemy")
	eq(dealt[1].ctype, COMBAT_DEATHDAMAGE, "death damage")

	-- Thermal Shock: brittle for 3 s, +2% of everything the target takes, from everyone
	fresh()
	t1 = mon(501, 101, 100)
	p.target = t1
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	tick(1500)
	cast(p, 302)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	flush()
	local marks = registered["ChaosSpellComboMarks"]
	ok(marks ~= nil, "the marks event is registered")
	eq((marks.onHealthChange(t1, nil, -1000, COMBAT_PHYSICALDAMAGE, -500, COMBAT_FIREDAMAGE)), -1020, "brittle: +2% on the primary part")
	local _, _, s2 = marks.onHealthChange(t1, nil, -1000, COMBAT_PHYSICALDAMAGE, -500, COMBAT_FIREDAMAGE)
	eq(s2, -510, "and on the secondary part")
	eq((marks.onHealthChange(t1, nil, 1000, COMBAT_HEALING, 0, COMBAT_NONE)), 1000, "a heal is never touched")
	tick(3100)
	eq((marks.onHealthChange(t1, nil, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE)), -1000, "after 3 s the target is plain again")
	eq(ChaosSpellCombos.marks[501], nil, "and the mark is dropped")

	-- Consecrated Ash: 15% more HOLY for 3 s
	fresh()
	t1 = mon(501, 101, 100)
	p.target = t1
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	tick(1500)
	cast(p, 303)
	strike(t1, COMBAT_HOLYDAMAGE, -1000)
	flush()
	eq((marks.onHealthChange(t1, nil, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE)), -1150, "holy: +15% on holy damage")
	eq((marks.onHealthChange(t1, nil, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE)), -1000, "nothing on fire damage")
	tick(3100)
	eq((marks.onHealthChange(t1, nil, -1000, COMBAT_HOLYDAMAGE, 0, COMBAT_NONE)), -1000, "after 3 s plain")

	-- Mudslide: slowed 30% for 3 s (a paralysis condition with a formula, the way Frost Ward does it)
	fresh()
	t1 = mon(501, 101, 100)
	p.target = t1
	cast(p, 304)
	strike(t1, COMBAT_EARTHDAMAGE, -1000)
	tick(1500)
	cast(p, 302)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	flush()
	eq(#t1.conds, 1, "one slow condition")
	eq(t1.conds[1].ctype, CONDITION_PARALYZE, "a paralysis")
	eq(t1.conds[1].p[CONDITION_PARAM_TICKS], 3000, "for 3 s")
	near(t1.conds[1].formula[1], -0.30, 1e-9, "30% slower")
	eq(#dealt, 0, "a slow deals nothing")

	-- Anvil Chain: Iron Chain (196) then Quaking Stomp (84), both rank 5: stunned 0.5 s, never a boss, never twice in the rest
	fresh()
	t1 = mon(501, 101, 100)
	p.target = t1
	setRank(196, 5)
	setRank(84, 5)
	cast(p, 196)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	tick(1500)
	cast(p, 84)
	d1 = strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	near(d1, -math.floor(1000 * R.factor(p, 84, false, false) * 1.18 + 0.5), 2, "Anvil Chain +18%")
	flush()
	local stunned
	for _, c in ipairs(t1.conds) do
		if c.ctype == CONDITION_PARALYZE then stunned = c end
	end
	ok(stunned ~= nil, "the stomp stuns")
	eq(stunned.p[CONDITION_PARAM_TICKS], 500, "for 0.5 s")
	eq(stunned.p[CONDITION_PARAM_SUBID], 71034, "with the weapon families' stun sub id (the monsters' attacks are cancelled while it lasts)")
	eq(stunned.formula[1], -1, "it holds the monster still")
	local rested
	for _, c in ipairs(t1.conds) do
		if c.ctype == CONDITION_ATTRIBUTES and c.p[CONDITION_PARAM_SUBID] == 71035 then rested = c end
	end
	ok(rested ~= nil, "and the monster cannot be stunned again for a while (the immunity timer)")
	-- a boss is not stunned
	fresh()
	t1 = mon(501, 101, 100)
	t1.maxHealth = 90000
	p.target = t1
	setRank(196, 5)
	setRank(84, 5)
	cast(p, 196)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	tick(1500)
	cast(p, 84)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	flush()
	eq(#t1.conds, 0, "a boss is not stunned")
	-- a monster in its rest is not stunned again
	fresh()
	t1 = mon(501, 101, 100)
	local rest = Condition(CONDITION_ATTRIBUTES)
	rest:setParameter(CONDITION_PARAM_SUBID, 71035)
	t1:addCondition(rest)
	p.target = t1
	setRank(196, 5)
	setRank(84, 5)
	cast(p, 196)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	tick(1500)
	cast(p, 84)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	flush()
	eq(#t1.conds, 1, "a monster in the rest after a stun is not stunned again")

	-- Psychic Shatter: Bewitching Hex (53) then Shattered Psyche (228): the target's Hex is renewed
	fresh()
	t1 = mon(501, 101, 100)
	p.target = t1
	setRank(53, 5)
	setRank(228, 5)
	cast(p, 53)
	strike(t1, COMBAT_ENERGYDAMAGE, -1000)
	tick(1500)
	cast(p, 228)
	strike(t1, COMBAT_ENERGYDAMAGE, -1000)
	flush()
	eq(#renewed, 1, "the Hex is renewed")
	eq(renewed[1], 501, "on the target")

	-- Meat Grinder: Gorehook (2) hit two enemies, Reaping Gyre (220): the +20% lands on every enemy the hook hit, once each
	fresh()
	t1 = mon(501, 101, 100)
	local t2, t3 = mon(502, 102, 100), mon(503, 103, 100)
	p.target = t1
	setRank(2, 5)
	setRank(220, 5)
	cast(p, 2)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	strike(t2, COMBAT_PHYSICALDAMAGE, -1000)
	tick(2000)
	cast(p, 220)
	local g = R.factor(p, 220, false, false)
	near(strike(t1, COMBAT_PHYSICALDAMAGE, -1000), -math.floor(1000 * g * 1.20 + 0.5), 2, "the first hit of the gyre: Meat Grinder +20%")
	near(strike(t2, COMBAT_PHYSICALDAMAGE, -1000), -math.floor(1000 * g * 1.20 + 0.5), 2, "the second enemy the hook hit: +20% too")
	near(strike(t3, COMBAT_PHYSICALDAMAGE, -1000), -math.floor(1000 * g + 0.5), 2, "an enemy the hook did not hit: plain")
	near(strike(t2, COMBAT_PHYSICALDAMAGE, -1000), -math.floor(1000 * g + 0.5), 2, "the same enemy again: plain (once each)")
	flush()
	eq(#dealt, 0, "the hooked rider deals no extra hit")
	-- the same cast of the hook on a different cast of the gyre long after: nothing remembered
	tick(3000)
	cast(p, 220)
	near(strike(t3, COMBAT_PHYSICALDAMAGE, -1000), -math.floor(1000 * g + 0.5), 2, "no hooked set is left after its second")

	-- Pyre of the Dead: death then fire; a kill of the player's own hit in the next 3 s bursts on the others near the corpse
	fresh()
	t1 = mon(501, 101, 100)
	local weak, bystander, farOne = mon(502, 101, 101), mon(503, 102, 101), mon(504, 110, 110)
	weak.health = 50
	p.target = t1
	cast(p, 305)
	strike(t1, COMBAT_DEATHDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	d1 = strike(t1, COMBAT_FIREDAMAGE, -1000)
	eq(d1, -1150, "Pyre of the Dead +15%")
	flush()
	ok(ChaosSpellCombos.states[900].death ~= nil, "a death mark is set")
	eq(#dealt, 0, "nothing bursts yet")
	tick(1000)
	-- a kill: a melee hit that takes the weak one down (any hit of the player counts)
	ev.onHealthChange(weak, p, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	flush()
	ok(#dealt >= 1, "the corpse burst hits enemies near it")
	local seen = {}
	for _, d in ipairs(dealt) do seen[d.target] = d end
	ok(seen[501] and seen[503], "the others within 1 sqm of the corpse take the burst")
	ok(not seen[504], "never a far enemy")
	ok(not seen[502], "never the corpse itself")
	near(-seen[503].amount, 34.5, 1.01, "3% of the hit that opened the combo (1150)")
	-- the cap: three bursts a combo, then no more; the window ends after 3 s
	for i = 1, 3 do
		local v = mon(600 + i, 101, 101)
		v.health = 10
		ev.onHealthChange(v, p, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	end
	flush()
	local bursts3 = 0
	for _, d in ipairs(dealt) do if d.target == 501 then bursts3 = bursts3 + 1 end end
	eq(bursts3, 3, "at most three bursts a combo (the kill above and two more)")
	-- the window: a combo, 3.1 s, a kill: nothing
	fresh()
	t1 = mon(501, 101, 100)
	weak, bystander = mon(502, 101, 101), mon(503, 102, 101)
	weak.health = 50
	p.target = t1
	cast(p, 305)
	strike(t1, COMBAT_DEATHDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	flush()
	tick(3100)
	ev.onHealthChange(weak, p, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	flush()
	eq(#dealt, 0, "a kill after the 3 s window does not burst")
	-- a hit that does not kill does not burst either
	fresh()
	t1 = mon(501, 101, 100)
	weak = mon(502, 101, 101)
	mon(503, 102, 101)
	p.target = t1
	cast(p, 305)
	strike(t1, COMBAT_DEATHDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	flush()
	ev.onHealthChange(weak, p, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	flush()
	eq(#dealt, 0, "a hit that leaves the enemy alive does not burst")

	-- Echoing Mend: Mirror Mend (96) then Lucid Reverie (97): the pulses of the next 6 s heal +15%, the spell's own only
	fresh()
	local friend = mon(700, 100, 100)
	function friend:isPlayer() return true end
	function friend:isMonster() return false end
	p.target = nil
	setRank(96, 5)
	setRank(97, 5)
	cast(p, 96)
	hit(p, friend, COMBAT_HEALING, 1000)
	tick(1500)
	cast(p, 97)
	local h1 = hit(p, friend, COMBAT_HEALING, 1000)
	near(h1, math.floor(1000 * R.factor(p, 97, true, false) * 1.15 + 0.5), 2, "Echoing Mend +15% on the first heal")
	tick(2000)
	local h2 = hit(p, friend, COMBAT_HEALING, 1000)
	near(h2, math.floor(1000 * R.factor(p, 97, true, false) * 1.15 + 0.5), 2, "the next pulse (2 s later) heals +15% too")
	tick(2000)
	local h3 = hit(p, friend, COMBAT_HEALING, 1000)
	near(h3, math.floor(1000 * R.factor(p, 97, true, false) * 1.15 + 0.5), 2, "and the third (4 s later)")
	tick(2500)
	local h4 = hit(p, friend, COMBAT_HEALING, 1000)
	near(h4, math.floor(1000 * R.factor(p, 97, true, false) + 0.5), 2, "6.5 s later the pulse is plain")
	flush()
	eq(#dealt, 0, "a heal over time rider deals no damage")
	-- another spell's heal in the window is plain
	fresh()
	friend = mon(700, 100, 100)
	function friend:isPlayer() return true end
	function friend:isMonster() return false end
	setRank(96, 5)
	setRank(97, 5)
	cast(p, 96)
	hit(p, friend, COMBAT_HEALING, 1000)
	tick(1500)
	cast(p, 97)
	hit(p, friend, COMBAT_HEALING, 1000)
	tick(500)
	cast(p, 98)
	local other = hit(p, friend, COMBAT_HEALING, 1000)
	near(other, math.floor(1000 * R.factor(p, 98, true, false) + 0.5), 2, "another spell's heal in the window is plain")

	-- no rider in PvP, with the switch off, or on a player or a summon (the row does not fire there)
	fresh()
	t1 = mon(501, 101, 100)
	local rivalP = mon(540, 101, 101)
	function rivalP:isPlayer() return true end
	function rivalP:isMonster() return false end
	p.target = t1
	cast(p, 300)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	strike(rivalP, COMBAT_FIREDAMAGE, -1000)
	flush()
	eq(#dealt, 0, "PvP: no rider")
	ok(ChaosSpellCombos.pending == nil, "PvP: nothing pending")
	RC.enabled = false
	fresh()
	t1 = mon(501, 101, 100)
	mon(502, 101, 101)
	p.target = t1
	cast(p, 300)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	flush()
	eq(#dealt, 0, "the ranks switch off: no rider")
	RC.enabled = true
	cfg.enabled = false
	fresh()
	t1 = mon(501, 101, 100)
	mon(502, 101, 101)
	p.target = t1
	cast(p, 300)
	strike(t1, COMBAT_ICEDAMAGE, -1000)
	tick(1500)
	cast(p, 301)
	strike(t1, COMBAT_FIREDAMAGE, -1000)
	flush()
	eq(#dealt, 0, "the combos switch off: no rider")
	cfg.enabled = true

	-- the text riders (a forced critical needs an engine patch): the row still gives its bonus and no rider runs
	fresh()
	t1 = mon(501, 101, 100)
	mon(502, 101, 101)
	p.target = t1
	setRank(99, 5)
	setRank(218, 5)
	cast(p, 99)
	strike(t1, COMBAT_PHYSICALDAMAGE, -1000)
	tick(1500)
	cast(p, 218)
	d1 = strike(t1, COMBAT_HOLYDAMAGE, -1000)
	near(d1, -math.floor(1000 * R.factor(p, 218, false, false) * 1.20 + 0.5), 2, "Pinned Shot still gives its +20%")
	eq(#events, 0, "a text rider schedules nothing")
	ok(ChaosSpellCombos.pending == nil, "and leaves nothing pending")

	-- the combo masteries: ChaosPassiveCache[pid].comboMod = id
	local function pairGap(gap, target2)
		fresh()
		local x1 = mon(501, 101, 100)
		p.target = x1
		cast(p, 300)
		strike(x1, COMBAT_ICEDAMAGE, -1000)
		return x1
	end
	-- Lingering Window (id 2): 5 s between the casts fires, without the mastery it does not
	local x1 = pairGap()
	tick(5000)
	cast(p, 301)
	eq((strike(x1, COMBAT_FIREDAMAGE, -1000)), -1000, "5 s apart: no combo without the mastery")
	x1 = pairGap()
	ChaosPassiveCache[900] = {comboMod = 2}
	tick(5000)
	cast(p, 301)
	eq((strike(x1, COMBAT_FIREDAMAGE, -1000)), -1100, "5 s apart: Steam Burst with Lingering Window")
	x1 = pairGap()
	ChaosPassiveCache[900] = {comboMod = 99}
	tick(5000)
	cast(p, 301)
	eq((strike(x1, COMBAT_FIREDAMAGE, -1000)), -1000, "an id that is no choice changes nothing")
	-- Short Memory (id 1): the same combo on the same target again after 4.5 s
	local function twice(gap, mod)
		fresh()
		ChaosPassiveCache[900] = mod and {comboMod = mod} or nil
		local y1 = mon(501, 101, 100)
		p.target = y1
		cast(p, 300)
		strike(y1, COMBAT_ICEDAMAGE, -1000)
		tick(1500)
		cast(p, 301)
		strike(y1, COMBAT_FIREDAMAGE, -1000)
		tick(gap)
		cast(p, 300)
		strike(y1, COMBAT_ICEDAMAGE, -1000)
		tick(1500)
		cast(p, 301)
		return (strike(y1, COMBAT_FIREDAMAGE, -1000))
	end
	eq(twice(3000), -1000, "Steam Burst again 4.5 s after it: no (repeat 6 s)")
	eq(twice(3000, 1), -1100, "with Short Memory (repeat -2 s): yes, 4.5 s after the first")
	-- Eager Rhythm (id 3): 0.8 s between two combos
	local function rhythm(mod)
		fresh()
		ChaosPassiveCache[900] = mod and {comboMod = mod} or nil
		local y1, y2 = mon(501, 101, 100), mon(502, 120, 120)
		p.target = y1
		cast(p, 300)
		strike(y1, COMBAT_ICEDAMAGE, -1000)
		tick(100)
		cast(p, 301)
		strike(y1, COMBAT_FIREDAMAGE, -1000)
		p.target = y2
		tick(300)
		cast(p, 300)
		strike(y2, COMBAT_ICEDAMAGE, -1000)
		tick(700)
		cast(p, 301)
		return (strike(y2, COMBAT_FIREDAMAGE, -1000))
	end
	eq(rhythm(), -1000, "a second combo 1 s after the first: no (pause 1.2 s)")
	eq(rhythm(3), -1100, "with Eager Rhythm (pause 0.8 s): yes")
	ChaosPassiveCache[900] = nil
	fresh()
end

-- O692: every row has a burst of ChaosVfx names that exist; a reaction row's effects are tagged with its two elements
do
	local f = assert(loadfile("data/lib/chaos_vfx.lua"))
	local saved = rawget(_G, "ChaosVfx")
	f()
	local V = rawget(_G, "ChaosVfx")
	local tags = {}
	local fh = assert(io.open("data/spells/spell_fx_elements.csv"))
	for line in fh:lines() do
		local id, _, el = line:match("^(%d+),([^,]*),([^,]*)$")
		if id then tags[tonumber(id)] = el end
	end
	fh:close()
	for _, row in ipairs(ChaosSpellCombosConfig.rows) do
		ok(type(row.burst) == "table" and #row.burst >= 1 and #row.burst <= 2, "row " .. row.id .. " has one or two burst effects")
		for i, name in ipairs(row.burst or {}) do
			ok(V[name] ~= nil, "row " .. row.id .. ": effect " .. name .. " is a ChaosVfx name")
			local tag = V[name] and tags[V[name].id]
			ok(tag ~= nil, "row " .. row.id .. ": effect " .. name .. " is tagged")
			if row.kind == "reaction" and tag then
				local want = (i == 1 and row.first or row.second).element
				ok(tag == want or tag == "any" or (want == "earth" and tag == "physical"),
					"row " .. row.id .. ": effect " .. name .. " (" .. tag .. ") is of " .. want)
			end
		end
	end
	rawset(_G, "ChaosVfx", saved)
end

print(string.format("spell_combos_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

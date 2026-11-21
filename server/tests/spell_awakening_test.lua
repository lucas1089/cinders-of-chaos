-- Run from the server/ folder: luajit tests/spell_awakening_test.lua && lua5.3 tests/spell_awakening_test.lua (CI runs both)
-- O686 phase 7: spell awakening. Part A: spell_awakening_core.lua, spell_awakening_config.lua and data/spells/awakened.csv (Seals per source,
-- slot costs, the awaken decision and its refusals, dormant slots, the table: 149 rows, names, the design's four examples, the value band, every
-- signature kind planned on a cast, the cap, PvP off). Part B: spell_awakening.lua on a mocked engine with the real ChaosPassiveDealt of
-- passivetree_effects.lua (Seals by hook, awaken flow, refusals, the +10% and PvP, a mark, the signature of each kind run, the kill window,
-- switch off, a dormant spell frees its slot).

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

dofile("data/scripts/chaos/spell_awakening_core.lua")
local A = ChaosSpellAwakeningCore
local cfg = dofile("data/scripts/chaos/spell_awakening_config.lua")
local rc = dofile("data/scripts/chaos/spell_ranks_config.lua")

-- ---------------------------------------------------------------- A1. the config
eq(#A.check(cfg), 0, "the config is sound: " .. table.concat(A.check(cfg), "; "))
eq(cfg.maxSlots, 3, "three slots")
eq(cfg.bonus, 0.10, "+10%")
local costs = {{40, 36, 16}, {70, 60, 28}, {100, 90, 40}}
for i, c in ipairs(costs) do
	local s = A.slotCost(cfg, i)
	eq(s.waystone, c[1], "slot " .. i .. " waystone Seals")
	eq(s.rift, c[2], "slot " .. i .. " rift Seals")
	eq(s.pinnacle, c[3], "slot " .. i .. " pinnacle Seals")
end
eq(A.slotCost(cfg, 4), nil, "no fourth slot")
eq(A.slotCost(cfg, 0), nil, "no slot 0")
-- the design's table of hours: waystone / 4 + rift / 3
near(A.hours(cfg, 1), 22, 1e-9, "the first awakening: 22 hours of the ideal top content")
near(A.hours(cfg, 2), 37.5, 1e-9, "the second: 37.5 hours")
near(A.hours(cfg, 3), 55, 1e-9, "the third: 55 hours")
near(A.hours(cfg, 1) + A.hours(cfg, 2) + A.hours(cfg, 3), 114.5, 1e-9, "all three: 114.5 hours")
near(A.hours(cfg, 1) * cfg.rates.efficiency, 30.8, 0.1, "the first with 1.4x real efficiency: about 31 hours")
near(A.pinnacleHours(cfg, 1), 22.2, 0.1, "the Pinnacle Seals of the first take about the same 22 hours")
near(A.pinnacleHours(cfg, 3), 55.6, 0.1, "and of the third about 55")
eq(cfg.slots[1].waystone + cfg.slots[2].waystone + cfg.slots[3].waystone, 210, "all three: 210 Waystone Seals")
eq(cfg.slots[1].rift + cfg.slots[2].rift + cfg.slots[3].rift, 186, "186 Rift Seals")
eq(cfg.slots[1].pinnacle + cfg.slots[2].pinnacle + cfg.slots[3].pinnacle, 84, "84 Pinnacle Seals")
-- (bonus + signature) x the awakened spell's share of a class's damage is +3% each, +9% with three (design 5.1)
near((cfg.bonus + cfg.signature.target) * cfg.classShare, cfg.perSpell, 1e-9, "+10% and +5% of a 20% share is +3% of the class's damage")
-- the storage keys are the ones the design reserved (7.1)
eq(rc.storage.awakened, 7107501, "awakened count key")
eq(rc.storage.awakenedSlots, 7107520, "slot keys from 7107520")
eq(rc.storage.sealWaystone, 7107510, "Waystone Seals key")
eq(rc.storage.sealRift, 7107511, "Rift Seals key")
eq(rc.storage.sealPinnacle, 7107512, "Pinnacle Seals key")
-- a config with a bad slot table is refused
do
	local bad = dofile("data/scripts/chaos/spell_awakening_config.lua")
	bad.slots[2].waystone = 30
	ok(#A.check(bad) > 0, "a second slot cheaper than the first is refused")
	local bad2 = dofile("data/scripts/chaos/spell_awakening_config.lua")
	bad2.hours = {22, 37.5, 99}
	ok(#A.check(bad2) > 0, "a wrong hours table is refused")
end

-- ---------------------------------------------------------------- A2. the Seals of each source
eq(A.gain(cfg, "waystone", {tier = 15}), 0, "a waystone map of tier XV: no Seal (the Seals start at tier XVI)")
eq(A.gain(cfg, "waystone", {tier = 16}), 1, "tier XVI: 1")
eq(A.gain(cfg, "waystone", {tier = 16, first = true}), 2, "tier XVI, the first clear: 2")
eq(A.gain(cfg, "waystone", {tier = 25}), 1, "tier XXV: 1")
eq(A.gain(cfg, "waystone", {tier = 25, first = true}), 2, "tier XXV first clear: 2")
eq(A.gain(cfg, "waystone", {tier = 12, first = true}), 0, "a first clear below XVI gives none")
eq(A.gain(cfg, "waystone", {}), 0, "no tier: none")
eq(A.gain(cfg, "rift", {tier = 15}), 0, "a plain tier 15 rift: no Seal")
eq(A.gain(cfg, "rift", {tier = 16}), 1, "a Greater run that ends at tier 16: 1")
eq(A.gain(cfg, "rift", {tier = 16, climbed = true}), 2, "and +1 when the run climbs")
eq(A.gain(cfg, "rift", {tier = 40, climbed = false}), 1, "tier 40 not climbed: 1")
eq(A.gain(cfg, "pinnacle", {}), 2, "an Ascended boss kill: 2 for the member")
eq(A.gain(cfg, "nothing", {}), 0, "an unknown source: none")
eq(A.add(5, 3, 9999), 8, "add")
eq(A.add(9998, 5, 9999), 9999, "a held count stops at the cap")
eq(A.add(-4, 0, 9999), 0, "a negative count reads as 0")
eq(A.add(nil, 2, 9999), 2, "nil reads as 0")
-- the rates of the design (3.2): 4 + 3 + 0.72 Seals an hour
eq(cfg.rates.waystonePerHour, 4.0, "4 Waystone Seals an hour")
eq(cfg.rates.riftPerHour, 3.0, "3 Rift Seals an hour")
near(cfg.rates.pinnacleSealsPerHour, 0.72, 1e-9, "0.72 Pinnacle Seals an hour")

-- ---------------------------------------------------------------- A3. the decision
local function state(over)
	local st = {on = true, entry = true, known = true, rank = 20, f1 = 1, f2 = 2, awakened = false, slots = {0, 0, 0},
		seals = {waystone = 400, rift = 400, pinnacle = 400}}
	for k, v in pairs(over or {}) do
		st[k] = v
	end
	return st
end
local function why(over, slot)
	return A.decide(cfg, 20, state(over), slot)
end
eq(why({on = false}).why, "off", "off")
eq(why({entry = false}).why, "spell", "a spell with no row")
eq(why({known = false}).why, "unknown", "a spell the character does not know")
eq(why({rank = 19}).why, "rank", "rank 19")
eq(why({rank = 19}).need, 20, "the rank needed")
eq(why({f1 = 0}).why, "forms", "no Form I pick")
eq(why({f2 = 0}).why, "forms", "no Form II pick")
eq(why({awakened = true}).why, "already", "already awakened")
eq(why({slots = {5, 6, 7}}).why, "slot", "all three slots taken")
eq(why({slots = {5, 0, 0}}, 3).why, "slot", "slot 3 asked while slot 2 is the lowest free")
eq(why({slots = {5, 0, 0}}, 3).slot, 2, "the answer names the lowest free slot")
do
	local d = why({})
	eq(d.ok, true, "the first awakening is open")
	eq(d.slot, 1, "into slot 1")
	eq(d.cost.waystone, 40, "for 40 Waystone Seals")
	d = why({slots = {5, 0, 0}})
	eq(d.slot, 2, "the second awakening goes to slot 2")
	eq(d.cost.rift, 60, "for 60 Rift Seals")
	d = why({slots = {5, 6, 0}}, 3)
	eq(d.ok, true, "slot 3 asked and free")
	eq(d.cost.pinnacle, 40, "for 40 Pinnacle Seals")
	d = why({slots = {0, 6, 0}})
	eq(d.slot, 1, "a freed slot 1 is the lowest free one")
	d = why({seals = {waystone = 39, rift = 36, pinnacle = 16}})
	eq(d.ok, false, "one Seal short")
	eq(d.why, "seals", "refused for Seals")
	eq(d.need.waystone, 1, "it needs 1 more Waystone Seal")
	eq(d.need.rift, nil, "no Rift Seal is missing")
	d = why({seals = {waystone = 0, rift = 0, pinnacle = 0}})
	eq(d.need.waystone, 40, "the whole cost is missing")
	eq(d.need.pinnacle, 16, "all three kinds")
	local left = A.pay({waystone = 50, rift = 40, pinnacle = 20}, A.slotCost(cfg, 1))
	eq(left.waystone, 10, "pay: waystone")
	eq(left.rift, 4, "pay: rift")
	eq(left.pinnacle, 4, "pay: pinnacle")
end
eq(A.freeSlot(cfg, {1, 2, 3}), nil, "no free slot")
eq(A.freeSlot(cfg, {1, 0, 3}), 2, "slot 2 is free")
eq(A.held(cfg, {1, 0, 3}), 2, "two held")
do
	local dormant = A.dormantSlots(cfg, {10, 20, 0}, {[10] = true})
	eq(#dormant, 1, "one dormant spell")
	eq(dormant[1].slot, 2, "in slot 2")
	eq(dormant[1].spell, 20, "its spell")
	eq(#A.dormantSlots(cfg, {10, 20, 0}, {[10] = true, [20] = true}), 0, "none when both are known")
end
near(A.factor(cfg, false, 0.5), 1.10, 1e-9, "the factor: +10%")
near(A.factor(cfg, true, 0.5), 1.05, 1e-9, "against a player: +10% at the PvP factor, +5%")
near(rc.pvp.rank, 0.5, 1e-9, "the PvP factor of the rank is 0.5")
eq(rc.pvp.awakening, false, "the signature is off in PvP")

-- ---------------------------------------------------------------- A4. awakened.csv
local rows = A.parse(readFile("data/spells/awakened.csv"))
ok(rows ~= nil, "awakened.csv parses")
local count = 0
for _ in pairs(rows) do
	count = count + 1
end
eq(count, 149, "149 rows: every attack and heal spell with Forms")
-- every spell of forms.csv has a row, and no other
do
	local ids = {}
	local header
	for line in readFile("data/spells/forms.csv"):gmatch("[^\r\n]+") do
		if not header then
			header = true
		else
			ids[tonumber(line:match("^(%d+),"))] = true
		end
	end
	local n = 0
	for id in pairs(ids) do
		n = n + 1
		ok(rows[id] ~= nil, "spell " .. id .. " has an awakened row")
	end
	eq(n, 149, "forms.csv has the same 149 spells")
	eq(#A.problems(rows, cfg, ids), 0, "no problem: " .. table.concat(A.problems(rows, cfg, ids), "; "))
end
-- the design's four examples (3.3), word for word and in numbers
do
	local d = rows[206]
	eq(d.nameEn, "Cataclysm of Cinders", "Doomtide: the awakened name")
	eq(d.kind, "PULSE", "Doomtide: a ring that pulses")
	local pulse = d.parts[1].n
	eq(pulse.secs, 6, "Doomtide: the ring stays 6 s")
	eq(pulse.pulses, 3, "Doomtide: it pulses 3 times")
	near(pulse.pct, 0.40, 1e-9, "Doomtide: for 40%")
	eq(pulse.minHit, 3, "Doomtide: a pulse that hits 3 or more enemies")
	near(pulse.mana, 0.03, 1e-9, "Doomtide: returns 3% mana")
	d = rows[218]
	eq(d.nameEn, "Verdict Unbound", "Final Verdict: the awakened name")
	eq(d.kind, "LINE+MARK", "Final Verdict: a line that marks")
	eq(d.parts[1].n.len, 6, "Final Verdict: a line of 6 sqm")
	eq(d.parts[2].n.secs, 6, "Final Verdict: the mark lasts 6 s")
	near(d.parts[2].n.pct, 0.5, 1e-9, "Final Verdict: the marked enemy takes the next single target spell as a critical (+50%)")
	d = rows[148]
	eq(d.nameEn, "Iron Reckoning", "Judgment of Iron: the awakened name")
	eq(d.kind, "RINGS+CDCUT", "Judgment of Iron: rings and a cooldown cut")
	eq(d.parts[1].n.rings, 3, "Judgment of Iron: 3 rings")
	eq(d.parts[2].n.window, 8, "Judgment of Iron: kills in the next 8 s")
	eq(d.parts[2].n.cut, 1, "Judgment of Iron: cut 1 s of the cooldown")
	eq(d.parts[2].n.cap, 5, "Judgment of Iron: at most 5 s")
	d = rows[96]
	eq(d.nameEn, "Hall of Mends", "Mirror Mend: the awakened name")
	eq(d.kind, "REFLECT+SHIELD", "Mirror Mend: a reflect and a shield")
	eq(d.parts[1].n.radius, 4, "Mirror Mend: every ally in 4 sqm")
	near(d.parts[1].n.pct, 0.5, 1e-9, "Mirror Mend: at 50%")
	near(d.parts[2].n.pct, 0.03, 1e-9, "Mirror Mend: a shield of 3% max health")
	eq(d.parts[2].n.secs, 4, "Mirror Mend: for 4 s")
	eq(d.heal, true, "Mirror Mend is a heal")
end
-- every row is worth about +5% of the spell (the band 3% to 7%), the mean near the target
do
	local sum, lo, hi = 0, 1, 0
	for id, s in pairs(rows) do
		local v = A.value(s, cfg)
		sum = sum + v
		lo, hi = math.min(lo, v), math.max(hi, v)
		ok(v >= cfg.signature.band.min - 1e-9 and v <= cfg.signature.band.max + 1e-9, id .. " is worth " .. v .. " inside the band")
	end
	near(sum / count, cfg.signature.target, 0.005, "the mean signature is +5% of the spell")
	ok(lo > 0.03 and hi < 0.07, "the rows spread 3% to 7%: " .. lo .. " to " .. hi)
end
-- the kinds are the legal ones, damage kinds on damage spells, heal kinds on heals, and the table covers every kind
do
	local used = {}
	local roles = {damage = 0, heal = 0}
	for id, s in pairs(rows) do
		roles[s.heal and "heal" or "damage"] = roles[s.heal and "heal" or "damage"] + 1
		for _, p in ipairs(s.parts) do
			used[p.kind] = (used[p.kind] or 0) + 1
		end
	end
	for _, k in ipairs(A.damageKinds) do
		ok(used[k], "the kind " .. k .. " is used by a spell")
	end
	for _, k in ipairs(A.healKinds) do
		ok(used[k], "the heal kind " .. k .. " is used")
	end
	eq(roles.heal, 16, "16 heals")
	eq(roles.damage, 133, "133 attack spells")
end
-- names: all different in both languages, none equal to the spell's own
do
	local en, pt = {}, {}
	for id, s in pairs(rows) do
		ok(not en[s.nameEn] and not pt[s.namePt], id .. ": the names are unique")
		en[s.nameEn], pt[s.namePt] = true, true
		ok(s.nameEn ~= s.spell and s.namePt ~= "", id .. ": a new name")
	end
end
-- bad tables are refused
do
	local _, e1 = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,damage,,single,5,NOPE,,A,B\n")
	ok(e1 and e1:find("unknown kind"), "an unknown kind is refused")
	local _, e2 = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,damage,,single,5,LINE,LINE.nope=3,A,B\n")
	ok(e2 and e2:find("no number"), "an unknown number is refused")
	local _, e3 = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,damage,,single,5,LINE,MARK.pct=3,A,B\n")
	ok(e3 and e3:find("which the kind does not have"), "an override of a part the kind lacks is refused")
	local _, e4 = A.parse("id,spell\n1,X\n")
	ok(e4 and e4:find("no column"), "a missing column is refused")
	local r = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,heal,,single,5,LINE,,A,B\n")
	ok(#A.problems(r, cfg) > 0, "a damage kind on a heal spell is refused")
	local r2 = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,damage,,single,5,SHIELD,SHIELD.pct=0.5,A,B\n")
	ok(#A.problems(r2, cfg) > 0, "a shield of 50% and a signature worth nothing is refused")
	local r3 = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,damage,,single,5,ECHO,ECHO.pct=2,A,B\n")
	eq(#A.problems(r3, cfg), 0, "a saturated echo is held at the cap: inside the band")
end

-- ---------------------------------------------------------------- A5. the signature of a cast
local function pos(x, y)
	return {x = x, y = y, z = 7}
end
local function castOf(spec, over)
	local c = {heal = spec.heal, pvp = false, spellId = spec.id, base = 1000, total = 3000, main = {id = 1, pos = pos(110, 100)},
		caster = {id = 900, pos = pos(100, 100)}, hits = {{id = 1, pos = pos(110, 100), amount = 1000}, {id = 2, pos = pos(111, 100), amount = 1000},
		{id = 3, pos = pos(111, 101), amount = 1000}}, foes = {{id = 1, pos = pos(110, 100)}, {id = 2, pos = pos(111, 100)}, {id = 3, pos = pos(111, 101)}},
		lineFoes = {{id = 8, pos = pos(112, 100)}, {id = 9, pos = pos(113, 100)}}, allies = {{id = 71, pos = pos(110, 101), maxHealth = 2000},
		{id = 72, pos = pos(109, 100), maxHealth = 3000}}, healed = {{id = 70, pos = pos(110, 100), maxHealth = 5000, amount = 800}}}
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end
local function actionsOf(plan, op)
	local out = {}
	for _, a in ipairs(plan.actions) do
		if a.op == op then
			out[#out + 1] = a
		end
	end
	return out
end
-- Doomtide: a ring that stays 6 s and pulses 3 times for 40%
do
	local spec = rows[206]
	local plan = A.plan(spec, castOf(spec), cfg)
	local pulse = actionsOf(plan, "pulse")[1]
	ok(pulse ~= nil, "Doomtide plans a pulse")
	eq(pulse.pulses, 3, "3 pulses")
	eq(pulse.everyMs, 2000, "every 2 s over the 6 s the ring stays")
	eq(pulse.radius, 3, "radius 3")
	eq(pulse.minHit, 3, "a pulse of 3 returns the mana")
	-- 3 pulses x 3 enemies x 40% of 1000 is 3600, the cap is 25% of the cast's 3000
	eq(plan.planned, 3 * 3 * 400, "planned 3600")
	eq(plan.limit, 750, "the cap is 25% of the cast")
	ok(pulse.amount <= 400 * 750 / 3600 + 1 and pulse.amount >= 1, "the pulse is scaled to the cap: " .. pulse.amount)
	local total = pulse.amount * pulse.pulses * 3
	ok(total <= plan.limit, "the pulses together stay under the cap")
	-- a small ring is not scaled
	local small = {id = 1, parts = {{kind = "PULSE", n = {pulses = 2, pct = 0.1, secs = 4, minHit = 1, mana = 0, radius = 3}}}, heal = false, shape = "circle"}
	local p2 = A.plan(small, castOf(small), cfg)
	eq(actionsOf(p2, "pulse")[1].amount, 100, "under the cap: 10% of the hit")
	eq(p2.scaled, 1, "not scaled")
end
-- Verdict Unbound: a line of 6 sqm that hits all, a mark on each enemy hit
do
	local spec = rows[218]
	local plan = A.plan(spec, castOf(spec), cfg)
	local line = actionsOf(plan, "line")[1]
	ok(line ~= nil, "the line is planned")
	eq(#line.targets, 2, "the line hits the two enemies in it")
	eq(line.len, 6, "6 sqm")
	local mark = actionsOf(plan, "mark")[1]
	ok(mark ~= nil, "the mark is planned")
	eq(#mark.ids, 5, "every enemy hit and every enemy in the line is marked")
	eq(mark.secs, 6, "6 s")
	near(mark.pct, 0.5, 1e-9, "+50%")
	-- no enemy in the line: no line action, the mark stays
	local p2 = A.plan(spec, castOf(spec, {lineFoes = {}}), cfg)
	eq(#actionsOf(p2, "line"), 0, "no enemy in the line: no line")
	eq(#actionsOf(p2, "mark")[1].ids, 3, "the three enemies hit are marked")
end
-- Iron Reckoning: 3 rings, a cooldown cut by kills
do
	local spec = rows[148]
	local plan = A.plan(spec, castOf(spec), cfg)
	local rings = actionsOf(plan, "rings")[1]
	eq(rings.rings, 3, "3 rings")
	eq(rings.pos.x, 100, "an around spell: the rings are around the caster")
	local cut = actionsOf(plan, "cdcut")[1]
	eq(cut.spellId, 148, "the spell whose cooldown is cut")
	eq(cut.window, 8, "kills in the next 8 s")
	eq(cut.cap, 5, "at most 5 s")
	local take, used = A.cut(1, 5, 0)
	eq(take, 1, "a kill cuts 1 s")
	eq(used, 1, "used")
	take, used = A.cut(1, 5, 4.5)
	near(take, 0.5, 1e-9, "the cut stops at the cap")
	near(used, 5, 1e-9, "and the cap is reached")
	take = A.cut(1, 5, 5)
	eq(take, 0, "nothing more past the cap")
end
-- Hall of Mends: the heal reflects to the allies near, a shield on each mirror
do
	local spec = rows[96]
	local plan = A.plan(spec, castOf(spec), cfg)
	local reflect = actionsOf(plan, "reflect")[1]
	eq(#reflect.targets, 2, "reflected to the two allies near")
	eq(reflect.radius, 4, "within 4 sqm")
	ok(reflect.amount <= 400 and reflect.amount >= 1, "at most half the healed amount (800 x 50% = 400): " .. reflect.amount)
	local shield = actionsOf(plan, "shield")[1]
	eq(#shield.targets, 1, "a shield on the healed ally")
	eq(shield.targets[1].amount, 150, "3% of its 5000 max health")
	eq(shield.secs, 4, "for 4 s")
end
-- every other kind
do
	local function parse(kind, over, role, shape)
		local t = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X," .. (role or "damage") .. ",fire," .. (shape or "single") ..
			",30," .. kind .. "," .. (over or "") .. ",A,B\n")
		return t[1]
	end
	local spec = parse("ECHO", "ECHO.pct=0.5;ECHO.delay=1500")
	local plan = A.plan(spec, castOf(spec), cfg)
	local echo = actionsOf(plan, "echo")[1]
	eq(#echo.hits, 3, "an echo repeats every hit")
	eq(echo.delay, 1500, "after 1.5 s")
	ok(echo.hits[1].amount <= 500, "at most 50% of the hit")
	spec = parse("SHIELD", "SHIELD.pct=0.04;SHIELD.minHit=3")
	plan = A.plan(spec, castOf(spec), cfg)
	local sh = actionsOf(plan, "shield")[1]
	eq(sh.targets[1].id, 900, "the caster is shielded")
	near(sh.targets[1].pct, 0.04, 1e-9, "4% of its max health")
	plan = A.plan(spec, castOf(spec, {hits = {{id = 1, pos = pos(110, 100), amount = 1000}}}), cfg)
	eq(#actionsOf(plan, "shield"), 0, "a shield that needs 3 enemies is not given for 1")
	spec = parse("LEECH", "LEECH.pct=0.04")
	plan = A.plan(spec, castOf(spec), cfg)
	eq(actionsOf(plan, "leech")[1].amount, 120, "4% of the cast's 3000 damage")
	spec = parse("PULSE", "", "heal")
	plan = A.plan(spec, castOf(spec), cfg)
	ok(actionsOf(plan, "pulse")[1].heal, "a heal ring heals")
	-- the 3.1 rule: no signature in PvP
	spec = rows[206]
	plan = A.plan(spec, castOf(spec, {pvp = true}), cfg)
	eq(#plan.actions, 0, "PvP: no signature effect")
	eq(#A.plan(nil, castOf(spec), cfg).actions, 0, "no spec: nothing")
	-- a shield above the cap is cut to it
	spec = parse("SHIELD", "SHIELD.pct=0.5")
	plan = A.plan(spec, castOf(spec), cfg)
	near(actionsOf(plan, "shield")[1].targets[1].pct, cfg.signature.shieldMax, 1e-9, "a shield is held at the max share")
end
-- the line of an eight direction ray
do
	local foes = {{id = 1, pos = pos(103, 100)}, {id = 2, pos = pos(105, 100)}, {id = 3, pos = pos(105, 101)}, {id = 4, pos = pos(110, 100)}}
	local out = A.lineFoes(pos(100, 100), pos(103, 100), 6, foes, 1)
	eq(#out, 1, "the main target is left out, only the one on the line within 6")
	eq(out[1].id, 2, "the enemy at 5 sqm")
	eq(#A.lineFoes(pos(100, 100), pos(100, 100), 6, foes, 1), 0, "no direction: no line")
	local d = A.parse("id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n1,X,damage,,single,5,LINE+MARK,,A,B\n")[1]
	eq(A.lineLength(d), 6, "the line length of a spec")
	eq(A.lineLength(rows[206]), 0, "a spec with no line")
	eq(A.allyRadius(rows[96]), 4, "the ally radius of a reflect")
end
-- the mark
do
	local m = {untilMs = 5000, pct = 0.5}
	local f, spent = A.markFactor(m, 1000, true)
	near(f, 1.5, 1e-9, "a single target spell on a marked enemy: +50%")
	eq(spent, true, "the mark is spent")
	f, spent = A.markFactor(m, 1000, false)
	eq(f, 1, "an area spell does not spend it")
	eq(spent, false, "and does not spend it")
	f, spent = A.markFactor(m, 6000, true)
	eq(f, 1, "an expired mark gives nothing")
	eq(spent, true, "and is dropped")
	f, spent = A.markFactor(nil, 1000, true)
	eq(f, 1, "no mark")
end

-- ---------------------------------------------------------------- B. the engine side on a mocked engine
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
ORIGIN_SPELL = ORIGIN_SPELL or 3
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
function Chaos.t(_, f, ...) return string.format(f, ...) end
function Chaos.isTester(p) return p.tester == true end
ChaosOpcodes = {spellRanks = 168}
local sent = {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data} return true end
local function lastSent(action)
	for i = #sent, 1, -1 do
		if sent[i].action == action then
			return sent[i]
		end
	end
	return nil
end
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name)
	local o = {}
	function o:register() registered[name] = o end
	function o:type() end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:register() registered[name] = o end
	function o:interval() end
	function o:type() end
	return o
end
function TalkAction(name)
	local o = {}
	function o:register() registered[name] = o end
	function o:separator() end
	return o
end
function Condition() local c = {p = {}}; function c:setTicks() end; function c:setParameter(k, v) self.p[k] = v end; return c end
local scheduled = {}
function addEvent(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, ms = ms, args = {...}} end
local function runEvents()
	local guard = 0
	while #scheduled > 0 and guard < 200 do
		guard = guard + 1
		local e = table.remove(scheduled, 1)
		e.fn((table.unpack or unpack)(e.args))
	end
end
local clock = 5000000
os.mtime = function() return clock end
function doTargetCombat() end
local function tick(ms) clock = clock + ms end

dofile("data/scripts/chaos/passivetree_effects.lua")
local ev = registered["ChaosPassiveDealt"]
dofile("data/scripts/chaos/spell_ranks_core.lua")
local RC = dofile("data/scripts/chaos/spell_ranks_config.lua")
ChaosSpellRanksConfig = RC
dofile("data/scripts/chaos/spell_awakening.lua")
local AW = ChaosSpellAwakening
local R = ChaosSpellRanks
local P = ChaosSpellRanksCore
local AC = ChaosSpellAwakeningConfig
ok(registered["ChaosSpellAwakeningLogin"] and registered["ChaosSpellAwakeningLogout"] and registered["ChaosSpellAwakeningKill"], "login, logout and kill events")
ok(registered["/spellseal"], "the staff command")
eq(AW.on(), false, "the shipped switch is off")
eq(#AW.table() == 0 and 0 or 1, 1, "the table loaded from data/spells/awakened.csv")
eq(AW.nameOf(206), "Cataclysm of Cinders", "the awakened name, English")
eq(AW.nameOf(206, true), "Cataclismo de Cinzas", "the awakened name, pt-BR")
eq(AW.nameOf(1234), nil, "no row, no name")

R.catalog = {
	[206] = {id = 206, name = "Doomtide", heal = false, cooldownMs = 13000},
	[218] = {id = 218, name = "Final Verdict", heal = false, cooldownMs = 12000},
	[148] = {id = 148, name = "Judgment of Iron", heal = false, cooldownMs = 45000},
	[96] = {id = 96, name = "Mirror Mend", heal = true, cooldownMs = 8000},
	[19] = {id = 19, name = "Sunspear", heal = false, cooldownMs = 10000},
	[2] = {id = 2, name = "Gorehook", heal = false, cooldownMs = 12000},
}

local storage = {}
local castSpell
local nextId = 900
ChaosSupportsSpell = {cast = function(pid) return 900, castSpell end}
local creatures = {}
local function newPlayer(voc, over)
	nextId = nextId + 1
	local p = {pos = {x = 100, y = 100, z = 7}, id = 900, msgs = {}, learned = {}, mana = 100, maxMana = 1000, health = 3000, maxHealth = 3000}
	for k, v in pairs(over or {}) do p[k] = v end
	function p:getId() return self.id end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getVocation() return {getId = function() return voc or 2 end} end
	function p:getLevel() return 2000 end
	function p:getStorageValue(k) return storage[k] or -1 end
	function p:setStorageValue(k, v) storage[k] = v end
	function p:getPosition() local pp = self.pos; pp.sendMagicEffect = function() end; return pp end
	function p:getTarget() return self.target end
	function p:registerEvent() end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:hasLearnedSpell(name) return self.learned[name] == true end
	function p:addMana(v) self.mana = self.mana + v end
	function p:getMaxMana() return self.maxMana end
	function p:getHealth() return self.health end
	function p:getMaxHealth() return self.maxHealth end
	function p:getGroup() return {getAccess = function() return true end} end
	creatures[p.id] = p
	return p
end
local function newMonster(id, x, y)
	local m = {id = id, pos = {x = x or 101, y = y or 100, z = 7}, health = 5000}
	function m:getId() return id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return nil end
	function m:getPosition() local pp = self.pos; pp.sendMagicEffect = function() end; return pp end
	function m:getHealth() return self.health end
	function m:getMaxHealth() return 5000 end
	creatures[id] = m
	return m
end
function Creature(id) return creatures[id] end
function Player(id) local c = creatures[id]; return c and c:isPlayer() and c or nil end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end

local p = newPlayer(2)
local function setSpell(id, rank, f1, f2, awakened)
	storage[RC.storage.rankBase + id] = P.pack(rank, f1, f2, awakened)
end
local function seals(a, b, c)
	storage[RC.storage.sealWaystone], storage[RC.storage.sealRift], storage[RC.storage.sealPinnacle] = a, b, c
end
local function held()
	local s = AW.seals(p)
	return s.waystone, s.rift, s.pinnacle
end

-- ---------------------------------------------------------------- B1. switched off (the shipped state)
eq(AW.onWaystoneClear(p, 20, true), 0, "off: no Waystone Seal")
eq(AW.onRiftRun(p, 20, true), 0, "off: no Rift Seal")
eq(AW.onPinnacleKill(p), 0, "off: no Pinnacle Seal")
eq(storage[RC.storage.sealWaystone], nil, "off: no storage written")
setSpell(206, 20, 1, 2, false)
seals(500, 500, 500)
p.learned.Doomtide = true
eq(AW.awaken(p, 206, 1).why, "off", "off: awaken answers off")
eq(AW.isAwakened(p, 206), false, "off: nothing is awakened")
eq(AW.hitFactor(p, newMonster(501), ORIGIN_SPELL, COMBAT_FIREDAMAGE, COMBAT_NONE), 1, "off: factor 1")
eq(AW.sync(p), 0, "off: sync does nothing")
storage = {}

-- the switch of the ranks alone is not enough: awakening has its own
RC.enabled = true
AC.enabled = false
eq(AW.on(), false, "awakening off by its own switch")
eq(AW.onWaystoneClear(p, 20, true), 0, "its own switch: no Seal")
AC.enabled = true
eq(AW.on(), true, "both on")

-- ---------------------------------------------------------------- B2. the Seals from each source
storage = {}
eq(AW.onWaystoneClear(p, 15, true), 0, "tier XV: no Seal")
eq(AW.onWaystoneClear(p, 16, false), 1, "tier XVI: 1 Waystone Seal")
eq(AW.onWaystoneClear(p, 20, true), 2, "tier XX first clear: 2")
eq(select(1, held()), 3, "three Waystone Seals held")
ok(p.msgs[#p.msgs]:find("Waystone Seal +2 (3 held)", 1, true), "the message names the Seal and the count")
eq(lastSent("awakened").data.seals[1], 3, "the state is pushed with the count")
eq(AW.onRiftRun(p, 15, true), 0, "a rift run below 16: none")
eq(AW.onRiftRun(p, 16, false), 1, "a run ending at tier 16: 1 Rift Seal")
eq(AW.onRiftRun(p, 19, true), 2, "a run that climbs: 2")
eq(select(2, held()), 3, "three Rift Seals held")
eq(AW.onPinnacleKill(p), 2, "a pinnacle kill: 2")
eq(AW.onPinnacleKill(p), 2, "and the next kill 2 more")
eq(select(3, held()), 4, "four Pinnacle Seals held")
seals(9998, 0, 0)
eq(AW.onWaystoneClear(p, 25, true), 1, "a count at 9998 takes 1 and stops at the cap")
eq(select(1, held()), 9999, "held at the cap")
eq(AW.onWaystoneClear(p, 25, true), 0, "nothing past the cap")
-- testers earn none, unless the config says
do
	local t = newPlayer(2, {tester = true, id = 905})
	seals(0, 0, 0)
	eq(AW.onWaystoneClear(t, 25, true), 0, "a tester earns no Seal")
	AC.testersEarn = true
	eq(AW.onWaystoneClear(t, 25, true), 2, "a tester earns them when testersEarn is on")
	AC.testersEarn = false
	creatures[905] = nil
end

-- ---------------------------------------------------------------- B3. awaken
storage = {}
p.learned = {Doomtide = true, ["Final Verdict"] = true, ["Judgment of Iron"] = true, ["Mirror Mend"] = true, Sunspear = true}
seals(500, 500, 500)
setSpell(206, 19, 1, 2, false)
eq(AW.awaken(p, 206, 1).why, "rank", "rank 19: refused")
setSpell(206, 20, 0, 2, false)
eq(AW.awaken(p, 206, 1).why, "forms", "no Form I pick: refused")
setSpell(206, 20, 1, 0, false)
eq(AW.awaken(p, 206, 1).why, "forms", "no Form II pick: refused")
setSpell(206, 20, 1, 2, false)
eq(AW.awaken(p, 9999, 1).why, "spell", "a spell with no row: refused")
eq(AW.awaken(p, nil, 1).why, "spell", "no spell id: refused")
for _, junk in ipairs({1 / 0, -1 / 0, 0 / 0, 2.5, "x", {}, true, 1e12}) do
	local d = AW.awaken(p, junk, 1)
	eq(d.ok, false, "a junk spell id is refused: " .. tostring(junk))
	eq(d.why, "spell", "as no spell: " .. tostring(junk))
	ok(d.spell == nil or (d.spell == d.spell and d.spell ~= 1 / 0 and d.spell ~= -1 / 0), "no infinite number goes back to the client")
end
p.learned.Doomtide = nil
eq(AW.awaken(p, 206, 1).why, "unknown", "a spell the character does not know: refused")
p.learned.Doomtide = true
setSpell(206, 20, 1, 2, false)
for _, junk in ipairs({1 / 0, 0 / 0, 1.5, "x"}) do
	local d = AW.awaken(p, 206, junk)
	eq(d.ok, false, "a junk slot is refused: " .. tostring(junk))
	ok(d.why == "slot" or d.why == "seals", "as a slot (or, with too few Seals, as Seals): " .. tostring(d.why))
end
seals(39, 36, 16)
do
	local d = AW.awaken(p, 206, 1)
	eq(d.why, "seals", "one Waystone Seal short: refused")
	eq(d.need.waystone, 1, "it says how many")
	eq(select(1, held()), 39, "nothing was paid")
	eq(AW.isAwakened(p, 206), false, "not awakened")
end
seals(40, 36, 16)
do
	local before = #sent
	local d = AW.awaken(p, 206, 1)
	eq(d.ok, true, "awakened with the exact Seals")
	eq(d.slot, 1, "in slot 1")
	eq(d.name, "Cataclysm of Cinders", "the answer carries the new name")
	eq(d.namePt, "Cataclismo de Cinzas", "and the pt-BR name")
	local w, r, pn = held()
	eq(w + r + pn, 0, "the Seals are spent")
	eq(AW.isAwakened(p, 206), true, "bit 9 is set")
	local rank, f1, f2, aw = P.unpack(storage[RC.storage.rankBase + 206])
	eq(rank, 20, "the rank is kept")
	eq(f1, 1, "the Form I pick is kept")
	eq(f2, 2, "the Form II pick is kept")
	eq(aw, true, "the packed state says awakened")
	eq(AW.slots(p)[1], 206, "slot 1 holds the spell")
	eq(storage[RC.storage.awakened], 1, "one awakened spell held")
	ok(p.msgs[#p.msgs]:find("Doomtide awakens: Cataclysm of Cinders", 1, true), "the message")
	eq(AW.awaken(p, 206, 1).why, "already", "the same spell again: refused")
end
-- the second awakening costs the second slot, and goes to the lowest free slot
do
	setSpell(218, 20, 2, 1, false)
	seals(69, 60, 28)
	eq(AW.awaken(p, 218, 2).why, "seals", "slot 2 costs 70: 69 is not enough")
	seals(70, 60, 28)
	eq(AW.awaken(p, 218, 3).why, "slot", "slot 3 asked while slot 2 is the lowest free: refused")
	eq(AW.awaken(p, 218, 2).ok, true, "slot 2 for 70 / 60 / 28")
	eq(AW.slots(p)[2], 218, "slot 2 holds Final Verdict")
	setSpell(148, 20, 1, 1, false)
	seals(100, 90, 40)
	eq(AW.awaken(p, 148, nil).slot, 3, "no slot asked: the lowest free one, 3")
	eq(storage[RC.storage.awakened], 3, "three held")
	setSpell(96, 20, 1, 1, false)
	seals(999, 999, 999)
	eq(AW.awaken(p, 96, nil).why, "slot", "a fourth awakening: no slot")
end
-- the request on opcode 168
do
	storage = {}
	setSpell(19, 20, 1, 1, false)
	seals(40, 36, 16)
	local before = #sent
	eq(AW.receive(p, {action = "awaken", data = {spell = 19, slot = 1}}), true, "the request is answered")
	local a = lastSent("awaken")
	eq(a.data.ok, true, "the answer: ok")
	eq(a.opcode, 168, "on opcode 168")
	eq(a.data.spell, 19, "for the spell")
	eq(lastSent("awakened").data.held, 1, "then the new state")
	eq(AW.receive(p, {action = "open"}), false, "another action is not this one")
	-- a refusal reaches the client with its reason
	AW.receive(p, {action = "awaken", data = {spell = 206, slot = 2}})
	tick(1000)
	AW.receive(p, {action = "awaken", data = {spell = 206, slot = 2}})
	eq(lastSent("awaken").data.ok, false, "a refusal is sent")
	ok(lastSent("awaken").data.why ~= nil, "with its reason")
end

-- ---------------------------------------------------------------- B4. the bonus, through the real ChaosPassiveDealt
storage = {}
local troll = newMonster(501)
p.target = troll
local function hit(attacker, target, ctype, amount, ctype2, amount2)
	local d1, _, d2 = ev.onHealthChange(target, attacker, amount, ctype, amount2 or 0, ctype2 or COMBAT_NONE, ORIGIN_SPELL)
	return d1, d2
end
setSpell(206, 20, 1, 1, false)
castSpell = 206
local plain = hit(p, troll, COMBAT_FIREDAMAGE, -1000)
setSpell(206, 20, 1, 1, true)
local awake = hit(p, troll, COMBAT_FIREDAMAGE, -1000)
near(awake / plain, 1.10, 0.005, "an awakened spell hits 10% harder than the same spell not awakened")
-- the secondary part follows
local d1, d2 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000, COMBAT_FIREDAMAGE, -200)
near(d2 / d1, 0.2, 0.01, "the secondary part keeps its share")
-- a spell that is not awakened is plain
setSpell(218, 20, 1, 1, false)
castSpell = 218
near(hit(p, troll, COMBAT_FIREDAMAGE, -1000) / plain, 1, 0.005, "another spell, not awakened: plain")
-- PvP: the factor follows the PvP share of the rank
castSpell = 206
local foe = newPlayer(2, {id = 777})
creatures[777] = foe
setSpell(206, 20, 1, 1, true)
local pvp = hit(p, foe, COMBAT_FIREDAMAGE, -1000)
setSpell(206, 20, 1, 1, false)
local pvpPlain = hit(p, foe, COMBAT_FIREDAMAGE, -1000)
near(pvp / pvpPlain, 1.05, 0.01, "PvP: +5% (the +10% at the PvP factor of 0.5)")
setSpell(206, 20, 1, 1, true)
creatures[777] = nil
-- a heal is +10% too
setSpell(96, 20, 1, 1, true)
castSpell = 96
local ally = newPlayer(2, {id = 778})
local healAwake = ev.onHealthChange(ally, p, 800, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
setSpell(96, 20, 1, 1, false)
local healPlain = ev.onHealthChange(ally, p, 800, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
near(healAwake / healPlain, 1.10, 0.01, "an awakened heal is +10%")
creatures[778] = nil
-- a hit outside a spell's cast context, and a weapon hit: nothing
castSpell = nil
setSpell(206, 20, 1, 1, true)
near(hit(p, troll, COMBAT_FIREDAMAGE, -1000), -1000, 0.5, "no cast context: nothing")
-- switch off: back to plain
castSpell = 206
RC.enabled = false
local off = ev.onHealthChange(troll, p, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(off, -1000, "off: a plain hit")
RC.enabled = true

-- ---------------------------------------------------------------- B5. the mark
storage = {}
castSpell = 19 -- Sunspear: a single target spell
setSpell(19, 0, 0, 0, false)
AW.marks[501] = {owner = 900, untilMs = clock + 5000, pct = 0.5}
local marked = hit(p, troll, COMBAT_HOLYDAMAGE, -1000)
near(marked / -1000, 1.5, 0.01, "a single target spell on a marked enemy: +50%")
eq(AW.marks[501], nil, "the mark is spent")
near(hit(p, troll, COMBAT_HOLYDAMAGE, -1000) / -1000, 1, 0.01, "once: the next hit is plain")
-- an area spell does not spend it
castSpell = 206
setSpell(206, 0, 0, 0, false)
AW.marks[501] = {owner = 900, untilMs = clock + 5000, pct = 0.5}
near(hit(p, troll, COMBAT_FIREDAMAGE, -1000) / -1000, 1, 0.01, "Doomtide (an area spell) does not spend a mark")
ok(AW.marks[501] ~= nil, "the mark stays")
-- another player's mark is not mine
castSpell = 19
AW.marks[501] = {owner = 12345, untilMs = clock + 5000, pct = 0.5}
near(hit(p, troll, COMBAT_HOLYDAMAGE, -1000) / -1000, 1, 0.01, "the mark of another player is not spent by me")
-- an expired mark
AW.marks[501] = {owner = 900, untilMs = clock - 1, pct = 0.5}
near(hit(p, troll, COMBAT_HOLYDAMAGE, -1000) / -1000, 1, 0.01, "an expired mark gives nothing")
eq(AW.marks[501], nil, "and is dropped")
AW.marks = {}

-- ---------------------------------------------------------------- B6. the signature on a cast
local F = ChaosSpellForms
ok(F ~= nil, "the Forms library is loaded")
local calls = {}
local fxCalls = {}
local cuts = {}
F.sendFx = function(pos, element, role) fxCalls[#fxCalls + 1] = {element, role} return true end
F.shortenCooldown = function(player, spellId, pct) cuts[#cuts + 1] = {spellId, pct} end
local foesList, alliesList = {}, {}
F.ops = {
	withContext = function(player, serial, spellId, fn) calls[#calls + 1] = {"ctx", serial, spellId}; fn() end,
	dealHit = function(player, target, ctype, amount, role, el) calls[#calls + 1] = {"hit", target:getId(), amount, role, el} end,
	dealHeal = function(player, target, amount) calls[#calls + 1] = {"heal", target:getId(), amount} end,
	addShield = function(target, amount, secs) calls[#calls + 1] = {"shield", target:getId(), amount, secs} end,
	foesNear = function(player, pos, radius, pvp)
		local out = {}
		for _, m in ipairs(foesList) do out[#out + 1] = {id = m:getId(), pos = m:getPosition(), creature = m} end
		return out
	end,
	alliesNear = function(player, pos, radius) return alliesList end,
	guarded = function(fn, ...) return fn(...) end,
}
local function count(kind)
	local n = 0
	for _, c in ipairs(calls) do if c[1] == kind then n = n + 1 end end
	return n
end
local function reset()
	calls, fxCalls, cuts = {}, {}, {}
	scheduled = {}
	AW.rings, AW.windows, AW.marks = {}, {}, {}
end
local function buffer(spellId, hits)
	return {spellId = spellId, serial = 77, hits = hits}
end
local m1, m2, m3 = newMonster(601, 110, 100), newMonster(602, 111, 100), newMonster(603, 111, 101)
local m4 = newMonster(604, 112, 100)
local function info(el, ctype, over)
	local i = {heal = false, pvp = false, element = el, ctype = ctype or COMBAT_FIREDAMAGE, mainId = 601, mainPos = {x = 110, y = 100, z = 7},
		hits = {{id = 601, pos = {x = 110, y = 100, z = 7}, amount = 1000, maxHealth = 5000}, {id = 602, pos = {x = 111, y = 100, z = 7}, amount = 1000,
		maxHealth = 5000}, {id = 603, pos = {x = 111, y = 101, z = 7}, amount = 1000, maxHealth = 5000}}, allies = {}}
	for k, v in pairs(over or {}) do i[k] = v end
	return i
end
p.pos = {x = 100, y = 100, z = 7}
foesList = {m1, m2, m3}

-- not awakened: nothing runs
reset()
setSpell(206, 20, 1, 1, false)
AW.onCast(p, buffer(206, {}), info("fire"))
eq(#calls, 0, "a spell that is not awakened runs no signature")
-- Doomtide: the ring pulses, each pulse inside the context of the spell, mana back
setSpell(206, 20, 1, 1, true)
p.mana = 100
AW.onCast(p, buffer(206, {}), info("fire"))
eq(count("hit"), 0, "the ring does not hit at the cast: it pulses later")
eq(#scheduled, 1, "the first pulse is scheduled")
eq(scheduled[1].ms, 2000, "2 s apart (6 s / 3 pulses)")
runEvents()
eq(count("hit"), 9, "3 pulses x 3 enemies")
eq(count("ctx") >= 4, true, "every pulse runs inside the spell's cast context")
eq(calls[1][3], 206, "the context is the spell's")
local first
for _, c in ipairs(calls) do if c[1] == "hit" then first = c break end end
ok(first[3] <= 400 and first[3] >= 1, "each pulse hits for at most 40% of the cast's hit, held by the cap: " .. first[3])
eq(first[5], "fire", "in the spell's own element")
local total = 0
for _, c in ipairs(calls) do if c[1] == "hit" then total = total + c[3] end end
ok(total <= 750 + 9, "the signature stays inside 25% of the cast's 3000: " .. total)
eq(p.mana, 100 + 3 * 30, "each pulse that hit 3 enemies returned 3% of 1000 mana")
local ground = 0
for _, f in ipairs(fxCalls) do if f[2] == "ground" then ground = ground + 1 end end
eq(ground, 3, "a ground effect on each pulse")
eq(AW.rings[900], 0, "the ring is over: the running count is back to 0")
-- a pulse that hits fewer than 3 enemies returns no mana
reset()
foesList = {m1, m2}
p.mana = 100
AW.onCast(p, buffer(206, {}), info("fire"))
runEvents()
eq(p.mana, 100, "2 enemies in the ring: no mana back")
foesList = {m1, m2, m3}
-- at most maxRings rings at once
reset()
for i = 1, 6 do AW.onCast(p, buffer(206, {}), info("fire")) end
eq(AW.rings[900], AC.signature.maxRings, "at most maxRings rings running at once")
runEvents()
-- Verdict Unbound: a line, a mark
reset()
setSpell(218, 20, 1, 1, true)
local m5 = newMonster(605, 105, 100) -- on the line from the caster (100, 100) through the target (110, 100), within 6 sqm
foesList = {m1, m2, m3, m4, m5}
p.pos = {x = 100, y = 100, z = 7}
AW.onCast(p, buffer(218, {}), info("holy", COMBAT_HOLYDAMAGE, {mainId = 601, mainPos = {x = 110, y = 100, z = 7},
	hits = {{id = 601, pos = {x = 110, y = 100, z = 7}, amount = 1000, maxHealth = 5000}}}))
local lineHits = {}
for _, c in ipairs(calls) do if c[1] == "hit" then lineHits[#lineHits + 1] = c[2] end end
eq(#lineHits, 1, "the line hits the one enemy on it (the one 12 sqm out is not)")
eq(lineHits[1], 605, "the enemy on the line")
eq(calls[1][1], "ctx", "inside the spell's cast context")
ok(AW.marks[601] ~= nil, "the enemy hit is marked")
ok(AW.marks[605] ~= nil, "and the enemy in the line")
eq(AW.marks[601].owner, 900, "the mark is the player's")
eq(AW.marks[601].pct, 0.5, "+50%")
ok(AW.marks[601].untilMs == clock + 6000, "for 6 s")
-- the next single target spell of the player on the marked enemy is +50%, once (Sunspear is a single target spell)
castSpell = 19
setSpell(19, 0, 0, 0, false)
local base = hit(p, newMonster(777, 120, 100), COMBAT_HOLYDAMAGE, -1000)
near(hit(p, m1, COMBAT_HOLYDAMAGE, -1000) / base, 1.5, 0.01, "the marked enemy takes the next single target spell +50%")
near(hit(p, m1, COMBAT_HOLYDAMAGE, -1000) / base, 1, 0.01, "once")
-- Iron Reckoning: rings and the cooldown window
reset()
setSpell(148, 20, 1, 1, true)
foesList = {m1, m2, m3}
AW.onCast(p, buffer(148, {}), info("physical", COMBAT_PHYSICALDAMAGE))
eq(count("hit"), 3, "the first ring hits the 3 enemies at once")
runEvents()
eq(count("hit"), 9, "3 rings x 3 enemies")
ok(AW.windows[900] and AW.windows[900][1].spellId == 148, "the cooldown window is open")
eq(AW.onKill(p), 1, "a kill in the window cuts 1 s")
eq(cuts[1][1], 148, "the cooldown of the spell")
near(cuts[1][2], 1000 * 100 / 45000, 1e-6, "as a share of its 45 s cooldown")
for i = 1, 6 do AW.onKill(p) end
local cutTotal = 0
for _, c in ipairs(cuts) do cutTotal = cutTotal + c[2] * 45000 / 100 end
near(cutTotal / 1000, 5, 0.01, "at most 5 s in all")
tick(9000)
eq(AW.onKill(p), 0, "after the 8 s window: nothing")
eq(AW.windows[900][1], nil, "the expired window is dropped")
-- the kill event
reset()
AW.windows[900] = {{spellId = 148, untilMs = clock + 5000, cut = 1, cap = 5, used = 0}}
registered["ChaosSpellAwakeningKill"].onKill(p, troll)
eq(#cuts, 1, "the kill event cuts the cooldown")
registered["ChaosSpellAwakeningKill"].onKill(p, ally)
eq(#cuts, 1, "a player's death cuts nothing")
-- Mirror Mend: the reflect and the shields
reset()
setSpell(96, 20, 1, 1, true)
alliesList = {{id = 71, pos = {x = 110, y = 101, z = 7}, maxHealth = 2000}, {id = 72, pos = {x = 109, y = 100, z = 7}, maxHealth = 3000}}
local a71, a72, a70 = newPlayer(2, {id = 71}), newPlayer(2, {id = 72}), newPlayer(2, {id = 70})
creatures[71], creatures[72], creatures[70] = a71, a72, a70
a70.maxHealth = 5000
AW.onCast(p, buffer(96, {}), {heal = true, pvp = false, element = nil, ctype = COMBAT_HEALING, mainId = 70, mainPos = {x = 110, y = 100, z = 7},
	hits = {{id = 70, pos = {x = 110, y = 100, z = 7}, amount = 800, maxHealth = 5000}}, allies = {}})
eq(count("heal"), 2, "the heal reflects to the two allies near")
local reflectAmount = nil
for _, c in ipairs(calls) do if c[1] == "heal" then reflectAmount = c[3] end end
ok(reflectAmount >= 1 and reflectAmount <= 400, "at most half the healed amount: " .. reflectAmount)
eq(count("shield"), 1, "a shield on the healed ally")
for _, c in ipairs(calls) do if c[1] == "shield" then eq(c[3], 150, "3% of 5000"); eq(c[4], 4, "for 4 s") end end
-- the other kinds on the engine: an echo, a shield, a leech, a heal ring, a heal echo (rows of their own, the table is put back after)
do
	local header = "id,spell,role,element,shape,cooldown,kind,over,name_en,name_pt\n"
	local rows301 = A.parse(header ..
		"301,Echo Test,damage,fire,single,12,ECHO,ECHO.pct=0.5;ECHO.delay=1500,Echo A,Eco A\n" ..
		"302,Shield Test,damage,fire,circle,12,ECHO+SHIELD,ECHO.pct=0.1;SHIELD.pct=0.04;SHIELD.secs=5;SHIELD.minHit=3,Shield A,Escudo A\n" ..
		"303,Leech Test,damage,fire,single,12,ECHO+LEECH,ECHO.pct=0.1;LEECH.pct=0.04,Leech A,Sugar A\n" ..
		"304,Heal Ring,heal,,single,1,PULSE,PULSE.pulses=2;PULSE.pct=0.2;PULSE.secs=4;PULSE.minHit=1;PULSE.mana=0;PULSE.radius=3,Heal A,Cura A\n" ..
		"305,Heal Echo,heal,,single,1,ECHO,ECHO.pct=0.3;ECHO.delay=2000,Heal B,Cura B\n")
	ok(rows301 ~= nil, "the test rows parse")
	local saved = AW.rows
	local merged = {}
	for id, e in pairs(AW.table()) do merged[id] = e end
	for id, e in pairs(rows301) do merged[id] = e end
	AW.setTable(merged)
	for id = 301, 305 do setSpell(id, 20, 1, 1, true) end
	-- an echo: every hit again after 1.5 s, held by the cap (3 x 500 = 1500 planned, 750 allowed: halved)
	reset()
	foesList = {m1, m2, m3}
	AW.onCast(p, buffer(301, {}), info("fire"))
	eq(count("hit"), 0, "an echo is not at once")
	eq(scheduled[1].ms, 1500, "after 1.5 s")
	runEvents()
	eq(count("hit"), 3, "the three hits repeat")
	for _, c in ipairs(calls) do if c[1] == "hit" then eq(c[3], 250, "each at 250 (500 held to the cap, halved)") end end
	-- a shield for the caster: 4% of max health when 3 enemies were hit
	reset()
	AW.onCast(p, buffer(302, {}), info("fire"))
	local shieldCall
	for _, c in ipairs(calls) do if c[1] == "shield" then shieldCall = c end end
	ok(shieldCall ~= nil, "the caster is shielded")
	eq(shieldCall[2], 900, "the caster")
	eq(shieldCall[3], 120, "4% of 3000 max health")
	eq(shieldCall[4], 5, "for 5 s")
	-- one enemy hit: no shield (minHit 3)
	reset()
	AW.onCast(p, buffer(302, {}), info("fire", COMBAT_FIREDAMAGE, {hits = {{id = 601, pos = {x = 110, y = 100, z = 7}, amount = 1000, maxHealth = 5000}}}))
	eq(count("shield"), 0, "a shield that needs 3 enemies hit is not given for 1")
	-- a leech: 4% of the cast's 3000 damage
	reset()
	AW.onCast(p, buffer(303, {}), info("fire"))
	local leech
	for _, c in ipairs(calls) do if c[1] == "heal" and c[2] == 900 then leech = c end end
	ok(leech ~= nil, "the caster is healed")
	eq(leech[3], 120, "4% of 3000")
	-- a heal ring heals the allies near, twice
	reset()
	alliesList = {{id = 71, pos = {x = 110, y = 101, z = 7}, maxHealth = 2000}}
	AW.onCast(p, buffer(304, {}), {heal = true, pvp = false, element = nil, ctype = COMBAT_HEALING, mainId = 70, mainPos = {x = 110, y = 100, z = 7},
		hits = {{id = 70, pos = {x = 110, y = 100, z = 7}, amount = 1000, maxHealth = 5000}}, allies = {}})
	eq(count("heal"), 0, "a heal ring pulses later")
	runEvents()
	eq(count("heal"), 2, "two pulses on the one ally near")
	for _, c in ipairs(calls) do if c[1] == "heal" then eq(c[3], 62, "20% of the 1000 heal is 200, held to the cap (2 pulses x 2 targets = 800 planned, 250 allowed): 62") end end
	-- a heal echo
	reset()
	AW.onCast(p, buffer(305, {}), {heal = true, pvp = false, element = nil, ctype = COMBAT_HEALING, mainId = 70, mainPos = {x = 110, y = 100, z = 7},
		hits = {{id = 70, pos = {x = 110, y = 100, z = 7}, amount = 1000, maxHealth = 5000}}, allies = {}})
	eq(scheduled[1].ms, 2000, "a heal echo after 2 s")
	runEvents()
	eq(count("heal"), 1, "the heal repeats once")
	for _, c in ipairs(calls) do if c[1] == "heal" then eq(c[3], 250, "30% of 1000 = 300, held to the cap of 25%: 250") end end
	AW.setTable(saved or false)
	AW.rows = nil
end
-- PvP: no signature
reset()
AW.onCast(p, buffer(206, {}), info("fire", COMBAT_FIREDAMAGE, {pvp = true}))
runEvents()
eq(#calls, 0, "PvP: the signature is off")
eq(#scheduled, 0, "PvP: nothing is scheduled")
-- the switch off
reset()
RC.enabled = false
AW.onCast(p, buffer(206, {}), info("fire"))
eq(#calls + #scheduled, 0, "switch off: no signature")
RC.enabled = true
-- no Forms helpers (a state without the Forms engine): nothing, no error
do
	reset()
	local ops = F.ops
	F.ops = nil
	AW.onCast(p, buffer(206, {}), info("fire"))
	eq(#calls, 0, "no Forms helpers: nothing")
	F.ops = ops
end

-- ---------------------------------------------------------------- B7. dormant slots and the reconcile at login
storage = {}
setSpell(206, 20, 1, 1, true)
setSpell(218, 20, 1, 1, true)
storage[RC.storage.awakenedSlots] = 206
storage[RC.storage.awakenedSlots + 1] = 218
storage[RC.storage.awakened] = 2
p.learned = {Doomtide = true, ["Final Verdict"] = true}
eq(AW.sync(p), 0, "both spells known: nothing freed")
-- the character changes class: Final Verdict is no longer known
p.learned = {Doomtide = true}
eq(AW.sync(p), 1, "a dormant spell frees its slot at login")
eq(AW.slots(p)[2], 0, "slot 2 is empty")
eq(AW.isAwakened(p, 218), false, "its awakened bit is cleared")
local rank, f1, f2 = P.unpack(storage[RC.storage.rankBase + 218])
eq(rank, 20, "its rank is kept")
eq(f1, 1, "and its Forms")
eq(storage[RC.storage.awakened], 1, "one awakened spell held")
eq(AW.isAwakened(p, 206), true, "the known one stays awakened")
-- it comes back when learned again, but awakening is paid again
p.learned = {Doomtide = true, ["Final Verdict"] = true}
seals(0, 0, 0)
eq(AW.awaken(p, 218, nil).why, "seals", "learning it again does not return the Seals: awakening costs again")
seals(70, 60, 28)
eq(AW.awaken(p, 218, nil).ok, true, "awakened again into the free slot 2 for the price of slot 2")
-- a slot whose spell has no bit (a reset of the rank block, a reassigned id) is freed
setSpell(206, 0, 0, 0, false)
eq(AW.sync(p), 1, "a slot with no awakened bit is freed")
eq(AW.slots(p)[1], 0, "slot 1 is empty")
eq(storage[RC.storage.awakened], 1, "the count follows")
-- the login event syncs
do
	storage = {}
	setSpell(206, 20, 1, 1, true)
	storage[RC.storage.awakenedSlots] = 206
	p.learned = {}
	registered["ChaosSpellAwakeningLogin"].onLogin(p)
	eq(AW.slots(p)[1], 0, "the login event frees a dormant slot")
end

-- ---------------------------------------------------------------- B7b. a spell without needlearn (every class spell of the game)
-- The live pass (O686 phase 8): the engine never lists such a spell as learned, so `hasLearnedSpell` is false for it; the class and the level decide
do
	storage = {}
	local savedBook = rawget(_G, "ChaosSpellbook")
	local book = {{name = "Doomtide", level = 200, vocations = {2, 3}}, {name = "Final Verdict", level = 100, vocations = {2}, needLearn = true}}
	ChaosSpellbook = {get = function() return book end}
	p.learned = {} -- nothing is "learned" by the engine's list
	setSpell(206, 20, 1, 1, false)
	seals(500, 500, 500)
	eq(AW.awaken(p, 206, 1).ok, true, "a needlearn=0 spell the class lists at this level is known: awakened with nothing in the learned list")
	eq(AW.sync(p), 0, "and a login does not free its slot as dormant")
	eq(AW.slots(p)[1], 206, "the slot stays")
	book[1].vocations = {5}
	eq(AW.sync(p), 1, "a class change to a class that does not list it: dormant, as the design says")
	setSpell(206, 20, 1, 1, false)
	seals(500, 500, 500)
	eq(AW.awaken(p, 206, 1).why, "unknown", "a spell another class lists is unknown")
	book[1].vocations, book[1].level = {2}, 2500
	eq(AW.awaken(p, 206, 1).why, "unknown", "a spell above the level is unknown")
	book[1].level = 200
	p.learned = {["Final Verdict"] = true}
	setSpell(218, 20, 1, 1, false)
	eq(AW.awaken(p, 218, nil).ok, true, "a needlearn spell still needs the learned list: learned, known")
	p.learned = {}
	storage[RC.storage.awakenedSlots] = 0
	setSpell(218, 20, 1, 1, false)
	eq(AW.awaken(p, 218, nil).why, "unknown", "a needlearn spell that is not learned is unknown")
	ChaosSpellbook = savedBook
	storage = {}
end

-- ---------------------------------------------------------------- B7c. a class change frees the dormant slot at once (O686 phase 8b)
-- Design 1.6: "an awakened spell that is dormant frees its slot at once". The live pass changed the class of a bot with three awakened spells: the slots of the
-- spells the new class does not know stayed taken until the next login, because only the login event synced. ascension.lua afterVocationChange calls this.
do
	storage = {}
	setSpell(206, 20, 1, 1, true)
	setSpell(218, 20, 1, 1, true)
	storage[RC.storage.awakenedSlots] = 206
	storage[RC.storage.awakenedSlots + 1] = 218
	storage[RC.storage.awakened] = 2
	p.learned = {Doomtide = true, ["Final Verdict"] = true}
	eq(AW.afterClassChange ~= nil, true, "the class change hook exists")
	eq(AW.afterClassChange(p), 0, "a class change that keeps both spells frees nothing")
	p.learned = {Doomtide = true} -- the new class does not know Final Verdict
	sent = {}
	eq(AW.afterClassChange(p), 1, "a class change frees the slot of the spell the new class does not know, at once")
	eq(AW.slots(p)[2], 0, "slot 2 is free")
	eq(AW.isAwakened(p, 218), false, "its awakened bit is cleared")
	local _, kf1 = P.unpack(storage[RC.storage.rankBase + 218])
	eq(kf1, 1, "its rank and Forms stay")
	eq(AW.isAwakened(p, 206), true, "the shared spell stays awakened")
	local st = lastSent("awakened")
	eq(st ~= nil and st.data.slots[2] == 0 and st.data.slots[1] == 206, true, "the client is told the new slots")
	sent = {}
	eq(AW.afterClassChange(p), 0, "nothing to free the second time")
	eq(lastSent("awakened"), nil, "and nothing is pushed")
	RC.enabled = false
	p.learned = {}
	eq(AW.afterClassChange(p), 0, "switch off: nothing")
	RC.enabled = true
	storage = {}
end

-- ---------------------------------------------------------------- B8. the staff command and the logout
do
	storage = {}
	local words = registered["/spellseal"]
	words.onSay(p, "/spellseal", "10 20 30")
	local w, r, pn = held()
	eq(w, 10, "staff: Waystone Seals set")
	eq(r, 20, "staff: Rift Seals set")
	eq(pn, 30, "staff: Pinnacle Seals set")
	words.onSay(p, "/spellseal", "clear")
	w, r, pn = held()
	eq(w + r + pn, 0, "staff: clear")
	AW.marks[1] = {owner = 900, untilMs = clock + 1000, pct = 0.5}
	AW.marks[2] = {owner = 5, untilMs = clock + 1000, pct = 0.5}
	registered["ChaosSpellAwakeningLogout"].onLogout(p)
	eq(AW.marks[1], nil, "logout: my marks are gone")
	ok(AW.marks[2] ~= nil, "another player's mark stays")
end

if fails > 0 then
	print("spell_awakening_test: " .. checks .. " checks, " .. fails .. " FAILURES")
	os.exit(1)
end
print("spell_awakening_test: " .. checks .. " checks ok")

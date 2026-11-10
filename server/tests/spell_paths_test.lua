-- Run from the server/ folder: luajit tests/spell_paths_test.lua && lua5.3 tests/spell_paths_test.lua (CI runs both)
-- O468 part B: every bonus reaches every player damage path. What this holds:
--   * the Beastmaster's bite and the pet's Spark Aura are ORIGIN_SPELL inside the class spell factor's guard (the engine runs no
--     onHealthChange event for ORIGIN_NONE); the real passive tree event takes the bite; the refitted `autoByLevel` keeps the
--     plain build's bite where it was against a monster with the median armour;
--   * the four damage over time spells (Blightswarm, Witchfire Bolt, Falling Pyre, Shattered Psyche) deal their ticks as spell
--     pulses (ChaosSpell.scriptedDot), the old tick for a typical character at levels 100, 500 and 1000;
--   * the damage spells have support sockets (no attack spell in `none`).
-- (Snares keeping the cast context: tests/snares_test.lua. The spell inputs: tests/spell_inputs_test.lua.)
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function near(a, b, tol, m)
	ok(math.abs(a - b) <= tol * math.max(1, math.abs(b)), (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
end
local function readAll(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- the mocked engine first: its constants (every unknown ALL_CAPS name becomes a number) and permissive stand-ins are used below
local Probe = dofile("tests/fixtures/spell_probe_engine.lua")

-- the typical character (server/tools/rotation_sim.py ANCHORS)
local ANCHORS = {
	ml_caster = {{1, 0}, {100, 60}, {300, 100}, {600, 120}, {1000, 140}},
	skill = {{1, 10}, {100, 80}, {300, 110}, {600, 125}, {1000, 140}},
}
local function interp(pts, x)
	if x <= pts[1][1] then return pts[1][2] end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
	end
	return pts[#pts][2]
end

-- ============================================================================================ B1, B2: bite and aura
do
	local beast = readAll("data/scripts/chaos/beastmaster.lua")
	local bite = beast:match("local function bite%(.-\nend\n")
	ok(bite ~= nil, "beastmaster.lua has the bite")
	ok(bite:find("pcall%(doTargetCombat[^\n]*ORIGIN_SPELL%)") and not bite:find("pcall%(doTargetCombat[^\n]*ORIGIN_NONE"),
		"the bite is ORIGIN_SPELL, not ORIGIN_NONE")
	ok(bite:find("SF.depth = (SF.depth or 0) + 1", 1, true) and bite:find("SF.depth = SF.depth - 1", 1, true),
		"inside the class spell factor's guard")
	local pets = readAll("data/scripts/chaos/pets.lua")
	local aura = pets:match("if pet and abilityOn%(live, \"aura\".-\n\tend\nend\n")
	ok(aura ~= nil, "pets.lua has the aura")
	ok(aura and aura:find("pcall%(doTargetCombat[^\n]*ORIGIN_SPELL%)") and not aura:find("pcall%(doTargetCombat[^\n]*ORIGIN_NONE"),
		"the aura is ORIGIN_SPELL")
	ok(aura and aura:find("SF.depth = (SF.depth or 0) + 1", 1, true), "the aura sits inside the guard")
	-- the axe cleave: a share of a hit that carried every bonus, dealt with the keystone guard up: left as it is
	local fam = readAll("data/scripts/chaos/weapon_families.lua")
	local cleave = fam:match("local function cleave%(.-\nend\n")
	ok(cleave and cleave:find("K.depth = (K.depth or 0) + 1", 1, true) and cleave:find("ORIGIN_NONE", 1, true),
		"the axe cleave stays a guarded share (ORIGIN_NONE): its source hit had the bonuses")
end

-- the real passive tree event on a bite: tree, class damage, no spell factor; the same bite as ORIGIN_NONE never reaches it
do
	local registered = {}
	EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
	rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
	function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
	local realAdd = addEvent
	function addEvent() end
	os.mtime = function() return 1000 end
	dofile("data/scripts/chaos/passivetree_effects.lua")
	dofile("data/scripts/chaos/class_tree.lua")
	local ev = registered["ChaosPassiveDealt"]
	ok(ev ~= nil, "the passive damage event is registered")
	local function player(vocId, level, id)
		local p = {}
		function p:isPlayer() return true end
		function p:getId() return id end
		function p:getLevel() return level end
		function p:getVocation() return {getId = function() return vocId end} end
		function p:getCondition() return nil end
		return p
	end
	local target = {getId = function() return 500 end}
	local ranger = player(15, 500, 7) -- a Beastmaster at level 500 with +40% physical and 60 strength
	ChaosPassiveCache[7] = {incrementPhysical = 40, strength = 60}
	local cd = ChaosClassTree.damageFactor("beastmaster", nil, 500)
	local str = 1 + ChaosPassiveCharStat(60, "strength") / 230
	ChaosSpellFactor.depth = 1 -- inside the guard, as beastmaster.lua deals the bite
	local inGuard = ev.onHealthChange(target, ranger, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
	ChaosSpellFactor.depth = 0
	near(math.abs(inGuard), 1000 * 1.4 * str * cd, 1.5, "the bite takes the tree's physical percent, strength and the class damage")
	ok(math.abs(inGuard) ~= 1000, "and so differs from the plain 1000 it was")
	local unguarded = ev.onHealthChange(target, ranger, -1000, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
	ok(math.abs(unguarded) < math.abs(inGuard) or ChaosSpellFactor.forVocation(15, nil, 500) >= 1,
		"outside the guard the class spell factor would apply too (it does not on a bite)")
	addEvent = realAdd
end

-- autoByLevel: the plain bite (no tree, no gear) is where it was against a monster of the median armour
do
	dofile("data/scripts/chaos/classes.lua")
	dofile("data/scripts/chaos/monster_defence_core.lua")
	local C = ChaosClasses
	local comp = Chaos.classes.companion
	local def = dofile("data/scripts/chaos/defence_config.lua")
	local mcfg = dofile("data/scripts/chaos/monster_defence_config.lua")
	local D = ChaosMonsterDefenceCore
	local legacy = {{60, 1}, {100, 0.88}, {500, 0.56}, {1000, 0.5}} -- autoByLevel before O468
	local worst, at = 0, 0
	for level = 50, 1300, 25 do
		local skill = interp(ANCHORS.skill, level)
		local base = level * comp.autoLevel + skill * comp.autoSkill
		local old = base * interp(legacy, level)
		local lo, hi = C.autoBiteValues(level, skill)
		local raw = (lo + hi) / 2
		local arm = D.armourReduction(def, D.armourValue(def, mcfg, level, "normal"), raw)
		local real = raw * ChaosClassTree.damageFactor("beastmaster", nil, level) * (1 - arm)
		local d = math.abs(real / old - 1)
		if d > worst then worst, at = d, level end
	end
	ok(worst < 0.03, string.format("the plain bite stays within 3%% of the old one (worst %.2f%% at level %d)", worst * 100, at))
end

-- ====================================================================================== B3: damage over time as pulses
do
	local CASTER_VOC = {witchfire = 1, blightswarm = 1, fallingpyre = 1, psyche = 10}
	local SPELLS = {
		{key = "witchfire", script = "chaos/sorcerer/hexfire_bolt.lua", ticks = 4, ms = 3000, ctype = "fire",
			tick = function(ml) return math.max(2, math.floor(ml * 0.15) + 3) end},
		{key = "fallingpyre", script = "chaos/sorcerer/meteor_strike.lua", ticks = 5, ms = 3000, ctype = "fire",
			tick = function(ml) return math.max(3, math.floor(ml * 0.2) + 5) end},
		{key = "psyche", script = "chaos/illusionist/mind_fracture.lua", ticks = 5, ms = 2000, ctype = "death",
			tick = function(ml) return math.max(3, math.floor(ml * 0.3) + 4) end},
		{key = "blightswarm", script = "chaos/druid/venom_swarm.lua", ticks = 8, ms = 2000, ctype = "earth", callback = "onVenomSwarmTarget",
			tick = function(ml) return math.max(2, math.floor(ml * 0.25) + 3) end},
	}
	for _, sp in ipairs(SPELLS) do
		local src = readAll("data/spells/" .. sp.script)
		ok(not src:find("addDamageCondition", 1, true), sp.script .. " deals no engine condition any more")
		ok(src:find("ChaosSpell.scriptedDot", 1, true), sp.script .. " deals scripted ticks")
		for _, level in ipairs({100, 500, 1000}) do
			local ml = interp(ANCHORS.ml_caster, level)
			Probe.set({voc = CASTER_VOC[sp.key], lvl = level, ml = ml, wtype = "none", hpNow = 3000})
			local res = Probe.cast(sp.script)
			if sp.callback then -- the mock's Combat:execute does not run the target callback: call it for the one target
				res = Probe.record(function() _G[sp.callback](Probe.caster, Probe.target) end)
			end
			ok(not res.err, sp.script .. " casts at level " .. level .. ": " .. tostring(res.err))
			local ticks = {}
			for _, h in ipairs(res.hits) do
				if h.via == "doTargetCombat" then ticks[#ticks + 1] = h end
			end
			ok(#ticks == sp.ticks, sp.script .. ": " .. sp.ticks .. " ticks at level " .. level .. " (" .. #ticks .. ")")
			local want = sp.tick(ml)
			for i, h in ipairs(ticks) do
				ok(h.origin == "spell" and h.ctype == sp.ctype, sp.script .. " tick " .. i .. " is a spell hit of its element")
				-- the damage event multiplies a spell hit by the class spell factor; the tick was divided by it first
				local f = ChaosSpellFactor.forVocation(CASTER_VOC[sp.key], nil, level)
				near(math.abs(h.lo) * f, want, 0.05, sp.script .. " tick " .. i .. " at level " .. level .. " (the old condition tick, class factor " .. string.format("%.2f", f) .. " put back)")
				ok(h.delay == i * sp.ms or (sp.key == "fallingpyre" and h.delay == 1200 + i * sp.ms), sp.script .. " tick " .. i .. " is due " .. sp.ms .. " ms after the last")
			end
		end
	end
	-- a new chain on the same target replaces the old one (a condition is refreshed)
	do
		Probe.set({voc = 1, lvl = 500, ml = 113})
		local res = Probe.record(function()
			ChaosSpell.dots["witchfire:1:2"] = -1 -- an older chain of the same spell on the same target
			ChaosSpell.scriptedDot(1, 2, "witchfire", COMBAT_FIREDAMAGE, 4, 3000, 20, 1)
		end)
		local n = 0
		for _, h in ipairs(res.hits) do if h.via == "doTargetCombat" then n = n + 1 end end
		ok(n == 4, "the newest chain deals its ticks")
	end
end

-- the class spell factor is taken off a tick before the event puts it back: the plain tick is the old one for every class
do
	dofile("data/scripts/chaos/spell_factor_config.lua")
	dofile("data/scripts/chaos/spell_factor_core.lua")
	for _, voc in ipairs({1, 5, 10, 20}) do
		for _, level in ipairs({100, 500, 1000}) do
			local p = {getLevel = function() return level end, getVocation = function() return {getId = function() return voc end} end}
			local f = ChaosSpellFactor.forVocation(voc, nil, level)
			near(ChaosSpell.dotTick(p, 100) * f, 100, 1e-9, "tick x class factor is the old tick: voc " .. voc .. " level " .. level)
		end
	end
	ok(ChaosSpell.dotTick(nil, 100) == 100 and ChaosSpell.dotTick({}, 100) == 100, "no player: the base")
end

-- ================================================================================ B4: damage spells have support sockets
do
	local cfg = dofile("data/lib/chaos_supports_config.lua")
	local none = {}
	for _, id in ipairs(cfg.none) do none[id] = true end
	local xml = readAll("data/spells/chaos/spells_chaos.xml")
	local n = 0
	for attrs in xml:gmatch("<instant ([^>]*)>") do
		local group, id = attrs:match('group="([^"]+)"'), tonumber(attrs:match('spellid="(%d+)"'))
		if group == "attack" or group == "healing" then
			n = n + 1
			ok(not none[id], "spell " .. id .. " (" .. attrs:match('name="([^"]+)"') .. ") is a damage or healing spell and has sockets")
		end
	end
	ok(n >= 125, "the attack and healing spells were found (" .. n .. ")")
	for _, id in ipairs({9, 38, 39, 42, 45, 134}) do
		ok(not none[id], "spell " .. id .. " left the list of spells without sockets")
	end
	ok(cfg.kindOverride[39] == "area" and cfg.kindOverride[42] == "area", "Rending Pounce and Grave Nova are area spells for the supports")
end

if fails > 0 then
	error("spell_paths_test: " .. fails .. " failure(s)")
end
print("spell_paths_test: " .. checks .. " checks ok")

-- Run from the server/ folder: luajit tests/spell_paths_test.lua && lua5.3 tests/spell_paths_test.lua (CI runs both)
-- O468 part B: every bonus reaches every player damage path. What this holds:
--   * the Beastmaster's bite and the pet's Spark Aura are ORIGIN_SPELL inside the class spell factor's guard (the engine runs no
--     onHealthChange event for ORIGIN_NONE); the real passive tree event takes the bite; the refitted `autoByLevel` keeps the
--     plain build's bite where it was against a monster with the median armour;
--   * the four damage over time spells (Blightswarm, Witchfire Bolt, Falling Pyre, Shattered Psyche) deal their ticks as spell
--     pulses (ChaosSpell.scriptedDot). O474 (2026-11-10): the side dots are 0.30 x the hit in 6 ticks 300 ms apart, Blightswarm its old
--     total in 6 ticks, against a player the old ticks, gaps and size; the engine of every chain (ChaosSpell.dotChain): the first tick
--     at once, the tick flag, the jump to the nearest monster when the host dies, the condition icon and the cure, the recast;
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
-- O474: the side dots deal 6 ticks 300 ms apart worth 0.30 x the spell's own hit together (the class spell factor stays: the tick is
-- a share of the hit as dealt), Blightswarm its old total in 6 ticks; against a player the old timing and size; the rest of a dot
-- moves on to the nearest living monster when its host dies; a tick is marked for the damage events while it is dealt.
do
	local DOT = dofile("data/scripts/chaos/dot_config.lua")
	dofile("data/scripts/chaos/dot_core.lua")
	local CASTER_VOC = {witchfire = 1, blightswarm = 1, fallingpyre = 1, psyche = 10}
	local SPELLS = {
		{key = "witchfire", script = "chaos/sorcerer/hexfire_bolt.lua", ctype = "fire", side = true, first = 300,
			old = {ticks = 4, ms = 3000, tick = function(ml) return math.max(2, math.floor(ml * 0.15) + 3) end}},
		{key = "fallingpyre", script = "chaos/sorcerer/meteor_strike.lua", ctype = "fire", side = true, first = 1200 + 300,
			old = {ticks = 5, ms = 3000, tick = function(ml) return math.max(3, math.floor(ml * 0.2) + 5) end}},
		{key = "psyche", script = "chaos/illusionist/mind_fracture.lua", ctype = "death", side = true, first = 300,
			old = {ticks = 5, ms = 2000, tick = function(ml) return math.max(3, math.floor(ml * 0.3) + 4) end}},
		{key = "blightswarm", script = "chaos/druid/venom_swarm.lua", ctype = "earth", callback = "onVenomSwarmTarget", first = 300,
			old = {ticks = 8, ms = 2000, tick = function(ml) return math.max(2, math.floor(ml * 0.25) + 3) end}},
	}
	local function cast(sp, level, ml)
		Probe.set({voc = CASTER_VOC[sp.key], lvl = level, ml = ml, wtype = "none", hpNow = 3000})
		local res = Probe.cast(sp.script)
		if sp.callback then -- the mock's Combat:execute does not run the target callback: call it for the one target
			res = Probe.record(function() _G[sp.callback](Probe.caster, Probe.target) end)
		end
		return res
	end
	for _, sp in ipairs(SPELLS) do
		local src = readAll("data/spells/" .. sp.script)
		ok(not src:find("addDamageCondition", 1, true), sp.script .. " deals no engine condition any more")
		ok(src:find("ChaosSpell.scriptedDot", 1, true), sp.script .. " deals scripted ticks")
		for _, level in ipairs({100, 500, 1000}) do
			local ml = interp(ANCHORS.ml_caster, level)
			local res = cast(sp, level, ml)
			ok(not res.err, sp.script .. " casts at level " .. level .. ": " .. tostring(res.err))
			local ticks, hit = {}, nil
			for _, h in ipairs(res.hits) do
				if h.via == "doTargetCombat" then ticks[#ticks + 1] = h elseif not hit then hit = (math.abs(h.lo) + math.abs(h.hi)) / 2 end
			end
			local want = sp.side and DOT.side or DOT.swarm
			ok(#ticks == want.ticks, sp.script .. ": " .. want.ticks .. " ticks at level " .. level .. " (" .. #ticks .. ")")
			local f = ChaosSpellFactor.forVocation(CASTER_VOC[sp.key], nil, level)
			local total = 0
			for i, h in ipairs(ticks) do
				ok(h.origin == "spell" and h.ctype == sp.ctype, sp.script .. " tick " .. i .. " is a spell hit of its element")
				ok(h.delay == sp.first + (i - 1) * want.tickMs, sp.script .. " tick " .. i .. " is due " .. want.tickMs ..
					" ms after the last (first at " .. sp.first .. "): " .. tostring(h.delay))
				total = total + math.abs(h.lo)
			end
			if sp.side then
				ok(hit and hit > 0, sp.script .. " has its own hit")
				-- the side dot is `share` of the hit as dealt: no class factor taken off the tick
				near(total / hit, DOT.side.share, 0.04, sp.script .. " at level " .. level .. ": the dot is 0.30 x the hit (" ..
					string.format("%.3f", total / hit) .. ")")
			else
				-- Blightswarm: the old total (8 old ticks, the class factor put back) in 6 ticks
				near(total * f, sp.old.ticks * sp.old.tick(ml), 0.05, sp.script .. " at level " .. level .. ": the old total of 8 ticks")
			end
		end
	end

	-- against a player: the old ticks, gap and size, the first tick one gap after the cast, no class factor trick lost
	local Pmock = setmetatable({}, {__index = function(t, k) return Probe.target[k] end})
	Pmock.isPlayer = function() return true end
	Pmock.isMonster = function() return false end
	Pmock.getPlayer = function(self) return self end
	Pmock.getCondition = function() return true end -- the icon stands
	local realCreature = Creature
	for _, sp in ipairs(SPELLS) do
		local level = 500
		local ml = interp(ANCHORS.ml_caster, level)
		Creature = function(id) if id == 2 then return Pmock end return realCreature(id) end
		local res = cast(sp, level, ml)
		Creature = realCreature
		ok(not res.err, sp.script .. " casts on a player: " .. tostring(res.err))
		local ticks = {}
		for _, h in ipairs(res.hits) do if h.via == "doTargetCombat" then ticks[#ticks + 1] = h end end
		ok(#ticks == sp.old.ticks, sp.script .. " on a player: the old " .. sp.old.ticks .. " ticks (" .. #ticks .. ")")
		local f = ChaosSpellFactor.forVocation(CASTER_VOC[sp.key], nil, level)
		for i, h in ipairs(ticks) do
			near(math.abs(h.lo) * f, sp.old.tick(ml), 0.05, sp.script .. " on a player: the old tick " .. i)
			local first = sp.key == "fallingpyre" and 1200 or 0
			ok(h.delay == first + i * sp.old.ms, sp.script .. " on a player: the old gap of " .. sp.old.ms .. " ms (" .. tostring(h.delay) .. ")")
		end
	end

	-- the kit and the Necromancer line's dots end to end (the real scripts on the mocked engine): the first tick at once, the new gaps; against a
	-- player the old gaps and first ticks
	do
		local KIT = {
			{"chaos/knight/gorehook.lua", 1, 5, 0, 400, 0, 1000}, {"chaos/illusionist/dreamrot.lua", 10, 6, 0, 400, 0, 1000},
			{"chaos/necromancer/blightbrand.lua", 20, 6, 0, 400, 1000, 1000}, {"chaos/lich/soul_rot.lua", 21, 6, 0, 400, 1000, 1000},
			{"chaos/necromancer/withering_curse.lua", 20, 10, 0, 250, 1000, 1000},
		}
		local realCreature3 = Creature
		local P2 = setmetatable({}, {__index = function(t, k) return Probe.target[k] end})
		P2.isPlayer = function() return true end
		P2.isMonster = function() return false end
		P2.getPlayer = function(self) return self end
		P2.getCondition = function() return true end
		local realCan2 = ChaosSpell.canAttack
		for _, k in ipairs(KIT) do
			Probe.set({voc = k[2], lvl = 500, ml = 100, wtype = "sword", hpNow = 3000})
			local res = Probe.cast(k[1])
			local d = {}
			for _, h in ipairs(res.hits) do if h.via == "doTargetCombat" then d[#d + 1] = h.delay end end
			ok(not res.err and #d == k[3], k[1] .. ": " .. k[3] .. " ticks (" .. #d .. ") " .. tostring(res.err))
			for i, delay in ipairs(d) do
				ok(delay == k[4] + (i - 1) * k[5], k[1] .. ": tick " .. i .. " at " .. (k[4] + (i - 1) * k[5]) .. " ms (" .. tostring(delay) .. ")")
			end
			Creature = function(id) if id == 2 then return P2 end return realCreature3(id) end
			ChaosSpell.canAttack = function(c, t) return t ~= c end
			res = Probe.cast(k[1])
			Creature = realCreature3
			ChaosSpell.canAttack = realCan2
			d = {}
			for _, h in ipairs(res.hits) do if h.via == "doTargetCombat" then d[#d + 1] = h.delay end end
			ok(not res.err and #d == k[3], k[1] .. " on a player: " .. k[3] .. " ticks (" .. #d .. ") " .. tostring(res.err))
			for i, delay in ipairs(d) do
				ok(delay == k[6] + (i - 1) * k[7], k[1] .. " on a player: tick " .. i .. " at " .. (k[6] + (i - 1) * k[7]) .. " ms, the old timing (" .. tostring(delay) .. ")")
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

	-- the one engine: first tick at once, the flag raised around every tick, the jump, the cure, the recast
	do
		local world, log, store = {}, {}, {}
		local function mk(id, x, player)
			local c = {id = id, x = x, hp = 100, player = player or false}
			c.getId = function() return c.id end
			c.getPosition = function() return Position(c.x, 100, 7) end
			c.getHealth = function() return c.hp end
			c.isPlayer = function() return c.player end
			c.isMonster = function() return not c.player end
			c.getMaster = function() return c.master end
			c.getTile = function() return nil end
			c.getPlayer = function() return c.player and c or nil end
			c.getCondition = function(_, kind, id, sub) return c.icon and c.icon[kind .. ":" .. sub] or nil end
			c.addCondition = function() return true end
			world[id] = c
			return c
		end
		local caster = Probe.caster
		caster.setStorageValue = function(_, k, v) store[k] = v end
		caster.getStorageValue = function(_, k) return store[k] or -1 end
		caster.isPlayer = function() return true end
		local realCreature2, realTargetCombat, realSpectators = Creature, doTargetCombat, Game.getSpectators
		local realCan = ChaosSpell.canAttack
		ChaosSpell.canAttack = function(c, t) return t ~= c and t:getHealth() > 0 end -- the PvP rules are ChaosSpell.canAttack's own
		Creature = function(id) if world[id] then return world[id] end return realCreature2(id) end
		Game.getSpectators = function() local l = {}; for _, c in pairs(world) do l[#l + 1] = c end; table.sort(l, function(x, y) return x.id < y.id end); return l end
		doTargetCombat = function(cid, tgt, ctype, lo, hi, effect, origin)
			tgt.hp = tgt.hp + lo
			log[#log + 1] = {target = tgt.id, v = -lo, tick = ChaosDot.isTick(ORIGIN_SPELL, caster, tgt), hp = tgt.hp}
			return true
		end
		local function run(opts, id, key, first, ticks, tickMs, v)
			log = {}
			Probe.record(function()
				ChaosSpell.scriptedDot(1, id, key, COMBAT_FIREDAMAGE, ticks or 6, tickMs or 300, v or 10, 1, opts)
			end)
			return log
		end
		-- first tick at once
		world = {}
		local host = mk(50, 101)
		local l = run({firstMs = 0, raw = true}, 50, "t1")
		ok(#l == 6, "six ticks")
		ok(l[1].tick, "the first tick is flagged as a damage over time tick while it is dealt")
		ok(store[DOT.storage] == -1 or store[DOT.storage] == nil, "and the flag is down again after it")
		ok(not ChaosDot.isTick(ORIGIN_SPELL, caster, host), "a hit outside a tick is a plain hit")
		-- the host dies at tick 2: the other 4 go on the nearest living monster within 3 squares, never a player or a summon
		world = {}
		local a, near1, far, pl, sm = mk(60, 101), mk(61, 103), mk(62, 105), mk(63, 102, true), mk(64, 102)
		sm.master = pl
		a.hp = 20 -- two ticks of 10
		l = run({firstMs = 0, raw = true}, 60, "t2")
		local on = {}
		for _, e in ipairs(l) do on[e.target] = (on[e.target] or 0) + 1 end
		ok(on[60] == 2 and on[61] == 4, "the host takes 2 ticks, the nearest monster the other 4 (" .. tostring(on[60]) .. ", " .. tostring(on[61]) .. ")")
		ok(not on[62] and not on[63] and not on[64], "not the far monster, the player or the player's summon")
		-- no new ticks: the total stays 6
		ok(#l == 6, "no new ticks: 6 in all")
		-- nothing within 3 squares: it ends
		world = {}
		a, far = mk(60, 101), mk(62, 108)
		a.hp = 20
		l = run({firstMs = 0, raw = true}, 60, "t3")
		ok(#l == 2, "no neighbour within 3 squares: the dot ends with its host (" .. #l .. ")")
		-- a monster that already carries the same dot is not picked (its own chain goes on)
		world = {}
		a, near1, far = mk(60, 101), mk(61, 102), mk(62, 104)
		a.hp = 20
		ChaosSpell.dots["t4:1:61"] = 12345
		l = run({firstMs = 0, raw = true}, 60, "t4")
		on = {}
		for _, e in ipairs(l) do on[e.target] = (on[e.target] or 0) + 1 end
		ok(on[62] == 4 and not on[61], "the rest goes past a monster that carries the dot already (" .. tostring(on[62]) .. ")")
		ChaosSpell.dots["t4:1:61"] = nil
		-- a dead host at the first tick: the dot of a bolt that killed its target moves on at once
		world = {}
		a, near1 = mk(60, 101), mk(61, 102)
		a.hp = 0
		l = run({raw = true}, 60, "t5")
		ok(#l == 6 and l[1].target == 61, "a target that the hit itself killed passes the whole dot on")
		-- against a player: the matching condition icon shows, a cure ends the dot, no jump
		world = {}
		local foe = mk(70, 101, true)
		foe.icon = {}
		local added = {}
		foe.addCondition = function(_, c) added[#added + 1] = c; foe.icon[c.kind .. ":" .. c.sub] = c; return true end
		local realCondition = Condition
		Condition = function(kind) local c = {kind = kind, params = {}}; c.setParameter = function(_, k, v) c.params[k] = v; if k == CONDITION_PARAM_SUBID then c.sub = v end end
			c.addDamage = function(_, r, ms, v) c.rounds, c.interval, c.value = r, ms, v end; return c end
		local killed = false
		l = {}
		log = {}
		Probe.record(function()
			ChaosSpell.scriptedDot(1, 70, "t6", COMBAT_FIREDAMAGE, 6, 300, 10, 1, {raw = true, firstMs = 0})
		end)
		Condition = realCondition
		ok(#added == 1 and added[1].kind == CONDITION_FIRE, "a player target gets the zero-damage burning condition (the icon)")
		ok(added[1].value == 0 and added[1].sub == DOT.icon.subId, "with no damage and its own sub id")
		ok(added[1].params[CONDITION_PARAM_OWNER] == 1, "owned by the caster")
		ok(#log == 6, "six ticks on a player while the icon stands")
		-- a cure removes the icon: the next tick does not land
		world = {}
		foe = mk(71, 101, true)
		foe.icon = {}
		foe.addCondition = function(_, c) foe.icon[c.kind .. ":" .. c.sub] = c; return true end
		Condition = function(kind) local c = {kind = kind}; c.setParameter = function(_, k, v) if k == CONDITION_PARAM_SUBID then c.sub = v end end
			c.addDamage = function() end; return c end
		local ticksSeen = 0
		doTargetCombat = function(cid, tgt, ctype, lo, hi)
			ticksSeen = ticksSeen + 1
			if ticksSeen == 2 then foe.icon = {} end -- the cure
			return true
		end
		Probe.record(function()
			ChaosSpell.scriptedDot(1, 71, "t7", COMBAT_FIREDAMAGE, 6, 300, 10, 1, {raw = true, firstMs = 0})
		end)
		Condition = realCondition
		ok(ticksSeen == 2, "a cure ends the dot on a player (" .. ticksSeen .. " ticks)")
		Creature, doTargetCombat, Game.getSpectators = realCreature2, realTargetCombat, realSpectators
		ChaosSpell.canAttack = realCan
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

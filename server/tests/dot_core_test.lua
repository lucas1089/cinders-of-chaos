-- Run from the server/ folder: luajit tests/dot_core_test.lua && lua5.3 tests/dot_core_test.lua (CI runs both)
-- O474, damage over time that is worth casting: the pure rules of data/scripts/chaos/dot_core.lua against dot_config.lua:
--   * the predicate: an engine condition tick or a scripted tick (the flag in a player storage, raised around the tick);
--   * the sizes: side dots 0.30 x the cast's own hit in 6 ticks, Blightswarm its old total in 6 ticks, one gear ailment stack;
--   * where a dot moves on when its host dies; gear ailment stacks (cap 3, the weakest replaced, 8 ticks);
--   * the PvP timing, the condition icon helpers;
--   * the copies of the numbers in attack_kit_config.lua and necro_config.lua (they are literals there).
-- The engine of a chain (ChaosSpell.dotChain) and the four scripts: tests/spell_paths_test.lua. The gear stacks and the sites of the
-- predicate: tests/item_mods_test.lua, unique_passives_test.lua, archetypes_test.lua, monster_defence_test.lua, trials tests.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, fails = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end
local function near(a, b, tol, m)
	checks = checks + 1
	if math.abs(a - b) > tol * math.max(1, math.abs(b)) then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end
end
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function readAll(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

local C = dofile("data/scripts/chaos/dot_config.lua")
local D = dofile("data/scripts/chaos/dot_core.lua")
eq(ChaosDot, D, "the module is the global")
eq(ChaosDotConfig, C, "the config is the global")

-- ----------------------------------------------------------------------------------------------------- the predicate
local function player(id, store)
	local p = {id = id, store = store or {}}
	function p:isPlayer() return true end
	function p:getId() return self.id end
	function p:getStorageValue(k) local v = self.store[k]; if v == nil then return -1 end return v end
	function p:setStorageValue(k, v) self.store[k] = v end
	return p
end
local function monster(id)
	local m = {id = id}
	function m:isPlayer() return false end
	function m:getId() return self.id end
	return m
end
do
	local me, foe, other = player(1), monster(500), monster(501)
	eq(D.isTick(ORIGIN_CONDITION, nil, nil), true, "an engine condition tick is a tick")
	eq(D.isTick(ORIGIN_SPELL, me, foe), false, "a spell hit is not")
	eq(D.isTick(ORIGIN_MELEE, me, foe), false, "a weapon hit is not")
	eq(D.isTick(ORIGIN_SPELL, nil, foe), false, "no attacker: not a tick")
	-- run raises the flag for the target and puts it back
	local seen = {}
	D.run(me, foe, function(a, b)
		seen.tick = D.isTick(ORIGIN_SPELL, me, foe)
		seen.other = D.isTick(ORIGIN_SPELL, me, other)
		seen.args = a .. b
	end, "x", "y")
	eq(seen.tick, true, "inside run the hit on the target is a tick")
	eq(seen.other, false, "a hit on another creature (a nova, a spread) is not")
	eq(seen.args, "xy", "run passes its arguments on")
	eq(D.isTick(ORIGIN_SPELL, me, foe), false, "the flag is down after run")
	eq(me.store[C.storage], -1, "put back to what it was")
	-- the flag follows nesting and errors
	me.store[C.storage] = 77
	local ok1, err = pcall(D.run, me, foe, function() error("boom", 0) end)
	eq(ok1, false, "an error goes on")
	eq(err, "boom", "with its message")
	eq(me.store[C.storage], 77, "and the flag is put back to the earlier value")
	me.store[C.storage] = nil
	-- returns what the function returns
	local a, b = D.run(me, foe, function() return 3, 4 end)
	eq(a + b, 7, "run returns the results")
	-- a monster caster raises nothing (monsters' own damage over time is untouched)
	eq(D.isTick(ORIGIN_SPELL, monster(9), foe), false, "a monster attacker is no scripted tick")
	-- a missing config key: no flag
	local saved = C.storage
	C.storage = nil
	eq(D.flagged(me, foe), false, "no storage key, no flag")
	C.storage = saved
end

-- --------------------------------------------------------------------------------------------------------- sizes
do
	-- a side dot: share x the average of the hit over the ticks
	local tick = D.sideTick(100, 300)
	near(tick, C.side.share * 200 / C.side.ticks, 1e-9, "a side tick is 0.30 x the average hit / 6")
	near(D.sideTotal(100, 300), 0.30 * 200, 1e-9, "the side dot is 0.30 x the hit")
	eq(C.side.ticks, 6, "six ticks")
	eq(C.side.tickMs, 300, "300 ms apart")
	eq(C.side.share, 0.30, "0.30 of the hit")
	-- Blightswarm keeps its total in fewer ticks
	near(D.swarmTick(5) * C.swarm.ticks, 5 * C.swarm.oldTicks, 1e-9, "Blightswarm: the old total of 8 ticks in 6")
	eq(C.swarm.ticks, 6, "Blightswarm six ticks")
	eq(C.swarm.tickMs, 300, "300 ms apart")
	-- one gear ailment stack: 40% of the hit over 8 ticks, whole points, at least 1
	eq(D.ailmentTick(400, 40, 8), 20, "40% of 400 over 8 ticks")
	eq(D.ailmentTick(-400, 40, 8), 20, "a negative hit counts by its size")
	eq(D.ailmentTick(1, 40, 8), 1, "at least 1")
	eq(D.ailmentTick(0, 40, 8), 1, "even a hit of 0")
	eq(D.ailmentTick(400, 40), 20, "the rounds default to the config's")
	eq(D.ailmentTick(1000, 40, 8) * 8 * 3, 1000 * 0.4 * 3, "three full stacks are three times 40% of the hit")
end

-- ---------------------------------------------------------------------------------------------------- a dot moves on
do
	local function cand(id, x, y, props)
		local c = {id = id, pos = {x = x, y = y, z = 7}, alive = true}
		for k, v in pairs(props or {}) do c[k] = v end
		return c
	end
	local at = {x = 0, y = 0, z = 7}
	eq(D.pickJump({cand(4, 3, 0), cand(5, 1, 1), cand(6, 0, 1, {alive = false})}, at, 3).id, 5, "the nearest living monster")
	eq(D.pickJump({cand(4, 4, 0)}, at, 3), nil, "out of reach")
	eq(D.pickJump({cand(4, 3, 3)}, at, 3).id, 4, "a king's move: the corner is 3 away")
	eq(D.pickJump({cand(4, 1, 0, {player = true})}, at, 3), nil, "never a player")
	eq(D.pickJump({cand(4, 1, 0, {summon = true})}, at, 3), nil, "never a summon of a player")
	eq(D.pickJump({cand(4, 1, 0, {busy = true})}, at, 3), nil, "never a monster that carries the dot already")
	eq(D.pickJump({cand(4, 1, 0, {busy = true}), cand(5, 3, 0)}, at, 3).id, 5, "it goes past a busy one")
	eq(D.pickJump({cand(4, 1, 0, {pos = {x = 1, y = 0, z = 8}})}, at, 3), nil, "never another floor")
	eq(D.pickJump({cand(9, 2, 0), cand(7, 0, 2)}, at, 3).id, 7, "a tie: the lower id")
	eq(D.pickJump({}, at, 3), nil, "no candidates")
	eq(D.pickJump(nil, at, 3), nil, "no list")
	eq(D.pickJump({cand(4, 1, 0)}, nil, 3), nil, "no position")
	eq(C.jump.radius, 3, "within 3 squares")
end

-- ------------------------------------------------------------------------------------------ gear ailment stacks
do
	eq(C.ailment.rounds, 8, "8 ticks")
	eq(C.ailment.interval, 500, "0.5 s apart")
	eq(C.ailment.maxStacks, 3, "up to 3 stacks")
	local list = {}
	local kept
	list, kept = D.stackAdd(list, 10)
	list, kept = D.stackAdd(list, 20)
	list, kept = D.stackAdd(list, 30)
	eq(#list, 3, "three stacks")
	eq(kept, true, "the third was kept")
	-- a fourth replaces the weakest
	list, kept = D.stackAdd(list, 25)
	eq(#list, 3, "still three")
	eq(kept, true, "the fourth was kept")
	local ticks = {}
	for _, s in ipairs(list) do ticks[#ticks + 1] = s.tick end
	table.sort(ticks)
	eq(table.concat(ticks, ","), "20,25,30", "the weakest (10) went")
	-- a fourth that is weaker than all of them is the weakest: dropped
	list, kept = D.stackAdd(list, 5)
	eq(kept, false, "a weaker fourth is dropped")
	eq(#list, 3, "still three")
	-- an equal one replaces the one with the fewest ticks left
	local two = {{tick = 10, left = 2}, {tick = 10, left = 6}, {tick = 50, left = 8}}
	two = D.stackAdd(two, 10)
	local lefts = {}
	for _, s in ipairs(two) do lefts[#lefts + 1] = s.left end
	table.sort(lefts)
	eq(table.concat(lefts, ","), "6,8,8", "on a tie the stack with the fewest ticks left is replaced")
	-- one beat deals the sum and uses a tick of each; a stack expires after 8 beats
	local st = {}
	D.stackAdd(st, 10, 8, 3)
	D.stackAdd(st, 20, 8, 3)
	local beats, total = 0, 0
	while #st > 0 do
		local sum = D.stackStep(st)
		beats = beats + 1
		total = total + sum
		if beats == 4 then D.stackAdd(st, 30, 8, 3) end -- a later proc joins the running beat
		ok(beats < 40, "the stacks run out")
		if beats >= 40 then break end
	end
	eq(total, 8 * 10 + 8 * 20 + 8 * 30, "every stack deals all of its 8 ticks, a late one included")
	eq(beats, 12, "the last stack (added at beat 4) ends 8 beats later")
	eq(D.stackStep({}), 0, "an empty list deals nothing")
	-- the cap argument and the default
	local cap = {}
	for i = 1, 10 do cap = D.stackAdd(cap, i, 8, 2) end
	eq(#cap, 2, "a cap of 2 holds")
	for i = 1, 10 do cap = D.stackAdd(cap, i) end
	eq(#cap, 3, "the config's cap by default")
end

-- ------------------------------------------------------------------------------------------------------- PvP timing
do
	local w = D.pvpSide("witchfire")
	eq(w.ticks, 4, "Witchfire Bolt on a player: the old 4 ticks")
	eq(w.tickMs, 3000, "3 s apart")
	eq(w.firstMs, 3000, "the first after 3 s")
	eq(D.pvpSide("fallingpyre").ticks, 5, "Falling Pyre on a player: 5 ticks")
	eq(D.pvpSide("shatteredpsyche").tickMs, 2000, "Shattered Psyche on a player: 2 s")
	eq(D.pvpSide("blightswarm").ticks, 8, "Blightswarm on a player: 8 ticks")
	eq(D.pvpSide("gorehook"), nil, "a key that is no side dot")
	local o = D.pvpSideOpts("witchfire", 17)
	eq(o.base, 17, "the old tick size is the script's")
	eq(o.ticks, 4, "with the old ticks")
	eq(D.pvpSideOpts("nothing", 1), nil, "none for an unknown key")
	local k = D.pvpKit("blightbrand")
	eq(k.tickMs, 1000, "the kit dots on a player: the old 1 s gap")
	eq(k.firstMs, 0, "the first at once, as before")
	near(k.mult, 1 / 1.25, 1e-9, "Blightbrand: back to the size before x1.25")
	near(D.pvpKit("martyrspyre").mult, 1 / 1.1, 1e-9, "Martyr's Pyre: back to the size before x1.1")
	eq(D.pvpKit("gorehook").mult, 1, "Gorehook: unchanged")
	local nc = D.pvpNecro("curse")
	eq(nc.tickMs, 1000, "Withering Curse on a player: the old 1 s gap")
	eq(nc.firstMs, 1000, "the first after 1 s")
	eq(nc.mult, 1, "its size unchanged")
	near(D.pvpNecro("soulrot").mult, 1 / 1.5, 1e-9, "Soul Rot on a player: x1 / 1.5")
	-- the old totals: against a player a dot deals what it dealt before, to the point
	local oldTotals = {witchfire = 4, fallingpyre = 5, shatteredpsyche = 5, blightswarm = 8}
	for key, ticks in pairs(oldTotals) do
		eq(D.pvpSide(key).ticks, ticks, key .. " keeps its old tick count against a player")
	end
end

-- ------------------------------------------------------------------------------------------------- the condition icon
do
	COMBAT_FIREDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_DEATHDAMAGE = 11, 12, 13
	CONDITION_FIRE, CONDITION_POISON, CONDITION_CURSED = 21, 22, 23
	eq(D.iconType(COMBAT_FIREDAMAGE), CONDITION_FIRE, "fire shows burning")
	eq(D.iconType(COMBAT_EARTHDAMAGE), CONDITION_POISON, "earth shows poison")
	eq(D.iconType(COMBAT_DEATHDAMAGE), CONDITION_CURSED, "death shows cursed")
	eq(D.iconType(999), nil, "an unknown type shows nothing")
	C.icon.enabled = false
	eq(D.iconType(COMBAT_FIREDAMAGE), nil, "switched off: nothing")
	C.icon.enabled = true
	-- the zero-damage condition
	local made
	local realCondition = Condition
	Condition = function(kind, id)
		local c = {kind = kind, id = id, params = {}}
		function c:setParameter(k, v) self.params[k] = v end
		function c:addDamage(rounds, ms, v) self.rounds, self.ms, self.v = rounds, ms, v end
		made = c
		return c
	end
	local held
	local target = {addCondition = function(_, c) held = c; return true end,
		getCondition = function(_, kind, id, sub) if held and held.kind == kind and held.params[CONDITION_PARAM_SUBID] == sub then return held end return nil end}
	eq(D.addIcon(target, CONDITION_FIRE, 2400, 7), C.icon.subId, "the icon condition is added with its own sub id")
	eq(made.v, 0, "it deals no damage")
	eq(made.rounds, 1, "in one round")
	eq(made.ms, 2400, "for the duration of the dot")
	eq(made.params[CONDITION_PARAM_OWNER], 7, "owned by the caster")
	eq(made.params[CONDITION_PARAM_DELAYED], true, "delayed: nothing at the start")
	eq(made.params[CONDITION_PARAM_SUBID], C.icon.subId, "its sub id")
	ok(not made.params[CONDITION_PARAM_TICKS], "its length comes from the round (addDamage adds it to the ticks)")
	eq(D.iconHeld(target, CONDITION_FIRE), true, "held while it stands")
	held = nil
	eq(D.iconHeld(target, CONDITION_FIRE), false, "a cure took it: not held")
	eq(D.iconHeld(target, nil), true, "no icon type: nothing to lose")
	eq(D.addIcon({}, CONDITION_FIRE, 100), nil, "a target that takes no condition")
	eq(D.addIcon(target, nil, 100), nil, "no type")
	eq(D.addIcon({addCondition = function() return false end}, CONDITION_FIRE, 100), nil, "refused by the engine: no icon")
	Condition = realCondition
	ok(C.icon.subId > 71096 and C.icon.subId < 71100, "a sub id nothing else uses")
end

-- ------------------------------------------------------------------- the copies of the numbers in the spell tables
do
	dofile("data/scripts/chaos/attack_kit_config.lua")
	local N = dofile("data/scripts/chaos/necro_config.lua")
	local kit = ChaosAttackKit.cfg.spells
	local dots = {}
	for key, s in pairs(kit) do
		if s.shape == "dot" then
			dots[#dots + 1] = key
			eq(s.tickMs, C.kit.tickMs, key .. ": the dot gap is dot_config.lua kit.tickMs")
			eq(s.scale, C.kit.scale[key] or 1, key .. ": the scale is dot_config.lua kit.scale (1 when none)")
		end
	end
	eq(#dots, 6, "six kit dots (Gorehook, Dreamrot, Venom Spiral, Blightbrand, Martyr's Pyre, Crimson Covenant)")
	eq(N.witheringCurse.tickMs, C.necro.curseTickMs, "Withering Curse: dot_config.lua necro.curseTickMs")
	eq(N.witheringCurse.durationMs, 12000, "its amplify keeps 12 s")
	eq(N.witheringCurse.ticks, 10, "its ticks stay 10")
	eq(N.soulRot.tickMs, C.necro.soulRotTickMs, "Soul Rot: dot_config.lua necro.soulRotTickMs")
	eq(N.soulRot.tick.scale, C.necro.soulRotScale, "Soul Rot: dot_config.lua necro.soulRotScale")
	near(C.necro.soulRotScale, 1.15 * 1.5, 1e-9, "x1.5 of the old 1.15")
	eq(N.soulRot.jumpRadius, C.jump.radius, "Soul Rot jumps as far as every dot")
	eq(N.soulRot.ticks, 6, "Soul Rot keeps its 6 ticks")
	-- the old gap of the PvP table is the old config
	eq(C.pvp.kit.tickMs, 1000, "the kit dots' old gap")
	eq(C.pvp.necro.tickMs, 1000, "the necro dots' old gap")
	-- the storage key sits in a block nothing else in the tree uses
	local key = tostring(C.storage)
	for _, f in ipairs({"data/scripts/chaos/chaos_constants.lua", "data/lib/chaos_supports_config.lua"}) do
		ok(not readAll(f):find(key, 1, true), key .. " is not used in " .. f)
	end
	ok(C.storage >= 7100000 and C.storage <= 7127999, "the storage key is in the reserved range")
end

if fails > 0 then
	error("dot_core_test: " .. fails .. " failure(s)")
end
print("dot_core_test: " .. checks .. " checks ok")

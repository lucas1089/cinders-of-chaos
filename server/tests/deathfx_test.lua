-- Run from the server/ folder: luajit tests/deathfx_test.lua (and lua5.3; CI runs both)
-- Death and spawn effects of monsters (O456; server/README.md "Death and spawn effects"). Part 1, the pure core
-- (deathfx_core.lua): the shipped config is valid, the effect per race, bosses, creatures with a master, the spawn
-- rules (map respawn only), the token bucket. Part 2, the engine glue deathfx.lua on a mocked engine: one packet at the
-- right tile and offset, a monster of an unknown race, a broken type call, nothing sent when switched off. Part 3, the
-- hooks: cosmetics.lua calls the glue from its death event and its spawn callback and registers nothing else. Part 4,
-- the config against the libs: every effect id, offset and length equals its ChaosVfx / ChaosFx row.

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
		error(m or "expected true", 2)
	end
end
local function readFile(path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local s = f:read("*a")
	f:close()
	return s
end

Chaos = Chaos or {}
dofile("data/scripts/chaos/deathfx_core.lua")
local K = ChaosDeathFx
local cfg = dofile("data/scripts/chaos/deathfx_config.lua")

-- ---------------------------------------------------------------- part 1: the core
eq(#K.validate(cfg), 0, "the shipped config is valid")
eq(cfg.enabled, true, "on by default")
eq(K.raceName(1), "venom", "race 1")
eq(K.raceName(2), "blood", "race 2")
eq(K.raceName(3), "undead", "race 3")
eq(K.raceName(4), "fire", "race 4")
eq(K.raceName(5), "energy", "race 5")
eq(K.raceName(0), nil, "race 0: none")
eq(K.raceName(9), nil, "race 9: none")
eq(K.raceName(nil), nil, "no race")

-- one effect per race, all different, for deaths, bosses and spawns
for _, set in ipairs({cfg.death.effects, cfg.death.boss, cfg.spawn.effects}) do
	local seen = {}
	for _, race in ipairs(K.RACE_NAMES) do
		ok(set[race], "an effect for " .. race)
		ok(not seen[set[race].id], "no two races share an effect")
		seen[set[race].id] = true
	end
end
-- a boss effect is not a normal one and is bigger or equal in time
for _, race in ipairs(K.RACE_NAMES) do
	ok(cfg.death.boss[race].id ~= cfg.death.effects[race].id, "boss effect differs: " .. race)
	ok(cfg.spawn.effects[race].ms <= 700, "spawn puffs are short: " .. race)
end

-- validation catches what would break a server
local function copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = type(v) == "table" and copy(v) or v
	end
	return o
end
local bad = copy(cfg)
bad.death.effects.fire = nil
ok(#K.validate(bad) > 0, "a missing race is a problem")
bad = copy(cfg)
bad.death.effects.blood.ms = 3000
ok(#K.validate(bad) > 0, "a long death effect is a problem")
bad = copy(cfg)
bad.spawn.effects.venom.id = "x"
ok(#K.validate(bad) > 0, "a non-numeric id is a problem")
bad = copy(cfg)
bad.death.budget.capacity = 0
ok(#K.validate(bad) > 0, "an empty budget is a problem")
eq(#K.validate(nil), 1, "no config")

-- the death rule
local function fresh()
	return {death = K.newBudget(cfg.death.budget.capacity), spawn = K.newBudget(cfg.spawn.budget.capacity)}
end
local st = fresh()
eq(K.decideDeath(cfg, 2, false, false, st.death, 1000), cfg.death.effects.blood, "blood race: the blood splash")
eq(K.decideDeath(cfg, 3, false, false, st.death, 1000), cfg.death.effects.undead, "undead race")
eq(K.decideDeath(cfg, "fire", false, false, st.death, 1000), cfg.death.effects.fire, "a race by name")
eq(K.decideDeath(cfg, 0, false, false, st.death, 1000), nil, "unknown race: nothing")
eq(K.decideDeath(cfg, 2, false, true, st.death, 1000), nil, "a creature with a master (summon, wolf, minion): nothing")
eq(K.decideDeath(cfg, 2, true, true, st.death, 1000), nil, "a boss summon: nothing")
eq(K.decideDeath(cfg, 5, true, false, st.death, 1000), cfg.death.boss.energy, "a boss: the large effect")
local off = copy(cfg)
off.enabled = false
eq(K.decideDeath(off, 2, false, false, fresh().death, 1000), nil, "switched off")
off = copy(cfg)
off.death.enabled = false
eq(K.decideDeath(off, 2, false, false, fresh().death, 1000), nil, "death effects off")
eq(K.decideDeath(nil, 2, false, false, st.death, 1000), nil, "no config")

-- the budget: a pack that dies in one instant starts at most `capacity` effects, a boss skips it
st = fresh()
local shown = 0
for _ = 1, 30 do
	if K.decideDeath(cfg, 2, false, false, st.death, 5000) then
		shown = shown + 1
	end
end
eq(shown, cfg.death.budget.capacity, "30 deaths in one instant: the capacity")
ok(K.decideDeath(cfg, 2, true, false, st.death, 5000), "a boss still gets its effect on an empty bucket")
shown = 0
for i = 1, 20 do
	-- 250 ms later: perSecond / 4 tokens
	if K.decideDeath(cfg, 2, false, false, st.death, 5000 + 250 * i) then
		shown = shown + 1
	end
end
ok(shown >= 19, "a death every 250 ms is always shown (a normal hunt): " .. shown)
st = fresh()
shown = 0
for i = 1, 1000 do
	-- a death every 20 ms for 20 s, 50 per second: the refill rate caps it
	if K.decideDeath(cfg, 2, false, false, st.death, 10000 + 20 * i) then
		shown = shown + 1
	end
end
ok(shown <= cfg.death.budget.capacity + 20 * cfg.death.budget.perSecond + 1, "a long stream is capped by the refill: " .. shown)
ok(shown >= 20 * cfg.death.budget.perSecond - 5, "and it still shows the refill rate: " .. shown)

-- the spawn rule: a map respawn only
st = fresh()
eq(K.decideSpawn(cfg, 2, false, false, false, st.spawn, 1000), cfg.spawn.effects.blood, "a map respawn: the puff")
eq(K.decideSpawn(cfg, 4, false, false, false, st.spawn, 1000), cfg.spawn.effects.fire, "fire respawn")
eq(K.decideSpawn(cfg, 2, false, true, false, st.spawn, 1000), nil, "the start of the server: nothing")
eq(K.decideSpawn(cfg, 2, false, false, true, st.spawn, 1000), nil, "a script-made monster (rift, tower, summon): nothing")
eq(K.decideSpawn(cfg, 2, true, false, false, st.spawn, 1000), nil, "a boss: nothing")
eq(K.decideSpawn(cfg, 0, false, false, false, st.spawn, 1000), nil, "unknown race: nothing")
st = fresh()
shown = 0
for _ = 1, 20 do
	if K.decideSpawn(cfg, 2, false, false, false, st.spawn, 7000) then
		shown = shown + 1
	end
end
eq(shown, cfg.spawn.budget.capacity, "20 respawns in one instant: the capacity")
off = copy(cfg)
off.spawn.enabled = false
eq(K.decideSpawn(off, 2, false, false, false, fresh().spawn, 1000), nil, "spawn effects off")
off = copy(cfg)
off.spawn.skipArtificial = false
eq(K.decideSpawn(off, 2, false, false, true, fresh().spawn, 1000).id, cfg.spawn.effects.blood.id, "skipArtificial = false lets a script-made one show")

-- ---------------------------------------------------------------- part 2: the glue on a mocked engine
local sent = {}
Position = function(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function(self, id)
		sent[#sent + 1] = {x = self.x, y = self.y, z = self.z, id = id}
	end}
end
local clock = 100000
os.mtime = function() return clock end
local function monster(opts)
	local m = {}
	function m:isMonster() return true end
	function m:getMaster() return opts.master end
	function m:getPosition() return {x = 1000, y = 2000, z = 7} end
	function m:getType()
		return {
			race = function() if opts.raceError then error("no race") end return opts.race end,
			isBoss = function() return opts.boss == true end,
		}
	end
	return m
end
dofile("data/scripts/chaos/deathfx.lua")
ok(K.ready, "glue ready with the shipped config")
eq(type(K.onDeath), "function", "onDeath")
eq(type(K.onSpawn), "function", "onSpawn")

sent = {}
eq(K.onDeath(monster({race = 2})), true, "a blood monster dies: sent")
eq(#sent, 1, "one packet")
eq(sent[1].id, 390, "the blood splash")
eq(sent[1].x, 1000, "2x2 at +0")
eq(sent[1].y, 2000, "2x2 at +0 (y)")
clock = clock + 5000
sent = {}
eq(K.onDeath(monster({race = 3})), true, "an undead monster dies")
eq(sent[1].id, 584, "the bone burst")
eq(sent[1].x, 1001, "3x3 sent at +1")
eq(sent[1].y, 2001, "3x3 sent at +1 (y)")
sent = {}
eq(K.onDeath(monster({race = 5, boss = true})), true, "a boss dies")
eq(sent[1].id, 652, "the large lightning burst")
eq(sent[1].x, 1003, "7x7 sent at +3")
sent = {}
eq(K.onDeath(monster({race = 2, master = {}})), false, "a summon dies: nothing")
eq(K.onDeath(monster({race = 2, boss = true, master = {}})), false, "a summoned boss: nothing")
eq(K.onDeath(monster({race = 0})), false, "race 0: nothing")
eq(K.onDeath(monster({raceError = true})), false, "a type call that fails: nothing, no error")
eq(K.onDeath(nil), false, "no monster")
eq(K.onDeath({isMonster = function() return false end}), false, "a player: nothing")
eq(#sent, 0, "no packet for any of them")

clock = clock + 5000
sent = {}
eq(K.onSpawn(monster({race = 4}), {x = 5, y = 6, z = 7}, false, false), true, "a map respawn: the puff")
eq(sent[1].id, 4141, "the orange flash")
eq(sent[1].x, 5, "at the position the engine gave")
eq(K.onSpawn(monster({race = 4}), {x = 5, y = 6, z = 7}, true, false), false, "startup: nothing")
eq(K.onSpawn(monster({race = 4}), {x = 5, y = 6, z = 7}, false, true), false, "script-made: nothing")
eq(K.onSpawn(monster({race = 4, boss = true}), {x = 5, y = 6, z = 7}, false, false), false, "boss: nothing")
eq(K.onSpawn(monster({race = 4}), nil, false, false), false, "no position: nothing")
eq(#sent, 1, "one packet in all")

-- the switch
ChaosDeathFxConfig.enabled = false
clock = clock + 5000
sent = {}
eq(K.onDeath(monster({race = 2})), false, "switched off: no death effect")
eq(K.onSpawn(monster({race = 2}), {x = 5, y = 6, z = 7}, false, false), false, "switched off: no spawn effect")
eq(#sent, 0, "switched off: no packet")
ChaosDeathFxConfig.enabled = true

-- a pack dying in one instant on the glue: capped by the budget
clock = clock + 10000
sent = {}
for _ = 1, 30 do
	K.onDeath(monster({race = 2}))
end
eq(#sent, cfg.death.budget.capacity, "30 deaths in one instant: the capacity in packets")

-- ---------------------------------------------------------------- part 3: the hooks of cosmetics.lua
local cos = readFile("data/scripts/chaos/cosmetics.lua")
ok(cos:find("ChaosDeathFx.onDeath", 1, true), "cosmetics.lua calls onDeath from its death event")
ok(cos:find("ChaosDeathFx.onSpawn", 1, true), "cosmetics.lua calls onSpawn from its spawn callback")
local glue = readFile("data/scripts/chaos/deathfx.lua")
ok(not glue:find("CreatureEvent(", 1, true), "deathfx.lua registers no creature event of its own")
ok(not glue:find("EventCallback", 1, true) or glue:find("registers no hook", 1, true), "deathfx.lua registers no callback")
ok(not glue:find(":register(", 1, true), "deathfx.lua registers nothing")
ok(not glue:find("addEvent", 1, true) and not glue:find("db.", 1, true), "no timer and no database")

-- ---------------------------------------------------------------- part 4: the config against the libs
-- the ChaosVfx rows `name = {id = N, dx = a, dy = b, ms = c}` of data/lib; the stock redraw 390 is ChaosFx.blood_splash
local libs = {"chaos_pack29_vfx_ids.lua", "chaos_vfx_art.lua", "chaos_big_fx_ids.lua", "chaos_pair50_fx_ids.lua"}
local rows = {}
for _, f in ipairs(libs) do
	for name, id, dx, dy, ms in readFile("data/lib/" .. f):gmatch("ChaosVfx%.([%w_]+)%s*=%s*{id%s*=%s*(%d+),%s*dx%s*=%s*(%-?%d+),%s*dy%s*=%s*(%-?%d+),%s*ms%s*=%s*(%d+)}") do
		rows[tonumber(id)] = {name = name, dx = tonumber(dx), dy = tonumber(dy), ms = tonumber(ms)}
	end
end
for _, set in ipairs({{"death", cfg.death.effects}, {"boss", cfg.death.boss}, {"spawn", cfg.spawn.effects}}) do
	for race, e in pairs(set[2]) do
		local row = rows[e.id]
		if e.id == 390 then
			ok(readFile("data/lib/chaos_fx.lua"):find("blood_splash = 390", 1, true), "390 is ChaosFx.blood_splash")
			eq(e.dx + e.dy, 0, "390 is sent at +0,+0")
		else
			ok(row, set[1] .. "." .. race .. ": effect " .. e.id .. " is a ChaosVfx row")
			eq(e.dx, row.dx, set[1] .. "." .. race .. " dx of " .. row.name)
			eq(e.dy, row.dy, set[1] .. "." .. race .. " dy of " .. row.name)
			eq(e.ms, row.ms, set[1] .. "." .. race .. " ms of " .. row.name)
		end
	end
end

print("deathfx_test: " .. checks .. " checks passed")

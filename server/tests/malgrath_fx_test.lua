-- Run from the server/ folder: luajit tests/malgrath_fx_test.lua (and lua5.3; CI runs both)
-- Malgrath, the Drowned Crown (O637, client pair 74; data/lib/chaos_malgrath_fx.lua, the generated chaos_malgrath_fx_ids.lua,
-- scripts/chaos/malgrath.lua and the `pose` rows of boss_mechanics_config.lua): the gate is config.lua chaosClientPair >= 74; with it
-- the eight effects join ChaosVfx at their send offsets, an attack's effect ends with the warning, the boss is hidden and frozen while
-- it plays and as it was afterwards, one effect at a time, the arrival hides the boss for the rise, the death plays the collapse on the
-- boss's tile and hides nothing; below the pair nothing answers. The ids are the block 5326.. in order, after the bolt from the sky.
local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	n = n + 1
	if not v then
		error(m or "not true", 2)
	end
end
local function slurp(path)
	local f = assert(io.open(path, "r"), path)
	local text = f:read("*a")
	f:close()
	return text
end

-- ---------------------------------------------------------------- a small engine
local sent, events, now = {}, {}, 0
local PosMeta = {}
PosMeta.__index = PosMeta
function PosMeta:sendMagicEffect(id)
	sent[#sent + 1] = {x = self.x, y = self.y, z = self.z, id = id}
end
function Position(x, y, z)
	return setmetatable({x = x, y = y, z = z}, PosMeta)
end
function addEvent(fn, ms, ...)
	events[#events + 1] = {at = now + (ms or 0), fn = fn, args = {...}}
end
local function runTo(t)
	while true do
		table.sort(events, function(a, b) return a.at < b.at end)
		local ev = events[1]
		if not ev or ev.at > t then
			break
		end
		table.remove(events, 1)
		now = ev.at
		ev.fn((table.unpack or unpack)(ev.args))
	end
	now = t
end
local bosses = {}
function Monster(id)
	return bosses[id]
end
local function newBoss(id, x, y)
	local b = {id = id, pos = {x = x, y = y, z = 11}, outfit = {lookType = 3530, lookHead = 0}, speed = 260, history = {}}
	function b:getId() return self.id end
	function b:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
	function b:getOutfit() return self.outfit end
	function b:setOutfit(o) self.outfit = o; self.history[#self.history + 1] = o.lookType end
	function b:getSpeed() return self.speed end
	function b:changeSpeed(d) self.speed = self.speed + d end
	bosses[id] = b
	return b
end

-- ---------------------------------------------------------------- the generated ids
dofile("data/lib/chaos_malgrath_fx_ids.lua")
local ids = ChaosMalgrathFxIds
eq(ids.pair, 74, "the ids are client pair 74's")
eq(ids.outfit, 3530, "the outfit after the 3,529 of pair 73")
eq(ids.first, 5326, "the first effect after the 5,325 of pair 73 (the bolt from the sky ends at 5325)")
eq(ids.count, 8, "eight effects")
local order = {"mg_ground_slam", "mg_lightning_rain", "mg_eye_laser", "mg_crown_inferno", "mg_summon", "mg_earthquake_stomp", "mg_death", "mg_spawn_rise"}
for i, name in ipairs(order) do
	local e = ids.effects[name]
	ok(e ~= nil, "effect " .. name)
	eq(e.id, 5325 + i, name .. " id")
	ok(e.dx >= 0 and e.dx < e.w and e.dy >= 0 and e.dy < e.h, name .. ": the send offset is inside its canvas")
	ok(e.w >= 7 and e.h >= 7 and e.ms >= 1800, name .. ": the canvas holds the 7x7 outfit and the play is a whole animation")
	ok(e.dx >= 3, name .. ": the boss's tile is column 3 of the outfit canvas, so at least 3 tiles to the right of the art's left edge")
end
local count = 0
for _ in pairs(ids.effects) do
	count = count + 1
end
eq(count, 8, "no other effect in the table")
dofile("data/lib/chaos_lightning_fx_ids.lua")
local lightning = ChaosLightningFxIds
eq(ids.first, lightning.first + lightning.count, "right after the bolt from the sky")
-- the table is the one the tool writes (client/tools/sprites/gen_malgrath_boss.py ids --check holds it to art_import/malgrath_boss.csv)
local csv = slurp("../client/tools/sprites/art_import/malgrath_boss.csv")
for _, name in ipairs(order) do
	local e = ids.effects[name]
	local id, tiles, send = csv:match(name .. ",(%d+),[^\n]-,(%d+x%d+),[%d:]+,([%d:]+),%d+,%d+\n")
	eq(tonumber(id), e.id, name .. ": id of the table")
	eq(tiles, e.w .. "x" .. e.h, name .. ": size of the table")
	eq(send, e.dx .. ":" .. e.dy, name .. ": send offset of the table")
end

-- ---------------------------------------------------------------- the gate
ChaosVfx = {}
function Vfx(pos, name, raw)
	local e = ChaosVfx[name]
	if not e or not pos then
		return false
	end
	Position(pos.x + e.dx, pos.y + e.dy, pos.z):sendMagicEffect(e.id)
	return true
end
local C = dofile("data/lib/chaos_malgrath_fx.lua")
eq(C.PAIR, 74, "the gate is pair 74")
eq(C.MONSTER, "Malgrath, the Drowned Crown", "the monster")
eq(C.parsePair("a = 1\nchaosClientPair = 74\n"), 74, "the pair of a config text")
eq(C.parsePair("-- chaosClientPair = 74\n"), nil, "a commented line is no pair")
eq(C.parsePair("chaosClientPair = 73 -- note"), 73, "a trailing comment")
eq(C.recordedPair("no/such/config.lua"), nil, "no config file")
C.ON = false
eq(C.live(), false, "closed: not live")
eq(C.pose(1, "mg_ground_slam", 2500), false, "closed: no pose")
eq(C.death(Position(1, 1, 11)), false, "closed: no death effect")
eq(next(ChaosVfx), nil, "closed: nothing joins ChaosVfx")
C.ON = true
eq(C.live(), true, "open: live")
eq(ChaosVfx.mg_ground_slam.id, 5326, "the effects join ChaosVfx")
eq(ChaosVfx.mg_spawn_rise.id, 5333, "the last one too")
eq(ChaosVfx.mg_lightning_rain.dx, ids.effects.mg_lightning_rain.dx, "with their send offset")
eq(C.length("mg_death"), 3200, "the length of the death")
eq(C.length("nope"), nil, "no length of another name")
eq(C.pose(1, "nope", 2500), false, "an unknown name plays nothing")

-- ---------------------------------------------------------------- an attack: it ends with the warning, the boss is hidden and still while it plays
local boss = newBoss(7, 16641, 16021)
sent, events, now = {}, {}, 0
eq(C.pose(7, "mg_ground_slam", 2500), true, "a pose is scheduled")
runTo(499)
eq(#sent, 0, "nothing before the delay (2500 - 1980 = 520 ms)")
eq(boss.outfit.lookType, 3530, "the boss is still seen")
runTo(520)
eq(#sent, 1, "the effect is sent")
local e = ids.effects.mg_ground_slam
eq(sent[1].x, 16641 + e.dx, "at the boss's tile plus the send offset (x)")
eq(sent[1].y, 16021 + e.dy, "(y)")
eq(sent[1].id, 5326, "effect 5326")
eq(boss.outfit.lookType, 0, "the boss is hidden while it plays")
eq(boss.speed, 0, "and does not walk off its tile")
runTo(520 + 1980 - 1)
eq(boss.outfit.lookType, 0, "hidden to the last frame")
runTo(520 + 1980 + 41)
eq(boss.outfit.lookType, 3530, "shown again after the last frame")
eq(boss.speed, 260, "walking again")
eq(C.playing[7], nil, "nothing plays")
eq(C.saved[7], nil, "nothing saved")
-- the effect ends with the warning: 520 + 1980 = 2500
-- a warning shorter than the effect: it starts at once
sent, events, now = {}, {}, 0
eq(C.pose(7, "mg_lightning_rain", 1000), true, "a short warning")
eq(#sent, 1, "plays at once")
runTo(5000)
eq(boss.outfit.lookType, 3530, "shown again")
-- one effect at a time: a second pose while one plays is dropped, the boss shows once
sent, events, now = {}, {}, 0
C.pose(7, "mg_eye_laser", 0)
eq(#sent, 1, "the first plays")
eq(C.pose(7, "mg_crown_inferno", 0), false, "the second is dropped at once: one effect at a time")
eq(C.pose(7, "mg_crown_inferno", 2400), true, "a delayed second is scheduled ...")
eq(#sent, 1, "... and does not play while the first does")
runTo(3000)
eq(#sent, 1, "it is dropped when its turn comes (the first plays until 1960 ms, the second was due at 500)")
eq(boss.outfit.lookType, 3530, "the boss is shown")
eq(boss.speed, 260, "speed back")
-- hidden once: the history holds one hide and one show
local hist = {}
for _, v in ipairs(boss.history) do hist[#hist + 1] = v end
ok(#hist % 2 == 0, "every hide has its show")

-- a boss that dies or vanishes while hidden: nothing to show, no error
sent, events, now = {}, {}, 0
local b2 = newBoss(8, 5, 5)
C.pose(8, "mg_summon", 0)
bosses[8] = nil
runTo(4000)
eq(C.playing[8], nil, "a vanished boss is forgotten")
eq(C.saved[8], nil, "and its saved look")
-- a boss that is gone before the delay plays nothing
sent, events, now = {}, {}, 0
newBoss(9, 5, 5)
C.pose(9, "mg_earthquake_stomp", 2500)
bosses[9] = nil
runTo(3000)
eq(#sent, 0, "no effect for a boss that is gone")

-- ---------------------------------------------------------------- the arrival: the rise, the boss hidden
sent, events, now = {}, {}, 0
local b3 = newBoss(10, 100, 200)
eq(C.rise(b3), true, "the rise plays")
eq(sent[1].id, 5333, "effect 5333")
eq(b3.outfit.lookType, 0, "hidden for the rise")
runTo(2400 + 41)
eq(b3.outfit.lookType, 3530, "standing after it")
eq(C.rise(nil), false, "no boss, no rise")

-- ---------------------------------------------------------------- the death: the collapse alone, nothing hidden
sent = {}
eq(C.death(Position(100, 200, 11)), true, "the collapse plays")
eq(sent[1].id, 5332, "effect 5332")
eq(sent[1].x, 100 + ids.effects.mg_death.dx, "at the tile plus the offset")
eq(C.death(nil), false, "no position, no effect")

-- ---------------------------------------------------------------- the files that use it
local mech = slurp("data/scripts/chaos/boss_mechanics.lua")
ok(mech:find("pcall(ChaosMalgrathFx.pose, f.id, spec.pose, warnMs or 0)", 1, true) ~= nil, "boss_mechanics.lua plays the pose")
ok(mech:find("sendCast(f, spec.label, warnMs, \"telegraph\")\n\tpose(f, spec, warnMs)", 1, true) ~= nil, "right after the cast bar of a telegraph")
ok(mech:find("pose(f, spec, 0)", 1, true) ~= nil, "and at the start of an adds phase")
local lua = slurp("data/scripts/chaos/malgrath.lua")
ok(lua:find("ChaosMalgrathRise", 1, true) and lua:find("ChaosMalgrathDeath", 1, true) and lua:find("L.MONSTER", 1, true), "malgrath.lua registers the rise and the death on the boss")
ok(lua:find("L.live()", 1, true) ~= nil, "only when the gate is open")
-- every pose of the mechanics profile is an effect of the table, six attacks, the adds one of them, and a telegraph's effect ends with its warning
dofile("data/lib/chaos_speed.lua")
dofile("data/scripts/chaos/boss_mechanics_core.lua")
local G = ChaosBossMechCore
local cfg = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local p = cfg.profiles["malgrath, the drowned crown"]
ok(p ~= nil, "the profile, keyed by the lower case name")
local used = {}
local warn = G.warnMs(nil, p.difficulty, p.fair)
for _, t in ipairs(p.telegraphs) do
	ok(t.pose and ids.effects[t.pose], t.key .. ": a pose of the table")
	ok(ids.effects[t.pose].ms <= warn, t.key .. ": the effect (" .. ids.effects[t.pose].ms .. " ms) ends with the warning (" .. warn .. " ms)")
	used[t.pose] = true
end
for _, a in ipairs(p.adds) do
	ok(a.pose and ids.effects[a.pose], "the adds phase: a pose of the table")
	used[a.pose] = true
end
local usedCount = 0
for _ in pairs(used) do usedCount = usedCount + 1 end
eq(usedCount, 6, "six attacks play as effects")
ok(not used.mg_death and not used.mg_spawn_rise, "the death and the arrival are no mechanic")
eq(ids.effects.mg_summon.ms, 2000, "the summon")
eq(p.element, "death", "its mechanics are death")
eq(p.fair.refLevel, 800, "fair for level 800")

print("malgrath_fx_test: " .. n .. " checks")

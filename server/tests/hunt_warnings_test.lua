-- Run from the server/ folder: luajit tests/hunt_warnings_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the hunt warnings' rules (data/scripts/chaos/hunt_warnings_core.lua): the caution effect round an entry, the near
-- and arrival messages, cooldowns, the gap between messages, ghosts, the switch, the config, the storage key.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/hunt_warnings_core.lua")
local W = ChaosHuntWarningsCore
local cfg = dofile("data/scripts/chaos/hunt_warnings_config.lua")

local fails, checks = 0, 0
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

-- ------------------------------------------------------------------ the shipped config and the storage key
eq(#W.validate(cfg), 0, "the shipped config has no problems")
eq(Chaos.storage.huntWarnLast, 7103050, "storage key")
eq(cfg.storage.last, Chaos.storage.huntWarnLast, "config and constants name the same key")
do
	-- the key is inside a reserved block and no other storage in chaos_constants.lua uses it
	local f = io.open("data/scripts/chaos/chaos_constants.lua")
	local text = f:read("*a")
	f:close()
	local n = 0
	for _ in text:gmatch("7103050") do
		n = n + 1
	end
	eq(n, 2, "7103050 appears only in the comment and the key")
end

-- ------------------------------------------------------------------ a small config
local test = {}
for k, v in pairs(cfg) do
	test[k] = v
end
test.cooldownSeconds = 600
test.minGapSeconds = 5
test.effectEveryTicks = 1
test.places = {
	{id = 1, kind = "floor", pos = {x = 100, y = 100, z = 7}, to = {x = 100, y = 100, z = 8}, group = 1, level = 80,
		from = "a", verdict = "danger"},
	{id = 2, kind = "teleport", pos = {x = 120, y = 100, z = 7}, to = {x = 300, y = 300, z = 7}, group = 2, level = 150,
		from = "b", verdict = "extreme"},
}
eq(#W.validate(test), 0, "test config valid")
local bad = {places = {{id = 1, verdict = "ok"}, {id = 1, pos = {x = 1, y = 1, z = 1}, to = {x = 1, y = 1, z = 1}, level = 0}}}
ok(#W.validate(bad) >= 5, "a broken config is reported")

local idx = W.index(test.places)
eq(idx.count, 2, "two places indexed")
eq(#idx.entries[7], 2, "entries by floor")
eq(#idx.landings[8], 1, "landing by floor")

local function pl(id, x, y, z, last)
	return {id = id, pos = {x = x, y = y, z = z}, lastWarn = last or 0, ghost = false}
end

-- ------------------------------------------------------------------ effect
local state = W.newState()
local out = W.tick(idx, test, state, {pl(1, 105, 100, 7)}, 1000)
eq(#out.effects, 1, "an entry in view flashes")
eq(out.effects[1].extreme, false, "danger is not extreme")
eq(#out.messages, 0, "no message outside warnRadius")
out = W.tick(idx, test, state, {pl(1, 109, 100, 7)}, 1001)
eq(#out.effects, 0, "no flash beyond the effect radius")
out = W.tick(idx, test, state, {pl(1, 100, 100, 6)}, 1002)
eq(#out.effects, 0, "no flash from another floor")
out = W.tick(idx, test, state, {pl(1, 103, 100, 7), pl(2, 101, 101, 7)}, 1003)
eq(#out.effects, 1, "two players, one flash")
out = W.tick(idx, test, state, {pl(1, 120, 100, 7)}, 1004)
eq(out.effects[1].extreme, true, "an extreme entry says so")

-- ------------------------------------------------------------------ near message, cooldown, gap
state = W.newState()
out = W.tick(idx, test, state, {pl(1, 102, 100, 7)}, 2000)
eq(#out.messages, 1, "message near the entry")
eq(out.messages[1].kind, "near", "kind near")
eq(out.messages[1].level, 80, "level")
out = W.tick(idx, test, state, {pl(1, 102, 100, 7, 2000)}, 2001)
eq(#out.messages, 0, "not again at once")
out = W.tick(idx, test, state, {pl(1, 102, 100, 7, 2000)}, 2300)
eq(#out.messages, 0, "not again inside the cooldown")
out = W.tick(idx, test, state, {pl(1, 102, 100, 7, 2000)}, 2601)
eq(#out.messages, 1, "again after the cooldown")
out = W.tick(idx, test, state, {pl(2, 102, 100, 7)}, 2602)
eq(#out.messages, 1, "another player is warned on his own")

-- the gap: a second area right after the first
state = W.newState()
out = W.tick(idx, test, state, {pl(1, 121, 100, 7, 3000)}, 3002)
eq(#out.messages, 0, "inside the gap no message")
out = W.tick(idx, test, state, {pl(1, 121, 100, 7, 3000)}, 3006)
eq(#out.messages, 1, "after the gap the message comes")
eq(out.messages[1].verdict, "extreme", "verdict passed on")

-- ------------------------------------------------------------------ arrival
state = W.newState()
out = W.tick(idx, test, state, {pl(1, 100, 101, 8)}, 4000)
eq(#out.messages, 1, "message on arrival")
eq(out.messages[1].kind, "arrive", "kind arrive")
out = W.tick(idx, test, state, {pl(1, 100, 105, 8)}, 4001)
eq(#out.messages, 0, "no message away from the landing")
out = W.tick(idx, test, state, {pl(1, 100, 100, 7)}, 4100)
eq(out.messages[1].kind, "near", "the near kind has its own cooldown")

-- the strongest area wins when two are close
local both = {}
for k, v in pairs(test) do
	both[k] = v
end
both.places = {test.places[1], {id = 3, kind = "floor", pos = {x = 101, y = 100, z = 7}, to = {x = 101, y = 100, z = 8},
	group = 3, level = 200, from = "c", verdict = "extreme"}}
state = W.newState()
out = W.tick(W.index(both.places), both, state, {pl(1, 100, 100, 7)}, 5000)
eq(#out.messages, 1, "one message per tick")
eq(out.messages[1].level, 200, "the extreme area wins")

-- ------------------------------------------------------------------ ghost, switch, logout memory
local ghost = pl(1, 101, 100, 7)
ghost.ghost = true
out = W.tick(idx, test, W.newState(), {ghost}, 6000)
eq(#out.effects + #out.messages, 0, "ghosts are skipped")
local off = {}
for k, v in pairs(test) do
	off[k] = v
end
off.enabled = false
out = W.tick(idx, off, W.newState(), {pl(1, 101, 100, 7)}, 6000)
eq(#out.effects + #out.messages, 0, "switched off")
state = W.newState()
W.tick(idx, test, state, {pl(7, 101, 100, 7)}, 7000)
ok(state.last[7] ~= nil, "memory kept while online")
W.tick(idx, test, state, {pl(8, 300, 300, 7)}, 7001)
ok(state.last[7] == nil, "memory dropped after logout")
out = W.tick(W.index({}), test, W.newState(), {pl(1, 101, 100, 7)}, 1)
eq(#out.messages, 0, "no places, no messages")

print(string.format("hunt_warnings_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)

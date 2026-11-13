-- Run from the server/ folder: luajit tests/radar_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the minimap radar rules (data/scripts/chaos/radar_core.lua): the config clamps, the circle of the radius, same floor only,
-- ghosts, summons, NPC / party / boss switches, the order and the cap, rounding, the diff (an equal list is not sent again; a list
-- that became empty is sent once), the interval, the per tick limit with round robin, a watcher that left, the rectangles with no
-- radar, and the size of a full message (under 8192 bytes at the largest cap). Also checks the opcode is the map marker one.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/radar_core.lua")
local R = ChaosRadar
local cfgFile = dofile("data/scripts/chaos/radar_config.lua")
local cfg = R.sanitize(cfgFile)

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

-- ------------------------------------------------------------------ opcode and the owner's numbers
eq(ChaosOpcodes.mapMarkers, 153, "the radar rides on the map marker opcode")
local seen = {}
for k, v in pairs(ChaosOpcodes) do
	ok(not seen[v], "opcode " .. v .. " used twice (" .. k .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = k
end
eq(cfgFile.radius, 30, "owner decision: radius 30")
eq(cfgFile.intervalMs, 1500, "owner decision: every 1.5 s")
eq(cfgFile.offInInstances, false, "no mitigation by default: instances")
eq(cfgFile.round, 1, "no mitigation by default: exact positions")
eq(cfgFile.summons, false, "summons of other players left out")
ok(next(cfgFile.offAreas) == nil, "no area with no radar by default")
eq(cfgFile.bosses, true, "boss flag on")

-- ------------------------------------------------------------------ sanitize
local s = R.sanitize({radius = 999, cap = 9999, maxCap = 9999, intervalMs = 1, round = 0, npcs = false, summons = 1, bosses = "yes"})
eq(s.radius, 60, "radius clamped")
eq(s.maxCap, 400, "maxCap clamped")
eq(s.cap, 400, "cap clamped to maxCap")
eq(s.intervalMs, 250, "interval clamped")
eq(s.round, 1, "round at least 1")
eq(s.npcs, false, "npcs switch kept")
eq(s.summons, false, "summons only for true")
eq(s.bosses, false, "bosses only for true")
local d = R.sanitize(nil)
eq(d.radius, 30, "defaults without config")
eq(d.npcs, true, "npcs default on")
eq(R.sanitize({cap = "x"}).cap, 120, "bad number falls back")

-- ------------------------------------------------------------------ plan
local me = {x = 1000, y = 1000, z = 7}
local function mon(dx, dy, extra)
	local e = {x = me.x + dx, y = me.y + dy, z = me.z}
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return e
end
local function plan(entries, over)
	local c = R.sanitize(cfgFile)
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return R.plan(me, entries, c)
end

eq(#plan({}), 0, "nothing in, nothing out")
eq(#plan({mon(30, 0)}), 1, "on the circle: listed")
eq(#plan({mon(31, 0)}), 0, "one tile outside: not listed")
eq(#plan({mon(21, 21)}), 1, "21,21 is 29.7 tiles away")
eq(#plan({mon(22, 22)}), 0, "22,22 is 31.1 tiles away: a circle, not a square")
eq(#plan({mon(0, 0, {z = 8})}), 0, "another floor is not listed")
eq(#plan({mon(3, 3, {ghost = true})}), 0, "ghost not listed")
eq(#plan({mon(3, 3, {summon = true})}), 0, "summon not listed by default")
eq(#plan({mon(3, 3, {summon = true})}, {summons = true}), 1, "summon listed with the switch")
eq(#plan({mon(3, 3, {npc = true})}), 1, "NPC listed")
eq(#plan({mon(3, 3, {npc = true})}, {npcs = false}), 0, "NPC off")
eq(#plan({mon(3, 3, {party = true})}), 1, "party listed")
eq(#plan({mon(3, 3, {party = true})}, {party = false}), 0, "party off")
eq(#plan({mon(3, 3, {party = true, z = 8})}), 0, "party on another floor is the party markers' job")

local p = plan({mon(5, 5), mon(1, 1, {boss = true}), mon(2, 2, {npc = true}), mon(3, 3, {party = true}), mon(-1, 0)})
eq(#p, 5, "five dots")
eq(p[1][3], R.BOSS, "boss first, flag 1")
eq(p[2][3], R.PARTY, "party second, flag 4")
eq(p[3][3], R.NPC, "NPC third, flag 2")
eq(p[4][3], 0, "monster next, flag 0")
eq(p[4][1], me.x - 1, "nearest monster first")
eq(p[5][1], me.x + 5, "farther monster last")
local nb = plan({mon(1, 1, {boss = true})}, {bosses = false})
eq(nb[1][3], 0, "boss flag off: a plain monster")
local cut = {}
for i = 1, 50 do
	cut[i] = mon(i % 20, math.floor(i / 20))
end
cut[#cut + 1] = mon(25, 0, {boss = true})
local capped = plan(cut, {cap = 10})
eq(#capped, 10, "cap cuts the list")
eq(capped[1][3], R.BOSS, "the boss survives the cap")
local rounded = plan({mon(3, 5)}, {round = 4})
eq(rounded[1][1] % 4, 0, "x rounded to a multiple of 4")
eq(rounded[1][2] % 4, 0, "y rounded to a multiple of 4")
eq(plan({mon(3, 5)})[1][1], me.x + 3, "exact by default")

-- the same input gives the same list (so the diff can skip)
local e1 = {mon(5, 5), mon(5, 5), mon(-5, 5), mon(5, -5)}
eq(R.key(me, plan(e1)), R.key(me, plan(e1)), "equal input, equal key")
local e2 = {mon(5, 5), mon(5, 6)}
ok(R.key(me, plan(e1)) ~= R.key(me, plan(e2)), "other list, other key")
ok(R.key(me, {}) ~= R.key({x = 1, y = 1, z = 8}, {}), "another floor is another key")

-- ------------------------------------------------------------------ areas with no radar
local areas = {{from = {x = 10, y = 10, z = 7}, to = {x = 20, y = 20, z = 7}}}
ok(R.inOffArea(15, 15, 7, areas), "inside a rectangle")
ok(not R.inOffArea(21, 15, 7, areas), "outside it")
ok(not R.inOffArea(15, 15, 8, areas), "another floor")
ok(R.inOffArea(20, 10, 7, {{from = {x = 20, y = 20, z = 7}, to = {x = 10, y = 10, z = 7}}}), "corners in any order")

-- ------------------------------------------------------------------ the scheduler
local state, sent, world = R.newState(), {}, {}
local function io()
	return {
		collect = function(id)
			local w = world[id]
			if not w then
				return nil
			end
			return w.viewer, w.entries, w.off
		end,
		send = function(id, payload)
			sent[#sent + 1] = {id = id, payload = payload}
		end
	}
end
local c = R.sanitize(cfgFile)
world[1] = {viewer = me, entries = {mon(5, 5), mon(9, 9, {boss = true})}}
R.setWatch(state, 1, true)
local st = R.tick(state, io(), c, 0)
eq(st.sends, 1, "first tick sends")
eq(#sent, 1, "one message")
eq(sent[1].payload.z, 7, "payload floor")
eq(sent[1].payload.r, 30, "payload radius")
eq(#sent[1].payload.m, 2, "payload dots")
st = R.tick(state, io(), c, 500)
eq(#sent, 1, "inside the interval nothing is read")
eq(st.looked, 0, "not looked at before the interval")
st = R.tick(state, io(), c, 1500)
eq(#sent, 1, "nothing changed: an equal list is not sent again")
eq(st.looked, 1, "looked at again after the interval")
world[1].entries[1] = mon(6, 5)
R.tick(state, io(), c, 3000)
eq(#sent, 2, "a moved monster is sent")
world[1].entries = {}
R.tick(state, io(), c, 4500)
eq(#sent, 3, "a list that became empty is sent once")
eq(#sent[3].payload.m, 0, "and it is empty")
R.tick(state, io(), c, 6000)
eq(#sent, 3, "then nothing")
world[1].viewer = {x = me.x, y = me.y, z = 8}
R.tick(state, io(), c, 7500)
eq(#sent, 4, "a floor change is a change even when empty")
world[1].off = true
world[1].entries = {mon(1, 1)}
world[1].viewer = me
R.tick(state, io(), c, 9000)
eq(#sent[#sent].payload.m, 0, "a place with no radar gets an empty list")
world[1] = nil
R.tick(state, io(), c, 10500)
ok(state.watch[1] == nil, "a watcher that left is dropped")

-- switching off and on
world[2] = {viewer = me, entries = {mon(2, 2)}}
R.setWatch(state, 2, true)
local before = #sent
R.tick(state, io(), c, 12000)
eq(#sent, before + 1, "a new watcher is sent its list")
eq(R.setWatch(state, 2, false), true, "switching off a watcher says it was one")
eq(R.setWatch(state, 2, false), false, "and twice says it was not")
R.tick(state, io(), c, 13500)
eq(#sent, before + 1, "no longer served")
R.setWatch(state, 2, true)
R.tick(state, io(), c, 15000)
eq(#sent, before + 2, "switched on again: the list goes out again even if equal")

-- the per tick limit and the round robin
local st2 = R.newState()
local got = {}
local io2 = {
	collect = function(id)
		return {x = 500, y = 500, z = 7}, {}
	end,
	send = function(id)
		got[#got + 1] = id
	end
}
for id = 1, 10 do
	R.setWatch(st2, id, true)
end
local small = R.sanitize(cfgFile)
small.maxPerTick = 4
R.tick(st2, io2, small, 0)
eq(#got, 4, "four watchers served in the first tick")
eq(got[1], 1, "in order")
R.tick(st2, io2, small, 1)
eq(#got, 8, "the next four in the next tick")
eq(got[5], 5, "round robin goes on after the last one")
R.tick(st2, io2, small, 2)
eq(#got, 10, "the rest, and every watcher once")
R.tick(st2, io2, small, 3)
eq(#got, 10, "all served, none due yet (equal lists are not sent again anyway)")

-- ------------------------------------------------------------------ message size at the largest cap
local function jsonish(v)
	if type(v) == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i, x in ipairs(v) do
				parts[i] = jsonish(x)
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in pairs(v) do
			parts[#parts + 1] = '"' .. tostring(k) .. '":' .. jsonish(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end
local many = {}
for i = 1, 800 do
	many[i] = {x = 65000 + (i % 61) - 30, y = 65000 + math.floor(i / 61) - 10, z = 7, boss = i % 7 == 0}
end
local big = R.sanitize({cap = 400, maxCap = 400, radius = 60})
local list = R.plan({x = 65000, y = 65000, z = 7}, many, big)
local buffer = jsonish({action = "radar", data = R.payload({x = 65000, y = 65000, z = 15}, list, big)})
ok(#buffer < 8192, "400 dots with five digit coordinates are " .. #buffer .. " bytes")
local def = R.plan({x = 65000, y = 65000, z = 7}, many, c)
eq(#def, 120, "the default cap lists 120")
ok(#jsonish({action = "radar", data = R.payload(me, def, c)}) < 3000, "a default message is small")

if fails > 0 then
	print(fails .. " of " .. checks .. " checks failed")
	os.exit(1)
end
print("radar_test: " .. checks .. " checks ok")

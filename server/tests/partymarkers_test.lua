-- Run from the server/ folder: luajit tests/partymarkers_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the party markers' rules (data/scripts/chaos/partymarkers_core.lua): health steps, who sees whom (ghost mode,
-- battleground scopes), the diff (only changes are sent, one list per scope), the membership edge cases (join, leave,
-- disband, a watcher gone), the throttle (parties and messages per tick, round robin) and a cost benchmark of 100
-- parties of 4. Also checks that the opcode is free.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/partymarkers_core.lua")
local P = ChaosPartyMarkers
local cfg = dofile("data/scripts/chaos/partymarkers_config.lua")
P.cfg = cfg

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

-- ------------------------------------------------------------------ opcode
eq(ChaosOpcodes.mapMarkers, 153, "opcode")
local seen = {}
for k, v in pairs(ChaosOpcodes) do
	ok(not seen[v], "opcode " .. v .. " used twice (" .. k .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = k
end
-- the reference server's opcodes, the base client's ExtendedIds and the admin panel's 120 (server/README.md)
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 120, 136, 140, 144, 145, 146, 181, 201, 202, 210, 212, 213, 230, 246}) do
	ok(v ~= ChaosOpcodes.mapMarkers, "opcode collides with " .. v)
end

-- ------------------------------------------------------------------ health steps
eq(P.hpPct(1000, 1000, 10), 100, "full")
eq(P.hpPct(0, 1000, 10), 0, "dead")
eq(P.hpPct(1, 1000, 10), 10, "alive is at least one step")
eq(P.hpPct(999, 1000, 10), 90, "hurt is never 100")
eq(P.hpPct(540, 1000, 10), 50, "rounded down")
eq(P.hpPct(550, 1000, 10), 60, "rounded up")
eq(P.hpPct(50, 0, 10), 0, "no max")
eq(P.hpPct(300, 1000, 25), 25, "other step")

-- ------------------------------------------------------------------ helpers
local function member(id, x, y, z, extra)
	local m = {id = id, name = "M" .. id, x = x, y = y, z = z, hp = 1000, hpMax = 1000}
	for k, v in pairs(extra or {}) do
		m[k] = v
	end
	return m
end
local function ids(list)
	local out = {}
	for _, e in ipairs(list) do
		out[#out + 1] = e.i
	end
	return table.concat(out, ",")
end

-- ------------------------------------------------------------------ visibility
ok(P.visibleTo(member(1, 1, 1, 7), ""), "plain member is visible")
ok(not P.visibleTo(member(1, 1, 1, 7, {ghost = true}), ""), "ghost hidden")
ok(not P.visibleTo(member(1, 1, 1, 7, {ghost = true}), "bg:1:1"), "ghost hidden in any scope")
ok(P.visibleTo(member(1, 1, 1, 7, {scope = "bg:1:1"}), "bg:1:1"), "same team sees")
ok(not P.visibleTo(member(1, 1, 1, 7, {scope = "bg:1:1"}), "bg:1:2"), "other team does not")
ok(not P.visibleTo(member(1, 1, 1, 7, {scope = "bg:1:1"}), ""), "outside does not see into the match")
ok(P.visibleTo(member(1, 1, 1, 7), "bg:1:1"), "inside sees the members outside")
eq(P.entry({id = 1, name = "A"}), nil, "no position, no entry")
local e = P.entry(member(4, 100.0, 200, 8, {hp = 500}), 10)
eq(e.i, 4, "entry id"); eq(e.x, 100, "entry x"); eq(e.z, 8, "entry z"); eq(e.p, 50, "entry hp"); eq(e.n, "M4", "entry name")

-- ------------------------------------------------------------------ diff
local sent = {}
local party = {member(1, 100, 100, 7), member(2, 110, 100, 7), member(3, 500, 500, 8)}
local msgs = P.plan(sent, party, {1, 2, 3}, cfg)
eq(#msgs, 1, "one list for one scope")
eq(#msgs[1].ids, 3, "to all three watchers")
eq(ids(msgs[1].list), "1,2,3", "everyone listed, the viewer included, party order")
eq(msgs[1].list[3].z, 8, "the member on another floor keeps its floor")
eq(#P.plan(sent, party, {1, 2, 3}, cfg), 0, "nothing changed: nothing sent")
party[2].x = 111
msgs = P.plan(sent, party, {1, 2, 3}, cfg)
eq(#msgs, 1, "a step is a change"); eq(#msgs[1].ids, 3, "everyone gets it")
party[3].z = 9
eq(#P.plan(sent, party, {1, 2, 3}, cfg), 1, "a floor change is a change")
party[1].hp = 900
eq(#P.plan(sent, party, {1, 2, 3}, cfg), 1, "hurt from full is a change (never 100 when hurt)")
party[1].hp = 880
eq(#P.plan(sent, party, {1, 2, 3}, cfg), 0, "a small health change inside a step is not")
party[1].hp = 600
eq(#P.plan(sent, party, {1, 2, 3}, cfg), 1, "a health step is")
eq(#P.plan(sent, party, {2}, cfg, true), 1, "forced (login) even unchanged")
eq(#P.plan(sent, party, {9}, cfg), 0, "a watcher that is not a member gets nothing")

-- ghost and scopes
sent = {}
party = {member(1, 100, 100, 7), member(2, 110, 100, 7, {ghost = true}), member(3, 120, 100, 7, {scope = "bg:5:1"}),
	member(4, 130, 100, 7, {scope = "bg:5:1"}), member(5, 140, 100, 7, {scope = "bg:5:2"})}
msgs = P.plan(sent, party, {1, 2, 3, 4, 5}, cfg)
local byWatcher = {}
for _, m in ipairs(msgs) do
	for _, id in ipairs(m.ids) do
		byWatcher[id] = ids(m.list)
	end
end
eq(#msgs, 3, "three scopes: outside, team 1, team 2")
eq(byWatcher[1], "1", "outside: the ghost and the match are hidden")
eq(byWatcher[2], "1", "the ghost sees the others but not itself")
eq(byWatcher[3], "1,3,4", "team 1 sees its team and the members outside")
eq(byWatcher[4], "1,3,4", "same list for the whole team")
eq(byWatcher[5], "1,5", "team 2 does not see team 1")
party[2].x = 200
eq(#P.plan(sent, party, {1, 2, 3, 4, 5}, cfg), 0, "a ghost moving is no change for anyone")
party[3].x = 200
msgs = P.plan(sent, party, {1, 2, 3, 4, 5}, cfg)
eq(#msgs, 1, "a team 1 move reaches team 1 only"); eq(#msgs[1].ids, 2, "both of team 1")

-- cap
local big = {}
for i = 1, 40 do
	big[i] = member(i, i, 1, 7)
end
local list = P.listFor(big, "", cfg)
eq(#list, cfg.maxMembers, "capped")

-- ------------------------------------------------------------------ ticks: membership edge cases
local world = {} -- key -> plain members
local sends, clears = {}, {}
local io = {
	read = function(key) return world[key] end,
	send = function(idlist, l)
		for _, id in ipairs(idlist) do
			sends[id] = ids(l)
		end
	end,
	clear = function(id) clears[id] = true end
}
local function reset()
	sends, clears = {}, {}
end
local function parties(map)
	local out = {}
	for key, w in pairs(map) do
		out[key] = {watchers = w}
	end
	return out
end
local state = P.newState()
world[1] = {member(1, 100, 100, 7), member(2, 101, 100, 7)}
reset()
P.tick(state, parties({[1] = {1, 2}}), io, cfg)
eq(sends[1], "1,2", "party formed: leader told"); eq(sends[2], "1,2", "party formed: member told")
-- join
world[1][3] = member(3, 300, 300, 6)
reset()
P.tick(state, parties({[1] = {1, 2, 3}}), io, cfg)
eq(sends[1], "1,2,3", "join: old members updated"); eq(sends[3], "1,2,3", "join: the new member gets the list")
-- a member without the module (not a watcher) is still shown
world[1][4] = member(4, 50, 50, 7)
reset()
P.tick(state, parties({[1] = {1, 2, 3}}), io, cfg)
eq(sends[1], "1,2,3,4", "a member whose client has no markers is still shown"); eq(sends[4], nil, "but not sent anything")
-- leave
table.remove(world[1], 3)
world[3] = nil
reset()
P.tick(state, parties({[1] = {1, 2}}), io, cfg)
eq(sends[1], "1,2,4", "leave: the others updated"); ok(clears[3], "leave: the leaver is cleared once")
reset()
P.tick(state, parties({[1] = {1, 2}}), io, cfg)
ok(not clears[3], "cleared only once"); eq(sends[1], nil, "no change: nothing")
-- leadership passed: a new key, same members in a new order
world[2] = {member(2, 101, 100, 7), member(1, 100, 100, 7), member(4, 50, 50, 7)}
world[1] = nil
reset()
P.tick(state, parties({[2] = {1, 2}}), io, cfg)
eq(sends[1], "2,1,4", "new leader first"); ok(not clears[1] and not clears[2], "nobody cleared on a leader change")
-- disband
reset()
P.tick(state, parties({}), io, cfg)
ok(clears[1] and clears[2], "disband: everyone cleared")
eq(next(state.sent), nil, "nothing remembered after a disband")
-- the party is gone between collect and read (logout in between): nothing sent, no error
reset()
P.tick(state, parties({[7] = {7}}), io, cfg)
eq(sends[7], nil, "a vanished party sends nothing")

-- ------------------------------------------------------------------ throttle
eq(table.concat(P.rotate({1, 2, 3, 4, 5}, nil), ","), "1,2,3,4,5", "rotate: from the start")
eq(table.concat(P.rotate({1, 2, 3, 4, 5}, 3), ","), "4,5,1,2,3", "rotate: after the cursor")
eq(table.concat(P.rotate({1, 2, 3, 4, 5}, 5), ","), "1,2,3,4,5", "rotate: wraps")
eq(table.concat(P.rotate({10, 20, 30}, 15), ","), "20,30,10", "rotate: a cursor that left")
local small = {maxMembers = 30, hpStep = 10, maxPartiesPerTick = 3, maxSendsPerTick = 100}
state = P.newState()
world = {}
local map = {}
for k = 1, 5 do
	local key = k * 10
	world[key] = {member(key, k, k, 7), member(key + 1, k, k, 7)}
	map[key] = {key, key + 1}
end
reset()
local st = P.tick(state, parties(map), io, small)
eq(st.parties, 3, "throttle: three parties this tick"); eq(st.waiting, 2, "two wait")
ok(sends[10] and sends[20] and sends[30] and not sends[40], "the first three")
reset()
st = P.tick(state, parties(map), io, small)
ok(sends[40] and sends[50], "the waiting ones come next"); eq(st.parties, 3, "then wraps around")
-- message budget
small.maxPartiesPerTick, small.maxSendsPerTick = 100, 4
state = P.newState()
reset()
st = P.tick(state, parties(map), io, small)
eq(st.sends, 4, "message budget"); eq(st.parties, 2, "two parties of two"); eq(st.waiting, 3, "the rest waits")
local served = 0
for _ = 1, 3 do
	st = P.tick(state, parties(map), io, small)
end
for key in pairs(map) do
	if state.sent[key] then
		served = served + 1
	end
end
eq(served, 5, "every party served within a few ticks")

-- ------------------------------------------------------------------ benchmark: 100 parties of 4
local function jsonish(v) -- a plain serializer, about the work of json.encode
	if type(v) == "table" then
		local parts = {}
		for k, x in pairs(v) do
			parts[#parts + 1] = tostring(k) .. ":" .. jsonish(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end
local engine = {}
for k = 1, 100 do
	local key = k * 10
	engine[key] = {}
	for j = 0, 3 do
		engine[key][j + 1] = {id = key + j, name = "Member" .. (key + j), x = 1000 + k * 7 + j, y = 1000 + j, z = 7, hp = 900, hpMax = 1000}
	end
end
local bytes, msgCount = 0, 0
local benchIo = {
	read = function(key)
		local out = {}
		for i, m in ipairs(engine[key]) do -- the engine reads: a fresh table per member, like partymarkers.lua plain()
			out[i] = {id = m.id, name = m.name, x = m.x, y = m.y, z = m.z, hp = m.hp, hpMax = m.hpMax, ghost = false}
		end
		return out
	end,
	send = function(idlist, l)
		local buffer = jsonish({action = "party", data = {m = l}})
		bytes, msgCount = bytes + #buffer * #idlist, msgCount + #idlist
	end,
	clear = function() end
}
local all = {}
for key, members in pairs(engine) do
	local w = {}
	for _, m in ipairs(members) do
		w[#w + 1] = m.id
	end
	all[key] = {watchers = w}
end
local function bench(ticks, move)
	local s = P.newState()
	P.tick(s, all, benchIo, cfg)
	bytes, msgCount = 0, 0
	local t0 = os.clock()
	for t = 1, ticks do
		if move then
			for _, members in pairs(engine) do
				for _, m in ipairs(members) do
					m.x = m.x + 1
				end
			end
		end
		P.tick(s, all, benchIo, cfg)
	end
	return (os.clock() - t0) * 1000 / ticks, msgCount / ticks, bytes / ticks
end
local quietMs = bench(50, false)
local busyMs, busyMsgs, busyBytes = bench(50, true)
print(string.format("benchmark 100 parties x 4: idle %.3f ms/tick (0 messages), all moving %.3f ms/tick, %d messages, %d bytes/tick",
	quietMs, busyMs, busyMsgs, busyBytes))
eq(busyMsgs, 400, "all moving: one message per watcher")
ok(busyMs < 50, "all moving under 50 ms per tick")

print(string.format("partymarkers_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

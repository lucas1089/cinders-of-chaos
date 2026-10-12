-- Run from the server/ folder: luajit tests/tilebars_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the progress bars over tiles (server/README.md "Progress bars over tiles"): the opcode is free, the core
-- (tilebars_core.lua: set / update / remove, countdowns and their expiry, who sees what, the progress throttle, message
-- size), the glue (tilebars.lua) against a mocked engine (spectators, owner bars, walking away, hello, logout) and the
-- three users (battleground braziers, profession nodes, the invasion breach).
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/tilebars_core.lua")
local K = ChaosTileBarsCore
local cfg = dofile("data/scripts/chaos/tilebars_config.lua")

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
eq(ChaosOpcodes.tileBars, 156, "opcode")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
-- the reference server's opcodes, the base client's ExtendedIds (0x8C = 140) and the admin panel's 120
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246,
		120, 154, 155}) do
	ok(ChaosOpcodes.tileBars ~= v, "not a taken opcode " .. v)
end

-- ------------------------------------------------------------------ normalize
local b = K.normalize({pos = {x = 100, y = 200, z = 7}, label = "Well", progress = 1.7, color = "#AABBCC"}, cfg, 0)
eq(b.pos.x, 100, "pos x")
eq(b.v, 1, "progress clamped to 1")
eq(b.color, "#aabbcc", "colour lower case")
b = K.normalize({pos = {1, 2, 3}, progress = -2, color = "red"}, cfg, 0)
eq(b.pos.z, 3, "array position")
eq(b.v, 0, "progress clamped to 0")
eq(b.color, cfg.defaultColor, "bad colour: default")
eq(K.normalize({pos = {x = 1, y = 2}}, cfg, 0), nil, "no z")
eq(K.normalize({pos = {x = 1, y = 2, z = 16}}, cfg, 0), nil, "z out of range")
eq(K.normalize(nil, cfg, 0), nil, "no definition")
b = K.normalize({pos = {1, 2, 3}, endsIn = 10, total = 40}, cfg, 5000)
eq(b.endMs, 15000, "countdown end")
eq(b.totalMs, 40000, "countdown total")
eq(b.v, nil, "a countdown has no progress")
b = K.normalize({pos = {1, 2, 3}, endsIn = 10, total = 4}, cfg, 0)
eq(b.totalMs, 10000, "total is at least the countdown")
eq(K.normalize({pos = {1, 2, 3}, endsIn = -1}, cfg, 0), nil, "negative countdown")
eq(K.label("a\nb", cfg), "a b", "label without line breaks")
eq(#K.label(string.rep("x", 100), cfg), cfg.labelMax, "label cut")
eq(K.label(nil, cfg), "", "no label")
ok(not K.validId(string.rep("x", 65), cfg), "id too long")
ok(not K.validId("", cfg), "empty id")
ok(K.validId("bg:1:2", cfg), "id")

-- ------------------------------------------------------------------ set / update / remove
local st = K.newState()
local P = {x = 100, y = 100, z = 7}
eq(K.set(st, "a", {pos = P, label = "A", progress = 0.2}, cfg, 0), "new", "new bar")
eq(st.count, 1, "count")
eq(K.set(st, "a", {pos = P, label = "A", progress = 0.2}, cfg, 0), nil, "same again: nothing")
eq(K.set(st, "a", {pos = P, label = "A", progress = 0.205}, cfg, 0), nil, "tiny step: nothing")
eq(st.bars.a.v, 0.205, "the value is kept")
eq(K.set(st, "a", {pos = P, label = "A", progress = 0.3}, cfg, 0), "progress", "progress step")
eq(K.set(st, "a", {pos = P, label = "A", progress = 1}, cfg, 0), "progress", "progress to 1")
eq(K.set(st, "a", {pos = P, label = "A", progress = 1}, cfg, 0), nil, "1 again")
eq(K.set(st, "a", {pos = P, label = "B", progress = 1}, cfg, 0), "full", "label change")
eq(K.set(st, "a", {pos = P, label = "B", progress = 1, color = "#112233"}, cfg, 0), "full", "colour change")
eq(K.set(st, "a", {pos = {x = 101, y = 100, z = 7}, label = "B", progress = 1, color = "#112233"}, cfg, 0), "full",
	"moved")
eq(K.set(st, "a", {pos = {x = 101, y = 100, z = 7}, label = "B", endsIn = 5, color = "#112233"}, cfg, 0), "full",
	"progress -> countdown")
eq(K.set(st, "a", {pos = {x = 101, y = 100, z = 7}, label = "B", endsIn = 5, color = "#112233"}, cfg, 100), nil,
	"same end again (100 ms later): nothing")
eq(K.set(st, "a", {pos = {x = 101, y = 100, z = 7}, label = "B", endsIn = 5, color = "#112233"}, cfg, 2000), "full",
	"the end moved")
eq(K.setProgress(st, "a", 0.5, cfg, 0), false, "setProgress on a countdown")
eq(K.set(st, "b", {pos = P, progress = 0}, cfg, 0), "new", "second bar")
eq(K.setProgress(st, "b", 0.5, cfg, 0), "progress", "setProgress")
eq(st.bars.b.v, 0.5, "setProgress value")
eq(K.set(st, "", {pos = P}, cfg, 0), false, "bad id refused")
eq(K.set(st, "c", {pos = {x = 1}}, cfg, 0), false, "bad position refused")
eq(K.remove(st, "a"), true, "remove")
eq(K.remove(st, "a"), false, "remove twice")
eq(st.count, 1, "count after remove")
K.set(st, "bg:1:1", {pos = P}, cfg, 0)
K.set(st, "bg:1:2", {pos = P}, cfg, 0)
K.set(st, "bg:12:1", {pos = P}, cfg, 0)
eq(K.removePrefix(st, "bg:1:"), 2, "remove by prefix")
ok(st.bars["bg:12:1"] ~= nil, "prefix is exact")
eq(st.count, 2, "count after prefix")
local small = {maxBars = 2}
for k, v in pairs(cfg) do
	if small[k] == nil then small[k] = v end
end
local full = K.newState()
K.set(full, "x", {pos = P}, small, 0)
K.set(full, "y", {pos = P}, small, 0)
local r, why = K.set(full, "z", {pos = P}, small, 0)
ok(r == false and why == "too many bars", "cap on bars")
ok(K.set(full, "x", {pos = P, progress = 0.5}, small, 0) == "progress", "an update passes the cap")

-- ------------------------------------------------------------------ expiry
st = K.newState()
K.set(st, "t1", {pos = P, endsIn = 2}, cfg, 0)
K.set(st, "t2", {pos = P, endsIn = 2, keep = true}, cfg, 0)
K.set(st, "t3", {pos = P, progress = 0.5}, cfg, 0)
eq(#K.expire(st, cfg, 2500), 0, "not yet (grace)")
local gone = K.expire(st, cfg, 3000)
eq(#gone, 1, "one expired")
eq(gone[1], "t1", "the countdown")
ok(st.bars.t2 and st.bars.t3, "kept ones stay")

-- ------------------------------------------------------------------ wire
local w = K.wire("t2", st.bars.t2, 500)
eq(w.l, 1500, "ms left")
eq(w.t, 2000, "ms in all")
eq(w.p[1], 100, "wire position")
w = K.wire("t3", st.bars.t3, 0)
eq(w.v, 0.5, "wire progress")
w = K.wire("t2", st.bars.t2, 9999)
eq(w.l, 0, "left never negative")

-- ------------------------------------------------------------------ who sees what
local bar = st.bars.t3
local function V(cid, x, y, z, name, guid)
	return {cid = cid, name = name or ("p" .. cid), guid = guid or cid, pos = {x = x, y = y, z = z}}
end
ok(K.visible(bar, V(1, 100, 100, 7), cfg), "on the tile")
ok(K.visible(bar, V(1, 109, 107, 7), cfg), "at the range")
ok(not K.visible(bar, V(1, 110, 100, 7), cfg), "too far east")
ok(not K.visible(bar, V(1, 100, 92, 7), cfg), "too far north")
ok(not K.visible(bar, V(1, 100, 100, 6), cfg), "another floor")
st.bars.t3.owner = {name = "Ann", guid = 5}
ok(K.visible(bar, V(1, 100, 100, 7, "Ann", 5), cfg), "the owner")
ok(not K.visible(bar, V(2, 100, 100, 7, "Bob", 6), cfg), "not the owner")
ok(not K.visible(bar, V(3, 100, 100, 7, "Ann", 9), cfg), "same name, other character")
st.bars.t3.owner = nil

-- ------------------------------------------------------------------ plan: spectators, throttle, walking away
st = K.newState()
K.set(st, "w", {pos = P, label = "Well", progress = 0}, cfg, 0)
local near, far = V(1, 102, 101, 7), V(2, 130, 100, 7)
local out = K.plan(st, {near, far}, cfg, 0)
eq(#out, 1, "only the near player hears")
eq(out[1].cid, 1, "the near one")
eq(#out[1].s, 1, "one bar")
eq(out[1].s[1].n, "Well", "its label")
eq(#K.plan(st, {near, far}, cfg, 100), 0, "nothing new")
K.set(st, "w", {pos = P, label = "Well", progress = 0.1}, cfg, 100)
eq(#K.plan(st, {near}, cfg, 200), 0, "progress throttled (200 ms after the first send)")
K.set(st, "w", {pos = P, label = "Well", progress = 0.2}, cfg, 300)
eq(#K.plan(st, {near}, cfg, 400), 0, "still throttled")
out = K.plan(st, {near}, cfg, 500)
eq(#out, 1, "progress goes out after progressMs")
eq(out[1].s[1].v, 0.2, "the latest value (coalesced)")
eq(#K.plan(st, {near}, cfg, 600), 0, "and only once")
K.set(st, "w", {pos = P, label = "Well!", progress = 0.3}, cfg, 600)
out = K.plan(st, {near}, cfg, 650)
eq(#out, 1, "a label change is not throttled")
eq(out[1].s[1].n, "Well!", "new label")
-- a second player comes close: gets the bar at once
out = K.plan(st, {near, V(2, 100, 100, 7)}, cfg, 700)
eq(#out, 1, "the newcomer")
eq(out[1].cid, 2, "is player 2")
-- player 1 walks away: told to drop it, then nothing; back: the bar again
near.pos = {x = 120, y = 100, z = 7}
out = K.plan(st, {near}, cfg, 800)
eq(#out, 1, "walked away")
eq(#out[1].s, 0, "no bars")
eq(out[1].d[1], "w", "drop w")
eq(st.known[1], nil, "nothing known any more")
eq(#K.plan(st, {near}, cfg, 900), 0, "then nothing")
near.pos = {x = 101, y = 100, z = 7}
out = K.plan(st, {near}, cfg, 1000)
eq(#out[1].s, 1, "back: the bar again")
-- the bar is removed: the viewers are told
K.remove(st, "w")
out = K.plan(st, {near, V(2, 100, 100, 7)}, cfg, 1100)
eq(#out, 2, "both told")
eq(out[1].d[1], "w", "drop")
-- known viewers are listed for the loop
K.set(st, "w2", {pos = P, progress = 0}, cfg, 0)
K.plan(st, {near}, cfg, 1200)
eq(K.knownViewers(st)[1], 1, "known viewer listed")
K.forget(st, 1)
eq(#K.knownViewers(st), 0, "forgotten")
out = K.plan(st, {near}, cfg, 1300)
eq(#out[1].s, 1, "after forget (hello) everything again")
-- owner bars
st = K.newState()
K.set(st, "own", {pos = P, endsIn = 60, owner = {name = "Ann", guid = 5}}, cfg, 0)
out = K.plan(st, {V(1, 100, 100, 7, "Bob", 6), V(2, 100, 100, 7, "Ann", 5)}, cfg, 0)
eq(#out, 1, "owner bar: one player")
eq(out[1].cid, 2, "the owner")
eq(out[1].s[1].l, 60000, "the countdown")
-- duplicated viewers are counted once
st = K.newState()
K.set(st, "w", {pos = P}, cfg, 0)
eq(#K.plan(st, {V(1, 100, 100, 7), V(1, 100, 100, 7)}, cfg, 0), 1, "a viewer twice is told once")

-- ------------------------------------------------------------------ message size
local entry = {s = {}, d = {}}
for i = 1, 95 do
	entry.s[i] = K.wire("bar" .. i, {pos = P, label = string.rep("x", cfg.labelMax), color = "#ffffff", v = 0.5}, 0)
end
for i = 1, 10 do
	entry.d[i] = "gone" .. i
end
local msgs = K.messages(entry, cfg)
eq(#msgs, 3, "105 entries in 3 messages")
local total = 0
for _, m in ipairs(msgs) do
	total = total + #m.s + #m.d
	ok(#m.s + #m.d <= cfg.perMessage, "at most perMessage")
	-- a rough size: every wire bar holds a label of labelMax, an id, 3 numbers, a colour and the keys
	ok((#m.s + #m.d) * (cfg.labelMax + cfg.maxIdLength + 60) < 8192, "a message stays under 8192 bytes")
end
eq(total, 105, "nothing lost")
eq(msgs[1].d[1], "gone1", "drops first")

-- ------------------------------------------------------------------ the client's message
eq(K.clientAction({action = "hello"}), "hello", "hello")
eq(K.clientAction({action = "x"}), nil, "unknown action")
eq(K.clientAction(nil), nil, "junk")

-- ------------------------------------------------------------------ brazier bar
local teams = {{name = "Emberguard", color = "#ff9a3c"}, {name = "Ashbound", color = "#8fb8ff"}}
local d = K.brazierBar(P, "West Well", 50, 0, false, teams)
eq(d.progress, 0.5, "half")
eq(d.color, "#ff9a3c", "team 1 colour")
eq(d.label, "West Well", "name")
d = K.brazierBar(P, "West Well", -100, 2, false, teams)
eq(d.progress, 1, "full")
eq(d.color, "#8fb8ff", "team 2 colour")
eq(d.label, "West Well: Ashbound", "held")
d = K.brazierBar(P, "West Well", 20, 1, true, teams)
eq(d.label, "West Well (contested)", "contested")
d = K.brazierBar(P, "West Well", 0, 0, false, teams)
eq(d.progress, 0, "empty")

-- ------------------------------------------------------------------ glue against a mocked engine
local clock = 0
os.mtime = function() return clock end
local events, globals = {}, {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.kind = t end
	function e:register() events[self.name] = self end
	return e
end
function GlobalEvent(name)
	local e = {name = name}
	function e:interval(ms) self.ms = ms end
	function e:register() globals[self.name] = self end
	return e
end
function Position(x, y, z)
	return {x = x, y = y, z = z}
end
json = {
	encode = function(t) return t end, -- the mock keeps the table so the test can read it
	decode = function(s)
		if s == "hello" then return {action = "hello"} end
		error("bad json")
	end
}
local players, byName = {}, {}
local function mkPlayer(cid, name, guid, x, y, z)
	local p = {cid = cid, name = name, guid = guid, pos = {x = x, y = y, z = z}, sent = {}, events = {}}
	function p:getId() return self.cid end
	function p:getName() return self.name end
	function p:getGuid() return self.guid end
	function p:getPosition() return self.pos end
	function p:registerEvent(n) self.events[#self.events + 1] = n end
	function p:sendExtendedOpcode(op, payload) self.sent[#self.sent + 1] = {op = op, msg = payload} end
	players[cid], byName[name] = p, p
	return p
end
function Player(k)
	if type(k) == "number" then return players[k] end
	return byName[k]
end
Game = Game or {}
function Game.getSpectators(pos, multi, onlyPlayers, minX, maxX, minY, maxY)
	local list = {}
	for _, p in pairs(players) do
		if p.pos.z == pos.z and math.abs(p.pos.x - pos.x) <= maxX and math.abs(p.pos.y - pos.y) <= maxY then
			list[#list + 1] = p
		end
	end
	table.sort(list, function(a, c) return a.cid < c.cid end)
	return list
end

dofile("data/scripts/chaos/tilebars.lua")
local B = ChaosTileBars
ok(globals.ChaosTileBars and globals.ChaosTileBars.ms == cfg.tickMs, "send loop every tickMs")
ok(events.ChaosTileBarsLogin and events.ChaosTileBarsLogin.kind == "login", "login event")
ok(events.ChaosTileBarsLogout and events.ChaosTileBarsLogout.kind == "logout", "logout event")
ok(events.ChaosTileBarsOpcode and events.ChaosTileBarsOpcode.kind == "extendedopcode", "opcode event")

local ann = mkPlayer(1, "Ann", 11, 100, 100, 7)
local bob = mkPlayer(2, "Bob", 12, 140, 100, 7)
events.ChaosTileBarsLogin.onLogin(ann)
ok(ann.events[1] == "ChaosTileBarsOpcode" and ann.events[2] == "ChaosTileBarsLogout", "login registers the events")

local function last(p)
	local s = p.sent[#p.sent]
	return s and s.msg
end
ok(B.set("w", {pos = {x = 101, y = 100, z = 7}, label = "Well", progress = 0.25, color = "#ff0000"}), "set")
globals.ChaosTileBars.onThink(250)
eq(#ann.sent, 1, "Ann gets the bar")
eq(ann.sent[1].op, 156, "on the opcode")
eq(last(ann).action, "bars", "action bars")
eq(last(ann).data.s[1].i, "w", "the id")
eq(last(ann).data.s[1].v, 0.25, "the progress")
eq(#bob.sent, 0, "Bob is too far")
clock = 100
B.progress("w", 0.5)
globals.ChaosTileBars.onThink(250)
eq(#ann.sent, 1, "throttled")
clock = 600
globals.ChaosTileBars.onThink(250)
eq(#ann.sent, 2, "after progressMs")
eq(last(ann).data.s[1].v, 0.5, "new progress")
-- owner bar: only Ann, wherever Bob stands
ok(B.set("prof:11:x", {pos = {x = 140, y = 100, z = 7}, label = "Ready in", endsIn = 10, owner = ann}), "owner bar")
globals.ChaosTileBars.onThink(250)
eq(#bob.sent, 0, "Bob does not get Ann's bar")
eq(#ann.sent, 2, "Ann is too far from it")
ann.pos = {x = 138, y = 100, z = 7}
clock = 700
globals.ChaosTileBars.onThink(250)
local m = last(ann).data
eq(#m.s, 1, "Ann near her node: the countdown")
eq(m.s[1].i, "prof:11:x", "her bar")
eq(m.s[1].l, 9900, "ms left")
eq(m.d[1], "w", "and the well is dropped (she walked away)")
-- hello: clear, then everything again on the next tick
local n = #ann.sent
events.ChaosTileBarsOpcode.onExtendedOpcode(ann, 156, "hello")
eq(last(ann).action, "clear", "hello answered with clear")
events.ChaosTileBarsOpcode.onExtendedOpcode(ann, 155, "hello")
eq(#ann.sent, n + 1, "another opcode is ignored")
events.ChaosTileBarsOpcode.onExtendedOpcode(ann, 156, "junk")
eq(#ann.sent, n + 1, "junk is ignored")
globals.ChaosTileBars.onThink(250)
eq(last(ann).data.s[1].i, "prof:11:x", "sent again after hello")
-- countdown runs out: removed and Ann told
clock = 600 + 10000 + cfg.expireGraceMs
globals.ChaosTileBars.onThink(250)
eq(B.get("prof:11:x"), nil, "expired")
eq(last(ann).data.d[1], "prof:11:x", "Ann told to drop it")
-- logout forgets; a player gone without logout is forgotten by the loop
B.set("w2", {pos = {x = 138, y = 101, z = 7}, progress = 0})
globals.ChaosTileBars.onThink(250)
ok(B.state.known[1] ~= nil, "Ann holds w2")
events.ChaosTileBarsLogout.onLogout(ann)
eq(B.state.known[1], nil, "logout forgets")
globals.ChaosTileBars.onThink(250)
players[1], byName.Ann = nil, nil
B.remove("w2")
globals.ChaosTileBars.onThink(250)
eq(B.state.known[1], nil, "a player who is gone is forgotten")
-- the loop is quiet without bars and viewers
B.removePrefix("")
local before = #bob.sent
globals.ChaosTileBars.onThink(250)
eq(#bob.sent, before, "quiet")
-- a broken definition is refused, the loop survives a bad bar
ok(not B.set("bad", {pos = {x = 1}}), "bad bar refused")
ok(not B.set("bad", nil), "no definition refused")
Chaos.tileBarsConfig.enabled = false
ok(not B.set("off", {pos = {x = 1, y = 1, z = 7}}), "turned off")
Chaos.tileBarsConfig.enabled = true

-- ------------------------------------------------------------------ the users
local function read(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end
local bg = read("data/scripts/chaos/battleground.lua")
ok(bg:find('ChaosTileBars.set("bg:" .. m.id .. ":" .. i, ChaosTileBarsCore.brazierBar(', 1, true) ~= nil,
	"battleground: a bar per brazier at each capture tick")
ok(bg:find('ChaosTileBars.removePrefix("bg:" .. m.id .. ":")', 1, true) ~= nil, "battleground: removed at the end")
local pr = read("data/scripts/chaos/professions.lua")
ok(pr:find('ChaosTileBars.set("prof:" .. S.guid .. ":" .. ch.node', 1, true) ~= nil, "professions: node countdown")
ok(pr:find("endsIn = cfg.respawnMin * 60", 1, true) ~= nil and pr:find("owner = player", 1, true) ~= nil,
	"professions: for the gatherer, as long as the node cooldown")
local inv = read("data/scripts/chaos/invasion.lua")
local _, sets = inv:gsub("breachBar%(true%)", "")
local _, offs = inv:gsub("breachBar%(false%)", "")
eq(sets, 1, "invasion: the breach bar is set in the tick")
eq(offs, 2, "invasion: removed at the end and when stopped")

print(string.format("tilebars_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

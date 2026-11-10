-- Run from the server/ folder: luajit tests/passivetree_keystone_cap_test.lua (and lua5.3; CI runs both). Mock engine API.
-- The keystone cap of the passive tree (O447, owner decision of 2026-11-09): a character holds at most
-- ChaosPassiveTreeConfig.keystoneMax (3) keystones.
--   * what counts, read from the tree data: 44 nodes in four kinds, the same 44 the client marks isKeystone; masteries and
--     class notables do not;
--   * the core: countKeystones, checkKeystones, validatePlan (saved + planned), overCapPresets;
--   * the doors of passivetree.lua: a plain save, planApply, sendNodes carries the cap; a refusal changes nothing;
--   * a build code over the cap is refused whole (buildshare_core.lua plan);
--   * the login: a tree over the cap is refunded once for free with a message, a tree at or under it is never touched,
--     the second login finds nothing to do;
--   * the texts have a pt-BR line. Auto build, loadouts and the generator: passive_builds_test.lua, loadouts_test.lua.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function ok(cond, m)
	checks = checks + 1
	if not cond then error(m or "check failed", 2) end
end
local events = {}
local function object(name)
	local o = {}
	return setmetatable(o, {__index = function(t, k)
		if k == "register" then return function() if name then events[name] = o end return true end end
		return function() return true end
	end})
end
CreatureEvent = function(name) return object(name) end
GlobalEvent = function(name) return object(name) end
TalkAction = function(name) return object(name) end
function addEvent() return 1 end

local rows, inserts, sent = {}, {}, {}
db = {escapeString = function(s) return "'" .. tostring(s) .. "'" end, asyncQuery = function() end,
	query = function(q)
		local p, nodes = q:match("INSERT INTO `[%w_]+` %(`player_id`, `preset`, `name`, `nodes`%) VALUES %(%d+, (%d+), '[^']*', '([^']*)'%)")
		if p then
			inserts[#inserts + 1] = {preset = tonumber(p), nodes = nodes}
			local found
			for _, r in ipairs(rows) do if r.preset == tonumber(p) then r.nodes = nodes; found = true end end
			if not found then rows[#rows + 1] = {preset = tonumber(p), name = "Preset " .. p, nodes = nodes} end
			table.sort(rows, function(a, b) return a.preset < b.preset end)
		end
		return true
	end}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
Chaos.send = function(_, _, action, data) sent[#sent + 1] = {action = action, data = data}; return true end
Chaos.select = function(q)
	if q:find("SELECT `preset`, `name`, `nodes`", 1, true) then
		local out = {}
		for _, r in ipairs(rows) do out[#out + 1] = {preset = r.preset, name = r.name, nodes = r.nodes} end
		return out
	end
	return {}
end
ChaosClassTree = {allowed = function() return true end, write = function() end,
	sanitize = function(_, ids) return ids, {} end}
local clock = 1000000
os.mtime = function() return clock end
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/passivetree.lua")
local ext = events.ChaosPassiveTreeExtended
local login = events.ChaosPassiveTreeLogin
assert(ext and login, "events registered")

local Core = ChaosPassiveTreeCore
local tree = Chaos.load("passivetree_data.lua")
local TEXT = "You can hold at most 3 keystones. Refund one to take another."

-- ------------------------------------------------------------------------------------------------ what counts
eq(ChaosPassiveTreeConfig.keystoneMax, 3, "the cap is 3")
eq(Core.keystoneMax(), 3, "the core reads it")
local kinds, ids = {archetype = 0, pair = 0, line = 0, ascension = 0}, {}
for id, node in pairs(tree.nodes) do
	local kind = Core.keystoneKind(node)
	if kind then
		kinds[kind] = (kinds[kind] or 0) + 1
		ids[#ids + 1] = id
	end
end
table.sort(ids)
eq(kinds.archetype, 24, "24 archetype keystones (rounds 1 to 3)")
eq(kinds.pair, 2, "2 nodes with a keystone per class (621, 624)")
eq(kinds.line, 4, "4 line keystones (369, 376, 383, 390)")
eq(kinds.ascension, 14, "14 class section keystones (8 of the Thief, Necromancer, Monk and Templar lines, 6 of O449)")
eq(#ids, 44, "44 keystone nodes")
eq(Core.keystoneKind(tree.nodes[621]), "pair", "621")
eq(Core.keystoneKind(tree.nodes[369]), "line", "369")
eq(Core.keystoneKind(tree.nodes[631]), "ascension", "631 Living Shadow")
for _, id in ipairs({679, 682, 689, 692, 699, 702}) do
	eq(Core.keystoneKind(tree.nodes[id]), "ascension", id .. " a class section keystone of the Warrior, Ranger or Mystic line")
end
eq(Core.keystoneKind(tree.nodes[77]), "archetype", "77")
-- masteries and class notables never count, nor plain nodes (with or without class lanes)
for _, id in ipairs({665, 666, 667, 668, 703, 704, 705}) do
	eq(Core.keystoneKind(tree.nodes[id]), nil, "mastery " .. id .. " is no keystone")
end
for _, id in ipairs({629, 630, 633, 639, 640, 642, 643, 650, 653, 660, 663, 677, 678, 680, 681, 687, 688, 690, 691, 697, 698, 700, 701}) do
	eq(Core.keystoneKind(tree.nodes[id]), nil, "class notable " .. id .. " is no keystone")
end
eq(Core.keystoneKind(tree.nodes[2]), nil, "a plain node with class lanes is no keystone")
eq(Core.keystoneKind(nil), nil, "no node")
-- the client marks the same nodes isKeystone (treedata/nodes.lua)
do
	local okLoad = pcall(dofile, "../client/overlay/modules/game_passivetree/treedata/nodes.lua")
	ok(okLoad and getTreeNodes, "the client's node table loads")
	local clientIds = {}
	for i, node in ipairs(getTreeNodes()) do
		if node.isKeystone then clientIds[#clientIds + 1] = i end
	end
	eq(table.concat(clientIds, ","), table.concat(ids, ","), "the client's isKeystone nodes are the server's keystones")
end

-- ------------------------------------------------------------------------------------------------ the core
eq(Core.countKeystones(tree, {77, 78, 2, 3}), 2, "two keystones among plain nodes")
eq(Core.countKeystones(tree, {77, 77, 78}), 2, "a node twice counts once")
eq(Core.countKeystones(tree, {[77] = true, [78] = true, [665] = true}), 2, "a set works, a mastery is not counted")
eq(Core.countKeystones(tree, {1, 99999}), 0, "the root and unknown ids are ignored")
eq(Core.countKeystones(tree, nil), 0, "nothing")
eq(Core.checkKeystones(tree, {77, 78, 81}), true, "three are fine")
local res, text, code, count = Core.checkKeystones(tree, {77, 78, 81, 82})
eq(res, nil, "four are refused"); eq(text, TEXT, "the text"); eq(code, "keystones", "the code"); eq(count, 4, "the count")
eq(Core.keystoneRefusal({keystoneMax = 2}), "You can hold at most 2 keystones. Refund one to take another.", "the number is the config's")
eq(Core.checkKeystones(tree, {77, 78, 81}, {keystoneMax = 2}), nil, "a lower cap bites")
local over = Core.overCapPresets(tree, {{preset = 1, nodes = {77, 78, 81}}, {preset = 2, nodes = {77, 78, 81, 82}}})
eq(#over, 1, "one preset over"); eq(over[1].preset, 2, "preset 2"); eq(over[1].keystones, 4, "with 4")

-- a route from the root to the targets through plain nodes (a legal tree to hold them)
local function route(targets)
	local parent, queue, head, seen = {}, {tree.root}, 1, {[tree.root] = true}
	while head <= #queue do
		local cur = queue[head]; head = head + 1
		for _, nb in ipairs(tree.nodes[cur].n) do
			if not seen[nb] and (not tree.nodes[nb].c or targets[nb]) then
				seen[nb] = true; parent[nb] = cur; queue[#queue + 1] = nb
			end
		end
	end
	local set, list = {}, {}
	for target in pairs(targets) do
		local id = target
		while id and id ~= tree.root do
			if not set[id] then set[id] = true; list[#list + 1] = id end
			id = parent[id]
		end
	end
	table.sort(list)
	return list
end
local function set(...)
	local t = {}
	for _, id in ipairs({...}) do t[id] = true end
	return t
end
local three = route(set(77, 78, 81))
local four = route(set(77, 78, 81, 109))
local two = route(set(77, 78))
eq(Core.countKeystones(tree, three), 3, "the route to three"); eq(Core.countKeystones(tree, four), 4, "the route to four")

-- validatePlan: saved + planned
local function plan(current, nodes)
	local cur = {}
	for _, id in ipairs(current) do cur[#cur + 1] = id end
	return Core.validatePlan(tree, cur, {}, {nodes = nodes}, {classKey = "warrior", points = 600, allowed = function() return true end})
end
local r = plan({}, three)
ok(r and #r.added == #three, "a plan of three keystones is accepted")
r, text, code = plan({}, four)
eq(r, nil, "a plan of four is refused whole"); eq(code, "keystones", "code keystones"); eq(text, TEXT, "the text")
-- two saved, the plan adds a third and a fourth
local savedTwo = two
local fromThree = {}
do
	local have = {}
	for _, id in ipairs(savedTwo) do have[id] = true end
	for _, id in ipairs(four) do if not have[id] then fromThree[#fromThree + 1] = id end end
end
r, text, code = plan(savedTwo, fromThree)
eq(code, "keystones", "two held + two planned = four: refused")
local fromOne = {}
do
	local have = {}
	for _, id in ipairs(savedTwo) do have[id] = true end
	for _, id in ipairs(three) do if not have[id] then fromOne[#fromOne + 1] = id end end
end
r = plan(savedTwo, fromOne)
ok(r, "two held + one planned = three: accepted")
-- a plan of plain nodes on a full tree is fine
r = plan(three, {2})
ok(r and #r.added == 1, "three held, a plain node planned: accepted")

-- ------------------------------------------------------------------------------------------------ the doors of passivetree.lua
local function mkPlayer(level)
	local st = {[Chaos.storage.passiveRework] = 6, [Chaos.storage.passiveLane] = 4}
	local p = {msgs = {}}
	function p:getGuid() return 1 end
	function p:getId() return 1 end
	function p:getLevel() return level end
	function p:getStorageValue(k) local v = st[k]; if v == nil then return -1 end return v end
	function p:setStorageValue(k, v) st[k] = v end
	function p:getVocation() return {getId = function() return 4 end, getName = function() return "Warrior" end} end
	function p:sendExtendedOpcode() return true end
	function p:registerEvent() end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	return p
end
local p = mkPlayer(1000)
local OP = ChaosOpcodes.passivetree
local function call(action, data)
	clock = clock + 2000
	inserts, sent = {}, {}
	ext.onExtendedOpcode(p, OP, {action = action, data = data})
end
local function last(action)
	for i = #sent, 1, -1 do if sent[i].action == action then return sent[i].data end end
end

rows = {}
call("planApply", {nodes = four})
eq(#inserts, 0, "planApply with four keystones writes nothing")
eq(last("planResult").ok, false, "planResult not ok")
eq(last("planResult").message, TEXT, "planResult carries the text")
ok(last("sendNodes"), "the tree is sent back")
call("sendNodes", {nodes = four})
eq(#inserts, 0, "a plain save of four keystones writes nothing")
eq(last("sendMessage").message, TEXT, "the message box carries the text")
call("planApply", {nodes = three})
eq(#inserts, 1, "planApply with three keystones saves")
eq(last("planResult").ok, true, "planResult ok")
eq(last("sendNodes").keystoneMax, 3, "sendNodes carries the cap for the client")
-- the third is in; a fourth planned on top is refused and nothing changes
local before = rows[1].nodes
do
	local have, more = {}, {}
	for _, id in ipairs(three) do have[id] = true end
	for _, id in ipairs(four) do if not have[id] then more[#more + 1] = id end end
	call("planApply", {nodes = more})
	eq(#inserts, 0, "a fourth keystone on top of three: nothing is written")
	eq(last("planResult").message, TEXT, "with the text")
end
eq(rows[1].nodes, before, "the tree is as it was")
-- refunding is not a door of the cap: a reset is free of it (respec.lua never adds)

-- ------------------------------------------------------------------------------------------------ a build code
dofile("data/scripts/chaos/buildshare_core.lua")
local B = ChaosBuildShare
local ctx = {classId = 1, classKey = "warrior", keystoneKey = "knight", current = {}, points = 600}
local planOk, planErr = B.plan(tree, {classId = 1, nodes = three}, ctx)
ok(planOk and planOk.applied == #three, "a code with three keystones imports")
planOk, planErr = B.plan(tree, {classId = 1, nodes = four}, ctx)
eq(planOk, nil, "a code with four keystones is refused whole")
eq(planErr, TEXT, "with the same text")
planOk, planErr = B.plan(tree, {classId = 1, nodes = four}, {classId = 1, classKey = "warrior", keystoneKey = "knight", current = three, points = 5})
eq(planErr, TEXT, "also when the character has too few points to take them all")
-- a code made before node 77 became a keystone (version 1) leaves it out: that is not a keystone of the code
local old = B.plan(tree, {classId = 1, nodes = four, version = 1}, ctx)
ok(old == nil or old.applied < #four, "an old code is still checked after the reworked nodes are left out")

-- ------------------------------------------------------------------------------------------------ the login
-- a beta character over the cap: every point back, once, with a message; at or under the cap nothing is touched
rows = {{preset = 1, name = "Preset 1", nodes = Core.formatAlloc(four, {})}}
inserts = {}
local q = mkPlayer(1000)
login.onLogin(q)
eq(rows[1].nodes, "", "over the cap: the tree is empty after the login")
eq(#inserts, 1, "one write")
eq(#q.msgs, 1, "one message")
ok(q.msgs[1]:find("held 4 keystones", 1, true) and q.msgs[1]:find("at most 3", 1, true) and q.msgs[1]:find("refunded for free", 1, true),
	"the message says why: " .. tostring(q.msgs[1]))
eq(q.msgs[1]:find("All " .. #four .. " points", 1, true) ~= nil, true, "and how many points came back")
-- the second login: nothing to do
inserts = {}
q = mkPlayer(1000)
login.onLogin(q)
eq(#inserts, 0, "second login writes nothing"); eq(#q.msgs, 0, "second login says nothing")
-- at the cap: never touched
rows = {{preset = 1, name = "Preset 1", nodes = Core.formatAlloc(three, {})}}
inserts = {}
q = mkPlayer(1000)
login.onLogin(q)
eq(rows[1].nodes, Core.formatAlloc(three, {}), "three keystones: the tree is as it was")
eq(#inserts, 0, "no write"); eq(#q.msgs, 0, "no message")
-- no tree at all
rows = {}
q = mkPlayer(1000)
login.onLogin(q)
eq(#q.msgs, 0, "no tree: nothing said")
-- two presets, only the one over the cap is emptied
rows = {{preset = 1, name = "Preset 1", nodes = Core.formatAlloc(three, {})}, {preset = 2, name = "Preset 2", nodes = Core.formatAlloc(four, {})}}
q = mkPlayer(1000)
login.onLogin(q)
eq(rows[1].nodes, Core.formatAlloc(three, {}), "the preset under the cap stays")
eq(rows[2].nodes, "", "the preset over the cap is emptied")
-- masteries and class notables do not count: a tree of 3 keystones, 4 masteries and notables stays whole
do
	local mixed = {}
	for _, id in ipairs(three) do mixed[#mixed + 1] = id end
	rows = {{preset = 1, name = "Preset 1", nodes = Core.formatAlloc(mixed, {})}}
	q = mkPlayer(1000)
	login.onLogin(q)
	eq(rows[1].nodes, Core.formatAlloc(three, {}), "untouched")
end

-- ------------------------------------------------------------------------------------------------ texts
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
ok(pt[TEXT:gsub("3", "%%d")] ~= nil or pt["You can hold at most %d keystones. Refund one to take another."], "pt-BR line of the refusal")
ok(pt["You can hold at most %d keystones. Refund one to take another."]:find("%%d"), "keeps the number")
ok(pt["Your passive tree held %d keystones; a character may hold at most %d. All %d points were refunded for free. Open the tree to spend them again, or use Auto build."],
	"pt-BR line of the login message")

print(string.format("passivetree_keystone_cap_test: %d checks OK", checks))

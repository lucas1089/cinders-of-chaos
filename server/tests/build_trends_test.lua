-- Run from the server/ folder: luajit tests/build_trends_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- Trending builds (O409): build_trends_core.lua (keystone flags of a tree, the bucket signature, the grouping per class
-- with minCount and top, the representative tree, the full build code against docs/build_code_vectors.txt), the
-- keystone names against the client's KEYSTONE_NAMES and every ks / ar flag of passivetree_data.lua, the class table
-- against the client's buildcode.lua, the SQL file against the core, and build_trends.lua against a mocked engine (the
-- snapshot query, the rows, no name or id stored, the window's answer).
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function read(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/build_trends_core.lua")
local K = ChaosBuildTrendsCore
local cfg = dofile("data/scripts/chaos/build_trends_config.lua")
local tree = dofile("data/scripts/chaos/passivetree_data.lua")

-- ====================================================================== config
eq(cfg.table, "chaos_build_trends", "table name")
ok(cfg.minCount >= 3, "no build of one or two characters is listed")
ok(cfg.top >= 1 and cfg.top <= 10, "top")
ok(cfg.minLevel >= 1 and cfg.activeDays >= 1, "who counts")

-- ====================================================================== keystone names: server, client, tree data
local clientSrc = read("../client/overlay/modules/game_passivetree/passivetree.lua")
local block = clientSrc:match("KEYSTONE_NAMES = (%b{})")
ok(block ~= nil, "client KEYSTONE_NAMES found")
local client = {}
for k, v in (block or ""):gmatch('(%w+) = "([^"]+)"') do
	client[k] = v
end
local nServer, nClient = 0, 0
for k, v in pairs(cfg.names) do
	nServer = nServer + 1
	eq(client[k], v, "client name of " .. k)
	ok(K.isKeystoneFlag(k), k .. " is a keystone flag")
end
for _ in pairs(client) do
	nClient = nClient + 1
end
eq(nServer, nClient, "same number of keystone names")
local flagsInTree = {}
for _, node in pairs(tree.nodes) do
	for key in pairs(node.s or {}) do
		if K.isKeystoneFlag(key) then
			flagsInTree[key] = true
		end
	end
	for _, stats in pairs(node.v or {}) do
		for key in pairs(stats) do
			if K.isKeystoneFlag(key) then
				flagsInTree[key] = true
			end
		end
	end
end
for key in pairs(flagsInTree) do
	ok(cfg.names[key] ~= nil, "a name for the tree flag " .. key)
end
ok(not K.isKeystoneFlag("kStuff") and not K.isKeystoneFlag("ksx") and not K.isKeystoneFlag("strength"), "not flags")

-- ====================================================================== classes: server core = client buildcode.lua
local bc = read("../client/overlay/modules/game_passivetree/buildcode.lua")
local cblock = bc:match("C%.CLASSES = (%b{})")
local clientClasses = {}
for key, id in (cblock or ""):gmatch("{'(%w+)', (%d+),") do
	clientClasses[#clientClasses + 1] = {key, tonumber(id)}
end
eq(#clientClasses, #K.CLASSES, "class count")
for i, c in ipairs(K.CLASSES) do
	local cc = clientClasses[i] or {}
	eq(cc[1], c[1], "class key " .. i)
	eq(cc[2], c[2], "class vocation " .. i)
end
local constants = read("data/scripts/chaos/chaos_constants.lua")
for _, c in ipairs(K.CLASSES) do
	ok(constants:find(c[1] .. " = " .. c[2], 1, true) ~= nil, "Chaos.classes.ids has " .. c[1])
end
eq(K.classIndex(4), 1, "warrior index")
eq(K.classIndex(25), 21, "sentinel index")
eq(K.classIndex(2), nil, "retired id")

-- ====================================================================== keystones of a tree
eq(K.signature(K.keystones(tree, {620, 621, 623, 624}, "knight")), "ksBulwark+ksCleavingArc", "knight keystones")
eq(K.signature(K.keystones(tree, {621}, "juggernaut")), "ksImmovable", "juggernaut variant")
eq(K.signature(K.keystones(tree, {621, 624}, "necromancer")), "ksCorpseBlast+ksReapersToll", "necromancer variant")
eq(K.signature(K.keystones(tree, {2, 3, 4}, "knight")), "", "no keystone")
eq(K.signature(K.keystones(tree, {999999}, "knight")), "", "unknown node")
eq(K.keystoneNames({"ksBulwark", "ksCleavingArc"}, cfg.names), "Bulwark, Cleaving Arc", "names")
eq(K.keystoneNames({"ksNew"}, cfg.names), "ksNew", "unknown flag: the flag")
eq(K.keystoneNames({}, cfg.names), "", "none")

-- ====================================================================== representative
local rep = K.representative({
	{id = 1, level = 200, nodes = {1, 2, 3, 9}},
	{id = 2, level = 150, nodes = {1, 2, 3}},
	{id = 3, level = 300, nodes = {1, 2, 7, 8}}
})
eq(rep.id, 2, "the tree closest to the majority")
rep = K.representative({{id = 5, level = 100, nodes = {1}}, {id = 4, level = 100, nodes = {1}}})
eq(rep.id, 4, "tie: the lower id")
rep = K.representative({{id = 5, level = 120, nodes = {1}}, {id = 4, level = 100, nodes = {1}}})
eq(rep.id, 5, "tie: the higher level")

-- ====================================================================== grouping
local chars = {}
local function add(n, class, level, flags, nodes)
	for _ = 1, n do
		chars[#chars + 1] = {id = #chars + 1, class = class, level = level, flags = flags, nodes = nodes or {1}}
	end
end
add(6, 4, 200, {"ksBulwark", "ksCleavingArc"})
add(3, 4, 400, {"ksCleavingArc"})
add(3, 4, 100, {"ksImmovable"})
add(2, 4, 900, {"ksUndyingRage"}) -- two characters: never listed
add(4, 3, 300, {})
local g = K.group(chars, {minCount = 3, top = 5})
eq(g[4].total, 14, "warrior total counts every character")
eq(#g[4].builds, 3, "the build of two is left out")
eq(g[4].builds[1].signature, "ksBulwark+ksCleavingArc", "most played first")
eq(g[4].builds[1].count, 6, "count")
eq(g[4].builds[1].share, 429, "share per mille (6 / 14)")
eq(g[4].builds[2].signature, "ksCleavingArc", "equal count: the higher level first")
eq(g[4].builds[2].level, 400, "average level")
eq(g[3].builds[1].signature, "", "a build without keystones is a build too")
eq(g[3].builds[1].share, 1000, "the whole class")
g = K.group(chars, {minCount = 3, top = 1})
eq(#g[4].builds, 1, "top")
g = K.group(chars, {minCount = 7, top = 5})
eq(#g[4].builds, 0, "minCount above every build")
-- privacy: what a build carries out is counts, averages and one tree; the snapshot rows (below) hold no id or name
for _, b in ipairs(K.group(chars, {minCount = 3, top = 5})[4].builds) do
	ok(b.name == nil and b.id == nil and b.members == nil, "no member list leaves the group")
end
eq(next(K.group({}, {})), nil, "no characters, no classes")

-- ====================================================================== the full build code (docs/build_code_vectors.txt)
local vectors = {}
for line in read("../docs/build_code_vectors.txt"):gmatch("[^\n]+") do
	local name, text, code = line:match("^ok|([^|]*)|([^|]*)|(.*)$")
	if name then
		vectors[name] = {text = text, code = code}
	end
end
local function field(text, key)
	return text:match("^" .. key .. "=([^;]*)") or text:match(";" .. key .. "=([^;]*)")
end
local tested = 0
for _, name in ipairs({"old tree code v1", "newer tree code"}) do
	local v = vectors[name]
	ok(v ~= nil, "vector " .. name)
	if v then
		local class, level, treeCode = field(v.text, "class"), tonumber(field(v.text, "level")), field(v.text, "tree")
		local voc
		for _, c in ipairs(K.CLASSES) do
			if c[1] == class then
				voc = c[2]
			end
		end
		eq(K.encodeFull(voc, level, treeCode), v.code, "encodeFull " .. name)
		tested = tested + 1
	end
end
eq(tested, 2, "vectors tested")
eq(K.encodeFull(4, 10, "nonsense"), nil, "a bad tree code")
eq(K.encodeFull(4, 10, "CB6-AA"), nil, "a short tree code")
local unknownClass = K.encodeFull(2, 50, "CB1-AwAEAgBASs_M")
ok(unknownClass ~= nil and unknownClass:sub(1, 4) == "CC1-", "an unknown class is left out")

-- ====================================================================== SQL file = core
local sql = read("sql/chaos_build_trends.sql")
ok(sql:find(K.schemaSql("chaos_build_trends") .. ";", 1, true) ~= nil, "sql/chaos_build_trends.sql matches schemaSql")
ok(not sql:find("player_id", 1, true) and not sql:find("`name`", 1, true), "no player column")

-- ====================================================================== build_trends.lua, mocked engine
do
	local function stub()
		return setmetatable({}, {__index = function() return function() end end})
	end
	local events, talks = {}, {}
	GlobalEvent = function(name)
		local o = stub()
		events[name] = o
		return o
	end
	TalkAction = function(words)
		local o = stub()
		talks[words] = o
		return o
	end
	addEvent = function() end
	MESSAGE_INFO_DESCR = 2
	local queries, sent = {}, {}
	local snapshotAt
	local nodesText = "620,621,623,624"
	local dbRows = {}
	for i = 1, 4 do
		dbRows[#dbRows + 1] = {id = i, level = 100 + i * 10, vocation = 4, preset = 1, nodes = nodesText}
	end
	dbRows[#dbRows + 1] = {id = 4, level = 140, vocation = 4, preset = 2, nodes = "2,3"} -- a second preset: skipped
	dbRows[#dbRows + 1] = {id = 9, level = 500, vocation = 4, preset = 1, nodes = "621"} -- a tester: skipped
	dbRows[#dbRows + 1] = {id = 10, level = 300, vocation = 8, preset = 1, nodes = ""} -- no tree: skipped
	local stored = {}
	db = {query = function(q)
		queries[#queries + 1] = q
		local t = q:match("^INSERT INTO `chaos_build_trends`")
		if t then
			stored[#stored + 1] = q
		end
		if q:find("server_config", 1, true) then
			snapshotAt = tonumber(q:match("VALUES %('chaos_build_trends_at', '(%d+)'%)"))
		end
		return true
	end, asyncQuery = function(q) queries[#queries + 1] = q end, escapeString = function(s) return "'" .. s .. "'" end,
		storeQuery = function(q)
			if q:find("server_config", 1, true) then
				return snapshotAt and 1 or nil
			end
			return nil
		end}
	result = {getString = function() return tostring(snapshotAt) end, getNumber = function() return 0 end,
		free = function() end}
	local selects = {}
	Chaos = {classes = {ids = {warrior = 4, juggernaut = 8, ranger = 3}},
		staffCommand = function() return true end,
		t = function(_, s) return s end,
		load = function(f) return dofile("data/scripts/chaos/" .. f) end,
		isTesterGuid = function(guid) return guid == 9 end,
		select = function(q, cols)
			selects[#selects + 1] = q
			if q:find("FROM `players`", 1, true) then
				return dbRows
			end
			return {}
		end,
		send = function(player, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data} end}
	ChaosOpcodes = {passivetree = 65}
	ChaosClasses = {baseOf = function(v) return ({[4] = 4, [8] = 4, [14] = 4, [3] = 3})[v] end,
		keystoneKey = function(v) return ({[4] = "knight", [8] = "juggernaut"})[v] end}
	ChaosLeaderboard = {classGroups = function()
		return {{key = 4, name = "Warrior", ids = {4, 8, 14}}, {key = 3, name = "Ranger", ids = {3, 7, 15}}}
	end}
	local printed = print
	print = function() end
	dofile("data/scripts/chaos/build_trends.lua")
	print = printed
	local BT = ChaosBuildTrends
	ok(events.ChaosBuildTrendsStartup ~= nil and events.ChaosBuildTrendsCheck ~= nil, "startup and hourly check")
	ok(talks["/buildtrends"] ~= nil, "staff command")
	ok(ChaosPassiveTree.extraActions.buildTrends ~= nil, "the window's action on opcode 65")
	eq(BT.due(1000000), true, "no snapshot yet: due")
	print = function() end
	local rows = BT.snapshot(1000000)
	print = printed
	local q = selects[1] or ""
	ok(q:find("p.`lastlogin` >= " .. (1000000 - 7 * 86400), 1, true) ~= nil, "active in the last 7 days")
	ok(q:find("p.`level` >= 100", 1, true) ~= nil, "minimum level")
	ok(q:find("p.`group_id` < 4", 1, true) ~= nil, "no staff")
	ok(q:find("p.`deletion` = 0", 1, true) ~= nil, "no deleted characters")
	eq(rows, 1, "one build listed (4 warriors, the tester and the empty tree out)")
	local row = stored[1] or ""
	ok(row:find("'ksBulwark+ksCleavingArc'", 1, true) ~= nil, "the signature")
	ok(row:find("'Bulwark, Cleaving Arc'", 1, true) ~= nil, "the keystone names")
	ok(row:find("'Warrior'", 1, true) ~= nil, "the class name")
	ok(row:find("'CB6-", 1, true) ~= nil and row:find("'CC1-", 1, true) ~= nil, "both codes")
	ok(row:find("VALUES (1000000, 4, 1, ", 1, true) ~= nil, "snapshot, class, rank")
	ok(row:find(", 4, 4, 1000, 125, ", 1, true) ~= nil, "count, total, share, average level")
	eq(snapshotAt, 1000000, "server_config time")
	eq(BT.due(1000000 + 3600), false, "not due an hour later")
	eq(BT.due(1000000 + 86400), true, "due a day later")
	-- the stored codes decode: the CC1 code wraps the tree code of the representative
	local treeCode = row:match("'(CB6%-[%w_%-]+)'")
	eq(row:match("'(CC1%-[%w_%-]+)'"), K.encodeFull(4, 125, treeCode), "full code = class, average level, tree")
	local decoded = ChaosBuildShare.decode and ChaosBuildShare.decode(treeCode)
	if decoded then
		eq(decoded.classId, 1, "tree code class line: warrior")
		eq(#(decoded.nodes or {}), 4, "the representative's nodes")
	end
	-- the window's answer
	local snapRows = {{class_base = 4, rank = 1, keystones = "Bulwark, Cleaving Arc", count = 4, total = 4, share = 1000,
		avg_level = 125, tree_code = treeCode, code = "CC1-x"}}
	Chaos.select = function(qq)
		if qq:find("chaos_build_trends", 1, true) then
			return snapRows
		end
		return {}
	end
	db.storeQuery = function(qq)
		return qq:find("MAX", 1, true) and 1 or nil
	end
	result.getNumber = function() return 1000000 end
	BT.cache = nil
	local player = {getVocation = function() return {getId = function() return 8 end} end, getGuid = function() return 7 end}
	eq(ChaosPassiveTree.extraActions.buildTrends(player, {}), true, "handled")
	local msg = sent[#sent]
	eq(msg and msg.op, 65, "opcode")
	eq(msg and msg.action, "buildTrends", "action")
	eq(msg and msg.data.class, 4, "no class asked: the character's own line (Juggernaut -> Warrior)")
	eq(msg and msg.data.at, 1000000, "snapshot time")
	eq(msg and #msg.data.rows, 1, "rows")
	eq(msg and msg.data.rows[1].full, "CC1-x", "the full code")
	eq(msg and #msg.data.classes, 2, "class tabs")
	for _, r in ipairs(msg and msg.data.rows or {}) do
		ok(r.name == nil and r.id == nil and r.player == nil, "no name or id in the answer")
	end
	ChaosPassiveTree.extraActions.buildTrends(player, {class = 3})
	eq(sent[#sent].data.class, 3, "a class tab")
	eq(#sent[#sent].data.rows, 0, "no build of that class yet")
	ChaosPassiveTree.extraActions.buildTrends(player, {class = 999})
	eq(sent[#sent].data.class, 4, "an unknown class: the own one")
end

print(string.format("build_trends: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

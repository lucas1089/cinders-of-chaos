-- Trending builds (O409, "Builds em alta"): once a day the passive trees of the active characters are grouped per
-- class by the keystones they took; the most played builds of every class are kept in chaos_build_trends with their
-- count, share of the class, average level and one representative code. Numbers: build_trends_config.lua. Pure logic:
-- build_trends_core.lua (tests/build_trends_test.lua). Overview: server/README.md "Trending builds (O409)".
--
-- Who counts: characters that logged in during the last activeDays, at least minLevel, below the staff group, not
-- deleted, not tester bots; their active preset (the lowest preset row of chaos_passive_tree). Privacy: no name or id
-- is stored or sent, a build of fewer than minCount characters is never listed.
--
-- Protocol (opcode 65, ChaosOpcodes.passivetree, through ChaosPassiveTree.extraActions like buildshare.lua):
--   client -> server  buildTrends {class?}   class = a class tab key (base class id); none = the character's own
--   server -> client  buildTrends {class, className, at (os.time of the snapshot, 0 = none yet), total, classes =
--                     [{key, name}], rows = [{rank, share (per mille), count, level, keystones = "A, B", code (CB<n>-),
--                     full (CC1-)}]}
-- The client (game_passivetree trends.lua) lists them and imports one through the Build Code panel (buildshare.lua's
-- preview and apply, the server's class and respec rules unchanged). The website: pages/trends.php.
-- Staff: /buildtrends (status) | /buildtrends run (a snapshot now).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosBuildShare or not ChaosBuildShare.encode then
	dofile("data/scripts/chaos/buildshare_core.lua")
end
if not ChaosPassiveTreeCore or not ChaosPassiveTreeCore.parseAlloc then
	dofile("data/scripts/chaos/passivetree_core.lua")
end
dofile("data/scripts/chaos/build_trends_core.lua")
ChaosBuildTrendsConfig = dofile("data/scripts/chaos/build_trends_config.lua")

ChaosBuildTrends = ChaosBuildTrends or {}
local BT = ChaosBuildTrends
local K = ChaosBuildTrendsCore
local OPCODE = ChaosOpcodes.passivetree

BT.cache = BT.cache or nil -- {snapshot, byClass = {[base] = rows}}

local function C()
	return ChaosBuildTrendsConfig
end

local function log(text)
	print("[Chaos build trends] " .. text)
end

local function try(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		log(what .. ": " .. tostring(err))
	end
	return ok, err
end

local function tree()
	local T = ChaosPassiveTree and ChaosPassiveTree.internal
	if T and T.getTree then
		return T.getTree()
	end
	return Chaos.load("passivetree_data.lua")
end

-- ---------------------------------------------------------------- classes
local function baseOf(voc)
	if ChaosClasses and ChaosClasses.baseOf then
		return ChaosClasses.baseOf(voc) or voc
	end
	return voc
end

local function variantKey(voc)
	return ChaosClasses and ChaosClasses.keystoneKey and ChaosClasses.keystoneKey(voc) or nil
end

-- the class tabs: the leaderboard's (base class and its ascensions), else the base classes seen
function BT.groups()
	local LB = ChaosLeaderboard
	if LB and LB.classGroups then
		local ok, groups = pcall(LB.classGroups)
		if ok and groups and #groups > 0 then
			return groups
		end
	end
	local out = {}
	for name, id in pairs((Chaos.classes and Chaos.classes.ids) or {}) do
		local v = Vocation(id)
		out[#out + 1] = {key = id, name = v and v:getName() or name}
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end

local function groupName(key)
	for _, g in ipairs(BT.groups()) do
		if g.key == key then
			return g.name
		end
	end
	local v = Vocation(key)
	return v and v:getName() or tostring(key)
end

-- the tree code's class byte (buildshare.lua classOf): the class line of the base class
local function lineOf(voc)
	local base = baseOf(voc)
	for name, id in pairs((Chaos.classes and Chaos.classes.ids) or {}) do
		if id == base then
			return ChaosBuildShare.lineIndex(name)
		end
	end
	return 0
end

-- ---------------------------------------------------------------- the snapshot
local function setConfig(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", db.escapeString(key), db.escapeString(tostring(value))))
end

local function getConfig(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key))
	if not id then
		return nil
	end
	local v = result.getString(id, "value")
	result.free(id)
	return tonumber(v)
end

-- the characters of a snapshot: {{id, class, voc, level, nodes, masteries, flags}}
function BT.characters(now)
	local cfg = C()
	local rows = Chaos.select(string.format("SELECT p.`id`, p.`level`, p.`vocation`, t.`preset`, t.`nodes` FROM `players` p " ..
		"JOIN `chaos_passive_tree` t ON t.`player_id` = p.`id` WHERE p.`lastlogin` >= %d AND p.`level` >= %d AND " ..
		"p.`group_id` < %d AND p.`deletion` = 0 ORDER BY p.`id`, t.`preset` LIMIT %d", now - cfg.activeDays * 86400,
		cfg.minLevel, cfg.staffGroup, cfg.maxCharacters),
		{{"id", "n"}, {"level", "n"}, {"vocation", "n"}, {"preset", "n"}, {"nodes", "s"}})
	local data, chars, seen = tree(), {}, {}
	for _, r in ipairs(rows) do
		if not seen[r.id] and not (Chaos.isTesterGuid and Chaos.isTesterGuid(r.id)) then
			seen[r.id] = true -- the first row is the active preset
			local nodes, masteries = ChaosPassiveTreeCore.parseAlloc(r.nodes)
			if #nodes > 0 then
				chars[#chars + 1] = {id = r.id, class = baseOf(r.vocation), voc = r.vocation, level = r.level,
					nodes = nodes, masteries = masteries, flags = K.keystones(data, nodes, variantKey(r.vocation)),
					-- the keystone cap (O447): not listed, counted in the total
					overCap = not ChaosPassiveTreeCore.checkKeystones(data, nodes)}
			end
		end
	end
	return chars
end

function BT.snapshot(now)
	local cfg = C()
	now = now or os.time()
	local grouped = K.group(BT.characters(now), cfg)
	db.query(K.schemaSql(cfg.table))
	local rows = 0
	for base, cl in pairs(grouped) do
		local name = groupName(base)
		for rank, b in ipairs(cl.builds) do
			local rep = b.rep
			local treeCode = ChaosBuildShare.encode({classId = lineOf(rep.voc), nodes = rep.nodes, masteries = rep.masteries})
			local full = K.encodeFull(rep.voc, b.level, treeCode) or ""
			db.query(string.format("INSERT INTO `%s` (`snapshot`, `class_base`, `rank`, `class_name`, `signature`, " ..
				"`keystones`, `count`, `total`, `share`, `avg_level`, `tree_code`, `code`) VALUES (%d, %d, %d, %s, %s, %s, " ..
				"%d, %d, %d, %d, %s, %s) ON DUPLICATE KEY UPDATE `count` = VALUES(`count`)", cfg.table, now, base, rank,
				db.escapeString(name), db.escapeString(b.signature:sub(1, 255)),
				db.escapeString(K.keystoneNames(b.flags, cfg.names):sub(1, 512)), b.count, cl.total, b.share, b.level,
				db.escapeString(treeCode), db.escapeString(full)))
			rows = rows + 1
		end
	end
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `snapshot` < %d", cfg.table, now - (cfg.keepDays or 30) * 86400))
	setConfig(cfg.configKey, now)
	BT.cache = nil
	log(string.format("snapshot %d: %d build row(s)", now, rows))
	return rows
end

function BT.due(now)
	local last = getConfig(C().configKey)
	return not last or now - last >= (C().refreshHours or 24) * 3600
end

-- ---------------------------------------------------------------- the latest snapshot (cached)
function BT.latest()
	local cfg = C()
	if BT.cache and os.time() - BT.cache.at < 300 then
		return BT.cache
	end
	local cache = {at = os.time(), snapshot = 0, byClass = {}}
	local id = db.storeQuery(string.format("SELECT MAX(`snapshot`) AS `s` FROM `%s`", cfg.table))
	if id then
		cache.snapshot = result.getNumber(id, "s") or 0
		result.free(id)
	end
	if cache.snapshot > 0 then
		local rows = Chaos.select(string.format("SELECT `class_base`, `rank`, `keystones`, `count`, `total`, `share`, " ..
			"`avg_level`, `tree_code`, `code` FROM `%s` WHERE `snapshot` = %d ORDER BY `class_base`, `rank`", cfg.table,
			cache.snapshot), {{"class_base", "n"}, {"rank", "n"}, {"keystones", "s"}, {"count", "n"}, {"total", "n"},
			{"share", "n"}, {"avg_level", "n"}, {"tree_code", "s"}, {"code", "s"}})
		local data = tree()
		for _, r in ipairs(rows) do
			local list = cache.byClass[r.class_base] or {total = r.total, rows = {}}
			cache.byClass[r.class_base] = list
			-- the keystone cap (O447): a row of a snapshot made before the rule can hold more keystones than a
			-- character may; it is not listed (its code would be refused on import anyway)
			local decoded = ChaosBuildShare.decode(r.tree_code)
			if not decoded or ChaosPassiveTreeCore.checkKeystones(data, decoded.nodes) then
				list.rows[#list.rows + 1] = {rank = r.rank, share = r.share, count = r.count, level = r.avg_level,
					keystones = r.keystones, code = r.tree_code, full = r.code ~= "" and r.code or nil}
			end
		end
	end
	BT.cache = cache
	return cache
end

function BT.send(player, classKey)
	local key = tonumber(classKey)
	local groups, classes = BT.groups(), {}
	local known = false
	for _, g in ipairs(groups) do
		classes[#classes + 1] = {key = g.key, name = g.name}
		known = known or g.key == key
	end
	if not known then
		key = baseOf(player:getVocation():getId())
	end
	local latest = BT.latest()
	local list = latest.byClass[key] or {total = 0, rows = {}}
	Chaos.send(player, OPCODE, "buildTrends", {class = key, className = groupName(key), at = latest.snapshot,
		total = list.total, classes = classes, rows = list.rows})
end

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}
ChaosPassiveTree.extraActions.buildTrends = function(player, data)
	if not C().enabled then
		return true
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "buildtrends.get", C().askMs or 1000) then
		return true
	end
	try("send", BT.send, player, type(data) == "table" and data.class or nil)
	return true
end

-- ---------------------------------------------------------------- events
local function check()
	if C().enabled and BT.due(os.time()) then
		try("snapshot", BT.snapshot, os.time())
	end
end

local startup = GlobalEvent("ChaosBuildTrendsStartup")
function startup.onStartup()
	try("table", function() db.query(K.schemaSql(C().table)) end)
	addEvent(function()
		try("check", check)
	end, (C().startDelaySeconds or 120) * 1000)
	return true
end
startup:register()

local think = GlobalEvent("ChaosBuildTrendsCheck")
function think.onThink(interval)
	try("check", check)
	return true
end
think:interval((C().checkSeconds or 3600) * 1000)
think:register()

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/buildtrends")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	local cmd = tostring(param or ""):lower():match("^%s*(%S*)")
	if not Chaos.staffCommand(player, words, param, cmd == "run") then
		return false
	end
	if cmd == "run" then
		local ok, rows = try("snapshot", BT.snapshot, os.time())
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Build trends: snapshot %s, %s row(s).",
			ok and "done" or "failed", tostring(ok and rows or 0)))
		return false
	end
	local latest = BT.latest()
	local classes = 0
	for _ in pairs(latest.byClass) do
		classes = classes + 1
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Build trends: snapshot %d (%s), %d class(es) listed.",
		latest.snapshot, latest.snapshot > 0 and os.date("%Y-%m-%d %H:%M", latest.snapshot) or "none yet", classes))
	return false
end
talk:separator(" ")
talk:register()

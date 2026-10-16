-- Run from the server/ folder: luajit tests/admin_panel_test.lua (and lua5.3; CI runs both). Mock of the engine API.
-- The admin panel (data/scripts/chaos/admin/): core.lua and every actions_*.lua loaded against a mocked engine.
--   * every action registers (a known category, a handler) and has a valid params schema
--   * permissions: a player gets nothing, a gamemaster never sees nor runs a dangerous or group-5 action, every run is
--     in the audit log, the group hierarchy protects the targets
--   * the catalog of the highest group goes out in S/P/E parts under 8192 bytes that join back to the JSON
--   * the stash actions go through the stash API (ChaosStash.staff*), never the stock Player:addItemStash or raw SQL
--   * a few Chaos actions run against mocked systems
local checks, failures = 0, 0
local realPrint = print
local function check(c, m)
	checks = checks + 1
	if not c then failures = failures + 1; realPrint("FAIL: " .. tostring(m)) end
end
local function eq(a, b, m) check(a == b, tostring(m) .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")") end

-- ---------------------------------------------------------------- engine mocks
local events = {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
EventCallback = {register = function() end}
local queries, async = {}, {}
db = {
	query = function(q) queries[#queries + 1] = q; return true end, asyncQuery = function(q) async[#async + 1] = q end,
	storeQuery = function() return nil end, escapeString = function(s) return "'" .. tostring(s):gsub("'", "\\'") .. "'" end,
}
-- a small JSON encoder (sizes and the S/P/E parts are measured on real JSON text); decode reads back what it wrote
local DECODE = {}
local function enc(v)
	local t = type(v)
	if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
	if t == "number" or t == "boolean" then return tostring(v) end
	if t ~= "table" then return "null" end
	if #v > 0 or next(v) == nil then
		local out = {}
		for _, x in ipairs(v) do out[#out + 1] = enc(x) end
		return "[" .. table.concat(out, ",") .. "]"
	end
	local keys, out = {}, {}
	for k in pairs(v) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	for _, k in ipairs(keys) do out[#out + 1] = enc(k) .. ":" .. enc(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end
json = {encode = function(v) local s = enc(v); DECODE[s] = v; return s end,
	decode = function(s) local v = DECODE[s]; if v == nil then error("bad json") end; return v end}
local clock = 1000000
os.mtime = function() clock = clock + 1000; return clock end
print = function() end

dofile("data/scripts/chaos/chaos_constants.lua")
local SELECT = {} -- pattern -> rows
Chaos.select = function(q) for pat, rows in pairs(SELECT) do if q:find(pat, 1, true) then return rows end end; return {} end
local sent = {}
dofile("data/scripts/chaos/admin/core.lua")
Chaos.sendChunked = function(player, opcode, buffer) sent[#sent + 1] = {player = player, opcode = opcode, msg = DECODE[buffer], raw = buffer} end

local FILES = {"actions_players", "actions_server", "actions_world", "actions_economy", "actions_events", "actions_content",
	"actions_security", "actions_tools", "actions_store", "actions_chaos_currency", "actions_chaos_progress", "actions_chaos_class",
	"actions_chaos_player", "actions_chaos_bosses", "actions_chaos_instances", "actions_chaos_social", "actions_staff_tools"}
for _, f in ipairs(FILES) do dofile("data/scripts/chaos/admin/" .. f .. ".lua") end
local okLs, ls = pcall(io.popen, "ls data/scripts/chaos/admin")
if okLs and ls then
	local listed = {}
	for _, f in ipairs(FILES) do listed[f .. ".lua"] = true end
	for name in ls:lines() do
		if name:match("^actions_.*%.lua$") then check(listed[name], "every actions file is loaded by this test: " .. name) end
	end
	ls:close()
end

-- ---------------------------------------------------------------- players
local online = {}
local function mkPlayer(id, group, name)
	local p = {id = id, group = group, name = name or ("P" .. id), storage = {}, texts = {}, items = {}, pos = {x = 100, y = 100, z = 7},
		blessings = {}, voc = 1}
	local g = {getId = function() return p.group end, getAccess = function() return p.group >= 3 end}
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:getName() return self.name end
	function p:isPlayer() return true end
	function p:getGroup() return g end
	function p:getAccountId() return self.id * 10 end
	function p:getIp() return 0 end
	function p:getLevel() return 100 end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
	function p:sendCancelMessage(t) self.texts[#self.texts + 1] = t end
	function p:getVocation() return {getId = function() return p.voc end, getName = function() return "Voc" .. p.voc end} end
	function p:getPosition() return self.pos end
	function p:teleportTo(pos) self.pos = pos end
	function p:addItemStash() error("the stock stash API must not be used") end
	function p:getStashItemCount() error("the stock stash API must not be used") end
	online[p.name:lower()] = p
	return p
end
function Player(name) return type(name) == "string" and online[name:lower()] or nil end
Game = {getPlayers = function() local out = {} for _, p in pairs(online) do out[#out + 1] = p end return out end}
local function itemType(id, name)
	return {getId = function() return id end, getName = function() return name end, getClientId = function() return id end}
end
local ITEMS = {[2160] = "crystal coin", [2400] = "magic sword"}
function ItemType(v)
	if tonumber(v) then return itemType(ITEMS[tonumber(v)] and tonumber(v) or 0, ITEMS[tonumber(v)] or "") end
	for id, n in pairs(ITEMS) do if n == v then return itemType(id, n) end end
	return itemType(0, "")
end

local player, gm, admin, god = mkPlayer(1, 1, "Plain"), mkPlayer(2, 4, "Gamemaster"), mkPlayer(3, 5, "Admin"), mkPlayer(4, 6, "God")
local ext = events.ChaosAdminExtended
local function run(actor, id, params)
	sent = {}
	ext.onExtendedOpcode(actor, CHAOS_ADMIN_OPCODE, json.encode({action = "run", data = {rid = 7, id = id, params = params or {}}}))
	local last = sent[#sent]
	return last and last.msg and last.msg.data
end
local function catalogOf(actor)
	sent = {}
	ext.onExtendedOpcode(actor, CHAOS_ADMIN_OPCODE, json.encode({action = "catalog"}))
	local parts = {}
	for _, s in ipairs(sent) do parts[#parts + 1] = s end
	return parts[1] and parts[1].msg and parts[1].msg.data, parts[1] and parts[1].raw
end

-- ---------------------------------------------------------------- every action registers, with a valid schema
local TYPES = {player = true, string = true, text = true, int = true, bool = true, select = true, pos = true, ip = true}
local cats, ids = {}, {}
for _, c in ipairs(ChaosAdmin.categories) do cats[c.id] = c end
for id in pairs(ChaosAdminPending) do ids[#ids + 1] = id end
table.sort(ids)
check(#ids >= 150, "the catalog holds the old and the new actions (" .. #ids .. ")")
local perCat = {}
for _, id in ipairs(ids) do
	local def = ChaosAdminPending[id]
	check(ChaosAdmin.getAction(id) == def, id .. ": registered (known category, a handler)")
	check(id == def.id and id:sub(1, #def.category + 1) == def.category .. ".", id .. ": id is category.name")
	check(type(def.name) == "string" and def.name ~= "" and type(def.description) == "string" and def.description ~= "", id .. ": name and description")
	check(ChaosAdminConfig.categoryMinGroup[def.category] ~= nil, id .. ": its category has a minimum group")
	perCat[def.category] = (perCat[def.category] or 0) + 1
	local names = {}
	for _, spec in ipairs(def.params or {}) do
		local where = id .. "." .. tostring(spec.name)
		check(type(spec.name) == "string" and spec.name:match("^[%w_]+$") and not names[spec.name], where .. ": a unique name")
		names[spec.name or ""] = true
		check(TYPES[spec.type or "string"], where .. ": a known type")
		check(type(spec.label) == "string" and spec.label ~= "", where .. ": a label")
		if spec.type == "int" then
			check(spec.min == nil or spec.max == nil or spec.min <= spec.max, where .. ": min <= max")
			check(spec.default == nil or ((spec.min or -math.huge) <= spec.default and spec.default <= (spec.max or math.huge)), where .. ": default in range")
		elseif spec.type == "select" then
			check(type(spec.options) == "table" and #spec.options > 0, where .. ": options")
			local found = spec.default == nil
			for _, o in ipairs(spec.options or {}) do
				local v = type(o) == "table" and o.value or o
				check(v ~= nil and (type(o) ~= "table" or o.label), where .. ": option value and label")
				if tostring(v) == tostring(spec.default) then found = true end
			end
			check(found, where .. ": the default is an option")
		elseif spec.type == "string" or spec.type == "text" then
			check(spec.max == nil or spec.max > 0, where .. ": max length")
		end
	end
end
for _, cat in ipairs({"chaos_currency", "chaos_progress", "chaos_class", "chaos_player", "chaos_bosses", "chaos_instances", "chaos_social"}) do
	check(cats[cat] and (perCat[cat] or 0) >= 4, "category " .. cat .. " is listed and has actions")
end
for _, id in ipairs({"economy.stash_give", "economy.stash_info", "economy.stash_remove", "tools.testkit", "tools.areagen_status",
		"tools.creatorcodes_run", "security.botreview_list"}) do
	check(ChaosAdminPending[id] ~= nil or id == "security.botreview_list", "registered: " .. id)
end
eq(ChaosAdminPending["economy.stash_remove"].dangerous, true, "stash_remove is dangerous")

-- ---------------------------------------------------------------- permissions
sent = {}
ext.onExtendedOpcode(player, CHAOS_ADMIN_OPCODE, json.encode({action = "catalog"}))
eq(#sent, 0, "a player gets no catalog")
eq(run(player, "chaos_currency.candlemarks_view", {player = "Plain"}), nil, "a player gets no reply to a run")
local gmCat = catalogOf(gm)
local gmIds = {}
for _, c in ipairs(gmCat.categories) do
	for _, a in ipairs(c.actions) do
		gmIds[a.id] = true
		check(not a.dangerous, "a gamemaster sees no dangerous action: " .. a.id)
		check(ChaosAdmin.requiredGroup(ChaosAdminPending[a.id]) <= 4, "a gamemaster sees only group-4 actions: " .. a.id)
	end
end
check(gmIds["chaos_bosses.pocket_view"] and not gmIds["chaos_bosses.pocket_set"], "a gamemaster may look, not give")
local logBefore = #async
local r = run(gm, "chaos_progress.achievements_reset", {player = "Plain"})
eq(r and r.ok, false, "a gamemaster is denied a dangerous action")
check(r and r.message:find("not allowed", 1, true), "told why")
check(#async > logBefore and async[#async]:find("denied", 1, true), "the denial is in the audit log")
r = run(admin, "economy.stash_remove", {player = "Plain", row = 1})
eq(r and r.ok, false, "an administrator (5) is denied the dangerous stash_remove")
local godCat, raw = catalogOf(god)
local godN = 0
for _, c in ipairs(godCat.categories) do godN = godN + #c.actions end
eq(godN, #ids, "the highest group sees every action")

-- the catalog in parts
local parts = Chaos.splitExtended(raw)
check(#raw > 8192 and #parts >= 2, "the catalog needs several parts (" .. #raw .. " bytes, " .. #parts .. " parts)")
local joined = {}
for i, part in ipairs(parts) do
	check(#part <= 8192, "part " .. i .. " fits one extended opcode message")
	check(part:sub(1, 1) == (i == 1 and "S" or (i == #parts and "E" or "P")), "part " .. i .. " marker")
	joined[#joined + 1] = part:sub(2)
end
eq(table.concat(joined), raw, "the parts join back to the catalog JSON")

-- params are validated and every run is logged
r = run(god, "chaos_currency.candlemarks_give", {player = "Plain", amount = 999999999})
eq(r and r.ok, false, "an amount out of range is refused")
check(async[#async]:find("invalid", 1, true), "and logged as invalid")
r = run(god, "chaos_player.embers_blessing_give", {player = "Plain", blessing = "nonsense"})
eq(r and r.ok, false, "a select value that is not an option is refused")

-- the group hierarchy
r = run(admin, "chaos_class.trials_view", {player = "God"})
eq(r and r.ok, false, "an administrator cannot touch a higher group")
ChaosAdmin.dbPlayer = function(name) return name == "Offgod" and {id = 99, account_id = 990, name = "Offgod", group_id = 6} or nil end
r = run(admin, "chaos_currency.conquest_view", {player = "Offgod"})
eq(r and r.ok, false, "nor an offline one")

-- ---------------------------------------------------------------- the stash actions go through the stash API
local calls = {}
ChaosStash = {
	staffGive = function(p, id, n, tab, src) calls[#calls + 1] = {"give", p:getName(), id, n, tab, src}; return true, "stored" end,
	staffSummary = function(guid) calls[#calls + 1] = {"summary", guid}; return {{tab = 1, name = "Tab 1", entries = 2, items = 7}}, 2, 7 end,
	staffFind = function(guid, id) calls[#calls + 1] = {"find", guid, id}; return {count = 5, tab = 1}, {{id = 3, tab = 105, name = "Doom", count = 1}} end,
	staffRemove = function(p, what) calls[#calls + 1] = {"remove", p:getName(), what.row, what.item, what.count}; return true, "removed" end,
	staffTabName = function(tab) return "Tab " .. tab end,
}
local q0 = #queries
r = run(admin, "economy.stash_give", {player = "Plain", item = "magic sword", count = 2, tab = "105"})
eq(r and r.ok, true, "stash_give runs")
eq(calls[1] and table.concat({calls[1][1], calls[1][2], calls[1][3], calls[1][4], calls[1][5], calls[1][6]}, ","), "give,Plain,2400,2,105,staff",
	"stash_give: ChaosStash.staffGive with the item, count and tab")
r = run(admin, "economy.stash_info", {player = "Plain", item = "2400"})
check(r and r.ok and r.lines and #r.lines == 3, "stash_info: per tab and the search")
eq(calls[2][1] .. calls[3][1], "summaryfind", "stash_info: staffSummary and staffFind")
r = run(god, "economy.stash_remove", {player = "Plain", row = 3})
eq(calls[4] and calls[4][1] .. ":" .. tostring(calls[4][3]), "remove:3", "stash_remove: a row through staffRemove")
r = run(god, "economy.stash_remove", {player = "Plain", item = "crystal coin", count = 50})
eq(calls[5] and tostring(calls[5][4]) .. "x" .. tostring(calls[5][5]), "2160x50", "stash_remove: a stack amount")
eq(#queries, q0, "the stash actions write no SQL of their own")
r = run(admin, "economy.stash_give", {player = "Nobody", item = "2400", count = 1, tab = "0"})
eq(r and r.ok, false, "stash_give needs the character online")

-- ---------------------------------------------------------------- Chaos actions against mocked systems
local acc = {balance = 10, earned = 10, spent = 0}
ChaosCandlemarks = {cfg = {}, core = {blockSec = function() return 1800 end}, earners = {}, why = {},
	account = function() return acc end, track = function(p) return {guid = p:getGuid(), account = p:getAccountId(), progress = 5, loginAt = 7} end,
	sendHud = function() end}
q0 = #queries
r = run(admin, "chaos_currency.candlemarks_give", {player = "Plain", amount = 25})
eq(r and r.ok, true, "candlemarks give")
eq(acc.balance, 35, "the cached balance follows")
check(queries[q0 + 1] and queries[q0 + 1]:find("`balance` + 25", 1, true) and queries[q0 + 1]:find("= 10", 1, true), "one UPDATE of the account row")
run(admin, "chaos_currency.candlemarks_take", {player = "Plain", amount = 100})
eq(acc.balance, 0, "take never goes below 0")
eq(run(gm, "chaos_currency.candlemarks_give", {player = "Plain", amount = 1}).ok, false, "a gamemaster gives no Candlemarks")

local pushed, rows = 0, {}
ChaosPocketBossCore = {}
Chaos.pocketBossConfig = {table = "chaos_pocketboss", charges = {daily = 3, bonusMax = 5}}
ChaosPocketBoss = {rows = rows, runs = {}, ensureTable = function() return true end, push = function() pushed = pushed + 1 end,
	index = function() return {byKey = {fen = {}}} end, bosses = function() return {{key = "fen", name = "Fen", minLevel = 30}} end,
	view = function(p) rows[p:getGuid()] = rows[p:getGuid()] or {fen = {day = 1, used = 3}}; return {} end,
	charges = function(p, key)
		local row = (rows[p:getGuid()] or {})[key] or {}
		return {day = 20261016, used = row.used or 0, bonus = row.bonus or 0, daily = 3 - (row.used or 0), max = 3,
			left = 3 - (row.used or 0) + (row.bonus or 0), bonusDay = 0, bonusAdded = 0, eventAt = 0}
	end}
r = run(admin, "chaos_bosses.pocket_set", {player = "Plain", boss = "fen", daily = 1, bonus = 9})
eq(r and r.ok, true, "pocket charges set")
eq(rows[1].fen.used .. "/" .. rows[1].fen.bonus, "2/5", "1 daily left (2 used), bonus capped at bonusMax")
eq(run(admin, "chaos_bosses.pocket_set", {player = "Plain", boss = "nope", daily = 1}).ok, false, "an unknown boss is refused")
r = run(gm, "chaos_bosses.pocket_reset_day", {player = "Plain"})
eq(r and r.ok and rows[1].fen.used, 0, "a gamemaster gives today's charges back")
check(pushed >= 2, "the client window is told")

Chaos.trials = {storage = {tierBase = 7101700, picksBase = 7101730, tokens = 7101760, cooldown = 7101764}, tiers = {1, 2, 3}}
ChaosTrialsCore = {heldNodes = function() return {} end}
ChaosTrials = {tierCleared = function(p, voc) return math.max(0, p:getStorageValue(7101700 + voc)) end, picks = function() return 0 end,
	refresh = function() end, sendState = function() end}
run(admin, "chaos_class.trials_tier", {player = "Plain", tier = 2})
eq(player.storage[7101701], 2, "trials: tier set for the vocation")
eq(run(admin, "chaos_class.trials_reset", {player = "Plain"}).ok, false, "a trials reset is dangerous (group 6)")
run(god, "chaos_class.trials_reset", {player = "Plain"})
eq(player.storage[7101701], 0, "trials: reset by the highest group")

Chaos.storage.passiveExtraPoints = Chaos.storage.passiveExtraPoints or 7100020
ChaosPassiveTree = {publicView = function() return {total = 10, nodes = {}, cls = "x"} end, internal = {sendPoints = function() end}}
run(admin, "chaos_class.tree_points", {player = "Plain", points = 3})
run(admin, "chaos_class.tree_points", {player = "Plain", points = -5})
eq(player.storage[Chaos.storage.passiveExtraPoints], 0, "tree points never below 0")

local moved
ChaosIdleHall = {stateOf = function() return {} end, moveToHall = function(p) moved = p:getName(); return true end}
eq(run(gm, "chaos_player.idlehall_send", {player = "Plain"}).ok and moved, "Plain", "idle hall: send")

local started
ChaosWorldBoss = {findBoss = function(a) return a == "" and nil or 2 end, start = function(i) started = i or "schedule"; return true end,
	stop = function() return true end, status = function() return "idle" end}
eq(run(admin, "chaos_bosses.worldboss_start", {boss = "2"}).ok and started, 2, "world boss: start a chosen boss")

local kit
ChaosTestKit = {kits = {mage = {}}, give = function(p, kind) kit = p:getName() .. ":" .. tostring(kind); return kind or "mage" end}
eq(run(admin, "tools.testkit", {player = "Plain", kind = "mage"}).ok and kit, "Plain:mage", "testkit through ChaosTestKit.give")
eq(run(admin, "tools.testkit", {kind = "nonsense"}).ok, false, "an unknown kit is refused")

ChaosCandlemarks = nil
r = run(admin, "chaos_currency.candlemarks_view", {player = "Plain"})
eq(r and r.ok, false, "a system that is not loaded: refused, not an error")
check(r and r.message:find("not loaded", 1, true), "and says so")

print = realPrint
print(string.format("admin_panel_test: %d checks, %d failures (%d actions, catalog %d bytes in %d parts)", checks, failures, #ids, #raw, #parts))
if failures > 0 then os.exit(1) end

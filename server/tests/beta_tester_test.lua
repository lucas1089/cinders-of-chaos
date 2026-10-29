-- Run from the server/ folder: luajit tests/beta_tester_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- Beta testers (beta_tester.lua, beta_core.lua, beta_config.lua tester): the windows, the record, the title that shows
-- only once the beta switch is off, and the SQL file. Engine mocked, the table in memory.
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
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	return s
end
local function at(y, mo, d, h, mi)
	return os.time({year = y, month = mo, day = d, hour = h, min = mi or 0, sec = 0})
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/beta_core.lua")
local B = ChaosBetaCore
local cfg = dofile("data/scripts/chaos/beta_config.lua")

-- ====================================================================== core
eq(B.parseTime("2026-10-31 15:00"), at(2026, 10, 31, 15), "parse")
eq(B.parseTime("31/10/2026"), nil, "bad date")
eq(B.parseTime(nil), nil, "no date")
eq(#cfg.tester.windows, 2, "two beta weekends")
ok(not B.inTesterWindow(cfg, at(2026, 10, 30, 20)), "Friday staff smoke test: not a tester window")
ok(not B.inTesterWindow(cfg, at(2026, 10, 31, 14, 59)), "a minute before weekend 1")
ok(B.inTesterWindow(cfg, at(2026, 10, 31, 15)), "weekend 1 opens")
ok(B.inTesterWindow(cfg, at(2026, 11, 1, 23)), "weekend 1 closes")
ok(not B.inTesterWindow(cfg, at(2026, 11, 1, 23, 1)), "after weekend 1")
ok(not B.inTesterWindow(cfg, at(2026, 11, 4, 12)), "between the weekends")
ok(B.inTesterWindow(cfg, at(2026, 11, 7, 15)), "weekend 2 opens")
ok(B.inTesterWindow(cfg, at(2026, 11, 8, 22)), "weekend 2")
ok(not B.inTesterWindow(cfg, at(2026, 11, 20, 15)), "launch: no window")
ok(not B.inTesterWindow({}, at(2026, 11, 1, 12)), "no tester config")
eq(B.testerSql(7, 12, 99), "INSERT IGNORE INTO `chaos_beta_testers` (`account_id`, `first_at`, `player_id`) VALUES (7, 99, 12)", "sql")
eq(B.testerSql(0, 12, 99), nil, "no account")
eq(B.testerSql("7 OR 1=1", 12, 99), nil, "not a number")
local off = {enabled = false, tester = cfg.tester}
local on = {enabled = true, tester = cfg.tester}
eq(B.testerTitle(off, true).text, "Beta Tester", "title at launch")
eq(B.testerTitle(off, true).key, "betatester", "title key")
eq(B.testerTitle(off, false), nil, "not a tester: no title")
eq(B.testerTitle(on, true), nil, "the beta is still on: no title yet")
ok(#cfg.tester.title.text <= 24, "a title fits the plate (24 characters)")
ok(cfg.tester.title.color:match("^#%x%x%x%x%x%x$") ~= nil, "title color")

-- the SQL file and the engine's CREATE agree; the wipe keeps the table (docs/BETA.md section 9)
local sql = readFile("sql/chaos_beta_testers.sql")
ok(sql:find("CREATE TABLE IF NOT EXISTS `chaos_beta_testers`", 1, true) ~= nil, "sql file")
ok(B.TESTERS_SCHEMA:find("PRIMARY KEY (`account_id`)", 1, true) ~= nil and sql:find("PRIMARY KEY (`account_id`)", 1, true) ~= nil, "one row per account")
ok(readFile("../docs/BETA.md"):find("'chaos_beta_testers'", 1, true) ~= nil, "docs/BETA.md keeps the table at the wipe")

-- ====================================================================== engine
local rows, cursor, nextId = {}, {}, 0
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	query = function(q)
		if q:find("CREATE TABLE", 1, true) then
			return true
		end
		local acc, first, pid = q:match("VALUES %((%d+), (%d+), (%d+)%)")
		if q:find("INSERT IGNORE INTO `chaos_beta_testers`", 1, true) and acc then
			acc = tonumber(acc)
			rows[acc] = rows[acc] or {first = tonumber(first), player = tonumber(pid)}
			return true
		end
		error("unexpected query " .. q)
	end,
	storeQuery = function(q)
		local acc = q:match("`account_id` = (%d+)")
		if not (q:find("chaos_beta_testers", 1, true) and acc) then
			error("unexpected query " .. q)
		end
		if not rows[tonumber(acc)] then
			return false
		end
		nextId = nextId + 1
		cursor[nextId] = {rows = {{n = 1}}, i = 1}
		return nextId
	end
}
result = {
	getNumber = function(id, col) return tonumber(cursor[id].rows[cursor[id].i][col]) or 0 end,
	getString = function(id, col) return tostring(cursor[id].rows[cursor[id].i][col] or "") end,
	next = function(id) cursor[id].i = cursor[id].i + 1; return cursor[id].rows[cursor[id].i] ~= nil end,
	free = function(id) cursor[id] = nil end
}
local events = {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) o.t = t end
	function o:register() events[name] = o end
	return o
end
local registered = {}
ChaosTitles = {register = function(source, fn) registered[source] = fn end}
local function newPlayer(id, account)
	local p = {}
	function p:getId() return id end
	function p:getGuid() return id - 1000 end
	function p:getAccountId() return account end
	return p
end
local realPrint = print
print = function() end

dofile("data/scripts/chaos/beta_tester.lua")
local T = ChaosBetaTester
ok(events.ChaosBetaTesterLogin ~= nil and events.ChaosBetaTesterLogin.t == "login", "login event")
ok(registered.betatester ~= nil, "title source registered")

local a, b = newPlayer(1001, 7), newPlayer(1002, 8)
-- outside a window: nothing recorded
ok(not T.record(a, at(2026, 10, 30, 20)), "smoke test night: not recorded")
eq(rows[7], nil, "no row")
-- inside: recorded once
ok(T.record(a, at(2026, 10, 31, 16)), "weekend 1: recorded")
eq(rows[7] and rows[7].first, at(2026, 10, 31, 16), "first login time")
eq(rows[7] and rows[7].player, 1, "with the character")
T.record(a, at(2026, 11, 7, 16))
eq(rows[7].first, at(2026, 10, 31, 16), "the first login stays")
-- the beta is on: no title yet. At launch (switch off) the tester has it and another account does not.
local plain = registered.betatester
eq(plain(a), nil, "beta on: no title")
T.config.enabled = false -- launch
eq(plain(a).text, "Beta Tester", "launch: the recorded account has the title")
eq(plain(b), nil, "launch: an account that never logged in does not")
T.config.enabled = true
-- the login event records and survives an error
events.ChaosBetaTesterLogin.onLogin(b)
print = realPrint
ok(true, "login event runs")

print(string.format("beta_tester_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

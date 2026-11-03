-- Run from the server/ folder: luajit tests/survey_test.lua (or lua5.3; CI runs both)
-- New player survey (O374; survey.lua, survey_core.lua, survey_config.lua; client game_chaossurvey; server/README.md "New
-- player funnel and survey (O374)"). Checks: the opcode (122: free, unique, named by no other script or client module);
-- the storage block; the text cleaning (UTF-8, control and format characters, 200 letters); the stage rules (level up,
-- login window, the account's rows); the answer parsing; the rate limit; the SQL (INSERT IGNORE, escaped, no name); and
-- survey.lua on a mocked engine: level 20 -> window out of combat -> answer -> row -> never again, skip, logout before an
-- answer, another character of the same account, staff and testers. All data is synthetic.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
SKILL_LEVEL = 8

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- ---------------------------------------------------------------- mocked engine
local queries, sent, registry, online = {}, {}, {}, {}
local rows = {} -- account -> {stage = row}
local now = 1000000
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return now end
db = {
	query = function(q) queries[#queries + 1] = q return true end,
	asyncQuery = function(q) queries[#queries + 1] = q
		local acc, stage = q:match("VALUES %((%d+), (%d+),")
		if acc then
			acc, stage = tonumber(acc), tonumber(stage)
			rows[acc] = rows[acc] or {}
			if not rows[acc][stage] then rows[acc][stage] = q end
		end
		return true
	end,
	escapeString = function(s) return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'" end,
	storeQuery = function(q)
		queries[#queries + 1] = q
		local acc = q:match("`account_id` = (%d+)")
		if acc then
			local list = {}
			for st in pairs(rows[tonumber(acc)] or {}) do list[#list + 1] = st end
			if #list == 0 then return false end
			return {list = list, i = 1, col = "stage"}
		end
		if q:find("onlinetime", 1, true) then return {list = {600}, i = 1, col = "t"} end
		return false
	end,
}
result = {
	getNumber = function(r, c) return r.list[r.i] end,
	getString = function(r, c) return tostring(r.list[r.i]) end,
	next = function(r) r.i = r.i + 1 return r.list[r.i] ~= nil end,
	free = function() end,
}
json = {encode = function() return "{}" end, decode = function(s) return NEXT end}
local function event(kind)
	return function(name)
		local e = {name = name}
		function e:type() end
		function e:register() registry[name] = self end
		function e:interval() end
		return e
	end
end
CreatureEvent = event("creature")
GlobalEvent = event("global")
Player = function(id) return online[id] end

dofile("data/scripts/chaos/chaos_constants.lua")
function Chaos.send(player, opcode, action, data)
	sent[#sent + 1] = {who = player:getId(), opcode = opcode, action = action, data = data}
	return true
end
local inCombat = {}
function Chaos.inCombat(player) return inCombat[player:getId()] == true end
dofile("data/scripts/chaos/ratelimit.lua")
local cfg = dofile("data/scripts/chaos/survey_config.lua")
dofile("data/scripts/chaos/survey_core.lua")
local S = ChaosSurveyCore

-- ---------------------------------------------------------------- opcode and storage
eq(ChaosOpcodes.survey, 122, "opcode 122")
do
	local seen = {}
	for name, v in pairs(ChaosOpcodes) do
		check(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
		seen[v] = name
	end
	for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 125, 126, 127, 144, 145, 146, 140, 210,
		212, 213, 230, 246}) do
		check(ChaosOpcodes.survey ~= v, "not an opcode of the reference server or client: " .. v)
	end
	-- no other script or client module on 122
	local others = 0
	local p = io.popen('ls data/scripts/chaos/*.lua ../client/overlay/modules/*/*.lua 2>/dev/null')
	for file in p:lines() do
		if not file:find("survey", 1, true) and not file:find("chaos_constants", 1, true) then
			local s = readFile(file) or ""
			if s:find("[Oo][Pp][Cc][Oo][Dd][Ee][%w_]*%s*=%s*122%f[%D]") or s:find("xtended[%w]*Opcode%(%s*122%f[%D]") then
				others = others + 1
				io.write("opcode 122 in " .. file .. "\n")
			end
		end
	end
	p:close()
	eq(others, 0, "no other script or module on 122")
	local client = readFile("../client/overlay/modules/game_chaossurvey/survey.lua") or ""
	check(client:find("local OPCODE = 122", 1, true) ~= nil, "the client listens on 122")
	eq(cfg.storage, 7103060, "storage block 7103060")
	eq(Chaos.storage.survey, cfg.storage, "Chaos.storage.survey")
	local readme = readFile("README.md") or ""
	check(readme:find("| 7103060 - 7103069 |", 1, true) ~= nil, "README storage table names the block")
	check(readme:find("7102834", 1, true) ~= nil, "README names the last system storage")
	local sql = readFile("sql/chaos_survey.sql") or ""
	check(sql:find("UNIQUE KEY `account_stage` (`account_id`, `stage`)", 1, true) ~= nil, "sql: one row per account and stage")
	check(S.createSql("chaos_survey"):find("UNIQUE KEY `account_stage` (`account_id`, `stage`)", 1, true) ~= nil, "createSql: same key")
	-- the client's text limit equals the server's
	local logic = readFile("../client/overlay/modules/game_chaossurvey/surveylogic.lua") or ""
	check(logic:find("L.TEXT_MAX = " .. cfg.textMax, 1, true) ~= nil, "client text limit " .. cfg.textMax)
	-- the report tool reads the same table and stages
	local tool = readFile("tools/newplayer_report.py") or ""
	check(tool:find('SURVEY_TABLE = "chaos_survey"', 1, true) ~= nil, "report tool reads chaos_survey")
	check(tool:find("STAGES = [" .. table.concat(cfg.stages, ", ") .. "]", 1, true) ~= nil, "report tool stages")
end

-- ---------------------------------------------------------------- text
eq(S.cleanText("  hello   world  ", 200), "hello world", "spaces folded and trimmed")
eq(S.cleanText("a\nb\tc\0d", 200), "a b c d", "control characters become spaces")
eq(S.cleanText("n\195\163o sei", 200), "n\195\163o sei", "a 2-byte letter kept")
eq(S.cleanText("\226\130\172 5", 200), "\226\130\172 5", "a 3-byte letter kept")
eq(S.cleanText("x\240\159\152\128y", 200), "xy", "a 4-byte character dropped")
eq(S.cleanText("a\255\254b\195", 200), "ab", "invalid bytes dropped")
eq(S.cleanText("a\226\128\174b\226\128\168c", 200), "abc", "direction and line separator characters dropped")
eq(S.cleanText("a\237\160\128b", 200), "ab", "a surrogate dropped")
eq(S.cleanText("a\192\175b", 200), "ab", "an overlong dropped")
eq(S.cleanText(nil, 200), "", "nil")
eq(S.cleanText(5, 200), "", "a number")
do
	local long = string.rep("\195\169", 300)
	local c = S.cleanText(long, 200)
	eq(#c, 400, "200 letters of 2 bytes")
	eq(#S.cleanText(string.rep("ab ", 200), 200), 200, "200 letters of a long text")
	eq(S.cleanText("abc   ", 4), "abc", "a trailing space at the cut is trimmed")
end
eq(S.cleanText("'; DROP TABLE x; --", 200), "'; DROP TABLE x; --", "quotes are kept (escaped by the SQL)")

-- ---------------------------------------------------------------- stages
eq(S.dueAtAdvance(19, 20, 0, cfg), 20, "level 20 reached")
eq(S.dueAtAdvance(18, 52, 0, cfg), 50, "two stages crossed: the higher")
eq(S.dueAtAdvance(20, 21, 0, cfg), nil, "no stage crossed")
eq(S.dueAtAdvance(19, 20, 1, cfg), nil, "stage 20 already handled")
eq(S.dueAtAdvance(49, 50, 1, cfg), 50, "stage 50 after 20")
eq(S.dueAtLogin(19, 0, cfg), nil, "below 20")
eq(S.dueAtLogin(20, 0, cfg), 20, "at 20")
eq(S.dueAtLogin(34, 0, cfg), 20, "in the window")
eq(S.dueAtLogin(35, 0, cfg), nil, "past the window")
eq(S.dueAtLogin(55, 0, cfg), 50, "stage 50 at 55")
eq(S.dueAtLogin(55, 2, cfg), nil, "stage 50 handled")
eq(S.dueAtLogin(300, 0, cfg), nil, "a veteran is not asked")
eq(S.maskFromStages(0, {20, 50, 77}, cfg), 3, "mask from the account's rows")
check(S.needsLookup(25, 0, cfg) and not S.needsLookup(25, 1, cfg), "needsLookup")
eq(S.setBit(1, 1), 1, "setBit twice")
check(math.type == nil or math.type(S.setBit(0, 2)) == "integer", "setBit gives an integer")

-- ---------------------------------------------------------------- parse
do
	local r = S.parse("answer", {s = 20, fun = 4, rec = true, text = " the map \n"}, 20, cfg)
	check(r and r.status == "answered" and r.fun == 4 and r.recommend == 1 and r.confused == "the map", "a full answer")
	r = S.parse("answer", {s = 20, fun = 9, rec = "yes", text = ""}, 20, cfg)
	check(r and r.status == "skipped" and r.fun == 0 and r.recommend == -1, "nothing valid: a skip")
	r = S.parse("answer", {s = 20, fun = 2.5, rec = false}, 20, cfg)
	check(r and r.status == "answered" and r.fun == 0 and r.recommend == 0, "a fraction is no score; no is an answer")
	r = S.parse("skip", {s = 50}, 50, cfg)
	check(r and r.status == "skipped" and r.stage == 50, "skip")
	local bad, why = S.parse("answer", {s = 50}, 20, cfg)
	check(bad == nil and why == "stage", "another stage than offered")
	bad, why = S.parse("answer", {s = 20}, nil, cfg)
	check(bad == nil and why == "stage", "nothing offered")
	bad, why = S.parse("drop", {s = 20}, 20, cfg)
	check(bad == nil and why == "action", "unknown action")
	r = S.parse("answer", {s = 20, text = string.rep("x", 5000)}, 20, cfg)
	eq(#r.confused, 200, "text capped")
	r = S.parse("answer", "junk", 20, cfg)
	eq(r, nil, "data not a table: no stage")
end

-- ---------------------------------------------------------------- global limit and SQL
do
	local st = {}
	local ok = 0
	for _ = 1, cfg.perMinute + 10 do
		if S.allowGlobal(st, 600, cfg) then ok = ok + 1 end
	end
	eq(ok, cfg.perMinute, "perMinute rows a minute")
	check(S.allowGlobal(st, 660, cfg), "the next minute")
	local q = S.insertSql("chaos_survey", 7, {stage = 20, status = "answered", fun = 3, recommend = 1, confused = "it's"},
		22, 95, 1234, db.escapeString)
	check(q:find("^INSERT IGNORE INTO `chaos_survey`") ~= nil, "INSERT IGNORE")
	check(q:find("VALUES (7, 20, 'answered', 3, 1, 'it\\'s', 22, 95, 1234)", 1, true) ~= nil, "values escaped: " .. q)
	check(not q:find("`name`", 1, true), "no name column")
end

-- ---------------------------------------------------------------- survey.lua on a mocked engine
dofile("data/scripts/chaos/survey.lua")
local V = ChaosSurvey
local function mk(o)
	local p = {storage = {}}
	for k, v in pairs(o) do p[k] = v end
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:getAccountId() return self.account end
	function p:getLevel() return self.level end
	function p:getGroup() local g = self.group or 1 return {getId = function() return g end} end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:registerEvent() end
	return p
end
local function login(p) online[p.id] = p registry.ChaosSurveyLogin.onLogin(p) end
local function logout(p) registry.ChaosSurveyLogout.onLogout(p) online[p.id] = nil end
local function levelUp(p, to) local old = p.level p.level = to registry.ChaosSurveyAdvance.onAdvance(p, SKILL_LEVEL, old, to) end
local function tick() registry.ChaosSurveyThink.onThink(5000) end
local function opened(p) local c = 0 for _, m in ipairs(sent) do if m.who == p.id and m.action == "open" then c = c + 1 end end return c end
local function msg(p, action, data)
	NEXT = {action = action, data = data}
	now = now + 3 -- past the rate limit (os.mtime is not mocked: os.time * 1000)
	registry.ChaosSurveyExtended.onExtendedOpcode(p, 122, "x")
end

local a = mk({id = 1, account = 100, level = 19})
login(a)
eq(opened(a), 0, "level 19: nothing")
levelUp(a, 20)
tick()
eq(opened(a), 0, "the delay first")
now = now + 5
inCombat[1] = true
tick()
eq(opened(a), 0, "not in combat")
inCombat[1] = nil
tick()
eq(opened(a), 1, "level 20: opened out of combat")
eq(sent[#sent].opcode, 122, "on 122")
eq(sent[#sent].data.s, 20, "stage 20")
eq(sent[#sent].data.max, 200, "the text limit")
msg(a, "answer", {s = 50, fun = 5})
eq(rows[100], nil, "a stage not offered is ignored")
msg(a, "answer", {s = 20, fun = 5, rec = true, text = "Where is the bank?"})
check(rows[100] and rows[100][20] ~= nil, "the row is written")
check(rows[100][20]:find("'answered', 5, 1, 'Where is the bank?'", 1, true) ~= nil, "the answers in the row")
eq(sent[#sent].action, "done", "done sent")
eq(a.storage[cfg.storage], 1, "the stage bit")
msg(a, "answer", {s = 20, fun = 1})
eq(select(2, rows[100][20]:gsub("INSERT", "")), 1, "a second answer is not accepted")
-- never again on this account: relog, and another character
logout(a)
login(a)
tick() now = now + 10 tick()
eq(opened(a), 1, "relog: not asked again")
local b = mk({id = 2, account = 100, level = 22})
login(b)
now = now + 10 tick()
eq(opened(b), 0, "another character of the account: not asked (the row is found)")
eq(b.storage[cfg.storage], 1, "its bit is set from the table")
-- skip, then a logout before an answer at 50
local c = mk({id = 3, account = 200, level = 19})
login(c)
levelUp(c, 20)
now = now + 10 tick()
eq(opened(c), 1, "c: opened")
msg(c, "skip", {s = 20})
check(rows[200] and rows[200][20]:find("'skipped'", 1, true) ~= nil, "skip written")
levelUp(c, 50)
now = now + 10 tick()
eq(opened(c), 2, "c: stage 50 opened")
logout(c)
login(c)
now = now + 10 tick()
eq(opened(c), 3, "logout before an answer: offered again at the next login")
msg(c, "answer", {s = 50, text = "\240\159\152\128 fun"})
check(rows[200][50]:find("'fun'", 1, true) ~= nil, "the cleaned text is stored")
-- staff and testers
local gm = mk({id = 4, account = 300, level = 19, group = 4})
login(gm) levelUp(gm, 20) now = now + 10 tick()
eq(opened(gm), 0, "staff is never asked")
local bot = mk({id = 5, account = 400, level = 19})
bot.storage[Chaos.storage.tester] = 1
login(bot) levelUp(bot, 20) now = now + 10 tick()
eq(opened(bot), 0, "a tester bot is never asked")
-- a veteran: no database lookup at login
local q0 = #queries
local vet = mk({id = 6, account = 500, level = 400})
login(vet)
eq(#queries, q0, "a veteran's login reads nothing")
-- the rate limit: two messages at once
local d = mk({id = 7, account = 600, level = 19})
login(d) levelUp(d, 20) now = now + 10 tick()
NEXT = {action = "drop", data = {}}
registry.ChaosSurveyExtended.onExtendedOpcode(d, 122, "x")
NEXT = {action = "skip", data = {s = 20}}
registry.ChaosSurveyExtended.onExtendedOpcode(d, 122, "x")
eq(rows[600], nil, "a second message inside requestMs is dropped")
msg(d, "skip", {s = 20})
check(rows[600] ~= nil, "after the wait it goes through")
-- privacy: no name, IP in any statement
local all = table.concat(queries, "\n")
for _, bad in ipairs({"`name`", "lastip", "`ip`"}) do
	check(not all:find(bad, 1, true), "no " .. bad .. " in any statement")
end
os.time = realTime

if failures == 0 then
	print(string.format("survey_test: %d checks passed", count))
else
	print(string.format("survey_test: %d of %d checks FAILED", failures, count))
	os.exit(1)
end

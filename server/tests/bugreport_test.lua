-- Run from the server/ folder: luajit tests/bugreport_test.lua (or lua5.3; CI runs both)
-- Bug reports (System > Report a Bug): reports_core.lua (validation, categories, text cap, positions, limits, staff
-- lines, webhook), reports.lua RP.onReportBug against a mocked engine (every account type, the row, the confirmation,
-- Chaos.limited, the per-account limits, staff notice, /reports list bugs) and tools/patch_base_events.py step 12 on the
-- stock Player:onReportBug (patched once, second run unchanged, unknown file reported).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/antibot_config.lua")
dofile("data/scripts/chaos/reports_core.lua")
local R = ChaosReportsCore
local B = cfg.reports.bugs

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

-- ---------------------------------------------------------------- core
do
	check(B and B.enabled ~= false, "bug reports configured and on")
	check(B.textMax + #"[technical] " <= 255, "the note fits chaos_reports.note")
	local v, err = R.validateBug(B, "0", 0)
	eq(v, nil, "an unpatched client's lone category digit is refused")
	eq(err, "bugshort", "with the short text error")
	eq(select(2, R.validateBug(B, "   \n\t  ", 3)), "bugshort", "blank text refused")
	v = R.validateBug(B, "Wall\nmissing\tnear the temple", 0)
	eq(v.category, "map", "category 0 is map")
	eq(v.text, "Wall missing near the temple", "control characters folded")
	eq(v.note, "[map] Wall missing near the temple", "note carries the category")
	eq(v.shortened, false, "not shortened")
	eq(R.validateBug(B, "typo in npc", 1).category, "typo", "1 typo")
	eq(R.validateBug(B, "client froze", 2).category, "technical", "2 technical")
	eq(R.validateBug(B, "something odd", 3).category, "other", "3 other")
	eq(R.validateBug(B, "something odd", 99).category, "other", "unknown category -> other")
	eq(R.validateBug(B, "something odd", nil).category, "other", "no category -> other")
	v = R.validateBug(B, string.rep("x", 2000), 3)
	eq(#v.text, B.textMax, "text capped")
	eq(v.shortened, true, "shortened flag")
	check(#v.note <= 255, "capped note fits the column")
	eq(#R.validateBug(B, string.rep("\200", 50) .. "abcdefg", 3).text, 7, "non-ASCII stripped")
	eq(select(2, R.validateBug({enabled = false}, "a long enough text", 3)), "bugdisabled", "switched off")
	for _, key in ipairs({"bugdisabled", "bugshort", "bugrapid", "bugday"}) do
		check(type(R.errors[key]) == "string", "error text " .. key)
	end

	-- positions
	local own = {x = 1000, y = 1000, z = 7}
	local p, kind = R.bugPosition(0, {x = 1005, y = 998, z = 6}, own)
	eq(kind, "reported tile", "map report keeps the reported tile")
	eq(p.x .. "," .. p.y .. "," .. p.z, "1005,998,6", "reported tile values")
	p, kind = R.bugPosition(0, {x = 0, y = 0, z = 0}, own)
	eq(kind, "character", "map report without a tile -> character")
	p, kind = R.bugPosition(2, {x = 1005, y = 998, z = 6}, own)
	eq(kind, "character", "other categories -> character position")
	eq(p.x, 1000, "character x")
	p = R.bugPosition(0, nil, own)
	eq(p.y, 1000, "nil position handled")

	-- limits per account
	local st = R.newState()
	local t0 = 1700000000
	check(R.allowBug(st, B, 7, t0), "first allowed")
	R.recordBug(st, 7, t0)
	eq(select(2, R.allowBug(st, B, 7, t0 + 1)), "bugrapid", "cooldown")
	check(R.allowBug(st, B, 8, t0 + 1), "other account not affected")
	local now = t0
	for i = 2, B.perDay do
		now = now + B.cooldownSeconds
		check(R.allowBug(st, B, 7, now), "allowed " .. i)
		R.recordBug(st, 7, now)
	end
	eq(select(2, R.allowBug(st, B, 7, now + B.cooldownSeconds)), "bugday", "per-day cap")
	check(R.allowBug(st, B, 7, (math.floor(now / 86400) + 1) * 86400), "next day allowed")
	local st2 = R.newState()
	check(R.allow(st2, cfg.reports, {account = 7}, 2, t0), "player reports have their own limits")

	-- staff text and webhook
	local details = R.bugDetails({category = "map", pos = {x = 5, y = 6, z = 7}, posKind = "reported tile",
		own = {x = 1, y = 2, z = 3}, level = 42, vocation = "Templar", at = t0, shortened = true})
	check(details:find("Category: map", 1, true) and details:find("Character position: 1, 2, 3", 1, true) and
		details:find("Reported map tile: 5, 6, 7", 1, true) and details:find("Level 42, Templar", 1, true) and
		details:find("shortened", 1, true), "detail lines")
	check(not R.bugDetails({category = "other", pos = {x = 1, y = 2, z = 3}, posKind = "character",
		own = {x = 1, y = 2, z = 3}, level = 1, at = t0}):find("Reported map tile", 1, true), "no tile line for other")
	local line = R.listLine({id = 9, status = "open", created_at = t0, reporter_name = "Alice", reason = "bug",
		note = "[map] " .. string.rep("y", 100), pos_x = 5, pos_y = 6, pos_z = 7})
	check(line:find("#9 open", 1, true) and line:find("bug from Alice at 5, 6, 7", 1, true) and line:find("...", 1, true),
		"bug list line: " .. line)
	check(R.listLine({id = 1, status = "open", created_at = t0, reporter_name = "A", target_name = "B", reason = "scam",
		suspicion = 3}):find("A reported B", 1, true), "player report line unchanged")
	local payload = R.discordPayload({id = 9, reason = "bug", category = "map", reporter_name = "Alice", pos_x = 5,
		pos_y = 6, pos_z = 7, note = "[map] @everyone secret"})
	eq(payload.content, "New bug report #9 (map) from Alice at 5, 6, 7.", "webhook text")
	check(not payload.content:find("everyone", 1, true), "player text never in the webhook")
	eq(#payload.allowed_mentions.parse, 0, "no mentions")
end

-- ---------------------------------------------------------------- reports.lua against a mocked engine
do
	local queries, lastId = {}, 0
	db = {
		query = function(q)
			queries[#queries + 1] = q
			if q:find("^INSERT INTO `chaos_reports`") then lastId = lastId + 1 end
			return true
		end,
		storeQuery = function() return false end,
		escapeString = function(s) return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'" end,
		lastInsertId = function() return lastId end
	}
	result = {free = function() end}
	json = {encode = function(t) return t end}
	local talks, callbacks = {}, {}
	function CreatureEvent(name) return {type = function() end, register = function() end} end
	function GlobalEvent(name) return {interval = function() end, type = function() end, register = function() end} end
	function TalkAction(words)
		local e = {separator = function() end, register = function() end}
		talks[words] = e
		return e
	end
	EventCallback = setmetatable({}, {__newindex = function(t, k, v) callbacks[k] = v end,
		__index = function(t, k) if k == "register" then return function() end end end})
	local clock = 5000000
	os.mtime = function() return clock end
	local players = {}
	local P = {}
	P.__index = P
	local function mk(guid, name, group, accountType)
		local p = setmetatable({guid = guid, id = 9000 + guid, name = name, group = group or 1, level = 30,
			accountType = accountType or 1, pos = {x = 1000, y = 1000, z = 7}, msgs = {}, account = 500 + guid}, P)
		players[#players + 1] = p
		return p
	end
	function P:getId() return self.id end
	function P:getGuid() return self.guid end
	function P:getName() return self.name end
	function P:getLevel() return self.level end
	function P:getAccountId() return self.account end
	function P:getAccountType() return self.accountType end
	function P:getVocation() return {getName = function() return "Ranger" end} end
	function P:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function P:getPosition() local p = self.pos return {x = p.x, y = p.y, z = p.z} end
	function P:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = {kind = kind, text = text} end
	function P:popupFYI(text) self.msgs[#self.msgs + 1] = {text = text} end
	Game = {getPlayers = function() return players end}
	dofile("data/scripts/chaos/ratelimit.lua")
	ChaosReports, ChaosAdminPending = nil, nil
	dofile("data/scripts/chaos/reports.lua")
	local RP = ChaosReports
	check(type(RP.onReportBug) == "function", "ChaosReports.onReportBug for the patched player.lua")

	local normal = mk(1, "Alice", 1, 1) -- ACCOUNT_TYPE_NORMAL: the stock script refused this one
	local other = mk(2, "Bob", 1, 1)
	local gm = mk(3, "Gamemaster", 6, 5)
	local last = function(p) return p.msgs[#p.msgs] and p.msgs[#p.msgs].text or "" end

	eq(RP.onReportBug(normal, "The bridge at the north gate has no floor", {x = 1010, y = 990, z = 7}, 0), true,
		"the event returns true")
	local ins = queries[#queries]
	check(ins:find("INSERT INTO `chaos_reports`", 1, true), "row written")
	check(ins:find("'bug'", 1, true), "reason bug")
	check(ins:find("'[map] The bridge at the north gate has no floor'", 1, true), "note with category and text")
	check(ins:find(", 1010, 990, 7, 1, 0, ", 1, true), "reported tile stored as the position")
	check(ins:find("Character position: 1000, 1000, 7", 1, true), "character position in the details")
	check(ins:find("Level 30, Ranger", 1, true), "character level and vocation in the details")
	check(ins:find("'Alice'", 1, true), "character name")
	check(ins:find("^INSERT INTO `chaos_reports` %(`created_at`[^)]*%) VALUES %(" .. os.time()) or
		ins:find("VALUES %(%d+, 1, 501, "), "time, character id and account")
	check(last(normal):find("Thank you. Your bug report #1 was sent to the staff.", 1, true), "confirmation: " .. last(normal))
	check(last(gm):find("[Bug #1] Alice (map) at 1010, 990, 7", 1, true), "online staff told: " .. last(gm))
	eq(last(other), "", "other players not told")

	-- Chaos.limited: same character right away
	local before = #queries
	RP.onReportBug(normal, "A second report right after the first", nil, 3)
	eq(#queries, before, "no row inside rapidMs")
	eq(last(normal), R.errors.bugrapid, "rate limit answer")
	-- after rapidMs, still inside the account cooldown (a relog does not reset it)
	clock = clock + B.rapidMs + 1
	RP.onReportBug(normal, "A second report a little later", nil, 3)
	eq(#queries, before, "account cooldown")
	eq(last(normal), R.errors.bugrapid, "cooldown answer")
	-- short text (unpatched client)
	RP.onReportBug(other, "2", nil, 3)
	eq(last(other), R.errors.bugshort, "short text answer")
	eq(#queries, before, "no row for a short text")
	-- long text: capped, told
	RP.onReportBug(other, string.rep("z", 1000), nil, 2)
	check(queries[#queries]:find("'[technical] " .. string.rep("z", B.textMax) .. "'", 1, true), "long text capped")
	check(last(other):find("shortened to " .. B.textMax, 1, true), "player told about the cap")
	check(queries[#queries]:find(", 1000, 1000, 7, 1, 0, ", 1, true), "technical report: character position")
	-- per day
	local realTime = os.time
	local t = realTime()
	os.time = function() return t end
	local okCount = 0
	for i = 1, B.perDay + 2 do
		clock = clock + B.rapidMs + 1
		t = t + B.cooldownSeconds
		RP.onReportBug(gm, "Staff test report number " .. i, nil, 3)
		if last(gm):find("was sent to the staff", 1, true) then okCount = okCount + 1 end
	end
	os.time = realTime
	eq(okCount, B.perDay, "per-day cap per account")
	eq(last(gm), R.errors.bugday, "per-day answer")
	-- a failing database never breaks the event
	local realQuery = db.query
	db.query = function() error("gone") end
	clock = clock + B.rapidMs + 1
	eq(RP.onReportBug(mk(4, "Carol"), "Database is down right now", nil, 3), true, "event survives a db error")
	check(last(players[4]):find("could not be stored", 1, true), "player told it failed")
	db.query = realQuery

	-- staff view
	local realSelect = Chaos.select
	local seen
	Chaos.select = function(q) seen = q return {} end
	talks["/reports"].onSay(gm, "/reports", "list bugs")
	check(seen and seen:find("`reason` = 'bug'", 1, true) and seen:find("`status` = 'open'", 1, true), "/reports list bugs")
	Chaos.select = function() return {{id = 1, created_at = 1, reporter_name = "Alice", target_id = 1, target_name = "Alice",
		reason = "bug", note = "[map] hole", pos_x = 1, pos_y = 2, pos_z = 7, target_online = 1, suspicion = 0,
		chat = "Category: map", status = "open", closed_at = 0, closed_by = "", staff_note = ""}} end
	local d = RP.detail(1)
	check(d[2]:find("(bug report)", 1, true) and d[3] == "Text: [map] hole" and d[4] == "Details:", "bug detail view")
	Chaos.select = realSelect
	local opts = ChaosAdminPending["security.reports_list"].params[1].options
	local hasBugs = false
	for _, o in ipairs(opts) do hasBugs = hasBugs or o.value == "bugs" end
	check(hasBugs, "admin panel filter for bug reports")
end

-- ---------------------------------------------------------------- tools/patch_base_events.py step 12
local STOCK = [[
function Player:onReportRuleViolation(targetName, reportType, reportReason, comment, translation)
	if hasEventCallback(EVENT_CALLBACK_ONREPORTRULEVIOLATION) then
		EventCallback(EVENT_CALLBACK_ONREPORTRULEVIOLATION, self, targetName, reportType, reportReason, comment, translation)
	end
end

function Player:onReportBug(message, position, category)
	if hasEventCallback(EVENT_CALLBACK_ONREPORTBUG) then
		return EventCallback(EVENT_CALLBACK_ONREPORTBUG, self, message, position, category)
	end
	return true
end
]]
local hasPython = os.execute("python3 -c 1 >/dev/null 2>&1")
if hasPython ~= true and hasPython ~= 0 then
	print("bugreport_test: python3 not found, patch checks skipped")
else
	local function runPatch(text)
		local path = os.tmpname()
		local f = assert(io.open(path, "wb"))
		f:write(text)
		f:close()
		local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_events as p; "
			.. "t = open(sys.argv[1]).read(); n, s = p.patch_report_bug(t); "
			.. "open(sys.argv[1], 'w').write(n); print(s)\" " .. path
		local h = assert(io.popen(cmd))
		local status = (h:read("*a") or ""):gsub("%s+$", "")
		h:close()
		f = assert(io.open(path, "rb"))
		local out = f:read("*a")
		f:close()
		os.remove(path)
		return out, status
	end
	local patched, status = runPatch(STOCK)
	eq(status, "patched", "patch applies to the stock function")
	local again, status2 = runPatch(patched)
	eq(status2, "already", "second run: already")
	eq(again, patched, "second run changes nothing")
	local _, status3 = runPatch("local x = 1\n")
	check(status3:find("unexpected", 1, true) ~= nil, "unknown file reported: " .. status3)

	-- the patched function: ChaosReports first, the stock callbacks only without it
	local chunk = assert(loadstring("local Player = {}\n" .. patched .. "\nreturn Player"))
	local stockCalls = 0
	hasEventCallback = function() return true end
	local realEC = EventCallback
	EventCallback = setmetatable({}, {__call = function() stockCalls = stockCalls + 1 return false end})
	local PL = chunk()
	local realReports = ChaosReports
	local got
	ChaosReports = {onReportBug = function(self, m, p, c) got = {self, m, p, c} return true end}
	eq(PL.onReportBug("me", "text here", {x = 1}, 0), true, "patched: Chaos answer")
	check(got and got[1] == "me" and got[2] == "text here" and got[4] == 0, "arguments passed through")
	eq(stockCalls, 0, "stock callback (refuses normal accounts) not run")
	ChaosReports = nil
	eq(PL.onReportBug("me", "text here", {x = 1}, 0), false, "without reports.lua the stock path runs")
	eq(stockCalls, 1, "stock callback ran")
	ChaosReports, EventCallback = realReports, realEC
end

print(string.format("bugreport_test: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end

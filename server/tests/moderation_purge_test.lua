-- Run from the server/ folder: luajit tests/moderation_purge_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The purge of old moderation records (data/scripts/chaos/moderation_purge_core.lua, numbers in
-- moderation_purge_config.lua): the config, the due check, the cutoffs, the protected accounts, names and IP bans, what
-- each table keeps (open reports, reports closed recently, uncleared holds, records of an account banned now or less than
-- appealDays ago, the admin log line of an active IP ban), the SQL. Then moderation_purge.lua against a mocked engine with
-- an in-memory database: a full run, a second run the same day does nothing, batches, a run a day later, a table at 0 days.
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

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/moderation_purge_core.lua")
local C = ChaosModerationPurgeCore
local cfg = dofile("data/scripts/chaos/moderation_purge_config.lua")
local DAY = 86400
local NOW = 1800000000

local function copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = type(v) == "table" and copy(v) or v
	end
	return o
end

-- ====================================================================== config
ok(C.validate(cfg), "shipped config is valid")
eq(cfg.tables.reports, Chaos.antibotTables.reports, "reports table = chaos_constants")
eq(cfg.tables.antibotLog, Chaos.antibotTables.log, "anti-bot log table = chaos_constants")
eq(cfg.tables.antibotHolds, Chaos.antibotTables.holds, "holds table = chaos_constants")
eq(cfg.tables.adminLog, "chaos_admin_log", "admin log table")
for _, k in ipairs(C.KINDS) do
	ok(cfg.days[k] >= 30, "days." .. k .. " is a real period")
	local sqlFile = k == "adminLog" and "sql/chaos_admin.sql" or "sql/chaos_reports.sql"
	local f = io.open(sqlFile, "r")
	local text = f:read("*a")
	f:close()
	ok(text:find("`" .. cfg.tables[k] .. "`", 1, true) ~= nil, k .. " table is in " .. sqlFile)
end
ok(cfg.appealDays >= 14, "an appeal window")
eq(cfg.runEverySeconds, DAY, "daily")
ok(cfg.checkSeconds <= 3600, "looked at every hour at least")

local bad = copy(cfg)
bad.days.reports = 7
ok(not C.validate(bad), "under 30 days refused")
bad = copy(cfg)
bad.days.adminLog = -1
ok(not C.validate(bad), "negative refused")
bad = copy(cfg)
bad.tables.adminLog = "players"
ok(not C.validate(bad), "only chaos_* tables")
bad = copy(cfg)
bad.days.antibotLog = 0
ok(C.validate(bad), "0 = never purged is valid")
eq(C.cutoff(bad, "antibotLog", NOW), nil, "0 days: no cutoff")
eq(C.cutoff(cfg, "reports", NOW), NOW - cfg.days.reports * DAY, "cutoff")
eq(C.appealSince(cfg, NOW), NOW - cfg.appealDays * DAY, "appeal window")

-- legal text and config in step: the policy names the period with the placeholder until the owner fills it; the
-- legal README says where the number lives
for _, lang in ipairs({"en", "pt-BR"}) do
	local f = io.open("../docs/legal/privacy." .. lang .. ".md", "r")
	if f then
		local text = f:read("*a")
		f:close()
		ok(text:find("[PRAZO DOS REGISTROS DE MODERAÇÃO]", 1, true) ~= nil or text:find(tostring(cfg.days.reports), 1, true) ~= nil,
			"privacy." .. lang .. " names the period")
	end
end
local rf = io.open("../docs/legal/README.md", "r")
if rf then
	local text = rf:read("*a")
	rf:close()
	ok(text:find("moderation_purge_config.lua", 1, true) ~= nil, "legal README points at the config")
end

-- ====================================================================== due
ok(C.due(0, NOW, cfg), "never ran: due")
ok(C.due(nil, NOW, cfg), "missing: due")
ok(not C.due(NOW - 3600, NOW, cfg), "an hour ago: not due")
ok(not C.due(NOW - DAY + 1, NOW, cfg), "just under a day: not due")
ok(C.due(NOW - DAY, NOW, cfg), "a day: due")
ok(C.due(NOW + DAY, NOW, cfg), "a last run in the future (clock moved back): due")
local off = copy(cfg)
off.enabled = false
ok(not C.due(0, NOW, off), "disabled: never due")

-- ====================================================================== context
local ctx = C.newContext({{account_id = 7}, {account_id = 7}, {account_id = 3}, {account_id = 0}},
	{{name = "Bad Guy"}, {name = " AltOne "}, {name = ""}}, {{banned_at = NOW - 100 * DAY}})
eq(#ctx.accountIds, 2, "accounts deduplicated, 0 dropped")
eq(ctx.accountIds[1], 3, "sorted")
ok(ctx.accounts[7] and ctx.accounts[3], "account set")
ok(ctx.names["bad guy"] and ctx.names["altone"], "names lower case, trimmed")
ok(ctx.names["7"], "a numeric account id counts as a name (account lookup)")
eq(#ctx.ipBans, 1, "ip bans")
eq(C.namesSql({}), nil, "no names query without accounts")
ok(C.namesSql({3, 7}):find("IN (3,7)", 1, true) ~= nil, "names query")
local bs = C.banSql(cfg, NOW)
ok(bs:find("`account_bans`", 1, true) and bs:find("`account_ban_history`", 1, true), "both ban tables")
ok(bs:find("`expires_at` <= 0", 1, true) ~= nil, "permanent bans (expires_at 0)")
ok(bs:find(tostring(NOW - cfg.appealDays * DAY), 1, true) ~= nil, "appeal window in the ban query")
ok(C.ipBanSql(cfg, NOW):find("`ip_bans`", 1, true) ~= nil, "ip ban query")

-- ====================================================================== keep
local cut = NOW - 730 * DAY
local old = cut - DAY
ok(C.keep("reports", {status = "open", closed_at = 0, target_account = 1}, ctx, cfg, cut), "open report kept")
ok(C.keep("reports", {status = "closed", closed_at = cut + 5, target_account = 1}, ctx, cfg, cut), "closed recently kept")
ok(C.keep("reports", {status = "closed", closed_at = old, target_account = 7}, ctx, cfg, cut), "banned target kept")
ok(not C.keep("reports", {status = "closed", closed_at = old, target_account = 1}, ctx, cfg, cut), "old closed report goes")
ok(not C.keep("reports", {status = "closed", closed_at = old, target_account = 0}, ctx, cfg, cut), "deleted character's report goes")
ok(C.keep("antibotLog", {created_at = old, account_id = 3}, ctx, cfg, cut), "banned account log kept")
ok(not C.keep("antibotLog", {created_at = old, account_id = 4}, ctx, cfg, cut), "old log goes")
ok(C.keep("antibotLog", {created_at = cut, account_id = 4}, ctx, cfg, cut), "the cutoff itself is kept")
ok(C.keep("antibotHolds", {id = 4, cleared_at = 0}, ctx, cfg, cut), "uncleared hold kept")
ok(C.keep("antibotHolds", {id = 4, cleared_at = cut + 1}, ctx, cfg, cut), "cleared recently kept")
ok(C.keep("antibotHolds", {id = 7, cleared_at = old}, ctx, cfg, cut), "banned account hold kept")
ok(not C.keep("antibotHolds", {id = 4, cleared_at = old}, ctx, cfg, cut), "old cleared hold goes")
ok(C.keep("adminLog", {created_at = old, action = "players.ban", target = "bad guy", status = "ok"}, ctx, cfg, cut), "ban line kept")
ok(C.keep("adminLog", {created_at = old, action = "players.info", target = "BAD GUY", status = "ok"}, ctx, cfg, cut), "any line on a banned character, any case")
ok(C.keep("adminLog", {created_at = old, action = "security.account_lookup", target = "7", status = "ok"}, ctx, cfg, cut), "lookup by account id")
ok(not C.keep("adminLog", {created_at = old, action = "players.kick", target = "Nobody", status = "ok"}, ctx, cfg, cut), "old line goes")
ok(not C.keep("adminLog", {created_at = old, action = "panel.access", target = "", status = "denied"}, ctx, cfg, cut), "no target goes")
local ipCtx = C.newContext({}, {}, {{banned_at = old + 30}})
ok(C.keep("adminLog", {created_at = old, action = "security.ip_ban", target = "", status = "ok"}, ipCtx, cfg, cut), "active ip ban line kept")
ok(not C.keep("adminLog", {created_at = old - 3600, action = "security.ip_ban", target = "", status = "ok"}, ipCtx, cfg, cut), "other ip ban line goes")
ok(not C.keep("adminLog", {created_at = old, action = "security.ip_ban", target = "", status = "fail"}, ipCtx, cfg, cut), "failed ip ban line goes")

local del, last, kept = C.split("antibotLog", {{id = 5, created_at = old, account_id = 1}, {id = 9, created_at = old, account_id = 3},
	{id = 8, created_at = old, account_id = 2}}, ctx, cfg, cut)
eq(#del, 2, "split deletes")
eq(last, 9, "split last id")
eq(kept, 1, "split kept")

-- ====================================================================== SQL
for _, k in ipairs(C.KINDS) do
	local q = C.candidateSql(cfg, k, cut, 10, 50)
	ok(q:find("`" .. cfg.tables[k] .. "`", 1, true) and q:find("LIMIT 50", 1, true) and q:find("> 10", 1, true), k .. " candidates")
	ok(q:find(tostring(cut), 1, true) ~= nil, k .. " cutoff in query")
end
ok(C.candidateSql(cfg, "reports", cut, 0, 5):find("LEFT JOIN `players`", 1, true) ~= nil, "report target account")
ok(C.candidateSql(cfg, "antibotHolds", cut, 0, 5):find("`cleared_at` > 0", 1, true) ~= nil, "uncleared holds never read")
eq(C.deleteSql(cfg, "antibotLog", {}), nil, "nothing to delete")
eq(C.deleteSql(cfg, "antibotLog", {1, 2}), "DELETE FROM `chaos_antibot_log` WHERE `id` IN (1,2)", "delete")
ok(C.deleteSql(cfg, "reports", {1}):find("`status` = 'closed'", 1, true) ~= nil, "a report reopened meanwhile stays")
ok(C.deleteSql(cfg, "antibotHolds", {4}):find("`account_id` IN (4) AND `cleared_at` > 0", 1, true) ~= nil, "holds by account")
ok(C.summary({reports = {deleted = 2, kept = 1}}):find("reports 2 deleted, 1 kept", 1, true) ~= nil, "summary")
ok(C.summary({}):find("adminLog off", 1, true) ~= nil, "summary off")

-- ====================================================================== engine (in-memory database)
local DB
local function resetDb()
	DB = {
		server_config = {},
		account_bans = {
			{account_id = 10, expires_at = NOW + 5 * DAY}, -- active
			{account_id = 11, expires_at = 0}, -- permanent
			{account_id = 12, expires_at = NOW - 10 * DAY}, -- expired 10 days ago, not moved yet: appeal window
			{account_id = 13, expires_at = NOW - 90 * DAY} -- long expired
		},
		account_ban_history = {{account_id = 14, expired_at = NOW - 3 * DAY}, {account_id = 15, expired_at = NOW - 200 * DAY}},
		ip_bans = {{banned_at = NOW - 800 * DAY, expires_at = NOW + DAY}},
		players = {{id = 100, account_id = 10, name = "Banned Ben"}, {id = 101, account_id = 1, name = "Clean Carl"},
			{id = 102, account_id = 14, name = "Appeal Amy"}, {id = 103, account_id = 15, name = "Old Olga"}},
		accounts = {{id = 10, name = "benacc"}, {id = 14, name = "amyacc"}},
		chaos_reports = {}, chaos_antibot_log = {}, chaos_antibot_holds = {}, chaos_admin_log = {}
	}
	local OLD, NEW = NOW - 800 * DAY, NOW - 10 * DAY
	local r = DB.chaos_reports
	r[#r + 1] = {id = 1, created_at = OLD, closed_at = OLD + DAY, status = "closed", target_id = 101} -- goes
	r[#r + 1] = {id = 2, created_at = OLD, closed_at = 0, status = "open", target_id = 101} -- open: kept
	r[#r + 1] = {id = 3, created_at = OLD, closed_at = OLD, status = "closed", target_id = 100} -- banned: kept
	r[#r + 1] = {id = 4, created_at = OLD, closed_at = NEW, status = "closed", target_id = 101} -- closed recently: kept
	r[#r + 1] = {id = 5, created_at = NEW, closed_at = NEW, status = "closed", target_id = 101} -- new: kept
	r[#r + 1] = {id = 6, created_at = OLD, closed_at = OLD, status = "closed", target_id = 102} -- appeal window: kept
	r[#r + 1] = {id = 7, created_at = OLD, closed_at = OLD, status = "closed", target_id = 103} -- ban long over: goes
	r[#r + 1] = {id = 8, created_at = OLD, closed_at = OLD, status = "closed", target_id = 999} -- character gone: goes
	for i = 1, 25 do -- batches (batch 4 in the test config)
		DB.chaos_antibot_log[#DB.chaos_antibot_log + 1] = {id = i, created_at = i <= 20 and OLD or NEW, account_id = (i % 5 == 0) and 11 or 1}
	end
	local h = DB.chaos_antibot_holds
	h[#h + 1] = {account_id = 1, created_at = OLD, cleared_at = OLD} -- goes
	h[#h + 1] = {account_id = 2, created_at = OLD, cleared_at = 0} -- open: kept
	h[#h + 1] = {account_id = 12, created_at = OLD, cleared_at = OLD} -- appeal window: kept
	h[#h + 1] = {account_id = 13, created_at = OLD, cleared_at = OLD} -- long expired ban: goes
	local a = DB.chaos_admin_log
	a[#a + 1] = {id = 1, created_at = OLD, action = "players.ban", target = "Banned Ben", status = "ok"} -- kept
	a[#a + 1] = {id = 2, created_at = OLD, action = "players.kick", target = "Clean Carl", status = "ok"} -- goes
	a[#a + 1] = {id = 3, created_at = OLD, action = "security.account_lookup", target = "amyacc", status = "ok"} -- kept
	a[#a + 1] = {id = 4, created_at = OLD, action = "security.ip_ban", target = "", status = "ok"} -- kept: active ip ban
	a[#a + 1] = {id = 5, created_at = NEW, action = "players.kick", target = "Clean Carl", status = "ok"} -- new: kept
	a[#a + 1] = {id = 6, created_at = OLD, action = "panel.access", target = "", status = "denied"} -- goes
end

local function rowsWhere(t, f)
	local out = {}
	for _, r in ipairs(DB[t]) do
		if f(r) then
			out[#out + 1] = r
		end
	end
	table.sort(out, function(x, y)
		return (x.id or x.account_id) < (y.id or y.account_id)
	end)
	return out
end

local queries = {}
local function run(q)
	queries[#queries + 1] = q
	local n
	if q:find("FROM `server_config`", 1, true) then
		local v = DB.server_config.chaos_moderation_purge
		return v and {{value = v}} or {}
	elseif q:find("FROM `account_bans`", 1, true) then
		local since = tonumber(q:match("`expires_at` > (%d+)"))
		local out, seen = {}, {}
		for _, r in ipairs(DB.account_bans) do
			if r.expires_at <= 0 or r.expires_at > since then
				out[#out + 1], seen[r.account_id] = {account_id = r.account_id}, true
			end
		end
		for _, r in ipairs(DB.account_ban_history) do
			if r.expired_at > since and not seen[r.account_id] then
				out[#out + 1] = {account_id = r.account_id}
			end
		end
		return out
	elseif q:find("FROM `ip_bans`", 1, true) then
		local since = tonumber(q:match("`expires_at` > (%d+)"))
		return rowsWhere("ip_bans", function(r) return r.expires_at <= 0 or r.expires_at > since end)
	elseif q:find("FROM `players` WHERE `account_id` IN", 1, true) then
		local set = {}
		for id in q:match("IN %(([%d,]+)%)"):gmatch("%d+") do
			set[tonumber(id)] = true
		end
		local out = {}
		for _, r in ipairs(DB.players) do
			if set[r.account_id] then out[#out + 1] = {name = r.name} end
		end
		for _, r in ipairs(DB.accounts) do
			if set[r.id] then out[#out + 1] = {name = r.name} end
		end
		return out
	elseif q:find("^SELECT r%.") then
		local after, cutoff, lim = q:match("r%.`id` > (%d+) AND r%.`created_at` < (%d+) ORDER BY r%.`id` LIMIT (%d+)")
		after, cutoff, lim = tonumber(after), tonumber(cutoff), tonumber(lim)
		local acc = {}
		for _, p in ipairs(DB.players) do acc[p.id] = p.account_id end
		local out = {}
		for _, r in ipairs(rowsWhere("chaos_reports", function(r) return r.id > after and r.created_at < cutoff end)) do
			if #out < lim then
				out[#out + 1] = {id = r.id, created_at = r.created_at, closed_at = r.closed_at, status = r.status, target_account = acc[r.target_id] or 0}
			end
		end
		return out
	elseif q:find("AS `id`, `created_at`, `cleared_at` FROM `chaos_antibot_holds`", 1, true) then
		local after, cutoff, lim = q:match("`account_id` > (%d+) AND `cleared_at` > 0 AND `cleared_at` < (%d+) ORDER BY `account_id` LIMIT (%d+)")
		after, cutoff, lim = tonumber(after), tonumber(cutoff), tonumber(lim)
		local out = {}
		for _, r in ipairs(rowsWhere("chaos_antibot_holds", function(r) return r.account_id > after and r.cleared_at > 0 and r.cleared_at < cutoff end)) do
			if #out < lim then out[#out + 1] = {id = r.account_id, created_at = r.created_at, cleared_at = r.cleared_at} end
		end
		return out
	elseif q:find("^SELECT `id`, `created_at`") then
		local t = q:match("FROM `([%w_]+)`")
		local after, cutoff, lim = q:match("`id` > (%d+) AND `created_at` < (%d+) ORDER BY `id` LIMIT (%d+)")
		after, cutoff, lim = tonumber(after), tonumber(cutoff), tonumber(lim)
		local out = {}
		for _, r in ipairs(rowsWhere(t, function(r) return r.id > after and r.created_at < cutoff end)) do
			if #out < lim then out[#out + 1] = r end
		end
		return out
	elseif q:find("^DELETE FROM") then
		local t, key, list = q:match("^DELETE FROM `([%w_]+)` WHERE `([%w_]+)` IN %(([%d,]+)%)")
		local set = {}
		for id in list:gmatch("%d+") do set[tonumber(id)] = true end
		local keep = {}
		n = 0
		for _, r in ipairs(DB[t]) do
			local hit = set[r[key]]
			if hit and q:find("`status` = 'closed'", 1, true) and r.status ~= "closed" then hit = false end
			if hit and q:find("`cleared_at` > 0", 1, true) and r.cleared_at <= 0 then hit = false end
			if hit then n = n + 1 else keep[#keep + 1] = r end
		end
		DB[t] = keep
		return true
	elseif q:find("^INSERT INTO `server_config`") then
		DB.server_config.chaos_moderation_purge = q:match("VALUES %('chaos_moderation_purge', '(%d+)'%)")
		return true
	end
	error("unexpected query: " .. q)
end

local cursor = {}
local nextId = 0
db = {
	escapeString = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end,
	query = function(q) return run(q) == true end,
	storeQuery = function(q)
		local rows = run(q)
		if type(rows) ~= "table" or #rows == 0 then return false end
		nextId = nextId + 1
		cursor[nextId] = {rows = rows, i = 1}
		return nextId
	end
}
result = {
	getNumber = function(id, col) local c = cursor[id]; return tonumber(c.rows[c.i][col]) or 0 end,
	getString = function(id, col) local c = cursor[id]; return tostring(c.rows[c.i][col] or "") end,
	next = function(id) local c = cursor[id]; c.i = c.i + 1; return c.rows[c.i] ~= nil end,
	free = function(id) cursor[id] = nil end
}
local registered = {}
function GlobalEvent(name)
	local o = {name = name}
	function o:interval(ms) o.ms = ms end
	function o:register() registered[name] = o end
	return o
end
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end

local MP = dofile("data/scripts/chaos/moderation_purge.lua")
print = realPrint
ok(registered.ChaosModerationPurge ~= nil, "globalevent registered")
eq(registered.ChaosModerationPurge.ms, cfg.checkSeconds * 1000, "checked every checkSeconds")
local ecfg = Chaos.moderationPurgeConfig
ecfg.batch = 4

local function ids(t, key)
	local out = {}
	for _, r in ipairs(DB[t]) do out[#out + 1] = r[key or "id"] end
	table.sort(out)
	return table.concat(out, ",")
end

resetDb()
print = function(s) printed[#printed + 1] = s end
ok(MP.tick(NOW), "first tick runs")
print = realPrint
eq(ids("chaos_reports"), "2,3,4,5,6", "reports: open, banned, closed recently, new, appeal window kept")
eq(ids("chaos_antibot_holds", "account_id"), "2,12", "holds: open and appeal window kept")
eq(ids("chaos_admin_log"), "1,3,4,5", "admin log: ban line, lookup of a protected account, active ip ban, new kept")
eq(ids("chaos_antibot_log"), "5,10,15,20,21,22,23,24,25", "anti-bot log over batches: banned account and new kept")
eq(DB.server_config.chaos_moderation_purge, tostring(NOW), "last run stored")
ok(printed[#printed]:find("reports 3 deleted", 1, true) ~= nil, "console summary: " .. tostring(printed[#printed]))
ok(printed[#printed]:find("accounts protected", 1, true) ~= nil, "protected count in the summary")

local before = #queries
ok(not MP.tick(NOW + 3600), "an hour later: not due")
eq(#queries - before, 1, "only the last-run read")

-- a day later: nothing new is old enough
print = function() end
ok(MP.tick(NOW + DAY), "a day later runs again")
eq(ids("chaos_reports"), "2,3,4,5,6", "nothing more")

-- 40 days later, account 12's ban (expired 10 days before NOW) is past the window: its hold goes
ok(MP.tick(NOW + 40 * DAY), "40 days later")
eq(ids("chaos_antibot_holds", "account_id"), "2", "appeal window over: the hold goes")
print = realPrint

-- a table at 0 days is left alone
resetDb()
ecfg.days.adminLog = 0
print = function() end
local counts = MP.run(NOW)
print = realPrint
eq(counts.adminLog, nil, "adminLog off")
eq(#DB.chaos_admin_log, 6, "admin log untouched")
eq(counts.reports.deleted, 3, "reports counted")
ecfg.days.adminLog = cfg.days.adminLog

-- a bad config deletes nothing
resetDb()
ecfg.days.reports = 3
print = function() end
eq(MP.run(NOW), nil, "bad config: no run")
print = realPrint
eq(#DB.chaos_reports, 8, "nothing deleted with a bad config")
ecfg.days.reports = cfg.days.reports

print(string.format("moderation_purge_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

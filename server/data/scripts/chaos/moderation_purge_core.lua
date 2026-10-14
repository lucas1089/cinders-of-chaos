-- Purge of old moderation records: pure logic (no engine calls). Engine file: moderation_purge.lua; numbers:
-- moderation_purge_config.lua; tests: tests/moderation_purge_test.lua; overview: server/README.md "Moderation record purge".
--
-- Once a day the engine file reads the accounts that must keep their records (an active ban, or one that ended less
-- than appealDays ago), the names that point at them, and the active IP bans. Then, per table, it reads old rows in id
-- order (C.candidateSql), keeps what C.keep says (open reports, uncleared holds, records of those accounts) and deletes
-- the rest by id (C.deleteSql). Reading by id keeps a kept row from stopping the run.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosModerationPurgeCore = ChaosModerationPurgeCore or {}
local C = ChaosModerationPurgeCore

C.DAY = 86400
C.KINDS = {"reports", "antibotLog", "antibotHolds", "adminLog"}
C.SERVER_CONFIG = "chaos_moderation_purge"
C.IP_BAN_ACTION = "security.ip_ban"

local function int(v)
	v = tonumber(v)
	if not v or v ~= v then
		return 0
	end
	return math.floor(v)
end

-- ok, err
function C.validate(cfg)
	if type(cfg) ~= "table" or type(cfg.days) ~= "table" or type(cfg.tables) ~= "table" then
		return false, "config needs days and tables"
	end
	for _, k in ipairs(C.KINDS) do
		local d = cfg.days[k]
		if type(d) ~= "number" or d < 0 or d ~= math.floor(d) then
			return false, "days." .. k .. " must be a whole number >= 0"
		end
		if d > 0 and d < 30 then
			return false, "days." .. k .. " under 30 leaves no time to review a case"
		end
		if type(cfg.tables[k]) ~= "string" or not cfg.tables[k]:match("^chaos_[%w_]+$") then
			return false, "tables." .. k .. " must be a chaos_* table"
		end
	end
	if type(cfg.appealDays) ~= "number" or cfg.appealDays < 0 then
		return false, "appealDays must be >= 0"
	end
	if int(cfg.batch) < 1 or int(cfg.maxBatches) < 1 then
		return false, "batch and maxBatches must be >= 1"
	end
	if int(cfg.runEverySeconds) < 3600 or int(cfg.checkSeconds) < 60 then
		return false, "runEverySeconds >= 3600, checkSeconds >= 60"
	end
	return true
end

-- a run is due when a full period passed since the last one (lastRun 0 or missing = never ran)
function C.due(lastRun, now, cfg)
	lastRun = int(lastRun)
	return cfg.enabled ~= false and (lastRun <= 0 or now - lastRun >= int(cfg.runEverySeconds) or lastRun > now)
end

-- rows older than this go (nil = this table is never purged)
function C.cutoff(cfg, kind, now)
	local d = int(cfg.days[kind])
	if d <= 0 then
		return nil
	end
	return now - d * C.DAY
end

-- a ban that ended after this time still protects its records
function C.appealSince(cfg, now)
	return now - int(cfg.appealDays) * C.DAY
end

-- ------------------------------------------------------------------ protected accounts
-- base tables: account_bans (expires_at 0 = permanent; an expired row stays until the account logs in again, so the
-- appeal window is applied to it too) and account_ban_history (expired_at)
function C.banSql(cfg, now)
	local since = C.appealSince(cfg, now)
	return string.format("SELECT `account_id` FROM `account_bans` WHERE `expires_at` <= 0 OR `expires_at` > %d "
		.. "UNION SELECT `account_id` FROM `account_ban_history` WHERE `expired_at` > %d", since, since)
end

function C.ipBanSql(cfg, now)
	return string.format("SELECT `banned_at` FROM `ip_bans` WHERE `expires_at` <= 0 OR `expires_at` > %d", C.appealSince(cfg, now))
end

local function idList(ids)
	local out = {}
	for _, id in ipairs(ids) do
		out[#out + 1] = string.format("%d", int(id))
	end
	return table.concat(out, ",")
end

-- the names that point at the protected accounts in the admin log (character names, account names); nil when none
function C.namesSql(accountIds)
	if #accountIds == 0 then
		return nil
	end
	local list = idList(accountIds)
	return string.format("SELECT `name` FROM `players` WHERE `account_id` IN (%s) UNION SELECT `name` FROM `accounts` WHERE `id` IN (%s)",
		list, list)
end

local function lower(s)
	return string.lower(tostring(s or "")):match("^%s*(.-)%s*$")
end

-- ctx from the rows the engine read: banRows {{account_id}}, nameRows {{name}}, ipBanRows {{banned_at}}
function C.newContext(banRows, nameRows, ipBanRows)
	local ctx = {accounts = {}, accountIds = {}, names = {}, ipBans = {}}
	for _, r in ipairs(banRows or {}) do
		local id = int(r.account_id)
		if id > 0 and not ctx.accounts[id] then
			ctx.accounts[id] = true
			ctx.accountIds[#ctx.accountIds + 1] = id
			ctx.names[tostring(id)] = true -- the admin panel's account lookup takes a numeric id too
		end
	end
	table.sort(ctx.accountIds)
	for _, r in ipairs(nameRows or {}) do
		local n = lower(r.name)
		if n ~= "" then
			ctx.names[n] = true
		end
	end
	for _, r in ipairs(ipBanRows or {}) do
		ctx.ipBans[#ctx.ipBans + 1] = int(r.banned_at)
	end
	return ctx
end

-- ------------------------------------------------------------------ candidates
-- columns of each candidate query, for Chaos.select
C.COLUMNS = {
	reports = {{"id", "n"}, {"created_at", "n"}, {"closed_at", "n"}, {"status", "s"}, {"target_account", "n"}},
	antibotLog = {{"id", "n"}, {"created_at", "n"}, {"account_id", "n"}},
	antibotHolds = {{"id", "n"}, {"created_at", "n"}, {"cleared_at", "n"}},
	adminLog = {{"id", "n"}, {"created_at", "n"}, {"action", "s"}, {"target", "s"}, {"status", "s"}}
}

-- old rows after afterId in id order (holds: the key is account_id)
function C.candidateSql(cfg, kind, cutoff, afterId, batch)
	local t = cfg.tables[kind]
	afterId, batch, cutoff = int(afterId), int(batch), int(cutoff)
	if kind == "reports" then
		return string.format("SELECT r.`id`, r.`created_at`, r.`closed_at`, r.`status`, COALESCE(p.`account_id`, 0) AS `target_account` "
			.. "FROM `%s` r LEFT JOIN `players` p ON p.`id` = r.`target_id` WHERE r.`id` > %d AND r.`created_at` < %d "
			.. "ORDER BY r.`id` LIMIT %d", t, afterId, cutoff, batch)
	elseif kind == "antibotLog" then
		return string.format("SELECT `id`, `created_at`, `account_id` FROM `%s` WHERE `id` > %d AND `created_at` < %d ORDER BY `id` LIMIT %d",
			t, afterId, cutoff, batch)
	elseif kind == "antibotHolds" then
		return string.format("SELECT `account_id` AS `id`, `created_at`, `cleared_at` FROM `%s` WHERE `account_id` > %d AND `cleared_at` > 0 "
			.. "AND `cleared_at` < %d ORDER BY `account_id` LIMIT %d", t, afterId, cutoff, batch)
	elseif kind == "adminLog" then
		return string.format("SELECT `id`, `created_at`, `action`, `target`, `status` FROM `%s` WHERE `id` > %d AND `created_at` < %d "
			.. "ORDER BY `id` LIMIT %d", t, afterId, cutoff, batch)
	end
	return nil
end

local function ipBanActive(ctx, at, cfg)
	local w = int(cfg.ipBanWindowSeconds)
	for _, b in ipairs(ctx.ipBans) do
		if math.abs(b - at) <= w then
			return true
		end
	end
	return false
end

-- keep?, why: the rules of moderation_purge_config.lua (open report, uncleared hold, a protected account, an active IP
-- ban); also a row that turns out newer than the cutoff
function C.keep(kind, row, ctx, cfg, cutoff)
	if kind == "reports" then
		if row.status ~= "closed" then
			return true, "open"
		end
		if int(row.closed_at) >= cutoff then
			return true, "closed recently"
		end
		if ctx.accounts[int(row.target_account)] then
			return true, "ban"
		end
		return false
	elseif kind == "antibotLog" then
		if int(row.created_at) >= cutoff then
			return true, "recent"
		end
		if ctx.accounts[int(row.account_id)] then
			return true, "ban"
		end
		return false
	elseif kind == "antibotHolds" then
		if int(row.cleared_at) <= 0 then
			return true, "open"
		end
		if int(row.cleared_at) >= cutoff then
			return true, "cleared recently"
		end
		if ctx.accounts[int(row.id)] then
			return true, "ban"
		end
		return false
	elseif kind == "adminLog" then
		if int(row.created_at) >= cutoff then
			return true, "recent"
		end
		local target = lower(row.target)
		if target ~= "" and ctx.names[target] then
			return true, "ban"
		end
		if row.action == C.IP_BAN_ACTION and row.status == "ok" and ipBanActive(ctx, int(row.created_at), cfg) then
			return true, "ip ban"
		end
		return false
	end
	return true, "unknown table"
end

-- deleteIds, lastId (the highest id read), kept
function C.split(kind, rows, ctx, cfg, cutoff)
	local del, last, kept = {}, 0, 0
	for _, r in ipairs(rows) do
		local id = int(r.id)
		if id > last then
			last = id
		end
		if C.keep(kind, r, ctx, cfg, cutoff) then
			kept = kept + 1
		else
			del[#del + 1] = id
		end
	end
	return del, last, kept
end

function C.deleteSql(cfg, kind, ids)
	if #ids == 0 then
		return nil
	end
	local key = kind == "antibotHolds" and "account_id" or "id"
	local extra = ""
	if kind == "reports" then
		extra = " AND `status` = 'closed'" -- reopened since it was read: kept
	elseif kind == "antibotHolds" then
		extra = " AND `cleared_at` > 0" -- held again since it was read: kept
	end
	return string.format("DELETE FROM `%s` WHERE `%s` IN (%s)%s", cfg.tables[kind], key, idList(ids), extra)
end

-- the console line after a run; counts = {kind = {deleted, kept}}
function C.summary(counts)
	local parts = {}
	for _, k in ipairs(C.KINDS) do
		local c = counts[k]
		if c then
			parts[#parts + 1] = string.format("%s %d deleted, %d kept", k, c.deleted or 0, c.kept or 0)
		else
			parts[#parts + 1] = k .. " off"
		end
	end
	return table.concat(parts, "; ")
end

return C

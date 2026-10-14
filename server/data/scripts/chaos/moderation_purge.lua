-- Purge of old moderation records: chaos_reports (player and bug reports), chaos_antibot_log, chaos_antibot_holds and
-- chaos_admin_log rows older than the days in moderation_purge_config.lua are deleted once a day. The Privacy Policy
-- promises this limit (docs/legal/privacy.*.md section 4, [PRAZO DOS REGISTROS DE MODERAÇÃO]).
-- Kept whatever their age: open reports, uncleared holds, every record about an account with an active ban or a ban that
-- ended less than appealDays ago (an appeal may still be open), the admin log line of an active IP ban.
-- Pure logic: moderation_purge_core.lua (tests/moderation_purge_test.lua); overview: server/README.md
-- "Moderation record purge". A globalevent looks every checkSeconds whether runEverySeconds passed since the last run
-- (server_config chaos_moderation_purge), so a daily restart neither skips nor repeats it.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosModerationPurgeCore then
	dofile("data/scripts/chaos/moderation_purge_core.lua")
end

Chaos.moderationPurgeConfig = dofile("data/scripts/chaos/moderation_purge_config.lua")
local cfg = Chaos.moderationPurgeConfig
local C = ChaosModerationPurgeCore
ChaosModerationPurge = ChaosModerationPurge or {}
local MP = ChaosModerationPurge

local function log(text)
	print("[Chaos moderation purge] " .. text)
end

local function sql(query, columns)
	return Chaos.select(query, columns)
end

local function esc(s)
	return db.escapeString(tostring(s))
end

function MP.lastRun()
	local r = sql(string.format("SELECT `value` FROM `server_config` WHERE `config` = %s", esc(C.SERVER_CONFIG)), {{"value", "s"}})[1]
	return r and tonumber(r.value) or 0
end

local function setLastRun(now)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE `value` = %s",
		esc(C.SERVER_CONFIG), esc(now), esc(now)))
end

-- the protected accounts, their names and the active IP bans
function MP.context(now)
	local bans = sql(C.banSql(cfg, now), {{"account_id", "n"}})
	local ipBans = sql(C.ipBanSql(cfg, now), {{"banned_at", "n"}})
	local q = C.namesSql(C.newContext(bans).accountIds)
	return C.newContext(bans, q and sql(q, {{"name", "s"}}) or {}, ipBans)
end

-- one table; returns {deleted, kept}
function MP.purgeTable(kind, ctx, now)
	local cutoff = C.cutoff(cfg, kind, now)
	if not cutoff then
		return nil
	end
	local out, after = {deleted = 0, kept = 0}, 0
	for _ = 1, cfg.maxBatches do
		local rows = sql(C.candidateSql(cfg, kind, cutoff, after, cfg.batch), C.COLUMNS[kind])
		if #rows == 0 then
			break
		end
		local del, last, kept = C.split(kind, rows, ctx, cfg, cutoff)
		out.kept = out.kept + kept
		local q = C.deleteSql(cfg, kind, del)
		if q then
			if db.query(q) then
				out.deleted = out.deleted + #del
			else
				log(kind .. ": delete failed (tried again next run)")
				break
			end
		end
		after = last
		if #rows < cfg.batch then
			break
		end
	end
	return out
end

-- the whole purge now; returns the counts per table
function MP.run(now)
	now = now or os.time()
	local ok, err = C.validate(cfg)
	if not ok then
		log("config: " .. err .. "; nothing deleted")
		return nil
	end
	local ctx = MP.context(now)
	local counts = {}
	for _, kind in ipairs(C.KINDS) do
		counts[kind] = MP.purgeTable(kind, ctx, now)
	end
	setLastRun(now)
	log(C.summary(counts) .. string.format(" (%d accounts protected by a ban)", #ctx.accountIds))
	return counts
end

-- runs MP.run when a day passed since the last run
function MP.tick(now)
	now = now or os.time()
	if not C.due(MP.lastRun(), now, cfg) then
		return false
	end
	MP.run(now)
	return true
end

local job = GlobalEvent("ChaosModerationPurge")
function job.onThink(interval)
	local ok, err = pcall(MP.tick)
	if not ok then
		log("error: " .. tostring(err))
	end
	return true
end
job:interval(cfg.checkSeconds * 1000)
job:register()

return MP

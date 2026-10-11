-- Run from the server/ folder: luajit tests/guildwar_test.lua (and lua5.3; CI runs both)
-- In-game guild wars: the pure rules (guildwar_core.lua) with the real guildwar_config.lua (terms, declaring and
-- answering, the anti-farming kill rules, the end and the escrow: every gold piece held is paid out or burnt as the
-- fee, never made), then guildwar.lua against a mocked engine and database: declare (the stake leaves the guild bank),
-- decline / expire (it comes back), accept (the other stake), kills (counted and refused ones), the frag limit, the
-- payout to the winner's bank, a surrender, the engine war list refresh, the opcode.
dofile("data/scripts/chaos/guildwar_core.lua")
local C = ChaosGuildWarCore
local cfg = dofile("data/scripts/chaos/guildwar_config.lua")

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end
local function copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = v
	end
	return o
end

-- ---------------------------------------------------------------- config sanity
ok(#cfg.fragLimits > 0 and #cfg.durations > 0, "terms offered")
ok(cfg.stake.feePercent > 0 and cfg.stake.feePercent < 100, "a fee between 0 and 100")
ok(cfg.rank >= 2 and cfg.stakeRank >= cfg.rank, "ranks")
ok(cfg.kills.minVictimLevel > 0 and cfg.kills.sameVictimMinutes > 0, "anti-farming numbers")

-- ---------------------------------------------------------------- terms
local t = C.terms({fragLimit = 25, hours = 24, stake = 0}, cfg)
eq(t.fragLimit, 25, "frag limit")
eq(t.hours, 24, "hours")
eq(t.stake, 0, "no stake")
t = C.terms({fragLimit = "50", hours = "72", stake = "250000"}, cfg)
eq(t.stake, 250000, "strings from the client")
eq(C.terms({fragLimit = 7, hours = 24, stake = 0}, cfg), nil, "a frag limit not offered")
eq(C.terms({fragLimit = 25, hours = 5, stake = 0}, cfg), nil, "a duration not offered")
eq(C.terms({fragLimit = 25, hours = 24, stake = cfg.stake.min - 1}, cfg), nil, "a stake under the minimum")
eq(C.terms({fragLimit = 25, hours = 24, stake = cfg.stake.max + 1}, cfg), nil, "a stake over the maximum")
eq(C.terms({fragLimit = 25, hours = 24, stake = -5}, cfg), nil, "a negative stake")
eq(C.terms({fragLimit = 25, hours = 24, stake = 0 / 0}, cfg), nil, "NaN")
eq(C.terms({fragLimit = 25, hours = 24, stake = math.huge}, cfg), nil, "infinite")
eq(C.terms(nil, cfg), nil, "nothing")

-- ---------------------------------------------------------------- declaring
local base = {enabled = true, guildId = 1, rank = 3, targetId = 2, targetExists = true, realm = 0, targetRealm = 0, members = 5,
	targetMembers = 5, wars = 0, targetWars = 0, pairBusy = false, pairCooldown = 0, sameOwner = false, stake = 0, bank = 0}
local function declare(over)
	local i = copy(base)
	for k, v in pairs(over or {}) do
		i[k] = v
	end
	return C.declareError(i, cfg)
end
eq(declare(), nil, "a leader declares")
eq(declare({rank = 2}), nil, "a vice-leader declares (no stake)")
ok(declare({rank = 1}), "a member cannot")
ok(declare({guildId = 0}), "no guild")
ok(declare({targetExists = false, targetId = nil}), "no such guild")
ok(declare({targetId = 1}), "not on itself")
ok(declare({targetRealm = 3}):find("realm"), "season realms: only within a realm")
eq(declare({realm = 3, targetRealm = 3}), nil, "two guilds of the same season realm")
ok(declare({sameOwner = true}):find("same account"), "guilds of one owner")
ok(declare({members = 2}), "too few members")
ok(declare({targetMembers = 2}), "the target has too few")
ok(declare({pairBusy = true}), "a war or offer between them")
ok(declare({pairCooldown = 3600}):find("1h 0m"), "pair cooldown")
ok(declare({wars = cfg.maxWars}), "own war limit")
ok(declare({targetWars = cfg.maxWars}), "target war limit")
ok(declare({sinceLastDeclare = 5}), "declare cooldown")
eq(declare({sinceLastDeclare = cfg.declareCooldown}), nil, "after the cooldown")
ok(declare({stake = 500000, rank = 2, bank = 10 ^ 9}):find("leader"), "a vice-leader cannot stake")
ok(declare({stake = 500000, bank = 400000}):find("400,000"), "a bank too small")
eq(declare({stake = 500000, bank = 500000}), nil, "a stake the bank holds")
ok(declare({stake = 500000, bank = 10 ^ 9, seasonBank = true}):find("Season"), "season characters: no bank")
ok(C.declareError(base, {enabled = false}), "closed")

-- ---------------------------------------------------------------- answering
local function pending(over)
	local w = {id = 7, guild1 = 1, guild2 = 2, name1 = "Ashen Wolves", name2 = "Iron Crows", realm = 0, fragLimit = 10, hours = 24,
		stake = 300000, status = "pending", expiresAt = 1000, escrow1 = 300000, escrow2 = 0, kills1 = 0, kills2 = 0}
	for k, v in pairs(over or {}) do
		w[k] = v
	end
	return w
end
local function answer(action, over, war)
	local i = {action = action, guildId = 2, rank = 3, war = war or pending(), bank = 10 ^ 9, wars = 1, now = 500}
	for k, v in pairs(over or {}) do
		i[k] = v
	end
	return C.answerError(i, cfg)
end
eq(answer("accept"), nil, "the other guild's leader accepts")
eq(answer("decline", {rank = 2}), nil, "a vice-leader declines")
ok(answer("accept", {rank = 2}):find("leader"), "a stake: only the leader accepts")
eq(answer("accept", {rank = 2}, pending({stake = 0, escrow1 = 0})), nil, "no stake: a vice-leader accepts")
ok(answer("accept", {bank = 1000}):find("1,000"), "the bank of the accepting guild")
ok(answer("accept", {guildId = 1}):find("other guild"), "the declarer cannot accept its own offer")
ok(answer("accept", {guildId = 9}), "a third guild")
ok(answer("accept", {rank = 1}), "a member")
ok(answer("accept", {now = 1000}):find("expired"), "an expired offer")
ok(answer("accept", nil, pending({status = "active"})), "not pending any more")
ok(answer("accept", {wars = cfg.maxWars + 1}), "the accepting guild is full")
ok(answer("accept", {seasonBank = true}):find("Season"), "season bank")
eq(answer("cancel", {guildId = 1}), nil, "the declarer takes it back")
ok(answer("cancel", {guildId = 2}), "the other guild cannot cancel")
ok(answer("surrender"), "no surrender of an offer")
eq(answer("surrender", nil, pending({status = "active"})), nil, "surrender of a running war")
eq(answer("surrender", {guildId = 1}, pending({status = "active"})), nil, "either side surrenders")
ok(C.answerError({action = "accept", guildId = 2, rank = 3}, cfg), "no war")
ok(answer("bogus"), "unknown action")

-- ---------------------------------------------------------------- the anti-farming kill rules
local war = pending({status = "active", startedAt = 0, endsAt = 100000})
local function kill(over)
	local k = {killerGuild = 1, victimGuild = 2, killerAccount = 11, victimAccount = 22, killerIp = 0x0100007f, victimIp = 0x0200007f,
		killerLevel = 400, victimLevel = 380, killerRealm = 0, victimRealm = 0, at = 5000, lastCounted = nil}
	for k2, v in pairs(over or {}) do
		k[k2] = v
	end
	return C.killVerdict(k, war, cfg)
end
local counted, why = kill()
eq(counted, true, "a fair kill counts")
eq(why, "ok", "reason ok")
counted, why = kill({killerGuild = 2, victimGuild = 1})
eq(counted, true, "the other side's kill counts too")
eq(select(2, kill({victimIp = 0x0100007f})), "same IP", "same IP")
eq(select(1, kill({killerIp = 0, victimIp = 0})), true, "no IP (0) is not the same IP")
eq(select(2, kill({victimAccount = 11})), "same account", "same account")
eq(select(2, kill({victimLevel = cfg.kills.minVictimLevel - 1, killerLevel = 50})), "low level", "under the minimum level")
eq(select(2, kill({victimLevel = 199, killerLevel = 400})), "low level", "under half the killer's level")
eq(select(1, kill({victimLevel = 200, killerLevel = 400})), true, "exactly half counts")
eq(select(2, kill({lastCounted = 5000 - 60})), "repeat", "the same victim a minute later")
eq(select(2, kill({lastCounted = 5000 - cfg.kills.sameVictimMinutes * 60 + 1})), "repeat", "one second short")
eq(select(1, kill({lastCounted = 5000 - cfg.kills.sameVictimMinutes * 60})), true, "after sameVictimMinutes")
eq(select(2, kill({victimRealm = 3})), "realm", "a victim of another realm")
eq(select(2, kill({killerRealm = 3})), "realm", "a killer of another realm")
eq(select(2, kill({killerGuild = 2, victimGuild = 2})), "no war", "same side")
eq(select(2, kill({killerGuild = 9})), "no war", "a third guild")
eq(select(2, kill({at = 100000})), "war over", "after the end")
eq(select(2, C.killVerdict({killerGuild = 1, victimGuild = 2}, pending(), cfg)), "no war", "an offer is no war")

-- the score and the frag limit
local w2 = pending({status = "active", fragLimit = 3, endsAt = 10 ^ 9, kills1 = 0, kills2 = 0})
eq(C.addKill(w2, 1), false, "1 : 0")
eq(C.addKill(w2, 2), false, "1 : 1")
eq(C.addKill(w2, 1), false, "2 : 1")
eq(C.addKill(w2, 1), true, "3 : 1 reaches the limit")
eq(C.addKill(w2, nil), false, "no side")
eq(C.scoreText(w2), "3 : 1", "score text")
eq(C.scoreText(w2, 2), "1 : 3", "score text of the other side")
eq((C.outcome(w2, "limit")), 1, "the declarer wins")
eq((C.outcome(w2, "surrender", 1)), 2, "a surrender: the other side wins whatever the score")
eq((C.outcome(w2, "disband", 2)), 1, "a disbanded guild loses")
eq((C.outcome(pending({kills1 = 4, kills2 = 4}), "time")), 0, "a tie at the time is a draw")
eq((C.outcome(pending({kills1 = 1, kills2 = 4}), "time")), 2, "more kills at the time")
ok(C.timeUp(pending({status = "active", endsAt = 50}), 50), "time up")
ok(not C.timeUp(pending({status = "active", endsAt = 50}), 49), "not yet")
ok(C.offerExpired(pending({expiresAt = 50}), 50), "offer expired")

-- ---------------------------------------------------------------- the escrow: nothing is made, the fee is burnt
for _, stake in ipairs({0, 100000, 333333, 500000000}) do
	for _, e2 in ipairs({0, stake}) do
		local wx = pending({status = "active", escrow1 = stake, escrow2 = e2})
		for side = 0, 2 do
			local p = C.settle(wx, side, cfg)
			eq(p.pay1 + p.pay2 + p.fee, stake + e2, "conservation " .. stake .. "/" .. e2 .. "/" .. side)
			ok(p.pay1 >= 0 and p.pay2 >= 0 and p.fee >= 0, "no negative payment")
			if side == 0 then
				eq(p.fee, 0, "a draw pays no fee")
				eq(p.pay1, stake, "a draw gives the stake back")
			else
				eq(p["pay" .. (3 - side)], 0, "the loser gets nothing")
				eq(p.fee, math.floor((stake + e2) * cfg.stake.feePercent / 100), "the fee")
			end
		end
		local r = C.refund(wx)
		eq(r.pay1 + r.pay2, stake + e2, "a refund gives everything back")
		eq(r.fee, 0, "no fee on a refund")
	end
end
local p = C.settle(pending({escrow1 = 1000000, escrow2 = 1000000}), 2, cfg)
eq(p.pay2, 1800000, "winner: 2,000,000 minus 10%")
eq(p.fee, 200000, "fee 200,000")

-- guild XP
eq(C.gxpOf(pending({kills1 = 8, kills2 = 2}), 1, "limit", cfg), cfg.gxp.win, "a won war gives guild XP")
eq(C.gxpOf(pending({kills1 = 8, kills2 = 2}), 1, "surrender", cfg), 0, "not for a surrender")
eq(C.gxpOf(pending({kills1 = 3, kills2 = 2}), 1, "time", cfg), 0, "not under minKills")
eq(C.gxpOf(pending({kills1 = 8, kills2 = 8}), 0, "time", cfg), 0, "not for a draw")

-- rows and texts
local row = C.row(pending(), 2, 400)
eq(row.own, "Iron Crows", "own name first")
eq(row.enemy, "Ashen Wolves", "the enemy")
eq(row.incoming, true, "incoming offer")
eq(row.left, 600, "time to answer")
ok(row.terms:find("300,000 gold at stake"), "terms text")
local ended = pending({status = "ended", winner = 2, reason = "limit", endedAt = 99, kills1 = 3, kills2 = 10, payout = 540000})
eq(C.row(ended, 2, 0).result, "won", "won")
eq(C.row(ended, 1, 0).result, "lost", "lost")
eq(C.row(pending({status = "ended", winner = 0, reason = "time"}), 1, 0).result, "draw", "draw")
eq(C.row(ended, 2, 0).score, "10 : 3", "own score first")
eq(C.row(ended, nil, 0).score, "3 : 10", "board: declarer first")
eq(C.row(pending({status = "declined"}), 1, 0).result, "declined", "declined")
eq(C.reasonText("limit"), "frag limit reached", "reason text")
eq(C.money(1234567), "1,234,567", "money")
eq(C.durationText(90061), "1d 1h", "duration")

-- ====================================================================== guildwar.lua against a mocked engine
-- a tiny database: the rows the script reads and writes, answered by query shape
local DB = {wars = {}, base = {}, kills = {}, nextId = 0, nextBase = 0, guilds = {}, members = {}, owners = {}, last = 0}
DB.guilds[1] = "Ashen Wolves"
DB.guilds[2] = "Iron Crows"
DB.guilds[3] = "Lone Guild"
DB.members = {[1] = 5, [2] = 4, [3] = 1}
DB.owners = {[1] = {guid = 101, account = 1, ip = 11}, [2] = {guid = 201, account = 2, ip = 22}, [3] = {guid = 301, account = 3, ip = 33}}
local rowCount = 0
local WARCOLS = {"id", "war_id", "guild1", "guild2", "name1", "name2", "realm", "frag_limit", "hours", "stake", "status",
	"declared_by", "declared_at", "expires_at", "started_at", "ends_at", "ended_at", "kills1", "kills2", "winner", "reason",
	"escrow1", "escrow2", "payout", "fee"}

local function unq(s)
	return (s:gsub("^'", ""):gsub("'$", ""):gsub("\\'", "'"))
end

local function sets(row, text)
	for col, val in text:gmatch("`([%w_]+)` = ([^,]+)") do
		val = val:gsub("^%s+", ""):gsub("%s+$", "")
		local inc = val:match("^`[%w_]+` %+ (%d+)$")
		if inc then
			row[col] = (row[col] or 0) + tonumber(inc)
		elseif val:match("^'") then
			row[col] = unq(val)
		else
			row[col] = tonumber(val) or val
		end
	end
end

db = {}
function db.escapeString(s)
	return "'" .. tostring(s):gsub("'", "\\'") .. "'"
end
function db.lastInsertId()
	return DB.last
end
function db.asyncQuery()
	return true
end
function db.query(q)
	rowCount = 0
	if q:find("CREATE TABLE") then
		return true
	end
	local cols, vals = q:match("^INSERT INTO `chaos_guildwar` %((.-)%) VALUES %((.*)%)$")
	if cols then
		DB.nextId = DB.nextId + 1
		local r = {id = DB.nextId, war_id = 0, started_at = 0, ends_at = 0, ended_at = 0, kills1 = 0, kills2 = 0, winner = 0, reason = "",
			escrow2 = 0, payout = 0, fee = 0}
		local names = {}
		for c in cols:gmatch("`([%w_]+)`") do
			names[#names + 1] = c
		end
		-- split values (strings have no commas in this test)
		local list = {}
		for v in vals:gmatch("[^,]+") do
			list[#list + 1] = v:gsub("^%s+", ""):gsub("%s+$", "")
		end
		for k, c in ipairs(names) do
			local v = list[k]
			r[c] = v:match("^'") and unq(v) or tonumber(v)
		end
		DB.wars[r.id] = r
		DB.last = r.id
		rowCount = 1
		return true
	end
	if q:find("^INSERT INTO `guild_wars`") then
		DB.nextBase = DB.nextBase + 1
		local g1, g2 = q:match("VALUES %((%d+), (%d+),")
		DB.base[DB.nextBase] = {id = DB.nextBase, guild1 = tonumber(g1), guild2 = tonumber(g2), status = 1, ended = 0}
		DB.last = DB.nextBase
		return true
	end
	if q:find("^INSERT INTO `chaos_guildwar_kills`") then
		local v = q:match("VALUES %((.*)%)$")
		local list = {}
		for x in v:gmatch("[^,]+") do
			list[#list + 1] = x:gsub("^%s+", ""):gsub("%s+$", "")
		end
		DB.kills[#DB.kills + 1] = {war_id = tonumber(list[1]), at = tonumber(list[2]), victim_id = tonumber(list[6]),
			counted = tonumber(list[10]), reason = unq(list[11])}
		return true
	end
	local set, id, status = q:match("^UPDATE `chaos_guildwar` SET (.*) WHERE `id` = (%d+) AND `status` = '(%w+)'$")
	if set then
		local r = DB.wars[tonumber(id)]
		if r and r.status == status then
			sets(r, set)
			rowCount = 1
		end
		return true
	end
	local base4, bid = q:match("^UPDATE `guild_wars` SET `status` = (%d+), `ended` = %d+ WHERE `id` = (%d+)")
	if base4 then
		DB.base[tonumber(bid)].status = tonumber(base4)
		return true
	end
	return true
end

result = {}
local function selectRows(q)
	if q:find("ROW_COUNT") then
		return {{n = rowCount}}
	end
	if q:find("FROM `chaos_guildwar` WHERE") or q:find("FROM `chaos_guildwar` $") then
		local out = {}
		local ids = {}
		for idv in pairs(DB.wars) do
			ids[#ids + 1] = idv
		end
		table.sort(ids)
		for _, idv in ipairs(ids) do
			local r = DB.wars[idv]
			local want = true
			if q:find("`status` IN %('pending', 'active'%)") then
				want = r.status == "pending" or r.status == "active"
			elseif q:find("`status` IN %('ended', 'declined'") then
				want = r.status ~= "pending" and r.status ~= "active"
			elseif q:find("WHERE `status` = 'ended'") then
				want = r.status == "ended"
			end
			local only = q:match("WHERE `id` = (%d+)")
			if only then
				want = r.id == tonumber(only)
			end
			if want then
				out[#out + 1] = r
			end
		end
		return out
	end
	local name = q:match("FROM `guilds` WHERE `name` = '(.-)' LIMIT 1")
	if name then
		for gid, n in pairs(DB.guilds) do
			if n:lower() == name:lower() then
				return {{id = gid, name = n}}
			end
		end
		return {}
	end
	local gid = q:match("^SELECT `id` FROM `guilds` WHERE `id` = (%d+)")
	if gid then
		return DB.guilds[tonumber(gid)] and {{id = tonumber(gid)}} or {}
	end
	gid = q:match("FROM `guild_membership` WHERE `guild_id` = (%d+)")
	if gid then
		return {{n = DB.members[tonumber(gid)] or 0}}
	end
	gid = q:match("LEFT JOIN `players` p ON p.`id` = g.`ownerid` WHERE g.`id` = (%d+)")
	if gid then
		local o = DB.owners[tonumber(gid)]
		return o and {o} or {}
	end
	if q:find("FROM `guild_wars` WHERE %(%(`guild1`") then
		return {}
	end
	if q:find("COALESCE%(MAX%(`ended_at`%)") then
		return {{t = 0}}
	end
	if q:find("information_schema") then
		return {{n = 0}}
	end
	gid = q:match("SELECT `guild1`, `guild2` FROM `guild_wars` WHERE %(`guild1` = (%d+)")
	if gid then
		gid = tonumber(gid)
		local out = {}
		for _, b in pairs(DB.base) do
			if b.status == 1 and (b.guild1 == gid or b.guild2 == gid) then
				out[#out + 1] = {guild1 = b.guild1, guild2 = b.guild2}
			end
		end
		return out
	end
	local bid = q:match("SELECT `status` FROM `guild_wars` WHERE `id` = (%d+)")
	if bid then
		local b = DB.base[tonumber(bid)]
		return b and {{status = b.status}} or {}
	end
	local wid, vid = q:match("FROM `chaos_guildwar_kills` WHERE `war_id` = (%d+) AND `victim_id` = (%d+) AND `counted` = 1")
	if wid then
		local tmax = 0
		for _, k in ipairs(DB.kills) do
			if k.war_id == tonumber(wid) and k.victim_id == tonumber(vid) and k.counted == 1 then
				tmax = math.max(tmax, k.at)
			end
		end
		return {{t = tmax}}
	end
	return {}
end

-- the engine
local NOW = 1791700000
os.time = (function(orig)
	return function(t)
		if t then
			return orig(t)
		end
		return NOW
	end
end)(os.time)
MESSAGE_INFO_DESCR, MESSAGE_STATUS_SMALL, MESSAGE_EVENT_ADVANCE = 1, 2, 3
local registry = {}
local function event(kind)
	return function(name)
		local e = {name = name}
		function e.register() registry[name or kind] = e end
		function e.interval() end
		function e.separator() end
		return e
	end
end
CreatureEvent = event("creature")
GlobalEvent = event("global")
TalkAction = event("talk")
json = {encode = function(t) return t end, decode = function(s) return s end}
local broadcast = {}
Game = {broadcastMessage = function(text) broadcast[#broadcast + 1] = text end, getPlayers = function() return {} end}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q, cols)
	return selectRows(q)
end
local sent = {}
Chaos.sendChunked = function(player, op, data)
	sent[#sent + 1] = {player = player, op = op, data = data}
	return true
end
Chaos.send = function(player, op, action, data)
	sent[#sent + 1] = {player = player, op = op, data = {action = action, data = data}}
	return true
end

-- the guild system's API (guild.lua) as the war script uses it: banks with conditional spends
local bank = {[1] = 2000000, [2] = 2000000, [3] = 0}
local logRows = {}
local players = {}
ChaosGuild = {
	exec = function(q)
		db.query(q)
		return rowCount
	end,
	spend = function(gid, n)
		if (bank[gid] or 0) < n then
			return false
		end
		bank[gid] = bank[gid] - n
		return true
	end,
	credit = function(gid, n)
		bank[gid] = (bank[gid] or 0) + n
		return true
	end,
	row = function(gid)
		return {bank = bank[gid] or 0, level = 5}
	end,
	logRow = function(gid, player, action, amount, a, b, text)
		logRows[#logRows + 1] = {gid = gid, action = action, amount = amount, text = text}
	end,
	tellGuild = function(gid, text) end,
	onlineMembers = function(gid)
		local out = {}
		for _, pl in ipairs(players) do
			if pl.gid == gid then
				out[#out + 1] = pl
			end
		end
		return out
	end,
	addStat = function() end,
	addXp = function() end,
	seasonBlocked = function() return nil end
}
function ChaosGuild.guildOf(player)
	if not player.gid then
		return nil
	end
	return player.gid, DB.guilds[player.gid], player.rank
end

local function newPlayer(id, guid, gid, rank, level, account, ip)
	local pl = {id = id, guid = guid, gid = gid, rank = rank, level = level, account = account, ip = ip, msgs = {}, warList = nil}
	function pl:getId() return self.id end
	function pl:getGuid() return self.guid end
	function pl:getName() return "P" .. self.guid end
	function pl:getLevel() return self.level end
	function pl:getAccountId() return self.account end
	function pl:getIp() return self.ip end
	function pl:isPlayer() return true end
	function pl:getPlayer() return self end
	function pl:getMaster() return nil end
	function pl:getGuild()
		if not self.gid then
			return nil
		end
		local g = self.gid
		return {getId = function() return g end}
	end
	function pl:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function pl:registerEvent() end
	function pl:setGuildWarList(list) self.warList = list end
	players[#players + 1] = pl
	return pl
end
local lead1 = newPlayer(1, 101, 1, 3, 500, 1, 11)
local lead2 = newPlayer(2, 201, 2, 3, 500, 2, 22)
local vice2 = newPlayer(3, 202, 2, 2, 450, 5, 55)
local mem1 = newPlayer(4, 102, 1, 1, 420, 6, 66)
local farm2 = newPlayer(5, 203, 2, 1, 120, 7, 66) -- same IP as mem1, low level
Player = setmetatable({setGuildWarList = function() end}, {__call = function(_, id)
	for _, pl in ipairs(players) do
		if pl.id == id then
			return pl
		end
	end
end})

dofile("data/scripts/chaos/guildwar.lua")
local W = ChaosGuildWar
W.load()

-- declare with a stake: the stake leaves the declarer's bank
local good, text = W.declare(lead1, {target = "iron crows", fragLimit = 10, hours = 24, stake = 500000})
eq(good, true, "declared: " .. tostring(text))
eq(bank[1], 1500000, "the stake is held")
local wid = DB.nextId
eq(DB.wars[wid].status, "pending", "pending")
eq(DB.wars[wid].escrow1, 500000, "escrow 1")
eq(W.declare(lead1, {target = "Iron Crows", fragLimit = 10, hours = 24, stake = 0}), false, "a second offer to the same guild")
eq(W.declare(lead1, {target = "Lone Guild", fragLimit = 10, hours = 24, stake = 0}), false, "a guild with too few members")
eq(W.declare(mem1, {target = "Lone Guild", fragLimit = 10, hours = 24, stake = 0}), false, "a member cannot declare")

-- the other side: a vice-leader cannot accept a stake, the leader can
eq(W.accept(vice2, wid), false, "vice-leader and a stake")
good, text = W.accept(lead2, wid)
eq(good, true, "accepted: " .. tostring(text))
eq(bank[2], 1500000, "the other stake is held")
eq(DB.wars[wid].status, "active", "active")
eq(DB.wars[wid].escrow2, 500000, "escrow 2")
ok(DB.wars[wid].war_id > 0, "a base war row")
eq(DB.base[DB.wars[wid].war_id].status, 1, "base war status 1 (the engine's war)")
eq(lead1.warList and lead1.warList[1], 2, "the declarer's members see guild 2 as enemy")
eq(vice2.warList and vice2.warList[1], 1, "the other side's members see guild 1")
eq(W.accept(lead2, wid), false, "accepted only once")
eq(bank[2], 1500000, "no second stake")

-- kills: counted, same IP, low level, the same victim again
local war = W.wars[wid]
W.onKill(lead2, lead1)
eq(war.kills1, 1, "a fair kill counts")
W.onKill(farm2, mem1)
eq(war.kills1, 1, "same IP and low level do not count")
eq(DB.kills[#DB.kills].reason, "same IP", "logged with the reason")
NOW = NOW + 60
W.onKill(lead2, mem1)
eq(war.kills1, 1, "the same victim within sameVictimMinutes")
eq(DB.kills[#DB.kills].reason, "repeat", "repeat logged")
NOW = NOW + cfg.kills.sameVictimMinutes * 60
W.onKill(lead2, mem1)
eq(war.kills1, 2, "the same victim later counts")
W.onKill(mem1, vice2)
eq(war.kills2, 1, "the other side scores")
eq(DB.wars[wid].kills1, 2, "score in the database")
-- reach the limit: 10 kills for guild 1 (new victims every 30 minutes)
for _ = 1, 8 do
	NOW = NOW + cfg.kills.sameVictimMinutes * 60
	W.onKill(lead2, lead1)
end
eq(DB.wars[wid].status, "ended", "ended by the frag limit")
eq(DB.wars[wid].winner, 1, "guild 1 won")
eq(DB.wars[wid].reason, "limit", "reason limit")
eq(bank[1], 1500000 + 900000, "the winner gets both stakes minus 10%")
eq(bank[2], 1500000, "the loser gets nothing back")
eq(DB.wars[wid].fee, 100000, "the fee is burnt")
eq(bank[1] + bank[2] + DB.wars[wid].fee, 4000000, "conservation over the whole war")
eq(DB.base[DB.wars[wid].war_id].status, 4, "the base war row ended (status 4)")
eq(#lead1.warList, 0, "the war list is empty again")
eq(W.wars[wid], nil, "no longer in memory")
ok(#broadcast >= 2, "start and end broadcast")
-- a kill after the end does nothing
W.onKill(lead2, lead1)
eq(DB.wars[wid].kills1, 10, "no kills after the end")

-- decline and expiry give the stake back; surrender pays the other side
NOW = NOW + cfg.pairCooldownHours * 3600
good = W.declare(lead2, {target = "Ashen Wolves", fragLimit = 25, hours = 6, stake = 200000})
local wid2 = DB.nextId
eq(good, true, "second declaration")
eq(bank[2], 1300000, "held")
eq(W.answer(lead1, "decline", wid2), true, "declined")
eq(bank[2], 1500000, "the stake came back")
eq(DB.wars[wid2].status, "declined", "declined status")
W.lastDeclare = {}
W.declare(lead2, {target = "Ashen Wolves", fragLimit = 25, hours = 6, stake = 200000})
local wid3 = DB.nextId
NOW = NOW + cfg.offerHours * 3600
W.think()
eq(DB.wars[wid3].status, "expired", "expired")
eq(bank[2], 1500000, "the stake came back after the expiry")
W.lastDeclare = {}
W.declare(lead1, {target = "Iron Crows", fragLimit = 25, hours = 6, stake = 100000})
local wid4 = DB.nextId
W.accept(lead2, wid4)
local before = bank[1] + bank[2]
eq(W.answer(lead2, "surrender", wid4), true, "surrender")
eq(DB.wars[wid4].winner, 1, "the other side wins a surrender")
eq(bank[1] + bank[2] + DB.wars[wid4].fee, before + 200000, "surrender conservation")
eq(DB.wars[wid4].fee, 20000, "fee of the surrender")
-- a war that runs out of time with a tie: both stakes back
W.lastDeclare = {}
NOW = NOW + cfg.pairCooldownHours * 3600
W.declare(lead1, {target = "Iron Crows", fragLimit = 25, hours = 6, stake = 100000})
local wid5 = DB.nextId
W.accept(lead2, wid5)
local b1, b2 = bank[1], bank[2]
NOW = NOW + 6 * 3600
W.think()
eq(DB.wars[wid5].status, "ended", "ended by the time")
eq(DB.wars[wid5].winner, 0, "a draw")
eq(bank[1], b1 + 100000, "draw: stake 1 back")
eq(bank[2], b2 + 100000, "draw: stake 2 back")

-- the opcode: open sends the state through sendChunked on 197
sent = {}
local incoming = {action = "open", data = {tab = "wars"}}
json.decode = function() return incoming end
registry.ChaosGuildWarOpcode.onExtendedOpcode(lead1, ChaosOpcodes.guildWar, '{"action":"open"}')
eq(sent[1] and sent[1].op, 197, "the state on opcode 197")
eq(sent[1].data.action, "state", "state action")
ok(#sent[1].data.data.wars.history >= 4, "history of the guild")
ok(#sent[1].data.data.board.history >= 3, "the server board")
eq(ChaosOpcodes.guildWar, 197, "opcode 197")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, ref in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	ok(ref ~= ChaosOpcodes.guildWar, "free in the reference server's list")
end

print(string.format("guildwar_test: %d checks OK", checks))

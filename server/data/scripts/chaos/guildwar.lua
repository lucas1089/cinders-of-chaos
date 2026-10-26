-- In-game guild wars: the leader or a vice-leader declares war from the client (game_guildwar, Social > Guild Wars):
-- target guild, frag limit, duration and an optional gold stake (escrowed from the guild bank); the other guild sees
-- the terms and accepts or declines in game. An accepted war is a row of the base server's `guild_wars` (status 1),
-- so the engine's war rules (no skull for war kills, the war emblems) work; our own rows (chaos_guildwar) hold the
-- terms, the stakes, the score and the history, and chaos_guildwar_kills every war kill with its verdict.
-- Settings: guildwar_config.lua (Chaos.guildWarConfig). Pure logic: guildwar_core.lua (tests/guildwar_test.lua).
-- Overview: server/README.md "Guild wars in game". The guild boss (guildboss.lua) shares the opcode and the window.
--
--   kills      a player killed by a player of the other side of an active war (the last hit, a summon's master, or
--              the most damage when the last hit was not a player) is a war kill; it counts unless the anti-farming
--              rules of guildwar_config.lua `kills` say no (same IP / account, low level victim, the same victim again
--              within sameVictimMinutes, another realm). Counted kills are the score.
--   the end    the frag limit (first side to reach it), the time (more counted kills wins, a tie is a draw) or a
--              surrender (the other side wins). A guild that disbands loses. The winner gets both stakes minus the
--              fee (a gold sink); a draw gives both stakes back. Every bank change is one conditional UPDATE (guild.lua
--              G.spend / G.credit) and every status change one conditional UPDATE of the war row checked with
--              ROW_COUNT(), so an end is paid once.
--   emblems    the engine loads a player's war list only at login. With engine patch 0020 (Player:setGuildWarList)
--              every online member of both guilds gets the new list at once (emblems and skull rules update in view);
--              without it the list changes at the next login, and the members are told so.
--   realms     while a season runs a guild belongs to the realm of its owner; wars only between guilds of one realm,
--              and kills count only between characters of that realm.
--
-- Protocol (JSON {action, data} on ChaosOpcodes.guildWar = 197, server -> client through Chaos.sendChunked):
--   client -> server  open {tab} | refresh {tab} | declare {target, fragLimit, hours, stake} | accept {id} |
--                     decline {id} | cancel {id} | surrender {id} | log {id} | boss* (guildboss.lua)
--   server -> client  state {open, tab, guild, options, wars {pending, active, history}, board {active, history}, boss}
--                     none {open, text} | message {ok, text} | log {id, title, lines}
-- Staff: /guildwar [list | end, <id> | expire, <id>]. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/guildwar_core.lua")
Chaos.guildWarConfig = dofile("data/scripts/chaos/guildwar_config.lua")

ChaosGuildWar = ChaosGuildWar or {}
local W = ChaosGuildWar
local C = ChaosGuildWarCore
local OPCODE = ChaosOpcodes.guildWar or 197

local function cfg()
	return Chaos.guildWarConfig
end

local function T()
	return cfg().tables
end

local function G()
	return ChaosGuild
end

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos guildwar] " .. text)
end
W.log = log

W.wars = W.wars or {} -- id -> war (pending and active only)
W.viewers = W.viewers or {} -- player id -> tab, the players with the window open (pushed on changes)
W.lastDeclare = W.lastDeclare or {} -- guild id -> os.time of its last declaration

-- ---------------------------------------------------------------- database
local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_guildwar` (`id` int(11) NOT NULL AUTO_INCREMENT, `war_id` int(11) NOT NULL DEFAULT 0,
	`guild1` int(11) NOT NULL, `guild2` int(11) NOT NULL, `name1` varchar(255) NOT NULL DEFAULT '',
	`name2` varchar(255) NOT NULL DEFAULT '', `realm` int(11) NOT NULL DEFAULT 0, `frag_limit` int(10) unsigned NOT NULL DEFAULT 0,
	`hours` int(10) unsigned NOT NULL DEFAULT 0, `stake` bigint(20) unsigned NOT NULL DEFAULT 0,
	`status` varchar(12) NOT NULL DEFAULT 'pending', `declared_by` int(11) NOT NULL DEFAULT 0,
	`declared_at` int(10) unsigned NOT NULL DEFAULT 0, `expires_at` int(10) unsigned NOT NULL DEFAULT 0,
	`started_at` int(10) unsigned NOT NULL DEFAULT 0, `ends_at` int(10) unsigned NOT NULL DEFAULT 0,
	`ended_at` int(10) unsigned NOT NULL DEFAULT 0, `kills1` int(10) unsigned NOT NULL DEFAULT 0,
	`kills2` int(10) unsigned NOT NULL DEFAULT 0, `winner` int(11) NOT NULL DEFAULT 0, `reason` varchar(12) NOT NULL DEFAULT '',
	`escrow1` bigint(20) unsigned NOT NULL DEFAULT 0, `escrow2` bigint(20) unsigned NOT NULL DEFAULT 0,
	`payout` bigint(20) unsigned NOT NULL DEFAULT 0, `fee` bigint(20) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
	KEY `chaos_guildwar_status` (`status`), KEY `chaos_guildwar_guild1` (`guild1`), KEY `chaos_guildwar_guild2` (`guild2`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guildwar_kills` (`id` int(11) NOT NULL AUTO_INCREMENT, `war_id` int(11) NOT NULL,
	`at` int(10) unsigned NOT NULL, `killer_id` int(11) NOT NULL DEFAULT 0, `killer_name` varchar(255) NOT NULL DEFAULT '',
	`killer_guild` int(11) NOT NULL DEFAULT 0, `victim_id` int(11) NOT NULL DEFAULT 0, `victim_name` varchar(255) NOT NULL DEFAULT '',
	`victim_guild` int(11) NOT NULL DEFAULT 0, `victim_level` int(10) unsigned NOT NULL DEFAULT 0,
	`counted` tinyint(1) unsigned NOT NULL DEFAULT 0, `reason` varchar(16) NOT NULL DEFAULT '', PRIMARY KEY (`id`),
	KEY `chaos_guildwar_kills_war` (`war_id`, `id`), KEY `chaos_guildwar_kills_victim` (`war_id`, `victim_id`, `counted`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

function W.ensureTables()
	for _, q in ipairs(SCHEMA) do
		db.query((q:gsub("%s+", " ")))
	end
end

local COLS = {{"id", "n"}, {"war_id", "n"}, {"guild1", "n"}, {"guild2", "n"}, {"name1", "s"}, {"name2", "s"}, {"realm", "n"},
	{"frag_limit", "n"}, {"hours", "n"}, {"stake", "n"}, {"status", "s"}, {"declared_by", "n"}, {"declared_at", "n"},
	{"expires_at", "n"}, {"started_at", "n"}, {"ends_at", "n"}, {"ended_at", "n"}, {"kills1", "n"}, {"kills2", "n"},
	{"winner", "n"}, {"reason", "s"}, {"escrow1", "n"}, {"escrow2", "n"}, {"payout", "n"}, {"fee", "n"}}
local SELECT = "SELECT `id`, `war_id`, `guild1`, `guild2`, `name1`, `name2`, `realm`, `frag_limit`, `hours`, `stake`, " ..
	"`status`, `declared_by`, `declared_at`, `expires_at`, `started_at`, `ends_at`, `ended_at`, `kills1`, `kills2`, `winner`, " ..
	"`reason`, `escrow1`, `escrow2`, `payout`, `fee` FROM `chaos_guildwar` "

local function fromRow(r)
	return {id = r.id, warId = r.war_id, guild1 = r.guild1, guild2 = r.guild2, name1 = r.name1, name2 = r.name2, realm = r.realm,
		fragLimit = r.frag_limit, hours = r.hours, stake = r.stake, status = r.status, declaredBy = r.declared_by,
		declaredAt = r.declared_at, expiresAt = r.expires_at, startedAt = r.started_at, endsAt = r.ends_at, endedAt = r.ended_at,
		kills1 = r.kills1, kills2 = r.kills2, winner = r.winner, reason = r.reason, escrow1 = r.escrow1, escrow2 = r.escrow2,
		payout = r.payout, fee = r.fee}
end

function W.query(where)
	local out = {}
	for _, r in ipairs(Chaos.select(SELECT .. where, COLS)) do
		out[#out + 1] = fromRow(r)
	end
	return out
end

function W.load()
	W.wars = {}
	for _, w in ipairs(W.query("WHERE `status` IN ('pending', 'active')")) do
		W.wars[w.id] = w
	end
	W.loaded = true
end

local function wars()
	if not W.loaded then
		W.load()
	end
	return W.wars
end

-- a status change pending/active -> new; true when this call made it (ROW_COUNT 1)
local function moveStatus(war, from, to, extra)
	local set = string.format("`status` = %s", db.escapeString(to))
	if extra and extra ~= "" then
		set = set .. ", " .. extra
	end
	return G().exec(string.format("UPDATE `%s` SET %s WHERE `id` = %d AND `status` = %s", T().wars, set, war.id,
		db.escapeString(from))) == 1
end

-- ---------------------------------------------------------------- guilds
local function guildByName(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" or #name > 60 then
		return nil
	end
	local r = Chaos.select("SELECT `id`, `name` FROM `guilds` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1",
		{{"id", "n"}, {"name", "s"}})[1]
	return r and r.id, r and r.name
end

local function guildExists(gid)
	return Chaos.select("SELECT `id` FROM `guilds` WHERE `id` = " .. math.floor(gid), {{"id", "n"}})[1] ~= nil
end

local function memberCount(gid)
	local r = Chaos.select("SELECT COUNT(*) AS `n` FROM `guild_membership` WHERE `guild_id` = " .. math.floor(gid), {{"n", "n"}})[1]
	return r and r.n or 0
end

-- owner: guid, account, last IP of a guild's owner (guilds.ownerid)
local function ownerOf(gid)
	local r = Chaos.select("SELECT g.`ownerid` AS `guid`, p.`account_id` AS `account`, p.`lastip` AS `ip` FROM `guilds` g " ..
		"LEFT JOIN `players` p ON p.`id` = g.`ownerid` WHERE g.`id` = " .. math.floor(gid), {{"guid", "n"}, {"account", "n"}, {"ip", "n"}})[1]
	return r
end

local function seasonOn()
	local S = ChaosSeason
	if not (S and S.current and S.realmOfGuid) then
		return false
	end
	local ok, season = pcall(S.current)
	return ok and season ~= nil
end

function W.realmOfGuid(guid)
	if not guid or guid == 0 or not seasonOn() then
		return 0
	end
	local ok, realm = pcall(ChaosSeason.realmOfGuid, guid)
	return ok and tonumber(realm) or 0
end

function W.realmOfPlayer(player)
	if not seasonOn() then
		return 0
	end
	local ok, realm = pcall(ChaosSeason.realmOf, player)
	return ok and tonumber(realm) or 0
end

-- a guild belongs to the realm of its owner
function W.realmOfGuild(gid)
	local o = ownerOf(gid)
	return W.realmOfGuid(o and o.guid or 0)
end

local function warsOf(gid)
	local n = 0
	for _, w in pairs(wars()) do
		if w.guild1 == gid or w.guild2 == gid then
			n = n + 1
		end
	end
	return n
end

local function pairOf(a, b)
	for _, w in pairs(wars()) do
		if (w.guild1 == a and w.guild2 == b) or (w.guild1 == b and w.guild2 == a) then
			return w
		end
	end
	return nil
end

-- a war of the base table between the pair that is not ours (declared on the website) also blocks a new one
local function basePairBusy(a, b)
	return Chaos.select(string.format("SELECT `id` FROM `guild_wars` WHERE ((`guild1` = %d AND `guild2` = %d) OR (`guild1` = %d AND " ..
		"`guild2` = %d)) AND `status` IN (0, 1) AND `ended` = 0 LIMIT 1", a, b, b, a), {{"id", "n"}})[1] ~= nil
end

local function pairCooldown(a, b)
	local r = Chaos.select(string.format("SELECT COALESCE(MAX(`ended_at`), 0) AS `t` FROM `%s` WHERE `status` = 'ended' AND " ..
		"((`guild1` = %d AND `guild2` = %d) OR (`guild1` = %d AND `guild2` = %d))", T().wars, a, b, b, a), {{"t", "n"}})[1]
	local t = r and r.t or 0
	if t <= 0 then
		return 0
	end
	return math.max(0, t + (cfg().pairCooldownHours or 0) * 3600 - now())
end

local function sameOwner(a, b)
	local oa, ob = ownerOf(a), ownerOf(b)
	if not oa or not ob then
		return false
	end
	if (oa.account or 0) ~= 0 and oa.account == ob.account then
		return true
	end
	return (oa.ip or 0) ~= 0 and oa.ip == ob.ip
end

-- a text in a language: the key is the English pattern (i18n_strings.lua)
local function L(lang, key, ...)
	return ChaosI18n.text(lang, key, ...)
end

-- text: English, a deferred text or a function(lang) -> text (G.tellGuild)
local function tellBoth(war, text)
	G().tellGuild(war.guild1, text)
	G().tellGuild(war.guild2, text)
end

local function notify(gid, title, text)
	for _, p in ipairs(G().onlineMembers(gid)) do
		if ChaosNotify and ChaosNotify.send then
			pcall(ChaosNotify.send, p, title, text)
		end
	end
end

-- ---------------------------------------------------------------- the engine's war list (emblems, skull rules)
-- the enemy guild ids of gid's active wars in the base table (what the engine loads at login)
function W.baseWarList(gid)
	local list = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `guild1`, `guild2` FROM `guild_wars` WHERE (`guild1` = %d OR `guild2` = %d) " ..
			"AND `ended` = 0 AND `status` = 1", gid, gid), {{"guild1", "n"}, {"guild2", "n"}})) do
		list[#list + 1] = r.guild1 == gid and r.guild2 or r.guild1
	end
	return list
end

-- push the war list to the online members of the guilds (engine patch 0020); false without the patch
function W.refreshWarLists(gids)
	local any = false
	for _, gid in ipairs(gids) do
		local list = W.baseWarList(gid)
		for _, p in ipairs(G().onlineMembers(gid)) do
			if p.setGuildWarList then
				p:setGuildWarList(list)
				any = true
			end
		end
	end
	return any or (Player and Player.setGuildWarList ~= nil)
end

-- ---------------------------------------------------------------- the window
local function rankOf(player)
	local _, _, rank = G().guildOf(player)
	return rank or 0
end

local function bankOf(gid)
	return G().row(gid).bank
end

local function seasonBank(player)
	return G().seasonBlocked and G().seasonBlocked(player) ~= nil
end

function W.historyOf(gid, limit)
	local where = gid and string.format("WHERE `status` IN ('ended', 'declined', 'cancelled', 'expired') AND (`guild1` = %d OR `guild2` = %d) ",
		gid, gid) or "WHERE `status` = 'ended' "
	return W.query(where .. "ORDER BY `ended_at` DESC, `id` DESC LIMIT " .. math.floor(limit or cfg().board.history))
end

function W.state(player, tab)
	local gid, gname, rank = G().guildOf(player)
	local t = now()
	local c = cfg()
	local data = {tab = tab or "wars",
		options = {fragLimits = c.fragLimits, durations = c.durations, stakeMin = c.stake.min, stakeMax = c.stake.max,
			fee = c.stake.feePercent, offerHours = c.offerHours, maxWars = c.maxWars, minVictimLevel = c.kills.minVictimLevel,
			sameVictimMinutes = c.kills.sameVictimMinutes, emblemsLive = Player ~= nil and Player.setGuildWarList ~= nil},
		wars = {pending = {}, active = {}, history = {}}, board = {active = {}, history = {}}}
	if gid then
		data.guild = {id = gid, name = gname, rank = rank, canDeclare = rank >= c.rank, canStake = rank >= c.stakeRank,
			bank = bankOf(gid), realm = W.realmOfGuild(gid), wars = warsOf(gid)}
	end
	local mine = {}
	for _, w in pairs(wars()) do
		mine[#mine + 1] = w
	end
	table.sort(mine, function(a, b)
		return a.id > b.id
	end)
	for _, w in ipairs(mine) do
		if gid and C.side(w, gid) then
			local row = C.row(w, gid, t, Chaos.lang(player))
			table.insert(w.status == "pending" and data.wars.pending or data.wars.active, row)
		end
		if w.status == "active" and #data.board.active < c.board.active then
			data.board.active[#data.board.active + 1] = C.row(w, nil, t, Chaos.lang(player))
		end
	end
	if gid then
		for _, w in ipairs(W.historyOf(gid, c.board.history)) do
			data.wars.history[#data.wars.history + 1] = C.row(w, gid, t, Chaos.lang(player))
		end
	end
	for _, w in ipairs(W.historyOf(nil, c.board.history)) do
		data.board.history[#data.board.history + 1] = C.row(w, nil, t, Chaos.lang(player))
	end
	if ChaosGuildBoss and ChaosGuildBoss.view then
		local ok, view = pcall(ChaosGuildBoss.view, player)
		if ok then
			data.boss = view
		else
			log("boss view failed: " .. tostring(view))
		end
	end
	return data
end

function W.sendState(player, open, tab)
	tab = tab or W.viewers[player:getId()] or "wars"
	local data = W.state(player, tab)
	data.open = open and true or false
	W.viewers[player:getId()] = tab
	if ChaosDisplayScale and ChaosDisplayScale.apply then -- the viewer's display scale: the guild boss damage board
		data = ChaosDisplayScale.apply("guildState", player, data)
	end
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = data}))
end

-- refresh the open windows of the members of these guilds (nil: everyone with the window open)
function W.push(gids)
	for pid, tab in pairs(W.viewers) do
		local p = Player(pid)
		if not p then
			W.viewers[pid] = nil
		else
			local gid = G().guildOf(p)
			local want = gids == nil
			for _, g in ipairs(gids or {}) do
				if g == gid then
					want = true
				end
			end
			if want then
				pcall(W.sendState, p, false, tab)
			end
		end
	end
end

function W.message(player, ok, text)
	if text and text ~= "" then
		text = Chaos.tx(player, text) -- the core's refusals are English
		player:sendTextMessage(ok and MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL, text)
		Chaos.send(player, OPCODE, "message", {ok = ok and true or false, text = text})
	end
end

-- ---------------------------------------------------------------- declaring and answering
function W.declare(player, data)
	local c = cfg()
	local gid, gname, rank = G().guildOf(player)
	local terms, why = C.terms(data, c)
	if not terms then
		return false, why
	end
	local tid, tname = guildByName(data.target)
	local info = {enabled = c.enabled, guildId = gid, rank = rank, targetId = tid, targetExists = tid ~= nil, stake = terms.stake}
	if gid and tid and tid ~= gid then
		info.realm = W.realmOfGuild(gid)
		info.targetRealm = W.realmOfGuild(tid)
		info.members, info.targetMembers = memberCount(gid), memberCount(tid)
		info.wars, info.targetWars = warsOf(gid), warsOf(tid)
		info.pairBusy = pairOf(gid, tid) ~= nil or basePairBusy(gid, tid)
		info.pairCooldown = pairCooldown(gid, tid)
		info.sameOwner = sameOwner(gid, tid)
		info.bank = bankOf(gid)
		info.seasonBank = seasonBank(player)
		info.sinceLastDeclare = W.lastDeclare[gid] and (now() - W.lastDeclare[gid]) or nil
	end
	why = C.declareError(info, c)
	if why then
		return false, why
	end
	if terms.stake > 0 and not G().spend(gid, terms.stake) then
		return false, string.format("The guild bank holds %s gold.", C.money(bankOf(gid)))
	end
	local t = now()
	local ok = db.query(string.format("INSERT INTO `%s` (`guild1`, `guild2`, `name1`, `name2`, `realm`, `frag_limit`, `hours`, `stake`, " ..
		"`status`, `declared_by`, `declared_at`, `expires_at`, `escrow1`) VALUES (%d, %d, %s, %s, %d, %d, %d, %d, 'pending', %d, %d, %d, %d)",
		T().wars, gid, tid, db.escapeString(gname), db.escapeString(tname), info.realm or 0, terms.fragLimit, terms.hours, terms.stake,
		player:getGuid(), t, t + c.offerHours * 3600, terms.stake))
	local id = ok and db.lastInsertId and db.lastInsertId() or 0
	if not ok or id == 0 then
		if terms.stake > 0 then
			G().credit(gid, terms.stake)
		end
		return false, "The declaration could not be saved."
	end
	local war = {id = id, warId = 0, guild1 = gid, guild2 = tid, name1 = gname, name2 = tname, realm = info.realm or 0,
		fragLimit = terms.fragLimit, hours = terms.hours, stake = terms.stake, status = "pending", declaredBy = player:getGuid(),
		declaredAt = t, expiresAt = t + c.offerHours * 3600, startedAt = 0, endsAt = 0, endedAt = 0, kills1 = 0, kills2 = 0,
		winner = 0, reason = "", escrow1 = terms.stake, escrow2 = 0, payout = 0, fee = 0}
	wars()[id] = war
	W.lastDeclare[gid] = t
	if terms.stake > 0 then
		G().logRow(gid, player, "war", terms.stake, 0, 0, string.format("stake of the war offer to %s (held)", tname))
	end
	G().tellGuild(gid, function(lang)
		return L(lang, "%s declared war on %s: %s. The offer is open for %d hours.", player:getName(), tname, C.termsText(war, lang),
			c.offerHours)
	end)
	G().tellGuild(tid, function(lang)
		return L(lang, "%s declares WAR on your guild: %s. Your leader or a vice-leader can accept or decline it (Social > Guild Wars) within %d hours.",
			gname, C.termsText(war, lang), c.offerHours)
	end)
	notify(tid, "War declared", string.format("%s declares war: %s.", gname, C.termsText(war)))
	log(string.format("%s (%d) offered war %d to %s (%d): %s", gname, gid, id, tname, tid, C.termsText(war)))
	W.push({gid, tid})
	return true, string.format("War declared on %s. They have %d hours to answer.", tname, c.offerHours)
end

-- a pending offer ends without a war: the declarer's stake goes back. status: declined | cancelled | expired
local function closeOffer(war, status, byName)
	if not moveStatus(war, "pending", status, string.format("`ended_at` = %d, `reason` = %s", now(), db.escapeString(status))) then
		return false
	end
	wars()[war.id] = nil
	war.status = status
	war.endedAt = now()
	local r = C.refund(war)
	local refunds = {{war.guild1, r.pay1}, {war.guild2, r.pay2}}
	for _, rf in ipairs(refunds) do
		if rf[2] > 0 then
			if guildExists(rf[1]) and G().credit(rf[1], rf[2]) then
				G().logRow(rf[1], nil, "war", rf[2], 0, 0, string.format("war stake returned (offer %s)", status))
			else
				log(string.format("war %d: %s gold of guild %d could not be returned (guild gone)", war.id, C.money(rf[2]), rf[1]))
			end
		end
	end
	tellBoth(war, function(lang)
		local what
		if status == "declined" then
			what = L(lang, "%s declined the war offered by %s%s.", war.name2, war.name1, byName and (" (" .. byName .. ")") or "")
		elseif status == "cancelled" then
			what = L(lang, "%s took back its war offer to %s.", war.name1, war.name2)
		else
			what = L(lang, "The war offer of %s to %s expired.", war.name1, war.name2)
		end
		return what .. ((war.escrow1 or 0) > 0 and L(lang, " The stake went back to the guild bank.") or "")
	end)
	log(string.format("war %d %s", war.id, status))
	W.push({war.guild1, war.guild2})
	return true
end
W.closeOffer = closeOffer

local function warOf(id)
	id = tonumber(id)
	return id and wars()[math.floor(id)] or nil
end

function W.accept(player, id)
	local c = cfg()
	local war = warOf(id)
	local gid, _, rank = G().guildOf(player)
	local why = C.answerError({action = "accept", guildId = gid, rank = rank, war = war, bank = gid and bankOf(gid),
		wars = gid and warsOf(gid), seasonBank = seasonBank(player), now = now()}, c)
	if why then
		return false, why
	end
	if not guildExists(war.guild1) then
		closeOffer(war, "cancelled")
		return false, "That guild does not exist any more."
	end
	if (war.realm or 0) ~= W.realmOfGuild(gid) then
		return false, "Wars are fought only within a realm."
	end
	if war.stake > 0 and not G().spend(gid, war.stake) then
		return false, string.format("Your guild bank holds %s gold.", C.money(bankOf(gid)))
	end
	local t = now()
	db.query(string.format("INSERT INTO `guild_wars` (`guild1`, `guild2`, `name1`, `name2`, `status`, `started`, `ended`) " ..
		"VALUES (%d, %d, %s, %s, 1, %d, 0)", war.guild1, war.guild2, db.escapeString(war.name1), db.escapeString(war.name2), t))
	local baseId = db.lastInsertId and db.lastInsertId() or 0
	local endsAt = t + war.hours * 3600
	if baseId == 0 or not moveStatus(war, "pending", "active", string.format("`war_id` = %d, `started_at` = %d, `ends_at` = %d, `escrow2` = %d",
			baseId, t, endsAt, war.stake)) then
		if baseId ~= 0 then
			db.query("DELETE FROM `guild_wars` WHERE `id` = " .. baseId)
		end
		if war.stake > 0 then
			G().credit(gid, war.stake)
		end
		return false, "The war could not be started."
	end
	-- the website's war page (if any) shows the frag limit from its own table
	if Chaos.select("SELECT COUNT(*) AS `n` FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'znote_guild_wars'",
			{{"n", "n"}})[1].n > 0 then
		db.query(string.format("INSERT IGNORE INTO `znote_guild_wars` (`id`, `limit`) VALUES (%d, %d)", baseId, war.fragLimit))
	end
	war.status, war.warId, war.startedAt, war.endsAt, war.escrow2 = "active", baseId, t, endsAt, war.stake
	if war.stake > 0 then
		G().logRow(gid, player, "war", war.stake, 0, 0, string.format("stake of the war with %s (held)", war.name1))
	end
	local live = W.refreshWarLists({war.guild1, war.guild2})
	tellBoth(war, function(lang)
		return L(lang, "WAR! %s and %s are at war: %s. Ends in %s.", war.name1, war.name2, C.termsText(war, lang),
			C.durationText(war.hours * 3600)) .. (live and "" or L(lang, " The war emblems show after your next login."))
	end)
	if c.broadcast then
		Chaos.broadcast(MESSAGE_EVENT_ADVANCE, function(lang)
			return L(lang, "%s and %s are now at war (%s).", war.name1, war.name2, C.termsText(war, lang))
		end)
	end
	log(string.format("war %d accepted by %s: base war %d", war.id, player:getName(), baseId))
	W.push(nil)
	return true, string.format("Your guild is at war with %s.", war.name1)
end

function W.answer(player, action, id)
	local war = warOf(id)
	local gid, _, rank = G().guildOf(player)
	local why = C.answerError({action = action, guildId = gid, rank = rank, war = war, now = now()}, cfg())
	if why then
		return false, why
	end
	local done, text
	if action == "decline" then
		done, text = closeOffer(war, "declined", player:getName()), "You declined the war."
	elseif action == "cancel" then
		done, text = closeOffer(war, "cancelled", player:getName()), "You took back the war offer."
	elseif action == "surrender" then
		done, text = W.finish(war, "surrender", C.side(war, gid), player:getName()), "Your guild surrendered."
	end
	if not done then
		return false, "That war changed in the meantime."
	end
	return true, text
end

-- ---------------------------------------------------------------- the end of a war
-- reason "limit" | "time" | "surrender" | "disband" | "staff" | "external"; loserSide for surrender / disband
function W.finish(war, reason, loserSide, byName)
	local c = cfg()
	local side = C.outcome(war, reason, loserSide)
	local winner = side == 1 and war.guild1 or side == 2 and war.guild2 or 0
	local pay = C.settle(war, side, c)
	local t = now()
	if not moveStatus(war, "active", "ended", string.format("`ended_at` = %d, `winner` = %d, `reason` = %s, `payout` = %d, `fee` = %d, " ..
			"`kills1` = %d, `kills2` = %d", t, winner, db.escapeString(reason), pay.pay1 + pay.pay2, pay.fee, war.kills1 or 0, war.kills2 or 0)) then
		wars()[war.id] = nil
		return false
	end
	wars()[war.id] = nil
	war.status, war.endedAt, war.winner, war.reason, war.payout, war.fee = "ended", t, winner, reason, pay.pay1 + pay.pay2, pay.fee
	if (war.warId or 0) > 0 then
		db.query(string.format("UPDATE `guild_wars` SET `status` = 4, `ended` = %d WHERE `id` = %d AND `status` = 1", t, war.warId))
	end
	for i, gid in ipairs({war.guild1, war.guild2}) do
		local amount = pay["pay" .. i]
		if amount > 0 then
			if guildExists(gid) and G().credit(gid, amount) then
				G().logRow(gid, nil, "war", amount, 0, 0, string.format("war with %s: %s", i == 1 and war.name2 or war.name1,
					side == 0 and "stake returned (draw)" or "both stakes won, minus the fee"))
			else
				log(string.format("war %d: %s gold for guild %d lost (guild gone)", war.id, C.money(amount), gid))
			end
		end
	end
	if pay.fee > 0 then
		log(string.format("war %d: fee %s gold (sink)", war.id, C.money(pay.fee)))
	end
	for _, gid in ipairs({war.guild1, war.guild2}) do
		if guildExists(gid) then
			pcall(G().addStat, gid, "wars", 1)
		end
	end
	if winner ~= 0 and guildExists(winner) then
		pcall(G().addStat, winner, "warWins", 1)
		local gxp = C.gxpOf(war, side, reason, c)
		if gxp > 0 then
			pcall(G().addXp, winner, 0, "war", gxp, true)
		end
	end
	W.refreshWarLists({war.guild1, war.guild2})
	local function result(lang)
		local text
		if side == 0 then
			text = L(lang, "The war between %s and %s ended in a draw (%s, %s).", war.name1, war.name2, C.scoreText(war),
				C.reasonText(reason, lang))
		elseif reason == "surrender" then
			text = L(lang, "%s surrendered%s: %s wins the war (%s).", side == 1 and war.name2 or war.name1,
				byName and (" (" .. byName .. ")") or "", side == 1 and war.name1 or war.name2, C.scoreText(war))
		else
			text = L(lang, "%s won the war against %s (%s, %s).", side == 1 and war.name1 or war.name2,
				side == 1 and war.name2 or war.name1, C.scoreText(war, winner), C.reasonText(reason, lang))
		end
		if pay.pay1 + pay.pay2 > 0 and side ~= 0 then
			text = text .. L(lang, " %s gold goes to the winner's guild bank.", C.money(pay.pay1 + pay.pay2))
		end
		return text
	end
	tellBoth(war, result)
	if c.broadcast then
		Chaos.broadcast(MESSAGE_EVENT_ADVANCE, result)
	end
	log(string.format("war %d ended: %s", war.id, result("en")))
	W.push(nil)
	return true
end

-- ---------------------------------------------------------------- kills
local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

local function lastCounted(war, victimGuid)
	local r = Chaos.select(string.format("SELECT COALESCE(MAX(`at`), 0) AS `t` FROM `%s` WHERE `war_id` = %d AND `victim_id` = %d AND `counted` = 1",
		T().kills, war.id, victimGuid), {{"t", "n"}})[1]
	return r and r.t > 0 and r.t or nil
end

function W.onKill(victim, killer)
	local vg, kg = victim:getGuild(), killer:getGuild()
	if not vg or not kg or vg:getId() == kg:getId() then
		return
	end
	local war = pairOf(vg:getId(), kg:getId())
	if not war or war.status ~= "active" then
		return
	end
	local t = now()
	local k = {killerGuild = kg:getId(), victimGuild = vg:getId(), killerAccount = killer:getAccountId(),
		victimAccount = victim:getAccountId(), killerIp = killer:getIp(), victimIp = victim:getIp(), killerLevel = killer:getLevel(),
		victimLevel = victim:getLevel(), killerRealm = W.realmOfPlayer(killer), victimRealm = W.realmOfPlayer(victim), at = t,
		lastCounted = lastCounted(war, victim:getGuid())}
	local counted, reason = C.killVerdict(k, war, cfg())
	db.query(string.format("INSERT INTO `%s` (`war_id`, `at`, `killer_id`, `killer_name`, `killer_guild`, `victim_id`, `victim_name`, " ..
		"`victim_guild`, `victim_level`, `counted`, `reason`) VALUES (%d, %d, %d, %s, %d, %d, %s, %d, %d, %d, %s)", T().kills, war.id, t,
		killer:getGuid(), db.escapeString(killer:getName()), k.killerGuild, victim:getGuid(), db.escapeString(victim:getName()),
		k.victimGuild, k.victimLevel, counted and 1 or 0, db.escapeString(reason)))
	if reason == "war over" then
		return
	end
	local side = C.side(war, k.killerGuild)
	local done = false
	if counted then
		done = C.addKill(war, side)
		db.query(string.format("UPDATE `%s` SET `kills%d` = `kills%d` + 1 WHERE `id` = %d AND `status` = 'active'", T().wars, side, side, war.id))
	end
	tellBoth(war, function(lang)
		return L(lang, "War %s - %s: %s killed %s%s. Score %s : %s.", war.name1, war.name2, killer:getName(), victim:getName(),
			counted and "" or L(lang, " (not counted: %s)", ChaosI18n.translate(lang, reason)), war.kills1, war.kills2)
	end)
	if done then
		W.finish(war, "limit")
	else
		W.push({war.guild1, war.guild2})
	end
end

local death = CreatureEvent("ChaosGuildWarDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local victim = creature and creature:getPlayer()
	if not victim then
		return true
	end
	local k = playerOf(killer) or playerOf(mostDamageKiller)
	if k and k ~= victim then
		local ok, err = pcall(W.onKill, victim, k)
		if not ok then
			log("war kill failed: " .. tostring(err))
		end
	end
	return true
end
death:register()

-- ---------------------------------------------------------------- the clock
function W.think()
	local t = now()
	local list = {}
	for _, w in pairs(wars()) do
		list[#list + 1] = w
	end
	for _, w in ipairs(list) do
		local g1, g2 = guildExists(w.guild1), guildExists(w.guild2)
		if w.status == "pending" then
			if not g1 or not g2 then
				closeOffer(w, "cancelled")
			elseif C.offerExpired(w, t) then
				closeOffer(w, "expired")
			end
		elseif w.status == "active" then
			if not g1 or not g2 then
				W.finish(w, "disband", (not g1 and g2) and 1 or ((g1 and not g2) and 2 or nil))
			elseif C.timeUp(w, t) then
				W.finish(w, "time")
			elseif (w.warId or 0) > 0 then
				local base = Chaos.select("SELECT `status` FROM `guild_wars` WHERE `id` = " .. w.warId, {{"status", "n"}})[1]
				if not base or base.status ~= 1 then
					W.finish(w, "external")
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- protocol
local function limited(player, key, ms)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, key, ms or 1000)
end

local function warLog(player, id)
	id = tonumber(id) and math.floor(tonumber(id)) or 0
	local war = W.query("WHERE `id` = " .. id)[1]
	if not war then
		return
	end
	local lines = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `at`, `killer_name`, `victim_name`, `victim_level`, `counted`, `reason` FROM `%s` " ..
			"WHERE `war_id` = %d ORDER BY `id` DESC LIMIT %d", T().kills, id, cfg().board.log),
			{{"at", "n"}, {"killer_name", "s"}, {"victim_name", "s"}, {"victim_level", "n"}, {"counted", "n"}, {"reason", "s"}})) do
		lines[#lines + 1] = {at = os.date("%d.%m %H:%M", r.at), killer = r.killer_name, victim = r.victim_name, level = r.victim_level,
			counted = r.counted == 1, reason = r.reason}
	end
	Chaos.sendChunked(player, OPCODE, json.encode({action = "log", data = {id = id, title = war.name1 .. " vs " .. war.name2,
		score = C.scoreText(war), lines = lines}}))
end

local function handle(player, action, data)
	local ok, text
	local tab = type(data.tab) == "string" and data.tab:sub(1, 16) or nil
	if action == "open" or action == "refresh" then
		if limited(player, "guildwar.state", 300) then
			return
		end
		W.sendState(player, action == "open", tab)
		return
	elseif action == "close" then
		W.viewers[player:getId()] = nil
		return
	elseif action == "log" then
		if not limited(player, "guildwar.log", 500) then
			warLog(player, data.id)
		end
		return
	elseif action:sub(1, 4) == "boss" then
		if ChaosGuildBoss and ChaosGuildBoss.handle then
			local refused
			ok, text, refused = ChaosGuildBoss.handle(player, action, data)
			if refused then
				W.message(player, false, text)
				return
			end
		else
			return
		end
	elseif limited(player, "guildwar.act", 1000) then
		W.message(player, false, Chaos.t(player, "Slow down."))
		return
	elseif action == "declare" then
		ok, text = W.declare(player, data)
	elseif action == "accept" then
		ok, text = W.accept(player, data.id)
	elseif action == "decline" or action == "cancel" or action == "surrender" then
		ok, text = W.answer(player, action, data.id)
	else
		return
	end
	if ok == nil and text == nil then
		return
	end
	W.message(player, ok, text)
	W.sendState(player, false, tab)
end
W.handle = handle

local ext = CreatureEvent("ChaosGuildWarOpcode")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	local ok, err = pcall(handle, player, msg.action:sub(1, 24), type(msg.data) == "table" and msg.data or {})
	if not ok then
		log("request " .. msg.action .. " failed: " .. tostring(err))
	end
end
ext:register()

local login = CreatureEvent("ChaosGuildWarLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGuildWarOpcode")
	player:registerEvent("ChaosGuildWarDeath")
	player:registerEvent("ChaosGuildWarLogout")
	local gid, _, rank = G().guildOf(player)
	if gid and rank >= cfg().rank then
		for _, w in pairs(wars()) do
			if w.status == "pending" and w.guild2 == gid then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s declared war on your guild (%s). Answer it in Social > Guild Wars before it expires in %s.", w.name1, C.termsText(w, Chaos.lang(player)), C.durationText(w.expiresAt - now())))
			end
		end
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosGuildWarLogout")
function logout.onLogout(player)
	W.viewers[player:getId()] = nil
	return true
end
logout:register()

-- ---------------------------------------------------------------- staff
local function onStaff(player, param)
	local args = {}
	for a in (param or ""):gmatch("[^,]+") do
		args[#args + 1] = a:gsub("^%s+", ""):gsub("%s+$", "")
	end
	local cmd = (args[1] or ""):lower()
	local war = warOf(args[2])
	if cmd == "end" and war and war.status == "active" then
		W.finish(war, "staff")
		player:sendTextMessage(MESSAGE_INFO_DESCR, "War " .. war.id .. " ended.")
	elseif cmd == "expire" and war and war.status == "pending" then
		closeOffer(war, "expired")
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Offer " .. war.id .. " expired.")
	elseif cmd == "time" and war and war.status == "active" then
		war.endsAt = now()
		W.think()
	else
		local lines = {}
		for _, w in pairs(wars()) do
			lines[#lines + 1] = string.format("%d: %s vs %s, %s, %s, %s, base war %d", w.id, w.name1, w.name2, w.status, C.scoreText(w),
				C.termsText(w), w.warId or 0)
		end
		player:showTextDialog(2847, #lines > 0 and table.concat(lines, "\n") or "No war offers or wars.")
	end
end

local staff = TalkAction("/guildwar")
function staff.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	onStaff(player, param)
	return false
end
staff:separator(" ")
staff:register()

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosGuildWarStartup")
function startup.onStartup()
	W.ensureTables()
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `at` < %d", T().kills, now() - cfg().board.keepDays * 86400))
	W.load()
	local n = 0
	for _ in pairs(W.wars) do
		n = n + 1
	end
	log(string.format("%d war offer(s) and war(s) loaded", n))
	return true
end
startup:register()

local think = GlobalEvent("ChaosGuildWarThink")
function think.onThink(interval)
	local ok, err = pcall(W.think)
	if not ok then
		log("think failed: " .. tostring(err))
	end
	return true
end
think:interval(cfg().thinkSeconds * 1000)
think:register()

-- tables also when the file is reloaded on a running server
if db and db.query then
	pcall(W.ensureTables)
end

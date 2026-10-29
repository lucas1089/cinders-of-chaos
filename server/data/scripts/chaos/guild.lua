-- Guild levels: guild XP from what the members already do, levels 1-20, perks for online members, the guild bank,
-- the contribution log, the weekly "Top guild" board and the Guild window (client game_guild, extended opcode
-- ChaosOpcodes.guild = 252). The guild hall (instance, upgrades, rent, depot) is guild_hall.lua.
-- Settings: guild_config.lua (Chaos.guildConfig). Pure logic: guild_core.lua (tests/guild_test.lua).
-- Overview: server/README.md "Guild levels and guild halls".
--
-- Guild XP sources
--   experience        an onGainExperience callback: 1% of a member's monster experience in "level units", capped per
--                     member and day (batched in memory, written every minute and at logout)
--   bounty, rift, worldboss, siege, goblin, invasion*   a wrapper around ChaosLeaderboard.record (like seasons), so
--                     those scripts need no change; the guild of an offline player is read from guild_membership
--   siege results     once a minute, new rows of chaos_siege_results (winner / other guilds)
-- Perks (online members): experience (own onGainExperience), loot (wraps ChaosLootConfig.rateMult), cheaper respec
--   (wraps ChaosRespec.fullCost / nodeCost), depot slots, the daily guild hall scroll, the guild aura, the hall.
-- Money: every gold change of the guild bank is one conditional UPDATE checked with ROW_COUNT() (never a read, then a
--   write), logged in chaos_guild_log and on the console; requests are rate limited per player.
-- API for other scripts: ChaosGuild.levelOf(guildId), ChaosGuild.perksOf(guildId), ChaosGuild.addXp(...).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.guild:
--   client -> server  open {tab?} | refresh | deposit {amount} | withdraw {amount} | buyHall {from} | upgrade {key} |
--                     payRent | take {id} | scroll
--   server -> client  state {open, tab, guild, perks, members, hall, depot, log, top} | none {open, text}
--                     message {text, ok} | openModule {name}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/guild_core.lua")

Chaos.guildConfig = dofile("data/scripts/chaos/guild_config.lua")
local cfg = Chaos.guildConfig
ChaosGuild = ChaosGuild or {}
local G = ChaosGuild
local C = ChaosGuildCore
local T = cfg.tables
local OPCODE = ChaosOpcodes.guild or 252

G.cache = G.cache or {} -- guildId -> {xp, level, bank}
G.names = G.names or {} -- guildId -> name
G.day = G.day or {} -- guid -> {day, exp, all, carry}
G.pendingExp = G.pendingExp or {} -- guildId -> {[guid] = gxp}

local function log(text)
	print("[Chaos guild] " .. text)
end
G.log = log

local function now()
	return os.time()
end

local function weekNow()
	return C.weekKey(now(), cfg.week.resetHour)
end

-- ---------------------------------------------------------------- database
-- run a write and return the rows it changed (ROW_COUNT() of the same connection, right after the statement)
function G.exec(query)
	if not db.query(query) then
		return 0
	end
	local rows = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_guild` (`guild_id` int(11) NOT NULL, `xp` bigint(20) unsigned NOT NULL DEFAULT 0,
	`level` smallint(5) unsigned NOT NULL DEFAULT 1, `bank` bigint(20) unsigned NOT NULL DEFAULT 0,
	`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`guild_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guild_contrib` (`guild_id` int(11) NOT NULL, `player_id` int(11) NOT NULL,
	`week` int(10) unsigned NOT NULL, `day` int(10) unsigned NOT NULL, `source` varchar(24) NOT NULL,
	`amount` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`guild_id`, `player_id`, `week`, `day`, `source`),
	KEY `chaos_guild_contrib_week` (`week`, `guild_id`), KEY `chaos_guild_contrib_player` (`player_id`, `day`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guild_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `guild_id` int(11) NOT NULL,
	`at` int(10) unsigned NOT NULL, `player_id` int(11) NOT NULL DEFAULT 0, `player_name` varchar(64) NOT NULL DEFAULT '',
	`action` varchar(16) NOT NULL, `amount` bigint(20) NOT NULL DEFAULT 0, `item_id` int(11) NOT NULL DEFAULT 0,
	`count` int(11) NOT NULL DEFAULT 0, `text` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`),
	KEY `chaos_guild_log_guild` (`guild_id`, `id`), KEY `chaos_guild_log_at` (`at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guild_stats` (`guild_id` int(11) NOT NULL, `stat` varchar(24) NOT NULL,
	`value` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`guild_id`, `stat`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guild_hall` (`guild_id` int(11) NOT NULL, `slot` smallint(5) unsigned NOT NULL,
	`bought_at` int(10) unsigned NOT NULL, `paid_until` int(10) unsigned NOT NULL, PRIMARY KEY (`guild_id`),
	UNIQUE KEY `chaos_guild_hall_slot` (`slot`), CONSTRAINT `chaos_guild_hall_guilds_fk` FOREIGN KEY (`guild_id`)
	REFERENCES `guilds` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guild_upgrades` (`guild_id` int(11) NOT NULL, `upgrade` varchar(16) NOT NULL,
	`tier` tinyint(3) unsigned NOT NULL DEFAULT 0, `bought_at` int(10) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`guild_id`, `upgrade`), CONSTRAINT `chaos_guild_upgrades_guilds_fk` FOREIGN KEY (`guild_id`)
	REFERENCES `guilds` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guild_depot` (`id` int(11) NOT NULL AUTO_INCREMENT, `guild_id` int(11) NOT NULL,
	`item_id` int(11) NOT NULL, `count` int(11) NOT NULL DEFAULT 1, `name` varchar(255) NOT NULL DEFAULT '',
	`attrs` text NOT NULL, `added_by` int(11) NOT NULL DEFAULT 0, `added_at` int(10) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`id`), KEY `chaos_guild_depot_guild` (`guild_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

function G.ensureTables()
	for _, q in ipairs(SCHEMA) do
		db.query((q:gsub("%s+", " ")))
	end
end

-- staff-visible log row (and the console for money)
function G.logRow(gid, player, action, amount, itemId, count, text)
	local pid, pname = 0, ""
	if type(player) == "userdata" then
		pid, pname = player:getGuid(), player:getName()
	elseif type(player) == "table" then
		pid, pname = player.guid or 0, player.name or ""
	end
	db.query(string.format("INSERT INTO `%s` (`guild_id`, `at`, `player_id`, `player_name`, `action`, `amount`, `item_id`, `count`, `text`) " ..
		"VALUES (%d, %d, %d, %s, %s, %d, %d, %d, %s)", T.log, gid, now(), pid, db.escapeString(pname), db.escapeString(action),
		amount or 0, itemId or 0, count or 0, db.escapeString((text or ""):sub(1, 255))))
	if amount and amount ~= 0 then
		log(string.format("guild %d (%s): %s %s gold by %s%s", gid, G.nameOf(gid), action, C.money(amount),
			pname ~= "" and pname or "the server", text and text ~= "" and (" - " .. text) or ""))
	end
end

-- ---------------------------------------------------------------- guilds
function G.nameOf(gid)
	if not G.names[gid] then
		local g = Guild and Guild(gid)
		if g then
			G.names[gid] = g:getName()
		else
			local rows = Chaos.select("SELECT `name` FROM `guilds` WHERE `id` = " .. gid, {{"name", "s"}})
			G.names[gid] = rows[1] and rows[1].name or ("guild " .. gid)
		end
	end
	return G.names[gid]
end

-- the cached row of a guild (created when missing)
function G.row(gid)
	local r = G.cache[gid]
	if r then
		return r
	end
	local rows = Chaos.select(string.format("SELECT `xp`, `bank` FROM `%s` WHERE `guild_id` = %d", T.guilds, gid),
		{{"xp", "n"}, {"bank", "n"}})
	if not rows[1] then
		db.query(string.format("INSERT IGNORE INTO `%s` (`guild_id`, `xp`, `level`, `bank`, `updated_at`) VALUES (%d, 0, 1, 0, %d)",
			T.guilds, gid, now()))
		rows[1] = {xp = 0, bank = 0}
	end
	r = {xp = rows[1].xp, bank = rows[1].bank}
	r.level = C.levelOf(r.xp, cfg)
	G.cache[gid] = r
	return r
end

function G.levelOf(gid)
	gid = tonumber(gid)
	if not gid or gid <= 0 then
		return 0
	end
	return G.row(gid).level
end

function G.perksOf(gid)
	if not gid then
		return C.perksAt(0, cfg)
	end
	return C.perksAt(G.levelOf(gid), cfg)
end

function G.guildOf(player)
	local g = player and player:getGuild()
	if not g then
		return nil
	end
	G.names[g:getId()] = g:getName()
	return g:getId(), g:getName(), player:getGuildLevel()
end

-- guild of a player id (online or not)
function G.guildOfGuid(guid)
	local p = Player(guid)
	if p then
		return (G.guildOf(p))
	end
	local rows = Chaos.select("SELECT `guild_id` FROM `guild_membership` WHERE `player_id` = " .. guid, {{"guild_id", "n"}})
	return rows[1] and rows[1].guild_id or nil
end

function G.onlineMembers(gid)
	local list = {}
	for _, p in ipairs(Game.getPlayers()) do
		local g = p:getGuild()
		if g and g:getId() == gid then
			list[#list + 1] = p
		end
	end
	return list
end

function G.tellGuild(gid, text, msgType)
	for _, p in ipairs(G.onlineMembers(gid)) do
		-- each member reads their language: `text` is English (or a deferred text), or a function(lang) -> text
		p:sendTextMessage(msgType or MESSAGE_EVENT_ADVANCE, type(text) == "function" and text(Chaos.lang(p)) or Chaos.tx(p, text))
	end
end

local function seasonBlocked(player)
	local S = ChaosSeason
	if S and S.current and S.realmOf and S.current() and player:getGroup():getAccess() == false then
		local ok, realm = pcall(S.realmOf, player)
		if ok and realm and realm ~= 0 then
			return "Season characters cannot use the guild bank or stash while the season runs."
		end
	end
	return nil
end
G.seasonBlocked = seasonBlocked

-- ---------------------------------------------------------------- guild XP
-- today's use of the daily caps of a member (loaded from the contribution log once per day)
local function dayOf(guid)
	local today = Chaos.dayKey()
	local d = G.day[guid]
	if d and d.day == today then
		return d
	end
	d = {day = today, exp = 0, all = 0, carry = d and d.carry or 0}
	for _, r in ipairs(Chaos.select(string.format("SELECT `source`, SUM(`amount`) AS `n` FROM `%s` WHERE `player_id` = %d AND `day` = %d GROUP BY `source`",
			T.contrib, guid, today), {{"source", "s"}, {"n", "n"}})) do
		d.all = d.all + r.n
		if r.source == "exp" then
			d.exp = d.exp + r.n
		end
	end
	G.day[guid] = d
	return d
end

local function levelUp(gid, from, to)
	local name = G.nameOf(gid)
	G.logRow(gid, nil, "level", 0, 0, to, string.format("level %d -> %d", from, to))
	local perks = {}
	for _, step in ipairs(cfg.perks) do
		if step.level > from and step.level <= to then
			perks[#perks + 1] = C.perkText(step)
		end
	end
	local text = string.format("Your guild %s reached guild level %d!%s", name, to,
		#perks > 0 and (" New: " .. table.concat(perks, "; ") .. ".") or "")
	G.tellGuild(gid, text)
	for _, p in ipairs(G.onlineMembers(gid)) do
		if ChaosNotify and ChaosNotify.send then
			pcall(ChaosNotify.send, p, Chaos.t(p, "Guild level %d", to), Chaos.tx(p, text))
		end
		G.applyAura(p)
		G.sendState(p, false)
	end
	log(string.format("%s (%d) reached guild level %d", name, gid, to))
	if G.onLevelUp then
		pcall(G.onLevelUp, gid, to)
	end
end

-- add guild XP for a member (guid 0 = the guild itself). source is a contribution key. Daily caps apply to members.
-- Returns the GXP really added.
function G.addXp(gid, guid, source, amount, uncapped)
	gid, guid = tonumber(gid), tonumber(guid) or 0
	amount = math.floor(tonumber(amount) or 0)
	if not gid or gid <= 0 or amount <= 0 then
		return 0
	end
	if guid > 0 and not uncapped then
		local d = dayOf(guid)
		amount = C.capAmount(amount, d.all, cfg.sources.dailyCapAll)
		if amount <= 0 then
			return 0
		end
		d.all = d.all + amount
	end
	local r = G.row(gid)
	local before = r.level
	r.xp = r.xp + amount
	r.level = C.levelOf(r.xp, cfg)
	db.query(string.format("UPDATE `%s` SET `xp` = `xp` + %d, `level` = %d, `updated_at` = %d WHERE `guild_id` = %d",
		T.guilds, amount, r.level, now(), gid))
	db.query(string.format("INSERT INTO `%s` (`guild_id`, `player_id`, `week`, `day`, `source`, `amount`) VALUES (%d, %d, %d, %d, %s, %d) " ..
		"ON DUPLICATE KEY UPDATE `amount` = `amount` + %d", T.contrib, gid, guid, weekNow(), Chaos.dayKey(),
		db.escapeString(source:sub(1, 24)), amount, amount))
	G.topCache = nil
	if r.level > before then
		levelUp(gid, before, r.level)
	end
	return amount
end

-- experience share: in memory, written by G.flushExp (every minute, at logout)
function G.expGain(player, gid, exp)
	local guid = player:getGuid()
	local d = dayOf(guid)
	local pend = G.pendingExp[gid] and G.pendingExp[gid][guid] or 0
	local gxp, carry = C.expShare(exp, player:getLevel(), d.carry, d.exp + pend, cfg)
	d.carry = carry
	if gxp > 0 then
		G.pendingExp[gid] = G.pendingExp[gid] or {}
		G.pendingExp[gid][guid] = pend + gxp
	end
end

function G.flushExp(onlyGuid)
	for gid, members in pairs(G.pendingExp) do
		for guid, amount in pairs(members) do
			if not onlyGuid or onlyGuid == guid then
				members[guid] = nil
				local d = dayOf(guid)
				local added = G.addXp(gid, guid, "exp", amount)
				d.exp = d.exp + added
			end
		end
		if next(members) == nil then
			G.pendingExp[gid] = nil
		end
	end
end

function G.addStat(gid, stat, value, mode)
	value = math.floor(tonumber(value) or 0)
	local expr = mode == "max" and string.format("GREATEST(`value`, %d)", value) or string.format("`value` + %d", value)
	db.query(string.format("INSERT INTO `%s` (`guild_id`, `stat`, `value`) VALUES (%d, %s, %d) ON DUPLICATE KEY UPDATE `value` = %s",
		T.stats, gid, db.escapeString(stat), value, expr))
end

function G.statsOf(gid)
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `stat`, `value` FROM `%s` WHERE `guild_id` = %d", T.stats, gid),
			{{"stat", "s"}, {"value", "n"}})) do
		out[r.stat] = r.value
	end
	return out
end

-- one ChaosLeaderboard.record call -> guild XP and trophy counters for the player's guild
function G.onRecord(board, who, value)
	local amount = C.boardAmount(board, value, cfg)
	if not amount then
		return
	end
	local guid
	if type(who) == "userdata" then
		guid = who:getGuid()
	elseif type(who) == "table" then
		guid = tonumber(who.guid)
	else
		guid = tonumber(who)
	end
	if not guid then
		return
	end
	local gid = G.guildOfGuid(guid)
	if not gid then
		return
	end
	local def = C.boardDef(board, cfg)
	local stat = def and def.stat or board
	G.addStat(gid, stat, 1)
	if board == "rift" then
		G.addStat(gid, "riftBest", value, "max")
	end
	G.addXp(gid, guid, stat, amount)
end

-- hook ChaosLeaderboard.record (again after a /reload of leaderboard.lua) through ChaosWrapChain: one hook per
-- call, also with season, mentor and records hooking it; nested record calls give no guild XP (outer only).
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end
function G.wrapLeaderboard()
	ChaosWrapChain.wrap(ChaosLeaderboard, "record", "guild", function(res, board, who, value)
		G.onRecord(board, who, value)
	end, function(e) log("guild XP failed: " .. e) end, {outer = true})
end

-- new siege results -> guild XP for every guild that fought (once per row)
function G.checkSiegeResults()
	local key = "chaos_guild_siege_seen"
	local seen = Chaos.select("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key), {{"value", "s"}})
	if G.siegeTable == nil then
		G.siegeTable = (Chaos.select("SELECT COUNT(*) AS `n` FROM information_schema.tables WHERE table_schema = DATABASE() " ..
			"AND table_name = 'chaos_siege_results'", {{"n", "n"}})[1] or {n = 0}).n > 0
	end
	if not G.siegeTable then
		return
	end
	local maxRow = Chaos.select("SELECT COALESCE(MAX(`id`), 0) AS `n` FROM `chaos_siege_results`", {{"n", "n"}})[1]
	if not maxRow then
		return
	end
	if not seen[1] then
		-- first run: earlier sieges give nothing
		db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, '%d')", db.escapeString(key), maxRow.n))
		return
	end
	local last = tonumber(seen[1].value) or 0
	if maxRow.n <= last then
		return
	end
	local rows = Chaos.select(string.format("SELECT `id`, `guild_id`, `winner` FROM `chaos_siege_results` WHERE `id` > %d ORDER BY `id`", last),
		{{"id", "n"}, {"guild_id", "n"}, {"winner", "n"}})
	db.query(string.format("UPDATE `server_config` SET `value` = '%d' WHERE `config` = %s", maxRow.n, db.escapeString(key)))
	local sr = cfg.sources.siegeResult
	for _, r in ipairs(rows) do
		if r.guild_id > 0 and Chaos.select("SELECT `id` FROM `guilds` WHERE `id` = " .. r.guild_id, {{"id", "n"}})[1] then
			G.addStat(r.guild_id, "sieges", 1)
			if r.winner == 1 then
				G.addStat(r.guild_id, "siegeWins", 1)
			end
			G.addXp(r.guild_id, 0, "siegeResult", r.winner == 1 and sr.winner or sr.others, true)
		end
	end
end

-- ---------------------------------------------------------------- perk hooks
-- loot: ChaosLootConfig.rateMult x (1 + loot perk of the corpse owner's guild)
function G.wrapLoot()
	local LC = ChaosLootConfig
	if not LC or LC.rateMult == G.lootWrapped then
		return
	end
	local original = LC.rateMult
	G.lootWrapped = function(ctx)
		local base = original
		if type(original) == "function" then
			base = original(ctx)
		end
		base = tonumber(base) or 1
		local p = ctx and ctx.player
		if type(p) == "userdata" then
			local gid = G.guildOf(p)
			if gid then
				local loot = G.perksOf(gid).loot
				if loot > 0 then
					return base * (1 + loot / 100)
				end
			end
		end
		return base
	end
	LC.rateMult = G.lootWrapped
end

-- respec: the respec prices x (1 - respec perk)
function G.wrapRespec()
	local R = ChaosRespec
	if not R or not R.fullCost or R.fullCost == G.respecFull then
		return
	end
	local function discount(player, cost)
		local gid = G.guildOf(player)
		if not gid or (cost or 0) <= 0 then
			return cost
		end
		local off = G.perksOf(gid).respec
		return off > 0 and math.floor(cost * (100 - off) / 100) or cost
	end
	local full, node = R.fullCost, R.nodeCost
	G.respecFull = function(player, kind)
		return discount(player, full(player, kind))
	end
	R.fullCost = G.respecFull
	if node then
		R.nodeCost = function(player)
			return discount(player, node(player))
		end
	end
end

function G.applyAura(player)
	local gid = G.guildOf(player)
	local id = cfg.aura and cfg.aura.id
	if not id or not player.addAura then
		return
	end
	local has = player:getStorageValue(cfg.storage.auraOn) == 1
	local want = gid and G.perksOf(gid).aura or false
	if want and not has then
		player:addAura(id)
		player:setStorageValue(cfg.storage.auraOn, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your guild's aura is yours to wear while you are in the guild (outfit window)."))
	elseif not want and has then
		local bought = Chaos.storage.shopAuraBase and player:getStorageValue(Chaos.storage.shopAuraBase + id) == 1
		if not bought and player.removeAura then
			player:removeAura(id)
		end
		player:setStorageValue(cfg.storage.auraOn, 0)
	end
end

local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	if not source or not source.isMonster or not source:isMonster() or (exp or 0) <= 0 then
		return exp
	end
	local gid = G.guildOf(player)
	if not gid then
		return exp
	end
	local ok, err = pcall(G.expGain, player, gid, exp)
	if not ok then
		log("experience share failed: " .. tostring(err))
	end
	local bonus = G.perksOf(gid).xp
	if bonus > 0 then
		return math.floor(exp * (1 + bonus / 100))
	end
	return exp
end
xp:register()

-- ---------------------------------------------------------------- guild bank
local function limited(player, key, ms)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, key, ms or 1000)
end

-- take gold from the guild bank: one conditional UPDATE. Returns true when it was taken.
function G.spend(gid, amount)
	amount = math.floor(amount)
	if amount <= 0 then
		return true
	end
	G.row(gid) -- cached before the debit: a row read after it already holds the new bank, and the subtraction below would count twice
	local n = G.exec(string.format("UPDATE `%s` SET `bank` = `bank` - %d, `updated_at` = %d WHERE `guild_id` = %d AND `bank` >= %d",
		T.guilds, amount, now(), gid, amount))
	if n == 1 then
		local r = G.row(gid)
		r.bank = math.max(0, r.bank - amount)
		return true
	end
	G.cache[gid] = nil -- re-read: the cache was wrong
	return false
end

function G.credit(gid, amount)
	G.row(gid)
	local n = G.exec(string.format("UPDATE `%s` SET `bank` = `bank` + %d, `updated_at` = %d WHERE `guild_id` = %d",
		T.guilds, amount, now(), gid))
	if n == 1 then
		local r = G.row(gid)
		r.bank = r.bank + amount
		return true
	end
	G.cache[gid] = nil
	return false
end

local function payFromPlayer(player, amount)
	return Chaos.pay(player, amount) and true or false
end
G.payFromPlayer = payFromPlayer

function G.deposit(player, amount)
	local gid, _, rank = G.guildOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	if limited(player, "guild.money") then
		return false, "Slow down."
	end
	local blocked = seasonBlocked(player)
	if blocked then
		return false, blocked
	end
	amount = Chaos.toInt(amount, 1)
	if not amount or amount < cfg.bank.minDeposit then
		return false, string.format("Deposit at least %s gold.", C.money(cfg.bank.minDeposit))
	end
	if rank < cfg.bank.depositRank then
		return false, "Your rank may not deposit."
	end
	if not payFromPlayer(player, amount) then
		return false, "You do not have that much gold (carried and in the bank)."
	end
	-- saved before the guild bank row is credited: a crash in between cannot leave the gold in both places
	if not Chaos.saveCharacter(player) then
		player:setBankBalance(player:getBankBalance() + amount)
		return false, "The guild bank is busy; your gold went back to your bank balance."
	end
	if not G.credit(gid, amount) then
		player:setBankBalance(player:getBankBalance() + amount)
		G.logRow(gid, player, "refund", amount, 0, 0, "deposit failed, gold returned to the bank balance")
		return false, "The deposit failed; your gold went back to your bank balance."
	end
	G.logRow(gid, player, "deposit", amount)
	return true, string.format("You deposited %s gold into the guild bank (now %s).", C.money(amount), C.money(G.row(gid).bank))
end

function G.withdraw(player, amount)
	local gid, _, rank = G.guildOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	if limited(player, "guild.money") then
		return false, "Slow down."
	end
	local blocked = seasonBlocked(player)
	if blocked then
		return false, blocked
	end
	if rank < cfg.bank.withdrawRank then
		return false, "Only the guild leader can withdraw from the guild bank."
	end
	amount = Chaos.toInt(amount, 1)
	if not amount then
		return false, "Withdraw how much?"
	end
	if not G.spend(gid, amount) then
		return false, string.format("The guild bank holds %s gold.", C.money(G.row(gid).bank))
	end
	player:setBankBalance(player:getBankBalance() + amount)
	-- the guild row is debited already: saved now, else a crash before the next save lost the gold (server/README.md
	-- "Stress test"); a failed save keeps the credit in memory for the next one
	Chaos.saveCharacter(player)
	G.logRow(gid, player, "withdraw", amount)
	return true, string.format("You withdrew %s gold to your bank balance (guild bank now %s).", C.money(amount), C.money(G.row(gid).bank))
end

-- ---------------------------------------------------------------- guild hall scroll
function G.claimScroll(player)
	local gid = G.guildOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	if not G.perksOf(gid).scroll then
		local lvl
		for _, s in ipairs(cfg.perks) do
			if s.scroll then
				lvl = s.level
				break
			end
		end
		return false, string.format("Your guild needs guild level %d for the guild hall scroll.", lvl or 0)
	end
	local today = Chaos.dayKey()
	if player:getStorageValue(cfg.storage.scrollDay) == today then
		return false, "You already took today's guild hall scroll."
	end
	local item = Game.createItem(cfg.scroll.itemId, 1)
	if not item then
		return false, "The scroll could not be created."
	end
	item:setActionId(cfg.scroll.actionId)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, "guild hall scroll")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Use it to travel to your guild's hall (a guild without one: your temple). One use.")
	if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
		return false, "You have no room for the scroll."
	end
	player:setStorageValue(cfg.storage.scrollDay, today)
	return true, "You received today's guild hall scroll."
end

local scroll = Action()
function scroll.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local blocked = ChaosShopServices and ChaosShopServices.teleportBlocked and ChaosShopServices.teleportBlocked(player)
	if not blocked and ChaosSiege and ChaosSiege.isInside and ChaosSiege.isInside(player) then
		blocked = "You cannot use this inside the siege."
	end
	if not blocked and ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) then
		blocked = "You cannot use this inside the arena."
	end
	if blocked then
		player:sendCancelMessage(Chaos.tx(player, blocked))
		return true
	end
	local ok = G.enterHall and G.enterHall(player, true)
	if not ok then
		local temple = player:getTown():getTemplePosition()
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		player:teleportTo(temple)
		temple:sendMagicEffect(CONST_ME_TELEPORT)
	end
	item:remove(1)
	return true
end
scroll:aid(cfg.scroll.actionId)
scroll:register()

-- ---------------------------------------------------------------- window data
function G.topGuilds(week)
	week = week or weekNow()
	G.topCache = G.topCache or {}
	local c = G.topCache[week]
	if c and c.at > now() - 60 then
		return c.rows
	end
	local rows = Chaos.select(string.format(
		"SELECT c.`guild_id` AS `id`, g.`name` AS `name`, SUM(c.`amount`) AS `points` FROM `%s` c JOIN `guilds` g ON g.`id` = c.`guild_id` " ..
		"WHERE c.`week` = %d GROUP BY c.`guild_id` ORDER BY `points` DESC LIMIT 50", T.contrib, week),
		{{"id", "n"}, {"name", "s"}, {"points", "n"}})
	for _, r in ipairs(rows) do
		r.level = G.levelOf(r.id)
	end
	rows = C.rankGuilds(rows)
	G.topCache[week] = {at = now(), rows = rows}
	return rows
end

local function membersOf(gid)
	local week = weekNow()
	local contrib = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `player_id`, SUM(`amount`) AS `total`, SUM(CASE WHEN `week` = %d THEN `amount` ELSE 0 END) AS `wk` " ..
			"FROM `%s` WHERE `guild_id` = %d GROUP BY `player_id`", week, T.contrib, gid), {{"player_id", "n"}, {"total", "n"}, {"wk", "n"}})) do
		contrib[r.player_id] = r
	end
	local list = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT m.`player_id`, p.`name`, p.`level`, r.`name` AS `rank`, r.`level` AS `ranklevel` " ..
			"FROM `guild_membership` m JOIN `players` p ON p.`id` = m.`player_id` JOIN `guild_ranks` r ON r.`id` = m.`rank_id` " ..
			"WHERE m.`guild_id` = %d", gid), {{"player_id", "n"}, {"name", "s"}, {"level", "n"}, {"rank", "s"}, {"ranklevel", "n"}})) do
		local c = contrib[r.player_id] or {total = 0, wk = 0}
		local pending = G.pendingExp[gid] and G.pendingExp[gid][r.player_id] or 0
		list[#list + 1] = {name = r.name, level = r.level, rank = r.rank, rankLevel = r.ranklevel,
			online = Player(r.player_id) ~= nil, week = c.wk + pending, total = c.total + pending}
	end
	table.sort(list, function(a, b)
		if a.week ~= b.week then
			return a.week > b.week
		end
		return a.name < b.name
	end)
	while #list > cfg.window.members do
		table.remove(list)
	end
	return list
end

-- player: the reader (the rows are told in the reader's language); nil: English (the staff command)
function G.logLines(gid, actions, limit, player)
	local where = ""
	if actions then
		local q = {}
		for _, a in ipairs(actions) do
			q[#q + 1] = db.escapeString(a)
		end
		where = " AND `action` IN (" .. table.concat(q, ", ") .. ")"
	end
	local t
	if player and Chaos.t then
		t = function(key, ...) return Chaos.t(player, key, ...) end
	end
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `at`, `player_name`, `action`, `amount`, `item_id`, `count`, `text` FROM `%s` " ..
			"WHERE `guild_id` = %d%s ORDER BY `id` DESC LIMIT %d", T.log, gid, where, limit or cfg.window.logRows),
			{{"at", "n"}, {"player_name", "s"}, {"action", "s"}, {"amount", "n"}, {"item_id", "n"}, {"count", "n"}, {"text", "s"}})) do
		out[#out + 1] = C.logLine({at = r.at, name = r.player_name ~= "" and r.player_name or "Guild", action = r.action,
			amount = r.amount, count = r.count, item = r.text, text = r.text}, t)
	end
	return out
end

function G.state(player, tab)
	local gid, gname, rank = G.guildOf(player)
	if not gid then
		return nil
	end
	G.flushExp()
	local r = G.row(gid)
	local level, into, need, pct = C.levelOf(r.xp, cfg)
	local week = weekNow()
	local top = G.topGuilds(week)
	local own
	for _, t in ipairs(top) do
		if t.id == gid then
			own = t
		end
	end
	local lastWeek = G.topGuilds(C.weekKey(now() - 7 * 86400, cfg.week.resetHour))
	local rows = {}
	for i = 1, math.min(#top, cfg.week.rows) do
		local t = top[i]
		rows[i] = {rank = t.rank, name = t.name, level = t.level, points = t.points, own = t.id == gid}
	end
	local _, weekEnd = C.weekBounds(week, cfg.week.resetHour)
	local perks = C.perksAt(level, cfg)
	local rankNames = {[3] = "Leader", [2] = "Vice-leader", [1] = "Member"}
	local data = {
		tab = tab or "overview",
		guild = {id = gid, name = gname, level = level, maxLevel = cfg.maxLevel, xp = r.xp, into = into, need = need, pct = pct,
			bank = r.bank, rank = rank, rankName = rankNames[rank] or "Member", weekPoints = own and own.points or 0,
			weekRank = own and own.rank or 0, canWithdraw = rank >= cfg.bank.withdrawRank, minDeposit = cfg.bank.minDeposit,
			scroll = perks.scroll, scrollTaken = player:getStorageValue(cfg.storage.scrollDay) == Chaos.dayKey()},
		perks = {now = perks, list = C.perkList(level, cfg)},
		members = membersOf(gid),
		log = G.logLines(gid, {"deposit", "withdraw", "hall", "upgrade", "rent", "refund", "level", "war", "boss"}, nil, player),
		top = {rows = rows, resetIn = math.max(0, weekEnd - now()), lastWinner = lastWeek[1] and lastWeek[1].name or ""}
	}
	if G.hallView then
		data.hall, data.depot = G.hallView(player, gid, rank, level)
	end
	return data
end

function G.sendState(player, open, tab)
	local data = G.state(player, tab)
	if not data then
		if open then
			Chaos.send(player, OPCODE, "none", {open = true, text = Chaos.t(player, "You are not in a guild. Guilds are founded and joined on the website.")})
		end
		return
	end
	data.open = open and true or false
	Chaos.send(player, OPCODE, "state", data)
end

function G.message(player, ok, text)
	if text and text ~= "" then
		text = Chaos.tx(player, text) -- the cores and helpers return English reasons
		player:sendTextMessage(ok and MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL, text)
		Chaos.send(player, OPCODE, "message", {ok = ok and true or false, text = text})
	end
end

-- ---------------------------------------------------------------- protocol
local function handle(player, action, data)
	local ok, text
	if action == "open" or action == "refresh" then
		if limited(player, "guild.state", 300) then
			return
		end
		G.sendState(player, action == "open", type(data.tab) == "string" and data.tab:sub(1, 16) or nil)
		return
	elseif limited(player, "guild.act", 250) then
		-- every action below answers with the whole state (members, log and depot are database reads): a flood of
		-- refused requests ("Slow down", "already taken") must not cost a state each
		return
	elseif action == "deposit" then
		ok, text = G.deposit(player, data.amount)
	elseif action == "withdraw" then
		ok, text = G.withdraw(player, data.amount)
	elseif action == "scroll" then
		ok, text = G.claimScroll(player)
	elseif action == "buyHall" and G.buyHall then
		ok, text = G.buyHall(player, data.from == "self" and "self" or "bank")
	elseif action == "upgrade" and G.buyUpgrade then
		ok, text = G.buyUpgrade(player, tostring(data.key or ""))
	elseif action == "payRent" and G.payRentBy then
		ok, text = G.payRentBy(player)
	elseif action == "take" and G.depotTake then
		ok, text = G.depotTake(player, data.id)
	else
		return
	end
	G.message(player, ok, text)
	G.sendState(player, false, data.tab)
end

local ext = CreatureEvent("ChaosGuildOpcode")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	local ok, err = pcall(handle, player, msg.action, type(msg.data) == "table" and msg.data or {})
	if not ok then
		log("request " .. msg.action .. " failed: " .. tostring(err))
	end
end
ext:register()

local login = CreatureEvent("ChaosGuildLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGuildOpcode")
	player:registerEvent("ChaosGuildLogout")
	G.wrapLeaderboard()
	G.wrapLoot()
	G.wrapRespec()
	local gid = G.guildOf(player)
	if gid then
		G.row(gid)
	end
	G.applyAura(player)
	if G.onLoginHall then
		pcall(G.onLoginHall, player)
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosGuildLogout")
function logout.onLogout(player)
	pcall(G.flushExp, player:getGuid())
	G.day[player:getGuid()] = nil
	return true
end
logout:register()

-- ---------------------------------------------------------------- commands
local function parseAmount(s)
	s = (s or ""):lower():gsub(",", ""):gsub("%s", "")
	local n, suffix = s:match("^(%d+%.?%d*)([km]?)$")
	if not n then
		return nil
	end
	n = tonumber(n)
	if suffix == "k" then
		n = n * 1000
	elseif suffix == "m" then
		n = n * 1000000
	end
	return math.floor(n)
end
G.parseAmount = parseAmount

-- staff: /guild xp <guild>, <n> | info <guild> | log <guild> | rent <guild>, due|lock|paid | hall <guild> | bank <guild>, <n>
local function guildByName(name)
	local rows = Chaos.select("SELECT `id`, `name` FROM `guilds` WHERE `name` = " .. db.escapeString(name or ""), {{"id", "n"}, {"name", "s"}})
	return rows[1] and rows[1].id, rows[1] and rows[1].name
end

local function onStaffCommand(player, words, param)
	if not cfg.staffAccess or not player:getGroup():getAccess() then
		return true
	end
	local sub, rest = (param or ""):match("^%s*(%S+)%s*(.*)$")
	sub = (sub or ""):lower()
	local name, arg = rest:match("^([^,]+),%s*(.+)$")
	name = (name or rest):gsub("%s+$", "")
	local gid, gname = guildByName(name)
	local function say(t)
		player:sendTextMessage(MESSAGE_INFO_DESCR, t)
	end
	if not gid then
		say("/guild xp|bank|info|log|rent|hall <guild name>[, value]: guild not found.")
		return false
	end
	-- staff never give value (docs/GM_HANDBOOK.md section 2): the guild bank, guild XP and a paid rent need an administrator
	local value = sub == "bank" or sub == "xp" or (sub == "rent" and (arg or ""):lower():match("^%s*paid") ~= nil)
	if not Chaos.staffCommand(player, words, param, value) then
		return false
	end
	if sub == "xp" then
		local n = G.addXp(gid, 0, "staff", tonumber(arg) or 0, true)
		G.logRow(gid, player, "staff", 0, 0, n, "staff added " .. n .. " GXP")
		say(string.format("%s: +%d GXP, level %d.", gname, n, G.levelOf(gid)))
	elseif sub == "bank" then
		local n = math.floor(tonumber(arg) or 0)
		if n > 0 and G.credit(gid, n) then
			G.logRow(gid, player, "staff", n, 0, 0, "staff credit")
		elseif n < 0 and G.spend(gid, -n) then
			G.logRow(gid, player, "staff", n, 0, 0, "staff debit")
		end
		say(string.format("%s: guild bank %s gold.", gname, C.money(G.row(gid).bank)))
	elseif sub == "info" then
		G.cache[gid] = nil
		local r = G.row(gid)
		local hall = G.hallOf and G.hallOf(gid)
		say(string.format("%s (%d): level %d, %s GXP, bank %s.%s", gname, gid, r.level, C.money(r.xp), C.money(r.bank),
			hall and string.format(" Hall slot %d, rent %s (%s).", hall.slot, G.rentStateOf(gid), C.durationText(hall.paidUntil - now())) or " No hall."))
	elseif sub == "log" then
		for _, line in ipairs(G.logLines(gid, nil, 20)) do
			say(line)
		end
	elseif sub == "rent" and G.staffRent then
		say(G.staffRent(gid, (arg or ""):lower()))
	elseif sub == "hall" and G.enterHall then
		say(G.enterHall(player, true, gid) and "Teleported." or "That guild has no hall.")
	else
		say("/guild xp|bank|info|log|rent|hall <guild name>[, value]")
	end
	return false
end

local staff = TalkAction("/guild")
staff.onSay = onStaffCommand
staff:separator(" ")
staff:register()

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosGuildStartup")
function startup.onStartup()
	G.ensureTables()
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `at` < %d", T.log, now() - (cfg.logKeepDays or 180) * 86400))
	G.wrapLeaderboard()
	G.wrapLoot()
	G.wrapRespec()
	if G.loadHalls then
		G.loadHalls()
	end
	return true
end
startup:register()

local think = GlobalEvent("ChaosGuildThink")
function think.onThink(interval)
	G.wrapLeaderboard()
	G.wrapLoot()
	G.wrapRespec()
	local ok, err = pcall(G.flushExp)
	if not ok then
		log("flush failed: " .. tostring(err))
	end
	ok, err = pcall(G.checkSiegeResults)
	if not ok then
		log("siege results failed: " .. tostring(err))
	end
	if G.hallThink then
		ok, err = pcall(G.hallThink)
		if not ok then
			log("hall check failed: " .. tostring(err))
		end
	end
	return true
end
think:interval(60000)
think:register()

local shutdown = GlobalEvent("ChaosGuildShutdown")
function shutdown.onShutdown()
	pcall(G.flushExp)
	return true
end
shutdown:register()

-- tables also when the file is reloaded on a running server
if db and db.query then
	pcall(G.ensureTables)
end

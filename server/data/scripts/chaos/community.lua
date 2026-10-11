-- Community goals and the weekly world modifier (client game_community, extended opcode ChaosOpcodes.community = 203).
-- Rules and numbers: community_config.lua; pure logic: community_core.lua (tests: server/tests/community_test.lua);
-- overview: server/README.md "Community goals and the weekly world modifier". Tables: chaos_community_goal,
-- chaos_community_buffs, chaos_community_contrib, chaos_community_week, chaos_community_history
-- (server/sql/chaos_community.sql; also created at startup). No player storages.
--
-- The goal: every character feeds one server-wide bar (or one per Season realm, goal.realms = "separate") with monster
-- kills, sealed rifts, repelled invasion waves, world boss kills, crafting orbs used and gold given to the Great Brazier
-- (an object next to the main temple). Per-character daily caps; staff add nothing. Each stage (25/50/75/100%) opens a
-- buff window for everyone (buff bar, chat, website). When the period ends, the top contributors get a title and
-- everybody above a threshold gets tokens, at their next login.
-- The week: one or two modifiers drawn by the week's seed (or set by staff), applied through existing hook points.
--
-- Hooks (each guarded; with no stage window open and no modifier active every one is neutral):
--   EventCallback onGainExperience   stage xp windows x the family modifier (Restless Dead ...), monster kills only
--   loot_config.lua rateMult          ChaosCommunity.lootMult(ctx): stage loot windows x the family modifier
--   ChaosEvents.dynamic               the week's calendar bonuses (Champions' Week tierChance, Gilded Week goblin ...)
--                                     as runtime events, so monster_tiers.lua / treasure_goblin.lua / infinitytower.lua
--                                     apply them as they apply the event calendar
--   ChaosRiftCore.hooks.world         Rift Beacon key chance, Ember Tides (one more modifier, richer chests)
--   factions.lua F.gain               ChaosCommunity.repMult(player)
--   crafting.lua craft()              ChaosCommunity.onOrbUsed(player, orb): the goal source, and Forgefire's kept orb
--   chaos_buffs.lua source community  the buff bar items (open stage windows, the week's modifiers)
--   ChaosLeaderboard.record           wrapped: "rift" -> rifts sealed, "defender" -> invasion waves repelled
--   ChaosLeaderboard.recordShares     wrapped: world boss kills (every share)
--   kill event on players             monsters slain
--   ChaosTitles.register("community") the reward title
--
-- Protocol (JSON {action, data}; the state goes out with Chaos.sendChunked):
--   client -> server  open | close | donate {gold}
--   server -> client  state {...} (community_core.lua C.payload) | msg {text, ok} | brazier {} (the Brazier was used:
--                     the client opens the donate dialog and asks with open)
-- Staff: /community [status | modifier <key>[,<key>] | modifier auto | add <points> | stage <n>]
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/community_core.lua")

Chaos.communityConfig = dofile("data/scripts/chaos/community_config.lua")
local cfg = Chaos.communityConfig
local K = ChaosCommunityCore
local OPCODE = ChaosOpcodes.community or cfg.opcode
local T = cfg.tables

ChaosCommunity = ChaosCommunity or {}
local X = ChaosCommunity
X.goals = X.goals or {} -- realm -> {period, finish, progress, dirty}
X.buffs = X.buffs or {} -- realm -> {[stage index] = {startedAt, endsAt, period}}
X.entries = X.entries or {} -- guid -> entry (K.newEntry + guid, name, realm, period, dirty)
X.watch = X.watch or {} -- player id -> true while the window is open
X.topCache = X.topCache or {} -- realm -> {at, list}
X.week = X.week or nil -- {key, mods, source, finish}
X.override = X.override or ""

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos community] " .. text)
end

local function try(what, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(what .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function q(text)
	return db.escapeString(tostring(text or ""))
end

local function hour()
	return cfg.resetHour or 6
end

local function today()
	return K.day(now(), hour())
end

local function periodNow()
	return K.period(cfg, now())
end

local function periodFinish(key)
	return K.keyStart(key, hour(), cfg.goal.periodDays or 7)
end

local function isStaff(player)
	local ok, id = pcall(function() return player:getGroup():getId() end)
	return ok and (id or 1) >= (cfg.staffGroup or 4)
end

local function realmOf(player)
	local S = ChaosSeason
	local r = 0
	if S and S.realmOf then
		local ok, v = pcall(S.realmOf, player)
		r = ok and tonumber(v) or 0
	end
	return K.realmOf(cfg, r)
end

local function realmName(realm)
	if realm == 0 then
		return cfg.goal.realms == "separate" and "Standard realm" or nil
	end
	local S = ChaosSeason
	local season = S and S.current and select(2, pcall(S.current))
	return type(season) == "table" and season.name or ("Season " .. realm)
end

local function broadcast(text)
	if Game and Game.broadcastMessage then
		Game.broadcastMessage(text, MESSAGE_EVENT_ADVANCE)
	end
end

local function history(period, realm, kind, text)
	db.asyncQuery(string.format("INSERT INTO `%s` (`period`, `realm`, `kind`, `text`, `created_at`) VALUES (%d, %d, %s, %s, %d)",
		T.history, period, realm, q(kind), q(text:sub(1, 250)), now()))
end

-- ---------------------------------------------------------------- tables
function X.ensureTables()
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`period` int(10) unsigned NOT NULL, `realm` int(11) NOT NULL DEFAULT 0, " ..
		"`name` varchar(64) NOT NULL DEFAULT '', `target` int(11) NOT NULL DEFAULT 0, `progress` bigint(20) NOT NULL DEFAULT 0, " ..
		"`stage` tinyint(3) unsigned NOT NULL DEFAULT 0, `finish` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`finished` tinyint(1) NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`period`, `realm`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.goal))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`period` int(10) unsigned NOT NULL, `realm` int(11) NOT NULL DEFAULT 0, " ..
		"`stage` tinyint(3) unsigned NOT NULL, `name` varchar(64) NOT NULL DEFAULT '', `text` varchar(255) NOT NULL DEFAULT '', " ..
		"`started_at` int(10) unsigned NOT NULL DEFAULT 0, `ends_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`period`, `realm`, `stage`), KEY `ends_at` (`ends_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.buffs))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`period` int(10) unsigned NOT NULL, `player_id` int(11) NOT NULL, " ..
		"`realm` int(11) NOT NULL DEFAULT 0, `name` varchar(255) NOT NULL DEFAULT '', `points` int(11) NOT NULL DEFAULT 0, " ..
		"`day` int(10) unsigned NOT NULL DEFAULT 0, `day_points` int(11) NOT NULL DEFAULT 0, `day_src` varchar(255) NOT NULL DEFAULT '', " ..
		"`place` tinyint(3) unsigned NOT NULL DEFAULT 0, `token` tinyint(1) NOT NULL DEFAULT 0, `rewarded` tinyint(1) NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`period`, `player_id`), KEY `rank` (`period`, `realm`, `points`), " ..
		"FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.contrib))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`week` int(10) unsigned NOT NULL, `mods` varchar(128) NOT NULL DEFAULT '', " ..
		"`names` varchar(255) NOT NULL DEFAULT '', `texts` text, `source` varchar(8) NOT NULL DEFAULT 'seed', " ..
		"`finish` int(10) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`week`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", T.week))
	db.query(string.format("CREATE TABLE IF NOT EXISTS `%s` (`id` int(11) NOT NULL AUTO_INCREMENT, `period` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`realm` int(11) NOT NULL DEFAULT 0, `kind` varchar(16) NOT NULL DEFAULT '', `text` varchar(255) NOT NULL DEFAULT '', " ..
		"`created_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `created_at` (`created_at`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8", T.history))
end

-- ---------------------------------------------------------------- the goal
local function writeGoal(realm, g)
	db.asyncQuery(string.format("INSERT INTO `%s` (`period`, `realm`, `name`, `target`, `progress`, `stage`, `finish`, `updated_at`) " ..
		"VALUES (%d, %d, %s, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `progress` = VALUES(`progress`), `stage` = VALUES(`stage`), " ..
		"`target` = VALUES(`target`), `name` = VALUES(`name`), `updated_at` = VALUES(`updated_at`)",
		T.goal, g.period, realm, q(cfg.goal.name), cfg.goal.target, math.floor(g.progress), K.stageAt(cfg, g.progress), g.finish, now()))
	g.dirty = false
end

local function writeEntry(e)
	db.asyncQuery(string.format("INSERT INTO `%s` (`period`, `player_id`, `realm`, `name`, `points`, `day`, `day_points`, `day_src`, " ..
		"`updated_at`) VALUES (%d, %d, %d, %s, %d, %d, %d, %s, %d) ON DUPLICATE KEY UPDATE `points` = VALUES(`points`), " ..
		"`day` = VALUES(`day`), `day_points` = VALUES(`day_points`), `day_src` = VALUES(`day_src`), `realm` = VALUES(`realm`), " ..
		"`name` = VALUES(`name`), `updated_at` = VALUES(`updated_at`)",
		T.contrib, e.period, e.guid, e.realm, q(e.name), e.points, e.day, e.dayTotal, q(K.encodeSrc(e.daySrc)), e.at or now()))
	e.dirty = false
end

function X.flush()
	for realm, g in pairs(X.goals) do
		if g.dirty then
			writeGoal(realm, g)
		end
	end
	for _, e in pairs(X.entries) do
		if e.dirty then
			writeEntry(e)
		end
	end
end

-- the rewards of a finished period are marked on its rows (place, token); they are given at the next login
function X.finishPeriod(period, realm)
	local rows = Chaos.select(string.format("SELECT `player_id`, `name`, `points`, `updated_at` FROM `%s` WHERE `period` = %d AND `realm` = %d",
		T.contrib, period, realm), {{"player_id", "n"}, {"name", "s"}, {"points", "n"}, {"updated_at", "n"}})
	local list = {}
	for _, r in ipairs(rows) do
		list[#list + 1] = {guid = r.player_id, name = r.name, points = r.points, at = r.updated_at}
	end
	local ranked = K.rank(list)
	for guid, rw in pairs(K.periodRewards(cfg, ranked)) do
		db.asyncQuery(string.format("UPDATE `%s` SET `place` = %d, `token` = %d WHERE `period` = %d AND `player_id` = %d",
			T.contrib, rw.place, rw.token and 1 or 0, period, guid))
	end
	local g = Chaos.select(string.format("SELECT `progress` FROM `%s` WHERE `period` = %d AND `realm` = %d", T.goal, period, realm),
		{{"progress", "n"}})[1]
	local pct = math.floor(K.pct(cfg, g and g.progress or 0))
	db.asyncQuery(string.format("UPDATE `%s` SET `finished` = 1 WHERE `period` = %d AND `realm` = %d", T.goal, period, realm))
	local names = {}
	for i = 1, math.min(3, #ranked) do
		names[#names + 1] = ranked[i].name
	end
	local text = string.format("The community goal ended at %d%%.%s", pct,
		#names > 0 and (" Top contributors: " .. table.concat(names, ", ") .. ".") or "")
	history(period, realm, "end", text)
	return text, ranked
end

-- the goal of a realm for the period now (a new period finishes the old one first)
function X.goal(realm)
	local period, _, finish = periodNow()
	local g = X.goals[realm]
	if g and g.period == period then
		return g
	end
	if g then
		writeGoal(realm, g)
		X.flush()
		local text = try("finish period", X.finishPeriod, g.period, realm)
		if text then
			broadcast(text .. " A new community goal begins: " .. cfg.goal.name .. ".")
		end
	end
	local row = Chaos.select(string.format("SELECT `progress` FROM `%s` WHERE `period` = %d AND `realm` = %d", T.goal, period, realm),
		{{"progress", "n"}})[1]
	g = {period = period, finish = finish, progress = row and row.progress or 0, dirty = row == nil}
	X.goals[realm] = g
	X.topCache[realm] = nil
	return g
end

-- finish every period that ended while the server was down
function X.finishOld()
	local period = periodNow()
	for _, r in ipairs(Chaos.select(string.format("SELECT `period`, `realm` FROM `%s` WHERE `finished` = 0 AND `period` < %d",
			T.goal, period), {{"period", "n"}, {"realm", "n"}})) do
		try("finish old period", X.finishPeriod, r.period, r.realm)
	end
end

function X.loadBuffs()
	X.buffs = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `period`, `realm`, `stage`, `started_at`, `ends_at` FROM `%s` WHERE `ends_at` > %d",
			T.buffs, now()), {{"period", "n"}, {"realm", "n"}, {"stage", "n"}, {"started_at", "n"}, {"ends_at", "n"}})) do
		X.buffs[r.realm] = X.buffs[r.realm] or {}
		local cur = X.buffs[r.realm][r.stage]
		if not cur or cur.endsAt < r.ends_at then
			X.buffs[r.realm][r.stage] = {startedAt = r.started_at, endsAt = r.ends_at, period = r.period}
		end
	end
end

local function pushAll()
	for id in pairs(X.watch) do
		local p = Player(id)
		if p then
			try("push", X.send, p)
		else
			X.watch[id] = nil
		end
	end
end

function X.unlockStage(realm, i, period)
	local s = cfg.goal.stages[i]
	X.buffs[realm] = X.buffs[realm] or {}
	local w = K.openWindow(cfg, X.buffs[realm], i, now(), period)
	if not w then
		return
	end
	db.asyncQuery(string.format("INSERT INTO `%s` (`period`, `realm`, `stage`, `name`, `text`, `started_at`, `ends_at`) VALUES " ..
		"(%d, %d, %d, %s, %s, %d, %d) ON DUPLICATE KEY UPDATE `started_at` = VALUES(`started_at`), `ends_at` = VALUES(`ends_at`)",
		T.buffs, period, realm, i, q(s.name), q(s.text), w.startedAt, w.endsAt))
	local who = realmName(realm)
	local text = string.format("Community goal %d%% reached%s! %s: %s for %d hours.", s.pct, who and (" (" .. who .. ")") or "",
		s.name, s.text, s.hours)
	broadcast(text)
	history(period, realm, "stage", text)
	writeGoal(realm, X.goals[realm])
	pushAll()
end

-- ---------------------------------------------------------------- contributions
local function entryOf(player, realm)
	local guid = player:getGuid()
	local period = periodNow()
	local e = X.entries[guid]
	if e and e.period == period then
		e.realm = realm
		return e
	end
	if e and e.dirty then
		writeEntry(e)
	end
	local row = Chaos.select(string.format("SELECT `points`, `day`, `day_points`, `day_src`, `updated_at` FROM `%s` " ..
		"WHERE `period` = %d AND `player_id` = %d", T.contrib, period, guid),
		{{"points", "n"}, {"day", "n"}, {"day_points", "n"}, {"day_src", "s"}, {"updated_at", "n"}})[1]
	e = K.newEntry()
	if row then
		e.points, e.day, e.dayTotal, e.daySrc, e.at = row.points, row.day, row.day_points, K.decodeSrc(row.day_src), row.updated_at
	end
	e.guid, e.name, e.realm, e.period = guid, player:getName(), realm, period
	X.entries[guid] = e
	return e
end

-- `units` of source `key` from player (opts: tier, riftTier). Returns the points counted.
function X.contribute(player, key, units, opts)
	if not cfg.enabled or not player or isStaff(player) then
		return 0
	end
	local pts = K.points(cfg, key, units, opts)
	if pts <= 0 then
		return 0
	end
	local realm = realmOf(player)
	local g = X.goal(realm)
	local e = entryOf(player, realm)
	local gained = K.credit(cfg, e, key, pts, today(), now())
	if gained <= 0 then
		return 0
	end
	e.dirty = true
	local before = g.progress
	g.progress = g.progress + gained
	g.dirty = true
	for _, p in ipairs(K.steps(cfg, before, g.progress)) do
		if p < 100 and not K.crossed(cfg, before, g.progress)[1] then
			broadcast(string.format("The Great Brazier burns at %d%%: keep feeding it!", p))
		end
	end
	for _, i in ipairs(K.crossed(cfg, before, g.progress)) do
		X.unlockStage(realm, i, g.period)
	end
	return gained
end

-- ---------------------------------------------------------------- the week
local function readOverride()
	local row = Chaos.select("SELECT `value` FROM `server_config` WHERE `config` = " .. q(cfg.overrideKey), {{"value", "s"}})[1]
	return row and row.value or ""
end

local function writeOverride(text)
	db.query("INSERT INTO `server_config` (`config`, `value`) VALUES (" .. q(cfg.overrideKey) .. ", " .. q(text) ..
		") ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)")
end

-- the week's calendar bonuses (and a line in !events for every modifier) as runtime events
local function applyEvents(w)
	local E = ChaosEvents
	if not E or not E.dynamic then
		return
	end
	for k in pairs(E.dynamic) do
		if type(k) == "string" and k:sub(1, 10) == "community_" then
			E.dynamic[k] = nil
		end
	end
	for _, m in ipairs(w.mods) do
		E.dynamic["community_" .. m.key] = {id = "community_" .. m.key, name = m.name, description = m.text,
			bonus = m.events, untilTime = w.finish}
	end
end

function X.currentWeek(force)
	local key = K.week(now(), hour())
	if X.week and X.week.key == key and not force then
		return X.week
	end
	local fresh = not X.week or X.week.key ~= key
	local mods, source = K.weekModifiers(cfg, key, X.override)
	local w = {key = key, mods = mods, source = source, finish = K.weekEnd(now(), hour())}
	X.week = w
	applyEvents(w)
	local keys, names, texts = {}, {}, {}
	for _, m in ipairs(mods) do
		keys[#keys + 1], names[#names + 1], texts[#texts + 1] = m.key, m.name, m.text
	end
	db.asyncQuery(string.format("INSERT INTO `%s` (`week`, `mods`, `names`, `texts`, `source`, `finish`, `updated_at`) VALUES " ..
		"(%d, %s, %s, %s, %s, %d, %d) ON DUPLICATE KEY UPDATE `mods` = VALUES(`mods`), `names` = VALUES(`names`), " ..
		"`texts` = VALUES(`texts`), `source` = VALUES(`source`), `finish` = VALUES(`finish`), `updated_at` = VALUES(`updated_at`)",
		T.week, key, q(table.concat(keys, ",")), q(table.concat(names, "|")), q(table.concat(texts, "|")), q(source), w.finish, now()))
	if fresh and X.started then
		broadcast("A new week: the world changes. " .. table.concat(names, ", ") .. " (Adventure > Community).")
	end
	return w
end

local function mods()
	local w = X.week or X.currentWeek()
	return w and w.mods or {}
end

-- ---------------------------------------------------------------- hooks for the other systems
local function buffsOf(realm)
	return X.buffs[realm] or {}
end

local function familyOf(creature)
	local name = Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
	return K.familyOf(cfg, name, function(n)
		local B = ChaosBestiary
		local ok, cat = pcall(function() return B and B.cat and B.cat() end)
		local e = ok and cat and cat.byKey and cat.byKey[n]
		return e and e.cat or nil
	end)
end

function X.xpMult(player, monster)
	if not cfg.enabled then
		return 1
	end
	return K.xpMult(cfg, buffsOf(realmOf(player)), mods(), now(), monster and familyOf(monster) or nil)
end

-- loot_config.lua rateMult (ctx = {tier, monster, player = the corpse owner})
function X.lootMult(ctx)
	if not cfg.enabled or type(ctx) ~= "table" then
		return 1
	end
	local realm = ctx.player and realmOf(ctx.player) or 0
	local fam = ctx.monster and try("family", familyOf, ctx.monster) or nil
	return K.lootMult(cfg, buffsOf(realm), mods(), now(), fam)
end

function X.repMult(player)
	if not cfg.enabled or not player then
		return 1
	end
	return K.repMult(cfg, buffsOf(realmOf(player)), mods(), now())
end

function X.riftWorld(player)
	if not cfg.enabled or not player then
		return nil
	end
	return K.riftWorld(cfg, buffsOf(realmOf(player)), mods(), now())
end

-- crafting.lua: an orb was used on an item. Feeds the goal; returns true when Forgefire keeps the orb.
function X.onOrbUsed(player, orbKey)
	try("orb", X.contribute, player, "orb", 1)
	local keep = cfg.enabled and K.orbKeep(mods()) or 0
	if keep > 0 and math.random(1, 100) <= keep then
		player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, "Forgefire: the orb was not used up.")
		return true
	end
	return false
end

-- chaos_buffs.lua source "community": def.week = true for the modifiers' entry, else the stage windows
function X.buffItems(player, def)
	if not cfg.enabled then
		return nil
	end
	local w = X.week or X.currentWeek()
	return K.buffItems(cfg, buffsOf(realmOf(player)), w and w.mods, now(), w and w.finish, def.week and "week" or "stage")
end

-- the rift: Rift Beacon (key chance) and Ember Tides (one more modifier, richer chests); see rift_core.lua R.worldMods
ChaosRiftCore = ChaosRiftCore or {}
ChaosRiftCore.hooks = ChaosRiftCore.hooks or {}
ChaosRiftCore.hooks.world = function(player, ctx)
	return X.riftWorld(player)
end

local function online(who)
	if type(who) ~= "table" and type(who) ~= "userdata" then
		return nil
	end
	if type(who) == "userdata" then
		return who
	end
	if who.getGuid then
		return who
	end
	local p = who.name and Player(who.name)
	if p and (not who.guid or p:getGuid() == who.guid) then
		return p
	end
	return nil
end

local function onRecord(board, who, value)
	local player = online(who)
	if not player then
		return
	end
	if board == "rift" then
		X.contribute(player, "rift", 1, {riftTier = tonumber(value) or 1})
	elseif board == "defender" then
		local V = ChaosInvasion
		local waves = V and V.state and tonumber(V.state.waves) or 5
		X.contribute(player, "invasion", waves)
	end
end

function X.installHooks()
	local LB = ChaosLeaderboard
	if LB and LB.record and not LB.communityWrapped then
		local original = LB.record
		LB.record = function(board, who, value, mode)
			local entry = original(board, who, value, mode)
			if cfg.enabled then
				try("leaderboard hook", onRecord, board, who, value)
			end
			return entry
		end
		LB.communityWrapped = true
	end
	if LB and LB.recordShares and not LB.communitySharesWrapped then
		local original = LB.recordShares
		LB.recordShares = function(shares, ...)
			local out = original(shares, ...)
			if cfg.enabled then
				for _, s in ipairs(shares or {}) do
					local p = online({guid = s.guid, name = s.name})
					if p then
						try("world boss hook", X.contribute, p, "worldboss", 1)
					end
				end
			end
			return out
		end
		LB.communitySharesWrapped = true
	end
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("community", function(player)
			local t = X.titles[player:getGuid()]
			if t and K.titleOf(cfg, t.place, t.periodEnd, now()) then
				return K.titleOf(cfg, t.place, t.periodEnd, now())
			end
			return nil
		end)
	end
end
X.titles = X.titles or {} -- guid -> {place, periodEnd} of the newest top place

-- ---------------------------------------------------------------- rewards at login
local function giveItems(player, items)
	for _, it in ipairs(items or {}) do
		local got = Chaos.giveItem(player, it.id, it.count)
		if got < it.count then
			local inbox = player:getInbox()
			if inbox then
				inbox:addItem(it.id, it.count - got)
			end
		end
	end
end

function X.deliverRewards(player)
	local guid = player:getGuid()
	local period = periodNow()
	local r = cfg.goal.rewards
	for _, row in ipairs(Chaos.select(string.format("SELECT `period`, `place`, `token`, `points` FROM `%s` WHERE `player_id` = %d " ..
			"AND `period` < %d AND `rewarded` = 0 AND (`place` > 0 OR `token` = 1)", T.contrib, guid, period),
			{{"period", "n"}, {"place", "n"}, {"token", "n"}, {"points", "n"}})) do
		db.query(string.format("UPDATE `%s` SET `rewarded` = 1 WHERE `period` = %d AND `player_id` = %d", T.contrib, row.period, guid))
		local parts = {}
		if row.token == 1 and r.token then
			giveItems(player, r.token.items)
			parts[#parts + 1] = r.token.text
		end
		if row.place > 0 and r.title then
			parts[#parts + 1] = string.format("the title %s for %d days (place %d)", r.title, r.titleDays or 7, row.place)
		end
		if #parts > 0 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Community goal reward (%d points): %s.", row.points,
				table.concat(parts, " and ")))
		end
	end
	local best = Chaos.select(string.format("SELECT `period`, `place` FROM `%s` WHERE `player_id` = %d AND `place` > 0 " ..
		"ORDER BY `period` DESC LIMIT 1", T.contrib, guid), {{"period", "n"}, {"place", "n"}})[1]
	X.titles[guid] = best and {place = best.place, periodEnd = periodFinish(best.period)} or nil
end

-- ---------------------------------------------------------------- the window
local function topOf(realm, period)
	local c = X.topCache[realm]
	if c and c.period == period and now() - c.at < 15 then
		return c.list
	end
	local rows = Chaos.select(string.format("SELECT `player_id`, `name`, `points`, `updated_at` FROM `%s` WHERE `period` = %d " ..
		"AND `realm` = %d ORDER BY `points` DESC LIMIT 20", T.contrib, period, realm),
		{{"player_id", "n"}, {"name", "s"}, {"points", "n"}, {"updated_at", "n"}})
	local byGuid = {}
	for _, r in ipairs(rows) do
		byGuid[r.player_id] = {guid = r.player_id, name = r.name, points = r.points, at = r.updated_at}
	end
	for guid, e in pairs(X.entries) do -- unflushed points of the characters online
		if e.period == period and e.realm == realm and e.points > 0 then
			byGuid[guid] = {guid = guid, name = e.name, points = e.points, at = e.at}
		end
	end
	local list = {}
	for _, e in pairs(byGuid) do
		list[#list + 1] = e
	end
	list = K.rank(list)
	X.topCache[realm] = {at = now(), period = period, list = list}
	return list
end

local function nearBrazier(player)
	local p = X.brazierPos
	if not p then
		return false
	end
	local pos = player:getPosition()
	local range = cfg.brazier.range or 4
	return pos.z == p.z and math.abs(pos.x - p.x) <= range and math.abs(pos.y - p.y) <= range
end

function X.payload(player)
	local realm = realmOf(player)
	local g = X.goal(realm)
	local e = entryOf(player, realm)
	local top = topOf(realm, g.period)
	local rank
	for _, r in ipairs(top) do
		if r.guid == e.guid then
			rank = r.rank
		end
	end
	local w = X.currentWeek()
	return K.payload(cfg, {now = now(), period = g.period, finish = g.finish, progress = g.progress, buffs = buffsOf(realm),
		mods = w.mods, modSource = w.source, weekEnd = w.finish, entry = e, day = today(), rank = rank, top = top,
		near = nearBrazier(player), gold = player:getMoney() + (player.getBankBalance and player:getBankBalance() or 0),
		realm = realm, realmName = realmName(realm)})
end

function X.send(player)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = X.payload(player)}))
end

local function msg(player, text, ok)
	Chaos.send(player, OPCODE, "msg", {text = text, ok = ok and true or false})
end

function X.donate(player, gold)
	if not cfg.enabled then
		return msg(player, "The Brazier is cold.")
	end
	if isStaff(player) then
		return msg(player, "Staff donations do not count.")
	end
	if not nearBrazier(player) then
		return msg(player, "Stand next to the Great Brazier in the temple to give gold.")
	end
	local realm = realmOf(player)
	local e = entryOf(player, realm)
	local carried = player:getMoney() + (player.getBankBalance and player:getBankBalance() or 0)
	local take, why = K.donation(cfg, e, gold, today(), carried)
	if take <= 0 then
		return msg(player, why)
	end
	local paid = player.removeTotalMoney and player:removeTotalMoney(take) or player:removeMoney(take)
	if not paid then
		return msg(player, "You do not have that much gold (backpack and bank).")
	end
	local pts = X.contribute(player, "brazier", take)
	if X.brazierPos then
		Position(X.brazierPos.x, X.brazierPos.y, X.brazierPos.z):sendMagicEffect(CONST_ME_FIREAREA or 7)
	end
	log(string.format("%s gave %d gold to the Brazier (%d points)", player:getName(), take, pts))
	msg(player, string.format("The Brazier flares: %d gold given, +%d points.", take, pts), true)
	X.send(player)
end

-- ---------------------------------------------------------------- the Brazier object
local function placeBrazier()
	local b = cfg.brazier
	local pos
	if b.pos then
		pos = Position(b.pos.x, b.pos.y, b.pos.z)
	else
		local town = b.townId and Town(b.townId)
		local temple = town and town:getTemplePosition()
		for _, o in ipairs(temple and b.offsets or {}) do
			local p = Position(temple.x + o[1], temple.y + o[2], temple.z)
			local tile = Tile(p)
			if tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and not tile:getTopCreature()
					and not tile:hasFlag(TILESTATE_TELEPORT) and not tile:hasFlag(TILESTATE_FLOORCHANGE) then
				pos = p
				break
			end
		end
	end
	if not pos then
		log("no place for the Great Brazier (set brazier.pos in community_config.lua)")
		return nil
	end
	local id = ChaosDarkTiles and ChaosDarkTiles.id and ChaosDarkTiles.id(b.darkTile, b.itemId) or b.itemId
	local tile = Tile(pos)
	local item
	for _, it in ipairs(tile and tile:getItems() or {}) do
		if it:getActionId() == b.actionId then
			item = it
		end
	end
	item = item or Game.createItem(id, 1, pos)
	if item then
		item:setActionId(b.actionId)
		if b.description and ITEM_ATTRIBUTE_DESCRIPTION then
			item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, b.description)
		end
	end
	X.brazierPos = {x = pos.x, y = pos.y, z = pos.z}
	return pos
end

local brazier = Action()
function brazier.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	X.brazierPos = X.brazierPos or {x = item:getPosition().x, y = item:getPosition().y, z = item:getPosition().z}
	X.watch[player:getId()] = true
	Chaos.send(player, OPCODE, "brazier", {})
	X.send(player)
	return true
end
brazier:aid(cfg.brazier.actionId)
brazier:register()

-- ---------------------------------------------------------------- events
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if not source or not source.isMonster or not source:isMonster() or source:getMaster() then
		return exp
	end
	local mult = try("xp", X.xpMult, self, source) or 1
	if mult ~= 1 then
		return math.floor(exp * mult)
	end
	return exp
end
xpCb:register()

local kill = CreatureEvent("ChaosCommunityKill")
function kill.onKill(player, target)
	if not cfg.enabled or not player:isPlayer() or not target or not target:isMonster() or target:getMaster() then
		return true
	end
	try("kill", function()
		local src = K.source(cfg, "kill")
		local B = ChaosBestiary
		local cat = B and B.cat and B.cat()
		local name = (Chaos.monsterTypeName and Chaos.monsterTypeName(target) or target:getName()):lower()
		local entry = cat and cat.byKey and cat.byKey[name]
		if entry and (entry.level or 0) < player:getLevel() * (src.minLevelShare or 0) then
			return -- far below the character: nothing
		end
		X.contribute(player, "kill", 1, {tier = ChaosTierOf and ChaosTierOf(target) or "normal"})
	end)
	return true
end
kill:type("kill")
kill:register()

local login = CreatureEvent("ChaosCommunityLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCommunityExtended")
	player:registerEvent("ChaosCommunityLogout")
	player:registerEvent("ChaosCommunityKill")
	X.installHooks()
	if not cfg.enabled then
		return true
	end
	try("rewards", X.deliverRewards, player)
	local realm = realmOf(player)
	local g = X.goal(realm)
	local w = X.currentWeek()
	local lines = K.loginLines(cfg, g.progress, buffsOf(realm), w.mods, now(), g.finish)
	-- the week's modifiers are runtime events: the event calendar's login lines name them already
	local count = (cfg.week.announceOnLogin and not (ChaosEvents and Chaos.events and Chaos.events.announceOnLogin)) and #lines or 1
	for i = 1, count do
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE or MESSAGE_INFO_DESCR, lines[i])
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCommunityLogout")
function logout.onLogout(player)
	X.watch[player:getId()] = nil
	local e = X.entries[player:getGuid()]
	if e then
		if e.dirty then
			writeEntry(e)
		end
		X.entries[player:getGuid()] = nil
	end
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosCommunityExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "community." .. tostring(m.action), cfg.requestMs) then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	if m.action == "open" then
		X.watch[player:getId()] = true
		try("open", X.send, player)
	elseif m.action == "close" then
		X.watch[player:getId()] = nil
	elseif m.action == "donate" then
		try("donate", X.donate, player, Chaos.toInt(d.gold, 1, 2000000000) or 0)
	end
end
ext:type("extendedopcode")
ext:register()

local startup = GlobalEvent("ChaosCommunityStartup")
function startup.onStartup()
	X.ensureTables()
	X.installHooks()
	X.override = try("override", readOverride) or ""
	X.loadBuffs()
	try("finish old", X.finishOld)
	X.currentWeek(true)
	X.goal(0)
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `period` < %d", T.contrib,
		K.period(cfg, now() - (cfg.keepPeriods or 12) * (cfg.goal.periodDays or 7) * 86400)))
	local problems = K.validate(cfg)
	for _, p in ipairs(problems) do
		log("config: " .. p)
	end
	if cfg.enabled then
		addEvent(function()
			local pos = try("brazier", placeBrazier)
			if pos then
				log(string.format("the Great Brazier stands at %d, %d, %d", pos.x, pos.y, pos.z))
			end
		end, 1500)
	end
	X.started = true
	return true
end
startup:register()

local think = GlobalEvent("ChaosCommunityThink")
local lastFlush, lastPush = 0, 0
function think.onThink(interval)
	local t = now()
	try("week", X.currentWeek)
	for realm in pairs(X.goals) do
		try("goal", X.goal, realm) -- a new period finishes the old one
	end
	if t - lastFlush >= (cfg.flushSeconds or 60) then
		lastFlush = t
		try("flush", X.flush)
	end
	if t - lastPush >= (cfg.pushSeconds or 20) then
		lastPush = t
		pushAll()
	end
	return true
end
think:interval(5000)
think:register()

local shutdown = GlobalEvent("ChaosCommunityShutdown")
function shutdown.onShutdown()
	try("flush", X.flush)
	return true
end
shutdown:register()

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/community")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < (cfg.staffGroup or 4) then
		return true
	end
	local cmd, rest = tostring(param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local realm = realmOf(player)
	local reply
	if cmd == "modifier" then
		local w = K.week(now(), hour())
		if rest == "auto" or rest == "" then
			X.override = ""
			writeOverride("")
			X.currentWeek(true)
			reply = "The week's modifiers come from the seed again."
		else
			local keys, why = K.checkKeys(cfg, rest)
			if not keys then
				reply = why .. " Known: " .. (function()
					local list = {}
					for _, m in ipairs(cfg.week.pool) do list[#list + 1] = m.key end
					return table.concat(list, ", ")
				end)()
			else
				X.override = K.encodeOverride(w, keys)
				writeOverride(X.override)
				X.currentWeek(true)
				history(periodNow(), 0, "override", player:getName() .. " set the week's modifiers: " .. table.concat(keys, ", "))
				reply = "This week's modifiers: " .. table.concat(keys, ", ") .. "."
			end
		end
		pushAll()
	elseif cmd == "add" then
		local n = Chaos.toInt(rest, 1, 100000000)
		if n then
			local g = X.goal(realm)
			local before = g.progress
			g.progress, g.dirty = g.progress + n, true
			for _, i in ipairs(K.crossed(cfg, before, g.progress)) do
				X.unlockStage(realm, i, g.period)
			end
			reply = string.format("+%d points (realm %d).", n, realm)
		end
	elseif cmd == "stage" then
		local i = Chaos.toInt(rest, 1, #cfg.goal.stages)
		if i then
			X.unlockStage(realm, i, X.goal(realm).period)
			reply = "Stage " .. i .. " window opened."
		end
	end
	local g = X.goal(realm)
	local w = X.currentWeek()
	local names = {}
	for _, m in ipairs(w.mods) do
		names[#names + 1] = m.key
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, (reply and (reply .. "\n") or "") ..
		string.format("Community goal (realm %d, period %d): %d / %d points (%d%%). Week %d modifiers (%s): %s.\n" ..
			"/community [status | modifier <key>[,<key>] | modifier auto | add <points> | stage <n>]",
			realm, g.period, g.progress, cfg.goal.target, math.floor(K.pct(cfg, g.progress)), w.key, w.source,
			table.concat(names, ", ")))
	return false
end
talk:separator(" ")
talk:register()

-- Seasonal Journey: a fixed, chaptered checklist per season that walks each season character through the season's
-- content (roadmap: see ROADMAP.md "Seasonal Journey"). Chapters, objectives and rewards: season_journey_config.lua;
-- pure logic: season_journey_core.lua (tests/season_journey_test.lua); tables: sql/chaos_season_journey.sql (also
-- created here); client: game_season, the Journey tab. Overview: server/README.md "Seasonal Journey".
--
-- Per character, season realm only: a character of the running season walks its season's journey; every other
-- character (standard, migrated, staff) sees the journey of the running or next season as a preview. Progress is kept
-- per season (chaos_season_journey_stats, chaos_season_journey); a finished chapter's rewards are given once (the
-- chapter row is written before anything is given).
--
-- Where the counters come from (hooks installed at runtime, again after a /reload of the other script):
--   ChaosAchievements.progress / set   wrapped: each achievement counter that season_journey_config.lua `stats` lists
--   ChaosFactions.gain                 wrapped: faction_rep (gained), faction_rank (rank index after the gain)
--   ChaosCommunity.contribute          wrapped: community_points (points added)
--   ChaosOrbExchange.place             wrapped: orbx_orders (an order placed)
--   ChaosTower.recordRun               wrapped: tower_floor (floors cleared in the run)
--   ChaosSeasonJourney.emit            one guarded line in descent.lua (descent_*), dungeons.lua (dungeon_clears) and
--                                      atlas.lua (atlas_points)
--   level                              the character's level (advance event, login)
-- At login the counters are raised to the character's achievement counters, Rift Atlas points and Ember Descent
-- record (a season character starts fresh at the join, so those are its season's numbers): a journey added in the
-- middle of a season counts what the character did before.
--
-- Protocol (season opcode ChaosOpcodes.season = 246, JSON {action, data}; the season window, client game_season):
--   client -> server  journey                          the Journey tab opened (or refreshed)
--   server -> client  journey {header, chapters}       header and chapter summaries (no objectives)
--                     journeyChapter {index, objectives, rewards}   one chapter's objectives and rewards
--                     journeyDone {text, chapter?}     an objective / a chapter just completed (the open tab flashes)
-- Toasts: the notifications opcode (79) action "journey" (client game_chaosnotify).
-- Gods: /journey status [name] | stat name, stat, value | reset name
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not (ChaosSeason and ChaosSeason.realmOf and Chaos.seasonConfig) then
	dofile("data/scripts/chaos/season.lua")
end
dofile("data/scripts/chaos/season_journey_core.lua")

Chaos.seasonJourneyConfig = dofile("data/scripts/chaos/season_journey_config.lua")
local cfg = Chaos.seasonJourneyConfig
local K = ChaosSeasonJourneyCore
local S = ChaosSeason
local T = cfg.tables
local OPCODE = ChaosOpcodes.season or 246
local NOTIFY = ChaosOpcodes.notifications or 79

ChaosSeasonJourney = ChaosSeasonJourney or {}
local J = ChaosSeasonJourney
J.st = J.st or {} -- guid -> {season, stats, done, claimed, dirty}
J.titles = J.titles or {} -- guid -> list of titles from finished chapters (every season)
J.wrapped = J.wrapped or {} -- marker -> our wrapper (installed once per target function)
J.viewing = J.viewing or {} -- guid -> true while the client has the Journey tab open
J.pushAt = J.pushAt or {} -- guid -> pending progress push (throttle)

local function log(text)
	print("[Chaos journey] " .. text)
end

for _, p in ipairs(K.validate(cfg)) do
	log("season_journey_config.lua: " .. p)
end

local function now()
	return os.time()
end

local function staff(player)
	return player:getGroup():getId() >= cfg.staffGroup
end

-- ---------------------------------------------------------------- storage
local tablesReady = false
local function ensureTables()
	if tablesReady then
		return true
	end
	tablesReady = db.query("CREATE TABLE IF NOT EXISTS `" .. T.stats .. "` (`season` smallint(5) unsigned NOT NULL, " ..
		"`player_id` int(11) NOT NULL, `stat` varchar(32) NOT NULL, `value` bigint(20) NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`season`, `player_id`, `stat`), " ..
		"CONSTRAINT `chaos_season_journey_stats_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
		and db.query("CREATE TABLE IF NOT EXISTS `" .. T.entries .. "` (`season` smallint(5) unsigned NOT NULL, " ..
		"`player_id` int(11) NOT NULL, `entry` varchar(40) NOT NULL, `done_at` int(10) unsigned NOT NULL, " ..
		"PRIMARY KEY (`season`, `player_id`, `entry`), CONSTRAINT `chaos_season_journey_fk` FOREIGN KEY (`player_id`) " ..
		"REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true or false
	return tablesReady
end

local function writeStat(seasonId, guid, stat, value)
	db.query(string.format("INSERT INTO `%s` (`season`, `player_id`, `stat`, `value`, `updated_at`) VALUES (%d, %d, %s, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `updated_at` = VALUES(`updated_at`)", T.stats, seasonId, guid,
		db.escapeString(stat), value, now()))
end

local function writeEntry(seasonId, guid, entry, at)
	return db.query(string.format("INSERT IGNORE INTO `%s` (`season`, `player_id`, `entry`, `done_at`) VALUES (%d, %d, %s, %d)",
		T.entries, seasonId, guid, db.escapeString(entry), at))
end

function J.flush(guid)
	local st = J.st[guid]
	if not st or not next(st.dirty) then
		return
	end
	for stat in pairs(st.dirty) do
		writeStat(st.season, guid, stat, st.stats[stat] or 0)
	end
	st.dirty = {}
end

-- ---------------------------------------------------------------- who and which journey
-- the season a character walks a journey of now (its own running season with a journey), or nil
local function seasonOfGuid(guid)
	local season = S.current and S.current()
	if not season or not K.journeyOf(cfg, season.id) then
		return nil
	end
	if S.realmOfGuid(guid) ~= season.id then
		return nil
	end
	return season
end

local function flagsOf(guid)
	local f = S.modeFlagsOfGuid and S.modeFlagsOfGuid(guid) or {}
	return {ssf = f.ssf == true, hc = f.hc == true}
end

local function online(who)
	if type(who) == "userdata" then
		return who, who:getGuid()
	end
	local guid, name
	if type(who) == "table" then
		guid, name = tonumber(who.guid), who.name
	else
		guid = tonumber(who)
	end
	if not guid then
		return nil, nil
	end
	local p = name and Player(name)
	if p and p:getGuid() == guid then
		return p, guid
	end
	if J.st[guid] then
		for _, q in ipairs(Game.getPlayers()) do
			if q:getGuid() == guid then
				return q, guid
			end
		end
	end
	return nil, guid
end

-- ---------------------------------------------------------------- titles (every season's finished chapters)
local function loadTitles(guid)
	local list = {}
	if not ensureTables() then
		return list
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `season`, `entry`, `done_at` FROM `%s` WHERE `player_id` = %d AND " ..
		"`entry` LIKE 'c:%%'", T.entries, guid), {{"season", "n"}, {"entry", "s"}, {"done_at", "n"}})) do
		local j = K.journeyOf(cfg, r.season)
		local key = r.entry:sub(3)
		for _, ch in ipairs(j and j.chapters or {}) do
			if ch.key == key then
				for _, rw in ipairs(ch.rewards or {}) do
					if rw.kind == "title" then
						list[#list + 1] = {text = rw.title, key = "journey:" .. rw.title:lower(), at = r.done_at}
					end
				end
			end
		end
	end
	J.titles[guid] = list
	return list
end

-- ---------------------------------------------------------------- loading
local function retro(guid, st)
	-- achievement counters (in memory while the character is online)
	local A = ChaosAchievements
	local a = A and A.stats and A.stats[guid]
	if a then
		for stat in pairs(cfg.stats) do
			if a[stat] and K.merge(st.stats, "max", stat, a[stat]) then
				st.dirty[stat] = true
			end
		end
	end
	-- Rift Atlas points earned
	if ChaosAtlas and ChaosAtlas.get and ChaosAtlasCore and ChaosAtlasCore.earned and ChaosAtlasConfig then
		local ok, pts = pcall(function()
			local done = ChaosAtlas.get(guid).done
			return ChaosAtlasCore.earned(ChaosAtlasConfig, ChaosRiftConfig, done)
		end)
		if ok and tonumber(pts) and K.merge(st.stats, "max", "atlas_points", pts) then
			st.dirty.atlas_points = true
		end
	end
	-- Ember Descent record
	if ChaosDescent and ChaosDescent.rowOf then
		local ok, row = pcall(ChaosDescent.rowOf, guid)
		if ok and type(row) == "table" then
			for stat, v in pairs({descent_depth = row.best, descent_runs = row.runs, descent_clears = row.clears}) do
				if tonumber(v) and K.merge(st.stats, "max", stat, v) then
					st.dirty[stat] = true
				end
			end
		end
	end
end

function J.load(player)
	local guid = player:getGuid()
	J.st[guid] = nil
	local season = not staff(player) and seasonOfGuid(guid) or nil
	if not season or not ensureTables() then
		return nil
	end
	local st = {season = season.id, stats = {}, done = {}, claimed = {}, dirty = {}}
	for _, r in ipairs(Chaos.select(string.format("SELECT `stat`, `value` FROM `%s` WHERE `season` = %d AND `player_id` = %d",
		T.stats, season.id, guid), {{"stat", "s"}, {"value", "n"}})) do
		st.stats[r.stat] = r.value
	end
	local rows = Chaos.select(string.format("SELECT `entry`, `done_at` FROM `%s` WHERE `season` = %d AND `player_id` = %d",
		T.entries, season.id, guid), {{"entry", "s"}, {"done_at", "n"}})
	for _, r in ipairs(rows) do
		r.at = r.done_at
	end
	st.done, st.claimed = K.entriesToMaps(rows)
	retro(guid, st)
	J.st[guid] = st
	player:registerEvent("ChaosSeasonJourneyAdvance")
	return st
end

-- ---------------------------------------------------------------- rewards
local function giveStack(player, id, count)
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

local function giveReward(player, r, seasonId, chapterKey)
	if r.kind == "passxp" then
		local SP = ChaosSeasonPass
		local s = SP and SP.active and SP.active()
		if s and s.id == seasonId and SP.account and SP.addXp then
			local acc = SP.account(player:getAccountId())
			if acc.season == seasonId then
				SP.addXp(acc, r.amount, "journey " .. chapterKey)
				return K.rewardText(r)
			end
		end
		return nil -- no pass of this season runs
	elseif r.kind == "items" then
		local inbox = giveStack(player, r.id, r.count or 1)
		return K.rewardText(r) .. (inbox and " (inbox)" or "")
	elseif r.kind == "look" then
		if ChaosTransmog and ChaosTransmog.unlockLook then
			ChaosTransmog.unlockLook(player:getAccountId(), r.id)
		end
		return K.rewardText(r)
	elseif r.kind == "outfit" then
		for _, look in ipairs({r.male, r.female}) do
			if (r.addons or 0) > 0 then
				player:addOutfitAddon(look, r.addons)
			else
				player:addOutfit(look)
			end
		end
		return K.rewardText(r)
	elseif r.kind == "mount" then
		player:addMount(r.id)
		return K.rewardText(r)
	elseif r.kind == "title" then
		return K.rewardText(r)
	end
	return nil
end

local function toast(player, text)
	player:sendExtendedOpcode(NOTIFY, json.encode({action = "journey", message = text}))
end

-- ---------------------------------------------------------------- the window
local function clientIdOf(serverId)
	local it = ItemType(serverId)
	return it and it:getClientId() or nil
end

local function shownJourney(player)
	local guid = player:getGuid()
	local st = J.st[guid]
	if st then
		return K.journeyOf(cfg, st.season), st, nil
	end
	local t = now()
	local season = S.current and S.current() or nil
	if not season and S.upcoming then
		season = S.upcoming(Chaos.seasonConfig.seasons, t, S.ov)
	end
	return season and K.journeyOf(cfg, season.id) or nil, nil, season
end

-- send the header and the chapters (all, or only the list `only` of chapter indexes)
function J.send(player, only)
	local journey, st, season = shownJourney(player)
	if not journey then
		Chaos.send(player, OPCODE, "journey", {none = true})
		return
	end
	local ctx
	if st then
		ctx = {level = player:getLevel(), stats = st.stats, flags = flagsOf(player:getGuid()), done = st.done,
			claimed = st.claimed}
	else
		ctx = {level = player:getLevel(), stats = {}, flags = {}, done = {}, claimed = {}}
	end
	local opts = {preview = st == nil, clientId = clientIdOf, female = player:getSex() == PLAYERSEX_FEMALE}
	local header, chapters = K.view(journey, ctx, opts)
	if st then
		local f = ctx.flags
		header.mode = f.hc and f.ssf and "Hardcore Self-Found" or (f.hc and "Hardcore") or (f.ssf and "Self-Found") or nil
	else
		header.why = season and string.format("Preview: only %s characters walk this journey. Join with a fresh character.",
			season.name) or "Preview."
	end
	local summaries = {}
	for i, c in ipairs(chapters) do
		summaries[i] = {key = c.key, name = c.name, text = c.text, level = c.level, state = c.state, lockedWhy = c.lockedWhy,
			done = c.done, total = c.total}
	end
	header.chapters = summaries
	Chaos.send(player, OPCODE, "journey", header)
	for i, c in ipairs(chapters) do
		local wanted = only == nil
		for _, k in ipairs(only or {}) do
			wanted = wanted or k == i
		end
		if wanted then
			Chaos.send(player, OPCODE, "journeyChapter", {index = i, objectives = c.objectives, rewards = c.rewards})
		end
	end
end

-- progress bars of an open tab: at most one push every 2 s per character
local function pushLater(player)
	local guid = player:getGuid()
	if not J.viewing[guid] or J.pushAt[guid] then
		return
	end
	J.pushAt[guid] = true
	addEvent(function(cid)
		J.pushAt[guid] = nil
		local p = Player(cid)
		if p and J.viewing[guid] then
			local st = J.st[guid]
			local open = {}
			local journey = st and K.journeyOf(cfg, st.season)
			for i, ch in ipairs(journey and journey.chapters or {}) do
				if not st.claimed[ch.key] then
					open[#open + 1] = i
					break
				end
			end
			J.send(p, open)
		end
	end, 2000, player:getId())
end

-- ---------------------------------------------------------------- progress
-- objectives and chapters done now -> rows, toasts, rewards
function J.check(player)
	local guid = player:getGuid()
	local st = J.st[guid]
	if not st then
		return
	end
	local journey = K.journeyOf(cfg, st.season)
	local ctx = {level = player:getLevel(), stats = st.stats, flags = flagsOf(guid), done = st.done, claimed = st.claimed,
		now = now()}
	local objs, chapters = K.evaluate(journey, ctx)
	if #objs == 0 and #chapters == 0 then
		pushLater(player)
		return
	end
	for _, e in ipairs(objs) do
		writeEntry(st.season, guid, K.entryKey("objective", e.obj.key), ctx.now)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Journey objective done: %s (%s).", e.obj.text,
			e.chapter.name))
		toast(player, "Objective done: " .. e.obj.text)
		Chaos.send(player, OPCODE, "journeyDone", {text = e.obj.text})
	end
	for _, c in ipairs(chapters) do
		local ch = c.chapter
		-- the row first: a crash after it loses the reward rather than giving it twice
		writeEntry(st.season, guid, K.entryKey("chapter", ch.key), ctx.now)
		local got = {}
		for _, r in ipairs(ch.rewards or {}) do
			local ok, text = pcall(giveReward, player, r, st.season, ch.key)
			if ok and text then
				got[#got + 1] = text
			elseif not ok then
				log(string.format("reward of %s for %s failed: %s", ch.key, player:getName(), tostring(text)))
			end
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: chapter %d, %s, complete! Rewards: %s.",
			journey.name, c.index, ch.name, #got > 0 and table.concat(got, ", ") or "none"))
		toast(player, string.format("Chapter complete: %s", ch.name))
		Chaos.send(player, OPCODE, "journeyDone", {text = ch.name, chapter = c.index})
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_BLUE)
		for _, r in ipairs(ch.rewards or {}) do
			if r.kind == "title" then
				loadTitles(guid)
				if ChaosNameplate and ChaosNameplate.refresh then
					pcall(ChaosNameplate.refresh, player)
				end
			end
		end
	end
	if J.viewing[guid] then
		J.send(player)
	end
end

-- a counter of a character (a Player, a guid or {guid, name}): online -> memory and check; offline -> SQL.
-- mode: nil = the configured one; "max" for values reported as totals (ChaosAchievements.set)
function J.record(who, stat, value, mode)
	local configured = cfg.stats[stat]
	if not configured then
		return false
	end
	mode = mode or configured
	value = math.floor(tonumber(value) or 0)
	local player, guid = online(who)
	if not guid then
		return false
	end
	local st = J.st[guid]
	if player and st then
		if K.merge(st.stats, mode, stat, value) then
			st.dirty[stat] = true
			J.check(player)
			return true
		end
		return false
	end
	if player then
		return false -- online but walks no journey
	end
	local season = seasonOfGuid(guid)
	if not season or not ensureTables() or (mode == "add" and value <= 0) then
		return false
	end
	local expr = mode == "max" and "GREATEST(`value`, VALUES(`value`))" or "`value` + VALUES(`value`)"
	db.query(string.format("INSERT INTO `%s` (`season`, `player_id`, `stat`, `value`, `updated_at`) VALUES (%d, %d, %s, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = %s, `updated_at` = VALUES(`updated_at`)", T.stats, season.id, guid,
		db.escapeString(stat), value, now(), expr))
	return true
end

-- the API of other scripts: if ChaosSeasonJourney and ChaosSeasonJourney.emit then pcall(..., who, stat, value) end
function J.emit(who, stat, value, mode)
	local ok, err = pcall(J.record, who, stat, value, mode)
	if not ok then
		log("emit " .. tostring(stat) .. ": " .. tostring(err))
	end
	return ok and err
end

-- ---------------------------------------------------------------- hooks into other systems
local function wrap(tbl, name, marker, make)
	if type(tbl) ~= "table" or type(tbl[name]) ~= "function" or tbl[name] == J.wrapped[marker] then
		return
	end
	J.wrapped[marker] = make(tbl[name])
	tbl[name] = J.wrapped[marker]
end

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		log("hook: " .. tostring(err))
	end
end

function J.installHooks()
	wrap(ChaosAchievements, "progress", "achProgress", function(orig)
		return function(who, key, amount)
			local r = orig(who, key, amount)
			if cfg.stats[key] then
				safe(J.record, who, key, amount == nil and 1 or amount)
			end
			return r
		end
	end)
	wrap(ChaosAchievements, "set", "achSet", function(orig)
		return function(who, key, value)
			local r = orig(who, key, value)
			if cfg.stats[key] then
				safe(J.record, who, key, value, "max")
			end
			return r
		end
	end)
	wrap(ChaosFactions, "gain", "factionGain", function(orig)
		return function(player, key, amount, source, quiet)
			local res = orig(player, key, amount, source, quiet)
			if type(res) == "table" and player then
				if (tonumber(res.gained) or 0) > 0 then
					safe(J.record, player, "faction_rep", res.gained)
				end
				if tonumber(res.rankAfter) then
					safe(J.record, player, "faction_rank", res.rankAfter, "max")
				end
			end
			return res
		end
	end)
	wrap(ChaosCommunity, "contribute", "communityContribute", function(orig)
		return function(player, key, units, opts)
			local gained = orig(player, key, units, opts)
			if player and (tonumber(gained) or 0) > 0 then
				safe(J.record, player, "community_points", gained)
			end
			return gained
		end
	end)
	wrap(ChaosOrbExchange, "place", "orbxPlace", function(orig)
		return function(player, d)
			local ok = orig(player, d)
			if ok == true and player then
				safe(J.record, player, "orbx_orders", 1)
			end
			return ok
		end
	end)
	wrap(ChaosTower, "recordRun", "towerRun", function(orig)
		return function(player, floorsCleared, seconds)
			local r = orig(player, floorsCleared, seconds)
			if player then
				safe(J.record, player, "tower_floor", tonumber(floorsCleared) or 0, "max")
			end
			return r
		end
	end)
end

-- name plate titles: the title rewards of every season's finished chapters
local function registerTitles()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("journey", function(player)
			return J.titles[player:getGuid()]
		end)
	end
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosSeasonJourneyStartup")
function startup.onStartup()
	ensureTables()
	J.installHooks()
	registerTitles()
	return true
end
startup:register()

local think = GlobalEvent("ChaosSeasonJourneyFlush")
function think.onThink(interval)
	J.installHooks()
	for guid in pairs(J.st) do
		J.flush(guid)
		-- a season that ended (or a Hardcore fall) since the login: the journey stops
		if not seasonOfGuid(guid) then
			J.st[guid] = nil
		end
	end
	return true
end
think:interval(cfg.flushSeconds * 1000)
think:register()

local shutdown = GlobalEvent("ChaosSeasonJourneyShutdown")
function shutdown.onShutdown()
	for guid in pairs(J.st) do
		J.flush(guid)
	end
	return true
end
shutdown:register()

local login = CreatureEvent("ChaosSeasonJourneyLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSeasonJourneyExtended")
	local guid = player:getGuid()
	J.viewing[guid] = nil
	loadTitles(guid)
	-- after the season, the achievements and the atlas loaded this character
	addEvent(function(cid)
		local p = Player(cid)
		if p and J.load(p) then
			J.check(p)
		end
	end, 1500, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSeasonJourneyLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	J.flush(guid)
	J.st[guid], J.viewing[guid], J.pushAt[guid], J.titles[guid] = nil, nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

local advance = CreatureEvent("ChaosSeasonJourneyAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel and J.st[player:getGuid()] then
		J.check(player)
	end
	return true
end
advance:type("advance")
advance:register()

local ext = CreatureEvent("ChaosSeasonJourneyExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "journey" then
		if J.st[player:getGuid()] then
			J.check(player)
		end
		J.viewing[player:getGuid()] = true
		J.send(player)
	elseif msg.action == "journeyClose" then
		J.viewing[player:getGuid()] = nil
	end
end
ext:type("extendedopcode")
ext:register()

-- ---------------------------------------------------------------- gods
local function target(name)
	local p = Player(name)
	if not p then
		return nil, "Character not online: " .. tostring(name)
	end
	return p
end

local function status(player, p)
	local st = J.st[p:getGuid()]
	if not st then
		return p:getName() .. " walks no journey now (not a character of a running season with a journey, or staff)."
	end
	local j = K.journeyOf(cfg, st.season)
	local n, parts = 0, {}
	for _, ch in ipairs(j.chapters) do
		if st.claimed[ch.key] then
			n = n + 1
		end
	end
	for stat, v in pairs(st.stats) do
		parts[#parts + 1] = stat .. "=" .. v
	end
	table.sort(parts)
	return string.format("%s: %s, %d / %d chapters. %s", p:getName(), j.name, n, #j.chapters, table.concat(parts, " "))
end

local talk = TalkAction("/journey")
function talk.onSay(player, words, param)
	if player:getAccountType() < (ACCOUNT_TYPE_GOD or 5) then
		return true
	end
	local args = {}
	for part in (param or ""):gmatch("[^,]+") do
		args[#args + 1] = part:gsub("^%s+", ""):gsub("%s+$", "")
	end
	local cmd = (args[1] or "status"):match("^(%S+)") or "status"
	local rest = (args[1] or ""):match("^%S+%s+(.+)$")
	if cmd == "status" then
		local p = rest and target(rest) or player
		player:sendTextMessage(MESSAGE_INFO_DESCR, p and status(player, p) or ("Not online: " .. tostring(rest)))
	elseif cmd == "stat" and rest and args[2] and args[3] then
		local p, why = target(rest)
		if not p then
			player:sendTextMessage(MESSAGE_INFO_DESCR, why)
		elseif not cfg.stats[args[2]] then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "Unknown journey stat " .. args[2] .. ".")
		else
			local st = J.st[p:getGuid()]
			if st then
				st.stats[args[2]] = math.max(0, math.floor(tonumber(args[3]) or 0))
				st.dirty[args[2]] = true
				J.check(p)
				J.flush(p:getGuid())
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, status(player, p))
		end
	elseif cmd == "reset" and rest then
		local p, why = target(rest)
		local st = p and J.st[p:getGuid()]
		if not st then
			player:sendTextMessage(MESSAGE_INFO_DESCR, why or (rest .. " walks no journey now."))
		else
			db.query(string.format("DELETE FROM `%s` WHERE `season` = %d AND `player_id` = %d", T.stats, st.season, p:getGuid()))
			db.query(string.format("DELETE FROM `%s` WHERE `season` = %d AND `player_id` = %d", T.entries, st.season, p:getGuid()))
			J.st[p:getGuid()] = nil
			J.load(p)
			player:sendTextMessage(MESSAGE_INFO_DESCR, "Journey reset (rewards already given stay): " .. status(player, p))
		end
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/journey status [name] | stat name, stat, value | reset name")
	end
	return false
end
talk:separator(" ")
talk:register()

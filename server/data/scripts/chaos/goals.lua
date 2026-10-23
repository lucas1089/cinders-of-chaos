-- Next Goals (client game_goals, extended opcode ChaosOpcodes.goals = 178): for EVERY character the goals of its level
-- band, why each matters, where to go (a button: a window, a mark on the map at an NPC, a hunt or the temple), the
-- progress, a small reward and the expected effort; the gear path and the hunts of the band; the next unlocks. A
-- compact tracker on screen shows the first open goals. Season characters see it beside the Seasonal Journey.
-- Data: goals_config.lua; pure logic: goals_core.lua (tests: server/tests/goals_test.lua); table:
-- server/sql/chaos_goals.sql (also created here). Overview: server/README.md "Next Goals". Owner rule: no talkaction;
-- the panel opens from the client menu (Adventure > Next Goals) and its tracker.
--
-- Progress comes from what the other systems already count, read live, with no edits of them:
--   ChaosAchievements.stats[guid]      every achievement counter (kills, rifts, bosses, dungeons, trials, ...)
--   ChaosAchievements.progress / set   wrapped: a changed counter checks the character's goals (kills, magic monsters,
--                                      bounty contracts through ChaosLeaderboard.record "bounty", ...)
--   onAdvance (level)                  the same check: "Reach level N" and the goals the level unlocks
--   ChaosPassiveTree.listeners         a spent passive point
-- Live refresh (G.schedule): a change waits checkMs, then the goals are checked and the tracker (and the panel while it
-- is open) is pushed when what it shows changed; at most one run every pushMs per character, changes in between merge.
--   own stats (goals_config.lua own)   ChaosFactions.gain, ChaosConquest.grant, ChaosTower.recordRun and
--                                      ChaosSeasonJourney.emit wrapped; ChaosPassiveTree.hasAllocation probed
--   ChaosGoals.emit(who, stat, value)  for other scripts: if ChaosGoals and ChaosGoals.emit then ... end
-- Rewards: experience (a share of the next level), gold to the bank and, when ChaosConquest runs, Conquest Tokens
-- (ChaosConquest.grant(player, "goals", n): given only while its config has a "goals" source).
--
-- Protocol (JSON {action, data}):
--   client -> server  open | close | tracker
--   server -> client  goals {header, goals, upcoming, gear, hunts, hereWhere}   (Chaos.sendChunked)
--                     tracker {rows = [{key, title, progress, target}]}
--                     done {text}
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/goals_core.lua")
if not ChaosFirstHourCore or not ChaosFirstHourCore.pickHunts then
	dofile("data/scripts/chaos/firsthour_core.lua")
end
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end

Chaos.goalsConfig = dofile("data/scripts/chaos/goals_config.lua")
local cfg = Chaos.goalsConfig
local K = ChaosGoalsCore
local OPCODE = ChaosOpcodes.goals or cfg.opcode
local NOTIFY = ChaosOpcodes.notifications or 79
local TABLE = cfg.table

ChaosGoals = ChaosGoals or {}
local G = ChaosGoals
G.st = G.st or {} -- guid -> {done, stats, dirty, ready}
G.viewing = G.viewing or {} -- guid -> true while the panel is open

local function log(text)
	print("[Chaos goals] " .. text)
end

for _, p in ipairs(K.validate(cfg)) do
	log("goals_config.lua: " .. p)
end

local function now()
	return os.time()
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ---------------------------------------------------------------- storage
local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (`player_id` int(11) NOT NULL, " ..
			"`entry` varchar(40) NOT NULL, `value` bigint(20) NOT NULL DEFAULT 0, `at` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`player_id`, `entry`), CONSTRAINT `chaos_goals_fk` FOREIGN KEY (`player_id`) REFERENCES " ..
			"`players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true or false
	end
	return tableReady
end

local function writeRow(guid, entry, value, at)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `entry`, `value`, `at`) VALUES (%d, %s, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `at` = VALUES(`at`)", TABLE, guid, db.escapeString(entry),
		math.floor(value), at))
end

function G.flush(guid)
	local st = G.st[guid]
	if not st or not next(st.dirty) then
		return
	end
	for stat in pairs(st.dirty) do
		writeRow(guid, "s:" .. stat, st.stats[stat] or 0, now())
	end
	st.dirty = {}
end

-- ---------------------------------------------------------------- the character's context
local function staff(player)
	return player:getGroup():getId() >= cfg.staffGroup
end

local function systems()
	local out = {}
	local function mark(item)
		if item.requires and rawget(_G, item.requires) ~= nil then
			out[item.requires] = true
		end
	end
	for _, g in ipairs(cfg.goals) do
		mark(g)
	end
	for _, b in ipairs(cfg.bands) do
		for _, g in ipairs(b.gear or {}) do
			mark(g)
		end
	end
	return out
end

function G.langOf(player)
	if ChaosFirstHour and ChaosFirstHour.langOf then
		local ok, l = pcall(ChaosFirstHour.langOf, player)
		if ok and l then
			return K.lang(l)
		end
	end
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		if ok then
			return K.lang(l)
		end
	end
	return "en"
end

local function seasonName(player)
	local J = ChaosSeasonJourney
	local st = J and J.st and J.st[player:getGuid()]
	if not st then
		return nil
	end
	local journey = ChaosSeasonJourneyCore and Chaos.seasonJourneyConfig
		and ChaosSeasonJourneyCore.journeyOf(Chaos.seasonJourneyConfig, st.season)
	return journey and journey.name or "Journey"
end

-- the counters: own stats first, then the achievement counters (in memory while the character is online)
local function statsOf(guid, st)
	return setmetatable({}, {__index = function(_, k)
		local v = st.stats[k]
		if v ~= nil then
			return v
		end
		local A = ChaosAchievements
		local a = A and A.stats and A.stats[guid]
		return a and a[k] or nil
	end})
end

local function ctxOf(player, st)
	local guid = player:getGuid()
	return {level = player:getLevel(), stats = statsOf(guid, st), done = st.done, systems = systems(),
		season = seasonName(player), now = now()}
end

-- ---------------------------------------------------------------- where: positions on the map
local function temple(player)
	local town = player:getTown()
	return town and town:getTemplePosition() or nil
end

local function plainPos(p)
	return p and {x = p.x, y = p.y, z = p.z} or nil
end

function G.resolver(player, lang)
	local T = cfg.texts
	return function(w)
		if w.k == "npc" then
			local ok, c = pcall(Creature, w.name)
			if ok and c and c.isNpc and c:isNpc() then
				return plainPos(c:getPosition()), w.name
			end
			return plainPos(temple(player)), K.text(T.temple, lang)
		elseif w.k == "temple" then
			return plainPos(temple(player)), K.text(T.temple, lang)
		elseif w.k == "hunts" then
			local P = ChaosPoi
			if P and P.all and P.key then
				local center = temple(player) or player:getPosition()
				local list = ChaosFirstHourCore.pickHunts(P.all, {}, P.key, center, player:getLevel(),
					{count = 1, slack = 5, range = 2000, floorCost = 40})
				if list[1] then
					return plainPos(list[1]), ChaosFirstHourCore.shortName(list[1])
				end
			end
			return nil, K.text(T.hunts, lang)
		elseif w.k == "plan" then
			local idx = ChaosHuntTeleports and ChaosHuntTeleports.idx
			for _, e in ipairs(idx and idx.list or {}) do
				if e.id == w.id then
					return plainPos(e.teleport), e.name
				end
			end
			return plainPos(cfg.room), K.text(T.room, lang)
		elseif w.k == "room" then
			return plainPos(cfg.room), K.text(T.room, lang)
		end
		return nil
	end
end

-- ---------------------------------------------------------------- loading
-- the probes: values the other systems keep in the database (read at login and when the panel opens)
local function probe(player, st)
	local function set(stat, v)
		if tonumber(v) and K.merge(st.stats, "max", stat, v) then
			st.dirty[stat] = true
		end
	end
	if ChaosPassiveTree and ChaosPassiveTree.hasAllocation then
		local ok, has = pcall(ChaosPassiveTree.hasAllocation, player)
		if ok and has then
			set("passive_spent", 1)
		end
	end
	local guid = player:getGuid()
	if ChaosDescent and ChaosDescent.rowOf then
		local ok, row = pcall(ChaosDescent.rowOf, guid)
		if ok and type(row) == "table" then
			set("descent_depth", row.best)
			set("descent_runs", row.runs)
			set("descent_clears", row.clears)
		end
	end
	if ChaosAtlas and ChaosAtlas.get and ChaosAtlasCore and ChaosAtlasCore.earned and ChaosAtlasConfig then
		local ok, pts = pcall(function()
			return ChaosAtlasCore.earned(ChaosAtlasConfig, ChaosRiftConfig, ChaosAtlas.get(guid).done)
		end)
		if ok then
			set("atlas_points", pts)
		end
	end
end

function G.load(player)
	local guid = player:getGuid()
	G.st[guid] = nil
	if not ensureTable() then
		return nil
	end
	local rows = Chaos.select(string.format("SELECT `entry`, `value`, `at` FROM `%s` WHERE `player_id` = %d", TABLE, guid),
		{{"entry", "s"}, {"value", "n"}, {"at", "n"}})
	local done, stats = K.rowsToState(rows)
	local st = {done = done, stats = stats, dirty = {}, fresh = next(done) == nil}
	G.st[guid] = st
	probe(player, st)
	return st
end

-- ---------------------------------------------------------------- rewards
local function giveReward(player, g, lang)
	local rw = K.reward(cfg, g, player:getLevel())
	local T, parts = cfg.texts, {}
	if rw.xp > 0 then
		player:addExperience(rw.xp, true)
		parts[#parts + 1] = string.format(K.text(T.xp, lang), K.int(rw.xp))
	end
	if rw.gold > 0 then
		player:setBankBalance(player:getBankBalance() + rw.gold)
		parts[#parts + 1] = string.format(K.text(T.gold, lang), K.int(rw.gold))
	end
	if rw.tokens > 0 and ChaosConquest and ChaosConquest.grant and ChaosConquestConfig
		and ChaosConquestConfig.sources and ChaosConquestConfig.sources.goals then
		local ok, given = pcall(ChaosConquest.grant, player, "goals", rw.tokens, "goal " .. g.key)
		if ok and (tonumber(given) or 0) > 0 then
			parts[#parts + 1] = string.format(K.text(T.tokens, lang), tonumber(given))
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or K.text(T.none, lang)
end

local function toast(player, text)
	if json then
		player:sendExtendedOpcode(NOTIFY, json.encode({action = "journey", message = text}))
	end
end

-- ---------------------------------------------------------------- the panel and the tracker
function G.send(player)
	local st = G.st[player:getGuid()]
	if not st then
		return
	end
	local lang = G.langOf(player)
	local payload = K.view(cfg, ctxOf(player, st), lang, G.resolver(player, lang))
	st.panelSig = K.panelSig(payload, lang)
	local ok, text = pcall(json.encode, {action = "goals", data = payload})
	if ok then
		Chaos.sendChunked(player, OPCODE, text)
	end
end

local function trackerSig(rows, lang)
	return lang .. "|" .. K.sig(rows)
end

function G.sendTracker(player)
	local st = G.st[player:getGuid()]
	if not st then
		return
	end
	local lang = G.langOf(player)
	local rows = K.tracker(cfg, ctxOf(player, st), lang, cfg.tracked)
	st.trackerSig = trackerSig(rows, lang)
	Chaos.send(player, OPCODE, "tracker", {rows = rows})
end

-- the live refresh: the tracker, and the panel while it is open, go out again only when what they show changed
-- (the level, a counter, a goal done and replaced by the next one). G.schedule calls it at most every pushMs.
function G.refresh(player)
	local guid = player:getGuid()
	local st = G.st[guid]
	if not st then
		return
	end
	local lang = G.langOf(player)
	local view = K.view(cfg, ctxOf(player, st), lang, nil)
	local rows = K.trackerOf(view, cfg.tracked)
	local sig = trackerSig(rows, lang)
	if sig ~= st.trackerSig then
		st.trackerSig = sig
		Chaos.send(player, OPCODE, "tracker", {rows = rows})
	end
	if G.viewing[guid] and K.panelSig(view, lang) ~= st.panelSig then
		G.send(player)
	end
end

-- ---------------------------------------------------------------- progress
-- rewards the goals done now (messages, toast, "done"); the tracker and the panel follow through G.refresh
function G.check(player)
	local guid = player:getGuid()
	local st = G.st[guid]
	if not st or staff(player) then
		return
	end
	local ctx = ctxOf(player, st)
	if st.fresh then
		-- the first load: what the character did in the bands below its own is marked done, without a reward
		st.fresh = false
		for _, key in ipairs(K.retro(cfg, ctx)) do
			writeRow(guid, "g:" .. key, 2, ctx.now)
		end
	end
	local list = K.evaluate(cfg, ctx)
	if #list == 0 then
		return
	end
	local lang = G.langOf(player)
	for _, g in ipairs(list) do
		-- the row first: a crash after it loses the reward rather than giving it twice
		writeRow(guid, "g:" .. g.key, 1, ctx.now)
		local got = giveReward(player, g, lang)
		local title = K.text(g.title, lang)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(K.text(cfg.texts.done, lang), title, got))
		toast(player, string.format(K.text(cfg.texts.doneShort, lang), title))
		Chaos.send(player, OPCODE, "done", {text = title})
	end
end

-- a counter or the level changed: check and refresh after checkMs, at most every pushMs; the changes in between
-- merge into the queued run (the queue lives in the loaded state: a relog starts a new one)
function G.schedule(player)
	if not player or type(player) ~= "userdata" then
		return
	end
	local st = G.st[player:getGuid()]
	if not st then
		return
	end
	st.push = st.push or {}
	local push = st.push
	local delay = K.queuePush(push, nowMs(), cfg.pushMs or 1000, cfg.checkMs or 250)
	if not delay then
		return
	end
	addEvent(function(cid)
		K.pushed(push, nowMs())
		local p = Player(cid)
		if not p or G.st[p:getGuid()] ~= st then
			return
		end
		local ok, err = pcall(G.check, p)
		if not ok then
			log("check: " .. tostring(err))
		end
		ok, err = pcall(G.refresh, p)
		if not ok then
			log("refresh: " .. tostring(err))
		end
	end, delay, player:getId())
end

local function playerOf(who)
	if type(who) == "userdata" then
		return who
	end
	local guid = type(who) == "table" and tonumber(who.guid) or tonumber(who)
	if guid and G.st[guid] then
		for _, p in ipairs(Game.getPlayers()) do
			if p:getGuid() == guid then
				return p
			end
		end
	end
	return nil
end

-- an own stat of an online character (offline: dropped; the probes catch up at the next login)
function G.record(who, stat, value, mode)
	local configured = cfg.own[stat]
	if not configured then
		return false
	end
	local player = playerOf(who)
	local st = player and G.st[player:getGuid()]
	if not st then
		return false
	end
	if K.merge(st.stats, mode or configured, stat, value) then
		st.dirty[stat] = true
		G.schedule(player)
		return true
	end
	return false
end

-- the API of other scripts: if ChaosGoals and ChaosGoals.emit then ChaosGoals.emit(player, stat, value) end
function G.emit(who, stat, value, mode)
	local ok, res = pcall(G.record, who, stat, value, mode)
	if not ok then
		log("emit " .. tostring(stat) .. ": " .. tostring(res))
	end
	return ok and res
end

-- ---------------------------------------------------------------- hooks
local function wrap(tbl, name, marker, after)
	ChaosWrapChain.wrap(tbl, name, "goals_" .. marker, after, function(e) log("hook: " .. e) end)
end

function G.installHooks()
	wrap(ChaosAchievements, "progress", "achProgress", function(res, who)
		G.schedule(playerOf(who))
	end)
	wrap(ChaosAchievements, "set", "achSet", function(res, who)
		G.schedule(playerOf(who))
	end)
	wrap(ChaosFactions, "gain", "factionGain", function(res, player)
		local r = res[1]
		if type(r) == "table" and tonumber(r.rankAfter) then
			G.record(player, "faction_rank", r.rankAfter, "max")
		end
	end)
	wrap(ChaosConquest, "grant", "conquestGrant", function(res, player, key)
		local given = tonumber(res[1]) or 0
		if given > 0 then
			G.record(player, "conquest_earned", given)
		end
		if type(key) == "string" and key:find("^pocketboss") then
			G.record(player, "pocket_kills", 1)
		end
	end)
	wrap(ChaosTower, "recordRun", "towerRun", function(res, player, floorsCleared)
		G.record(player, "tower_floor", tonumber(floorsCleared) or 0, "max")
	end)
	wrap(ChaosSeasonJourney, "emit", "journeyEmit", function(res, who, stat, value, mode)
		if cfg.own[stat] then
			G.record(who, stat, value, mode)
		end
	end)
	-- the passive tree calls its listeners after every apply (login, save, reset): a spent point, live
	local PT = ChaosPassiveTree
	if PT and type(PT.listeners) == "table" and PT.hasAllocation then
		local there = false
		for _, fn in ipairs(PT.listeners) do
			there = there or fn == G.onPassiveApply
		end
		if not there then
			PT.listeners[#PT.listeners + 1] = G.onPassiveApply
		end
	end
end

function G.onPassiveApply(player)
	if not player or not G.st[player:getGuid()] then
		return
	end
	local ok, has = pcall(ChaosPassiveTree.hasAllocation, player)
	if ok and has then
		G.record(player, "passive_spent", 1, "max")
	end
end

-- ---------------------------------------------------------------- events
if GlobalEvent then
	local startup = GlobalEvent("ChaosGoalsStartup")
	function startup.onStartup()
		ensureTable()
		G.installHooks()
		return true
	end
	startup:register()

	local think = GlobalEvent("ChaosGoalsFlush")
	function think.onThink()
		G.installHooks()
		for guid in pairs(G.st) do
			G.flush(guid)
		end
		return true
	end
	think:interval(60000)
	think:register()

	local shutdown = GlobalEvent("ChaosGoalsShutdown")
	function shutdown.onShutdown()
		for guid in pairs(G.st) do
			G.flush(guid)
		end
		return true
	end
	shutdown:register()
end

if CreatureEvent then
	local login = CreatureEvent("ChaosGoalsLogin")
	function login.onLogin(player)
		if not cfg.enabled then
			return true
		end
		player:registerEvent("ChaosGoalsExtended")
		player:registerEvent("ChaosGoalsAdvance")
		G.viewing[player:getGuid()] = nil
		-- after the achievements loaded this character (their counters are the goals' progress)
		addEvent(function(cid)
			local p = Player(cid)
			if p and G.load(p) then
				pcall(G.check, p)
				G.sendTracker(p)
			end
		end, 2000, player:getId())
		return true
	end
	login:type("login")
	login:register()

	local logout = CreatureEvent("ChaosGoalsLogout")
	function logout.onLogout(player)
		local guid = player:getGuid()
		G.flush(guid)
		G.st[guid], G.viewing[guid] = nil, nil
		return true
	end
	logout:type("logout")
	logout:register()

	local advance = CreatureEvent("ChaosGoalsAdvance")
	function advance.onAdvance(player, skill, oldLevel, newLevel)
		if skill ~= SKILL_LEVEL or newLevel <= oldLevel or not G.st[player:getGuid()] then
			return true
		end
		G.schedule(player)
		local bi = K.bandEntered(cfg, oldLevel, newLevel)
		if bi then
			local lang = G.langOf(player)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(K.text(cfg.texts.newBand, lang), cfg.bands[bi].from,
				K.text(cfg.bands[bi].name, lang)))
		end
		return true
	end
	advance:type("advance")
	advance:register()

	local ext = CreatureEvent("ChaosGoalsExtended")
	function ext.onExtendedOpcode(player, opcode, buffer)
		if opcode ~= OPCODE then
			return
		end
		local msg = Chaos.decode(buffer)
		if not msg or type(msg.action) ~= "string" then
			return
		end
		if Chaos.limited and Chaos.limited(player, "goals." .. msg.action, cfg.requestMs) then
			return
		end
		local guid = player:getGuid()
		if msg.action == "open" then
			-- only a character loaded at its login (goals.lua login event): never a stale or logged out one
			local st = G.st[guid]
			if st then
				probe(player, st)
				pcall(G.check, player)
				G.viewing[guid] = true
				G.send(player)
				pcall(G.refresh, player) -- the tracker, when the probes or the check changed it
			end
		elseif msg.action == "close" then
			G.viewing[guid] = nil
		elseif msg.action == "tracker" then
			G.sendTracker(player)
			if ChaosAscensionTracker and ChaosAscensionTracker.sent then
				ChaosAscensionTracker.sent[player:getId()] = nil -- the next sweep sends the ascension rows too
			end
		end
	end
	ext:type("extendedopcode")
	ext:register()
end

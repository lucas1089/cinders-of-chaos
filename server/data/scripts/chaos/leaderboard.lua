-- Leaderboards (client game_leaderboard, extended opcode ChaosOpcodes.leaderboard)
--
-- Weekly boards (Chaos.leaderboardConfig.boards): World Boss (damage dealt to world bosses, kills participated; fed by
-- worldboss.lua), Bounty Hunter (contracts completed; bounty.lua) and Rifts (highest tier; the rift scripts call
-- ChaosLeaderboard.record). They reset on Monday at resetHour (the bounty board's week rule). At the reset the top 3 of
-- every weekly board get the board's title for the week that starts (look text, the board) and orbs in the inbox
-- (players offline at the reset get them at their next login), and the winners are broadcast.
-- All-time Class Ladder: highest level per class, read from the players table (cached cacheSeconds), grouped by base
-- class (Chaos.classes.baseOf, else the vocation's demotion chain); class names come from Vocation(id):getName().
--
-- Public API (any script):
--   ChaosLeaderboard.record(board, who, value, mode)
--       board  "worldboss" | "bounty" | "rift" (a key of Chaos.leaderboardConfig.boards)
--       who    a Player, a player guid, or {guid = n, name = s}
--       value  integer >= 0; mode "add" (sum, the default of worldboss/bounty) or "max" (best, the default of rift);
--              nil = the board's mode. Every call also counts one (kill / contract / run) in the board's count column.
--       -> the player's entry {value, count, at} of this week, or nil (unknown board / player)
--   ChaosLeaderboard.recordShares(shares)   world boss shares (worldboss.lua computeShares) -> record("worldboss", ...)
--   ChaosLeaderboard.titlesOf(guid)         titles the player holds this week: {{title, rank, rankName, board}}
-- State: chaos_leaderboard (scores per board, week, player), chaos_leaderboard_titles (the top 3 of each ended week,
-- with the reward state), server_config chaos_leaderboard_reset (the last processed week). The current week's scores
-- are kept in memory (loaded at startup and at the week change) and written through to the DB.
--
-- Protocol (JSON {action, data}):
--   client -> server  open {board?} | get {board, group?}
--   server -> client  meta {open, boards = [{key, name, weekly, value, count, title, info}], groups = [{key, name}]}
--                     board {key, group, week, resetIn, rows = [{rank, name, value, count, level, vocation, title}],
--                            own = {rank, value, count} | nil, champions = [{rank, rankName, name, value, title}],
--                            total}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/leaderboard_core.lua")

Chaos.leaderboardConfig = dofile("data/scripts/chaos/leaderboard_config.lua")
local cfg = Chaos.leaderboardConfig
local LB = ChaosLeaderboard
local OPCODE = ChaosOpcodes.leaderboard or 229
local T_SCORES, T_TITLES = cfg.tables.scores, cfg.tables.titles

LB.offset = LB.offset or 0 -- seconds added to os.time() (staff test helper: /leaderboard shift <days>)
LB.current = LB.current or nil -- {week, scores = {[board] = {[guid] = entry}}}
LB.ranked = {} -- board -> ranked list (cleared when the board changes)
LB.held = LB.held or {week = 0, awards = {}, byGuid = {}} -- titles held this week (awarded for the previous week)
LB.ladder = {} -- base id -> {at, rows}

local boardByKey = {}
for _, b in ipairs(cfg.boards) do
	boardByKey[b.key] = b
end

function LB.now()
	return os.time() + LB.offset
end

local function weekNow()
	return LB.week(LB.now(), cfg.resetHour)
end

local function log(text)
	print("[Chaos leaderboard] " .. text)
end

-- ---------------------------------------------------------------- persistence
local function loadScores(week)
	local scores = {}
	for _, b in ipairs(cfg.boards) do
		scores[b.key] = {}
	end
	local rows = Chaos.select(string.format("SELECT s.`board`, s.`player_id`, s.`value`, s.`count`, s.`updated_at`, " ..
		"p.`name`, p.`group_id`, p.`vocation` FROM `%s` s JOIN `players` p ON p.`id` = s.`player_id` WHERE s.`week` = %d",
		T_SCORES, week), {{"board", "s"}, {"player_id", "n"}, {"value", "n"}, {"count", "n"}, {"updated_at", "n"},
		{"name", "s"}, {"group_id", "n"}, {"vocation", "n"}})
	for _, r in ipairs(rows) do
		if scores[r.board] then
			scores[r.board][r.player_id] = {value = r.value, count = r.count, at = r.updated_at, name = r.name,
				group = r.group_id, voc = r.vocation}
		end
	end
	return scores
end

local function ensureWeek()
	local week = weekNow()
	if not LB.current or LB.current.week ~= week then
		LB.current = {week = week, scores = loadScores(week)}
		LB.ranked = {}
	end
	return LB.current
end

local function getConfig(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key))
	if not id then
		return nil
	end
	local v = result.getString(id, "value")
	result.free(id)
	return tonumber(v)
end

local function setConfig(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", db.escapeString(key), db.escapeString(tostring(value))))
end

local function loadHeld(week)
	local rows = Chaos.select(string.format("SELECT t.`board`, t.`rank`, t.`player_id`, t.`value`, t.`title`, p.`name` " ..
		"FROM `%s` t JOIN `players` p ON p.`id` = t.`player_id` WHERE t.`week` = %d ORDER BY t.`board`, t.`rank`",
		T_TITLES, week), {{"board", "s"}, {"rank", "n"}, {"player_id", "n"}, {"value", "n"}, {"title", "s"}, {"name", "s"}})
	local awards = {}
	for _, r in ipairs(rows) do
		awards[#awards + 1] = {board = r.board, rank = r.rank, rankName = cfg.rankNames[r.rank] or ("#" .. r.rank),
			guid = r.player_id, name = r.name, value = r.value, title = r.title}
	end
	LB.held = {week = week, awards = awards, byGuid = LB.titleMap(awards)}
end

-- who -> guid, name, group (or nil)
local function identify(who)
	if type(who) == "userdata" then
		return who:getGuid(), who:getName(), who:getGroup():getId()
	end
	local guid, name
	if type(who) == "table" then
		guid, name = tonumber(who.guid), who.name
	else
		guid = tonumber(who)
	end
	if not guid then
		return nil
	end
	local online = name and Player(name)
	if online and online:getGuid() == guid then
		return guid, online:getName(), online:getGroup():getId()
	end
	local id = db.storeQuery("SELECT `name`, `group_id` FROM `players` WHERE `id` = " .. guid)
	if not id then
		return nil
	end
	name = result.getString(id, "name")
	local group = result.getNumber(id, "group_id")
	result.free(id)
	return guid, name, group
end

-- ---------------------------------------------------------------- public API
function LB.record(board, who, value, mode)
	local b = boardByKey[board]
	if not b then
		LB.warned = LB.warned or {}
		if not LB.warned[tostring(board)] then
			LB.warned[tostring(board)] = true
			log("record: unknown board " .. tostring(board) .. " (add it to leaderboard_config.lua boards); calls ignored")
		end
		return nil
	end
	value = tonumber(value)
	if not value or value < 0 or value ~= value then
		return nil
	end
	local cur = ensureWeek()
	local guid, name, group = identify(who)
	if not guid or (Chaos.isTesterGuid and Chaos.isTesterGuid(guid)) then
		return nil -- tester bots never rank (testers.lua)
	end
	local now = LB.now()
	local e = LB.merge(cur.scores[board][guid], value, mode or b.mode, now)
	e.name, e.group = name, group
	if type(who) == "userdata" then
		e.voc = who:getVocation():getId() -- the class tabs of byClass boards
	end
	cur.scores[board][guid] = e
	LB.ranked[board] = nil
	db.asyncQuery(string.format("INSERT INTO `%s` (`board`, `week`, `player_id`, `value`, `count`, `updated_at`) " ..
		"VALUES (%s, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `count` = VALUES(`count`), " ..
		"`updated_at` = VALUES(`updated_at`)", T_SCORES, db.escapeString(board), cur.week, guid, e.value, e.count, e.at))
	return e
end

function LB.recordShares(shares)
	for _, s in ipairs(shares or {}) do
		LB.record("worldboss", {guid = s.guid, name = s.name}, math.floor(s.damage or 0), "add")
	end
end

function LB.titlesOf(guid)
	return LB.held.byGuid[guid]
end

function LB.rankedBoard(board)
	local cur = ensureWeek()
	if not LB.ranked[board] then
		LB.ranked[board] = LB.rank(cur.scores[board] or {}, cfg.staffGroup, (boardByKey[board] or {}).mode == "min")
		-- accounts held off the boards pending an anti-bot review (antibot.lua; off unless log.holdLeaderboards)
		if ChaosAntibot and ChaosAntibot.filterRanked then
			LB.ranked[board] = ChaosAntibot.filterRanked(LB.ranked[board])
		end
	end
	return LB.ranked[board]
end

-- ---------------------------------------------------------------- rewards
local function inboxGive(player, id, count)
	local inbox = player:getInbox()
	local rest = count
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return inbox ~= nil
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

-- deliver every unrewarded title reward of this player (any week)
function LB.deliverPending(player)
	local guid = player:getGuid()
	local rows = Chaos.select(string.format("SELECT `week`, `board`, `rank`, `title` FROM `%s` WHERE `player_id` = %d " ..
		"AND `rewarded` = 0", T_TITLES, guid), {{"week", "n"}, {"board", "s"}, {"rank", "n"}, {"title", "s"}})
	for _, r in ipairs(rows) do
		db.query(string.format("UPDATE `%s` SET `rewarded` = 1 WHERE `week` = %d AND `board` = %s AND `rank` = %d",
			T_TITLES, r.week, db.escapeString(r.board), r.rank))
		local parts = {}
		local nb = boardByKey[r.board]
		for _, it in ipairs(not (nb and nb.noReward) and cfg.rewards[r.rank] or {}) do -- noReward: the title only
			if inboxGive(player, it.id, it.count) then
				parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
			end
		end
		local b = boardByKey[r.board]
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"Leaderboard: %s place on the %s board last week. You hold the title %s this week.%s",
			cfg.rankNames[r.rank] or ("#" .. r.rank), b and b.name or r.board, r.title,
			#parts > 0 and Chaos.t(player, " Reward in your inbox: %s.", table.concat(parts, ", ")) or ""))
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	end
end

-- ---------------------------------------------------------------- weekly reset
function LB.checkReset(force)
	local cur = weekNow()
	local last = getConfig(cfg.resetConfigKey)
	if not force and not LB.resetDue(last, cur) then
		return false
	end
	local prev = LB.prevWeek(cur, cfg.resetHour)
	local scores = loadScores(prev)
	local ranked = {}
	for _, b in ipairs(cfg.boards) do
		ranked[b.key] = LB.rank(scores[b.key], cfg.staffGroup, b.mode == "min")
		if ChaosAntibot and ChaosAntibot.filterRanked then -- no titles or orbs while held for an anti-bot review
			ranked[b.key] = ChaosAntibot.filterRanked(ranked[b.key])
		end
	end
	local awards = LB.awards(cfg.boards, ranked, cfg)
	for _, a in ipairs(awards) do
		db.query(string.format("INSERT IGNORE INTO `%s` (`week`, `board`, `rank`, `player_id`, `value`, `title`, " ..
			"`rewarded`, `awarded_at`) VALUES (%d, %s, %d, %d, %d, %s, 0, %d)", T_TITLES, prev, db.escapeString(a.board),
			a.rank, a.guid, a.value, db.escapeString(a.title), os.time()))
	end
	setConfig(cfg.resetConfigKey, cur)
	local oldest = LB.week(LB.weekStart(cur, cfg.resetHour) - cfg.keepWeeks * 7 * 86400, cfg.resetHour)
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `week` < %d", T_SCORES, oldest))
	loadHeld(prev)
	ensureWeek()
	if #awards > 0 then
		local text = Chaos.broadcast(MESSAGE_EVENT_ADVANCE, function(lang) return LB.broadcastText(cfg.boards, awards, lang) end)
		if ChaosNotify and ChaosNotify.gmBroadcast then
			ChaosNotify.gmBroadcast(nil, text)
		end
		log(text)
	end
	log(string.format("weekly reset: week %d scored (%d titles), new week %d", prev, #awards, cur))
	for _, p in ipairs(Game.getPlayers()) do
		LB.deliverPending(p)
	end
	return true, prev, awards
end

-- ---------------------------------------------------------------- class ladder
local function vocationName(id)
	local v = Vocation(id)
	return v and v:getName() or ("Vocation " .. id)
end

function LB.classGroups()
	if LB.groupsCache then
		return LB.groupsCache
	end
	-- the ids of data/XML/vocations.xml (Vocation(id) of a missing id prints an engine warning), else a scan
	local ids, seen = {}, {}
	local f = io.open(cfg.ladder.vocationsFile, "r")
	if f then
		local text = f:read("*a")
		f:close()
		for tag in text:gmatch("<vocation%s[^>]*>") do
			local id = tonumber(tag:match('%sid%s*=%s*"(%d+)"'))
			if id and id > 0 and not seen[id] and Vocation(id) then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	if #ids == 0 then
		for id = 1, cfg.ladder.maxVocationId do
			local v = Vocation(id)
			if v and v:getId() == id then
				ids[#ids + 1] = id
			end
		end
	end
	local baseOf = cfg.ladder.baseOf or (Chaos.classes and Chaos.classes.baseOf)
	local groups = LB.groups(ids, baseOf, function(id)
		local v = Vocation(id)
		local d = v and v.getDemotion and v:getDemotion()
		return d and d:getId() or nil
	end)
	for _, g in ipairs(groups) do
		g.name = vocationName(g.base)
		g.key = g.base
	end
	LB.groupsCache = groups
	return groups
end

local function groupByKey(key)
	for _, g in ipairs(LB.classGroups()) do
		if g.key == key then
			return g
		end
	end
	return nil
end

local function groupOfPlayer(player)
	local id = player:getVocation():getId()
	for _, g in ipairs(LB.classGroups()) do
		for _, v in ipairs(g.ids) do
			if v == id then
				return g
			end
		end
	end
	return LB.classGroups()[1]
end

local function ladderWhere(g)
	return string.format("`vocation` IN (%s) AND `group_id` < %d AND `deletion` = 0", table.concat(g.ids, ","),
		cfg.staffGroup) .. (ChaosAntibot and ChaosAntibot.heldClause and ChaosAntibot.heldClause("") or "")
end

local function ladderRows(g)
	local c = LB.ladder[g.key]
	if c and os.time() - c.at < cfg.ladder.cacheSeconds then
		return c.rows
	end
	local rows = Chaos.select(string.format("SELECT `id`, `name`, `level`, `vocation`, `experience` FROM `players` " ..
		"WHERE %s ORDER BY `experience` DESC, `id` ASC LIMIT %d", ladderWhere(g), cfg.rows),
		{{"id", "n"}, {"name", "s"}, {"level", "n"}, {"vocation", "n"}, {"experience", "n"}})
	for i, r in ipairs(rows) do
		r.rank = i
	end
	LB.ladder[g.key] = {at = os.time(), rows = rows}
	return rows
end

-- the title shown next to a name: the one of this board if held, else the first; "+n" when more are held
local function firstTitle(guid, board)
	local t = LB.held.byGuid[guid]
	if not t or #t == 0 then
		return nil
	end
	local pick = t[1]
	for _, x in ipairs(t) do
		if x.board == board then
			pick = x
		end
	end
	return #t > 1 and string.format("%s +%d", pick.title, #t - 1) or pick.title
end

local function ladderBoard(player, g)
	local rows = {}
	for _, r in ipairs(ladderRows(g)) do
		rows[#rows + 1] = {rank = r.rank, name = r.name, value = r.level, level = r.level,
			vocation = vocationName(r.vocation), title = firstTitle(r.id),
			fallen = ChaosSeason and ChaosSeason.fallenMark and ChaosSeason.fallenMark(r.id) or nil} -- season_modes.lua
	end
	local own
	local mine = groupOfPlayer(player)
	if mine and mine.key == g.key and player:getGroup():getId() < cfg.staffGroup then
		local exp = player:getExperience()
		local id = db.storeQuery(string.format("SELECT COUNT(*) AS `n` FROM `players` WHERE %s AND `id` <> %d AND " ..
			"(`experience` > %d OR (`experience` = %d AND `id` < %d))", ladderWhere(g), player:getGuid(), exp, exp,
			player:getGuid()))
		local ahead = 0
		if id then
			ahead = result.getNumber(id, "n")
			result.free(id)
		end
		own = {rank = ahead + 1, value = player:getLevel()}
	end
	return {key = cfg.ladder.key, group = g.key, rows = rows, own = own}
end

-- ---------------------------------------------------------------- protocol
local function sendMeta(player, open)
	local boards = {}
	for _, b in ipairs(cfg.boards) do
		boards[#boards + 1] = {key = b.key, name = b.name, weekly = true, value = b.value, count = b.count,
			title = b.title, info = b.info, byClass = b.byClass, format = b.format}
	end
	boards[#boards + 1] = {key = cfg.ladder.key, name = cfg.ladder.name, weekly = false, value = "Level",
		info = "Highest level per class, all time."}
	local groups = {}
	for _, g in ipairs(LB.classGroups()) do
		groups[#groups + 1] = {key = g.key, name = g.name}
	end
	Chaos.send(player, OPCODE, "meta", {open = open and true or false, boards = boards, groups = groups,
		ownGroup = (groupOfPlayer(player) or {}).key,
		season = ChaosSeason and ChaosSeason.leaderboardMeta and ChaosSeason.leaderboardMeta(player) or nil}) -- season.lua
end

function LB.sendBoard(player, key, groupKey, season, mode)
	-- the "Season" view (season.lua): only the running season's characters (mode: a tab of season_modes.lua)
	if season and ChaosSeason and ChaosSeason.sendBoard and ChaosSeason.sendBoard(player, key, groupKey, mode) then
		return
	end
	local now = LB.now()
	local data
	if key == cfg.ladder.key then
		local g = groupByKey(tonumber(groupKey)) or groupOfPlayer(player)
		if not g then
			return
		end
		data = ladderBoard(player, g)
	else
		local b = boardByKey[key] or cfg.boards[1]
		local ranked = LB.rankedBoard(b.key)
		-- a board with class tabs (byClass): the class group asked for, none = every class
		local g = b.byClass and groupKey and groupByKey(tonumber(groupKey))
		if g then
			ranked = LB.filterClass(ranked, g.ids)
		end
		local rows = {}
		for i = 1, math.min(cfg.rows, #ranked) do
			local e = ranked[i]
			rows[#rows + 1] = {rank = e.rank, name = e.name, value = e.value, count = e.count, title = firstTitle(e.guid, b.key)}
		end
		local mine = LB.find(ranked, player:getGuid())
		local champions = {}
		for _, a in ipairs(LB.held.awards) do
			if a.board == b.key then
				champions[#champions + 1] = {rank = a.rank, rankName = a.rankName, name = a.name, value = a.value,
					title = a.title}
			end
		end
		data = {key = b.key, group = g and g.key or nil, rows = rows, total = #ranked, champions = champions,
			own = mine and {rank = mine.rank, value = mine.value, count = mine.count} or nil}
	end
	data.week = LB.current and LB.current.week or weekNow()
	data.resetIn = math.max(0, LB.nextReset(now, cfg.resetHour) - now)
	if ChaosDisplayScale and ChaosDisplayScale.apply then -- the viewer's display scale: the damage / healing boards
		data = ChaosDisplayScale.apply("leaderboard", player, data)
	end
	Chaos.send(player, OPCODE, "board", data)
end

-- ---------------------------------------------------------------- look text
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() then
		local titles = LB.held.byGuid[thing:getGuid()]
		if titles then
			local pronoun = thing:getId() == self:getId() and "You" or (thing:getSex() == PLAYERSEX_FEMALE and "She" or "He")
			local line = LB.lookText(titles, pronoun)
			if pronoun == "You" then
				line = line:gsub("^You holds", "You hold")
			end
			description = (description or "") .. "\n" .. line
		end
	end
	return description
end
-- after the base server's default_onLook (index 0), which builds the "You see ..." text and ignores what came before
look:register(100)

-- ---------------------------------------------------------------- events
local think = GlobalEvent("ChaosLeaderboardReset")
function think.onThink(interval)
	ensureWeek()
	LB.checkReset()
	return true
end
think:interval(cfg.checkSeconds * 1000)
think:register()

-- load the week, run a due reset, else load the titles held this week
function LB.refresh()
	ensureWeek()
	local done = LB.checkReset()
	if not done then
		loadHeld(LB.prevWeek(weekNow(), cfg.resetHour))
	end
	return done
end

local startup = GlobalEvent("ChaosLeaderboardStartup")
function startup.onStartup()
	LB.refresh()
	log(string.format("week %d, %d title(s) held", LB.current.week, #LB.held.awards))
	return true
end
startup:register()

local login = CreatureEvent("ChaosLeaderboardLogin")
function login.onLogin(player)
	player:registerEvent("ChaosLeaderboardExtended")
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			LB.deliverPending(p)
		end
	end, 2500, player:getId())
	return true
end
login:type("login")
login:register()

local ext = CreatureEvent("ChaosLeaderboardExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local key = type(data.board) == "string" and data.board or nil
	-- board answers read the database (the class ladder counts the players ahead); ratelimit.lua
	if msg.action == "get" and ChaosRateLimit and not ChaosRateLimit.allow(player, "leaderboard.get", 150) then
		return
	end
	if msg.action == "open" then
		sendMeta(player, true)
		LB.sendBoard(player, key or cfg.boards[1].key)
	elseif msg.action == "get" then
		LB.sendBoard(player, key or cfg.boards[1].key, data.group, data.season == true,
			type(data.mode) == "string" and data.mode:sub(1, 12) or nil)
	end
end
ext:type("extendedopcode")
ext:register()

-- !leaderboard opens the window. Staff (/leaderboard): reset (process the weekly reset now, even if done),
-- shift <days> (move the leaderboard clock, for tests; 0 = real time), status.
local function onCommand(player, words, param)
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if words == "/leaderboard" and player:getGroup():getAccess() and param ~= "" then
		local cmd, arg = param:match("^(%S+)%s*(.*)$")
		if cmd == "reset" then
			local done, prev, awards = LB.checkReset(true)
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Leaderboard reset: week %s scored, %d title(s).",
				tostring(prev), awards and #awards or 0))
		elseif cmd == "shift" then
			LB.offset = math.floor((tonumber(arg) or 0) * 86400)
			local done = LB.refresh()
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Leaderboard clock shifted %s day(s): week %d%s.",
				arg, LB.current.week, done and ", weekly reset processed" or ""))
		else
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Leaderboard: week %d, next reset in %d s, %d title(s) " ..
				"held (week %d), clock offset %d s.", ensureWeek().week, LB.nextReset(LB.now(), cfg.resetHour) - LB.now(),
				#LB.held.awards, LB.held.week, LB.offset))
		end
		return false
	end
	sendMeta(player, true)
	LB.sendBoard(player, cfg.boards[1].key)
	return false
end

-- staff only (players open the window from the menu)
local talk = TalkAction("/leaderboard")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	-- the test clock: every shift past a week end awards that week's titles and orbs again: an administrator only, logged
	local cmd = tostring(param or ""):lower():match("^%s*(%S*)")
	local value = cmd == "shift"
	if not Chaos.staffCommand(player, words, param, value) then
		return false
	end
	return onCommand(player, words, param)
end
talk:separator(" ")
talk:register()

-- The weekly class boards (O409): a weekly leaderboard board ranked per class, the experience every character gains
-- from monsters this week. Numbers: weekly_class_config.lua. Pure logic: weekly_class_core.lua
-- (tests/weekly_class_test.lua). Overview: server/README.md "Weekly class ranking (O409)".
--
-- How it plugs in (no opcode, no storage of its own):
--   EventCallback onGainExperience (index cfg.expIndex, after every bonus and cap): a monster kill's experience is kept
--                 per character in memory; once a minute and at logout it goes to ChaosLeaderboard.record(cfg.board,
--                 player, amount, "add") (the weekly_xp board of leaderboard_config.lua: classAwards, class tabs)
--   ChaosLeaderboard.onReset -> onWeekEnd: per class tab the top 3 get Conquest Tokens (conquest.lua grantGuid, source
--                 "weekly_class"), one broadcast names the 1st of every class, one Discord row "weekly_class"
--                 (discord_core.lua D.weeklyClass) lists the podium of every class; the podium is written to
--                 chaos_weekly_class_podium (the website shows it; a second reset of the same week finds it and pays nothing)
-- The client: game_leaderboard shows the board with its class tabs (the meta's byClass); the website's Leaderboards page
-- shows it and last week's podium per class.
-- Staff: /weeklyclass (status: the week, characters with experience kept, the last week paid).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/weekly_class_core.lua")
ChaosWeeklyClassConfig = dofile("data/scripts/chaos/weekly_class_config.lua")

ChaosWeeklyClass = ChaosWeeklyClass or {}
local WK = ChaosWeeklyClass
local K = ChaosWeeklyClassCore

WK.buf = WK.buf or {} -- guid -> experience not yet written to the board

local function C()
	return ChaosWeeklyClassConfig
end

local function log(text)
	print("[Chaos weekly class] " .. text)
end

local function try(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		log(what .. ": " .. tostring(err))
	end
	return ok, err
end

-- ---------------------------------------------------------------- the experience
local function isMonster(c)
	return c ~= nil and c.isMonster ~= nil and c:isMonster() and true or false
end

local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	if C().enabled and isMonster(source) then
		K.add(WK.buf, player:getGuid(), exp)
	end
	return exp
end
xp:register(C().expIndex or 1500)

function WK.flush(player)
	local amount = K.take(WK.buf, player:getGuid())
	if amount > 0 and ChaosLeaderboard and ChaosLeaderboard.record then
		ChaosLeaderboard.record(C().board, player, amount, "add")
	end
	return amount
end

local think = GlobalEvent("ChaosWeeklyClassFlush")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		if WK.buf[player:getGuid()] then
			try("flush", WK.flush, player)
		end
	end
	return true
end
think:interval((C().flushSeconds or 60) * 1000)
think:register()

local logout = CreatureEvent("ChaosWeeklyClassLogout")
function logout.onLogout(player)
	try("flush", WK.flush, player)
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- the week's end (leaderboard reset)
local function paid(week)
	local cfg = C()
	local id = db.storeQuery(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `week` = %d AND `board` = %s",
		cfg.table, week, db.escapeString(cfg.board)))
	if not id then
		return false
	end
	local n = result.getNumber(id, "n")
	result.free(id)
	return n > 0
end

function WK.onWeekEnd(prev, ranked)
	local cfg = C()
	local LB = ChaosLeaderboard
	if not cfg.enabled or not (LB and LB.classGroups and LB.filterClass) then
		return
	end
	if paid(prev) then
		log(string.format("week %d was closed already: nothing paid again", prev))
		return
	end
	local n = math.max(cfg.rewardTop or 3, cfg.discordTop or 3)
	local tops = K.classTop(ranked[cfg.board] or {}, LB.classGroups(), n, LB.filterClass, cfg.minValue)
	local label = K.weekLabel(prev)
	local given, now = 0, os.time()
	for _, a in ipairs(K.awards(cfg, tops)) do
		local tokens = 0
		if a.tokens > 0 and ChaosConquest and ChaosConquest.grantGuid then
			tokens = ChaosConquest.grantGuid(a.guid, a.tokens, "weekly_class", string.format("Weekly Experience %s", label))
		end
		given = given + tokens
		db.query(string.format("INSERT IGNORE INTO `%s` (`week`, `board`, `class_base`, `rank`, `player_id`, `value`, " ..
			"`tokens`, `awarded_at`) VALUES (%d, %s, %d, %d, %d, %d, %d, %d)", cfg.table, prev, db.escapeString(cfg.board),
			tonumber(a.group) or 0, a.rank, a.guid, math.floor(a.value or 0), tokens, now))
	end
	local oldest = LB.week(LB.weekStart(prev, Chaos.leaderboardConfig.resetHour) - (cfg.keepWeeks or 12) * 7 * 86400,
		Chaos.leaderboardConfig.resetHour)
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `week` < %d", cfg.table, oldest))
	local board
	for _, b in ipairs(Chaos.leaderboardConfig.boards or {}) do
		if b.key == cfg.board then
			board = b
		end
	end
	if cfg.broadcast and K.broadcastText(tops, nil, "en") then
		Chaos.broadcast(MESSAGE_EVENT_ADVANCE, function(lang)
			return K.broadcastText(tops, board and board.name or nil, lang)
		end)
	end
	if ChaosDiscord and ChaosDiscord.queue and ChaosDiscordCore and ChaosDiscordConfig then
		ChaosDiscord.queue(ChaosDiscordCore.weeklyClass(ChaosDiscordConfig, label, board and board.name or "Weekly Experience",
			K.discordSections(cfg, tops)))
	end
	WK.lastPaid = prev
	WK.podium = {week = nil, byClass = {}}
	log(string.format("week %s ended: %d Conquest Tokens to the class top %d", label, given, cfg.rewardTop or 3))
end

-- last week's podium of one class tab (leaderboard.lua sendBoard: the champions line of a classAwards board):
-- {{rank, rankName, name, value}}, read once a week from the podium table
WK.podium = WK.podium or {week = nil, byClass = {}}
function WK.champions(groupKey)
	local LB = ChaosLeaderboard
	local hour = Chaos.leaderboardConfig and Chaos.leaderboardConfig.resetHour or 6
	if not (LB and LB.week and LB.prevWeek) then
		return {}
	end
	local prev = LB.prevWeek(LB.week(LB.now and LB.now() or os.time(), hour), hour)
	if WK.podium.week ~= prev then
		local byClass = {}
		local rows = Chaos.select(string.format("SELECT w.`class_base`, w.`rank`, w.`value`, p.`name` FROM `%s` w JOIN " ..
			"`players` p ON p.`id` = w.`player_id` WHERE w.`week` = %d AND w.`board` = %s ORDER BY w.`class_base`, w.`rank`",
			C().table, prev, db.escapeString(C().board)), {{"class_base", "n"}, {"rank", "n"}, {"value", "n"}, {"name", "s"}})
		for _, r in ipairs(rows) do
			byClass[r.class_base] = byClass[r.class_base] or {}
			table.insert(byClass[r.class_base], {rank = r.rank, rankName = (Chaos.leaderboardConfig.rankNames or {})[r.rank],
				name = r.name, value = r.value})
		end
		WK.podium = {week = prev, byClass = byClass}
	end
	return WK.podium.byClass[tonumber(groupKey) or -1] or {}
end

local function hook()
	if ChaosLeaderboard and ChaosLeaderboard.onReset then
		ChaosLeaderboard.onReset(function(prev, ranked)
			WK.onWeekEnd(prev, ranked)
		end, "weekly_class")
		return true
	end
	return false
end

local startup = GlobalEvent("ChaosWeeklyClassStartup")
function startup.onStartup()
	try("table", function() db.query(K.schemaSql(C().table)) end)
	if not hook() then
		log("the leaderboard is not loaded: no rewards and no Discord post at the week's end")
	end
	return true
end
startup:register()
hook()

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/weeklyclass")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	if not Chaos.staffCommand(player, words, param, false) then
		return false
	end
	local kept = 0
	for _ in pairs(WK.buf) do
		kept = kept + 1
	end
	local LB = ChaosLeaderboard
	local week = LB and LB.current and LB.current.week or 0
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Weekly class board %s: week %d, %d character(s) with " ..
		"experience not written yet, last week paid %s.", C().board, week, kept, tostring(WK.lastPaid or "-")))
	return false
end
talk:separator(" ")
talk:register()

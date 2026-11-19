-- Greater Rift ladder and rewards (O668). The engine part: the database, the season end, the delivery, the command.
-- Pure logic: greater_ladder_core.lua (tests/greater_rift_test.lua); the rift side (keys, rule, clock): rift_core.lua R.greater*,
-- rift.lua RF.greaterSettle; numbers: rift_config.lua `greater`; tables: sql/chaos_greater_rift.sql. No opcode: the weekly
-- boards greater_solo / greater_party of leaderboard_config.lua show the tier in the client's Leaderboards window, the season
-- ladder is read with the Greater Ladder button of the Rift Keys page of the Info window (ChaosCommands id "greater", a text window).
--
-- Public API (rift.lua):
--   ChaosGreater.record(info) -> {[guid] = {tier, best, improved, rewards}}
--       info = {tier = shown tier, secs, players = n, finishers = {[guid] = {name, player?}}}. Testers are skipped (Chaos.isTesterGuid).
--       Writes the (season, character, mode) row, pays the personal best (one row of chaos_greater_rift_rewards per new tier of
--       the season, delivered at once to an online character), records the weekly board and rolls the pinnacle fragment.
--   ChaosGreater.deliverPending(player)       every unpaid reward row of the character into backpack / inbox (login, season end)
--   ChaosGreater.checkSeasons(startup, now)   pays every ended season once (server_config rift_config greater.ladder.configKey)
--   ChaosGreater.text(player)                 the ladder text of the Greater Ladder window
-- Staff: /greaterseason status | pay (group 4+).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosTowerCore then
	dofile("data/scripts/chaos/infinitytower_core.lua")
end
if not ChaosRiftCore then
	dofile("data/scripts/chaos/rift_core.lua")
end
ChaosRiftConfig = ChaosRiftConfig or dofile("data/scripts/chaos/rift_config.lua")
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
dofile("data/scripts/chaos/greater_ladder_core.lua")

ChaosGreater = ChaosGreater or {}
local G = ChaosGreater
local K = ChaosGreaterCore
local R = ChaosRiftCore
local T_BEST = Chaos.tables.greaterRift or "chaos_greater_rift"
local T_RW = Chaos.tables.greaterRiftRewards or "chaos_greater_rift_rewards"

local function cfg()
	return ChaosRiftConfig
end

local function log(text)
	print("[Chaos greater rift] " .. text)
end

function G.currentSeason(now)
	local number, _, finish = K.seasonOf(cfg(), Chaos.tower, now or os.time())
	return number, finish
end

local function groups()
	local LB = ChaosLeaderboard
	return LB and LB.classGroups and LB.classGroups() or {}
end

-- the vocation id of a character: online, else the players table
local function vocOf(guid, player)
	if player then
		local ok, id = pcall(function() return player:getVocation():getId() end)
		if ok and id then
			return id
		end
	end
	local rows = Chaos.select("SELECT `vocation` FROM `players` WHERE `id` = " .. tonumber(guid) .. " LIMIT 1", {{"vocation", "n"}})
	return rows[1] and rows[1].vocation or 0
end

local function giveStack(player, id, count)
	if count <= 0 then
		return
	end
	local rest = count - Chaos.giveItem(player, id, count)
	local inbox = rest > 0 and player:getInbox() or nil
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
end

-- ---------------------------------------------------------------- rewards: written once, delivered at once or at login
local function grant(guid, season, kind, slot, f)
	db.query(string.format("INSERT IGNORE INTO `%s` (`season`, `player_id`, `kind`, `slot`, `tier`, `place`, `label`, `fate`, " ..
		"`upheaval`, `fragments`, `gold`, `rewarded`, `awarded_at`) VALUES (%d, %d, %s, %d, %d, %d, %s, %d, %d, %d, %d, 0, %d)",
		T_RW, season, guid, db.escapeString(kind), slot, f.tier or 0, f.place or 0, db.escapeString(f.label or ""), f.fate or 0,
		f.upheaval or 0, f.fragments or 0, f.gold or 0, os.time()))
end
G.grant = grant

function G.deliverPending(player)
	local guid = player:getGuid()
	local c = cfg().greater.rewards.best
	local rows = Chaos.select(string.format("SELECT `season`, `kind`, `slot`, `tier`, `place`, `label`, `fate`, `upheaval`, " ..
		"`fragments`, `gold` FROM `%s` WHERE `player_id` = %d AND `rewarded` = 0 ORDER BY `season`, `slot`", T_RW, guid),
		{{"season", "n"}, {"kind", "s"}, {"slot", "n"}, {"tier", "n"}, {"place", "n"}, {"label", "s"}, {"fate", "n"},
		{"upheaval", "n"}, {"fragments", "n"}, {"gold", "n"}})
	local n = 0
	for _, r in ipairs(rows) do
		-- marked first: a failure below never pays twice
		db.query(string.format("UPDATE `%s` SET `rewarded` = 1, `delivered_at` = %d WHERE `season` = %d AND `player_id` = %d " ..
			"AND `kind` = %s AND `slot` = %d AND `rewarded` = 0", T_RW, os.time(), r.season, guid, db.escapeString(r.kind), r.slot))
		giveStack(player, c.orbFate.id, r.fate)
		giveStack(player, c.orbUpheaval.id, r.upheaval)
		giveStack(player, c.fragments.id, r.fragments)
		if r.gold > 0 then
			player:setBankBalance(player:getBankBalance() + r.gold)
		end
		local parts = {}
		if r.fate > 0 then parts[#parts + 1] = r.fate .. " Orb of Fate" end
		if r.upheaval > 0 then parts[#parts + 1] = r.upheaval .. " Orb of Upheaval" end
		if r.fragments > 0 then parts[#parts + 1] = r.fragments .. " omen fragments" end
		if r.gold > 0 then parts[#parts + 1] = r.gold .. " gold" end
		local text
		if r.kind == "pb" then
			text = Chaos.t(player, "Greater Rift tier %d, a new personal best: %s.", r.tier, table.concat(parts, ", "))
		else
			text = Chaos.t(player, "Greater Rift season %d has ended: %s, place %d, tier %d. %s.", r.season, r.label, r.place,
				r.tier, table.concat(parts, ", "))
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		if ChaosNotify and ChaosNotify.send then
			pcall(ChaosNotify.send, player, "Greater Rift", text, "achievement")
		end
		n = n + 1
	end
	return n
end

-- ---------------------------------------------------------------- the run
local function bestRows(guid, season)
	return Chaos.select(string.format("SELECT `mode`, `voc`, `best_tier`, `best_time`, `runs` FROM `%s` WHERE `season` = %d " ..
		"AND `player_id` = %d", T_BEST, season, guid), {{"mode", "n"}, {"voc", "n"}, {"best_tier", "n"}, {"best_time", "n"},
		{"runs", "n"}})
end

-- info: {tier (shown), secs, players, finishers = {[guid] = {name, player}}}
function G.record(info)
	local rc = cfg()
	local out = {}
	if not R.greaterOn(rc) or (info.tier or 0) < rc.greater.firstTier then
		return out
	end
	local season = G.currentSeason()
	local mode = K.modeOf(info.players)
	local modeId = K.MODES[mode]
	local board = rc.greater.ladder.boards[mode]
	for guid, f in pairs(info.finishers or {}) do
		local player = f.player
		if not (Chaos.isTesterGuid and Chaos.isTesterGuid(guid)) and not (player and Chaos.isTester and Chaos.isTester(player)) then
			local rows = bestRows(guid, season)
			local base, mine = K.baseline(rows), nil
			for _, r in ipairs(rows) do
				if r.mode == modeId then
					mine = r
				end
			end
			local row, improved = K.merge(mine, info.tier, info.secs)
			local voc = vocOf(guid, player)
			db.query(string.format("INSERT INTO `%s` (`season`, `player_id`, `mode`, `voc`, `best_tier`, `best_time`, `runs`, " ..
				"`updated_at`) VALUES (%d, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `voc` = IF(%d = 1, VALUES(`voc`), " ..
				"`voc`), `best_tier` = VALUES(`best_tier`), `best_time` = VALUES(`best_time`), `runs` = VALUES(`runs`), " ..
				"`updated_at` = VALUES(`updated_at`)", T_BEST, season, guid, modeId, voc, row.best_tier, row.best_time, row.runs,
				os.time(), improved and 1 or 0))
			local pays = R.greaterBestRewards(rc, base, info.tier)
			for _, p in ipairs(pays) do
				grant(guid, season, "pb", p.tier, {tier = p.tier, fate = p.fate, upheaval = p.upheaval, fragments = p.fragments,
					gold = p.gold})
			end
			if ChaosLeaderboard and ChaosLeaderboard.record and board then
				pcall(ChaosLeaderboard.record, board, player or {guid = guid, name = f.name}, info.tier, "max")
			end
			-- a pinnacle fragment (O667): a small chance; without that system nothing happens
			local pct = R.greaterPinnacleChance(rc, info.tier)
			if player and pct > 0 and ChaosPinnacle and ChaosPinnacle.grantFragment and math.random(1, 100000) <= pct * 1000 then
				pcall(ChaosPinnacle.grantFragment, player, rc.greater.rewards.pinnacle.source, {tier = info.tier, players = info.players})
			end
			out[guid] = {tier = info.tier, best = row.best_tier, improved = improved, rewards = #pays}
			if player then
				G.deliverPending(player)
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- the ladder
function G.rowsOf(season, mode)
	local rows = Chaos.select(string.format("SELECT t.`player_id`, p.`name`, p.`group_id`, t.`voc`, t.`best_tier`, t.`best_time` " ..
		"FROM `%s` t JOIN `players` p ON p.`id` = t.`player_id` WHERE t.`season` = %d AND t.`mode` = %d AND t.`best_tier` > 0 AND %s",
		T_BEST, season, K.MODES[mode], Chaos.notTesterSql("p")), -- a tester bot is on no ladder
		{{"player_id", "n"}, {"name", "s"}, {"group_id", "n"}, {"voc", "n"}, {"best_tier", "n"}, {"best_time", "n"}})
	local list = {}
	for _, r in ipairs(rows) do
		list[#list + 1] = {guid = r.player_id, name = r.name, group = r.group_id, voc = r.voc, tier = r.best_tier,
			time = r.best_time, mode = mode}
	end
	if ChaosAntibot and ChaosAntibot.filterRanked then
		list = ChaosAntibot.filterRanked(list)
	end
	return list
end

function G.text(player)
	local rc = cfg()
	local season, finish = G.currentSeason()
	local gs = groups()
	local mine = K.groupOf(gs, player:getVocation():getId())
	local lines = {Chaos.t(player, "Greater Rift, season %d.", season)}
	local own = bestRows(player:getGuid(), season)
	for _, r in ipairs(own) do
		lines[#lines + 1] = Chaos.t(player, K.MODE_NAMES[r.mode] == "solo" and "Your best, solo: tier %d in %s."
			or "Your best, party: tier %d in %s.", r.best_tier, K.timeText(r.best_time))
	end
	if #own == 0 then
		lines[#lines + 1] = Chaos.t(player, "You have not sealed a Greater Rift this season. A tier 15 guardian may leave a Greater Rift Key, or %d omen fragments bind one (Bind Greater Key).",
			rc.greater.key.fragmentCost)
	end
	for _, mode in ipairs({"solo", "party"}) do
		local top = K.board(G.rowsOf(season, mode), gs, mine, rc.greater.ladder.staffGroup, rc.greater.ladder.rows)
		lines[#lines + 1] = Chaos.t(player, mode == "solo" and "Top, solo, your class:" or "Top, party, your class:")
		if #top == 0 then
			lines[#lines + 1] = "  -"
		end
		for _, r in ipairs(top) do
			lines[#lines + 1] = string.format("  %d. %s - %d (%s)", r.place, r.name, r.tier, K.timeText(r.time))
		end
	end
	if finish then
		lines[#lines + 1] = Chaos.t(player, "The season ends in %d days.", math.max(0, math.ceil((finish - os.time()) / 86400)))
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------- season end: the brackets
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

function G.processSeason(season)
	local rows = {}
	for _, mode in ipairs({"solo", "party"}) do
		for _, r in ipairs(G.rowsOf(season, mode)) do
			rows[#rows + 1] = r
		end
	end
	local awards = K.awards(cfg(), rows, groups())
	for _, a in ipairs(awards) do
		grant(a.guid, season, "season", K.MODES[a.mode], {tier = a.tier, place = a.place, label = a.bracket.name,
			fate = a.bracket.fate, upheaval = a.bracket.upheaval, fragments = a.bracket.fragments})
	end
	return awards
end

function G.checkSeasons(startup, now)
	local lc = cfg().greater.ladder
	local current = G.currentSeason(now)
	local done = getConfig(lc.configKey)
	local pending = ChaosTowerCore.pendingSeasons(done, current)
	if not pending then
		setConfig(lc.configKey, current - 1) -- a new server: nothing earlier to pay out
		return 0
	end
	local paid = 0
	for _, s in ipairs(pending) do
		local ok, awards = pcall(G.processSeason, s)
		if not ok then
			log("season " .. s .. " end failed: " .. tostring(awards))
			return paid
		end
		setConfig(lc.configKey, s)
		paid = paid + 1
		log(string.format("season %d ended: %d reward(s) written", s, #awards))
		if not startup then
			Chaos.broadcast(MESSAGE_EVENT_ADVANCE, ChaosI18n.msg("Greater Rift season %d has ended. Season %d begins.", s, s + 1))
		end
	end
	if paid > 0 then
		for _, p in ipairs(Game.getPlayers()) do
			G.deliverPending(p)
		end
	end
	return paid
end

-- ---------------------------------------------------------------- engine glue
local login = CreatureEvent("ChaosGreaterLogin")
function login.onLogin(player)
	local ok, err = pcall(G.deliverPending, player)
	if not ok then
		log("delivery at login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local tick = GlobalEvent("ChaosGreaterSeason")
function tick.onThink(interval)
	local ok, err = pcall(G.checkSeasons, false)
	if not ok then
		log("season check: " .. tostring(err))
	end
	return true
end
tick:interval(cfg().greater.ladder.checkSeconds * 1000)
tick:register()

local start = GlobalEvent("ChaosGreaterStartup")
function start.onStartup()
	pcall(G.checkSeasons, true)
	return true
end
start:register()

-- the Info window (Rift Keys page): the Greater Ladder and Bind Greater Key buttons run this command (id "greater", param "key" binds a key)
if ChaosCommands and ChaosCommands.register then
	ChaosCommands.register("greater", function(player, param)
		if tostring(param or ""):lower():match("^%s*key") then
			if ChaosRift and ChaosRift.buyGreaterKey then
				ChaosRift.buyGreaterKey(player)
			end
			return false
		end
		player:showTextDialog(cfg().key.itemId, G.text(player))
		return false
	end)
end

local staff = TalkAction("/greaterseason")
function staff.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local season, finish = G.currentSeason()
	if tostring(param or ""):lower():match("^%s*pay") then
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Greater Rift: %d season(s) paid.", G.checkSeasons(false)))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Greater Rift: season %d, ends %s, last paid %s.", season,
			finish and os.date("%Y-%m-%d %H:%M", finish) or "never", tostring(getConfig(cfg().greater.ladder.configKey))))
	end
	return false
end
staff:separator(" ")
staff:register()

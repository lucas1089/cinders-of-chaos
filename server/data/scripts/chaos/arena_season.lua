-- PvP seasons: a season rating per bracket (arena 1v1, 2v2, 3v3 and the battleground), placement matches, rank
-- tiers, a soft reset every season, inactivity decay at the top tiers and the end-of-season rewards (a title with its
-- plate frame, cosmetics of cosmetics_config.lua with source "pvp", honor).
-- Settings: battleground_config.lua `season`. Pure part: battleground_core.lua (Glicko-lite, decay, soft reset,
-- tiers, rewards; tests/battleground_test.lua). Overview: server/README.md "Battleground and PvP seasons".
--
-- API (arena.lua, battleground.lua; both call it only when it is loaded)
--   ChaosPvpSeason.current()                    -> season id, start, end (os.time)
--   ChaosPvpSeason.rowOf(guid, bracket)          the stored row of the current season (soft reset from the last one)
--   ChaosPvpSeason.ratingFor(guid, bracket)      the rating to match with (decay applied)
--   ChaosPvpSeason.viewOf(guid)                  {bracket = view} for the windows (battleground_core.lua K.view)
--   ChaosPvpSeason.record(bracket, teams, winner)  teams = {{{guid, name, left}, ...}, {...}}; rates, saves, returns
--                                                {[guid] = {before, after, delta, tier, placed, placementLeft}}
--   ChaosPvpSeason.recordArena(mode, sides, winner)  arena.lua finish(): sides = its team lists (guid, name, left)
--   ChaosPvpSeason.titlesOf(guid)                the season titles the character earned (ChaosTitles source "pvpseason")
-- The matchmaking of the arena keeps the lifetime Elo (arena_core.lua): the best estimate of skill. The season
-- rating decides tiers and rewards; the battleground matches with it.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not Chaos.battlegroundConfig then
	Chaos.battlegroundConfig = dofile("data/scripts/chaos/battleground_config.lua")
end
if not (ChaosBattlegroundCore and ChaosBattlegroundCore.rateTeams) then
	dofile("data/scripts/chaos/battleground_core.lua")
end

ChaosPvpSeason = ChaosPvpSeason or {}
local P = ChaosPvpSeason
local K = ChaosBattlegroundCore

local function C()
	return Chaos.battlegroundConfig
end

local function T(k)
	return C().tables[k]
end

P.rows = P.rows or {} -- guid -> {season = id, [bracket] = row}
P.titles = P.titles or {} -- guid -> list of reward rows
P.lastCheck = P.lastCheck or 0

local function log(text)
	print("[Chaos pvp season] " .. text)
end

function P.current(now)
	return K.seasonOf(C(), now or os.time())
end

-- ---------------------------------------------------------------- DB
local SQL = {
	"CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `player_id` int(11) NOT NULL, " ..
		"`bracket` varchar(8) NOT NULL, `rating` int(11) NOT NULL, `rd` int(11) NOT NULL, `matches` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`wins` int(10) unsigned NOT NULL DEFAULT 0, `losses` int(10) unsigned NOT NULL DEFAULT 0, `draws` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`peak` int(11) NOT NULL DEFAULT 0, `last_match` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`season`, `player_id`, `bracket`), " ..
		"KEY `chaos_pvp_ratings_player` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`season` smallint(5) unsigned NOT NULL, `player_id` int(11) NOT NULL, " ..
		"`account_id` int(11) NOT NULL DEFAULT 0, `tier` tinyint(3) unsigned NOT NULL, `bracket` varchar(8) NOT NULL DEFAULT '', " ..
		"`rating` int(11) NOT NULL DEFAULT 0, `honor` int(10) unsigned NOT NULL DEFAULT 0, `title` varchar(32) NOT NULL DEFAULT '', " ..
		"`frame` varchar(16) NOT NULL DEFAULT '', `cosmetics` varchar(128) NOT NULL DEFAULT '', `granted_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`season`, `player_id`), KEY `chaos_pvp_season_rewards_player` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
}

function P.ensureTables()
	db.query(string.format(SQL[1], T("ratings")))
	db.query(string.format(SQL[2], T("rewards")))
end

local COLS = {{"season", "n"}, {"bracket", "s"}, {"rating", "n"}, {"rd", "n"}, {"matches", "n"}, {"wins", "n"},
	{"losses", "n"}, {"draws", "n"}, {"peak", "n"}, {"last_match", "n"}}

local function fromDb(r)
	return {rating = r.rating, rd = r.rd, matches = r.matches, wins = r.wins, losses = r.losses, draws = r.draws,
		peak = r.peak, last = r.last_match}
end

-- the current season's rows of a character; a bracket without a row of this season starts from the soft reset of
-- the latest earlier one (decayed at that season's end), else fresh
function P.load(guid, force)
	local id, start = P.current()
	local cached = P.rows[guid]
	if cached and cached.season == id and not force then
		return cached
	end
	local out = {season = id}
	local rows = Chaos.select(string.format("SELECT `season`, `bracket`, `rating`, `rd`, `matches`, `wins`, `losses`, `draws`, " ..
		"`peak`, `last_match` FROM `%s` WHERE `player_id` = %d AND `season` <= %d ORDER BY `season` DESC", T("ratings"), guid, id), COLS)
	for _, r in ipairs(rows) do
		if not out[r.bracket] then
			if r.season == id then
				out[r.bracket] = fromDb(r)
			else
				local rating = K.decay(C(), r.rating, r.last_match, start)
				local rd = K.inflate(C(), r.rd, start - (r.last_match > 0 and r.last_match or start))
				local nr, nrd = K.softReset(C(), rating, rd)
				local row = K.newRow(C())
				row.rating, row.rd, row.peak, row.carried = nr, nrd, nr, true
				out[r.bracket] = row
			end
		end
	end
	for _, b in ipairs(C().season.brackets) do
		out[b] = out[b] or K.newRow(C())
	end
	P.rows[guid] = out
	return out
end

function P.rowOf(guid, bracket)
	return P.load(guid)[bracket]
end

function P.ratingFor(guid, bracket)
	local row = P.rowOf(guid, bracket)
	return (K.decay(C(), row.rating, row.last, os.time()))
end

local function save(guid, bracket, row)
	db.query(string.format("INSERT INTO `%s` (`season`, `player_id`, `bracket`, `rating`, `rd`, `matches`, `wins`, `losses`, `draws`, " ..
		"`peak`, `last_match`) VALUES (%d, %d, %s, %d, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `rating` = VALUES(`rating`), " ..
		"`rd` = VALUES(`rd`), `matches` = VALUES(`matches`), `wins` = VALUES(`wins`), `losses` = VALUES(`losses`), " ..
		"`draws` = VALUES(`draws`), `peak` = VALUES(`peak`), `last_match` = VALUES(`last_match`)", T("ratings"),
		P.load(guid).season, guid, db.escapeString(bracket), row.rating, math.floor(row.rd + 0.5), row.matches, row.wins,
		row.losses, row.draws, row.peak or row.rating, row.last or 0))
end

function P.viewOf(guid)
	local rows, now = P.load(guid), os.time()
	local out = {}
	for _, b in ipairs(C().season.brackets) do
		local v = K.view(C(), rows[b], now)
		out[b] = {rating = v.rating, rd = v.rd, matches = v.matches, wins = v.wins, losses = v.losses, draws = v.draws,
			peak = v.peak, placed = v.placed, placementLeft = v.placementLeft, tier = v.tierIndex, tierName = v.tier.name,
			color = v.tier.color, decayIn = v.decayIn, name = C().season.bracketNames[b]}
	end
	return out
end

-- one rated match of a bracket
function P.record(bracket, teams, winner)
	local now = os.time()
	local rated = {{}, {}}
	for side = 1, 2 do
		for _, e in ipairs(teams[side]) do
			local row = P.rowOf(e.guid, bracket)
			-- decay and the idle rd growth happen before the match counts
			row.rating = (K.decay(C(), row.rating, row.last, now))
			if row.last and row.last > 0 then
				row.rd = K.inflate(C(), row.rd, now - row.last)
			end
			table.insert(rated[side], {guid = e.guid, rating = row.rating, rd = row.rd, left = e.left, row = row})
		end
	end
	K.rateTeams(C(), rated, winner)
	local out = {}
	for side = 1, 2 do
		for _, p in ipairs(rated[side]) do
			local row = p.row
			row.rating, row.rd = p.after, p.rdAfter
			row.matches = row.matches + 1
			if p.score == 1 then
				row.wins = row.wins + 1
			elseif p.score == 0 then
				row.losses = row.losses + 1
			else
				row.draws = row.draws + 1
			end
			row.peak = math.max(row.peak or row.rating, row.rating)
			row.last = now
			save(p.guid, bracket, row)
			local v = K.view(C(), row, now)
			out[p.guid] = {before = p.before, after = p.after, delta = p.delta, tier = v.tierIndex, tierName = v.tier.name,
				color = v.tier.color, placed = v.placed, placementLeft = v.placementLeft}
		end
	end
	return out
end

-- arena.lua finish(): `sides` are its two team lists (guid, name, left)
function P.recordArena(mode, sides, winner)
	if mode ~= "1v1" and mode ~= "2v2" and mode ~= "3v3" then
		return nil
	end
	return P.record(mode, sides, winner)
end

-- ---------------------------------------------------------------- titles
function P.loadTitles(guid)
	P.titles[guid] = Chaos.select(string.format("SELECT `season`, `tier`, `title`, `frame`, `granted_at` FROM `%s` WHERE " ..
		"`player_id` = %d AND `title` <> '' ORDER BY `season`", T("rewards"), guid),
		{{"season", "n"}, {"tier", "n"}, {"title", "s"}, {"frame", "s"}, {"granted_at", "n"}})
	return P.titles[guid]
end

function P.titlesOf(guid)
	return P.titles[guid] or {}
end

if ChaosTitles and ChaosTitles.register then
	ChaosTitles.register("pvpseason", function(player)
		local out = {}
		for _, t in ipairs(P.titlesOf(player:getGuid())) do
			local tier = C().season.tiers[t.tier]
			out[#out + 1] = {key = "pvpseason:" .. t.season, text = t.title, at = t.granted_at,
				color = tier and tier.color or nil, frame = t.frame ~= "" and t.frame or nil}
		end
		return out
	end)
end

-- ---------------------------------------------------------------- the season's end
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

local function onlineByGuid(guid)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getGuid() == guid then
			return p
		end
	end
	return nil
end

-- hand out the rewards of an ended season (every character with a placed bracket). Idempotent: one reward row per
-- season and character (INSERT IGNORE), the cosmetics only when not owned, the honor only with a new row.
function P.processSeason(seasonId)
	local cfg = C()
	local endAt = K.epoch(cfg) + seasonId * K.seasonLength(cfg)
	local rows = Chaos.select(string.format("SELECT r.`player_id`, r.`bracket`, r.`rating`, r.`rd`, r.`matches`, r.`last_match`, " ..
		"p.`account_id`, p.`group_id` FROM `%s` r JOIN `players` p ON p.`id` = r.`player_id` WHERE r.`season` = %d",
		T("ratings"), seasonId), {{"player_id", "n"}, {"bracket", "s"}, {"rating", "n"}, {"rd", "n"}, {"matches", "n"},
		{"last_match", "n"}, {"account_id", "n"}, {"group_id", "n"}})
	local byPlayer = {}
	for _, r in ipairs(rows) do
		if r.group_id < cfg.staffGroup then
			local e = byPlayer[r.player_id] or {account = r.account_id, rows = {}}
			e.rows[r.bracket] = {rating = r.rating, rd = r.rd, matches = r.matches, last = r.last_match}
			byPlayer[r.player_id] = e
		end
	end
	local n = 0
	for guid, e in pairs(byPlayer) do
		local tierIndex, bracket, rating = K.bestTier(cfg, e.rows, endAt)
		if tierIndex then
			local rw = K.seasonReward(cfg, tierIndex, seasonId)
			local exists = Chaos.select(string.format("SELECT `tier` FROM `%s` WHERE `season` = %d AND `player_id` = %d",
				T("rewards"), seasonId, guid), {{"tier", "n"}})
			if #exists == 0 then
				db.query(string.format("INSERT IGNORE INTO `%s` (`season`, `player_id`, `account_id`, `tier`, `bracket`, `rating`, `honor`, " ..
					"`title`, `frame`, `cosmetics`, `granted_at`) VALUES (%d, %d, %d, %d, %s, %d, %d, %s, %s, %s, %d)", T("rewards"),
					seasonId, guid, e.account, tierIndex, db.escapeString(bracket), rating, rw.honor, db.escapeString(rw.title or ""),
					db.escapeString(rw.frame or ""), db.escapeString(table.concat(rw.cosmetics, ",")), os.time()))
				if rw.honor > 0 then
					if ChaosBattleground and ChaosBattleground.addHonor then
						ChaosBattleground.addHonor(guid, rw.honor, false)
					end
				end
				for _, key in ipairs(rw.cosmetics) do
					local CM = ChaosCosmetics
					if CM and CM.grant and not CM.owns(e.account, key) then
						local ok, err = CM.grant(e.account, key, "pvp")
						if not ok then
							log(string.format("cosmetic %s for account %d: %s", key, e.account, tostring(err)))
						end
					end
				end
				if ChaosAchievements and ChaosAchievements.set then
					pcall(ChaosAchievements.set, guid, "pvp_season_tier", tierIndex)
				end
				n = n + 1
				local p = onlineByGuid(guid)
				if p then
					P.loadTitles(guid)
					if ChaosNameplate and ChaosNameplate.refresh then
						pcall(ChaosNameplate.refresh, p)
					end
					p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "PvP Season %d has ended: you finished %s (%s, rating %d).%s",
						seasonId, rw.tier.name, cfg.season.bracketNames[bracket] or bracket, rating,
						rw.title and Chaos.t(p, " Title: %s.", rw.title) or ""))
				end
			end
		end
	end
	log(string.format("season %d ended: rewards for %d character(s)", seasonId, n))
	return n
end

function P.check(startup)
	local cfg = C()
	local id = P.current()
	local done = getConfig(cfg.season.configKey)
	if not done then
		setConfig(cfg.season.configKey, id - 1) -- a new server: nothing earlier to hand out
		return
	end
	for s = done + 1, id - 1 do
		local ok, err = pcall(P.processSeason, s)
		if not ok then
			log("season end failed: " .. tostring(err))
			return
		end
		setConfig(cfg.season.configKey, s)
		if not startup then
			Chaos.broadcast(MESSAGE_STATUS_WARNING, "PvP Season %d has ended. Season %d begins: ratings were softly reset; the season rewards are handed out.",
				s, s + 1)
		end
	end
	-- a season changed while characters were online: their cached rows are of the old season
	for guid, rows in pairs(P.rows) do
		if rows.season ~= id then
			P.rows[guid] = nil
		end
	end
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosPvpSeasonStartup")
function startup.onStartup()
	P.ensureTables()
	local ok, err = pcall(P.check, true)
	if not ok then
		log("startup check failed: " .. tostring(err))
	end
	return true
end
startup:register()

local think = GlobalEvent("ChaosPvpSeasonThink")
function think.onThink(interval)
	local now = os.time()
	if now - P.lastCheck >= C().season.checkSeconds then
		P.lastCheck = now
		local ok, err = pcall(P.check, false)
		if not ok then
			log("check failed: " .. tostring(err))
		end
	end
	return true
end
think:interval(10000)
think:register()

local login = CreatureEvent("ChaosPvpSeasonLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPvpSeasonLogout")
	local guid = player:getGuid()
	P.load(guid, true)
	P.loadTitles(guid)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPvpSeasonLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	P.rows[guid] = nil
	P.titles[guid] = nil
	return true
end
logout:type("logout")
logout:register()


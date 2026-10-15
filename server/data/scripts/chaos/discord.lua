-- Discord announcements (server/README.md "Discord announcements"): the game writes rows to chaos_discord_queue
-- (server/sql/chaos_discord.sql); the website's worker (plugins/chaos/discord_worker.php, run by cron or
-- server/deploy/chaos-discord.timer) posts them to Discord channel webhooks from the environment
-- (CHAOS_DISCORD_WEBHOOK_<CHANNEL>). No HTTP on the game loop (one asynchronous INSERT per event), no bot, no token in
-- the repository, no account linking. Switches, channels, milestones and rate limits: discord_config.lua; texts and
-- rules: discord_core.lua (tests/discord_test.lua).
--
-- Sources (public functions wrapped once, wrapchain_core.lua; installed at load, at startup and every minute):
--   ChaosRecordsCore.recordText / firstText   a beaten all-time record and a realm first (the texts records.lua
--                                             broadcasts: only while its announceRecord / announceFirst are on)
--   ChaosWorldBoss.start                      a world boss event starts
--   ChaosRecords.submit                       accepted runs: world boss kills (wb_time), Ascended and Cinderheart kills
--                                             (ascended) with the kill time and the fighters
--   advance event (registered at login)       levels of levelMilestones
--   a minute clock                            season start / end (ChaosSeason.current(); the id last announced is kept
--                                             in server_config, so a restart does not announce again)
--   startup / shutdown                        server up; the daily restart (a shutdown just after the server save
--                                             time of globalevents.xml) or down
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/discord_config.lua")
dofile("data/scripts/chaos/discord_core.lua")
dofile("data/scripts/chaos/wrapchain_core.lua")

local cfg = ChaosDiscordConfig
local D = ChaosDiscordCore

ChaosDiscord = ChaosDiscord or {}
local X = ChaosDiscord
X.rate = X.rate or {}
X.sent = X.sent or 0

local function log(text)
	print("[Chaos discord] " .. tostring(text))
end

local function esc(s)
	return db.escapeString(tostring(s))
end

local function serverName()
	local ok, name = pcall(function() return configManager.getString(configKeys.SERVER_NAME) end)
	return ok and name or nil
end

-- queue one event (sync: during shutdown, when the async queue may not run any more)
function X.queue(ev, sync)
	if not ev or not D.enabled(cfg, ev.kind) then
		return false
	end
	local now = os.time()
	if not D.allow(X.rate, cfg, ev.kind, now) then
		return false
	end
	local sql = D.insertSql(cfg.table, ev, now, esc, json.encode)
	if sync then
		db.query(sql)
	else
		db.asyncQuery(sql)
	end
	X.sent = X.sent + 1
	return true
end

local function try(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(err))
	end
end

-- ---------------------------------------------------------------- hooks
local function nameOf(m)
	if type(m) == "userdata" then
		local ok, n = pcall(function() return m:getName() end)
		return ok and n or nil
	end
	return type(m) == "table" and m.name or nil
end

local function variantName(board, key)
	local R = ChaosRecords
	local b = R and R.byKey and R.byKey[board]
	for _, v in ipairs(b and b.variants or {}) do
		if v.key == key then
			return v.name or key
		end
	end
	return key
end

-- records.lua builds a broadcast text once per language of the players online (the last argument, lang; nil or "en"
-- is English): only the English text is posted, and the same text twice within a few seconds only once
X.lastText = X.lastText or {}
local function postText(kind, text, lang)
	if type(text) ~= "string" or (lang ~= nil and lang ~= "en") then
		return
	end
	local last = X.lastText[kind]
	local now = os.time()
	if last and last.text == text and now - last.at <= 5 then
		return
	end
	X.lastText[kind] = {text = text, at = now}
	X.queue(kind == "first" and D.first(cfg, text) or D.record(cfg, text))
end

local function onRecordText(res, board, variant, size, value, members, prev, lang)
	postText("record", res[1], lang)
end

local function onFirstText(res, display, members, seasonName, lang)
	postText("first", res[1], lang)
end

local function onWorldBossStart(res)
	if not res[1] then
		return
	end
	local W, c = ChaosWorldBoss, Chaos.worldBoss
	local b = W and W.state and c and c.bosses and c.bosses[W.state.index]
	if b then
		X.queue(D.worldBossSpawn(cfg, b.name, c.minLevel))
	end
end

local function onRecordRun(res, run)
	if not res[1] or type(run) ~= "table" then
		return
	end
	local kind
	if run.board == "wb_time" then
		kind = "worldboss_kill"
	elseif run.board == "ascended" then
		kind = run.variant == "cinder" and "cinderheart_kill" or "ascended_kill"
	else
		return
	end
	local names = {}
	for _, m in ipairs(run.members or {}) do
		local n = nameOf(m)
		if n then
			names[#names + 1] = n
		end
	end
	table.sort(names)
	local boss = kind == "cinderheart_kill" and "The Cinderheart" or variantName(run.board, run.variant)
	X.queue(D.bossKill(cfg, kind, boss, run.value, names))
end

function X.installHooks()
	local W = ChaosWrapChain
	W.wrap(ChaosRecordsCore, "recordText", "discord", onRecordText, log)
	W.wrap(ChaosRecordsCore, "firstText", "discord", onFirstText, log)
	W.wrap(ChaosWorldBoss, "start", "discord", onWorldBossStart, log)
	W.wrap(ChaosRecords, "submit", "discord", onRecordRun, log)
end

-- ---------------------------------------------------------------- levels
function X.onAdvance(player, skill, oldLevel, newLevel)
	if skill ~= SKILL_LEVEL or not D.enabled(cfg, "level") then
		return
	end
	if player:getGroup():getId() >= (cfg.staffGroup or 4) then
		return
	end
	for _, m in ipairs(D.milestones(oldLevel, newLevel, cfg.levelMilestones)) do
		local ok, voc = pcall(function() return player:getVocation():getName() end)
		X.queue(D.level(cfg, player:getName(), m, ok and voc or nil))
	end
end

local advance = CreatureEvent("ChaosDiscordAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	try("advance", X.onAdvance, player, skill, oldLevel, newLevel)
	return true
end
advance:register()

local login = CreatureEvent("ChaosDiscordLogin")
function login.onLogin(player)
	player:registerEvent("ChaosDiscordAdvance")
	return true
end
login:type("login")
login:register()

-- ---------------------------------------------------------------- seasons
local function getConfig(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. esc(key))
	if not id then
		return nil
	end
	local v = result.getString(id, "value")
	result.free(id)
	return tonumber(v)
end

local function setConfig(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", esc(key), esc(tostring(value))))
end

local function seasonById(id)
	for _, s in ipairs(Chaos.seasonConfig and Chaos.seasonConfig.seasons or {}) do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- the season running now against the one last announced; the first check ever only records it
function X.checkSeason()
	local S = ChaosSeason
	if not S or not S.current then
		return
	end
	local season = S.current()
	local id = season and season.id or 0
	if X.lastSeason == nil then
		X.lastSeason = getConfig(cfg.seasonKey) or false -- read once; false = never recorded
	end
	local last = X.lastSeason
	if last == id then
		return
	end
	setConfig(cfg.seasonKey, id)
	X.lastSeason = id
	if last == false then
		return
	end
	if last > 0 then
		X.queue(D.season(cfg, "season_end", seasonById(last)))
	end
	if season then
		X.queue(D.season(cfg, "season_start", season))
	end
end

-- ---------------------------------------------------------------- server status
local function saveTime()
	local f = io.open("data/globalevents/globalevents.xml", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return D.saveTime(text)
end

local startup = GlobalEvent("ChaosDiscordStartup")
function startup.onStartup()
	if cfg.enabled == false then
		return true
	end
	db.query(D.schemaSql(cfg.table))
	X.installHooks()
	try("season", X.checkSeason)
	X.queue(D.status(cfg, "status_up", serverName()))
	return true
end
startup:register()

local shutdown = GlobalEvent("ChaosDiscordShutdown")
function shutdown.onShutdown()
	if cfg.enabled == false then
		return true
	end
	local hour, min = saveTime()
	local kind = D.isDailyRestart(os.date("*t"), hour, min, cfg.restartWindowMinutes) and "status_restart" or "status_down"
	try("shutdown", X.queue, D.status(cfg, kind, serverName()), true)
	return true
end
shutdown:register()

local think = GlobalEvent("ChaosDiscordClock")
function think.onThink(interval)
	if cfg.enabled == false then
		return true
	end
	X.installHooks() -- again after a /reload of a wrapped script
	try("season", X.checkSeason)
	return true
end
think:interval((cfg.checkSeconds or 60) * 1000)
think:register()

pcall(X.installHooks)

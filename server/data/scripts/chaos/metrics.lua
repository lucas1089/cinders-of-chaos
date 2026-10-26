-- Progress metrics (server/README.md "Progress metrics (O253)"; rules in metrics_core.lua, numbers in metrics_config.lua).
-- Anonymous counters so balance can be tuned from real data; the admin app shows them (chaos-ctl.sh metrics --json):
--   deaths     per area (instance, or the nearest hunt) and per killer monster, per level band
--   first session  minutes played in the first session of a new character, in buckets
--   time to level  played minutes at the first time a character reaches 10 / 25 / 50 / 100 / 200 (a histogram)
--   churn      per level band: characters whose last login is older than churnDays, and the active ones (one GROUP BY
--              on `players` at startup and daily; nothing is stored per player)
-- Counters live in memory and are added to chaos_progress_metrics every flushSeconds and at shutdown. A tester bot
-- (Chaos.isTester) and a staff character (group id above cfg.maxGroupId) are never counted. No name, account id, IP
-- or chat is read into a counter or stored.
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout/death/advance, GlobalEvent startup/think/shutdown,
-- Player:getGroup():getId(), getLastLoginSaved, getGuid, getLevel, getPosition, getStorageValue/setStorageValue,
-- db.query/asyncQuery/storeQuery/escapeString, players.onlinetime (seconds, saved at logout).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMetrics or not ChaosMetrics.areaFor then
	dofile("data/scripts/chaos/metrics_core.lua")
end

Chaos.metricsConfig = dofile("data/scripts/chaos/metrics_config.lua")
local cfg = Chaos.metricsConfig
local X = ChaosMetrics
local T = Chaos.tables.progressMetrics or "chaos_progress_metrics"
local PLACES = "data/lib/chaos_hunt_places.lua"

X.state = X.state or X.newState()
X.sessions = X.sessions or {} -- player id -> {at (login time), first (first login ever), mask, guid}; memory only
X.spots = X.spots or {}
X.lastFlush, X.lastChurn = X.lastFlush or 0, X.lastChurn or 0

local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		print("[Warning - ChaosMetrics] " .. label .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local tableReady
local function ensureTable()
	if tableReady == nil then
		tableReady = db.query(X.createSql(T)) and true or false
	end
	return tableReady
end

-- the hunts' arrival tiles, to name the area of a death outside an instance
function X.loadSpots()
	X.spots = {}
	local f = io.open(PLACES, "r")
	if not f then
		return
	end
	f:close()
	local ok, places = pcall(dofile, PLACES)
	if not ok or type(places) ~= "table" then
		return
	end
	local function add(name, pos)
		if type(name) == "string" and type(pos) == "table" and pos.x and pos.y and pos.z then
			X.spots[#X.spots + 1] = {name = name, x = pos.x, y = pos.y, z = pos.z}
		end
	end
	for _, e in ipairs(type(places.places) == "table" and places.places or {}) do
		add(e.name or e.id, e.arrival)
	end
	for _, e in ipairs(type(places.base) == "table" and places.base or {}) do
		add(e.name or e.id, e.dest or e.arrival)
	end
end

local function counted(player)
	local group = 0
	local ok, g = pcall(function() return player:getGroup():getId() end)
	if ok and g then
		group = g
	end
	return X.eligible(group, Chaos.isTester(player), cfg)
end

-- ---------------------------------------------------------------- flush
function X.flush(final)
	if not ensureTable() then
		return
	end
	local run = final and db.query or db.asyncQuery
	for _, q in ipairs(X.flushSql(X.state, T, db.escapeString)) do
		run(q)
	end
end

-- the churn snapshot: one GROUP BY, the answer is one row per band
function X.computeChurn()
	if not ensureTable() then
		return
	end
	local now = os.time()
	local q = X.churnSql(cfg, now, Chaos.notTesterSql("`players`"))
	local rows = Chaos.select(q, {{"band", "n"}, {"gone", "n"}, {"active", "n"}})
	local sql = X.setSql(X.churnRows(rows, cfg, now), T, db.escapeString)
	if sql then
		db.asyncQuery(sql)
	end
	X.lastChurn = now
end

-- ---------------------------------------------------------------- events
local function mask(player)
	local v = player:getStorageValue(cfg.storage)
	return (v and v > 0) and v or 0
end

function X.onLogin(player)
	player:registerEvent("ChaosMetricsDeath")
	player:registerEvent("ChaosMetricsLogout")
	player:registerEvent("ChaosMetricsAdvance")
	X.sessions[player:getId()] = nil
	if not cfg.enabled or not counted(player) then
		return
	end
	local m = mask(player)
	local newMask = X.maskAtLogin(player:getLevel(), m, cfg)
	if newMask ~= m then
		player:setStorageValue(cfg.storage, newMask)
	end
	X.sessions[player:getId()] = {at = os.time(), first = player:getLastLoginSaved() == 0, guid = player:getGuid()}
end

function X.onLogout(player)
	local s = X.sessions[player:getId()]
	X.sessions[player:getId()] = nil
	if s and s.first then
		local minutes = X.sessionMinutes(os.time() - s.at)
		X.add(X.state, "session1", X.bucketLabel(minutes, cfg.sessionBuckets), "", 1, cfg)
	end
end

local function killerOf(killer)
	if not killer then
		return "other"
	end
	if killer:isPlayer() then
		return "player"
	end
	if killer:isMonster() then
		local master = killer:getMaster()
		if master and master:isPlayer() then
			return "summon"
		end
		return "monster", killer:getName()
	end
	return "other"
end

function X.onDeath(player, killer)
	if not cfg.enabled or not X.sessions[player:getId()] then
		return
	end
	local band = X.bandOf(player:getLevel(), cfg.bands)
	local okI, _, label = pcall(Chaos.inAnyInstance, player)
	local area = X.areaFor(player:getPosition(), okI and label or nil, X.spots, cfg)
	local kind, name = killerOf(killer)
	X.add(X.state, "death_area", area, band, 1, cfg)
	X.add(X.state, "death_monster", X.killerName(kind, name, cfg), band, 1, cfg)
end

function X.onAdvance(player, oldLevel, newLevel)
	local s = X.sessions[player:getId()]
	if not cfg.enabled or not s then
		return
	end
	local crossed, newMask = X.milestonesCrossed(oldLevel, newLevel, mask(player), cfg)
	if #crossed == 0 then
		if newMask ~= mask(player) then
			player:setStorageValue(cfg.storage, newMask)
		end
		return
	end
	player:setStorageValue(cfg.storage, newMask)
	local base = Chaos.select(string.format("SELECT `onlinetime` AS `t` FROM `players` WHERE `id` = %d", s.guid),
		{{"t", "n"}})[1]
	local minutes = X.sessionMinutes((base and base.t or 0) + (os.time() - s.at))
	for _, m in ipairs(crossed) do
		X.add(X.state, "ttl", tostring(m), X.bucketLabel(minutes, cfg.timeBuckets), 1, cfg)
	end
end

local death = CreatureEvent("ChaosMetricsDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	if creature:isPlayer() then
		try("death", X.onDeath, creature, killer or mostDamageKiller)
	end
	return true
end
death:type("death")
death:register()

local advance = CreatureEvent("ChaosMetricsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL then
		try("advance", X.onAdvance, player, oldLevel, newLevel)
	end
	return true
end
advance:type("advance")
advance:register()

local login = CreatureEvent("ChaosMetricsLogin")
function login.onLogin(player)
	try("login", X.onLogin, player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosMetricsLogout")
function logout.onLogout(player)
	try("logout", X.onLogout, player)
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- global events
local startup = GlobalEvent("ChaosMetricsStartup")
function startup.onStartup()
	ensureTable()
	try("spots", X.loadSpots)
	X.startedAt = os.time()
	X.lastFlush = os.time()
	return true
end
startup:type("startup")
startup:register()

local think = GlobalEvent("ChaosMetricsThink")
function think.onThink(interval)
	if not cfg.enabled then
		return true
	end
	local t = os.time()
	if t - X.lastFlush >= cfg.flushSeconds then
		X.lastFlush = t
		try("flush", X.flush)
	end
	if X.lastChurn == 0 then
		if t - (X.startedAt or t) >= cfg.churnDelaySeconds then
			try("churn", X.computeChurn)
		end
	elseif t - X.lastChurn >= cfg.churnEverySeconds then
		try("churn", X.computeChurn)
	end
	return true
end
think:interval(60000)
think:register()

local shutdown = GlobalEvent("ChaosMetricsShutdown")
function shutdown.onShutdown()
	try("flush", X.flush, true)
	return true
end
shutdown:type("shutdown")
shutdown:register()

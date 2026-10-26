-- Progress metrics (server/README.md "Progress metrics (O253)"; rules in metrics_core.lua, numbers in metrics_config.lua).
-- Anonymous counters so balance can be tuned from real data; the admin app shows them (chaos-ctl.sh metrics --json):
--   deaths     per area (instance, or the nearest hunt) and per killer monster, per level band
--   first session  minutes played in the first session of a new character, in buckets
--   time to level  played minutes at the first time a character reaches 10 / 25 / 50 / 100 / 200 (a histogram)
--   churn      per level band: characters whose last login is older than churnDays, and the active ones (one GROUP BY
--              on `players` at startup and daily; nothing is stored per player)
-- O258 funnel ("Funnel metrics (O258)" in server/README.md): return (d1 / d3 / d7 per first-login day), first use of a
--   system (ChaosMetrics.firstUse, called by wrapped success paths), where the gone characters stood (area and band).
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
if not ChaosMetrics or not ChaosMetrics.areaFor or not ChaosMetrics.returnCheck then
	dofile("data/scripts/chaos/metrics_core.lua")
end
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end

Chaos.metricsConfig = dofile("data/scripts/chaos/metrics_config.lua")
local cfg = Chaos.metricsConfig
local X = ChaosMetrics
local T = Chaos.tables.progressMetrics or "chaos_progress_metrics"
local PLACES = "data/lib/chaos_hunt_places.lua"

X.state = X.state or X.newState()
X.sessions = X.sessions or {} -- player id -> {at (login time), first (first login ever), mask, guid}; memory only
X.spots = X.spots or {}
X.lastFlush, X.lastChurn, X.lastMembers = X.lastFlush or 0, X.lastChurn or 0, X.lastMembers or 0

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
	local function add(name, pos, sid)
		if type(name) == "string" and type(pos) == "table" and pos.x and pos.y and pos.z then
			X.spots[#X.spots + 1] = {name = name, x = pos.x, y = pos.y, z = pos.z, sid = sid}
		end
	end
	local seen = {}
	local function id(e)
		local sid = e.id ~= nil and X.stableId(e.id) or nil
		if sid and seen[sid] and seen[sid] ~= tostring(e.id) then
			print("[Warning - ChaosMetrics] hunt ids " .. seen[sid] .. " and " .. tostring(e.id) .. " share a stored id")
			return nil
		end
		if sid then
			seen[sid] = tostring(e.id)
		end
		return sid
	end
	for _, e in ipairs(type(places.places) == "table" and places.places or {}) do
		add(e.name or e.id, e.arrival, id(e))
	end
	for _, e in ipairs(type(places.base) == "table" and places.base or {}) do
		add(e.name or e.id, e.dest or e.arrival, id(e))
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
	-- O258 where they stop: the area and band of the gone characters, a snapshot (the old rows are replaced)
	local stops = Chaos.select(X.stopSql(cfg, now, Chaos.notTesterSql("`players`")),
		{{"band", "n"}, {"sid", "n"}, {"pz", "n"}, {"cx", "n"}, {"cy", "n"}, {"gone", "n"}})
	-- a failed query reads as no rows: keep the last snapshot then rather than wiping it until the next run
	if #stops == 0 then
		X.lastChurn = now
		return
	end
	db.query("DELETE FROM `" .. T .. "` WHERE `kind` = 'stop'")
	for _, q in ipairs(X.setSqlChunks(X.stopRows(stops, X.spots, cfg), T, db.escapeString)) do
		db.asyncQuery(q)
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
	player:registerEvent("ChaosMetricsKill")
	X.sessions[player:getId()] = nil
	if not cfg.enabled or not counted(player) then
		return
	end
	local m = mask(player)
	local newMask = X.maskAtLogin(player:getLevel(), m, cfg)
	if newMask ~= m then
		player:setStorageValue(cfg.storage, newMask)
	end
	local first = player:getLastLoginSaved() == 0
	local hunt = player:getStorageValue(cfg.huntStorage)
	X.sessions[player:getId()] = {at = os.time(), first = first, guid = player:getGuid(), hunt = hunt > 0 and hunt or nil}
	try("return", X.countReturn, player, first)
	-- already in a guild at login: not a first use (a join during the session is found by memberCheck)
	if player:getGuild() then
		local fm = player:getStorageValue(cfg.firstStorage)
		local _, nm = X.firstUseMark(fm > 0 and fm or 0, "guild", cfg)
		if nm ~= fm then
			player:setStorageValue(cfg.firstStorage, nm)
		end
	end
end

-- ---------------------------------------------------------------- O258: return
-- server time: seconds east of UTC now (the engine reads the local clock)
function X.timeOffset(t)
	t = t or os.time()
	local ok, off = pcall(function()
		return os.time(os.date("*t", t)) - os.time(os.date("!*t", t))
	end)
	return ok and off or 0
end

function X.today(t)
	t = t or os.time()
	return X.dayNumber(t, X.timeOffset(t))
end

-- a first login stores today and counts the cohort; a later login counts d1 / d3 / d7 once each
function X.countReturn(player, first)
	local today = X.today()
	local stored = player:getStorageValue(cfg.returnStorage)
	if first and stored <= 0 then
		player:setStorageValue(cfg.returnStorage, X.returnStart(today))
		X.add(X.state, "cohort", X.dayString(today), "", 1, cfg)
		return
	end
	local due, new, cohort = X.returnCheck(stored, today, cfg)
	if #due == 0 then
		return
	end
	player:setStorageValue(cfg.returnStorage, new)
	for _, d in ipairs(due) do
		X.add(X.state, "return", d, X.dayString(cohort), 1, cfg)
	end
end

-- ---------------------------------------------------------------- O258: first use of a system
-- called by the success path of each system (the wraps in X.installHooks); once per character and system
function X.firstUse(player, key)
	if not cfg.enabled then
		return false
	end
	local s = player and X.sessions[player:getId()]
	if not s then
		return false
	end
	local m = player:getStorageValue(cfg.firstStorage)
	local isNew, newMask = X.firstUseMark(m > 0 and m or 0, key, cfg)
	if not isNew then
		return false
	end
	player:setStorageValue(cfg.firstStorage, newMask)
	if s.base == nil then
		local row = Chaos.select(string.format("SELECT `onlinetime` AS `t` FROM `players` WHERE `id` = %d", s.guid),
			{{"t", "n"}})[1]
		s.base = row and row.t or 0
	end
	local minutes = X.sessionMinutes(s.base + (os.time() - s.at))
	X.add(X.state, "first", key, X.bandOf(player:getLevel(), cfg.bands) .. "|" .. X.playedBucket(minutes, cfg), 1, cfg)
	return true
end

-- party and guild have no success hook of their own: the open sessions are looked at every memberCheckSeconds
function X.memberCheck()
	for _, player in ipairs(Game.getPlayers()) do
		local s = X.sessions[player:getId()]
		if s then
			local m = player:getStorageValue(cfg.firstStorage)
			m = m > 0 and m or 0
			local needParty = X.firstUseMark(m, "party", cfg)
			local needGuild = X.firstUseMark(m, "guild", cfg)
			if needGuild and player:getGuild() then
				X.firstUse(player, "guild")
			end
			if needParty then
				local party = player:getParty()
				if party and #(party:getMembers() or {}) >= 1 then
					X.firstUse(player, "party")
				end
			end
		end
	end
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

-- O258 last hunt: a kill of a monster by a counted character, at most once per cfg.huntSeconds, only on a tile that is
-- not a protection zone, outside the instances, near a hunt's arrival tile. The storage is written when the hunt changes.
function X.onKill(player, target)
	local s = cfg.enabled and X.sessions[player:getId()]
	if not s or not target or not target:isMonster() then
		return
	end
	local now = os.time()
	if s.huntAt and now - s.huntAt < cfg.huntSeconds then
		return
	end
	local okT, tile = pcall(function() return player:getTile() end)
	if okT and tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		s.huntAt = now
		return
	end
	local okI, inside = pcall(Chaos.inAnyInstance, player)
	if okI and inside then
		s.huntAt = now
		return
	end
	local sid = X.huntMark(s, player:getPosition(), now, X.spots, cfg)
	if sid then
		player:setStorageValue(cfg.huntStorage, sid)
	end
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

-- ---------------------------------------------------------------- O258: hooks into the systems
-- The existing public APIs are wrapped through ChaosWrapChain (like community.lua); installed at startup and again every
-- minute (a /reload of the wrapped script puts the hook back). Pocket Boss calls X.firstUse from its success path.
local function onlinePlayer(who)
	local t = type(who)
	if t == "userdata" or (t == "table" and who.getGuid) then
		return who
	end
	if t == "table" and who.name then
		local p = Player(who.name)
		if p and (not who.guid or p:getGuid() == who.guid) then
			return p
		end
	end
	return nil
end

local BOARD_SYSTEM = {rift = "rift", bounty = "bounty", defender = "invasion", worldboss = "worldboss"}

function X.installHooks()
	local W = ChaosWrapChain
	local function log(e)
		print("[Warning - ChaosMetrics] hook: " .. tostring(e))
	end
	-- rifts sealed, bounty contracts, invasion waves repelled, world boss shares: the leaderboard boards
	W.wrap(ChaosLeaderboard, "record", "metrics", function(res, board, who)
		local key = BOARD_SYSTEM[board]
		local p = key and onlinePlayer(who)
		if p then
			X.firstUse(p, key)
		end
	end, log)
	-- a dungeon clear (dungeons.lua endRun, every member)
	W.wrap(ChaosSeasonJourney, "emit", "metrics", function(res, player, stat)
		if stat == "dungeon_clears" and player then
			X.firstUse(player, "dungeon")
		end
	end, log)
	-- an Infinity Tower run with a floor cleared
	W.wrap(ChaosTower, "recordRun", "metrics", function(res, player, floors)
		if player and (tonumber(floors) or 0) >= 1 then
			X.firstUse(player, "tower")
		end
	end, log)
	-- a waystone opened a map (the opener's guid)
	W.wrap(ChaosWaystoneAtlas, "beginRun", "metrics", function(res, i, t, mods)
		local guid = type(mods) == "table" and tonumber(mods.opener)
		local p = guid and Player(guid)
		if p then
			X.firstUse(p, "waystone")
		end
	end, log)
	-- the market: a listing or a purchase that went through
	W.wrap(ChaosMarket, "list", "metrics", function(res, player)
		if res[1] == true and player then
			X.firstUse(player, "market")
		end
	end, log)
	W.wrap(ChaosMarket, "buy", "metrics", function(res, player)
		if res[1] == true and player then
			X.firstUse(player, "market")
		end
	end, log)
	-- the crafting bench and the orbs: the item's owner
	W.wrap(ChaosCrafting, "apply", "metrics", function(res, orbKey, item)
		if res[1] and item then
			local ok, top = pcall(function() return item:getTopParent() end)
			if ok and top and top.isPlayer and top:isPlayer() then
				X.firstUse(top, "craft")
			end
		end
	end, log)
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

local kill = CreatureEvent("ChaosMetricsKill")
function kill.onKill(creature, target)
	if creature:isPlayer() then
		try("kill", X.onKill, creature, target)
	end
	return true
end
kill:type("kill")
kill:register()

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
	try("hooks", X.installHooks)
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
	try("hooks", X.installHooks)
	if t - X.lastMembers >= cfg.memberCheckSeconds then
		X.lastMembers = t
		try("members", X.memberCheck)
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

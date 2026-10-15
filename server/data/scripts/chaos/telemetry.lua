-- Balance telemetry for staff (roadmap: balance telemetry; website page.php?plugin=chaos&p=telemetry, group 5+).
-- Hourly aggregates in the chaos_telemetry_* tables (server/sql/chaos_telemetry.sql); numbers in telemetry_config.lua;
-- pure logic in telemetry_core.lua (tests/telemetry_test.lua). Overview: server/README.md "Balance telemetry".
--
-- Sources (existing data first; no content script was edited):
--   hunting     every cfg.sampleSeconds the hunt tracker's session counters of each online character (ChaosHunt
--               .sessions: experience, loot value, supplies value, kills, session clock), as deltas since the last
--               sample -> exp/h, gold/h (loot minus supplies), kills per level band and class
--   online      the same sample: characters online per level band and class, and in total
--   bosses      the runs the competitive records accept (ChaosRecords.submit wrapped: world boss, Ascended and
--               Cinderheart, guild boss, Omen guardians: time and party size), and the map bosses of the boss spawns
--               tracker (ChaosBossSpawns.onDeath wrapped: party = players in the damage map, time since the first hit
--               by a player, read by a healthchange event this file puts on tracked bosses at spawn)
--   deaths      a death event registered at login: level band, area (instance, hunting place, nearest town), killer
--               (monster type; "a player" for PvP: no names)
--   spell casts ChaosSpellEvents "cast" (the same engine event the combat log reads): casts per class and spell
--   economy     faucets: loot value (hunt tracker), Loot Bag sales (ChaosAutoSell.sellBag wrapped), the corpse Auto
--               Seller (needs the one-line hook ChaosTelemetry.economy in autosell.lua, server/README.md); sinks:
--               supplies used (runes, potions, ammunition at the NPC price: the hunt tracker), respec and skill
--               resets (ChaosRespec.pay wrapped). Store coins per category come from chaos_shop_purchases directly
--               (the website reads it; not copied).
-- Privacy: per-character numbers (the last hunt counters, the guid sets that count distinct characters per bucket) live
-- in memory only and are dropped when the hour is written; no row holds a character id, a name or an account.
-- Staff characters (group >= cfg.staffGroup) are left out. Retention: hourly rows for cfg.hourlyDays, then one daily row
-- per day, kept cfg.dailyDays.
--   /telemetry          (gods) the hour in memory: buckets, samples; /telemetry flush writes it now
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/telemetry_config.lua")
dofile("data/scripts/chaos/telemetry_core.lua")
dofile("data/scripts/chaos/wrapchain_core.lua")

local cfg = ChaosTelemetryConfig
local K = ChaosTelemetryCore
local T_ = cfg.tables

ChaosTelemetry = ChaosTelemetry or {}
local T = ChaosTelemetry
T.acc = T.acc or K.newAcc(K.hourOf(os.time()))
T.last = T.last or {} -- guid -> the hunt counters of the last sample (memory only)
T.firstHit = T.firstHit or {} -- boss creature id -> os.time of the first hit by a player
T.castTick = T.castTick or 0

local function log(text)
	print("[Chaos telemetry] " .. tostring(text))
end

local function esc(s)
	return db.escapeString(tostring(s))
end

local function counted(player)
	if not player then
		return false
	end
	local ok, gid = pcall(function() return player:getGroup():getId() end)
	return ok and (gid or 0) < (cfg.staffGroup or 4)
end

local function bandOf(player)
	return K.bandOf(player:getLevel(), cfg.bands) or "?"
end

local function vocOf(player)
	local ok, id = pcall(function() return player:getVocation():getId() end)
	return ok and id or 0
end

-- the player of a creature: itself, or the master of a summon
local function playerOf(c)
	if not c then
		return nil
	end
	if c:isPlayer() then
		return c
	end
	local m = c:getMaster()
	if m and m:isPlayer() then
		return m
	end
	return nil
end

-- ---------------------------------------------------------------- tables, server_config
local function ensureTables()
	for _, sql in ipairs(K.schemaSql(T_)) do
		db.query(sql)
	end
end

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

-- ---------------------------------------------------------------- the hour
function T.flush(sync)
	local acc = T.acc
	local n = 0
	for _, sql in ipairs(K.flushSql(acc, T_, esc)) do
		if sync then
			db.query(sql)
		else
			db.asyncQuery(sql)
		end
		n = n + 1
	end
	T.acc = K.newAcc(K.hourOf(os.time()))
	return n
end

-- once a day (also over restarts): hourly rows older than hourlyDays become daily rows, old daily rows go
function T.rollup(now, force)
	local today = K.dayOf(now or os.time())
	if not force and (getConfig(cfg.rollupKey) or 0) >= today then
		return false
	end
	local ok, err = pcall(function()
		for _, sql in ipairs(K.rollupSql(T_, today - cfg.hourlyDays * 86400, today - cfg.dailyDays * 86400)) do
			db.query(sql)
		end
	end)
	if not ok then
		db.query("ROLLBACK")
		log("rollup failed: " .. tostring(err))
		return false
	end
	setConfig(cfg.rollupKey, today)
	return true
end

-- a new hour: the last one is written (asynchronously), a new day rolls the old rows up
function T.rotate(now)
	now = now or os.time()
	local hour = K.hourOf(now)
	if hour == T.acc.hour then
		return false
	end
	local newDay = K.dayOf(hour) ~= K.dayOf(T.acc.hour)
	T.flush(false)
	if newDay then
		T.rollup(now)
	end
	return true
end

function T.economy(player, flow, source, gold)
	if cfg.enabled == false or not counted(player) then
		return false
	end
	T.rotate()
	return K.addEconomy(T.acc, flow, source, bandOf(player), gold)
end

-- ---------------------------------------------------------------- sample: online and hunting
function T.sample(now)
	now = now or os.time()
	T.rotate(now)
	local H = ChaosHunt
	local online, seen = {}, {}
	for _, player in ipairs(Game.getPlayers()) do
		if counted(player) then
			local guid, band, voc = player:getGuid(), bandOf(player), vocOf(player)
			seen[guid] = true
			online[#online + 1] = {band = band, voc = voc}
			local s = H and H.sessions and H.sessions[guid]
			if s then
				local cur = {exp = s.exp, loot = s.lootValue, sup = s.supplyValue, kills = s.killCount,
					elapsed = H.elapsed and H.elapsed(s, now) or 0}
				local d = K.huntDelta(T.last[guid], cur, cfg.sampleSeconds)
				T.last[guid] = cur
				K.addHunt(T.acc, band, voc, guid, d)
				K.addEconomy(T.acc, "faucet", "loot", band, d.loot)
				K.addEconomy(T.acc, "sink", "supplies", band, d.sup)
			end
		end
	end
	for guid in pairs(T.last) do
		if not seen[guid] then
			T.last[guid] = nil -- logged out: the next login starts from a fresh base
		end
	end
	K.addOnline(T.acc, online)
	return #online
end

-- ---------------------------------------------------------------- hooks (wrapped public functions)
-- tbl[name] runs as before; after(results, ...) runs behind it, guarded; once per flag (wrapchain_core.lua)
function T.wrap(tbl, name, flag, after)
	return ChaosWrapChain.wrap(tbl, name, flag, function(res, ...)
		if cfg.enabled ~= false then
			after(res, ...)
		end
	end, log)
end

-- the display name of a records board variant ("wb_time" + "ashmaw" -> the boss's name)
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

-- records.lua R.submit(run) -> true, slot when the run counted
local function onRecordRun(res, run)
	if not res[1] or type(run) ~= "table" then
		return
	end
	local prefix = cfg.recordBosses[run.board]
	if not prefix then
		return
	end
	local members = run.members or {}
	local name = prefix
	if run.variant then
		name = prefix .. ": " .. tostring(variantName(run.board, run.variant))
	end
	T.rotate()
	K.addBoss(T.acc, K.clip(name, 64), K.partyOf(math.max(tonumber(run.size) or 0, #members), cfg.maxParty), run.value)
end

-- bossspawns.lua S.onDeath(creature, killer, mostDamageKiller): a tracked map boss died
local function onMapBoss(res, creature)
	if not creature then
		return
	end
	local cid = creature:getId()
	local first = T.firstHit[cid]
	T.firstHit[cid] = nil
	local pos = creature:getPosition()
	if Chaos.instanceAt and Chaos.instanceAt(pos) then
		return -- instance bosses (world boss arena, raids, Ascended) come from the records
	end
	local players = {}
	for id in pairs(creature:getDamageMap() or {}) do
		local p = playerOf(Creature(id))
		if p then
			players[p:getId()] = true
		end
	end
	local n = K.count(players)
	if n == 0 then
		return
	end
	T.rotate()
	K.addBoss(T.acc, K.clip(Chaos.monsterTypeName(creature) or creature:getName(), 64), K.partyOf(n, cfg.maxParty),
		first and (os.time() - first) or nil)
end

local function onRespecPay(res, player, cost)
	if res[1] and (tonumber(cost) or 0) > 0 then
		T.economy(player, "sink", "respec", cost)
	end
end

local function onSellBag(res, player)
	local plan = res[1]
	if type(plan) == "table" and (tonumber(plan.gold) or 0) > 0 then
		T.economy(player, "faucet", "lootbag", plan.gold)
	end
end

function T.installHooks()
	T.wrap(ChaosRecords, "submit", "telemetryWrapped", onRecordRun)
	T.wrap(ChaosBossSpawns, "onDeath", "telemetryWrapped", onMapBoss)
	T.wrap(ChaosRespec, "pay", "telemetryWrapped", onRespecPay)
	T.wrap(ChaosAutoSell, "sellBag", "telemetryWrapped", onSellBag)
	if ChaosSpellEvents and ChaosSpellEvents.set then
		ChaosSpellEvents.set("cast", "telemetry", function(player, name)
			T.onCast(player, name)
		end)
	end
end

function T.onCast(player, name)
	if cfg.enabled == false or not counted(player) or type(name) ~= "string" or name == "" then
		return
	end
	T.castTick = T.castTick + 1
	if T.castTick % math.max(1, cfg.castSampleEvery or 1) ~= 0 then
		return
	end
	T.rotate()
	K.addCast(T.acc, vocOf(player), K.clip(name, 64), player:getGuid())
end

-- ---------------------------------------------------------------- deaths
-- the map markers (data/chaos_poi.lua, written at install by tools/gen_poi.py), read once
function T.marks()
	if T.poiMarks == nil then
		local ok, data = pcall(dofile, "data/chaos_poi.lua")
		T.poiMarks = ok and type(data) == "table" and data.marks or false
	end
	return T.poiMarks or {}
end

function T.onDeath(player, killer, mostDamageKiller)
	if cfg.enabled == false or not counted(player) then
		return
	end
	local pos = player:getPosition()
	local label
	if Chaos.instanceAt then
		local _, l = Chaos.instanceAt(pos)
		label = l
	end
	local area = K.areaOf({x = pos.x, y = pos.y, z = pos.z}, label, T.marks(), cfg)
	local k = killer or mostDamageKiller
	local info
	if k then
		if playerOf(k) then
			info = {player = true}
		else
			info = {monster = Chaos.monsterTypeName(k)}
		end
	end
	T.rotate()
	K.addDeath(T.acc, bandOf(player), area, K.killerOf(info))
end

local death = CreatureEvent("ChaosTelemetryDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local ok, err = pcall(T.onDeath, creature, killer, mostDamageKiller)
	if not ok then
		log("death: " .. tostring(err))
	end
	return true
end
death:register()

-- the first hit of a player on a tracked map boss (the kill time)
local bossHit = CreatureEvent("ChaosTelemetryBossHit")
function bossHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and not T.firstHit[creature:getId()] and primaryDamage > 0 and playerOf(attacker) then
		T.firstHit[creature:getId()] = os.time()
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
bossHit:type("healthchange")
bossHit:register()

local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if cfg.enabled == false or self:getMaster() then
		return true
	end
	local S = ChaosBossSpawns
	local ok, idx = pcall(function() return S and S.ensure and S.ensure() end)
	local typeName = Chaos.monsterTypeName(self)
	if ok and idx and idx.byType and typeName and idx.byType[typeName:lower()] then
		self:registerEvent("ChaosTelemetryBossHit")
	end
	return true
end
spawn:register()

local login = CreatureEvent("ChaosTelemetryLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTelemetryDeath")
	return true
end
login:type("login")
login:register()

-- ---------------------------------------------------------------- clock
local think = GlobalEvent("ChaosTelemetrySample")
function think.onThink(interval)
	if cfg.enabled == false then
		return true
	end
	T.installHooks() -- again after a /reload of a wrapped script
	local ok, err = pcall(T.sample)
	if not ok then
		log("sample: " .. tostring(err))
	end
	-- boss first hits of creatures that are gone (left, despawned)
	for cid in pairs(T.firstHit) do
		if not Creature(cid) then
			T.firstHit[cid] = nil
		end
	end
	return true
end
think:interval(cfg.sampleSeconds * 1000)
think:register()

local startup = GlobalEvent("ChaosTelemetryStartup")
function startup.onStartup()
	if cfg.enabled == false then
		return true
	end
	ensureTables()
	T.installHooks()
	T.acc = K.newAcc(K.hourOf(os.time()))
	T.rollup(os.time())
	return true
end
startup:register()

local shutdown = GlobalEvent("ChaosTelemetryShutdown")
function shutdown.onShutdown()
	if cfg.enabled ~= false then
		pcall(T.flush, true) -- the hour so far, before the database goes
	end
	return true
end
shutdown:register()

local talk = TalkAction("/telemetry")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	if Chaos.staffCommand and not Chaos.staffCommand(player, words, param, false) then
		return false
	end
	local acc = T.acc
	if tostring(param or ""):lower():match("flush") then
		local n = T.flush(false)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Telemetry: %d statement(s) written.", n))
		return false
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Telemetry hour %s UTC: %d samples, buckets hunt %d, " ..
		"boss %d, deaths %d, casts %d, economy %d; %d characters with a hunt base.", os.date("!%Y-%m-%d %H:00", acc.hour),
		acc.onlineSamples, K.count(acc.hunt), K.count(acc.boss), K.count(acc.deaths), K.count(acc.casts),
		K.count(acc.economy), K.count(T.last)))
	return false
end
talk:separator(" ")
talk:register()

pcall(T.installHooks)

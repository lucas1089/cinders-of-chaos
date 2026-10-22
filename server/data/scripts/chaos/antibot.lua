-- Anti-bot behaviour detection and the presence check (client game_antibot, extended opcode ChaosOpcodes.antibot = 211,
-- shared with the player reports of reports.lua). Pure logic: antibot_core.lua (tests/antibot_test.lua); numbers:
-- antibot_config.lua; overview and staff guide: server/README.md "Anti-bot and player reports".
--
-- Nothing here bans or punishes on its own. A character whose suspicion score passes check.at gets a presence check (a
-- small modal: click the picture matching a word, one retry); a failed or unanswered check runs check.failAction
-- (log, the default, or temple; never a kick) and writes chaos_antibot_log; a score over log.at writes a staff log entry. Staff decide.
--
-- Where the samples come from (all cheap, bounded):
--   positions   one getPosition per online character every sampleMs (GlobalEvent); only cell changes are stored
--   heals/hits  a healthchange event on every character: own heals (attacker = the character: spells, runes, potions;
--               leech has no attacker) and hits taken
--   spells      ChaosSpellEvents "cast" (engine patch 0008, events enabled); without it own heals are the actions
--   PvP / boss  the same healthchange plus an EventCallback onTargetCombat (a player or a boss on either side)
--   loot        EventCallback onItemMoved: an item moved by hand out of a corpse into the inventory
-- Cost: per online character about 300 numbers and strings; per event one table write; per evalSeconds one
-- evaluation (rings of at most 40 numbers; the loop search, at most every loop.everySeconds, is about 128 x 29 x 3
-- string compares). Staff (group >= staffGroup) are never sampled.
--
-- Storages (Chaos.storage.antibot = 7100890): +0 last check, +1 its day key, +2 checks that day, +3 grace until,
-- +4 score x 10. The rolling stats live in memory (a relog within keepOfflineMinutes keeps them; a restart clears them).
--
-- Protocol (JSON {action, data}):
--   server -> client  check {t, w, o = [{k, c}], s, a, r} | checkResult {ok, text} | reportOpen {name, reasons}
--                     | reportResult {ok, text}
--   client -> server  answer {t, k} | another {t} | report {name, reason, note} | reportOpen {name?}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/antibot_core.lua")

Chaos.antibotConfig = Chaos.antibotConfig or dofile("data/scripts/chaos/antibot_config.lua")
local cfg = Chaos.antibotConfig
local K = ChaosAntibotCore
local OPCODE = ChaosOpcodes.antibot or 211
local STORAGE = Chaos.storage.antibot or 7100890
local T = Chaos.antibotTables or {reports = "chaos_reports", log = "chaos_antibot_log", holds = "chaos_antibot_holds"}

ChaosAntibot = ChaosAntibot or {}
local AB = ChaosAntibot
AB.states = AB.states or {} -- guid -> core state (+ meta: cid, account, name, offlineAt, nextEval)
AB.byCid = AB.byCid or {} -- creature id -> guid of the characters online
AB.held = AB.held or {accounts = {}, guids = {}, count = 0}
AB.bossNames = AB.bossNames or {}

local function log(text)
	print("[Chaos antibot] " .. text)
end

local function try(name, fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(a))
		return nil
	end
	return a, b, c
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function isStaff(player)
	local ok, group = pcall(function()
		return player:getGroup():getId()
	end)
	return ok and (tonumber(group) or 0) >= cfg.staffGroup
end

-- ---------------------------------------------------------------- tables
function AB.ensureTables()
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.log .. "` (`id` int unsigned NOT NULL AUTO_INCREMENT, `created_at` int " ..
		"unsigned NOT NULL, `player_id` int unsigned NOT NULL, `account_id` int unsigned NOT NULL DEFAULT 0, `player_name` " ..
		"varchar(64) NOT NULL DEFAULT '', `kind` varchar(16) NOT NULL, `score` int unsigned NOT NULL DEFAULT 0, `detail` " ..
		"varchar(512) NOT NULL DEFAULT '', `pos_x` int unsigned NOT NULL DEFAULT 0, `pos_y` int unsigned NOT NULL DEFAULT 0, " ..
		"`pos_z` tinyint unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `idx_player` (`player_id`, `created_at`), " ..
		"KEY `idx_created` (`created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T.holds .. "` (`account_id` int unsigned NOT NULL, `player_id` int unsigned " ..
		"NOT NULL DEFAULT 0, `created_at` int unsigned NOT NULL, `reason` varchar(64) NOT NULL DEFAULT '', `cleared_at` int " ..
		"unsigned NOT NULL DEFAULT 0, `cleared_by` varchar(64) NOT NULL DEFAULT '', PRIMARY KEY (`account_id`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
end

-- ---------------------------------------------------------------- leaderboard holds
local function holdsOn()
	return cfg.log.holdLeaderboards == true
end

function AB.loadHolds()
	local held = {accounts = {}, guids = {}, count = 0}
	if holdsOn() then
		for _, r in ipairs(Chaos.select("SELECT h.`account_id`, p.`id` FROM `" .. T.holds .. "` h JOIN `players` p ON " ..
				"p.`account_id` = h.`account_id` WHERE h.`cleared_at` = 0", {{"account_id", "n"}, {"id", "n"}})) do
			if not held.accounts[r.account_id] then
				held.accounts[r.account_id] = true
				held.count = held.count + 1
			end
			held.guids[r.id] = true
		end
	end
	AB.held = held
	-- the boards rank again without (or with) them
	if ChaosLeaderboard then
		ChaosLeaderboard.ranked = {}
		ChaosLeaderboard.ladder = {}
	end
	if ChaosSeason then
		ChaosSeason.ladderCache = {}
	end
	return held
end

function AB.isHeld(guid)
	return holdsOn() and AB.held.guids[guid] == true
end

-- leaderboard.lua LB.rankedBoard: the ranked list without held characters, ranks renumbered
function AB.filterRanked(list)
	if not holdsOn() or AB.held.count == 0 or type(list) ~= "table" then
		return list
	end
	local out = {}
	for _, e in ipairs(list) do
		if not AB.held.guids[e.guid] then
			out[#out + 1] = e
			e.rank = #out
		end
	end
	return out
end

-- SQL for the ladders (leaderboard.lua, season.lua): "" while holds are off; prefix = the players table alias ("p.")
function AB.heldClause(prefix)
	if not holdsOn() then
		return ""
	end
	return string.format(" AND %s`account_id` NOT IN (SELECT `account_id` FROM `%s` WHERE `cleared_at` = 0)", prefix or "",
		T.holds)
end

local function hold(guid, account, reason)
	if not holdsOn() or not account or account <= 0 then
		return
	end
	db.query(string.format("INSERT INTO `%s` (`account_id`, `player_id`, `created_at`, `reason`) VALUES (%d, %d, %d, %s) " ..
		"ON DUPLICATE KEY UPDATE `player_id` = VALUES(`player_id`), `created_at` = VALUES(`created_at`), `reason` = " ..
		"VALUES(`reason`), `cleared_at` = 0, `cleared_by` = ''", T.holds, account, guid, os.time(), db.escapeString(reason)))
	AB.loadHolds()
end

-- staff: clear the hold of the account of a character (any state); returns true when a row was cleared
function AB.clearHold(account, by)
	local before = Chaos.select(string.format("SELECT `account_id` FROM `%s` WHERE `account_id` = %d AND `cleared_at` = 0",
		T.holds, account), {{"account_id", "n"}})
	db.query(string.format("UPDATE `%s` SET `cleared_at` = %d, `cleared_by` = %s WHERE `account_id` = %d AND `cleared_at` = 0",
		T.holds, os.time(), db.escapeString(by or ""), account))
	AB.loadHolds()
	return #before > 0
end

-- ---------------------------------------------------------------- the staff log
function AB.writeLog(guid, account, name, kind, score, detail, pos)
	pos = pos or {x = 0, y = 0, z = 0}
	db.asyncQuery(string.format("INSERT INTO `%s` (`created_at`, `player_id`, `account_id`, `player_name`, `kind`, `score`, " ..
		"`detail`, `pos_x`, `pos_y`, `pos_z`) VALUES (%d, %d, %d, %s, %s, %d, %s, %d, %d, %d)", T.log, os.time(), guid,
		account or 0, db.escapeString(name or ""), db.escapeString(kind), math.floor(score or 0),
		db.escapeString((detail or ""):sub(1, 512)), pos.x or 0, pos.y or 0, pos.z or 0))
	log(string.format("%s %s (score %d): %s", kind, tostring(name), math.floor(score or 0), detail or ""))
	-- online staff see it in the server log channel line
	for _, p in ipairs(Game.getPlayers()) do
		if isStaff(p) then
			p:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format("[Anti-bot] %s: %s (score %d). /reports log %s",
				kind, tostring(name), math.floor(score or 0), tostring(name)))
		end
	end
	if kind == "score" or kind == "check_fail" then
		hold(guid, account, kind)
	end
end

-- ---------------------------------------------------------------- states
local function storageOf(player, k)
	local v = player:getStorageValue(STORAGE + k)
	return (v and v > 0) and v or 0
end

local function restore(st, player)
	st.check.lastAt = storageOf(player, 0)
	st.check.day = storageOf(player, 1)
	st.check.dayCount = storageOf(player, 2)
	st.check.graceUntil = storageOf(player, 3)
	if st.score == 0 then
		st.score = storageOf(player, 4) / 10
	end
end

local function persist(st, player)
	player:setStorageValue(STORAGE + 0, st.check.lastAt or 0)
	player:setStorageValue(STORAGE + 1, st.check.day or 0)
	player:setStorageValue(STORAGE + 2, st.check.dayCount or 0)
	player:setStorageValue(STORAGE + 3, st.check.graceUntil or 0)
	player:setStorageValue(STORAGE + 4, math.floor((st.score or 0) * 10))
end

function AB.stateOf(player)
	local guid = player:getGuid()
	local st = AB.states[guid]
	if not st then
		st = K.newState(cfg, os.time())
		st.guid = guid
		AB.states[guid] = st
		restore(st, player)
	end
	return st
end

-- the score of a character (online, or kept after logout), 0 when unknown
function AB.scoreOf(guid)
	local st = AB.states[guid]
	return st and math.floor(st.score or 0) or 0
end

local function stateOfCreature(creature)
	local guid = creature and AB.byCid[creature:getId()]
	return guid and AB.states[guid] or nil
end

-- ---------------------------------------------------------------- bosses
local function isBossName(name)
	local key = tostring(name or ""):lower()
	local cached = AB.bossNames[key]
	if cached ~= nil then
		return cached
	end
	local boss = false
	local bp = ChaosBossPoints and ChaosBossPoints.index
	if bp and bp.byName and bp.byName[key] then
		boss = true
	end
	for _, b in ipairs(Chaos.worldBoss and Chaos.worldBoss.bosses or {}) do
		if tostring(b.name or ""):lower() == key then
			boss = true
		end
	end
	if not boss then
		local ok, res = pcall(function()
			local mt = MonsterType(name)
			return mt and mt.isBoss and mt:isBoss()
		end)
		boss = ok and res == true
	end
	AB.bossNames[key] = boss
	return boss
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

-- ---------------------------------------------------------------- sending
local function send(player, action, data)
	return Chaos.send(player, OPCODE, action, data or {})
end
AB.send = send

local function clientIdOf(serverId)
	local ok, id = pcall(function()
		return ItemType(serverId):getClientId()
	end)
	return ok and id or serverId
end

-- ---------------------------------------------------------------- the presence check
local function where(player)
	local p = player:getPosition()
	return {x = p.x, y = p.y, z = p.z}
end

function AB.startCheck(player, st, attempt)
	local now = os.time()
	local c = K.newChallenge(st, cfg, math.random, now, attempt)
	send(player, "check", K.payload(c, cfg, now, clientIdOf))
	persist(st, player)
	return c
end

local function failAction(player)
	-- never a kick (manual review only, server/README.md "Bot detection"): "kick" from an old config acts as "log"
	local action = cfg.check.failAction
	if action == "temple" then
		local town = player:getTown()
		local pos = town and town:getTemplePosition()
		if pos then
			player:teleportTo(pos)
			pos:sendMagicEffect(CONST_ME_TELEPORT)
		end
		player:sendTextMessage(MESSAGE_STATUS_WARNING, Chaos.t(player, "Presence check failed. You were taken to the temple."))
		return "temple"
	end
	player:sendTextMessage(MESSAGE_STATUS_WARNING, Chaos.t(player, "Presence check failed."))
	return "log"
end

function AB.finishCheck(player, st, result, why)
	local c = st.check.active
	local now = os.time()
	local tookS = c and (now - c.started) or 0
	K.finish(st, cfg, result, now)
	persist(st, player)
	local name, guid, account = player:getName(), player:getGuid(), player:getAccountId()
	if result == "pass" then
		send(player, "checkResult", {ok = true, text = "Thank you!"})
		AB.writeLog(guid, account, name, "check_pass", st.score, string.format("answered in %d s, attempt %d", tookS,
			c and c.attempt or 1), where(player))
	else
		local done = failAction(player)
		send(player, "checkResult", {ok = false, text = "Presence check failed."})
		AB.writeLog(guid, account, name, "check_fail", st.score, string.format("%s after %d s, attempt %d, action %s; %s",
			why or "wrong", tookS, c and c.attempt or 1, done, K.summary(st)), where(player))
	end
end

-- ---------------------------------------------------------------- per character evaluation
local function context(player, st, nowS)
	local c = cfg.check
	local ctx = {}
	ctx.pvp = (st.lastPvp and nowS - st.lastPvp < c.pvpSeconds) or (player.isPzLocked and player:isPzLocked()) or false
	ctx.boss = (st.lastBoss and nowS - st.lastBoss < c.bossSeconds) or false
	local target = player:getTarget()
	if target then
		if target:isPlayer() then
			ctx.pvp = true
		elseif target:isMonster() and not target:getMaster() and isBossName(target:getName()) then
			ctx.boss = true
		end
	end
	local rift = Chaos.storage.riftRun and player:getStorageValue(Chaos.storage.riftRun) or 0
	ctx.busy = rift and rift > 0 or false
	return ctx
end

function AB.evaluate(player, st, nowS)
	K.evaluate(st, cfg, nowS)
	local ctx = context(player, st, nowS)
	if st.check.owed and not st.check.active and not (ctx.pvp or ctx.boss or ctx.busy) then
		st.check.owed = nil
		AB.startCheck(player, st, 1)
	end
	local action, writeLog = K.decide(st, cfg, nowS, ctx, Chaos.dayKey(nowS))
	if writeLog then
		K.markLogged(st, nowS)
		AB.writeLog(player:getGuid(), player:getAccountId(), player:getName(), "score", st.score, K.summary(st), where(player))
	end
	if action == "check" then
		AB.startCheck(player, st, 1)
	end
	persist(st, player)
	return action
end

-- ---------------------------------------------------------------- the tick
function AB.tick()
	local nowS, ms = os.time(), nowMs()
	for _, player in ipairs(Game.getPlayers()) do
		local guid = AB.byCid[player:getId()]
		local st = guid and AB.states[guid]
		if st then
			local pos = player:getPosition()
			K.onPosition(st, cfg, pos.x, pos.y, pos.z, nowS, ms)
			if st.check.active and K.timedOut(st, nowS) then
				AB.finishCheck(player, st, "fail", "no answer")
			end
			if nowS >= (st.nextEval or 0) then
				st.nextEval = nowS + cfg.evalSeconds
				try("evaluate", AB.evaluate, player, st, nowS)
			end
		end
	end
	-- forget characters offline for longer than keepOfflineMinutes
	for guid, st in pairs(AB.states) do
		if st.offlineAt and nowS - st.offlineAt >= cfg.keepOfflineMinutes * 60 then
			AB.states[guid] = nil
		end
	end
	return ms
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosAntibotLogin")
function login.onLogin(player)
	player:registerEvent("ChaosAntibotExtended")
	player:registerEvent("ChaosAntibotLogout")
	-- staff, and the staff's tester bots (testers.lua: they are bots by design)
	if cfg.enabled == false or isStaff(player) or (Chaos.isTester and Chaos.isTester(player)) then
		return true
	end
	player:registerEvent("ChaosAntibotHealth")
	local st = AB.stateOf(player)
	st.offlineAt = nil
	st.nextEval = os.time() + (player:getGuid() % cfg.evalSeconds) + 5
	AB.byCid[player:getId()] = player:getGuid()
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosAntibotLogout")
function logout.onLogout(player)
	local guid = AB.byCid[player:getId()]
	AB.byCid[player:getId()] = nil
	AB.ready[player:getId()], AB.pendingCd[player:getId()] = nil, nil
	local st = guid and AB.states[guid]
	if st then
		st.offlineAt = os.time()
		if st.check.active then
			-- logging out is no failure: the check comes again after the next login
			st.check.active = nil
			st.check.owed = true
		end
		persist(st, player)
	end
	return true
end
logout:type("logout")
logout:register()

local health = CreatureEvent("ChaosAntibotHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local st = stateOfCreature(creature)
	if st then
		local ms = nowMs()
		if primaryType == COMBAT_HEALING then
			if attacker and attacker == creature then
				K.onSelfHeal(st, cfg, ms, os.time())
			end
		elseif (primaryDamage or 0) > 0 or (secondaryDamage or 0) > 0 then
			K.onDamage(st, cfg, ms)
			if attacker then
				if playerOf(attacker) and playerOf(attacker) ~= creature then
					st.lastPvp = os.time()
				elseif attacker:isMonster() and isBossName(attacker:getName()) then
					st.lastBoss = os.time()
				end
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:type("healthchange")
health:register()

-- outgoing: attacking a player (PvP) or a boss defers the check too
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	local p = playerOf(creature)
	local st = p and stateOfCreature(p)
	if st and target then
		if target:isPlayer() and target ~= p then
			st.lastPvp = os.time()
		elseif target:isMonster() and isBossName(target:getName()) then
			st.lastBoss = os.time()
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- loot taken by hand out of a corpse into the inventory
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	local st = player and stateOfCreature(player)
	if not st or not toPosition or toPosition.x ~= CONTAINER_POSITION then
		return
	end
	local corpse = false
	pcall(function()
		if fromCylinder and fromCylinder:isItem() and fromCylinder:isContainer() then
			corpse = ItemType(fromCylinder:getId()):isCorpse() or (fromCylinder:getAttribute(ITEM_ATTRIBUTE_CORPSEOWNER) or 0) ~= 0
		end
	end)
	if corpse then
		K.onLootMove(st, cfg, nowMs(), os.time())
	end
end
moved:register()

-- spell casts (engine patch 0008 with the spell events on)
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end
-- The cooldown events of a cast come before its cast event: they say when this spell and its group are ready again, so
-- a cast the moment it was ready (a held hotkey, a human spamming) gives no rhythm sample; a cast at a fixed delay
-- after that does.
AB.ready = AB.ready or {} -- creature id -> {["s" .. spell id] = ms ready, ["g" .. group] = ms ready}
AB.pendingCd = AB.pendingCd or {} -- creature id -> {spell = ms, group = ms} of the cast in progress
if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cooldown", "antibot", function(player, name, id, group, aggressive, cooldownType, ms)
		if player and AB.byCid[player:getId()] then
			local p = AB.pendingCd[player:getId()] or {}
			AB.pendingCd[player:getId()] = p
			if cooldownType == "spell" then
				p.spell = ms
			elseif cooldownType == "group" then
				p.group = ms
			end
		end
		return ms
	end)
	ChaosSpellEvents.set("cast", "antibot", function(player, name, id, group, aggressive, mana, health)
		local st = player and stateOfCreature(player)
		if not st then
			return
		end
		local cid, now = player:getId(), nowMs()
		local rd = AB.ready[cid] or {}
		AB.ready[cid] = rd
		local sk, gk = "s" .. tostring(id), "g" .. tostring(group)
		local readyAt = math.max(rd[sk] or 0, rd[gk] or 0)
		local bound = nil
		if readyAt > 0 then
			bound = now >= readyAt - cfg.timing.readySlackMs and now - readyAt <= cfg.timing.readySlackMs
		end
		local p = AB.pendingCd[cid]
		AB.pendingCd[cid] = nil
		rd[sk] = now + (p and p.spell or 0)
		rd[gk] = now + (p and p.group or 0)
		K.onAction(st, cfg, now, os.time(), sk, bound)
	end)
end

local think = GlobalEvent("ChaosAntibotThink")
function think.onThink(interval)
	if cfg.enabled ~= false then
		try("tick", AB.tick)
	end
	return true
end
think:interval(cfg.sampleMs)
think:register()

local startup = GlobalEvent("ChaosAntibotStartup")
function startup.onStartup()
	try("tables", AB.ensureTables)
	try("holds", AB.loadHolds)
	return true
end
startup:type("startup")
startup:register()

-- ---------------------------------------------------------------- the opcode
local function handle(player, action, d)
	if action == "answer" or action == "another" then
		local st = stateOfCreature(player)
		if not st then
			return
		end
		local now = os.time()
		local token = tostring(d.t or "")
		if action == "another" then
			if K.canRetry(st, cfg, token) then
				AB.startCheck(player, st, st.check.active.attempt + 1)
			end
			return
		end
		local res = K.answer(st, cfg, token, tostring(d.k or ""), now)
		if res == "pass" then
			AB.finishCheck(player, st, "pass")
		elseif res == "retry" then
			send(player, "checkResult", {ok = false, retry = true, text = "That was not it. Here is another picture."})
			AB.startCheck(player, st, st.check.active.attempt + 1)
		elseif res == "fail" then
			AB.finishCheck(player, st, "fail", "wrong picture")
		end
		return
	end
	if ChaosReports and ChaosReports.handle then
		return ChaosReports.handle(player, action, d)
	end
end

local ext = CreatureEvent("ChaosAntibotExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "antibot." .. msg.action, 400) then
		return
	end
	try("action " .. msg.action, handle, player, msg.action, type(msg.data) == "table" and msg.data or {})
end
ext:type("extendedopcode")
ext:register()

-- ---------------------------------------------------------------- staff helpers (used by reports.lua /reports)
-- the state of a character by name (online, or kept after logout); nil when unknown
function AB.stateByName(name)
	local p = Player(name)
	if p then
		return AB.states[p:getGuid()], p
	end
	local guid = Chaos.findPlayer(name)
	return guid and AB.states[guid] or nil, nil
end

-- staff: send a presence check now (testing, or a staff member's suspicion)
function AB.forceCheck(player)
	if isStaff(player) then
		return false, "Staff characters are not checked."
	end
	local st = stateOfCreature(player)
	if not st then
		return false, "No anti-bot state for that character."
	end
	if st.check.active then
		return false, "A check is already running."
	end
	AB.startCheck(player, st, 1)
	return true
end

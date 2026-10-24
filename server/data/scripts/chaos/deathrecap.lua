-- Death recap (client game_deathrecap, extended opcode ChaosOpcodes.deathRecap = 154). After a death the client shows
-- who hit the character in the last seconds (attackers with health and mana damage and the element split, the
-- killing blow, the time window, the last hits), the experience and levels lost, and the character's last deaths.
--
-- The hits come from the combat log (combatlog.lua calls ChaosCombatLog.takenHook for every hit a character takes,
-- with the same attacker attribution as its "Taken" tab, the part a mana shield took and mana drain): a rolling log
-- per character, bounded by count and age (deathrecap_core.lua; numbers in deathrecap_config.lua). With the combat log
-- off (combatlog_config.lua enabled = false) a recap only names the killer.
--
-- When a recap is made:
--   a death        the character's onDeath (also in a rift, a dungeon, the tower, a Hardcore season character, PvP).
--                  Stored at once (chaos_death_recaps, seen = 0); at the next login the experience and levels lost
--                  are filled in (the engine takes them after onDeath) and the client opens it.
--   a mode defeat  a lethal hit cancelled by a mode's onPrepareDeath (arena, battleground, the Marches, raid, descent,
--                  guild boss, Ascended Omens, trials, the Trial of Ascension) while the character stood in a
--                  Chaos.registerInstance instance: sent at once (nothing lost), stored as seen.
--   cfg.hideModes lists instance keys whose recaps are hidden on purpose (none by default).
-- Privacy: names as the victim saw them; a staff character in ghost mode the victim could not see is
-- cfg.hiddenName (also as the master of a summon). A character reads only its own recaps.
--
-- Protocol (JSON {action, data}; server -> client through Chaos.sendChunked):
--   client -> server  open {id?} | get {id}
--   server -> client  history {list = [summary], sel, recap} | recap {id, recap, auto (true: open by itself)}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/deathrecap_core.lua")

Chaos.deathRecapConfig = dofile("data/scripts/chaos/deathrecap_config.lua")
local cfg = Chaos.deathRecapConfig
local R = ChaosDeathRecap
R.configure(cfg)
local OPCODE = ChaosOpcodes.deathRecap or 154
local T = Chaos.tables.deathRecaps or "chaos_death_recaps"

R.logs = R.logs or {} -- player id -> rolling log (kept over /reload)
R.pending = R.pending or {} -- player id -> {at, mk, mode, killer}: a lethal hit in an instance, checked after a moment

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local tableReady
local function ensureTable()
	if tableReady == nil then
		tableReady = db.query(R.createSql(T)) and true or false
	end
	return tableReady
end

-- ---------------------------------------------------------------- who hit (as the victim saw it)
local function sameCreature(a, b)
	local ok, same = pcall(function() return a:getId() == b:getId() end)
	return ok and same
end

local function visible(victim, c)
	local ok, ghost = pcall(function() return c:isPlayer() and c:isInGhostMode() end)
	if not ok or not ghost then
		return true
	end
	local okSee, can = pcall(function() return victim:canSeeCreature(c) end)
	return okSee and can == true
end

-- kind, name, master name, pv (a player's summon) of an attacker
local function describe(victim, attacker, src)
	if not attacker or type(attacker) == "boolean" then
		return "e", src and src.n or "Environment"
	end
	if sameCreature(attacker, victim) then
		return "s", R.cut(victim:getName())
	end
	if not visible(victim, attacker) then
		return "h", cfg.hiddenName
	end
	if attacker:isPlayer() then
		return "u", R.cut(attacker:getName())
	end
	local master, pv
	local m = attacker:getMaster()
	if m and m:isPlayer() then
		pv = not sameCreature(m, victim)
		master = visible(victim, m) and R.cut(m:getName()) or cfg.hiddenName
	end
	return "c", R.cut(attacker:getName()), master, pv
end

local function killerInfo(victim, killer)
	if not killer or type(killer) == "boolean" then
		return nil
	end
	local ok, kind, name, master = pcall(describe, victim, killer)
	if not ok then
		return nil
	end
	return {n = name, kind = kind, m = master}
end

-- a hit the character took (combatlog.lua): src = the combat log's attacker source, mana = a mana shield / mana drain
function R.onTaken(creature, attacker, src, amount, el, critical, now, mana)
	if not cfg.enabled or not amount or amount <= 0 then
		return
	end
	local pid = creature:getId()
	local log = R.logs[pid]
	if not log then
		log = R.newLog()
		R.logs[pid] = log
	end
	local kind, name, master, pv = describe(creature, attacker, src)
	if kind == "s" and (el == "manadrain" or el == "healing") then
		return -- a mana restore or a cost the character paid itself is no damage, never "Yourself" (O159)
	end
	local key = R.key(kind, name, master)
	if attacker and kind ~= "h" and kind ~= "e" and R.wantLook(log, key) then
		local ok, outfit = pcall(function() return attacker:getOutfit() end)
		R.setLook(log, key, ok and R.look(outfit) or false)
	end
	R.record(log, now or nowMs(), {k = key, n = name, kind = kind, m = master, el = el, a = amount,
		c = critical and true or nil, mp = mana and true or nil, pv = pv})
end
ChaosCombatLog = ChaosCombatLog or {}
ChaosCombatLog.takenHook = R.onTaken

-- ---------------------------------------------------------------- store and send
local function send(player, action, data)
	-- the display scale (display_scale_core.lua): each recap at the level the character had at that death
	local DS = ChaosDisplayScale
	if DS and DS.deathRecapData then
		data = DS.deathRecapData(data, DS.forPlayer(player))
	end
	Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data}))
end

local function store(guid, recap, seen)
	if not ensureTable() then
		return false
	end
	db.asyncQuery(R.insertSql(T, guid, recap.at or os.time(), json.encode(recap), seen, db.escapeString))
	db.asyncQuery(R.trimSql(T, guid, cfg.keep))
	return true
end

local function modeOf(player)
	local ok, key, label = pcall(Chaos.inAnyInstance, player)
	if ok and key then
		return key, label
	end
	return nil
end

-- the rows of a character, newest first: {id, at, seen, recap}
local function rowsOf(guid)
	if not ensureTable() then
		return {}
	end
	local out = {}
	for _, row in ipairs(Chaos.select(R.listSql(T, guid, cfg.keep),
			{{"id", "n"}, {"at", "n"}, {"seen", "n"}, {"data", "s"}})) do
		local recap = Chaos.decode(row.data)
		if recap then
			out[#out + 1] = {id = row.id, at = row.at, seen = row.seen, recap = recap}
		end
	end
	return out
end
R.rowsOf = rowsOf

-- ---------------------------------------------------------------- death, mode defeat
local death = CreatureEvent("ChaosDeathRecapDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if not cfg.enabled or not creature:isPlayer() then
		return true
	end
	local pid = creature:getId()
	R.pending[pid] = nil -- a real death, not a mode's defeat
	local log = R.logs[pid] or R.newLog()
	R.logs[pid] = nil
	local key, label = modeOf(creature)
	if R.hidden(key, cfg.hideModes) then
		return true
	end
	local ok, err = pcall(function()
		local recap = R.build(log, nowMs(), {at = os.time(), real = true, mode = label, mk = key, level = creature:getLevel(),
			exp = creature:getExperience(), killer = killerInfo(creature, killer or mostDamageKiller)})
		store(creature:getGuid(), recap, false)
	end)
	if not ok then
		print("[Warning - ChaosDeathRecap] death: " .. tostring(err))
	end
	return true
end
death:type("death")
death:register()

function R.checkDefeat(pid)
	local p = R.pending[pid]
	R.pending[pid] = nil
	if not p then
		return
	end
	local player = Player(pid)
	if not player or player:getHealth() <= 0 or R.hidden(p.mk, cfg.hideModes) then
		return
	end
	local log = R.logs[pid] or R.newLog()
	R.logs[pid] = nil -- the next defeat (a battleground respawn) starts a new log
	local recap = R.build(log, p.at, {at = os.time(), real = false, mode = p.mode, mk = p.mk, level = player:getLevel(),
		killer = p.killer})
	R.finalize(recap)
	store(player:getGuid(), recap, true)
	send(player, "recap", {recap = recap, auto = true})
end

-- runs before the modes' own prepare-death events of the instances (they are registered when a run starts; the
-- Marches' at login, after this one by name): it only notes the hit and never cancels it
local prepare = CreatureEvent("ChaosDeathRecapPrepare")
function prepare.onPrepareDeath(creature, killer)
	if cfg.enabled and creature:isPlayer() then
		local pid = creature:getId()
		if not R.pending[pid] then
			local key, label = modeOf(creature)
			if key then
				R.pending[pid] = {at = nowMs(), mk = key, mode = label, killer = killerInfo(creature, killer)}
				addEvent(R.checkDefeat, cfg.defeatCheckMs or 100, pid)
			end
		end
	end
	return true
end
prepare:register()

-- ---------------------------------------------------------------- login: the last death, finished and shown
function R.loginCheck(pid)
	local player = Player(pid)
	if not player or not ensureTable() then
		return
	end
	local guid = player:getGuid()
	local rows = rowsOf(guid)
	local newest = rows[1]
	if not newest or newest.seen ~= 0 then
		return
	end
	local recap = R.finalize(newest.recap, player:getLevel(), player:getExperience())
	db.asyncQuery(R.seenSql(T, newest.id, guid, json.encode(recap), db.escapeString))
	-- an older unseen one (a login check that never ran) is marked seen as it is
	for i = 2, #rows do
		if rows[i].seen == 0 then
			db.asyncQuery(string.format("UPDATE `%s` SET `seen` = 1 WHERE `id` = %d AND `player_id` = %d", T, rows[i].id, guid))
		end
	end
	local age = os.time() - (tonumber(newest.at) or 0)
	send(player, "recap", {id = newest.id, recap = recap, auto = age <= (cfg.autoOpenMaxAgeSeconds or 604800)})
end

local login = CreatureEvent("ChaosDeathRecapLogin")
function login.onLogin(player)
	player:registerEvent("ChaosDeathRecapDeath")
	player:registerEvent("ChaosDeathRecapPrepare")
	player:registerEvent("ChaosDeathRecapLogout")
	player:registerEvent("ChaosDeathRecapExtended")
	local pid = player:getId()
	R.logs[pid], R.pending[pid] = nil, nil
	if cfg.enabled then
		addEvent(R.loginCheck, cfg.loginDelayMs or 1500, pid)
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosDeathRecapLogout")
function logout.onLogout(player)
	local pid = player:getId()
	R.logs[pid], R.pending[pid] = nil, nil
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosDeathRecapStartup")
function startup.onStartup()
	ensureTable()
	return true
end
startup:type("startup")
startup:register()

-- ---------------------------------------------------------------- opcode
local ext = CreatureEvent("ChaosDeathRecapExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" or Chaos.limited(player, "deathrecap", cfg.rateLimitMs) then
		return
	end
	local d = type(msg.data) == "table" and msg.data or {}
	local want = Chaos.toInt(d.id, 1, 4294967295)
	local rows = rowsOf(player:getGuid())
	if msg.action == "open" then
		local list, sel = {}, nil
		for _, row in ipairs(rows) do
			list[#list + 1] = R.summary(row.id, row.recap)
			if row.id == want or (not want and not sel) then
				sel = row
			end
		end
		sel = sel or rows[1]
		send(player, "history", {list = list, sel = sel and sel.id or nil, recap = sel and sel.recap or nil})
	elseif msg.action == "get" and want then
		for _, row in ipairs(rows) do
			if row.id == want then
				send(player, "recap", {id = row.id, recap = row.recap})
				return
			end
		end
	end
end
ext:type("extendedopcode")
ext:register()

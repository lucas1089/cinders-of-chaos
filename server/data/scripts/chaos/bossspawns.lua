-- Boss spawns tracker (client game_bossspawns, extended opcode ChaosOpcodes.bossSpawns). Every boss of the server by
-- category, where it is and when it comes back. List and rules: bossspawns_config.lua; pure logic: bossspawns_core.lua
-- (tests/bossspawns_test.lua); overview: server/README.md "Boss spawns".
--
-- Tracking: an EventCallback onSpawn looks at every monster the engine creates (map spawns, raids, Game.createMonster);
-- a monster whose TYPE is a listed boss gets the death event, and 100 ms later (the creature id exists only once the
-- engine has placed it) the monster near the spawn point is matched by type, shown name and place (bossspawns_core.lua
-- K.match) and counted alive. Its death stores the kill time, the killer and the kill count in the table
-- chaos_boss_spawns (one row per boss key), so the respawn countdowns survive a restart. A boss removed without dying
-- (the world boss leaving, a raid cleaned up) is dropped from "alive" when the list is built.
--
-- Protocol (JSON {action, data}):
--   client -> server  open | refresh                        (rate limited, requestMs)
--   server -> client  list {now, refresh, cats = [{k, n, c, t}], rows = [...]}   (Chaos.sendChunked: about 20 KB)
--   pocket bosses (pocketboss.lua, ChaosPocketBoss.actions):
--   client -> server  pocketEnter {k = boss key} | pocketLeave | pocketInfo
--   server -> client  pocket {bosses = {key = {l, m, b, lv, ok}}, reset, inside} (after every list) | pocketError {text}
-- Rows: k key, c category, n name, loc, p {x, y, z}, lv level, o outfit, st status, in seconds to `at`, at "Wed 19:30",
-- ln place note (no coordinates), tx rule text, sh its short form, ago seconds since the last kill, by killer, kills, alive (count when more
-- than one), party, pl (pocket level, pocketboss.lua: the raid category is sorted by it, then by name).
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/bossspawns_core.lua")

Chaos.bossSpawnsConfig = Chaos.bossSpawnsConfig or dofile("data/scripts/chaos/bossspawns_config.lua")
local cfg = Chaos.bossSpawnsConfig
local K = ChaosBossSpawnsCore
local OPCODE = ChaosOpcodes.bossSpawns

ChaosBossSpawns = ChaosBossSpawns or {}
local S = ChaosBossSpawns
S.state = S.state or K.newState()
S.tracked = S.tracked or {} -- creature id -> {keys}
local TABLE = cfg.table or "chaos_boss_spawns"

local function log(text)
	print("[Chaos boss spawns] " .. text)
end

local function try(name, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res
end

-- ---------------------------------------------------------------- database
local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (`boss_key` varchar(48) NOT NULL, " ..
			"`last_kill` int(10) unsigned NOT NULL DEFAULT 0, `killer` varchar(64) NOT NULL DEFAULT '', " ..
			"`kills` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`boss_key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true
	end
	return tableReady
end

local function loadKills()
	if not ensureTable() then
		return 0
	end
	local rows = Chaos.select("SELECT `boss_key`, `last_kill`, `killer`, `kills` FROM `" .. TABLE .. "`",
		{{"boss_key", "s"}, {"last_kill", "n"}, {"killer", "s"}, {"kills", "n"}})
	return K.loadKills(S.state, rows, S.index)
end

local function saveKill(key, kill)
	if not ensureTable() then
		return
	end
	local q = string.format("INSERT INTO `%s` (`boss_key`, `last_kill`, `killer`, `kills`) VALUES (%s, %d, %s, 1) " ..
		"ON DUPLICATE KEY UPDATE `last_kill` = VALUES(`last_kill`), `killer` = VALUES(`killer`), `kills` = `kills` + 1",
		TABLE, db.escapeString(key), kill.at, db.escapeString(kill.killer or ""))
	if db.asyncQuery then
		db.asyncQuery(q)
	else
		db.query(q)
	end
end

-- ---------------------------------------------------------------- the list
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- base server raids: interval, margin and position from data/raids/; raid entries no raid spawns are left out
local function readRaids(idx)
	local list = K.parseRaidList(readFile("data/raids/raids.xml"))
	if #list == 0 then
		return
	end
	for _, r in ipairs(list) do
		r.spawns = K.parseRaidSpawns(readFile("data/raids/" .. r.file))
	end
	local found = K.applyRaids(idx, list)
	log(string.format("%d raid boss(es) found in data/raids", found))
end

local function outfitOf(name)
	local mt = MonsterType(name)
	if not mt then
		return nil
	end
	local o = mt:outfit() or {}
	if (tonumber(o.lookType) or 0) <= 0 and (tonumber(o.lookTypeEx) or 0) <= 0 then
		return {}
	end
	return {type = o.lookType or 0, aux = o.lookTypeEx, head = o.lookHead, body = o.lookBody, legs = o.lookLegs,
		feet = o.lookFeet, addons = o.lookAddons}
end

-- open-world entries whose monster is not on this server are left out (others keep their row without a look)
local OPEN_WORLD = {rotation = true, weekly = true, timer = true, raid = true, chance = true}

local function loadOptional(file)
	local ok, t = pcall(dofile, "data/scripts/chaos/" .. file)
	return ok and type(t) == "table" and t or nil
end

function S.rebuild()
	local ds = type(DUNGEON_SYSTEM) == "table" and DUNGEON_SYSTEM or nil
	local storages = ds and type(ds.Storages) == "table" and ds.Storages or {}
	local tower = type(ChaosTowerRunConfig) == "table" and ChaosTowerRunConfig or nil
	local sources = {
		worldBoss = Chaos.worldBoss,
		invasion = Chaos.invasionConfig or loadOptional("invasion_config.lua"),
		towerBosses = tower and tower.bosses, towerEvery = tower and tower.bossEvery,
		trials = Chaos.trials or loadOptional("trials_config.lua"),
		ascension = true,
		ascensionLevel = Chaos.classes and Chaos.classes.ascension and Chaos.classes.ascension.minLevel,
		dungeonsExtra = Chaos.dungeons and Chaos.dungeons.extra,
		dungeonsBase = ds and ds.Dungeons,
		dungeonCooldown = storages.timerCooldown or storages.TimerCooldown
	}
	local idx = K.build(cfg, sources)
	for _, p in ipairs(idx.problems) do
		log("config: " .. p)
	end
	try("raids", readRaids, idx)
	local missing = {}
	for _, e in ipairs(idx.list) do
		if e.monster and not e.look then
			local o = outfitOf(e.monster)
			if o then
				e.look = o.type and o or nil
			elseif OPEN_WORLD[e.rule.type] and not e.missing then
				e.missing = true
				missing[#missing + 1] = e.name
			end
		end
	end
	if #missing > 0 then
		log("not loaded, left out: " .. table.concat(missing, ", "))
	end
	S.index = idx
	S.townsDone = false
	return idx
end

function S.ensure()
	if not S.index then
		S.rebuild()
		local n = try("load", loadKills) or 0
		log(string.format("%d boss(es) listed, %d last kill(s) loaded", #S.index.list, n))
	end
	return S.index
end

-- "near <town>" for entries without a place name (Game.getTowns exists once the map is loaded)
local function fillTowns(idx)
	if S.townsDone then
		return
	end
	local towns = {}
	for _, t in ipairs(Game.getTowns() or {}) do
		local p = t:getTemplePosition()
		towns[#towns + 1] = {name = t:getName(), pos = {x = p.x, y = p.y, z = p.z}}
	end
	if #towns == 0 then
		return
	end
	for _, e in ipairs(idx.list) do
		if not e.loc and e.pos then
			local name = K.nearestTown(e.pos, towns)
			e.autoLoc = name and ("near " .. name) or nil
		end
	end
	S.townsDone = true
end

-- ---------------------------------------------------------------- tracking
local function playerName(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature:getName()
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master:getName()
	end
	return nil
end

local function infoOf(creature)
	local id = creature:getId()
	local inv = ChaosInvasion and ChaosInvasion.state
	local p = creature:getPosition()
	return {type = Chaos.monsterTypeName(creature), shown = creature:getName(), pos = {x = p.x, y = p.y, z = p.z},
		invasion = inv ~= nil and inv.bossId == id}
end

local function track(creature)
	local id = creature:getId()
	if id == 0 or S.tracked[id] then
		return S.tracked[id]
	end
	local keys = {}
	for _, e in ipairs(K.match(S.index, infoOf(creature), cfg.radius)) do
		keys[#keys + 1] = e.key
		K.onSpawn(S.state, e.key, id, os.time())
	end
	if #keys > 0 then
		S.tracked[id] = keys
		return keys
	end
	return nil
end

-- 100 ms after onSpawn: the new monster(s) of that type near the spawn point
local function scan(typeName, pos)
	local r = cfg.scanRadius or 3
	local lowerType = typeName:lower()
	for _, c in ipairs(Game.getSpectators(Position(pos.x, pos.y, pos.z), false, false, r, r, r, r) or {}) do
		if c:isMonster() and not c:getMaster() and (Chaos.monsterTypeName(c) or ""):lower() == lowerType then
			track(c)
		end
	end
end

function S.onDeath(creature, killer, mostDamageKiller)
	S.ensure()
	local id = creature:getId()
	local keys = S.tracked[id] or track(creature)
	S.tracked[id] = nil
	if not keys then
		return
	end
	local now = os.time()
	local who = playerName(mostDamageKiller) or playerName(killer)
	for _, key in ipairs(keys) do
		local kill = K.onDeath(S.state, key, id, now, who)
		if kill then
			saveKill(key, kill)
		end
	end
end

local death = CreatureEvent("ChaosBossSpawnsDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	try("death", S.onDeath, creature, killer, mostDamageKiller)
	return true
end
death:register()

local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if not cfg.enabled or self:getMaster() then
		return true
	end
	local idx = S.ensure()
	local typeName = Chaos.monsterTypeName(self)
	if typeName and idx.byType[typeName:lower()] then
		self:registerEvent("ChaosBossSpawnsDeath")
		local p = {x = position.x, y = position.y, z = position.z}
		addEvent(function()
			try("scan", scan, typeName, p)
		end, 100)
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- status context
local function worldBossContext(now)
	local c = Chaos.worldBoss
	if not c or not c.bosses then
		return nil
	end
	local W = ChaosWorldBoss
	local count = #c.bosses
	local last = Game.getStorageValue(c.rotationStorage)
	local nextIndex
	if W and W.pickBoss then
		nextIndex = c.mode == "random" and 1 or W.pickBoss(count, c.mode, last)
	else
		last = tonumber(last) or 0
		nextIndex = (last >= 1 and last <= count) and (last % count + 1) or 1
	end
	local ctx = {enabled = c.enabled, mode = c.mode, interval = c.intervalHours or 6, count = count, nextIndex = nextIndex,
		nextAt = c.enabled and ((W and W.nextAt) or K.nextSlot(now, c.intervalHours, c.offsetHours)) or nil}
	local st = W and W.state
	if st and st.phase and st.phase ~= "idle" and st.index then
		ctx.active = {index = st.index, phase = st.phase, spawnAt = st.spawnAt}
	end
	return ctx
end

local function invasionContext(now, ctx)
	local I, V, c = ChaosInvasionCore, ChaosInvasion, Chaos.invasionConfig
	if not I or not c then
		return
	end
	local times = {}
	for _, e in ipairs(c.schedule or {}) do
		for _, d in ipairs(e.weekdays or {}) do
			times[#times + 1] = {day = d, hour = e.hour or 20, min = e.minute or 0}
		end
	end
	ctx.invasionText = "Invasions " .. K.weeklyText(times) .. ((c.random and (c.random.chance or 0) > 0) and
		" and surprise days; the area and faction pick the boss" or "; the area and faction pick the boss")
	if c.enabled == false then
		ctx.invasionText = "Invasions are off"
		ctx.invasionShort = "Invasions are off"
	end
	local warnFirst = ((c.warnMinutes or {})[1] or 30) * 60
	local list = {}
	for _, s in ipairs(I.upcoming(c, now, 14 * 86400)) do
		if not s.secret or s.at - now <= warnFirst then
			local area = s.areaKey and I.areaByKey(c, s.areaKey)
			local faction = s.factionKey and c.factions[s.factionKey]
			local plan = area and faction and I.planBoss(c, area, faction, 0)
			if plan then
				list[#list + 1] = {at = s.at, boss = plan.rename or plan.name,
					text = string.format("%s invades %s", faction.name or "A horde", area.name or "?")}
			end
		end
	end
	ctx.invasions = list
	local st = V and V.state
	if st and st.phase == "running" and st.bossName then
		ctx.invasionActive = {boss = st.bossName}
	end
end

function S.context(player, now)
	local idx = S.ensure()
	now = now or os.time()
	K.prune(S.state, function(cid)
		local alive = Monster(cid) ~= nil
		if not alive then
			S.tracked[cid] = nil
		end
		return alive
	end)
	local ctx = {now = now, state = S.state, worldBoss = try("world boss", worldBossContext, now), cooldowns = {}}
	try("invasions", invasionContext, now, ctx)
	if player then
		for _, e in ipairs(idx.list) do
			local storage = e.rule.cooldown
			if storage and ctx.cooldowns[storage] == nil then
				ctx.cooldowns[storage] = tonumber(player:getStorageValue(storage)) or -1
			end
		end
	end
	return ctx
end

function S.payload(player)
	local idx = S.ensure()
	fillTowns(idx)
	local data = K.payload(idx, S.context(player))
	-- pocket bosses (pocketboss.lua): each pocket row's level (pl) and the raid bosses sorted by it, then by name
	if ChaosPocketBoss and ChaosPocketBoss.tidy then
		try("pocket rows", ChaosPocketBoss.tidy, data.rows)
	end
	data.refresh = cfg.refreshSeconds or 30
	return data
end

function S.send(player)
	if not cfg.enabled or not player then
		return false
	end
	local data = try("payload", S.payload, player)
	if not data then
		return false
	end
	local sent = Chaos.sendChunked(player, OPCODE, json.encode({action = "list", data = data}))
	-- the pocket charges of this player (pocketboss.lua), shown as the rows' Pocket buttons
	if ChaosPocketBoss and ChaosPocketBoss.push then
		try("pocket", ChaosPocketBoss.push, player)
	end
	return sent
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosBossSpawnsStartup")
function startup.onStartup()
	S.ensure()
	return true
end
startup:register()

local login = CreatureEvent("ChaosBossSpawnsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBossSpawnsExtended")
	return true
end
login:type("login")
login:register()

local ext = CreatureEvent("ChaosBossSpawnsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	-- the pocket bosses' actions (pocketboss.lua: pocketEnter, pocketLeave, pocketInfo; rate limited there)
	local PB = ChaosPocketBoss
	local pocket = type(msg.action) == "string" and PB and PB.actions and PB.actions[msg.action]
	if pocket then
		pocket(player, msg.data)
		return
	end
	if msg.action ~= "open" and msg.action ~= "refresh" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "bossspawns", cfg.requestMs or 1000) then
		return
	end
	S.send(player)
end
ext:type("extendedopcode")
ext:register()

-- The Ashen Sepulchre: the weekly raid for organised groups (5-15 players). Numbers: raid_config.lua. Pure logic
-- (tests/raid_test.lua): raid_core.lua. Monsters: data/monster/monsters/chaos/raid/. Overview: server/README.md
-- "The Ashen Sepulchre (weekly raid)".
--
-- Flow
--   the city portal (a forcefield next to the temple) or Adventure > Raid opens the raid window -> "start" (a new raid
--   of this week) or "continue" (a saved raid of this week the character belongs to) in a protection zone, out of
--   combat: the party within partyRange (5-15) comes along -> a slot of the raid grid is built (Game.createTile, the
--   rift slot functions of rift_core.lua): the entry hall, then per boss a corridor with its trash and the boss room.
--   Doors open as the trash is cleared and the bosses fall. Stepping close to a boss pulls it: the room seals, the boss
--   takes the raid's size into its health and runs its phases and mechanics (raid_config.lua mechanics: tank swap,
--   cleaves, soak circles, adds, spread marks, totems, the hex to cleanse); telegraphs mark the tiles first
--   (uber_core.lua's way). A lethal hit is caught: the player lands in the entry hall (no death, no loss). Everyone
--   down or out is a wipe: the boss resets and the room opens.
--   A kill saves the raid's progress (SQL), so the group can continue another day of the same week. Every present
--   player whose lockout of that boss is free this week gets personal loot (gold, orbs, gear at item level 120-130,
--   a small raid unique chance, Sepulchre Marks for the vendor) and the lockout; the others helped (no loot).
--   The final boss: achievements (cosmetic kill effect), the guild trophy, the weekly fastest-clear board.
--   A crash: the marker storage moves the character to the temple at the next login; a clean shutdown closes every
--   instance first (progress is saved at every kill and trash clear anyway).
--
-- Protocol (extended opcode ChaosOpcodes.raid = 213, JSON {action, data}, sent through Chaos.sendChunked):
--   client -> server  open | start | continue {id} | join {id} | leave | buy {key} | journal | query
--   server -> client  info {...}      the raid window: lockouts, saved raids, marks, the vendor's stock
--                     journal {bosses} the boss journal (mechanics with their numbers, loot preview)
--                     hud {...}       the in-raid HUD (raid_core.lua K.hud), alert {text, kind} (a mechanic call-out)
--                     loot {boss, eligible, lines}, end {text}, msg {text, ok}, closeInfo
-- Exports: ChaosRaid.isInside(player), ChaosRaid.buffItems(player, kind) (buff bar source "raid").
-- Staff: /raid (see onCommand).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRiftCore then
	dofile("data/scripts/chaos/rift_core.lua")
end
if not ChaosUberCore then
	dofile("data/scripts/chaos/uber_core.lua")
end
dofile("data/scripts/chaos/raid_core.lua")
if not ChaosFactionsCore then
	dofile("data/scripts/chaos/factions_core.lua") -- gearProblems / gearMods / modText: the vendor's fixed gear
end
ChaosRaidConfig = dofile("data/scripts/chaos/raid_config.lua")
dofile("data/lib/chaos_dark_paint.lua")

ChaosRaid = ChaosRaid or {}
local X = ChaosRaid
local K = ChaosRaidCore
local OPCODE = ChaosOpcodes.raid or 213

local function C()
	return ChaosRaidConfig
end

local function ST()
	return C().storage
end

local function T()
	return C().tables
end

local function log(text)
	print("[Chaos raid] " .. text)
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function rand(a, b)
	return math.random(a, b)
end

X.runs = X.runs or {} -- slot -> run
X.runOf = X.runOf or {} -- player id -> run
X.monsterRun = X.monsterRun or {} -- monster id -> run
X.built = X.built or {}
X.bad = X.bad or {}
X.inst = X.inst or {} -- instance id -> instance (loaded)
X.locks = X.locks or {} -- guid -> {week, set}
X.prow = X.prow or {} -- guid -> {marks, kills, clears, best}
X.portals = X.portals or {}

-- bosses, adds, totems and trash keep their tuned stats (trash gets its tier from the raid, not at random)
local function tierSkip()
	local tc = ChaosTierConfig
	if not tc or not tc.skip then
		return
	end
	for _, b in ipairs(C().bosses) do
		tc.skip[b.name:lower()] = true
		if tc.bosses then
			tc.bosses[b.name:lower()] = true
		end
		if b.add then
			tc.skip[b.add:lower()] = true
		end
		if b.totem then
			tc.skip[b.totem:lower()] = true
		end
	end
	for _, s in ipairs(C().trash) do
		for _, pack in ipairs(s.packs) do
			for _, name in ipairs(pack) do
				tc.skip[name:lower()] = true
			end
		end
	end
end
tierSkip()

-- ======================================================================== helpers
local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
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

local function insideOther(player)
	return (ChaosDungeonIsInside and ChaosDungeonIsInside(player))
		or (ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player))
		or (ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(player:getPosition()))
		or (ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player))
		or (ChaosAscended and ChaosAscended.isInside and ChaosAscended.isInside(player))
		or (ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player))
		or (ChaosDescent and ChaosDescent.isInside and ChaosDescent.isInside(player))
end

local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

local function giveEx(player, item)
	if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		return true
	end
	return false
end

local function itemName(id, count)
	local it = ItemType(id)
	local name = it and it:getName() or tostring(id)
	if count and count > 1 and it and it.getPluralName and it:getPluralName() ~= "" then
		return it:getPluralName()
	end
	return name
end

local function rate(player, k, ms)
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "raid." .. k, ms or 400)
end

local function send(player, action, data)
	if not player then
		return
	end
	local payload = {action = action}
	if data ~= nil then
		payload.data = data
	end
	Chaos.sendChunked(player, OPCODE, json.encode(payload))
end

local function each(run, fn)
	for pid, e in pairs(run.players) do
		local p = Player(pid)
		if p then
			fn(p, e)
		end
	end
end

local function say(run, text, kind)
	each(run, function(p)
		p:sendTextMessage(kind or MESSAGE_EVENT_ADVANCE, text)
	end)
end

local function fxAt(pos, name, fallback)
	if Vfx and ChaosVfx and ChaosVfx[name] then
		Vfx(pos, name)
	elseif fallback then
		pos:sendMagicEffect(fallback)
	end
end

local hitFn = doTargetCombat or doTargetCombatHealth

-- damage without a source (this engine's addHealth takes the damage type first; the stock form as the fallback)
local function hurt(creature, amount)
	local before = creature:getHealth()
	creature:addHealth("physical", -amount)
	if creature:getHealth() == before then
		creature:addHealth(-amount)
	end
end

-- ======================================================================== persistence (X.store; tests swap it)
local store = {}
X.store = X.store or store

function X.createTables()
	if not db or not db.query then
		return
	end
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().lockouts .. "` (`player_id` int(11) NOT NULL, " ..
		"`week` int(10) unsigned NOT NULL, `boss` varchar(16) NOT NULL, `instance_id` int(11) NOT NULL DEFAULT 0, " ..
		"`at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `week`, `boss`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().instances .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, " ..
		"`week` int(10) unsigned NOT NULL, `leader_id` int(11) NOT NULL, `leader_name` varchar(255) NOT NULL DEFAULT '', " ..
		"`killed` int(10) unsigned NOT NULL DEFAULT 0, `trash` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`cleared` tinyint(1) unsigned NOT NULL DEFAULT 0, `created_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_raid_instances_week` (`week`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().members .. "` (`instance_id` int(11) NOT NULL, `player_id` int(11) NOT NULL, " ..
		"PRIMARY KEY (`instance_id`, `player_id`), KEY `chaos_raid_members_player` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().players .. "` (`player_id` int(11) NOT NULL, " ..
		"`marks` int(10) unsigned NOT NULL DEFAULT 0, `kills` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`clears` int(10) unsigned NOT NULL DEFAULT 0, `best_clear` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().purchases .. "` (`player_id` int(11) NOT NULL, " ..
		"`week` int(10) unsigned NOT NULL, `offer` varchar(24) NOT NULL, `count` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`, `week`, `offer`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
end

function store.lockRows(guid, week)
	return Chaos.select(string.format("SELECT `week`, `boss` FROM `%s` WHERE `player_id` = %d AND `week` = %d",
		T().lockouts, guid, week), {{"week", "n"}, {"boss", "s"}})
end

function store.addLock(guid, week, boss, instId)
	db.query(string.format("INSERT IGNORE INTO `%s` (`player_id`, `week`, `boss`, `instance_id`, `at`) VALUES " ..
		"(%d, %d, %s, %d, %d)", T().lockouts, guid, week, db.escapeString(boss), instId or 0, os.time()))
end

function store.player(guid)
	local r = Chaos.select(string.format("SELECT `marks`, `kills`, `clears`, `best_clear` FROM `%s` WHERE `player_id` = %d",
		T().players, guid), {{"marks", "n"}, {"kills", "n"}, {"clears", "n"}, {"best_clear", "n"}})[1]
	return r and {marks = r.marks, kills = r.kills, clears = r.clears, best = r.best_clear} or
		{marks = 0, kills = 0, clears = 0, best = 0}
end

function store.savePlayer(guid, row)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `marks`, `kills`, `clears`, `best_clear`, `updated_at`) VALUES " ..
		"(%d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `marks` = VALUES(`marks`), `kills` = VALUES(`kills`), " ..
		"`clears` = VALUES(`clears`), `best_clear` = VALUES(`best_clear`), `updated_at` = VALUES(`updated_at`)",
		T().players, guid, row.marks, row.kills, row.clears, row.best, os.time()))
end

-- spends marks with one conditional UPDATE (never a read, then a write); true when the balance covered it
function store.spendMarks(guid, amount)
	db.query(string.format("UPDATE `%s` SET `marks` = `marks` - %d WHERE `player_id` = %d AND `marks` >= %d",
		T().players, amount, guid, amount))
	local r = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	return r ~= nil and r.n == 1
end

local function instRow(r)
	return {id = r.id, week = r.week, leader = r.leader_id, leaderName = r.leader_name, killed = r.killed, trash = r.trash,
		cleared = r.cleared == 1, members = {}}
end

local INST_COLS = {{"id", "n"}, {"week", "n"}, {"leader_id", "n"}, {"leader_name", "s"}, {"killed", "n"}, {"trash", "n"},
	{"cleared", "n"}}

local function loadMembers(inst)
	for _, m in ipairs(Chaos.select(string.format("SELECT `player_id` FROM `%s` WHERE `instance_id` = %d", T().members,
			inst.id), {{"player_id", "n"}})) do
		inst.members[m.player_id] = true
	end
	return inst
end

function store.newInstance(week, guid, name)
	db.query(string.format("INSERT INTO `%s` (`week`, `leader_id`, `leader_name`, `created_at`, `updated_at`) VALUES " ..
		"(%d, %d, %s, %d, %d)", T().instances, week, guid, db.escapeString(name), os.time(), os.time()))
	local r = Chaos.select(string.format("SELECT MAX(`id`) AS `id` FROM `%s` WHERE `leader_id` = %d AND `week` = %d",
		T().instances, guid, week), {{"id", "n"}})[1]
	return r and r.id or nil
end

function store.instance(id)
	local r = Chaos.select(string.format("SELECT `id`, `week`, `leader_id`, `leader_name`, `killed`, `trash`, `cleared` " ..
		"FROM `%s` WHERE `id` = %d", T().instances, id), INST_COLS)[1]
	return r and loadMembers(instRow(r)) or nil
end

function store.instancesOf(guid, week)
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT i.`id`, i.`week`, i.`leader_id`, i.`leader_name`, i.`killed`, " ..
			"i.`trash`, i.`cleared` FROM `%s` i WHERE i.`week` = %d AND (i.`leader_id` = %d OR i.`id` IN (SELECT " ..
			"`instance_id` FROM `%s` WHERE `player_id` = %d)) ORDER BY i.`id` DESC LIMIT 10", T().instances, week, guid,
			T().members, guid), INST_COLS)) do
		out[#out + 1] = loadMembers(instRow(r))
	end
	return out
end

function store.saveInstance(inst)
	db.query(string.format("UPDATE `%s` SET `killed` = %d, `trash` = %d, `cleared` = %d, `updated_at` = %d WHERE `id` = %d",
		T().instances, inst.killed, inst.trash, inst.cleared and 1 or 0, os.time(), inst.id))
end

function store.addMember(id, guid)
	db.query(string.format("INSERT IGNORE INTO `%s` (`instance_id`, `player_id`) VALUES (%d, %d)", T().members, id, guid))
end

function store.purchases(guid, week)
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `offer`, `count` FROM `%s` WHERE `player_id` = %d AND `week` = %d",
			T().purchases, guid, week), {{"offer", "s"}, {"count", "n"}})) do
		out[r.offer] = r.count
	end
	return out
end

function store.addPurchase(guid, week, offer)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `week`, `offer`, `count`) VALUES (%d, %d, %s, 1) " ..
		"ON DUPLICATE KEY UPDATE `count` = `count` + 1", T().purchases, guid, week, db.escapeString(offer)))
end

local function S()
	return X.store
end

-- ======================================================================== lockouts and records
local function week()
	return K.cfgWeek(C(), os.time())
end

function X.lockSet(guid)
	local w = week()
	local l = X.locks[guid]
	if not l or l.week ~= w then
		l = {week = w, set = K.lockSet(S().lockRows(guid, w), w)}
		X.locks[guid] = l
	end
	return l.set
end

function X.row(guid)
	local r = X.prow[guid]
	if not r then
		r = S().player(guid)
		X.prow[guid] = r
	end
	return r
end

local function saveRow(guid)
	if X.prow[guid] then
		S().savePlayer(guid, X.prow[guid])
	end
end

-- the Boss Spawns window's cooldown column: the reset time for every boss looted this week
local function mirrorLocks(player)
	local set = X.lockSet(player:getGuid())
	local now = os.time()
	for i, b in ipairs(C().bosses) do
		player:setStorageValue(ST() + i, K.lockStorage(C(), set, b.key, now))
	end
end

function X.instance(id)
	local inst = X.inst[id]
	if not inst then
		inst = S().instance(id)
		X.inst[id] = inst
	end
	return inst
end

-- ======================================================================== the slot
local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function fixtures()
	local cfg = C()
	local wall, basin = cfg.wallId, cfg.basinId
	local d = cfg.dark
	if d and d.enabled and ChaosDarkTiles then
		wall = ChaosDarkTiles.id(d.wall) or wall
		basin = ChaosDarkTiles.id(d.basin) or basin
	end
	return wall, basin
end

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
	return tile and tile:getItemById(id)
end

local function buildSlot(slot)
	local cfg = C()
	local L = K.layout(cfg, slot)
	if X.built[slot] then
		return L
	end
	if X.bad[slot] then
		return nil, X.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local wall, basin = fixtures()
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, f in ipairs(list) do
			local tile = Tile(P(f))
			local gid = tile and groundId(tile)
			if tile and gid and gid ~= cfg.groundId and not (ChaosDarkPaint and ChaosDarkPaint.isDark(gid)) then
				return nil, string.format("tile %d,%d,%d already exists in the map", f.x, f.y, f.z)
			end
		end
	end
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, f in ipairs(list) do
			local pos = P(f)
			local tile = Tile(pos) or Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(cfg.groundId, 1, pos)
			end
		end
	end
	if cfg.dark and cfg.dark.enabled and ChaosDarkPaint and ChaosDarkPaint.ready(cfg.dark.style) then
		local reserved = {L.exit, L.start, L.fallen}
		for _, r in ipairs(L.rooms) do
			reserved[#reserved + 1] = r.center
			for _, f in ipairs(r.fonts) do
				reserved[#reserved + 1] = f
			end
		end
		for _, b in ipairs(L.basins) do
			reserved[#reserved + 1] = b
		end
		local walls = {}
		for k in pairs(L.walls) do
			walls[k] = true
		end
		pcall(function()
			ChaosDarkPaint.apply(ChaosDarkPaint.plan(L.floorList, cfg.dark.style, math.random, {walls = walls, reserved = reserved}), L.z)
		end)
	end
	for _, f in ipairs(L.wallList) do
		placeItem(P(f), wall)
	end
	for _, f in ipairs(L.basins) do
		placeItem(P(f), basin)
	end
	local ex = placeItem(P(L.exit), cfg.objects.exit)
	if ex then
		ex:setActionId(cfg.aid.exit)
	end
	X.built[slot] = true
	return L
end

local function takeSlot()
	local cfg = C()
	while true do
		local slot = ChaosRiftCore.allocSlot(cfg, X.runs, X.bad)
		if not slot then
			return nil
		end
		local L, why = buildSlot(slot)
		if L then
			return slot, L
		end
		X.bad[slot] = why
		log(string.format("slot %d not usable: %s", slot, tostring(why)))
	end
end

-- the doors of corridor i: bars across its west / east end
local function setDoor(L, i, side, open)
	local id = C().doorId
	for _, f in ipairs(L.corridors[i][side]) do
		local tile = Tile(P(f))
		local have = tile and tile:getItemById(id)
		if open and have then
			have:remove()
		elseif not open and tile and not have then
			for _, c in ipairs(tile:getCreatures() or {}) do
				-- nobody is shut inside a door: whoever stands on it steps back west
				c:teleportTo(Position(f.x - 1, f.y, f.z), true)
			end
			Game.createItem(id, 1, P(f))
		end
	end
end

function X.syncDoors(run)
	for i = 1, #C().bosses do
		setDoor(run.L, i, "west", K.doorOpen(run.inst, i, "west"))
		setDoor(run.L, i, "east", K.doorOpen(run.inst, i, "east", run.fight and run.fight.idx or nil))
	end
end

-- monsters and loose items of the slot (walls, lights, doors and the exit stay)
local function cleanSlot(L)
	local cfg = C()
	local wall, basin = fixtures()
	local keep = {[wall] = true, [basin] = true, [cfg.doorId] = true, [cfg.objects.exit] = true}
	for _, f in ipairs(L.floorList) do
		local tile = Tile(P(f))
		if tile then
			for _, c in ipairs(tile:getCreatures() or {}) do
				if c:isMonster() then
					X.monsterRun[c:getId()] = nil
					c:remove()
				end
			end
			for _, item in ipairs(tile:getItems() or {}) do
				if not keep[item:getId()] then
					item:remove()
				end
			end
		end
	end
end

-- ======================================================================== monsters
local function setHealth(m, hp)
	hp = math.max(1, math.floor(hp))
	m:setMaxHealth(hp)
	local missing = hp - m:getHealth()
	if missing > 0 then
		Chaos.heal(m, missing)
	elseif missing < 0 then
		hurt(m, -missing)
	end
end

local function spawn(run, name, pos, kind, opts)
	opts = opts or {}
	local m = Game.createMonster(name, P(pos), true, true)
	if not m then
		log(string.format("cannot create %s (is data/monster/monsters/chaos/raid registered?)", name))
		return nil
	end
	if opts.tier and opts.tier ~= "normal" and ChaosApplyTier then
		pcall(ChaosApplyTier, m, opts.tier)
	end
	if opts.mult and opts.mult ~= 1 then
		setHealth(m, m:getMaxHealth() * opts.mult)
	end
	m:registerEvent("ChaosRaidMonsterDeath")
	m:registerEvent("ChaosRaidMonsterHit")
	X.monsterRun[m:getId()] = run
	run.mons[m:getId()] = {kind = kind, idx = opts.idx, born = mnow()}
	return m
end

local function players(run)
	local n = 0
	for _ in pairs(run.players) do
		n = n + 1
	end
	return n
end

local function spawnTrash(run, i)
	local cfg = C()
	if K.hasBit(run.inst.trash, i) or run.trashUp[i] then
		return
	end
	run.trashUp[i] = true
	local cr = run.L.corridors[i]
	local size = K.packSize(cfg, players(run))
	local mult = K.trashMult(cfg, players(run))
	local n = 0
	for p, pack in ipairs(cfg.trash[i].packs) do
		local at = cr.packAt[p] or cr.packAt[1]
		for k = 1, size do
			local name = pack[((k - 1) % #pack) + 1]
			local pos = {x = at.x + (k % 3) - 1, y = at.y + (k % 2 == 0 and 1 or -1) * math.floor(k / 3), z = at.z}
			pos.y = math.max(cr.rect.y1, math.min(cr.rect.y2, pos.y))
			if spawn(run, name, pos, "trash", {idx = i, tier = K.trashTier(cfg, rand(1, 100)), mult = mult}) then
				n = n + 1
			end
		end
	end
	run.trashLeft[i] = n
	if n == 0 then
		run.trashLeft[i] = nil
		run.inst.trash = K.setBit(run.inst.trash, i)
		S().saveInstance(run.inst)
	end
end

local function spawnBoss(run, i)
	local b = C().bosses[i]
	if K.hasBit(run.inst.killed, i) or run.bossId[i] then
		return
	end
	local m = spawn(run, b.name, run.L.rooms[i].bossSpawn, "boss", {idx = i})
	if m then
		run.bossId[i] = m:getId()
		run.bossBase[i] = m:getMaxHealth()
		m:registerEvent("ChaosRaidBossDeath")
	end
end

local function bossOf(run, i)
	local id = run.bossId[i]
	return id and Monster(id) or nil
end

-- ======================================================================== HUD and alerts
local function alert(run, text, kind)
	run.alerts[#run.alerts + 1] = {text = text, at = os.time()}
	while #run.alerts > 4 do
		table.remove(run.alerts, 1)
	end
	each(run, function(p)
		send(p, "alert", {text = text, kind = kind or "mech"})
		if kind and kind ~= "mech" then
			p:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, text)
		end
	end)
end

local function hudData(run, pid)
	local cfg = C()
	local f = run.fight
	local idx = f and f.idx or K.nextBoss(cfg, run.inst)
	local b = idx and cfg.bosses[idx] or nil
	local boss = idx and bossOf(run, idx)
	local s = {inst = run.inst, bossIdx = idx, boss = b, state = f and "fight" or (b and "idle" or "clear"),
		hp = boss and math.floor(boss:getHealth() * 100 / math.max(1, boss:getMaxHealth())) or nil,
		players = players(run), alerts = {}}
	if f then
		local elapsed = (mnow() - f.start) / 1000
		local enraged, left = K.clock(b, elapsed)
		s.phase, s.enraged, s.toEnrage = f.phase, enraged, math.floor(left)
		local adds, totems = 0, 0
		for mid, e in pairs(run.mons) do
			if Monster(mid) then
				if e.kind == "add" then
					adds = adds + 1
				elseif e.kind == "totem" then
					totems = totems + 1
				end
			end
		end
		s.adds, s.totems = adds, totems
		local fallen = 0
		for _, e in pairs(run.players) do
			if e.fallen then
				fallen = fallen + 1
			end
		end
		s.fallen = fallen
		s.stacks = {sunder = pid and K.sunderStacks(f.sunder, pid) or 0, hexed = pid and f.hexed.stacks[pid] or 0}
		s.hexed = pid and f.hexes[pid] and math.max(0, math.ceil((f.hexes[pid] - mnow()) / 1000)) or nil
	elseif b and not K.doorOpen(run.inst, idx, "east") then
		s.trash = run.trashLeft[idx]
	end
	local now = os.time()
	for _, a in ipairs(run.alerts) do
		if now - a.at <= 8 then
			s.alerts[#s.alerts + 1] = a.text
		end
	end
	return K.hud(cfg, s)
end

local function sendHud(run, player)
	if player then
		send(player, "hud", hudData(run, player:getId()))
		return
	end
	each(run, function(p)
		send(p, "hud", hudData(run, p:getId()))
	end)
	run.hudAt = os.time() + C().hudEvery
end

-- ======================================================================== telegraphs
-- marks the tiles now and every turn until the hit; fn(run) at the hit (only while the same fight goes on). centers:
-- circles of radius 1 (soak, marks, the verdict) get the 3 x 3 warning picture centred on them, whatever the tile
local function telegraph(run, tiles, hitFnc, warnMs, centers)
	local cfg = C()
	local f = run.fight
	if not f or #tiles == 0 then
		return
	end
	local timing = K.telegraphTiming(cfg, f.enraged)
	local hitMs = warnMs or timing.hitMs
	local plan = centers and {big = centers, small = {}} or K.markPlan(tiles)
	local fid, slot = f.id, run.slot
	local function live()
		local r = X.runs[slot]
		return r and r.fight and r.fight.id == fid and r or nil
	end
	local marks = {0}
	local turn = cfg.telegraph.turnMs
	while turn and turn > 0 and marks[#marks] + turn < hitMs do
		marks[#marks + 1] = marks[#marks] + turn
	end
	for i, ms in ipairs(marks) do
		local effect = i == 1 and cfg.telegraph.warnEffect or cfg.telegraph.fillEffect
		addEvent(function()
			if not live() then
				return
			end
			for _, t in ipairs(plan.big) do
				fxAt(P(t), effect, CONST_ME_MAGIC_RED)
			end
			for _, t in ipairs(plan.small) do
				P(t):sendMagicEffect(i == 1 and CONST_ME_MAGIC_RED or CONST_ME_DRAWBLOOD)
			end
		end, ms)
	end
	addEvent(function()
		local r = live()
		if r then
			hitFnc(r)
		end
	end, hitMs)
end

-- a share of max health as one scripted hit of the boss (not scaled again by the sunder or the enrage); a Hollow Vessel
-- counts health + maximum energy shield (Chaos.percentBase)
local function shareHit(run, player, share, ctype)
	local f = run.fight
	local boss = f and bossOf(run, f.idx)
	local dmg = K.shareDamage(Chaos.percentBase(player), share)
	run.scripted = true
	if hitFn then
		pcall(hitFn, boss and boss:getId() or 0, player, ctype or COMBAT_PHYSICALDAMAGE, -dmg, -dmg, CONST_ME_NONE,
			ORIGIN_SPELL)
	end
	run.scripted = false
end

-- the raid players standing (not fallen) in room i: list of players
local function roomPlayers(run, i)
	local out = {}
	each(run, function(p, e)
		if not e.fallen and K.inRoom(run.L, i, p:getPosition()) then
			out[#out + 1] = p
		end
	end)
	return out
end

local function posOf(p)
	local q = p:getPosition()
	return {x = q.x, y = q.y, z = q.z}
end

local function onTiles(run, i, set, fn)
	for _, p in ipairs(roomPlayers(run, i)) do
		local q = p:getPosition()
		if set[K.key(q.x, q.y)] then
			fn(p)
		end
	end
end

-- ======================================================================== mechanics
local M = {}

function M.cleave(run, back)
	local cfg = C()
	local f = run.fight
	local boss = bossOf(run, f.idx)
	if not boss then
		return
	end
	local m = cfg.mechanics[back and "sweep" or "cleave"]
	local target = boss:getTarget()
	local bp = posOf(boss)
	local tp = target and posOf(target) or {x = bp.x + 1, y = bp.y, z = bp.z}
	local tiles = K.cone(run.L, f.idx, bp, tp, m.length, m.spread, back)
	local set = K.tileSet(tiles)
	local tid = target and target:getId() or 0
	alert(run, K.ANNOUNCE[back and "sweep" or "cleave"])
	telegraph(run, tiles, function(r)
		for i, t in ipairs(tiles) do
			if i % 2 == 1 then
				fxAt(P(t), "shadow_eruption", CONST_ME_GROUNDSHAKER or CONST_ME_EXPLOSIONAREA)
			end
		end
		onTiles(r, f.idx, set, function(p)
			if back or p:getId() ~= tid then
				shareHit(r, p, m.share)
			end
		end)
	end)
end

function M.sweep(run)
	M.cleave(run, true)
end

function M.marks(run)
	local cfg = C()
	local f = run.fight
	local m = cfg.mechanics.marks
	local centers = {}
	for _, p in ipairs(roomPlayers(run, f.idx)) do
		centers[#centers + 1] = posOf(p)
	end
	local tiles = K.circles(run.L, f.idx, centers, m.radius)
	local set = K.tileSet(tiles)
	alert(run, K.ANNOUNCE.marks)
	telegraph(run, tiles, function(r)
		for _, c in ipairs(centers) do
			fxAt(P(c), "bone_burst", CONST_ME_BONE_CAPSULE or CONST_ME_MORTAREA)
		end
		onTiles(r, f.idx, set, function(p)
			shareHit(r, p, m.share, COMBAT_DEATHDAMAGE)
		end)
	end, nil, m.radius == 1 and centers or nil)
end

function M.soak(run)
	local cfg = C()
	local f = run.fight
	local m = cfg.mechanics.soak
	local list = roomPlayers(run, f.idx)
	if #list == 0 then
		return
	end
	local pos = {}
	for _, p in ipairs(list) do
		pos[#pos + 1] = posOf(p)
	end
	local centers = K.soakCenters(cfg, pos, rand)
	local need = K.soakNeed(cfg, players(run))
	local circles = {}
	local all = {}
	for _, c in ipairs(centers) do
		local tiles = K.circles(run.L, f.idx, {c}, m.radius)
		circles[#circles + 1] = K.tileSet(tiles)
		for _, t in ipairs(tiles) do
			all[#all + 1] = t
		end
	end
	alert(run, string.format(K.ANNOUNCE.soak, need))
	telegraph(run, all, function(r)
		local room = roomPlayers(r, f.idx)
		for ci, set in ipairs(circles) do
			local inside, isIn = {}, {}
			for _, p in ipairs(room) do
				local q = p:getPosition()
				if set[K.key(q.x, q.y)] then
					inside[#inside + 1] = p
					isIn[p:getId()] = true
				end
			end
			local each_, overflow = K.soakResolve(cfg, #inside, need)
			fxAt(P(centers[ci]), "dome_blast_fire", CONST_ME_FIREAREA)
			for _, p in ipairs(inside) do
				shareHit(r, p, each_, COMBAT_FIREDAMAGE)
			end
			if overflow > 0 then
				alert(r, string.format("Ember Brand overflows: only %d of %d soaked!", #inside, need), "fail")
				for _, p in ipairs(room) do
					if not isIn[p:getId()] then
						shareHit(r, p, overflow, COMBAT_FIREDAMAGE)
					end
				end
			end
		end
	end, m.warnMs, m.radius == 1 and centers or nil)
end

local function freeTile(run, i, near, spread)
	local r = run.L.rooms[i].rect
	for _ = 1, 16 do
		local pos = {x = math.max(r.x1 + 1, math.min(r.x2 - 1, near.x + rand(-spread, spread))),
			y = math.max(r.y1 + 1, math.min(r.y2 - 1, near.y + rand(-spread, spread))), z = run.L.z}
		local tile = Tile(P(pos))
		if tile and not tile:getTopCreature() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) then
			return pos
		end
	end
	return run.L.rooms[i].center
end

function M.adds(run)
	local cfg = C()
	local f = run.fight
	local b = cfg.bosses[f.idx]
	local n = K.waveCount(cfg.mechanics.adds, players(run))
	local made = 0
	local mult = K.addMult(cfg, players(run))
	for _ = 1, n do
		if spawn(run, b.add, freeTile(run, f.idx, run.L.rooms[f.idx].center, 8), "add", {idx = f.idx, mult = mult}) then
			made = made + 1
		end
	end
	if made > 0 then
		alert(run, string.format(K.ANNOUNCE.adds, made == 1 and b.add or (made .. " " .. b.add .. "s")))
	end
end

function M.totem(run)
	local cfg = C()
	local f = run.fight
	local b = cfg.bosses[f.idx]
	local n = K.waveCount(cfg.mechanics.totem, players(run))
	local mult = K.addMult(cfg, players(run))
	local made = 0
	for _ = 1, n do
		local m = spawn(run, b.totem, freeTile(run, f.idx, run.L.rooms[f.idx].center, 9), "totem", {idx = f.idx, mult = mult})
		if m then
			made = made + 1
			fxAt(m:getPosition(), "shadow_eruption", CONST_ME_MORTAREA)
		end
	end
	if made > 0 then
		alert(run, string.format(K.ANNOUNCE.totem, b.totem))
	end
end

local function hexCondition(ms)
	local m = C().mechanics.hex
	local cond = Condition(CONDITION_CURSED, CONDITIONID_COMBAT)
	cond:setParameter(CONDITION_PARAM_SUBID, m.subId)
	cond:setParameter(CONDITION_PARAM_DELAYED, true)
	local ticks = math.max(1, math.floor(ms / 2000))
	cond:addDamage(ticks, 2000, -1)
	return cond
end

local function hexed(p)
	return p:getCondition(CONDITION_CURSED, CONDITIONID_COMBAT, C().mechanics.hex.subId) ~= nil
end

function X.cleanse(p)
	p:removeCondition(CONDITION_CURSED, CONDITIONID_COMBAT, C().mechanics.hex.subId)
end

function M.hex(run)
	local cfg = C()
	local f = run.fight
	local m = cfg.mechanics.hex
	local list = roomPlayers(run, f.idx)
	local ids = {}
	for _, p in ipairs(list) do
		if not f.hexes[p:getId()] then
			ids[#ids + 1] = p:getId()
		end
	end
	local names = {}
	for _, pid in ipairs(K.hexTargets(cfg, ids, players(run), rand)) do
		local p = Player(pid)
		if p then
			p:addCondition(hexCondition(m.windowMs + 2000))
			f.hexes[pid] = mnow() + m.windowMs
			names[#names + 1] = p:getName()
			p:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
		end
	end
	if #names > 0 then
		alert(run, string.format(K.ANNOUNCE.hex, table.concat(names, ", ")))
	end
end

-- a hex ran out: cleansed (the condition is gone) or a burst on everyone near the hexed player
local function hexDue(run, pid)
	local cfg = C()
	local f = run.fight
	f.hexes[pid] = nil
	local p = Player(pid)
	if not p then
		return
	end
	local clean = not hexed(p)
	X.cleanse(p)
	local others = {}
	for _, q in ipairs(roomPlayers(run, f.idx)) do
		others[#others + 1] = {id = q:getId(), pos = posOf(q)}
	end
	local hit = K.hexResolve(cfg, clean, posOf(p), others)
	if #hit > 0 then
		fxAt(p:getPosition(), "shadow_eruption", CONST_ME_MORTAREA)
		alert(run, string.format("The hex on %s bursts!", p:getName()), "fail")
		for _, id in ipairs(hit) do
			local q = Player(id)
			if q then
				shareHit(run, q, cfg.mechanics.hex.burstShare, COMBAT_DEATHDAMAGE)
			end
		end
	end
end

-- sunder: a melee hit of the boss on its target landed; the swap or the Crushing Verdict
local function sunderAfterHit(run, target)
	local cfg = C()
	local f = run.fight
	local boss = bossOf(run, f.idx)
	if not boss or f.verdictAt then
		return
	end
	local cands = {}
	local bp = posOf(boss)
	for _, p in ipairs(roomPlayers(run, f.idx)) do
		local q = posOf(p)
		cands[#cands + 1] = {id = p:getId(), dist = math.max(math.abs(q.x - bp.x), math.abs(q.y - bp.y))}
	end
	local d = K.sunderDecide(f.sunder, cfg, target:getId(), cands)
	if not d then
		return
	end
	if d.action == "swap" then
		local to = Player(d.to)
		if to and boss.selectTarget then
			boss:selectTarget(to)
			alert(run, string.format("%s turns to %s.", cfg.bosses[f.idx].name, to:getName()), "swap")
		end
		return
	end
	-- nobody fresh in melee: the verdict falls on the target unless the boss turns away in time
	local stacks = K.sunderStacks(f.sunder, target:getId())
	local tid = target:getId()
	f.verdictAt = mnow()
	alert(run, string.format(K.ANNOUNCE.sunder, target:getName(), stacks), "tank")
	local tp = posOf(target)
	telegraph(run, K.circles(run.L, f.idx, {tp}, 1), function(r)
		r.fight.verdictAt = nil
		local b2 = bossOf(r, r.fight.idx)
		local cur = b2 and b2:getTarget()
		local t = Player(tid)
		if t and cur and cur:getId() == tid then
			fxAt(t:getPosition(), "meteor_strike", CONST_ME_GROUNDSHAKER or CONST_ME_EXPLOSIONAREA)
			alert(r, string.format(K.ANNOUNCE.verdict, t:getName()), "fail")
			shareHit(r, t, K.verdictShare(cfg, K.sunderStacks(r.fight.sunder, tid)))
		end
	end, cfg.mechanics.sunder.warnMs, {tp})
end

-- ======================================================================== fights
local function phaseStart(run, idx)
	local f = run.fight
	local b = C().bosses[f.idx]
	local ph = b.phases[idx]
	if not ph then
		return
	end
	local boss = bossOf(run, f.idx)
	if boss and ph.yell then
		boss:say(ph.yell, TALKTYPE_MONSTER_YELL)
	end
	if idx > 1 then
		alert(run, string.format("%s: phase %d of %d, %s.", b.name, idx, #b.phases, ph.name), "phase")
		if boss then
			fxAt(boss:getPosition(), "dome_blast_fire", CONST_ME_FIREAREA)
		end
	end
	local now = mnow()
	for k, m in ipairs(ph.mech) do
		if m ~= "sunder" and not f.next[m] then
			f.next[m] = now + C().pullDelay * 1000 + 2500 * k
		end
	end
	sendHud(run)
end

local fightId = 0
local function pull(run, i)
	local cfg = C()
	local boss = bossOf(run, i)
	if not boss then
		return
	end
	fightId = fightId + 1
	-- raiders waiting in the corridor in front of the room come in with the pull
	each(run, function(p, e)
		local w, wi = K.where(run.L, p:getPosition())
		if not e.fallen and w == "corridor" and wi == i then
			p:teleportTo(P(run.L.rooms[i].entry))
			p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
	end)
	run.fight = {id = fightId, idx = i, start = mnow(), phase = 0, next = {}, sunder = K.newSunder(), hexed = K.newHexed(),
		hexes = {}, deaths = 0, nextHeal = mnow() + 5000, nextPulse = 0, nextHex = mnow() + cfg.mechanics.totem.hexMs}
	for _, e in pairs(run.players) do
		e.fallen = nil
	end
	local n = players(run)
	run.fight.size = n
	setHealth(boss, run.bossBase[i] * K.healthMult(cfg, n))
	if run.session and not run.session.firstPull then
		run.session.firstPull = mnow()
	end
	X.syncDoors(run)
	local b = cfg.bosses[i]
	alert(run, string.format("%s awakens! The doors seal. Enrage in %s.", b.name, K.clockText(b.enrageAt)), "pull")
	K.advancePhase(run.fight, b, 1)
	phaseStart(run, 1)
	log(string.format("raid %d: %s pulled with %d player(s)", run.inst.id, b.name, n))
end

local function removeMechanicMonsters(run)
	for mid, e in pairs(run.mons) do
		if e.kind == "add" or e.kind == "totem" then
			local m = Monster(mid)
			if m then
				m:remove()
			end
			run.mons[mid] = nil
			X.monsterRun[mid] = nil
		end
	end
end

local function endFight(run)
	local f = run.fight
	if not f then
		return
	end
	for pid in pairs(f.hexes) do
		local p = Player(pid)
		if p then
			X.cleanse(p)
		end
	end
	removeMechanicMonsters(run)
	run.fight = nil
	X.syncDoors(run)
end

local function wipe(run)
	local f = run.fight
	local i = f.idx
	local b = C().bosses[i]
	endFight(run)
	local boss = bossOf(run, i)
	if boss then
		setHealth(boss, run.bossBase[i])
		Chaos.heal(boss, boss:getMaxHealth())
		boss:teleportTo(P(run.L.rooms[i].bossSpawn))
	end
	alert(run, string.format("The raid falls before %s. The doors open again.", b.name), "wipe")
	for _, e in pairs(run.players) do
		e.fallen = nil
	end
	sendHud(run)
	log(string.format("raid %d: wipe on %s", run.inst.id, b.name))
end

-- ======================================================================== loot and the kill
function X.deliver(player, b, idx)
	local cfg = C()
	local sp = K.spoils(cfg, b)
	local lines = {}
	local inbox = false
	player:setBankBalance(player:getBankBalance() + sp.gold)
	lines[#lines + 1] = string.format("%d gold (bank)", sp.gold)
	for _, it in ipairs(sp.items) do
		local ready = ItemType(it.id)
		if ready and ready:getId() ~= 0 then
			inbox = giveStack(player, it.id, it.count) or inbox
			lines[#lines + 1] = string.format("%d %s", it.count, itemName(it.id, it.count))
		end
	end
	local L = ChaosLoot
	local find = L and L.itemFindMult and L.itemFindMult(player) or 1
	for _ = 1, sp.gearRolls do
		local id = b.gear[rand(1, #b.gear)]
		local level = K.gearLevel(cfg, rand)
		local rarity = 0
		if L and L.upgradeRarity and L.stockRarity then
			rarity = L.upgradeRarity("boss", L.stockRarity(), find * cfg.loot.rarityFind)
		end
		local item = ChaosCrafting and ChaosCrafting.createItem and ChaosCrafting.createItem(id, rarity, level) or Game.createItem(id, 1)
		if item and ChaosVeiled and ChaosVeiled.rollReward then
			ChaosVeiled.rollReward(item, {raid = true}) -- veiled.lua
		end
		if item then
			inbox = giveEx(player, item) or inbox
			local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names
			lines[#lines + 1] = (rarity > 0 and ("[" .. (names and names[rarity] or rarity) .. "] ") or "") ..
				itemName(id) .. " (item level " .. level .. ")"
		end
	end
	local u = K.rollUnique(cfg, b, rand(1, 10000), rand)
	if u then
		local item = Game.createItem(u.id, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			inbox = giveEx(player, item) or inbox
			lines[#lines + 1] = "{" .. u.name .. "}"
			Game.broadcastMessage(string.format("%s found %s in %s!", player:getName(), u.name, cfg.name), MESSAGE_EVENT_ADVANCE)
		end
	end
	-- item sets (itemsets.lua): the raid set's chase roll of this boss
	if ChaosItemSets and ChaosItemSets.grantChase then
		local piece = ChaosItemSets.grantChase(player, "raid", b.key, {final = b.final and true or nil, itemFind = find}, rand)
		if piece then
			lines[#lines + 1] = "{" .. piece .. "}"
		end
	end
	local row = X.row(player:getGuid())
	row.marks = row.marks + sp.marks
	lines[#lines + 1] = string.format("%d Sepulchre Marks", sp.marks)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Spoils of %s: %s.%s", b.name, table.concat(lines, ", "),
		inbox and " Your backpack was full: the rest is in your inbox." or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_GIFT_WRAPS)
	return lines
end

-- the guild trophy: once per guild of an eligible player of the final kill
local function guildTrophies(run, eligible)
	local G = ChaosGuild
	if not G or not G.guildOf then
		return
	end
	local done = {}
	for _, p in ipairs(eligible) do
		local gid = G.guildOf(p)
		if gid and not done[gid] then
			done[gid] = true
			pcall(G.addStat, gid, "raidClears", 1)
			if G.addXp then
				pcall(G.addXp, gid, p:getGuid(), "raid", C().trophyGxp, true)
			end
			log(string.format("raid %d: trophy for guild %d", run.inst.id, gid))
		end
	end
end

local function bossKilled(run, i)
	local cfg = C()
	local b = cfg.bosses[i]
	local f = run.fight
	local deaths = f and f.idx == i and f.deaths or 0
	run.inst.killed = K.setBit(run.inst.killed, i)
	run.inst.cleared = K.isCleared(cfg, run.inst)
	S().saveInstance(run.inst)
	run.bossId[i] = nil
	if f and f.idx == i then
		endFight(run)
	end
	if run.session then
		run.session.kills = run.session.kills + 1
	end
	local w = week()
	local present = {}
	each(run, function(p, e)
		local where, wi = K.where(run.L, p:getPosition())
		if (where == "room" and wi == i) or e.fallen ~= nil then
			present[#present + 1] = p
		end
	end)
	local eligible, helpers = {}, {}
	for _, p in ipairs(present) do
		local set = X.lockSet(p:getGuid())
		if K.eligible(set, b.key) then
			set[b.key] = true
			S().addLock(p:getGuid(), w, b.key, run.inst.id)
			eligible[#eligible + 1] = p
		else
			helpers[#helpers + 1] = p
		end
	end
	for _, p in ipairs(eligible) do
		local ok, lines = pcall(X.deliver, p, b, i)
		local row = X.row(p:getGuid())
		row.kills = row.kills + 1
		if b.final then
			row.clears = row.clears + 1
		end
		saveRow(p:getGuid())
		mirrorLocks(p)
		send(p, "loot", {boss = b.name, eligible = true, lines = ok and lines or {}})
		-- exclusives.lua: the rare personal drop of a visual exclusive (looting players only, like the spoils)
		if ChaosExclusives and ChaosExclusives.bossKill then pcall(ChaosExclusives.bossKill, p, "raid_" .. b.key) end
	end
	for _, p in ipairs(helpers) do
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You helped slay %s. You looted it already this week: no spoils " ..
			"until the reset.", b.name))
		send(p, "loot", {boss = b.name, eligible = false, lines = {}})
	end
	-- achievements and the records count for everyone present
	local secs
	if b.final and K.sessionClear(cfg, run.session) then
		secs = math.max(1, math.floor((mnow() - run.session.firstPull) / 1000))
	end
	for _, p in ipairs(present) do
		if ChaosAchievements and ChaosAchievements.progress then
			pcall(ChaosAchievements.progress, p, "raid_kills", 1)
			pcall(ChaosAchievements.progress, p, "raid_" .. b.key, 1)
			if b.final then
				pcall(ChaosAchievements.progress, p, "raid_clears", 1)
				if deaths == 0 then
					pcall(ChaosAchievements.progress, p, "raid_flawless", 1)
				end
				if secs and secs <= cfg.speedSeconds then
					pcall(ChaosAchievements.progress, p, "raid_speed", 1)
				end
			end
		end
		if secs then
			if ChaosLeaderboard and ChaosLeaderboard.record then
				pcall(ChaosLeaderboard.record, cfg.board, p, secs)
			end
			local row = X.row(p:getGuid())
			if row.best == 0 or secs < row.best then
				row.best = secs
				saveRow(p:getGuid())
			end
		end
	end
	if b.final then
		guildTrophies(run, eligible)
		local names = {}
		for _, p in ipairs(present) do
			names[#names + 1] = p:getName()
		end
		table.sort(names)
		Game.broadcastMessage(string.format("%s fell to %s%s!", b.name, #names > 0 and table.concat(names, ", ") or "a raid",
			secs and (" in " .. K.clockText(secs)) or ""), MESSAGE_EVENT_ADVANCE)
	end
	alert(run, string.format("%s is slain! %d looted, %d helped.%s", b.name, #eligible, #helpers,
		b.final and " The Sepulchre is cleared." or " The way on opens."), "kill")
	-- the next corridor: its trash wakes up
	if cfg.bosses[i + 1] then
		spawnTrash(run, i + 1)
	end
	X.syncDoors(run)
	sendHud(run)
	log(string.format("raid %d: %s slain (%d looted, %d helped%s)", run.inst.id, b.name, #eligible, #helpers,
		secs and (", clear " .. secs .. " s") or ""))
end

-- ======================================================================== joining and leaving
local function eventsOn(player)
	player:registerEvent("ChaosRaidPlayerHit")
	player:registerEvent("ChaosRaidPrepareDeath")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosRaidPlayerHit")
	player:unregisterEvent("ChaosRaidPrepareDeath")
end

local function enter(run, m)
	local pid = m:getId()
	local pos = m:getPosition()
	run.players[pid] = {guid = m:getGuid(), name = m:getName(), entry = {x = pos.x, y = pos.y, z = pos.z}}
	X.runOf[pid] = run
	if not run.inst.members[m:getGuid()] then
		run.inst.members[m:getGuid()] = true
		S().addMember(run.inst.id, m:getGuid())
	end
	eventsOn(m)
	m:setStorageValue(ST(), 1)
	pos:sendMagicEffect(CONST_ME_TELEPORT)
	m:teleportTo(Position(run.L.start.x + rand(-1, 1), run.L.start.y + rand(-2, 2), run.L.z))
	m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	X.lockSet(m:getGuid())
	mirrorLocks(m)
	send(m, "closeInfo", {})
end

local closeRun

-- mode: "exit" | "logout" (back where the player came from) | "temple"
local function removePlayer(run, pid, mode)
	local e = run.players[pid]
	if not e then
		return
	end
	run.players[pid] = nil
	X.runOf[pid] = nil
	local p = Player(pid)
	if p then
		eventsOff(p)
		X.cleanse(p)
		p:setStorageValue(ST(), 0)
		if ChaosRiftCore.slotOfPos(C(), p:getPosition()) then
			local to = (mode == "temple" or not e.entry) and p:getTown():getTemplePosition() or P(e.entry)
			p:teleportTo(to)
			p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		send(p, "end", {text = "You left " .. C().name .. "."})
	end
	run.lastActive = os.time()
	if run.fight then
		run.fight.lastSeen = run.fight.lastSeen or mnow()
	end
end

closeRun = function(run, mode)
	if run.closed then
		return
	end
	run.closed = true
	for pid in pairs(run.players) do
		removePlayer(run, pid, mode or "temple")
	end
	if run.fight then
		endFight(run)
	end
	for mid in pairs(run.mons) do
		X.monsterRun[mid] = nil
	end
	cleanSlot(run.L)
	X.runs[run.slot] = nil
	S().saveInstance(run.inst)
	if ChaosInstanceLimits then
		ChaosInstanceLimits.freed("raid", C().name)
	end
	log(string.format("raid %d closed (slot %d)", run.inst.id, run.slot))
end

function X.interruptAll()
	for _, run in pairs(X.runs) do
		closeRun(run, "temple")
	end
end

function X.isInside(player)
	return X.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("raid", {label = "a raid", inside = X.isInside, at = function(pos)
	return ChaosRiftCore.slotOfPos(C(), pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out, now = {}, os.time()
	for slot, run in pairs(X.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.inst.id, what = string.format("slot %d, %d of %d bosses slain%s", slot,
			K.bitCount(run.inst.killed, #C().bosses), #C().bosses, run.fight and ", in a fight" or ""),
			left = run.endsAt and math.max(0, run.endsAt - now) or nil, players = n,
			idle = n == 0 and math.max(0, C().idleMinutes * 60 - (now - (run.lastActive or now))) or nil}
	end
	return out
end, close = function(id) -- everyone to the temple; the progress stays saved (as the idle close)
	for _, run in pairs(X.runs) do
		if run.inst.id == id then
			say(run, "A gamemaster closed the raid. Your progress is saved for the week.")
			closeRun(run, "temple")
			return true, "Raid " .. id .. " closed."
		end
	end
	return false, "No open raid " .. tostring(id) .. "."
end})

local function memberProblem(m)
	local cfg = C()
	if X.runOf[m:getId()] then
		return "is already in the raid"
	end
	if m:getLevel() < cfg.minLevel then
		return string.format("needs level %d", cfg.minLevel)
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(m) then
		return "has another character from the same connection online"
	end
	if inCombat(m) then
		return "is in a fight"
	end
	if insideOther(m) then
		return "is inside another instance"
	end
	return nil
end

local function groupOf(player)
	local cfg = C()
	local members = {player}
	local party = player:getParty()
	if not party then
		return members
	end
	local list = {party:getLeader()}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	local pos = player:getPosition()
	for _, m in ipairs(list) do
		if m and m:getId() ~= player:getId() and #members < cfg.maxPlayers then
			local mp = m:getPosition()
			if mp.z == pos.z and mp:getDistance(pos) <= cfg.partyRange then
				members[#members + 1] = m
			end
		end
	end
	return members
end

local function runOfInstance(id)
	for _, run in pairs(X.runs) do
		if run.inst.id == id then
			return run
		end
	end
	return nil
end

-- opens a raid: id = nil (a new raid of this week) or a saved one to continue. force: staff, any party size
function X.open(player, id, force)
	local cfg = C()
	if not cfg.enabled then
		return false, "The Sepulchre is sealed."
	end
	if X.runOf[player:getId()] then
		return false, "You are already in the raid."
	end
	if cfg.needProtectionZone and not inProtectionZone(player) and not force then
		return false, "You must stand in a protection zone to open the raid."
	end
	local why = memberProblem(player)
	if why then
		return false, "You " .. why:gsub("^is ", "are "):gsub("^needs ", "need "):gsub("^has ", "have ") .. "."
	end
	local w = week()
	local inst
	if id then
		inst = X.instance(id)
		local ok, no = K.canContinue(cfg, inst, player:getGuid(), w)
		if not ok then
			return false, ({none = "That raid does not exist.", expired = "That raid belongs to an earlier week.",
				cleared = "That raid is cleared.", member = "You were not in that raid."})[no] or "You cannot continue that raid."
		end
		if runOfInstance(id) then
			return false, "That raid is open right now: join it from the window."
		end
	end
	local group = {player}
	for k, m in ipairs(groupOf(player)) do
		if k > 1 then
			local mwhy = memberProblem(m)
			if mwhy then
				player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s stays behind: %s.", m:getName(), mwhy))
			else
				group[#group + 1] = m
			end
		end
	end
	if #group < cfg.minPlayers and not force then
		return false, string.format("The Sepulchre opens for a party of %d to %d (within %d sqm). You have %d.",
			cfg.minPlayers, cfg.maxPlayers, cfg.partyRange, #group)
	end
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(X.runs) do
		running = running + 1
	end
	local slot, L
	if not (IL and IL.capped("raid", running, cfg.limits)) then
		slot, L = takeSlot()
	end
	if not slot then
		if IL then
			local lefts, t = {}, os.time()
			for _, r in pairs(X.runs) do
				lefts[#lefts + 1] = math.max(0, (r.endsAt or t) - t)
			end
			return false, IL.busy(player, "raid", "wings of the Sepulchre", lefts, cfg.limits)
		end
		return false, "Every wing of the Sepulchre is taken right now. Try again in a moment."
	end
	if not inst then
		local newId = S().newInstance(w, player:getGuid(), player:getName())
		if not newId then
			return false, "The raid could not be saved (database)."
		end
		inst = K.newInstance(newId, w, player:getGuid(), player:getName())
		X.inst[newId] = inst
	end
	local run = {inst = inst, slot = slot, L = L, players = {}, mons = {}, bossId = {}, bossBase = {}, trashLeft = {},
		trashUp = {}, alerts = {}, lastActive = os.time(), openedAt = os.time(),
		endsAt = (cfg.sessionMinutes or 0) > 0 and os.time() + cfg.sessionMinutes * 60 or nil,
		session = {startKilled = K.bitCount(inst.killed, #cfg.bosses), kills = 0}}
	X.runs[slot] = run
	cleanSlot(L)
	X.placeFonts(run)
	for _, m in ipairs(group) do
		enter(run, m)
	end
	for i = 1, #cfg.bosses do
		if not K.hasBit(inst.killed, i) then
			spawnBoss(run, i)
		end
		if K.doorOpen(inst, i, "west") then
			spawnTrash(run, i)
		end
	end
	X.syncDoors(run)
	local nb = K.nextBoss(cfg, inst)
	say(run, string.format("%s, raid #%d: %d of %d bosses slain this week. %s", cfg.name, inst.id,
		K.bitCount(inst.killed, #cfg.bosses), #cfg.bosses, nb and ("Next: " .. cfg.bosses[nb].name .. ".") or ""))
	sendHud(run)
	log(string.format("%s opened raid %d (slot %d, %d player(s), killed %d)", player:getName(), inst.id, slot, #group,
		inst.killed))
	addEvent(X.tick, cfg.tickMs, slot, inst.id)
	return true
end

-- a member of a saved raid joins it while it is open
function X.join(player, id)
	local cfg = C()
	local run = runOfInstance(id)
	if not run then
		return false, "That raid is not open."
	end
	if not run.inst.members[player:getGuid()] and run.inst.leader ~= player:getGuid() then
		local party = player:getParty()
		local leader = party and party:getLeader()
		if not (leader and X.runOf[leader:getId()] == run) then
			return false, "Only its members (or the party of one inside) may join this raid."
		end
	end
	if players(run) >= cfg.maxPlayers then
		return false, "The raid is full."
	end
	if cfg.needProtectionZone and not inProtectionZone(player) then
		return false, "You must stand in a protection zone to join the raid."
	end
	local why = memberProblem(player)
	if why then
		return false, "You " .. why:gsub("^is ", "are "):gsub("^needs ", "need "):gsub("^has ", "have ") .. "."
	end
	enter(run, player)
	say(run, string.format("%s joins the raid.", player:getName()))
	sendHud(run)
	return true
end

-- ======================================================================== the tick
local function fightTick(run, now)
	local cfg = C()
	local f = run.fight
	local b = cfg.bosses[f.idx]
	local boss = bossOf(run, f.idx)
	if not boss then
		endFight(run)
		return
	end
	-- the boss stays in its room
	if not K.inRoom(run.L, f.idx, boss:getPosition()) then
		boss:teleportTo(P(run.L.rooms[f.idx].bossSpawn))
	end
	-- a wipe: nobody standing in the room for wipeSeconds
	if #roomPlayers(run, f.idx) == 0 then
		f.empty = f.empty or now
		if now - f.empty >= cfg.wipeSeconds * 1000 then
			wipe(run)
			return
		end
	else
		f.empty = nil
	end
	-- phases
	local frac = boss:getHealth() / math.max(1, boss:getMaxHealth())
	for _, idx in ipairs(K.advancePhase(f, b, frac)) do
		if idx > 1 then
			phaseStart(run, idx)
		end
	end
	local enraged = K.clock(b, (now - f.start) / 1000)
	if enraged and not f.enraged then
		f.enraged = true
		alert(run, string.format("%s is ENRAGED!", b.name), "fail")
	end
	if f.enraged and now >= f.nextPulse then
		f.nextPulse = now + cfg.enrage.pulseMs
		for _, p in ipairs(roomPlayers(run, f.idx)) do
			shareHit(run, p, cfg.enrage.pulseShare, COMBAT_FIREDAMAGE)
		end
	end
	-- the scheduled mechanics of the phase
	local set = K.mechSet(b, f.phase)
	for mech in pairs(set) do
		if mech ~= "sunder" and f.next[mech] and now >= f.next[mech] then
			f.next[mech] = now + K.every(cfg, mech, f.enraged)
			if M[mech] then
				local ok, err = pcall(M[mech], run)
				if not ok then
					log("mechanic " .. mech .. ": " .. tostring(err))
				end
			end
		end
	end
	if f.sunder then
		K.sunderExpire(f.sunder, cfg, now)
	end
	-- totems: the Hexed ticks and the detonations
	local alive = {}
	for mid, e in pairs(run.mons) do
		if e.kind == "totem" then
			local m = Monster(mid)
			if not m then
				run.mons[mid] = nil
			elseif K.totemExpired(cfg, e.born, now) then
				fxAt(m:getPosition(), "dome_blast_violet", CONST_ME_MORTAREA)
				alert(run, string.format("A %s detonates!", b.totem or "totem"), "fail")
				for _, p in ipairs(roomPlayers(run, f.idx)) do
					shareHit(run, p, cfg.mechanics.totem.detonateShare, COMBAT_DEATHDAMAGE)
				end
				run.mons[mid] = nil
				X.monsterRun[mid] = nil
				m:remove()
			else
				alive[#alive + 1] = m
			end
		end
	end
	if now >= f.nextHex then
		f.nextHex = now + cfg.mechanics.totem.hexMs
		local ids = {}
		for _, p in ipairs(roomPlayers(run, f.idx)) do
			ids[#ids + 1] = p:getId()
		end
		for pid, share in pairs(K.hexTick(f.hexed, cfg, #alive, ids)) do
			local p = Player(pid)
			if p then
				shareHit(run, p, share, COMBAT_DEATHDAMAGE)
			end
		end
	end
	-- hexes that ran out
	for pid, due in pairs(f.hexes) do
		if now >= due then
			hexDue(run, pid)
		end
	end
	-- adds: the heal
	if now >= f.nextHeal then
		f.nextHeal = now + 5000
		local adds = 0
		for mid, e in pairs(run.mons) do
			if e.kind == "add" and Monster(mid) then
				adds = adds + 1
			end
		end
		local heal = K.addHeal(cfg, adds, boss:getMaxHealth())
		if heal > 0 then
			Chaos.heal(boss, heal)
			boss:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
		end
	end
end

function X.tick(slot, id)
	local run = X.runs[slot]
	if not run or run.inst.id ~= id or run.closed then
		return
	end
	local cfg = C()
	local now = mnow()
	for pid in pairs(run.players) do
		local p = Player(pid)
		if not p then
			removePlayer(run, pid, "logout")
		elseif ChaosRiftCore.slotOfPos(cfg, p:getPosition()) ~= run.slot then
			removePlayer(run, pid, "exit")
		end
	end
	-- strangers in this slot (a town portal or a stored hideout spot let them in): out (chaos_constants.lua)
	if Chaos.sweepDue and Chaos.sweepDue(run, now) then
		Chaos.sweepIntruders(function(pos) return ChaosRiftCore.slotOfPos(cfg, pos) == run.slot end,
			function(p) return run.players[p:getId()] ~= nil end, "You are not part of this raid: you were sent to your temple.")
	end
	if next(run.players) == nil then
		if os.time() - (run.lastActive or os.time()) >= cfg.idleMinutes * 60 or run.inst.cleared then
			closeRun(run, "temple")
			return
		end
	else
		run.lastActive = os.time()
	end
	-- the session's time limit (instance limits): everyone back where they came from, the progress stays saved
	if run.endsAt then
		local left = run.endsAt - os.time()
		if left <= 0 then
			say(run, string.format("Time is up: %s closes. Your progress is saved for the week; continue it from the raid window.",
				cfg.name))
			closeRun(run, "exit")
			return
		end
		if ChaosInstanceLimits then
			ChaosInstanceLimits.warn(run, left, ChaosInstanceLimits.playersOf(run.players), cfg.name, cfg.limits)
		end
	end
	-- the trash of the corridors: cleared sections open their door
	for i, left in pairs(run.trashLeft) do
		if left <= 0 then
			run.trashLeft[i] = nil
			run.inst.trash = K.setBit(run.inst.trash, i)
			S().saveInstance(run.inst)
			X.syncDoors(run)
			alert(run, string.format("The corridor is clear: the door to %s opens.", cfg.bosses[i].name), "door")
		end
	end
	-- bosses outside a fight stay in their room; a raider close to one pulls it
	if run.fight then
		fightTick(run, now)
	else
		for i = 1, #cfg.bosses do
			local boss = bossOf(run, i)
			if boss then
				if not K.inRoom(run.L, i, boss:getPosition()) then
					boss:teleportTo(P(run.L.rooms[i].bossSpawn))
				end
				local pulled = false
				each(run, function(p, e)
					if not pulled and not e.fallen and K.inRoom(run.L, i, p:getPosition()) and
							p:getPosition():getDistance(boss:getPosition()) <= 8 then
						pulled = true
					end
				end)
				if pulled or (boss:getHealth() < boss:getMaxHealth() and K.doorOpen(run.inst, i, "east")) then
					pull(run, i)
					break
				end
			end
		end
	end
	if not run.closed and os.time() >= (run.hudAt or 0) then
		sendHud(run)
	end
	if not run.closed then
		addEvent(X.tick, cfg.tickMs, slot, id)
	end
end

-- ======================================================================== combat hooks
local function signed(v, ref)
	return (tonumber(ref) or 0) < 0 and -v or v
end

-- monsters: a boss takes less damage while its adds live
local mhit = CreatureEvent("ChaosRaidMonsterHit")
function mhit.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	if pt == COMBAT_HEALING then
		return pd, pt, sd, st
	end
	local run = X.monsterRun[creature:getId()]
	local e = run and run.mons[creature:getId()]
	if not e or e.kind ~= "boss" or not run.fight or run.fight.idx ~= e.idx then
		return pd, pt, sd, st
	end
	local adds = 0
	for mid, x in pairs(run.mons) do
		if x.kind == "add" and Monster(mid) then
			adds = adds + 1
		end
	end
	local cut = K.addReduction(C(), adds)
	if cut > 0 then
		pd = signed(math.floor(math.abs(pd) * (100 - cut) / 100), pd)
		if st ~= COMBAT_HEALING then
			sd = signed(math.floor(math.abs(sd) * (100 - cut) / 100), sd)
		end
	end
	return pd, pt, sd, st
end
mhit:register()

local mdeath = CreatureEvent("ChaosRaidMonsterDeath")
function mdeath.onDeath(creature)
	local mid = creature:getId()
	local run = X.monsterRun[mid]
	X.monsterRun[mid] = nil
	local e = run and run.mons[mid]
	if not e or run.closed then
		return true
	end
	run.mons[mid] = nil
	if e.kind == "trash" and run.trashLeft[e.idx] then
		run.trashLeft[e.idx] = run.trashLeft[e.idx] - 1
	end
	return true
end
mdeath:register()

local bdeath = CreatureEvent("ChaosRaidBossDeath")
function bdeath.onDeath(creature)
	local mid = creature:getId()
	for _, run in pairs(X.runs) do
		for i, id in pairs(run.bossId) do
			if id == mid then
				local ok, err = pcall(bossKilled, run, i)
				if not ok then
					log("boss kill: " .. tostring(err))
				end
				return true
			end
		end
	end
	return true
end
bdeath:register()

-- a raider is hit: the boss's sunder stacks and enrage, and the lethal catch (the entry hall instead of a death)
local phit = CreatureEvent("ChaosRaidPlayerHit")
function phit.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	local run = X.runOf[creature:getId()]
	local e = run and run.players[creature:getId()]
	if not e or pt == COMBAT_HEALING then
		return pd, pt, sd, st
	end
	local cfg = C()
	local p, s = math.abs(pd), (st == COMBAT_HEALING) and 0 or math.abs(sd)
	local f = run.fight
	if f and attacker and not run.scripted then
		local x = run.mons[attacker:getId()]
		if x and (x.kind == "boss" or x.kind == "add") then
			local mult = K.damageMult(cfg, f.enraged)
			if x.kind == "boss" and K.mechSet(cfg.bosses[f.idx], f.phase).sunder then
				local stacks = K.sunderStacks(f.sunder, creature:getId())
				mult = mult * K.sunderMult(cfg, stacks)
				if origin == ORIGIN_MELEE then
					local target = attacker:getTarget()
					if target and target:getId() == creature:getId() then
						K.sunderHit(f.sunder, cfg, creature:getId(), mnow())
						local cid = creature:getId()
						addEvent(function()
							local r, c = X.runOf[cid], Player(cid)
							if r == run and c and r.fight == f then
								sunderAfterHit(r, c)
							end
						end, 0)
					end
				end
			end
			p, s = math.floor(p * mult), math.floor(s * mult)
		end
	end
	local health = creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)
	if p + s >= health then
		p, s = math.max(0, math.min(p, health - 1)), 0
		local pid = creature:getId()
		addEvent(function()
			X.fall(pid)
		end, 0)
	end
	return signed(p, pd), pt, (st == COMBAT_HEALING) and sd or signed(s, sd ~= 0 and sd or pd), st
end
phit:register()

-- the lethal catch: the entry hall, healed; out of the fight until it ends
function X.fall(pid)
	local run = X.runOf[pid]
	local e = run and run.players[pid]
	local p = Player(pid)
	if not e or not p then
		return
	end
	X.cleanse(p)
	p:teleportTo(P(run.L.fallen))
	p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	Chaos.heal(p, math.floor(p:getMaxHealth() * C().fallen.healShare))
	if run.fight then
		e.fallen = run.fight.id
		run.fight.deaths = run.fight.deaths + 1
		alert(run, string.format("%s has fallen.", p:getName()), "fall")
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You fell. The fight goes on without you; the doors open when it ends.")
	end
	sendHud(run)
end

local prepare = CreatureEvent("ChaosRaidPrepareDeath")
function prepare.onPrepareDeath(creature)
	local run = X.runOf[creature:getId()]
	if not run then
		return true
	end
	if creature:getHealth() < 1 then
		creature:setHealth(1)
	end
	local pid = creature:getId()
	addEvent(function()
		X.fall(pid)
	end, 0)
	return false
end
prepare:register()

-- ======================================================================== portal, exit, the Font of Ash
local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:isPlayer() and creature or nil
	if not player then
		return true
	end
	local cfg = C()
	if item:getActionId() == cfg.aid.exit then
		local run = X.runOf[player:getId()]
		if run then
			removePlayer(run, player:getId(), "exit")
		else
			player:teleportTo(player:getTown():getTemplePosition())
		end
		return true
	end
	player:teleportTo(fromPosition, true)
	X.sendInfo(player)
	return true
end
step:aid(ChaosRaidConfig.aid.exit, ChaosRaidConfig.aid.portal)
step:register()

local font = Action()
function font.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local run = X.runOf[player:getId()]
	if not run then
		return true
	end
	if player:getPosition():getDistance(item:getPosition()) > 1 then
		player:sendCancelMessage("Stand next to the Font of Ash.")
		return true
	end
	if hexed(player) then
		X.cleanse(player)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The Font of Ash washes the hex away.")
	else
		player:sendCancelMessage("You carry no hex.")
	end
	return true
end
font:aid(ChaosRaidConfig.aid.font)
font:register()

-- the fonts of the rooms whose boss casts hexes (placed when a raid opens)
local function placeFonts(run)
	local cfg = C()
	for i, b in ipairs(cfg.bosses) do
		local set = {}
		for _, m in ipairs(K.bossMechs(b)) do
			set[m] = true
		end
		if set.hex then
			for _, f in ipairs(run.L.rooms[i].fonts) do
				local it = placeItem(P(f), cfg.objects.font)
				if it then
					it:setActionId(cfg.aid.font)
				end
			end
		end
	end
end
X.placeFonts = placeFonts

-- ======================================================================== the window
local journal
function X.sendJournal(player)
	if not journal then
		journal = K.journal(C())
		for _, b in ipairs(journal) do
			for _, it in ipairs(b.loot.items) do
				it.n = itemName(it.id, it.count)
			end
		end
	end
	send(player, "journal", {bosses = journal})
end

local function vendorView(guid)
	local cfg = C()
	local w = week()
	local bought = S().purchases(guid, w)
	local row = X.row(guid)
	local list = {}
	for _, k in ipairs(K.vendorStock(cfg, w)) do
		local o = K.offer(cfg, k)
		local e = {k = o.key, n = o.name, kind = o.kind, price = o.price, weekly = o.weekly, bought = bought[o.key] or 0}
		if o.kind == "gear" then
			local ok, F = pcall(function()
				return ChaosFactionsCore
			end)
			e.level, e.rarity = o.level, o.rarity
			e.mods = {}
			if ok and F and F.gearMods and ChaosItemMods then
				for _, m in ipairs(F.gearMods(o, ChaosItemMods)) do
					e.mods[#e.mods + 1] = F.modText(m) .. " (T" .. m.tier .. ")"
				end
			end
			local it = ItemType(o.id)
			e.cid = it and it.getClientId and it:getClientId() or nil
		else
			e.items = {}
			for _, it in ipairs(o.items) do
				local t = ItemType(it.id)
				e.items[#e.items + 1] = {n = itemName(it.id, it.count), c = it.count, cid = t and t.getClientId and t:getClientId() or nil}
			end
			e.cid = e.items[1] and e.items[1].cid or nil
		end
		e.can = K.canBuy(o, e.bought, row.marks) or nil
		list[#list + 1] = e
	end
	return {marks = row.marks, stock = list}
end

function X.sendInfo(player)
	local cfg = C()
	local guid = player:getGuid()
	local now = os.time()
	local w = week()
	local set = X.lockSet(guid)
	local row = X.row(guid)
	local saved = {}
	for _, inst in ipairs(S().instancesOf(guid, w)) do
		local cached = X.inst[inst.id]
		if cached then
			inst = cached
		else
			X.inst[inst.id] = inst
		end
		local v = K.instanceView(cfg, inst)
		local run = runOfInstance(inst.id)
		v.open = run ~= nil or nil
		v.inside = run ~= nil and run.players[player:getId()] ~= nil or nil
		v.mine = inst.leader == guid or nil
		saved[#saved + 1] = v
	end
	mirrorLocks(player)
	send(player, "info", {name = cfg.name, minLevel = cfg.minLevel, level = player:getLevel(), minPlayers = cfg.minPlayers,
		maxPlayers = cfg.maxPlayers, lock = K.lockView(cfg, set, now), saved = saved, marks = row.marks, kills = row.kills,
		clears = row.clears, best = row.best, vendor = vendorView(guid), inRaid = X.runOf[player:getId()] ~= nil or nil,
		pz = inProtectionZone(player) or nil})
end

-- the fixed vendor gear (factions.lua F.makeGear's way: rarity, item level, these modifiers at these tiers)
local function makeGear(o)
	local Cr, M2, F = ChaosCrafting, ChaosItemMods, ChaosFactionsCore
	if not Cr or not M2 or not Cr.writeAffix or not F then
		return nil, "The vendor's forge is cold (crafting is not loaded)."
	end
	local item = Game.createItem(o.id, 1)
	if not item then
		return nil, "That item does not exist on this server."
	end
	Cr.clearMods(item)
	item:setCustomAttribute("rarity", o.rarity)
	item:setCustomAttribute(M2.ILVL, o.level)
	item:setCustomAttribute("combatPowerLevel", o.level)
	if Cr.applyBaseBonus then
		Cr.applyBaseBonus(item, o.rarity, o.level)
	end
	for _, m in ipairs(F.gearMods(o, M2)) do
		local affix = Cr.affixOf(M2.attr(m.key)) or Cr.affixOf(m.key)
		if affix then
			Cr.writeAffix(item, affix, m.tier, m.value)
		end
	end
	item:setAttribute(ITEM_ATTRIBUTE_NAME, o.name:lower())
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Bought with Sepulchre Marks")
	item:setCustomAttribute("chaos_raid", o.key)
	Cr.rewriteDescription(item)
	return item
end

function X.buy(player, k)
	local cfg = C()
	local o = K.offer(cfg, tostring(k or ""))
	local w = week()
	if not o or not K.inStock(cfg, w, o.key) then
		return false, "That is not for sale this week."
	end
	if cfg.needProtectionZone and not inProtectionZone(player) and not X.runOf[player:getId()] then
		return false, "Visit the vendor from a protection zone (or inside the raid)."
	end
	local guid = player:getGuid()
	local bought = S().purchases(guid, w)[o.key] or 0
	local row = X.row(guid)
	local ok, why = K.canBuy(o, bought, row.marks)
	if not ok then
		return false, why == "limit" and "You bought that as often as you may this week." or
			string.format("You need %d Sepulchre Marks.", o.price)
	end
	local item
	if o.kind == "gear" then
		local err
		item, err = makeGear(o)
		if not item then
			return false, err
		end
	end
	saveRow(guid)
	if not S().spendMarks(guid, o.price) then
		if item then
			item:remove()
		end
		X.prow[guid] = nil
		return false, "Your marks could not be spent."
	end
	row.marks = row.marks - o.price
	S().addPurchase(guid, w, o.key)
	if item then
		giveEx(player, item)
	else
		for _, it in ipairs(o.items) do
			giveStack(player, it.id, it.count)
		end
	end
	return true, string.format("You bought %s for %d marks.", o.name, o.price)
end

local ext = CreatureEvent("ChaosRaidExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local d = type(msg.data) == "table" and msg.data or {}
	local a = msg.action
	if a == "open" then
		if rate(player, "open", 500) then
			X.sendInfo(player)
		end
	elseif a == "journal" then
		if rate(player, "journal", 1000) then
			X.sendJournal(player)
		end
	elseif a == "start" or a == "continue" or a == "join" then
		if rate(player, "start", 2000) then
			local id = tonumber(d.id)
			local ok, why
			if a == "join" then
				ok, why = X.join(player, id or 0)
			else
				ok, why = X.open(player, a == "continue" and id or nil)
			end
			if not ok then
				send(player, "msg", {text = why or "You cannot enter now."})
				player:sendCancelMessage(why or "You cannot enter now.")
			end
		end
	elseif a == "buy" then
		if rate(player, "buy", 600) then
			local ok, text = X.buy(player, d.key)
			send(player, "msg", {text = text, ok = ok or nil})
			X.sendInfo(player)
		end
	elseif a == "leave" then
		local run = X.runOf[player:getId()]
		if run then
			if run.fight and run.players[player:getId()] and not run.players[player:getId()].fallen and
					K.inRoom(run.L, run.fight.idx, player:getPosition()) then
				send(player, "msg", {text = "Not in the middle of a boss fight."})
			else
				removePlayer(run, player:getId(), "exit")
				X.sendInfo(player)
			end
		end
	elseif a == "query" then
		local run = X.runOf[player:getId()]
		if run then
			sendHud(run, player)
		end
	end
end
ext:type("extendedopcode")
ext:register()

-- ======================================================================== buff bar (source "raid")
function X.buffItems(player, kind)
	local run = X.runOf[player:getId()]
	local f = run and run.fight
	if not f or kind ~= "debuff" then
		return nil
	end
	local cfg = C()
	local pid = player:getId()
	local list = {}
	local s = K.sunderStacks(f.sunder, pid)
	if s > 0 then
		local at = f.sunder.at[pid] or mnow()
		list[#list + 1] = {key = "raid_sunder", name = "Sundered", icon = "buff:raid_sunder", kind = "debuff", prio = 38,
			desc = string.format("+%d%% damage taken from %s. Swap tanks at %d stacks.", s * cfg.mechanics.sunder.stackPct,
				cfg.bosses[f.idx].name, cfg.mechanics.sunder.swapAt),
			stacks = s, leftMs = math.max(0, cfg.mechanics.sunder.expireMs - (mnow() - at))}
	end
	local h = f.hexed.stacks[pid]
	if h and h > 0 then
		list[#list + 1] = {key = "raid_hexed", name = "Hexed", icon = "buff:raid_hexed", kind = "debuff", prio = 38,
			desc = string.format("Each living effigy adds a stack; %d%% of your health per stack every %d s.",
				math.floor(cfg.mechanics.totem.stackShare * 100 + 0.5), math.floor(cfg.mechanics.totem.hexMs / 1000)), stacks = h}
	end
	local due = f.hexes[pid]
	if due then
		list[#list + 1] = {key = "raid_hex", name = "Withering Hex", icon = "buff:raid_hex", kind = "debuff", prio = 37,
			desc = "Lift it (cure curse or the Font of Ash) before it bursts on everyone near you.",
			leftMs = math.max(0, due - mnow())}
	end
	return list
end

-- ======================================================================== the city portal
local function spotFree(pos)
	local tile = Tile(pos)
	return tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and not tile:getTopCreature()
		and not tile:hasFlag(TILESTATE_TELEPORT) and not tile:hasFlag(TILESTATE_FLOORCHANGE) and #(tile:getItems() or {}) == 0
end

function X.placePortals()
	local cfg = C()
	local placed = 0
	for _, townId in ipairs(cfg.portal.townIds) do
		local town = Town(townId)
		local t = town and town:getTemplePosition()
		if t then
			local done = false
			for _, off in ipairs(cfg.portal.offsets) do
				local tile = Tile(Position(t.x + off[1], t.y + off[2], t.z))
				local have = tile and tile:getItemById(cfg.portal.itemId)
				if have and have:getActionId() == cfg.aid.portal then
					done = true
					break
				end
			end
			for _, off in ipairs(cfg.portal.offsets) do
				if done then
					break
				end
				local pos = Position(t.x + off[1], t.y + off[2], t.z)
				if spotFree(pos) then
					local item = Game.createItem(cfg.portal.itemId, 1, pos)
					if item then
						item:setActionId(cfg.aid.portal)
						X.portals[#X.portals + 1] = {x = pos.x, y = pos.y, z = pos.z}
						done = true
						placed = placed + 1
					end
				end
			end
			if not done then
				log("no free tile for the portal next to the temple of town " .. townId)
			end
		end
	end
	return placed
end

-- ======================================================================== login, logout, startup, shutdown
local login = CreatureEvent("ChaosRaidLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRaidExtended")
	player:registerEvent("ChaosRaidLogout")
	X.locks[player:getGuid()] = nil
	X.prow[player:getGuid()] = nil
	if player:getStorageValue(ST()) == 1 and not X.runOf[player:getId()] then
		player:setStorageValue(ST(), 0)
		local pos = player:getPosition()
		if ChaosRiftCore.slotOfPos(C(), pos) or not Tile(pos) then
			player:teleportTo(player:getTown():getTemplePosition())
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your raid was interrupted. Its progress is saved: continue it from the raid window.")
	elseif ChaosRiftCore.slotOfPos(C(), player:getPosition()) then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	pcall(mirrorLocks, player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosRaidLogout")
function logout.onLogout(player)
	local run = X.runOf[player:getId()]
	if run then
		if run.fight and inCombat(player) and K.inRoom(run.L, run.fight.idx, player:getPosition()) then
			player:sendCancelMessage("You cannot leave in the middle of a boss fight.")
			return false
		end
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosRaidStartup")
function startup.onStartup()
	for _, problem in ipairs(K.validate(C())) do
		log("config: " .. problem)
	end
	X.createTables()
	if C().enabled then
		addEvent(function()
			log(X.placePortals() .. " portal(s) placed")
		end, 1600)
	end
	return true
end
startup:register()

local shutdown = GlobalEvent("ChaosRaidShutdown")
function shutdown.onShutdown()
	X.interruptAll()
	return true
end
shutdown:register()

-- ======================================================================== staff: /raid
local function onCommand(player, param)
	local cfg = C()
	if player:getGroup():getId() < cfg.staffGroup then
		return true
	end
	local args = {}
	for w in tostring(param or ""):gmatch("[^,%s]+") do
		args[#args + 1] = w
	end
	local function reply(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "[raid] " .. text)
	end
	local cmd = args[1] or "status"
	local run = X.runOf[player:getId()]
	if cmd == "status" then
		local n = 0
		for slot, r in pairs(X.runs) do
			n = n + 1
			reply(string.format("slot %d: raid %d killed %d trash %d players %d%s", slot, r.inst.id, r.inst.killed,
				r.inst.trash, players(r), r.fight and (" fighting " .. cfg.bosses[r.fight.idx].name) or ""))
		end
		reply(n .. " open raid(s); week " .. week())
	elseif cmd == "open" then
		local ok, why = X.open(player, tonumber(args[2]), true)
		reply(ok and "opened" or tostring(why))
	elseif cmd == "trash" then
		if run then
			for mid, e in pairs(run.mons) do
				if e.kind == "trash" then
					local m = Monster(mid)
					if m then
						hurt(m, m:getHealth())
					end
				end
			end
		end
		reply(run and "trash slain" or "not in a raid")
	elseif cmd == "kill" then
		local f = run and run.fight
		local boss = f and bossOf(run, f.idx)
		if boss then
			hurt(boss, boss:getHealth())
		end
		reply(boss and "boss slain" or "no fight")
	elseif cmd == "phase" then
		local f = run and run.fight
		local boss = f and bossOf(run, f.idx)
		local b = f and cfg.bosses[f.idx]
		local ph = b and b.phases[tonumber(args[2]) or 2]
		if boss and ph then
			local want = math.floor(boss:getMaxHealth() * ph.at) - 1
			if boss:getHealth() > want then
				hurt(boss, boss:getHealth() - want)
			end
		end
		reply(ph and "phase set" or "/raid phase, <n> (in a fight)")
	elseif cmd == "mech" then
		local f = run and run.fight
		if f and M[args[2] or ""] then
			M[args[2]](run)
		end
		reply(f and ("cast " .. tostring(args[2])) or "/raid mech, <cleave|sweep|soak|adds|marks|totem|hex> (in a fight)")
	elseif cmd == "stacks" then
		local f = run and run.fight
		if f then
			for _ = 1, tonumber(args[2]) or cfg.mechanics.sunder.swapAt do
				K.sunderHit(f.sunder, cfg, player:getId(), mnow())
			end
			sunderAfterHit(run, player)
		end
		reply(f and "stacks added" or "no fight")
	elseif cmd == "reset" then
		db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `week` = %d", T().lockouts, player:getGuid(), week()))
		X.locks[player:getGuid()] = nil
		mirrorLocks(player)
		reply("your lockouts of this week are cleared")
	elseif cmd == "marks" then
		local row = X.row(player:getGuid())
		row.marks = row.marks + (tonumber(args[2]) or 100)
		saveRow(player:getGuid())
		reply("marks: " .. row.marks)
	elseif cmd == "close" then
		if run then
			closeRun(run, "temple")
		end
		reply(run and "closed" or "not in a raid")
	elseif cmd == "portal" then
		reply(X.placePortals() .. " portal(s) placed")
	else
		reply("/raid status | open[, id] | trash | kill | phase, n | mech, key | stacks[, n] | reset | marks[, n] | close | portal")
	end
	return false
end

local talk = TalkAction("/raid")
function talk.onSay(player, words, param)
	return onCommand(player, param)
end
talk:separator(" ")
talk:register()

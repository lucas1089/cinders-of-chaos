-- The Ember Descent (roadmap item 59): a roguelike trial of 8-12 rooms in a runtime-built hall. Numbers:
-- descent_config.lua. Pure logic (tests/descent_test.lua): descent_core.lua. Overview: server/README.md "The Ember Descent".
--
-- Flow
--   the city portal (a forcefield next to the temple) or the Descent window -> "start" (normal or weekly) in a
--   protection zone, out of combat: the party within partyRange (up to 4) comes along, each member paying with his free
--   run (one a day, one weekly a week) or an Ember Sigil -> a slot of the descent grid is built (Game.createTile, the
--   rift slot functions of rift_core.lua) -> room 1 .. N of the seeded plan (descent_core.lua generate): combat waves,
--   an elite pack, a treasure guard and its chest, a shrine (health for a boon), the merchant (embers), the boss.
--   After every combat, elite and treasure room each player picks one of three boons (game_descent's cards), sometimes
--   with a curse that pays more. Boons work through the hit and kill hooks below, Quickstep through the speed, and
--   show on the buff bar (data/lib/chaos_buffs.lua source "descent").
--   A lethal hit is caught: the player is out of the run with the rewards of the depth reached (no real death, nothing
--   lost). The run ends when nobody is left, at the time limit or with the boss slain (a full clear).
--   Rewards per player at his exit: gold to the bank, orbs, a run-exclusive unique roll, titles at milestones; the
--   weekly run records its depth on the weekly leaderboard "descent".
--   A crash: the marker storage moves the character to the temple at the next login. A clean shutdown ends every run
--   first (rewards of the depth reached).
--
-- Protocol (extended opcode ChaosOpcodes.descent = 205, JSON {action, data}):
--   client -> server  open | start {weekly} | craft | pick {offer, card, curse} | buy {key} | ready | leave | query
--   server -> client  info {...}            the Descent window (free runs, sigils, craft cost, best depths, weekly)
--                     hud {...}             the run HUD (room, rooms, type, boons, curses, embers, time left, party)
--                     offer {...}           the boon choice (3 cards, maybe a curse)
--                     shop {...}            the merchant's wares
--                     closeOffer / closeShop, end {result, depth, rooms, rewards, text}, msg {text}
-- Exports: ChaosDescent.isInside(player), ChaosDescent.buffItems(player, kind) (buff bar), ChaosDescent.rowOf(guid).
-- Staff: /descent (see onCommand).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosRiftCore then
	dofile("data/scripts/chaos/rift_core.lua")
end
dofile("data/scripts/chaos/descent_core.lua")
ChaosDescentConfig = dofile("data/scripts/chaos/descent_config.lua")
dofile("data/lib/chaos_dark_paint.lua")
if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end

ChaosDescent = ChaosDescent or {}
local X = ChaosDescent
local DC = ChaosDescentCore
local R = ChaosRiftCore
local OPCODE = ChaosOpcodes.descent

local function C()
	return ChaosDescentConfig
end

local function ST()
	return C().storage
end

local function log(text)
	print("[Chaos descent] " .. text)
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

X.runs = X.runs or {} -- slot -> run
X.runOf = X.runOf or {} -- player id -> run
X.monsterRun = X.monsterRun or {} -- monster id -> run
X.built = X.built or {}
X.bad = X.bad or {}
X.rows = X.rows or {} -- guid -> {best, bestClear, freeDay, freeWeek, runs, clears, week, weekBest}
X.nextId = X.nextId or 0
X.guard = 0 -- > 0 while a boon's own extra hit is dealt (no boon applies to it again)
X.portals = X.portals or {}

-- ======================================================================== helpers
local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	if Chaos.inCombat then
		return Chaos.inCombat(player)
	end
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
end

-- damage without a source (this engine's addHealth takes the damage type first; the stock form as the fallback)
local function hurt(creature, amount)
	local before = creature:getHealth()
	creature:addHealth("physical", -amount)
	if creature:getHealth() == before then
		creature:addHealth(-amount)
	end
end

local function giveStack(player, id, count)
	if count <= 0 then
		return
	end
	local rest = count - Chaos.giveItem(player, id, count)
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
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

local function rate(player, key, ms)
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "descent." .. key, ms or 400)
end

local function send(player, action, data)
	if player then
		Chaos.send(player, OPCODE, action, data)
	end
end

-- key and arguments: every player of the run reads the line in their own language
local function say(run, key, ...)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, key, ...))
		end
	end
end

-- ======================================================================== persistence
local function T()
	return C().tables
end

function X.createTables()
	if not db or not db.query then
		return
	end
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().players .. "` (`player_id` int(11) NOT NULL, " ..
		"`best_depth` smallint(5) unsigned NOT NULL DEFAULT 0, `best_clear` tinyint(1) unsigned NOT NULL DEFAULT 0, " ..
		"`free_day` int(10) unsigned NOT NULL DEFAULT 0, `free_week` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`week` int(10) unsigned NOT NULL DEFAULT 0, `week_best` smallint(5) unsigned NOT NULL DEFAULT 0, " ..
		"`runs` int(10) unsigned NOT NULL DEFAULT 0, `clears` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T().runs .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, " ..
		"`player_id` int(11) NOT NULL, `run` int(11) NOT NULL DEFAULT 0, `seed` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`mode` varchar(8) NOT NULL DEFAULT 'daily', `paid` varchar(8) NOT NULL DEFAULT 'free', " ..
		"`depth` smallint(5) unsigned NOT NULL DEFAULT 0, `rooms` smallint(5) unsigned NOT NULL DEFAULT 0, " ..
		"`cleared` tinyint(1) unsigned NOT NULL DEFAULT 0, `result` varchar(12) NOT NULL DEFAULT '', " ..
		"`party` tinyint(3) unsigned NOT NULL DEFAULT 1, `seconds` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`gold` bigint(20) unsigned NOT NULL DEFAULT 0, `unique_id` int(11) NOT NULL DEFAULT 0, " ..
		"`boons` varchar(255) NOT NULL DEFAULT '', `started_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`ended_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_descent_runs_player` (`player_id`, `id`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
end

function X.loadRow(guid)
	local row = {best = 0, bestClear = 0, freeDay = 0, freeWeek = 0, week = 0, weekBest = 0, runs = 0, clears = 0}
	if db and db.storeQuery then
		local rows = Chaos.select(string.format("SELECT `best_depth`, `best_clear`, `free_day`, `free_week`, `week`, " ..
			"`week_best`, `runs`, `clears` FROM `%s` WHERE `player_id` = %d", T().players, guid),
			{{"best_depth", "n"}, {"best_clear", "n"}, {"free_day", "n"}, {"free_week", "n"}, {"week", "n"},
				{"week_best", "n"}, {"runs", "n"}, {"clears", "n"}})
		local r = rows[1]
		if r then
			row = {best = r.best_depth, bestClear = r.best_clear, freeDay = r.free_day, freeWeek = r.free_week,
				week = r.week, weekBest = r.week_best, runs = r.runs, clears = r.clears}
		end
	end
	X.rows[guid] = row
	return row
end

function X.rowOf(guid)
	return X.rows[guid] or X.loadRow(guid)
end

local function saveRow(guid)
	local r = X.rows[guid]
	if not r or not db or not db.query then
		return
	end
	db.query(string.format("INSERT INTO `%s` (`player_id`, `best_depth`, `best_clear`, `free_day`, `free_week`, `week`, " ..
		"`week_best`, `runs`, `clears`, `updated_at`) VALUES (%d, %d, %d, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE " ..
		"`best_depth` = VALUES(`best_depth`), `best_clear` = VALUES(`best_clear`), `free_day` = VALUES(`free_day`), " ..
		"`free_week` = VALUES(`free_week`), `week` = VALUES(`week`), `week_best` = VALUES(`week_best`), " ..
		"`runs` = VALUES(`runs`), `clears` = VALUES(`clears`), `updated_at` = VALUES(`updated_at`)", T().players, guid,
		r.best, r.bestClear, r.freeDay, r.freeWeek, r.week, r.weekBest, r.runs, r.clears, os.time()))
end

-- the Boss Spawns window's cooldown column: the time the next free run is ready
local function mirrorFree(player)
	local fs = DC.freeState(C(), X.rowOf(player:getGuid()), os.time())
	player:setStorageValue(ST() + 1, fs.daily and 0 or fs.nextDaily)
end

-- ======================================================================== Ember Sigils
local function isSigil(item)
	local s = C().sigil
	return item and item:getId() == s.itemId and item:getActionId() == s.actionId
end

-- every sigil the player carries (equipment slots and the containers in them, recursively)
function X.sigils(player)
	local found = {}
	local function walk(item, depth)
		if not item or depth > 12 then
			return
		end
		if isSigil(item) then
			found[#found + 1] = item
		end
		if item:isContainer() then
			local c = Container(item:getUniqueId())
			if c then
				for i = 0, c:getSize() - 1 do
					walk(c:getItem(i), depth + 1)
				end
			end
		end
	end
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		walk(player:getSlotItem(slot), 0)
	end
	return found
end

function X.makeSigil()
	local s = C().sigil
	local item = Game.createItem(s.itemId, 1)
	if item then
		item:setActionId(s.actionId)
		item:setCustomAttribute("descent_sigil", 1)
		item:setAttribute(ITEM_ATTRIBUTE_NAME, s.name)
		item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "an")
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, s.description)
	end
	return item
end

function X.craft(player)
	local cr = C().sigil.craft
	if player:getItemCount(cr.shardId) < cr.shards then
		return false, string.format("You need %d %s.", cr.shards, itemName(cr.shardId, cr.shards))
	end
	if not Chaos.canPay(player, cr.gold) then
		return false, string.format("You need %d gold (carried or in the bank).", cr.gold)
	end
	local paid
	paid = Chaos.pay(player, cr.gold)
	if not paid then
		return false, string.format("You need %d gold (carried or in the bank).", cr.gold)
	end
	if not player:removeItem(cr.shardId, cr.shards) then
		player:setBankBalance(player:getBankBalance() + cr.gold)
		return false, "The shards could not be taken."
	end
	local item = X.makeSigil()
	if not item then
		return false, "The sigil could not be made."
	end
	local inbox = giveEx(player, item)
	return true, string.format("You forged an %s.%s", C().sigil.name, inbox and " It is in your inbox." or "")
end

-- ======================================================================== the hall
local function riftThemes()
	if not ChaosRiftConfig then
		ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
	end
	return ChaosRiftConfig.themes
end

local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
	return tile and tile:getItemById(id)
end

-- wall and light ids: the dark set when installed (rift_config.lua dark)
local function fixtures()
	local cfg = C()
	local wall, basin = cfg.wallId, cfg.basinId
	local d = ChaosRiftConfig and ChaosRiftConfig.dark
	if d and d.enabled and ChaosDarkTiles then
		wall = ChaosDarkTiles.id(d.wall) or wall
		basin = ChaosDarkTiles.id(d.basin) or basin
	end
	return wall, basin
end

-- the hall of a slot: {center, rect, floorList, wallList, walls ("x,y" set), start, exit, basins}
function X.layout(slot)
	local cfg = C()
	local c = R.slotCenter(cfg, slot)
	local h = cfg.room.half - 1
	local L = {center = c, rect = {x1 = c.x - h, y1 = c.y - h, x2 = c.x + h, y2 = c.y + h}, floorList = {}, wallList = {},
		walls = {}, z = c.z}
	for x = L.rect.x1, L.rect.x2 do
		for y = L.rect.y1, L.rect.y2 do
			L.floorList[#L.floorList + 1] = {x = x, y = y, z = c.z}
		end
	end
	for x = L.rect.x1 - 1, L.rect.x2 + 1 do
		for y = L.rect.y1 - 1, L.rect.y2 + 1 do
			if x < L.rect.x1 or x > L.rect.x2 or y < L.rect.y1 or y > L.rect.y2 then
				L.wallList[#L.wallList + 1] = {x = x, y = y, z = c.z}
				L.walls[x .. "," .. y] = true
			end
		end
	end
	L.start = {x = c.x, y = L.rect.y2 - 2, z = c.z}
	L.exit = {x = c.x, y = L.rect.y1 + 1, z = c.z}
	L.basins = {{x = L.rect.x1, y = L.rect.y1, z = c.z}, {x = L.rect.x2, y = L.rect.y1, z = c.z},
		{x = L.rect.x1, y = L.rect.y2, z = c.z}, {x = L.rect.x2, y = L.rect.y2, z = c.z}}
	return L
end

local function buildSlot(slot)
	local L = X.layout(slot)
	if X.built[slot] then
		return L
	end
	if X.bad[slot] then
		return nil, X.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local ours = {}
	for _, th in ipairs(riftThemes()) do
		for _, id in ipairs(th.stockGrounds or th.grounds) do
			ours[id] = true
		end
		for _, id in ipairs(th.grounds) do
			ours[id] = true
		end
	end
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, f in ipairs(list) do
			local tile = Tile(P(f))
			local gid = tile and groundId(tile)
			if tile and ((not ours[gid or 0] and not (ChaosDarkPaint.isDark(gid or 0)) and not ChaosArenaLook.isOwned(gid or 0)) or (tile.getHouse and tile:getHouse())) then
				return nil, string.format("tile %d,%d,%d already exists in the map", f.x, f.y, f.z)
			end
		end
	end
	local base = (riftThemes()[1].stockGrounds or riftThemes()[1].grounds)[1]
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, f in ipairs(list) do
			local pos = P(f)
			local tile = Tile(pos) or Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(base, 1, pos)
			end
		end
	end
	local wall, basin = fixtures()
	for _, f in ipairs(L.wallList) do
		placeItem(P(f), wall)
	end
	for _, f in ipairs(L.basins) do
		placeItem(P(f), basin)
	end
	X.built[slot] = true
	return L
end

-- monsters and loose items (corpses, drops, fields, the room objects) on the floor; walls and lights stay
local function cleanSlot(L)
	local wall, basin = fixtures()
	local keep = {[wall] = true, [basin] = true}
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
				if not keep[item:getId()] and not ChaosArenaLook.isOwned(item:getId()) then
					item:remove()
				end
			end
		end
	end
end

-- the key of a hall's look in arenalook_core.lua
local function lookKey(L)
	return "descent" .. L.center.x .. "," .. L.center.y
end

-- O276: the floor of a room is the shared arena look (arenalook_core.lua): a theme per rift theme (descent_config.lua
-- look), varied ground with borders, cover and lights, a paved lane from the arrival to the gate. A hall is repainted
-- whenever the theme or the room's variant changes; the arrival, the gate, the middle (altar, stand, chest, boss) and
-- the corner basins stay open. themeIndex is the room's rift theme (1..4), depth the room number.
local function paint(L, th, themeIndex, depth)
	local lk = C().look or {}
	local name = (lk.themes or {})[themeIndex] or ChaosArenaLook.themeFor(th.name)
	local keep = {{x = L.start.x, y = L.start.y, r = 3}, {x = L.exit.x, y = L.exit.y, r = 2}, {x = L.center.x, y = L.center.y, r = 2}}
	for _, b in ipairs(L.basins) do
		keep[#keep + 1] = {x = b.x, y = b.y, r = 1}
	end
	local wall = fixtures()
	local base = (riftThemes()[1].stockGrounds or riftThemes()[1].grounds)[1]
	return ChaosArenaLook.dress(lookKey(L), L.rect, L.z, name, {keep = keep, roads = {{from = L.start, to = L.exit}},
		seed = (lk.seed or 1) + depth % (lk.variants or 3), mirror = false, cover = lk.cover, lights = lk.lights,
		wallSize = ChaosArenaLook.wallSizeOf(wall), groundIds = {[base] = true}, fallbackGround = base})
end

local function takeSlot()
	local cfg = C()
	while true do
		local slot = R.allocSlot(cfg, X.runs, X.bad)
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

-- ======================================================================== monster pool
local rawPool = dofile("data/scripts/chaos/bounty_pool.lua")
local knownCache = {}
local function known(name)
	local k = name:lower()
	if knownCache[k] == nil then
		local ok = false
		local mt = MonsterType(name)
		if mt and not (ChaosTierConfig and ChaosTierConfig.skip and ChaosTierConfig.skip[k]) then
			local okBoss, isBoss = pcall(function() return mt:isBoss() end)
			ok = not (okBoss and isBoss)
		end
		knownCache[k] = ok
	end
	return knownCache[k]
end

-- the monster types of a room: `types` picks of the depth's level window (widened when too few, then the nearest levels
-- of the pool, descent_core.lua D.pickTypes: a window above the pool's levels must not leave a room without monsters)
local function pickTypes(run, esc, r)
	return DC.pickTypes(C(), rawPool.hunt, esc.window, known, r)
end

-- ======================================================================== the run's players
local function stateOf(run, pid)
	return run.players[pid]
end

local function fxOf(pe)
	pe.fx = pe.fx or DC.effects(C(), pe.st)
	return pe.fx
end

local function refreshFx(player, pe)
	pe.fx = DC.effects(C(), pe.st)
	local want = pe.fx.speed
	if want ~= (pe.speed or 0) and player then
		player:changeSpeed(want - (pe.speed or 0))
		pe.speed = want
	end
	if pe.fx.ward > 0 and (pe.ward or 0) <= 0 and player then
		pe.ward = math.floor(player:getMaxHealth() * pe.fx.ward / 100)
		pe.wardAt = os.time()
	end
end

local function aliveCount(run)
	local n = 0
	for _ in pairs(run.players) do
		n = n + 1
	end
	return n
end

local function partyLevel(run)
	local sum, n = 0, 0
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			sum, n = sum + p:getLevel(), n + 1
		end
	end
	return n > 0 and math.floor(sum / n) or (run.level or 100)
end

local function roomOf(run)
	return run.plan.rooms[run.idx]
end

local function themeOf(run)
	local th = riftThemes()
	return th[math.min(#th, roomOf(run).theme)]
end

-- ======================================================================== HUD and messages
local function boonList(pe)
	local list = {}
	for _, key in ipairs(pe.st.order) do
		local def = DC.boonDef(C(), key)
		local n = pe.st.boons[key] or 0
		if def and n > 0 then
			list[#list + 1] = {k = key, n = def.name, d = DC.boonText(def, n), s = n, m = def.max}
		end
	end
	return list
end

local function curseList(pe)
	local list = {}
	for _, key in ipairs(pe.st.curses) do
		local def = DC.curseDef(C(), key)
		if def then
			list[#list + 1] = {k = key, n = def.name, d = DC.curseText(def), r = def.reward}
		end
	end
	return list
end

local function hudData(run, pe)
	local room = roomOf(run)
	local party = {}
	for _, pid in ipairs(run.order) do
		local e = run.players[pid]
		local p = Player(pid)
		party[#party + 1] = {name = e and e.name or (run.names[pid] or "?"), alive = e ~= nil,
			hp = p and e and math.floor(p:getHealth() * 100 / math.max(1, p:getMaxHealth())) or 0}
	end
	return {name = C().name, room = run.idx, rooms = run.plan.count, type = room.type,
		typeName = DC.ROOM_NAMES[room.type] or room.type, theme = themeOf(run).name, depth = run.depth,
		state = run.state, left = math.max(0, run.deadline - os.time()), limit = C().timeLimit,
		wave = run.wave or 0, waves = run.waves or 0, monsters = run.alive or 0,
		embers = pe and pe.st.embers or 0, reward = pe and pe.st.rewardPct or 0,
		boons = pe and boonList(pe) or {}, curses = pe and curseList(pe) or {}, ward = pe and pe.ward or 0,
		weekly = run.weekly, seed = run.seed, party = party,
		ready = run.state == "rest" and pe and run.ready[pe.id] or false,
		bossName = run.bossName}
end

local function sendHud(run, player)
	if player then
		local pe = stateOf(run, player:getId())
		send(player, "hud", hudData(run, pe))
		return
	end
	for pid, pe in pairs(run.players) do
		local p = Player(pid)
		if p then
			send(p, "hud", hudData(run, pe))
		end
	end
	run.hudAt = os.time() + C().hudEvery
end

-- ======================================================================== offers
local function cardOf(key, pe)
	local def = DC.boonDef(C(), key)
	local have = pe.st.boons[key] or 0
	return {k = key, n = def.name, d = DC.boonText(def, have + 1), s = have, m = def.max, kind = def.kind}
end

-- a boon choice for one player; source: "room", "shrine", "merchant"
local function offer(run, pid, source)
	local pe = stateOf(run, pid)
	local p = Player(pid)
	if not pe or not p then
		return false
	end
	pe.offerN = (pe.offerN or 0) + 1
	local r = DC.roomRng(run.seed, run.idx, string.format("offer:%d:%d", pe.slot, pe.offerN))
	local room = roomOf(run)
	local o = DC.rollOffer(C(), r, pe.st, run.idx, {curse = source == "room" and (room.type == "combat" or room.type == "elite")})
	if #o.cards == 0 then
		return false
	end
	o.id = pe.offerN
	o.source = source
	o.until_ = os.time() + C().chooseSeconds
	pe.offer = o
	local cards = {}
	for _, key in ipairs(o.cards) do
		cards[#cards + 1] = cardOf(key, pe)
	end
	local curse
	if o.curse then
		local c = DC.curseDef(C(), o.curse)
		curse = {k = c.key, n = c.name, d = DC.curseText(c), r = c.reward, e = c.embers}
	end
	send(p, "offer", {id = o.id, source = source, cards = cards, curse = curse, timeout = C().chooseSeconds,
		room = run.idx, rooms = run.plan.count})
	return true
end

local nextRoom, finish, removePlayer, startRoom

-- everyone still in the run has picked (and, in a rest room, is ready): the next room
local function checkAdvance(run)
	if run.ended then
		return
	end
	for pid, pe in pairs(run.players) do
		if pe.offer then
			return
		end
		if run.state == "rest" and not run.ready[pid] then
			return
		end
	end
	if run.state == "choose" or run.state == "rest" then
		run.state = "travel"
		local rid, slot = run.id, run.slot
		addEvent(function()
			local r = X.runs[slot]
			if r and r.id == rid and not r.ended then
				nextRoom(r)
			end
		end, C().nextRoomDelay * 1000)
		say(run, "The next door opens...")
		sendHud(run)
	end
end

function X.pick(player, d)
	local run = X.runOf[player:getId()]
	local pe = run and stateOf(run, player:getId())
	if not pe or not pe.offer then
		return
	end
	local o = pe.offer
	if tonumber(d.offer) ~= o.id then
		return
	end
	local ok, key, curse = DC.applyPick(C(), pe.st, o, tonumber(d.card) or 0, d.curse == true)
	if not ok then
		return
	end
	pe.offer = nil
	refreshFx(player, pe)
	local def = DC.boonDef(C(), key)
	local text = string.format("%s: %s", def.name, DC.boonText(def, pe.st.boons[key]))
	if curse then
		local c = DC.curseDef(C(), curse)
		text = text .. string.format(" Cursed with %s (+%d%% rewards, +%d embers).", c.name, c.reward, c.embers)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	player:getPosition():sendMagicEffect(curse and CONST_ME_MORTAREA or CONST_ME_MAGIC_RED)
	send(player, "closeOffer", {id = o.id})
	sendHud(run, player)
	checkAdvance(run)
end

-- ======================================================================== spawning
local function randomIn(L, margin)
	margin = margin or 2
	return {x = math.random(L.rect.x1 + margin, L.rect.x2 - margin), y = math.random(L.rect.y1 + margin, L.center.y), z = L.z}
end

local function spawnOne(run, name, pos, tier, opts)
	opts = opts or {}
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	pos = ChaosArenaLook.freeSpot(lookKey(run.L), pos) -- never inside a cover piece or a light
	local m = create(name, P(pos), true, false, opts.shown) or create(name, P(pos), true, true, opts.shown)
	if not m then
		return nil
	end
	if opts.look then
		m:setOutfit({lookType = opts.look})
	end
	if tier and ChaosApplyTier then
		ChaosApplyTier(m, tier)
	end
	local hp = math.floor(m:getMaxHealth() * run.esc.health * (opts.healthMult or 1))
	if hp > 0 and hp ~= m:getMaxHealth() then
		m:setMaxHealth(hp)
		m:setHealth(hp)
	end
	if (run.partyFx.frenzy or 0) > 0 then
		m:changeSpeed(run.partyFx.frenzy)
	end
	m:registerEvent("ChaosDescentMonsterHit")
	m:registerEvent("ChaosDescentMonsterDeath")
	X.monsterRun[m:getId()] = run
	run.monsters[m:getId()] = true
	run.alive = (run.alive or 0) + 1
	return m
end

-- one line in the log and the end of the run: a room that made no monster is never a cleared room
local function abortRun(run, why)
	log(string.format("ERROR run %d room %d (%s): %s; the run ends, the room is not counted as cleared", run.id, run.idx,
		roomOf(run).type, why))
	say(run, "The embers will not rise here: your descent ends.")
	finish(run, "error")
end

local function spawnWave(run)
	local room = roomOf(run)
	local L = run.L
	local r = DC.roomRng(run.seed, run.idx, "wave:" .. run.wave)
	local center = randomIn(L, 3)
	local spread = C().spread
	local elite = run.roomPlan.elite
	local per = {} -- the position and tier of monster k, rolled once even when its type has to change
	local spawned, failed = DC.spawnSet(run.types, run.roomPlan.size, function(e, k)
		if not per[k] then
			per[k] = {tier = elite and DC.eliteTier(C(), run.idx, r) or DC.rollTier(run.esc, r),
				pos = {x = math.max(L.rect.x1 + 1, math.min(L.rect.x2 - 1, center.x + math.random(-spread, spread))),
					y = math.max(L.rect.y1 + 1, math.min(L.rect.y2 - 4, center.y + math.random(-spread, spread))), z = L.z}}
		end
		return spawnOne(run, e.name, per[k].pos, per[k].tier, {healthMult = elite and C().elite.healthMult or 1})
	end)
	P(center):sendMagicEffect(CONST_ME_MORTAREA)
	if #failed > 0 then
		log(string.format("run %d room %d (%s): could not create %s", run.id, run.idx, room.type, table.concat(failed, ", ")))
	end
	return spawned
end

local function spawnBoss(run)
	local th = themeOf(run)
	local b = C().boss
	local name = b.names[th.name] or b.defaultName
	-- the strongest type first, then the weaker ones
	for i = #run.types, 1, -1 do
		local e = run.types[i]
		local m = spawnOne(run, e.name, run.L.center, b.tier,
			{shown = name, look = b.looks[th.name], healthMult = DC.bossHealth(C(), aliveCount(run))})
		if m then
			run.bossId = m:getId()
			run.bossName = name
			P(run.L.center):sendMagicEffect(CONST_ME_MORTAREA)
			say(run, "%s rises from the embers!", name)
			return 1
		end
		log(string.format("run %d: the boss (%s) could not be created", run.id, e.name))
	end
	return 0
end

-- the item of a room object; the reward chest falls back to the stock one while its own look is not installed
local function objectItemId(cfg, kind)
	local id = cfg.objects[kind]
	if kind == "chest" and cfg.objects.chestFallback then
		local ok, tid = pcall(function() return ItemType(id):getId() end)
		if not (ok and tid ~= nil and tid ~= 0) then
			return cfg.objects.chestFallback
		end
	end
	return id
end

local function placeObject(run, pos, kind)
	local cfg = C()
	local item = Game.createItem(objectItemId(cfg, kind), 1, P(pos))
	if item then
		item:setActionId(cfg.aid[kind])
		P(pos):sendMagicEffect(CONST_ME_FIREAREA)
	end
	return item
end

-- ======================================================================== rooms
-- the room is cleared: embers, the chest of a treasure room, the boon choices (or the end after the boss)
local function roomCleared(run)
	local room = roomOf(run)
	run.depth = run.idx
	for pid, pe in pairs(run.players) do
		pe.depth = run.depth
		pe.st.embers = pe.st.embers + DC.embers(fxOf(pe), C().embers.perRoom)
	end
	if ChaosCharms and ChaosCharms.onSource then -- a charm drop per player (charms.lua)
		for pid in pairs(run.players) do
			if Player(pid) then
				pcall(ChaosCharms.onSource, Player(pid), "descent", {depth = run.idx, boss = room.type == "boss"})
			end
		end
	end
	if room.type == "boss" then
		finish(run, "cleared")
		return
	end
	if room.type == "treasure" then
		placeObject(run, run.L.center, "chest")
		local tr = C().treasure
		for pid, pe in pairs(run.players) do
			local p = Player(pid)
			local e = DC.embers(fxOf(pe), tr.embers.base + tr.embers.perDepth * run.idx)
			local g = tr.gold.base + tr.gold.perDepth * run.idx
			pe.st.embers = pe.st.embers + e
			if p then
				p:setBankBalance(p:getBankBalance() + g)
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "The chest spills %d embers and %d gold (to your bank).", e, g))
			end
		end
	end
	run.state = "choose"
	say(run, "Room %d of %d cleared. Choose a boon.", run.idx, run.plan.count)
	for pid in pairs(run.players) do
		offer(run, pid, "room")
	end
	sendHud(run)
	checkAdvance(run)
end

local function nextWave(run)
	run.wave = run.wave + 1
	local n = spawnWave(run)
	sendHud(run)
	if n > 0 or run.alive > 0 then
		run.spawnTries = 0
		return
	end
	-- nothing could be created and nothing lives: try again with the types picked again, never "cleared"
	run.spawnTries = (run.spawnTries or 0) + 1
	local sp = C().spawn
	if run.spawnTries > sp.retries then
		abortRun(run, string.format("no monster could be created in %d tries", run.spawnTries))
		return
	end
	log(string.format("run %d room %d: wave %d made no monster, try %d of %d", run.id, run.idx, run.wave, run.spawnTries, sp.retries))
	run.wave = run.wave - 1
	local rid, slot = run.id, run.slot
	addEvent(function()
		local r = X.runs[slot]
		if r and r.id == rid and not r.ended and r.state == "fight" and r.alive <= 0 then
			r.types = pickTypes(r, r.esc, DC.roomRng(r.seed, r.idx, "types:retry" .. r.spawnTries))
			nextWave(r)
		end
	end, sp.retrySeconds * 1000)
end

startRoom = function(run)
	local cfg = C()
	local room = roomOf(run)
	cleanSlot(run.L)
	run.monsters, run.alive, run.wave, run.bossId, run.bossName = {}, 0, 0, nil, nil
	run.ready, run.used = {}, {}
	local th = themeOf(run)
	paint(run.L, th, math.min(#riftThemes(), roomOf(run).theme), run.idx)
	run.level = partyLevel(run)
	run.esc = DC.escalation(cfg, run.idx, run.level)
	local states = {}
	for _, pe in pairs(run.players) do
		states[#states + 1] = pe.st
	end
	run.partyFx = DC.partyEffects(cfg, states)
	run.roomPlan = DC.roomPlan(cfg, room.type, run.idx, aliveCount(run), run.partyFx.swarm)
	run.waves = run.roomPlan.waves
	run.types = pickTypes(run, run.esc, DC.roomRng(run.seed, run.idx, "types"))
	local i = 0
	for pid, pe in pairs(run.players) do
		local p = Player(pid)
		if p then
			i = i + 1
			local off = ({{0, 0}, {1, 0}, {-1, 0}, {0, 1}})[i] or {0, 0}
			p:teleportTo(Position(run.L.start.x + off[1], run.L.start.y + off[2], run.L.z))
			p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			pe.offer = nil
			send(p, "closeOffer", {})
			send(p, "closeShop", {})
		end
	end
	local name = DC.ROOM_NAMES[room.type] or room.type
	if room.type == "shrine" or room.type == "merchant" then
		run.state = "rest"
		run.restUntil = os.time() + cfg.readySeconds
		placeObject(run, run.L.center, room.type)
		placeObject(run, run.L.exit, "exit")
		if room.type == "shrine" then
			say(run, "Room %d of %d: a Shrine. Use the altar: %d%% of your health for a boon. Step into the gate (or press Continue) to go on.",
				run.idx, run.plan.count, cfg.shrine.healthCost)
		else
			say(run, "Room %d of %d: the Merchant. Use the stand to spend your embers. Step into the gate (or press Continue) to go on.",
				run.idx, run.plan.count)
		end
		if room.type == "merchant" then
			for pid in pairs(run.players) do
				X.sendShop(Player(pid), run)
			end
		end
		sendHud(run)
		return
	end
	run.state = "fight"
	if room.type == "boss" then
		run.waves = 1
		run.wave = 1
		say(run, "Room %d of %d: the last hall.", run.idx, run.plan.count)
		if #run.types == 0 then
			abortRun(run, string.format("no monster type in the window %d-%d", run.esc.window[1], run.esc.window[2]))
			return
		end
		if spawnBoss(run) == 0 then
			abortRun(run, "the boss could not be created")
			return
		end
		sendHud(run)
		return
	end
	say(run, run.waves == 1 and "Room %d of %d: %s (%s), %d wave." or "Room %d of %d: %s (%s), %d waves.",
		run.idx, run.plan.count, name, th.name, run.waves)
	if #run.types == 0 then
		abortRun(run, string.format("no monster type in the window %d-%d", run.esc.window[1], run.esc.window[2]))
		return
	end
	run.spawnTries = 0
	local rid, slot = run.id, run.slot
	addEvent(function()
		local r = X.runs[slot]
		if r and r.id == rid and not r.ended and r.state == "fight" and r.wave == 0 then
			nextWave(r)
		end
	end, 1500)
	sendHud(run)
end

nextRoom = function(run)
	if run.ended then
		return
	end
	if run.idx >= run.plan.count then
		finish(run, "cleared")
		return
	end
	run.idx = run.idx + 1
	startRoom(run)
end

-- ======================================================================== shrine, merchant, ready
function X.sendShop(player, run)
	local pe = player and run and stateOf(run, player:getId())
	if not pe then
		return
	end
	local wares = {}
	for _, w in ipairs(C().wares) do
		wares[#wares + 1] = {k = w.key, n = w.name, d = w.desc, p = DC.price(C(), w, run.idx),
			off = (w.key == "cleanse" and #pe.st.curses == 0) or nil}
	end
	send(player, "shop", {embers = pe.st.embers, wares = wares, room = run.idx})
end

function X.buy(player, d)
	local run = X.runOf[player:getId()]
	local pe = run and stateOf(run, player:getId())
	if not pe or roomOf(run).type ~= "merchant" or run.state ~= "rest" then
		return
	end
	local w = DC.ware(C(), tostring(d.key or ""))
	if not w then
		return
	end
	local price = DC.price(C(), w, run.idx)
	if pe.st.embers < price then
		player:sendCancelMessage(Chaos.t(player, "You do not have enough embers."))
		return
	end
	if w.key == "cleanse" and #pe.st.curses == 0 then
		player:sendCancelMessage(Chaos.t(player, "You carry no curse."))
		return
	end
	if w.key == "boon" and pe.offer then
		player:sendCancelMessage(Chaos.t(player, "Choose your boon first."))
		return
	end
	pe.st.embers = pe.st.embers - price
	if w.key == "mend" then
		Chaos.heal(player, player:getMaxHealth())
		player:addMana(player:getMaxMana() - player:getMana())
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	elseif w.key == "boon" then
		offer(run, player:getId(), "merchant")
	elseif w.key == "cleanse" then
		local key = DC.cleanse(C(), pe.st)
		refreshFx(player, pe)
		local c = DC.curseDef(C(), key)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s is lifted.", c and c.name or key))
	elseif w.key == "ward" then
		pe.shell = (pe.shell or 0) + math.floor(player:getMaxHealth() * (w.value or 25) / 100)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	end
	X.sendShop(player, run)
	sendHud(run, player)
end

function X.useShrine(player)
	local run = X.runOf[player:getId()]
	local pe = run and stateOf(run, player:getId())
	if not pe or roomOf(run).type ~= "shrine" or run.state ~= "rest" then
		return false
	end
	if run.used[player:getId()] then
		player:sendCancelMessage(Chaos.t(player, "The altar has taken its due from you."))
		return true
	end
	run.used[player:getId()] = true
	local cost = math.floor(player:getMaxHealth() * C().shrine.healthCost / 100)
	cost = math.min(cost, player:getHealth() - 1)
	if cost > 0 then
		hurt(player, cost)
	end
	player:getPosition():sendMagicEffect(CONST_ME_DRAWBLOOD)
	offer(run, player:getId(), "shrine")
	return true
end

function X.ready(player)
	local run = X.runOf[player:getId()]
	if not run or run.state ~= "rest" then
		return
	end
	run.ready[player:getId()] = true
	sendHud(run)
	checkAdvance(run)
end

-- ======================================================================== the end of a run
local function rewardPlayer(run, pe, cleared, player)
	local cfg = C()
	local depth = pe.depth or 0
	local level = player and player:getLevel() or run.level or 100
	local rw = DC.reward(cfg, depth, cleared, level, pe.st.rewardPct)
	local lines = {}
	local items = {}
	local uniqueId = 0
	if player then
		if rw.gold > 0 then
			player:setBankBalance(player:getBankBalance() + rw.gold)
			lines[#lines + 1] = string.format("%d gold (bank)", rw.gold)
		end
		for _, it in ipairs(rw.items) do
			giveStack(player, it.id, it.count)
			lines[#lines + 1] = string.format("%d %s", it.count, itemName(it.id, it.count))
			items[#items + 1] = {name = itemName(it.id, it.count), count = it.count}
		end
		if rw.uniqueChance > 0 and math.random(1, 10000) <= rw.uniqueChance then
			local u = DC.pickUnique(cfg, depth, DC.rng(math.random(1, 2000000000)))
			local item = u and Game.createItem(u.id, 1)
			if item then
				if ChaosMakeUnique then
					ChaosMakeUnique(item)
				end
				giveEx(player, item)
				uniqueId = u.id
				lines[#lines + 1] = u.name
				items[#items + 1] = {name = u.name, count = 1, unique = true}
				Chaos.broadcast(MESSAGE_EVENT_ADVANCE, "%s carried %s out of the Ember Descent!", player:getName(), u.name)
			end
		end
		-- Conquest Tokens (conquest.lua) by the depth reached, more for a full clear
		if ChaosConquest and ChaosConquest.reward then
			pcall(ChaosConquest.reward, player, "descent_clear", {depth = depth, cleared = cleared and true or nil},
				"depth " .. tostring(depth))
		end
		-- item sets (itemsets.lua): the Descent set's chase roll by the depth reached
		if ChaosItemSets and ChaosItemSets.grantChase then
			local piece = ChaosItemSets.grantChase(player, "descent", nil, {depth = depth, cleared = cleared and true or nil})
			if piece then
				lines[#lines + 1] = piece
				items[#items + 1] = {name = piece, count = 1, unique = true}
			end
		end
	end
	-- the record: best depth, full clears, the weekly board, titles
	local row = X.rowOf(pe.guid)
	local before = DC.titles(cfg, row.best, row.bestClear == 1)
	row.best = math.max(row.best, depth)
	row.runs = row.runs + 1
	if cleared then
		row.bestClear, row.clears = 1, row.clears + 1
	end
	if run.weekly then
		local week = DC.weekKey(os.time(), cfg.resetHour)
		if row.week ~= week then
			row.week, row.weekBest = week, 0
		end
		row.weekBest = math.max(row.weekBest, depth)
		if ChaosLeaderboard and ChaosLeaderboard.record then
			ChaosLeaderboard.record(cfg.board, player or {guid = pe.guid, name = pe.name}, depth, "max")
		end
	end
	saveRow(pe.guid)
	if ChaosSeasonJourney and ChaosSeasonJourney.emit then -- Seasonal Journey (season_journey.lua)
		local who = player or {guid = pe.guid, name = pe.name}
		ChaosSeasonJourney.emit(who, "descent_runs", 1)
		ChaosSeasonJourney.emit(who, "descent_depth", depth, "max")
		if cleared then
			ChaosSeasonJourney.emit(who, "descent_clears", 1)
		end
	end
	local after = DC.titles(cfg, row.best, row.bestClear == 1)
	local newTitle
	if #after > #before then
		newTitle = after[#after].text
		if player then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You earned the title \"%s\".", newTitle))
			if ChaosNameplate and ChaosNameplate.refresh then
				pcall(ChaosNameplate.refresh, player)
			end
		end
	end
	if db and db.asyncQuery then
		local boons = {}
		for _, k in ipairs(pe.st.order) do
			boons[#boons + 1] = k .. "x" .. (pe.st.boons[k] or 0)
		end
		db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `run`, `seed`, `mode`, `paid`, `depth`, `rooms`, " ..
			"`cleared`, `result`, `party`, `seconds`, `gold`, `unique_id`, `boons`, `started_at`, `ended_at`) VALUES " ..
			"(%d, %d, %d, %s, %s, %d, %d, %d, %s, %d, %d, %d, %d, %s, %d, %d)", T().runs, pe.guid, run.id, run.seed,
			db.escapeString(run.weekly and "weekly" or "daily"), db.escapeString(pe.paid or "free"), depth, run.plan.count,
			cleared and 1 or 0, db.escapeString(pe.result or ""), #run.order, os.time() - run.startTime, rw.gold, uniqueId,
			db.escapeString(table.concat(boons, ",")):sub(1, 250), run.startTime, os.time()))
	end
	return {gold = rw.gold, items = items, lines = lines, title = newTitle, depth = depth}
end

local RESULT_TEXT = {
	cleared = "The Descent is conquered!", fallen = "You fell in the Descent.", time = "The embers burned out.",
	error = "The embers would not rise.", left = "You left the Descent.", logout = "You left the Descent.", shutdown = "The Descent closes for a restart."
}

removePlayer = function(run, pid, result)
	local pe = run.players[pid]
	if not pe then
		return
	end
	run.players[pid] = nil
	X.runOf[pid] = nil
	pe.result = result
	local player = Player(pid)
	local cleared = result == "cleared"
	local rw = rewardPlayer(run, pe, cleared, player)
	if player then
		player:unregisterEvent("ChaosDescentPlayerHit")
		player:unregisterEvent("ChaosDescentPrepareDeath")
		if (pe.speed or 0) ~= 0 then
			player:changeSpeed(-pe.speed)
		end
		player:setStorageValue(ST(), 0)
		if result == "fallen" then
			Chaos.heal(player, player:getMaxHealth())
		end
		if result ~= "left" or R.slotOfPos(C(), player:getPosition()) then
			local to = pe.entry and P(pe.entry) or player:getTown():getTemplePosition()
			if run.restart then
				to = player:getTown():getTemplePosition()
			end
			player:teleportTo(to)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		local text = RESULT_TEXT[result] or ""
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s Depth %d of %d. Rewards: %s.", Chaos.t(player, text), rw.depth,
			run.plan.count, #rw.lines > 0 and table.concat(rw.lines, ", ") or Chaos.t(player, "none")))
		send(player, "end", {result = result, depth = rw.depth, rooms = run.plan.count, gold = rw.gold, items = rw.items,
			title = rw.title, text = text, weekly = run.weekly})
		mirrorFree(player)
	end
	if not run.ended and next(run.players) == nil then
		finish(run, result == "cleared" and "cleared" or "fallen")
	elseif not run.ended then
		say(run, "%s is out of the Descent.", pe.name)
		checkAdvance(run)
		sendHud(run)
	end
end

finish = function(run, result)
	if run.ended then
		return
	end
	run.ended = true
	run.state = "done"
	for pid in pairs(run.players) do
		removePlayer(run, pid, result)
	end
	for mid, r in pairs(X.monsterRun) do
		if r == run then
			X.monsterRun[mid] = nil
		end
	end
	local rid, slot = run.id, run.slot
	addEvent(function()
		local r = X.runs[slot]
		if r and r.id == rid then
			cleanSlot(r.L)
			X.runs[slot] = nil
			if ChaosInstanceLimits and not r.restart then
				ChaosInstanceLimits.freed("descent", "the Ember Descent")
			end
		end
	end, run.restart and 0 or C().exitDelay * 1000)
	if run.restart then
		cleanSlot(run.L)
		X.runs[slot] = nil
	end
	log(string.format("run %d (slot %d, seed %d%s) ended: %s at depth %d of %d", run.id, run.slot, run.seed,
		run.weekly and ", weekly" or "", result, run.depth, run.plan.count))
end
X._finish = finish
X._removePlayer = removePlayer

-- a clean shutdown: every run ends first (rewards of the depth reached), everyone to the temple
function X.interruptAll()
	for _, run in pairs(X.runs) do
		run.restart = true
		finish(run, "shutdown")
	end
end

-- ======================================================================== starting a run
local function memberProblem(m)
	local cfg = C()
	if X.runOf[m:getId()] then
		return ChaosI18n.msg("is already in the Descent")
	end
	if m:getLevel() < cfg.minLevel then
		return ChaosI18n.msg("needs level %d", cfg.minLevel)
	end
	if Chaos.isMultiClient(m) then
		return ChaosI18n.msg("has another character from the same connection online")
	end
	if inCombat(m) then
		return ChaosI18n.msg("is in a fight")
	end
	if insideOther(m) then
		return ChaosI18n.msg("is inside another instance")
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

-- how a member pays: "free", "sigil" or nil + why
local function paymentOf(m, weekly)
	local fs = DC.freeState(C(), X.rowOf(m:getGuid()), os.time())
	return DC.payment(fs, weekly, #X.sigils(m))
end

function X.start(player, weekly)
	local cfg = C()
	if not cfg.enabled then
		return false, "The Ember Descent is closed."
	end
	if X.runOf[player:getId()] then
		return false, "You are already in the Descent."
	end
	if cfg.needProtectionZone and not inProtectionZone(player) then
		return false, "You must stand in a protection zone to enter the Descent."
	end
	local why = memberProblem(player)
	if why then
		return false, ChaosI18n.msg("You %s.", ChaosI18n.you(why))
	end
	local pay, payWhy = paymentOf(player, weekly)
	if not pay then
		return false, payWhy
	end
	local group, pays = {player}, {pay}
	for i, m in ipairs(groupOf(player)) do
		if i > 1 then
			local mwhy = memberProblem(m)
			local mpay = paymentOf(m, weekly)
			if not mwhy and not mpay then
				mwhy = ChaosI18n.msg(weekly and "has used the free weekly descent and carries no Ember Sigil"
					or "has used today's free descent and carries no Ember Sigil")
			end
			if mwhy then
				player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s stays behind: %s.", m:getName(), mwhy))
				m:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(m, "You stay behind from %s's descent: you %s.", player:getName(),
					ChaosI18n.you(mwhy)))
			else
				group[#group + 1] = m
				pays[#pays + 1] = mpay
			end
		end
	end
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(X.runs) do
		running = running + 1
	end
	local slot, L
	if not (IL and IL.capped("descent", running, cfg.limits)) then
		slot, L = takeSlot()
	end
	if not slot then
		if IL then
			local lefts, t = {}, os.time()
			for _, r in pairs(X.runs) do
				lefts[#lefts + 1] = r.ended and cfg.exitDelay or math.max(0, r.deadline - t)
			end
			return false, IL.busy(player, "descent", "halls of the Descent", lefts, cfg.limits)
		end
		return false, "Every hall of the Descent is taken right now. Try again in a moment."
	end
	-- payment: the free run of the mode, or one sigil
	local now = os.time()
	for i, m in ipairs(group) do
		local row = X.rowOf(m:getGuid())
		if pays[i] == "free" then
			local fs = DC.freeState(cfg, row, now)
			if weekly then
				row.freeWeek = fs.week
			else
				row.freeDay = DC.spendDaily(cfg, row, now)
			end
			saveRow(m:getGuid())
		else
			local s = X.sigils(m)[1]
			if not s or not s:remove(1) then
				return false, ChaosI18n.msg("%s's sigil could not be used.", m:getName())
			end
		end
	end
	X.nextId = X.nextId + 1
	local seed = weekly and DC.weekSeed(DC.weekKey(now, cfg.resetHour)) or DC.runSeed(player:getGuid(), now, X.nextId)
	local run = {id = X.nextId, slot = slot, L = L, seed = seed, weekly = weekly and true or false, idx = 1, depth = 0,
		plan = DC.generate(cfg, seed, #riftThemes()), players = {}, order = {}, names = {}, startTime = now,
		deadline = now + cfg.timeLimit, state = "fight", monsters = {}, alive = 0, ready = {}, used = {}}
	X.runs[slot] = run
	for i, m in ipairs(group) do
		local pid = m:getId()
		local entry = m:getPosition()
		run.players[pid] = {id = pid, guid = m:getGuid(), name = m:getName(), entry = {x = entry.x, y = entry.y, z = entry.z},
			st = DC.newState(), slot = i, paid = pays[i], depth = 0, speed = 0, ward = 0, shell = 0}
		run.order[#run.order + 1] = pid
		run.names[pid] = m:getName()
		X.runOf[pid] = run
		m:registerEvent("ChaosDescentPlayerHit")
		m:registerEvent("ChaosDescentPrepareDeath")
		m:setStorageValue(ST(), 1)
		entry:sendMagicEffect(CONST_ME_TELEPORT)
		mirrorFree(m)
	end
	local kinds = {}
	for _, r in ipairs(run.plan.rooms) do
		kinds[#kinds + 1] = r.type
	end
	log(string.format("%s opened run %d: slot %d, seed %d%s, %d player(s), rooms %s", player:getName(), run.id, slot,
		seed, run.weekly and " (weekly)" or "", #group, table.concat(kinds, "/")))
	say(run, run.weekly and "You enter %s (weekly descent): %d rooms, %d minutes." or "You enter %s: %d rooms, %d minutes.",
		cfg.name, run.plan.count, math.floor(cfg.timeLimit / 60))
	startRoom(run)
	addEvent(X.tick, 1000, slot, run.id)
	return true
end

-- ======================================================================== the tick
function X.tick(slot, rid)
	local run = X.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local now = os.time()
	if now >= run.deadline then
		say(run, "The embers burn out: your descent ends here.")
		finish(run, "time")
		return
	end
	if ChaosInstanceLimits then -- warnings before the end (instance_limits.lua)
		ChaosInstanceLimits.warn(run, run.deadline - now, ChaosInstanceLimits.playersOf(run.players), "Ember Descent", C().limits)
	end
	for pid, pe in pairs(run.players) do
		local p = Player(pid)
		if not p then
			removePlayer(run, pid, "logout")
		elseif R.slotOfPos(C(), p:getPosition()) ~= run.slot then
			removePlayer(run, pid, "left")
		else
			local fx = fxOf(pe)
			if fx.ward > 0 and now - (pe.wardAt or 0) >= fx.wardEvery then
				pe.ward = math.floor(p:getMaxHealth() * fx.ward / 100)
				pe.wardAt = now
			end
			if pe.offer and now >= pe.offer.until_ then
				X.pick(p, {offer = pe.offer.id, card = 1, curse = false})
			end
		end
	end
	if run.ended then
		return
	end
	-- strangers in this slot (a town portal or a stored hideout spot let them in): out (chaos_constants.lua)
	if Chaos.sweepDue and Chaos.sweepDue(run, now * 1000) then
		Chaos.sweepIntruders(function(pos) return R.slotOfPos(C(), pos) == run.slot end,
			function(p) return run.players[p:getId()] ~= nil end, "You are not part of this descent: you were sent to your temple.")
	end
	if run.state == "rest" and now >= (run.restUntil or now) then
		for pid in pairs(run.players) do
			run.ready[pid] = true
		end
		checkAdvance(run)
	end
	if now >= (run.hudAt or 0) then
		sendHud(run)
	end
	addEvent(X.tick, 1000, slot, rid)
end

-- ======================================================================== combat hooks
-- a new amount with the sign of the engine's value (this engine hands damage over as negative numbers)
local function signed(v, ref)
	return (tonumber(ref) or 0) < 0 and -v or v
end

local ELEMENT
local function elementType(name)
	if not ELEMENT then
		ELEMENT = {fire = COMBAT_FIREDAMAGE, ice = COMBAT_ICEDAMAGE, death = COMBAT_DEATHDAMAGE,
			energy = COMBAT_ENERGYDAMAGE, earth = COMBAT_EARTHDAMAGE, holy = COMBAT_HOLYDAMAGE}
	end
	return ELEMENT[name]
end

local function extraHit(attackerId, targetId, ctype, amount, effect)
	local target = Creature(targetId)
	if not target or amount <= 0 then
		return
	end
	X.guard = X.guard + 1
	pcall(doTargetCombatHealth, attackerId or 0, target, ctype, -amount, -amount, effect or CONST_ME_NONE)
	X.guard = X.guard - 1
end

-- hits on Descent monsters: the attacker's boons
local mhit = CreatureEvent("ChaosDescentMonsterHit")
function mhit.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	if X.guard > 0 or pt == COMBAT_HEALING or not attacker then
		return pd, pt, sd, st
	end
	local run = X.monsterRun[creature:getId()]
	local owner = playerOf(attacker)
	local pe = run and owner and stateOf(run, owner:getId())
	if not pe then
		return pd, pt, sd, st
	end
	local fx = fxOf(pe)
	local before = math.abs(pd) + (st ~= COMBAT_HEALING and math.abs(sd) or 0)
	if before <= 0 then
		return pd, pt, sd, st
	end
	local pct = math.floor(creature:getHealth() * 100 / math.max(1, creature:getMaxHealth()))
	local out = DC.hitOut(fx, before, pt == COMBAT_PHYSICALDAMAGE and (sd == 0 or st == COMBAT_NONE), pct,
		DC.rng(math.random(1, 2000000000)))
	-- spread the new total over primary and secondary in their old shares; a brand turns part of a physical hit
	local npd, nsd
	local ref = pd
	if out.converted > 0 then
		npd, nsd, st = out.amount - out.converted, out.converted, elementType(out.element) or st
		sd = pd
	else
		npd = math.floor(out.amount * math.abs(pd) / before)
		nsd = out.amount - npd
	end
	local cid, aid = creature:getId(), owner:getId()
	if out.crit then
		creature:getPosition():sendMagicEffect(CONST_ME_CRITICAL_DAMAGE or CONST_ME_EXPLOSIONHIT)
	end
	if out.echo > 0 then
		addEvent(function()
			local a, t = Player(aid), Creature(cid)
			if a and t then
				a:getPosition():sendDistanceEffect(t:getPosition(), CONST_ANI_FIRE)
				extraHit(aid, cid, out.element and elementType(out.element) or pt, out.echo, CONST_ME_FIREATTACK)
			end
		end, 250)
	end
	if out.leech > 0 then
		local heal = DC.healIn(fx, out.leech)
		if heal > 0 then
			addEvent(function()
				local a = Player(aid)
				if a then
					Chaos.heal(a, heal)
				end
			end, 0)
		end
	end
	return signed(npd, ref), pt, signed(nsd, sd ~= 0 and sd or ref), st
end
mhit:register()

-- a Descent monster died: embers, kill boons, the next wave or the end of the room
local mdeath = CreatureEvent("ChaosDescentMonsterDeath")
function mdeath.onDeath(creature, corpse, killer, mostDamageKiller)
	local mid = creature:getId()
	local run = X.monsterRun[mid]
	X.monsterRun[mid] = nil
	if not run or run.ended or not run.monsters[mid] then
		return true
	end
	run.monsters[mid] = nil
	run.alive = math.max(0, run.alive - 1)
	local elite = run.roomPlan and run.roomPlan.elite
	for pid, pe in pairs(run.players) do
		pe.st.embers = pe.st.embers + DC.embers(fxOf(pe), elite and C().embers.eliteKill or C().embers.perKill)
	end
	local owner = playerOf(killer) or playerOf(mostDamageKiller)
	local pe = owner and stateOf(run, owner:getId())
	if pe then
		local fx = fxOf(pe)
		if fx.harvest > 0 then
			Chaos.heal(owner, DC.healIn(fx, math.floor(owner:getMaxHealth() * fx.harvest / 100)))
			owner:addMana(math.floor(owner:getMaxMana() * fx.harvest / 100))
		end
		if fx.burst > 0 then
			local pos = creature:getPosition()
			local dmg = math.floor(creature:getMaxHealth() * fx.burst / 100)
			local aid = owner:getId()
			pos:sendMagicEffect(CONST_ME_FIREAREA)
			for _, c in ipairs(Game.getSpectators(pos, false, false, fx.burstRadius, fx.burstRadius, fx.burstRadius, fx.burstRadius) or {}) do
				if c:isMonster() and X.monsterRun[c:getId()] == run then
					local tid = c:getId()
					addEvent(extraHit, 100, aid, tid, COMBAT_FIREDAMAGE, dmg, CONST_ME_FIREATTACK)
				end
			end
		end
	end
	if mid == run.bossId then
		run.bossId = nil
	end
	if run.alive <= 0 and run.state == "fight" then
		local rid, slot = run.id, run.slot
		addEvent(function()
			local r = X.runs[slot]
			if not r or r.id ~= rid or r.ended or r.state ~= "fight" or r.alive > 0 then
				return
			end
			if r.wave < r.waves then
				nextWave(r)
			else
				roomCleared(r)
			end
		end, 1200)
	end
	if run.killHud ~= os.time() then
		run.killHud = os.time()
		sendHud(run)
	end
	return true
end
mdeath:register()

-- the player's side: monster damage scaling, wards, Stoneskin, Frailty, Thornmail, Withering, the lethal catch
local phit = CreatureEvent("ChaosDescentPlayerHit")
function phit.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	local run = X.runOf[creature:getId()]
	local pe = run and stateOf(run, creature:getId())
	if not pe then
		return pd, pt, sd, st
	end
	local fx = fxOf(pe)
	if pt == COMBAT_HEALING then
		if fx.healing > 0 then
			pd = signed(DC.healIn(fx, math.abs(pd)), pd)
			if st == COMBAT_HEALING then
				sd = signed(DC.healIn(fx, math.abs(sd)), sd)
			end
		end
		return pd, pt, sd, st
	end
	local fromMonster = attacker and X.monsterRun[attacker:getId()] == run
	local p, s = math.abs(pd), (st == COMBAT_HEALING) and 0 or math.abs(sd)
	if fromMonster and run.esc then
		p, s = math.floor(p * run.esc.damage), math.floor(s * run.esc.damage)
	end
	local total = p + s
	if total > 0 then
		local shield = (pe.shell or 0) + (pe.ward or 0)
		local after, absorbed = DC.hitIn(fx, total, shield)
		if absorbed > 0 then
			local fromShell = math.min(pe.shell or 0, absorbed)
			pe.shell = (pe.shell or 0) - fromShell
			pe.ward = math.max(0, (pe.ward or 0) - (absorbed - fromShell))
			creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		end
		local ps = total > 0 and p / total or 1
		p = math.floor(after * ps)
		s = after - p
		if fromMonster and fx.thorns > 0 and X.guard == 0 then
			local back = math.floor(total * fx.thorns / 100)
			local aid, cid = creature:getId(), attacker:getId()
			addEvent(extraHit, 0, aid, cid, COMBAT_PHYSICALDAMAGE, back, CONST_ME_HITAREA)
		end
	end
	-- the lethal catch (the energy shield, engine patch 0015, takes its part after this event)
	local health = creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)
	if p + s >= health then
		if fx.phoenix > 0 and not pe.phoenixUsed then
			pe.phoenixUsed = true
			local keep = math.max(1, math.floor(creature:getMaxHealth() * fx.phoenix / 100))
			local cut = math.max(0, creature:getHealth() - keep)
			creature:getPosition():sendMagicEffect(CONST_ME_FIREAREA)
			creature:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(creature, "The Phoenix Ember flares: you rise again."))
			addEvent(function(cid, want)
				local pl = Player(cid)
				if pl and pl:getHealth() < want then
					Chaos.heal(pl, want - pl:getHealth())
				end
			end, 0, creature:getId(), keep)
			p, s = math.min(p, cut), 0
		else
			p, s = math.max(0, math.min(p, health - 1)), 0
			local pid = creature:getId()
			addEvent(function()
				local r = X.runOf[pid]
				if r == run then
					removePlayer(run, pid, "fallen")
				end
			end, 0)
		end
	end
	return signed(p, pd), pt, (st == COMBAT_HEALING) and sd or signed(s, sd ~= 0 and sd or pd), st
end
phit:register()

-- the safety net: whatever got past the hit event (another script raising the damage, a hit without origin)
local prepare = CreatureEvent("ChaosDescentPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local run = X.runOf[creature:getId()]
	if not run then
		return true
	end
	if creature:getHealth() < 1 then
		creature:setHealth(1)
	end
	local pid = creature:getId()
	addEvent(function()
		if X.runOf[pid] == run then
			removePlayer(run, pid, "fallen")
		end
	end, 0)
	return false
end
prepare:register()

-- ======================================================================== room objects
local obj = Action()
function obj.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local cfg = C()
	local aid = item:getActionId()
	if aid == cfg.aid.shrine then
		if not X.useShrine(player) then
			player:sendCancelMessage(Chaos.t(player, "The altar is cold."))
		end
	elseif aid == cfg.aid.merchant then
		local run = X.runOf[player:getId()]
		if run and roomOf(run).type == "merchant" then
			X.sendShop(player, run)
		end
	elseif aid == cfg.aid.chest then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "The chest is empty: its embers and gold are yours already."))
	end
	return true
end
obj:aid(ChaosDescentConfig.aid.shrine, ChaosDescentConfig.aid.merchant, ChaosDescentConfig.aid.chest)
obj:register()

-- the exit gate of a rest room and the city portal
local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:isPlayer() and creature or nil
	if not player then
		return true
	end
	local cfg = C()
	if item:getActionId() == cfg.aid.exit then
		X.ready(player)
		player:teleportTo(fromPosition, true)
		return true
	end
	-- the city portal: the Descent window
	player:teleportTo(fromPosition, true)
	X.sendInfo(player)
	return true
end
step:aid(ChaosDescentConfig.aid.exit, ChaosDescentConfig.aid.portal)
step:register()

-- ======================================================================== the window
function X.sendInfo(player)
	local cfg = C()
	local row = X.rowOf(player:getGuid())
	local now = os.time()
	local fs = DC.freeState(cfg, row, now)
	local cr = cfg.sigil.craft
	local week = DC.weekKey(now, cfg.resetHour)
	local titles = {}
	for _, t in ipairs(cfg.titles) do
		titles[#titles + 1] = {text = t.text, depth = t.depth, clear = t.clear or nil,
			held = (t.clear and row.bestClear == 1) or (t.depth and row.best >= t.depth) or false}
	end
	send(player, "info", {name = cfg.name, minLevel = cfg.minLevel, level = player:getLevel(), maxPlayers = cfg.maxPlayers,
		rooms = {cfg.rooms.min, cfg.rooms.max}, freeDaily = fs.daily, freeDailyCount = fs.dailyCount, freeWeekly = fs.weekly,
		nextDaily = math.max(0, fs.nextDaily - now), sigils = #X.sigils(player),
		craft = {shards = cr.shards, gold = cr.gold, haveShards = player:getItemCount(cr.shardId),
			haveGold = Chaos.totalMoney(player), name = cfg.sigil.name},
		best = row.best, bestClear = row.bestClear == 1, runs = row.runs, clears = row.clears,
		weekBest = row.week == week and row.weekBest or 0, week = week, weekSeed = DC.weekSeed(week),
		titles = titles, inRun = X.runOf[player:getId()] ~= nil, timeLimit = cfg.timeLimit})
end

local ext = CreatureEvent("ChaosDescentExtended")
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
	elseif a == "start" then
		if rate(player, "start", 2000) then
			local ok, why = X.start(player, d.weekly == true)
			if not ok then
				local text = Chaos.t(player, why or "You cannot enter now.")
				send(player, "msg", {text = text})
				player:sendCancelMessage(text)
			else
				send(player, "closeInfo", {})
			end
		end
	elseif a == "craft" then
		if rate(player, "craft", 1000) then
			local _, text = X.craft(player)
			send(player, "msg", {text = text and Chaos.tx(player, text) or text})
			X.sendInfo(player)
		end
	elseif a == "pick" then
		X.pick(player, d)
	elseif a == "buy" then
		if rate(player, "buy", 300) then
			X.buy(player, d)
		end
	elseif a == "ready" then
		X.ready(player)
	elseif a == "leave" then
		local run = X.runOf[player:getId()]
		if run then
			removePlayer(run, player:getId(), "left")
		end
	elseif a == "query" then
		local run = X.runOf[player:getId()]
		if run then
			sendHud(run, player)
			local pe = stateOf(run, player:getId())
			if pe and pe.offer then
				pe.offerN = pe.offerN - 1
				offer(run, player:getId(), pe.offer.source)
			end
		end
	end
end
ext:type("extendedopcode")
ext:register()

-- ======================================================================== buff bar and titles
-- the buff bar's source "descent" (data/lib/chaos_buffs.lua): kind "buff" = the boons, "debuff" = the curses
function X.buffItems(player, kind)
	local run = X.runOf[player:getId()]
	local pe = run and stateOf(run, player:getId())
	if not pe then
		return nil
	end
	local list = {}
	if kind == "buff" then
		for _, b in ipairs(boonList(pe)) do
			list[#list + 1] = {key = "descent_b_" .. b.k, name = b.n, desc = b.d, icon = "buff:descent_b_" .. b.k,
				kind = "buff", prio = 26, stacks = b.s > 1 and b.s or nil}
		end
	else
		for _, c in ipairs(curseList(pe)) do
			list[#list + 1] = {key = "descent_c_" .. c.k, name = c.n, desc = c.d, icon = "buff:descent_c_" .. c.k,
				kind = "debuff", prio = 39}
		end
	end
	return list
end

function X.isInside(player)
	return X.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("descent", {label = "the Ember Descent", inside = X.isInside, at = function(pos)
	return R.slotOfPos(C(), pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out, now = {}, os.time()
	for slot, run in pairs(X.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.id, what = string.format("slot %d, room %d of %d%s", slot, run.idx or 0, run.plan.count,
			run.ended and ", ending" or ""), left = not run.ended and math.max(0, run.deadline - now) or nil, players = n}
	end
	return out
end, close = function(id) -- as when the time runs out: every player out with the rewards of the depth reached
	for _, run in pairs(X.runs) do
		if run.id == id and not run.ended then
			say(run, "A gamemaster closed the Descent.")
			finish(run, "time")
			return true, "Descent run " .. id .. " closed."
		end
	end
	return false, "No running Descent run " .. tostring(id) .. "."
end})

if ChaosTitles and ChaosTitles.register then
	ChaosTitles.register("descent", function(player)
		local row = X.rows[player:getGuid()]
		if not row then
			return nil
		end
		local list = {}
		for _, t in ipairs(DC.titles(C(), row.best, row.bestClear == 1)) do
			list[#list + 1] = {text = t.text, key = "descent:" .. t.text:lower(), color = t.color}
		end
		return list
	end)
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
		-- the town's fixed tile (portal.positions: in Cinderhold an alcove of the temple's portal gallery,
		-- temple_portals_config.lua); else next to the temple
		local fixed
		for _, p in ipairs(cfg.portal.positions or {}) do
			if p.town == townId and Tile(Position(p.x, p.y, p.z)) then
				fixed = Position(p.x, p.y, p.z)
			end
		end
		if fixed then
			local tile = Tile(fixed)
			local have = tile:getItemById(cfg.portal.itemId)
			local ok = have and have:getActionId() == cfg.aid.portal
			if not ok then
				local item = spotFree(fixed) and Game.createItem(cfg.portal.itemId, 1, fixed)
				if item then
					item:setActionId(cfg.aid.portal)
					X.portals[#X.portals + 1] = {x = fixed.x, y = fixed.y, z = fixed.z}
					placed = placed + 1
					ok = true
				else
					log("the fixed portal tile of town " .. townId .. " is taken (portal.positions): next to the temple")
				end
			end
			if ok then
				t = nil
			end
		end
		if t then
			local done = false
			for _, off in ipairs(cfg.portal.offsets) do
				local pos = Position(t.x + off[1], t.y + off[2], t.z)
				local tile = Tile(pos)
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
	-- the look text and the effect of a city portal (cityportals.lua, cityportals_fx.lua)
	if not ChaosCityPortals then
		pcall(dofile, "data/scripts/chaos/cityportals.lua")
	end
	if ChaosCityPortals then
		for _, p in ipairs(X.portals) do
			ChaosCityPortals.register("descent", cfg.aid.portal, p)
		end
	end
	return placed
end

-- ======================================================================== login, logout, startup, shutdown
local login = CreatureEvent("ChaosDescentLogin")
function login.onLogin(player)
	player:registerEvent("ChaosDescentExtended")
	player:registerEvent("ChaosDescentLogout")
	X.loadRow(player:getGuid())
	-- a run in progress at a crash: back to the temple
	if player:getStorageValue(ST()) == 1 and not X.runOf[player:getId()] then
		player:setStorageValue(ST(), 0)
		local pos = player:getPosition()
		if R.slotOfPos(C(), pos) or not Tile(pos) then
			player:teleportTo(player:getTown():getTemplePosition())
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your last descent was interrupted by a server restart."))
	elseif R.slotOfPos(C(), player:getPosition()) then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	mirrorFree(player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosDescentLogout")
function logout.onLogout(player)
	local run = X.runOf[player:getId()]
	if run then
		if inCombat(player) and run.state == "fight" then
			player:sendCancelMessage(Chaos.t(player, "You cannot leave the Descent while you are in a fight."))
			return false
		end
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosDescentStartup")
function startup.onStartup()
	for _, problem in ipairs(DC.validate(C())) do
		log("config: " .. problem)
	end
	X.createTables()
	if C().enabled then
		addEvent(function()
			log(X.placePortals() .. " portal(s) placed")
		end, 1500)
	end
	return true
end
startup:register()

local shutdown = GlobalEvent("ChaosDescentShutdown")
function shutdown.onShutdown()
	X.interruptAll()
	return true
end
shutdown:register()

-- ======================================================================== staff: /descent
local function onCommand(player, words, param)
	if player:getGroup():getId() < 4 then
		return true
	end
	local args = {}
	for w in tostring(param or ""):gmatch("%S+") do
		args[#args + 1] = w
	end
	local function reply(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "[descent] " .. text)
	end
	local cmd = args[1] or "status"
	-- a sigil is a tradable item: an administrator only, logged (docs/GM_HANDBOOK.md section 2)
	if cmd == "sigil" and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	if cmd == "status" then
		local n = 0
		for slot, run in pairs(X.runs) do
			n = n + 1
			local names = {}
			for _, pe in pairs(run.players) do
				names[#names + 1] = pe.name
			end
			reply(string.format("slot %d: run %d seed %d room %d/%d (%s) %s, alive %d, %ds left, players %s", slot, run.id,
				run.seed, run.idx, run.plan.count, roomOf(run).type, run.state, run.alive or 0, run.deadline - os.time(),
				table.concat(names, ", ")))
		end
		reply(n .. " run(s)")
	elseif cmd == "sigil" then
		local item = X.makeSigil()
		if item then
			giveEx(player, item)
		end
		reply("a sigil")
	elseif cmd == "reset" then
		local row = X.rowOf(player:getGuid())
		row.freeDay, row.freeWeek = 0, 0
		saveRow(player:getGuid())
		mirrorFree(player)
		reply("free runs reset")
	elseif cmd == "clear" then
		local run = X.runOf[player:getId()]
		if run then
			for mid in pairs(run.monsters) do
				local m = Monster(mid)
				if m then
					hurt(m, m:getHealth())
				end
			end
		end
		reply(run and "room cleared" or "not in a run")
	elseif cmd == "skip" then
		local run = X.runOf[player:getId()]
		if run then
			cleanSlot(run.L)
			run.state = "fight"
			run.alive, run.wave = 0, run.waves
			roomCleared(run)
		end
		reply(run and "room skipped" or "not in a run")
	elseif cmd == "boon" then
		local run = X.runOf[player:getId()]
		local pe = run and stateOf(run, player:getId())
		local def = pe and DC.boonDef(C(), args[2] or "")
		if def then
			if (pe.st.boons[def.key] or 0) == 0 then
				pe.st.order[#pe.st.order + 1] = def.key
			end
			pe.st.boons[def.key] = math.min(def.max, (pe.st.boons[def.key] or 0) + 1)
			refreshFx(player, pe)
			sendHud(run, player)
		end
		reply(def and ("boon " .. def.key) or "/descent boon <key> (in a run)")
	elseif cmd == "offer" then
		local run = X.runOf[player:getId()]
		if run then
			offer(run, player:getId(), "room")
		end
		reply(run and "offer sent" or "not in a run")
	elseif cmd == "portal" then
		reply(X.placePortals() .. " portal(s) placed")
	else
		reply("/descent status | sigil | reset | clear | skip | boon <key> | offer | portal")
	end
	return false
end

local talk = TalkAction("/descent")
function talk.onSay(player, words, param)
	return onCommand(player, words, param)
end
talk:separator(" ")
talk:register()

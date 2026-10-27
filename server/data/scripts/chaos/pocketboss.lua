-- Pocket bosses: a private copy of a time-gated or contested boss (the world bosses, the weekly island bosses, the
-- random raid bosses such as Moloveth), opened any time from the Boss Spawns window (client game_bossspawns, extended
-- opcode ChaosOpcodes.bossSpawns = 217: bossspawns.lua hands the pocket* actions to ChaosPocketBoss.actions). Owner
-- rule: no player talkaction or command opens it (client UI only). Daily charges per character and boss, reduced
-- experience and loot, Conquest Tokens.
-- The scheduled and contested fights stay the full-reward events; their island and raid bosses now give a personal
-- loot roll to every helper above a contribution threshold (not only the corpse owner).
-- Settings: pocketboss_config.lua (Chaos.pocketBossConfig). Pure logic: pocketboss_core.lua (tests/pocketboss_test.lua).
-- Overview: server/README.md "Pocket bosses".
--
--   the list    pocketboss_core.lua K.list: Chaos.worldBoss's bosses and the Boss Spawns entries of the island and raid
--               categories whose monster type is loaded (bossspawns.lua leaves the others out)
--   charges     chaos_pocketboss (player, boss): the day's used charges and the bonus charges; a charge is written at
--               once when spent (before the teleport): logout, death or a crash never give it back. A server shutdown
--               with a pocket open gives the charges of that pocket back (refundOnRestart).
--   the arena   uber_core.lua's runtime-built slot layout (as the guild boss), a grid of its own (pocketboss_config.lua
--               grid); a way out (portalActionId) in the antechamber
--   the fight   the boss's own monster type, health x the party curve, its hits x the damage curve; boss_mechanics.lua
--               attaches its profile when it has one; a lethal hit is caught (catchLethal): the player goes back out
--   rewards     experience x xpMult (EventCallback onGainExperience), the corpse x lootMult (loot.lua reads
--               ChaosPocketBoss.lootMultOf), Conquest Tokens (ChaosConquest.grant, "pocketboss:<key>"), for world bosses
--               a reduced share of the event reward (orbs, a gear roll of the boss's set, a unique roll), for island
--               bosses orbs plus picks of gear, materials and deck cards (islandReward). The boss passive
--               point comes from bosspoints.lua as for any kill of that type.
--   no stacking a character rewarded by the event of a boss cannot open its pocket for noStackSeconds (event_at in
--               chaos_pocketboss: a restart keeps it)
-- Exports: ChaosPocketBoss.bosses(), .addCharges(player, key, n), .charges(player, key), .view(player), .enter(player,
-- key), .isInside(player), .lootMultOf(monster), .isWorldBoss(monster), .noteEvent(player, key), .actions.
-- Staff: /pocketboss. Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosUberCore then
	dofile("data/scripts/chaos/uber_core.lua")
end
dofile("data/scripts/chaos/pocketboss_core.lua")
Chaos.pocketBossConfig = dofile("data/scripts/chaos/pocketboss_config.lua")
pcall(dofile, "data/lib/chaos_dark_paint.lua")
if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end

ChaosPocketBoss = ChaosPocketBoss or {}
local PB = ChaosPocketBoss
local K = ChaosPocketBossCore
local U = ChaosUberCore
local HUD = ChaosOpcodes.rift
local unpack = table.unpack or unpack

local function C()
	return Chaos.pocketBossConfig
end

local function TABLE()
	return Chaos.tables and Chaos.tables.pocketBoss or C().table
end

local function now()
	return os.time()
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos pocket bosses] " .. text)
end

local function try(name, fn, ...)
	local ok, res, b = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res, b
end

-- a reason from the core ({key, args...}) in the player's language
local function say(player, why)
	if type(why) ~= "table" then
		return tostring(why or "")
	end
	return Chaos.t(player, why[1], unpack(why, 2))
end

PB.runs = PB.runs or {} -- slot -> run
PB.runOf = PB.runOf or {} -- player id -> run
PB.monsterRun = PB.monsterRun or {} -- monster id -> run
PB.built = PB.built or {}
PB.gates = PB.gates or {} -- slot -> the arena's own way out {x, y, z} (K.arenaGate)
PB.bad = PB.bad or {}
PB.nextId = PB.nextId or 0
PB.rows = PB.rows or {} -- guid -> {key -> row}
PB.lastEnter = PB.lastEnter or {} -- guid -> time
PB.contest = PB.contest or {} -- monster id -> contested fight {key, damage, healing, names, ...}

-- ======================================================================== the list
function PB.index()
	if PB._index then
		return PB._index
	end
	local entries = {}
	if ChaosBossSpawns and ChaosBossSpawns.ensure then
		local idx = try("boss spawns", ChaosBossSpawns.ensure)
		entries = idx and idx.list or {}
	end
	local index = K.list(C(), Chaos.worldBoss, entries)
	-- a type the server does not have (no MonsterType) is left out
	local kept = {list = {}, byKey = {}, byType = index.byType}
	for _, b in ipairs(index.list) do
		if not MonsterType or MonsterType(b.monster) then
			kept.list[#kept.list + 1] = b
			kept.byKey[b.key] = b
		end
	end
	if #entries > 0 or not ChaosBossSpawns then
		PB._index = kept -- the Boss Spawns list is complete once bossspawns.lua ran; until then it is built again
	end
	return kept
end

-- for other modules (the online-time shop): {{key, name, minLevel}}
function PB.bosses()
	local out = {}
	for _, b in ipairs(PB.index().list) do
		out[#out + 1] = {key = b.key, name = b.name, minLevel = b.minLevel}
	end
	return out
end

-- ======================================================================== charges (database)
local tableReady = false
function PB.ensureTable()
	if not tableReady and db and db.query then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE() .. "` (`player_id` int(11) NOT NULL, " ..
			"`boss_key` varchar(48) NOT NULL, `day` int(10) unsigned NOT NULL DEFAULT 0, `used` smallint(5) unsigned NOT NULL DEFAULT 0, " ..
			"`bonus` smallint(5) unsigned NOT NULL DEFAULT 0, `bonus_day` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"`bonus_added` smallint(5) unsigned NOT NULL DEFAULT 0, `kills` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"`event_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`player_id`, `boss_key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true
	end
	return tableReady
end

local function rowsOf(guid)
	local rows = PB.rows[guid]
	if rows then
		return rows
	end
	rows = {}
	if PB.ensureTable() then
		for _, r in ipairs(Chaos.select(string.format("SELECT `boss_key`, `day`, `used`, `bonus`, `bonus_day`, `bonus_added`, `event_at` FROM `%s` " ..
				"WHERE `player_id` = %d", TABLE(), guid), {{"boss_key", "s"}, {"day", "n"}, {"used", "n"}, {"bonus", "n"},
				{"bonus_day", "n"}, {"bonus_added", "n"}, {"event_at", "n"}})) do
			rows[r.boss_key] = {day = r.day, used = r.used, bonus = r.bonus, bonusDay = r.bonus_day, bonusAdded = r.bonus_added,
				eventAt = r.event_at}
		end
	end
	PB.rows[guid] = rows
	return rows
end

-- written at once (a synchronous query): the charge is gone before the player moves
local function saveRow(guid, key, row, kill)
	PB.rows[guid] = PB.rows[guid] or {}
	PB.rows[guid][key] = row
	if not PB.ensureTable() then
		return false
	end
	return db.query(string.format("INSERT INTO `%s` (`player_id`, `boss_key`, `day`, `used`, `bonus`, `bonus_day`, `bonus_added`, `kills`, `event_at`) " ..
		"VALUES (%d, %s, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `day` = VALUES(`day`), `used` = VALUES(`used`), " ..
		"`bonus` = VALUES(`bonus`), `bonus_day` = VALUES(`bonus_day`), `bonus_added` = VALUES(`bonus_added`), `kills` = `kills` + %d, " ..
		"`event_at` = VALUES(`event_at`)",
		TABLE(), guid, db.escapeString(key), row.day or 0, row.used or 0, row.bonus or 0, row.bonusDay or 0, row.bonusAdded or 0,
		kill and 1 or 0, row.eventAt or 0, kill and 1 or 0)) and true or false
end

function PB.charges(player, key)
	return K.charges(C(), rowsOf(player:getGuid())[key], now())
end

-- bonus charges beyond the daily ones (the online-time shop): at most charges.bonusPerDay added per boss and day and
-- charges.bonusMax held. Returns the number added (0 when none) and the reason in English when none was.
function PB.addCharges(player, bossKey, n)
	if not player or not PB.index().byKey[bossKey] then
		return 0, "There is no pocket of that boss."
	end
	local guid = player:getGuid()
	local row, added, why = K.addBonus(C(), rowsOf(guid)[bossKey], n, now())
	if added <= 0 then
		return 0, why and string.format(why[1], unpack(why, 2)) or nil
	end
	saveRow(guid, bossKey, row)
	PB.push(player)
	return added
end

function PB.view(player)
	local guid = player:getGuid()
	local v = K.view(C(), PB.index(), rowsOf(guid), now(), player:getLevel())
	local run = PB.runOf[player:getId()]
	v.inside = run and run.boss.key or nil
	return v
end

-- the Boss Spawns list (bossspawns.lua S.payload): the pocket level on every pocket row, the raid bosses by level and name
function PB.tidy(rows)
	local levels = {}
	for _, b in ipairs(PB.index().list) do
		levels[b.key] = b.minLevel
	end
	return K.tidy(rows, levels, C().sortSpawns or {})
end

-- the Boss Spawns window's pocket data (bossspawns.lua S.payload adds it to the list)
function PB.push(player)
	if ChaosOpcodes.bossSpawns and Chaos.send then
		Chaos.send(player, ChaosOpcodes.bossSpawns, "pocket", PB.view(player))
	end
end

-- ======================================================================== no stacking with the events
-- persisted in chaos_pocketboss.event_at (a restart keeps it)
function PB.noteEvent(player, key)
	local guid = type(player) == "number" and player or (player and player:getGuid())
	if guid and key and PB.index().byKey[key] then
		saveRow(guid, key, K.noteEvent(C(), rowsOf(guid)[key], now()))
	end
end

local function noStackOf(guid, key)
	local row = rowsOf(guid)[key]
	return K.noStackLeft(row and row.eventAt, now(), C().noStackSeconds or 0)
end

-- the world boss event's rewards (worldboss.lua W.deliver): the boss of the event that is closing
local function wrapWorldBoss()
	local W = ChaosWorldBoss
	if not W or not W.deliver or W._pocketWrapped then
		return
	end
	local original = W.deliver
	W._pocketWrapped = true
	W.deliver = function(player, r, ...)
		local idx = W.state and W.state.index
		if player and idx then
			pcall(PB.noteEvent, player, "world_" .. idx)
		end
		return original(player, r, ...)
	end
end

-- ======================================================================== arena slots (uber_core.lua layout)
local function groundIdOf(tile)
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

local function dark()
	local cfg = C()
	if cfg.darkActive ~= nil then
		return cfg.darkActive
	end
	cfg.darkActive = false
	local d = cfg.dark
	if d and d.enabled and ChaosDarkPaint and ChaosDarkTiles and ChaosDarkPaint.ready(d.style) then
		local wall, basin = ChaosDarkTiles.id(d.wall), ChaosDarkTiles.id(d.basin)
		if wall and basin then
			cfg.wallId, cfg.basinId, cfg.darkActive = wall, basin, true
		end
	end
	return cfg.darkActive
end

-- O276: the look of the arena (arenalook_core.lua): the theme of the boss, varied ground, mirrored cover and lights that
-- leave the lane from the entry to the boss, the arrival and the boss spot open. Repainted when the theme changes (a
-- slot serves many bosses); the fixtures are placed after it.
local function dressSlot(L, bossKey, arenaGate)
	local cfg = C()
	ChaosArenaLook.dressBossArena("pocket", L, cfg, bossKey, arenaGate)
	for _, t in ipairs(L.basins) do
		placeItem(P(t), cfg.basinId)
	end
end

local function buildSlot(slot, bossKey)
	local cfg = C()
	local isDark = dark()
	local L = U.layout(cfg, slot)
	if PB.built[slot] then
		L.arenaGate = PB.gates[slot]
		dressSlot(L, bossKey, L.arenaGate)
		return L
	end
	if PB.bad[slot] then
		return nil, PB.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local lists = {L.floorList, L.anteList, L.wallList}
	for _, list in ipairs(lists) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			local gid = tile and groundIdOf(tile)
			if tile and ((gid ~= cfg.groundId and not (isDark and ChaosDarkPaint.isDark(gid)) and not ChaosArenaLook.isOwned(gid)) or (tile.getHouse and tile:getHouse())) then
				return nil, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
			end
		end
	end
	for _, list in ipairs(lists) do
		for _, t in ipairs(list) do
			local pos = P(t)
			local tile = Tile(pos) or Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(cfg.groundId, 1, pos)
			end
		end
	end
	for _, t in ipairs(L.wallList) do
		placeItem(P(t), cfg.wallId)
	end
	-- a second way out inside the arena, next to where the players arrive (beta 2026-10-20: a player was stuck at the
	-- boss with the exit in the antechamber; closed boss rooms always get a portal). Chosen before the paint and kept
	-- free of decoration (K.arenaGate; it was placed after the paint, on whatever the paint put there).
	local taken = {[L.bossSpawn.x .. "," .. L.bossSpawn.y] = true, [L.portal.x .. "," .. L.portal.y] = true}
	for _, b in ipairs(L.basins) do
		taken[b.x .. "," .. b.y] = true
	end
	for _, st in ipairs(L.starts or {}) do
		taken[st.x .. "," .. st.y] = true
	end
	local best = K.arenaGate(L.floorList, (L.starts and L.starts[1]) or L.entry, taken)
	L.arenaGate = best
	dressSlot(L, bossKey, best)
	local gate = placeItem(P(L.portal), cfg.portalId)
	if gate then
		gate:setActionId(cfg.portalActionId)
	end
	if best then
		local arenaGate = placeItem(P(best), cfg.portalId)
		if arenaGate then
			arenaGate:setActionId(cfg.portalActionId)
		end
	end
	PB.built[slot] = true
	PB.gates[slot] = best
	return L
end

local function cleanSlot(L)
	local cfg = C()
	local keep = {[cfg.groundId] = true, [cfg.wallId] = true, [cfg.basinId] = true, [cfg.portalId] = true}
	for _, list in ipairs({L.floorList, L.anteList}) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						PB.monsterRun[c:getId()] = nil
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					local id = item:getId()
					if not keep[id] and not (cfg.darkActive and ChaosDarkPaint and ChaosDarkPaint.isDark(id)) and not ChaosArenaLook.isOwned(id) then
						item:remove()
					end
				end
			end
		end
	end
end

local function takeSlot(bossKey)
	local cfg = C()
	while true do
		local slot = U.allocSlot(cfg, PB.runs, PB.bad)
		if not slot then
			return nil
		end
		local L, why = buildSlot(slot, bossKey)
		if L then
			return slot, L
		end
		PB.bad[slot] = why
		log(string.format("slot %d not usable: %s", slot, tostring(why)))
	end
end

-- a monster of a pocket: created by it, or standing in the pocket grid (adds of boss mechanics)
function PB.isPocketMonster(monster)
	if not monster then
		return nil
	end
	local run = PB.monsterRun[monster:getId()]
	if run then
		return run
	end
	local ok, pos = pcall(function() return monster:getPosition() end)
	local slot = ok and U.slotAt(C(), pos)
	return slot and PB.runs[slot] or nil
end

-- loot.lua: the corpse of a pocket monster x lootMult (1 elsewhere)
function PB.lootMultOf(monster)
	local run = PB.isPocketMonster(monster)
	return run and run.settings.lootMult or 1
end

-- loot.lua: a pocket world boss drops at the world boss item level
function PB.isWorldBoss(monster)
	local run = PB.isPocketMonster(monster)
	return run ~= nil and run.boss.category == "world" and run.bossId == monster:getId()
end

-- ======================================================================== the run
local function tell(run, text, ...)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, text, ...))
		end
	end
end

local function bossOf(run)
	return run.bossId and Monster(run.bossId) or nil
end

local function timeLeft(run, t)
	local limit = (run.settings.minutes or 10) * 60
	if run.bossAt then
		return math.max(0, math.floor(limit - (t - run.bossAt) / 1000))
	end
	return limit + math.max(0, math.ceil(((run.bossDueAt or t) - t) / 1000))
end
PB.timeLeft = timeLeft

local function hudData(run)
	local limit = (run.settings.minutes or 10) * 60
	local boss = bossOf(run)
	local notes = {}
	if run.state == "running" and boss then
		notes[#notes + 1] = string.format("Health: %d%%", math.floor(boss:getHealth() * 100 / math.max(1, boss:getMaxHealth())))
	end
	notes[#notes + 1] = string.format("Pocket: %d%% experience, %d%% loot", math.floor(run.settings.xpMult * 100 + 0.5),
		math.floor(run.settings.lootMult * 100 + 0.5))
	return {tier = 0, theme = run.boss.name, left = timeLeft(run, mnow()), limit = limit, total = 0, killed = 0, bossAt = 0,
		boss = run.bossState, state = run.state, bossName = run.boss.name, mods = {}, notes = notes,
		title = "Pocket: " .. run.boss.name}
end

local function sendHud(run, action, player)
	if not HUD or not Chaos.send then
		return
	end
	local data = hudData(run)
	if player then
		Chaos.send(player, HUD, action, data)
		return
	end
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			Chaos.send(p, HUD, action, data)
		end
	end
end

local function eventsOn(player)
	player:registerEvent("ChaosPocketBossPlayerHit")
	player:registerEvent("ChaosPocketBossPrepareDeath")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosPocketBossPlayerHit")
	player:unregisterEvent("ChaosPocketBossPrepareDeath")
end

local finishExit

local function removePlayer(run, id, mode)
	local entry = run.players[id]
	if not entry then
		return
	end
	run.players[id] = nil
	PB.runOf[id] = nil
	local player = Player(id)
	if player then
		eventsOff(player)
		if mode ~= "stay" and mode ~= "logout" then
			local dest = entry.entry and P(entry.entry) or player:getTown():getTemplePosition()
			player:teleportTo(dest)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		player:removeCondition(CONDITION_INFIGHT)
		if mode ~= "logout" and HUD and Chaos.send then
			local running = run.state == "running"
			Chaos.send(player, HUD, "end", {result = running and "left" or run.state,
				text = running and "You left the pocket." or (run.endText or "")})
		end
		PB.push(player)
	end
	if next(run.players) == nil and not run.ended then
		if run.state == "running" then
			run.state = "failed"
			run.endText = "Everyone left the pocket."
		end
		finishExit(run)
	end
end

local function removeMonsters(run)
	for mid, r in pairs(PB.monsterRun) do
		if r == run then
			PB.monsterRun[mid] = nil
			local m = Monster(mid)
			if m then
				m:remove()
			end
		end
	end
end

finishExit = function(run)
	if run.ended then
		return
	end
	run.ended = true
	for id in pairs(run.players) do
		removePlayer(run, id, "out")
	end
	removeMonsters(run)
	cleanSlot(run.L)
	if PB.runs[run.slot] == run then
		PB.runs[run.slot] = nil
		if ChaosInstanceLimits and not run.restart then
			ChaosInstanceLimits.freed("pocketboss", "the pocket boss arenas")
		end
	end
	log(string.format("run %d (%s, slot %d, %d player(s)) ended: %s", run.id, run.boss.key, run.slot, run.size, run.state))
end

local function fail(run, text, ...)
	if run.ended or run.state ~= "running" then
		return
	end
	run.state = "failed"
	tell(run, text, ...)
	run.endText = "The pocket closes."
	sendHud(run, "update")
	finishExit(run)
end
PB._fail = fail

-- a server shutdown: the open pockets close and (refundOnRestart) their charges come back
function PB.interruptAll()
	for _, run in pairs(PB.runs) do
		if not run.ended then
			run.restart = true
			if run.state == "running" and C().refundOnRestart then
				for _, e in pairs(run.spent) do
					local rows = rowsOf(e.guid)
					saveRow(e.guid, run.boss.key, K.refund(C(), rows[run.boss.key], e.kind, now()))
				end
				run.spent = {}
				run.state = "interrupted"
				run.endText = "The server is restarting: the pocket closes and your charge is given back."
				tell(run, run.endText)
			end
			finishExit(run)
		end
	end
end

local function serverClosing()
	local state = Game.getGameState and Game.getGameState()
	return state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED)
end

-- ======================================================================== rewards
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
	if player:addItemEx(item, false) == (RETURNVALUE_NOERROR or 0) then
		return false
	end
	local inbox = player:getInbox()
	if inbox then
		inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	return true
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

local function worldRewardOf(run, player)
	local wb = Chaos.worldBoss
	local boss = wb and wb.bosses and wb.bosses[run.boss.worldIndex]
	if not boss then
		return
	end
	local pool = ChaosWorldBoss and ChaosWorldBoss.uniquePool and ChaosWorldBoss.uniquePool(boss.name) or {}
	local r = K.worldReward(wb.reward or {}, boss, run.settings.lootMult, pool, math.random, C().worldReward)
	local parts, inboxUsed = {}, false
	for _, it in ipairs(r.items) do
		inboxUsed = giveStack(player, it.id, it.count) or inboxUsed
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	if r.gear then
		local level = ChaosItemMods and ChaosItemMods.sourceLevel and ChaosItemMods.sourceLevel({worldBoss = true}) or nil
		local item = ChaosCrafting and ChaosCrafting.createItem and ChaosCrafting.createItem(r.gear, r.gearRarity or 0, level)
			or Game.createItem(r.gear, 1)
		if item then
			inboxUsed = giveEx(player, item) or inboxUsed
			parts[#parts + 1] = itemName(r.gear)
		end
	end
	if r.unique then
		local item = Game.createItem(r.unique, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			inboxUsed = giveEx(player, item) or inboxUsed
			local e = ChaosUniqueById and ChaosUniqueById[r.unique]
			parts[#parts + 1] = e and e.name or itemName(r.unique)
		end
	end
	if #parts > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Pocket reward of %s: %s.%s", run.boss.name,
			table.concat(parts, ", "), inboxUsed and Chaos.t(player, " Your backpack was full: the rest is in your inbox.") or ""))
	end
end

-- the cards by tier (1 Minor .. 4 Powerful) of cards_config.lua, for the island reward
local function cardsByTier()
	local cfg = ChaosCardsConfig
	if not cfg then
		local ok, loaded = pcall(dofile, "data/scripts/chaos/cards_config.lua")
		cfg = ok and loaded or nil
	end
	local out = {{}, {}, {}, {}}
	for id, c in pairs((cfg or {}).cards or {}) do
		if not c.legendary and out[c.tier] then
			out[c.tier][#out[c.tier] + 1] = id
		end
	end
	for t = 1, 4 do
		table.sort(out[t])
	end
	return out
end

-- the island bosses' reward (pocketboss_config.lua islandReward): orbs, picks of gear of the boss's own loot table,
-- materials and deck cards, for every player present at the kill. Cards were the one sure item of the island loot tables.
local function islandRewardOf(run, player, gearIds, cards)
	local cfg = C().islandReward
	if not cfg or cfg.enabled == false then
		return
	end
	local r = K.islandReward(cfg, run.settings.lootMult or 1, gearIds, cards, math.random)
	local parts, inboxUsed = {}, false
	for _, it in ipairs(r.items) do
		inboxUsed = giveStack(player, it.id, it.count) or inboxUsed
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	for _, g in ipairs(r.gear) do
		local level = run.bossDrop and run.bossDrop.level or nil
		local item = ChaosCrafting and ChaosCrafting.createItem and ChaosCrafting.createItem(g.id, g.rarity or 0, level)
			or Game.createItem(g.id, 1)
		if item then
			inboxUsed = giveEx(player, item) or inboxUsed
			parts[#parts + 1] = itemName(g.id)
		end
	end
	for _, id in ipairs(r.cards) do
		local item = Game.createItem(id, 1)
		if item then
			inboxUsed = giveEx(player, item) or inboxUsed
			parts[#parts + 1] = itemName(id)
		end
	end
	if #parts > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Pocket reward of %s: %s.%s", run.boss.name,
			table.concat(parts, ", "), inboxUsed and Chaos.t(player, " Your backpack was full: the rest is in your inbox.") or ""))
	end
end

-- the boss's loot when its corpse had none (K.needsFallbackLoot: a reward boss whose loot goes to the reward chest of
-- its home room, or an empty corpse): every player of the run gets a personal roll of its loot table x lootMult, gear
-- with the stock rarity roll and the boss floor of the loot layer, at the kill's item level. Returns the players served.
local function fallbackLoot(run)
	local d = run.bossDrop
	if not d or not K.needsFallbackLoot(d) then
		return 0
	end
	local given = 0
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			local parts, inboxUsed = {}, false
			for _, it in ipairs(K.personalRoll(d.loot, run.settings.lootMult or 1, math.random)) do
				local isGear = ChaosLoot and ChaosLoot.isGearId and ChaosLoot.isGearId(it.id)
				if isGear and ChaosCrafting and ChaosCrafting.createItem then
					local rarity = ChaosLoot.stockRarity and ChaosLoot.stockRarity() or 0
					if ChaosLoot.upgradeRarity then
						rarity = ChaosLoot.upgradeRarity("boss", rarity, 1)
					end
					local item = ChaosCrafting.createItem(it.id, rarity, d.level)
					if item then
						inboxUsed = giveEx(p, item) or inboxUsed
					end
				else
					inboxUsed = giveStack(p, it.id, it.count) or inboxUsed
				end
				parts[#parts + 1] = (it.count > 1 and (it.count .. "x ") or "") .. itemName(it.id)
			end
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "Pocket loot of %s: %s.%s", run.boss.name,
				#parts > 0 and table.concat(parts, ", ") or Chaos.t(p, "nothing this time"),
				inboxUsed and Chaos.t(p, " Your backpack was full: the rest is in your inbox.") or ""))
			given = given + 1
		end
	end
	log(string.format("%s: no corpse loot (reward boss %s, %s items), personal loot for %d player(s)", run.boss.key,
		tostring(d.rewardBoss), tostring(d.corpseItems), given))
	return given
end

-- a way out that the boss's own death script opened in the pocket (the stairs or teleport of its home room, which lead
-- nowhere here): every item on such a tile goes, except the ground (a floor-change ground becomes the arena's ground)
-- and the corpse. The pocket's two forcefields stay. Returns the tiles cleaned.
local function clearForeignExits(run)
	local cfg = C()
	local L = run.L
	local gates = {[L.portal.x .. "," .. L.portal.y] = true}
	if L.arenaGate then
		gates[L.arenaGate.x .. "," .. L.arenaGate.y] = true
	end
	local tiles = {}
	for _, list in ipairs({L.floorList, L.anteList}) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			if tile and ((TILESTATE_TELEPORT and tile:hasFlag(TILESTATE_TELEPORT))
					or (TILESTATE_FLOORCHANGE and tile:hasFlag(TILESTATE_FLOORCHANGE))) then
				tiles[#tiles + 1] = {x = t.x, y = t.y, exit = true}
			end
		end
	end
	local cleaned = 0
	for _, t in ipairs(K.foreignExits(tiles, gates)) do
		local pos = P({x = t.x, y = t.y, z = L.z})
		local tile = Tile(pos)
		for _, item in ipairs(tile and tile:getItems() or {}) do
			if not item:isContainer() then
				item:remove()
			end
		end
		if tile and TILESTATE_FLOORCHANGE and tile:hasFlag(TILESTATE_FLOORCHANGE) then
			Game.createItem(cfg.groundId, 1, pos)
		end
		cleaned = cleaned + 1
	end
	if cleaned > 0 then
		log(string.format("%s: %d way(s) out of its home room taken away", run.boss.key, cleaned))
	end
	return cleaned
end
PB.clearForeignExits = clearForeignExits

-- the boss's corpse once the engine dropped its loot (onDeath runs before the loot goes in, so the size read there is 0
-- for every corpse): a container's real item count goes to bossDrop.corpseItems; a corpse that is no container (beta
-- 2026-10-22, Weakened Slurgoth: its corpse is a ramp item that holds nothing and looks like a way down) is taken away,
-- and the run gets the personal roll (K.needsFallbackLoot: no corpse). Returns "container", "removed" or nil.
local function settleCorpse(run)
	local d = run.bossDrop
	if not d or not d.corpsePos or not d.corpseId then
		return nil
	end
	local tile = Tile(P(d.corpsePos))
	local item = tile and tile.getItemById and tile:getItemById(d.corpseId)
	if not item then
		return nil
	end
	if item:isContainer() then
		local okS, size = pcall(function() return item:getSize() end)
		if okS and tonumber(size) then
			d.corpseItems = tonumber(size)
		end
		return "container"
	end
	item:remove()
	d.corpseItems = nil
	log(string.format("%s: its corpse (item %d) holds no loot: taken away", run.boss.key, d.corpseId))
	return "removed"
end
PB.settleCorpse = settleCorpse

local function success(run)
	run.state = "success"
	run.bossState = "dead"
	local secs = math.max(1, math.floor((mnow() - (run.bossAt or mnow())) / 1000))
	local tokens = math.max(0, math.floor(run.settings.tokens or 0))
	for id, e in pairs(run.players) do
		local p = Player(id)
		if p then
			saveRow(e.guid, run.boss.key, rowsOf(e.guid)[run.boss.key] or K.charges(C(), nil, now()), true)
			if ChaosMetrics and ChaosMetrics.firstUse then -- funnel metrics (metrics.lua, O258)
				pcall(ChaosMetrics.firstUse, p, "pocketboss")
			end
			if tokens > 0 and ChaosConquest and ChaosConquest.grant then
				pcall(ChaosConquest.grant, p, "pocketboss:" .. run.boss.key, tokens)
			end
			if run.boss.category == "world" then
				try("world reward", worldRewardOf, run, p)
			end
		end
	end
	if run.boss.category == "island" then
		local gearIds, seenGear = {}, {}
		for _, e in ipairs(run.bossDrop and run.bossDrop.loot or {}) do
			local gid = tonumber(e.itemId or e.id)
			if gid and not seenGear[gid] and ChaosLoot and ChaosLoot.isGearId and ChaosLoot.isGearId(gid) then
				seenGear[gid] = true
				gearIds[#gearIds + 1] = gid
			end
		end
		local cards = cardsByTier()
		for id in pairs(run.players) do
			local p = Player(id)
			if p then
				try("island reward", islandRewardOf, run, p, gearIds, cards)
			end
		end
	end
	try("corpse", settleCorpse, run)
	if run.boss.category ~= "world" then
		try("fallback loot", fallbackLoot, run)
	end
	-- the boss's own death script may open its home room's way on now or a moment later: taken away at once and again
	local slot0, rid0 = run.slot, run.id
	try("foreign exits", clearForeignExits, run)
	for _, ms in ipairs({1000, 5000}) do
		addEvent(function()
			local r = PB.runs[slot0]
			if r and r.id == rid0 then
				try("foreign exits", clearForeignExits, r)
			end
		end, ms)
	end
	tell(run, "%s falls in %s. The pocket closes in %d seconds: loot the corpse, or leave now through the forcefield by the arrival.",
		run.boss.name, K.clockText(secs), C().exitDelay)
	sendHud(run, "update")
	local slot, rid = run.slot, run.id
	addEvent(function()
		local r = PB.runs[slot]
		if r and r.id == rid then
			finishExit(r)
		end
	end, C().exitDelay * 1000)
end

-- ======================================================================== the fight
local function arenaPlayers(run)
	local out = {}
	for id, e in pairs(run.players) do
		local p = Player(id)
		if p and U.inArena(run.L, p:getPosition()) then
			out[#out + 1] = p
		end
	end
	return out
end

local function setHealth(monster, hp)
	hp = math.max(1, math.floor(hp))
	monster:setMaxHealth(hp)
	monster:addHealth(hp - monster:getHealth())
end

local function spawnBoss(run)
	PB.creating = true
	-- O177: created with the level the pocket is tuned for / its drops use (Chaos.spawnLevel, shown after the name), not
	-- the experience / health estimate of the species ("Lv 10182" on a world boss type)
	local level = K.bossLevel(run.boss, ChaosLoot and ChaosLoot.typeLevel and Chaos.huntingLevel(ChaosLoot.typeLevel(run.boss.monster)),
		ChaosMonsterLevelsCore and ChaosMonsterLevelsCore.maxEstimate)
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	local ok, m = pcall(create, run.boss.monster, P(run.L.bossSpawn), false, true, nil, level)
	PB.creating = false
	if not ok or not m then
		log("cannot create " .. tostring(run.boss.monster) .. ": " .. tostring(m))
		-- the boss did not come: the charges go back
		for _, e in pairs(run.spent) do
			saveRow(e.guid, run.boss.key, K.refund(C(), rowsOf(e.guid)[run.boss.key], e.kind, now()))
		end
		run.spent = {}
		fail(run, "The boss did not answer; your charge is given back.")
		return
	end
	PB.monsterRun[m:getId()] = run
	run.bossId = m:getId()
	if ChaosBossMech and ChaosBossMech.attach then
		local rid, slot = run.id, run.slot
		pcall(ChaosBossMech.attach, m, nil, {tiles = run.L.floorList, size = run.size, solo = run.size == 1,
			players = function()
				local r = PB.runs[slot]
				return (r and r.id == rid) and arenaPlayers(r) or {}
			end})
	end
	setHealth(m, m:getMaxHealth() * K.scale(run.settings.health, run.size))
	m:registerEvent("ChaosPocketBossDeath")
	run.bossState = "alive"
	run.bossAt = mnow()
	tell(run, "%s appears. You have %d minutes.", run.boss.name, run.settings.minutes or 10)
	sendHud(run, "update")
end

local function tick(slot, rid)
	local run = PB.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local cfg = C()
	local t = mnow()
	for id, e in pairs(run.players) do
		local p = Player(id)
		if not p then
			removePlayer(run, id, "logout")
		else
			local pos = p:getPosition()
			if not U.inArena(run.L, pos) and not U.inAnte(run.L, pos) then
				removePlayer(run, id, "stay")
			end
		end
	end
	if run.ended or PB.runs[slot] ~= run then
		return
	end
	if Chaos.sweepDue and Chaos.sweepDue(run, t) then
		Chaos.sweepIntruders(function(pos) return U.slotAt(cfg, pos) == slot end,
			function(p) return run.players[p:getId()] ~= nil end, "This pocket is not yours: you were sent to your temple.")
	end
	if run.state == "running" and run.bossState == "waiting" and t >= (run.bossDueAt or 0) then
		spawnBoss(run)
	end
	if run.ended then
		return
	end
	if run.state == "running" and run.bossState == "alive" then
		if timeLeft(run, t) <= 0 then
			fail(run, "Time is up: %s still stands.", run.boss.name)
			return
		end
		local boss = bossOf(run)
		if boss and not boss:getTarget() and #arenaPlayers(run) == 0 then
			boss:teleportTo(P(run.L.bossSpawn))
		end
		if ChaosInstanceLimits then
			ChaosInstanceLimits.warn(run, timeLeft(run, t), ChaosInstanceLimits.playersOf(run.players), run.boss.name, cfg.limits)
		end
	end
	if t >= (run.nextHud or 0) then
		run.nextHud = t + (cfg.hudEvery or 2) * 1000
		sendHud(run, "update")
	end
	addEvent(tick, cfg.tickMs or 500, slot, rid)
end
PB._tick = tick

-- ======================================================================== entering
local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function instanceOf(player)
	if PB.runOf[player:getId()] then
		return "a pocket"
	end
	local _, label = Chaos.inAnyInstance and Chaos.inAnyInstance(player, "pocketboss")
	return label
end

local function partyOf(player)
	local party = player:getParty()
	if not party then
		return {player}
	end
	local out = {party:getLeader()}
	for _, m in ipairs(party:getMembers() or {}) do
		out[#out + 1] = m
	end
	return out
end

function PB.enter(player, key)
	local cfg = C()
	local boss = PB.index().byKey[key]
	local guid = player:getGuid()
	local t = now()
	local last = PB.lastEnter[guid] or 0
	local info = {enabled = cfg.enabled, boss = boss, level = player:getLevel(), needPz = cfg.needProtectionZone,
		pz = inProtectionZone(player), inFight = inCombat(player), instance = instanceOf(player),
		cooldown = math.max(0, last + (cfg.enterCooldown or 0) - t)}
	if boss then
		info.charges = K.charges(cfg, rowsOf(guid)[key], t)
		info.noStack = noStackOf(guid, key)
		info.reset = K.nextReset(t, (cfg.charges or {}).resetHour)
	end
	local why = K.enterError(info)
	if why then
		return false, say(player, why)
	end
	-- the party members near the opener (each spends a charge); the others stay behind and are told why
	local group, left = {player}, {}
	local from = player:getPosition()
	local range = (cfg.party or {}).range or 8
	for _, m in ipairs(partyOf(player)) do
		if m:getId() ~= player:getId() then
			local mp = m:getPosition()
			local mg = m:getGuid()
			local mwhy = #group >= ((cfg.party or {}).max or 5) and K.T("the pocket is full") or K.memberError({boss = boss,
				level = m:getLevel(), instance = instanceOf(m), inFight = inCombat(m),
				far = mp.z ~= from.z or math.max(math.abs(mp.x - from.x), math.abs(mp.y - from.y)) > range,
				noStack = noStackOf(mg, key), charges = K.charges(cfg, rowsOf(mg)[key], t)})
			if mwhy then
				left[#left + 1] = {player = m, why = mwhy}
			else
				group[#group + 1] = m
			end
		end
	end
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(PB.runs) do
		running = running + 1
	end
	local slot, L
	if not (IL and IL.capped("pocketboss", running, cfg.limits)) then
		slot, L = takeSlot(tostring((boss and (boss.name or boss.monster)) or key))
	end
	if not slot then
		if IL then
			local lefts, mt = {}, mnow()
			for _, r in pairs(PB.runs) do
				lefts[#lefts + 1] = r.state == "running" and timeLeft(r, mt) or cfg.exitDelay
			end
			return false, IL.busy(player, "pocketboss", "pocket boss arenas", lefts, cfg.limits)
		end
		return false, Chaos.t(player, "Every pocket arena is in use. Try again in a moment.")
	end
	-- the charges: spent and written before anyone moves
	local spent = {}
	for _, m in ipairs(group) do
		local mg = m:getGuid()
		local row, kind = K.spend(cfg, rowsOf(mg)[key], t)
		if kind then
			saveRow(mg, key, row)
			spent[m:getId()] = {guid = mg, kind = kind}
		end
	end
	cleanSlot(L)
	PB.nextId = PB.nextId + 1
	local run = {id = PB.nextId, slot = slot, L = L, boss = boss, settings = boss.settings, players = {}, spent = spent,
		state = "running", bossState = "waiting", size = 0, startedAt = t, bossDueAt = mnow() + (cfg.startDelay or 5) * 1000}
	PB.runs[slot] = run
	for i, m in ipairs(group) do
		if spent[m:getId()] then
			local p = m:getPosition()
			run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), name = m:getName(), entry = {x = p.x, y = p.y, z = p.z}}
			run.size = run.size + 1
			PB.runOf[m:getId()] = run
			PB.lastEnter[m:getGuid()] = t
			eventsOn(m)
			p:sendMagicEffect(CONST_ME_TELEPORT)
			m:teleportTo(P(L.starts[(i - 1) % #L.starts + 1] or L.entry))
			m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
	end
	for _, l in ipairs(left) do
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s stays behind: %s.", l.player:getName(), say(player, l.why)))
		l.player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(l.player, "You stay behind from the pocket of %s: %s.", boss.name,
			say(l.player, l.why)))
	end
	tell(run, "Pocket of %s: it comes in %d seconds. %d%% experience and loot; the way out is in the room to the south.",
		boss.name, cfg.startDelay or 5, math.floor(run.settings.xpMult * 100 + 0.5))
	sendHud(run, "start")
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			PB.push(p)
		end
	end
	log(string.format("%s opened run %d (%s): slot %d, %d player(s)", player:getName(), run.id, key, slot, run.size))
	addEvent(tick, cfg.tickMs or 500, slot, run.id)
	return true
end

function PB.isInside(player)
	return PB.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("pocketboss", {label = "a pocket boss arena", inside = PB.isInside, at = function(pos)
	return U.slotAt(C(), pos) ~= nil
end, runs = function()
	local out = {}
	for slot, run in pairs(PB.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.id, what = string.format("%s, slot %d, %s", run.boss.name, slot, run.state),
			left = run.state == "running" and timeLeft(run, mnow()) or nil, players = n}
	end
	return out
end, close = function(id)
	for _, run in pairs(PB.runs) do
		if run.id == id and not run.ended then
			if run.state == "running" then
				fail(run, "A gamemaster closed the pocket.")
			else
				finishExit(run)
			end
			return true, "Pocket run " .. id .. " closed."
		end
	end
	return false, "No pocket run " .. tostring(id) .. "."
end})

-- a lethal hit: out, healed, no death; the charge stays spent
local function fall(run, pid)
	local p = Player(pid)
	if not p or not run.players[pid] then
		return
	end
	Chaos.heal(p, p:getMaxHealth() - p:getHealth())
	tell(run, "%s falls and is carried out of the pocket.", p:getName())
	removePlayer(run, pid, "out")
end

-- ======================================================================== protocol (bossspawns.lua routes the pocket* actions)
local function limited(player)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, "pocketboss", C().requestMs or 1000)
end

PB.actions = {
	pocketEnter = function(player, data)
		if limited(player) then
			return
		end
		local key = type(data) == "table" and data.k or nil
		if type(key) ~= "string" or #key > 48 then
			return
		end
		local ok, text = PB.enter(player, key)
		if not ok and text then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, text)
			if Chaos.send then
				Chaos.send(player, ChaosOpcodes.bossSpawns, "pocketError", {text = text})
			end
		end
	end,
	pocketLeave = function(player)
		if limited(player) then
			return
		end
		local run = PB.runOf[player:getId()]
		if run then
			removePlayer(run, player:getId(), "out")
		end
	end,
	pocketInfo = function(player)
		if limited(player) then
			return
		end
		PB.push(player)
	end
}

-- ======================================================================== events
local gate = MoveEvent()
function gate.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local run = PB.runOf[player:getId()]
	if run then
		removePlayer(run, player:getId(), "out")
	else
		player:teleportTo(player:getTown():getTemplePosition())
	end
	return true
end
gate:type("stepin")
gate:aid(C().portalActionId)
gate:register()

local bossDeath = CreatureEvent("ChaosPocketBossDeath")
function bossDeath.onDeath(creature, corpse)
	local run = PB.monsterRun[creature:getId()]
	if run and run.bossId == creature:getId() and run.state == "running" and not run.ended then
		-- the corpse: the engine drops the loot into it after this event, so success() (one tick later) reads its size
		-- again by its position and id (settleCorpse). An empty one, no container or a reward boss gets the personal
		-- roll in success() (K.needsFallbackLoot)
		local mt = creature:getType()
		local okR, reward = pcall(function() return mt and mt.isRewardBoss and mt:isRewardBoss() end)
		local okL, loot = pcall(function() return mt and mt:getLoot() end)
		local okC, size = pcall(function() return corpse and corpse:isContainer() and corpse:getSize() or nil end)
		local okV, level = pcall(function() return ChaosLoot and ChaosLoot.dropLevel and ChaosLoot.dropLevel(creature, nil, "boss") end)
		run.bossDrop = {rewardBoss = okR and reward == true, corpseItems = okC and size or nil,
			loot = okL and type(loot) == "table" and loot or {}, level = okV and tonumber(level) or nil}
		run.bossDrop.lootEntries = #run.bossDrop.loot
		local okP, cpos = pcall(function() return corpse and corpse:getPosition() end)
		local okI, cid = pcall(function() return corpse and corpse:getId() end)
		if okP and cpos and cpos.x then
			run.bossDrop.corpsePos = {x = cpos.x, y = cpos.y, z = cpos.z}
		end
		run.bossDrop.corpseId = okI and tonumber(cid) or nil
		local slot, rid = run.slot, run.id
		addEvent(function()
			local r = PB.runs[slot]
			if r and r.id == rid and r.state == "running" and not r.ended then
				success(r)
			end
		end, 0)
	end
	-- kept until the run ends: loot.lua reads the loot factor in onDropLoot after this
	return true
end
bossDeath:register()

-- the damage curve of a pocket monster's hit on a player of its run; nil for any other hit
local function pocketHitMult(creature, attacker)
	local run = PB.runOf[creature:getId()]
	if not run or run.state ~= "running" or not attacker or not attacker:isMonster()
		or PB.isPocketMonster(attacker) ~= run then
		return nil
	end
	return K.scale(run.settings.damage, run.size)
end

-- the hits of the pocket's monsters x the damage curve; a lethal hit is caught (catchLethal). A hit a mana shield took
-- was scaled by the mana event already (manashield.lua): the rest is left as it is.
local playerHit = CreatureEvent("ChaosPocketBossPlayerHit")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local run = PB.runOf[creature:getId()]
	if not run or run.state ~= "running" or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local mult = pocketHitMult(creature, attacker)
	if mult and not (ChaosManaShield and ChaosManaShield.scaled(creature, attacker, "pocketboss")) then
		primaryDamage = math.floor(primaryDamage * mult)
		if secondaryType ~= COMBAT_HEALING then
			secondaryDamage = math.floor(secondaryDamage * mult)
		end
	end
	if C().catchLethal then
		local sign = primaryDamage < 0 and -1 or 1
		local pool = creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)
		local healSecondary = secondaryType == COMBAT_HEALING
		local p, s, caught = U.catchDamage(pool, primaryDamage, healSecondary and 0 or secondaryDamage)
		if caught then
			local slot, rid, pid = run.slot, run.id, creature:getId()
			addEvent(function()
				local r = PB.runs[slot]
				if r and r.id == rid then
					fall(r, pid)
				end
			end, 0)
		end
		return sign * p, primaryType, healSecondary and secondaryDamage or sign * s, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
playerHit:register()

-- the mana shield part of the hit (manashield.lua): the same damage curve
if not ChaosManaShield or not ChaosManaShield.provide then
	dofile("data/scripts/chaos/manashield_core.lua")
end
ChaosManaShield.provide("pocketboss", {
	hit = function(player, attacker, amount)
		local mult = pocketHitMult(player, attacker)
		return mult and math.floor(amount * mult) or nil
	end
})

local prepare = CreatureEvent("ChaosPocketBossPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local run = PB.runOf[creature:getId()]
	if not run or not C().catchLethal then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	local slot, rid, pid = run.slot, run.id, creature:getId()
	addEvent(function()
		local r = PB.runs[slot]
		if r and r.id == rid then
			fall(r, pid)
		end
	end, 0)
	return false
end
prepare:register()

-- experience of a pocket monster x xpMult (after the pack combat recorder, before the bonuses)
local xpCb = EventCallback
xpCb.onGainExperience = function(player, source, exp, rawExp)
	if not source or not source.isMonster or not source:isMonster() or next(PB.runs) == nil then
		return exp
	end
	local run = PB.isPocketMonster(source)
	if not run then
		return exp
	end
	return K.scaleExp(exp, run.settings.xpMult or 1)
end
xpCb:register(-5)

-- ======================================================================== the contested fights: personal loot
-- island and raid bosses spawned by the base server (not by a pocket): damage on the boss and healing on the players
-- fighting it near it are counted; at the death every other helper above contested.minPercent gets a personal roll
local function contestCfg()
	return C().contested or {}
end

local contestTypes
local function contestType(name)
	if not contestTypes then
		contestTypes = {}
		local cats = contestCfg().categories or {}
		for _, b in ipairs(PB.index().list) do
			if cats[b.category] and b.monster then
				contestTypes[b.monster:lower()] = true
			end
		end
		if not PB._index then
			local t = contestTypes
			contestTypes = nil
			return t[name] or false
		end
	end
	return contestTypes[name] or false
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

-- the fight of a contested boss, made at its first hit (its place decides: an island or raid spawn, not a lair one)
local function contestOf(creature)
	local id = creature:getId()
	local c = PB.contest[id]
	if c ~= nil then
		return c or nil
	end
	PB.contest[id] = false
	local S, BK = ChaosBossSpawns, ChaosBossSpawnsCore
	if not (S and S.ensure and BK and BK.match) then
		return nil
	end
	local p = creature:getPosition()
	local cats = contestCfg().categories or {}
	local idx = S.ensure()
	for _, e in ipairs(BK.match(idx, {type = Chaos.monsterTypeName(creature), shown = creature:getName(),
			pos = {x = p.x, y = p.y, z = p.z}}, Chaos.bossSpawnsConfig and Chaos.bossSpawnsConfig.radius or 40)) do
		if cats[e.category] and PB.index().byKey[e.key] then
			c = {key = e.key, name = e.name, damage = {}, healing = {}, names = {}, maxHealth = creature:getMaxHealth(), scanAt = 0}
			PB.contest[id] = c
			return c
		end
	end
	return nil
end

local contestHealth = CreatureEvent("ChaosPocketContestHealth")
function contestHealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING then
		local p = playerOf(attacker)
		local c = p and contestOf(creature)
		if c then
			local guid = p:getGuid()
			local amount = math.abs(primaryDamage or 0) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage or 0) or 0)
			c.damage[guid] = (c.damage[guid] or 0) + math.min(amount, creature:getHealth())
			c.names[guid] = p:getName()
			-- the players near the boss get the healing counter (registered again every scanSeconds)
			local t = now()
			if t >= c.scanAt then
				c.scanAt = t + (contestCfg().scanSeconds or 3)
				local r = contestCfg().healRange or 10
				for _, s in ipairs(Game.getSpectators(creature:getPosition(), false, true, r, r, r, r) or {}) do
					s:registerEvent("ChaosPocketContestHeal")
				end
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
contestHealth:register()

-- healing on a player who fights a contested boss nearby (it is in the boss's damage list), capped at the missing health
local contestHeal = CreatureEvent("ChaosPocketContestHeal")
function contestHeal.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING and next(PB.contest) ~= nil then
		local healer = playerOf(attacker)
		if healer and healer:getId() ~= creature:getId() then
			local target = creature:getGuid()
			local pos = creature:getPosition()
			local r = contestCfg().healRange or 10
			local amount = math.min(math.abs(primaryDamage or 0), math.max(0, creature:getMaxHealth() - creature:getHealth()))
			for mid, c in pairs(PB.contest) do
				if c and c.damage[target] and amount > 0 then
					local m = Monster(mid)
					local mp = m and m:getPosition()
					if mp and mp.z == pos.z and math.abs(mp.x - pos.x) <= r and math.abs(mp.y - pos.y) <= r then
						local guid = healer:getGuid()
						c.healing[guid] = (c.healing[guid] or 0) + amount
						c.names[guid] = healer:getName()
					end
				end
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
contestHeal:register()

function PB.contestDeath(creature, corpse, mostDamageKiller)
	local id = creature:getId()
	local c = PB.contest[id]
	PB.contest[id] = nil
	if not c then
		return 0
	end
	local cc = contestCfg()
	local owner = corpse and corpse.getCorpseOwner and Player(corpse:getCorpseOwner()) or playerOf(mostDamageKiller)
	local ownerGuid = owner and owner:getGuid() or nil
	if owner then
		PB.noteEvent(owner, c.key)
	end
	local stats = {}
	for guid, d in pairs(c.damage) do
		stats[guid] = {name = c.names[guid], damage = d, healing = c.healing[guid] or 0}
	end
	for guid, h in pairs(c.healing) do
		if not stats[guid] then
			stats[guid] = {name = c.names[guid], damage = 0, healing = h}
		end
	end
	local list = K.contestEligible(stats, c.maxHealth, cc, ownerGuid)
	local mt = creature:getType()
	local loot = mt and mt.getLoot and mt:getLoot() or {}
	local given = 0
	for _, e in ipairs(list) do
		local p = e.name and Player(e.name)
		if p and p:getGuid() == e.guid then
			PB.noteEvent(p, c.key)
			local parts, inboxUsed = {}, false
			for _, it in ipairs(K.personalRoll(loot, cc.lootMult or 1, math.random)) do
				local isGear = ChaosLoot and ChaosLoot.isGearId and ChaosLoot.isGearId(it.id)
				if isGear and ChaosCrafting and ChaosCrafting.createItem then
					local rarity = ChaosLoot.stockRarity and ChaosLoot.stockRarity() or 0
					local level = ChaosLoot.dropLevel and select(2, pcall(ChaosLoot.dropLevel, creature, p, "boss")) or nil
					local item = ChaosCrafting.createItem(it.id, rarity, tonumber(level))
					if item then
						inboxUsed = giveEx(p, item) or inboxUsed
					end
				else
					inboxUsed = giveStack(p, it.id, it.count) or inboxUsed
				end
				parts[#parts + 1] = (it.count > 1 and (it.count .. "x ") or "") .. itemName(it.id)
			end
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "Personal loot of %s (%.1f%% of its health in damage and healing): %s.%s",
				c.name, e.score * 100 / math.max(1, c.maxHealth), #parts > 0 and table.concat(parts, ", ") or Chaos.t(p, "nothing this time"),
				inboxUsed and Chaos.t(p, " Your backpack was full: the rest is in your inbox.") or ""))
			given = given + 1
		end
	end
	return given
end

local contestDeath = CreatureEvent("ChaosPocketContestDeath")
function contestDeath.onDeath(creature, corpse, killer, mostDamageKiller)
	try("personal loot", PB.contestDeath, creature, corpse, mostDamageKiller)
	return true
end
contestDeath:register()

local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	local cc = contestCfg()
	if not C().enabled or not cc.enabled or PB.creating or self:getMaster() then
		return true
	end
	local name = Chaos.monsterTypeName and Chaos.monsterTypeName(self) or self:getName()
	if name and contestType(name:lower()) and not U.slotAt(C(), position) then
		self:registerEvent("ChaosPocketContestHealth")
		self:registerEvent("ChaosPocketContestDeath")
	end
	return true
end
spawn:register()

-- ======================================================================== login, logout, shutdown
local logout = CreatureEvent("ChaosPocketBossLogout")
function logout.onLogout(player)
	if next(PB.runs) ~= nil and serverClosing() then
		PB.interruptAll()
	end
	local run = PB.runOf[player:getId()]
	if run then
		removePlayer(run, player:getId(), "logout")
	end
	PB.rows[player:getGuid()] = nil
	return true
end
logout:register()

local login = CreatureEvent("ChaosPocketBossLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPocketBossLogout")
	wrapWorldBoss()
	-- a character that logs in inside the pocket grid (after a crash, or a logout inside) goes to its temple
	if U.slotAt(C(), player:getPosition()) and not PB.runOf[player:getId()] then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	return true
end
login:type("login")
login:register()

local shutdown = GlobalEvent("ChaosPocketBossShutdown")
function shutdown.onShutdown()
	PB.interruptAll()
	return true
end
shutdown:register()

local startup = GlobalEvent("ChaosPocketBossStartup")
function startup.onStartup()
	PB.ensureTable()
	wrapWorldBoss()
	PB._index = nil
	log(string.format("%d pocket boss(es)", #PB.index().list))
	return true
end
startup:register()

-- ======================================================================== staff: /pocketboss
-- /pocketboss                     the open pockets
-- /pocketboss charges, <name>, <key>, <n>   bonus charges to an online player (as the shop would)
-- /pocketboss reset, <name>       that player's charges of today back
-- /pocketboss end                 your pocket fails
local function onCommand(player, param)
	local args = {}
	for a in (param or ""):gmatch("[^,]+") do
		args[#args + 1] = a:gsub("^%s+", ""):gsub("%s+$", "")
	end
	local cmd = (args[1] or ""):lower()
	if cmd == "charges" then
		local target = Player(args[2] or "")
		if target then
			local n, why = PB.addCharges(target, args[3], tonumber(args[4]) or 1)
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: +%d bonus charge(s) of %s. %s", target:getName(), n,
				tostring(args[3]), why or ""))
		end
	elseif cmd == "reset" then
		local target = Player(args[2] or "")
		if target then
			local guid = target:getGuid()
			for key, row in pairs(rowsOf(guid)) do
				row.used = 0
				saveRow(guid, key, row)
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: today's pocket charges are back.", target:getName()))
		end
	elseif cmd == "end" then
		local run = PB.runOf[player:getId()]
		if run then
			fail(run, "Ended by the staff.")
		end
	else
		local lines = {}
		for slot, r in pairs(PB.runs) do
			local n = 0
			for _ in pairs(r.players) do
				n = n + 1
			end
			lines[#lines + 1] = string.format("slot %d: %s, %s, %d player(s), %ds left", slot, r.boss.name, r.state, n,
				timeLeft(r, mnow()))
		end
		player:showTextDialog(1387, #lines > 0 and table.concat(lines, "\n") or "No pocket is open.")
	end
end

local talk = TalkAction("/pocketboss")
function talk.onSay(player, words, param)
	local g = player:getGroup()
	if not g or g:getId() < C().staffGroup then
		return true
	end
	onCommand(player, param)
	return false
end
talk:separator(" ")
talk:register()

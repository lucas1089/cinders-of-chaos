-- Generated areas (server/README.md "Generated areas"): hunting areas and a dungeon built at startup from a seed, with
-- no map edit. The tile model comes from areagen_core.lua (pure, tests/areagen_test.lua), the palettes and areas from
-- areagen_config.lua. This file only talks to the engine:
--   startup   every enabled area is generated and built with Game.createTile / Game.createItem in its empty part of
--             the map (refused, with a log line, when a tile of its footprint already exists or an item id is
--             missing); the entrance portal goes on the live map (action id aid.entrance, a level gate), the exit
--             portal next to the arrival (aid.exit, back to the entrance or the temple); the spawn points get their
--             monsters; an area with `dungeon` is registered as a base dungeon of the dungeon system (dungeons.lua).
--   monsters  scaled to the area's level (A.levelScale: health at the spawn, damage to players in the health / mana
--             events, experience in an onGainExperience callback); a dead point respawns after its spawntime; while
--             a player sees the spot only under the map spawns' rule (config spawnNearPlayers, engine patch 0041:
--             free non-PZ tile, no player within spawnMinPlayerDistance), else the timer starts again; faster where several
--             hunters fight close together (the dynamic respawn's percent, respawn_core.lua); a monster far from its
--             point and without a target walks back (leash).
-- Staff: /areagen [status | goto <id> | fill <id>].
-- Assumed engine API (TFS 1.4): Game.createTile/createItem/createMonster, Tile, ItemType, Item:setActionId,
-- Creature:setMaxHealth/setHealth/getMonsterLevel/getTarget/teleportTo, Game.getSpectators, MoveEvent stepin by aid,
-- CreatureEvent death/healthchange/manachange/login, EventCallback onGainExperience, GlobalEvent startup/think.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/areagen_core.lua")
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end
if not ChaosDarkTiles then
	dofile("data/lib/chaos_dark_tiles.lua")
end
if not ChaosRespawn or not ChaosRespawn.percentFor then
	dofile("data/scripts/chaos/respawn_core.lua")
end
ChaosAreaGenConfig = dofile("data/scripts/chaos/areagen_config.lua")

ChaosAreaGen = ChaosAreaGen or {}
local AG = ChaosAreaGen
local A = ChaosAreaGenCore
AG.built = AG.built or {} -- area id -> true (tiles stay for the server's lifetime, also over a /reload)
AG.areas = AG.areas or {} -- area id -> {def, model, points, entrance}
AG.scaled = AG.scaled or {} -- monster id -> {damage, experience}
AG.pointOf = AG.pointOf or {} -- monster id -> point

local function C()
	return ChaosAreaGenConfig
end

local function log(text)
	print("[areagen] " .. text)
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

-- the dark tile set is used when every dark item the palettes name is installed
local function darkReady()
	for name in pairs(ChaosDarkTiles.ids) do
		if not ChaosDarkTiles.installed(name) then
			return false
		end
	end
	return true
end

local function itemKnown(id)
	local ok, yes = pcall(function()
		local it = ItemType(id)
		return it ~= nil and it:getId() == id
	end)
	return ok and yes
end

-- ======================================================================== building
local function footprintFree(model)
	for _, t in ipairs(model.tiles) do
		if Tile(Position(t.x, t.y, t.z)) then
			return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
		end
	end
	return true
end

local function build(model)
	local made = 0
	for _, t in ipairs(model.tiles) do
		local pos = Position(t.x, t.y, t.z)
		local tile = Game.createTile(pos, true)
		if tile then
			Game.createItem(t.ground, 1, pos)
			for _, id in ipairs(t.items) do
				local item = Game.createItem(id, 1, pos)
				if item and id == C().items.portal and t.x == model.exit.x and t.y == model.exit.y and t.z == model.exit.z then
					item:setActionId(C().aid.exit)
				end
			end
			made = made + 1
		end
	end
	return made
end

local function spotFree(pos)
	local tile = Tile(pos)
	return tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and not tile:getHouse()
		and not tile:hasFlag(TILESTATE_TELEPORT) and not tile:hasFlag(TILESTATE_FLOORCHANGE)
end

local function placeEntrance(entry)
	local def = entry.def
	if not def.entrance then
		return true
	end
	local pos = P(def.entrance)
	local tile = Tile(pos)
	local have = tile and tile:getItemById(C().items.portal)
	-- the look text ("Hunting Area Portal (Emberdeep Hollows, levels 1000-1100): ...") and an effect, from this config
	local title = ChaosCityPortalsCore.bandTitle(def.name, def.spawns and def.spawns.level)
	if have and have:getActionId() == C().aid.entrance then
		ChaosCityPortals.register("hunt", C().aid.entrance, pos, nil, title)
		return true
	end
	if not spotFree(pos) or not spotFree(P(def.back or def.entrance)) then
		return false, string.format("the entrance %d,%d,%d (or its way back) is not a free walkable tile", pos.x, pos.y, pos.z)
	end
	local item = Game.createItem(C().items.portal, 1, pos)
	if not item then
		return false, "the entrance portal could not be created"
	end
	item:setActionId(C().aid.entrance)
	ChaosCityPortals.register("hunt", C().aid.entrance, pos, nil, title)
	return true
end

-- ======================================================================== monsters
local function huntersNear(pos)
	local cfg = ChaosRespawnConfig or {nearRadius = 10}
	local r = cfg.nearRadius or 10
	local seen, n = {}, 0
	for _, c in ipairs(Game.getSpectators(pos, false, true, r, r, r, r) or {}) do
		local p = c:getPlayer()
		if p and not Chaos.isStaff(p) and (not cfg.requireInFight or p:hasCondition(CONDITION_INFIGHT)) then
			local ip = p:getIp()
			local k = (cfg.onePerIp ~= false and ip and ip ~= 0) and ("ip" .. ip) or ("id" .. p:getId())
			if not seen[k] then
				seen[k] = true
				n = n + 1
			end
		end
	end
	return n
end

local function respawnDelayMs(point)
	local pct = 100
	if ChaosRespawn and ChaosRespawn.percentFor and ChaosRespawnConfig and ChaosRespawnConfig.enabled then
		pct = ChaosRespawn.percentFor(huntersNear(P(point)), ChaosRespawnConfig)
	end
	return math.max(10, point.spawntime) * 10 * pct
end

local function playerSees(pos)
	local v = C().viewRange
	for _, c in ipairs(Game.getSpectators(pos, false, true, v.x, v.x, v.y, v.y) or {}) do
		if c:isPlayer() then
			return true
		end
	end
	return false
end

-- Respawn near players: the rule of the map spawns (engine patch 0041, server/README.md "Respawn near players").
-- The minimum player distance in sqm while config spawnNearPlayers is on, else nil: the old rule (no respawn while a
-- player sees the point). An engine without patch 0041 has no such config keys: nil too.
function AG.nearPlayersDistance()
	if not (configManager and configKeys and configKeys.SPAWN_NEAR_PLAYERS) then
		return nil
	end
	local okOn, on = pcall(configManager.getBoolean, configKeys.SPAWN_NEAR_PLAYERS)
	if not okOn or on ~= true then
		return nil
	end
	local dist = 2
	if configKeys.SPAWN_MIN_PLAYER_DISTANCE then
		local okN, n = pcall(configManager.getNumber, configKeys.SPAWN_MIN_PLAYER_DISTANCE)
		if okN and tonumber(n) then
			dist = math.max(0, math.min(7, math.floor(tonumber(n))))
		end
	end
	return dist
end

-- a point may fill while players see it: its tile has a ground, no creature, no blocking item and no protection zone,
-- and no player within dist - 1 sqm (2 = never next to a player). A point of more than one monster places the others
-- up to 2 sqm away (Game.createMonster's extended search), so the player box grows by 2 for it.
function AG.canSpawnNear(point, dist)
	local pos = P(point)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if (tile.getCreatureCount and tile:getCreatureCount() or 0) > 0 then
		return false
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:hasProperty(CONST_PROP_BLOCKSOLID) then
		return false
	end
	local r = math.max(0, dist - 1) + ((point.count - #point.alive) > 1 and 2 or 0)
	if r == 0 then
		return true
	end
	for _, c in ipairs(Game.getSpectators(pos, false, true, r, r, r, r) or {}) do
		if c:isPlayer() then
			return false
		end
	end
	return true
end

-- one monster of a point, scaled to the point's level; returns the monster or nil
-- noForce (a fill in a player's view): never the forced placement, which puts a monster over creatures and items
local function spawnPoint(point, noForce)
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	local pos = P(point)
	-- the point's level, shown after the name (monster_levels.lua): the level A.levelScale scales it to
	local m = create(point.monster, pos, true, false, point.name, point.level)
		or (not noForce and create(point.monster, pos, true, true, point.name, point.level)) or nil
	if not m then
		return nil
	end
	local native = 0
	pcall(function() native = m:getMonsterLevel() end)
	local sc = A.levelScale(native > 0 and native or point.level, point.level)
	local hp = math.floor(m:getMaxHealth() * sc.health * (point.healthMult or 1))
	if hp > 0 and hp ~= m:getMaxHealth() then
		m:setMaxHealth(hp)
		m:setHealth(hp)
	end
	m:registerEvent("ChaosAreaGenDeath")
	if point.boss then
		-- a boss keeps its set health: no natural monster tier (magic x2 ... legendary x6, monster_tiers.lua), whose roll
		-- the spawn registered as a first-think event
		for _, ev in ipairs({"ChaosTierRollMagic", "ChaosTierRollRare", "ChaosTierRollLegendary"}) do
			pcall(function() m:unregisterEvent(ev) end)
		end
	end
	AG.scaled[m:getId()] = {damage = sc.damage * (point.damageMult or 1), experience = sc.experience}
	AG.pointOf[m:getId()] = point
	point.alive[#point.alive + 1] = m:getId()
	pos:sendMagicEffect(CONST_ME_TELEPORT)
	return m
end

local function fillPoint(point, noForce)
	local want = point.count - #point.alive
	for _ = 1, want do
		spawnPoint(point, noForce)
	end
	point.dueAt = nil
end

local function forget(mid)
	AG.scaled[mid] = nil
	local point = AG.pointOf[mid]
	AG.pointOf[mid] = nil
	if not point then
		return nil
	end
	for k, id in ipairs(point.alive) do
		if id == mid then
			table.remove(point.alive, k)
			break
		end
	end
	return point
end

local function pointsOf(model)
	local list = {}
	for _, s in ipairs(model.spawns) do
		list[#list + 1] = {x = s.x, y = s.y, z = s.z, monster = s.monster, level = s.level, count = s.count,
			spawntime = s.spawntime, alive = {}}
	end
	if model.boss then
		local b = model.boss
		list[#list + 1] = {x = b.x, y = b.y, z = b.z, monster = b.monster, name = b.name, level = b.level, count = 1,
			spawntime = b.spawntime or 3600, healthMult = b.healthMult, damageMult = b.damageMult, boss = true, alive = {}}
	end
	return list
end

-- ======================================================================== the dungeon system
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

local function itemName(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	return ok and name and name ~= "" and name or ("item " .. id)
end

-- The boss chest of a generated dungeon (`dungeon.chest`): one per finisher of a won run, straight into the backpack
-- (the inbox when it is full; the run sends everyone out 10 s after the kill, so there is no chest to open on the
-- floor). What it holds per difficulty: dungeons_difficulty.lua D.chest. Gear: pieces drawn from the boss's own loot
-- table by its chances, item level M.sourceLevel(boss level, tier boss) + the difficulty's bonus, rarity: the
-- difficulty's floor and the loot layer's bonus steps (item find counts). rand(a, b) for the tests.
function AG.giveChest(entry, player, difficulty, rand)
	local d = entry.def.dungeon
	if not (d and d.chest) then
		return nil
	end
	rand = rand or math.random
	local DD = ChaosDungeonDifficulty or dofile("data/scripts/chaos/dungeons_difficulty.lua")
	local c = DD.chest(d.chest, difficulty)
	local L, M = ChaosLoot, ChaosItemMods
	local found, inbox = {}, false
	if c.gold > 0 then
		player:setBankBalance(player:getBankBalance() + c.gold)
	end
	local b = entry.def.boss
	local rows, total = {}, 0
	local mt = b and MonsterType(b.monster)
	for _, e in ipairs(mt and mt:getLoot() or {}) do
		if e.itemId and (e.chance or 0) > 0 and L and L.isGearId(e.itemId) then
			rows[#rows + 1] = e
			total = total + e.chance
		end
	end
	local itemFind = L and L.itemFindMult and L.itemFindMult(player) or 1
	local level = M and M.sourceLevel and M.sourceLevel({monsterLevel = b and b.level or d.level, tier = "boss"}) or nil
	if level and M.config and M.config.itemLevel then
		level = math.min(M.config.itemLevel.max, level + c.itemLevel)
	end
	local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names
	for _ = 1, (total > 0 and c.pieces or 0) do
		local roll, pick = rand(1, total), rows[#rows]
		for _, e in ipairs(rows) do
			roll = roll - e.chance
			if roll <= 0 then
				pick = e
				break
			end
		end
		local rarity = L.upgradeRarity and L.upgradeRarity(c.tier, c.rarity, itemFind) or c.rarity
		local item = ChaosCrafting and ChaosCrafting.createItem and ChaosCrafting.createItem(pick.itemId, rarity, level)
			or Game.createItem(pick.itemId, 1)
		if item then
			inbox = giveEx(player, item) or inbox
			found[#found + 1] = "[" .. (names and names[rarity] or rarity) .. "] " .. itemName(pick.itemId)
		end
	end
	if L and L.rollCurrency then
		local ctx = {tier = c.tier, player = player, level = 0, itemFind = itemFind}
		for _ = 1, c.currency do
			for _, cur in ipairs(L.rollCurrency(c.tier, ctx)) do
				local rest = cur.count - Chaos.giveItem(player, cur.id, cur.count)
				if rest > 0 then
					local box = player:getInbox()
					if box then
						box:addItem(cur.id, rest, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
					end
					inbox = true
				end
				found[#found + 1] = (cur.count > 1 and (cur.count .. "x ") or "") .. itemName(cur.id)
			end
		end
	end
	local t = Chaos.t or function(_, text) return text end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(t(player, "Boss chest of %s: %d gold to your bank%s%s.%s"),
		entry.def.name, c.gold, #found > 0 and ", " or "", table.concat(found, ", "),
		inbox and t(player, " Your backpack was full: the rest is in your inbox.") or ""))
	return c, found
end

-- a won run (dungeons.lua endRun, per finisher): the boss chest and the achievement counters of the dungeon
-- (achievements_data.lua: dungeon_<area id> clears, dungeon_<area id>_top the best difficulty)
local function onClear(entry, player, info)
	AG.giveChest(entry, player, info and info.difficulty or 1)
	local A2 = ChaosAchievements
	if A2 and A2.progress then
		A2.progress(player, "dungeon_" .. entry.def.id, 1)
		local diff = info and info.difficulty or 1
		A2.set(player, "dungeon_" .. entry.def.id .. "_top", diff)
		if diff >= 6 then
			A2.set(player, "dungeon_" .. entry.def.id .. "_d6", 1)
		end
	end
end

-- The boss room gate of a generated dungeon: every walkable tile of the ring just outside the boss room (the doorways
-- the corridors cut through its wall) gets a wall piece of the theme's wall brush (horizontal on the north and south
-- rows, vertical on the west and east columns: ids the palette check already covers). Closed at every run start, opened
-- by the dungeon system when the run reaches Chaos.dungeons.progressNeeded (dungeons.lua), when the boss also appears.
-- Returns {{x, y, z, id}}; empty for a theme without walls.
function AG.gateTiles(cfg, def, model)
	local q = model.bossRoom
	local theme = cfg.themes[def.theme]
	local brush = theme and theme.wall and cfg.walls[theme.wall]
	local walk = q and model.walk and model.walk[q.z]
	local out = {}
	if not (brush and walk) then
		return out
	end
	local h, v = brush.horizontal[1][1], brush.vertical[1][1]
	for y = q.y1 - 1, q.y2 + 1 do
		for x = q.x1 - 1, q.x2 + 1 do
			local ring = x == q.x1 - 1 or x == q.x2 + 1 or y == q.y1 - 1 or y == q.y2 + 1
			if ring and walk[y * 65536 + x] then
				local side = (y == q.y1 - 1 or y == q.y2 + 1) and h or v
				out[#out + 1] = {x = x, y = y, z = q.z, id = side}
			end
		end
	end
	return out
end

local function setGate(entry, closed)
	for _, g in ipairs(entry.gate or {}) do
		local pos = P(g)
		local tile = Tile(pos)
		local item = tile and tile:getItemById(g.id)
		if closed and not item then
			Game.createItem(g.id, 1, pos)
		elseif not closed and item then
			item:remove()
			pos:sendMagicEffect(CONST_ME_POFF or 3)
		end
	end
	entry.gateClosed = closed
end

local function registerDungeon(entry)
	local d = entry.def.dungeon
	if not d then
		return
	end
	if not (DUNGEON_SYSTEM and DUNGEON_SYSTEM.Dungeons and Chaos.dungeons and Chaos.dungeons.extra) then
		log(entry.def.id .. ": the dungeon system is not loaded, the dungeon is not registered")
		return
	end
	local m = entry.model
	local x1, y1 = m.origin.x, m.origin.y
	local x2, y2 = x1 + m.w - 1, y1 + m.h - 1
	DUNGEON_SYSTEM.Dungeons[d.id] = {
		Name = entry.def.name, NeedParty = (d.party or 1) > 1, AmountParty = d.party or 1, NeedLevel = true, Level = d.level,
		DungeonTime = d.time, DungeonPos = P(m.arrival), FromPos = {x = x1, y = y1, z = m.origin.z},
		ToPos = {x = x2, y = y2, z = m.origin.z + (entry.def.floors or 1) - 1}, SpawnMonsters = false, Monsters = {}
	}
	local b = m.boss
	Chaos.dungeons.extra[d.id] = {
		title = d.title or entry.def.name,
		-- the boss shows its own name (Chaos.createMonsterNamed); the dungeon matches the kill by that name
		bossName = b and ((Chaos.createMonsterNamed and b.name or b.monster):lower()) or nil,
		bossType = b and b.monster or nil,
		loot = d.loot, challenges = d.challenges, bossHealth = d.bossHealth, trashHealth = d.trashHealth,
		-- the boss chest and the achievement counters of a won run (dungeons.lua endRun, per finisher)
		onClear = d.chest and function(player, info)
			onClear(entry, player, info)
		end or nil,
		-- every run: the monsters of every point (dungeons.lua startRun; its teardown removes them); the boss room is
		-- closed by its gate and the boss waits for `unlock`
		populate = function()
			for _, point in ipairs(entry.points) do
				local old = {}
				for k, mid in ipairs(point.alive) do
					old[k] = mid
				end
				for _, mid in ipairs(old) do
					local m = Monster(mid)
					if m then
						m:remove()
					end
					forget(mid)
				end
				if not point.boss then
					fillPoint(point)
				end
			end
			setGate(entry, true)
		end,
		-- the run reached Chaos.dungeons.progressNeeded (dungeons.lua): the gate opens and the boss appears in its room
		unlock = function()
			setGate(entry, false)
			for _, point in ipairs(entry.points) do
				if point.boss and #point.alive == 0 then
					fillPoint(point)
				end
			end
		end
	}
	entry.gate = AG.gateTiles(C(), entry.def, m)
	setGate(entry, true)
	entry.isDungeon = true
	log(string.format("%s registered as dungeon %d (level %d)", entry.def.name, d.id, d.level))
end

-- ======================================================================== startup
function AG.buildAll()
	local cfg = C()
	if not cfg.enabled then
		return 0
	end
	if not Game.createTile then
		log("Game.createTile is missing: no generated areas")
		return 0
	end
	local dark = darkReady()
	local opts = {dark = dark, darkIds = ChaosDarkTiles.ids}
	local done = 0
	for _, def in ipairs(cfg.areas) do
		if def.enabled ~= false and not AG.built[def.id] then
			local t0 = os.clock()
			local model = A.generate(cfg, def, opts)
			local problems = A.validate(cfg, model, opts)
			local missing
			for id in pairs(A.allowedIds(cfg, def, opts)) do
				if not itemKnown(id) then
					missing = id
					break
				end
			end
			local free, why = footprintFree(model)
			if #problems > 0 then
				log(def.id .. " not built: " .. problems[1])
			elseif missing then
				log(string.format("%s not built: item %d is not in items.otb", def.id, missing))
			elseif not free then
				log(def.id .. " not built: " .. why)
			else
				local tiles = build(model)
				AG.built[def.id] = true
				local entry = {def = def, model = model, points = pointsOf(model)}
				AG.areas[def.id] = entry
				local ok, err = placeEntrance(entry)
				if not ok then
					log(def.id .. ": " .. err .. " (no entrance; /areagen goto " .. def.id .. " still works)")
				end
				if def.dungeon then
					registerDungeon(entry)
				else
					for _, point in ipairs(entry.points) do
						fillPoint(point)
					end
				end
				log(string.format("%s built: %d tiles, %d monsters%s, %.2f s%s", def.name, tiles, model.stats.monsters,
					model.boss and " + boss" or "", os.clock() - t0, dark and ", dark tile set" or ""))
				done = done + 1
			end
		end
	end
	return done
end

local startup = GlobalEvent("ChaosAreaGenStartup")
function startup.onStartup()
	local ok, err = pcall(AG.buildAll)
	if not ok then
		log("startup failed: " .. tostring(err))
	end
	return true
end
startup:register()

-- ======================================================================== the tick: respawns and the leash
local think = GlobalEvent("ChaosAreaGenTick")
function think.onThink(interval)
	local now = nowMs()
	local leash = C().leash or 14
	for _, entry in pairs(AG.areas) do
		if not entry.isDungeon then
			for _, point in ipairs(entry.points) do
				-- monsters gone without a death event (removed by staff or a script)
				for k = #point.alive, 1, -1 do
					local m = Monster(point.alive[k])
					if not m then
						forget(point.alive[k])
						point.dueAt = point.dueAt or (now + respawnDelayMs(point))
					else
						local pos = m:getPosition()
						if (math.abs(pos.x - point.x) > leash or math.abs(pos.y - point.y) > leash or pos.z ~= point.z)
							and not m:getTarget() then
							m:teleportTo(P(point), true)
						end
					end
				end
				if #point.alive < point.count then
					point.dueAt = point.dueAt or (now + respawnDelayMs(point))
					if now >= point.dueAt then
						if not playerSees(P(point)) then
							fillPoint(point)
						else
							-- in view: the near-players rule (spawnNearPlayers), else the timer starts again
							local dist = AG.nearPlayersDistance()
							if dist and AG.canSpawnNear(point, dist) then
								fillPoint(point, true)
							else
								point.dueAt = now + respawnDelayMs(point)
							end
						end
					end
				end
			end
		end
	end
	return true
end
think:interval((ChaosAreaGenConfig.tickSeconds or 2) * 1000)
think:register()

local death = CreatureEvent("ChaosAreaGenDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local point = forget(creature:getId())
	if point and #point.alive < point.count and not point.dueAt then
		point.dueAt = nowMs() + respawnDelayMs(point)
	end
	return true
end
death:register()

-- ======================================================================== damage and experience of scaled monsters
local function scaleHit(attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local sc = attacker and AG.scaled[attacker:getId()]
	if sc and primaryType ~= COMBAT_HEALING and sc.damage ~= 1 then
		primaryDamage = math.floor(primaryDamage * sc.damage)
		secondaryDamage = math.floor(secondaryDamage * sc.damage)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

local hit = CreatureEvent("ChaosAreaGenPlayerHit")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return scaleHit(attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
hit:register()

local mana = CreatureEvent("ChaosAreaGenPlayerMana")
function mana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return scaleHit(attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
mana:register()

local login = CreatureEvent("ChaosAreaGenLogin")
function login.onLogin(player)
	player:registerEvent("ChaosAreaGenPlayerHit")
	player:registerEvent("ChaosAreaGenPlayerMana")
	return true
end
login:type("login")
login:register()

local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	local sc = source and AG.scaled[source:getId()]
	if sc and sc.experience ~= 1 then
		return math.floor(exp * sc.experience + 1e-9)
	end
	return exp
end
xpCb:register(1)

-- ======================================================================== the portals
local function areaOfEntrance(pos)
	for _, entry in pairs(AG.areas) do
		local e = entry.def.entrance
		if e and e.x == pos.x and e.y == pos.y and e.z == pos.z then
			return entry
		end
	end
	return nil
end

local function areaOfExit(pos)
	for _, entry in pairs(AG.areas) do
		local ex = entry.model.exit
		if ex.x == pos.x and ex.y == pos.y and ex.z == pos.z then
			return entry
		end
	end
	return nil
end

local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	if item:getActionId() == C().aid.entrance then
		local entry = areaOfEntrance(position)
		if not entry then
			player:teleportTo(fromPosition, true)
			return true
		end
		local need = entry.def.minLevel or 1
		if player:getLevel() < need then
			player:teleportTo(fromPosition, true)
			player:sendCancelMessage(string.format("%s is for level %d and above.", entry.def.name, need))
			return true
		end
		player:teleportTo(P(entry.model.arrival))
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: monsters of level %d-%d. The portal beside you leads back.",
			entry.def.name, entry.def.spawns.level[1], entry.def.spawns.level[2]))
		return true
	end
	-- the exit: back beside the entrance, or to the temple for an area without one
	local entry = areaOfExit(position)
	local back = entry and (entry.def.back or entry.def.entrance)
	-- a planned content hunt's exit: back to the teleport room (hunt_teleports.lua)
	local room = not back and ChaosHuntTeleports and ChaosHuntTeleports.backFor and ChaosHuntTeleports.backFor(position)
	player:teleportTo(back and P(back) or room or player:getTown():getTemplePosition())
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
step:aid(ChaosAreaGenConfig.aid.entrance, ChaosAreaGenConfig.aid.exit)
step:register()

-- ======================================================================== staff
local talk = TalkAction("/areagen")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < 4 then
		return true
	end
	local args = {}
	for w in tostring(param or ""):gmatch("%S+") do
		args[#args + 1] = w
	end
	local function reply(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "[areagen] " .. text)
	end
	local cmd = args[1] or "status"
	if cmd == "status" then
		for _, def in ipairs(C().areas) do
			local entry = AG.areas[def.id]
			if entry then
				local alive, total = 0, 0
				for _, p in ipairs(entry.points) do
					alive, total = alive + #p.alive, total + p.count
				end
				reply(string.format("%s (%s): built, %d / %d monsters alive, arrival %d,%d,%d%s", def.id, def.name, alive, total,
					entry.model.arrival.x, entry.model.arrival.y, entry.model.arrival.z, entry.isDungeon and ", dungeon" or ""))
			else
				reply(def.id .. ": not built")
			end
		end
	elseif cmd == "goto" then
		local entry = AG.areas[args[2] or ""]
		if entry then
			player:teleportTo(P(entry.model.arrival))
		end
		reply(entry and "ok" or "/areagen goto <id>")
	elseif cmd == "fill" then
		local entry = AG.areas[args[2] or ""]
		if entry then
			for _, point in ipairs(entry.points) do
				fillPoint(point)
			end
		end
		reply(entry and "filled" or "/areagen fill <id>")
	else
		reply("/areagen status | goto <id> | fill <id>")
	end
	return false
end
talk:separator(" ")
talk:register()

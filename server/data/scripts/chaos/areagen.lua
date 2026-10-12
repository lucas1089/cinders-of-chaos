-- Generated areas (server/README.md "Generated areas"): hunting areas and a dungeon built at startup from a seed, with
-- no map edit. The tile model comes from areagen_core.lua (pure, tests/areagen_test.lua), the palettes and areas from
-- areagen_config.lua. This file only talks to the engine:
--   startup   every enabled area is generated and built with Game.createTile / Game.createItem in its empty part of
--             the map (refused, with a log line, when a tile of its footprint already exists or an item id is
--             missing); the entrance portal goes on the live map (action id aid.entrance, a level gate), the exit
--             portal next to the arrival (aid.exit, back to the entrance or the temple); the spawn points get their
--             monsters; an area with `dungeon` is registered as a base dungeon of the dungeon system (dungeons.lua).
--   monsters  scaled to the area's level (A.levelScale: health at the spawn, damage to players in the health / mana
--             events, experience in an onGainExperience callback); a dead point respawns after its spawntime, never
--             while a player sees the spot (the timer starts again, as the engine does), faster where several
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
	if have and have:getActionId() == C().aid.entrance then
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

-- one monster of a point, scaled to the point's level; returns the monster or nil
local function spawnPoint(point)
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	local pos = P(point)
	local m = create(point.monster, pos, true, false, point.name) or create(point.monster, pos, true, true, point.name)
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
	AG.scaled[m:getId()] = {damage = sc.damage * (point.damageMult or 1), experience = sc.experience}
	AG.pointOf[m:getId()] = point
	point.alive[#point.alive + 1] = m:getId()
	pos:sendMagicEffect(CONST_ME_TELEPORT)
	return m
end

local function fillPoint(point)
	local want = point.count - #point.alive
	for _ = 1, want do
		spawnPoint(point)
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
		loot = d.loot, challenges = d.challenges,
		-- every run: the monsters of every point and the boss (dungeons.lua startRun; its teardown removes them)
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
				fillPoint(point)
			end
		end
	}
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
						if playerSees(P(point)) then
							point.dueAt = now + respawnDelayMs(point)
						else
							fillPoint(point)
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
	player:teleportTo(back and P(back) or player:getTown():getTemplePosition())
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

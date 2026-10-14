-- Invasions: a themed horde attacks a town or a hunting ground in waves; everybody can defend it.
-- Settings: invasion_config.lua (Chaos.invasionConfig). Pure logic: invasion_core.lua (tests/invasion_test.lua).
-- Client: game_invasion (HUD over the map, upcoming events window; extended opcode ChaosOpcodes.invasion = 251),
-- toasts through game_chaosnotify (action "invasion" on opcode 79). Overview: server/README.md "Invasions and world
-- events". The small world events (Chaos Storm, Wandering Merchant, Golden Hour) are worldevents.lua.
--
-- Flow
--   schedule (fixed times + a random one on some days) -> warnings 30 / 10 / 1 minutes before (broadcast + toast)
--   -> start: the HUD appears for everybody online, the first wave arrives after firstWaveSeconds
--   -> waves of packs spawn at the area border (walkable tiles only: never a protection zone, house, depot,
--      teleport or floor change) and walk to the target point (path search, else greedy steps; Creature:move with a
--      tile and flags 0, so the engine's own rules keep monsters out of protection zones and houses). An invader
--      with a player target fights instead (the engine's AI). Invaders at the target raise the breach meter.
--   -> the last wave brings the boss -> all waves and the boss slain in time: victory (rewards by contribution, the
--      Defender board, the Victory buff); the breach meter full or the time up: the area is occupied (occupation)
--   Damage dealt to invaders, kills and healing done to other players inside the area count as contribution.
--
-- Engine API used (all in this engine's luascript.cpp): Game.createMonster (onSpawn runs before the placement,
-- which is where an invader is renamed), Monster:rename, Creature:getPathTo / move(tile, flags) / getTarget /
-- setMaxHealth / changeSpeed, Tile:hasFlag / hasProperty / getHouse / getItemByType / getCreatureCount,
-- CreatureEvent healthchange / death / login / extendedopcode, EventCallback onSpawn / onGainExperience,
-- GlobalEvent onThink / onStartup, TalkAction. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosInvasionCore or not ChaosInvasionCore.hud then
	dofile("data/scripts/chaos/invasion_core.lua")
end
Chaos.invasionConfig = Chaos.invasionConfig or dofile("data/scripts/chaos/invasion_config.lua")

ChaosInvasion = ChaosInvasion or {}
local V = ChaosInvasion
local I = ChaosInvasionCore
local function C()
	return Chaos.invasionConfig
end
local OPCODE = ChaosOpcodes.invasion or 251
local NOTIFY = ChaosOpcodes.notifications or 79

V.state = V.state or {phase = "idle", token = 0}
V.invaders = V.invaders or {} -- creature id -> {scale, boss, occupier, wave, path, nextStep, stuck}
V.recent = V.recent or {} -- creature id -> scale, kept a few seconds after a death (experience runs before the death event)
V.pending = V.pending or {} -- guid -> list of rewards for players offline at the end
V.warned = V.warned or {}
V.buff = V.buff or nil -- Victory buff {endsAt, xp, scope, areaKey, name}
V.extraAreas = V.extraAreas or {} -- areas added at runtime (V.addArea, test servers)
local state = V.state

local function log(text)
	print("[Chaos invasion] " .. text)
end

local function now()
	return os.time()
end

local function P(t)
	return Position(t.x, t.y, t.z or 7)
end

-- ======================================================================== messages
-- text: a string or a deferred text (ChaosI18n.msg), written in each player's language
local function toast(player, text)
	local function payload(p)
		return json.encode({action = "invasion", message = Chaos.t(p, text)})
	end
	if player then
		player:sendExtendedOpcode(NOTIFY, payload(player))
		return
	end
	for _, p in ipairs(Game.getPlayers()) do
		p:sendExtendedOpcode(NOTIFY, payload(p))
	end
end
V.toast = toast

-- text: a string or a deferred text (ChaosI18n.msg): each player reads it in their language, the log is English
local function announce(text, withToast)
	local english = Chaos.broadcast(MESSAGE_EVENT_ADVANCE, text)
	if withToast ~= false then
		toast(nil, text)
	end
	log(english)
end
V.announce = announce

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

-- ======================================================================== areas and tiles
function V.areas()
	local list = {}
	for _, a in ipairs(C().areas or {}) do
		list[#list + 1] = a
	end
	for _, a in ipairs(V.extraAreas) do
		list[#list + 1] = a
	end
	return list
end

-- the config with the runtime areas (test servers add theirs with V.addArea)
function V.cfg()
	local c = C()
	if #V.extraAreas == 0 then
		return c
	end
	local copy = {}
	for k, v in pairs(c) do
		copy[k] = v
	end
	copy.areas = V.areas()
	return copy
end

function V.addArea(area)
	for i, a in ipairs(V.extraAreas) do
		if a.key == area.key then
			V.extraAreas[i] = area
			return
		end
	end
	V.extraAreas[#V.extraAreas + 1] = area
end

function V.area(key)
	return (I.areaByKey(V.cfg(), key))
end

local templeCache
local function temples()
	if templeCache then
		return templeCache
	end
	templeCache = {}
	for _, town in ipairs(Game.getTowns and Game.getTowns() or {}) do
		local ok, pos = pcall(function() return town:getTemplePosition() end)
		if ok and pos then
			templeCache[#templeCache + 1] = pos
		end
	end
	return templeCache
end

-- a tile an invader may be created on or walk to: ground, walkable, no protection zone, house, depot, teleport or
-- floor change, not in the area's exclude rectangles, not within templeRadius of a temple
function V.tileOk(pos, area, allowCreature)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false, "no tile"
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false, "protection zone"
	end
	if tile:getHouse() then
		return false, "house"
	end
	if tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT) then
		return false, "floor change / teleport"
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_IMMOVABLEBLOCKSOLID) then
		return false, "blocked"
	end
	if ITEM_TYPE_DEPOT and tile:getItemByType(ITEM_TYPE_DEPOT) then
		return false, "depot"
	end
	if not allowCreature and tile:getCreatureCount() > 0 then
		return false, "occupied"
	end
	if area and I.excluded(pos, area) then
		return false, "excluded"
	end
	local radius = C().templeRadius or 6
	for _, t in ipairs(temples()) do
		if t.z == pos.z and math.max(math.abs(t.x - pos.x), math.abs(t.y - pos.y)) <= radius then
			return false, "temple"
		end
	end
	return true
end

-- valid spawn points of an area (shuffled), at most `want`
local function spawnPoints(area, want, rng)
	local out = {}
	for _, p in ipairs(I.edgePoints(area, rng, (C().waves or {}).edgeDepth or 3)) do
		if V.tileOk(p, area) then
			out[#out + 1] = p
			if #out >= want then
				break
			end
		end
	end
	return out
end

-- the target point, moved to the nearest valid tile when it is not one (a protection zone, a wall)
local function resolveTarget(area)
	local t = area.target
	local z = t.z or area.z or 7
	if V.tileOk(Position(t.x, t.y, z), nil, true) then
		return {x = t.x, y = t.y, z = z}, true
	end
	for r = 1, 8 do
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local p = Position(t.x + dx, t.y + dy, z)
					if V.tileOk(p, nil, true) then
						return {x = p.x, y = p.y, z = z}, false
					end
				end
			end
		end
	end
	return nil, false
end

-- /invasion check: is the area usable on this map?
function V.check(area)
	local lines = {}
	local target, exact = resolveTarget(area)
	if not target then
		lines[#lines + 1] = "target: no walkable tile outside a protection zone within 8 tiles of " ..
			area.target.x .. "," .. area.target.y .. " - fix the target"
	elseif not exact then
		lines[#lines + 1] = string.format("target %d,%d is not walkable or in a protection zone: %d,%d is used",
			area.target.x, area.target.y, target.x, target.y)
	else
		lines[#lines + 1] = "target ok"
	end
	local reasons, count = {}, 0
	for _, p in ipairs(I.edgePoints(area, I.lcg(1), (C().waves or {}).edgeDepth or 3)) do
		local ok, why = V.tileOk(p, area)
		if ok then
			count = count + 1
		else
			reasons[why] = (reasons[why] or 0) + 1
		end
	end
	local parts = {}
	for why, n in pairs(reasons) do
		parts[#parts + 1] = why .. " " .. n
	end
	table.sort(parts)
	lines[#lines + 1] = string.format("%d valid spawn tiles on the border (refused: %s)", count, #parts > 0 and table.concat(parts, ", ") or "none")
	if count < 10 then
		lines[#lines + 1] = "too few spawn tiles: widen the rectangle or change `edges`"
	end
	return table.concat(lines, "\n"), count >= 10 and target ~= nil
end

-- ======================================================================== client
local function hudList()
	local c = C()
	local cw = c.contribution or {}
	return I.shares(state.contrib or {}, cw, state.unit or 0, 0)
end

local function sendHud(player, list, index)
	local mine = index and index[player:getGuid()]
	Chaos.send(player, OPCODE, "hud", I.hud(state, now(), list, mine, C()))
end

function V.broadcastHud()
	if state.phase == "idle" then
		return
	end
	local list = hudList()
	local index = {}
	for _, e in ipairs(list) do
		index[e.guid] = e
	end
	local minLevel = C().minLevel or 0
	for _, p in ipairs(Game.getPlayers()) do
		if p:getLevel() >= minLevel then
			sendHud(p, list, index)
		end
	end
end

local function sendAll(action, data)
	for _, p in ipairs(Game.getPlayers()) do
		Chaos.send(p, OPCODE, action, data)
	end
end

-- upcoming events for the client window / !invasion: invasions (not the secret random ones before their first
-- warning), the world event and the Victory buff
function V.calendar()
	local c = V.cfg()
	local t = now()
	local list = {}
	local warnFirst = ((c.warnMinutes or {})[1] or 30) * 60
	for _, s in ipairs(I.upcoming(c, t, 7 * 86400)) do
		if not s.secret or s.at - t <= warnFirst then
			local area = s.areaKey and I.areaByKey(c, s.areaKey)
			local faction = s.factionKey and c.factions[s.factionKey]
			list[#list + 1] = {kind = "invasion", at = s.at, inSeconds = s.at - t, when = os.date("%a %H:%M", s.at),
				name = (faction and faction.name or "A horde") .. " invades " .. (area and area.name or "?")}
		end
		if #list >= 6 then
			break
		end
	end
	if state.phase ~= "idle" then
		table.insert(list, 1, {kind = "invasion", at = state.startedAt, inSeconds = 0, when = "now",
			name = (state.phase == "occupied" and "Occupied: " or "Invasion: ") .. tostring(state.areaName)})
	end
	if ChaosWorldEvents and ChaosWorldEvents.calendar then
		for _, e in ipairs(ChaosWorldEvents.calendar(t)) do
			list[#list + 1] = e
		end
	end
	if V.buff and I.buffActive(V.buff, t) then
		list[#list + 1] = {kind = "buff", at = V.buff.endsAt, inSeconds = 0, when = "until " .. os.date("%H:%M", V.buff.endsAt),
			name = string.format("Victory: +%d%% experience%s", math.floor((V.buff.xp - 1) * 100 + 0.5),
				V.buff.scope == "area" and (" in " .. V.buff.name) or "")}
	end
	return list
end

-- ======================================================================== spawning
local pendingRename -- set around Game.createMonster; the onSpawn callback below renames before the placement

local function scaleMonster(monster, scale)
	if scale and scale.hp and scale.hp ~= 1 then
		local hp = math.max(1, math.floor(monster:getMaxHealth() * scale.hp))
		monster:setMaxHealth(hp)
		monster:setHealth(hp)
	end
end

local function registerInvader(monster, info)
	V.invaders[monster:getId()] = info
	monster:registerEvent("ChaosInvasionHealth")
	monster:registerEvent("ChaosInvasionDeath")
	state.alive = (state.alive or 0) + 1
	if info.wave then
		state.waveAlive = (state.waveAlive or 0) + 1
	end
	state.unitSum = (state.unitSum or 0) + monster:getMaxHealth()
	state.unitCount = (state.unitCount or 0) + 1
	state.unit = state.unitSum / state.unitCount
end

local function spawnOne(name, pos, tier, scale, info, rename)
	pendingRename = rename
	local monster = Game.createMonster(name, P(pos), true, false)
	pendingRename = nil
	if not monster then
		return nil
	end
	if tier and tier ~= "normal" and ChaosApplyTier then
		ChaosApplyTier(monster, tier)
	end
	scaleMonster(monster, scale)
	info.scale = scale
	info.areaLevel = state.area and state.area.level -- monster_damage.lua: an invader counts at least at this level
	registerInvader(monster, info)
	return monster
end

local function countPlayers(area)
	local radius = (C().players or {}).radius or 30
	local minLevel = C().minLevel or 0
	local n = 0
	for _, p in ipairs(Game.getPlayers()) do
		if p:getLevel() >= minLevel and I.inArea(p:getPosition(), area, radius) then
			n = n + 1
		end
	end
	return math.max(1, n)
end

local function spawnWave(i)
	local c = C()
	local area = state.area
	local faction = c.factions[state.factionKey]
	local players = countPlayers(area)
	local plan = I.planWave(c, area, faction, i, players, math.random)
	local points = spawnPoints(area, #plan.packs * 3 + 6, I.lcg(state.startedAt + i * 31))
	state.wave = i
	state.waveAt = now()
	state.waveAlive = 0
	local spawned = 0
	if #points == 0 then
		log("wave " .. i .. ": no valid spawn tile on the border of " .. area.key)
	else
		for k, pack in ipairs(plan.packs) do
			local p = points[(k - 1) % #points + 1]
			for _, m in ipairs(pack.monsters) do
				if spawnOne(m.name, p, m.tier, m.scale, {wave = i}) then
					spawned = spawned + 1
				end
			end
			P(p):sendMagicEffect(CONST_ME_TELEPORT)
		end
	end
	state.waveSize = math.max(1, spawned)
	state.planned = (state.planned or 0) + spawned
	if i == state.waves then
		local boss = I.planBoss(c, area, faction, players)
		if boss then
			local bp = points[1] or state.target
			local monster = spawnOne(boss.name, bp, boss.tier, {hp = 1, dmg = boss.dmg, xp = boss.xp}, {wave = i, boss = true},
				boss.rename)
			if monster then
				monster:setMaxHealth(boss.health)
				monster:setHealth(boss.health)
				state.bossId = monster:getId()
				state.bossName = monster:getName()
				-- its type ("Orc Warlord" behind "Warchief Grashnak"): the unique drop lists name types
				state.bossType = Chaos.monsterTypeName and Chaos.monsterTypeName(monster) or boss.name
				state.bossAlive = true
				state.bossHp = 100
				state.planned = state.planned + 1
				announce(ChaosI18n.msg("Wave %d of %d: %s leads the last assault on %s!", i, state.waves, state.bossName,
					state.areaName))
			else
				log("boss " .. boss.name .. " could not be created")
			end
		end
		state.bossSpawned = true
	end
	if i < state.waves or not state.bossAlive then
		announce(ChaosI18n.msg("Wave %d of %d: %d %s reach %s!", i, state.waves, spawned,
			spawned == 1 and "invader" or "invaders", state.areaName))
	end
end

-- ======================================================================== movement
local DIRS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {-1, 1}, {1, 1}, {-1, -1}, {1, -1}} -- engine Direction order

local function stepTo(monster, pos)
	local tile = Tile(pos)
	if not tile then
		return false
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:getHouse() then
		return false
	end
	local ok, ret = pcall(function() return monster:move(tile, 0) end)
	return ok and (ret == 0 or ret == RETURNVALUE_NOERROR)
end

local function greedyStep(monster, from, target)
	local best = {}
	for _, d in ipairs(DIRS) do
		local p = {x = from.x + d[1], y = from.y + d[2], z = from.z}
		local dist = math.max(math.abs(p.x - target.x), math.abs(p.y - target.y)) + (math.abs(p.x - target.x) + math.abs(p.y - target.y)) * 0.01
		best[#best + 1] = {p = p, d = dist}
	end
	table.sort(best, function(a, b) return a.d < b.d end)
	local here = math.max(math.abs(from.x - target.x), math.abs(from.y - target.y))
	for i = 1, 3 do
		if best[i].d < here + 0.5 and stepTo(monster, Position(best[i].p.x, best[i].p.y, best[i].p.z)) then
			return true
		end
	end
	return false
end

local function moveInvader(id, info, t, target, radius)
	local monster = Monster(id)
	if not monster then
		return
	end
	if info.occupier then
		return
	end
	if monster:getTarget() then
		info.path = nil
		return
	end
	if t < (info.nextStep or 0) then
		return
	end
	local pos = monster:getPosition()
	if pos.z ~= target.z then
		return
	end
	if math.max(math.abs(pos.x - target.x), math.abs(pos.y - target.y)) <= radius then
		return
	end
	local speed = math.max(50, monster:getSpeed())
	info.nextStep = t + math.max(C().moveMs or 400, math.floor(150000 / speed))
	if not info.path or #info.path == 0 or (info.steps or 0) >= 12 then
		local ok, path = pcall(function() return monster:getPathTo(P(target), 0, radius, true, false, 0) end)
		info.path = ok and type(path) == "table" and path or nil
		info.steps = 0
	end
	local moved = false
	if info.path and #info.path > 0 then
		local d = DIRS[table.remove(info.path, 1) + 1]
		if d then
			moved = stepTo(monster, Position(pos.x + d[1], pos.y + d[2], pos.z))
		end
		info.steps = (info.steps or 0) + 1
		if not moved then
			info.path = nil
		end
	end
	if not moved then
		moved = greedyStep(monster, pos, target)
	end
	info.stuck = moved and 0 or (info.stuck or 0) + 1
end

local function moveLoop(token)
	if state.token ~= token or state.phase ~= "running" then
		return
	end
	local t = os.mtime and os.mtime() or now() * 1000
	local target = state.target
	local radius = (C().breach or {}).radius or 2
	for id, info in pairs(V.invaders) do
		moveInvader(id, info, t, target, radius)
	end
	addEvent(moveLoop, C().moveMs or 400, token)
end

-- ======================================================================== the fight
local function invadersAtTarget()
	local radius = (C().breach or {}).radius or 2
	local n, boss = 0, false
	for id, info in pairs(V.invaders) do
		local m = Monster(id)
		if m then
			local p = m:getPosition()
			if p.z == state.target.z and math.max(math.abs(p.x - state.target.x), math.abs(p.y - state.target.y)) <= radius then
				if info.boss then
					boss = true
				else
					n = n + 1
				end
			end
		end
	end
	return n, boss
end

local function cleanupInvaders()
	for id in pairs(V.invaders) do
		local m = Monster(id)
		if m then
			m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			m:remove()
		end
	end
	V.invaders = {}
end

local giveRewards, occupy, finish

-- the breach meter over the target point for the players near it (tilebars.lua, client game_tileoverlays)
local function breachBar(on)
	if not (ChaosTileBars and ChaosTileBars.set) then
		return
	end
	if not on then
		ChaosTileBars.remove("inv:breach")
	elseif Chaos.tileBarsConfig and Chaos.tileBarsConfig.invasion and state.target then
		ChaosTileBars.set("inv:breach", {pos = {x = state.target.x, y = state.target.y, z = state.target.z},
			label = "Breach", progress = state.breach / 100, color = "#d0453a"})
	end
end

local function tick(token)
	if state.token ~= token then
		return
	end
	local t = now()
	if state.phase == "running" then
		local n, boss = invadersAtTarget()
		local before = state.breach
		state.breach = I.breachStep(state.breach, n, boss, 1, C().breach)
		if before < 50 and state.breach >= 50 then
			announce(ChaosI18n.msg("The defences of %s are crumbling: the breach is at 50%%!", state.areaName))
		elseif before < 80 and state.breach >= 80 then
			announce(ChaosI18n.msg("%s is about to fall: the breach is at 80%%!", state.areaName))
		end
		breachBar(true)
		if state.bossAlive then
			local b = Monster(state.bossId)
			if b then
				state.bossHp = math.floor(b:getHealth() * 100 / math.max(1, b:getMaxHealth()))
			end
		end
		if I.nextWaveDue(state, t, C().waves) then
			spawnWave(state.wave + 1)
		end
		local result = I.outcome(state, t)
		if result then
			finish(result)
			return
		end
	elseif state.phase == "occupied" then
		local occ = state.occupation
		local alive = 0
		for id in pairs(V.invaders) do
			if Monster(id) then
				alive = alive + 1
			end
		end
		occ.alive = alive
		local over = I.occupationOver(occ, t, alive)
		if over then
			V.endOccupation(over)
			return
		end
	else
		return
	end
	if t >= (state.nextHud or 0) then
		state.nextHud = t + (C().hudSeconds or 2)
		V.broadcastHud()
	end
	addEvent(tick, 1000, token)
end

function V.start(areaKey, factionKey)
	if state.phase ~= "idle" then
		return false, "an invasion is running (" .. tostring(state.areaName) .. ", " .. state.phase .. ")"
	end
	local c = V.cfg()
	local area = areaKey and areaKey ~= "random" and I.areaByKey(c, areaKey)
	if areaKey and areaKey ~= "random" and not area then
		return false, "unknown area " .. tostring(areaKey)
	end
	local ak, fk = I.resolve(c, now(), area and area.key or "random", factionKey)
	if not ak then
		return false, "no area / faction configured"
	end
	area = I.areaByKey(c, ak)
	local faction = c.factions[fk]
	if ChaosWorldEvents and ChaosWorldEvents.stopIn then
		ChaosWorldEvents.stopIn(area.key) -- no world event where the horde arrives
	end
	local target = resolveTarget(area)
	if not target then
		return false, "the target of " .. area.key .. " has no valid tile (see /invasion check " .. area.key .. ")"
	end
	cleanupInvaders()
	local t = now()
	state.token = state.token + 1
	for k in pairs(state) do
		if k ~= "token" then
			state[k] = nil
		end
	end
	state.phase = "running"
	state.area = area
	state.areaKey = area.key
	state.areaName = area.name
	state.factionKey = fk
	state.factionName = faction.name
	state.factionColor = faction.color
	state.targetName = area.targetName or "the target"
	state.target = target
	state.startedAt = t
	state.firstWaveAt = t + (c.firstWaveSeconds or 30)
	state.endsAt = t + (c.timeLimitMinutes or 20) * 60
	state.wave = 0
	state.waves = math.max(1, (c.waves or {}).count or 5)
	state.alive = 0
	state.slain = 0
	state.planned = 0
	state.breach = 0
	state.contrib = {}
	state.mc = {}
	announce(ChaosI18n.msg("INVASION! The %s attacks %s! Defend %s: %d waves in %d minutes, the last one led by their warlord.",
		faction.name, area.name, state.targetName, state.waves, c.timeLimitMinutes or 20))
	addEvent(tick, 1000, state.token)
	addEvent(moveLoop, c.moveMs or 400, state.token)
	V.broadcastHud()
	return true
end

-- victory / defeat
finish = function(result)
	local c = C()
	local token = state.token
	breachBar(false)
	if result == "win" then
		state.phase = "ending"
		local list = giveRewards(1, state.contrib, false)
		local names = {}
		for i = 1, math.min(3, #list) do
			names[#names + 1] = string.format("%s (%d%%)", list[i].name, math.floor(list[i].share * 100 + 0.5))
		end
		announce(ChaosI18n.msg("VICTORY! %s held: the %s is broken in %s. Top defenders: %s.", state.areaName,
			state.factionName, I.clock(now() - state.startedAt), #names > 0 and table.concat(names, ", ") or "nobody"))
		V.startBuff(state.area)
		state.result = "win"
		sendAll("end", {result = "win", text = string.format("%s held!", state.areaName)})
		cleanupInvaders()
		addEvent(function(tk)
			if state.token == tk then
				state.phase = "idle"
				sendAll("hide", {})
			end
		end, 20000, token)
		return
	end
	state.result = result
	sendAll("end", {result = result, text = result == "breach" and string.format("%s has fallen!", state.areaName)
		or string.format("Time is up: %s is overrun!", state.areaName)})
	announce(ChaosI18n.msg("DEFEAT! %s %s. The %s occupies it for %d minutes: slay the occupiers to free it.",
		state.areaName, result == "breach" and "has fallen" or "could not be held in time", state.factionName,
		(c.occupation or {}).minutes or 30))
	occupy()
end

-- the invaders stay: survivors stop pushing and toughen up, a garrison joins them at the target
occupy = function()
	local c = C()
	local o = c.occupation or {}
	state.phase = "occupied"
	state.occupation = {endsAt = now() + (o.minutes or 30) * 60, alive = 0}
	state.libContrib = {}
	for id, info in pairs(V.invaders) do
		local m = Monster(id)
		if m then
			info.occupier = true
			scaleMonster(m, {hp = o.hpMult or 1.5})
		end
	end
	local faction = c.factions[state.factionKey]
	local roster = I.roster(faction, state.area.level, c.scaling)
	local spots = {}
	for r = 1, 4 do
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local p = {x = state.target.x + dx, y = state.target.y + dy, z = state.target.z}
					if V.tileOk(P(p), state.area) then
						spots[#spots + 1] = p
					end
				end
			end
		end
	end
	local weights = o.garrisonTiers or {rare = 70, legendary = 30}
	for k = 1, math.min(o.garrison or 6, #spots) do
		local m = roster[math.random(#roster)]
		local tier = math.random(100) <= (weights.legendary or 0) and "legendary" or "rare"
		local sc = I.scale(m.level, state.area.level, c.scaling)
		local mon = spawnOne(m.name, spots[k], tier, sc, {occupier = true})
		if mon then
			scaleMonster(mon, {hp = o.hpMult or 1.5})
		end
	end
	local alive = 0
	for id in pairs(V.invaders) do
		if Monster(id) then
			alive = alive + 1
		end
	end
	state.occupation.alive = alive
	addEvent(tick, 1000, state.token) -- finish() ended the running tick
	if ChaosAchievements then -- guarded: achievements.lua
		for guid, e in pairs(state.contrib or {}) do
			ChaosAchievements.progress({guid = guid, name = e.name}, "invasion_fought", 1)
		end
	end
	V.broadcastHud()
end

function V.endOccupation(how)
	local token = state.token
	if how == "liberated" then
		local list = giveRewards((C().rewards or {}).liberationMult or 0.25, state.libContrib or {}, true)
		announce(ChaosI18n.msg("%s is liberated! The last occupier is slain (%d defender%s rewarded).", state.areaName, #list,
			#list == 1 and "" or "s"))
		sendAll("end", {result = "liberated", text = string.format("%s is free again!", state.areaName)})
	else
		announce(ChaosI18n.msg("The %s withdraws from %s.", state.factionName, state.areaName))
		sendAll("end", {result = "withdrawn", text = string.format("The occupiers leave %s.", state.areaName)})
	end
	cleanupInvaders()
	state.phase = "ending"
	addEvent(function(tk)
		if state.token == tk then
			state.phase = "idle"
			sendAll("hide", {})
		end
	end, 15000, token)
end

function V.stop()
	if state.phase == "idle" then
		return false
	end
	state.token = state.token + 1
	cleanupInvaders()
	breachBar(false)
	state.phase = "idle"
	sendAll("hide", {})
	announce(ChaosI18n.msg("The invasion of %s was called off.", tostring(state.areaName)))
	return true
end

function V.isOccupied(areaKey)
	return state.phase == "occupied" and (areaKey == nil or state.areaKey == areaKey)
end

-- ======================================================================== rewards
local function giveStack(player, id, count)
	local added = Chaos.giveItem(player, id, count)
	local rest = count - added
	if rest > 0 then
		local inbox = player:getInbox()
		while inbox and rest > 0 do
			local n = math.min(rest, 100)
			inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
		end
		return true
	end
	return false
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

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

-- a unique through the Chaos loot layer: its own roll for the boss first, else any unique (not boss-only, not
-- blocked for the player's season) up to the area level + levelSlack
local function pickUnique(player, r)
	local L = ChaosLoot
	if not L then
		return nil
	end
	local level = r.areaLevel or 1
	local itemFind = L.itemFindMult and L.itemFindMult(player) or 1
	local bossType = r.bossType or r.bossName
	if L.rollUniques and bossType then
		local hits = L.rollUniques("boss", bossType, level, itemFind * 20, nil, player)
		if hits[1] then
			return hits[1]
		end
	end
	local cands = {}
	local slack = (C().rewards or {}).uniqueLevelSlack or 20
	for _, e in ipairs(L.uniqueList and L.uniqueList() or {}) do
		local blocked = e.season and ChaosSeason and ChaosSeason.uniqueBlocked and ChaosSeason.uniqueBlocked(e.season, player)
		if not e.bossOnly and not blocked and (tonumber(e.level) or 0) <= level + slack then
			cands[#cands + 1] = e
		end
	end
	return cands[1] and cands[math.random(#cands)] or nil
end

function V.deliver(player, r)
	local inboxUsed = false
	if r.bank and r.bank > 0 then
		player:setBankBalance(player:getBankBalance() + r.bank)
	end
	local parts = {}
	for _, it in ipairs(r.items) do
		inboxUsed = giveStack(player, it.id, it.count) or inboxUsed
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	if r.unique then
		local e = pickUnique(player, r)
		local item = e and Game.createItem(e.id, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			inboxUsed = giveEx(player, item) or inboxUsed
			parts[#parts + 1] = "the unique " .. tostring(e.name)
			announce(ChaosI18n.msg("%s received the unique %s for defending %s!", player:getName(), tostring(e.name), tostring(r.areaName)), false)
		end
	end
	local text = string.format("%s reward (rank %d, %d%% of the defence): %d gold to your bank%s%s.%s",
		r.liberation and "Liberation" or "Invasion", r.rank, math.floor(r.share * 100 + 0.5), r.bank or 0,
		#parts > 0 and ", " or "", table.concat(parts, ", "),
		inboxUsed and " Your backpack was full: the rest is in your inbox." or "")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	toast(player, text)
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
end

giveRewards = function(mult, contrib, liberation)
	local c = C()
	local excluded = {}
	if not (c.rewards or {}).mcReward then
		for guid in pairs(state.mc or {}) do
			excluded[guid] = true
		end
	end
	-- players below minLevel get nothing
	local unit = state.unit or 0
	local totalHp = (state.unitSum or 0)
	local minPoints = totalHp * ((c.contribution or {}).minPercent or 0) / 100
	local list = I.shares(contrib, c.contribution, unit, minPoints, excluded)
	local rewards = I.rewards(list, c.rewards or {}, state.area.level, mult, math.random)
	for _, r in ipairs(rewards) do
		r.areaLevel = state.area.level
		r.areaName = state.areaName
		r.bossName = state.bossName
		r.bossType = state.bossType
		r.liberation = liberation
		local who = {guid = r.guid, name = r.name}
		if not liberation and ChaosLeaderboard and ChaosLeaderboard.record then -- weekly Defender board
			ChaosLeaderboard.record("defender", who, r.points, "add")
		end
		if ChaosAchievements then -- guarded: achievements.lua (another module)
			local e = contrib[r.guid] or {}
			if liberation then
				ChaosAchievements.progress(who, "invasion_liberated", 1)
			else
				ChaosAchievements.progress(who, "invasion_defended", 1)
				if r.rank == 1 then
					ChaosAchievements.progress(who, "invasion_top", 1)
				end
				if (e.boss or 0) > 0 then
					ChaosAchievements.progress(who, "invasion_boss", 1)
				end
			end
			if (e.kills or 0) > 0 then
				ChaosAchievements.progress(who, "invasion_kills", e.kills)
			end
		end
		local player = Player(r.name)
		if player and player:getGuid() == r.guid then
			V.deliver(player, r)
			if ChaosCharms and ChaosCharms.onSource then -- a charm drop (charms.lua)
				pcall(ChaosCharms.onSource, player, "invasion", {level = r.areaLevel, rank = r.rank})
			end
		else
			V.pending[r.guid] = V.pending[r.guid] or {}
			table.insert(V.pending[r.guid], r)
		end
	end
	-- the ones who fought but get nothing are told why
	local got = {}
	for _, s in ipairs(list) do
		got[s.guid] = true
	end
	for guid, e in pairs(contrib) do
		local player = Player(e.name)
		if player and player:getGuid() == guid and not got[guid] then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, excluded[guid]
				and "No invasion reward: another character from your connection was online during the fight."
				or "No invasion reward: your part in the defence was too small.")
		end
	end
	return list
end

-- ======================================================================== Victory buff
function V.startBuff(area)
	local v = C().victory or {}
	if (v.minutes or 0) <= 0 or (v.xp or 1) <= 1 then
		return
	end
	local t = now()
	V.buff = {endsAt = t + v.minutes * 60, xp = v.xp, scope = v.scope or "server", areaKey = area.key, name = area.name,
		area = area}
	local pct = math.floor((v.xp - 1) * 100 + 0.5)
	-- server-wide: an entry of the events calendar (events_schedule.lua applies its xp bonus, !events lists it)
	if V.buff.scope == "server" and ChaosEvents and ChaosEvents.dynamic then
		ChaosEvents.dynamic.invasionVictory = {id = "invasionVictory", name = "Victory of " .. area.name,
			description = string.format("+%d%% experience for everyone until %s.", pct, os.date("%H:%M", V.buff.endsAt)),
			bonus = {xp = v.xp}, untilTime = V.buff.endsAt}
		V.buff.viaEvents = true
	end
	announce(ChaosI18n.msg("Victory buff: +%d%% experience %s for %d minutes!", pct,
		V.buff.scope == "area" and ("in " .. area.name) or "for everyone", v.minutes))
end

local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if not source or not source:isMonster() then
		return exp
	end
	local id = source:getId()
	local info = V.invaders[id]
	local scale = info and info.scale or V.recent[id]
	if scale and scale.xp and scale.xp ~= 1 then
		exp = math.floor(exp * scale.xp)
	end
	local b = V.buff
	if b and I.buffActive(b, now()) and not b.viaEvents then
		if b.scope ~= "area" or I.inArea(self:getPosition(), b.area) then
			exp = math.floor(exp * b.xp)
		end
	end
	return exp
end
xpCb:register()

-- ======================================================================== engine hooks
-- invaders are renamed before they are placed (the name the clients see first)
local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if pendingRename then
		self:rename(pendingRename)
		pendingRename = nil
	end
	return true
end
spawnCb:register()

local function creditPlayer(contrib, player, field, amount)
	local guid = player:getGuid()
	local e = I.credit(contrib, guid, player:getName(), field, amount)
	if e and not e.mcChecked then
		e.mcChecked = true
		if Chaos.isMultiClient and Chaos.isMultiClient(player) then
			state.mc[guid] = true
		end
	end
	return e
end

local function activeContrib()
	if state.phase == "running" then
		return state.contrib
	elseif state.phase == "occupied" then
		return state.libContrib
	end
	return nil
end

local health = CreatureEvent("ChaosInvasionHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local contrib = activeContrib()
	if contrib and primaryType ~= COMBAT_HEALING and V.invaders[creature:getId()] then
		local dmg = math.abs(primaryDamage) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage) or 0)
		dmg = math.min(dmg, creature:getHealth())
		local player = playerOf(attacker)
		if player and dmg > 0 then
			local e = creditPlayer(contrib, player, "damage", dmg)
			if e and V.invaders[creature:getId()].boss then
				e.boss = (e.boss or 0) + dmg
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:register()

local death = CreatureEvent("ChaosInvasionDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local id = creature:getId()
	local info = V.invaders[id]
	if not info then
		return true
	end
	V.invaders[id] = nil
	V.recent[id] = info.scale
	addEvent(function(cid) V.recent[cid] = nil end, 5000, id)
	state.alive = math.max(0, (state.alive or 0) - 1)
	if info.wave and info.wave == state.wave then
		state.waveAlive = math.max(0, (state.waveAlive or 0) - 1)
	end
	state.slain = (state.slain or 0) + 1
	local contrib = activeContrib()
	if contrib then
		local credited = {}
		for _, cr in ipairs({killer, mostDamageKiller}) do
			local p = playerOf(cr)
			if p and not credited[p:getGuid()] then
				credited[p:getGuid()] = true
				creditPlayer(contrib, p, "kills", 1)
			end
		end
	end
	if info.boss and id == state.bossId then
		state.bossAlive = false
		state.bossHp = 0
		local p = playerOf(mostDamageKiller) or playerOf(killer)
		announce(p and ChaosI18n.msg("%s is slain by %s!", tostring(state.bossName), p:getName()) or ChaosI18n.msg("%s is slain!", tostring(state.bossName)))
	end
	return true
end
death:register()

-- on players: the invaders' damage scaling, and healing done to other players inside the area
local playerHit = CreatureEvent("ChaosInvasionPlayer")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if state.phase == "idle" or not attacker then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if primaryType == COMBAT_HEALING then
		local contrib = activeContrib()
		local healer = playerOf(attacker)
		if contrib and healer and healer ~= creature and creature:isPlayer() and I.inArea(creature:getPosition(), state.area, 10) then
			local amount = math.min(math.abs(primaryDamage), creature:getMaxHealth() - creature:getHealth())
			if amount > 0 then
				creditPlayer(contrib, healer, "healing", amount)
			end
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local info = attacker:isMonster() and V.invaders[attacker:getId()]
	if info and info.scale and info.scale.dmg and info.scale.dmg ~= 1 then
		primaryDamage = math.floor(primaryDamage * info.scale.dmg)
		secondaryDamage = math.floor(secondaryDamage * info.scale.dmg)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
playerHit:register()

local login = CreatureEvent("ChaosInvasionLogin")
function login.onLogin(player)
	player:registerEvent("ChaosInvasionPlayer")
	player:registerEvent("ChaosInvasionOpcode")
	local guid = player:getGuid()
	local list = V.pending[guid]
	if list then
		V.pending[guid] = nil
		addEvent(function(name, rewards)
			local p = Player(name)
			if p then
				for _, r in ipairs(rewards) do
					V.deliver(p, r)
				end
			else
				V.pending[guid] = rewards
			end
		end, 2000, player:getName(), list)
	end
	return true
end
login:register()

local opcode = CreatureEvent("ChaosInvasionOpcode")
function opcode.onExtendedOpcode(player, op, buffer)
	if op ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	-- per action (ratelimit.lua): requests that hit the database cannot be flooded
	if Chaos.limited and Chaos.limited(player, "invasion." .. tostring(msg.action), 300) then
		return
	end
	if msg.action == "query" then -- the client (re)loaded: the HUD if an invasion runs
		if state.phase == "running" or state.phase == "occupied" then
			local list = hudList()
			local index = {}
			for _, e in ipairs(list) do
				index[e.guid] = e
			end
			sendHud(player, list, index)
		end
	elseif msg.action == "calendar" then
		local open = type(msg.data) == "table" and msg.data.open and true or false
		Chaos.send(player, OPCODE, "calendar", {list = V.calendar(), open = open})
	end
end
opcode:register()

-- ======================================================================== schedule
local schedule = GlobalEvent("ChaosInvasionSchedule")
function schedule.onThink(interval)
	local c = V.cfg()
	if not c.enabled then
		return true
	end
	local t = now()
	local warn = c.warnMinutes or {30, 10, 1}
	local horizon = (warn[1] or 30) * 60 + 60
	for _, s in ipairs(I.upcoming(c, t - 90, horizon + 90)) do
		local area = s.areaKey and I.areaByKey(c, s.areaKey)
		local faction = s.factionKey and c.factions[s.factionKey]
		if area and faction then
			for _, m in ipairs(warn) do
				local key = s.at .. ":" .. m
				if not V.warned[key] and t >= s.at - m * 60 and t < s.at - m * 60 + 120 and t < s.at then
					V.warned[key] = true
					announce(ChaosI18n.msg("The %s gathers: %s will be invaded in %d minute%s!", faction.name, area.name, m,
						m == 1 and "" or "s"))
				end
			end
			local key = s.at .. ":start"
			if not V.warned[key] and t >= s.at and t < s.at + 90 then
				V.warned[key] = true
				local ok, err = V.start(s.areaKey, s.factionKey)
				if not ok then
					log("scheduled start failed: " .. tostring(err))
				end
			end
		end
	end
	return true
end
schedule:interval(15000)
schedule:register()

-- the calendar on the login screen and !events: one whole-day entry per scheduled weekday (events_schedule.lua reads
-- Chaos.events.list, as siege.lua does)
local function calendarEntries()
	local c = C()
	if not (Chaos.events and Chaos.events.list) then
		return
	end
	for i = #Chaos.events.list, 1, -1 do
		local id = Chaos.events.list[i].id
		if type(id) == "string" and id:find("^invasion%d") then
			table.remove(Chaos.events.list, i)
		end
	end
	if not c.enabled then
		return
	end
	local colors = c.calendarColors or {"#c8402a", "#6a1a10"}
	for i, e in ipairs(c.schedule or {}) do
		if not e.at then
			local area = e.area and e.area ~= "random" and I.areaByKey(c, e.area)
			table.insert(Chaos.events.list, {id = "invasion" .. i, name = c.calendarName or "Invasion",
				weekdays = e.weekdays or {1, 2, 3, 4, 5, 6, 7}, colorlight = colors[1], colordark = colors[2],
				description = string.format("A horde invades %s at %02d:%02d (server time). Defend it for gold, orbs, a "
					.. "chance at a unique and a 1-hour Victory buff; Adventure > Events shows the next ones.",
					area and area.name or "a town or a hunting ground", e.hour or 20, e.minute or 0)})
		end
	end
end
calendarEntries()

-- ======================================================================== commands
local function statusText()
	local t = now()
	local lines = {}
	if state.phase == "running" then
		lines[#lines + 1] = string.format("Invasion of %s by the %s: wave %d/%d, %d invaders left, breach %d%%, %s left%s.",
			state.areaName, state.factionName, state.wave, state.waves, state.alive or 0, math.floor(state.breach + 0.5),
			I.clock(state.endsAt - t), state.bossAlive and (", boss " .. state.bossName .. " " .. (state.bossHp or 100) .. "%") or "")
	elseif state.phase == "occupied" then
		lines[#lines + 1] = string.format("%s is occupied by the %s: %d occupiers, %s left.", state.areaName,
			state.factionName, state.occupation.alive or 0, I.clock(state.occupation.endsAt - t))
	else
		lines[#lines + 1] = "No invasion is running."
	end
	local cal = V.calendar()
	if #cal > 0 then
		lines[#lines + 1] = "Upcoming:"
		for _, e in ipairs(cal) do
			lines[#lines + 1] = "- " .. e.when .. ": " .. e.name
		end
	end
	return table.concat(lines, "\n")
end
V.statusText = statusText

local gm = TalkAction("/invasion")
function gm.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local args = {}
	for w in param:gmatch("%S+") do
		args[#args + 1] = w
	end
	local cmd = (args[1] or ""):lower()
	local reply
	if cmd == "start" then
		local ok, err = V.start(args[2] or "random", args[3])
		reply = ok and ("Invasion started: " .. state.areaName .. ", " .. state.factionName .. ".") or ("Not started: " .. tostring(err))
	elseif cmd == "stop" then
		reply = V.stop() and "Invasion stopped." or "No invasion is running."
	elseif cmd == "status" or cmd == "" then
		reply = statusText()
	elseif cmd == "schedule" then
		local minutes = tonumber(args[2])
		if not minutes or minutes < 1 then
			reply = "Usage: /invasion schedule <minutes> [area|random] [faction|random]"
		else
			local at = now() + math.floor(minutes * 60)
			table.insert(C().schedule, {at = at, area = args[3] or "random", faction = args[4] or "random"})
			local ak, fk = I.resolve(V.cfg(), at, args[3] or "random", args[4])
			reply = string.format("Invasion scheduled at %s: %s, %s.", os.date("%H:%M:%S", at), tostring(ak), tostring(fk))
		end
	elseif cmd == "check" then
		local list = args[2] and {V.area(args[2])} or V.areas()
		local out = {}
		for _, a in ipairs(list) do
			out[#out + 1] = "[" .. a.key .. (a.enabled == false and ", disabled" or "") .. "] " .. (V.check(a))
		end
		reply = #out > 0 and table.concat(out, "\n") or "Unknown area."
	elseif cmd == "breach" then -- test helper: set the breach meter
		if state.phase == "running" then
			state.breach = I.clamp(tonumber(args[2]) or 0, 0, 100)
			reply = "Breach set to " .. state.breach .. "%."
		else
			reply = "No invasion is running."
		end
	elseif cmd == "wave" then -- test helper: the next wave now
		if state.phase == "running" and state.wave < state.waves then
			spawnWave(state.wave + 1)
			reply = "Wave " .. state.wave .. " sent."
		else
			reply = "No further wave."
		end
	elseif cmd == "event" then
		if ChaosWorldEvents then
			local ok, err = ChaosWorldEvents.start(args[2], args[3])
			reply = ok and ("World event started: " .. tostring(err)) or ("Not started: " .. tostring(err))
		else
			reply = "worldevents.lua is not loaded."
		end
	elseif cmd == "areas" then
		local out = {}
		for _, a in ipairs(V.areas()) do
			out[#out + 1] = string.format("%s (%s, level %d%s)", a.key, a.name, a.level, a.enabled == false and ", disabled" or "")
		end
		reply = "Areas: " .. table.concat(out, ", ") .. "\nFactions: " .. table.concat(I.factionKeys(C()), ", ")
	else
		reply = "Usage: /invasion start <area|random> [faction], stop, status, schedule <minutes> [area] [faction], " ..
			"check [area], areas, event <storm|merchant|golden|stop> [area], wave, breach <n>"
	end
	player:showTextDialog(2175, reply)
	player:sendTextMessage(MESSAGE_INFO_DESCR, reply)
	return false
end
gm:separator(" ")
gm:register()


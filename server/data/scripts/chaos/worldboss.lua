-- World boss event: five world bosses, an arena built at runtime, town portals, damage-share rewards.
-- Settings: Chaos.worldBoss in chaos_constants.lua. Monsters: data/monster/monsters/chaos/world_bosses/*.xml
-- (<flag isboss="1"/>). Overview, numbers and coordinates: server/README.md "World bosses".
--
-- Flow
--   start (schedule every Chaos.worldBoss.intervalHours, or /worldboss start [name|number|random])
--     -> arena + lobby are built with Game.createTile (refused if any tile of the footprint already exists and is
--        not ours), a forcefield (item 1387, action id aid.enter) appears next to every temple, broadcast + toast
--     -> after gatherSeconds the boss appears in the middle of the arena
--     -> phases at health thresholds: adds, enrage (a periodic pulse around the boss)
--     -> boss dies: rewards for every eligible damage dealer (not only the corpse owner), broadcast; or the fight
--        time runs out / /worldboss stop: the boss leaves, broadcast
--     -> town portals are removed, after exitDelaySeconds everybody still inside goes to their temple, the arena is
--        cleaned (monsters, corpses, loose items; walls, decor and the arena portals stay)
--   The lobby is protected by script (no combat in it, no PvP in lobby or arena unless allowPvp): dynamic tiles cannot
--   get the protection-zone flag from Lua in this engine.
--
-- Multi-client (Chaos.isMultiClient): such characters may enter and fight (the event is open to everyone and they
-- already cannot attack players), but they get no participation reward unless mcReward = true. A character counts
-- as multi-clienting if it was at entry or at any arena check (every 3 s) during the event.
--
-- Not run on a server. Assumed engine API (TFS 1.4 as in the base server source): Game.createTile(pos, true),
-- Game.createItem(id, n, pos), Item:setActionId/getActionId, Tile:getGround/getItemById/getItems/getHouse/hasProperty,
-- Game.createMonster(name, pos, false, true), Creature:setMaxHealth/addHealth, CreatureEvent healthchange/death/login,
-- MoveEvent stepin with aid, EventCallback onTargetCombat, GlobalEvent onThink/onStartup, doTargetCombatHealth,
-- Player:getInbox()/addItemEx/getBankBalance/setBankBalance, Game.createItemWithRarity, Game.getTowns.
-- The pure parts (layout, schedule, rotation, shares, rewards, phases) are tested in tests/worldboss_test.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosWorldBoss = ChaosWorldBoss or {}
local W = ChaosWorldBoss

local function C()
	return Chaos.worldBoss
end

-- ======================================================================== pure helpers (tested)

-- Geometry of arena and lobby. Every value is derived from Chaos.worldBoss.arena.
function W.layout(a)
	a = a or C().arena
	local o = a.origin
	local last = a.inner + 1
	local L = {z = o.z}
	L.arena = {x1 = o.x, y1 = o.y, x2 = o.x + last, y2 = o.y + last}
	local half = math.floor((a.inner + 1) / 2) -- integer in Lua 5.3 too (positions are table keys in tests)
	local cx, cy = o.x + half, o.y + half
	L.center = {x = cx, y = cy, z = o.z}
	local halfW = math.floor((a.lobbyInnerW + 1) / 2)
	local ly1 = L.arena.y2 + a.lobbyGap + 1
	L.lobby = {x1 = cx - halfW, y1 = ly1, x2 = cx + halfW, y2 = ly1 + a.lobbyInnerH + 1}
	local lcy = L.lobby.y1 + math.floor((a.lobbyInnerH + 1) / 2)
	L.bossSpawn = {x = cx, y = cy, z = o.z}
	L.arenaEntry = {x = cx, y = L.arena.y2 - 3, z = o.z} -- players arrive here from the lobby
	L.arenaBack = {x = cx, y = L.arena.y2 - 1, z = o.z} -- forcefield back to the lobby
	L.lobbyArrival = {x = cx, y = L.lobby.y2 - 2, z = o.z}
	L.lobbyToArena = {x = cx, y = L.lobby.y1 + 1, z = o.z}
	L.lobbyExits = {{x = L.lobby.x1 + 1, y = lcy, z = o.z}, {x = L.lobby.x2 - 1, y = lcy, z = o.z}}
	L.pillars = {}
	for _, d in ipairs({{-7, -7}, {7, -7}, {-7, 7}, {7, 7}}) do
		L.pillars[#L.pillars + 1] = {x = cx + d[1], y = cy + d[2], z = o.z}
	end
	L.basins = {
		{x = L.arena.x1 + 1, y = L.arena.y1 + 1, z = o.z}, {x = L.arena.x2 - 1, y = L.arena.y1 + 1, z = o.z},
		{x = L.arena.x1 + 1, y = L.arena.y2 - 1, z = o.z}, {x = L.arena.x2 - 1, y = L.arena.y2 - 1, z = o.z},
		{x = L.lobby.x1 + 1, y = L.lobby.y1 + 1, z = o.z}, {x = L.lobby.x2 - 1, y = L.lobby.y1 + 1, z = o.z},
		{x = L.lobby.x1 + 1, y = L.lobby.y2 - 1, z = o.z}, {x = L.lobby.x2 - 1, y = L.lobby.y2 - 1, z = o.z}
	}
	return L
end

local function inRect(r, z, pos)
	return pos ~= nil and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

function W.inArena(pos, L)
	L = L or W.layout()
	return inRect(L.arena, L.z, pos)
end

function W.inLobby(pos, L)
	L = L or W.layout()
	return inRect(L.lobby, L.z, pos)
end

function W.inside(pos, L)
	L = L or W.layout()
	return inRect(L.arena, L.z, pos) or inRect(L.lobby, L.z, pos)
end

-- Every tile of both rooms: {x, y, z, wall = bool, lobby = bool}
function W.footprint(L)
	L = L or W.layout()
	local list = {}
	for _, room in ipairs({{r = L.arena, lobby = false}, {r = L.lobby, lobby = true}}) do
		local r = room.r
		for x = r.x1, r.x2 do
			for y = r.y1, r.y2 do
				list[#list + 1] = {x = x, y = y, z = L.z, lobby = room.lobby,
					wall = (x == r.x1 or x == r.x2 or y == r.y1 or y == r.y2)}
			end
		end
	end
	return list
end

-- Next boss index. rotation: the one after `last`; random: any but `last` (when there is more than one).
function W.pickBoss(count, mode, last, rng)
	rng = rng or math.random
	last = tonumber(last) or 0
	if count <= 1 then
		return 1
	end
	if mode == "random" then
		if last < 1 or last > count then
			return rng(count)
		end
		local i = rng(count - 1)
		return i >= last and i + 1 or i
	end
	if last < 1 or last > count then
		return 1
	end
	return last % count + 1
end

-- First scheduled start strictly after `now` (server local time, full hours).
function W.nextStart(now, c)
	c = c or C()
	local interval = math.max(1, math.floor(c.intervalHours or 6))
	local offset = math.floor(c.offsetHours or 0) % interval
	local d = os.date("*t", now)
	for i = 0, 24 * 2 + interval do
		local t = os.time({year = d.year, month = d.month, day = d.day, hour = d.hour + i, min = 0, sec = 0})
		local h = os.date("*t", t).hour
		if t > now and (h - offset) % interval == 0 then
			return t
		end
	end
	return now + interval * 3600
end

-- Phases whose threshold `fraction` (health left / max health) has reached and that did not run yet.
function W.duePhases(phases, done, fraction)
	local list = {}
	for i, p in ipairs(phases or {}) do
		if not done[i] and fraction <= p.at then
			list[#list + 1] = i
		end
	end
	return list
end

-- damage = {[guid] = {damage = n, name = s}}; excluded = {[guid] = true}
-- -> sorted list {guid, name, damage, share, rank} of the eligible players, total eligible damage
function W.computeShares(damage, maxHealth, minPercent, excluded)
	excluded = excluded or {}
	local minDamage = (maxHealth or 0) * (minPercent or 0) / 100
	local list, total = {}, 0
	for guid, e in pairs(damage) do
		if not excluded[guid] and e.damage > 0 and e.damage >= minDamage then
			list[#list + 1] = {guid = guid, name = e.name, damage = e.damage}
			total = total + e.damage
		end
	end
	table.sort(list, function(a, b)
		if a.damage ~= b.damage then
			return a.damage > b.damage
		end
		return a.guid < b.guid
	end)
	for i, e in ipairs(list) do
		e.share = total > 0 and e.damage / total or 0
		e.rank = i
	end
	return list, total
end

local function addItem(map, order, id, count)
	if count <= 0 then
		return
	end
	if not map[id] then
		map[id] = 0
		order[#order + 1] = id
	end
	map[id] = map[id] + count
end

-- shares from computeShares -> list of {guid, name, share, rank, bank, items = {{id, count}}, gear, gearRarity, unique}
function W.computeRewards(shares, r, boss, uniquePool, rng)
	rng = rng or math.random
	local out = {}
	for _, s in ipairs(shares) do
		local map, order = {}, {}
		for _, it in ipairs(r.base or {}) do
			addItem(map, order, it.id, it.count)
		end
		for _, it in ipairs(r.pool or {}) do
			addItem(map, order, it.id, math.floor(it.count * s.share))
		end
		for _, it in ipairs((r.top or {})[s.rank] or {}) do
			addItem(map, order, it.id, it.count)
		end
		local items = {}
		for _, id in ipairs(order) do
			items[#items + 1] = {id = id, count = map[id]}
		end
		local reward = {guid = s.guid, name = s.name, share = s.share, rank = s.rank, damage = s.damage, items = items,
			bank = (r.bankGold or 0) + math.floor((r.bankGoldPool or 0) * s.share)}
		local gear = boss and boss.gear or {}
		if #gear > 0 and rng(10000) <= (r.gearChance or 0) + math.floor((r.gearShareBonus or 0) * s.share) then
			reward.gear = gear[rng(#gear)]
			local lo, hi = (r.gearRarity or {0, 0})[1], (r.gearRarity or {0, 0})[2]
			reward.gearRarity = rng(lo, math.max(lo, hi))
		end
		uniquePool = uniquePool or {}
		if #uniquePool > 0 and rng(10000) <= (r.uniqueChance or 0) + math.floor((r.uniqueShareBonus or 0) * s.share) then
			reward.unique = uniquePool[rng(#uniquePool)]
		end
		out[#out + 1] = reward
	end
	return out
end

-- boss-only uniques of chaos_unique_items.lua that list this boss
function W.uniquePool(bossName)
	local pool = {}
	local lname = bossName:lower()
	local list = ChaosUniqueItems or {}
	for key, e in pairs(list) do
		if type(e) == "table" and e.id and e.bossOnly then
			for _, m in ipairs(e.monsters or {}) do
				if m:lower() == lname then
					pool[#pool + 1] = e.id
					break
				end
			end
		end
	end
	table.sort(pool)
	return pool
end

-- "kael", "3", "random", "" -> boss index or nil
function W.findBoss(arg)
	local list = C().bosses
	arg = tostring(arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "" or arg == "random" then
		return nil
	end
	local n = tonumber(arg)
	if n and list[n] then
		return n
	end
	for i, b in ipairs(list) do
		if b.name:lower():find(arg, 1, true) then
			return i
		end
	end
	return false
end

-- ======================================================================== runtime state
W.state = W.state or {phase = "idle", token = 0}
W.pending = W.pending or {} -- guid -> list of rewards for players offline at the kill
local state = W.state

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function effectOf(name, fallback)
	return (name and _G["CONST_ME_" .. name:upper()]) or fallback or CONST_ME_MORTAREA
end

local function combatOf(name)
	if name == "physical" then
		return COMBAT_PHYSICALDAMAGE
	end
	return _G["COMBAT_" .. tostring(name):upper() .. "DAMAGE"] or COMBAT_PHYSICALDAMAGE
end

local function announce(text, toast)
	if Game.broadcastMessage then
		Game.broadcastMessage(text, MESSAGE_EVENT_ADVANCE)
	else
		for _, p in ipairs(Game.getPlayers()) do
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
	end
	if toast and ChaosNotify and ChaosNotify.gmBroadcast then
		ChaosNotify.gmBroadcast(nil, text)
	end
	print("[Chaos world boss] " .. text)
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

local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function bossCfg()
	return state.index and C().bosses[state.index] or nil
end

local function playersInside()
	local list = {}
	local L = W.layout()
	for _, p in ipairs(Game.getPlayers()) do
		if W.inside(p:getPosition(), L) then
			list[#list + 1] = p
		end
	end
	return list
end

-- ======================================================================== arena
local function fixedItemIds()
	local a = C().arena
	return {[a.wallId] = true, [a.pillarId] = true, [a.basinId] = true, [a.portalId] = true}
end

local function placeItem(pos, id, aid)
	local tile = Tile(pos)
	if not tile then
		return nil
	end
	local item = tile:getItemById(id)
	if not item then
		item = Game.createItem(id, 1, pos)
	end
	if item and aid and item.setActionId then
		item:setActionId(aid)
	end
	return item
end

-- returns true, or false + reason (nothing is built then)
function W.buildArena()
	local a = C().arena
	local L = W.layout()
	local foot = W.footprint(L)
	for _, t in ipairs(foot) do
		local tile = Tile(P(t))
		if tile then
			local gid = groundId(tile)
			if (gid ~= a.groundId and gid ~= a.lobbyGroundId) or (tile.getHouse and tile:getHouse()) then
				return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
			end
		end
	end
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(t.lobby and a.lobbyGroundId or a.groundId, 1, pos)
			end
			if t.wall and not tile:getItemById(a.wallId) then
				Game.createItem(a.wallId, 1, pos)
			end
		end
	end
	for _, p in ipairs(L.pillars) do
		placeItem(P(p), a.pillarId)
	end
	for _, p in ipairs(L.basins) do
		placeItem(P(p), a.basinId)
	end
	local aid = C().aid
	placeItem(P(L.arenaBack), a.portalId, aid.lobby)
	placeItem(P(L.lobbyToArena), a.portalId, aid.arena)
	for _, p in ipairs(L.lobbyExits) do
		placeItem(P(p), a.portalId, aid.exit)
	end
	return true
end

-- monsters and loose items (corpses, drops, fields) inside both rooms
local function cleanArena()
	local L = W.layout()
	local keep = fixedItemIds()
	for _, t in ipairs(W.footprint(L)) do
		if not t.wall then
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
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
end

-- ======================================================================== town portals
local function spotFree(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile.getHouse and tile:getHouse() then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH) then
		return false
	end
	if ITEM_TYPE_TELEPORT and tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return false
	end
	return true
end

function W.portalSpots()
	local c = C()
	local spots = {}
	if c.portalPositions and #c.portalPositions > 0 then
		for _, p in ipairs(c.portalPositions) do
			spots[#spots + 1] = P(p)
		end
		return spots
	end
	local allowed
	if c.towns then
		allowed = {}
		for _, id in ipairs(c.towns) do
			allowed[id] = true
		end
	end
	local seen = {}
	for _, town in ipairs(Game.getTowns()) do
		if not allowed or allowed[town:getId()] then
			local t = town:getTemplePosition()
			local key = t.x .. "," .. t.y .. "," .. t.z
			if t.x > 0 and not seen[key] then
				seen[key] = true
				for _, off in ipairs(c.portalOffsets) do
					local p = Position(t.x + off[1], t.y + off[2], t.z)
					if spotFree(p) then
						spots[#spots + 1] = p
						break
					end
				end
			end
		end
	end
	return spots
end

local function openPortals()
	state.portals = {}
	local a = C().arena
	for _, pos in ipairs(W.portalSpots()) do
		local item = Game.createItem(a.portalId, 1, pos)
		if item then
			item:setActionId(C().aid.enter)
			state.portals[#state.portals + 1] = pos
			pos:sendMagicEffect(CONST_ME_TELEPORT)
		end
	end
	state.portalsOpen = true
	return #state.portals
end

local function closePortals()
	local a = C().arena
	for _, pos in ipairs(state.portals or {}) do
		local tile = Tile(pos)
		local item = tile and tile:getItemById(a.portalId)
		if item and item:getActionId() == C().aid.enter then
			item:remove()
			pos:sendMagicEffect(CONST_ME_POFF)
		end
	end
	state.portals = {}
	state.portalsOpen = false
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

function W.deliver(player, r)
	local inboxUsed = false
	if r.bank and r.bank > 0 then
		player:setBankBalance(player:getBankBalance() + r.bank)
	end
	local parts = {}
	for _, it in ipairs(r.items) do
		inboxUsed = giveStack(player, it.id, it.count) or inboxUsed
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	if r.gear then
		local item = Game.createItemWithRarity and Game.createItemWithRarity(r.gear, 1, r.gearRarity or 0) or Game.createItem(r.gear, 1)
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
			parts[#parts + 1] = "the unique " .. (e and e.name or itemName(r.unique))
			announce(player:getName() .. " received the unique " .. (e and e.name or itemName(r.unique)) .. " from the world boss!", false)
		end
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"World boss reward (rank %d, %.1f%% of the damage): %d gold to your bank, %s.%s",
		r.rank, r.share * 100, r.bank or 0, table.concat(parts, ", "),
		inboxUsed and " Your backpack was full: the rest is in your inbox." or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
end

local function distribute()
	local c = C()
	local boss = bossCfg()
	local excluded = {}
	if not c.mcReward then
		for guid in pairs(state.mc or {}) do
			excluded[guid] = true
		end
	end
	local shares, total = W.computeShares(state.damage or {}, state.maxHealth or 0, c.reward.minDamagePercent, excluded)
	local rewards = W.computeRewards(shares, c.reward, boss, W.uniquePool(boss.name))
	if ChaosLeaderboard and ChaosLeaderboard.recordShares then ChaosLeaderboard.recordShares(shares) end -- leaderboard.lua
	for _, r in ipairs(rewards) do
		local player = Player(r.name)
		if player and player:getGuid() == r.guid then
			W.deliver(player, r)
		else
			W.pending[r.guid] = W.pending[r.guid] or {}
			table.insert(W.pending[r.guid], r)
		end
	end
	-- the ones who fought but get nothing are told why
	for guid, e in pairs(state.damage or {}) do
		local player = Player(e.name)
		if player and player:getGuid() == guid then
			local got = false
			for _, s in ipairs(shares) do
				if s.guid == guid then
					got = true
					break
				end
			end
			if not got then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, excluded[guid]
					and "No world boss reward: another character from your connection was online during the fight."
					or string.format("No world boss reward: you need at least %.2f%% of the boss health in damage.", c.reward.minDamagePercent))
			end
		end
	end
	return shares, total
end

-- ======================================================================== event flow
local function sendBossInfo(boss, players)
	if not (Chaos.send and ChaosOpcodes and ChaosOpcodes.monsterbar) then
		return
	end
	for _, p in ipairs(players) do
		if W.inArena(p:getPosition()) then
			Chaos.send(p, ChaosOpcodes.monsterbar, "info", {cid = boss:getId(), tier = "boss", name = boss:getName(), mods = {}})
		end
	end
end

local function randomNear(center, radius)
	local L = W.layout()
	for _ = 1, 10 do
		local x = center.x + math.random(-radius, radius)
		local y = center.y + math.random(-radius, radius)
		if x > L.arena.x1 and x < L.arena.x2 and y > L.arena.y1 and y < L.arena.y2 then
			return Position(x, y, L.z)
		end
	end
	return P(L.bossSpawn)
end

local function runPhase(token, i)
	if state.token ~= token or state.phase ~= "fight" then
		return
	end
	local boss = Monster(state.bossId)
	local b = bossCfg()
	local phase = b.phases[i]
	if not boss or not phase then
		return
	end
	if phase.yell then
		boss:say(phase.yell, TALKTYPE_MONSTER_YELL)
	end
	if phase.adds and MonsterType(phase.adds.name) then
		local pos = boss:getPosition()
		for _ = 1, phase.adds.count do
			local m = Game.createMonster(phase.adds.name, randomNear(pos, 4), false, true)
			if m then
				if phase.adds.health then
					m:setMaxHealth(phase.adds.health)
					m:addHealth(phase.adds.health)
				end
				state.adds[m:getId()] = true
				m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			end
		end
	end
	if phase.enrage then
		state.enraged = true
		state.nextPulse = os.time() + (b.pulse and b.pulse.every or 8)
		boss:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
	end
end

local function pulse(boss, b)
	local p = b.pulse
	if not p then
		return
	end
	local pos = boss:getPosition()
	local effect = effectOf(p.effect)
	pos:sendMagicEffect(effect)
	local hits = 0
	for _, target in ipairs(Game.getSpectators(pos, false, true, p.radius, p.radius, p.radius, p.radius)) do
		if W.inArena(target:getPosition()) then
			doTargetCombatHealth(boss, target, combatOf(p.type), -p.min, -p.max, effect)
			hits = hits + 1
		end
	end
	if p.healPerHit and hits > 0 then
		boss:addHealth(p.healPerHit * hits)
	end
end

local function tick(token)
	if state.token ~= token or state.phase == "idle" then
		return
	end
	local inside = playersInside()
	for _, p in ipairs(inside) do
		if Chaos.isMultiClient and Chaos.isMultiClient(p) then
			state.mc[p:getGuid()] = true
		end
	end
	local boss = state.bossId and Monster(state.bossId)
	if boss and state.phase == "fight" then
		sendBossInfo(boss, inside)
		if state.enraged and os.time() >= (state.nextPulse or 0) then
			local b = bossCfg()
			pulse(boss, b)
			state.nextPulse = os.time() + (b.pulse and b.pulse.every or 8)
		end
	end
	addEvent(tick, 3000, token)
end

local finish

local function spawnBoss(token)
	if state.token ~= token or state.phase ~= "gather" then
		return
	end
	local b = bossCfg()
	local L = W.layout()
	local boss = Game.createMonster(b.name, P(L.bossSpawn), false, true)
	if not boss then
		announce("The world boss could not appear. The event is cancelled.", true)
		finish(false, "spawn failed")
		return
	end
	state.bossId = boss:getId()
	state.maxHealth = boss:getMaxHealth()
	state.phase = "fight"
	state.fightStart = os.time()
	state.fightEnd = os.time() + C().fightMinutes * 60
	boss:registerEvent("ChaosWorldBossHealth")
	boss:registerEvent("ChaosWorldBossDeath")
	boss:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
	boss:say(b.intro, TALKTYPE_MONSTER_YELL)
	announce(string.format("%s has appeared in the world boss arena! You have %d minutes to bring it down.", b.name, C().fightMinutes), true)
	addEvent(function(t)
		if state.token == t and state.phase == "fight" then
			finish(false, "time")
		end
	end, C().fightMinutes * 60 * 1000, token)
end

local function closeOut(token)
	if state.token ~= token then
		return
	end
	for _, p in ipairs(playersInside()) do
		p:teleportTo(p:getTown():getTemplePosition())
		p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
	cleanArena()
	W.state = {phase = "idle", token = token + 1}
	state = W.state
	W.nextAt = C().enabled and W.nextStart(os.time()) or nil
end

-- victory = true when the boss died. reason: "kill", "time", "stop", "spawn failed"
finish = function(victory, reason)
	if state.phase == "idle" or state.phase == "ending" then
		return false
	end
	local b = bossCfg()
	state.phase = "ending"
	state.token = state.token + 1
	local token = state.token
	closePortals()
	for id in pairs(state.adds or {}) do
		local m = Monster(id)
		if m then
			m:getPosition():sendMagicEffect(CONST_ME_POFF)
			m:remove()
		end
	end
	local delay = C().exitDelaySeconds
	if victory then
		local shares = distribute()
		local secs = os.time() - (state.fightStart or os.time())
		local top = {}
		for i = 1, math.min(3, #shares) do
			top[#top + 1] = string.format("%s (%.1f%%)", shares[i].name, shares[i].share * 100)
		end
		announce(string.format("%s has been slain by %d champion(s) in %dm %02ds! Top damage: %s. Everyone inside returns home in %d seconds.",
			b.name, #shares, math.floor(secs / 60), secs % 60, #top > 0 and table.concat(top, ", ") or "nobody", delay), true)
	else
		local boss = state.bossId and Monster(state.bossId)
		if boss then
			boss:say("You are not worthy of my death.", TALKTYPE_MONSTER_YELL)
			boss:getPosition():sendMagicEffect(CONST_ME_POFF)
			boss:remove()
		end
		if reason == "stop" then
			delay = math.min(delay, 10)
			announce("The world boss event was stopped by the staff.", true)
		elseif reason == "time" then
			announce(string.format("%s was not defeated in time and withdraws. The world boss event is over.", b.name), true)
		end
	end
	addEvent(closeOut, delay * 1000, token)
	return true
end

-- index = boss index (nil = by mode). Returns true or false + reason.
function W.start(index)
	local c = C()
	if state.phase ~= "idle" then
		return false, "a world boss event is already running"
	end
	if not index then
		index = W.pickBoss(#c.bosses, c.mode, Game.getStorageValue(c.rotationStorage))
	end
	local b = c.bosses[index]
	if not b then
		return false, "unknown boss"
	end
	if not MonsterType(b.name) then
		return false, b.name .. " is not loaded (register world_bosses/*.xml in monsters.xml)"
	end
	local ok, err = W.buildArena()
	if not ok then
		return false, "arena not built: " .. err
	end
	Game.setStorageValue(c.rotationStorage, index)
	local token = state.token + 1
	W.state = {phase = "gather", token = token, index = index, damage = {}, mc = {}, adds = {}, phasesDone = {},
		startedAt = os.time(), spawnAt = os.time() + c.gatherSeconds, portalsUntil = os.time() + c.portalMinutes * 60}
	state = W.state
	local n = openPortals()
	announce(string.format("WORLD BOSS: %s Portals are open next to the temples for %d minutes (level %d+). The boss appears in %d seconds.",
		b.intro, c.portalMinutes, c.minLevel, c.gatherSeconds), true)
	if n == 0 then
		print("[Chaos world boss] no portal spot found (Game.getTowns / portalPositions)")
	end
	addEvent(spawnBoss, c.gatherSeconds * 1000, token)
	addEvent(function(t)
		if state.token == t and state.portalsOpen then
			closePortals()
			announce("The world boss portals have closed.", false)
		end
	end, c.portalMinutes * 60 * 1000, token)
	addEvent(tick, 3000, token)
	return true
end

function W.stop()
	return finish(false, "stop")
end

function W.status()
	local c = C()
	if state.phase == "idle" then
		local nextAt = W.nextAt
		if c.enabled and nextAt then
			local b = c.bosses[W.pickBoss(#c.bosses, c.mode, Game.getStorageValue(c.rotationStorage))]
			return string.format("No world boss is active. Next one at %s%s.", os.date("%H:%M", nextAt),
				c.mode == "rotation" and (": " .. b.name) or "")
		end
		return "No world boss is active."
	end
	local b = bossCfg()
	if state.phase == "gather" then
		return string.format("%s appears in %d seconds. Portals are next to the temples.", b.name, math.max(0, state.spawnAt - os.time()))
	elseif state.phase == "fight" then
		local boss = Monster(state.bossId)
		local pct = boss and math.floor(boss:getHealth() * 100 / boss:getMaxHealth()) or 0
		return string.format("%s is fighting (%d%% health, %d minutes left).%s", b.name, pct,
			math.max(0, math.ceil((state.fightEnd - os.time()) / 60)), state.portalsOpen and " Portals are open." or "")
	end
	return "The world boss event is ending."
end

-- ======================================================================== engine hooks
local health = CreatureEvent("ChaosWorldBossHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if state.phase == "fight" and creature:getId() == state.bossId and primaryType ~= COMBAT_HEALING then
		local dmg = math.abs(primaryDamage) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage) or 0)
		dmg = math.min(dmg, creature:getHealth())
		local player = playerOf(attacker)
		if player and dmg > 0 then
			local guid = player:getGuid()
			local e = state.damage[guid]
			if not e then
				e = {damage = 0, name = player:getName()}
				state.damage[guid] = e
			end
			e.damage = e.damage + dmg
		end
		local b = bossCfg()
		local fraction = (creature:getHealth() - dmg) / creature:getMaxHealth()
		for _, i in ipairs(W.duePhases(b.phases, state.phasesDone, fraction)) do
			state.phasesDone[i] = true
			addEvent(runPhase, 100, state.token, i)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:register()

local death = CreatureEvent("ChaosWorldBossDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	if creature:getId() == state.bossId and state.phase == "fight" then
		finish(true, "kill")
	end
	return true
end
death:register()

local login = CreatureEvent("ChaosWorldBossLogin")
function login.onLogin(player)
	local guid = player:getGuid()
	local list = W.pending[guid]
	if list then
		W.pending[guid] = nil
		addEvent(function(name, rewards)
			local p = Player(name)
			if p then
				for _, r in ipairs(rewards) do
					W.deliver(p, r)
				end
			else
				W.pending[guid] = rewards
			end
		end, 2000, player:getName(), list)
	end
	if state.phase == "idle" and W.inside(player:getPosition()) then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	return true
end
login:register()

-- no PvP in arena and lobby, no combat at all against players in the lobby
local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target or not target:isPlayer() then
		return RETURNVALUE_NOERROR
	end
	local L = W.layout()
	local tpos = target:getPosition()
	if not W.inside(tpos, L) then
		return RETURNVALUE_NOERROR
	end
	if W.inLobby(tpos, L) or W.inLobby(creature:getPosition(), L) then
		return RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE
	end
	if not C().allowPvp and playerOf(creature) and playerOf(creature) ~= target then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

-- forcefields
local function pushBack(player, fromPosition, text)
	player:sendCancelMessage(text)
	player:teleportTo(fromPosition, true)
end

local function open()
	return state.phase == "gather" or state.phase == "fight"
end

local enter = MoveEvent()
function enter.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local c = C()
	if not open() or not state.portalsOpen then
		pushBack(player, fromPosition, "The world boss portal is closed.")
		return true
	end
	if player:getLevel() < c.minLevel then
		pushBack(player, fromPosition, string.format("You need level %d to face the world boss.", c.minLevel))
		return true
	end
	if c.maxPlayers > 0 and #playersInside() >= c.maxPlayers then
		pushBack(player, fromPosition, "The world boss arena is full.")
		return true
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(player) then
		state.mc[player:getGuid()] = true
		if not c.mcReward then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
				"Another character from your connection is online: you may fight, but you will get no world boss reward.")
		end
	end
	player:teleportTo(P(W.layout().lobbyArrival))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "World boss lobby: the forcefield to the north leads to the arena, the ones on the sides take you home. " .. W.status())
	return true
end
enter:type("stepin")
enter:aid(Chaos.worldBoss.aid.enter)
enter:register()

local toArena = MoveEvent()
function toArena.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	if not open() then
		pushBack(player, fromPosition, "There is no fight in the arena right now.")
		return true
	end
	player:teleportTo(P(W.layout().arenaEntry))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
toArena:type("stepin")
toArena:aid(Chaos.worldBoss.aid.arena)
toArena:register()

local toLobby = MoveEvent()
function toLobby.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	player:teleportTo(P(W.layout().lobbyArrival))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
toLobby:type("stepin")
toLobby:aid(Chaos.worldBoss.aid.lobby)
toLobby:register()

local exit = MoveEvent()
function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	player:teleportTo(player:getTown():getTemplePosition())
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
exit:type("stepin")
exit:aid(Chaos.worldBoss.aid.exit)
exit:register()

-- schedule
local warned = {}
local schedule = GlobalEvent("ChaosWorldBossSchedule")
function schedule.onThink(interval)
	local c = C()
	if not c.enabled then
		return true
	end
	local now = os.time()
	W.nextAt = W.nextAt or W.nextStart(now)
	if state.phase ~= "idle" then
		return true
	end
	for _, m in ipairs(c.warnMinutes or {}) do
		local key = W.nextAt .. ":" .. m
		if not warned[key] and now >= W.nextAt - m * 60 and now < W.nextAt then
			warned[key] = true
			local b = c.bosses[W.pickBoss(#c.bosses, c.mode, Game.getStorageValue(c.rotationStorage))]
			announce(string.format("A world boss awakens in %d minute(s)%s! Portals will open next to the temples.", m,
				c.mode == "rotation" and (": " .. b.name) or ""), m == (c.warnMinutes or {})[1])
		end
	end
	if now >= W.nextAt then
		W.nextAt = W.nextStart(now)
		local ok, err = W.start()
		if not ok then
			print("[Chaos world boss] scheduled start failed: " .. tostring(err))
		end
	end
	return true
end
schedule:interval(30000)
schedule:register()

-- commands
local gm = TalkAction("/worldboss")
function gm.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local cmd, arg = param:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "start" then
		local index = W.findBoss(arg)
		if index == false then
			player:sendCancelMessage("Unknown boss. Bosses: " .. (function()
				local names = {}
				for i, b in ipairs(C().bosses) do
					names[#names + 1] = i .. " " .. b.name
				end
				return table.concat(names, ", ")
			end)())
			return false
		end
		if index == nil and arg:lower() == "random" then
			index = W.pickBoss(#C().bosses, "random", Game.getStorageValue(C().rotationStorage))
		end
		local ok, err = W.start(index)
		player:sendTextMessage(MESSAGE_INFO_DESCR, ok and "World boss event started." or ("Not started: " .. tostring(err)))
	elseif cmd == "stop" then
		player:sendTextMessage(MESSAGE_INFO_DESCR, W.stop() and "World boss event stopped." or "No world boss event is running.")
	elseif cmd == "arena" then
		-- builds the arena if needed (check the footprint without starting an event) and takes you to the lobby
		local ok, err = W.buildArena()
		if not ok then
			player:sendCancelMessage("Arena not built: " .. tostring(err))
			return false
		end
		player:teleportTo(P(W.layout().lobbyArrival))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, W.status() .. "\nUsage: /worldboss start [name|number|random], /worldboss stop, /worldboss arena")
	end
	return false
end
gm:separator(" ")
gm:register()

local info = TalkAction("!worldboss")
function info.onSay(player, words, param)
	player:sendTextMessage(MESSAGE_INFO_DESCR, W.status())
	return false
end
info:separator(" ")
info:register()

local startup = GlobalEvent("ChaosWorldBossStartup")
function startup.onStartup()
	W.nextAt = C().enabled and W.nextStart(os.time()) or nil
	return true
end
startup:register()

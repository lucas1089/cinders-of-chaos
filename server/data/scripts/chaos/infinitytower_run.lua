-- Infinity Tower: the run itself (instance, floors, waves, bosses, rewards).
--
-- A run happens in an arena that is BUILT AT RUNTIME with Game.createTile (dynamic tiles, never saved)
-- in a part of the map that has no tiles, so no map editing is needed. Each running group gets one of
-- `maxSlots` arenas side by side. Floors are waves: kill everything to open the next floor; every
-- `bossEvery`-th floor is a boss floor. Monsters get the health of their floor (infinitytower_balance_config.lua:
-- a curve with a sawtooth, derived with tools/tower_model.py so the floor dies in about what a base hunt pack of its
-- level does), more tier/modifier chances (monster_tiers.lua) as the floors rise, and drop tower items. Every fifth
-- floor pays a reward (first clear per character and tower season, and every time). When a run ends each player's cleared
-- floors are recorded with ChaosTower.recordRun (points, best floor, ranking, milestones in infinitytower.lua).
--
-- Entry: "!tower start" or the Enter button of the client window (action "enter"); "!tower leave" leaves.
-- A party leader takes the party members who are close; solo works too.
--
-- Not run on a server: assumed API Game.createTile(pos, true), Tile:addItem, Game.createMonster, Creature:remove,
-- Position:getDistance, Player:teleportTo, CreatureEvent "death"/"logout"/"login". The floor planner and the
-- run bookkeeping are covered by server/tests/infinitytower_run_test.lua (mocked engine).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

if not ChaosTowerBalanceCore then
	dofile("data/scripts/chaos/infinitytower_balance_core.lua")
end
ChaosTowerBalance = dofile("data/scripts/chaos/infinitytower_balance_config.lua")
local B = ChaosTowerBalanceCore
local BC = ChaosTowerBalance

if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end
if not ChaosDarkTiles then
	dofile("data/lib/chaos_dark_tiles.lua")
end

ChaosTowerRun = ChaosTowerRun or {}

local function bossNames()
	local names = {}
	for i, b in ipairs(BC.bosses) do
		names[i] = b.name
	end
	return names
end

local cfg = {
	arenaBase = {x = 2000, y = 2000, z = 7}, -- top-left corner of slot 0; this part of the map has no tiles
	slotSpacing = 40,
	maxSlots = 16,
	inner = 25, -- inner width and height of the arena (odd; O276: 19 -> 25, room to kite; slotSpacing 40 holds 27)
	spawnRadius = 6, -- monsters appear within this distance of the middle (players start there)
	spawnMinDistance = 3, -- ... but not closer than this
	groundId = 413, -- "stone floor"
	wallId = 5648, -- "stone wall"
	-- O276 look (arenalook_core.lua): every run gets one theme and one layout variant in turn (the same hash of the
	-- coordinates every time, so the layout of a variant never changes): varied ground with borders, a rim along the wall
	-- with rubble, mirrored cover pieces that never touch each other or the spawn ring, lights against the wall and a
	-- paved lane from the south wall to the middle. The theme "dark" is the dark tile set when it is installed (else the
	-- ember theme). Nothing solid within keepRadius of the middle (the group starts there; monsters appear around it).
	look = {themes = {"ember", "stone", "crypt", "dark"}, variants = 6, keepRadius = 3, cover = 5, lights = 8},
	minLevel = 100,
	maxPartySize = 4,
	partyRange = 12, -- members farther than this from the leader stay out
	floorTimeLimit = 300, -- seconds per floor
	-- a boss floor gets floorTimeLimit x this (600 s): a boss lives 45-90 s for the median class at its floor's level
	-- (tools/tower_model.py), 5 minutes at most for the weakest class
	bossFloorTimeMult = 2,
	-- instance limits (instance_limits.lua, server/README.md "Instance limits"): a whole run lasts at most runTimeLimit
	-- seconds (0 = no limit); then it ends like a lost floor: everyone back where they entered, the floors cleared so far
	-- are recorded (gold was paid per floor). 60 minutes: about 30 floors at two minutes a floor, three bosses deep; the
	-- weekly ranking is by floors, so a long run cannot hold a slot for hours. Warnings at warnAt seconds left of the run
	-- and at floorWarnAt seconds left of a floor; at most maxRuns runs (maxSlots arenas); a group that finds every arena
	-- busy waits in line and is told when one frees up. A run ends at once when its last player is out.
	runTimeLimit = 3600,
	limits = {warnAt = {300, 60, 10}, floorWarnAt = {60, 10}, maxRuns = 16, waitlist = true},
	startDelay = 5, -- seconds before floor 1
	nextFloorDelay = 6, -- seconds between floors
	-- "Next floor now" (client button / hotkey, action "skip" of opcode 214): during the start delay or the pause between
	-- floors it starts the next floor at once. Floors have no waves (all monsters of a floor appear together), so there
	-- is no "call next wave": only the pause is skipped. Never more than one floor is alive (a floor must be cleared
	-- first), so nothing stacks and no kill is skipped; the heal between floors is paid when the floor is cleared, so
	-- only the regeneration of the pause is lost. The run leader presses it (any member once the leader is out).
	skip = {
		enabled = true,
		minInterval = 2, -- seconds between two presses of one run
		intoBoss = false -- true: the pause before a boss floor can be skipped too (false: it is the group's time to get ready)
	},
	healBetweenFloors = 0.5, -- fraction of missing health and mana restored
	bossEvery = BC.bossEvery,
	floorGold = 50, -- gold per floor per player (multiplied by the floor number), 0 = none
	-- the species of a floor's band and the bosses of the boss floors: infinitytower_balance_config.lua (the floor's band is
	-- floor // bandFloors + 1, the last one repeats)
	pools = BC.pools,
	bosses = bossNames(),
	fallbackMonster = "demon"
}
ChaosTowerRunConfig = cfg

-- ------------------------------------------------------------------ floor planner (pure)
function ChaosTowerFloorPlan(floor, players, rng)
	return B.plan(BC, floor, players, rng)
end

-- seconds the group has for `floor` (a boss floor: bossFloorTimeMult times floorTimeLimit)
function ChaosTowerFloorLimit(floor)
	local boss = (floor or 0) > 0 and floor % cfg.bossEvery == 0
	return cfg.floorTimeLimit * (boss and (cfg.bossFloorTimeMult or 1) or 1)
end

function ChaosTowerFloorPoints(floor)
	return floor -- floors cleared; ChaosTower.recordRun turns them into points (pointsPerFloor)
end

-- ------------------------------------------------------------------ arena
local function slotOrigin(slot)
	return {x = cfg.arenaBase.x + slot * cfg.slotSpacing, y = cfg.arenaBase.y, z = cfg.arenaBase.z}
end

local function inArena(pos)
	local b = cfg.arenaBase
	return pos.z == b.z and pos.y >= b.y and pos.y <= b.y + cfg.inner + 1
		and pos.x >= b.x and pos.x <= b.x + cfg.maxSlots * cfg.slotSpacing
end
ChaosTowerRun.inArena = inArena

local function arenaPos(slot, dx, dy) -- dx, dy are 0 .. inner+1 (0 and inner+1 are walls)
	local o = slotOrigin(slot)
	return Position(o.x + dx, o.y + dy, o.z)
end

-- the look of run number n (local coordinates 1..inner, the same in every slot): theme and variant in turn, cached
local function towerLook(n)
	local L = cfg.look
	local themeName = L.themes[n % #L.themes + 1]
	local variant = math.floor(n / #L.themes) % L.variants + 1
	local theme = ChaosArenaLook.theme(themeName, ChaosArenaLook.darkIds)
	local center = math.floor(cfg.inner / 2) + 1
	local look = ChaosArenaLook.cached("tower:" .. theme.name .. ":" .. variant, function()
		return {
			tiles = ChaosArenaLook.rectTiles(1, 1, cfg.inner, cfg.inner), theme = theme, seed = 100 + variant, mirror = true,
			keep = {{x = center, y = center, r = L.keepRadius}, {x = center, y = cfg.inner, r = 1}},
			roads = {{from = {x = center, y = cfg.inner}, to = {x = center, y = center + L.keepRadius + 1}}},
			cover = L.cover, lights = L.lights
		}
	end)
	return look
end
ChaosTowerRun.look = towerLook

ChaosTowerBuiltSlots = ChaosTowerBuiltSlots or {} -- global: survives a script reload (slot -> true once its tiles are ours)
local builtSlots = ChaosTowerBuiltSlots

-- returns true, or false + reason (nothing is built then: a tile of the footprint already belongs to the map)
local function buildArena(slot, look)
	local last = cfg.inner + 1
	local wallId = look.wallId or cfg.wallId
	if not builtSlots[slot] then
		for dx = 0, last do
			for dy = 0, last do
				if Tile(arenaPos(slot, dx, dy)) then
					return false, string.format("tile %d,%d,%d of tower slot %d already exists in the map",
						arenaPos(slot, dx, dy).x, arenaPos(slot, dx, dy).y, cfg.arenaBase.z, slot)
				end
			end
		end
	end
	for dx = 0, last do
		for dy = 0, last do
			local pos = arenaPos(slot, dx, dy)
			local tile = Game.createTile(pos, true)
			if tile then
				local wall = dx == 0 or dy == 0 or dx == last or dy == last
				-- Game.createItem places a ground item as the tile's ground; Tile:addItem does not
				if wall and not tile:getGround() then
					Game.createItem(cfg.groundId, 1, pos)
				end
				if wall and not tile:getItemById(wallId) then
					Game.createItem(wallId, 1, pos)
				end
			end
		end
	end
	local o = slotOrigin(slot)
	ChaosArenaLook.paint(look, o.z, o.x, o.y)
	-- a floor tile the painter could not give a ground (an unknown item) gets the plain one: never a hole
	for dx = 1, cfg.inner do
		for dy = 1, cfg.inner do
			local pos = arenaPos(slot, dx, dy)
			local tile = Tile(pos)
			if tile and not tile:getGround() then
				Game.createItem(cfg.groundId, 1, pos)
			end
		end
	end
	builtSlots[slot] = true
	return true
end

-- ground, walls and decoration go too: the next run repaints with its own theme
local function clearArena(slot)
	local last = cfg.inner + 1
	for dx = 0, last do
		for dy = 0, last do
			local tile = Tile(arenaPos(slot, dx, dy))
			if tile then
				local creatures = tile:getCreatures()
				for _, c in ipairs(creatures or {}) do
					if c:isMonster() then
						c:remove()
					end
				end
				local items = tile:getItems()
				for _, item in ipairs(items or {}) do
					item:remove()
				end
				local ground = tile.getGround and tile:getGround()
				if ground and type(ground) ~= "number" and ground.remove then
					ground:remove()
				end
			end
		end
	end
end

-- monsters appear around the middle of the arena, where the players stand, so they always see them; never on a
-- cover piece or a light
local function randomInnerPos(slot, rng, look)
	local center = math.floor(cfg.inner / 2) + 1
	local r = math.min(cfg.spawnRadius or 6, center - 1)
	local minDist = math.min(cfg.spawnMinDistance or 3, r)
	local blocked = look and look.blocked or {}
	for _ = 1, 30 do
		local dx = center + rng(2 * r + 1) - r - 1
		local dy = center + rng(2 * r + 1) - r - 1
		if math.max(math.abs(dx - center), math.abs(dy - center)) >= minDist and not blocked[ChaosArenaLook.key(dx, dy)] then
			return arenaPos(slot, dx, dy)
		end
	end
	return arenaPos(slot, center, center - r)
end

-- ------------------------------------------------------------------ run state
local runCount = 0     -- runs started since the server came up: picks the theme and the layout variant
local runs = {}        -- slot -> run
local runOf = {}       -- player id -> run
local monsterRun = {}  -- monster id -> run
local monsterInfo = {} -- monster id -> {floor, tier, boss, damage}: kept until the corpse is dropped

function ChaosTowerRun.activeRuns()
	local n = 0
	for _ in pairs(runs) do
		n = n + 1
	end
	return n
end

local function say(run, text)
	for _, p in pairs(run.players) do
		local player = Player(p.id)
		if player then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
	end
end

-- ------------------------------------------------------------------ "Next floor now"
-- The client's button is enabled by the state the server pushes (opcode 214, action "state"): {inRun, canSkip, floor,
-- nextBoss}. canSkip is true only while the run waits for the next floor (start delay or pause) and the skip rules allow it.
local function skipRefusal(run, player, now)
	local sk = cfg.skip or {}
	if sk.enabled == false then
		return "Next floor now is not available."
	end
	if run.ended or not run.players[player:getId()] then
		return "You are not inside the tower."
	end
	if not (player.getPosition and inArena(player:getPosition())) then
		return "You are not inside the tower."
	end
	if not run.waiting or run.remaining > 0 then
		return "The next floor can be called only when this one is cleared."
	end
	if run.leader and run.leader ~= player:getId() and run.players[run.leader] then
		return "Only the run leader can call the next floor."
	end
	if (run.floor + 1) % cfg.bossEvery == 0 and not sk.intoBoss then
		return "A boss floor is next: get ready, it starts by itself."
	end
	if run.lastSkip and now - run.lastSkip < (sk.minInterval or 2) then
		return "Wait a moment before calling the next floor again."
	end
end

function ChaosTowerRun.pushState(player, run)
	local op = ChaosOpcodes and ChaosOpcodes.infinitytower
	if not (op and json and json.encode and player.sendExtendedOpcode) then
		return
	end
	local state = {action = "state", inRun = run ~= nil, canSkip = false, floor = 0, nextBoss = false}
	if run then
		state.floor = run.floor
		state.nextBoss = (run.floor + 1) % cfg.bossEvery == 0
		state.canSkip = skipRefusal(run, player, os.time()) == nil
		-- the tower panel (O274): the floor's monsters, the countdowns (seconds left when this was sent; the client counts on)
		local now = os.time()
		state.cleared = run.cleared
		state.waiting = run.waiting == true
		state.remaining = run.waiting and 0 or run.remaining
		state.total = run.total or 0
		state.boss = run.floor > 0 and run.floor % cfg.bossEvery == 0
		if run.waiting and run.nextDue then
			state.nextIn = math.max(0, run.nextDue - now)
		elseif run.floorStart and run.remaining > 0 then
			state.floorLeft = math.max(0, run.floorStart + (run.floorLimit or cfg.floorTimeLimit) - now)
		end
		state.isLeader = run.leader == nil or run.leader == player:getId()
	end
	pcall(player.sendExtendedOpcode, player, op, json.encode(state))
end

function ChaosTowerRun.sendState(player)
	ChaosTowerRun.pushState(player, runOf[player:getId()])
end

local function pushStates(run)
	for _, p in pairs(run.players) do
		local player = Player(p.id)
		if player then
			ChaosTowerRun.pushState(player, run)
		end
	end
end

local function removePlayer(run, playerId, teleportOut)
	local entry = run.players[playerId]
	if not entry then
		return
	end
	run.players[playerId] = nil
	runOf[playerId] = nil
	local player = Player(playerId)
	if player then
		player:unregisterEvent("ChaosTowerPlayerDeath")
		if teleportOut then
			player:teleportTo(entry.entry)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
	end
	run.finished[#run.finished + 1] = {guid = entry.guid, id = playerId, floors = run.cleared}
	if player and run.leader == playerId then
		run.leader = nil -- the next skip press falls to any member
	end
	if player then
		ChaosTowerRun.pushState(player, nil)
	end
	if player and ChaosTower and ChaosTower.recordRun then
		ChaosTower.recordRun(player, run.cleared, os.time() - run.startTime)
	end
end

local function endRun(run, reason)
	if run.ended then
		return
	end
	run.ended = true
	for id in pairs(run.players) do
		local player = Player(id)
		if player then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, reason) .. " " .. Chaos.t(player, "You cleared %d floor(s).", run.cleared))
		end
		removePlayer(run, id, true)
	end
	for mid, r in pairs(monsterRun) do
		if r == run then
			monsterRun[mid] = nil
			monsterInfo[mid] = nil
		end
	end
	clearArena(run.slot)
	runs[run.slot] = nil
	if ChaosInstanceLimits then
		ChaosInstanceLimits.freed("tower", "the Infinity Tower")
	end
end

local startFloor

-- ------------------------------------------------------------------ floor rewards (infinitytower_balance_config.lua)
local function currentSeason()
	if ChaosTower and ChaosTower.currentSeason then
		return (ChaosTower.currentSeason())
	end
	return 1
end

-- gold coins go straight to the bank (owner 2026-10-27: "o gold da infinity tower ainda está indo pra bp")
local COIN_VALUE = {[2148] = 1, [2152] = 100, [2160] = 10000}

local function bankGold(player, amount)
	if amount > 0 then
		player:setBankBalance(player:getBankBalance() + amount)
	end
end

-- into the bags; what does not fit goes to the inbox; coins to the bank
local function deliver(player, items)
	for _, it in ipairs(items) do
		local coin = COIN_VALUE[it.id]
		if coin then
			bankGold(player, coin * it.count)
		else
			local given = Chaos.giveItem(player, it.id, it.count) or 0
			local rest = it.count - given
			local inbox = rest > 0 and player.getInbox and player:getInbox() or nil
			while inbox and rest > 0 do
				local c = math.min(rest, 100)
				inbox:addItem(it.id, c, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
				rest = rest - c
			end
		end
	end
end

local function storageValue(player)
	local ok, value = pcall(player.getStorageValue, player, BC.rewards.storage)
	return ok and tonumber(value) or 0
end

local function storedFloor(player)
	return B.stored(storageValue(player), currentSeason())
end

-- the reward text of the next milestone floor above `floor` for this character: its repeatable items, and the first-clear
-- items while the floor is not cleared yet this season. nil when there is none.
function ChaosTowerRun.nextRewardText(player, floor)
	local nm = B.nextMilestone(BC, floor)
	if not nm then
		return nil
	end
	local every = B.rewardItems(BC.rewards.repeatable, nm, BC.maxFloor)
	local first = nm > storedFloor(player) and B.rewardItems(BC.rewards.firstClear, nm, BC.maxFloor) or {}
	local text
	if #first > 0 and #every > 0 then
		text = Chaos.t(player, "Next reward: floor %d, %s (first clear this season: %s).", nm, B.itemsText(every), B.itemsText(first))
	elseif #first > 0 then
		text = Chaos.t(player, "Next reward: floor %d, first clear this season: %s.", nm, B.itemsText(first))
	elseif #every > 0 then
		text = Chaos.t(player, "Next reward: floor %d, %s.", nm, B.itemsText(every))
	end
	return text, nm
end

-- the rewards of a cleared milestone floor for one player: the repeatable ones and the first clear of the season
local function floorRewards(player, floor)
	if not B.isMilestone(BC, floor) then
		return
	end
	local every = B.rewardItems(BC.rewards.repeatable, floor, BC.maxFloor)
	if #every > 0 then
		deliver(player, every)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Floor %d reward: %s.", floor, B.itemsText(every)))
	end
	local items, value = B.firstClear(BC, storageValue(player), currentSeason(), floor)
	if items then
		player:setStorageValue(BC.rewards.storage, value) -- marked first: a failure below never pays twice
		deliver(player, items)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "First clear of floor %d this season: %s.", floor,
			B.itemsText(items)))
		pcall(function() player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW) end)
	end
end

-- the next floor starts after `seconds`, or at once with ChaosTowerRun.skip; a sequence number makes the timer of a
-- floor that was skipped to do nothing when it fires
local function scheduleNext(run, seconds)
	run.nextSeq = (run.nextSeq or 0) + 1
	run.waiting = true
	run.nextDue = os.time() + seconds
	run.nextEvent = addEvent(function(slot, owner, seq)
		local r = runs[slot]
		if r and r == owner and not r.ended and r.waiting and r.nextSeq == seq then -- not a later run in the same slot
			startFloor(r)
		end
	end, seconds * 1000, run.slot, run, run.nextSeq)
	pushStates(run)
end

local function floorCleared(run)
	run.cleared = run.floor
	run.floorEvent = nil
	if ChaosRecords and ChaosRecords.towerFloor then -- records.lua: the fastest climb to floors 50 / 100 / 120
		pcall(ChaosRecords.towerFloor, run.players, run.floor, os.time() - run.startTime)
	end
	for _, p in pairs(run.players) do
		local player = Player(p.id)
		if player then
			if cfg.floorGold > 0 then
				bankGold(player, cfg.floorGold * math.min(run.floor, BC.maxFloor)) -- the gold of a floor above maxFloor is that of maxFloor (O328)
			end
			Chaos.heal(player, (player:getMaxHealth() - player:getHealth()) * cfg.healBetweenFloors)
			player:addMana(math.floor((player:getMaxMana() - player:getMana()) * cfg.healBetweenFloors))
			floorRewards(player, run.floor)
		end
	end
	for _, p in pairs(run.players) do
		local player = Player(p.id)
		if player then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Floor %d cleared! Next floor in %d seconds.", run.floor, cfg.nextFloorDelay))
			if B.isMilestone(BC, run.floor) then
				local text = ChaosTowerRun.nextRewardText(player, run.floor)
				if text then
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
				end
			end
		end
	end
	scheduleNext(run, cfg.nextFloorDelay)
end

local function onMonsterDead(monsterId)
	local run = monsterRun[monsterId]
	monsterRun[monsterId] = nil
	monsterInfo[monsterId] = nil -- the corpse (onDropLoot) is made before the death event
	if not run or run.ended then
		return
	end
	run.remaining = run.remaining - 1
	if run.remaining <= 0 then
		floorCleared(run)
	else
		pushStates(run) -- the panel's monsters left
	end
end
ChaosTowerRun._onMonsterDead = onMonsterDead

-- Creature:setHealth is clamped to the maximum health in the engine, so the maximum goes first (monsters keep the health
-- of their species otherwise). The stock Creature:setMaxHealth exists for monsters (luascript.cpp luaCreatureSetMaxHealth).
local function setHealth(monster, health)
	health = math.max(1, math.floor(health))
	monster:setMaxHealth(health)
	monster:setHealth(health)
end

-- A tower monster has its tier from the plan only: the natural roll that monster_tiers.lua registers in onSpawn (magic /
-- rare / legendary, and for a boss 4-5 modifiers such as Juggernaut x1.6 health and Regenerating) would apply at its first
-- think on top of the floor's health curve and the boss's tuned seconds (tools/tower_model.py), so it is taken off.
local NATURAL_ROLLS = {"ChaosTierRollMagic", "ChaosTierRollRare", "ChaosTierRollLegendary", "ChaosTierRollBoss"}
local function dropNaturalRoll(monster)
	for _, name in ipairs(NATURAL_ROLLS) do
		pcall(monster.unregisterEvent, monster, name)
	end
end

local function spawnPlan(run, plan, rng)
	local spawned = 0
	for _, s in ipairs(plan.spawns) do
		local name = s.name
		if not MonsterType(name) then
			print("[Chaos tower] unknown monster '" .. name .. "', using " .. cfg.fallbackMonster)
			name = cfg.fallbackMonster
		end
		local monster
		for _ = 1, 6 do
			-- O168: the floor's level goes to monster_levels.lua (Chaos.spawnLevel) so "[level]" follows the floor; a plain
			-- Game.createMonster showed the species' own level whatever the floor
			if Chaos.createMonsterNamed then
				monster = Chaos.createMonsterNamed(name, randomInnerPos(run.slot, rng, run.look), false, true, nil, s.level)
			else
				monster = Game.createMonster(name, randomInnerPos(run.slot, rng, run.look), false, true)
			end
			if monster then
				break
			end
		end
		if monster then
			monster:registerEvent("ChaosTowerMonsterDeath")
			local id = monster:getId()
			monsterRun[id] = run
			monsterInfo[id] = {floor = plan.floor, tier = s.tier, boss = s.boss, damage = s.damage or 1, level = s.level}
			dropNaturalRoll(monster)
			-- the floor's health (infinitytower_balance_config.lua); a tier multiplies on top, by the tower's own
			-- tierHealth (the stock tier would multiply by its x2 / x3.5 / x6 after it)
			if s.health and monster.setMaxHealth then
				local stock = ChaosTiers and s.tier and ChaosTiers[s.tier] and ChaosTiers[s.tier].hp
				setHealth(monster, (s.tier and ChaosApplyTier and stock) and B.preTierHealth(BC, s.health, s.tier, stock) or s.health)
			end
			if s.tier and ChaosApplyTier then
				local applied = ChaosApplyTier(monster, s.tier)
				if not applied and s.health and monster.setMaxHealth then
					setHealth(monster, B.tierMaxHealth(BC, s.health, s.tier))
				end
			end
			spawned = spawned + 1
		end
	end
	return spawned
end

-- A tower monster that has no target (a boss that was placed before the group stood still, a monster whose target was
-- lost) picks the nearest living player of the run; the other scripted fights do the same (trials.lua, nemesis.lua).
-- Without it a monster without a target only takes random steps.
local ENGAGE_MS = 2000
local function nearestPlayer(run, monster)
	local mpos = monster:getPosition()
	local best, bestDist
	for _, entry in pairs(run.players) do
		local player = Player(entry.id)
		if player and player:getHealth() > 0 then
			local ppos = player:getPosition()
			if ppos and ppos.z == mpos.z then
				local d = mpos:getDistance(ppos)
				if not bestDist or d < bestDist then
					best, bestDist = player, d
				end
			end
		end
	end
	return best
end

local function engageTick(slot, floor, owner)
	local run = runs[slot]
	if not run or run ~= owner or run.ended or run.floor ~= floor or run.remaining <= 0 then
		return
	end
	for id, r in pairs(monsterRun) do
		if r == run then
			local ok = pcall(function()
				local monster = Monster(id)
				if monster and monster.selectTarget and not monster:getTarget() then
					local player = nearestPlayer(run, monster)
					if player then
						monster:selectTarget(player)
					end
				end
			end)
			if not ok then
				break -- the engine has no Monster:selectTarget / getTarget: nothing to do
			end
		end
	end
	run.engageEvent = addEvent(engageTick, ENGAGE_MS, slot, floor, owner)
end
ChaosTowerRun._engageTick = engageTick

startFloor = function(run)
	run.waiting = false
	run.floor = run.floor + 1
	local count = 0
	for _ in pairs(run.players) do
		count = count + 1
	end
	local plan = ChaosTowerFloorPlan(run.floor, count)
	run.remaining = spawnPlan(run, plan, math.random)
	run.total = run.remaining
	run.floorStart = os.time()
	run.floorLimit = ChaosTowerFloorLimit(run.floor)
	run.floorWarn = {} -- the floor's own warnings (instance limits)
	say(run, plan.boss and string.format("Floor %d: BOSS!", run.floor) or string.format("Floor %d", run.floor))
	if ChaosCombatFx and ChaosCombatFx.label then
		local c = math.floor(cfg.inner / 2) + 1
		pcall(ChaosCombatFx.label, arenaPos(run.slot, c, c - cfg.look.keepRadius - 1),
			plan.boss and string.format("BOSS FLOOR %d", run.floor) or string.format("Floor %d", run.floor), plan.boss and "#ff5050" or "#ffffff")
	end
	if run.remaining == 0 then
		floorCleared(run) -- nothing could be created: do not trap the group
		return
	end
	run.floorEvent = addEvent(function(slot, floor, owner)
		local r = runs[slot]
		if r and r == owner and not r.ended and r.floor == floor and r.remaining > 0 then
			endRun(r, "Time is up!")
		end
	end, run.floorLimit * 1000, run.slot, run.floor, run)
	run.engageEvent = addEvent(engageTick, 1000, run.slot, run.floor, run)
	pushStates(run)
end

-- Next floor now: the run leader (any member once the leader is out) starts the next floor at once. Returns true | false, text.
function ChaosTowerRun.skip(player)
	local run = runOf[player:getId()]
	if not run then
		player:sendCancelMessage(Chaos.t(player, "You are not inside the tower."))
		ChaosTowerRun.pushState(player, nil)
		return false
	end
	local why = skipRefusal(run, player, os.time())
	if why then
		player:sendCancelMessage(Chaos.t(player, why))
		ChaosTowerRun.pushState(player, run)
		return false
	end
	run.lastSkip = os.time()
	if run.nextEvent and stopEvent then
		pcall(stopEvent, run.nextEvent)
	end
	say(run, Chaos.t(player, "%s calls the next floor now.", player:getName()))
	startFloor(run) -- also clears run.waiting, so the pending timer does nothing
	return true
end

-- ------------------------------------------------------------------ the run's clock (instance limits)
-- seconds left of the whole run (nil without a run limit)
local function runLeft(run, now)
	if (cfg.runTimeLimit or 0) <= 0 then
		return nil
	end
	return math.max(0, run.startTime + cfg.runTimeLimit - (now or os.time()))
end
ChaosTowerRun.runLeft = runLeft

local function clockTick(slot, startTime)
	local run = runs[slot]
	if not run or run.ended or run.startTime ~= startTime then
		return
	end
	local now = os.time()
	local left = runLeft(run, now)
	if left and left <= 0 then
		endRun(run, "Time is up: your tower run ends here.")
		return
	end
	local IL = ChaosInstanceLimits
	if IL then
		local players = IL.playersOf(run.players)
		if left then
			IL.warn(run, left, players, "Infinity Tower", cfg.limits)
		end
		if run.floorWarn and run.remaining > 0 and run.floorStart then
			IL.warn(run.floorWarn, run.floorStart + (run.floorLimit or cfg.floorTimeLimit) - now, players, "Floor " .. run.floor,
				{warnAt = cfg.limits.floorWarnAt})
		end
	end
	addEvent(clockTick, 1000, slot, startTime)
end
ChaosTowerRun._clockTick = clockTick

-- ------------------------------------------------------------------ entering
local function freeSlot()
	for slot = 0, cfg.maxSlots - 1 do
		if not runs[slot] then
			return slot
		end
	end
end

local function groupOf(player)
	local members = {player}
	local party = player:getParty()
	if party and party:getLeader() and party:getLeader():getId() == player:getId() then
		for _, m in ipairs(party:getMembers()) do
			if #members < cfg.maxPartySize and m:getPosition():getDistance(player:getPosition()) <= cfg.partyRange then
				members[#members + 1] = m
			end
		end
	end
	return members
end

function ChaosTowerRun.start(player)
	if runOf[player:getId()] then
		player:sendCancelMessage(Chaos.t(player, "You are already inside the tower."))
		return false
	end
	if player:getLevel() < cfg.minLevel then
		player:sendCancelMessage(Chaos.t(player, "You need level %d to enter the Infinity Tower.", cfg.minLevel))
		return false
	end
	if player:getParty() and player:getParty():getLeader():getId() ~= player:getId() then
		player:sendCancelMessage(Chaos.t(player, "Only the party leader can start the tower."))
		return false
	end
	local group = groupOf(player)
	for _, m in ipairs(group) do
		if runOf[m:getId()] then
			player:sendCancelMessage(Chaos.t(player, "%s is already inside the tower.", m:getName()))
			return false
		end
		if m:getLevel() < cfg.minLevel then
			player:sendCancelMessage(Chaos.t(player, "%s does not have the required level.", m:getName()))
			return false
		end
		if ChaosTower and ChaosTower.canEnter and not ChaosTower.canEnter(m) then
			player:sendCancelMessage(Chaos.t(player, "%s has to wait before trying the tower again.", m:getName()))
			return false
		end
		if Chaos and Chaos.isMultiClient and Chaos.isMultiClient(m) then
			player:sendCancelMessage(m:getName() .. ": " .. Chaos.t(player, Chaos.multiClient.msgDungeon))
			return false
		end
		if m:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT) then
			player:sendCancelMessage(Chaos.t(player, "%s is in a fight.", m:getName()))
			return false
		end
	end
	local IL = ChaosInstanceLimits
	local slot = not (IL and IL.capped("tower", ChaosTowerRun.activeRuns(), cfg.limits)) and freeSlot() or nil
	if not slot then
		if IL then
			local lefts = {}
			for _, r in pairs(runs) do
				lefts[#lefts + 1] = runLeft(r) or cfg.floorTimeLimit
			end
			player:sendCancelMessage(IL.busy(player, "tower", "tower arenas", lefts, cfg.limits))
		else
			player:sendCancelMessage(Chaos.t(player, "All tower arenas are busy. Try again in a moment."))
		end
		return false
	end

	runCount = runCount + 1
	local look = towerLook(runCount)
	local built, why = buildArena(slot, look)
	if not built then
		print("[Chaos tower] " .. tostring(why))
		player:sendCancelMessage(Chaos.t(player, "The tower arena is not ready. Tell a game master."))
		return false
	end
	local run = {slot = slot, players = {}, finished = {}, floor = 0, cleared = 0, remaining = 0, startTime = os.time(),
		look = look}
	runs[slot] = run
	local center = math.floor(cfg.inner / 2) + 1
	for i, m in ipairs(group) do
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), entry = m:getPosition()}
		runOf[m:getId()] = run
		m:registerEvent("ChaosTowerPlayerDeath")
		m:teleportTo(arenaPos(slot, center + (i - 1) % 2, center + math.floor((i - 1) / 2)))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		m:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(m, "Welcome to the Infinity Tower. Floor 1 starts in %d seconds. Leave Tower (Adventure > Infinity Tower) takes you out.", cfg.startDelay))
		m:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(m, "Goal: kill every monster of a floor to open the next one; every %dth floor is a boss floor. Stay in the open middle to kite; the pillars and braziers along the walls are cover.", cfg.bossEvery))
		local reward = ChaosTowerRun.nextRewardText(m, 0)
		if reward then
			m:sendTextMessage(MESSAGE_EVENT_ADVANCE, reward)
		end
	end
	run.leader = player:getId()
	scheduleNext(run, cfg.startDelay)
	addEvent(clockTick, 1000, slot, run.startTime)
	return true
end

function ChaosTowerRun.isInside(player)
	return runOf[player:getId()] ~= nil
end

if Chaos.registerInstance then -- chaos_constants.lua (a test may stub Chaos)
	Chaos.registerInstance("tower", {label = "the Infinity Tower", inside = ChaosTowerRun.isInside, at = inArena,
		runs = function() -- /instances (instance_limits.lua)
			local out = {}
			for slot, run in pairs(runs) do
				local n = 0
				for _ in pairs(run.players) do
					n = n + 1
				end
				out[#out + 1] = {id = slot, what = string.format("slot %d, floor %d (%d cleared)", slot, run.floor, run.cleared),
					left = runLeft(run), players = n}
			end
			return out
		end, close = function(id) -- as when the time runs out: everyone out, the cleared floors recorded
			local run = runs[tonumber(id) or -1]
			if not run or run.ended then
				return false, "No tower run in slot " .. tostring(id) .. "."
			end
			endRun(run, "A gamemaster closed the tower run.")
			return true, "Tower run in slot " .. id .. " closed."
		end})
end

function ChaosTowerRun.leave(player)
	local run = runOf[player:getId()]
	if not run then
		player:sendCancelMessage(Chaos.t(player, "You are not inside the tower."))
		return false
	end
	removePlayer(run, player:getId(), true)
	if next(run.players) == nil then
		endRun(run, "Everyone left.")
	end
	return true
end

-- damage factor of a tower monster against players (infinitytower_balance_config.lua `damage`: the pace_config.lua curve
-- at the pool's hunting level, so a species hits as hard as outside). monster_damage.lua multiplies it on top of the
-- monster's own boost; 1 for anything that is not a tower monster, a boss included.
function ChaosTowerRun.damageMultOf(attacker)
	if not attacker or not attacker.isMonster or not attacker:isMonster() then
		return 1
	end
	local info = monsterInfo[attacker:getId()]
	if not info then
		local master = attacker.getMaster and attacker:getMaster()
		info = master and master.getId and monsterInfo[master:getId()]
	end
	return info and not info.boss and info.damage or 1
end

-- the level the floor is meant for (infinitytower_balance_config.lua `level`) of a tower monster or its summon, nil for
-- anything else. monster_damage.lua takes it as the monster's level (the physical damage boost by level): a tower monster
-- kept the level of its species there, so a floor 100 troll hit like a level 20 one.
function ChaosTowerRun.levelOf(monster)
	if not monster or not monster.getId then
		return nil
	end
	local info = monsterInfo[monster:getId()]
	if not info then
		local master = monster.getMaster and monster:getMaster()
		info = master and master.getId and monsterInfo[master:getId()]
	end
	return info and info.level or nil
end

-- the monster-info of a tower monster or its summon (nil for anything else)
local function infoOf(monster)
	if not monster or not monster.getId then
		return nil
	end
	local info = monsterInfo[monster:getId()]
	if not info then
		local master = monster.getMaster and monster:getMaster()
		info = master and master.getId and monsterInfo[master:getId()]
	end
	return info
end

-- the level the loot of a tower monster counts at (O328, infinitytower_balance_config.lua): the level of its floor, never above
-- the level of maxFloor. loot.lua ChaosLoot.monsterLevel takes at least this (item level, gear by level, class weapons,
-- rarity, orb and unique gates). A boss counts too. nil for anything that is not a tower monster.
function ChaosTowerRun.lootLevelOf(monster)
	local info = infoOf(monster)
	return info and info.floor and B.lootLevel(BC, info.floor) or nil
end

-- the loot factors of a normal tower monster (pace factors of its loot level x lootShare), the way pace.lua gives a hunt
-- monster its own; loot.lua reads them for the corpse and the extra rolls. nil for a boss (bosses are never thinned), a
-- summon of anything else or when pace_core.lua is not loaded.
function ChaosTowerRun.lootFactorsOf(monster)
	local info = monster and monster.getId and monsterInfo[monster:getId()]
	if not info or info.boss or not info.floor or not ChaosPaceCore or not ChaosPaceCore.factors or not ChaosPaceConfig then
		return nil
	end
	local ok, f = pcall(B.lootFactors, BC, info.floor, function(level, scaled)
		return ChaosPaceCore.factors(ChaosPaceConfig, level, scaled, false)
	end)
	return ok and f or nil
end

-- tower drops (infinitytower_balance_config.lua `drops`): orbs and crystal coins on top of the monster's own loot, and the
-- floor's gold (`killGold`, O328) in coins
if EventCallback then
	local lootCb = EventCallback
	local function addStacked(corpse, id, count)
		local stackable = ItemType(id):isStackable()
		local n = count
		while n > 0 do
			local k = stackable and math.min(n, 100) or 1
			corpse:addItem(id, k, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			n = n - k
		end
	end
	lootCb.onDropLoot = function(monster, corpse)
		local info = monster and monster.getId and monsterInfo[monster:getId()]
		if not info or info.boss or not corpse then
			return
		end
		local ok, err = pcall(function()
			for _, d in ipairs(B.dropRolls(BC, info.floor, info.tier, math.random)) do
				addStacked(corpse, d.id, d.count)
			end
			local gold = B.goldRoll(BC, info.floor, math.random)
			if gold > 0 and ChaosPaceCore and ChaosPaceCore.coinStacks then
				for _, c in ipairs(ChaosPaceCore.coinStacks(gold)) do
					addStacked(corpse, c[1], c[2])
				end
			end
		end)
		if not ok then
			print("[Chaos tower] drops failed: " .. tostring(err))
		end
	end
	lootCb:register(1.7)
end

-- ------------------------------------------------------------------ events
local monsterDeath = CreatureEvent("ChaosTowerMonsterDeath")
function monsterDeath.onDeath(creature)
	onMonsterDead(creature:getId())
	return true
end
monsterDeath:register()

local playerDeath = CreatureEvent("ChaosTowerPlayerDeath")
function playerDeath.onDeath(player)
	local run = runOf[player:getId()]
	if run then
		-- no teleport: the player respawns at the temple by the engine
		removePlayer(run, player:getId(), false)
		say(run, player:getName() .. " has fallen.")
		if next(run.players) == nil then
			endRun(run, "Your group has fallen.")
		end
	end
	return true
end
playerDeath:register()

local logout = CreatureEvent("ChaosTowerLogout")
function logout.onLogout(player)
	local run = runOf[player:getId()]
	if run then
		removePlayer(run, player:getId(), true)
		if next(run.players) == nil then
			endRun(run, "Everyone left.")
		end
	end
	return true
end
logout:register()

-- somebody who logged out or crashed inside an arena is sent to the temple
local login = CreatureEvent("ChaosTowerRunLogin") -- infinitytower.lua owns "ChaosTowerLogin" (a second one of that name is dropped)
function login.onLogin(player)
	if inArena(player:getPosition()) and not runOf[player:getId()] then
		local town = player:getTown()
		if town then
			player:teleportTo(town:getTemplePosition())
		end
	end
	return true
end
login:register()

ChaosTowerRun._state = function() return runs, runOf, monsterRun end

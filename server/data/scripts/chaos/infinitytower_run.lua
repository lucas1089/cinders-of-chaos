-- Infinity Tower: the run itself (instance, floors, waves, bosses, rewards).
--
-- A run happens in an arena that is BUILT AT RUNTIME with Game.createTile (dynamic tiles, never saved)
-- in a part of the map that has no tiles, so no map editing is needed. Each running group gets one of
-- `maxSlots` arenas side by side. Floors are waves: kill everything to open the next floor; every
-- `bossEvery`-th floor is a boss floor. Monsters get stronger pools and more tier/modifier chances
-- (monster_tiers.lua) as the floors rise. When a run ends each player's cleared floors are recorded with
-- ChaosTower.recordRun (points, best floor, ranking, milestones in infinitytower.lua).
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

ChaosTowerRun = ChaosTowerRun or {}

local cfg = {
	arenaBase = {x = 2000, y = 2000, z = 7}, -- top-left corner of slot 0; this part of the map has no tiles
	slotSpacing = 40,
	maxSlots = 16,
	inner = 19, -- inner width and height of the arena (odd)
	spawnRadius = 6, -- monsters appear within this distance of the middle (players start there)
	spawnMinDistance = 3, -- ... but not closer than this
	groundId = 413, -- "stone floor"
	wallId = 5648, -- "stone wall"
	minLevel = 100,
	maxPartySize = 4,
	partyRange = 12, -- members farther than this from the leader stay out
	floorTimeLimit = 300, -- seconds per floor
	-- a boss floor gets floorTimeLimit x this (600 s): the floor 90 boss needs 5:18 alone at level 1000 (server/README.md
	-- "Solo kill times")
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
	healBetweenFloors = 0.5, -- fraction of missing health and mana restored
	bossEvery = 10,
	floorGold = 50, -- gold per floor per player (multiplied by the floor number), 0 = none
	-- monster pools by band; the band is floor // 8 + 1, the last one repeats
	pools = {
		{"troll", "orc warrior", "skeleton", "ghoul", "dwarf soldier"},
		{"minotaur", "cyclops", "giant spider", "gargoyle", "stone golem"},
		{"dragon", "warlock", "banshee", "serpent spawn", "crystal spider"},
		{"demon skeleton", "vampire", "werewolf", "lost soul", "hydra"},
		{"behemoth", "dragon lord", "dark torturer", "fury", "phantasm"},
		{"hellhound", "juggernaut", "plaguesmith", "undead dragon", "grim reaper"},
		{"demon", "destroyer", "hellfire fighter", "massive fire elemental", "blightwalker"}
	},
	bosses = {"the grey widow", "the ashen count", "zeburoth", "pestrogh", "morgashal", "moloveth", "vharagoth",
		"ssylvath the corruptor", "ashvoran", "massacre", "jungle's revenge", "vhalkareth"},
	fallbackMonster = "demon"
}
ChaosTowerRunConfig = cfg

-- ------------------------------------------------------------------ floor planner (pure)
function ChaosTowerFloorPlan(floor, players, rng)
	rng = rng or math.random
	players = math.max(1, players or 1)
	local band = math.min(#cfg.pools, math.floor(floor / 8) + 1)
	local pool = cfg.pools[band]
	local isBoss = floor % cfg.bossEvery == 0
	local count = math.min(4 + math.floor(floor / 3), 16) + (players - 1) * 2
	local plan = {floor = floor, boss = isBoss, spawns = {}}
	if isBoss then
		local boss = cfg.bosses[(math.floor(floor / cfg.bossEvery) - 1) % #cfg.bosses + 1]
		plan.spawns[1] = {name = boss, boss = true}
		count = math.floor(count / 3)
	end
	local magic = math.min(5 + floor, 60)
	local rare = math.min(math.floor(floor / 2), 30)
	local legendary = math.min(math.floor(floor / 10), 10)
	for _ = 1, count do
		local roll = rng(100)
		local tier
		if roll <= legendary then
			tier = "legendary"
		elseif roll <= legendary + rare then
			tier = "rare"
		elseif roll <= legendary + rare + magic then
			tier = "magic"
		end
		plan.spawns[#plan.spawns + 1] = {name = pool[rng(#pool)], tier = tier}
	end
	return plan
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

local function buildArena(slot)
	local last = cfg.inner + 1
	for dx = 0, last do
		for dy = 0, last do
			local pos = arenaPos(slot, dx, dy)
			local tile = Game.createTile(pos, true)
			if tile then
				-- Game.createItem places a ground item as the tile's ground; Tile:addItem does not
				if not tile:getGround() then
					Game.createItem(cfg.groundId, 1, pos)
				end
				if (dx == 0 or dy == 0 or dx == last or dy == last) and not tile:getItemById(cfg.wallId) then
					Game.createItem(cfg.wallId, 1, pos)
				end
			end
		end
	end
end

local function clearArena(slot)
	for dx = 1, cfg.inner do
		for dy = 1, cfg.inner do
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
			end
		end
	end
end

-- monsters appear around the middle of the arena, where the players stand, so they always see them
local function randomInnerPos(slot, rng)
	local center = math.floor(cfg.inner / 2) + 1
	local r = math.min(cfg.spawnRadius or 6, center - 1)
	local minDist = math.min(cfg.spawnMinDistance or 3, r)
	for _ = 1, 20 do
		local dx = center + rng(2 * r + 1) - r - 1
		local dy = center + rng(2 * r + 1) - r - 1
		if math.max(math.abs(dx - center), math.abs(dy - center)) >= minDist then
			return arenaPos(slot, dx, dy)
		end
	end
	return arenaPos(slot, center, center - r)
end

-- ------------------------------------------------------------------ run state
local runs = {}        -- slot -> run
local runOf = {}       -- player id -> run
local monsterRun = {}  -- monster id -> run

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
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, reason .. string.format(" You cleared %d floor(s).", run.cleared))
		end
		removePlayer(run, id, true)
	end
	for mid, r in pairs(monsterRun) do
		if r == run then
			monsterRun[mid] = nil
		end
	end
	clearArena(run.slot)
	runs[run.slot] = nil
	if ChaosInstanceLimits then
		ChaosInstanceLimits.freed("tower", "the Infinity Tower")
	end
end

local startFloor

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
				player:addMoney(cfg.floorGold * run.floor)
			end
			Chaos.heal(player, (player:getMaxHealth() - player:getHealth()) * cfg.healBetweenFloors)
			player:addMana(math.floor((player:getMaxMana() - player:getMana()) * cfg.healBetweenFloors))
		end
	end
	say(run, string.format("Floor %d cleared! Next floor in %d seconds.", run.floor, cfg.nextFloorDelay))
	run.nextEvent = addEvent(function(slot)
		local r = runs[slot]
		if r and not r.ended then
			startFloor(r)
		end
	end, cfg.nextFloorDelay * 1000, run.slot)
end

local function onMonsterDead(monsterId)
	local run = monsterRun[monsterId]
	monsterRun[monsterId] = nil
	if not run or run.ended then
		return
	end
	run.remaining = run.remaining - 1
	if run.remaining <= 0 then
		floorCleared(run)
	end
end
ChaosTowerRun._onMonsterDead = onMonsterDead

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
			monster = Game.createMonster(name, randomInnerPos(run.slot, rng), false, true)
			if monster then
				break
			end
		end
		if monster then
			monster:registerEvent("ChaosTowerMonsterDeath")
			monsterRun[monster:getId()] = run
			if s.tier and ChaosApplyTier then
				ChaosApplyTier(monster, s.tier)
			end
			spawned = spawned + 1
		end
	end
	return spawned
end

startFloor = function(run)
	run.floor = run.floor + 1
	local count = 0
	for _ in pairs(run.players) do
		count = count + 1
	end
	local plan = ChaosTowerFloorPlan(run.floor, count)
	run.remaining = spawnPlan(run, plan, math.random)
	run.floorStart = os.time()
	run.floorLimit = ChaosTowerFloorLimit(run.floor)
	run.floorWarn = {} -- the floor's own warnings (instance limits)
	say(run, plan.boss and string.format("Floor %d: BOSS!", run.floor) or string.format("Floor %d", run.floor))
	if run.remaining == 0 then
		floorCleared(run) -- nothing could be created: do not trap the group
		return
	end
	run.floorEvent = addEvent(function(slot, floor)
		local r = runs[slot]
		if r and not r.ended and r.floor == floor and r.remaining > 0 then
			endRun(r, "Time is up!")
		end
	end, run.floorLimit * 1000, run.slot, run.floor)
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
			player:sendCancelMessage(m:getName() .. " is already inside the tower.")
			return false
		end
		if m:getLevel() < cfg.minLevel then
			player:sendCancelMessage(m:getName() .. " does not have the required level.")
			return false
		end
		if ChaosTower and ChaosTower.canEnter and not ChaosTower.canEnter(m) then
			player:sendCancelMessage(m:getName() .. " has to wait before trying the tower again.")
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

	buildArena(slot)
	local run = {slot = slot, players = {}, finished = {}, floor = 0, cleared = 0, remaining = 0, startTime = os.time()}
	runs[slot] = run
	local center = math.floor(cfg.inner / 2) + 1
	for i, m in ipairs(group) do
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), entry = m:getPosition()}
		runOf[m:getId()] = run
		m:registerEvent("ChaosTowerPlayerDeath")
		m:teleportTo(arenaPos(slot, center + (i - 1) % 2, center + math.floor((i - 1) / 2)))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		m:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(m, "Welcome to the Infinity Tower. Floor 1 starts in %d seconds. Leave Tower (Adventure > Infinity Tower) takes you out.", cfg.startDelay))
	end
	run.nextEvent = addEvent(function(s)
		local r = runs[s]
		if r and not r.ended then
			startFloor(r)
		end
	end, cfg.startDelay * 1000, slot)
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
		player:teleportTo(player:getTown():getTemplePosition())
	end
	return true
end
login:register()

ChaosTowerRun._state = function() return runs, runOf, monsterRun end

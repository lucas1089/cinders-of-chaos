-- Map overlay marks (client game_mapoverlay, extended opcode ChaosOpcodes.mapmarks)
--
-- The client draws its own explored-map data over the game view; this script only tells it where the points of
-- interest are. It reads the live state of the other systems and changes none of them:
--   party       the members of the player's party (any distance; the client shows the ones on its floor)
--   temple      the temple of the player's town; depot: the depot lockers around that temple (scanned once per town)
--   npc         NPCs within cfg.scanRange
--   rift        ChaosRift.runOf: the way in, the guardian(s) (alive, or their spawn while they wait), the reward
--               chest, the sealed coffer, the run's treasure goblin
--   goblin      treasure goblins (ChaosTreasureGoblin.alive) within cfg.goblinRange
--   worldboss   ChaosWorldBoss.state.bossId while it lives
--   invasion    ChaosInvasion.state.target while an invasion runs, and its boss (boss)
--   boss        dungeon bosses (Chaos.dungeons.extra[*].bossName) within cfg.scanRange
-- Pure helpers: map_marks_core.lua (tests: server/tests/map_marks_test.lua).
--
-- Protocol (JSON {action, data}):
--   client -> server  watch {on = true|false}   (the overlay is open / closed)
--   server -> client  marks {marks = [{k, x, y, z, n?}]}                 every cfg.thinkMs while watching
--                     rift  {id, x1, y1, x2, y2, z}                      once per run and floor of the slot, to
--                                                                         everyone in it: the client forgets its old
--                                                                         map of that square (every run of a slot
--                                                                         gets a new generated layout)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/map_marks_core.lua")

local M = ChaosMapMarksCore
local OPCODE = ChaosOpcodes.mapmarks or 245
local cfg = {
	thinkMs = 1000,
	scanRange = 40, -- NPCs / dungeon bosses / goblins around the player (sqm)
	goblinRange = 80,
	depotRadius = 40, -- depot lockers this close to a town's temple (same floor)
	maxMarks = 80
}

ChaosMapMarks = ChaosMapMarks or {}
local MM = ChaosMapMarks
MM.watch = MM.watch or {} -- player id -> true while the overlay is open
MM.riftSent = MM.riftSent or {} -- player id -> run token last sent
MM.depots = MM.depots or {} -- town id -> list of depot positions

local function townDepots(town)
	local id = town:getId()
	if MM.depots[id] then
		return MM.depots[id]
	end
	local list = {}
	local ok, temple = pcall(function() return town:getTemplePosition() end)
	if ok and temple then
		local r = cfg.depotRadius
		for x = temple.x - r, temple.x + r do
			for y = temple.y - r, temple.y + r do
				local tile = Tile(Position(x, y, temple.z))
				if tile and tile:getItemByType(ITEM_TYPE_DEPOT) then
					list[#list + 1] = {x = x, y = y, z = temple.z}
				end
			end
		end
	end
	MM.depots[id] = list
	return list
end

local dungeonBosses
local function isDungeonBoss(name)
	if not dungeonBosses then
		dungeonBosses = {}
		for _, e in pairs(Chaos.dungeons and Chaos.dungeons.extra or {}) do
			if type(e) == "table" and e.bossName then
				dungeonBosses[e.bossName:lower()] = true
			end
		end
	end
	return dungeonBosses[name:lower()] == true
end

local function monsterPos(id)
	local m = id and Monster(id)
	return m and m:getPosition() or nil, m
end

local function riftMarks(player, list, seen)
	local RF = ChaosRift
	local run = RF and RF.runOf and RF.runOf[player:getId()]
	if not run or not run.L then
		return
	end
	local L = run.L
	M.add(list, seen, "entry", L.start, "Rift entrance")
	local alive = false
	for id in pairs(run.bossIds or {}) do
		local pos, m = monsterPos(id)
		if pos then
			alive = true
			M.add(list, seen, "guardian", pos, m:getName())
		end
	end
	if not alive and run.boss ~= "dead" and L.bossSpawn then
		M.add(list, seen, "guardian", L.bossSpawn, run.boss == "waiting" and "Guardian (not yet)" or "Guardian")
	end
	if run.chestPos then
		M.add(list, seen, "chest", run.chestPos, "Rift chest")
	end
	-- closed (not woken yet) or guarded (its wave is out); "open" is looted and "gone" crumbled at the seal
	local cofferState = run.coffer and run.coffer.state
	if run.coffer and run.coffer.pos and (cofferState == "closed" or cofferState == "guarded") then
		M.add(list, seen, "coffer", run.coffer.pos, "Sealed coffer")
	end
	if run.goblin == "out" then
		local pos = monsterPos(run.goblinId)
		if pos then
			M.add(list, seen, "goblin", pos, "Treasure Goblin")
		end
	end
end

local function buildMarks(player)
	local list, seen = {}, {}
	local here = player:getPosition()
	local party = player:getParty()
	if party then
		local members = {party:getLeader()}
		for _, m in ipairs(party:getMembers() or {}) do
			members[#members + 1] = m
		end
		for _, m in ipairs(members) do
			if m and m:getId() ~= player:getId() then
				M.add(list, seen, "party", m:getPosition(), m:getName())
			end
		end
	end
	local town = player:getTown()
	if town then
		local ok, temple = pcall(function() return town:getTemplePosition() end)
		if ok and temple then
			M.add(list, seen, "temple", temple, "Temple")
		end
		for _, p in ipairs(townDepots(town)) do
			M.add(list, seen, "depot", p, "Depot")
		end
	end
	riftMarks(player, list, seen)

	local W = ChaosWorldBoss and ChaosWorldBoss.state
	if W and W.bossId then
		local pos, m = monsterPos(W.bossId)
		if pos then
			M.add(list, seen, "worldboss", pos, m:getName())
		end
	end
	local V = ChaosInvasion and ChaosInvasion.state
	if V and (V.phase == "running" or V.phase == "occupied") then
		if V.target then
			M.add(list, seen, "invasion", V.target, "Invasion: " .. tostring(V.areaName or "target"))
		end
		local pos, m = monsterPos(V.bossId)
		if pos then
			M.add(list, seen, "boss", pos, m:getName())
		end
	end
	local TG = ChaosTreasureGoblin
	for id in pairs(TG and TG.alive or {}) do
		local pos, m = monsterPos(id)
		if pos and M.distance(pos, here) <= cfg.goblinRange then
			M.add(list, seen, "goblin", pos, m:getName())
		end
	end

	local r = cfg.scanRange
	for _, c in ipairs(Game.getSpectators(here, false, false, r, r, r, r) or {}) do
		if c:isNpc() then
			M.add(list, seen, "npc", c:getPosition(), c:getName())
		elseif c:isMonster() and not c:getMaster() and isDungeonBoss(c:getName()) then
			M.add(list, seen, "boss", c:getPosition(), c:getName())
		end
	end
	return M.trim(list, here, cfg.maxMarks)
end

local function sendMarks(player)
	local ok, list = pcall(buildMarks, player)
	if not ok then
		print("[Chaos map marks] " .. tostring(list))
		return
	end
	Chaos.send(player, OPCODE, "marks", {marks = list})
end

-- the rift square once per run, so the client can forget the rooms of earlier runs there
local function sendRiftArea(player)
	local RF = ChaosRift
	local run = RF and RF.runOf and RF.runOf[player:getId()]
	if not run or run.slot == nil then
		MM.riftSent[player:getId()] = nil
		return
	end
	run.mapToken = run.mapToken or string.format("%d-%d-%d", os.time(), run.id or 0, math.random(1, 99999))
	if MM.riftSent[player:getId()] == run.mapToken then
		return
	end
	local grid = ChaosRiftConfig and ChaosRiftConfig.grid
	local area = M.riftArea(grid, run.slot)
	if area then
		-- one square per floor of the slot (a rift layout may have two)
		for k = 1, (grid.floors or 1) do
			local a = {x1 = area.x1, y1 = area.y1, x2 = area.x2, y2 = area.y2, z = area.z + k - 1,
				id = k == 1 and run.mapToken or (run.mapToken .. "/" .. k)}
			Chaos.send(player, OPCODE, "rift", a)
		end
		MM.riftSent[player:getId()] = run.mapToken
	end
end

local think = GlobalEvent("ChaosMapMarksThink")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		local id = player:getId()
		if ChaosRift and ChaosRift.runOf and (ChaosRift.runOf[id] or MM.riftSent[id]) then
			sendRiftArea(player)
		end
		if MM.watch[id] then
			sendMarks(player)
		end
	end
	return true
end
think:interval(cfg.thinkMs)
think:register()

local login = CreatureEvent("ChaosMapMarksLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMapMarksExtended")
	player:registerEvent("ChaosMapMarksLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosMapMarksLogout")
function logout.onLogout(player)
	MM.watch[player:getId()] = nil
	MM.riftSent[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosMapMarksExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "watch" then
		return
	end
	local on = type(msg.data) == "table" and msg.data.on == true
	MM.watch[player:getId()] = on or nil
	if on then
		sendMarks(player)
	end
end
ext:type("extendedopcode")
ext:register()

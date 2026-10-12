-- Run from the server/ folder: luajit tests/base_eventrooms_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_eventrooms.py on copies of the stock soul pit and tower defence (written here in their stock shape,
-- shortened, with made-up monsters), then the scripts on a mocked engine:
--   tool         dry run, patched, a second run changes nothing, CRLF kept, a script of another shape left alone
--   soul pit     without the Chaos scripts the patched pit runs exactly as the stock one; with them: the pit is locked
--                while a run is on (when it frees up), the time limit with warnings, time up sends everyone to the
--                lobby spot (off the next group's start tiles) and removes the waves, the pit's own state is reset (the next group gets a fresh run); a
--                completed pit closes the room 65 s later
--   tower        the lever starts a session for the players in the arena; the entrance tile sends a newcomer back
--   defence      while it runs; a second pull of the group's own lever: "still going"; time up: everyone out to the
--                exit drop, spawning stopped, the summon counters reset, the monsters removed; a win or a loss ends it
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_eventrooms_patch_test: python3 not found, skipped")
	return
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function sh(cmd)
	local h = io.popen(cmd .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end

-- ------------------------------------------------------------------ the stock code (shortened, made-up monsters)
local SOULPIT = [[
print(">> Soulpit System Loaded")
local event = {
    waves = {
        [30001] = {
        monsters = {
            {"angry mudling", "angry mudling"},
            {"wrathful mudling"}
        },
            storage = 976547,
            waves = 2,
            name = "Mudling"
        },
    },


    spawnArea = {Position(3001, 3004, 8), Position(3024, 3009, 8)},
    creatures = {},
    currentWave = 0,
    participants = {},
    currentItem = nil
}

local function verifyEventCreatures()
    if #event.creatures > 0 then
        local creature = nil
        for pid = #event.creatures, 1, -1 do
            creature = Creature(event.creatures[pid][1])
            if not creature then
                table.remove(event.creatures, pid)
            end
        end
    end
end

local function spawnEventCreatures(wave, indexTracker)
    local monsters = event.waves[event.currentItem].monsters[wave]
    if not monsters then
        return
    end
    for _, monster in ipairs(monsters) do
        local attempts = 0
        while attempts < 20 do
            local randomPosition = Position(math.random(event.spawnArea[1].x, event.spawnArea[2].x),
                                             math.random(event.spawnArea[1].y, event.spawnArea[2].y),
                                             math.random(event.spawnArea[1].z, event.spawnArea[2].z))
            local creature = Game.createMonster(monster, randomPosition, false, true)
            if creature then
                table.insert(event.creatures, {creature:getId()})
                break
            end
            attempts = attempts + 1
        end
    end
end

local function monitorEvent()
    verifyEventCreatures()
    if #event.creatures > 0 then
        addEvent(monitorEvent, 1000)
        return
    end
    if event.currentItem then
        if event.waves[event.currentItem] and event.currentWave == event.waves[event.currentItem].waves then
            local eventName = event.waves[event.currentItem].name or "Soulpit"
            for _, playerId in pairs(event.participants) do
                local player = Player(playerId)
                if player then
                    player:setStorageValue(event.waves[event.currentItem].storage, 1)
                    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have completed the \"" .. eventName .. "\" Soulpit.")
                end
            end
            event.creatures = {}
            event.currentWave = 0
            event.participants = {}
            event.currentItem = nil
        end
    end
end

local function eventManager()
    if #event.creatures > 0 then
        addEvent(eventManager, 1000)
        return
    end
    if event.currentItem and event.waves[event.currentItem] then
        if event.currentWave < event.waves[event.currentItem].waves then
            event.currentWave = event.currentWave + 1
            spawnEventCreatures(event.currentWave, 1)
            addEvent(monitorEvent, 1000)
            addEvent(eventManager, 1000)
        else
            event.creatures = {}
            event.currentWave = 0
            event.participants = {}
            event.currentItem = nil
        end
    end
end

local function startNextWave()
    verifyEventCreatures()
    if #event.creatures == 0 and event.currentItem then
        if event.currentWave < event.waves[event.currentItem].waves then
            event.currentWave = event.currentWave + 1
            spawnEventCreatures(event.currentWave, 1)
            addEvent(monitorEvent, 1000)
            addEvent(eventManager, 1000)
        else
            event.creatures = {}
            event.currentWave = 0
            event.participants = {}
            event.currentItem = nil
        end
    else
        addEvent(startNextWave, 1000)
    end
end

local function checkAndStartWave(player, item)
    local itemId = item:getId()
    if event.waves[itemId] then
        event.currentItem = itemId
        item:remove(1)
        table.insert(event.participants, player:getId())
        addEvent(function()
            player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The Soulpit has been started.")
            startNextWave()
        end, 5000)
        return true
    end
    event.currentItem = nil
    return false
end

local config = {
    actionId = 47392,
    participantsPos = {
        Position(3030, 3010, 8),
        Position(3030, 3011, 8)
    },
    spawnArea = {
    fromPos = Position(3000, 3000, 8),
    toPos = Position(3022, 3015, 8)
    },
    entranceArea = Position(3012, 3014, 8),
}

local function getSpectators()
    if not config.centerPosition then
        config.diffX = math.ceil((config.spawnArea.toPos.x - config.spawnArea.fromPos.x) / 2)
        config.diffY = math.ceil((config.spawnArea.toPos.y - config.spawnArea.fromPos.y) / 2)
        config.centerPosition = config.spawnArea.fromPos + Position(config.diffX, config.diffY, 0)
    end
    return Game.getSpectators(config.centerPosition, false, false, config.diffX, config.diffX, config.diffY, config.diffY)
end


local soulPit = Action()

function soulPit.onUse(player, item, fromPos, target, toPos, isHotkey)
    local participants = {}
    for index, pos in pairs(config.participantsPos) do
        local tile = Tile(pos)
        if not tile then error("[Warning - Tile not found]") end
        local participant = tile:getTopVisibleCreature(player)
        if participant and participant:isPlayer() then
            if index == 1 and participant ~= player then
                player:sendCancelMessage("Only the first participant can pull the lever.")
                return true
            end
            participants[#participants +1] = participant
        end
    end

    local spectators = getSpectators()
    for _, spectator in pairs(spectators) do
        if spectator:isPlayer() then
            player:sendTextMessage(MESSAGE_INFO_DESCR, "At this time the Soulpit is occupied, please try again later.")
            return true
        end
    end

    for _, spectator in pairs(spectators) do spectator:remove() end
    if event.waves[item:getId()] and target:getActionId() == config.actionId then
        target:transform(28241)
        if checkAndStartWave(player, item) then
            addEvent(function()
                for index, participant in pairs(participants) do
                    participant:teleportTo(config.entranceArea, false)
                end
                target:transform(28240)
            end, 5000)
        end
    else
        player:sendTextMessage(MESSAGE_INFO_DESCR, "You need a Soul Core to start the event.")
    end
    return true
end

for itemId, _ in pairs(event.waves) do
    soulPit:id(itemId)
end
soulPit:register()
]]

local TOWER = [[
print(">> Tower Defense System Loaded")

local currentItemId
local currentWave = 0
local activeMonsters = 0
local spawnMonster
local spawningWave = false
local stopSpawning = false

local monsterTable = {
    [37931] = {names = {"ash imp", "ash brute"}, spawns = {3, 1}},
}

local fromPos = {x = 31180, y = 32239, z = 8}
local toPos = {x = 31236, y = 32277, z = 8}

local function removeCreaturesInRange(fromPos, toPos)
    for _, c in ipairs(Game.getSpectators(Position(31208, 32258, 8), false, false, 28, 28, 19, 19)) do
        if c:isMonster() then c:remove() end
    end
end

local function rewardPlayers()
    for _, player in ipairs(Game.getPlayers()) do
        player:sendTextMessage(MESSAGE_INFO_DESCR, "You have been rewarded for completing the Tower Defense!")
    end
    spawningWave = false
    stopSpawning = true
    removeCreaturesInRange(fromPos, toPos)
end

local function checkFinalBossStatus()
    local teleportPos = {x = 31206, y = 32301, z = 8}
                local playersTeleported = false
    for _, player in ipairs(Game.getPlayers()) do
        player:teleportTo(teleportPos)
        player:sendTextMessage(MESSAGE_INFO_DESCR, "You lost! You have been teleported to town.")
        playersTeleported = true
    end
    stopSpawning = true
    return playersTeleported
end

local function moveAlongPath(cid)
            local playersTeleported = false
    stopSpawning = true
    return playersTeleported
end

spawnMonster = function(monsterType, spawnPos, itemId)
    if stopSpawning then
        return
    end
    Game.createMonster(monsterType, spawnPos)
    activeMonsters = activeMonsters + 1
    addEvent(function() spawnMonster(monsterType, spawnPos, itemId) end, 2300)
end

local towerDefense = Action()

function towerDefense.onUse(cid, item, fromPosition, itemEx, toPosition)
    if spawningWave then
        cid:sendTextMessage(MESSAGE_INFO_DESCR, "Another wave is already being spawned. Cannot start a new wave.")
        return true
    end
    currentItemId = item.actionid
    local monsterData = monsterTable[currentItemId]
    if not monsterData then
        return false
    end
    local baseMonster = Game.createMonster("Base Core", Position(31230, 32268, 8))
    stopSpawning = false
    spawningWave = true
    addEvent(function() spawnMonster(monsterData.names[1], Position(31184, 32245, 8), currentItemId) end, 10000)
    cid:sendTextMessage(MESSAGE_INFO_DESCR, "Tower Defense will start in 10 Seconds! Prepare yourself!")
    return true
end

for actionId, _ in pairs(monsterTable) do
    towerDefense:aid(actionId)
end
towerDefense:register()

TowerTest = {reward = rewardPlayers, lose = checkFinalBossStatus, lose2 = moveAlongPath}
]]

local ENTRANCE = [[
local entranceTower = MoveEvent()

function entranceTower.onStepIn(player, item, position, fromPosition)
    local cooldownEntrance = 184320
    local currentTime = os.time()
    local cooldownTime = player:getStorageValue(cooldownEntrance)
    local remainingTime = cooldownTime - currentTime
	if player:isPlayer() then
        if player:getStorageValue(cooldownEntrance) < os.time() then
		player:teleportTo(Position(31205, 32270, 8))
        player:setStorageValue(88709, 1)
        else
            player:teleportTo(fromPosition)
            player:sendTextMessage(MESSAGE_INFO_DESCR, "There is a cooldown of " .. remainingTime .. " seconds for entry to the tower defense.")
        end
	end
	return true
end

entranceTower:type("stepin")
entranceTower:aid(25485)
entranceTower:register()
]]

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
local pitPath = data .. "/scripts/customs/soulpit_system/soulpit.lua"
local towerPath = data .. "/scripts/customs/tower_defense/tower_defense.lua"
local entrancePath = data .. "/scripts/customs/tower_defense/entrance_teleport.lua"
os.execute("mkdir -p '" .. data .. "/scripts/customs/soulpit_system' '" .. data .. "/scripts/customs/tower_defense'")
local SOULPIT_CRLF = SOULPIT:gsub("\n", "\r\n")
writeFile(pitPath, SOULPIT_CRLF)
writeFile(towerPath, TOWER)
writeFile(entrancePath, ENTRANCE)

local tool = "python3 -I tools/patch_base_eventrooms.py '" .. data .. "'"
local out = sh(tool .. " --dry-run")
ok(out:find("soulpit.lua: patched aid47392 (dry run, not written)", 1, true) ~= nil, "dry run reports: " .. out)
eq(readFile(pitPath), SOULPIT_CRLF, "dry run writes nothing")
out = sh(tool)
ok(out:find("soulpit_system/soulpit.lua: patched aid47392\n", 1, true) ~= nil, "soul pit patched: " .. out)
ok(out:find("tower_defense/tower_defense.lua: patched aid37931\n", 1, true) ~= nil, "tower defence patched")
ok(out:find("tower_defense/entrance_teleport.lua: patched aid37931\n", 1, true) ~= nil, "its entrance patched")
local pit, tower, entrance = readFile(pitPath), readFile(towerPath), readFile(entrancePath)
local _, lf = pit:gsub("[^\r]\n", "")
eq(lf, 0, "CRLF kept")
local _, pitMarks = pit:gsub("patch_base_eventrooms%.py", "")
eq(pitMarks, 14 + 2 + 1 + 1, "soul pit: the room config, the lock, the start, the end")
local _, towerMarks = tower:gsub("patch_base_eventrooms%.py", "")
eq(towerMarks, 15 + 1 + 2 + 1 + 1, "tower defence: the room config, the win, two losses, the lock, the start")
-- the stock text is all still there, in order
local stripped = pit:gsub("[^\r\n]*%-%- Chaos %(patch_base_eventrooms%.py%)\r\n", ""):gsub("\r\n\r\n(local function getSpectators)", "\r\n%1")
ok(stripped == SOULPIT_CRLF or stripped:gsub("\r\n", "\n") == SOULPIT, "soul pit: only lines added")
out = sh(tool)
ok(out:find("soulpit.lua: already patched", 1, true) and out:find("tower_defense.lua: already patched", 1, true)
	and out:find("entrance_teleport.lua: already patched", 1, true), "second run: already patched")
ok(readFile(pitPath) == pit and readFile(towerPath) == tower and readFile(entrancePath) == entrance, "idempotent")
-- another shape: left alone
local other = root .. "/other/data"
os.execute("mkdir -p '" .. other .. "/scripts/customs/soulpit_system'")
local OTHER = SOULPIT:gsub("if checkAndStartWave%(player, item%) then", "if startPit(player, item) then")
writeFile(other .. "/scripts/customs/soulpit_system/soulpit.lua", OTHER)
out = sh("python3 -I tools/patch_base_eventrooms.py '" .. other .. "'")
ok(out:find("soulpit.lua: unrecognised", 1, true) ~= nil, "another shape: listed: " .. out)
eq(readFile(other .. "/scripts/customs/soulpit_system/soulpit.lua"), OTHER, "and left alone")
out = sh("python3 -I tools/patch_base_eventrooms.py '" .. root .. "/other'; echo status=$?")
ok(out:find("nothing to do", 1, true) and out:find("status=0", 1, true), "no scripts: nothing to do, status 0")

-- ------------------------------------------------------------------ mocked engine
local now = 1000000
os.time = function() return now end -- luacheck: ignore
local timers, nextTimer = {}, 0
addEvent = function(fn, ms, ...)
	nextTimer = nextTimer + 1
	timers[nextTimer] = {fn = fn, at = now * 1000 + (ms or 0), args = {...}}
	return nextTimer
end
stopEvent = function(id) if id then timers[id] = nil end end
local function advance(sec)
	for _ = 1, sec do
		now = now + 1
		local due = {}
		for id, t in pairs(timers) do
			if t.at <= now * 1000 then due[#due + 1] = {id = id, t = t} end
		end
		table.sort(due, function(a, b) return a.id < b.id end)
		for _, d in ipairs(due) do
			if timers[d.id] then
				timers[d.id] = nil
				d.t.fn((table.unpack or unpack)(d.t.args))
			end
		end
	end
end
local function P(x, y, z)
	return setmetatable({x = x, y = y, z = z}, {__index = {sendMagicEffect = function() end}, __add = function(a, b)
		return P(a.x + b.x, a.y + b.y, a.z + b.z)
	end})
end
Position = P
local events, moves, actions = {}, {}, {}
local function eventMock(kind)
	return function(name)
		local e = {name = name, kind = kind}
		function e:type(t) self.t = t end
		function e:separator() end
		function e:aid(a) self.aidv = a; if kind == "move" then moves[a] = self else actions[a] = self end end
		function e:id(i) actions[i] = self end
		function e:register() events[(self.name or kind) .. ":" .. tostring(self.t or kind)] = self end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"),
	eventMock("talk"), eventMock("action"), eventMock("move")
GAME_STATE_NORMAL = 1
local printed = {}
print = function(...) printed[#printed + 1] = table.concat({...}, " ") end -- luacheck: ignore
local realPrint = io.write
math.randomseed(7)

local players, creatures, monsters, log
local monsterSeq = 9000
local function reset()
	players, creatures, monsters, log = {}, {}, {}, {}
	timers = {}
end
reset()
local function newPlayer(id, name, pos)
	local p = {id = id, guid = id + 500, name = name, pos = pos, msgs = {}, cancels = {}, storage = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getPosition() return self.pos end
	function p:teleportTo(q) self.pos = P(q.x, q.y, q.z); log[#log + 1] = self.name .. " to " .. q.x .. "," .. q.y end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t; log[#log + 1] = self.name .. ": " .. t end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:say() end
	function p:remove() end
	function p:getGroup() return {getAccess = function() return false end, getId = function() return 1 end} end
	function p:getTown() return {getTemplePosition = function() return P(1, 1, 7) end} end
	players[id] = p
	creatures[#creatures + 1] = p
	return p
end
local function newMonster(name, pos)
	monsterSeq = monsterSeq + 1
	local m = {id = monsterSeq, name = name, pos = pos}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:getPosition() return self.pos end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:registerEvent() end
	function m:say() end
	function m:remove()
		monsters[self.id] = nil
		for i, c in ipairs(creatures) do
			if c == self then table.remove(creatures, i) break end
		end
	end
	monsters[m.id] = m
	creatures[#creatures + 1] = m
	log[#log + 1] = "monster " .. name
	return m
end
Player = function(k) return players[k] end
Monster = function(id) return monsters[id] end
Creature = function(id) return monsters[id] or players[id] end
Game = {
	getGameState = function() return 1 end,
	getPlayers = function()
		local l = {}
		for _, p in pairs(players) do l[#l + 1] = p end
		table.sort(l, function(a, b) return a.id < b.id end)
		return l
	end,
	getSpectators = function(c, _, _, minx, maxx, miny, maxy)
		local l = {}
		for _, cr in ipairs(creatures) do
			local q = cr:getPosition()
			if q.z == c.z and q.x >= c.x - minx and q.x <= c.x + maxx and q.y >= c.y - miny and q.y <= c.y + maxy then
				l[#l + 1] = cr
			end
		end
		return l
	end,
	createMonster = function(name, pos) return newMonster(name, pos) end,
	getReturnMessage = function() return "" end
}
local function tileAt(pos)
	for _, c in ipairs(creatures) do
		local q = c:getPosition()
		if q.x == pos.x and q.y == pos.y and q.z == pos.z then return c end
	end
	return nil
end
Tile = function(pos) return {getTopVisibleCreature = function() return tileAt(pos) end} end
playSound = function() end
local function soulCore()
	local item = {}
	function item:getId() return 30001 end
	function item:remove() self.used = true end
	return item
end
local pitLever = {}
function pitLever:getActionId() return 47392 end
function pitLever:transform() end
local function killAll()
	for id, m in pairs(monsters) do
		if m.name ~= "Base Core" then m:remove() end
	end
end
local function said(p, text)
	for _, t in ipairs(p.msgs) do
		if t:find(text, 1, true) then return true end
	end
	return false
end

-- one soul pit run: two players at the pit, the core used, the waves killed as they come
local function pitRun(text)
	reset()
	assert((loadstring or load)(text, "=soulpit.lua"))()
	local a = newPlayer(1, "Aela", P(3030, 3010, 8))
	local b = newPlayer(2, "Bram", P(3030, 3011, 8))
	actions[30001].onUse(a, soulCore(), a.pos, pitLever)
	advance(6)
	for _ = 1, 4 do
		advance(2)
		killAll()
	end
	advance(3)
	return table.concat(log, "\n"), a, b
end

-- 1. without the Chaos scripts the patched pit is the stock pit
local stockLog = pitRun(SOULPIT)
local patchedLog = pitRun(pit)
ok(stockLog:find("Aela to 3012,3014", 1, true) and stockLog:find("completed the \"Mudling\"", 1, true), "stock: a full run")
eq(patchedLog, stockLog, "patched without the Chaos scripts: the same run")

-- 2. with the Chaos scripts
local bars = {}
ChaosTileBars = {set = function(id, def) bars[id] = def end, removePrefix = function(prefix)
	for id in pairs(bars) do
		if id:sub(1, #prefix) == prefix then bars[id] = nil end
	end
end}
ChaosNotify = {send = function() return true end}
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/instance_limits.lua")
local BR = ChaosBossRooms
eq(BR.limitOf({chaosRoom = "soulpit"}), 900, "soul pit: 15 minutes")
eq(BR.limitOf({chaosRoom = "towerdefense"}), 1200, "tower defence: 20 minutes")

do -- soul pit
	reset()
	assert((loadstring or load)(pit, "=soulpit.lua"))()
	BR.collect()
	local room = BR.rooms.aid47392
	ok(room ~= nil, "the pit is a room")
	ok(room.bossArea.fromPos.x == 3000 and room.bossArea.toPos.x == 3024 and room.bossArea.fromPos.y == 3000
		and room.bossArea.toPos.y == 3015, "its box covers the room and every spawn spot")
	local a = newPlayer(1, "Aela", P(3030, 3010, 8))
	local b = newPlayer(2, "Bram", P(3030, 3011, 8))
	actions[30001].onUse(a, soulCore(), a.pos, pitLever)
	local s = BR.sessions.aid47392
	ok(s and s.limit == 900 and s.guids[a.guid] and s.guids[b.guid], "a session of 15 minutes for the group")
	ok(said(a, "Soulpit: you have 15 min"), "told the time: " .. table.concat(a.msgs, " | "))
	advance(6)
	eq(a.pos.x, 3012, "the group is in the pit")
	-- another group with a core: locked
	local c = newPlayer(3, "Cato", P(3030, 3010, 8))
	a.pos = P(3012, 3014, 8)
	local core = soulCore()
	actions[30001].onUse(c, core, c.pos, pitLever)
	ok((c.cancels[1] or ""):find("frees up in", 1, true) ~= nil, "locked, with the time: " .. tostring(c.cancels[1]))
	ok(not core.used, "the core is not spent")
	-- a core used on something else is not the pit's business
	local other = {getActionId = function() return 1 end, transform = function() end}
	actions[30001].onUse(c, soulCore(), c.pos, other)
	eq(#c.cancels, 1, "a core used elsewhere: no lock message")
	-- the group lingers on a wave: warnings, then time up
	advance(900 - 300 - 6 + 1)
	ok(said(a, "Soulpit: 5 minutes left"), "5 minute warning")
	local wave = 0
	for _ in pairs(monsters) do wave = wave + 1 end
	ok(wave > 0, "a wave is up")
	advance(300)
	ok(a.pos.x == 31589 and a.pos.y == 32281, "time up: at the pit's lobby spot")
	eq(b.pos.y, 32281, "everyone")
	eq(next(monsters), nil, "the wave removed")
	eq(BR.sessions.aid47392, nil, "the pit is free")
	-- the pit's own state was reset: the next group gets a full fresh run (wave 1, then 2, then done)
	log = {}
	c.pos = P(3030, 3010, 8)
	actions[30001].onUse(c, soulCore(), c.pos, pitLever)
	advance(6)
	ok(table.concat(log, "\n"):find("monster angry mudling", 1, true) ~= nil, "the next run starts at wave 1")
	for _ = 1, 4 do
		advance(2)
		killAll()
	end
	advance(2)
	ok(said(c, "completed the \"Mudling\""), "and completes")
	eq(BR.sessions.aid47392.state, "won", "a completed pit is like a boss kill")
	advance(66)
	eq(c.pos.y, 32281, "65 s later the room closes: at the lobby spot")
	eq(BR.sessions.aid47392, nil, "free")
end

do -- tower defence
	reset()
	assert((loadstring or load)(tower, "=tower_defense.lua"))()
	assert((loadstring or load)(entrance, "=entrance_teleport.lua"))()
	BR.collect()
	ok(BR.rooms.aid37931 ~= nil, "the arena is a room")
	local lever = actions[37931]
	local a = newPlayer(1, "Aela", P(31206, 32294, 8))
	moves[25485].onStepIn(a, {}, a.pos, P(31206, 32295, 8))
	eq(a.pos.x, 31205, "before a run the entrance lets in")
	local b = newPlayer(2, "Bram", P(31207, 32270, 8))
	a.storage[86704], a.storage[88709] = 5, 1
	lever.onUse(a, {actionid = 37931}, a.pos)
	local s = BR.sessions.aid37931
	ok(s and s.limit == 1200 and s.guids[a.guid] and s.guids[b.guid], "the lever: a 20 minute session for the players inside")
	ok(bars["room:aid37931:lever"] and bars["room:aid37931:lever"].pos.y == 32295, "'Room in use' over the drop at the entrance")
	-- a newcomer at the entrance: sent back
	local c = newPlayer(3, "Cato", P(31206, 32294, 8))
	moves[25485].onStepIn(c, {}, c.pos, P(31206, 32295, 8))
	eq(c.pos.y, 32295, "the entrance sends a newcomer back where they came from")
	ok((c.cancels[1] or ""):find("frees up in", 1, true) ~= nil, "with the time")
	-- the group's own second pull
	lever.onUse(b, {actionid = 37931}, b.pos)
	ok((b.cancels[1] or ""):find("Your run is still going", 1, true) ~= nil, "own lever: still going: " .. tostring(b.cancels[1]))
	advance(30)
	local spawned = 0
	for _, m in pairs(monsters) do if m.name == "ash imp" then spawned = spawned + 1 end end
	ok(spawned > 0, "the waves come")
	advance(1200 - 30)
	eq(a.pos.y, 32295, "time up: at the exit drop")
	eq(b.pos.y, 32295, "everyone")
	eq(a.storage[86704], 0, "the summon counters reset")
	eq(a.storage[88709], 0, "the inside mark reset")
	eq(next(monsters), nil, "the core and the waves removed")
	eq(BR.sessions.aid37931, nil, "the arena is free")
	advance(10)
	eq(next(monsters), nil, "spawning stopped")
	-- a win: the room closes once everyone is out (here 65 s later with the group still inside)
	a.pos = P(31205, 32270, 8)
	lever.onUse(a, {actionid = 37931}, a.pos)
	TowerTest.reward()
	eq(BR.sessions.aid37931.state, "won", "a win ends the run")
	advance(66)
	eq(a.pos.y, 32295, "out 65 s later")
	-- a loss: the script sends everyone out itself; the room frees up at once
	a.pos = P(31205, 32270, 8)
	b.pos = P(31207, 32270, 8)
	lever.onUse(a, {actionid = 37931}, a.pos)
	advance(15)
	killAll()
	TowerTest.lose() -- the stock loss runs when the last wave monster is gone; here the test calls it
	eq(BR.sessions.aid37931.state, "won", "a loss ends the run too")
	advance(1)
	eq(BR.sessions.aid37931, nil, "nobody inside after a loss: free at once")
	a.pos = P(31205, 32270, 8)
	lever.onUse(a, {actionid = 37931}, a.pos)
	TowerTest.lose2()
	eq(BR.sessions.aid37931.state, "won", "the other loss path ends the run too")
end

os.execute("rm -rf '" .. root .. "'")
if fails > 0 then
	realPrint(string.format("base_eventrooms_patch_test: %d of %d checks failed\n", fails, checks))
	for _, l in ipairs(printed) do
		if l:find("FAIL", 1, true) then realPrint(l .. "\n") end
	end
	os.exit(1)
end
realPrint(string.format("base_eventrooms_patch_test: all %d checks passed\n", checks))

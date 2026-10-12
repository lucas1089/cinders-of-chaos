-- Run from the server/ folder: luajit tests/base_stalls_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_stalls.py on copies of the stock code it changes (written here), then the stock and the patched
-- scripts run against the same mocked engine and must do the same:
--   expedition announcement  the same players get the sound, the map mark and the broadcast, in the same order (a player
--                            under a monster, two players on one tile, other floors and places outside the box)
--   upgrade slots            the same conditions added and removed, tick after tick; the description is parsed once
-- and: a second run changes nothing, --dry-run writes nothing, a removal loop (not a player scan) is left alone.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_stalls_patch_test: python3 not found, skipped")
	return
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
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

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
local expDir = data .. "/scripts/customs/expeditions_system/expeditions/island/lost_objects"
local bossDir = data .. "/scripts/customs/expeditions_system/expeditions/bosses"
local upDir = data .. "/scripts/customs/upgrade"
os.execute("mkdir -p '" .. expDir .. "' '" .. bossDir .. "' '" .. upDir .. "'")

-- the stock code (as the base server has it; the box made small here so the stock scan stays quick)
local EXPEDITION = [[
local npc1Position = Position(31597, 31395, 7)

for i, time in ipairs({"06:17:00"}) do
    local LostObjectsExpedition = GlobalEvent("LostObjectsExpedition" .. i)
    function LostObjectsExpedition.onTime(interval)
        local fromPosX = Position(100, 200, 7)
        local toPosX = Position(140, 230, 7)
        for x = fromPosX.x, toPosX.x do
            for y = fromPosX.y, toPosX.y do
                local checkPos = Position(x, y, fromPosX.z)
                local tile = Tile(checkPos)

                if tile then
                    local creature = tile:getTopCreature()
                    if creature and creature:isPlayer() then
                        playSoundPlayer(creature, "expedition.ogg")
                        creature:addMapMark(Position(31597, 31395, 7), 22, "Expedition: Find Lost Objects")
                        Game.broadcastMessage("The expedition guide has arrived on the island.", MESSAGE_EVENT_ADVANCE)
                    end
                end
            end
        end
        return true
    end
    LostObjectsExpedition:time(time)
    LostObjectsExpedition:register()
end
]]

-- a boss script: its announcement scan is patched, its removal loop (monsters, not players) is not
local BOSS = [[
local fromPos = Position(100, 200, 9)
local toPos = Position(110, 210, 9)

local function announceSpawn()
    for x = fromPos.x, toPos.x do
        for y = fromPos.y, toPos.y do
            local checkPos = Position(x, y, fromPos.z)
            local tile = Tile(checkPos)

            if tile then
                local creature = tile:getTopCreature()
                if creature and creature:isPlayer() then
                    Game.broadcastMessage("The Boss has spawned.", MESSAGE_EVENT_ADVANCE)
                end
            end
        end
    end
end

local function removeMonster(areaFrom, areaTo, monsterName)
    for x = areaFrom.x, areaTo.x do
        for y = areaFrom.y, areaTo.y do
            local checkPos = Position(x, y, areaFrom.z)
            local tile = Tile(checkPos)

            if tile then
                local creature = tile:getTopCreature()
                if creature and creature:isMonster() and creature:getName():lower() == monsterName:lower() then
                    creature:remove()
                end
            end
        end
    end
end

BossAnnounce, BossRemove = announceSpawn, removeMonster
]]

local UPGRADE = [[
local slotAttribute = {}
slotAttribute.maxSlots = 3
slotAttribute.baseSubids = 90
slotAttribute.cache = {}

local Attr = {}
Attr.__index = Attr
Attr.init = function(slot)
 local attr = {}
 setmetatable(attr, Attr)
 attr.name = slot.name
 attr.value = slot.value
 attr.percent = slot.percent
 return attr
end
setmetatable(Attr, {
 __call = function(_, ...) return Attr.init(...) end,
 __eq = function(a, b) return a.name == b.name and a.value == b.value and a.percent == b.percent end
})

slotAttribute.conditions = {
    ["Club"] = {Type = CONDITION_ATTRIBUTES, Attr = CONDITION_PARAM_SKILL_CLUB},
    ["Sword"] = {Type = CONDITION_ATTRIBUTES, Attr = CONDITION_PARAM_SKILL_SWORD},
}

slotAttribute.getItemSlots = function(item)
    local slots = {}
    for slot in string.gmatch(Item.getDescription(item), "(%[.-%])") do
    local name = string.match(slot, "%[(%a+)%p")
        local value = tonumber(string.match(slot, "%p(%d+)%]"))
        local valuePercent = tonumber(string.match(slot, "%p(%d+)%%+%]"))
        slots[#slots + 1] = {
        name = name,
        value = value,
        valuePercent = valuePercent
        }
    end
    return slots
   end

slotAttribute.onSlotEquip = function(player, slots, slotIndex)
    for index, slot in pairs(slots) do
        local attr = Attr(slot)
        local subid = slotAttribute.baseSubids + slotIndex + (CONST_SLOT_AMMO * index)
        if not slotAttribute.cache[player.uid][subid] or slotAttribute.cache[player.uid][subid] ~= attr then
            if slotAttribute.cache[player.uid][subid] and slotAttribute.cache[player.uid][subid] ~= attr then
                player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, subid, true)
            end
        local info = slotAttribute.conditions[attr.name]
            if info then
                local condition = Condition(info.Type, CONDITIONID_DEFAULT)
                    if condition then
                        condition:setParameter(info.Attr, attr.value)
                        condition:setParameter(CONDITION_PARAM_SUBID, subid)
                        player:addCondition(condition)
                        slotAttribute.cache[player.uid][subid] = attr
                    end
            end
        end
    end
end

slotAttribute.autoDetection = function(playerId)
    local player = Player(playerId)
        if player then
            if not slotAttribute.cache[playerId] then
                slotAttribute.cache[playerId] = {}
            end
            for slot = CONST_SLOT_HEAD, CONST_SLOT_GLOVES do
                local item = player:getSlotItem(slot)
                    if item then
                        local slots = slotAttribute.getItemSlots(item)
                        slotAttribute.onSlotEquip(player, slots, slot)
                            if #slots < slotAttribute.maxSlots then
                                for index = #slots+1, slotAttribute.maxSlots do
                                    local subid = slotAttribute.baseSubids + slot + (CONST_SLOT_GLOVES * index)
                                        player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, subid, true)
                                end
                            end
                    else
                        for index = 1, slotAttribute.maxSlots do
                            local subid = slotAttribute.baseSubids + slot + (CONST_SLOT_GLOVES * index)
                            player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, subid, true)
                        end
                    end
            end
            addEvent(slotAttribute.autoDetection, 100, playerId)
        else
            slotAttribute.cache[playerId] = nil
    end
end

UpgradeAutoDetection = slotAttribute.autoDetection
]]

local expPath = expDir .. "/spawn_npc_lost_objects.lua"
local bossPath = bossDir .. "/spawn_boss.lua"
local upPath = upDir .. "/upgrade_slot_item.lua"
writeFile(expPath, EXPEDITION)
writeFile(bossPath, BOSS)
writeFile(upPath, UPGRADE)

local tool = "python3 -I tools/patch_base_stalls.py '" .. data .. "'"
local out = sh(tool .. " --dry-run")
ok(out:find("spawn_npc_lost_objects.lua: patched %(1 loop%) %(dry run"), "dry run reports the expedition: " .. out)
ok(out:find("upgrade_slot_item.lua: patched %(dry run"), "dry run reports the upgrade script")
ok(readFile(expPath) == EXPEDITION and readFile(upPath) == UPGRADE, "dry run writes nothing")
out = sh(tool)
ok(out:find("spawn_npc_lost_objects.lua: patched %(1 loop%)"), "expedition patched: " .. out)
ok(out:find("spawn_boss.lua: patched %(1 loop%)"), "boss announcement patched, the removal loop left alone")
ok(out:find("upgrade_slot_item.lua: patched"), "upgrade script patched")
local patchedExp, patchedBoss, patchedUp = readFile(expPath), readFile(bossPath), readFile(upPath)
ok(patchedExp:find("chaosPlayerTiles", 1, true) ~= nil, "the helper is in the expedition script")
ok(select(2, patchedBoss:gsub("for x = ", "")) == 1, "the boss removal loop still scans its box")
ok(patchedUp:find("local slots = chaosItemSlots(item)", 1, true) ~= nil, "the check uses the cached slots")
out = sh(tool)
ok(out:find("spawn_npc_lost_objects.lua: already") and out:find("upgrade_slot_item.lua: already"), "second run: already")
ok(readFile(expPath) == patchedExp and readFile(upPath) == patchedUp, "second run changes nothing")
local empty = root .. "/empty"
os.execute("mkdir -p '" .. empty .. "'")
out = sh("python3 -I tools/patch_base_stalls.py '" .. empty .. "'; echo status=$?")
ok(out:find("nothing to do") and out:find("status=0"), "no base scripts: nothing to do, status 0")

-- ------------------------------------------------------------------ mocked engine
MESSAGE_EVENT_ADVANCE = 1
CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT = 1, 0
CONDITION_PARAM_SKILL_CLUB, CONDITION_PARAM_SKILL_SWORD, CONDITION_PARAM_SUBID = 10, 11, 12
CONST_SLOT_HEAD, CONST_SLOT_AMMO, CONST_SLOT_GLOVES = 1, 10, 11

local log
local tiles, players
function Position(x, y, z)
	return {x = x, y = y, z = z}
end
local function key(x, y, z)
	return x .. ":" .. y .. ":" .. z
end
function Tile(pos)
	local stack = tiles[key(pos.x, pos.y, pos.z)]
	if not stack then
		return nil
	end
	return {getTopCreature = function() return stack[1] end}
end
local function creature(name, isPlayer, pos)
	local c = {name = name, pos = pos}
	function c:isPlayer() return isPlayer end
	function c:isMonster() return not isPlayer end
	function c:getName() return name end
	function c:getPosition() return {x = pos.x, y = pos.y, z = pos.z} end
	function c:addMapMark(p, t, text) log[#log + 1] = "mark " .. name .. " " .. text end
	function c:remove() log[#log + 1] = "remove " .. name end
	return c
end
function playSoundPlayer(c, sound) log[#log + 1] = "sound " .. c:getName() end
Game = {
	broadcastMessage = function(text) log[#log + 1] = "broadcast " .. text end,
	getPlayers = function() return players end,
}
local events = {}
function GlobalEvent(name)
	local e = {name = name}
	function e:time() end
	function e:register() events[name] = self end
	return e
end

-- the world: players in and out of the box, two on one tile, one under a monster, one on another floor
local function world()
	tiles, players = {}, {}
	local function put(c, x, y, z)
		local k = key(x, y, z)
		tiles[k] = tiles[k] or {}
		table.insert(tiles[k], 1, c) -- the last one put is on top
		if c:isPlayer() then
			players[#players + 1] = c
		end
	end
	put(creature("Ann", true, {x = 120, y = 210, z = 7}), 120, 210, 7)
	put(creature("Bob", true, {x = 101, y = 229, z = 7}), 101, 229, 7)
	put(creature("Cid", true, {x = 120, y = 210, z = 7}), 120, 210, 7) -- on Ann's tile, on top
	put(creature("Dan", true, {x = 130, y = 205, z = 7}), 130, 205, 7)
	put(creature("Rat", false, {x = 130, y = 205, z = 7}), 130, 205, 7) -- a monster on top of Dan
	put(creature("Eve", true, {x = 120, y = 210, z = 8}), 120, 210, 8) -- another floor
	put(creature("Fay", true, {x = 141, y = 210, z = 7}), 141, 210, 7) -- just outside
	put(creature("Gus", true, {x = 140, y = 200, z = 7}), 140, 200, 7) -- the corner
	put(creature("Hal", true, {x = 100, y = 230, z = 7}), 100, 230, 7) -- the other corner
	put(creature("Boss", false, {x = 105, y = 205, z = 9}), 105, 205, 9)
	put(creature("Ivy", true, {x = 104, y = 204, z = 9}), 104, 204, 9)
end

local function runExpedition(text)
	world()
	log = {}
	events = {}
	assert(load(text))()
	events.LostObjectsExpedition1.onTime(0)
	return table.concat(log, "\n")
end
local stockLog = runExpedition(EXPEDITION)
local patchedLog = runExpedition(patchedExp)
ok(stockLog ~= "" and patchedLog == stockLog, "expedition: the same players, marks and broadcasts in the same order")
ok(stockLog:find("sound Cid", 1, true) and not stockLog:find("sound Ann", 1, true), "two on a tile: the top one")
ok(not stockLog:find("Dan", 1, true), "a player under a monster: nothing (stock and patched)")
ok(not patchedLog:find("Eve", 1, true) and not patchedLog:find("Fay", 1, true), "other floor and outside: nothing")
ok(patchedLog:find("Gus", 1, true) and patchedLog:find("Hal", 1, true), "the box corners count")

local function runBoss(text)
	world()
	log = {}
	assert(load(text))()
	BossAnnounce()
	BossRemove(Position(100, 200, 9), Position(110, 210, 9), "Boss")
	return table.concat(log, "\n")
end
ok(runBoss(BOSS) == runBoss(patchedBoss), "boss script: the same announcement and removal")

-- upgrade slots: a player with items whose descriptions change between ticks
local function runUpgrade(text)
	log = {}
	local timers = {}
	function addEvent(fn, ms, ...)
		timers[#timers + 1] = {fn = fn, args = {...}}
	end
	local descriptions = {
		[1] = "You see a helmet. [Club+2], [Sword+1]",
		[4] = "You see an armor.",
		[8] = "You see a ring. [Sword+3]",
	}
	local parsed = 0
	Item = {getDescription = function(item)
		parsed = parsed + 1
		return descriptions[item.slot]
	end}
	local player = {uid = 7}
	function player:getSlotItem(slot)
		return descriptions[slot] and {slot = slot} or nil
	end
	function player:removeCondition(t, id, subid) log[#log + 1] = "remove " .. subid end
	function player:addCondition(c) log[#log + 1] = "add " .. c.subid .. " " .. c.attr .. "=" .. c.value end
	function Player(id)
		return id == 7 and player or nil
	end
	function Condition(t, id)
		local c = {}
		function c:setParameter(p, v)
			if p == CONDITION_PARAM_SUBID then
				c.subid = v
			else
				c.attr, c.value = p, v
			end
		end
		return c
	end
	assert(load(text))()
	local calls = {}
	local function tick()
		local t = table.remove(timers, 1)
		t.fn((table.unpack or unpack)(t.args))
	end
	UpgradeAutoDetection(7)
	tick()
	descriptions[4] = "You see an armor. [Club+1]" -- upgraded between two checks
	tick()
	descriptions[8] = nil -- the ring taken off
	tick()
	tick()
	return table.concat(log, "\n"), parsed
end
local stockUp, stockParsed = runUpgrade(UPGRADE)
local patchedUp2, patchedParsed = runUpgrade(patchedUp)
ok(stockUp ~= "" and patchedUp2 == stockUp, "upgrade: the same conditions added and removed")
-- the stock check reads each description once per tick; the patched one reads it once per tick too, and once more
-- for a text it has not parsed before (the parse itself is kept)
ok(patchedParsed == stockParsed + 4, "upgrade: each new description parsed once (4 texts), then only read: "
	.. stockParsed .. " / " .. patchedParsed)

os.execute("rm -rf '" .. root .. "'")
if fails > 0 then
	print(string.format("base_stalls_patch_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("base_stalls_patch_test: all %d checks passed", checks))

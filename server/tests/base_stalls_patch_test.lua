-- Run from the server/ folder: luajit tests/base_stalls_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_stalls.py on copies of the stock code it changes (written here), then the stock and the patched
-- scripts run against the same mocked engine and must do the same:
--   expedition announcement  the same players get the sound, the map mark and the broadcast, in the same order (a player
--                            under a monster, two players on one tile, other floors and places outside the box)
--   upgrade slots            the same conditions once a change has settled (1 s); each description parsed once
--   upgrade check interval   a check at login and at once on an equip / unequip move, every player once a second in
--                            12 groups (instead of 10 times a second each), a player who left dropped, a reload
--                            of the scripts does not run two chains
-- and: a second run changes nothing, --dry-run writes nothing, a removal loop (not a player scan) is left alone, CRLF
-- files stay CRLF, a script patched by the older tool (slot cache only) gets the interval step.
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

local creatureEvent = CreatureEvent()

function creatureEvent.onLogin(player)
    slotAttribute.autoDetection(player.uid)
    return true
end

creatureEvent:register()
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
ok(out:find("upgrade_slot_item.lua: patched %(slot cache, check every 1 s and on equip%) %(dry run"),
	"dry run reports the upgrade script")
ok(readFile(expPath) == EXPEDITION and readFile(upPath) == UPGRADE, "dry run writes nothing")
out = sh(tool)
ok(out:find("spawn_npc_lost_objects.lua: patched %(1 loop%)"), "expedition patched: " .. out)
ok(out:find("spawn_boss.lua: patched %(1 loop%)"), "boss announcement patched, the removal loop left alone")
ok(out:find("upgrade_slot_item.lua: patched"), "upgrade script patched")
local patchedExp, patchedBoss, patchedUp = readFile(expPath), readFile(bossPath), readFile(upPath)
ok(patchedExp:find("chaosPlayerTiles", 1, true) ~= nil, "the helper is in the expedition script")
ok(select(2, patchedBoss:gsub("for x = ", "")) == 1, "the boss removal loop still scans its box")
ok(patchedUp:find("local slots = chaosItemSlots(item)", 1, true) ~= nil, "the check uses the cached slots")
ok(not patchedUp:find("addEvent(slotAttribute.autoDetection", 1, true), "no timer per player")
ok(patchedUp:find("chaosUpgradeMoved:register(13)", 1, true) ~= nil, "the equip callback is registered")
out = sh(tool)
ok(out:find("spawn_npc_lost_objects.lua: already") and out:find("upgrade_slot_item.lua: already"), "second run: already")
ok(readFile(expPath) == patchedExp and readFile(upPath) == patchedUp, "second run changes nothing")
-- a script patched by the older tool (its slot cache step only): the interval step is added, the cache not doubled
writeFile(upPath, UPGRADE)
sh("python3 -I -c 'import sys; sys.path.insert(0, \"tools\"); import patch_base_stalls as p; f = sys.argv[1]; "
	.. "t = open(f, newline=\"\").read(); open(f, \"w\", newline=\"\").write(p.patch_upgrade_cache(t)[0])' '"
	.. upPath .. "'")
local cacheOnly = readFile(upPath)
ok(cacheOnly:find("chaosItemSlots", 1, true) and not cacheOnly:find("check interval", 1, true),
	"the older patch made for the test")
out = sh(tool)
ok(out:find("upgrade_slot_item.lua: patched %(check every 1 s and on equip; slot cache already%)"),
	"older patch: the interval step added: " .. out)
ok(readFile(upPath) == patchedUp, "older patch: the same text as a fresh install")
-- CRLF: the stock script with Windows line ends is patched the same and stays CRLF
writeFile(upPath, (UPGRADE:gsub("\n", "\r\n")))
out = sh(tool)
local crlfUp = readFile(upPath)
ok(out:find("upgrade_slot_item.lua: patched %(slot cache, check every 1 s and on equip%)"), "CRLF patched: " .. out)
ok(crlfUp == patchedUp:gsub("\n", "\r\n") and not crlfUp:find("[^\r]\n"), "CRLF: same text, every line CRLF")
writeFile(upPath, patchedUp)
local empty = root .. "/empty"
os.execute("mkdir -p '" .. empty .. "'")
out = sh("python3 -I tools/patch_base_stalls.py '" .. empty .. "'; echo status=$?")
ok(out:find("nothing to do") and out:find("status=0"), "no base scripts: nothing to do, status 0")

-- ------------------------------------------------------------------ mocked engine
MESSAGE_EVENT_ADVANCE = 1
CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT = 1, 0
CONDITION_PARAM_SKILL_CLUB, CONDITION_PARAM_SKILL_SWORD, CONDITION_PARAM_SUBID = 10, 11, 12
CONST_SLOT_HEAD, CONST_SLOT_AMMO, CONST_SLOT_GLOVES = 1, 10, 16 -- as the engine (creature.h)
CONTAINER_POSITION = 0xFFFF

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

-- upgrade slots: the stock script (a 100 ms timer per player) and the patched one (login, equip moves, 12 groups a
-- second) against the same mocked engine with a clock; the same steps on 24 players
local unpackf = table.unpack or unpack
local INV = CONTAINER_POSITION
local function runUpgrade(text, patched)
	local now, queue, seq = 0, {}, 0
	function addEvent(fn, ms, ...)
		seq = seq + 1
		queue[#queue + 1] = {at = now + ms, seq = seq, fn = fn, args = {...}, n = select("#", ...)}
	end
	local function advance(ms)
		local stop = now + ms
		while true do
			local best
			for i, e in ipairs(queue) do
				local b = best and queue[best]
				if e.at <= stop and (not b or e.at < b.at or (e.at == b.at and e.seq < b.seq)) then
					best = i
				end
			end
			if not best then
				break
			end
			local e = table.remove(queue, best)
			now = e.at
			e.fn(unpackf(e.args, 1, e.n))
		end
		now = stop
	end
	local online, all, checks, texts = {}, {}, {}, {}
	local described, reads, ntexts = 0, 0, 0
	local loginEvent, callbacks = nil, {}
	local function newPlayer(id)
		local p = {uid = id, items = {}, conds = {}}
		function p:getId() return id end
		function p:getSlotItem(slot)
			if self.items[slot] then
				reads = reads + 1
				return {owner = self, slot = slot}
			end
		end
		function p:removeCondition(t, cid, subid) self.conds[subid] = nil end
		function p:addCondition(c) self.conds[c.subid] = c.attr .. "=" .. c.value end
		return p
	end
	Item = {getDescription = function(item)
		described = described + 1
		local s = item.owner.items[item.slot]
		if not texts[s] then
			texts[s], ntexts = true, ntexts + 1
		end
		return s
	end}
	function Player(id)
		checks[id] = (checks[id] or 0) + 1
		return online[id]
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
	function CreatureEvent()
		local e = {}
		function e:register() loginEvent = self end
		return e
	end
	EventCallback = {}
	function EventCallback:register()
		callbacks[#callbacks + 1] = rawget(self, "onItemMoved")
		self.onItemMoved = nil
	end
	Game.getPlayers = function()
		local list = {}
		for id = 1, 24 do
			if online[id] then
				list[#list + 1] = online[id]
			end
		end
		return list
	end
	assert(load(text))()

	local r = {snaps = {}}
	local function snap(name)
		local parts = {}
		for id = 1, 24 do
			local subids = {}
			for subid in pairs(all[id].conds) do
				subids[#subids + 1] = subid
			end
			table.sort(subids)
			for _, subid in ipairs(subids) do
				parts[#parts + 1] = id .. ":" .. subid .. "=" .. all[id].conds[subid]
			end
		end
		r.snaps[#r.snaps + 1] = name .. " " .. table.concat(parts, " ")
	end
	local function move(id, fromPos, toPos)
		local results = {}
		for _, cb in ipairs(callbacks) do
			results[#results + 1] = select("#", cb(all[id], {}, 1, fromPos, toPos, nil, nil))
		end
		return results
	end
	local function checksOf(id)
		return checks[id] or 0
	end

	-- 24 players log in at once; 7 wears a helmet with two slots, a plain armor and a ring; every second player a ring
	for id = 1, 24 do
		all[id] = newPlayer(id)
		if id % 2 == 0 then
			all[id].items[9] = "You see a ring. [Club+1]"
		end
	end
	all[7].items[1] = "You see a helmet. [Club+2], [Sword+1]"
	all[7].items[4] = "You see an armor."
	all[7].items[9] = "You see a ring. [Sword+3]"
	for id = 1, 24 do
		online[id] = all[id]
		loginEvent.onLogin(all[id])
	end
	snap("login")
	advance(1000)
	snap("1 s")

	-- a worn item gets a slot without a move (an upgrade used on it): applied within a second
	all[7].items[4] = "You see an armor. [Club+1]"
	local t0 = now
	local applied
	for _ = 1, 20 do
		advance(50)
		if all[7].conds[104] then
			applied = applied or now - t0
		end
	end
	r.upgradeDelay = applied
	snap("upgrade settled")

	-- a sword put on by hand (ground -> right hand): at once with the equip event
	all[7].items[5] = "You see a sword. [Sword+2]"
	local before = checksOf(7)
	r.equipCallbacks = move(7, {x = 100, y = 100, z = 7}, {x = INV, y = 5, z = 0})
	r.equipChecks = checksOf(7) - before
	r.equipAtOnce = all[7].conds[105]
	advance(1000)
	snap("equip settled")

	-- taken off into the backpack: a check at once; then a move between two containers: no check
	all[7].items[5] = nil
	before = checksOf(7)
	move(7, {x = INV, y = 5, z = 0}, {x = INV, y = 64, z = 0})
	r.unequipChecks = checksOf(7) - before
	before = checksOf(7)
	move(7, {x = INV, y = 64, z = 1}, {x = INV, y = 65, z = 0})
	r.containerChecks = checksOf(7) - before
	advance(1000)
	snap("unequip settled")

	-- a ring that ends (decay): no move event, gone within a second
	all[8].items[9] = nil
	advance(1000)
	snap("decay settled")

	-- the rate and the spread: checks per player over 10 periods of the groups (9960 ms), the most in one group tick
	local start = {}
	for id = 1, 24 do
		start[id] = checksOf(id)
	end
	r.maxPerStep = 0
	for _ = 1, 120 do
		local stepStart = 0
		for id = 1, 24 do
			stepStart = stepStart + checksOf(id)
		end
		advance(83)
		local n = -stepStart
		for id = 1, 24 do
			n = n + checksOf(id)
		end
		r.maxPerStep = math.max(r.maxPerStep, n)
	end
	r.perPlayer = {}
	for id = 1, 24 do
		r.perPlayer[id] = checksOf(id) - start[id]
	end
	snap("10 s")

	-- 7 logs out: dropped within a second, no checks after that
	online[7] = nil
	advance(1100)
	before = checksOf(7)
	advance(3000)
	r.afterLogout = checksOf(7) - before
	snap("logout")

	r.described, r.reads, r.texts = described, reads, ntexts
	if patched then
		-- a reload of the scripts: the new chain takes the players online, the old chain stops
		assert(load(text))()
		advance(2000)
		snap("reload")
		for id = 1, 24 do
			start[id] = checksOf(id)
		end
		advance(9960)
		r.afterReload = {}
		for id = 1, 24 do
			r.afterReload[id] = checksOf(id) - start[id]
		end
	end
	return r
end

local stock = runUpgrade(UPGRADE, false)
local new = runUpgrade(patchedUp, true)
for i, s in ipairs(stock.snaps) do
	ok(new.snaps[i] == s, "upgrade: the same conditions at '" .. s:match("^[^%d]*") .. "':\n  stock   " .. s ..
		"\n  patched " .. tostring(new.snaps[i]))
end
ok(#stock.snaps == 8 and stock.snaps[1]:find("7:", 1, true), "upgrade: the snapshots hold conditions")
ok(stock.upgradeDelay and stock.upgradeDelay <= 100, "stock: a slot on a worn item applied within 100 ms")
ok(new.upgradeDelay and new.upgradeDelay <= 1000, "patched: a slot on a worn item applied within 1 s: "
	.. tostring(new.upgradeDelay))
ok(new.equipAtOnce == CONDITION_PARAM_SKILL_SWORD .. "=2" and new.equipChecks == 1, "patched: equip applied at once")
ok(new.equipCallbacks[1] == 0, "patched: the equip callback returns nothing (later callbacks still run)")
ok(stock.equipAtOnce == nil and #stock.equipCallbacks == 0, "stock: no equip callback (the next 100 ms tick)")
ok(new.unequipChecks == 1 and new.containerChecks == 0, "patched: a check on unequip, none between containers")
local rateOk = true
for id = 1, 24 do
	if id ~= 7 and (new.perPlayer[id] ~= 10 or stock.perPlayer[id] < 99) then
		rateOk = false
	end
end
ok(rateOk, "every player checked once a second (10 in 9960 ms) instead of 10 times: " .. new.perPlayer[1] .. " / "
	.. stock.perPlayer[1])
ok(new.maxPerStep == 2, "patched: one group (2 of 24 players) per 83 ms tick: " .. new.maxPerStep)
ok(new.afterLogout == 0 and stock.afterLogout == 0, "a player who left is no longer checked")
local reloadOk = true
for id = 1, 24 do
	if id ~= 7 and new.afterReload[id] ~= 10 then
		reloadOk = false
	end
end
ok(reloadOk, "after a reload: one chain, every player still once a second")
-- the stock check parses each description it reads; the patched one reads it the same way and parses each text once
ok(stock.described == stock.reads and new.described == new.reads + new.texts, "upgrade: each description parsed "
	.. "once: " .. new.described .. " reads " .. new.reads .. " texts " .. new.texts)

os.execute("rm -rf '" .. root .. "'")
if fails > 0 then
	print(string.format("base_stalls_patch_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("base_stalls_patch_test: all %d checks passed", checks))

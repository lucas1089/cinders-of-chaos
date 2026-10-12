-- Run from the server/ folder: luajit tests/base_dungeonentry_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_dungeonentry.py on a copy of the base dungeon window script (dungeon_mod.lua, written here), then:
--   tool      dry run writes nothing; LF and CRLF copies patched, CRLF kept; a second run changes nothing; another shape
--             is listed and left alone; no script: nothing to do, status 0
--   stock     without the Chaos scripts the stock and the patched script do the same, click by click: the "team inside"
--             refusal, level, party, leader, party size, safe zone, cooldown, distance, the teleports and the timer's
--             exit (the patched one without the tile scans: Tile() calls counted, and timed on this mock)
--   chaos     with dungeons.lua loaded: the window's group becomes one run of dungeons.lua (one per dungeon, listed by
--             /instances), "A team is already inside." with the wait, the queue shows the wait too, the 45 minute cap
--             with warnings, time up: back to the entry, the window's text, the window's cooldown end, the monsters
--             removed; a member who walked out is not pulled back; a logout leaves the run and no Player object is used
--             after it; the cooldown storage is the queue's; a staff close; a solo dungeon
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
	print("base_dungeonentry_patch_test: python3 not found, skipped")
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

-- the base server's dungeon window script, as it is (only its Confirm and Details buttons)
local STOCK = [==[
function onModalWindow(player, modalWindowId, buttonId, choiceId)  
    
	player:unregisterEvent("DungeonSystem_Modal")

	local dg = DUNGEON_SYSTEM.Dungeons
	local msg = DUNGEON_SYSTEM.Messages
	local modal = DUNGEON_SYSTEM.Modal
	local sto = DUNGEON_SYSTEM.Storages	

    if (modalWindowId == DUNGEON_SYSTEM.Modal.ID) then
		
		if buttonId == 200 then
			
			local players = {}
			for x = dg[choiceId].FromPos.x, dg[choiceId].ToPos.x do
				for y = dg[choiceId].FromPos.y, dg[choiceId].ToPos.y do
					for z = dg[choiceId].FromPos.z, dg[choiceId].ToPos.z do
						local tile = Tile(x, y, z)
						local creature = tile:getTopCreature()
						if creature and creature:isPlayer() then
							players[#players+1] = creature
						end
					end
				end
			end
			
			if #players > 0 then
				player:getPosition():sendMagicEffect(CONST_ME_POFF)
				return player:sendTextMessage(MESSAGE_STATUS_SMALL, msg.PlayerInside)
			end
			
			if (dg[choiceId].NeedLevel) then
				if (player:getLevel() < dg[choiceId].Level) then
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(msg.MsgNeedLevel, dg[choiceId].Level))
					return false
				end
			end
			
			local pt = player:getParty()
			local partyMembers
			
			local party = {}
			party = partyMembers
			
			local fromPosPlayer = player:getPosition()
			
			if (dg[choiceId].NeedParty) then
				
				if not pt then
					
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg.MsgUniqueNeedParty)
					return false
				
				else
					
					partyMembers = pt:getMembers()
					local party = player:getParty():getMemberCount()
					
					if not (pt:getLeader():getName() == player:getName()) then
						
						player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg.MsgLeaderParty)
						return false
					
					else
					
						local partyMaisUm = party+1
						
						if not (partyMaisUm == dg[choiceId].AmountParty) then
							player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(msg.MsgNeedParty, dg[choiceId].AmountParty))
							return false
						end
						
						local names = {}
						local posOfPlayer = {}
						
						for i = 1, party do
						
							local ppt = partyMembers[i]
							local fromPosPpt = ppt:getPosition()
						
							if DUNGEON_SYSTEM.PzToEntry then
								if not getTileInfo(fromPosPpt).protection then
									player:getPosition():sendMagicEffect(CONST_ME_POFF)
									return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg.NeedPzMsg)
								elseif not getTileInfo(fromPosPlayer).protection then
									player:getPosition():sendMagicEffect(CONST_ME_POFF)
									return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg.NeedPzSoloMsg)
								end
							end
						
							-- SE TEM COOLDOWN
							if player:getStorageValue(sto.TimerCooldown) - os.time() > 0 or ppt:getStorageValue(sto.TimerCooldown) - os.time() > 0 then
								if player:getStorageValue(sto.TimerCooldown) - os.time() > 0 then
									player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(msg.ToCooldown, string.format(player:getStorageValue(sto.TimerCooldown)-os.time())))
									player:getPosition():sendMagicEffect(CONST_ME_POFF)
									ppt:getPosition():sendMagicEffect(CONST_ME_POFF)
								else
									player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(msg.WaitFriendsCooldown, string.format(ppt:getStorageValue(sto.TimerCooldown)-os.time())))
									player:getPosition():sendMagicEffect(CONST_ME_POFF)
									ppt:getPosition():sendMagicEffect(CONST_ME_POFF)
								end
								return false
							end
							
							names[i] = ppt:getName()
							
						end
						
						local positionPlayer = player:getPosition()
						local distance = DUNGEON_SYSTEM.SQMsDistanceOfLeader
						
						for x = positionPlayer.x - distance, positionPlayer.x + distance do
							for y = positionPlayer.y - distance, positionPlayer.y + distance do
								for z = positionPlayer.z, positionPlayer.z do
									local tileP = Tile(x, y, z)
									local creatureP = tileP:getTopCreature()
									if creatureP and creatureP:isPlayer() then
										for xx = 1, #names do
											if creatureP:getName() == names[xx] then
												posOfPlayer[#posOfPlayer+1] = creatureP
											end
										end
									end
								end
							end
						end
						
						if #posOfPlayer+1 ~= dg[choiceId].AmountParty then
							return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg.MsgDistanceLeader)
						end
						
						if dg[choiceId].SpawnMonsters then
							for m, l in pairs(dg[choiceId].Monsters) do
								Game.createMonster(m, l)
							end
						end
						
						player:teleportTo(dg[choiceId].DungeonPos)
						player:getPosition():sendMagicEffect(40)
						player:say(msg.ToEntry, TALKTYPE_MONSTER_SAY)
						
						addEvent(function()
							player:teleportTo(fromPosPlayer)
							player:setStorageValue(sto.TimerCooldown, os.time() + DUNGEON_SYSTEM.CooldownTime)
							player:getPosition():sendMagicEffect(40)
							player:popupFYI(msg.ToFail)
							
							-- Remove All monsters
							local monsterPos = {}
							for x = dg[choiceId].FromPos.x, dg[choiceId].ToPos.x do
								for y = dg[choiceId].FromPos.y, dg[choiceId].ToPos.y do
									for z = dg[choiceId].FromPos.z, dg[choiceId].ToPos.z do
										local tile = Tile(x, y, z)
										local monster = tile:getTopCreature()
										if monster and monster:isMonster() then
											monster:remove()
										end
									end
								end
							end
							
						end, dg[choiceId].DungeonTime*1000)	
						
						for mx = 1, party do
						
							local ppt = partyMembers[mx]
							local fromPosPpt = ppt:getPosition()
						
							ppt:teleportTo(dg[choiceId].DungeonPos)
							ppt:getPosition():sendMagicEffect(40)
							
							addEvent(function()
								ppt:teleportTo(fromPosPpt)
								ppt:setStorageValue(sto.TimerCooldown, os.time() + DUNGEON_SYSTEM.CooldownTime)
								ppt:getPosition():sendMagicEffect(40)
								ppt:popupFYI(msg.ToFail)
							end, dg[choiceId].DungeonTime*1000)	
						
						end
						
					end
					
				end
				
			else
				
				if DUNGEON_SYSTEM.PzToEntry then
					if not getTileInfo(fromPosPlayer).protection then
						player:getPosition():sendMagicEffect(CONST_ME_POFF)
						return player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg.NeedPzSoloMsg)
					end
				end
				
				if player:getStorageValue(sto.TimerCooldown) - os.time() > 0 then
					player:getPosition():sendMagicEffect(CONST_ME_POFF)
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(msg.ToCooldown, string.format(player:getStorageValue(sto.TimerCooldown)-os.time())))
					return false
				end
				
				if dg[choiceId].SpawnMonsters then
					for m, l in pairs(dg[choiceId].Monsters) do
						Game.createMonster(m, l)
					end
				end
					
				-- To Dungeon
				player:teleportTo(dg[choiceId].DungeonPos)
				player:getPosition():sendMagicEffect(40)
				player:say(msg.ToEntry, TALKTYPE_MONSTER_SAY)
				player:setStorageValue(sto.TimerDungeon, os.time() + dg[choiceId].DungeonTime)
				
				-- Back Dungeon
				addEvent(function()
					player:teleportTo(fromPosPlayer)
					player:setStorageValue(sto.TimerCooldown, os.time() + DUNGEON_SYSTEM.CooldownTime)
					player:getPosition():sendMagicEffect(40)
					player:popupFYI(msg.ToFail)
					
					-- Remove All monsters
					local monsterPos = {}
					for x = dg[choiceId].FromPos.x, dg[choiceId].ToPos.x do
						for y = dg[choiceId].FromPos.y, dg[choiceId].ToPos.y do
							for z = dg[choiceId].FromPos.z, dg[choiceId].ToPos.z do
								local tile = Tile(x, y, z)
								local monster = tile:getTopCreature()
								if monster and monster:isMonster() then
									monster:remove()
								end
							end
						end
					end
					
				end, dg[choiceId].DungeonTime*1000)
				
			end
			
			
		elseif buttonId == 201 then
			
			player:registerEvent("DungeonSystemDetails_Modal")
			
			local needPartyMsg, needLevelMsg = "", ""
			
			if (dg[choiceId].NeedParty) then
				needPartyMsg = string.format("Party: %s players", dg[choiceId].AmountParty)
			else
				needPartyMsg = "Party: 1 players"
			end
			
			if (dg[choiceId].NeedLevel) then
				needLevelMsg = string.format("Level: %s+", dg[choiceId].Level)
			else
				needLevelMsg = "Don't need Level"
			end
			
			local currentTime = os.time()
			local endTime = dg[choiceId].DungeonTime + currentTime  -- Calculate the end time

			-- Check if the dungeon time has already passed
			if endTime < currentTime then
    			endTime = currentTime  -- Set it to the current time to avoid negative values
			end

			local timeDiff = endTime - currentTime

			-- Calculate hours, minutes, and seconds as before
			local hours = math.floor(timeDiff / 3600)
			local minutes = math.floor((timeDiff % 3600) / 60)
			local seconds = timeDiff % 60

			-- Format the time difference as a string
			local timeDiffStr = string.format("%02d:%02d:%02d", hours, minutes, seconds)


			local detailsModal = ModalWindow(modal.IDDetails, modal.TitleDetails, string.format(" Dungeon %s \n\n%s\n%s\nTime to make Dungeon: %s", dg[choiceId].Name, needPartyMsg, needLevelMsg, timeDiffStr))

			
			detailsModal:addButton(100, "Back")
			
			detailsModal:setDefaultEnterButton(100)
			detailsModal:setDefaultEscapeButton(100)
			
			detailsModal:sendToPlayer(player)
			
			-- player:popupFYI(string.format(">> Dungeon %s <<\n\n" .. needPartyMsg .. "\n" .. needLevelMsg .."\n\nTime to Dungeon: %s", dg[choiceId].Name, string.format(dg[choiceId].DungeonTime)))

		end
    
	end
	
end
]==]

-- ======================================================================== the tool
local root = os.tmpname()
os.remove(root)
local function dataDir(name, text)
	local dir = root .. "/" .. name .. "/data/creaturescripts/scripts"
	os.execute("mkdir -p '" .. dir .. "'")
	writeFile(dir .. "/dungeon_mod.lua", text)
	return root .. "/" .. name .. "/data", dir .. "/dungeon_mod.lua"
end
local lfData, lfPath = dataDir("lf", STOCK)
local crData, crPath = dataDir("crlf", (STOCK:gsub("\n", "\r\n")))
-- another shape: a window without the member timers (left alone)
local otherData, otherPath = dataDir("other", (STOCK:gsub("ppt:teleportTo%(fromPosPpt%)", "ppt:remove()")))
local function tool(data, extra)
	return sh("python3 -I tools/patch_base_dungeonentry.py '" .. data .. "'" .. (extra or "") .. "; echo status=$?")
end
local out = tool(lfData, " --dry-run")
ok(out:find("dungeon_mod.lua: patched %(dry run"), "dry run reports: " .. out)
eq(readFile(lfPath), STOCK, "dry run writes nothing")
out = tool(lfData)
ok(out:find("dungeon_mod.lua: patched") and out:find("status=0"), "patched: " .. out)
local PATCHED = readFile(lfPath)
local _, marks = PATCHED:gsub("patch_base_dungeonentry%.py", "")
eq(marks, 13, "the marked lines (3 helpers, storage, scan, wait, distance, 3 x 2 timer lines)")
ok(not PATCHED:find("\r", 1, true), "LF kept")
out = tool(lfData)
ok(out:find("dungeon_mod.lua: already patched"), "second run: already patched")
eq(readFile(lfPath), PATCHED, "second run changes nothing")
out = tool(crData)
ok(out:find("dungeon_mod.lua: patched"), "CRLF copy patched")
local cr = readFile(crPath)
eq(cr, (PATCHED:gsub("\n", "\r\n")), "CRLF copy: the same change, CRLF kept on every line")
tool(crData)
eq(readFile(crPath), cr, "CRLF: a second run changes nothing")
out = tool(otherData)
ok(out:find("dungeon_mod.lua: unrecognised %(timers x2%)"), "another shape listed: " .. out)
ok(readFile(otherPath) ~= nil and not readFile(otherPath):find("Chaos", 1, true), "another shape left alone")
os.execute("mkdir -p '" .. root .. "/empty/data'")
out = tool(root .. "/empty/data")
ok(out:find("nothing to do") and out:find("status=0"), "no script: nothing to do, status 0")
ok(load(PATCHED) ~= nil, "the patched script loads")

-- ======================================================================== mocked engine
local clockMs = 2000000000
os.mtime = function() return clockMs end
os.time = function() return math.floor(clockMs / 1000) end
local queue = {}
addEvent = function(fn, ms, ...)
	queue[#queue + 1] = {fn = fn, at = clockMs + (ms or 0), args = {...}, n = select("#", ...)}
	return #queue
end
stopEvent = function() end
local unpack = table.unpack or unpack
local function advance(ms)
	local limit = clockMs + ms
	while true do
		local best, bi
		for i, q in ipairs(queue) do
			if q.at <= limit and (not best or q.at < best.at) then
				best, bi = q, i
			end
		end
		if not best then
			break
		end
		table.remove(queue, bi)
		clockMs = math.max(clockMs, best.at)
		best.fn(unpack(best.args, 1, best.n))
	end
	clockMs = limit
end

local function P(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = P
local creatures -- array, the last one put on a tile is its top creature
local tileCalls = 0
local removedUse = 0
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
-- the real map has a tile at every position of every dungeon box and of the entry's square (counted from the map file)
function Tile(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	tileCalls = tileCalls + 1
	return {getTopCreature = function()
		for i = #creatures, 1, -1 do
			local q = creatures[i].pos
			if q.x == x and q.y == y and q.z == z then
				return creatures[i]
			end
		end
		return nil
	end}
end
local pz = function(pos) return pos.x < 200 end -- the town around the entry is a safe zone
function getTileInfo(pos)
	return {protection = pz(pos)}
end
local temple = P(150, 150, 7)
local players
local function newPlayer(guid, name, pos, level)
	local p = {guid = guid, id = guid + 1000, name = name, pos = pos, storage = {}, msgs = {}, lastLogout = 0,
		level = level or 700}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getPosition() return self.pos end
	function p:teleportTo(q) self.pos = P(q.x, q.y, q.z) end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t return true end
	function p:sendCancelMessage(t) self.msgs[#self.msgs + 1] = "cancel " .. t end
	function p:popupFYI(t) self.msgs[#self.msgs + 1] = "popup " .. t end
	function p:say(t) self.msgs[#self.msgs + 1] = "say " .. t end
	function p:registerEvent() end
	function p:unregisterEvent() end
	function p:getLevel() return self.level end
	-- the engine reads a nil storage key as 0
	function p:getStorageValue(k) return self.storage[k or 0] or -1 end
	function p:setStorageValue(k, v) self.storage[k or 0] = v end
	function p:isPzLocked() return false end
	function p:hasCondition() return false end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getTown() return {getTemplePosition = function() return temple end} end
	function p:getLastLogout() return self.lastLogout end
	function p:getGroup() return {getAccess = function() return false end, getId = function() return 1 end} end
	function p:getParty() return self.party end
	function p:sendExtendedOpcode() end
	players[#players + 1] = p
	creatures[#creatures + 1] = p
	return p
end
-- a logout: the object is gone; any later use of it is counted (the engine would read freed memory)
local function logoutPlayer(p)
	for i = #players, 1, -1 do
		if players[i] == p then table.remove(players, i) end
	end
	for i = #creatures, 1, -1 do
		if creatures[i] == p then table.remove(creatures, i) end
	end
	for k, v in pairs(p) do
		if type(v) == "function" then
			p[k] = function() removedUse = removedUse + 1 return P(0, 0, 0) end
		end
	end
end
local function newMonster(name, pos)
	local m = {name = name, pos = pos, id = #creatures + 5000}
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return nil end
	function m:getName() return self.name end
	function m:getId() return self.id end
	function m:getPosition() return self.pos end
	function m:remove()
		for i = #creatures, 1, -1 do
			if creatures[i] == self then table.remove(creatures, i) end
		end
	end
	creatures[#creatures + 1] = m
	return m
end
local function party(leader, members)
	local pt = {}
	function pt:getMembers() return members end
	function pt:getMemberCount() return #members end
	function pt:getLeader() return leader end
	leader.party = pt
	for _, m in ipairs(members) do m.party = pt end
end
Player = function(k)
	for _, p in ipairs(players) do
		if p.id == k or p.name == k then return p end
	end
end
Game = {
	getPlayers = function()
		local l = {}
		for _, p in ipairs(players) do l[#l + 1] = p end
		return l
	end,
	getSpectators = function(c, _, _, rx1, rx2, ry1, ry2)
		local l = {}
		for _, cr in ipairs(creatures) do
			local q = cr.pos
			if q.z == c.z and q.x >= c.x - rx1 and q.x <= c.x + rx2 and q.y >= c.y - ry1 and q.y <= c.y + ry2 then
				l[#l + 1] = cr
			end
		end
		return l
	end,
	createMonster = function() end,
}
ModalWindow = function()
	return setmetatable({}, {__index = function() return function() end end})
end

-- the base server's table (data/lib/core/dungeon.lua): its four dungeons with their real boxes
local function baseTable()
	return {
		Storages = {timerDungeon = 49356, timerCooldown = 50203, storageReward = 50205},
		Modal = {IDType = 2049, ID = 2050, IDDetails = 2051, Title = "Dungeon System", TitleDetails = "Details Dungeon"},
		Messages = {
			ToEntry = "Welcome to Dungeon",
			ToFail = "You were unable to complete the dungeon in the respective time.\n\nNext time you will do it better!",
			WaitFriendsCooldown = "Wait your party: %s",
			ToCooldown = "You're in cooldown to enter in a dungeon again. Cooldown: %s.",
			MsgNeedLevel = "You don't have level required. You need level %s.",
			MsgUniqueNeedParty = "You need party, to entry in dungeon",
			MsgNeedParty = "You need to be at a party to enter the dungeon. You need %s players",
			MsgLeaderParty = "You are not the leader of the Party.",
			MsgDistanceLeader = "Your team need to be close to you.",
			NeedPzSoloMsg = "You need to be in a safe area [PZ].",
			NeedPzMsg = "Your team needs to go a safe area [PZ].",
			PlayerInside = "A team is already inside.",
		},
		CooldownTime = 3600,
		PzToEntry = true,
		SQMsDistanceOfLeader = 20,
		Dungeons = {
			[1] = {Name = "Bones Dungeon", NeedParty = true, AmountParty = 2, NeedLevel = true, Level = 150,
				DungeonTime = 3600, DungeonPos = P(31662, 32143, 8), FromPos = {x = 31630, y = 32134, z = 8},
				ToPos = {x = 31851, y = 32300, z = 8}, SpawnMonsters = false, Monsters = {}},
			[2] = {Name = "Master of the Elements", NeedParty = true, AmountParty = 2, NeedLevel = true, Level = 200,
				DungeonTime = 3600, DungeonPos = P(31700, 32340, 8), FromPos = {x = 31633, y = 32322, z = 8},
				ToPos = {x = 31855, y = 32596, z = 8}, SpawnMonsters = false, Monsters = {}},
			[4] = {Name = "Rootkraken", NeedParty = false, AmountParty = 2, NeedLevel = true, Level = 600,
				DungeonTime = 1800, DungeonPos = P(31574, 31623, 8), FromPos = {x = 31564, y = 31614, z = 8},
				ToPos = {x = 31586, y = 31620, z = 8}, SpawnMonsters = false, Monsters = {}},
		},
	}
end

local function loadWindow(text)
	onModalWindow = nil
	assert(load(text, "=dungeon_mod"))()
	local fn = onModalWindow
	onModalWindow = nil
	return function(player, choice, button)
		return fn(player, 2050, button or 200, choice)
	end
end
local function reset()
	clockMs = 2000000000
	players, creatures, queue = {}, {}, {}
	tileCalls, removedUse = 0, 0
	DUNGEON_SYSTEM = baseTable()
end

-- ======================================================================== stock and patched, without the Chaos scripts
-- every scenario runs on the stock and on the patched script; the players' messages, places and storages must match
local scenarios = {
	{"a team inside", function()
		local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 100, 7))
		party(a, {b})
		newPlayer(9, "Inside", P(31700, 32200, 8))
		return a, 1
	end},
	{"level", function()
		local a = newPlayer(1, "Ash", P(100, 100, 7), 100)
		return a, 1
	end},
	{"no party", function() return newPlayer(1, "Ash", P(100, 100, 7)), 1 end},
	{"not the leader", function()
		local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 100, 7))
		party(b, {a})
		return a, 1
	end},
	{"party size", function()
		local a, b, c = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 100, 7)),
			newPlayer(3, "Cal", P(102, 100, 7))
		party(a, {b, c})
		return a, 1
	end},
	{"member not in a safe zone", function()
		local a, b = newPlayer(1, "Ash", P(190, 100, 7)), newPlayer(2, "Bry", P(205, 100, 7))
		party(a, {b})
		return a, 1
	end},
	{"cooldown", function()
		local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 100, 7))
		party(a, {b})
		b.storage[0] = os.time() + 500
		return a, 1
	end},
	{"member too far", function()
		local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(100, 125, 7))
		party(a, {b})
		return a, 1
	end},
	{"member under a monster", function()
		local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(110, 110, 7))
		party(a, {b})
		newMonster("rat", P(110, 110, 7))
		return a, 1
	end},
	{"a group goes in, time up", function()
		local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 101, 7))
		party(a, {b})
		newPlayer(3, "Cal", P(100, 100, 7)) -- on the leader's tile, on top (one position for two players)
		newMonster("skeleton", P(31700, 32200, 8))
		return a, 1
	end},
	{"solo dungeon", function()
		local a = newPlayer(1, "Ash", P(100, 100, 7))
		return a, 4
	end},
}
local function stateOf()
	local parts = {}
	for _, p in ipairs(players) do
		local st = {}
		for k, v in pairs(p.storage) do st[#st + 1] = k .. "=" .. v end
		table.sort(st)
		parts[#parts + 1] = string.format("%s@%d,%d,%d [%s] {%s}", p.name, p.pos.x, p.pos.y, p.pos.z,
			table.concat(p.msgs, " | "), table.concat(st, ","))
	end
	local mons = 0
	for _, c in ipairs(creatures) do
		if c:isMonster() then mons = mons + 1 end
	end
	return table.concat(parts, "\n") .. "\nmonsters " .. mons
end
local function run(text, sc)
	reset()
	local click = loadWindow(text)
	local who, choice = sc[2]()
	local t0 = os.clock()
	click(who, choice)
	local cost = os.clock() - t0
	local calls = tileCalls
	local first = stateOf()
	advance(3601 * 1000)
	return first .. "\n-- after the timer\n" .. stateOf(), calls, cost
end
local stockCalls, patchedCalls, stockCost, patchedCost = 0, 0, 0, 0
for _, sc in ipairs(scenarios) do
	local s, sCalls, sCost = run(STOCK, sc)
	local p, pCalls, pCost = run(PATCHED, sc)
	ok(s == p, "without the Chaos scripts, " .. sc[1] .. ": the same as stock\n--- stock\n" .. s .. "\n--- patched\n" .. p)
	stockCalls, patchedCalls = stockCalls + sCalls, patchedCalls + pCalls
	stockCost, patchedCost = stockCost + sCost, patchedCost + pCost
	if sc[1] == "a group goes in, time up" then
		ok(s:find("Ash@100,100,7", 1, true) and s:find("say Welcome to Dungeon", 1, true), "the group went in and came back")
		ok(s:find("monsters 0", 1, true), "the timer removed the monsters")
		-- the box of dungeon 1 (37,074 tiles) and the leader's square (41 x 41) per click
		eq(sCalls, 37074 + 1681, "stock: Tile() calls of a click")
		eq(pCalls, 2, "patched: a Tile() call only where a player stands near the leader (2 positions), none in the box")
	end
end
ok(stockCalls > 300000 and patchedCalls < 20, "Tile() calls in all scenarios: " .. stockCalls .. " / " .. patchedCalls)
print(string.format("base_dungeonentry_patch_test: clicks on this mock: stock %d Tile() calls, %.1f ms; patched %d, %.1f ms",
	stockCalls, stockCost * 1000, patchedCalls, patchedCost * 1000))

-- the stock timer keeps the Player object: a member who logged out is still used an hour later
reset()
do
	local click = loadWindow(STOCK)
	local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 101, 7))
	party(a, {b})
	click(a, 1)
	logoutPlayer(b)
	advance(3601 * 1000)
	ok(removedUse > 0, "stock: the timer uses the object of a player who logged out (" .. removedUse .. " calls)")
end

-- ======================================================================== with the Chaos scripts
reset()
db = {query = function() return true end, storeQuery = function() return nil end, asyncQuery = function() end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {free = function() end}
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function(self) events[(rawget(self, "name") or kind) .. ":" .. kind] = self end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"),
	eventMock("talk"), eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
ItemType = function(id) return {getId = function() return id end, getClientId = function() return id end} end
MonsterType = function() return nil end
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(p, opcode, action, data) sent[#sent + 1] = {p = p, action = action, data = data} return true end
Chaos.decode = function(b) return b end
Chaos.select = function() return {} end
Chaos.isMultiClient = function() return false end
dofile("data/scripts/chaos/instance_limits.lua")
dofile("data/scripts/chaos/dungeons.lua")
local IL = ChaosInstanceLimits
local login, logout = events["ChaosDungeonsLogin:creature"], events["ChaosDungeonsLogout:creature"]
local ext = events["ChaosDungeonsExtended:creature"]
local function said(p, text)
	for _, t in ipairs(p.msgs) do
		if t:find(text, 1, true) then return true end
	end
	return false
end
local function runsOf()
	local list = {}
	for _, r in ipairs(IL.runs()) do
		if r.key == "dungeon" then list[#list + 1] = r end
	end
	return list
end
-- no queued event may hold a Player object (in its arguments or its upvalues)
local function holdsPlayer()
	local isPlayer = {}
	for _, p in ipairs(players) do isPlayer[p] = true end
	for _, q in ipairs(queue) do
		for i = 1, q.n do
			if isPlayer[q.args[i]] then return true end
		end
		local i = 1
		while true do
			local name, v = debug.getupvalue(q.fn, i)
			if not name then break end
			if isPlayer[v] then return true end
			i = i + 1
		end
	end
	return false
end

do
	local click = loadWindow(PATCHED)
	local a, b = newPlayer(1, "Ash", P(100, 100, 7)), newPlayer(2, "Bry", P(101, 101, 7))
	party(a, {b})
	local c, d = newPlayer(3, "Cal", P(110, 100, 7)), newPlayer(4, "Dov", P(111, 100, 7))
	party(c, {d})
	local mon = newMonster("skeleton", P(31700, 32200, 8))
	local start = os.time()
	tileCalls = 0
	click(a, 1)
	eq(tileCalls, 4, "chaos: a click looks only at the 4 tiles near the leader that hold a player")
	eq(a.pos.x, 31662, "chaos: the leader is in")
	eq(b.pos.x, 31662, "chaos: the member is in")
	ok(said(a, "say Welcome to Dungeon"), "chaos: the window's welcome")
	local r = runsOf()
	ok(#r == 1 and r[1].players == 2 and r[1].left == 2700 and r[1].what == "Bones Dungeon, entry window",
		"chaos: one run of two in /instances, 45 minutes left: " .. tostring(r[1] and r[1].what))
	ok(not holdsPlayer(), "chaos: no queued event holds a Player object")
	-- a second group: refused with the wait
	click(c, 1)
	ok(said(c, "A team is already inside. It frees up in ~45 min at the latest."), "chaos: the second group hears the wait: "
		.. table.concat(c.msgs, " | "))
	eq(c.pos.x, 110, "chaos: the second group stays out")
	-- the queue window shows the same wait
	sent = {}
	ext.onExtendedOpcode(c, ChaosOpcodes.dungeons, {action = "fetch"})
	local wait
	for _, s in ipairs(sent) do
		if s.action == "dungeon" and s.data.id == 1 then wait = s.data.queue.estimated end
	end
	ok(wait and wait >= 2690 * 1000, "chaos: the queue shows the wait of the window's run: " .. tostring(wait))
	-- Bry walks out after 10 minutes: released, the window's cooldown end (entry + 60 + 60 minutes), never pulled back
	advance(600 * 1000)
	b:teleportTo(P(101, 101, 7))
	advance(3000)
	eq(runsOf()[1] and runsOf()[1].players, 1, "chaos: Bry left the run")
	eq(b.storage[50203], start + 7200, "chaos: Bry's cooldown ends where the window's did (entry + DungeonTime + 1 h)")
	-- the warnings
	advance((2700 - 600 - 300) * 1000)
	ok(said(a, "Bones Dungeon: 5 minutes left"), "chaos: the 5 minute warning: " .. table.concat(a.msgs, " | "))
	advance(240 * 1000)
	ok(said(a, "Bones Dungeon: 1 minute left"), "chaos: the 1 minute warning")
	advance(61 * 1000)
	eq(a.pos.x, 100, "chaos: time up after 45 minutes: back at the entry")
	ok(said(a, "popup You were unable to complete the dungeon in the respective time."), "chaos: the window's text")
	eq(a.storage[50203], start + 7200, "chaos: the leader's cooldown: the window's end, in the queue's storage")
	eq(a.storage[0], nil, "chaos: storage 0 no longer used")
	ok(mon.pos and not (function() for _, cr in ipairs(creatures) do if cr == mon then return true end end end)(),
		"chaos: the monsters of the box removed")
	eq(b.pos.x, 101, "chaos: Bry (out before) not pulled back")
	eq(#runsOf(), 0, "chaos: the run is over")
	-- the window's own cooldown check reads the queue's storage now
	a.msgs = {}
	click(a, 1)
	ok(said(a, "You're in cooldown to enter in a dungeon again."), "chaos: the window sees the cooldown")
	-- the queue sees it too
	ext.onExtendedOpcode(a, ChaosOpcodes.dungeons, {action = "queue", data = {id = 4, difficulty = 1}})
	ok(said(a, "cancel You are in cooldown for dungeons."), "chaos: the queue sees the window's cooldown")

	-- the second group goes in; Dov logs out inside: out of the run, his object never used again
	c.msgs = {}
	click(c, 1)
	eq(c.pos.x, 31662, "chaos: the next group goes in")
	ok(not holdsPlayer(), "chaos: no queued event holds a Player object (second run)")
	logout.onLogout(d)
	logoutPlayer(d)
	removedUse = 0
	advance(3000)
	eq(runsOf()[1] and runsOf()[1].players, 1, "chaos: Dov's logout left the run")
	-- a staff close: the failure rule
	ok(Chaos.instances.dungeon.close(runsOf()[1].id), "chaos: staff close")
	eq(c.pos.x, 110, "chaos: out where Cal entered")
	advance(3600 * 1000)
	eq(removedUse, 0, "chaos: nothing used Dov's object after his logout")
	-- Dov logs in again inside the box while the server runs: the temple and the cooldown
	d = newPlayer(4, "Dov", P(31662, 32143, 8))
	d.lastLogout = os.time() - 10
	login.onLogin(d)
	eq(d.pos.x, temple.x, "chaos: a relog inside goes to the temple")
	ok(said(d, "You logged out inside the dungeon: your run is over."), "chaos: told why")

	-- a solo dungeon (Rootkraken: 30 minutes)
	local e = newPlayer(5, "Eli", P(120, 100, 7))
	local s0 = os.time()
	click(e, 4)
	eq(e.pos.x, 31574, "chaos: solo dungeon: in")
	eq(e.storage[49356], s0 + 1800, "chaos: the window's own dungeon timer storage, now under its real key")
	r = runsOf()
	ok(#r == 1 and r[1].left == 1800, "chaos: the solo run, 30 minutes (under the cap)")
	advance(1801 * 1000)
	eq(e.pos.x, 120, "chaos: solo time up: back")
	eq(e.storage[50203], s0 + 1800 + 3600, "chaos: solo cooldown as the window's")
end

os.execute("rm -rf '" .. root .. "'")
if fails > 0 then
	print(string.format("base_dungeonentry_patch_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("base_dungeonentry_patch_test: all %d checks passed", checks))

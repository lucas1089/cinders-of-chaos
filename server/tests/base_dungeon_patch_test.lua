-- Run from the server/ folder: luajit tests/base_dungeon_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_dungeon.py on a copy of the stock dungeon entry (the step-in script and its modal answer, written
-- here with made-up dungeons), then the stock and the patched scripts on the same mocked engine:
--   without the Chaos scripts   stock and patched send the same modal window (title, buttons, choices) and the answer
--                               runs as before (its box scan, its teleport, its exit timer)
--   with dungeons.lua loaded    the patched tile sends the dungeon list and "open" (the window), no modal window, no
--                               modal event, not one tile looked at; the queue then runs the dungeon; a monster on the
--                               tile does nothing; a second step within a second only opens the window (rate limit)
-- and: dry run, a second run changes nothing, CRLF kept, a step-in of another shape and a script not registered as a
-- StepIn movevent are left alone, a data folder without the script: nothing to do.
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
	print("base_dungeon_patch_test: python3 not found, skipped")
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
os.execute("mkdir -p '" .. data .. "/movements/scripts/quests' '" .. data .. "/creaturescripts/scripts'")

-- the stock code (as the base server has it)
local STEPIN = [[


function onStepIn(player, item, fromPosition, itemEx, toPosition, isHotkey)

	player:registerEvent("DungeonSystem_Modal")

	local window = ModalWindow(DUNGEON_SYSTEM.Modal.ID, DUNGEON_SYSTEM.Modal.Title, DUNGEON_SYSTEM.Modal.Msg)

	window:addButton(200, "Confirm")
	window:addButton(201, "Details")
	window:addButton(202, "Exit")

	for k,v in pairs(DUNGEON_SYSTEM.Dungeons) do
		window:addChoice(k, v.Name)
	end

	window:setDefaultEnterButton(200)
    window:setDefaultEscapeButton(202)

	window:sendToPlayer(player)

	return true
end
]]

-- the modal answer, its solo path (the party path scans and times the same way)
local ANSWER = [[
function onModalWindow(player, modalWindowId, buttonId, choiceId)
	player:unregisterEvent("DungeonSystem_Modal")
	local dg = DUNGEON_SYSTEM.Dungeons
	local msg = DUNGEON_SYSTEM.Messages
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
				return player:sendTextMessage(MESSAGE_STATUS_SMALL, msg.PlayerInside)
			end
			local fromPosPlayer = player:getPosition()
			player:teleportTo(dg[choiceId].DungeonPos)
			addEvent(function()
				player:teleportTo(fromPosPlayer)
				player:popupFYI(msg.ToFail)
			end, dg[choiceId].DungeonTime*1000)
		end
	end
end
]]

-- another step-in that names the modal window but has two handlers: left alone
local OTHER = "function onStepIn(creature)\n\treturn ModalWindow(DUNGEON_SYSTEM.Modal.ID) end\n" ..
	"function onStepIn(creature)\n\treturn true end\n"
local XML = [[
<?xml version="1.0" encoding="UTF-8"?>
<movements>
	<movevent event="StepIn" itemid="1945" script="quests/other.lua"/>
	<!-- <movevent event="StepIn" itemid="1946" script="old.lua"/> -->
	<movevent event="StepIn" itemid ="26702" script="dungeon.lua"/>
	<movevent event="StepOut" itemid="1947" script="stepout.lua"/>
</movements>
]]
local stepPath = data .. "/movements/scripts/dungeon.lua"
local otherPath = data .. "/movements/scripts/quests/other.lua"
local oldPath = data .. "/movements/scripts/old.lua"
local outPath = data .. "/movements/scripts/stepout.lua"
writeFile(data .. "/movements/movements.xml", XML)
writeFile(stepPath, STEPIN)
writeFile(otherPath, OTHER)
writeFile(oldPath, STEPIN)
writeFile(outPath, STEPIN)

local tool = "python3 -I tools/patch_base_dungeon.py '" .. data .. "'"
local out = sh(tool .. " --dry-run")
ok(out:find("data/movements/scripts/dungeon.lua: patched (dry run, not written)", 1, true), "dry run reports: " .. out)
ok(readFile(stepPath) == STEPIN, "dry run writes nothing")
out = sh(tool)
ok(out:find("data/movements/scripts/dungeon.lua: patched\n", 1, true), "patched: " .. out)
ok(out:find("quests/other.lua: unrecognised (onStepIn x2)", 1, true), "another shape: listed and left alone")
ok(not out:find("old.lua", 1, true) and not out:find("stepout.lua", 1, true),
	"a commented-out movevent and a StepOut script are not touched")
local patched = readFile(stepPath)
ok(patched:find("function onStepIn(player, item, fromPosition, itemEx, toPosition, isHotkey)\n\tif ChaosDungeonsOpen " ..
	"and ChaosDungeonsOpen(player) then return true end -- Chaos (patch_base_dungeon.py)\n", 1, true) ~= nil,
	"the line is the first of onStepIn")
eq(#patched - #STEPIN, #"\tif ChaosDungeonsOpen and ChaosDungeonsOpen(player) then return true end -- Chaos (patch_base_dungeon.py)\n",
	"one line added, the rest untouched")
ok(readFile(otherPath) == OTHER and readFile(oldPath) == STEPIN and readFile(outPath) == STEPIN, "the others unchanged")
out = sh(tool)
ok(out:find("dungeon.lua: already patched", 1, true), "second run: already patched")
eq(readFile(stepPath), patched, "second run changes nothing")
-- CRLF
writeFile(stepPath, (STEPIN:gsub("\n", "\r\n")))
sh(tool)
local crlf = readFile(stepPath)
ok(crlf:find("isHotkey)\r\n\tif ChaosDungeonsOpen and ChaosDungeonsOpen(player) then return true end -- " ..
	"Chaos (patch_base_dungeon.py)\r\n", 1, true) ~= nil and not crlf:gsub("\r\n", ""):find("\n"), "CRLF kept")
writeFile(stepPath, patched)
local empty = root .. "/empty"
os.execute("mkdir -p '" .. empty .. "'")
out = sh("python3 -I tools/patch_base_dungeon.py '" .. empty .. "'; echo status=$?")
ok(out:find("nothing to do", 1, true) and out:find("status=0", 1, true), "no base scripts: nothing to do, status 0")

-- ------------------------------------------------------------------ mocked engine
local clockMs = 2000000000
os.mtime = function() return clockMs end
os.time = function() return math.floor(clockMs / 1000) end -- luacheck: ignore
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
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function(self) events[(rawget(self, "name") or kind) .. ":" .. kind] = self end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
db = {query = function() return true end, storeQuery = function() return nil end, asyncQuery = function() end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end}
result = {free = function() end}
ItemType = function(id) return {getId = function() return id end, getClientId = function() return id end} end
MonsterType = function() return nil end

local log
local tileLookups = 0
function Tile()
	tileLookups = tileLookups + 1
	return {getTopCreature = function() return nil end}
end
local windows
function ModalWindow(id, title, text)
	local w = {id = id, title = title, text = text, buttons = {}, choices = {}}
	function w:addButton(b, t) self.buttons[#self.buttons + 1] = b .. "=" .. t end
	function w:addChoice(c, t) self.choices[#self.choices + 1] = c .. "=" .. t end
	function w:setDefaultEnterButton(b) self.enter = b end
	function w:setDefaultEscapeButton(b) self.escape = b end
	function w:sendToPlayer(p) windows[#windows + 1] = self; log[#log + 1] = "modal " .. p:getName() end
	return w
end

local players = {}
local temple = P(1, 1, 7)
local function newPlayer(guid, name, pos)
	local p = {guid = guid, id = guid + 1000, name = name, pos = pos, storage = {}, msgs = {}, cancels = {}, lastLogout = 0}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getPosition() return self.pos end
	function p:teleportTo(q) self.pos = P(q.x, q.y, q.z) end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:popupFYI(t) self.msgs[#self.msgs + 1] = t end
	function p:say() end
	function p:registerEvent(e) log[#log + 1] = "register " .. e end
	function p:unregisterEvent(e) log[#log + 1] = "unregister " .. e end
	function p:getLevel() return 500 end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:isPzLocked() return false end
	function p:hasCondition() return false end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getTown() return {getTemplePosition = function() return temple end} end
	function p:getLastLogout() return self.lastLogout end
	function p:getGroup() return {getAccess = function() return false end, getId = function() return 1 end} end
	function p:getVocation() return {getId = function() return 4 end} end
	function p:sendExtendedOpcode() end
	players[guid] = p
	return p
end
Player = function(k)
	for _, p in pairs(players) do
		if p.name == k or p.id == k then
			return p
		end
	end
	return nil
end
Game = {getPlayers = function()
	local l = {}
	for _, p in pairs(players) do l[#l + 1] = p end
	return l
end, getSpectators = function(c, _, _, rx1, rx2, ry1, ry2)
	local l = {}
	for _, p in pairs(players) do
		local q = p.pos
		if q.z == c.z and q.x >= c.x - rx1 and q.x <= c.x + rx2 and q.y >= c.y - ry1 and q.y <= c.y + ry2 then
			l[#l + 1] = p
		end
	end
	return l
end}

-- made-up dungeons in the base table's shape
DUNGEON_SYSTEM = {
	Storages = {timerDungeon = 49356, timerCooldown = 50203},
	Modal = {ID = 2050, Title = "Dungeon System", Msg = "Select your Dungeon:"},
	Messages = {ToFail = "Out of time.", PlayerInside = "A team is already inside."},
	CooldownTime = 3600,
	Dungeons = {
		[1] = {Name = "Gloomroot Hollow", NeedParty = false, NeedLevel = false, DungeonTime = 3600,
			DungeonPos = Position(510, 510, 7), FromPos = {x = 500, y = 500, z = 7}, ToPos = {x = 529, y = 539, z = 7}},
		[2] = {Name = "Saltglass Vault", NeedParty = false, NeedLevel = false, DungeonTime = 1800,
			DungeonPos = Position(610, 610, 7), FromPos = {x = 600, y = 600, z = 7}, ToPos = {x = 620, y = 620, z = 7}},
	},
}

-- one step on the tile and, when a modal window came, its Confirm for the first dungeon
local function stepOn(stepText, who)
	log, windows = {}, {}
	tileLookups = 0
	assert(load(stepText))()
	local stepIn = onStepIn
	stepIn(who, {}, who:getPosition(), nil, who:getPosition(), false)
	local registered = false
	for _, l in ipairs(log) do
		if l == "register DungeonSystem_Modal" then registered = true end
	end
	if windows[1] and registered then
		assert(load(ANSWER))()
		onModalWindow(who, windows[1].id, 200, 1)
	end
	return windows[1]
end
local function same(a, b)
	return a and b and a.id == b.id and a.title == b.title and a.text == b.text and a.enter == b.enter
		and a.escape == b.escape and table.concat(a.buttons, ",") == table.concat(b.buttons, ",")
		and table.concat(a.choices, ",") == table.concat(b.choices, ",")
end

-- 1. without the Chaos scripts: the tile works as before
do
	local a = newPlayer(1, "Ansel", P(100, 100, 7))
	local stock = stepOn(STEPIN, a)
	local stockLog, stockTiles = table.concat(log, "\n"), tileLookups
	eq(a.pos.x, 510, "stock: the modal answer teleports the player in")
	eq(stockTiles, 30 * 40, "stock: the answer looks at every tile of the box")
	advance(3600 * 1000)
	eq(a.pos.x, 100, "stock: the exit timer brings the player back")
	local patchedWindow = stepOn(patched, a)
	ok(same(stock, patchedWindow), "patched without Chaos: the same modal window")
	eq(table.concat(log, "\n"), stockLog, "patched without Chaos: the same events, teleport and messages")
	eq(tileLookups, stockTiles, "patched without Chaos: the same answer")
	local choices = table.concat(stock.choices, ",")
	ok(#stock.choices == 2 and choices:find("1=Gloomroot Hollow", 1, true) and choices:find("2=Saltglass Vault", 1, true),
		"the choices are the dungeons: " .. choices)
	advance(3600 * 1000)
	players[1] = nil
end

-- 2. with dungeons.lua loaded
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(p, opcode, action, data)
	sent[#sent + 1] = {p = p, opcode = opcode, action = action, data = data}
	return true
end
Chaos.decode = function(b) return b end
Chaos.select = function() return {} end
Chaos.isMultiClient = function() return false end
dofile("data/scripts/chaos/instance_limits.lua")
dofile("data/scripts/chaos/dungeons.lua")
ok(type(ChaosDungeonsOpen) == "function", "dungeons.lua: ChaosDungeonsOpen")
local function actions(p)
	local l = {}
	for _, s in ipairs(sent) do
		if s.p == p then l[#l + 1] = s.action end
	end
	return table.concat(l, ",")
end
do
	local b = newPlayer(2, "Brisa", P(100, 100, 7))
	events["ChaosDungeonsLogin:creature"].onLogin(b)
	sent = {}
	local stock = stepOn(STEPIN, b)
	ok(stock ~= nil and actions(b) == "", "stock with Chaos: still the modal window (what the patch fixes)")
	advance(3600 * 1000)
	b.pos = P(100, 100, 7)
	sent = {}
	local w = stepOn(patched, b)
	ok(w == nil, "patched: no modal window")
	eq(table.concat(log, ","), "", "patched: no modal event registered, nothing else done")
	eq(tileLookups, 0, "patched: not one tile looked at")
	eq(actions(b), "dungeon,dungeon,list,open", "patched: the window's data, then open")
	for _, s in ipairs(sent) do
		eq(s.opcode, ChaosOpcodes.dungeons, "patched: the dungeon opcode")
	end
	eq(b.pos.x, 100, "patched: the player stays on the tile")
	-- the window's queue runs the dungeon (capped at 45 minutes)
	events["ChaosDungeonsExtended:creature"].onExtendedOpcode(b, ChaosOpcodes.dungeons,
		{action = "queue", data = {id = 1, difficulty = 1}})
	eq(b.pos.x, 510, "the queue runs the dungeon")
	local start
	for _, s in ipairs(sent) do
		if s.action == "start" then start = s.data end
	end
	eq(start and start.duration, Chaos.dungeons.maxTimeSeconds * 1000, "the queue's time cap")
	-- a monster on the tile: nothing
	sent = {}
	local rat = {isPlayer = function() return false end, getName = function() return "Rat" end,
		getPosition = function() return P(100, 100, 7) end}
	ok(stepOn(patched, rat) == nil and #sent == 0 and #log == 0, "a monster on the tile: nothing")
	-- the rate limit of the window's fetch: a second step within a second only opens the window
	local c = newPlayer(3, "Corin", P(100, 100, 7))
	local allowed = {}
	ChaosRateLimit = {allow = function(p, key, ms)
		local k = p:getGuid() .. key
		if allowed[k] and clockMs - allowed[k] < ms then
			return false
		end
		allowed[k] = clockMs
		return true
	end}
	sent = {}
	stepOn(patched, c)
	stepOn(patched, c)
	eq(actions(c), "dungeon,dungeon,list,open,open", "a second step within a second: only open")
	advance(1000)
	sent = {}
	stepOn(patched, c)
	eq(actions(c), "dungeon,dungeon,list,open", "a second later: the list again")
	ChaosRateLimit = nil
end

os.execute("rm -rf '" .. root .. "'")
if fails > 0 then
	print(string.format("base_dungeon_patch_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("base_dungeon_patch_test: all %d checks passed", checks))

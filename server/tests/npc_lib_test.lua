-- Run from the server/ folder: luajit tests/npc_lib_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The base NPC library patch (tools/patch_base_npcs.py) on condensed copies of the stock files (the lines the patch
-- matches are verbatim), then the patched functions with a mock engine: replies as lists of lines (Yberius "twist of
-- fate"), nodes without text, the blessing cost tags, delayed lines for a player who logged out. Also the NPC
-- spellName rewrite of tools/rename_spells.py (a new name with an apostrophe must stay valid Lua).
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local load = loadstring or load

-- ---------------------------------------------------------------- condensed stock files
local STOCK_HANDLER = [[
NpcHandler = {}
NpcHandler.__index = NpcHandler
TAG_PLAYERNAME = "|PLAYERNAME|"

	-- Translates all message tags found in msg using parseInfo
	function NpcHandler:parseMessage(msg, parseInfo)
		local ret = msg
		for search, replace in pairs(parseInfo) do
			ret = string.gsub(ret, search, replace)
		end
		return ret
	end

	--    shallDelay is a boolean value. If it is false, the message is not delayed. Default value is true.
	function NpcHandler:say(message, focus, publicize, shallDelay, delay)
		if type(message) == "table" then
			return self:doNPCTalkALot(message, delay or 6000, focus)
		end
		said[#said + 1] = message
	end
]]

local STOCK_MODULES = [[
StdModule = {}

	-- Usage:
		-- keywordHandler:addKeyword({"offer"}, StdModule.say, {npcHandler = npcHandler, text = "I sell many powerful melee weapons."})
	function StdModule.say(cid, message, keywords, parameters, node)
		local npcHandler = parameters.npcHandler
		if npcHandler == nil then
			error("StdModule.say called without any npcHandler instance.")
		end
		local onlyFocus = (parameters.onlyFocus == nil or parameters.onlyFocus == true)
		if not npcHandler:isFocused(cid) and onlyFocus then
			return false
		end

		local parseInfo = {[TAG_PLAYERNAME] = Player(cid):getName()}
		npcHandler:say(npcHandler:parseMessage(parameters.text or parameters.message, parseInfo), cid, parameters.publicize and true)
		if parameters.reset then
			npcHandler:resetNpc(cid)
		end
		return true
	end

	function StdModule.bless(cid, message, keywords, parameters, node)
		local npcHandler = parameters.npcHandler
		if npcHandler == nil then
			error("StdModule.bless called without any npcHandler instance.")
		end

		local player = Player(cid)
		if player:isPremium() or not parameters.premium then
			if player:hasBlessing(parameters.bless) then
				npcHandler:say("Gods have already blessed you with this blessing!", cid)
			elseif not player:removeTotalMoney(parameters.cost) then
				npcHandler:say("You don't have enough money for blessing.", cid)
			else
				player:addBlessing(parameters.bless)
				npcHandler:say("You have been blessed by one of the five gods!", cid)
			end
		end
		npcHandler:resetNpc(cid)
		return true
	end

	function StdModule.travel(cid, message, keywords, parameters, node)
		return true
	end
]]

local STOCK_NPC = [[
local func = function(cid, text, type, e, pcid)
	if Player(pcid):isPlayer() then
		local creature = Creature(cid)
		creature:say(text, type, false, pcid, creature:getPosition())
		e.done = true
	end
end

function doCreatureSayWithDelay(cid, text, type, delay, e, pcid)
	if Player(pcid):isPlayer() then
		e.done = false
		e.event = addEvent(func, delay < 1 and 1000 or delay, cid, text, type, e, pcid)
	end
end
]]

-- ---------------------------------------------------------------- mock engine
said, events, players, creatures = {}, {}, {}, {}
function addEvent(fn, delay, ...)
	events[#events + 1] = {fn = fn, args = {...}, delay = delay}
	return #events
end
local function runEvents()
	local list = events
	events = {}
	for _, e in ipairs(list) do
		e.fn((table.unpack or unpack)(e.args))
	end
end
function Player(cid) return players[cid] end
function Creature(cid) return creatures[cid] end
function getFormattedWorldTime() return "14:05" end

local function makePlayer(cid, level, money)
	local p = {cid = cid, level = level, money = money, blessings = {}}
	function p:getName() return "Tester%1" end -- a "%" in the replacement must stay plain text
	function p:getLevel() return self.level end
	function p:isPlayer() return true end
	function p:isPremium() return true end
	function p:hasBlessing(b) return self.blessings[b] == true end
	function p:addBlessing(b) self.blessings[b] = true end
	function p:removeTotalMoney(amount) -- data/lib/core/player.lua compares the amount with numbers
		if amount <= self.money then
			self.money = self.money - amount
			return true
		end
		return false
	end
	players[cid] = p
	return p
end
local npcLines = {}
local npc = {}
function npc:say(text, type, ghost, target) npcLines[#npcLines + 1] = {text = text, target = target} end
function npc:getPosition() return {x = 1, y = 1, z = 7} end
creatures[9] = npc

-- ---------------------------------------------------------------- the patch tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
local function runPython(fn, text)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_npcs as p; "
		.. "t = open(sys.argv[1]).read(); n, s = p." .. fn .. "(t); "
		.. "open(sys.argv[1], 'w').write(n); print(s)\" " .. path
	local h = assert(io.popen(cmd))
	local status = (h:read("*a") or ""):gsub("%s+$", "")
	h:close()
	f = assert(io.open(path, "rb"))
	local out = f:read("*a")
	f:close()
	os.remove(path)
	return out, status
end

if not hasPython then
	print("npc_lib_test: python3 not found, patch checks skipped")
else
	-- the stock library: the table reply fails like on the server (npchandler.lua:311)
	assert(load(STOCK_HANDLER))()
	local h = setmetatable({}, NpcHandler)
	local okStock, err = pcall(h.parseMessage, h, {"a", "b"}, {[TAG_PLAYERNAME] = "x"})
	ok(not okStock and tostring(err):find("table") ~= nil, "stock: gsub on a table fails (" .. tostring(err) .. ")")

	local patched = {}
	for _, t in ipairs({{"patch_npchandler", STOCK_HANDLER, "handler"}, {"patch_modules", STOCK_MODULES, "modules"},
			{"patch_npc_lib", STOCK_NPC, "npc"}}) do
		local text, status = runPython(t[1], t[2])
		eq(status, "patched", t[3] .. ": patch applies to the stock lines")
		local again, status2 = runPython(t[1], text)
		eq(status2, "already", t[3] .. ": second run")
		eq(again, text, t[3] .. ": second run changes nothing")
		local _, status3 = runPython(t[1], "local x = 1\n")
		ok(status3:find("unexpected", 1, true) ~= nil, t[3] .. ": unknown file reported: " .. status3)
		patched[t[3]] = text
	end

	-- ------------------------------------------------------------ the patched library
	assert(load(patched.handler))()
	assert(load(patched.modules))()
	assert(load(patched.npc))()
	local talked
	function NpcHandler:doNPCTalkALot(msgs, interval, cid)
		talked = {msgs = msgs, interval = interval, cid = cid}
		for i, line in ipairs(msgs) do
			doCreatureSayWithDelay(9, line, 1, (i - 1) * interval + 700, {}, cid)
		end
	end
	function NpcHandler:isFocused() return true end
	function NpcHandler:resetNpc() end
	local handler = setmetatable({}, NpcHandler)
	local player = makePlayer(100, 150, 100000)

	-- Yberius "twist of fate": four lines, the cost tag filled for level 150 ((150 - 20) * 200)
	local twist = {npcHandler = handler, text = {
		"This is a special blessing ... |PLAYERNAME|?",
		"It only works when you're killed by other adventurers. ...",
		"Would you like to receive that protection for a sacrifice of |PVPBLESSCOST| gold, child?"}}
	local okSay, sayErr = pcall(StdModule.say, 100, "twist of fate", {"twist of fate"}, twist)
	ok(okSay, "a table reply no longer fails: " .. tostring(sayErr))
	eq(talked and #talked.msgs, 3, "said line by line")
	eq(talked and talked.msgs[1], "This is a special blessing ... Tester%1?", "player name filled, % kept")
	eq(talked and talked.msgs[3], "Would you like to receive that protection for a sacrifice of 26000 gold, child?",
		"twist of fate cost for level 150")
	eq(#twist.text, 3, "the script's own table is not changed")
	eq(twist.text[3]:find("|PVPBLESSCOST|", 1, true) ~= nil, true, "the tag stays in the script's table")
	runEvents()
	eq(#npcLines, 3, "three delayed lines")
	eq(npcLines[3] and npcLines[3].target, 100, "said to the player")

	-- the player logs out during a long reply: the remaining lines are dropped, no error
	npcLines = {}
	StdModule.say(100, "twist of fate", {"twist of fate"}, twist)
	players[100] = nil
	local okEvents, evErr = pcall(runEvents)
	ok(okEvents, "logged out during the reply: " .. tostring(evErr))
	eq(#npcLines, 0, "nothing said to a player who left")
	local okDelay, delayErr = pcall(doCreatureSayWithDelay, 9, "x", 1, 0, {}, 100)
	ok(okDelay, "doCreatureSayWithDelay for a player who left: " .. tostring(delayErr))
	players[100] = player

	-- a node without text (Seymour "dead rat": the action says the line): no error, nothing said
	said = {}
	local okNil, nilErr = pcall(StdModule.say, 100, "5 dead rats", {}, {npcHandler = handler})
	ok(okNil, "a node without text: " .. tostring(nilErr))
	eq(#said, 0, "nothing said for it")

	-- strings as before, with the other tags
	said = {}
	StdModule.say(100, "time", {"time"}, {npcHandler = handler, text = "It is |TIME|, |PLAYERNAME|."})
	eq(said[1], "It is 14:05, Tester%1.", "|TIME| and the name")
	said = {}
	StdModule.say(100, "spiritual", {}, {npcHandler = handler, text = "Sacrifice |BLESSCOST| gold."})
	eq(said[1], "Sacrifice 20000 gold.", "blessing cost capped at level 120")

	-- the costs
	eq(StdModule.chaosBlessCost(8, false), 2000, "blessing, level 8")
	eq(StdModule.chaosBlessCost(50, false), 6000, "blessing, level 50")
	eq(StdModule.chaosBlessCost(300, false), 20000, "blessing, level 300")
	eq(StdModule.chaosBlessCost(50, true), 6000, "twist of fate, level 50")
	eq(StdModule.chaosBlessCost(1000, true), 50000, "twist of fate, level 1000")
	eq(StdModule.chaosCost(player, 10000), 10000, "a number cost stays")

	-- "yes": StdModule.bless with the cost tag charges the level's cost (stock: compare string with number)
	said = {}
	local okBless, blessErr = pcall(StdModule.bless, 100, "yes", {"yes"},
		{npcHandler = handler, cost = "|PVPBLESSCOST|", bless = 6})
	ok(okBless, "bless with a cost tag: " .. tostring(blessErr))
	eq(player.money, 100000 - 26000, "26000 gold taken")
	eq(player.blessings[6], true, "twist of fate given")
	local poor = makePlayer(101, 150, 100)
	StdModule.bless(101, "yes", {"yes"}, {npcHandler = handler, cost = "|BLESSCOST|", bless = 1})
	eq(poor.blessings[1], nil, "not enough money: no blessing")
	eq(said[#said], "You don't have enough money for blessing.", "not enough money: said so")

	-- ------------------------------------------------------------ rename_spells.py: NPC spellName with an apostrophe
	local SCRIPT = "keywordHandler:addSpellKeyword({'intense', 'wound', 'cleansing'}, {npcHandler = npcHandler, "
		.. "spellName = 'Intense Wound Cleansing', price = 6000})\n"
		.. "keywordHandler:addSpellKeyword({'berserk'}, {npcHandler = npcHandler, spellName = 'Reaver's Spin', price = 2500})\n"
		.. "keywordHandler:addSpellKeyword({'strike'}, {npcHandler = npcHandler, spellName = 'Apprentice\\'s Strike'})\n"
		.. "keywordHandler:addSpellKeyword({'x'}, {npcHandler = npcHandler, spellName = \"Divine Healing\"})\n"
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(SCRIPT)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import rename_spells as r; "
		.. "rows, names, runes = r.load(); t = open(sys.argv[1]).read(); n, c = r.rename_npc_lua(t, names); "
		.. "m, c2 = r.rename_npc_lua(n, names); open(sys.argv[1], 'w').write(n); print(c, c2, m == n)\" " .. path
	local hp = assert(io.popen(cmd))
	local counts = (hp:read("*a") or ""):gsub("%s+$", "")
	hp:close()
	f = assert(io.open(path, "rb"))
	local renamed = f:read("*a")
	f:close()
	os.remove(path)
	eq(counts, "4 0 True", "rename: three renamed + one broken line repaired, second run changes nothing")
	ok(load(renamed) ~= nil, "renamed script is valid Lua")
	ok(renamed:find("spellName = 'Warlord\\'s Resolve'", 1, true) ~= nil, "apostrophe escaped in single quotes")
	ok(renamed:find("spellName = 'Reaver\\'s Spin'", 1, true) ~= nil, "broken line of an older run repaired")
	ok(renamed:find("spellName = 'Kindling Spark'", 1, true) ~= nil, "escaped stock name found and renamed")
	ok(renamed:find("spellName = \"Dawn's Mending\"", 1, true) ~= nil, "double quotes: apostrophe as it is")
end

if fails > 0 then
	print(("npc_lib_test: %d of %d checks failed"):format(fails, checks))
	os.exit(1)
end
print(("npc_lib_test: all %d checks passed"):format(checks))

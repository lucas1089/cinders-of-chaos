-- Run from the server/ folder: luajit tests/base_crafting_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_crafting.py on the base server's crafting script (fixtures/base_crafting/1crafting_mod.lua, a copy
-- of the stock file with LF line ends): the patch itself (idempotent, CRLF kept, another version refused), then the
-- patched script on a mock engine: no craft away from a table, one pending craft per player, gold and materials taken
-- before the item is made, checks again in the delayed event, refunds when the item cannot be added.
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

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local STOCK = readFile("tests/fixtures/base_crafting/1crafting_mod.lua")

-- ---------------------------------------------------------------- the tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_crafting_patch_test: python3 not found, skipped")
	return
end

local function runPatch(text)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_crafting as p; "
		.. "t = open(sys.argv[1], encoding='utf-8', newline='').read(); n, s = p.patch(t); "
		.. "open(sys.argv[1], 'w', encoding='utf-8', newline='').write(n); print(s)\" " .. path
	local h = assert(io.popen(cmd))
	local status = (h:read("*a") or ""):gsub("%s+$", "")
	h:close()
	local out = readFile(path)
	os.remove(path)
	return out, status
end

local patched, st = runPatch(STOCK)
eq(st, "patched", "stock file patched")
local again, st2 = runPatch(patched)
eq(st2, "already", "second run: already patched")
eq(again, patched, "second run changes nothing")

local crlf = STOCK:gsub("\n", "\r\n")
local patchedCrlf, st3 = runPatch(crlf)
eq(st3, "patched", "CRLF stock file patched")
ok(not patchedCrlf:gsub("\r\n", ""):find("\n"), "CRLF file keeps CRLF line ends")
eq((patchedCrlf:gsub("\r\n", "\n")), patched, "CRLF and LF give the same script")

local other = STOCK:gsub("player:removeMoney%(craft%.cost%)", "player:removeMoney(craft.cost * 2)")
local otherOut, st4 = runPatch(other)
ok(st4:find("not the expected stock version", 1, true) ~= nil, "another Crafting:craft refused: " .. st4)
eq(otherOut, other, "a refused file is not changed")

local half = patched:gsub("%-%- Chaos: crafting guard %(patch_base_crafting%.py%) v1 table\n", "")
local _, st5 = runPatch(half)
ok(st5:find("partly patched", 1, true) ~= nil, "a partly patched file is refused: " .. st5)

-- ---------------------------------------------------------------- mock engine
local clockMs = 1000000
os.mtime = function() return clockMs end
local realTime = os.time
os.time = function(t)
	if t then
		return realTime(t)
	end
	return math.floor(clockMs / 1000)
end
math.random = function() return 100 end -- rollRarity: no rarity

CONST_SLOT_BACKPACK = 3
RETURNVALUE_NOERROR = 0
RETURNVALUE_NOTENOUGHROOM = 4
json = {encode = function() return "{}" end, decode = function(b) return b end}
function playSound() end

local actions, creatureEvents, events = {}, {}, {}
function Action()
	local a = {}
	function a:aid(id) self.id = id end
	function a:register() actions[self.id] = self end
	return a
end
function CreatureEvent(name)
	local e = {name = name}
	function e:type() end
	function e:register() creatureEvents[self.name] = self end
	return e
end
function addEvent(fn, delay)
	events[#events + 1] = {fn = fn, delay = delay}
end
local function runEvents()
	local list = events
	events = {}
	for _, ev in ipairs(list) do
		ev.fn()
	end
	return #list
end

local itemTypes = {
	[26712] = {name = "pruning knife", weight = 1000},
	[26713] = {name = "apprentice's scissor", weight = 1500},
	[26729] = {name = "leaf", weight = 10, stackable = true},
}
function ItemType(id)
	local t = itemTypes[id] or {name = "item " .. id, weight = 100}
	return {
		getName = function() return t.name end,
		getWeight = function(_, count) return t.weight * math.max(1, count or 1) end,
		isStackable = function() return t.stackable == true end,
		getClientId = function() return id end,
	}
end

local log = {}
local created = {}
Game = {}
function Game.createItem(id, count)
	log[#log + 1] = "create"
	local item = {id = id, count = count}
	function item:getWeight() return ItemType(id):getWeight(count) end
	created[#created + 1] = item
	return item
end
function Game.createItemWithRarity(id, count, rarity)
	local item = Game.createItem(id, count)
	item.rarity = rarity
	return item
end

local online = {}
Player = setmetatable({}, {__call = function(_, cid) return online[cid] end})
local P = setmetatable({}, {__index = Player})
P.__index = P

local function newPlayer(id)
	local p = setmetatable({id = id, pos = {x = 101, y = 100, z = 7}, money = 5000, items = {[26712] = 2, [26729] = 12},
		popups = {}, tries = 0, cap = 100000, slots = 10, received = {}}, P)
	online[id] = p
	return p
end
function P:getId() return self.id end
function P:getPosition() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
function P:getMoney() return self.money end
function P:removeMoney(n)
	if self.failMoney or self.money < n then
		return false
	end
	self.money = self.money - n
	log[#log + 1] = "removeMoney"
	return true
end
function P:addMoney(n)
	self.money = self.money + n
	log[#log + 1] = "addMoney"
	return true
end
function P:getItemCount(id) return self.items[id] or 0 end
function P:removeItem(id, n)
	if self.failRemove == id or (self.items[id] or 0) < n then
		return false
	end
	self.items[id] = self.items[id] - n
	log[#log + 1] = "removeItem " .. id
	return true
end
function P:addItem(id, n)
	self.items[id] = (self.items[id] or 0) + n
	log[#log + 1] = "addItem " .. id
	return true
end
function P:addItemEx(item)
	log[#log + 1] = "addItemEx"
	if self.failAdd then
		return RETURNVALUE_NOTENOUGHROOM
	end
	self.received[#self.received + 1] = item
	return RETURNVALUE_NOERROR
end
function P:popupFYI(text) self.popups[#self.popups + 1] = text end
function P:sendExtendedOpcode() end
function P:registerEvent() end
function P:getStorageValue() return -1 end
function P:getEffectiveSkillLevel() return 50 end
function P:addSkillTries(_, n) self.tries = self.tries + n end
function P:getFreeCapacity() return self.cap end
function P:getSlotItem(slot)
	if slot ~= CONST_SLOT_BACKPACK then
		return nil
	end
	local p = self
	return {getEmptySlots = function() return p.slots end}
end

-- ---------------------------------------------------------------- load the patched script
local realPrint, realDofile = print, dofile
print = function() end
dofile = function() error("no category files in the test") end
local chunk = assert((loadstring or load)(patched, "=1crafting_mod.lua"))
chunk()
print, dofile = realPrint, realDofile

Crafting.herbalist = {
	{name = "Apprentice's Scissor", id = 26713, level = 10, cost = 1000, count = 1,
		materials = {{id = 26712, count = 1}, {id = 26729, count = 5}}},
}
Crafting.mining = {
	{name = "Ore", id = 26712, level = 10, cost = 10, count = 1, materials = {{id = 26729, count = 1}}},
}

ok(actions[38820] and actions[38826] and actions[38824], "the seven table actions are registered")
local opcode = creatureEvents.CraftingExtended
ok(opcode ~= nil, "the opcode handler is registered")

local TABLE = {x = 100, y = 100, z = 7}
local function useTable(p, aid, z)
	local pos = {x = TABLE.x, y = TABLE.y, z = z or TABLE.z}
	return actions[aid or 38820].onUse(p, {}, pos, nil, pos)
end
local function craft(p, category, id)
	opcode.onExtendedOpcode(p, 91, {action = "craft", data = {category = category or "herbalist", craftId = id or 1}})
end
local function last(p) return p.popups[#p.popups] end
local function reset()
	log, created, events = {}, {}, {}
	clockMs = clockMs + 600000
end

-- 1. no table used: refused, nothing queued
local a = newPlayer(0x10000001)
craft(a)
eq(#events, 0, "no table: no craft queued")
eq(last(a), "Use the crafting table and stay next to it to craft.", "no table: refusal text")

-- 2. table used: 5 requests in the same moment -> one craft, one set of materials
reset()
useTable(a)
for _ = 1, 5 do
	craft(a)
end
eq(#events, 1, "concurrent requests: one craft queued")
eq(events[1] and events[1].delay, 860, "the stock delay")
eq(#a.popups, 1 + 4, "four busy refusals")
eq(last(a), "You are already crafting. Wait a moment.", "busy text")
clockMs = clockMs + 860
runEvents()
eq(#a.received, 1, "one item")
eq(a.money, 4000, "gold taken once")
eq(a.items[26712], 1, "first material taken once")
eq(a.items[26729], 7, "second material taken once")
eq(table.concat(log, ","), "removeMoney,removeItem 26712,removeItem 26729,create,addItemEx",
	"gold and materials removed before the item is created")
ok(a.tries > 0, "skill tries")

-- 3. cooldown: 1 s after the request
clockMs = clockMs + 100 -- 960 ms after the first request
craft(a)
eq(#events, 0, "cooldown: refused under 1 s")
clockMs = clockMs + 100
craft(a)
eq(#events, 1, "cooldown over: accepted")
runEvents()
eq(#a.received, 2, "second item")

-- 4. materials gone before the event: nothing taken, no item
reset()
local b = newPlayer(0x10000002)
useTable(b)
craft(b)
b.items[26729] = 2
clockMs = clockMs + 860
runEvents()
eq(#b.received, 0, "materials gone: no item")
eq(#created, 0, "materials gone: nothing created")
eq(b.money, 5000, "materials gone: gold kept")
eq(last(b), "You don't have enough leaf (need 5).", "materials gone: stock text")

-- 5. addItemEx fails: gold and materials given back, the item is not kept
reset()
local c = newPlayer(0x10000003)
useTable(c)
c.failAdd = true
craft(c)
runEvents()
eq(#c.received, 0, "add fails: no item")
eq(c.money, 5000, "add fails: gold refunded")
eq(c.items[26712], 2, "add fails: first material refunded")
eq(c.items[26729], 12, "add fails: second material refunded")
eq(table.concat(log, ","),
	"removeMoney,removeItem 26712,removeItem 26729,create,addItemEx,addMoney,addItem 26712,addItem 26729",
	"add fails: taken first, refunded after")
ok(last(c):find("given back", 1, true) ~= nil, "add fails: text")

-- 6. a material cannot be removed: what was taken comes back, nothing created
reset()
local d = newPlayer(0x10000004)
useTable(d)
d.failRemove = 26729
craft(d)
runEvents()
eq(#created, 0, "remove fails: nothing created")
eq(d.money, 5000, "remove fails: gold back")
eq(d.items[26712], 2, "remove fails: first material back")
eq(last(d), "Your materials could not be taken. Nothing was crafted.", "remove fails: text")

-- 7. gold cannot be removed: nothing taken, nothing created
reset()
local e = newPlayer(0x10000005)
useTable(e)
e.failMoney = true
craft(e)
runEvents()
eq(#created, 0, "gold fails: nothing created")
eq(e.items[26712], 2, "gold fails: materials untouched")
eq(e.items[26729], 12, "gold fails: materials untouched")

-- 8. table range, time and category
reset()
local f = newPlayer(0x10000006)
useTable(f)
f.pos = {x = 103, y = 100, z = 7}
craft(f)
eq(#events, 0, "3 tiles away: refused")
f.pos = {x = 102, y = 98, z = 7}
craft(f)
eq(#events, 1, "2 tiles away: accepted")
f.pos = {x = 105, y = 100, z = 7}
runEvents()
eq(#created, 0, "walked away before the event: nothing created")
eq(f.money, 5000, "walked away: gold kept")
eq(last(f), "Use the crafting table and stay next to it to craft.", "walked away: text")

reset()
f.pos = {x = 101, y = 100, z = 6}
useTable(f, 38820, 6)
f.pos = {x = 100, y = 100, z = 7}
craft(f)
eq(#events, 0, "another floor: refused")

reset()
f.pos = {x = 101, y = 100, z = 7}
useTable(f)
clockMs = clockMs + 301000
craft(f)
eq(#events, 0, "table used over 5 minutes ago: refused")

reset()
useTable(f, 38820)
craft(f, "mining")
eq(#events, 0, "herbalist table, mining recipe: refused")
useTable(f, 38822)
craft(f, "mining")
eq(#events, 1, "mining table, mining recipe: accepted")
runEvents()

-- 9. logged out before the event
reset()
local g = newPlayer(0x10000007)
useTable(g)
craft(g)
online[g.id] = nil
eq(runEvents(), 1, "logout: the event runs")
eq(#created, 0, "logout: nothing created")
eq(g.money, 5000, "logout: nothing taken")

print(string.format("base_crafting_patch_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

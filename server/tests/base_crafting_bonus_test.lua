-- Run from the server/ folder: luajit tests/base_crafting_bonus_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_crafting_bonus.py on the base crafting script (fixtures/base_crafting/1crafting_mod.lua) after
-- tools/patch_base_crafting.py and tools/patch_base_crafting_ui.py: the patch (needs both earlier patches, idempotent,
-- CRLF kept, partly patched or another version refused, the earlier tools still see their markers), then the patched
-- script with the real data/scripts/chaos/craft_bonus.lua on a mock engine: equipment is made by ChaosCrafting.createItem
-- with a rarity only after the gold and the materials were taken, five requests at once still give one item, potions
-- get their extra pieces only once the item was added, a failed add refunds and gives no extra, tools keep the stock
-- roll and texts, the recipe pages carry the odds, and a server without craft_bonus.lua crafts the stock way.
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
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local STOCK = readFile("tests/fixtures/base_crafting/1crafting_mod.lua")
if not STOCK then
	print("base_crafting_bonus_test: fixture missing, skipped")
	return
end
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_crafting_bonus_test: python3 not found, skipped")
	return
end

local function runPatch(module, text)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import " .. module .. " as p; "
		.. "t = open(sys.argv[1], encoding='utf-8', newline='').read(); n, s = p.patch(t); "
		.. "open(sys.argv[1], 'w', encoding='utf-8', newline='').write(n); print(s)\" " .. path
	local h = assert(io.popen(cmd))
	local status = (h:read("*a") or ""):gsub("%s+$", "")
	h:close()
	local out = readFile(path)
	os.remove(path)
	return out, status
end

-- ---------------------------------------------------------------- the tool
local out0, st0 = runPatch("patch_base_crafting_bonus", STOCK)
ok(st0:find("patch_base_crafting.py", 1, true) ~= nil, "the stock file is refused: " .. st0)
eq(out0, STOCK, "a refused file is not changed")
local guarded = runPatch("patch_base_crafting", STOCK)
local _, st1 = runPatch("patch_base_crafting_bonus", guarded)
ok(st1:find("patch_base_crafting_ui.py", 1, true) ~= nil, "the ui patch is needed too: " .. st1)
local windowed = runPatch("patch_base_crafting_ui", guarded)
local patched, st = runPatch("patch_base_crafting_bonus", windowed)
eq(st, "patched", "bonus patch")
local again, st2 = runPatch("patch_base_crafting_bonus", patched)
eq(st2, "already", "second run: already patched")
eq(again, patched, "second run changes nothing")
eq(select(2, runPatch("patch_base_crafting", patched)), "already", "the guard tool still sees its markers")
eq(select(2, runPatch("patch_base_crafting_ui", patched)), "already", "the ui tool still sees its markers")
ok(not patched:find("acquired a rarity: \" .. RarityNames[rarityId]", 1, true), "the old success texts are gone")
local take = patched:find("if not CraftGuard.take(player, craft) then", 1, true)
local make = patched:find("local made = CraftingBonus.make(", 1, true)
local added = patched:find("if not CraftGuard.added(player:addItemEx(item)) then", 1, true)
local finish = patched:find("CraftingUi.notify(player, \"ok\", CraftingBonus.finish(", 1, true)
ok(take and make and added and finish and take < make and make < added and added < finish,
	"take, then make, then add, then finish")

local wCrlf = runPatch("patch_base_crafting_ui", (runPatch("patch_base_crafting", (STOCK:gsub("\n", "\r\n")))))
local pCrlf, st3 = runPatch("patch_base_crafting_bonus", wCrlf)
eq(st3, "patched", "CRLF file patched")
ok(not pCrlf:gsub("\r\n", ""):find("\n"), "CRLF file keeps CRLF line ends")
eq((pCrlf:gsub("\r\n", "\n")), patched, "CRLF and LF give the same script")

local half = patched:gsub("%-%- Chaos: crafting bonus %(patch_base_crafting_bonus%.py%) v1 odds", "")
local _, st4 = runPatch("patch_base_crafting_bonus", half)
ok(st4:find("partly patched", 1, true) ~= nil, "a partly patched file is refused: " .. st4)
local other = windowed:gsub("local rarityId = rollRarity%(%)", "local rarityId = 0")
local otherOut, st5 = runPatch("patch_base_crafting_bonus", other)
ok(st5:find("not the expected version", 1, true) ~= nil, "another version is refused: " .. st5)
eq(otherOut, other, "another version is not changed")

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
local stockRoll = 100
math.random = function() return stockRoll end -- the stock rollRarity: 100 = no rarity

CONST_SLOT_BACKPACK = 3
RETURNVALUE_NOERROR = 0
RETURNVALUE_NOTENOUGHROOM = 1
INDEX_WHEREEVER, FLAG_NOLIMIT = -1, 1
local captured
json = {encode = function(t)
	if t.action == "fetch" then
		captured = t
		return "{}"
	end
	return t
end, decode = function(b) return b end}
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
end

local types = {
	[2519] = {name = "crown shield", gear = true},
	[28076] = {name = "Exalted Health Potion", stackable = true},
	[26713] = {name = "apprentice's scissor"},
	[26712] = {name = "pruning knife"},
	[26729] = {name = "leaf", stackable = true},
}
function ItemType(id)
	local t = types[id] or {name = "item " .. id}
	return {
		getName = function() return t.name end,
		getWeight = function(_, count) return 100 * math.max(1, count or 1) end,
		isStackable = function() return t.stackable == true end,
		getClientId = function() return id + 1 end,
		isRune = function() return false end,
		getMinReqLevel = function() return 0 end,
	}
end

local log = {}
Game = {}
function Game.createItem(id, count)
	log[#log + 1] = "create"
	return {id = id, count = count}
end
function Game.createItemWithRarity(id, count, rarity)
	log[#log + 1] = "createWithRarity"
	return {id = id, count = count, rarity = rarity}
end

-- the Chaos side craft_bonus.lua uses (stand-ins; their own tests cover them)
local nextRarityRoll = 1
ChaosCrafting = {
	isGear = function(item) return (types[item:getId()] or {}).gear == true end,
	createItem = function(id, rarity, level)
		log[#log + 1] = "forge " .. rarity
		return {id = id, count = 1, rarity = rarity, level = level}
	end,
	rarityName = function(r) return ({"Common", "Uncommon", "Magic", "Rare", "Legendary"})[r] end,
}
ChaosItemMods = {sourceLevel = function() return 1 end}
ChaosGems = {rollDropSockets = function() return 0 end}

local online = {}
Player = setmetatable({}, {__call = function(_, cid) return online[cid] end})
local P = setmetatable({}, {__index = Player})
P.__index = P
local function newPlayer(id)
	local p = setmetatable({id = id, pos = {x = 101, y = 100, z = 7}, money = 50000,
		items = {[26712] = 20, [26729] = 120}, sent = {}, received = {}, skill = 65}, P)
	online[id] = p
	return p
end
function P:getId() return self.id end
function P:getPosition() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
function P:getMoney() return self.money end
function P:removeMoney(n)
	if self.money < n then return false end
	self.money = self.money - n
	log[#log + 1] = "removeMoney"
	return true
end
function P:addMoney(n) self.money = self.money + n log[#log + 1] = "addMoney" return true end
function P:getItemCount(id) return self.items[id] or 0 end
function P:removeItem(id, n)
	if (self.items[id] or 0) < n then return false end
	self.items[id] = self.items[id] - n
	log[#log + 1] = "removeItem " .. id
	return true
end
function P:addItem(id, n)
	self.items[id] = (self.items[id] or 0) + n
	log[#log + 1] = "addItem " .. id .. " x" .. n
	return true
end
function P:addItemEx(item)
	log[#log + 1] = "addItemEx"
	if self.failAdd then return RETURNVALUE_NOTENOUGHROOM end
	self.received[#self.received + 1] = item
	self.items[item.id] = (self.items[item.id] or 0) + (item.count or 1)
	return RETURNVALUE_NOERROR
end
function P:popupFYI() error("no popup boxes after the ui patch") end
function P:sendExtendedOpcode(op, msg) self.sent[#self.sent + 1] = {op = op, msg = msg} end
function P:registerEvent() end
function P:getStorageValue() return -1 end
function P:getEffectiveSkillLevel() return self.skill end
function P:addSkillTries() end
function P:getFreeCapacity() return 100000 end
function P:getSlotItem() return {getEmptySlots = function() return 10 end} end
function P:getInbox() return {addItem = function() end} end

Chaos = {giveItem = function(player, id, n)
	player:addItem(id, n)
	return n
end}

local realPrint, realDofile = print, dofile
print = function() end
dofile = function() error("no category files in the test") end
local chunk = assert((loadstring or load)(patched, "=1crafting_mod.lua"))
chunk()
dofile = realDofile
dofile("data/scripts/chaos/craft_bonus.lua")
print = realPrint
local B = ChaosCraftBonus

Crafting.armorsmith = {
	{name = "Crown Shield", id = 2519, level = 10, cost = 1000, count = 1, storage = 0, storageText = "",
		materials = {{id = 26712, count = 1}, {id = 26729, count = 5}}},
}
Crafting.herbalist = {
	{name = "Exalted Health Potion", id = 28076, level = 15, cost = 850, count = 5, storage = 0, storageText = "",
		materials = {{id = 26729, count = 5}}},
	{name = "Apprentice's Scissor", id = 26713, level = 10, cost = 1000, count = 1, storage = 0, storageText = "",
		materials = {{id = 26712, count = 1}}},
}

local opcode = creatureEvents.CraftingExtended
local function send(p, action, data) opcode.onExtendedOpcode(p, 91, {action = action, data = data}) end
local function lastMessage(p)
	for i = #p.sent, 1, -1 do
		if p.sent[i].msg.action == "message" then
			return p.sent[i].msg.data
		end
	end
end
local TABLE = {x = 100, y = 100, z = 7}
local function useTable(p, aid) return actions[aid].onUse(p, {}, TABLE, nil, TABLE) end
local function reset()
	log, events = {}, {}
	clockMs = clockMs + 2000
end
-- the rolls craft_bonus.lua makes: a fixed value
local function rolls(v) B.random = function() return v end end

-- 1. equipment: a Rare roll (the best a craft gives), made after gold and materials, five requests give one item
local a = newPlayer(0x10000001)
useTable(a, 38825)
rolls(1)
for _ = 1, 5 do
	send(a, "craft", {category = "armorsmith", craftId = 1})
end
eq(#events, 1, "five requests: one craft queued")
runEvents()
eq(#a.received, 1, "one item")
eq(a.received[1].rarity, 4, "Rare")
eq(a.received[1].level, 37, "item level: recipe 10 + (65 - 10) / 2")
eq(table.concat(log, ","), "removeMoney,removeItem 26712,removeItem 26729,forge 4,addItemEx",
	"gold and materials first, then the Chaos roll, then the add")
eq(a.money, 49000, "gold once")
local m = lastMessage(a)
eq(m.kind, "ok", "ok")
eq(m.text, "You crafted a Rare Crown Shield (item level 37).", "rarity named in the text")

-- 2. a plain roll
reset()
rolls(100000)
send(a, "craft", {category = "armorsmith", craftId = 1})
runEvents()
eq(a.received[2].rarity, 0, "plain")
eq(lastMessage(a).text, "You crafted a Crown Shield (item level 37).", "plain text")

-- 3. potions: the recipe's 5 plus a double
reset()
useTable(a, 38820)
rolls(1)
local before = a.items[28076] or 0
send(a, "craft", {category = "herbalist", craftId = 1})
runEvents()
eq(a.received[3].count, 5, "the recipe's own stack")
eq(a.items[28076] - before, 10, "plus 5 extra")
eq(table.concat(log, ","), "removeMoney,removeItem 26729,create,addItemEx,addItem 28076 x5",
	"the extra pieces only after the item was added")
eq(lastMessage(a).text, "You crafted 10 Exalted Health Potions (bonus +5).", "count and bonus in the text")

-- 4. a failed add: everything back, no extra pieces
reset()
a.failAdd = true
rolls(1)
local money, leaf, pots = a.money, a.items[26729], a.items[28076]
send(a, "craft", {category = "herbalist", craftId = 1})
runEvents()
a.failAdd = nil
eq(a.money, money, "gold back")
eq(a.items[26729], leaf, "materials back")
eq(a.items[28076], pots, "no extra pieces")
eq(lastMessage(a).kind, "error", "error message")

-- 5. a tool: the stock roll and text
reset()
stockRoll = 100
send(a, "craft", {category = "herbalist", craftId = 2})
runEvents()
eq(table.concat(log, ","), "removeMoney,removeItem 26712,create,addItemEx", "the stock make")
eq(lastMessage(a).text, "Item Successfully Crafted: apprentice's scissor", "the stock text")

-- 6. the recipe pages carry the odds
send(a, "fetch", {category = "herbalist", page = 1})
local crafts = captured.data.crafts
eq(crafts[1].bonus.kind, "stack", "potion: stack odds")
eq(crafts[1].bonus.odds[1].extra, 5, "potion: double first")
eq(crafts[1].bonus.odds[1].pct, 4, "potion: double at mastery 50")
eq(crafts[2].bonus, nil, "tool: no odds")
send(a, "fetch", {category = "armorsmith", page = 1})
local gear = captured.data.crafts[1].bonus
eq(gear.kind, "gear", "shield: gear odds")
eq(gear.level, 37, "shield: item level")
eq(gear.odds[1].name, "Rare", "shield: best first")

-- 7. ChaosCraftBonus failing or missing: the stock way
reset()
local realMake = B.make
B.make = function() error("boom") end
useTable(a, 38825)
stockRoll = 1 -- the stock roll: a rarity
print = function() end
send(a, "craft", {category = "armorsmith", craftId = 1})
runEvents()
print = realPrint
B.make = realMake
eq(table.concat(log, ","), "removeMoney,removeItem 26712,removeItem 26729,createWithRarity,addItemEx",
	"an error falls back to the stock roll")
eq(lastMessage(a).text, "Your crafted item has acquired a rarity: Common", "the stock rarity text")
reset()
local saved = ChaosCraftBonus
ChaosCraftBonus = nil
stockRoll = 100
send(a, "craft", {category = "armorsmith", craftId = 1})
runEvents()
ChaosCraftBonus = saved
eq(table.concat(log, ","), "removeMoney,removeItem 26712,removeItem 26729,create,addItemEx",
	"without craft_bonus.lua: the stock make")
eq(lastMessage(a).text, "Item Successfully Crafted: crown shield", "without craft_bonus.lua: the stock text")

print(string.format("base_crafting_bonus_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

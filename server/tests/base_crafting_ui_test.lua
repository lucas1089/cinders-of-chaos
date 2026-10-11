-- Run from the server/ folder: luajit tests/base_crafting_ui_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_crafting_ui.py on the base crafting script (fixtures/base_crafting/1crafting_mod.lua) after
-- tools/patch_base_crafting.py: the patch (needs the guard patch first, idempotent, CRLF kept, partly patched refused),
-- then the patched script on a mock engine: every answer to a craft is a JSON "message" on opcode 91 (no popup box),
-- "ok" only for the success texts; the recipe pages carry material names; "tip" answers with the item tooltip.
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
	print("base_crafting_ui_test: fixture missing, skipped")
	return
end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_crafting_ui_test: python3 not found, skipped")
	return
end

-- runs tools/<module>.patch on text; returns the new text and the status
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
local stockOut, st0 = runPatch("patch_base_crafting_ui", STOCK)
ok(st0:find("run that first", 1, true) ~= nil, "a file without the guard patch is refused: " .. st0)
eq(stockOut, STOCK, "a refused file is not changed")

local guarded, stg = runPatch("patch_base_crafting", STOCK)
eq(stg, "patched", "guard patch first")
local patched, st = runPatch("patch_base_crafting_ui", guarded)
eq(st, "patched", "ui patch")
local again, st2 = runPatch("patch_base_crafting_ui", patched)
eq(st2, "already", "second run: already patched")
eq(again, patched, "second run changes nothing")
local _, st3 = runPatch("patch_base_crafting", patched)
eq(st3, "already", "the guard tool still sees its markers")
ok(not patched:find("popupFYI", 1, true), "no popup box left")

local guardedCrlf = runPatch("patch_base_crafting", (STOCK:gsub("\n", "\r\n")))
local patchedCrlf, st4 = runPatch("patch_base_crafting_ui", guardedCrlf)
eq(st4, "patched", "CRLF file patched")
ok(not patchedCrlf:gsub("\r\n", ""):find("\n"), "CRLF file keeps CRLF line ends")
eq((patchedCrlf:gsub("\r\n", "\n")), patched, "CRLF and LF give the same script")

local half = patched:gsub("%-%- Chaos: crafting window %(patch_base_crafting_ui%.py%) v1 tip", "")
local _, st5 = runPatch("patch_base_crafting_ui", half)
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
-- the script encodes tables; the mock hands the table itself to sendExtendedOpcode (a recipe page is cut into chunks
-- of its JSON text: a short string here)
json = {encode = function(t) return t.action == "fetch" and "{}" or t end, decode = function(b) return b end}
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

local names = {[26712] = "pruning knife", [26713] = "apprentice's scissor", [26729] = "leaf"}
function ItemType(id)
	return {
		getName = function() return names[id] or ("item " .. id) end,
		getWeight = function(_, count) return 100 * math.max(1, count or 1) end,
		isStackable = function() return id == 26729 end,
		getClientId = function() return id + 1 end,
	}
end
Game = {}
function Game.createItem(id, count)
	return {id = id, count = count, getWeight = function() return 100 end}
end
Game.createItemWithRarity = Game.createItem
ChaosItemTooltip = {build = function(item) return {id = item.id + 1, name = names[item.id], key = "k", base = {}} end}

local online = {}
Player = setmetatable({}, {__call = function(_, cid) return online[cid] end})
local P = setmetatable({}, {__index = Player}) -- the script adds Player:showCrafting
P.__index = P
local function newPlayer(id)
	local p = setmetatable({id = id, pos = {x = 101, y = 100, z = 7}, money = 5000, items = {[26712] = 2, [26729] = 12},
		sent = {}, popups = 0, received = 0}, P)
	online[id] = p
	return p
end
function P:getId() return self.id end
function P:getPosition() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
function P:getMoney() return self.money end
function P:removeMoney(n)
	if self.money < n then return false end
	self.money = self.money - n
	return true
end
function P:addMoney(n) self.money = self.money + n return true end
function P:getItemCount(id) return self.items[id] or 0 end
function P:removeItem(id, n)
	if (self.items[id] or 0) < n then return false end
	self.items[id] = self.items[id] - n
	return true
end
function P:addItem(id, n) self.items[id] = (self.items[id] or 0) + n return true end
function P:addItemEx() self.received = self.received + 1 return RETURNVALUE_NOERROR end
function P:popupFYI() self.popups = self.popups + 1 end
function P:sendExtendedOpcode(op, msg)
	self.sent[#self.sent + 1] = {op = op, msg = msg}
end
function P:registerEvent() end
function P:getStorageValue() return -1 end
function P:getEffectiveSkillLevel() return self.skill or 50 end
function P:addSkillTries() end
function P:getFreeCapacity() return 100000 end
function P:getSlotItem() return {getEmptySlots = function() return 10 end} end

local realPrint, realDofile = print, dofile
print = function() end
dofile = function() error("no category files in the test") end
local chunk = assert((loadstring or load)(patched, "=1crafting_mod.lua"))
chunk()
print, dofile = realPrint, realDofile

Crafting.herbalist = {
	{name = "Apprentice's Scissor", id = 26713, level = 10, cost = 1000, count = 1, storage = 0, storageText = "",
		materials = {{id = 26712, count = 1}, {id = 26729, count = 5}}},
}

local opcode = creatureEvents.CraftingExtended
local function send(p, action, data) opcode.onExtendedOpcode(p, 91, {action = action, data = data}) end
local function lastOf(p, action)
	for i = #p.sent, 1, -1 do
		if p.sent[i].msg.action == action then
			return p.sent[i].msg, p.sent[i].op
		end
	end
end
local TABLE = {x = 100, y = 100, z = 7}
local function useTable(p) return actions[38820].onUse(p, {}, TABLE, nil, TABLE) end

-- 1. refusal away from a table: a message, no popup
local a = newPlayer(0x10000001)
send(a, "craft", {category = "herbalist", craftId = 1})
local m, op = lastOf(a, "message")
eq(op, 91, "message on opcode 91")
eq(m and m.data.kind, "error", "refusal: kind error")
eq(m and m.data.text, "Use the crafting table and stay next to it to craft.", "refusal: the guard text")
eq(a.popups, 0, "no popup box")

-- 2. at the table: the craft acknowledgement, then "ok" after the delay
useTable(a)
eq(lastOf(a, "show").data.category, "herbalist", "table use: show")
send(a, "craft", {category = "herbalist", craftId = 1})
eq(lastOf(a, "craft").data.success, true, "accepted: craft acknowledgement")
runEvents()
m = lastOf(a, "message")
eq(m.data.kind, "ok", "success: kind ok")
ok(m.data.text:find("apprentice's scissor", 1, true) ~= nil, "success: item name in the text")
eq(a.received, 1, "item given")
eq(a.popups, 0, "no popup box on success")
local page = lastOf(a, "chunkedFetch")
ok(page ~= nil, "the page is sent again after a craft")

-- 3. busy: a second request inside 1 s
send(a, "craft", {category = "herbalist", craftId = 1})
eq(lastOf(a, "message").data.text, "You are already crafting. Wait a moment.", "busy text")
eq(lastOf(a, "message").data.kind, "error", "busy: kind error")

-- 4. missing gold and skill
clockMs = clockMs + 2000
a.money = 10
send(a, "craft", {category = "herbalist", craftId = 1})
eq(lastOf(a, "message").data.kind, "error", "no gold: error")
ok(lastOf(a, "message").data.text:find("money", 1, true) ~= nil, "no gold: text")
a.money = 5000
a.skill = 3
send(a, "craft", {category = "herbalist", craftId = 1})
ok(lastOf(a, "message").data.text:find("skill", 1, true) ~= nil, "low skill: text")
a.skill = nil

-- 5. the recipe pages carry material names (sent in chunks: the mock passes the joined table through)
a.sent = {}
local captured
local realEncode = json.encode
json.encode = function(t)
	if t.action == "fetch" then captured = t end
	return realEncode(t)
end
send(a, "fetch", {category = "herbalist", page = 1})
json.encode = realEncode
ok(captured ~= nil, "fetch answered")
local mats = captured and captured.data.crafts[1].materials or {}
eq(mats[1] and mats[1].name, "pruning knife", "material name")
eq(mats[2] and mats[2].name, "leaf", "second material name")
eq(mats[2] and mats[2].player, 7, "the player's count (12 less the 5 crafted with)")

-- 6. tip
send(a, "tip", {category = "herbalist", craftId = 1})
m = lastOf(a, "tip")
eq(m and m.data.craftId, 1, "tip: recipe echoed")
eq(m and m.data.tip.name, "apprentice's scissor", "tip: tooltip")
eq(m and m.data.tip.key, nil, "tip: no cache key")
local n = #a.sent
send(a, "tip", {category = "craft", craftId = 1})
send(a, "tip", {category = "herbalist", craftId = 99})
send(a, "tip", "junk")
eq(#a.sent, n, "tip: unknown recipe or method name ignored")
for _ = 1, 20 do send(a, "tip", {category = "herbalist", craftId = 1}) end
ok(#a.sent - n <= 8, "tip: at most 8 per second, got " .. (#a.sent - n))

-- 7. malformed requests (v2 valid): a category must be one of the 7 and a page a whole number, so a fetch that names
-- one of the script's own functions ("craft") no longer takes the length of a function and logs a Lua error
local function quiet(what, buffer)
	local before = #a.sent
	print = function() end -- the stock "[Crafting] Invalid fetch request" line
	local okCall, err = pcall(opcode.onExtendedOpcode, a, 91, buffer)
	print = realPrint
	ok(okCall, what .. ": no Lua error (" .. tostring(err) .. ")")
	eq(#a.sent, before, what .. ": nothing sent")
end
for _, cat in ipairs({"craft", "sendCrafts", "sendMaterials", "fetch", "__index", "", 5, true}) do
	quiet("fetch category " .. tostring(cat), {action = "fetch", data = {category = cat, page = 1}})
	quiet("show category " .. tostring(cat), {action = "show", data = {category = cat}})
	quiet("craft category " .. tostring(cat), {action = "craft", data = {category = cat, craftId = 1}})
end
for _, pg in ipairs({0, -1, 1.5, "abc", 1e9, {}, true}) do
	quiet("fetch page " .. tostring(pg), {action = "fetch", data = {category = "herbalist", page = pg}})
end
for _, data in ipairs({"junk", 5, true}) do
	quiet("fetch data " .. tostring(data), {action = "fetch", data = data})
	quiet("show data " .. tostring(data), {action = "show", data = data})
	quiet("craft data " .. tostring(data), {action = "craft", data = data})
end
quiet("a JSON number", 5)
quiet("a JSON string", "fetch")
quiet("craft of an unknown recipe", {action = "craft", data = {category = "herbalist", craftId = "1"}})
a.sent = {}
send(a, "fetch", {category = "herbalist", page = "1"})
ok(lastOf(a, "chunkedFetch") ~= nil, "a page given as text \"1\" is still answered")
a.sent = {}
send(a, "fetch", {category = "herbalist"})
ok(lastOf(a, "chunkedFetch") ~= nil, "a fetch without a page shows page 1")
ok(patched:find("v2 valid", 1, true) ~= nil, "the checks are marked")

-- an install patched before the checks existed (v1 only) gets them on the next run, then nothing more
local v1 = runPatch("patch_base_crafting_ui", guarded)
local v1only = (function()
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(guarded)
	f:close()
	local h = assert(io.popen("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_crafting_ui as p; "
		.. "t = open(sys.argv[1], encoding='utf-8', newline='').read(); n, s = p.patch_v1(t); "
		.. "open(sys.argv[1], 'w', encoding='utf-8', newline='').write(n); print(s)\" " .. path))
	h:read("*a")
	h:close()
	local out = readFile(path)
	os.remove(path)
	return out
end)()
ok(v1only and not v1only:find("v2 valid", 1, true) and v1only:find("v1 ui", 1, true), "a v1-only file for the upgrade")
local upgraded, stu = runPatch("patch_base_crafting_ui", v1only)
eq(stu, "patched", "a v1-only install gets the checks")
eq(upgraded, v1, "the upgrade ends as a fresh install")
local _, stu2 = runPatch("patch_base_crafting_ui", upgraded)
eq(stu2, "already", "and then nothing more")
local v1Crlf = v1only:gsub("\n", "\r\n")
local upCrlf, stu3 = runPatch("patch_base_crafting_ui", v1Crlf)
eq(stu3, "patched", "a CRLF v1-only install gets the checks")
eq((upCrlf:gsub("\r\n", "\n")), v1, "and keeps CRLF")
ok(not upCrlf:gsub("\r\n", ""):find("\n"), "CRLF kept on the upgrade")
local _, stb = runPatch("patch_base_crafting_bonus", upgraded)
eq(stb, "patched", "the bonus tool still finds its anchors")

print(string.format("base_crafting_ui_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/base_item_names_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_item_names.py on a small base data folder written here: items.xml entries get the names of a CSV
-- by id (name, article, plural), monster loot that named them becomes loot by id (Lua and XML), other mentions in the
-- base data are renamed whole words only, the repository's own folders are left alone, a second run changes nothing.
-- The fixture names are placeholders.
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

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_item_names_patch_test: python3 not found, skipped")
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

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
for _, d in ipairs({"items", "monster/monsters", "monster/lua/bosses", "npc/scripts", "actions/scripts",
		"scripts/chaos"}) do
	os.execute("mkdir -p '" .. data .. "/" .. d .. "'")
end
writeFile(root .. "/names.csv", "id,article,name,plural\n"
	.. "30001,an,ember test quiver,\n"
	.. "30002,a,grim test mask,grim test masks\n"
	.. "30003,,new plain thing,\n"
	.. "30099,a,missing entry,\n")

writeFile(data .. "/items/items.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<items>
	<item id="30001" article="a" name="Placeholder Quiver">
		<attribute key="weight" value="800" />
	</item>
	<item id="30002" article="a" name="old test mask" plural="old test masks">
		<attribute key="armor" value="5" />
	</item>
	<item id="30003" article="an" name="old plain thing" />
	<item id="30004" article="an" name="old test mask holder" />
</items>
]])
writeFile(data .. "/monster/lua/bosses/boss.lua", [[
monster.loot = {
	{id = "placeholder quiver", chance = 2000},
	{id = "Old Test Mask", chance = 1000},
	{id = "old test mask holder", chance = 500},
	{id = 30001, chance = 100},
	{name = "gold coin", chance = 100000, maxCount = 50}
}
]])
writeFile(data .. "/monster/monsters/brute.xml", [[
<monster name="Brute">
	<loot>
		<item name="old plain thing" chance="5000" />
		<item id="2148" countmax="20" chance="50000" />
	</loot>
</monster>
]])
writeFile(data .. "/npc/Trader.xml", [[
<npc name="Trader">
	<parameters>
		<parameter key="shop_buyable" value="old test mask,30002,900;old test mask holder,30004,50;" />
	</parameters>
</npc>
]])
writeFile(data .. "/actions/scripts/reward.lua", [[
player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have found an Old Test Mask and a placeholder quivers bag.")
]])
local ours = "-- old test mask stays in the repository's own scripts\n"
writeFile(data .. "/scripts/chaos/ours.lua", ours)

local function run(extra)
	local h = io.popen("python3 -I tools/patch_base_item_names.py '" .. data .. "' --names '" .. root .. "/names.csv' "
		.. (extra or "") .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end

local dry = run("--dry-run")
ok(dry:find("dry run: nothing written", 1, true) ~= nil, "dry run: " .. dry)
ok(readFile(data .. "/items/items.xml"):find("Placeholder Quiver", 1, true) ~= nil, "dry run writes nothing")

local out1 = run()
ok(out1:find("file(s) written", 1, true) ~= nil, "first run writes: " .. out1)
ok(out1:find("30099 has no entry of its own", 1, true) ~= nil, "a CSV id without an entry is listed")

local items = readFile(data .. "/items/items.xml")
ok(items:find('<item id="30001" article="an" name="ember test quiver">', 1, true) ~= nil, "quiver: name and article")
ok(items:find('<item id="30002" article="a" name="grim test mask" plural="grim test masks">', 1, true) ~= nil,
	"mask: name and plural")
ok(items:find('<item id="30003" name="new plain thing" />', 1, true) ~= nil, "an empty article removes it")
ok(items:find('<item id="30004" article="an" name="old test mask holder" />', 1, true) ~= nil, "other entries untouched")

local boss = readFile(data .. "/monster/lua/bosses/boss.lua")
ok(boss:find("{id = 30001, chance = 2000}", 1, true) ~= nil, "Lua loot by old name -> id")
ok(boss:find("{id = 30002, chance = 1000}", 1, true) ~= nil, "Lua loot by old name, any case -> id")
ok(boss:find('{id = "old test mask holder", chance = 500}', 1, true) ~= nil, "a longer name is another item")
ok(boss:find('{name = "gold coin"', 1, true) ~= nil, "the rest kept")
local brute = readFile(data .. "/monster/monsters/brute.xml")
ok(brute:find('<item id="30003" chance="5000" />', 1, true) ~= nil, "XML loot by old name -> id")
ok(brute:find('<item id="2148" countmax="20"', 1, true) ~= nil, "XML loot by id kept")
local trader = readFile(data .. "/npc/Trader.xml")
ok(trader:find("grim test mask,30002,900;old test mask holder,30004,50;", 1, true) ~= nil, "NPC shop: whole words only")
local reward = readFile(data .. "/actions/scripts/reward.lua")
ok(reward:find("grim test mask", 1, true) ~= nil and reward:find("Old Test Mask", 1, true) == nil,
	"a mention in another case gets the new name: " .. reward)
ok(reward:find("You have found an ", 1, true) ~= nil and reward:find("ember test quiver", 1, true) == nil
	and reward:find("placeholder quivers bag", 1, true) ~= nil, "a plural form is another word")
eq(readFile(data .. "/scripts/chaos/ours.lua"), ours, "data/scripts/chaos untouched")

-- second run: nothing to change
local before = {}
for _, p in ipairs({"/items/items.xml", "/monster/lua/bosses/boss.lua", "/monster/monsters/brute.xml", "/npc/Trader.xml",
		"/actions/scripts/reward.lua"}) do
	before[p] = readFile(data .. p)
end
local out2 = run()
ok(out2:find("0 file(s) written", 1, true) ~= nil, "second run: nothing written (" .. out2 .. ")")
for p, text in pairs(before) do
	eq(readFile(data .. p), text, "second run keeps " .. p)
end

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_item_names_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

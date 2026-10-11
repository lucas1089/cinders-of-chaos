-- Run from the server/ folder: luajit tests/base_monster_names_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_monster_names.py on a small base data folder written here: the CSV keys the names by the sha256 of
-- the old name in lower case; registrations, monster files, Lua monsters, spawns, raids, scripts (strings only) and
-- item descriptions get the new names, item names and other longer names keep theirs, NPC dialogue, the quest log,
-- house files, paths, identifiers, comments and the repository's own folders are left alone, a second run changes
-- nothing. The fixture names are placeholders.
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
local function has(text, part, what)
	ok(text ~= nil and text:find(part, 1, true) ~= nil, what .. " (" .. part .. ")")
end
local function hasnt(text, part, what)
	ok(text ~= nil and text:find(part, 1, true) == nil, what .. " (no " .. part .. ")")
end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_monster_names_patch_test: python3 not found, skipped")
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
for _, d in ipairs({"items", "monster/monsters", "monster/lua/bosses", "monster/monsters/chaos", "world", "raids/east",
		"npc/scripts", "scripts/quests", "scripts/chaos", "XML", "creaturescripts"}) do
	os.execute("mkdir -p '" .. data .. "/" .. d .. "'")
end
-- sha256 of "placeholder beast", "oldboss xy", "old test mount", "unused name"
writeFile(root .. "/names.csv", "sha256,name,kind\n"
	.. "dbafe04e9269d73a1891761e14098a0c4fc742aed12a76348cd2cbb72bafad72,Ember Test Beast,monster\n"
	.. "011c571fbfdbe2208b245550a11701197876449460ec65e49b4378cb0f69f231,Grim Test Lord,monster\n"
	.. "3cf76eaffad92845368110dc08b0d922743eb6422bd90bc1126d60e5a8cab9dc,Ember Test Mount,look\n"
	.. "baedb9cb7f88a74800a0d67549a46046d2ba39d70d03a0d9e2659215c5352b5b,Never Used,monster\n")

writeFile(data .. "/monster/monsters.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<monsters>
	<monster name="Placeholder Beast" file="monsters/placeholder_beast.xml" />
	<monster name="Other Thing" file="monsters/other_thing.xml" />
	<monster name="Old Placeholder" file="monsters/stale.xml" />
	<monster name="Oldboss Xy" file="monsters/oldboss_a.xml" />
	<monster name="oldboss xy" file="monsters/oldboss_b.xml" />
	<monster name="Ember Test Beast" file="monsters/chaos/leftover.xml" />
</monsters>
]])
writeFile(data .. "/monster/monsters/placeholder_beast.xml", [[
<monster name="Placeholder Beast" nameDescription="a placeholder beast" race="blood">
	<script>
		<event name="Placeholder Beast"/>
	</script>
	<summons maxSummons="1">
		<summon name="Other Thing" interval="2000" chance="10" />
	</summons>
	<voices interval="5000" chance="10">
		<voice sentence="Placeholder Beast hungers!" />
	</voices>
	<defenses>
		<defense name="healing" interval="2000" chance="10">
			<attribute key="areaEffect" value="placeholder beast" />
		</defense>
	</defenses>
	<loot>
		<item name="dead placeholder beast" chance="100" />
	</loot>
</monster>
]])
writeFile(data .. "/monster/monsters/other_thing.xml", [[
<monster name="Other Thing" nameDescription="an other thing">
	<summons maxSummons="2">
		<summon name="placeholder beast" interval="2000" chance="10" />
	</summons>
</monster>
]])
writeFile(data .. "/monster/lua/bosses/oldboss.lua", [[
local mType = Game.createMonsterType("Oldboss Xy")
local monster = {}
monster.description = "an oldboss xy"
monster.summon = {summons = {{name = "Placeholder Beast", chance = 10, interval = 2000}}}
-- Oldboss Xy keeps this comment
mType:register(monster)
]])
local ownMonster = '<monster name="Ember Test Beast" nameDescription="placeholder beast mentions stay here" />\n'
writeFile(data .. "/monster/monsters/chaos/leftover.xml", ownMonster)
writeFile(data .. "/world/map-spawn.xml", [[
<spawns>
	<spawn centerx="100" centery="100" centerz="7" radius="3">
		<monster name="Placeholder Beast" x="0" y="0" z="7" spawntime="60" />
		<monster name="placeholder beast" x="1" y="0" z="7" spawntime="60" />
		<monster name="Other Thing" x="2" y="0" z="7" spawntime="60" />
		<monster name="Oldboss Xy" x="3" y="0" z="7" spawntime="600" lategame="Placeholder Beast" />
		<npc name="Placeholder Beast" x="4" y="0" z="7" spawntime="60" />
	</spawn>
</spawns>
]])
local house = '<houses><house name="Placeholder Beast Lane 1" houseid="1" /></houses>\n'
writeFile(data .. "/world/map-house.xml", house)
writeFile(data .. "/raids/east/oldboss.xml", [[
<raid>
	<announce delay="0" type="event" message="Oldboss Xy rises in the east!" />
	<singlespawn delay="1000" name="Oldboss Xy" x="1" y="1" z="7" />
	<areaspawn delay="2000" fromx="1" fromy="1" fromz="7" tox="5" toy="5" toz="7">
		<monster name="Placeholder Beast" amount="3" />
	</areaspawn>
</raid>
]])
writeFile(data .. "/creaturescripts/creaturescripts.xml", [[
<creaturescripts>
	<event type="death" name="Placeholder Beast" script="bosses/placeholder beast.lua" />
</creaturescripts>
]])
writeFile(data .. "/scripts/quests/boss.lua", [=[
local bossName = "Oldboss Xy"
local PlaceholderBeastStorage = Storage.PlaceholderBeast
dofile("data/monster/lua/bosses/placeholder beast.lua")
-- spawn a placeholder beast here
function spawn(pos)
	Game.createMonster('placeholder beast', pos)
	Game.createMonster("Placeholder Beasts", pos)
	player:addItem("dead placeholder beast", 1)
	player:say("You slew AN OLDBOSS XY and a placeholder beast_kills counter.")
	player:say("Grim'Oldboss Xy is another one, 'Oldboss Xy' is not.")
	return [[Placeholder Beast]]
end
]=])
writeFile(data .. "/items/items.xml", [[
<items>
	<item id="100" article="a" name="dead placeholder beast">
		<attribute key="description" value="What is left of a Placeholder Beast." />
	</item>
	<item id="101" article="a" name="placeholder beast" />
</items>
]])
writeFile(data .. "/XML/mounts.xml", [[
<mounts>
	<mount id="1" clientid="368" name="Old Test Mount" speed="20" premium="no" />
	<mount id="2" clientid="369" name="Shadow Placeholder Beast" speed="20" premium="no" />
</mounts>
]])
local quests = '<quests><quest name="The Placeholder Beast" startstorageid="1" startstoragevalue="1" /></quests>\n'
writeFile(data .. "/XML/quests.xml", quests)
local npc = "keywordHandler:addKeyword({'placeholder beast'}, StdModule.say, {npcHandler = npcHandler, text = 'Oldboss Xy!'})\n"
writeFile(data .. "/npc/scripts/talker.lua", npc)
local ours = 'local name = "Placeholder Beast" -- the repository\'s own scripts\n'
writeFile(data .. "/scripts/chaos/ours.lua", ours)

local function run(extra)
	local h = io.popen("python3 -I tools/patch_base_monster_names.py '" .. data .. "' --names '" .. root .. "/names.csv' "
		.. (extra or "") .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end

local dry = run("--dry-run")
has(dry, "dry run: nothing written", "dry run: " .. dry)
has(readFile(data .. "/world/map-spawn.xml"), '"Placeholder Beast"', "dry run writes nothing")

local out1 = run()
has(out1, "file(s) written", "first run writes: " .. out1)
has(out1, "monsters: 2 names renamed now (3 in the CSV)", "counts the names it renamed")
has(out1, "(1 duplicate lines dropped), spawn entries 3, raid spawns 2", "counts registrations, spawns, raids")
has(out1, "outfits and mounts: 1", "counts the looks")

local reg = readFile(data .. "/monster/monsters.xml")
hasnt(reg, "Placeholder Beast", "registration renamed")
has(reg, '<monster name="Other Thing" file="monsters/other_thing.xml" />', "other registrations kept")
has(reg, '<monster name="Ember Test Beast" file="monsters/chaos/leftover.xml" />', "the line that had the new name wins")
local _, regs = reg:gsub("Ember Test Beast", "")
eq(regs, 1, "a monster is registered once")
ok(reg:find('<monster name="Grim Test Lord" file="monsters/oldboss_a.xml" />', 1, true) ~= nil
	and reg:find('<monster name="Grim Test Lord" file="monsters/oldboss_b.xml" />', 1, true) ~= nil,
	"two lines that already shared a name both stay")

local beast = readFile(data .. "/monster/monsters/placeholder_beast.xml")
has(beast, '<monster name="Ember Test Beast" nameDescription="an ember test beast"', "name, description and article")
has(beast, '<event name="Ember Test Beast"/>', "event name")
has(beast, 'sentence="Ember Test Beast hungers!"', "voice")
has(beast, '<item name="dead placeholder beast"', "an item name that contains the old name is kept")
has(beast, '<attribute key="areaEffect" value="placeholder beast" />', "an effect name is the engine's")
has(readFile(data .. "/monster/monsters/other_thing.xml"), '<summon name="ember test beast"', "summon, lower case kept")

local boss = readFile(data .. "/monster/lua/bosses/oldboss.lua")
has(boss, 'Game.createMonsterType("Grim Test Lord")', "Lua monster type")
has(boss, 'monster.description = "a grim test lord"', "Lua description and article")
has(boss, '{name = "Ember Test Beast", chance = 10', "Lua summon")
has(boss, "-- Oldboss Xy keeps this comment", "comments untouched")

local spawn = readFile(data .. "/world/map-spawn.xml")
has(spawn, '<monster name="Ember Test Beast" x="0"', "spawn entry")
has(spawn, '<monster name="ember test beast" x="1"', "spawn entry in lower case")
has(spawn, '<monster name="Grim Test Lord" x="3" y="0" z="7" spawntime="600" lategame="Ember Test Beast" />',
	"spawn entry and its late game mark")
has(spawn, '<monster name="Other Thing" x="2"', "other spawns kept")
has(spawn, '<npc name="Placeholder Beast" x="4"', "an NPC of the same name keeps it")
eq(readFile(data .. "/world/map-house.xml"), house, "house file untouched")

local raid = readFile(data .. "/raids/east/oldboss.xml")
has(raid, 'message="Grim Test Lord rises in the east!"', "raid message")
has(raid, '<singlespawn delay="1000" name="Grim Test Lord"', "raid single spawn")
has(raid, '<monster name="Ember Test Beast" amount="3" />', "raid area spawn")
has(readFile(data .. "/creaturescripts/creaturescripts.xml"),
	'<event type="death" name="Ember Test Beast" script="bosses/placeholder beast.lua" />', "event renamed, path kept")

local script = readFile(data .. "/scripts/quests/boss.lua")
has(script, 'local bossName = "Grim Test Lord"', "string in a script")
has(script, "local PlaceholderBeastStorage = Storage.PlaceholderBeast", "identifiers untouched")
has(script, 'dofile("data/monster/lua/bosses/placeholder beast.lua")', "paths untouched")
has(script, "-- spawn a placeholder beast here", "comment untouched")
has(script, "Game.createMonster('ember test beast', pos)", "single-quoted string, lower case")
has(script, 'Game.createMonster("Placeholder Beasts", pos)', "a longer word is another name")
has(script, 'player:addItem("dead placeholder beast", 1)', "an item name is kept")
has(script, 'You slew A GRIM TEST LORD and a placeholder beast_kills counter.', "upper case and article, but not a key")
has(script, "return [[Ember Test Beast]]", "long string")
has(script, "Grim'Oldboss Xy is another one, 'Grim Test Lord' is not.", "a name joined by an apostrophe stays, a quoted one not")

local items = readFile(data .. "/items/items.xml")
has(items, 'name="dead placeholder beast"', "item names are for patch_base_item_names.py")
has(items, 'value="What is left of an Ember Test Beast."', "item description")
has(items, '<item id="101" article="a" name="placeholder beast" />', "an item with the old name keeps it")

local mounts = readFile(data .. "/XML/mounts.xml")
has(mounts, 'name="Ember Test Mount"', "mount by look row")
has(mounts, 'name="Shadow Ember Test Beast"', "mount named after the monster")
eq(readFile(data .. "/XML/quests.xml"), quests, "quest log untouched")
eq(readFile(data .. "/npc/scripts/talker.lua"), npc, "NPC dialogue untouched")
eq(readFile(data .. "/scripts/chaos/ours.lua"), ours, "data/scripts/chaos untouched")
eq(readFile(data .. "/monster/monsters/chaos/leftover.xml"), ownMonster, "the Chaos monster folder untouched")

-- second run: nothing to change
local paths = {"/monster/monsters.xml", "/monster/monsters/placeholder_beast.xml", "/monster/lua/bosses/oldboss.lua",
	"/world/map-spawn.xml", "/raids/east/oldboss.xml", "/scripts/quests/boss.lua", "/items/items.xml", "/XML/mounts.xml"}
local before = {}
for _, p in ipairs(paths) do
	before[p] = readFile(data .. p)
end
local out2 = run()
has(out2, "0 file(s) written", "second run: nothing written (" .. out2 .. ")")
has(out2, "monsters: 0 names renamed now", "second run: no old names left")
for _, p in ipairs(paths) do
	eq(readFile(data .. p), before[p], "second run keeps " .. p)
end

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_monster_names_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

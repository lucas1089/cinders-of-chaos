-- Run from the server/ folder: luajit tests/base_world_names_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_npc_names.py, tools/patch_base_texts.py and tools/patch_base_houses.py on a small base data folder
-- written here. The lists key every old name by its sha256 (lower case); the fixture names are placeholders.
-- NPC files, shown names, spawn entries and Game.createNpc names; dialogue, keywords, travel, quest log, raids,
-- achievements, item descriptions and the map's item texts; house names by id; quotes escaped for their Lua string;
-- paths, identifiers, comments, item names and the repository's own files untouched; a second run changes nothing.
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
	print("base_world_names_patch_test: python3 not found, skipped")
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
local function exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
	end
	return f ~= nil
end

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
for _, d in ipairs({"npc/scripts", "world", "raids/east", "XML", "items", "lib/core", "scripts/chaos", "monster",
		"spells"}) do
	os.execute("mkdir -p '" .. data .. "/" .. d .. "'")
end

-- old names: "grumtest", "oldname vex", "oldname vexdock" (a file name), "copper" (an English word), "ferry olden", "olden",
-- "oldtown xy", "ab'testra", "oldgod", "oldtowner", "placeholder beast"
writeFile(root .. "/npc.csv", "sha256,name,kind,match\n"
	.. "91ca353caf62b0efcfe1878d15784cbddfb4b64ff0eb6fe59bf135ec21ee7691,Kesra Test,npc,word\n"
	.. "36126d7157fd50ce30d30a604ee07ebedd49298cfa995e886f8f10fb2b232fee,Kesra Testdock,file,word\n"
	.. "d16f06fe255d801e0639b8d749b815ea9e788af7b9ceba2b773c1dbc8f080442,Brindle,npc,cap\n"
	.. "8737f1f12cd31bce513f990e1996359b33b468822337fed7f70b8ca4ab82f3d8,Ferry Ashtest,npc,word\n"
	.. "2f94e5ec2e5fcf8cafbed28ddb7c7560a2fd5b1976e29ed561cf9f28680fcb69,Ashtest,npc,word\n"
	.. "184451420dd063f9f88b1292f0d779c343ec14905281cce9246fdb89e309685f,Grumnew,npc,word\n")
writeFile(root .. "/world.csv", "sha256,name,kind,match\n"
	.. "7b474e2f2f687b2b15cc4b2554eadc3b7e573d038824c151334ce2f41004c1aa,Embertest,town,word\n"
	.. "6651f1d8a403214cd5ea1590feafbcf424fe65dba998619f20ac2d14d31172a2,Testgloom,place,word\n"
	.. "008f6bc279134ae8bea9a67d3a5f2f82eb25064a03ed2cf373235af37268dc41,the Tester,god,word\n"
	.. "648639d746a6db964ee9da969f9fe422354323c2723847b7b260bf21426a21c2,O'Testfolk,demonym,word\n"
	.. "ff627b684246e47dfbfc0b63166e1125fc9e80e1fdb1f3d32ae7afadf2b7b35a,Gloomtest,person,word\n"
	.. "f0dd58ff085f09a0cea80da67e2bbc8f5383f7462989ae1ef0d4b643f3714fa6,Duskrow,person,word\n")
writeFile(root .. "/monster.csv", "sha256,name,kind\n"
	.. "dbafe04e9269d73a1891761e14098a0c4fc742aed12a76348cd2cbb72bafad72,Ember Test Beast,monster\n")
writeFile(root .. "/houses.csv", "id,name\n1,Tallow Test Row 1\n2,\"Tallow Test Row 2, Flat\"\n")

writeFile(data .. "/npc/Oldname Vex.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<npc name="Oldname Vex" script="Oldname Vex.lua" walkinterval="2000">
	<parameters>
		<parameter key="message_greet" value="Hello |PLAYERNAME|, welcome to Oldtown Xy. Copper and Olden are friends." />
		<parameter key="keywords" value="job;copper;oldtown xy;" />
	</parameters>
</npc>
]])
writeFile(data .. "/npc/Oldname VexDock.xml", '<npc name="Oldname Vex" script="dock.lua" />\n')
writeFile(data .. "/npc/Copper.xml", '<npc name="Copper" script="copper.lua" />\n')
writeFile(data .. "/npc/Ferry Olden.xml", '<npc name="Ferry Olden" script="travel.lua" />\n')
local ownNpc = '<npc name="Material Broker" script="material_broker.lua">Oldtown Xy</npc>\n'
writeFile(data .. "/npc/Material Broker.xml", ownNpc)
local travel = [=[
-- Oldtown Xy travel, a comment that stays
local OldtownXy = Storage.OldtownXy
addTravelKeyword('oldtown xy', 'Do you seek a passage to Oldtown Xy for 10 gold?', 10, Position(1, 1, 7))
npcHandler:say("Olden says hi. Copper coins are copper. He sent me", cid)
keywordHandler:addKeyword({'copper sent me'}, StdModule.say, {npcHandler = npcHandler, text = 'Ask Copper.'})
local a = 'Oldgod watches. Pray to Oldgod, and the oldgod hears.'
local b = 'You found an Ab\'Testra relic, a Oldtowner blade and a placeholder beast.'
local c = "We are Oldtowner folk."
local d = [[Oldtown Xy]]
dofile("data/npc/scripts/oldtown xy/helper.lua")
Game.createNpc("Oldname VexDock", Position(1, 1, 7))
Game.createNpc("Copper", Position(1, 1, 7))
spell:words("drai copper")
local towns = {{name = 'Oldtown Xy', mapName = 'oldtown xy'}}
]=]
writeFile(data .. "/npc/scripts/travel.lua", travel)
writeFile(data .. "/world/map-spawn.xml", [[
<spawns>
	<spawn centerx="100" centery="100" centerz="7" radius="3">
		<npc name="Oldname Vex" x="0" y="0" z="7" spawntime="60" />
		<npc name="Oldname VexDock" x="1" y="0" z="7" spawntime="60" />
		<npc name="Copper" x="2" y="0" z="7" spawntime="60" />
		<monster name="Placeholder Beast" x="3" y="0" z="7" spawntime="60" />
	</spawn>
</spawns>
]])
writeFile(data .. "/world/map-house.xml", [[
<houses>
	<house name="Oldtown Xy Lane 1" houseid="1" entryx="1" entryy="1" entryz="7" rent="10" townid="1" size="9" />
	<house name="Oldtown Xy Lane 2, Flat" houseid="2" entryx="2" entryy="1" entryz="7" rent="10" townid="1" size="9" />
	<house name="Oldtown Xy Lane 3" houseid="3" entryx="3" entryy="1" entryz="7" rent="10" townid="1" size="9" />
</houses>
]])
writeFile(data .. "/raids/east/raid.xml", '<raid><announce delay="0" type="event" message="Oldtown Xy is under attack!" /></raid>\n')
writeFile(data .. "/XML/quests.xml", [[
<quests>
	<quest name="The Oldtown Xy Errand" startstorageid="1" startstoragevalue="1">
		<mission name="Mission 1" storageid="2" startvalue="1" endvalue="2">
			<missionstate id="1" description="Ask Copper in Oldtown Xy about Ab'Testra." />
			<missionstate id="2" description="Bring olden to Olden." />
		</mission>
	</quest>
</quests>
]])
writeFile(data .. "/items/items.xml", [[
<items>
	<item id="101" article="an" name="olden" />
	<item id="100" article="an" name="oldtown xy sword">
		<attribute key="description" value="Forged in Oldtown Xy." />
	</item>
</items>
]])
writeFile(data .. "/monster/monsters.xml",
	'<monsters><monster name="Copper Golem" file="x.xml" /><monster name="Vexmaw" file="v.xml" /></monsters>\n')
-- raid spawn names are monster type names: "Vexmaw" is a registered monster, "Zapholdt" is not found by the tool (a
-- raid boss defined where the tool does not look), both stay in the spawn tags; the messages of the second are renamed
writeFile(data .. "/raids/east/boss.xml", '<raid><announce message="Zapholdt rises!" /><singlespawn name="Zapholdt" x="1" y="2" z="7" />'
	.. '<areaspawn fromx="1" fromy="1" fromz="7" tox="2" toy="2" toz="7"><monster name="Zapholdt" minamount="1" maxamount="2" /></areaspawn></raid>\n')
-- left by an older run: the spawn was renamed although the monster Vexmaw exists
writeFile(data .. "/raids/east/damaged.xml", '<raid><singlespawn name="Gloomtest" x="1" y="2" z="7" />'
	.. '<areaspawn fromx="1" fromy="1" fromz="7" tox="2" toy="2" toz="7"><monster name="gloomtest" minamount="1" maxamount="2" /></areaspawn>'
	.. '<singlespawn name="Duskrow" x="3" y="2" z="7" /></raid>\n')
local effect = '<monster name="Copper Golem"><attribute key="areaEffect" value="placeholder beast" /></monster>\n'
writeFile(data .. "/monster/x.xml", effect)
os.execute("mkdir -p '" .. data .. "/monster/lua'")
local spawnLua = 'local boss = Game.createMonster("Zapholdt", Position(1, 1, 7))\nlocal say = "Zapholdt rises"\n'
writeFile(data .. "/lib/core/spawnboss.lua", spawnLua)
local luaMonster = 'local mType = Game.createMonsterType("Grumtest")\nmonster.voices = {{text = "Grumtest smashes!"}}\n'
writeFile(data .. "/monster/lua/grumtest.lua", luaMonster)
writeFile(data .. "/lib/core/achievements.lua",
	'achievements = {[1] = {name = "Oldtown Xy Hero", description = "You saved Oldtown Xy and met Copper Golem."}}\n')
writeFile(data .. "/XML/mounts.xml", '<mounts><mount id="1" name="Crimson Copper" /><mount id="2" name="Oldtown Xy Strider" /></mounts>\n')
writeFile(data .. "/raids/east/title.xml", "<raid><announce message=\"Courier Copper is missing.\" /></raid>\n")
writeFile(data .. "/spells/spells.xml", '<spells><instant name="Oldtown Xy Light" words="drai copper" /></spells>\n')
local ours = 'local town = "Oldtown Xy" -- the repository\'s own scripts\n'
writeFile(data .. "/scripts/chaos/ours.lua", ours)

-- a small map: root node, three item nodes with texts (one with an escaped byte, one with an unknown attribute)
local function u16(n)
	return string.char(n % 256, math.floor(n / 256))
end
local function textAttr(s)
	return "\6" .. u16(#s) .. s
end
local map = "\0\0\0\0" .. "\254\0" .. "head"
	.. "\254\6" .. u16(10000) .. textAttr("Welcome to Oldtown Xy!") .. "\255"
	.. "\254\6" .. u16(10001) .. "\4\253\254\0" .. textAttr("Oldgod rests here.") .. "\255"
	.. "\254\6" .. u16(10002) .. "\99\0\0" .. textAttr("Oldtown Xy unknown") .. "\255"
	.. "\254\6" .. u16(10003) .. "\255"
	.. "\255"
writeFile(data .. "/world/map.otbm", map)

local function tool(name, args)
	local h = io.popen("python3 -I tools/" .. name .. " '" .. data .. "' " .. args .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end
local npcArgs = "--names '" .. root .. "/npc.csv'"
local textArgs = "--names '" .. root .. "/world.csv' --npc-names '" .. root .. "/npc.csv' --monster-names '"
	.. root .. "/monster.csv'"
local houseArgs = "--names '" .. root .. "/houses.csv'"

-- dry runs write nothing
has(tool("patch_base_npc_names.py", npcArgs .. " --dry-run"), "dry run: nothing written", "NPC dry run")
has(tool("patch_base_texts.py", textArgs .. " --dry-run"), "dry run: nothing written", "texts dry run")
has(tool("patch_base_houses.py", houseArgs .. " --dry-run"), "dry run", "houses dry run")
ok(exists(data .. "/npc/Oldname Vex.xml"), "dry run keeps the files")
eq(readFile(data .. "/npc/scripts/travel.lua"), travel, "dry run keeps the scripts")
eq(readFile(data .. "/world/map.otbm"), map, "dry run keeps the map")

-- NPC names
local out = tool("patch_base_npc_names.py", npcArgs)
has(out, "npcs: 4 file(s) renamed, 4 shown name(s) changed, 3 spawn entries, 2 Lua reference(s)", "NPC counts: " .. out)
ok(not exists(data .. "/npc/Oldname Vex.xml") and exists(data .. "/npc/Kesra Test.xml"), "file renamed by the shown name")
ok(exists(data .. "/npc/Kesra Testdock.xml"), "file renamed by its file name row")
ok(exists(data .. "/npc/Brindle.xml") and exists(data .. "/npc/Ferry Ashtest.xml"), "other files renamed")
has(readFile(data .. "/npc/Kesra Test.xml"), '<npc name="Kesra Test" script="Oldname Vex.lua"', "shown name, script path kept")
has(readFile(data .. "/npc/Kesra Testdock.xml"), '<npc name="Kesra Test" script="dock.lua"', "second file of one NPC")
eq(readFile(data .. "/npc/Material Broker.xml"), ownNpc, "the repository's NPCs are skipped")
local spawn = readFile(data .. "/world/map-spawn.xml")
has(spawn, '<npc name="Kesra Test" x="0"', "spawn entry")
has(spawn, '<npc name="Kesra Testdock" x="1"', "spawn entry by file name")
has(spawn, '<npc name="Brindle" x="2"', "spawn entry of a common-word name")
has(spawn, '<monster name="Placeholder Beast"', "monster spawns are not this tool's")

-- texts
out = tool("patch_base_texts.py", textArgs)
has(out, "map: 2 item text(s) rewritten", "map counts: " .. out)
has(out, "raids: 2 spawn name(s) put back", "raid repair count: " .. out)
local t = readFile(data .. "/npc/scripts/travel.lua")
has(t, "-- Oldtown Xy travel, a comment that stays", "comments untouched")
has(t, "local OldtownXy = Storage.OldtownXy", "identifiers untouched")
has(t, "addTravelKeyword('embertest', 'Do you seek a passage to Embertest for 10 gold?'", "travel keyword and text")
has(t, '"Ashtest says hi. Brindle coins are copper. He sent me"', "NPC names; a common word only when capitalized")
has(t, "{'brindle sent me'}", "a lower-case keyword phrase follows the new name")
has(t, "text = 'Ask Brindle.'", "single-quoted text")
has(t, "'The Tester watches. Pray to the Tester, and the tester hears.'", "'the' names: capitalized, not doubled")
has(t, "'You found a Testgloom relic, an O\\'Testfolk blade and an ember test beast.'",
	"escaped apostrophe found, article fixed, new apostrophe escaped, monster names")
has(t, '"We are O\'Testfolk folk."', "double-quoted string keeps a plain apostrophe")
has(t, "local d = [[Embertest]]", "long string")
has(t, 'dofile("data/npc/scripts/oldtown xy/helper.lua")', "paths untouched")
has(t, 'Game.createNpc("Kesra Testdock", Position(1, 1, 7))', "Game.createNpc by file name")
has(t, 'Game.createNpc("Brindle", Position(1, 1, 7))', "Game.createNpc of a common word")
ok((loadstring or load)(t) ~= nil, "the patched NPC script parses")
has(t, 'spell:words("drai copper")', "spell words in Lua stay")
has(t, "{{name = 'Embertest', mapName = 'oldtown xy'}}", "a file or map name key keeps its value")
has(readFile(data .. "/spells/spells.xml"), 'name="Embertest Light" words="drai copper"', "spell words in XML stay")
local x = readFile(data .. "/npc/Kesra Test.xml")
has(x, 'value="Hello |PLAYERNAME|, welcome to Embertest. Brindle and Ashtest are friends."', "XML dialogue")
has(x, 'value="job;brindle;embertest;"', "XML keywords")
eq(readFile(data .. "/npc/Material Broker.xml"), ownNpc, "the repository's NPCs untouched by texts")
has(readFile(data .. "/raids/east/raid.xml"), 'message="Embertest is under attack!"', "raid message")
has(readFile(data .. "/lib/core/spawnboss.lua"), 'Game.createMonster("Zapholdt", Position', "createMonster name stays")
has(readFile(data .. "/lib/core/spawnboss.lua"), 'local say = "Duskrow rises"', "other strings are renamed")
local boss = readFile(data .. "/raids/east/boss.xml")
has(boss, '<singlespawn name="Zapholdt" x="1"', "raid spawn name stays")
has(boss, '<monster name="Zapholdt" minamount', "raid area spawn name stays")
has(boss, 'message="Duskrow rises!"', "raid message is renamed")
local dmg = readFile(data .. "/raids/east/damaged.xml")
has(dmg, '<singlespawn name="Vexmaw" x="1"', "a renamed spawn is put back")
has(dmg, '<monster name="Vexmaw" minamount', "a renamed area spawn is put back")
has(dmg, '<singlespawn name="Duskrow" x="3"', "a replacement name no hash of a monster gives stays")
local q = readFile(data .. "/XML/quests.xml")
has(q, 'name="The Embertest Errand"', "quest name")
has(q, 'description="Ask Brindle in Embertest about Testgloom."', "mission text")
has(q, 'description="Bring olden to Ashtest."', "an item name that is also a person: the person where capitalized")
local it = readFile(data .. "/items/items.xml")
has(it, 'name="oldtown xy sword"', "item names are kept")
has(it, 'value="Forged in Embertest."', "item description")
has(readFile(data .. "/XML/mounts.xml"), 'name="Crimson Copper" /><mount id="2" name="Embertest Strider"',
	"a common-word name inside a title-case name stays, a place is renamed")
has(readFile(data .. "/raids/east/title.xml"), 'message="Courier Brindle is missing."', "in prose a title before the name")
has(readFile(data .. "/lib/core/achievements.lua"),
	'name = "Embertest Hero", description = "You saved Embertest and met Copper Golem."', "achievement; a monster name kept")
eq(readFile(data .. "/scripts/chaos/ours.lua"), ours, "data/scripts/chaos untouched")
eq(readFile(data .. "/monster/x.xml"), effect, "engine effect names stay")
eq(readFile(data .. "/monster/lua/grumtest.lua"), luaMonster, "a monster that has an old NPC's name keeps it")
local m = readFile(data .. "/world/map.otbm")
has(m, "\254\6" .. u16(10000) .. textAttr("Welcome to Embertest!") .. "\255", "map text and its length")
has(m, "\254\6" .. u16(10001) .. "\4\253\254\0" .. textAttr("The Tester rests here.") .. "\255", "escaped byte kept")
has(m, "\99\0\0" .. textAttr("Oldtown Xy unknown"), "a node with an unknown attribute is left alone")
ok(exists(data .. "/world/map.otbm.bak") and readFile(data .. "/world/map.otbm.bak") == map, "map backup")

-- houses
out = tool("patch_base_houses.py", houseArgs)
has(out, "houses: 2 renamed of 3", "house counts: " .. out)
has(out, "houses without a row (name kept): 3", "a house without a row is listed")
local h = readFile(data .. "/world/map-house.xml")
has(h, '<house name="Tallow Test Row 1" houseid="1" entryx="1"', "house renamed by id")
has(h, '<house name="Tallow Test Row 2, Flat" houseid="2"', "a name with a comma")
has(h, '<house name="Oldtown Xy Lane 3" houseid="3"', "a house without a row keeps its name")

-- second runs: nothing to change
local snap = {}
local files = {"/npc/scripts/travel.lua", "/npc/Kesra Test.xml", "/world/map-spawn.xml", "/world/map.otbm",
	"/world/map-house.xml", "/XML/quests.xml", "/items/items.xml", "/raids/east/raid.xml", "/raids/east/boss.xml", "/raids/east/damaged.xml"}
for _, p in ipairs(files) do
	snap[p] = readFile(data .. p)
end
has(tool("patch_base_npc_names.py", npcArgs), "npcs: 0 file(s) renamed, 0 shown name(s) changed, 0 spawn entries",
	"second NPC run")
has(tool("patch_base_texts.py", textArgs), "0 replacement(s) in 0 file(s)", "second texts run")
has(tool("patch_base_houses.py", houseArgs), "nothing to change", "second houses run")
for _, p in ipairs(files) do
	eq(readFile(data .. p), snap[p], "second run keeps " .. p)
end

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_world_names_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

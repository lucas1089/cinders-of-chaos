-- Run from the server/ folder: luajit tests/base_spawns_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_spawns.py on a small data folder written here (placeholder monsters, a spawn file and a tuning
-- JSON): glitched spawntimes take the monster's usual one, the band respawn shortens only that band's timers (not
-- rare ones, bosses or other bands), entries move, are removed and added by position (the added monster and spawntime
-- copied from the entry at `like`), late_game.py's markers stay; a second run changes nothing, --remove gives the
-- stock file back byte for byte (also with CRLF line ends), bad positions are reported with exit status 1, --report
-- prints the band table. The fill file (tools/spawn_density.json, by gen_spawn_density.py) adds spawns per hunt
-- with the monster and final spawntime of a like entry.
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
	print("base_spawns_patch_test: python3 not found, skipped")
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
local function count(text, pattern)
	local n = 0
	for _ in text:gmatch(pattern) do
		n = n + 1
	end
	return n
end

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
for _, d in ipairs({"world", "monster/monsters"}) do
	os.execute("mkdir -p '" .. data .. "/" .. d .. "'")
end
writeFile(root .. "/config.lua", 'mapName = "testmap"\nrateSpawn = 1\n')

-- placeholder monsters: low (hunting level ~32), mid (~404, in the 300-600 band), a level-scaled high one (720),
-- a boss with mid experience, and a rare one with too few spawns for the glitch rule
local monsters = {
	{"Test Low", "test_low", 'experience="100"', '<health now="200" max="200"/>', ""},
	{"Test Mid", "test_mid", 'experience="16000"', '<health now="10000" max="10000"/>', ""},
	{"Test High", "test_high", 'experience="13000"', '<health now="13000" max="13000"/>', '<level min="700" max="740"/>'},
	{"Test Boss", "test_boss", 'experience="16000"', '<health now="10000" max="10000"/>',
		'<flags><flag isboss="1"/></flags>'},
	{"Test Rare", "test_rare", 'experience="100"', '<health now="200" max="200"/>', ""},
}
local reg = {'<?xml version="1.0" encoding="UTF-8"?>', "<monsters>"}
for _, m in ipairs(monsters) do
	reg[#reg + 1] = string.format('\t<monster name="%s" file="monsters/%s.xml" />', m[1], m[2])
	writeFile(data .. "/monster/monsters/" .. m[2] .. ".xml", string.format(
		'<?xml version="1.0" encoding="UTF-8"?>\n<monster name="%s" race="blood" %s speed="200">\n\t%s\n\t%s\n</monster>\n',
		m[1], m[3], m[4], m[5]))
end
-- the base server's duplicate lines: a wrong-case first line (the engine keeps the first line of a name, its file is
-- missing on Linux) before a good one; a missing file without a good line; a stock comment
writeFile(data .. "/monster/monsters/test_dead.xml", '<?xml version="1.0" encoding="UTF-8"?>\n' ..
	'<monster name="Test Dead" race="blood" experience="100" speed="200">\n\t<health now="200" max="200"/>\n</monster>\n')
table.insert(reg, 3, '\t<monster name="Test Dead" file="monsters/Test_Dead.xml" />')
reg[#reg + 1] = '\t<monster name="Test Dead" file="monsters/test_dead.xml" />'
reg[#reg + 1] = '\t<monster name="Test Gone" file="monsters/test_gone.xml" />'
reg[#reg + 1] = '\t<!-- <monster name="Test Low" file="monsters/old_low.xml" /> -->'
reg[#reg + 1] = "</monsters>"
local regStock = table.concat(reg, "\n") .. "\n"
local regPath = data .. "/monster/monsters.xml"
writeFile(regPath, regStock)

local stock = [[
<?xml version="1.0"?>
<spawns>
	<spawn centerx="1000" centery="1000" centerz="7" radius="3">
		<monster name="Test Low" x="0" y="0" z="7" spawntime="60" />
		<monster name="Test Low" x="1" y="0" z="7" spawntime="60" />
		<monster name="Test Low" x="2" y="0" z="7" spawntime="60" />
		<monster name="Test Low" x="-1" y="2" z="7" spawntime="31488" />
		<monster name="Test Rare" x="0" y="3" z="7" spawntime="60" />
		<monster name="Test Rare" x="1" y="3" z="7" spawntime="32000" />
	</spawn>
	<spawn centerx="2000" centery="2000" centerz="8" radius="2">
		<monster name="Test Mid" x="0" y="0" z="8" spawntime="120" />
		<monster name="Test Mid" x="2" y="1" z="8" spawntime="120" />
		<monster name="Test Mid" x="-2" y="1" z="8" spawntime="60" />
		<monster name="Test Mid" x="1" y="-2" z="8" spawntime="900" />
		<monster name="Test Boss" x="0" y="2" z="8" spawntime="120" />
		<npc name="Test Merchant" x="0" y="-1" z="8" />
	</spawn>
	<spawn centerx="3000" centery="3000" centerz="9" radius="1">
		<monster name="Test High" x="0" y="0" z="9" spawntime="120" lategame="Test Low" />
	</spawn>
	<spawn centerx="3010" centery="3000" centerz="9" radius="1">
		<monster name="Test Low" x="0" y="0" z="9" spawntime="60"/>
	</spawn>
	<spawn centerx="4000" centery="4000" centerz="7" radius="1">
		<monster name="Test Low" x="0" y="0" z="7" spawntime="60" />
	</spawn>
</spawns>
]]
local spawnPath = data .. "/world/testmap-spawn.xml"
writeFile(spawnPath, stock)

local tuning = [[
{
  "fixDeadRegistrations": true,
  "huntLevelFactor": 2.0,
  "glitchSpawntime": {"min": 30000, "minOthers": 3},
  "bandRespawn": [{"from": 300, "to": 600, "spawntime": 90, "onlyUpTo": 300}],
  "areas": [{"id": "T-01", "box": [1990, 1990, 8, 2010, 2010, 8], "band": "300-600", "note": "test"}],
  "move": [{"at": [2002, 2001, 8], "to": [2003, 2003]}, {"at": [3010, 3000, 9], "to": [3011, 3001]}],
  "remove": [{"at": [1002, 1000, 7]}, {"at": [4000, 4000, 7]}],
  "fill": "fill.json",
  "add": [
    {"area": "T-01", "at": [2005, 2005, 8], "like": [2000, 2000, 8]},
    {"area": "T-01", "at": [2006, 2004, 8], "like": [1998, 2001, 8], "radius": 1}
  ]
}
]]
local tuningPath = root .. "/tuning.json"
writeFile(tuningPath, tuning)
writeFile(root .. "/fill.json", [==[
{"areas": [
  {"id": "F0001", "z": 7, "likes": [[1000, 1000], [999, 1002]], "add": [[1004, 1004, 0], [996, 1006, 1]]},
  {"id": "F0002", "z": 8, "likes": [[2000, 2000]], "add": [[1995, 1996, 0]]},
  {"id": "F0003", "z": 8, "likes": [[2000, 2000]], "add": [[1990, 1990, 0, 1, 0, 0, 1]]}
]}
]==])

local tool = "tools/patch_base_spawns.py"
local function run(args)
	local p = io.popen("python3 -I " .. tool .. " '" .. data .. "' --tuning '" .. tuningPath .. "' " .. (args or "") ..
		" 2>&1; echo \"rc=$?\"")
	local out = p:read("*a")
	p:close()
	return out, tonumber(out:match("rc=(%d+)"))
end

-- ------------------------------------------------------------------ first run
local out, rc = run("")
eq(rc, 0, "first run ok: " .. out)
ok(out:find("written", 1, true) ~= nil, "first run writes")
ok(out:find("1 glitch", 1, true) ~= nil, "one glitched spawntime fixed (the rare one has too few others)")
ok(out:find("2 band", 1, true) ~= nil, "two band respawns")
ok(out:find("2 moved", 1, true) ~= nil and out:find("2 removed", 1, true) ~= nil and out:find("1 emptied", 1, true) ~= nil and out:find("2 added", 1, true) ~= nil,
	"moves, removal, adds counted")
ok(out:find("6 filled", 1, true) ~= nil, "fill monsters counted (a block of 3 counts 3)")
local reg1 = readFile(regPath)
ok(out:find("1 dead first line(s) commented out: Test Dead", 1, true) ~= nil, "dead registration reported")
ok(reg1:find('<!-- chaosdeadreg: <monster name="Test Dead" file="monsters/Test_Dead.xml" /> -->', 1, true) ~= nil,
	"the dead first line is commented out")
ok(reg1:find('\t<monster name="Test Dead" file="monsters/test_dead.xml" />', 1, true) ~= nil, "the good line stays")
ok(reg1:find('\t<monster name="Test Gone" file="monsters/test_gone.xml" />', 1, true) ~= nil,
	"a missing file without a good line: left for the engine's own warning")
ok(reg1:find('\t<!-- <monster name="Test Low" file="monsters/old_low.xml" /> -->', 1, true) ~= nil, "stock comments stay")
local text = readFile(spawnPath)
ok(text:find('<monster chaosst="31488" name="Test Low" x="-1" y="2" z="7" spawntime="60" />', 1, true) ~= nil,
	"glitch -> the monster's usual spawntime, old value kept")
ok(text:find('<monster name="Test Rare" x="1" y="3" z="7" spawntime="32000" />', 1, true) ~= nil,
	"too few other entries: left alone")
ok(text:find('<monster chaosst="120" name="Test Mid" x="0" y="0" z="8" spawntime="90" />', 1, true) ~= nil,
	"band entry 120 -> 90")
ok(text:find('<monster name="Test Mid" x="-2" y="1" z="8" spawntime="60" />', 1, true) ~= nil,
	"already faster than the band: unchanged")
ok(text:find('<monster name="Test Mid" x="1" y="-2" z="8" spawntime="900" />', 1, true) ~= nil,
	"a rare spawn above onlyUpTo: unchanged")
ok(text:find('<monster name="Test Boss" x="0" y="2" z="8" spawntime="120" />', 1, true) ~= nil, "bosses: unchanged")
ok(text:find('<monster name="Test High" x="0" y="0" z="9" spawntime="120" lategame="Test Low" />', 1, true) ~= nil,
	"other band and late_game.py's marker: unchanged")
ok(text:find('<monster chaosxy="2,1" chaosst="120" name="Test Mid" x="3" y="3" z="8" spawntime="90" />', 1, true) ~= nil,
	"moved (offsets from the spawn centre) and band respawn on the same entry")
ok(text:find('<monster chaosxy="0,0" name="Test Low" x="1" y="1" z="9" spawntime="60"/>', 1, true) ~= nil,
	"moved, the tag's own format kept")
ok(text:find('<!-- chaosremoved: <monster name="Test Low" x="2" y="0" z="7" spawntime="60" /> -->', 1, true) ~= nil,
	"removed as a comment")
-- a stock spawn left without an entry: the whole block becomes one comment (the engine warns "Empty spawn")
ok(text:find('\t<!-- chaosemptied: <spawn centerx="4000" centery="4000" centerz="7" radius="1">\n' ..
	'\t\t<monster name="Test Low" x="0" y="0" z="7" spawntime="60" />\n\t</spawn> -->\n', 1, true) ~= nil,
	"an emptied spawn: the stock block as one comment")
ok(text:find('<!-- chaosremoved: <monster name="Test Low" x="0" y="0" z="7" spawntime="60" /> -->\n\t</spawn>', 1, true)
	== nil, "no <spawn> left with only a removed entry")
ok(text:find('<spawn centerx="2005" centery="2005" centerz="8" radius="2" chaosadd="T-01">\n' ..
	'\t\t<monster name="Test Mid" x="0" y="0" z="8" spawntime="90" />\n\t</spawn>', 1, true) ~= nil,
	"added: the monster and the final spawntime of the entry at like")
ok(text:find('<spawn centerx="2006" centery="2004" centerz="8" radius="1" chaosadd="T-01">\n' ..
	'\t\t<monster name="Test Mid" x="0" y="0" z="8" spawntime="60" />', 1, true) ~= nil, "second add, own radius")
ok(text:find('<npc name="Test Merchant"', 1, true) ~= nil, "NPCs untouched")
ok(text:find("</spawn>\n</spawns>\n$") ~= nil, "added before </spawns>")
ok(text:find('<spawn centerx="1004" centery="1004" centerz="7" radius="2" chaosadd="F0001">\n' ..
	'\t\t<monster name="Test Low" x="0" y="0" z="7" spawntime="60" />', 1, true) ~= nil, "fill: copies the like entry")
ok(text:find('<spawn centerx="996" centery="1006" centerz="7" radius="2" chaosadd="F0001">\n' ..
	'\t\t<monster name="Test Low" x="0" y="0" z="7" spawntime="60" />', 1, true) ~= nil,
	"fill: the final spawntime of a glitched like entry (31488 -> 60)")
ok(text:find('<spawn centerx="1995" centery="1996" centerz="8" radius="2" chaosadd="F0002">\n' ..
	'\t\t<monster name="Test Mid" x="0" y="0" z="8" spawntime="90" />', 1, true) ~= nil,
	"fill: the band respawn of the like entry")
eq(count(text, "<spawn "), 11, "five stock spawns (one of them commented out), two added, four filled")
eq(count(text, "\n\t<spawn "), 10, "four live stock spawns, two added, four filled")
ok(text:find('<spawn centerx="1990" centery="1990" centerz="8" radius="2" chaosadd="F0003">\n' ..
	'\t\t<monster name="Test Mid" x="0" y="0" z="8" spawntime="90" />\n' ..
	'\t\t<monster name="Test Mid" x="1" y="0" z="8" spawntime="90" />\n' ..
	'\t\t<monster name="Test Mid" x="0" y="1" z="8" spawntime="90" />\n\t</spawn>', 1, true) ~= nil,
	"fill: a block of 3 (the pack fill)")

-- ------------------------------------------------------------------ idempotent, report, remove
local first = text
out, rc = run("--report")
eq(rc, 0, "second run ok")
ok(out:find("unchanged", 1, true) ~= nil, "second run: unchanged")
eq(readFile(spawnPath), first, "second run: same bytes")
eq(readFile(regPath), reg1, "second run: monsters.xml the same")
ok(out:find("| Band | Spawn blocks | Monsters |", 1, true) ~= nil, "report table")
ok(out:find("| 300-600 | 5 | 10 |", 1, true) ~= nil, "report: the mid band (the stock block, two added, one filled, a block of 3)")
-- blocks another tool appended after ours (install_content_areas.py: chaoscontent / chaoshunt) stay after them
local later = '\t<spawn centerx="3000" centery="3000" centerz="7" radius="1" chaoscontent="P1">\n' ..
	'\t\t<monster name="Test Mid" x="0" y="0" z="7" spawntime="60" />\n\t</spawn>\n' ..
	-- a display monster keeps its own spawntime (120 s would be the band's 90 s otherwise)
	'\t<spawn centerx="3002" centery="3000" centerz="7" radius="1" chaoshunt="P1">\n' ..
	'\t\t<monster name="Test Mid" x="0" y="0" z="7" spawntime="120" />\n\t</spawn>\n'
local withLater = first:gsub("</spawns>", function() return later .. "</spawns>" end)
writeFile(spawnPath, withLater)
out, rc = run("")
ok(out:find("unchanged", 1, true) ~= nil, "a content block after ours: unchanged (" .. out .. ")")
eq(readFile(spawnPath), withLater, "a content block after ours keeps its place, a display monster its spawntime")
writeFile(spawnPath, first)
out, rc = run("--dry-run --remove")
eq(readFile(spawnPath), first, "dry run writes nothing")
out, rc = run("--remove")
eq(rc, 0, "remove ok")
eq(readFile(spawnPath), stock, "remove: the stock file byte for byte")
eq(readFile(regPath), regStock, "remove: monsters.xml byte for byte")
out, rc = run("--remove")
ok(out:find("unchanged", 1, true) ~= nil, "remove twice: unchanged")

-- ------------------------------------------------------------------ a list of fill files (spawn_expand.json: fills and removals)
do
	writeFile(spawnPath, stock)
	writeFile(root .. "/expand.json", [==[
{"areas": [{"id": "XW01", "z": 8, "likes": [[2000, 2000]], "add": [[2008, 2008, 0, 1, 0]]}], "remove": [[2001, 1998, 8]]}
]==])
	local t2 = tuning:gsub('"fill": "fill.json",', '"fill": ["fill.json", "expand.json"],')
	local tp2 = root .. "/tuning2.json"
	writeFile(tp2, t2)
	local p = io.popen("python3 -I " .. tool .. " '" .. data .. "' --tuning '" .. tp2 .. "' 2>&1; echo \"rc=$?\"")
	local o = p:read("*a")
	p:close()
	ok(o:find("rc=0", 1, true) ~= nil, "the list of fill files: ok " .. o)
	local txt = readFile(spawnPath)
	ok(txt:find('chaosadd="XW01"', 1, true) ~= nil, "the second file's area is added (a block of 2)")
	ok(txt:find('<!-- chaosremoved: <monster name="Test Mid" x="1" y="-2" z="8" spawntime="900" /> -->', 1, true) ~= nil,
		"an entry of the second file's remove list is taken out like a tuning remove")
	p = io.popen("python3 -I " .. tool .. " '" .. data .. "' --tuning '" .. tp2 .. "' 2>&1")
	o = p:read("*a")
	p:close()
	ok(o:find("unchanged", 1, true) ~= nil, "the list of fill files: a second run changes nothing (" .. o .. ")")
	p = io.popen("python3 -I " .. tool .. " '" .. data .. "' --tuning '" .. tp2 .. "' --remove 2>&1")
	p:read("*a")
	p:close()
	eq(readFile(spawnPath), stock, "the list of fill files: --remove gives the stock file back byte for byte")
	writeFile(spawnPath, first)
end

-- ------------------------------------------------------------------ CRLF files
local crlf = stock:gsub("\n", "\r\n")
writeFile(spawnPath, crlf)
out, rc = run("")
eq(rc, 0, "CRLF run ok")
text = readFile(spawnPath)
ok(text:find('chaosadd="T-01">\r\n\t\t<monster name="Test Mid"', 1, true) ~= nil, "CRLF: added blocks use CRLF")
ok(not text:find("[^\r]\n"), "CRLF: no bare LF")
out, rc = run("")
ok(out:find("unchanged", 1, true) ~= nil, "CRLF: second run unchanged")
run("--remove")
eq(readFile(spawnPath), crlf, "CRLF: remove gives the stock file back")

-- ------------------------------------------------------------------ pack combat: a 600+ band (late_game.py's entries too)
do
	writeFile(spawnPath, stock)
	local t2 = tuning:gsub('"bandRespawn": %[[^%]]*%]',
		'"bandRespawn": [{"from": 300, "to": 600, "spawntime": 45, "onlyUpTo": 300}, ' ..
		'{"from": 600, "to": 100000, "spawntime": 75, "onlyUpTo": 300}]')
	writeFile(tuningPath, t2)
	out, rc = run("")
	eq(rc, 0, "600+ band run ok: " .. out)
	text = readFile(spawnPath)
	ok(text:find('<monster chaosst="120" name="Test High" x="0" y="0" z="9" spawntime="75" lategame="Test Low" />', 1,
		true) ~= nil, "600+ band: a late_game.py entry 120 -> 75, its marker kept")
	ok(text:find('<monster chaosst="120" name="Test Mid" x="0" y="0" z="8" spawntime="45" />', 1, true) ~= nil,
		"300-600 band: 120 -> 45")
	ok(text:find('<monster chaosst="60" name="Test Mid" x="-2" y="1" z="8" spawntime="45" />', 1, true) ~= nil,
		"300-600 band: 60 -> 45")
	out, rc = run("")
	ok(out:find("unchanged", 1, true) ~= nil, "600+ band: second run unchanged")
	run("--remove")
	eq(readFile(spawnPath), stock, "600+ band: remove gives the stock file back")
	writeFile(tuningPath, tuning)
end

-- ------------------------------------------------------------------ pack combat: a base dungeon keeps `keep` monsters
do
	writeFile(spawnPath, stock)
	local t3 = tuning:gsub('"remove": ', '"dungeons": [{"id": 9, "boxes": [[1994, 1994, 8, 2004, 2004, 8]], "keep": 1}],\n  "remove": ')
	writeFile(tuningPath, t3)
	out, rc = run("")
	eq(rc, 0, "dungeon run ok: " .. out)
	ok(out:find("3 dungeon", 1, true) ~= nil, "dungeon: 4 hunting monsters inside, 1 kept: " .. out)
	text = readFile(spawnPath)
	eq(count(text, "chaosremoved"), 4, "dungeon: three taken out as comments (and the listed removal)")
	ok(text:find('<monster name="Test Boss" x="0" y="2" z="8" spawntime="120" />', 1, true) ~= nil,
		"dungeon: the boss stays")
	ok(text:find('chaosadd="F0002"', 1, true) == nil, "dungeon: no fill spawn inside the box")
	ok(text:find('chaosadd="F0003"', 1, true) ~= nil, "dungeon: fill spawns outside the box stay")
	ok(text:find('<spawn centerx="2005" centery="2005" centerz="8" radius="2" chaosadd="T-01">', 1, true) ~= nil,
		"dungeon: an add outside whose like was taken out still copies it")
	out, rc = run("")
	ok(out:find("unchanged", 1, true) ~= nil, "dungeon: second run unchanged")
	run("--remove")
	eq(readFile(spawnPath), stock, "dungeon: remove gives the stock file back")
	writeFile(tuningPath, tuning)
end

-- the shipped tuning: every base dungeon keeps at least 100 monsters (owner rule, 2026-10-14)
do
	local p = io.popen("python3 -I -c \"import json; d = json.load(open('tools/spawn_tuning.json')); " ..
		"print(min(x['keep'] for x in d['dungeons']), len(d['dungeons']))\"")
	local res = p:read("*a")
	p:close()
	local least, n = res:match("(%d+) (%d+)")
	eq(tonumber(n), 4, "the four base dungeons are listed")
	ok(tonumber(least) and tonumber(least) >= 100, "every base dungeon keeps at least 100 monsters: " .. tostring(least))
end

-- ------------------------------------------------------------------ problems
writeFile(spawnPath, stock)
writeFile(tuningPath, [[
{
  "areas": [{"id": "T-01", "box": [1990, 1990, 8, 2010, 2010, 8]}],
  "move": [{"at": [5000, 5000, 7], "to": [5001, 5000]}],
  "remove": [{"at": [5000, 5001, 7]}],
  "fill": "fill.json",
  "add": [
    {"area": "T-01", "at": [2500, 2500, 8], "like": [2000, 2000, 8]},
    {"area": "T-02", "at": [2000, 2001, 8], "like": [2000, 2000, 8]},
    {"area": "T-01", "at": [2001, 2001, 8], "like": [2009, 2009, 8]}
  ]
}
]])
writeFile(root .. "/fill.json", '{"areas": [{"id": "F0009", "z": 7, "likes": [[1500, 1500]], "add": [[1501, 1501, 0]]}]}')
out, rc = run("")
eq(rc, 1, "bad positions: exit 1")
ok(out:find("fill F0009: no entry at like [1500, 1500, 7]", 1, true) ~= nil, "fill copying nothing")
ok(out:find("move [5000, 5000, 7]: 0 entries there", 1, true) ~= nil, "move without an entry")
ok(out:find("remove [5000, 5001, 7]: no entry there", 1, true) ~= nil, "remove without an entry")
ok(out:find("outside the box of area T-01", 1, true) ~= nil, "add outside its area")
ok(out:find("unknown area 'T-02'", 1, true) ~= nil, "add with an unknown area")
ok(out:find("no entry at like [2009, 2009, 8]", 1, true) ~= nil, "add copying nothing")

os.execute("rm -rf '" .. root .. "'")
if fails > 0 then
	print(string.format("base_spawns_patch: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("base_spawns_patch: all %d checks passed", checks))

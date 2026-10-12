-- Run from the server/ folder: luajit tests/treestats_test.lua (no engine; CI runs it with luajit and lua5.3)
-- The passive tree pick statistics (data/scripts/chaos/treestats_core.lua, treestats.lua): level bands, the active
-- preset of each character, staff and empty trees left out, unknown ids ignored, counts per line and band (and "all"),
-- top N, never-taken nodes, the node descriptions, the CSV (counts only, small groups left out) and the /treestats
-- command against a mocked engine (staff only, the class and band words, the export file).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/treestats_config.lua")
dofile("data/scripts/chaos/treestats_core.lua")
local S = ChaosTreeStatsCore
local cfg = ChaosTreeStatsConfig
local tree = dofile("data/scripts/chaos/passivetree_data.lua")

-- ------------------------------------------------------------------ bands
eq(S.bandOf(1, cfg.bands), "1-99", "level 1"); eq(S.bandOf(299, cfg.bands), "100-299", "level 299")
eq(S.bandOf(300, cfg.bands), "300-499", "level 300"); eq(S.bandOf(1000, cfg.bands), "1000+", "level 1000")
eq(S.bandOf(2400, cfg.bands), "1000+", "level 2400"); eq(S.bandOf(0, cfg.bands), nil, "no level")
eq(table.concat(S.bandLabels(cfg.bands), " "), "1-99 100-299 300-499 500-999 1000+ all", "labels in order")
eq(table.concat(S.parseNodes("2,3,9,665|665:2"), ","), "2,3,9,665", "the masteries part is not nodes")
eq(#S.parseNodes(""), 0, "an empty tree")

-- ------------------------------------------------------------------ test data: 9 saved trees, 8 characters
local LINE = {[4] = "warrior", [8] = "warrior", [11] = "thief", [12] = "thief", [21] = "necromancer"}
local rows = {
	{player = 1, preset = 1, vocation = 4, level = 350, group = 1, nodes = "2,9,11"},
	{player = 2, preset = 1, vocation = 8, level = 420, group = 1, nodes = "2,9,11,13"},
	{player = 3, preset = 1, vocation = 4, level = 310, group = 1, nodes = "2,9"},
	{player = 3, preset = 2, vocation = 4, level = 310, group = 1, nodes = "3,8,10"}, -- not the active preset
	{player = 4, preset = 1, vocation = 12, level = 1200, group = 1, nodes = "626,627,628,629,665|665:2"},
	{player = 5, preset = 1, vocation = 11, level = 150, group = 1, nodes = "626,627,99999"}, -- 99999: retired id
	{player = 6, preset = 1, vocation = 4, level = 360, group = 5, nodes = "2,9,11,13,61"}, -- staff: left out
	{player = 7, preset = 1, vocation = 21, level = 500, group = 1, nodes = ""}, -- nothing saved: left out
	{player = 8, preset = 1, vocation = 2, level = 500, group = 1, nodes = "2"}, -- a retired vocation: no line
}
local ctx = {tree = tree, bands = cfg.bands, staffGroup = cfg.staffGroup, minCharacters = 3,
	lineOf = function(v) return LINE[v] end, lines = {"warrior", "thief", "necromancer"},
	lineClasses = {warrior = {"warrior", "juggernaut", "berserker"}, thief = {"thief", "ninja", "samurai"},
		necromancer = {"necromancer", "lich", "bonelord"}}}
local stats = S.aggregate(rows, ctx)
local w = stats.warrior["300-499"]
eq(w.characters, 3, "three warriors at 300-499 (staff left out)")
eq(w.counts[2], 3, "node 2: all three"); eq(w.counts[9], 3); eq(w.counts[11], 2); eq(w.counts[13], 1)
eq(w.counts[3], nil, "the second preset is not counted"); eq(w.counts[61], nil, "the staff tree is not counted")
eq(stats.warrior.all.characters, 3, "all bands"); eq(stats.thief.all.characters, 2, "two thieves")
eq(stats.thief["1000+"].counts[665], 1, "a mastery node counts as a node")
eq(stats.thief["100-299"].counts[99999], nil, "a retired id is not counted")
eq(stats.necromancer, nil, "an empty tree does not count")
-- top and never
local top = S.top(w, 2)
eq(#top, 2, "top 2"); eq(top[1].id, 2, "most taken first"); eq(top[2].id, 9, "ties by id")
eq(top[1].count, 3); eq(top[1].share, 1)
local lineIds = S.lineNodes(tree, ctx.lineClasses.thief)
local has = {}
for _, id in ipairs(lineIds) do has[id] = true end
check(has[626] and has[383] and has[2] and not has[636] and not has[621], "the Thief line's nodes: its section and 383, not others'")
local never = S.never(stats.thief.all, lineIds)
local nv = {}
for _, id in ipairs(never) do nv[id] = true end
check(not nv[626] and not nv[629] and nv[383] and nv[2], "never taken: 383 and node 2 for the thieves")
eq(#never, #lineIds - 5, "five nodes taken by thieves (626, 627, 628, 629, 665)")
eq(#S.never(nil, lineIds), #lineIds, "a line without characters: every node")
-- descriptions
eq(S.describe(tree.nodes[393]), "absorbFire+1 incrementFire+3", "a notable")
eq(S.describe(tree.nodes[383]), "ksBlackbloodCreed", "a keystone by its key")
eq(S.describe(tree.nodes[665]), "mastery (4 effects)", "a mastery")
eq(S.describe(tree.nodes[621]), "variants (9 classes)", "the per-class keystone")
-- the report
local lines = S.report(stats, tree, ctx, "warrior", "300-499", 3, 5)
check(lines[1]:find("warrior, level 300-499, 3 characters.", 1, true), "report head: " .. lines[1])
check(lines[3]:find("node 2", 1, true) and lines[3]:find("3 (100%)", 1, true), "report top line: " .. lines[3])
check(lines[#lines]:find("^Never taken: %d+ nodes: ") and lines[#lines]:find("...", 1, true), "never taken, cut: " .. lines[#lines])
lines = S.report(stats, tree, ctx, "thief", "all", 3)
check(lines[1]:find("(few characters: not in the CSV)", 1, true), "a small group is marked")
lines = S.report(stats, tree, ctx, "necromancer", "all", 3)
eq(lines[2], "No saved tree in this line and band.", "no data")
-- no personal data: no player id, name or account anywhere in a report
for _, l in ipairs(S.report(stats, tree, ctx, "warrior", "all", 40)) do
	check(not l:find("player", 1, true), "no player in the report")
end

-- ------------------------------------------------------------------ the CSV
local csv, written, skipped = S.csv(stats, tree, ctx)
local first = csv:match("^[^\n]+")
eq(first, "line,band,characters,node,count,share,stats", "header")
local wIds = #S.lineNodes(tree, ctx.lineClasses.warrior)
eq(written, 2 * wIds, "warrior 300-499 and all, every node of the line (counts of 0 too)")
eq(table.concat(skipped, "; "), "thief 100-299; thief 1000+; thief all", "the thieves are too few")
check(csv:find("\nwarrior,300-499,3,2,3,1.000,strength+1\n", 1, true), "a row: node 2 by all three")
check(csv:find("\nwarrior,300-499,3,13,1,0.333,strength+1\n", 1, true), "a row: node 13 by one")
check(csv:find("\nwarrior,all,3,383,", 1, true) == nil, "383 is not a warrior node")
check(not csv:find("Thief", 1, true) and not csv:find("thief", 1, true), "no thief rows at all")
-- every data row has seven fields (descriptions never hold a comma)
local rowsOk = true
for line in csv:gmatch("[^\n]+") do
	local n = select(2, line:gsub(",", ",")) + 1
	rowsOk = rowsOk and n == 7
end
check(rowsOk, "seven fields per row")
ctx.minCharacters = 1
csv, written, skipped = S.csv(stats, tree, ctx)
eq(#skipped, 0, "minCharacters 1: nothing left out")
check(csv:find("\nthief,1000+,1,629,1,1.000,ctTwinFangs strength+2\n", 1, true), "a class notable row")

-- ------------------------------------------------------------------ the command (mocked engine)
local talks = {}
function TalkAction(words)
	local t = {}
	function t:separator() end
	function t:register() talks[words] = self end
	return t
end
Chaos.select = function() return rows end
local tmpBase = os.tmpname() -- (creates an empty file: removed at the end)
ChaosTreeStatsConfig.csvPath = tmpBase .. "_%s.csv"
dofile("data/scripts/chaos/treestats.lua")
local TS = ChaosTreeStats
local linesKeys, classes = TS.lines()
eq(table.concat(linesKeys, ","), "mystic,ranger,warrior,thief,monk,necromancer,templar", "the seven lines by base id")
eq(table.concat(classes.thief, ","), "ninja,samurai,thief", "the Thief line's classes")
local out = TS.command("")
check(out[1]:find("Characters with a saved tree", 1, true), "summary head")
local warriorLine
for _, l in ipairs(out) do if l:find("^warrior:") then warriorLine = l end end
check(warriorLine and warriorLine:find("300-499 3", 1, true) and warriorLine:find("all 3", 1, true), "summary: " .. tostring(warriorLine))
out = TS.command("juggernaut 300-499 2")
check(out[1]:find("warrior, level 300-499, 3 characters", 1, true), "a class word means its line: " .. out[1])
eq(out[2], "Top 2:", "n from the command")
out = TS.command("warrior 350")
check(out[1]:find("level 300-499", 1, true), "a level picks its band: " .. out[1])
out = TS.command("warrior 1000+")
check(out[1]:find("level 1000+, 0 characters", 1, true), "an empty band")
out = TS.command("warrior 12-13")
check(out[1]:find("Unknown band", 1, true), "an unknown band")
out = TS.command("knight")
check(out[1]:find("Unknown class", 1, true), "an unknown class")
local path, text
out, path, text = TS.command("export")
check(out[1]:find("Written", 1, true) and path and text, "export: " .. tostring(out[1]))
local f = io.open(path, "r")
check(f ~= nil, "the CSV file exists")
if f then
	local disk = f:read("*a")
	f:close()
	eq(disk, text, "the file holds the CSV")
	check(not disk:find("Bob", 1, true), "no names")
	os.remove(path)
end
check(out[2] and out[2]:find("thief all", 1, true), "the export names what it left out: " .. tostring(out[2]))
-- staff only (Chaos.staffCommand): a player's words are said as chat, nothing is read
local said = {}
local function mkPlayer(access, gid)
	local p = {msgs = {}}
	function p:getGroup() return {getAccess = function() return access end, getId = function() return gid end} end
	function p:getName() return "Tester" end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:sendCancelMessage(text) self.msgs[#self.msgs + 1] = text end
	return p
end
local reads = 0
Chaos.select = function() reads = reads + 1; return rows end
local pl = mkPlayer(false, 1)
eq(talks["/treestats"].onSay(pl, "/treestats", ""), true, "a player: the words are chat")
eq(reads, 0, "and nothing is read")
local gm = mkPlayer(true, 4)
eq(talks["/treestats"].onSay(gm, "/treestats", "warrior"), false, "staff: swallowed")
eq(reads, 1, "one query")
check(gm.msgs[1] and gm.msgs[1]:find("warrior", 1, true), "staff gets the report")

os.remove(tmpBase)

print(string.format("treestats_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

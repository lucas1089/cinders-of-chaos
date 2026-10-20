-- Run from the server/ folder: luajit tests/tile_labels_test.lua (and lua5.3; CI runs both)
-- Orange tile labels (tile_labels_core.lua, tile_labels.lua, tile_labels_config.lua; server/README.md "Tile labels"):
-- every booth NPC of every hall is labelled with its name, the row titles stand at both ends of their row, fixed labels
-- are kept, nothing is listed twice, a bad entry is skipped, and the engine side sends the config's colour.
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		io.write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label) .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/npc_booths_core.lua")
dofile("data/scripts/chaos/tile_labels_core.lua")
local B, K = ChaosNpcBoothsCore, ChaosTileLabelsCore
local bcfg = B.cfg()
local lcfg = dofile("data/scripts/chaos/tile_labels_config.lua")

check(lcfg.enabled and lcfg.color == 198, "enabled, orange palette byte")

-- the real config: every booth of every hall
local list = K.collect(lcfg, bcfg, B)
local at = {}
for _, l in ipairs(list) do
	at[l.x .. ":" .. l.y .. ":" .. l.z .. ":" .. l.text] = true
end
local npcLabels = 0
for _, hall in ipairs(bcfg.halls) do
	for _, b in ipairs(B.booths(bcfg, hall)) do
		check(at[b.x .. ":" .. b.y .. ":" .. b.z .. ":" .. b.name], "booth " .. b.name .. " in " .. hall.name)
		npcLabels = npcLabels + 1
	end
	local p = bcfg.rows[1]
	for _, x in ipairs({p.from, p.to}) do
		local w = B.offset(hall, x, p.npcRow)
		check(at[w.x .. ":" .. w.y .. ":" .. w.z .. ":Progression"], "title at the row end " .. x .. " in " .. hall.name)
	end
end
check(npcLabels > 0, "booths exist")
-- a booth that differs per town is labelled per town
check(at[B.offset(bcfg.halls[1], 20, 27).x .. ":" .. B.offset(bcfg.halls[1], 20, 27).y .. ":7:Forgemaster Brannoc"]
	or at[B.offset(bcfg.halls[2], 20, 27).x .. ":" .. B.offset(bcfg.halls[2], 20, 27).y .. ":7:Forgemaster Brannoc"],
	"a per-town NPC is labelled")
-- free slots and a false title give nothing
for _, l in ipairs(list) do
	check(l.text ~= "false" and l.text ~= "", "no empty text")
	check(l.text ~= "stash keeper" and l.text ~= "pocket boss NPC", "a free slot has no label")
end

-- the pure rules on a small config
local small = {halls = {{town = 1, name = "T", at = {x = 100, y = 200, z = 7}}},
	rows = {{key = "r", npcRow = 5, counterRow = 4, from = 1, to = 9, booths = {{x = 3, npc = "A"}, {x = 8, npc = false}}}}}
local l2 = K.collect({booths = true, rowTitles = {r = "Row"}, labels = {
	{text = "Corner", pos = {x = 1, y = 2, z = 7}}, {text = "Corner", pos = {x = 1, y = 2, z = 7}}, {text = "", pos = {x = 1, y = 2, z = 7}},
	{text = "NoPos"}}}, small, B)
eq(#l2, 4, "booth, two titles, one corner (duplicates, empty text and a missing tile skipped)")
eq(l2[1].text, "A"); eq(l2[1].x, 103); eq(l2[1].y, 205)
eq(l2[2].x, 101); eq(l2[3].x, 109); eq(l2[4].text, "Corner")
eq(#K.collect({booths = false, rowTitles = {}, labels = {}}, small, B), 0, "everything off: nothing")
eq(#K.collect({labels = {{text = "X", pos = {x = 1, y = 1, z = 7}}}}, nil, nil), 1, "no halls: the fixed labels")

-- the engine side: one animated text per label with the config colour
local sent = {}
GlobalEvent = function() return {interval = function() end, register = function() end} end
ChaosCombatFx = {label = function(pos, text, color) sent[#sent + 1] = {pos = pos, text = text, color = color}; return true end}
Chaos = {}
dofile("data/scripts/chaos/tile_labels.lua")
eq(ChaosTileLabels.pulse(), #list, "a pulse sends every label")
eq(sent[1].color, 198, "orange"); eq(#sent, #list)
ChaosTileLabels.config.enabled = false
eq(ChaosTileLabels.pulse(), 0, "off: nothing sent")

print(string.format("tile_labels_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/tile_labels_test.lua (and lua5.3; CI runs both)
-- Orange tile labels (tile_labels_core.lua, tile_labels.lua, tile_labels_config.lua; server/README.md "Tile labels"):
-- every NPC in a stall of the hub is labelled with its name, fixed labels are kept, nothing is listed twice, a bad entry
-- is skipped, nothing is labelled at the temple any more, and the engine side sends the config's colour.
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

-- the real config: every stall of the hub with a Chaos NPC, nothing else
local list = K.collect(lcfg, bcfg, B)
local at = {}
for _, l in ipairs(list) do
	at[l.x .. ":" .. l.y .. ":" .. l.z .. ":" .. l.text] = true
end
local npcLabels = 0
for _, b in ipairs(B.booths(bcfg)) do
	check(at[b.x .. ":" .. b.y .. ":" .. b.z .. ":" .. b.name], "stall " .. b.name)
	npcLabels = npcLabels + 1
end
check(npcLabels >= 10, "the hub's stalls have their NPCs")
eq(#list, npcLabels + #(lcfg.labels or {}), "one label per stall NPC and fixed label")
for _, l in ipairs(list) do
	check(l.text ~= "false" and l.text ~= "", "no empty text")
	check(not (l.x >= 32356 and l.x <= 32382 and l.y >= 32240 and l.y <= 32249), "no label at the temple: " .. l.text)
end

-- the pure rules on a small config
local small = {enabled = true, booths = {{x = 103, y = 205, z = 7, npc = "A"}, {x = 108, y = 205, z = 7, npc = false}}}
local l2 = K.collect({booths = true, labels = {
	{text = "Corner", pos = {x = 1, y = 2, z = 7}}, {text = "Corner", pos = {x = 1, y = 2, z = 7}}, {text = "", pos = {x = 1, y = 2, z = 7}},
	{text = "NoPos"}}}, small, B)
eq(#l2, 2, "the stall's NPC and one corner (an empty stall, duplicates, empty text and a missing tile skipped)")
eq(l2[1].text, "A"); eq(l2[1].x, 103); eq(l2[1].y, 205)
eq(l2[2].text, "Corner")
eq(#K.collect({booths = false, labels = {}}, small, B), 0, "everything off: nothing")
eq(#K.collect({booths = true}, {enabled = false, booths = small.booths}, B), 0, "booths off in their config: nothing")
eq(#K.collect({labels = {{text = "X", pos = {x = 1, y = 1, z = 7}}}}, nil, nil), 1, "no booths: the fixed labels")

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

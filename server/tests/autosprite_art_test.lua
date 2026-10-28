-- Run from the server/ folder: luajit tests/autosprite_art_test.lua (and lua5.3; CI runs both)
-- The creature looks of our AutoSprite renders, client pair 54 (data/lib/chaos_autosprite_art.lua): while the switch is
-- off the monsters keep their stock looks and the picks rows stay out of picks.csv; each picks row names its monster and
-- the look the module names; forced on, lookOf gives the new looks; the Embergut Rift holds the boss and both hunt
-- monsters.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local M = dofile("data/lib/chaos_autosprite_art.lua")

local FILES = {
	["Vharzul the Verdant Eye"] = {key = "eye_demon", file = "vharzul_the_verdant_eye.xml", boss = true},
	["Ashbound Thrall"] = {key = "ashbound_thrall", file = "ashbound_thrall.xml"},
	["Slagback Hound"] = {key = "slagback_hound", file = "slagback_hound.xml"}
}

-- ---------------------------------------------------------------- the picks rows
local picks = assert(io.open("../client/tools/sprites/monster_looks/autosprite_picks.csv", "r")):read("*a")
local all = assert(io.open("../client/tools/sprites/monster_looks/picks.csv", "r")):read("*a")
local rows, nextLook = 0, 3361
for key, look, monster in picks:gmatch("\n([%w_]+),(%d+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^,]+),") do
	rows = rows + 1
	local f = FILES[monster]
	eq(f and f.key, key, monster .. ": the picks row")
	eq(tonumber(look), nextLook, key .. ": looks follow pair 53's 3360 outfits in order")
	eq(M.monsters[monster] and M.monsters[monster].look, nextLook, key .. ": the module maps the monster to its look")
	eq(all:find("\n" .. key .. ",", 1, true) ~= nil, M.PAIR54, key .. ": in picks.csv exactly when the switch is on")
	nextLook = nextLook + 1
end
eq(rows, 3, "three looks")
local count = 0
for _ in pairs(M.monsters) do
	count = count + 1
end
eq(count, 3, "the module holds exactly the picks rows")

-- ---------------------------------------------------------------- the monster files
for name, f in pairs(FILES) do
	local xml = assert(io.open("data/monster/monsters/chaos/" .. f.file, "r")):read("*a")
	eq(xml:match('<monster name="([^"]+)"'), name, f.file)
	eq(xml:match('isboss="(%d)"'), f.boss and "1" or nil, name .. ": boss flag")
	local m = M.monsters[name]
	eq(tonumber(xml:match('<look type="(%d+)"')), M.PAIR54 and m.look or m.stock, name .. ": the look the switch gives")
end

M.PAIR54 = false
eq(M.lookOf("Ashbound Thrall", 40), 40, "off: lookOf gives the stock look")
eq(M.lookOf("Demon", 35), 35, "another monster keeps its look")
M.PAIR54 = true
eq(M.lookOf("Vharzul the Verdant Eye", 35), 3361, "on: the boss look")
eq(M.lookOf("Slagback Hound", 240), 3363, "on: the hound look")
eq(M.lookOf("Demon", 35), 35, "on: another monster keeps its look")

-- ---------------------------------------------------------------- the plan
local plan = assert(io.open("tools/areaplan/plans/embergut_rift.json", "r")):read("*a")
eq(plan:match('"boss"%s*:%s*{[^}]-"monster"%s*:%s*"([^"]+)"'), "Vharzul the Verdant Eye", "the Embergut Rift's boss")
eq(plan:match('"boss"%s*:%s*{[^}]-"zone"%s*:%s*"([^"]+)"'), "scorched_pools", "it stands in the Scorched Pools")
eq(plan:find('"Ashbound Thrall"', 1, true) ~= nil, true, "the thralls hunt the rift")
eq(plan:find('"Slagback Hound"', 1, true) ~= nil, true, "the hounds hunt the rift")

print("autosprite_art_test: " .. n .. " checks passed")

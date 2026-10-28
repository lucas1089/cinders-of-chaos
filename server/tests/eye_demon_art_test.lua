-- Run from the server/ folder: luajit tests/eye_demon_art_test.lua (and lua5.3; CI runs both)
-- The Verdant Eye Demon look of the client pair 54 (data/lib/chaos_eye_demon_art.lua): while the switch is off the
-- boss keeps the stock demon look and the picks row stays out of picks.csv; the picks row names the boss and the look
-- the module names; forced on, lookOf gives the new look; the boss stands in the Embergut Rift's boss room.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local M = dofile("data/lib/chaos_eye_demon_art.lua")
local NAME = "Vharzul the Verdant Eye"

-- ---------------------------------------------------------------- the picks row
local picks = assert(io.open("../client/tools/sprites/monster_looks/eye_demon_picks.csv", "r")):read("*a")
local key, look, monster = picks:match("\n([%w_]+),(%d+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^,]+),")
eq(key, "eye_demon", "the picks row")
eq(tonumber(look), 3361, "look of the picks row (after pair 53's 3360 outfits)")
eq(monster, NAME, "the picks row names the boss")
eq(M.monsters[NAME], 3361, "the module maps the boss to look 3361")

local all = assert(io.open("../client/tools/sprites/monster_looks/picks.csv", "r")):read("*a")
local inPicks = all:find("\neye_demon,", 1, true) ~= nil
eq(inPicks, M.PAIR54, "the row is in picks.csv exactly when the switch is on")

-- ---------------------------------------------------------------- the boss file
local xml = assert(io.open("data/monster/monsters/chaos/vharzul_the_verdant_eye.xml", "r")):read("*a")
eq(xml:match('<monster name="([^"]+)"'), NAME, "the boss file")
eq(xml:match('isboss="(%d)"'), "1", "Vharzul is a boss (never paced)")
local current = tonumber(xml:match('<look type="(%d+)"'))
eq(current, M.PAIR54 and 3361 or 35, "the boss file has the look the switch gives")

M.PAIR54 = false
eq(M.lookOf(NAME, 35), 35, "off: lookOf keeps the current look")
eq(M.lookOf("Demon", 35), 35, "another monster keeps its look")
M.PAIR54 = true
eq(M.lookOf(NAME, 35), 3361, "on: lookOf gives the new look")
eq(M.lookOf("Demon", 35), 35, "on: another monster keeps its look")

-- ---------------------------------------------------------------- the plan
local plan = assert(io.open("tools/areaplan/plans/embergut_rift.json", "r")):read("*a")
eq(plan:match('"boss"%s*:%s*{[^}]-"monster"%s*:%s*"([^"]+)"'), NAME, "the Embergut Rift's boss")
eq(plan:match('"boss"%s*:%s*{[^}]-"zone"%s*:%s*"([^"]+)"'), "scorched_pools", "it stands in the Scorched Pools")

print("eye_demon_art_test: " .. n .. " checks passed")

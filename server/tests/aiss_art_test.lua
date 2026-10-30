-- Run from the server/ folder: luajit tests/aiss_art_test.lua (and lua5.3; CI runs both)
-- The creature looks of the AI Sprite Studio sample pack, client pair 57 (data/lib/chaos_aiss_art.lua): while the switch is
-- off the monsters keep their stock looks and the picks rows stay out of picks.csv; each picks row names its monster and
-- the look the module names; forced on, lookOf gives the new looks. Each file carries the level band, health and
-- experience of the table below (the pack 30 template under level 650, the late-game curves above) and has loot and attacks.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local M = dofile("data/lib/chaos_aiss_art.lua")

-- key, file, level mid, level span, health, experience
local FILES = {
	["Gloamgeode Shellback"] = {key = "gloamgeode_shellback", file = "gloamgeode_shellback.xml", mid = 1150, span = 20, hp = 25300, xp = 21100},
	["Wickstaff Hexmage"] = {key = "wickstaff_hexmage", file = "wickstaff_hexmage.xml", mid = 630, span = 10, hp = 12210, xp = 4050},
	["Bogtusk Cleaver"] = {key = "bogtusk_cleaver", file = "bogtusk_cleaver.xml", mid = 400, span = 10, hp = 7750, xp = 1650},
	["Redmane Anvilbreaker"] = {key = "redmane_anvilbreaker", file = "redmane_anvilbreaker.xml", mid = 1550, span = 20, hp = 30400, xp = 37350},
	["Marshlight Hollowseer"] = {key = "marshlight_hollowseer", file = "marshlight_hollowseer.xml", mid = 1350, span = 20, hp = 28200, xp = 29100},
	["Gravecrown Oathbreaker"] = {key = "gravecrown_oathbreaker", file = "gravecrown_oathbreaker.xml", mid = 1850, span = 20, hp = 32800, xp = 49950},
	["Coralcrown Brinecaller"] = {key = "coralcrown_brinecaller", file = "coralcrown_brinecaller.xml", mid = 930, span = 20, hp = 20900, xp = 12800}
}

-- ---------------------------------------------------------------- the picks rows
local picks = assert(io.open("../client/tools/sprites/monster_looks/aiss_picks.csv", "r")):read("*a")
local all = assert(io.open("../client/tools/sprites/monster_looks/picks.csv", "r")):read("*a")
local rows, nextLook = 0, 3364
for key, look, monster in picks:gmatch("\n([%w_]+),(%d+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^,]+),") do
	rows = rows + 1
	local f = FILES[monster]
	eq(f and f.key, key, monster .. ": the picks row")
	eq(tonumber(look), nextLook, key .. ": looks follow pair 56's 3363 outfits in order")
	eq(M.monsters[monster] and M.monsters[monster].look, nextLook, key .. ": the module maps the monster to its look")
	eq(all:find("\n" .. key .. ",", 1, true) ~= nil, M.PAIR57, key .. ": in picks.csv exactly when the switch is on")
	nextLook = nextLook + 1
end
eq(rows, 7, "seven looks")
local count = 0
for _ in pairs(M.monsters) do
	count = count + 1
end
eq(count, 7, "the module holds exactly the picks rows")

-- ---------------------------------------------------------------- the monster files
for name, f in pairs(FILES) do
	local xml = assert(io.open("data/monster/monsters/chaos/" .. f.file, "r")):read("*a")
	eq(xml:match('<monster name="([^"]+)"'), name, f.file)
	eq(xml:match('isboss="(%d)"'), nil, name .. ": a hunt monster, not a boss")
	local m = M.monsters[name]
	eq(tonumber(xml:match('<look type="(%d+)"')), M.PAIR57 and m.look or m.stock, name .. ": the look the switch gives")
	local lo, hi = xml:match('<level min="(%d+)" max="(%d+)"')
	eq(tonumber(lo), f.mid - f.span, name .. ": level min")
	eq(tonumber(hi), f.mid + f.span, name .. ": level max")
	eq(tonumber(xml:match('<health now="(%d+)"')), f.hp, name .. ": health")
	eq(tonumber(xml:match('experience="(%d+)"')), f.xp, name .. ": experience")
	eq(xml:find('<item id="2152"', 1, true) ~= nil, true, name .. ": platinum coins in the loot")
	eq(xml:find("<attack ", 1, true) ~= nil, true, name .. ": attacks")
end

M.PAIR57 = false
eq(M.lookOf("Bogtusk Cleaver", 7), 7, "off: lookOf gives the stock look")
eq(M.lookOf("Demon", 35), 35, "another monster keeps its look")
M.PAIR57 = true
eq(M.lookOf("Gloamgeode Shellback", 197), 3364, "on: the tortoise look")
eq(M.lookOf("Coralcrown Brinecaller", 47), 3370, "on: the naga look")
eq(M.lookOf("Demon", 35), 35, "on: another monster keeps its look")

print("aiss_art_test: " .. n .. " checks passed")

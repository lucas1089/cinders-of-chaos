-- Run from the server/ folder: luajit tests/assets_art_test.lua (and lua5.3; CI runs both)
-- The catacomb kit of the client pair 27 trial (data/lib/chaos_assets_art.lua, chaos_assets_decor.lua): the switch is
-- off (pair 27 is a trial), so the Hollow Rider keeps its stock look; the generated decoration ids match the manifest;
-- the look of the picks file is the one the module names; forced on, lookOf gives the new look.

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local M = dofile("data/lib/chaos_assets_art.lua")
eq(M.PAIR27, true, "the pair 27 switch is on: pair 27 is live (windows-assets 51a26d26)")

-- ---------------------------------------------------------------- decoration ids against the manifest
local rows = {}
local f = assert(io.open("data/items/assets_decor.csv", "r"))
local header = true
for line in f:lines() do
	if header then
		header = false
	else
		local cid, sid, key = line:match("^(%d+),(%d+),([%w_]+),")
		rows[#rows + 1] = {cid = tonumber(cid), sid = tonumber(sid), key = key}
	end
end
f:close()
eq(#rows, 9, "nine kit items in the manifest")
local count = 0
for _, r in ipairs(rows) do
	eq(r.sid, r.cid + 3000, r.key .. ": server id = client id + 3000")
	eq(M.decor.items[r.key] and M.decor.items[r.key].id, r.sid, r.key .. ": id in chaos_assets_decor.lua")
	count = count + 1
end
for _ in pairs(M.decor.items) do
	count = count - 1
end
eq(count, 0, "chaos_assets_decor.lua holds exactly the manifest rows")
eq(M.decor.first, 36986, "first server id")
eq(M.decor.last, 36994, "last server id")

-- ---------------------------------------------------------------- the monster look
local picks = assert(io.open("../client/tools/sprites/monster_looks/assets_art_picks.csv", "r")):read("*a")
local key, look, monster = picks:match("\n([%w_]+),(%d+),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^,]+),")
eq(key, "hollow_rider", "the picks row")
eq(tonumber(look), 2234, "look of the picks row")
eq(monster, "Hollow Rider", "the picks row names the boss")
eq(M.monsters["Hollow Rider"], 2234, "the module maps the boss to look 2234")

local xml = assert(io.open("data/monster/monsters/chaos/hollow_rider.xml", "r")):read("*a")
local stock = tonumber(xml:match('<look type="(%d+)"'))
eq(stock, 2234, "the boss file has the kit look (apply_monster_looks.py)")
M.PAIR27 = false
eq(M.lookOf("Hollow Rider", 1074), 1074, "off: lookOf keeps the current look")
eq(xml:match('isboss="(%d)"'), "1", "the Hollow Rider is a boss (never paced)")

M.PAIR27 = true
eq(M.lookOf("Hollow Rider", 1074), 2234, "on: lookOf gives the kit look")
eq(M.lookOf("Plagueroot", 1477), 1477, "on: other monsters keep theirs")

print("assets_art_test: " .. n .. " checks OK")

-- Run from the server/ folder: luajit tests/source_wings_test.lua (and lua5.3; CI runs both)
-- The fifteen source wings of client pair 74 (O627, data/lib/chaos_source_wings.lua): ids follow pair 73's last outfit (3529) and the 121
-- wings of pair 33, the rows match the art table of client/tools/sprites/gen_source_wings.py, the gate is config.lua chaosClientPair >= 74
-- (nothing changes below it), and when it is on the store sells them at the end of the Wings category and the store validates.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/transmog_core.lua")
dofile("data/scripts/chaos/exclusives_core.lua")
dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/nameplate_core.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local LIB = "data/lib/chaos_source_wings.lua"
local M = dofile(LIB)
eq(M.PAIR, 74, "pair 74")
eq(M.PAIR74, false, "no config.lua next to the tests: the gate is off")

-- ---------------------------------------------------------------- the pair record
eq(M.parsePair("chaosClientPair = 74"), 74, "plain")
eq(M.parsePair("x = 1\nchaosClientPair=73 -- shipped\ny = 2\n"), 73, "comment, no spaces, other lines")
eq(M.parsePair("chaosClientPair = \"abc\"\n"), nil, "not a number")
eq(M.parsePair(nil), nil, "no text")
eq(M.recordedPair("tests/no_such_config.lua"), nil, "no file")

-- ---------------------------------------------------------------- the rows
eq(#M.wings, 15, "15 wings")
local keys, names = {}, {}
for i, p in ipairs(M.wings) do
	eq(p.look, 3529 + i, p.key .. ": looks follow pair 73's 3529 outfits in order")
	eq(p.id, 121 + i, p.key .. ": wings.xml ids 122.. after the 121 of pair 33")
	eq(keys[p.key], nil, p.key .. ": unique key") keys[p.key] = true
	eq(names[p.name], nil, p.name .. ": unique name") names[p.name] = true
	eq(p.key:match("^wings_[a-z]+$") ~= nil, true, p.key .. ": a key of the exclusives style")
	eq(p.name:match(" Wings$") ~= nil, true, p.name .. ": ends in Wings")
	eq(p.cost == 250 or p.cost == 300, true, p.key .. ": 250 or 300 coins like the pair 33 wings")
end

-- no name or key of another wings piece: the pair 33 list, the exclusives and the theme and owner art
local pack33 = dofile("data/lib/chaos_pack33_cosmetics.lua")
local taken = {}
for _, p in ipairs(pack33.wings) do taken[p.name] = true taken[p.key] = true end
for _, path in ipairs({"data/scripts/chaos/exclusives_config.lua", "data/lib/chaos_theme_art.lua", "data/lib/chaos_owner_art.lua"}) do
	local h = assert(io.open(path, "r"))
	local text = h:read("*a")
	h:close()
	for key, name in text:gmatch('key = "(wings_%w+)"[^\n]-name = "([^"]+)"') do taken[key] = true taken[name] = true end
	for name in text:gmatch('kind = "wings"[^\n]-\n[^\n]-name = "([^"]+)"') do taken[name] = true end
end
for _, p in ipairs(M.wings) do
	eq(taken[p.name], nil, p.name .. ": no other wings has this name")
	eq(taken[p.key], nil, p.key .. ": no other wings has this key")
end

-- the same rows as the art table (client/tools/sprites/art_import/source_wings.csv: src,srchash,new,key,name,kind,size,...)
local f = io.open("../client/tools/sprites/art_import/source_wings.csv", "r")
eq(f ~= nil, true, "the art table is there")
local rows = {}
for line in f:lines() do
	local id, key, name, size = line:match("^%d+,%x+,(%d+),(%a+),([^,]+),%a+,(%dx%d),")
	if id then rows[#rows + 1] = {look = tonumber(id), key = key, name = name, size = size} end
end
f:close()
eq(#rows, #M.wings, "the art table has the same number of rows")
for i, r in ipairs(rows) do
	eq(r.look, M.wings[i].look, r.key .. ": id")
	eq("wings_" .. r.key, M.wings[i].key, r.key .. ": key")
	eq(r.name, M.wings[i].name, r.key .. ": name")
	eq(M.wings[i].cost, r.size == "3x3" and 250 or 300, r.key .. ": the price follows the drawn canvas")
end

-- every sentence of every description has a pt-BR text
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for _, p in ipairs(M.wings) do
	local el = ({fire = "Fire", water = "Water", wind = "Wind", earth = "Earth", energy = "Storm", light = "Light", dark = "Dark",
		neutral = "Plain"})[p.element]
	eq(el ~= nil, true, p.key .. ": a known element")
	eq(type(pt[el .. " wings, animated"]), "string", p.key .. ": pt-BR text of its element sentence")
end
eq(type(pt["Wear them with any aura, head accessory or cape"]), "string", "the closing sentence has a pt-BR text")

-- ---------------------------------------------------------------- gate off: nothing changes
eq(#M.storeOffers(), 0, "no store offers while off")
local realDofile = dofile
local function withM(path, ...)
	if path == LIB then
		return M
	end
	return realDofile(path, ...)
end
local function shopWith(on)
	M.PAIR74 = on
	dofile = withM
	local ok, shop = pcall(realDofile, "data/scripts/chaos/shop_config.lua")
	dofile = realDofile
	if not ok then error(shop) end
	return shop
end
local function category(shop, name)
	for _, c in ipairs(shop.categories) do
		if c.name == name then return c end
	end
end
local off = shopWith(false)
local baseWings = #category(off, "Wings").offers
for _, o in ipairs(category(off, "Wings").offers) do
	eq(o.id < 122, true, "no source wings offer while off")
end

-- ---------------------------------------------------------------- gate on
M.PAIR74 = true
eq(#M.storeOffers(), 15, "15 offers while on")
local on = shopWith(true)
local wings = category(on, "Wings")
eq(#wings.offers, baseWings + 15, "the Wings category grows by fifteen")
local seen = {}
for i, o in ipairs(wings.offers) do
	eq(seen[o.id], nil, "wings id " .. o.id .. ": one offer") seen[o.id] = true
	if i > baseWings then
		local p = M.wings[i - baseWings]
		eq(o.kind, "wings", p.key .. ": a wings offer")
		eq(o.id, p.id, p.key .. ": the wings.xml id")
		eq(o.cost, p.cost, p.key .. ": the price")
		eq(o.description:find("wings, animated", 1, true) ~= nil, true, p.key .. ": the element sentence")
	end
end
eq(wings.offers[#wings.offers].id, 136, "last source wings 136")
eq(wings.offers[baseWings + 1].id, 122, "first source wings 122")

-- the store with the fifteen validates with the real cores
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
dofile("data/scripts/chaos/class_looks_core.lua")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
local EX = ChaosShopCore.exclusions({classLooks = ChaosClassLooks.looks, classOutfits = Chaos.classes.outfits,
	achievements = achievements, season = dofile("data/scripts/chaos/season_config.lua"),
	seasonpass = dofile("data/scripts/chaos/seasonpass_config.lua"), exclusives = excl})
local problems = ChaosShopCore.validate(on, EX)
eq(#problems, 0, "the store with the source wings validates: " .. table.concat(problems, "; "))
M.PAIR74 = false

print("source_wings_test: " .. n .. " checks, OK")

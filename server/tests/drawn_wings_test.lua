-- Run from the server/ folder: luajit tests/drawn_wings_test.lua (and lua5.3; CI runs both)
-- The six code-drawn wings of client pair 78 (O581 phase 2, data/lib/chaos_drawn_wings.lua and the generated chaos_drawn_wings_ids.lua): the ids and looks
-- follow the old ones in order and match client/tools/sprites/drawn_wings/new_looks.csv, the gate is config.lua chaosClientPair >= 78 (nothing changes
-- below it), and when it is on the store sells the six at the end of Cosmetics > Wings and the shop validates with the real core.
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

local LIB = "data/lib/chaos_drawn_wings.lua"
local M = dofile(LIB)
eq(M.PAIR, 78, "pair 78")
eq(M.PAIR78, false, "no config.lua next to the tests: the gate is off")

-- ---------------------------------------------------------------- the pair record
eq(M.parsePair("chaosClientPair = 78"), 78, "plain")
eq(M.parsePair("x = 1\nchaosClientPair=77 -- shipped\ny = 2\n"), 77, "comment, no spaces, other lines")
eq(M.parsePair("chaosClientPair = \"abc\"\n"), nil, "not a number")
eq(M.parsePair("x = 1\n"), nil, "no key")
eq(M.parsePair(nil), nil, "no text")
eq(M.recordedPair("tests/no_such_config.lua"), nil, "no file")

-- ---------------------------------------------------------------- the six wings
eq(#M.wings, 6, "six wings")
local names = {"Ember Pinions", "Ossuary Wings", "Void Orbit", "Bladefan", "Rimeshard", "Grave Lanterns"}
local keys, elements = {}, {fire = true, water = true, wind = true, earth = true, energy = true, light = true, dark = true, neutral = true}
for i, p in ipairs(M.wings) do
	eq(p.id, 121 + i, p.key .. ": wings.xml ids 122.. after the 121 old wings")
	eq(p.look, 3554 + i, p.key .. ": looks 3555.. after the last outfit of pair 77 (3554)")
	eq(p.name, names[i], p.key .. ": name")
	eq(keys[p.key], nil, p.key .. ": unique key") keys[p.key] = true
	eq(p.key:match("^wings_[%w_]+$") ~= nil, true, p.key .. ": a key")
	eq(elements[p.element], true, p.key .. ": a known element")
	eq(M.piece(p.key), p, p.key .. ": piece by key")
	eq(M.piece(p.id), p, p.key .. ": piece by id")
end
eq(M.piece("wings_nope"), nil, "no such piece")

-- the same rows as the art table (client/tools/sprites/drawn_wings/new_looks.csv: key,name,theme,element,wings,look)
local f = io.open("../client/tools/sprites/drawn_wings/new_looks.csv", "r")
eq(f ~= nil, true, "the table is there")
local rows = {}
for line in f:lines() do
	local key, name, _, element, wings, look = line:match("^([%w_]+),([^,]+),([%w]+),([%w]+),(%d+),(%d+)$")
	if key then rows[#rows + 1] = {key = key, name = name, element = element, id = tonumber(wings), look = tonumber(look)} end
end
f:close()
eq(#rows, 6, "the table has six rows")
for i, r in ipairs(rows) do
	local p = M.wings[i]
	eq(p.key, "wings_" .. r.key, r.key .. ": key")
	eq(p.name, r.name, r.key .. ": name")
	eq(p.element, r.element, r.key .. ": element")
	eq(p.id, r.id, r.key .. ": wings id")
	eq(p.look, r.look, r.key .. ": look")
end

-- no id, look or key of the 121 old wings is taken
local pack33 = dofile("data/lib/chaos_pack33.lua")
local oldId, oldKey, oldName = {}, {}, {}
for _, w in ipairs(pack33.data.wings) do
	oldId[w.id], oldKey[w.key], oldName[w.name] = true, true, true
	eq(w.look < 3555, true, w.key .. ": an old look")
end
for _, p in ipairs(M.wings) do
	eq(oldId[p.id], nil, p.key .. ": wings id not taken by a pair 33 wing")
	eq(oldKey[p.key], nil, p.key .. ": key not taken")
	eq(oldName[p.name], nil, p.key .. ": name not taken")
end
local pairs33 = dofile("data/lib/chaos_pack33_cosmetics.lua")
eq(pairs33.wings[#pairs33.wings].id, 121, "the last old wings id is 121")

-- the price: 300, inside the store's band and the wings' 120-350
eq(M.COST, 300, "300 coins")
local band = dofile("data/scripts/chaos/store_balance_config.lua")
eq(M.COST >= band.cosmetics.min and M.COST <= band.cosmetics.max and M.COST <= 350, true, "the price is in the cosmetics band")

-- every sentence of the description has a pt-BR text
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for _, p in ipairs(M.wings) do
	local d = M.describe(p)
	eq(d:sub(-1), ".", p.key .. ": a sentence")
	for sentence in d:gmatch("([^%.]+)%.?") do
		sentence = sentence:gsub("^%s+", "")
		eq(type(pt[sentence]), "string", p.key .. ": pt-BR text of '" .. sentence .. "'")
	end
end

-- ---------------------------------------------------------------- gate off: nothing changes
eq(#M.storeOffers(), 0, "no store offers while off")
local realDofile = dofile
local function shopWith(on)
	M.PAIR78 = on
	dofile = function(path, ...)
		if path == LIB then
			return M
		end
		return realDofile(path, ...)
	end
	local ok, shop = pcall(realDofile, "data/scripts/chaos/shop_config.lua")
	dofile = realDofile
	if not ok then error(shop) end
	return shop
end
local function wingsOf(shop)
	for _, c in ipairs(shop.categories) do
		if c.name == "Wings" then return c end
	end
end
local off = shopWith(false)
for _, o in ipairs(wingsOf(off).offers) do
	eq(o.kind ~= "wings" or o.id < 122, true, "no drawn wings offer while off")
end

-- ---------------------------------------------------------------- gate on
local on = shopWith(true)
local cat = wingsOf(on)
eq(#cat.offers, #wingsOf(off).offers + 6, "six more offers in Wings")
for i, p in ipairs(M.wings) do
	local o = cat.offers[#cat.offers - 6 + i]
	eq(o.kind, "wings", p.key .. ": a wings offer")
	eq(o.id, p.id, p.key .. ": the wings id, in order at the end of the category")
	eq(o.cost, 300, p.key .. ": 300 coins")
	eq(o.description, M.describe(p), p.key .. ": the description")
end
local seen = {}
for _, o in ipairs(cat.offers) do
	if o.kind == "wings" then
		eq(seen[o.id], nil, "wings " .. o.id .. " offered once")
		seen[o.id] = true
	end
end
local offers = M.storeOffers()
eq(#offers, 6, "storeOffers when on")
eq(M.addStore({categories = {{name = "Other", offers = {}}}}).categories[1].offers[1], nil, "no Wings category, nothing added")

-- the store validates with the real core (as pack33_test.lua does)
dofile("data/scripts/chaos/class_looks_core.lua")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
local EX = ChaosShopCore.exclusions({classLooks = ChaosClassLooks.looks, classOutfits = Chaos.classes.outfits,
	achievements = dofile("data/scripts/chaos/achievements_data.lua"), season = dofile("data/scripts/chaos/season_config.lua"),
	seasonpass = dofile("data/scripts/chaos/seasonpass_config.lua"), exclusives = excl})
local problems = ChaosShopCore.validate(on, EX)
eq(#problems, 0, "the store with the drawn wings validates: " .. table.concat(problems, "; "))
M.PAIR78 = false

print("drawn_wings_test: " .. n .. " checks passed")

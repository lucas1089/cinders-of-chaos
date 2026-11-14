-- Run from the server/ folder: luajit tests/fun_costumes_test.lua (and lua5.3; CI runs both)
-- The twelve fun costumes, the new Dusk Moth look and the round Rune Seal ring of client pair 72 (O566, data/lib/chaos_fun_costumes.lua):
-- the looks follow pair 71's last outfit (3510) in order and match the art table of client/tools/sprites/gen_fun_costumes.py, the
-- gate is config.lua chaosClientPair >= 72 (nothing changes below it), and when it is on the store sells the costumes at the end of
-- Cosmetics > Costumes, the Dusk Moth pet, its store offer and the Rune Seal aura take their new looks.
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

local FUN = "data/lib/chaos_fun_costumes.lua"
local M = dofile(FUN)
eq(M.PAIR, 72, "pair 72")
eq(M.PAIR72, false, "no config.lua next to the tests: the gate is off")

-- ---------------------------------------------------------------- the pair record
eq(M.parsePair("chaosClientPair = 72"), 72, "plain")
eq(M.parsePair("x = 1\nchaosClientPair=71 -- shipped\ny = 2\n"), 71, "comment, no spaces, other lines")
eq(M.parsePair("  chaosClientPair = 55 --"), 55, "leading blanks")
eq(M.parsePair("chaosClientPair = \"abc\"\n"), nil, "not a number")
eq(M.parsePair("x = 1\n"), nil, "no key")
eq(M.parsePair(nil), nil, "no text")
eq(M.recordedPair("tests/no_such_config.lua"), nil, "no file")

-- ---------------------------------------------------------------- the looks and outfits
eq(#M.looks, 14, "14 looks: 12 costumes, the moth, the ring")
local byLook, keys = {}, {}
for i, l in ipairs(M.looks) do
	eq(l.look, 3510 + i, l.key .. ": looks follow pair 71's 3510 outfits in order")
	eq(keys[l.key], nil, l.key .. ": unique key") keys[l.key] = true
	byLook[l.look] = l
end
eq(M.moth.old, 213, "the stock look of the moth")
eq(byLook[M.moth.look].key, "dusk_moth", "the new moth look is the dusk_moth row")
eq(M.seal.old, 2186, "the old Rune Seal look")
eq(byLook[M.seal.look].key, "rune_seal", "the new ring look is the rune_seal row")
eq(#M.outfits, 12, "12 costumes")
local used, okeys, names = {}, {}, {}
for _, o in ipairs(M.outfits) do
	eq(okeys[o.key], nil, o.key .. ": unique outfit key") okeys[o.key] = true
	eq(names[o.name], nil, o.name .. ": unique name") names[o.name] = true
	eq(o.male, o.female, o.key .. ": one look for both sexes")
	eq(byLook[o.male] ~= nil and byLook[o.male].name == o.name, true, o.key .. ": a look of the list, the same name")
	used[o.male] = true
	eq(o.category, "Costumes", o.key .. ": sold in Costumes")
	eq(o.cost, 300, o.key .. ": 300 coins like the pair 37 costumes")
	eq(#o.desc > 20 and o.desc:sub(-1) ~= ".", true, o.key .. ": a description, a sentence with no full stop")
	eq(o.desc:find("glide", 1, true), nil, o.key .. ": it animates, no glide")
end
for _, l in ipairs(M.looks) do
	eq(used[l.look] == true, l.key ~= "dusk_moth" and l.key ~= "rune_seal", l.key .. ": every costume look is worn by an outfit")
end

-- the same rows as the art table (client/tools/sprites/art_import/fun_costumes.csv: new,key,name,kind,...)
local f = io.open("../client/tools/sprites/art_import/fun_costumes.csv", "r")
eq(f ~= nil, true, "the art table is there")
local rows = {}
for line in f:lines() do
	local id, key, name = line:match("^(%d+),([%w_]+),([^,]+),")
	if id then rows[#rows + 1] = {look = tonumber(id), key = key, name = name} end
end
f:close()
eq(#rows, #M.looks, "the art table has the same number of rows")
for i, r in ipairs(rows) do
	eq(r.look, M.looks[i].look, r.key .. ": id")
	eq(r.key, M.looks[i].key, r.key .. ": key")
	eq(r.name, M.looks[i].name, r.key .. ": name")
end

-- every sentence of every description has a pt-BR text
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for _, o in ipairs(M.outfits) do
	eq(type(pt[o.desc]), "string", o.key .. ": pt-BR text of its description")
	eq(#pt[o.desc] > 10, true, o.key .. ": the pt-BR text is not empty")
end
eq(type(pt["One look for both sexes"]), "string", "the closing sentence has a pt-BR text")

-- ---------------------------------------------------------------- gate off: nothing changes
eq(#M.storeOffers("Costumes"), 0, "no store offers while off")
eq(M.mothLook(), 213, "the moth keeps look 213 while off")
eq(M.sealLook(), 2186, "the Rune Seal keeps look 2186 while off")
local realDofile = dofile
local function withM(path, ...)
	if path == FUN then
		return M
	end
	return realDofile(path, ...)
end
local function shopWith(on)
	M.PAIR72 = on
	dofile = withM
	local ok, shop = pcall(realDofile, "data/scripts/chaos/shop_config.lua")
	dofile = realDofile
	if not ok then error(shop) end
	return shop
end
local function petsWith(on)
	M.PAIR72 = on
	dofile = withM
	local ok, cfg = pcall(realDofile, "data/scripts/chaos/pets_config.lua")
	dofile = realDofile
	if not ok then error(cfg) end
	return cfg
end
local function sealWith(on)
	M.PAIR72 = on
	dofile = withM
	local ok, art = pcall(realDofile, "data/lib/chaos_theme_art.lua")
	dofile = realDofile
	if not ok then error(art) end
	for _, e in ipairs(art.exclusives) do
		if e.key == "aura_runeseal" then return e end
	end
end
local function mothOffer(shop)
	for _, c in ipairs(shop.categories) do
		for _, o in ipairs(c.offers or {}) do
			if o.unlock == "petDuskMoth" then return o end
		end
	end
end
local function species(cfg, key)
	for _, s in ipairs(cfg.species) do
		if s.key == key then return s end
	end
end
local off = shopWith(false)
for _, c in ipairs(off.categories) do
	if c.name == "Costumes" then
		eq(#c.offers, 6, "six pair 37 costumes only while off")
		for _, o in ipairs(c.offers) do
			eq(o.looktype < 3511, true, "no fun costume offer while off")
		end
	end
end
eq(mothOffer(off).look, 213, "the store offer shows look 213 while off")
eq(species(petsWith(false), "dusk_moth").look, 213, "the pet shows look 213 while off")
local sealOff = sealWith(false)
eq(sealOff.look, 2186, "the Rune Seal exclusive keeps 2186 while off")
eq(sealOff.id, 32, "aura id 32")

-- ---------------------------------------------------------------- gate on
M.PAIR72 = true
eq(#M.storeOffers("Costumes"), 12, "12 offers while on")
local on = shopWith(true)
local cats, order = {}, {}
for i, c in ipairs(on.categories) do
	cats[c.name] = c
	order[c.name] = i
end
eq(cats["Costumes"].parent, "Cosmetics", "Costumes stays a subcategory of Cosmetics")
eq(order["Costumes"], order["Outfits"] + 1, "Costumes still right after Outfits")
eq(#cats["Costumes"].offers, 18, "six pair 37 costumes and twelve fun costumes")
local seen = {}
for i, o in ipairs(cats["Costumes"].offers) do
	eq(seen[o.key], nil, o.name .. ": unique store key") seen[o.key] = true
	eq(o.kind, "outfit", o.name .. ": an outfit offer")
	eq(o.looktype, o.lookfemale, o.name .. ": one look for both sexes")
	eq(o.key, "outfit:" .. o.looktype, o.name .. ": the store key")
	eq(o.cost, 300, o.name .. ": 300 coins")
	eq(o.looktype >= 3511, i > 6, o.name .. ": the fun costumes come after the six of pair 37")
	eq(o.description:sub(-#". One look for both sexes."), ". One look for both sexes.", o.name .. ": the closing sentence")
end
eq(cats["Costumes"].offers[7].name, "Volt Fizz Can", "first fun costume")
eq(cats["Costumes"].offers[18].name, "Chicken Suit", "last fun costume")
eq(mothOffer(on).look, M.moth.look, "the store offer shows the new moth")
eq(mothOffer(on).cost, 400, "its price is unchanged")
local pets = petsWith(true)
eq(species(pets, "dusk_moth").look, 3523, "the pet shows the new moth")
eq(species(pets, "dusk_moth").source.store, "petDuskMoth", "the pet id and store unlock stay")
eq(sealWith(true).look, 3524, "the Rune Seal exclusive shows the round ring")
eq(sealWith(true).id, 32, "the aura id stays 32")
M.PAIR72 = false

print("fun_costumes_test: " .. n .. " checks, OK")

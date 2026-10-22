-- Run from the server/ folder: luajit tests/pack37_looks_test.lua (and lua5.3; CI runs both)
-- The moon outfits and costumes of client pair 37 (data/lib/chaos_pack37_looks.lua): the looks follow pair 36's last
-- outfit (2667) in order, every outfit names looks of the list, and the store gets them only while the switch is on
-- (the moon outfits at the end of Outfits, the costumes in a new Costumes category right after it).
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

local M = dofile("data/lib/chaos_pack37_looks.lua")
eq(M.PAIR37, true, "the pair 37 switch is on (pair 37 on windows-assets since 2026-10-22)")

-- ---------------------------------------------------------------- the looks and outfits
eq(#M.looks, 14, "14 looks")
local byLook, keys = {}, {}
for i, l in ipairs(M.looks) do
	eq(l.look, 2667 + i, l.key .. ": looks follow pair 36's 2667 outfits in order")
	eq(keys[l.key], nil, l.key .. ": unique key") keys[l.key] = true
	byLook[l.look] = l
end
eq(#M.outfits, 10, "10 outfits: four moon outfits, six costumes")
local used, okeys = {}, {}
for _, o in ipairs(M.outfits) do
	eq(okeys[o.key], nil, o.key .. ": unique outfit key") okeys[o.key] = true
	for _, look in ipairs({o.male, o.female}) do
		eq(byLook[look] ~= nil, true, o.key .. ": look " .. look .. " is a pair 37 look")
		eq(byLook[look].name, o.name, o.key .. ": the look's name")
		used[look] = true
	end
	eq(o.category == "Outfits" or o.category == "Costumes", true, o.key .. ": sold in Outfits or Costumes")
	eq(o.category == "Outfits", o.male ~= o.female, o.key .. ": the moon outfits have a male and a female look")
	eq(o.cost == 750 or o.cost == 300, true, o.key .. ": a placeholder price")
	eq(#o.desc > 10, true, o.key .. ": a description")
end
for _, l in ipairs(M.looks) do
	eq(used[l.look], true, l.key .. ": every look is worn by an outfit")
end

-- ---------------------------------------------------------------- forced off: nothing in the store
M.PAIR37 = false
local realDofile = dofile
local function withM(path, ...)
	if path == "data/lib/chaos_pack37_looks.lua" then
		return M
	end
	return realDofile(path, ...)
end
dofile = withM
local shopOff = realDofile("data/scripts/chaos/shop_config.lua")
dofile = realDofile
for _, c in ipairs(shopOff.categories) do
	eq(c.name ~= "Costumes", true, "no Costumes category while off")
	for _, o in ipairs(c.offers or {}) do
		eq(o.kind ~= "outfit" or (o.looktype or 0) < 2668, true, "no pair 37 outfit offer while off")
	end
end
eq(#M.storeOffers("Outfits") + #M.storeOffers("Costumes"), 0, "no store offers while off")

-- ---------------------------------------------------------------- forced on
M.PAIR37 = true
dofile = withM
local shop = realDofile("data/scripts/chaos/shop_config.lua")
dofile = realDofile
local cats, order = {}, {}
for i, c in ipairs(shop.categories) do
	cats[c.name] = c
	order[c.name] = i
end
eq(cats["Costumes"] ~= nil, true, "the Costumes category while on")
eq(cats["Costumes"].parent, "Cosmetics", "Costumes: a subcategory of Cosmetics")
eq(order["Costumes"], order["Outfits"] + 1, "Costumes right after Outfits")
eq(#cats["Costumes"].offers, 6, "six costumes")
local moon = 0
for _, o in ipairs(cats["Outfits"].offers) do
	if o.looktype >= 2668 then
		moon = moon + 1
		eq(o.lookfemale, o.looktype + 1, o.name .. ": female look right after the male one")
	end
end
eq(moon, 4, "four moon outfits at the end of Outfits")
for _, o in ipairs(cats["Costumes"].offers) do
	eq(o.kind, "outfit", o.name .. ": an outfit offer")
	eq(o.looktype, o.lookfemale, o.name .. ": one look for both sexes")
	eq(o.key, "outfit:" .. o.looktype, o.name .. ": the store key")
end
local fry = cats["Costumes"].offers[6]
eq(fry.name, "Fry Box Costume", "the fry box is the last costume")
eq(fry.description:find("glides", 1, true) ~= nil, true, "the fry box says it does not animate")

print("pack37_looks_test: " .. n .. " checks, OK")

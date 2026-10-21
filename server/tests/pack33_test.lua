-- Run from the server/ folder: luajit tests/pack33_test.lua (and lua5.3; CI runs both)
-- The wings, head accessories and capes of client pair 33 (data/lib/chaos_pack33.lua, chaos_pack33_cosmetics.lua,
-- data/XML/chaos_auras_pack33.csv): the switch is off until pair 33 is on windows-assets, so the shipped configs name
-- no pair 33 look; the generated data is whole and matches the aura manifest; forced on, the store gets the wings and
-- the two new categories, the six exclusives join their bosses, and both configs validate with the real cores.
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

local M = dofile("data/lib/chaos_pack33.lua")
eq(M.PAIR33, true, "the pair 33 switch is on (pair 33 on windows-assets since 2026-10-21)")

-- ---------------------------------------------------------------- the generated data
local D = M.data
eq(#D.wings, 92, "92 wings") eq(#D.heads, 92, "92 head accessories") eq(#D.capes, 89, "89 capes")
local look, keys = 2385, {}
local costs = {wings = {[250] = true, [300] = true}, heads = {[150] = true, [200] = true}, capes = {[200] = true, [250] = true}}
for _, slug in ipairs({"wings", "heads", "capes"}) do
	for _, p in ipairs(D[slug]) do
		eq(p.look, look, p.key .. ": looks follow the client order") look = look + 1
		eq(keys[p.key], nil, p.key .. ": unique key") keys[p.key] = true
		eq(#p.key <= 40 and p.key:match("^[%w_]+$") ~= nil, true, p.key .. ": an exclusives-safe key")
		eq(costs[slug][p.cost], true, p.key .. ": a price of its list")
		eq(type(p.name) == "string" and #p.name > 0, true, p.key .. ": a name")
	end
end
eq(look - 1, 2657, "the last cosmetic look is 2657 (the kit looks follow)")
for i, p in ipairs(D.wings) do
	eq(p.id, 29 + i, p.key .. ": wings.xml ids 30.. after ours (1..29)")
end
local auras = {}
for _, p in ipairs(D.heads) do auras[#auras + 1] = p end
for _, p in ipairs(D.capes) do auras[#auras + 1] = p end
for i, p in ipairs(auras) do
	eq(p.id, 32 + i, p.key .. ": auras.xml ids 33.. after ours (1..32)")
end
eq(auras[#auras].id <= 255, true, "aura ids fit 1..255 (install_auras.py)")
local f = assert(io.open("data/XML/chaos_auras_pack33.csv", "r"))
local text = f:read("*a")
f:close()
local want = "aura_id,client_id,name\n"
for _, p in ipairs(auras) do
	want = want .. p.id .. "," .. p.look .. "," .. p.name .. "\n"
end
eq(text, want, "chaos_auras_pack33.csv matches the generated data")
-- no aura id or wings id of ours already taken
for _, path in ipairs({"data/XML/chaos_auras.csv", "data/XML/chaos_auras_donor.csv", "data/XML/chaos_auras_exclusive.csv",
	"data/XML/chaos_auras_theme.csv"}) do
	local h = io.open(path, "r")
	if h then
		for line in h:lines() do
			local id = tonumber(line:match("^(%d+),"))
			eq(id == nil or id < 33, true, path .. ": aura " .. tostring(id) .. " below the pair 33 ids")
		end
		h:close()
	end
end
for _, e in ipairs(M.exclusives) do
	eq(M.piece(e.key) ~= nil, true, e.key .. ": an exclusive names a kept piece")
end

-- ---------------------------------------------------------------- forced off: no config names pair 33
M.PAIR33 = false
local offDofile = dofile
dofile = function(path, ...)
	if path == "data/lib/chaos_pack33.lua" then
		return M
	end
	return offDofile(path, ...)
end
local shopOff = dofile("data/scripts/chaos/shop_config.lua")
local exclOff = dofile("data/scripts/chaos/exclusives_config.lua")
dofile = offDofile
for _, c in ipairs(shopOff.categories) do
	eq(c.name ~= "Head Accessories" and c.name ~= "Capes", true, "no pair 33 category while off")
	for _, o in ipairs(c.offers or {}) do
		eq(o.kind ~= "wings" or o.id < 30, true, "no pair 33 wings offer while off")
		eq(o.kind ~= "aura" or o.id < 33, true, "no pair 33 aura offer while off")
	end
end
for _, e in ipairs(exclOff.exclusives) do
	eq(e.look == nil or e.look < 2385, true, "no exclusive names a pair 33 look while off")
end
eq(#M.storeOffers("wings") + #M.storeOffers("heads") + #M.storeOffers("capes"), 0, "no store offers while off")

-- ---------------------------------------------------------------- forced on
M.PAIR33 = true
local realDofile = dofile
dofile = function(path, ...)
	if path == "data/lib/chaos_pack33.lua" then
		return M
	end
	return realDofile(path, ...)
end
local shop = dofile("data/scripts/chaos/shop_config.lua")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
dofile = realDofile
local cats, order = {}, {}
for i, c in ipairs(shop.categories) do
	cats[c.name] = c
	order[c.name] = i
end
eq(cats["Head Accessories"] ~= nil and cats["Capes"] ~= nil, true, "the two new categories while on")
eq(cats["Head Accessories"].parent, "Cosmetics", "Head Accessories: a subcategory of Cosmetics")
eq(cats["Capes"].parent, "Cosmetics", "Capes: a subcategory of Cosmetics")
eq(order["Head Accessories"], order["Auras"] + 1, "Head Accessories right after Auras")
eq(order["Capes"], order["Auras"] + 2, "then Capes")
eq(cats["Head Accessories"].icon.outfit.aura, M.piece("head_bone_crown").look, "category icon: a head accessory")
eq(#cats["Head Accessories"].offers, 90, "90 head accessories sold (2 exclusives)")
eq(#cats["Capes"].offers, 88, "88 capes sold (1 exclusive)")
local newWings = 0
for _, o in ipairs(cats["Wings"].offers) do
	if o.id >= 30 then newWings = newWings + 1 end
end
eq(newWings, 89, "89 pair 33 wings in the Wings category (3 exclusives)")
for _, o in ipairs(cats["Capes"].offers) do
	eq(o.kind, "aura", "a cape is an aura offer")
	eq(o.description:find("aura slot", 1, true) ~= nil, true, "the description says it takes the aura slot")
end
local found = {}
for _, e in ipairs(excl.exclusives) do
	if e.look and e.look >= 2385 then
		found[e.key] = e
	end
end
local sold = {}
for _, c in ipairs(shop.categories) do
	for _, o in ipairs(c.offers or {}) do
		sold[o.kind .. ":" .. tostring(o.id)] = true
	end
end
for _, e in ipairs(M.exclusives) do
	local x = found[e.key]
	eq(x ~= nil, true, e.key .. ": an exclusive when on")
	eq(sold[x.kind .. ":" .. x.id], nil, e.key .. ": not sold")
	local rolled
	for _, b in ipairs(excl.bosses) do
		for _, r in ipairs(b.rewards) do
			if r == e.key then rolled = b.key end
		end
	end
	eq(rolled, e.boss, e.key .. ": rolled by " .. e.boss)
	if x.kind == "aura" then
		eq(text:find("\n" .. x.id .. "," .. x.look .. "," .. x.name .. "\n", 1, true) ~= nil, true,
			e.key .. ": in chaos_auras_pack33.csv")
	end
end
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
local storeList = dofile("data/scripts/chaos/shop_cosmetics.lua")
local storeLooks = {looks = {}, mounts = {}}
for _, e in ipairs(storeList.outfits) do
	storeLooks.looks[e.looktype], storeLooks.looks[e.lookfemale] = true, true
end
for _, e in ipairs(storeList.addons) do
	storeLooks.looks[e.looktype], storeLooks.looks[e.lookfemale] = true, true
end
for _, e in ipairs(storeList.mounts) do
	storeLooks.mounts[e.id] = true
end
local opts = {achievements = achievements, shop = shop, storeLooks = storeLooks,
	cosmetics = dofile("data/scripts/chaos/cosmetics_config.lua"), transmog = dofile("data/scripts/chaos/transmog_config.lua"),
	pets = dofile("data/scripts/chaos/pets_config.lua"), portal = dofile("data/scripts/chaos/townportal_config.lua"),
	frames = ChaosNameplate.FRAMES}
local problems = ChaosExclusivesCore.validate(excl, opts)
eq(#problems, 0, "exclusives with pair 33 validate: " .. table.concat(problems, "; "))
dofile("data/scripts/chaos/class_looks_core.lua")
local EX = ChaosShopCore.exclusions({classLooks = ChaosClassLooks.looks, classOutfits = Chaos.classes.outfits,
	achievements = achievements, season = dofile("data/scripts/chaos/season_config.lua"),
	seasonpass = dofile("data/scripts/chaos/seasonpass_config.lua"), exclusives = excl})
problems = ChaosShopCore.validate(shop, EX)
eq(#problems, 0, "the store with pair 33 validates: " .. table.concat(problems, "; "))
-- the store resolves the preview of an aura offer through auras.xml (client look); the category icon is the look itself
eq(ChaosShopCore.lookOf({kind = "aura", id = 33}, {aura = function(id) return id == 33 and 2477 or 0 end}).look, 2477,
	"an aura offer previews its client look")

print("pack33_test: " .. n .. " checks passed")

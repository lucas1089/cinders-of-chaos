-- Run from the server/ folder: luajit tests/shop_retired_test.lua (and lua5.3; CI runs both)
-- Offers retired from sale (O748, owner 2026-11-24: "Os cortes das asas pode fazer sim"): shop_core.lua C.retiredSet /
-- C.retire and the retired checks of C.validate; shop_config.lua `retired`: the eight wings (Butterfly, Enslaved, Runic,
-- Tidewing, Duskfeather, Emberplume, Wildgrove, Bloodfeather) are in no category, bundle, rotation or sale, so nobody
-- can buy them; an owner keeps them: the wings.xml lines stay (install_outfits.py reads chaos_owner_art.lua storeWings,
-- the base XML holds 11 and 13), the shop never takes a cosmetic back, Runic Wings stays Kaelgor's drop.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/shop_core.lua")
local K = ChaosShopCore

-- ------------------------------------------------------------------ core: retire
local cfg = {
	retired = {"wings:11", "wings:13"},
	groups = {{name = "Cosmetics"}},
	categories = {
		{name = "Wings", parent = "Cosmetics", offers = {
			{kind = "wings", id = 1, cost = 250}, {kind = "wings", id = 11, cost = 200}, {kind = "wings", id = 13, cost = 350}}},
		{name = "Bundles", offers = {
			{kind = "bundle", key = "bundle:x", pct = 20, name = "X", parts = {"wings:1", "wings:13", {kind = "wings", id = 11}}}}}
	},
	storefront = {
		featured = {pool = {"wings:1", "wings:13"}},
		sales = {{offers = {"wings:11", "wings:1"}, pct = 10}},
		new = {{offers = {"wings:13"}}}
	}
}
local bad = K.validate(cfg)
local seen = {}
for _, p in ipairs(bad) do
	if p:find("retired", 1, true) then seen[#seen + 1] = p end
end
eq(#seen, 5, "validate names every retired offer still sold: 2 offers, 2 bundle parts, 1 featured")
eq(K.retire(cfg), 7, "retire takes out 2 offers, 2 bundle parts, 1 featured, 1 sale, 1 new entry")
eq(#cfg.categories[1].offers, 1, "only wings:1 left in Wings")
eq(K.offerKey(cfg.categories[1].offers[1]), "wings:1", "the kept offer")
eq(#cfg.categories[2].offers[1].parts, 1, "the bundle keeps its other part")
eq(table.concat(cfg.storefront.featured.pool, ","), "wings:1", "rotation pool")
eq(table.concat(cfg.storefront.sales[1].offers, ","), "wings:1", "sale list")
eq(#cfg.storefront.new[1].offers, 0, "new list")
local left = 0
for _, p in ipairs(K.validate(cfg)) do
	if p:find("retired", 1, true) then left = left + 1 end
end
eq(left, 0, "nothing retired left after retire")
eq(K.retire(cfg), 0, "a second run takes nothing")
eq(K.retire({categories = {{name = "A", offers = {{kind = "wings", id = 1}}}}}), 0, "no retired list: nothing changes")
check(K.retiredSet({})["wings:11"] == nil, "empty set without a list")

-- ------------------------------------------------------------------ shop_config.lua: the eight wings
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29
local shop = dofile("data/scripts/chaos/shop_config.lua")
local CUT = {"wings:11", "wings:13", "wings:20", "wings:22", "wings:23", "wings:24", "wings:25", "wings:26"}
local retired = K.retiredSet(shop)
for _, k in ipairs(CUT) do
	check(retired[k], k .. " is in shop_config.lua retired")
end
eq(#shop.retired, #CUT, "only the eight approved wings are retired")
local sold = {}
local wingsCat
for _, cat in ipairs(shop.categories) do
	if cat.name == "Wings" then wingsCat = cat end
	for _, o in ipairs(cat.offers or {}) do
		sold[K.offerKey(o)] = true
		for _, p in ipairs(o.kind == "bundle" and o.parts or {}) do
			sold[type(p) == "string" and p or K.offerKey(p)] = true
		end
	end
end
for _, k in ipairs(CUT) do
	check(not sold[k], k .. " is not buyable (no category, no bundle)")
end
for _, k in ipairs(shop.storefront.featured.pool) do
	check(not retired[k], "rotation pool has no retired offer: " .. k)
end
for _, s in ipairs(shop.storefront.sales or {}) do
	for _, k in ipairs(s.offers or {}) do
		check(not retired[k], "sale has no retired offer: " .. k)
	end
end
check(wingsCat ~= nil and #wingsCat.offers > 0, "the Wings category still sells the others")
check(sold["wings:1"] and sold["wings:21"], "Fiery Wings and Jadeleaf Pinions still on sale")
local probs = K.validate(shop)
for _, p in ipairs(probs) do print("problem: " .. p) end
eq(#probs, 0, "shop_config.lua validates")

-- ------------------------------------------------------------------ owners keep and wear them
-- wings.xml: 11 and 13 are base lines (wings 1-15, never rewritten); 22-26 come from chaos_owner_art.lua storeWings
local owner = dofile("data/lib/chaos_owner_art.lua")
check(owner.PAIR26, "pair 26 on: install_outfits.py writes the owner art wings lines")
local ownerIds = {}
for _, w in ipairs(owner.storeWings) do ownerIds[w.id] = true end
for id = 22, 26 do
	check(ownerIds[id], "wings " .. id .. " keeps its wings.xml line (storeWings)")
end
-- Runic Wings: still the boss exclusive of Kaelgor
local theme = dofile("data/lib/chaos_theme_art.lua")
local runic
for _, e in ipairs(theme.exclusives) do
	if e.key == "wings_runic" then runic = e end
end
check(runic and runic.id == 20 and runic.source == "boss", "Runic Wings stays a boss exclusive")
eq(theme.bossRewards.kaelgor, "wings_runic", "Kaelgor still drops Runic Wings")
-- an owner: the engine's list (player:addWings at purchase) is what the outfit window reads; retire never touches a player
local owned = {[11] = true, [23] = true}
local player = {hasWings = function(_, id) return owned[id] == true end}
K.retire(shop)
check(player:hasWings(11) and player:hasWings(23), "an owner of Butterfly and Duskfeather Wings still has and wears them")

print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end

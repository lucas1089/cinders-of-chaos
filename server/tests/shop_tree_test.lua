-- Run from the server/ folder: luajit tests/shop_tree_test.lua (and lua5.3; CI runs both)
-- The store's category tree and clean-up (2026-10-21, owner: "De uma limpada na store do jogo. Separe em categorias e
-- subcategorias. Use o layout do server"): shop_core.lua C.arrange / C.groupsOf / C.addSubcategory / C.search and the
-- tree checks of C.validate; shop_config.lua's tree (the parents, where every category stands); and every offer of the
-- store resolvable: a price, a known id or look (wings, auras and shaders of the base XML and the Chaos blocks,
-- generated outfits and mounts, plate frames that are no exclusives), a service with a handler, an unlock that its
-- system knows, spell skins whose spells a class still casts (after the 15-spell cap), no empty or doubled category,
-- no doubled offer name, and no Depot Tabs while the depot is withdraw-only.

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
local function readFile(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/shop_core.lua")
local K = ChaosShopCore

-- ------------------------------------------------------------------ core: arrange
local list = {
	{name = "Starter"}, {name = "Wings", parent = "Cosmetics"}, {name = "Potions", parent = "Consumables"},
	{name = "Auras", parent = "Cosmetics"}, {name = "Crafting"}, {name = "Runes", parent = "Consumables"}
}
local names = {}
for i, c in ipairs(K.arrange(list)) do names[i] = c.name end
eq(table.concat(names, ","), "Starter,Wings,Auras,Potions,Runes,Crafting", "a parent's subcategories together, at its first one")
eq(#K.arrange({}), 0, "empty list")
names = {}
for i, c in ipairs(K.arrange({{name = "A"}, {name = "B"}})) do names[i] = c.name end
eq(table.concat(names, ","), "A,B", "a flat list stays as it is")

-- ------------------------------------------------------------------ core: groupsOf
local withOffers = K.arrange({
	{name = "Wings", parent = "Cosmetics", offers = {1, 2, 3}}, {name = "Auras", parent = "Cosmetics", offers = {1}},
	{name = "Potions", parent = "Consumables", offers = {1, 2}}, {name = "Crafting", offers = {1}}
})
local g = K.groupsOf(withOffers, {{name = "Consumables", icon = {item = 7590}}, {name = "Unused", icon = {item = 1}}})
eq(#g, 2, "only parents with a subcategory")
eq(g[1].name .. g[1].size .. "/" .. g[1].children, "Cosmetics4/2", "Cosmetics: 4 offers in 2 subcategories")
eq(g[1].icon, nil, "a parent not in groups: no icon (the client takes its first subcategory's)")
eq(g[2].icon and g[2].icon.item, 7590, "the icon of groups")

-- ------------------------------------------------------------------ core: addSubcategory (the way other files add one)
local cfgA = {groups = {{name = "Cosmetics"}}, categories = {
	{name = "Starter"}, {name = "Wings", parent = "Cosmetics"}, {name = "Auras", parent = "Cosmetics"}, {name = "Crafting"}}}
K.addSubcategory(cfgA, "Cosmetics", {name = "Capes", offers = {}}, "Wings")
K.addSubcategory(cfgA, "Cosmetics", {name = "Head Accessories", offers = {}})
names = {}
for i, c in ipairs(cfgA.categories) do names[i] = c.name end
eq(table.concat(names, ","), "Starter,Wings,Capes,Auras,Head Accessories,Crafting", "after a sibling, or after the last one")
eq(cfgA.categories[3].parent, "Cosmetics", "the parent set")
check(not pcall(K.addSubcategory, cfgA, "Nope", {name = "X"}), "an unknown parent is an error")
local cfgB = {groups = {{name = "New Parent"}}, categories = {{name = "Starter"}}}
K.addSubcategory(cfgB, "New Parent", {name = "Child", offers = {}})
eq(cfgB.categories[2].name, "Child", "a parent's first subcategory goes to the end")

-- ------------------------------------------------------------------ core: validate's tree rules
local function problemsOf(c)
	return table.concat(K.validate(c), " | ")
end
check(problemsOf({groups = {{name = "P"}}, categories = {{name = "A", parent = "Q", offers = {}}}}):find("unknown parent Q", 1, true),
	"unknown parent found")
check(problemsOf({groups = {{name = "P"}}, categories = {{name = "A", offers = {}}}}):find("P has no subcategory", 1, true),
	"an empty parent found")
check(problemsOf({groups = {{name = "A"}}, categories = {{name = "A", parent = "A", offers = {}}}}):find("name of a parent", 1, true),
	"a category named like a parent found")
check(problemsOf({categories = {{name = "A", offers = {}}, {name = "A", offers = {}}}}):find("category A twice", 1, true),
	"a doubled category found")
check(problemsOf({categories = {{name = "A", offers = {}}}, storefront = {sales = {{categories = {"Gone"}, pct = 10}}}})
	:find("unknown category Gone", 1, true), "a sale on a category that is gone found")
eq(problemsOf({groups = {{name = "P"}}, categories = {{name = "A", parent = "P", offers = {}}},
	storefront = {sales = {{categories = {"P"}, pct = 10}}}}), "", "a sale may name a parent")

-- ------------------------------------------------------------------ core: search
local view = {
	{name = "This week", endsIn = 100, offers = {{t = "Fiery Wings"}}},
	{name = "Wings", parent = "Cosmetics", offers = {{t = "Fiery Wings"}, {t = "Vampire Wings"}}},
	{name = "Potions", parent = "Consumables", offers = {{t = "100 Great Mana Potions"}, {t = "100 Great Spirit Potions"}}}
}
local function title(e) return e.t end
local hits = K.search(view, "fiery", title)
eq(#hits, 1, "the rotation is skipped")
eq(hits[1].c .. ":" .. hits[1].i, "2:1", "category and offer index")
eq(#K.search(view, "GREAT mana", title), 1, "every word, any case")
eq(#K.search(view, "cosmetics", title), 2, "the parent matches")
eq(#K.search(view, "potions", title, 1), 1, "the limit")
eq(#K.search(view, "   ", title), 0, "no words, no results")
eq(#K.search(view, "dragon", title), 0, "nothing found")
eq(#K.search(view, "%a+", title), 0, "plain text, no patterns")

-- ------------------------------------------------------------------ shop_config.lua: the tree
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29
local cfg = dofile("data/scripts/chaos/shop_config.lua")
local problems = K.validate(cfg)
for _, p in ipairs(problems) do print("problem: " .. p) end
eq(#problems, 0, "shop_config.lua validates")

local PARENT = {
	["Premium & Services"] = {"Premium Time", "Chaos Pact", "Storage & Slots", "Season Pass", "Services", "XP Boosts",
		"Blessings", "World Buffs"},
	["Consumables"] = {"Potions", "Runes", "Training", "Convenience"},
	["Cosmetics"] = {"Outfits", "Outfit Addons", "Mounts", "Wings", "Auras", "Outfit Shaders", "Footprints", "Outlines",
		"Kill Effects", "Spell Effects", "Loot Labels", "Chat Colours", "Name Plates", "Pets", "Appearances",
		"Portal Styles", "Hideout Decorations"}
}
local TOP = {Starter = true, Bundles = true, Crafting = true, ["Themed Sets"] = true}
local byName = {}
for _, c in ipairs(cfg.categories) do byName[c.name] = c end
eq(#cfg.groups, 3, "three parents")
for parent, children in pairs(PARENT) do
	for _, name in ipairs(children) do
		check(byName[name] ~= nil, "category " .. name .. " exists")
		eq(byName[name] and byName[name].parent, parent, name .. " under " .. parent)
	end
end
for _, c in ipairs(cfg.categories) do
	if not c.parent then
		check(TOP[c.name], "a top category: " .. c.name)
	end
end
local order = {}
for i, c in ipairs(K.arrange(cfg.categories)) do order[c.name] = i end
check(order.Starter < order.Bundles and order.Bundles < order["Premium Time"] and order["Premium Time"] < order.Potions and
	order.Potions < order.Outfits and order.Outfits < order.Crafting, "Starter, Bundles, Premium & Services, Consumables, Cosmetics, Crafting")

-- the categories of before the clean-up are gone (renamed, merged or not sold)
for _, gone in ipairs({"Supplies", "Boosts", "Chaos Shaders", "Classes"}) do
	eq(byName[gone], nil, "no category " .. gone .. " any more")
end
-- Depot Tabs: only while the depot takes items
local withdrawOnly = dofile("data/scripts/chaos/stash_config.lua").depot.withdrawOnly == true
eq(byName["Depot Tabs"] ~= nil, not withdrawOnly, "Depot Tabs only while the depot is not withdraw-only")

-- ------------------------------------------------------------------ every offer resolvable
-- the base XML (not in git; client/MANIFEST.md lists it): wings 1-15, auras 1-5, shaders 1-17; the Chaos blocks on top
local WINGS, AURAS, SHADERS = {}, {}, {}
for id = 1, 15 do WINGS[id] = true end
for id = 1, 5 do AURAS[id] = true end
for id = 1, 17 do SHADERS[id] = true end
SHADERS[16] = nil -- green_pixent: not sold (shop_config.lua)
for line in readFile("data/XML/chaos_auras.csv"):gmatch("[^\n]+") do
	local id = tonumber(line:match("^(%d+),"))
	if id then AURAS[id] = true end
end
local owner = dofile("data/lib/chaos_owner_art.lua")
if owner.PAIR26 then
	for _, w in ipairs(owner.storeWings) do WINGS[w.id] = true end
end
local COS = dofile("data/scripts/chaos/shop_cosmetics.lua")
local LOOKS, MOUNTS = {}, {}
for _, e in ipairs(COS.outfits) do LOOKS[e.looktype] = true end
for _, e in ipairs(COS.addons) do LOOKS[e.looktype] = true end
for _, e in ipairs(COS.mounts) do MOUNTS[e.id] = e.clientid end
-- service handlers: shop_services.lua S.services, and the systems that add theirs
local servicesSrc = readFile("data/scripts/chaos/shop_services.lua")
local function serviceKnown(name)
	if servicesSrc:find("\n\t" .. name .. " = ", 1, true) then return true end
	for _, f in ipairs({"pact.lua", "store_food.lua"}) do
		if readFile("data/scripts/chaos/" .. f):find("S.services." .. name .. " =", 1, true) then return true end
	end
	return dofile("data/scripts/chaos/gentledeath_config.lua").eternal.service == name
end
-- unlocks: the systems' store keys
local UNLOCK = {autoSeller = true, rarityAutoloot = true}
for line in readFile("data/scripts/chaos/pets_config.lua"):gmatch("store = \"([%w_]+)\"") do UNLOCK[line] = true end
local tp = dofile("data/scripts/chaos/townportal_config.lua")
for _, s in ipairs(tp.styles or {}) do
	if s.route == "store" then UNLOCK["portal_" .. s.key] = true end
end
local tm = dofile("data/scripts/chaos/transmog_config.lua")
for _, s in ipairs(tm.sets or {}) do
	if s.source == "store" then UNLOCK["transmog_" .. s.key] = true end
end
local cc = dofile("data/scripts/chaos/cosmetics_config.lua")
for _, c in ipairs(cc.cosmetics) do
	if c.source == "store" then UNLOCK["cosmetic_" .. c.key] = true end
end
for _, s in ipairs(cc.outfitShaders and cc.outfitShaders.list or {}) do UNLOCK["cosmetic_" .. s.key] = true end
local ho = dofile("data/scripts/chaos/hideout_config.lua")
for _, d in ipairs(ho.decorations) do
	if d.source and d.source.type == "store" then UNLOCK["hideout_" .. d.key] = true end
end
local sp = dofile("data/scripts/chaos/seasonpass_config.lua")
for _, pass in pairs(sp.passes or {}) do
	if pass.premium and pass.premium.unlock then UNLOCK[pass.premium.unlock] = true end
	for _, p in ipairs(pass.packs or {}) do UNLOCK[p.unlock] = true end
end
local POUCH = dofile("data/scripts/chaos/pouches_config.lua")
local FRAME_SOLD = 13 -- shop_core.lua C.FRAMES 1-13 are the store's, 14-16 exclusives

local keys, total = {}, 0
for _, cat in ipairs(cfg.categories) do
	check(cat.rotationOnly or #cat.offers > 0, "category " .. cat.name .. " has offers")
	check(type(cat.icon) == "table" and (cat.icon.item or cat.icon.outfit), "category " .. cat.name .. " has an icon")
	local seenName = {}
	for _, o in ipairs(cat.offers) do
		total = total + 1
		local key = K.offerKey(o)
		local what = cat.name .. " " .. key
		keys[key] = o
		if o.kind == "bundle" then
			check((type(o.cost) == "number" and o.cost > 0) or (type(o.pct) == "number" and o.pct > 0), what .. ": a price")
			check(type(o.name) == "string" and type(o.icon) == "number", what .. ": a name and an icon")
		else
			check(type(o.cost) == "number" and o.cost > 0 and o.cost % 1 == 0, what .. ": a whole price above 0")
		end
		if o.name then
			check(not seenName[o.name], what .. ": the name " .. o.name .. " twice in the category")
			seenName[o.name] = true
		end
		local k = o.kind
		if k == "bundle" then
			check(#(o.parts or {}) > 0, what .. ": parts (C.validate resolves them)")
		elseif k == "item" then
			check(type(o.id) == "number" and o.id > 0 and (o.count or 1) > 0 and type(o.name) == "string", what .. ": an item")
		elseif k == "wings" then
			check(WINGS[o.id], what .. ": wings that exist")
		elseif k == "aura" then
			check(AURAS[o.id], what .. ": an aura that exists")
		elseif k == "shader" then
			check(SHADERS[o.id] and type(o.name) == "string", what .. ": a shader that exists, with a name")
		elseif k == "outfit" or k == "addons" then
			check(LOOKS[o.looktype] and (o.lookfemale or 0) > 0, what .. ": a generated outfit")
		elseif k == "mount" then
			check(MOUNTS[o.id] and (o.clientid or 0) > 0, what .. ": a generated mount with a look")
		elseif k == "frame" then
			local i = K.frameIndex(o.frame)
			check(i and i <= FRAME_SOLD and type(o.icon) == "number", what .. ": a store plate frame")
		elseif k == "premium" then
			check((o.days or 0) > 0, what .. ": premium days")
		elseif k == "service" then
			check(serviceKnown(o.service), what .. ": a service with a handler")
			check(type(o.name) == "string" and type(o.icon) == "number", what .. ": a name and an icon")
			if o.service == "pouch" then
				check(POUCH.kinds and POUCH.kinds[o.pouch], what .. ": a pouch that exists")
			end
		elseif k == "unlock" then
			check(UNLOCK[o.unlock], what .. ": an unlock its system knows")
			check(type(o.name) == "string" and (type(o.icon) == "number" or type(o.look) == "number"), what .. ": a name and a picture")
		else
			check(false, what .. ": a known kind")
		end
	end
end
check(total > 450, "the store has its offers (" .. total .. ")")
-- the rotation's pool and the bundles name offers that are sold
for _, k in ipairs(cfg.storefront.featured.pool) do
	check(keys[k] ~= nil, "rotation offer " .. k .. " is sold")
end

-- spell skins: every spell they change is still cast by a class (the 15-spell cap retired 68 spells)
local spellsXml = readFile("data/spells/chaos/spells_chaos.xml")
local function spellHasClass(id)
	local body = spellsXml:match('spellid="' .. id .. '"[^>]*>(.-)</instant>')
	return body ~= nil and body:find("<vocation ", 1, true) ~= nil
end
for _, c in ipairs(cc.cosmetics) do
	if c.kind == "spellskin" and c.source == "store" then
		for _, id in ipairs(c.spells or {}) do
			check(spellHasClass(id), "spell skin " .. c.key .. ": spell " .. id .. " is still cast by a class")
		end
	end
end

print(string.format("shop_tree_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end

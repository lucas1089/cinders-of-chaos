-- Find my item (O412): itemsearch_core.lua. Run from server/: luajit tests/itemsearch_test.lua (and lua5.3).
-- The engine side (stash.lua S.find against a mocked engine) is in tests/stash_test.lua.
dofile("data/scripts/chaos/itemsearch_core.lua")
local K = ChaosItemSearchCore
local cfg = dofile("data/scripts/chaos/stash_config.lua").find

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL: " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- folding and queries
eq(K.fold("  Lendária   ESPADA "), "lendaria espada", "accents, case and spaces")
eq(K.fold("Coração\tde Ferro"), "coracao de ferro", "a tab and the cedilla")
eq(K.fold(nil), "", "not a string")
local w = K.query("Fire  Sword", cfg)
check(w and #w == 2 and w[1] == "fire" and w[2] == "sword", "two words")
local none, why = K.query("a", cfg)
check(none == nil and why == "short", "one letter is too short")
none, why = K.query("   ", cfg)
check(none == nil and why == "short", "only spaces")
none, why = K.query(string.rep("x", cfg.maxChars + 1), cfg)
check(none == nil and why == "long", "too long")
eq(#K.query("a b c d e f g h", cfg), cfg.maxWords, "words capped")
check(K.matches({"sw", "fire"}, "fire sword"), "every word, any order")
check(not K.matches({"ice"}, "fire sword"), "a missing word")
check(not K.matches({}, "fire sword"), "no words match nothing")

-- a character: a backpack with a bag with a sword, a quiver of arrows, a purse, an inbox with a parcel, the stash
local function item(name, cid, extra)
	local it = {name = name, cid = cid, count = 1}
	for k, v in pairs(extra or {}) do it[k] = v end
	return it
end
local sword = item("fire sword", 3001, {rarity = 5, words = "Legendary Lendária Attack Speed +5% (T4)"})
local bag = item("bag", 1987, {container = true, kids = {item("worm", 3976, {count = 50}), sword}})
local backpack = item("backpack", 1988, {container = true, kids = {item("gold coin", 2148, {count = 77}), bag}})
local helmet = item("steel helmet", 2457)
local arrows = item("arrow", 2544, {count = 100})
local quiver = item("quiver", 2591, {container = true, kids = {arrows}})
local purse = item("your store inbox", 26052, {container = true, kids = {item("exercise sword", 32124)}})
local parcel = item("parcel", 2595, {container = true, kids = {item("ice sword", 3002)}})
local inbox = item("inbox", 14404, {container = true, kids = {parcel}})
local api = {
	describe = function(it) return it end,
	children = function(it) return it.kids end
}
local places = {
	{kind = "equip", slot = 1, item = helmet},
	{kind = "equip", slot = 3, item = backpack},
	{kind = "equip", slot = 10, item = quiver},
	{kind = "purse", item = purse, name = "Purse"},
	{kind = "inbox", item = inbox, name = "Inbox"},
	{kind = "stash", entries = {
		{name = "magic sword", cid = 3003, count = 1, rarity = 3, words = "Magic Mágica", tab = 105, tabName = "Weapons", row = 9},
		{name = "gold coin", cid = 2148, count = 5000, tab = 1, item = 2148},
		{name = "old relic", cid = 3004, count = 1, tab = 200, old = true, row = 11}
	}}
}

local r = K.search(cfg, K.query("sword", cfg), places, api)
eq(r.total, 4, "four swords: the bag, the purse, the inbox parcel, the stash")
eq(#r.items, 4, "all kept")
local first = r.items[1]
eq(first.loc, "bag", "the carried one first")
eq(first.slot, 3, "in the backpack slot")
eq(#first.path, 1, "one container down") eq(first.path[1], 1, "the bag is the second item of the backpack")
eq(first.at, 1, "the sword is the second item of the bag")
eq(#first.ids, 2, "the ids of the backpack and the bag") eq(first.ids[1], 1988, "backpack") eq(first.ids[2], 1987, "bag")
eq(first.where, "backpack > bag", "where it is")
eq(first.rarity, 5, "its rarity") eq(first.cid, 3001, "its client id")
eq(r.items[2].loc, "purse", "then the purse") eq(r.items[2].where, "Purse", "the purse is named")
eq(r.items[3].loc, "inbox", "then the inbox") eq(r.items[3].where, "Inbox > parcel", "inside the parcel")
eq(r.items[4].loc, "stash", "then the stash") eq(r.items[4].tab, 105, "its tab") eq(r.items[4].row, 9, "its row")
eq(r.items[4].tabName, "Weapons", "the tab name")

r = K.search(cfg, K.query("lendaria", cfg), places, api)
eq(r.total, 1, "a rarity name in pt-BR without the accent") eq(r.items[1].cid, 3001, "the fire sword")
r = K.search(cfg, K.query("attack speed", cfg), places, api)
eq(r.total, 1, "an affix line")
r = K.search(cfg, K.query("helmet", cfg), places, api)
eq(r.items[1].loc, "equip", "an equipped item") eq(r.items[1].slot, 1, "its slot") eq(r.items[1].path, nil, "no path")
r = K.search(cfg, K.query("arrow", cfg), places, api)
eq(r.items[1].loc, "bag", "inside the quiver") eq(r.items[1].slot, 10, "the ammo slot") eq(r.items[1].count, 100, "the count")
r = K.search(cfg, K.query("gold coin", cfg), places, api)
eq(r.total, 2, "the carried gold and the stash stack") eq(r.items[2].item, 2148, "a merged stack names its item id")
eq(r.items[2].row, nil, "no row")
r = K.search(cfg, K.query("relic", cfg), places, api)
eq(r.items[1].old, true, "the Old depot tab")
r = K.search(cfg, K.query("backpack", cfg), places, api)
eq(r.total, 1, "an equipped container is found itself") eq(r.items[1].loc, "equip", "as equipment")
r = K.search(cfg, K.query("dragon", cfg), places, api)
eq(r.total, 0, "nothing") eq(#r.items, 0, "no rows")

-- cap, scan limit, depth
local many = {}
for i = 1, 30 do many[i] = item("rope " .. i, 3003) end
local big = item("loot bag", 1990, {container = true, kids = many})
local small = {max = 10, scanLimit = 3000, maxDepth = 8}
r = K.search(small, {"rope"}, {{kind = "equip", slot = 3, item = big}}, api)
eq(#r.items, 10, "capped at max") eq(r.total, 30, "the total counts every match") eq(r.capped, true, "capped")
r = K.search({max = 200, scanLimit = 12}, {"rope"}, {{kind = "equip", slot = 3, item = big}}, api)
eq(r.scanned, 12, "the walk stops at the scan limit") eq(r.capped, true, "and says so")
local deep = item("leaf", 1)
local chain = deep
for i = 1, 6 do chain = item("box " .. i, 1000 + i, {container = true, kids = {chain}}) end
r = K.search({maxDepth = 3}, {"leaf"}, {{kind = "equip", slot = 3, item = chain}}, api)
eq(r.total, 0, "deeper than maxDepth is not walked")
r = K.search({maxDepth = 8}, {"leaf"}, {{kind = "equip", slot = 3, item = chain}}, api)
eq(r.total, 1, "within maxDepth") eq(#r.items[1].path, 5, "five containers below the slot's") eq(#r.items[1].ids, 6, "six ids")

-- pages
local res = {items = {}, total = 45}
for i = 1, 45 do res.items[i] = {n = i} end
local p = K.page(res, 2, 20)
eq(p.page, 2, "page two") eq(p.pages, 3, "three pages") eq(#p.items, 20, "twenty rows") eq(p.items[1].n, 21, "from row 21")
p = K.page(res, 9, 20)
eq(p.page, 3, "past the end: the last page") eq(#p.items, 5, "five rows")
p = K.page(res, "x", 20)
eq(p.page, 1, "not a number: page one")
p = K.page({items = {}, total = 0}, 1, 20)
eq(p.pages, 1, "an empty result has one page") eq(#p.items, 0, "no rows")

-- a page fits the packet limit: 20 rows with the longest texts
local fat = {}
for i = 1, 20 do
	fat[i] = {loc = "bag", slot = 3, path = {1, 2, 3, 4, 5, 6, 7}, at = 19, ids = {11111, 22222, 33333, 44444, 55555, 66666, 77777, 88888},
		where = string.rep("w", cfg.whereChars), name = string.rep("n", cfg.nameChars), count = 2000000000, cid = 65535,
		rarity = 10, unique = true}
end
local function enc(v)
	if type(v) == "table" then
		local parts = {}
		for k, x in pairs(v) do parts[#parts + 1] = '"' .. tostring(k) .. '":' .. enc(x) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return type(v) == "string" and ('"' .. v .. '"') or tostring(v)
end
check(#enc({make = "found", q = string.rep("q", cfg.maxChars), page = 10, pages = 10, total = 3000, shown = 200, capped = true,
	items = fat}) < 8192, "a full page stays under 8192 bytes")

print(string.format("itemsearch_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

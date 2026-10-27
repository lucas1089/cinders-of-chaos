-- Run from the server/ folder: luajit tests/itemfinder_test.lua (and lua5.3; CI runs both)
-- Item finder: the opcode is free; the texts (percent, counts, gold); the parsers (shop lists, NPC files, NPC scripts,
-- the spawn file, hunting bands, nearest town); the index built from mocked sources (monster loot with child loot and
-- the loot rate, hidden items and sources, unknown ids, duplicates, recipes both ways, NPC shops, store, Gambler);
-- the sources on the real configs (rewards of every system without errors, hidden achievements left out, the store,
-- the Gambler, professions, salvage, gems); search ranking and paging; an item and the pages of one section; the
-- request dispatch; and the engine part (itemfinder.lua) against a mocked engine: the build from monsters, files and
-- the bestiary, the answers on the opcode, Chaos.sendChunked for long answers, the rate limit (ratelimit.lua).

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/itemfinder_core.lua")
dofile("data/scripts/chaos/itemfinder_sources.lua")
local K, S = ChaosItemFinderCore, ChaosItemFinderSources
local cfg = dofile("data/scripts/chaos/itemfinder_config.lua")

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = copy(v)
	end
	return o
end

-- ---------------------------------------------------------------- the opcode
eq(cfg.opcode, 155, "opcode")
eq(ChaosOpcodes.itemFinder, 155, "ChaosOpcodes.itemFinder")
for key, v in pairs(ChaosOpcodes) do
	if key ~= "itemFinder" then
		check(v ~= 155, "155 is not taken by ChaosOpcodes." .. key)
	end
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(v ~= cfg.opcode, "not a reference server opcode " .. v)
end
for _, v in ipairs({144, 145, 146, 210, 212, 213, 230, 246}) do
	check(v ~= cfg.opcode, "not a base client ExtendedIds value " .. v)
end
check(CHAOS_ADMIN_OPCODE == nil or CHAOS_ADMIN_OPCODE ~= 155, "not the admin opcode")

-- ---------------------------------------------------------------- texts
eq(K.norm("  Orb of  FATE! "), "orb of fate", "norm")
eq(K.norm("Gravewarden's Verdict"), "gravewarden s verdict", "norm apostrophe")
eq(K.int(1234567), "1,234,567", "int")
eq(K.int(999), "999", "int small")
eq(K.pct(100000), "100%", "pct 100")
eq(K.pct(12500), "12.5%", "pct 12.5")
eq(K.pct(1000), "1%", "pct 1")
eq(K.pct(50), "0.05%", "pct 0.05")
eq(K.pct(1), "0.001%", "pct 0.001")
eq(K.pct(0.5), "<0.001%", "pct tiny")
eq(K.pct(0), "0%", "pct 0")
eq(K.per10k(2500), "25%", "per10k")
eq(K.countText(1, 1), nil, "count one")
eq(K.countText(1, 3), "x1-3", "count range")
eq(K.countText(5), "x5", "count fixed")
eq(K.gold(1500), "1,500 gold", "gold")
eq(K.toInt("3", 1), 3, "toInt")
eq(K.toInt(2.5), nil, "toInt fraction")
eq(K.toInt(0, 1), nil, "toInt below")

-- ---------------------------------------------------------------- parsers
do
	local l = K.parseShopList("amphora,2023,4,0;\n\t\t\tarmor rack kit,6114,90;\n bad;nope,x,1; zero,0,5;cheap,2160,0")
	eq(#l, 3, "shop list entries")
	eq(l[1].id, 2023, "shop list id")
	eq(l[1].price, 4, "shop list price")
	eq(l[2].price, 90, "shop list second")
	eq(l[3].price, 0, "a free item is kept")
	local c = K.parseShopList("bag of runes,1987,2268,500;", true)
	eq(c[1].id, 2268, "container list: the item")
	eq(c[1].price, 500, "container list: the price")

	local npc = K.parseNpcXml([[<?xml version="1.0" encoding="UTF-8"?>
<npc name="Agnes Emberhand" script="Felicia.lua" walkinterval="2000">
	<parameters>
		<parameter key="module_shop" value="1" />
		<parameter key="shop_buyable" value="
			amphora,2023,4,0;
			barrel kit,3919,12;" />
		<parameter key="shop_sellable" value="vial,2006,5;" />
		<parameter key="shop_buyable_containers" value="bag of runes,1987,2268,500;" />
	</parameters>
</npc>]])
	eq(npc.name, "Agnes Emberhand", "npc name (the renamed one inside the file)")
	eq(npc.script, "Felicia.lua", "npc script")
	eq(#npc.buy, 3, "npc buy list (with the container)")
	eq(#npc.sell, 1, "npc sell list")
	eq(npc.sell[1].id, 2006, "npc sells to")

	local buy, sell = K.parseNpcScript([[
local shopModule = ShopModule:new()
shopModule:addBuyableItem({'spellbook'}, 2175, 150, 'spellbook')
shopModule:addBuyableItem({'small health'}, 8704, 20, 1, 'small health potion')
shopModule:addBuyableItem(nil, 2160, 10000)
shopModule:addBuyableItemContainer({'bp sd'}, 2003, 2268, 2000, 1, 'backpack of sudden death')
shopModule:addSellableItem({'vial', 'flask'}, 7636, 5, 'empty potion flask')
]])
	eq(#buy, 4, "script: three buyables and a container")
	eq(buy[2].id, 8704, "script: buy id")
	eq(buy[2].price, 20, "script: buy price")
	eq(buy[3].id, 2160, "script: nil names")
	eq(buy[4].id, 2268, "script: container content")
	eq(buy[4].price, 2000, "script: container price")
	eq(#sell, 1, "script: sellable")
	eq(sell[1].price, 5, "script: sell price")

	local b2, s2 = K.parseNpcScript([[
local function getTable()
	local list = {
		{name="Didgeridoo", id=3952, buy=5000},
		{name="meat", id=2666, sell=2},
		{name = "both", id = 2672, buy = 10, sell = 3}
	}
	return list
end
openShopWindow(cid, getTable(player), onBuy, onSell)]])
	eq(#b2, 2, "own trade window: buy rows")
	eq(#s2, 2, "own trade window: sell rows")
	eq(b2[1].price, 5000, "own trade window: price")
	local b3 = K.parseNpcScript("local t = {{id = 5, buy = 7}}") -- no trade window: quest tables are not shops
	eq(#b3, 0, "tables without a trade window are not read")

	local spawns = K.parseSpawnNpcs([[<?xml version="1.0"?>
<spawns>
	<spawn centerx="1000" centery="2000" centerz="7" radius="2">
		<monster name="Rat" x="1" y="1" z="7" spawntime="60" />
		<npc name="Agnes" x="-1" y="2" z="7" spawntime="60" />
	</spawn>
	<spawn centerx="3000" centery="3000" centerz="6" radius="1">
		<npc name="Tom" x="0" y="0" spawntime="60" />
	</spawn>
</spawns>]])
	eq(#spawns, 2, "spawn npcs")
	eq(spawns[1].x, 999, "spawn x relative to the centre")
	eq(spawns[1].y, 2002, "spawn y")
	eq(spawns[2].z, 6, "spawn z from the centre when absent")

	local bands = K.huntBands({{k = "hunt", n = "Hunting: Wyrmblood Warmaster, Ghoul (level 70-90)"},
		{k = "hunt", n = "Hunting: Ghoul (level 20-40)"}, {k = "shop", n = "Ghoul (shop)"}})
	eq(bands["wyrmblood warmaster"], "70-90", "hunting band")
	eq(bands["ghoul"], "20-40", "the lowest band wins")

	local towns = {{name = "Brassgate", x = 100, y = 100, z = 7}, {name = "Saltgrave", x = 500, y = 500, z = 7}}
	eq(K.placeText({x = 120, y = 90, z = 7}, towns, 60), "in Brassgate", "in a town")
	eq(K.placeText({x = 300, y = 320, z = 7}, towns, 60), "near Saltgrave", "near a town")
	eq(K.placeText({x = 1, y = 1, z = 7}, {}, 60), nil, "no towns")
	eq(K.placesText({{x = 100, y = 100}, {x = 101, y = 100}, {x = 500, y = 500}}, towns, 60, 1), "in Brassgate (+1)",
		"places: each town once, more counted")
end

-- ---------------------------------------------------------------- the index from mocked sources
local NAMES = {
	[2160] = "crystal coin", [2148] = "gold coin", [2666] = "meat", [29856] = "Orb of Upheaval", [29857] = "Orb of Fate",
	[2400] = "magic sword", [2401] = "staff", [5000] = "dragon scale", [5001] = "dragon shield", [5002] = "dragon scale mail",
	[5003] = "dragonfly", [5004] = "scale", [6000] = "secret wand", [7000] = "bag", [7001] = "golden ring",
	[2023] = "amphora", [3919] = "barrel kit", [2006] = "vial", [9001] = "orb", [9002] = "sword of orbs"
}
local function info(id)
	local n = NAMES[id]
	if not n then
		return nil
	end
	return n, id - 100
end

local function newIndex(conf)
	local idx = K.new(conf or cfg, info)
	return idx, function(kind, id, row) return K.add(idx, id, kind, row) end
end

do
	local c = copy(cfg)
	c.hidden.items = {6000}
	c.hidden.sources = {"Cursed Altar"}
	local idx, emit = newIndex(c)
	S.monsters({
		{name = "Dragon", level = 120, band = "100-140", places = {"near Brassgate (underground, floor -1)"}, loot = {
			{itemId = 2148, chance = 100000, maxCount = 80},
			{itemId = 5000, chance = 25000, maxCount = 3},
			{itemId = 6000, chance = 50000}, -- hidden item
			{itemId = 99999, chance = 50000}, -- unknown id
			{itemId = 7000, chance = 50000, childLoot = {{itemId = 7001, chance = 10000}}}}},
		{name = "Dragon Lord", boss = true, level = 300, loot = {{itemId = 5000, chance = 80000}, {itemId = 2400, chance = 0}}},
		{name = "Rat", loot = {{itemId = 2666, chance = 60000}}}
	}, emit, {rate = 2})
	emit("reward", 5000, {n = "Cursed Altar", d = "a hidden source"})
	emit("reward", 5000, {n = "Daily reward", d = "day 1"})
	check(not emit("reward", 5000, {n = "Daily reward", d = "day 1"}), "a duplicate row is refused")
	check(not emit("nokind", 5000, {n = "x"}), "an unknown kind is refused")
	check(not emit("reward", 5000, {d = "no name"}), "a row without a name is refused")
	-- recipes both ways
	S.crafting({
		mining = {{id = 5001, level = 20, cost = 3000, count = 1, storage = 0,
			materials = {{id = 5000, count = 5}, {id = 2148, count = 50}}}},
		weaponsmith = {{id = 2400, level = 50, cost = 0, count = 1, storage = 7100, storageText = "Learned from the smith",
			materials = {{id = 5000, count = 2}}},
			{id = 5002, level = 1, cost = 0, materials = {{id = 88888, count = 1}}}} -- unknown material: no recipe
	}, cfg, emit)
	emit("reward", 5002, {n = "Chest"})
	S.npcs({{name = "Agnes", places = "in Brassgate", buy = {{id = 2023, price = 4}}, sell = {{id = 5000, price = 120}}}}, emit)
	local st = K.finish(idx)

	local scale = idx.items[5000]
	eq(#scale.rows.monster, 2, "two monsters drop it")
	eq(scale.rows.monster[1].n, "Dragon Lord", "highest chance first")
	eq(scale.rows.monster[1].v, "100%", "chance x the loot rate, capped at 100%")
	eq(scale.rows.monster[2].v, "50%", "25% x rate 2")
	eq(scale.rows.monster[2].c, "x1-3", "count range")
	eq(scale.rows.monster[2].d, "level 100-140, near Brassgate (underground, floor -1)", "monster detail: band and place")
	eq(scale.rows.monster[1].d, "level 300", "boss detail (the flag is b)")
	eq(scale.rows.monster[1].b, true, "boss flag")
	eq(#scale.rows.reward, 1, "the hidden source is left out")
	eq(#scale.rows.usedin, 2, "used in two recipes")
	eq(scale.rows.usedin[1].n, "dragon shield", "recipe use: the product's name")
	eq(scale.rows.usedin[1].l, 5001, "recipe use: the product's server id")
	eq(scale.rows.usedin[1].i, 4901, "recipe use: the product's client id")
	eq(scale.rows.usedin[1].v, "x5", "recipe use: how many")
	eq(scale.rows.sellto[1].v, "120 gold", "an NPC buys it")
	eq(idx.items[6000], false, "the hidden item has no record")
	eq(idx.items[99999], false, "an unknown id has no record")
	eq(idx.items[7001].rows.monster[1].v, "10%", "child loot: 50% x 10% x rate 2")
	eq(idx.items[2400].rows.monster, nil, "a 0% loot entry is not shown")
	local b = K.brief(idx, 5000)
	eq(#b.s, 2, "brief: two sources")
	eq(b.s[1].n, "Dragon Lord", "brief: the best monster first")
	eq(b.s[1].k, "monster", "brief: its kind")
	eq(b.e, nil, "brief: no effort line for a common drop")
	local child = K.brief(idx, 7001)
	check(child.e and math.abs(child.e.p - 0.1) < 1e-9 and child.e.m == "Dragon", "brief: a rare monster drop names the monster")
	eq(K.brief(idx, 5001).e, nil, "brief: a crafted item has no effort line")
	eq(table.concat(b.u.n, "|"), "dragon shield|magic sword", "brief: what it is used in, lowest level first")
	eq(b.u.m, nil, "brief: no other product")
	eq(K.brief(idx, 5001).u, nil, "brief: an item used in nothing has no used-in part")
	local shield = idx.items[5001].rows.craft[1]
	eq(shield.n, "Mining table", "station name")
	eq(shield.d, "level 20, 3,000 gold", "recipe detail")
	eq(#shield.m, 2, "materials")
	eq(shield.m[1].n, "dragon scale", "material name")
	eq(shield.m[1].c, 5, "material count")
	eq(shield.m[2].i, 2048, "material client id")
	eq(idx.items[2400].rows.craft[1].d, "level 50, Learned from the smith", "a recipe to learn says so")
	eq(idx.items[5002].rows.craft, nil, "a recipe with an unknown material is not shown")
	eq(idx.items[2023].rows.shop[1].d, "in Brassgate", "NPC shop place")
	eq(st.items, 9, "items with rows: " .. st.items)
	check(st.rows > 10, "rows counted")
	eq(idx.byCid[4900], scale, "client id map")

	-- search ranking
	local r = K.search(idx, "dragon scale", 1)
	eq(r.rows[1].name, "dragon scale", "exact name first")
	eq(r.rows[2].name, "dragon scale mail", "then names starting with it")
	r = K.search(idx, "drag", 1)
	eq(r.total, 3, "prefix: three dragon items with rows (" .. r.total .. ")")
	eq(r.rows[1].name, "dragon scale", "ties: shorter name first")
	r = K.search(idx, "scale mail", 1)
	eq(r.rows[1].name, "dragon scale mail", "every word starts a word")
	r = K.search(idx, "ale", 1)
	eq(r.total, 2, "contains")
	r = K.search(idx, "x", 1)
	eq(r.total, 0, "too short")
	eq(K.search(idx, "  ", 1).total, 0, "blank")
	r = K.search(idx, "coin", 1)
	eq(r.rows[1].name, "gold coin", "a word of the name")
	check(r.rows[1].kinds[1] == "monster", "kinds of a result in section order")
	eq(K.search(idx, string.rep("a", 200), 1).q, string.rep("a", cfg.maxQuery), "the query is cut")
end

-- paging and ranking on many items
do
	local many = {}
	for i = 1, 40 do
		many[10000 + i] = string.format("blade %02d", i)
	end
	many[10100] = "blade"
	many[10101] = "old blade"
	many[10102] = "bladed whip"
	many[10103] = "a sword with no blade word" -- contains "blade" as a whole word, not at the start
	many[10104] = "bastard sword"
	local idx = K.new(cfg, function(id) return many[id], id end)
	for id in pairs(many) do
		K.add(idx, id, "reward", {n = "Chest"})
	end
	K.add(idx, 10001, "shop", {n = "Agnes", v = "1 gold"})
	K.finish(idx)
	local r = K.search(idx, "blade", 1)
	eq(r.total, 44, "all blades")
	eq(r.pages, math.ceil(44 / cfg.perPage), "pages")
	eq(#r.rows, cfg.perPage, "a full page")
	eq(r.rows[1].name, "blade", "exact first")
	eq(r.rows[2].name, "blade 01", "then the shortest prefix match")
	local last = K.search(idx, "blade", r.pages)
	eq(#last.rows, 44 - (r.pages - 1) * cfg.perPage, "the last page")
	eq(last.rows[#last.rows].name, "a sword with no blade word", "a word match after the prefix matches")
	eq(K.search(idx, "blade", 999).p, r.pages, "a page past the end is the last")
	eq(K.search(idx, "blade", -3).p, 1, "a page below 1 is the first")
	eq(K.search(idx, "blade", "x").p, 1, "a bad page is the first")
	r = K.search(idx, "bl sw", 1)
	eq(r.rows[1].name, "a sword with no blade word", "word prefixes in any order")
	eq(K.search(idx, "lade old", 1).total, 1, "every word contained")

	-- an item and its sections
	local rows = {}
	for i = 1, 37 do
		rows[i] = {n = string.format("Monster %02d", i), v = "1%", o = i}
	end
	local idx2 = K.new(cfg, function(id) return id == 1 and "orb" or nil, 77 end)
	for _, row in ipairs(rows) do
		K.add(idx2, 1, "monster", row)
	end
	K.add(idx2, 1, "store", {n = "Orb pack", v = "10 Chaos Coins", c = "x5"})
	K.add(idx2, 1, "reward", {n = "Daily reward", d = "day 2"})
	K.finish(idx2)
	local item = K.lookup(idx2, 1)
	eq(item.name, "orb", "item name")
	eq(item.total, 39, "item rows")
	eq(#item.secs, 3, "three sections")
	eq(item.secs[1].k, "monster", "sections in config order")
	eq(item.secs[2].k, "reward", "reward before store")
	eq(item.secs[3].k, "store", "store")
	eq(#item.secs[1].rows, cfg.rowsPerPage, "first page of a section")
	eq(item.secs[1].pages, math.ceil(37 / cfg.rowsPerPage), "section pages")
	eq(item.secs[1].rows[1].o, nil, "the sort number is not sent")
	local p3 = K.pageOf(idx2, idx2.items[1], "monster", 3)
	eq(#p3.rows, 37 - 2 * cfg.rowsPerPage, "last section page")
	eq(p3.rows[1].n, string.format("Monster %02d", 2 * cfg.rowsPerPage + 1), "section page order")
	eq(K.lookup(idx2, nil, 77).id, 1, "by client id")
	local none = K.lookup(idx2, nil, 4242)
	eq(none.none, true, "an item without sources")
	eq(none.cid, 4242, "keeps the client id")

	-- the dispatch
	local a, d = K.request(K.new(cfg, info), "search", {q = "orb"})
	eq(a, "busy", "busy before the index is ready")
	a, d = K.request(idx2, "search", {q = "orb", p = 1})
	eq(a, "results", "search answer")
	eq(d.total, 1, "search answer rows")
	a, d = K.request(idx2, "search", {q = {1}})
	eq(d.total, 0, "a query that is not text")
	a, d = K.request(idx2, "item", {id = 1})
	eq(a, "item", "item answer")
	eq(d.secs[1].k, "monster", "item answer sections")
	a, d = K.request(idx2, "page", {id = 1, k = "monster", p = 2})
	eq(a, "page", "page answer")
	eq(d.p, 2, "page number")
	eq(K.request(idx2, "page", {id = 1, k = "shop", p = 1}), nil, "a section the item has not")
	eq(K.request(idx2, "page", {id = 1, k = 5}), nil, "a kind that is not text")
	eq(K.request(idx2, "nope", {}), nil, "an unknown action")
	eq(K.request(idx2, nil, {}), nil, "no action")
	a, d = K.request(idx2, "item", "garbage")
	eq(d.none, true, "garbage data")
end

-- ---------------------------------------------------------------- what a material is for (K.brief u)
-- owner 2026-10-22, on the Seraphic Charged Stone that showed only "Drops from": "Coloque pra que servem"
do
	local idx, emit = newIndex()
	S.crafting({
		armorsmith = {
			{id = 5001, level = 35, cost = 0, materials = {{id = 9001, count = 3}}},
			{id = 5002, level = 35, cost = 0, materials = {{id = 9001, count = 5}}},
			{id = 5002, level = 40, cost = 0, materials = {{id = 9001, count = 9}}}, -- the same product again: one name
			{id = 2400, level = 35, cost = 0, materials = {{id = 9001, count = 1}}},
			{id = 2401, level = 10, cost = 0, materials = {{id = 9001, count = 1}}}}
	}, cfg, emit)
	K.finish(idx)
	local b = K.brief(idx, 9001)
	check(b ~= nil, "brief: an item used in recipes and from nowhere still has a brief")
	eq(b and #b.s, 0, "brief: no sources")
	eq(b and b.e, nil, "brief: no effort line")
	eq(b and table.concat(b.u.n, "|"), "staff|dragon scale mail", "brief: the first two products (lowest level, then name)")
	eq(b and b.u.m, 2, "brief: two more products (one name counted once)")
	eq(b and #b.u.n, K.USED_SHOWN, "brief: K.USED_SHOWN products named")
end

-- the real base recipes as installed (data/items/base_recipes.csv, patch_base_recipes.py): the Seraphic and Dawnforged
-- stones and emblems are used in their own sets, the Myst ones never in another set's piece
do
	local Crafting = {}
	local f = assert(io.open("data/items/base_recipes.csv", "r"))
	f:read("*l")
	for line in f:lines() do
		local id, count, cost, level, book, mats = line:match("^(%d+),(%d+),(%d+),(%d+),(%w+),(.*)$")
		if id then
			local m = {}
			for n, mid in mats:gmatch("(%d+)x(%d+)") do
				m[#m + 1] = {id = tonumber(mid), count = tonumber(n)}
			end
			Crafting[book] = Crafting[book] or {}
			table.insert(Crafting[book], {id = tonumber(id), count = tonumber(count), cost = tonumber(cost),
				level = tonumber(level), materials = m})
		end
	end
	f:close()
	local SET = {[29869] = "Seraphic Helmet", [29870] = "Seraphic Tabard", [29871] = "Seraphic Greaves",
		[29872] = "Seraphic Boots", [29873] = "Seraphic Quiver", [29874] = "Seraphic Bleeder", [29875] = "Seraphic Piercer",
		[29876] = "Seraphic Necklace", [29877] = "Seraphic Ring", [29925] = "Seraphic Emblem"}
	local idx = K.new(cfg, function(id) return SET[id] or ("item " .. id), id end)
	S.crafting(Crafting, cfg, function(kind, id, row) return K.add(idx, id, kind, row) end)
	K.finish(idx)
	local b = K.brief(idx, 29922)
	check(b ~= nil and b.u ~= nil, "Seraphic Charged Stone: a used-in part")
	eq(b and b.u and b.u.n[1], "Seraphic Emblem", "Seraphic Charged Stone: the emblem first (level 30)")
	eq(b and b.u and b.u.n[2], "Seraphic Bleeder", "Seraphic Charged Stone: then the level 35 pieces by name")
	eq(b and b.u and b.u.m, 8, "Seraphic Charged Stone: nine pieces and the emblem")
	for _, mat in ipairs({29922, 29923, 29925, 29926, 29900, 29908, 29909, 29910, 29911, 29912, 29913}) do
		check(idx.items[mat] and idx.items[mat].rows.usedin, "boss material " .. mat .. " is used in a recipe")
	end
	for _, row in ipairs(idx.items[29921].rows.usedin) do
		check(not (row.l >= 29869 and row.l <= 29890), "the Myst Charged Stone makes no Seraphic or Dawnforged piece: " .. row.l)
	end
end

-- ---------------------------------------------------------------- the sources on the real configs
do
	local ids = {}
	local function realInfo(id)
		return "item " .. id, id
	end
	local idx = K.new(cfg, realInfo)
	local function emit(kind, id, row)
		ids[kind] = (ids[kind] or 0) + 1
		return K.add(idx, id, kind, row)
	end
	local base = "data/scripts/chaos/"
	local D = {
		daily = Chaos.daily, dailyStreak = dofile(base .. "daily_config.lua"), bounty = dofile(base .. "bounty_config.lua"),
		rift = dofile(base .. "rift_config.lua"), tower = Chaos.tower, worldBoss = Chaos.worldBoss,
		invasion = dofile(base .. "invasion_config.lua"), arena = dofile(base .. "arena_config.lua"),
		battleground = dofile(base .. "battleground_config.lua"), guildboss = dofile(base .. "guildboss_config.lua"),
		descent = dofile(base .. "descent_config.lua"), raid = dofile(base .. "raid_config.lua"), dungeons = Chaos.dungeons,
		goblin = dofile(base .. "treasure_goblin_config.lua"), achievements = dofile(base .. "achievements_data.lua"),
		factions = dofile(base .. "factions_config.lua"), uber = dofile(base .. "uber_config.lua"),
		pocketBoss = dofile(base .. "pocketboss_config.lua"),
		-- the Conquest vendor (conquest.lua): two offers of its catalog
		conquest = {cfg = dofile(base .. "conquest_config.lua"), offers = {{id = 2412, level = 60, price = 690},
			{id = 36659, level = 650, price = 1580, always = true}}},
		candlemarks = dofile(base .. "candlemarks_config.lua"), gems = dofile("data/lib/chaos_gems_config.lua"),
		mentor = dofile(base .. "mentor_config.lua"), tales = dofile(base .. "tales_config.lua"),
		embercache = dofile(base .. "embercache_config.lua"), siege = dofile(base .. "siege_config.lua"),
		leaderboard = dofile(base .. "leaderboard_config.lua"), community = dofile(base .. "community_config.lua"),
		referral = dofile(base .. "referral_config.lua"), trials = dofile(base .. "trials_config.lua"),
		charms = dofile(base .. "charms_config.lua"), nemesis = dofile(base .. "nemesis_config.lua"),
		newplayer = dofile(base .. "newplayer_config.lua"), seasonpass = dofile(base .. "seasonpass_config.lua"),
		potions = dofile(base .. "potions_config.lua"),
		journey = dofile(base .. "season_journey_config.lua")
	}
	local storeCtx = {pouches = dofile(base .. "pouches_config.lua"), storeFood = dofile(base .. "store_food_config.lua")}
	local errors = S.rewards(D, emit)
	for _, e in ipairs(errors) do
		print("  rewards " .. e.key .. ": " .. e.message)
	end
	eq(#errors, 0, "every reward source reads its real config")
	do
		local function vendorRow(id)
			for _, r in ipairs((K.rec(idx, id) or {rows = {}}).rows.shop or {}) do
				if r.n == "Conquest vendor" then
					return r
				end
			end
		end
		local r = vendorRow(2412)
		check(r ~= nil and r.v == "690 tokens", "a unique is listed at the Conquest vendor")
		check(r ~= nil and r.d:find("from level 10", 1, true) ~= nil, "with its level band: " .. tostring(r and r.d))
		check(vendorRow(36659) ~= nil and vendorRow(36659).d:find("always", 1, true) ~= nil, "the Monk's fist weapon always")
		check(vendorRow(D.rift.omen.key.id) ~= nil, "Omen Keys of a chosen kind")
		check(vendorRow(D.uber.items.shards.storm.id) ~= nil, "Ascended Shards of a chosen kind")
	end
	local gems = dofile("data/lib/chaos_gems_config.lua")
	S.lootLayer(dofile(base .. "loot_config.lua"), gems, {
		{id = 8209, name = "Soulreaper", minTier = "legendary", chance = 150, monsters = {"demon", "hellhound"}},
		{id = 8210, name = "Bossblade", minTier = "boss", chance = 50, bossOnly = true}
	}, emit, function(key) return key:gsub("^%l", string.upper) end)
	local shopCfg = dofile(base .. "shop_config.lua")
	S.store(shopCfg, emit, storeCtx)
	S.gamble(dofile(base .. "gamble_config.lua"), emit)
	S.professions(dofile(base .. "professions_config.lua"), emit)
	dofile("data/lib/chaos_crafting.lua")
	local function orbId(key)
		for _, o in ipairs(ChaosCrafting.config.orbs) do
			if o.key == key then
				return o.id
			end
		end
	end
	S.salvage(dofile(base .. "salvage_config.lua"), orbId, emit)
	S.gemCombining(gems, emit)
	K.finish(idx)

	-- the tooltip's short sources (K.brief): a unique by luck, with its chance per legendary kill
	local soul = K.brief(idx, 8209)
	check(soul ~= nil and soul.s[1].n == "Unique drop", "brief: the unique drop row")
	check(soul and soul.e and soul.e.w == "legendary", "brief: effort per legendary kill")
	check(soul and soul.e and math.abs(soul.e.p - 150 * 4 / 10000) < 1e-9, "brief: 150 x tierMult 4 per 10000")
	local boss = K.brief(idx, 8210)
	check(boss and boss.e and boss.e.w == "boss", "brief: a boss-only unique counts boss kills")
	eq(K.brief(idx, 1), nil, "brief: an item without rows")
	-- the global table comes before a monster that lists the item (live test winpkg-35)
	do
		local g = K.new(cfg, realInfo)
		K.add(g, 29851, "monster", {n = "Embermaw Archon", v = "50%", o = -50000, p = 0.5})
		S.lootLayer({currency = {entries = {{id = 29851, weight = 20, count = {1, 2}, chance = {normal = 30, boss = 3500}}},
			guaranteed = {boss = 1}}}, nil, {}, function(kind, id, row) return K.add(g, id, kind, row) end)
		K.finish(g)
		local b = K.brief(g, 29851)
		eq(b.s[1].n .. " (" .. b.s[1].v .. ")", "Any monster (global drop, about 1 in 330 kills)", "brief: the global drop first")
		eq(b.s[2].n, "Embermaw Archon", "brief: then the monster")
		eq(K.lookup(g, 29851).secs[1].k, "drop", "the item page: the global drop section first")
	end
	-- live test winpkg-35: "Drops from: Abyssal Crab (100%), Abyssal Crab (100%)": a monster listing the item twice
	do
		local dup = K.new(cfg, realInfo)
		K.add(dup, 2148, "monster", {n = "Abyssal Crab", v = "100%", c = "1-100", o = -100000, p = 1})
		K.add(dup, 2148, "monster", {n = "Abyssal Crab", v = "100%", c = "1-50", o = -100000, p = 1})
		K.add(dup, 2148, "monster", {n = "Rat", v = "40%", o = -40000, p = 0.4})
		K.finish(dup)
		local b = K.brief(dup, 2148)
		eq(#b.s, 2, "brief: two sources")
		eq(b.s[1].n .. "|" .. b.s[2].n, "Abyssal Crab|Rat", "brief: a monster once, the next one after it")
	end
	eq(K.brief(nil, 8209), nil, "brief: no index")

	local function has(id, kind, name, label)
		local r = idx.items[id]
		for _, row in ipairs(r and r.rows[kind] or {}) do
			if row.n == name then
				return true
			end
		end
		check(false, label .. " (" .. id .. " " .. kind .. " " .. name .. ")")
		return false
	end
	has(29856, "reward", "Daily reward", "daily reward cycle")
	has(29856, "reward", "Pocket boss", "world boss pocket orbs")
	has(Chaos.worldBoss.bosses[1].gear[1], "drop", Chaos.worldBoss.bosses[1].name .. " (pocket)", "world boss pocket set piece")
	has(29856, "reward", "Login streak", "login streak")
	has(29856, "reward", "Bounty contract", "bounty contract orbs")
	has(29851, "reward", "Bounty weekly chest", "bounty weekly extra")
	has(29856, "reward", "Rift chest", "rift chest orbs")
	has(10155, "reward", "Rift completion", "rift key from a completed rift")
	has(10155, "drop", "Any monster", "rift key from monsters")
	has(32072, "craft", "Omen binding", "omen key from fragments")
	has(32071, "usedin", "item 32072", "omen fragment used for the key")
	has(8209, "reward", "Infinity Tower", "tower milestone")
	has(29857, "reward", "Infinity Tower season", "tower season chest")
	has(29857, "reward", "World boss", "world boss")
	has(29855, "reward", "Invasion", "invasion top 3")
	has(28095, "shop", "Wandering Merchant", "the world event merchant")
	has(29856, "reward", "Arena", "arena")
	has(7591, "store", "Battleground vendor", "battleground vendor")
	has(32051, "use", "Guild boss ember stone", "guild boss donation")
	has(29858, "reward", "The Descent", "descent orbs")
	has(7402, "reward", "The Descent", "descent unique")
	has(2498, "reward", "The Ashen Sepulchre", "raid unique")
	has(2160, "reward", "Bones Dungeon", "dungeon loot")
	has(32051, "reward", "Shard Goblin", "treasure goblin shards")
	has(32076, "craft", "Ascended binding", "ascended sigil")
	has(32073, "reward", "Omen guardian", "ascended shard")
	has(32091, "use", "Warden Ysolde", "faction token turn-in")
	has(29857, "craft", "Warden Ysolde", "faction recipe output")
	has(29856, "shop", "Warden Ysolde", "faction orbs")
	has(29857, "drop", "Any monster", "Chaos currency drop")
	has(32001, "drop", "Any monster", "gem drop")
	has(32002, "craft", "Gem combining", "gem combining")
	has(32001, "usedin", "item 32002", "gem used for the next tier")
	has(8209, "drop", "Unique drop", "unique with its monsters")
	eq(idx.items[8209].rows.drop[1].d, "Demon, Hellhound; legendary and better", "unique: its monsters and tier")
	eq(idx.items[8210].rows.drop[1].d, "any monster; bosses only", "boss-only unique")
	has(8472, "store", "100 Great Spirit Potions", "store item")
	has(8472, "store", "Novice Pack", "store bundle part")
	has(2398, "gamble", "The Gambler", "the Gambler's pool")
	has(32351, "gather", "Delving", "gathering")
	has(32351, "sellto", "Material Broker", "the Material Broker buys materials")
	has(2553, "shop", "Material Broker", "the Material Broker sells tools")
	has(32051, "craft", "Salvage", "rune shards from salvage")
	has(29851, "craft", "Salvage bench", "an orb from shards")
	has(32051, "usedin", "item 29851", "shards used for an orb")
	-- live test winpkg-35: the Everfull Ration (a store service, not an item offer) had no source
	has(storeCtx.storeFood.item.id, "store", "Everfull Ration", "the Everfull Ration in the store")
	has(storeCtx.pouches.kinds.loot.id, "store", "Loot Bag", "a store pouch")
	has(storeCtx.pouches.kinds.loot.id, "store", "Adventurer Pack", "a pouch as a bundle part")
	do
		local r = idx.items[storeCtx.storeFood.item.id].rows.store[1]
		eq(r.d, "Store > Convenience", "the store row names its category")
		eq(r.v, "100 Chaos Coins", "and its price")
	end
	has(29851, "store", "3 Orbs of Awakening", "the Candlemark shop")
	has(D.gems.firstId, "store", "Chipped Gem", "a Candlemark gem")
	has(7618, "store", "50 Health Potions", "the Mentor Marks shop")
	has(7618, "reward", "Mentor program", "the mentor graduation")
	has(29856, "reward", "Quest: The Bone Choir", "a tale's reward")
	has(24692, "reward", "Ember Cache", "the Ember Cache")
	has(29857, "reward", "Guild siege", "the siege")
	has(29857, "reward", "Weekly leaderboards", "the leaderboards")
	has(29857, "reward", "Community goal", "the community goal")
	has(7620, "reward", "Referral", "the referral gift")
	has(29857, "reward", "Class trials", "the class trials")
	has(32301, "reward", "Charm drop", "a charm")
	has(32309, "craft", "Charm salvage", "the charm shard")
	has(D.nemesis.rewards.trophy.id, "reward", "Nemesis", "the nemesis trophy")
	has(27990, "reward", "Level gift", "a level gift")
	has(2120, "reward", "Starter kit", "the starter kit")
	has(32085, "reward", "Starter kit", "the Everfull health potion")
	has(32086, "reward", "Starter kit", "the Everfull mana potion")
	has(32257, "store", "Raid vendor", "the raid vendor (found by the audit)")

	-- the global drop tables (live test winpkg-35: an Orb of Awakening from a Rat; the tooltip said "Drops from: Embermaw
	-- Archon (50%), Inferno Juggernaut (50%)"): every entry of every global table has an "Any monster" row with its odds
	do
		local function globalRow(id)
			for _, r in ipairs((idx.items[id] or {rows = {}}).rows.drop or {}) do
				if r.n == "Any monster" and tostring(r.v):find("global drop", 1, true) then
					return r
				end
			end
		end
		local lootCfg = dofile(base .. "loot_config.lua")
		for _, e in ipairs(lootCfg.currency.entries) do
			check(globalRow(e.id) ~= nil, "global drop row of " .. e.name)
		end
		for i = 0, #gems.types * #gems.tiers - 1 do
			check(globalRow(gems.firstId + i) ~= nil, "global drop row of gem " .. (gems.firstId + i))
		end
		check(globalRow(D.rift.key.itemId) ~= nil, "global drop row of the Rift Key")
		local awakening = globalRow(29851)
		eq(awakening and awakening.v, "global drop, about 1 in 330 kills", "Orb of Awakening: 30 per 10000 normal kills")
		local total = 0
		for _, e in ipairs(lootCfg.currency.entries) do
			total = total + e.weight
		end
		check(awakening and awakening.d:find("legendary and boss monsters always draw one entry by weight (this one 20 of " ..
			total .. ")", 1, true) ~= nil, "and its weight in the guaranteed draw: " .. tostring(awakening and awakening.d))
		eq(globalRow(32255).v, "global drop, about 1 in 10,000 magic monster kills", "Orb of Ruin: none from normal monsters")
		check(globalRow(D.rift.key.itemId).v:find("level " .. Chaos.huntingLevel(60) .. "+", 1, true) ~= nil, "the key's level gate")
		check(globalRow(gems.firstId + 4).v:find("level " .. Chaos.huntingLevel(300) .. "+", 1, true) ~= nil, "a perfect gem's level gate: " .. globalRow(gems.firstId + 4).v)
	end
	has(2160, "reward", "Ashen Pass", "the season pass")
	has(29855, "reward", "The Ashen Pilgrimage", "the season journey")

	-- audit: every item a config hands out (any {kind = "item" | "items", id} entry, any {id, count} or {id, n} entry of
	-- an `items`, `equip`, `backpack` or `everfull` list, the store's item, bundle and service offers) has at least one row. A new
	-- reward in a config that the item finder does not read fails here: add its source to itemfinder_sources.lua.
	do
		local given = {}
		local function give(id, where)
			id = tonumber(id)
			if id and id > 0 and not given[id] then
				given[id] = where
			end
		end
		local LISTS = {items = true, equip = true, backpack = true, everfull = true}
		-- t: a config table; isEntry: t is an entry of an `items` / `equip` / ... list; isList: t is such a list
		local function scan(t, where, seen, isEntry, isList)
			if type(t) ~= "table" or seen[t] then
				return
			end
			seen[t] = true
			if (t.kind == "item" or t.kind == "items") and tonumber(t.id) then
				give(t.id, where)
			end
			if isEntry and (tonumber(t.id) or (type(t[1]) == "number" and type(t[2]) == "number")) then
				give(t.id or t[1], where)
			end
			for k, v in pairs(t) do
				-- secrets: hidden achievements are never listed
				if type(v) == "table" and not v.hidden then
					scan(v, where, seen, isList == true and type(k) == "number", LISTS[k] == true)
				end
			end
		end
		local skip = {conquest = true} -- a mocked catalog
		for key, t in pairs(D) do
			if not skip[key] then
				scan(t, key, {}, false, false)
			end
		end
		for _, cat in ipairs(shopCfg.categories) do
			for _, o in ipairs(cat.offers or {}) do
				scan(o, "store " .. tostring(cat.name), {}, false, false)
				local sid = o.kind == "service" and S.serviceItem(o.service, o.pouch or o.upgrade, storeCtx)
				if sid then
					give(sid, "store service " .. o.service)
				end
				for _, part in ipairs(o.kind == "bundle" and o.parts or {}) do
					local id = type(part) == "string" and part:match("^item:(%d+)")
					give(id, "store bundle " .. tostring(o.name))
				end
			end
		end
		local missing, total = {}, 0
		for id, where in pairs(given) do
			total = total + 1
			local r = idx.items[id]
			if not r or r.n == 0 then
				missing[#missing + 1] = id .. " (" .. where .. ")"
			end
		end
		table.sort(missing)
		check(total >= 90, "the audit finds the configs' items (" .. total .. ")")
		check(#missing == 0, "every item a config gives has a source; missing: " .. table.concat(missing, ", "))
	end
	-- achievements: the visible ones with items are listed, hidden ones never
	local ach = D.achievements
	local visible, hidden = 0, 0
	for _, a in ipairs(ach.list) do
		if a.reward and a.reward.items then
			if a.hidden then
				hidden = hidden + 1
			else
				visible = visible + 1
			end
		end
	end
	check(visible > 0, "achievements with item rewards exist")
	local listed, secret = 0, 0
	for _, r in pairs(idx.items) do
		for _, row in ipairs(r and r.rows.reward or {}) do
			if row.n:find("^Achievement: ") then
				listed = listed + 1
				for _, a in ipairs(ach.list) do
					if a.hidden and row.n == "Achievement: " .. a.name then
						secret = secret + 1
					end
				end
			end
		end
	end
	check(listed >= visible, "visible achievement rewards listed (" .. listed .. ")")
	eq(secret, 0, "hidden achievements are never listed (" .. hidden .. " hidden with items)")
	-- a broken config stops only its own rows
	local broken = copy(D)
	broken.raid = {uniques = 5}
	broken.arena = {reward = {win = {{id = 29856, count = 1}}}}
	local n0 = 0
	local errs = S.rewards(broken, function() n0 = n0 + 1 end)
	eq(#errs, 1, "one broken config, one error")
	eq(errs[1] and errs[1].key, "raid", "the broken one is named")
	check(n0 > 50, "the others still give rows")
end

-- ---------------------------------------------------------------- the engine part against a mocked engine
do
	local function encode(v)
		local t = type(v)
		if t == "table" then
			if next(v) == nil or v[1] ~= nil then
				local parts = {}
				for _, x in ipairs(v) do
					parts[#parts + 1] = encode(x)
				end
				return "[" .. table.concat(parts, ",") .. "]"
			end
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = tostring(k)
			end
			table.sort(keys)
			local parts = {}
			for _, k in ipairs(keys) do
				parts[#parts + 1] = string.format("%q:%s", k, encode(v[k]))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		elseif t == "string" then
			return string.format("%q", v)
		elseif t == "number" or t == "boolean" then
			return tostring(v)
		end
		return "null"
	end
	local registry = {}
	json = {
		encode = function(v)
			local s = encode(v)
			registry[s] = copy(v)
			return s
		end,
		decode = function(s) return copy(registry[s]) end
	}
	MESSAGE_INFO_DESCR = 3
	local events, globals, talks = {}, {}, {}
	CreatureEvent = function(name)
		local e = {register = function() end, type = function() end}
		events[name] = e
		return e
	end
	GlobalEvent = function(name)
		local e = {register = function() end}
		globals[name] = e
		return e
	end
	TalkAction = function(words)
		local t = {separator = function() end, register = function() end}
		talks[words] = t
		return t
	end
	local fakeNow = 100000
	os.mtime = function() return fakeNow end
	dofile("data/scripts/chaos/ratelimit.lua")

	-- the files: a spawn file, two NPC files and a shared script
	local dir = os.tmpname()
	os.remove(dir)
	os.execute("mkdir -p '" .. dir .. "/scripts'")
	local function write(path, text)
		local f = assert(io.open(path, "wb"))
		f:write(text)
		f:close()
	end
	write(dir .. "/spawn.xml", [[<spawns>
<spawn centerx="105" centery="100" centerz="7" radius="1"><npc name="Agnes" x="0" y="0" z="7" /></spawn>
<spawn centerx="900" centery="900" centerz="7" radius="1"><npc name="Agnes" x="0" y="0" z="7" /><npc name="Quiet" x="1" y="0" z="7" /></spawn>
</spawns>]])
	write(dir .. "/Agnes.xml", [[<npc name="Agnes Emberhand" script="runes.lua"><parameters>
<parameter key="shop_buyable" value="amphora,2023,4;" /><parameter key="shop_sellable" value="dragon scale,5000,120;" /></parameters></npc>]])
	write(dir .. "/Quiet.xml", [[<npc name="Quiet One" script="none.lua"></npc>]])
	write(dir .. "/scripts/runes.lua", "shopModule:addBuyableItem({'vial'}, 2006, 10)")
	write(dir .. "/monsters.xml", "")

	local nameOf = {[2148] = "gold coin", [5000] = "dragon scale", [2023] = "amphora", [2006] = "vial",
		[29856] = "Orb of Upheaval", [29857] = "Orb of Fate"}
	ItemType = function(id)
		return {getId = function() return nameOf[id] and id or 0 end, getName = function() return nameOf[id] or "" end,
			getClientId = function() return id + 1 end}
	end
	local loots = {dragon = {{itemId = 5000, chance = 25000, maxCount = 2}, {itemId = 2148, chance = 100000, maxCount = 50}}}
	MonsterType = function(name)
		local key = tostring(name):lower()
		if not loots[key] then
			return nil
		end
		return {name = function() return "Dragon" end, getLoot = function() return loots[key] end,
			isBoss = function() return false end, experience = function() return 700 end}
	end
	Game = {getTowns = function()
		return {{getName = function() return "Brassgate" end, getTemplePosition = function() return {x = 100, y = 100, z = 7} end}}
	end, getMonsterTypes = function() return {} end}
	configManager = {getNumber = function() return 3 end, getString = function() return "map" end}
	configKeys = {RATE_LOOT = 1, MAP_NAME = 2}
	ChaosBestiary = {cat = function()
		return {list = {{name = "Dragon", key = "dragon", level = 120, boss = false, areas = {{110, 100, 8, 30}}},
			{name = "Training Dummy", key = "training dummy", level = 1}}}
	end}
	dofile("data/scripts/chaos/bestiary_core.lua")
	ChaosPoi = {all = {{k = "hunt", n = "Hunting: Dragon (level 100-140)"}}}
	ChaosLoot, ChaosLootConfig, ChaosGemsConfig, ChaosShopConfig, Crafting = nil, nil, nil, nil, nil

	local printed = {}
	local realPrint = print
	print = function(s) printed[#printed + 1] = tostring(s) end
	dofile("data/scripts/chaos/itemfinder.lua")
	local F = ChaosItemFinder
	F.cfg.spawnFile = dir .. "/spawn.xml"
	F.cfg.npcDir = dir .. "/"
	F.cfg.monstersXml = dir .. "/monsters.xml"
	check(globals.ChaosItemFinderStartup ~= nil, "startup event")
	globals.ChaosItemFinderStartup.onStartup()
	print = realPrint
	local idx = F.index
	check(idx and idx.ready, "built at startup")
	local scale = idx.items[5000]
	eq(scale.rows.monster[1].v, "75%", "loot rate 3 from config.lua")
	eq(scale.rows.monster[1].d, "level 100-140, in Brassgate (underground, floor -1)", "bestiary place and hunting band")
	eq(#scale.rows.monster, 1, "the dummy is left out")
	eq(scale.rows.sellto[1].n, "Agnes Emberhand", "the NPC's own (renamed) name")
	eq(scale.rows.sellto[1].d, "in Brassgate, near Brassgate", "every place of the NPC")
	eq(idx.items[2006].rows.shop[1].v, "10 gold", "the NPC's script shop")
	check(idx.stats.ms >= 0 and idx.stats.kb ~= nil, "build time and memory measured")
	local summary = false
	for _, line in ipairs(printed) do
		if line:find("%[Chaos itemfinder%] %d+ items") then
			summary = true
		end
	end
	check(summary, "the build prints its numbers")

	-- the opcode
	local sent = {}
	local player = {id = 7}
	function player:getId() return self.id end
	function player:sendExtendedOpcode(op, payload) sent[#sent + 1] = {op = op, payload = payload} return true end
	local ext = events.ChaosItemFinderExtended
	local function ask(action, data)
		local before = #sent
		ext.onExtendedOpcode(player, 155, json.encode({action = action, data = data}))
		local out = {}
		for i = before + 1, #sent do
			out[#out + 1] = sent[i]
		end
		return out
	end
	local got = ask("search", {q = "drag"})
	eq(#got, 1, "one answer")
	eq(got[1].op, 155, "on the item finder opcode")
	local m = json.decode(got[1].payload)
	eq(m.action, "results", "search results")
	eq(m.data.rows[1].name, "dragon scale", "found by name")
	got = ask("item", {id = 5000})
	eq(#got, 0, "a second request at once is dropped (rate limit)")
	fakeNow = fakeNow + cfg.requestMs
	got = ask("item", {id = 5000})
	eq(#got, 1, "after the interval it is answered")
	m = json.decode(got[1].payload)
	eq(m.data.secs[1].k, "monster", "item sections")
	fakeNow = fakeNow + cfg.requestMs
	got = ask("item", {cid = 5001})
	eq(json.decode(got[1].payload).data.id, 5000, "by client id")
	fakeNow = fakeNow + cfg.requestMs
	ext.onExtendedOpcode(player, 154, json.encode({action = "search", data = {q = "drag"}}))
	ext.onExtendedOpcode(player, 155, "not json")
	eq(#sent, 3, "other opcodes and garbage are ignored")
	-- a long answer goes through Chaos.sendChunked
	local big = {}
	for i = 1, 200 do
		big[i] = {n = string.format("Monster with a rather long name number %03d", i), d = "level 100-140, near Brassgate", v = "1.5%"}
		K.add(idx, 2148, "monster", big[i])
	end
	K.finish(idx)
	F.cfg.rowsPerPage = 300
	fakeNow = fakeNow + cfg.requestMs
	got = ask("item", {id = 2148})
	check(#got > 1, "a long answer is sent in parts (" .. #got .. ")")
	local joined = {}
	for i, g in ipairs(got) do
		check(#g.payload <= 8192, "each part fits an extended opcode")
		local mark = g.payload:sub(1, 1)
		eq(mark, i == 1 and "S" or (i == #got and "E" or "P"), "part mark " .. i)
		joined[#joined + 1] = g.payload:sub(2)
	end
	m = json.decode(table.concat(joined))
	eq(#m.data.secs[1].rows, 201, "the parts join into the whole answer")
	F.cfg.rowsPerPage = 15
	-- the staff command
	local said = {}
	local staff = {getGroup = function() return {getId = function() return 5 end} end,
		sendTextMessage = function(_, _, text) said[#said + 1] = text end}
	eq(talks["/itemfinder"].onSay(staff, "/itemfinder", "drag"), false, "staff search")
	check(said[1] and said[1]:find("dragon scale", 1, true) ~= nil, "staff search text: " .. tostring(said[1]))
	local pl = {getGroup = function() return {getId = function() return 1 end} end}
	eq(talks["/itemfinder"].onSay(pl, "/itemfinder", ""), true, "players cannot use it")
	os.execute("rm -rf '" .. dir .. "'")
end

print(string.format("itemfinder_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/rune_supply_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Rune supply (server/README.md "Rune supply"): no rune conjuring; runes from NPC vendors and crafting.
--   * data/lib/chaos_rune_supply.lua: its own check, the names against spell_names.csv, the conjure list against the
--     csv rows marked "removed" and sql/chaos_rune_supply.sql, vendor towns (hub and start towns)
--   * vendors: every rune and the unscribed rune has a seller in the hub town and in every start town
--   * crafting: every rune has a recipe (blank runes, a herb and an ore piece of its band, gold); a rune crafted costs
--     less gold than at the vendor, and still a share of it
--   * tools/install_rune_supply.py on a small data folder written here: the conjure spells go (runes, blank rune, food,
--     the enchanted spear and staff; rune entries, other spells and a commented entry stay), every NPC sells at the config's price, the vendors get every rune, the crafting loader
--     adds the recipes (once), a second run changes nothing, a missing vendor writes nothing
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end
local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

local R = dofile("data/lib/chaos_rune_supply.lua")
eq(ChaosRuneSupply, R, "global and return value")

-- ------------------------------------------------------------------ the config's own check
for _, e in ipairs(R.check()) do
	ok(false, "R.check: " .. e)
end
eq(#R.runes, 36, "36 runes a stock spell conjured")

-- ------------------------------------------------------------------ spell_names.csv
local csvRows = {}
for line in (readFile("data/spells/spell_names.csv") or ""):gmatch("[^\r\n]+") do
	local old, new, words, item, removed = line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
	if old and old ~= "old_name" then
		csvRows[#csvRows + 1] = {old = old, new = new, words = words, item = tonumber(item), removed = removed}
	end
end
ok(#csvRows > 100, "spell_names.csv read with its removed column")
local nameOfItem, removedRows = {}, {}
for _, r in ipairs(csvRows) do
	if r.item then
		nameOfItem[r.item] = r.new
	end
	if r.removed ~= "" then
		eq(r.removed, "conjure", r.old .. ": removed kind")
		ok(r.words ~= "", r.old .. ": a removed row has the old words")
		removedRows[#removedRows + 1] = r
	end
end
eq(#removedRows, #R.removedScripts(), "one removed csv row per removed script (36 runes, the blank rune, 3 others)")
eq(#R.removedScripts(), 40, "40 conjure spells go")
do
	-- the conjure spells that make no rune: food, the enchanted spear and staff (owner: "Pode tirar")
	local want = {["Conjure Rations"] = "support/food.lua", ["Hallow Spear"] = "conjuring/enchant_spear.lua",
		["Charge Staff"] = "conjuring/enchant_staff.lua"}
	eq(#R.otherConjures, 3, "three other conjure spells")
	for _, c in ipairs(R.otherConjures) do
		eq(want[c.name], c.script, c.name .. ": script")
		local row
		for _, r in ipairs(csvRows) do
			if r.new == c.name then row = r end
		end
		ok(row and row.removed == "conjure", c.name .. ": csv row marked removed")
	end
	local seen = {}
	for _, s in ipairs(R.removedScripts()) do
		ok(not seen[s], s .. " once")
		seen[s] = true
	end
	ok(seen["conjuring/great_fireball_rune.lua"] and seen["conjuring/blank_rune.lua"] and seen["support/food.lua"],
		"removedScripts: full paths")
end
for _, r in ipairs(R.runes) do
	eq(r.name, nameOfItem[r.id], "rune " .. r.id .. ": the Chaos name of spell_names.csv")
end
local blankRow
for _, r in ipairs(csvRows) do
	if r.old == "Blank Rune" then blankRow = r end
end
ok(blankRow and blankRow.new == R.blankRune.name and blankRow.removed == "conjure", "the blank rune row")

-- sql/chaos_rune_supply.sql removes exactly these learned names (stock and Chaos)
local sql = readFile("sql/chaos_rune_supply.sql") or ""
local inSql = {}
do
	-- SQL string literals ('' is a quote inside one)
	local body, i = sql:match("IN %((.-)%);") or "", 1
	while true do
		local s = body:find("'", i, true)
		if not s then break end
		local j, buf = s + 1, {}
		while j <= #body do
			local c = body:sub(j, j)
			if c == "'" and body:sub(j + 1, j + 1) == "'" then
				buf[#buf + 1] = "'"; j = j + 2
			elseif c == "'" then
				break
			else
				buf[#buf + 1] = c; j = j + 1
			end
		end
		inSql[table.concat(buf)] = true
		i = j + 1
	end
end
local want = 0
for _, r in ipairs(removedRows) do
	ok(inSql[r.old], "sql names " .. r.old)
	ok(inSql[r.new], "sql names " .. r.new)
	want = want + 2
end
local n = 0
for _ in pairs(inSql) do n = n + 1 end
eq(n, want, "sql names nothing else")

-- ------------------------------------------------------------------ vendors: every rune has a seller
do
	local townsOf = {}
	for _, v in ipairs(R.vendors) do
		townsOf[v.town] = (townsOf[v.town] or 0) + 1
	end
	ok(townsOf[R.hubTown], "a vendor in the main hub (town " .. R.hubTown .. ")")
	for _, t in ipairs(R.startTowns) do
		ok(townsOf[t], "a vendor in start town " .. t)
	end
	for _, r in ipairs(R.runes) do
		ok(r.price >= 1 and r.price >= r.old, r.name .. ": a price, never below the old NPC price")
		eq(R.price(r.id), r.price, r.name .. ": R.price")
	end
	eq(R.price(R.blankRune.id), 10, "the unscribed rune stays at 10")
	eq(R.price(1), nil, "no price for other items")
end

-- ------------------------------------------------------------------ crafting: every rune has a recipe
do
	local recipes = R.recipes()
	eq(#recipes, #R.runes, "one recipe per rune")
	local byId = {}
	for _, c in ipairs(recipes) do
		ok(not byId[c.id], "recipe " .. c.id .. " once")
		byId[c.id] = c
	end
	for _, r in ipairs(R.runes) do
		local c = byId[r.id]
		ok(c, r.name .. ": a recipe")
		if c then
			eq(c.name, r.name, r.name .. ": recipe name")
			eq(c.count, r.count * R.crafting.blanks, r.name .. ": blanks x the conjure count")
			eq(c.materials[1].id, R.blankRune.id, r.name .. ": unscribed runes")
			eq(c.materials[1].count, R.crafting.blanks, r.name .. ": blank count")
			local b = R.band(r.level)
			eq(c.materials[2].id, b.herb, r.name .. ": herb of the band")
			eq(c.materials[3].id, b.ore, r.name .. ": ore of the band")
			eq(c.level, b.skill, r.name .. ": crafting skill of the band")
			ok(c.level >= 10 and c.level <= 35, r.name .. ": skill inside the stock 10-35")
			ok(c.cost >= 0 and c.storage == 0, r.name .. ": gold, no unlock")
			local per = R.craftGoldPerRune(r)
			ok(per < r.price, r.name .. ": crafting cheaper than the vendor")
			ok(per >= r.price * 0.4, r.name .. ": crafting still costs a share of the vendor price")
		end
	end
	-- the bands follow the rune level
	eq(R.band(1).skill, 10, "band 1")
	eq(R.band(30).herb, 26726, "band 3 herb")
	eq(R.band(54).ore, 26401, "the last band")
	-- addRecipes: appended after the stock recipes, once
	local list = {{id = 1, name = "stock"}}
	eq(R.addRecipes(list), #R.runes, "added")
	eq(list[1].name, "stock", "stock recipe first")
	eq(#list, 1 + #R.runes, "all runes after it")
	eq(R.addRecipes(list), 0, "a second load adds nothing")
	eq(R.addRecipes(nil), 0, "no list")
end

-- ------------------------------------------------------------------ the install tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("rune_supply_test: python3 not found, install tool part skipped")
else
	local root = os.tmpname()
	os.remove(root)
	local data = root .. "/data"
	for _, d in ipairs({"spells", "npc/scripts", "scripts/customs/crafting"}) do
		os.execute("mkdir -p '" .. data .. "/" .. d .. "'")
	end
	writeFile(data .. "/spells/spells.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<spells>
	<rune group="attack" spellid="16" name="Searing Orb Rune" id="2304" allowfaruse="1" charges="4" level="30" magiclevel="4" cooldown="2000" groupcooldown="2000" script="attack/great_fireball.lua" />
	<instant group="support" spellid="42" name="Conjure Rations" words="drai bren" level="14" mana="120" soul="1" script="support/food.lua">
		<vocation name="Mystic" />
	</instant>
	<!-- Conjuring Spells -->
	<instant group="support" name="Searing Orb Rune" words="rhun vas pyr" level="30" mana="530" soul="3" script="conjuring/great_fireball_rune.lua">
		<vocation name="Mystic" />
		<vocation name="Elementalist" />
	</instant>
	<instant group="support" name="Unscribed Rune" words="rhun nul" level="20" mana="50" soul="1" script="conjuring/blank_rune.lua">
		<vocation name="Mystic" />
	</instant>
	<instant group="support" name="Shackle Rune" words="rhua shak" level="54" mana="1400" soul="3" script="conjuring/paralyze_rune.lua" />
	<instant group="support" spellid="110" name="Hallow Spear" words="vok sol" level="45" mana="350" soul="3" script="conjuring/enchant_spear.lua">
		<vocation name="Ranger" />
	</instant>
	<instant group="support" spellid="92" name="Charge Staff" words="vok zhul" level="41" mana="80" script="conjuring/enchant_staff.lua" />
	<instant group="support" spellid="10" name="Lantern" words="vael lux" level="8" mana="20" script="support/light.lua" />
	<instant group="support" name="Other Food" words="x y" script="custom/food.lua" />
	<!-- Chaos: no rune conjuring (install_rune_supply.py): <instant group="support" name="Faint Dart Rune" words="rhun tin zhul" script="conjuring/lightest_missile_rune.lua" /> -->
</spells>
]])
	-- the hub vendor (already renamed by the npcnames step): some runes at the old prices
	writeFile(data .. "/npc/Raloth.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<npc name="Raloth" script="Raloth.lua" walkinterval="2000" floorchange="0">
	<parameters>
		<parameter key="module_shop" value="1" />
		<parameter key="shop_buyable" value="searing orb rune,2304,45;
unscribed rune,2260,10;
mana potion,7620,50;
reaper's rune,2268,108" />
	</parameters>
</npc>
]])
	writeFile(data .. "/npc/Isora.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<npc name="Isora" script="Isora.lua">
	<parameters>
		<parameter key="module_shop" value="1" />
		<parameter key="shop_buyable" value="spellbook,2175,150;" />
	</parameters>
</npc>
]])
	-- another seller (not a vendor of the config): its rune prices follow, its other wares stay
	writeFile(data .. "/npc/Testmonger.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<npc name="Testmonger" script="runes.lua">
	<parameters>
		<parameter key="shop_buyable" value="grand mending rune,2273,175,1;health potion,7618,45" />
	</parameters>
</npc>
]])
	writeFile(data .. "/npc/scripts/runes.lua", [[
local shopModule = ShopModule:new()
shopModule:addBuyableItem({'searing orb'}, 2304, 180, 4, 'searing orb rune')
shopModule:addBuyableItem({'mana potion'}, 7620, 50, 1, 'mana potion')
local items = {{name = 'shackle rune', id = 2278, buy = 700}, {name = 'spellbook', id = 2175, buy = 150}}
]])
	local stockCrafting = "Crafting.generalcrafting = {\r\n    {\r\n        id = 28120,\r\n        name = \"Life Orb\",\r\n" ..
		"        level = 10,\r\n        cost = 1200,\r\n        count = 1,\r\n        storage = 0,\r\n        storageText = \"\",\r\n" ..
		"        materials = {\r\n            {id = 26795, count = 2},\r\n        }\r\n    },\r\n}\r\n"
	writeFile(data .. "/scripts/customs/crafting/generalcrafting.lua", stockCrafting)

	local function run(args)
		local p = io.popen("python3 -I tools/install_rune_supply.py '" .. data .. "' " .. (args or "") .. " 2>&1; echo \"exit=$?\"")
		local out = p:read("*a")
		p:close()
		return out, tonumber(out:match("exit=(%d+)"))
	end
	local out, code = run()
	eq(code, 0, "install exit status (" .. out .. ")")
	ok(out:find("6 conjure spell(s) switched off", 1, true), "six conjure spells counted")

	-- spells.xml: the conjure spells are comments; the rune entry and the other spells stay
	local spells = readFile(data .. "/spells/spells.xml")
	local active = spells:gsub("<!%-%-.-%-%->", "")
	ok(not active:find("conjuring/great_fireball_rune.lua", 1, true), "no active Searing Orb conjure")
	ok(not active:find("conjuring/blank_rune.lua", 1, true), "no active unscribed rune conjure")
	ok(not active:find("conjuring/paralyze_rune.lua", 1, true), "no active Shackle conjure (self-closing)")
	ok(active:find('<rune group="attack" spellid="16" name="Searing Orb Rune"', 1, true), "the rune itself stays")
	ok(not active:find("support/food.lua", 1, true), "no active Conjure Rations")
	ok(not active:find("conjuring/enchant_spear.lua", 1, true), "no active Hallow Spear")
	ok(not active:find("conjuring/enchant_staff.lua", 1, true), "no active Charge Staff")
	ok(active:find("support/light.lua", 1, true), "another spell stays")
	ok(active:find("custom/food.lua", 1, true), "a script of the same file name elsewhere stays")
	ok(spells:find("Chaos: no conjuring (install_rune_supply.py)", 1, true), "marker")
	local _, comments = spells:gsub("Chaos: no conjuring", "")
	eq(comments, 6, "six commented out")
	local _, earlier = spells:gsub("Chaos: no rune conjuring", "")
	eq(earlier, 1, "an entry an earlier version commented out stays as it was")

	-- NPC prices and stock
	local function shop(path)
		local text = readFile(path)
		local list = {}
		for name, id, price in text:match('key="shop_buyable" value="([^"]*)"'):gmatch("%s*([^,;]-)%s*,%s*(%d+)%s*,%s*(%d+)") do
			list[tonumber(id)] = {name = name, price = tonumber(price)}
		end
		return list, text
	end
	for _, vendor in ipairs({"Raloth", "Isora"}) do
		local list = shop(data .. "/npc/" .. vendor .. ".xml")
		for _, r in ipairs(R.runes) do
			local e = list[r.id]
			ok(e, vendor .. " sells " .. r.name)
			if e then
				eq(e.price, r.price, vendor .. ": price of " .. r.name)
			end
		end
		ok(list[R.blankRune.id] and list[R.blankRune.id].price == R.blankRune.price, vendor .. " sells unscribed runes at 10")
	end
	local raloth, ralothText = shop(data .. "/npc/Raloth.xml")
	eq(raloth[7620].price, 50, "Raloth's mana potion untouched")
	eq(raloth[2304].name, "searing orb rune", "the existing entry keeps its name")
	eq(raloth[2268].price, R.price(2268), "Reaper's Rune repriced")
	eq(select(2, ralothText:gsub(",2304,", "")), 1, "no second Searing Orb entry")
	ok(ralothText:find("shackle rune,2278," .. R.price(2278) .. ";", 1, true), "added entry: Chaos name, id, price")
	local isora = shop(data .. "/npc/Isora.xml")
	eq(isora[2175].price, 150, "Isora keeps her spellbook")
	local monger, mongerText = shop(data .. "/npc/Testmonger.xml")
	eq(monger[2273].price, R.price(2273), "another NPC's rune price follows the config")
	ok(mongerText:find("grand mending rune,2273," .. R.price(2273) .. ",1;", 1, true), "its subtype stays")
	eq(monger[7618].price, 45, "its potion stays")
	ok(not monger[2304], "a non-vendor gets no new runes")
	local lua = readFile(data .. "/npc/scripts/runes.lua")
	ok(lua:find("addBuyableItem({'searing orb'}, 2304, " .. R.price(2304) .. ", 4, 'searing orb rune')", 1, true), "Lua shop price")
	ok(lua:find("addBuyableItem({'mana potion'}, 7620, 50, 1", 1, true), "Lua potion untouched")
	ok(lua:find("id = 2278, buy = " .. R.price(2278) .. "}", 1, true), "Lua table price")
	ok(lua:find("id = 2175, buy = 150}", 1, true), "Lua table other item")

	-- crafting: the loader at the end of the category file (CRLF kept), loading it adds every recipe once
	local craft = readFile(data .. "/scripts/customs/crafting/generalcrafting.lua")
	eq(craft:sub(1, #stockCrafting), stockCrafting, "stock recipes untouched")
	ok(craft:find("-- Chaos: rune recipes (install_rune_supply.py) v1", 1, true), "loader marker")
	ok(not craft:sub(#stockCrafting + 1):find("[^\r]\n"), "CRLF kept")
	Crafting = {}
	ChaosRuneSupply = nil
	local okLoad, err = pcall(dofile, data .. "/scripts/customs/crafting/generalcrafting.lua")
	ok(okLoad, "the patched category file loads: " .. tostring(err))
	local list = Crafting.generalcrafting or {}
	eq(#list, 1 + #R.runes, "stock recipe + one per rune")
	eq(list[1].id, 28120, "the stock recipe keeps index 1")
	local have = {}
	for _, c in ipairs(list) do
		have[c.id] = c
	end
	for _, r in ipairs(R.runes) do
		ok(have[r.id] and have[r.id].materials[1].id == R.blankRune.id, r.name .. ": craftable at the general table")
	end
	dofile(data .. "/scripts/customs/crafting/generalcrafting.lua") -- a reload: the file builds its table again
	eq(#Crafting.generalcrafting, 1 + #R.runes, "a reload has every recipe once")

	-- a second run changes nothing
	local before = {}
	for _, f in ipairs({"spells/spells.xml", "npc/Raloth.xml", "npc/Isora.xml", "npc/Testmonger.xml", "npc/scripts/runes.lua",
			"scripts/customs/crafting/generalcrafting.lua"}) do
		before[f] = readFile(data .. "/" .. f)
	end
	local out2, code2 = run()
	eq(code2, 0, "second run")
	ok(out2:find("nothing to do", 1, true), "second run: nothing to do")
	for f, text in pairs(before) do
		eq(readFile(data .. "/" .. f), text, "second run leaves " .. f)
	end
	local out3 = run("--dry-run")
	ok(out3:find("nothing to do", 1, true), "dry run after the install")

	-- a vendor that is missing: an error, nothing written
	os.remove(data .. "/npc/Isora.xml")
	writeFile(data .. "/npc/Testmonger.xml", (readFile(data .. "/npc/Testmonger.xml"):gsub("2273," .. R.price(2273), "2273,175")))
	local out4, code4 = run()
	eq(code4, 1, "missing vendor: exit 1")
	ok(out4:find("vendor Isora", 1, true), "names the vendor")
	ok(readFile(data .. "/npc/Testmonger.xml"):find("2273,175", 1, true), "nothing written")
	os.execute("rm -rf '" .. root .. "'")
end

print(string.format("rune_supply_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

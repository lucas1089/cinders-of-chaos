-- Run from the server/ folder: luajit tests/base_archery_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_archery.py on a small base server data folder written here: launchers fire without ammunition
-- (attack, hit chance and missile of their band, no ammo type), quivers become equipment (items.xml, items.otb group,
-- movements.xml with the launchers' vocations), the conjure spells go, arrows and bolts leave monster loot, NPC shops
-- and script rewards; a second run changes nothing.
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

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("base_archery_patch_test: python3 not found, skipped")
	return
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

local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
for _, d in ipairs({"items", "weapons", "movements", "spells", "monster/monsters", "monster/lua", "npc/scripts",
		"creaturescripts/scripts", "actions/scripts"}) do
	os.execute("mkdir -p '" .. data .. "/" .. d .. "'")
end

writeFile(data .. "/items/items.xml", [[
<?xml version="1.0" encoding="UTF-8"?>
<items>
	<item id="2456" article="a" name="bow">
		<attribute key="weight" value="3100" />
		<attribute key="weaponType" value="distance" />
		<attribute key="slotType" value="two-handed" />
		<attribute key="ammoType" value="arrow" />
		<attribute key="range" value="6" />
	</item>
	<item id="27471" article="a" name="sanguine bow">
		<attribute key="weaponType" value="distance" />
		<attribute key="slotType" value="two-handed" />
		<attribute key="ammoType" value="arrow" />
		<attribute key="attack" value="9" />
		<attribute key="hitChance" value="6" />
	</item>
	<item id="29479" article="a" name="water arbalest">
		<attribute key="weaponType" value="distance" />
		<attribute key="slotType" value="two-handed" />
		<attribute key="ammoType" value="bolt" />
		<attribute key="attack" value="9" />
		<attribute key="hitChance" value="3" />
	</item>
	<item id="31000" article="a" name="test bolter">
		<attribute key="weaponType" value="distance" />
		<attribute key="slotType" value="two-handed" />
		<attribute key="ammoType" value="bolt" />
		<attribute key="attack" value="2" />
	</item>
	<item id="2389" article="a" name="spear">
		<attribute key="weaponType" value="distance" />
		<attribute key="attack" value="25" />
		<attribute key="shootType" value="spear" />
	</item>
	<item id="2544" article="an" name="arrow" plural="arrows">
		<attribute key="weaponType" value="ammunition" />
		<attribute key="slotType" value="ammo" />
		<attribute key="ammoType" value="arrow" />
		<attribute key="attack" value="25" />
	</item>
	<item id="2543" article="a" name="bolt" plural="bolts">
		<attribute key="weaponType" value="ammunition" />
		<attribute key="ammoType" value="bolt" />
	</item>
	<item id="29873" article="a" name="test quiver">
		<attribute key="showattributes" value="1" />
		<attribute key="absorbpercentenergy" value="3"/>
		<attribute key="slotType" value="right-hand"/>
		<attribute key="containersize" value="12"/>
		<attribute key="slotType" value="ammo" />
		<attribute key="weight" value="2470"/>
	</item>
</items>
]])
writeFile(data .. "/weapons/weapons.xml", [[
<weapons>
	<distance id="27471" level="600" unproperly="1">
		<vocation name="Ranger" />
		<vocation name="Beastmaster" showInDescription="0" />
	</distance>
	<distance id="31000" level="70" unproperly="1">
		<vocation name="Deadeye" />
	</distance>
	<distance id="2544" action="removecount" />
</weapons>
]])
writeFile(data .. "/movements/movements.xml", [[
<movements>
	<movevent event="Equip" itemid="2463" slot="armor" function="onEquipItem" />
	<movevent event="Equip" itemid="29873" slot="ammo" level="1000" function="onDeEquipItem">
		<vocation name="Thief" />
	</movevent>
	<movevent event="DeEquip" itemid="29873" slot="ammo" function="onEquipItem" />
</movements>
]])
writeFile(data .. "/spells/spells.xml", [[
<spells>
	<instant group="support" spellid="51" name="Fletch" words="a b" level="13" mana="100" script="conjuring/conjure_arrow.lua">
		<vocation name="Ranger" />
	</instant>
	<instant group="healing" spellid="2" name="Mend" words="c d" script="healing/light_healing.lua" />
</spells>
]])
writeFile(data .. "/monster/monsters/elf.xml", [[
<monster name="Elf">
	<loot>
		<item id="2148" countmax="20" chance="50000" />
		<item id="2544" countmax="12" chance="30710" /><!-- arrow -->
		<item name="bolt" countmax="5" chance="1000" />
	</loot>
</monster>
]])
writeFile(data .. "/monster/lua/orc.lua", [[
monster.loot = {
	{id = "gold coin", chance = 50000, maxCount = 30},
	{id = "arrow", chance = 7000, maxCount = 10},
	{id = 2543, chance = 4000},
	{id = "test quiver", chance = 2000}
}
]])
writeFile(data .. "/npc/Seller.xml", [[
<npc name="Seller">
	<parameters>
		<parameter key="shop_buyable" value="arrow,2544,3;spear,2389,9;bolt,2543,4;" />
	</parameters>
</npc>
]])
writeFile(data .. "/npc/scripts/Seller.lua", [[
local shop = {
	{name='arrow', id=2544, buy=3},
	{name='spear', id=2389, buy=9},
}
addBuyableKeyword('pixo', 2544, 10, 30, 'arrows?')
local trade = {item1 = {5944, 6529}}
player:addItem(6529, 6)
if player:removeItem(2544, 12) then end
]])
writeFile(data .. "/creaturescripts/scripts/firstitems.lua", [[
local items = {
	{2456, 1},
	{2544, 50},  -- arrows
}
]])
writeFile(data .. "/actions/scripts/enchanting.lua", [[
if not isInArray({2544, 8905}, target.itemid) then end
]])
-- items.otb: the root and three nodes (the bow, the quiver as a container, the arrow)
local mk = io.popen("python3 -I -c \"import sys, struct; sys.path.insert(0, 'tools'); "
	.. "from install_gems import escape, attr, START, END; "
	.. "node = lambda g, sid: bytes([START]) + escape(bytes([g]) + struct.pack('<I', 0x60) + attr(16, struct.pack('<H', sid))) + bytes([END]); "
	.. "d = b'\\x00\\x00\\x00\\x00' + bytes([START, 0, 0, 0, 0, 0]) + node(0, 2456) + node(2, 29873) + node(0, 2544) + bytes([END]); "
	.. "open(sys.argv[1], 'wb').write(d)\" '" .. data .. "/items/items.otb'")
mk:read("*a")
mk:close()

local function run()
	local h = io.popen("python3 -I tools/patch_base_archery.py '" .. data .. "' 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end
local out1 = run()
ok(out1:find("file(s) written", 1, true) ~= nil, "first run writes: " .. out1)

local items = readFile(data .. "/items/items.xml")
local function entry(id)
	return items:match('<item id="' .. id .. '".-</item>') or ""
end
local bow = entry(2456)
ok(not bow:find("ammoType"), "bow: no ammo type")
ok(bow:find('key="attack" value="29"', 1, true), "bow: attack of the level 0 band")
ok(bow:find('key="hitChance" value="93"', 1, true), "bow: hit chance of the band")
ok(bow:find('key="shootType" value="arrow"', 1, true), "bow: arrow missile")
local sang = entry(27471)
ok(sang:find('key="attack" value="74"', 1, true), "sanguine bow: 9 + 65")
ok(sang:find('key="hitChance" value="100"', 1, true), "sanguine bow: 95 + 6, at most 100")
ok(sang:find('value="crystallinearrow"', 1, true), "sanguine bow: crystalline missile")
local arb = entry(29479)
ok(arb:find('key="attack" value="75"', 1, true), "water arbalest: 9 + 66")
ok(arb:find('value="waterbolt"', 1, true), "water arbalest: water bolt by its name")
local bolter = entry(31000)
ok(bolter:find('key="attack" value="58"', 1, true), "unlisted crossbow: 2 + the level 70 band (56)")
ok(out1:find("31000 test bolter (crossbow, level 70)", 1, true) ~= nil, "unlisted launcher reported")
ok(entry(2389):find('value="spear"', 1, true) and not entry(2389):find("hitChance"), "a spear is untouched")
ok(entry(2544):find("ammoType"), "the arrow item itself stays (players' leftovers are refunded in game)")
local q = entry(29873)
ok(not q:lower():find("containersize"), "quiver: no container size")
ok(not q:find("right%-hand") and not q:find("absorbpercent"), "quiver: no hand slot, no stock abilities")
ok(q:find('key="slotType" value="ammo"', 1, true), "quiver: ammunition slot")
ok(q:find("Distance Fighting +4", 1, true) and q:find("Extra Projectile Chance +8%", 1, true), "quiver: implicits in its text")
ok(q:find('key="weight" value="2470"', 1, true), "quiver: weight kept")

local check = io.popen("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); from install_gems import scan; "
	.. "k, _ = scan(open(sys.argv[1], 'rb').read()); print(' '.join('%d:%d' % (x[2], x[4]) for x in k))\" '"
	.. data .. "/items/items.otb'")
local groups = check:read("*a")
check:close()
ok(groups:find("29873:0", 1, true) and groups:find("2456:0", 1, true), "items.otb: the quiver is no container (" .. groups .. ")")
ok(readFile(data .. "/items/items.otb.bak") ~= nil, "items.otb.bak kept")

local moves = readFile(data .. "/movements/movements.xml")
ok(not moves:find('itemid="29873" slot="ammo" level="1000" function="onDeEquipItem"', 1, true), "stock quiver entry gone")
ok(moves:find('itemid="29873" slot="ammo" level="1000" function="onEquipItem"', 1, true), "Chaos quiver entry")
ok(moves:find('name="Ranger"', 1, true) and moves:find('name="Beastmaster"', 1, true) and moves:find('name="Deadeye"', 1, true),
	"the launchers' vocations")
ok(not moves:find('name="Thief"', 1, true), "not the stock list")
ok(moves:find('itemid="2463"', 1, true), "other entries kept")

local spells = readFile(data .. "/spells/spells.xml")
ok(spells:find("<!-- Chaos: no ammunition", 1, true) and spells:find('name="Mend"', 1, true), "conjure spell commented out")
ok(not spells:match("\n\t<instant[^\n]*conjure_arrow"), "no active conjure spell")

local elf = readFile(data .. "/monster/monsters/elf.xml")
ok(not elf:find('id="2544"', 1, true) and not elf:find('name="bolt"', 1, true), "XML loot: arrows and bolts gone")
ok(elf:find('id="2148"', 1, true), "XML loot: gold kept")
local orc = readFile(data .. "/monster/lua/orc.lua")
ok(not orc:find('"arrow"', 1, true) and not orc:find("2543", 1, true), "Lua loot: arrows and bolts gone")
ok(orc:find('"test quiver"', 1, true) and orc:find('"gold coin"', 1, true), "Lua loot: the rest kept")

ok(readFile(data .. "/npc/Seller.xml"):find('value="spear,2389,9;"', 1, true), "XML shop: only the spear left")
local seller = readFile(data .. "/npc/scripts/Seller.lua")
ok(not seller:find("name='arrow'", 1, true) and seller:find("name='spear'", 1, true), "Lua shop entry gone")
ok(seller:find("-- Chaos: no ammunition (patch_base_archery.py) addBuyableKeyword", 1, true), "buy keyword off")
ok(seller:find("item1 = {5944, 2148}", 1, true), "trade gives gold")
ok(seller:find("player:addItem(2148, 60)", 1, true), "6 infernal bolts: 60 gold")
ok(seller:find("player:removeMoney(24)", 1, true), "12 arrows asked: 24 gold")
ok(readFile(data .. "/creaturescripts/scripts/firstitems.lua"):find("{2148, 50}", 1, true), "first items: 50 gold")
ok(readFile(data .. "/actions/scripts/enchanting.lua"):find("{2544, 8905}", 1, true), "an id pair is no reward")

-- a second run changes nothing
local before = {}
for _, p in ipairs({"/items/items.xml", "/items/items.otb", "/movements/movements.xml", "/spells/spells.xml",
		"/monster/monsters/elf.xml", "/monster/lua/orc.lua", "/npc/Seller.xml", "/npc/scripts/Seller.lua",
		"/creaturescripts/scripts/firstitems.lua"}) do
	before[p] = readFile(data .. p)
end
local out2 = run()
ok(out2:find("0 file(s) written", 1, true) ~= nil, "second run: nothing written (" .. out2 .. ")")
for p, text in pairs(before) do
	eq(readFile(data .. p), text, "second run keeps " .. p)
end

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_archery_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/base_archery_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_base_archery.py on a small base server data folder written here: launchers fire without ammunition
-- (attack, hit chance and missile of their band, no ammo type), quivers become equipment (items.xml, items.otb group,
-- movements.xml with the launchers' vocations), the conjure spells go, arrows and bolts leave monster loot, NPC shops
-- and script rewards; the might ring gets the key chaosMightRing (with the ids it turns into); base_rarity.lua keeps
-- both rings of a ring slot swap; a second run changes nothing.
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
		"creaturescripts/scripts", "actions/scripts", "scripts/customs/rarity", "lib/core", "scripts/eventcallbacks/player"}) do
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
	<item id="2164" article="a" name="might ring">
		<attribute key="slotType" value="ring" />
		<attribute key="charges" value="20" />
		<attribute key="absorbPercentPhysical" value="20" />
		<attribute key="absorbPercentMagic" value="20" />
	</item>
	<item id="2169" article="a" name="time ring">
		<attribute key="slotType" value="ring" />
		<attribute key="transformEquipTo" value="2206" />
	</item>
	<item id="2206" article="a" name="time ring">
		<attribute key="slotType" value="ring" />
		<attribute key="transformDeEquipTo" value="2169" />
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
npcHandler:say("The crows took my pigeons. Bring me 12 arrows. Do you have 12 arrows with you?", cid)
if player:removeItem(2544, 12) then end
]])
-- a script patched by the earlier version of the tool: gold asked, the text still names the arrows
writeFile(data .. "/npc/scripts/Older.lua", [[
npcHandler:say('Bring me 10 bolts, please.', cid)
npcHandler:say("I still have 3 arrows of my own.", cid)
if player:removeMoney(20) then end
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
-- the base slot maps (the second ring slot, engine patch 0023)
writeFile(data .. "/scripts/customs/rarity/base_rarity.lua", [[
local slotBits = {
	[CONST_SLOT_RING] = SLOTP_RING,
	[CONST_SLOT_AMMO] = SLOTP_AMMO,
    [CONST_SLOT_BADGE] = SLOTP_BADGE,
}

local function usesSlot(itemType, slot)
	return bit.band(itemType:getSlotPosition(), slotBits[slot] or 0) ~= 0
end

local function onDeEquip(player, slotPosition)
    player.conds[slotPosition] = nil
end

local function onEquip(player, item, slotPosition)
    player.conds[slotPosition] = item.name
end

local ec = EventCallback

function ec.onItemMoved(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
    if fromPosition.x == CONTAINER_POSITION and bit.band(fromPosition.y, 0x40) == 0 then
        local itemType = item:getType()
        if usesSlot(itemType, fromPosition.y) then
            onDeEquip(player, fromPosition.y)
        end
    end

    if toPosition.x == CONTAINER_POSITION and bit.band(toPosition.y, 0x40) == 0 then
        local itemType = item:getType()
        if usesSlot(itemType, toPosition.y) then
            onEquip(player, item, toPosition.y)
        end
    end
end

ec:register(10)
]])
writeFile(data .. "/lib/core/itemtype.lua", [[
local slotBits = {
	[CONST_SLOT_RING] = SLOTP_RING,
	[CONST_SLOT_AMMO] = SLOTP_AMMO
}
]])
-- the base's two-handed swap (a quiver must stay beside a launcher)
writeFile(data .. "/scripts/eventcallbacks/player/default_onMoveItem.lua", [[
	if item:getTopParent() == self and bit.band(toPosition.y, 0x40) == 0 then
		local itemType, moveItem = ItemType(item:getId())
		if bit.band(itemType:getSlotPosition(), SLOTP_TWO_HAND) ~= 0 and toPosition.y == CONST_SLOT_LEFT then
			moveItem = self:getSlotItem(CONST_SLOT_RIGHT)
		elseif itemType:getWeaponType() == WEAPON_SHIELD and toPosition.y == CONST_SLOT_RIGHT then
			moveItem = self:getSlotItem(CONST_SLOT_LEFT)
		end
	end
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
ok(not q:find("absorbpercent"), "quiver: no stock abilities")
ok(q:find('key="weaponType" value="quiver"', 1, true), "quiver: weapon type quiver (engine patch 0023)")
ok(q:find('key="slotType" value="right-hand"', 1, true), "quiver: the off-hand (the shield hand)")
ok(not q:find('value="ammo"', 1, true), "quiver: no ammunition slot")
local _, slotTypes = q:gsub('key="slotType"', "")
eq(slotTypes, 1, "quiver: one slot type")
ok(q:find("Distance Fighting +4", 1, true) and q:find("Extra Projectile Chance +8%", 1, true), "quiver: implicits in its text")
ok(q:find('key="weight" value="2470"', 1, true), "quiver: weight kept")
-- one might ring at a time (engine src-patch 0023 reads the key)
ok(entry(2164):find('<attribute key="chaosMightRing" value="1" />', 1, true), "might ring: marked")
ok(entry(2164):find('key="absorbPercentMagic" value="20"', 1, true), "might ring: its stats stay")
ok(not entry(2169):find("chaosMightRing", 1, true) and not entry(2206):find("chaosMightRing", 1, true),
	"a time ring (normal and worn) is no might ring")
ok(out1:find("might rings 2164 marked", 1, true) ~= nil, "might rings reported")
-- a might ring that turns into a worn id on equip: both ids are marked, other rings are not
writeFile(root .. "/rings.xml", [[
<items>
	<item id="5000" name="m">
		<attribute key="transformEquipTo" value="5001" />
	</item>
	<item id="5001" name="m">
		<attribute key="transformDeEquipTo" value="5000" />
	</item>
	<item id="5002" name="r" />
</items>
]])
local mr = io.popen("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_base_archery as P; "
	.. "x = open(sys.argv[1]).read(); y, n = P.patch_might_rings(x, [5000]); z, n2 = P.patch_might_rings(y, [5000]); "
	.. "print(sorted(P.might_ring_ids(x, [5000])), y.count('chaosMightRing'), z == y, n[-1], n2[-1])\" '"
	.. root .. "/rings.xml'")
local mrOut = mr:read("*a")
mr:close()
ok(mrOut:find("[5000, 5001] 2 True items.xml: might rings 5000, 5001 marked", 1, true) ~= nil
	and mrOut:find("the might rings 5000, 5001 are marked", 1, true) ~= nil, "worn ids followed, idempotent: " .. mrOut)

local check = io.popen("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); from install_gems import scan; "
	.. "k, _ = scan(open(sys.argv[1], 'rb').read()); print(' '.join('%d:%d' % (x[2], x[4]) for x in k))\" '"
	.. data .. "/items/items.otb'")
local groups = check:read("*a")
check:close()
ok(groups:find("29873:0", 1, true) and groups:find("2456:0", 1, true), "items.otb: the quiver is no container (" .. groups .. ")")
ok(readFile(data .. "/items/items.otb.bak") ~= nil, "items.otb.bak kept")

local moves = readFile(data .. "/movements/movements.xml")
ok(not moves:find('itemid="29873" slot="ammo"', 1, true), "stock quiver entry gone")
ok(moves:find('itemid="29873" slot="shield" level="1000" function="onEquipItem"', 1, true), "Chaos quiver entry (the hands)")
ok(moves:find('event="DeEquip" itemid="29873" slot="shield" function="onDeEquipItem"', 1, true), "Chaos quiver DeEquip")
ok(moves:find('name="Ranger"', 1, true) and moves:find('name="Beastmaster"', 1, true) and moves:find('name="Deadeye"', 1, true),
	"the launchers' vocations")
ok(not moves:find('name="Thief"', 1, true), "not the stock list")
ok(moves:find('itemid="2463"', 1, true), "other entries kept")

local rarityMap = readFile(data .. "/scripts/customs/rarity/base_rarity.lua")
ok(rarityMap:find("[CONST_SLOT_AMMO] = SLOTP_RING, -- Chaos: the second ring slot", 1, true), "base rarity: slot 10 maps to the ring bit")
ok(rarityMap:find("[CONST_SLOT_BADGE] = SLOTP_BADGE,", 1, true) and not rarityMap:find("SLOTP_AMMO", 1, true), "the rest kept")
ok(readFile(data .. "/lib/core/itemtype.lua"):find("[CONST_SLOT_AMMO] = SLOTP_RING -- Chaos", 1, true), "ItemType.usesSlot: the same")

-- the ring swap (engine 0023 swaps the rings of slots 9 and 10 and calls onItemMoved for each) run as code: the
-- base's conditions per slot are a table here (player.conds[slot] = the ring's name)
ok(rarityMap:find("-- Chaos: two rings swapped between the ring slots", 1, true), "base rarity: the ring swap hook")
do
	local env = setmetatable({
		CONTAINER_POSITION = 0xFFFF, CONST_SLOT_RING = 9, CONST_SLOT_AMMO = 10, CONST_SLOT_BADGE = 12,
		SLOTP_RING = 32, SLOTP_AMMO = 512, SLOTP_BADGE = 4096, SLOTP_BACKPACK = 4,
		bit = bit or (load or loadstring)("return {band = function(a, b) return a & b end}")(),
		EventCallback = {register = function() end},
	}, {__index = _G})
	local chunk
	if setfenv then
		chunk = assert(loadstring(rarityMap))
		setfenv(chunk, env)
	else
		chunk = assert(load(rarityMap, "base_rarity", "t", env))
	end
	chunk()
	local moved = env.EventCallback.onItemMoved
	local function ring(name, slotp)
		return {name = name, getType = function() return {getSlotPosition = function() return slotp or 32 end} end}
	end
	local a, b = ring("A"), ring("B")
	local function slot(y) return {x = 0xFFFF, y = y, z = 0} end
	-- before: A in slot 10, B in slot 9; after the engine's swap: A in 9, B in 10
	local me = {conds = {[9] = "B", [10] = "A"}, slots = {[9] = a, [10] = b}}
	function me:getSlotItem(y) return self.slots[y] end
	moved(me, b, 1, slot(9), slot(10))
	eq(me.conds[9], "A", "swap, first call: slot 9 holds A's conditions")
	eq(me.conds[10], "B", "swap, first call: slot 10 holds B's conditions")
	moved(me, a, 1, slot(10), slot(9))
	eq(me.conds[9], "A", "swap, second call: slot 9 still A")
	eq(me.conds[10], "B", "swap, second call: slot 10 still B")
	-- a ring taken off into a container: its slot is cleared, the other ring stays (stock)
	me.slots[9] = nil
	moved(me, a, 1, slot(9), {x = 0xFFFF, y = 64, z = 0})
	eq(me.conds[9], nil, "taken off: slot 9 cleared")
	eq(me.conds[10], "B", "taken off: slot 10 kept")
	-- a ring put on from a container (stock)
	me.slots[9] = a
	moved(me, a, 1, {x = 0xFFFF, y = 64, z = 0}, slot(9))
	eq(me.conds[9], "A", "put on: slot 9 filled")
	-- step 13: a two-handed weapon reached the weapon hand and the base swap moved the shield away with moveTo (no
	-- onItemMoved for the shield): the empty shield hand is cleared at once; a hand still holding an item is kept (the
	-- fixture's slot map has no hands, so the weapon hand's own conditions are not filled here)
	env.CONST_SLOT_LEFT, env.CONST_SLOT_RIGHT, env.SLOTP_LEFT = 6, 5, 32
	local axe = ring("Axe", 32)
	me.conds[5], me.conds[6] = "Shield", "Sword"
	me.slots[5], me.slots[6] = nil, axe
	moved(me, axe, 1, {x = 0xFFFF, y = 64, z = 0}, slot(6))
	eq(me.conds[5], nil, "two-handed swap: the emptied shield hand is cleared")
	me.conds[5], me.slots[5] = "Shield", ring("Shield", 16)
	moved(me, axe, 1, {x = 0xFFFF, y = 64, z = 0}, slot(6))
	eq(me.conds[5], "Shield", "a weapon next to a shield: the shield hand is kept")
	moved(me, a, 1, {x = 0xFFFF, y = 64, z = 0}, slot(9))
	eq(me.conds[5], "Shield", "a ring put on: the hands are left alone")
end
ok(rarityMap:find("-- Chaos: a hand emptied by the two-handed swap", 1, true), "base rarity: the hand hook")

local swap = readFile(data .. "/scripts/eventcallbacks/player/default_onMoveItem.lua")
ok(swap:find("moveItem = self:getSlotItem(CONST_SLOT_RIGHT)\n\t\t\t-- Chaos: a quiver stays beside a bow or crossbow", 1, true),
	"the base swap keeps the quiver (hook right after the off-hand lookup)")
ok(swap:find("ChaosArchery.handsAllowed(ChaosArchery.handKind(itemType),", 1, true), "asks the hand rule")
-- the hook run as code: the block's local moveItem is made visible to the test (what the swap would move)
local swapCode = swap:gsub("local itemType, moveItem = ", "local itemType; itemType, moveItem = ")
local swapFn = assert((loadstring or load)("return function(self, item, toPosition) moveItem = nil " .. swapCode
	.. " return moveItem end"))()
CONST_SLOT_LEFT, CONST_SLOT_RIGHT, SLOTP_TWO_HAND, WEAPON_SHIELD = 6, 5, 2048, 4
bit = bit or {band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end}
local kinds = {[1] = "launcher", [2] = "quiver", [3] = "shield", [4] = "twohanded"}
ChaosArchery = {handKind = function(it) return kinds[it.id] end,
	handsAllowed = function(m, o) return m == "launcher" and o == "quiver" end}
ItemType = function(id) return {id = id, getSlotPosition = function() return (id == 1 or id == 4) and 2048 or 48 end,
	getWeaponType = function() return id == 3 and 4 or 0 end} end
local function holder(offId)
	local off = {getId = function() return offId end}
	return {getSlotItem = function(_, s) return s == 5 and off or nil end}, off
end
local me, quiverItem = holder(2)
local self1 = me
local bowItem = {getId = function() return 1 end, getTopParent = function() return self1 end}
eq(swapFn(me, bowItem, {y = 6}), nil, "a bow taken into the hand leaves the quiver in the off-hand")
local me2, shieldItem = holder(3)
self1 = me2
eq(swapFn(me2, bowItem, {y = 6}), shieldItem, "a bow taken into the hand still moves a shield out (stock)")
local axe = {getId = function() return 4 end, getTopParent = function() return me end}
self1 = me
eq(swapFn(me, axe, {y = 6}), quiverItem, "a two-handed axe moves the quiver out")

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
ok(seller:find('"The crows took my pigeons. Bring me 24 gold. Do you have 24 gold with you?"', 1, true),
	"the dialogue asks for the gold")
local older = readFile(data .. "/npc/scripts/Older.lua")
ok(older:find("'Bring me 20 gold, please.'", 1, true), "an earlier patched script: its text asks for the gold")
ok(older:find("3 arrows of my own", 1, true), "a count that is not the price stays")
ok(readFile(data .. "/creaturescripts/scripts/firstitems.lua"):find("{2148, 50}", 1, true), "first items: 50 gold")
ok(readFile(data .. "/actions/scripts/enchanting.lua"):find("{2544, 8905}", 1, true), "an id pair is no reward")

-- a second run changes nothing
local before = {}
for _, p in ipairs({"/items/items.xml", "/items/items.otb", "/movements/movements.xml", "/spells/spells.xml",
		"/monster/monsters/elf.xml", "/monster/lua/orc.lua", "/npc/Seller.xml", "/npc/scripts/Seller.lua", "/npc/scripts/Older.lua",
		"/creaturescripts/scripts/firstitems.lua", "/scripts/customs/rarity/base_rarity.lua", "/lib/core/itemtype.lua",
		"/scripts/eventcallbacks/player/default_onMoveItem.lua"}) do
	before[p] = readFile(data .. p)
end
local out2 = run()
ok(out2:find("0 file(s) written", 1, true) ~= nil, "second run: nothing written (" .. out2 .. ")")
for p, text in pairs(before) do
	eq(readFile(data .. p), text, "second run keeps " .. p)
end

-- a server patched with the earlier layout (quivers in the ammunition slot) is moved to the off-hand by the next run
local items = readFile(data .. "/items/items.xml")
local oldItems = items:gsub('<attribute key="weaponType" value="quiver" />%s*<attribute key="slotType" value="right%-hand" />',
	'<attribute key="slotType" value="ammo" />')
local oldMoves = readFile(data .. "/movements/movements.xml"):gsub('slot="shield"', 'slot="ammo"')
ok(oldItems ~= items and oldMoves:find('slot="ammo"', 1, true), "earlier layout written back")
writeFile(data .. "/items/items.xml", oldItems)
writeFile(data .. "/movements/movements.xml", oldMoves)
local out3 = run()
ok(out3:find("2 file(s) written", 1, true) ~= nil, "earlier layout: items.xml and movements.xml rewritten (" .. out3 .. ")")
eq(readFile(data .. "/items/items.xml"), before["/items/items.xml"], "earlier layout: items.xml as a fresh install")
eq(readFile(data .. "/movements/movements.xml"), before["/movements/movements.xml"], "earlier layout: movements.xml as a fresh install")

-- a block written after the quivers (the unique equip step's) stays after them: the quiver block is rebuilt in place,
-- not moved to the end, so a second install run over an installed server is a no-op
local later = "\t<!-- later block -->\n\t<movevent event=\"Equip\" itemid=\"7890\" slot=\"necklace\" function=\"onEquipItem\" />\n"
local withLater = readFile(data .. "/movements/movements.xml"):gsub("</movements>", function() return later .. "</movements>" end)
writeFile(data .. "/movements/movements.xml", withLater)
local out4 = run()
ok(out4:find("0 file(s) written", 1, true) ~= nil, "a block after the quivers: nothing written (" .. out4 .. ")")
eq(readFile(data .. "/movements/movements.xml"), withLater, "a block after the quivers keeps its place")

os.execute("rm -rf '" .. root .. "'")
print(string.format("base_archery_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

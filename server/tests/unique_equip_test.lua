-- Run from the server/ folder: luajit tests/unique_equip_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Unique equip rules (server/README.md "Unique equip rules", 2026-10-13):
--   * every round-two archetype unique can be worn by exactly the classes its archetype names, from the level in its
--     drop entry and its description, and not below it (the in-game measure found the Stillheart Robe at level 400,
--     the Hollowglass Diadem refused to the Elementalist, the Choirmaster's Circlet for two lines only, the Snarewalker
--     Greaves at level 300: the base items' rules);
--   * data/lib/chaos_unique_equip.lua: a unique copy is held to its own rule, a stock copy of the same base id to the
--     stock rule, only the check pass decides;
--   * tools/install_unique_equip.py on a small movements.xml: the stock entries taken in and recorded, the looser rule
--     in the block, the movement script, a second run changes nothing, add_vocations.py leaves the block alone.
local count, failures = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what) check(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- globals the specs and the unique lib read (numbers stand in for the engine's constants)
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^ITEM_ATTRIBUTE_") then return k end
end})
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
dofile("data/scripts/chaos/archetypes_config.lua")
local E, SPECS, C = ChaosUniqueEquip, ChaosUniqueSpecs, ChaosArchetypesConfig
check(E and E.allows and E.onEquip, "the lib is loaded by chaos_unique_items.lua")

-- ------------------------------------------------------------------------------------------------ the round-two uniques
local NAME = {warrior = "Warrior", juggernaut = "Juggernaut", berserker = "Berserker", ranger = "Ranger",
	deadeye = "Deadeye", beastmaster = "Beastmaster", mystic = "Mystic", elementalist = "Elementalist",
	illusionist = "Illusionist", thief = "Thief", ninja = "Ninja", samurai = "Samurai", monk = "Monk",
	shadowfist = "Shadowfist", ironsage = "Iron Sage", necromancer = "Necromancer", lich = "Lich", bonelord = "Bone Lord",
	templar = "Templar", inquisitor = "Inquisitor", sentinel = "Sentinel"}
-- the archetype each unique serves (docs/BUILDS.md "The new keystones": the vigil uniques push both vigil keystones)
local SERVES = {snarewalker = {"arSnarewright"}, fusewright = {"arSnarewright"}, choirmaster = {"arVigils", "arIronTithe"},
	oathkeeper = {"arVigils", "arIronTithe"}, hollowglass = {"arHollowVessel"}, stillheart = {"arHollowVessel"}}
local dropById = {}
for _, u in ipairs(ChaosUniqueItems) do dropById[u.id] = u end
local roundTwo = 0
for id, key in pairs(C.uniques) do
	if SERVES[key] then
		roundTwo = roundTwo + 1
		local spec, drop = SPECS[id], dropById[id]
		local rule = spec and spec.equip
		check(rule ~= nil, key .. ": an equip rule in the spec")
		if rule then
			eq(rule.level, drop and drop.level, key .. ": the rule's level is the drop entry's")
			eq(tonumber(spec.description:match("Requires level (%d+)")), rule.level, key .. ": the description's level")
			local want, wanted = {}, 0
			for _, flag in ipairs(SERVES[key]) do
				for _, cls in ipairs(C.classes[flag] or {}) do
					if not want[NAME[cls]] then wanted = wanted + 1 end
					want[NAME[cls]] = true
				end
			end
			check(wanted > 0, key .. ": its archetype names classes")
			for name in pairs(want) do
				check(E.allows(rule, rule.level, name), key .. ": " .. name .. " may wear it at level " .. rule.level)
				check(not E.allows(rule, rule.level - 1, name), key .. ": not below level " .. rule.level)
			end
			for _, name in pairs(NAME) do
				if not want[name] then
					check(not E.allows(rule, 1000, name), key .. ": " .. name .. " is not one of its classes")
				end
			end
		end
	end
end
eq(roundTwo, 6, "six round-two uniques")

-- ------------------------------------------------------------------------------------------------ the rules
check(E.allows(nil, 1, "Ranger"), "no rule: anyone")
check(E.allows({}, 1, "Ranger"), "an empty rule: anyone")
check(E.allows({level = 60}, 60, "Knight"), "a level only")
check(not E.allows({level = 60}, 59, "Mystic"), "below the level")
-- equipLevel without equipLines: the spec has an empty class list, which lets every class wear it
check(E.allows({level = 12, vocations = {}}, 12, "Ranger"), "an empty class list: every class")
check(not E.allows({level = 12, vocations = {}}, 11, "Ranger"), "an empty class list keeps the level")
local STOCK = {[27390] = {level = 400, vocations = {"Mystic", "Elementalist", "Illusionist", "Necromancer", "Lich", "Bone Lord"}},
	[27668] = {level = 230, vocations = {"Mystic", "Illusionist", "Necromancer", "Lich", "Bone Lord"}}, [15453] = {}}
eq(E.ruleOf(27390, true, SPECS, STOCK), SPECS[27390].equip, "a unique copy: its own rule")
eq(E.ruleOf(27390, false, SPECS, STOCK), STOCK[27390], "a stock copy: the stock rule")
eq(E.ruleOf(2400, true, SPECS, STOCK), nil, "an id without either: no rule")

local function player(voc, level, flag)
	return {getVocation = function() return {getName = function() return voc end} end,
		getLevel = function() return level end, hasFlag = function() return flag == true end}
end
local function item(id, unique)
	return {getId = function() return id end, getCustomAttribute = function(_, k) return k == "chaos_unique" and unique or nil end}
end
check(E.onEquip(player("Elementalist", 300), item(27668, 1), 1, true, STOCK), "the Diadem: an Elementalist at 300")
check(not E.onEquip(player("Elementalist", 300), item(27668, nil), 1, true, STOCK), "a stock eldritch hood: no Elementalist")
check(E.onEquip(player("Shadowfist", 300), item(27390, 1), 4, true, STOCK), "the Robe: a Shadowfist at 300")
check(not E.onEquip(player("Shadowfist", 999), item(27390, nil), 4, true, STOCK), "a stock soulmantle: no Monk line")
check(not E.onEquip(player("Mystic", 399), item(27390, nil), 4, true, STOCK), "a stock soulmantle: still level 400")
check(E.onEquip(player("Mystic", 400), item(27390, nil), 4, true, STOCK), "a stock soulmantle at 400")
check(not E.onEquip(player("Mystic", 299), item(27390, 1), 4, true, STOCK), "the Robe below 300")
check(E.onEquip(player("Ranger", 1), item(27390, 1), 4, false, STOCK), "only the check pass decides")
PlayerFlag_IgnoreWeaponCheck = 7
check(E.onEquip(player("Ranger", 1, true), item(27390, 1), 4, true, STOCK), "staff ignore the rules, as the engine")
PlayerFlag_IgnoreWeaponCheck = nil
check(not E.onEquip(player("Ranger", 999), item(15453, 1), 2, true, STOCK), "the Standard: not a Ranger")
check(E.onEquip(player("Ranger", 1), item(15453, nil), 2, true, STOCK), "a stock warrior's shield: anyone")

-- ------------------------------------------------------------------------------------------------ the install tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then python:close() end
if not hasPython then
	print("unique_equip_test: python3 not found, the tool part skipped")
else
	local function readFile(path)
		local f = io.open(path, "rb")
		if not f then return nil end
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
	os.execute("mkdir -p '" .. data .. "/movements'")
	local moves = data .. "/movements/movements.xml"
	writeFile(moves, [[
<?xml version="1.0" encoding="UTF-8"?>
<movements>
	<movevent event="Equip" itemid="28115" slot="feet" level="300" function="onEquipItem">
		<vocation name="Ranger" />
		<vocation name="Deadeye" showInDescription="0" />
		<vocation name="Beastmaster" showInDescription="0" />
		<vocation name="Thief" />
		<vocation name="Ninja" showInDescription="0" />
		<vocation name="Samurai" showInDescription="0" />
		<vocation name="Monk" />
		<vocation name="Shadowfist" showInDescription="0" />
		<vocation name="Iron Sage" showInDescription="0" />
	</movevent>
	<movevent event="DeEquip" itemid="28115" slot="feet" function="onDeEquipItem" />
	<movevent event="Equip" itemid="7890" slot="necklace" level="60" function="onEquipItem" />
	<movevent event="DeEquip" itemid="7890" slot="necklace" function="onDeEquipItem" />
	<movevent event="Equip" itemid="27668" slot="head" level="230" function="onEquipItem" >
		<vocation name="Mystic" />
		<vocation name="Illusionist" showInDescription="0" />
		<vocation name="Necromancer" />
		<vocation name="Lich" showInDescription="0" />
		<vocation name="Bone Lord" showInDescription="0" />
	</movevent>
	<movevent event="DeEquip" itemid="27668" slot="head" function="onDeEquipItem" />
	<movevent event="Equip" itemid="27667" slot="head" level="230" function="onEquipItem" >
		<vocation name="Mystic" />
		<vocation name="Necromancer" />
	</movevent>
	<movevent event="DeEquip" itemid="27667" slot="head" function="onDeEquipItem" />
	<movevent event="Equip" itemid="27390" slot="armor" level="400" function="onEquipItem">
		<vocation name="Mystic" />
		<vocation name="Elementalist" showInDescription="0" />
		<vocation name="Necromancer" />
	</movevent>
	<movevent event="DeEquip" itemid="27390" slot="armor" function="onDeEquipItem" />
	<movevent event="Equip" itemid="2466" slot="armor" level="50" function="onEquipItem">
		<vocation name="Warrior" />
	</movevent>
	<movevent event="DeEquip" itemid="2466" slot="armor" function="onDeEquipItem" />
</movements>
]])
	local function run()
		local p = io.popen("python3 -I tools/install_unique_equip.py '" .. data .. "' 2>&1; echo \"exit=$?\"")
		local out = p:read("*a")
		p:close()
		return out
	end
	local out = run()
	check(out:find("exit=0", 1, true), "the tool runs: " .. out)
	local text = readFile(moves) or ""
	local block = text:match("<!%-%- Chaos unique equip rules.-<!%-%- end of the Chaos unique equip rules %-%->") or ""
	local outside = text:gsub("<!%-%- Chaos unique equip rules.-<!%-%- end of the Chaos unique equip rules %-%->", "")
	for _, id in ipairs({28115, 7890, 27668, 27667, 27390, 15453}) do
		check(not outside:find('event="Equip" itemid="' .. id .. '"', 1, true), id .. ": no Equip entry outside the block")
		check(block:find('event="Equip" itemid="' .. id .. '"', 1, true), id .. ": an Equip entry in the block")
		check(block:find("<!-- stock " .. id .. ":", 1, true), id .. ": its stock rule recorded")
	end
	check(outside:find('event="Equip" itemid="2466" slot="armor" level="50"', 1, true), "other items untouched")
	check(outside:find('event="DeEquip" itemid="28115"', 1, true), "the stock DeEquip stays")
	check(block:find('itemid="15453" slot="shield" function="onDeEquipItem"', 1, true), "a DeEquip for the Standard")
	check(not block:find('event="DeEquip" itemid="28115"', 1, true), "no second DeEquip")
	local function entryOf(id)
		return block:match('<movevent event="Equip" itemid="' .. id .. '"[^>]*/>') or
			block:match('<movevent event="Equip" itemid="' .. id .. '".-</movevent>') or ""
	end
	check(entryOf(27390):find('level="300"', 1, true) and entryOf(27390):find('script="chaos_unique_equip.lua"', 1, true),
		"the Robe's entry: the lower level, the script")
	check(entryOf(27390):find('name="Shadowfist"', 1, true) and entryOf(27390):find('name="Elementalist"', 1, true),
		"the Robe's entry: both lists")
	check(entryOf(27668):find('name="Elementalist"', 1, true), "the Diadem's entry lets the Elementalist through")
	check(entryOf(28115):find('level="120"', 1, true), "the Greaves' entry: level 120")
	check(entryOf(28115):find('<vocation name="Monk" showInDescription="0" />', 1, true),
		"a stock-only class is hidden in the look")
	check(entryOf(7890):find('level="60"', 1, true) and not entryOf(7890):find("<vocation", 1, true),
		"the Charm's entry: everyone from 60 (the stock rule)")
	check(entryOf(15453) ~= "" and not entryOf(15453):find("level=", 1, true), "the Standard: no engine rule")
	local script = readFile(data .. "/movements/scripts/chaos_unique_equip.lua")
	check(script and script:find("[27390] = {level = 400", 1, true), "the script holds the stock rules")
	-- a second run changes nothing
	local before, beforeScript = text, script
	out = run()
	check(out:find("up to date", 1, true) and out:find("exit=0", 1, true), "second run: " .. out)
	eq(readFile(moves), before, "second run: movements.xml unchanged")
	eq(readFile(data .. "/movements/scripts/chaos_unique_equip.lua"), beforeScript, "second run: the script unchanged")
	-- the generated script against the lib
	onEquip = nil
	local chunk = (loadstring or load)(script or "")
	check(chunk ~= nil, "the script parses")
	if chunk then
		chunk()
		check(onEquip(player("Lich", 300), item(27390, 1), 4, true), "script: the Robe on a Lich at 300")
		check(not onEquip(player("Lich", 300), item(27390, nil), 4, true), "script: a stock soulmantle at 300")
		check(not onEquip(player("Monk", 999), item(27668, nil), 1, true), "script: a stock eldritch hood on a Monk")
		check(onEquip(player("Iron Sage", 250), item(27668, 1), 1, true), "script: the Diadem on an Iron Sage")
	end
	-- add_vocations.py leaves the block alone
	local p = io.popen("python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import add_vocations as a; "
		.. "import re; b = lambda x: re.search(r'<!-- Chaos unique equip rules.*?end of the Chaos unique equip rules -->', x, re.S).group(0); "
		.. "t = open(sys.argv[1]).read(); n, c = a.patch_movements(t, {}); print('same' if b(n) == b(t) else 'changed')\" '"
		.. moves .. "' 2>&1")
	local res = p:read("*a")
	p:close()
	check(res:find("same", 1, true), "add_vocations.patch_movements leaves the block: " .. res)
	os.execute("rm -rf '" .. root .. "'")
end

print(string.format("unique_equip_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end

-- Run from the server/ folder: luajit tests/potions_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The potion lists of the base script data/actions/scripts/other/potions.lua, as tools/add_vocations.py patches them
-- (patch_potions): every class drinks the potions of its role (docs/CLASSES.md) and the refusal texts name our classes.
-- A condensed copy of the stock script (a few potions of each kind, the stock onUse), patched by the tool, then run on
-- a mock engine for every class.
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

-- the stock script, condensed (CRLF line ends as the base server ships it; the stock texts, one of them wrong: the
-- tumble life potion lists paladins but says knights)
local STOCK = table.concat({
	"local berserk = Condition(CONDITION_ATTRIBUTES)",
	"local mastermind = Condition(CONDITION_ATTRIBUTES)",
	"",
	"local potions = {",
	"\t[6558] = { -- concentrated demonic blood",
	"\t\ttransform = {7588, 7589},",
	"\t\teffect = CONST_ME_DRAWBLOOD",
	"\t},",
	"\t[7439] = { -- berserk potion",
	"\t\tcondition = berserk,",
	"\t\tvocations = {4, 8},",
	"\t\teffect = CONST_ME_MAGIC_RED,",
	"\t\tdescription = \"Only knights may drink this potion.\",",
	"\t\ttext = \"You feel stronger.\"",
	"\t},",
	"\t[7440] = { -- mastermind potion",
	"\t\tcondition = mastermind, ",
	"\t\tvocations = {1, 2, 5, 6, 9, 10},",
	"\t\teffect = CONST_ME_MAGIC_BLUE,",
	"\t\tdescription = \"Only sorcerers, druids and illusionists may drink this potion.\",",
	"\t\ttext = \"You feel smarter.\"",
	"\t\t},",
	"\t[7588] = { -- strong health potion",
	"\t\thealth = {250, 350},",
	"\t\tvocations = {3, 4, 7, 8},",
	"\t\tlevel = 50,",
	"\t\tflask = 7634,",
	"\t\tdescription = \"Only knights and paladins of level 50 or above may drink this fluid.\"",
	"\t},",
	"\t[7590] = { -- great mana potion",
	"\t\tmana = {150, 250},",
	"\t\tvocations = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10},",
	"\t\tlevel = 80,",
	"\t\tflask = 7635,",
	"\t\tdescription = \"Only druids, sorcerers, paladins, knights and illusionists of level 80 or above may drink this fluid.\"",
	"\t},",
	"\t[7591] = { -- great health potion",
	"\t\thealth = {425, 575},",
	"\t\tvocations = {4, 8},",
	"\t\tlevel = 80,",
	"\t\tflask = 7635,",
	"\t\tdescription = \"Only knights of level 80 or above may drink this fluid.\"",
	"\t},",
	"\t[7618] = { -- health potion",
	"\t\thealth = {125, 175},",
	"\t\tflask = 7636",
	"\t},",
	"\t[8472] = { -- great spirit potion",
	"\t\thealth = {250, 350},",
	"\t\tmana = {100, 200},",
	"\t\tvocations = {3, 7},",
	"\t\tlevel = 80,",
	"\t\tflask = 7635,",
	"\t\tdescription = \"Only paladins of level 80 or above may drink this fluid.\"",
	"\t},",
	"\t[26735] = { -- tumble life potion",
	"\t\thealth = {890, 1050},",
	"\t\tvocations = {3, 4, 7, 8},",
	"\t\tlevel = 200,",
	"\t\tdescription = \"Only knights of level 200 or above may drink this fluid.\"",
	"\t},",
	"\t[26736] = { -- nimble mana potion",
	"\t\tmana = {570, 775},",
	"\t\tvocations = {1, 2, 5, 6, 9, 10},",
	"\t\tlevel = 100,",
	"\t\tdescription = \"Only sorcerers, druids and illusionists of level 100 or above may drink this fluid.\"",
	"\t},",
	"\t[26737] = { -- hazel mana potion",
	"\t\tmana = {750, 885},",
	"\t\tvocations = {1, 2, 3, 5, 6, 7, 9, 10},",
	"\t\tlevel = 150,",
	"\t\tdescription = \"Only sorcerers, druids, paladins and illusionists of level 150 or above may drink this fluid.\"",
	"\t},",
	"}",
	"",
	"function onUse(player, item, fromPosition, target, toPosition, isHotkey)",
	"\tif type(target) == \"userdata\" and not target:isPlayer() then",
	"\t\treturn false",
	"\tend",
	"",
	"\tlocal potion = potions[item:getId()]",
	"\tif potion.level and player:getLevel() < potion.level or potion.vocations and not table.contains(potion.vocations, player:getVocation():getId()) then",
	"\t\tplayer:say(potion.description, TALKTYPE_MONSTER_SAY)",
	"\t\treturn true",
	"\tend",
	"\tif potion.health then",
	"\t\tdoTargetCombat(player, target, COMBAT_HEALING, potion.health[1], potion.health[2])",
	"\tend",
	"\tif potion.mana then",
	"\t\tdoTargetCombat(player, target, COMBAT_MANADRAIN, potion.mana[1], potion.mana[2])",
	"\tend",
	"\ttarget:say(\"Aaaah...\", TALKTYPE_MONSTER_SAY)",
	"\treturn true",
	"end",
	""
}, "\r\n")

-- ---------------------------------------------------------------- the tool
local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("potions_patch_test: python3 not found, skipped")
	return
end

local function runPatch(text, fn)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import add_vocations as a; "
		.. "t = a.read(sys.argv[1]); n, c = a." .. (fn or "patch_potions") .. "(t); a.write(sys.argv[1], n); print(c)\" " .. path
	local h = assert(io.popen(cmd))
	local count = tonumber((h:read("*a") or ""):match("%d+"))
	h:close()
	f = assert(io.open(path, "rb"))
	local out = f:read("*a")
	f:close()
	os.remove(path)
	return out, count
end

local patched, n = runPatch(STOCK)
eq(n, 9, "every potion with a vocation list patched")
local again, n2 = runPatch(patched)
eq(n2, 0, "second run: nothing to do")
eq(again, patched, "second run changes nothing")
ok(patched:find("\r\n", 1, true) ~= nil and not patched:gsub("\r\n", ""):find("\n", 1, true), "CRLF line ends kept")
ok(not patched:lower():find("knight", 1, true) and not patched:lower():find("paladin", 1, true)
	and not patched:lower():find("sorcerer", 1, true) and not patched:lower():find("druid", 1, true),
	"no stock vocation name left in the texts")

-- an install patched by the former rule (Berserker, Beastmaster, Monk, Templar, Necromancer appended, no Thief line):
-- the same result as a fresh patch
local former = STOCK:gsub("vocations = {3, 7}", "vocations = {3, 7, 15, 17, 18, 19, 23, 24, 25}")
	:gsub("vocations = {4, 8}", "vocations = {4, 8, 14, 23, 24, 25}")
	:gsub("vocations = {1, 2, 5, 6, 9, 10}", "vocations = {1, 2, 5, 6, 9, 10, 20, 21, 22}")
eq((runPatch(former)), patched, "an install of the former rule ends like a fresh one")

-- ---------------------------------------------------------------- mock engine
COMBAT_HEALING, COMBAT_MANADRAIN, TALKTYPE_MONSTER_SAY = 128, 64, 36
CONST_ME_DRAWBLOOD, CONST_ME_MAGIC_RED, CONST_ME_MAGIC_BLUE, CONDITION_ATTRIBUTES = 1, 2, 3, 4
function Condition()
	return {}
end
function table.contains(t, v)
	for _, x in ipairs(t) do
		if x == v then
			return true
		end
	end
	return false
end
local drank, said
function doTargetCombat(source, target, ctype)
	drank[#drank + 1] = ctype
	return true
end
local function makePlayer(voc, level)
	return {
		isPlayer = function() return true end,
		getLevel = function() return level end,
		getVocation = function() return {getId = function() return voc end} end,
		say = function(_, text) said = text end
	}
end
local env = setmetatable({}, {__index = _G})
local chunk = assert((loadstring or load)(patched, "potions.lua", "t", env))
if setfenv then
	setfenv(chunk, env)
end
chunk()
local onUse = env.onUse

-- drink: true when the potion worked, false and the refusal text when refused
local function drink(voc, potionId, level)
	drank, said = {}, nil
	local p = makePlayer(voc, level or 300)
	onUse(p, {getId = function() return potionId end}, {}, p, {}, false)
	return #drank > 0, said
end

-- the rules (docs/CLASSES.md): melee lines the knight's, hybrids the paladin's, casters the mage's; Templar both
local KNIGHT, PALADIN, MAGE = {7439, 7591}, {8472}, {7440, 26736}
local lines = {
	{name = "Warrior", ids = {4, 8, 14}, can = {KNIGHT}},
	{name = "Ranger", ids = {3, 7, 15}, can = {PALADIN}},
	{name = "Mystic", ids = {1, 5, 10}, can = {MAGE}},
	{name = "Thief", ids = {11, 12, 13}, can = {PALADIN}},
	{name = "Monk", ids = {17, 18, 19}, can = {PALADIN}},
	{name = "Necromancer", ids = {20, 21, 22}, can = {MAGE}},
	{name = "Templar", ids = {23, 24, 25}, can = {KNIGHT, PALADIN}}
}
for _, line in ipairs(lines) do
	local allowed = {}
	for _, group in ipairs(line.can) do
		for _, id in ipairs(group) do
			allowed[id] = true
		end
	end
	for _, voc in ipairs(line.ids) do
		for _, id in ipairs({7439, 7591, 8472, 7440, 26736}) do
			local okDrink = drink(voc, id)
			if id ~= 7439 and id ~= 7440 then -- the buff potions add a condition, not a heal
				eq(okDrink, allowed[id] == true, line.name .. " line " .. voc .. " potion " .. id)
			else
				eq(said == "Aaaah...", allowed[id] == true, line.name .. " line " .. voc .. " buff potion " .. id)
			end
		end
		-- open to all: the weak potions, the mana potions of every vocation
		eq((drink(voc, 7618)), true, voc .. " health potion")
		eq((drink(voc, 7590)), true, voc .. " great mana potion")
		-- strong health: everyone but the casters
		local caster = line.can[1] == MAGE
		eq((drink(voc, 7588)), not caster, voc .. " strong health potion")
		eq((drink(voc, 26737)), line.name ~= "Warrior", voc .. " hazel mana potion")
	end
end

-- the refusal texts
local _, text = drink(12, 7591)
eq(text, "Only Warriors and Templars of level 80 or above may drink this fluid.", "great health refused to a Ninja")
_, text = drink(21, 7588)
eq(text, "Only Warriors, Rangers, Thieves, Monks and Templars of level 50 or above may drink this fluid.",
	"strong health refused to a Lich")
_, text = drink(24, 26736)
eq(text, "Only Mystics and Necromancers of level 100 or above may drink this fluid.", "nimble mana refused to a Templar")
_, text = drink(1, 7439)
eq(text, "Only Warriors and Templars may drink this potion.", "berserk refused to a Mystic")
_, text = drink(4, 26737)
eq(text, "Only Rangers, Mystics, Thieves, Monks, Necromancers and Templars of level 150 or above may drink this fluid.",
	"hazel mana refused to a Warrior")
_, text = drink(12, 7590, 50)
eq(text, "Only characters of level 80 or above may drink this fluid.", "every class: only the level is named")
_, text = drink(12, 26735, 100)
eq(text, "Only Warriors, Rangers, Thieves, Monks and Templars of level 200 or above may drink this fluid.",
	"the stock text that named knights only now matches its list")

-- ---------------------------------------------------------------- open potions (patch_open_potions.py)
-- Owner 2026-10-24: every class drinks every health, mana and spirit potion; the level gates stay. The tool runs after
-- add_vocations.py on the patched script; every vocation id of docs/CLASSES.md (and the stock ones) must drink them all.
local function runOpen(text)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
	local cmd = "python3 -I -c \"import sys; sys.path.insert(0, 'tools'); import patch_open_potions as o; "
		.. "t = open(sys.argv[1], newline='').read().replace(chr(13)+chr(10), chr(10)); n, c = o.patch_potions(t); "
		.. "open(sys.argv[1], 'w', newline='').write(n.replace(chr(10), chr(13)+chr(10))); print(c)\" " .. path
	local h = assert(io.popen(cmd))
	local count = tonumber((h:read("*a") or ""):match("%d+"))
	h:close()
	f = assert(io.open(path, "rb"))
	local out = f:read("*a")
	f:close()
	os.remove(path)
	return out, count
end
local opened, on = runOpen(patched)
eq(on, 7, "every healing potion with a vocation list opened")
local openedAgain, on2 = runOpen(opened)
eq(on2, 0, "open potions: second run does nothing")
eq(openedAgain, opened, "open potions: second run changes nothing")
eq((runOpen((runPatch(STOCK)))), opened, "stock and patched give the same result")
local oenv = setmetatable({}, {__index = _G})
local ochunk = assert((loadstring or load)(opened, "potions.lua", "t", oenv))
if setfenv then
	setfenv(ochunk, oenv)
end
ochunk()
local allVocations = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25}
local healing = {7588, 7590, 7591, 7618, 8472, 26735, 26736, 26737}
for _, voc in ipairs(allVocations) do
	for _, id in ipairs(healing) do
		drank, said = {}, nil
		local p = makePlayer(voc, 300)
		oenv.onUse(p, {getId = function() return id end}, {}, p, {}, false)
		ok(#drank > 0, "vocation " .. voc .. " drinks potion " .. id)
	end
end
-- the level gate stays, for everyone, with a text that names no class
drank, said = {}, nil
local low = makePlayer(12, 79)
oenv.onUse(low, {getId = function() return 8472 end}, {}, low, {}, false)
eq(#drank, 0, "great spirit below level 80 is refused")
eq(said, "Only characters of level 80 or above may drink this fluid.", "level refusal names no class")
local _, lists = opened:gsub("vocations = {", "")
eq(lists, 2, "only the berserk and the mastermind potion keep a class list")
-- the buff potions keep their lists
eq((drink(1, 7439)), false, "berserk potion stays for the knights' lines")

-- ---------------------------------------------------------------- the mastermind potion (strengthening_potions.lua)
-- the stock check, Player.isMage, knows 1, 2, 5 and 6 only: the Illusionist and the Necromancer line were refused
local STRENGTH = table.concat({
	"local mastermind = Condition(CONDITION_ATTRIBUTES)",
	"local config = {[7440] = mastermind}",
	"function onUse(player, item, fromPosition, target, toPosition, isHotkey)",
	"\tlocal useItem = config[item.itemid]",
	"\tif not useItem then",
	"\t\treturn true",
	"\tend",
	"\tif item.itemid == 7440 then",
	"\t\tif not player:isMage() then",
	"\t\t\tplayer:say('Only sorcerers and druids may drink this fluid.', TALKTYPE_MONSTER_SAY)",
	"\t\t\treturn true",
	"\t\tend",
	"\tend",
	"\tplayer:addCondition(useItem)",
	"\treturn true",
	"end",
	""
}, "\n")
local sPatched, sn = runPatch(STRENGTH, "patch_strengthening")
eq(sn, 2, "mastermind: the check and the text")
local sAgain, sn2 = runPatch(sPatched, "patch_strengthening")
eq(sn2, 0, "mastermind: second run does nothing")
eq(sAgain, sPatched, "mastermind: second run changes nothing")
local senv = setmetatable({}, {__index = _G})
local schunk = assert((loadstring or load)(sPatched, "strengthening_potions.lua", "t", senv))
if setfenv then
	setfenv(schunk, senv)
end
schunk()
local function mastermind(voc)
	local cond
	said = nil
	local p = makePlayer(voc, 300)
	p.addCondition = function(_, c) cond = c end
	p.isMage = function() return voc == 1 or voc == 5 end
	senv.onUse(p, {itemid = 7440}, {}, p, {}, false)
	return cond ~= nil, said
end
for _, voc in ipairs({1, 5, 10, 20, 21, 22}) do
	eq((mastermind(voc)), true, "mastermind for " .. voc)
end
for _, voc in ipairs({4, 3, 12, 18, 24}) do
	local drankIt, refusal = mastermind(voc)
	eq(drankIt, false, "no mastermind for " .. voc)
	eq(refusal, "Only Mystics and Necromancers may drink this fluid.", "mastermind refusal for " .. voc)
end

if fails > 0 then
	print(("potions_patch_test: %d of %d checks failed"):format(fails, checks))
	os.exit(1)
end
print(("potions_patch_test: %d checks, 0 failures"):format(checks))

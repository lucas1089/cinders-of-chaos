-- Run from the server/ folder: luajit tests/melee_skill_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- tools/patch_melee_skill.py (beta report 2026-10-22: equipment said and gave "+2 Club" instead of Melee) on copies of
-- the stock lines it changes, written here:
--   items.xml        an item with a sword, axe or club number gets all three at the highest; fist and distance stay
--   base_rarity.lua  the stock onEquip, run against a mocked Condition: a rolled melee modifier (club, sword or axe)
--                    sets all three melee skills, fist and distance only their own
-- and: a second run changes nothing, --dry-run writes nothing, a file without the stock lines is refused.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local python = io.popen and io.popen("python3 -V 2>/dev/null")
local hasPython = python and (python:read("*a") or ""):find("Python 3")
if python then
	python:close()
end
if not hasPython then
	print("melee_skill_patch_test: python3 not found, skipped")
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
local function sh(cmd)
	local p = io.popen(cmd .. " 2>&1")
	local out = p:read("*a")
	p:close()
	return out
end

local ITEMS = [[
<?xml version="1.0" encoding="iso-8859-1"?>
<items>
	<item id="100" article="a" name="test ring">
		<attribute key="weight" value="90" />
		<attribute key="skillSword" value="4" />
		<attribute key="duration" value="1800" />
	</item>
	<item id="101" article="a" name="test helmet">
		<attribute key="skillaxe" value="1" />
		<attribute key="skillclub" value="3" />
		<attribute key="skilldist" value="2" />
	</item>
	<item id="102" article="a" name="test gloves">
		<attribute key="skillFist" value="2" />
	</item>
	<item id="103" article="a" name="test bow">
		<attribute key="skillDist" value="3" />
	</item>
	<item id="104" name="plain" />
	<item fromid="105" toid="106" article="a" name="test cuirass">
		<attribute key="skillAxe" value="2" />
		<attribute key="skillSword" value="2" />
		<attribute key="skillClub" value="2" />
	</item>
</items>
]]

-- the stock onEquip of the base rarity script (the lines the patch reads; the rest reduced)
local RARITY = [[
local conditions = {
    ["fistSkill"] = {condition = {id = 0, subId = 1000, type = 1, param = "FIST", ticks = -1}},
    ["clubSkill"] = {condition = {id = 0, subId = 1001, type = 1, param = "CLUB", ticks = -1}},
    ["swordSkill"] = {condition = {id = 0, subId = 1002, type = 1, param = "SWORD", ticks = -1}},
    ["axeSkill"] = {condition = {id = 0, subId = 1003, type = 1, param = "AXE", ticks = -1}},
    ["distanceSkill"] = {condition = {id = 0, subId = 1004, type = 1, param = "DISTANCE", ticks = -1}}
}
local conditionCount = 5

function onEquip(player, item, slotPosition)
    local cleanSlot = true
    for index, info in pairs(conditions) do
        local key = string.format("rarity_%s", index)
        local value = item:getCustomAttribute(key) or 0
        if value ~= 0 then
            local condition = Condition(info.condition.type, info.condition.id)
            condition:setTicks(info.condition.ticks)
            local subId = (conditionCount * slotPosition) + info.condition.subId
            condition:setParameter(CONDITION_PARAM_SUBID, subId)
            condition:setParameter(info.condition.param, value)
            player:addCondition(condition)
            cleanSlot = false
        end
    end
end
]]

local tmp = os.tmpname()
os.remove(tmp)
local root = tmp .. "_melee"
sh("mkdir -p '" .. root .. "/items' '" .. root .. "/scripts/customs/rarity'")
local itemsPath = root .. "/items/items.xml"
local rarityPath = root .. "/scripts/customs/rarity/base_rarity.lua"
writeFile(itemsPath, ITEMS)
writeFile(rarityPath, RARITY)
local tool = "python3 -I tools/patch_melee_skill.py '" .. root .. "'"

local out = sh(tool .. " --dry-run")
ok(out:find("2 file%(s%) would change") ~= nil, "dry run reports both files (" .. out .. ")")
eq(readFile(itemsPath), ITEMS, "dry run writes nothing")
out = sh(tool)
ok(out:find("2 item%(s%)") ~= nil, "two items changed (" .. out .. ")")
local items, rarity = readFile(itemsPath), readFile(rarityPath)
out = sh(tool)
ok(out:find("nothing to change") ~= nil, "a second run changes nothing (" .. out .. ")")
eq(readFile(itemsPath), items, "second run: items.xml unchanged")
eq(readFile(rarityPath), rarity, "second run: base_rarity.lua unchanged")

local function skills(id)
	local block = items:match('<item id="' .. id .. '".-</item>') or items:match('<item fromid="' .. id .. '".-</item>')
	local out2 = {}
	for k, v in (block or ""):gmatch('key="(skill%a+)" value="(%-?%d+)"') do
		out2[k:lower()] = tonumber(v)
	end
	return out2
end
local s = skills(100)
ok(s.skillsword == 4 and s.skillaxe == 4 and s.skillclub == 4, "a sword ring: all three melee skills +4")
s = skills(101)
ok(s.skillsword == 3 and s.skillaxe == 3 and s.skillclub == 3, "axe 1 and club 3: all three at the highest, 3")
eq(s.skilldist, 2, "distance stays")
s = skills(102)
ok(s.skillfist == 2 and not s.skillsword, "fist stays alone (the Monk line)")
s = skills(103)
ok(s.skilldist == 3 and not s.skillsword, "a bow keeps distance only")
s = skills(105)
ok(s.skillsword == 2 and s.skillaxe == 2 and s.skillclub == 2, "an item that has all three is left alone")
ok(items:find('<item id="104" name="plain" />', 1, true) ~= nil, "a self-closed item is left alone")

-- the patched onEquip against a mocked Condition
local added = {}
CONDITION_PARAM_SUBID, CONDITION_PARAM_SKILL_SWORD, CONDITION_PARAM_SKILL_AXE, CONDITION_PARAM_SKILL_CLUB =
	"SUBID", "SWORD", "AXE", "CLUB"
Condition = function()
	local c = {params = {}}
	function c:setTicks() end
	function c:setParameter(k, v) self.params[k] = v end
	return c
end
dofile(rarityPath)
local function equip(attrs)
	added = {}
	local player = {addCondition = function(_, c) added[#added + 1] = c end}
	local item = {getCustomAttribute = function(_, k) return attrs[k] end}
	onEquip(player, item, 1)
	local total = {}
	for _, c in ipairs(added) do
		for k, v in pairs(c.params) do
			if k ~= "SUBID" then
				total[k] = (total[k] or 0) + v
			end
		end
	end
	return total
end
local t = equip({rarity_clubSkill = 2})
ok(t.SWORD == 2 and t.AXE == 2 and t.CLUB == 2, "a +2 club modifier raises all three melee skills by 2")
t = equip({rarity_swordSkill = 2, rarity_axeSkill = 3})
ok(t.SWORD == 5 and t.AXE == 5 and t.CLUB == 5, "two melee modifiers add up: melee +5")
t = equip({rarity_distanceSkill = 2, rarity_fistSkill = 1})
ok(t.DISTANCE == 2 and t.FIST == 1 and not t.SWORD, "distance and fist only their own")

-- a file without the stock lines is refused
writeFile(rarityPath, "local x = 1\n")
out = sh(tool)
ok(out:find("REFUSED", 1, true) ~= nil, "unknown base_rarity.lua refused (" .. out .. ")")

sh("rm -rf '" .. root .. "'")
print(string.format("melee_skill_patch_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

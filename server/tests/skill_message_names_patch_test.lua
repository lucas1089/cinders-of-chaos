-- Run from the server/ folder: luajit tests/skill_message_names_patch_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- src-patch 0065: the engine's skill messages ("You advanced to <skill> level N.") use the names of the skills window:
-- sword, club and axe fighting are "melee", distance fighting is "ranged". The patch is text, so this reads it: every
-- message site calls getSkillMessageName, getSkillName (item look texts) is untouched, and the new switch maps as above.
local fails, count = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local f = assert(io.open("src-patches/0065-skill-message-names.patch", "rb"))
local text = f:read("*a")
f:close()

local function count_of(s, pat)
	local n = 0
	for _ in s:gmatch(pat) do
		n = n + 1
	end
	return n
end

local added, removed = {}, {}
for line in text:gmatch("[^\n]+") do
	if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
		added[#added + 1] = line:sub(2)
	elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
		removed[#removed + 1] = line:sub(2)
	end
end
local add, rem = table.concat(added, "\n"), table.concat(removed, "\n")

check(count_of(rem, "getSkillName%(skill%)") == 4, "four message lines lose getSkillName(skill) in player.cpp")
check(count_of(add, "getSkillMessageName%(skill%)") == 4, "and call getSkillMessageName(skill)")
check(add:find('"You advanced to {:s} level {:d}."', 1, true) ~= nil, "the advance message text is unchanged")
check(add:find('"You were downgraded to {:s} level {:d}."', 1, true) ~= nil, "the downgrade message text is unchanged")
check(add:find("std::string getSkillMessageName(uint8_t skillid);", 1, true) ~= nil, "tools.h declares it")
check(not add:find("getSkillName(uint8_t skillid)", 1, true), "getSkillName itself is not redefined (look texts)")

-- the mapping, read from the patch's switch
local body = add:match("std::string getSkillMessageName%(uint8_t skillid%)\n{(.-)\n}") or ""
local map, cases = {}, {}
for line in body:gmatch("[^\n]+") do
	local c = line:match("case (SKILL_%u+):")
	if c then
		cases[#cases + 1] = c
	end
	local r = line:match('return "([^"]+)"')
	if r then
		for _, k in ipairs(cases) do
			map[k] = r
		end
		cases = {}
	end
end
check(map.SKILL_SWORD == "melee" and map.SKILL_CLUB == "melee" and map.SKILL_AXE == "melee", "sword, club, axe: melee")
check(map.SKILL_DISTANCE == "ranged", "distance fighting: ranged")
check(map.SKILL_FIST == nil and map.SKILL_SHIELD == nil and map.SKILL_MAGLEVEL == nil,
	"fist fighting, shielding, magic level fall through to the engine's name")
check(body:find("default:\n%s*return getSkillName%(skillid%);") ~= nil, "any other skill keeps getSkillName")

-- the look text rewrite still has its engine input (getSkillName gives the three names apart)
dofile("data/scripts/chaos/melee_skill_core.lua")
check(ChaosMeleeSkill.lookText("You see a ring (club fighting +4, sword fighting +4, axe fighting +4).")
	== "You see a ring (melee +4).", "the look text rewrite is not affected")

if fails > 0 then
	print(string.format("%d of %d checks failed", fails, count))
	os.exit(1)
end
print(string.format("skill_message_names_patch_test: %d checks passed", count))

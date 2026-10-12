-- Run from the server/ folder: luajit tests/monster_names_test.lua (or lua5.3; CI runs both)
-- Shown monster names (chaos_constants.lua "Monster names") against a mocked engine: the type name behind a renamed
-- monster, the loot-line description, and Chaos.createMonsterNamed renaming in onSpawn, before the placement.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")

local failures, count = 0, 0
local function eq(a, b, label)
	count = count + 1
	if a ~= b then
		failures = failures + 1
		print("FAIL " .. label .. ": got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

-- a monster of type `typeName` (nameDescription `desc`), shown as `shown` (nil: not renamed)
local function monster(typeName, desc, shown)
	local mt = {name = function() return typeName end, getNameDescription = function() return desc end}
	local m = {shown = shown}
	function m:isMonster() return true end
	function m:getType() return mt end
	function m:getName() return self.shown or typeName end
	function m:rename(name, d) self.shown, self.desc = name, d end
	return m
end
local player = {isMonster = function() return false end, getName = function() return "Knight" end}

eq(Chaos.monsterTypeName(monster("Charged Mechanic Goblin", "a charged mechanic goblin", "Abyssal Spawn")),
	"Charged Mechanic Goblin", "a renamed monster: its type name")
eq(Chaos.monsterTypeName(monster("Dragon", "a dragon")), "Dragon", "a plain monster: its name")
eq(Chaos.monsterTypeName(player), "Knight", "a player: its name")
eq(Chaos.monsterTypeName(nil), nil, "nothing: nil")
local broken = {isMonster = function() return true end, getType = function() error("no type") end,
	getName = function() return "Odd" end}
eq(Chaos.monsterTypeName(broken), "Odd", "a type lookup that fails: the shown name")

eq(Chaos.nameDescriptionOf("Abyssal Spawn"), "an abyssal spawn", "vowel: an")
eq(Chaos.nameDescriptionOf("Crypt Thrall"), "a crypt thrall", "consonant: a")
eq(Chaos.monsterNameDescription(monster("Dragon Lord", "a dragon lord")), "a dragon lord", "not renamed: the type's own")
eq(Chaos.monsterNameDescription(monster("Elf", "an elf", "Obsidian Hound")), "an obsidian hound", "renamed: from the name")

-- createMonsterNamed: the engine runs onSpawn before the placement; the callback (monster_tiers.lua) renames there
local placedAs, spawnCalls = nil, 0
local function onSpawn(m)
	local name = Chaos.spawnName
	if name then
		Chaos.spawnName = nil
		m:rename(name, Chaos.nameDescriptionOf(name))
	end
end
Game = {createMonster = function(typeName, pos, extended, force)
	spawnCalls = spawnCalls + 1
	if typeName == "Nothing" then
		return nil
	end
	if typeName == "Boom" then
		error("engine error")
	end
	local m = monster(typeName, "a " .. typeName:lower())
	onSpawn(m)
	placedAs = m:getName() -- what the first creature packet carries
	return m
end}
local m = Chaos.createMonsterNamed("Golden Lord", {x = 1, y = 1, z = 7}, true, false, "Abyssal Gazer")
eq(placedAs, "Abyssal Gazer", "placed under the shown name")
eq(m.desc, "an abyssal gazer", "with its description")
eq(Chaos.monsterTypeName(m), "Golden Lord", "still its type")
eq(Chaos.spawnName, nil, "the name is used once")
m = Chaos.createMonsterNamed("Golden Lord", {x = 1, y = 1, z = 7}, true, false, nil)
eq(placedAs, "Golden Lord", "no shown name: the type's")
m = Chaos.createMonsterNamed("Golden Lord", {x = 1, y = 1, z = 7}, true, false, "Golden Lord")
eq(m.shown, nil, "the type's own name: no rename")
eq(Chaos.createMonsterNamed("Nothing", {}, true, false, "Crypt Reaper"), nil, "not placed: nil")
eq(Chaos.spawnName, nil, "not placed: no name left over for the next monster")
local ok = pcall(Chaos.createMonsterNamed, "Boom", {}, true, false, "Crypt Reaper")
eq(ok, false, "an engine error is passed on")
eq(Chaos.spawnName, nil, "an engine error leaves no name over")

print(string.format("monster names tests: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end

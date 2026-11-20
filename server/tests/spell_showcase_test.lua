-- Spell showcase pack (O692, TEST ONLY helper of the spells video): server/tools/spell_showcase_core.lua and spell_showcase.lua on a mocked
-- engine. Run from server/: luajit tests/spell_showcase_test.lua
local checks, fails = 0, 0
local function eq(a, b, what)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b))
	end
end

dofile("tools/spell_showcase_core.lua")
local C = ShowcaseCore

-- the name rule
eq(C.isShowcase("Showcase Elementalist"), true, "a showcase name")
eq(C.isShowcase("Showcase"), false, "the prefix needs its space")
eq(C.isShowcase("Tester Aka"), false, "a tester is not a showcase character")
eq(C.isShowcase("Showcase Deadeye1"), false, "letters only")
eq(C.isShowcase(nil), false, "no name")
eq(C.isShowcase("Live Aldric A"), false, "a live check character is not one")

-- how many to make
eq(C.needed(0), C.MAX_PER_TICK, "an empty place: a few at a time")
eq(C.needed(C.WANT - 1), 1, "one missing")
eq(C.needed(C.WANT), 0, "full")
eq(C.needed(C.WANT + 3), 0, "more than wanted")
eq(C.needed("x"), C.MAX_PER_TICK, "junk counts as none")

-- the offsets: nearest first, none twice, never the character's own tile
local seen, first8 = {}, true
for i, o in ipairs(C.OFFSETS) do
	local key = o[1] .. "," .. o[2]
	eq(seen[key], nil, "offset " .. key .. " once")
	seen[key] = true
	eq(o[1] == 0 and o[2] == 0, false, "not the character's own tile")
	if i <= 8 and math.max(math.abs(o[1]), math.abs(o[2])) ~= 1 then first8 = false end
end
eq(first8, true, "the first eight are the ring next to the character")
local free = C.freeOffsets({["1,0"] = true})
eq(#free, #C.OFFSETS - 1, "an occupied offset is skipped")
eq(free[1][1] == 1 and free[1][2] == 0, false, "the first free offset is not the occupied one")

-- the engine file on a mock: a pack is made for a showcase character only, up to the wanted count, with the first monster name the server knows
local created, spectators, players = {}, {}, {}
local registered
function GlobalEvent(name)
	local o = {}
	function o:interval(ms) o.ms = ms end
	function o:register() registered = o end
	return o
end
function Position(x, y, z) return {x = x, y = y, z = z} end
local known = {Rotworm = true}
Game = {
	createMonster = function(name, pos, ext, force)
		if not known[name] then return nil end
		created[#created + 1] = {name = name, x = pos.x, y = pos.y, z = pos.z, force = force}
		return {}
	end,
	getSpectators = function() return spectators end,
	getPlayers = function() return players end,
}
local function player(name, x, y)
	return {getName = function() return name end, getPosition = function() return {x = x, y = y, z = 8} end}
end
dofile("tools/spell_showcase.lua")
eq(registered ~= nil and registered.ms, C.INTERVAL_MS, "the think event is registered at the interval")

players = {player("Showcase Deadeye", 100, 200), player("Tester Aka", 500, 500)}
registered.onThink(1500)
eq(#created, C.MAX_PER_TICK, "a showcase character with no monsters near gets a few")
eq(created[1].name, "Rotworm", "the first name the server knows is used (Troll is not known)")
eq(created[1].force, true, "made with force")
for _, m in ipairs(created) do
	eq(m.x >= 99 and m.x <= 101 and m.y >= 199 and m.y <= 201, true, "the first ones stand next to the character")
	eq(m.z, 8, "on its floor")
end
local tester = false
for _, m in ipairs(created) do if m.x > 400 then tester = true end end
eq(tester, false, "no pack for a tester")

-- a full pack: nothing is made; monsters standing on an offset are not covered again
created = {}
spectators = {}
for i = 1, C.WANT do
	spectators[i] = {isMonster = function() return true end, getPosition = function() return {x = 100 + i, y = 200, z = 8} end}
end
registered.onThink(1500)
eq(#created, 0, "a full pack: nothing is made")
-- a player in view is not a monster
spectators = {{isMonster = function() return false end, getPosition = function() return {x = 101, y = 200, z = 8} end}}
registered.onThink(1500)
eq(#created, C.MAX_PER_TICK, "a player does not count as a monster")

-- a server that knows no monster of the list: nothing is made, nothing raises
known = {}
created = {}
spectators = {}
registered.onThink(1500)
eq(#created, 0, "no known monster: none made")

print(string.format("spell_showcase_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

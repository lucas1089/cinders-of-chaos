-- Run from the server/ folder: luajit tests/npc_booths_test.lua (and lua5.3; CI runs both)
-- The Halls of Services (npc_booths_core.lua, npc_booths.lua, npc_booths_config.lua; server/README.md "Halls of
-- Services"). Checks: the booth rows (an NPC between two partitions, coal basins on the rest of the NPC row, a counter
-- on every tile of the row in front); a row without an NPC builds nothing; a booth per town ({[town] = name}); the
-- spot of an NPC per town; on a mocked map npc_booths.lua places every fixture once (a second setup adds nothing),
-- re-tags the hall's exit, puts the way in next to the temple, the two portals lead in and back; without the hall on
-- the map no spot is given (the NPCs stay at the temple); ChaosNpcPlace.place and the Keeper of Trials use the booth.
-- tools/services_halls_test.py checks the layout on the compiled plans.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		io.write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/npc_booths_core.lua")
local K = ChaosNpcBoothsCore
local cfg = K.cfg()

-- ---------------------------------------------------------------- pure
do
	local items = {counter = {11, 12}, partition = 13, light = 14}
	local row = {npcRow = 5, counterRow = 4, from = 1, to = 9, booths = {{x = 3, npc = "A"}, {x = 8, npc = {[2] = "B"}}}}
	local t = K.rowTiles(row, 2, items)
	local byPos = {}
	for _, e in ipairs(t) do
		byPos[e[1] .. ":" .. e[2]] = e
	end
	eq(#t, 18, "two rows of 9 tiles")
	eq(byPos["3:5"][3], "npc", "the NPC tile")
	eq(byPos["2:5"][4], 13, "a partition west of the NPC")
	eq(byPos["4:5"][4], 13, "a partition east of the NPC")
	eq(byPos["1:5"][4], 14, "a coal basin at the row's end")
	eq(byPos["5:5"][4], 14, "a coal basin between the booths")
	eq(byPos["9:5"][4], 13, "the second booth's partition at the end")
	eq(byPos["1:4"][4], 11, "counters alternate")
	eq(byPos["2:4"][4], 12, "counters alternate (2)")
	eq(byPos["9:4"][3], "counter", "a counter on every tile of the front row")
	eq(#K.rowTiles(row, 1, items), 18, "town 1 still has A: the row is built")
	eq(#K.rowTiles({npcRow = 1, counterRow = 2, from = 1, to = 5, booths = {{x = 2, npc = false}}}, 2, items), 0,
		"a row with free slots only is not built")
	eq(K.npcName({npc = {[2] = "B"}}, 1), nil, "a per-town booth without this town")
	eq(K.npcName({npc = "A"}, 7), "A", "a plain name in every town")
end

-- the configured halls
do
	local h2, h1 = K.hallOf(cfg, 2), K.hallOf(cfg, 1)
	check(h2 and h1, "a hall for Cinderhold and one for Mirewake")
	local s = K.spot(cfg, "Ascendant Oracle", 2)
	check(s and s.x == h2.at.x + 5 and s.y == h2.at.y + 27, "the Oracle's booth in Cinderhold")
	eq(K.spot(cfg, "ascendant oracle", 1).y, h1.at.y + 27, "by name, any case, in Mirewake")
	eq(K.spot(cfg, "Warden Ysolde", 2) ~= nil, true, "Cinderhold's faction NPC")
	eq(K.spot(cfg, "Warden Ysolde", 1), nil, "not in Mirewake")
	eq(K.spot(cfg, "Forgemaster Brannoc", 1) ~= nil, true, "Mirewake's faction NPC")
	eq(K.spot(cfg, "Ascendant Oracle", 4), nil, "no hall in Thornmere")
	eq(K.spot(cfg, "Nobody", 2), nil, "an NPC without a booth")
	local names = {}
	for _, b in ipairs(K.booths(cfg, h2)) do
		names[b.name] = true
	end
	for _, n in ipairs({"Ascendant Oracle", "Keeper of Trials", "Archivist Maelis", "Loot Buyer", "Material Broker",
			"Mordecai Ashwager", "Iselde Varrow", "Osric the Chandler"}) do
		check(names[n], n .. " has a booth in the main city")
	end
	local p = K.portal(cfg, h2, "descent")
	check(p and p.x == h2.at.x + cfg.portals.descent[1], "the Descent portal tile")
end

-- ---------------------------------------------------------------- the engine part on a mocked map
local tiles, created, npcs, logs = {}, {}, {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function mkItem(id, pos)
	local it = {id = id, pos = pos, aid = 0, attrs = {}}
	function it:getId() return self.id end
	function it:getActionId() return self.aid end
	function it:setActionId(a) self.aid = a end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:getPosition() return self.pos end
	return it
end
local function mkTile(x, y, z)
	local t = {items = {}, pos = {x = x, y = y, z = z}}
	function t:getGround() return true end
	function t:getItems() return self.items end
	function t:getItemById(id)
		for _, it in ipairs(self.items) do
			if it.id == id then return it end
		end
		return nil
	end
	function t:hasProperty() return false end
	function t:hasFlag() return false end
	function t:getTopCreature() return nil end
	tiles[key(x, y, z)] = t
	return t
end
Position = function(x, y, z)
	local p = {x = x, y = y, z = z}
	function p:sendMagicEffect() end
	return p
end
Tile = function(p) return tiles[key(p.x, p.y, p.z)] end
Game = {
	createItem = function(id, n, pos)
		local t = Tile(pos)
		if not t then return nil end
		local it = mkItem(id, pos)
		t.items[#t.items + 1] = it
		created[#created + 1] = it
		return it
	end,
	createNpc = function(name, pos)
		local n = {name = name, pos = pos}
		function n:getName() return self.name end
		function n:isNpc() return true end
		function n:getPosition() return self.pos end
		npcs[#npcs + 1] = n
		return n
	end,
	getSpectators = function(pos, multi, onlyPlayers, a, b, c, d)
		local out = {}
		for _, n in ipairs(npcs) do
			if math.abs(n.pos.x - pos.x) <= a and math.abs(n.pos.y - pos.y) <= c and n.pos.z == pos.z then
				out[#out + 1] = n
			end
		end
		return out
	end
}
local temples = {[2] = Position(1000, 1000, 7), [1] = Position(2000, 2000, 7)}
local function mkTown(id)
	return {getId = function() return id end, getTemplePosition = function() return temples[id] end}
end
Town = function(id) return temples[id] and mkTown(id) or nil end
Game.getTowns = function() return {mkTown(1), mkTown(2)} end
CONST_PROP_BLOCKSOLID, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE, CONST_ME_TELEPORT = 0, 0, 0, 11
MESSAGE_EVENT_ADVANCE, ITEM_ATTRIBUTE_DESCRIPTION = 19, 1
local moves, globals = {}, {}
MoveEvent = function()
	local m = {}
	function m:type(t) self.t = t end
	function m:aid(a) self.a = a end
	function m:register() moves[self.a] = self end
	return m
end
GlobalEvent = function(name)
	local g = {name = name}
	function g:register() globals[self.name] = self end
	return g
end
Chaos = {t = function(_, s, ...) return select("#", ...) > 0 and string.format(s, ...) or s end}
local realPrint = print
print = function(s) logs[#logs + 1] = s end

dofile("data/scripts/chaos/npc_booths.lua")
local X = ChaosNpcBooths

-- no hall on the map: no spot, the NPCs stand next to the temple
eq(X.spot("Ascendant Oracle", 2), nil, "no hall on the map: no booth")
eq(X.setup(), 0, "no hall set up")

-- build the Cinderhold hall's floor (its whole rectangle) and its exit portal; plus the temple surroundings
local h2 = K.hallOf(cfg, 2)
for x = h2.at.x, h2.at.x + h2.size[1] - 1 do
	for y = h2.at.y, h2.at.y + h2.size[2] - 1 do
		mkTile(x, y, h2.at.z)
	end
end
local exitTile = Tile(Position(h2.at.x + h2.exit[1], h2.at.y + h2.exit[2], h2.at.z))
local exitItem = mkItem(1387, exitTile.pos)
exitItem.aid = 47951
exitTile.items[1] = exitItem
for dx = -4, 4 do
	for dy = -4, 4 do
		mkTile(1000 + dx, 1000 + dy, 7)
	end
end
-- the first entry offset is taken: the next one is used
local o1 = cfg.entry.offsets[1]
Tile(Position(1000 + o1[1], 1000 + o1[2], 7)).items[1] = mkItem(1481, nil)

check(X.spot("Ascendant Oracle", 2) ~= nil, "the hall is on the map: the Oracle's booth")
eq(X.spot("Ascendant Oracle", 1), nil, "Mirewake's hall is not on the map")
eq(X.spotForTemple("Keeper of Trials", temples[2]).y, h2.at.y + 27, "by the temple position")
eq(X.setup(), 1, "one hall set up")
local fixtures = #K.fixtures(cfg, h2)
eq(#created, fixtures + 1, "every fixture and the entry portal placed")
for _, it in ipairs(created) do
	if it.id ~= cfg.entry.item then
		eq(it.aid, cfg.aid.fixture, "fixtures carry the fixture action id")
		break
	end
end
eq(exitItem.aid, cfg.aid.exit, "the exit portal re-tagged")
-- playtest 2026-10-16: the exit had no look text; registered like the other exits (cityportals_fx.lua labels it)
local exitReg = ChaosCityPortals.placed[ChaosCityPortalsCore.key(exitTile.pos)]
check(exitReg ~= nil and exitReg.kind == "servicesexit" and exitReg.aid == cfg.aid.exit and exitReg.town == 2,
	"the exit portal registered for its look text")
eq(ChaosCityPortals.kindOf(cfg.aid.exit), "servicesexit", "the exit's action id has a kind")
local entryItem = created[#created]
eq(entryItem.aid, cfg.aid.entry, "the way in")
local o2 = cfg.entry.offsets[2]
check(entryItem.pos.x == 1000 + o2[1] and entryItem.pos.y == 1000 + o2[2], "on the first free offset")
X.setup()
eq(#created, fixtures + 1, "a second setup adds nothing")
check(globals.ChaosNpcBoothsStartup ~= nil, "the startup event")

-- the portals
local player = {pos = nil, town = mkTown(1), msgs = {}}
function player:getPlayer() return self end
function player:teleportTo(p) self.pos = p end
function player:getPosition() return self.pos end
function player:sendTextMessage(_, m) self.msgs[#self.msgs + 1] = m end
function player:getTown() return self.town end
moves[cfg.aid.entry].onStepIn(player, entryItem, entryItem.pos, Position(1000, 1000, 7))
check(player.pos.x == h2.at.x + h2.arrival[1] and player.pos.y == h2.at.y + h2.arrival[2], "the way in leads to the arrival")
moves[cfg.aid.exit].onStepIn(player, exitItem, exitTile.pos, player.pos)
check(player.pos.x == 1000 and player.pos.y == 1000, "the exit leads to the hall's town (Cinderhold), not the character's")

-- ChaosNpcPlace.place uses the booth
dofile("data/scripts/chaos/npc_place.lua")
local npc = ChaosNpcPlace.place("Iselde Varrow", temples[2], {{1, 1}})
local want = X.spot("Iselde Varrow", 2)
check(npc and npc.pos.x == want.x and npc.pos.y == want.y, "ChaosNpcPlace.place puts the NPC in its booth")
eq(ChaosNpcPlace.place("Iselde Varrow", temples[2], {{1, 1}}), npc, "found again in its booth (no second NPC)")
eq(#npcs, 1, "one NPC")
check(#logs >= 2, "a hall not on the map is logged")
print = realPrint

print(string.format("npc_booths_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end

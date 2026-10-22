-- Run from the server/ folder: luajit tests/npc_booths_test.lua (and lua5.3; CI runs both)
-- The hub's NPC stalls (npc_booths_core.lua, npc_booths.lua, npc_booths_config.lua; server/README.md "Hub NPC
-- booths"). Checks: the real config (16 stalls on two rows of the hub, no tile twice, every Chaos NPC once, the
-- progression NPCs there, nobody at the temple); the spot of an NPC only for the hub's town / temple, by name in any
-- case; a character logging in inside a retired Hall of Services goes to the temple of the hall's town (others are
-- left alone); ChaosNpcPlace.place puts an NPC in its stall (and finds it again), and next to the temple in another
-- town. tools/patch_hub_npcs_test.py checks the spawn file side.

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

-- ---------------------------------------------------------------- the real config
do
	check(cfg.enabled, "enabled")
	eq(cfg.town, 2, "the main city's NPCs (Cinderhold)")
	eq(#cfg.booths, 16, "sixteen stalls")
	local tiles, names, rows = {}, {}, {}
	for _, b in ipairs(cfg.booths) do
		local k = b.x .. ":" .. b.y .. ":" .. b.z
		check(not tiles[k], "one stall per tile: " .. k)
		tiles[k] = true
		rows[b.y] = (rows[b.y] or 0) + 1
		eq(b.z, 7, "the hub's floor")
		check(b.x >= 31620 and b.x <= 31675, "a stall of the hub's market: " .. b.x)
		if b.npc then
			check(not names[b.npc], b.npc .. " in one stall only")
			names[b.npc] = true
			local f = io.open("data/npc/" .. b.npc .. ".xml", "r")
			check(f ~= nil, b.npc .. " is an NPC of data/npc")
			if f then
				f:close()
			end
		else
			eq(b.npc, false, "a stall without an NPC is false")
		end
	end
	eq(rows[32230], 8, "eight stalls on the north row")
	eq(rows[32236], 8, "eight stalls on the south row")
	for _, n in ipairs({"Ascendant Oracle", "Keeper of Trials", "Archivist Maelis", "Warden Ysolde", "Loot Buyer",
		"Material Broker", "Osric the Chandler", "Iselde Varrow", "Mordecai Ashwager", "Cassian Auric", "Tavish Coldhand",
		"Halvard Deedkeeper", "Vessa Hollowmark", "Pell Ashmere"}) do
		check(names[n], n .. " has a stall in the hub")
	end
	eq(#K.booths(cfg), 14, "fourteen NPCs, two empty stalls")
	-- the temple's portal gallery holds no NPC any more
	local gallery = dofile("data/scripts/chaos/temple_portals_config.lua")
	for _, t in ipairs(gallery.towns) do
		eq(t.stands, nil, "no NPC stands at the temple of " .. t.name)
	end
end

-- ---------------------------------------------------------------- pure
do
	local s = K.spot(cfg, "Ascendant Oracle", 2)
	check(s and s.x == 31642 and s.y == 32236 and s.z == 7, "the Oracle's stall")
	eq(K.spot(cfg, "keeper of trials", 2).x, 31636, "by name, any case")
	eq(K.spot(cfg, "Ascendant Oracle", 1), nil, "no stall in Mirewake")
	eq(K.spot(cfg, "Nobody", 2), nil, "an NPC without a stall")
	eq(K.spot(cfg, nil, 2), nil, "no name")
	eq(K.spotForTemple(cfg, "Warden Ysolde", cfg.temple).x, 31622, "by the hub town's temple")
	eq(K.spotForTemple(cfg, "Warden Ysolde", {x = 32957, y = 32076, z = 7}), nil, "another temple: none")
	eq(K.spotForTemple(cfg, "Warden Ysolde", nil), nil, "no temple: none")
	eq(K.spot({enabled = false, town = 2, booths = cfg.booths}, "Ascendant Oracle", 2), nil, "off: none")
	eq(#K.booths({enabled = false, booths = cfg.booths}), 0, "off: no booths")
	-- the retired halls
	local h = K.retiredHallAt(cfg, {x = 14570, y = 14830, z = 7})
	check(h and h.town == 2, "inside Cinderhold's old hall")
	h = K.retiredHallAt(cfg, {x = 14560 + 65, y = 14870 + 33, z = 7})
	check(h and h.town == 1, "the last tile of Mirewake's old hall")
	eq(K.retiredHallAt(cfg, {x = 14560 + 66, y = 14830, z = 7}), nil, "just east of the hall")
	eq(K.retiredHallAt(cfg, {x = 14570, y = 14830, z = 6}), nil, "another floor")
	eq(K.retiredHallAt(cfg, {x = 32369, y = 32241, z = 7}), nil, "the temple")
	eq(K.retiredHallAt(cfg, nil), nil, "no position")
end

-- ---------------------------------------------------------------- the engine part
local npcs, logs, effects = {}, {}, 0
Position = function(x, y, z)
	local p = {x = x, y = y, z = z}
	function p:sendMagicEffect() effects = effects + 1 end
	return p
end
local tiles = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
Tile = function(p) return tiles[key(p.x, p.y, p.z)] end
local function mkTile(x, y, z)
	local t = {pos = {x = x, y = y, z = z}}
	function t:getGround() return true end
	function t:getItems() return {} end
	function t:getItemCount() return 0 end
	function t:hasProperty() return false end
	function t:hasFlag() return false end
	function t:getTopCreature() return nil end
	function t:getCreatureCount() return 0 end
	function t:getHouse() return nil end
	tiles[key(x, y, z)] = t
	return t
end
Game = {
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
local temples = {[2] = Position(32369, 32241, 7), [1] = Position(32957, 32076, 7)}
local function mkTown(id)
	return {getId = function() return id end, getTemplePosition = function() return temples[id] end}
end
Town = function(id) return temples[id] and mkTown(id) or nil end
Game.getTowns = function() return {mkTown(1), mkTown(2)} end
CONST_PROP_BLOCKSOLID, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE, TILESTATE_HOUSE, CONST_ME_TELEPORT = 0, 0, 0, 0, 11
MESSAGE_EVENT_ADVANCE = 19
local events = {}
CreatureEvent = function(name)
	local e = {name = name}
	function e:type(t) self.t = t end
	function e:register() events[self.name] = self end
	return e
end
GlobalEvent = function(name)
	local g = {name = name}
	function g:interval() end
	function g:register() end
	return g
end
Chaos = {t = function(_, s, ...) return select("#", ...) > 0 and string.format(s, ...) or s end}
local realPrint = print
print = function(s) logs[#logs + 1] = s end

dofile("data/scripts/chaos/npc_booths.lua")
local X = ChaosNpcBooths

local s = X.spot("Archivist Maelis", 2)
check(s and s.x == 31628 and s.y == 32236, "the Archivist's stall (a Position)")
eq(X.spot("Archivist Maelis", 1), nil, "none in Mirewake")
eq(X.spotForTemple("Keeper of Trials", temples[2]).x, 31636, "the Keeper by the temple position")

-- relocation at login
local function mkPlayer(x, y, z, town)
	local p = {pos = Position(x, y, z), town = mkTown(town), msgs = {}}
	function p:getPosition() return self.pos end
	function p:teleportTo(q) self.pos = q end
	function p:getTown() return self.town end
	function p:sendTextMessage(_, m) self.msgs[#self.msgs + 1] = m end
	return p
end
local login = events.ChaosRetiredHallLogin
check(login ~= nil and login.t == "login", "the login event")
local p1 = mkPlayer(14580, 14840, 7, 1)
eq(login.onLogin(p1), true, "login goes on")
check(p1.pos.x == 32369 and p1.pos.y == 32241, "inside Cinderhold's old hall: to Cinderhold's temple (the hall's town)")
check(#p1.msgs == 1 and p1.msgs[1]:find("Hall of Services is closed", 1, true), "told why")
local p2 = mkPlayer(14580, 14880, 7, 2)
login.onLogin(p2)
check(p2.pos.x == 32957 and p2.pos.y == 32076, "inside Mirewake's old hall: to Mirewake's temple")
local p3 = mkPlayer(32370, 32246, 7, 2)
login.onLogin(p3)
check(p3.pos.x == 32370 and p3.pos.y == 32246 and #p3.msgs == 0, "anywhere else: left alone")
-- an error in the relocation never stops a login
local bad = mkPlayer(14580, 14840, 7, 2)
bad.teleportTo = function() error("boom") end
eq(login.onLogin(bad), true, "an error is caught")
check(#logs >= 1 and tostring(logs[#logs]):find("boom", 1, true), "and logged")

-- ChaosNpcPlace.place uses the stall in the hub's town, the temple elsewhere
for dx = -4, 4 do
	for dy = -4, 4 do
		mkTile(32957 + dx, 32076 + dy, 7)
	end
end
dofile("data/scripts/chaos/npc_place.lua")
local npc = ChaosNpcPlace.place("Archivist Maelis", temples[2], {{1, 1}})
check(npc and npc.pos.x == 31628 and npc.pos.y == 32236, "ChaosNpcPlace.place puts the NPC in its stall")
eq(ChaosNpcPlace.place("Archivist Maelis", temples[2], {{1, 1}}), npc, "found again in its stall (no second NPC)")
local other = ChaosNpcPlace.place("Loot Buyer", temples[1], {{2, 2}})
check(other and other.pos.x == 32959 and other.pos.y == 32078, "another town: next to its temple")
eq(#npcs, 2, "two NPCs")
print = realPrint

print(string.format("npc_booths_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end

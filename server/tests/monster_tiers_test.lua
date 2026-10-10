-- Run from the server/ folder: luajit tests/monster_tiers_test.lua (or lua5.3; CI runs both)
-- monster_tiers.lua against a mocked engine that behaves like this one: onSpawn callbacks run before the placement, and
-- a monster gets its id only at the placement (getId() is 0 inside onSpawn). Natural rolls, boss tiers, the ambush on
-- a normal kill, ambush copies, forced tiers (ChaosApplyTier) and the rename callback at index -100.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- mocked engine
local spawnCallbacks, creatureEvents, events, byId, messages = {}, {}, {}, {}, {}
local nextId = 0x40000000

local function registerCallback(self, index)
	local p = rawget(self, "_pending")
	rawset(self, "_pending", nil)
	if p[1] == "onSpawn" then
		spawnCallbacks[#spawnCallbacks + 1] = {fn = p[2], index = index or 0, order = #spawnCallbacks}
		table.sort(spawnCallbacks, function(a, b)
			if a.index ~= b.index then
				return a.index < b.index
			end
			return a.order < b.order
		end)
	end
end
-- `local cb = EventCallback; cb.onSpawn = fn; cb:register(index)`: the global collects one callback at a time
EventCallback = setmetatable({register = registerCallback}, {__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end})

function CreatureEvent(name)
	local ev = {name = name}
	function ev:register()
		creatureEvents[name] = self
	end
	return ev
end

function addEvent(fn, ms, ...)
	events[#events + 1] = {fn = fn, args = {...}, n = select("#", ...)}
end
local unpack = table.unpack or unpack
-- one pass over what is scheduled now (a modifier tick schedules the next one)
local function runEvents()
	local now = events
	events = {}
	for _, e in ipairs(now) do
		e.fn(unpack(e.args, 1, e.n))
	end
end

local function position(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end,
		getDistance = function(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end}
end

local spectators = {}
Game = {getSpectators = function() return spectators end}

-- types: maxHealth, boss flag
local types = {
	Dragon = {hp = 1000}, Rat = {hp = 20}, ["Dragon Lord"] = {hp = 1900},
	Ferumbras = {hp = 50000, boss = true}, ["Blocked"] = {hp = 1000}
}

local function newMonster(typeName)
	local t = types[typeName]
	local mt = {name = function() return typeName end, isBoss = function() return t.boss or false end}
	local m = {id = 0, typeName = typeName, maxHealth = t.hp, health = t.hp, speed = 200, events = {}, order = {},
		outfit = {lookType = 34, lookShader = 0}, pos = position(0, 0, 0)}
	function m:getId() return self.id end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getType() return mt end
	function m:getName() return self.shown or typeName end
	function m:rename(name) self.shown = name end
	function m:getMaster() return nil end
	function m:getMaxHealth() return self.maxHealth end
	function m:setMaxHealth(v) self.maxHealth = v end
	function m:getHealth() return self.health end
	function m:setHealth(v) self.health = v end
	function m:changeSpeed(d) self.speed = self.speed + d end
	function m:getOutfit()
		local o = {}
		for k, v in pairs(self.outfit) do
			o[k] = v
		end
		return o
	end
	function m:setOutfit(o) self.outfit = o end
	function m:getPosition() return self.pos end
	function m:registerEvent(name)
		if self.events[name] then
			return false
		end
		self.events[name] = true
		self.order[#self.order + 1] = name
		return true
	end
	function m:unregisterEvent(name)
		if not self.events[name] then
			return false
		end
		self.events[name] = nil
		return true
	end
	return m
end

-- onSpawn runs before the placement (id 0); the placement gives the id ("Blocked" never places)
function Game.createMonster(typeName, pos, extended, force)
	local m = newMonster(typeName)
	m.idInsideOnSpawn = {}
	for _, cb in ipairs(spawnCallbacks) do
		m.idInsideOnSpawn[#m.idInsideOnSpawn + 1] = m:getId()
		if cb.fn(m, pos, false, true) == false then
			return nil
		end
	end
	if typeName == "Blocked" then
		return nil
	end
	nextId = nextId + 1
	m.id = nextId
	m.pos = position(pos.x, pos.y, pos.z)
	byId[m.id] = m
	return m
end
function Creature(id) return byId[id] end
Monster = Creature

-- the engine's checkCreatures: think events of a placed monster (a copy of the list, as getCreatureEvents returns)
local function think(m)
	local list = {}
	for _, name in ipairs(m.order) do
		if m.events[name] and creatureEvents[name] and creatureEvents[name].onThink then
			list[#list + 1] = name
		end
	end
	for _, name in ipairs(list) do
		creatureEvents[name].onThink(m, 1000)
	end
end

local player = {isPlayer = function() return true end, isMonster = function() return false end, getId = function() return 7 end,
	sendTextMessage = function(self, kind, text) messages[#messages + 1] = text end,
	getPosition = function() return position(100, 100, 7) end}
spectators = {player}

dofile("data/scripts/chaos/monster_tiers.lua")
local cfg = ChaosTierConfig
local state = ChaosTierState

local function setChance(legendary, rare, magic)
	cfg.spawnChance = {legendary = legendary, rare = rare, magic = magic}
end
local function stateCount()
	local c = 0
	for _ in pairs(state) do
		c = c + 1
	end
	return c
end

-- ---------------------------------------------------------------- the mock itself
setChance(0, 0, 0)
local plain = Game.createMonster("Dragon", position(100, 100, 7), true, false)
check(#plain.idInsideOnSpawn > 0, "mock: onSpawn callbacks ran")
for i, id in ipairs(plain.idInsideOnSpawn) do
	eq(id, 0, "mock: id inside onSpawn callback " .. i)
end
check(plain:getId() ~= 0, "mock: placed monster has its id")

-- ---------------------------------------------------------------- natural roll
setChance(10000, 0, 0)
local legend = Game.createMonster("Dragon", position(101, 100, 7), true, false)
eq(state[0], nil, "natural roll: nothing kept under id 0")
eq(legend.maxHealth, 1000, "natural roll: not applied before the placement")
think(legend)
local s = state[legend:getId()]
check(s ~= nil, "natural roll: state under the placed id")
eq(s and s.tier, "legendary", "natural roll: tier")
eq(ChaosTierOf(legend), "legendary", "natural roll: ChaosTierOf")
check(s and #s.mods >= 3, "natural roll: legendary modifiers")
check(legend.maxHealth >= 6000, "natural roll: health multiplier")
check(legend.outfit.lookShader ~= 0, "natural roll: shader")
check(legend.events.ChaosTierDeath, "natural roll: death event")
check(legend.events.ChaosModTaken, "natural roll: modifier event")
check(not legend.events.ChaosTierRollLegendary, "natural roll: the roll event removes itself")
eq(messages[#messages], "A legendary Dragon appears!", "natural roll: announced at its place")
local ticked = false
for _, e in ipairs(events) do
	if e.args[1] == legend:getId() then
		ticked = true
	end
end
check(ticked, "natural roll: modifier tick scheduled for the placed id")
local hp = legend.maxHealth
think(legend)
eq(legend.maxHealth, hp, "natural roll: a second think changes nothing")

-- monster bar: the info answer carries the tier
local sent
Chaos.send = function(p, op, action, data) sent = {action = action, data = data} end
Chaos.decode = function() return {action = "query", data = {cid = legend:getId()}} end -- no json library here
creatureEvents.ChaosTierQuery.onExtendedOpcode(player, ChaosOpcodes.monsterbar, "query")
eq(sent and sent.data.tier, "legendary", "monster bar: tier")
eq(sent and sent.data.label, "Legendary", "monster bar: label")
check(sent and #sent.data.mods >= 3, "monster bar: modifiers")
eq(sent and sent.data.role, nil, "monster bar: no role outside a rift")
eq(sent and sent.data.level, nil, "monster bar: no level without the loot script")
-- a rift guardian and an Omen guardian (rift.lua's run of the monster), the level from loot.lua
ChaosLoot = {monsterLevel = function(m) return 245.6 end}
ChaosRift = {monsterRun = {[legend:getId()] = {bossIds = {[legend:getId()] = true}}}}
creatureEvents.ChaosTierQuery.onExtendedOpcode(player, ChaosOpcodes.monsterbar, "query")
eq(sent and sent.data.role, "guardian", "monster bar: rift guardian")
eq(sent and sent.data.level, 245, "monster bar: level")
ChaosRift.monsterRun[legend:getId()].omen = "storm"
creatureEvents.ChaosTierQuery.onExtendedOpcode(player, ChaosOpcodes.monsterbar, "query")
eq(sent and sent.data.role, "omen", "monster bar: omen guardian")
ChaosRift.monsterRun[legend:getId()] = {bossIds = {}}
creatureEvents.ChaosTierQuery.onExtendedOpcode(player, ChaosOpcodes.monsterbar, "query")
eq(sent and sent.data.role, nil, "monster bar: a rift pack monster has no role")
ChaosLoot.monsterLevel = function() error("no type") end
creatureEvents.ChaosTierQuery.onExtendedOpcode(player, ChaosOpcodes.monsterbar, "query")
eq(sent and sent.data.level, nil, "monster bar: a failing level is left out")
ChaosLoot, ChaosRift = nil, nil

-- the tier damages: a hit from the legendary is doubled (or more)
local dmg = creatureEvents.ChaosTierHit.onHealthChange({isPlayer = function() return false end}, legend, -100, 1, 0, 1, 0)
check(dmg <= -200, "natural roll: damage multiplier")

-- ---------------------------------------------------------------- normal kills still bring ambushes after a roll
setChance(0, 0, 0)
local normal = Game.createMonster("Dragon", position(102, 100, 7), true, false)
think(normal)
eq(ChaosTierOf(normal), "normal", "normal spawn: normal")
check(normal.events.ChaosTierDeath, "normal spawn after a tiered one: death event (ambush on kill)")
cfg.ambush.normal = 10000
local before = stateCount()
events = {}
creatureEvents.ChaosTierDeath.onDeath(normal, nil, player, player)
runEvents()
local copy = byId[nextId]
check(copy ~= normal and copy.typeName == "Dragon", "ambush: a copy is created")
local cs = state[copy:getId()]
check(cs ~= nil and cs.tier ~= "normal", "ambush: copy tiered under its id")
eq(cs and cs.depth, 1, "ambush: depth")
eq(state[0], nil, "ambush: nothing under id 0")
eq(stateCount(), before + 1, "ambush: one new tier state")
think(copy)
eq(state[copy:getId()], cs, "ambush: no natural roll on top of the copy's tier")

-- ---------------------------------------------------------------- forced tier wins over the natural roll
setChance(10000, 0, 0)
local forced = Game.createMonster("Dragon", position(103, 100, 7), true, false)
check(ChaosApplyTier(forced, "magic"), "forced: applied")
local fhp = forced.maxHealth
think(forced)
eq(ChaosTierOf(forced), "magic", "forced: keeps the forced tier")
eq(forced.maxHealth, fhp, "forced: no second health multiplier")

-- ---------------------------------------------------------------- bosses, skip list, small monsters, failed placement
setChance(10000, 0, 0)
local boss = Game.createMonster("Ferumbras", position(104, 100, 7), true, false)
think(boss)
eq(ChaosTierOf(boss), "boss", "boss: boss tier")
check(state[boss:getId()] and #state[boss:getId()].mods >= 4, "boss: modifiers under its id")

cfg.skip["dragon lord"] = true
local skipped = Game.createMonster("Dragon Lord", position(105, 100, 7), true, false)
think(skipped)
eq(state[skipped:getId()], nil, "skip list: no tier")
check(not skipped.events.ChaosTierDeath, "skip list: no ambush death event")
cfg.skip["dragon lord"] = nil

local rat = Game.createMonster("Rat", position(106, 100, 7), true, false)
think(rat)
eq(state[rat:getId()], nil, "below minMaxHealth: no tier")

local count0 = stateCount()
eq(Game.createMonster("Blocked", position(107, 100, 7), true, false), nil, "failed placement: nil")
eq(stateCount(), count0, "failed placement: no tier state")
eq(state[0], nil, "failed placement: nothing under id 0")

-- ---------------------------------------------------------------- shown names (rename callback at -100 runs first)
setChance(10000, 0, 0)
messages = {}
local named = Chaos.createMonsterNamed("Dragon", position(108, 100, 7), true, false, "Abyssal Gazer")
eq(named:getName(), "Abyssal Gazer", "shown name: renamed before the placement")
think(named)
eq(ChaosTierOf(named), "legendary", "shown name: rolled by its type")
eq(messages[#messages], "A legendary Abyssal Gazer appears!", "shown name: announced under the shown name")
eq(state[0], nil, "end: nothing ever under id 0")

print(string.format("monster tiers tests: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end

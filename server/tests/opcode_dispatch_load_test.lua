-- Run from the server/ folder: luajit tests/opcode_dispatch_load_test.lua (and lua5.3; CI runs both)
-- The extended opcode dispatch of chaos_constants.lua when the file is first loaded outside the Scripts interface.
-- In the engine every interface shares one Lua state, and a spell (thief/shadow_veil.lua: ChaosSpell.loadClasses,
-- dofile classes.lua) loads chaos_constants.lua first, in the spells' interface, where CreatureEvent() reports an
-- error and gives nil. The file's own load from data/scripts then returned at `if Chaos then return end`: the dispatch
-- event was never made, Player:registerEvent was never hooked, and no client request reached a Chaos handler (found in
-- a live client, 2026-10-13: the bestiary, achievements, leaderboard, siege and pets windows never opened).
-- The engine mock is the one of tests/opcode_dispatch_test.lua, with a switch for the interface.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

-- ---------------------------------------------------------------- engine mock
local scriptsInterface = false -- CreatureEvent() works only in the Scripts interface
local engineEvents = {}
local metatables = {}
function rawgetmetatable(name)
	return metatables[name]
end
CreatureEvent = {}
local instanceMT = {__index = CreatureEvent}
metatables.CreatureEvent = instanceMT
setmetatable(CreatureEvent, {__call = function(self, name)
	if not scriptsInterface then
		return nil -- luaCreateCreatureEvent: "CreatureEvents can only be registered in the Scripts interface."
	end
	return setmetatable({_name = name}, instanceMT)
end})
function CreatureEvent.type(self, t) rawset(self, "_type", t) end
local function callback(self, fn) rawset(self, "_fn", fn) return true end
CreatureEvent.onExtendedOpcode = callback
CreatureEvent.onLogout = callback
function CreatureEvent.register(self)
	if not rawget(self, "_fn") then
		return false
	end
	engineEvents[self._name] = self
	return true
end
instanceMT.__newindex = function(self, key, value)
	if key == "onExtendedOpcode" then
		self:type("extendedopcode")
		self:onExtendedOpcode(value)
		return
	elseif key == "onLogout" then
		self:type("logout")
		self:onLogout(value)
		return
	end
	rawset(self, key, value)
end

Creature = {}
function Creature.registerEvent(self, name)
	if not engineEvents[name] then
		return false
	end
	self.events[#self.events + 1] = name
	return true
end
function Creature.unregisterEvent(self, name)
	return false
end
Player = setmetatable({}, {__index = Creature})
local playerMT = {__index = Player}
function Player.getId(self) return self.id end
function Player.getName(self) return "Tester" .. self.id end
local function sendOpcode(player, opcode, buffer)
	for _, name in ipairs(player.events) do
		local ev = engineEvents[name]
		if ev and ev._type == "extendedopcode" then
			ev._fn(player, opcode, buffer)
		end
	end
end

-- ---------------------------------------------------------------- the load order of the engine
-- 1. a spell loads the file in the spells' interface
dofile("data/scripts/chaos/chaos_constants.lua")
ok(Chaos ~= nil and Chaos.opcodeDispatch ~= nil, "the first load (spells' interface) defines Chaos")
ok(engineEvents.ChaosOpcodeDispatch == nil, "no engine event outside the Scripts interface")

-- 2. the Scripts interface: modules (some before chaos_constants.lua, alphabetically) and the file itself
scriptsInterface = true
local got = {}
local function module(name, opcode)
	local OPCODE = opcode
	local ev = CreatureEvent(name)
	function ev.onExtendedOpcode(player, op, buffer)
		if op ~= OPCODE then
			return
		end
		got[#got + 1] = name .. ":" .. buffer
	end
	ev:register()
end
module("ChaosBestiaryExtended", 253)
dofile("data/scripts/chaos/chaos_constants.lua") -- data/scripts/chaos/chaos_constants.lua as a revscript
module("ChaosPetsExtended", 240)
ok(engineEvents.ChaosOpcodeDispatch ~= nil, "the Scripts interface's load makes the dispatch event")
ok(engineEvents.ChaosOpcodeDispatchLogout ~= nil, "and its logout event")
dofile("data/scripts/chaos/chaos_constants.lua")
ok(Chaos.opcodeDispatch.installed == true, "a third load changes nothing")

-- 3. a player logs in and the modules register their events
local p = setmetatable({id = 7, events = {}}, playerMT)
ok(p:registerEvent("ChaosBestiaryExtended") == true, "a dispatched name registers")
ok(p:registerEvent("ChaosPetsExtended") == true, "a name defined after the install registers")
local n = 0
for _, e in ipairs(p.events) do
	if e == "ChaosOpcodeDispatch" then
		n = n + 1
	end
end
ok(n == 1, "the one engine event is registered once: " .. n)
sendOpcode(p, 253, '{"action":"open"}')
sendOpcode(p, 240, '{"action":"list"}')
ok(got[1] == 'ChaosBestiaryExtended:{"action":"open"}', "the bestiary request reaches its handler: " .. tostring(got[1]))
ok(got[2] == 'ChaosPetsExtended:{"action":"list"}', "the pets request reaches its handler: " .. tostring(got[2]))
ok(#got == 2, "each request reaches only its own handler")

if fails > 0 then
	print(string.format("opcode_dispatch_load_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("opcode_dispatch_load_test: all %d checks passed", checks))

-- Run from the server/ folder: luajit tests/spells_interface_load_test.lua (and lua5.3; CI runs both)
-- A spell loads the class rules before any revscript: thief/shadow_veil.lua -> _common.lua ChaosSpell.loadClasses ->
-- classes.lua -> chaos_constants.lua, all in the spells' interface. There CreatureEvent() reports "CreatureEvents can
-- only be registered in the Scripts interface." with a traceback (start log 2026-10-16). Here the mocked
-- CreatureEvent throws outside the Scripts interface: the spell side must load Chaos and ChaosClasses without calling
-- it, the classes work, and the Scripts interface's own load of chaos_constants.lua then makes the dispatch events.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

-- ---------------------------------------------------------------- engine mock
local scriptsInterface = false
local created = {}
local metatables = {}
function rawgetmetatable(name)
	return metatables[name]
end
CreatureEvent = {}
local instanceMT = {__index = CreatureEvent}
metatables.CreatureEvent = instanceMT
setmetatable(CreatureEvent, {__call = function(self, name)
	if not scriptsInterface then
		error("LuaScriptInterface::luaCreateCreatureEvent(). CreatureEvents can only be registered in the Scripts interface.")
	end
	created[#created + 1] = name
	return setmetatable({_name = name}, instanceMT)
end})
function CreatureEvent.type(self, t) rawset(self, "_type", t) end
CreatureEvent.onExtendedOpcode = function(self, fn) rawset(self, "_fn", fn) return true end
CreatureEvent.onLogout = CreatureEvent.onExtendedOpcode
function CreatureEvent.register(self) return true end
instanceMT.__newindex = function(self, key, value)
	if key == "onLogout" then
		self:type("logout")
		rawset(self, "_fn", value)
		return
	end
	rawset(self, key, value)
end
Creature = {}
function Creature.registerEvent() return true end
function Creature.unregisterEvent() return true end
Player = setmetatable({}, {__index = Creature})
function Player.getId(self) return self.id end

-- what the spells' interface has besides: the spell supports wrapper and the effect ids are loaded elsewhere
ChaosSupportsSpell = {cast = function() return nil end}
Fx, FxMissile = {}, {}
NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
CONST_ME_POFF = 3

-- ---------------------------------------------------------------- 1. a spell loads the classes
local loaded, err = pcall(dofile, "data/spells/chaos/_common.lua")
ok(loaded, "_common.lua loads in the spells' interface: " .. tostring(err))
local okClasses, classes = pcall(function() return ChaosSpell.loadClasses() end)
ok(okClasses, "ChaosSpell.loadClasses() does not call CreatureEvent(): " .. tostring(classes))
ok(okClasses and type(classes) == "table" and classes == ChaosClasses, "it gives ChaosClasses")
ok(Chaos ~= nil and Chaos.classes ~= nil, "Chaos and its class numbers are loaded")
ok(#created == 0, "no engine event made outside the Scripts interface")
ok(Chaos and Chaos.opcodeDispatch and not Chaos.opcodeDispatch.installed, "the dispatch is not installed yet")
ok(okClasses and type(ChaosClasses.now) == "function", "the class rules are usable")

-- a second spell: nothing new, still no call
local again = pcall(function() return ChaosSpell.loadClasses() end)
ok(again and #created == 0, "a second spell: still no CreatureEvent() call")

-- ---------------------------------------------------------------- 2. the Scripts interface's own load
scriptsInterface = true
local okScripts, errScripts = pcall(dofile, "data/scripts/chaos/chaos_constants.lua")
ok(okScripts, "the revscript load: " .. tostring(errScripts))
ok(Chaos.opcodeDispatch.installed == true, "the Scripts interface installs the dispatch")
local made = table.concat(created, ",")
ok(made == "ChaosOpcodeDispatch,ChaosOpcodeDispatchLogout", "its two engine events: " .. made)

if fails > 0 then
	print(string.format("spells_interface_load_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("spells_interface_load_test: all %d checks passed", checks))

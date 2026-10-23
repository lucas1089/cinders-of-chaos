-- Run from the server/ folder: luajit tests/retired_spells_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- O145 (owner beta report 2026-10-23, "some of my support spells disappeared"): the login clean-up of the retired spells
-- (retired_spells_core.lua, retired_spells.lua, retired_spells_config.lua): learned rows of retired spells are forgotten,
-- the class that lost Galeborne Stride is told once, and the list matches what patch_spell_cap.py retires.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

dofile("data/scripts/chaos/retired_spells_core.lua")
local C = ChaosRetiredSpellsCore
local cfg = dofile("data/scripts/chaos/retired_spells_config.lua")

-- ------------------------------------------------------------------ the rules
local known = {["Galeborne Stride"] = true, ["Arc Bolt"] = true, ["Minor Mending"] = true}
local list = C.forgetList(cfg.names, function(name) return known[name] end)
eq(table.concat(list, ","), "Arc Bolt,Galeborne Stride", "retired rows only, sorted; a live spell stays")
eq(#C.forgetList({"A", "A"}, function() return true end), 1, "a name twice counts once")
eq(#C.forgetList(nil, function() return true end), 0, "no list")
eq(#C.forgetList(cfg.names, function() return false end), 0, "nothing learned: nothing to forget")

local MYSTIC, WARRIOR, THIEF = 1, 4, 11
eq(#C.due(cfg.notices, 1, 0, MYSTIC, 100), 1, "a Mystic is told")
eq(C.due(cfg.notices, 1, 0, MYSTIC, 100)[1].name, "Galeborne Stride", "which spell")
eq(#C.due(cfg.notices, 1, 0, WARRIOR, 100), 0, "the Warrior never had it")
eq(#C.due(cfg.notices, 1, 0, THIEF, 19), 0, "below the spell's level: nothing was lost yet")
eq(#C.due(cfg.notices, 1, 0, THIEF, 20), 1, "at the spell's level")
eq(#C.due(cfg.notices, 1, 1, MYSTIC, 100), 0, "told once")
eq(#C.due(cfg.notices, 2, 1, MYSTIC, 100), 1, "a new version is told again")
eq(#C.due(cfg.notices, 1, -1, MYSTIC, 100), 1, "an unset storage (-1) is never told")
local expect = {[1] = 1, [5] = 1, [11] = 1, [12] = 1, [13] = 1, [17] = 1, [18] = 1, [19] = 1, [20] = 1, [21] = 1, [22] = 1}
for voc = 1, 25 do
	eq(#C.due(cfg.notices, 1, 0, voc, 100), expect[voc] or 0, "vocation " .. voc)
end

-- ------------------------------------------------------------------ the engine part
Chaos = {t = function(player, text) return "[" .. (player.lang or "en") .. "] " .. text end}
local scheduled, events = {}, {}
function addEvent(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, ms = ms, args = {...}} end
function CreatureEvent(name) local e = {name = name}; function e:type(t) self.kind = t end; function e:register() events[name] = self end; return e end
local players = {}
function Player(id) return players[id] end
local function newPlayer(id, voc, level, learned)
	local p = {id = id, store = {}, messages = {}, calls = {}, learned = learned or {}}
	function p:getId() return id end
	function p:getVocation() return {getId = function() return voc end} end
	function p:getLevel() return level end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:setStorageValue(k, v) self.store[k] = v end
	function p:hasLearnedSpell(name) return self.learned[name] == true end
	function p:forgetSpell(name) self.learned[name] = nil; self.calls[#self.calls + 1] = "forget " .. name; return true end
	function p:sendTextMessage(kind, text) self.messages[#self.messages + 1] = text end
	players[id] = p
	return p
end
ChaosI18n = {}
dofile("data/scripts/chaos/retired_spells.lua")
local R = ChaosRetiredSpells
local login = events.ChaosRetiredSpellsLogin
eq(login and login.kind, "login", "a login event")

local mystic = newPlayer(1, MYSTIC, 120, {["Galeborne Stride"] = true, ["Second Wind"] = true, ["Minor Mending"] = true})
eq(login.onLogin(mystic), true, "login goes on")
eq(mystic.learned["Galeborne Stride"], nil, "the retired row is forgotten")
eq(mystic.learned["Second Wind"], nil, "the other retired row too")
eq(mystic.learned["Minor Mending"], true, "a live spell is kept")
eq(#scheduled, 1, "the notice is scheduled")
eq(scheduled[1].ms, cfg.delayMs, "after the delay")
scheduled[1].fn(unpack and unpack(scheduled[1].args) or table.unpack(scheduled[1].args))
eq(#mystic.messages, 1, "one message")
assert(mystic.messages[1]:find("Galeborne Stride was retired", 1, true), "it names the spell")
assert(mystic.messages[1]:find("Fleetfoot and Vigil of Haste", 1, true), "and the replacements")
eq(mystic.store[cfg.storage], cfg.version, "the version is marked")
-- a second login: the row clean-up is a no-op and nothing is told again
scheduled = {}
login.onLogin(mystic)
scheduled[1].fn(scheduled[1].args[1])
eq(#mystic.messages, 1, "told once")
eq(#mystic.calls, 2, "nothing forgotten twice")

-- a Warrior is marked without a message, and a player gone before the notice is skipped
scheduled = {}
local warrior = newPlayer(2, WARRIOR, 300)
login.onLogin(warrior)
scheduled[1].fn(scheduled[1].args[1])
eq(#warrior.messages, 0, "the Warrior had no such spell")
eq(warrior.store[cfg.storage], cfg.version, "marked all the same")
scheduled = {}
newPlayer(3, MYSTIC, 100)
login.onLogin(players[3])
players[3] = nil
scheduled[1].fn(scheduled[1].args[1])

-- a failing engine call does not stop the login
local broken = newPlayer(4, MYSTIC, 100, {["Galeborne Stride"] = true})
function broken:forgetSpell() error("boom") end
eq(login.onLogin(broken), true, "forgetSpell may fail")

-- ------------------------------------------------------------------ the data
-- the list is the stock spells patch_spell_cap.py retires (CAP entries without a class) plus the three cure retirements
local cap = read("tools/patch_spell_cap.py")
local retired, count = {}, 0
for name, keep in cap:gmatch("%(%d+, '([^']*)', (%b())%),") do
	if keep == "()" then retired[name] = true; count = count + 1 end
end
for name, keep in cap:gmatch("%(%d+, \"([^\"]*)\", (%b())%),") do
	if keep == "()" then retired[name] = true; count = count + 1 end
end
assert(count >= 60, "parsed the CAP table: " .. count)
local inList = {}
for _, name in ipairs(cfg.names) do
	assert(not inList[name], "name twice: " .. name)
	inList[name] = true
end
for name in pairs(retired) do
	assert(inList[name], "retired by patch_spell_cap.py but not forgotten at login: " .. name)
end
for _, name in ipairs({"Hawkeye", "Bulwark", "Windrunner"}) do
	assert(inList[name], name)
end
eq(#cfg.names, count + 3, "every other name is a cure retirement")

-- no name is a spell a class has now (Chaos spells and the kit)
local xml = read("data/spells/chaos/spells_chaos.xml")
for name in xml:gmatch('<instant[^>]-name="([^"]+)"') do
	assert(not inList[name], "a live Chaos spell is on the forget list: " .. name)
end

-- the notice text has a pt-BR translation
local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for _, notice in ipairs(cfg.notices) do
	assert(strings[notice.text], "pt-BR text of the notice " .. notice.name)
	assert(#notice.text <= 250, "short enough for one message")
end
-- the storage key is new
for _, f in ipairs({"data/scripts/chaos/chaos_constants.lua"}) do
	assert(not read(f):find(tostring(cfg.storage), 1, true), "storage key " .. cfg.storage .. " is used in " .. f)
end
print("retired_spells tests OK")

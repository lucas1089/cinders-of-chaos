-- Run from the server/ folder: luajit tests/potions_helper_test.lua (and lua5.3; CI runs both)
-- The helper is told which Everfull potion each slot carries (README "Potions", "The helper and the tiers", O246):
-- potions_core.lua heldView / heldKey / heldPayload, data/lib/chaos_potions.lua PT.heldView / PT.sendHeld,
-- potions_helper.lua (login, the client's `sync`, the 3 s think) and the opcode.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/potions_core.lua")
local cfg = dofile("data/scripts/chaos/potions_config.lua")
local K = ChaosPotionsCore

-- the looks: every Everfull tier shows under its stock potion's client id (the tests of the client helper list the same)
local LOOK = {[32085] = 266, [32086] = 268, [32261] = 239, [32262] = 238, [32263] = 7642, [32264] = 7643, [32265] = 23373,
	[32266] = 23374, [32267] = 23375}
local function clientId(id) return LOOK[id] end
local FULL = {health = 500, mana = 800}

-- ---------------------------------------------------------------- core
local v = K.heldView(cfg, {counts = {}, charges = FULL, clientId = clientId})
eq(next(v), nil, "nothing carried: an empty view")
eq(K.heldKey(v), "health:-|mana:-", "its key")
eq(K.heldPayload(v).v, 1, "an empty payload is still an object (version field)")

v = K.heldView(cfg, {counts = {[32085] = 1, [32086] = 1}, charges = FULL, clientId = clientId})
eq(v.health.look, 266, "tier 1 health: the Health Potion look") eq(v.mana.look, 268, "tier 1 mana: the Mana Potion look")
eq(v.health.tier, 1, "tier 1") eq(v.health.level, 0, "no level gate") eq(v.health.line, "health", "line") eq(v.health.ready, true, "full flask: ready")

v = K.heldView(cfg, {counts = {[32261] = 1, [32265] = 1}, charges = FULL, clientId = clientId})
eq(v.health.look, 239, "great health: the Great Health Potion look") eq(v.health.tier, 2, "tier 2") eq(v.health.level, 80, "level 80")
eq(v.mana.look, 23373, "ultimate mana: its look") eq(v.mana.tier, 3, "tier 3") eq(v.mana.level, 130, "level 130")

v = K.heldView(cfg, {counts = {[32267] = 1}, charges = FULL, clientId = clientId})
eq(v.health.look, 23375, "supreme health") eq(v.health.tier, 4, "tier 4") eq(v.mana, nil, "no mana flask carried: no mana slot")

v = K.heldView(cfg, {counts = {[32263] = 1}, charges = FULL, clientId = clientId})
eq(v.health.look, 7642, "great spirit sits in the health slot, under the Great Spirit look") eq(v.health.line, "spirit", "spirit line")
eq(v.mana, nil, "and takes no mana slot")

-- ready: a spirit drink needs a whole charge in BOTH pools; a plain flask only in its own
v = K.heldView(cfg, {counts = {[32263] = 1}, charges = {health = 500, mana = 99}, clientId = clientId})
eq(v.health.ready, false, "spirit with the mana pool short: not ready")
v = K.heldView(cfg, {counts = {[32263] = 1}, charges = {health = 99, mana = 800}, clientId = clientId})
eq(v.health.ready, false, "spirit with the health pool short: not ready")
v = K.heldView(cfg, {counts = {[32261] = 1, [32262] = 1}, charges = {health = 500, mana = 0}, clientId = clientId})
eq(v.health.ready, true, "the health flask does not care about the mana pool") eq(v.mana.ready, false, "an empty mana flask")
v = K.heldView(cfg, {counts = {[32261] = 1}, charges = {health = 100, mana = 0}, clientId = clientId})
eq(v.health.ready, true, "exactly one charge is ready")

-- a character that holds two (a GM gift) is told the higher tier; a count of 0 and a missing look are nothing
v = K.heldView(cfg, {counts = {[32085] = 1, [32264] = 1}, charges = FULL, clientId = clientId})
eq(v.health.look, 7643, "the higher tier of two health items")
v = K.heldView(cfg, {counts = {[32085] = 0}, charges = FULL, clientId = clientId})
eq(next(v), nil, "count 0: not carried")
v = K.heldView(cfg, {counts = {[32085] = 1}, charges = FULL, clientId = function() return nil end})
eq(next(v), nil, "an item type without a client id is not told")
v = K.heldView(cfg, {counts = {[32085] = 1}, charges = FULL, clientId = function() return 0 end})
eq(next(v), nil, "client id 0 is not a look")
v = K.heldView(cfg, {counts = {[999999] = 3}, charges = FULL, clientId = clientId})
eq(next(v), nil, "an item that is not an Everfull one is ignored")

-- the key changes with every field the client sees, and only then
local a = K.heldView(cfg, {counts = {[32261] = 1}, charges = FULL, clientId = clientId})
local b = K.heldView(cfg, {counts = {[32261] = 1}, charges = {health = 400, mana = 3}, clientId = clientId})
eq(K.heldKey(a), K.heldKey(b), "charges that stay ready change nothing")
local c2 = K.heldView(cfg, {counts = {[32261] = 1}, charges = {health = 0, mana = 3}, clientId = clientId})
check(K.heldKey(a) ~= K.heldKey(c2), "a flask that empties changes the key")
local d = K.heldView(cfg, {counts = {[32264] = 1}, charges = FULL, clientId = clientId})
check(K.heldKey(a) ~= K.heldKey(d), "an upgrade changes the key")
local p = K.heldPayload(a)
eq(p.health.look, 239, "payload: look") eq(p.health.tier, 2, "tier") eq(p.health.level, 80, "level") eq(p.health.line, "health", "line")
eq(p.health.ready, true, "ready") eq(p.mana, nil, "no mana slot")

-- every Everfull entry of the config has a look in this table (a new tier must be added to the client helper too)
for _, e in ipairs(cfg.everfull) do
	check(LOOK[e.id] ~= nil, "the test knows the look of " .. e.name)
end

-- ---------------------------------------------------------------- the opcode
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.everfull, 116, "opcode 116")
local seen = {}
for name, op in pairs(ChaosOpcodes) do
	if op == 116 then seen[#seen + 1] = name end
end
eq(#seen, 1, "no other Chaos opcode has 116")
local f = io.open("../client/overlay/modules/game_helperrotation/everfullheld.lua", "r")
check(f ~= nil, "the client listens in game_helperrotation/everfullheld.lua")
if f then
	local src = f:read("*a") f:close()
	check(src:find("116", 1, true) ~= nil, "and names 116")
end

-- ---------------------------------------------------------------- potions_helper.lua on a mocked engine
RETURNVALUE_NOERROR = 0
CONST_SLOT_FIRST, CONST_SLOT_LAST = 1, 10
local registered = {}
local function event(name)
	local e = {name = name}
	function e:register() registered[name or "action"] = self end
	function e:type() end
	function e:interval(ms) self.ms = ms end
	return e
end
CreatureEvent, GlobalEvent = event, event
Action = function() return event(nil) end
local installed = true
ItemType = function(id)
	return {getId = function() return installed and id or 0 end, getClientId = function() return LOOK[id] or id end}
end
local added = {}
function addEvent(fn, ms) added[#added + 1] = {fn = fn, ms = ms} end
local players = {}
Player = function(id) return players[id] end
local online = {}
Game = {getPlayers = function() return online end, getTowns = function() return {} end}
ChaosRateLimit = nil

local function mkPlayer(id, items)
	local p = {id = id, st = {}, items = items or {}, sent = {}, events = {}}
	function p:getId() return self.id end
	function p:getName() return "P" .. self.id end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:registerEvent(n) self.events[#self.events + 1] = n end
	function p:sendExtendedOpcode(op, buffer) self.sent[#self.sent + 1] = {op = op, buffer = buffer} end
	players[id] = p
	return p
end
json = json or {encode = function(t)
	local function enc(x)
		if type(x) == "table" then
			local keys = {}
			for k in pairs(x) do keys[#keys + 1] = k end
			table.sort(keys)
			local out = {}
			for _, k in ipairs(keys) do out[#out + 1] = string.format("%q:%s", k, enc(x[k])) end
			return "{" .. table.concat(out, ",") .. "}"
		end
		return type(x) == "string" and string.format("%q", x) or tostring(x)
	end
	return enc(t)
end, decode = function(s)
	local t = {}
	for k, val in s:gmatch('"(%w+)"%s*:%s*"(%w+)"') do t[k] = val end
	return t
end}
Chaos.decode = Chaos.decode or function(s) return json.decode(s) end

dofile("data/scripts/chaos/potions_helper.lua")
local PT = ChaosPotions
local login, logout, ext, think = registered.ChaosPotionsHeldLogin, registered.ChaosPotionsHeldLogout,
	registered.ChaosPotionsHeldExtended, registered.ChaosPotionsHeldThink
check(login and logout and ext and think, "login, logout, opcode and think registered")
eq(think.ms, 3000, "a 3 s think")

local ann = mkPlayer(1, {[32261] = 1, [32086] = 1})
online = {ann}
login.onLogin(ann)
eq(#ann.events, 2, "the login registers the opcode and logout events")
eq(#ann.sent, 0, "nothing at once: the client may not listen yet")
eq(#added, 1, "one delayed send") added[1].fn()
eq(#ann.sent, 1, "sent after the delay") eq(ann.sent[1].op, 116, "on opcode 116")
check(ann.sent[1].buffer:find('"action":"held"', 1, true) ~= nil, "action held")
check(ann.sent[1].buffer:find('"look":239', 1, true) ~= nil, "the great health look")
check(ann.sent[1].buffer:find('"look":268', 1, true) ~= nil, "the mana flask look")

-- unchanged: the think sends nothing; changed: it sends once
think.onThink(3000)
eq(#ann.sent, 1, "unchanged: nothing sent")
ann.st[cfg.storage.healthCharges] = 0 -- the flask empties
think.onThink(3000)
eq(#ann.sent, 2, "an emptied flask is told") check(ann.sent[2].buffer:find('"ready":false', 1, true) ~= nil, "not ready")
think.onThink(3000)
eq(#ann.sent, 2, "and once")
ann.items = {[32264] = 1, [32086] = 1} -- the upgrade swapped the item
think.onThink(3000)
eq(#ann.sent, 3, "an upgrade is told") check(ann.sent[3].buffer:find('"look":7643', 1, true) ~= nil, "the ultimate look")
ann.items = {} -- everything moved to the depot
think.onThink(3000)
eq(#ann.sent, 4, "nothing carried any more is told too")
check(ann.sent[4].buffer:find('"look"', 1, true) == nil, "with no slot")

-- the client's sync: always answered, the request carries no data that is read
ext.onExtendedOpcode(ann, 115, '{"action":"sync"}')
eq(#ann.sent, 4, "another opcode: ignored")
ext.onExtendedOpcode(ann, 116, 'not json')
eq(#ann.sent, 4, "garbage: ignored")
ext.onExtendedOpcode(ann, 116, '{"action":"look","look":"239"}')
eq(#ann.sent, 4, "an unknown action: ignored")
ext.onExtendedOpcode(ann, 116, '{"action":"sync"}')
eq(#ann.sent, 5, "sync: sent again even if unchanged")
local limited = 0
ChaosRateLimit = {allow = function() limited = limited + 1 return false end}
ext.onExtendedOpcode(ann, 116, '{"action":"sync"}')
eq(#ann.sent, 5, "rate limited") eq(limited, 1, "one check")
ChaosRateLimit = nil

-- logout forgets, so the next login tells again
logout.onLogout(ann)
eq(PT.heldSent[1], nil, "forgotten")
-- a not installed item type (install_potions.py did not run) is never counted
installed = false
local bob = mkPlayer(2, {[32261] = 1})
eq(next(PT.heldView(bob)), nil, "items.otb without the Everfull nodes: an empty view")
installed = true

print(string.format("potions_helper_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

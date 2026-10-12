-- Run from the server/ folder: luajit tests/instances_test.lua (and lua5.3; CI runs both)
-- The instance registry of chaos_constants.lua (Chaos.registerInstance / inAnyInstance / instanceAt / sweepIntruders):
-- the Town Portal, the hideout and the store teleports refuse inside every instance, the hideout never returns a
-- player into an instance area, and the group instances sweep strangers out of their slots.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")

local function newPlayer(id, pos, staff)
	local p = {id = id, pos = pos, msgs = {}}
	function p:getId() return self.id end
	function p:getPosition() return self.pos end
	function p:getGroup() return {getAccess = function() return staff == true end} end
	function p:getTown() return {getTemplePosition = function() return {x = 1, y = 1, z = 7} end} end
	function p:teleportTo(q) self.pos = q end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	return p
end

-- ---------------------------------------------------------------- registry
local members = {[1] = true}
Chaos.registerInstance("raid", {label = "a raid", inside = function(p) return members[p:getId()] end,
	at = function(pos) return pos.x >= 1000 and pos.x < 1100 end})
Chaos.registerInstance("broken", {label = "a broken one", inside = function() error("boom") end, at = function() error("boom") end})
Chaos.registerInstance("hideout", {label = "a hideout", at = function(pos) return pos.x >= 5000 end})

local member = newPlayer(1, {x = 10, y = 10, z = 7})
local stranger = newPlayer(2, {x = 1050, y = 10, z = 7})
local outside = newPlayer(3, {x = 10, y = 10, z = 7})
local key, label = Chaos.inAnyInstance(member)
eq(key, "raid", "a member is inside (membership)")
eq(label, "a raid", "label")
eq(Chaos.inAnyInstance(stranger), "raid", "a stranger standing in the area is inside (area)")
eq(Chaos.inAnyInstance(outside), nil, "nobody else; an erroring check counts as no")
eq(Chaos.instanceAt({x = 1001, y = 1, z = 7}), "raid", "instanceAt")
eq(Chaos.instanceAt({x = 10, y = 1, z = 7}), nil, "instanceAt outside")
local inHideout = newPlayer(4, {x = 5001, y = 1, z = 7})
eq(Chaos.inAnyInstance(inHideout), "hideout", "hideout registered")
eq(Chaos.inAnyInstance(inHideout, "hideout"), nil, "except")
-- registering again replaces, keeps one entry
local before = #Chaos.instanceOrder
Chaos.registerInstance("raid", Chaos.instances.raid)
eq(#Chaos.instanceOrder, before, "re-register keeps the order list")

-- ---------------------------------------------------------------- sweep
local staff = newPlayer(5, {x = 1060, y = 10, z = 7}, true)
local inMember = newPlayer(1, {x = 1070, y = 10, z = 7})
Game = {getPlayers = function() return {stranger, staff, inMember, outside} end}
local sent = Chaos.sweepIntruders(Chaos.instances.raid.at, Chaos.instances.raid.inside)
eq(sent, 1, "only the stranger is sent out")
eq(stranger.pos.x, 1, "stranger at the temple")
eq(#stranger.msgs, 1, "told why")
eq(staff.pos.x, 1060, "staff stays")
eq(inMember.pos.x, 1070, "member stays")
local run = {}
eq(Chaos.sweepDue(run, 10000), true, "first sweep due")
eq(Chaos.sweepDue(run, 10000 + Chaos.instanceSweepMs - 1), false, "throttled")
eq(Chaos.sweepDue(run, 10000 + Chaos.instanceSweepMs), true, "due again")
Game = {}
eq(Chaos.sweepIntruders(function() return true end, function() return false end), 0, "no Game.getPlayers: nothing")

-- ---------------------------------------------------------------- saveCharacter
local saver = {save = function() return true end}
eq(Chaos.saveCharacter(saver), true, "save ok")
eq(Chaos.saveCharacter({save = function() return false end}), false, "save failed")
eq(Chaos.saveCharacter({save = function() error("db down") end}), false, "save raised")

-- ---------------------------------------------------------------- the refusals
dofile("data/scripts/chaos/townportal_core.lua")
local why = ChaosTownPortalCore.blockReason({instance = "a raid"})
eq(type(why) == "string" and why:find("a raid", 1, true) ~= nil, true, "town portal refused inside a raid")
dofile("data/scripts/chaos/hideout_core.lua")
eq(ChaosHideoutCore.enterProblem({instance = true}) ~= nil, true, "hideout refused inside an instance")

-- ---------------------------------------------------------------- wiring: every instance registers, the callers ask
local function src(f)
	local h = assert(io.open("data/scripts/chaos/" .. f, "r"))
	local s = h:read("*a")
	h:close()
	return s
end
local registered = {
	["rift.lua"] = "rift", ["dungeons.lua"] = "dungeon", ["infinitytower_run.lua"] = "tower", ["arena.lua"] = "arena",
	["worldboss.lua"] = "worldboss", ["siege.lua"] = "siege", ["raid.lua"] = "raid", ["descent.lua"] = "descent",
	["uber.lua"] = "ascended", ["guildboss.lua"] = "guildboss", ["battleground.lua"] = "battleground",
	["trials.lua"] = "trials", ["ascension_quest.lua"] = "ascension", ["pvpzone.lua"] = "marches", ["hideout.lua"] = "hideout"
}
for f, k in pairs(registered) do
	eq(src(f):find('Chaos.registerInstance("' .. k .. '"', 1, true) ~= nil, true, f .. " registers " .. k)
end
for _, f in ipairs({"raid.lua", "descent.lua", "uber.lua", "guildboss.lua", "battleground.lua"}) do
	eq(src(f):find("Chaos.sweepIntruders(", 1, true) ~= nil, true, f .. " sweeps strangers out of its slot")
end
eq(src("townportal.lua"):find("instance = Chaos.inAnyInstance", 1, true) ~= nil, true, "town portal asks the registry")
eq(src("hideout.lua"):find("instance = Chaos.inAnyInstance", 1, true) ~= nil, true, "hideout enterFacts sets instance")
eq(src("hideout.lua"):find("Chaos.instanceAt(p", 1, true) ~= nil, true, "hideout leave checks the stored spot")
eq(src("shop_services.lua"):find("Chaos.inAnyInstance(player", 1, true) ~= nil, true, "store teleports ask the registry")
eq(src("siege.lua"):find("function S.isInside(player)", 1, true) ~= nil, true, "ChaosSiege.isInside exists")
eq(src("siege.lua"):find("function S.isInsidePos(pos)", 1, true) ~= nil, true, "ChaosSiege.isInsidePos exists")

print(string.format("instances_test: %d checks OK", checks))

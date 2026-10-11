-- Run from the server/ folder: luajit tests/rate_limits_test.lua (and lua5.3; CI runs both)
-- Chaos.limited (chaos_constants.lua over ratelimit.lua) and the opcode handlers that use it: every action of these
-- modules is limited per player and action, so a flood of requests cannot hammer the database.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
function CreatureEvent() local o = {}; function o:type() end; function o:register() end; return o end
local clock = 5000
os.mtime = function() return clock end
eq(Chaos.limited({getId = function() return 1 end}, "x.y", 300), false, "no ratelimit.lua loaded: never limited")
dofile("data/scripts/chaos/ratelimit.lua")
local p = {getId = function() return 7 end}
eq(Chaos.limited(p, "bounty.accept", 300), false, "first request")
eq(Chaos.limited(p, "bounty.accept", 300), true, "a second one inside 300 ms is dropped")
eq(Chaos.limited(p, "bounty.open", 300), false, "another action is not")
clock = clock + 300
eq(Chaos.limited(p, "bounty.accept", 300), false, "allowed again")

local function src(f)
	local h = assert(io.open("data/scripts/chaos/" .. f, "r"))
	local s = h:read("*a")
	h:close()
	return s
end
local keys = {["season.lua"] = "season", ["siege.lua"] = "siege", ["arena.lua"] = "arena", ["bounty.lua"] = "bounty",
	["rift.lua"] = "rift", ["season_journey.lua"] = "journey", ["season_modes.lua"] = "seasonmodes", ["daily.lua"] = "daily",
	["hunt.lua"] = "hunt", ["invasion.lua"] = "invasion", ["infinitytower.lua"] = "tower", ["patchnotes.lua"] = "patchnotes",
	["bestiary.lua"] = "bestiary"}
for f, k in pairs(keys) do
	eq(src(f):find('Chaos.limited(player, "' .. k .. '." .. tostring(', 1, true) ~= nil, true, f .. " limits its requests")
end
local pt = src("passivetree.lua")
eq(pt:find('ChaosRateLimit.allow(player, "passivetree.save", 1000)', 1, true) ~= nil, true, "passive tree saves are limited")
eq(pt:find('ChaosRateLimit.allow(player, "passivetree.reset", 1000)', 1, true) ~= nil, true, "passive tree resets are limited")

print(string.format("rate_limits_test: %d checks OK", checks))

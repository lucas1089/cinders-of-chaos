-- Run from the server/ folder: lua5.3 tests/waystone_test.lua (mock engine API; CI runs it)
Chaos = {}
local cb
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, k, v) end})
function EventCallback:register() cb = self.onGainExperience end
dofile("data/scripts/chaos/waystone_bonuses.lua")
local W = ChaosWaystone
assert(W.experienceMultiplier(-1) == 1, "unset storage")
assert(W.experienceMultiplier(0) == 1)
assert(math.abs(W.experienceMultiplier(50) - 1.5) < 1e-9)
assert(math.abs(W.experienceMultiplier(100) - 2.0) < 1e-9)
assert(math.abs(W.experienceMultiplier(250) - 2.0) < 1e-9, "clamped to the upgrade maximum")
local function player(level) return {getStorageValue = function(_, k) return k == W.experienceStorage and level or -1 end} end
local monster = {isMonster = function() return true end}
local other = {isMonster = function() return false end}
assert(cb(player(50), monster, 1000, 10) == 1500)
assert(cb(player(-1), monster, 1000, 10) == 1000)
assert(cb(player(50), other, 1000, 10) == 1000, "only experience from monsters")
assert(cb(player(50), nil, 1000, 10) == 1000)
print("waystone_test: ok")

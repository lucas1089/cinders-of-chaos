-- Run from the server/ folder: luajit tests/reward_sparkle_test.lua (reward chest sparkle registry; CI runs it with
-- LuaJIT and Lua 5.3). Also checks the reward chest ids of the configs: one eye-catching, non-moveable chest.
local cfg = dofile("data/scripts/chaos/reward_sparkle_config.lua")
dofile("data/scripts/chaos/reward_sparkle_core.lua")
local K = ChaosRewardSparkleCore

local fails, count = 0, 0
local function check(cond, name)
	count = count + 1
	if not cond then
		fails = fails + 1
		print("FAIL: " .. name)
	end
end
local function eq(a, b, name)
	check(a == b, name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- registry
local s = K.new()
eq(K.count(s), 0, "empty")
check(K.add(s, cfg, "rift:1", {x = 1, y = 2, z = 7}, 21584, 100), "add a chest")
check(not K.add(s, cfg, "bad", nil, 21584, 100), "no position: refused")
eq(K.count(s), 1, "one chest")
check(K.add(s, cfg, "rift:1", {x = 1, y = 2, z = 7}, 21584, 110), "add again refreshes")
eq(K.count(s), 1, "still one chest")
local d = K.due(s, cfg, 120)
eq(#d, 1, "due: the chest")
eq(d[1].pos.x, 1, "due: its position")
eq(d[1].itemId, 21584, "due: its item")

-- the position is copied
local p = {x = 5, y = 5, z = 7}
K.add(s, cfg, "copy", p, 21584, 120)
p.x = 99
local found
for _, e in ipairs(K.due(s, cfg, 121)) do
	if e.key == "copy" then
		found = e
	end
end
eq(found and found.pos.x, 5, "position copied at add")
check(K.remove(s, "copy"), "remove")
check(not K.remove(s, "copy"), "remove twice: false")
eq(K.count(s), 1, "one left")

-- check(): false ends the glint
local open = true
K.add(s, cfg, "check", {x = 2, y = 2, z = 7}, 21584, 130, function() return open end)
eq(#K.due(s, cfg, 131), 2, "both glint")
open = false
eq(#K.due(s, cfg, 132), 1, "the taken chest stops")
eq(K.count(s), 1, "the taken chest is dropped")
K.add(s, cfg, "err", {x = 3, y = 2, z = 7}, 21584, 133, function() error("boom") end)
eq(#K.due(s, cfg, 134), 1, "an erroring check drops its chest")

-- exists(): the chest item is gone
K.add(s, cfg, "gone", {x = 4, y = 2, z = 7}, 21584, 140)
local d2 = K.due(s, cfg, 141, function(pos) return pos.x ~= 4 end)
eq(#d2, 1, "a chest no longer on its tile does not glint")
eq(K.count(s), 1, "and is dropped")

-- maxAge
local s2 = K.new()
K.add(s2, cfg, "old", {x = 1, y = 1, z = 7}, 21584, 0)
eq(#K.due(s2, cfg, cfg.maxAge), 1, "at maxAge: still")
eq(#K.due(s2, cfg, cfg.maxAge + 1), 0, "past maxAge: dropped")

-- maxEntries: the oldest go
local s3 = K.new()
local small = {maxEntries = 3, maxAge = 1000}
for i = 1, 5 do
	K.add(s3, small, "k" .. i, {x = i, y = 1, z = 7}, 21584, 0)
end
eq(K.count(s3), 3, "capped")
local keys = {}
for _, e in ipairs(K.due(s3, small, 1)) do
	keys[#keys + 1] = e.key
end
eq(table.concat(keys, ","), "k3,k4,k5", "the newest stay")

-- config
check(cfg.intervalMs >= 1000, "one shared timer, not faster than 1 s")
check(type(cfg.effect) == "string" and cfg.effect:match("^CONST_ME_") ~= nil, "effect is a CONST_ME name")

-- ---------------------------------------------------------------- the reward chest ids
-- 32311 "reward chest" (the one-tile look: client 38758, redrawn in pair 53; a copy of 21584: container 32, not moveable /
-- pickupable); 32310 is its 2 x 2 look of pair 45, only a legacy id now (the map step moves its chests to 32311)
-- 21584 the stock reward chest it falls back to while 32311 is not installed
-- 32312 "sealed coffer" (O315: the 2 x 2 big gold chest art of pair 45, client 38657; a copy of 21584, install_reward_chest.py) is
-- the rift's sealed coffer (needs a container); it is not 32310, the reward chest's legacy id, so the map step never moves it
-- 12664 "treasure chest" (2x2, blue and silver, container 20, not moveable): the coffer's fallback while 32312 is not installed
local REWARD, STOCK, COFFER, COFFER_FALLBACK = 32311, 21584, 32312, 12664
local rift = dofile("data/scripts/chaos/rift_config.lua")
eq(rift.chest.itemId, REWARD, "rift chest: the reward chest")
eq(rift.chest.fallbackId, STOCK, "rift chest: falls back to the stock reward chest")
eq(table.concat(rift.chest.legacyItemIds, ","), "32310", "rift chest: the 2 x 2 look is a legacy id (only the map patch reads it)")
check(rift.chest.legacyItemIds[1] ~= rift.chest.itemId and rift.chest.legacyItemIds[1] ~= rift.chest.fallbackId, "the legacy look is not the reward chest")
eq(rift.chest.smallItemId, nil, "no second look any more: every reward chest is the one-tile look")
eq(rift.coffer.itemId, COFFER, "rift coffer: the big gold chest look, an item of its own")
eq(rift.coffer.fallbackId, COFFER_FALLBACK, "rift coffer: falls back to the stock treasure chest")
check(rift.coffer.actionId == 47403 and rift.chest.actionId == 47402, "coffer and chest keep their own action ids")
for _, id in ipairs(rift.chest.legacyItemIds) do
	check(id ~= rift.coffer.itemId, "the coffer is not a legacy reward chest id (the map step moves those to 32311)")
end
local descent = dofile("data/scripts/chaos/descent_config.lua")
eq(descent.objects.chest, REWARD, "Descent treasure room chest: the reward chest")
eq(descent.objects.chestFallback, STOCK, "Descent treasure room chest: falls back to the stock reward chest")
check(rift.chest.itemId ~= rift.coffer.itemId, "chest and coffer differ (the coffer is looked up by id on its tile)")
check(rift.chest.fallbackId ~= rift.coffer.itemId and rift.chest.fallbackId ~= rift.coffer.fallbackId,
	"the reward chest's fallback is not the coffer, nor the coffer's fallback")
check(rift.chest.itemId ~= rift.coffer.fallbackId, "the reward chest is not the coffer's fallback")

if fails > 0 then
	print(string.format("reward_sparkle_test: %d of %d checks failed", fails, count))
	os.exit(1)
end
print(string.format("reward_sparkle_test: all %d checks passed", count))

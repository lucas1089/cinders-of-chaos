-- Run from the server/ folder: luajit tests/attack_speed_cap_test.lua (and lua5.3; CI runs both)
-- The attack speed cap (engine patch 0011, server/README.md "Attack speed cap"): ChaosItemMods.effectiveInterval
-- mirrors Player::getAttackSpeed of the patched engine (vocation scaling, the weapon's own interval with its attack
-- speed modifier and topaz gems, dexterity, the total bonus cap and the interval floor); the config defaults agree with
-- the patch; and a simulation of the patch's leech rule (one life leech heal per minPlayerLeechInterval).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

ITEM_ATTRIBUTE_ATTACK_SPEED = 3
dofile("data/lib/chaos_item_mods.lua")
local M = ChaosItemMods
local E = M.effectiveInterval

-- ---------------------------------------------------------------- the defaults agree with the engine patch
local f = io.open("src-patches/0011-attack-speed-cap.patch", "r")
local patch = f:read("*a")
f:close()
eq(patch:find('"minPlayerAttackInterval", ' .. M.attackCap.minInterval .. ')', 1, true) ~= nil, true, "floor default")
eq(patch:find('"maxPlayerAttackSpeedBonus", ' .. M.attackCap.maxBonus .. ')', 1, true) ~= nil, true, "bonus default")
eq(patch:find('"minPlayerLeechInterval", 900)', 1, true) ~= nil, true, "leech default")

-- configManager (when the engine has the keys) wins over the defaults
configKeys = {MIN_PLAYER_ATTACK_INTERVAL = 101, MAX_PLAYER_ATTACK_SPEED_BONUS = 102}
configManager = {getNumber = function(k) return k == 101 and 800 or 30 end}
local cap = M.attackCapConfig()
eq(cap.minInterval, 800) eq(cap.maxBonus, 30)
configKeys, configManager = nil, nil
cap = M.attackCapConfig()
eq(cap.minInterval, 1000) eq(cap.maxBonus, 40, "40% since 2026-10-28 (owner)")

-- ---------------------------------------------------------------- the old formula when the cap is off
local OFF = {minInterval = 0, maxBonus = 0}
eq(E(0, 0, 2000, 0, OFF), 2000, "no weapon: the vocation's")
eq(E(0, 0, 1300, 0, OFF), 1300, "Shadowfist unarmed")
eq(E(3000, 3000, 2000, 0, OFF), 3000, "two-handed, own interval")
eq(E(0, 1600, 1300, 0, OFF), 1040, "Shadowfist, weapon +20% (2000 -> 1600) x 1300/2000")
eq(E(0, 1600, 1300, 20, OFF), 832, "... and dexterity 20")
eq(E(0, 1600, 1400, 20, OFF), 896, "Ninja: same")
eq(E(3000, 2400, 2000, 20, OFF), 1920, "two-handed: -20% weapon, -20% dexterity")

-- ---------------------------------------------------------------- with the cap (defaults: floor 1000 ms, bonus 40%)
local ms, capped, raw = E(0, 0, 1300, 0)
eq(ms, 1300) eq(capped, false) eq(raw, 1300)
ms, capped = E(0, 0, 1300, 20)
eq(ms, 1040, "Shadowfist unarmed + dexterity 20: -20%, under the bonus cap and the floor") eq(capped, false)
ms, capped, raw = E(0, 1600, 1300, 20)
eq(ms, 1000, "fastest build: the floor") eq(capped, true) eq(raw, 832)
ms, capped = E(0, 1600, 1300, 0)
eq(ms, 1040, "Shadowfist, weapon +20%: above the floor") eq(capped, false)
ms, capped = E(0, 1600, 1400, 20)
eq(ms, 1000, "Ninja: the floor") eq(capped, true)
ms, capped = E(0, 1600, 1600, 20)
eq(ms, 1024, "Thief: -36%, under the 40% cap") eq(capped, false)
ms, capped = E(0, 1600, 2000, 20)
eq(ms, 1280, "any 2000 class: weapon -20% and dexterity 20 multiply to -36%") eq(capped, false)
ms, capped = E(3000, 2400, 2000, 20)
eq(ms, 1920, "two-handed: 3000 x 0.64") eq(capped, false)
ms, capped = E(0, 1600, 2000, 20, nil, 20)
eq(ms, 1200, "any 2000 class: everything maxed stops at 2000 x 0.60") eq(capped, true)
ms, capped = E(1700, 1700, 2000, 0)
eq(ms, 1700, "a weapon's own fast interval is no bonus") eq(capped, false)
ms, capped = E(0, 1600, 2000, 0)
eq(ms, 1600, "weapon +20% alone stays under the bonus cap") eq(capped, false)
ms = E(0, 1600, 2000, 150)
eq(ms, 1200, "a dexterity out of range is clamped")
ms = E(0, 1600, 2000, -5)
eq(ms, 1600, "negative dexterity counts as 0")

-- every vocation and every bonus combination: never under the floor, never more than 40% off its base
for _, voc in ipairs({1300, 1400, 1500, 1600, 1700, 1800, 2000}) do
	for _, typeSpeed in ipairs({0, 1700, 1800, 2700, 3000}) do
		for pct = 0, 20, 5 do
			for dex = 0, 20, 5 do
				local own = pct > 0 and M.attackInterval(typeSpeed, pct) or typeSpeed
				local base = math.floor((typeSpeed > 0 and typeSpeed or 2000) * voc / 2000)
				if own == 0 then
					base = voc
				end
				local v = E(typeSpeed, own, voc, dex)
				eq(v >= 1000, true, "floor")
				eq(v >= math.floor(base * 0.60), true, "bonus cap " .. voc .. "/" .. typeSpeed .. "/" .. pct .. "/" .. dex)
			end
		end
	end
end

-- ---------------------------------------------------------------- the leech rule (engine: Player::canLeech)
-- A Ninja at the floor (1 swing/s) with the off-hand strike (+150 ms) and 100% leech chance: hits at 0, 150, 1000,
-- 1150, ... Without the rule every hit heals (2/s), with it one heal per swing (1/s).
local function heals(hits, interval)
	local last, n = nil, 0
	for _, t in ipairs(hits) do
		if interval <= 0 or not last or t - last >= interval then
			n, last = n + 1, t
		end
	end
	return n
end
local hits = {}
for s = 0, 9 do
	hits[#hits + 1] = s * 1000
	hits[#hits + 1] = s * 1000 + 150
end
eq(heals(hits, 0), 20, "no rule: every hit heals")
eq(heals(hits, 900), 10, "one heal per second")
-- Bloodrage: main hit + 4 cleaves 100 ms later, every 2 s
hits = {}
for s = 0, 4 do
	hits[#hits + 1] = s * 2000
	for _ = 1, 4 do
		hits[#hits + 1] = s * 2000 + 100
	end
end
eq(heals(hits, 0), 25) eq(heals(hits, 900), 5, "one heal per swing")
-- a timer a millisecond early at the 1000 ms floor still heals on every swing (why 900, not 1000)
eq(heals({0, 999, 1998, 2997}, 900), 4)

-- ---------------------------------------------------------------- one attack per second at most (owner 2026-10-28)
-- No combination of sources goes under 1000 ms: vocation speed, the weapon's own interval with its attack speed modifier and
-- gems, dexterity and the player-level bonus (passive tree + worn pieces, engine patch 0078), whatever their size.
eq(M.attackCap.minInterval, 1000, "the floor is one attack per second")
local lowest = math.huge
for _, voc in ipairs({1300, 1400, 1500, 1600, 1700, 1800, 2000}) do
	for _, typeSpeed in ipairs({0, 1000, 1500, 2000, 2500}) do
		for pct = 0, 60, 5 do
			local itemSpeed = (typeSpeed > 0 or pct > 0) and M.attackInterval(typeSpeed, pct) or 0
			for dex = 0, 120, 10 do
				for bonus = 0, 120, 10 do
					local ms = E(typeSpeed, itemSpeed, voc, dex, nil, bonus)
					lowest = math.min(lowest, ms)
					eq(ms >= 1000, true, string.format("voc %d type %d weapon -%d%% dex %d bonus %d: %d ms", voc, typeSpeed, pct, dex, bonus, ms))
				end
			end
		end
	end
end
eq(lowest, 1000, "the floor is reached, never passed")
-- the player-level bonus counts like dexterity and sits inside the same 40% cap: 2000 ms class
eq(E(0, 0, 2000, 0, nil, 12), 1760, "a bonus of 12% shortens 2000 ms to 1760")
eq(E(0, 0, 2000, 20, nil, 12), 1360, "dexterity and the bonus add up: -32%")
eq(E(0, 0, 2000, 0, nil, 0), 2000, "no bonus, no change")
eq(E(0, 0, 2000, 60, nil, 0), 1200, "a bonus past 40% stops at the cap")
-- the sum of the sources is held at the player cap before the engine sees it
eq(M.config.playerSpeedCap, 12)
eq(M.playerSpeedTotal({tree = 8, gear = 10}), 12, "tree and gear together are held at the player cap")
eq(M.playerSpeedTotal({tree = 5, gear = 3}), 8)
eq(M.playerSpeedTotal({tree = -4, gear = 3}), 3, "a negative source counts as zero")

-- ---------------------------------------------------------------- 40% is reachable, but only min-maxed (owner 2026-10-28)
-- The sources at their maximum: the weapon's modifier and topaz gems together (gems config attackspeed cap), the stat
-- window's dexterity (charStatMax), the passive tree and worn pieces together (playerSpeedCap). All of them reach the
-- 40% cap; dropping any one of them clearly short of its maximum misses it.
local G = dofile("data/lib/chaos_gems_config.lua")
local weaponMax = (G.effects or G).attackspeed and (G.effects or G).attackspeed.cap or 15
local dexMax, playerMax = 20, M.config.playerSpeedCap
local function cut(w, d, b)
	local ms = E(2000, M.attackInterval(2000, w), 2000, d, nil, b)
	return 100 - ms * 100 / 2000
end
eq(weaponMax, 15, "weapon modifier and gems together") eq(playerMax, 12, "tree and worn pieces together")
eq(cut(weaponMax, dexMax, playerMax) >= 40, true, "every source at its maximum reaches the 40% cap")
eq(cut(weaponMax, dexMax, playerMax) <= 45, true, "and not far past it: no slack to skip a source")
eq(cut(weaponMax - 4, dexMax, playerMax) < 40, true, "a weapon 4 short misses it")
eq(cut(weaponMax, dexMax - 5, playerMax) < 40, true, "dexterity 5 short misses it")
eq(cut(weaponMax, dexMax, playerMax - 3) < 40, true, "tree and gear 3 short miss it")
eq(cut(0, dexMax, playerMax) < 33, true, "no weapon speed: about a third")
local set = {}
local fake = {getId = function() return 7 end, setAttackSpeedBonus = function(_, v) set.v = v end}
eq(M.setPlayerAttackSpeed(fake, "tree", 8), 8) eq(set.v, 8)
eq(M.setPlayerAttackSpeed(fake, "gear", 10), 12) eq(set.v, 12, "the engine gets the capped sum")
eq(M.playerAttackSpeed(fake), 12)
eq(M.setPlayerAttackSpeed({getId = function() return 8 end}, "tree", 5), 5, "an engine without patch 0078 is no error")
M.clearPlayerAttackSpeed(fake) eq(M.playerAttackSpeed(fake), 0)

-- ---------------------------------------------------------------- engine patch 0078 agrees
f = io.open("src-patches/0078-player-attack-speed-bonus.patch", "r")
local p78 = f:read("*a")
f:close()
eq(p78:find("dexterity = std::min<int32_t>(100, dexterity + attackSpeedBonus);", 1, true) ~= nil, true, "the bonus counts with dexterity")
eq(p78:find("setAttackSpeedBonus(int16_t value)", 1, true) ~= nil, true, "a setter that clamps")
eq(p78:find("std::min<int16_t>(100, std::max<int16_t>(0, value))", 1, true) ~= nil, true, "0 .. 100")
eq(p78:find("MIN_PLAYER_ATTACK_INTERVAL", 1, true) == nil, true, "the floor stays patch 0011's")

print(string.format("attack_speed_cap_test: %d checks OK", checks))

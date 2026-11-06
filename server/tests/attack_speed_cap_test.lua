-- Run from the server/ folder: luajit tests/attack_speed_cap_test.lua (and lua5.3; CI runs both)
-- The attack speed cap (engine patch 0011, server/README.md "Attack speed cap"): ChaosItemMods.effectiveInterval
-- mirrors Player::getAttackSpeed of the patched engine (vocation scaling, the weapon's own interval with its attack
-- speed modifier and topaz gems, dexterity, the total bonus cap and the interval floor); the config defaults agree with
-- the patch; and a simulation of the patch's leech rule (one life leech heal per minPlayerLeechInterval).
-- O426 (owner 2026-11-06, "raise the attack limit to 3 per second. Make it reachable too, but balanced"): the floor is 333 ms
-- (engine patch 0088), only a min-maxed build reaches it (the fast classes first), a typical build lands in range, and the
-- extras a hit triggers are limited per second (attack_rate_core.lua).
-- O429 (owner 2026-11-06, "lower the classes' base interval", then "keep the auto hit worth the same"): the vocation base
-- intervals are 900 / 1000 / 1150 / 1300 ms; a hit keeps its full damage at any rate, so the auto attack's damage per second
-- grows with the swing rate on purpose (no per-hit reduction any more).

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
f = io.open("src-patches/0088-attack-speed-3-per-second.patch", "r")
local patch88 = f:read("*a")
f:close()
-- 0011 keeps its old numbers (earlier patches keep applying); 0088 moves the floor and the bonus cap
eq(patch:find('"minPlayerAttackInterval", 1000)', 1, true) ~= nil, true, "0011 still names 1000")
eq(patch88:find('"minPlayerAttackInterval", ' .. M.attackCap.minInterval .. ')', 1, true) ~= nil, true, "floor default")
eq(patch88:find('"maxPlayerAttackSpeedBonus", ' .. M.attackCap.maxBonus .. ')', 1, true) ~= nil, true, "bonus default")
eq(patch:find('"minPlayerLeechInterval", 900)', 1, true) ~= nil, true, "leech default")
eq(patch88:find("minPlayerLeechInterval", 1, true) ~= nil, true, "0088 only mentions the leech line as context")

-- configManager (when the engine has the keys) wins over the defaults
configKeys = {MIN_PLAYER_ATTACK_INTERVAL = 101, MAX_PLAYER_ATTACK_SPEED_BONUS = 102}
configManager = {getNumber = function(k) return k == 101 and 800 or 30 end}
local cap = M.attackCapConfig()
eq(cap.minInterval, 800) eq(cap.maxBonus, 30)
configKeys, configManager = nil, nil
cap = M.attackCapConfig()
eq(cap.minInterval, 333, "3 attacks per second (O426)") eq(cap.maxBonus, 76, "76% since O426 (40 before)")

-- ---------------------------------------------------------------- the old formula when the cap is off
local OFF = {minInterval = 0, maxBonus = 0}
eq(E(0, 0, 2000, 0, OFF), 2000, "no weapon: the vocation's")
eq(E(0, 0, 900, 0, OFF), 900, "Shadowfist unarmed")
eq(E(3000, 3000, 2000, 0, OFF), 3000, "two-handed, own interval")
eq(E(0, 1600, 900, 0, OFF), 720, "Shadowfist, weapon +20% (2000 -> 1600) x 900/2000")
eq(E(0, 1600, 900, 20, OFF), 576, "... and dexterity 20")
eq(E(0, 1600, 1000, 20, OFF), 640, "Monk: same")
eq(E(3000, 2400, 2000, 20, OFF), 1920, "two-handed: -20% weapon, -20% dexterity")

-- ---------------------------------------------------------------- with the cap (defaults: floor 333 ms, bonus 76%)
local ms, capped, raw = E(0, 0, 900, 0)
eq(ms, 900) eq(capped, false) eq(raw, 900)
ms, capped = E(0, 0, 900, 20)
eq(ms, 720, "Shadowfist unarmed + dexterity 20: -20%, under the bonus cap and the floor") eq(capped, false)
ms, capped, raw = E(0, 1600, 900, 20)
eq(ms, 576, "Shadowfist, weapon +20% and dexterity 20") eq(capped, false) eq(raw, 576)
ms, capped = E(0, 1600, 900, 0)
eq(ms, 720, "Shadowfist, weapon +20%") eq(capped, false)
ms, capped = E(0, 1600, 1000, 20)
eq(ms, 640, "Monk / Thief: -36%") eq(capped, false)
ms, capped = E(0, 1600, 1300, 20)
eq(ms, 832, "any 1300 class: weapon -20% and dexterity 20 multiply to -36%") eq(capped, false)
ms, capped = E(3000, 2400, 1300, 20)
eq(ms, 1248, "two-handed: 3000 x 0.64 x 1300/2000") eq(capped, false)
ms, capped = E(0, 1600, 2000, 20)
eq(ms, 1280, "any 2000 class: weapon -20% and dexterity 20 multiply to -36%") eq(capped, false)
ms, capped = E(3000, 2400, 2000, 20)
eq(ms, 1920, "two-handed: 3000 x 0.64") eq(capped, false)
ms, capped = E(0, 1600, 2000, 20, nil, 20)
eq(ms, 960, "any 2000 class: weapon -20%, dexterity and tree / gear 40 points") eq(capped, false)
ms, capped = E(0, 0, 2000, 80, nil, 0)
eq(ms, 480, "dexterity 80 alone: 2000 x 0.20 is past the 76% cap: held at 2000 x 0.24") eq(capped, true)
ms, capped = E(1700, 1700, 2000, 0)
eq(ms, 1700, "a weapon's own fast interval is no bonus") eq(capped, false)
ms, capped = E(0, 1600, 2000, 0)
eq(ms, 1600, "weapon +20% alone stays under the bonus cap") eq(capped, false)
ms = E(0, 1600, 2000, 150)
eq(ms, 480, "a dexterity out of range is clamped (100 points: the 76% cap holds it)")
ms = E(0, 1600, 2000, -5)
eq(ms, 1600, "negative dexterity counts as 0")

-- every vocation and every bonus combination: never under the floor, never more than 76% off its base
for _, voc in ipairs({900, 1000, 1150, 1300, 2000}) do
	for _, typeSpeed in ipairs({0, 1700, 1800, 2700, 3000}) do
		for pct = 0, 20, 5 do
			for dex = 0, 20, 5 do
				local own = pct > 0 and M.attackInterval(typeSpeed, pct) or typeSpeed
				local base = math.floor((typeSpeed > 0 and typeSpeed or 2000) * voc / 2000)
				if own == 0 then
					base = voc
				end
				local v = E(typeSpeed, own, voc, dex)
				eq(v >= 333, true, "floor")
				eq(v >= math.floor(base * 0.24), true, "bonus cap " .. voc .. "/" .. typeSpeed .. "/" .. pct .. "/" .. dex)
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

-- ---------------------------------------------------------------- three attacks per second at most (owner 2026-11-06)
-- No combination of sources goes under 333 ms: vocation speed, the weapon's own interval with its attack speed modifier and
-- gems, dexterity and the player-level bonus (passive tree + worn pieces, engine patch 0078), whatever their size.
eq(M.attackCap.minInterval, 333, "the floor is three attacks per second")
local lowest = math.huge
for _, voc in ipairs({900, 1000, 1150, 1300, 2000}) do
	for _, typeSpeed in ipairs({0, 1000, 1500, 2000, 2500}) do
		for pct = 0, 90, 5 do
			local itemSpeed = (typeSpeed > 0 or pct > 0) and M.attackInterval(typeSpeed, pct) or 0
			for dex = 0, 120, 10 do
				for bonus = 0, 120, 10 do
					local ms = E(typeSpeed, itemSpeed, voc, dex, nil, bonus)
					lowest = math.min(lowest, ms)
					eq(ms >= 333, true, string.format("voc %d type %d weapon -%d%% dex %d bonus %d: %d ms", voc, typeSpeed, pct, dex, bonus, ms))
				end
			end
		end
	end
end
eq(lowest, 333, "the floor is reached, never passed")
-- the player-level bonus counts like dexterity and sits inside the same 76% cap: 2000 ms class
eq(E(0, 0, 2000, 0, nil, 12), 1760, "a bonus of 12% shortens 2000 ms to 1760")
eq(E(0, 0, 2000, 20, nil, 12), 1360, "dexterity and the bonus add up: -32%")
eq(E(0, 0, 2000, 0, nil, 0), 2000, "no bonus, no change")
eq(E(0, 0, 2000, 60, nil, 0), 800, "60 points: 2000 x 0.40, under the cap")
eq(E(0, 0, 2000, 90, nil, 0), 480, "a bonus past 76% stops at the cap")
-- the sum of the sources is held at the player cap before the engine sees it
eq(M.config.playerSpeedCap, 45)
eq(M.playerSpeedTotal({tree = 8, gear = 10}), 18, "tree and gear add up")
eq(M.playerSpeedTotal({tree = 15, gear = 40}), 45, "tree and gear together are held at the player cap")
eq(M.playerSpeedTotal({tree = 5, gear = 3}), 8)
eq(M.playerSpeedTotal({tree = -4, gear = 3}), 3, "a negative source counts as zero")

-- ---------------------------------------------------------------- 3 per second is reachable, but only min-maxed
-- The sources at their maximum: the weapon's modifier and topaz gems together (gems config attackspeed cap), the stat
-- window's dexterity (charStatMax), the passive tree (maxAttackSpeed 15) and worn pieces together (playerSpeedCap 45).
local G = dofile("data/lib/chaos_gems_config.lua")
local weaponMax = (G.effects or G).attackspeed and (G.effects or G).attackspeed.cap or 30
local dexMax, playerMax = 20, M.config.playerSpeedCap
local function ms(voc, w, d, b) -- the interval only
	return (E(2000, M.attackInterval(2000, w), voc, d, nil, b))
end
local function perSecond(voc, w, d, b)
	return 1000 / ms(voc, w, d, b)
end
eq(weaponMax, 30, "weapon modifier and gems together") eq(playerMax, 45, "tree and worn pieces together")
-- O429 base intervals (xml): Shadowfist / Ninja 900, Monk / Thief 1000, Iron Sage / Samurai 1150, every other class 1300
local BASES = {900, 1000, 1150, 1300}
for _, voc in ipairs(BASES) do
	eq(ms(voc, weaponMax, dexMax, playerMax), 333, "min-maxed, base " .. voc .. " reaches the floor: 3 per second")
end
-- a 1300 ms class (the slowest) needs every source near its maximum; a source clearly short of it misses 3 per second
eq(ms(1300, weaponMax - 8, dexMax, playerMax) > 333, true, "a weapon 8 short misses it")
eq(ms(1300, weaponMax, dexMax - 6, playerMax) > 333, true, "dexterity 6 short misses it")
eq(ms(1300, weaponMax, dexMax, playerMax - 9) > 333, true, "tree and gear 9 short miss it")
eq(ms(1300, 0, dexMax, playerMax) > 333, true, "no weapon speed misses it")
-- the fastest classes have room: the Shadowfist reaches the floor without any weapon speed
eq(ms(900, 0, dexMax, playerMax), 333, "Shadowfist: dexterity and tree / gear alone reach 3 per second")
eq(ms(900, weaponMax, dexMax, 0) > 333, true, "... but dexterity and a weapon alone do not (500 ms)")
eq(ms(900, weaponMax, 0, 0) > 333, true)
-- a typical build (half of every source: weapon 15, dexterity 10, tree and worn pieces 22) lands in 1.3 - 2.0 per second;
-- the class order holds (faster base, faster typical build)
local TYP = {15, 10, 22}
local last = math.huge
for _, voc in ipairs(BASES) do
	local r = perSecond(voc, TYP[1], TYP[2], TYP[3])
	eq(r >= 1.3 and r <= 2.0, true, string.format("typical base %d ms: %.2f per second in 1.30 - 2.00", voc, r))
	eq(r < last, true, "the order of the classes holds at " .. voc)
	last = r
end
-- the old best build (floor 1000, 40% cap, caps 15 / 20 / 12) swung once per second
local OLD = {minInterval = 1000, maxBonus = 40}
eq(E(2000, M.attackInterval(2000, 15), 1300, 20, OLD, 12), 1000, "an old Shadowfist maximum was 1 per second")

-- ---------------------------------------------------------------- the hit keeps its full damage (owner 2026-11-06)
dofile("data/scripts/chaos/attack_rate_core.lua")
local AR = ChaosAttackRate
eq(AR.hitFactor, nil, "no per-hit reduction any more") eq(AR.dpsFactor, nil)
eq(AR.config.curveExponent, nil) eq(AR.config.refIntervalMs, nil)
-- so the auto attack's damage per second is hit x rate: the typical build and the min-maxed build against before (the
-- classes' old base intervals are 1300 / 1400 / 1500 / 1600 / 1700 / 1800 / 2000, with the old per-hit cut below 1000 ms)
local function oldHit(i) return i >= 1000 and 1 or (i / 1000) ^ 0.63 end
local function oldInterval(base, w, d, b) return (E(2000, M.attackInterval(2000, w), base, d, nil, b)) end
local classes = {{"Shadowfist", 1300, 900}, {"Monk", 1500, 1000}, {"Iron Sage", 1700, 1150}, {"other", 2000, 1300}}
for _, c in ipairs(classes) do
	local oldTyp = oldInterval(c[2], TYP[1], TYP[2], TYP[3])
	local newTyp = ms(c[3], TYP[1], TYP[2], TYP[3])
	local gainTyp = (1000 / newTyp) / (oldHit(oldTyp) * 1000 / oldTyp)
	local newMax = ms(c[3], weaponMax, dexMax, playerMax)
	local oldMax = math.max(1000, (E(2000, M.attackInterval(2000, 15), c[2], 20, OLD, 12)))
	local gainMax = (1000 / newMax) / (1000 / oldMax)
	eq(gainTyp > 1 and gainTyp < 2.2, true, string.format("%s typical DPS x%.2f against before", c[1], gainTyp))
	eq(gainMax > 2.0 and gainMax < 4.0, true, string.format("%s min-maxed DPS x%.2f against the old best", c[1], gainMax))
end
-- a faster swing always does more auto attack damage per second now (full hit each)
eq(1000 / ms(900, 15, 10, 22) > 1000 / ms(1300, 15, 10, 22), true, "faster class, more damage per second")

-- ---------------------------------------------------------------- per-second limits of on-hit extras
-- Swings at the floor (every 333 ms, 6 s): the extras (off-hand strike, cleave, ricochet...) trigger at most limits[key] per
-- second, whatever the rate; a limit of 0 turns the rule off.
local function triggers(key, intervalMs, seconds, cfg)
	local st, n = {}, 0
	for t = 0, seconds * 1000 - 1, intervalMs do
		if AR.allow(st, key, t, cfg) then
			n = n + 1
		end
	end
	return n
end
for _, key in ipairs({"offhand", "fistOffhand", "bloodrage", "cleavingArc", "ricochet", "radiant", "undyingRage"}) do
	local per = AR.limit(key)
	eq(per > 0 and per <= 1.5, true, key .. " is limited to 1.5 per second at most")
	local n = triggers(key, 333, 6)
	eq(n <= per * 6 + 1, true, key .. " at 3 swings per second: " .. n .. " triggers in 6 s")
	eq(n >= per * 6 - 1, true, key .. " still triggers at its limit: " .. n)
	eq(triggers(key, 1000, 6), 6, key .. " at 1 per second: every swing")
end
eq(triggers("offhand", 333, 6, {limits = {offhand = 0}}), 19, "limit 0 = no rule")
eq(triggers("other", 333, 6, {procPerSecond = 1, limits = {}}), 7, "an unnamed key uses procPerSecond (one per 950 ms: 0, 999, ...)")
local pid, passed = 77, 0
for _ = 1, 5 do
	if AR.gate(pid, "offhand") then passed = passed + 1 end
end
eq(passed, 1, "the player's gate lets one of five instant triggers through") AR.clear(pid)
eq(AR.gate(pid, "offhand"), true, "a cleared player starts fresh") AR.clear(pid)
-- every on-hit extra of the config is gated where it is triggered (the engine files call arGate(pid, key))
local sites = {
	offhand = "thief_combat.lua", fistOffhand = "monk_combat.lua", bloodrage = "berserker_combat.lua",
	radiant = "templar_combat.lua", cleavingArc = "passivetree_keystones.lua", ricochet = "passivetree_keystones.lua",
	undyingRage = "passivetree_keystones.lua"}
for key, file in pairs(sites) do
	local fh = io.open("data/scripts/chaos/" .. file, "r")
	local src = fh:read("*a")
	fh:close()
	eq(src:find('arGate(player:getId(), "' .. key .. '")', 1, true) ~= nil or src:find('arGate(pid, "' .. key .. '")', 1, true) ~= nil,
		true, key .. " is gated in " .. file)
	eq(AR.config.limits[key] ~= nil, true, key .. " has a limit")
end
-- the leech rule still holds at 3 swings per second: one heal per 900 ms
local fast = {}
for t = 0, 9999, 333 do
	fast[#fast + 1] = t
end
local healsFast = heals(fast, 900)
eq(healsFast <= 12 and healsFast >= 10, true, "3 swings per second heal about 1.1 times per second, not 3 (" .. healsFast .. ")")


-- ---------------------------------------------------------------- engine patch 0078 agrees
f = io.open("src-patches/0078-player-attack-speed-bonus.patch", "r")
local p78 = f:read("*a")
f:close()
eq(p78:find("dexterity = std::min<int32_t>(100, dexterity + attackSpeedBonus);", 1, true) ~= nil, true, "the bonus counts with dexterity")
eq(p78:find("setAttackSpeedBonus(int16_t value)", 1, true) ~= nil, true, "a setter that clamps")
eq(p78:find("std::min<int16_t>(100, std::max<int16_t>(0, value))", 1, true) ~= nil, true, "0 .. 100")
eq(p78:find("MIN_PLAYER_ATTACK_INTERVAL", 1, true) == nil, true, "the floor stays patch 0011's")

print(string.format("attack_speed_cap_test: %d checks OK", checks))

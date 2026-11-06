-- Run from the server/ folder: luajit tests/attack_speed_cap_test.lua (and lua5.3; CI runs both)
-- The attack speed cap (engine patch 0011, server/README.md "Attack speed cap"): ChaosItemMods.effectiveInterval
-- mirrors Player::getAttackSpeed of the patched engine (vocation scaling, the weapon's own interval with its attack
-- speed modifier and topaz gems, dexterity, the total bonus cap and the interval floor); the config defaults agree with
-- the patch; and a simulation of the patch's leech rule (one life leech heal per minPlayerLeechInterval).
-- O426 (owner 2026-11-06, "raise the attack limit to 3 per second. Make it reachable too, but balanced"): the floor is 333 ms
-- (engine patch 0088), only a min-maxed build reaches it (the fast classes first), a typical build lands in range, and the
-- damage per hit falls with the rate (attack_rate_core.lua) so the damage per second gain stays bounded.

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
eq(E(0, 0, 1300, 0, OFF), 1300, "Shadowfist unarmed")
eq(E(3000, 3000, 2000, 0, OFF), 3000, "two-handed, own interval")
eq(E(0, 1600, 1300, 0, OFF), 1040, "Shadowfist, weapon +20% (2000 -> 1600) x 1300/2000")
eq(E(0, 1600, 1300, 20, OFF), 832, "... and dexterity 20")
eq(E(0, 1600, 1400, 20, OFF), 896, "Ninja: same")
eq(E(3000, 2400, 2000, 20, OFF), 1920, "two-handed: -20% weapon, -20% dexterity")

-- ---------------------------------------------------------------- with the cap (defaults: floor 333 ms, bonus 76%)
local ms, capped, raw = E(0, 0, 1300, 0)
eq(ms, 1300) eq(capped, false) eq(raw, 1300)
ms, capped = E(0, 0, 1300, 20)
eq(ms, 1040, "Shadowfist unarmed + dexterity 20: -20%, under the bonus cap and the floor") eq(capped, false)
ms, capped, raw = E(0, 1600, 1300, 20)
eq(ms, 832, "Shadowfist, weapon +20% and dexterity 20: no longer at a floor") eq(capped, false) eq(raw, 832)
ms, capped = E(0, 1600, 1300, 0)
eq(ms, 1040, "Shadowfist, weapon +20%: above the floor") eq(capped, false)
ms, capped = E(0, 1600, 1400, 20)
eq(ms, 896, "Ninja: same") eq(capped, false)
ms, capped = E(0, 1600, 1600, 20)
eq(ms, 1024, "Thief: -36%") eq(capped, false)
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
for _, voc in ipairs({1300, 1400, 1500, 1600, 1700, 1800, 2000}) do
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
-- Only the fast classes reach 333 ms, only with every source at its maximum; the 2000 ms classes bottom out near 2 per second.
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
eq(ms(1300, weaponMax, dexMax, playerMax), 333, "a Shadowfist with every source at its maximum swings 3 times per second")
eq(perSecond(1400, weaponMax, dexMax, playerMax) >= 2.8, true, "a Ninja min-maxed: 2.9 per second")
eq(perSecond(1500, weaponMax, dexMax, playerMax) >= 2.6, true, "a Monk min-maxed: 2.7 per second")
eq(perSecond(2000, weaponMax, dexMax, playerMax) < 2.1, true, "a 2000 ms class min-maxed: about 2 per second, never 3")
eq(perSecond(2000, weaponMax, dexMax, playerMax) > 1.9, true)
for _, voc in ipairs({1400, 1500, 1600, 1700, 1800, 2000}) do
	eq(ms(voc, weaponMax, dexMax, playerMax) > 333, true, "only the Shadowfist reaches the floor itself: " .. voc)
end
-- one source clearly short of its maximum misses 3 per second, even for the fastest class
eq(ms(1300, weaponMax - 8, dexMax, playerMax) > 333, true, "a weapon 8 short misses it")
eq(ms(1300, weaponMax, dexMax - 6, playerMax) > 333, true, "dexterity 6 short misses it")
eq(ms(1300, weaponMax, dexMax, playerMax - 9) > 333, true, "tree and gear 9 short miss it")
eq(ms(1300, 0, dexMax, playerMax) > 333, true, "no weapon speed misses it")
eq(perSecond(1300, 0, dexMax, playerMax) < 2.6, true, "... and lands near 2.4 per second")
-- a typical build (half of every source: weapon 15, dexterity 10, tree and worn pieces 22) lands in range
local TYP = {15, 10, 22}
for _, row in ipairs({{1300, 1.2, 1.5}, {1400, 1.1, 1.4}, {1500, 1.0, 1.3}, {1600, 0.95, 1.2}, {1800, 0.9, 1.1}, {2000, 0.8, 1.0}}) do
	local r = perSecond(row[1], TYP[1], TYP[2], TYP[3])
	eq(r >= row[2] and r <= row[3], true, string.format("typical %d ms class: %.2f per second in %.2f - %.2f", row[1], r, row[2], row[3]))
end
-- the old best build (floor 1000, 40% cap, caps 15 / 20 / 12) swung once per second
local OLD = {minInterval = 1000, maxBonus = 40}
eq(E(2000, M.attackInterval(2000, 15), 1300, 20, OLD, 12), 1000, "the old Shadowfist maximum was 1 per second")

-- ---------------------------------------------------------------- the damage per hit falls with the rate (attack_rate_core.lua)
dofile("data/scripts/chaos/attack_rate_core.lua")
local AR = ChaosAttackRate
eq(AR.hitFactor(1000), 1, "one attack per second: a full hit") eq(AR.hitFactor(2000), 1, "slow swings are unchanged")
eq(AR.hitFactor(0), 1, "unknown interval") eq(AR.hitFactor(nil), 1)
local function near(a, b, tol, m)
	eq(math.abs(a - b) <= tol, true, (m or "") .. ": " .. a .. " vs " .. b)
end
near(AR.hitFactor(333), 0.50, 0.01, "a hit at the floor is half")
near(AR.dpsFactor(333), 1.50, 0.02, "3 per second: +50% damage per second over 1 per second (not +200%)")
eq(AR.dpsFactor(333) >= 1.4 and AR.dpsFactor(333) <= 1.6, true, "owner design: +40-60%")
near(AR.dpsFactor(500), 1.29, 0.02, "2 per second: about +29%")
eq(AR.dpsFactor(1000), 1)
-- monotonic: faster never loses damage per second, never gains linearly
local prev = 0
for i = 1000, 333, -1 do
	local d = AR.dpsFactor(i)
	eq(d >= prev - 1e-9, true, "damage per second grows with the rate " .. i)
	eq(d <= (1000 / i) * 0.8 or i >= 700, true, "and clearly under linear below 700 ms: " .. i)
	prev = d
end
-- the fastest build against the old maximum (1 per second, a full hit): +50% damage per second
near(AR.hitFactor(ms(1300, weaponMax, dexMax, playerMax)) * 3.003, 1.50, 0.03, "the fastest build against the old maximum")
eq(AR.hitFactor(500, {refIntervalMs = 1000, curveExponent = 1}), 0.5, "exponent 1: damage per second flat")
eq(AR.hitFactor(500, {refIntervalMs = 1000, curveExponent = 0}), 1, "exponent 0: off")

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
for _, key in ipairs({"offhand", "fistOffhand", "bloodrage", "cleavingArc", "ricochet", "radiant"}) do
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
	radiant = "templar_combat.lua", cleavingArc = "passivetree_keystones.lua", ricochet = "passivetree_keystones.lua"}
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

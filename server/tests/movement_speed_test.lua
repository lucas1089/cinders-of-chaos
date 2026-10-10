-- Run from the server/ folder: luajit tests/movement_speed_test.lua (and lua5.3; CI runs both)
-- Movement speed (engine patch 0018, client base-patch 0029, server/README.md "Movement speed"): ChaosSpeed
-- (data/lib/chaos_speed.lua) mirrors the patched engine: base speed by level, the min / max clamp of a player's walk
-- speed, the step time (10.98 formula, 10 ms rounding for players, a diagonal 7/5); its defaults and constants agree with
-- both patches; and the numbers of the README table.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end

dofile("data/lib/chaos_speed.lua")
local S = ChaosSpeed
local D = S.defaults

local function read(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local t = f:read("*a")
	f:close()
	return t
end

-- ---------------------------------------------------------------- the defaults agree with the engine patch
local patch = read("src-patches/0018-movement-speed.patch")
ok(patch, "server patch present")
for name, key in pairs({minPlayerSpeed = "minSpeed", maxPlayerSpeed = "maxSpeed", playerSpeedBonus = "bonus",
		playerSpeedPerTenLevels = "perTenLevels", playerSpeedSoftLevel = "softLevel",
		playerSpeedPerTenLevelsAbove = "perTenLevelsAbove"}) do
	ok(patch:find('"' .. name .. '", ' .. D[key] .. ')', 1, true), "engine default " .. name)
end
ok(patch:find("PLAYER_STEP_ROUNDING = " .. S.playerStepRounding .. ";", 1, true), "engine rounding")
ok(patch:find("PLAYER_DIAGONAL_STEP_NUM = " .. S.diagonalNum .. ";", 1, true), "engine diagonal num")
ok(patch:find("PLAYER_DIAGONAL_STEP_DEN = " .. S.diagonalDen .. ";", 1, true), "engine diagonal den")
-- the client predicts the same (a mismatch makes the walk stutter)
local cpatch = read("../client/base-patches/0029-movement-speed.patch")
ok(cpatch, "client patch present")
ok(cpatch:find("ChaosPlayerStepRounding = " .. S.playerStepRounding .. ";", 1, true), "client rounding")
ok(cpatch:find("ChaosPlayerDiagonalNum = " .. S.diagonalNum .. ";", 1, true), "client diagonal num")
ok(cpatch:find("ChaosPlayerDiagonalDen = " .. S.diagonalDen .. ";", 1, true), "client diagonal den")

-- configManager (when the engine has the keys) wins over the defaults
configKeys = {MIN_PLAYER_SPEED = 201, MAX_PLAYER_SPEED = 202}
configManager = {getNumber = function(k) return k == 201 and 150 or 3000 end}
local cfg = S.config()
eq(cfg.minSpeed, 150) eq(cfg.maxSpeed, 3000) eq(cfg.bonus, D.bonus, "a key the engine lacks keeps its default")
configKeys, configManager = nil, nil
cfg = S.config()
eq(cfg.minSpeed, 120) eq(cfg.maxSpeed, 2600)

-- ---------------------------------------------------------------- base speed (Player::updateBaseSpeed)
eq(S.baseSpeed(220, 1), 270, "level 1")
eq(S.baseSpeed(220, 100), 220 + 50 + 247, "level 100: 2.5 per level, rounded down")
eq(S.baseSpeed(220, 300), 1017, "level 300")
eq(S.baseSpeed(220, 301), 1018, "1 per level above 300")
eq(S.baseSpeed(220, 1000), 1717, "level 1000")
eq(S.baseSpeed(232, 1), 282, "the vocation's own base stays (Ninja)")
eq(S.baseSpeed(220, 0), 270, "level 0 counts as 1")
local stock = {bonus = 0, perTenLevels = 20, softLevel = 1, perTenLevelsAbove = 20}
eq(S.baseSpeed(220, 1000, stock), 220 + 2 * 999, "the stock formula is a config away")
for L = 2, 2000 do
	ok(S.baseSpeed(220, L) > S.baseSpeed(220, L - 1) or L % 2 == 0, "grows every level or two")
end

-- ---------------------------------------------------------------- the clamp (Player::getStepSpeed)
eq(S.clamp(27), 120, "a 90% slow at level 1 stops at the floor")
eq(S.clamp(-500), 120, "even a negative speed")
eq(S.clamp(5000), 2600, "haste stacking stops at the ceiling")
eq(S.clamp(1717), 1717, "inside: unchanged")
local lo, hi = S.limits({minSpeed = 0, maxSpeed = 0})
eq(lo, 10) eq(hi, 12000, "0 = the engine's own limits")
lo, hi = S.limits({minSpeed = 500, maxSpeed = 300})
eq(lo, 500) eq(hi, 500, "a max under the min becomes the min")

-- ---------------------------------------------------------------- creature speed
local function creature(speed, player, step)
	return {getSpeed = function() return speed end, isPlayer = function() return player end, getStepSpeed = step}
end
eq(S.effective(creature(4000, true)), 2600, "player without the engine method: clamped here")
eq(S.effective(creature(4000, false)), 4000, "monsters are not clamped")
eq(S.effective(creature(4000, true, function() return 2222 end)), 2222, "the engine's answer wins")
eq(S.effective(nil), 0)

-- ---------------------------------------------------------------- step time (Creature::getStepDuration)
eq(S.stepSpeed(220), 278) eq(S.stepSpeed(2218), 1398)
eq(S.stepSpeed(10), 1, "below 16 the formula is negative: 1 (the engine used to wrap to a 0 ms step)")
eq(S.stepDuration(220, nil, {monster = true}), 550, "stock level 1: 550 ms")
eq(S.stepDuration(2218, nil, {monster = true}), 150, "stock level 1000: 107 ms rounded to 150")
local T = {[1] = {270, 450}, [100] = {517, 270}, [300] = {1017, 170}, [1000] = {1717, 130}}
for L, row in pairs(T) do
	local speed = S.baseSpeed(220, L)
	eq(speed, row[1], "speed at level " .. L)
	eq(S.stepDuration(speed), row[2], "straight step at level " .. L)
	eq(S.stepDuration(speed, nil, {diagonal = true}), math.floor(row[2] * 7 / 5), "diagonal at level " .. L)
end
eq(S.stepDuration(S.clamp(1), nil), 980, "the floor: about 1 tile per second")
eq(S.stepDuration(S.clamp(1e6), nil), 100, "the ceiling: 10 tiles per second")
eq(S.stepDuration(1017, 100), 110, "faster ground")
eq(S.stepDuration(1017, 200), 230, "slower ground")
-- slower speed never steps faster; the player rounding never makes a step longer than the stock 50 ms one
local prev = math.huge
for speed = 16, 12000, 7 do
	local d = S.stepDuration(speed)
	ok(d <= prev, "monotonic at " .. speed)
	ok(d <= S.stepDuration(speed, nil, {monster = true}), "10 ms rounding never slower at " .. speed)
	prev = d
end
-- a diagonal step costs more than a straight one and less than two (stock 3x on the client)
for _, speed in ipairs({120, 270, 1017, 2600}) do
	local s, d = S.stepDuration(speed), S.stepDuration(speed, nil, {diagonal = true})
	ok(d > s and d < 2 * s, "diagonal between 1x and 2x at " .. speed)
end
-- every base speed of the table walks at least 15% faster than before (stock formula, stock rounding)
for _, L in ipairs({1, 100, 300, 1000}) do
	local old = S.stepDuration(220 + 2 * (L - 1), nil, {monster = true})
	local new = S.stepDuration(S.baseSpeed(220, L))
	ok(old / new >= 1.15 and old / new <= 1.35, ("level %d: %d -> %d ms"):format(L, old, new))
end
eq(string.format("%.2f", S.tilesPerSecond(1717)), "7.69")

print(("movement_speed_test: %d checks OK"):format(checks))

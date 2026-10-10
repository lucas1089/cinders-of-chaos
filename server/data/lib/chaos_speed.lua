-- Movement speed (engine patch src-patches/0018-movement-speed.patch, client base-patch 0029; server/README.md
-- "Movement speed"): the Lua mirror of the engine's rules, for scripts that reason about how fast a player really walks
-- and for tests (tests/movement_speed_test.lua).
--
--   base speed   vocation base + playerSpeedBonus + playerSpeedPerTenLevels / 10 per level up to playerSpeedSoftLevel,
--                playerSpeedPerTenLevelsAbove / 10 per level after it (Player::updateBaseSpeed)
--   walk speed   base + every change (haste, slows, items, mounts, passive tree, Paragon, Lua changeSpeed), held between
--                minPlayerSpeed and maxPlayerSpeed (Player::getStepSpeed; creature:getStepSpeed() in Lua). Monsters and
--                NPCs are not clamped.
--   step time    the 10.98 formula: step speed = floor(A * ln(speed / 2 + B) + C + 0.5), at least 1;
--                ms = floor(1000 * ground speed / step speed), rounded up to 10 ms for players (50 ms for monsters / NPCs);
--                a player's diagonal step takes 7/5 of a straight one (monsters / NPCs: the straight one)
--
-- The config keys are read through configManager when the engine has them (patch 0018); the defaults below are the
-- patch's own defaults and apply otherwise.

ChaosSpeed = ChaosSpeed or {}
local M = ChaosSpeed
local floor, ceil, log = math.floor, math.ceil, math.log

M.defaults = {
	minSpeed = 120,           -- minPlayerSpeed: about 1 tile/s on normal ground; a slow never freezes a player
	maxSpeed = 2600,          -- maxPlayerSpeed: 100 ms per step (10 tiles/s) on normal ground
	bonus = 50,               -- playerSpeedBonus: added to every vocation's base speed
	perTenLevels = 25,        -- playerSpeedPerTenLevels: 2.5 speed per level ...
	softLevel = 300,          -- playerSpeedSoftLevel: ... up to level 300 ...
	perTenLevelsAbove = 10,   -- playerSpeedPerTenLevelsAbove: ... then 1 per level
}
M.engineMin, M.engineMax = 10, 12000          -- PLAYER_MIN_SPEED / PLAYER_MAX_SPEED of the engine (staff keep these)
M.formula = {a = 857.36, b = 261.29, c = -4795.01}
M.playerStepRounding, M.otherStepRounding = 10, 50
M.diagonalNum, M.diagonalDen = 7, 5
M.normalGround = 150                         -- the engine's ground speed when a ground has none

local KEYS = {
	minSpeed = "MIN_PLAYER_SPEED", maxSpeed = "MAX_PLAYER_SPEED", bonus = "PLAYER_SPEED_BONUS",
	perTenLevels = "PLAYER_SPEED_PER_TEN_LEVELS", softLevel = "PLAYER_SPEED_SOFT_LEVEL",
	perTenLevelsAbove = "PLAYER_SPEED_PER_TEN_LEVELS_ABOVE",
}

-- the engine's settings (configManager) or the defaults
function M.config()
	local c = {}
	for k, v in pairs(M.defaults) do
		c[k] = v
		local key = configKeys and configKeys[KEYS[k]]
		if key and configManager and configManager.getNumber then
			local ok, n = pcall(configManager.getNumber, key)
			if ok and type(n) == "number" then
				c[k] = n
			end
		end
	end
	return c
end

-- the limits a player's speed is held between (0 in the config = the engine's own limit), as Player::getStepSpeed
function M.limits(cfg)
	cfg = cfg or M.config()
	local lo, hi = M.engineMin, M.engineMax
	if (cfg.minSpeed or 0) > 0 then
		lo = math.min(cfg.minSpeed, M.engineMax)
	end
	if (cfg.maxSpeed or 0) > 0 then
		hi = math.max(lo, math.min(cfg.maxSpeed, M.engineMax))
	end
	return lo, hi
end

function M.clamp(speed, cfg)
	local lo, hi = M.limits(cfg)
	speed = tonumber(speed) or 0
	if speed < lo then
		return lo
	elseif speed > hi then
		return hi
	end
	return speed
end

-- a player's base speed (Player::updateBaseSpeed)
function M.baseSpeed(vocationBase, level, cfg)
	cfg = cfg or M.config()
	local levels = math.max(0, (tonumber(level) or 1) - 1)
	local soft = math.max(1, cfg.softLevel or 1)
	local below = math.min(levels, soft - 1)
	local above = levels - below
	local per, perAbove = math.max(0, cfg.perTenLevels or 0), math.max(0, cfg.perTenLevelsAbove or 0)
	local speed = (tonumber(vocationBase) or 0) + (cfg.bonus or 0) + floor((below * per + above * perAbove) / 10)
	return math.max(1, math.min(speed, M.engineMax))
end

-- the speed a creature walks at: the engine's own answer when it has patch 0018, else the clamp for players
function M.effective(creature)
	if not creature then
		return 0
	end
	if creature.getStepSpeed then
		local ok, s = pcall(creature.getStepSpeed, creature)
		if ok and type(s) == "number" then
			return s
		end
	end
	local speed = creature:getSpeed()
	local isPlayer = creature.isPlayer and creature:isPlayer()
	return isPlayer and M.clamp(speed) or speed
end

-- C++ integer division of an int by 2 (towards zero)
local function half(n)
	return n >= 0 and floor(n / 2) or -floor(-n / 2)
end

-- the formula's step speed (Creature::getStepDuration), at least 1
function M.stepSpeed(speed)
	local f = M.formula
	if speed <= -f.b then
		return 1
	end
	local v = floor(f.a * log(half(speed) + f.b) + f.c + 0.5)
	return v < 1 and 1 or v
end

-- ms of one step: speed = the walk speed (already clamped), ground = the ground's speed (nil: 150), opts.diagonal,
-- opts.monster (the stock rules: 50 ms rounding, diagonal as straight; a monster's x2 near its target is not included)
function M.stepDuration(speed, ground, opts)
	opts = opts or {}
	ground = (ground and ground > 0) and ground or M.normalGround
	local duration = floor(1000 * ground / M.stepSpeed(speed))
	local rounding = opts.monster and M.otherStepRounding or M.playerStepRounding
	local ms = ceil(duration / rounding) * rounding
	if opts.diagonal and not opts.monster then
		ms = floor(ms * M.diagonalNum / M.diagonalDen)
	end
	return ms
end

function M.tilesPerSecond(speed, ground, opts)
	return 1000 / M.stepDuration(speed, ground, opts)
end

return M

-- Global experience cap: pure logic (no engine calls), shared by xpcap.lua and server/tests/xpcap_test.lua.
--   ChaosXpCap.levelFactor(monsterLevel)               the engine's monster level bonus (x0.03 per level, at least 1)
--   ChaosXpCap.base(rawExp, monsterLevel, stage, tierXp)  the kill's experience without any bonus
--   ChaosXpCap.clamp(exp, base, cap)                    exp, at most floor(base x cap)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosXpCap = ChaosXpCap or {}
local X = ChaosXpCap

local floor = math.floor

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return v
end

-- base player.lua scales a monster of level L by 0.03 L (only upwards; rift.lua's cap reads it the same way)
function X.levelFactor(monsterLevel)
	local f = num(monsterLevel, 0) * 0.03
	if f > 1 then
		return f
	end
	return 1
end

-- what the kill gives with no bonus at all: the monster's experience x its level factor x the experience stage of the
-- player's level x the monster tier (magic 2, rare 4, legendary 10: the tier is the monster, not a bonus)
function X.base(rawExp, monsterLevel, stage, tierXp)
	local b = num(rawExp, 0) * X.levelFactor(monsterLevel) * num(stage, 1) * num(tierXp, 1)
	if b < 0 then
		return 0
	end
	return b
end

-- exp after every bonus, at most cap x base. A missing base or cap leaves exp alone; nothing is ever raised.
function X.clamp(exp, base, cap)
	exp = num(exp, 0)
	base, cap = num(base, 0), num(cap, 0)
	if exp <= 0 or base <= 0 or cap <= 0 then
		return exp
	end
	local most = floor(base * cap)
	if most < 1 then
		most = 1
	end
	if exp > most then
		return most
	end
	return exp
end

return X

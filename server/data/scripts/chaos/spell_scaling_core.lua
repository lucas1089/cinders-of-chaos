-- spell_scaling_core.lua: the magic level share of weapon spells (O468; numbers: spell_scaling_config.lua). Pure: no
-- engine call besides the player getters it is handed. Tests: server/tests/spell_scaling_test.lua. Lua 5.1 / LuaJIT and
-- Lua 5.3 compatible.
--
-- A weapon spell's base damage (the formula of its script: level, weapon skill x attack, flat terms) is multiplied by
-- S.factor(level, magicLevel) = (1 + ML / per) / (1 + refML(level) / per). Applied in the helpers, once per hit:
--   * AttackKit.cast for the melee, distance and monk schools (the blade and shuriken schools through ChaosSpell.weaponStrike),
--   * the SKILLVALUE callback spells (ChaosSpell.weaponFormula), ChaosSpell.weaponStrike, MonkSpell.strike / values,
--   * the wolves' mauls and the companion bite (ChaosClasses.biteValuesFor, autoBiteValuesFor), snares and mines (at placement).
-- Not applied to auto attacks, to caster spells, to the spells that already read the magic level (the Templar line, the
-- Ranger holy spells) nor twice to one hit.

ChaosSpellScaling = ChaosSpellScaling or {}
local S = ChaosSpellScaling

local function cfg(c)
	c = c or ChaosSpellScalingConfig
	return c and c.mlShare
end

-- the typical magic level of a weapon class at `level`: linear between the anchors, flat above the last one
function S.refML(level, c)
	local m = cfg(c)
	local pts = m and m.ref
	if not pts or #pts == 0 then
		return 0
	end
	level = tonumber(level) or 0
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- the factor on a weapon spell's base damage for a character of `level` and `magicLevel` (1 without a config)
function S.factor(level, magicLevel, c)
	local m = cfg(c)
	if not m or not m.per or m.per <= 0 then
		return 1
	end
	local f = 1 + math.max(0, tonumber(magicLevel) or 0) / m.per
	if m.normalise then
		f = f / (1 + S.refML(level, c) / m.per)
	end
	return f
end

-- the same for a player object
function S.forPlayer(player, c)
	if not player or not player.getLevel or not player.getMagicLevel then
		return 1
	end
	return S.factor(player:getLevel(), player:getMagicLevel(), c)
end

return S

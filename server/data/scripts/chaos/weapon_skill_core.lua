-- weapon_skill_core.lua: the auto attack of every weapon type scales with the character's skill (owner 2026-10-20:
-- "faça o dano das armas/auto attack escalar com as skills dos players"; server/README.md "Weapon damage scales with
-- skills"). Pure Lua, no engine calls; tests/weapon_skill_test.lua. The glue is weapon_styles.lua (the one
-- onHealthChange of weapon hits); the numbers are weapon_skill_config.lua.
--
-- What the engine already does (TFS 1.4.2, Weapons::getMaxWeaponDamage, unchanged by any src-patch):
--   max hit = level / 5 (integer) + ((skill / 4 + 1) x (attack / 3) x 1.03) / stance factor
-- for swords, axes and clubs (the best melee skill: melee_skill_core.lua), distance weapons (distance skill) and the
-- fist (fist skill; the Monk's fist attack: monk_chi_core.lua). The skill term is 79-94% of the hit at the typical
-- skills of levels 50 .. 1000, so those weapons scale with the skill already; this module keeps them as they are.
-- What it adds: wands and rods. The engine hits with a flat min .. max of weapons.xml (WeaponWand::getWeaponDamage),
-- whatever the magic level; M.wandFactor scales the hit by the magic level against the typical one of the level.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosWeaponSkill = ChaosWeaponSkill or {}
local M = ChaosWeaponSkill

if not M.config then
	M.config = dofile("data/scripts/chaos/weapon_skill_config.lua")
end

local function num(v)
	return tonumber(v) or 0
end

-- linear over {level, value} anchors, flat outside
function M.interp(points, level)
	level = num(level)
	if level <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local x1, y1 = points[i][1], points[i][2]
		if level <= x1 then
			local x0, y0 = points[i - 1][1], points[i - 1][2]
			return y0 + (y1 - y0) * (level - x0) / (x1 - x0)
		end
	end
	return points[#points][2]
end

-- kind "skill" (melee, distance, fist) or "magic": what a character usually has at `level`
function M.typical(kind, level)
	local points = M.config.typical[kind]
	if not points then
		return 0
	end
	return M.interp(points, level)
end

-- the engine's maximum weapon damage (Weapons::getMaxWeaponDamage, rounded as the engine rounds it)
function M.maxHit(level, skill, attack, factor)
	local f = num(factor)
	if f <= 0 then
		f = 1
	end
	return math.floor(math.floor(num(level) / 5) + ((num(skill) / 4 + 1) * (num(attack) / 3) * 1.03) / f + 0.5)
end

-- the share of the maximum hit that comes from the skill (the rest is level / 5): how much the skill drives the hit
function M.skillShare(level, skill, attack)
	local top = math.floor(num(level) / 5) + (num(skill) / 4 + 1) * (num(attack) / 3) * 1.03
	if top <= 0 then
		return 0
	end
	return 1 - math.floor(num(level) / 5) / top
end

-- the factor a wand or rod hit is multiplied by: the magic level against the typical magic level of the level
function M.wandFactor(level, magicLevel)
	local w = M.config.wand
	local want = math.max(0, num(magicLevel)) + w.offset
	local usual = math.max(0, M.typical("magic", level)) + w.offset
	local f = want / usual
	if f < w.minFactor then
		f = w.minFactor
	elseif f > w.maxFactor then
		f = w.maxFactor
	end
	return f
end

return M

-- weapon_power_core.lua: the auto attack keeps up with the skill and the level (owner 2026-10-23: "auto attack nao esta
-- escalando com a skill e lvl, esta muito fraco"; server/README.md "Auto attack power"). Pure Lua, no engine calls;
-- tests/weapon_power_test.lua. The glue is weapon_styles.lua (the one onHealthChange of weapon hits); the numbers are
-- weapon_power_config.lua, written by server/tools/weapon_sim.py --power --write.
--
-- The engine's hit (TFS 1.4.2, Weapons::getMaxWeaponDamage, unchanged) is level / 5 + (skill / 4 + 1) x attack / 3 x 1.03.
-- Gear attack and the typical skill flatten out above level ~600 while a class's spells keep growing with the level, so a
-- launcher fell to 15-24% of a Ranger's spell damage per second at levels 1000-2000 and a wand to 9% of a Mystic's. Two
-- multipliers on top of the engine hit:
--   levelFactor(kind, level): lifts a kind (melee, distance, wand) to its share of the single-target spell rotation of its
--     reference class (weapon_sim.py POWER_KINDS); never below 1, so a kind that is above the share is left as it is.
--   skillFactor(level, skill): (skill / typical skill of the level) ^ exponent, clamped. The engine's term is linear in the
--     skill, which is +5% for +10 skill at skill 140; the exponent makes a trained character hit visibly harder and a
--     neglected one softer, 1 at the typical skill (weapon_skill_config.lua) so the balance numbers hold.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosWeaponPower = ChaosWeaponPower or {}
local P = ChaosWeaponPower

if not P.config then
	P.config = dofile("data/scripts/chaos/weapon_power_config.lua")
end
if not ChaosWeaponSkill then
	dofile("data/scripts/chaos/weapon_skill_core.lua")
end
local WS = ChaosWeaponSkill

-- linear interpolation over levels / values, flat outside
function P.interp(levels, values, level)
	level = tonumber(level) or 0
	if level <= levels[1] then
		return values[1]
	end
	for i = 2, #levels do
		if level <= levels[i] then
			local x0, x1 = levels[i - 1], levels[i]
			return values[i - 1] + (values[i] - values[i - 1]) * (level - x0) / (x1 - x0)
		end
	end
	return values[#values]
end

-- kind: "melee" (a sword, axe or club), "distance" (a bow or crossbow), "wand" (a wand or rod) or "fist" (the Monk line's
-- fists and fist weapons, monk_combat.lua); anything else is 1
function P.levelFactor(kind, level)
	local values = P.config[kind]
	if not values or kind == "levels" or kind == "skill" then
		return 1
	end
	return P.interp(P.config.levels, values, level)
end

-- the skill against the typical skill of the level; 1 when either is missing
function P.skillFactor(level, skill)
	local c = P.config.skill
	skill = tonumber(skill)
	local typical = WS.typical("skill", level)
	if not skill or skill <= 0 or typical <= 0 then
		return 1
	end
	local f = (skill / typical) ^ c.exponent
	if f < c.min then
		f = c.min
	elseif f > c.max then
		f = c.max
	end
	return f
end

-- the multiplier of one weapon hit (kinds: melee, distance, wand, fist). A wand scales with the magic level through ChaosWeaponSkill.wandFactor already,
-- so it gets the level factor only
function P.hitFactor(kind, level, skill)
	local f = P.levelFactor(kind, level)
	if skill ~= nil and kind ~= "wand" then
		f = f * P.skillFactor(level, skill)
	end
	return f
end

return P

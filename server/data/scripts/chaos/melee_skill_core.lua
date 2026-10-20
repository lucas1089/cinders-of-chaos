-- melee_skill_core.lua: ONE melee skill (owner debug item 46: "Simplificar skills: melee, ranged, magic, wand e shielding.
-- Itens de melee servem a todas as classes de melee"; server/README.md "One melee skill"). Pure Lua, no engine calls;
-- tests/melee_skill_test.lua. The glue is melee_skill.lua (training) and weapon_styles.lua (the hit); the spells read
-- ChaosSpell.meleeSkillLevel (data/spells/chaos/_common.lua), which is the same rule.
--
-- The engine keeps three weapon skills (sword, club, axe: a weapon hits with the skill of its own type). Merging them
-- into one stored skill needs an engine patch (README, "Engine patch 0048 proposal"), and would touch every saved
-- character; this module gets the same play without one:
--   * a weapon hit, a melee spell and the training use the BEST of the three skills: a Warrior who trained the sword
--     and picks up an axe hits with the sword skill, nothing starts over (hitMultiplier below)
--   * the experience of any melee skill goes to the best one (routeTries), so a character has one melee skill that
--     grows whatever it swings, and the vocations' three multipliers are the same (chaos_vocations*.xml)
--   * the client shows one "Melee" row (game_simpleskills)
-- The fist (Monk, bare hands), the distance skill (the "ranged" skill), shielding and the magic level (which the wands and
-- rods use: a wand is damage by magic level) stay what they are.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosMeleeSkill = ChaosMeleeSkill or {}
local M = ChaosMeleeSkill

-- the skills that are one: names in the order the ties are broken (sword first)
M.names = {"sword", "club", "axe"}

local function num(v)
	return tonumber(v) or 0
end

-- levels = {sword = n, club = n, axe = n} (and optional percents = {sword = p, ...} as the tie-break) ->
-- name, value of the best melee skill (the first of the names on a tie)
function M.best(levels, percents)
	local bestName, bestValue, bestPercent
	for _, name in ipairs(M.names) do
		local v = num(levels and levels[name])
		local p = num(percents and percents[name])
		if bestName == nil or v > bestValue or (v == bestValue and p > bestPercent) then
			bestName, bestValue, bestPercent = name, v, p
		end
	end
	return bestName, bestValue
end

-- the engine's maximum weapon damage (Weapons::getMaxWeaponDamage); `factor` is the fight mode's attack factor
function M.maxHit(level, skill, attack, factor)
	local f = num(factor)
	if f <= 0 then
		f = 1
	end
	return math.floor(num(level) / 5) + ((num(skill) / 4 + 1) * (num(attack) / 3) * 1.03) / f
end

-- the factor a hit dealt with the weapon's own skill is multiplied by, so it is the hit of the best melee skill: the
-- ratio of the two maximum hits (1 when the weapon's skill is the best, or the weapon has no attack)
function M.hitMultiplier(level, weaponSkill, bestSkill, attack, factor)
	weaponSkill, bestSkill = num(weaponSkill), num(bestSkill)
	if bestSkill <= weaponSkill or num(attack) <= 0 then
		return 1
	end
	local own = M.maxHit(level, weaponSkill, attack, factor)
	if own <= 0 then
		return 1
	end
	return M.maxHit(level, bestSkill, attack, factor) / own
end

-- the training: `skill` gained tries; `levels` / `percents` as in best. Returns the name the tries go to (the best
-- melee skill) when that is not `skill` itself, else nil (the tries stay: not a melee skill, or already the best)
function M.routeTarget(skill, levels, percents)
	local isMelee = false
	for _, name in ipairs(M.names) do
		if name == skill then
			isMelee = true
		end
	end
	if not isMelee then
		return nil
	end
	local top = M.best(levels, percents)
	-- a tie with the skill itself keeps the tries where they are (no ping-pong between equal skills)
	if top == skill or (num(levels[skill]) == num(levels[top]) and num(percents and percents[skill]) == num(percents and percents[top])) then
		return nil
	end
	return top
end

-- the weapon types (items.xml weaponType) that hit with the melee skill
M.weaponTypes = {sword = "sword", club = "club", axe = "axe"}

return M

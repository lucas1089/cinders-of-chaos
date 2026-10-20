-- weapon_dps_core.lua: the "Estimated DPS" line of a weapon's tooltip (owner debug item 79: "Faça um medidor de DPS pra
-- cada arma. Pode ser estimado."). Pure Lua, no engine calls except the optional ItemType reads in D.forItem
-- (tests/weapon_dps_test.lua). It is an ESTIMATE of the damage of the auto attack of one weapon on a monster that does
-- not defend, the same model tools/weapon_sim.py checks the weapon styles with:
--   max hit  = round(level / 5 (integer) + ((skill / 4 + 1) * (attack / 3) * 1.03) / attack factor)     engine, Weapons::getMaxWeaponDamage
--   mean hit = (min + max) / 2, min 0 for melee and a fifth of the level (rounded up) for a launcher    the hit is a bell curve
--   hit      = mean hit x the style factor of weapon_styles.lua (two-handed melee, bow, crossbow: weapon_balance_core.lua)
--   DPS      = hit x hit chance (launchers) / interval in seconds
-- The attack is the item's own (a rarity roll writes it as an attribute), the skill is the character's best melee skill
-- (one melee skill) or distance skill, the interval is "Your Attack Interval" of the tooltip. Left out: critical hits, the
-- modifiers of the item and the passive tree, monster resistances, spells, wands and rods (their damage is the magic
-- level's, not the attack's) and the fist. Lua 5.1 / LuaJIT and 5.3.
ChaosWeaponDps = ChaosWeaponDps or {}
local D = ChaosWeaponDps

local floor = math.floor

local function num(v)
	return tonumber(v) or 0
end

-- Weapons::getMaxWeaponDamage (fight mode factor 1: the offensive stance)
function D.maxHit(level, skill, attack, factor)
	local f = num(factor)
	if f <= 0 then
		f = 1
	end
	return floor(floor(num(level) / 5) + ((num(skill) / 4 + 1) * (num(attack) / 3) * 1.03) / f + 0.5)
end

-- p = {level, skill, attack, interval (ms), launcher = "bow" | "crossbow" | nil, twoHanded = bool, weaponType = "sword" |
-- "club" | "axe" | nil, hitChance = percent (launchers), factor = attack factor (default 1), styleFactor = override}
-- Returns the estimate (damage per second, a number) or nil when it cannot be worked out.
function D.estimate(p)
	if type(p) ~= "table" then
		return nil
	end
	local attack, interval, level = num(p.attack), num(p.interval), num(p.level)
	if attack <= 0 or interval <= 0 or level < 1 then
		return nil
	end
	local top = D.maxHit(level, p.skill, attack, p.factor)
	local low = 0
	local chance = 1
	if p.launcher then
		low = math.min(top, -floor(-level / 5)) -- ceil(level / 5)
		local hc = num(p.hitChance)
		chance = hc > 0 and math.min(100, hc) / 100 or 1
	end
	local style = p.styleFactor
	if style == nil then
		local WB = ChaosWeaponBalance
		style = WB and WB.hitFactor and WB.hitFactor(level, p.twoHanded, p.launcher, p.weaponType) or 1
	end
	return (low + top) / 2 * style * chance / (interval / 1000)
end

-- the number the tooltip shows: a whole number, nil when there is nothing to show
function D.round(dps)
	dps = tonumber(dps)
	if not dps or dps <= 0 then
		return nil
	end
	return floor(dps + 0.5)
end

-- the weapon types an estimate is made for (items.xml weaponType names)
D.MELEE = {sword = true, club = true, axe = true}

return D

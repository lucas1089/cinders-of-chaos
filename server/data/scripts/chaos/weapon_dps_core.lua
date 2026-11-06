-- weapon_dps_core.lua: the "Estimated DPS" line of a weapon's tooltip (owner debug item 79: "Faça um medidor de DPS pra
-- cada arma. Pode ser estimado."). Pure Lua, no engine calls except the optional ItemType reads in D.forItem
-- (tests/weapon_dps_test.lua). It is an ESTIMATE of the damage of the auto attack of one weapon on a monster that does
-- not defend, the same model tools/weapon_sim.py checks the weapon styles with:
--   max hit  = round(level / 5 (integer) + ((skill / 4 + 1) * (attack / 3) * 1.03) / attack factor)     engine, Weapons::getMaxWeaponDamage
--   mean hit = (min + max) / 2, min 0 for melee and a fifth of the level (rounded up) for a launcher    the hit is a bell curve
--   hit      = mean hit x the style factor of weapon_styles.lua (two-handed melee, bow, crossbow: weapon_balance_core.lua)
--              x the auto attack power (level and skill: weapon_power_core.lua) when that script is loaded
--   DPS      = hit x hit chance (launchers) / interval in seconds
-- The attack is the item's own (a rarity roll writes it as an attribute), the skill is the character's best melee skill
-- (one melee skill) or distance skill, the interval is "Your Attack Interval" of the tooltip. Left out: critical hits, the
-- modifiers of the item and the passive tree, monster resistances, spells and the fist. Lua 5.1 / LuaJIT and 5.3.
-- Wands and rods (O353, owner 2026-10-31 "mostre o ataque dos rods tambem, juntamente com o dps deles"): their hit is
-- the flat min..max of weapons.xml x a factor (weapon_styles.lua: the magic level against the typical one of the level,
-- weapon_skill_core.lua wandFactor, x the auto attack power, weapon_power_core.lua levelFactor "wand"); D.wandHit and
-- D.wandEstimate take that factor. The engine does not give weapons.xml numbers to Lua, so D.collectWands reads them
-- from the generated item tables of data/lib (chaos_base_wands.lua for the stock ones).
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
	-- the auto attack power of weapon_power_core.lua (level and skill), when the script is loaded; an explicit styleFactor
	-- (a test, a caller that works the style out itself) stands for the whole multiplier
	local power = 1
	local WP = ChaosWeaponPower
	if WP and WP.hitFactor and p.styleFactor == nil then
		local kind = p.launcher and "distance" or (p.weaponType and "melee") or nil
		if kind then
			power = WP.hitFactor(kind, level, p.skill)
		end
	end
	return (low + top) / 2 * style * power * chance / (interval / 1000)
end

-- the number the tooltip shows: a whole number, nil when there is nothing to show
function D.round(dps)
	dps = tonumber(dps)
	if not dps or dps <= 0 then
		return nil
	end
	return floor(dps + 0.5)
end

-- a wand or rod hit: lo, hi (whole numbers) of the flat min..max x factor; nil when there is nothing to show
function D.wandHit(min, max, factor)
	min, max, factor = num(min), num(max), num(factor)
	if max <= 0 or factor <= 0 then
		return nil
	end
	if min > max then
		min, max = max, min
	end
	return floor(min * factor + 0.5), floor(max * factor + 0.5)
end

-- p = {min, max, factor, interval (ms)}: damage per second of a wand or rod (every shot hits)
function D.wandEstimate(p)
	if type(p) ~= "table" or num(p.interval) <= 0 then
		return nil
	end
	local lo, hi = D.wandHit(p.min, p.max, p.factor)
	if not lo then
		return nil
	end
	return (num(p.min) + num(p.max)) / 2 * num(p.factor) / (num(p.interval) / 1000)
end

-- the wand and rod table {[server id] = {min, max}} from item tables: each a list or a map of entries
-- {id?, stats = {wandMin, wandMax}} (the map key is the id when the entry has none): data/lib/chaos_base_wands.lua (the
-- stock ones, tools/gen_base_wands.py from data/items/base_weapons.csv) and the generated tables of our items
function D.collectWands(tables)
	local out = {}
	local function walk(t, key, depth)
		if type(t) ~= "table" or depth > 4 then
			return
		end
		local st = t.stats
		if type(st) == "table" and tonumber(st.wandMax) and tonumber(st.wandMax) > 0 then
			local id = tonumber(t.id) or tonumber(key)
			if id then
				out[id] = {min = tonumber(st.wandMin) or 0, max = tonumber(st.wandMax)}
			end
			return
		end
		for k, v in pairs(t) do
			if type(v) == "table" and k ~= "stats" then
				walk(v, k, depth + 1)
			end
		end
	end
	for _, t in ipairs(tables or {}) do
		walk(t, nil, 0)
	end
	return out
end

-- the weapon types an estimate is made for (items.xml weaponType names)
D.MELEE = {sword = true, club = true, axe = true}

return D

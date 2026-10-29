-- combat_stats_core.lua: the numbers of the combat stat rows below the skill bars of the client's Skills window
-- (Damage/Healing, Attack Value, Defence Value, Armor Value, Mitigation). Pure Lua, no engine calls; the engine file is
-- combat_stats.lua, the numbers are combat_stats_config.lua, tests are tests/combat_stats_test.lua.
--
-- The base client has these rows and fills them from a newer protocol's packet that a 10.98 server never sends, so they
-- stayed 0. Here the server works them out from what the game itself uses:
--   Attack Value    the equipped weapon's attack, the number of its tooltip (type attack or the rarity / unique roll)
--   Damage/Healing  the average auto attack hit with that weapon: the engine's max hit (weapon_dps_core.lua), the weapon
--                   style and power factors, the passive tree's damage percent / strength / Paragon / class factor of
--                   passivetree_effects.lua, times the display scale of the level. Nothing for a wand, a rod or a fist:
--                   those hit by magic level, spells or the Monk's chi, not by an attack.
--   Defence Value   the engine's Player::getDefense: (skill / 4 + 2.23) x defence x 0.15, defence of the shield (or the
--                   weapon), skill = shielding (or the weapon's skill, fist with no weapon)
--   Armor Value     the sum of the armour of the worn pieces (Player::getArmor)
--   Mitigation      the share of a physical monster hit that never lands: armour / (armour + K) (engine patch 0016),
--                   the passive tree's physical resist, and the "Damage Taken from Monsters" gear modifier, one after
--                   the other (each takes its share of what is left)
-- Mantra is a newer protocol's elemental protection; this game has per-element resists (their own rows), so the client
-- hides that row and the server sends nothing for it.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosCombatStats = ChaosCombatStats or {}
local C = ChaosCombatStats

local floor = math.floor

local function num(v)
	return tonumber(v) or 0
end

-- engine: Player::getArmor, the sum over the worn pieces' armour (a list of numbers, negative and missing count 0)
function C.armour(list)
	local total = 0
	for _, v in ipairs(list or {}) do
		total = total + math.max(0, floor(num(v)))
	end
	return total
end

-- engine patch 0016, Creature::armorPercentReduction: armour / (armour + K), at most cap percent. 0 with no armour.
function C.armourShare(armour, k, capPercent)
	armour = num(armour)
	if armour <= 0 then
		return 0
	end
	k = math.max(1, num(k))
	local cap = math.max(0, math.min(100, num(capPercent))) / 100
	return math.min(cap, armour / (armour + k))
end

-- engine: Player::getDefense. s = {weapon = {defense, extra, skill} | nil, shield = {defense} | nil, shielding, fist,
-- bare, factor}. The shield wins over the weapon, as in the engine.
function C.defence(s)
	s = s or {}
	local skill = num(s.fist)
	local value = num(s.bare)
	local weapon, shield = s.weapon, s.shield
	if weapon then
		value = num(weapon.defense) + num(weapon.extra)
		skill = num(weapon.skill)
	end
	if shield then
		value = weapon and (num(shield.defense) + num(weapon.extra)) or num(shield.defense)
		skill = num(s.shielding)
	end
	if skill <= 0 then
		return 1
	end
	local factor = num(s.factor)
	if factor <= 0 then
		factor = 1
	end
	return floor((skill / 4 + 2.23) * value * 0.15 * factor)
end

-- the share of a physical monster hit that does not land. Each part is a share 0 .. 1 of what the earlier ones left.
function C.mitigation(armourShare, absorbPercent, monsterPercent)
	local left = 1
	left = left * (1 - math.max(0, math.min(1, num(armourShare))))
	left = left * (1 - math.max(0, math.min(100, num(absorbPercent))) / 100)
	left = left * (1 - math.max(0, math.min(100, num(monsterPercent))) / 100)
	return 1 - left
end

-- the average auto attack hit of a weapon. w = {kind = "sword" | "club" | "axe" | "distance", attack, twoHanded,
-- launcher = "bow" | "crossbow" | nil, hitChance}; p = {level, skill}. nil when there is no hit to show.
function C.hit(w, p, mult, scale)
	local D = ChaosWeaponDps
	if not (D and w and p) or num(w.attack) <= 0 then
		return nil
	end
	local melee = w.kind == "sword" or w.kind == "club" or w.kind == "axe"
	if not melee and w.kind ~= "distance" then
		return nil
	end
	local launcher
	if not melee then
		launcher = w.launcher or "bow"
	end
	local dps = D.estimate({
		level = p.level, skill = p.skill, attack = w.attack, interval = 1000,
		launcher = launcher, twoHanded = w.twoHanded or false,
		weaponType = melee and w.kind or nil, hitChance = w.hitChance})
	if not dps then
		return nil
	end
	local hit = dps * (num(mult) > 0 and num(mult) or 1) * (num(scale) > 0 and num(scale) or 1)
	hit = floor(hit + 0.5)
	return hit > 0 and hit or nil
end

-- the message data. s = {level, weapon, shield, armourList, skills = {melee, distance, shielding, fist}, k, cap,
-- absorb (percent), monster (percent), mult (tree factor on a physical hit), scale (display scale)}
-- Returns {damage = n | nil, attack = n | nil, defense = n, armor = n, mitigation = share 0 .. 1}.
function C.build(s, cfg)
	s = s or {}
	cfg = cfg or {}
	local out = {}
	local w = s.weapon
	local skills = s.skills or {}
	local weaponSkill = 0
	if w then
		weaponSkill = (w.kind == "distance") and num(skills.distance) or num(skills.melee)
		if w.kind ~= "sword" and w.kind ~= "club" and w.kind ~= "axe" and w.kind ~= "distance" then
			weaponSkill = 0
		end
		if num(w.attack) > 0 and (w.kind == "sword" or w.kind == "club" or w.kind == "axe" or w.kind == "distance") then
			out.attack = floor(num(w.attack))
		end
		out.damage = C.hit(w, {level = s.level, skill = weaponSkill}, s.mult, s.scale)
	end
	out.defense = C.defence({
		weapon = w and {defense = w.defense, extra = w.extra, skill = weaponSkill} or nil,
		shield = s.shield, shielding = skills.shielding, fist = skills.fist,
		bare = cfg.bareDefense, factor = cfg.defenseFactor})
	out.armor = C.armour(s.armourList)
	local share = s.k and C.armourShare(out.armor, s.k, s.cap) or 0
	out.mitigation = floor(C.mitigation(share, s.absorb, s.monster) * 10000 + 0.5) / 10000
	return out
end

-- a stable text of a message's numbers, to send only what changed
function C.signature(d)
	return table.concat({tostring(d.damage), tostring(d.attack), tostring(d.defense), tostring(d.armor),
		tostring(d.mitigation)}, "|")
end

-- debounce and throttle state (a table per player id): C.dueSend(state, now, minGap) -> bool
function C.dueGet(state, now, gap)
	if state.at and now - state.at < gap then
		return false
	end
	state.at = now
	return true
end

return C

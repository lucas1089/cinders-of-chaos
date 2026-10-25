-- weapon_styles.lua: how weapon styles differ in auto attacks (spells are not affected).
--   * two-handed weapons (swords, axes, clubs, bows, crossbows) swing slower and hit harder: the slower speed is
--     the `attackspeed` items.xml gets from server/tools/two_handed.py (x1.5), this script multiplies the hit by the
--     factor of the wielder's level (weapon_balance_core.lua, weapon_balance_config.lua written by
--     server/tools/weapon_sim.py), so a two-handed weapon, a bow and a crossbow of one tier deal the damage per second
--     of one hand + shield within 4% (owner debug item 47; it was a flat x1.6: +12-26% for two hands, up to +99% for
--     launchers; server/data/spells/README.md "Weapon damage per second")
--   * ONE melee skill (owner debug item 46, melee_skill_core.lua): a sword, axe or club hit uses the best of the three
--     melee skills, not only the skill of its own type (the hit is multiplied by the ratio of the two maximum hits)
--   * wands and rods scale with the magic level (weapon_skill_core.lua): the engine's flat min .. max of weapons.xml
--     is multiplied by the magic level against the typical one of the wielder's level (owner 2026-10-20: "faça o dano
--     das armas/auto attack escalar com as skills"); the other weapons scale with their skill in the engine already
--   * the auto attack keeps up with the level and the skill (weapon_power_core.lua, owner 2026-10-23): a launcher and a
--     wand or rod are lifted to their share of the class's spell rotation at high levels, and a melee or launcher hit
--     also scales with (skill / typical skill) ^ 0.5 on top of the engine's skill term; a spell's weapon strike is not
--     an auto attack and is left out
--   * bows splash: the creatures around the target take arrowSplash of the hit (engine PvP rules apply)
--   * crossbows hit only their target (no splash)
--   * the quiver (data/lib/chaos_archery_core.lua), while it counts (a bow or crossbow in the hands): Critical Strike
--     with Bows, the element share (Adds N% of Bow Damage as an element, against the monster's resistance) and the
--     Extra Projectile Chance (a second missile at another monster close to the target, else at the target)
-- Bows and crossbows fire without ammunition (server/README.md "Infinite arrows and quivers"): which kind a launcher
-- is comes from chaos_archery_config.lua, not from an ammunition slot.
-- Only weapon hits are touched (combat origin melee / ranged; a wand hit has the melee origin in this engine); runes and
-- spells are not.
local cfg = {
	arrowSplash = 0.5,
}
ChaosWeaponStyles = cfg

if not ChaosArchery then
	dofile("data/lib/chaos_archery_core.lua")
end
local A = ChaosArchery
if not ChaosWeaponBalance then
	dofile("data/scripts/chaos/weapon_balance_core.lua")
end
local WB = ChaosWeaponBalance
if not ChaosMeleeSkill then
	dofile("data/scripts/chaos/melee_skill_core.lua")
end
local MS = ChaosMeleeSkill
if not ChaosWeaponSkill then
	dofile("data/scripts/chaos/weapon_skill_core.lua")
end
local WS = ChaosWeaponSkill
if not ChaosWeaponPower then
	dofile("data/scripts/chaos/weapon_power_core.lua")
end
local WP = ChaosWeaponPower

local splashArea = createCombatArea({
	{1, 1, 1},
	{1, 2, 1},
	{1, 1, 1},
})

-- weapon in the hands (not a shield, not ammunition, not a quiver): its item type, then the item
local function handWeapon(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local it = ItemType(item:getId())
			local wt = it:getWeaponType()
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO and wt ~= (WEAPON_QUIVER or 8) then
				return it, item
			end
		end
	end
	return nil
end

-- 1 while ChaosSpell.weaponStrike deals a strike (Chaos.storage.weaponStrike)
local STRIKE_KEY = (Chaos and Chaos.storage and Chaos.storage.weaponStrike) or 7100028

-- the melee weapon types and their skills (ONE melee skill: melee_skill_core.lua)
local MELEE_NAME = {[WEAPON_SWORD] = "sword", [WEAPON_CLUB] = "club", [WEAPON_AXE] = "axe"}
local MELEE_SKILL = {sword = SKILL_SWORD, club = SKILL_CLUB, axe = SKILL_AXE}

-- the attack of the weapon item the way the engine adds it up: a rarity roll or a unique writes it as an item attribute
local function itemAttack(item, it)
	local a = item:getAttribute(ITEM_ATTRIBUTE_ATTACK)
	if not a or a == 0 then
		a = it:getAttack()
	end
	return a or 0
end

-- Player::getAttackFactor: 1 offensive, 2 balanced, 3 defensive
local function attackFactor(player)
	local mode = player.getFightMode and player:getFightMode() or 1
	if mode == 2 then
		return 1.2
	elseif mode == 3 then
		return 2.0
	end
	return 1.0
end

-- what a hit of a sword, axe or club is multiplied by to be the hit of the best melee skill (1 when its own is the best)
local function meleeSkillMultiplier(player, item, it, typeName)
	local own = player:getEffectiveSkillLevel(MELEE_SKILL[typeName])
	local levels = {}
	for name, skill in pairs(MELEE_SKILL) do
		levels[name] = name == typeName and own or player:getEffectiveSkillLevel(skill)
	end
	local _, best = MS.best(levels)
	if best <= own then
		return 1
	end
	return MS.hitMultiplier(player:getLevel(), own, best, itemAttack(item, it), attackFactor(player))
end

-- the best of the three melee skills (ONE melee skill), the skill a melee hit scales with
local function bestMeleeSkill(player)
	local levels = {}
	for name, skill in pairs(MELEE_SKILL) do
		levels[name] = player:getEffectiveSkillLevel(skill)
	end
	local _, best = MS.best(levels)
	return best
end

local function isTwoHanded(it)
	return bit.band(it:getSlotPosition(), SLOTP_TWO_HAND) ~= 0
end

local function scale(value, factor)
	local v = math.floor(math.abs(value) * factor + 0.5)
	return value < 0 and -v or v
end

-- the quiver totals of the attacker (item_mods.lua counts a quiver only while a launcher is held)
local function bonus(player, key)
	local M = ChaosItemMods
	return M and M.playerBonus and M.playerBonus(player, key) or 0
end

-- monster resistance to a combat type (percent), cached by type name
local resCache = {}
local function resistance(creature, ctype)
	if not creature:isMonster() then
		return 0
	end
	-- the type name: monsters of other types shown under one name (rift names, invaders) have their own resistances
	local name
	if Chaos and Chaos.monsterTypeName then
		name = Chaos.monsterTypeName(creature)
	else
		local ok, n = pcall(function() return creature:getType():name() end)
		name = ok and type(n) == "string" and n ~= "" and n or creature:getName()
	end
	name = tostring(name):lower()
	local r = resCache[name]
	if r == nil then
		local ok, list = pcall(function() return creature:getType():getElementList() end)
		r = ok and type(list) == "table" and list or false
		resCache[name] = r
	end
	return r and tonumber(r[ctype]) or 0
end

-- the monster closest to `target` within the multishot range, other than the target (nil when none)
local function nextTarget(attacker, target)
	local range = A.config.effects.multishotRange
	local pos = target:getPosition()
	local best, bestDist
	for _, c in ipairs(Game.getSpectators(pos, false, false, range, range, range, range) or {}) do
		if c:isMonster() and c:getId() ~= target:getId() and c:getHealth() > 0 then
			local master = c:getMaster()
			if not (master and master:isPlayer()) then
				local p = c:getPosition()
				local d = math.max(math.abs(p.x - pos.x), math.abs(p.y - pos.y))
				if not bestDist or d < bestDist then
					best, bestDist = c, d
				end
			end
		end
	end
	return best
end

local extraDepth = 0 -- the extra projectile's own hit is not styled again

local function extraProjectile(attacker, target, kind, element, hit)
	local amount = A.extraHit(hit)
	if amount <= 0 then
		return
	end
	local attackerId, targetId = attacker:getId(), target:getId()
	local missile = A.extraMissile(kind, element)
	local vmissile = element and element.vmissile
	addEvent(function()
		local a, t = Creature(attackerId), Creature(targetId)
		if not a or not t then
			return
		end
		local victim = nextTarget(a, t) or t
		-- a fire or ice quiver sends the pair 41 fire / frost arrow (O239) where the client has it
		local sent = false
		if vmissile and ChaosVfxMissile and VfxShoot then
			if ChaosPack36Fx and ChaosPack36Fx.live then
				pcall(ChaosPack36Fx.live)
			end
			sent = ChaosVfxMissile[vmissile] ~= nil and VfxShoot(t:getPosition(), victim:getPosition(), vmissile)
		end
		if not sent then
			t:getPosition():sendDistanceEffect(victim:getPosition(), missile)
		end
		local K = ChaosKeystones
		if K then K.depth = (K.depth or 0) + 1 end
		extraDepth = extraDepth + 1
		local ok, err = pcall(doTargetCombatHealth, attackerId, victim, COMBAT_PHYSICALDAMAGE, -amount, -amount,
			CONST_ME_NONE, ORIGIN_RANGED)
		extraDepth = extraDepth - 1
		if K then K.depth = K.depth - 1 end
		if not ok then
			print("[ChaosWeaponStyle] " .. tostring(err))
		end
	end, 0)
end

local hit = CreatureEvent("ChaosWeaponStyle")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if not attacker or not attacker:isPlayer() or primaryType == COMBAT_HEALING or extraDepth > 0
			or (origin ~= ORIGIN_MELEE and origin ~= ORIGIN_RANGED) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local weapon, weaponItem = handWeapon(attacker)
	if not weapon then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local typeName = MELEE_NAME[weapon:getWeaponType()]
	-- a spell's scripted weapon strike (ChaosSpell.weaponStrike) was worked out with the best melee skill already
	if typeName and origin == ORIGIN_MELEE and attacker:getStorageValue(STRIKE_KEY) ~= 1 then
		local m = meleeSkillMultiplier(attacker, weaponItem, weapon, typeName)
		if m ~= 1 then
			primaryDamage = scale(primaryDamage, m)
			secondaryDamage = scale(secondaryDamage, m)
		end
	end
	-- a wand or rod: the flat hit of weapons.xml scaled by the magic level (weapon_skill_core.lua); nothing else applies
	if weapon:getWeaponType() == WEAPON_WAND then
		if origin == ORIGIN_MELEE and attacker:getStorageValue(STRIKE_KEY) ~= 1 then
			local m = WS.wandFactor(attacker:getLevel(), attacker:getMagicLevel()) * WP.levelFactor("wand", attacker:getLevel())
			if m ~= 1 then
				primaryDamage = scale(primaryDamage, m)
				secondaryDamage = scale(secondaryDamage, m)
			end
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local launcher = A.kindOfType(weapon)
	local styleFactor = WB.hitFactor(attacker:getLevel(), isTwoHanded(weapon), launcher, typeName)
	if styleFactor ~= 1 then
		primaryDamage = scale(primaryDamage, styleFactor)
		secondaryDamage = scale(secondaryDamage, styleFactor)
	end
	-- the auto attack keeps up with the level and the skill (weapon_power_core.lua); a spell's weapon strike is not an auto attack
	if attacker:getStorageValue(STRIKE_KEY) ~= 1 then
		local power
		if launcher and origin == ORIGIN_RANGED then
			power = WP.hitFactor("distance", attacker:getLevel(), attacker:getEffectiveSkillLevel(SKILL_DISTANCE))
		elseif typeName and origin == ORIGIN_MELEE then
			power = WP.hitFactor("melee", attacker:getLevel(), bestMeleeSkill(attacker))
		end
		if power and power ~= 1 then
			primaryDamage = scale(primaryDamage, power)
			secondaryDamage = scale(secondaryDamage, power)
		end
	end
	local kind = origin == ORIGIN_RANGED and launcher or nil
	if not kind then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	-- the quiver: critical strike, element share, extra projectile
	local crit = bonus(attacker, "bowcrit")
	if crit > 0 and math.random(1, 100) <= crit then
		primaryDamage = A.critHit(primaryDamage)
		secondaryDamage = A.critHit(secondaryDamage)
		if ChaosCombatFx and ChaosCombatFx.crit then
			ChaosCombatFx.crit(creature:getPosition(), attacker:getId())
		end
	end
	local totals = ChaosItemModsCache and ChaosItemModsCache[attacker:getId()]
	local element = A.elementOf(totals)
	if element and (secondaryDamage == 0 or secondaryType == COMBAT_NONE) and _G[element.combat] then
		local ctype = _G[element.combat]
		local extra = A.elementDamage(primaryDamage, element.pct, resistance(creature, ctype))
		if extra > 0 then
			secondaryType, secondaryDamage = ctype, primaryDamage < 0 and -extra or extra
			if _G[element.effect] then
				creature:getPosition():sendMagicEffect(_G[element.effect])
			end
		end
	end
	local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
	local multi = bonus(attacker, "multishot")
	if multi > 0 and math.random(1, 100) <= multi then
		extraProjectile(attacker, creature, kind, element, total)
	end

	if kind == "bow" then
		local amount = math.floor(total * cfg.arrowSplash)
		if amount > 0 then
			local attackerId, pos = attacker:getId(), creature:getPosition()
			-- after this hit is applied; area combat follows the engine's rules (PvP, protection zones, summons)
			addEvent(function()
				local a = Creature(attackerId)
				if a then
					-- a share of a hit that had the passive tree's bonuses already: the keystone guard keeps the tree (and
					-- the keystones) from applying to the splash a second time
					local K = ChaosKeystones
					if K then K.depth = (K.depth or 0) + 1 end
					local ok, err = pcall(doAreaCombat, a, primaryType, pos, splashArea, -amount, -amount, CONST_ME_HITAREA)
					if K then K.depth = K.depth - 1 end
					if not ok then
						print("[ChaosWeaponStyle] " .. tostring(err))
					end
				end
			end, 0)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

-- the event has to sit on whatever a player attacks (same approach as the passive tree / equipment scripts)
-- Chaos.registerOnce / eventKnown (chaos_constants.lua): register on a monster once, not at every hit
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local function eventKnown(creature, name)
	local f = Chaos and Chaos.eventKnown
	return f ~= nil and f(creature, name)
end
local target = EventCallback
target.onTargetCombat = function(creature, victim)
	if creature and victim and creature:isPlayer() then
		registerOnce(victim, "ChaosWeaponStyle")
	end
	return RETURNVALUE_NOERROR
end
target:register()

local login = CreatureEvent("ChaosWeaponStyleLogin")
function login.onLogin(player)
	player:registerEvent("ChaosWeaponStyle")
	return true
end
login:register()

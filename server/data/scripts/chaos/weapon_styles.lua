-- weapon_styles.lua: how weapon styles differ in auto attacks (spells are not affected).
--   * two-handed weapons (swords, axes, clubs, bows, crossbows) swing slower and hit harder: the slower speed is
--     the `attackspeed` items.xml gets from server/tools/two_handed.py (x1.5), this script multiplies the hit
--     (x twoHandedDamage), so a two-handed weapon does a bit more damage per second than one hand + shield
--   * arrows splash: the creatures around the target take arrowSplash of the hit (engine PvP rules apply)
--   * bolts hit only their target (no splash)
-- Only weapon hits are touched (combat origin melee / ranged); runes, spells and wands are not.
local cfg = {
	twoHandedDamage = 1.6,
	arrowSplash = 0.5,
}
ChaosWeaponStyles = cfg

local splashArea = createCombatArea({
	{1, 1, 1},
	{1, 2, 1},
	{1, 1, 1},
})

-- weapon in the hands (not a shield, not ammunition) and its item type
local function handWeapon(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local it = ItemType(item:getId())
			local wt = it:getWeaponType()
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO then
				return it
			end
		end
	end
	return nil
end

local function isTwoHanded(it)
	return bit.band(it:getSlotPosition(), SLOTP_TWO_HAND) ~= 0
end

local function firesArrows(player, weapon)
	if weapon:getWeaponType() ~= WEAPON_DISTANCE or weapon:getAmmoType() ~= AMMO_ARROW then
		return false
	end
	local ammo = player:getSlotItem(CONST_SLOT_AMMO)
	return ammo ~= nil and ItemType(ammo:getId()):getAmmoType() == AMMO_ARROW
end

local function scale(value, factor)
	local v = math.floor(math.abs(value) * factor + 0.5)
	return value < 0 and -v or v
end

local hit = CreatureEvent("ChaosWeaponStyle")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if not attacker or not attacker:isPlayer() or primaryType == COMBAT_HEALING
			or (origin ~= ORIGIN_MELEE and origin ~= ORIGIN_RANGED) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local weapon = handWeapon(attacker)
	if not weapon then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if isTwoHanded(weapon) then
		primaryDamage = scale(primaryDamage, cfg.twoHandedDamage)
		secondaryDamage = scale(secondaryDamage, cfg.twoHandedDamage)
	end
	if origin == ORIGIN_RANGED and firesArrows(attacker, weapon) then
		local amount = math.floor((math.abs(primaryDamage) + math.abs(secondaryDamage)) * cfg.arrowSplash)
		if amount > 0 then
			local attackerId, pos = attacker:getId(), creature:getPosition()
			-- after this hit is applied; area combat follows the engine's rules (PvP, protection zones, summons)
			addEvent(function()
				local a = Creature(attackerId)
				if a then
					doAreaCombat(a, primaryType, pos, splashArea, -amount, -amount, CONST_ME_HITAREA)
				end
			end, 0)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

-- the event has to sit on whatever a player attacks (same approach as the passive tree / equipment scripts)
local target = EventCallback
target.onTargetCombat = function(creature, victim)
	if creature and victim and creature:isPlayer() then
		victim:registerEvent("ChaosWeaponStyle")
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

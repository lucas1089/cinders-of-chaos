-- weapon_styles.lua: how weapon styles differ in auto attacks (spells are not affected).
--   * two-handed weapons (swords, axes, clubs, bows, crossbows) swing slower and hit harder: the slower speed is
--     the `attackspeed` items.xml gets from server/tools/two_handed.py (x1.5), this script multiplies the hit
--     (x twoHandedDamage), so a two-handed weapon does a bit more damage per second than one hand + shield
--   * bows splash: the creatures around the target take arrowSplash of the hit (engine PvP rules apply)
--   * crossbows hit only their target (no splash)
--   * the quiver (data/lib/chaos_archery_core.lua), while it counts (a bow or crossbow in the hands): Critical Strike
--     with Bows, the element share (Adds N% of Bow Damage as an element, against the monster's resistance) and the
--     Extra Projectile Chance (a second missile at another monster close to the target, else at the target)
-- Bows and crossbows fire without ammunition (server/README.md "Infinite arrows and quivers"): which kind a launcher
-- is comes from chaos_archery_config.lua, not from an ammunition slot.
-- Only weapon hits are touched (combat origin melee / ranged); runes, spells and wands are not.
local cfg = {
	twoHandedDamage = 1.6,
	arrowSplash = 0.5,
}
ChaosWeaponStyles = cfg

if not ChaosArchery then
	dofile("data/lib/chaos_archery_core.lua")
end
local A = ChaosArchery

local splashArea = createCombatArea({
	{1, 1, 1},
	{1, 2, 1},
	{1, 1, 1},
})

-- weapon in the hands (not a shield, not ammunition, not a quiver) and its item type
local function handWeapon(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local it = ItemType(item:getId())
			local wt = it:getWeaponType()
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO and wt ~= (WEAPON_QUIVER or 8) then
				return it
			end
		end
	end
	return nil
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
	local name = creature:getName():lower()
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
	addEvent(function()
		local a, t = Creature(attackerId), Creature(targetId)
		if not a or not t then
			return
		end
		local victim = nextTarget(a, t) or t
		t:getPosition():sendDistanceEffect(victim:getPosition(), missile)
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
	local weapon = handWeapon(attacker)
	if not weapon then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if isTwoHanded(weapon) then
		primaryDamage = scale(primaryDamage, cfg.twoHandedDamage)
		secondaryDamage = scale(secondaryDamage, cfg.twoHandedDamage)
	end
	local kind = origin == ORIGIN_RANGED and A.kindOfType(weapon) or nil
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

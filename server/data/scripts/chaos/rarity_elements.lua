-- rarity_elements.lua: several rarity elements on one character (base server script
-- data/scripts/customs/rarity/rarity_onCombat_elementdamage.lua).
--
-- The base script adds "X% <element> damage" of the rarity modifiers (storages 977554..977561, one per element, the
-- sum of the two hand slots) to a melee or ranged hit: (weapon element % + rarity %) of the physical part as the
-- secondary damage, of the weapon's element (else the rarity element). With two DIFFERENT rarity elements it returned
-- nothing from onHealthChange, which the engine reads as 0 damage: the whole hit was lost.
-- server/tools/patch_base_events.py (step 9) makes that branch call ChaosRarityElements.onHealthChange instead:
--   * every element gets its own share: the weapon's element its own %, each rarity element its own % (same formula
--     as the base script: physical * percent / 133); the same element twice is added up;
--   * the primary damage is never changed; one share goes into the hit's secondary damage like the base script does
--     (the one of the secondary's element when the hit already has one, else the largest); when the hit's secondary
--     already holds another element, every share becomes an extra hit;
--   * every other share is dealt right after the hit (addEvent 0) as its own hit of that element from the attacker
--     (doTargetCombat, ORIGIN_NONE: no damage events, so no second round of rarity / passive tree bonuses; the
--     target's resistances apply; the attacker's Intelligence bonus and the PvP halving that call adds are taken
--     back out, it can still roll a critical hit; PvP only where ChaosSpell.canAttack allows it).
-- A single rarity element keeps the base script's own path (unchanged). The mana part (onManaChange) has no element:
-- the patch lets it add every rarity element's % instead of stopping at the second one.

ChaosRarityElements = ChaosRarityElements or {}
local R = ChaosRarityElements

R.divisor = 133 -- the base script's formula: damage = physical * percent / 133
R.storages = {977554, 977555, 977556, 977557, 977558, 977559, 977560, 977561}
R.typeNames = {"COMBAT_FIREDAMAGE", "COMBAT_ICEDAMAGE", "COMBAT_ENERGYDAMAGE", "COMBAT_EARTHDAMAGE",
	"COMBAT_DEATHDAMAGE", "COMBAT_WATERDAMAGE", "COMBAT_HOLYDAMAGE", "COMBAT_ARCANEDAMAGE"}

-- the rarity element bonuses of a player: list of {type, percent} in the base script's order (fire .. arcane)
function R.bonuses(player)
	local list = {}
	for i, storage in ipairs(R.storages) do
		local ctype = _G[R.typeNames[i]]
		local value = tonumber(player:getStorageValue(storage)) or 0
		if ctype and value > 0 then
			list[#list + 1] = {type = ctype, percent = value}
		end
	end
	return list
end

-- the shares of one hit (pure): the weapon's own element first, then the rarity elements; one entry per element
function R.shares(baseElement, baseElementType, bonuses)
	local out, byType = {}, {}
	local function add(ctype, percent)
		if not ctype or ctype == COMBAT_NONE or (percent or 0) <= 0 then
			return
		end
		local entry = byType[ctype]
		if entry then
			entry.percent = entry.percent + percent
		else
			entry = {type = ctype, percent = percent}
			byType[ctype] = entry
			out[#out + 1] = entry
		end
	end
	add(baseElementType, tonumber(baseElement) or 0)
	for _, b in ipairs(bonuses or {}) do
		add(b.type, b.percent)
	end
	return out
end

-- split a hit (pure): returns primary, primaryType, secondary, secondaryType, extra ({type, damage} with damage > 0)
function R.split(shares, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local physical = primaryDamage < 0 and -primaryDamage or 0
	local parts = {}
	for _, s in ipairs(shares) do
		local damage = math.floor(physical * s.percent / R.divisor)
		if damage > 0 then
			parts[#parts + 1] = {type = s.type, damage = damage}
		end
	end
	local inline
	if secondaryType ~= COMBAT_NONE and secondaryDamage < 0 then
		for i, p in ipairs(parts) do
			if p.type == secondaryType then
				inline = i
				break
			end
		end
		if inline then
			secondaryDamage = secondaryDamage - parts[inline].damage
		end
	else
		for i, p in ipairs(parts) do
			if not inline or p.damage > parts[inline].damage then
				inline = i
			end
		end
		if inline then
			secondaryType = parts[inline].type
			secondaryDamage = -parts[inline].damage
		end
	end
	local extra = {}
	for i, p in ipairs(parts) do
		if i ~= inline then
			extra[#extra + 1] = p
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType, extra
end

-- what to pass to doTargetCombat so the target takes `damage` before its resistances: Combat::doTargetCombat adds
-- the attacker's Intelligence % to element damage and halves damage between players (not black skull); the share
-- was already taken of the hit after both (the inline share gets neither again), so they are taken back out here
function R.sentAmount(damage, intelligence, pvpHalved)
	local amount = damage
	intelligence = tonumber(intelligence) or 0
	if intelligence ~= 0 and 100 + intelligence > 0 then
		amount = math.floor(amount * 100 / (100 + intelligence) + 0.5)
	end
	if pvpHalved then
		amount = amount * 2
	end
	return math.max(1, amount)
end

-- the extra element hits, dealt one tick after the hit
function R.dealExtra(sourceId, targetId, extra)
	local source, target = Creature(sourceId), Creature(targetId)
	if not source or not target or target:getHealth() <= 0 then
		return
	end
	if target:isPlayer() and ChaosSpell and ChaosSpell.canAttack and not ChaosSpell.canAttack(source, target) then
		return
	end
	local intelligence = 0
	if source:isPlayer() and source.getCharacterStat and CHARSTAT_INTELLIGENCE then
		intelligence = tonumber(source:getCharacterStat(CHARSTAT_INTELLIGENCE)) or 0
	end
	local pvpHalved = source:isPlayer() and target:isPlayer() and target:getSkull() ~= SKULL_BLACK
	for _, p in ipairs(extra) do
		if target:getHealth() <= 0 then
			return
		end
		local amount = R.sentAmount(p.damage, intelligence, pvpHalved)
		local ok, err = pcall(doTargetCombat, source, target, p.type, -amount, -amount, CONST_ME_NONE, ORIGIN_NONE)
		if not ok then
			print("[ChaosRarityElements] " .. tostring(err))
		end
	end
end

-- called by the patched base script when the attacker has two or more different rarity elements; always returns the
-- four damage values (never nil: nil is 0 damage for the engine)
function R.onHealthChange(source, target, baseElement, baseElementType, primaryDamage, primaryType, secondaryDamage,
		secondaryType)
	local ok, p, pt, s, st, extra = pcall(function()
		local shares = R.shares(baseElement, baseElementType, R.bonuses(source))
		return R.split(shares, primaryDamage, primaryType, secondaryDamage, secondaryType)
	end)
	if not ok then
		print("[ChaosRarityElements] " .. tostring(p))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if #extra > 0 and target then
		addEvent(R.dealExtra, 0, source:getId(), target:getId(), extra)
	end
	return p, pt, s, st
end

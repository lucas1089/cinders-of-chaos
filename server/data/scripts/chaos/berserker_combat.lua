-- berserker_combat.lua: the Berserker's Rage and Bloodrage (docs/CLASSES.md; rules in classes.lua, numbers in
-- Chaos.classes.rage / .bloodrage, chaos_constants.lua).
--
--   * Rage (passive): every damage the Berserker deals gets a bonus that grows as its health drops: 0 at full health,
--     up to +30% at 30% health and below (ChaosClasses.rageMultiplier).
--   * Bloodrage (spell, berserker/bloodrage.lua): costs 10% of the current health (which feeds Rage); for 12 s Rage
--     gets +10% on top and every melee weapon hit also strikes up to 4 other enemies next to the Berserker for 40% of
--     the hit. The spell adds a condition (CONDITION_ATTRIBUTES, sub id Chaos.classes.subId.bloodrage): the spells
--     and this file run in different Lua states, the condition is the state both see.
-- The cleave strikes are dealt with origin ORIGIN_NONE inside a guard flag, so they get no Rage of their own and
-- never cleave again. Extra hits of the passive tree keystones (ChaosKeystones.depth > 0) get no Rage either: they
-- are shares of a hit that had it.

if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end
local C = ChaosClasses
local function cfg()
	return Chaos.classes
end

local scripted = false

local function scale(value, factor)
	local v = math.floor(math.abs(value) * factor + 0.5)
	return value < 0 and -v or v
end

local function inBloodrage(player)
	return player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, cfg().subId.bloodrage) ~= nil
end

-- the enemies next to the Berserker, other than the creature it just hit
local function cleaveTargets(player, mainId)
	local list = {}
	local pos = player:getPosition()
	for _, c in ipairs(Game.getSpectators(pos, false, false, 1, 1, 1, 1) or {}) do
		if c ~= player and c:getId() ~= mainId and c:getHealth() > 0 then
			local ok = false
			if c:isMonster() then
				local master = c:getMaster()
				ok = not (master and master:isPlayer())
			elseif c:isPlayer() then
				ok = ChaosSpell and ChaosSpell.canAttack(player, c) or false
			end
			if ok then
				list[#list + 1] = c:getId()
			end
		end
	end
	table.sort(list)
	for i = #list, cfg().bloodrage.maxTargets + 1, -1 do
		list[i] = nil
	end
	return list
end

local function cleave(playerId, ids, amount, ctype)
	local player = Player(playerId)
	if not player then
		return
	end
	for _, id in ipairs(ids) do
		local target = Creature(id)
		if target and target:getHealth() > 0 then
			scripted = true
			local ok, err = pcall(doTargetCombat, player, target, ctype or COMBAT_PHYSICALDAMAGE, -amount, -amount,
				CONST_ME_DRAWBLOOD, ORIGIN_NONE)
			scripted = false
			if not ok then
				print("[ChaosBerserker] " .. tostring(err))
			end
		end
	end
end

local function onOffence(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local player = attacker and attacker:getPlayer()
	if not player or scripted or primaryType == COMBAT_HEALING or creature == player then
		return primaryDamage, secondaryDamage
	end
	if not C.isBerserker(player:getVocation():getId()) then
		return primaryDamage, secondaryDamage
	end
	if ChaosKeystones and (ChaosKeystones.depth or 0) > 0 then
		return primaryDamage, secondaryDamage
	end
	if primaryDamage == 0 and secondaryDamage == 0 then
		return primaryDamage, secondaryDamage
	end
	local blood = inBloodrage(player)
	local mult = C.rageMultiplier(player:getHealth(), player:getMaxHealth(), blood)
	if mult ~= 1 then
		primaryDamage = scale(primaryDamage, mult)
		secondaryDamage = scale(secondaryDamage, mult)
	end
	if blood and origin == ORIGIN_MELEE then
		local value = C.bloodrageCleave(math.abs(primaryDamage) + math.abs(secondaryDamage))
		if value > 0 then
			local ids = cleaveTargets(player, creature:getId())
			if #ids > 0 then
				addEvent(cleave, cfg().bloodrage.delayMs, player:getId(), ids, value, primaryType)
			end
		end
	end
	return primaryDamage, secondaryDamage
end

local event = CreatureEvent("ChaosBerserkerCombat")
function event.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local ok, a, b = pcall(onOffence, creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if not ok then
		print("[ChaosBerserker] " .. tostring(a))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return a, primaryType, b, secondaryType
end
event:register()

-- the event has to sit on whatever a Berserker attacks (the spells' area hits go through onTargetCombat too)
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
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and not eventKnown(target, "ChaosBerserkerCombat")
			and C.isBerserker(creature:getVocation():getId()) then
		registerOnce(target, "ChaosBerserkerCombat")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

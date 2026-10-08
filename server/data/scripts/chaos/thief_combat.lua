-- thief_combat.lua: the combat mechanics of the Thief line (Thief, Ninja, Samurai; docs/CLASSES.md).
-- Rules and numbers: classes.lua (ChaosClasses) and Chaos.classes in chaos_constants.lua.
--
--   * Evasion (all three): a chance to dodge melee and ranged hits (monster attacks and player weapons). A dodge
--     takes no damage and shows ChaosCombatFx.dodge.
--   * Shadow Veil (spell, thief/shadow_veil.lua): an invisibility condition (sub id Chaos.classes.subId.stealth).
--     While it lasts monsters drop the player as a target (the spell pulses that) and a monster that still targets it
--     cannot attack it (onTargetCombat below); a hit from anything else, or the player dealing damage, ends it. The
--     first weapon hit out of it is a critical hit (x ambushMultiplier).
--   * Poison Blades (spell): while the buff lasts, weapon hits poison the target (earth damage over a few seconds).
--   * Ninja dual wield: with a light blade (a one-handed sword) in each hand, every melee hit of the main hand is
--     followed by an off-hand strike for ~50% of it. Holding the second sword in the shield hand needs the engine
--     change server/src-patches/0002-dual-wield-and-vocation-attack-speed.patch, which reads the storage this
--     file keeps at 1 for Ninjas (Chaos.classes.storage.dualWield).
--   * Samurai Counter Stance (spell): the next melee hit within 2 s is parried and answered.
--   * Samurai Bushido Focus (spell): crit chance stacks every second without taking damage.
-- Scripted strikes (off-hand, counter) are dealt with origin ORIGIN_NONE inside a guard flag, so they never trigger
-- the weapon-hit rules again (no off-hand from an off-hand, no poison, no second ambush).

if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
-- ChaosSpell.canAttack (the PvP rules of the scripted strikes) lives with the spells; load it into this state too
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end
local C = ChaosClasses
local function cfg()
	return Chaos.classes
end

local scripted = false -- guard: true while this file deals its own strikes

local function hasCond(creature, ctype, subId)
	return creature:getCondition(ctype, CONDITIONID_COMBAT, subId) ~= nil
end

local function stealthed(creature)
	return creature:isPlayer() and hasCond(creature, CONDITION_INVISIBLE, cfg().subId.stealth)
end

local function endStealth(player)
	player:removeCondition(CONDITION_INVISIBLE, CONDITIONID_COMBAT, cfg().subId.stealth)
end

local function scale(value, factor)
	local v = math.floor(math.abs(value) * factor + 0.5)
	return value < 0 and -v or v
end

local function itemAttack(item)
	local a = item:getAttribute(ITEM_ATTRIBUTE_ATTACK)
	if not a or a == 0 then
		a = ItemType(item:getId()):getAttack()
	end
	return a or 0
end

local function lightBlade(item)
	if not item then
		return false
	end
	local it = ItemType(item:getId())
	return C.isLightBlade(it:getWeaponType(), it:getSlotPosition())
end

-- Bushido: the buff condition is the truth; the stacks are counted here (classes.lua)
local function bushidoSync(player, now)
	local cond = player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, cfg().subId.bushido)
	local id = player:getId()
	if not cond then
		C.bushidoState[id] = nil
		return false
	end
	local s = C.bushidoState[id]
	local left = cond:getTicks()
	-- unknown, or recast (more time left than this state expects): start / refresh
	if not s or left > (s.untilMs - now) + 500 then
		C.bushidoStart(id, now)
		C.bushidoState[id].untilMs = now + left
	end
	return true
end

-- ------------------------------------------------------------------------------------------------ offence
local function offhandStrike(attackerId, targetId, amount, ctype)
	local attacker, target = Player(attackerId), Creature(targetId)
	if not attacker or not target or target:getHealth() <= 0 then
		return
	end
	if target:isPlayer() and ChaosSpell and not ChaosSpell.canAttack(attacker, target) then
		return
	end
	scripted = true
	local ok, err = pcall(doTargetCombat, attacker, target, ctype or COMBAT_PHYSICALDAMAGE, -amount, -amount,
		CONST_ME_DRAWBLOOD, ORIGIN_NONE)
	scripted = false
	if not ok then
		print("[ChaosThief] " .. tostring(err))
	end
end

local function poison(attacker, target, hit)
	local p = cfg().poisonBlades
	local c = Condition(CONDITION_POISON)
	c:setParameter(CONDITION_PARAM_OWNER, attacker:getId())
	c:setParameter(CONDITION_PARAM_DELAYED, true)
	c:addDamage(p.ticks, p.tickMs, -C.poisonTick(hit))
	target:addCondition(c)
end

local function onOffence(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local player = attacker and attacker:getPlayer()
	if not player or scripted or primaryType == COMBAT_HEALING or creature == player then
		return primaryDamage, secondaryDamage
	end
	local voc = player:getVocation():getId()
	if not C.isThiefLine(voc) then
		return primaryDamage, secondaryDamage
	end
	local amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if amount == 0 then
		return primaryDamage, secondaryDamage
	end
	local now = C.now()
	local isWeapon = origin == ORIGIN_MELEE or origin == ORIGIN_RANGED
	local mult, crit = 1, false

	-- Shadow Veil: dealing damage ends it, the first weapon hit out of it crits
	local m, ends = C.stealthOnAttack(stealthed(player), isWeapon, amount)
	if ends then
		endStealth(player)
	end
	if m > 1 then
		mult, crit = mult * m, true
	end

	-- Bushido Focus: crit chance from the stacks (weapon hits; Iaijutsu rolls it itself)
	if isWeapon and C.isSamurai(voc) and bushidoSync(player, now) then
		local bm, bc = C.bushidoRoll(player:getId(), now, math.random())
		if bc and not crit then
			mult, crit = mult * bm, true
		end
	end

	if mult ~= 1 then
		primaryDamage = scale(primaryDamage, mult)
		secondaryDamage = scale(secondaryDamage, mult)
		amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	end
	if crit and ChaosCombatFx then
		ChaosCombatFx.crit(creature:getPosition(), player:getId())
	end

	-- Poison Blades
	if isWeapon and hasCond(player, CONDITION_ATTRIBUTES, cfg().subId.poisonBlades) then
		poison(player, creature, amount)
	end

	-- Ninja dual wield: an off-hand strike after each melee hit of the main hand
	if origin == ORIGIN_MELEE then
		local main, off = player:getSlotItem(CONST_SLOT_LEFT), player:getSlotItem(CONST_SLOT_RIGHT)
		if C.dualWieldProc(voc, true, lightBlade(main), lightBlade(off), scripted, amount) then
			local value = C.offhandDamage(amount, itemAttack(main), itemAttack(off), creature:isPlayer())
			if value > 0 then
				addEvent(offhandStrike, cfg().dualWield.delayMs, player:getId(), creature:getId(), value,
					primaryType)
			end
		end
	end
	return primaryDamage, secondaryDamage
end

-- ------------------------------------------------------------------------------------------------ defence
local function counterStrike(playerId, targetId, amount)
	local player, target = Player(playerId), Creature(targetId)
	if not player or not target or target:getHealth() <= 0 then
		return
	end
	if ChaosSpell and not ChaosSpell.canAttack(player, target) then
		return
	end
	player:getPosition():sendDistanceEffect(target:getPosition(), CONST_ANI_WHIRLWINDSWORD)
	scripted = true
	local ok, err = pcall(doTargetCombat, player, target, COMBAT_PHYSICALDAMAGE, -amount, -amount,
		CONST_ME_HITAREA, ORIGIN_NONE)
	scripted = false
	if not ok then
		print("[ChaosThief] " .. tostring(err))
	end
end

local function onDefence(player, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not attacker or attacker == player or origin == ORIGIN_CONDITION then
		return primaryDamage, secondaryDamage
	end
	local voc = player:getVocation():getId()
	if not C.isThiefLine(voc) then
		return primaryDamage, secondaryDamage
	end
	local amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if amount == 0 then
		return primaryDamage, secondaryDamage
	end
	local now = C.now()
	local isMelee = origin == ORIGIN_MELEE
	local isWeapon = isMelee or origin == ORIGIN_RANGED

	-- Counter Stance: parry the next melee hit and answer it
	if C.isSamurai(voc) then
		local cond = player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, cfg().subId.counter)
		if C.counterTake(cond and cond:getTicks() or 0, isMelee, true) then
			player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, cfg().subId.counter)
			player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
			if ChaosCombatFx then
				ChaosCombatFx.label(player:getPosition(), "PARRY", 35)
			end
			addEvent(counterStrike, 100, player:getId(), attacker:getId(), C.counterDamage(amount))
			return 0, 0
		end
	end

	-- Evasion
	if C.dodges(voc, isWeapon, math.random()) then
		if ChaosCombatFx then
			ChaosCombatFx.dodge(player)
		end
		return 0, 0
	end

	-- the hit lands: it ends the stealth and resets the Bushido stacks
	if C.stealthOnHit(stealthed(player), amount, true) then
		endStealth(player)
	end
	if C.isSamurai(voc) and bushidoSync(player, now) then
		C.bushidoOnDamaged(player:getId(), now)
	end
	return primaryDamage, secondaryDamage
end

local event = CreatureEvent("ChaosThiefCombat")
function event.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local ok, a, b = pcall(function()
		local p, s = onOffence(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
		if creature:isPlayer() then
			p, s = onDefence(creature, attacker, p, primaryType, s, secondaryType, origin)
		end
		return p, s
	end)
	if not ok then
		print("[ChaosThief] " .. tostring(a))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return a, primaryType, b, secondaryType
end
event:register()

-- register on whatever a player attacks; a monster that targets a stealthed player cannot attack it
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if not creature or not target then
		return RETURNVALUE_NOERROR
	end
	if creature:isPlayer() then
		target:registerEvent("ChaosThiefCombat")
	elseif creature:isMonster() and target:isPlayer() and creature:getTarget() == target
			and not C.monsterMayTarget(stealthed(target), true) then
		creature:setTarget(nil)
		creature:setFollowCreature(nil)
		creature:removeTarget(target)
		return RETURNVALUE_NOTPOSSIBLE
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(5)

local login = CreatureEvent("ChaosThiefLogin")
function login.onLogin(player)
	player:registerEvent("ChaosThiefCombat")
	player:registerEvent("ChaosThiefLogout")
	C.syncDualWield(player)
	return true
end
login:register()

local logout = CreatureEvent("ChaosThiefLogout")
function logout.onLogout(player)
	C.clear(player:getId())
	return true
end
logout:register()

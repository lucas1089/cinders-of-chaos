-- monk_combat.lua: the combat mechanics of the Monk line (Monk, Shadowfist, Iron Sage; docs/CLASSES.md).
-- Rules and numbers: monk_chi_core.lua (ChaosMonk, ChaosMonk.cfg, every id in ChaosMonk.ids).
--
--   * Unarmed: the engine hits with fists for attack 7 and leaves out the vocation's meleeDamage. A Monk's fist hit
--     (melee origin, no weapon in hand) is scaled to a level-based fist attack (ChaosMonk.unarmedFactor), or to the
--     attack of a fist weapon in hand (ChaosMonk.cfg.unarmed.fistWeapons). Staves (clubs) are ordinary weapons.
--   * Chi: a melee weapon or fist hit of a Monk gives a chi (at most one every weaponHitIcdMs). The spells give and
--     spend the rest (data/spells/chaos/monk|shadowfist|ironsage). The HUD (client game_monkchi) is sent on login.
--   * Monk strikes: the kit's damage comes with ORIGIN_SPELL from a Monk; melee origin from a Monk is its auto attack.
--   * Shadowfist focus: after a finisher, the Shadowfist's weapon hits and strikes crit with the chi spent
--     (condition subId.focus, chi in storage.focusChi).
--   * Pressure Points: a target with stacks (one condition per stack, subId.pressure) takes more from Monks.
--   * Evasion: a chance to dodge melee / ranged hits, more while Mistborne Step's window lasts (subId.roll).
--   * Chi Ward: a shield on any player (subId.ward timer, storage.wardAmount) absorbs damage.
--   * Mantra of Stone: players under it (subId.mantra) take less damage.
--   * Iron Palm stun: a monster under the stun (subId.stun) cannot attack (onTargetCombat below).
-- Scripted damage is not dealt here, so there is no recursion guard; the scaled values are returned to the engine.

if not ChaosMonk then
	dofile("data/scripts/chaos/monk_chi_core.lua")
end
local M = ChaosMonk
local ID = M.ids
if not ChaosClassTree then
	dofile("data/scripts/chaos/class_tree.lua") -- the class nodes of the passive tree
end
local CT = ChaosClassTree

local function hasCond(creature, ctype, subId)
	return creature:getCondition(ctype, CONDITIONID_COMBAT, subId) ~= nil
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

-- nil when a weapon is in the hands; else the best fist weapon's attack (0 = bare fists)
local function fistWeaponAttack(player)
	local best = 0
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local wt = ItemType(item:getId()):getWeaponType()
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO then
				return nil
			end
			for _, id in ipairs(M.cfg.unarmed.fistWeapons) do
				if id == item:getId() then
					best = math.max(best, itemAttack(item))
				end
			end
		end
	end
	return best
end

local function pressureStacks(creature)
	local n = 0
	for _, sub in ipairs(ID.subId.pressure) do
		if hasCond(creature, CONDITION_ATTRIBUTES, sub) then
			n = n + 1
		end
	end
	return n
end

-- ------------------------------------------------------------------------------------------------ offence
local function onOffence(creature, attacker, primaryDamage, secondaryDamage, primaryType, origin)
	local player = attacker and attacker:getPlayer()
	if not player or primaryType == COMBAT_HEALING or creature == player then
		return primaryDamage, secondaryDamage
	end
	local voc = player:getVocation():getId()
	if not M.isMonkLine(voc) then
		return primaryDamage, secondaryDamage
	end
	if math.abs(primaryDamage) + math.abs(secondaryDamage) == 0 then
		return primaryDamage, secondaryDamage
	end
	local isMelee = origin == ORIGIN_MELEE
	local isStrike = isMelee or origin == ORIGIN_RANGED or origin == ORIGIN_SPELL
	local mult = 1

	-- unarmed: the engine's fist hit becomes the Monk's
	if isMelee then
		local fist = fistWeaponAttack(player)
		if fist then
			mult = mult * M.unarmedFactor(voc, player:getLevel(), player:getEffectiveSkillLevel(SKILL_FIST), fist,
				M.attackFactor(player.getFightMode and player:getFightMode() or 1))
		end
		-- chi from the auto attack (one per weaponHitIcdMs)
		local id, now = player:getId(), M.now()
		if M.weaponHitGivesChi(M.lastWeaponChi[id], now) then
			M.lastWeaponChi[id] = now
			M.addChi(player, M.cfg.chi.perWeaponHit)
		end
	end

	-- Pressure Points on the target
	if isStrike then
		local stacks = pressureStacks(creature)
		if stacks > 0 then
			mult = mult * M.pressureMultiplier(stacks, CT.value(player, "ctNerveStrike", "perStack"))
		end
	end

	-- Shadowfist focus window: the crit grows with the chi the last finisher spent
	if isStrike and M.isShadowfist(voc) and hasCond(player, CONDITION_ATTRIBUTES, ID.subId.focus) then
		local m, crit = M.focusRoll(player:getStorageValue(ID.storage.focusChi), math.random())
		if crit then
			mult = mult * m
			if ChaosCombatFx then
				ChaosCombatFx.crit(creature:getPosition(), player:getId())
			end
			-- Hundred Hands (the passive tree): a focus crit gives a chi
			if CT.has(player, "ksHundredHands") then
				local f = CT.fx.ksHundredHands
				if M.critGivesChi(player:getId(), M.now(), f.icdMs) then
					M.addChi(player, f.chi)
				end
			end
		end
	end


	if mult ~= 1 then
		primaryDamage = scale(primaryDamage, mult)
		secondaryDamage = scale(secondaryDamage, mult)
	end
	return primaryDamage, secondaryDamage
end

-- ------------------------------------------------------------------------------------------------ defence
local function onDefence(player, attacker, primaryDamage, secondaryDamage, primaryType, origin)
	if primaryType == COMBAT_HEALING or attacker == player then
		return primaryDamage, secondaryDamage
	end
	local amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if amount == 0 then
		return primaryDamage, secondaryDamage
	end
	local voc = player:getVocation():getId()

	-- evasion (Monk line; melee and ranged hits of creatures)
	if attacker and M.isMonkLine(voc) and origin ~= ORIGIN_CONDITION then
		local isWeapon = origin == ORIGIN_MELEE or origin == ORIGIN_RANGED
		if M.dodges(voc, isWeapon, hasCond(player, CONDITION_ATTRIBUTES, ID.subId.roll), math.random()) then
			if ChaosCombatFx then
				ChaosCombatFx.dodge(player)
			end
			return 0, 0
		end
	end

	-- Mantra of Stone (anyone under it; the Deep Mantra one is stronger)
	local deep = hasCond(player, CONDITION_ATTRIBUTES, ID.subId.mantraDeep)
	if deep or hasCond(player, CONDITION_ATTRIBUTES, ID.subId.mantra) then
		local f = M.mantraDamage(amount, deep and CT.fx.ctDeepMantra.reduction or nil) / amount
		primaryDamage, secondaryDamage = scale(primaryDamage, f), scale(secondaryDamage, f)
		amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	end

	-- Chi Ward (anyone carrying one): absorbs from the primary damage first
	if amount > 0 and hasCond(player, CONDITION_ATTRIBUTES, ID.subId.ward) then
		local left = player:getStorageValue(ID.storage.wardAmount)
		if left > 0 then
			local throughP, rest = M.absorb(left, math.abs(primaryDamage))
			local throughS, rest2 = M.absorb(rest, math.abs(secondaryDamage))
			primaryDamage = primaryDamage < 0 and -throughP or throughP
			secondaryDamage = secondaryDamage < 0 and -throughS or throughS
			player:setStorageValue(ID.storage.wardAmount, rest2)
			player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
			if rest2 <= 0 then
				player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, ID.subId.ward)
			end
		end
	end
	return primaryDamage, secondaryDamage
end

local event = CreatureEvent("ChaosMonkCombat")
function event.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local ok, a, b = pcall(function()
		local p, s = onOffence(creature, attacker, primaryDamage, secondaryDamage, primaryType, origin)
		if creature:isPlayer() then
			p, s = onDefence(creature, attacker, p, s, primaryType, origin)
		end
		return p, s
	end)
	if not ok then
		print("[ChaosMonk] " .. tostring(a))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return a, primaryType, b, secondaryType
end
event:register()

-- register on whatever a player attacks; a stunned monster cannot attack
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if not creature or not target then
		return RETURNVALUE_NOERROR
	end
	if creature:isPlayer() then
		target:registerEvent("ChaosMonkCombat")
	elseif creature:isMonster() and hasCond(creature, CONDITION_PARALYZE, ID.subId.stun) then
		return RETURNVALUE_NOTPOSSIBLE
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(6)

local login = CreatureEvent("ChaosMonkLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMonkCombat")
	player:registerEvent("ChaosMonkLogout")
	-- the HUD: shown for the Monk line (current chi), hidden for everyone else
	M.sendChi(player, M.getChi(player))
	return true
end
login:register()

local logout = CreatureEvent("ChaosMonkLogout")
function logout.onLogout(player)
	M.clear(player:getId())
	return true
end
logout:register()

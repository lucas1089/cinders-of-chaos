-- monk_combat.lua: the combat mechanics of the Monk line (Monk, Shadowfist, Iron Sage; docs/CLASSES.md).
-- Rules and numbers: monk_chi_core.lua (ChaosMonk, ChaosMonk.cfg, every id in ChaosMonk.ids).
--
--   * Unarmed: the engine hits with fists for attack 7 and leaves out the vocation's meleeDamage. A Monk's fist hit
--     (melee origin, no weapon in hand) is scaled to a level-based fist attack (ChaosMonk.unarmedFactor), or to the
--     attack of a fist weapon in hand (ChaosMonk.cfg.unarmed.fistWeapons), then by the weapon power of the fist skill
--     (ChaosWeaponPower kind "fist", server/README.md "Auto attack power"). Staves (clubs) are ordinary weapons.
--   * Chi: a melee weapon or fist hit of a Monk gives a chi (at most one every weaponHitIcdMs). The spells give and
--     spend the rest (data/spells/chaos/monk|shadowfist|ironsage). The HUD (client game_monkchi) is sent on login.
--   * Monk strikes: the kit's damage comes with ORIGIN_SPELL from a Monk; melee origin from a Monk is its auto attack.
--   * Shadowfist focus: after a finisher, the Shadowfist's weapon hits and strikes crit with the chi spent
--     (condition subId.focus, chi in storage.focusChi).
--   * Pressure Points: a target with stacks (one condition per stack, subId.pressure) takes more from Monks.
--   * Evasion: a chance to dodge melee / ranged hits.
--   * Chi Ward: a shield on any player (subId.ward timer, storage.wardAmount) absorbs damage.
--   * Mantra of Stone: players under it (subId.mantra) take less damage.
--   * Scarred Discipline (the line's keystone in the main tree, node 390): no evasion; a hit taken from a creature
--     gives a chi (one every 2 s); 10% less damage taken while holding 3 chi or more.
--   * Iron Palm stun: a monster under the stun (subId.stun) cannot attack (onTargetCombat below). A player hit by an
--     Iron Palm (the spell sets storage.palmChi while its strike lands) is stunned here, after every PvP rule let the
--     damage through: the engine's movement block and no-move flag (no walking, not pushed; released by a timer at
--     the exact time) and CONDITION_PACIFIED (no attacks, no attack spells or runes; it ends on time by itself). Immunity and diminishing returns
--     are condition timers on the victim (subId.stunImmune, subId.stunDr); the buff bar shows "Stunned".
-- Scripted damage is not dealt here, so there is no recursion guard; the scaled values are returned to the engine.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosMonk then
	dofile("data/scripts/chaos/monk_chi_core.lua")
end
local M = ChaosMonk
local ID = M.ids
if not ChaosClassTree then
	dofile("data/scripts/chaos/class_tree.lua") -- the class nodes of the passive tree
end
local CT = ChaosClassTree
if not ChaosKeystoneLabels then
	dofile("data/scripts/chaos/keystone_labels.lua") -- the combat log's keystone rows (optional)
end
local KL = ChaosKeystoneLabels
if not ChaosWeaponPower then
	dofile("data/scripts/chaos/weapon_power_core.lua") -- the auto attack keeps up with the level and the skill
end
local WP = ChaosWeaponPower

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
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO and wt ~= (WEAPON_QUIVER or 8) then
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
			local skill = player:getEffectiveSkillLevel(SKILL_FIST)
			mult = mult * M.unarmedFactor(voc, player:getLevel(), skill, fist,
				M.attackFactor(player.getFightMode and player:getFightMode() or 1))
			-- the same weapon power as every other weapon (weapon_power_core.lua, kind "fist"): the fist skill against the
			-- typical skill of the level, ^ 0.5, clamped; 1 at the typical skill, so the measured balance stands
			mult = mult * WP.hitFactor("fist", player:getLevel(), skill)
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
					KL.note(player, "ksHundredHands", 0)
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
	-- Scarred Discipline (the line keystone): no evasion; hits taken give chi; less damage taken at 3+ chi
	local scar = M.isMonkLine(voc) and CT.has(player, "ksScarredDiscipline") and CT.fx.ksScarredDiscipline or nil

	-- evasion (Monk line; melee and ranged hits of creatures)
	if attacker and M.isMonkLine(voc) and origin ~= ORIGIN_CONDITION then
		local isWeapon = origin == ORIGIN_MELEE or origin == ORIGIN_RANGED
		if M.dodges(voc, isWeapon, math.random(), scar ~= nil) then
			if ChaosCombatFx then
				ChaosCombatFx.dodge(player)
			end
			return 0, 0
		end
	end

	if scar and attacker and origin ~= ORIGIN_CONDITION then
		local chi = M.getChi(player)
		local f = M.scarFactor(chi, scar)
		if f ~= 1 then
			local before = amount
			primaryDamage, secondaryDamage = scale(primaryDamage, f), scale(secondaryDamage, f)
			amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
			KL.note(player, "ksScarredDiscipline", before - amount)
		end
		if M.scarGivesChi(player:getId(), M.now(), scar) then
			M.addChi(player, scar.chi)
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

-- ------------------------------------------------------------------------------------------------ Iron Palm on players
local function timer(creature, subId, ticks)
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, subId)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	creature:addCondition(c)
end

-- the buff bar is told at once (a stun is shorter than its once-per-second look)
local function pushBuffBar(player)
	local Bar, B = ChaosBuffBar, ChaosBuffs
	local w = Bar and Bar.watch and Bar.watch[player:getId()]
	if w and B then
		B.forget(player:getId())
		pcall(Bar.update, player, w, B.nowMs(), false)
	end
end

-- ends a stun: only what this file set is undone (another script's movement block stays)
local function releaseStun(id)
	local s = M.pvpStun[id]
	M.pvpStun[id] = nil
	local p = Player(id)
	if not s or not p then
		return
	end
	if s.blocked then
		p:setMovementBlocked(false)
	end
	if s.noMove then
		p:setNoMove(false)
	end
	p:unregisterEvent("ChaosMonkStunThink")
	pushBuffBar(p)
end

local function releaseIfOver(id)
	local s = M.pvpStun[id]
	if s and M.now() >= s.untilMs then
		releaseStun(id)
	end
end

local function stunPlayer(victim, monk, chi)
	local cfgPvp = M.cfg.stun.pvp
	local immune = hasCond(victim, CONDITION_ATTRIBUTES, ID.subId.stunImmune)
	local ms = M.pvpStunFor(chi, immune, hasCond(victim, CONDITION_ATTRIBUTES, ID.subId.stunDr))
	if ms <= 0 then
		if immune then
			monk:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(monk, "%s cannot be stunned again yet.", victim:getName()))
		end
		return
	end
	local id, now = victim:getId(), M.now()
	local s = M.pvpStun[id]
	if not s then
		s = {}
		if not victim:isMovementBlocked() then
			victim:setMovementBlocked(true)
			s.blocked = true
		end
		if victim:canMove() then
			victim:setNoMove(true) -- also stops a walk already queued
			s.noMove = true
		end
		M.pvpStun[id] = s
		victim:registerEvent("ChaosMonkStunThink")
	end
	s.untilMs = now + ms
	-- the attack lock: the engine only sees CONDITION_PACIFIED with sub id 0 (Creature::hasCondition), and checks its
	-- end time to the millisecond, so the condition ends on time by itself. The default condition id: the one the
	-- engine's own stair-hop delay uses (they merge, the longer one counts), and not the buff bar's "Pacified" row.
	local c = Condition(CONDITION_PACIFIED, CONDITIONID_DEFAULT)
	c:setParameter(CONDITION_PARAM_TICKS, ms)
	victim:addCondition(c)
	timer(victim, ID.subId.stunImmune, ms + cfgPvp.immuneMs)
	timer(victim, ID.subId.stunDr, cfgPvp.drWindowMs)
	addEvent(releaseIfOver, ms, id)
	if ChaosCasting and ChaosCasting.interrupt then
		pcall(ChaosCasting.interrupt, victim, "paralysed", "You were stunned: the spell is interrupted.")
	end
	local secs = string.format("%.1f", ms / 1000)
	victim:getPosition():sendMagicEffect(CONST_ME_STUN)
	if ChaosPack29Vfx then -- pair 29 (switch off: nothing): the stunned aura while it lasts
		pcall(ChaosPack29Vfx.hold, victim, "stunned", ms)
	end
	victim:say("Stunned!", TALKTYPE_MONSTER_SAY)
	victim:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(victim, "You are stunned for %s s by %s.", secs, monk:getName()))
	monk:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(monk, "%s is stunned for %s s.", victim:getName(), secs))
	pushBuffBar(victim)
end

-- a fallback if a release timer was lost (a script reload): the creature think frees a stun that is over
local stunThink = CreatureEvent("ChaosMonkStunThink")
function stunThink.onThink(creature, interval)
	local id = creature:getId()
	if not M.pvpStun[id] then
		creature:unregisterEvent("ChaosMonkStunThink")
	else
		releaseIfOver(id)
	end
	return true
end
stunThink:register()

local event = CreatureEvent("ChaosMonkCombat")
function event.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local ok, a, b = pcall(function()
		local p, s = onOffence(creature, attacker, primaryDamage, secondaryDamage, primaryType, origin)
		if creature:isPlayer() then
			p, s = onDefence(creature, attacker, p, s, primaryType, origin)
			-- Iron Palm on a player: the stun when its damage lands (not dodged, not fully warded)
			local monk = attacker and attacker:getPlayer()
			if monk and monk ~= creature and origin == ORIGIN_SPELL and primaryType == COMBAT_PHYSICALDAMAGE
					and math.abs(p) + math.abs(s) > 0 and math.abs(p) + math.abs(s) < creature:getHealth() then
				local chi = monk:getStorageValue(ID.storage.palmChi)
				if chi > 0 then
					monk:setStorageValue(ID.storage.palmChi, -1)
					stunPlayer(creature, monk, chi)
				end
			end
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
	if not creature or not target then
		return RETURNVALUE_NOERROR
	end
	if creature:isPlayer() then
		registerOnce(target, "ChaosMonkCombat")
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
	M.pvpStun[player:getId()] = nil
	return true
end
logout:register()

-- Shared helpers of the Monk line's spells (monk/ shadowfist/ ironsage/; docs/CLASSES.md).
-- Loaded by every Monk spell with: dofile('data/spells/scripts/chaos/_monk.lua')
-- The rules, numbers and ids are data/scripts/chaos/monk_chi_core.lua (ChaosMonk), loaded here into the spell Lua
-- state; chi is a player storage, so the spells and data/scripts/chaos/monk_combat.lua see the same value.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMonk then
	dofile('data/scripts/chaos/monk_chi_core.lua')
end
-- the class nodes of the passive tree (class_tree.lua: their flags, read from a player storage)
if not ChaosClassTree then
	dofile('data/scripts/chaos/class_tree.lua')
end
if MonkSpell then
	return
end

MonkSpell = {}
local M = ChaosMonk

local function itemAttack(item)
	local a = item:getAttribute(ITEM_ATTRIBUTE_ATTACK)
	if not a or a == 0 then
		a = ItemType(item:getId()):getAttack()
	end
	return a or 0
end

-- skill x attack of the Monk's strikes: a staff (any club) in hand uses the melee skill x its attack, otherwise the fists
-- (fist skill x the level-based fist attack, or a fist weapon's attack)
function MonkSpell.power(player)
	local fistWeapon = 0
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local wt = ItemType(item:getId()):getWeaponType()
			if wt == WEAPON_CLUB then
				return ChaosSpell.meleeSkillLevel(player) * math.max(20, itemAttack(item))
			end
			for _, id in ipairs(M.cfg.unarmed.fistWeapons) do
				if id == item:getId() then
					fistWeapon = math.max(fistWeapon, itemAttack(item))
				end
			end
		end
	end
	return M.fistPower(player:getLevel(), player:getEffectiveSkillLevel(SKILL_FIST), fistWeapon)
end

function MonkSpell.isAdjacent(a, b)
	local p, t = a:getPosition(), b:getPosition()
	return p.z == t.z and math.max(math.abs(p.x - t.x), math.abs(p.y - t.y)) <= 1
end

-- the target of a melee strike spell, or nil after a cancel message
function MonkSpell.meleeTarget(player, variant)
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
		return nil
	end
	if not MonkSpell.isAdjacent(player, target) then
		ChaosSpell.cancel(player, RETURNVALUE_TOOFARAWAY)
		return nil
	end
	if not ChaosSpell.canAttack(player, target) then
		ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
		return nil
	end
	return target
end

-- a Monk strike: physical damage, ORIGIN_SPELL (monk_combat.lua treats a Monk's spell damage as its strikes:
-- Pressure Points and the Shadowfist focus crit apply, no chi from it). f = ChaosMonk.formula.<name>
function MonkSpell.strike(player, target, f, scale, effect)
	if not ChaosSpell.canAttack(player, target) then
		return false
	end
	local min, max = M.strikeValues(player:getLevel(), MonkSpell.power(player), f, scale)
	return doTargetCombat(player, target, COMBAT_PHYSICALDAMAGE, -math.floor(min), -math.floor(max),
		effect or CONST_ME_HITAREA, ORIGIN_SPELL)
end

-- min, max for an area strike (doAreaCombat), same formula
function MonkSpell.values(player, f, scale)
	local min, max = M.strikeValues(player:getLevel(), MonkSpell.power(player), f, scale)
	return math.floor(min), math.floor(max)
end

-- A finisher takes all chi: returns the chi spent, or nil after a cancel message. A Shadowfist's finisher opens the
-- focus window (crit chance from the chi spent).
function MonkSpell.finisher(player)
	local spent, why = M.takeChi(player)
	if not spent then
		player:sendCancelMessage(why)
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return nil
	end
	if M.isShadowfist(player:getVocation():getId()) then
		player:setStorageValue(M.ids.storage.focusChi, spent)
		local c = Condition(CONDITION_ATTRIBUTES)
		c:setParameter(CONDITION_PARAM_SUBID, M.ids.subId.focus)
		c:setParameter(CONDITION_PARAM_TICKS, M.cfg.focus.durationMs)
		player:addCondition(c)
	end
	return spent
end

-- a timer condition (CONDITION_ATTRIBUTES without attributes) with a sub id
function MonkSpell.timer(creature, subId, ticks)
	local c = Condition(CONDITION_ATTRIBUTES)
	c:setParameter(CONDITION_PARAM_SUBID, subId)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	creature:addCondition(c)
end

function MonkSpell.hasTimer(creature, subId)
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
end

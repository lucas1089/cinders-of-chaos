-- Kindled Breath: breathe the chi in and heal; the heal grows with the chi spent.
--
-- Finisher (needs 1 chi). Monk and Shadowfist: heal yourself for (level x 2 + fist x 6) x the finisher scale.
-- Iron Sage (the line's healer): the most hurt party member within 5 sqm (yourself without a party, or when you are the
-- most hurt) for (level x 0.5 + fist x 27) x the finisher scale, and 60% more over 6 s (CONDITION_REGENERATION, sub id
-- ChaosMonk.ids.subId.breath). The Flowing Mercy keystone (the passive tree, class_tree.lua) also heals the next most
-- hurt for a share of it. Numbers: ChaosMonk.cfg.breath / sageBreath.
dofile('data/spells/scripts/chaos/_monk.lua')

local function inReach(player, other, r)
	local p, o = player:getPosition(), other:getPosition()
	return p.z == o.z and math.max(math.abs(p.x - o.x), math.abs(p.y - o.y)) <= r
end

-- party members within range (and the caster), most hurt first
local function hurtList(player, r)
	local list = {player}
	for _, c in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), r, false)) do
		if c:isPlayer() and c ~= player and c:getHealth() > 0 and inReach(player, c, r) then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b)
		local sa, sb = a:getHealth() / math.max(1, a:getMaxHealth()), b:getHealth() / math.max(1, b:getMaxHealth())
		if sa ~= sb then
			return sa < sb
		end
		return a:getId() < b:getId()
	end)
	return list
end

local function regen(target, tick)
	if tick <= 0 then
		return
	end
	local M = ChaosMonk
	local c = Condition(CONDITION_REGENERATION)
	c:setParameter(CONDITION_PARAM_SUBID, M.ids.subId.breath)
	c:setParameter(CONDITION_PARAM_TICKS, M.cfg.breath.hotTicks * 1000)
	c:setParameter(CONDITION_PARAM_HEALTHGAIN, tick)
	c:setParameter(CONDITION_PARAM_HEALTHTICKS, 1000)
	target:addCondition(c)
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local spent = MonkSpell.finisher(player)
	if not spent then
		return false
	end
	local M = ChaosMonk
	local fist = player:getEffectiveSkillLevel(SKILL_FIST)
	if not M.isIronSage(player:getVocation():getId()) then
		local heal = M.breathHeal(player:getLevel(), fist, spent, false)
		ChaosSpell.healTarget(player, player, heal, heal, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
		ChaosSpell.vfx(player:getPosition(), "chi_charge")
		return true
	end
	local heal, tick = M.sageBreathHeal(player:getLevel(), fist, spent)
	local list = hurtList(player, M.cfg.sageBreath.range)
	local target = list[1]
	ChaosSpell.healTarget(player, target, heal, heal, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
	regen(target, tick)
	if target ~= player then
		player:getPosition():sendDistanceEffect(target:getPosition(), CONST_ANI_SMALLHOLY)
	end
	ChaosSpell.vfx(target:getPosition(), "chi_charge")
	-- Flowing Mercy: the next most hurt gets a share of it too
	local share = ChaosClassTree.value(player, "ksFlowingMercy", "share")
	if share > 0 and list[2] then
		local second = math.floor(heal * share)
		ChaosSpell.healTarget(player, list[2], second, second, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
		regen(list[2], math.floor(tick * share))
	end
	return true
end

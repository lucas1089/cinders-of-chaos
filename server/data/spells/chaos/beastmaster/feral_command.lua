-- Feral Command: your companions leap at the target (range 7) and maul it, each for 1.5 bites at once.
--
-- The Beastmaster's command. A bite is physical damage dealt as you, from your level and distance skill
-- (ChaosClasses.biteValues, Chaos.classes.companion); it needs a companion out (Wild Bond).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	local cfg = Chaos.classes.companion
	local pack = {}
	for _, s in ipairs(player:getSummons()) do
		if s:isMonster() then
			local name = s:getName():lower()
			for _, n in ipairs(cfg.monsters) do
				if n:lower() == name then
					pack[#pack + 1] = s
				end
			end
		end
	end
	if #pack == 0 then
		return ChaosSpell.cancel(player, "You have no companion out. Call it with Wild Bond.")
	end
	local tpos = target:getPosition()
	local min, max = ChaosClasses.biteValues(player:getLevel(), player:getEffectiveSkillLevel(SKILL_DISTANCE))
	for _, s in ipairs(pack) do
		local spos = s:getPosition()
		if spos.z ~= tpos.z or math.max(math.abs(spos.x - tpos.x), math.abs(spos.y - tpos.y)) > 1 then
			local spots = ChaosSpell.freeAround(tpos, spos)
			if spots[1] then
				ChaosSpell.shoot(spos, spots[1].pos, "shadow_bolt", CONST_ANI_WHIRLWINDCLUB)
				s:teleportTo(spots[1].pos, true)
			end
		end
		s:setTarget(target)
		ChaosSpell.damageTarget(player, target, COMBAT_PHYSICALDAMAGE, min * cfg.mauls, max * cfg.mauls, CONST_ME_DRAWBLOOD)
	end
	target:getPosition():sendMagicEffect(CONST_ME_HITAREA)
	return true
end

-- Shuriken Barrage: a fan of shurikens at your target and up to 4 more monsters near it.
--
-- One ranged weapon strike each (shuriken power as Shuriken Toss) within 3 sqm of the target. Other players are only
-- hit when they are the spell's target.
dofile('data/spells/scripts/chaos/_common.lua')

local SCALE = 1.0
local EXTRA = 4
local RADIUS = 3

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
	local targets = {target}
	local tpos = target:getPosition()
	local around = ChaosSpell.enemiesAround(player, tpos, RADIUS)
	table.sort(around, function(a, b)
		local pa, pb = a:getPosition(), b:getPosition()
		return math.max(math.abs(pa.x - tpos.x), math.abs(pa.y - tpos.y)) < math.max(math.abs(pb.x - tpos.x), math.abs(pb.y - tpos.y))
	end)
	for _, m in ipairs(around) do
		if #targets > EXTRA then
			break
		end
		if m ~= target then
			targets[#targets + 1] = m
		end
	end
	local power = ChaosSpell.shurikenPower(player)
	local l = player:getLevel() / 5
	local min = (l + power * 0.050 + 20) * SCALE
	local max = (l + power * 0.080 + 40) * SCALE
	local from = player:getPosition()
	for _, t in ipairs(targets) do
		ChaosSpell.shoot(from, t:getPosition(), "shuriken", CONST_ANI_REDSTAR)
		ChaosSpell.weaponStrike(player, t, min, max, CONST_ME_DRAWBLOOD, ORIGIN_RANGED)
	end
	return true
end

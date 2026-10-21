-- Shuriken Tempest: Shuriken Barrage's late sibling. A storm of shurikens at your target and up to 8 more monsters within
-- 4 sqm of it, two ranged weapon strikes each, 0.5 s apart (shuriken power as Shuriken Toss, 1.1 times a Barrage strike).
-- 14 s cooldown (the cooldown ladder, 2026-10-20; was 30 s). Other players are only
-- hit when they are the spell's target.
dofile('data/spells/scripts/chaos/_common.lua')

local SCALE = 1.1
local EXTRA = 8
local RADIUS = 4
local GAP_MS = 500

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
	local ids = {}
	for _, t in ipairs(targets) do
		ids[#ids + 1] = t:getId()
	end
	local casterId = player:getId()
	local function wave()
		local p = Player(casterId)
		if not p then
			return
		end
		for _, id in ipairs(ids) do
			local t = Creature(id)
			if t and t:getHealth() > 0 and ChaosSpell.canAttack(p, t) then
				ChaosSpell.shoot(p:getPosition(), t:getPosition(), "shuriken", CONST_ANI_REDSTAR)
				ChaosSpell.weaponStrike(p, t, min, max, CONST_ME_DRAWBLOOD, ORIGIN_RANGED)
			end
		end
	end
	wave()
	addEvent(wave, GAP_MS)
	return true
end

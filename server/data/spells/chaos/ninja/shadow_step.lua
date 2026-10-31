-- Shadow Step: step through the shadows behind your target and stab it.
--
-- Teleports to the free tile around the target farthest from where the Ninja stood (range 5) and strikes it. A melee
-- weapon strike: the off-hand follows it when dual wielding, it crits out of Shadow Veil and carries Poison Blades.
dofile('data/spells/scripts/chaos/_common.lua')

local SCALE = 1.0

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
	local from = player:getPosition()
	local tpos = target:getPosition()
	local spots = ChaosSpell.freeAround(tpos, from, true)
	if #spots == 0 then
		return ChaosSpell.noRoom(player)
	end
	ChaosSpell.vfxOr(from, "shade_vanish", "shadow_smoke", CONST_ME_POFF)
	player:teleportTo(spots[1].pos)
	local p = player:getPosition()
	local dx, dy = tpos.x - p.x, tpos.y - p.y
	if math.abs(dx) >= math.abs(dy) then
		player:setDirection(dx > 0 and DIRECTION_EAST or DIRECTION_WEST)
	else
		player:setDirection(dy > 0 and DIRECTION_SOUTH or DIRECTION_NORTH)
	end
	ChaosSpell.vfxOr(spots[1].pos, "shade_appear", "shadow_smoke", CONST_ME_MORTAREA)
	local power = ChaosSpell.bladePower(player)
	local l = player:getLevel() / 5
	local min = (l + power * 0.075 + 30) * SCALE
	local max = (l + power * 0.120 + 60) * SCALE
	ChaosSpell.weaponStrike(player, target, min, max, CONST_ME_DRAWBLOOD, ORIGIN_MELEE)
	return true
end

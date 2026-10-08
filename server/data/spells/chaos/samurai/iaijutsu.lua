-- Iaijutsu: gather for a moment, then cut your target with one heavy draw strike.
--
-- The Samurai charges for 0.8 s, then strikes the target if it is still within 2 sqm. A melee weapon strike: it rolls
-- the Bushido Focus crit, crits out of Shadow Veil and carries Poison Blades.
dofile('data/spells/scripts/chaos/_common.lua')

local SCALE = 1.0
local CHARGE_MS = 800
local REACH = 2

local function strike(playerId, targetId)
	local player, target = Player(playerId), Creature(targetId)
	if not player or not target or target:getHealth() <= 0 then
		return
	end
	local p, t = player:getPosition(), target:getPosition()
	if p.z ~= t.z or math.max(math.abs(p.x - t.x), math.abs(p.y - t.y)) > REACH then
		p:sendMagicEffect(CONST_ME_POFF)
		return
	end
	local power = ChaosSpell.bladePower(player)
	local l = player:getLevel() / 5
	local min = (l + power * 0.20 + 60) * SCALE
	local max = (l + power * 0.30 + 120) * SCALE
	p:sendDistanceEffect(t, CONST_ANI_WHIRLWINDSWORD)
	ChaosSpell.fx(t, "ground_slam", CONST_ME_HITAREA)
	ChaosSpell.weaponStrike(player, target, min, max, CONST_ME_DRAWBLOOD, ORIGIN_MELEE)
end

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
	player:getPosition():sendMagicEffect(CONST_ME_YELLOWENERGY)
	addEvent(strike, CHARGE_MS, player:getId(), target:getId())
	return true
end

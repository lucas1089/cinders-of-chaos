-- Shadowfist Flurry: spend all chi on a flurry of blows at the target next to you: 2 + 1 per chi spent.
--
-- Finisher. One hit every 0.2 s while the target stays next to you; every hit is a Monk strike, so it crits in the
-- focus window this finisher opens (8% per chi spent, x1.5) and counts the target's Pressure Points.
dofile('data/spells/scripts/chaos/_monk.lua')

local function hit(playerId, targetId, left)
	local player, target = Player(playerId), Creature(targetId)
	if not player or not target or target:getHealth() <= 0 then
		return
	end
	if MonkSpell.isAdjacent(player, target) then
		player:getPosition():sendDistanceEffect(target:getPosition(), CONST_ANI_SMALLHOLY)
		MonkSpell.strike(player, target, ChaosMonk.formula.flurryHit, 1, CONST_ME_HITAREA)
	else
		if not ChaosSpell.vfx(target:getPosition(), "punch_hit_violet") then
			target:getPosition():sendMagicEffect(CONST_ME_POFF)
		end
	end
	if left > 1 then
		addEvent(hit, ChaosMonk.cfg.flurry.intervalMs, playerId, targetId, left - 1)
	end
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = MonkSpell.meleeTarget(player, variant)
	if not target then
		return false
	end
	local spent = MonkSpell.finisher(player)
	if not spent then
		return false
	end
	ChaosSpell.fx(player:getPosition(), "shadow_smoke", CONST_ME_MORTAREA)
	hit(player:getId(), target:getId(), ChaosMonk.flurryHits(spent))
	return true
end

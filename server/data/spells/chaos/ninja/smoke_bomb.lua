-- Smoke Bomb: a cloud of smoke around you blinds monsters for 3 seconds; they lose their target and are slowed.
--
-- 5x5 around the Ninja. Blinded monsters drop their target and cannot pick a player while it lasts (re-applied every
-- pulse), and are slowed 30%. Bosses (more than 50000 health) only lose their target once.
dofile('data/spells/scripts/chaos/_common.lua')

local RADIUS = 2
local BLIND_MS = 3000
local PULSE_MS = 250
local BOSS_HEALTH = 50000

-- the blindness is over: players in view go back on the monster's target list (the engine adds them again only when
-- they move or appear) and it looks for a target
local function wake(m)
	for _, p in ipairs(ChaosSpell.spectators(m:getPosition(), 7, true)) do
		if m:isOpponent(p) then
			m:addTarget(p)
		end
	end
	if m:isIdle() then
		m:setIdle(false)
	end
	if not m:getTarget() then
		m:searchTarget()
	end
end

local function blind(monsterId, left)
	local m = Monster(monsterId)
	if not m then
		return
	end
	if left <= 0 then
		wake(m)
		return
	end
	ChaosSpell.dropTarget(m, nil)
	addEvent(blind, PULSE_MS, monsterId, left - PULSE_MS)
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local pos = player:getPosition()
	for dx = -RADIUS, RADIUS do
		for dy = -RADIUS, RADIUS do
			if (dx + dy) % 2 == 0 then
				ChaosSpell.fx(Position(pos.x + dx, pos.y + dy, pos.z), "shadow_smoke", CONST_ME_POFF)
			end
		end
	end
	for _, m in ipairs(ChaosSpell.enemiesAround(player, pos, RADIUS)) do
		if m:getMaxHealth() > BOSS_HEALTH then
			ChaosSpell.dropTarget(m, nil)
		else
			ChaosSpell.slow(m, BLIND_MS, 0.3)
			blind(m:getId(), BLIND_MS)
		end
		m:getPosition():sendMagicEffect(CONST_ME_STUN)
	end
	return true
end

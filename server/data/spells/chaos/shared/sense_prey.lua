-- Hunter's Instinct: pings every monster within 12 sqm on the caster's floor (max 15 marked) and reports the nearest.
dofile('data/spells/scripts/chaos/_common.lua')

local RADIUS = 12
local MAX_MARKS = 15

local function compass(dx, dy)
	local ns = dy < 0 and "north" or (dy > 0 and "south" or "")
	local ew = dx < 0 and "west" or (dx > 0 and "east" or "")
	if ns ~= "" and ew ~= "" then
		return ns .. "-" .. ew
	end
	return ns .. ew
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local pos = player:getPosition()
	local found, nearest, nearestDist = 0, nil, nil
	for _, c in ipairs(ChaosSpell.spectators(pos, RADIUS)) do
		if c:isMonster() and not c:getMaster() then
			found = found + 1
			local p = c:getPosition()
			local dist = math.max(math.abs(p.x - pos.x), math.abs(p.y - pos.y))
			if not nearestDist or dist < nearestDist then
				nearest, nearestDist = c, dist
			end
			if found <= MAX_MARKS then
				ChaosSpell.fx(p, "arcane_circle", CONST_ME_MAGIC_BLUE)
			end
		end
	end

	ChaosSpell.fx(pos, "aura_ring", CONST_ME_MAGIC_BLUE)
	if found == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Hunter's Instinct: nothing stirs nearby.")
	else
		local np = nearest:getPosition()
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
			"Hunter's Instinct: %d creature%s nearby. Nearest: %s, %d sqm %s.",
			found, found == 1 and "" or "s", nearest:getName(), nearestDist, compass(np.x - pos.x, np.y - pos.y)))
	end
	return true
end

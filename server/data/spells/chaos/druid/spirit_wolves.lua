-- Moonfang Pack: summons 2 wolves (3 from level 200) for 40s. Tries "Spirit Wolf", "Winter Wolf", "Wolf" in that order.
dofile('data/spells/scripts/chaos/_common.lua')

local CANDIDATES = {"Spirit Wolf", "Winter Wolf", "Wolf"}
local DURATION = 40000
local MAX_SUMMONS = 4

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if player:getSkull() == SKULL_BLACK then
		return ChaosSpell.cancel(player)
	end

	local monsterName
	for _, name in ipairs(CANDIDATES) do
		if MonsterType(name) then
			monsterName = name
			break
		end
	end
	if not monsterName then
		return ChaosSpell.cancel(player, "No wolf monster is defined on this server.")
	end

	local want = player:getLevel() >= 200 and 3 or 2
	if #player:getSummons() + want > MAX_SUMMONS then
		return ChaosSpell.cancel(player, "You cannot summon more creatures.")
	end

	local free = ChaosSpell.freeAround(player:getPosition(), player:getPosition())
	local created = 0
	for i = 1, #free do
		if created >= want then
			break
		end
		local wolf = Game.createMonster(monsterName, free[i].pos)
		if wolf then
			ChaosSpell.bindSummon(player, wolf) -- an ally of its owner: no target of its own from the start
			wolf:registerEvent("ChaosCompanionGuard") -- the owner's area spells and its other summons do not hurt it
			ChaosSpell.vfxOr(free[i].pos, "teleport_in", "summon_portal", CONST_ME_TELEPORT)
			addEvent(ChaosSpell.removeLater, DURATION, wolf:getId())
			created = created + 1
		end
	end
	if created == 0 then
		return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
	end
	ChaosSpell.buffTimer(player, ChaosSpell.SUBID.moonfang_pack, DURATION) -- the buff bar's timer
	ChaosSpell.fx(player:getPosition(), "summon_portal", CONST_ME_MAGIC_GREEN)
	return true
end

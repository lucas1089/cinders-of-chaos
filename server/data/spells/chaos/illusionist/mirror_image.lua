-- Hall of Mirrors: up to 3 decoys wearing the caster's outfit, they vanish after 10s.
-- Needs the "Clone" monster (data/monster/lua/clones/clone.lua in the reference server).
dofile('data/spells/scripts/chaos/_common.lua')

local DURATION = 10000
local COPIES = 3

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if not MonsterType("Clone") then
		return ChaosSpell.cancel(player, "The mirror image needs the Clone monster.")
	end
	local pos = player:getPosition()
	local spots = ChaosSpell.freeAround(pos, pos)
	local made = 0
	for i = 1, math.min(COPIES, #spots) do
		local clone = Game.createMonster("Clone", spots[i].pos)
		if clone then
			clone:setOutfit(player:getOutfit())
			clone:rename(player:getName())
			clone:setMaster(player)
			ChaosSpell.fx(spots[i].pos, "summon_portal", CONST_ME_MAGIC_BLUE)
			addEvent(ChaosSpell.removeLater, DURATION, clone:getId())
			made = made + 1
		end
	end
	if made == 0 then
		return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
	end
	ChaosSpell.fx(pos, "arcane_circle", CONST_ME_MAGIC_BLUE)
	return true
end

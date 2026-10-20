-- Hall of Mirrors: up to 3 decoys wearing the caster's outfit, they vanish after 10s.
-- Needs the "Clone" monster (data/monster/lua/clones/clone.lua in the reference server).
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosMysticFx then
	pcall(dofile, 'data/lib/chaos_mystic_fx.lua')
end

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
			ChaosSpell.bindSummon(player, clone)
			-- each clone: the sigil (class swap chaos_class_fx.lua: arcane_sigil -> illusion_mirror, the mirror panes)
			if not ChaosSpell.vfx(spots[i].pos, "arcane_sigil") then
				ChaosSpell.fx(spots[i].pos, "summon_portal", CONST_ME_MAGIC_BLUE)
			end
			addEvent(ChaosSpell.removeLater, DURATION, clone:getId())
			made = made + 1
		end
	end
	if made == 0 then
		return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
	end
	ChaosSpell.buffTimer(player, ChaosSpell.SUBID.mirror_image, DURATION) -- the buff bar's timer
	-- the caster: runes orbiting it (pack arcane_orbit; server/data/spells/README_FX.md "Mystic line effects")
	if not (ChaosMysticFx and ChaosMysticFx.send(pos, "arcane_orbit")) then
		ChaosSpell.vfxOr(pos, "arcane_sigil", "arcane_circle", CONST_ME_MAGIC_BLUE)
	end
	return true
end

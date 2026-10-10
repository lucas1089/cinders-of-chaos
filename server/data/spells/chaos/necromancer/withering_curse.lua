-- Withering Curse: curse the target (range 6) for 12 s: it takes 15% more damage from everyone and rots (death
-- damage every second, 10 ticks). The Lich's curse amplifies by 25%, rots harder and also curses up to 2 more
-- enemies within 2 sqm of the target.
--
-- On a player the curse only rots (no amplify). The amplify is applied by data/scripts/chaos/necromancer_combat.lua
-- (ChaosNecroCurse); numbers: necro_config.lua witheringCurse.
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local classKey = NecroSpell.class(player)
	if not classKey then
		return false
	end
	local target = NecroSpell.target(player, variant)
	if not target then
		return false
	end
	local w = NecroSpell.cfg.witheringCurse
	ChaosSpell.vshoot(player:getPosition(), target:getPosition(), "shadow_orb", "skull_orb", CONST_ANI_DEATH)
	ChaosSpell.vfx(target:getPosition(), "cursed")
	NecroSpell.curse(player, classKey, target)
	local more = w.spread[classKey] or 0
	if more > 0 then
		more = more + ChaosClassTree.value(player, "ctSpreadingBlight", "spread") -- the passive tree (Lich)
		local tpos = target:getPosition()
		for _, e in ipairs(ChaosNecro.enemiesAround(player, tpos, w.spreadRadius, false)) do
			if more <= 0 then
				break
			end
			if e ~= target then
				ChaosSpell.shoot(tpos, e:getPosition(), "skull_orb", CONST_ANI_DEATH)
				NecroSpell.curse(player, classKey, e)
				more = more - 1
			end
		end
	end
	return true
end

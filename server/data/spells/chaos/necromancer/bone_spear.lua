-- Bone Spear: hurl a spear of bone at the target (range 5). Physical damage; the creature right behind the target
-- (seen from you) takes half of it. The Necromancer line's filler.
--
-- (level / 5 + magic level x 1.6..2.6 + 20..40) x the line's level scale (necro_config.lua boneSpear, levelScale);
-- the Lich's Soul Hoard adds to it.
dofile('data/spells/scripts/chaos/_necro.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if not NecroSpell.class(player) then
		return false
	end
	local target = NecroSpell.target(player, variant)
	if not target then
		return false
	end
	local L, f = ChaosNecro, NecroSpell.cfg.boneSpear
	local min, max = L.values(player, f)
	local ppos, tpos = player:getPosition(), target:getPosition()
	ChaosSpell.vshoot(ppos, tpos, "bone_spear", "bone_spear", CONST_ANI_ETHEREALSPEAR) -- our bone spear (chaos_vfx_art.lua)
	NecroSpell.fx(tpos, {"necro_spear_hit", "bone_spear"}) -- it splinters on the target
	local dealt = L.damage(player, target, COMBAT_PHYSICALDAMAGE, min, max, CONST_ME_HITAREA, ORIGIN_SPELL)
	-- the tile behind the target, one step further along the line from the caster
	local dx, dy = tpos.x - ppos.x, tpos.y - ppos.y
	local sx = dx == 0 and 0 or (dx > 0 and 1 or -1)
	local sy = dy == 0 and 0 or (dy > 0 and 1 or -1)
	local behind = Position(tpos.x + sx, tpos.y + sy, tpos.z)
	local tile = Tile(behind)
	local other = tile and tile:getTopCreature()
	if other and other ~= target and (ChaosSpell.isEnemy(player, other) or other:isPlayer()) then
		local v = math.max(1, math.floor((dealt > 0 and dealt or (min + max) / 2) * f.pierce))
		L.damage(player, other, COMBAT_PHYSICALDAMAGE, v, v, CONST_ME_HITAREA, ORIGIN_SPELL)
	end
	return true
end

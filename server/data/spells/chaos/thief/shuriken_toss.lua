-- Shuriken Toss: throw a shuriken at one target; physical damage from your sword or distance skill.
--
-- The Thief's filler (range 5). A ranged weapon strike: the better of sword and distance skill x a default shuriken attack
-- (no star is carried; a one-handed distance weapon in hand raises it), so it works with a blade in hand too. It crits out of Shadow Veil and carries Poison Blades.
dofile('data/spells/scripts/chaos/_common.lua')

-- Damage scale per class (server vocation id). Cooldown 2 s since the rotation pass (2026-10-14; was 3 s at x2.0, a
-- 1 s window every cast with the snares out of the presets): the scale keeps each class's spell damage within 5% of
-- the 3 s kit (server/data/spells/README.md "Rotations"; read by server/tools/rotation_sim.py). Thief 4/3 of the old
-- x2.0 per cast; the Ninja and the Samurai share the attack group with their big strikes, so they keep more per cast
-- once those come: Ninja x1.62 from Shuriken Barrage (level 180), Samurai x1.5 from Iaijutsu (level 120).
local SCALE = {[11] = 1.33, [12] = 1.62, [13] = 1.5}
local EARLY = {[12] = {below = 180, scale = 1.33}, [13] = {below = 120, scale = 1.33}}
local DEFAULT_SCALE = 1.33

local function scaleFor(player)
	local voc = player:getVocation():getId()
	local early = EARLY[voc]
	if early and player:getLevel() < early.below then
		return early.scale
	end
	return SCALE[voc] or DEFAULT_SCALE
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
	local power = ChaosSpell.shurikenPower(player)
	local l = player:getLevel() / 5
	local scale = scaleFor(player)
	local min = (l + power * 0.050 + 20) * scale
	local max = (l + power * 0.080 + 40) * scale
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "shuriken", CONST_ANI_REDSTAR)
	ChaosSpell.weaponStrike(player, target, min, max, CONST_ME_DRAWBLOOD, ORIGIN_RANGED)
	return true
end

-- Rampage Leap: Leap next to the target (range 6) and bring the two-handed weapon down: heavy physical damage to
-- everything in a 5x5 square around the target (about 1.6 times Skyfall Cleave per hit), from weapon attack and skill;
-- every hit gets Rage; the slam staggers (50% slow, 2.5 s). 10 s cooldown.
-- Skyfall Cleave's late sibling. Rage: data/scripts/chaos/berserker_combat.lua.
-- Cooldown ladder, 2026-10-20: 14 s, was 18 s; O176, 2026-10-24: 10 s.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("ground_slam", CONST_ME_GROUNDSHAKER))
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setParameter(COMBAT_PARAM_USECHARGES, true)
combat:setArea(createCombatArea(AREA_CIRCLE2X2))

function onGetFormulaValues(player, skill, attack, factor)
	local min = ((player:getLevel() / 5) + (skill * attack * 0.095) + 40)
	local max = ((player:getLevel() / 5) + (skill * attack * 0.165) + 80)
	return -min, -max
end

function onRampageTarget(creature, target)
	ChaosSpell.slow(target, 2500, 0.5)
	return true
end

combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onRampageTarget")

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
	local from = player:getPosition()
	local tpos = target:getPosition()
	if math.max(math.abs(from.x - tpos.x), math.abs(from.y - tpos.y)) > 1 then
		local spots = ChaosSpell.freeAround(tpos, from)
		if #spots == 0 then
			return ChaosSpell.noRoom(player)
		end
		from:sendMagicEffect(CONST_ME_POFF)
		player:teleportTo(spots[1].pos)
		ChaosSpell.shoot(from, spots[1].pos, "blood_spear", CONST_ANI_WHIRLWINDAXE)
	end
	ChaosSpell.vfxDir(tpos, "heavy_cleave", ChaosSpell.dirTo(player:getPosition(), tpos))
	-- the class effect on the slammed spot (server/README.md "Class signature effects"): the combat's own effect id is
	-- fixed when the script loads, outside any cast, so the swap is asked here
	local cls = not ChaosSpell.skinned("fx", "ground_slam") and ChaosSpell.classFx("ground_slam")
	if cls and Vfx then
		Vfx(Position(tpos), cls)
	end
	return combat:execute(player, Variant(tpos))
end

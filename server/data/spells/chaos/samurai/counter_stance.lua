-- Counter Stance: for 3 seconds the next melee hit you take is parried and answered with a strike, every other hit
-- you take is 30% smaller, and the monsters within 3 sqm turn on you (the Samurai is the line's duelist off-tank).
--
-- The answer does 1.5x the parried hit (Chaos.classes.counter; done by data/scripts/chaos/thief_combat.lua, which sees
-- the stance as a condition with the class sub id).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = Chaos.classes
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId.counter)
	-- Iron Parry (passive tree, class_tree.lua): the stance lasts longer
	local extra = ChaosClassTree and ChaosClassTree.value(player, "ctIronParry", "windowMs") or 0
	c:setParameter(CONDITION_PARAM_TICKS, cfg.counter.windowMs + extra)
	player:addCondition(c)
	-- the duelist's challenge: the monsters around turn on the Samurai
	local r = cfg.counter.tauntRadius or 0
	if r > 0 then
		for _, m in ipairs(Game.getSpectators(player:getPosition(), false, false, r, r, r, r) or {}) do
			if m:isMonster() and not m:getMaster() and m:getTarget() ~= player then
				m:selectTarget(player)
			end
		end
	end
	if not ChaosSpell.vfx(player:getPosition(), "shield_bubble") then
		player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
	end
	return true
end

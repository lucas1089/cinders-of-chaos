-- Pressure Points: strike a nerve of the target next to you: 1 chi, and a stack of Pressure Points on it (+5% damage from Monks, up to 5 stacks, 8 s).
--
-- Each stack (max 5, 8 s, refreshed by every cast) makes the target take +5% from Monks' hits and strikes. The stacks
-- are timer conditions on the target, one sub id per stack (ChaosMonk.ids.subId.pressure), which
-- data/scripts/chaos/monk_combat.lua counts.
dofile('data/spells/scripts/chaos/_monk.lua')

local function addStack(target)
	local M = ChaosMonk
	local subs, present = M.ids.subId.pressure, {}
	for i, sub in ipairs(subs) do
		present[i] = MonkSpell.hasTimer(target, sub)
		if present[i] then
			MonkSpell.timer(target, sub, M.cfg.pressure.durationMs) -- refresh
		end
	end
	local slot = M.pressureSlot(present)
	if slot then
		MonkSpell.timer(target, subs[slot], M.cfg.pressure.durationMs)
	end
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = MonkSpell.meleeTarget(player, variant)
	if not target then
		return false
	end
	-- the stack first, so this strike already counts it
	addStack(target)
	ChaosSpell.fx(target:getPosition(), "void_eye", CONST_ME_MAGIC_RED)
	ChaosSpell.vfx(target:getPosition(), "punch_hit_violet")
	MonkSpell.strike(player, target, ChaosMonk.formula.pressurePoints, 1, CONST_ME_HITAREA)
	ChaosMonk.addChi(player, ChaosMonk.cfg.chi.pressurePoints)
	return true
end

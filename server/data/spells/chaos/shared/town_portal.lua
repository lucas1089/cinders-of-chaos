-- Town Portal: every class, from level 1, no mana. A 3 s channel, then a portal home and a return portal beside
-- the temple; all rules, the cooldown and the portal styles are in data/scripts/chaos/townportal.lua.
-- The XML cooldown is only a short guard: the real cooldown (60 s) starts when the portal opens.
function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player or not ChaosTownPortal or not ChaosTownPortal.cast then
		return false
	end
	return ChaosTownPortal.cast(player, "spell")
end

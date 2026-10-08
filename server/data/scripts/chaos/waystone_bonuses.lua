-- waystone_bonuses.lua: the waystone character upgrade "Experience" (base server,
-- data/scripts/customs/waystone_system/character_upgrades.lua) only wrote its level into storage 405788 and
-- nothing read it. Its own comment: "EXP is base 1.00, so each level adds 0.01 to the multiplier, so 100 levels
-- will be 2.00". This applies it to experience from monsters.
-- The "Loot" and "Rarity" upgrades (405789, 405790) are applied in the base loot callback by
-- server/tools/patch_base_events.py. Needs the experience dispatch from that tool too (see server/README.md).
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosWaystone = ChaosWaystone or {}
ChaosWaystone.experienceStorage = 405788
ChaosWaystone.perLevel = 0.01
ChaosWaystone.maxLevel = 100 -- the upgrade's own maximum (x2.0)

-- experience multiplier for an upgrade level (pure, testable)
function ChaosWaystone.experienceMultiplier(level)
	level = math.max(0, math.min(tonumber(level) or 0, ChaosWaystone.maxLevel))
	return 1 + level * ChaosWaystone.perLevel
end

local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if source and source:isMonster() then
		local mult = ChaosWaystone.experienceMultiplier(self:getStorageValue(ChaosWaystone.experienceStorage))
		if mult ~= 1 then
			return math.floor(exp * mult)
		end
	end
	return exp
end
xpCb:register()

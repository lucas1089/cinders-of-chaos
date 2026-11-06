-- attack_pace.lua: skill training does not jump with the lower base attack intervals (O429, server/README.md "Attack speed
-- cap"). Every swing or shot is one skill try, so a vocation that swings 1.5x as often would train 1.5x as fast. The tries of
-- weapon use (fist, sword, club, axe, distance) are cut by the vocation's new / old base interval (attack_rate_core.lua
-- trainFactor); exercise weapons (a charge is not a swing, exercise_training.lua sets Chaos.exerciseTries around its tries)
-- and shielding are left alone. An EventCallback onGainSkillTries at index 3: after the melee reroute (2), before the
-- training multipliers (5). Lua 5.1 / LuaJIT compatible.

if not ChaosAttackRate then
	dofile("data/scripts/chaos/attack_rate_core.lua")
end
local AR = ChaosAttackRate

local carry = {} -- [player id] = {carry}: a fraction of a try per player (a few bytes each, kept until restart)

local cb = EventCallback
cb.onGainSkillTries = function(self, skill, tries)
	if not tries or tries <= 0 or skill > 4 or (Chaos and Chaos.exerciseTries) then
		return tries
	end
	local voc = self:getVocation()
	if not voc then
		return tries
	end
	local f = AR.trainFactor(voc:getId(), voc:getAttackSpeed())
	if f >= 1 then
		return tries
	end
	local pid = self:getId()
	carry[pid] = carry[pid] or {}
	return AR.trainTries(carry[pid], tries, f)
end
cb:register(3)

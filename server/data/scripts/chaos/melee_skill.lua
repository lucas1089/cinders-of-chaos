-- melee_skill.lua: the training half of ONE melee skill (owner debug item 46; rules: melee_skill_core.lua, tests:
-- tests/melee_skill_test.lua; server/README.md "One melee skill"). A try of the sword, club or axe skill is credited to
-- the best of the three instead, so a character has one melee skill that grows whichever melee weapon it swings, and the
-- weaker two stay where saved characters left them (nothing is lost; the hit already uses the best, weapon_styles.lua).
-- An EventCallback onGainSkillTries at index 2: after the class lock (1, which zeroes the tries of a locked character),
-- before the training multipliers (shop_services.lua 5) and the island guard (1000), which then see the rerouted tries
-- once, from the call below, and a zero from the original call. Lua 5.1 / LuaJIT compatible.

if not ChaosMeleeSkill then
	dofile("data/scripts/chaos/melee_skill_core.lua")
end
local MS = ChaosMeleeSkill

local SKILL_NAME = {[SKILL_SWORD] = "sword", [SKILL_CLUB] = "club", [SKILL_AXE] = "axe"}
local SKILL_ID = {sword = SKILL_SWORD, club = SKILL_CLUB, axe = SKILL_AXE}

local rerouting = false -- the call below goes through this same chain

local cb = EventCallback
cb.onGainSkillTries = function(self, skill, tries)
	if rerouting or not tries or tries <= 0 or not SKILL_NAME[skill] then
		return tries
	end
	local levels, percents = {}, {}
	for name, id in pairs(SKILL_ID) do
		levels[name] = self:getSkillLevel(id)
		percents[name] = self:getSkillPercent(id)
	end
	local target = MS.routeTarget(SKILL_NAME[skill], levels, percents)
	if not target then
		return tries
	end
	rerouting = true
	local ok, err = pcall(self.addSkillTries, self, SKILL_ID[target], tries)
	rerouting = false
	if not ok then
		print("[ChaosMeleeSkill] " .. tostring(err))
		return tries
	end
	return 0
end
cb:register(2)

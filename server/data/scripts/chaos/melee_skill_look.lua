-- melee_skill_look.lua: the look text of equipment says one melee skill (server/README.md "Melee and Ranged on
-- equipment"): "melee +2" for the engine's "club fighting +2, sword fighting +2, axe fighting +2", "ranged" for
-- "distance fighting" (melee_skill_core.lua M.lookText).
if not ChaosMeleeSkill or not ChaosMeleeSkill.lookText then
	dofile("data/scripts/chaos/melee_skill_core.lua")
end
local K = ChaosMeleeSkill

local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing.isItem and thing:isItem() then
		local ok, text = pcall(K.lookText, description)
		if ok and type(text) == "string" then
			description = text
		end
	end
	return description
end
-- after the base default_onLook (0), the salvage line (120) and the charges (125)
look:register(126)

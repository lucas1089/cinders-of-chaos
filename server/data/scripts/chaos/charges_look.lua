-- charges_look.lua: Look text of an item with charges (amulets, rings, exercise weapons) says how many it has left,
-- even when its items.xml entry lacks showcharges (charges_look_core.lua). Not stackable items only.
if not ChaosChargesLook then
	dofile("data/scripts/chaos/charges_look_core.lua")
end
local K = ChaosChargesLook

local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing.isItem and thing:isItem() then
		local ok, text = pcall(function()
			local it = ItemType(thing:getId())
			if it:isStackable() then
				return description
			end
			return K.append(description, thing:getCharges(), it:getCharges())
		end)
		if ok then
			description = text
		end
	end
	return description
end
-- after the base default_onLook (0) and the salvage line (120)
look:register(125)

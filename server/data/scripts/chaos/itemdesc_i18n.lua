-- itemdesc_i18n.lua: Look at an item: its description line in the player's language (itemdesc_i18n_core.lua).
-- English players see the description as before. Text with no pt-BR entry stays English.
if not ChaosItemDescI18n then
	dofile("data/scripts/chaos/itemdesc_i18n_core.lua")
end
local D = ChaosItemDescI18n

-- the description of the item: the attribute a script wrote, else the one of its item type (items.xml)
local function rawDescription(item)
	local ok, text = pcall(function()
		local d = item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
		if type(d) == "string" and d ~= "" then
			return d
		end
		return ItemType(item:getId()):getDescription()
	end)
	return ok and type(text) == "string" and text or nil
end

local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if not (thing and thing.isItem and thing:isItem() and Chaos and Chaos.lang and Chaos.tx) then
		return description
	end
	if Chaos.lang(self) == "en" then
		return description
	end
	local raw = rawDescription(thing)
	if not raw then
		return description
	end
	local ok, text = pcall(D.apply, description, raw, function(t)
		return Chaos.tx(self, t)
	end, ChaosUniqueDescPt)
	return ok and text or description
end
-- after the base default_onLook (0), the salvage line (120) and the charges line (125)
look:register(130)

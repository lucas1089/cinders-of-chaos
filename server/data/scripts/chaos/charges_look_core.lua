-- charges_look_core.lua: the "It has N charges left." line of the Look text, for items with charges whose engine
-- description does not show them (the engine prints the charges only for a type with showcharges="1", so a Stone Skin
-- or Protection amulet showed none: owner debug item 80). Pure Lua (tests/charges_look_test.lua). charges_look.lua hooks it.
ChaosChargesLook = ChaosChargesLook or {}
local K = ChaosChargesLook

-- the engine's own wording is "... that has N charges left" / "It has N charges left": nothing is added when the text has it
function K.alreadyShown(description)
	return type(description) == "string" and description:lower():find("charges? left", 1) ~= nil
end

function K.line(charges, typeCharges)
	charges, typeCharges = tonumber(charges), tonumber(typeCharges)
	if not charges or charges <= 0 or not typeCharges or typeCharges <= 0 then
		return nil
	end
	local text = string.format("It has %d charge%s left", charges, charges == 1 and "" or "s")
	if typeCharges > charges then
		text = text .. string.format(" (of %d)", typeCharges)
	end
	return text .. "."
end

-- description + the charges line (a new line), or the description unchanged
function K.append(description, charges, typeCharges)
	description = description or ""
	if K.alreadyShown(description) then
		return description
	end
	local line = K.line(charges, typeCharges)
	if not line then
		return description
	end
	return description .. "\n" .. line
end

return K

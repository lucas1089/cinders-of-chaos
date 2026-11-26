-- star_inlay_core.lua: pure logic the three base star scripts call (server/README.md "Star inlay stones", O181).
-- Plain table, loaded with  local StarInlay = dofile("data/scripts/chaos/star_inlay_core.lua")  (the lines that
-- server/tools/patch_star_inlay.py puts into data/scripts/customs/tier_system/*.lua). Lua 5.1 / LuaJIT / 5.3.
--
-- The base system (README "Star inlay stones" has the item ids): a plain Skeletal, Netherwave, Ironwrath, Blightwoven or
-- Ashborne piece turns into its empty-star twin with a Star Inlay Stone; a Common .. Legendary stone of 1, 2 or 3 stars
-- turns the empty-star twin into the star variant (+1 to +3 armour, absorbs and speed by tier); the Star Extractor
-- turns a star variant back and gives the stone. The scripts swap the item id with item:transform, so every custom
-- attribute (item level, rarity, modifiers, sockets) stays.
-- Two faults of the stock scripts are fixed here:
--   1. the stone wrote the item type's description over the item's own description attribute, which holds the rolled
--      "Item Level: N. modifiers" text of the Chaos crafting (and the socket line): refine() keeps it and adds the line;
--   2. the stone and the extractor change the item type while the piece is worn, but the equip events added the old
--      type's speed and skills: taking it off took the new type's away (drift), so a worn piece is refused.

local K = {}

K.REFINED = "Refined by "
K.WORN_TEXT = "Take it off first: its stars change what it gives."

-- an item the player wears has the position {x = 65535, y = slot 1 .. 16}; one in a container has y = 64 + the
-- container's number, one on the ground a map position
function K.isWorn(pos)
	return type(pos) == "table" and pos.x == 65535 and type(pos.y) == "number" and pos.y >= 1 and pos.y < 64
end

-- the description without a "Refined by <name>." line (the text before it keeps its own line breaks)
function K.stripRefined(text)
	text = tostring(text or "")
	local out = text:gsub("[ \t\r]*\nRefined by [^\n]*", "")
	out = out:gsub("^Refined by [^\n]*\n?", "")
	return out
end

-- a tier line of the star items' type descriptions ("Tier I ( 3 Star )", "No Tier ( Empty Stars )"): the type's text,
-- copied by refine(), never the item's own
function K.isTierLine(line)
	line = tostring(line or "")
	return line:match("^%s*No Tier %b()%s*$") ~= nil or line:match("^%s*Tier [IVX]+ %b()%s*$") ~= nil
end

-- the item's own text: the description without the "Refined by" line and without a copied tier line. O181 seen in a
-- client (2026-11-26, V22): the extractor left "Tier I ( 3 Star )" on the empty-star piece, so its Look named the old
-- tier, and the next stone kept that line as own text and the new variant named the old tier too.
function K.ownText(text)
	local kept = {}
	for line in (K.stripRefined(text) .. "\n"):gmatch("([^\n]*)\n") do
		if not K.isTierLine(line) then
			kept[#kept + 1] = line
		end
	end
	return (table.concat(kept, "\n"):gsub("%s+$", ""))
end

-- the new description after a stone: the item's own text (a rolled "Item Level: N. ..." line stays), else the type's
-- description (the tier line of the star variant), and one "Refined by <name>." line
function K.refine(old, typeDescription, name)
	local base = K.ownText(old)
	if base == "" then
		base = tostring(typeDescription or "")
	end
	local line = K.REFINED .. tostring(name) .. "."
	if base == "" then
		return line
	end
	return base .. "\n" .. line
end

-- the engine side: write the refined description on `item` (an item userdata, or a mock with the same methods)
function K.refineItem(item, typeDescription, name)
	local ok, old = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION) end)
	local text = K.refine(ok and old or "", typeDescription, name)
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
	return text
end

-- the extractor: the "Refined by" line and the copied tier line go (a stale line told the wrong tier on the empty-star
-- piece); an own description that holds nothing else goes too, so the piece shows its type's text again. Returns true
-- when it changed the item.
function K.unrefineItem(item)
	local ok, old = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION) end)
	if not ok or type(old) ~= "string" or not old:find(K.REFINED, 1, true) then
		return false
	end
	local text = K.ownText(old)
	if text == "" then
		item:removeAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
	else
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
	end
	return true
end

-- the clean-up of pieces from before the V22 fix (owner 2026-11-26, "8 faça a limpeza"; star_inlay_clean.lua walks a
-- character once at login and cleans every item withdrawn from the stash). A piece the old extractor handled keeps the
-- copied "Tier I ( 3 Star )" line in its own description, and a piece stoned again after that named the old tier.

-- the name of the last "Refined by <name>." line of a description, or nil
function K.refinedName(text)
	local name
	for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
		local n = line:match("^%s*Refined by (.-)%.?%s*$")
		if n and n ~= "" then
			name = n
		end
	end
	return name
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- the description a piece should carry, from its own description and its item type's description (the current tier
-- line of a star variant, "No Tier ( Empty Stars )" of an empty-star twin). A tier line that is not the type's goes; the
-- type's own tier line stays (once). A refined piece left with no text of its own gets the type's text back, as refine()
-- writes it. Returns the new text ("" = remove the attribute) and whether it changed; a description without a tier
-- line is never touched.
function K.cleanText(text, typeDescription)
	if type(text) ~= "string" or text == "" then
		return text, false
	end
	local any = false
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		if K.isTierLine(line) then
			any = true
			break
		end
	end
	if not any then
		return text, false
	end
	local current = {}
	for line in (tostring(typeDescription or "") .. "\n"):gmatch("([^\n]*)\n") do
		if K.isTierLine(line) then
			current[trim(line)] = true
		end
	end
	local kept, seen = {}, {}
	for line in (K.stripRefined(text) .. "\n"):gmatch("([^\n]*)\n") do
		if not K.isTierLine(line) then
			kept[#kept + 1] = line
		elseif current[trim(line)] and not seen[trim(line)] then
			seen[trim(line)] = true
			kept[#kept + 1] = line
		end
	end
	local body = (table.concat(kept, "\n"):gsub("%s+$", ""))
	local name = K.refinedName(text)
	local out = body
	if name then
		-- as refine() writes it, but the type's tier line kept above stays where it was
		if out == "" then
			out = tostring(typeDescription or "")
		end
		local line = K.REFINED .. name .. "."
		out = out == "" and line or (out .. "\n" .. line)
	end
	return out, out ~= text
end

-- the engine side of cleanText on one item (an item userdata, or a mock with the same methods). Returns true when it
-- changed the item.
function K.cleanItem(item, typeDescription)
	local ok, old = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION) end)
	if not ok or type(old) ~= "string" then
		return false
	end
	local text, changed = K.cleanText(old, typeDescription)
	if not changed then
		return false
	end
	if text == "" then
		item:removeAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
	else
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
	end
	return true
end

-- the refusal for a worn piece, in the player's language when Chaos.t is loaded
function K.refuseWorn(player)
	local text = K.WORN_TEXT
	if Chaos and Chaos.t then
		text = Chaos.t(player, text)
	end
	player:sendCancelMessage(text)
	return true
end

return K

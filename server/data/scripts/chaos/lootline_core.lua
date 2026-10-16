-- One loot line per kill (server/README.md "One loot line per kill"): the rules, no engine calls (lootline.lua is the
-- engine side; server/tests/lootline_test.lua). Playtest 2026-10-16: a kill printed three lines, the stock "Loot of
-- <monster>: <items>" (default_onDropLoot.lua), "Chaos bonus loot of <monster>: <items>" (loot.lua) and "Looted:
-- <items> (<pouch notes>)." (pouches.lua). Now they are one line:
--   "Loot of a dragon: 120 gold coins, a dragon ham, 2 ember shards, {Ashbringer}. Looted: 120 gold coins,
--    {Ashbringer} (2 to your backpack)."
-- The stock part comes first and keeps its "Loot of" start (the client's loot colouring and short numbers read loot
-- messages by their mode; the stock prefix stays), the Chaos bonus items join its list (uniques and rare items keep
-- their {} highlight), and the pouch part (what the pouches and the Loot Bag took, their notes) ends the line. The
-- pouch part is the owner's own: in a party the other members get the line without it.
-- Each recipient reads the fixed parts in their language (t = Chaos.t bound to the recipient: "Loot of %s: %s",
-- "nothing", ...; pt-BR in i18n_strings.lua); item and monster names stay as the engine gives them. The stock line is
-- read in English (the engine writes it so); the client's loot colouring keys on the message mode and the {} marks,
-- not on the words, so the translated prefix keeps it working.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosLootLineCore = ChaosLootLineCore or {}
local K = ChaosLootLineCore

K.PREFIX = "Loot of "

-- a stock loot line ("Loot of <monster>: <items>")
function K.isStockLine(text)
	return type(text) == "string" and text:sub(1, #K.PREFIX) == K.PREFIX and text:find(": ", #K.PREFIX + 1, true) ~= nil
end

-- "Loot of a dragon: 120 gold coins" -> "a dragon", "120 gold coins"
function K.split(text)
	if not K.isStockLine(text) then
		return nil, nil
	end
	local at = text:find(": ", #K.PREFIX + 1, true)
	return text:sub(#K.PREFIX + 1, at - 1), text:sub(at + 2)
end

local function trimDot(s)
	return (s:gsub("%s+$", ""):gsub("%.$", ""))
end

function K.english(pattern, ...)
	if select("#", ...) == 0 then
		return pattern
	end
	return string.format(pattern, ...)
end

-- the stock "nothing" texts the recipient's language has a key for
local NOTHING = {["nothing"] = true, ["nothing (due to low stamina)"] = true}

-- rec = {stock = the stock line or nil, monster = the monster's name description (used without a stock line),
-- bonus = {item texts of the Chaos loot layer}, pouch = the pouch line ("Looted: ... (notes).", already in the
-- owner's language) or nil}. withPouch: false for the other members of a party. t: the recipient's translator
-- (default English). Returns the line, or nil when there is nothing to say.
function K.compose(rec, withPouch, t)
	t = t or K.english
	local monster, items = K.split(rec.stock)
	monster = monster or rec.monster
	local bonus = rec.bonus or {}
	local list
	if items then
		items = trimDot(items)
		-- "nothing" (an empty corpse) and "nothing (due to low stamina)": the bonus items replace it
		if #bonus > 0 and items:sub(1, 7) == "nothing" then
			list = table.concat(bonus, ", ")
		elseif #bonus > 0 then
			list = items .. ", " .. table.concat(bonus, ", ")
		elseif NOTHING[items] then
			list = t(items)
		else
			list = items
		end
	elseif #bonus > 0 then
		list = table.concat(bonus, ", ")
	end
	local pouch = withPouch ~= false and rec.pouch or nil
	if not list and not pouch then
		return nil
	end
	local parts = {}
	if list then
		parts[#parts + 1] = t("Loot of %s: %s", monster or t("a creature"), list) .. "."
	end
	if pouch then
		parts[#parts + 1] = trimDot(pouch) .. "."
	end
	return table.concat(parts, " ")
end

return K

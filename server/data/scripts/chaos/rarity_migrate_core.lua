-- rarity_migrate_core.lua: the pure part of the rarity migration (rarity_migrate.lua; server/README.md "Item rarities").
-- Until 2026-10-18 the game had 15 rarities (Common .. Transcendent); it has seven now (data/lib/chaos_rarity.lua). An item
-- keeps its custom attribute "rarity" in the engine's old number space, and every reader maps an old id to the rarity it
-- became, so nothing needs this to work. The migration only tidies: it rewrites the attribute of an item that still has one of
-- the ids 6 .. 9 or 11 .. 15 to the id of its rarity (5 or 10). Nothing else on the item changes: not its modifiers, tiers,
-- values, item level, quality, sockets or gems. Running it twice changes nothing (a stored id maps to itself).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

ChaosRarityMigrateCore = ChaosRarityMigrateCore or {}
local K = ChaosRarityMigrateCore

K.VERSION = 2 -- (2: stackables lose their rarity, owner 2026-10-20)
-- the number the character's storage holds once its items were walked

-- the id an attribute value should hold, or nil when it is fine (none, already a stored id, not a number)
function K.target(value)
	local n = tonumber(value)
	if not n then
		return nil
	end
	n = math.floor(n)
	if n < 1 or n > ChaosRarity.MAX_LEGACY or not ChaosRarity.isLegacy(n) then
		return nil
	end
	return ChaosRarity.canon(n)
end

-- fix one item through two accessors (get(key) -> value, set(key, value)); returns the old id when it changed, else nil.
-- `stack` (optional): {stackable = bool, clear = function(key)}. A stackable item never carries a rarity (owner
-- 2026-10-20): its attribute is cleared, and the answer is the string "stackable" (a text a drop's shield also is, but
-- that is checked below it).
function K.fixItem(get, set, stack)
	local ok, v = pcall(get, "rarity")
	if not ok or v == nil then
		return nil
	end
	if stack and stack.stackable and type(v) ~= "string" then
		pcall(stack.clear, "rarity")
		return "stackable"
	end
	-- a drop's rarity is text for a moment (ChaosCrafting.shield): the shield owner gives the number back, leave it
	if type(v) == "string" then
		return nil
	end
	local to = K.target(v)
	if not to then
		return nil
	end
	set("rarity", to)
	return tonumber(v)
end

-- the report line of a walk: counts per old id -> "Mythic x2, Cosmic x1" (nil when nothing changed)
function K.summary(counts)
	local ids = {}
	for id in pairs(counts or {}) do
		if type(id) == "number" then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		parts[#parts + 1] = string.format("%s x%d", ChaosRarity.legacyNames[id] or tostring(id), counts[id])
	end
	if counts and (counts.stackable or 0) > 0 then
		parts[#parts + 1] = string.format("stackables x%d", counts.stackable)
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

return K

-- retired_spells_core.lua: pure rules of the retired-spell clean-up at login (no engine calls; tests:
-- tests/retired_spells_test.lua). Lua 5.1 / LuaJIT and Lua 5.3 compatible. Engine side: retired_spells.lua.
ChaosRetiredSpellsCore = ChaosRetiredSpellsCore or {}
local M = ChaosRetiredSpellsCore

-- the retired spells a character still has a learned row for (names sorted, no name twice).
-- names: the list of the config; knows(name) -> bool
function M.forgetList(names, knows)
	local out, seen = {}, {}
	for _, name in ipairs(names or {}) do
		if not seen[name] then
			seen[name] = true
			if knows(name) then
				out[#out + 1] = name
			end
		end
	end
	table.sort(out)
	return out
end

local function lists(ids, vocationId)
	for _, id in ipairs(ids or {}) do
		if id == vocationId then
			return true
		end
	end
	return false
end

-- the notices a character is owed: its class lost the spell and its level had reached it, and the stored version is
-- older than the config's (told = the stored value, 0 or less when never told). Returns the notices in config order.
function M.due(notices, version, told, vocationId, level)
	local out = {}
	if (tonumber(told) or 0) >= version then
		return out
	end
	for _, n in ipairs(notices or {}) do
		if lists(n.vocations, vocationId) and (tonumber(level) or 0) >= (tonumber(n.level) or 0) then
			out[#out + 1] = n
		end
	end
	return out
end

return M

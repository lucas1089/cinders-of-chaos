-- Main quest gates (O570, server/README.md "Deck of Cards (O570)", "Main quest (O551)"): a feature that opens when a character is past
-- a step of the main quest (the Deck of Cards and the Badge slot open with the step "deck"). Reads the main quest's own storages
-- (mainquest_config.lua `storage`), so any Lua state can ask it: revscripts and NPC scripts. No event, no write.
--   ChaosMQGate.passed(player, stepKey)   true when the character is past the step: its quest is done, skipped or quiet (first
--        seen above level 500), or its current step is after the step. A character the quest has not seen yet (state -1) is not past.
--   ChaosMQGate.title(stepKey, lang)      the title of the step in the language of the player ("pt-BR" or anything else = English)
-- Lua 5.1 / LuaJIT and 5.3.

ChaosMQGate = ChaosMQGate or {}
local G = ChaosMQGate

local cache

local function cfg()
	if cache == nil then
		local ok, c = pcall(dofile, "data/scripts/chaos/mainquest_config.lua")
		cache = (ok and type(c) == "table") and c or false
	end
	return cache or nil
end

-- test hook: forget the cached config
function G.reset()
	cache = nil
end

function G.indexOf(stepKey)
	local c = cfg()
	for i, s in ipairs(c and c.steps or {}) do
		if s.key == stepKey then
			return i
		end
	end
	return nil
end

function G.passed(player, stepKey)
	local c = cfg()
	local idx = G.indexOf(stepKey)
	if not (player and c and idx) then
		return false
	end
	local st = c.storage
	local state = tonumber(player:getStorageValue(st.base + st.state))
	if state == nil then
		return false
	end
	if state == c.states.done or state == c.states.skipped or state == c.states.quiet then
		return true
	end
	if state == c.states.active then
		return (tonumber(player:getStorageValue(st.base + st.step)) or 0) > idx
	end
	return false
end

function G.title(stepKey, lang)
	local c = cfg()
	for _, s in ipairs(c and c.steps or {}) do
		if s.key == stepKey then
			return lang == "pt-BR" and s.title.pt or s.title.en
		end
	end
	return tostring(stepKey)
end

return G

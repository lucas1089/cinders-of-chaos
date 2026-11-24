-- intros_core.lua: the pure rules of the quiet first login and the introductions after it (O761; intros_config.lua; engine side
-- intros.lua; server/README.md "Quiet first login (O761)"). No engine calls. tests/intros_test.lua covers it. Lua 5.1 / LuaJIT and 5.3.

ChaosIntrosCore = ChaosIntrosCore or {}
local M = ChaosIntrosCore

local floor = math.floor

function M.cfg()
	if not M.config then
		local ok, t = pcall(dofile, "data/scripts/chaos/intros_config.lua")
		M.config = ok and type(t) == "table" and t or nil
	end
	return M.config
end

-- bit i (1-based) of a stored mask (-1 = never stored)
function M.has(mask, i)
	mask = floor(tonumber(mask) or 0)
	if mask < 0 then
		return false
	end
	return floor(mask / 2 ^ (i - 1)) % 2 == 1
end

function M.set(mask, i)
	mask = math.max(0, floor(tonumber(mask) or 0))
	if M.has(mask, i) then
		return mask
	end
	return floor(mask + 2 ^ (i - 1))
end

function M.index(cfg, key)
	for i, it in ipairs(cfg.intros or {}) do
		if it.key == key then
			return i
		end
	end
	return nil
end

-- the state a character gets the first time this module sees it: quiet when this is its first login (lastLoginSaved 0) and it is
-- neither staff nor a tester bot; open otherwise (a character from before O761 keeps every introduction as it was)
function M.firstState(cfg, lastLoginSaved, staff, tester)
	if cfg.enabled ~= false and (tonumber(lastLoginSaved) or 0) <= 0 and not staff and not tester then
		return cfg.states.quiet
	end
	return cfg.states.open
end

-- the windows of the login window queue this login may open by itself: all of them, or on a quiet first login only the
-- firstLoginWindows keys (the Daily Reward)
function M.loginWindowWanted(cfg, key, firstQuietLogin)
	if not firstQuietLogin then
		return true
	end
	return (cfg.firstLoginWindows or {})[key] == true
end

-- may the system behind an introduction show its things? Always for an open character; for a quiet one once its introduction
-- was given (the bit). An unknown key is never held back.
function M.allowed(cfg, state, shown, key)
	if state ~= cfg.states.quiet then
		return true
	end
	local i = M.index(cfg, key)
	return i == nil or M.has(shown, i)
end

-- ctx: {level, questActive (the main quest runs for the character), questStep (index of the open step), indexOf = function(key)}
function M.reached(cfg, i, ctx)
	local it = cfg.intros[i]
	if not it then
		return false
	end
	ctx = ctx or {}
	if not ctx.questActive then
		return true
	end
	if it.level and (tonumber(ctx.level) or 0) >= it.level then
		return true
	end
	local after = it.after and ctx.indexOf and ctx.indexOf(it.after)
	return after ~= nil and (tonumber(ctx.questStep) or 0) > after
end

-- the introductions due now (reached, not given yet), in their order; an open character has none
function M.due(cfg, state, shown, ctx)
	local out = {}
	if state ~= cfg.states.quiet then
		return out
	end
	for i = 1, #(cfg.intros or {}) do
		if not M.has(shown, i) and M.reached(cfg, i, ctx) then
			out[#out + 1] = i
		end
	end
	return out
end

function M.text(t, lang)
	if type(t) ~= "table" then
		return nil
	end
	return (lang == "pt" or lang == "pt-BR") and t.pt or t.en
end

local SYSTEMS = {outfit = true, firsthour = true, unlocks = true, goals = true}

-- problems of the config (an empty list when it is fine); questKeys: set of the main quest's step keys, or nil
function M.validate(cfg, questKeys)
	local out = {}
	local s = cfg.storage or {}
	for _, k in ipairs({"state", "shown"}) do
		local key = (tonumber(s.base) or 0) + (tonumber(s[k]) or -1000)
		if key < 7103160 or key > 7103169 then
			out[#out + 1] = "storage " .. k .. " outside 7103160-7103169"
		end
	end
	if #(cfg.intros or {}) > 30 then
		out[#out + 1] = "more than 30 introductions"
	end
	local seen = {}
	for i, it in ipairs(cfg.intros or {}) do
		local where = "intro " .. i .. " (" .. tostring(it.key) .. ")"
		if type(it.key) ~= "string" or seen[it.key] then
			out[#out + 1] = where .. ": no key or a key twice"
		end
		seen[it.key or i] = true
		if not SYSTEMS[it.system] then
			out[#out + 1] = where .. ": unknown system " .. tostring(it.system)
		end
		if not (tonumber(it.level) and it.level >= 1) then
			out[#out + 1] = where .. ": no level"
		end
		if questKeys and it.after and not questKeys[it.after] then
			out[#out + 1] = where .. ": the main quest has no step " .. tostring(it.after)
		end
		if it.text ~= nil and (type(it.text) ~= "table" or type(it.text.en) ~= "string" or type(it.text.pt) ~= "string") then
			out[#out + 1] = where .. ": text needs en and pt"
		end
	end
	return out
end

return M

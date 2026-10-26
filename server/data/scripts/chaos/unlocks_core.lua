-- unlocks_core.lua: the pure rules of the level-gated top menu (unlocks_config.lua; server/README.md "The top menu reveals
-- systems by level (O259)"). No engine calls; unlocks.lua is the engine side. tests/unlocks_test.lua covers it.
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosUnlocksCore = ChaosUnlocksCore or {}
local M = ChaosUnlocksCore

local floor = math.floor

function M.cfg()
	if not M.config then
		local ok, t = pcall(dofile, "data/scripts/chaos/unlocks_config.lua")
		M.config = ok and type(t) == "table" and t or nil
	end
	return M.config
end

-- bit i (1-based) of a stored mask (-1 = never stored = nothing set)
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

function M.all(n)
	return floor(2 ^ n - 1)
end

function M.index(key)
	for i, e in ipairs(M.cfg().entries) do
		if e.key == key then
			return i
		end
	end
	return nil
end

-- the entries a character at `level` has reached and not unlocked yet: indexes, lowest level first (ties by index)
function M.due(mask, level)
	local out = {}
	local entries = M.cfg().entries
	for i, e in ipairs(entries) do
		if e.level <= (tonumber(level) or 0) and not M.has(mask, i) then
			out[#out + 1] = i
		end
	end
	table.sort(out, function(a, b)
		if entries[a].level ~= entries[b].level then
			return entries[a].level < entries[b].level
		end
		return a < b
	end)
	return out
end

-- the next entry to unlock: the lowest level above the character's that is not unlocked yet -> {key, level} or nil.
-- (An entry at or below the level that waits for its announcement is not "next": it is about to appear.)
function M.nextLocked(mask, level)
	local best
	local entries = M.cfg().entries
	for i, e in ipairs(entries) do
		if e.level > (tonumber(level) or 0) and not M.has(mask, i) then
			if not best or e.level < entries[best].level then
				best = i
			end
		end
	end
	if not best then
		return nil
	end
	return {key = entries[best].key, level = entries[best].level}
end

-- entries added after the character's masks were made (index known+1 .. count) at a level it already passed: set in the
-- mask, silently. Returns the new mask.
function M.sync(mask, known, count, levelOf, level)
	mask = math.max(0, floor(tonumber(mask) or 0))
	level = tonumber(level) or 0
	for i = math.max(1, floor(tonumber(known) or 0) + 1), count do
		if levelOf(i) <= level then
			mask = M.set(mask, i)
		end
	end
	return mask
end

-- a character first seen: above quietAbove it gets every entry of its level unlocked and seen, silently
function M.firstMasks(level)
	local c = M.cfg()
	if (tonumber(level) or 0) > (c.quietAbove or 0) then
		local m = M.sync(0, 0, #c.entries, function(i) return c.entries[i].level end, level)
		return m, m
	end
	return 0, 0
end

function M.pace()
	local p = M.cfg().pace or {}
	return math.max(1, floor(tonumber(p.perRun) or 1)), math.max(1000, floor(tonumber(p.gapMs) or 75000))
end

local function pick(pair, lang)
	return (lang == "pt" or lang == "pt-BR") and pair[2] or pair[1]
end

-- the `state` message: the whole table (the client filters its menu by it), what is unlocked and seen, the next one.
-- all = true: the whole menu (staff, or the module off)
function M.state(unlockedMask, seenMask, level, all)
	local c = M.cfg()
	local entries, unlocked, seen = {}, {}, {}
	for i, e in ipairs(c.entries) do
		entries[i] = {key = e.key, level = e.level, menu = e.menu}
		if M.has(unlockedMask, i) then
			unlocked[#unlocked + 1] = e.key
			if M.has(seenMask, i) then
				seen[#seen + 1] = e.key
			end
		end
	end
	local data = {entries = entries, unlocked = unlocked, seen = seen}
	local nxt = M.nextLocked(unlockedMask, level)
	if nxt then
		data.next = nxt
	end
	if all then
		data.all = true
	end
	return data
end

-- the `new` message of entry i: the screen text and the small window
function M.announcement(i, lang)
	local e = M.cfg().entries[i]
	return {key = e.key, level = e.level, menu = e.menu, title = pick(e.title, lang),
		why = {pick(e.why[1], lang), pick(e.why[2], lang)}}
end

return M

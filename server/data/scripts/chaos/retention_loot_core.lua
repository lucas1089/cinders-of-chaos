-- retention_loot_core.lua: the rules of O260 without engine calls (retention_loot.lua, hooks in loot.lua; numbers:
-- retention_loot_config.lua; tests: server/tests/retention_loot_test.lua). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   first unique   RLC.countRead(raw), RLC.firstUniqueStep(cfg, raw, level, tester) -> action, newRaw
--                  RLC.candidatesOf(cfg, className), RLC.pickUnique(cfg, className, level, byName) -> entry
--   pity           RLC.pityRead(raw), RLC.pityDue(cfg, count), RLC.pityBoost(cfg, rank) -> new rank | nil
--                  RLC.pityFinish(cfg, count, hunting, boosted, bestRank) -> the counter after the kill
--   drop feed      RLC.feedKind(cfg, rank, unique) -> "legendary" | "divine" | "unique" | nil
--                  RLC.feedRank(cfg, kind), RLC.optionRank(option), RLC.shown(cfg, kind, option)
--                  RLC.feedNew(), RLC.feedAllow(state, cfg, guid, now) (per character and server-wide limits)
--                  RLC.feedLine(cfg, name, level, link) the English text; the engine translates the key
--   records        RLC.dropBest(items) -> best rank, best value of a kill's gear (the personal drop boards)

RetentionLootCore = RetentionLootCore or {}
local RLC = RetentionLootCore

local floor = math.floor

-- ---------------------------------------------------------------- 1. the first unique
-- the kill counter of a raw storage value: unset (-1) and anything below 0 count as no kills
function RLC.countRead(raw)
	raw = floor(tonumber(raw) or 0)
	return raw > 0 and raw or 0
end

-- What a kill does to the first-unique counter.
--   returns "skip", raw           nothing to do (off, a tester, too high a level, already given)
--           "count", newRaw       one more kill, store newRaw
--           "give", doneValue     this is the `kills`-th kill: give the unique and store doneValue
function RLC.firstUniqueStep(cfg, raw, level, tester)
	local f = cfg and cfg.firstUnique
	if not (cfg and cfg.enabled ~= false and f and f.enabled ~= false) or tester then
		return "skip", raw
	end
	if (tonumber(level) or 0) > (tonumber(f.maxLevel) or 60) then
		return "skip", raw
	end
	local n = RLC.countRead(raw)
	if n >= (tonumber(f.doneValue) or 1000000) then
		return "skip", raw
	end
	n = n + 1
	if n >= (tonumber(f.kills) or 150) then
		return "give", tonumber(f.doneValue) or 1000000
	end
	return "count", n
end

-- the list of unique names for a class: its own, else its line's, else the default
function RLC.candidatesOf(cfg, className)
	local f = cfg.firstUnique
	local own = f.byClass[className]
	if own then
		return own
	end
	local line = f.lineOf and f.lineOf[className]
	return (line and f.byClass[line]) or f.default or {}
end

-- byName: name -> {name, id, level} (ChaosUniqueByName entries; level = the unique's requirement). The candidate with
-- the highest requirement not above `level`, else the lowest one. nil when no candidate is a known unique.
function RLC.pickUnique(cfg, className, level, byName)
	level = tonumber(level) or 1
	local best, bestLevel, lowest, lowestLevel
	for _, name in ipairs(RLC.candidatesOf(cfg, className)) do
		local e = byName and byName[name]
		if e and tonumber(e.id) then
			local req = tonumber(e.level) or 1
			if req <= level and (not best or req > bestLevel) then
				best, bestLevel = e, req
			end
			if not lowest or req < lowestLevel then
				lowest, lowestLevel = e, req
			end
		end
	end
	return best or lowest
end

-- ---------------------------------------------------------------- 2. pity
function RLC.pityRead(raw)
	raw = floor(tonumber(raw) or 0)
	return raw > 0 and raw or 0
end

function RLC.pityDue(cfg, count)
	local p = cfg and cfg.pity
	if not (cfg and cfg.enabled ~= false and p and p.enabled ~= false) then
		return false
	end
	return RLC.pityRead(count) >= (tonumber(p.threshold) or 400)
end

-- the rank a due gear drop of `rank` is raised to, nil when it stays (below minRank, or at maxRank already)
function RLC.pityBoost(cfg, rank)
	local p = cfg.pity
	rank = floor(tonumber(rank) or 0)
	if rank >= (tonumber(p.minRank) or 3) and rank < (tonumber(p.maxRank) or 5) then
		return rank + 1
	end
	return nil
end

-- The counter after a kill. hunting: the kill counted (a rift, a waystone map, a boss leave it as it was); boosted: the
-- pity raised a drop of this kill; bestRank: the best rank among the kill's gear and uniques (7 for a unique).
function RLC.pityFinish(cfg, count, hunting, boosted, bestRank)
	count = RLC.pityRead(count)
	if not hunting then
		return count
	end
	if boosted or (tonumber(bestRank) or 0) >= (tonumber(cfg.pity.resetRank) or 4) then
		return 0
	end
	return count + 1
end

-- ---------------------------------------------------------------- 3. the drop feed
-- A drop's kind. rank: the rarity rank of the item (data/lib/chaos_rarity.lua R.rank; 0 none); unique: the item is a unique.
function RLC.feedKind(cfg, rank, unique)
	if unique then
		return "unique"
	end
	rank = floor(tonumber(rank) or 0)
	if rank >= 6 then
		return "divine"
	end
	if rank >= (tonumber(cfg.feed.minRankLegendary) or 5) then
		return "legendary"
	end
	return nil
end

function RLC.feedRank(cfg, kind)
	return tonumber(cfg.feed.kinds[kind]) or 0
end

-- the client option "Drop feed": "off" | "unique" | "legendary" (the minimum shown) -> its rank; off = 0 shows nothing
function RLC.optionRank(cfg, option)
	if option == "unique" then
		return 2
	elseif option == "legendary" then
		return 1
	end
	return 0
end

-- does a line of `kind` show with this option?
function RLC.shown(cfg, kind, option)
	local min = RLC.optionRank(cfg, option)
	return min > 0 and RLC.feedRank(cfg, kind) >= min
end

function RLC.feedNew()
	return {chars = {}, window = nil, dropped = 0, sent = 0}
end

-- may this character's drop post a line now? One line per character in perCharSeconds, maxPerMinute server-wide; the
-- rest is dropped silently (counted). now in seconds. Records the line when it allows it.
function RLC.feedAllow(state, cfg, guid, now)
	local f = cfg.feed
	now = tonumber(now) or 0
	local last = state.chars[guid]
	if last and now - last < (tonumber(f.perCharSeconds) or 60) then
		state.dropped = state.dropped + 1
		return false
	end
	local minute = floor(now / 60)
	if not state.window or state.window.minute ~= minute then
		state.window = {minute = minute, n = 0}
	end
	if state.window.n >= (tonumber(f.maxPerMinute) or 12) then
		state.dropped = state.dropped + 1
		return false
	end
	state.window.n = state.window.n + 1
	state.chars[guid] = now
	state.sent = state.sent + 1
	-- forget the characters that are past the limit anyway (the table stays small)
	if state.sent % 64 == 0 then
		for g, at in pairs(state.chars) do
			if now - at >= (tonumber(f.perCharSeconds) or 60) then
				state.chars[g] = nil
			end
		end
	end
	return true
end

-- a name safe to put in a line: no control characters, no brackets or braces (they would end an item link), cut
function RLC.cleanName(name)
	name = tostring(name or "")
	name = name:gsub("[%c%[%]{}]", ""):gsub("%s+", " ")
	return (name:sub(1, 30))
end

-- the line, in English or through `translate(key) -> pattern` (the engine's Chaos.t for a player); link is the item link text
function RLC.feedLine(cfg, name, level, link, pattern)
	return string.format(pattern or cfg.feed.text, RLC.cleanName(name), floor(tonumber(level) or 0), tostring(link))
end

-- ---------------------------------------------------------------- 4. the personal drop boards
-- items = {{rank = n (1..7; 7 a unique), value = gold}}; returns the best rank and the best value (0, 0 when empty)
function RLC.dropBest(items)
	local rank, value = 0, 0
	for _, it in ipairs(items or {}) do
		rank = math.max(rank, floor(tonumber(it.rank) or 0))
		value = math.max(value, floor(tonumber(it.value) or 0))
	end
	return rank, value
end

return RLC

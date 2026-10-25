-- firsthour_core.lua: the pure rules of the first-hour hints (firsthour_config.lua; docs/CONTENT.md "First hour").
-- No engine calls; firsthour.lua is the engine side. tests/firsthour_test.lua covers it. Lua 5.1 / LuaJIT and 5.3.

ChaosFirstHourCore = ChaosFirstHourCore or {}
local M = ChaosFirstHourCore

local floor, abs = math.floor, math.abs

function M.cfg()
	if not M.config then
		local ok, t = pcall(dofile, "data/scripts/chaos/firsthour_config.lua")
		M.config = ok and type(t) == "table" and t or nil
	end
	return M.config
end

-- bit i (1-based) of a stored mask
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

-- the hints due at a level (hint level <= level) and not given yet: list of indexes, lowest level first (ties by index;
-- hints added later at the end of the list can sit at a lower level than the ones before them). A hint missed (a level
-- gained before the kit, on the tutorial island) comes at the next chance.
function M.dueHints(mask, level)
	local out = {}
	local hints = M.cfg().hints
	for i, h in ipairs(hints) do
		if h.level <= (tonumber(level) or 0) and not M.has(mask, i) then
			out[#out + 1] = i
		end
	end
	table.sort(out, function(a, b)
		if hints[a].level ~= hints[b].level then
			return hints[a].level < hints[b].level
		end
		return a < b
	end)
	return out
end

-- how many hints one run may say and how long the rest waits (cfg.pace): a new character starts at level 8 with three
-- hints due, which used to arrive together with the welcome and the Helper. Returns perRun, gapMs.
function M.pace()
	local p = M.cfg().pace or {}
	return math.max(1, math.floor(tonumber(p.perRun) or 1)), math.max(1000, math.floor(tonumber(p.gapMs) or 60000))
end

-- the reveals due at a level: one pick covers them all (the hunts of the current level)
function M.dueReveals(mask, level)
	local out = {}
	for i, lv in ipairs(M.cfg().revealAt) do
		if lv <= (tonumber(level) or 0) and not M.has(mask, i) then
			out[#out + 1] = i
		end
	end
	return out
end

-- the level band of a hunting mark's name ("Hunting: Rat, Snake (level 4-9)") -> lo, hi
function M.bandOf(name)
	local lo, hi = tostring(name or ""):match("%(level (%d+)%-(%d+)%)")
	if not lo then
		return nil
	end
	return tonumber(lo), tonumber(hi)
end

-- the hunting marks to reveal: marks = {{k, x, y, z, n}}, seen = set of keys (keyOf(mark)), center = temple position
-- -> up to cfg.reveal.count marks, nearest first (ties by x, y, z)
function M.pickHunts(marks, seen, keyOf, center, level, opts)
	opts = opts or M.cfg().reveal
	local out = {}
	for _, m in ipairs(marks or {}) do
		if m.k == "hunt" and not (seen and seen[keyOf(m)]) then
			local lo, hi = M.bandOf(m.n)
			if lo and lo <= level + (opts.slack or 0) and hi >= level then
				local d = math.max(abs(m.x - center.x), abs(m.y - center.y)) + abs(m.z - center.z) * (opts.floorCost or 0)
				if d <= (opts.range or 1e9) then
					out[#out + 1] = {m = m, d = d}
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		if a.m.x ~= b.m.x then
			return a.m.x < b.m.x
		end
		if a.m.y ~= b.m.y then
			return a.m.y < b.m.y
		end
		return a.m.z < b.m.z
	end)
	local list = {}
	for i = 1, math.min(#out, opts.count or 3) do
		list[i] = out[i].m
	end
	return list
end

-- a hint or reveal added after the character got its mask: entries known+1 .. count whose level (levelOf(i)) the
-- character has passed are marked given, silently (an old level 600 character is not told about level 150 now).
-- Returns the new mask.
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

-- the content hunts of the teleport room for a level: plans = {{name, level = {lo, hi}}}; up to opts.count whose band
-- holds the level or starts at most opts.slack above it, lowest band first -> "Sulphur Gallery (215-299)" names
function M.pickPlans(plans, level, opts)
	opts = opts or M.cfg().plans or {}
	level = tonumber(level) or 0
	local out = {}
	for _, p in ipairs(plans or {}) do
		local lo, hi = p.level and tonumber(p.level[1]), p.level and tonumber(p.level[2])
		if lo and hi and lo <= level + (opts.slack or 0) and hi >= level then
			out[#out + 1] = p
		end
	end
	table.sort(out, function(a, b)
		if a.level[1] ~= b.level[1] then
			return a.level[1] < b.level[1]
		end
		return tostring(a.name) < tostring(b.name)
	end)
	local names = {}
	for i = 1, math.min(#out, opts.count or 3) do
		names[i] = string.format("%s (%d-%d)", tostring(out[i].name or out[i].id), out[i].level[1], out[i].level[2])
	end
	return names
end

-- a hunting mark's short name: "Rat, Snake (level 4-9)"
function M.shortName(m)
	return (tostring(m.n or ""):gsub("^Hunting: ", ""))
end

function M.text(i, lang, names)
	local h = M.cfg().hints[i]
	local t = h[lang] or h.en
	if t:find("%s", 1, true) then
		local list = names and #names > 0 and table.concat(names, "; ") or (M.cfg().none[lang] or M.cfg().none.en)
		t = string.format(t, list)
	end
	return t
end

return M

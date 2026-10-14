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

-- the hints due at a level (hint level <= level) and not given yet: list of indexes. A hint missed (a level gained
-- before the kit, on the tutorial island) comes at the next chance.
function M.dueHints(mask, level)
	local out = {}
	for i, h in ipairs(M.cfg().hints) do
		if h.level <= (tonumber(level) or 0) and not M.has(mask, i) then
			out[#out + 1] = i
		end
	end
	return out
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

-- unique_window_core.lua: the monster level window of a leveling unique (O342, O467). One place for the rule, read by
-- loot.lua (L.openLevelMult: who may drop it), the Codex and wiki generators (tools/gen_codex_data.lua,
-- tools/gen_wiki_data.lua: the "Level window" row) and the Item Finder (itemfinder_sources.lua). Numbers:
-- loot_config.lua unique.openLevel. Pure, no engine calls. Lua 5.1 / 5.3 / LuaJIT compatible.

ChaosUniqueWindow = ChaosUniqueWindow or {}
local W = ChaosUniqueWindow

-- the monster levels (lo, hi, as numbers; a monster drops it from level lo up to level hi) a leveling unique entry also
-- drops from besides its listed monsters; nil when the rule does not apply to the entry (rule off, a boss-only entry, an
-- entry with a minimum monster level, an item level above maxItemLevel, no level). o = loot_config.lua unique.openLevel,
-- e = an entry of ChaosUniqueItems.
function W.range(o, e)
	local lv = tonumber(e and e.level)
	if not (type(o) == "table" and o.enabled and lv and lv > 0) then
		return nil
	end
	if e.bossOnly or e.minMonsterLevel or lv > (tonumber(o.maxItemLevel) or 0) then
		return nil
	end
	return lv * (1 - (tonumber(o.below) or 0)), lv * (tonumber(o.above) or 1) + (tonumber(o.aboveFlat) or 0)
end

-- the same window in whole monster levels for a text: the lowest level (rounded up) and the highest (rounded down)
function W.levels(o, e)
	local lo, hi = W.range(o, e)
	if not lo then
		return nil
	end
	return math.ceil(lo - 1e-6), math.floor(hi + 1e-6)
end

-- linear between points {{x, y}, ...} (sorted by x), flat beyond the ends
function W.curveAt(points, x)
	if type(points) ~= "table" or #points == 0 then
		return 0
	end
	if x <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

return W

-- Monster levels in the name (monster_levels.lua; server/README.md "Monster levels in the name"): the pure part.
-- A level-scaled monster (a <level min max> in its XML) shows its rolled level after the name through the engine
-- ("Black Stag [777]"). Every other monster gets the level the Chaos systems already use for it
-- (ChaosLoot.monsterLevel: the bounty pool's hunting level, else the experience / health estimate) as a display level
-- (engine patch 0040, monster:setDisplayLevel): shown only, no stat change. A monster a system scaled (rift, invasion,
-- generated area or dungeon) shows that level instead, even over its own (patch 0044). tests/monster_levels_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosMonsterLevelsCore = ChaosMonsterLevelsCore or {}
local K = ChaosMonsterLevelsCore

local function level(v)
	local lv = tonumber(v)
	if not lv or lv ~= lv or lv <= 0 or lv == math.huge then
		return nil
	end
	return math.max(1, math.floor(lv + 0.5))
end

-- O177 (beta 2026-10-24: a pocket boss showed "Lv 10182"): the highest level a monster may SHOW from an estimate. The
-- experience / health estimate of a world boss species is far above any level (it is only meant to rank monsters), so
-- an estimate is shown at most at the top hunting level (progression_config.lua limits.toLevel, 2200; the test keeps
-- them equal). A level a system passes itself (Chaos.spawnLevel: the Infinity Tower's floors may go higher) is not
-- clamped. Display only: loot, damage and pace read their own levels.
K.maxEstimate = 2200

-- Owner 2026-10-27: a pool-derived estimate is the bounty pool's "fair hunt" level; the level players hunt the monster
-- at (and the map marks, the Codex and the wiki print) is `mult` times it (pace_config.lua baseLevelMult, 1 since 2026-10-28, O285: the pool level; the x2 rule of O272 is retired). A level a
-- system or the engine gave the monster (waystone tier, generated area point, level-scaled) is already a hunting level.
-- Display only: loot, damage and pace keep reading the pool level.
function K.huntingLevel(poolLevel, mult)
	local lv = tonumber(poolLevel)
	if not lv or lv ~= lv or lv <= 0 then
		return nil
	end
	local m = tonumber(mult)
	if not m or m < 1 then
		m = 1
	end
	return lv * m
end

-- the display level of a monster: nil when it is a player's summon (a pet or a conjured creature: its level is the
-- owner's business); else `scaled` when given (the level a rift, an invasion or a generated area scaled it to:
-- Chaos.spawnLevel; it wins over the own level, engine patch 0044); else nil when it shows its own (own > 0) or no
-- estimate is known; else the estimate, at least 1 and at most K.maxEstimate
function K.displayLevel(own, estimate, playerSummon, scaled)
	if playerSummon then
		return nil
	end
	local forced = level(scaled)
	if forced then
		return forced
	end
	if (tonumber(own) or 0) > 0 then
		return nil
	end
	local lv = level(estimate)
	return lv and math.min(lv, K.maxEstimate) or nil
end

-- ---------------------------------------------------------------- unlisted monsters in a hunt
-- Beta 2026-10-27: monsters inside a high-level hunt showed a level below 10. A monster that is not in the bounty pool
-- (fewer than six spawn entries, scenery, a summon) has only the estimate of its experience and health, which is low
-- for a Sheep or a Mirror Image standing in a level 800 hunt. Such a monster is shown at the lower end of the hunting
-- area it stands in (the map marks of data/chaos_poi.lua, hunting levels), never lower than its own estimate. Display only.
K.areaCell = 64
K.areaRadius = 60
K.farBelow = 0.1 -- a monster of the pool is raised to its hunt only when it shows less than this share of the hunt's lower end

-- "Hunting: Rat, Snake (level 4-9)" -> lo, hi (the hunting level band of a hunt mark)
function K.bandOf(name)
	local lo, hi = tostring(name or ""):match("%(level (%d+)%-(%d+)%)")
	if not lo then
		return nil
	end
	return tonumber(lo), tonumber(hi)
end

-- the hunt marks {k, x, y, z, n} of the map markers -> an index by floor and 64-tile cell
function K.indexHunts(marks)
	local idx = {}
	for _, m in ipairs(marks or {}) do
		if m.k == "hunt" then
			local lo, hi = K.bandOf(m.n)
			if lo then
				local key = m.z .. ":" .. math.floor(m.x / K.areaCell) .. ":" .. math.floor(m.y / K.areaCell)
				idx[key] = idx[key] or {}
				table.insert(idx[key], {x = m.x, y = m.y, lo = lo, hi = hi})
			end
		end
	end
	return idx
end

-- the band floor (lo) of the nearest hunting area within K.areaRadius squares on the floor, or nil
function K.areaFloor(idx, x, y, z)
	if not idx or not x or not y or not z then
		return nil
	end
	local cx, cy = math.floor(x / K.areaCell), math.floor(y / K.areaCell)
	local best, bestD
	for dx = -1, 1 do
		for dy = -1, 1 do
			for _, h in ipairs(idx[z .. ":" .. (cx + dx) .. ":" .. (cy + dy)] or {}) do
				local d = math.max(math.abs(h.x - x), math.abs(h.y - y))
				if d <= K.areaRadius and (not bestD or d < bestD) then
					best, bestD = h, d
				end
			end
		end
	end
	return best and best.lo or nil
end

-- the shown level of an unlisted monster: its hunting estimate, raised to the floor of its area (or its master's level)
function K.raise(level, floor)
	local lv, fl = tonumber(level), tonumber(floor)
	if fl and fl > 0 and (not lv or lv < fl) then
		return fl
	end
	return lv
end

return K

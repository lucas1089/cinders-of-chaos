-- gentledeath_core.lua: the pure rules of gentle deaths (gentledeath_config.lua; server/README.md "Gentle deaths and
-- blessings").
-- No engine calls; gentledeath.lua is the engine side. Tests: server/tests/gentledeath_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGentleDeathCore = ChaosGentleDeathCore or {}
local G = ChaosGentleDeathCore

local floor = math.floor

-- the day key (YYYYMMDD) of unix time t, the day turning at `hour`
function G.day(t, hour)
	return tonumber(os.date("%Y%m%d", t - (hour or 6) * 3600))
end

-- piecewise linear curve over {level, mult} points (sorted by level), flat beyond the ends
function G.curve(points, level)
	level = tonumber(level) or 1
	if not points or #points == 0 then
		return 1
	end
	if level <= points[1].level then
		return points[1].mult
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if level <= b.level then
			if b.level == a.level then
				return b.mult
			end
			return a.mult + (b.mult - a.mult) * (level - a.level) / (b.level - a.level)
		end
	end
	return points[#points].mult
end

-- the factor of a death: the level curve x the first-death-of-the-day factor (when firstToday)
function G.mult(cfg, level, firstToday)
	local m = G.curve(cfg.xpLoss, level)
	if firstToday then
		m = m * (tonumber(cfg.firstDeathOfDay) or 1)
	end
	if m < 0 then
		m = 0
	elseif m > 1 then
		m = 1
	end
	return m
end

-- the experience lost after the factor (an integer, never more than exp)
function G.ease(exp, mult)
	exp = tonumber(exp) or 0
	if exp <= 0 then
		return 0
	end
	local out = floor(exp * mult + 0.5)
	if out > exp then
		out = exp
	end
	return out
end

-- true when no item drops: always (cfg.keepItems), but never with a red / black skull or for a Hardcore character.
-- `level` is kept in the signature for callers of the first version; it no longer matters.
function G.keepItems(cfg, level, redOrBlack, hardcore)
	return cfg.keepItems == true and not redOrBlack and not hardcore
end

-- the gold of ONE classic blessing at a level (cfg.bless): the base NPC price to midCap, then latePerLevel a level
function G.blessCost(b, level)
	level = floor(tonumber(level) or 1)
	local cost = b.baseCost + b.perLevel * math.max(0, level - b.fromLevel)
	if cost > b.midCap then
		cost = b.midCap
	end
	cost = cost + b.latePerLevel * math.max(0, level - b.lateFrom)
	if cost > b.maxEach then
		cost = b.maxEach
	end
	return math.max(0, floor(cost))
end

-- the blessing ids of `ids` that has(id) says are missing
function G.missing(ids, has)
	local out = {}
	for _, id in ipairs(ids or {}) do
		if not has(id) then
			out[#out + 1] = id
		end
	end
	return out
end

-- why !bless is refused (a key), or nil. ctx = {inCombat, missing (count), gold (total), money}
function G.blessProblem(ctx)
	if ctx.inCombat then
		return "Blessings: leave combat first (no battle sign or protection zone lock)."
	end
	if ctx.missing <= 0 then
		return "You already have all blessings."
	end
	if ctx.money < ctx.gold then
		return "Blessings: you need %d gold (carried or in the bank) for %d blessing(s)."
	end
	return nil
end

-- the percent of the usual loss that was taken, for the message (0..100)
function G.percent(mult)
	return floor((tonumber(mult) or 1) * 100 + 0.5)
end

return G

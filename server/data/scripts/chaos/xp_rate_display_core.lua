-- XP gain rate shown in the client's Skills window (xp_rate_display.lua; server/README.md "XP gain rate display").
-- Pure functions. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosXpRateDisplay = ChaosXpRateDisplay or {}
local R = ChaosXpRateDisplay

R.MAX = 65535 -- the stats packet carries the rate as a uint16 percent
R.MIN = 1

-- the percent of a kill: the experience it really gave over its base (the monster's experience x level factor x stage x
-- tier), every bonus in between counted: world, self, passive tree, item mods, party ... nil when unknown
function R.percent(exp, base)
	exp, base = tonumber(exp), tonumber(base)
	if not exp or not base or base <= 0 or exp <= 0 then
		return nil
	end
	local pct = math.floor(exp / base * 100 + 0.5)
	return math.max(R.MIN, math.min(R.MAX, pct))
end

-- The client shows (base + low level bonus + boost) x stamina / 100. The kill's experience already carries the stamina
-- bonus, so the base the server sends is the percent without it.
function R.baseGain(pct, staminaPercent)
	pct = tonumber(pct)
	if not pct then
		return nil
	end
	staminaPercent = tonumber(staminaPercent) or 100
	if staminaPercent > 100 then
		pct = pct * 100 / staminaPercent
	end
	return math.max(R.MIN, math.min(R.MAX, math.floor(pct + 0.5)))
end

return R

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

-- O774: the standing rate, before any kill of the session (seen in a client: the line read 100% while the Chaos Pact was
-- active). Systems whose bonus holds outside a kill register a provider: R.providers[name] = function(player) -> the
-- experience multiplier (1 = none). The chain's other bonuses (tree, item mods, party, the monster's tier ...) depend
-- on the kill, so the first kill still sets the exact rate.
R.providers = R.providers or {}

-- product of the multipliers of a list (a bad or non-positive one counts as 1)
function R.product(mults)
	local m = 1
	for _, v in ipairs(mults or {}) do
		v = tonumber(v)
		if v and v > 0 and v == v then
			m = m * v
		end
	end
	return m
end

-- the base XP gain to send at a refresh: with a kill known, its rate moved by the change of the standing multipliers
-- since that kill; without one, 100 x the standing multipliers
function R.refreshGain(killGain, standingAtKill, standingNow)
	standingNow = tonumber(standingNow) or 1
	killGain, standingAtKill = tonumber(killGain), tonumber(standingAtKill)
	local pct
	if killGain and standingAtKill and standingAtKill > 0 then
		pct = killGain * standingNow / standingAtKill
	else
		pct = 100 * standingNow
	end
	return math.max(R.MIN, math.min(R.MAX, math.floor(pct + 0.5)))
end

return R

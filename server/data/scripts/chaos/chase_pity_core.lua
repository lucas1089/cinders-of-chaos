-- chase_pity_core.lua: the visible pity of the long chases (O753). Pure rules, no engine calls; numbers in
-- chase_pity_config.lua, engine glue in chase_pity.lua, tests in tests/chase_pity_test.lua, the sizing of N in
-- tools/chase_pity_model.lua. server/README.md "Chase pity (O753)".
--
-- A source (a rift chest, a waystone boss, a rift guardian, a pocket boss, a pinnacle fragment clear) has a chase drop of
-- base chance p per eligible event. After k misses in a row the chance is p x (1 + ramp x k / n); the n-th eligible event
-- (k = n - 1) is certain. A drop sets k back to 0. n is sized so the mean number of events to the drop is at most
-- maxShift (10%) below 1 / p (K.shift).
--   K.source(cfg, key)               -> the source row or nil
--   K.mult(src, misses)              -> the chance multiplier after `misses` misses (1 .. 1 + ramp)
--   K.forced(src, misses)            -> true when this event must drop (misses >= n - 1)
--   K.chance(p, src, misses)         -> the chance of this event (0 .. 1)
--   K.topUp(p, src, misses)          -> the chance of a second roll after the source's own roll of p missed
--   K.nextMisses(src, misses, hit)   -> the count after this event (0 after a hit, at most n - 1 after a miss)
--   K.meanEvents(p, n, ramp)         -> the mean number of events to the drop under the rule
--   K.shift(p, n, ramp)              -> 1 - p x meanEvents: how much shorter the chase is (0 .. 1)
--   K.deriveN(p, ramp, maxShift)     -> the smallest n whose shift is at most maxShift
--   K.progress(src, misses)          -> {key, done = misses, n, text = "37 / 60"}
--   K.view(cfg, missesOf)            -> the rows of the Collection log's pity panel, in cfg.order
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosChasePityCore = ChaosChasePityCore or {}
local K = ChaosChasePityCore

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end

function K.source(cfg, key)
	for _, s in ipairs((cfg and cfg.sources) or {}) do
		if s.key == key then
			return s
		end
	end
	return nil
end

local function nOf(src)
	return max(1, floor(num(src and src.n, 1)))
end

function K.mult(src, misses)
	local n = nOf(src)
	local k = min(max(0, floor(num(misses, 0))), n - 1)
	return 1 + num(src and src.ramp, 0) * k / n
end

function K.forced(src, misses)
	return floor(num(misses, 0)) >= nOf(src) - 1
end

function K.chance(p, src, misses)
	if K.forced(src, misses) then
		return 1
	end
	return min(1, max(0, num(p, 0)) * K.mult(src, misses))
end

-- a source that already rolled its own base chance p and missed: the chance of a second roll that lifts the total to
-- K.chance (1 when the event is forced)
function K.topUp(p, src, misses)
	p = min(1, max(0, num(p, 0)))
	local c = K.chance(p, src, misses)
	if c >= 1 then
		return 1
	end
	if p >= 1 then
		return 0
	end
	return max(0, (c - p) / (1 - p))
end

function K.nextMisses(src, misses, hit)
	if hit then
		return 0
	end
	return min(nOf(src) - 1, max(0, floor(num(misses, 0))) + 1)
end

function K.meanEvents(p, n, ramp)
	local src = {n = n, ramp = ramp}
	local alive, mean = 1, 0
	for k = 0, nOf(src) - 1 do
		mean = mean + alive
		alive = alive * (1 - K.chance(p, src, k))
		if alive <= 0 then
			break
		end
	end
	return mean
end

function K.shift(p, n, ramp)
	p = num(p, 0)
	if p <= 0 then
		return 1
	end
	return 1 - p * K.meanEvents(p, n, ramp)
end

function K.deriveN(p, ramp, maxShift)
	p = num(p, 0)
	if p <= 0 then
		return nil
	end
	local limit = 200000
	for n = 1, limit do
		if K.shift(p, n, ramp) <= maxShift then
			return n
		end
	end
	return nil
end

function K.progress(src, misses)
	local n = nOf(src)
	local done = min(n, max(0, floor(num(misses, 0))))
	return {key = src.key, done = done, n = n, text = string.format("%d / %d", done, n)}
end

-- missesOf(src) -> the character's count of that source (nil = 0)
function K.view(cfg, missesOf)
	local out = {}
	for _, key in ipairs(cfg.order or {}) do
		local src = K.source(cfg, key)
		if src then
			local pr = K.progress(src, missesOf and missesOf(src) or 0)
			out[#out + 1] = {k = key, l = src.label, d = pr.done, n = pr.n}
		end
	end
	return out
end

return K

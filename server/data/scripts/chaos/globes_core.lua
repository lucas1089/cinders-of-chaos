-- globes_core.lua: the pure rules of the health and mana globes (no engine calls; tests/globes_test.lua). The engine glue
-- is globes.lua, the numbers globes_config.lua, the ground pickup framework pickups_core.lua / pickups.lua; overview
-- server/README.md "Ground pickups and globes".
--
--   K.chance(cfg, kind, share, tier)            percent chance of one globe kind for the lowest share of max (0 .. 1)
--   K.lowest(shares)                            the lowest share of a list (nil: empty)
--   K.levelOk(cfg, playerLevel, monsterLevel)   false for a trivial monster
--   K.cooldownOk(st, ownerId, kind, cfg, now)   the per-killer, per-kind cooldown is over
--   K.noteDrop(st, ownerId, kind, now)          starts it
--   K.amount(cfg, kind, max, bonusPct)          what a globe restores
--   K.rollKinds(cfg, shares, tier, rand)        {health = bool, mana = bool} (rand(a, b) integers)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGlobesCore = ChaosGlobesCore or {}
local K = ChaosGlobesCore

function K.lowest(shares)
	local low
	for _, s in ipairs(shares or {}) do
		if s ~= nil and (low == nil or s < low) then
			low = s
		end
	end
	return low
end

-- the curve: points {share, pct}, highest share first
local function curveAt(points, share)
	if not points or #points == 0 or share == nil then
		return 0
	end
	if share >= points[1][1] then
		return 0
	end
	for i = 2, #points do
		local hi, lo = points[i - 1], points[i]
		if share >= lo[1] then
			local span = hi[1] - lo[1]
			local t = span > 0 and (hi[1] - share) / span or 1
			return hi[2] + (lo[2] - hi[2]) * t
		end
	end
	return points[#points][2]
end
K.curveAt = curveAt

function K.chance(cfg, kind, share, tier)
	if share == nil then
		return 0 -- the kind does not apply (no mana pool): no flat chance either
	end
	local flat = (cfg.flat or {})[tier or "normal"] or 0
	local pct = curveAt((cfg.curve or {})[kind], share) + flat
	return math.max(0, math.min(pct, cfg.maxChance or 100))
end

function K.levelOk(cfg, playerLevel, monsterLevel)
	local g = cfg.levelGap or {}
	playerLevel, monsterLevel = tonumber(playerLevel) or 1, tonumber(monsterLevel) or 0
	if monsterLevel <= 0 or playerLevel - monsterLevel <= (g.grace or 0) then
		return true
	end
	return monsterLevel / math.max(1, playerLevel) >= (g.minShare or 0)
end

function K.cooldownOk(st, ownerId, kind, cfg, now)
	local last = st[ownerId .. ":" .. kind]
	return last == nil or now - last >= ((cfg.cooldownMs or {})[kind] or 0)
end

function K.noteDrop(st, ownerId, kind, now)
	st[ownerId .. ":" .. kind] = now
end

function K.amount(cfg, kind, max, bonusPct)
	local pct = kind == "mana" and (cfg.manaPct or 0) or (cfg.healthPct or 0)
	local v = math.max(0, max or 0) * pct / 100 * (1 + math.max(0, bonusPct or 0) / 100)
	return math.max(1, math.floor(v + 0.5))
end

-- shares: {health = lowest health share or nil, mana = lowest mana share or nil}; one independent roll per kind,
-- resolution 1/10000 %
function K.rollKinds(cfg, shares, tier, rand)
	local out = {}
	for _, kind in ipairs({"health", "mana"}) do
		local pct = K.chance(cfg, kind, shares[kind], tier)
		out[kind] = pct > 0 and rand(1, 1000000) <= pct * 10000
	end
	return out
end

return K

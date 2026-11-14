-- mainquest_boss_attacks_core.lua: the rules of Vael Ashmourn's own attacks (O554; numbers: mainquest_boss_config.lua; glue:
-- mainquest_boss.lua; tests/mainquest_boss_attacks_test.lua; server/README.md "Vael's attacks (O554)"). Pure Lua, no engine
-- calls; every random number comes from the `rand(a, b)` argument (integer in [a, b]). The shapes are boss_mechanics_core.lua's
-- (G.shape), the walking and the fairness check too (G.makeFair, G.isFair).
-- Lua 5.1 / LuaJIT and 5.3.

if not (ChaosBossMechCore and ChaosBossMechCore.shape) then
	dofile("data/scripts/chaos/boss_mechanics_core.lua")
end

ChaosVaelAttacks = ChaosVaelAttacks or {}
local A = ChaosVaelAttacks
local G = ChaosBossMechCore

local floor, max, min = math.floor, math.max, math.min

function A.cfg()
	if not A.config then
		local ok, t = pcall(dofile, "data/scripts/chaos/mainquest_boss_config.lua")
		A.config = ok and type(t) == "table" and t or nil
	end
	return A.config
end

function A.byKey(cfg, key)
	for _, a in ipairs(cfg.attacks) do
		if a.key == key then
			return a
		end
	end
	return nil
end

-- the attacks of a phase (index into the boss's phases), in config order
function A.phaseList(cfg, phaseIdx)
	local out = {}
	for _, a in ipairs(cfg.attacks) do
		for _, p in ipairs(a.phases) do
			if p == phaseIdx then
				out[#out + 1] = a
				break
			end
		end
	end
	return out
end

-- the next attack of a phase: never the one just cast while another is in the phase's list
function A.pick(cfg, phaseIdx, lastKey, rand)
	local list = A.phaseList(cfg, phaseIdx)
	if #list == 0 then
		return nil
	end
	local pool = {}
	for _, a in ipairs(list) do
		if a.key ~= lastKey or #list == 1 then
			pool[#pool + 1] = a
		end
	end
	return pool[rand(1, #pool)]
end

-- the windup (ms) of an attack: its own, never below the config's minimum
function A.windMs(cfg, attack)
	return max(cfg.minWindMs, attack.windMs)
end

-- ms from the start of an attack to the start of the next: the phase's cadence (shorter when enraged), never less than the
-- windup of the attack just cast + the quiet time
function A.delayAfter(cfg, phaseIdx, enraged, attack)
	local every = cfg.every[min(max(1, phaseIdx), #cfg.every)]
	if enraged then
		every = floor(every * cfg.enrage.cadenceMult + 0.5)
	end
	return max(every, A.windMs(cfg, attack) + cfg.gapMs)
end

-- the tiles of an attack. ctx = {grid (G.grid of the walkable tiles), boss = {x, y, z}, target = {x, y, z} (the character Vael faces),
-- players = {{x, y, z}}, rand}. Returns {key, windMs, parts = {{kind, share, tiles, set}}, tiles (the union), set, fair, cut}.
-- Every part is made fair in turn (a pocket cut where a character has no safe tile in reach, the other parts counted as marked);
-- `fair` is the check of the union at the end: a plan that is not fair must not be cast.
function A.plan(cfg, attack, ctx)
	local wind = A.windMs(cfg, attack)
	local g = ctx.grid
	local parts = {}
	for i, spec in ipairs(attack.parts) do
		local tiles = G.shape(spec, {grid = g, boss = ctx.boss, size = 1, target = ctx.target, players = ctx.players,
			rand = ctx.rand, z = g.z})
		parts[i] = {kind = spec.kind, share = spec.share, tiles = tiles}
	end
	local straight, diag = G.stepCosts(cfg.fair)
	local budget = G.budget(wind, {reactionMs = cfg.reactionMs})
	local cut = 0
	local players = ctx.players or {}
	for i, part in ipairs(parts) do
		local others = {}
		for j, other in ipairs(parts) do
			if j ~= i then
				for k in pairs(G.tileSet(other.tiles)) do
					others[k] = true
				end
			end
		end
		local left, cutTiles = G.makeFair(g, part.tiles, players, budget, straight, diag, ctx.boss, others)
		part.tiles = left
		cut = cut + #cutTiles
	end
	local union, seen = {}, {}
	for _, part in ipairs(parts) do
		part.set = G.tileSet(part.tiles)
		for _, t in ipairs(part.tiles) do
			local k = G.key(t.x, t.y)
			if not seen[k] then
				seen[k] = true
				union[#union + 1] = t
			end
		end
	end
	local fair = G.isFair(g, union, players, budget, straight, diag, nil)
	return {key = attack.key, windMs = wind, parts = parts, tiles = union, set = seen, fair = fair, cut = cut}
end

-- the parts of a plan that hold a position (x, y)
function A.partsAt(plan, pos)
	local out = {}
	if not pos then
		return out
	end
	local k = G.key(pos.x, pos.y)
	for _, part in ipairs(plan.parts) do
		if part.set[k] then
			out[#out + 1] = part
		end
	end
	return out
end

-- the share of the maximum health a character at pos takes from the plan, before the resistance: the shares of the parts it stands in
-- (0 when it dodged), times the enrage's damage factor
function A.shareAt(cfg, plan, pos, enraged)
	local share = 0
	for _, part in ipairs(A.partsAt(plan, pos)) do
		share = share + part.share
	end
	if enraged then
		share = share * cfg.enrage.damageMult
	end
	return share
end

-- the share after the resistance of the phase's element and the tier's hit scale: the rule of mainquest_core.lua hitAmount (the result
-- after the penalty, at most `cap`, at least -100). scale = tier hit / the design hit the shares were written against (1 = as written)
function A.effectiveShare(share, scale, resistPct, cap)
	local r = tonumber(resistPct) or 0
	cap = tonumber(cap) or 75
	if r > cap then
		r = cap
	end
	if r < -100 then
		r = -100
	end
	return share * (tonumber(scale) or 1) * (1 - r / 100)
end

-- the longest windup and the biggest single hit of the table: the numbers the model holds
function A.limits(cfg)
	local minWind, maxShare = math.huge, 0
	for _, a in ipairs(cfg.attacks) do
		minWind = min(minWind, A.windMs(cfg, a))
		local s = 0
		for _, p in ipairs(a.parts) do
			s = s + p.share
		end
		maxShare = max(maxShare, s * cfg.enrage.damageMult)
	end
	return {minWind = minWind, maxShare = maxShare}
end

return A

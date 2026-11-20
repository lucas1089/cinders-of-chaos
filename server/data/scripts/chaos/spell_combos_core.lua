-- Spell combos, the pure rules (O686 phase 6; docs/SPELL_UPGRADES.md section 4; server/README.md "Spell combos (O686 phase 6)").
-- Two spells cast inside a window, on the same target or near the first one's hit, give the second spell's first hit a bonus of
-- 10% to 20% (the row of spell_combos_config.lua). This file knows no engine: the ring of the last casts of a player, the
-- match of a hit against the rows, the limits (same combo on the same target, the pause between combos), the element of a hit and
-- the numbers the model counts. The engine file spell_combos.lua feeds it. tests: server/tests/spell_combos_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSpellCombosCore = ChaosSpellCombosCore or {}
local C = ChaosSpellCombosCore
local abs, max, floor = math.abs, math.max, math.floor

-- ---------------------------------------------------------------- the config
-- the problems of a config table (empty when it is sound): every bonus in the band, every id once, specs well formed
function C.check(cfg)
	local bad = {}
	local band, seen = cfg.band, {}
	for i, row in ipairs(cfg.rows or {}) do
		local what = "row " .. i .. " " .. tostring(row.id)
		if type(row.id) ~= "string" or seen[row.id] then
			bad[#bad + 1] = what .. ": missing or repeated id"
		end
		seen[tostring(row.id)] = true
		if type(row.name) ~= "string" or type(row.pt) ~= "string" then
			bad[#bad + 1] = what .. ": name and pt are required"
		end
		if row.kind ~= "reaction" and row.kind ~= "class" and row.kind ~= "heal" then
			bad[#bad + 1] = what .. ": kind " .. tostring(row.kind)
		end
		if type(row.bonus) ~= "number" or row.bonus < band.min - 1e-9 or row.bonus > band.max + 1e-9 then
			bad[#bad + 1] = string.format("%s: bonus %s is outside %d%%..%d%%", what, tostring(row.bonus), band.min * 100, band.max * 100)
		end
		if type(row.weight) ~= "number" or row.weight <= 0 then
			bad[#bad + 1] = what .. ": weight"
		end
		for _, side in ipairs({"first", "second"}) do
			local s = row[side]
			if type(s) ~= "table" or ((s.element == nil) == (s.spells == nil)) then
				bad[#bad + 1] = what .. ": " .. side .. " needs an element or spells"
			elseif row.kind == "reaction" and not s.element then
				bad[#bad + 1] = what .. ": a reaction names elements"
			elseif row.kind ~= "reaction" and not s.spells then
				bad[#bad + 1] = what .. ": a signature or heal combo names spells"
			end
		end
	end
	return bad
end

-- the row by id
function C.row(cfg, id)
	for _, r in ipairs(cfg.rows) do
		if r.id == id then
			return r
		end
	end
	return nil
end

-- ---------------------------------------------------------------- numbers the model counts
-- the mean bonus of the rows weighted by `weight` (how often a typical rotation fires each)
function C.meanBonus(cfg)
	local sum, w = 0, 0
	for _, r in ipairs(cfg.rows) do
		sum = sum + r.bonus * r.weight
		w = w + r.weight
	end
	return w > 0 and sum / w or 0
end

-- the typical rotation's gain: the share of its spell damage on a combo hit x the mean bonus
function C.typicalGain(cfg)
	return cfg.model.triggerShare * C.meanBonus(cfg)
end

-- the best legal rotation: every counted hit a combo of the best row
function C.bestGain(cfg)
	local top = 0
	for _, r in ipairs(cfg.rows) do
		top = max(top, r.bonus)
	end
	return cfg.model.triggerShare * top
end

-- ---------------------------------------------------------------- the element of a hit
-- two parts of a hit (elements named or nil, damage as numbers) -> the element of the hit, or nil
function C.elementOf(e1, d1, e2, d2, cfg)
	d1, d2 = abs(d1 or 0), abs(d2 or 0)
	if e1 and d1 <= 0 then
		e1 = nil
	end
	if e2 and d2 <= 0 then
		e2 = nil
	end
	if not e1 or not e2 then
		return e1 or e2
	end
	local big, bigDmg, small, smallDmg = e1, d1, e2, d2
	if d2 > d1 then
		big, bigDmg, small, smallDmg = e2, d2, e1, d1
	end
	if big == "physical" and small ~= "physical" and smallDmg >= bigDmg * (cfg.elementShare or 0.25) then
		return small
	end
	return big
end

-- ---------------------------------------------------------------- the ring of a player
function C.newState()
	return {ring = {}, lastAt = nil, byTarget = {}}
end

-- one cast: the entry of the ring (target and position are what the cast knows: the player's target, else the player's tile)
function C.cast(state, cfg, spellId, now, targetId, pos)
	local ring = state.ring
	local entry = {spell = spellId, t = now, target = targetId, pos = pos, hit = false}
	ring[#ring + 1] = entry
	while #ring > cfg.ring.size do
		table.remove(ring, 1)
	end
	return entry
end

-- the entry of the cast a hit belongs to: the newest of that spell, when it has no hit yet and is younger than ring.expireMs
function C.current(state, cfg, spellId, now)
	for i = #state.ring, 1, -1 do
		local e = state.ring[i]
		if e.spell == spellId then
			if not e.hit and now - e.t <= cfg.ring.expireMs and now >= e.t then
				return e
			end
			return nil
		end
	end
	return nil
end

-- ---------------------------------------------------------------- matching
local function chebyshev(a, b)
	if not a or not b or a.z ~= b.z then
		return math.huge
	end
	return max(abs(a.x - b.x), abs(a.y - b.y))
end
C.dist = chebyshev

local function inList(list, v)
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

-- is a cast (an entry, with the element of its hit when it had one) the first side of a row?
local function isFirst(row, e)
	local f = row.first
	if f.element then
		return e.hit and e.element == f.element
	end
	return inList(f.spells, e.spell)
end

local function isSecond(row, h)
	local s = row.second
	if row.kind == "heal" then
		if not h.heal then
			return false
		end
	elseif h.heal then
		return false
	end
	if s.element then
		return h.element == s.element
	end
	return inList(s.spells, h.spell)
end

-- the first cast is on the same target, or its position is within window.nearSqm of the second hit
function C.near(cfg, e, h)
	if e.target and h.target and e.target == h.target then
		return true
	end
	return chebyshev(e.pos, h.pos) <= cfg.window.nearSqm
end

-- may this row fire now on this target (the limits of 4.1)?
function C.canFire(state, cfg, row, targetId, now)
	if state.lastAt and now - state.lastAt < cfg.limits.globalMs then
		return false
	end
	local t = state.byTarget[row.id .. ":" .. tostring(targetId)]
	return not (t and now - t < cfg.limits.repeatMs)
end

function C.fire(state, cfg, row, targetId, now)
	state.lastAt = now
	state.byTarget[row.id .. ":" .. tostring(targetId)] = now
	for k, t in pairs(state.byTarget) do
		if now - t >= cfg.limits.repeatMs then
			state.byTarget[k] = nil
		end
	end
end

-- the best row of the casts before `cur` against the hit h = {spell, now, element, heal, target, pos}; rankOf(spellId) -> rank
function C.find(state, cfg, cur, h, rankOf)
	local best
	for _, row in ipairs(cfg.rows) do
		if (not best or row.bonus > best.bonus) and isSecond(row, h) then
			local rankOk = row.kind == "reaction" or rankOf(h.spell) >= cfg.classMinRank
			if rankOk and C.canFire(state, cfg, row, h.target, h.now) then
				for _, e in ipairs(state.ring) do
					if e ~= cur and e.t <= cur.t and cur.t - e.t <= cfg.window.windowMs and isFirst(row, e) and C.near(cfg, e, h)
							and (row.kind == "reaction" or rankOf(e.spell) >= cfg.classMinRank) then
						best = row
						break
					end
				end
			end
		end
	end
	return best
end

-- The first hit of a cast. h = {spell, now, element, heal, target, pos, pvp, rankOf}. Returns the row that fired (or nil) and the
-- factor of the hit (1 + bonus, 1 when none). The entry of the cast is closed whatever happens: only its first hit asks.
function C.onHit(state, cfg, h)
	local cur = C.current(state, cfg, h.spell, h.now)
	if not cur then
		return nil, 1
	end
	cur.hit, cur.element, cur.target, cur.pos = true, h.element, h.target, h.pos
	if h.pvp then
		return nil, 1
	end
	local row = C.find(state, cfg, cur, h, h.rankOf or function() return 0 end)
	if not row then
		return nil, 1
	end
	C.fire(state, cfg, row, h.target, h.now)
	return row, 1 + row.bonus
end

-- a damage value (negative) or a heal (positive) scaled by a factor, rounded to a whole number away from zero by half
function C.apply(amount, factor)
	if factor == 1 then
		return amount
	end
	local v = amount * factor
	return v < 0 and -floor(-v + 0.5) or floor(v + 0.5)
end

return C

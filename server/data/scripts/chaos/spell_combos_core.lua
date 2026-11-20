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
	local best, bestEntry
	for _, row in ipairs(cfg.rows) do
		if (not best or row.bonus > best.bonus) and isSecond(row, h) then
			local rankOk = row.kind == "reaction" or rankOf(h.spell) >= cfg.classMinRank
			if rankOk and C.canFire(state, cfg, row, h.target, h.now) then
				for _, e in ipairs(state.ring) do
					if e ~= cur and e.t <= cur.t and cur.t - e.t <= cfg.window.windowMs and isFirst(row, e) and C.near(cfg, e, h)
							and (row.kind == "reaction" or rankOf(e.spell) >= cfg.classMinRank) then
						best, bestEntry = row, e
						break
					end
				end
			end
		end
	end
	return best, bestEntry
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
	local row, first = C.find(state, cfg, cur, h, h.rankOf or function() return 0 end)
	if not row then
		return nil, 1
	end
	C.fire(state, cfg, row, h.target, h.now)
	return row, 1 + row.bonus, first
end

-- a damage value (negative) or a heal (positive) scaled by a factor, rounded to a whole number away from zero by half
function C.apply(amount, factor)
	if factor == 1 then
		return amount
	end
	local v = amount * factor
	return v < 0 and -floor(-v + 0.5) or floor(v + 0.5)
end

-- ---------------------------------------------------------------- riders (O686 phase 6b)
-- row.fx = {kind = ..., ...} (spell_combos_config.lua `riders`): what a fired row does besides the bonus. The engine side is
-- spell_combos.lua; this file holds the rules that need no engine: the checks of the config, the counted gain, the amplifier factor of a
-- marked monster, the hooked set, the death burst budget, the heal over time window.
C.DAMAGE_KINDS = {burst = true, chain = true, deathburst = true}
C.KINDS = {burst = true, chain = true, deathburst = true, brittle = true, holyamp = true, slow = true, stun = true, hooked = true,
	hexrenew = true, hot = true, text = true}

-- the problems of the riders of a config (empty when sound): every row has a known kind, a damage rider is at most its row's bonus and
-- at most riders.maxShare, the timed ones have a time
function C.checkRiders(cfg)
	local bad = {}
	local R = cfg.riders
	if type(R) ~= "table" then
		return {"riders block missing"}
	end
	for _, row in ipairs(cfg.rows or {}) do
		local what = "row " .. tostring(row.id)
		local fx = row.fx
		if type(fx) ~= "table" or not C.KINDS[fx.kind] then
			bad[#bad + 1] = what .. ": fx kind " .. tostring(fx and fx.kind)
		else
			if C.DAMAGE_KINDS[fx.kind] then
				if type(fx.share) ~= "number" or fx.share <= 0 or fx.share > row.bonus + 1e-9 or fx.share > R.maxShare + 1e-9 then
					bad[#bad + 1] = what .. ": a damage rider is at most the row's bonus and " .. tostring(R.maxShare) .. " of the hit"
				end
				if fx.kind ~= "chain" and type(fx.cap) ~= "number" then
					bad[#bad + 1] = what .. ": a burst needs a cap"
				end
				if type(fx.radius) ~= "number" or fx.radius < 1 or fx.radius > 3 then
					bad[#bad + 1] = what .. ": radius 1 to 3"
				end
			end
			if (fx.kind == "brittle" or fx.kind == "holyamp" or fx.kind == "slow" or fx.kind == "stun" or fx.kind == "hot"
					or fx.kind == "deathburst") and type(fx.ms) ~= "number" then
				bad[#bad + 1] = what .. ": a timed rider needs ms"
			end
			if (fx.kind == "brittle" or fx.kind == "holyamp" or fx.kind == "hot") and (type(fx.pct) ~= "number" or fx.pct <= 0) then
				bad[#bad + 1] = what .. ": pct"
			end
			if fx.kind == "text" and not (R.why and R.why[fx.why]) then
				bad[#bad + 1] = what .. ": a text rider names its reason in riders.why"
			end
		end
	end
	return bad
end

-- the other enemies within `radius` of a target, as the model pictures a hunt (riders.model.near, radius 1..3)
local function nearCount(cfg, radius)
	local n = cfg.riders.model.near
	return n[max(1, math.min(3, floor(radius)))] or 0
end

-- the extra damage a row's rider counts for the typical rotation, in hits of the triggering hit (0.01 = 1% of that hit). Only what is
-- built counts; a text rider, a slow, a stun, a hex renewal and a heal over time add no damage to the model.
function C.riderGain(cfg, row)
	local fx, m = row.fx, cfg.riders.model
	if not fx then
		return 0
	end
	local k = fx.kind
	if k == "burst" then
		return fx.share * math.min(fx.cap, nearCount(cfg, fx.radius))
	elseif k == "chain" then
		return fx.share * math.min(fx.targets, nearCount(cfg, fx.radius))
	elseif k == "deathburst" then
		return fx.share * math.min(fx.cap, m.killsPerSecond * fx.ms / 1000) * math.min(fx.targets or 3, nearCount(cfg, fx.radius))
	elseif k == "brittle" then
		return fx.pct * (fx.ms / m.hitEveryMs)
	elseif k == "holyamp" then
		return fx.pct * (fx.ms / m.hitEveryMs) * m.holyShare
	end
	return 0
end

-- the weighted mean of the riders' counted gain over the rows
function C.meanRider(cfg)
	local sum, w = 0, 0
	for _, r in ipairs(cfg.rows) do
		sum = sum + C.riderGain(cfg, r) * r.weight
		w = w + r.weight
	end
	return w > 0 and sum / w or 0
end

-- the typical rotation's gain with the riders (bonus and riders on the combo hits)
function C.typicalWithRiders(cfg)
	return cfg.model.triggerShare * (C.meanBonus(cfg) + C.meanRider(cfg))
end

-- the best legal rotation fights one target: a rider that hits other enemies counts 0, an amplifier counts, a text rider counts 0
function C.bestWithRiders(cfg)
	local top = 0
	for _, r in ipairs(cfg.rows) do
		local k = r.fx and r.fx.kind
		local extra = (k == "brittle" or k == "holyamp") and C.riderGain(cfg, r) or 0
		top = max(top, r.bonus + extra)
	end
	return cfg.model.triggerShare * top
end

-- the amount of a rider hit: `share` of the triggering hit (a whole number, at least 1 for a hit that deals anything)
function C.riderAmount(share, hit)
	hit = abs(hit or 0)
	if hit <= 0 or not share or share <= 0 then
		return 0
	end
	return max(1, floor(hit * share + 0.5))
end

-- ---------------------------------------------------------------- the marks on a monster (brittle, holy)
-- marks = {brittle = {untilMs, pct}, holy = {untilMs, pct}} -> the factor of one damage part (`isHoly`: it is holy damage) at `now`;
-- an expired mark is dropped
function C.markFactor(marks, now, isHoly)
	if not marks then
		return 1
	end
	local f = 1
	for _, key in ipairs({"brittle", "holy"}) do
		local m = marks[key]
		if m then
			if m.untilMs < now then
				marks[key] = nil
			elseif key == "brittle" or isHoly then
				f = f * (1 + m.pct)
			end
		end
	end
	return f
end

-- sets a mark; a stronger or later one replaces, the same time never stacks
function C.setMark(marks, key, now, ms, pct)
	local m = marks[key]
	if not m or m.untilMs < now or pct >= m.pct then
		marks[key] = {untilMs = now + ms, pct = pct}
	end
end

-- ---------------------------------------------------------------- the hooked set, the death marks, the heal over time
-- the ids of every enemy the first spell hit, noted on its ring entry (at most 8)
function C.noteHit(state, spellId, now, targetId, windowMs)
	for i = #state.ring, 1, -1 do
		local e = state.ring[i]
		if e.spell == spellId then
			if targetId and now - e.t <= windowMs and now >= e.t then
				e.ids = e.ids or {}
				if #e.ids < 8 then
					e.ids[#e.ids + 1] = targetId
				end
			end
			return
		end
	end
end

-- a fired `hooked` row remembers the enemies the first cast hit: its entry's ids and target, the second spell, until `now + ms`
function C.hook(state, row, firstEntry, secondSpell, now, ms)
	local ids = {}
	for _, id in ipairs(firstEntry.ids or {}) do
		ids[id] = true
	end
	if firstEntry.target then
		ids[firstEntry.target] = true
	end
	state.hooked = {row = row, ids = ids, spell = secondSpell, untilMs = now + ms}
end

-- the factor of a later hit of the second spell on an enemy the hook hit (once for each enemy); 1 when none
function C.hookedFactor(state, spellId, targetId, now)
	local h = state.hooked
	if not h then
		return 1
	end
	if now > h.untilMs then
		state.hooked = nil
		return 1
	end
	if h.spell == spellId and targetId and h.ids[targetId] then
		h.ids[targetId] = nil
		return 1 + h.row.bonus
	end
	return 1
end

-- a death mark: the next `fx.ms` of kills burst, at most `fx.cap` bursts. Returns the mark.
function C.deathMark(state, fx, now, amount, ctype)
	state.death = {untilMs = now + fx.ms, left = fx.cap, share = fx.share, radius = fx.radius, targets = fx.targets or 3, amount = amount, ctype = ctype}
	return state.death
end

-- a kill inside the window: the mark when a burst is due (and one is used), else nil
function C.deathDue(state, now)
	local d = state.death
	if not d then
		return nil
	end
	if now > d.untilMs or d.left <= 0 then
		state.death = nil
		return nil
	end
	d.left = d.left - 1
	return d
end

-- a heal over time window: the second spell's heals are x(1 + pct) until `now + fx.ms`
function C.hotStart(state, row, spellId, now)
	state.hot = {spell = spellId, untilMs = now + row.fx.ms, pct = row.fx.pct}
end

function C.hotFactor(state, spellId, now)
	local h = state.hot
	if not h then
		return 1
	end
	if now > h.untilMs then
		state.hot = nil
		return 1
	end
	return h.spell == spellId and (1 + h.pct) or 1
end

-- ---------------------------------------------------------------- combo masteries (O686 phase 6b)
-- the choice row of an id (nil for none or an unknown id)
function C.masteryChoice(cfg, id)
	id = tonumber(id)
	if not id then
		return nil
	end
	for _, c in ipairs(cfg.masteries.choices) do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- a config as one player has it with a combo mastery: the window, the repeat pause and the pause between combos moved, never under
-- masteries.floor. Without a choice the config itself.
function C.effective(cfg, choice)
	if not choice then
		return cfg
	end
	local fl = cfg.masteries.floor
	local eff = {}
	for k, v in pairs(cfg) do
		eff[k] = v
	end
	eff.window = {windowMs = cfg.window.windowMs + (choice.windowMs or 0), nearSqm = cfg.window.nearSqm}
	eff.limits = {repeatMs = max(fl.repeatMs, cfg.limits.repeatMs + (choice.repeatMs or 0)),
		globalMs = max(fl.globalMs, cfg.limits.globalMs + (choice.globalMs or 0))}
	return eff
end

-- the model's count of one mastery: the typical gain with the riders x the relative share it adds
function C.masteryGain(cfg, choice)
	return C.typicalWithRiders(cfg) * choice.shareGain
end

return C

-- Spell ranks (O686 phase 2): pure logic, no engine call. Numbers: spell_ranks_config.lua; engine: spell_ranks.lua;
-- design: docs/SPELL_UPGRADES.md; tests: server/tests/spell_ranks_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   Spell Points (SP): K = kill value in hours = min(clampHours, E / refXpPerHour(level)); a spell's SP = K x its credit share.
--   The share is the spell's part of the damage the character dealt to that monster (P.shares); a heal pool takes 20% when
--   a heal mattered just before the kill. A rank r costs c x r^1.5 SP x the spell's needScale; a spell far below the best
--   spell of its weight earns x2; the account echo gives a floor.

ChaosSpellRanksCore = ChaosSpellRanksCore or {}
local P = ChaosSpellRanksCore

local floor, min, max = math.floor, math.min, math.max

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return v
end

-- linear between points {x, y}, flat outside; defaultBelow: the value below the first point (nil: the first point's)
function P.interp(points, x, defaultBelow)
	if not points or #points == 0 then
		return defaultBelow
	end
	x = num(x, 0)
	if x < points[1][1] then
		if defaultBelow ~= nil then
			return defaultBelow
		end
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if x <= b[1] then
			if b[1] == a[1] then
				return b[2]
			end
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

-- ---------------------------------------------------------------- the cost curve
local costCache = setmetatable({}, {__mode = "k"})

local function curve(cfg)
	local c = costCache[cfg]
	if c then
		return c
	end
	local exp = num(cfg.cost and cfg.cost.exp, 1.5)
	local total = num(cfg.cost and cfg.cost.totalSp, 42)
	local n = cfg.maxRank or 20
	local sum = 0
	for r = 1, n do
		sum = sum + r ^ exp
	end
	local k = total / sum
	c = {cost = {}, cum = {[0] = 0}}
	for r = 1, n do
		c.cost[r] = k * r ^ exp
		c.cum[r] = c.cum[r - 1] + c.cost[r]
	end
	costCache[cfg] = c
	return c
end

-- SP of rank r (1..maxRank) for a spell of weight 1
function P.rankCost(r, cfg)
	return curve(cfg).cost[floor(num(r, 0))] or 0
end

-- SP of all ranks up to r, weight 1
function P.cumCost(r, cfg)
	r = max(0, min(cfg.maxRank or 20, floor(num(r, 0))))
	return curve(cfg).cum[r]
end

-- rank, SP into the next rank, SP the next rank costs (0 at the top) for `sp` SP on a spell of weight `scale`
function P.rankOf(sp, scale, cfg)
	scale = num(scale, 1)
	if scale <= 0 then
		scale = 1
	end
	sp = max(0, num(sp, 0))
	local c = curve(cfg)
	local top = cfg.maxRank or 20
	local rank = 0
	for r = 1, top do
		if sp + 1e-9 >= c.cum[r] * scale then
			rank = r
		else
			break
		end
	end
	if rank >= top then
		return top, 0, 0
	end
	return rank, sp - c.cum[rank] * scale, c.cost[rank + 1] * scale
end

-- SP that is needed in all to hold rank r on a spell of weight `scale`
function P.spForRank(r, scale, cfg)
	return P.cumCost(r, cfg) * num(scale, 1)
end

-- ---------------------------------------------------------------- weight of a spell
-- meta {heal = bool, cooldownMs = n}: the weight class key and the needScale
function P.weight(meta, cfg)
	local n = cfg.needScale
	meta = meta or {}
	if meta.heal then
		return "heal", n.heal
	end
	local cd = num(meta.cooldownMs, 0)
	if n.ultimate and cd >= n.ultimate.minCooldownMs then
		return "ultimate", n.ultimate.scale
	end
	for i, band in ipairs(n.bands or {}) do
		if cd <= band[1] then
			return "band" .. i, band[2]
		end
	end
	return "default", n.default or 1
end

-- ---------------------------------------------------------------- kill value
function P.refXp(level, cfg)
	return P.interp(cfg.refXpPerHour, level) or 1
end

-- hours of on-level hunting one kill is worth, clamped; E = the kill's base experience
function P.killValue(E, level, cfg)
	E = num(E, 0)
	if E <= 0 then
		return 0
	end
	local ref = P.refXp(level, cfg)
	if ref <= 0 then
		return 0
	end
	return min(num(cfg.clampHours, 0.05), E / ref)
end

-- does a kill count at all? ctx {tester, level, pvp, monsterMaster (a summon or clone), exp (the kill's experience)}
function P.counts(ctx, cfg)
	if ctx.tester and not cfg.testersEarn then
		return false, "tester"
	end
	if ctx.pvp then
		return false, "pvp"
	end
	if ctx.monsterMaster then
		return false, "summon"
	end
	if num(ctx.level, 0) < num(cfg.minLevel, 0) then
		return false, "level"
	end
	if num(ctx.exp, 0) <= 0 then
		return false, "noexp"
	end
	return true
end

-- ---------------------------------------------------------------- damage records
function P.newRecord()
	return {total = 0, spells = {}, n = 0}
end

-- which spell id a hit is credited to: the spell in the cast context (a direct hit, a tick of its dot, an extra hit that rides
-- on it, a Form or combo hit), else the spell a summon is named for, else 0 (an auto attack or weapon hit: in the
-- denominator, earns nothing). hit {spellId, summon = lowercase name or nil}
function P.creditSpell(hit, cfg)
	local id = num(hit.spellId, 0)
	if id > 0 then
		return id
	end
	if hit.summon then
		return (cfg.credit.summonSpells or {})[tostring(hit.summon):lower()] or 0
	end
	return 0
end

-- add damage to a record: the total always, the spell's bucket when it has room (at most maxSpellsPerMonster ids)
function P.record(rec, spellId, amount, cfg)
	amount = num(amount, 0)
	if amount <= 0 then
		return
	end
	rec.total = rec.total + amount
	spellId = num(spellId, 0)
	if spellId <= 0 then
		return
	end
	local cur = rec.spells[spellId]
	if cur then
		rec.spells[spellId] = cur + amount
	elseif rec.n < (cfg.credit.maxSpellsPerMonster or 16) then
		rec.spells[spellId] = amount
		rec.n = rec.n + 1
	end
end

-- one heal into a list kept per healer: {spell, amount, allyMax, at}; the list is cut to the window at every call
function P.recordHeal(list, spellId, effective, allyMax, nowMs, cfg)
	local window = cfg.credit.healWindowMs
	local keep = {}
	for _, h in ipairs(list) do
		if nowMs - h.at <= window then
			keep[#keep + 1] = h
		end
	end
	effective = num(effective, 0)
	if effective > 0 and num(spellId, 0) > 0 then
		keep[#keep + 1] = {spell = spellId, amount = effective, allyMax = num(allyMax, 0), at = nowMs}
	end
	if #keep > 64 then
		table.remove(keep, 1)
	end
	return keep
end

-- The credit split of one kill for one character: spell id -> fraction of K.
--   rec          the character's damage record on the monster (P.record)
--   monsterMax   the monster's maximum health
--   heals        the character's heal list (P.recordHeal), or nil
--   nowMs        the kill time
--   eligible     function(spell id) -> bool (only ranked spells earn; the rest stay in the denominator)
-- A character under minHealthShare of the monster's health earns nothing from damage (no leeching). Qualifying heals (>= healMinShare
-- of the ally's health, inside the window) take healPool of K, split by effective healing; with none, damage keeps 100%.
function P.shares(rec, monsterMax, heals, nowMs, eligible, cfg)
	local out = {}
	local c = cfg.credit
	local healTotal, healBy = 0, {}
	if heals then
		for _, h in ipairs(heals) do
			if nowMs - h.at <= c.healWindowMs and h.allyMax > 0 and h.amount >= c.healMinShare * h.allyMax
					and (not eligible or eligible(h.spell)) then
				healBy[h.spell] = (healBy[h.spell] or 0) + h.amount
				healTotal = healTotal + h.amount
			end
		end
	end
	local damagePart = 1
	if healTotal > 0 then
		damagePart = 1 - c.healPool
		for id, amount in pairs(healBy) do
			out[id] = (out[id] or 0) + c.healPool * amount / healTotal
		end
	end
	if rec and rec.total > 0 and num(monsterMax, 0) > 0 and rec.total >= c.minHealthShare * monsterMax then
		for id, dmg in pairs(rec.spells) do
			if not eligible or eligible(id) then
				out[id] = (out[id] or 0) + damagePart * dmg / rec.total
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- catch-up and echo
-- the multiplier of a spell of rank `rank` when the best rank among spells of its weight is `best`
function P.catchUp(rank, best, cfg)
	local c = cfg.catchUp
	if c and num(best, 0) - num(rank, 0) > c.ranksBelow then
		return c.mult
	end
	return 1
end

-- the floor rank the account echo gives on a spell whose best rank on the account is `best`
function P.echoFloor(best, cfg)
	local e = cfg.echo
	if not e then
		return 0
	end
	return min(e.maxFloor, floor(e.share * max(0, num(best, 0))))
end

-- the best rank of an account on a spell after a rank was reached: new best, and whether it changed
function P.echoBest(best, rank)
	best, rank = num(best, 0), num(rank, 0)
	if rank > best then
		return rank, true
	end
	return best, false
end

-- the SP a spell holds with the echo floor applied
function P.withFloor(sp, floorRank, scale, cfg)
	return max(num(sp, 0), P.spForRank(floorRank, scale, cfg))
end

-- ---------------------------------------------------------------- awarding
-- SP gained by one spell from one kill: K x share x catch-up; the SP never go past the cost of the top rank
function P.gain(K, share, mult, scale, sp, cfg)
	local g = num(K, 0) * num(share, 0) * num(mult, 1)
	if g <= 0 then
		return 0
	end
	local top = P.spForRank(cfg.maxRank or 20, scale, cfg)
	return max(0, min(g, top - num(sp, 0)))
end

-- ---------------------------------------------------------------- what a rank gives (design 1.5)
local function kindOf(isHeal, cfg)
	return isHeal and cfg.effects.heal or cfg.effects.damage
end

-- the multiplier on a hit or a heal at `rank`; pvp: the hit is on another player (half, owner 2026-11-20)
function P.power(rank, isHeal, pvp, cfg)
	rank = max(0, min(cfg.maxRank or 20, num(rank, 0)))
	local delta = rank * kindOf(isHeal, cfg).power / 100
	if pvp then
		delta = delta * cfg.pvp.rank
	end
	return 1 + delta
end

function P.cooldownMult(rank, isHeal, cfg)
	local e = cfg.effects
	local steps = 0
	for _, r in ipairs(e.cdRanks) do
		if rank >= r then
			steps = steps + 1
		end
	end
	return 1 - steps * kindOf(isHeal, cfg).cooldownPerStep / 100
end

function P.manaMult(rank, isHeal, cfg)
	rank = max(0, min(cfg.maxRank or 20, num(rank, 0)))
	return 1 - rank * kindOf(isHeal, cfg).mana / 100
end

-- a cooldown in ms after the rank's cut; never below minCooldownMs unless it was shorter to begin with
function P.cooldown(ms, rank, isHeal, cfg)
	ms = num(ms, 0)
	if ms <= 0 or rank <= 0 then
		return ms
	end
	local cut = floor(ms * P.cooldownMult(rank, isHeal, cfg))
	return max(min(ms, cfg.effects.minCooldownMs), cut)
end

function P.mana(mana, rank, isHeal, cfg)
	mana = num(mana, 0)
	if mana <= 0 or rank <= 0 then
		return mana
	end
	return floor(mana * P.manaMult(rank, isHeal, cfg))
end

-- ---------------------------------------------------------------- packed state (design 7.1): one storage a spell
-- bits 0-4 rank, 5-6 Form I pick, 7-8 Form II pick, 9 awakened
function P.pack(rank, form1, form2, awakened)
	return floor(num(rank, 0)) + 32 * floor(num(form1, 0)) + 128 * floor(num(form2, 0)) + (awakened and 512 or 0)
end

function P.unpack(v)
	v = floor(num(v, 0))
	if v < 0 then
		v = 0
	end
	return v % 32, floor(v / 32) % 4, floor(v / 128) % 4, floor(v / 512) % 2 == 1
end

-- ---------------------------------------------------------------- retire, class change, reset (design 1.6)
-- does a stored block version clear the id? (a reassigned id)
function P.reassignedClears(spellId, storedVersion, cfg)
	local need = (cfg.reassigned or {})[spellId]
	return need ~= nil and num(storedVersion, 0) < need
end

-- after a class or ascension change: ranks stay; the ids the new class does not know (known: set of spell ids) are dormant
function P.dormant(ranks, known)
	local out = {}
	for id, rank in pairs(ranks) do
		if rank > 0 and not known[id] then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

-- the storage range the tutorial reset clears (the passive tree reset never touches it)
function P.resetRange(cfg)
	return cfg.storage.base, cfg.storage.last
end

-- ---------------------------------------------------------------- monster health (design 5.3)
-- 1 below the first point (level 100)
function P.healthFactor(level, cfg)
	return P.interp(cfg.health, level, 1) or 1
end

return P

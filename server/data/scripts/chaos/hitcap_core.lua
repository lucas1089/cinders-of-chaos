-- Hit caps, pure logic (O478 rift guardian, O483 Nemesis and Reflective monsters). Tests: server/tests/hitcap_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Loaded by rift_core.lua, rift.lua, nemesis.lua and monster_tiers.lua (any order:
-- the global is only created once, so the registry of sources survives a second dofile).
--
-- * pool: what a ceiling is a share of. The maximum health plus, while a mana shield is up, the maximum mana (the energy shield
--   is not in it). Maximum values, so a ceiling does not fall as a character loses health.
-- * cut: one hit cut to share x pool as a whole (health part and mana part together, `spent` = what an earlier part of the
--   same hit already took). A hit is only cut, never scaled up.
-- * sources: who is capped. The two cap events of rift.lua (ChaosRiftHitCapHealth / ChaosRiftHitCapMana, the last health and
--   mana events of the player) ask every source "is this attacker capped on this victim, and with which share?". A source is a
--   function (attacker, victim) -> share or nil. The rift guardian is the first source (rift.lua), the Nemesis the second
--   (nemesis.lua). The smallest share wins.
-- * reflect: the amount a Reflective monster sends back for one hit (share of what landed, then at most perHit x pool and at
--   most perSecond x pool in a second, summed over the reflects of that second on the same character).

ChaosHitCapCore = ChaosHitCapCore or {}
local H = ChaosHitCapCore
local floor = math.floor

function H.pool(maxHealth, maxMana, shieldUp)
	return math.max(0, maxHealth or 0) + (shieldUp and math.max(0, maxMana or 0) or 0)
end

-- p, s = the two parts of a hit (damage is negative in the events: the sign is kept, the magnitude is |p| + |s|).
-- Returns p, s, limit, capped. limit = the most this call may let through (share x pool less `spent`, at least 0);
-- capped = true when the hit was cut. Both parts take the same factor and round down, so their sum is at most the limit.
function H.cut(share, p, s, pool, spent)
	p, s = p or 0, s or 0
	if not share or (pool or 0) <= 0 then
		return p, s, nil, false
	end
	local limit = math.max(0, floor(share * pool) - (spent or 0))
	local ap, as = math.abs(p), math.abs(s)
	local total = ap + as
	if total <= limit then
		return p, s, limit, false
	end
	local k = limit / total
	local np, ns = floor(ap * k), floor(as * k)
	return p < 0 and -np or np, s < 0 and -ns or ns, limit, true
end

-- ------------------------------------------------------------------ sources
ChaosHitCap = ChaosHitCap or {sources = {}, order = {}}
local S = ChaosHitCap
S.sources, S.order = S.sources or {}, S.order or {}

-- key: a name (a second call with the same key replaces the function, so a reload adds nothing)
function S.setSource(key, fn)
	if S.sources[key] == nil then
		S.order[#S.order + 1] = key
	end
	S.sources[key] = fn
end

-- the share that caps a hit of `attacker` on `victim`, or nil when no source caps it. A source that fails counts as "not capped"
-- (an error never breaks a hit).
function S.shareOf(attacker, victim)
	local best
	for _, key in ipairs(S.order) do
		local fn = S.sources[key]
		if fn then
			local ok, share = pcall(fn, attacker, victim)
			share = ok and tonumber(share) or nil
			if share and (not best or share < best) then
				best = share
			end
		end
	end
	return best
end

-- ------------------------------------------------------------------ reflect
-- cap = {enabled, perHit, perSecond} (monster_tiers.lua reflectCap). landed = the hit's damage, monsterHealth = the monster's
-- health before it, pool = the attacker's pool, spent = what the same character already got back in the last second.
-- share = the modifier's own share (0.15). Returns the amount to send back (>= 0, a whole number).
function H.reflectAmount(share, cap, landed, monsterHealth, pool, spent)
	local raw = floor(math.min(math.abs(landed or 0), math.max(0, monsterHealth or 0)) * (share or 0))
	if raw <= 0 or not (cap and cap.enabled) or (pool or 0) <= 0 then
		return math.max(0, raw)
	end
	local perHit = floor((cap.perHit or 1) * pool)
	local perSecond = math.max(0, floor((cap.perSecond or 1) * pool) - (spent or 0))
	return math.max(0, math.min(raw, perHit, perSecond))
end

-- the reflects of one second per character: list = {{t = ms, a = amount}, ...} (a table the caller keeps per victim).
-- Entries older than windowMs fall out; returns the sum of the rest.
function H.spentIn(list, now, windowMs)
	local sum, keep = 0, 1
	for i = 1, #list do
		local e = list[i]
		if now - e.t < windowMs then
			list[keep] = e
			keep = keep + 1
			sum = sum + e.a
		end
	end
	for i = #list, keep, -1 do
		list[i] = nil
	end
	return sum
end

function H.spend(list, now, amount)
	if amount > 0 then
		list[#list + 1] = {t = now, a = amount}
	end
end

return H

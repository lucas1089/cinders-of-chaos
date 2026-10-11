-- healing_rules_core.lua: the healer rules (docs/CLASSES.md: the Illusionist is the best healer, plus party attack
-- buffs). Every number is in ChaosHealing.cfg below; the functions after it need no engine:
--   * Weaver's Grace (Illusionist passive): heals the Illusionist casts on another player are stronger.
--   * Mirror Mend (Illusionist spell 96): heals the most hurt party member, a mirror image heals the next one.
--   * Lucid Reverie (Illusionist spell 97): a heal over time on every party member around the Illusionist.
--   * PvP healing reduction (everyone): a player in PvP combat (hit by or hitting a player in the last few seconds,
--     fight-locked by a player attack, inside an arena match or the siege arena) receives less healing.
--
-- Pure: no engine calls. Loaded by data/scripts/chaos/healing_rules.lua (scripts Lua state, the onHealthChange
-- rules) and by the two spells (spells Lua state). Unit tests: server/tests/healing_rules_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Times are milliseconds of the caller's clock (os.mtime on the server).

ChaosHealing = ChaosHealing or {}
local M = ChaosHealing

M.cfg = {
	ids = {
		-- the classes that get Weaver's Grace (server vocation ids: 10 = Illusionist)
		healerVocations = {[10] = true},
		-- spell ids (below 256: the cooldown packet sends one byte; free in the base server, the client and the Chaos
		-- block; not in the ranges reserved for the class lines: 63-74, 180-191, 198-199, 200-253)
		spell = {mirrorMend = 96, lucidReverie = 97}
	},
	-- Weaver's Grace: heals the Illusionist casts on another creature (a party member, any player) x (1 + othersBonus);
	-- its own self heals are unchanged
	weaversGrace = {othersBonus = 0.16}, -- 0.05 until the role rebalance: kept the Illusionist >= 12% over the Iron Sage
	-- Mirror Mend: heal = level x level + magic level x ml + base (min..max) on the party member within range with the
	-- lowest health share (or the one named); the mirror heals the next most hurt (the Illusionist included) for
	-- `mirror` of it. Without a hurt party member it heals the Illusionist.
	mirrorMend = {range = 7, mirror = 0.25, level = 0.3, mlMin = 11, mlMax = 17, baseMin = 40, baseMax = 80},
	-- Lucid Reverie: every party member within range (and the Illusionist) is healed `pulses` times, every intervalMs,
	-- a pulse = level x level + magic level x ml + base; a member farther than followRange (or on another floor) misses
	-- the pulse
	lucidReverie = {range = 7, followRange = 10, pulses = 5, intervalMs = 2000, level = 0.16, mlMin = 0.9, mlMax = 1.3,
		baseMin = 10, baseMax = 20},
	-- PvP: healing a player receives while in PvP combat is x healingTaken. A player is in PvP combat for windowMs after
	-- a player (or a player's summon) damaged it or it damaged a player, while it is fight-locked (isPzLocked), and
	-- while it is in an arena match or in the siege arena during a match.
	pvp = {healingTaken = 0.70, windowMs = 10000}
}

-- heal formula of the spells: min, max (positive)
function M.values(level, magicLevel, spec)
	local l = (level or 0) * spec.level
	local m = magicLevel or 0
	return l + m * spec.mlMin + spec.baseMin, l + m * spec.mlMax + spec.baseMax
end

-- the healing multiplier of one heal: h = {healerVoc, selfHeal, pvp}
function M.healMultiplier(h)
	local c = M.cfg
	local m = 1
	if not h.selfHeal and c.ids.healerVocations[h.healerVoc or -1] then
		m = m * (1 + c.weaversGrace.othersBonus)
	end
	if h.pvp then
		m = m * c.pvp.healingTaken
	end
	return m
end

-- scale a heal value keeping its sign, rounding toward zero
function M.scale(v, m)
	local a = math.floor(math.abs(v * m) + 1e-6)
	return v < 0 and -a or a
end

local function share(c)
	if (c.maxHealth or 0) <= 0 then
		return 1
	end
	return c.health / c.maxHealth
end

-- candidates {id, health, maxHealth} sorted by health share (lowest first, ties: lowest id)
function M.byNeed(candidates)
	local list = {}
	for _, c in ipairs(candidates) do
		list[#list + 1] = c
	end
	table.sort(list, function(a, b)
		local sa, sb = share(a), share(b)
		if sa ~= sb then
			return sa < sb
		end
		return a.id < b.id
	end)
	return list
end

-- Mirror Mend targets: candidates = the party members in range and the caster ({id, health, maxHealth}).
-- primary: the named id when given (it must be a candidate), else the most hurt member other than the caster (a member
-- at full health only when nobody is hurt), else the caster. mirror: the next most hurt candidate (the caster
-- included) that is not at full health, or nil.
function M.mirrorTargets(candidates, casterId, namedId)
	local sorted = M.byNeed(candidates)
	local primary
	if namedId then
		for _, c in ipairs(sorted) do
			if c.id == namedId then
				primary = c
			end
		end
		if not primary then
			return nil, nil
		end
	else
		for _, c in ipairs(sorted) do
			if c.id ~= casterId and c.health < c.maxHealth then
				primary = c
				break
			end
		end
		if not primary then
			for _, c in ipairs(sorted) do
				if c.id == casterId then
					primary = c
				end
			end
		end
	end
	if not primary then
		return nil, nil
	end
	for _, c in ipairs(sorted) do
		if c.id ~= primary.id and c.health < c.maxHealth then
			return primary.id, c.id
		end
	end
	return primary.id, nil
end

-- ------------------------------------------------------------------ PvP combat state (per player id, in memory)
M.pvpState = M.pvpState or {}

function M.markPvp(state, id, now)
	state[id] = now + M.cfg.pvp.windowMs
end

function M.recentPvp(state, id, now)
	local untilTime = state[id]
	if not untilTime then
		return false
	end
	if untilTime < now then
		state[id] = nil
		return false
	end
	return true
end

return M

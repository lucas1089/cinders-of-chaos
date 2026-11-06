-- spell_factor_core.lua: the class factor on spell damage (numbers: spell_factor_config.lua; server/README.md "Class spell
-- factor"). Pure: no engine call. Tests: server/tests/spell_factor_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- What it scales: damage (not healing) a player deals with origin ORIGIN_SPELL, the origin of every spell hit, its
-- pulses and scripted strikes (Combat:execute and doTargetCombat in the spell scripts). What it leaves alone:
--   * weapon and auto-attack hits (ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND) and conditions (ORIGIN_CONDITION: burns,
--     poisons and rots tick unscaled);
--   * keystone, support and archetype procs (ChaosKeystones.depth > 0): a share of a hit that already had the factor;
--   * damage dealt inside F.guard: hits that use ORIGIN_SPELL but are no spell of the class's damage model, the Templar
--     line's holy strike on a weapon hit (templar_combat.lua) and the Necromancer line's minion hits
--     (necro_minions.lua; the rotation model has no minions). The Beastmaster's companion bites are ORIGIN_NONE (no
--     event sees them); Feral Command and Pack Frenzy are spells and take the factor;
--   * healing of every kind.
-- Runes: the engine gives a rune's hit ORIGIN_SPELL too, so a rune used by a listed class takes its factor
-- (onHealthChange cannot tell a rune from an instant).

ChaosSpellFactor = ChaosSpellFactor or {}
local F = ChaosSpellFactor
F.depth = F.depth or 0

-- the factor of vocation `vocId` (1 when not listed) for a player of `level`: a class with a byLevel curve (O136) gets
-- the value on it (flat below the first point, linear between points, the last point's value above it) when the level is
-- known, else the byVocation value (the end of the curve)
function F.forVocation(vocId, cfg, level)
	cfg = cfg or ChaosSpellFactorConfig
	local id = tonumber(vocId) or -1
	local pts = level and cfg and cfg.byLevel and cfg.byLevel[id]
	if pts and #pts > 0 then
		if level <= pts[1][1] then
			return pts[1][2]
		end
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			if level <= b[1] then
				return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
			end
		end
		return pts[#pts][2]
	end
	local v = cfg and cfg.byVocation and cfg.byVocation[id]
	return v or 1
end

-- O430 (2026-11-06, owner: balance the classes far from the median DPS): the extra target factor. A spell cast that hits
-- several targets deals its damage to the first target at the class factor above and to every other target of the same cast
-- at the class factor x the extra target factor (spell_factor_config.lua `extra`: {level, factor} points like byLevel,
-- 1 for a class without one). It is the one lever that moves a class's pack damage and its single target damage apart:
-- a single-target class (Deadeye, Ranger) gets a factor above 1, an area caster (Mystic, Elementalist) below it.
function F.extraFor(vocId, cfg, level)
	cfg = cfg or ChaosSpellFactorConfig
	local pts = cfg and cfg.extra and cfg.extra[tonumber(vocId) or -1]
	if not pts or #pts == 0 or not level then
		return 1
	end
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- the extra target factor of one damage value: the same rule as F.factor (ORIGIN_SPELL damage, not healing, not a proc, not
-- guarded) and the vocation's `extra` curve at the level
function F.extra(vocId, origin, combatType, spellOrigin, healingType, procActive, cfg, level)
	if procActive or F.depth > 0 then
		return 1
	end
	if spellOrigin == nil or origin ~= spellOrigin or not combatType or combatType == 0 or combatType == healingType then
		return 1
	end
	return F.extraFor(vocId, cfg, level)
end

-- Is this hit on another target than the first one of the same cast? One cast deals all its hits inside one engine loop (the
-- same millisecond, well inside windowMs); the first target hit by an attacker after a quiet windowMs is the cast's first
-- target, and every later hit inside the window on another creature is an extra one (a second companion's hit on the first
-- target is not). state: a table kept by the caller { [attackerId] = { t, first } }; nowMs: the engine clock in ms
F.EXTRA_WINDOW_MS = 25
function F.additionalTarget(state, attackerId, targetId, nowMs, windowMs)
	windowMs = windowMs or F.EXTRA_WINDOW_MS
	local s = state[attackerId]
	if not s or nowMs - s.t > windowMs then
		state[attackerId] = {t = nowMs, first = targetId}
		return false
	end
	return targetId ~= s.first
end

-- the factor on one damage value: the vocation, origin and combat type of the hit; spellOrigin / healingType are the
-- engine's ORIGIN_SPELL and COMBAT_HEALING; procActive = a keystone proc is running
function F.factor(vocId, origin, combatType, spellOrigin, healingType, procActive, cfg, level)
	if procActive or F.depth > 0 then
		return 1
	end
	if spellOrigin == nil or origin ~= spellOrigin or not combatType or combatType == 0 or combatType == healingType then
		return 1
	end
	return F.forVocation(vocId, cfg, level)
end

-- run fn(...) with the factor off (an ORIGIN_SPELL hit that is not the class's spell damage); returns pcall's results
function F.guard(fn, ...)
	F.depth = F.depth + 1
	local res = {pcall(fn, ...)}
	F.depth = F.depth - 1
	return (table.unpack or unpack)(res)
end

return F

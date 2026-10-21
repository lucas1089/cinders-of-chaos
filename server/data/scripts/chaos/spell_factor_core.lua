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

-- the factor of vocation `vocId` (1 when not listed)
function F.forVocation(vocId, cfg)
	cfg = cfg or ChaosSpellFactorConfig
	local v = cfg and cfg.byVocation and cfg.byVocation[tonumber(vocId) or -1]
	return v or 1
end

-- the factor on one damage value: the vocation, origin and combat type of the hit; spellOrigin / healingType are the
-- engine's ORIGIN_SPELL and COMBAT_HEALING; procActive = a keystone proc is running
function F.factor(vocId, origin, combatType, spellOrigin, healingType, procActive, cfg)
	if procActive or F.depth > 0 then
		return 1
	end
	if spellOrigin == nil or origin ~= spellOrigin or not combatType or combatType == 0 or combatType == healingType then
		return 1
	end
	return F.forVocation(vocId, cfg)
end

-- run fn(...) with the factor off (an ORIGIN_SPELL hit that is not the class's spell damage); returns pcall's results
function F.guard(fn, ...)
	F.depth = F.depth + 1
	local res = {pcall(fn, ...)}
	F.depth = F.depth - 1
	return (table.unpack or unpack)(res)
end

return F

-- weapon_families_core.lua: the rules of the three melee weapon families (O454; numbers: weapon_families_config.lua; engine glue:
-- weapon_families.lua; tests/weapon_families_test.lua; server/README.md "Weapon families (O454)"). Pure Lua, no engine calls.
--
-- A sword, an axe and a club of one tier hit the same since the one melee skill (melee_skill_core.lua). Each family now has a
-- trait on the basic melee attack, which weapon_styles.lua already styles (the hit of a weapon, origin melee, not a spell's
-- weapon strike):
--   sword  tempo   consecutive hits on one target speed up the swing; each hit is as much lighter as the swing is faster, so
--                  the damage per second stays, plus an edge of at most `edge` at full stacks
--   axe    cleave  the hit shares `pool` of itself among the monsters next to the target
--   club   impact  a chance to daze: the monster cannot attack for a moment, then rests; a boss is only slowed
-- Damage per second of one hit of a family is x `single` (the axe and the club pay), see the config for the limits.
-- Affected: the Warrior, Thief and Templar lines only. Not the Monk line, fists, bows, wands, spells, keystone extra hits.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosWeaponFamilies = ChaosWeaponFamilies or {}
local F = ChaosWeaponFamilies

if not F.config then
	F.config = dofile("data/scripts/chaos/weapon_families_config.lua")
end

local floor = math.floor

local function num(v)
	return tonumber(v) or 0
end

-- a value or a function that gives it (the glue passes the costly reads as functions: the scan of the tiles around the target,
-- the conditions of a monster, so they run only when a rule needs them)
local function val(x)
	if type(x) == "function" then
		return x()
	end
	return x
end

F.FAMILIES = {"sword", "axe", "club"}

-- the family of an items.xml weapon type name: "sword", "axe", "club"; nil for anything else (fist, distance, wand, none)
function F.familyOf(typeName)
	if typeName == "sword" or typeName == "axe" or typeName == "club" then
		return typeName
	end
	return nil
end

-- true when the vocation gets the traits (and they are on)
function F.affected(vocId)
	local c = F.config
	return c.enabled == true and c.vocations[tonumber(vocId) or -1] == true
end

-- the multiplier of one hit of a family (the price: 1 for the sword, a little under 1 for the axe and the club)
function F.single(family)
	local f = F.config.families[family]
	return f and num(f.single) > 0 and f.single or 1
end

-- ---------------------------------------------------------------------------------------------------------- sword: tempo
local function tempoCfg()
	return F.config.families.sword.tempo
end

-- the stacks a target may be given: all of them against a monster, pvpStackShare of them against a player
function F.tempoMax(pvp)
	local t = tempoCfg()
	if pvp then
		return math.max(1, floor(t.maxStacks * num(t.pvpStackShare) + 1e-9))
	end
	return t.maxStacks
end

-- state = one table per player. A hit on `targetId` at `now` (ms): returns the stacks the swing that made it had (before) and
-- the stacks after it. A new target, or a pause over windowMs, starts again at none; a hit within minGapMs of the one that
-- last gave a stack is the same swing and gives none.
function F.tempoStep(state, targetId, now, pvp)
	local t = tempoCfg()
	local before = 0
	if state.target == targetId and state.last and now - state.last <= t.windowMs then
		before = state.stacks or 0
	end
	local max = F.tempoMax(pvp)
	if before > max then
		before = max
	end
	local after = before
	if before == 0 or not state.stackAt or now - state.stackAt >= t.minGapMs then
		after = math.min(max, before + 1)
		state.stackAt = now
	end
	state.target, state.stacks, state.last = targetId, after, now
	return before, after
end

-- forget the stacks (another weapon in the hands, a pause); returns whether there were any
function F.tempoClear(state)
	local had = (state.stacks or 0) > 0
	state.target, state.stacks, state.last, state.stackAt = nil, 0, nil, nil
	return had
end

-- the attack speed percent the stacks give (set as the "tempo" source of the player attack speed bonus)
function F.tempoHaste(stacks)
	return num(stacks) * tempoCfg().stackPct
end

-- the multiplier of a hit swung with `stacks` stacks: the interval it was swung at over the interval without tempo (1 when
-- the cap held the swing back, so a capped swing is not lighter for nothing). O473: the edge of the stacks is no multiplier any
-- more, it is raw percent of the additive damage pool (F.tempoEdge)
function F.tempoFactor(stacks, intervalNow, intervalBase)
	local ratio = 1
	intervalNow, intervalBase = num(intervalNow), num(intervalBase)
	if intervalBase > 0 and intervalNow > 0 and intervalNow < intervalBase then
		ratio = intervalNow / intervalBase
	end
	return ratio
end

-- O473: the edge of the stacks the swing had, as raw percent of the additive damage pool: edge x 100 x stacks / maxStacks
-- (2 at full stacks)
function F.tempoEdge(stacks)
	local t = tempoCfg()
	stacks = math.max(0, math.min(t.maxStacks, num(stacks)))
	return num(t.edge) * 100 * stacks / t.maxStacks
end

-- the stacks the NEXT hit on `targetId` at `now` will be swung with: what F.tempoStep returns as `before`, without changing the state
function F.tempoPeek(state, targetId, now, pvp)
	local t = tempoCfg()
	if not state or state.target ~= targetId or not state.last or now - state.last > t.windowMs then
		return 0
	end
	return math.min(F.tempoMax(pvp), state.stacks or 0)
end

-- ----------------------------------------------------------------------------------------------------------- axe: cleave
-- the share of the hit each of `neighbors` monsters takes (0 when nothing is split) and how many take it. pvp: the target is a
-- player.
function F.cleaveShare(neighbors, pvp)
	local c = F.config.families.axe.cleave
	if pvp and not c.pvp then
		return 0, 0
	end
	local n = math.min(floor(num(neighbors)), c.maxTargets)
	if n <= 0 then
		return 0, 0
	end
	return c.pool / n, n
end

-- the damage one neighbour takes of a hit of `total` (a whole number, at least 1 when anything is split)
function F.cleaveAmount(total, share)
	if share <= 0 then
		return 0
	end
	return math.max(1, floor(math.abs(num(total)) * share + 0.5))
end

-- ---------------------------------------------------------------------------------------------------------- club: impact
local function dazeCfg()
	return F.config.families.club.daze
end

-- true for a boss: the type says so, or its maximum health is above bossHealth (the Monk's Iron Palm rule)
function F.isBoss(typeIsBoss, maxHealth)
	return typeIsBoss == true or num(maxHealth) > dazeCfg().bossHealth
end

-- What a hit does to a monster. boss: a boss; immune: it is in the rest after a stun (or an Iron Palm); bossRest: in the rest
-- after a boss slow; roll: a number in [0, 1). Returns nil, or {kind = "stun", ms, restMs} / {kind = "slow", ms, slow, restMs}
-- where restMs is the time the rest condition runs from the start of the daze (so the daze and the rest make the cycle).
function F.dazePlan(boss, immune, bossRest, roll)
	local d = dazeCfg()
	roll = num(roll)
	if boss then
		if bossRest or roll >= d.bossChance then
			return nil
		end
		return {kind = "slow", ms = d.bossSlowMs, slow = d.bossSlow, restMs = d.bossSlowMs + d.bossImmuneMs}
	end
	if immune or roll >= d.chance then
		return nil
	end
	return {kind = "stun", ms = d.stunMs, restMs = d.stunMs + d.immuneMs}
end

-- the most a monster can be held, as a share of the time: a stun (or a slow) over the whole cycle it starts
function F.dazeUptimeCap(boss)
	local d = dazeCfg()
	if boss then
		return d.bossSlowMs / (d.bossSlowMs + d.bossImmuneMs)
	end
	return d.stunMs / (d.stunMs + d.immuneMs)
end

-- ------------------------------------------------------------------------------------------------------------- the hit
-- What the glue does with a basic melee hit. state = the player's tempo state. ctx:
--   family       "sword" | "axe" | "club" (F.familyOf of the weapon in the hands)
--   vocId        the player's vocation id
--   pvp          the target is a player
--   targetId, now (ms)
--   intervalNow, intervalBase   the swing interval with and without the tempo haste (ms), the sword only
--   neighbors    number or function: the monsters next to the target (the axe only)
--   gate         function(key) -> bool, the per-second limit of the extras (ChaosAttackRate.gate)
--   boss, immune, bossRest   booleans or functions (the club only, against a monster)
--   roll         a number in [0, 1) or a function
-- Returns nil when the traits do not apply (the hit stays as it is), else
--   {factor = multiplier of the hit, haste = attack speed percent to set (the sword; nil = leave it), cleave = {share, count},
--    daze = F.dazePlan result}
-- The cleave and the daze are worked out by the caller from the hit after `factor`.
function F.plan(state, ctx)
	local family = ctx.family
	if not F.affected(ctx.vocId) or not F.config.families[family] then
		return nil
	end
	local plan = {factor = F.single(family)}
	-- the axe and the club pay for a trait: against a player the trait is off, so the price is too (PvP stays as before O454)
	if ctx.pvp and ((family == "axe" and not F.config.families.axe.cleave.pvp)
			or (family == "club" and not dazeCfg().pvp)) then
		plan.factor = 1
	end
	if family ~= "sword" then
		-- another weapon in the hands: the tempo of a sword ends with it
		if F.tempoClear(state) then
			plan.haste = 0
		end
	end
	if family == "sword" then
		local before, after = F.tempoStep(state, ctx.targetId, ctx.now, ctx.pvp)
		plan.factor = plan.factor * F.tempoFactor(before, ctx.intervalNow, ctx.intervalBase)
		plan.haste = F.tempoHaste(after)
		plan.stacks = after
	elseif family == "axe" then
		if not ctx.pvp then
			local share, count = F.cleaveShare(val(ctx.neighbors), false)
			if share > 0 and (not ctx.gate or ctx.gate("axeCleave")) then
				plan.cleave = {share = share, count = count}
			end
		end
	elseif family == "club" then
		local d = dazeCfg()
		if not ctx.pvp or d.pvp then
			local roll = val(ctx.roll)
			if roll == nil then
				roll = math.random()
			end
			-- the cheap roll first: the conditions are read only for a hit that would daze
			if roll < math.max(d.chance, d.bossChance) then
				plan.daze = F.dazePlan(val(ctx.boss), val(ctx.immune), val(ctx.bossRest), roll)
			end
		end
	end
	return plan
end

-- ----------------------------------------------------------------------------------------------------------- the tooltip
-- 14 -> "14", 2.5 -> "2.5": a number of the config as the player reads it
local function shown(v)
	if math.abs(v - floor(v + 0.5)) < 1e-9 then
		return tostring(floor(v + 0.5))
	end
	return string.format("%.1f", v)
end

-- the line of a weapon tooltip: "Sword: ...", "Axe: ...", "Club: ..." (English; the server turns it into the player's
-- language through i18n_strings.lua, the keys write the percent signs as %%). nil for a type that has no family
function F.note(family)
	local f = F.config.families[family]
	if not f then
		return nil
	end
	local price = shown((1 - f.single) * 100)
	if family == "sword" then
		local t = f.tempo
		return string.format("Sword: tempo. Each hit on the same target speeds up your swing, up to %s%% faster, and adds up to +%s%% increased damage. Best on one target. A new target starts over.",
			shown(t.maxStacks * t.stackPct), shown(t.edge * 100))
	elseif family == "axe" then
		local c = f.cleave
		return string.format("Axe: cleave. %s%% of each hit is split among the monsters next to the target. Costs %s%% damage on one target. Best in packs.",
			shown(c.pool * 100), price)
	elseif family == "club" then
		local d = f.daze
		return string.format("Club: impact. A hit has a %s%% chance to daze a monster: it cannot attack for %s s, then rests for %s s. A boss is only slowed. Costs %s%% damage on one target.",
			shown(d.chance * 100), shown(d.stunMs / 1000), shown(d.immuneMs / 1000), price)
	end
	return nil
end

return F

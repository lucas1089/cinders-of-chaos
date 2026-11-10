-- passivetree_totals.lua: the totals of the passive tree window (O146). Rules: passivetree_totals_core.lua.
--
-- Protocol (opcode 65, through ChaosPassiveTree.extraActions, passivetree.lua):
--   client -> server  statTotals              -> statTotals (the window asks when it opens and after a save / Paragon change)
--   server -> client  {"action":"statTotals","data":{attributes = [{k, n, raw, eff, cap, effect}], damage = [{k, n, raw, eff, cap}],
--                      crit = {chance = {total, tree, other}, amount = {total, tree, paragon, other}},
--                      attackSpeed = {total, tree, gear, cap} (only with a bonus)}}
--                     O473: a damage row also carries pool = {raw, eff, parts = [{n, raw, cap}]}, the one additive damage pool
--                     (damage_pool_core.lua) of that type without a target: tree and Spell Damage, Paragon, gems, the card set
--                     n = the stat name in the player's language (Chaos.t); raw = what the nodes give, eff = after the soft cap
--                     (passivetree_effects.lua ChaosSoftCap), crit totals are the engine's own value: tree, Paragon, gear, gems,
--                     blessings and every other source together.
-- One request per rateMs per player (a tree window opened and closed in a loop costs nothing).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPassiveStatsConfig then
	dofile("data/scripts/chaos/passivetree_stats_config.lua")
end
if not PassiveTotalsCore then
	dofile("data/scripts/chaos/passivetree_totals_core.lua")
end

local OPCODE = ChaosOpcodes.passivetree
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}
ChaosPassiveTotals = ChaosPassiveTotals or {}
local TT = ChaosPassiveTotals
TT.rateMs = 300
TT.last = TT.last or {} -- player id -> ms of the last answer

-- stat key -> combat type: physical first, then the elements, as the window lists them
local function damageTypes()
	return {
		{"incrementPhysical", COMBAT_PHYSICALDAMAGE}, {"incrementFire", COMBAT_FIREDAMAGE}, {"incrementIce", COMBAT_ICEDAMAGE},
		{"incrementEnergy", COMBAT_ENERGYDAMAGE}, {"incrementEarth", COMBAT_EARTHDAMAGE}, {"incrementDeath", COMBAT_DEATHDAMAGE},
		{"incrementHoly", COMBAT_HOLYDAMAGE}, {"incrementArcane", COMBAT_ARCANEDAMAGE}, {"incrementWater", COMBAT_WATERDAMAGE}
	}
end

local function api()
	return {charStat = ChaosPassiveCharStat, softCap = ChaosSoftCap, cfg = ChaosPassiveEffectsConfig,
		damageRaw = ChaosPassiveDamageRaw, damagePercent = ChaosPassiveDamagePercent, types = damageTypes()}
end

-- the engine's critical chance and damage of a player (all sources), nil without the Lua binding
local function engineCrit(player)
	if not player.getSpecialSkill then
		return nil, nil
	end
	return player:getSpecialSkill(SPECIALSKILL_CRITICALHITCHANCE), player:getSpecialSkill(SPECIALSKILL_CRITICALHITAMOUNT)
end

local function named(player, rows)
	local stats = ChaosPassiveStatsConfig.stats
	for _, row in ipairs(rows) do
		local def = stats[row.k]
		row.n = Chaos.t(player, def and def[1] or row.k)
	end
	return rows
end

-- O473: the one additive damage pool of a damage type for the window and the character sheet: every source that holds without a
-- target (the tree and the worn Spell Damage, Paragon, gems, the card set of that element), the sum, the soft cap result. The unique
-- passives, charms, the sword's edge and a mastery depend on the hit: the help line names them. {raw, eff, parts = {{n, raw, cap}}}
function TT.pool(player, bonuses, combatType)
	if not ChaosDamagePool then
		return nil
	end
	local list, sum, eff = ChaosDamagePool.sheet(player, combatType, ChaosPassiveDamageRaw(bonuses, combatType))
	local parts = {}
	for _, e in ipairs(list) do
		parts[#parts + 1] = {n = Chaos.t(player, e.label), raw = math.floor(e.raw * 10 + 0.5) / 10, cap = e.cap}
	end
	return {raw = math.floor(sum * 10 + 0.5) / 10, eff = math.floor(eff * 10 + 0.5) / 10, parts = parts}
end

-- the message data for a player (bonuses = the cached tree + Paragon sums, ChaosPassiveCache)
function TT.build(player, bonuses)
	bonuses = bonuses or ChaosPassiveCache and ChaosPassiveCache[player:getId()] or {}
	local a = api()
	local chance, amount = engineCrit(player)
	local damage = named(player, PassiveTotalsCore.damage(bonuses, a))
	local typeOf = {}
	for _, t in ipairs(a.types) do
		typeOf[t[1]] = t[2]
	end
	for _, row in ipairs(damage) do
		row.pool = typeOf[row.k] and TT.pool(player, bonuses, typeOf[row.k]) or nil
	end
	return {
		attributes = named(player, PassiveTotalsCore.attributes(bonuses, a)),
		damage = damage,
		crit = PassiveTotalsCore.crit(bonuses, chance, amount),
		attackSpeed = PassiveTotalsCore.attackSpeed(bonuses, ChaosItemMods and ChaosItemMods.playerBonus and
			ChaosItemMods.playerBonus(player, "gearspeed") or 0,
			ChaosPassiveEffectsConfig and ChaosPassiveEffectsConfig.maxAttackSpeed,
			ChaosItemMods and ChaosItemMods.config and ChaosItemMods.config.playerSpeedCap)
	}
end

ChaosPassiveTree.extraActions.statTotals = function(player)
	local now = os.mtime and os.mtime() or os.time() * 1000
	local id = player:getId()
	if TT.last[id] and now - TT.last[id] < TT.rateMs then
		return true
	end
	TT.last[id] = now
	Chaos.send(player, OPCODE, "statTotals", TT.build(player))
	return true
end

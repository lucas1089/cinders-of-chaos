-- Pure rules of the totals panel of the passive tree window (passivetree_totals.lua; tests: tests/softcap_test.lua).
-- O146: the window showed only the node sums, so a player with 280 strength saw "+280 strength" and never learned that the
-- value stops growing fast at 120, and the critical chance and damage of the gear were nowhere in it.
--
--   PassiveTotalsCore.attributes(bonuses, api)   [{k, raw, eff, cap, effect}] for strength, intelligence, dexterity,
--                                                vitality, spirit that have points
--       raw    = the points the tree gives (the node sums)
--       eff    = the points that count after the soft cap: raw up to the cap, then cap + H ln(1 + (raw - cap) / H)
--       cap    = the point count where the full-value curve ends (the soft cap starts)
--       effect = the stat's own value (damage / health percent of its curve, ChaosPassiveCharStat)
--   PassiveTotalsCore.damage(bonuses, api)       [{k, raw, eff, cap}] for physical and every element with a percent
--       raw = the percent the tree gives to the type (its increment + all-elements), eff = after the soft cap, cap = 150
--   PassiveTotalsCore.crit(bonuses, gearChance, gearAmount)
--       {chance = {total, tree, other}, amount = {total, tree, paragon, other}}: `total` is what the engine rolls with
--       (tree, Paragon, gear, gems, blessings together); tree / paragon are the shares of the passive tree and Paragon;
--       other = total - tree - paragon (gear and the rest). A nil total (no engine API) counts the tree and Paragon only.
-- `api` = {charStat = fn(points, stat), softCap = fn(raw, cap, H), cfg = ChaosPassiveEffectsConfig, damageRaw = fn(bonuses,
-- combatType), damagePercent = fn(bonuses, combatType), types = {{statKey, combatType}, ...}}.
-- Lua 5.1 / LuaJIT and Lua 5.3.

PassiveTotalsCore = PassiveTotalsCore or {}
local M = PassiveTotalsCore

M.ATTRIBUTES = {"strength", "intelligence", "dexterity", "vitality", "spirit"}

local function round(v, places)
	local m = 10 ^ (places or 1)
	return math.floor(v * m + 0.5) / m
end

function M.attributes(bonuses, api)
	local out = {}
	for _, stat in ipairs(M.ATTRIBUTES) do
		local raw = bonuses[stat] or 0
		if raw > 0 then
			local cap = api.cfg.charStatCap[stat]
			out[#out + 1] = {k = stat, raw = round(raw), eff = round(api.softCap(raw, cap, api.cfg.softCap.charStatH[stat])), cap = cap,
				effect = round(api.charStat(raw, stat), 2)}
		end
	end
	return out
end

function M.damage(bonuses, api)
	local out = {}
	local cap = api.cfg.maxDamagePercent
	for _, t in ipairs(api.types) do
		local raw = api.damageRaw(bonuses, t[2])
		if raw > 0 then
			out[#out + 1] = {k = t[1], raw = round(raw), eff = round(api.damagePercent(bonuses, t[2])), cap = cap}
		end
	end
	return out
end

function M.crit(bonuses, gearChance, gearAmount)
	local treeChance = bonuses.criticalHitChance or 0
	local treeAmount = bonuses.criticalHitAmount or 0
	local paragon = bonuses.paragonCritDamage or 0
	local chance = gearChance ~= nil and math.max(gearChance, treeChance) or treeChance
	local amount = gearAmount ~= nil and math.max(gearAmount, treeAmount + paragon) or treeAmount + paragon
	return {
		chance = {total = round(chance), tree = round(treeChance), other = round(chance - treeChance)},
		amount = {total = round(amount), tree = round(treeAmount), paragon = round(paragon), other = round(amount - treeAmount - paragon)}
	}
end

-- Attack speed (engine patch 0078): the percent the tree and the worn pieces give as a player-level bonus, each under its own
-- cap, together under the player cap; the engine adds its own rules on top (all bonuses together at most 40% shorter
-- interval, one attack per second at most). nil when neither gives any.
function M.attackSpeed(bonuses, gear, treeCap, playerCap)
  local tree = math.min(treeCap or 12, math.max(0, math.floor((bonuses.attackSpeed or 0) + 1e-6)))
  gear = math.max(0, math.floor(tonumber(gear) or 0))
  if tree <= 0 and gear <= 0 then
    return nil
  end
  return {total = math.min(playerCap or 20, tree + gear), tree = tree, gear = gear, cap = playerCap or 20}
end

return M

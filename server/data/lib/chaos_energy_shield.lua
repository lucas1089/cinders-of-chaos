-- Energy shield (ChaosEnergyShield): a pool above the health that items give. The engine (src-patches/0015-energy-
-- shield.patch) keeps the value per player, takes the damage from it after the mana shield (utamo vita) and after the
-- onHealthChange scripts, before the health, recharges it and sends it to the client (extended opcode
-- ChaosOpcodes.energyShield, "es:<current>:<maximum>", client game_energyshield). This file is the pure part: the three
-- item modifiers (added to ChaosItemMods.config.mods, so the roll, the bench, tooltips, the Codex and the caps know them),
-- the maths of the maximum and the recharge, and the helpers the scripts use (data/scripts/chaos/energy_shield.lua applies
-- the totals of the equipped items; lethal-hit checks of other scripts count the shield with effectiveHealth).
-- Tested by server/tests/energy_shield_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible. Overview: server/README.md
-- "Energy shield".
--
-- Maximum: (sum of "+N Maximum Energy Shield") x (100 + sum of "+N% Maximum Energy Shield") / 100; the percent raises the
-- flat amount only, so a character without a flat modifier has no shield.
-- Recharge: starts energyShieldRechargeDelay ms (config.lua, default 2000) after the last hit taken, then
-- basePerMille / 10 % of the maximum per second (20%), raised by "Faster Energy Shield Recharge" (+50% -> 30% per second).

ChaosEnergyShield = ChaosEnergyShield or {}
local E = ChaosEnergyShield
if not ChaosItemMods then
	dofile("data/lib/chaos_item_mods.lua")
end
local M = ChaosItemMods
local floor = math.floor

E.config = {
	basePerMille = 200, -- recharge per second, per mille of the maximum (200 = 20%)
	maxPerMille = 1000 -- at most the whole shield per second
}

-- the three modifiers (T1 .. T8, like the others). Balance (server/README.md "Energy shield"): at level 300 (item level
-- ~74, T1 .. T5 roll) four flat rolls at T4-T5 and one percent roll give ~480-760, 15-24% of a mid class's health
-- (10 per level: ~3,200; a Mystic ~1,700: 28-45%, a Warrior ~4,700: 10-16%); at level 1000 (item level 128+, T3/T4 ..
-- T7/T8) four at T7 and a T7 percent roll give ~1,580, 15% of ~10,200 (Mystic 30%). Caps: 1,500 flat, +60%.
E.defs = {
	{key = "energyshield", label = "Maximum Energy Shield", fmt = "flat", side = "prefix", weight = 6, cap = 1500,
		kinds = {armor = true, shield = true, helmet = true, jewel = true},
		tiers = {{12, 25}, {25, 50}, {50, 85}, {85, 135}, {135, 195}, {195, 270}, {270, 360}, {360, 480}}},
	{key = "energyshieldpct", label = "Maximum Energy Shield", fmt = "pct", side = "prefix", weight = 4, cap = 60,
		kinds = {armor = true, shield = true, helmet = true, jewel = true},
		tiers = {{2, 4}, {4, 6}, {6, 9}, {8, 12}, {10, 15}, {13, 19}, {16, 23}, {20, 28}}},
	{key = "esrecharge", label = "Faster Energy Shield Recharge", fmt = "pct", side = "suffix", weight = 4, cap = 100,
		kinds = {armor = true, shield = true, helmet = true, jewel = true},
		tiers = {{5, 8}, {8, 12}, {12, 16}, {16, 20}, {20, 25}, {25, 30}, {30, 36}, {36, 45}}}
}
E.keys = {}
for _, def in ipairs(E.defs) do
	M.addMod(def)
	E.keys[#E.keys + 1] = def.key
end

-- the maximum from the totals of the equipped items ({key -> value}, ChaosItemMods.totals)
function E.maximum(totals)
	totals = totals or {}
	local flat = math.max(0, tonumber(totals.energyshield) or 0)
	local pct = math.max(0, tonumber(totals.energyshieldpct) or 0)
	return floor(flat * (100 + pct) / 100 + 1e-9)
end

-- the recharge, per mille of the maximum per second
function E.rechargePerMille(totals)
	local bonus = math.max(0, tonumber(totals and totals.esrecharge) or 0)
	return math.min(E.config.maxPerMille, floor(E.config.basePerMille * (100 + bonus) / 100 + 1e-9))
end

-- what the engine does in one think of `ms` milliseconds `sinceHit` ms after the last hit (tests and tooltips)
function E.recharge(current, maximum, perMille, sinceHit, ms, delayMs)
	current, maximum = tonumber(current) or 0, tonumber(maximum) or 0
	if maximum <= 0 or current >= maximum or (perMille or 0) <= 0 then
		return math.min(current, math.max(0, maximum))
	end
	local over = (tonumber(sinceHit) or 0) - (tonumber(delayMs) or 2000)
	if over <= 0 then
		return current
	end
	local span = math.min(tonumber(ms) or 1000, over)
	local gain = math.max(1, floor(maximum * perMille * span / 1000000))
	return math.min(maximum, current + gain)
end

-- seconds from empty to full once the delay is over
function E.fullAfter(perMille)
	perMille = tonumber(perMille) or 0
	return perMille > 0 and 1000 / perMille or math.huge
end

-- the shield of a creature now (0 for monsters, offline players or an engine without patch 0015)
function E.current(creature)
	if not creature then
		return 0
	end
	local ok, v = pcall(function()
		return creature:isPlayer() and creature.getEnergyShield and creature:getEnergyShield() or 0
	end)
	return ok and tonumber(v) or 0
end

-- health + shield: what a hit must exceed to kill the creature (the shield takes its part after the onHealthChange
-- scripts, so a script that catches lethal hits compares the hit with this, not with the health alone)
function E.effectiveHealth(creature)
	return creature:getHealth() + E.current(creature)
end

-- set the maximum and the recharge of a player from the totals of the equipped items
function E.apply(player, totals)
	if not player or not player.setMaxEnergyShield then
		return false
	end
	player:setMaxEnergyShield(E.maximum(totals))
	player:setEnergyShieldRecharge(E.rechargePerMille(totals))
	return true
end

return E

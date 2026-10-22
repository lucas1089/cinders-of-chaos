-- Legendary powers (ChaosPowers): twelve modifiers that change what the character does instead of adding a number. They
-- are modifiers of data/lib/chaos_item_mods.lua with `power = true` (so a power has a tier, a value, a prefix or suffix
-- and counts against the item's modifier limits like any other) that only roll on items of rarity Legendary or better,
-- one per item (ChaosItemMods.config.powers). The value of a tier is the chance of the proc, except Last Breath (the
-- health left), Bloodrush (percent per stack) and Smoldering Aura (damage per second).
--
-- This file is the pure part: the catalogue (added to ChaosItemMods.config.mods, so tooltips, the bench, the loot filter
-- and the caps know them) and the maths and the limits of every power: cooldowns, stacks, damage formulas, who is
-- affected. data/scripts/chaos/item_powers.lua applies them to the game (hits, kills, deaths, blocks). Every power has an
-- internal cooldown or a counted limit and a recursion guard in the script, so none can be abused. Tested by
-- server/tests/powers_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible. Overview: server/README.md "Legendary powers".
--
-- Not done (said so on purpose): "culling strike" is the Execute modifier already; "cast a class spell on a critical hit"
-- needs an engine call that casts a spell by name (there is none); summoning a minion needs a monster per class and a
-- lifetime that the minion scripts own (the Necromancer's), so no power summons.

ChaosPowers = ChaosPowers or {}
local P = ChaosPowers
if not ChaosItemMods then
	dofile("data/lib/chaos_item_mods.lua")
end
local M = ChaosItemMods
local floor = math.floor

-- every number of the powers; the `tiers` (T1 .. T8) of each are in the catalogue below
P.config = {
	-- Death Blast: a fire explosion where the monster died, `hpPct` % of its maximum health but at most `capBase + capPerLevel
	-- x character level`, on up to `targets` other monsters within `radius`; no more often than every `cooldownMs`.
	-- 2026-10-22: was 25% and 50 + 8 x level (in packs 9% of a typical character's own damage per second at level 100,
	-- 76% at 1000; now 3-12%, server/README.md "Legendary powers")
	deathblast = {hpPct = 10, capBase = 50, capPerLevel = 1, radius = 2, targets = 8, cooldownMs = 1500},
	-- Glacial Ward: when a hit of a monster is dodged or blocked, an ice nova around you: `base + perLevel x level` damage,
	-- monsters slowed by `slow` % for `slowMs`. 2026-10-22: was 40 + 5 x level (14-95% of a typical character's damage
	-- per second; now 4-10%)
	frostward = {base = 100, perLevel = 1, radius = 2, targets = 8, slow = 35, slowMs = 3000, cooldownMs = 4000},
	-- Echo Shot: a ranged hit that lands is repeated after `delayMs` for `pct` % of it
	echoshot = {pct = 60, delayMs = 250, cooldownMs = 800},
	-- Critical Echo: a critical hit is repeated after `delayMs` for `pct` % of it
	critecho = {pct = 50, delayMs = 200, cooldownMs = 1000},
	-- Crimson Burst: a hit heals `healPct` % of your maximum health
	crimsonburst = {healPct = 4, cooldownMs = 2500},
	-- Last Breath: a hit that would kill you leaves you at the power's % of your health instead; once per `cooldownMs`
	-- (the time of the last one is kept in a player storage, so logging out does not reset it)
	lastbreath = {cooldownMs = 300000, minHealth = 1, storage = 7101800},
	-- Ember Step: a single hit of at least `hitPct` % of your maximum health blinks you up to `range` sqm away (a free
	-- tile) and burns where you stood: `base + perLevel x level` fire damage, `radius`. 2026-10-22: was 60 + 6 x level (at
	-- one blink per cooldown 46-147% of a typical character's damage per second; now at most 16-25%)
	emberstep = {hitPct = 20, range = 3, base = 60, perLevel = 2, radius = 2, targets = 8, cooldownMs = 15000},
	-- Bloodrush: every kill adds a stack for `windowMs`; each stack adds the power's % to your damage, `maxStacks` at most
	bloodrush = {maxStacks = 5, windowMs = 6000},
	-- Arc Lightning: a hit arcs to up to `targets` other monsters within `radius` for `pct` % of it
	arclightning = {pct = 30, radius = 3, targets = 3, cooldownMs = 700},
	-- Hunter's Rush: haste of `speed` for `ms`
	hunterrush = {speed = 40, ms = 4000, cooldownMs = 8000},
	-- Shatter Splash: the killing blow bursts onto up to `targets` monsters within `radius`: the power's % of the health
	-- the blow took, shared by them (P.splashShare). 2026-10-22: it was 10-75% of the whole blow to each of them, in packs
	-- 190-480% of a typical character's own damage per second; now 8-15%
	shattersplash = {radius = 2, targets = 6, cooldownMs = 1000},
	-- Smoldering Aura: every `tickMs` the power's damage per second x seconds burns up to `targets` monsters within `radius`
	-- and in clear sight. The damage per second is at most `capBase` + 1 per `levelsPerPoint` character levels (P.auraCap:
	-- about 1.3% of a typical character's own damage per second at every level, so a full pack takes 7-9% of it). It
	-- ticks only while the character fights (it attacked a monster within `activeMs`) and stands outside a protection
	-- zone. Beta 2026-10-22 ("extremamente forte"): it had been 55-140% of a typical character's damage per second.
	smolderaura = {radius = 2, targets = 6, tickMs = 3000, capBase = 2, levelsPerPoint = 30, activeMs = 5000}
}
local CFG = P.config

local PCT = {{2, 3}, {3, 4}, {4, 6}, {5, 7}, {6, 9}, {8, 11}, {10, 13}, {12, 16}}
local SPLASH = {{10, 15}, {15, 20}, {20, 25}, {25, 30}, {30, 40}, {40, 50}, {50, 60}, {60, 75}}

-- the catalogue. kinds: which items may roll it (chaos_item_mods.lua M.kindOf)
P.defs = {
	{key = "deathblast", label = "Death Blast", text = "Death Blast: %d%% chance on kill to explode", fmt = "pct",
		side = "prefix", weight = 3, cap = 25, kinds = {weapon = true, jewel = true}, tiers = PCT},
	{key = "frostward", label = "Glacial Ward", text = "Glacial Ward: %d%% chance when you dodge or block for a frost nova",
		fmt = "pct", side = "prefix", weight = 3, cap = 30, kinds = {shield = true, armor = true, legs = true, boots = true,
		other = true}, tiers = PCT},
	{key = "echoshot", label = "Echo Shot", text = "Echo Shot: %d%% chance on a ranged hit to shoot again", fmt = "pct",
		side = "prefix", weight = 2, cap = 25, kinds = {weapon = true}, tiers = PCT},
	{key = "critecho", label = "Critical Echo", text = "Critical Echo: %d%% chance on a critical hit to strike again",
		fmt = "pct", side = "prefix", weight = 3, cap = 30, kinds = {weapon = true, jewel = true},
		tiers = {{3, 5}, {5, 7}, {6, 9}, {8, 11}, {10, 14}, {12, 17}, {15, 20}, {18, 25}}},
	{key = "arclightning", label = "Arc Lightning", text = "Arc Lightning: %d%% chance on hit to arc to 3 monsters nearby",
		fmt = "pct", side = "prefix", weight = 3, cap = 30, kinds = {weapon = true, jewel = true}, tiers = PCT},
	{key = "bloodrush", label = "Bloodrush", text = "Bloodrush: each kill adds %d%% damage (5 stacks, 6 s)", fmt = "pct",
		side = "prefix", weight = 3, cap = 5, kinds = {weapon = true, jewel = true, other = true},
		tiers = {{1, 1}, {1, 1}, {1, 2}, {2, 2}, {2, 3}, {3, 3}, {3, 4}, {4, 5}}},
	-- Shatter Splash, cut 2026-10-22 (the ranges before in `cutFrom`, read like Smoldering Aura's)
	{key = "shattersplash", label = "Shatter Splash",
		text = "Shatter Splash: killing blows burst for %d%%, shared by the monsters nearby",
		fmt = "pct", side = "prefix", weight = 3, cap = 25, kinds = {weapon = true}, tiers = PCT, cutFrom = SPLASH},
	{key = "crimsonburst", label = "Crimson Burst", text = "Crimson Burst: %d%% chance on hit to heal 4%% of your health",
		fmt = "pct", side = "suffix", weight = 3, cap = 25, kinds = {weapon = true, jewel = true, helmet = true},
		tiers = PCT},
	{key = "lastbreath", label = "Last Breath", text = "Last Breath: a lethal hit leaves you at %d%% health (once per 5 minutes)",
		fmt = "pct", side = "suffix", weight = 2, cap = 50, kinds = {armor = true, helmet = true, shield = true,
		jewel = true, legs = true}, tiers = {{10, 15}, {15, 20}, {20, 25}, {25, 30}, {30, 35}, {35, 40}, {40, 45}, {45, 50}}},
	{key = "emberstep", label = "Ember Step", text = "Ember Step: %d%% chance when hit hard to blink away in flames",
		fmt = "pct", side = "suffix", weight = 3, cap = 30, kinds = {boots = true, legs = true, armor = true, jewel = true},
		tiers = {{4, 6}, {6, 8}, {8, 10}, {10, 13}, {12, 16}, {15, 19}, {18, 23}, {22, 28}}},
	{key = "hunterrush", label = "Hunter's Rush", text = "Hunter's Rush: %d%% chance on kill for haste (4 s)", fmt = "pct",
		side = "suffix", weight = 3, cap = 30, kinds = {boots = true, jewel = true, helmet = true, other = true},
		tiers = {{4, 6}, {6, 8}, {8, 10}, {10, 13}, {12, 16}, {15, 19}, {18, 23}, {22, 28}}},
	-- Smoldering Aura, cut 2026-10-22: each tier's top is about the level cap (P.auraCap) of the lowest character level
	-- whose drops roll that tier. `cutFrom` holds the ranges before: an item rolled in them reads as the top of its tier
	-- today (chaos_item_mods.lua M.read); nothing on the item is rewritten.
	{key = "smolderaura", label = "Smoldering Aura",
		text = "Smoldering Aura: while you fight, monsters within 2 sqm take %d fire damage per second",
		fmt = "flat", side = "suffix", weight = 3, cap = 40, kinds = {armor = true, helmet = true, jewel = true, legs = true,
		other = true}, tiers = {{1, 2}, {2, 3}, {3, 4}, {5, 7}, {8, 12}, {13, 20}, {20, 28}, {28, 35}},
		cutFrom = {{5, 10}, {10, 20}, {20, 35}, {35, 60}, {60, 100}, {100, 160}, {160, 250}, {250, 400}}}
}

P.keys = {}
for _, def in ipairs(P.defs) do
	def.power = true
	def.minRarity = M.config.powers.minRarity
	M.addMod(def)
	P.keys[#P.keys + 1] = def.key
end

-- ---------------------------------------------------------------------------------------------------------------
-- maths
-- ---------------------------------------------------------------------------------------------------------------
-- a chance roll: pct percent (a whole or fractional number), rand(1, 10000) so tenths of a percent count
function P.roll(pct, rand)
	pct = tonumber(pct) or 0
	if pct <= 0 then
		return false
	end
	if pct >= 100 then
		return true
	end
	return (rand or math.random)(1, 10000) <= pct * 100
end

-- an internal cooldown: state[key] = the time (ms) it may proc again. Returns true and starts the cooldown when it is
-- over, false while it runs.
function P.ready(state, key, now, ms)
	if (state[key] or 0) > now then
		return false
	end
	state[key] = now + (ms or 0)
	return true
end

-- Death Blast: damage of the explosion
function P.blastDamage(monsterMaxHealth, level)
	local c = CFG.deathblast
	local cap = c.capBase + c.capPerLevel * math.max(1, tonumber(level) or 1)
	return math.max(1, math.min(cap, floor((tonumber(monsterMaxHealth) or 0) * c.hpPct / 100)))
end

-- Glacial Ward and Ember Step: damage of the nova / the burn at a character level
function P.novaDamage(level)
	local c = CFG.frostward
	return c.base + c.perLevel * math.max(1, tonumber(level) or 1)
end

function P.burnDamage(level)
	local c = CFG.emberstep
	return c.base + c.perLevel * math.max(1, tonumber(level) or 1)
end

-- the repeated hit of Echo Shot / Critical Echo / the arc of Arc Lightning / the splash of Shatter Splash, for a hit
function P.share(hit, pct)
	return math.max(1, floor(math.abs(tonumber(hit) or 0) * (tonumber(pct) or 0) / 100 + 1e-9))
end

-- Shatter Splash: the damage on each of `n` monsters for a killing blow that took `hit` health and a power of `pct`
function P.splashShare(hit, pct, n)
	n = math.max(1, tonumber(n) or 1)
	return math.max(1, floor(math.abs(tonumber(hit) or 0) * (tonumber(pct) or 0) / 100 / n + 1e-9))
end

-- Crimson Burst: the heal for a character with this maximum health
function P.burstHeal(maxHealth)
	return math.max(1, floor((tonumber(maxHealth) or 0) * CFG.crimsonburst.healPct / 100))
end

-- Last Breath: a hit of `damage` on a character at `health` of `maxHealth` with a power of `pct` percent. Returns the
-- damage to take instead and the health to be set to afterwards, or nil when the hit is not lethal.
function P.lastBreath(health, maxHealth, damage, pct)
	health, maxHealth, damage, pct = tonumber(health) or 0, tonumber(maxHealth) or 0, tonumber(damage) or 0, tonumber(pct) or 0
	if pct <= 0 or damage < health or health <= 0 then
		return nil
	end
	return health - CFG.lastbreath.minHealth, math.max(CFG.lastbreath.minHealth + 1, floor(maxHealth * math.min(pct, 100) / 100))
end

-- Ember Step: is this hit hard enough?
function P.hardHit(damage, maxHealth)
	return (tonumber(maxHealth) or 0) > 0 and (tonumber(damage) or 0) * 100 >= CFG.emberstep.hitPct * maxHealth
end

-- Bloodrush: kills of one character. state = {stacks, last}; returns the stacks after a kill at `now` (ms): the stacks of
-- an older kill are gone after the window
function P.rushKill(state, now)
	local w = CFG.bloodrush
	if (state.stacks or 0) > 0 and now - (state.last or 0) > w.windowMs then
		state.stacks = 0
	end
	state.stacks = math.min(w.maxStacks, (state.stacks or 0) + 1)
	state.last = now
	return state.stacks
end

-- stacks still running at `now`
function P.rushStacks(state, now)
	if state and (state.stacks or 0) > 0 and now - (state.last or 0) <= CFG.bloodrush.windowMs then
		return state.stacks
	end
	return 0
end

-- percent more damage with `stacks` stacks of a power of `pct` per stack
function P.rushBonus(stacks, pct)
	return math.min(CFG.bloodrush.maxStacks, tonumber(stacks) or 0) * (tonumber(pct) or 0)
end

-- Smoldering Aura: the most damage per second a character of this level gets from it (all items together)
function P.auraCap(level)
	local c = CFG.smolderaura
	return floor(c.capBase + math.max(1, tonumber(level) or 1) / c.levelsPerPoint + 1e-9)
end

-- Smoldering Aura: damage of one tick for a power of `perSecond` on a character of `level` (without a level: no cap)
function P.auraTick(perSecond, level)
	local v = tonumber(perSecond) or 0
	if level then
		v = math.min(v, P.auraCap(level))
	end
	return math.max(0, floor(v * CFG.smolderaura.tickMs / 1000 + 1e-9))
end

-- Smoldering Aura: does it tick at `now` (ms) for a character that last attacked a monster at `fightAt` (nil: never)?
function P.auraActive(fightAt, now)
	return fightAt ~= nil and now - fightAt <= CFG.smolderaura.activeMs
end

-- the powers of a character's capped totals (every power key above 0): {key = value}
function P.active(totals)
	local out = {}
	for _, key in ipairs(P.keys) do
		if totals and (totals[key] or 0) > 0 then
			out[key] = totals[key]
		end
	end
	return out
end

-- the power an item carries ({key, value, tier, def, ...} as ChaosItemMods.read gives it) or nil; an item has one at most
function P.powerOf(item)
	for _, m in ipairs(M.read(item)) do
		if M.isPower(m.def) then
			return m
		end
	end
	return nil
end

return P

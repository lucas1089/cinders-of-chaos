-- blessings_config.lua: every number of the Ember Blessings (blessings.lua, blessings_core.lua). A monster kill may
-- bless its loot owner for one minute: more experience, gold, damage, speed and so on. Plain table, loaded as
-- ChaosBlessingsConfig = dofile("data/scripts/chaos/blessings_config.lua"). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- Edit here, then /reload scripts (or restart). See server/README.md "Ember Blessings".
return {
	enabled = true,

	-- every blessing lasts this long; a second proc of a blessing that is still active sets it back to the full time
	durationMs = 60000,
	-- at most this many different blessings at once; a new kind past the cap replaces the one with the least time left
	maxActive = 3,
	-- after a proc no other proc for this long (one character, any kind); it starts at the roll, not at the pickup
	cooldownMs = 20000,

	-- A proc drops an ember on the ground (pickups.lua, item "ember" of pickups_config.lua) instead of blessing at once.
	-- The blessing is given when someone takes it. lifetimeMs: how long it lies there, then it goes out with a fade
	-- effect and gives nothing. ownerWindowMs: the corpse owner alone; after that the owner's party members take it
	-- as well; nobody outside the party ever. enabled = false (or the items not installed, or no free tile): the
	-- blessing goes to the owner at once, as before.
	pickup = {enabled = true, lifetimeMs = 30000, ownerWindowMs = 6000},

	-- ------------------------------------------------------------------ the chance of a kill
	-- percent per kill by the monster's tier (monster_tiers.lua ChaosTierOf)
	chance = {normal = 1.5, magic = 4, rare = 8, legendary = 15, boss = 25},
	-- never more than this, whatever multiplies it
	maxChance = 40,
	-- the level gap: a monster at most `grace` levels under the character counts in full; past that the chance
	-- follows the monster's level as a share of the character's (`ratio`, the first row the share reaches). Under the
	-- last row there is no chance at all, so farming trivial monsters gives nothing.
	levelGap = {
		grace = 10,
		ratio = {
			{0.75, 1.0},
			{0.6, 0.5},
			{0.45, 0.2}
		}
	},

	-- ------------------------------------------------------------------ the pool
	-- key, name, weight (share of the draw), value (percent unless noted), label (the floating text), colour (palette
	-- byte r*36 + g*6 + b, each 0..5: never a "#rrggbb" string), effect (a CONST_ME_* name), desc (%d = value)
	pool = {
		{key = "xp", name = "Ember of Insight", weight = 20, value = 25, label = "+25% XP", color = 210,
			effect = "CONST_ME_MAGIC_GREEN", desc = "+%d%% experience from monsters."},
		{key = "gold", name = "Ember of Avarice", weight = 18, value = 50, label = "+50% GOLD", color = 204,
			effect = "CONST_ME_GIFT_WRAPS", desc = "+%d%% gold coins in the corpses of your kills."},
		{key = "damage", name = "Ember of Fury", weight = 16, value = 15, label = "+15% DAMAGE", color = 192,
			effect = "CONST_ME_HITBYFIRE", desc = "+%d%% damage dealt to monsters."},
		{key = "ward", name = "Ember of Warding", weight = 14, value = 15, label = "-15% DAMAGE TAKEN", color = 101,
			effect = "CONST_ME_BLOCKHIT", desc = "-%d%% damage taken from monsters."},
		-- the share of the character's base speed
		{key = "speed", name = "Ember of Haste", weight = 14, value = 25, label = "+25% SPEED", color = 107,
			effect = "CONST_ME_MAGIC_BLUE", desc = "+%d%% movement speed."},
		-- value: percent of the maximum health and mana back every `regenTicksMs`
		{key = "regen", name = "Ember of Renewal", weight = 12, value = 2, label = "REGENERATION", color = 30,
			effect = "CONST_ME_MAGIC_GREEN", desc = "%d%% of your maximum health and mana back every 2 seconds."},
		-- value: critical hit chance; critAmount: extra damage of a critical hit, in percent
		{key = "crit", name = "Ember of Precision", weight = 12, value = 10, critAmount = 25, label = "+10% CRIT",
			color = 198, effect = "CONST_ME_FIREATTACK", desc = "+%d%% critical hit chance, critical hits +25%% damage."},
		-- the Chaos loot layer's extra rolls and currency chances (loot_config.lua rateMult)
		{key = "loot", name = "Ember of Plenty", weight = 10, value = 40, label = "+40% LOOT", color = 205,
			effect = "CONST_ME_GIFT_WRAPS", desc = "+%d%% Chaos loot: extra rolls and currency drops."},
		-- the bonus rarity chance of gear drops (loot.lua rarity find)
		{key = "rarity", name = "Ember of Fortune", weight = 8, value = 60, label = "+60% RARITY", color = 155,
			effect = "CONST_ME_MAGIC_RED", desc = "+%d%% rarity find on gear drops."},
		-- the chance of every orb of the loot layer's currency list (loot.lua rollCurrency)
		{key = "orb", name = "Ember of the Forge", weight = 6, value = 100, label = "+100% ORBS", color = 125,
			effect = "CONST_ME_ENERGYAREA", desc = "+%d%% chance of orbs from your kills."}
	},
	regenTicksMs = 2000,

	-- ------------------------------------------------------------------ engine
	-- condition sub ids of the blessings carried by a condition (next to the gems' 7240)
	subIds = {speed = 7260, regen = 7261, crit = 7262},
	-- the look-out for ends and PvP places, every this many ms
	tickMs = 1000,
	-- the proc text in the server log of the character (false: only the floating label and the buff bar)
	message = true
}

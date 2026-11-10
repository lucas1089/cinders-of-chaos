-- damage_pool_config.lua: the numbers of the one additive "increased damage" pool (O473, owner 2026-11-10: "Smooth that out. The
-- source of damage must be more balanced." and "You can do everything."). Pure data. Rules: damage_pool_core.lua (tested by
-- server/tests/damage_pool_test.lua); the engine side: passivetree_effects.lua ChaosPassiveDealt; documented in server/README.md
-- "Increased damage pool (O473)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Rule. These sources ADD raw percent into ONE sum. The sum takes the soft cap of the passive tree (passivetree_effects.lua
-- cfg.maxDamagePercent 150, softCap.damagePercentH 60: unchanged) and applies once, as 1 + soft(sum) / 100:
--   tree        the passive tree's increments of the hit's damage type, the all-element increment, the worn Spell Damage (as before)
--   uniques     the "more damage" part of the worn unique passives: each passive at most `each`, all together at most `cap`
--   gems        the socketed gem's damage value of the hit's type, held by chaos_gems_config.lua effects cap (25, physical 12)
--   masteries   a spell modifier mastery that is a plain damage effect (a brand) on its own spell: `each`, at most `cap`
--   cardSets    the damage part of the card set of the hit's element, at most `cap`
--   charms      Damage to a monster family (charm), shares the `extras` cap with the weapon family
--   families    the sword's tempo edge, shares the `extras` cap with the charm
--   paragon     the Paragon damage (0.5 a point up to 40 points, the mastery term as before), no cap of its own
-- These stay multiplicative, unchanged: attributes (strength, intelligence, dexterity), the weapon and its Weapon Damage
-- modifier, critical hits, support runes (brand, echo, hex ...), the class factors (classDamage, spell factor), skill terms, the
-- O468 scaling factor, the monster's defence, every price (a "less" of a unique passive, the weapon family's single factor).
-- Healing takes the tree's Healing only; the pool never raises a heal.
return {
	-- the soft cap is the passive tree's (read from ChaosPassiveEffectsConfig when it is loaded): kept here for the tests and the
	-- character sheet when that table is absent
	softCap = {cap = 150, H = 60},

	sources = {
		tree = {label = "Passive tree and Spell Damage"},
		uniques = {label = "Unique passives", each = 10, cap = 40},
		gems = {label = "Gems", cap = 25, capPhysical = 12},
		masteries = {label = "Spell masteries", each = 3, cap = 12},
		cardSets = {label = "Card set", cap = 4},
		charms = {label = "Charms", group = "extras"},
		families = {label = "Weapon family", group = "extras"},
		paragon = {label = "Paragon"}
	},
	-- caps shared by several sources
	groups = {
		extras = {label = "Charms and weapon family", cap = 6}
	},
	-- the order of the lines on the character sheet and in the help line
	order = {"tree", "uniques", "gems", "masteries", "cardSets", "charms", "families", "paragon"}
}

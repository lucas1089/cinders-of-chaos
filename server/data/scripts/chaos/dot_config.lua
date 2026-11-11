-- dot_config.lua: damage over time that is worth casting (O474, owner 2026-11-10: "Also look at how the damage over time
-- effects are. I think they are well below what they should be."). Pure data. Rules: dot_core.lua (tested by
-- server/tests/dot_core_test.lua). Documented in server/README.md "Damage over time (O474)".
--
-- The decisions below were taken by the orchestrator from the audit (scratch SP/dotaudit/report.md) and are the owner's to change;
-- every number of the system is here. The two spell tables keep literal copies of the timings they use
-- (attack_kit_config.lua dot specs, necro_config.lua witheringCurse / soulRot); tests/dot_core_test.lua fails when a copy
-- differs from this file.
ChaosDotConfig = {
	-- 1. one predicate says "this is a damage over time tick" (ChaosDot.isTick): an engine condition tick (ORIGIN_CONDITION), or a
	-- scripted tick (a spell pulse of a dot spell). The spell scripts run in another Lua state than the damage events, so the
	-- scripted tick is marked in a player storage while it is dealt: the id of the creature being hit (-1 outside a tick). The
	-- value only matches that creature, so a hit a tick causes on another one (a nova, a spread) is a plain hit.
	storage = 7103110,

	-- 2. a dot moves on when its host dies with ticks left: the rest continues on the nearest living MONSTER within `radius`
	-- squares of where the host died (never a player, never a summon of a player, no new ticks, never onto a monster that
	-- already carries the same dot of the same caster).
	jump = {radius = 3},

	-- 3. the side dots of a hit spell (Witchfire Bolt, Falling Pyre, Shattered Psyche): `ticks` ticks `tickMs` apart, the first
	-- one tickMs after the cast (Falling Pyre: after the impact); together `share` x the cast's own hit (the average of the
	-- spell's min / max formula). Was 4 to 5 ticks of 2 to 3 s worth 9 to 13% of the hit.
	side = {share = 0.30, ticks = 6, tickMs = 300},

	-- Blightswarm keeps its total (8 ticks of its old tick, 0.45 to 0.6 of its hit) in `ticks` ticks `tickMs` apart.
	swarm = {oldTicks = 8, ticks = 6, tickMs = 300},

	-- 4. kit dots (attack_kit_config.lua shape "dot": Gorehook, Dreamrot, Venom Spiral, Blightbrand, Martyr's Pyre, Crimson
	-- Covenant): the first tick at once, then every tickMs. Their ticks stay (5 to 6); only Blightbrand and Martyr's Pyre grow.
	kit = {tickMs = 400, scale = {blightbrand = 1.25, martyrspyre = 1.10}},

	-- 5. the necromancer line: Withering Curse ticks every tickMs (its amplify still lasts 12 s), Soul Rot every tickMs with its
	-- tick scale x1.5 (1.15 -> 1.725); the first tick of every necro dot is at once.
	necro = {curseTickMs = 250, soulRotTickMs = 400, soulRotScale = 1.725},

	-- 6. gear ailments (Chance to Bleed / Ignite / Poison): up to `maxStacks` per type per target per owner (a fourth replaces
	-- the weakest, unless it is weaker than all of them), each `rounds` ticks `interval` ms apart, together the share of the
	-- hit that caused it that chaos_item_mods.lua `ailment.share` names (40%, as before). The ticks are dealt as
	-- ORIGIN_CONDITION, so every rule that reads a condition keeps working. The item sets and keystones that put their own
	-- engine condition (itemsets.lua, S.dotTick) keep it.
	ailment = {rounds = 8, interval = 500, maxStacks = 3},

	-- 7. the condition icon: a scripted dot against a PLAYER shows the matching condition (the cure removes it and ends the dot):
	-- a zero-damage engine condition of the same type with its own sub id, for the duration of the dot. Monsters show none.
	icon = {
		enabled = true,
		subId = 71097,
		-- combat type name -> condition constant name
		byType = {fire = "CONDITION_FIRE", earth = "CONDITION_POISON", physical = "CONDITION_BLEEDING", energy = "CONDITION_ENERGY",
			ice = "CONDITION_FREEZING", holy = "CONDITION_DAZZLED", death = "CONDITION_CURSED"},
	},

	-- 8. PvP: nothing changes on purpose. Against a PLAYER target every dot keeps the timing AND the size it had before this
	-- round (the old ticks and gaps, the old totals), so a duel's length and the engine's player-against-player halving of every
	-- hit are what they were. A dot never jumps to a player. `side`: the old ticks, gap and first tick of the four side dots
	-- (their old tick sizes are the scripts' own formulas, kept there); `kit` and `necro`: the old gap and first tick, and the
	-- factor that takes the new tick back to the old one.
	pvp = {
		side = {
			witchfire = {ticks = 4, tickMs = 3000, firstMs = 3000},
			fallingpyre = {ticks = 5, tickMs = 3000, firstMs = 3000},
			shatteredpsyche = {ticks = 5, tickMs = 2000, firstMs = 2000},
			blightswarm = {ticks = 8, tickMs = 2000, firstMs = 2000},
		},
		kit = {tickMs = 1000, firstMs = 0, mult = {blightbrand = 1 / 1.25, martyrspyre = 1 / 1.10}},
		necro = {tickMs = 1000, firstMs = 1000, soulRotMult = 1 / 1.5},
	},
}
return ChaosDotConfig

-- Spell combos (O686 phase 6): every number. Plain table, loaded with
--     ChaosSpellCombosConfig = dofile("data/scripts/chaos/spell_combos_config.lua")
-- Design: docs/SPELL_UPGRADES.md section 4 (4.1 rule, 4.2 rows, 4.3 detection, 4.4 client), 5.1, 5.2; logic: spell_combos_core.lua; engine:
-- spell_combos.lua; server/README.md "Spell combos (O686 phase 6)". Owner 2026-11-20: "Deixe os combos, como gelo e fogo, baterem de 10 a
-- 20% a mais": every combo gives +10% to +20% on the hit it triggers, the easier and the more frequent a combo the nearer 10%.
-- Nothing acts while spell_ranks_config.lua `enabled` is false (the combos are one part of the spell upgrades; the same switch) or
-- `enabled` below is false. Never in PvP (spell_ranks_config.lua pvp.combos = false). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- 4.1: the second spell is cast at most `windowMs` after the first, on the same target or within `nearSqm` of where the first hit
	window = {windowMs = 4000, nearSqm = 2},
	-- 4.1 limits: the same combo does not fire on the same target again for `repeatMs`; a player has a pause of `globalMs` between
	-- combos; at most one combo a cast (the best row: the highest bonus, then the order of `rows`)
	limits = {repeatMs = 6000, globalMs = 1200},
	-- 4.3: the ring of the last casts of a player, and how long a cast waits for its first hit (a cast that misses never fires)
	ring = {size = 4, expireMs = 1000},

	-- the element of a hit with two parts (a weapon line spell: physical and an element): the larger part, but an element other than
	-- physical wins when it has at least this share of the larger part
	elementShare = 0.25,

	-- the bonus of every row stays inside these (owner 2026-11-20); tests/spell_combos_test.lua and the model hold every row to it
	band = {min = 0.10, max = 0.20},

	-- a signature combo opens when both spells are at this rank (design 4.2); a reaction is free for everyone
	classMinRank = 5,

	-- the typical rotation (spell_upgrade_model.py reads this block, it does not keep its own number): `triggerShare` of the spell
	-- damage of a rotation lands on a combo-triggered hit (design 4.1: about 40%), at the mean bonus of the rows weighted by
	-- `weight` (how often a typical hunt rotation fires the row next to the others: the easy reactions most, a signature of the
	-- class a little less, a heal combo least). 0.40 x 0.151 = +6.0% of the spell damage (design 5.1). The best legal rotation
	-- (every hit a 20% combo) is 0.40 x 0.20 = +8% (design 4.1); the model holds both.
	-- O686 phase 6b: the riders are counted on top of the bonus (riders.model below). The best legal rotation fights one target: no rider
	-- that hits other enemies counts there, and the two critical riders are text (below), so its gain is still 0.40 x 0.20 = +8%.
	model = {triggerShare = 0.40, typicalMax = 0.065, bestMax = 0.08},

	-- O686 phase 6b: the riders of design 4.2, the `fx` of each row. Monsters only (never a player, never in PvP: a rider needs a row
	-- that fired, and a row never fires in PvP), never combo again: every extra hit runs inside the proc guard with ORIGIN_SPELL and
	-- inside the cast context of the second spell (so the combat log credits it), the way a Form's extra hits do. Kinds:
	--   burst       other enemies within `radius` of the target take `share` of the triggering hit each, at most `cap` (the element of the
	--               hit, or `element`); one burst a fire
	--   chain       up to `targets` other enemies within `radius` take `share` of the hit as `element` damage
	--   deathburst  every enemy the player's hits kill within `ms` bursts: the others within `radius` of it take `share` of the hit that
	--               opened the combo, at most `targets` of them a burst and `cap` bursts a combo
	--   brittle     the target takes +`pct` damage from everyone for `ms` (the Hex rune's way: supports.lua, here ChaosSpellCombos)
	--   holyamp     the target takes +`pct` more HOLY damage from everyone for `ms`
	--   slow        the target is slowed `pct` percent for `ms` (CONDITION_PARALYZE with a formula, as item_powers.lua Frost Ward does)
	--   stun        the target cannot move or attack for `ms` (the weapon families' stun: same sub ids, same immunity timer, a boss only
	--               if its health is under `stun.bossHealth`; never twice inside `stun.restMs`)
	--   hooked      the combo bonus also lands on every hit of the second spell on an enemy the first spell hit (not only the first hit)
	--   hexrenew    the target's Hex (a Hex rune or mastery of the supports) lasts again its full time, when it has one
	--   hot         the second spell's heals (the heal over time pulses) of this player are +`pct` for `ms`
	--   text        NOT built: it needs an engine patch, `why` says which (README "Spell combos (O686 phase 6)")
	-- A damage rider never deals more than its row's share of the hit: `share` is at most the row's `bonus`, and at most `maxShare`.
	riders = {
		maxShare = 0.05,
		stun = {subId = 71034, immuneSubId = 71035, restMs = 3000, bossHealth = 50000},
		-- why a rider is text: `critical` = the critical roll is made in combat.cpp before Lua sees the hit (server/src-patches/
		-- 0001-critical-hit-to-lua.patch only reports it), so a forced critical, and a critical with more critical damage, need a new patch
		why = {critical = "the critical roll is in combat.cpp, a forced critical needs an engine patch"},
		-- the model's picture of a hunt (spell_upgrade_model.py counts the riders from it, tools/combo_numbers.lua prints the numbers): the
		-- other enemies within 1, 2 and 3 sqm of a target (the blend of a one target and a five target hunt), the enemies a player kills a
		-- second, the milliseconds between two hits on one target, the share of a rotation's hits that are holy
		model = {near = {0.4, 0.8, 1.2}, killsPerSecond = 0.2, hitEveryMs = 1500, holyShare = 0.1}
	},

	-- O686 phase 6b: combo masteries, extra effects of the seven mastery nodes of O451 (tree stat comboMod = id; the character holds one
	-- effect a node, so a combo mastery replaces a spell modifier or a plain effect). Each changes one number of the rule above for this
	-- player (spell_combos.lua reads ChaosPassiveCache[pid].comboMod). `node`, `line`, `effect`: the mastery node and the position of the
	-- effect in it (appended after the old ones, client treedata/nodes.lua; tests/spell_masteries_test.lua holds both). `shareGain` is the
	-- model's guess of how much more of a rotation's damage lands on combo hits (relative): the model counts typical x shareGain and holds
	-- it under `maxGain` of the spell damage. `floor` keeps the cut limits above these values.
	masteries = {
		maxGain = 0.015,
		floor = {repeatMs = 3000, globalMs = 600},
		choices = {
			{id = 1, line = "thief", node = 665, effect = 8, name = "Short Memory", repeatMs = -2000, shareGain = 0.08},
			{id = 2, line = "necromancer", node = 666, effect = 7, name = "Lingering Window", windowMs = 1500, shareGain = 0.12},
			{id = 3, line = "monk", node = 667, effect = 8, name = "Eager Rhythm", globalMs = -400, shareGain = 0.05},
			{id = 4, line = "templar", node = 668, effect = 7, name = "Lingering Window", windowMs = 1500, shareGain = 0.12},
			{id = 5, line = "warrior", node = 703, effect = 8, name = "Short Memory", repeatMs = -2000, shareGain = 0.08},
			{id = 6, line = "ranger", node = 704, effect = 8, name = "Eager Rhythm", globalMs = -400, shareGain = 0.05},
			{id = 7, line = "mystic", node = 705, effect = 7, name = "Lingering Window", windowMs = 1500, shareGain = 0.12}
		}
	},

	-- O692: `burst` is the burst on the target when the row fires: ChaosVfx names (data/lib/chaos_vfx.lua, sent raw so no Form swap),
	-- existing effects of the element(s) of the row (first, then second; a class row an effect of its weapon line or element), sent
	-- together by spell_combos.lua announce. No new sprite; the ids are tagged in data/spells/spell_fx_elements.csv.
	-- rows. kind: reaction (any class, by the element of the two hits, the element after a Form conversion counts), class (a signature
	-- combo of a class line: spell ids of the two casts, both at rank classMinRank or more), heal (the second spell is a heal; the
	-- bonus is on the heal). first / second: {element = name} or {spells = {ids}}. `show` (signature and heal rows) is the pair as the Codex page writes it, spell names as in data/spells/forms.csv (tests hold it to
	-- the ids). `name` is the English name the client shows
	-- (client_chaos_locale/pt_br.lua has the pt-BR text, held equal to `pt` by tests/spell_combos_test.lua). `rider` is the design's
	-- rider text: it has no damage of its own and is not built in phase 6 (README "Spell combos (O686 phase 6)").
	rows = {
		-- element reactions, free for every class
		{id = "steam_burst", burst = {"frost_nova", "fire_explosion"}, name = "Steam Burst", pt = "Explosão de Vapor", kind = "reaction", first = {element = "ice"},
			second = {element = "fire"}, bonus = 0.10, weight = 3, rider = "a burst in 1 sqm",
			fx = {kind = "burst", radius = 1, share = 0.02, cap = 3}},
		{id = "thermal_shock", burst = {"fireball_hit", "ice_shatter"}, name = "Thermal Shock", pt = "Choque Térmico", kind = "reaction", first = {element = "fire"},
			second = {element = "ice"}, bonus = 0.12, weight = 2, rider = "the target is brittle for 3 s",
			fx = {kind = "brittle", ms = 3000, pct = 0.02}},
		{id = "overload", burst = {"lightning_hit", "fire_explosion"}, name = "Overload", pt = "Sobrecarga", kind = "reaction", first = {element = "energy"},
			second = {element = "fire"}, bonus = 0.12, weight = 2, rider = "the same energy to 3 enemies near",
			fx = {kind = "chain", radius = 3, targets = 3, share = 0.015, element = "energy"}},
		{id = "pyre_of_the_dead", burst = {"shadow_eruption", "fire_explosion"}, name = "Pyre of the Dead", pt = "Pira dos Mortos", kind = "reaction", first = {element = "death"},
			second = {element = "fire"}, bonus = 0.15, weight = 1, rider = "enemies that die in the next 3 s burst",
			fx = {kind = "deathburst", ms = 3000, radius = 1, share = 0.03, cap = 3, targets = 3}},
		{id = "mudslide", burst = {"earth_spikes", "ice_shatter"}, name = "Mudslide", pt = "Deslizamento de Lama", kind = "reaction", first = {element = "earth"},
			second = {element = "ice"}, bonus = 0.10, weight = 2, rider = "the target is slowed 30% for 3 s",
			fx = {kind = "slow", ms = 3000, pct = 30}},
		{id = "consecrated_ash", burst = {"fireball_hit", "holy_hit"}, name = "Consecrated Ash", pt = "Cinza Consagrada", kind = "reaction", first = {element = "fire"},
			second = {element = "holy"}, bonus = 0.15, weight = 1, rider = "the target takes 15% more holy for 3 s",
			fx = {kind = "holyamp", ms = 3000, pct = 0.15}},

		-- signature combos, one to three per class line (spell ids: data/spells/forms.csv, spells_chaos.xml)
		{id = "pinned_shot", burst = {"thrust_e"}, show = "Snare Trap / Seeker Mine > Final Verdict / Twin Verdict / Sunspear", name = "Pinned Shot", pt = "Tiro Cravado", kind = "class",
			first = {spells = {99, 100}}, -- Snare Trap, Seeker Mine
			second = {spells = {218, 144, 19}}, -- Final Verdict, Twin Verdict, Sunspear
			bonus = 0.20, weight = 1.5, rider = "the second hit is a guaranteed critical",
			fx = {kind = "text", why = "critical"}},
		{id = "meat_grinder", burst = {"claw_rake_e"}, show = "Gorehook > Reaping Gyre / Butcher's Gyre / Earthbreaker", name = "Meat Grinder", pt = "Moedor de Carne", kind = "class",
			first = {spells = {2}}, -- Gorehook
			second = {spells = {220, 105, 221}}, -- Reaping Gyre, Butcher's Gyre, Earthbreaker
			bonus = 0.20, weight = 1.5, rider = "on the enemies the hook pulled",
			fx = {kind = "hooked"}},
		{id = "anvil_chain", burst = {"earth_spikes"}, show = "Iron Chain > Quaking Stomp", name = "Anvil Chain", pt = "Corrente da Bigorna", kind = "class",
			first = {spells = {196}}, -- Iron Chain
			second = {spells = {84}}, -- Quaking Stomp
			bonus = 0.18, weight = 1.5, rider = "the stomp stuns 0.5 s",
			fx = {kind = "stun", ms = 500}},
		{id = "backstab", burst = {"sword_slash_e"}, show = "Shadow Step > Gutting Slash / Death Between Heartbeats", name = "Backstab", pt = "Facada nas Costas", kind = "class",
			first = {spells = {240}}, -- Shadow Step
			second = {spells = {45, 157}}, -- Gutting Slash, Death Between Heartbeats
			bonus = 0.20, weight = 1.5, rider = "the second hit crits for +50% crit damage",
			fx = {kind = "text", why = "critical"}},
		{id = "rotting_curse", burst = {"shadow_eruption"}, show = "Withering Curse > Soul Rot / Blightbrand / Corpse Explosion", name = "Rotting Curse", pt = "Maldição Apodrecida", kind = "class",
			first = {spells = {182}}, -- Withering Curse
			second = {spells = {183, 113, 185}}, -- Soul Rot, Blightbrand, Corpse Explosion
			bonus = 0.18, weight = 1.5, rider = "the curse bursts with the hit",
			fx = {kind = "burst", radius = 2, share = 0.02, cap = 3, element = "death"}},
		{id = "psychic_shatter", burst = {"arcane_hit"}, show = "Bewitching Hex > Shattered Psyche / Dreamrot", name = "Psychic Shatter", pt = "Estilhaço Psíquico", kind = "class",
			first = {spells = {53}}, -- Bewitching Hex
			second = {spells = {228, 43}}, -- Shattered Psyche, Dreamrot
			bonus = 0.20, weight = 1.5, rider = "the hex time is renewed",
			fx = {kind = "hexrenew"}},
		{id = "echoing_mend", burst = {"aura_burst_gold"}, show = "Mirror Mend > Lucid Reverie", name = "Echoing Mend", pt = "Cura Ecoante", kind = "heal",
			first = {spells = {96}}, -- Mirror Mend
			second = {spells = {97}}, -- Lucid Reverie
			bonus = 0.15, weight = 1, rider = "the party's heal over time ticks +15% for 6 s",
			fx = {kind = "hot", ms = 6000, pct = 0.15}},
	},
}

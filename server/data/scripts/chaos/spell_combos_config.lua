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
	model = {triggerShare = 0.40, typicalMax = 0.065, bestMax = 0.08},

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
			second = {element = "fire"}, bonus = 0.10, weight = 3, rider = "a burst in 1 sqm"},
		{id = "thermal_shock", burst = {"fireball_hit", "ice_shatter"}, name = "Thermal Shock", pt = "Choque Térmico", kind = "reaction", first = {element = "fire"},
			second = {element = "ice"}, bonus = 0.12, weight = 2, rider = "the target is brittle for 3 s"},
		{id = "overload", burst = {"lightning_hit", "fire_explosion"}, name = "Overload", pt = "Sobrecarga", kind = "reaction", first = {element = "energy"},
			second = {element = "fire"}, bonus = 0.12, weight = 2, rider = "the same energy to 3 enemies near"},
		{id = "pyre_of_the_dead", burst = {"shadow_eruption", "fire_explosion"}, name = "Pyre of the Dead", pt = "Pira dos Mortos", kind = "reaction", first = {element = "death"},
			second = {element = "fire"}, bonus = 0.15, weight = 1, rider = "enemies that die in the next 3 s burst"},
		{id = "mudslide", burst = {"earth_spikes", "ice_shatter"}, name = "Mudslide", pt = "Deslizamento de Lama", kind = "reaction", first = {element = "earth"},
			second = {element = "ice"}, bonus = 0.10, weight = 2, rider = "the target is slowed 30% for 3 s"},
		{id = "consecrated_ash", burst = {"fireball_hit", "holy_hit"}, name = "Consecrated Ash", pt = "Cinza Consagrada", kind = "reaction", first = {element = "fire"},
			second = {element = "holy"}, bonus = 0.15, weight = 1, rider = "the target takes 15% more holy for 3 s"},

		-- signature combos, one to three per class line (spell ids: data/spells/forms.csv, spells_chaos.xml)
		{id = "pinned_shot", burst = {"thrust_e"}, show = "Snare Trap / Seeker Mine > Final Verdict / Twin Verdict / Sunspear", name = "Pinned Shot", pt = "Tiro Cravado", kind = "class",
			first = {spells = {99, 100}}, -- Snare Trap, Seeker Mine
			second = {spells = {218, 144, 19}}, -- Final Verdict, Twin Verdict, Sunspear
			bonus = 0.20, weight = 1.5, rider = "the second hit is a guaranteed critical"},
		{id = "meat_grinder", burst = {"claw_rake_e"}, show = "Gorehook > Reaping Gyre / Butcher's Gyre / Earthbreaker", name = "Meat Grinder", pt = "Moedor de Carne", kind = "class",
			first = {spells = {2}}, -- Gorehook
			second = {spells = {220, 105, 221}}, -- Reaping Gyre, Butcher's Gyre, Earthbreaker
			bonus = 0.20, weight = 1.5, rider = "on the enemies the hook pulled"},
		{id = "anvil_chain", burst = {"earth_spikes"}, show = "Iron Chain > Quaking Stomp", name = "Anvil Chain", pt = "Corrente da Bigorna", kind = "class",
			first = {spells = {196}}, -- Iron Chain
			second = {spells = {84}}, -- Quaking Stomp
			bonus = 0.18, weight = 1.5, rider = "the stomp stuns 0.5 s"},
		{id = "backstab", burst = {"sword_slash_e"}, show = "Shadow Step > Gutting Slash / Death Between Heartbeats", name = "Backstab", pt = "Facada nas Costas", kind = "class",
			first = {spells = {240}}, -- Shadow Step
			second = {spells = {45, 157}}, -- Gutting Slash, Death Between Heartbeats
			bonus = 0.20, weight = 1.5, rider = "the second hit crits for +50% crit damage"},
		{id = "rotting_curse", burst = {"shadow_eruption"}, show = "Withering Curse > Soul Rot / Blightbrand / Corpse Explosion", name = "Rotting Curse", pt = "Maldição Apodrecida", kind = "class",
			first = {spells = {182}}, -- Withering Curse
			second = {spells = {183, 113, 185}}, -- Soul Rot, Blightbrand, Corpse Explosion
			bonus = 0.18, weight = 1.5, rider = "the curse bursts with the hit"},
		{id = "psychic_shatter", burst = {"arcane_hit"}, show = "Bewitching Hex > Shattered Psyche / Dreamrot", name = "Psychic Shatter", pt = "Estilhaço Psíquico", kind = "class",
			first = {spells = {53}}, -- Bewitching Hex
			second = {spells = {228, 43}}, -- Shattered Psyche, Dreamrot
			bonus = 0.20, weight = 1.5, rider = "the hex time is renewed"},
		{id = "echoing_mend", burst = {"aura_burst_gold"}, show = "Mirror Mend > Lucid Reverie", name = "Echoing Mend", pt = "Cura Ecoante", kind = "heal",
			first = {spells = {96}}, -- Mirror Mend
			second = {spells = {97}}, -- Lucid Reverie
			bonus = 0.15, weight = 1, rider = "the party's heal over time ticks +15% for 6 s"},
	},
}

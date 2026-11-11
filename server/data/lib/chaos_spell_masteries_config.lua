-- Spell modifier masteries (O451): every number and every choice. Rules: data/lib/chaos_supports.lua "spell modifier
-- masteries"; the stored choice and the cache: data/scripts/chaos/spell_masteries.lua; the tree nodes: client
-- game_passivetree/treedata/nodes.lua (the mastery nodes 665 - 668 and 703 - 705), the model: server/tools/spell_mastery_model.py.
-- Plain table, loaded with  dofile("data/lib/chaos_spell_masteries_config.lua")  in both Lua states (scripts and spells).
-- Lua 5.1 / LuaJIT and 5.3.
--
-- A spell modifier is one more effect of a mastery node. Its tree stat is  spellMod = <id>  (the id of the row below). The
-- character holds one effect per mastery node and a line has one mastery node, so at most one modifier at a time.
-- The modifier gives ONE named spell a free support effect: the effect a support rune of data/lib/chaos_supports_config.lua
-- gives, at the lowest tier (`tier`, a Common rune: runes of that tier drop at every level band), reduced to `strength`
-- percent in the fields of `reduce` (no support has a price, so the effect is weaker instead). It takes no rune slot.
-- It never adds to a real rune of the same support on that spell: the stronger one counts. A brand never joins another brand.

return {
	-- the player storage the passive tree listener writes (spell_masteries.lua) and both Lua states read: the id of the
	-- held modifier, or -1. 7109990 - 7109992 are the cast context and Reprisal, 7110000 - 7111999 the rune sockets.
	storage = 7109993,

	tier = 1, -- the rune level of the support (1 = Common, the lowest tier that drops at every band)
	strength = 75, -- percent of that tier's number in the fields below

	-- the fields of a support's effect that the strength reduces (value, value2: chaos_supports_config.lua `values`,
	-- `values2`). The other field stays as the rune has it (the number of enemies of Fork, the radius of Breadth).
	reduce = {
		fork = {"value2"}, -- the share of the hit the forked enemies take
		breadth = {"value2"}, -- the share of the average hit the missed enemies take
		shatter = {"value"}, -- the share of the hit the neighbours take
		quickening = {"value"}, -- the cooldown cut in percent
		hex = {"value"}, -- the damage taken in percent
		echo = {"value"} -- the chance per cast in percent (the damage of the second strike stays 50%)
	},

	-- O473 (2026-11-10): a choice whose support is a plain damage effect (a brand) is not a free support: while its spell is cast it adds
	-- raw percent to the one additive damage pool (damage_pool_config.lua sources.masteries: +3 each, at most 12), so it is "increased
	-- damage" and shares the soft cap with the tree. Before: the free brand, 75% of a Common rune's extra element damage (dawnbrand,
	-- gravebrand, stormbrand `value` reduced) as a separate multiplier. The other supports (fork, breadth, shatter, quickening, hex,
	-- echo) stay free supports: they add targets, strikes or cooldown, not increased damage.
	damage = {dawnbrand = true, gravebrand = true, stormbrand = true},

	-- the choices: id = the tree stat spellMod; line = the class line (the mastery node's `line`); node, effect = the mastery
	-- node and the position of the effect in it (append only, an existing effect keeps its position); name = the effect's name;
	-- spell = a spell id that every class of the line casts (rotation_sim.py: the three classes of the line have it in their
	-- kit); support = the key of the support. The client text of each is in treedata/spellmods.lua (client game_passivetree).
	choices = {
		-- Warrior line, Warbound Discipline (703): three more effects after Hammerfall, Tempered Hide, Cruel Edge, Shield Drill
		{id = 1, line = "warrior", node = 703, effect = 5, name = "Gore Fork", spell = 2, support = "fork"},
		{id = 2, line = "warrior", node = 703, effect = 6, name = "Echoing Slam", spell = 225, support = "echo"},
		{id = 3, line = "warrior", node = 703, effect = 7, name = "Wide Cry", spell = 29, support = "breadth"},
		-- Ranger line, Hunter's Discipline (704)
		{id = 4, line = "ranger", node = 704, effect = 5, name = "Splintering Spear", spell = 19, support = "shatter"},
		{id = 5, line = "ranger", node = 704, effect = 6, name = "Hallowed Ground", spell = 216, support = "dawnbrand"},
		{id = 6, line = "ranger", node = 704, effect = 7, name = "Hunter's Mark", spell = 214, support = "hex"},
		-- Mystic line, Arcane Discipline (705): only two spells outside the utility kit that all three classes cast
		{id = 7, line = "mystic", node = 705, effect = 5, name = "Crimson Fork", spell = 203, support = "fork"},
		{id = 8, line = "mystic", node = 705, effect = 6, name = "Storm Rupture", spell = 152, support = "stormbrand"},
		-- Thief line, Shadow Discipline (665)
		{id = 9, line = "thief", node = 665, effect = 5, name = "Twin Toss", spell = 236, support = "fork"},
		{id = 10, line = "thief", node = 665, effect = 6, name = "Wide Smoke", spell = 241, support = "breadth"},
		{id = 11, line = "thief", node = 665, effect = 7, name = "Echoing Flurry", spell = 73, support = "echo"},
		-- Necromancer line, Grave Mastery (666)
		{id = 12, line = "necromancer", node = 666, effect = 4, name = "Cursed Marrow", spell = 106, support = "hex"},
		{id = 13, line = "necromancer", node = 666, effect = 5, name = "Grave Wail", spell = 112, support = "gravebrand"},
		{id = 14, line = "necromancer", node = 666, effect = 6, name = "Splintered Rot", spell = 113, support = "shatter"},
		-- Monk line, Inner Discipline (667)
		{id = 15, line = "monk", node = 667, effect = 5, name = "Wide Mist", spell = 67, support = "breadth"},
		{id = 16, line = "monk", node = 667, effect = 6, name = "Splitting Palm", spell = 64, support = "shatter"},
		{id = 17, line = "monk", node = 667, effect = 7, name = "Quick Heel", spell = 65, support = "quickening"},
		-- Templar line, Sacred Oath (668)
		{id = 18, line = "templar", node = 668, effect = 4, name = "Echoing Ground", spell = 190, support = "echo"},
		{id = 19, line = "templar", node = 668, effect = 5, name = "Marked Cut", spell = 121, support = "hex"},
		{id = 20, line = "templar", node = 668, effect = 6, name = "Bell of Dawn", spell = 128, support = "dawnbrand"}
	}
}

-- spell_id_pool_config.lua: the spell ids reserved for the 21 line-quest spells (docs/CLASSES.md, server/README.md "Spell id pool").
-- A spell id is one byte on the wire until the engine patch 0079 (wide spell ids) is on, and all 255 were believed used. They
-- were not: the 15-spell cap (tools/patch_spell_cap.py CAP, rows with no class left) and the cure retirement
-- (tools/retire_cure_spells.py) comment out many stock spells, and tests/spell_ids_test.lua used to count the ids of
-- the moved stock spells (tools/patch_spell_ids.py) as taken although their spells are retired. This table names the ids
-- the quest spells take, so two systems never pick the same one. tests/spell_ids_test.lua checks that every id here is
-- free in the install: no stock spell keeps it, no Chaos spell uses it, and a retiring tool freed it.
--   ids    one per quest spell, in the order of the spec: 7 lines x (level 500 attack, level 800 buff, level 1200 ultimate)
--   spare  free ids left for more spells; take them from the front
-- A spell that takes an id writes the same number in spells_chaos.xml (and in attack_kit_config.lua for a kit spell) and
-- the client regenerates spelldata.lua (client/tools/gen_spell_data.py); the client moves a stock entry that held the id
-- by itself (game_chaosspells/spellfix.lua chaosIds). Plain table, Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	ids = {
		142, 143, 148, 149, 150, 151, 152, 153, 154, 155, 156,
		157, 158, 159, 160, 172, 173, 174, 177, 178, 237
	},
	spare = {40, 41, 47, 52, 60, 101, 165, 168, 171}
}

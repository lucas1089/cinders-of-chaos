-- Loot bag instead of monster bodies (O435; corpse_core.lua, corpse_bag.lua, engine src-patch 0089, items.xml step
-- tools/patch_monster_corpses.py; server/README.md "Loot bag instead of corpses"). Returned as a table, loaded as
-- Chaos.corpseConfig. The one place of the rule: tools/patch_monster_corpses.py reads bagId, name, slots and seconds
-- from here too, and the client's ground labels (game_groundlabels, groundlabelslogic.lua CORPSE_BAG_ID) carry the same
-- bagId (tests/corpse_bag_test.lua checks both).
-- Owner 2026-11-08 (pt-BR): "remover os corpos de criaturas mortos do jogo e deixar so aquela bagzinha". Lua 5.1 /
-- LuaJIT compatible.
return {
	-- the switch: false = every monster leaves its own corpse again (a reload is enough, no rebuild)
	enabled = true,

	-- the bag: item 6068, the container the monster import fallback (tools/fix_monster_xml.py FALLBACK_CORPSE) already
	-- gave 191 monsters. It is a container with corpseType set, so everything that treats a corpse as a corpse
	-- (ItemType:isCorpse, the corpse owner, loot, auto loot, ground labels, Necromancer corpse spells) takes it as one.
	bagId = 6068,

	-- items.xml of the bag (tools/patch_monster_corpses.py): the name, the slots (the biggest stock corpse holds 60: bonus
	-- loot, orbs and waystones come on top of the stock loot) and the seconds it lies on the ground before it vanishes with
	-- whatever is left in it. No body remains after it (the stock chain 6068 -> 5527 -> 5528 left a pile for 3 minutes more).
	name = "sack of loot",
	article = "a",
	slots = 60,
	seconds = 180,

	-- the monsters whose OWN corpse id stays as it is: scripts of the base server look for these items by id.
	--   8934, 8967, 8968, 8969   the four Elemental Overlord corpses of the sphere quest (movements/.../summonOverlord.lua
	--                            summons the boss when the corpse is moved onto the altar)
	--   12545, 12546             Glitterscale's and Heoni's bodies of the Father's Burden quest (actions/.../corpse.lua)
	-- Everything else is the bag. A monster whose own corpse is 0 (22 Chaos monsters, summons, minions) leaves nothing,
	-- as before.
	keepIds = {8934, 8967, 8968, 8969, 12545, 12546},
}

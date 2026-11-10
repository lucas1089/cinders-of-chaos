-- defence_config.lua: the numbers of the defence rules that a monster and (in the player stage) a player share
-- (server/README.md "Monster defence (O462)"). Plain table, loaded as Chaos.defence = dofile("data/scripts/chaos/defence_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. No other file holds a copy of these four numbers: read them from here.
--
-- armour of a hit of size H: reduction = A / (A + armourHitFactor x H). A big hit loses less of itself than a small one.
-- physicalReductionCap: armour, the physical resistance of the monster and the physical reduction modifier together
--   remove at most this percent of a physical hit.
-- resistCap: the highest element resistance (percent) after the rank bonus. Penetration is taken off after it.
-- blockCap: the highest chance (percent) to block an attack hit.
-- resistFloor: the lowest a resistance goes after penetration (a negative resistance raises the damage taken).
return {
	armourHitFactor = 0.07,
	physicalReductionCap = 90,
	resistCap = 75,
	blockCap = 75,
	resistFloor = -100
}

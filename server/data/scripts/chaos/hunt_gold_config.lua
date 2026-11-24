-- The gold per hour of hunting by character level: the ONE curve every price or reward sized in "hours of hunting gold"
-- reads (O751, owner 2026-11-24 "Acertar o ouro"; server/README.md "One gold curve (O751)", docs/PRICES.md).
-- Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
--
-- Readers: gamble_config.lua (balance.hunting), professions_config.lua (balance.hunting), boss_roulette_config.lua and
-- cursedchest_config.lua (the prize gold), embercache_config.lua (income; weeklychest_config.lua and
-- tools/mainquest_model.lua read it there), respec_config.lua (fullCurve), tools/store_model.lua,
-- tools/roulette_model.lua, tools/gen_item_prices.py (the crafted gear cap).
--
-- The numbers are tools/loot_model.lua's SALE gold (`luajit tools/loot_model.lua --income` prints them; `--check` in CI
-- holds every point from 40 to 2500 within 5% of the model, never falling): the pool's hunts of the level (+-15% of it up
-- to 650, from 800 the progression window 0.8-1.1 x the level; base and late monsters together), the stock loot of their
-- monsters thinned by the corpse rule of pace_config.lua at the pack model's kills per hour (tools/spawn_tuning.json
-- paceKillsPerHour), coins and junk at the NPC price, gear at what an NPC pays for the copy that drops (rarity x
-- 1 + item level / 200, data/lib/chaos_item_prices.lua), plus the Chaos extra rolls (loot_config.lua). The Rare+ pieces of
-- the stock roll count at their plain price x the item level: a hunter equips, salvages or trades them (sold to an NPC at
-- x6-24 they would make 234k / 977k / 2.58M / 2.29M at 100 / 300 / 500 / 1000; the ceiling, printed by --income). Gold
-- finds, item find, pets, events, the tiers' rarity floors, rifts and waystones are not in it. Linear between the points,
-- flat beyond. The level 8 point is not modelled (the base loot data starts at level 40): the one of before (19,000).
-- The level 40 point sits 4% above the model (62,744) so the professions' first tiers keep their prices.
--
-- Before O751 four configs carried the "Respec" table of tools/respec_income.py, an unpaced hunt with no corpse rule and
-- the old kill speed: {8, 19000} {40, 83000} {100, 358839} {300, 881866} {500, 5548330} {1000, 9519711}, flat beyond
-- 1000. The corpse rule of 2026-10-20 / O285 cut that gold, so it was 2.1x the hunt at 100, 4.6x at 500 and 5.9x at 1000.
-- tools/loot_model.lua's corpse gold (coins and plain NPC prices only) was the nearer one: 138k / 454k / 834k at
-- 100 / 300 / 500, under this curve by the item level and rarity of the gear and the extra rolls.
return {
	hunting = {{8, 19000}, {40, 65000}, {100, 164000}, {300, 619000}, {500, 1197000}, {650, 1262000}, {800, 1325000},
		{1000, 1550000}, {1300, 1687000}, {1600, 1837000}, {2000, 1839000}, {2500, 1970000}}
}

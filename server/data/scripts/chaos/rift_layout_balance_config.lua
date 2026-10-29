-- Limits of the rift layout model (tools/rift_layout_model.lua --check, server/README.md "Rifts", Layout size and
-- density, O309). Data only. Owner report 2026-10-29 (tester): "tem uns mapas absurdamente grandes e com densidade muito
-- baixa pelo tamanho, fiquei 10min so andando": a tier 6 Forsaken Sanctum with 214 monsters on a map of 15,000 walkable
-- tiles, mostly empty grey floor.
--
-- The model generates `samples` layouts per rift theme and size band (the seeds below, dark tile set off, the same
-- generator the live builder uses) and, per layout and per tier of the band (the first and the last: the first has the
-- fewest monsters on the same map), reads the plan the run would make: monsters (R.density, solo, no modifiers), the live
-- cap, the walking distance arrival -> arena. Then:
--   tilesPerMonster  walkable tiles / planned monsters: the density a player sees over the whole map
--   tilesPerLive     walkable tiles / monsters alive at once: what the floor looks like at one moment
--   sweepSeconds     a full clear walks past every part of the map: walkable / sweepWidth steps (the width of ground a
--                    player sees and clears on each step) at the walking speed of the tier's level
--   routeSeconds     the run to the arena (route x walk.sweep, as the clear time model of rift_core.lua R.walkSeconds)
-- and the limits check them for every layout; walkable, route and the spread of a band are bounded too.
return {
	samples = 4, -- layouts per theme and band
	seedBase = 500, seedStep = 37, -- seed of sample i = seedBase + i x seedStep
	sweepWidth = 8, -- tiles of width cleared per step of the full sweep (the client shows 15 x 11 tiles; caves wind, so about half)

	limits = {
		tilesPerMonster = 34, -- at most this many walkable tiles per planned monster (the Sanctum of the report: 54-65; now 27-33)
		tilesPerLive = 75, -- at most this many walkable tiles per monster alive at once
		sweepSecondsMax = 300, -- the whole map swept in at most 5 minutes ...
		sweepShare = 0.30, -- ... and in at most this share of the band's time limit
		routeSecondsMax = 150, -- arrival -> arena in at most 2.5 minutes of walking
		walkableMax = {7500, 11000, 15500}, -- walkable tiles per band, no layout above
		walkableMin = {4500, 7000, 10500}, -- ... and none below (a rift stays a big map)
		spreadMax = 1.5, -- the largest layout of a band over the smallest
		typicalTolerance = 0.15 -- layout.typical (the density model's typical layout) within this of the measured mean
	}
}

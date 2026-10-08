-- Respec prices (respec_core.lua, respec.lua). Every number of the passive tree / Paragon respec rules is here.
-- The curve is ~37.5 minutes of hunting gold at the level (README "Respec"), measured with
-- server/tools/respec_income.py: best spawned hunt per level, coins + the NPC sell value of the drops.
--   level  100: Dragons     ~359k gold/h      level 300: Demons    ~882k gold/h
--   level  500: Soul War   ~5.55M gold/h      level 600: Soul War ~6.34M gold/h     level 1000: Soul War ~9.52M gold/h
ChaosRespecConfig = {
	-- full resets (and single-node refunds) are free below this level
	freeBelowLevel = 50,
	-- full reset of the passive tree: {level, gold} points, linear in between, the last slope past the last point
	fullCurve = {
		{50, 50000},
		{100, 225000},
		{300, 565000},
		{500, 3450000},
		{600, 3950000},
		{1000, 5950000}
	},
	-- prices are rounded down to this many gold
	roundTo = 1000,
	-- single-node refund = full reset x nodeShare (1.5 of the 37.5 minutes), at least nodeMin gold
	nodeShare = 0.04,
	nodeMin = 1000,
	-- Paragon reset = full reset x paragonFactor (the same rule; Paragon unlocks at level 1000)
	paragonFactor = 1.0,
	-- one free full reset after the vocation changed (ascension, class migration); the vocation id the last free
	-- reset was granted for is kept in this storage (respec.lua)
	freeVocationStorage = 7100550
}

return ChaosRespecConfig

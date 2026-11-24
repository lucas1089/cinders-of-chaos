-- Respec prices (respec_core.lua, respec.lua). Every number of the passive tree / Paragon respec rules is here.
-- The curve is `minutes` (37.5) of hunting gold at the level (README "Respec"): O751, the one gold curve
-- (hunt_gold_config.lua) at each of its points from level 100, rounded down to 1,000 gold, and 50,000 at level 50.
-- Before O751 it was the "Respec" table of server/tools/respec_income.py (an unpaced hunt): {50, 50000} {100, 225000}
-- {300, 565000} {500, 3450000} {600, 3950000} {1000, 5950000}, the last slope past 1000 (6,950,000 at 1200).
local MINUTES = 37.5
local function fullCurve()
	local out = {{50, 50000}}
	for _, p in ipairs(dofile("data/scripts/chaos/hunt_gold_config.lua").hunting) do
		if p[1] >= 100 then
			out[#out + 1] = {p[1], math.floor(p[2] * MINUTES / 60 / 1000) * 1000}
		end
	end
	return out
end
ChaosRespecConfig = {
	-- full resets (and single-node refunds) are free below this level
	freeBelowLevel = 50,
	-- full reset of the passive tree: {level, gold} points, linear in between, the last slope past the last point
	minutes = MINUTES,
	fullCurve = fullCurve(),
	-- prices are rounded down to this many gold
	roundTo = 1000,
	-- single-node refund = full reset x nodeShare (1.5 of the 37.5 minutes), at least nodeMin gold
	nodeShare = 0.04,
	nodeMin = 1000,
	-- Paragon reset = full reset x paragonFactor (the same rule; Paragon unlocks at level 1000)
	paragonFactor = 1.0,
	-- one free full reset after the vocation changed (ascension, class migration); the vocation id the last free
	-- reset was granted for is kept in this storage (respec.lua)
	freeVocationStorage = 7100550,
	-- Tester bots (testers_core.lua, server/README.md "Tester bots"): their resets, node refunds and mastery changes cost
	-- no gold, so a bot can verify keystones at any level. Nothing is credited: no gold is created, so none can leave
	-- the character. Only a character that passes ChaosTestersCore.safetyProblem and isTesterName AND carries the
	-- tester storage; at most perDay waived payments per day (UTC day number and count in the two storages, inside the
	-- tester block 7102900-7102909 of chaos_constants.lua). Every waiver is logged.
	testerWaiver = {perDay = 400, storageDay = 7102905, storageUsed = 7102906}
}

return ChaosRespecConfig

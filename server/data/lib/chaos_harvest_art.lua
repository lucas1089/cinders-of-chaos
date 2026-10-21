-- chaos_harvest_art.lua: the harvest kit of the client pair 33 on the server side, behind one switch.
-- Loaded with  ChaosHarvestArt = dofile("data/lib/chaos_harvest_art.lua")  (server/tools/install_pack33_items.py,
-- install_harvest_event.py, install_content_areas.py and area_plan_decor.py read the switch line). Plain Lua, no
-- engine calls at load (server/tests/harvest_event_test.lua).
--
-- Pair switch (M.PAIR33, OFF: pair 33 is not built yet, client/MANIFEST.md "Pair 33 packs"). A client on pair 32 or
-- older has no outfits 2658..2667 and no items 38093..38607 (it would draw nothing). The kit half of the pair only: the
-- cosmetics of the same pair (wings, head pieces, capes) have their own switch; flip both when the pair ships.
-- On:
--   * install_content_areas.py places the two event areas of server/tools/areaplan/events/ (the Haunted Harvest:
--     haunted_harvest.json above, harvest_catacombs.json below) at their origins;
--   * the area planner merges server/tools/areaplan/decor_pack33_kit.json (the biomes harvest and harvest_crypt get
--     the kit's corn, pumpkins, tombstones, lanterns, coffins and urns);
--   * data/scripts/chaos/harvest_event.lua dresses the areas (pumpkin patches, graves, the crypt seal, the ritual
--     circle, coffins, cauldrons, the corn maze) and runs the event in its window;
--   * the rows of client/tools/sprites/monster_looks/harvest_picks.csv go into picks.csv (then
--     server/tools/apply_monster_looks.py writes the kit looks below into the monsters' files; tools/ci/check_content.py
--     PAIR_OUTFITS follows the pair).
-- Off: nothing places the items, the event never opens, the monsters keep their stock looks.
--
-- What it holds (art: client/tools/sprites/gen_pack33.py `set33 kit`, docs/CREDITS.md):
--   * ten looks 2658..2667: five monsters, four critters and the 5x5 boss of the event (monster -> look below);
--   * 514 items and the boss corpse (server ids 41093..41607, data/lib/chaos_pack33_kit.lua, installed by
--     server/tools/install_pack33_items.py).

local M = {}

M.PAIR33 = true

local ok, kit = pcall(dofile, "data/lib/chaos_pack33_kit.lua")
M.kit = ok and kit or {first = 41093, last = 41607, items = {}, states = {}, decay = {}}

-- monster name -> {kit look, stock look it carries while the switch is off}
M.monsters = {
	["Hexwhisker Cat"] = {look = 2658, stock = 276},
	["Reapmoon Lycan"] = {look = 2659, stock = 308},
	["Thornhex Crone"] = {look = 2660, stock = 54},
	["Malvorn the Hollow King"] = {look = 2661, stock = 287},
	["Gourdmaw Brute"] = {look = 2662, stock = 292},
	["Gallows Raven"] = {look = 2663, stock = 122},
	["Strawhusk Stalker"] = {look = 2664, stock = 194},
	["Barrowbone Archer"] = {look = 2665, stock = 33},
	["Barrowbone Reaver"] = {look = 2666, stock = 298},
	["Lamenting Shade"] = {look = 2667, stock = 78}
}

-- the look a monster should carry now
function M.lookOf(name, current)
	local m = M.monsters[name]
	if not m then
		return current
	end
	return M.PAIR33 and m.look or m.stock
end

return M

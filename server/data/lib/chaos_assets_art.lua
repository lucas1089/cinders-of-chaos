-- chaos_assets_art.lua: the catacomb kit things of the client pair 27 trial on the server side, behind one switch.
-- Loaded with  ChaosAssetsArt = dofile("data/lib/chaos_assets_art.lua")  (server/tools/install_assets_decor.py and
-- area_plan_decor.py read the switch line). Plain Lua, no engine calls at load (server/tests/assets_art_test.lua).
--
-- Pair switch (M.PAIR27, ON since 2026-10-15: pair 27 is live, windows-assets 51a26d26). A client on
-- pair 26 or older has no outfit 2234 and no items 33986..33994 (it would draw nothing, or stop on a look id past its
-- last outfit). On: the area planner merges server/tools/areaplan/decor_assets_art.json (the catacomb biome gets the
-- sarcophagi, crypt hatches and the portal ring) and the rows of client/tools/sprites/monster_looks/assets_art_picks.csv
-- are appended to picks.csv (server/tools/apply_monster_looks.py writes look 2234 into the Hollow Rider's
-- file). Off: the Hollow Rider keeps its stock look and nothing places the items.
--
-- What it holds (art: client/tools/sprites/gen_assets_art.py, from the owner's Drive folder "ots/assets",
-- 2026-10-15, the kit credited in docs/CREDITS.md):
--   * one monster look 2234 (5x5): the Hollow Rider, boss of the Hollow Crypt (server/tools/areaplan/plans/
--     hollow_crypt.json, levels 300-400);
--   * nine decoration items (server ids 36986..36994, data/lib/chaos_assets_decor.lua, installed by
--     server/tools/install_assets_decor.py).

local M = {}

M.PAIR27 = true

local ok, decor = pcall(dofile, "data/lib/chaos_assets_decor.lua")
M.decor = ok and decor or {first = 36986, last = 36994, items = {}}

-- monster name -> look once the switch is on (before: the stock look the file has now)
M.monsters = {
	["Hollow Rider"] = 2234 -- before 1074
}

-- the look a monster should carry now
function M.lookOf(name, current)
	if M.PAIR27 and M.monsters[name] then
		return M.monsters[name]
	end
	return current
end

return M

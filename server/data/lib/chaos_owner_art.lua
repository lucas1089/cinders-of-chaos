-- chaos_owner_art.lua: the owner's art of client pair 26 (things_custom26) on the server side, behind one switch.
-- Loaded with  ChaosOwnerArt = dofile("data/lib/chaos_owner_art.lua")  (exclusives_config.lua and shop_config.lua do so).
-- Plain Lua, no engine calls at load (server/tests/owner_art_test.lua reads it with plain Lua).
--
-- Pair switch (M.PAIR26, OFF): things_custom26 is a trial pair, not on windows-assets yet. A client on pair 25 or older
-- has no outfits 2213..2233 and no items 33940..33985 (it would draw nothing, or stop on a look id past its last
-- outfit). While off nothing in the game names them: no exclusive, no store offer, no wings line in wings.xml
-- (install_outfits.py), no decoration in the area planner's kits, and the monster files keep their looks (the picks
-- below go into client/tools/sprites/monster_looks/picks.csv only with the pair). Turn it on in the same change that
-- publishes the pair (client/MANIFEST.md "Owner art (pair 26)", server/README.md "Owner art").
--
-- What it holds (art: client/tools/sprites/gen_owner_art.py, from the owner's Drive folder "ots", 2026-10-15):
--   * twelve monster looks 2213..2224: own looks for the four deep dungeon bosses and eight monsters of the
--     1300-2000 hunts (M.monsters; written into the monster XML by server/tools/apply_monster_looks.py once the rows of
--     monster_looks/owner_art_picks.csv are appended to picks.csv);
--   * nine wings 2225..2233: six sold in the store's Wings category, three boss drops (visual exclusives);
--   * 46 decoration items (server ids 36940..36985, data/lib/chaos_owner_decor.lua, installed by
--     server/tools/install_owner_decor.py): 45 desert plants and a 3x3 waypoint seal, for the area planner
--     (server/tools/areaplan/decor_owner_art.json) and map makers.

local M = {}

M.PAIR26 = false

local ok, decor = pcall(dofile, "data/lib/chaos_owner_decor.lua")
M.decor = ok and decor or {first = 36940, last = 36985, plants = {}, waypoint = nil}

-- monster name -> look (the picks of client/tools/sprites/monster_looks/owner_art_picks.csv, families dungeonboss and
-- hunt; before: the looks the files have now)
M.monsters = {
	["Vaelith the Fallen Seraph"] = 2213, -- before 1148
	["Ossivane the Gravecage"] = 2214, -- before 863
	["Forgewarden Kharzun"] = 2215, -- before 1281
	["Azhkarrath the Chained Wyrm"] = 2216, -- before 1535
	["Gloamfang Ravager"] = 2217, -- before 1547
	["Cinderhorn Juggernaut"] = 2218, -- before 1546
	["Cinderskull Reaver"] = 2219, -- before 1543
	["Silicron"] = 2220, -- before 875
	["Vyrm"] = 2221, -- before 906
	["Winterstride"] = 2222, -- before 1494
	["Bloodantler Fiend"] = 2223, -- before 1369
	["Mirecoil Wyrm"] = 2224 -- before 1462
}

-- wings: wings.xml ids 21..29 (the store sells 1..15, the exclusives hold 16..20). PLACEHOLDER PRICES
-- (docs/OWNER_TODO.md): 250 a pair, like the store's other feathered wings.
M.storeWings = {
	{key = "wings_jadeleaf", id = 21, look = 2225, name = "Jadeleaf Pinions", cost = 250},
	{key = "wings_tidewing", id = 22, look = 2226, name = "Tidewing Plumes", cost = 250},
	{key = "wings_duskfeather", id = 23, look = 2227, name = "Duskfeather Wings", cost = 250},
	{key = "wings_emberplume", id = 24, look = 2228, name = "Emberplume Wings", cost = 250},
	{key = "wings_wildgrove", id = 25, look = 2229, name = "Wildgrove Wings", cost = 250},
	{key = "wings_bloodfeather", id = 26, look = 2230, name = "Bloodfeather Wings", cost = 250}
}

-- the visual exclusives (exclusives_config.lua format; install_outfits.py reads the wings lines of this file when the
-- switch is on), and the boss groups that roll them
M.exclusives = {
	{key = "wings_gloomgild", kind = "wings", id = 27, look = 2231, icon = 2192, source = "boss",
		name = "Gloomgild Wings", desc = "Violet scaled wings on gilded bone roots, a violet gem at each."},
	{key = "wings_sunforged", kind = "wings", id = 28, look = 2232, icon = 2353, source = "boss",
		name = "Sunforged Wings", desc = "Ember scaled wings on gilded bone roots, still warm from the pyre."},
	{key = "wings_starmoth", kind = "wings", id = 29, look = 2233, icon = 6500, source = "boss",
		name = "Starmoth Wings", desc = "Violet moth wings dusted with starlight."}
}
M.bossRewards = {nyxareth = "wings_gloomgild", cinderheart = "wings_sunforged", ascended = "wings_starmoth"}

-- the store's Wings offers of the sold wings (shop_config.lua appends them to its Wings category); empty while off
function M.storeOffers()
	local out = {}
	if not M.PAIR26 then
		return out
	end
	for _, w in ipairs(M.storeWings) do
		out[#out + 1] = {kind = "wings", id = w.id, cost = w.cost}
	end
	return out
end

-- exclusives_config.lua calls this on its table: the wings and their boss groups, only when on
function M.addExclusives(cfg)
	if not M.PAIR26 then
		return cfg
	end
	for _, e in ipairs(M.exclusives) do
		cfg.exclusives[#cfg.exclusives + 1] = e
	end
	for _, b in ipairs(cfg.bosses or {}) do
		local key = M.bossRewards[b.key]
		if key then
			b.rewards[#b.rewards + 1] = key
		end
	end
	return cfg
end

-- a decoration item by key ("cactus_01".."cactus_45", "waypoint_seal"); `fallback` while off or not installed
function M.decorId(key, fallback)
	if not M.PAIR26 then
		return fallback
	end
	if key == "waypoint_seal" then
		return M.decor.waypoint or fallback
	end
	for _, p in ipairs(M.decor.plants or {}) do
		if p.key == key then
			return p.id
		end
	end
	return fallback
end

return M

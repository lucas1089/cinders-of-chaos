-- chaos_pack37_looks.lua: the owner's moon outfits and novelty costumes of client pair 37 on the server side, behind
-- one switch. Loaded with  ChaosPack37 = dofile("data/lib/chaos_pack37_looks.lua")  (shop_config.lua does so;
-- server/tools/install_outfits.py reads the switch line and the M.outfits lines). Plain Lua, no engine calls at load
-- (server/tests/pack37_looks_test.lua).
--
-- Pair switch (M.PAIR37, ON since pair 37 is on windows-assets, 2026-10-22). A client on pair 36 or older has no outfits
-- 2668+ (it would draw nothing, or stop on a look id past its last outfit). On: install_outfits.py writes their
-- outfits.xml lines (locked, unlocked="no"), the store sells the four moon outfits in Outfits and the six costumes in
-- a new Costumes category after it. Off: none of that (client/MANIFEST.md "Owner outfits (pair 37)", server/README.md
-- "Owner outfits (pair 37)").
--
-- Art: client/tools/sprites/gen_pack37_looks.py (the owner's .obd files on Drive, source pack unnamed). Its
-- `build --check` compares M.looks with its LOOKS table. Prices are PLACEHOLDERS (docs/OWNER_TODO.md): 750 a full moon
-- outfit like the store's other full outfits, 300 a costume (the store's lowest outfit price).

local M = {}

M.PAIR37 = true

-- every client look of the pair, in id order (gen_pack37_looks.py LOOKS)
M.looks = {
	{key = "starweaver_m", look = 2668, name = "Starweaver"},
	{key = "starweaver_f", look = 2669, name = "Starweaver"},
	{key = "crescent_oracle_m", look = 2670, name = "Crescent Oracle"},
	{key = "crescent_oracle_f", look = 2671, name = "Crescent Oracle"},
	{key = "moonblade_mystic_m", look = 2672, name = "Moonblade Mystic"},
	{key = "moonblade_mystic_f", look = 2673, name = "Moonblade Mystic"},
	{key = "moonflame_mystic_m", look = 2674, name = "Moonflame Mystic"},
	{key = "moonflame_mystic_f", look = 2675, name = "Moonflame Mystic"},
	{key = "plush_bear", look = 2676, name = "Plush Bear"},
	{key = "snow_plush_bear", look = 2677, name = "Snow Plush Bear"},
	{key = "frost_crawling_hand", look = 2678, name = "Frost Crawling Hand"},
	{key = "grave_crawling_hand", look = 2679, name = "Grave Crawling Hand"},
	{key = "rose_crawling_hand", look = 2680, name = "Rose Crawling Hand"},
	{key = "fry_box", look = 2681, name = "Fry Box Costume"}
}

-- the outfits as players get them (one outfits.xml line per sex; install_outfits.py reads these lines as written:
-- keep one entry per line). category: the store category that sells it.
M.outfits = {
	{key = "starweaver", name = "Starweaver", male = 2668, female = 2669, cost = 750, category = "Outfits", desc = "A white-robed seer with a violet crescent. Addons: a crescent charm and a trailing star chart."},
	{key = "crescent_oracle", name = "Crescent Oracle", male = 2670, female = 2671, cost = 750, category = "Outfits", desc = "A white-robed seer with a violet crescent. Addons: a crescent charm and a pair of glowing moons."},
	{key = "moonblade_mystic", name = "Moonblade Mystic", male = 2672, female = 2673, cost = 750, category = "Outfits", desc = "A white-robed seer with a violet crescent. Addons: a crescent charm and a moonlit blade."},
	{key = "moonflame_mystic", name = "Moonflame Mystic", male = 2674, female = 2675, cost = 750, category = "Outfits", desc = "A white-robed seer with a violet crescent. Addons: a crescent charm and violet moonflames."},
	{key = "plush_bear", name = "Plush Bear", male = 2676, female = 2676, cost = 300, category = "Costumes", desc = "Become a small violet plush bear. No colours, no addons."},
	{key = "snow_plush_bear", name = "Snow Plush Bear", male = 2677, female = 2677, cost = 300, category = "Costumes", desc = "Become a small white plush bear. No colours, no addons."},
	{key = "frost_crawling_hand", name = "Frost Crawling Hand", male = 2678, female = 2678, cost = 300, category = "Costumes", desc = "Scuttle about as an icy blue severed hand with an eye in its palm."},
	{key = "grave_crawling_hand", name = "Grave Crawling Hand", male = 2679, female = 2679, cost = 300, category = "Costumes", desc = "Scuttle about as a green grave hand with an eye in its palm."},
	{key = "rose_crawling_hand", name = "Rose Crawling Hand", male = 2680, female = 2680, cost = 300, category = "Costumes", desc = "Scuttle about as a pink severed hand with an eye in its palm."},
	{key = "fry_box", name = "Fry Box Costume", male = 2681, female = 2681, cost = 300, category = "Costumes", desc = "A walking box of fries. It does not animate: it glides."}
}

M.COSTUMES = "Costumes"

-- the store offers of one category ("Outfits" or "Costumes"); empty while the switch is off
function M.storeOffers(category)
	local out = {}
	if not M.PAIR37 then
		return out
	end
	for _, o in ipairs(M.outfits) do
		if o.category == category then
			out[#out + 1] = {kind = "outfit", key = "outfit:" .. o.male, looktype = o.male, lookfemale = o.female,
				name = o.name, cost = o.cost, description = o.desc ..
					(o.male ~= o.female and " Both addons, male and female look." or " One look for both sexes.")}
		end
	end
	return out
end

-- shop_config.lua: the moon outfits go at the end of its Outfits category, the costumes into a new subcategory of
-- `parent` (the store tree's "Cosmetics") right after Outfits (ChaosShopCore.addSubcategory when loaded, the same
-- placement by hand otherwise). None while off.
function M.addStore(cfg, parent)
	if not M.PAIR37 then
		return cfg
	end
	parent = parent or "Cosmetics"
	for _, c in ipairs(cfg.categories or {}) do
		if c.name == "Outfits" then
			for _, o in ipairs(M.storeOffers("Outfits")) do
				c.offers[#c.offers + 1] = o
			end
		end
	end
	local cat = {name = M.COSTUMES, icon = {outfit = {type = 2676, rotating = true}}, offers = M.storeOffers(M.COSTUMES)}
	if ChaosShopCore and ChaosShopCore.addSubcategory then
		ChaosShopCore.addSubcategory(cfg, parent, cat, "Outfits")
	else
		cat.parent = parent
		local at = #cfg.categories
		for i, x in ipairs(cfg.categories) do
			if x.name == "Outfits" then
				at = i
			end
		end
		table.insert(cfg.categories, at + 1, cat)
	end
	return cfg
end

return M

-- chaos_fun_costumes.lua: the twelve fun costumes of client pair 72, the new Dusk Moth look and the round Rune Seal ring, on the
-- server side, behind one gate (O566). Loaded with  ChaosFunCostumes = dofile("data/lib/chaos_fun_costumes.lua")  (shop_config.lua,
-- pets_config.lua and chaos_theme_art.lua do so; server/tools/install_outfits.py, install_fun_looks.py and install_auras.py read the
-- M.outfits lines and the two ids). Plain Lua, no engine calls at load (server/tests/fun_costumes_test.lua).
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 72 or more, read from the file at load (M.pairOn). A client on
-- pair 71 or older has no outfits 3511+ (it would draw nothing), so below 72 nothing here changes anything: no outfits.xml lines, no
-- store offers, the Dusk Moth keeps the stock butterfly look 213, the Rune Seal keeps its look 2186. The install steps (outfits,
-- funlooks, auras) wait for the same record (client_pair.py PAIR_FUN). The owner raises it when pair 72 ships.
--
-- Art: client/tools/sprites/gen_fun_costumes.py (PixelLab, ours). Its `check` compares M.looks with its table. Price: 300 a costume,
-- the store's lowest outfit price and what the six pair 37 costumes cost (store_model.lua prices no costume separately).

local M = {}

M.PAIR = 72

-- the pair recorded in a config.lua text, or nil (the same reading as server/tools/client_pair.py parse)
function M.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

-- the recorded pair of the server's config.lua (nil when it cannot be read: no engine, a test, a missing key)
function M.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return M.parsePair(text)
end

-- the gate, read once at load; tests set it by hand
M.PAIR72 = (M.recordedPair() or 0) >= M.PAIR

-- every client look of the pair, in id order (gen_fun_costumes.py table)
M.looks = {
	{key = "energy_can", look = 3511, name = "Volt Fizz Can"},
	{key = "smoke_pack", look = 3512, name = "Puff Pack"},
	{key = "toaster", look = 3513, name = "Wandering Toaster"},
	{key = "rubber_duck", look = 3514, name = "Rubber Duck"},
	{key = "eye_box", look = 3515, name = "Peeking Box"},
	{key = "pizza", look = 3516, name = "Pizza Slice"},
	{key = "road_cone", look = 3517, name = "Road Cone"},
	{key = "gnome", look = 3518, name = "Garden Gnome"},
	{key = "snowman", look = 3519, name = "Living Snowman"},
	{key = "mushroom", look = 3520, name = "Mushroom Folk"},
	{key = "bone_jester", look = 3521, name = "Bone Jester"},
	{key = "chicken", look = 3522, name = "Chicken Suit"},
	{key = "dusk_moth", look = 3523, name = "Dusk Moth"},
	{key = "rune_seal", look = 3524, name = "Rune Seal"}
}

-- the new look of the Dusk Moth pet (was the stock look 213) and of the Rune Seal aura (was 2186)
M.moth = {old = 213, look = 3523}
M.seal = {old = 2186, look = 3524}

-- the costumes as players get them (one outfits.xml line per sex; install_outfits.py reads these lines as written: keep one entry per
-- line). One look for both sexes, locked, sold in Cosmetics > Costumes.
M.outfits = {
	{key = "energy_can", name = "Volt Fizz Can", male = 3511, female = 3511, cost = 300, category = "Costumes", desc = "Hop about as a fizzing blue energy drink can with a yellow lightning bolt"},
	{key = "smoke_pack", name = "Puff Pack", male = 3512, female = 3512, cost = 300, category = "Costumes", desc = "Hop about as a plain red and white pack of smokes with its lid open"},
	{key = "toaster", name = "Wandering Toaster", male = 3513, female = 3513, cost = 300, category = "Costumes", desc = "Waddle about as a chrome toaster with two slices of toast popping up"},
	{key = "rubber_duck", name = "Rubber Duck", male = 3514, female = 3514, cost = 300, category = "Costumes", desc = "Waddle about as a squeaky yellow rubber duck"},
	{key = "eye_box", name = "Peeking Box", male = 3515, female = 3515, cost = 300, category = "Costumes", desc = "Scuttle about as a cardboard box with two eyes peeking out"},
	{key = "pizza", name = "Pizza Slice", male = 3516, female = 3516, cost = 300, category = "Costumes", desc = "Bounce about as a slice of pepperoni pizza with dripping cheese"},
	{key = "road_cone", name = "Road Cone", male = 3517, female = 3517, cost = 300, category = "Costumes", desc = "Hop about as an orange road cone with two white stripes"},
	{key = "gnome", name = "Garden Gnome", male = 3518, female = 3518, cost = 300, category = "Costumes", desc = "Stroll about as a garden gnome with a tall red hat and a long white beard"},
	{key = "snowman", name = "Living Snowman", male = 3519, female = 3519, cost = 300, category = "Costumes", desc = "Stroll about as a snowman that came to life, top hat, carrot nose and scarf"},
	{key = "mushroom", name = "Mushroom Folk", male = 3520, female = 3520, cost = 300, category = "Costumes", desc = "Stroll about as a little mushroom folk under a big spotted red cap"},
	{key = "bone_jester", name = "Bone Jester", male = 3521, female = 3521, cost = 300, category = "Costumes", desc = "Stroll about as a skeleton jester with a belled two-pointed hat"},
	{key = "chicken", name = "Chicken Suit", male = 3522, female = 3522, cost = 300, category = "Costumes", desc = "Strut about in a white chicken suit with a red comb and a feathered tail"}
}

M.COSTUMES = "Costumes"

-- the store offers of one category ("Costumes"); empty while the gate is off
function M.storeOffers(category)
	local out = {}
	if not M.PAIR72 then
		return out
	end
	for _, o in ipairs(M.outfits) do
		if o.category == category then
			out[#out + 1] = {kind = "outfit", key = "outfit:" .. o.male, looktype = o.male, lookfemale = o.female,
				name = o.name, cost = o.cost, description = o.desc .. ". One look for both sexes."}
		end
	end
	return out
end

-- shop_config.lua: the costumes go to the end of the "Costumes" subcategory of Cosmetics that chaos_pack37_looks.lua makes. None
-- while the gate is off.
function M.addStore(cfg)
	if not M.PAIR72 then
		return cfg
	end
	for _, c in ipairs(cfg.categories or {}) do
		if c.name == M.COSTUMES then
			for _, o in ipairs(M.storeOffers(M.COSTUMES)) do
				c.offers[#c.offers + 1] = o
			end
		end
	end
	return cfg
end

-- the look the Dusk Moth pet and its store offer show: the new moth once the gate is on, else the stock look
function M.mothLook()
	return M.PAIR72 and M.moth.look or M.moth.old
end

-- the client look of the Rune Seal aura: the round ring once the gate is on, else the old flat ring
function M.sealLook()
	return M.PAIR72 and M.seal.look or M.seal.old
end

return M

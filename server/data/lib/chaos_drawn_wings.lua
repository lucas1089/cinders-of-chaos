-- chaos_drawn_wings.lua: the six code-drawn wings of client pair 78 on the server side, behind one gate (O581 phase 2).
-- Loaded with  ChaosDrawnWings = dofile("data/lib/chaos_drawn_wings.lua")  (shop_config.lua does so; server/tools/install_outfits.py reads
-- the wings of chaos_drawn_wings_ids.lua behind the same gate). Plain Lua, no engine calls at load (server/tests/drawn_wings_test.lua).
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 78 or more, read from the file at load (M.PAIR78). A client on pair 77 or
-- older has no outfits 3555-3560 (it would draw nothing, or stop on a look id past its last outfit), so below 78 nothing here changes
-- anything: no wings.xml lines, no store offers. The install step (outfits, install_outfits.py) waits for the same record (client_pair.py
-- PAIR_DRAWN_WINGS); PAIR_ASSETS stays 77 until pair 78 is on windows-assets. The owner raises the record when pair 78 ships.
--
-- What it holds (art: client/tools/sprites/gen_drawn_wings.py, ours, no art file): Ember Pinions, Ossuary Wings, Void Orbit, Bladefan,
-- Rimeshard and Grave Lanterns as wings.xml ids 122-127 on the client looks 3555-3560. The ids, names and elements are generated from
-- client/tools/sprites/drawn_wings/new_looks.csv (gen_drawn_wings_new.py new-table) into data/lib/chaos_drawn_wings_ids.lua; this file adds the
-- gate and the price. Bought in the store, Cosmetics > Wings (the end of the category); none is a boss drop or a reward.
--
-- Price: 300 coins a pair, a placeholder for the owner to confirm (docs/PRICES.md). The pair 33 wings cost 250 at 3 x 3 and 300 above it; these
-- are 3 x 3 but drawn in two layers round the body (part of them in front of the character), so they take the upper price. Inside the 120-350
-- of the wings and the cosmetics band of store_balance_config.lua.

local M = {}

M.PAIR = 78
M.COST = 300

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
M.PAIR78 = (M.recordedPair() or 0) >= M.PAIR

local ok, data = pcall(dofile, "data/lib/chaos_drawn_wings_ids.lua")
M.wings = ok and type(data) == "table" and type(data.wings) == "table" and data.wings or {}

local ELEMENT = {fire = "Fire", water = "Water", wind = "Wind", earth = "Earth", energy = "Storm", light = "Light",
	dark = "Dark", neutral = "Plain"}

-- the store text of one wing: the sentences of the pair 33 wings, so the pt-BR texts exist
function M.describe(p)
	return (ELEMENT[p.element] or "Plain") .. " wings, animated. Wear them with any aura, head accessory or cape."
end

-- a wing by key or by wings.xml id
function M.piece(keyOrId)
	for _, p in ipairs(M.wings) do
		if p.key == keyOrId or p.id == keyOrId then
			return p
		end
	end
	return nil
end

-- the store offers (the key is the default "wings:ID"); empty while the gate is off
function M.storeOffers()
	local out = {}
	if not M.PAIR78 then
		return out
	end
	for _, p in ipairs(M.wings) do
		out[#out + 1] = {kind = "wings", id = p.id, cost = M.COST, description = M.describe(p)}
	end
	return out
end

-- shop_config.lua: the offers go at the end of the Wings category. None while the gate is off.
function M.addStore(cfg)
	if not M.PAIR78 then
		return cfg
	end
	for _, c in ipairs(cfg.categories or {}) do
		if c.name == "Wings" then
			for _, o in ipairs(M.storeOffers()) do
				c.offers[#c.offers + 1] = o
			end
		end
	end
	return cfg
end

return M

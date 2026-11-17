-- chaos_source_wings.lua: the fifteen source wings of client pair 74 (O627) on the server side, behind one gate. Loaded with
--   ChaosSourceWings = dofile("data/lib/chaos_source_wings.lua")  (shop_config.lua does so; server/tools/install_outfits.py reads the
-- M.wings lines and the pair). Plain Lua, no engine calls at load (server/tests/source_wings_test.lua).
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 74 or more, read from the file at load (M.recordedPair), as for the fun
-- costumes of pair 72. A client on pair 73 or older has no outfits 3530+ (it would draw nothing), so below 74 nothing here changes
-- anything: no wings.xml lines, no store offers. `install_all.py --only outfits` waits for the same record (client_pair.py
-- PAIR_SOURCE_WINGS); the owner raises it when pair 74 ships.
--
-- How a player gets them: the store, category Wings, the way the pair 33 wings are sold (shop_config.lua; Cinder Coins, 250 for a
-- 3x3 canvas, 300 for a larger one, the prices of ChaosPack33). Not a boss drop and not an achievement: the 15 are picks of the
-- owner, not a reward set. wings.xml ids 122-136 follow the 121 of pair 33.
--
-- Art: client/tools/sprites/gen_source_wings.py (art_import/source_wings.csv; its `check` compares M.wings with the table). Names are
-- English like every wings name (the store shows the wings.xml name; the element sentences have pt-BR texts in i18n_strings.lua).

local M = {}

M.PAIR = 74

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
M.PAIR74 = (M.recordedPair() or 0) >= M.PAIR

-- every wings piece, in outfit order (one entry per line: install_outfits.py reads these lines as written). id = wings.xml id, look =
-- client outfit; element picks the store sentence ("Dark wings, animated.")
M.wings = {
	{key = "wings_voidbloom", id = 122, look = 3530, name = "Voidbloom Wings", element = "dark", cost = 250},
	{key = "wings_bloodmoon", id = 123, look = 3531, name = "Bloodmoon Wings", element = "dark", cost = 250},
	{key = "wings_rustfang", id = 124, look = 3532, name = "Rustfang Wings", element = "fire", cost = 250},
	{key = "wings_nightglass", id = 125, look = 3533, name = "Nightglass Wings", element = "dark", cost = 250},
	{key = "wings_cinderveil", id = 126, look = 3534, name = "Cinderveil Wings", element = "fire", cost = 250},
	{key = "wings_ashenrelic", id = 127, look = 3535, name = "Ashen Relic Wings", element = "neutral", cost = 250},
	{key = "wings_gildenmourn", id = 128, look = 3536, name = "Gildenmourn Wings", element = "light", cost = 250},
	{key = "wings_sootweave", id = 129, look = 3537, name = "Sootweave Wings", element = "neutral", cost = 250},
	{key = "wings_mirewood", id = 130, look = 3538, name = "Mirewood Wings", element = "earth", cost = 250},
	{key = "wings_gravemist", id = 131, look = 3539, name = "Gravemist Wings", element = "dark", cost = 250},
	{key = "wings_drownlight", id = 132, look = 3540, name = "Drownlight Wings", element = "water", cost = 250},
	{key = "wings_redthorn", id = 133, look = 3541, name = "Redthorn Wings", element = "dark", cost = 250},
	{key = "wings_wraithspan", id = 134, look = 3542, name = "Wraithspan Wings", element = "water", cost = 300},
	{key = "wings_hollowhalo", id = 135, look = 3543, name = "Hollow Halo Wings", element = "dark", cost = 300},
	{key = "wings_bloodring", id = 136, look = 3544, name = "Bloodring Wings", element = "dark", cost = 250}
}

local ELEMENT = {fire = "Fire", water = "Water", wind = "Wind", earth = "Earth", energy = "Storm", light = "Light",
	dark = "Dark", neutral = "Plain"}

M.CATEGORY = "Wings"

local function describe(p)
	return (ELEMENT[p.element] or "Plain") .. " wings, animated. Wear them with any aura, head accessory or cape."
end

-- the store offers (kind "wings"); empty while the gate is off
function M.storeOffers()
	local out = {}
	if not M.PAIR74 then
		return out
	end
	for _, p in ipairs(M.wings) do
		out[#out + 1] = {kind = "wings", id = p.id, cost = p.cost, description = describe(p)}
	end
	return out
end

-- shop_config.lua: the offers go at the end of its Wings category, after the pair 33 wings. None while the gate is off.
function M.addStore(cfg)
	if not M.PAIR74 then
		return cfg
	end
	for _, c in ipairs(cfg.categories or {}) do
		if c.name == M.CATEGORY then
			for _, o in ipairs(M.storeOffers()) do
				c.offers[#c.offers + 1] = o
			end
		end
	end
	return cfg
end

return M

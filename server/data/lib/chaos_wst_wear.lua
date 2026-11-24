-- chaos_wst_wear.lua: the purchased wings, head pieces and capes of client pair 83 on the server side, behind one gate (O747).
-- Loaded with  ChaosWstWear = dofile("data/lib/chaos_wst_wear.lua")  (cosmetics_config.lua, shop_config.lua and chaos_pack33.lua
-- do so; server/tools/install_outfits.py reads the wings of chaos_wst_wear_ids.lua behind the same gate). Plain Lua, no engine
-- calls at load (server/tests/pack_wear_test.lua).
--
-- Owner 2026-11-24: "Pode importar, com levitação e camada nova. Remova as nossas artes já publicadas que estão com qualidade
-- inferior a essas." Art: client/tools/sprites/gen_wst_wear.py (three purchased sets, no picture in the repository).
--
-- Gate: config.lua `chaosClientPair` is 83 or more, read from the file at load (M.on; client_pair.py PAIR_WST_WEAR). A client on
-- pair 82 or older has no outfit 3589 and up, so below 83 nothing here changes anything: no cosmetics of kind head / cape, no
-- store offer, no wings.xml line, no hidden aura.
--
-- What it holds (ids, names, elements, prices generated into data/lib/chaos_wst_wear_ids.lua):
--   * wings: 73 of our code-drawn wings get the pack art in place on the client (same look, same wings.xml id: owners keep
--     them, the server changes nothing); Plasma Fly Wings is new, wings.xml id 128 on look 3589, sold at the end of Wings.
--   * heads (66) and capes (78): cosmetics of the kinds `head` and `cape` (cosmetics_config.lua; chosen per character in
--     Character > Cosmetics, drawn by every viewer's client round the body: client base patch 0210). Unlocks are account wide.
--     Ids: heads 1000 + n, capes 1100 + n, n the row of the generated list from 1 (the list is in key order and only grows at
--     its end: a new piece takes the next id; never reuse one).
--   * twins: 64 heads and 73 capes are the same piece as an aura of pair 33 (chaos_pack33.lua, auras.xml id `aura`). From pair
--     83 the aura is no longer sold (M.hidesAura) and an account whose character has the aura gets the new piece free
--     (cosmetics.lua grants it at login and when the window opens). The aura stays with whoever owns it.
-- Prices: the twin's price (heads 150 / 200, capes 200 / 250), else heads 150 and capes 200; the new wing 300 like the drawn
-- wings of pair 78. Placeholders for the owner to confirm (docs/PRICES.md).

local M = {}

M.PAIR = 83
M.WING_COST = 300
M.HEAD_BASE = 1000
M.CAPE_BASE = 1100

-- the pair recorded in a config.lua text, or nil (the same reading as server/tools/client_pair.py parse)
function M.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

function M.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return M.parsePair(text)
end

-- the gate, read once at load; a test sets ChaosWstWearOn before it loads this file (or M.on by hand)
if ChaosWstWearOn ~= nil then
	M.on = ChaosWstWearOn == true
else
	M.on = (M.recordedPair() or 0) >= M.PAIR
end

local ok, data = pcall(dofile, "data/lib/chaos_wst_wear_ids.lua")
data = ok and type(data) == "table" and data or {}
M.wings = type(data.wings) == "table" and data.wings or {}
M.heads = type(data.heads) == "table" and data.heads or {}
M.capes = type(data.capes) == "table" and data.capes or {}

local ELEMENT = {fire = "Fire", water = "Water", wind = "Wind", earth = "Earth", energy = "Storm", light = "Light",
	dark = "Dark", neutral = "Plain"}
-- the server item drawn for a piece in the store list and the window (a picture only), by element
local ICON = {fire = 2187, water = 2146, wind = 2150, earth = 18415, energy = 7759, light = 2145, dark = 2153, neutral = 2154}

local function describe(kind, p)
	local el = ELEMENT[p.element] or "Plain"
	if kind == "head" then
		return el .. " head accessory, animated. It has its own layer: wear it with any aura, wings and cape."
	end
	return el .. " cape, animated. It has its own layer: wear it with any aura, wings and head accessory."
end
M.describe = describe

-- the cosmetics of kinds head and cape (cosmetics_config.lua appends them; `pair = 83` keeps them out below the gate)
function M.cosmetics()
	local out = {}
	for i, p in ipairs(M.heads) do
		out[#out + 1] = {id = M.HEAD_BASE + i, key = "head_" .. p.key, kind = "head", icon = ICON[p.element] or 2154,
			source = "store", price = p.cost, pair = M.PAIR, look = p.look, aura = p.aura, name = p.name,
			desc = describe("head", p)}
	end
	for i, p in ipairs(M.capes) do
		out[#out + 1] = {id = M.CAPE_BASE + i, key = "cape_" .. p.key, kind = "cape", icon = ICON[p.element] or 2154,
			source = "store", price = p.cost, pair = M.PAIR, look = p.look, aura = p.aura, name = p.name,
			desc = describe("cape", p)}
	end
	return out
end

-- auras.xml id -> cosmetic key of its twin (both lists)
function M.twins()
	local out = {}
	for _, c in ipairs(M.cosmetics()) do
		if c.aura then
			out[c.aura] = c.key
		end
	end
	return out
end

-- true when the pair 33 aura `id` has a twin here and the gate is on: the store no longer sells it
function M.hidesAura(id)
	if not M.on then
		return false
	end
	return M.twins()[tonumber(id) or -1] ~= nil
end

-- the twin pieces an account gets for the auras its character owns: hasAura(id) -> true / false; [] while off
function M.twinGrants(hasAura)
	local out = {}
	if not M.on or type(hasAura) ~= "function" then
		return out
	end
	local t = M.twins()
	local ids = {}
	for id in pairs(t) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if hasAura(id) then
			out[#out + 1] = t[id]
		end
	end
	return out
end

-- the store offer of the new wing (the key is the default "wings:ID"); empty while the gate is off
function M.storeOffers()
	local out = {}
	if not M.on then
		return out
	end
	for _, p in ipairs(M.wings) do
		out[#out + 1] = {kind = "wings", id = p.id, cost = p.cost or M.WING_COST,
			description = (ELEMENT[p.element] or "Plain") .. " wings, animated. They lift you off the ground. Wear them with any aura, head accessory or cape."}
	end
	return out
end

-- shop_config.lua: the new wing at the end of the Wings category. None while the gate is off.
function M.addStore(cfg)
	if not M.on then
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

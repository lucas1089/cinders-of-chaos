-- wardrobe.lua: the full appearance catalogue for the Customise Character window (client game_unlocks, base patch
-- 0058). Rules in wardrobe_core.lua (server/tests/wardrobe_test.lua); server/README.md "Wardrobe catalogue".
-- On the cosmetics opcode (ChaosOpcodes.cosmetics, 225, JSON {action, data}; no new opcode):
--   client -> server  wardrobe            (sent by game_unlocks when the game starts and when the outfit window opens)
--   server -> client  wardrobe {sex, hash, outfit, mount, wings, aura, shader}   (ChaosWardrobeCore.list; chunked)
-- cosmetics.lua's handler calls ChaosWardrobe.send for the action. The XML catalogues and the unlock sources are read
-- once per sex and kept; only the owned flags are made per request. Nothing here grants or wears anything: the engine
-- refuses an outfit change with a part the character does not own (Game::playerChangeOutfit).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosWardrobeCore then
	dofile("data/scripts/chaos/wardrobe_core.lua")
end

ChaosWardrobe = ChaosWardrobe or {}
local M = ChaosWardrobe
local W = ChaosWardrobeCore
local OPCODE = ChaosOpcodes.cosmetics

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	return s
end

local cache = {} -- [sex] = {cat, src}

local function exclusiveHow()
	local K, cfg = ChaosExclusivesCore, ChaosExclusivesConfig
	if not (K and cfg and K.how) then
		return {}, nil
	end
	local data = ChaosAchievements and ChaosAchievements.data or nil
	return cfg.exclusives or {}, function(e)
		local ok, text = pcall(K.how, cfg, e, data, false)
		return ok and text or nil
	end
end

local function classLooks()
	local L = ChaosClassLooks
	if not L or type(L.looks) ~= "table" then
		return {}
	end
	local out = {}
	for voc, l in pairs(L.looks) do
		out[#out + 1] = l
		local p = L.PAIR19_LOOKS and L.pair19Looks and L.pair19Looks[voc]
		if p then
			out[#out + 1] = {name = l.name, male = p.male, female = p.female}
		end
	end
	return out
end

function M.catalogueOf(sex)
	if cache[sex] then
		return cache[sex]
	end
	local xml = {}
	for _, f in ipairs({"outfits", "mounts", "wings", "auras", "shaders"}) do
		xml[f] = readFile("data/XML/" .. f .. ".xml")
	end
	local exclusives, how = exclusiveHow()
	local entry = {
		cat = W.catalogue(xml, sex),
		src = W.sources({exclusives = exclusives, how = how, classLooks = classLooks(),
			shopOffers = ChaosShopConfig})
	}
	cache[sex] = entry
	return entry
end

function M.list(player)
	local sex = player:getSex() == PLAYERSEX_FEMALE and 0 or 1
	local c = M.catalogueOf(sex)
	local premium = player.isPremium and player:isPremium() or false
	local list = W.list(c.cat, c.src, {
		access = player:getGroup() and player:getGroup():getAccess() or false,
		premium = premium,
		hasOutfit = function(look, addons)
			return player:hasOutfit(look, addons) == true
		end,
		hasMount = function(id)
			return player:hasMount(id) == true
		end,
		value = function(key)
			return player:getStorageValue(key)
		end
	})
	list.sex = sex
	return list
end

function M.send(player)
	local list = M.list(player)
	local body = json.encode(list)
	list.hash = W.hash(body)
	return Chaos.sendChunked(player, OPCODE, json.encode({action = "wardrobe", data = list}))
end

-- a reload of the XML files (/reload) is picked up at the next server start; staff can drop the cache here
function M.clearCache()
	cache = {}
end

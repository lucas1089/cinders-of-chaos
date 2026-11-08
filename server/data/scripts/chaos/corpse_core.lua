-- Loot bag instead of monster bodies, the pure part (ChaosCorpse; config corpse_config.lua, engine glue corpse_bag.lua,
-- tests/corpse_bag_test.lua). server/README.md "Loot bag instead of corpses". Lua 5.1 / LuaJIT compatible.
--   ChaosCorpse.validate(cfg)            list of problems (empty = fine)
--   ChaosCorpse.engineArgs(cfg, itemOk)  bagId, keepIds for Game.setMonsterLootBag: bagId 0 when off or invalid
--   ChaosCorpse.corpseFor(cfg, kind, id) the corpse item a creature of kind ("monster" | "player") leaves when its own
--                                        corpse is id; the same rule as the engine (src-patch 0089, chaoslootbag.h)
--   ChaosCorpse.isBag(cfg, id)           the id is the bag
--   ChaosCorpse.itemXml(cfg, text)       items.xml text with the bag's entry set (tools/patch_monster_corpses.py mirrors it)

ChaosCorpse = ChaosCorpse or {}
local C = ChaosCorpse

local function isId(v)
	return type(v) == "number" and v >= 100 and v <= 65535 and v == math.floor(v)
end

function C.validate(cfg)
	local out = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	if not isId(cfg.bagId) then
		out[#out + 1] = "bagId must be an item id (100-65535)"
	end
	if type(cfg.seconds) ~= "number" or cfg.seconds < 30 or cfg.seconds > 300 then
		out[#out + 1] = "seconds must be 30-300 (the owner's rule: a corpse stays at most 5 minutes)"
	end
	if type(cfg.slots) ~= "number" or cfg.slots < 1 or cfg.slots > 255 then
		out[#out + 1] = "slots must be 1-255"
	end
	if type(cfg.name) ~= "string" or cfg.name == "" then
		out[#out + 1] = "name must be a text"
	end
	for i, id in ipairs(cfg.keepIds or {}) do
		if not isId(id) then
			out[#out + 1] = "keepIds[" .. i .. "] is no item id"
		elseif id == cfg.bagId then
			out[#out + 1] = "keepIds[" .. i .. "] is the bag itself"
		end
	end
	return out
end

-- itemOk: nil (not asked) or the answer of the engine about the bag item: a container that counts as a corpse
function C.engineArgs(cfg, itemOk)
	if type(cfg) ~= "table" or not cfg.enabled or #C.validate(cfg) > 0 or itemOk == false then
		return 0, {}
	end
	local keep = {}
	for _, id in ipairs(cfg.keepIds or {}) do
		keep[#keep + 1] = id
	end
	table.sort(keep)
	return cfg.bagId, keep
end

function C.isBag(cfg, id)
	return type(cfg) == "table" and cfg.bagId == id
end

-- what the engine does (chaoslootbag.h corpseOf, called from Monster::getLookCorpse only). A player never gets the bag:
-- Player::getLookCorpse is not touched by the patch, and this function says the same.
function C.corpseFor(cfg, kind, id)
	if kind ~= "monster" then
		return id
	end
	local bag, keep = C.engineArgs(cfg)
	if bag == 0 or not id or id == 0 or id == bag then
		return id
	end
	for _, k in ipairs(keep) do
		if k == id then
			return id
		end
	end
	return bag
end

return C

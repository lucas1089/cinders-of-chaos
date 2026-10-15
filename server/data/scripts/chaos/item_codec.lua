-- The item codec: a whole item (every attribute) to a database row and back. Shared by the market escrow (market.lua)
-- and the stash (stash.lua). The text forms are in item_codec_core.lua. The charms grid (charms.lua) keeps its own
-- fallback form (a JSON list of the charm's keys) for its rows of before.
--
--   ChaosItemCodec.hasBlob()                       true with engine patch 0017 (item:serializeAttributes /
--                                                  unserializeAttributes)
--   ChaosItemCodec.encode(item[, useBlob])         -> codec, data: "blob" (the engine's binary form, hex) when
--                                                  useBlob (default hasBlob()), else "attrs" (a key list of the standard
--                                                  attributes and every custom key the Chaos scripts set)
--   ChaosItemCodec.decode(itemId, count, codec, data[, useBlob])
--                                                  -> a new item (not in the world), or nil, why. "plain" makes the bare
--                                                  item. The per-item id (chaos_iid) is dropped: the engine gives the copy
--                                                  a new one when it is first sent, so links of the old copy never point
--                                                  at it.
--   ChaosItemCodec.isPlain(item[, useBlob])        true when the item is nothing but its id and count (a plain stack:
--                                                  no action / unique id, text, name, charges, custom attribute, ...)
--   ChaosItemCodec.customKeys()                    the custom keys the key-list codec copies
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosItemCodecCore then
	dofile("data/scripts/chaos/item_codec_core.lua")
end

ChaosItemCodec = ChaosItemCodec or {}
local IC = ChaosItemCodec
local CC = ChaosItemCodecCore

function IC.hasBlob()
	return Item ~= nil and Item.serializeAttributes ~= nil and Item.unserializeAttributes ~= nil
end

-- the key-list codec (without engine patch 0017): the standard attributes and every custom key the Chaos scripts set
local STD = {"ITEM_ATTRIBUTE_DESCRIPTION", "ITEM_ATTRIBUTE_TEXT", "ITEM_ATTRIBUTE_WRITER", "ITEM_ATTRIBUTE_DATE",
	"ITEM_ATTRIBUTE_NAME", "ITEM_ATTRIBUTE_ARTICLE", "ITEM_ATTRIBUTE_PLURALNAME", "ITEM_ATTRIBUTE_ACTIONID",
	"ITEM_ATTRIBUTE_ATTACK", "ITEM_ATTRIBUTE_DEFENSE", "ITEM_ATTRIBUTE_EXTRADEFENSE", "ITEM_ATTRIBUTE_ARMOR",
	"ITEM_ATTRIBUTE_HITCHANCE", "ITEM_ATTRIBUTE_SHOOTRANGE", "ITEM_ATTRIBUTE_CHARGES", "ITEM_ATTRIBUTE_DURATION",
	"ITEM_ATTRIBUTE_ATTACK_SPEED"}
local EXTRA_KEYS = {"rarity", "combatPowerLevel", "chaos_unique", "chaos_sockets", "chaos_uses", "omen_kind", "rift_tier",
	"rift_mods", "prefix", "chaos_mods_pending", "chaos_tmog"}
IC.STD = STD

local keyList
function IC.customKeys()
	if keyList then
		return keyList
	end
	local seen, list = {}, {}
	local function add(k)
		if type(k) == "string" and k ~= "" and not seen[k:lower()] then
			seen[k:lower()] = true
			list[#list + 1] = k
		end
	end
	for _, k in ipairs(EXTRA_KEYS) do
		add(k)
	end
	for i = 1, 8 do
		add((ChaosGems and ChaosGems.ATTR_GEM or "chaos_gem") .. i)
	end
	if ChaosCrafting and ChaosCrafting.attributeKeys then
		for _, k in ipairs(ChaosCrafting.attributeKeys()) do
			add(k)
		end
	end
	if ChaosCharms and ChaosCharms.attributeKeys then -- a charm's modifiers (charms.lua)
		for _, k in ipairs(ChaosCharms.attributeKeys()) do
			add(k)
		end
	end
	keyList = list
	return list
end

local function readAttrs(item)
	local list = {}
	for _, name in ipairs(STD) do
		local c = _G[name]
		if c and item:hasAttribute(c) then
			local v = item:getAttribute(c)
			if v ~= nil and v ~= "" and v ~= 0 then
				list[#list + 1] = {"@" .. name, v}
			end
		end
	end
	for _, k in ipairs(IC.customKeys()) do
		local v = item:getCustomAttribute(k)
		if v ~= nil then
			list[#list + 1] = {k, v}
		end
	end
	return list
end
IC.readAttrs = readAttrs

local function writeAttrs(item, list)
	for _, a in ipairs(list) do
		local k, v = a[1], a[2]
		if k:sub(1, 1) == "@" then
			local c = _G[k:sub(2)]
			if c then
				item:setAttribute(c, v)
			end
		else
			item:setCustomAttribute(k, v)
		end
	end
end

function IC.encode(item, useBlob)
	if useBlob == nil then
		useBlob = IC.hasBlob()
	end
	if useBlob then
		local blob = item:serializeAttributes()
		if type(blob) == "string" then
			return "blob", CC.hex(blob)
		end
	end
	return "attrs", CC.encodeAttrs(readAttrs(item))
end

function IC.decode(itemId, count, codec, data, useBlob)
	if useBlob == nil then
		useBlob = IC.hasBlob()
	end
	local item = Game.createItem(itemId, count)
	if not item then
		return nil, "could not create item " .. tostring(itemId)
	end
	if codec == "plain" then
		return item
	end
	if codec == "blob" then
		if not useBlob then
			return nil, "codec blob needs engine patch 0017"
		end
		local raw = CC.unhex(data)
		if not raw or not item:unserializeAttributes(raw) then
			return nil, "attributes could not be read"
		end
	else
		writeAttrs(item, CC.decodeAttrs(data))
	end
	-- a new per-item id: the engine gives one the first time the item is sent (engine patch 0003)
	item:removeCustomAttribute("chaos_iid")
	return item
end

-- every engine call guarded: scripts and tests hand over items with fewer methods
local function call(obj, method, ...)
	local f = obj and obj[method]
	if not f then
		return nil
	end
	local ok, v = pcall(f, obj, ...)
	if ok then
		return v
	end
	return nil
end

function IC.isPlain(item, useBlob)
	if useBlob == nil then
		useBlob = IC.hasBlob()
	end
	if useBlob and item.serializeAttributes then
		local raw = call(item, "serializeAttributes")
		if type(raw) == "string" then
			return CC.isPlainBlob(raw)
		end
	end
	for _, name in ipairs(STD) do
		local c = _G[name]
		if c and call(item, "hasAttribute", c) then
			return false
		end
	end
	for _, a in ipairs({"ITEM_ATTRIBUTE_UNIQUEID"}) do
		if _G[a] and call(item, "hasAttribute", _G[a]) then
			return false
		end
	end
	if item.getCustomAttribute then
		for _, k in ipairs(IC.customKeys()) do
			if call(item, "getCustomAttribute", k) ~= nil then
				return false
			end
		end
		if call(item, "getCustomAttribute", "chaos_locked") ~= nil or call(item, "getCustomAttribute", "chaos_storebound") ~= nil then
			return false
		end
	end
	return true
end

return IC

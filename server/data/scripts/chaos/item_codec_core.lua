-- The item codec's text forms, without engine calls (item_codec.lua; market_core.lua points its codec functions here;
-- tests: server/tests/market_test.lua, server/tests/stash_test.lua).
--
-- A stored item is a row with an item id, a count, a codec and a text:
--   codec "blob"   the engine's own binary form of every attribute (item:serializeAttributes(), engine patch 0017),
--                  hex encoded
--   codec "attrs"  a key list (without patch 0017): "key=n:123;key=s:<hex>;..." with every key hex encoded; a key
--                  "@NAME" is the standard attribute ITEM_ATTRIBUTE_NAME
--   codec "plain"  nothing but the item id and the count (a plain stack, the stash merges these by type)
--
--   ChaosItemCodecCore.hex(s) / unhex(h)             bytes <-> lower case hex (unhex: nil for odd length or a non hex digit)
--   ChaosItemCodecCore.encodeAttrs(list) / decodeAttrs(text)   the "attrs" text form of {{key, value}}
--   ChaosItemCodecCore.isPlainBlob(raw)              true when a serialized item holds nothing but its count: the engine
--                                                    writes ATTR_COUNT (15) and one byte for a stack, nothing else
--   ChaosItemCodecCore.CODECS                        the codecs a row may carry
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosItemCodecCore = ChaosItemCodecCore or {}
local C = ChaosItemCodecCore

C.ATTR_COUNT = 15 -- the engine's ATTR_COUNT (item.h AttrTypes_t)
C.CODECS = {blob = true, attrs = true, plain = true}

function C.hex(s)
	return (tostring(s or ""):gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function C.unhex(h)
	h = tostring(h or "")
	if #h % 2 == 1 or h:find("[^%x]") then
		return nil
	end
	return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

function C.encodeAttrs(list)
	local parts = {}
	for _, a in ipairs(list or {}) do
		local k, v = a[1], a[2]
		if type(v) == "number" then
			parts[#parts + 1] = C.hex(k) .. "=n:" .. string.format("%.17g", v)
		elseif type(v) == "boolean" then
			parts[#parts + 1] = C.hex(k) .. "=b:" .. (v and "1" or "0")
		elseif v ~= nil then
			parts[#parts + 1] = C.hex(k) .. "=s:" .. C.hex(tostring(v))
		end
	end
	return table.concat(parts, ";")
end

function C.decodeAttrs(text)
	local list = {}
	for part in tostring(text or ""):gmatch("[^;]+") do
		local k, t, v = part:match("^(%x*)=(%a):(.*)$")
		if k then
			local key = C.unhex(k)
			local value
			if t == "n" then
				value = tonumber(v)
			elseif t == "b" then
				value = v == "1"
			elseif t == "s" then
				value = C.unhex(v)
			end
			if key and value ~= nil then
				list[#list + 1] = {key, value}
			end
		end
	end
	return list
end

function C.isPlainBlob(raw)
	if type(raw) ~= "string" then
		return false
	end
	if raw == "" then
		return true
	end
	return #raw == 2 and raw:byte(1) == C.ATTR_COUNT
end

return C

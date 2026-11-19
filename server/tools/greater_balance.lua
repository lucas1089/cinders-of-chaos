-- greater_balance.lua: greater_balance_config.lua as JSON for tools/greater_rift_model.py (O668).
-- Run from server/: luajit tools/greater_balance.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
local bal = dofile("data/scripts/chaos/greater_balance_config.lua")

local function json(v)
	local t = type(v)
	if t == "number" then
		return string.format("%.10g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v .. '"'
	elseif t == "table" then
		local n = 0
		for _ in pairs(v) do
			n = n + 1
		end
		if n == #v then
			local parts = {}
			for i = 1, n do
				parts[i] = json(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = json(k) .. ":" .. json(v[k] ~= nil and v[k] or v[tonumber(k)])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

print(json(bal))

-- waystone_endgame_numbers.lua: the waystone tier, endgame and balance configs as JSON, for tools/waystone_endgame_model.py (O666).
-- Run from server/: luajit tools/waystone_endgame_numbers.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
local function json(v)
	local t = type(v)
	if t == "number" then
		return string.format("%.10g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. (v:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
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
local tiers = dofile("data/scripts/chaos/waystone_tiers_config.lua")
tiers.maps, tiers.arrivals, tiers.layouts, tiers.clearPath = nil, nil, nil, nil
print(json({tiers = tiers, endgame = dofile("data/scripts/chaos/waystone_endgame_config.lua"),
	bal = dofile("data/scripts/chaos/waystone_endgame_balance_config.lua")}))

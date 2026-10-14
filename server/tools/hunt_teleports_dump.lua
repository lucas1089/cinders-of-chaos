-- Prints hunt_teleports_config.lua as JSON for server/tools/install_content_areas.py.
-- Run from the server/ folder: luajit tools/hunt_teleports_dump.lua [CONFIG]   (Lua 5.3 too)
local path = arg and arg[1] or "data/scripts/chaos/hunt_teleports_config.lua"
local cfg = dofile(path)

local function isArray(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local function json(v)
	local t = type(v)
	if t == "table" then
		local parts = {}
		if isArray(v) and (next(v) == nil or v[1] ~= nil) then
			for i = 1, #v do
				parts[i] = json(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local x = v[k]
			if x == nil then
				x = v[tonumber(k)]
			end
			parts[#parts + 1] = json(k) .. ":" .. json(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "number" then
		if v == math.floor(v) then
			return string.format("%d", v)
		end
		return tostring(v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end

print(json(cfg))

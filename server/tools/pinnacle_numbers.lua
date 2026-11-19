-- pinnacle_numbers.lua: the pinnacle boss config, its balance config and the mechanics profiles of the four bosses, as JSON, for
-- tools/pinnacle_model.py (O667; server/README.md "Pinnacle bosses (O667)"). Run from server/: luajit tools/pinnacle_numbers.lua
-- Prints {"cfg": pinnacle_config.lua, "bal": pinnacle_balance_config.lua, "profiles": {lower boss name: profile}, "fair":
-- boss_mechanics_config.lua fair}. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
local cfg = dofile("data/scripts/chaos/pinnacle_config.lua")
local bal = dofile("data/scripts/chaos/pinnacle_balance_config.lua")
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")

local function json(v)
	local t = type(v)
	if t == "number" then
		return string.format("%.10g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", c:byte())
		end) .. '"'
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
			local x = v[k]
			if x == nil then
				x = v[tonumber(k)]
			end
			parts[#parts + 1] = json(k) .. ":" .. json(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local profiles = {}
for _, b in ipairs(cfg.bosses) do
	local p = mech.profiles[b.name:lower()]
	if p then
		profiles[b.name:lower()] = p
	end
end
print(json({cfg = cfg, bal = bal, profiles = profiles, fair = mech.fair}))

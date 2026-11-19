-- greater_numbers.lua: the Greater Rift numbers of the rift config and core, as JSON, for tools/greater_rift_model.py
-- (O668; server/README.md "Greater Rift (O668)"). Run from server/: luajit tools/greater_numbers.lua [LEVEL,LEVEL,...]
-- Prints {"greater": cfg.greater, "maxTier", "tier15": {minLevel, limit, solo = {packs, guardian, walk}, party5 = {...},
--         refArea, refSingle, shown, walkRoute}, "info": {"1": {health, damage, level, reward}, ...}, "tps": {"1500": n, ...},
--         "engineBonus": 0.0015}.
-- The clear parts are R.clearParts at tier 15 for a typical player (dps 1) and a party of 5 (dps 1: the model scales it).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
local cfg = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/scripts/chaos/guardian_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local R = ChaosRiftCore

local function json(v)
	local t = type(v)
	if t == "number" then
		return string.format("%.10g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('"', '\\"') .. '"'
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

local top = cfg.maxTier
local t15 = R.tierInfo(cfg, top)
local out = {maxTier = top, greater = cfg.greater, engineBonus = 0.0015}
local ref1, ref2 = R.refDps(cfg, t15.minLevel)
out.tier15 = {minLevel = t15.minLevel, limit = R.timeLimit(cfg, top), clock = R.greaterClock(cfg, R.timeLimit(cfg, top)),
	solo = R.clearParts(cfg, top, 1, 1), party5 = R.clearParts(cfg, top, 5, 1), refArea = ref1, refSingle = ref2,
	health = t15.health, damage = t15.damage, chestGold = R.reward(cfg, top, nil, function(a) return a end).gold}
out.info = {}
for g = 1, 149 do
	local i = R.greaterInfo(cfg, g)
	out.info[tostring(g)] = {health = i.health, damage = i.damage, level = i.level, reward = i.reward, shown = i.shown}
end
out.tps = {}
local levels = {1025, 1500, 2000, 2500}
if arg and arg[1] then
	levels = {}
	for n in arg[1]:gmatch("%d+") do
		levels[#levels + 1] = tonumber(n)
	end
end
for _, l in ipairs(levels) do
	out.tps[tostring(l)] = R.tilesPerSecond(l)
end
print(json(out))

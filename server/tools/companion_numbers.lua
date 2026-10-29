-- companion_numbers.lua: the Beastmaster companion's numbers from the real config and classes.lua, as JSON, for
-- server/tools/companion_model.py (the companion balance model, O306; server/README.md "Beastmaster companion (O306)").
-- Run from server/: luajit tools/companion_numbers.lua [LEVEL:DISTANCESKILL ...]
-- Prints {"rows": [...], "config": {...}, "balance": {...}, "necro": {...}}: a row is one level: the health, the bites
-- (the companion's own, the same bite x 1.5), the cap and what a 1000 point hit becomes on the companion.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/class_tree.lua")
local C = ChaosClasses
local balance = dofile("data/scripts/chaos/companion_balance_config.lua")
local necro = dofile("data/scripts/chaos/necro_balance_config.lua")

-- JSON of plain tables (arrays are tables with keys 1..n)
local function json(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return string.format("%.6g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
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

local rows = {}
for i = 1, #arg do
	local level, skill = arg[i]:match("^(%d+):([%d%.]+)$")
	level, skill = tonumber(level), tonumber(skill)
	local alo, ahi = C.autoBiteValues(level, skill)
	local mlo, mhi = C.biteValues(level, skill, 1)
	local wlo, whi = C.biteValues(level, skill, 1.5)
	rows[#rows + 1] = {
		level = level, skill = skill, health = C.companionHealth(level), cap = C.companionCap(level),
		autoMin = alo, autoMax = ahi, mulMin = mlo, mulMax = mhi, wolfMin = wlo, wolfMax = whi, shown = C.companionLevel(level),
		taken = C.companionDamageTaken(1000, 0), takenAlpha = C.companionDamageTaken(1000, 0.25)
	}
end

print(json({rows = rows, config = Chaos.classes.companion, balance = balance, necro = {monsterDps = necro.monsterDps},
	classDamage = ChaosClassTree.classDamage, packAlpha = ChaosClassTree.fx.ksPackAlpha}))

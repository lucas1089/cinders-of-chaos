-- descent_numbers.lua: the Lua side of the Ember Descent model (tools/descent_model.py, server/README.md "Ember Descent model
-- (O664)") from the real files, as JSON. Run from server/: luajit tools/descent_numbers.lua [legacy] LEVEL [LEVEL ...]
-- Prints {"cfg": {...}, "pool": [...], "levels": {level: {depth: {esc, plan}}}, "pick": {...}, "balance": {...}}.
--   cfg      the numbers of descent_config.lua the model reads (rooms, waves, size, elite, boss, escalation, boons, curses, pace)
--   pool     every hunt entry of bounty_pool.lua with scaled (a level of its own, pace_core.lua entryLevel), ph / pd (the
--            health and damage factor a Descent monster gets, descent_core.lua paceScale) and hh / hd (the hunt's own)
--   levels   for every party level and depth 1-12: the real escalation (window, health, damage, tier mix) and the room plans
--            (waves, monsters per wave) of combat, elite, treasure and boss rooms for 1 to maxPlayers players, with and without
--            the Swarm curse
--   pick     for every party level and depth: the types pickTypes draws for 12 seeds (the model's candidates must hold them)
--   balance  descent_balance_config.lua (the model's inputs and limits)
-- `legacy` as the first argument: the config with pace.enabled = false and boss.damage = 1 (the state before O664).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
dofile("data/scripts/chaos/descent_core.lua")
dofile("data/scripts/chaos/pace_core.lua")
local DC = ChaosDescentCore
local PC = ChaosPaceCore
local cfg = dofile("data/scripts/chaos/descent_config.lua")
local pcfg = dofile("data/scripts/chaos/pace_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")

local args = {}
for i = 1, #arg do
	args[#args + 1] = arg[i]
end
if args[1] == "legacy" then
	table.remove(args, 1)
	cfg.pace = {enabled = false}
	cfg.boss.damage = 1
end

local function json(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return string.format("%.10g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
	elseif t == "table" then
		local n = 0
		for _ in pairs(v) do
			n = n + 1
		end
		if n > 0 and n == #v then
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
for _, e in ipairs(pool.hunt) do
	local level, scaled = PC.entryLevel(pcfg, e)
	local f = PC.factors(pcfg, level, scaled)
	local ph, pd = DC.paceScale(cfg, PC, pcfg, e)
	rows[#rows + 1] = {name = e.name, level = e.level, exp = e.exp, health = e.health, spawns = e.spawns, scaled = scaled,
		ph = ph, pd = pd, hh = f.health, hd = f.damage}
end

local MAXDEPTH = 12
local levels = {}
local pick = {}
for _, a in ipairs(args) do
	local level = tonumber(a)
	local byDepth, pickDepth = {}, {}
	for depth = 1, MAXDEPTH do
		local plans = {}
		for _, kind in ipairs({"combat", "elite", "treasure", "boss"}) do
			local row = {}
			for n = 1, cfg.maxPlayers do
				row[tostring(n)] = {plain = DC.roomPlan(cfg, kind, depth, n, 0), swarm = DC.roomPlan(cfg, kind, depth, n, 30)}
			end
			plans[kind] = row
		end
		local esc = DC.escalation(cfg, depth, level)
		byDepth[tostring(depth)] = {esc = esc, plan = plans}
		local names = {}
		for seed = 1, 12 do
			local types = DC.pickTypes(cfg, pool.hunt, esc.window, nil, DC.roomRng(seed, depth, "types"))
			for _, m in ipairs(types) do
				names[#names + 1] = m.name
			end
		end
		pickDepth[tostring(depth)] = names
	end
	levels[tostring(level)] = byDepth
	pick[tostring(level)] = pickDepth
end

local keep = {"enabled", "maxPlayers", "rooms", "roomWeights", "eliteFrom", "waves", "size", "types", "elite", "treasure",
	"escalation", "boss", "boons", "curseFrom", "curseChance", "curses", "pace", "readySeconds", "nextRoomDelay"}
local out = {}
for _, k in ipairs(keep) do
	out[k] = cfg[k]
end

print(json({cfg = out, pool = rows, levels = levels, pick = pick, balance = dofile("data/scripts/chaos/descent_balance_config.lua")}))

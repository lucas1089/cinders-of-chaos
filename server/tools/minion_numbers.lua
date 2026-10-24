-- minion_numbers.lua: the Necromancer line's minion numbers from the real config and core, as JSON, for
-- server/tools/minion_model.py (the minion balance model; server/data/spells/README.md "Necromancer minions (O160)").
-- Run from server/: luajit tools/minion_numbers.lua LEVEL:MAGICLEVEL [LEVEL:MAGICLEVEL ...]
-- Prints {"rows": [...], "config": {...}, "balance": {...}, "classDamage": {...}} where a row is one class, minion kind
-- and level: the hit range, the health, the caps, the damage per second of one minion on 1 and on 5 enemies (the
-- minion's action cycle with its two spells, run with necro_core.lua N.minionSpell: the same choice the server makes),
-- the regeneration per second and the share of a monster's damage the minion takes. No tree, no class damage factor.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
local cfg = dofile("data/scripts/chaos/necro_config.lua")
dofile("data/scripts/chaos/necro_core.lua")
local N = ChaosNecroCore
local balance = dofile("data/scripts/chaos/necro_balance_config.lua")
dofile("data/scripts/chaos/class_tree.lua")
local pace = dofile("data/scripts/chaos/pace_config.lua")

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

-- Damage per second of one minion of `kind` against `near` enemies standing close together, in units of its hit range
-- (avg of min and max): the action cycle of necro_minions.lua act(): every intervalMs the area spell when `near` enemies
-- are in it and it is ready, else the single target spell when ready, else the plain hit. The area spell strikes every
-- enemy in it, the others only the target.
local function perSecond(kind, near, avgHit, seconds)
	local interval = cfg.minions[kind].intervalMs
	local timers, t, total = {}, 0, 0
	while t < seconds * 1000 do
		local which = N.minionSpell(cfg, kind, t, timers, near)
		if which then
			timers[which] = t + cfg.minionSpells[kind][which].cooldownMs
			local lo, hi = N.minionSpellHit(cfg, kind, which, avgHit, avgHit)
			total = total + (lo + hi) / 2 * (which == "area" and near or 1)
		else
			total = total + avgHit * (cfg.minions[kind].slam and near or 1)
		end
		t = t + interval
	end
	return total / seconds
end

local rows = {}
for i = 1, #arg do
	local level, ml = arg[i]:match("^(%d+):([%d%.]+)$")
	level, ml = tonumber(level), tonumber(ml)
	for _, class in ipairs({"necromancer", "lich", "bonelord"}) do
		for _, kind in ipairs(N.kinds) do
			local lo, hi = N.minionHit(cfg, class, kind, level, ml, false)
			local avg = (lo + hi) / 2
			rows[#rows + 1] = {
				class = class, kind = kind, level = level, ml = ml, hitMin = lo, hitMax = hi,
				health = N.minionHealth(cfg, class, kind, level, ml),
				cap = N.minionCap(cfg, class, kind, level), total = N.totalCap(cfg, class, level),
				dps1 = perSecond(kind, 1, avg, 240), dps5 = perSecond(kind, 5, avg, 240),
				regen = N.minionRegen(cfg, 1000, false, 1000), regenIdle = N.minionRegen(cfg, 1000, true, 1000),
				taken = N.minionTaken(cfg, 1000, 0.5)
			}
		end
	end
end

print(json({rows = rows, config = {minions = cfg.minions, minionSpells = cfg.minionSpells, summonSpells = cfg.summonSpells,
	raiseDead = cfg.raiseDead}, balance = balance, classDamage = ChaosClassTree.classDamage, paceDamage = pace.damage}))

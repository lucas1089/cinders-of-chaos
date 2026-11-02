-- survival_numbers.lua: the class numbers of the survival model (tools/survival_model.py, server/README.md "Hunt survival
-- by class (O367)") from the real data files, as JSON. Run from server/: luajit tools/survival_numbers.lua LEVEL [LEVEL ...]
-- Prints {"balance": {...}, "classes": {...}, "evasion": {...}, "monkEvasion": {...}, "fx": {...}, "effects": {...},
-- "pace": {...}, "boost": {...}, "potions": {...}, "auras": {...}, "guard": {...}, "guardAt": {vocation id: {level: reduction}},
-- "builds": {class: {level: [build, ...]}}}.
-- A build row is one Auto build of passive_builds_data.lua cut to the tree points of the level (Chaos.passive: one point
-- every levelsPerPoint levels from startLevel), with the sums of the stats the model uses and the flags it holds.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/class_tree.lua")
dofile("data/scripts/chaos/monk_chi_core.lua")
dofile("data/scripts/chaos/templar_aura_core.lua")
dofile("data/scripts/chaos/passivetree_data.lua")
dofile("data/scripts/chaos/passive_builds_data.lua")
local balance = dofile("data/scripts/chaos/survival_balance_config.lua")
local start = dofile("data/scripts/chaos/start_stats.lua")
local pace = dofile("data/scripts/chaos/pace_config.lua")
local boost = dofile("data/scripts/chaos/monster_damage_config.lua")
local potions = dofile("data/scripts/chaos/potions_config.lua")

-- the numbers block of passivetree_effects.lua (the file itself needs the engine's constants)
local function effectsConfig()
	local f = assert(io.open("data/scripts/chaos/passivetree_effects.lua", "rb"))
	local text = f:read("*a")
	f:close()
	local body = assert(text:match("\nlocal cfg = (%b{})"), "passivetree_effects.lua: no cfg table")
	local chunk = assert((loadstring or load)("return " .. body))
	return chunk()
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

local STATS = {"vitality", "spirit", "absorbPhysical", "absorbAllElements"}
local FLAGS = {"ctFleetShadow", "ksBlackbloodCreed", "ksLivingShadow", "ksScarredDiscipline", "ksImmovable"}

local function points(level)
	local p = Chaos.passive
	return math.max(0, math.floor((level - p.startLevel) / p.levelsPerPoint))
end

local nodes = ChaosPassiveTreeData.nodes
local classes, builds = {}, {}
for key, vocId in pairs(Chaos.classes.ids) do
	local s = start.stats[vocId]
	local variant = ChaosClasses.keystoneKey(vocId)
	classes[key] = {id = vocId, line = ChaosClasses.classKey(Chaos.classes.baseOf[vocId]), health = s.health, mana = s.mana,
		gainhp = s.gainhp, gainmana = s.gainmana}
	builds[key] = {}
	for i = 1, #arg do
		local level = tonumber(arg[i])
		local n = points(level)
		local rows = {}
		for _, b in ipairs(ChaosPassiveBuildsData.classes[key] or {}) do
			if b.kind == "role" then
				local sum, flags = {}, {}
				for j = 1, math.min(n, #b.order) do
					local node = nodes[b.order[j]]
					local st = (node.v and node.v[variant]) or node.s or {}
					for _, k in ipairs(STATS) do
						sum[k] = (sum[k] or 0) + (tonumber(st[k]) or 0)
					end
					for _, k in ipairs(FLAGS) do
						if st[k] then
							flags[#flags + 1] = k
						end
					end
				end
				for _, k in ipairs(STATS) do
					sum[k] = sum[k] or 0
				end
				sum.id = b.id
				sum.flags = flags
				rows[#rows + 1] = sum
			end
		end
		builds[key][tostring(level)] = rows
	end
end

print(json({
	balance = balance, classes = classes, builds = builds,
	evasion = Chaos.classes.evasion, monkEvasion = ChaosMonk.cfg.evasion,
	fx = {fleetShadow = ChaosClassTree.fx.ctFleetShadow.evasion, creedScale = ChaosClassTree.fx.ksBlackbloodCreed.evasionScale,
		scarred = ChaosClassTree.fx.ksScarredDiscipline.reduction, immovable = ChaosClassTree.fx.ksImmovable.reduction},
	effects = effectsConfig(),
	pace = {damage = pace.damage, enabled = pace.enabled},
	boost = {points = boost.points, enabled = boost.enabled, elemental = boost.elemental},
	potions = {everfull = potions.everfull, amount = potions.amount},
	auras = ChaosTemplar.cfg.aura.byVocation,
	guard = Chaos.classes.guard,
	-- the guard reduction of the game's own function (classes.lua) at every requested level, by vocation id
	guardAt = (function()
		local out = {}
		for _, vocId in pairs(Chaos.classes.ids) do
			local row = {}
			for i = 1, #arg do
				row[arg[i]] = ChaosClasses.guardReduction(vocId, tonumber(arg[i]))
			end
			out[tostring(vocId)] = row
		end
		return out
	end)()
}))

-- pocket_numbers.lua: the numbers of the world pocket bosses, as JSON, for tools/boss_length_model.py (O704; server/README.md "Pocket boss
-- profile (O704)"). Run from server/: luajit tools/pocket_numbers.lua
-- Prints {"pocket": boss_mechanics_config.lua `pocket`, "bosses": [{key, name, xmlHealth, xmlHeal, settings (pocketboss_config.lua health
-- curve of the boss), event (the event profile's ref), profile (the pocket profile), before = {n: row}, after = {n: row}, weak = {n: seconds}}]}.
-- A row = {health (the fight's health after the mechanics' factor), hpMult, seconds (the median class's kill time: health / (damage a second
-- x (uptime - the mechanics' downtime) - heal) + the fixed seconds), share, fixed}, for 1 to 5 players of the median class.
--   before  what the code did before O704: the event profile by the boss's name, its factor of the event ref (10 players, G.refFor(ref) at every
--           size), health = the file's x the category's world curve (3% solo, +2.5% a player), the file's own heal, the adds and totems of the event
--   after   the pocket profile: pocketboss.lua hands attach partySize and healthScale = the override's health curve, so the factor is worked out for that
--           size (G.refFor(ref, size, health)); the heal is the file's x healScale (boss_mechanics.lua), the adds and totems of the pocket profile
--   weak    after, for the weakest class (0.75 of the median, class_dps_model.py keeps every class within 25%) with the same health
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		n = n + 1
		rawset(t, k, n)
		return n
	end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/uber_core.lua")
dofile("data/scripts/chaos/pocketboss_core.lua")
local K = ChaosPocketBossCore
local pcfg = dofile("data/scripts/chaos/pocketboss_config.lua")
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local G = dofile("data/scripts/chaos/boss_mechanics_core.lua")

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
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "table" then
		local count = 0
		for _ in pairs(v) do
			count = count + 1
		end
		if count == #v then
			local parts = {}
			for i = 1, count do
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

local function readFile(path)
	local h = io.open(path, "rb")
	if not h then
		return ""
	end
	local s = h:read("*a")
	h:close()
	return s
end

local function xmlOf(name)
	local f = "data/monster/monsters/chaos/world_bosses/" .. name:lower():gsub("[^%w]+", "_") .. ".xml"
	local text = readFile(f)
	local health = tonumber(text:match('<health now="(%d+)"')) or 0
	local interval, chance, lo, hi = text:match('<defense name="healing" interval="(%d+)" chance="(%d+)" min="(%d+)" max="(%d+)"')
	local heal = 0
	if interval then
		heal = tonumber(chance) / 100 * (tonumber(lo) + tonumber(hi)) / 2 / (tonumber(interval) / 1000)
	end
	return health, heal
end

-- the median class's seconds on a fight: health, the boss's heal a second, `players` of the class at `each` damage a second on one boss
local function seconds(p, players, health, heal, each, up)
	local dps = players * each
	local dpsE = dps - heal / up
	if dpsE <= 0 then
		return math.huge, 0, 0
	end
	local share, fixed = G.downtime(p, {dps = dpsE, players = players})
	local up2 = math.max(0.3, up - share)
	return health / (dpsE * up2) + fixed, share, fixed
end

local P = mech.pocket
local out = {}
for i, b in ipairs(Chaos.worldBoss.bosses) do
	local key = b.name:lower()
	local raid = mech.profiles[key]
	local pocket = mech.profiles[P.prefix .. key]
	local entry = K.settings(pcfg, "world", "world_" .. i)
	local xmlHealth, xmlHeal = xmlOf(b.name)
	local row = {key = "world_" .. i, name = b.name, xmlHealth = xmlHealth, xmlHeal = xmlHeal, settings = entry.health, defaults = pcfg.categories.world.health,
		event = raid and raid.ref, profile = pocket, before = {}, after = {}, weak = {}}
	local each = P.dps
	for players = 1, P.players do
		-- before
		if raid then
			local solo = G.balance(raid, G.refFor(raid.ref))
			local health = xmlHealth * K.scale(pcfg.categories.world.health, players) * solo.hpMult
			local s, share, fixed = seconds(raid, players, health, xmlHeal, each, raid.ref.uptime)
			row.before[tostring(players)] = {health = health, hpMult = solo.hpMult, seconds = s, share = share, fixed = fixed}
		end
		-- after
		if pocket then
			local plain = xmlHealth * K.scale(entry.health, players)
			local ref = G.refFor(pocket.ref, players, plain)
			local bal = G.balance(pocket, ref)
			local health = plain * bal.hpMult
			local heal = xmlHeal * pocket.pocket.healScale
			local s, share, fixed = seconds(pocket, players, health, heal, each, pocket.ref.uptime)
			row.after[tostring(players)] = {health = health, plain = plain, hpMult = bal.hpMult, seconds = s, share = share, fixed = fixed,
				base = bal.base, final = bal.final}
			local w = seconds(pocket, players, health, heal, each * 0.75, pocket.ref.uptime)
			row.weak[tostring(players)] = w
		end
	end
	out[#out + 1] = row
end
print(json({pocket = P, bosses = out, limit = pcfg.categories.world.minutes * 60, worldLevel = Chaos.worldBoss.minLevel, partyMax = pcfg.party.max}))

-- party_factor_numbers.lua: the mechanics' health factor of the fights that give a party more health on a curve of the party size (O703;
-- server/README.md "Same flaw elsewhere (O702)", "applied (O703)"), as JSON, for tools/boss_length_model.py. Run from server/:
-- luajit tools/party_factor_numbers.lua
-- Prints {"fights": [{key, kind, rows: {size: row}}]}. A row is the real core's answer (boss_mechanics_core.lua G.refForCurve / G.balance, what
-- boss_mechanics.lua attach computes when dungeons.lua, guildboss.lua or rift.lua hand it the size and the health curve): health = the ref health
-- of that size, hpMult = the factor applied now (the fight's own size), soloMult = the factor of the profile's own party (the factor the fights
-- had before O703 at every size), base = the plain kill time, final = the time with the factor, oldFinal = the time with the factor the fights had.
-- Seconds are the ref's: the plain time of the solo ref (150 s for a dungeon boss, 313.5 s for an Omen guardian, 495 / 421 s for Gorvath).
-- Lua 5.1 / LuaJIT and Lua 5.3. No engine calls.
local G = dofile("data/scripts/chaos/boss_mechanics_core.lua")
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local D = dofile("data/scripts/chaos/dungeons_difficulty.lua")
dofile("data/scripts/chaos/guildboss_core.lua")
local gcfg = dofile("data/scripts/chaos/guildboss_config.lua")
local rcfg = dofile("data/scripts/chaos/rift_config.lua")
local B = ChaosGuildBossCore

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

local function rowOf(p, n, curve)
	local ref = G.refForCurve(p.ref, n, curve)
	local b = G.balance(p, ref)
	local solo = G.balance(p, G.refFor(p.ref))
	local dpsE = ref.dps - (ref.heal or 0) / ref.uptime
	local oldFinal = ref.health * solo.hpMult / (dpsE * math.max(0.3, ref.uptime - b.downShare)) + b.fixed
	return {health = ref.health, hpMult = b.hpMult, soloMult = solo.hpMult, base = b.base, final = b.final, oldFinal = oldFinal,
		share = b.downShare, fixed = b.fixed}
end

local fights = {}
local function add(key, kind, curve, sizes)
	local p = mech.profiles[key]
	local rows = {}
	for _, n in ipairs(sizes) do
		rows[tostring(n)] = rowOf(p, n, curve)
	end
	fights[#fights + 1] = {key = key, kind = kind, rows = rows, ref = p.ref}
end

local function dungeonCurve(n)
	return D.partyHealth(n, {healthPerExtra = 0.6})
end
local function omenCurve(n)
	return 1 + rcfg.omen.healthPerExtraPlayer * (math.max(1, n) - 1)
end
local function guildCurve(n)
	return B.healthMult(gcfg, n)
end

for _, k in ipairs({"vault keeper ossrim", "ossivane the gravecage", "forgewarden kharzun", "vaelith the fallen seraph", "azhkarrath the chained wyrm"}) do
	add(k, "dungeon", dungeonCurve, {1, 2, 3, 4, 5})
end
add("gorvath the banner-eater", "guild", guildCurve, {1, 2, 3, 4, 5, 10})
for _, k in ipairs({"sangrith the bloodmoon herald", "morvane the hollow crown", "thalcyra the stormbound seer"}) do
	add(k, "omen", omenCurve, {1, 2, 3, 4, 5})
end
print(json({fights = fights, guild = {enrageAt = gcfg.boss.enrageAt, targets = gcfg.targets, healthPerExtraPlayer = gcfg.boss.healthPerExtraPlayer,
	soloHealthMult = gcfg.boss.soloHealthMult}, omen = {healthPerExtraPlayer = rcfg.omen.healthPerExtraPlayer}}))

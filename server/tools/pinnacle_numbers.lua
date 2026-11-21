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
-- O698: the mechanics' health factor of each boss for each party size, from the real core (boss_mechanics_core.lua G.refFor / G.balance, the
-- numbers pinnacle.lua hands boss_mechanics.lua: the health of the size, the damage of that many players). `solo` is the factor of the profile's
-- own party, the one the fights used before O698 at every size. Arguments `NAME,HEALTH_SCALE,DPS_SCALE` (lower boss name; the committed health
-- and the median's damage times these) add `scaled`: the same rows for another health or damage (the options of pinnacle_model.py --options)
local G = dofile("data/scripts/chaos/boss_mechanics_core.lua")
local function rowOf(p, boss, n, hs, ds)
	local ref = G.refFor(p.ref, n, boss.health * (1 + (boss.perExtra or 0) * (n - 1)) * hs)
	ref.dps = ref.dps * ds
	if ref.weakDps then
		ref.weakDps = ref.weakDps * ds
	end
	local b = G.balance(p, ref)
	local solo = G.balance(p, G.refFor(p.ref))
	local dpsE = ref.dps - (ref.heal or 0) / ref.uptime
	local oldFinal = ref.health * solo.hpMult / (dpsE * math.max(0.3, ref.uptime - b.downShare)) + b.fixed
	return {health = ref.health, hpMult = b.hpMult, base = b.base, final = b.final, share = b.downShare, fixed = b.fixed,
		soloMult = solo.hpMult, soloFinal = oldFinal}
end
local factors = {}
for _, b in ipairs(cfg.bosses) do
	local p = mech.profiles[b.name:lower()]
	if p and p.ref then
		local rows = {}
		for n = 1, bal.players do
			rows[tostring(n)] = rowOf(p, b, n, 1, 1)
		end
		factors[b.name:lower()] = rows
	end
end
local scaled = {}
for _, a in ipairs(arg or {}) do
	local name, hs, ds = a:match("^(.-),([%d.]+),([%d.]+)$")
	if name then
		for _, b in ipairs(cfg.bosses) do
			local p = mech.profiles[b.name:lower()]
			if p and p.ref and b.name:lower() == name then
				local rows = {}
				for _, n in ipairs({1, bal.players}) do
					rows[tostring(n)] = rowOf(p, b, n, tonumber(hs), tonumber(ds))
				end
				scaled[a] = rows
			end
		end
	end
end
print(json({cfg = cfg, bal = bal, profiles = profiles, fair = mech.fair, factors = factors, scaled = scaled}))

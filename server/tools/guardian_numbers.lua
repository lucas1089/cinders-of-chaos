-- guardian_numbers.lua: the guardian and pack numbers of the rift config and cores, as JSON, for tools/guardian_model.py
-- (O427; server/README.md "Rifts", Guardian damage). Run from server/: luajit tools/guardian_numbers.lua [legacy]
-- With `legacy` the config is patched with guardian_balance_config.lua `legacy` first (the numbers before O427).
-- Prints {"tiers": [{tier, minLevel, pick, tierDamage, guardian, packDamage, count, live, marksBase, marksKit,
-- minion = {factor, splash}} ...], "omen": {guardian, marksBase, marksKit, minion}, "party": {...}}.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
local cfg = dofile("data/scripts/chaos/rift_config.lua")
local bal = dofile("data/scripts/chaos/guardian_balance_config.lua")
dofile("data/scripts/chaos/guardian_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local necro = dofile("data/scripts/chaos/necro_config.lua")
local G, R = ChaosGuardianCore, ChaosRiftCore

local function patch(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" and not v[1] then
			patch(dst[k], v)
		else
			dst[k] = v
		end
	end
end
local legacy = arg and arg[1] == "legacy"
if legacy then
	patch(cfg, bal.legacy.cfg)
	necro.minions.incoming = bal.legacy.necroIncoming
end

local function json(v)
	local t = type(v)
	if t == "number" then
		return string.format("%.6g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v .. '"'
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

-- mean marked-attack share of max health per second over the themes and seeds (the kit as the run draws it)
local function marks(base, tier, omen, kit)
	local themes = {}
	for _, th in ipairs(cfg.themes) do
		themes[#themes + 1] = th.name
	end
	local sum, n = 0, 0
	local diff = (base.difficulty or 0.2) + (base.tierDifficulty or 0) * math.max(0, tier - 1)
	for _, theme in ipairs(themes) do
		for seed = 1, 25 do
			local keys = {}
			if kit then
				local skip = {}
				for _, t in ipairs(base.telegraphs or {}) do
					skip[t.key] = true
				end
				keys = G.pickKit(cfg, seed * 131 + tier, theme, tier, omen, skip)
			end
			local p = G.profile(cfg, base, keys, tier, omen)
			sum = sum + G.markShare(p, diff, tier)
			n = n + 1
		end
	end
	return sum / n
end

local function hasKit()
	return not legacy
end

local out = {tiers = {}, omen = {}}
local d = cfg.density
for t = 1, cfg.maxTier do
	local ti = R.tierInfo(cfg, t)
	local dens = R.density(cfg, t, 1, nil, nil)
	local rg = mech.profiles.rift_guardian
	out.tiers[t] = {tier = t, minLevel = ti.minLevel, pick = ti.pick, tierDamage = ti.damage,
		guardian = G.damageMult(cfg, t, false), packDamage = R.packDamage(cfg, t),
		count = dens.count, live = dens.live,
		marksBase = marks(rg, t, false, false), marksKit = marks(rg, t, false, hasKit()),
		minion = {factor = hasKit() and cfg.guardian.minion.factor or necro.minions.incoming.factor,
			splash = hasKit() and cfg.guardian.minion.splash or 0}}
end
local omens = {}
for _, name in ipairs({"sangrith the bloodmoon herald", "morvane the hollow crown", "thalcyra the stormbound seer"}) do
	omens[#omens + 1] = mech.profiles[name]
end
local b0, b1 = 0, 0
for _, p in ipairs(omens) do
	b0 = b0 + marks(p, 1, true, false) / #omens
	b1 = b1 + marks(p, 1, true, hasKit()) / #omens
end
out.omen = {guardian = G.damageMult(cfg, nil, true), minLevel = cfg.omen.minLevel, marksBase = b0, marksKit = b1,
	minion = out.tiers[1].minion}
out.party = cfg.party
-- O476: what the single hit and the level warning read (tools/guardian_model.py hit_table / warn_levels)
local mods = {}
for _, m in ipairs(cfg.mods) do
	mods[#mods + 1] = {key = m.key, group = m.group, excludes = m.excludes, minTier = m.minTier, tiers = m.tiers,
		range = m.range, side = m.side}
end
out.hit = {maxTier = cfg.maxTier, types = cfg.packs.types, widenStep = cfg.widenStep, minPoolHealth = cfg.minPoolHealth,
	maxPlayers = cfg.maxPlayers, maxMods = cfg.key.maxMods, modWindow = cfg.modTiers.window, mods = mods,
	critMult = cfg.keen.critMult, brands = cfg.brands}
out.warn = cfg.warn
out.cap = cfg.guardian.hitCap -- O478: the cap of one guardian hit (rift_config.lua), the model's retention step reads it
bal.legacy = nil
out.bal = bal
print(json(out))

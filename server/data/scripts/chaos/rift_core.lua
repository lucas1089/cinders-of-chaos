-- Rifts: the pure part (no engine calls), shared by rift.lua and tests/rift_test.lua.
--   keys       rollModCount / rollMods / rollKey, encode / decode of the "rift_mods" attribute, name, description
--   effects    what the modifiers do to the monsters and the players, and the reward bonuses they give
--   plan       monster types from the bounty pool window of the tier, packs, elites, the boss threshold
--   rewards    the chest of one player, the next-key roll, the tier-1 key chance of a normal kill
--   instance   slot grid, slot allocation, the room layout of a slot (floor, walls, doorways)
--   run        timer / kill / boss / success / fail bookkeeping
--   exp        the experience cap (rate of the leveling model per minute in the rift)
-- Every random number comes from the `rand(a, b)` argument (integer in [a, b]).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosRiftCore = ChaosRiftCore or {}
local R = ChaosRiftCore

-- a text in `lang` (Chaos.t keys, i18n_strings.lua); English without ChaosI18n
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local floor = math.floor

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function weighted(rows, rand) -- rows = {{value, weight}, ...}
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return rows[1] and rows[1][1]
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end
R.weighted = weighted

-- true with probability p percent (resolution 1/10000 %)
local function chance(p, rand)
	if not p or p <= 0 then
		return false
	end
	if p >= 100 then
		return true
	end
	return rand(1, 1000000) <= floor(p * 10000 + 0.5)
end
R.chance = chance

-- ===================================================================== keys
function R.modDef(cfg, key)
	for i, m in ipairs(cfg.mods) do
		if m.key == key then
			return m, i
		end
	end
	return nil
end

function R.clampTier(cfg, tier)
	tier = floor(tonumber(tier) or 1)
	return clamp(tier, 1, cfg.maxTier)
end

function R.rollModCount(cfg, rand, better)
	return weighted(better and cfg.modCountBetter or cfg.modCount, rand)
end

-- roll weight of a modifier (default 100) and whether a key of `tier` may roll it (minTier, default 1; nil tier: any)
function R.modWeight(def)
	return def.weight or 100
end

function R.modAllowed(def, tier)
	return tier == nil or tier >= (def.minTier or 1)
end

-- ---------------------------------------------------------------- modifier tiers (I-V)
-- def.tiers = the highest value of each tier; tier 1 starts at range[1], tier t at tiers[t - 1] + step. A modifier
-- without `tiers` has none (R.modTier is nil).
function R.tierBounds(def, t)
	local tiers = def.tiers
	if not tiers or #tiers == 0 then
		return def.range[1], def.range[2]
	end
	t = clamp(floor(t), 1, #tiers)
	local lo = t == 1 and def.range[1] or tiers[t - 1] + def.step
	return lo, tiers[t]
end

function R.modTier(def, value)
	if not def or not def.tiers then
		return nil
	end
	for t, top in ipairs(def.tiers) do
		if value <= top then
			return t
		end
	end
	return #def.tiers
end

-- {lowest, highest} modifier tier a key of `tier` rolls (no tier or no table: I-III, the ranges before the tiers)
function R.modTierWindow(cfg, tier)
	local mt = cfg and cfg.modTiers
	if not mt or not tier then
		return 1, 3
	end
	for _, row in ipairs(mt.window) do
		if tier <= row[1] then
			return row[2], row[3]
		end
	end
	local last = mt.window[#mt.window]
	return last[2], last[3]
end

function R.tierName(cfg, t)
	local names = cfg and cfg.modTiers and cfg.modTiers.names
	return t and (names and names[t] or tostring(t)) or nil
end

-- a value for a modifier on a key of `tier`: evenly on the step grid from the bottom of the lowest to the top of the
-- highest tier of the window (one rand call; keys of tier 1-5 and calls without a tier roll exactly the I-III range)
local function rollValue(def, rand, tier, cfg)
	local lo, hi = def.range[1], def.range[2]
	if def.tiers then
		local a, b = R.modTierWindow(cfg, tier)
		b = math.min(b, #def.tiers)
		a = math.min(a, b)
		lo = (R.tierBounds(def, a))
		hi = select(2, R.tierBounds(def, b))
	end
	local steps = floor((hi - lo) / def.step)
	return lo + rand(0, steps) * def.step
end
R.rollValue = rollValue

-- true when two modifier definitions never share a key: the same `group`, or one `excludes` the other
function R.modConflict(a, b)
	if not a or not b or a.key == b.key then
		return false
	end
	if a.group and a.group == b.group then
		return true
	end
	for _, def in ipairs({a, b}) do
		local other = def == a and b or a
		for _, k in ipairs(def.excludes or {}) do
			if k == other.key then
				return true
			end
		end
	end
	return false
end

local function conflictsWith(cfg, def, have)
	for k in pairs(have or {}) do
		if R.modConflict(def, R.modDef(cfg, k)) then
			return true
		end
	end
	return false
end

-- indexes of cfg.mods a key of `tier` may still roll (not in `have` = {key = true}, and no conflict with them)
local function modPool(cfg, tier, have)
	local pool = {}
	for i, def in ipairs(cfg.mods) do
		if R.modAllowed(def, tier) and not (have and have[def.key]) and R.modWeight(def) > 0
				and not conflictsWith(cfg, def, have) then
			pool[#pool + 1] = i
		end
	end
	return pool
end
R.modPool = modPool

-- draws up to `count` different indexes from pool (weighted, without replacement); a pick takes every modifier it
-- conflicts with (R.modConflict) out of the pool. Without groups the draws are the same as before.
local function drawMods(cfg, pool, count, rand)
	local picked = {}
	for _ = 1, count do
		if #pool == 0 then
			break
		end
		local total = 0
		for _, i in ipairs(pool) do
			total = total + R.modWeight(cfg.mods[i])
		end
		local roll, acc = rand(1, total), 0
		for k, i in ipairs(pool) do
			acc = acc + R.modWeight(cfg.mods[i])
			if roll <= acc then
				picked[#picked + 1] = table.remove(pool, k)
				break
			end
		end
		local got = cfg.mods[picked[#picked]]
		for k = #pool, 1, -1 do
			if R.modConflict(got, cfg.mods[pool[k]]) then
				table.remove(pool, k)
			end
		end
	end
	table.sort(picked)
	return picked
end

-- `count` different modifiers, each {key =, value =}, in the order of cfg.mods (weighted by `weight`; with a tier,
-- only the modifiers whose minTier it reaches)
function R.rollMods(cfg, count, rand, tier)
	local mods = {}
	for _, i in ipairs(drawMods(cfg, modPool(cfg, tier), count, rand)) do
		local m = cfg.mods[i]
		mods[#mods + 1] = {key = m.key, value = rollValue(m, rand, tier, cfg)}
	end
	return mods
end

-- adds up to `count` new modifiers to key (the orbs of upheaval_crafting.lua); returns the added ones. key.mods stays in
-- config order.
function R.addMods(cfg, key, count, rand)
	local have = {}
	for _, m in ipairs(key.mods) do
		have[m.key] = true
	end
	local added = {}
	for _, i in ipairs(drawMods(cfg, modPool(cfg, key.tier, have), count, rand)) do
		local def = cfg.mods[i]
		local m = {key = def.key, value = rollValue(def, rand, key.tier, cfg)}
		key.mods[#key.mods + 1] = m
		added[#added + 1] = m
	end
	key.mods = R.decodeMods(cfg, R.encodeMods(key.mods))
	return added
end

function R.rollKey(cfg, tier, rand, better)
	tier = R.clampTier(cfg, tier)
	return {tier = tier, mods = R.rollMods(cfg, R.rollModCount(cfg, rand, better), rand, tier)}
end

function R.encodeMods(mods)
	local parts = {}
	for _, m in ipairs(mods or {}) do
		parts[#parts + 1] = m.key .. ":" .. m.value
	end
	return table.concat(parts, ",")
end

-- parses and validates (unknown keys dropped, values clamped to the range, duplicates dropped, at most cfg.key.maxMods)
function R.decodeMods(cfg, text)
	local mods, seen = {}, {}
	if type(text) ~= "string" then
		return mods
	end
	local max = cfg.key and cfg.key.maxMods or 3
	for key, value in text:gmatch("([%a_]+):(%-?%d+)") do
		local def = R.modDef(cfg, key)
		-- a modifier that conflicts with one already read is dropped (the first in the text stays)
		if def and not seen[key] and #mods < max and not conflictsWith(cfg, def, seen) then
			seen[key] = true
			mods[#mods + 1] = {key = key, value = clamp(tonumber(value), def.range[1], def.range[2])}
		end
	end
	table.sort(mods, function(a, b)
		local _, ia = R.modDef(cfg, a.key)
		local _, ib = R.modDef(cfg, b.key)
		return ia < ib
	end)
	return mods
end

-- packed storage value of one modifier (index x 1000 + value) and back; used by the crash refund marker
function R.packMod(cfg, m)
	local _, i = R.modDef(cfg, m.key)
	return i and (i * 1000 + m.value) or 0
end

function R.unpackMod(cfg, n)
	n = tonumber(n) or 0
	local def = cfg.mods[floor(n / 1000)]
	if n <= 0 or not def then
		return nil
	end
	return {key = def.key, value = clamp(n % 1000, def.range[1], def.range[2])}
end

function R.keyName(cfg, tier)
	return string.format(cfg.key.nameFormat, tier)
end

function R.modText(cfg, m)
	local def = R.modDef(cfg, m.key)
	if not def then
		return m.key
	end
	return (def.text:find("%%d") and string.format(def.text, m.value) or def.text)
end

-- "Vitality III" (the name and the tier of a modifier; the name alone without a tier)
function R.modLabel(cfg, m)
	local def = R.modDef(cfg, m.key)
	if not def then
		return m.key
	end
	local t = R.modTier(def, m.value)
	return t and (def.name .. " " .. R.tierName(cfg, t)) or def.name
end

-- reward bonuses in percent {quantity, rarity, experience} from the modifiers (+ tiers above the table)
function R.bonuses(cfg, mods, tier)
	local b = {quantity = 0, rarity = 0, experience = 0}
	for _, m in ipairs(mods or {}) do
		local def = R.modDef(cfg, m.key)
		if def and def.reward then
			for k, per in pairs(def.reward) do
				if k == "fixed" then
					for fk, fv in pairs(per) do
						b[fk] = b[fk] + fv
					end
				elseif b[k] then
					b[k] = b[k] + per * m.value
				end
			end
		end
	end
	local cap = R.bonusCaps(cfg, mods)
	for k, v in pairs(b) do
		b[k] = floor(v + 0.5)
		if cap[k] and b[k] > cap[k] then
			b[k] = cap[k]
		end
	end
	return b
end

-- the caps of the summed bonuses: bonusCap + modTiers.capRaise of every tier IV / V modifier
function R.bonusCaps(cfg, mods)
	local cap = {}
	for k, v in pairs(cfg.bonusCap or {}) do
		cap[k] = v
	end
	local raise = cfg.modTiers and cfg.modTiers.capRaise
	if raise then
		for _, m in ipairs(mods or {}) do
			local t = R.modTier(R.modDef(cfg, m.key), m.value)
			local r = t and raise[t]
			if r then
				for k, v in pairs(r) do
					if cap[k] then
						cap[k] = cap[k] + v
					end
				end
			end
		end
	end
	return cap
end

function R.describe(cfg, key)
	local lines = {}
	for _, m in ipairs(key.mods or {}) do
		local t = R.modTier(R.modDef(cfg, m.key), m.value)
		lines[#lines + 1] = R.modText(cfg, m) .. (t and (" (" .. R.tierName(cfg, t) .. ")") or "")
	end
	local b = R.bonuses(cfg, key.mods, key.tier)
	local bonus = {}
	if b.quantity > 0 then
		bonus[#bonus + 1] = "+" .. b.quantity .. "% item quantity"
	end
	if b.rarity > 0 then
		bonus[#bonus + 1] = "+" .. b.rarity .. "% item rarity"
	end
	if b.experience > 0 then
		bonus[#bonus + 1] = "+" .. b.experience .. "% experience"
	end
	local t = R.tierInfo(cfg, key.tier)
	return string.format("Modifiers: %s. Rewards: %s. Opens a rift of tier %d (level %d+). Use it in a protection zone; your party within %d sqm comes along.",
		#lines > 0 and table.concat(lines, "; ") or "none", #bonus > 0 and table.concat(bonus, ", ") or "normal",
		key.tier, t.minLevel, cfg.partyRange)
end

-- ===================================================================== effects
function R.tierInfo(cfg, tier)
	tier = R.clampTier(cfg, tier)
	local n = #cfg.tiers
	local base = cfg.tiers[math.min(tier, n)]
	local over = math.max(0, tier - n)
	return {
		tier = tier,
		minLevel = base.minLevel + over * cfg.beyond.minLevelStep,
		pick = {base.pick[1], base.pick[2]},
		health = 1 + over * cfg.beyond.health,
		damage = 1 + over * cfg.beyond.damage,
		reward = 1 + over * cfg.beyond.reward
	}
end

-- what the modifiers do: multipliers / additions used by rift.lua
function R.effects(cfg, mods, tier)
	local t = R.tierInfo(cfg, tier)
	local fx = {health = t.health, damage = t.damage, speed = 0, elite = 1, reflect = 0, resist = 0, noRegen = false, packBonus = 0,
		packMult = 1, gilded = 0, warband = 0, coffer = 0, twin = 0, echo = 0, cinder = 0, healMult = 1, timeMult = 1,
		boss = 1, fragile = 0,
		-- third set: brand {element, share}, crit chance, physical damage taken, fester chance (percent), elemental
		-- reflect, one brood, guardian nova share, breach chance (percent), hexes, no mana, ground {kind, element,
		-- percent}, storm share
		brand = nil, crit = 0, physResist = 0, fester = 0, spite = 0, brood = false, wrath = 0, breach = 0, hexElem = 0,
		hexPhys = 0, sap = 0, noMana = false, ground = nil, storm = 0}
	for _, m in ipairs(mods or {}) do
		local v = m.value
		local brand = cfg.brands and cfg.brands[m.key]
		if brand then
			fx.brand = {element = brand, share = v / 100}
		elseif m.key == "keen" then
			fx.crit = v / 100
		elseif m.key == "ironhide" then
			fx.physResist = v / 100
		elseif m.key == "festering" then
			fx.fester = v
		elseif m.key == "spiteglass" then
			fx.spite = v / 100
		elseif m.key == "brood" then
			fx.brood = true
		elseif m.key == "wrath" then
			fx.wrath = v / 100
		elseif m.key == "breach" then
			fx.breach = v
		elseif m.key == "searing" then
			fx.hexElem = v / 100
		elseif m.key == "flaying" then
			fx.hexPhys = v / 100
		elseif m.key == "sapping" then
			fx.sap = v / 100
		elseif m.key == "parched" then
			fx.noMana = true
		elseif m.key == "scorched" or m.key == "rimefloor" then
			local el = cfg.ground and cfg.ground.element and cfg.ground.element[m.key] or "fire"
			fx.ground = {kind = m.key, element = el, percent = v}
		elseif m.key == "veilstorm" then
			fx.storm = v / 100
		end
		if m.key == "vitality" then
			fx.health = fx.health * (1 + v / 100)
		elseif m.key == "brutality" then
			fx.damage = fx.damage * (1 + v / 100)
		elseif m.key == "haste" then
			fx.speed = fx.speed + v
		elseif m.key == "elites" then
			fx.elite = fx.elite * (1 + v / 100)
		elseif m.key == "reflection" then
			fx.reflect = fx.reflect + v / 100
		elseif m.key == "warding" then
			fx.resist = fx.resist + v / 100
		elseif m.key == "withering" then
			fx.noRegen = true
		elseif m.key == "swarm" then
			fx.packBonus = fx.packBonus + v
		elseif m.key == "teeming" then
			fx.packMult = fx.packMult * (1 + v / 100)
		elseif m.key == "gilded" then
			fx.gilded = v -- percent chance of the goblin
		elseif m.key == "warband" then
			fx.warband = v -- percent of packs
		elseif m.key == "coffer" then
			fx.coffer = v -- percent chance of the coffer
		elseif m.key == "twin" then
			fx.twin = v / 100 -- health share of each guardian
		elseif m.key == "echo" then
			fx.echo = v -- percent chance per kill
		elseif m.key == "cinder" then
			fx.cinder = v / 100 -- share of the monster's max health
		elseif m.key == "blight" then
			fx.healMult = fx.healMult * (1 - v / 100)
		elseif m.key == "waning" then
			fx.timeMult = fx.timeMult * (1 - v / 100)
		elseif m.key == "dread" then
			fx.boss = fx.boss * (1 + v / 100) -- guardian health and damage
		elseif m.key == "fragile" then
			fx.fragile = fx.fragile + v -- fewer lives
		end
	end
	fx.packDamage = R.packDamage(cfg) -- density: pack monsters hit softer (R.monsterHit)
	return fx
end

-- ===================================================================== plan
-- pool entries of the window (hunt list of bounty_pool.lua), filtered by `known(name)` when given
function R.candidates(cfg, pool, window, known)
	local list = {}
	for _, e in ipairs(pool or {}) do
		if e.level >= window[1] and e.level <= window[2] and (e.health or 0) >= cfg.minPoolHealth
				and (not known or known(e.name)) then
			list[#list + 1] = e
		end
	end
	return list
end

-- `cfg.packs.types` different monster types for a tier (window widened when too few)
function R.pickTypes(cfg, pool, tier, rand, known)
	local t = R.tierInfo(cfg, tier)
	local want = cfg.packs.types
	local window = {t.pick[1], t.pick[2]}
	local list = R.candidates(cfg, pool, window, known)
	local widen = 0
	while #list < want and widen < 5 do
		widen = widen + 1
		window = {window[1] - cfg.widenStep, window[2] + cfg.widenStep}
		list = R.candidates(cfg, pool, window, known)
	end
	local picked = {}
	for _ = 1, math.min(want, #list) do
		picked[#picked + 1] = table.remove(list, rand(1, #list))
	end
	table.sort(picked, function(a, b)
		if a.level == b.level then
			return a.name < b.name
		end
		return a.level < b.level
	end)
	return picked
end

-- scale (optional): the density share (R.density), so a denser rift has about as many elites as before
local function eliteTier(cfg, fx, tier, rand, scale)
	local mult = fx.elite * (1 + cfg.elite.perTier * tier) * (scale or 1)
	local roll = rand(1, 1000000)
	local acc = 0
	for _, name in ipairs({"legendary", "rare", "magic"}) do
		acc = acc + floor(cfg.elite[name] * mult * 10000)
		if roll <= acc then
			return name
		end
	end
	return nil
end
R.eliteTier = eliteTier

-- the looks of a run (rift-exclusive outfits, cfg.looks): {byName = {[lowercase type name] = lookType}, guardian =
-- lookType, names = {[lowercase type name] = shown name}, guardianName}, or nil (looks off, or a theme without a
-- family). `types` sorted by level (R.pickTypes): the weakest is the minion, the strongest the elite, the rest brutes;
-- one type is the elite, two are brute and elite. Each rank shows its name of cfg.looks.names (none: the type's own).
function R.lookPlan(cfg, themeName, types)
	local L = cfg.looks
	local fam = L and L.enabled and L.families and L.families[themeName]
	if not fam then
		return nil
	end
	local names = L.names and L.names[themeName] or {}
	local plan = {byName = {}, guardian = R.bigLook(L, fam.guardian), names = {}, guardianName = names.guardian}
	local n = #types
	for i, e in ipairs(types) do
		local rank = "brute"
		if i == n then
			rank = "elite"
		elseif i == 1 and n >= 3 then
			rank = "minion"
		end
		plan.byName[e.name:lower()] = fam[rank]
		plan.names[e.name:lower()] = names[rank]
		local var = L.variantsOn and L.variants and L.variants[themeName] and L.variants[themeName][rank]
		if var and #var > 0 then
			plan.variants = plan.variants or {}
			plan.variants[e.name:lower()] = var
		end
	end
	plan.variantShare = L.variantShare or 0
	return plan
end

-- a guardian's bigger look (cfg.looks.bigGuardians, only with looks.bigGuardiansOn): the big look listed for `look`,
-- else `look` itself (also nil). L = cfg.looks.
function R.bigLook(L, look)
	if L and L.bigGuardiansOn and L.bigGuardians and look and L.bigGuardians[look] then
		return L.bigGuardians[look]
	end
	return look
end

-- the rank variant a pack monster wears (cfg.looks.variants, only with looks.variantsOn): {look, name} or nil (the
-- rank's own look and name). roll in [0, 1), one per spawn: below variantShare it picks one of the rank's variants
-- (evenly), else none. Guardians have no variants.
function R.pickVariant(plan, name, boss, roll)
	if not plan or boss or not plan.variants then
		return nil
	end
	local list = plan.variants[tostring(name):lower()]
	local share = plan.variantShare or 0
	if not list or #list == 0 or not roll or roll >= share then
		return nil
	end
	return list[math.min(#list, floor(roll / share * #list) + 1)]
end

-- the name a rift monster shows: its rank's name (the guardian's for a guardian); nil = its type's own
function R.nameOf(plan, name, boss)
	if not plan then
		return nil
	end
	if boss then
		return plan.guardianName
	end
	return plan.names and plan.names[tostring(name):lower()]
end

-- the look a rift monster wears: the guardian's for a guardian, else its type's rank's; nil = its own
function R.lookOf(plan, name, boss)
	if not plan then
		return nil
	end
	if boss then
		return plan.guardian
	end
	return plan.byName[tostring(name):lower()]
end

-- the run plan: {types, packs = {{room, name, count, elites = {tier or false, ...}}}, total, bossAt, boss}
-- rooms = list of room names the packs may use (the layout's sections in the order they fill); the first pack goes
-- to opts.first (default "hub"); opts.area = the layout's walkable tiles (density, R.density)
function R.plan(cfg, tier, fx, players, types, rooms, rand, opts)
	opts = opts or {}
	players = math.max(1, players or 1)
	local plan = {types = types, packs = {}, total = 0}
	if #types == 0 then
		return plan
	end
	local dens = R.density(cfg, tier, players, fx, opts.area)
	plan.density = dens
	local count = dens and dens.packs or R.packCount(cfg, tier, players)
	if not dens and (fx.packMult or 1) ~= 1 then
		count = floor(count * fx.packMult + 0.5) -- Teeming
	end
	local sizes = dens and cfg.density.size or cfg.packs.size
	local areas = {}
	for _, r in ipairs(rooms) do
		areas[#areas + 1] = r
	end
	for i = 1, count do
		local room
		if i == 1 or #areas == 0 then
			room = opts.first or "hub"
		else
			room = areas[(i - 2) % #areas + 1]
		end
		local size = rand(sizes[1], sizes[2]) + (fx.packBonus or 0)
		local name = types[rand(1, #types)].name
		if fx.brood then
			name = types[#types].name -- Single Brood: every pack of the strongest kind
		end
		local elites, laden = {}, nil
		for k = 1, size do
			elites[k] = eliteTier(cfg, fx, tier, rand, dens and dens.share) or false
		end
		if dens then
			-- husks: only the share of the normal monsters that the packs of before had carries loot
			laden = {}
			for k = 1, size do
				laden[k] = elites[k] and true or chance(dens.normalShare * 100, rand)
			end
		end
		local warband = (fx.warband or 0) > 0 and chance(fx.warband * (dens and dens.share or 1), rand)
		if warband then -- Warbands: every member at least rare, the first legendary
			for k = 1, size do
				if elites[k] ~= "legendary" then
					elites[k] = "rare"
				end
			end
			elites[1] = "legendary"
			for k = 1, laden and size or 0 do
				laden[k] = true
			end
		end
		plan.packs[#plan.packs + 1] = {room = room, name = name, count = size, elites = elites, warband = warband or nil,
			laden = laden}
		plan.total = plan.total + size
	end
	plan.bossAt = math.max(1, math.ceil(plan.total * cfg.bossAt / 100))
	plan.boss = types[#types].name -- the strongest type (types are sorted by level)
	plan.guardians = (fx.twin or 0) > 0 and 2 or 1
	-- Gilded Trail: the kill count at which the goblin appears (nil: no goblin this run)
	if (fx.gilded or 0) > 0 and chance(fx.gilded, rand) then
		local at = cfg.gilded and cfg.gilded.atKills or {25, 60}
		plan.gildedAt = math.max(1, math.ceil(plan.total * rand(at[1], at[2]) / 100))
	end
	-- Sealed Coffer: the room it stands in (nil: no coffer this run)
	if (fx.coffer or 0) > 0 and chance(fx.coffer, rand) then
		plan.coffer = #rooms > 0 and rooms[rand(1, #rooms)] or "hub"
	end
	return plan
end

-- packs of a run before Teeming: packs.base + tier / packs.perTiers + packs.perExtraPlayer x (players - 1)
function R.packCount(cfg, tier, players)
	players = math.max(1, floor(tonumber(players) or 1))
	return cfg.packs.base + floor(tier / cfg.packs.perTiers) + cfg.packs.perExtraPlayer * (players - 1)
end

-- ===================================================================== density
-- cfg.density (rift_config.lua): many more, weaker monsters per run. Off (or no block): every function returns nil /
-- the values of before.
function R.densityOn(cfg)
	return cfg and cfg.density and cfg.density.enabled and true or false
end

local function mean(a, b)
	return (a + b) / 2
end

-- the size band of a key tier (rift_config.lua layout.sizes): index, side, time limit; nil without layouts
function R.band(cfg, tier)
	local lc = cfg and cfg.layout
	if not (lc and lc.enabled and lc.sizes) then
		return nil
	end
	for i, row in ipairs(lc.sizes) do
		if tier <= row[1] then
			return i, row[2], row[3]
		end
	end
	local last = lc.sizes[#lc.sizes]
	return #lc.sizes, last[2], last[3]
end

-- walkable tiles and walking distance (arrival -> arena) of a typical layout of the tier's band (layout.typical,
-- measured over the generated layouts); nil without layouts
function R.typicalLayout(cfg, tier)
	local b = R.band(cfg, R.clampTier(cfg, tier or 1))
	return b and cfg.layout.typical and cfg.layout.typical[b] or nil
end

-- the plan's and the live cap's growth with the layout (density.area): (walkable / ref) ^ exp, 1 to maxMult.
-- area nil: the typical layout of the tier's band; 1 without layouts
function R.areaMult(cfg, area, tier)
	local a = cfg.density.area
	if not a then
		return 1
	end
	if not area then
		local t = R.typicalLayout(cfg, tier or 1)
		area = t and t.walkable
	end
	if not area then
		return 1
	end
	return math.min(a.maxMult, math.max(1, (area / a.ref) ^ a.exp))
end

-- planned monsters before Teeming / Swarm: count.base + perTier x (t - 1), x (1 + perExtraPlayer x (players - 1)),
-- x the layout's area (R.areaMult; area = walkable tiles, nil = the band's typical layout)
function R.densityCount(cfg, tier, players, area)
	local c = cfg.density.count
	players = math.max(1, floor(tonumber(players) or 1))
	return (c.base + c.perTier * (R.clampTier(cfg, tier) - 1)) * (1 + c.perExtraPlayer * (players - 1))
		* R.areaMult(cfg, area, tier)
end

-- expected monsters of the packs of before (density off) with the run's Teeming / atlas density and Swarm
function R.legacyMonsters(cfg, tier, players, fx)
	local packs = R.packCount(cfg, tier, players)
	if fx and (fx.packMult or 1) ~= 1 then
		packs = floor(packs * fx.packMult + 0.5)
	end
	return packs * (mean(cfg.packs.size[1], cfg.packs.size[2]) + (fx and fx.packBonus or 0))
end

-- the share of a monster that is magic or better (before the Elites modifier), x scale
function R.eliteShare(cfg, tier, scale)
	local m = (1 + cfg.elite.perTier * tier) * (scale or 1)
	return math.min(1, (cfg.elite.magic + cfg.elite.rare + cfg.elite.legendary) * m / 100)
end

-- the average health multiplier of a monster from its tier (monster_tiers.lua), elite chances x scale
function R.eliteHealthAvg(cfg, tier, scale)
	local hp = cfg.density.model.tierHp
	local m = (1 + cfg.elite.perTier * tier) * (scale or 1)
	local avg, rest = 0, 1
	for _, k in ipairs({"magic", "rare", "legendary"}) do
		local p = cfg.elite[k] / 100 * m
		avg, rest = avg + p * hp[k], rest - p
	end
	return avg + math.max(0, rest)
end

-- a run's density: {count, packs, share, normalShare, legacy, live} or nil (off). share = monsters of before / now
-- (at most 1): the elite chances, Warbands and the laden share follow it, so the spoils of a run stay as before.
function R.density(cfg, tier, players, fx, area)
	if not R.densityOn(cfg) then
		return nil
	end
	local d = cfg.density
	players = math.max(1, floor(tonumber(players) or 1))
	local size = mean(d.size[1], d.size[2]) + (fx and fx.packBonus or 0)
	local packs = math.max(1, floor(R.densityCount(cfg, tier, players, area) / mean(d.size[1], d.size[2]) * (fx and fx.packMult or 1) + 0.5))
	local count = packs * size
	local legacy = R.legacyMonsters(cfg, tier, players, fx)
	local share = math.min(1, legacy / count)
	local before = R.eliteShare(cfg, tier, 1)
	local now = R.eliteShare(cfg, tier, share)
	return {count = count, packs = packs, share = share, legacy = legacy,
		normalShare = math.min(1, legacy * (1 - before) / (count * (1 - now))), live = R.liveCap(cfg, players, area, tier),
		area = area}
end

-- monsters alive at once (the rest wait in the queue): base + perExtraPlayer x (players - 1) + per100 per 100
-- walkable tiles of the layout (area nil: the typical layout of the tier's band, none without layouts), at most max
function R.liveCap(cfg, players, area, tier)
	local l = cfg.density.live
	if not area and l.per100 then
		local t = R.typicalLayout(cfg, tier or 1)
		area = t and t.walkable
	end
	local byArea = (area and l.per100) and floor(l.per100 * area / 100) or 0
	return math.min(l.max, l.base + l.perExtraPlayer * (math.max(1, floor(tonumber(players) or 1)) - 1) + byArea)
end

-- walking speed of a player of `level` in tiles a second on straight steps (engine patch 0018's base speed, the
-- engine's step formula, ground speed density.model.walk.ground, steps rounded up to 10 ms; no haste)
function R.tilesPerSecond(level)
	level = math.max(1, level or 1)
	local speed = 270 + 2.5 * (math.min(level, 300) - 1) + math.max(0, level - 300)
	local calc = math.max(1, floor(857.36 * math.log(speed / 2 + 261.29) - 4795.01 + 0.5))
	local ms = math.ceil(1000 * 150 / calc / 10) * 10
	return 1000 / ms
end

-- the model's walking time of a run: the layout's walking distance arrival -> arena (route; nil = the band's typical
-- layout) x walk.sweep (side branches, packs off the way) at the tier's level
function R.walkSeconds(cfg, tier, route)
	local w = cfg.density.model.walk
	if not w then
		return 0
	end
	if not route then
		local t = R.typicalLayout(cfg, tier)
		route = t and t.route or 0
	end
	return route * w.sweep / R.tilesPerSecond(R.tierInfo(cfg, tier).minLevel)
end

-- the damage model of the budget (rift_config.lua density.model) at a player level: area (5 targets) and single target
function R.refDps(cfg, level)
	local m = cfg.density.model
	local x = math.max(1, level) / 1000
	return m.dps5 * x ^ m.dps5Exp * m.gear, m.dps1 * x ^ m.dps1Exp * m.gear
end

-- health of a normal pack monster of a tier (before its magic / rare / legendary tier, the modifiers, the tiers above
-- 10 and the party): the packs up to the guardian take packSeconds of a typical solo player's area damage
function R.packHealth(cfg, tier, walkable)
	local m = cfg.density.model
	local t = R.tierInfo(cfg, tier)
	local area = R.refDps(cfg, t.minLevel)
	local d = R.density(cfg, t.tier, 1, nil, walkable)
	local budget = area * m.uptime * m.packSeconds / (cfg.bossAt / 100)
	return math.max(1, floor(budget / (d.count * R.eliteHealthAvg(cfg, t.tier, d.share)) + 0.5))
end

-- the guardian's base health (x boss.healthMult = what R.guardianHealthMult multiplies): guardianSeconds of a typical
-- solo player's single-target damage
function R.guardianBase(cfg, tier)
	local m = cfg.density.model
	local t = R.tierInfo(cfg, tier)
	local _, single = R.refDps(cfg, t.minLevel)
	return math.max(1, floor(single * m.guardianUptime * m.guardianSeconds / cfg.boss.healthMult + 0.5))
end

-- the model's time of a run in seconds (packs up to the guardian, then the guardian) for `players` with `dps` times a
-- typical player's damage in total (the party model: 4.98 for five), no modifiers
function R.clearSeconds(cfg, tier, players, dps, walkable, route)
	local m = cfg.density.model
	local t = R.tierInfo(cfg, tier)
	local area, single = R.refDps(cfg, t.minLevel)
	local d = R.density(cfg, t.tier, players, nil, walkable)
	local ps = R.party(cfg, players)
	local packs = d.count * cfg.bossAt / 100 * R.packHealth(cfg, t.tier, walkable) * R.eliteHealthAvg(cfg, t.tier, d.share)
		* t.health * R.partyMonsterHealth(cfg, t.tier, players)
	local guardian = R.guardianBase(cfg, t.tier) * R.guardianHealthMult(cfg, {health = t.health}, players)
	dps = dps or 1
	return packs / (area * m.uptime * dps) + guardian / (single * m.guardianUptime * dps) + R.walkSeconds(cfg, t.tier, route)
end

-- the run's base time limit (before Waning Veil and charms): the band's (layout.sizes), else timeLimit
function R.timeLimit(cfg, tier)
	local _, _, limit = R.band(cfg, R.clampTier(cfg, tier or 1))
	return limit or cfg.timeLimit
end

-- pack monster damage multiplier (the guardians keep theirs)
function R.packDamage(cfg)
	return R.densityOn(cfg) and cfg.density.damage or 1
end

-- ===================================================================== party scaling
-- cfg.party (rift_config.lua): with n players who entered,
--   health  the rift's total monster health x (1 + healthPerExtraPlayer x (n - 1))
--   damage  rift monsters and guardians x (1 + damagePerExtraPlayer x (n - 1))
--   reward  every finisher's chest x (1 + min(rewardCap, rewardPerExtraPlayer x (n - 1)) / 100)
--   loot    the kills' Chaos loot rate and the Sealed Coffer x (1 + min(lootCap, lootPerExtraPlayer x (n - 1)) / 100)
-- Solo (or no cfg.party): every value 1.
function R.party(cfg, players)
	local p = cfg and cfg.party
	local extra = math.max(1, floor(tonumber(players) or 1)) - 1
	if not p or extra == 0 then
		return {players = extra + 1, health = 1, damage = 1, reward = 1, loot = 1}
	end
	return {
		players = extra + 1,
		health = 1 + (p.healthPerExtraPlayer or 0) * extra,
		damage = 1 + (p.damagePerExtraPlayer or 0) * extra,
		reward = 1 + math.min(p.rewardCap or 0, (p.rewardPerExtraPlayer or 0) * extra) / 100,
		loot = 1 + math.min(p.lootCap or 0, (p.lootPerExtraPlayer or 0) * extra) / 100
	}
end

-- each pack monster's health multiplier for the party: the packs already grow with the players (R.packCount), so a
-- monster gets the rest of the total health curve (party.health x solo packs / party packs), never below 1
function R.partyMonsterHealth(cfg, tier, players)
	local ps = R.party(cfg, players)
	if ps.players <= 1 then
		return 1
	end
	if R.densityOn(cfg) then
		return math.max(1, ps.health * R.densityCount(cfg, tier, 1) / R.densityCount(cfg, tier, ps.players))
	end
	return math.max(1, ps.health * R.packCount(cfg, tier, 1) / R.packCount(cfg, tier, ps.players))
end

-- the party part of a run's effects (after R.effects / R.applyAtlasFx): fx.damage x party damage (every rift monster
-- and guardian), fx.partyHealth (each pack monster's extra health), fx.party (the R.party table). Omen arenas pass
-- tier nil (no packs). Changes and returns fx.
function R.applyParty(cfg, fx, players, tier)
	local ps = R.party(cfg, players)
	fx.party = ps
	fx.damage = (fx.damage or 1) * ps.damage
	fx.partyHealth = tier and R.partyMonsterHealth(cfg, tier, players) or 1
	return fx
end

-- one finisher's chest x the party bonus: gold, orbs and item rolls (fractions a chance of one more). Changes and
-- returns r; solo leaves it as it was.
function R.partyReward(cfg, r, players, rand)
	local m = R.party(cfg, players).reward
	if m == 1 then
		return r
	end
	r.gold = floor((r.gold or 0) * m)
	r.chaos = R.roundChance((r.chaos or 0) * m, rand)
	r.divine = R.roundChance((r.divine or 0) * m, rand)
	r.rolls = math.max(1, R.roundChance((r.rolls or 1) * m, rand))
	r.partyMult = m
	return r
end

-- a count (Omen Fragments) x the party bonus, fractions a chance of one more
function R.partyCount(cfg, n, players, rand)
	local m = R.party(cfg, players).reward
	if m == 1 or (n or 0) <= 0 then
		return n
	end
	return R.roundChance(n * m, rand)
end

-- the chat line of a party's scaling ("Party of 3: monster health x3, damage +20%; every chest +20%, loot +10%."),
-- nil solo. health = the health multiplier to show (the rift total, or the guardian's)
function R.partyNote(ps, health)
	if not ps or ps.players <= 1 then
		return nil
	end
	local function pct(x)
		return floor((x - 1) * 100 + 0.5)
	end
	return string.format("Party of %d: monster health x%s, damage +%d%%; every chest +%d%%, loot +%d%%.", ps.players,
		tostring(floor((health or ps.health) * 100 + 0.5) / 100), pct(ps.damage), pct(ps.reward), pct(ps.loot))
end

-- the guardian's health multiplier (on its base health): boss.healthMult, players, the modifiers' health, Dread
-- Guardian, and the Twin Guardians share of each
function R.guardianHealthMult(cfg, fx, players)
	local c = cfg.boss
	local m = c.healthMult * (1 + c.perExtraPlayer * (math.max(1, players or 1) - 1)) * (fx.health or 1) * (fx.boss or 1)
	if (fx.twin or 0) > 0 then
		m = m * fx.twin
	end
	return m
end

-- Cinderdeath: fire damage of a slain monster's burst
function R.cinderDamage(cfg, maxHealth, share, tier)
	if not share or share <= 0 then
		return 0
	end
	local c = cfg.cinder
	return math.max(1, floor(math.min((maxHealth or 0) * share, c.capBase + c.capPerTier * R.clampTier(cfg, tier))))
end

-- ---------------------------------------------------------------- hits (third set of modifiers)
-- T = the engine's combat types: {physical, none, brand = {fire = ..., ice = ..., energy = ...}}.
-- A rift monster hits a player: hit = {primary, ptype, secondary, stype, boss = true for a guardian}. Returns
-- primary, ptype, secondary, stype, info = {crit = true, fester = amount (positive) or nil}.
-- Order: the run's damage (Brutality, tiers above 10, party, x Dread Guardian for a guardian, x density.damage for a
-- pack monster), Keen Fangs, the brand (extra damage of its element, in the free secondary slot, else on the primary),
-- the hexes on the parts of their kind, Festering Wounds on the total.
function R.monsterHit(cfg, fx, hit, T, rand)
	local p, pt, s, st = hit.primary or 0, hit.ptype, hit.secondary or 0, hit.stype
	local info = {}
	local mult = fx.damage or 1
	if hit.boss then
		mult = mult * (fx.boss or 1)
	else
		mult = mult * (fx.packDamage or 1)
	end
	if (fx.crit or 0) > 0 and chance(fx.crit * 100, rand) then
		mult = mult * (cfg.keen and cfg.keen.critMult or 1.5)
		info.crit = true
	end
	if mult ~= 1 then
		p, s = floor(p * mult), floor(s * mult)
	end
	if fx.brand and fx.brand.share > 0 and T.brand and T.brand[fx.brand.element] then
		local extra = floor((p + s) * fx.brand.share)
		local bt = T.brand[fx.brand.element]
		if s == 0 or st == T.none or st == nil or st == bt then
			s, st = s + extra, bt
		else
			p = p + extra
		end
	end
	local function hex(v, t)
		if v == 0 or t == nil or t == T.none then
			return v
		end
		if t == T.physical then
			return (fx.hexPhys or 0) > 0 and floor(v * (1 + fx.hexPhys)) or v
		end
		return (fx.hexElem or 0) > 0 and floor(v * (1 + fx.hexElem)) or v
	end
	p, s = hex(p, pt), hex(s, st)
	if (fx.fester or 0) > 0 and chance(fx.fester, rand) then
		local n = floor((math.abs(p) + math.abs(s)) * (cfg.festering and cfg.festering.share or 0.4))
		info.fester = n > 0 and n or nil
	end
	return p, pt, s, st, info
end

-- a player (or a player's summon, fromPlayer) hits a rift monster: Warding (non-physical), Ironhide (physical), Sapping
-- Hex (fromPlayer). Returns primary, secondary, elemental = the non-physical part after them (for Spiteglass).
function R.monsterTaken(fx, hit, T)
	local p, s = hit.primary or 0, hit.secondary or 0
	local function cut(v, t)
		if v == 0 or t == nil or t == T.none then
			return v, 0
		end
		if t == T.physical then
			return (fx.physResist or 0) > 0 and floor(v * (1 - fx.physResist)) or v, 0
		end
		v = (fx.resist or 0) > 0 and floor(v * (1 - fx.resist)) or v
		return v, v
	end
	local ep, es
	p, ep = cut(p, hit.ptype)
	s, es = cut(s, hit.stype)
	if hit.fromPlayer and (fx.sap or 0) > 0 then
		local k = 1 - fx.sap
		p, s, ep, es = floor(p * k), floor(s * k), floor(ep * k), floor(es * k)
	end
	return p, s, math.abs(ep) + math.abs(es)
end

-- a share of a player's max health as a hit (ground, storm, nova): at least 1
function R.percentHit(maxHealth, share)
	return math.max(1, floor((maxHealth or 0) * share + 0.5))
end

-- a patch of ground: a plus of 5 tiles around its centre
function R.plus(c)
	return {{x = c.x, y = c.y, z = c.z}, {x = c.x + 1, y = c.y, z = c.z}, {x = c.x - 1, y = c.y, z = c.z},
		{x = c.x, y = c.y + 1, z = c.z}, {x = c.x, y = c.y - 1, z = c.z}}
end

-- a tile within `near` sqm of pos (rand)
function R.nearTile(pos, near, rand)
	return {x = pos.x + rand(-near, near), y = pos.y + rand(-near, near), z = pos.z}
end

-- the open room (or "hub") for the next reinforcement: the one whose centre is farthest from the nearest player,
-- if that is at least minDistance sqm (Chebyshev); nil when every room is too close. centres = {name = pos}
function R.reinforceRoom(centres, players, minDistance)
	local best, bestD
	for name, c in pairs(centres) do
		local d = math.huge
		for _, p in ipairs(players) do
			d = math.min(d, math.max(math.abs(p.x - c.x), math.abs(p.y - c.y)))
		end
		if d >= minDistance and (not bestD or d > bestD or (d == bestD and name < best)) then
			best, bestD = name, d
		end
	end
	return best
end

-- Sealed Coffer: number of monsters in the wave
function R.cofferWaveSize(cfg, players)
	local w = cfg.coffer.wave
	return w.base + w.perExtraPlayer * (math.max(1, players or 1) - 1)
end

-- ===================================================================== rewards
function R.lootTier(cfg, tier)
	for _, row in ipairs(cfg.reward.lootTier) do
		if tier <= row[1] then
			return row[2]
		end
	end
	return "boss"
end

-- whole number with a chance for the fraction: 2.3 -> 2, 30% 3
local function roundChance(x, rand)
	local n = floor(x)
	local frac = x - n
	if frac > 0 and rand(1, 10000) <= floor(frac * 10000 + 0.5) then
		n = n + 1
	end
	return n
end
R.roundChance = roundChance

-- one player's chest (without the item rolls' contents): {gold, chaos, divine, rolls, lootTier, rarityMult}
function R.reward(cfg, tier, bonus, rand)
	local t = R.tierInfo(cfg, tier)
	local q = 1 + (bonus and bonus.quantity or 0) / 100
	local scale = q * t.reward
	local r = cfg.reward
	return {
		gold = floor(r.goldPerTier2 * t.tier * t.tier * scale),
		chaos = roundChance((r.chaos.base + r.chaos.perTier * t.tier) * scale, rand),
		divine = roundChance((r.divine.base + r.divine.perTier * t.tier) * scale, rand),
		rolls = math.max(1, roundChance((r.rolls.base + r.rolls.perTier * t.tier) * scale, rand)),
		countMult = q, -- stack size of a rolled item
		lootTier = R.lootTier(cfg, t.tier),
		rarityMult = 1 + (bonus and bonus.rarity or 0) / 100
	}
end

-- the Sealed Coffer's contents: {gold, chaos, divine, rolls, countMult, lootTier, rarityMult}; players = who entered
function R.cofferLoot(cfg, tier, bonus, rand, players)
	local t = R.tierInfo(cfg, tier)
	local q = 1 + (bonus and bonus.quantity or 0) / 100
	local scale = q * t.reward * R.party(cfg, players).loot -- the party's loot bonus (one coffer for the party)
	local c = cfg.coffer
	return {
		gold = floor(c.goldPerTier2 * t.tier * t.tier * scale),
		chaos = roundChance((c.chaos.base + c.chaos.perTier * t.tier) * scale, rand),
		divine = roundChance((c.divine.base + c.divine.perTier * t.tier) * scale, rand),
		rolls = math.max(1, roundChance((c.rolls.base + c.rolls.perTier * t.tier) * scale, rand)),
		countMult = q,
		lootTier = R.lootTier(cfg, t.tier),
		rarityMult = 1 + (bonus and bonus.rarity or 0) / 100
	}
end

-- gold value -> coin stacks {{id, count}} (crystal 2160, platinum 2152, gold 2148; at most 100 per stack)
function R.coins(value)
	local out = {}
	for _, c in ipairs({{2160, 10000}, {2152, 100}, {2148, 1}}) do
		local n = floor(value / c[2])
		value = value - n * c[2]
		while n > 0 do
			local k = math.min(100, n)
			out[#out + 1] = {c[1], k}
			n = n - k
		end
	end
	return out
end

-- odds of the next key: {chance = percent of a key, nextTier = percent of those that are tier + 1}
-- am (optional): the Rift Atlas modifiers of the key user (R.atlasMods): keyChance adds to the chance and to its cap,
-- keyUpgrade to nextTier; the Ashen Ascent keystone halves the chance (keyChanceMult) and makes every key tier + 1
function R.keyOdds(cfg, modCount, am)
	local k = cfg.keyDrop
	modCount = modCount or 0
	local extra = am and am.keyChance or 0
	local odds = {
		chance = math.min(k.max + extra, k.base + k.perMod * modCount + extra),
		nextTier = math.min(100, k.nextTier + k.nextPerMod * modCount + (am and am.keyUpgrade or 0))
	}
	if am and am.keyChanceMult then
		odds.chance = odds.chance * am.keyChanceMult
	end
	if am and am.keyAscend then
		odds.nextTier = 100
	end
	return odds
end

-- nil, or the new key {tier, mods}. am (optional): as R.keyOdds; betterMods rolls the modifier count as a next-tier key
function R.rollKeyDrop(cfg, tier, modCount, rand, am)
	local odds = R.keyOdds(cfg, modCount, am)
	if not chance(odds.chance, rand) then
		return nil
	end
	local up = chance(odds.nextTier, rand) and tier < cfg.maxTier
	return R.rollKey(cfg, up and tier + 1 or tier, rand, up or (am and am.betterMods) or false)
end

-- per 100000 chance of a tier-1 key from a normal kill (0 when the kill does not qualify)
function R.monsterKeyChance(cfg, monsterLevel, killerLevel, tierName)
	local mk = cfg.monsterKey
	if not monsterLevel or not killerLevel then
		return 0
	end
	if killerLevel < cfg.tiers[1].minLevel then
		return 0
	end
	if monsterLevel < math.max(mk.minMonsterLevel, killerLevel * mk.levelShare) then
		return 0
	end
	return mk.chance * (mk.tierMult[tierName or "normal"] or 1)
end

-- ===================================================================== instance
function R.slotCount(cfg)
	return cfg.grid.cols * cfg.grid.rows
end

function R.slotCenter(cfg, slot)
	local g = cfg.grid
	local col, row = slot % g.cols, floor(slot / g.cols)
	local half = floor(g.spacing / 2)
	return {x = g.origin.x + col * g.spacing + half, y = g.origin.y + row * g.spacing + half, z = g.origin.z}
end

-- first slot that is neither busy nor bad (busy[slot] / bad[slot] = true), or nil
function R.allocSlot(cfg, busy, bad)
	for slot = 0, R.slotCount(cfg) - 1 do
		if not (busy and busy[slot]) and not (bad and bad[slot]) then
			return slot
		end
	end
	return nil
end

-- the slot whose square contains pos, or nil
function R.slotOfPos(cfg, pos)
	local g = cfg.grid
	if not pos or pos.z < g.origin.z or pos.z > g.origin.z + (g.floors or 1) - 1 then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / g.spacing), floor(dy / g.spacing)
	if col >= g.cols or row >= g.rows then
		return nil
	end
	return row * g.cols + col
end

-- ===================================================================== run state
-- run = R.newRun(cfg, now, total, bossAt[, fx]): {state = "running", startTime, deadline, limit, total, killed, bossAt,
-- boss = "waiting", guardians}. fx (R.effects): Waning Veil shortens the limit, Twin Guardians makes two guardians.
function R.newRun(cfg, now, total, bossAt, fx, base)
	local limit = math.max(60, floor((base or cfg.timeLimit) * (fx and fx.timeMult or 1) + 0.5))
	return {state = "running", startTime = now, deadline = now + limit, limit = limit, total = total, killed = 0,
		bossAt = bossAt or total, boss = "waiting", guardians = (fx and (fx.twin or 0) > 0) and 2 or 1}
end

function R.timeLeft(run, now)
	if run.state ~= "running" then
		return 0
	end
	return math.max(0, run.deadline - now)
end

-- a rift monster died: "boss" when the boss must appear now, else nil
function R.onKill(run)
	if run.state ~= "running" then
		return nil
	end
	run.killed = math.min(run.total, run.killed + 1)
	if run.boss == "waiting" and run.killed >= run.bossAt then
		run.boss = "alive"
		return "boss"
	end
	return nil
end

-- a guardian died: "twin" while another guardian still lives, then "success" (only while running and before the
-- deadline)
function R.onBossKilled(run, now)
	if run.state ~= "running" or run.boss ~= "alive" then
		return nil
	end
	if now > run.deadline then
		run.state = "failed"
		return "fail"
	end
	run.guardiansKilled = (run.guardiansKilled or 0) + 1
	if run.guardiansKilled < (run.guardians or 1) then
		return "twin"
	end
	run.boss = "dead"
	run.state = "success"
	run.endTime = now
	return "success"
end

-- the periodic check: "fail" once the time is up while the run is still going, else nil
function R.tick(run, now)
	if run.state == "running" and now >= run.deadline then
		run.state = "failed"
		run.endTime = now
		return "fail"
	end
	return nil
end

-- ===================================================================== lives
-- shared lives of a run: lives.base + perExtraPlayer x (players - 1) - Fragile, at least lives.min
function R.startLives(cfg, players, fx)
	local l = cfg.lives or {base = 3, perExtraPlayer = 1, min = 1}
	local n = l.base + l.perExtraPlayer * (math.max(1, players or 1) - 1) - (fx and fx.fragile or 0)
	-- Rift Atlas (R.applyAtlasFx): extra lives, or the Lone Ember keystone's single life
	if fx and fx.oneLife then
		return 1
	end
	n = n + (fx and fx.atlasLives or 0)
	return math.max(l.min or 1, n)
end

-- a player died inside a running run: one life less. Returns the lives left (0: the rift collapses), or nil when the
-- run is not running (the death costs nothing then)
function R.loseLife(run)
	if run.state ~= "running" then
		return nil
	end
	run.deaths = (run.deaths or 0) + 1
	run.lives = math.max(0, (run.lives or 1) - 1)
	return run.lives
end

-- ===================================================================== omens
-- a kind by its key ("bloodmoon") or index; returns def, index
function R.omenKind(cfg, k)
	local kinds = cfg.omen and cfg.omen.kinds or {}
	if type(k) == "number" then
		return kinds[k], kinds[k] and k or nil
	end
	for i, d in ipairs(kinds) do
		if d.key == k then
			return d, i
		end
	end
	return nil
end

function R.omenKeyName(cfg, kind)
	local d = R.omenKind(cfg, kind)
	return "Omen Key (" .. (d and d.name or "?") .. ")"
end

-- fragments of one finisher's chest of a sealed rift of `tier` (0 below omen.minTier)
function R.omenFragments(cfg, tier, bonus, rand)
	local o = cfg.omen
	if not o or tier < o.minTier then
		return 0
	end
	local q = 1 + (bonus and bonus.quantity or 0) / 100
	return roundChance((o.chest.base + o.chest.perTier * (tier - o.minTier)) * q, rand)
end

-- the guardian's health multiplier for `players`
function R.omenHealthMult(cfg, players)
	return 1 + cfg.omen.healthPerExtraPlayer * (math.max(1, players or 1) - 1)
end

-- one finisher's guardian chest: {gold, chaos, divine, rolls, countMult, lootTier, rarityMult, uniqueRolls, uniqueFind}.
-- Gold: goldPerLevel x the finisher's level (at least omen.minLevel); a flat `gold` of an older config still works.
function R.omenReward(cfg, level)
	local o = cfg.omen
	local r = o.reward
	local gold = r.gold
	if r.goldPerLevel then
		gold = floor(r.goldPerLevel * math.max(o.minLevel or 1, floor(tonumber(level) or 0)))
	end
	return {gold = gold or 0, chaos = r.chaos, divine = r.divine, rolls = r.rolls, countMult = 1, lootTier = "boss",
		rarityMult = r.rarityMult, uniqueRolls = r.uniqueRolls, uniqueFind = r.uniqueFind}
end

-- the crash refund marker stores a rift key's tier (1..maxTier) or omenMarker + the kind's index
R.omenMarker = 1000
function R.markerTier(cfg, kind)
	local _, i = R.omenKind(cfg, kind)
	return R.omenMarker + (i or 1)
end

function R.markerOmen(cfg, value)
	value = tonumber(value) or 0
	if value <= R.omenMarker then
		return nil
	end
	local d = R.omenKind(cfg, value - R.omenMarker)
	return d and d.key or nil
end

-- ===================================================================== experience cap
-- experience needed for a level (the engine's formula)
function R.expForLevel(level)
	level = level - 1
	return floor((50 * level * level * level - 150 * level * level + 400 * level) / 3)
end

-- base experience per minute of the leveling model at a level
function R.expRatePerMinute(cfg, level)
	local model = cfg.exp.model
	for _, b in ipairs(model) do
		if level >= b[1] and level < b[2] then
			return (R.expForLevel(b[2]) - R.expForLevel(b[1])) / (b[3] * 60)
		end
	end
	-- past the model: hours per level grow with the experience per level, so the rate stays the last band's
	local b = level < model[1][1] and model[1] or model[#model]
	return (R.expForLevel(b[2]) - R.expForLevel(b[1])) / (b[3] * 60)
end

-- how much of a kill's experience a player keeps: the factor (0..1) and the state updated.
-- st = {base = base experience already credited at full rate}; minutes = time in the run
function R.capFactor(cfg, st, level, base, minutes)
	if base <= 0 then
		return 1
	end
	local e = cfg.exp
	local allowed = R.expRatePerMinute(cfg, level) * math.max(minutes, e.capMinMinutes) * e.capFactor
	local room = allowed - (st.base or 0)
	if room >= base then
		st.base = (st.base or 0) + base
		return 1
	end
	if room > 0 then
		st.base = (st.base or 0) + room
		return (room + (base - room) * e.overCapMult) / base
	end
	return e.overCapMult
end

-- ===================================================================== rift atlas
-- The Rift Atlas (atlas.lua, atlas_core.lua, atlas_config.lua) plugs in through R.hooks; with no hook set every
-- function below leaves the run exactly as before. am = the flat modifiers of atlas_core.lua A.resolve (nil = none):
-- density, elite, time, modReward, goldMult, keyChance, keyUpgrade, fragments, chaos, divine, rolls, goblin, coffer,
-- lives, betterMods, themeWeights, and the keystone flags oneLife, rewardMult, guardianMult, orbsMult, keyChanceMult,
-- keyAscend, timeMult.
--   hooks.atlasMods(player, ctx) -> am      ctx = {theme = name, tier = number, omen = kind}
--   hooks.onSealed(info)                    info = {theme, tier, omen, deaths, secs, guids = {guid, ...}}
R.hooks = R.hooks or {}

function R.atlasMods(player, ctx)
	local f = R.hooks.atlasMods
	if not f or not player then
		return R.mergeWorld(nil, R.worldMods(player, ctx))
	end
	local ok, am = pcall(f, player, ctx or {})
	return R.mergeWorld(ok and type(am) == "table" and am or nil, R.worldMods(player, ctx))
end

-- The community goal and the weekly world modifier (community.lua) plug in through R.hooks.world(player, ctx) ->
-- nil or wm = {keyChance = percentage points, rewardMult = percent, extraMods = n}. With no hook, or a nil answer, every
-- function here returns its input unchanged.
function R.worldMods(player, ctx)
	local f = R.hooks.world
	if not f or not player then
		return nil
	end
	local ok, wm = pcall(f, player, ctx or {})
	return ok and type(wm) == "table" and wm or nil
end

-- am (the atlas modifiers, may be nil) with wm's key chance and chest bonus added; a copy, never am itself
function R.mergeWorld(am, wm)
	if not wm or ((wm.keyChance or 0) <= 0 and (wm.rewardMult or 0) <= 0) then
		return am
	end
	local out = {}
	for k, v in pairs(am or {}) do
		out[k] = v
	end
	out.keyChance = (out.keyChance or 0) + math.max(0, wm.keyChance or 0)
	out.rewardMult = (out.rewardMult or 0) + math.max(0, wm.rewardMult or 0)
	return out
end

-- a key about to be opened gets wm.extraMods more modifiers (Ember Tides); returns the added ones (none: {})
function R.worldKeyMods(cfg, player, key, rand)
	local wm = R.worldMods(player, {tier = key and key.tier})
	local n = wm and math.floor(wm.extraMods or 0) or 0
	if n <= 0 or not key or not key.mods then
		return {}
	end
	return R.addMods(cfg, key, n, rand)
end

function R.atlasSealed(info)
	local f = R.hooks.onSealed
	if f then
		pcall(f, info)
	end
end

-- the theme of a new rift: even odds, each theme's weight raised by its attunement (weights = {[name] = percent});
-- without weights exactly one rand(1, #themes) as before
function R.pickTheme(cfg, rand, weights)
	local any = false
	for _, v in pairs(weights or {}) do
		if v > 0 then
			any = true
		end
	end
	if not any then
		return cfg.themes[rand(1, #cfg.themes)]
	end
	local rows = {}
	for _, th in ipairs(cfg.themes) do
		rows[#rows + 1] = {th, 100 + floor(weights[th.name] or 0)}
	end
	return weighted(rows, rand)
end

-- the run-shaping part of am on the effects of R.effects (before R.plan / R.newRun / R.startLives)
function R.applyAtlasFx(fx, am)
	if not am then
		return fx
	end
	fx.packMult = (fx.packMult or 1) * (1 + (am.density or 0) / 100)
	fx.elite = (fx.elite or 1) * (1 + (am.elite or 0) / 100)
	fx.timeMult = (fx.timeMult or 1) * (1 + (am.time or 0) / 100) * (am.timeMult or 1)
	fx.gilded = math.min(100, (fx.gilded or 0) + (am.goblin or 0))
	fx.coffer = math.min(100, (fx.coffer or 0) + (am.coffer or 0))
	fx.boss = (fx.boss or 1) * (am.guardianMult or 1)
	fx.atlasLives = am.lives or 0
	fx.oneLife = am.oneLife or nil
	return fx
end

-- the modifiers' reward bonuses (R.bonuses) x (1 + modReward / 100)
function R.atlasBonus(b, am)
	local m = am and am.modReward or 0
	if m <= 0 then
		return b
	end
	for k, v in pairs(b) do
		b[k] = floor(v * (1 + m / 100) + 0.5)
	end
	return b
end

-- one finisher's chest (R.reward) with the atlas: own = the finisher's own am (gold, orbs, item rolls), run = the key
-- user's am (the keystone's rewardMult and orbsMult, shared by every finisher). goldMult and rewardMult (Lone Ember,
-- Fleeting Sanctum, the world modifier) raise gold (rewardMult the item rolls too), never the orbs: only orbsMult
-- (Obsidian Crown) and the flat orb nodes change those. Changes and returns r.
function R.atlasReward(cfg, r, own, run, rand)
	if not own and not run then
		return r
	end
	local mult = 1 + (run and run.rewardMult or 0) / 100
	local orbs = run and run.orbsMult or 1
	own = own or {}
	r.gold = floor(r.gold * (1 + (own.goldMult or 0) / 100) * mult)
	r.chaos = roundChance((r.chaos + (own.chaos or 0)) * orbs, rand)
	r.divine = roundChance((r.divine + (own.divine or 0)) * orbs, rand)
	r.rolls = math.max(1, roundChance((r.rolls + (own.rolls or 0)) * mult, rand))
	return r
end

-- Omen Fragments of a chest x (1 + fragments / 100) (fractions a chance of one more)
function R.atlasFragments(n, am, rand)
	local f = am and am.fragments or 0
	if n <= 0 or f <= 0 then
		return n
	end
	return roundChance(n * (1 + f / 100), rand)
end

-- the HUD line of a run's atlas ("Atlas: Lone Ember, +12% packs, +1 life"), or nil; in `lang` (English without)
function R.atlasNote(am, lang)
	if not am then
		return nil
	end
	local parts = {}
	if am.keystone then
		parts[#parts + 1] = am.keystone
	end
	if (am.density or 0) > 0 then
		parts[#parts + 1] = T(lang, "+%s%% packs", floor(am.density))
	end
	if (am.time or 0) > 0 then
		parts[#parts + 1] = T(lang, "+%s%% time", floor(am.time))
	end
	if (am.lives or 0) > 0 then
		parts[#parts + 1] = am.lives == 1 and T(lang, "+%s life", am.lives) or T(lang, "+%s lives", am.lives)
	end
	if #parts == 0 then
		return nil
	end
	return T(lang, "Atlas: %s", table.concat(parts, ", "))
end

return R

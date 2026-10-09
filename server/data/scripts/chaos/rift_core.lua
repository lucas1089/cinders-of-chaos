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

-- indexes of cfg.mods a key of `tier` may still roll (not in `have` = {key = true})
local function modPool(cfg, tier, have)
	local pool = {}
	for i, def in ipairs(cfg.mods) do
		if R.modAllowed(def, tier) and not (have and have[def.key]) and R.modWeight(def) > 0 then
			pool[#pool + 1] = i
		end
	end
	return pool
end
R.modPool = modPool

-- draws up to `count` different indexes from pool (weighted, without replacement)
local function drawMods(cfg, pool, count, rand)
	local picked = {}
	for _ = 1, math.min(count, #pool) do
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

-- adds up to `count` new modifiers to key (the orbs of chaos_crafting.lua); returns the added ones. key.mods stays in
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
		if def and not seen[key] and #mods < max then
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
		boss = 1, fragile = 0}
	for _, m in ipairs(mods or {}) do
		local v = m.value
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

local function eliteTier(cfg, fx, tier, rand)
	local mult = fx.elite * (1 + cfg.elite.perTier * tier)
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

-- the run plan: {types, packs = {{room, name, count, elites = {tier or false, ...}}}, total, bossAt, boss}
-- rooms = list of room names the packs may use (open side rooms; "hub" gets at most one pack)
function R.plan(cfg, tier, fx, players, types, rooms, rand)
	players = math.max(1, players or 1)
	local plan = {types = types, packs = {}, total = 0}
	if #types == 0 then
		return plan
	end
	local count = cfg.packs.base + floor(tier / cfg.packs.perTiers) + cfg.packs.perExtraPlayer * (players - 1)
	if (fx.packMult or 1) ~= 1 then
		count = floor(count * fx.packMult + 0.5) -- Teeming
	end
	local areas = {}
	for _, r in ipairs(rooms) do
		areas[#areas + 1] = r
	end
	for i = 1, count do
		local room
		if i == 1 or #areas == 0 then
			room = "hub"
		else
			room = areas[(i - 2) % #areas + 1]
		end
		local size = rand(cfg.packs.size[1], cfg.packs.size[2]) + (fx.packBonus or 0)
		local name = types[rand(1, #types)].name
		local elites = {}
		for k = 1, size do
			elites[k] = eliteTier(cfg, fx, tier, rand) or false
		end
		local warband = (fx.warband or 0) > 0 and chance(fx.warband, rand)
		if warband then -- Warbands: every member at least rare, the first legendary
			for k = 1, size do
				if elites[k] ~= "legendary" then
					elites[k] = "rare"
				end
			end
			elites[1] = "legendary"
		end
		plan.packs[#plan.packs + 1] = {room = room, name = name, count = size, elites = elites, warband = warband or nil}
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

-- the Sealed Coffer's contents: {gold, chaos, divine, rolls, countMult, lootTier, rarityMult}
function R.cofferLoot(cfg, tier, bonus, rand)
	local t = R.tierInfo(cfg, tier)
	local q = 1 + (bonus and bonus.quantity or 0) / 100
	local scale = q * t.reward
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
function R.keyOdds(cfg, modCount)
	local k = cfg.keyDrop
	modCount = modCount or 0
	return {
		chance = math.min(k.max, k.base + k.perMod * modCount),
		nextTier = math.min(100, k.nextTier + k.nextPerMod * modCount)
	}
end

-- nil, or the new key {tier, mods}
function R.rollKeyDrop(cfg, tier, modCount, rand)
	local odds = R.keyOdds(cfg, modCount)
	if not chance(odds.chance, rand) then
		return nil
	end
	local up = chance(odds.nextTier, rand) and tier < cfg.maxTier
	return R.rollKey(cfg, up and tier + 1 or tier, rand, up)
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
	if not pos or pos.z ~= g.origin.z then
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

R.DIRS = {
	{name = "north", dx = 0, dy = -1},
	{name = "east", dx = 1, dy = 0},
	{name = "south", dx = 0, dy = 1},
	{name = "west", dx = -1, dy = 0}
}

-- layout of a slot, all rooms: {center, hub = rect, rooms = {name = {center, rect}}, doors = {name = {pos...}},
-- floor = {[key] = pos}, walls = {[key] = pos}, floorList, wallList}. rect = inner floor {x1, y1, x2, y2}.
function R.layout(cfg, slot)
	local c = R.slotCenter(cfg, slot)
	local rm = cfg.room
	local z = c.z
	local L = {center = c, rooms = {}, doors = {}, floor = {}, walls = {}, floorList = {}, wallList = {}}
	local function key(x, y)
		return x .. "," .. y
	end
	local function addFloor(x, y)
		local k = key(x, y)
		if not L.floor[k] then
			L.floor[k] = {x = x, y = y, z = z}
			L.floorList[#L.floorList + 1] = L.floor[k]
		end
	end
	local hi = rm.hubHalf - 1
	L.hub = {x1 = c.x - hi, y1 = c.y - hi, x2 = c.x + hi, y2 = c.y + hi}
	for x = L.hub.x1, L.hub.x2 do
		for y = L.hub.y1, L.hub.y2 do
			addFloor(x, y)
		end
	end
	local reach = rm.hubHalf + rm.corridor + 1 + rm.sideHalf -- hub centre -> side room centre
	for _, d in ipairs(R.DIRS) do
		local rc = {x = c.x + d.dx * reach, y = c.y + d.dy * reach, z = z}
		local si = rm.sideHalf - 1
		local rect = {x1 = rc.x - si, y1 = rc.y - si, x2 = rc.x + si, y2 = rc.y + si}
		L.rooms[d.name] = {center = rc, rect = rect}
		for x = rect.x1, rect.x2 do
			for y = rect.y1, rect.y2 do
				addFloor(x, y)
			end
		end
		-- corridor from the hub wall to the room wall (both included: the doorways)
		local door = {}
		for s = rm.hubHalf, rm.hubHalf + rm.corridor + 1 do
			for w = -rm.corridorHalf, rm.corridorHalf do
				local x = c.x + d.dx * s + (d.dx == 0 and w or 0)
				local y = c.y + d.dy * s + (d.dy == 0 and w or 0)
				addFloor(x, y)
				if s == rm.hubHalf then
					door[#door + 1] = {x = x, y = y, z = z}
				end
			end
		end
		L.doors[d.name] = door
	end
	-- walls: every non-floor tile next to a floor tile (8 neighbours)
	for _, p in ipairs(L.floorList) do
		for ox = -1, 1 do
			for oy = -1, 1 do
				local k = key(p.x + ox, p.y + oy)
				if not L.floor[k] and not L.walls[k] then
					L.walls[k] = {x = p.x + ox, y = p.y + oy, z = z}
					L.wallList[#L.wallList + 1] = L.walls[k]
				end
			end
		end
	end
	table.sort(L.wallList, function(a, b)
		return a.y == b.y and a.x < b.x or a.y < b.y
	end)
	L.start = {x = c.x, y = c.y + rm.hubHalf - 3, z = z} -- players arrive at the south part of the hub
	L.bossSpawn = {x = c.x, y = c.y, z = z}
	L.basins = {
		{x = L.hub.x1, y = L.hub.y1, z = z}, {x = L.hub.x2, y = L.hub.y1, z = z},
		{x = L.hub.x1, y = L.hub.y2, z = z}, {x = L.hub.x2, y = L.hub.y2, z = z}
	}
	return L
end

-- which side rooms a run opens: a list of names (rand picks 2-4 of them)
function R.pickRooms(cfg, rand)
	local names = {}
	for _, d in ipairs(R.DIRS) do
		names[#names + 1] = d.name
	end
	local n = rand(cfg.openRooms[1], cfg.openRooms[2])
	local open = {}
	for _ = 1, math.min(n, #names) do
		open[#open + 1] = table.remove(names, rand(1, #names))
	end
	table.sort(open)
	return open
end

-- ===================================================================== run state
-- run = R.newRun(cfg, now, total, bossAt[, fx]): {state = "running", startTime, deadline, limit, total, killed, bossAt,
-- boss = "waiting", guardians}. fx (R.effects): Waning Veil shortens the limit, Twin Guardians makes two guardians.
function R.newRun(cfg, now, total, bossAt, fx)
	local limit = math.max(60, floor(cfg.timeLimit * (fx and fx.timeMult or 1) + 0.5))
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

-- one finisher's guardian chest: {gold, chaos, divine, rolls, countMult, lootTier, rarityMult, uniqueRolls, uniqueFind}
function R.omenReward(cfg)
	local r = cfg.omen.reward
	return {gold = r.gold, chaos = r.chaos, divine = r.divine, rolls = r.rolls, countMult = 1, lootTier = "boss",
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

return R

-- Chaos loot layer ("loot customizado"): a second EventCallback.onDropLoot that post-processes the
-- corpse AFTER the stock data/scripts/eventcallbacks/monster/default_onDropLoot.lua.
--
--   1. extra loot rolls from the monster's own loot table by tier (magic x1, rare x2, legendary x3, boss x2)
--   2. gear quality: floor + bonus rarity per tier (the "rarity" attribute)
--   2b. item level and modifiers: every gear drop gets the item level of this kill (L.dropLevel: the monster's level,
--       its tier, boss, rift tier, Omen guardian, world boss; chaos_item_mods.lua M.sourceLevel); drops with a rarity
--       are rolled whole by ChaosCrafting.forgeDrop (tiers by item level, count by rarity, prefixes / suffixes)
--   3. currency / crafting drops (stock orbs 29856 / 29857 + configurable list)
--   3b. gems (data/lib/chaos_gems_config.lua drop) and, in step 2b, sockets on gear with a rarity (chaos_gems.lua)
--   3c. spell support runes (data/lib/chaos_supports_config.lua drop, scripts/chaos/supports.lua)
--   4. unique items from the global ChaosUniqueItems (contract in LOOT.md)
--   5. item find (player storage) multiplies the chances
--   6. ChaosLootRoll(monsterName, tier, kills): pure simulation for balance tuning
--
-- All numbers live in loot_config.lua. See LOOT.md. Not verified on a running server; the
-- engine APIs used (Game.createItemWithRarity, Container:addItemEx, Game.getSpectators,
-- MonsterType:getLoot, Monster:getMonsterLevel) are read from the base server sources.
--
-- Lua dialect: TFS 1.4.2 / LuaJIT (Lua 5.1 semantics).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end

-- always reloaded so that /reload scripts picks up edits; loot.lua reads the GLOBAL at runtime
-- (never a captured local), so another script may patch ChaosLootConfig.rateMult etc. later.
ChaosLootConfig = dofile("data/scripts/chaos/loot_config.lua")

ChaosLoot = {}
local L = ChaosLoot

local function cfg()
	return ChaosLootConfig
end

-- ---------------------------------------------------------------------------
-- the only random source of this file: randomFn(a, b) -> integer in [a, b]
-- ---------------------------------------------------------------------------
local randomFn = math.random

function L.setRandom(fn)
	randomFn = fn or math.random
end

local function rnd(a, b)
	return randomFn(a, b)
end

-- true with probability p percent (0..100, fractions allowed, resolution 1/10000 %)
local function pct(p)
	if not p or p <= 0 then
		return false
	end
	if p >= 100 then
		return true
	end
	return rnd(1, 1000000) <= p * 10000
end

-- same maths as global getLootRandom(): 0..MAX_LOOTCHANCE divided by the loot rate
local function lootRandom()
	local max = MAX_LOOTCHANCE or 100000
	local rate = 1
	if configManager and configKeys and configKeys.RATE_LOOT then
		local r = configManager.getNumber(configKeys.RATE_LOOT)
		if r and r > 0 then
			rate = r
		end
	end
	return rnd(0, max) / rate
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local TIERS = {normal = true, magic = true, rare = true, legendary = true, boss = true}

function L.normTier(tier)
	tier = type(tier) == "string" and tier:lower() or "normal"
	return TIERS[tier] and tier or "normal"
end

local function tierValue(tbl, tier, default)
	local v = tbl and tbl[tier]
	if v == nil then
		return default
	end
	return v
end

-- ctx = {tier=, monster=, player=, itemFind= (1 = none)}
local function rateMult(ctx)
	local r = cfg().rateMult
	if type(r) == "function" then
		local ok, v = pcall(r, ctx)
		r = ok and v or 1
	end
	r = tonumber(r) or 1
	if r ~= r or r < 0 then
		r = 0
	end
	-- every loot bonus multiplies into this one rate (events, store, rift quantity, Golden Hour, community, Marches,
	-- blessings, the guild perk wrapper): the product is capped here (loot_config.lua maxRate)
	local cap = tonumber(cfg().maxRate)
	if cap and r > cap then
		r = cap
	end
	return r
end
L.rateMult = rateMult

function L.itemFindMult(player)
	local c = cfg()
	if not player or not c.itemFindStorage then
		return 1
	end
	local ok, v = pcall(function() return player:getStorageValue(c.itemFindStorage) end)
	v = math.max(0, ok and tonumber(v) or 0)
	-- the Item Find modifier of the equipped items (item_mods.lua)
	v = v + (ChaosItemMods and ChaosItemMods.playerBonus and ChaosItemMods.playerBonus(player, "itemfind") or 0)
	-- the pet's Treasure Sense (pets.lua)
	v = v + (ChaosPets and ChaosPets.itemFind and ChaosPets.itemFind(player) or 0)
	-- the Self-Found loot bonus (season_modes.lua)
	v = v + (ChaosSeason and ChaosSeason.modesLootBonus and select(1, ChaosSeason.modesLootBonus(player)) or 0)
	if v <= 0 then
		return 1
	end
	if v > (c.itemFindMaxPercent or 300) then
		v = c.itemFindMaxPercent or 300
	end
	return 1 + v / 100
end

local function levelCountMult(level)
	for _, row in ipairs(cfg().levelCountMult or {}) do
		if level >= row[1] and level <= row[2] then
			return row[3]
		end
	end
	return 1
end

local function itemName(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	if ok and name and name ~= "" then
		return name
	end
	return "item " .. tostring(id)
end

local function rarityName(r)
	local names = cfg().gear.names
	return names and names[r] or ("Rarity " .. tostring(r))
end

local function uniqueSet()
	local set = {}
	for _, e in ipairs(L.uniqueList()) do
		set[e.id] = true
	end
	return set
end

-- ---------------------------------------------------------------------------
-- gear detection (same relevance test as the stock hasRelevantStats, minus ammo / stackables /
-- containers / excluded ids)
-- ---------------------------------------------------------------------------
local SKILL_NAMES = {"fist", "club", "sword", "axe", "distance", "shield", "magic", "mining", "crafting",
	"woodcutting", "herbalist", "armorsmith", "weaponsmith", "jewelsmith"}
local SPECIALS = {"criticalHitChance", "criticalHitAmount", "manaLeechChance", "manaLeechAmount",
	"lifeLeechChance", "lifeLeechAmount"}

local function skillIdOf(name)
	local map = {club = SKILL_CLUB, sword = SKILL_SWORD, axe = SKILL_AXE, mining = SKILL_MINING,
		crafting = SKILL_CRAFTING, woodcutting = SKILL_WOODCUTTING, herbalist = SKILL_HERBALIST,
		armorsmith = SKILL_ARMORSMITH, weaponsmith = SKILL_WEAPONSMITH, jewelsmith = SKILL_JEWELSMITH}
	if map[name] then
		return map[name]
	elseif name:sub(1, 4) == "dist" then
		return SKILL_DISTANCE
	elseif name:sub(1, 6) == "shield" then
		return SKILL_SHIELD
	elseif name:sub(1, 4) == "fist" then
		return SKILL_FIST
	elseif name:sub(1, 1) == "m" then
		return SKILL_MAGLEVEL
	end
	return nil
end

local function relevantType(itType)
	if itType:getAttack() > 0 or itType:getDefense() > 0 or itType:getArmor() > 0 or itType:getHitChance() > 0 then
		return true
	end
	local abilities = itType:getAbilities()
	if abilities then
		if abilities.absorbPercent then
			for _, percent in pairs(abilities.absorbPercent) do
				if percent > 0 then
					return true
				end
			end
		end
		if abilities.skills then
			for _, name in ipairs(SKILL_NAMES) do
				local sid = skillIdOf(name)
				local v = sid and abilities.skills[sid]
				if v and v > 0 then
					return true
				end
			end
		end
		if abilities.specialSkills then
			for _, name in ipairs(SPECIALS) do
				if abilities.specialSkills[name] and abilities.specialSkills[name] > 0 then
					return true
				end
			end
		end
	end
	return false
end

-- true when item id `id` may receive a rarity from this layer
function L.isGearId(id)
	local c = cfg()
	if c.gear.excludedItems[id] then
		return false
	end
	if L.protectedIds and L.protectedIds[id] then
		return false
	end
	if type(ItemType) ~= "function" and type(ItemType) ~= "table" then
		return c.sim.fallbackGear[id] == true
	end
	local ok, res = pcall(function()
		local t = ItemType(id)
		if not t or t:getId() == 0 then
			return false
		end
		if t:isContainer() or t:isStackable() or t:getAmmoType() ~= 0 then
			return false
		end
		-- a quiver (data/lib/chaos_archery_core.lua): its stats are implicit modifiers, not item type values
		if ChaosItemMods and ChaosItemMods.kindOfType and ChaosItemMods.kindOfType(t) == "quiver" then
			return true
		end
		return relevantType(t)
	end)
	return ok and res or false
end

function L.isStackableId(id)
	local ok, res = pcall(function() return ItemType(id):isStackable() end)
	if ok then
		return res
	end
	return true
end

-- ---------------------------------------------------------------------------
-- rarity maths
-- ---------------------------------------------------------------------------
-- port of the stock rollRarity (so extra gear is comparable and the simulation can mimic stock)
function L.stockRarity()
	local g = cfg().gear
	if rnd(1, 100) > g.stockRollChance then
		return 0
	end
	for id, chance in ipairs(g.stockChances) do
		if rnd(1, 100) <= chance then
			return id
		end
	end
	return 0
end

local function weightedPick(rows) -- rows = {{value, weight}, ...}
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rnd(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end

-- returns the new rarity (>= current, <= maxRarity). itemFind scales the bonus chance.
function L.upgradeRarity(tier, current, itemFind)
	local g = cfg().gear
	tier = L.normTier(tier)
	current = tonumber(current) or 0
	local target = current
	local floor = tierValue(g.minRarity, tier, 0)
	if floor > 0 and pct(tierValue(g.ensureChance, tier, 0)) and target < floor then
		target = floor
	end
	local bonus = tierValue(g.bonusChance, tier, 0) * (itemFind or 1)
	if bonus > 0 and pct(bonus) then
		target = target + (weightedPick(g.bonusSteps) or 0)
	end
	if target > g.maxRarity then
		target = g.maxRarity
	end
	if target < current then
		target = current
	end
	return target
end

-- ---------------------------------------------------------------------------
-- 1. extra loot rolls. lootTable = MonsterType:getLoot() style list.
-- returns list of {itemId=, count=}
-- ---------------------------------------------------------------------------
function L.rollExtraLoot(lootTable, tier, ctx)
	local c = cfg()
	tier = L.normTier(tier)
	ctx = ctx or {}
	local out = {}
	local rolls = tierValue(c.extraRolls, tier, 0)
	-- loot events and the store's World Loot buff add one extra roll to every monster, normal ones included
	-- (not for season characters: ctx.player, the corpse owner)
	local buff = ChaosShopServices and ChaosShopServices.buffMult and ChaosShopServices.buffMult("loot", ctx.player) or 1
	if (ChaosEvents and ChaosEvents.bonus("loot") > 1) or buff > 1 then
		rolls = rolls + 1
	end
	if rolls <= 0 or not lootTable then
		return out
	end
	local rm = rateMult(ctx)
	local find = ctx.itemFind or 1
	-- pack combat (pace.lua): x the monster's loot factor, outside the maxRate cap
	local chanceMult = tierValue(c.extraChanceMult, tier, 1) * rm * find * (tonumber(ctx.pace) or 1)
	-- the rate scales how often an extra roll hits, not its stack size (rate x count would square the bonus)
	local countMult = tierValue(c.extraCountMult, tier, 1) * levelCountMult(ctx.level or 0)
	for _ = 1, rolls do
		for _, entry in ipairs(lootTable) do
			local id = entry.itemId
			local threshold = (entry.chance or 0) * chanceMult
			if id and threshold > 0 and not (c.extraSkipItems and c.extraSkipItems[id]) and lootRandom() <= threshold then
				local minC = entry.minCount or 1
				local maxC = entry.maxCount or entry.count or 1
				if maxC < minC then
					maxC = minC
				end
				local n = math.floor(rnd(minC, maxC) * countMult)
				if n < 1 then
					n = 1
				end
				if not L.isStackableId(id) then
					n = 1
				end
				out[#out + 1] = {itemId = id, count = n}
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- 3. currency
-- returns list of {id=, count=, name=} (merged by id)
-- ---------------------------------------------------------------------------
function L.rollCurrency(tier, ctx)
	local cur = cfg().currency
	tier = L.normTier(tier)
	ctx = ctx or {}
	local scale = rateMult(ctx) * (ctx.itemFind or 1) * (ctx.orbFind or 1) -- orbFind: charms.lua
	-- the Ember of the Forge blessing of the corpse owner (blessings.lua): every orb of the list more often
	scale = scale * (ChaosBlessings and ChaosBlessings.mult and ChaosBlessings.mult(ctx.player, "orb") or 1)
	-- rate, item find, orb find and the Forge together: capped (loot_config.lua currency.maxScale)
	local maxScale = tonumber(cur.maxScale)
	if maxScale and scale > maxScale then
		scale = maxScale
	end
	-- pack combat (pace.lua): x the monster's loot factor, outside the cap
	scale = scale * (tonumber(ctx.pace) or 1)
	local cm = tierValue(cur.countMult, tier, 1)
	local merged, order = {}, {}
	local function add(e)
		local n = math.floor(rnd(e.count[1], e.count[2]) * cm)
		if n < 1 then
			n = 1
		end
		if merged[e.id] then
			merged[e.id].count = merged[e.id].count + n
		else
			merged[e.id] = {id = e.id, count = n, name = e.name or itemName(e.id)}
			order[#order + 1] = e.id
		end
	end
	for _, e in ipairs(cur.entries) do
		local chance = tierValue(e.chance, tier, 0)
		if chance > 0 and rnd(1, 1000000) <= chance * scale * 100 then
			add(e)
		end
	end
	local g = tierValue(cur.guaranteed, tier, 0)
	if g > 0 then
		local rows = {}
		for _, e in ipairs(cur.entries) do
			rows[#rows + 1] = {e, e.weight or 1}
		end
		for _ = 1, g do
			local e = weightedPick(rows)
			if e then
				add(e)
			end
		end
	end
	local out = {}
	for _, id in ipairs(order) do
		out[#out + 1] = merged[id]
	end
	return out
end

-- ---------------------------------------------------------------------------
-- 4. unique items
-- ---------------------------------------------------------------------------
-- flat, name-sorted list of valid entries from ChaosUniqueItems (array or name-keyed map)
function L.uniqueList(source)
	source = source or ChaosUniqueItems
	local list = {}
	if type(source) ~= "table" then
		return list
	end
	for k, e in pairs(source) do
		if type(e) == "table" and tonumber(e.id) and tonumber(e.id) > 0 then
			list[#list + 1] = {
				name = e.name or (type(k) == "string" and k) or ("item " .. tostring(e.id)),
				id = tonumber(e.id),
				minTier = L.normTier(e.minTier or (e.tiers and e.tiers[1]) or "normal"),
				chance = tonumber(e.chance) or 0,
				monsters = e.monsters,
				bossOnly = e.bossOnly and true or false,
				level = e.level,
				minMonsterLevel = e.minMonsterLevel,
				season = e.season -- season uniques (season.lua)
			}
		end
	end
	table.sort(list, function(a, b)
		if a.name == b.name then
			return a.id < b.id
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return list
end

local function monsterListed(monsters, name)
	if type(monsters) ~= "table" then
		return true
	end
	if next(monsters) == nil then
		return true
	end
	name = tostring(name):lower()
	for _, m in pairs(monsters) do
		if tostring(m):lower() == name then
			return true
		end
	end
	return false
end

-- returns list of unique entries that dropped (at most unique.maxPerKill, random among the hits)
-- owner (optional): the Player the drop is for; season uniques only drop for that season's characters (season.lua)
function L.rollUniques(tier, monsterName, monsterLevel, itemFind, source, owner)
	local u = cfg().unique
	tier = L.normTier(tier)
	local mult = tierValue(u.tierMult, tier, 0)
	local rank = tierValue(u.tierRank, tier, 0)
	local hits = {}
	if mult <= 0 then
		return hits
	end
	for _, e in ipairs(L.uniqueList(source)) do
		local ok = rank >= tierValue(u.tierRank, e.minTier, 0)
		if ok and e.bossOnly and tier ~= "boss" then
			ok = false
		end
		if ok and not monsterListed(e.monsters, monsterName) then
			ok = false
		end
		if ok and e.minMonsterLevel and (monsterLevel or 0) < e.minMonsterLevel then
			ok = false
		end
		if ok and e.season and ChaosSeason and ChaosSeason.uniqueBlocked and ChaosSeason.uniqueBlocked(e.season, owner) then
			ok = false
		end
		if ok then
			local chance = e.chance * mult * (itemFind or 1)
			if chance > u.maxChance then
				chance = u.maxChance
			end
			if chance > 0 and rnd(1, 1000000) <= chance * 100 then
				hits[#hits + 1] = e
			end
		end
	end
	local max = u.maxPerKill or 1
	while #hits > max do
		table.remove(hits, rnd(1, #hits))
	end
	return hits
end

-- ---------------------------------------------------------------------------
-- 6. simulation (no corpse, no engine objects): ChaosLootRoll(monsterName, tier, kills [, opts])
-- opts = {lootTable=, level=, itemFind=, uniques=, rand=function(a,b)}
-- returns {monster, tier, kills, items={[id]=n}, gear=N, rarity={[0..15]=n}, upgraded=N,
--          extraItems=N, currency={[id]=n}, uniques={[name]=n}}
-- ---------------------------------------------------------------------------
local function lootTableOf(monsterName)
	local ok, res = pcall(function()
		local mt = MonsterType(monsterName)
		return mt and mt:getLoot()
	end)
	if ok and type(res) == "table" and #res > 0 then
		return res
	end
	return cfg().sim.fallbackLoot
end

function L.simulate(monsterName, tier, kills, opts)
	opts = opts or {}
	local c = cfg()
	tier = L.normTier(tier)
	kills = math.floor(tonumber(kills) or 1000)
	if kills < 1 then
		kills = 1
	end
	if kills > c.sim.maxKills then
		kills = c.sim.maxKills
	end
	local savedRandom = randomFn
	if opts.rand then
		randomFn = opts.rand
	end
	local lootTable = opts.lootTable or lootTableOf(monsterName)
	local ctx = {tier = tier, level = opts.level or 0, itemFind = opts.itemFind or 1}
	local res = {monster = monsterName, tier = tier, kills = kills, items = {}, gear = 0, rarity = {},
		upgraded = 0, extraItems = 0, currency = {}, uniques = {}}
	for r = 0, c.gear.maxRarity do
		res.rarity[r] = 0
	end
	local ok, err = pcall(function()
		for _ = 1, kills do
			local drops = {} -- {id, rarity}
			for _, entry in ipairs(lootTable) do
				if entry.itemId and lootRandom() <= entry.chance then
					local r = 0
					if L.isGearId(entry.itemId) then
						r = L.stockRarity()
					end
					drops[#drops + 1] = {id = entry.itemId, rarity = r}
				end
			end
			for _, ex in ipairs(L.rollExtraLoot(lootTable, tier, ctx)) do
				local r = 0
				if L.isGearId(ex.itemId) then
					r = L.stockRarity()
				end
				drops[#drops + 1] = {id = ex.itemId, rarity = r, count = ex.count}
				res.extraItems = res.extraItems + 1
			end
			for _, d in ipairs(drops) do
				if L.isGearId(d.id) then
					local nr = L.upgradeRarity(tier, d.rarity, ctx.itemFind)
					if nr > d.rarity then
						res.upgraded = res.upgraded + 1
					end
					res.gear = res.gear + 1
					res.rarity[nr] = res.rarity[nr] + 1
				end
				res.items[d.id] = (res.items[d.id] or 0) + (d.count or 1)
			end
			for _, cdrop in ipairs(L.rollCurrency(tier, ctx)) do
				res.currency[cdrop.id] = (res.currency[cdrop.id] or 0) + cdrop.count
			end
			for _, e in ipairs(L.rollUniques(tier, monsterName, ctx.level, ctx.itemFind, opts.uniques)) do
				res.uniques[e.name] = (res.uniques[e.name] or 0) + 1
			end
		end
	end)
	randomFn = savedRandom
	if not ok then
		error(err, 0)
	end
	return res
end

function L.formatSim(res)
	local lines = {string.format("ChaosLootRoll %s [%s] x%d: gear %d (upgraded %d), extra items %d",
		res.monster, res.tier, res.kills, res.gear, res.upgraded, res.extraItems)}
	local parts = {}
	for r = 0, #res.rarity do
		if res.rarity[r] and res.rarity[r] > 0 then
			parts[#parts + 1] = string.format("%s=%d", r == 0 and "none" or rarityName(r), res.rarity[r])
		end
	end
	lines[#lines + 1] = "rarity: " .. (#parts > 0 and table.concat(parts, ", ") or "-")
	parts = {}
	for id, n in pairs(res.currency) do
		parts[#parts + 1] = string.format("%s=%d", itemName(id), n)
	end
	table.sort(parts)
	lines[#lines + 1] = "currency: " .. (#parts > 0 and table.concat(parts, ", ") or "-")
	parts = {}
	for name, n in pairs(res.uniques) do
		parts[#parts + 1] = string.format("%s=%d", name, n)
	end
	table.sort(parts)
	lines[#lines + 1] = "uniques: " .. (#parts > 0 and table.concat(parts, ", ") or "-")
	return table.concat(lines, "\n")
end

-- global entry points for an admin action
function ChaosLootRoll(monsterName, tier, kills, opts)
	return L.simulate(monsterName, tier, kills, opts)
end

function ChaosLootReport(monsterName, tier, kills, opts)
	return L.formatSim(L.simulate(monsterName, tier, kills, opts))
end

-- ---------------------------------------------------------------------------
-- engine glue
-- ---------------------------------------------------------------------------
local function globalByName(name, default)
	local v = name and _G[name]
	if v == nil then
		return default
	end
	return v
end

local function spectatorsOf(pos, multifloor, rx, ry)
	local ok, list = pcall(function() return Game.getSpectators(pos, multifloor, true, rx, rx, ry, ry) end)
	if ok and type(list) == "table" then
		return list
	end
	return {}
end

local function tierOfMonster(monster)
	local info = ChaosTierDead and ChaosTierDead[monster:getId()]
	if info and info.tier then
		return L.normTier(info.tier)
	end
	if type(ChaosTierOf) == "function" then
		local ok, t = pcall(ChaosTierOf, monster)
		if ok then
			return L.normTier(t)
		end
	end
	return "normal"
end

local function itemRarityOf(item)
	local ok, r = pcall(function() return item:getCustomAttribute("rarity") end)
	return ok and tonumber(r) or 0
end

-- true once the engine rolled the rarity stats (Item::applyRarityEffects / the Monster::dropLoot pass set it)
function L.isRolled(item)
	local ok, v = pcall(function() return item:getCustomAttribute("combatPowerLevel") end)
	return ok and v ~= nil
end

-- For an item about to leave a corpse before the engine's rarity pass (autoloot, the loot pouch, the Rarity Autoloot).
-- A drop the loot layer forged keeps its rarity as text until a tick later (ChaosCrafting.shield): it gets the number
-- back now. An item with a rarity nobody rolled yet (a corpse the layer skipped) is forged here, in place, at the item
-- level it carries (or its type's). Returns the item to move (always the item itself now; callers keep the return).
function L.finalizeRarity(item)
	local C = ChaosCrafting
	if not C then
		return item
	end
	if C.unshield(item) then
		return item
	end
	local r = itemRarityOf(item)
	if r <= 0 or L.isRolled(item) or not L.isGearId(item:getId()) then
		return item
	end
	C.forge(item, r, C.orbLevel(item))
	return item
end

-- ---------------------------------------------------------------------------
-- item level of a kill's drops
-- ---------------------------------------------------------------------------
local poolLevels
local function poolLevel(name)
	if not poolLevels then
		poolLevels = {}
		local ok, pool = pcall(dofile, "data/scripts/chaos/bounty_pool.lua")
		if ok and type(pool) == "table" then
			for _, list in ipairs({pool.hunt or {}, pool.bosses or {}}) do
				for _, e in ipairs(list) do
					poolLevels[tostring(e.name):lower()] = tonumber(e.level)
				end
			end
		end
	end
	return poolLevels[tostring(name):lower()]
end

-- the monster's level: Monster:getMonsterLevel (level-scaled monsters), else its hunting level from bounty_pool.lua,
-- else the same estimate from its experience and health
function L.monsterLevel(monster)
	local ok, lvl = pcall(function() return monster:getMonsterLevel() end)
	if ok and tonumber(lvl) and tonumber(lvl) > 0 then
		return tonumber(lvl)
	end
	local okN, name = pcall(function() return typeNameOf(monster) end)
	local pl = okN and poolLevel(name)
	if pl and pl > 0 then
		return pl
	end
	local mt = monster:getType()
	local okE, exp = pcall(function() return mt:getExperience() end)
	local okH, hp = pcall(function() return mt:getMaxHealth() end)
	return ChaosItemMods.estimateMonsterLevel(okE and exp or 0, okH and hp or 0)
end

-- the item level of this kill's drops (owner = the corpse owner; inside a rift / Omen arena its run counts)
function L.dropLevel(monster, owner, tier)
	local M = ChaosItemMods
	if not M then
		return 0
	end
	local src = {monsterLevel = L.monsterLevel(monster), tier = tier}
	local mt = monster:getType()
	local okB, boss = pcall(function() return mt and mt:isBoss() end)
	if okB and boss then
		src.tier = "boss"
	end
	local run = owner and ChaosRift and ChaosRift.runOf and ChaosRift.runOf[owner:getId()]
	if run and run.key then
		src.riftTier = run.key.tier
		src.omen = run.omen ~= nil
	end
	local wb = ChaosWorldBoss and ChaosWorldBoss.state
	if wb and wb.bossId and wb.bossId == monster:getId() then
		src.worldBoss = true
	end
	return M.sourceLevel(src)
end

local function announce(owner, corpsePos, text, nearMessage)
	local u = cfg().unique
	local msgType = globalByName(u.messageType, MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR)
	local near, seen = spectatorsOf(corpsePos, false, u.viewRangeX, u.viewRangeY), {}
	for _, p in ipairs(near) do
		seen[p:getId()] = true
		p:sendTextMessage(msgType, nearMessage or text)
	end
	if owner and not seen[owner:getId()] then
		owner:sendTextMessage(msgType, nearMessage or text)
		seen[owner:getId()] = true
	end
	for _, p in ipairs(spectatorsOf(corpsePos, true, u.broadcastRangeX, u.broadcastRangeY)) do
		if not seen[p:getId()] then
			p:sendTextMessage(msgType, text)
		end
	end
end

local function processKill(monster, corpse)
	local c = cfg()
	if configManager and configKeys and configManager.getNumber(configKeys.RATE_LOOT) == 0 then
		return
	end
	local owner = Player(corpse:getCorpseOwner())
	if not owner then
		return
	end
	if owner:getStamina() <= c.minStamina then
		return
	end

	local tier = tierOfMonster(monster)
	local mType = monster:getType()
	local level = 0
	local okLevel, lvl = pcall(function() return monster:getMonsterLevel() end)
	if okLevel and tonumber(lvl) then
		level = tonumber(lvl)
	end
	-- pack combat (pace.lua): loot per kill x the monster's loot factor (1 when it is not paced)
	local pace = ChaosPace and ChaosPace.lootMultOf and ChaosPace.lootMultOf(monster) or 1
	local ctx = {tier = tier, monster = monster, player = owner, level = level, itemFind = L.itemFindMult(owner),
		pace = pace}
	-- the Orb Find of the placed charms (charms.lua): the currency chances only
	ctx.orbFind = ChaosCharms and ChaosCharms.orbFindMult and ChaosCharms.orbFindMult(owner) or 1
	local bonus = {} -- text pieces for the bonus-loot message
	local corpsePos = corpse:getPosition()

	-- items that must never be touched: unique items
	-- uniques are ordinary base items until ChaosMakeUnique runs on the dropped copy (step 4, after the gear
	-- upgrades), so stock copies of the same base ids may still be upgraded
	L.protectedIds = {}

	-- 0. no arrows or bolts any more (bows fire without them: data/lib/chaos_archery_core.lua). The install tool takes
	-- them out of the base loot tables; a loot table it could not read still drops none.
	local A = ChaosArchery
	local function isAmmo(id)
		return A ~= nil and A.isAmmoId(id, ItemType and ItemType(id) or nil)
	end
	if A then
		for slot = corpse:getSize() - 1, 0, -1 do
			local item = corpse:getItem(slot)
			if item and isAmmo(item:getId()) then
				item:remove()
			end
		end
	end

	-- 0b. pack combat (pace.lua): the stock loot thinned by the loot factor. A stack keeps count x factor rounded at
	-- random (gold included); any other item stays with chance = factor. The expected value per hour stays.
	if pace < 1 then
		L.thinCorpse(corpse, pace)
	end

	-- 1. extra rolls
	local lootTable = mType and mType:getLoot()
	for _, drop in ipairs(L.rollExtraLoot(lootTable, tier, ctx)) do
		local item = not isAmmo(drop.itemId) and corpse:addItem(drop.itemId, drop.count) or nil
		if item then
			if L.isGearId(drop.itemId) then
				local r = L.stockRarity()
				if r > 0 then
					item:setCustomAttribute("rarity", r)
				end
			end
			bonus[#bonus + 1] = (drop.count > 1 and (drop.count .. "x ") or "") .. itemName(drop.itemId)
		end
	end

	-- 2. gear quality over everything in the corpse
	local items = {}
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item and item:isItem() then
			items[#items + 1] = item
		end
	end
	local noError = RETURNVALUE_NOERROR or 0
	-- the Rarity Find modifier of the equipped items (item_mods.lua) raises the bonus rarity chance
	local rarityFind = ChaosItemMods and ChaosItemMods.playerBonus and ChaosItemMods.playerBonus(owner, "rarityfind") or 0
	-- and the Self-Found loot bonus (season_modes.lua)
	rarityFind = rarityFind + (ChaosSeason and ChaosSeason.modesLootBonus and select(2, ChaosSeason.modesLootBonus(owner)) or 0)
	-- and the Ember of Fortune blessing (blessings.lua)
	rarityFind = rarityFind + (ChaosBlessings and ChaosBlessings.value and ChaosBlessings.value(owner, "rarity") or 0)
	-- Only the "rarity" attribute is raised here, as the stock callback sets it: the engine rolls the stats of every
	-- item that still carries one in the corpse after all onDropLoot callbacks (Monster::dropLoot), once. Rolling here
	-- too (Game.createItemWithRarity) gave corpse items two sets of stats. Items that leave the corpse before the
	-- engine pass (autoloot, the loot pouch) are rolled on the way out: L.finalizeRarity.
	for _, item in ipairs(items) do
		local id = item:getId()
		if L.isGearId(id) and not L.isRolled(item) then
			local current = itemRarityOf(item)
			local target = L.upgradeRarity(tier, current, ctx.itemFind * (1 + rarityFind / 100))
			if target > current then
				item:setCustomAttribute("rarity", target)
				bonus[#bonus + 1] = string.format("[%s] %s", rarityName(target), itemName(id))
				local from = c.announceRarityFrom or 0
				if from > 0 and target >= from then
					announce(owner, corpsePos,
						string.format("%s found a [%s] %s!", owner:getName(), rarityName(target), itemName(id)))
				end
			end
		end
	end

	-- 2b. item level and modifiers (data/lib/chaos_crafting.lua forgeDrop): every gear drop gets this kill's item
	-- level; one with a rarity gets sockets (data/lib/chaos_gems.lua: 0-3 by rarity) and its whole roll now, the
	-- rarity kept as text through the engine's own pass (ChaosItemMods.afterDrop makes it a number a tick later)
	if ChaosCrafting and ChaosCrafting.forgeDrop then
		local ilvl = L.dropLevel(monster, owner, tier)
		local forged = false
		for slot = 0, corpse:getSize() - 1 do
			local item = corpse:getItem(slot)
			if item and (L.isGearId(item:getId()) or ChaosCrafting.isGear(item)) and not L.isRolled(item) then
				if itemRarityOf(item) > 0 then
					if ChaosGems then
						ChaosGems.rollDropSockets(item)
					end
					forged = #ChaosCrafting.forgeDrop(item, ilvl) >= 0 or forged
				else
					ChaosCrafting.forgeDrop(item, ilvl)
				end
			end
		end
		if forged and ChaosItemMods.afterDrop then
			ChaosItemMods.afterDrop(corpse)
		end
	end
	-- 2c. veiled modifiers and the Orb of Unveiling (veiled.lua): kills in high content only
	if ChaosVeiled and ChaosVeiled.onCorpse then
		for _, text in ipairs(ChaosVeiled.onCorpse(corpse, monster, owner, tier)) do
			bonus[#bonus + 1] = text
		end
	end

	-- 3. currency
	for _, drop in ipairs(L.rollCurrency(tier, ctx)) do
		local item = corpse:addItem(drop.id, drop.count)
		if item then
			bonus[#bonus + 1] = (drop.count > 1 and (drop.count .. "x ") or "") .. drop.name
		end
	end

	-- 3b. gems (data/lib/chaos_gems_config.lua drop): chance by monster tier x the layer's rate x item find, the tier
	-- by the monster's level (the killer's when the monster has none)
	if ChaosGems then
		local gemLevel = level > 0 and level or owner:getLevel()
		for _, id in ipairs(ChaosGems.rollDrop(tier, gemLevel, rateMult(ctx) * ctx.itemFind * pace, rnd)) do
			local item = corpse:addItem(id, 1)
			if item then
				bonus[#bonus + 1] = ChaosGems.gemName(id)
			end
		end
	end
	-- 3c. spell support runes (data/lib/chaos_supports_config.lua drop; supports.lua): like the gems
	if ChaosSupports and ChaosSupports.lootDrop then
		for _, name in ipairs(ChaosSupports.lootDrop(corpse, tier, level > 0 and level or owner:getLevel(),
				rateMult(ctx) * ctx.itemFind * pace, rnd)) do
			bonus[#bonus + 1] = name
		end
	end

	-- 4. uniques
	local u = c.unique
	for _, e in ipairs(L.rollUniques(tier, typeNameOf(monster), level, ctx.itemFind * pace, nil, owner)) do
		local item = corpse:addItem(e.id, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			bonus[#bonus + 1] = "{" .. e.name .. "}"
			local effect = globalByName(u.effect, u.fallbackEffect)
			corpsePos:sendMagicEffect(effect)
			announce(owner, corpsePos,
				string.format(u.broadcastText, owner:getName(), e.name),
				string.format(u.message, Chaos.monsterNameDescription(monster), e.name))
		end
	end

	if #bonus > 0 then
		local text = ("Chaos bonus loot of %s: %s"):format(Chaos.monsterNameDescription(monster), table.concat(bonus, ", "))
		local party = owner:getParty()
		if party then
			party:broadcastPartyLoot(text)
		else
			owner:sendTextMessage(MESSAGE_LOOT, text)
		end
	end
end

L.processKill = processKill

-- pack combat (pace.lua): thin the top-level items of a corpse by factor f (pace_core.lua P.thinPlan); returns the
-- number of items removed or reduced
function L.thinCorpse(corpse, f)
	local P = ChaosPaceCore
	if not P or not corpse or f >= 1 then
		return 0
	end
	local items, list = {}, {}
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item then
			list[#list + 1] = item
			items[#items + 1] = {count = item:getCount(), stackable = L.isStackableId(item:getId())}
		end
	end
	local plan = P.thinPlan(items, f, function() return rnd(0, 999999) / 1000000 end)
	local changed = 0
	for i, item in ipairs(list) do
		local keep = plan[i]
		if keep <= 0 then
			item:remove()
			changed = changed + 1
		elseif keep < items[i].count then
			item:remove(items[i].count - keep)
			changed = changed + 1
		end
	end
	return changed
end

-- pack combat: an empty corpse decays after ChaosPaceConfig.emptyCorpseSeconds (more kills leave more corpses)
local function shortenEmptyCorpse(corpse)
	local secs = ChaosPaceConfig and ChaosPaceConfig.enabled ~= false and tonumber(ChaosPaceConfig.emptyCorpseSeconds) or 0
	if secs <= 0 or not corpse or corpse:getSize() > 0 or not ITEM_ATTRIBUTE_DURATION then
		return
	end
	pcall(function()
		corpse:setAttribute(ITEM_ATTRIBUTE_DURATION, secs * 1000)
		corpse:decay()
	end)
end
L.shortenEmptyCorpse = shortenEmptyCorpse

local ec = EventCallback
ec.onDropLoot = function(self, corpse)
	local ok, err = pcall(processKill, self, corpse)
	if not ok then
		print("[Chaos loot] onDropLoot failed: " .. tostring(err))
	end
	if ChaosPace and ChaosPace.isPaced and ChaosPace.isPaced(self) then
		shortenEmptyCorpse(corpse)
	end
end
ec:register(cfg().priority or 1)

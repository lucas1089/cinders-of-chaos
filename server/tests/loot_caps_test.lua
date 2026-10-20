-- Run from the server/ folder: luajit tests/loot_caps_test.lua (and lua5.3; CI runs both)
-- The caps of the Chaos loot layer (loot.lua, loot_config.lua): the final loot rate (every bonus multiplied, the
-- guild perk wrapper included) is capped at maxRate, the rate scales the chance of an extra roll but not its stack
-- count, and the currency chance scale (rate x item find x orb find x Ember of the Forge) is capped at
-- currency.maxScale.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, what)
	ok(math.abs(a - b) < 1e-9, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- engine mock
Chaos = {}
MAX_LOOTCHANCE = 100000
local registered, dropSteps = nil, {}
EventCallback = setmetatable({register = function(self, index)
	registered = registered or index
	dropSteps[#dropSteps + 1] = {index = index, fn = self.onDropLoot}
end}, {__newindex = rawset})
function ItemType(id)
	return {isStackable = function() return id ~= 2400 end, getName = function() return "item " .. id end}
end

dofile("data/scripts/chaos/loot.lua")
local L, C = ChaosLoot, ChaosLootConfig
ok(registered == C.priority, "the drop callback is registered")
near(C.maxRate, 3.0, "default rate cap")
near(C.currency.maxScale, 3.0, "default currency cap")

-- every bonus at once (the audit's stack): event 1.5, World Loot 1.25, rift 2.28, Golden Hour 1.25, community 1.10 x
-- 1.30, Marches 1.5, shrine 1.1, Ember of Plenty 1.4
ChaosEvents = {bonus = function(kind) return kind == "loot" and 1.5 or 1 end}
ChaosShopServices = {buffMult = function() return 1.25 end}
ChaosRift = {lootMult = function() return 2.28 end}
ChaosWorldEvents = {lootMult = function() return 1.25 end}
ChaosCommunity = {lootMult = function() return 1.10 * 1.30 end}
ChaosPvpZone = {lootMult = function() return 1.5 * 1.1 end}
ChaosBlessings = {mult = function(_, kind) return (kind == "loot" and 1.4) or (kind == "orb" and 1.5) or 1 end}
local raw = C.rateMult({})
ok(raw > 9, "uncapped product is ~10x: " .. raw)
near(L.rateMult({}), 3.0, "the rate is capped")

-- the guild perk wraps rateMult (guild.lua G.wrapLoot): still under the cap
local inner = C.rateMult
C.rateMult = function(ctx) return inner(ctx) * 1.05 end
near(L.rateMult({}), 3.0, "the guild wrapper is capped too")
C.rateMult = 2
near(L.rateMult({}), 2, "below the cap: unchanged")
C.rateMult = -1
near(L.rateMult({}), 0, "negative: 0")
C.rateMult = function() error("boom") end
near(L.rateMult({}), 1, "a failing hook: 1")
C.rateMult = 50
C.maxRate = nil
near(L.rateMult({}), 50, "no cap configured: the raw rate")
C.maxRate = 3.0

-- extra rolls: the stack count does not grow with the rate
ChaosEvents, ChaosShopServices = nil, nil
local function roll(rate)
	C.rateMult = rate
	-- rnd(a, b) -> b: the count is the maximum, lootRandom() is MAX_LOOTCHANCE (needs threshold >= 100000)
	L.setRandom(function(a, b) return b end)
	return L.rollExtraLoot({{itemId = 2160, chance = 100000, minCount = 1, maxCount = 10}}, "magic", {level = 0})
end
local out = roll(1)
ok(#out == 0, "chance 100% x magic 0.5 x rate 1 misses at the top roll")
out = roll(2)
ok(#out == 1 and out[1].count == 10, "rate 2: hits, count 10 (not 20): " .. tostring(out[1] and out[1].count))
out = roll(3)
ok(#out == 1 and out[1].count == 10, "rate 3: count still 10")
L.setRandom(nil)

-- currency: the chance scale is capped
C.rateMult = 3
L.setRandom(function(a, b)
	if b == 1000000 then
		return 1000000 -- the chance test: hits only when chance * scale * 100 >= 1000000
	end
	return a
end)
-- normal-tier Orb of Fate chance 20 / 10000: the scale would need 500 to hit
ChaosBlessings = {mult = function(_, kind) return kind == "orb" and 1.5 or 1 end}
local cur = L.rollCurrency("normal", {itemFind = 4, orbFind = 2})
ok(#cur == 0, "a 72x scale (3 x 4 x 2 x 1.5) does not saturate the entries")
-- boss tier: Orb of Fate 4000 x 3 = 12000 (>= 10000): hits with the capped scale
local hits = 0
for _, e in ipairs(L.rollCurrency("boss", {itemFind = 4, orbFind = 2})) do
	if e.id == 29857 then
		hits = hits + 1
	end
end
ok(hits == 1, "boss-tier entries above 1/3 still hit at the cap")
-- the cap itself: an entry with chance 3400 / 10000 hits at scale 3 (10200), one with 3300 does not
C.currency.entries = {{id = 1, count = {1, 1}, chance = {normal = 3400}}, {id = 2, count = {1, 1}, chance = {normal = 3300}}}
C.currency.guaranteed = {}
cur = L.rollCurrency("normal", {itemFind = 4, orbFind = 2})
ok(#cur == 1 and cur[1].id == 1, "the scale is exactly the cap (3.0)")
C.currency.maxScale = nil
cur = L.rollCurrency("normal", {itemFind = 4, orbFind = 2})
ok(#cur == 2, "without the cap both hit")
-- pack combat (pace.lua): ctx.pace scales the currency chance after the cap (3400 x 3 = 10200 hits; x0.5 = 5100 not)
C.currency.maxScale = 3.0
cur = L.rollCurrency("normal", {itemFind = 4, orbFind = 2, pace = 0.5})
ok(#cur == 0, "pace: the currency chance x the loot factor, outside the cap")
L.setRandom(nil)

-- pace: extra rolls x the loot factor (a 5% entry at x2 rate x0.2 pace = 2%: a 3% roll misses, a 1% roll hits)
do
	local saved = C.rateMult
	C.rateMult = 2
	local roll
	L.setRandom(function(a, b)
		if a == 0 and b == 100000 then
			return roll
		end
		return a
	end)
	local tbl = {{itemId = 2148, chance = 5000, minCount = 1, maxCount = 1}}
	local function rolls(pace)
		local out = L.rollExtraLoot(tbl, "magic", {level = 0, pace = pace})
		return #out
	end
	roll = 3000
	local base = rolls(nil)
	local paced = rolls(0.2)
	roll = 1000
	local paced2 = rolls(0.2)
	ok(base > 0 and paced == 0 and paced2 > 0, "pace: extra roll chance x the loot factor ("
		.. base .. "/" .. paced .. "/" .. paced2 .. ")")
	C.rateMult = saved
	L.setRandom(nil)
end

-- pace: thinning a corpse
do
	ChaosPaceCore = nil
	dofile("data/scripts/chaos/pace_core.lua")
	local removed = {}
	local function item(id, count)
		local it = {id = id, count = count}
		function it:getId() return self.id end
		function it:getCount() return self.count end
		function it:remove(n)
			if n then
				self.count = self.count - n
			else
				removed[#removed + 1] = self.id
				self.count = 0
			end
			return true
		end
		return it
	end
	local coins, sword = item(2148, 100), item(2400, 1)
	local corpse = {items = {coins, sword}}
	function corpse:getSize() return #self.items end
	function corpse:getItem(i) return self.items[i + 1] end
	local stackable = {[2148] = true}
	local savedS = L.isStackableId
	L.isStackableId = function(id) return stackable[id] == true end
	L.setRandom(function(a, b) return math.floor((a + b) / 2) end) -- 0.5 for the thinning
	L.thinCorpse(corpse, 0.2)
	ok(coins.count == 20, "pace: 100 coins x0.2 = 20 (" .. coins.count .. ")")
	ok(removed[1] == 2400, "pace: a sword at 0.5 >= 0.2 removed")
	coins.count = 100
	removed = {}
	L.setRandom(function(a, b) return a end) -- 0.0
	local sword2 = item(2400, 1)
	corpse.items = {coins, sword2}
	L.thinCorpse(corpse, 0.3)
	ok(#removed == 0 and sword2.count == 1, "pace: a sword at 0.0 < 0.3 kept")
	ok(L.thinCorpse(corpse, 1) == 0, "pace: factor 1 changes nothing")
	-- the gold factor: coins and sellable junk thinned again, gear and orbs untouched
	coins.count = 100
	removed = {}
	local orb = item(29851, 10)
	stackable[29851] = true
	corpse.items = {coins, orb}
	L.setRandom(function(a, b) return math.floor((a + b) / 2) end)
	local savedP = ChaosItemPrices
	ChaosItemPrices = {unsellable = function(id) return id == 29851 end, basePrice = function(id) return 50 end}
	L.thinCorpse(corpse, 1, 0.3)
	ok(coins.count == 30, "gold factor: 100 coins x0.3 = 30 (" .. coins.count .. ")")
	ok(orb.count == 10, "gold factor: an orb (unsellable currency) keeps its count")
	ok(L.isGoldLike(2148) and not L.isGoldLike(29851), "gold-like: coins yes, an unsellable currency no")
	ChaosItemPrices = savedP
	L.isStackableId = savedS
	L.setRandom(nil)
end

-- ---------------------------------------------------------------- pace: a corpse the autoloot empties decays fast too
do
	ITEM_ATTRIBUTE_DURATION = ITEM_ATTRIBUTE_DURATION or 9
	ChaosPaceConfig = {enabled = true, emptyCorpseSeconds = 30}
	local pacedMonster = {getId = function() return 5 end}
	local stockMonster = {getId = function() return 6 end}
	ChaosPace = {isPaced = function(m) return m == pacedMonster end}
	local function corpseOf(n)
		local c = {items = n, duration = nil, decays = 0}
		function c:getSize() return self.items end
		function c:setAttribute(k, v) if k == ITEM_ATTRIBUTE_DURATION then self.duration = v end end
		function c:getAttribute(k) return self.stock or 0 end
		function c:decay() self.decays = self.decays + 1 end
		return c
	end
	-- the steps after the loot layer (index > priority) that run after every autoloot (3.5) and the filter finish (4.5)
	local late
	for _, s in ipairs(dropSteps) do
		if s.fn and s.index > 4.5 then
			late = s.fn
		end
	end
	ok(late ~= nil, "an empty corpse check runs after the autoloot steps")
	if late then
		-- the autoloot (Loot Bag, base autoloot) took the last item: empty at the end of the drop
		local looted = corpseOf(0)
		late(pacedMonster, looted)
		ok(looted.duration == 30000 and looted.decays == 1, "emptied by autoloot: short decay")
		local left = corpseOf(2)
		late(pacedMonster, left)
		ok(left.duration == nil and left.decays == 0, "items left in it: stock decay (corpseSeconds unset)")
		ChaosPaceConfig.corpseSeconds = 120
		local full = corpseOf(2)
		full.stock = 300000
		late(stockMonster, full)
		ok(full.duration == 120000 and full.decays == 1, "corpse with loot: shortened to corpseSeconds")
		local brief = corpseOf(2)
		brief.stock = 60000
		late(stockMonster, brief)
		ok(brief.duration == nil, "stock decay already shorter: kept")
		ChaosPaceConfig.corpseSeconds = nil
		local stock = corpseOf(0)
		late(stockMonster, stock)
		ok(stock.duration == nil, "not paced: stock decay")
		ChaosPaceConfig.emptyCorpseSeconds = 0
		local off = corpseOf(0)
		late(pacedMonster, off)
		ok(off.duration == nil, "emptyCorpseSeconds 0: stock decay")
	end
	ChaosPace, ChaosPaceConfig = nil, nil
end

-- bad-luck protection (conquest.lua) in L.rollUniques: with an owner the chance x the group's multiplier, every group
-- with an eligible entry records a miss or a hit; without an owner (simulation, chests) nothing changes
do
	local list = {
		{id = 9001, name = "Monster Blade", minTier = "magic", chance = 10, monsters = {"Wolf"}},
		{id = 9002, name = "Boss Crown", minTier = "boss", chance = 10, bossOnly = true, monsters = {"Wolf"}},
		{id = 9003, name = "Set Helm", minTier = "magic", chance = 10, set = "embers", monsters = {"Wolf"}}
	}
	local mult, records = {monster = 1, boss = 1, set = 1}, {}
	ChaosConquest = {
		pityMult = function(_, g) return mult[g] end,
		pityRecord = function(_, g, hit, id) records[#records + 1] = {g = g, hit = hit, id = id} end
	}
	local owner = {}
	-- a magic kill: chance 10 x1 per 10000 = 1000 per 1,000,000; a roll of 1500 misses, x2 pity makes it hit
	L.setRandom(function(a, b) return b == 1000000 and 1500 or a end)
	ok(#L.rollUniques("magic", "Wolf", 50, 1, list, owner) == 0, "no pity: the roll misses")
	local groups = {}
	for _, r in ipairs(records) do groups[r.g] = r.hit end
	ok(groups.monster == false and groups.set == false and groups.boss == nil, "monster and set misses recorded, no boss roll")
	records = {}
	mult.monster = 2
	local hits = L.rollUniques("magic", "Wolf", 50, 1, list, owner)
	ok(#hits == 1 and hits[1].id == 9001, "x2 pity: the monster unique drops")
	groups = {}
	for _, r in ipairs(records) do groups[r.g] = r end
	ok(groups.monster and groups.monster.hit == true and groups.monster.id == 9001, "the hit resets the monster group")
	ok(groups.set and groups.set.hit == false, "the set group still missed")
	records = {}
	L.rollUniques("magic", "Wolf", 50, 1, list, nil)
	ok(#records == 0, "no owner: no pity")
	ChaosConquest = nil
	L.setRandom(math.random)
end

-- owner 2026-10-17: orbs only from monsters of level 100+ (bosses exempt), waystones only from level 150+
do
	local cur0 = C.currency
	local saved = {entries = cur0.entries, guaranteed = cur0.guaranteed, scale = cur0.maxScale}
	cur0.entries = {{id = 1, count = {1, 1}, chance = {normal = 10000, boss = 10000}}}
	cur0.guaranteed = {}
	cur0.maxScale = 3.0
	L.setRandom(function(a, b) return a end)
	ok(cur0.minMonsterLevel == 100, "orb level gate default 100")
	ok(#L.rollCurrency("normal", {orbLevel = 99}) == 0, "level 99: no orb")
	ok(#L.rollCurrency("normal", {orbLevel = 100}) == 1, "level 100: orbs drop")
	ok(#L.rollCurrency("normal", {}) == 1, "no level in ctx (diagnostics): not gated")
	ok(#L.rollCurrency("boss", {orbLevel = 10}) == 1, "bosses are exempt")
	cur0.entries, cur0.guaranteed, cur0.maxScale = saved.entries, saved.guaranteed, saved.scale
	L.setRandom(math.random)

	local function mkCorpse(names)
		local removed = {}
		local items = {}
		for i, n in ipairs(names) do
			items[i] = {getName = function() return n end, remove = function() removed[n] = true; items[i].gone = true end}
		end
		local corpse = {getSize = function() return #items end, getItem = function(_, slot) return items[slot + 1] end}
		return corpse, removed
	end
	local corpse, removed = mkCorpse({"Waystone Tier III", "gold coin", "Waystone Tier I"})
	ok(L.gateWaystones(corpse, 149, "normal") == 2 and removed["Waystone Tier III"] and removed["Waystone Tier I"]
		and not removed["gold coin"], "level 149: waystones taken out, other loot kept")
	corpse, removed = mkCorpse({"Waystone Tier III"})
	ok(L.gateWaystones(corpse, 150, "normal") == 0 and not next(removed), "level 150: waystone stays")
	corpse, removed = mkCorpse({"Waystone Tier III"})
	ok(L.gateWaystones(corpse, 20, "boss") == 0, "boss tier is skipped")
end

print(string.format("loot_caps_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

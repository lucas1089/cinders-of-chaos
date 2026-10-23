-- Run from the server/ folder: luajit tests/boss_roulette_test.lua (and lua5.3; CI runs both)
-- The Boss Roulette's prize pool (data/scripts/chaos/boss_roulette_config.lua, tools/patch_roulette.py, README "Boss
-- Roulette", O148). Beta 2026-10-23: "One reward was the golden deck, the other a boat. The roulette also shows lots of
-- card rewards." Checks: no retired id (decks, ships, belts, gloves), no dead id (every id is a base or a Chaos item
-- that the committed data knows), the odds add up, a card is at most a few percent of the spins, the orbs are the ones
-- the loot layer drops, gold grows with the level, the unique chest picks a unique of the level; prints the expected
-- value of a spin before and after.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, eps, what)
	ok(math.abs(a - b) <= eps, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

local K = dofile("data/scripts/chaos/prizes_core.lua")
local cfg = dofile("data/scripts/chaos/boss_roulette_config.lua")
local lim = cfg.limits

-- ------------------------------------------------------------------------------------------------ the item ids
-- what the committed data knows: base item lists, the price classes, the Chaos orb / gem / crafting configs, the
-- badge range of patch_badges.py. (The base items.xml is not in the repo: tools/patch_roulette_test.py also reads an
-- installed one when CHAOS_ITEMS_XML points at it.)
local known = {}
local function addAll(text, pattern)
	for id in text:gmatch(pattern) do
		known[tonumber(id)] = true
	end
end
addAll(readFile("data/items/base_item_names.csv"), "\n(%d+),")
addAll(readFile("data/items/base_item_values.csv"), "\n(%d+),")
addAll(readFile("data/items/chaos_items.xml"), 'id="(%d+)"')
addAll(readFile("data/lib/chaos_item_prices_data.lua"), "%[(%d+)%]")
addAll(readFile("data/lib/chaos_orbs_config.lua"), "id = (%d+)")
addAll(readFile("data/lib/chaos_crafting.lua"), "id = (%d+)")
addAll(readFile("data/lib/chaos_gems_config.lua"), "id = (%d+)")
local badgesPy = readFile("tools/patch_badges.py")
local lo, hi = badgesPy:match("BADGES = range%((%d+), (%d+)%)")
for id = tonumber(lo), tonumber(hi) - 1 do
	known[id] = true
end

-- retired: the config's own list and the decks, ships, belts and gloves of patch_badges.py
local retired = {}
for _, id in ipairs(cfg.retired) do
	retired[id] = true
end
for _, name in ipairs({"DECKS", "BELTGLOVES"}) do
	local body = badgesPy:match(name .. " = %(([^)]*)%)")
	for id in (body or ""):gmatch("%d+") do
		retired[tonumber(id)] = true
	end
end
local shipLo, shipHi = badgesPy:match("SHIPS = tuple%(range%((%d+), (%d+)%)%)")
for id = tonumber(shipLo), tonumber(shipHi) - 1 do
	retired[id] = true
end
ok(retired[27633] and retired[27634] and retired[27797] and retired[29577], "the retired set holds decks, ships, belts")

local KINDS = {orb = true, material = true, gold = true, unique = true, badge = true, catalyst = true, card = true}
local seen = {}
for i, e in ipairs(cfg.pool) do
	local tag = "entry " .. i .. " " .. tostring(e.name)
	ok(type(e.id) == "number" and e.id > 0, tag .. ": an id")
	ok(known[e.id], tag .. ": id " .. tostring(e.id) .. " is a known item")
	ok(not retired[e.id], tag .. ": not a deck, ship, belt or gloves")
	ok(KINDS[e.kind], tag .. ": a known kind")
	ok(e.count[1] >= 1 and e.count[2] >= e.count[1], tag .. ": a count")
	ok(e.chance >= 1 and e.chance <= 10000, tag .. ": a chance in 1..10000")
	local key = e.id .. ":" .. e.count[1] .. "-" .. e.count[2]
	ok(not seen[key], tag .. ": not twice")
	seen[key] = true
	if e.kind ~= "gold" then
		for j = 1, i - 1 do
			ok(cfg.pool[j].id ~= e.id, tag .. ": the id appears once (only gold repeats the crystal coin)")
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the odds
local function oddsOf(list)
	local pool = {}
	for i, e in ipairs(list) do
		pool[i] = {itemId = e.id, chance = e.chance}
	end
	return K.odds(pool)
end
local odds = oddsOf(cfg.pool)
local sum, share, avgCount = 0, {}, {}
for i, e in ipairs(cfg.pool) do
	sum = sum + odds[i]
	share[e.kind] = (share[e.kind] or 0) + odds[i]
end
near(sum, 1, 1e-9, "the odds of the pool add up to 1")
ok(share.card <= lim.maxCardShare, string.format("cards are at most %.0f%% of the spins (%.2f%%)", lim.maxCardShare * 100,
	share.card * 100))
ok(share.orb + share.material + share.gold >= lim.minOrbShare, "orbs, sockets and gold are the bulk: " ..
	(share.orb + share.material + share.gold))
ok(share.gold >= lim.minGoldShare, "gold share: " .. share.gold)
ok(share.unique >= lim.minUniqueShare and share.unique <= lim.maxUniqueShare, "unique chest share: " .. share.unique)
ok(share.badge + share.catalyst > 0.03, "badges and catalysts stay a prize")
-- every badge line has its badge and the line's first catalyst in the pool
ok(#cfg.pool >= 30, "a pool with variety: " .. #cfg.pool)

-- ------------------------------------------------------------------------------------------------ the loot layer
-- the orbs of the pool are the orbs the loot layer drops (loot_config.lua currency.entries): no orb that nothing else
-- hands out, and the chase orbs stay chase prizes
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
Chaos = {}
MAX_LOOTCHANCE = 100000
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
dofile("data/scripts/chaos/loot.lua")
local C = ChaosLootConfig
local dropped, normalEq = {}, {}
for _, e in ipairs(C.currency.entries) do
	dropped[e.id] = true
	local n = e.chance.normal
	if not n or n == 0 then
		n = (e.chance.magic or 0) / 3
	end
	normalEq[e.id] = 10000 / n -- kills of a level 100+ monster per drop of that orb
end
for i, e in ipairs(cfg.pool) do
	if e.kind == "orb" or e.kind == "material" then
		ok(dropped[e.id], e.name .. " is an orb the loot layer drops (currency.entries)")
	end
end
for _, name in ipairs({"Orb of Ruin", "Void Orb", "Crown Orb", "Ember Orb", "Orb of Binding", "Orb of Excision"}) do
	for i, e in ipairs(cfg.pool) do
		if e.name == name then
			ok(odds[i] <= 0.01, name .. " stays a chase prize (at most 1% of the spins): " .. odds[i])
		end
	end
end

-- ------------------------------------------------------------------------------------------------ gold
local hunting = dofile("data/scripts/chaos/gamble_config.lua").balance.hunting
ok(#hunting == #cfg.gold.hunting, "the gold curve has the points of gamble_config.lua balance.hunting")
for i, p in ipairs(hunting) do
	ok(cfg.gold.hunting[i] and cfg.gold.hunting[i][1] == p[1] and cfg.gold.hunting[i][2] == p[2], "gold curve point " .. i)
end
local prev = 0
for _, level in ipairs({1, 8, 40, 100, 300, 500, 1000, 1500, 2000}) do
	local g = K.goldFor(cfg, 1, level)
	ok(g >= 10000 and g % 10000 == 0, "level " .. level .. ": whole crystal coins, at least one: " .. g)
	ok(g >= prev, "level " .. level .. ": gold does not fall with the level")
	prev = g
	local total = 0
	for _, st in ipairs(K.coinStacks(g)) do
		total = total + st[2] * ({[2160] = 10000, [2152] = 100, [2148] = 1})[st[1]]
	end
	ok(total == g, "level " .. level .. ": the coin stacks add up")
end
ok(math.abs(K.goldFor(cfg, 5, 1000) - 5 * K.goldFor(cfg, 1, 1000)) <= 40000, "5 units pay 5 times one (whole crystal coins)")
near(K.goldFor(cfg, 1, 1000) / 9519711, cfg.gold.perUnit, 0.001, "a unit is perUnit of an hour at level 1000")
ok(K.goldFor(cfg, 1, 1500) == K.goldFor(cfg, 1, 5000), "flat beyond the last point")

-- ------------------------------------------------------------------------------------------------ the unique chest
setmetatable(_G, {__index = function(_, k)
	if type(k) == "string" and k:match("^ITEM_ATTRIBUTE_") then return k end
end})
dofile("data/lib/chaos_item_mods.lua")
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
local list = ChaosLoot.uniqueList()
for _, level in ipairs({1, 12, 100, 400, 1000, 1500, 2000, 2400, 5000}) do
	local pick = K.uniqueChoices(cfg, list, level)
	ok(#pick > 0, "level " .. level .. ": the chest has a unique to give (" .. #pick .. ")")
	for _, e in ipairs(pick) do
		ok(not e.season and not e.ascended and not e.bossOnly, "level " .. level .. ": " .. e.name .. " is a plain unique")
	end
end
local at1500 = K.uniqueChoices(cfg, list, 1500)
local allIn = true
for _, e in ipairs(at1500) do
	if e.level < 750 or e.level > 1500 then allIn = false end
end
ok(allIn and #at1500 >= 5, "level 1500: " .. #at1500 .. " uniques of item level 750-1500")

-- ------------------------------------------------------------------------------------------------ expected value
-- Orbs: kills of a level 100+ monster that the loot layer needs for the same orbs (normal-tier chance; the Orb of Ruin,
-- with none, by its magic chance / 3). Gold: kills of the level 1000 hunt that pay the same gold (9.5M an hour at 870
-- kills an hour: tools/spawn_tuning.json model.paceKillsPerHour, gamble_config.lua balance.hunting).
local OLD = {
	{id = 27822, chance = 6800, kind = "badge"}, {id = 27808, chance = 6500, kind = "badge"},
	{id = 27804, chance = 6100, kind = "badge"}, {id = 27812, chance = 5000, kind = "badge"},
	{id = 27826, chance = 4800, kind = "badge"}, {id = 27817, chance = 4100, kind = "badge"},
	{id = 27831, chance = 3500, kind = "badge"}, {id = 27835, chance = 3000, kind = "badge"},
	{id = 27839, chance = 2500, kind = "badge"}, {id = 27547, chance = 800, kind = "card"},
	{id = 27595, chance = 800, kind = "card"}, {id = 27613, chance = 800, kind = "card"},
	{id = 27571, chance = 800, kind = "card"},
}
local OLD_WITH_DECKS = {{id = 27633, chance = 7000, kind = "deck"}, {id = 27634, chance = 5800, kind = "deck"},
	{id = 27797, chance = 4400, kind = "ship"}}
for _, e in ipairs(OLD) do
	OLD_WITH_DECKS[#OLD_WITH_DECKS + 1] = e
end
local function summary(list)
	local o = oddsOf(list)
	local s = {orbKills = 0, orbs = 0, goldKills = 0, gold = 0, kinds = {}}
	for i, e in ipairs(list) do
		local avg = e.count and (e.count[1] + e.count[2]) / 2 or 1
		s.kinds[e.kind] = (s.kinds[e.kind] or 0) + o[i]
		if e.kind == "orb" or e.kind == "material" then
			s.orbs = s.orbs + o[i] * avg
			s.orbKills = s.orbKills + o[i] * avg * normalEq[e.id]
		elseif e.kind == "gold" then
			local g = K.goldFor(cfg, e.count[1], 1000)
			s.gold = s.gold + o[i] * g
			s.goldKills = s.goldKills + o[i] * g / (9519711 / 870)
		end
	end
	return s
end
local before0, before1, after = summary(OLD_WITH_DECKS), summary(OLD), summary(cfg.pool)
local function pct(x) return string.format("%.1f%%", (x or 0) * 100) end
print("Boss Roulette, expected value of one spin")
print(string.format("  base pool (decks, ship, badges, 4 cards): cards %s, decks/ship %s, orbs 0, gold 0, useless %s",
	pct(before0.kinds.card), pct((before0.kinds.deck or 0) + (before0.kinds.ship or 0)),
	pct((before0.kinds.deck or 0) + (before0.kinds.ship or 0))))
print(string.format("  after the prizes step (badges, 4 cards): cards %s, badges %s, orbs 0, gold 0", pct(before1.kinds.card),
	pct(before1.kinds.badge)))
print(string.format("  now: cards %s, badges %s, catalysts %s, orbs %s, sockets %s, gold %s, unique chest %s; %.2f orbs and "
	.. "%.0f gold at level 1000 per spin = %.0f + %.0f kills", pct(after.kinds.card), pct(after.kinds.badge),
	pct(after.kinds.catalyst), pct(after.kinds.orb), pct(after.kinds.material), pct(after.kinds.gold), pct(after.kinds.unique),
	after.orbs, after.gold, after.orbKills, after.goldKills))
ok(before1.orbKills == 0 and before1.goldKills == 0, "before: no orb and no gold in the pool")
ok(after.orbKills > 100 and after.orbKills < 1500, "a spin pays 100-1500 kills of orbs: " .. after.orbKills)
ok(after.goldKills > 20 and after.goldKills < 600, "and 20-600 kills of gold at level 1000: " .. after.goldKills)
ok((before0.kinds.deck or 0) + (before0.kinds.ship or 0) > 0.27, "the base pool was 27.8% decks and a ship")

print(string.format("boss_roulette_test: %d of %d failed", fails, checks))
os.exit(fails == 0 and 0 or 1)

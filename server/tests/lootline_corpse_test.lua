-- Run from the server/ folder: luajit tests/lootline_corpse_test.lua (and lua5.3; mock engine API, CI runs it)
-- Beta report 2026-10-21 (Nightfang Widow, Shadowcrystal Widow): "it says it drops X items, but neither the Loot tab nor
-- the bag gets even half". The stock "Loot of ..." line is written at onDropLoot index 0, from the corpse the stock pass
-- filled. The Chaos loot layer (loot.lua, index 1) then thins that corpse for pack combat (pace.lua): for these two base
-- monsters (bounty pool levels 509 and 480, hunting level 2x) about 24% of the items stay and about 7% of the coins and
-- NPC-sellable items. The line kept the full stock list. Now lootline.lua reads the corpse at index 1.9 and the line lists
-- exactly what is in it (lootline_core.lua K.describe). Also: loot.lua L.addToCorpse (a stack above 100 is split, a full
-- corpse takes the item past its size), the line's entry format, the display scale never touching loot texts.
-- Since 2026-10-21 the thinning is by the monster's level only (server/README.md "Loot by monster level", tests/
-- loot_by_level_test.lua): the coins come back as coins, and the same kill leaves the same corpse for any killer.
--
-- The widows are base server monsters: their loot files are not in this repository (the base tree is not committed),
-- so the loot list below is a representative high-level spider list (coins, potions, creature products, gear). Their
-- levels, health and experience are the real ones of data/scripts/chaos/bounty_pool.lua.
local checks, failures = 0, 0
local function check(v, m)
	checks = checks + 1
	if not v then
		failures = failures + 1
		print("FAIL " .. tostring(m))
	end
end
local function eq(a, b, m) check(a == b, tostring(m) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, eps, m) check(math.abs(a - b) <= eps, tostring(m) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ---------------------------------------------------------------- the widows' pace factors (the root cause's size)
dofile("data/scripts/chaos/pace_core.lua")
local PCore = ChaosPaceCore
local paceCfg = dofile("data/scripts/chaos/pace_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")
local widows = {}
for _, list in ipairs({pool.hunt or {}, pool.bosses or {}}) do
	for _, e in ipairs(list) do
		if e.name == "Nightfang Widow" or e.name == "Shadowcrystal Widow" then
			widows[e.name] = e
		end
	end
end
check(widows["Nightfang Widow"] and widows["Shadowcrystal Widow"], "both widows are in the bounty pool")
local factors = {}
for name, e in pairs(widows) do
	local level, scaled = PCore.entryLevel(paceCfg, e)
	check(not scaled, name .. ": a base monster (pool level = its estimate)")
	local f = PCore.factors(paceCfg, level, scaled)
	factors[name] = f
	-- O285 (hunting level = pool level): a widow is hunted at 509 / 480; the base loot curve there is 0.014-0.017 of the
	-- stock items (the pool's own level-500 monsters carry about 8x the gold of the level-250 ones the curve was fitted
	-- on before), with the coins share of the O141 gold curve
	check(f.loot > 0.05 and f.loot < 0.15, name .. ": about a tenth of the plain stock items stay (" .. f.loot .. ")")
	-- loot by monster level (2026-10-21, server/README.md "Loot by monster level"): the coins curve replaced the flat
	-- 0.30 of `gold`; the notable drops keep the loot factor below level 650
	check(f.coins > 0.003 and f.coins < 0.3, name .. ": coins and sellables worth x" .. f.coins .. " on top")
	check(f.notable > 0.15 and f.notable < 0.25, name .. ": the notable drops stay at the pre-O285 rate (" .. f.notable .. ")")
end
eq(PCore.entryLevel(paceCfg, widows["Nightfang Widow"]), 509, "Nightfang Widow: hunting level (the pool level)")
eq(PCore.entryLevel(paceCfg, widows["Shadowcrystal Widow"]), 480, "Shadowcrystal Widow: hunting level (the pool level)")

-- ---------------------------------------------------------------- engine mock
MESSAGE_LOOT, MESSAGE_INFO_DESCR = 22, 20
FLAG_NOLIMIT, INDEX_WHEREEVER = 1, -1
MAX_LOOTCHANCE = 100000
local unpackFn = table.unpack or unpack

-- item types: {name, plural, article, stackable, gear, price}
local TYPES = {
	[2148] = {"gold coin", "gold coins", "a", true, false, 1},
	[2152] = {"platinum coin", "platinum coins", "a", true, false, 100},
	[2160] = {"crystal coin", "crystal coins", "a", true, false, 10000},
	[7590] = {"great mana potion", "great mana potions", "a", true, false, 120},
	[8473] = {"ultimate health potion", "ultimate health potions", "an", true, false, 310},
	[36026] = {"tuft of spider silk", "tufts of spider silk", "a", true, false, 40},
	[2392] = {"fire sword", "fire swords", "a", false, true, 4000},
	[2476] = {"knight armor", "knight armors", "a", false, true, 5000},
	[2195] = {"pair of boots of haste", "pairs of boots of haste", "a", false, true, 30000},
	[5021] = {"orichalcum pearl", "orichalcum pearls", "an", true, false, 0},
	[2400] = {"magic sword", "magic swords", "a", false, true, 0}
}
local typeMeta = {}
typeMeta.__index = function(t, k)
	local row = TYPES[rawget(t, "id")] or {"item " .. tostring(rawget(t, "id")), nil, "a", false, false, 0}
	local fns = {
		getId = function() return TYPES[t.id] and t.id or 0 end,
		getName = function() return row[1] end,
		getPluralName = function() return row[2] end,
		getArticle = function() return row[3] end,
		isStackable = function() return row[4] end,
		getArmor = function() return row[5] and 5 or 0 end,
		getClientId = function() return t.id end
	}
	if fns[k] then
		return fns[k]
	end
	return function() return 0 end -- getAttack, getDefense, getAmmoType, getCharges, ...: none
end
function ItemType(id)
	return setmetatable({id = tonumber(id) or 0, isContainer = function() return false end,
		getAbilities = function() return nil end, isRune = function() return false end,
		isFluidContainer = function() return false end, getWeaponType = function() return 0 end,
		getSlotPosition = function() return 0 end}, typeMeta)
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getType() return ItemType(self.id) end
function Item:getName() return TYPES[self.id][1] end
function Item:getPluralName() return TYPES[self.id][2] end
function Item:getArticle() return TYPES[self.id][3] end
function Item:isItem() return true end
function Item:isContainer() return false end
function Item:getActionId() return 0 end
function Item:getCustomAttribute(k) return self.attrs[k] end
function Item:setCustomAttribute(k, v) self.attrs[k] = v end
function Item:removeCustomAttribute(k) self.attrs[k] = nil end
function Item:remove(n)
	local c = self.parent
	if n and n < self.count then
		self.count = self.count - n
		return true
	end
	for i, it in ipairs(c.items) do
		if it == self then
			table.remove(c.items, i)
			break
		end
	end
	return true
end

local Corpse = {}
Corpse.__index = Corpse
local function newCorpse(owner, capacity)
	return setmetatable({owner = owner, items = {}, capacity = capacity or 20}, Corpse)
end
function Corpse:getCorpseOwner() return self.owner end
function Corpse:getSize() return #self.items end
function Corpse:getCapacity() return self.capacity end
function Corpse:getItem(i) return self.items[i + 1] end
function Corpse:getItems()
	local out = {}
	for i, it in ipairs(self.items) do
		out[i] = it
	end
	return out
end
function Corpse:isContainer() return true end
function Corpse:getType() return {isContainer = function() return true end} end
function Corpse:getPosition() return {x = 100, y = 100, z = 7} end
-- the engine's Container:addItem (luascript.cpp): a stackable count is cut to 100; a full container refuses without
-- FLAG_NOLIMIT
function Corpse:addItem(id, count, index, flags)
	count = count or 1
	if TYPES[id][4] then
		count = math.min(count, 100)
	end
	if #self.items >= self.capacity and flags ~= FLAG_NOLIMIT then
		return nil
	end
	local it = newItem(id, TYPES[id][4] and count or 1)
	it.parent = self
	self.items[#self.items + 1] = it
	return it
end

-- TFS Container::getContentDescription: "100 gold coins, a fire sword" (the stock line's list)
local function contentDescription(corpse)
	if #corpse.items == 0 then
		return "nothing"
	end
	local parts = {}
	for _, it in ipairs(corpse.items) do
		local t = TYPES[it.id]
		parts[#parts + 1] = (t[4] and it.count > 1) and (it.count .. " " .. t[2]) or (t[3] .. " " .. t[1])
	end
	return table.concat(parts, ", ")
end

local sent = {}
local players = {}
Player = setmetatable({}, {__call = function(_, id) return players[id] end})
local Pmeta = {__index = Player}
function Player.sendTextMessage(self, mode, text) sent[#sent + 1] = {self.name, mode, text} return true end
function Player.getId(self) return self.id end
function Player.getParty() return nil end
function Player.getName(self) return self.name end
function Player.getStamina() return 2520 end
function Player.getStorageValue() return -1 end
function Player.getLevel() return 520 end
function Player.getGuid(self) return self.id end
Party = {broadcastPartyLoot = function() end}
local hunter = setmetatable({id = 1, name = "Hunter"}, Pmeta)
players[1] = hunter

Game = {getSpectators = function() return {} end}
Chaos = {
	monsterNameDescription = function(m) return m.desc end,
	monsterTypeName = function(m) return m.name end,
	t = function(_, key, ...)
		if select("#", ...) == 0 then return tostring(key) end
		return string.format(tostring(key), ...)
	end
}
ChaosI18n = {msg = function(fmt, ...) return string.format(fmt, ...) end}

local callbacks, pending = {}, nil
EventCallback = setmetatable({}, {
	__index = function(_, k)
		if k == "register" then
			return function(_, index) callbacks[#callbacks + 1] = {fn = pending, index = index or 0} end
		end
	end,
	__newindex = function(_, _, v) pending = v end
})

dofile("data/scripts/chaos/lootline.lua")
dofile("data/scripts/chaos/loot.lua")
local X, L, K = ChaosLootLine, ChaosLoot, ChaosLootLineCore
local indexes = {}
for _, c in ipairs(callbacks) do
	indexes[#indexes + 1] = c.index
end
table.sort(indexes)
eq(table.concat(indexes, ","), "-1,1,1.9,99,100", "lootline open -1, loot layer 1, settle 1.9, empty check 99, flush 100")
check(X.settleIndex > 1.7 and X.settleIndex < 2, "settle after Echoing Spoils (1.5) and the dungeon loot (1.7), before the auto seller (2)")

-- the widow's stock loot: what default_onDropLoot puts in at index 0 (every entry hit, counts at their maximum)
local WIDOW_LOOT = {
	{itemId = 2148, chance = 100000, maxCount = 100}, {itemId = 2152, chance = 100000, maxCount = 8},
	{itemId = 7590, chance = 100000, maxCount = 3}, {itemId = 8473, chance = 100000, maxCount = 2},
	{itemId = 36026, chance = 100000, maxCount = 4}, {itemId = 2392, chance = 100000, maxCount = 1},
	{itemId = 2476, chance = 100000, maxCount = 1}, {itemId = 2195, chance = 100000, maxCount = 1}
}
local function stockPass(monster, corpse)
	for _, e in ipairs(WIDOW_LOOT) do
		corpse:addItem(e.itemId, e.maxCount)
	end
	Player(corpse.owner):sendTextMessage(MESSAGE_LOOT, "Loot of " .. monster.desc .. ": " .. contentDescription(corpse))
end

local function monsterOf(name, id)
	local e = widows[name]
	return {id = id, name = name, desc = "a " .. name:lower(), getId = function(self) return self.id end,
		getName = function(self) return self.name end, getMonsterLevel = function() return 0 end,
		getPosition = function() return {x = 100, y = 100, z = 7} end,
		getType = function()
			return {getLoot = function() return WIDOW_LOOT end, getExperience = function() return e.exp end,
				getMaxHealth = function() return e.health end, isBoss = function() return false end}
		end}
end

-- the kill: lootline -1, stock 0, loot layer 1, settle 1.9, the loot channel snapshot 2.5 (what it would list), the empty
-- check 99, the flush 100
local function kill(monster, corpse)
	local chain = {{index = 0, fn = stockPass}}
	local snapshot
	chain[#chain + 1] = {index = 2.5, fn = function(_, c)
		snapshot = {}
		for _, it in ipairs(c.items) do
			snapshot[#snapshot + 1] = {id = it.id, count = it.count}
		end
	end}
	for _, c in ipairs(callbacks) do
		chain[#chain + 1] = c
	end
	table.sort(chain, function(a, b) return a.index < b.index end)
	for _, c in ipairs(chain) do
		c.fn(monster, corpse)
	end
	return snapshot
end

-- the pack thinning of pace.lua for these monsters (pace.lua marks a spawned monster; here by name)
ChaosPace = {
	lootMultOf = function(m) return factors[m.name] and factors[m.name].loot or 1 end,
	goldMultOf = function(m) return factors[m.name] and factors[m.name].gold or 1 end,
	factorsOf = function(m) return factors[m.name] end
}
ChaosPaceConfig = paceCfg -- lootLevel on: the corpse is thinned by the monster's level (L.thinCorpseByLevel)
ChaosItemPrices = {unsellable = function(id) return id == 5021 end,
	basePrice = function(id) return TYPES[id] and TYPES[id][6] or 0 end}

-- the counts of a line's list: "100 gold coins, a fire sword" -> {gold coin = 100, fire sword = 1}
local function countsOf(list)
	local out = {}
	for part in (list .. ", "):gmatch("(.-), ") do
		part = part:gsub("^{", ""):gsub("}$", ""):gsub("^%[[^%]]+%] ", "")
		local n, rest = part:match("^(%d+) (.+)$")
		local name
		if n then
			for _, t in pairs(TYPES) do
				if t[2] == rest then name = t[1] end
			end
		else
			name = part:gsub("^an? ", "")
		end
		out[name or part] = (out[name or part] or 0) + (tonumber(n) or 1)
	end
	return out
end
local function corpseCounts(items)
	local out = {}
	for _, it in ipairs(items) do
		local name = TYPES[it.id][1]
		out[name] = (out[name] or 0) + it.count
	end
	return out
end
local function sameCounts(a, b, m)
	for k, v in pairs(a) do
		eq(b[k], v, m .. ": " .. k)
	end
	for k, v in pairs(b) do
		eq(a[k], v, m .. ": " .. k)
	end
end

local seeds = {7, 11, 23, 42, 99}
for _, name in ipairs({"Nightfang Widow", "Shadowcrystal Widow"}) do
	local stockTotal, lineTotal, corpseTotal = 0, 0, 0
	local stockGold, corpseGold, stockItems, corpseItems, smallCoins = 0, 0, 0, 0, 0
	for k, seed in ipairs(seeds) do
		math.randomseed(seed)
		local corpse = newCorpse(1, 20)
		sent = {}
		local snapshot = kill(monsterOf(name, 1000 + k), corpse)
		local loot = {}
		for _, s in ipairs(sent) do
			if s[2] == MESSAGE_LOOT then loot[#loot + 1] = s[3] end
		end
		eq(#loot, 1, name .. " #" .. k .. ": one loot line")
		local line = loot[1] or ""
		local listed = countsOf((line:match("^Loot of [^:]+: (.-)%.$")) or "")
		if os.getenv("LOOTLINE_SHOW") then print(line) end
		local inCorpse = corpseCounts(corpse.items)
		if #corpse.items == 0 then
			eq(line, "Loot of a " .. name:lower() .. ": nothing.", name .. " #" .. k .. ": an empty corpse says nothing")
		else
			sameCounts(listed, inCorpse, name .. " #" .. k .. ": the line lists exactly the corpse")
		end
		-- the loot channel (snapshot at 2.5) sees the same items the line lists
		sameCounts(corpseCounts(snapshot), inCorpse, name .. " #" .. k .. ": the loot channel row")
		for _, e in ipairs(WIDOW_LOOT) do
			stockTotal = stockTotal + e.maxCount
			if e.itemId == 2148 or e.itemId == 2152 then
				stockGold = stockGold + e.maxCount * TYPES[e.itemId][6]
			else
				stockItems = stockItems + 1
			end
		end
		if #corpse.items > 0 then -- "nothing." lists no item
			for _, n in pairs(listed) do lineTotal = lineTotal + n end
		end
		for _, n in pairs(inCorpse) do corpseTotal = corpseTotal + n end
		for _, it in ipairs(corpse.items) do
			if it.id == 2148 or it.id == 2152 then
				smallCoins = smallCoins + it.count
			end
			if it.id == 2148 or it.id == 2152 or it.id == 2160 then
				corpseGold = corpseGold + it.count * (it.id == 2148 and 1 or it.id == 2152 and 100 or 10000)
			else
				corpseItems = corpseItems + 1
			end
		end
	end
	eq(lineTotal, corpseTotal, name .. ": over the kills the line said exactly what arrived")
	-- the old line: the stock list as written at index 0 said every stock item and coin; the corpse got far less
	check(corpseGold < stockGold / 2, name .. ": the thinning keeps less than half the stock gold (" .. corpseGold ..
		" of " .. stockGold .. ")")
	check(corpseItems < stockItems, name .. ": and fewer than the stock items (" .. corpseItems .. " of " ..
		stockItems .. ")")
	-- O285: the widows are off lootLevel.crystalOnly, their pay (a few hundred gold) comes as platinum and gold coins
	check(smallCoins > 0, name .. ": gold or platinum coins in the corpses (" .. smallCoins .. ")")
end

-- loot by monster level (owner 2026-10-21): the corpse depends on the monster only. The same kill with the same rolls
-- for a level 100 hunter alone and a level 1500 hunter in a party leaves the same corpse.
do
	local low = setmetatable({id = 5, name = "Low", getLevel = function() return 100 end}, Pmeta)
	local partyObj = {getLeader = function() return nil end, getMembers = function() return {} end,
		broadcastPartyLoot = function() end, isSharedExperienceActive = function() return true end}
	local high = setmetatable({id = 6, name = "High", getLevel = function() return 1500 end,
		getParty = function() return partyObj end}, Pmeta)
	players[5], players[6] = low, high
	for _, name in ipairs({"Nightfang Widow", "Shadowcrystal Widow"}) do
		for _, seed in ipairs({3, 31, 43}) do
			local got = {}
			for _, who in ipairs({5, 6}) do
				math.randomseed(seed)
				local corpse = newCorpse(who, 20)
				sent = {}
				kill(monsterOf(name, 3000 + seed), corpse)
				local parts = {}
				for _, it in ipairs(corpse.items) do
					parts[#parts + 1] = it.id .. "x" .. it.count
				end
				got[who] = table.concat(parts, ",")
			end
			eq(got[5], got[6], name .. " seed " .. seed .. ": the same corpse for a level 100 hunter and a level 1500 party")
			-- O285: no "the corpse is not empty" check here any more. A widow pays about 700-870 gold a kill at its pool
			-- level (it paid 3,170 as a level 1018 monster) and its pay is crystal coins only (10,000 each, a random
			-- whole number): about 90% of the kills show no coin, and the items are 0.04 a kill (README "Loot by monster level")
		end
	end
	-- the shares come from the monster alone
	local f = L.corpseFactors(monsterOf("Nightfang Widow", 3100), 1)
	near(f.coins, factors["Nightfang Widow"].coins, 1e-12, "corpseFactors: the monster's coins share")
	near(f.notable, factors["Nightfang Widow"].notable, 1e-12, "corpseFactors: the monster's notable share at level 509")
	local fp = L.corpseFactors(monsterOf("Nightfang Widow", 3101), 0.5)
	near(fp.loot, factors["Nightfang Widow"].loot * 0.5, 1e-12, "corpseFactors: a pocket's factor on loot")
	near(fp.notable, factors["Nightfang Widow"].notable * 0.5, 1e-12, "corpseFactors: and on the notable drops")
end

-- the report reproduced: without the settle step (the chain before the fix) the line is the stock list of index 0
do
	local saved = {}
	for i = #callbacks, 1, -1 do
		if callbacks[i].index == X.settleIndex then
			saved[#saved + 1] = table.remove(callbacks, i)
		end
	end
	eq(#saved, 1, "the settle step taken out")
	math.randomseed(7)
	local corpse = newCorpse(1, 20)
	sent = {}
	kill(monsterOf("Nightfang Widow", 2000), corpse)
	local line = sent[#sent] and sent[#sent][3] or ""
	local listed = countsOf((line:match("^Loot of [^:]+: (.-)%.$")) or "")
	if os.getenv("LOOTLINE_SHOW") then print("before the fix: " .. line) end
	eq(listed["gold coin"], 100, "before the fix: the line said 100 gold coins")
	local inCorpse = corpseCounts(corpse.items)
	check((inCorpse["gold coin"] or 0) < 100 and (inCorpse["platinum coin"] or 0) < 8,
		"before the fix: the corpse held " .. tostring(inCorpse["gold coin"]) .. " gold coins")
	local said, got = 0, 0
	for k, n in pairs(listed) do said = said + ((k == "gold coin" or k == "platinum coin") and 0 or n) end
	for k, n in pairs(inCorpse) do got = got + ((k == "gold coin" or k == "platinum coin") and 0 or n) end
	check(got < said, "before the fix: not all the items arrived (" .. got .. " of " .. said .. ")")
	callbacks[#callbacks + 1] = saved[1]
end

-- ---------------------------------------------------------------- K.describe: the entry format
local D = K.describe({
	{id = 2148, name = "gold coin", plural = "gold coins", article = "a", count = 60, stackable = true},
	{id = 2148, name = "gold coin", plural = "gold coins", article = "a", count = 40, stackable = true},
	{id = 7590, name = "great mana potion", plural = "great mana potions", article = "a", count = 1, stackable = true},
	{id = 2392, name = "fire sword", article = "a", count = 1, rarity = 4},
	{id = 2476, name = "knight armor", article = "a", count = 1, rarity = 2},
	{id = 2476, name = "knight armor", article = "a", count = 1, rarity = 7}, -- an old id: Legendary
	{id = 2400, name = "Ashbringer", article = "a", count = 1, rarity = 5, unique = true},
	{id = 2195, name = "pair of boots of haste", article = "a", count = 1, rarity = "3", veiled = true}
})
eq(table.concat(D, ", "), "100 gold coins, a great mana potion, {[Rare] fire sword}, [Uncommon] knight armor, " ..
	"{[Legendary] knight armor}, {Ashbringer}, {[Magic] Veiled pair of boots of haste}",
	"stacks added up, singles with their article, rarity in [], {} from Magic, uniques, a rarity kept as text")
eq(#K.describe({}), 0, "an empty corpse: no entries")
eq(K.compose({stock = "Loot of a rat: a meat, 5 gold coins", items = {"5 gold coins"}}), "Loot of a rat: 5 gold coins.",
	"the corpse list replaces the stock list")
eq(K.compose({stock = "Loot of a rat: a meat", items = {}}), "Loot of a rat: nothing.", "all thinned away: nothing")
eq(K.compose({stock = "Loot of a rat: nothing (due to low stamina)", items = {}}),
	"Loot of a rat: nothing (due to low stamina).", "low stamina keeps its text")
eq(K.compose({stock = "Loot of a rat: a meat", items = {"a meat"}, bonus = {"an ember shard"}, upgrades = {{name = "meat", to = "Rare"}}}),
	"Loot of a rat: a meat.", "the corpse list: bonus items and raises are in it already, never twice")
eq(K.compose({monster = "a rat", items = {}}), nil, "no stock line and an empty corpse: nothing to say")
eq(K.compose({monster = "a rat", items = {"{Ashbringer}"}, pouch = "Looted: {Ashbringer}."}),
	"Loot of a rat: {Ashbringer}. Looted: {Ashbringer}.", "no stock line: the corpse list and the pouch part")

-- ---------------------------------------------------------------- L.addToCorpse
do
	local c = newCorpse(1, 20)
	local item, added = L.addToCorpse(c, 2148, 270)
	check(item ~= nil, "a stack of 270: made")
	eq(added, 270, "270 gold arrive (the engine cuts one addItem to 100)")
	eq(#c.items, 3, "in stacks of 100, 100, 70")
	eq(c.items[3].count, 70, "the last stack")
	local _, one = L.addToCorpse(c, 2392, 3)
	eq(one, 3, "three non-stackables are three items")
	local full = newCorpse(1, 1)
	full:addItem(2148, 5)
	local u, n = L.addToCorpse(full, 2400, 1)
	check(u ~= nil and n == 1, "a full corpse: the item goes in past its size (FLAG_NOLIMIT), not lost")
	eq(#full.items, 2, "the corpse holds it")
end

-- ---------------------------------------------------------------- the display scale never touches loot
-- (owner hint 2026-10-21: "inflação de números" could show loot counts x the level factor). The engine scales only the
-- damage and heal message types (src-patch 0037 ProtocolGame::sendTextMessage) and, in them, only numbers before
-- " hitpoint", " mana", " energy shield" or " health"; MESSAGE_LOOT passes as it is. The Lua sites scale no loot field.
do
	local patch = io.open("src-patches/0037-display-scale.patch", "r")
	local text = patch and patch:read("*a") or ""
	if patch then patch:close() end
	local switch = text:match("switch %(message%.type%) {(.-)default:")
	check(switch ~= nil, "the patch's message type switch")
	for _, mode in ipairs({"MESSAGE_LOOT", "MESSAGE_INFO_DESCR", "MESSAGE_STATUS"}) do
		check(switch and not switch:find(mode, 1, true), mode .. " is not scaled by the engine")
	end
	check(text:find('{" hitpoint", " mana", " energy shield", " health"}', 1, true) ~= nil,
		"only hitpoint / mana / energy shield / health numbers are scaled in a text")
	dofile("data/scripts/chaos/display_scale_core.lua")
	local DS = ChaosDisplayScale
	for _, site in ipairs({"lootLine", "loot", "lootfilter", "pouches", "autoloot", "lootFeed"}) do
		check(DS[site] == nil, "no display scale site for " .. site)
	end
end

print(string.format("lootline_corpse_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/craft_bonus_test.lua (and lua5.3; CI runs both)
-- Crafting bonus: the pure rules of craft_bonus_core.lua with the real craft_bonus_config.lua (rarity odds of crafted
-- equipment by mastery, the caps against boss drops and the item level gates, the item level, the rolls; the extra
-- pieces of potions and runes; the texts), then craft_bonus.lua against a mocked engine (which products count, the odds
-- the window gets, make and finish, extra pieces that do not fit going to the store inbox).
dofile("data/lib/chaos_item_mods.lua")
dofile("data/scripts/chaos/craft_bonus_core.lua")
local K = ChaosCraftBonusCore
local cfg = dofile("data/scripts/chaos/craft_bonus_config.lua")
local loot = dofile("data/scripts/chaos/loot_config.lua")
local M = ChaosItemMods

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(c, m)
	checks = checks + 1
	if not c then
		error(m or "check", 2)
	end
end
local function near(a, b, tol, m)
	checks = checks + 1
	if math.abs(a - b) > tol then
		error((m or "") .. ": " .. tostring(a) .. " not near " .. tostring(b), 2)
	end
end
local function oddsOf(rows, key)
	local out = {}
	for _, r in ipairs(rows) do
		out[r[key]] = r.pct
	end
	return out
end

-- a fixed sequence of rolls
local function seq(list)
	local i = 0
	return function()
		i = i + 1
		return list[i]
	end
end
-- a small deterministic generator (same numbers under LuaJIT and Lua 5.3)
local function lcg(seed)
	local s = seed
	return function(a, b)
		s = (s * 1103515245 + 12345) % 2147483648
		return a + s % (b - a + 1)
	end
end

-- ---------------------------------------------------------------- config sanity
local last = math.huge
for i, o in ipairs(cfg.gear.odds) do
	eq(o.rarity, i, "rarity rows in order")
	ok(o.chance < last, "a better rarity is rarer")
	last = o.chance
end
ok(cfg.gear.maxRarity < loot.gear.minRarity.boss, "crafting tops out below a boss drop's floor")
ok(cfg.gear.maxRarity <= loot.gear.minRarity.legendary, "and no higher than a legendary monster's floor")
ok(cfg.gear.itemLevel.max < M.config.tierLevels[6], "crafted gear never reaches the T6 gate")
ok(cfg.gear.itemLevel.max < M.config.itemLevel.worldBoss, "nor a world boss's item level")
for _, s in ipairs(cfg.yield.steps) do
	ok(s.max <= 25 and s.mult <= 1, "yield steps stay small")
end
for cat, skill in pairs(cfg.skills) do
	ok(skill >= 7 and skill <= 13, "a crafting skill for " .. cat)
end

-- ---------------------------------------------------------------- mastery and gear odds
eq(K.mastery(30, 20), 0, "below the recipe: mastery 0")
eq(K.mastery(30, 45), 15, "mastery")
eq(K.gearMult(cfg, 0), 1, "no bonus at mastery 0")
near(K.gearMult(cfg, 20), 1.2, 1e-9, "+1% per point")
eq(K.gearMult(cfg, 500), 1.5, "capped at +50%")

local o0 = oddsOf(K.gearOdds(cfg, 30, 30), "rarity")
eq(o0[1], 12, "Common at mastery 0")
eq(o0[3], 3, "Magic at mastery 0")
eq(o0[4], 1.2, "Rare at mastery 0")
eq(o0[5], nil, "nothing above Rare: a craft never gives Legendary or Divine")
eq(K.gearOdds(cfg, 30, 30)[1].rarity, 4, "best rarity first")
local oMax = oddsOf(K.gearOdds(cfg, 10, 400), "rarity")
eq(oMax[1], 18, "Common at the cap")
eq(oMax[4], 1.8, "Rare at the cap")
local total = 0
for _, p in pairs(oMax) do
	total = total + p
end
ok(total <= cfg.gear.maxTotal, "the cap holds: " .. total)
ok(total < 50, "mostly a plain item even at the cap")

-- maxTotal shrinks every chance by the same factor
local tight = {gear = {odds = {{rarity = 1, chance = 30}, {rarity = 2, chance = 10}}, perPoint = 0, maxBonus = 0,
	maxRarity = 5, maxTotal = 20, itemLevel = cfg.gear.itemLevel}}
local ot = oddsOf(K.gearOdds(tight, 1, 1), "rarity")
eq(ot[1], 15, "scaled to the total cap")
eq(ot[2], 5, "scaled to the total cap (2)")
-- maxRarity cuts rows
local capped = {gear = {odds = {{rarity = 5, chance = 1}, {rarity = 6, chance = 1}}, perPoint = 0, maxBonus = 0,
	maxRarity = 5, maxTotal = 50, itemLevel = cfg.gear.itemLevel}}
eq(#K.gearOdds(capped, 1, 1), 1, "a rarity above maxRarity never rolls")

-- ---------------------------------------------------------------- item level
eq(K.itemLevel(cfg, 30, 30, 1), 30, "recipe level at mastery 0")
eq(K.itemLevel(cfg, 30, 10, 1), 30, "under the recipe's skill: the recipe level")
eq(K.itemLevel(cfg, 30, 100, 1), 65, "half the mastery on top")
eq(K.itemLevel(cfg, 35, 400, 1), cfg.gear.itemLevel.max, "capped")
eq(K.itemLevel(cfg, 10, 10, 40), 40, "never below the item type's own level")
eq(K.itemLevel(cfg, 10, 10, 140), cfg.gear.itemLevel.max, "the type level is capped too")

-- ---------------------------------------------------------------- gear rolls
-- at mastery 0 the summed odds are Rare 1.2, Magic 4.2, Uncommon 10.2, Common 22.2 (x 1000 units)
eq(K.rollGear(cfg, 30, 30, seq({1200})), 4, "roll 1200: Rare")
eq(K.rollGear(cfg, 30, 30, seq({1201})), 3, "roll 1201: Magic")
eq(K.rollGear(cfg, 30, 30, seq({4200})), 3, "roll 4200: Magic")
eq(K.rollGear(cfg, 30, 30, seq({22200})), 1, "roll 22200: Common")
eq(K.rollGear(cfg, 30, 30, seq({22201})), 0, "roll 22201: plain")
eq(K.rollGear(cfg, 30, 30, seq({100000})), 0, "roll 100000: plain")
local rand, counts, N = lcg(7), {[0] = 0, 0, 0, 0, 0, 0}, 200000
for _ = 1, N do
	local r = K.rollGear(cfg, 30, 30, rand)
	counts[r] = counts[r] + 1
end
near(counts[1] * 100 / N, 12, 0.4, "Common rate")
near(counts[3] * 100 / N, 3, 0.2, "Magic rate")
near(counts[4] * 100 / N, 1.2, 0.15, "Rare rate")
near(counts[0] * 100 / N, 77.8, 0.5, "plain rate")

-- ---------------------------------------------------------------- tools
ok(K.isTool(cfg, "other", 48), "hands only: a tool")
ok(K.isTool(cfg, "other", 16), "one hand: a tool")
ok(not K.isTool(cfg, "other", 32816), "gloves and belts (own slot bit): equipment")
ok(not K.isTool(cfg, "other", 560), "the ammo slot: equipment")
ok(not K.isTool(cfg, "weapon", 48), "a weapon is no tool")

-- ---------------------------------------------------------------- potions and runes
ok(K.isYieldId(cfg, 28076), "exalted health potion")
ok(K.isYieldId(cfg, 28091), "mythic spirit potion")
ok(not K.isYieldId(cfg, 29550), "the flasks sold to NPCs are no potions here")
ok(not K.isYieldId(cfg, 26713), "a tool is not")
local y0 = K.yieldOdds(cfg, 15, 15, 5)
eq(#y0, 1, "mastery 0: only +50%")
eq(y0[1].extra, 3, "+50% of 5 rounds up")
eq(y0[1].pct, 5, "+50% at 5%")
local y50 = oddsOf(K.yieldOdds(cfg, 15, 65, 5), "extra")
eq(y50[5], 4, "double at mastery 50")
eq(y50[3], 17.5, "+50% at mastery 50")
local yMax = oddsOf(K.yieldOdds(cfg, 15, 400, 50), "extra")
eq(yMax[50], 8, "double capped")
eq(yMax[25], 25, "+50% capped")
eq(K.yieldOdds(cfg, 15, 400, 50)[1].extra, 50, "best first")
eq(K.rollYield(cfg, 15, 65, 5, seq({4000})), 5, "roll 4000: double")
eq(K.rollYield(cfg, 15, 65, 5, seq({4001})), 3, "roll 4001: +50%")
eq(K.rollYield(cfg, 15, 65, 5, seq({21500})), 3, "roll 21500: +50%")
eq(K.rollYield(cfg, 15, 65, 5, seq({21501})), 0, "roll 21501: none")
near(K.yieldMean(cfg, 15, 400, 5), 0.08 * 5 + 0.25 * 3, 1e-9, "mean extra at the cap")
local yr, extra = lcg(11), 0
for _ = 1, N do
	extra = extra + K.rollYield(cfg, 15, 65, 5, yr)
end
near(extra / N, K.yieldMean(cfg, 15, 65, 5), 0.02, "rolled mean")

-- ---------------------------------------------------------------- texts
eq(K.plural("Exalted Health Potion"), "Exalted Health Potions", "plural")
eq(K.plural("Glass"), "Glasses", "plural -s")
eq(K.plural("Ruby"), "Rubies", "plural -y")
eq(K.article("Epic Axe"), "an", "an") -- any word starting with a vowel
eq(K.article("Rare Axe"), "a", "a")
eq(K.gearText("Steel Axe", "Rare", 32), "You crafted a Rare Steel Axe (item level 32).", "gear text")
eq(K.gearText("Epee", nil, 10), "You crafted an Epee (item level 10).", "plain gear text")
eq(K.yieldText("Exalted Health Potion", 7, 2, 0), "You crafted 7 Exalted Health Potions (bonus +2).", "yield text")
eq(K.yieldText("Exalted Health Potion", 5, 0, 0), "You crafted 5 Exalted Health Potions.", "no bonus")
eq(K.yieldText("Fire Rune", 1, 0, 0), "You crafted a Fire Rune.", "one piece")
ok(K.yieldText("X", 10, 5, 5):find("5 went to your store inbox", 1, true) ~= nil, "inbox text")

-- ---------------------------------------------------------------- craft_bonus.lua on a mocked engine
local types = {
	[2519] = {name = "crown shield", gear = true, req = 0},
	[7000] = {name = "high blade", gear = true, req = 300},
	[28076] = {name = "Exalted Health Potion"},
	[2268] = {name = "sudden death rune", rune = true},
	[26713] = {name = "apprentice's scissor"},
	[26589] = {name = "apprentice's axe", gear = true, slot = 48},
	[29577] = {name = "shadowwoven gloves", gear = true, slot = 32816},
}
function ItemType(id)
	local t = types[id] or {name = "item " .. id}
	return {
		getName = function() return t.name end,
		isRune = function() return t.rune == true end,
		getMinReqLevel = function() return t.req or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
	}
end
local createdLog = {}
ChaosCrafting = {
	isGear = function(item) return (types[item:getId()] or {}).gear == true end,
	createItem = function(id, rarity, level)
		local it = {id = id, rarity = rarity, level = level}
		createdLog[#createdLog + 1] = it
		return it
	end,
	rarityName = function(r) return ChaosRarity.name(r) end,
}
local sockets = 0
ChaosGems = {rollDropSockets = function() sockets = sockets + 1 return 1 end}
local bag = {}
local room = 1000
Chaos = {giveItem = function(_, id, n)
	local k = math.min(n, room)
	bag[id] = (bag[id] or 0) + k
	room = room - k
	return k
end}
INDEX_WHEREEVER, FLAG_NOLIMIT = -1, 1
local inboxGot = {}
local player = {skill = 30}
function player:getEffectiveSkillLevel(s) self.asked = s return self.skill end
function player:getInbox()
	return {addItem = function(_, id, n) inboxGot[#inboxGot + 1] = {id, n} end}
end
dofile("data/scripts/chaos/craft_bonus.lua")
local B = ChaosCraftBonus

local shield = {id = 2519, name = "Crown Shield", level = 10, count = 1}
local potion = {id = 28076, name = "Exalted Health Potion", level = 15, count = 5}
eq(B.kind(shield), "gear", "a shield is equipment")
eq(B.kind(potion), "stack", "a potion yields more")
eq(B.kind({id = 2268, count = 3, level = 10}), "stack", "a rune yields more")
eq(B.kind({id = 26713, count = 1, level = 10}), nil, "a material: the stock way")
eq(B.kind({id = 26589, count = 1, level = 10}), nil, "a profession tool (hands only): the stock way")
eq(B.kind({id = 29577, count = 1, level = 10}), "gear", "gloves are equipment")
eq(B.kind({id = 2519, count = 2, level = 10}), nil, "two pieces of equipment: the stock way")
eq(B.kind("junk"), nil, "junk")

local od = B.odds(player, "armorsmith", shield)
eq(player.asked, 11, "armorsmith skill asked")
eq(od.kind, "gear", "gear odds")
eq(od.level, 20, "item level: recipe 10 + mastery 20 / 2")
eq(od.odds[1].name, "Rare", "odds carry the names")
near(od.odds[#od.odds].pct, 14.4, 1e-9, "Common at mastery 20")
local hi = B.odds(player, "weaponsmith", {id = 7000, name = "High Blade", level = 10, count = 1})
eq(hi.level, B.typeLevel(7000), "a high level type keeps its own item level")
ok(hi.level > 20, "type level used: " .. hi.level)
local po = B.odds(player, "herbalist", potion)
eq(po.kind, "stack", "stack odds")
eq(po.odds[1].extra, 5, "double of 5")
eq(B.odds(player, "generalcrafting", {id = 26713, count = 1, level = 10}), nil, "no odds for a tool")

B.random = seq({1})
local made = B.make(player, "armorsmith", shield, 30)
eq(made.kind, "gear", "made gear")
eq(made.rarity, 4, "roll 1: Rare")
eq(made.item.level, 20, "forged at the item level")
eq(createdLog[#createdLog].rarity, 4, "ChaosCrafting.createItem with the rarity")
eq(sockets, 1, "sockets rolled for a rarity")
eq(B.finish(player, shield, made), "You crafted a Rare Crown Shield (item level 20).", "gear finish text")
B.random = seq({99999})
made = B.make(player, "armorsmith", shield, 30)
eq(made.rarity, 0, "plain")
eq(sockets, 1, "no sockets for a plain piece")
eq(B.finish(player, shield, made), "You crafted a Crown Shield (item level 20).", "plain finish text")

player.skill = 65
B.random = seq({1})
made = B.make(player, "herbalist", potion, nil)
eq(made.kind, "stack", "made stack")
eq(made.extra, 5, "double")
eq(made.item, nil, "the base script makes the recipe's own count")
eq(B.finish(player, potion, made), "You crafted 10 Exalted Health Potions (bonus +5).", "stack finish text")
eq(bag[28076], 5, "extra pieces in the backpack")
room = 2
B.random = seq({1})
made = B.make(player, "herbalist", potion, 65)
local text = B.finish(player, potion, made)
eq(bag[28076], 7, "what fits goes to the backpack")
eq(inboxGot[1] and inboxGot[1][2], 3, "the rest to the store inbox")
ok(text:find("3 went to your store inbox", 1, true) ~= nil, "inbox told: " .. text)

print("craft_bonus_test: " .. checks .. " checks passed")
for _, s in ipairs({15, 40, 65, 90, 115}) do
	local g = oddsOf(K.gearOdds(cfg, 15, s), "rarity")
	local y = oddsOf(K.yieldOdds(cfg, 15, s, 5), "extra")
	print(string.format("  recipe 15, skill %3d: ilvl %2d  Common %.2f Uncommon %.2f Magic %.2f Rare %.2f | x5: +3 %.2f%% +5 %.2f%%",
		s, K.itemLevel(cfg, 15, s, 1), g[1] or 0, g[2] or 0, g[3] or 0, g[4] or 0, y[3] or 0, y[5] or 0))
end

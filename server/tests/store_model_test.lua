-- Run from the server/ folder: luajit tests/store_model_test.lua (and lua5.3; CI runs both)
-- tools/store_model.lua (O140): the real configs pass every rule, and each rule fails when its number is broken (a copy of
-- the config is changed in memory and put back).
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

ChaosStoreModelLib = true
local M = dofile("tools/store_model.lua")
local env = M.load()

local function has(problems, text)
	for _, p in ipairs(problems) do
		if p:find(text, 1, true) then return true end
	end
	return false
end

-- a change that must produce a problem containing `text`, restored afterwards
local function breaks(label, text, change)
	local undo = change()
	local problems = M.problems(env)
	undo()
	check(has(problems, text), label .. " is caught (" .. text .. ")")
end

local base = M.problems(env)
for _, p in ipairs(base) do print("problem: " .. p) end
check(#base == 0, "the real store passes every rule")

local function offer(pred)
	for _, o in ipairs(env.offers) do
		if pred(o) then return o end
	end
end

-- the stash room (O316)
local slotOne, slotPack = env.byKey["service:pactExtra:stashSlots"], env.byKey["service:pactExtra:stashSlots:4"]
check(slotOne ~= nil and slotPack ~= nil, "the single expansion and the pack are offers")
breaks("an expansion too dear per slot", "coins per slot", function() local v = slotOne.cost; slotOne.cost = 200; return function() slotOne.cost = v end end)
breaks("an expansion too cheap per slot", "coins per slot", function() local v = slotOne.cost; slotOne.cost = 10; return function() slotOne.cost = v end end)
breaks("a pack dearer than the singles", "not cheaper", function() local v = slotPack.cost; slotPack.cost = 220; return function() slotPack.cost = v end end)
breaks("a pack with too deep a discount", "% off", function() local v = slotPack.cost; slotPack.cost = 100; return function() slotPack.cost = v end end)
local orbsTab = env.byKey["service:pactExtra:stashOrbs"]
breaks("an affinity tab dearer than the expansion per entry", "per entry", function() local v = orbsTab.cost; orbsTab.cost = 300; return function() orbsTab.cost = v end end)
breaks("an old tab worth more than it cost", "old tab converts", function() local v = env.stash.slots.legacyPacksPerTab; env.stash.slots.legacyPacksPerTab = 5; return function() env.stash.slots.legacyPacksPerTab = v end end)
breaks("a bigger free room", "one tab of 30", function() local v = env.stash.slots.free; env.stash.slots.free = 100; return function() env.stash.slots.free = v end end)

-- coin packs
local pack = env.coins.packs[3]
breaks("a pack USD price off .98", "does not end in", function() local v = pack.usdCents; pack.usdCents = 1000; return function() pack.usdCents = v end end)
breaks("a bonus above 20%", "bonus 25%", function() local v = pack.bonusPct; pack.bonusPct = 25; return function() pack.bonusPct = v end end)
breaks("a bonus that falls", "bonus falls", function() local v = env.coins.packs[4].bonusPct; env.coins.packs[4].bonusPct = 0; return function() env.coins.packs[4].bonusPct = v end end)
local small = env.coins.packs[2]
breaks("a base pack off the base rate", "base rate is", function() local v = small.coins; small.coins = 300; return function() small.coins = v end end)
local starter = env.coins.packs[#env.coins.packs]
breaks("a starter pack worth too much", "starter pack gives", function() local v = starter.bonusCoins; starter.bonusCoins = 600; return function() starter.bonusCoins = v end end)

-- supplies and the gold loop
local pot = offer(function(o) return o.kind == "item" and o.id == 26031 and o.count == 100 end)
breaks("a potion pack far below its gold", "gold per coin", function() local v = pot.cost; pot.cost = 10; return function() pot.cost = v end end)
breaks("a potion pack far above its gold", "gold per coin", function() local v = pot.cost; pot.cost = 300; return function() pot.cost = v end end)

-- boosts
local xpOffers = {}
for _, o in ipairs(env.offers) do
	if o.kind == "item" and o.id == 28095 then xpOffers[#xpOffers + 1] = o end
end
check(#xpOffers == 2, "two Double Experience Potion offers")
for _, o in ipairs(xpOffers) do check(o.weeklyLimit and o.weeklyLimit > 0, o.name .. " has a weekly limit") end
breaks("no weekly limit on the potion", "no weekly limit", function() local v = xpOffers[1].weeklyLimit; xpOffers[1].weeklyLimit = nil; return function() xpOffers[1].weeklyLimit = v end end)
breaks("too many potion hours a week", "hours of x2 a week", function() local v = xpOffers[2].weeklyLimit; xpOffers[2].weeklyLimit = 6; return function() xpOffers[2].weeklyLimit = v end end)
breaks("a deep pack discount", "off the single", function() local v = xpOffers[2].cost; xpOffers[2].cost = 150; return function() xpOffers[2].cost = v end end)
breaks("a bigger world buff", "bonus", function() local v = env.worldBuffs.xp.bonus; env.worldBuffs.xp.bonus = 0.5; return function() env.worldBuffs.xp.bonus = v end end)
breaks("a bigger experience cap", "xp cap", function() local v = env.xpcap.cap; env.xpcap.cap = 8; return function() env.xpcap.cap = v end end)

-- services
local reset = offer(function(o) return o.service == "passiveReset" end)
breaks("a passive reset far below its gold", "Passive Tree Reset", function() local v = reset.cost; reset.cost = 40; return function() reset.cost = v end end)
local eternal = offer(function(o) return o.service == "eternalBlessing" end)
breaks("an Eternal Blessing too dear", "Eternal Blessing", function() local t = eternal.levelPrices[3]; local v = t.cost; t.cost = 1500; return function() t.cost = v end end)

-- cosmetics and bundles
local frame = offer(function(o) return o.kind == "frame" end)
breaks("a static frame dearer than wings", "static frame", function() local v = frame.cost; frame.cost = 300; return function() frame.cost = v end end)
local novice = offer(function(o) return o.key == "starter:novice" end)
breaks("a starter pack with a deep discount", "off its parts", function() local v = novice.cost; novice.cost = 100; return function() novice.cost = v end end)
local pactPart
for _, p in ipairs(novice.parts) do
	if type(p) == "table" and p.kind == "pact" then pactPart = p end
end
breaks("Pact days at the wrong price", "of the Pact listed at", function() local v = pactPart.cost; pactPart.cost = 90; return function() pactPart.cost = v end end)

-- exercise weapons (O150): coins per hunting hour saved
local lasting = offer(function(o) return o.kind == "item" and o.name == "Lasting Exercise Melee Weapon (14400)" end)
local small500 = offer(function(o) return o.kind == "item" and o.name == "Exercise Rod (500)" end)
breaks("a lasting exercise weapon far too cheap", "coins per hunting hour", function() local v = lasting.cost; lasting.cost = 60; return function() lasting.cost = v end end)
breaks("an exercise rod far too dear", "Double Experience Potion", function() local v = small500.cost; small500.cost = 300; return function() small500.cost = v end end)
breaks("a deep tier discount", "cheaper per charge", function() local v = small500.cost; small500.cost = 40; return function() small500.cost = v end end)

-- O317 (owner 2026-10-29): Pacto Completo, the Pact and Premium prices, Blessings by level, potion packs, Lasting weapons,
-- the account discount, the Remote Stash Deposit, Pact Marks
local c30, c90, c180 = env.byKey["complete:30"], env.byKey["complete:90"], env.byKey["complete:180"]
check(c30 and c90 and c180, "three Pacto Completo offers")
check(c30.cost == 499 and c90.cost == 1350 and c180.cost == 2500, "the Completo is 499 / 1350 / 2500")
local pactOffer = offer(function(o) return o.service == "pact" end)
local p30o, p90o, p180o = env.byKey["premium:30"], env.byKey["premium:90"], env.byKey["premium:180"]
check(pactOffer.cost == 299 and p30o.cost == 299, "the Pact and a month of Premium are 299 each")
check(p90o.cost == 800 and p180o.cost == 1500, "Premium 90 / 180 days are 800 / 1500")
breaks("a Completo month too dear", "monthly target", function() local v = c30.cost; c30.cost = 560; return function() c30.cost = v end end)
breaks("a Completo month as dear as both apart", "less than both apart", function() local v = c30.cost; c30.cost = 598; return function() c30.cost = v end end)
breaks("a Completo no better than Premium alone", "clearly better", function() local v = c90.cost; c90.cost = 1550; return function() c90.cost = v end end)
breaks("a Completo with a deep discount", "off buying both apart", function() local v = c180.cost; c180.cost = 2300; return function() c180.cost = v end end)
breaks("Premium 90 days nearly as good as the Completo", "clearly better", function() local v = p90o.cost; p90o.cost = 740; return function() p90o.cost = v end end)
breaks("a Completo part at the wrong Pact price", "listed at", function() local v = c30.parts[1].cost; c30.parts[1].cost = 400; return function() c30.parts[1].cost = v end end)
breaks("a Completo that cannot be gifted", "not giftable", function() local v = c30.gift; c30.gift = false; return function() c30.gift = v end end)
breaks("a Completo pact part that is not giftable", "marked giftable", function() local v = c30.parts[1].giftable; c30.parts[1].giftable = nil; return function() c30.parts[1].giftable = v end end)
breaks("a Completo pact part that is not required", "not required", function() local v = c30.parts[1].required; c30.parts[1].required = nil; return function() c30.parts[1].required = v end end)
local bless = offer(function(o) return o.service == "blessings" end)
check(bless.levelPrices and #bless.levelPrices == 3, "All Blessings has three level tiers")
check(bless.levelPrices[1].cost == 60 and bless.levelPrices[1].upTo == 200, "60 coins up to level 200")
check(bless.levelPrices[2].cost == 100 and bless.levelPrices[2].upTo == 500, "100 coins up to level 500")
check(bless.levelPrices[3].cost == 150 and bless.levelPrices[3].upTo == nil, "150 coins above")
check(env.K.levelCost(bless, 1) == 60 and env.K.levelCost(bless, 200) == 60 and env.K.levelCost(bless, 201) == 100 and
	env.K.levelCost(bless, 500) == 100 and env.K.levelCost(bless, 501) == 150 and env.K.levelCost(bless, 2000) == 150, "the price at each level")
breaks("a blessing tier far under its gold", "cheaper than", function() local v = bless.levelPrices[3].cost; bless.levelPrices[3].cost = 90; return function() bless.levelPrices[3].cost = v end end)
breaks("blessing tiers that do not rise", "not dearer", function() local v = bless.levelPrices[2].cost; bless.levelPrices[2].cost = 60; return function() bless.levelPrices[2].cost = v end end)
check(eternal.levelPrices and #eternal.levelPrices == 3 and eternal.cost == 300, "the Eternal Blessing has three level tiers, from 300")
check(eternal.levelPrices[1].cost == 300 and eternal.levelPrices[1].upTo == 200, "300 coins up to level 200")
check(eternal.levelPrices[2].cost == 500 and eternal.levelPrices[2].upTo == 500, "500 coins up to level 500")
check(eternal.levelPrices[3].cost == 750 and eternal.levelPrices[3].upTo == nil, "750 coins above")
breaks("an Eternal Blessing too cheap for the top tier", "tier 3", function() local t = eternal.levelPrices[3]; local v = t.cost; t.cost = 450; return function() t.cost = v end end)
breaks("an Eternal Blessing too cheap for the first tier", "tier 1", function() local t = eternal.levelPrices[1]; local v = t.cost; t.cost = 120; return function() t.cost = v end end)
breaks("an Eternal Blessing with fewer tiers", "price tiers", function() local v = eternal.levelPrices; eternal.levelPrices = {{upTo = 200, cost = 300}, {cost = 750}}; return function() eternal.levelPrices = v end end)
breaks("an Eternal Blessing cost that is not its first tier", "first tier", function() local v = eternal.cost; eternal.cost = 310; return function() eternal.cost = v end end)
local ult = offer(function(o) return o.kind == "item" and o.id == 26029 and o.count == 100 end)
local sup = offer(function(o) return o.kind == "item" and o.id == 26031 and o.count == 100 end)
local uhp = offer(function(o) return o.kind == "item" and o.id == 8473 and o.count == 100 end)
local gpc = function(o) return M.askOf(env, o.id) * o.count / o.cost end
check(uhp.cost == 27 and ult.cost == 33 and sup.cost == 42, "ultimate health 27, ultimate mana 33, supreme health 42 for 100")
check(gpc(uhp) >= 1000 and gpc(uhp) <= 1250 and gpc(ult) >= 1000 and gpc(ult) <= 1250 and gpc(sup) >= 1000 and gpc(sup) <= 1250, "100 packs at about 1000-1250 gold a coin")
breaks("an ultimate pack under its new price", "gold per coin", function() local v = ult.cost; ult.cost = 24; return function() ult.cost = v end end)
local lastingOffers = {}
for _, o in ipairs(env.offers) do
	if o.kind == "item" and o.name and o.name:find("Lasting Exercise", 1, true) then lastingOffers[#lastingOffers + 1] = o end
end
check(#lastingOffers == 6, "six Lasting Exercise weapons")
for _, o in ipairs(lastingOffers) do check(o.weeklyLimit == 2 and o.weeklyGroup == "lastingExercise", o.name .. ": 2 a week, one shared group") end
breaks("a Lasting weapon without a limit", "weekly limit", function() local v = lastingOffers[1].weeklyLimit; lastingOffers[1].weeklyLimit = nil; return function() lastingOffers[1].weeklyLimit = v end end)
breaks("a Lasting weapon with a bigger limit", "weekly limit", function() local v = lastingOffers[2].weeklyLimit; lastingOffers[2].weeklyLimit = 5; return function() lastingOffers[2].weeklyLimit = v end end)
breaks("a Lasting weapon outside the shared limit", "weeklyGroup", function() local v = lastingOffers[3].weeklyGroup; lastingOffers[3].weeklyGroup = nil; return function() lastingOffers[3].weeklyGroup = v end end)
local rs = env.byKey["service:pactExtra:stashRemote"]
check(rs.cost == 400, "Remote Stash Deposit is 400 coins")
breaks("a Remote Stash Deposit under a month of Pact", "Remote Stash Deposit", function() local v = rs.cost; rs.cost = 250; return function() rs.cost = v end end)
breaks("a Remote Stash Deposit above the Auto Seller", "Remote Stash Deposit", function() local v = rs.cost; rs.cost = 600; return function() rs.cost = v end end)
local lootBag = env.byKey["service:pouch:loot"]
check(lootBag.accountDiscount == 50, "the Loot Bag is half price for another character")
breaks("a deeper account discount", "account discount", function() local v = lootBag.accountDiscount; lootBag.accountDiscount = 70; return function() lootBag.accountDiscount = v end end)
breaks("a convenience without the account discount", "without the account discount", function() local v = lootBag.accountDiscount; lootBag.accountDiscount = nil; return function() lootBag.accountDiscount = v end end)
local shelf1 = env.pact.marks.shelf[1]
breaks("a Marks shelf item cheaper than its coins", "Marks shelf", function() local v = shelf1.marks; shelf1.marks = 100; return function() shelf1.marks = v end end)
breaks("a Marks shelf item that is not a cosmetic", "no cosmetic", function() local v = shelf1.key; shelf1.key = "premium:30"; return function() shelf1.key = v end end)
breaks("the Pact paying coins again", "Chaos Coins a day", function() env.pact.pact.dailyCoins = 5; return function() env.pact.pact.dailyCoins = nil end end)
local mon1 = env.pact.marks.monthly[1]
breaks("a monthly Marks cosmetic cheaper than its coins", "Marks shelf", function() local v = mon1.marks; mon1.marks = 100; return function() mon1.marks = v end end)
breaks("a monthly Marks cosmetic that does not exist", "no cosmetic", function() local v = mon1.key; mon1.key = "foot_nobody"; return function() mon1.key = v end end)
breaks("a monthly Marks cosmetic that is a spell effect", "changes a spell", function() local v = mon1.key; mon1.key = "skin_warrior_void"; mon1.marks = 250; return function() mon1.key = v; mon1.marks = 200 end end)
breaks("a monthly Marks cosmetic from the fixed shelf", "fixed shelf", function() local v = mon1.key; mon1.key = shelf1.key; return function() mon1.key = v end end)
breaks("a monthly rotation of two", "monthly rotation", function() local v = env.pact.marks.monthly; env.pact.marks.monthly = {v[1], v[2]}; return function() env.pact.marks.monthly = v end end)
breaks("too many Marks a day", "month of Marks", function() local v = env.pact.pact.dailyMarks; env.pact.pact.dailyMarks = 8; return function() env.pact.pact.dailyMarks = v end end)

-- Founder Pack (O322): two time-limited packs of cosmetics that never return, about R$ 50 and R$ 100
local fp, fg = env.byKey["founder:pack"], env.byKey["founder:grand"]
check(fp and fg and fp.cost == 499 and fg.cost == 999, "the Founder Packs are 499 and 999 coins")
breaks("a Founder Pack off its price anchor", "the anchor is 499", function() local v = fp.cost; fp.cost = 560; return function() fp.cost = v end end)
breaks("a grand pack at the first pack's price", "x the first", function() local v = fg.cost; fg.cost = 600; return function() fg.cost = v end end)
breaks("a Founder Pack that can be gifted", "must not be giftable", function() local v = fp.gift; fp.gift = nil; return function() fp.gift = v end end)
breaks("a Founder Pack bought twice", "once per account", function() local v = fp.oncePerAccount; fp.oncePerAccount = nil; return function() fp.oncePerAccount = v end end)
breaks("a Founder Pack without its window", "window differs", function() local v = fp.availableUntil; fp.availableUntil = nil; return function() fp.availableUntil = v end end)
breaks("a Founder Pack with an item in it", "neither a cosmetic piece nor Pact days", function()
	fp.parts[#fp.parts + 1] = {kind = "item", id = 7590, count = 100, cost = 50}
	return function() fp.parts[#fp.parts] = nil end end)
breaks("a Founder Pack with too many Pact days", "Pact days", function() local v = env.founder.tiers[1].pactDays; env.founder.tiers[1].pactDays = 30; return function() env.founder.tiers[1].pactDays = v end end)
breaks("a Founder Pack sold for too long", "days (", function() local v = env.founder["end"]; env.founder["end"] = "2027-03-01 15:00"; return function() env.founder["end"] = v end end)
breaks("a Founder piece that is not a cosmetic", "not a cosmetic", function()
	local e; for _, x in ipairs(env.exclusives.exclusives) do if x.key == "wings_gold_peacock" then e = x end end
	local v = e.kind; e.kind = "pet"; return function() e.kind = v end end)

-- the real numbers of O140
check(reset.cost == 100, "Passive Tree Reset is 100 coins")
check(frame.cost == 200, "plate frames are 200 coins")
check(xpOffers[1].weeklyLimit == 4 and xpOffers[2].weeklyLimit == 2, "4 singles and 2 packs of 5 a week")

if failures > 0 then
	print(string.format("store_model_test: %d of %d checks FAILED", failures, checks))
	os.exit(1)
end
print(string.format("store_model_test: %d checks OK", checks))

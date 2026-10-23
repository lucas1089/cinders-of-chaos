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
breaks("an Eternal Blessing too dear", "Eternal Blessing", function() local v = eternal.cost; eternal.cost = 1500; return function() eternal.cost = v end end)

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

-- the real numbers of O140
check(reset.cost == 100, "Passive Tree Reset is 100 coins")
check(frame.cost == 200, "plate frames are 200 coins")
check(xpOffers[1].weeklyLimit == 4 and xpOffers[2].weeklyLimit == 2, "4 singles and 2 packs of 5 a week")

if failures > 0 then
	print(string.format("store_model_test: %d of %d checks FAILED", failures, checks))
	os.exit(1)
end
print(string.format("store_model_test: %d checks OK", checks))

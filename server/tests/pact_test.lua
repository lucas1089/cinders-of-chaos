-- Run from the server/ folder: luajit tests/pact_test.lua (or lua5.3; CI runs both)
-- Chaos Pact and account storage (pact_core.lua with the real pact_config.lua): limits (free / Pact / extras, caps,
-- premium for the loot rules), stacking and its cap, the daily coins, one-time extras (the stash tabs themselves:
-- tests/stash_test.lua), saved build slots, character slots, and the store offers (shop_config.lua inserts them;
-- prices, keys, the coin drip below the price).
dofile("data/scripts/chaos/pact_core.lua")
local P = ChaosPactCore
local cfg = dofile("data/scripts/chaos/pact_config.lua")

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local DAY = 86400
local NOW = 1800000000
local L = cfg.limits

-- ---------------------------------------------------------------- limits
local free = {pactEnds = 0, extras = {}}
local pact = {pactEnds = NOW + 10 * DAY, extras = {}}
local ended = {pactEnds = NOW - 1, extras = {stashSlots = 2, buildSlots = 1}}
eq(P.active(free, NOW), false, "no Pact")
eq(P.active(pact, NOW), true, "Pact active")
eq(P.active(ended, NOW), false, "Pact ended")
eq(P.active(nil, NOW), false, "no state")
for key, l in pairs(L) do
	eq(P.limit(cfg, free, key, NOW), l.free, "free limit " .. key)
	eq(P.limit(cfg, pact, key, NOW), l.free + l.pact, "Pact limit " .. key)
end
eq(P.limit(cfg, ended, "stashSlots", NOW), L.stashSlots.free + 2, "bought expansions stay after the Pact")
eq(P.limit(cfg, ended, "buildSlots", NOW), L.buildSlots.free + 1, "bought build slot stays")
eq(P.limit(cfg, {pactEnds = 0, extras = {stashSlots = 99}}, "stashSlots", NOW), L.stashSlots.free + L.stashSlots.maxExtra, "extras capped at maxExtra")
eq(P.limit(cfg, {pactEnds = 0, extras = {stashSlots = -3}}, "stashSlots", NOW), L.stashSlots.free, "negative extras ignored")
-- O316: the retired extras are not limits any more and cannot be bought; the stash reads them as old tabs
eq(P.limit(cfg, {pactEnds = 0, extras = {stashTabs = 6, depotTabs = 12}}, "stashTabs", NOW), 0, "no stashTabs limit any more")
eq(L.stashTabs, nil, "no stashTabs limit") eq(L.depotTabs, nil, "no depotTabs limit")
check(P.extraCheck(cfg, free, "stashTabs") ~= nil, "Extra Stash Tab is not sold any more")
check(P.extraCheck(cfg, free, "depotTabs") ~= nil, "Extra Depot Tab is not sold any more")
check(P.extraCheck(cfg, free, "depotTabs", 4) ~= nil, "4 Depot Tabs are not sold any more")
eq(cfg.extras.stashTabs.retired, true, "stashTabs kept as a name only") eq(cfg.extras.depotTabs.retired, true, "depotTabs kept as a name only")
eq(P.limit(cfg, free, "nope", NOW), 0, "unknown limit")
-- premium alone gives the loot rule bonus (the base autoloot callback does too), not the other perks
local prem = {pactEnds = 0, extras = {}, premium = true}
eq(P.limit(cfg, prem, "lootRules", NOW), L.lootRules.free + L.lootRules.pact, "premium counts for loot rules")
eq(P.limit(cfg, prem, "stashSlots", NOW), L.stashSlots.free, "premium does not count for stash slots")
check(L.lootRules.free + L.lootRules.pact <= 20, "loot rules within the base callback's 20 storages")
-- character slots: bought (capped) + legacy (not capped)
local chars = {pactEnds = NOW + DAY, extras = {charSlots = 3, charSlotsLegacy = 4}}
eq(P.limit(cfg, chars, "charSlots", NOW), L.charSlots.free + 3 + 4, "character slots: bought + legacy, Pact adds none")
local rows = P.breakdown(cfg, ended, NOW)
eq(#rows, #cfg.order, "breakdown rows")
eq(rows[1].key, "stashSlots", "breakdown order")
eq(rows[1].extra, 2, "breakdown extra")
eq(rows[1].total, L.stashSlots.free + 2, "breakdown total")
eq(rows[1].pactActive, false, "breakdown Pact off")

-- ---------------------------------------------------------------- the Pact: stacking, cap
eq(P.extendPact(cfg, 0, NOW), NOW + cfg.pact.days * DAY, "first purchase")
eq(P.extendPact(cfg, NOW - 5 * DAY, NOW), NOW + cfg.pact.days * DAY, "after an ended Pact: from now")
eq(P.extendPact(cfg, NOW + 10 * DAY, NOW), NOW + (10 + cfg.pact.days) * DAY, "stacks on the time left")
local ends, err = P.extendPact(cfg, NOW + (cfg.pact.maxStackDays - cfg.pact.days + 1) * DAY, NOW)
check(ends == nil and type(err) == "string", "stacking cap refuses")
check(P.extendPact(cfg, NOW + (cfg.pact.maxStackDays - cfg.pact.days) * DAY, NOW) ~= nil, "stacking up to the cap")
eq(P.daysLeft(NOW + 10 * DAY, NOW), 10, "days left")
eq(P.daysLeft(NOW + 1, NOW), 1, "days left rounds up")
eq(P.daysLeft(NOW - 5, NOW), 0, "days left when over")

-- ---------------------------------------------------------------- daily Pact Marks (O317: they replace the daily coins)
local st = {pactEnds = NOW + DAY, lastClaim = 0, extras = {}}
eq(cfg.pact.dailyCoins, nil, "no daily Chaos Coins any more")
eq(cfg.pact.dailyMarks, 5, "5 Pact Marks a day")
eq(P.claim(cfg, st, NOW, 20270115), cfg.pact.dailyMarks, "claim")
st.lastClaim = 20270115
local amount, why = P.claim(cfg, st, NOW, 20270115)
check(amount == nil and why == cfg.messages.alreadyClaimed, "one claim a day")
eq(P.claim(cfg, st, NOW, 20270116), cfg.pact.dailyMarks, "next day")
amount, why = P.claim(cfg, {pactEnds = NOW - 1, lastClaim = 0}, NOW, 20270116)
check(amount == nil and why == cfg.messages.noPact, "no claim without the Pact")
local offer = cfg.store.pact.offers[1]
eq(offer.cost, 299, "the Pact is 299 coins (O317)")
check(cfg.pact.dailyMarks > 0, "a Marks drip")

-- ---------------------------------------------------------------- the Marks shelf: cosmetics only, never power or coins
local ccfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local cosOf = {}
for _, c in ipairs(ccfg.cosmetics) do cosOf[c.key] = c end
check(#cfg.marks.shelf >= 3 and #cfg.marks.shelf <= 8, "a small shelf")
local seenShelf = {}
local COSMETIC_KINDS = {lootbeam = true, chatcolor = true, killfx = true, footprint = true, outline = true}
for _, it in ipairs(cfg.marks.shelf) do
	local c = cosOf[it.key]
	check(c ~= nil, "shelf cosmetic exists: " .. it.key)
	check(not seenShelf[it.key], "shelf key once: " .. it.key) seenShelf[it.key] = true
	check(c and c.source == "store", "a shelf cosmetic is a store cosmetic: " .. it.key)
	check(c and COSMETIC_KINDS[c.kind], "a look, not a spell: " .. it.key)
	check(c and c.price and it.marks >= c.price and it.marks <= c.price * 1.5, "a Mark is worth about a coin: " .. it.key)
	-- a month of Pact Marks (150) buys at most about one cosmetic: nothing is cheaper in Marks than in coins
	check(it.marks >= cfg.pact.dailyMarks * 28, "at least four weeks of Marks: " .. it.key)
end
eq(P.shelfCheck(cfg, 150, {}, "loot_ember"), nil, "150 Marks buy an Ember Label")
check(P.shelfCheck(cfg, 149, {}, "loot_ember") ~= nil, "149 are not enough")
check(P.shelfCheck(cfg, 9999, {loot_ember = true}, "loot_ember") ~= nil, "owned: not twice")
for _, key in ipairs({"coins", "premium", "stamina", "service:blessings", "item:28095x1", "kill_voidring", "skin_warrior_void", "bogus", ""}) do
	check(P.shelfCheck(cfg, 99999, {}, key) == cfg.messages.marksNoItem, "Marks buy nothing off the shelf: " .. key)
end
-- no store offer takes Marks, and the Pact tables name the Marks table
for _, cat in pairs(cfg.store) do
	for _, o in ipairs(cat.offers) do
		check(o.marks == nil and o.cost ~= nil, "store offers cost coins only: " .. o.name)
	end
end
eq(cfg.tables.marks, "chaos_pact_marks", "Marks table") eq(cfg.tables.xp, "chaos_pact_xp", "experience table")
eq(P.monthExp({{month = 202611, exp = 500}, {month = 202610, exp = 900}, {month = 202611, exp = 250}}, 202611), 750, "the month's rows add up")
eq(P.monthExp({}, 202611), 0, "no rows") eq(P.monthExp(nil, 202611), 0, "no table")

-- ---------------------------------------------------------------- expiry warnings: 3 days, then 1 day
eq(cfg.pact.warnDays[1], 3, "first warning 3 days") eq(cfg.pact.warnDays[2], 1, "second warning 1 day")
eq(P.expiry(cfg, NOW + 10 * DAY, 0, NOW), nil, "10 days left: no warning")
eq(P.expiry(cfg, NOW + 4 * DAY, 0, NOW), nil, "4 days left: none yet")
local w = P.expiry(cfg, NOW + 3 * DAY, 0, NOW)
eq(w.level, 3, "3 days left: level 3") eq(w.days, 3, "3 days") eq(w.both, false, "the Pact alone")
w = P.expiry(cfg, NOW + 2 * DAY + 100, 0, NOW)
eq(w.level, 3, "2 days and a bit: still level 3") eq(w.days, 3, "rounded up")
w = P.expiry(cfg, NOW + DAY, 0, NOW)
eq(w.level, 1, "1 day left: level 1") eq(w.days, 1, "1 day")
w = P.expiry(cfg, NOW + 3600, 0, NOW)
eq(w.level, 1, "hours left: level 1")
eq(P.expiry(cfg, NOW - 1, 0, NOW), nil, "ended: no warning (the login line says it ended)")
eq(P.expiry(cfg, 0, 0, NOW), nil, "never had the Pact")
eq(P.expiry(cfg, NOW + 2 * DAY, 2, NOW).both, true, "the Pact and Premium end together: the Completo text")
eq(P.expiry(cfg, NOW + 2 * DAY, 40, NOW).both, false, "Premium runs on: the Pact alone")
eq(P.expiry(cfg, NOW + 2 * DAY, 0, NOW).both, false, "no premium days left is not a Completo")
-- a bundle's days stack with the same cap: 180 days on top of 190 is refused, 30 on top of 335 fits
eq(P.extendPact(cfg, NOW, NOW, 180), NOW + 180 * DAY, "a bundle of 180 days")
check(P.extendPact(cfg, NOW + 190 * DAY, NOW, 180) == nil, "180 days on 190 days left pass the cap (370)")
check(P.extendPact(cfg, NOW + 335 * DAY, NOW, 30) ~= nil, "30 days on 335 days left fit exactly")
check(P.extendPact(cfg, NOW + 336 * DAY, NOW, 30) == nil, "30 days on 336 days left do not")

-- ---------------------------------------------------------------- one-time extras
eq(P.extraCheck(cfg, free, "stashSlots"), nil, "an expansion can be bought")
check(P.extraCheck(cfg, {extras = {stashSlots = L.stashSlots.maxExtra}}, "stashSlots") ~= nil, "expansions capped")
check(P.extraCheck(cfg, {extras = {stashOrbs = 1}}, "stashOrbs") ~= nil, "special tab once")
check(P.extraCheck(cfg, free, "marketListings") ~= nil, "listings are not sold")
check(P.extraCheck(cfg, free, "bogus") ~= nil, "unknown extra")
-- packs (pact_config.lua sells 4 expansions at once): the whole pack must fit under maxExtra
eq(P.extraCheck(cfg, free, "stashSlots", 4), nil, "a pack of 4 expansions can be bought")
eq(P.extraCheck(cfg, {extras = {stashSlots = L.stashSlots.maxExtra - 4}}, "stashSlots", 4), nil, "a pack that just fits")
check(P.extraCheck(cfg, {extras = {stashSlots = L.stashSlots.maxExtra - 3}}, "stashSlots", 4) ~= nil, "a pack past the cap is refused")
eq(P.extraCheck(cfg, {extras = {stashSlots = L.stashSlots.maxExtra - 3}}, "stashSlots", 1), nil, "a single expansion still fits")
eq(P.limit(cfg, {pactEnds = NOW + DAY, extras = {}}, "stashSlots", NOW), L.stashSlots.free + L.stashSlots.pact, "Pact expansion")
eq(P.extraMax(cfg, "charSlots"), L.charSlots.maxExtra, "character slot max")
eq(P.extraMax(cfg, "stashGems"), 1, "special tab max")

-- remote stash deposit (stash_config.lua remoteDeposit): a limit of 0 free, lent by the Pact, bought once
eq(P.limit(cfg, {pactEnds = 0, extras = {}}, "stashRemote", NOW), 0, "remote deposit: free players have none")
eq(P.limit(cfg, {pactEnds = NOW + DAY, extras = {}}, "stashRemote", NOW), 1, "remote deposit: lent by the Pact")
eq(P.limit(cfg, {pactEnds = NOW - 1, extras = {}}, "stashRemote", NOW), 0, "remote deposit: gone when the Pact ends")
eq(P.limit(cfg, {pactEnds = 0, extras = {stashRemote = 1}}, "stashRemote", NOW), 1, "remote deposit: bought")
eq(P.limit(cfg, {pactEnds = NOW + DAY, extras = {stashRemote = 1}}, "stashRemote", NOW) > 0, true, "remote deposit: both")
eq(P.extraMax(cfg, "stashRemote"), 1, "remote deposit: bought once")
local scfgR = dofile("data/scripts/chaos/stash_config.lua").remoteDeposit
eq(scfgR.extra, "stashRemote", "the stash reads the same extra")
eq(scfgR.pact and cfg.limits.stashRemote.pact > 0, true, "the stash and the limit agree: the Pact lends it")

-- ---------------------------------------------------------------- saved builds
local limB = P.limits(cfg, {pactEnds = 0, extras = {}}, NOW)
eq(P.buildEditable(limB, 1), true, "slot 1 editable")
eq(P.buildEditable(limB, L.buildSlots.free + 1), false, "slot past the free count read-only")
eq(P.buildEditable(limB, 0), false, "slot 0")
eq(P.freeBuildSlot(limB, {{slot = 1}}), 2, "first free slot")
eq(P.freeBuildSlot(limB, {{slot = 1}, {slot = 2}, {slot = 5}}), nil, "no free editable slot (slot 5 kept, read-only)")
local limBP = P.limits(cfg, pact, NOW)
eq(P.freeBuildSlot(limBP, {{slot = 1}, {slot = 2}}), 3, "Pact slots")

-- ---------------------------------------------------------------- characters
eq(P.characterIndex({30, 10, 20}, 20), 2, "character index by id")
eq(P.characterIndex({30, 10, 20}, 99), 4, "unknown guid past the end")
eq(P.legacySlots(cfg, L.charSlots.free + 3, 0), 3, "legacy slots")
eq(P.legacySlots(cfg, L.charSlots.free + 3, 2), 1, "legacy slots minus owned")
eq(P.legacySlots(cfg, 2, 0), 0, "no legacy slots needed")
eq(cfg.characters.free, L.charSlots.free, "website free character count matches")
eq(cfg.characters.maxExtra, L.charSlots.maxExtra, "website character max matches")

-- ---------------------------------------------------------------- store offers
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29
local shop = dofile("data/scripts/chaos/shop_config.lua")
local found, keys = {}, {}
for _, cat in ipairs(shop.categories) do
	for _, o in ipairs(cat.offers) do
		if o.service == "pact" or o.service == "pactExtra" then
			found[#found + 1] = o
			check(type(o.cost) == "number" and o.cost > 0, "price of " .. o.name)
			check(type(o.key) == "string" and not keys[o.key], "stable unique key of " .. o.name)
			keys[o.key or ""] = true
			check(#o.description <= 84, "short description (two lines in the store) of " .. o.name)
			if o.service == "pactExtra" then
				check(cfg.extras[o.extra] ~= nil and P.extraMax(cfg, o.extra) > 0, "extra " .. tostring(o.extra) .. " can be bought")
			end
		end
	end
end
-- O316: the depot is retired, so no depot tab is sold: the store has the Pact and Storage & Slots offers only
eq(dofile("data/scripts/chaos/depot_config.lua").store, nil, "depot_config.lua sells nothing")
eq(#found, #cfg.store.pact.offers + #cfg.store.storage.offers, "every Pact and storage offer is in the store")
for _, o in ipairs(found) do
	check(o.extra ~= "stashTabs" and o.extra ~= "depotTabs", "no retired tab offer: " .. o.name)
	check(not o.name:lower():find("depot", 1, true), "no depot in " .. o.name)
end
for key, x in pairs(cfg.extras) do
	local sold = false
	for _, o in ipairs(found) do
		sold = sold or o.extra == key
	end
	check(sold or x.retired == true, "extra " .. key .. " is sold or retired")
	check(x.name ~= nil, "extra " .. key .. " has a name")
end
-- the affinity stash tabs (stash_config.lua): each bought one is an extra sold here, ids above the general tabs
local scfg = dofile("data/scripts/chaos/stash_config.lua")
for _, a in ipairs(scfg.affinities) do
	if a.extra then
		check(cfg.extras[a.extra] ~= nil and P.extraMax(cfg, a.extra) == 1, "affinity tab " .. a.key .. " has an extra of 1")
	end
	check(a.tab > 100 and a.tab < scfg.oldDepot.tab, "affinity tab id above the general tabs")
end
check(scfg.maxGeneralTabs < 100, "general tab ids stay below the affinity ones")
-- O316 prices: 1 expansion 50 coins (+25 slots), 4 for 180 (10% off); the old tab (150 coins) is worth 3 expansions
local function offer(key)
	for _, o in ipairs(found) do
		if o.key == key then
			return o
		end
	end
end
eq(scfg.slots.free, 30, "FREE: one tab of 30 slots") eq(scfg.generalTabs, 1, "FREE: exactly one general tab")
eq(scfg.slots.perPack, 25, "an expansion adds 25 slots") eq(L.stashSlots.maxExtra, 20, "at most 20 expansions")
eq(offer("service:pactExtra:stashSlots").cost, 50, "expansion price") eq(offer("service:pactExtra:stashSlots:4").cost, 180, "4 expansions price")
eq(offer("service:pactExtra:stashSlots:4").amount, 4, "the pack adds 4")
check(offer("service:pactExtra:stashSlots:4").cost < 4 * offer("service:pactExtra:stashSlots").cost, "the pack is cheaper")
eq(scfg.slots.legacyPacksPerTab * offer("service:pactExtra:stashSlots").cost, 150, "an old tab (150 coins) = the same coins in expansions")
eq(L.stashSlots.pact, 1, "the Pact lends one expansion (modest)")
for _, a in ipairs(scfg.affinities) do
	check(a.free == nil and a.pact == nil and a.achievements == nil, "affinity tab " .. a.key .. " is store-sold only")
	check(offer("service:pactExtra:" .. a.extra) ~= nil, "affinity tab " .. a.key .. " has a store offer")
end

print(string.format("pact_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

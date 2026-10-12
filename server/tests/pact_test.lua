-- Run from the server/ folder: luajit tests/pact_test.lua (or lua5.3; CI runs both)
-- Chaos Pact and account storage (pact_core.lua with the real pact_config.lua): limits (free / Pact / extras, caps,
-- premium for the loot rules), stacking and its cap, the daily coins, one-time extras, stash tabs (placing the stash of
-- before tabs, special tabs, withdraw-only tabs after the Pact ends, nothing deleted), saved build slots, character
-- slots, and the store offers (shop_config.lua inserts them; prices, keys, the coin drip below the price).
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
local ended = {pactEnds = NOW - 1, extras = {stashTabs = 2, buildSlots = 1}}
eq(P.active(free, NOW), false, "no Pact")
eq(P.active(pact, NOW), true, "Pact active")
eq(P.active(ended, NOW), false, "Pact ended")
eq(P.active(nil, NOW), false, "no state")
for key, l in pairs(L) do
	eq(P.limit(cfg, free, key, NOW), l.free, "free limit " .. key)
	eq(P.limit(cfg, pact, key, NOW), l.free + l.pact, "Pact limit " .. key)
end
eq(P.limit(cfg, ended, "stashTabs", NOW), L.stashTabs.free + 2, "bought tabs stay after the Pact")
eq(P.limit(cfg, ended, "buildSlots", NOW), L.buildSlots.free + 1, "bought build slot stays")
eq(P.limit(cfg, {pactEnds = 0, extras = {stashTabs = 99}}, "stashTabs", NOW), L.stashTabs.free + L.stashTabs.maxExtra, "extras capped at maxExtra")
eq(P.limit(cfg, {pactEnds = 0, extras = {stashTabs = -3}}, "stashTabs", NOW), L.stashTabs.free, "negative extras ignored")
eq(P.limit(cfg, free, "nope", NOW), 0, "unknown limit")
-- premium alone gives the loot rule bonus (the base autoloot callback does too), not the other perks
local prem = {pactEnds = 0, extras = {}, premium = true}
eq(P.limit(cfg, prem, "lootRules", NOW), L.lootRules.free + L.lootRules.pact, "premium counts for loot rules")
eq(P.limit(cfg, prem, "stashTabs", NOW), L.stashTabs.free, "premium does not count for stash tabs")
check(L.lootRules.free + L.lootRules.pact <= 20, "loot rules within the base callback's 20 storages")
-- character slots: bought (capped) + legacy (not capped)
local chars = {pactEnds = NOW + DAY, extras = {charSlots = 3, charSlotsLegacy = 4}}
eq(P.limit(cfg, chars, "charSlots", NOW), L.charSlots.free + 3 + 4, "character slots: bought + legacy, Pact adds none")
local lim = P.limits(cfg, {pactEnds = 0, extras = {stashOrbs = 1}}, NOW)
eq(lim.stashSpecial.orbs, true, "orbs tab owned")
eq(lim.stashSpecial.gems, false, "gems tab not owned")
local rows = P.breakdown(cfg, ended, NOW)
eq(#rows, #cfg.order, "breakdown rows")
eq(rows[1].key, "stashTabs", "breakdown order")
eq(rows[1].extra, 2, "breakdown extra")
eq(rows[1].total, L.stashTabs.free + 2, "breakdown total")
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

-- ---------------------------------------------------------------- daily coins
local st = {pactEnds = NOW + DAY, lastClaim = 0, extras = {}}
eq(P.claim(cfg, st, NOW, 20270115), cfg.pact.dailyCoins, "claim")
st.lastClaim = 20270115
local amount, why = P.claim(cfg, st, NOW, 20270115)
check(amount == nil and why == cfg.messages.alreadyClaimed, "one claim a day")
eq(P.claim(cfg, st, NOW, 20270116), cfg.pact.dailyCoins, "next day")
amount, why = P.claim(cfg, {pactEnds = NOW - 1, lastClaim = 0}, NOW, 20270116)
check(amount == nil and why == cfg.messages.noPact, "no claim without the Pact")
-- the drip is a discount, not a profit: a month of claims is less than the price
local offer = cfg.store.pact.offers[1]
check(cfg.pact.dailyCoins * cfg.pact.days < offer.cost, "coin drip below the Pact price")
check(cfg.pact.dailyCoins > 0, "coin drip")

-- ---------------------------------------------------------------- one-time extras
eq(P.extraCheck(cfg, free, "stashTabs"), nil, "extra tab can be bought")
check(P.extraCheck(cfg, {extras = {stashTabs = L.stashTabs.maxExtra}}, "stashTabs") ~= nil, "extra tabs capped")
check(P.extraCheck(cfg, {extras = {stashOrbs = 1}}, "stashOrbs") ~= nil, "special tab once")
check(P.extraCheck(cfg, free, "marketListings") ~= nil, "listings are not sold")
check(P.extraCheck(cfg, free, "bogus") ~= nil, "unknown extra")
-- packs (depot_config.lua sells 4 depot tabs at once): the whole pack must fit under maxExtra
eq(P.extraCheck(cfg, free, "depotTabs", 4), nil, "a pack of 4 depot tabs can be bought")
eq(P.extraCheck(cfg, {extras = {depotTabs = L.depotTabs.maxExtra - 4}}, "depotTabs", 4), nil, "a pack that just fits")
check(P.extraCheck(cfg, {extras = {depotTabs = L.depotTabs.maxExtra - 3}}, "depotTabs", 4) ~= nil, "a pack past the cap is refused")
eq(P.extraCheck(cfg, {extras = {depotTabs = L.depotTabs.maxExtra - 3}}, "depotTabs", 1), nil, "a single tab still fits")
check(P.extraCheck(cfg, {extras = {depotTabs = L.depotTabs.maxExtra}}, "depotTabs") ~= nil, "depot tabs capped")
eq(P.limit(cfg, {pactEnds = 0, extras = {depotTabs = 99}}, "depotTabs", NOW), L.depotTabs.free + L.depotTabs.maxExtra, "bought depot tabs capped")
eq(P.limit(cfg, {pactEnds = NOW + DAY, extras = {}}, "depotTabs", NOW), L.depotTabs.free + L.depotTabs.pact, "Pact depot tab")
eq(P.extraMax(cfg, "charSlots"), L.charSlots.maxExtra, "character slot max")
eq(P.extraMax(cfg, "stashGems"), 1, "special tab max")

-- ---------------------------------------------------------------- stash tabs
local SIZE = cfg.stash.tabSize
local function entries(n, firstItem, tab, kind)
	local out = {}
	for i = 1, n do
		out[i] = {item = firstItem + i - 1, tab = tab or 0, kind = kind}
	end
	return out
end
local function concat(a, b)
	local out = {}
	for _, e in ipairs(a) do out[#out + 1] = e end
	for _, e in ipairs(b) do out[#out + 1] = e end
	return out
end
local function tabCount(list, tab)
	local n = 0
	for _, e in ipairs(list) do
		if e.tab == tab then n = n + 1 end
	end
	return n
end
local limFree = P.limits(cfg, free, NOW) -- 2 tabs
local limPact = P.limits(cfg, pact, NOW) -- 4 tabs
-- the stash of before tabs: 130 types, placed in order; what does not fit the 2 free tabs goes to tab 3, read-only
local old = entries(130, 1000)
local moves = P.layout(cfg, limFree, old)
eq(#moves, 130, "every old entry placed")
eq(tabCount(old, 1), SIZE, "tab 1 full")
eq(tabCount(old, 2), SIZE, "tab 2 full")
eq(tabCount(old, 3), 130 - 2 * SIZE, "the rest in tab 3")
eq(P.tabWritable(cfg, limFree, 3), false, "tab 3 withdraw-only without the Pact")
eq(P.tabWritable(cfg, limPact, 3), true, "tab 3 writable with the Pact")
eq(#P.layout(cfg, limFree, old), 0, "layout is stable")
-- deposits: full without the Pact (entries in a withdraw-only tab), fine with it
local tab, reason = P.depositTab(cfg, limFree, old, 5000, nil)
check(tab == nil and reason == "locked", "new item refused: tabs full, tab 3 withdraw-only")
eq(P.depositTab(cfg, limFree, old, 1000, nil), 1, "known item in a writable tab")
tab, reason = P.depositTab(cfg, limFree, old, 1129, nil)
check(tab == nil and reason == "locked", "known item in a withdraw-only tab with no room elsewhere")
eq(P.depositTab(cfg, limPact, old, 5000, nil), 3, "with the Pact: the first tab with room")
eq(P.depositTab(cfg, limPact, old, 1129, nil), 3, "with the Pact: its own tab")
-- withdrawing frees room: a known item from the read-only tab moves into the writable tab with room
local partial = entries(SIZE * 2 - 1, 1000, nil)
P.layout(cfg, limFree, partial)
partial[#partial + 1] = {item = 9000, tab = 3}
eq(P.depositTab(cfg, limFree, partial, 9000, nil), 2, "entry of a read-only tab moves to a writable tab with room")
eq(P.depositTab(cfg, limFree, partial, 9001, nil), 2, "new item into the free place")
-- empty stash
eq(P.depositTab(cfg, limFree, {}, 1, nil), 1, "empty stash: tab 1")
tab, reason = P.depositTab(cfg, P.limits(cfg, {extras = {}}, NOW), entries(2 * SIZE, 1, 0), 99999, nil)
-- (unplaced entries do not count: layout runs first in stash.lua)
eq(tab, 1, "unplaced entries are not counted")
local full = entries(2 * SIZE, 1)
P.layout(cfg, limFree, full)
tab, reason = P.depositTab(cfg, limFree, full, 99999, nil)
check(tab == nil and reason == "full", "full stash")
-- special tabs
local limOrbs = P.limits(cfg, {pactEnds = 0, extras = {stashOrbs = 1}}, NOW)
eq(P.depositTab(cfg, limOrbs, full, 29856, "orbs"), 101, "an orb goes to the Orbs tab even when the general tabs are full")
tab = P.depositTab(cfg, limFree, full, 29856, "orbs")
eq(tab, nil, "no Orbs tab: an orb needs general room")
local mixed = concat(entries(3, 2000, 1), entries(2, 29850, 1, "orbs"))
moves = P.layout(cfg, limOrbs, mixed)
eq(#moves, 2, "orbs move into the bought Orbs tab")
eq(tabCount(mixed, 101), 2, "two orbs in tab 101")
eq(tabCount(mixed, 1), 3, "the rest stays")
local gemsInGems = entries(2, 32001, 102, "gems")
eq(P.tabWritable(cfg, limFree, 102), false, "a special tab not owned is withdraw-only")
eq(#P.layout(cfg, limFree, gemsInGems), 0, "entries of a lost special tab stay")
local unknown = {{item = 7, tab = 150}}
P.layout(cfg, limFree, unknown)
eq(unknown[1].tab, 1, "an unknown tab id is placed again")
-- the tab bar
local view = P.tabsView(cfg, limFree, old)
eq(#view, 3, "two free tabs and the withdraw-only tab 3")
eq(view[3].locked, true, "tab 3 shown locked")
eq(view[1].used, SIZE, "tab 1 usage")
view = P.tabsView(cfg, limOrbs, mixed)
eq(view[#view].special, "orbs", "the Orbs tab shown")
eq(view[#view].size, cfg.stash.special[1].size, "special tab size")
view = P.tabsView(cfg, limPact, {})
eq(#view, L.stashTabs.free + L.stashTabs.pact, "empty tabs of the Pact shown")

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
local depotStore = dofile("data/scripts/chaos/depot_config.lua").store
eq(#found, #cfg.store.pact.offers + #cfg.store.storage.offers + #depotStore.offers, "every Pact and depot tab offer is in the store")
for key, x in pairs(cfg.extras) do
	local sold = false
	for _, o in ipairs(found) do
		sold = sold or o.extra == key
	end
	check(sold, "extra " .. key .. " is sold")
	check(x.name ~= nil, "extra " .. key .. " has a name")
end
for _, s in ipairs(cfg.stash.special) do
	check(cfg.extras[s.extra] ~= nil, "special tab " .. s.kind .. " has an extra")
	check(s.tab > 100, "special tab id above the general tabs")
end
check(L.stashTabs.free + L.stashTabs.pact + L.stashTabs.maxExtra < 100, "general tab ids stay below the special ones")

print(string.format("pact_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

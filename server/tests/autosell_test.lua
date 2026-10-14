-- Run from the server/ folder: luajit tests/autosell_test.lua (and lua5.3; CI runs both)
-- The Auto Seller sells the Loot Bag (owner, 2026-10-13: "vende tudo dentro da loot bag e pode ser usado a cada 30s"):
-- autosell_core.lua (the plan: NPC prices, coins to the bank, locked / unique / orbs kept, the rarity tiers the player
-- ticks (owner 2026-10-13: "Deixe o jogador configurar o autosell por raridade"), containers' contents, the 30 s
-- cooldown, the chat line) and autosell.lua on a mocked engine (unlock or Pact needed, the carried bag only, items
-- removed, gold to the bank, the cooldown, the window actions of opcode 226 and their validation, no chat command).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/autosell_core.lua")
local K = ChaosAutoSellCore

-- ---------------------------------------------------------------- core
eq(K.COOLDOWN, 30, "every 30 s")
eq(K.cooldownLeft(nil, 1000), 0, "first sale: ready")
eq(K.cooldownLeft(1000, 1010), 20, "10 s later: 20 s to wait")
eq(K.cooldownLeft(1000, 1030), 0, "30 s later: ready")
local prices = {[2400] = 100, [2401] = 5, [2402] = 1000, [2403] = 70}
local plan = K.bagPlan({
	{ref = "a", id = 2400, count = 1},
	{ref = "b", id = 2401, count = 20},
	{ref = "c", id = 2402, count = 1, locked = true},
	{ref = "d", id = 2402, count = 1, unique = true},
	{ref = "e", id = 2402, count = 1, rarity = 3}, -- Rare: kept by default
	{ref = "e2", id = 2401, count = 1, rarity = 1}, -- Common: sold by default
	{ref = "e3", id = 2401, count = 1, rarity = 0, attributes = true}, -- a named item: kept
	{ref = "f", id = 29856, count = 5, neverSell = true},
	{ref = "g", id = 1988, count = 1, container = true},
	{ref = "h", id = 2403, count = 1}, -- inside the bag "g": sold too
	{ref = "i", id = 9999, count = 1},
	{ref = "j", id = 2152, count = 3},
	{ref = "k", id = 2148, count = 50}
}, prices)
eq(#plan.sell, 6, "sold: two items, a Common one, the nested one and two coin stacks")
eq(plan.gold, 100 + 100 + 5 + 70 + 300 + 50, "NPC gold and the coins' worth")
eq(plan.kept.custom, 1, "a named item is kept")
eq(plan.kept.locked, 1, "a locked item is kept") eq(plan.kept.unique, 1, "a unique is kept")
eq(plan.kept.rarity, 1, "a rarity item is kept by default") eq(plan.kept.protected, 1, "orbs are kept")
eq(plan.kept.noPrice, 1, "no NPC buys it: kept")
local opted = K.bagPlan({{ref = "e", id = 2402, count = 1, rarity = 3}, {ref = "c", id = 2402, locked = true, rarity = 3},
	{ref = "u", id = 2402, unique = true, rarity = 9}}, prices, {tiers = {rare = true}})
eq(opted.gold, 1000, "Rare sold once ticked; a locked one and a unique never")
local priced = K.bagPlan({{ref = "r", id = 2400, count = 1, rarity = 1, price = 900}, {ref = "p", id = 2401, count = 2}}, prices)
eq(priced.gold, 900 + 10, "a copy's own price (ChaosItemPrices) beats the plain table; no own price: the table")
local text = K.saleText(plan)
check(text:find("sold 23 items from your Loot Bag for 625 gold (to your bank)", 1, true) ~= nil, "chat line: " .. text)
check(text:find("Kept 6", 1, true) ~= nil and text:find("named 1", 1, true) ~= nil, "kept count: " .. text)

-- ---------------------------------------------------------------- rarity tiers
eq(#K.TIERS, 5, "five tiers")
local d = K.unpackTiers(-1)
check(d.common and d.uncommon and not d.rare and not d.epic and not d.legendary, "default: Common and Uncommon on")
d = K.unpackTiers(0)
check(d.common and not d.rare, "the old 'rarity off' (0) reads as the defaults")
d = K.unpackTiers(1)
check(d.common and d.rare and d.epic and d.legendary, "the old 'rarity on' (1) reads as every tier on")
local packed = K.packTiers({rare = true, legendary = true})
d = K.unpackTiers(packed)
check(not d.common and not d.uncommon and d.rare and not d.epic and d.legendary, "pack / unpack round trip")
eq(K.unpackTiers(K.packTiers({})).common, false, "every tier off is kept as off")
eq(K.tierOf(0), nil, "no rarity: no tier") eq(K.tierOf(2), "uncommon", "rarity 2 is Uncommon")
eq(K.tierOf(5), "legendary", "Legendary") eq(K.tierOf(15), "legendary", "Transcendent goes with Legendary+")
eq(K.sells(K.DEFAULT_TIERS, 0), true, "a plain item") eq(K.sells(K.DEFAULT_TIERS, 1), true, "Common by default")
eq(K.sells(K.DEFAULT_TIERS, 3), false, "Rare kept by default") eq(K.sells(K.DEFAULT_TIERS, 9), false, "Eternal kept")
local t, why = K.rarityChange(K.DEFAULT_TIERS, {tier = "epic", on = true})
check(t and t.epic and t.common, "tick Epic, the rest kept")
t = K.rarityChange(K.DEFAULT_TIERS, {tier = "Legendary+", on = true})
check(t and t.legendary, "the shown name works too")
t = K.rarityChange(K.DEFAULT_TIERS, {tiers = {common = false, rare = true}})
check(t and not t.common and t.rare and t.uncommon, "several at once")
t, why = K.rarityChange(K.DEFAULT_TIERS, {tier = "unique", on = true})
check(t == nil and why == "unknown rarity", "uniques cannot be ticked")
t, why = K.rarityChange(K.DEFAULT_TIERS, {tier = "rare", on = "yes"})
check(t == nil and why ~= nil, "on must be a boolean")
t, why = K.rarityChange(K.DEFAULT_TIERS, {tiers = {mythic = true}})
check(t == nil, "an unknown key in tiers")
t, why = K.rarityChange(K.DEFAULT_TIERS, "rare")
check(t == nil, "not a table")
eq(#K.tierList(K.DEFAULT_TIERS), 5, "the window's list") eq(K.tierList(K.DEFAULT_TIERS)[5].name, "Legendary+", "its names")

-- ---------------------------------------------------------------- autosell.lua on a mocked engine
do
	MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, MESSAGE_LOOT, ITEM_ATTRIBUTE_NAME = 19, 22, 23, 1
	ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_TEXT = 2, 4
	dofile("data/scripts/chaos/chaos_constants.lua")
	EventCallback = {register = function() end}
	local registeredCommands = {}
	ChaosCommands = {register = function(name, fn) registeredCommands[name] = fn end}
	ItemType = function(x)
		local names = {[2400] = "dagger", [2401] = "rope", [29856] = "orb", [9999] = "letter"}
		local id = tonumber(x)
		if not id then
			for k, v in pairs(names) do
				if v == x then id = k end
			end
		end
		return {getId = function() return names[id or 0] and id or 0 end, getName = function() return names[id] or "?" end}
	end
	local function item(id, opts)
		opts = opts or {}
		local it = {id = id, count = opts.count or 1, items = opts.items, attrs = opts.attrs or {}, removed = false}
		function it:getId() return self.id end
		function it:getCount() return self.count end
		function it:isContainer() return self.items ~= nil end
		function it:getItems() return self.items or {} end
		function it:getCustomAttribute(k) return self.attrs[k] end
		function it:hasAttribute() return false end
		function it:remove() self.removed = true return true end
		return it
	end
	local inner = item(1988, {items = {item(2403)}})
	local locked = item(2402, {attrs = {chaos_locked = 1}})
	local bag = item(32081, {items = {item(2400), item(2401, {count = 20}), locked, inner, item(2152, {count = 2})}})
	local carry = {loot = bag}
	ChaosPouches = {carried = function() return carry end, neverSell = function(id) return id == 29856 end}
	local pl = {st = {}, bank = 0, msgs = {}, cancel = {}}
	function pl:getGuid() return 7 end
	function pl:getId() return 1 end
	function pl:getStorageValue(k) return self.st[k] or -1 end
	function pl:setStorageValue(k, v) self.st[k] = v end
	function pl:getBankBalance() return self.bank end
	function pl:setBankBalance(v) self.bank = v end
	function pl:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function pl:sendCancelMessage(t) self.cancel[#self.cancel + 1] = t end
	dofile("data/scripts/chaos/autosell.lua")
	local A = ChaosAutoSell
	local P = A.prices
	local plan2, why = A.sellBag(pl)
	eq(plan2, nil, "no Auto Seller: refused")
	check(why:find("Auto Seller from the store", 1, true) ~= nil, "the reason names the store and the Pact")
	pl.st[Chaos.storage.shopAutoSeller] = 2 -- lent by an active Chaos Pact (pact_perks.lua)
	local realTime = os.time
	local now = 1000000
	os.time = function() return now end
	plan2 = A.sellBag(pl)
	check(plan2 ~= nil, "sold with the Pact's Auto Seller")
	local want = (P[2400] or 0) + 20 * (P[2401] or 0) + (P[2403] or 0) + 200
	eq(pl.bank, want, "NPC gold and the coins to the bank")
	eq(bag.items[1].removed, (P[2400] or 0) > 0, "a priced item removed")
	eq(locked.removed, false, "the locked item stays")
	eq(inner.removed, false, "the container stays") eq(inner.items[1].removed, (P[2403] or 0) > 0, "its contents are sold")
	now = now + 10
	plan2, why = A.sellBag(pl)
	eq(plan2, nil, "10 s later: refused") eq(why, "Auto Seller: ready again in 20 s.", "the cooldown told")
	now = now + 20
	carry = {}
	plan2, why = A.sellBag(pl)
	eq(why, "Auto Seller: carry your Loot Bag to sell what is in it.", "no bag carried")
	carry = {loot = bag}
	pl.st[Chaos.storage.shopAutoSeller] = 1
	eq(registeredCommands.autosell, nil, "no autosell command any more (the top menu window)")
	local st = A.handleAction(pl, "sell", {})
	check(pl.msgs[#pl.msgs]:find("from your Loot Bag", 1, true) ~= nil, "sell: the chat line")
	check(st.notice:find("from your Loot Bag", 1, true) ~= nil, "sell: the window notice")
	eq(st.cooldown, 30, "sell: the cooldown sent") check(st.last and st.last.at == now, "sell: the last sale kept")
	st = A.handleAction(pl, "sell", {})
	check(st.notice:find("ready again in 30 s", 1, true) ~= nil, "sell again at once: the cooldown")
	-- the window's state and validation
	st = A.handleAction(pl, "as_open")
	eq(st.open, true, "as_open opens") eq(st.unlocked, true, "unlocked") eq(#st.tiers, 5, "five tiers sent")
	check(st.tiers[1].on and st.tiers[2].on and not st.tiers[3].on, "default tiers sent")
	eq(A.handleAction(pl, "nope"), nil, "not an Auto Seller action")
	st = A.handleAction(pl, "asrar", {tier = "rare", on = true})
	eq(st.tiers[3].on, true, "Rare ticked") eq(K.unpackTiers(pl.st[Chaos.storage.autosellRarity]).rare, true, "stored")
	local before = pl.st[Chaos.storage.autosellRarity]
	st = A.handleAction(pl, "asrar", {tier = "unique", on = true})
	check(st.notice and st.notice:find("unknown rarity", 1, true), "a bad tier refused") eq(pl.st[Chaos.storage.autosellRarity], before, "nothing stored")
	A.handleAction(pl, "asrar", {tier = "legendary", on = "1"})
	eq(pl.st[Chaos.storage.autosellRarity], before, "a bad value refused")
	st = A.handleAction(pl, "aslist", {op = "add", item = "dagger"})
	eq(#st.list, (P[2400] or 0) > 0 and 1 or 0, "an item an NPC buys is added")
	st = A.handleAction(pl, "aslist", {op = "add", item = "orb"})
	check(st.notice:find("never auto%-sold") ~= nil, "orbs refused")
	st = A.handleAction(pl, "aslist", {op = "add", item = "letter"})
	check(st.notice:find("No NPC buys", 1, true) ~= nil, "no NPC price refused")
	st = A.handleAction(pl, "aslist", {op = "add", item = "nothing at all"})
	check(st.notice:find("There is no item", 1, true) ~= nil, "unknown item refused")
	st = A.handleAction(pl, "aslist", {op = "drop"})
	eq(st.notice, "Unknown list change.", "unknown op refused")
	st = A.handleAction(pl, "aslist", {op = "clear"})
	eq(#st.list, 0, "list cleared")
	st = A.handleAction(pl, "aspause", {on = false})
	eq(st.paused, true, "corpse selling off") st = A.handleAction(pl, "aspause", {on = true}) eq(st.paused, false, "and on")
	st = A.handleAction(pl, "aspause", {on = 1})
	eq(st.notice, "Bad request.", "aspause wants a boolean")
	-- without the unlock: the state with the reason, nothing changes
	pl.st[Chaos.storage.shopAutoSeller] = -1
	before = pl.st[Chaos.storage.autosellRarity]
	st = A.handleAction(pl, "asrar", {tier = "epic", on = true})
	eq(st.unlocked, false, "locked state") check(st.notice:find("Chaos Pact", 1, true) ~= nil, "the reason")
	eq(pl.st[Chaos.storage.autosellRarity], before, "locked: nothing stored")
	eq(A.handleAction(pl, "as_sync").unlocked, false, "as_sync works without the unlock (greyed window)")
	-- a rolled Rare copy priced through ChaosItemPrices.sellPrice (the item price table: rarity and item level)
	pl.st[Chaos.storage.shopAutoSeller] = 1
	pl.st[Chaos.storage.autosellRarity] = K.packTiers({common = true, uncommon = true, rare = true})
	local asked = {}
	ChaosItemPrices = {sellPrice = function(it, count)
		asked[#asked + 1] = it
		local r = tonumber(it.attrs.rarity) or 0
		return (r > 0 and 4000 or 7) * (count or 1)
	end}
	local rolled = item(2400, {attrs = {rarity = 3}})
	local plainOne = item(2401, {count = 3})
	bag.items = {rolled, plainOne}
	now = now + 31
	local bank0 = pl.bank
	local plan3 = A.sellBag(pl)
	check(plan3 ~= nil, "sold with the API prices")
	eq(pl.bank - bank0, 4000 + 21, "the Rare copy at its own price, the plain stack at the API's price")
	eq(rolled.removed, true, "the rolled copy sold (Rare ticked)") check(#asked >= 2, "the API asked per copy")
	pl.st[Chaos.storage.autosellRarity] = K.packTiers({common = true})
	local rolled2 = item(2400, {attrs = {rarity = 3}})
	bag.items = {rolled2}
	now = now + 31
	A.sellBag(pl)
	eq(rolled2.removed, false, "Rare not ticked: kept, whatever its price")
	ChaosItemPrices = nil
	os.time = realTime
end

if failures > 0 then
	error(failures .. " of " .. count .. " checks failed")
end
print("autosell_test: " .. count .. " checks OK")

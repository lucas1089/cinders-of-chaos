-- Run from the server/ folder: luajit tests/shop_test.lua (and lua5.3; CI runs both)
-- The Chaos store: shop_core.lua rules (keys, exclusives, prices, sales, featured rotation, bundles, gifts, coin packs),
-- the generated cosmetics list against the class looks and the rewards, shop_config.lua (no random orbs, valid
-- storefront), and shop.lua against a mocked engine and database: buying an outfit (both sexes, both addons), a mount,
-- an aura, a frame, a bundle and a starter pack; duplicates refused; prices echoed; weekly limits; season rules;
-- gifts online and offline; paid coin orders with the bonuses; a second load (reload) changes nothing.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
PLAYERSEX_FEMALE, PLAYERSEX_MALE = 0, 1

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function ok(v, m) if not v then error(m or "check failed", 2) end end

-- the store's clock: a fixed day before the Founder Pack window (O322), so the tests do not depend on the date they run on;
-- the Founder Pack tests move it (os.time with a table still converts a date)
local realTime, clock = os.time, nil
clock = realTime({year = 2026, month = 10, day = 29, hour = 15, min = 0, sec = 0})
os.time = function(t) if t then return realTime(t) end return clock or realTime() end

dofile("data/scripts/chaos/shop_core.lua")
local K = ChaosShopCore

-- ------------------------------------------------------------------ core: keys
eq(K.offerKey({kind = "wings", id = 4}), "wings:4", "wings key")
eq(K.offerKey({kind = "item", id = 32256, count = 10}), "item:32256x10", "item key")
eq(K.offerKey({kind = "outfit", looktype = 909, lookfemale = 910}), "outfit:909", "outfit key")
eq(K.offerKey({kind = "service", service = "pouch", pouch = "loot"}), "service:pouch:loot", "pouch key")
eq(K.offerKey({kind = "service", service = "worldBuff", buff = "xp"}), "service:worldBuff:xp", "buff key")
eq(K.offerKey({kind = "unlock", unlock = "autoSeller"}), "unlock:autoSeller", "unlock key")
eq(K.offerKey({kind = "bundle", key = "bundle:x"}), "bundle:x", "explicit key")
eq(#K.outfitLooks({looktype = 1207, lookfemale = 1207}), 1, "one look when both sexes share it")
eq(#K.outfitLooks({looktype = 909, lookfemale = 910}), 2, "two looks")

-- ------------------------------------------------------------------ core: exclusives from the real files
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/class_looks_core.lua")
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
local season = dofile("data/scripts/chaos/season_config.lua")
local seasonpass = dofile("data/scripts/chaos/seasonpass_config.lua")
local retiredLooks = {}
for _, e in ipairs(ChaosClassLooks.retired) do
	retiredLooks[#retiredLooks + 1] = e.male
	retiredLooks[#retiredLooks + 1] = e.female
end
-- as shop.lua: the retired donor art class outfits (1559 Archmage) too
for _, o in ipairs(Chaos.classes.retiredOutfits) do
	retiredLooks[#retiredLooks + 1] = o.lookType
end
-- and the replacement Archmage of pair 29, both looks, switch on or off
local repl = Chaos.classes.outfitReplacement.outfit
retiredLooks[#retiredLooks + 1] = repl.lookType
retiredLooks[#retiredLooks + 1] = repl.female
local EX = K.exclusions({classLooks = ChaosClassLooks.looks, classOutfits = Chaos.classes.outfits,
	achievements = achievements, season = season, seasonpass = seasonpass, looks = retiredLooks})
ok(EX.looks[1559], "the retired Archmage 1559 is never sold")
ok(EX.looks[2235] and EX.looks[2236], "the pair 29 Archmage (2235 / 2236) is never sold")
ok(EX.looks[1551] and EX.looks[1558], "the donor art class outfits stay excluded")
for _, e in pairs(ChaosClassLooks.looks) do
	ok(EX.looks[e.male] and EX.looks[e.female], "class look " .. e.name .. " excluded")
end
ok(EX.looks[131] and EX.looks[139], "former class looks (the Knight) stay excluded")
for _, look in ipairs({974, 973, 278, 279, 1016, 1017, 665, 664}) do
	ok(EX.looks[look], "season pass look " .. look .. " excluded")
end
for _, id in ipairs({106, 90, 47, 116}) do
	ok(EX.mounts[id], "season pass mount " .. id .. " excluded")
end
local exw = K.exclusions({seasonpass = {cosmetics = {{reward = {kind = "wings", id = 3}}, {reward = {kind = "frame", frame = "frost"}}}}})
ok(K.excluded({kind = "wings", id = 3}, exw) and K.excluded({kind = "frame", frame = "frost"}, exw), "wings and frames as rewards")
for _, look in ipairs({131, 139, 130, 138, 1373, 1372, 1188, 1189, 1505, 1560}) do
	ok(EX.looks[look], "class look / class outfit " .. look .. " excluded")
end
for _, look in ipairs({666, 667, 845, 846, 884, 885, 288, 289, 1066, 1067}) do
	ok(EX.looks[look], "reward look " .. look .. " excluded")
end
for _, id in ipairs({53, 107, 87, 85, 56, 105, 103}) do
	ok(EX.mounts[id], "reward mount " .. id .. " excluded")
end
ok(not EX.looks[909] and not EX.mounts[121], "store outfits and mounts are not exclusives")
ok(K.excluded({kind = "outfit", looktype = 667, lookfemale = 666}, EX), "excluded outfit")
ok(K.excluded({kind = "mount", id = 53}, EX), "excluded mount")
eq(K.excluded({kind = "mount", id = 121}, EX), nil, "sold mount")
ok(K.excluded({kind = "addons", looktype = 131, lookfemale = 139}, EX), "class look addons excluded")

-- ------------------------------------------------------------------ the generated list
local COS = dofile("data/scripts/chaos/shop_cosmetics.lua")
local keys = {}
for _, list in ipairs({COS.outfits, COS.addons, COS.mounts}) do
	for _, e in ipairs(list) do
		ok(not keys[e.key], "unique key " .. e.key); keys[e.key] = true
		ok(type(e.name) == "string" and e.name ~= "", "name of " .. e.key)
		ok(e.cost >= 150 and e.cost <= 750, "price range of " .. e.key)
	end
end
ok(#COS.outfits >= 50 and #COS.mounts >= 100 and #COS.addons >= 5, "the list is not empty")
for _, e in ipairs(COS.outfits) do
	ok(e.looktype and e.lookfemale, "both looks " .. e.key)
	eq(K.excluded({kind = "outfit", looktype = e.looktype, lookfemale = e.lookfemale}, EX), nil, "not exclusive " .. e.key)
	ok(e.cost == 300 or e.cost == 500 or e.cost == 750, "outfit tier " .. e.key)
end
for _, e in ipairs(COS.addons) do
	eq(K.excluded({kind = "addons", looktype = e.looktype, lookfemale = e.lookfemale}, EX), nil, "not exclusive " .. e.key)
end
for _, e in ipairs(COS.mounts) do
	eq(K.excluded({kind = "mount", id = e.id}, EX), nil, "not exclusive " .. e.key)
	ok(e.id ~= 22 and e.id ~= 25 and e.id ~= 26, "no rented horse")
end

-- ------------------------------------------------------------------ shop_config.lua
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29
local cfg = dofile("data/scripts/chaos/shop_config.lua")
local problems = K.validate(cfg, EX)
for _, p in ipairs(problems) do print("problem: " .. p) end
eq(#problems, 0, "shop_config.lua validates")
local RANDOM_ORBS = {[29856] = "Upheaval", [29857] = "Fate", [29851] = "Awakening", [24691] = "Gilding", [24688] = "Erasure",
	[24697] = "Unmaking", [24692] = "Sockets", [29855] = "Grafting", [32251] = "Tempering", [32254] = "Reforging"}
local cfgKeys = {}
for _, cat in ipairs(cfg.categories) do
	for _, o in ipairs(cat.offers) do
		cfgKeys[K.offerKey(o)] = o
		local parts = o.parts or {o}
		for _, p in ipairs(parts) do
			local po = type(p) == "table" and p or nil
			ok(not (po and po.kind == "item" and RANDOM_ORBS[po.id]), "random orb sold: " .. tostring(po and RANDOM_ORBS[po.id]))
			ok(not (type(p) == "string" and p:match("^item:(%d+)") and RANDOM_ORBS[tonumber(p:match("^item:(%d+)"))]), "random orb in a bundle")
		end
		if o.kind == "item" and (o.id == 32256 or o.id == 32253 or o.id == 32252) then
			ok(o.weeklyLimit and o.weeklyLimit > 0, "weekly limit on " .. o.name)
		end
		if o.kind == "item" and o.id == 28095 then
			ok(o.seasonBlocked, "double experience potions are not for season characters")
		end
		if o.oncePerAccount and o.availableUntil then
			ok(o.gift == false and o.availableFrom and not o.maxLevel, "limited packs: a window, not giftable") -- Founder Pack (O322)
			for _, p in ipairs(o.parts) do
				ok(p.kind == "exclusive" or p.kind == "pact", "a limited pack gives cosmetics and Pact days only")
			end
		elseif o.oncePerAccount then
			ok(o.maxLevel and o.gift == false, "starter packs: level gate, not giftable")
			for _, p in ipairs(o.parts) do
				local key = type(p) == "string" and p or K.offerKey(p)
				ok(not key:match("^item:2[49]") and not key:match("^item:32"), "no orbs in a starter pack")
			end
		end
	end
end
ok(cfgKeys["outfit:909"] and cfgKeys["mount:121"] and cfgKeys["addons:128"] and cfgKeys["frame:violet"], "categories built")
ok(not cfgKeys["frame:gold"] and not cfgKeys["frame:crimson"], "staff and champion frames stay theirs")

-- ------------------------------------------------------------------ prices
local t0 = os.time({year = 2026, month = 10, day = 14, hour = 12, min = 0, sec = 0})
local wings = {kind = "wings", id = 1, cost = 250}
local ctx = {now = t0, sales = {{categories = {"Wings"}, pct = 20, from = "2026-10-10 00:00", to = "2026-10-24 06:00", tag = "Launch sale"},
	{offers = {"wings:1"}, pct = 10}}, featured = {}}
local cost, old, tags = K.price(wings, "Wings", ctx)
eq(cost, 200, "biggest sale wins"); eq(old, 250, "old price"); eq(tags[1], "Launch sale -20%", "tag")
ctx.now = os.time({year = 2026, month = 10, day = 25, hour = 0, min = 0, sec = 0})
cost, old = K.price(wings, "Wings", ctx)
eq(cost, 225, "the category sale ended, the offer sale (no end) runs"); eq(old, 250, "old price 2")
cost, old, tags = K.price(wings, "Wings", {now = t0, featured = {["wings:1"] = 15}})
eq(cost, 212, "featured discount"); ok(tags[#tags] == "Featured", "featured tag")
cost, old = K.price({kind = "bundle", key = "b", cost = 100}, "Bundles", ctx)
eq(cost, 100, "no sale on bundles"); eq(old, nil, "no old price")
local _, _, nt = K.price(wings, "Wings", {now = t0, new = {{categories = {"Wings"}, ["until"] = "2026-11-10 06:00"}}})
eq(nt[1], "New", "new tag")
_, _, nt = K.price(wings, "Wings", {now = os.time({year = 2026, month = 12, day = 1, hour = 0}), new = {{categories = {"Wings"}, ["until"] = "2026-11-10 06:00"}}})
eq(#nt, 0, "new tag ended")
eq(K.bundleCost({pct = 20}, 1340), 1072, "bundle pct"); eq(K.bundleCost({cost = 250}, 999), 250, "bundle fixed")
eq(K.parseTime("2026-10-10"), os.time({year = 2026, month = 10, day = 10, hour = 0, min = 0, sec = 0}), "date only")
eq(K.parseTime("bad"), nil, "bad time")

-- weeks start on Monday at the hour
local mon = os.time({year = 2026, month = 10, day = 12, hour = 6, min = 0, sec = 0})
eq(K.weekKey(mon, 6), K.weekKey(mon - 1, 6) + 1, "a new week on Monday 06:00")
eq(K.weekKey(mon + 6 * 86400, 6), K.weekKey(mon, 6), "same week on Sunday")
-- featured rotation
local pool = {"a", "b", "c", "d", "e", "f", "g", "h"}
local w1, w1b, w2 = K.featured(pool, 100, 4), K.featured(pool, 100, 4), K.featured(pool, 101, 4)
eq(#w1, 4, "count"); eq(table.concat(w1), table.concat(w1b), "same week, same choice")
ok(table.concat(w1) ~= table.concat(w2), "another week, another choice")
local seen = {}
for _, v in ipairs(w1) do ok(not seen[v], "distinct"); seen[v] = true end

-- gifts and coin packs
eq(K.giftProblem({found = false}), "There is no character with that name.", "unknown")
ok(K.giftProblem({found = true, staff = true}), "staff")
ok(K.giftProblem({found = true, banned = true}), "banned")
ok(K.giftProblem({found = true, self = true}), "self")
ok(K.giftProblem({found = true, kind = "service"}), "services are not giftable")
eq(K.giftProblem({found = true, kind = "outfit"}), nil, "ok")
-- Chaos Coin gifts: a hold after the last donation, a daily cap, no banned receiver; chargebacks claw back
local CG = cfg.coinGifts
ok(CG and CG.holdDays >= 7 and CG.perDay > 0, "coin gift rules configured")
local T0 = 1700000000
ok(K.coinGiftProblem(CG, {now = T0, amount = 10, targetBanned = true}), "no coin gift to a banned account")
ok(K.coinGiftProblem(CG, {now = T0, amount = 10, lastCredited = T0 - 86400}), "no coin gift the day after a donation")
eq(K.coinGiftProblem(CG, {now = T0, amount = 10, lastCredited = T0 - CG.holdDays * 86400}), nil, "allowed after the hold")
eq(K.coinGiftProblem(CG, {now = T0, amount = 10, lastCredited = 0}), nil, "never donated: allowed")
ok(K.coinGiftProblem(CG, {now = T0, amount = 11, giftedToday = CG.perDay - 10}), "daily cap")
eq(K.coinGiftProblem(CG, {now = T0, amount = 10, giftedToday = CG.perDay - 10}), nil, "up to the cap")
local plan, rest = K.clawbackPlan(700, {{id = 3, to_account = 9, amount = 500, clawed = 0, balance = 300},
	{id = 2, to_account = 8, amount = 500, clawed = 100, balance = 1000}, {id = 1, to_account = 7, amount = 500, clawed = 0, balance = 1000}})
eq(#plan, 2, "two receivers")
eq(plan[1].take, 300, "the newest gift: what its receiver still has")
eq(plan[2].take, 400, "then the next: its unclawed rest")
eq(rest, 0, "all recovered")
plan, rest = K.clawbackPlan(900, {{id = 5, to_account = 9, amount = 500, clawed = 0, balance = 200},
	{id = 4, to_account = 9, amount = 500, clawed = 0, balance = 200}})
eq(#plan, 1, "one receiver's balance is shared by its gifts")
eq(rest, 700, "the rest is flagged")
local coins = dofile("data/scripts/chaos/shop_coins_config.lua")
local packs = {}
for _, p in ipairs(coins.packs) do packs[p.key] = p end
eq(K.packCredit(packs.coins250, false, coins).total, 250, "250")
eq(K.packCredit(packs.coins500, false, coins).total, 525, "500 +5%")
eq(K.packCredit(packs.coins1000, false, coins).total, 1100, "1000 +10%")
eq(K.packCredit(packs.coins2500, false, coins).total, 2875, "2500 +15%")
eq(K.packCredit(packs.coins500, true, coins).total, 1025, "first purchase: double coins (+100% of the pack)")
eq(K.packCredit(packs.coins100, false, coins).total, 100, "entry pack 100")
eq(K.packCredit(packs.coins5000, false, coins).total, 6000, "Vault: 5000 +20%")
eq(coins.firstPurchase.bonusPct, 100, "first purchase doubles")
eq(coins.firstPurchase.maxBonus, 1000, "at most 1000 extra (owner: Limite a 1000)")
eq(K.packCredit(packs.coins2500, true, coins).firstBonus, 1000, "2500 pack: +1000 flat")
eq(K.packCredit(packs.coins5000, true, coins).total, 6000 + 1000, "Vault: +1000 flat")
eq(K.packCredit(packs.coins500, true, coins).firstBonus, 500, "500 pack: doubled")
eq(K.packCredit(packs.coins1000, true, coins).firstBonus, 1000, "1000: doubled, the cap")
eq(K.packCredit(packs.starter, true, coins).total, 500, "starter: no first purchase bonus")

-- ------------------------------------------------------------------ shop.lua with a mocked engine and database
local registry, talks, sent = {}, {}, {}
local function obj(store, name)
	local o = {}
	function o:register() if store and name then store[name] = o end end
	function o:separator() end
	function o:type() end
	function o:interval() end
	return o
end
function CreatureEvent(name) return obj(registry, name) end
function GlobalEvent(name) return obj(registry, name) end
function TalkAction(words) return obj(talks, words) end
function addEvent() end
-- not stackable here (one item per count): Backpack of Holding, an exercise chest; everything else stackable
local NOSTACK = {[2365] = true, [27761] = true}
function ItemType(id) return {getClientId = function() return id end, getName = function() return "item " .. id end,
	getId = function() return id end, isStackable = function() return not NOSTACK[id] end} end
json = {encode = function(t) sent[#sent + 1] = t; return "" end, decode = function(b) return b end}

local DB = {coins = {}, purchases = {}, gifts = {}, orders = {}, queries = {}}
local players = {}
-- items made by the store delivery (store_delivery.lua): placed into a player's purse, inbox or backpack mock below
local function mockItem(id, n)
	local it = {id = id, count = n or 1}
	function it:getWeight() return self.count end
	function it:remove()
		local p = self.holder
		if p then
			p.items[self.id] = (p.items[self.id] or 0) - self.count
			p.placed[self.where] = (p.placed[self.where] or 0) - 1
			self.holder = nil
		end
		return true
	end
	return it
end
Game = {getPlayers = function() local l = {} for _, p in pairs(players) do l[#l + 1] = p end return l end,
	createItem = function(id, n) return mockItem(id, n) end}
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	asyncQuery = function() end,
	query = function(q)
		DB.queries[#DB.queries + 1] = q
		local a, v, add = q:match("INSERT INTO `chaos_shop_coins` %(`account_id`, `coins`%) VALUES %((%d+), (%d+)%) ON DUPLICATE KEY UPDATE `coins` = GREATEST%(0, `coins` %+ (%-?%d+)%)")
		if a then DB.coins[tonumber(a)] = math.max(0, (DB.coins[tonumber(a)] or 0) + tonumber(add)); return true end
		local amount, acc = q:match("UPDATE `chaos_shop_coins` SET `coins` = `coins` %- (%d+) WHERE `account_id` = (%d+)")
		if amount then
			acc, amount = tonumber(acc), tonumber(amount)
			-- as the engine: the query succeeds even when the WHERE matched no row; ROW_COUNT() tells
			if (DB.coins[acc] or 0) < amount then DB.rowCount = 0; return true end
			DB.coins[acc] = DB.coins[acc] - amount; DB.rowCount = 1; return true
		end
		local vals = q:match("INSERT INTO `chaos_shop_purchases` .- VALUES %((.*)%)$")
		if vals then
			local f = {}
			for x in (vals .. ","):gmatch("%s*('?[^,]*'?)%s*,") do f[#f + 1] = x:gsub("^'(.*)'$", "%1") end
			DB.purchases[#DB.purchases + 1] = {account = tonumber(f[1]), player = tonumber(f[2]), key = f[5], price = tonumber(f[8]),
				list = tonumber(f[9]), giftPlayer = tonumber(f[11]), created = tonumber(f[12])}
			return true
		end
		vals = q:match("INSERT INTO `chaos_shop_gifts` .- VALUES %((.*)%)$")
		if vals then
			local f = {}
			for x in (vals .. ","):gmatch("%s*('?[^,]*'?)%s*,") do f[#f + 1] = x:gsub("^'(.*)'$", "%1") end
			DB.gifts[#DB.gifts + 1] = {id = #DB.gifts + 1, target = tonumber(f[1]), key = f[2], title = f[3], price = tonumber(f[4]),
				from = tonumber(f[5]), fromName = f[6], status = 0}
			return true
		end
		local st, gid = q:match("UPDATE `chaos_shop_gifts` SET `status` = (%d+).-WHERE `id` = (%d+)")
		if st then DB.gifts[tonumber(gid)].status = tonumber(st); return true end
		local oid = q:match("UPDATE `chaos_coin_orders` SET `status` = 'credited'.-WHERE `id` = (%d+)")
		if oid then
			local o = DB.orders[tonumber(oid)]
			o.status = "credited"; o.total = tonumber(q:match("`coins` = (%d+)")) + tonumber(q:match("`bonus` = (%d+)")) +
				tonumber(q:match("`first_bonus` = (%d+)"))
			return true
		end
		oid = q:match("UPDATE `chaos_coin_orders` SET `status` = 'rejected'.-WHERE `id` = (%d+)")
		if oid then DB.orders[tonumber(oid)].status = "rejected"; return true end
		return true
	end
}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
Chaos.findPlayer = function(name)
	for _, p in pairs(players) do if p.name:lower() == name:lower() then return p.guid, p.name end end
	for _, p in pairs(DB.offline or {}) do if p.name:lower() == name:lower() then return p.guid, p.name end end
end
Chaos.giveItem = function(p, id, count)
	if p.full then return 0 end
	p.items[id] = (p.items[id] or 0) + count; return count
end
local function inList(q, key)
	local list = q:match("IN %((.-)%)")
	return list and list:find("'" .. key .. "'", 1, true)
end
Chaos.select = function(q, cols)
	local acc = tonumber(q:match("`account_id` = (%d+)"))
	if q:find("ROW_COUNT()", 1, true) then
		return {{n = DB.rowCount or 0}}
	elseif q:find("SELECT `coins` FROM `chaos_shop_coins`", 1, true) then
		local have = DB.coins[acc]
		if DB.afterCoinRead then DB.afterCoinRead(acc) end -- another process (the website) moves coins right after the read
		return have and {{coins = have}} or {}
	elseif q:find("SELECT COUNT(*) AS `n` FROM `chaos_shop_purchases`", 1, true) then
		local key, since = q:match("`offer_key` = '([^']*)'"), tonumber(q:match("`created` >= (%d+)")) or 0
		local count = 0
		for _, r in ipairs(DB.purchases) do
			if r.account == acc and (not key or r.key == key) and (key or not q:find("`offer_key` IN", 1, true) or inList(q, r.key)) and r.created >= since and (not q:find("`gift_player` > 0", 1, true) or r.giftPlayer > 0) then
				count = count + 1
			end
		end
		return {{n = count}}
	elseif q:find("JOIN `players` c ON", 1, true) then
		-- ownedByOthers (O317): offers another character of the account bought for itself and that still exists
		local account, me = tonumber(q:match("p%.`account_id` = (%d+)")), tonumber(q:match("p%.`player_id` <> (%d+)"))
		local out, seen = {}, {}
		for _, r in ipairs(DB.purchases) do
			local alive = players[r.player] ~= nil
			for _, p in pairs(DB.offline or {}) do alive = alive or p.guid == r.player end
			if r.account == account and r.player ~= me and r.giftPlayer == 0 and alive and inList(q, r.key) and not seen[r.key] then
				seen[r.key] = true
				out[#out + 1] = {offer_key = r.key}
			end
		end
		return out
	elseif q:find("SELECT DISTINCT `offer_key`", 1, true) then
		local out = {}
		for _, r in ipairs(DB.purchases) do if r.account == acc and inList(q, r.key) then out[#out + 1] = {offer_key = r.key} end end
		return out
	elseif q:find("FROM `players` WHERE `id`", 1, true) then
		local id = tonumber(q:match("`id` = (%d+)"))
		for _, p in pairs(players) do if p.guid == id then return {{account_id = p.account, group_id = p.group}} end end
		for _, p in pairs(DB.offline or {}) do if p.guid == id then return {{account_id = p.account, group_id = p.group}} end end
		return {}
	elseif q:find("FROM `account_bans`", 1, true) then
		return {{n = (DB.banned or {})[acc] and 1 or 0}}
	elseif q:find("FROM `chaos_shop_gifts`", 1, true) then
		local target = tonumber(q:match("`target_player` = (%d+)"))
		local out = {}
		for _, g in ipairs(DB.gifts) do
			if g.target == target and g.status == 0 then
				out[#out + 1] = {id = g.id, offer_key = g.key, title = g.title, price = g.price, from_account = g.from, from_name = g.fromName}
			end
		end
		return out
	elseif q:find("SELECT `status` FROM `chaos_coin_orders` WHERE `id`", 1, true) then
		local o = DB.orders[tonumber(q:match("`id` = (%d+)"))]
		return o and {{status = o.status}} or {}
	elseif q:find("FROM `chaos_coin_orders` WHERE `status` = 'paid'", 1, true) then
		local out = {}
		for i, o in ipairs(DB.orders) do if o.status == "paid" then out[#out + 1] = {id = i, account_id = o.account, pack_key = o.pack} end end
		return out
	elseif q:find("FROM `chaos_coin_orders` WHERE `account_id`", 1, true) then
		local c = 0
		for _, o in ipairs(DB.orders) do
			if o.account == acc and o.status == "credited" then
				local key = q:match("`pack_key` = '([^']*)'")
				local notIn = q:match("NOT IN %((.-)%)")
				if (not key or o.pack == key) and (not notIn or not notIn:find("'" .. o.pack .. "'", 1, true)) then c = c + 1 end
			end
		end
		return {{n = c}}
	end
	return {}
end

ChaosShopServices = {
	check = function(p, offer) if offer.unlock == "autoSeller" and p.autoSeller then return "You have the Auto Seller already." end end,
	deliver = function(p, offer) if offer.unlock == "autoSeller" then p.autoSeller = true end; p.services[#p.services + 1] = offer.key or offer.service; return true end
}
-- >>> Seasons: the real store rule (season_core.lua storeText with season_config.lua `store`), as season.lua uses it
dofile("data/scripts/chaos/season_core.lua")
local SeasonCore = ChaosSeason
local offlineRealm = {} -- guid -> realm of offline characters
ChaosSeason = {realmOf = function(p) return p.realm or 0 end,
	storeProblem = function(target, offer, gift, name)
		local realm = type(target) == "number" and (offlineRealm[target] or 0) or (target.realm or 0)
		return SeasonCore.storeText(realm, offer, season.store, gift, name or (type(target) ~= "number" and target:getName() or nil))
	end}
-- <<< Seasons
ChaosRateLimit = {allow = function() return true end}
local pactDays = 0
local pactSources, pactCapBlock = {}, false
ChaosPact = {grantDays = function(p, days, source)
		pactDays = pactDays + days
		pactSources[#pactSources + 1] = source
		ok(source == "store" or source == "complete", "pact source")
	end,
	-- the stacking cap (pact.lua Pact.checkDays): the test switches it on
	checkDays = function(p, days) if pactCapBlock then return "Your Chaos Pact already runs for more than 185 days. Buy more later." end end}

local nextGuid = 0
local function newPlayer(name, opt)
	nextGuid = nextGuid + 1
	local p = {name = name, guid = nextGuid, account = opt.account or nextGuid, sex = opt.sex or PLAYERSEX_MALE, level = opt.level or 20,
		premium = opt.premium ~= false, group = opt.group or 1, realm = opt.realm, storage = {}, outfits = {}, mounts = {}, items = {},
		services = {}, messages = {}, wings = {}, auras = {}, shaders = {}}
	function p:getName() return self.name end
	function p:getGuid() return self.guid end
	function p:getId() return self.guid end
	function p:getAccountId() return self.account end
	function p:getLevel() return self.level end
	function p:getSex() return self.sex end
	function p:isPremium() return self.premium end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:addOutfit(look, addons) self.outfits[look] = (self.outfits[look] or 0) end
	function p:addOutfitAddon(look, addon)
		local a = self.outfits[look] or 0
		if addon == 3 then a = 3 elseif a ~= addon and a ~= 3 then a = a + addon end
		self.outfits[look] = a
	end
	function p:hasOutfit(look, addons)
		local a = self.outfits[look]
		if not a then return false end
		return (addons or 0) == 0 or a == addons or a == 3
	end
	function p:addMount(id) self.mounts[id] = true end
	function p:hasMount(id) return self.mounts[id] == true end
	function p:addWings(id) self.wings[id] = true end
	function p:addAura(id) self.auras[id] = true end
	function p:addShader(id) self.shaders[id] = true end
	function p:addPremiumDays(d) self.premDays = (self.premDays or 0) + d end
	function p:removeItem(id, c) self.items[id] = (self.items[id] or 0) - c end
	-- the purse (store inbox), the depot inbox and the backpack (store_delivery.lua places items there)
	p.placed = {}
	local function place(where, it)
		it.holder, it.where = p, where
		p.items[it.id] = (p.items[it.id] or 0) + it.count
		p.placed[where] = (p.placed[where] or 0) + 1
		p.stacks = p.stacks or {}
		p.stacks[#p.stacks + 1] = {where = where, id = it.id, count = it.count}
		return RETURNVALUE_NOERROR or 0
	end
	function p:getStoreInbox()
		if self.noPurse then return nil end
		return {addItemEx = function(_, it) if self.full or self.purseFull then return 1 end return place("purse", it) end}
	end
	function p:getInbox()
		if not self.hasInbox then return nil end
		return {addItemEx = function(_, it) if self.full then return 1 end return place("inbox", it) end}
	end
	function p:addItemEx(it) if self.full or self.bagFull then return 1 end return place("backpack", it) end
	function p:getFreeCapacity() return self.cap or 1000000 end
	function p:getPosition() return {sendMagicEffect = function() end} end
	function p:sendExtendedOpcode() end
	function p:sendTextMessage(_, text) self.messages[#self.messages + 1] = text end
	function p:registerEvent() end
	players[p.guid] = p
	return p
end
function Player(x)
	for _, p in pairs(players) do if p.name == x or p.guid == x then return p end end
end

local function loadShop()
	sent = {}
	dofile("data/scripts/chaos/shop.lua")
end
loadShop()
local Shop = ChaosShop
local ext = registry.ChaosShopExtended

local function last(action)
	for i = #sent, 1, -1 do if sent[i].action == action then return sent[i] end end
end
local function request(p, action, data)
	sent = {}
	ext.onExtendedOpcode(p, ChaosOpcodes.shop, {action = action, data = data or {}})
end
-- category / page / offer index of an offer key in the player's view
local function find(p, key)
	for c, cat in ipairs(Shop.view(p)) do
		if cat.name ~= "Featured" then
			for i, e in ipairs(cat.offers) do
				if e.offer.key == key then
					local page = math.floor((i - 1) / cfg.perPage) + 1
					return c, page, i - (page - 1) * cfg.perPage, e
				end
			end
		end
	end
end
local function buy(p, key, gift)
	local c, page, o = find(p, key)
	ok(c, "offer in view: " .. key)
	request(p, "get_page", {category = c, page = page})
	local view = last("category_page").data.offers[o]
	request(p, "buy", {category = c, page = page, offer = o, title = view.title, cost = view.cost, gift = gift})
	local m = last("message")
	return m and m.data.title, m and m.data.msg, view
end

local A = newPlayer("Alice", {sex = PLAYERSEX_FEMALE, level = 20})
DB.coins[A.account] = 20000
-- the view: Starter first for a young character, then the weekly rotation ("This week")
local v = Shop.view(A)
eq(v[1].name, "Starter", "starter packs first"); eq(v[2].name, "This week", "then the weekly rotation")
eq(#v[2].offers, cfg.storefront.featured.count, "rotation count")
ok(cfg.storefront.featured.count >= 4 and cfg.storefront.featured.count <= 6, "4-6 offers a week")
ok(v[2].endsIn > 0 and v[2].endsIn <= 7 * 86400, "the rotation's countdown")
for _, c in ipairs(v) do
	ok(c.name ~= "Themed Sets", "a rotationOnly category is never shown on its own")
end

-- an outfit: both looks, both addons
local title, msg, view = buy(A, "outfit:1237")
eq(title, "Purchase complete", msg)
eq(A.outfits[1237], 3, "male look with addons"); eq(A.outfits[1238], 3, "female look with addons")
eq(view.outfit.type, 1238, "female preview for a female viewer")
eq(#DB.purchases, 1, "logged"); eq(DB.purchases[1].key, "outfit:1237", "log key")
local before = DB.coins[A.account]
title, msg = buy(A, "outfit:1237")
eq(title, "Not possible", "duplicate outfit refused"); eq(DB.coins[A.account], before, "no coins taken")
local _, _, v2 = buy(A, "outfit:1237")
ok(v2.owned, "shown as owned")

-- a mount, an aura (storage), a frame
eq(buy(A, "mount:121"), "Purchase complete", "mount"); ok(A.mounts[121], "mount added")
eq(buy(A, "mount:121"), "Not possible", "duplicate mount refused")
eq(buy(A, "aura:6"), "Purchase complete", "aura"); ok(A.auras[6] and A.storage[Chaos.storage.shopAuraBase + 6] == 1, "aura and storage")
eq(buy(A, "aura:6"), "Not possible", "duplicate aura")
-- the offers carry their own look (client icon and preview): a mount, a frame, a bundle of parts
do
	local function viewOf(key)
		local c, page, o = find(A, key)
		ok(c, "offer in view for its look: " .. key)
		request(A, "get_page", {category = c, page = page})
		return last("category_page").data.offers[o]
	end
	local mv = viewOf("mount:119")
	eq(mv.look.kind, "mount", "mount look"); eq(mv.look.look, mv.outfit.type, "the mount look is the icon's creature")
	local fv = viewOf("frame:ember")
	eq(fv.look.kind, "nameplate", "frame look"); eq(fv.look.frame, "ember", "frame name")
	local bv = viewOf("bundle:glacial")
	eq(bv.look.kind, "bundle", "bundle look"); ok(#bv.look.parts >= 2, "the bundle shows its parts (outfit and mount; wings and auras need the XML files)")
	eq(bv.type, "outfit", "a bundle of looks is drawn as a creature wearing them")
	ok(bv.outfit.mount, "the mount is on the bundle icon (wings and auras need the XML files, absent in this test)")
	local iv = viewOf("item:2304x100")
	eq(iv.look, nil, "an item has no look"); eq(iv.type, "item", "an item keeps its picture")
end
eq(buy(A, "frame:frost"), "Purchase complete", "frame")
eq(Shop.frameOf(A), "frost", "frame shown")
Shop.plateFrame(A, "off"); eq(Shop.frameOf(A), nil, "title frame")
Shop.plateFrame(A, "violet"); eq(Shop.frameOf(A), nil, "a frame not owned cannot be picked")
Shop.plateFrame(A, "frost"); eq(Shop.frameOf(A), "frost", "back to frost")
-- addons of an outfit everyone has
eq(buy(A, "addons:128"), "Purchase complete", "addons"); eq(A.outfits[136], 3, "female citizen addons")
-- unlocks stay unlocks (owner 2026-10-16, store items to the purse): outfits, addons, mounts, wings, auras, frames,
-- services put nothing in the purse and send no delivery line
eq(next(A.placed), nil, "unlocks: nothing placed in the purse, inbox or backpack")
eq(buy(A, "wings:1"), "Purchase complete", "wings") eq(next(A.placed), nil, "wings: an unlock, not an item")
for _, m in ipairs(A.messages) do ok(not m:find("Delivered", 1, true), "no delivery line for an unlock: " .. m) end

-- the sale price is what is charged; a stale price is refused
local c, page, o, e = find(A, "wings:1")
ok(e.oldCost and e.cost < e.oldCost or os.time() >= K.parseTime("2026-10-24 06:00"), "wings on sale during the launch sale")
request(A, "buy", {category = c, page = page, offer = o, title = "Fiery Wings", cost = e.cost + 1})
eq(last("message").data.title, "Error", "stale price refused")

-- premium outfits need premium
local B = newPlayer("Bob", {premium = false})
DB.coins[B.account] = 5000
eq(buy(B, "outfit:151"), "Not possible", "premium outfit without premium")

-- weekly limit
for i = 1, 5 do eq(buy(B, "item:32256x10"), "Purchase complete", "whetstones " .. i) end
title, msg = buy(B, "item:32256x10")
eq(title, "Not possible", "weekly limit"); ok(msg:find("this week"), msg)
-- beta test mode (beta_mode_core.lua) never lifts a store limit on its own: Chaos Coins are bought with real money
local betaBefore = Chaos.betaMode
Chaos.betaMode = {enabled = true, storeOfferKeys = {}}
title, msg = buy(B, "item:32256x10")
eq(title, "Not possible", "beta mode on: the store weekly limit stays"); ok(msg:find("this week"), msg)
-- only an offer the owner names in storeOfferKeys is lifted
Chaos.betaMode = {enabled = true, storeOfferKeys = {"item:32256x10"}}
eq(buy(B, "item:32256x10"), "Purchase complete", "beta mode on + the owner named the offer: lifted")
Chaos.betaMode = {enabled = false, storeOfferKeys = {"item:32256x10"}}
title = buy(B, "item:32256x10")
eq(title, "Not possible", "beta mode off: a named offer is capped again")
Chaos.betaMode = betaBefore

-- season characters
local S1 = newPlayer("Seasoned", {realm = 1})
DB.coins[S1.account] = 1000
eq(buy(S1, "item:28095x1"), "Not possible", "no double experience potion for season characters")

-- a bundle at 20% off; refused when one part is owned
local before2 = DB.coins[B.account]
_, _, e = find(B, "bundle:frostborn")
_, _, _, e = find(B, "bundle:frostborn")
eq(e.cost, math.floor(e.offer.listSum * 0.8), "bundle price"); eq(e.oldCost, e.offer.listSum, "list price shown")
eq(buy(B, "bundle:frostborn"), "Purchase complete", "bundle")
eq(DB.coins[B.account], before2 - e.cost, "bundle cost")
ok(B.wings[10] and B.auras[16] and B.shaders[10] and B.mounts[119], "every part delivered")
ok(not find(B, "bundle:frostborn"), "every part owned: the bundle is hidden")
-- a part owned already: left out of the bundle and its price
local B3 = newPlayer("Bram", {level = 50})
DB.coins[B3.account] = 20000
eq(buy(B3, "wings:10"), "Purchase complete", "Nimbus Wings alone")
local _, _, _, e3 = find(B3, "bundle:frostborn")
local full = Shop.byKey["bundle:frostborn"]
eq(e3.offer.ownedParts, 1, "one part owned")
eq(#e3.offer.resolved, #full.resolved - 1, "the owned part left out")
eq(e3.offer.listSum, full.listSum - Shop.byKey["wings:10"].cost, "list price without it")
eq(e3.cost, math.floor(e3.offer.listSum * 0.8), "20% off the rest")
ok(e3.cost < full.cost, "cheaper than the full bundle")
local beforeB3 = DB.coins[B3.account]
eq(buy(B3, "bundle:frostborn"), "Purchase complete", "the rest of the bundle")
eq(DB.coins[B3.account], beforeB3 - e3.cost, "charged the lower price")
ok(B3.auras[16] and B3.shaders[10] and B3.mounts[119], "the other parts delivered")
-- the themed regalia: outfit + mount + wings + aura at 25%
local _, _, _, eg = find(B3, "bundle:pyre")
local pyre = Shop.byKey["bundle:pyre"]
eq(#pyre.resolved, 4, "regalia: four parts"); eq(pyre.cost, math.floor(pyre.listSum * 0.75), "regalia: 25% off")
ok(eg ~= nil, "regalia in view")

-- starter packs: once per account, level gate, hidden afterwards, pact days when the Pact exists
eq(buy(A, "starter:novice"), "Purchase complete", "novice pack")
ok(A.auras[17] and A.items[8472] == 100 and A.items[26031] == 100 and not A.items[27990], "novice parts (Supreme Health Potions, no stamina since 2026-10-15)"); eq(pactDays, 3, "pact days")
eq(A.placed.purse, 2, "the starter pack's potions in the purse")
ok(not find(A, "starter:novice"), "hidden once bought")
local A2 = newPlayer("Alicealt", {account = A.account, level = 10})
ok(not find(A2, "starter:novice"), "hidden for the whole account")
local Old = newPlayer("Veteran", {level = 400})
ok(not find(Old, "starter:champion"), "level gate hides it")
eq(Shop.view(Old)[1].name, "This week", "the weekly rotation first without starter packs")
-- a failing item part takes nothing and refunds
local Full = newPlayer("Fullbag", {level = 30})
Full.full = true
DB.coins[Full.account] = 1000
eq(buy(Full, "starter:adventurer"), "Error", "no room")
eq(DB.coins[Full.account], 1000, "refunded"); ok(not Full.mounts[23], "nothing given")

-- rune packs (owner approval 2026-10-13): the Runes category, priced from chaos_rune_supply.lua's vendor gold
local runeLib = dofile("data/lib/chaos_rune_supply.lua")
local runeCat
for _, c in ipairs(cfg.categories) do
	if c.name == "Runes" then runeCat = c end
	if c.name == "Supplies" then
		for _, o in ipairs(c.offers) do ok(o.id ~= 2304 and o.id ~= 2268 and o.id ~= 2273, "Supplies holds no rune any more: " .. o.name) end
	end
end
ok(runeCat and #runeCat.offers >= 25, "a Runes category with the packs")
local priceOf = {}
for _, r in ipairs(runeLib.runes) do priceOf[r.id] = r.price end
local sizes = {}
for _, o in ipairs(runeCat.offers) do
	ok(priceOf[o.id] ~= nil, o.name .. ": a rune of the supply list")
	local gold = priceOf[o.id] * o.count
	ok(o.cost >= math.ceil(gold * 0.9 / 1000) and o.cost <= math.ceil(gold / 1000), o.name .. ": about 1000 vendor gold a coin (" .. o.cost .. ")")
	ok(o.overflowInbox, o.name .. ": backpack, then the store inbox")
	sizes[o.id] = (sizes[o.id] or 0) + 1
end
for _, id in ipairs({2304, 2288, 2315, 2274, 2268, 2311, 2265, 2273}) do eq(sizes[id], 3, "100 / 250 / 500 of rune " .. id) end
ok(sizes[2278] and sizes[2261], "Shackle and Dispel packs")
eq(Shop.byKey["item:2304x100"].cost, math.ceil(84 * 100 / 1000), "100 Searing Orb Runes: 9 coins (the old Supplies offer, same key)")
ok(Shop.byKey["item:2304x500"].cost < 5 * Shop.byKey["item:2304x100"].cost, "the big pack is cheaper per rune")
-- delivery (owner 2026-10-16: store items go to the purse): stacks of 100 into the purse
local Rune = newPlayer("Runa", {level = 60})
DB.coins[Rune.account] = 1000
eq(buy(Rune, "item:2304x500"), "Purchase complete", "500 Searing Orb Runes")
eq(Rune.items[2304], 500, "all delivered")
eq(Rune.placed.purse, 5, "five stacks in the purse")
eq(Rune.stacks[1].count, 100, "stacks of 100")
ok(Rune.messages[#Rune.messages]:find("purse"), "told: delivered to the purse")
-- the purse cannot take them: the depot inbox (weight free), then the backpack
Rune.purseFull, Rune.hasInbox = true, true
eq(buy(Rune, "item:2268x250"), "Purchase complete", "250 Reaper's Runes with the purse refusing")
eq(Rune.items[2268], 250, "all delivered") eq(Rune.placed.inbox, 3, "three stacks to the depot inbox")
ok(Rune.messages[#Rune.messages]:find("depot inbox"), "told where: " .. Rune.messages[#Rune.messages])
-- no purse, no inbox: the backpack
Rune.purseFull, Rune.hasInbox, Rune.noPurse = nil, nil, true
eq(buy(Rune, "item:2265x100"), "Purchase complete", "100 Mending Runes without a purse")
eq(Rune.placed.backpack, 1, "the backpack") ok(Rune.messages[#Rune.messages]:find("no purse"), "told why")
-- nowhere: nothing kept, refunded
Rune.bagFull = true
local coinsR = DB.coins[Rune.account]
eq(buy(Rune, "item:2265x250"), "Error", "no purse, no inbox, no room: refused")
eq(DB.coins[Rune.account], coinsR, "refunded")
eq(Rune.items[2265], 100, "nothing more kept (stacks placed before the failure taken back)")
-- capacity: the purse counts in the inventory weight, so an item too heavy goes to the depot inbox
local Heavy = newPlayer("Heavy", {level = 60})
Heavy.cap, Heavy.hasInbox = 10, true
DB.coins[Heavy.account] = 1000
eq(buy(Heavy, "item:2304x100"), "Purchase complete", "100 runes, capacity 10")
eq(Heavy.placed.inbox, 1, "too heavy for the purse: depot inbox") eq(Heavy.placed.purse, nil, "not the purse")
ok(Heavy.messages[#Heavy.messages]:find("capacity"), "told: capacity")
-- a bundle whose later part fails takes back the items placed in the purse
local Bun = newPlayer("Bundler", {level = 30})
DB.coins[Bun.account] = 5000
function Bun:addMount() end -- the mount part fails after the potions are in the purse
eq(buy(Bun, "starter:adventurer"), "Error", "a failing part")
eq(DB.coins[Bun.account], 5000, "refunded")
eq(Bun.placed.purse, 0, "the potions placed before were taken back out of the purse")
for id, n in pairs(Bun.items) do eq(n, 0, "nothing kept of item " .. id) end

-- gifts: online, offline (delivered at login), refused targets
local Cara = newPlayer("Cara", {})
eq(buy(A, "aura:7", "Cara"), "Gift sent", "online gift"); ok(Cara.auras[7], "delivered at once")
eq(DB.purchases[#DB.purchases].giftPlayer, Cara.guid, "gift logged")
eq(buy(A, "aura:7", "Cara"), "Not possible", "target owns it")
eq(buy(A, "service:blessings", "Cara"), "Not possible", "services cannot be gifted")
-- Hideouts: an unlock offer with gift = true (hideout_store.lua) may be gifted; other unlocks may not
eq(buy(A, "unlock:hideout_gargoyle", "Cara"), "Gift sent", "a hideout decoration is giftable")
eq(buy(A, "unlock:autoSeller", "Cara"), "Not possible", "other unlocks are not giftable")
local Gm = newPlayer("Gamemaster", {group = 4})
eq(buy(A, "aura:8", "Gamemaster"), "Not possible", "no gifts to staff")
eq(buy(A, "aura:8", "Alice"), "Not possible", "not to yourself")
DB.offline = {{name = "Dorian", guid = 900, account = 900, group = 1}}
local coinsBefore = DB.coins[A.account]
eq(buy(A, "outfit:909", "Dorian"), "Gift sent", "offline gift queued")
eq(#DB.gifts, 1, "queued"); eq(DB.coins[A.account], coinsBefore - DB.gifts[1].price, "paid")
nextGuid = 899
local Dorian = newPlayer("Dorian", {account = 900})
DB.offline = nil
Shop.deliverGifts(Dorian)
eq(DB.gifts[1].status, 1, "delivered at login"); eq(Dorian.outfits[909], 3, "outfit with addons")
-- an offline gift the target owns by then is refunded
DB.offline = {{name = "Erin", guid = 950, account = 950, group = 1}}
eq(buy(A, "mount:120", "Erin"), "Gift sent", "offline gift 2")
nextGuid = 949
local Erin = newPlayer("Erin", {account = 950})
Erin.mounts[120] = true
local beforeRefund = DB.coins[A.account]
Shop.deliverGifts(Erin)
eq(DB.gifts[2].status, 2, "refunded"); eq(DB.coins[A.account], beforeRefund + DB.gifts[2].price, "coins back")

-- >>> Seasons: coins are account-wide; a season character gets only cosmetics and account services
local Sea = newPlayer("Ashling", {realm = 1, level = 20})
DB.coins[Sea.account] = 5000
title, msg = buy(Sea, "item:7590x100")
eq(title, "Not possible", "season character: no supplies"); ok(msg:find("not for season characters", 1, true), msg)
eq(buy(Sea, "item:32256x10"), "Not possible", "season character: no whetstones")
eq(buy(Sea, "starter:novice"), "Not possible", "season character: no starter pack (potions, stamina)")
eq(buy(Sea, "service:blessings"), "Not possible", "season character: no blessings (the Stamina Refill offer is gone, 2026-10-15)")
do -- the Stamina Refill is not sold any more (pay to farm; catchup.lua halves low stamina loot instead)
	local refill = false
	for _, cat in ipairs(dofile("data/scripts/chaos/shop_config.lua").categories or {}) do
		for _, o in ipairs(cat.offers or {}) do
			if o.kind == "service" and o.service == "stamina" then refill = true end
		end
	end
	eq(refill, false, "no Stamina Refill offer")
end
eq(buy(Sea, "unlock:autoSeller"), "Not possible", "season character: no Auto Seller")
eq(DB.coins[Sea.account], 5000, "nothing taken")
eq(buy(Sea, "wings:1"), "Purchase complete", "season character: wings")
eq(buy(Sea, "service:sexChange"), "Purchase complete", "season character: sex change")
-- gifts: online and offline season receivers get only cosmetics
title, msg = buy(A, "item:8472x100", "Ashling")
eq(title, "Not possible", "no supplies as a gift to a season character"); ok(msg:find("Ashling is a season character", 1, true), msg)
eq(buy(A, "aura:5", "Ashling"), "Gift sent", "a cosmetic gift to a season character"); ok(Sea.auras[5], "delivered")
DB.offline = {{name = "Cinder", guid = 970, account = 970, group = 1}}
offlineRealm[970] = 1
eq(buy(A, "item:8472x100", "Cinder"), "Not possible", "no supplies to an offline season character")
-- a gift queued for a standard character that joins a season before its next login is refunded
DB.offline = {{name = "Turncoat", guid = 980, account = 980, group = 1}}
local gifts0 = #DB.gifts
eq(buy(A, "item:8472x100", "Turncoat"), "Gift sent", "offline gift to a standard character")
eq(#DB.gifts, gifts0 + 1, "queued")
nextGuid = 979
local Turncoat = newPlayer("Turncoat", {account = 980, realm = 1})
DB.offline = nil
local beforeTurn = DB.coins[A.account]
Shop.deliverGifts(Turncoat)
eq(DB.gifts[gifts0 + 1].status, 2, "refused at login: the receiver is a season character now")
eq(DB.coins[A.account], beforeTurn + DB.gifts[gifts0 + 1].price, "coins back"); eq(Turncoat.items[8472], nil, "no potions")
-- <<< Seasons

-- coin orders: pack bonus, first purchase bonus once, starter once, unknown pack rejected
DB.orders = {{account = 77, pack = "coins500", status = "paid"}, {account = 77, pack = "coins500", status = "paid"},
	{account = 77, pack = "starter", status = "paid"}, {account = 77, pack = "starter", status = "paid"}, {account = 77, pack = "nope", status = "paid"}}
Shop.processOrders()
eq(DB.orders[1].total, 1025, "first pack with the first purchase bonus (double)"); eq(DB.orders[2].total, 525, "second pack without")
eq(DB.orders[3].total, 500, "starter"); eq(DB.orders[4].status, "rejected", "second starter rejected")
eq(DB.orders[5].status, "rejected", "unknown pack"); eq(DB.coins[77], 1025 + 525 + 500, "coins credited")
Shop.processOrders()
eq(DB.coins[77], 2050, "credited once")
-- refunded on the website between the crediting step's SELECT and its locked re-read: nothing credited
DB.orders[#DB.orders + 1] = {account = 77, pack = "coins250", status = "paid"}
local realSelect = Chaos.select
Chaos.select = function(q, cols)
	if q:find("FOR UPDATE", 1, true) then DB.orders[#DB.orders].status = "refunded" end
	return realSelect(q, cols)
end
Shop.processOrders()
Chaos.select = realSelect
eq(DB.orders[#DB.orders].status, "refunded", "refunded order left alone"); eq(DB.coins[77], 2050, "no coins for a refunded order")

-- Chaos Coin gifts through shop.lua: hold, cap, ban, ledger
do
	local G1 = newPlayer("Giver", {account = 501})
	local R1 = newPlayer("Receiver", {account = 502})
	local orders, ledger = {}, {}
	DB.coins[501] = 10000
	local baseSelect, baseQuery = Chaos.select, db.query
	Chaos.select = function(q, cols)
		if q:find("MAX(`credited`)", 1, true) then
			local acc = tonumber(q:match("`account_id` = (%d+)"))
			return {{t = orders[acc] or 0, id = orders[acc] and 1 or 0}}
		elseif q:find("FROM `chaos_coin_gifts`", 1, true) then
			local from, since = tonumber(q:match("`from_account` = (%d+)")), tonumber(q:match("`created` >= (%d+)"))
			local sum = 0
			for _, g in ipairs(ledger) do if g.from == from and g.created >= since then sum = sum + g.amount end end
			return {{n = sum}}
		end
		return baseSelect(q, cols)
	end
	db.query = function(q)
		local f, t, a, o, c = q:match("INSERT INTO `chaos_coin_gifts` .- VALUES %((%d+), (%d+), (%d+), (%d+), (%d+)%)")
		if f then ledger[#ledger + 1] = {from = tonumber(f), to = tonumber(t), amount = tonumber(a), order = tonumber(o), created = tonumber(c)}; return true end
		return baseQuery(q)
	end
	orders[501] = os.time() - 3600
	request(G1, "gift_coins", {name = "Receiver", amount = 100})
	eq(DB.coins[501], 10000, "no coin gift right after a donation")
	ok(last("message").data.msg:find("days after your last donation", 1, true), "told why")
	orders[501] = os.time() - (cfg.coinGifts.holdDays + 1) * 86400
	request(G1, "gift_coins", {name = "Receiver", amount = 100})
	eq(DB.coins[501], 9900, "gift after the hold")
	eq(DB.coins[502], 100, "received")
	eq(#ledger, 1, "the gift is in the ledger")
	eq(ledger[1].order, 1, "with the sender's last credited order")
	request(G1, "gift_coins", {name = "Receiver", amount = cfg.coinGifts.perDay})
	eq(DB.coins[501], 9900, "over the daily cap: refused")
	DB.banned = {[502] = true}
	request(G1, "gift_coins", {name = "Receiver", amount = 100})
	eq(DB.coins[501], 9900, "no coin gift to a banned account")
	DB.banned = nil
	Chaos.select, db.query = baseSelect, baseQuery
	-- /coins creates store currency: a gamemaster (group 4) is refused, an administrator (group 5) may; both logged
	local gm = newPlayer("Gamemaster", {group = 4, account = 601})
	local god = newPlayer("Admin", {group = 5, account = 602})
	for _, p in ipairs({gm, god, R1}) do
		function p:getGroup() local g = self.group; return {getId = function() return g end, getAccess = function() return g >= 4 end} end
		function p:sendCancelMessage(t) self.cancel = t end
		function p:sendTextMessage() end
	end
	local logged = {}
	ChaosAdmin = {log = function(p, action, _, params, status) logged[#logged + 1] = {p = p, action = action, status = status} end}
	local before = DB.coins[502]
	eq(talks["/coins"].onSay(gm, "/coins", "Receiver, 500"), false, "staff words are swallowed")
	eq(DB.coins[502], before, "a gamemaster cannot create coins")
	eq(logged[1] and logged[1].status, "denied", "the refusal is logged")
	talks["/coins"].onSay(god, "/coins", "Receiver, 500")
	eq(DB.coins[502], before + 500, "an administrator can")
	eq(logged[2] and logged[2].action, "talk/coins", "the use is logged")
	eq(talks["/coins"].onSay(R1, "/coins", "Receiver, 500"), true, "a player: said as chat, nothing else")
	eq(#logged, 2, "players are not logged")
	ChaosAdmin = nil
end

-- the website's bazaar takes coins from another process: between the balance read and the UPDATE the coins can go;
-- the UPDATE then changes no row and the purchase must not go through (it used to deliver for free)
do
	local Racer = newPlayer("Racer", {account = 777})
	DB.coins[777] = 20
	local e = Shop.byKey["item:2304x100"]
	ok(e and e.cost <= 20, "a cheap offer for the race")
	DB.afterCoinRead = function(acc) if acc == 777 then DB.coins[777] = 0 end end
	local had = Racer.items[2304] or 0
	local recv = DB.coins[502]
	request(Racer, "gift_coins", {name = "Receiver", amount = 10})
	eq(DB.coins[777], 0, "coin gift: the sender has nothing")
	eq(DB.coins[502], recv, "coin gift: the receiver got nothing (no coins created)")
	DB.coins[777] = 20
	-- buy() reads the balance twice (its own check, then spend): the coins go right after the second read
	local reads = 0
	DB.afterCoinRead = function(acc)
		if acc == 777 then
			reads = reads + 1
			if reads == 2 then DB.coins[777] = 0 end
		end
	end
	local _, gp = find(Racer, "item:2304x100")
	request(Racer, "get_page", {category = (find(Racer, "item:2304x100")), page = gp})
	reads = 0
	local c, pg, o = find(Racer, "item:2304x100")
	local view = last("category_page").data.offers[o]
	request(Racer, "buy", {category = c, page = pg, offer = o, title = view.title, cost = view.cost})
	local title = last("message") and last("message").data.title
	DB.afterCoinRead = nil
	ok(title ~= "Purchase complete", "store purchase refused: " .. tostring(title))
	eq(Racer.items[2304] or 0, had, "store purchase: nothing delivered when the coins went meanwhile")
	eq(DB.coins[777], 0, "and no coins created")
end

-- outfit shaders: a mark without the engine's ownership (bought before server src-patch 0036) gets it at login
do
	local K = ChaosShopCore
	local marks = {[3] = 1, [10] = 1, [12] = 0, [59] = 1, [60] = 1}
	local ids = K.markedShaders(function(id) return marks[id] or -1 end)
	eq(table.concat(ids, ","), "3,10,59", "marked shader ids (0 and past the block are not marks)")
	local P = newPlayer("Shadered", {})
	P.storage[Chaos.storage.shopShaderBase + 11] = 1
	P.storage[Chaos.storage.shopShaderBase + 24] = 1
	registry.ChaosShopLogin.onLogin(P)
	ok(P.shaders[11] and P.shaders[24], "login adds the engine's ownership of the marked shaders")
	eq(P.shaders[10], nil, "an unmarked shader is not added")
	eq(Shop.syncShaders(P), 2, "a second sync adds the same two again (idempotent in the engine)")
	local noApi = newPlayer("NoShaderApi", {})
	noApi.addShader = nil
	noApi.storage[Chaos.storage.shopShaderBase + 11] = 1
	eq(Shop.syncShaders(noApi), 0, "an engine without Player:addShader: nothing to do")
	-- buying one sets the mark and the ownership; the next login keeps both
	local C1 = newPlayer("Shaderbuyer", {})
	ok(Shop.deliver(C1, {kind = "shader", id = 11}) == true, "a store shader delivered")
	ok(C1.shaders[11] and C1.storage[Chaos.storage.shopShaderBase + 11] == 1, "mark and ownership")
	C1.shaders = {}
	registry.ChaosShopLogin.onLogin(C1)
	ok(C1.shaders[11], "ownership back at login")
end

-- ------------------------------------------------------------------ the category tree (2026-10-21) and the search
do
	local T = newPlayer("Treewalker", {level = 400})
	DB.coins[T.account] = 5000
	-- init: the parents first, then the flat list in tree order (an old client reads only "categories")
	request(T, "init")
	eq(sent[1] and sent[1].action, "category_groups", "the parents come first")
	eq(sent[2] and sent[2].action, "categories", "then the categories")
	local groups, cats = sent[1].data, sent[2].data
	local gname = {}
	for i, g in ipairs(groups) do gname[i] = g.name end
	eq(table.concat(gname, "|"), "Premium & Services|Consumables|Cosmetics", "the three parents, in tree order")
	for _, g in ipairs(groups) do
		ok(g.type == "item" or g.type == "outfit", "a parent icon: " .. g.name)
		ok(g.size > 0 and g.children > 0, "a parent's offers and subcategories: " .. g.name)
	end
	eq(cats[1].name, "This week", "a level 400 character: the rotation first")
	eq(cats[1].parent, nil, "the rotation is a top category")
	local seenParent, closed = {}, {}
	local prev
	for i, c in ipairs(cats) do
		ok(c.size and c.size > 0, "a category's offer count: " .. c.name)
		ok(c.pages == math.max(1, math.ceil(c.size / cfg.perPage)), "pages from the count: " .. c.name)
		-- a parent's subcategories stand together
		if c.parent ~= prev and prev then closed[prev] = true end
		ok(not (c.parent and closed[c.parent]), "subcategories of " .. tostring(c.parent) .. " together (" .. c.name .. ")")
		if c.parent then seenParent[c.parent] = (seenParent[c.parent] or 0) + 1 end
		prev = c.parent
		ok(c.name ~= "Depot Tabs" and c.name ~= "Chaos Shaders" and c.name ~= "Supplies" and c.name ~= "Boosts",
			"a category of before the clean-up: " .. c.name)
	end
	for _, g in ipairs(groups) do
		eq(seenParent[g.name], g.children, "the parent's subcategory count: " .. g.name)
	end
	-- a sale on a parent covers its subcategories
	local wings = Shop.byKey["wings:1"]
	local c0 = K.price(wings, "Wings", {now = os.time(), sales = {{categories = {"Cosmetics"}, pct = 30}}}, "Cosmetics")
	eq(c0, math.floor(wings.cost * 0.7), "a sale on Cosmetics lowers the wings")
	local c1 = K.price(Shop.byKey["item:7590x100"], "Potions", {now = os.time(), sales = {{categories = {"Cosmetics"}, pct = 30}}}, "Consumables")
	eq(c1, Shop.byKey["item:7590x100"].cost, "not the potions")

	-- search: every word in the title, category or parent; results say where they are (at) and their path
	request(T, "search", {text = "  PLATE frost "})
	local res = last("search_results")
	ok(res and res.data.text == "  PLATE frost ", "the results name their search")
	eq(#res.data.offers, 1, "one offer is a frost plate (every frame is in Name Plates, one is frost)")
	local hit = res.data.offers[1]
	eq(hit.title, "Frost Plate Frame", "the frame found")
	eq(table.concat(hit.path, ">"), "Cosmetics>Name Plates", "its path")
	request(T, "search", {text = "potions"})
	res = last("search_results")
	ok(#res.data.offers >= 4, "the category name matches too: " .. #res.data.offers)
	request(T, "search", {text = "cosmetics"})
	eq(#last("search_results").data.offers, 30, "at most 30 results")
	request(T, "search", {text = ""})
	eq(#last("search_results").data.offers, 0, "an empty search finds nothing")
	request(T, "search", {text = "this week"})
	for _, o in ipairs(last("search_results").data.offers) do
		ok(o.path[1] ~= "This week", "the rotation is not searched (its offers are in their categories)")
	end
	-- buy from the results: buy sends the result's `at`, the server finds the same offer
	request(T, "search", {text = "Strength Wings"})
	hit = last("search_results").data.offers[1]
	ok(hit and hit.title == "Strength Wings", "wings 15 under their own name, not the base typo")
	request(T, "buy", {category = hit.at.category, page = hit.at.page, offer = hit.at.offer, title = hit.title, cost = hit.cost})
	eq(last("message").data.title, "Purchase complete", "bought from the search results")
	ok(T.storage[Chaos.storage.shopWingsBase + 15] == 1, "the wings 15 delivered")
end

-- a reload builds the same store and keeps what was bought
local keysBefore = #Shop.view(A)
loadShop()
ext = registry.ChaosShopExtended
eq(#ChaosShop.view(A), keysBefore, "same categories after a reload")
eq(buy(A, "outfit:1237"), "Not possible", "still owned after a reload")

-- potion packs (2026-10-23): six potions in 100 / 250 / 500, the 100 packs keep their keys and coins, bigger packs
-- cost less a potion
for id, c100 in pairs({[7590] = 15, [8472] = 15, [8473] = 27, [26029] = 33, [26030] = 33, [26031] = 42}) do
	local a, b, c = Shop.byKey["item:" .. id .. "x100"], Shop.byKey["item:" .. id .. "x250"], Shop.byKey["item:" .. id .. "x500"]
	ok(a and b and c, "potion " .. id .. ": three packs")
	eq(a.cost, c100, "potion " .. id .. ": 100 pack coins")
	ok(b.cost / 250 < a.cost / 100 and c.cost / 500 < b.cost / 250, "potion " .. id .. ": bigger packs cost less a potion")
end


-- ------------------------------------------------------------------ O317: Pacto Completo, prices by level, account discount,
-- the weekly group of the Lasting Exercise weapons
-- core: the price of a level tier, the discount, and the validation
do
	local tiers = {cost = 60, levelPrices = {{upTo = 200, cost = 60}, {upTo = 500, cost = 100}, {cost = 150}}}
	eq(K.levelCost(tiers, 1), 60, "level 1: 60") eq(K.levelCost(tiers, 200), 60, "level 200: 60")
	eq(K.levelCost(tiers, 201), 100, "level 201: 100") eq(K.levelCost(tiers, 500), 100, "level 500: 100")
	eq(K.levelCost(tiers, 501), 150, "level 501: 150") eq(K.levelCost(tiers, 3000), 150, "level 3000: 150")
	eq(K.levelCost({cost = 77}, 800), 77, "no tiers: the cost")
	eq(K.discountCost(250, 50), 125, "half of 250") eq(K.discountCost(75, 50), 38, "rounded up") eq(K.discountCost(1, 50), 1, "at least 1")
	eq(K.discountCost(100, 150), 10, "capped at 90% off")
	local function problemsOf(offer)
		return K.validate({categories = {{name = "C", offers = {offer}}}}, nil)
	end
	local function has(list, text) for _, p in ipairs(list) do if p:find(text, 1, true) then return true end end return false end
	ok(has(problemsOf({kind = "service", service = "x", cost = 60, levelPrices = {{upTo = 200, cost = 60}, {upTo = 100, cost = 90}, {cost = 150}}}), "must rise"), "tiers that fall are caught")
	ok(has(problemsOf({kind = "service", service = "x", cost = 60, levelPrices = {{upTo = 200, cost = 60}, {upTo = 500, cost = 100}}}), "needs no upTo"), "a last tier with an upTo is caught")
	ok(has(problemsOf({kind = "service", service = "x", cost = 70, levelPrices = {{upTo = 200, cost = 60}, {cost = 150}}}), "first levelPrices"), "a cost that is not the first tier is caught")
	ok(has(problemsOf({kind = "service", service = "x", cost = 60, accountDiscount = 95}), "accountDiscount"), "a discount of 95 is caught")
	ok(has(problemsOf({kind = "item", id = 1, count = 1, cost = 60, accountDiscount = 50}), "per-character"), "a discount on a giftable kind is caught")
	ok(has(problemsOf({kind = "item", id = 1, count = 1, cost = 60, weeklyGroup = "g"}), "weeklyLimit"), "a weekly group without a limit is caught")
	eq(#problemsOf({kind = "service", service = "x", cost = 60, levelPrices = {{upTo = 200, cost = 60}, {cost = 150}}, accountDiscount = 50}), 0, "a good one")
end

-- Pacto Completo: the top offer of Premium & Services, 499 / 1350 / 2500, Pact days and premium days, not giftable
do
	local E = newPlayer("Elda", {level = 120, premium = true})
	DB.coins[E.account] = 10000
	local firstOfPremium
	for _, cat in ipairs(Shop.view(E)) do
		if cat.parent == "Premium & Services" and not firstOfPremium then firstOfPremium = cat end
	end
	eq(firstOfPremium.name, "Pacto Completo", "the Pacto Completo is the first category of Premium & Services")
	eq(#firstOfPremium.offers, 3, "three lengths")
	local c, page, o, e = find(E, "complete:30")
	eq(e.cost, 499, "30 days: 499") eq(e.oldCost, 598, "listed at the Pact (299) plus Premium (299)")
	eq(Shop.byKey["complete:90"].cost, 1350, "90 days: 1350") eq(Shop.byKey["complete:180"].cost, 2500, "180 days: 2500")
	eq(Shop.byKey["complete:90"].listSum, 897 + 800, "90 days: three Pacts apart and the 90 day Premium") eq(Shop.byKey["complete:180"].listSum, 1794 + 1500, "180 days apart")
	request(E, "get_page", {category = c, page = page})
	local view = last("category_page").data.offers[o]
	eq(view.gift, nil, "not giftable")
	ok(view.description:find("+10% XP", 1, true) and view.description:find("Premium:", 1, true) and view.description:find("Chaos Pact:", 1, true), "both benefit lists")
	ok(not view.description:find("days of Chaos Pact", 1, true), "no second Pact line")
	ok(#view.description <= 200, "short enough for three lines of the store")
	local days0, prem0, srcs0 = pactDays, E.premDays or 0, #pactSources
	eq(buy(E, "complete:30"), "Purchase complete", "bought")
	eq(pactDays - days0, 30, "30 Pact days") eq((E.premDays or 0) - prem0, 30, "30 premium days")
	eq(pactSources[srcs0 + 1], "complete", "the Pact days say where they came from")
	eq(DB.coins[E.account], 10000 - 499, "499 coins")
	eq(DB.purchases[#DB.purchases].key, "complete:30", "logged under the bundle key")
	-- the stacking cap: nothing is taken, nothing is given
	pactCapBlock = true
	local coinsBefore, daysBefore, premBefore = DB.coins[E.account], pactDays, E.premDays
	local title, msg = buy(E, "complete:180")
	eq(title, "Not possible", "refused at the cap") ok(msg:find("185 days", 1, true), msg)
	eq(DB.coins[E.account], coinsBefore, "no coins taken") eq(pactDays, daysBefore, "no Pact days") eq(E.premDays, premBefore, "no premium days")
	pactCapBlock = false
	eq(buy(E, "complete:180"), "Purchase complete", "180 days")
	eq(pactDays - days0, 210, "30 + 180 Pact days") eq(E.premDays - prem0, 210, "30 + 180 premium days")
	-- a starter pack's Pact part stays tolerant of a missing Pact system, the Completo does not
	local saved = ChaosPact
	ChaosPact = nil
	title = buy(E, "complete:30")
	eq(title, "Not possible", "no Pact system: the Completo is not sold")
	ChaosPact = saved
	-- the Pact and Premium alone: 299 each
	eq(Shop.byKey["premium:30"].cost, 299, "Premium 30 days: 299") eq(Shop.byKey["premium:90"].cost, 800, "Premium 90 days: 800")
	eq(Shop.byKey["premium:180"].cost, 1500, "Premium 180 days: 1500")
end

-- All Blessings: the price follows the level, the store shows each player their own, a stale price is refused
do
	local function blessCost(p) local _, _, _, e = find(p, "service:blessings"); return e.cost end
	local L1, L2, L3, L4 = newPlayer("Lowbie", {level = 80}), newPlayer("Midlevel", {level = 350}), newPlayer("Highlevel", {level = 650}),
		newPlayer("Border", {level = 200})
	eq(blessCost(L1), 60, "level 80: 60") eq(blessCost(L4), 60, "level 200: 60") eq(blessCost(L2), 100, "level 350: 100") eq(blessCost(L3), 150, "level 650: 150")
	DB.coins[L3.account] = 1000
	local c, page, o, e = find(L3, "service:blessings")
	request(L3, "get_page", {category = c, page = page})
	local view = last("category_page").data.offers[o]
	eq(view.cost, 150, "the client is sent 150 for a level 650 character")
	request(L3, "buy", {category = c, page = page, offer = o, title = view.title, cost = 60})
	eq(last("message").data.title, "Error", "a price from another level tier is refused")
	eq(DB.coins[L3.account], 1000, "no coins taken")
	local title = buy(L3, "service:blessings")
	eq(title, "Purchase complete", "bought") eq(DB.coins[L3.account], 850, "150 coins taken")
	eq(DB.purchases[#DB.purchases].price, 150, "logged at the level price")
	-- the character levels up past a border while the window is open: the old price is refused
	DB.coins[L4.account] = 1000
	local cat4, page4, off4, ent4 = find(L4, "service:blessings")
	L4.level = 201
	request(L4, "buy", {category = cat4, page = page4, offer = off4, title = "All Blessings", cost = ent4.cost})
	eq(last("message").data.title, "Error", "60 is refused once the character is level 201")
	eq(blessCost(L4), 100, "and the store shows 100 now")
end

-- the account discount: another character of the account owns it (or a starter pack with it)
do
	local function costOf(p, key) local _, _, _, e = find(p, key); return e.cost, e end
	local C1 = newPlayer("Cinder One", {level = 60})
	local C2 = newPlayer("Cinder Two", {level = 60, account = C1.account})
	local C3 = newPlayer("Cinder Three", {level = 60, account = C1.account})
	local Other = newPlayer("Other Account", {level = 60})
	for _, p in ipairs({C1, C2, C3, Other}) do DB.coins[p.account] = 5000 end
	eq(costOf(C2, "service:pouch:loot"), 250, "nobody owns it: the list price")
	eq(buy(C1, "service:pouch:loot"), "Purchase complete", "the first character pays 250")
	eq(DB.coins[C1.account], 4750, "250 taken")
	local cost, e = costOf(C2, "service:pouch:loot")
	eq(cost, 125, "another character of the account: half") eq(e.oldCost, 250, "the list price is struck through")
	eq(e.tags[1], "Account -50%", "tagged")
	ok(e.offer.description:find("Another character of your account has it: 50% off.", 1, true), "the description says why")
	eq(costOf(C1, "service:pouch:orbs"), 200, "an offer nobody owns: full price")
	eq(costOf(Other, "service:pouch:loot"), 250, "another account: full price")
	c, page, o = find(C2, "service:pouch:loot")
	request(C2, "get_page", {category = c, page = page})
	local view = last("category_page").data.offers[o]
	eq(view.cost, 125, "the client is sent 125") eq(view.oldCost, 250, "and the old price") eq(view.gift, nil, "not giftable")
	request(C2, "buy", {category = c, page = page, offer = o, title = view.title, cost = 250})
	eq(last("message").data.title, "Error", "the list price is refused for a discounted offer (the store changed)")
	eq(buy(C2, "service:pouch:loot"), "Purchase complete", "the second character pays 125")
	eq(DB.coins[C2.account], 4750 - 125, "125 taken")
	eq(DB.purchases[#DB.purchases].price, 125, "logged at 125") eq(DB.purchases[#DB.purchases].list, 250, "list price kept in the log")
	eq(costOf(C3, "service:pouch:loot"), 125, "a third character: half too")
	-- every per-character convenience of the store carries the discount: the pouches, the ration, the unlocks, ten Everfull tiers
	local n = 0
	for key, offer in pairs(Shop.byKey) do
		if offer.accountDiscount then
			n = n + 1
			eq(offer.accountDiscount, 50, key .. ": 50%")
			ok(offer.kind == "service" or offer.kind == "unlock", key .. ": a per-character kind")
		end
	end
	eq(n, 17, "17 offers: 4 pouches, the ration, Auto Seller, Rarity Autoloot, 10 Everfull tiers")
	for _, key in ipairs({"service:pouch:loot", "service:pouch:orbs", "service:pouch:keys", "service:pouch:gems", "service:storeFood",
			"unlock:autoSeller", "unlock:rarityAutoloot", "service:everfullUpgrade:32268", "service:everfullUpgrade:32270"}) do
		ok(Shop.byKey[key] and Shop.byKey[key].accountDiscount == 50, key .. " has the discount")
	end
	-- the discount follows an Everfull tier: 70 coins -> 35
	eq(costOf(C3, "service:everfullUpgrade:32270"), 70, "an Everfull tier nobody owns: 70")
	-- a character that no longer exists owns nothing
	local D1 = newPlayer("Doomed", {level = 60})
	local D2 = newPlayer("Survivor", {level = 60, account = D1.account})
	DB.coins[D1.account] = 5000
	eq(buy(D1, "unlock:autoSeller"), "Purchase complete", "Auto Seller on the first character")
	eq(costOf(D2, "unlock:autoSeller"), 200, "half for the second")
	players[D1.guid] = nil
	eq(costOf(D2, "unlock:autoSeller"), 400, "the owner was deleted: full price")
	-- a starter pack with the Loot Bag counts as owning it
	local S1 = newPlayer("Starter One", {level = 30})
	local S2 = newPlayer("Starter Two", {level = 30, account = S1.account})
	DB.coins[S1.account] = 5000
	eq(costOf(S2, "service:pouch:loot"), 250, "before the pack: full price")
	eq(buy(S1, "starter:adventurer"), "Purchase complete", "the Adventurer Pack (Loot Bag inside)")
	eq(costOf(S2, "service:pouch:loot"), 125, "the pack's Loot Bag counts: half for the other character")
	-- a sale that beats the account discount keeps its own tag; a bigger account discount replaces a smaller sale
	local sale = ChaosShopConfig.storefront.sales
	sale[#sale + 1] = {offers = {"service:pouch:keys"}, pct = 60, tag = "Test sale"}
	DB.coins[Other.account] = 5000
	local O2 = newPlayer("Other Two", {level = 60, account = Other.account})
	eq(buy(Other, "service:pouch:keys"), "Purchase complete", "keys pouch (sale 60%: 60 coins)")
	cost, e = costOf(O2, "service:pouch:keys")
	eq(cost, 60, "the 60% sale beats the 50% account discount") eq(e.tags[1], "Test sale -60%", "the sale's tag stays")
	sale[#sale] = nil
	cost, e = costOf(O2, "service:pouch:keys")
	eq(cost, 75, "no sale: 150 / 2") eq(e.tags[1], "Account -50%", "the account tag")
	sale[#sale + 1] = {offers = {"service:pouch:keys"}, pct = 20, tag = "Small sale"}
	cost, e = costOf(O2, "service:pouch:keys")
	eq(cost, 75, "a 20% sale loses to the account discount") eq(e.tags[1], "Account -50%", "the account tag replaced the sale tag") eq(e.oldCost, 150, "struck-through list price")
	sale[#sale] = nil
end

-- Lasting Exercise weapons: 2 a week in all, one shared limit (the Double Experience Potion mechanism)
do
	local W = newPlayer("Weaponsmith", {level = 400})
	DB.coins[W.account] = 10000
	eq(buy(W, "item:27775x1"), "Purchase complete", "the first Lasting weapon")
	eq(buy(W, "item:27779x1"), "Purchase complete", "a second, of another kind")
	local title, msg = buy(W, "item:27781x1")
	eq(title, "Not possible", "the third in a week is refused, whichever kind") ok(msg:find("Lasting Exercise Weapons", 1, true) and msg:find("this week", 1, true), msg)
	title = buy(W, "item:27775x1")
	eq(title, "Not possible", "also the same kind again")
	eq(DB.coins[W.account], 10000 - 900, "only two were paid")
	local W2 = newPlayer("Second Account", {level = 400})
	DB.coins[W2.account] = 1000
	eq(buy(W2, "item:27776x1"), "Purchase complete", "another account has its own two")
	-- a gift to an offline character counts against the giver's week (the limit is the buyer's)
	for _, key in ipairs({"item:27775x1", "item:27776x1", "item:27778x1", "item:27779x1", "item:27780x1", "item:27781x1"}) do
		local o = Shop.byKey[key]
		eq(o.weeklyLimit, 2, key .. ": 2 a week") eq(o.weeklyGroup, "lastingExercise", key .. ": one group")
		eq(#Shop.weekGroups.lastingExercise, 6, "six offers in the group")
	end
	local smaller = Shop.byKey["item:27768x1"]
	eq(smaller.weeklyLimit, nil, "the 1800 charge weapons have no weekly limit")
end

-- ------------------------------------------------------------------ Founder Pack (O322): a window, one per account and tier, the grant
do
	local FC = dofile("data/scripts/chaos/founder_config.lua")
	local T0, T1 = K.parseTime(FC.start), K.parseTime(FC["end"])
	eq(FC.start, "2026-11-20 15:00", "the launch: 20/11/2026 15:00") eq(FC["end"], "2026-12-18 15:00", "four weeks later")
	eq(T1 - T0, 28 * 86400, "the sale lasts four weeks")
	-- core: the window
	local offer = {availableFrom = FC.start, availableUntil = FC["end"]}
	eq(K.windowState(offer, T0 - 1), "early", "one second before the start") eq(K.windowState(offer, T0), nil, "at the start")
	eq(K.windowState(offer, T1 - 1), nil, "one second before the end") eq(K.windowState(offer, T1), "late", "at the end")
	eq(K.windowState({}, T1 + 99999), nil, "an offer without a window is always on")
	eq(K.windowState({availableUntil = FC["end"]}, T0 - 99999), nil, "no start: on until the end")
	eq(K.windowNote(offer, "en"), "Available until 2026-12-18 15:00.", "the end date, English")
	eq(K.windowNote(offer, "pt-BR"), "Disponível até 18/12/2026 15:00.", "the end date, pt-BR")
	eq(K.windowNote({}, "en"), nil, "no note without an end")
	local bad = table.concat(K.validate({categories = {{name = "X", offers = {{kind = "premium", days = 1, cost = 1,
		availableFrom = "2026-12-18 15:00", availableUntil = "2026-11-20 15:00"}}}}}), ";")
	ok(bad:find("not after availableFrom", 1, true), "an end before the start is a problem")

	-- the exclusives of the pack: a mocked ChaosExclusives (exclusives.lua) records the grants
	local granted = {}
	ChaosExclusives = {owns = function(acc, key) return (granted[acc] or {})[key] == true end,
		grant = function(acc, key, source, player)
			granted[acc] = granted[acc] or {}
			if granted[acc][key] then return false, "owned" end
			ok(source == "founder", "the grant names the Founder Pack as its source")
			granted[acc][key] = true
			return true
		end}
	local F1, F2 = Shop.byKey["founder:pack"], Shop.byKey["founder:grand"]
	ok(F1 and F2, "both tiers are store offers")
	eq(F1.cost, 499, "the first pack: about R$ 50") eq(F2.cost, 999, "the grand pack: about R$ 100")
	eq(F1.availableFrom, FC.start, "the offer carries the window") eq(F1.gift, false, "not giftable") eq(F1.oncePerAccount, true, "once")
	for _, o in ipairs({F1, F2}) do
		for _, part in ipairs(o.resolved) do
			ok(part.kind == "exclusive" or part.kind == "pact", "cosmetics and Pact days only")
			if part.kind == "exclusive" then ok(part.name, "a piece has the exclusive's name") end
		end
	end

	local P = newPlayer("Founder", {level = 400})
	DB.coins[P.account] = 3000
	local before = pactDays
	-- before the start: not in the view, not sold
	clock = T0 - 1
	ok(not find(P, "founder:pack") and not find(P, "founder:grand"), "hidden before the start")
	for _, cat in ipairs(Shop.view(P)) do ok(cat.name ~= "Founder Pack", "no Founder Pack category before the start") end
	-- at the start: shown with the end date first in its text, the price echoed
	clock = T0
	local c, page, i, e = find(P, "founder:pack")
	ok(c, "shown at the start") eq(e.cost, 499, "price 499")
	request(P, "get_page", {category = c, page = page})
	local view = last("category_page").data.offers[i]
	eq(view.description:find("Available until 2026-12-18 15:00.", 1, true), 1, "the end date leads the text")
	ok(view.description:find("14 days of Chaos Pact", 1, true), "the Pact days are told")
	ok(Chaos.setLang, "the language switch is there")
	do
		Chaos.setLang(P, "pt-BR")
		request(P, "get_page", {category = c, page = page})
		local pt = last("category_page").data.offers[i].description
		eq(pt:find("Disponível até 18/12/2026 15:00.", 1, true), 1, "pt-BR: disponível até")
		ok(pt:find("Uma vez por conta, nunca mais vendido", 1, true), "pt-BR text: " .. pt)
		Chaos.setLang(P, "en")
	end
	-- buying the first pack: coins, both pieces for the account, 14 Pact days, logged
	eq(buy(P, "founder:pack"), "Purchase complete", "the first pack")
	eq(DB.coins[P.account], 3000 - 499, "499 coins")
	ok(granted[P.account].wings_gold_peacock and granted[P.account].head_royal_coronet, "both pieces for the account")
	eq(granted[P.account].wings_pyre_seraph, nil, "not the grand pack's pieces")
	eq(pactDays - before, 14, "14 days of the Chaos Pact")
	-- one per account and tier: gone for the whole account, also for another character
	ok(not find(P, "founder:pack"), "hidden once bought")
	local P2 = newPlayer("Founder Alt", {level = 30, account = P.account})
	ok(not find(P2, "founder:pack"), "hidden for the other characters of the account")
	ok(find(P2, "founder:grand"), "the grand pack is its own tier")
	-- the grand pack: a separate purchase
	eq(buy(P, "founder:grand"), "Purchase complete", "the grand pack")
	eq(DB.coins[P.account], 3000 - 499 - 999, "999 coins")
	for _, key in ipairs(F2.parts and {"wings_pyre_seraph", "cape_phoenix_plume_cape", "head_double_halo", "frame_founder"}) do
		ok(granted[P.account][key], "grand pack piece " .. key)
	end
	eq(pactDays - before, 14 + 30, "30 more Pact days")
	ok(not find(P, "founder:grand"), "hidden once bought")

	-- another account: sold up to the last second, then never
	local Q = newPlayer("Late Founder", {level = 120})
	DB.coins[Q.account] = 2000
	clock = T1 - 1
	ok(find(Q, "founder:pack"), "still sold one second before the end")
	local qc, qp, qo = find(Q, "founder:pack")
	request(Q, "get_page", {category = qc, page = qp})
	local qv = last("category_page").data.offers[qo]
	clock = T1
	ok(not find(Q, "founder:pack") and not find(Q, "founder:grand"), "gone at the end")
	request(Q, "buy", {category = qc, page = qp, offer = qo, title = qv.title, cost = qv.cost})
	eq(last("message").data.title, "Error", "a stale window cannot buy it after the end")
	eq(DB.coins[Q.account], 2000, "no coins taken")
	eq((granted[Q.account] or {}).wings_gold_peacock, nil, "nothing granted")
	clock = T1 + 365 * 86400
	ok(not find(Q, "founder:pack"), "never again")

	-- no Pact system: the pack is not sold (the Pact days are part of what is paid for)
	clock = T0 + 86400
	local R = newPlayer("No Pact", {level = 50})
	DB.coins[R.account] = 2000
	local savedPact = ChaosPact
	ChaosPact = nil
	local t2, m2 = buy(R, "founder:pack")
	eq(t2, "Not possible", "no Pact system, no sale") eq(DB.coins[R.account], 2000, "nothing taken")
	ChaosPact = savedPact
	-- a piece the account has (a staff grant): the pack is refused, nothing taken
	granted[R.account] = {wings_gold_peacock = true}
	local t3 = buy(R, "founder:pack")
	eq(t3, "Not possible", "an owned piece") eq(DB.coins[R.account], 2000, "no coins taken")
	-- a gift is refused: the packs are for one's own account
	local G = newPlayer("Gifter", {level = 50})
	DB.coins[G.account] = 2000
	local t4 = buy(G, "founder:pack", "Founder Alt")
	ok(t4 ~= "Purchase complete", "no gifts of the Founder Pack")
	eq(DB.coins[G.account], 2000, "no coins taken for a gift")
	clock = realTime({year = 2026, month = 10, day = 29, hour = 15, min = 0, sec = 0})
end

print("shop_test: ok")

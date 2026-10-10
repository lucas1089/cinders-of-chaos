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
local EX = K.exclusions({classLooks = ChaosClassLooks.looks, classOutfits = Chaos.classes.outfits,
	achievements = achievements, season = season, seasonpass = seasonpass, looks = retiredLooks})
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
		if o.oncePerAccount then
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
local coins = dofile("data/scripts/chaos/shop_coins_config.lua")
local packs = {}
for _, p in ipairs(coins.packs) do packs[p.key] = p end
eq(K.packCredit(packs.coins250, false, coins).total, 250, "250")
eq(K.packCredit(packs.coins750, false, coins).total, 825, "750 +10%")
eq(K.packCredit(packs.coins1500, false, coins).total, 1725, "1500 +15%")
eq(K.packCredit(packs.coins4000, false, coins).total, 5000, "4000 +25%")
eq(K.packCredit(packs.coins750, true, coins).total, 975, "first purchase +20%")
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
function ItemType(id) return {getClientId = function() return id end, getName = function() return "item " .. id end} end
json = {encode = function(t) sent[#sent + 1] = t; return "" end, decode = function(b) return b end}

local DB = {coins = {}, purchases = {}, gifts = {}, orders = {}, queries = {}}
local players = {}
Game = {getPlayers = function() local l = {} for _, p in pairs(players) do l[#l + 1] = p end return l end}
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
			if (DB.coins[acc] or 0) < amount then return false end
			DB.coins[acc] = DB.coins[acc] - amount; return true
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
	if q:find("SELECT `coins` FROM `chaos_shop_coins`", 1, true) then
		return DB.coins[acc] and {{coins = DB.coins[acc]}} or {}
	elseif q:find("SELECT COUNT(*) AS `n` FROM `chaos_shop_purchases`", 1, true) then
		local key, since = q:match("`offer_key` = '([^']*)'"), tonumber(q:match("`created` >= (%d+)")) or 0
		local count = 0
		for _, r in ipairs(DB.purchases) do
			if r.account == acc and (not key or r.key == key) and r.created >= since and (not q:find("`gift_player` > 0", 1, true) or r.giftPlayer > 0) then
				count = count + 1
			end
		end
		return {{n = count}}
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
ChaosSeason = {realmOf = function(p) return p.realm or 0 end}
ChaosRateLimit = {allow = function() return true end}
local pactDays = 0
ChaosPact = {grantDays = function(p, days, source) pactDays = pactDays + days; eq(source, "store", "pact source") end}

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
-- the view: Starter first for a young character, then Featured
local v = Shop.view(A)
eq(v[1].name, "Starter", "starter packs first"); eq(v[2].name, "Featured", "then featured")
eq(#v[2].offers, cfg.storefront.featured.count, "featured count")

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
eq(buy(A, "frame:frost"), "Purchase complete", "frame")
eq(Shop.frameOf(A), "frost", "frame shown")
Shop.plateFrame(A, "off"); eq(Shop.frameOf(A), nil, "title frame")
Shop.plateFrame(A, "violet"); eq(Shop.frameOf(A), nil, "a frame not owned cannot be picked")
Shop.plateFrame(A, "frost"); eq(Shop.frameOf(A), "frost", "back to frost")
-- addons of an outfit everyone has
eq(buy(A, "addons:128"), "Purchase complete", "addons"); eq(A.outfits[136], 3, "female citizen addons")

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
eq(buy(B, "bundle:frostborn"), "Not possible", "bundle with owned parts refused")

-- starter packs: once per account, level gate, hidden afterwards, pact days when the Pact exists
eq(buy(A, "starter:novice"), "Purchase complete", "novice pack")
ok(A.auras[17] and A.items[8472] == 100 and A.items[27990] == 5, "novice parts"); eq(pactDays, 3, "pact days")
ok(not find(A, "starter:novice"), "hidden once bought")
local A2 = newPlayer("Alicealt", {account = A.account, level = 10})
ok(not find(A2, "starter:novice"), "hidden for the whole account")
local Old = newPlayer("Veteran", {level = 400})
ok(not find(Old, "starter:champion"), "level gate hides it")
eq(Shop.view(Old)[1].name, "Featured", "featured first without starter packs")
-- a failing item part takes nothing and refunds
local Full = newPlayer("Fullbag", {level = 30})
Full.full = true
DB.coins[Full.account] = 1000
eq(buy(Full, "starter:adventurer"), "Error", "no room")
eq(DB.coins[Full.account], 1000, "refunded"); ok(not Full.mounts[23], "nothing given")

-- gifts: online, offline (delivered at login), refused targets
local Cara = newPlayer("Cara", {})
eq(buy(A, "aura:7", "Cara"), "Gift sent", "online gift"); ok(Cara.auras[7], "delivered at once")
eq(DB.purchases[#DB.purchases].giftPlayer, Cara.guid, "gift logged")
eq(buy(A, "aura:7", "Cara"), "Not possible", "target owns it")
eq(buy(A, "service:stamina", "Cara"), "Not possible", "services cannot be gifted")
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

-- coin orders: pack bonus, first purchase bonus once, starter once, unknown pack rejected
DB.orders = {{account = 77, pack = "coins750", status = "paid"}, {account = 77, pack = "coins750", status = "paid"},
	{account = 77, pack = "starter", status = "paid"}, {account = 77, pack = "starter", status = "paid"}, {account = 77, pack = "nope", status = "paid"}}
Shop.processOrders()
eq(DB.orders[1].total, 975, "first pack with the first purchase bonus"); eq(DB.orders[2].total, 825, "second pack without")
eq(DB.orders[3].total, 500, "starter"); eq(DB.orders[4].status, "rejected", "second starter rejected")
eq(DB.orders[5].status, "rejected", "unknown pack"); eq(DB.coins[77], 975 + 825 + 500, "coins credited")
Shop.processOrders()
eq(DB.coins[77], 2300, "credited once")

-- a reload builds the same store and keeps what was bought
local keysBefore = #Shop.view(A)
loadShop()
ext = registry.ChaosShopExtended
eq(#ChaosShop.view(A), keysBefore, "same categories after a reload")
eq(buy(A, "outfit:1237"), "Not possible", "still owned after a reload")

print("shop_test: ok")

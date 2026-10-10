-- Chaos store (client module game_shop, extended opcode ChaosOpcodes.shop, JSON).
--
-- client -> server {"action": ..., "data": {...}}
--   init                                          -> "categories" (+ status)
--   get_page {category, page}                     -> "category_page" {category, page, offers}
--   buy {category, page, offer, title, cost, gift?} -> "message" (+ status); gift = a character name: bought for it
--   history                                       -> "history" [offers with a description line]
--   gift_coins {name, amount}                     -> "message" (+ status)
-- server -> client {"action": ..., "data": ..., "status": {points, ad, buyUrl}}
--   an offer: {type, item|outfit, title, description, cost, oldCost?, tags?, gift?, owned?}
--
-- Categories are built per player (ChaosShop.view): the Starter packs first while one is for sale to the player, then
-- this week's Featured offers, then shop_config.lua's categories; empty categories are left out. Prices are worked out
-- here (sales, featured discount: ChaosShopCore.price) and the client echoes title and cost, so a price that changed
-- meanwhile is refused, never charged.
--
-- Coins live per account in chaos_shop_coins; every purchase goes to chaos_shop_purchases (account, character, level,
-- offer key, price, list price, gift target) and, for the client's history, chaos_shop_history. Gifts to offline
-- characters wait in chaos_shop_gifts. Paid Chaos Coin orders (chaos_coin_orders, written by the website) are credited
-- here (shop_coins_config.lua). Staff add coins with /coins <player>, <amount>. Offers: shop_config.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/shop_core.lua")

ChaosShopConfig = dofile("data/scripts/chaos/shop_config.lua")
ChaosShopCoinsConfig = dofile("data/scripts/chaos/shop_coins_config.lua")
local cfg, coinsCfg = ChaosShopConfig, ChaosShopCoinsConfig
local K = ChaosShopCore
local OPCODE = ChaosOpcodes.shop
local TB = Chaos.tables
local T_COINS, T_HISTORY = TB.shopCoins, TB.shopHistory
local T_PURCHASES, T_GIFTS, T_ORDERS = TB.shopPurchases, TB.shopGifts, TB.coinOrders
local S = Chaos.storage
local SF = cfg.storefront or {}

ChaosShop = ChaosShop or {}
local Shop = ChaosShop

local function log(text)
	print("[Chaos store] " .. text)
end

-- ------------------------------------------------------------------ tables (also in server/sql/chaos.sql)
db.query([[CREATE TABLE IF NOT EXISTS `chaos_shop_purchases` (
  `id` int(11) NOT NULL AUTO_INCREMENT, `account_id` int(11) NOT NULL, `player_id` int(11) NOT NULL,
  `player_name` varchar(255) NOT NULL DEFAULT '', `level` int(11) NOT NULL DEFAULT 0, `offer_key` varchar(64) NOT NULL,
  `category` varchar(64) NOT NULL DEFAULT '', `title` varchar(100) NOT NULL, `price` int(11) NOT NULL,
  `list_price` int(11) NOT NULL, `gift_account` int(11) NOT NULL DEFAULT 0, `gift_player` int(11) NOT NULL DEFAULT 0,
  `created` int(10) unsigned NOT NULL, PRIMARY KEY (`id`), KEY `chaos_shop_purchases_account` (`account_id`, `offer_key`),
  KEY `chaos_shop_purchases_created` (`created`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]])
db.query([[CREATE TABLE IF NOT EXISTS `chaos_shop_gifts` (
  `id` int(11) NOT NULL AUTO_INCREMENT, `target_player` int(11) NOT NULL, `offer_key` varchar(64) NOT NULL,
  `title` varchar(100) NOT NULL, `price` int(11) NOT NULL, `from_account` int(11) NOT NULL,
  `from_name` varchar(255) NOT NULL DEFAULT '', `status` tinyint(4) NOT NULL DEFAULT 0, `created` int(10) unsigned NOT NULL,
  `done` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_shop_gifts_target` (`target_player`, `status`))
  ENGINE=InnoDB DEFAULT CHARSET=utf8]])
db.query([[CREATE TABLE IF NOT EXISTS `chaos_coin_orders` (
  `id` int(11) NOT NULL AUTO_INCREMENT, `account_id` int(11) NOT NULL, `pack_key` varchar(32) NOT NULL,
  `provider` varchar(32) NOT NULL DEFAULT '', `provider_ref` varchar(128) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'paid', `coins` int(11) NOT NULL DEFAULT 0, `bonus` int(11) NOT NULL DEFAULT 0,
  `first_bonus` int(11) NOT NULL DEFAULT 0, `note` varchar(255) NOT NULL DEFAULT '', `created` int(10) unsigned NOT NULL,
  `credited` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), UNIQUE KEY `chaos_coin_orders_ref` (`provider`, `provider_ref`),
  KEY `chaos_coin_orders_status` (`status`), KEY `chaos_coin_orders_account` (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]])

-- ------------------------------------------------------------------ cosmetics names from the XML files
local function readXml(file, tag)
	local list = {}
	local f = io.open(file, "r")
	if not f then
		return list
	end
	for line in f:lines() do
		local id = line:match("<" .. tag .. "[^>]-%sid=\"(%d+)\"") -- the space keeps clientid out
		if id then
			list[tonumber(id)] = {
				name = line:match("name=\"([^\"]*)\""),
				clientid = tonumber(line:match("clientid=\"(%d+)\"") or "")
			}
		end
	end
	f:close()
	return list
end

local WINGS = readXml("data/XML/wings.xml", "wing")
local AURAS = readXml("data/XML/auras.xml", "aura")
local SHADERS = readXml("data/XML/shaders.xml", "shader")
local FRAMES = {"violet", "frost"} -- index = storage offset (Chaos.storage.shopFrameBase + i)
local FRAME_INDEX = {violet = 1, frost = 2}

-- ------------------------------------------------------------------ exclusives (checked again at every load)
local function exclusions()
	if not ChaosClassLooks or not ChaosClassLooks.looks then
		pcall(dofile, "data/scripts/chaos/class_looks_core.lua")
	end
	local src = {classLooks = ChaosClassLooks and ChaosClassLooks.looks, classOutfits = Chaos.classes and Chaos.classes.outfits,
		looks = {}}
	-- the looks classes wore before: characters own them already
	for _, e in ipairs(ChaosClassLooks and ChaosClassLooks.retired or {}) do
		src.looks[#src.looks + 1] = e.male
		src.looks[#src.looks + 1] = e.female
	end
	local ok, data = pcall(dofile, "data/scripts/chaos/achievements_data.lua")
	src.achievements = ok and data or nil
	ok, data = pcall(dofile, "data/scripts/chaos/season_config.lua")
	src.season = ok and data or nil
	ok, data = pcall(dofile, "data/scripts/chaos/seasonpass_config.lua")
	src.seasonpass = ok and data or nil
	return K.exclusions(src)
end
Shop.exclusions = exclusions()

-- ------------------------------------------------------------------ catalog (static part)
local byKey, CATS = {}, {}
for _, category in ipairs(cfg.categories) do
	local cat = {name = category.name, icon = category.icon, starter = category.starter, offers = {}}
	for _, offer in ipairs(category.offers) do
		offer.key = K.offerKey(offer)
		local why = K.excluded(offer, Shop.exclusions)
		if why then
			log("not sold: " .. offer.key .. " (" .. why .. ")")
		else
			offer.category = category.name
			byKey[offer.key] = byKey[offer.key] or offer
			cat.offers[#cat.offers + 1] = offer
		end
	end
	CATS[#CATS + 1] = cat
end
-- bundles: their parts and price
for _, cat in ipairs(CATS) do
	for _, offer in ipairs(cat.offers) do
		if offer.kind == "bundle" then
			local parts, sum = {}, 0
			for _, p in ipairs(offer.parts or {}) do
				local part = type(p) == "string" and byKey[p] or (type(p) == "table" and p or nil)
				if part then
					part.key = K.offerKey(part)
					parts[#parts + 1] = part
					sum = sum + (part.cost or 0)
				else
					log("bundle " .. offer.key .. ": part " .. tostring(p) .. " is not sold")
				end
			end
			offer.resolved, offer.listSum = parts, sum
			offer.cost = K.bundleCost(offer, sum)
		end
	end
end
for _, problem in ipairs(K.validate(cfg, Shop.exclusions)) do
	log("shop_config.lua: " .. problem)
end
Shop.byKey = byKey

-- ------------------------------------------------------------------ helpers
local function now()
	return os.time()
end

local function pactGrant()
	local api = cfg.pact and _G[cfg.pact.api]
	local fn = api and api[cfg.pact.fn]
	return type(fn) == "function" and fn or nil
end

local function isSeason(player)
	return ChaosSeason and ChaosSeason.realmOf and (ChaosSeason.realmOf(player) or 0) > 0 or false
end

local function storageKey(offer)
	if offer.kind == "wings" then
		return S.shopWingsBase + offer.id
	elseif offer.kind == "aura" then
		return S.shopAuraBase + offer.id
	elseif offer.kind == "shader" then
		return S.shopShaderBase + offer.id
	elseif offer.kind == "frame" and FRAME_INDEX[offer.frame] then
		return S.shopFrameBase + FRAME_INDEX[offer.frame]
	end
	return nil
end

local function sexLook(player, offer)
	if player:getSex() == PLAYERSEX_FEMALE then
		return offer.lookfemale or offer.looktype
	end
	return offer.looktype
end

-- does the player own this cosmetic already
function Shop.owns(player, offer)
	local key = storageKey(offer)
	if key then
		return player:getStorageValue(key) > 0
	elseif offer.kind == "outfit" or offer.kind == "addons" then
		return player:hasOutfit(sexLook(player, offer), 3)
	elseif offer.kind == "mount" then
		return player:hasMount(offer.id)
	end
	return false
end

local function weekStart(t)
	local hour = SF.weekHour or 6
	return os.time({year = 1970, month = 1, day = 5, hour = hour, min = 0, sec = 0}) + K.weekKey(t, hour) * 604800
end

local function boughtCount(accountId, key, since)
	local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM `" .. T_PURCHASES .. "` WHERE `account_id` = " .. accountId ..
		" AND `offer_key` = " .. db.escapeString(key) .. " AND `created` >= " .. (since or 0), {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

-- keys of the oncePerAccount offers the account bought
local ONCE = {}
for key, offer in pairs(byKey) do
	if offer.oncePerAccount then
		ONCE[#ONCE + 1] = db.escapeString(key)
	end
end
local function onceBought(accountId)
	local set = {}
	if #ONCE == 0 then
		return set
	end
	local rows = Chaos.select("SELECT DISTINCT `offer_key` FROM `" .. T_PURCHASES .. "` WHERE `account_id` = " .. accountId ..
		" AND `offer_key` IN (" .. table.concat(ONCE, ",") .. ")", {{"offer_key", "s"}})
	for _, r in ipairs(rows) do
		set[r.offer_key] = true
	end
	return set
end

-- ------------------------------------------------------------------ prices and the per-player view
function Shop.context(t)
	t = t or now()
	local f = SF.featured or {}
	local keys = {}
	for _, k in ipairs(K.featured(f.pool or {}, K.weekKey(t, SF.weekHour or 6), #(f.pool or {}))) do
		if byKey[k] and #keys < (f.count or 0) then
			keys[#keys + 1] = k
		end
	end
	local featured = {}
	for _, k in ipairs(keys) do
		featured[k] = f.pct or 0
	end
	return {now = t, sales = SF.sales, new = SF.new, featured = featured, featuredKeys = keys}
end

local function entry(offer, ctx)
	local cost, oldCost, tags = K.price(offer, offer.category, ctx)
	if offer.kind == "bundle" and offer.listSum and offer.listSum > cost then
		oldCost = offer.listSum
		table.insert(tags, 1, (offer.oncePerAccount and "Starter" or "Bundle") .. " -" ..
			math.floor((offer.listSum - cost) * 100 / offer.listSum + 0.5) .. "%")
	end
	return {offer = offer, cost = cost, oldCost = oldCost, tags = tags}
end

-- the categories this player sees now: {{name, icon, offers = {entry, ...}}}
function Shop.view(player, t)
	local ctx = Shop.context(t)
	local bought = onceBought(player:getAccountId())
	local level = player:getLevel()
	local function visible(o)
		return not (o.oncePerAccount and bought[o.key]) and not (o.maxLevel and level > o.maxLevel)
	end
	local list = {}
	local function add(cat, offers)
		if #offers > 0 then
			list[#list + 1] = {name = cat.name, icon = cat.icon, offers = offers}
		end
	end
	for _, cat in ipairs(CATS) do
		local offers = {}
		for _, o in ipairs(cat.offers) do
			if visible(o) then
				offers[#offers + 1] = entry(o, ctx)
			end
		end
		add(cat, offers)
	end
	local featured = {}
	for _, k in ipairs(ctx.featuredKeys) do
		local o = byKey[k]
		if visible(o) then
			local e = entry(o, ctx)
			featured[#featured + 1] = e
		end
	end
	if #featured > 0 then
		-- right after the Starter packs, or first when none is for sale to this player
		local at = (list[1] and CATS[1].starter and list[1].name == CATS[1].name) and 2 or 1
		table.insert(list, at, {name = "Featured", icon = Shop.iconOf(featured[1].offer), offers = featured})
	end
	return list
end

-- a category icon from an offer
function Shop.iconOf(offer)
	if offer.kind == "mount" then
		return {outfit = {type = offer.clientid, rotating = true}}
	elseif offer.kind == "outfit" then
		return {outfit = {type = offer.looktype, head = 2, body = 116, legs = 114, feet = 114, addons = 3, rotating = true}}
	end
	return {item = 2160}
end

-- ------------------------------------------------------------------ offers as the client shows them
local PREVIEW = {type = 128, head = 114, body = 94, legs = 94, feet = 114, addons = 3, rotating = true}

local function previewWith(field, value)
	local o = {}
	for k, v in pairs(PREVIEW) do
		o[k] = v
	end
	o[field] = value
	return o
end

local function giftable(offer)
	if offer.gift == false or not K.GIFTABLE[offer.kind] then
		return false
	end
	for _, p in ipairs(offer.resolved or {}) do
		if not K.GIFTABLE[p.kind] or p.kind == "pact" then
			return false
		end
	end
	return true
end

local function clientOffer(e, player)
	local offer = e.offer
	local view = {cost = e.cost, oldCost = e.oldCost, title = offer.name, description = offer.description or ""}
	if e.tags and #e.tags > 0 then
		view.tags = e.tags
	end
	if offer.kind == "item" then
		local it = ItemType(offer.id)
		view.type, view.item, view.count = "item", it:getClientId(), offer.count or 1
		view.title = view.title or it:getName()
	elseif offer.kind == "wings" then
		local w = WINGS[offer.id] or {}
		view.type, view.outfit = "outfit", previewWith("wings", w.clientid or 0)
		view.title = view.title or w.name or ("Wings " .. offer.id)
		view.description = offer.description or "Wings for every outfit, yours for good."
	elseif offer.kind == "aura" then
		local a = AURAS[offer.id] or {}
		view.type, view.outfit = "outfit", previewWith("aura", a.clientid or 0)
		view.title = view.title or a.name or ("Aura " .. offer.id)
		view.description = offer.description or "An aura around your character, yours for good."
	elseif offer.kind == "shader" then
		local s = SHADERS[offer.id] or {}
		view.type, view.outfit = "outfit", previewWith("shader", s.name or "")
	elseif offer.kind == "outfit" or offer.kind == "addons" then
		-- the look of the viewer's sex
		local look = player and sexLook(player, offer) or offer.looktype
		view.type = "outfit"
		view.outfit = {type = look, head = 2, body = 116, legs = 114, feet = 114, addons = 3, rotating = true}
		if offer.kind == "addons" then
			view.title = view.title .. " Addons"
		end
	elseif offer.kind == "mount" then
		view.type, view.outfit = "outfit", {type = offer.clientid, rotating = true}
	elseif offer.kind == "premium" then
		view.type, view.item, view.count = "item", ItemType(16101):getClientId(), 1
	elseif offer.kind == "unlock" and offer.look then
		-- a pet (pets.lua): its outfit
		view.type, view.outfit = "outfit", {type = offer.look, rotating = true}
	else
		-- services, unlocks, frames, bundles: the icon is any item picture
		view.type, view.item, view.count = "item", ItemType(offer.icon or 1949):getClientId(), offer.iconCount or 1
	end
	if offer.kind == "bundle" and pactGrant() then
		for _, p in ipairs(offer.resolved or {}) do
			if p.kind == "pact" then
				view.description = view.description .. " +" .. p.days .. " days of Chaos Pact."
			end
		end
	end
	view.title = view.title or "Offer"
	view.gift = giftable(offer) or nil
	if player and Shop.owns(player, offer) then
		view.owned = true
		view.description = "Owned. " .. view.description
	end
	return view
end

local function categoriesView(player, list)
	local out = {}
	for c, category in ipairs(list or Shop.view(player)) do
		local entry = {name = category.name, pages = math.max(1, math.ceil(#category.offers / cfg.perPage))}
		if category.icon.item then
			entry.type, entry.item, entry.count = "item", ItemType(category.icon.item):getClientId(), category.icon.count or 1
		else
			entry.type, entry.outfit = "outfit", category.icon.outfit
		end
		out[c] = entry
	end
	return out
end

local function pageOf(list, c, p)
	local cat = list[c]
	if not cat then
		return nil
	end
	local out = {}
	for i = (p - 1) * cfg.perPage + 1, math.min(#cat.offers, p * cfg.perPage) do
		out[#out + 1] = cat.offers[i]
	end
	return #out > 0 and out or nil
end

-- ------------------------------------------------------------------ coins
function Shop.getCoins(accountId)
	local rows = Chaos.select("SELECT `coins` FROM `" .. T_COINS .. "` WHERE `account_id` = " .. accountId, {{"coins", "n"}})
	return rows[1] and rows[1].coins or 0
end

function Shop.addCoins(accountId, amount)
	db.query("INSERT INTO `" .. T_COINS .. "` (`account_id`, `coins`) VALUES (" .. accountId .. ", " .. math.max(0, amount) ..
		") ON DUPLICATE KEY UPDATE `coins` = GREATEST(0, `coins` + " .. amount .. ")")
end

-- takes the coins if the account has them; true on success. Game scripts run on one thread and
-- db.query is synchronous, so the check and the update cannot interleave with another purchase.
local function spend(accountId, amount)
	if Shop.getCoins(accountId) < amount then
		return false
	end
	return db.query("UPDATE `" .. T_COINS .. "` SET `coins` = `coins` - " .. amount ..
		" WHERE `account_id` = " .. accountId .. " AND `coins` >= " .. amount) and true or false
end

local function logHistory(player, title, cost)
	db.asyncQuery("INSERT INTO `" .. T_HISTORY .. "` (`account_id`, `player_id`, `title`, `cost`, `created`) VALUES (" ..
		player:getAccountId() .. ", " .. player:getGuid() .. ", " .. db.escapeString(title) .. ", " .. cost .. ", " .. os.time() .. ")")
end

-- the purchase log (synchronous: weekly limits and starter packs read it right after)
local function logPurchase(player, offer, title, price, listPrice, giftAccount, giftPlayer)
	db.query("INSERT INTO `" .. T_PURCHASES .. "` (`account_id`, `player_id`, `player_name`, `level`, `offer_key`, `category`, " ..
		"`title`, `price`, `list_price`, `gift_account`, `gift_player`, `created`) VALUES (" .. player:getAccountId() .. ", " ..
		player:getGuid() .. ", " .. db.escapeString(player:getName()) .. ", " .. player:getLevel() .. ", " ..
		db.escapeString(offer.key) .. ", " .. db.escapeString(offer.category or "") .. ", " .. db.escapeString(title) .. ", " ..
		price .. ", " .. (listPrice or price) .. ", " .. (giftAccount or 0) .. ", " .. (giftPlayer or 0) .. ", " .. os.time() .. ")")
end

-- ------------------------------------------------------------------ protocol
local function send(player, action, data, withStatus)
	local payload = {action = action, data = data}
	if withStatus then
		payload.status = {points = Shop.getCoins(player:getAccountId()), buyUrl = cfg.buyUrl or "", ad = {}}
	end
	player:sendExtendedOpcode(OPCODE, json.encode(payload))
end

local function message(player, title, text)
	send(player, "message", {title = title, msg = text}, true)
end

-- ------------------------------------------------------------------ checks before coins are taken
local function nameOf(offer)
	if offer.name then
		return offer.name
	end
	local x = (offer.kind == "wings" and WINGS[offer.id]) or (offer.kind == "aura" and AURAS[offer.id]) or nil
	return x and x.name or offer.key
end

-- why `target` cannot get this offer now (nil = it can); gift = bought by someone else
local function partProblem(target, offer, gift)
	if offer.kind == "pact" then
		return nil
	end
	if Shop.owns(target, offer) then
		return (gift and (target:getName() .. " already owns ") or "You already own ") .. nameOf(offer) .. "."
	end
	if not gift and offer.premium and (offer.kind == "outfit" or offer.kind == "addons" or offer.kind == "mount") and
		not target:isPremium() then
		return nameOf(offer) .. " needs a Premium account to wear. Get Premium Time first."
	end
	if offer.kind == "service" or offer.kind == "unlock" then
		if not ChaosShopServices then
			return "This offer is not available."
		end
		return ChaosShopServices.check(target, offer)
	end
	return nil
end

function Shop.partsProblem(target, offer, gift)
	local parts = offer.kind == "bundle" and offer.resolved or {offer}
	for _, part in ipairs(parts) do
		local problem = partProblem(target, part, gift)
		if problem then
			return problem
		end
	end
	return nil
end

local function offerProblem(player, offer, gift)
	if not gift then
		if offer.seasonBlocked and isSeason(player) then
			return "Season characters cannot buy " .. nameOf(offer) .. "."
		end
		if offer.maxLevel and player:getLevel() > offer.maxLevel then
			return nameOf(offer) .. " is for characters up to level " .. offer.maxLevel .. "."
		end
		if offer.oncePerAccount and boughtCount(player:getAccountId(), offer.key, 0) > 0 then
			return "Your account already bought " .. nameOf(offer) .. "."
		end
	end
	if offer.weeklyLimit and boughtCount(player:getAccountId(), offer.key, weekStart(now())) >= offer.weeklyLimit then
		return "You bought " .. nameOf(offer) .. " " .. offer.weeklyLimit .. " times this week; the limit resets on Monday."
	end
	return Shop.partsProblem(gift or player, offer, gift ~= nil)
end

-- ------------------------------------------------------------------ delivery
-- gives one offer (not a bundle); returns true or an error text
local function deliverOne(player, offer)
	if offer.kind == "item" then
		local count = offer.count or 1
		local given = Chaos.giveItem(player, offer.id, count)
		if given < count then
			if given > 0 then
				player:removeItem(offer.id, given)
			end
			return player:getName() .. " does not have enough room or capacity."
		end
		return true
	elseif offer.kind == "wings" then
		player:addWings(offer.id)
	elseif offer.kind == "aura" then
		player:addAura(offer.id)
	elseif offer.kind == "shader" then
		player:addShader(offer.id)
	elseif offer.kind == "frame" then
		player:setStorageValue(S.shopFrameActive, FRAME_INDEX[offer.frame] or 0)
	elseif offer.kind == "outfit" or offer.kind == "addons" then
		-- both sexes' looks with both addons: a later sex change keeps them (the engine keeps outfits per look type)
		for _, look in ipairs(K.outfitLooks(offer)) do
			player:addOutfit(look)
			player:addOutfitAddon(look, 1)
			player:addOutfitAddon(look, 2)
		end
		if not player:hasOutfit(sexLook(player, offer), 3) then
			return "The outfit could not be added."
		end
	elseif offer.kind == "mount" then
		player:addMount(offer.id)
		if not player:hasMount(offer.id) and not (offer.premium and not player:isPremium()) then
			return "The mount could not be added."
		end
	elseif offer.kind == "premium" then
		player:addPremiumDays(offer.days)
	elseif offer.kind == "pact" then
		local grant = pactGrant()
		if grant then
			grant(player, offer.days, "store")
		end
	elseif offer.kind == "service" or offer.kind == "unlock" then
		if not ChaosShopServices then
			return "This offer is not available."
		end
		return ChaosShopServices.deliver(player, offer)
	else
		return "This offer cannot be bought."
	end
	local key = storageKey(offer)
	if key then
		player:setStorageValue(key, 1)
	end
	return true
end

-- items first (they can fail: no room), then services and unlocks, then cosmetics; a failing item takes back the
-- items of the bundle given so far
local ORDER = {item = 1, service = 2, unlock = 2}
function Shop.deliver(player, offer)
	if offer.kind ~= "bundle" then
		return deliverOne(player, offer)
	end
	local parts = {}
	for i, p in ipairs(offer.resolved) do
		parts[i] = p
	end
	table.sort(parts, function(a, b)
		return (ORDER[a.kind] or 3) < (ORDER[b.kind] or 3)
	end)
	local given = {}
	for _, p in ipairs(parts) do
		local result = deliverOne(player, p)
		if result ~= true then
			for _, g in ipairs(given) do
				player:removeItem(g.id, g.count or 1)
			end
			return result
		end
		if p.kind == "item" then
			given[#given + 1] = p
		end
	end
	return true
end

local function afterDelivery(player)
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
end

-- ------------------------------------------------------------------ gifts
local function giftTarget(player, name)
	local guid, realName = Chaos.findPlayer(tostring(name or ""))
	local t = {found = guid ~= nil, name = realName, guid = guid}
	if not guid then
		return t
	end
	t.self = guid == player:getGuid()
	local rows = Chaos.select("SELECT `account_id`, `group_id` FROM `players` WHERE `id` = " .. guid, {{"account_id", "n"}, {"group_id", "n"}})
	if not rows[1] then
		t.found = false
		return t
	end
	t.account, t.staff = rows[1].account_id, rows[1].group_id >= 2
	local bans = Chaos.select("SELECT COUNT(*) AS `n` FROM `account_bans` WHERE `account_id` = " .. t.account ..
		" AND (`expires_at` <= 0 OR `expires_at` > " .. now() .. ")", {{"n", "n"}})
	t.banned = (bans[1] and bans[1].n or 0) > 0
	return t
end

local function giftsToday(accountId)
	local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM `" .. T_PURCHASES .. "` WHERE `account_id` = " .. accountId ..
		" AND `gift_player` > 0 AND `created` >= " .. (now() - 86400), {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

-- pending gifts of a character that logs in
function Shop.deliverGifts(player)
	local rows = Chaos.select("SELECT `id`, `offer_key`, `title`, `price`, `from_account`, `from_name` FROM `" .. T_GIFTS ..
		"` WHERE `target_player` = " .. player:getGuid() .. " AND `status` = 0 ORDER BY `id`",
		{{"id", "n"}, {"offer_key", "s"}, {"title", "s"}, {"price", "n"}, {"from_account", "n"}, {"from_name", "s"}})
	for _, r in ipairs(rows) do
		local offer = byKey[r.offer_key]
		local problem = not offer and "it is no longer sold" or Shop.partsProblem(player, offer, true)
		local result = problem or Shop.deliver(player, offer)
		if result == true then
			db.query("UPDATE `" .. T_GIFTS .. "` SET `status` = 1, `done` = " .. now() .. " WHERE `id` = " .. r.id)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, r.from_name .. " gave you " .. r.title .. " from the Chaos store.")
			afterDelivery(player)
		else
			db.query("UPDATE `" .. T_GIFTS .. "` SET `status` = 2, `done` = " .. now() .. " WHERE `id` = " .. r.id .. " AND `status` = 0")
			Shop.addCoins(r.from_account, r.price)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, r.from_name .. " sent you " .. r.title .. ", but " ..
				tostring(result):gsub("%.$", ""):lower() .. "; the coins went back to them.")
		end
	end
end

-- ------------------------------------------------------------------ buying
local function buy(player, data)
	local list = Shop.view(player)
	local c, p, o = Chaos.toInt(data.category, 1), Chaos.toInt(data.page, 1), Chaos.toInt(data.offer, 1)
	local page = c and p and pageOf(list, c, p)
	local e = page and o and page[o]
	if not e then
		send(player, "categories", categoriesView(player, list), true)
		return message(player, "Error", "This offer does not exist any more.")
	end
	local offer = e.offer
	local view = clientOffer(e, nil)
	-- the client echoes title and cost: a stale window must not buy something else or at another price
	if data.title ~= view.title or tonumber(data.cost) ~= e.cost then
		send(player, "categories", categoriesView(player, list), true)
		return message(player, "Error", "The store changed. Please choose the offer again.")
	end
	local accountId = player:getAccountId()

	-- a gift
	local giftName = type(data.gift) == "string" and data.gift ~= "" and data.gift or nil
	local target, targetPlayer
	if giftName then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "shop.giftbuy", (cfg.gifts or {}).cooldownMs or 3000) then
			return message(player, "Not possible", "Please wait a moment before the next gift.")
		end
		target = giftTarget(player, giftName)
		target.kind = giftable(offer) and offer.kind or "service"
		local problem = K.giftProblem(target)
		if not problem and giftsToday(accountId) >= ((cfg.gifts or {}).perDay or 20) then
			problem = "You sent as many gifts as you may today."
		end
		if problem then
			return message(player, "Not possible", problem)
		end
		targetPlayer = Player(target.name)
		if targetPlayer then
			problem = offerProblem(player, offer, targetPlayer)
		elseif offer.weeklyLimit then
			problem = offerProblem(player, {key = offer.key, weeklyLimit = offer.weeklyLimit, name = offer.name})
		end
		if problem then
			return message(player, "Not possible", problem)
		end
	else
		local problem = offerProblem(player, offer, nil)
		if problem then
			return message(player, "Not possible", problem)
		end
	end

	if Shop.getCoins(accountId) < e.cost then
		return message(player, "Not enough coins", "You need " .. e.cost .. " Chaos Coins for " .. view.title .. ".")
	end
	if not spend(accountId, e.cost) then
		return message(player, "Error", "Could not take the coins. Try again.")
	end

	if target then
		if targetPlayer then
			local result = Shop.deliver(targetPlayer, offer)
			if result ~= true then
				Shop.addCoins(accountId, e.cost)
				return message(player, "Error", result)
			end
			afterDelivery(targetPlayer)
			targetPlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, player:getName() .. " gave you " .. view.title .. " from the Chaos store.")
			targetPlayer:getPosition():sendMagicEffect(cfg.purchaseEffect)
		else
			db.query("INSERT INTO `" .. T_GIFTS .. "` (`target_player`, `offer_key`, `title`, `price`, `from_account`, `from_name`, `created`) VALUES (" ..
				target.guid .. ", " .. db.escapeString(offer.key) .. ", " .. db.escapeString(view.title) .. ", " .. e.cost .. ", " ..
				accountId .. ", " .. db.escapeString(player:getName()) .. ", " .. now() .. ")")
		end
		logPurchase(player, offer, view.title, e.cost, e.oldCost, target.account, target.guid)
		logHistory(player, view.title .. " (gift to " .. target.name .. ")", e.cost)
		log(player:getName() .. " gave " .. offer.key .. " to " .. target.name .. " for " .. e.cost)
		return message(player, "Gift sent", "You gave " .. view.title .. " to " .. target.name .. " for " .. e.cost .. " Chaos Coins." ..
			(targetPlayer and "" or " It is delivered at their next login."))
	end

	local result = Shop.deliver(player, offer)
	if result ~= true then
		Shop.addCoins(accountId, e.cost) -- refund
		return message(player, "Error", result)
	end
	afterDelivery(player)
	logPurchase(player, offer, view.title, e.cost, e.oldCost)
	logHistory(player, view.title, e.cost)
	player:getPosition():sendMagicEffect(cfg.purchaseEffect)
	if offer.oncePerAccount then
		send(player, "categories", categoriesView(player), true)
	else
		-- the page again: the offer now reads "Owned" and its Buy button is off
		local fresh = pageOf(Shop.view(player), c, p)
		if fresh then
			local offers = {}
			for i, x in ipairs(fresh) do
				offers[i] = clientOffer(x, player)
			end
			send(player, "category_page", {category = c, page = p, offers = offers})
		end
	end
	message(player, "Purchase complete", "You bought " .. view.title .. " for " .. e.cost .. " Chaos Coins.")
end

local function history(player)
	local rows = Chaos.select("SELECT `title`, `cost`, `created` FROM `" .. T_HISTORY .. "` WHERE `account_id` = " ..
		player:getAccountId() .. " ORDER BY `id` DESC LIMIT 50", {{"title", "s"}, {"cost", "n"}, {"created", "n"}})
	local list = {}
	for _, r in ipairs(rows) do
		list[#list + 1] = {
			type = "item", item = ItemType(29856):getClientId(), count = 1, cost = r.cost, title = r.title,
			description = "Bought on " .. os.date("%Y-%m-%d %H:%M", r.created) .. " for " .. r.cost .. " Chaos Coins."
		}
	end
	send(player, "history", list, true)
end

local function gift(player, data)
	local amount = Chaos.toInt(data.amount, cfg.giftMin)
	if not amount then
		return message(player, "Error", "You can gift at least " .. cfg.giftMin .. " Chaos Coins.")
	end
	local guid, name = Chaos.findPlayer(tostring(data.name or ""))
	if not guid then
		return message(player, "Error", "There is no character with that name.")
	end
	local rows = Chaos.select("SELECT `account_id` FROM `players` WHERE `id` = " .. guid, {{"account_id", "n"}})
	local target = rows[1] and rows[1].account_id
	if not target or target == player:getAccountId() then
		return message(player, "Error", "You cannot gift coins to your own account.")
	end
	if not spend(player:getAccountId(), amount) then
		return message(player, "Not enough coins", "You do not have " .. amount .. " Chaos Coins.")
	end
	Shop.addCoins(target, amount)
	logHistory(player, "Gift to " .. name, amount)
	message(player, "Gift sent", "You gifted " .. amount .. " Chaos Coins to " .. name .. ".")
end

local ext = CreatureEvent("ChaosShopExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.data) ~= "table" then
		return
	end
	if msg.action == "init" then
		send(player, "categories", categoriesView(player), true)
	elseif msg.action == "get_page" then
		local c, p = Chaos.toInt(msg.data.category, 1), Chaos.toInt(msg.data.page, 1)
		local page = c and p and pageOf(Shop.view(player), c, p)
		if page then
			local offers = {}
			for i, e in ipairs(page) do
				offers[i] = clientOffer(e, player)
			end
			send(player, "category_page", {category = c, page = p, offers = offers})
		end
	elseif msg.action == "buy" then
		if not ChaosRateLimit or ChaosRateLimit.allow(player, "shop.buy", 300) then
			buy(player, msg.data)
		end
	elseif msg.action == "history" then
		-- database reads (ratelimit.lua)
		if not ChaosRateLimit or ChaosRateLimit.allow(player, "shop.history", 1000) then
			history(player)
		end
	elseif msg.action == "gift_coins" then
		if not ChaosRateLimit or ChaosRateLimit.allow(player, "shop.gift", 1000) then
			gift(player, msg.data)
		end
	end
end
ext:type("extendedopcode")
ext:register()

-- ------------------------------------------------------------------ name plate frames (titles.lua frame source "store")
function Shop.frameOf(player)
	local i = player:getStorageValue(S.shopFrameActive)
	local frame = FRAMES[i]
	if frame and player:getStorageValue(S.shopFrameBase + i) > 0 then
		return frame
	end
	return nil
end

local function registerFrames()
	if ChaosTitles and ChaosTitles.registerFrame then
		ChaosTitles.registerFrame("store", Shop.frameOf)
	end
end
registerFrames()

-- switching frames: Info & Services > Services, "Plate frame" (commands_ui.lua id "plateframe": violet | frost | off)
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
local function plateFrame(player, param)
	local want = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local owned = {}
	for i, f in ipairs(FRAMES) do
		if player:getStorageValue(S.shopFrameBase + i) > 0 then
			owned[#owned + 1] = f
		end
	end
	if want == "off" then
		player:setStorageValue(S.shopFrameActive, 0)
	elseif FRAME_INDEX[want] and player:getStorageValue(S.shopFrameBase + FRAME_INDEX[want]) > 0 then
		player:setStorageValue(S.shopFrameActive, FRAME_INDEX[want])
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Your name plate frames: " ..
			(#owned > 0 and table.concat(owned, ", ") or "none (Store > Name Plates)") .. ".")
		return
	end
	afterDelivery(player)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Name plate frame: " .. (want == "off" and "your title's own" or want) .. ".")
end
ChaosCommands.register("plateframe", plateFrame)
Shop.plateFrame = plateFrame

-- ------------------------------------------------------------------ paid Chaos Coin orders (shop_coins_config.lua)
local PACKS = {}
for _, pack in ipairs(coinsCfg.packs or {}) do
	PACKS[pack.key] = pack
end

local function orderCount(accountId, where)
	local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM `" .. T_ORDERS .. "` WHERE `account_id` = " .. accountId ..
		" AND `status` = 'credited' AND " .. where, {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

-- credits every paid order (one transaction each: coins and status together)
function Shop.processOrders()
	local rows = Chaos.select("SELECT `id`, `account_id`, `pack_key` FROM `" .. T_ORDERS .. "` WHERE `status` = 'paid' ORDER BY `id` LIMIT 50",
		{{"id", "n"}, {"account_id", "n"}, {"pack_key", "s"}})
	for _, r in ipairs(rows) do
		local pack = PACKS[r.pack_key]
		local reject
		if not pack then
			reject = "unknown pack"
		elseif pack.once and orderCount(r.account_id, "`pack_key` = " .. db.escapeString(pack.key)) > 0 then
			reject = "one per account, already credited"
		end
		if reject then
			db.query("UPDATE `" .. T_ORDERS .. "` SET `status` = 'rejected', `note` = " .. db.escapeString(reject) ..
				" WHERE `id` = " .. r.id .. " AND `status` = 'paid'")
			log("coin order " .. r.id .. " rejected: " .. reject)
		else
			local starters = {}
			for key, p in pairs(PACKS) do
				if p.starter then
					starters[#starters + 1] = db.escapeString(key)
				end
			end
			local first = orderCount(r.account_id, #starters > 0 and ("`pack_key` NOT IN (" .. table.concat(starters, ",") .. ")") or "1") == 0
			local credit = K.packCredit(pack, first, coinsCfg)
			db.query("START TRANSACTION")
			-- the row again, locked: the website may have marked it refunded since the SELECT above
			local still = Chaos.select("SELECT `status` FROM `" .. T_ORDERS .. "` WHERE `id` = " .. r.id .. " FOR UPDATE", {{"status", "s"}})[1]
			if still and still.status == "paid" then
				db.query("UPDATE `" .. T_ORDERS .. "` SET `status` = 'credited', `coins` = " .. credit.coins .. ", `bonus` = " .. credit.bonus ..
					", `first_bonus` = " .. credit.firstBonus .. ", `credited` = " .. now() .. " WHERE `id` = " .. r.id .. " AND `status` = 'paid'")
				Shop.addCoins(r.account_id, credit.total)
			end
			db.query("COMMIT")
			if still and still.status == "paid" then
				log(string.format("coin order %d: %d coins to account %d (%s, bonus %d, first purchase %d)", r.id, credit.total,
					r.account_id, pack.key, credit.bonus, credit.firstBonus))
				for _, p in ipairs(Game.getPlayers()) do
					if p:getAccountId() == r.account_id then
						-- coin packs are donations (shop_payments_core.lua ChaosPayCore.thanks)
						p:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Thank you for your voluntary donation! You received %d Chaos Coins as a thank-you (%s%s).",
							credit.total, pack.name or pack.key, credit.firstBonus > 0 and ", first donation bonus included" or ""))
						break
					end
				end
				if ChaosShopPay and ChaosShopPay.onCredited then
					ChaosShopPay.onCredited(r.id, r.account_id, credit, pack)
				end
			end
		end
	end
end

local orders = GlobalEvent("ChaosShopCoinOrders")
function orders.onThink(interval)
	Shop.processOrders()
	return true
end
orders:interval((coinsCfg.pollSeconds or 30) * 1000)
orders:register()

local startup = GlobalEvent("ChaosShopStartup")
function startup.onStartup()
	registerFrames()
	Shop.processOrders()
	return true
end
startup:register()

local login = CreatureEvent("ChaosShopLogin")
function login.onLogin(player)
	player:registerEvent("ChaosShopExtended")
	registerFrames()
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			Shop.deliverGifts(p)
		end
	end, 2000, player:getId())
	return true
end
login:register()

-- /coins <player>, <amount>   (staff; negative amounts take coins away)
local talk = TalkAction("/coins")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local name, amount = param:match("^%s*(.-)%s*,%s*(%-?%d+)%s*$")
	local guid, realName = Chaos.findPlayer(name or "")
	amount = tonumber(amount)
	if not guid or not amount then
		player:sendCancelMessage("Usage: /coins <player>, <amount>")
		return false
	end
	local rows = Chaos.select("SELECT `account_id` FROM `players` WHERE `id` = " .. guid, {{"account_id", "n"}})
	if not rows[1] then
		return false
	end
	Shop.addCoins(rows[1].account_id, amount)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s now has %d Chaos Coins.", realName, Shop.getCoins(rows[1].account_id)))
	return false
end
talk:separator(" ")
talk:register()

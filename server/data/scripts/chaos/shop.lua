-- Chaos store (client module game_shop, extended opcode ChaosOpcodes.shop, JSON).
--
-- client -> server {"action": ..., "data": {...}}
--   init                                    -> "categories" (+ status)
--   get_page {category, page}               -> "category_page" {category, page, offers}
--   buy {category, page, offer, title, cost} -> "message" (+ status)
--   history                                 -> "history" [offers with a description line]
--   gift_coins {name, amount}               -> "message" (+ status)
-- server -> client {"action": ..., "data": ..., "status": {points, ad, buyUrl}}
--
-- Coins live per account in chaos_shop_coins, purchases in chaos_shop_history (server/sql/chaos.sql).
-- Staff add coins with /coins <player>, <amount>. Offers are in shop_config.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosShopConfig = dofile("data/scripts/chaos/shop_config.lua")
local cfg = ChaosShopConfig
local OPCODE = ChaosOpcodes.shop
local T_COINS, T_HISTORY = Chaos.tables.shopCoins, Chaos.tables.shopHistory
local S = Chaos.storage

ChaosShop = ChaosShop or {}
local Shop = ChaosShop

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

-- storage that marks a one-time cosmetic as owned
local function ownedKey(offer)
	if offer.kind == "wings" then
		return S.shopWingsBase + offer.id
	elseif offer.kind == "aura" then
		return S.shopAuraBase + offer.id
	elseif offer.kind == "shader" then
		return S.shopShaderBase + offer.id
	end
	return nil
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

local function clientOffer(offer)
	local view = {cost = offer.cost, title = offer.name, description = offer.description or ""}
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
	elseif offer.kind == "outfit" then
		view.type = "outfit"
		view.outfit = {type = offer.looktype, head = 2, body = 116, legs = 114, feet = 114, addons = offer.addons or 0, rotating = true}
	elseif offer.kind == "mount" then
		view.type, view.outfit = "outfit", {type = offer.clientid, rotating = true}
	elseif offer.kind == "premium" then
		view.type, view.item, view.count = "item", ItemType(16101):getClientId(), 1
	elseif offer.kind == "unlock" and offer.look then
		-- a pet (pets.lua): its outfit
		view.type, view.outfit = "outfit", {type = offer.look, rotating = true}
	elseif offer.kind == "service" or offer.kind == "unlock" then
		-- shop_services.lua: the icon is any item picture
		view.type, view.item, view.count = "item", ItemType(offer.icon or 1949):getClientId(), offer.iconCount or 1
	end
	view.title = view.title or "Offer"
	return view
end

local pages = {} -- [category][page] = {offer, ...} (server offers)
for c, category in ipairs(cfg.categories) do
	pages[c] = {}
	for i, offer in ipairs(category.offers) do
		local p = math.floor((i - 1) / cfg.perPage) + 1
		pages[c][p] = pages[c][p] or {}
		table.insert(pages[c][p], offer)
	end
end

local function categoriesView()
	local list = {}
	for c, category in ipairs(cfg.categories) do
		local entry = {name = category.name, pages = #pages[c]}
		if category.icon.item then
			entry.type, entry.item, entry.count = "item", ItemType(category.icon.item):getClientId(), category.icon.count or 1
		else
			entry.type, entry.outfit = "outfit", category.icon.outfit
		end
		list[c] = entry
	end
	return list
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

-- gives what the offer sells; returns true or an error text
local function deliver(player, offer)
	if offer.kind == "item" then
		local count = offer.count or 1
		local given = Chaos.giveItem(player, offer.id, count)
		if given < count then
			if given > 0 then
				player:removeItem(offer.id, given)
			end
			return "You do not have enough room or capacity."
		end
		return true
	elseif offer.kind == "wings" then
		player:addWings(offer.id)
	elseif offer.kind == "aura" then
		player:addAura(offer.id)
	elseif offer.kind == "shader" then
		player:addShader(offer.id)
	elseif offer.kind == "outfit" then
		local look = player:getSex() == PLAYERSEX_FEMALE and (offer.lookfemale or offer.looktype) or offer.looktype
		if player:hasOutfit(look, offer.addons or 0) then
			return "You already have this outfit."
		end
		player:addOutfit(look)
		if (offer.addons or 0) >= 1 then
			player:addOutfitAddon(look, 1)
		end
		if (offer.addons or 0) >= 2 then
			player:addOutfitAddon(look, 2)
		end
	elseif offer.kind == "mount" then
		if player:hasMount(offer.id) then
			return "You already have this mount."
		end
		player:addMount(offer.id)
	elseif offer.kind == "premium" then
		player:addPremiumDays(offer.days)
	elseif offer.kind == "service" or offer.kind == "unlock" then
		if not ChaosShopServices then
			return "This offer is not available."
		end
		return ChaosShopServices.deliver(player, offer)
	else
		return "This offer cannot be bought."
	end
	return true
end

local function buy(player, data)
	local c, p, o = Chaos.toInt(data.category, 1), Chaos.toInt(data.page, 1), Chaos.toInt(data.offer, 1)
	local offer = c and p and o and pages[c] and pages[c][p] and pages[c][p][o]
	if not offer then
		send(player, "categories", categoriesView(), true)
		return message(player, "Error", "This offer does not exist any more.")
	end
	local view = clientOffer(offer)
	-- the client echoes title and cost: a stale window must not buy something else
	if data.title ~= view.title or tonumber(data.cost) ~= offer.cost then
		send(player, "categories", categoriesView(), true)
		return message(player, "Error", "The store changed. Please choose the offer again.")
	end
	local key = ownedKey(offer)
	if key and player:getStorageValue(key) > 0 then
		return message(player, "Error", "You already own " .. view.title .. ".")
	end
	-- services and unlocks say before any coin is taken whether they can apply now (owned, stamina full, ...)
	if offer.kind == "service" or offer.kind == "unlock" then
		local problem = "This offer is not available."
		if ChaosShopServices then
			problem = ChaosShopServices.check(player, offer)
		end
		if problem then
			return message(player, "Not possible", problem)
		end
	end
	local accountId = player:getAccountId()
	if Shop.getCoins(accountId) < offer.cost then
		return message(player, "Not enough coins", "You need " .. offer.cost .. " Chaos Coins for " .. view.title .. ".")
	end
	if not spend(accountId, offer.cost) then
		return message(player, "Error", "Could not take the coins. Try again.")
	end
	local result = deliver(player, offer)
	if result ~= true then
		Shop.addCoins(accountId, offer.cost) -- refund
		return message(player, "Error", result)
	end
	if key then
		player:setStorageValue(key, 1)
	end
	logHistory(player, view.title, offer.cost)
	player:getPosition():sendMagicEffect(cfg.purchaseEffect)
	message(player, "Purchase complete", "You bought " .. view.title .. " for " .. offer.cost .. " Chaos Coins.")
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
		send(player, "categories", categoriesView(), true)
	elseif msg.action == "get_page" then
		local c, p = Chaos.toInt(msg.data.category, 1), Chaos.toInt(msg.data.page, 1)
		if c and p and pages[c] and pages[c][p] then
			local offers = {}
			for i, offer in ipairs(pages[c][p]) do
				offers[i] = clientOffer(offer)
			end
			send(player, "category_page", {category = c, page = p, offers = offers})
		end
	elseif msg.action == "buy" then
		buy(player, msg.data)
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

local login = CreatureEvent("ChaosShopLogin")
function login.onLogin(player)
	player:registerEvent("ChaosShopExtended")
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

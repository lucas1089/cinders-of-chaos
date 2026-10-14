-- The Loot Buyer (server/README.md "Item prices"; data/lib/chaos_item_prices.lua, data/scripts/chaos/item_prices.lua).
-- Runs in the NPC's own Lua state. Buys every item the price table prices, each copy at its own price:
--   "trade"          the trade window lists what the player carries (in the backpack and its containers) at the plain
--                    price; a sale pays every copy by ChaosItemPrices.sellPrice (rarity, item level), never takes a
--                    locked item or a unique, and pays the gold like any NPC
--   "appraise"       the most valuable copies the player carries and what the whole backpack is worth here
--   uniques are never bought (owner 2026-10-14: salvage or market); asked about them, he says so
-- Items the table does not buy (currency, keys, quest, store-bound, profession materials) are not listed; asked about
-- them, he says why.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
-- only the nearest NPC answers a greeting (data/lib/chaos_npc_focus.lua)
if not ChaosNpcFocus then pcall(dofile, "data/lib/chaos_npc_focus.lua") end
function onCreatureSay(cid, type, msg)
	if not ChaosNpcFocus or ChaosNpcFocus.hears(cid, npcHandler) then
		npcHandler:onCreatureSay(cid, type, msg)
	end
end
function onThink()				npcHandler:onThink()					end

-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
end

local okLib = pcall(dofile, "data/lib/chaos_item_prices.lua")
local P = ChaosItemPrices
local okCfg, cfg = pcall(dofile, "data/scripts/chaos/item_prices_config.lua")
if not okCfg or type(cfg) ~= "table" then
	cfg = {appraiseLines = 12}
end

local shopModule = ShopModule:new()
npcHandler:addModule(shopModule)

local function fmt(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function ready()
	return okLib and P and P.sellPrice
end

-- the trade window: what this player carries and the table buys, at the plain price
local function onTradeRequest(cid)
	local player = Player(cid)
	if not player or not ready() then
		return false
	end
	local list, seen = {}, {}
	for _, item in ipairs(P.carried(player)) do
		local id = item:getId()
		if not seen[id] then
			seen[id] = true
			local price = P.basePrice(id)
			if price > 0 then
				list[#list + 1] = {id = id, buy = -1, sell = price, subType = 0, name = ItemType(id):getName()}
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	npcHandler.shopItems = list
	if #list == 0 then
		npcHandler:say(t(cid, "You carry nothing I buy. Coins, orbs, keys, quest items and store items stay with you; ores, herbs, hides and fish go to the Material Broker."), cid)
		return false
	end
	return true
end

-- a sale from the trade window: each copy at its own price; the module's flat-price sale never runs
local function onSell(cid, itemid, subType, amount, ignoreEquipped)
	local player = Player(cid)
	if not player or not ready() then
		return false
	end
	local gold, units, kept = P.sell(player, P.carried(player, itemid), amount)
	if gold > 0 then
		player:addMoney(gold)
		player:sendTextMessage(MESSAGE_INFO_DESCR, t(player, "Sold %dx %s for %s gold.", units, ItemType(itemid):getName(), fmt(gold)))
	end
	if kept > 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, t(player, kept == 1 and
			"Kept %d copy: locked, a unique (salvage it or sell it on the market) or a container that is not empty." or
			"Kept %d copies: locked, a unique (salvage it or sell it on the market) or a container that is not empty.", kept))
	end
	if gold <= 0 and kept == 0 then
		player:sendCancelMessage(t(player, "You do not have this item."))
	end
	npcHandler.talkStart[cid] = os.time()
	return false
end

npcHandler:setCallback(CALLBACK_ONTRADEREQUEST, onTradeRequest)
npcHandler:setCallback(CALLBACK_ONSELL, onSell)

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function appraise(cid, player)
	local rows, total = {}, 0
	for _, item in ipairs(P.carried(player)) do
		if not P.saleBlock(item) then
			local price = P.sellPrice(item)
			total = total + price
			rows[#rows + 1] = {price = price, name = item:getName()}
		end
	end
	if #rows == 0 then
		npcHandler:say(t(cid, "Nothing in your bags that I buy."), cid)
		return
	end
	table.sort(rows, function(a, b) return a.price > b.price end)
	local parts = {}
	for i = 1, math.min(#rows, cfg.appraiseLines or 12) do
		parts[#parts + 1] = string.format("%s %s", rows[i].name, fmt(rows[i].price))
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, t(player, "Loot Buyer: %s. Everything I buy in your bags: %s gold (locked items and uniques left out).",
		table.concat(parts, ", "), fmt(total)))
	npcHandler:say(t(cid, "All of it together: %s gold. The list is in your server log.", fmt(total)), cid)
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player or not ready() then
		return false
	end
	local text = msg:lower()
	if has(text, "appraise", "worth", "value") then
		appraise(cid, player)
		return true
	elseif has(text, "unique") then
		npcHandler:say(t(cid, "A unique? Keep it, salvage it or sell it on the market. I will not put a price on a thing like that."), cid)
		return true
	elseif has(text, "orb", "coin", "key", "token", "shard") then
		npcHandler:say(t(cid, "Orbs, coins, keys, tokens and shards are worth more to you than to me: trade orbs at the Orb Exchange."), cid)
		return true
	elseif has(text, "ore", "herb", "hide", "fish", "material") then
		npcHandler:say(t(cid, "The Material Broker pays better for what you gather; I leave those to him."), cid)
		return true
	elseif has(text, "rarity", "rare", "level", "price") then
		npcHandler:say(t(cid, "A plain piece pays the listed price. Uncommon pays half again, rare three times, epic six, legendary twelve, and higher still above that; each item level adds half a percent."), cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- greet, farewell, walk away and trade lines in the player's language
npcHandler:addModule(FocusModule:new())

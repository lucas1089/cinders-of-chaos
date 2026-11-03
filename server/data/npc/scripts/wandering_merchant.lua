-- The Wandering Merchant (world event, data/scripts/chaos/worldevents.lua). Runs in the NPC's own Lua state, so it
-- reads its goods straight from the config file: invasion_config.lua worldEvents.merchant.items ({id, price, name,
-- seasonBlocked}). A seasonBlocked item (the double experience potion) is refused to season characters, both in the
-- trade window and by "buy <name>": the realm comes from chaos_season_players and season_core.lua, as in season.lua.
-- O399: one of each item per character and stop (perStop; the stop is floor(os.time() / (moveHours * 3600)), the same
-- clock worldevents.lua moves him by). A bought item is marked in player storage storageBase + its place - 1 with the
-- stop + 1. Spoken buys are sent to the trade window, which checks the limit.
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

local shopModule = ShopModule:new()
npcHandler:addModule(shopModule)

local ok, cfg = pcall(dofile, "data/scripts/chaos/invasion_config.lua")
local merchant = ok and type(cfg) == "table" and cfg.worldEvents and cfg.worldEvents.merchant or {}
local items = merchant.items or {}
local refuseText = merchant.seasonBlockedText or "Season characters cannot buy a %s."

-- season realm of a player (0 = standard character); any error counts as standard
local seasonOk = pcall(dofile, "data/scripts/chaos/season_core.lua")
local seasonCfgOk, seasonCfg = pcall(dofile, "data/scripts/chaos/season_config.lua")
local function configNumber(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key))
	if not id then
		return nil
	end
	local v = tonumber(result.getString(id, "value"))
	result.free(id)
	return v
end
local function seasonRealm(player)
	if not (seasonOk and seasonCfgOk and type(seasonCfg) == "table" and ChaosSeason and ChaosSeason.realm) then
		return 0
	end
	local S = ChaosSeason
	local id = db.storeQuery(string.format("SELECT `season`, `migrated_at` FROM `%s` WHERE `player_id` = %d",
		seasonCfg.tables.players, player:getGuid()))
	if not id then
		return 0
	end
	local row = {season = result.getNumber(id, "season"), migrated = result.getNumber(id, "migrated_at")}
	result.free(id)
	local ov = {}
	for _, s in ipairs(seasonCfg.seasons or {}) do
		local start = configNumber(seasonCfg.configPrefix .. s.id .. "_start")
		local finish = configNumber(seasonCfg.configPrefix .. s.id .. "_end")
		if start or finish then
			ov[s.id] = {start = start, finish = finish}
		end
	end
	return S.realm(row, os.time(), seasonCfg.seasons, ov) or 0
end

local blocked = {} -- item id -> name
local place = {} -- item id -> its place in the list (1-based)
for i, it in ipairs(items) do
	place[it.id] = i
	if it.seasonBlocked then
		blocked[it.id] = it.name
	end
end

-- the limit per stop (O399)
local perStop = tonumber(merchant.perStop) or 0
local storageBase = tonumber(merchant.storageBase)
local limited = perStop > 0 and storageBase ~= nil
local function stopNumber()
	local period = math.max(1, math.floor((tonumber(merchant.moveHours) or 3) * 3600))
	return math.floor(os.time() / period), period
end
local function boughtKey(itemId)
	return place[itemId] and storageBase + place[itemId] - 1
end
-- true (and the NPC says why) when the limit stops this buy
local function overLimit(cid, itemId, amount)
	if not limited then
		return false
	end
	local player = Player(cid)
	local key = boughtKey(itemId)
	if not player or not key then
		return false
	end
	local stop, period = stopNumber()
	if (tonumber(amount) or 1) > perStop then
		npcHandler:say(t(cid, "One of each per customer, friend. I have only so much to go around."), cid)
		return true
	end
	if player:getStorageValue(key) == stop + 1 then
		local left = math.max(1, math.ceil(((stop + 1) * period - os.time()) / 60))
		npcHandler:say(t(cid, "You already bought that from me here. I move on in %d minutes; find me again then.", left), cid)
		return true
	end
	return false
end

-- true (and the NPC says why) when this player may not buy this item
local function refused(cid, itemId)
	local name = blocked[itemId]
	local player = Player(cid)
	if not name or not player then
		return false
	end
	local okRealm, realm = pcall(seasonRealm, player)
	if not okRealm or (tonumber(realm) or 0) <= 0 then
		return false
	end
	npcHandler:say(t(cid, refuseText, name), cid)
	player:sendCancelMessage(t(player, "Season characters cannot buy a %s.", name))
	return true
end

-- trade window
npcHandler:setCallback(CALLBACK_ONBUY, function(cid, itemId, subType, amount, ignoreCap, inBackpacks)
	return not refused(cid, itemId) and not overLimit(cid, itemId, amount)
end)
-- a sale that went through marks the item for this stop (the shop's own callback answers true only then)
if limited and shopModule.callbackOnBuy then
	local shopBuy = shopModule.callbackOnBuy
	function shopModule:callbackOnBuy(cid, itemId, subType, amount, ignoreCap, inBackpacks)
		local done = shopBuy(self, cid, itemId, subType, amount, ignoreCap, inBackpacks)
		local player, key = Player(cid), boughtKey(itemId)
		if done and player and key then
			player:setStorageValue(key, stopNumber() + 1)
		end
		return done
	end
end

-- "buy <name>": a node in front of the shop's own one; it answers only a refusal, else the shop's node goes on
for _, it in ipairs(items) do
	if it.seasonBlocked or limited then
		keywordHandler:addKeyword({"buy", it.name}, function(cid, message, keywords, parameters, node)
			if not npcHandler:isFocused(cid) then
				return false
			end
			if not refused(cid, it.id) then
				if not limited then
					return false
				end
				-- O399: spoken buys could ask for any amount; the trade window keeps the limit
				npcHandler:say(t(cid, "Ask me for a {trade}; one of each per customer."), cid)
			end
			if shop_npcuid then
				shop_npcuid[cid] = 0
			end
			return true
		end)
	end
	shopModule:addBuyableItem({it.name}, it.id, it.price, 1, it.name)
end

ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away / trade lines in the player's language
npcHandler:addModule(FocusModule:new())

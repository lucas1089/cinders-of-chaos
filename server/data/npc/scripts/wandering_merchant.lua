-- The Wandering Merchant (world event, data/scripts/chaos/worldevents.lua). Runs in the NPC's own Lua state, so it
-- reads its goods straight from the config file: invasion_config.lua worldEvents.merchant.items ({id, price, name,
-- seasonBlocked}). A seasonBlocked item (the double experience potion) is refused to season characters, both in the
-- trade window and by "buy <name>": the realm comes from chaos_season_players and season_core.lua, as in season.lua.
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
for _, it in ipairs(items) do
	if it.seasonBlocked then
		blocked[it.id] = it.name
	end
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
	npcHandler:say(string.format(refuseText, name), cid)
	player:sendCancelMessage("Season characters cannot buy a " .. name .. ".")
	return true
end

-- trade window
npcHandler:setCallback(CALLBACK_ONBUY, function(cid, itemId, subType, amount, ignoreCap, inBackpacks)
	return not refused(cid, itemId)
end)

-- "buy <name>": a node in front of the shop's own one; it answers only a refusal, else the shop's node goes on
for _, it in ipairs(items) do
	if it.seasonBlocked then
		keywordHandler:addKeyword({"buy", it.name}, function(cid, message, keywords, parameters, node)
			if not npcHandler:isFocused(cid) or not refused(cid, it.id) then
				return false
			end
			if shop_npcuid then
				shop_npcuid[cid] = 0
			end
			return true
		end)
	end
	shopModule:addBuyableItem({it.name}, it.id, it.price, 1, it.name)
end

npcHandler:addModule(FocusModule:new())

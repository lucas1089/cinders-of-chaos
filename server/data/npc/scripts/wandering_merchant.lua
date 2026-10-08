-- The Wandering Merchant (world event, data/scripts/chaos/worldevents.lua). Runs in the NPC's own Lua state, so it
-- reads its goods straight from the config file: invasion_config.lua worldEvents.merchant.items ({id, price, name}).
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

local shopModule = ShopModule:new()
npcHandler:addModule(shopModule)

local ok, cfg = pcall(dofile, "data/scripts/chaos/invasion_config.lua")
local items = ok and type(cfg) == "table" and cfg.worldEvents and cfg.worldEvents.merchant and cfg.worldEvents.merchant.items or {}
for _, it in ipairs(items) do
	shopModule:addBuyableItem({it.name}, it.id, it.price, 1, it.name)
end

npcHandler:addModule(FocusModule:new())

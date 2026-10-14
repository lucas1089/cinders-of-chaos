-- The Material Broker (server/data/scripts/chaos/professions.lua, professions_config.lua; server/README.md "Professions").
-- Runs in the NPC's own Lua state. "trade": the stock gathering tools in the trade window (professions_config.lua
-- broker.tools). "sell" / "demand" / "materials": opens the client's Professions window on its Broker tab (extended
-- opcode 195, action "npc"); the sale itself is done and checked by professions.lua (a broker close by, the items, the
-- prices of the week, the daily cap), never here.
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

local ok, cfg = pcall(dofile, "data/scripts/chaos/professions_config.lua")
if not ok or type(cfg) ~= "table" then
	cfg = {opcode = 195, broker = {tools = {}}}
end

local shopModule = ShopModule:new()
npcHandler:addModule(shopModule)
for _, t in ipairs(cfg.broker.tools or {}) do
	local it = ItemType(t.id)
	local name = it and it:getName() or ("item " .. t.id)
	if name ~= "" then
		shopModule:addBuyableItem({name}, t.id, t.price, 1, name)
	end
end

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function openWindow(player)
	return pcall(function()
		player:sendExtendedOpcode(cfg.opcode or 195, '{"action":"npc","data":{}}')
	end)
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player then
		return false
	end
	local text = msg:lower()
	if has(text, "sell", "material", "demand", "price", "ore", "herb", "hide", "fish", "profession") then
		openWindow(player)
		npcHandler:say("Show me what you have. My prices change every week, and I only take so much of one thing a day: " ..
			"see the ledger (Economy > Professions).", cid)
		return true
	elseif has(text, "tool", "pick", "sickle", "knife", "rod") then
		npcHandler:say("A pick for the veins, a sickle for the herbs, an obsidian knife for hides and a rod for the water. " ..
			"Ask me to {trade}.", cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())

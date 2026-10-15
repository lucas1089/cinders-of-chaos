-- Osric the Chandler, the Candlemark shop (server/data/scripts/chaos/candlemarks.lua, candlemarks_config.lua;
-- server/README.md "Candlemarks"). Runs in the NPC's own Lua state. "wares" / "trade" / "shop" / "buy" opens the
-- client's Candlemark window (extended opcode 176, action "npc"); prices, limits and purchases are checked by
-- candlemarks.lua, never here. The window opens from the game menu too (Economy > Candlemarks).
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

local ok, cfg = pcall(dofile, "data/scripts/chaos/candlemarks_config.lua")
if not ok or type(cfg) ~= "table" then
	cfg = {opcode = 176, blockMinutes = 30}
end

-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
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
		player:sendExtendedOpcode(cfg.opcode or 176, '{"action":"npc","data":{}}')
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
	if has(text, "ware", "trade", "shop", "buy", "offer", "candle", "mark") then
		openWindow(player)
		npcHandler:say(t(cid, "Here is what your marks can buy. Some of it only once a week, mind you."), cid)
		return true
	elseif has(text, "earn", "how", "time", "coin") then
		npcHandler:say(t(cid, "Every %d minutes a soul spends in this world, a mark is burnt in for its account. Two souls per hearth at most.",
			cfg.blockMinutes or 30), cid)
		return true
	elseif has(text, "job", "name", "who") then
		npcHandler:say(t(cid, "Osric, chandler. I count the hours you keep the dark at bay. Ask about my {wares}."), cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away / trade lines in the player's language
npcHandler:addModule(FocusModule:new())

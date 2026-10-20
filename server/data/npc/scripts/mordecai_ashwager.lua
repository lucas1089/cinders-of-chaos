-- Mordecai Ashwager, the Gambler (server/data/scripts/chaos/gamble.lua, gamble_config.lua; server/README.md "The Gambler").
-- Runs in the NPC's own Lua state. "gamble" / "trade" / "crates" / "buy" opens the client's Gambler window (extended
-- opcode 199, action "npc"); the stock, the price and the purchase are done and checked by gamble.lua (the Gambler
-- close by, the gold, the sold slots, the save before the roll), never here.
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

local ok, cfg = pcall(dofile, "data/scripts/chaos/gamble_config.lua")
if not ok or type(cfg) ~= "table" then
	cfg = {opcode = 199, refresh = {hours = 4}}
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
		player:sendExtendedOpcode(cfg.opcode or 199, '{"action":"npc","data":{}}')
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
	if has(text, "gamble", "trade", "crate", "buy", "offer", "wares", "stock", "seal") then
		openWindow(player)
		npcHandler:say(t(cid, "Pick a crate. You see the make and the craft, never the luck inside. That you pay to learn."), cid)
		return true
	elseif has(text, "odds", "chance", "rarity", "luck") then
		npcHandler:say(t(cid, "Every crate holds something touched by Chaos, never plain iron. Most are modest. One in twenty-five is Legendary or better, no more than the beasts give. The window lists the odds; I hide nothing but the crate."), cid)
		return true
	elseif has(text, "time", "refresh", "new", "when", "change") then
		npcHandler:say(t(cid, "New crates every %d hours, on the mark: midnight, four, eight and so on, by the temple bell. For a price I fetch fresh ones sooner.",
			cfg.refresh and cfg.refresh.hours or 4), cid)
		return true
	elseif has(text, "job", "name", "who") then
		npcHandler:say(t(cid, "Mordecai Ashwager. I sell what the Chaos left sealed. Ask me to {gamble}."), cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away / trade lines in the player's language
npcHandler:addModule(FocusModule:new())

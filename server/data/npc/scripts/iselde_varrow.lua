-- Iselde Varrow, the Conquest vendor (server/data/scripts/chaos/conquest.lua, conquest_config.lua; server/README.md
-- "Conquest Tokens, the Conquest vendor and bad-luck protection"). Runs in the NPC's own Lua state. "wares" / "trade" /
-- "buy" opens the client's Conquest window (extended opcode 167, action "npc"); the offers, the prices and every purchase
-- are checked and done by conquest.lua, never here.
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

local ok, cfg = pcall(dofile, "data/scripts/chaos/conquest_config.lua")
if not ok or type(cfg) ~= "table" then
	cfg = {opcode = 167}
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
		player:sendExtendedOpcode(cfg.opcode or 167, '{"action":"npc","data":{}}')
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
	if has(text, "ware", "trade", "buy", "offer", "stock", "vendor") then
		openWindow(player)
		npcHandler:say(t(cid, "Pick what you need. Anything you have seen fall, or anything of your level, is on my ledger."), cid)
		return true
	elseif has(text, "token", "conquest", "earn") then
		npcHandler:say(t(cid, "Conquest Tokens come from every boss you help slay, every sealed rift, dungeon, Descent run and defended town. The harder the fight, the more you earn."), cid)
		return true
	elseif has(text, "luck", "pity", "chance") then
		npcHandler:say(t(cid, "Every time a boss, a raid or a chest keeps its treasure from you, the next try gets kinder. Once it drops, the count starts over. The window shows how far along you are."), cid)
		return true
	elseif has(text, "job", "name", "who") then
		npcHandler:say(t(cid, "Iselde Varrow. I keep the ledger of conquests. Ask about my {wares}."), cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away / trade lines in the player's language
npcHandler:addModule(FocusModule:new())

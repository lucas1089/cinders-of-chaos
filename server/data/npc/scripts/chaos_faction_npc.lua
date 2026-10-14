-- Shared dialogue of the four faction NPCs (server/data/scripts/chaos/factions.lua, factions_config.lua; server/README.md
-- "Factions"). Each NPC script sets FACTION_KEY and runs this file. It runs in the NPC's own Lua state: it reads the
-- faction's texts from factions_config.lua and only opens the client's Factions window on the faction (extended opcode
-- 215, action "npc"); every action there (contracts, token turn-ins, deliveries, the quartermaster, recipes) is checked
-- again by factions.lua, which also checks that this NPC stands close.
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

local cfg = dofile("data/scripts/chaos/factions_config.lua")
local key = FACTION_KEY
local faction, rival
for _, f in ipairs(cfg.factions) do
	if f.key == key then
		faction = f
	end
end
for _, f in ipairs(cfg.factions) do
	if faction and f.key == faction.rival then
		rival = f
	end
end
local token = cfg.tokens[key]

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function openWindow(player)
	local ok = pcall(function()
		player:sendExtendedOpcode(cfg.opcode, '{"action":"npc","data":{"f":"' .. key .. '"}}')
	end)
	return ok
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) or not faction then
		return false
	end
	local player = Player(cid)
	local text = msg:lower()
	if not player then
		return false
	end
	if has(text, "contract", "work", "task", "quartermaster", "trade", "offer", "buy", "reputation", "standing",
			"token", "deliver", "recipe", "window") then
		openWindow(player)
		npcHandler:say("Here is what " .. faction.name .. " asks, and what it gives. Your contracts, your standing and my "
			.. "stores are in the ledger (Adventure > Factions). Bring " .. token.plural .. " and deliveries to me.", cid)
		return true
	elseif has(text, "lore", "who", "faction", "about") then
		npcHandler:say(faction.lore, cid)
		return true
	elseif rival and has(text, rival.short:lower(), "rival", "enemy") then
		npcHandler:say("Every favour you do " .. rival.name .. " is a favour we remember, and the same is true the other way. "
			.. "Choose, or work twice as hard.", cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())

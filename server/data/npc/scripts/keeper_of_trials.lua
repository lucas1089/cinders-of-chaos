-- The Keeper of Trials (server/data/scripts/chaos/TRIALS.md): greeting him opens the list of the three difficulties of
-- your vocation's trial; the answer (enter a tier) arrives in data/scripts/chaos/trials.lua (CreatureEvent
-- "ChaosTrialModal"), which checks everything again. The same door opens from the Trials button of the passive tree window.
-- This script runs in the NPC's own Lua state and only reads the player's storages.
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

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTrialsCore then
	dofile("data/scripts/chaos/trials_core.lua")
end
local M = ChaosTrialsCore
-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
end

local function openWindow(player)
	local cfg = M.cfg()
	local voc = player:getVocation():getId()
	local fam = M.family(voc)
	if not fam then
		return false
	end
	local tier = M.clearedTier(math.max(0, player:getStorageValue(cfg.storage.tierBase + voc)))
	local lang = ChaosI18n.langOf(player)
	local lines, names = {}, {}
	for i, t in ipairs(cfg.tiers) do
		local problem = M.enterProblem(i, player:getLevel(), tier, os.time(), player:getStorageValue(cfg.storage.cooldown), lang)
		names[#names + 1] = string.format("%s%s", t.name, i <= tier and ChaosI18n.text(lang, " (cleared)") or "")
		lines[#lines + 1] = ChaosI18n.text(lang, "%s: level %d, %d minutes, %d lives%s", t.name, t.minLevel, math.floor(t.time / 60), t.lives,
			problem and (" - " .. problem) or "")
	end
	local text = ChaosI18n.text(lang, "%s\n\n%s\n\nYou go alone. A fall costs a life, not your experience or items; nothing is lost if you fail. The first clear of each difficulty opens a pair of special nodes for your vocation (choose them in the passive tree window, Trials).\n\n%s",
		fam.name, ChaosI18n.text(lang, fam.story), table.concat(lines, "\n"))
	if not ModalWindow then
		return false
	end
	local w = ModalWindow(cfg.modalId, ChaosI18n.text(lang, "Trial of the %s", player:getVocation():getName()), text)
	for i, c in ipairs(names) do
		w:addChoice(i, c)
	end
	w:addButton(1, ChaosI18n.text(lang, "Enter"))
	w:addButton(2, ChaosI18n.text(lang, "Not yet"))
	w:setDefaultEnterButton(1)
	w:setDefaultEscapeButton(2)
	w:sendToPlayer(player)
	return true
end

-- no window on the greeting: the Keeper stands near the Ascendant Oracle, a "hi" greets both, and the client shows only
-- one modal window at a time, so a window opened here hid the Oracle's Choice. The window opens on {trials}.
local function greetCallback(cid)
	return true
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	local text = msg:lower()
	if player and (text:find("trial", 1, true) or text:find("node", 1, true) or text:find("door", 1, true)) then
		if not openWindow(player) then
			npcHandler:say(t(cid, "The doors are closed to you for now."), cid)
		else
			npcHandler:say(t(cid, "Choose your difficulty. Each cleared difficulty opens a pair of special nodes for your vocation."), cid)
		end
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_GREET, greetCallback)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away lines in the player's language
npcHandler:addModule(FocusModule:new())

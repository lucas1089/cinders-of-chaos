-- The Keeper of Trials (server/data/scripts/chaos/TRIALS.md): greeting him opens the list of the three difficulties of
-- your vocation's trial; the answer (enter a tier) arrives in data/scripts/chaos/trials.lua (CreatureEvent
-- "ChaosTrialModal"), which checks everything again. The same door opens from the Trials button of the passive tree window.
-- This script runs in the NPC's own Lua state and only reads the player's storages.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTrialsCore then
	dofile("data/scripts/chaos/trials_core.lua")
end
local M = ChaosTrialsCore

local function openWindow(player)
	local cfg = M.cfg()
	local voc = player:getVocation():getId()
	local fam = M.family(voc)
	if not fam then
		return false
	end
	local tier = M.clearedTier(math.max(0, player:getStorageValue(cfg.storage.tierBase + voc)))
	local lines, names = {}, {}
	for i, t in ipairs(cfg.tiers) do
		local problem = M.enterProblem(i, player:getLevel(), tier, os.time(), player:getStorageValue(cfg.storage.cooldown))
		names[#names + 1] = string.format("%s%s", t.name, i <= tier and " (cleared)" or "")
		lines[#lines + 1] = string.format("%s: level %d, %d minutes, %d lives%s", t.name, t.minLevel, math.floor(t.time / 60), t.lives,
			problem and (" - " .. problem) or "")
	end
	local text = string.format("%s\n\n%s\n\nYou go alone. A fall costs a life, not your experience or items; nothing is lost if you fail. "
		.. "The first clear of each difficulty opens a pair of special nodes for your vocation (choose them in the passive tree window, Trials).\n\n%s",
		fam.name, fam.story, table.concat(lines, "\n"))
	if not ModalWindow then
		return false
	end
	local w = ModalWindow(cfg.modalId, "Trial of the " .. player:getVocation():getName(), text)
	for i, c in ipairs(names) do
		w:addChoice(i, c)
	end
	w:addButton(1, "Enter")
	w:addButton(2, "Not yet")
	w:setDefaultEnterButton(1)
	w:setDefaultEscapeButton(2)
	w:sendToPlayer(player)
	return true
end

local function greetCallback(cid)
	local player = Player(cid)
	if player and M.cfg().enabled and M.family(player:getVocation():getId()) then
		openWindow(player)
	end
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
			npcHandler:say("The doors are closed to you for now.", cid)
		else
			npcHandler:say("Choose your difficulty. Each cleared difficulty opens a pair of special nodes for your vocation.", cid)
		end
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_GREET, greetCallback)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())

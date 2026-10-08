-- The Ascendant Oracle (docs/CLASSES.md "Ascension quest"): the Calling, the Proof's progress, the door to the Trial
-- and the Choice. This script runs in the NPC's own Lua state: it reads and writes the quest storages and opens the
-- modal windows; the answers (enter the Trial, choose, confirm) are handled and checked again by
-- data/scripts/chaos/ascension_quest.lua. Rules and texts: ascension_quest_core.lua, settings: ascension_quest_config.lua.
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
if not ChaosAscensionQuestCore or not ChaosAscensionQuestCore.sendConfirmModal then
	dofile("data/scripts/chaos/ascension_quest_core.lua")
end
local Q = ChaosAscensionQuestCore

local PROMOTION = "The old rites of promotion are broken; no king or guild can grant what must be earned. "
	.. "At level %d, walk the road of {ascension} with me."

local function nameOf(id)
	local v = Vocation(id)
	return v and v:getName() or tostring(id)
end

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function storage()
	return Q.cfg().storage
end

local function stageOf(player)
	return Q.stage(player:getStorageValue(storage().stage))
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
	local minLevel = Chaos.classes.ascension.minLevel
	if has(text, "promot") then
		npcHandler:say(string.format(PROMOTION, minLevel), cid)
		return true
	end
	local voc = player:getVocation():getId()
	local word = Q.choiceInText(voc, text)
	if not word and not has(text, "ascen", "quest", "calling", "path", "proof", "trial", "choice", "choose", "mission", "task") then
		return false
	end
	if not Q.cfg().enabled then
		npcHandler:say("The veil is closed for now. Come back later.", cid)
		return true
	end
	local ok, _, why = Q.eligibility(voc, player:getLevel())
	if not ok then
		npcHandler:say(why, cid)
		return true
	end
	local base = Q.baseOf(voc)
	local stage = stageOf(player)
	if stage == Q.STAGE.NONE then
		-- stage 1, the Calling
		player:setStorageValue(storage().stage, Q.STAGE.PROOF)
		player:setStorageValue(storage().proof, 0)
		npcHandler:say({
			"You hear it too, then: the Calling. " .. Q.callingText(nameOf(voc), base, nameOf),
			"Before you choose, prove that you are worth a road at all. " .. Q.proofText(0),
			"When your strength is proven, I will open the {trial} for you. Ask me about your {ascension} at any time."
		}, cid)
	elseif stage == Q.STAGE.PROOF then
		npcHandler:say(Q.proofText(player:getStorageValue(storage().proof)) .. string.format(
			" Only beasts of level %d and above are worthy of you.", Q.minMonsterLevel(player:getLevel())), cid)
	elseif stage == Q.STAGE.TRIAL then
		local wait = player:getStorageValue(storage().cooldown) - os.time()
		if wait > 0 then
			npcHandler:say("You are still bleeding from your last attempt. Return in " .. Q.formatWait(wait) .. ".", cid)
		else
			local g = Q.guardianFor(base)
			npcHandler:say(string.format("Your strength is proven. Beyond the veil waits the %s. %s Step through when you are ready.",
				g.name, g.hint or ""), cid)
			Q.sendTrialModal(player, base)
		end
	else
		-- stage 4, the Choice (also a character the store's Vocation Change took back to the base class)
		if word then
			local id, reason = Q.validateChoice(voc, word, stage)
			if not id then
				npcHandler:say(reason, cid)
			else
				npcHandler:say("So you have chosen. Confirm it, and it is done.", cid)
				Q.sendConfirmModal(player, id, word, nameOf(id))
			end
		else
			npcHandler:say("The Trial is behind you. Now choose. " .. Q.callingText(nameOf(voc), base, nameOf), cid)
			Q.sendChoiceModal(player, base, nameOf)
		end
	end
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())

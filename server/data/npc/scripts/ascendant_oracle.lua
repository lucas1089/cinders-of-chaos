-- The Ascendant Oracle (docs/CLASSES.md "Ascension quest"): the Calling, the Proof's progress, the door to the Trial
-- and the Choice. This script runs in the NPC's own Lua state: it reads and writes the quest storages and opens the
-- modal windows; the answers (enter the Trial, choose, confirm) are handled and checked again by
-- data/scripts/chaos/ascension_quest.lua. Rules and texts: ascension_quest_core.lua, settings: ascension_quest_config.lua.
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
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosAscensionQuestCore or not ChaosAscensionQuestCore.sendConfirmModal then
	dofile("data/scripts/chaos/ascension_quest_core.lua")
end
local Q = ChaosAscensionQuestCore
-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
local L = ChaosI18n.langOf
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
end

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
		npcHandler:say(t(cid, PROMOTION, minLevel), cid)
		return true
	end
	local voc = player:getVocation():getId()
	local word = Q.choiceInText(voc, text)
	if not word and not has(text, "ascen", "quest", "calling", "path", "proof", "trial", "choice", "choose", "mission", "task") then
		return false
	end
	if not Q.cfg().enabled then
		npcHandler:say(t(cid, "The veil is closed for now. Come back later."), cid)
		return true
	end
	local lang = L(player)
	local ok, _, why = Q.eligibility(voc, player:getLevel(), lang)
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
			t(cid, "You hear it too, then: the Calling. %s", Q.callingText(nameOf(voc), base, nameOf, lang)),
			t(cid, "Before you choose, prove that you are worth a road at all. %s", Q.proofText(0, lang)),
			t(cid, "When your strength is proven, I will open the {trial} for you. Ask me about your {ascension} at any time.")
		}, cid)
	elseif stage == Q.STAGE.PROOF then
		npcHandler:say(Q.proofText(player:getStorageValue(storage().proof), lang) .. t(cid,
			" Only beasts of level %d and above are worthy of you.", Q.minHuntingLevel(player:getLevel())), cid)
	elseif stage == Q.STAGE.TRIAL then
		local wait = player:getStorageValue(storage().cooldown) - os.time()
		if wait > 0 then
			npcHandler:say(t(cid, "You are still bleeding from your last attempt. Return in %s.", Q.formatWait(wait, lang)), cid)
		else
			local g = Q.guardianFor(base)
			npcHandler:say(t(cid, "Your strength is proven. Beyond the veil waits the %s. %s Step through when you are ready.",
				g.name, g.hint and t(cid, g.hint) or ""), cid)
			Q.sendTrialModal(player, base, lang)
		end
	else
		-- stage 4, the Choice (also a character the store's Vocation Change took back to the base class)
		if word then
			local id, reason = Q.validateChoice(voc, word, stage, lang)
			if not id then
				npcHandler:say(reason, cid)
			else
				npcHandler:say(t(cid, "So you have chosen. Confirm it, and it is done."), cid)
				Q.sendConfirmModal(player, id, word, nameOf(id), lang)
			end
		else
			npcHandler:say(t(cid, "The Trial is behind you. Now choose. %s", Q.callingText(nameOf(voc), base, nameOf, lang)), cid)
			Q.sendChoiceModal(player, base, nameOf, lang)
		end
	end
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- greet, farewell and walk away in the player's language
npcHandler:addModule(FocusModule:new())

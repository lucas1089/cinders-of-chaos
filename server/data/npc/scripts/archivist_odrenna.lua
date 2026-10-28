-- Archivist Odrenna (server/README.md "Line spell quests"): starts the three spell quests of the character's line, tells how
-- the hunt stands and opens the question for the trial. This script runs in the NPC's own Lua state: it reads and writes the
-- quest storages and opens the modal window; the answer (enter the trial) is handled and checked again by
-- data/scripts/chaos/spellquest.lua. Rules and texts: spellquest_core.lua, settings: spellquest_config.lua.
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
if not ChaosSpellQuestCore or not ChaosSpellQuestCore.sendTrialModal then
	dofile("data/scripts/chaos/spellquest_core.lua")
end
local Q = ChaosSpellQuestCore
-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
local L = ChaosI18n.langOf
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

-- raw storage values of every quest
local function read(player)
	local q = {}
	for n = 1, Q.count() do
		local k = Q.keys(n)
		q[n] = {step = player:getStorageValue(k.step), kills = player:getStorageValue(k.kills),
			fragments = player:getStorageValue(k.fragments), mask = player:getStorageValue(k.lines)}
	end
	return q
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
	if not has(text, "spell", "quest", "hunt", "fragment", "trial", "archive", "mission", "task", "learn") then
		return false
	end
	if not Q.cfg().enabled then
		npcHandler:say(t(cid, "The archive is closed for now. Come back later."), cid)
		return true
	end
	local lang = L(player)
	local voc = player:getVocation():getId()
	local q = read(player)
	local n, step, code = Q.current(voc, player:getLevel(), q)
	if code == "noline" then
		npcHandler:say(t(cid, "Your path holds no spell for me to give, wanderer."), cid)
		return true
	end
	local idx = Q.lineOf(voc)
	if code == "done" then
		npcHandler:say(t(cid, "You have earned every spell of your line. The archive has nothing more for you."), cid)
		return true
	end
	local qc = Q.quest(n)
	local spell = Q.spellName(idx, n)
	if code == "level" then
		npcHandler:say(t(cid, "%s is not for you yet. Return when you have reached level %d.", spell, qc.level), cid)
		return true
	end
	local k = Q.keys(n)
	if step == Q.STEP.NONE then
		local s = Q.startState()
		player:setStorageValue(k.step, s.step)
		player:setStorageValue(k.kills, s.kills)
		player:setStorageValue(k.fragments, s.fragments)
		player:setStorageValue(k.pity, s.pity)
		npcHandler:say({
			t(cid, "The archive keeps %s, a spell of your line. It is earned, not bought.", spell),
			t(cid, "First the hunt. %s", Q.huntText(n, s, lang)),
			t(cid, "Then the trial. Ask me about your {quest} at any time.")
		}, cid)
	elseif step == Q.STEP.HUNT then
		npcHandler:say(Q.huntText(n, {kills = player:getStorageValue(k.kills), fragments = player:getStorageValue(k.fragments)}, lang), cid)
	else
		local wait = player:getStorageValue(k.cooldown) - os.time()
		if wait > 0 then
			npcHandler:say(t(cid, "The door stays shut for now. Return in %s.", Q.formatWait(wait, lang)), cid)
		else
			npcHandler:say(t(cid, "The hunt is done. %s Step through when you are ready.", Q.trialText(n, lang)), cid)
			Q.sendTrialModal(player, n, spell, lang)
		end
	end
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- greet, farewell and walk away in the player's language
npcHandler:addModule(FocusModule:new())

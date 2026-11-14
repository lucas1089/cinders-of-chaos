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

-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
end

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

-- the tales (data/scripts/chaos/tales_core.lua): a "talk" step that names this NPC is done when the character asks
-- about the tale or the Archivist here. The step's reply is said in the tale's language; the next step is named.
if not ChaosTalesCore or not ChaosTalesCore.talkTo then
	pcall(dofile, "data/scripts/chaos/tales_core.lua")
end
local function taleTalk(cid, player, msg)
	local M = ChaosTalesCore
	if not M or not M.talkTo or not M.cfg() or not faction.npc then
		return false
	end
	local s = M.plain(msg)
	if not M.asksTales(msg) and not s:find(" archivist ", 1, true) and not s:find(" maelis ", 1, true)
			and not s:find(" arquivista ", 1, true) then
		return false
	end
	local hooked
	if Chaos and Chaos.lang then
		local okL, l = pcall(Chaos.lang, player)
		hooked = okL and l or nil
	elseif ChaosI18n and ChaosI18n.langOf and ChaosI18n.langOf(player) == "pt-BR" then
		hooked = "pt" -- the stored language of this state; English stays the tales' own choice
	end
	local lang = M.lang(player:getStorageValue(M.langKey()), hooked)
	local done = M.talkTo(faction.npc.name, function(t) return player:getStorageValue(M.stateKey(t)) end,
		function(t, v)
			player:setStorageValue(M.stateKey(t), v)
			player:setStorageValue(M.countKey(t), 0)
		end)
	local ui = M.cfg().ui
	for _, d in ipairs(done) do
		npcHandler:say(M.t(d.step.reply, lang), cid)
		local nextStep = d.tale.steps[M.state(d.tale, d.state)]
		local line
		if nextStep and M.FIELD[nextStep.kind] then
			line = string.format(M.t(ui.stepNext, lang), M.t(d.tale.name, lang), M.t(nextStep.text, lang))
		else
			line = string.format(M.t(ui.stepDone, lang), M.t(d.tale.name, lang))
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, line)
	end
	return #done > 0
end

-- the main quest (O551, data/scripts/chaos/mainquest_core.lua, mainquest_config.lua): Warden Ysolde (faction "vigil") is its giver.
-- "oath" / "juramento" offers it, sets the talk flag of a step that wants one, or says what the open step asks; "door" / "porta"
-- asks for the last page (the engine side answers). Own Lua state: only the storages are touched here.
if key == "vigil" and (not ChaosMainQuestCore or not ChaosMainQuestCore.talk) then
	pcall(dofile, "data/scripts/chaos/mainquest_core.lua")
end
local function questTalk(cid, player, msg)
	local K = ChaosMainQuestCore
	local c = K and K.cfg and K.cfg()
	if key ~= "vigil" or not c or not c.enabled then
		return false
	end
	local s = " " .. msg:lower():gsub("[^%w ]", " ") .. " "
	local door = s:find(" door ", 1, true) or s:find(" porta ", 1, true) or s:find(" chamber ", 1, true) or s:find(" camara ", 1, true)
	local oath = s:find(" oath ", 1, true) or s:find(" juramento ", 1, true) or s:find(" quest ", 1, true) or s:find(" missao ", 1, true)
	if not door and not oath then
		return false
	end
	local lang = ChaosI18n.langOf and ChaosI18n.langOf(player) == "pt-BR" and "pt" or "en"
	local function get(name) return player:getStorageValue(c.storage.base + c.storage[name]) end
	local function put(name, v) player:setStorageValue(c.storage.base + c.storage[name], v) end
	local vars = {oath = "oath", juramento = "juramento", door = "door", porta = "porta"}
	local state = get("state")
	if door then
		-- the engine side (mainquest.lua sweep) reads the flag, checks the door and answers in the chat
		local name, bit = K.flagPlace(c, "door")
		if name then
			put(name, K.setBit(math.max(0, get(name)), bit))
		end
		npcHandler:say(K.fill(K.text(c.ysolde.take, lang), vars), cid)
		return true
	end
	if state < 0 or state == c.states.skipped then
		if state == c.states.skipped then
			put("state", c.states.active)
			npcHandler:say(K.fill(K.text(c.ysolde.offer, lang), vars), cid)
		else
			npcHandler:say(K.fill(K.text(c.ysolde.greet, lang), vars), cid)
		end
	elseif state == c.states.active then
		-- O553: a bring step takes the quest items of its drop step from the backpack (the items carry the key of the step and the
		-- guid of the character; a plain copy of the same stock item counts for nothing)
		local items = {held = function(stepKey) return K.heldCount(c, player, stepKey) end,
			take = function(stepKey, n) return K.takeQuestItems(c, player, stepKey, n) end}
		local r, a, b, dc = K.talk(c, get, put, items)
		local step = c.steps[get("step")]
		if r == true then
			npcHandler:say(K.fill(K.text(c.ysolde.take, lang), vars), cid)
			if dc and a and a > 0 then
				npcHandler:say(K.fill(K.text(c.ysolde.took, lang), {n = a, item = K.text(dc.item, lang)}), cid)
			end
		elseif r == "short" then
			npcHandler:say(K.fill(K.text(c.ysolde.short, lang), {held = a, target = b, item = K.text(dc.item, lang)}), cid)
		elseif step then
			vars.step = K.fill(K.text(step.title, lang), vars)
			npcHandler:say(K.fill(K.text(c.ysolde.wait, lang), vars), cid)
		end
	elseif state == c.states.done then
		npcHandler:say(K.fill(K.text(c.ysolde.done, lang), vars), cid)
	else
		npcHandler:say(K.fill(K.text(c.ysolde.veteran, lang), vars), cid)
	end
	return true
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
	local okQ, quest = pcall(questTalk, cid, player, msg)
	if okQ and quest then
		return true
	end
	local okT, talked = pcall(taleTalk, cid, player, msg)
	if okT and talked then
		return true
	end
	if has(text, "contract", "work", "task", "quartermaster", "trade", "offer", "buy", "reputation", "standing",
			"token", "deliver", "recipe", "window") then
		-- O368: the ledger opens at cfg.minLevel (factions.lua checks it again)
		if player:getLevel() < (cfg.minLevel or 1) then
			npcHandler:say(t(cid, "Come back at level %d. %s takes no oaths from the untried.", cfg.minLevel, faction.name), cid)
			return true
		end
		openWindow(player)
		npcHandler:say(t(cid, "Here is what %s asks, and what it gives. Your contracts, your standing and my stores are in the ledger. Bring %s and deliveries to me.",
			faction.name, token.plural), cid)
		return true
	elseif has(text, "lore", "who", "faction", "about") then
		npcHandler:say(t(cid, faction.lore), cid)
		return true
	elseif rival and has(text, rival.short:lower(), "rival", "enemy") then
		npcHandler:say(t(cid, "Every favour you do %s is a favour we remember, and the same is true the other way. Choose, or work twice as hard.",
			rival.name), cid)
		return true
	end
	return false
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away / trade lines in the player's language
npcHandler:addModule(FocusModule:new())

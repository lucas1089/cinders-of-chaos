-- Archivist Maelis (docs/CONTENT.md "Tales" and "Lore"): opens the list of tales (a modal window; the answers are
-- handled and checked again by data/scripts/chaos/tales.lua) and answers lore keywords from lore_data.lua, in English
-- or Brazilian Portuguese ("portugues" / "english" switch; Chaos.lang decides when the localization work adds it).
-- This script runs in the NPC's own Lua state: it reads the tale storages, writes only the language choice.
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
if not ChaosTalesCore or not ChaosTalesCore.taleView then
	dofile("data/scripts/chaos/tales_core.lua")
end
local M = ChaosTalesCore

local GREET = {
	en = "Ash on your boots, |PLAYERNAME|. I keep the {ledger}. Ask me for {tales}, or for any {lore} you fear. "
		.. "(Diga {portugues} para conversar em português.)",
	pt = "Cinza nas suas botas, |PLAYERNAME|. Eu guardo o {registro}. Peça {histórias}, ou qualquer {lenda} que você tema. "
		.. "(Say {english} to talk in English.)"
}
local LINES = {
	job = {en = "I write down what the fire gives back. Bosses, rifts, Omens. Bring me a true account and I pay for it: ask for {tales}.",
		pt = "Eu anoto o que o fogo devolve. Chefes, fendas, Presságios. Traga um relato verdadeiro e eu pago por ele: peça {histórias}."},
	lore = {en = "Ask me about any of these: %s.", pt = "Pergunte sobre qualquer um destes: %s."},
	hunt = {en = "Your map marks the hunting grounds you have walked near, with their levels. The Bestiary (Hunt > Bestiary) "
		.. "shows where each creature lives, and the Bounty Board pays for the ones at your level.",
		pt = "Seu mapa marca as áreas de caça por onde você passou, com seus níveis. O Bestiário (Caça > Bestiário) mostra onde "
		.. "cada criatura vive, e o Quadro de Recompensas paga pelas do seu nível."},
	switched = {en = "As you wish. We speak English now.", pt = "Como quiser. Agora falamos português."},
	tales = {en = "Here is what I pay for.", pt = "Eis o que eu pago."},
	nothing = {en = "I do not know that name. Ask me about {lore}, or for {tales}.",
		pt = "Não conheço esse nome. Pergunte sobre {lendas}, ou peça {histórias}."}
}

local function langOf(player)
	local hooked
	if Chaos and Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		hooked = ok and l or nil
	end
	return M.lang(player:getStorageValue(M.langKey()), hooked)
end

local function sendList(player, lang)
	if not ModalWindow then
		return false
	end
	local cfg = M.cfg()
	local v = M.listView(player:getLevel(), function(t) return player:getStorageValue(M.stateKey(t)) end, lang)
	local w = ModalWindow(cfg.modal.list, v.title, v.text)
	for i, c in ipairs(v.choices) do
		w:addChoice(i, c.label)
	end
	if #v.choices > 0 then
		w:addButton(1, M.t(cfg.ui.read, lang))
	end
	w:addButton(2, M.t(cfg.ui.close, lang))
	w:setDefaultEnterButton(#v.choices > 0 and 1 or 2)
	w:setDefaultEscapeButton(2)
	w:sendToPlayer(player)
	return true
end

local function greetCallback(cid)
	local player = Player(cid)
	if player then
		npcHandler:setMessage(MESSAGE_GREET, GREET[langOf(player)])
	end
	return true
end

local function has(text, ...)
	local s = M.plain(text)
	for _, w in ipairs({...}) do
		if s:find(" " .. w .. " ", 1, true) then
			return true
		end
	end
	return false
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player then
		return false
	end
	local switch = M.langWord(msg)
	if switch then
		player:setStorageValue(M.langKey(), M.langCode(switch))
		-- Chaos.lang wins in langOf, so the switch must reach it too (the client's next hello may set it again)
		if Chaos and Chaos.setLang then
			pcall(Chaos.setLang, player, switch == "pt" and "pt-BR" or "en")
		end
		npcHandler:say(LINES.switched[switch], cid)
		return true
	end
	local lang = langOf(player)
	if M.asksTales(msg) then
		npcHandler:say(LINES.tales[lang], cid)
		sendList(player, lang)
		return true
	end
	if has(msg, "job", "trabalho", "oficio", "name", "nome") then
		npcHandler:say(LINES.job[lang], cid)
		return true
	end
	if has(msg, "hunt", "hunting", "caca", "cacar") then
		npcHandler:say(LINES.hunt[lang], cid)
		return true
	end
	if has(msg, "chronicle", "cronica") then
		-- the Ashen Chronicle (chronicle_text.lua): NPCs run in their own Lua state, so read the data files and the
		-- global storages the server sets
		local okT, T = pcall(dofile, "data/scripts/chaos/chronicle_text.lua")
		local okC, C = pcall(dofile, "data/scripts/chaos/chronicle_config.lua")
		if okT and okC and type(T) == "table" and type(C) == "table" then
			local g = C.globalStorage
			local arc = C.arcs[Game.getStorageValue(g.season)]
			npcHandler:say(T.npcLine(arc, Game.getStorageValue(g.done), lang), cid)
			return true
		end
	end
	local e = M.loreFor(msg)
	if e then
		npcHandler:say(M.loreText(e, lang), cid)
		return true
	end
	if has(msg, "lore", "lenda", "lendas", "names", "nomes") then
		npcHandler:say(string.format(LINES.lore[lang], M.loreTopics(lang)), cid)
		return true
	end
	npcHandler:say(LINES.nothing[lang], cid)
	return true
end

npcHandler:setCallback(CALLBACK_GREET, greetCallback)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())

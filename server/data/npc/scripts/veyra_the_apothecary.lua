-- Veyra the Apothecary, the supplies seller of the hub (server/data/scripts/chaos/apothecary_config.lua, apothecary.lua;
-- server/README.md "The Apothecary"). Runs in the NPC's own Lua state. The goods and prices are the XML's shop_buyable
-- list (the potion and rune installers read it); the config adds the level of each potion tier: a buyer below it is
-- refused at the counter. Everything else is the base trade window ("trade", "buy <name>", "sell <name>").
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

local okCfg, cfg = pcall(dofile, "data/scripts/chaos/apothecary_config.lua")
if not okCfg or type(cfg) ~= "table" then
	cfg = {potions = {}}
end

-- item id -> {name, level} of the goods with a level
local gated = {}
for _, d in ipairs(cfg.decks or {}) do
	if (d.level or 0) > 0 then
		gated[d.id] = d
	end
end
for _, p in ipairs(cfg.potions or {}) do
	if (p.level or 0) > 0 then
		gated[p.id] = p
	end
end

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local text = msg:lower()
	if has(text, "buy", "sell", "trade", "offer") then
		return false -- the trade window and "buy <name>" are the shop module's
	end
	if has(text, "job", "name", "who") then
		npcHandler:say(t(cid, "Veyra, apothecary. I sell potions of every tier one at a time, the runes hunters ask for most, and rope, shovel, torch and backpack. Ask for a {trade}."), cid)
		return true
	elseif has(text, "potion", "pack", "bulk") then
		npcHandler:say(t(cid, "Health, mana and spirit draughts from the small to the supreme, each for a level. In bulk the store sells packs of one hundred for less. Ask for a {trade}."), cid)
		return true
	elseif has(text, "deck", "card") then
		npcHandler:say(t(cid, "A deck holds your cards: five in the Bronze, ten in the Silver, twenty in the Golden. Carry it, then use a card to put it in and turn it on. Ask for a {trade}."), cid)
		return true
	elseif has(text, "flask", "vial", "empty") then
		npcHandler:say(t(cid, "No potion leaves a flask now. Old empty ones I still buy, five gold each."), cid)
		return true
	end
	return false
end

-- the trade window: a potion tier above the buyer's level is refused
npcHandler:setCallback(CALLBACK_ONBUY, function(cid, itemId, subType, amount, ignoreCap, inBackpacks)
	local g = gated[itemId]
	local player = Player(cid)
	if g and player and player:getLevel() < g.level then
		npcHandler:say(t(cid, "A %s is for level %d and up, and you are not there yet.", g.name, g.level), cid)
		return false
	end
	return true
end)

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
-- no ShopModule:new() here: the XML's module_shop parameter makes NpcSystem.parseParameters (line 7) build the shop module
-- and read shop_buyable / shop_sellable into it. A module made by hand never reads them (O188: empty trade window).
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away / trade lines in the player's language
npcHandler:addModule(FocusModule:new())

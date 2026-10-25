-- Veyra the Apothecary, the supplies seller of the hub (server/data/scripts/chaos/apothecary_config.lua, apothecary.lua;
-- server/README.md "The Apothecary"). Runs in the NPC's own Lua state. The goods and prices are the XML's shop_buyable
-- list (the potion and rune installers read it); the config adds the level of each potion tier: a buyer below it is
-- refused at the counter. Everything else is the base trade window ("trade", "buy <name>", "sell <name>").
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
local pending = {} -- cid -> what she offered last (the Everfull upgrade task, O245)
function onCreatureDisappear(cid)		pending[cid] = nil	npcHandler:onCreatureDisappear(cid)			end
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

-- the Everfull flask upgrade task and the lost flask (data/lib/chaos_potions.lua, README "Potions", "Higher tiers"): the
-- same swap the store sells. All checks are the library's, run again when the player says yes.
if not ChaosPotions then pcall(dofile, "data/lib/chaos_potions.lua") end
local unpack = table.unpack or unpack

-- a whole word ("no" is not "know")
local function word(text, ...)
	local padded = " " .. text:gsub("[^%w]+", " ") .. " "
	for _, w in ipairs({...}) do
		if padded:find(" " .. w .. " ", 1, true) then
			return true
		end
	end
	return false
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
	local player = Player(cid)
	if player and ChaosPotions and ChaosPotions.upgradeOffers then
		local PT = ChaosPotions
		local ask = pending[cid]
		if ask and word(text, "no", "cancel", "never") then
			pending[cid] = nil
			npcHandler:say(t(cid, "As you wish."), cid)
			return true
		end
		if ask then
			local chosen
			if #ask.list == 1 then
				if word(text, "yes", "ok", "sure", "deal") then
					chosen = ask.list[1]
				end
			else
				for _, x in ipairs(ask.list) do
					local word = ask.kind == "restore" and x.slot or x.line
					if has(text, word) then
						chosen = x
					end
				end
			end
			if chosen then
				pending[cid] = nil
				if ask.kind == "restore" then
					local ok, why, args = PT.restore(cid, chosen.slot)
					if ok then
						npcHandler:say(t(cid, "Here is your %s again. Keep it safe.", why.name), cid)
					else
						npcHandler:say(t(cid, why, unpack(args or {})), cid)
					end
				else
					local ok, why, args = PT.upgrade(player, chosen.id, "quest")
					if ok then
						npcHandler:say(t(cid, "Done. Your flask is now an %s. Its charges are as you left them.", chosen.name), cid)
					else
						npcHandler:say(t(cid, why, unpack(args or {})), cid)
					end
				end
				return true
			end
		end
		if has(text, "upgrade", "everfull", "task", "quest") then
			local list = PT.upgradeOffers(player)
			if #list == 0 then
				pending[cid] = nil
				npcHandler:say(t(cid, "I have no upgrade for your flask now. Carry your Everfull potion, and come at level 80, 130 or 200 for the next one."), cid)
				return true
			end
			pending[cid] = {kind = "upgrade", list = list}
			if #list == 1 then
				local e = list[1]
				npcHandler:say(t(cid, "I can turn your flask into an %s, level %d. Bring me %d %s and keep your flask in your backpack, inbox or depot. Say {yes}.",
					e.name, e.level, ChaosPotionsConfig.upgrade.materials, PT.stockName(e) .. "s"), cid)
			else
				local lines = {}
				for _, e in ipairs(list) do
					lines[#lines + 1] = "{" .. e.line .. "}"
				end
				npcHandler:say(t(cid, "Your flask can go two ways, level %d: %s. Each needs %d potions of its kind and your flask. Which one?",
					list[1].level, table.concat(lines, " / "), ChaosPotionsConfig.upgrade.materials), cid)
			end
			return true
		elseif has(text, "lost", "restore", "replace") then
			local list = PT.restorable(player)
			if #list == 0 then
				npcHandler:say(t(cid, "You have lost nothing I can give back."), cid)
				return true
			end
			pending[cid] = {kind = "restore", list = list}
			if #list == 1 then
				npcHandler:say(t(cid, "I can give you back your %s for %d gold. Say {yes}.", list[1].entry.name, list[1].entry.price), cid)
			else
				npcHandler:say(t(cid, "I can give back your {health} or your {mana} flask. Which one?"), cid)
			end
			return true
		end
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

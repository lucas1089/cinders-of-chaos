-- Shared dialogue of the five service NPCs of the Halls of Services (server/data/scripts/chaos/service_npcs.lua,
-- service_npcs_config.lua, service_npcs_core.lua, service_npcs_run.lua; server/README.md "Service NPCs"). Each NPC script
-- sets SERVICE_KEY (stash, pocketboss, banker, broker, services) and runs this file. It runs in the NPC's own Lua state:
-- it opens the client window of the module (that module's extended opcode, action "npc") and answers; every action in
-- the window is checked again by the module's own script. The house broker also sells a house and runs the base
-- server's leave / sell house commands; the services clerk the familiar and web shop commands.
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
-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/service_npcs_run.lua")
local K = ChaosServiceNpcsCore
local R = ChaosServiceNpcsRun
local key = SERVICE_KEY

local function t(cid, text, ...)
	return ChaosI18n.npcText(cid, text, ...)
end

local pending = {} -- house broker: player id -> the house a "yes" buys

local function gold(n)
	return tostring(math.floor(n))
end

local ANSWERS = {}

-- ------------------------------------------------------------------ the stash keeper
ANSWERS.stash = {
	job = function(cid)
		return t(cid, "Tavish Coldhand. I keep the supply stash of every adventurer. Ask me to open your {stash}.")
	end,
	open = function(cid, player)
		R.open(player, key)
		return t(cid, "Your stash is open. Drag items onto it, or take them out. Taking out works in town only, mind you.")
	end
}

-- ------------------------------------------------------------------ the pocket boss NPC
ANSWERS.pocketboss = {
	job = function(cid)
		return t(cid, "Vessa Hollowmark. I keep the ledger of every boss: where it lives and when it returns. Ask for the {bosses}.")
	end,
	charges = function(cid)
		local ok, pb = pcall(dofile, "data/scripts/chaos/pocketboss_config.lua")
		local daily = ok and type(pb) == "table" and pb.charges and pb.charges.daily or 3
		return t(cid, "Every boss gives you %d free pocket charges a day, renewed at midnight. A charge buys a private fight. The ledger shows what you hold.", daily)
	end,
	open = function(cid, player)
		R.open(player, key)
		return t(cid, "Here is the ledger. A boss that is out of reach can be fought in a pocket of its own: the Pocket button spends a charge.")
	end
}

-- ------------------------------------------------------------------ the banker
ANSWERS.banker = {
	job = function(cid)
		return t(cid, "Cassian Auric. I keep the gold that you cannot carry. Ask to {open} your account.")
	end,
	balance = function(cid, player)
		return t(cid, "Your account holds %s gold coins.", gold(player:getBankBalance()))
	end,
	open = function(cid, player)
		R.open(player, key)
		return t(cid, "Your account is open. You can deposit, withdraw or transfer gold. Your balance is %s gold coins.",
			gold(player:getBankBalance()))
	end
}

-- ------------------------------------------------------------------ the house broker
local function houseText(cid, reason, price)
	local text = K.TEXT[reason]
	if reason == "money" then
		return t(cid, text, price or 0)
	end
	return text and t(cid, text) or t(cid, "That cannot be done now.")
end

local function townNamed(houses, text)
	local lower = text:lower()
	for _, town in ipairs(K.townCounts(houses, 99)) do
		if town.name ~= "" and lower:find(town.name:lower(), 1, true) then
			return town
		end
	end
	return nil
end

ANSWERS.broker = {
	job = function(cid)
		return t(cid, "Halvard Deedkeeper. I sell the free houses of the land and take back the ones you leave. Ask for the {list}, or say {buy} and a house name.")
	end,
	towns = function(cid)
		local houses = R.houses()
		local towns = K.townCounts(houses, R.cfg.broker.townMax)
		if #towns == 0 then
			return t(cid, "No house is free at the moment.")
		end
		local parts = {}
		for _, town in ipairs(towns) do
			parts[#parts + 1] = string.format("%s (%d)", town.name, town.free)
		end
		return t(cid, "Free houses by town: %s. Ask for the {list} of a town.", table.concat(parts, ", "))
	end,
	list = function(cid, player, msg)
		local houses = R.houses()
		local town = townNamed(houses, msg)
		if not town then
			return ANSWERS.broker.towns(cid)
		end
		local perSqm = R.perSqm()
		if not perSqm then
			return t(cid, K.TEXT.off)
		end
		local list, total = K.freeHouses(houses, town.town, R.cfg.broker.listMax, perSqm)
		local parts = {}
		for _, h in ipairs(list) do
			parts[#parts + 1] = string.format("%s (%s gold)", h.name, gold(K.price(h.tiles, perSqm)))
		end
		return t(cid, "%s has %d free houses, the cheapest: %s. Say {buy} and a name.", town.name, total, table.concat(parts, ", "))
	end,
	buy = function(cid, player, msg)
		pending[cid] = nil
		local name = K.buyName(msg)
		if not name then
			return t(cid, "Which house? Say {buy} and its name; ask for the {list} to hear the free ones.")
		end
		local houses = R.houses()
		local row, why = K.findHouse(houses, name:sub(1, R.cfg.broker.nameMax))
		if not row then
			return why == "many" and t(cid, "More than one house fits that name. Say it fully.") or t(cid, "I know no house of that name.")
		end
		local perSqm = R.perSqm()
		local price = K.price(row.tiles, perSqm or 0)
		local ok, reason = K.buyCheck({priceOn = perSqm ~= nil, premium = player:isPremium(), owner = row.owner,
			owns = R.ownsHouse(player), price = price,
			money = Chaos.totalMoney(player)})
		if not ok then
			return houseText(cid, reason, price)
		end
		pending[cid] = row.id
		return t(cid, "%s in %s costs %s gold coins, paid from your backpack and then the bank. Do you want it? Say {yes}.",
			row.name, row.townName, gold(price))
	end,
	leave = function(cid, player)
		return R.runBase(player, "leavehouse") or t(cid, "That cannot be done now.")
	end,
	sell = function(cid, player, msg)
		local who = K.afterWord(msg, {"sell"}) or ""
		who = who:gsub("^[Mm]y%s+[Hh]ouse%s*", ""):gsub("^[Tt]o%s+", "")
		if who == "" then
			return t(cid, "Say {sell} and the name of the one who buys it. Both of you must be here.")
		end
		return R.runBase(player, "sellhouse", who) or t(cid, "That cannot be done now.")
	end
}
ANSWERS.broker.open = ANSWERS.broker.towns

-- ------------------------------------------------------------------ the services clerk
local function tokens(player, storageKey)
	local n = player:getStorageValue(storageKey)
	return n > 0 and n or 0
end

ANSWERS.services = {
	job = function(cid)
		return t(cid, "Pell Ashmere. I see to your name, your class, your familiar, your plate frame and your web shop orders. Ask what you need.")
	end,
	open = function(cid, player)
		R.open(player, key)
		return t(cid, "The services are open. Name, class and frame changes are done in that window.")
	end,
	name = function(cid, player)
		R.open(player, key)
		return t(cid, "A name change takes a token from the store, and you have %d. Choose the new name in the window.",
			tokens(player, Chaos.storage.nameChangeTokens))
	end,
	vocation = function(cid, player)
		R.open(player, key)
		return t(cid, "A class change takes a token from the store, and you have %d. The window shows the free switch of an old character as well.",
			tokens(player, Chaos.storage.vocationChangeTokens))
	end,
	frame = function(cid, player)
		R.open(player, key)
		return t(cid, "Your plate frames are in the window. Pick one, or switch it off.")
	end,
	familiar = function(cid, player, msg)
		local lower = msg:lower()
		local id = "summonfamiliar"
		local param = ""
		if lower:find("level", 1, true) then
			id = "familiarlevel"
		elseif lower:find("choose", 1, true) then
			id = "choosefamiliar"
			param = K.afterWord(msg, {"choose"}) or ""
		end
		return R.runBase(player, id, param) or t(cid, "Familiars are not on this server.")
	end,
	webshop = function(cid, player)
		return R.runBase(player, "webshop") or t(cid, "The web shop is not on this server.")
	end
}

-- ------------------------------------------------------------------ the dialogue
local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player then
		return false
	end
	local text = msg:lower()
	if key == "broker" and pending[cid] then
		local id = pending[cid]
		pending[cid] = nil
		if text:find("yes", 1, true) then
			local row
			for _, h in ipairs(R.houses()) do
				if h.id == id then
					row = h
				end
			end
			if not row then
				npcHandler:say(t(cid, "That cannot be done now."), cid)
				return true
			end
			local ok, reason, price = R.buyHouse(player, row)
			if ok then
				npcHandler:say(t(cid, "%s is yours. Keep the rent in your bank, or the house returns to me.", row.name), cid)
			else
				npcHandler:say(houseText(cid, reason, price), cid)
			end
			return true
		end
		npcHandler:say(t(cid, "As you wish."), cid)
		return true
	end
	local answers = ANSWERS[key]
	local intent = K.intent(key, text)
	local answer = answers and intent and answers[intent]
	if not answer then
		return false
	end
	npcHandler:say(answer(cid, player, msg), cid)
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- the XML's greet / farewell / walk away lines in the player's language
npcHandler:addModule(FocusModule:new())

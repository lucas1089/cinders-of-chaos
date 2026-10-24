-- Prizes of base scripts into the backpack (server/README.md "Prizes into the backpack"). The glue the base scripts call
-- after tools/patch_prizes.py; rules and texts: prizes_core.lua (tests/prizes_test.lua).
--   ChaosPrizes.give(player, id, count[, charges])   a new item: the backpack (or a container in it), else the store
--        inbox ("Purse"), else the ground under the player; never an inventory slot. -> "backpack" | "store inbox" |
--        "ground" (the last place used), nil when nothing could be made
--   ChaosPrizes.stow(player, item)   an item made by the script (Game.createItem): the backpack or a container in it.
--        -> RETURNVALUE_NOERROR, nil when it did not fit (the item is left as it was)
--   ChaosPrizes.toInbox(player, item)   a worn item out of a slot no client shows: the store inbox, else the depot
--        inbox. -> "store inbox" | "inbox" | nil (nothing moved)
--   ChaosPrizes.rouletteReward(playerId, config, position, label)   the base roulettes' rewardPlayer
--   ChaosPrizes.bossPrize(player, w[, cfg])   the roulettes' gold (scaled to the level), unique chest (O148) and the
--        exercise chest of the winner's class (O151); cfg = the roulette's config (default: the Boss Roulette's)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosI18n then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPrizesCore or not ChaosPrizesCore.winner then
	dofile("data/scripts/chaos/prizes_core.lua")
end

if not ChaosBossRouletteConfig then
	ChaosBossRouletteConfig = dofile("data/scripts/chaos/boss_roulette_config.lua")
end
-- the other four roulettes (O151); ChaosRoulettePools is read by the script's actionId (K.configFor)
if not ChaosRoulettePools then
	ChaosRoulettePools = {boss = ChaosBossRouletteConfig}
	local list = {ChaosBossRouletteConfig}
	for _, name in ipairs({"exercise", "premium", "crystal"}) do
		list[#list + 1] = dofile("data/scripts/chaos/roulette_" .. name .. "_config.lua")
	end
	for _, cfg in ipairs(list) do
		for _, aid in ipairs(cfg.actionIds or {}) do
			ChaosRoulettePools[aid] = cfg
		end
	end
end

ChaosPrizes = ChaosPrizes or {}
local P = ChaosPrizes
local K = ChaosPrizesCore

local function log(msg)
	print("[ChaosPrizes] " .. msg)
end

local function noError(ret)
	return ret == true or ret == (RETURNVALUE_NOERROR or 0)
end

local function text(player, key, ...)
	if Chaos.t then
		return Chaos.t(player, key, ...)
	end
	return select("#", ...) > 0 and string.format(key, ...) or key
end

-- an item made by the script into the backpack or a container in it (the containers in the order the engine lists them)
function P.stow(player, item)
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not (bp and bp:isContainer()) then
		return nil
	end
	if noError(bp:addItemEx(item)) then
		return RETURNVALUE_NOERROR or 0
	end
	for _, c in ipairs(bp:getItems(true) or {}) do
		if c:isContainer() and noError(c:addItemEx(item)) then
			return RETURNVALUE_NOERROR or 0
		end
	end
	return nil
end

local function storeInbox(player)
	local ok, inbox = pcall(function() return player:getStoreInbox() end)
	return ok and inbox or nil
end

-- one item made by the script: the backpack, else the store inbox, else the ground
local function place(player, item)
	if P.stow(player, item) then
		return "backpack"
	end
	local inbox = storeInbox(player)
	if inbox and noError(inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)) then
		return "store inbox"
	end
	local tile = Tile(player:getPosition())
	if tile and noError(tile:addItemEx(item, FLAG_NOLIMIT or 1)) then
		return "ground"
	end
	return nil
end

local RANK = {backpack = 1, ["store inbox"] = 2, ground = 3}

function P.give(player, id, count, charges)
	id, count = tonumber(id), math.max(1, math.floor(tonumber(count) or 1))
	if not (player and id and id > 0) then
		return nil
	end
	local it = ItemType(id)
	local pieces = {}
	if charges then
		pieces[1] = {1, charges}
	elseif it:isStackable() then
		while count > 0 do
			local n = math.min(100, count)
			pieces[#pieces + 1] = {n}
			count = count - n
		end
	else
		for _ = 1, count do
			pieces[#pieces + 1] = {1}
		end
	end
	local worst
	for _, piece in ipairs(pieces) do
		local item = Game.createItem(id, piece[1])
		if not item then
			log("could not make item " .. id .. " for " .. player:getName())
			return worst
		end
		if piece[2] then
			item:setAttribute(ITEM_ATTRIBUTE_CHARGES or "charges", piece[2])
		end
		local where = place(player, item)
		if not where then
			log("no place for item " .. id .. " of " .. player:getName())
			return worst
		end
		if not worst or RANK[where] > RANK[worst] then
			worst = where
		end
	end
	if worst == "store inbox" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text(player, K.TEXT_INBOX, it:getName()))
	elseif worst == "ground" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text(player, K.TEXT_GROUND, it:getName()))
	end
	return worst
end

function P.toInbox(player, item)
	local flags = (FLAG_NOLIMIT or 1) + (FLAG_IGNOREAUTOSTACK or 0)
	local inbox = storeInbox(player)
	if inbox and item:moveTo(inbox, flags) then
		return "store inbox"
	end
	local ok, depot = pcall(function() return player:getInbox() end)
	if ok and depot and item:moveTo(depot, flags) then
		return "inbox"
	end
	return nil
end

-- the values of the roulette tile's top visible thing (an item, a creature or nothing)
local function readThing(thing)
	if not thing then
		return nil
	end
	local isItem = thing.isItem and thing:isItem() or false
	if not isItem then
		return {isItem = false}
	end
	local id = thing:getId()
	local it = ItemType(id)
	return {isItem = true, id = id, count = thing:getCount(), charges = thing.getCharges and thing:getCharges() or nil,
		showCharges = it and it:hasShowCharges() or false}
end

-- the roulette prizes that are not the tile's item (boss_roulette_config.lua, roulette_*_config.lua): crystal coins on the
-- tile are gold scaled to the winner's level, the chest is a unique of the winner's level, an exercise chest becomes the
-- one of the winner's class. true when the prize was given.
function P.bossPrize(player, w, cfg)
	cfg = cfg or ChaosBossRouletteConfig
	local e = cfg and K.entryOf(cfg, w.id)
	if not e then
		return false
	end
	if e.kind == "gold" then
		local gold = K.goldFor(cfg, w.count, player:getLevel())
		for _, st in ipairs(K.coinStacks(gold)) do
			if not P.give(player, st[1], st[2]) then
				return false
			end
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR,
			text(player, K.TEXT_GOLD, tostring(gold)))
		return true
	elseif e.kind == "unique" then
		if not (ChaosLoot and ChaosLoot.uniqueList and ChaosMakeUnique) then
			return false
		end
		local choices = K.uniqueChoices(cfg, ChaosLoot.uniqueList(), player:getLevel())
		if #choices == 0 then
			return false
		end
		local pick = choices[math.random(#choices)]
		local item = Game.createItem(pick.id, 1)
		if not item then
			return false
		end
		ChaosMakeUnique(item)
		if not place(player, item) then
			item:remove()
			return false
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text(player, K.TEXT_UNIQUE, pick.name))
		Game.broadcastMessage("The player " .. player:getName() .. " has won the unique " .. pick.name
			.. " from the " .. tostring(cfg.title or "boss") .. " roulette!", MESSAGE_EVENT_ADVANCE)
		return true
	elseif e.kind == "chest" and cfg.chests then
		if not ChaosExercise then
			dofile("data/scripts/chaos/exercise_core.lua")
		end
		local vocation = player.getVocation and player:getVocation()
		local vocId = vocation and vocation:getId()
		local id, changed = K.classChest(cfg, w.id, vocId and function(kind)
			return ChaosExercise.allowed(kind, vocId)
		end or nil, math.random)
		if not P.give(player, id, 1) then
			return false
		end
		if changed then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR,
				text(player, K.TEXT_CHEST, ItemType(id):getName()))
		end
		return true
	end
	return false
end

-- the base rewardPlayer: the prize on the winning tile goes to the player (give), the free spin storage is cleared, a
-- rare prize is broadcast as before. When the tile holds no prize any more, nothing is given and the storage stays, so
-- the next spin is free (the base's own rule for a spin that went wrong).
function P.rouletteReward(playerId, config, position, label)
	local player = Player(playerId)
	if not player then
		return false
	end
	local opts = config.rouletteOptions or {}
	local tile = position and Tile(position)
	local ground = tile and tile:getGround()
	local w = K.winner(readThing(tile and tile:getTopVisibleThing()), ground and ground:getId(), opts.ignoredItems)
	if not w then
		log(player:getName() .. ": the " .. tostring(label) .. " roulette tile held no prize; the next spin is free")
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text(player, K.TEXT_LOST_SPIN))
		return false
	end
	-- the gold, the unique chest and the exercise chest are worked out here (O148, O151); anything else, or a failure, is
	-- the item itself
	local poolCfg = K.configFor(ChaosRoulettePools, config, label)
	local done = poolCfg and P.bossPrize(player, w, poolCfg)
	if not done and not P.give(player, w.id, w.count, w.charges) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text(player, K.TEXT_LOST_SPIN))
		return false
	end
	if opts.rouletteStorage then
		player:setStorageValue(opts.rouletteStorage, -1)
	end
	if K.isRare(config.prizePool, w.id, opts.rareItemChance_broadcastThreshold) then
		Game.broadcastMessage("The player " .. player:getName() .. " has won " .. ItemType(w.id):getName() .. " from the "
			.. tostring(label) .. " roulette!", MESSAGE_EVENT_ADVANCE)
	end
	return true
end

return P

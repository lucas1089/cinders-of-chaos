-- commands_ui.lua: the Info & Services window (client game_chaosinfo, extended opcode ChaosOpcodes.info, JSON).
-- The players' spoken commands are gone: every one of them is reached from the client's menu. The windows of the
-- Chaos modules talk to their own scripts; the commands that only print text or take a short argument (name change,
-- vocation change, auto seller, rift keys, events, the base server's house / online / familiar commands, ...) run
-- here. Pure logic and the list of base commands: commands_ui_core.lua.
--
-- Client -> server: {action = "catalog"} -> {action = "catalog", data = {ids = {...}, vocations = "a|b"}}
--                   {action = "store"} -> {action = "store", data = {points, entries = {{id, kind, name, item,
--                       price}}, maxCount, message}}
--                   {action = "buy", id = <entry id>, count = <1..maxCount>} -> the same "store" answer, with a message
--                   {action = "services"} -> {action = "services", data = <K.servicesState>}
--                   {action = "run", page, ids = {...}, params = {...}} (params[i] goes to ids[i])
--                       -> {action = "result", data = {page, parts = {{id, text}, ...}}}
-- Chaos scripts register their command: ChaosCommands.register("rift", function(player, param) ... end)

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCommandsCore or not ChaosCommandsCore.capture or not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
local K = ChaosCommandsCore
local OPCODE = ChaosOpcodes.info or 237
local MAX_IDS = 6 -- commands per request (a page shows a few at once)

-- ChaosCommands.register(id, fn): commands_ui_core.lua. fn(player, param) shows its answer as usual (text message,
-- popup, dialog); the window catches it.
local M = ChaosCommands

-- ---------------------------------------------------------------- base server commands
local XML_PATH = "data/talkactions/talkactions.xml"
local xmlMap -- words -> script file, read once
local loaded = {} -- id -> onSay (false: not available)

local readFile = K.readFile

local function xml()
	if not xmlMap then
		xmlMap = K.parseXml(readFile(XML_PATH) or "")
	end
	return xmlMap
end

local function baseHandler(id)
	if loaded[id] == nil then
		loaded[id] = K.baseHandler(id, xml()) or false
	end
	return loaded[id] or nil
end

-- ---------------------------------------------------------------- native commands
M.register("pos", function(player)
	local p = player:getPosition()
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Your position: %d, %d, %d.", p.x, p.y, p.z))
end)

-- ---------------------------------------------------------------- ancestral store
-- Price and item come from the base store scripts (read only; K.storeEntries); the purchase is made here. The base
-- scripts' own buy path is never run: it read the wrong row (fiery_wings.lua) and took the points without a check.
local storeCache
local function store()
	if not storeCache then
		storeCache = K.storeEntries(K.ancestralStore(xml()), function(script)
			if type(script) ~= "string" or script:find("..", 1, true) then
				return nil
			end
			return readFile("data/talkactions/scripts/" .. script)
		end, function(itemId)
			local it = ItemType(itemId)
			if not it or it:getId() == 0 then
				return nil
			end
			return {name = it:getName(), clientId = it:getClientId()}
		end)
	end
	return storeCache
end

local function pointsOf(guid)
	local rows = Chaos.select("SELECT `ancestral_points` FROM `players` WHERE `id` = " .. guid, {{"ancestral_points", "n"}})
	return rows[1] and tonumber(rows[1].ancestral_points) or nil
end

local lastPoints = {} -- player id -> points last sent (answers to refused requests read no database)
-- the store answer; cached = true: the points last sent instead of a database read
local function sendStore(player, message, cached)
	local cid = player:getId()
	local points = lastPoints[cid] or 0
	if not cached then
		points = pointsOf(player:getGuid()) or 0
		lastPoints[cid] = points
	end
	Chaos.send(player, OPCODE, "store", K.storePayload(store(), points, message))
end

local buySlots = {} -- player id -> time of the last purchase (only when ratelimit.lua is missing)
local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- Buys `count` of `entry` (checked by K.validateBuy); returns the text for the player, nil for no logged-in character.
-- a logged-in character whose purchase cooldown is over (checked before any input is looked at or the database read)
local function buyAllowed(player)
	local cid, guid = player:getId(), player:getGuid()
	if not Player(cid) or not guid or guid <= 0 then
		return nil -- not (or no longer) a logged-in character: no answer
	end
	if ChaosRateLimit then
		return ChaosRateLimit.allow(player, "commands.ancestralbuy", K.STORE.buyMs)
	end
	return K.throttle(buySlots, cid, nowMs(), K.STORE.buyMs)
end

local function buyEntry(player, entry, count)
	local guid = player:getGuid()
	local cost = entry.price * count
	local before = pointsOf(guid)
	if not before then
		return Chaos.t(player, "The purchase failed. Try again.")
	end
	if before < cost then
		return Chaos.t(player, "You need %d Ancestral Points; you have %d.", cost, before)
	end
	if ItemType(entry.itemId):getWeight(count) > player:getFreeCapacity() then
		return Chaos.t(player, "You do not have enough capacity.")
	end
	-- the WHERE keeps the points from going below zero even if they changed since the read
	db.query("UPDATE `players` SET `ancestral_points` = `ancestral_points` - " .. cost .. " WHERE `id` = " .. guid ..
		" AND `ancestral_points` >= " .. cost)
	if pointsOf(guid) ~= before - cost then
		return Chaos.t(player, "The purchase failed. Try again.")
	end
	local given = 0
	for _ = 1, count do
		if not player:addItem(entry.itemId, 1, false) then
			break
		end
		given = given + 1
	end
	if given < count then
		local back = (count - given) * entry.price
		db.query("UPDATE `players` SET `ancestral_points` = `ancestral_points` + " .. back .. " WHERE `id` = " .. guid)
		print(string.format("[chaos ancestral store] %s: %d of %dx %s given, %d points returned", player:getName(),
			given, count, entry.name, back))
		if given == 0 then
			return Chaos.t(player, "No room in your backpack: your %d Ancestral Points were returned.", back)
		end
		return Chaos.t(player, "Bought %dx %s; no room for the rest: %d Ancestral Points returned.", given, entry.name, back)
	end
	print(string.format("[chaos ancestral store] %s bought %dx %s (%d) for %d points", player:getName(), count,
		entry.name, entry.itemId, cost))
	return Chaos.t(player, "Bought %dx %s for %d Ancestral Points.", count, entry.name, cost)
end

-- the window's Buy button: {action = "buy", id = <entry id>, count = <1..maxCount>}
local function buyRequest(player, msg)
	local allowed = buyAllowed(player)
	if allowed == nil then
		return
	end
	if not allowed then
		sendStore(player, Chaos.t(player, "Wait a moment between purchases."), true)
		return
	end
	local entry, count = K.validateBuy(store(), msg.id, msg.count)
	if not entry then
		sendStore(player, count == "count" and Chaos.t(player, "Choose between 1 and %d.", K.STORE.maxCount) or
			Chaos.t(player, "That item is not in the store."), true)
		return
	end
	local text = buyEntry(player, entry, count)
	if text and Player(player:getId()) then
		sendStore(player, text)
	end
end

-- ---------------------------------------------------------------- Services page state
local FAMILIAR_LEVEL = 200 -- the base familiar script answers only from this level (pet_system.lua)
local function servicesState(player)
	local st = Chaos.storage
	local facts = {
		nameTokens = player:getStorageValue(st.nameChangeTokens),
		vocationTokens = player:getStorageValue(st.vocationChangeTokens),
		level = player:getLevel(),
		familiarLevel = FAMILIAR_LEVEL,
	}
	local freeKey = Chaos.classes and Chaos.classes.storage and Chaos.classes.storage.freeSwitch
	local free = freeKey and player:getStorageValue(freeKey) or -1
	if free > 0 and Vocation(free) then
		facts.freeSwitch = Vocation(free):getName()
	end
	local NP = ChaosNewPlayer
	if NP and NP.inTutorial and NP.key then
		facts.inTutorial = NP.inTutorial(player:getStorageValue(NP.key("stage"))) == true
	end
	local SC = ChaosShopCore
	if SC and SC.FRAMES and SC.frameStorage then
		facts.frames = {}
		local active = st.shopFrameActive and player:getStorageValue(st.shopFrameActive) or 0
		for i, name in ipairs(SC.FRAMES) do
			local key = SC.frameStorage(st, i)
			if key and player:getStorageValue(key) > 0 then
				facts.frames[#facts.frames + 1] = name
				if i == active then
					facts.activeFrame = name
				end
			end
		end
	end
	local web = K.BASE.webshop
	if web and readFile(web.file) then
		local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM `znote_shop_orders` WHERE `account_id` = " ..
			player:getAccountId(), {{"n", "n"}})
		facts.webshopOrders = rows[1] and rows[1].n or nil
	end
	return K.servicesState(facts)
end

-- ---------------------------------------------------------------- catalog
local function catalog()
	local ids = {}
	for id in pairs(M.handlers) do
		ids[#ids + 1] = id
	end
	for id, def in pairs(K.BASE) do
		local present = def.kind == "xml" and xml()[def.words] ~= nil or def.kind == "rev" and readFile(def.file) ~= nil
		if present then
			ids[#ids + 1] = id
		end
	end
	if #store() > 0 then
		ids[#ids + 1] = "ancestralstore"
	end
	table.sort(ids)
	local words = Chaos.shopServices and Chaos.shopServices.vocationWords or ""
	return {ids = ids, vocations = words}
end

-- ---------------------------------------------------------------- run
local function returnMessage(value)
	if Game and Game.getReturnMessage then
		return Game.getReturnMessage(value)
	end
	return nil
end

-- runs one command; returns the text it showed (nil: unknown id)
local function run(player, id, param)
	if type(id) ~= "string" then
		return nil
	end
	local max = K.PARAM[id]
	param = max and K.cleanParam(param, max) or ""
	if param == "" and K.SELF[id] then
		param = player:getName()
	end
	local fn, words = M.handlers[id], nil
	local chaos = fn ~= nil
	if not fn then
		if id == "ancestralstore" then
			-- the old "group, n" param: bought here (buyEntry), one piece; the base script is never run
			local entry = K.entryByParam(store(), param)
			if not entry then
				return nil
			end
			local allowed = buyAllowed(player)
			if allowed == nil then
				return nil
			end
			return allowed and buyEntry(player, entry, 1) or Chaos.t(player, "Wait a moment between purchases.")
		elseif K.BASE[id] then
			fn = baseHandler(id)
			words = K.BASE[id].words
		else
			return nil
		end
	end
	if not fn then
		return "This is not available on this server."
	end
	local lines, restore = K.capture(Player, player:getId(), function(p) return p.getId and p:getId() end, returnMessage)
	local ok, err = pcall(function()
		if chaos then
			fn(player, param)
		else
			fn(player, words or "", param)
		end
	end)
	restore()
	if not ok then
		print("[chaos commands] " .. id .. ": " .. tostring(err))
	end
	if not chaos then
		-- base server texts: a few read better another way (K.REWRITE), then in the player's language
		for i, line in ipairs(lines) do
			if K.REWRITE[line] then
				lines[i] = Chaos.t(player, K.REWRITE[line])
			end
		end
	end
	return K.joinLines(lines, ok and "Done." or "Something went wrong.")
end

local login = CreatureEvent("ChaosCommandsLogin")
function login.onLogin(player)
	lastPoints[player:getId()] = nil
	player:registerEvent("ChaosCommandsExtended")
	return true
end
login:type("login")
login:register()

local ext = CreatureEvent("ChaosCommandsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "catalog" then
		Chaos.send(player, OPCODE, "catalog", catalog())
	elseif msg.action == "store" then
		-- the Ancestral Store page: entries, prices and the player's points (a database read: rate limited)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "commands.store", 500) then
			return
		end
		sendStore(player)
	elseif msg.action == "buy" then
		buyRequest(player, msg)
	elseif msg.action == "services" then
		-- the Services page: tokens, free switch, tutorial, frames, web shop orders (a database read: rate limited)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "commands.services", 500) then
			return
		end
		Chaos.send(player, OPCODE, "services", servicesState(player))
	elseif msg.action == "run" then
		-- {action = "run", page = "<page id>", ids = {"<command id>", ...} (at most MAX_IDS), params = {"<text>", ...}}
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "commands.run", 250) then
			return
		end
		local ids = type(msg.ids) == "table" and msg.ids or {msg.id}
		local parts = {}
		for i = 1, math.min(#ids, MAX_IDS) do
			local param = type(msg.params) == "table" and msg.params[i] or (i == 1 and msg.param) or ""
			local text = run(player, ids[i], type(param) == "string" and param or "")
			if not Player(player:getId()) then
				return -- logged out by the command (name change, ...)
			end
			if text then
				parts[#parts + 1] = {id = ids[i], text = text}
			end
		end
		Chaos.send(player, OPCODE, "result", {page = type(msg.page) == "string" and msg.page:sub(1, 64) or "", parts = parts})
	end
end
ext:type("extendedopcode")
ext:register()

-- commands_ui.lua: the Info & Services window (client game_chaosinfo, extended opcode ChaosOpcodes.info, JSON).
-- The players' spoken commands are gone: every one of them is reached from the client's menu. The windows of the
-- Chaos modules talk to their own scripts; the commands that only print text or take a short argument (name change,
-- vocation change, auto seller, rift keys, events, the base server's house / online / familiar commands, ...) run
-- here. Pure logic and the list of base commands: commands_ui_core.lua.
--
-- Client -> server: {action = "catalog"} -> {action = "catalog", data = {ids = {...}, store = {...}}}
--                   {action = "run", page, ids = {...}, params = {...}} (params[i] goes to ids[i])
--                       -> {action = "result", data = {page, parts = {{id, text}, ...}}}
-- Chaos scripts register their command: ChaosCommands.register("rift", function(player, param) ... end)

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
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

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function xml()
	if not xmlMap then
		xmlMap = K.parseXml(readFile(XML_PATH) or "")
	end
	return xmlMap
end

-- loads a chunk into its own environment (LuaJIT / 5.1: setfenv; 5.2+: load with env)
local function loadInto(path, env)
	local text = readFile(path)
	if not text then
		return nil
	end
	local chunk
	if setfenv then
		chunk = loadstring(text, "@" .. path)
		if chunk then
			setfenv(chunk, env)
		end
	else
		chunk = load(text, "@" .. path, "t", env)
	end
	if not chunk then
		return nil
	end
	local ok = pcall(chunk)
	return ok
end

local function xmlHandler(words)
	local script = xml()[words]
	if not script then
		return nil
	end
	local env = setmetatable({}, {__index = _G})
	if not loadInto("data/talkactions/scripts/" .. script, env) then
		return nil
	end
	return type(rawget(env, "onSay")) == "function" and rawget(env, "onSay") or nil
end

local function revHandler(def)
	local env, talks = K.stubEnv(_G)
	if not loadInto(def.file, env) then
		return nil
	end
	local t = talks[def.index or 1]
	return t and type(rawget(t, "onSay")) == "function" and rawget(t, "onSay") or nil
end

local function baseHandler(id, words)
	if loaded[id] == nil then
		local def = K.BASE[id]
		local fn
		if def and def.kind == "xml" then
			fn = xmlHandler(def.words)
		elseif def and def.kind == "rev" then
			fn = revHandler(def)
		elseif id == "ancestralstore" and words then
			fn = xmlHandler(words)
		end
		loaded[id] = fn or false
	end
	return loaded[id] or nil
end

-- ---------------------------------------------------------------- native commands
M.register("pos", function(player)
	local p = player:getPosition()
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Your position: %d, %d, %d.", p.x, p.y, p.z))
end)

-- ---------------------------------------------------------------- catalog
local storeCache
local function store()
	if not storeCache then
		storeCache = K.ancestralStore(xml())
	end
	return storeCache
end

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
	return {ids = ids, store = store(), vocations = words}
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
			for _, e in ipairs(store()) do
				if e.param == param then
					words = "!ancestralstore " .. e.param
				end
			end
			if not words then
				return nil
			end
			loaded.ancestralstore = nil -- one script per entry
			fn = baseHandler(id, words)
			param = ""
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
	return K.joinLines(lines, ok and "Done." or "Something went wrong.")
end

local login = CreatureEvent("ChaosCommandsLogin")
function login.onLogin(player)
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

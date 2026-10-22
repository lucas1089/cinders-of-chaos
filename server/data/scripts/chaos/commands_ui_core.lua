-- commands_ui_core.lua: pure logic of the Info & Services window (client game_chaosinfo, commands_ui.lua).
-- Every player command of the server is reached from the client's menu instead of being typed in the chat:
-- the window sends {action = "run", id = <command id>, param = <text>} and commands_ui.lua runs the command's
-- function, catches the text it would have shown (text messages, cancel messages, popups, text dialogs) and sends
-- it back for the window to show.
--
-- Three kinds of command:
--   chaos   a Chaos script registers its function with ChaosCommands.register(id, fn) (fn(player, param))
--   xml     a base server talkaction from data/talkactions/talkactions.xml; server/tools/install_commands.py
--           comments the line out (the players' spoken form is gone) and this window loads its script on demand
--   rev     a base server revscript talkaction (data/scripts/**); install_commands.py takes the player words out of
--           its TalkAction(...) and this window loads the file in a sandbox to get its onSay
-- Lua 5.1 / LuaJIT and 5.3 (tests run both).

ChaosCommandsCore = ChaosCommandsCore or {}
local K = ChaosCommandsCore

-- The registry the Chaos scripts add their commands to (here, not in commands_ui.lua, so a script loaded before it can
-- register): ChaosCommands.register("rift", function(player, param) ... end). Each script starts with
--     if not ChaosCommands then dofile("data/scripts/chaos/commands_ui_core.lua") end
ChaosCommands = ChaosCommands or {}
ChaosCommands.handlers = ChaosCommands.handlers or {}
function ChaosCommands.register(id, fn)
	if type(id) == "string" and type(fn) == "function" then
		ChaosCommands.handlers[id] = fn
	end
end

-- Base server commands the window offers: id -> {kind, words (as in the base server), file (rev), index (rev: the
-- n-th TalkAction(...) call of the file), label}. A command whose script is missing is left out of the catalog.
K.BASE = {
	online = {kind = "xml", words = "!online"},
	uptime = {kind = "xml", words = "!uptime"},
	serverinfo = {kind = "xml", words = "!serverinfo"},
	resis = {kind = "xml", words = "!resis"},
	deathlist = {kind = "xml", words = "!deathlist"},
	kills = {kind = "xml", words = "!kills"},
	ancestral = {kind = "xml", words = "!ancestral"},
	buyhouse = {kind = "xml", words = "!buyhouse"},
	sellhouse = {kind = "xml", words = "!sellhouse"},
	leavehouse = {kind = "xml", words = "!leavehouse"},
	exp = {kind = "rev", words = "!exp", file = "data/scripts/customs/actions/double_exp_talkaction.lua", index = 1},
	deck = {kind = "rev", words = "!deck", file = "data/scripts/customs/deck_system/deck_system.lua", index = 1},
	webshop = {kind = "rev", words = "!shop", file = "data/scripts/customs/znote/shopsystem_talkaction.lua", index = 1},
	summonfamiliar = {kind = "rev", words = "!summonfamiliar", file = "data/scripts/customs/pet_system/pet_system.lua", index = 1},
	familiarlevel = {kind = "rev", words = "!familiarlevel", file = "data/scripts/customs/pet_system/pet_system.lua", index = 2},
	choosefamiliar = {kind = "rev", words = "!choosefamiliar", file = "data/scripts/customs/pet_system/pet_system.lua", index = 3},
}

-- Commands whose param is free text typed in the window (the others take none or a fixed choice).
K.PARAM = {changename = 64, changevocation = 32, ascend = 32, sellhouse = 40, ancestralstore = 12,
	deathlist = 30, plateframe = 16} -- plateframe: a frame name (shop.lua; without it the frame buttons did nothing)
-- Commands that take a character name and mean the player's own when none is given.
K.SELF = {deathlist = true}

-- One <talkaction .../> line of talkactions.xml (commented out or not) -> words, script; nil for any other line.
function K.parseXmlLine(line)
	if type(line) ~= "string" then
		return nil
	end
	local tag = line:match("<talkaction%s+(.-)/>")
	if not tag then
		return nil
	end
	local words = tag:match('words%s*=%s*"([^"]*)"')
	local script = tag:match('script%s*=%s*"([^"]*)"')
	if not words or not script then
		return nil
	end
	return words, script
end

-- Every talkaction of the XML text: {words -> script} (a line with "a;b" gives both words).
function K.parseXml(text)
	local map = {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		local words, script = K.parseXmlLine(line)
		if words then
			for w in words:gmatch("[^;]+") do
				map[w] = script
			end
		end
	end
	return map
end

-- "fiery_wings.lua" -> "Fiery Wings"
function K.label(script)
	local base = tostring(script or ""):gsub("%.lua$", ""):gsub("^.*/", "")
	return (base:gsub("_", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- The ancestral store entries of the XML map: list sorted by entry number of
-- {id = 1, param = "2, 1", label = "Fiery Wings", group = 2, script = "fiery_wings.lua"}. An entry number used twice
-- keeps its first line (the window buys by id).
function K.ancestralStore(map)
	local list = {}
	for words, script in pairs(map or {}) do
		local a, b = words:match("^!ancestralstore%s+(%d+)%s*,%s*(%d+)$")
		if a then
			list[#list + 1] = {param = a .. ", " .. b, label = K.label(script), group = tonumber(a), id = tonumber(b),
				script = script}
		end
	end
	table.sort(list, function(x, y)
		if x.id ~= y.id then
			return x.id < y.id
		end
		return x.param < y.param
	end)
	local out, seen = {}, {}
	for _, e in ipairs(list) do
		if not seen[e.id] then
			seen[e.id] = true
			out[#out + 1] = e
		end
	end
	return out
end

-- ---------------------------------------------------------------- ancestral store (bought here, not by the base scripts)
-- The base server's store scripts (data/talkactions/scripts/<entry>.lua) only hold the price and the item: their own
-- buy path read the points of the wrong row (fiery_wings.lua: the account id as a player id) and took the points with
-- an unconditional UPDATE after a separate read. This window reads price and item from each script and buys itself.
K.STORE = {
	buyMs = 1000,       -- one purchase a second per player
	maxCount = 10,      -- pieces per purchase
	maxPrice = 1000000, -- a parsed price above this is a broken script: the entry is left out
	maxEntries = 64,    -- keeps the store answer far below the 8192-byte extended opcode limit
}
-- entry group of the XML (the comments of talkactions.xml) -> what it gives
K.STORE_KIND = {[1] = "Aura", [2] = "Wings", [3] = "Exercise Chest"}

-- price and item id of one base store script, or nil
function K.parseStoreScript(text)
	if type(text) ~= "string" then
		return nil
	end
	local price = tonumber(text:match("ITEM_PRICE%s*=%s*(%d+)"))
	local item = tonumber(text:match("ItemType%(%s*(%d+)%s*%)"))
	if not price or not item or price < 1 or price > K.STORE.maxPrice or item < 100 or item > 65535 then
		return nil
	end
	return price, item
end

-- The store entries with price and item: entries of K.ancestralStore, readScript(script) -> text of the script,
-- itemInfo(itemId) -> {name, clientId} or nil (an item this server does not have). Entries that do not parse are left out.
function K.storeEntries(list, readScript, itemInfo)
	local out = {}
	for _, e in ipairs(list or {}) do
		if #out >= K.STORE.maxEntries then
			break
		end
		local price, itemId = K.parseStoreScript(readScript(e.script))
		local info = itemId and itemInfo(itemId)
		if price and info then
			out[#out + 1] = {id = e.id, param = e.param, group = e.group, kind = K.STORE_KIND[e.group] or "Other",
				label = e.label, name = info.name or e.label, itemId = itemId, clientId = info.clientId or 0, price = price}
		end
	end
	return out
end

-- A strict whole number from client input in [lo, hi], or nil (no floats, no strings with extra text, no NaN/inf).
function K.wholeNumber(value, lo, hi)
	if type(value) == "string" then
		if not value:match("^%s*%d+%s*$") then
			return nil
		end
		value = tonumber(value)
	end
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	if value < lo or value > hi then
		return nil
	end
	return value
end

-- A purchase request {id, count} against the entries: entry, count, cost or nil, reason ("id", "count").
-- A missing count is 1.
function K.validateBuy(entries, id, count)
	local n = K.wholeNumber(id, 1, 1000000)
	local entry
	for _, e in ipairs(entries or {}) do
		if n and e.id == n then
			entry = e
			break
		end
	end
	if not entry then
		return nil, "id"
	end
	if count == nil then
		count = 1
	end
	local c = K.wholeNumber(count, 1, K.STORE.maxCount)
	if not c then
		return nil, "count"
	end
	return entry, c, entry.price * c
end

-- the entry a legacy param ("2, 1") names
function K.entryByParam(entries, param)
	for _, e in ipairs(entries or {}) do
		if e.param == param then
			return e
		end
	end
	return nil
end

-- The store as sent to the client: points and entries without the server-only fields.
function K.storePayload(entries, points, message)
	local list = {}
	for _, e in ipairs(entries or {}) do
		list[#list + 1] = {id = e.id, kind = e.kind, name = e.name, item = e.clientId, price = e.price}
	end
	return {points = math.max(0, math.floor(tonumber(points) or 0)), entries = list, maxCount = K.STORE.maxCount,
		message = message}
end

-- per-player throttle when ratelimit.lua is missing: true when allowed (records the time)
function K.throttle(slots, id, now, ms)
	local last = slots[id]
	if last and now >= last and now - last < ms then
		return false
	end
	slots[id] = now
	return true
end

-- ---------------------------------------------------------------- texts of base commands
-- Lines of base server commands shown with another text (the original text is the key).
K.REWRITE = {
	["You didn't have any current Double EXP enhancement."] = "No Double EXP active.",
}
function K.rewrite(lines)
	for i, line in ipairs(lines or {}) do
		lines[i] = K.REWRITE[line] or line
	end
	return lines
end

-- ---------------------------------------------------------------- Services status
-- The state the Services page uses to enable its buttons. facts: nameTokens, vocationTokens (storage values, -1 =
-- none), freeSwitch (vocation name or nil), inTutorial, inBossRoom (a running boss room: Leave Boss Room), level, familiarLevel, webshopOrders (nil = unknown),
-- frames (owned frame names), activeFrame (name or nil).
function K.servicesState(facts)
	local f = facts or {}
	local frames = {}
	for _, name in ipairs(f.frames or {}) do
		if type(name) == "string" then
			frames[#frames + 1] = name
		end
	end
	local level = tonumber(f.level) or 0
	local need = tonumber(f.familiarLevel) or 0
	return {
		nameTokens = math.max(0, tonumber(f.nameTokens) or 0),
		vocationTokens = math.max(0, tonumber(f.vocationTokens) or 0),
		freeSwitch = type(f.freeSwitch) == "string" and f.freeSwitch or "",
		inTutorial = f.inTutorial == true,
		inBossRoom = f.inBossRoom == true,
		familiarReady = level >= need,
		familiarLevel = need,
		webshopOrders = f.webshopOrders == nil and -1 or math.max(0, tonumber(f.webshopOrders) or 0),
		frames = frames,
		activeFrame = type(f.activeFrame) == "string" and f.activeFrame or "",
	}
end

-- Cleans the window's text field: trimmed, single line, at most `max` characters; "" when nothing is left.
function K.cleanParam(param, max)
	local s = tostring(param or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if max and #s > max then
		s = s:sub(1, max)
	end
	return s
end

-- Collects the text a command shows while it runs. `methods` is the class table the player's methods live in
-- (Player in the server; a plain table in the tests); `id` the player's creature id. Returns the list of lines and a
-- restore function (always call it, also after an error).
local CAUGHT = {
	sendTextMessage = 2,   -- (self, type, text, ...)
	sendCancelMessage = 1, -- (self, text or return value)
	popupFYI = 1,          -- (self, text)
	showTextDialog = 2,    -- (self, item id, text, ...)
}

function K.capture(methods, id, getId, returnMessage)
	local lines, saved = {}, {}
	for name, argIndex in pairs(CAUGHT) do
		local original = methods[name]
		if type(original) == "function" then
			saved[name] = original
			methods[name] = function(self, ...)
				if getId(self) == id then
					local value = select(argIndex, ...)
					if type(value) == "number" and returnMessage then
						value = returnMessage(value)
					end
					if value ~= nil and tostring(value) ~= "" then
						lines[#lines + 1] = tostring(value)
					end
					return true
				end
				return original(self, ...)
			end
		end
	end
	local function restore()
		for name, original in pairs(saved) do
			methods[name] = original
		end
	end
	return lines, restore
end

-- The text sent back: the caught lines without repeats, or `fallback` when the command showed nothing.
function K.joinLines(lines, fallback)
	local out, seen = {}, {}
	for _, line in ipairs(lines or {}) do
		if not seen[line] then
			seen[line] = true
			out[#out + 1] = line
		end
	end
	if #out == 0 then
		return fallback or "Done."
	end
	return table.concat(out, "\n")
end

-- TalkAction stub for loading a base revscript in a sandbox: records each TalkAction(...) in call order and keeps
-- every other registrable object (CreatureEvent, Action, GlobalEvent, ...) away from the engine.
function K.stubEnv(base)
	local talks = {}
	local env = {}
	local function stub()
		return setmetatable({}, {__index = function() return function() return true end end})
	end
	env.TalkAction = function(...)
		local t = stub()
		talks[#talks + 1] = t
		return t
	end
	for _, name in ipairs({"CreatureEvent", "Action", "GlobalEvent", "MoveEvent", "EventCallback", "Spell", "Weapon"}) do
		env[name] = function() return stub() end
	end
	setmetatable(env, {__index = base})
	return env, talks
end

-- ---------------------------------------------------------------- loading the base commands
-- Shared by commands_ui.lua (the main Lua state) and the service NPCs (service_npcs_run.lua, an NPC's own state): the
-- base talkaction scripts are loaded into a sandbox and only their onSay is kept. Plain io and load: no engine API.
K.XML_PATH = "data/talkactions/talkactions.xml"

function K.readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- loads a chunk into its own environment (LuaJIT / 5.1: setfenv; 5.2+: load with env)
function K.loadInto(path, env)
	local text = K.readFile(path)
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

-- onSay of a base XML talkaction (xmlMap: K.parseXml of talkactions.xml), or nil
function K.xmlHandler(words, xmlMap)
	local script = (xmlMap or {})[words]
	if not script then
		return nil
	end
	local env = setmetatable({}, {__index = _G})
	if not K.loadInto("data/talkactions/scripts/" .. script, env) then
		return nil
	end
	return type(rawget(env, "onSay")) == "function" and rawget(env, "onSay") or nil
end

-- onSay of a base revscript talkaction (def.file, def.index-th TalkAction(...) of the file), or nil
function K.revHandler(def)
	local env, talks = K.stubEnv(_G)
	if not K.loadInto(def.file, env) then
		return nil
	end
	local t = talks[def.index or 1]
	return t and type(rawget(t, "onSay")) == "function" and rawget(t, "onSay") or nil
end

-- onSay of the base command K.BASE[id], or nil (not on this server)
function K.baseHandler(id, xmlMap)
	local def = K.BASE[id]
	if def and def.kind == "xml" then
		return K.xmlHandler(def.words, xmlMap)
	elseif def and def.kind == "rev" then
		return K.revHandler(def)
	end
	return nil
end

return K

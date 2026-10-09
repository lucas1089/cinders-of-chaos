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
K.PARAM = {changename = 64, changevocation = 32, ascend = 32, autosell = 80, sellhouse = 40, ancestralstore = 12,
	deathlist = 30}
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

-- The ancestral store entries of the XML map: sorted list of {param = "2, 1", label = "Fiery Wings", group = 2}.
function K.ancestralStore(map)
	local list = {}
	for words, script in pairs(map or {}) do
		local a, b = words:match("^!ancestralstore%s+(%d+)%s*,%s*(%d+)$")
		if a then
			list[#list + 1] = {param = a .. ", " .. b, label = K.label(script), group = tonumber(a), n = tonumber(b)}
		end
	end
	table.sort(list, function(x, y) return x.n < y.n end)
	for _, e in ipairs(list) do
		e.n = nil
	end
	return list
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

return K

-- Server category.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "server"; def.id = "server." .. def.id; ChaosAdminPending[def.id] = def end

ChaosAdmin = ChaosAdmin or {}
ChaosAdmin.startTime = ChaosAdmin.startTime or os.time() -- resets on "reload scripts"; only approximate uptime

local RELOAD_OPTIONS = {
	{value = "talkactions", label = "Talkactions"}, {value = "scripts", label = "Scripts (revscripts)"},
	{value = "monsters", label = "Monsters"}, {value = "npcs", label = "NPCs"}, {value = "config", label = "Config"},
	{value = "actions", label = "Actions"}, {value = "movements", label = "Movements"},
	{value = "creaturescripts", label = "Creaturescripts"}, {value = "globalevents", label = "Globalevents"},
	{value = "spells", label = "Spells"}, {value = "weapons", label = "Weapons"}, {value = "items", label = "Items"},
	{value = "quests", label = "Quests"}, {value = "raids", label = "Raids"}, {value = "mounts", label = "Mounts"},
	{value = "chat", label = "Chat channels"}, {value = "events", label = "Events"}, {value = "global", label = "Global lib"},
	{value = "all", label = "ALL"},
}
local RELOAD_CONST = {
	talkactions = "RELOAD_TYPE_TALKACTIONS", scripts = "RELOAD_TYPE_SCRIPTS", monsters = "RELOAD_TYPE_MONSTERS",
	npcs = "RELOAD_TYPE_NPCS", config = "RELOAD_TYPE_CONFIG", actions = "RELOAD_TYPE_ACTIONS",
	movements = "RELOAD_TYPE_MOVEMENTS", creaturescripts = "RELOAD_TYPE_CREATURESCRIPTS",
	globalevents = "RELOAD_TYPE_GLOBALEVENTS", spells = "RELOAD_TYPE_SPELLS", weapons = "RELOAD_TYPE_WEAPONS",
	items = "RELOAD_TYPE_ITEMS", quests = "RELOAD_TYPE_QUESTS", raids = "RELOAD_TYPE_RAIDS", mounts = "RELOAD_TYPE_MOUNTS",
	chat = "RELOAD_TYPE_CHAT", events = "RELOAD_TYPE_EVENTS", global = "RELOAD_TYPE_GLOBAL", all = "RELOAD_TYPE_ALL",
}

reg{id = "broadcast", name = "Broadcast", description = "Send a server-wide message to every online player.",
	params = {{name = "message", label = "Message", type = "text", max = 250},
		{name = "type", label = "Style", type = "select", default = "warning", options = {
			{value = "warning", label = "Warning (red)"}, {value = "event", label = "Event (white)"}, {value = "info", label = "Info (green)"}}}},
	handler = function(actor, p)
		local kinds = {warning = MESSAGE_STATUS_WARNING, event = MESSAGE_EVENT_ADVANCE, info = MESSAGE_INFO_DESCR}
		ChaosAdmin.broadcast(actor:getName() .. ": " .. p.message, kinds[p.type] or MESSAGE_STATUS_WARNING)
		return true, "Broadcast sent."
	end}

reg{id = "save", name = "Save server", description = "Save all players and the map state (saveServer).",
	handler = function()
		saveServer()
		return true, "Server saved."
	end}

reg{id = "reload", name = "Reload system", description = "Reload one subsystem without restarting.", dangerous = true,
	params = {{name = "system", label = "System", type = "select", options = RELOAD_OPTIONS}},
	handler = function(actor, p)
		local c = ChaosAdmin.constant(RELOAD_CONST[p.system])
		if c == nil then return false, "Reload type " .. p.system .. " is not available on this server." end
		if (p.system == "scripts" or p.system == "all") and EventCallback and EventCallback.clear then
			EventCallback:clear() -- same as data/talkactions/scripts/reload.lua, avoids duplicated callbacks
		end
		Game.reload(c)
		return true, "Reloaded " .. p.system .. "."
	end}

local MARKS = {[3600] = true, [1800] = true, [600] = true, [300] = true, [120] = true, [60] = true, [30] = true,
	[10] = true, [5] = true, [4] = true, [3] = true, [2] = true, [1] = true}

local function fmtLeft(s)
	if s >= 60 then return string.format("%d minute(s)", math.ceil(s / 60)) end
	return s .. " second(s)"
end

local function tick(token)
	local s = ChaosAdmin.shutdownState
	if not s or s.token ~= token then return end
	local left = s.at - os.time()
	if left <= 0 then
		ChaosAdmin.shutdownState = nil
		ChaosAdmin.broadcast("Server is going down now: " .. s.reason)
		saveServer()
		print("[ChaosAdmin] countdown finished: " .. s.kind .. " requested by " .. s.by)
		Game.setGameState(GAME_STATE_SHUTDOWN)
		return
	end
	if MARKS[left] and not s.said[left] then
		s.said[left] = true
		ChaosAdmin.broadcast(string.format("Server %s in %s. %s", s.kind == "restart" and "restart" or "shutdown", fmtLeft(left), s.reason))
	end
	addEvent(tick, 1000, token)
end

local function startCountdown(actor, kind, minutes, reason)
	if ChaosAdmin.shutdownState then return false, "A countdown is already running. Cancel it first." end
	local token = os.time() * 1000 + math.random(999)
	ChaosAdmin.shutdownState = {token = token, kind = kind, at = os.time() + minutes * 60, said = {}, reason = reason or "", by = actor:getName()}
	ChaosAdmin.broadcast(string.format("Server %s in %d minute(s). %s", kind == "restart" and "restart" or "shutdown", minutes, reason or ""))
	addEvent(tick, 1000, token)
	return true, string.format("%s scheduled in %d minute(s). The process exits; a supervisor must start it again for a restart.", kind, minutes)
end

reg{id = "shutdown", name = "Shutdown (countdown)", description = "Announce and shut the server down after N minutes (saves first).",
	dangerous = true,
	params = {{name = "minutes", label = "Minutes", type = "int", min = 1, max = 120, default = 5},
		{name = "reason", label = "Reason", type = "string", max = 120, required = false}},
	handler = function(actor, p) return startCountdown(actor, "shutdown", p.minutes, p.reason) end}

reg{id = "restart", name = "Restart (countdown)", description = "Same as shutdown but announced as a restart. TFS has no in-process restart, so an external supervisor (systemd, docker restart policy, loop script) must relaunch it.",
	dangerous = true,
	params = {{name = "minutes", label = "Minutes", type = "int", min = 1, max = 120, default = 5},
		{name = "reason", label = "Reason", type = "string", max = 120, required = false}},
	handler = function(actor, p) return startCountdown(actor, "restart", p.minutes, p.reason) end}

reg{id = "cancel_countdown", name = "Cancel countdown", description = "Abort a running shutdown/restart countdown.",
	handler = function(actor)
		if not ChaosAdmin.shutdownState then return false, "No countdown is running." end
		ChaosAdmin.shutdownState = nil
		ChaosAdmin.broadcast("The scheduled server shutdown has been cancelled.", MESSAGE_INFO_DESCR)
		return true, "Countdown cancelled."
	end}

reg{id = "set_state", name = "Open / close server", description = "Close the server for normal players (admins stay) or reopen it.", dangerous = true,
	params = {{name = "state", label = "State", type = "select", options = {{value = "closed", label = "Closed"}, {value = "normal", label = "Open"}}}},
	handler = function(actor, p)
		Game.setGameState(p.state == "closed" and GAME_STATE_CLOSED or GAME_STATE_NORMAL)
		return true, "Game state set to " .. p.state .. "."
	end}

reg{id = "online", name = "Online list", description = "List every online player with level, vocation and group.",
	handler = function()
		local lines = {}
		for _, pl in ipairs(Game.getPlayers()) do
			lines[#lines + 1] = string.format("%s  lvl %d  %s  group %d%s", pl:getName(), pl:getLevel(), pl:getVocation():getName(), pl:getGroup():getId(),
				Chaos.isTester and Chaos.isTester(pl) and "  [TESTER bot, not counted]" or "")
		end
		table.sort(lines)
		return true, #lines .. " player(s) online.", lines
	end}

reg{id = "stats", name = "Server stats", description = "Players, monsters, NPCs, Lua memory, approximate uptime.",
	handler = function()
		local up = os.time() - (ChaosAdmin.startTime or os.time())
		local lines = {
			"Players online: " .. (Chaos.countedPlayers and Chaos.countedPlayers() or Game.getPlayerCount()) ..
				(Chaos.countedPlayers and string.format(" (+%d tester bots)", Game.getPlayerCount() - Chaos.countedPlayers()) or ""),
			"Monsters: " .. Game.getMonsterCount(),
			"NPCs: " .. Game.getNpcCount(),
			string.format("Lua memory: %.1f MB", collectgarbage("count") / 1024),
			string.format("Uptime (since scripts loaded): %dh %dm", math.floor(up / 3600), math.floor(up % 3600 / 60)),
			"Countdown: " .. (ChaosAdmin.shutdownState and (ChaosAdmin.shutdownState.kind .. " in " .. math.max(0, ChaosAdmin.shutdownState.at - os.time()) .. "s") or "none"),
		}
		return true, "Server stats", lines
	end}

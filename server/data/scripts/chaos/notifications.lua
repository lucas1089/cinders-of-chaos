-- game_notifications (extended opcodes 79 server->client, 151 and 152 client->server)
--
-- Client contract (client/overlay/modules/game_notifications/notifications.lua):
--   server -> client, opcode 79, flat JSON (no "data" wrapper):
--     {"action":"gmBroadcast","message":"..."}
--     {"action":"taskComplete","taskName":"..","taskPoints":N,"killCount":N,
--        "monsterLookType":N (optional),"customIcon":"images/..png" (optional)}
--     {"action":"battlePassComplete","missionName":"..","expPoints":N,"monsterLookType":N (optional)}
--     {"action":"partyInvite","inviterName":"..","inviterResets":N,"element":"..","level":N}
--     {"action":"catacombFree","element":"..","level":N}
--     {"action":"achievement" (or another message kind, e.g. "sale"),"message":"title: text"}   ChaosNotify.send
--   client -> server, opcode 151, plain text (NOT json):
--     "accept_invite|<inviterName>"
--     "decline_invite|<inviterName>"
--     "start_catacomb|solo|<level>|<element>"
--   client -> server, opcode 152, plain text:  "leave_queue"
--
-- What is real here: GM broadcast (/gmnotify), accept/decline of an ordinary TFS party invite,
-- and the global ChaosNotify.* senders other scripts can call.
-- What is NOT here: the reference server has no catacomb system and no Party:onInvite hook, so
-- nothing calls partyInvite/catacombFree automatically and start_catacomb / leave_queue only
-- reach the overridable hooks ChaosNotify.onStartCatacomb / ChaosNotify.onLeaveQueue.
-- Task completion: to get the task toast, add one line to the reference tasks.lua where a task
-- is completed:  ChaosNotify.taskComplete(player, taskName, points, kills, lookType)

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

local OPCODE = ChaosOpcodes.notifications

ChaosNotify = ChaosNotify or {}

local function sendFlat(player, payload)
	player:sendExtendedOpcode(OPCODE, json.encode(payload))
end

-- player == nil broadcasts to everyone online
function ChaosNotify.gmBroadcast(player, message)
	local payload = {action = "gmBroadcast", message = tostring(message)}
	if player then
		sendFlat(player, payload)
		return
	end
	for _, online in ipairs(Game.getPlayers()) do
		sendFlat(online, payload)
	end
end

function ChaosNotify.taskComplete(player, taskName, taskPoints, killCount, monsterLookType, customIcon)
	sendFlat(player, {
		action = "taskComplete",
		taskName = tostring(taskName),
		taskPoints = tonumber(taskPoints) or 0,
		killCount = tonumber(killCount) or 0,
		monsterLookType = monsterLookType,
		customIcon = customIcon
	})
end

function ChaosNotify.battlePassComplete(player, missionName, expPoints, monsterLookType)
	sendFlat(player, {
		action = "battlePassComplete",
		missionName = tostring(missionName),
		expPoints = tonumber(expPoints) or 0,
		monsterLookType = monsterLookType
	})
end

function ChaosNotify.partyInvite(player, inviterName, inviterResets, element, level)
	sendFlat(player, {
		action = "partyInvite",
		inviterName = tostring(inviterName),
		inviterResets = tonumber(inviterResets) or 0,
		element = element and tostring(element) or "party",
		level = tonumber(level) or 0
	})
end

function ChaosNotify.catacombFree(player, element, level)
	sendFlat(player, {action = "catacombFree", element = tostring(element), level = tonumber(level) or 0})
end

-- A generic toast: send(player, title, text[, kind]). kind is one of the client's message actions (default
-- "achievement"); the client shows "title: text" under that kind's header. Used by guild.lua (guild level-up) and
-- guildwar.lua (war toasts). "sale" (header ITEM SOLD) is a listing of the player that sold: market.lua and the Orb
-- Exchange (orbexchange.lua), at once or at the next login.
local SEND_KINDS = {achievement = true, bounty = true, newplayer = true, bestiary = true, bosspoints = true,
	ascension = true, market = true, sale = true, seasonpass = true, journey = true, invasion = true}

function ChaosNotify.send(player, title, text, kind)
	if not player then
		return false
	end
	title = title ~= nil and tostring(title) or ""
	text = text ~= nil and tostring(text) or ""
	local message = text
	if title ~= "" then
		message = text ~= "" and (title .. ": " .. text) or title
	end
	if message == "" then
		return false
	end
	sendFlat(player, {action = SEND_KINDS[kind] and kind or "achievement", message = message})
	return true
end

-- Overridable hooks (no catacomb system exists in the reference server).
function ChaosNotify.onStartCatacomb(player, mode, level, element)
	player:sendCancelMessage(Chaos.t(player, "Catacombs are not available on this server."))
end

function ChaosNotify.onLeaveQueue(player)
end

local function handleInvite(player, accept, inviterName)
	local inviter = Player(inviterName)
	if not inviter then
		player:sendCancelMessage(Chaos.t(player, "The inviting player is no longer online."))
		return
	end
	local party = inviter:getParty()
	if not party then
		player:sendCancelMessage(Chaos.t(player, "That party no longer exists."))
		return
	end
	local invited = false
	for _, invitee in ipairs(party:getInvitees()) do
		if invitee:getId() == player:getId() then
			invited = true
			break
		end
	end
	if not invited then
		player:sendCancelMessage(Chaos.t(player, "You have no pending invitation from %s.", inviter:getName()))
		return
	end

	if accept then
		if player:getParty() then
			player:sendCancelMessage(Chaos.t(player, "You are already in a party."))
			return
		end
		if not party:addMember(player) then
			player:sendCancelMessage(Chaos.t(player, "You could not join the party."))
		end
	else
		party:removeInvite(player)
		inviter:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(inviter, "%s has declined your party invitation.", player:getName()))
	end
end

local LoginEvent = CreatureEvent("ChaosNotificationsLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosNotificationsExtended")
	return true
end

local ExtendedEvent = CreatureEvent("ChaosNotificationsExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if type(buffer) ~= "string" then
		return
	end
	if opcode == ChaosOpcodes.notificationsAction then
		local command, a, b, c = buffer:match("^([%w_]+)|?([^|]*)|?([^|]*)|?([^|]*)$")
		if command == "accept_invite" or command == "decline_invite" then
			if a ~= "" then
				handleInvite(player, command == "accept_invite", a)
			end
		elseif command == "start_catacomb" then
			-- a = mode ("solo"), b = level, c = element
			ChaosNotify.onStartCatacomb(player, a, tonumber(b), c)
		end
	elseif opcode == ChaosOpcodes.notificationsQueue then
		if buffer == "leave_queue" then
			ChaosNotify.onLeaveQueue(player)
		end
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

-- /gmnotify <message>  : toast to every online player (staff only)
local talk = TalkAction("/gmnotify")

function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	if param == "" then
		player:sendCancelMessage(Chaos.t(player, "Usage: /gmnotify <message>"))
		return false
	end
	ChaosNotify.gmBroadcast(nil, param)
	return false
end

talk:separator(" ")
talk:register()

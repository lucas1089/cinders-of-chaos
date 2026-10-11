-- Run from the server/ folder: luajit tests/notify_test.lua (and lua5.3; CI runs both)
-- notifications.lua against a mocked engine: the generic ChaosNotify.send(player, title, text[, kind]) that guild.lua
-- (guild level-up) and guildwar.lua (war toasts) call, next to the typed senders.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- engine mock
Chaos = {}
ChaosOpcodes = {notifications = 79, notificationsAction = 151, notificationsQueue = 152}
json = {encode = function(t) return t end} -- the payload table itself, to look at
local function event()
	local e = {}
	function e:type() end
	function e:register() end
	function e:separator() end
	return e
end
CreatureEvent, TalkAction = event, event
Game = {getPlayers = function() return {} end}

dofile("data/scripts/chaos/notifications.lua")

local function mkPlayer()
	local p = {sent = {}}
	function p:sendExtendedOpcode(op, payload)
		self.sent[#self.sent + 1] = {op = op, payload = payload}
	end
	return p
end

ok(type(ChaosNotify.send) == "function", "ChaosNotify.send exists")
local p = mkPlayer()
eq(ChaosNotify.send(p, "Guild level 5", "Your guild reached guild level 5!"), true, "sent")
eq(#p.sent, 1, "one packet")
eq(p.sent[1].op, 79, "on the notifications opcode")
eq(p.sent[1].payload.action, "achievement", "default kind: a message action the client shows")
eq(p.sent[1].payload.message, "Guild level 5: Your guild reached guild level 5!", "title and text")
ChaosNotify.send(p, "War declared", "Blades vs Shields", "invasion")
eq(p.sent[2].payload.action, "invasion", "a known kind is kept")
ChaosNotify.send(p, "X", "y", "partyInvite")
eq(p.sent[3].payload.action, "achievement", "an action with other fields falls back to the default")
ChaosNotify.send(p, "Only a title")
eq(p.sent[4].payload.message, "Only a title", "title only")
ChaosNotify.send(p, nil, "Only text")
eq(p.sent[5].payload.message, "Only text", "text only")
eq(ChaosNotify.send(p, nil, nil), false, "nothing to say: nothing sent")
eq(#p.sent, 5, "still five packets")
eq(ChaosNotify.send(nil, "a", "b"), false, "no player: false")
ChaosNotify.send(p, "While you were away", "3 items sold for 4.2M gold: a, b, c.", "sale")
eq(p.sent[6].payload.action, "sale", "the sale kind (market.lua, orbexchange.lua) is kept")
eq(p.sent[6].payload.message, "While you were away: 3 items sold for 4.2M gold: a, b, c.", "sale message")
-- the callers' guarded pcall form works
local okCall = pcall(ChaosNotify.send, p, "Guild level 6", "text")
ok(okCall and #p.sent == 7, "pcall(ChaosNotify.send, p, title, text) as guild.lua / guildwar.lua call it")

print(string.format("notify_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end

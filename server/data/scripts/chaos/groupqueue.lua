-- The Group Queue (O407; client game_groupqueue, extended opcode ChaosOpcodes.groupQueue = 160). One window where a
-- player, or a party leader, picks the arena (1v1 / 2v2 / 3v3 by party size), the battleground and a dungeon with its
-- difficulty and joins them all at once. Rules: groupqueue_core.lua (pure, tests/groupqueue_test.lua); numbers:
-- groupqueue_config.lua; overview: server/README.md "Group Queue (O407)".
--
-- The queues stay the modes' own: this file calls ChaosArena.join, ChaosBattleground.join and
-- ChaosDungeons.queueJoin, and their leave functions. Matchmaking is untouched. Each mode asks ChaosGroupQueue.gate(key,
-- cids) right before it starts a match it found (one guarded call in arena.lua / battleground.lua startMatch and
-- dungeons.lua tryMatch): false = keep everyone queued and try again later (a ready check runs); true = start. On a
-- start the groups in it leave their other queues. A party gets a ready check (Accept / Decline, readyCheckSeconds);
-- a decline or no answer drops that party from every queue, the other side stays queued and is paired again.
-- The arena and the battleground refuse a player queued in the other one; a group that picked both is let through
-- (ChaosGroupQueue.shares in arena.lua / battleground.lua). Raid: the party leader starts a ready check here; when
-- everyone accepted, the raid opens as from the Raid window (ChaosRaid.open).
--
-- Protocol (JSON {action, data}):
--   client -> server  open | query | join {arena?, bg?, role?, dungeon? {id, difficulty}} | leave | accept | decline | raid
--   server -> client  state {open, enabled, size, leader, inParty, arena, bg, raid, dungeons?, group?}
--                     check {key, label, left, seconds, accepted, total, mine}   checkEnd {}   msg {text}
-- In memory only: no storage, no table. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/groupqueue_core.lua")
ChaosGroupQueueConfig = dofile("data/scripts/chaos/groupqueue_config.lua")

ChaosGroupQueue = ChaosGroupQueue or {}
local G = ChaosGroupQueue
local K = ChaosGroupQueueCore
local OPCODE = ChaosOpcodes.groupQueue or 160
G.state = G.state or K.newState()
G.watch = G.watch or {} -- creature id -> true while the window is open

local function cfg()
	return ChaosGroupQueueConfig
end

local function log(text)
	print("[Chaos group queue] " .. text)
end

local function try(name, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function send(player, action, data)
	if player then
		Chaos.send(player, OPCODE, action, data)
	end
end

local function tell(player, text)
	if player then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	end
end

local function onlineOf(g)
	local out = {}
	for _, cid in ipairs(g.members) do
		local p = Player(cid)
		if p then
			out[#out + 1] = p
		end
	end
	return out
end

-- the player alone, or the whole party (leader first); nil + reason when a party member asks
local function membersOf(player)
	local party = player:getParty()
	if not party then
		return {player}
	end
	local leader = party:getLeader()
	if leader ~= player and (not leader or leader:getId() ~= player:getId()) then
		return nil, "Only the party leader can queue the party."
	end
	local list = {player}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	return list
end

-- ---------------------------------------------------------------- the modes (tests replace these)
local function anyQueued(g, isQueued)
	for _, p in ipairs(onlineOf(g)) do
		if isQueued(p) then
			return p
		end
	end
	return nil
end

G.modes = G.modes or {}

G.modes.arena = {
	join = function(g, pick, player)
		local A = ChaosArena
		return A ~= nil and A.join ~= nil and A.join(player, pick.mode) == true
	end,
	queued = function(g)
		local A = ChaosArena
		return A ~= nil and A.isQueued ~= nil and anyQueued(g, A.isQueued) ~= nil
	end,
	leave = function(g)
		local A = ChaosArena
		local p = A and A.isQueued and anyQueued(g, A.isQueued)
		if p then
			A.leaveQueue(p, true)
		end
	end,
	nudge = function()
		if ChaosArena then
			ChaosArena.lastMatchmake = 0
		end
	end
}

G.modes.bg = {
	join = function(g, pick, player)
		local B = ChaosBattleground
		return B ~= nil and B.join ~= nil and B.join(player, pick.role) == true
	end,
	queued = function(g)
		local B = ChaosBattleground
		return B ~= nil and B.isQueued ~= nil and anyQueued(g, B.isQueued) ~= nil
	end,
	leave = function(g)
		local B = ChaosBattleground
		local p = B and B.isQueued and anyQueued(g, B.isQueued)
		if p then
			B.leaveQueue(p, true)
		end
	end,
	nudge = function()
		if ChaosBattleground then
			ChaosBattleground.lastMatchmake = 0
		end
	end
}

-- dungeons queue one character at a time: every member joins the same dungeon and difficulty (all or none)
G.modes.dungeon = {
	join = function(g, pick, player)
		local D = ChaosDungeons
		if not (D and D.queueJoin) then
			return false
		end
		local done = {}
		for _, p in ipairs(onlineOf(g)) do
			local ok, why = D.queueJoin(p, pick.id, pick.difficulty)
			if not ok then
				for _, q in ipairs(done) do
					D.queueLeave(q)
				end
				local text = tostring(why or "")
				if p ~= player then
					text = p:getName() .. ": " .. text
				end
				player:sendCancelMessage(text)
				tell(player, Chaos.t(player, "Dungeon: %s", text))
				return false
			end
			done[#done + 1] = p
		end
		return #done > 0
	end,
	queued = function(g, pick)
		local D = ChaosDungeons
		if not (D and D.queuedFor) then
			return false
		end
		for _, p in ipairs(onlineOf(g)) do
			if D.queuedFor(p) == pick.id then
				return true
			end
		end
		return false
	end,
	leave = function(g, pick)
		local D = ChaosDungeons
		if not (D and D.queuedFor) then
			return
		end
		for _, p in ipairs(onlineOf(g)) do
			if D.queuedFor(p) == pick.id then
				D.queueLeave(p)
			end
		end
	end
}

-- ---------------------------------------------------------------- texts
local function label(player, pick)
	if pick.key == "arena" then
		return Chaos.t(player, "Arena %s", tostring(pick.mode))
	elseif pick.key == "bg" then
		return Chaos.t(player, "Battleground")
	elseif pick.key == "dungeon" then
		local title = ChaosDungeons and ChaosDungeons.titleFor and ChaosDungeons.titleFor(pick.id) or tostring(pick.id)
		return Chaos.t(player, "Dungeon %s (difficulty %d)", title, pick.difficulty or 1)
	end
	return Chaos.t(player, "the raid")
end

local function labelOf(player, g, key)
	return label(player, K.pickOf(g, key) or {key = key})
end

local function labels(player, picks)
	local out = {}
	for _, p in ipairs(picks) do
		out[#out + 1] = label(player, p)
	end
	return table.concat(out, ", ")
end

-- ---------------------------------------------------------------- client
local function sendCheck(g)
	local now = os.time()
	for _, p in ipairs(onlineOf(g)) do
		local v = K.view(g, p:getId(), now)
		if v and v.check then
			v.check.label = labelOf(p, g, v.check.key)
			v.check.seconds = cfg().readyCheckSeconds
			send(p, "check", v.check)
		end
	end
end

function G.sendState(player, open)
	local c = cfg()
	local cid = player:getId()
	local members = membersOf(player)
	local party = player:getParty()
	local size = members and #members or (party and (#(party:getMembers() or {}) + 1)) or 1
	local data = {open = open and true or false, enabled = c.enabled ~= false, size = size, inParty = party ~= nil,
		leader = members ~= nil, arena = {order = c.arenaOrder}, bg = {partyMax = c.bgPartyMax},
		raid = c.raid == true and ChaosRaid ~= nil and ChaosRaid.open ~= nil}
	if Chaos.battlegroundConfig and Chaos.battlegroundConfig.partyMax then
		data.bg.partyMax = Chaos.battlegroundConfig.partyMax
	end
	local g = K.groupOf(G.state, cid)
	local v = K.view(g, cid, os.time())
	if v then
		for i, p in ipairs(g.picks) do
			v.picks[i].label = label(player, p)
		end
		if v.check then
			v.check.label = labelOf(player, g, v.check.key)
		end
		data.group = v
	end
	if open and ChaosDungeons and ChaosDungeons.groupQueueList then
		data.dungeons = try("dungeons", ChaosDungeons.groupQueueList, player) or {}
	end
	send(player, "state", data)
end

local function pushAll(g)
	for _, p in ipairs(onlineOf(g)) do
		G.sendState(p, false)
	end
end

local function refuse(player, text)
	text = Chaos.t(player, text)
	player:sendCancelMessage(text)
	send(player, "msg", {text = text})
end

-- every pick of the group out of its mode's queue (a decline, a time-out, Leave)
local function leaveAll(g, except)
	for _, pick in ipairs(g.picks) do
		local m = G.modes[pick.key]
		if pick.key ~= except and m and m.leave then
			try("leave " .. pick.key, m.leave, g, pick)
		end
	end
end

-- ---------------------------------------------------------------- the hook the modes call
-- key = "arena" | "bg" | "dungeon"; cids = the creature ids of every player of the found match. true = start it.
function G.gate(key, cids)
	if cfg().enabled == false then
		return true
	end
	local ok, verdict, groups = pcall(K.gate, G.state, cfg(), key, cids, os.time())
	if not ok then
		log("gate: " .. tostring(verdict))
		return true
	end
	if verdict == "free" then
		return true
	end
	if verdict == "wait" then
		for _, g in ipairs(groups) do
			for _, p in ipairs(onlineOf(g)) do
				tell(p, Chaos.t(p, "Group Queue: %s found. Ready check: accept within %d seconds.", labelOf(p, g, key),
					cfg().readyCheckSeconds))
			end
			sendCheck(g)
		end
		return false
	end
	for _, g in ipairs(groups) do
		K.remove(G.state, g)
		leaveAll(g, key)
		for _, p in ipairs(onlineOf(g)) do
			if #g.picks > 1 then
				tell(p, Chaos.t(p, "Group Queue: %s found. You left your other queues.", labelOf(p, g, key)))
			end
			send(p, "checkEnd", {})
		end
		pushAll(g)
	end
	return true
end

-- the arena and the battleground let a player stand in both queues when the Group Queue put them there
function G.shares(player, a, b)
	return player ~= nil and K.shares(G.state, player:getId(), a, b)
end

-- ---------------------------------------------------------------- actions
function G.join(player, data)
	local c = cfg()
	if c.enabled == false then
		return refuse(player, "The Group Queue is closed.")
	end
	if K.groupOf(G.state, player:getId()) then
		return refuse(player, "You are in the Group Queue already: leave it first.")
	end
	local members, why = membersOf(player)
	if not members then
		return refuse(player, why)
	end
	local picks
	picks, why = K.parseSelection(c, data, #members)
	if not picks then
		return refuse(player, why)
	end
	local ids = {}
	for i, m in ipairs(members) do
		ids[i] = m:getId()
	end
	local g = K.add(G.state, player:getId(), ids, picks, os.time())
	if not g then
		return refuse(player, "A party member is in the Group Queue already.")
	end
	local failed = {}
	for _, pick in ipairs(picks) do
		local m = G.modes[pick.key]
		local ok = m and m.join and try("join " .. pick.key, m.join, g, pick, player)
		if not ok then
			failed[#failed + 1] = pick
			K.dropPick(G.state, g, pick.key)
		end
	end
	if #g.picks == 0 then
		K.remove(G.state, g)
		refuse(player, "No queue took your group (the reasons are in the messages above).")
		G.sendState(player, false)
		return
	end
	for _, p in ipairs(onlineOf(g)) do
		tell(p, Chaos.t(p, "Group Queue: you joined %s.", labels(p, g.picks)))
		if #failed > 0 then
			tell(p, Chaos.t(p, "Group Queue: not joined: %s.", labels(p, failed)))
		end
	end
	pushAll(g)
end

function G.leave(player)
	local g = K.groupOf(G.state, player:getId())
	if not g then
		return refuse(player, "You are not in the Group Queue.")
	end
	K.remove(G.state, g)
	leaveAll(g)
	for _, p in ipairs(onlineOf(g)) do
		tell(p, p == player and Chaos.t(p, "Group Queue: you left every queue.") or
			Chaos.t(p, "Group Queue: %s left the queues, so did your party.", player:getName()))
		send(p, "checkEnd", {})
	end
	pushAll(g)
	G.sendState(player, false)
end

-- the group is out (a decline, a time-out, a logout during the check): every queue left, everyone told
local function dropped(g, text, ...)
	leaveAll(g)
	for _, p in ipairs(onlineOf(g)) do
		tell(p, Chaos.t(p, text, ...))
		send(p, "checkEnd", {})
	end
	pushAll(g)
end

local function openRaid(g)
	local leader = Player(g.leader)
	K.remove(G.state, g)
	for _, p in ipairs(onlineOf(g)) do
		send(p, "checkEnd", {})
	end
	if not leader then
		for _, p in ipairs(onlineOf(g)) do
			tell(p, Chaos.t(p, "Group Queue: the party leader is gone, the raid stays closed."))
		end
		return
	end
	local ok, why = false, nil
	if ChaosRaid and ChaosRaid.open then
		ok, why = try("raid open", ChaosRaid.open, leader)
	end
	if not ok then
		for _, p in ipairs(onlineOf(g)) do
			tell(p, Chaos.t(p, "Group Queue: the raid did not open: %s", Chaos.t(p, why or "The Sepulchre is sealed.")))
		end
	end
	pushAll(g)
end

function G.answer(player, accept)
	local res, g, key = K.answer(G.state, cfg(), player:getId(), accept, os.time())
	if not res then
		send(player, "checkEnd", {})
		return
	end
	if res == "accepted" then
		sendCheck(g)
	elseif res == "ready" then
		if key == "raid" then
			return openRaid(g)
		end
		for _, p in ipairs(onlineOf(g)) do
			tell(p, Chaos.t(p, "Group Queue: everyone is ready for %s.", labelOf(p, g, key)))
			send(p, "checkEnd", {})
		end
		local m = G.modes[key]
		if m and m.nudge then
			try("nudge", m.nudge)
		end
		pushAll(g)
	elseif res == "declined" then
		dropped(g, "Group Queue: %s declined the ready check. Your group left every queue.", player:getName())
	end
end

function G.raidCheck(player)
	local c = cfg()
	if c.enabled == false or not c.raid or not (ChaosRaid and ChaosRaid.open) then
		return refuse(player, "The raid ready check is not available.")
	end
	if K.groupOf(G.state, player:getId()) then
		return refuse(player, "You are in the Group Queue already: leave it first.")
	end
	local members, why = membersOf(player)
	if not members then
		return refuse(player, why)
	end
	if #members < 2 then
		return refuse(player, "A ready check needs a party. Alone, open the raid from the Raid window.")
	end
	local ids = {}
	for i, m in ipairs(members) do
		ids[i] = m:getId()
	end
	local g = K.add(G.state, player:getId(), ids, {{key = "raid"}}, os.time())
	if not g then
		return refuse(player, "A party member is in the Group Queue already.")
	end
	K.startCheck(c, g, "raid", os.time())
	for _, p in ipairs(onlineOf(g)) do
		tell(p, Chaos.t(p, "Group Queue: %s asks for a raid ready check. Accept within %d seconds.", player:getName(),
			c.readyCheckSeconds))
	end
	sendCheck(g)
	-- the leader asked, so the leader is ready
	G.answer(player, true)
	pushAll(g)
end

-- ---------------------------------------------------------------- the tick
function G.tick()
	local now = os.time()
	for _, e in ipairs(K.expire(G.state, now)) do
		local names = {}
		for _, cid in ipairs(e.missing) do
			local p = Player(cid)
			names[#names + 1] = p and p:getName() or "?"
		end
		dropped(e.group, "Group Queue: no answer from %s. Your group left every queue.", table.concat(names, ", "))
	end
	local changed = K.sync(G.state, function(g, pick)
		local m = G.modes[pick.key]
		if not (m and m.queued) then
			return false
		end
		local ok, res = pcall(m.queued, g, pick)
		return ok and res == true
	end)
	for _, e in ipairs(changed) do
		for _, p in ipairs(onlineOf(e.group)) do
			if e.empty then
				tell(p, Chaos.t(p, "Group Queue: you are in no queue any more."))
				send(p, "checkEnd", {})
			end
		end
		pushAll(e.group)
	end
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosGroupQueueLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGroupQueueExtended")
	player:registerEvent("ChaosGroupQueueLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosGroupQueueLogout")
function logout.onLogout(player)
	G.watch[player:getId()] = nil
	local res, g = K.dropMember(G.state, cfg(), player:getId(), os.time())
	if res == "declined" then
		dropped(g, "Group Queue: %s logged out during the ready check. Your group left every queue.", player:getName())
	end
	return true
end
logout:type("logout")
logout:register()

local think = GlobalEvent("ChaosGroupQueueThink")
function think.onThink(interval)
	try("tick", G.tick)
	return true
end
think:interval(ChaosGroupQueueConfig.tickMs or 1000)
think:register()

local ext = CreatureEvent("ChaosGroupQueueExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	local a = msg.action
	local read = a == "open" or a == "query"
	if Chaos.limited(player, read and "gq.read" or ("gq." .. a), read and cfg().readMs or cfg().actMs) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if a == "open" then
		G.watch[player:getId()] = true
		try("open", G.sendState, player, true)
	elseif a == "query" then
		try("query", G.sendState, player, false)
	elseif a == "join" then
		try("join", G.join, player, data)
	elseif a == "leave" then
		try("leave", G.leave, player)
	elseif a == "accept" or a == "decline" then
		try("answer", G.answer, player, a == "accept")
	elseif a == "raid" then
		try("raid", G.raidCheck, player)
	end
end
ext:type("extendedopcode")
ext:register()

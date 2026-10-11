-- Party Finder (LFG) (client game_partyfinder, extended opcode ChaosOpcodes.partyFinder = 208). Players post a listing
-- (activity, wanted tank / healer / DPS slots, minimum level, note, expiry), others browse it and apply with a role, the
-- leader accepts (a real party invite from the engine) or declines. "Join as role" queues a character for the oldest
-- listing with that role open. Numbers: party_finder_config.lua; pure logic: party_finder_core.lua
-- (tests/party_finder_test.lua); overview: server/README.md "Party Finder".
--
-- The listings are in memory (transient: a restart clears them); no storage keys, no table. The server is the
-- authority: every action is checked by the core against the character's real class, level, party and realm, and rate
-- limited (ChaosRateLimit). Seasons: a listing is only shown to and joinable by characters of its realm (standard or
-- the running season, ChaosSeason.realmOf), as the season's party rule (season.lua onJoin, ChaosSeason.partyAllowed)
-- would refuse the join anyway; staff (group >= staffGroup) see every realm and may close any listing.
-- Every cfg.tickMs a GlobalEvent compares the listings with the engine's parties: accepted applicants who joined, left,
-- or did not answer the invite in time (slot opens again); the leader logged out, left the party or the party broke
-- up (listing closes); expiry; full listings close; the quick-join queue is matched; open windows get the new list.
--
-- Protocol (JSON {action, data}):
--   client -> server  open | hide | refresh | post {a, lo, hi, t, title, want {tank, healer, dps}, minLevel, note, exp,
--                     role, auto} | unlist {id?} | apply {id, role} | withdraw {id} | accept {id, g} | decline {id, g}
--                     | queue {role, a?} | unqueue
--   server -> client  init {acts, roles, my, lv, exp, defExp, lim, staff} | list {rows, mine, badge, applied, queue}
--                     | badge {n} | notice {text, kind}   (kind: info | apply | accepted | error)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/party_finder_core.lua")

Chaos.partyFinderConfig = Chaos.partyFinderConfig or dofile("data/scripts/chaos/party_finder_config.lua")
local cfg = Chaos.partyFinderConfig
local K = ChaosPartyFinderCore
local OPCODE = ChaosOpcodes.partyFinder or 208

ChaosPartyFinder = ChaosPartyFinder or {}
local PF = ChaosPartyFinder
PF.state = PF.state or K.newState()
PF.watch = PF.watch or {} -- creature id -> true while the client's window is open
PF.dirty = false

local function log(text)
	print("[Chaos party finder] " .. text)
end

local function try(name, fn, ...)
	local ok, res, b, c = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res, b, c
end

-- ---------------------------------------------------------------- the activities (from the live configs)
local function namesOf(list, field)
	local out = {}
	for _, e in ipairs(type(list) == "table" and list or {}) do
		local name = type(e) == "table" and e[field] or nil
		if type(name) == "string" and name ~= "" then
			out[#out + 1] = name
		end
	end
	return out
end

function PF.sources()
	local src = {}
	local rift = ChaosRiftConfig
	if type(rift) == "table" then
		src.riftMaxTier = rift.maxTier
		src.omens = namesOf(rift.omen and rift.omen.kinds, "boss")
	end
	local extra = Chaos.dungeons and Chaos.dungeons.extra
	if type(extra) == "table" then
		local ids = {}
		for id in pairs(extra) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		src.dungeons = {}
		for _, id in ipairs(ids) do
			src.dungeons[#src.dungeons + 1] = extra[id].title
		end
	end
	src.worldBosses = namesOf(Chaos.worldBoss and Chaos.worldBoss.bosses, "name")
	src.trials = namesOf(Chaos.trials and Chaos.trials.tiers, "name")
	if type(ChaosRaidConfig) == "table" and ChaosRaidConfig.name then
		src.raids = {ChaosRaidConfig.name} -- raid.lua: the weekly raid
	end
	return src
end

function PF.acts()
	if not PF.activities then
		PF.activities = K.buildActivities(cfg, PF.sources())
	end
	return PF.activities
end

-- ---------------------------------------------------------------- characters
local function isStaff(player)
	local ok, group = pcall(function()
		return player:getGroup():getId()
	end)
	return ok and (tonumber(group) or 0) >= cfg.staffGroup
end

local function realmOf(player)
	local S = ChaosSeason
	if not S or not S.current or not S.realmOf then
		return 0
	end
	local ok, realm = pcall(function()
		return S.current() and S.realmOf(player) or 0
	end)
	return ok and tonumber(realm) or 0
end

local function plain(player)
	local voc = player:getVocation()
	local w = {guid = player:getGuid(), cid = player:getId(), name = player:getName(), level = player:getLevel(),
		voc = voc and voc:getId() or 0, vocName = voc and voc:getName() or ""}
	-- the mentor tag of the character ("mentor" / "seeking"; mentor.lua), shown on listings and applications
	if ChaosMentor and ChaosMentor.tagOf then
		local ok, tag = pcall(ChaosMentor.tagOf, player)
		w.mt = ok and tag or nil
	end
	return w
end

function PF.who(player)
	local w = plain(player)
	w.realm, w.staff = realmOf(player), isStaff(player)
	local party = player:getParty()
	if party then
		w.party = {leader = party:getLeader() == player, members = {}}
		for _, m in ipairs(party:getMembers() or {}) do
			if m ~= player then
				w.party.members[#w.party.members + 1] = plain(m)
			end
		end
		local leader = party:getLeader()
		if leader and leader ~= player then
			w.party.members[#w.party.members + 1] = plain(leader)
		end
	end
	return w
end

-- the online player of a record {guid, cid}
local function online(rec)
	local p = rec and Player(rec.cid)
	if p and p:getGuid() == rec.guid then
		return p
	end
	return nil
end

-- ---------------------------------------------------------------- sending
local function send(player, action, data)
	if not player then
		return false
	end
	return Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))
end

local function notice(player, text, kind, console)
	if not player then
		return
	end
	send(player, "notice", {text = text, kind = kind or "info"})
	if console ~= false then
		player:sendTextMessage(kind == "error" and MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, text)
	end
end

local function refuse(player, reason)
	notice(player, K.reasons[reason] or tostring(reason), "error")
end

function PF.pushList(player)
	if not player then
		return false
	end
	local data = K.list(PF.state, cfg, PF.acts(), PF.who(player), os.time())
	return send(player, "list", data)
end

-- the leader's application count (the client's badge), sent whether the window is open or not
local function badge(L)
	local p = L and online(L.leader)
	if p then
		send(p, "badge", {n = #L.appOrder})
	end
end

local function badgeOf(id)
	badge(PF.state.listings[id])
end

local function roleName(role)
	for _, r in ipairs(cfg.roles) do
		if r.key == role then
			return r.name
		end
	end
	return tostring(role)
end

local function titleOf(L)
	return K.activityText(PF.acts(), L)
end

-- a closed listing: the leader (unless it closed it itself) and every applicant are told
function PF.notifyClosed(L)
	if not L then
		return
	end
	local why = K.closeText[L.closed] or L.closed
	if L.closed ~= "closed" and L.closed ~= "offline" then
		notice(online(L.leader), string.format("Your Party Finder listing (%s) closed: %s.", titleOf(L), why))
	end
	for _, guid in ipairs(L.appOrder) do
		local app = L.apps[guid]
		notice(online(app), string.format("The group of %s (%s) closed: %s.", L.leader.name, titleOf(L), why), "info", false)
	end
	PF.dirty = true
end

-- ---------------------------------------------------------------- accept (the party invite)
function PF.accept(leader, id, guid)
	local state, now = PF.state, os.time()
	local L = state.listings[tonumber(id) or -1]
	local ok, why, app, others = K.decide(state, cfg, leader:getGuid(), id, guid, true, now)
	if not ok then
		return refuse(leader, why)
	end
	for _, other in ipairs(others or {}) do
		badgeOf(other)
	end
	local target = online(app)
	local problem
	local party = leader:getParty()
	if not target then
		problem = app.name .. " is not online."
	elseif target:getParty() then
		problem = app.name .. " joined another party."
	elseif party and party:getLeader() ~= leader then
		problem = "You are no longer the party leader."
	end
	if not problem and not party then
		party = Party(leader)
		if not party then
			problem = "You cannot start a party now."
		end
	end
	if not problem and not party:addInvite(target) then
		problem = app.name .. " cannot be invited now."
	end
	if problem then
		K.inviteFailed(state, L.id, app.guid)
		notice(leader, problem, "error")
	else
		notice(leader, string.format("%s was invited to your party as %s.", app.name, roleName(app.role)))
		notice(target, string.format("%s accepted you as %s for %s: accept the party invitation.", leader:getName(),
			roleName(app.role), titleOf(L)), "accepted")
	end
	badge(L)
	PF.dirty = true
end

-- ---------------------------------------------------------------- the tick
local function partyInfo(L)
	local leader = online(L.leader)
	local info = {leaderOnline = leader ~= nil, party = {}, crew = {}}
	if not leader then
		return info
	end
	local party = leader:getParty()
	if party then
		info.leaderInParty = true
		info.leaderIsLeader = party:getLeader() == leader
		for _, m in ipairs(party:getMembers() or {}) do
			if m ~= leader then
				local p = plain(m)
				info.party[p.guid] = true
				info.crew[#info.crew + 1] = p
			end
		end
	end
	return info
end

function PF.tick()
	local state, now = PF.state, os.time()
	local ids = {}
	for _, id in ipairs(state.order) do
		ids[#ids + 1] = id
	end
	for _, id in ipairs(ids) do
		local L = state.listings[id]
		local events, closed = {}, nil
		if L then
			events, closed = K.reconcile(state, cfg, id, partyInfo(L), now)
		end
		local leader = L and online(L.leader)
		for _, e in ipairs(events) do
			PF.dirty = true
			if e.kind == "joined" then
				notice(leader, string.format("%s joined your group as %s.", e.member.name, roleName(e.member.role)), "info", false)
			elseif e.kind == "inviteExpired" then
				notice(leader, string.format("%s did not join in time; the %s slot is open again.", e.member.name,
					roleName(e.member.role)))
				notice(online(e.member), "The party invitation from " .. L.leader.name .. " ran out.", "info", false)
			end
		end
		if closed then
			PF.notifyClosed(closed)
		end
	end
	-- the queue: offline characters and characters in a party leave it, then the matching
	for i = #state.queueOrder, 1, -1 do
		local guid = state.queueOrder[i]
		local p = online(state.queue[guid])
		if not p or p:getParty() then
			K.queueLeave(state, guid)
		end
	end
	for _, m in ipairs(K.match(state, cfg, now)) do
		PF.dirty = true
		local L = m.id and state.listings[m.id]
		if m.expired then
			notice(online(m.who), "You left the Party Finder queue: no group was found in time.")
		elseif L then
			local leader = online(L.leader)
			notice(online(m.app), string.format("Quick join: you applied to %s's group (%s) as %s.", L.leader.name,
				titleOf(L), roleName(m.app.role)))
			if m.auto and leader then
				PF.accept(leader, L.id, m.guid)
			else
				notice(leader, string.format("Quick join: %s (level %d %s) wants to join as %s.", m.app.name, m.app.level,
					m.app.vocName or "", roleName(m.app.role)), "apply")
				badge(L)
			end
		end
	end
	if PF.dirty then
		PF.dirty = false
		for cid in pairs(PF.watch) do
			local p = Player(cid)
			if p then
				try("push", PF.pushList, p)
			else
				PF.watch[cid] = nil
			end
		end
	end
end

-- ---------------------------------------------------------------- actions
local function handle(player, action, d)
	local state, now = PF.state, os.time()
	if action == "open" then
		PF.watch[player:getId()] = true
		send(player, "init", K.init(cfg, PF.acts(), PF.who(player)))
		return PF.pushList(player)
	elseif action == "hide" then
		PF.watch[player:getId()] = nil
		return
	elseif action == "refresh" then
		return PF.pushList(player)
	end
	local who = PF.who(player)
	if action == "post" then
		local L, st = K.post(state, cfg, PF.acts(), who, d, now)
		if not L then
			return refuse(player, st)
		end
		notice(player, st == "posted" and "Your group is listed in the Party Finder." or "Your listing was updated.",
			"info", false)
		badge(L)
	elseif action == "unlist" then
		local L, why = K.closeBy(state, who, d.id)
		if not L then
			return refuse(player, why)
		end
		PF.notifyClosed(L)
	elseif action == "apply" then
		local app, st = K.apply(state, cfg, who, d.id, d.role, now, false)
		if not app then
			return refuse(player, st)
		end
		local L = state.listings[tonumber(d.id)]
		notice(player, string.format("You applied to %s's group as %s.", L.leader.name, roleName(app.role)), "info", false)
		local leader = online(L.leader)
		if st == "applied" then
			notice(leader, string.format("%s (level %d %s) applied to your group as %s.", app.name, app.level,
				app.vocName or "", roleName(app.role)), "apply")
		end
		badge(L)
	elseif action == "withdraw" then
		if K.withdraw(state, who.guid, d.id) then
			badgeOf(tonumber(d.id))
		end
	elseif action == "accept" then
		PF.accept(player, d.id, d.g)
	elseif action == "decline" then
		local ok, why, app = K.decide(state, cfg, who.guid, d.id, d.g, false, now)
		if not ok then
			return refuse(player, why)
		end
		notice(online(app), string.format("%s declined your application.", player:getName()), "info")
		badgeOf(tonumber(d.id))
	elseif action == "queue" then
		local q, why = K.queueJoin(state, cfg, PF.acts(), who, d.role, d.a, now)
		if not q then
			return refuse(player, why)
		end
		notice(player, string.format("Queued as %s. You will be matched with the first group that needs one.",
			roleName(q.role)), "info", false)
	elseif action == "unqueue" then
		K.queueLeave(state, who.guid)
	else
		return
	end
	PF.dirty = true
	PF.pushList(player)
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosPartyFinderLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPartyFinderExtended")
	player:registerEvent("ChaosPartyFinderLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPartyFinderLogout")
function logout.onLogout(player)
	PF.watch[player:getId()] = nil
	local closed, ids = K.dropPlayer(PF.state, player:getGuid())
	if closed then
		try("closed", PF.notifyClosed, closed)
	end
	for _, id in ipairs(ids or {}) do
		try("badge", badgeOf, id)
	end
	PF.dirty = true
	return true
end
logout:type("logout")
logout:register()

local think = GlobalEvent("ChaosPartyFinderThink")
function think.onThink(interval)
	if cfg.enabled ~= false then
		try("tick", PF.tick)
	end
	return true
end
think:interval(cfg.tickMs)
think:register()

local ext = CreatureEvent("ChaosPartyFinderExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return
	end
	local action = msg.action
	local read = action == "open" or action == "refresh" or action == "hide"
	if ChaosRateLimit and action ~= "hide" and not ChaosRateLimit.allow(player, read and "pf.read" or "pf.act",
			read and cfg.readMs or cfg.actMs) then
		return
	end
	if cfg.enabled == false then
		return refuse(player, "disabled")
	end
	try("action " .. action, handle, player, action, type(msg.data) == "table" and msg.data or {})
end
ext:type("extendedopcode")
ext:register()

-- Party Finder (LFG): the pure logic (no engine calls), tested by tests/party_finder_test.lua. The engine file
-- party_finder.lua feeds it plain tables and turns its answers into party invites, messages and window payloads.
-- Overview: server/README.md "Party Finder". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A character ("who") is a plain table:
--   {guid, cid, name, level, voc, vocName, realm, staff, party = nil | {leader = bool, members = {who-like, ...}}}
--   party.members are the OTHER members of the character's party (the engine's party, not the listing's).
-- A listing:
--   {id, leader = {guid, cid, name, level, voc, vocName, role}, realm, staff, a (activity key), lo, hi, t (target, 0 =
--    any), title, want = {tank, healer, dps}, minLevel, note, expMin, created, expires, auto, max (group size: 10, raid 15),
--    members = {{guid, cid, name, level, voc, vocName, role, st = "invited" | "joined", at}, ...} (taken by the listing),
--    crew = {{guid, name, level, voc, vocName, role}, ...} (in the leader's party without a listing slot),
--    apps = {[guid] = app}, appOrder = {guid, ...}, hadParty}
--   want counts the slots of a role the listing offers; the ones its members took are no longer open.

ChaosPartyFinderCore = ChaosPartyFinderCore or {}
local K = ChaosPartyFinderCore

K.reasons = {
	disabled = "The Party Finder is closed right now.",
	activity = "Pick an activity.",
	range = "That range is not possible for this activity.",
	target = "Pick one of the listed targets.",
	title = "Give your group a short title.",
	role = "Your class cannot fill that role.",
	want = "Ask for at least one tank, healer or DPS.",
	perRole = "Too many of one role.",
	size = "That is more than a full party.",
	wantBelow = "You already took more of that role.",
	level = "Your level is below the listing's minimum.",
	minLevel = "That minimum level is not possible.",
	notLeader = "Only the party leader can post a listing.",
	cooldown = "Wait a moment before posting again.",
	busyServer = "Too many listings right now. Try again later.",
	gone = "That listing is gone.",
	own = "That is your own listing.",
	realm = "That group plays in another realm.",
	inParty = "Leave your party first.",
	already = "You are already in that group.",
	full = "That role is already filled.",
	declined = "The leader declined you a moment ago.",
	tooMany = "You have too many applications open. Withdraw one first.",
	busy = "That listing has too many applications.",
	notYours = "That is not your listing.",
	noApp = "That application is gone.",
	partyFull = "Your party is full.",
	queued = "You are already queued.",
	notQueued = "You are not queued."
}

K.closeText = {
	closed = "closed by the leader",
	full = "full",
	expired = "expired",
	offline = "the leader logged out",
	leaderLeft = "the leader left the party",
	disbanded = "the party broke up",
	staff = "closed by staff"
}

-- ---------------------------------------------------------------- small helpers
local function int(v)
	local n = tonumber(v)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.floor(n)
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

function K.newState()
	return {listings = {}, order = {}, nextId = 1, byLeader = {}, apps = {}, declined = {}, lastPost = {},
		lastUpdate = {}, queue = {}, queueOrder = {}}
end

-- ---------------------------------------------------------------- roles
function K.roleKeys(cfg)
	local keys = {}
	for _, r in ipairs(cfg.roles) do
		keys[#keys + 1] = r.key
	end
	return keys
end

function K.isRole(cfg, role)
	return type(role) == "string" and contains(K.roleKeys(cfg), role)
end

function K.rolesOf(cfg, voc)
	return cfg.classRoles[int(voc) or -1] or cfg.defaultRoles
end

function K.canFill(cfg, voc, role)
	return contains(K.rolesOf(cfg, voc), role)
end

function K.mainRole(cfg, voc)
	return K.rolesOf(cfg, voc)[1] or "dps"
end

-- ---------------------------------------------------------------- activities
-- sources = {riftMaxTier, dungeons = {names}, worldBosses = {names}, omens = {names}, trials = {names}}
function K.buildActivities(cfg, sources)
	sources = sources or {}
	local list = {}
	for _, a in ipairs(cfg.activities) do
		local e = {k = a.key, n = a.name}
		if a.range then
			local max = a.range.max
			if a.key == "rift" and int(sources.riftMaxTier) and int(sources.riftMaxTier) >= a.range.min then
				max = int(sources.riftMaxTier)
			end
			e.range = {min = a.range.min, max = max, label = a.range.label, short = a.range.short}
		end
		if a.targets then
			local names = sources[a.targets]
			if type(names) ~= "table" or #names == 0 then
				names = a.fallback or {}
			end
			e.targets = {}
			for _, name in ipairs(names) do
				e.targets[#e.targets + 1] = tostring(name)
			end
		end
		if a.title then
			e.title = true
		end
		-- the group size and wanted caps per role of this activity (a raid holds 15), and the form's proposal
		e.max = int(a.maxParty) or cfg.maxParty
		e.per = {}
		for _, r in ipairs(K.roleKeys(cfg)) do
			e.per[r] = int(a.perRole and a.perRole[r]) or cfg.maxPerRole
		end
		if type(a.suggest) == "table" then
			e.suggest = {}
			for _, r in ipairs(K.roleKeys(cfg)) do
				e.suggest[r] = int(a.suggest[r]) or 0
			end
		end
		list[#list + 1] = e
	end
	return list
end

function K.activity(acts, key)
	for _, a in ipairs(acts or {}) do
		if a.k == key then
			return a
		end
	end
	return nil
end

-- "Rift T5-8", "Infinity Tower F10", "Dungeon: Bones Dungeon", "Raid", "Other: Quest help"
function K.activityText(acts, L)
	local a = K.activity(acts, L.a)
	if not a then
		return "?"
	end
	if a.range then
		local short = a.range.short or ""
		if L.lo == L.hi then
			return string.format("%s %s%d", a.n, short, L.lo)
		end
		return string.format("%s %s%d-%d", a.n, short, L.lo, L.hi)
	end
	if a.targets then
		local t = a.targets[L.t or 0]
		return t and (a.n .. ": " .. t) or a.n
	end
	if a.title and L.title and L.title ~= "" then
		return a.n .. ": " .. L.title
	end
	return a.n
end

-- ---------------------------------------------------------------- the note filter
-- printable ASCII only, one line, single spaces, bad words become asterisks, link-like words are cut, at most `max`
function K.cleanText(text, max, cfg)
	local s = tostring(text or "")
	s = s:gsub("[^\32-\126]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	local tlds = {}
	for _, t in ipairs(cfg and cfg.linkTlds or {}) do
		tlds[t] = true
	end
	local words = {}
	for word in s:gmatch("%S+") do
		local lower = word:lower()
		local tld = lower:match("^[%w%-_]+%.([%a]+)[/%w%.%-_]*$")
		if lower:find("://", 1, true) or lower:find("^www%.") or (tld and tlds[tld]) then
			word = "***"
		end
		words[#words + 1] = word
	end
	s = table.concat(words, " ")
	for _, bad in ipairs(cfg and cfg.badWords or {}) do
		local lower = s:lower()
		local from = 1
		while true do
			local i, j = lower:find(bad, from, true)
			if not i then
				break
			end
			s = s:sub(1, i - 1) .. string.rep("*", j - i + 1) .. s:sub(j + 1)
			from = j + 1
		end
	end
	if max and #s > max then
		s = s:sub(1, max):gsub(" $", "")
	end
	return s
end

-- ---------------------------------------------------------------- slots
function K.filled(cfg, L)
	local out = {}
	for _, r in ipairs(K.roleKeys(cfg)) do
		out[r] = 0
	end
	for _, m in ipairs(L.members) do
		out[m.role] = (out[m.role] or 0) + 1
	end
	return out
end

-- open slots per role and in total
function K.open(cfg, L)
	local filled = K.filled(cfg, L)
	local out, total = {}, 0
	for _, r in ipairs(K.roleKeys(cfg)) do
		out[r] = math.max(0, (L.want[r] or 0) - (filled[r] or 0))
		total = total + out[r]
	end
	return out, total
end

-- characters in the group now or on their way: leader + crew + listing members
function K.size(L)
	return 1 + #L.crew + #L.members
end

-- the most characters the listing's group may hold (its activity's maxParty, set by K.post)
function K.maxOf(cfg, L)
	return int(L and L.max) or cfg.maxParty
end

function K.visibleTo(L, viewer)
	return viewer.staff or L.staff or (L.realm or 0) == (viewer.realm or 0)
end

local function findMember(L, guid)
	for i, m in ipairs(L.members) do
		if m.guid == guid then
			return m, i
		end
	end
	return nil
end

local function plainOf(who, role)
	return {guid = who.guid, cid = who.cid, name = who.name, level = who.level, voc = who.voc, vocName = who.vocName,
		role = role, mt = who.mt} -- mt: the mentor tag ("mentor" / "seeking", mentor.lua ChaosMentor.tagOf)
end

local function crewOf(cfg, who, L)
	local crew = {}
	for _, m in ipairs(who.party and who.party.members or {}) do
		if not (L and findMember(L, m.guid)) then
			local c = plainOf(m, K.mainRole(cfg, m.voc))
			crew[#crew + 1] = c
		end
	end
	return crew
end

-- ---------------------------------------------------------------- applications
local function removeApp(state, L, guid)
	if not L.apps[guid] then
		return false
	end
	L.apps[guid] = nil
	for i, g in ipairs(L.appOrder) do
		if g == guid then
			table.remove(L.appOrder, i)
			break
		end
	end
	local mine = state.apps[guid]
	if mine then
		mine[L.id] = nil
		if next(mine) == nil then
			state.apps[guid] = nil
		end
	end
	return true
end

function K.appCount(state, guid)
	local n = 0
	for _ in pairs(state.apps[guid] or {}) do
		n = n + 1
	end
	return n
end

-- ---------------------------------------------------------------- post / update / close
-- input = {a, lo, hi, t, title, want = {tank, healer, dps}, minLevel, note, exp, role, auto}
-- -> listing, "posted" | "updated"   or   nil, reason key
function K.post(state, cfg, acts, who, input, now)
	if cfg.enabled == false then
		return nil, "disabled"
	end
	input = type(input) == "table" and input or {}
	if who.party and not who.party.leader then
		return nil, "notLeader"
	end
	local L = state.byLeader[who.guid] and state.listings[state.byLeader[who.guid]] or nil
	local a = K.activity(acts, input.a)
	if not a then
		return nil, "activity"
	end
	local lo, hi, t, title = 0, 0, 0, nil
	if a.range then
		lo = int(input.lo) or a.range.min
		hi = int(input.hi) or lo
		if lo < a.range.min or hi > a.range.max or lo > hi then
			return nil, "range"
		end
	end
	if a.targets then
		t = int(input.t) or 0
		if t < 0 or t > #a.targets then
			return nil, "target"
		end
	end
	if a.title then
		title = K.cleanText(input.title, cfg.titleMax, cfg)
		if title == "" or title:gsub("[%*%s]", "") == "" then
			return nil, "title"
		end
	end
	local role = input.role
	if not K.isRole(cfg, role) or not K.canFill(cfg, who.voc, role) then
		return nil, "role"
	end
	local want, sum = {}, 0
	local wantIn = type(input.want) == "table" and input.want or {}
	for _, r in ipairs(K.roleKeys(cfg)) do
		local n = int(wantIn[r] or 0)
		if not n or n < 0 or n > ((a.per and a.per[r]) or cfg.maxPerRole) then
			return nil, "perRole"
		end
		want[r] = n
		sum = sum + n
	end
	if sum < 1 then
		return nil, "want"
	end
	local minLevel = int(input.minLevel or 1)
	if not minLevel or minLevel < 1 or minLevel > cfg.maxLevel then
		return nil, "minLevel"
	end
	local expMin = int(input.exp) or cfg.defaultExpiry
	if not contains(cfg.expiryMinutes, expMin) then
		expMin = cfg.defaultExpiry
	end
	local crew = crewOf(cfg, who, L)
	-- the slots: the leader, the party without a listing slot, and every wanted slot (taken ones included)
	local max = a.max or cfg.maxParty
	if 1 + #crew + sum > max then
		return nil, "size"
	end
	if L then
		local filled = K.filled(cfg, L)
		for _, r in ipairs(K.roleKeys(cfg)) do
			if want[r] < (filled[r] or 0) then
				return nil, "wantBelow"
			end
		end
		if state.lastUpdate[who.guid] and now - state.lastUpdate[who.guid] < cfg.updateCooldown then
			return nil, "cooldown"
		end
	else
		if state.lastPost[who.guid] and now - state.lastPost[who.guid] < cfg.postCooldown then
			return nil, "cooldown"
		end
		local count = 0
		for _ in pairs(state.listings) do
			count = count + 1
		end
		if count >= cfg.maxListings then
			return nil, "busyServer"
		end
	end
	local status = L and "updated" or "posted"
	if not L then
		L = {id = state.nextId, members = {}, apps = {}, appOrder = {}, created = now}
		state.nextId = state.nextId + 1
		state.listings[L.id] = L
		table.insert(state.order, 1, L.id)
		state.byLeader[who.guid] = L.id
		state.lastPost[who.guid] = now
	end
	state.lastUpdate[who.guid] = now
	L.leader = plainOf(who, role)
	L.realm, L.staff = who.realm or 0, who.staff and true or false
	L.a, L.lo, L.hi, L.t, L.title = a.k, lo, hi, t, title
	L.max = max
	L.want, L.minLevel, L.expMin, L.auto = want, minLevel, expMin, input.auto and true or false
	L.note = K.cleanText(input.note, cfg.noteMax, cfg)
	L.crew = crew
	L.hadParty = L.hadParty or #crew > 0
	L.expires = now + expMin * 60
	-- applications for a role that is no longer open stay: the leader sees them and may decline
	return L, status
end

-- removes the listing; returns it (its apps and members still inside, for the messages) or nil
function K.close(state, id, why)
	local L = state.listings[id]
	if not L then
		return nil
	end
	for _, guid in ipairs(L.appOrder) do
		local mine = state.apps[guid]
		if mine then
			mine[id] = nil
			if next(mine) == nil then
				state.apps[guid] = nil
			end
		end
	end
	state.listings[id] = nil
	state.declined[id] = nil
	if state.byLeader[L.leader.guid] == id then
		state.byLeader[L.leader.guid] = nil
	end
	for i, v in ipairs(state.order) do
		if v == id then
			table.remove(state.order, i)
			break
		end
	end
	L.closed = why or "closed"
	return L
end

-- the leader's own close, or a staff member's
function K.closeBy(state, who, id)
	local L = state.listings[int(id) or (state.byLeader[who.guid] or -1)]
	if not L then
		return nil, "gone"
	end
	if L.leader.guid ~= who.guid and not who.staff then
		return nil, "notYours"
	end
	return K.close(state, L.id, L.leader.guid == who.guid and "closed" or "staff")
end

-- ---------------------------------------------------------------- apply / withdraw / decide
-- -> app, "applied" | "updated"   or   nil, reason key
function K.apply(state, cfg, who, id, role, now, quick)
	local L = state.listings[int(id) or -1]
	if not L then
		return nil, "gone"
	end
	if L.leader.guid == who.guid then
		return nil, "own"
	end
	if not K.visibleTo(L, who) then
		return nil, "realm"
	end
	if who.party then
		return nil, "inParty"
	end
	if findMember(L, who.guid) then
		return nil, "already"
	end
	if not K.isRole(cfg, role) or not K.canFill(cfg, who.voc, role) then
		return nil, "role"
	end
	if (who.level or 0) < L.minLevel then
		return nil, "level"
	end
	local open = K.open(cfg, L)
	if (open[role] or 0) <= 0 then
		return nil, "full"
	end
	local until_ = state.declined[L.id] and state.declined[L.id][who.guid]
	if until_ and now < until_ then
		return nil, "declined"
	end
	local app = L.apps[who.guid]
	if app then
		app.role, app.level = role, who.level
		return app, "updated"
	end
	if K.appCount(state, who.guid) >= cfg.maxApplications then
		return nil, "tooMany"
	end
	if #L.appOrder >= cfg.maxApplicants then
		return nil, "busy"
	end
	app = plainOf(who, role)
	app.at, app.quick = now, quick and true or false
	L.apps[who.guid] = app
	L.appOrder[#L.appOrder + 1] = who.guid
	state.apps[who.guid] = state.apps[who.guid] or {}
	state.apps[who.guid][L.id] = true
	return app, "applied"
end

function K.withdraw(state, guid, id)
	local L = state.listings[int(id) or -1]
	if not L then
		return false
	end
	return removeApp(state, L, guid)
end

-- every application of a character (it joined a group, logged out): the listing ids it was removed from
function K.withdrawAll(state, guid)
	local ids = {}
	for id in pairs(state.apps[guid] or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local L = state.listings[id]
		if L then
			removeApp(state, L, guid)
		end
	end
	state.apps[guid] = nil
	return ids
end

-- the leader accepts or declines an application.
-- accept -> true, "accepted", app, {other listing ids the applicant was withdrawn from}; the engine then sends the
-- party invite (K.inviteFailed when that is not possible). decline -> true, "declined", app.
function K.decide(state, cfg, leaderGuid, id, guid, accept, now)
	local L = state.listings[int(id) or -1]
	if not L then
		return nil, "gone"
	end
	if L.leader.guid ~= leaderGuid then
		return nil, "notYours"
	end
	guid = int(guid)
	local app = guid and L.apps[guid]
	if not app then
		return nil, "noApp"
	end
	if not accept then
		removeApp(state, L, guid)
		state.declined[L.id] = state.declined[L.id] or {}
		state.declined[L.id][guid] = now + cfg.declineCooldown
		return true, "declined", app
	end
	local open = K.open(cfg, L)
	if (open[app.role] or 0) <= 0 then
		return nil, "full"
	end
	if K.size(L) >= K.maxOf(cfg, L) then
		return nil, "partyFull"
	end
	removeApp(state, L, guid)
	local others = K.withdrawAll(state, guid)
	K.queueLeave(state, guid)
	local m = plainOf(app, app.role)
	m.st, m.at = "invited", now
	L.members[#L.members + 1] = m
	return true, "accepted", app, others
end

-- the engine could not send the invite: the slot opens again
function K.inviteFailed(state, id, guid)
	local L = state.listings[id]
	if not L then
		return false
	end
	local _, i = findMember(L, guid)
	if i then
		table.remove(L.members, i)
		return true
	end
	return false
end

-- ---------------------------------------------------------------- the engine's view
-- info = {leaderOnline, leaderInParty, leaderIsLeader, party = {[guid] = true} (the leader's party members),
--         crew = {who-like} (the leader's party members, for the composition)}
-- -> list of events {kind = "joined" | "left" | "inviteExpired", guid, member} and, when the listing closed, the
--    listing (closed field set)
function K.reconcile(state, cfg, id, info, now)
	local L = state.listings[id]
	if not L then
		return {}, nil
	end
	local events = {}
	if not info.leaderOnline then
		return events, K.close(state, id, "offline")
	end
	if info.leaderInParty and not info.leaderIsLeader then
		return events, K.close(state, id, "leaderLeft")
	end
	if now >= L.expires then
		return events, K.close(state, id, "expired")
	end
	local party = info.party or {}
	local i = 1
	while i <= #L.members do
		local m = L.members[i]
		if party[m.guid] then
			if m.st ~= "joined" then
				m.st = "joined"
				L.hadParty = true
				events[#events + 1] = {kind = "joined", guid = m.guid, member = m}
			end
			i = i + 1
		elseif m.st == "joined" then
			table.remove(L.members, i)
			events[#events + 1] = {kind = "left", guid = m.guid, member = m}
		elseif now - (m.at or now) >= cfg.inviteSeconds then
			table.remove(L.members, i)
			events[#events + 1] = {kind = "inviteExpired", guid = m.guid, member = m}
		else
			i = i + 1
		end
	end
	-- (a party of the leader alone with an open invitation does not count: an unanswered invite must not close it)
	if not info.leaderInParty and L.hadParty then
		return events, K.close(state, id, "disbanded")
	end
	local crew = {}
	for _, c in ipairs(info.crew or {}) do
		if not findMember(L, c.guid) then
			crew[#crew + 1] = plainOf(c, K.mainRole(cfg, c.voc))
		end
	end
	L.crew = crew
	if #crew > 0 then
		L.hadParty = true
	end
	local _, open = K.open(cfg, L)
	if open == 0 then
		local pending = false
		for _, m in ipairs(L.members) do
			if m.st ~= "joined" then
				pending = true
			end
		end
		if not pending then
			return events, K.close(state, id, "full")
		end
	end
	return events, nil
end

-- a character logged out: its listing closes, its applications and queue entry go.
-- -> closed listing or nil, {listing ids it had applied to}
function K.dropPlayer(state, guid)
	local closed
	if state.byLeader[guid] then
		closed = K.close(state, state.byLeader[guid], "offline")
	end
	local ids = K.withdrawAll(state, guid)
	K.queueLeave(state, guid)
	state.lastUpdate[guid] = nil
	return closed, ids
end

-- ---------------------------------------------------------------- quick join ("Join as role")
function K.queueJoin(state, cfg, acts, who, role, activity, now)
	if who.party then
		return nil, "inParty"
	end
	if not K.isRole(cfg, role) or not K.canFill(cfg, who.voc, role) then
		return nil, "role"
	end
	if activity ~= nil and activity ~= "" and not K.activity(acts, activity) then
		return nil, "activity"
	end
	local q = state.queue[who.guid]
	if not q then
		q = {}
		state.queue[who.guid] = q
		state.queueOrder[#state.queueOrder + 1] = who.guid
	end
	for k, v in pairs(plainOf(who, role)) do
		q[k] = v
	end
	q.realm, q.staff = who.realm or 0, who.staff and true or false
	q.a = (activity ~= "" and activity) or nil
	q.at = q.at or now
	q.untilAt = now + cfg.queueMinutes * 60
	return q
end

function K.queueLeave(state, guid)
	if not state.queue[guid] then
		return false
	end
	state.queue[guid] = nil
	for i, g in ipairs(state.queueOrder) do
		if g == guid then
			table.remove(state.queueOrder, i)
			break
		end
	end
	return true
end

-- every queued character (first come, first served) into the oldest listing with its role open, its level, realm and
-- activity. -> list of {guid, id, app, auto}; matched characters leave the queue; expired ones too ({guid, expired =
-- true, who = the queue entry}).
function K.match(state, cfg, now)
	local out = {}
	local order = {}
	for _, g in ipairs(state.queueOrder) do
		order[#order + 1] = g
	end
	for _, guid in ipairs(order) do
		local q = state.queue[guid]
		if q and now >= q.untilAt then
			K.queueLeave(state, guid)
			out[#out + 1] = {guid = guid, expired = true, who = q}
		elseif q then
			for i = #state.order, 1, -1 do
				local L = state.listings[state.order[i]]
				if L and (not q.a or q.a == L.a) and not L.apps[guid] then
					local app = K.apply(state, cfg, q, L.id, q.role, now, true)
					if app then
						K.queueLeave(state, guid)
						out[#out + 1] = {guid = guid, id = L.id, app = app, auto = L.auto}
						break
					end
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- payloads
local function brief(p, st)
	return {n = p.name, lv = p.level, vn = p.vocName, v = p.voc, r = p.role, st = st, mt = p.mt}
end

function K.row(cfg, acts, L, viewer, now)
	local open = K.open(cfg, L)
	local comp = {brief(L.leader, "leader")}
	for _, c in ipairs(L.crew) do
		comp[#comp + 1] = brief(c, "party")
	end
	for _, m in ipairs(L.members) do
		comp[#comp + 1] = brief(m, m.st)
	end
	local app = L.apps[viewer.guid]
	local row = {id = L.id, a = L.a, an = K.activityText(acts, L), ld = L.leader.name, comp = comp, want = L.want,
		open = open, ml = L.minLevel, note = L.note, left = math.max(0, L.expires - now), auto = L.auto,
		mine = L.leader.guid == viewer.guid, ap = app and app.role or nil, max = K.maxOf(cfg, L)}
	row.mt = L.leader.mt
	if L.realm and L.realm > 0 then
		row.season = true
	end
	return row
end

-- the browse list of one viewer (realm filtered; listings without an open slot only when they are the viewer's own or
-- the viewer applied), newest first; plus the viewer's own listing with its applications, and its queue entry
function K.list(state, cfg, acts, viewer, now)
	local rows = {}
	for _, id in ipairs(state.order) do
		local L = state.listings[id]
		if L and K.visibleTo(L, viewer) then
			local _, total = K.open(cfg, L)
			if total > 0 or L.leader.guid == viewer.guid or L.apps[viewer.guid] then
				rows[#rows + 1] = K.row(cfg, acts, L, viewer, now)
			end
		end
	end
	local out = {rows = rows, badge = 0}
	local mineId = state.byLeader[viewer.guid]
	local L = mineId and state.listings[mineId]
	if L then
		local mine = K.row(cfg, acts, L, viewer, now)
		mine.input = {a = L.a, lo = L.lo, hi = L.hi, t = L.t, title = L.title, want = L.want, minLevel = L.minLevel,
			note = L.note, exp = L.expMin, role = L.leader.role, auto = L.auto}
		mine.apps = {}
		for _, guid in ipairs(L.appOrder) do
			local a = L.apps[guid]
			mine.apps[#mine.apps + 1] = {g = a.guid, n = a.name, lv = a.level, vn = a.vocName, v = a.voc, r = a.role,
				q = a.quick or nil, ago = math.max(0, now - a.at), mt = a.mt}
		end
		out.mine = mine
		out.badge = #mine.apps
	end
	local q = state.queue[viewer.guid]
	if q then
		out.queue = {r = q.role, a = q.a, since = math.max(0, now - q.at)}
	end
	out.applied = K.appCount(state, viewer.guid)
	return out
end

-- the window's first message: activities, roles, what the viewer may fill, the limits
function K.init(cfg, acts, who)
	local roles = {}
	for _, r in ipairs(cfg.roles) do
		roles[#roles + 1] = {k = r.key, n = r.name, c = r.c}
	end
	return {acts = acts, roles = roles, my = K.rolesOf(cfg, who.voc), lv = who.level, exp = cfg.expiryMinutes,
		defExp = cfg.defaultExpiry, lim = {note = cfg.noteMax, title = cfg.titleMax, perRole = cfg.maxPerRole,
		party = cfg.maxParty, level = cfg.maxLevel}, staff = who.staff and true or nil}
end

return K

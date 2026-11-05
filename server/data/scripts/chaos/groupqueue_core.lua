-- The Group Queue (O407): pure logic, no engine calls (tests/groupqueue_test.lua). Engine glue: groupqueue.lua; numbers:
-- groupqueue_config.lua; overview: server/README.md "Group Queue (O407)".
--
-- A group is one player or one party, put into one or more mode queues at once ("picks": arena, bg, dungeon). The
-- queues themselves stay the modes' own (arena.lua, battleground.lua, dungeons.lua). When a mode found a match it asks
-- K.gate before it starts it:
--   "free"  none of the players came through the Group Queue: the mode goes on as before
--   "wait"  a ready check runs (or was just started) for a group in it: the mode keeps everyone queued and tries again
--   "go"    every group in it accepted (or needs no check): the mode starts the match, the groups leave their other queues
-- A decline or a time-out drops the decliner's group (it leaves all its queues); every other group of that match stays
-- queued, and the mode pairs it again. "raid" is a ready check only: the leader's raid opens when everyone accepted.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGroupQueueCore = ChaosGroupQueueCore or {}
local K = ChaosGroupQueueCore

K.QUEUES = {"arena", "bg", "dungeon"} -- the order the engine joins them in

function K.newState()
	return {groups = {}, of = {}, seq = 0}
end

local function int(v)
	local n = tonumber(v)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.floor(n)
end

-- the client's choice -> the picks, in K.QUEUES order; nil + reason (an English key of i18n_strings.lua)
-- data = {arena = "2v2", bg = true, role = "tank", dungeon = {id = 3, difficulty = 2}}; size = the party size (1 alone)
function K.parseSelection(cfg, data, size)
	if type(data) ~= "table" then
		return nil, "Pick at least one queue."
	end
	size = math.max(1, int(size) or 1)
	local picks = {}
	local arena = data.arena
	if arena ~= nil and arena ~= false and arena ~= "" then
		local mode = tostring(arena)
		local need = cfg.arenaModes[mode]
		if not need then
			return nil, "That arena mode does not exist."
		end
		if need ~= size then
			return nil, "Arena: 1v1 is played alone, 2v2 as a party of two, 3v3 as a party of three."
		end
		picks[#picks + 1] = {key = "arena", mode = mode}
	end
	if data.bg == true then
		if size > cfg.bgPartyMax then
			return nil, "Your party is too large for the battleground."
		end
		local role = type(data.role) == "string" and data.role or nil
		picks[#picks + 1] = {key = "bg", role = (role and cfg.roles[role]) and role or nil}
	end
	if type(data.dungeon) == "table" then
		local id, diff = int(data.dungeon.id), int(data.dungeon.difficulty) or 1
		if not id or id < 1 or id > 9999 then
			return nil, "That dungeon does not exist."
		end
		if diff < 1 or diff > cfg.maxDifficulty then
			return nil, "That difficulty does not exist."
		end
		picks[#picks + 1] = {key = "dungeon", id = id, difficulty = diff}
	end
	if #picks == 0 then
		return nil, "Pick at least one queue."
	end
	return picks
end

function K.groupOf(state, cid)
	local id = state.of[cid]
	return id and state.groups[id] or nil
end

function K.pickOf(g, key)
	for _, p in ipairs(g and g.picks or {}) do
		if p.key == key then
			return p
		end
	end
	return nil
end

-- true when the player's group holds both modes (their queues may stand side by side)
function K.shares(state, cid, a, b)
	local g = K.groupOf(state, cid)
	return g ~= nil and K.pickOf(g, a) ~= nil and K.pickOf(g, b) ~= nil
end

-- a new group; nil when a member is in another group already (or nobody is given)
function K.add(state, leader, members, picks, now)
	if type(members) ~= "table" or #members == 0 then
		return nil
	end
	for _, cid in ipairs(members) do
		if state.of[cid] then
			return nil
		end
	end
	state.seq = state.seq + 1
	local g = {id = state.seq, leader = leader, members = {}, picks = {}, joined = now}
	for i, cid in ipairs(members) do
		g.members[i] = cid
		state.of[cid] = g.id
	end
	for i, p in ipairs(picks or {}) do
		g.picks[i] = p
	end
	state.groups[g.id] = g
	return g
end

function K.remove(state, g)
	if not g or state.groups[g.id] ~= g then
		return false
	end
	state.groups[g.id] = nil
	for _, cid in ipairs(g.members) do
		if state.of[cid] == g.id then
			state.of[cid] = nil
		end
	end
	return true
end

-- a pick the group no longer holds (the mode dropped it, or the join failed); returns the picks left
function K.dropPick(state, g, key)
	for i = #g.picks, 1, -1 do
		if g.picks[i].key == key then
			table.remove(g.picks, i)
		end
	end
	if g.check and g.check.key == key then
		g.check = nil
	end
	if g.confirmed and g.confirmed.key == key then
		g.confirmed = nil
	end
	return #g.picks
end

function K.needsCheck(cfg, g)
	return #g.members > 1 or cfg.soloReadyCheck == true
end

function K.startCheck(cfg, g, key, now)
	g.check = {key = key, started = now, deadline = now + cfg.readyCheckSeconds, answers = {}}
	g.confirmed = nil
	return g.check
end

-- a mode found a match for the players `cids` (creature ids, every side): see the header
function K.gate(state, cfg, key, cids, now)
	local seen, groups = {}, {}
	for _, cid in ipairs(cids or {}) do
		local g = K.groupOf(state, cid)
		if g and not seen[g.id] then
			seen[g.id] = true
			groups[#groups + 1] = g
		end
	end
	if #groups == 0 then
		return "free", groups
	end
	local started, waiting = {}, false
	for _, g in ipairs(groups) do
		if g.check then
			waiting = true -- its check (for this mode or another) is still open
		elseif g.confirmed and now <= g.confirmed.untilAt then
			if g.confirmed.key ~= key then
				waiting = true -- accepted for another mode, which starts on its next try
			end
		elseif K.needsCheck(cfg, g) then
			K.startCheck(cfg, g, key, now)
			started[#started + 1] = g
			waiting = true
		end
	end
	if waiting then
		return "wait", started
	end
	return "go", groups
end

-- a member answers the open ready check of the group.
-- Returns nil (no check, not a member, answered already, too late), or
--   "accepted", g        recorded, others still to answer
--   "ready", g, key      everyone accepted: the group holds `key` for confirmSeconds
--   "declined", g, key   the group is removed (the engine leaves all its queues)
function K.answer(state, cfg, cid, accept, now)
	local g = K.groupOf(state, cid)
	local c = g and g.check
	if not c or now > c.deadline or c.answers[cid] ~= nil then
		return nil
	end
	if not accept then
		c.answers[cid] = false
		K.remove(state, g)
		return "declined", g, c.key
	end
	c.answers[cid] = true
	for _, m in ipairs(g.members) do
		if c.answers[m] ~= true then
			return "accepted", g
		end
	end
	g.check = nil
	g.confirmed = {key = c.key, untilAt = now + cfg.confirmSeconds}
	return "ready", g, c.key
end

-- the checks past their deadline: {group, key, missing = {cids}} each, by group id; those groups are removed
function K.expire(state, now)
	local out = {}
	for _, g in pairs(state.groups) do
		if g.check and now > g.check.deadline then
			local missing = {}
			for _, cid in ipairs(g.members) do
				if g.check.answers[cid] ~= true then
					missing[#missing + 1] = cid
				end
			end
			out[#out + 1] = {group = g, key = g.check.key, missing = missing}
		end
	end
	table.sort(out, function(a, b)
		return a.group.id < b.group.id
	end)
	for _, e in ipairs(out) do
		K.remove(state, e.group)
	end
	return out
end

-- a member leaves the group (logout, left the party): during a check that is a decline. Returns the same as K.answer
-- for a decline, or "left", g (the group goes on without the member; removed when nobody is left)
function K.dropMember(state, cfg, cid, now)
	local g = K.groupOf(state, cid)
	if not g then
		return nil
	end
	if g.check then
		local key = g.check.key
		g.check.answers[cid] = false
		K.remove(state, g)
		return "declined", g, key
	end
	for i = #g.members, 1, -1 do
		if g.members[i] == cid then
			table.remove(g.members, i)
		end
	end
	state.of[cid] = nil
	if #g.members == 0 then
		K.remove(state, g)
	end
	return "left", g
end

-- the picks a mode no longer holds: queued(g, pick) -> bool. A raid pick is never in a queue and stays.
-- Returns {group, dropped = {keys}, empty = true when no pick is left (the group is removed)} per changed group
function K.sync(state, queued)
	local ids = {}
	for id in pairs(state.groups) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		local g = state.groups[id]
		local dropped = {}
		for i = #g.picks, 1, -1 do
			local p = g.picks[i]
			if p.key ~= "raid" and not queued(g, p) then
				dropped[#dropped + 1] = p.key
				K.dropPick(state, g, p.key)
			end
		end
		if #dropped > 0 then
			local empty = #g.picks == 0
			if empty then
				K.remove(state, g)
			end
			out[#out + 1] = {group = g, dropped = dropped, empty = empty}
		end
	end
	return out
end

-- what the client shows of the player's group
function K.view(g, cid, now)
	if not g then
		return nil
	end
	local v = {leader = g.leader == cid, size = #g.members, waited = math.max(0, now - (g.joined or now)), picks = {}}
	for i, p in ipairs(g.picks) do
		v.picks[i] = {key = p.key, mode = p.mode, role = p.role, id = p.id, difficulty = p.difficulty}
	end
	local c = g.check
	if c then
		local yes = 0
		for _, m in ipairs(g.members) do
			if c.answers[m] == true then
				yes = yes + 1
			end
		end
		v.check = {key = c.key, left = math.max(0, c.deadline - now), accepted = yes, total = #g.members,
			mine = c.answers[cid] == true}
	end
	if g.confirmed and now <= g.confirmed.untilAt then
		v.ready = g.confirmed.key
	end
	return v
end

return K

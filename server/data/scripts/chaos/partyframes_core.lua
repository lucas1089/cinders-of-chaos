-- partyframes_core.lua: the rules of the party frames (client game_partyframes, extended opcode
-- ChaosOpcodes.partyFrames = 235; the glue is partyframes.lua). Pure Lua, no engine calls; tests/partyframes_test.lua.
--
-- What a viewer is told about the members of its OWN party, every cfg.tickMs:
--   members in range (same party, at most cfg.rangeFloors floors and cfg.rangeSqm squares away):
--       exact health and mana, level, vocation, outfit, the distance, the state flags and their buffs
--   members out of range:
--       health in steps of cfg.farStep percent, no mana, no distance, no buffs; only the floor difference
-- so a far member is still a name and a rough health bar (the minimap already shows where party members are), and the
-- exact numbers are for the ones standing next to you. Nothing is ever sent about anyone outside the party, and the
-- actions a viewer may ask for (kick, pass the leadership, invite) are checked here.
--
-- A member entry (JSON): {i id, n name, lv level, vc vocation id, h health, H max health, m mana, M max mana,
--   p health percent (always), dz floor difference (down is +), d distance in squares (in range only),
--   f flags (1 leader, 2 in fight, 4 dead, 8 connection lost, 16 you), o {t, h, b, l, f, a} outfit, b [{i icon, t 0/1, l ms}]}
-- Lua 5.1 / LuaJIT and 5.3.

ChaosPartyFrames = ChaosPartyFrames or {}
local P = ChaosPartyFrames

P.cfg = {
	tickMs = 500, -- how often a watching viewer is sent the state
	heartbeatMs = 2000, -- an unchanged state is sent again this often, so the client can tell a lost connection from a quiet party
	rangeSqm = 50, -- members closer than this (Chebyshev distance) are "in range"
	rangeFloors = 2, -- and at most this many floors up or down
	farStep = 10, -- far members' health is rounded to this many percent
	maxMembers = 20, -- more than this are never listed
	actionMs = 500, -- the least time between two actions of one viewer
	inviteMs = 2000 -- and between two invitations
}

P.FLAG = {leader = 1, fight = 2, dead = 4, offline = 8, self = 16}

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function pct(hp, max)
	if (max or 0) <= 0 then
		return 0
	end
	return clamp(math.floor(hp * 100 / max + 0.5), 0, 100)
end
P.pct = pct

-- health percent rounded to `step`, but never 0 for a living member and never 100 for a hurt one
function P.farPct(hp, max, step)
	step = step or P.cfg.farStep
	local p = pct(hp, max)
	local r = math.floor(p / step + 0.5) * step
	if hp > 0 and r < step then
		r = step
	end
	if hp < max and r >= 100 then
		r = 100 - step
	end
	return clamp(r, 0, 100)
end

-- range of a member seen by a viewer: in range?, floors (+ down), squares
function P.range(viewer, member, cfg)
	cfg = cfg or P.cfg
	local dz = (member.z or 0) - (viewer.z or 0)
	local d = math.max(math.abs((member.x or 0) - (viewer.x or 0)), math.abs((member.y or 0) - (viewer.y or 0)))
	return math.abs(dz) <= cfg.rangeFloors and d <= cfg.rangeSqm, dz, d
end

function P.flags(member, leaderId, viewerId)
	local f = 0
	if member.id == leaderId then
		f = f + P.FLAG.leader
	end
	if member.fight then
		f = f + P.FLAG.fight
	end
	if (member.hp or 0) <= 0 or member.dead then
		f = f + P.FLAG.dead
	end
	if member.offline then
		f = f + P.FLAG.offline
	end
	if member.id == viewerId then
		f = f + P.FLAG.self
	end
	return f
end

-- the entry of `member` for `viewer` (plain tables: id, name, level, voc, hp, hpMax, mp, mpMax, x, y, z, fight,
-- dead, offline, outfit {t,h,b,l,f,a}, buffs [{i,t,l}])
function P.entry(viewer, member, leaderId, cfg)
	cfg = cfg or P.cfg
	local inRange, dz, d = P.range(viewer, member, cfg)
	local e = {i = member.id, n = member.name, lv = member.level or 0, vc = member.voc or 0,
		p = pct(member.hp or 0, member.hpMax or 0), dz = dz, f = P.flags(member, leaderId, viewer.id), o = member.outfit}
	if inRange or member.id == viewer.id then
		e.h, e.H, e.m, e.M = member.hp or 0, member.hpMax or 0, member.mp or 0, member.mpMax or 0
		e.d = member.id == viewer.id and 0 or d
		e.b = member.buffs
	else
		e.p = P.farPct(member.hp or 0, member.hpMax or 0, cfg.farStep)
		e.far = 1
	end
	return e
end

-- the state payload for a viewer: {leader = id, members = [entry]}. `members` includes the viewer and the leader,
-- the leader first. A viewer that is not in the list gets an empty state (no party).
function P.state(viewer, members, leaderId, cfg)
	cfg = cfg or P.cfg
	local listed = false
	for _, m in ipairs(members) do
		if m.id == viewer.id then
			listed = true
		end
	end
	if not listed or #members < 2 then
		return {members = {}}
	end
	local ordered = {}
	for _, m in ipairs(members) do
		if m.id == leaderId then
			table.insert(ordered, 1, m)
		else
			ordered[#ordered + 1] = m
		end
	end
	local list = {}
	for _, m in ipairs(ordered) do
		if #list < cfg.maxMembers then
			list[#list + 1] = P.entry(viewer, m, leaderId, cfg)
		end
	end
	return {leader = leaderId, members = list}
end

-- a short text that is equal for equal states (what the viewer last got), to send only what changed
function P.signature(state)
	local parts = {tostring(state.leader or 0)}
	for _, e in ipairs(state.members or {}) do
		local buffs = {}
		for _, b in ipairs(e.b or {}) do
			-- a timer ticking down is not a change: the client counts it down
			buffs[#buffs + 1] = tostring(b.i) .. ":" .. tostring(b.t) .. ":" .. tostring(b.n)
		end
		parts[#parts + 1] = table.concat({e.i, e.p, e.h or "-", e.H or "-", e.m or "-", e.M or "-", e.lv, e.f, e.dz,
			e.d or "-", e.far or 0, table.concat(buffs, ",")}, "/")
	end
	return table.concat(parts, "|")
end

-- ------------------------------------------------------------------------------------------------ actions
-- ok, text. memberIds = set of ids in the viewer's party (the leader included).
function P.canKick(viewerId, leaderId, targetId, memberIds)
	if viewerId ~= leaderId then
		return false, "Only the party leader can remove a member."
	end
	if targetId == leaderId then
		return false, "You cannot remove yourself: leave the party instead."
	end
	if not memberIds[targetId] then
		return false, "That player is not in your party."
	end
	return true
end

function P.canPassLeadership(viewerId, leaderId, targetId, memberIds)
	if viewerId ~= leaderId then
		return false, "Only the party leader can pass the leadership."
	end
	if targetId == leaderId then
		return false, "You are the leader already."
	end
	if not memberIds[targetId] then
		return false, "That player is not in your party."
	end
	return true
end

-- name: what the client typed; target: nil or {id, inParty, isSelf, name}; party: nil (the viewer has none) or {leaderId,
-- members, invitees}
function P.canInvite(viewerId, party, targetName, target, maxMembers)
	if type(targetName) ~= "string" or #targetName < 2 or #targetName > 30 then
		return false, "Type the name of the player to invite."
	end
	if party and party.leaderId ~= viewerId then
		return false, "Only the party leader can invite."
	end
	if not target then
		return false, "There is no player called " .. targetName .. " online."
	end
	if target.isSelf then
		return false, "You cannot invite yourself."
	end
	if target.inParty then
		return false, target.name .. " is already in a party."
	end
	if party and party.invited and party.invited[target.id] then
		return false, target.name .. " is already invited."
	end
	if party and (party.members or 0) >= (maxMembers or P.cfg.maxMembers) then
		return false, "Your party is full."
	end
	return true
end

return P

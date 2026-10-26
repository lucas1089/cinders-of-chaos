-- groupnudge_core.lua: the pure rules of the group nudge (groupnudge_config.lua; server/README.md "The group nudge
-- (O261)"). No engine calls; groupnudge.lua is the engine side. Tests: server/tests/groupnudge_test.lua.
-- Works on the Party Finder's state (party_finder_core.lua K.newState: listings, order, queue) and its activities list.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosPartyFinderCore then
	dofile("data/scripts/chaos/party_finder_core.lua")
end

ChaosGroupNudgeCore = ChaosGroupNudgeCore or {}
local N = ChaosGroupNudgeCore
local PF = ChaosPartyFinderCore

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return d or 0
	end
	return v
end

-- does a listing of the activity cover what was entered? detail: the rift tier (a number) or the dungeon's title
local function covers(acts, L, activity, detail)
	if L.a ~= activity then
		return false
	end
	local a = PF.activity(acts, activity)
	if a and a.range then
		local tier = num(detail, -1)
		if tier < 0 then
			return true
		end
		return tier >= num(L.lo) and tier <= num(L.hi)
	end
	if a and a.targets and num(L.t) > 0 and type(detail) == "string" then
		return a.targets[L.t] == detail
	end
	return true
end

-- how many players look for a group for this content, for a player (who as party_finder.lua PF.who):
--   the people of the open listings that cover it (the leader, the party and the accepted ones: they need more) and the
--   players in the quick-join queue for that activity. Listings of the player's own party, closed ones, other realms
--   and the player itself do not count. Returns the number and the activity's label ("Rift T5", "Dungeon: Bones Dungeon").
function N.looking(state, cfg, acts, who, activity, detail)
	local mine = {[who.guid] = true}
	for _, m in ipairs(who.party and who.party.members or {}) do
		mine[m.guid] = true
	end
	local count = 0
	for _, id in ipairs(state.order or {}) do
		local L = state.listings[id]
		if L and PF.visibleTo(L, who) and not mine[L.leader.guid] and covers(acts, L, activity, detail) then
			local _, open = PF.open(cfg, L)
			if open > 0 then
				count = count + PF.size(L)
			end
		end
	end
	for _, guid in ipairs(state.queueOrder or {}) do
		local q = state.queue[guid]
		if q and not mine[guid] and q.a == activity and (who.staff or (q.realm or 0) == (who.realm or 0)) then
			count = count + 1
		end
	end
	return count, N.label(acts, activity, detail)
end

-- "Rift T5", "Dungeon: Bones Dungeon", "Dungeon"
function N.label(acts, activity, detail)
	local a = PF.activity(acts, activity)
	if not a then
		return tostring(activity)
	end
	if a.range and num(detail, -1) >= 0 then
		return string.format("%s %s%d", a.n, a.range.short or "", math.floor(num(detail)))
	end
	if a.targets and type(detail) == "string" and detail ~= "" then
		return a.n .. ": " .. detail
	end
	return a.n
end

-- may this player be nudged now? last = {[key] = time}; true (and the time is recorded) at most once per cooldown
function N.due(last, key, now, cooldown)
	local at = last[key]
	if at and now - at < cooldown then
		return false
	end
	last[key] = now
	return true
end

-- drop the entries older than the cooldown
function N.sweep(last, now, cooldown)
	for key, at in pairs(last) do
		if now - at >= cooldown then
			last[key] = nil
		end
	end
end

-- the size of the entering player's group: its party's members, itself included
function N.groupSize(who)
	return 1 + #(who.party and who.party.members or {})
end

return N

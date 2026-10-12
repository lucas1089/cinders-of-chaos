-- partymarkers_core.lua: the rules of the party markers (client game_mapmarkers, extended opcode
-- ChaosOpcodes.mapMarkers = 153; the glue is partymarkers.lua, the numbers partymarkers_config.lua). Pure Lua, no engine
-- calls; tests/partymarkers_test.lua (diff, throttle, membership edge cases, a cost benchmark).
--
-- Every party member whose client asked for markers (a "watcher") is sent where the members of its party are:
--   {i id, n name, x, y, z, p health percent in cfg.hpStep steps}
-- for every member it may see, itself included (the client leaves its own entry out, so one list serves the whole
-- party and is encoded once). Members on other floors are listed with their own z; the client draws the floor arrow.
-- Far members are listed too: the minimap can be scrolled to them.
-- Who sees whom:
--   * a member in ghost mode (invisible staff) is listed to nobody;
--   * a member with a scope (inside a battleground match: "bg:<match>:<team>") is listed only to watchers of the same
--     scope, so a match's positions stay inside its team; a member without a scope is listed to everyone of the party.
-- A watcher is sent a list only when it differs from the last one it got (positions, floors, health steps, who is in
-- the party); a watcher that left its party (or whose party disbanded) is sent one empty list and then nothing.
-- The throttle: at most cfg.maxPartiesPerTick parties are read per tick and at most cfg.maxSendsPerTick messages go
-- out; the next tick goes on after the last party handled (round robin), so every party is served in turn.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosPartyMarkers = ChaosPartyMarkers or {}
local P = ChaosPartyMarkers

P.defaults = {tickMs = 1000, hpStep = 10, maxMembers = 30, maxPartiesPerTick = 300, maxSendsPerTick = 600, setMs = 500}
P.cfg = P.cfg or P.defaults

local floor = math.floor

-- health percent in `step` steps: 0 only when dead, never 100 for a hurt member, at least one step for a living one
function P.hpPct(hp, max, step)
	hp, max, step = tonumber(hp) or 0, tonumber(max) or 0, tonumber(step) or 10
	if hp <= 0 or max <= 0 then
		return 0
	end
	if hp >= max then
		return 100
	end
	local r = floor(hp * 100 / max / step + 0.5) * step
	if r < step then
		r = step
	end
	if r >= 100 then
		r = 100 - step
	end
	return r
end

-- may a watcher of scope `scope` ("" = none) see member `m`?
function P.visibleTo(m, scope)
	if m.ghost then
		return false
	end
	local s = m.scope or ""
	return s == "" or s == (scope or "")
end

-- the entry of a member (plain table {id, name, x, y, z, hp, hpMax, ghost, scope}); nil without a valid position
function P.entry(m, step)
	local x, y, z = tonumber(m.x), tonumber(m.y), tonumber(m.z)
	if not m.id or not x or not y or not z then
		return nil
	end
	return {i = m.id, n = tostring(m.name or ""), x = floor(x), y = floor(y), z = floor(z), p = P.hpPct(m.hp, m.hpMax, step)}
end

-- equal lists give equal texts (the order is the party's: leader first)
function P.signature(list)
	local parts = {}
	for i, e in ipairs(list) do
		parts[i] = e.i .. ":" .. e.x .. ":" .. e.y .. ":" .. e.z .. ":" .. e.p .. ":" .. e.n
	end
	return table.concat(parts, "|")
end

-- the list a watcher of `scope` gets from `members`, and its signature
function P.listFor(members, scope, cfg)
	cfg = cfg or P.cfg
	local list = {}
	for _, m in ipairs(members) do
		if #list >= (cfg.maxMembers or 30) then
			break
		end
		if P.visibleTo(m, scope) then
			local e = P.entry(m, cfg.hpStep)
			if e then
				list[#list + 1] = e
			end
		end
	end
	return list, P.signature(list)
end

-- One party. sent: watcher id -> signature of its last list (changed in place). members: plain tables in party order.
-- watchers: ids of the members whose clients want markers. force: send even when unchanged (login, option on).
-- Returns the messages to send: {{ids = {...}, list = {...}}, ...} (one per scope that has a change; one encode each).
function P.plan(sent, members, watchers, cfg, force)
	cfg = cfg or P.cfg
	local byId = {}
	for _, m in ipairs(members) do
		byId[m.id] = m
	end
	local groups, out = {}, {}
	for _, id in ipairs(watchers) do
		local me = byId[id]
		if me then
			local scope = me.scope or ""
			local g = groups[scope]
			if not g then
				local list, sig = P.listFor(members, scope, cfg)
				g = {list = list, sig = sig, ids = {}}
				groups[scope] = g
			end
			if force or sent[id] ~= g.sig then
				sent[id] = g.sig
				if #g.ids == 0 then
					out[#out + 1] = g
				end
				g.ids[#g.ids + 1] = id
			end
		end
	end
	local msgs = {}
	for _, g in ipairs(out) do
		msgs[#msgs + 1] = {ids = g.ids, list = g.list}
	end
	return msgs
end

-- keys (sorted) starting after `cursor`, wrapping around: the order of a tick
function P.rotate(keys, cursor)
	if cursor == nil then
		return keys
	end
	local start = #keys + 1
	for i, k in ipairs(keys) do
		if k > cursor then
			start = i
			break
		end
	end
	local out = {}
	for i = start, #keys do
		out[#out + 1] = keys[i]
	end
	for i = 1, start - 1 do
		out[#out + 1] = keys[i]
	end
	return out
end

function P.newState()
	return {sent = {}, cursor = nil}
end

-- One tick.
--   state   P.newState() (kept between ticks)
--   parties party key (the leader's id) -> {watchers = {id, ...}}: every watcher that is in a party now
--   io      read(key) -> plain members in party order (or nil: the party is gone); send(ids, list); clear(id)
-- Returns {parties = read, sends = messages, cleared = n, waiting = parties left for the next tick}.
function P.tick(state, parties, io, cfg)
	cfg = cfg or P.cfg
	local stats = {parties = 0, sends = 0, cleared = 0, waiting = 0}
	local inParty = {}
	local keys = {}
	for key, g in pairs(parties) do
		keys[#keys + 1] = key
		for _, id in ipairs(g.watchers) do
			inParty[id] = true
		end
	end
	-- left the party, the party disbanded, or no longer watching: one empty list
	local gone = {}
	for id in pairs(state.sent) do
		if not inParty[id] then
			gone[#gone + 1] = id
		end
	end
	table.sort(gone)
	for _, id in ipairs(gone) do
		state.sent[id] = nil
		io.clear(id)
		stats.cleared = stats.cleared + 1
	end
	table.sort(keys)
	local order = P.rotate(keys, state.cursor)
	local maxParties, maxSends = cfg.maxPartiesPerTick or 300, cfg.maxSendsPerTick or 600
	for n, key in ipairs(order) do
		if stats.parties >= maxParties or stats.sends + stats.cleared >= maxSends then
			stats.waiting = #order - n + 1
			break
		end
		stats.parties = stats.parties + 1
		state.cursor = key
		local members = io.read(key)
		if members then
			for _, msg in ipairs(P.plan(state.sent, members, parties[key].watchers, cfg, false)) do
				io.send(msg.ids, msg.list)
				stats.sends = stats.sends + #msg.ids
			end
		end
	end
	return stats
end

return P

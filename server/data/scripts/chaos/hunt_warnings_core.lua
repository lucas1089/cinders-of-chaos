-- Hunt warnings, the rules (server/README.md "Hunt warnings (O323)"; tests/hunt_warnings_test.lua). Pure: no engine calls.
-- The places come from hunt_warnings_config.lua (written by server/tools/audit_hunt_transitions.py): entries (a hole, stairs,
-- a ladder, a teleport) that lead to monsters much stronger than the ones round the entry.
--   index    places bucketed by floor, for the entry tile and for the landing tile
--   tick     one pass over the online players: which entries flash their caution effect, and which player gets which message
-- A message is {player id, kind "near" | "arrive", level, group, verdict}; the engine turns it into text in the player's language.
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosHuntWarningsCore = ChaosHuntWarningsCore or {}
local W = ChaosHuntWarningsCore

local function cheb(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- {entries = {[z] = {place...}}, landings = {[z] = {place...}}}; a place without a position is skipped
function W.index(places)
	local idx = {entries = {}, landings = {}, count = 0}
	for _, p in ipairs(places or {}) do
		if p.pos and p.to and p.group then
			local e, l = idx.entries, idx.landings
			e[p.pos.z] = e[p.pos.z] or {}
			e[p.pos.z][#e[p.pos.z] + 1] = p
			l[p.to.z] = l[p.to.z] or {}
			l[p.to.z][#l[p.to.z] + 1] = p
			idx.count = idx.count + 1
		end
	end
	return idx
end

function W.newState()
	return {last = {}, ticks = 0}
end

function W.forget(state, playerId)
	state.last[playerId] = nil
end

local function severity(p)
	return p.verdict == "extreme" and 2 or 1
end

-- players: list of {id, pos = {x, y, z}, lastWarn = os.time of the last message (0 none), ghost}
-- returns {effects = {{pos, extreme}...}, messages = {{id, kind, level, group, verdict}...}}
-- state.last[player id][kind .. group] = the time of the last message of that kind for that area
function W.tick(idx, cfg, state, players, now)
	state.ticks = state.ticks + 1
	local out = {effects = {}, messages = {}}
	if not cfg.enabled or idx.count == 0 then
		return out
	end
	local present = {}
	for _, pl in ipairs(players) do
		present[pl.id] = true
	end
	for id in pairs(state.last) do
		if not present[id] then
			state.last[id] = nil -- logged out: the memory of this session goes
		end
	end
	local showEffects = state.ticks % math.max(1, cfg.effectEveryTicks or 1) == 0
	local flashed = {}
	for _, pl in ipairs(players) do
		if not (cfg.skipGhost and pl.ghost) then
			local pos = pl.pos
			if showEffects then
				for _, p in ipairs(idx.entries[pos.z] or {}) do
					if not flashed[p.id] and cheb(p.pos, pos) <= cfg.effectRadius then
						flashed[p.id] = true
						out.effects[#out.effects + 1] = {pos = p.pos, extreme = p.verdict == "extreme"}
					end
				end
			end
			-- at most one message per player per tick: the strongest area, the near kind before the arrival kind
			local best
			local mine = state.last[pl.id]
			local function consider(p, kind, radius, at)
				if cheb(at, pos) > radius then
					return
				end
				local key = kind .. p.group
				local t = mine and mine[key]
				if t and now - t < cfg.cooldownSeconds then
					return
				end
				local rank = severity(p) * 10 + (kind == "arrive" and 5 or 0) + p.level / 10000
				if not best or rank > best.rank then
					best = {rank = rank, key = key, kind = kind, p = p}
				end
			end
			for _, p in ipairs(idx.entries[pos.z] or {}) do
				consider(p, "near", cfg.warnRadius, p.pos)
			end
			for _, p in ipairs(idx.landings[pos.z] or {}) do
				consider(p, "arrive", cfg.arriveRadius, p.to)
			end
			if best and now - (pl.lastWarn or 0) >= cfg.minGapSeconds then
				state.last[pl.id] = state.last[pl.id] or {}
				state.last[pl.id][best.key] = now
				out.messages[#out.messages + 1] = {id = pl.id, kind = best.kind, level = best.p.level, group = best.p.group,
					verdict = best.p.verdict}
			end
		end
	end
	return out
end

-- problems in a config: {text...}; none when it is usable
function W.validate(cfg)
	local bad = {}
	local ids = {}
	for i, p in ipairs(cfg.places or {}) do
		local where = "place " .. i
		if not (p.pos and p.pos.x and p.pos.y and p.pos.z) then
			bad[#bad + 1] = where .. " has no pos"
		end
		if not (p.to and p.to.x and p.to.y and p.to.z) then
			bad[#bad + 1] = where .. " has no to"
		end
		if type(p.level) ~= "number" or p.level < 1 then
			bad[#bad + 1] = where .. " has no level"
		end
		if p.verdict ~= "danger" and p.verdict ~= "extreme" then
			bad[#bad + 1] = where .. " has verdict " .. tostring(p.verdict)
		end
		if p.id then
			if ids[p.id] then
				bad[#bad + 1] = where .. " repeats id " .. tostring(p.id)
			end
			ids[p.id] = true
		end
	end
	return bad
end

return W

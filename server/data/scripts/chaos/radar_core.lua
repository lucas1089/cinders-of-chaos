-- radar_core.lua: the rules of the minimap radar (client game_minimapdots, extended opcode ChaosOpcodes.mapMarkers = 153, action
-- `radar`; the glue is radar.lua, the numbers radar_config.lua). Pure Lua, no engine calls; tests/radar_test.lua.
--
-- A watcher is a player whose client switched the radar on (the option "Monsters on the minimap", sent only while the minimap
-- window is visible). Every cfg.intervalMs the creatures within cfg.radius tiles (a circle) on the watcher's floor are listed:
--   {x, y, f}   f bits: 1 boss, 2 NPC, 4 party member; monsters are 0
-- with the watcher's floor `z` and the radius `r` once per message. Positions are absolute, so a message only changes when
-- something moved: a list equal to the last one sent is not sent again; a watcher whose list became empty is sent one empty
-- list and then nothing.
-- Who is listed: monsters (a summon of a player only with cfg.summons), NPCs (cfg.npcs), the watcher's own party on the same
-- floor (cfg.party). Never other players and never a creature in ghost mode. A boss carries f = 1 when cfg.bosses. When more
-- than cfg.cap qualify, bosses come first, then party, NPCs, then monsters nearest first; the rest is cut.
-- This is information the game screen does not give (monsters behind walls, far away): see server/README.md "Minimap radar
-- (O543)" for what a bot could do with it.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosRadar = ChaosRadar or {}
local R = ChaosRadar

R.defaults = {radius = 30, intervalMs = 1500, tickMs = 500, cap = 120, maxCap = 400, maxPerTick = 300, npcs = true, party = true,
	bosses = true, summons = false, offInInstances = false, offAreas = {}, round = 1, setMs = 500}
R.cfg = R.cfg or R.defaults

R.BOSS, R.NPC, R.PARTY = 1, 2, 4

local floor = math.floor

local function num(v, default, lo, hi)
	v = tonumber(v)
	if not v or v ~= v then
		v = default
	end
	if lo and v < lo then
		v = lo
	end
	if hi and v > hi then
		v = hi
	end
	return v
end

-- the config with every number clamped to something that cannot hurt the server or the 8192 byte message limit
function R.sanitize(cfg)
	cfg = cfg or {}
	local d = R.defaults
	local maxCap = floor(num(cfg.maxCap, d.maxCap, 1, 400))
	local out = {
		radius = floor(num(cfg.radius, d.radius, 1, 60)),
		intervalMs = floor(num(cfg.intervalMs, d.intervalMs, 250, 60000)),
		tickMs = floor(num(cfg.tickMs, d.tickMs, 100, 10000)),
		maxCap = maxCap,
		maxPerTick = floor(num(cfg.maxPerTick, d.maxPerTick, 1, 5000)),
		round = floor(num(cfg.round, d.round, 1, 8)),
		setMs = floor(num(cfg.setMs, d.setMs, 0, 60000)),
		offAreas = type(cfg.offAreas) == "table" and cfg.offAreas or {}
	}
	out.cap = floor(num(cfg.cap, d.cap, 1, maxCap))
	for _, k in ipairs({"npcs", "party", "bosses"}) do
		if cfg[k] == nil then
			out[k] = d[k]
		else
			out[k] = cfg[k] == true
		end
	end
	out.summons = cfg.summons == true
	out.offInInstances = cfg.offInInstances == true
	return out
end

-- is the point inside one of the rectangles with no radar?
function R.inOffArea(x, y, z, areas)
	for _, a in ipairs(areas or {}) do
		local f, t = a.from, a.to
		if f and t and z == f.z and z == t.z then
			local x1, x2 = math.min(f.x, t.x), math.max(f.x, t.x)
			local y1, y2 = math.min(f.y, t.y), math.max(f.y, t.y)
			if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
				return true
			end
		end
	end
	return false
end

local function roundTo(v, step)
	if step <= 1 then
		return v
	end
	return floor(v / step + 0.5) * step
end

-- the dots of a watcher: viewer {x, y, z}; entries = [{x, y, z, boss, npc, party, summon, ghost}]; a plain list [{x, y, f}]
function R.plan(viewer, entries, cfg)
	cfg = cfg or R.cfg
	local list = {}
	local r2 = cfg.radius * cfg.radius
	for _, e in ipairs(entries or {}) do
		local ok = e.z == viewer.z and not e.ghost
		local kind = 3
		if ok then
			if e.party then
				ok, kind = cfg.party, 1
			elseif e.npc then
				ok, kind = cfg.npcs, 2
			elseif e.summon then
				ok = cfg.summons
			elseif e.boss and cfg.bosses then
				kind = 0
			end
		end
		if ok then
			local dx, dy = e.x - viewer.x, e.y - viewer.y
			local d2 = dx * dx + dy * dy
			if d2 <= r2 then
				local f = 0
				if kind == 0 then
					f = R.BOSS
				elseif kind == 1 then
					f = R.PARTY
				elseif kind == 2 then
					f = R.NPC
				end
				list[#list + 1] = {x = roundTo(e.x, cfg.round), y = roundTo(e.y, cfg.round), f = f, kind = kind, d2 = d2}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		if a.d2 ~= b.d2 then
			return a.d2 < b.d2
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.y < b.y
	end)
	local out = {}
	for i = 1, math.min(#list, cfg.cap) do
		out[i] = {list[i].x, list[i].y, list[i].f}
	end
	return out
end

-- the message body of a list: {z, r, m = [[x, y, f], ...]}
function R.payload(viewer, list, cfg)
	cfg = cfg or R.cfg
	return {z = viewer.z, r = cfg.radius, m = list}
end

-- a string that is equal for equal lists (and floors), to skip a message that would change nothing
function R.key(viewer, list)
	local parts = {tostring(viewer.z)}
	for i, d in ipairs(list) do
		parts[i + 1] = d[1] .. "," .. d[2] .. "," .. d[3]
	end
	return table.concat(parts, ";")
end

function R.newState()
	return {watch = {}, sent = {}, last = {}, cursor = 0}
end

-- one scheduler tick. state.watch: id -> true. io.collect(id) -> viewer {x, y, z}, entries, off (true: no radar here) or nil
-- when the player is gone; io.send(id, payload). now in ms. Returns {looked, sends, due}.
function R.tick(state, io, cfg, now)
	cfg = cfg or R.cfg
	local ids = {}
	for id in pairs(state.watch) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local stats = {looked = 0, sends = 0, due = 0}
	if #ids == 0 then
		return stats
	end
	-- round robin: start after the last id handled
	local start = 1
	for i, id in ipairs(ids) do
		if id > state.cursor then
			start = i
			break
		end
	end
	local handled = 0
	for k = 0, #ids - 1 do
		local id = ids[((start - 1 + k) % #ids) + 1]
		local last = state.last[id]
		if not last or now - last >= cfg.intervalMs then
			stats.due = stats.due + 1
			if handled >= cfg.maxPerTick then
				break
			end
			handled = handled + 1
			state.cursor = id
			state.last[id] = now
			local viewer, entries, off = io.collect(id)
			stats.looked = stats.looked + 1
			if not viewer then
				state.watch[id], state.sent[id], state.last[id] = nil, nil, nil
			else
				local list = off and {} or R.plan(viewer, entries, cfg)
				local key = R.key(viewer, list)
				local prev = state.sent[id]
				-- a changed list goes out; a new watcher gets its first list (empty or not), a list that became empty goes out once
				if key ~= prev then
					state.sent[id] = key
					io.send(id, R.payload(viewer, list, cfg))
					stats.sends = stats.sends + 1
				end
			end
		end
	end
	return stats
end

-- a watcher switches on (the first list goes out at the next tick) or off (one empty list so its dots vanish)
function R.setWatch(state, id, on)
	if on then
		state.watch[id] = true
		state.last[id] = nil
		state.sent[id] = nil
		return true
	end
	local was = state.watch[id]
	state.watch[id], state.last[id], state.sent[id] = nil, nil, nil
	return was == true
end


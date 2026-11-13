-- telegraph_core.lua: the rules of the floor telegraphs (glue: telegraph.lua; client game_telegraph; server/README.md
-- "Floor telegraphs (O549)"). Pure Lua, no engine calls; tests/telegraph_test.lua.
--
-- A boss attack marks its tiles on the floor: a flat translucent fill and a bright line round the whole area, drawn by the
-- client (game_telegraph). The client says hello once; the sprite pulses of a telegraph (warning_zone, warning_fill, the red
-- circles) then go only to the players near it that did not.
--   server -> client  floor {id, z, x0, y0, t = [[dx, dy]], c = colour key, ms = ms to the hit}   (the area, sent once to
--                     every capable player near it; again, whole, when a follow circle moves or locks)
--                     floorclear {id}                                                            (the hit came, the fight ended,
--                     the player walked away)
--   client -> server  floorhello {v = 1}                                                         (this client draws floor marks)
-- All on the monster bar's opcode 125 (ChaosOpcodes.monsterbar): no new number.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosTelegraphCore = ChaosTelegraphCore or {}
local K = ChaosTelegraphCore

local floor, max, min = math.floor, math.max, math.min

function K.newState()
	return {marks = {}, count = 0, capable = {}}
end

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return floor(v)
end

-- an id: a short string of letters, digits and : _ - . (nil for anything else)
function K.validId(id, cfg)
	if type(id) ~= "string" or id == "" or #id > ((cfg and cfg.maxIdLength) or 64) then
		return nil
	end
	if id:find("[^%w:_%-%.]") then
		return nil
	end
	return id
end

-- a colour key of the config, else the default
function K.colorOf(c, cfg)
	if type(c) == "string" and cfg.colors and cfg.colors[c] then
		return c
	end
	return cfg.defaultColor or "orange"
end

-- the union of a tile list, dropping what is not on the floor of the first valid tile ({x, y, z} or {x, y}); sorted by row,
-- then column, so the same area always makes the same payload. Returns {list = {{x, y}}, z, x1, y1, x2, y2} or nil, reason.
function K.normalize(tiles, cfg)
	if type(tiles) ~= "table" then
		return nil, "no tiles"
	end
	local z
	local seen, list = {}, {}
	for _, t in ipairs(tiles) do
		if type(t) == "table" then
			local x, y, tz = int(t.x or t[1]), int(t.y or t[2]), int(t.z or t[3])
			if x and y and x >= 0 and y >= 0 and x <= 65535 and y <= 65535 then
				if z == nil and tz then
					z = tz
				end
				if (tz == nil or tz == z) and z ~= nil and z >= 0 and z <= 15 then
					local k = y * 65536 + x
					if not seen[k] then
						seen[k] = true
						list[#list + 1] = {x = x, y = y}
					end
				end
			end
		end
	end
	if #list == 0 then
		return nil, "no tiles"
	end
	if #list > ((cfg and cfg.maxTiles) or 300) then
		return nil, "too many tiles"
	end
	table.sort(list, function(a, b)
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a.x < b.x
	end)
	local x1, y1, x2, y2 = list[1].x, list[1].y, list[1].x, list[1].y
	for _, t in ipairs(list) do
		x1, x2, y1, y2 = min(x1, t.x), max(x2, t.x), min(y1, t.y), max(y2, t.y)
	end
	return {list = list, z = z, x1 = x1, y1 = y1, x2 = x2, y2 = y2}
end

-- the tiles of the union that border an unmarked tile, with the sides (bit 1 up, 2 right, 4 down, 8 left): the line the
-- client draws. Here for the tests and the README table; the client works the same out of the tiles alone
-- (game_telegraph telegraph_logic.lua edgeMask).
function K.outline(list)
	local set = {}
	for _, t in ipairs(list) do
		set[t.x .. "," .. t.y] = true
	end
	local out = {}
	for _, t in ipairs(list) do
		local m = 0
		if not set[t.x .. "," .. (t.y - 1)] then
			m = m + 1
		end
		if not set[(t.x + 1) .. "," .. t.y] then
			m = m + 2
		end
		if not set[t.x .. "," .. (t.y + 1)] then
			m = m + 4
		end
		if not set[(t.x - 1) .. "," .. t.y] then
			m = m + 8
		end
		if m ~= 0 then
			out[#out + 1] = {x = t.x, y = t.y, m = m}
		end
	end
	return out
end

-- the centre tile of the area's bounding box and how far it reaches from there ({cx, cy, hx, hy})
local function reach(n)
	return {cx = floor((n.x1 + n.x2) / 2), cy = floor((n.y1 + n.y2) / 2), hx = floor((n.x2 - n.x1) / 2) + 1,
		hy = floor((n.y2 - n.y1) / 2) + 1}
end

-- open (or replace) a mark. ms = time to the hit; opts = {color}. Returns the mark, or nil and the reason (the caller then
-- draws the sprite marks for everybody).
function K.open(st, id, tiles, ms, now, cfg, opts)
	if not K.validId(id, cfg) then
		return nil, "bad id"
	end
	local n, why = K.normalize(tiles, cfg)
	if not n then
		return nil, why
	end
	ms = int(ms)
	if not ms or ms < (cfg.minMs or 100) or ms > (cfg.maxMs or 12000) then
		return nil, "bad time"
	end
	local old = st.marks[id]
	if not old then
		if st.count >= (cfg.maxMarks or 60) then
			return nil, "too many marks"
		end
		st.count = st.count + 1
	end
	local r = reach(n)
	local m = {id = id, list = n.list, z = n.z, x1 = n.x1, y1 = n.y1, x2 = n.x2, y2 = n.y2, cx = r.cx, cy = r.cy, hx = r.hx,
		hy = r.hy, color = K.colorOf(opts and opts.color, cfg), hitAt = now + ms, sent = old and old.sent or {}}
	-- a replaced mark goes out again, whole, to everyone
	for cid in pairs(m.sent) do
		m.sent[cid] = false
	end
	st.marks[id] = m
	return m
end

-- a follow circle moved or locked: new tiles, the same hit time unless ms is given. Everyone near gets it again, whole.
function K.move(st, id, tiles, now, cfg, ms)
	local old = st.marks[id]
	if not old then
		return nil, "no such mark"
	end
	local n, why = K.normalize(tiles, cfg)
	if not n then
		return nil, why
	end
	local r = reach(n)
	old.list, old.z, old.x1, old.y1, old.x2, old.y2 = n.list, n.z, n.x1, n.y1, n.x2, n.y2
	old.cx, old.cy, old.hx, old.hy = r.cx, r.cy, r.hx, r.hy
	ms = int(ms)
	if ms and ms >= 0 then
		old.hitAt = now + ms
	end
	for cid in pairs(old.sent) do
		old.sent[cid] = false
	end
	return old
end

-- the message the client gets for a mark
function K.payload(m, now)
	local t = {}
	for i, tile in ipairs(m.list) do
		t[i] = {tile.x - m.x1, tile.y - m.y1}
	end
	return {id = m.id, z = m.z, x0 = m.x1, y0 = m.y1, t = t, c = m.color, ms = max(0, m.hitAt - now)}
end

function K.clearPayload(id)
	return {id = id}
end

-- drop a mark; the ids of the players that have it on their screen ({cid = ...}), to be told to clear it
function K.close(st, id)
	local m = st.marks[id]
	if not m then
		return {}
	end
	st.marks[id] = nil
	st.count = st.count - 1
	local out = {}
	for cid, has in pairs(m.sent) do
		if has then
			out[#out + 1] = {cid = cid, id = id}
		end
	end
	table.sort(out, function(a, b)
		return a.cid < b.cid
	end)
	return out
end

-- every mark whose id starts with prefix (a fight's marks): the clears to send
function K.closePrefix(st, prefix)
	local ids = {}
	for id in pairs(st.marks) do
		if id:sub(1, #prefix) == prefix then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		for _, c in ipairs(K.close(st, id)) do
			out[#out + 1] = c
		end
	end
	return out
end

-- marks past their hit time (plus the grace) are dropped: the clears to send
function K.expire(st, now, cfg)
	local ids = {}
	for id, m in pairs(st.marks) do
		if now >= m.hitAt + (cfg.graceMs or 300) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		for _, c in ipairs(K.close(st, id)) do
			out[#out + 1] = c
		end
	end
	return out
end

-- capable clients (the ones that said hello)
function K.setCapable(st, cid, on)
	st.capable[cid] = on and true or nil
end

function K.isCapable(st, cid)
	return st.capable[cid] == true
end

-- a player logged out (or logged in again): nothing is on its screen, it is not capable until it says hello
function K.forget(st, cid)
	st.capable[cid] = nil
	for _, m in pairs(st.marks) do
		m.sent[cid] = nil
	end
end

-- a client message: true for a hello of a client that draws floor marks
function K.clientHello(msg)
	if type(msg) ~= "table" or msg.action ~= "floorhello" then
		return false
	end
	local v = type(msg.data) == "table" and int(msg.data.v) or 1
	return v ~= nil and v >= 1
end

-- what each capable player near a mark has to be told. viewersOf(mark) -> {cid = true} (the capable players that can see
-- the mark now). Returns a list of {cid, action = "floor" | "floorclear", data}; marks them sent.
function K.plan(st, viewersOf, now)
	local out = {}
	local ids = {}
	for id in pairs(st.marks) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local m = st.marks[id]
		local seeing = viewersOf(m) or {}
		local cids = {}
		for cid in pairs(seeing) do
			cids[#cids + 1] = cid
		end
		table.sort(cids)
		local payload
		for _, cid in ipairs(cids) do
			if m.sent[cid] ~= true then
				payload = payload or K.payload(m, now)
				out[#out + 1] = {cid = cid, action = "floor", data = payload}
				m.sent[cid] = true
			end
		end
		local gone = {}
		for cid, has in pairs(m.sent) do
			if not seeing[cid] then
				if has then
					gone[#gone + 1] = cid
				end
				m.sent[cid] = nil
			end
		end
		table.sort(gone)
		for _, cid in ipairs(gone) do
			out[#out + 1] = {cid = cid, action = "floorclear", data = K.clearPayload(id)}
		end
	end
	return out
end

-- how a telegraph draws its sprite marks, given the players that see it now: "all" (nobody drew floor marks: send the
-- effects to everybody, exactly as before), "none" (everybody did), "some" (only to the ones that did not: legacy list)
function K.spriteMode(capableN, legacyN)
	if capableN <= 0 then
		return "all"
	end
	if legacyN <= 0 then
		return "none"
	end
	return "some"
end

return K

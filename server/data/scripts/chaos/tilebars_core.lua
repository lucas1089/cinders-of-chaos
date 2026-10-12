-- tilebars_core.lua: the rules of the progress bars over tiles (glue: tilebars.lua; client game_tileoverlays; extended
-- opcode ChaosOpcodes.tileBars = 156; server/README.md "Progress bars over tiles"). Pure Lua, no engine calls;
-- tests/tilebars_test.lua.
--
-- A bar is {pos, label, progress 0..1 | a countdown, colour, owner}. Scripts set, update and remove bars by id; the
-- send loop asks plan() what each nearby player has to be told:
--   server -> client  bars {s = [{i, p = [x, y, z], n, c, v | l + t}], d = [ids]}     (v progress 0..1; l ms left,
--                     t ms in all of a countdown; the client counts a countdown down by itself)
--                     clear {}                                                          (forget every bar)
--   client -> server  hello {}                                                          (send me everything again)
-- Only players on the bar's floor within rangeX / rangeY tiles get it (and only the owner, when it has one); a player who
-- walks away gets the id in d, and the bar again when back. A change of the progress alone reaches a player at most
-- every progressMs and only when it moved by minStep (or reached 0 or 1); everything else goes out on the next tick.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosTileBarsCore = ChaosTileBarsCore or {}
local K = ChaosTileBarsCore

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

function K.newState()
	return {bars = {}, count = 0, known = {}}
end

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return floor(v)
end

local function posOf(p)
	if type(p) ~= "table" then
		return nil
	end
	local x, y, z = int(p.x or p[1]), int(p.y or p[2]), int(p.z or p[3])
	if not x or not y or not z or x < 0 or y < 0 or z < 0 or z > 15 or x > 65535 or y > 65535 then
		return nil
	end
	return {x = x, y = y, z = z}
end
K.posOf = posOf

-- "#rrggbb" (any case) or nil
function K.color(c)
	if type(c) == "string" and c:match("^#%x%x%x%x%x%x$") then
		return c:lower()
	end
	return nil
end

-- the label: text only, no line breaks, at most cfg.labelMax characters
function K.label(s, cfg)
	if s == nil then
		return ""
	end
	s = tostring(s):gsub("[%c]", " ")
	local n = cfg and cfg.labelMax or 32
	if #s > n then
		s = s:sub(1, n)
	end
	return s
end

function K.validId(id, cfg)
	return type(id) == "string" and #id > 0 and #id <= (cfg and cfg.maxIdLength or 64)
end

-- the bar a script's definition asks for, or nil and why. def = {pos, label, progress | endsIn (s) [, total (s)],
-- color, owner = {name, guid} | nil, keep}. A countdown is endsIn seconds from now; total is the whole length it is
-- drawn against (default endsIn).
function K.normalize(def, cfg, nowMs)
	if type(def) ~= "table" then
		return nil, "no definition"
	end
	local pos = posOf(def.pos)
	if not pos then
		return nil, "bad position"
	end
	local color = K.color(def.color) or cfg.defaultColor or "#d8b45a"
	local bar = {pos = pos, label = K.label(def.label, cfg), color = color, keep = def.keep == true}
	local endsIn = tonumber(def.endsIn)
	if endsIn then
		if endsIn ~= endsIn or endsIn < 0 then
			return nil, "bad countdown"
		end
		local total = tonumber(def.total) or endsIn
		if total ~= total or total <= 0 then
			total = max(endsIn, 0.001)
		end
		bar.endMs = nowMs + floor(endsIn * 1000 + 0.5)
		bar.totalMs = max(1, floor(max(total, endsIn) * 1000 + 0.5))
	else
		local v = tonumber(def.progress) or 0
		if v ~= v then
			v = 0
		end
		bar.v = min(1, max(0, v))
	end
	if type(def.owner) == "table" and (def.owner.name or def.owner.guid) then
		bar.owner = {name = def.owner.name, guid = tonumber(def.owner.guid)}
	end
	return bar
end

local function samePos(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

local function sameOwner(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.name == b.name and a.guid == b.guid
end

-- set (create or update) bar id. Returns "new", "full" (something the client draws besides the progress changed),
-- "progress", nil (nothing to send) or false and why (refused).
function K.set(st, id, def, cfg, nowMs)
	if not K.validId(id, cfg) then
		return false, "bad id"
	end
	local bar, err = K.normalize(def, cfg, nowMs)
	if not bar then
		return false, err
	end
	local old = st.bars[id]
	if not old then
		if st.count >= (cfg.maxBars or 500) then
			return false, "too many bars"
		end
		bar.ver, bar.pver, bar.pv = 1, 1, bar.v
		st.bars[id] = bar
		st.count = st.count + 1
		return "new"
	end
	local full = not samePos(old.pos, bar.pos) or old.label ~= bar.label or old.color ~= bar.color
		or not sameOwner(old.owner, bar.owner) or (old.v == nil) ~= (bar.v == nil)
	-- a countdown counts as changed when it moved by more than a tick (a script that sets the same end again is quiet)
	if not full and bar.endMs and (abs(bar.endMs - old.endMs) > (cfg.tickMs or 250) or bar.totalMs ~= old.totalMs) then
		full = true
	end
	if full then
		bar.ver, bar.pver, bar.pv = old.ver + 1, old.pver + 1, bar.v
		st.bars[id] = bar
		return "full"
	end
	old.keep = bar.keep
	if bar.v ~= nil and bar.v ~= old.v then
		old.v = bar.v
		local edge = (bar.v == 0 or bar.v == 1) and bar.v ~= old.pv
		if edge or abs(bar.v - (old.pv or 0)) >= (cfg.minStep or 0.01) then
			old.pver = old.pver + 1
			old.pv = bar.v
			return "progress"
		end
	end
	return nil
end

-- the progress alone (a capture tick); same as set with the bar's other fields kept
function K.setProgress(st, id, v, cfg, nowMs)
	local b = st.bars[id]
	if not b or b.v == nil then
		return false, "no progress bar"
	end
	return K.set(st, id, {pos = b.pos, label = b.label, color = b.color, owner = b.owner, keep = b.keep, progress = v},
		cfg, nowMs)
end

function K.remove(st, id)
	if st.bars[id] then
		st.bars[id] = nil
		st.count = st.count - 1
		return true
	end
	return false
end

-- every bar whose id starts with prefix (the bars of one match); returns how many
function K.removePrefix(st, prefix)
	local list = {}
	for id in pairs(st.bars) do
		if id:sub(1, #prefix) == prefix then
			list[#list + 1] = id
		end
	end
	for _, id in ipairs(list) do
		K.remove(st, id)
	end
	return #list
end

-- countdowns that ran out (expireGraceMs ago) and were not set with keep: removed, their ids returned (sorted)
function K.expire(st, cfg, nowMs)
	local gone = {}
	for id, b in pairs(st.bars) do
		if b.endMs and not b.keep and nowMs >= b.endMs + (cfg.expireGraceMs or 1000) then
			gone[#gone + 1] = id
		end
	end
	table.sort(gone)
	for _, id in ipairs(gone) do
		K.remove(st, id)
	end
	return gone
end

-- the wire form of a bar for one message at nowMs
function K.wire(id, b, nowMs)
	local w = {i = id, p = {b.pos.x, b.pos.y, b.pos.z}, n = b.label, c = b.color}
	if b.endMs then
		w.l = max(0, b.endMs - nowMs)
		w.t = b.totalMs
	else
		w.v = floor(b.v * 1000 + 0.5) / 1000
	end
	return w
end

-- may this viewer {name, guid, pos} see bar b (owner and range)
function K.visible(b, viewer, cfg)
	local p = viewer.pos
	if not p or p.z ~= b.pos.z then
		return false
	end
	if abs(p.x - b.pos.x) > (cfg.rangeX or 9) or abs(p.y - b.pos.y) > (cfg.rangeY or 7) then
		return false
	end
	if b.owner then
		if b.owner.guid and viewer.guid ~= b.owner.guid then
			return false
		end
		if b.owner.name and viewer.name ~= b.owner.name then
			return false
		end
	end
	return true
end

-- the player logged out or asked for everything again (hello): nothing is known on that side any more
function K.forget(st, cid)
	st.known[cid] = nil
end

local function sortedIds(t)
	local ids = {}
	for id in pairs(t) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

-- what to tell whom. viewers = list of {cid, name, guid, pos}: every player near a bar or owning one, and every
-- player known to hold bars (so the ones who walked away hear about it). Returns a list of
-- {cid, s = {wire bars}, d = {ids}} (only players with something to hear) and updates what each one knows.
function K.plan(st, viewers, cfg, nowMs)
	local out = {}
	local ids = sortedIds(st.bars)
	local seen = {}
	for _, viewer in ipairs(viewers) do
		local cid = viewer.cid
		if cid ~= nil and not seen[cid] then
			seen[cid] = true
			local known = st.known[cid] or {}
			local s, d = {}, {}
			local now = {}
			for _, id in ipairs(ids) do
				local b = st.bars[id]
				if K.visible(b, viewer, cfg) then
					now[id] = true
					local k = known[id]
					if not k or k.ver ~= b.ver then
						s[#s + 1] = K.wire(id, b, nowMs)
						known[id] = {ver = b.ver, pver = b.pver, at = nowMs}
					elseif k.pver ~= b.pver and nowMs - k.at >= (cfg.progressMs or 500) then
						s[#s + 1] = K.wire(id, b, nowMs)
						k.pver, k.at = b.pver, nowMs
					end
				end
			end
			for _, id in ipairs(sortedIds(known)) do
				if not now[id] then
					d[#d + 1] = id
					known[id] = nil
				end
			end
			st.known[cid] = next(known) and known or nil
			if #s > 0 or #d > 0 then
				out[#out + 1] = {cid = cid, s = s, d = d}
			end
		end
	end
	return out
end

-- one plan entry as messages of at most cfg.perMessage bars (and ids) each: list of data tables {s, d}
function K.messages(entry, cfg)
	local n = cfg.perMessage or 40
	local msgs = {}
	local cur
	local function take()
		if not cur or #cur.s + #cur.d >= n then
			cur = {s = {}, d = {}}
			msgs[#msgs + 1] = cur
		end
		return cur
	end
	for _, id in ipairs(entry.d or {}) do
		local m = take()
		m.d[#m.d + 1] = id
	end
	for _, w in ipairs(entry.s or {}) do
		local m = take()
		m.s[#m.s + 1] = w
	end
	return msgs
end

-- the ids of players the send loop must look at besides the spectators of each bar (they hold bars)
function K.knownViewers(st)
	return sortedIds(st.known)
end

-- the client's message: "hello" or nil
function K.clientAction(msg)
	if type(msg) == "table" and msg.action == "hello" then
		return "hello"
	end
	return nil
end

-- battleground brazier bar: progress -100 (team 2) .. 100 (team 1), owner 0 / 1 / 2. Returns the definition.
function K.brazierBar(pos, name, progress, owner, contested, teams)
	local side = progress > 0 and 1 or (progress < 0 and 2 or owner)
	local color = (teams[side] and teams[side].color) or "#bfb6a6"
	local label = name
	if contested then
		label = name .. " (contested)"
		color = "#c8c8c8"
	elseif owner ~= 0 and abs(progress) >= 100 then
		label = name .. ": " .. (teams[owner] and teams[owner].name or "held")
	end
	return {pos = pos, label = label, progress = abs(progress) / 100, color = color}
end

return K

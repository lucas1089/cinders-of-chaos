-- poi_core.lua: the rules of the points of interest (poi.lua; client game_mapmarkers, extended opcode
-- ChaosOpcodes.mapMarkers = 153). Pure Lua, no engine calls; tests/poi_test.lua.
--
-- A mark is {k = kind, x, y, z, n = name, r = 0 | 1}. r = 0: always on the map (temples, depots, the services in
-- town, the Chaos NPCs, the portals next to the temples). r = 1: discovered: shown once the character came within
-- cfg.revealRange squares of it on its floor (hunting areas, bosses, dungeons, the services out in the world).
-- A character's discoveries are a set of keys (P.key: a kind letter and the position in hex, 10 characters), kept as
-- one comma-separated text per character (chaos_poi_seen). A key names a place, not a line of the data file, so
-- regenerating the data keeps what was discovered where the place stayed.
-- Quests (O410): kind "quest" marks a quest giver (the quest NPCs of cfg.questNpcs, r = 0 in town) or an area's quest
-- chest (r = 1); kind "questgoal" is a character's own next quest step (P.goals), sent apart and never stored.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosPoi = ChaosPoi or {}
local P = ChaosPoi

P.KINDS = {
	temple = "T", depot = "D", craft = "C", bank = "b", bless = "l", travel = "t", shop = "s", boss = "B", hunt = "h",
	npc = "n", portal = "p", guild = "g", dungeon = "d", quest = "q", questgoal = "Q"
}
P.CELL = 32 -- the reveal index cell (squares)

local floor = math.floor

local function int(v)
	v = tonumber(v)
	if not v or v ~= v then
		return nil
	end
	return floor(v)
end

-- a clean mark, or nil
function P.mark(kind, x, y, z, name, r)
	x, y, z = int(x), int(y), int(z)
	if not P.KINDS[kind] or not x or not y or not z or x <= 0 or y <= 0 or x > 65535 or y > 65535 or z < 0 or z > 15 then
		return nil
	end
	return {k = kind, x = x, y = y, z = z, n = tostring(name or ""), r = (r == 1 or r == true) and 1 or 0}
end

function P.key(m)
	return string.format("%s%04x%04x%x", P.KINDS[m.k] or "?", m.x, m.y, m.z)
end

-- the generated data ({version, marks}) checked: bad entries are dropped. -> marks, version
function P.load(data)
	local out = {}
	if type(data) ~= "table" or type(data.marks) ~= "table" then
		return out, ""
	end
	for _, e in ipairs(data.marks) do
		if type(e) == "table" then
			local m = P.mark(e.k, e.x, e.y, e.z, e.n, e.r)
			if m then
				out[#out + 1] = m
			end
		end
	end
	return out, tostring(data.version or "")
end

-- static and runtime marks as one list: one mark of a kind per tile (the first wins); the version changes with it
function P.merge(static, runtime, version)
	local seen, out = {}, {}
	for _, list in ipairs({static or {}, runtime or {}}) do
		for _, m in ipairs(list) do
			local key = P.key(m)
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = m
			end
		end
	end
	local parts = {tostring(version or "")}
	for _, m in ipairs(runtime or {}) do
		parts[#parts + 1] = P.key(m)
	end
	return out, P.hash(table.concat(parts, ","))
end

-- a short hash of a text (djb2, 8 hex digits): the version the client is told
function P.hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

-- the reveal index: the discoverable marks by cell
local function cellKey(x, y, z)
	return floor(x / P.CELL) .. ":" .. floor(y / P.CELL) .. ":" .. z
end

function P.index(marks)
	local idx = {}
	for _, m in ipairs(marks) do
		if m.r == 1 then
			m.key = P.key(m)
			local c = cellKey(m.x, m.y, m.z)
			local list = idx[c]
			if not list then
				list = {}
				idx[c] = list
			end
			list[#list + 1] = m
		end
	end
	return idx
end

-- the discoverable marks within `range` of pos (same floor) that `seen` does not hold yet
function P.near(idx, pos, range, seen)
	local out = {}
	local x, y, z = int(pos.x), int(pos.y), int(pos.z)
	if not x or not y or not z then
		return out
	end
	local c0x, c1x = floor((x - range) / P.CELL), floor((x + range) / P.CELL)
	local c0y, c1y = floor((y - range) / P.CELL), floor((y + range) / P.CELL)
	for cx = c0x, c1x do
		for cy = c0y, c1y do
			for _, m in ipairs(idx[cx .. ":" .. cy .. ":" .. z] or {}) do
				if math.abs(m.x - x) <= range and math.abs(m.y - y) <= range and not (seen and seen[m.key or P.key(m)]) then
					out[#out + 1] = m
				end
			end
		end
	end
	return out
end

-- the discoveries: text <-> set. Unknown pieces are kept out.
function P.decodeSeen(text)
	local set = {}
	for piece in tostring(text or ""):gmatch("[^,]+") do
		if piece:match("^[%a]%x%x%x%x%x%x%x%x%x$") then
			set[piece] = true
		end
	end
	return set
end

function P.encodeSeen(set)
	local list = {}
	for k in pairs(set or {}) do
		list[#list + 1] = k
	end
	table.sort(list)
	return table.concat(list, ",")
end

-- what a character is shown: the marks always on the map and its discoveries ({k, x, y, z, n})
function P.view(marks, seen)
	local out = {}
	for _, m in ipairs(marks) do
		if m.r == 0 or (seen and seen[P.key(m)]) then
			out[#out + 1] = {k = m.k, x = m.x, y = m.y, z = m.z, n = m.n}
		end
	end
	return out
end

-- reveals for one character at pos: marks the set did not hold (now added). -> list of marks
function P.reveal(idx, pos, range, seen)
	local found = P.near(idx, pos, range, seen)
	for _, m in ipairs(found) do
		seen[m.key or P.key(m)] = true
	end
	return found
end

-- the shown name of a Chaos NPC (cfg.npcs), nil for others
function P.npcName(cfg, name)
	return cfg and cfg.npcs and cfg.npcs[tostring(name or ""):lower()] or nil
end

-- the kind of a Chaos NPC's mark: "quest" for the quest givers (cfg.questNpcs, O410), else "npc"
function P.npcKind(cfg, name)
	return cfg and cfg.questNpcs and cfg.questNpcs[tostring(name or ""):lower()] and "quest" or "npc"
end

-- the Chaos NPCs in the stalls of the hub (npc_booths_config.lua), 700 tiles from the temple, so the temple scan
-- cannot see them. booths: {{name, x, y, z}} (ChaosNpcBoothsCore.booths); find(booth) -> {{name, x, y, z}} the NPCs
-- standing at the stall. An NPC counts when its name is the stall's. The shown name is cfg.npcs, else the NPC's name.
function P.hubMarks(cfg, booths, find)
	local out = {}
	for _, b in ipairs(booths or {}) do
		local want = tostring(b.name or ""):lower()
		for _, c in ipairs(find(b) or {}) do
			if tostring(c.name or ""):lower() == want then
				local m = P.mark(P.npcKind(cfg, c.name), c.x, c.y, c.z, P.npcName(cfg, c.name) or c.name, 0)
				if m then
					out[#out + 1] = m
				end
			end
		end
	end
	return out
end

-- a value inside nested tables by a path of keys (nil when a step is missing)
function P.dig(t, path)
	for _, k in ipairs(path or {}) do
		if type(t) ~= "table" then
			return nil
		end
		t = t[k]
	end
	return t
end

-- the portal list of the config as {[action id] = {kind, name}}. load(file) returns a config table (or nil); the
-- globals table is searched for `global` paths. Entries that do not resolve to a number are left out.
function P.portalIds(list, load, globals)
	local out, cache = {}, {}
	for _, e in ipairs(list or {}) do
		local id
		if e.config then
			if cache[e.config] == nil then
				cache[e.config] = load(e.config) or false
			end
			id = P.dig(cache[e.config] or nil, e.path)
		elseif e.global then
			id = P.dig(globals, e.global)
		end
		id = tonumber(id)
		if id and P.KINDS[e.kind] then
			out[id] = {kind = e.kind, name = e.name}
		end
	end
	return out
end

-- ---------------------------------------------------------------- quest goals (O410)
-- A character's next quest steps on its map. The quest systems name places in three ways (poi.lua asks them through
-- ChaosPoi.addQuestSource): {x, y, z, n} a fixed place, {npc = name, n} the NPC to talk to or turn in at (its npc or
-- quest mark, by name), {hunts = {monster names}, n} the hunting areas of those monsters (their hunt marks, at most
-- cfg.questHunts per step). The result: clean "questgoal" marks, one per tile, at most cfg.questGoalMax.

local function lower(s)
	return tostring(s or ""):lower()
end

-- the npc / quest mark of an NPC: its shown name is the NPC's name, or starts with it followed by " ", "," or "("
function P.findNpc(marks, name)
	local want = lower(name)
	if want == "" then
		return nil
	end
	for _, m in ipairs(marks or {}) do
		if m.k == "npc" or m.k == "quest" then
			local n = lower(m.n)
			if n == want then
				return m
			end
			local nxt = n:sub(#want + 1, #want + 1)
			if n:sub(1, #want) == want and (nxt == " " or nxt == "," or nxt == "(") then
				return m
			end
		end
	end
	return nil
end

-- the monsters a hunting mark names ("Hunting: Dragon, Dragon Lord (level 50-120)") in lower case
function P.huntMonsters(m)
	local out = {}
	local body = tostring(m and m.n or ""):match("^Hunting: (.-) %(") or ""
	for name in body:gmatch("[^,]+") do
		out[#out + 1] = lower(name:match("^%s*(.-)%s*$"))
	end
	return out
end

-- the hunting marks of any of these monsters, in the order of the list, at most `limit`
function P.huntsFor(marks, monsters, limit)
	local want = {}
	for _, n in ipairs(monsters or {}) do
		want[lower(n)] = true
	end
	local out = {}
	for _, m in ipairs(marks or {}) do
		if m.k == "hunt" then
			for _, n in ipairs(P.huntMonsters(m)) do
				if want[n] then
					out[#out + 1] = m
					break
				end
			end
			if limit and #out >= limit then
				break
			end
		end
	end
	return out
end

-- entries of the quest sources -> clean "questgoal" marks {k, x, y, z, n}
function P.goals(entries, marks, cfg)
	cfg = cfg or {}
	local max = cfg.questGoalMax or 12
	local out, seen = {}, {}
	local function add(x, y, z, n)
		if #out >= max then
			return
		end
		local m = P.mark("questgoal", x, y, z, n, 0)
		if m then
			local key = P.key(m)
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = {k = m.k, x = m.x, y = m.y, z = m.z, n = m.n}
			end
		end
	end
	for _, e in ipairs(entries or {}) do
		if type(e) == "table" then
			local n = tostring(e.n or "")
			if e.npc then
				local m = P.findNpc(marks, e.npc)
				if m then
					add(m.x, m.y, m.z, n)
				end
			elseif type(e.hunts) == "table" then
				for _, m in ipairs(P.huntsFor(marks, e.hunts, cfg.questHunts or 2)) do
					add(m.x, m.y, m.z, n)
				end
			else
				add(e.x, e.y, e.z, n)
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- marks over NPC heads (O415)
-- The quest systems say which NPC a character has something with (poi.lua asks them through ChaosPoi.markSources):
-- {npc = name, mark = "new" | "ready" | "locked"}. "new": a quest the character can start now (gold "!"), "ready": a
-- step to turn in or report to this NPC (gold "?"), "locked": a quest that waits for a level (grey "!"). An NPC with
-- several keeps the strongest (ready, then new, then locked). The client matches by the NPC's name.
P.MARK_RANK = {locked = 1, new = 2, ready = 3}

-- entries -> {[lower case name] = {n = name, m = mark}}, at most cfg.marks.max NPCs (the strongest, then by name)
function P.mergeMarks(entries, cfg)
	local max = cfg and cfg.marks and cfg.marks.max or 24
	local best = {}
	for _, e in ipairs(entries or {}) do
		local rank = type(e) == "table" and P.MARK_RANK[e.mark]
		local name = type(e) == "table" and tostring(e.npc or "") or ""
		if rank and name ~= "" then
			local key = lower(name)
			if not best[key] then
				best[key] = {n = name, m = e.mark}
			elseif P.MARK_RANK[best[key].m] < rank then
				best[key].m = e.mark -- the name of the first entry stays
			end
		end
	end
	local list = {}
	for key, v in pairs(best) do
		list[#list + 1] = {key = key, rank = P.MARK_RANK[v.m]}
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.key < b.key
	end)
	local out = {}
	for i = 1, math.min(#list, max) do
		out[list[i].key] = best[list[i].key]
	end
	return out
end

-- what changed from the marks last sent to the marks now: set = [{n, m}] (new or changed), clear = [name] (gone)
function P.markDiff(old, new)
	local set, clear = {}, {}
	for key, v in pairs(new or {}) do
		local o = (old or {})[key]
		if not o or o.m ~= v.m then
			set[#set + 1] = {n = v.n, m = v.m}
		end
	end
	for key, o in pairs(old or {}) do
		if not (new or {})[key] then
			clear[#clear + 1] = o.n
		end
	end
	table.sort(set, function(a, b) return lower(a.n) < lower(b.n) end)
	table.sort(clear, function(a, b) return lower(a) < lower(b) end)
	return set, clear
end

-- a short hash of a goal list: poi.lua sends the list again only when it changed
function P.goalsHash(list)
	local parts = {}
	for _, m in ipairs(list or {}) do
		parts[#parts + 1] = P.key(m) .. "=" .. tostring(m.n)
	end
	return P.hash(table.concat(parts, "|"))
end

return P

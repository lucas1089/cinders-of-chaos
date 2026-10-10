-- Name plates and titles: pure logic (no engine calls), shared by titles.lua, nameplate.lua and
-- server/tests/nameplate_test.lua.
--   ChaosNameplate.normalize(t, source)     one title from a source -> {key, text, color, at, frame, priority, source} | nil
--   ChaosNameplate.collect(sources, player) every title the player holds, sorted (staff first, then newest first)
--   ChaosNameplate.sort(list)               the same order, in place
--   ChaosNameplate.pick(list, choice)       the active title: choice nil = the first, "none" = nil, a key = that title
--                                           (falls back to the first when the chosen title is gone)
--   ChaosNameplate.find(list, query)        a title by key or by text (exact, then prefix; case-insensitive)
--   ChaosNameplate.frameOf(title, extra)    frame id: a cosmetic frame (extra) beats the title's own, else "default"
--   ChaosNameplate.clean(s, max)            text safe for the wire (no separators or control characters), trimmed
--   ChaosNameplate.encode(rec)              one plate on the wire: "cid|title|color|guild|frame"
--   ChaosNameplate.decodeQuery(buffer, max) "q|id,id,..." from the client -> list of ids (unique, at most max)
-- Wire format (extended opcode ChaosOpcodes.nameplate):
--   server -> client  one plate per line: cid|title|color|guild|frame. Empty title / guild = no such line; color is
--                     RRGGBB of the title; frame empty = the default frame.
--   client -> server  q|id,id,...   plates of creatures the client has not got yet
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosNameplate = ChaosNameplate or {}
local N = ChaosNameplate

-- title colour per source (RRGGBB); a title may bring its own
N.COLORS = {
	staff = "e0402c", -- red
	leaderboard = "e8c15a", -- gold
	champion = "f08a2c", -- orange (Siege Champions)
	season = "b48cff", -- violet
	arena = "8fb6e8", -- steel blue
	streak = "7cd17c", -- green (login-streak milestones)
	achievement = "5cc8c0", -- teal
	other = "d6c9ae" -- parchment
}

-- frames the client has (game_nameplate/images/plate_<id>.png)
N.FRAMES = {default = true, gold = true, crimson = true, violet = true, frost = true, ember = true, verdant = true,
	bone = true}

-- frame a title of this source brings when it is the active title
N.SOURCE_FRAME = {staff = "gold", champion = "crimson"}

-- sort weight: staff titles first
N.SOURCE_PRIORITY = {staff = 100}

N.MAX_TITLE = 24
N.MAX_GUILD = 30

function N.clean(s, max)
	if s == nil then
		return ""
	end
	s = tostring(s):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
	if max and #s > max then
		s = s:sub(1, max):gsub("%s+$", "")
	end
	return s
end

local function hexColor(c)
	if type(c) ~= "string" then
		return nil
	end
	c = c:gsub("^#", "")
	if #c == 6 and not c:find("[^%x]") then
		return c:lower()
	end
	return nil
end

-- t = {key?, text | title, color?, at?, frame?, priority?}; source = the registry name
function N.normalize(t, source)
	if type(t) == "string" then
		t = {text = t}
	end
	if type(t) ~= "table" then
		return nil
	end
	local text = N.clean(t.text or t.title, N.MAX_TITLE)
	if text == "" then
		return nil
	end
	source = tostring(source or t.source or "other")
	local frame = t.frame or N.SOURCE_FRAME[source]
	return {
		key = N.clean(t.key, 64) ~= "" and N.clean(t.key, 64) or (source .. ":" .. text:lower()),
		text = text,
		color = hexColor(t.color) or N.COLORS[source] or N.COLORS.other,
		at = tonumber(t.at) or 0,
		frame = (frame and N.FRAMES[frame]) and frame or nil,
		priority = tonumber(t.priority) or N.SOURCE_PRIORITY[source] or 0,
		source = source
	}
end

function N.sort(list)
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.key < b.key
	end)
	return list
end

-- sources = ordered list of {name, fn}; fn(player) -> list of titles (or one title). A source that errors is skipped
-- (onError(name, err) is told).
function N.collect(sources, player, onError)
	local list, seen = {}, {}
	for _, s in ipairs(sources or {}) do
		local ok, got = pcall(s.fn, player)
		if not ok then
			if onError then
				onError(s.name, got)
			end
		elseif type(got) == "table" then
			if got.text or got.title then
				got = {got}
			end
			for _, raw in ipairs(got) do
				local t = N.normalize(raw, s.name)
				if t and not seen[t.key] then
					seen[t.key] = true
					list[#list + 1] = t
				end
			end
		end
	end
	return N.sort(list)
end

function N.pick(list, choice)
	if choice == "none" then
		return nil
	end
	if choice and choice ~= "" then
		for _, t in ipairs(list) do
			if t.key == choice then
				return t
			end
		end
	end
	return list[1]
end

function N.find(list, query)
	query = N.clean(query):lower()
	if query == "" then
		return nil
	end
	for _, t in ipairs(list) do
		if t.key == query or t.text:lower() == query then
			return t
		end
	end
	for _, t in ipairs(list) do
		if t.text:lower():sub(1, #query) == query then
			return t
		end
	end
	return nil
end

function N.frameOf(title, extra)
	if extra and N.FRAMES[extra] then
		return extra
	end
	return title and title.frame or "default"
end

-- rec = {cid, title, color, guild, frame}
function N.encode(rec)
	local frame = rec.frame
	if frame == "default" then
		frame = ""
	end
	local title = N.clean(rec.title, N.MAX_TITLE)
	return table.concat({
		tostring(math.floor(tonumber(rec.cid) or 0)),
		title,
		title ~= "" and (hexColor(rec.color) or "") or "",
		N.clean(rec.guild, N.MAX_GUILD),
		frame or ""
	}, "|")
end

function N.decodeQuery(buffer, max)
	local ids, seen = {}, {}
	if type(buffer) ~= "string" or buffer:sub(1, 2) ~= "q|" then
		return ids
	end
	max = max or 40
	for part in buffer:sub(3):gmatch("[^,]+") do
		local id = tonumber(part)
		if id and id > 0 and id == math.floor(id) and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
			if #ids >= max then
				break
			end
		end
	end
	return ids
end

return N

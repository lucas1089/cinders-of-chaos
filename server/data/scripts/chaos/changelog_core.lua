-- Changelog of the Patch Notes window: pure logic (no engine calls), shared by patchnotes.lua and
-- server/tests/changelog_test.lua. The file data/changelog/changelog.json is written at deploy time by
-- server/tools/gen_changelog.py (the kit update); this side never trusts it: a file over the size limit, JSON that does
-- not decode, or a value of the wrong type or size is refused or dropped, and the rest is rebuilt from known fields only.
--   ChaosChangelog.decode(raw, jsonDecode)  the file's text -> validated changelog, or nil, reason
--   ChaosChangelog.validate(data)           a decoded table -> {server = {date, ts}, published, entries = [{id, date, ts,
--                                           pr, text, tags = [server|client|content|website], client, pending}]}
--   ChaosChangelog.payload(cl)              what goes to the client (action "changelog"); empty when there is no file:
--                                           {available, server = {date}, published, entries}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosChangelog = ChaosChangelog or {}
local CL = ChaosChangelog

CL.limits = {
	fileBytes = 256 * 1024, -- the generator caps the file at 200 KB
	entries = 250, -- the generator writes at most 200
	text = 200, -- characters of one entry (the generator cuts at 160)
	tagsPerEntry = 4
}

CL.TAGS = {server = 1, client = 2, content = 3, website = 4}

local function isDate(s)
	return type(s) == "string" and s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

-- an integer number in [lo, hi], or nil
local function int(v, lo, hi)
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then
		return nil
	end
	return v
end

-- printable text: control characters out, spaces squeezed, cut to `n` bytes without splitting a UTF-8 character
function CL.text(s, n)
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if s == "" then
		return nil
	end
	if #s > n then
		local cut = n - 3
		-- back off a UTF-8 continuation byte (10xxxxxx) so the cut never leaves half a character
		while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do
			cut = cut - 1
		end
		s = s:sub(1, cut) .. "..."
	end
	return s
end

function CL.entry(e)
	if type(e) ~= "table" then
		return nil
	end
	local text = CL.text(e.text, CL.limits.text)
	if not text or not isDate(e.date) then
		return nil
	end
	local id = type(e.id) == "string" and e.id:match("^[0-9a-f]+$") and #e.id >= 7 and #e.id <= 40 and e.id or nil
	local tags, seen = {}, {}
	if type(e.tags) == "table" then
		for _, t in ipairs(e.tags) do
			if CL.TAGS[t] and not seen[t] and #tags < CL.limits.tagsPerEntry then
				seen[t] = true
				tags[#tags + 1] = t
			end
		end
	end
	if #tags == 0 then
		return nil
	end
	table.sort(tags, function(a, b)
		return CL.TAGS[a] < CL.TAGS[b]
	end)
	local out = {id = id or "", date = e.date, ts = int(e.ts, 0, 4102444800) or 0, pr = int(e.pr, 1, 9999999),
		text = text, tags = tags}
	if seen.client then
		out.client = int(e.client, 1, 999999)
		out.pending = e.pending == true or out.client == nil
	end
	return out
end

function CL.validate(data)
	if type(data) ~= "table" then
		return nil, "not an object"
	end
	if type(data.entries) ~= "table" then
		return nil, "no entries"
	end
	local entries = {}
	for _, e in ipairs(data.entries) do
		if #entries >= CL.limits.entries then
			break
		end
		local ok = CL.entry(e)
		if ok then
			entries[#entries + 1] = ok
		end
	end
	local server = type(data.server) == "table" and data.server or {}
	return {
		server = {date = isDate(server.date) and server.date or "", ts = int(server.ts, 0, 4102444800) or 0},
		published = int(data.published, 1, 999999),
		entries = entries
	}
end

-- raw: the file's bytes (the caller reads at most limits.fileBytes + 1); jsonDecode: the engine's json.decode
function CL.decode(raw, jsonDecode)
	if type(raw) ~= "string" or raw == "" then
		return nil, "empty"
	end
	if #raw > CL.limits.fileBytes then
		return nil, "over " .. CL.limits.fileBytes .. " bytes"
	end
	if type(jsonDecode) ~= "function" then
		return nil, "no JSON decoder"
	end
	local ok, data = pcall(jsonDecode, raw)
	if not ok then
		return nil, "bad JSON"
	end
	return CL.validate(data)
end

function CL.payload(cl)
	if not cl then
		return {available = false, server = {date = ""}, entries = {}}
	end
	return {available = true, server = {date = cl.server.date}, published = cl.published, entries = cl.entries}
end

return CL

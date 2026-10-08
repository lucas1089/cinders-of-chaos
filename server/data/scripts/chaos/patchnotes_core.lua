-- Patch notes: pure logic (no engine calls), shared by patchnotes.lua and server/tests/patchnotes_test.lua.
--   ChaosPatchNotes.parse(text, id)          one notes file -> {id, title, date, intro = {lines}, sections = [{name, kind,
--                                            items = [{text, level (0 paragraph, 1 bullet, 2 sub-bullet), lead}]}]}
--   ChaosPatchNotes.fileNames(listing)       the notes files of a directory listing (one name per line): *.md, not
--                                            README.md, not drafts (a name starting with "_"); sorted
--   ChaosPatchNotes.sort(notes)              newest first (date, then id)
--   ChaosPatchNotes.key(note)                "YYYY-MM-DD|id": what is stored as "last seen" (string order = age order)
--   ChaosPatchNotes.isNew(note, seenKey)     newer than the last seen key
--   ChaosPatchNotes.autoOpen(notes, seenKey, autoEnabled)   the note to open by itself at login, or nil
--   ChaosPatchNotes.validId(id)              a client-sent id is safe to look up
--   ChaosPatchNotes.summary(notes, seenKey, max)   the week list sent to the client
--   ChaosPatchNotes.parts(note, budget)      the note split into packets of about `budget` bytes of text: [{id, title,
--                                            date, part, parts, intro, sections}]; a section cut in two continues in
--                                            the next part with cont = true (the client joins them)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- File format (data/patchnotes/<id>.md, id = file name without .md, e.g. 2026-10-08):
--   # Title of the week                  first "# " line
--   Date: 2026-10-08                     optional; else the date in the file name; else none
--   Free text before the first section   the intro
--   ## New | ## Changes | ## Fixes | ## Balance    sections (other names are kept as "other")
--   - a bullet (or "* ")                 indent by 2+ spaces for a sub-bullet; "- **Lead.** text" gives the bullet a
--                                        highlighted lead
--     an indented line without a dash continues the bullet above
--   plain text inside a section          a paragraph
--   <!-- ... -->                         ignored (may span lines)
--   **bold**, __bold__, `code`, [text](link)   the markers are removed (the client colours sections, not words)

ChaosPatchNotes = ChaosPatchNotes or {}
local PN = ChaosPatchNotes

PN.limits = {
	title = 80,
	text = 700, -- one bullet or paragraph
	items = 60, -- per section
	sections = 12,
	intro = 6, -- lines
	list = 52 -- weeks sent to the client (a year)
}

PN.kinds = {
	new = "new", added = "new", ["new features"] = "new",
	changes = "changes", changed = "changes", change = "changes",
	fixes = "fixes", fixed = "fixes", fix = "fixes", ["bug fixes"] = "fixes",
	balance = "balance", balancing = "balance"
}

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cut(s, n)
	if #s <= n then
		return s
	end
	return s:sub(1, n - 3) .. "..."
end

-- inline markdown markers out, spaces squeezed
function PN.clean(s)
	s = s:gsub("%*%*(.-)%*%*", "%1"):gsub("__(.-)__", "%1"):gsub("`(.-)`", "%1")
	s = s:gsub("%[(.-)%]%((.-)%)", "%1") -- [text](link) -> text
	s = s:gsub("%s+", " ")
	return trim(s)
end

local function isDate(s)
	return type(s) == "string" and s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end
PN.isDate = isDate

-- a bullet; a bold start ("**Bounty board.** New contracts ...") becomes its lead, which the client highlights
function PN.item(bullet, level)
	local lead, rest = bullet:match("^%*%*(.-)%*%*%s*(.*)$")
	if lead and PN.clean(lead) ~= "" then
		return {lead = PN.clean(lead), text = PN.clean(rest), level = level}
	end
	return {text = PN.clean(bullet), level = level}
end

function PN.parse(text, id)
	local note = {id = id, title = nil, date = nil, intro = {}, sections = {}}
	local section, item
	local inComment = false
	text = (text or ""):gsub("\r\n?", "\n")
	if text:sub(1, 3) == "\239\187\191" then
		text = text:sub(4) -- UTF-8 BOM
	end
	for raw in (text .. "\n"):gmatch("(.-)\n") do
		local line = raw:gsub("\t", "    ")
		-- comments
		if inComment then
			local e = line:find("-->", 1, true)
			if e then
				inComment = false
				line = line:sub(e + 3)
			else
				line = ""
			end
		end
		line = line:gsub("<!%-%-.-%-%->", "")
		local s = line:find("<!--", 1, true)
		if s then
			inComment = true
			line = line:sub(1, s - 1)
		end

		local body = trim(line)
		local indent = #(line:match("^( *)"))
		if body == "" then
			item = nil -- a blank line ends a bullet's continuation
		elseif body:match("^#[^#]") and not note.title then
			note.title = cut(PN.clean(body:sub(2)), PN.limits.title)
			item = nil
		elseif body:match("^##+") then
			local name = PN.clean(body:gsub("^#+", ""))
			if #note.sections < PN.limits.sections and name ~= "" then
				section = {name = cut(name, PN.limits.title), kind = PN.kinds[name:lower()] or "other", items = {}}
				note.sections[#note.sections + 1] = section
			else
				section = nil
			end
			item = nil
		elseif not section and not note.date and body:lower():match("^date%s*:") then
			local d = trim(body:match(":(.*)$"))
			if isDate(d) then
				note.date = d
			end
		else
			local bullet = body:match("^[%-%*%+]%s+(.*)$")
			if bullet then
				if section then
					if #section.items < PN.limits.items then
						item = PN.item(bullet, indent >= 2 and 2 or 1)
						section.items[#section.items + 1] = item
					else
						item = nil
					end
				elseif #note.intro < PN.limits.intro then
					item = {text = PN.clean(bullet)}
					note.intro[#note.intro + 1] = item
				else
					item = nil
				end
			elseif item then
				-- continuation of the bullet or paragraph above
				item.text = PN.clean(item.text .. " " .. body)
			elseif section then
				if #section.items < PN.limits.items then
					item = {text = PN.clean(body), level = 0}
					section.items[#section.items + 1] = item
				end
			elseif #note.intro < PN.limits.intro then
				item = {text = PN.clean(body)}
				note.intro[#note.intro + 1] = item
			end
		end
	end
	for _, sec in ipairs(note.sections) do
		for _, it in ipairs(sec.items) do
			it.text = cut(it.text, PN.limits.text)
		end
	end
	for i, l in ipairs(note.intro) do
		note.intro[i] = cut(l.text, PN.limits.text)
	end
	if not note.date and type(id) == "string" then
		local d = id:match("^(%d%d%d%d%-%d%d%-%d%d)")
		if d then
			note.date = d
		end
	end
	note.title = note.title or (note.date and ("Patch notes " .. note.date)) or tostring(id or "Patch notes")
	-- drop empty sections (a heading with nothing under it)
	local kept = {}
	for _, sec in ipairs(note.sections) do
		if #sec.items > 0 then
			kept[#kept + 1] = sec
		end
	end
	note.sections = kept
	return note
end

function PN.validId(id)
	return type(id) == "string" and #id >= 1 and #id <= 48 and id:match("^[%w][%w%-%._]*$") ~= nil
end

-- *.md file names of a listing (ls / dir /b output, one per line), without README.md and drafts ("_" prefix)
function PN.fileNames(listing)
	local out, seen = {}, {}
	for line in ((listing or "") .. "\n"):gmatch("(.-)\r?\n") do
		local name = trim(line):match("([^/\\]+)$")
		if name and name:lower():match("%.md$") and name:lower() ~= "readme.md" and name:sub(1, 1) ~= "_" then
			local id = name:sub(1, -4)
			if PN.validId(id) and not seen[id] then
				seen[id] = true
				out[#out + 1] = name
			end
		end
	end
	table.sort(out)
	return out
end

function PN.key(note)
	return (note.date or "0000-00-00") .. "|" .. tostring(note.id)
end

function PN.sort(notes)
	table.sort(notes, function(a, b)
		return PN.key(a) > PN.key(b)
	end)
	return notes
end

function PN.isNew(note, seenKey)
	if not note then
		return false
	end
	if type(seenKey) ~= "string" or seenKey == "" then
		return true
	end
	return PN.key(note) > seenKey
end

-- notes sorted newest first; returns the newest note when it is unseen and auto-open is on
function PN.autoOpen(notes, seenKey, autoEnabled)
	if autoEnabled == false then
		return nil
	end
	local newest = notes and notes[1]
	if newest and PN.isNew(newest, seenKey) then
		return newest
	end
	return nil
end

-- the later of two seen keys (a player reading an old week never "unsees" a newer one)
function PN.maxKey(a, b)
	if type(a) ~= "string" or a == "" then
		return b
	end
	if type(b) ~= "string" or b == "" then
		return a
	end
	return a > b and a or b
end

function PN.summary(notes, seenKey, max)
	local list = {}
	for i = 1, math.min(#notes, max or PN.limits.list) do
		local n = notes[i]
		list[#list + 1] = {id = n.id, title = n.title, date = n.date or "", new = PN.isNew(n, seenKey)}
	end
	return list
end

-- ---------------------------------------------------------------- packets
-- One extended opcode message must stay small (a long note did not arrive in the test client), so a note goes out
-- in parts of at most `budget` bytes of text (estimated: text + lead + a fixed overhead per item).
PN.partBudget = 4000

local function itemSize(it)
	return #(it.text or "") + #(it.lead or "") + 40
end

function PN.parts(note, budget)
	budget = budget or PN.partBudget
	local parts = {}
	local cur, used, count
	local function newPart()
		cur = {id = note.id, title = note.title, date = note.date or "", intro = {}, sections = {}}
		parts[#parts + 1] = cur
		used, count = #(note.title or "") + 60, 0
	end
	newPart()
	cur.intro = note.intro or {}
	for _, l in ipairs(cur.intro) do
		used = used + #l + 4
	end
	for _, sec in ipairs(note.sections or {}) do
		local out
		for _, it in ipairs(sec.items or {}) do
			local size = itemSize(it)
			if count > 0 and used + size > budget then
				-- full: go on in a new part; the section continues there
				local cut = out ~= nil
				newPart()
				out = nil
				if cut then
					out = {name = sec.name, kind = sec.kind, items = {}, cont = true}
					cur.sections[1] = out
				end
			end
			if not out then
				out = {name = sec.name, kind = sec.kind, items = {}}
				cur.sections[#cur.sections + 1] = out
			end
			out.items[#out.items + 1] = it
			used, count = used + size, count + 1
		end
	end
	for i, p in ipairs(parts) do
		p.part, p.parts = i, #parts
	end
	return parts
end

return PN

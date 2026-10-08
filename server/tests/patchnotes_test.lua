-- Run from the server/ folder: luajit tests/patchnotes_test.lua (and lua5.3; CI runs both)
-- Pure logic of the patch notes (patchnotes_core.lua): parsing a notes file, the file list, newest-first order, the
-- "last seen" key and the login auto-open choice. Also parses every real file of data/patchnotes/.
dofile("data/scripts/chaos/patchnotes_core.lua")
local PN = ChaosPatchNotes

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- parse
local text = table.concat({
	"\239\187\191# The **big** week",
	"Date: 2026-10-08",
	"",
	"Intro line one",
	"continues here.",
	"",
	"Second intro paragraph.",
	"",
	"<!-- a comment",
	"## Hidden",
	"- not parsed -->",
	"## New",
	"- First `thing`",
	"  wraps onto a second line.",
	"  - a sub bullet",
	"* star bullet with [a link](http://example.com)",
	"",
	"A paragraph in a section",
	"over two lines.",
	"## Changes",
	"",
	"## fixes",
	"\t- tab-indented sub bullet",
	"- fixed __this__ <!-- inline comment --> too",
	"## Balance",
	"+ plus bullet",
	"## Known issues",
	"- other kind",
	""
}, "\r\n")
local n = PN.parse(text, "2026-10-01")
eq(n.id, "2026-10-01", "id")
eq(n.title, "The big week", "title without markers and BOM")
eq(n.date, "2026-10-08", "the Date: line wins over the file name")
eq(#n.intro, 2, "two intro paragraphs")
eq(n.intro[1], "Intro line one continues here.", "intro lines joined")
eq(n.intro[2], "Second intro paragraph.", "second intro")
eq(#n.sections, 4, "empty Changes and the commented-out section dropped")
local new, fixes, balance, other = n.sections[1], n.sections[2], n.sections[3], n.sections[4]
eq(new.name, "New", "section name")
eq(new.kind, "new", "kind new")
eq(#new.items, 4, "new items")
eq(new.items[1].text, "First thing wraps onto a second line.", "continuation joined, code marker removed")
eq(new.items[1].level, 1, "bullet level")
eq(new.items[1].lead, nil, "no lead")
eq(new.items[2].text, "a sub bullet", "sub bullet")
eq(new.items[2].level, 2, "sub level")
eq(new.items[3].text, "star bullet with a link", "link text kept")
eq(new.items[4].level, 0, "paragraph")
eq(new.items[4].text, "A paragraph in a section over two lines.", "paragraph joined")
eq(fixes.kind, "fixes", "kind is case-insensitive")
eq(fixes.name, "fixes", "name kept as written")
eq(fixes.items[1].level, 2, "tab indent is a sub bullet")
eq(fixes.items[2].text, "fixed this too", "inline comment and __ removed")
eq(balance.kind, "balance", "kind balance")
eq(balance.items[1].text, "plus bullet", "+ bullet")
eq(other.kind, "other", "unknown section kind")

-- a bold start is the lead
local b = PN.parse("## New\n- **Bounty board.** New `contracts`\n  daily.\n- **bold** only\n- **** empty\n", "x")
eq(b.sections[1].items[1].lead, "Bounty board.", "lead")
eq(b.sections[1].items[1].text, "New contracts daily.", "text after the lead, continuation joined")
eq(b.sections[1].items[2].lead, "bold", "lead only")
eq(b.sections[1].items[2].text, "only", "text")
eq(b.sections[1].items[3].text, "empty", "empty bold markers removed")
eq(b.sections[1].items[3].lead, nil, "empty lead ignored")

-- defaults: no title, no Date: line
local d = PN.parse("## Fixes\n- one\n", "2026-09-30-hotfix")
eq(d.date, "2026-09-30", "date from the file name")
eq(d.title, "Patch notes 2026-09-30", "default title")
local e = PN.parse("", "v3.7.5")
eq(e.date, nil, "no date")
eq(e.title, "v3.7.5", "title falls back to the id")
eq(#e.sections, 0, "empty file")
eq(PN.parse("Date: 08.10.2026\n", "x").date, nil, "bad date ignored")

-- limits
local long = {"## New"}
for i = 1, 80 do
	long[#long + 1] = "- item " .. i
end
long[#long + 1] = "- " .. string.rep("a", 1000)
local l = PN.parse(table.concat(long, "\n"), "2026-01-01")
eq(#l.sections[1].items, PN.limits.items, "items capped")
local l2 = PN.parse("## New\n- " .. string.rep("b", 1000), "2026-01-01")
eq(#l2.sections[1].items[1].text, PN.limits.text, "text capped")
eq(l2.sections[1].items[1].text:sub(-3), "...", "ellipsis")
eq(#PN.parse("# " .. string.rep("t", 200), "x").title, PN.limits.title, "title capped")

-- ---------------------------------------------------------------- file list
local files = PN.fileNames("2026-10-08.md\r\nREADME.md\n_draft.md\nnotes.txt\n2026-10-01.md\n./data/patchnotes/v3.8.md\nbad name.md\n2026-10-01.md\n")
eq(#files, 3, "md files, no readme, drafts, other files, bad names or duplicates")
eq(files[1], "2026-10-01.md", "sorted 1")
eq(files[2], "2026-10-08.md", "sorted 2")
eq(files[3], "v3.8.md", "path stripped")
eq(#PN.fileNames(nil), 0, "no listing")

-- ---------------------------------------------------------------- ids
eq(PN.validId("2026-10-08"), true, "date id")
eq(PN.validId("v3.7.5_hotfix"), true, "version id")
eq(PN.validId("../config"), false, "path")
eq(PN.validId(""), false, "empty")
eq(PN.validId(12), false, "number")
eq(PN.validId(string.rep("a", 49)), false, "too long")

-- ---------------------------------------------------------------- order, seen key, auto-open
local notes = PN.sort({
	{id = "2026-09-24", date = "2026-09-24"},
	{id = "2026-10-08", date = "2026-10-08"},
	{id = "v3.7.5", date = nil},
	{id = "2026-10-08b", date = "2026-10-08"},
	{id = "2026-10-01", date = "2026-10-01"}
})
eq(notes[1].id, "2026-10-08b", "same date: id decides")
eq(notes[2].id, "2026-10-08", "newest date")
eq(notes[4].id, "2026-09-24", "older")
eq(notes[5].id, "v3.7.5", "undated last")
eq(PN.key(notes[2]), "2026-10-08|2026-10-08", "key")

eq(PN.autoOpen(notes, nil, true), notes[1], "never seen: open the newest")
eq(PN.autoOpen(notes, "", nil), notes[1], "empty key, setting unknown: open")
eq(PN.autoOpen(notes, PN.key(notes[1]), true), nil, "seen: do not open again")
eq(PN.autoOpen(notes, PN.key(notes[3]), true), notes[1], "older seen: open")
eq(PN.autoOpen(notes, PN.key(notes[1]), false), nil, "auto off")
eq(PN.autoOpen(notes, nil, false), nil, "auto off, never seen")
eq(PN.autoOpen({}, nil, true), nil, "no notes")
eq(PN.autoOpen(notes, "2099-01-01|x", true), nil, "a seen note that was deleted later still counts")

eq(PN.maxKey(nil, "2026-10-01|a"), "2026-10-01|a", "max from nil")
eq(PN.maxKey("2026-10-08|a", "2026-10-01|a"), "2026-10-08|a", "reading an old week keeps the newer key")
eq(PN.maxKey("2026-10-01|a", "2026-10-08|a"), "2026-10-08|a", "max")
eq(PN.maxKey("2026-10-01|a", nil), "2026-10-01|a", "max with nil")

local sum = PN.summary(notes, PN.key(notes[3]), 3)
eq(#sum, 3, "summary capped")
eq(sum[1].new, true, "newer is new")
eq(sum[3].new, false, "seen is not new")
eq(sum[3].date, "2026-10-01", "summary date")
eq(PN.summary({notes[5]}, nil)[1].date, "", "undated summary")

-- ---------------------------------------------------------------- packets
-- join parts back the way the client does (a section with cont goes on in the previous part's last section)
local function join(parts)
	local out = {intro = parts[1].intro, sections = {}}
	for _, p in ipairs(parts) do
		for _, sec in ipairs(p.sections) do
			local last = out.sections[#out.sections]
			if sec.cont and last and last.name == sec.name then
				for _, it in ipairs(sec.items) do
					last.items[#last.items + 1] = it
				end
			else
				local copy = {name = sec.name, kind = sec.kind, items = {}}
				for _, it in ipairs(sec.items) do
					copy.items[#copy.items + 1] = it
				end
				out.sections[#out.sections + 1] = copy
			end
		end
	end
	return out
end
local function same(a, b, m)
	eq(#a.sections, #b.sections, m .. ": sections")
	for i, sec in ipairs(a.sections) do
		eq(sec.name, b.sections[i].name, m .. ": section name " .. i)
		eq(#sec.items, #b.sections[i].items, m .. ": items of " .. sec.name)
		for j, it in ipairs(sec.items) do
			eq(it, b.sections[i].items[j], m .. ": item order")
		end
	end
	eq(#a.intro, #b.intro, m .. ": intro")
end
local one = PN.parts(n)
eq(#one, 1, "a small note is one part")
eq(one[1].part, 1, "part")
eq(one[1].parts, 1, "parts")
eq(one[1].intro, n.intro, "intro in part 1")
local tiny = PN.parts(n, 1)
eq(#tiny, 8, "budget 1: one item per part (8 items)")
eq(tiny[2].sections[1].cont, true, "the second item of New continues the section")
eq(tiny[5].sections[1].cont, nil, "a new section starts fresh")
eq(#tiny[2].intro, 0, "intro only in part 1")
eq(tiny[8].parts, 8, "parts count everywhere")
same(join(tiny), n, "budget 1 joins back")

-- ---------------------------------------------------------------- the real files
local ls = io.popen and io.popen('ls -1 data/patchnotes 2>/dev/null')
local listing = ls and ls:read("*a") or ""
if ls then
	ls:close()
end
local real = 0
for _, name in ipairs(PN.fileNames(listing)) do
	local f = assert(io.open("data/patchnotes/" .. name, "rb"))
	local body = f:read("*a")
	f:close()
	local note = PN.parse(body, name:sub(1, -4))
	assert(note.date, name .. ": no date")
	assert(#note.sections > 0, name .. ": no sections")
	for _, sec in ipairs(note.sections) do
		assert(sec.kind ~= "other", name .. ": unknown section " .. sec.name)
		for _, it in ipairs(sec.items) do
			assert(#it.text < PN.limits.text, name .. ": a bullet was cut: " .. it.text:sub(1, 40))
		end
	end
	local parts = PN.parts(note)
	for _, p in ipairs(parts) do
		local size = 0
		for _, sec in ipairs(p.sections) do
			for _, it in ipairs(sec.items) do
				size = size + #it.text + #(it.lead or "") + 40
			end
		end
		assert(size <= PN.partBudget, name .. ": a part is too big")
	end
	same(join(parts), note, name .. " parts join back")
	real = real + 1
end
assert(real >= 1, "no notes files found in data/patchnotes")

print("patchnotes_test: OK (" .. real .. " notes file(s))")

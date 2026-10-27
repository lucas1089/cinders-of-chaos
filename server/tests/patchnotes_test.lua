-- Run from the server/ folder: luajit tests/patchnotes_test.lua (and lua5.3; CI runs both)
-- Pure logic of the patch notes (patchnotes_core.lua): parsing a notes file, the file list, newest-first order, the
-- "last seen" key and the login auto-open choice. Also parses every real file of data/patchnotes/.
dofile("data/scripts/chaos/patchnotes_core.lua")
local PN = ChaosPatchNotes

local check
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
do
	local cutText = PN.parse("## New\n- " .. string.rep("ç", 600), "x").sections[1].items[1].text
	eq(cutText:sub(-3), "...", "utf-8 cut ellipsis")
	assert(not cutText:sub(1, -4):find("[\192-\255]$"), "utf-8 cut leaves no half character")
	assert(#cutText <= PN.limits.text, "utf-8 cut size")
end
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

-- ---------------------------------------------------------------- pt-BR twins
local listing2 = "2026-10-08.md\n2026-10-08.pt-br.md\n2026-10-09.PT-BR.md\n_draft.pt-br.md\nREADME.md\nbad name.pt-br.md\n2026-10-08.pt-br.md\n"
local names2 = PN.fileNames(listing2)
eq(#names2, 1, "twins are not notes of their own")
eq(names2[1], "2026-10-08.md", "the English file stays")
local tw = PN.twinNames(listing2)
eq(tw["2026-10-08"], "2026-10-08.pt-br.md", "twin paired by id")
eq(tw["2026-10-09"], "2026-10-09.PT-BR.md", "twin suffix any case")
eq(tw["_draft"], nil, "draft twin skipped")
eq(tw["bad name"], nil, "bad id skipped")
eq(next(PN.twinNames(nil)), nil, "no listing")
eq(PN.lang("pt-BR"), "pt-BR", "lang pt-BR")
eq(PN.lang("pt_br"), "pt-BR", "lang pt_br")
eq(PN.lang("pt"), "pt-BR", "lang pt")
eq(PN.lang("en"), "en", "lang en")
eq(PN.lang(nil), "en", "lang nil")
eq(PN.lang("de"), "en", "other language falls back")

local EN = "# Week\nDate: 2026-10-08\n\nIntro.\n\n## New\n- **Big.** thing\n  - sub\n- plain\n\n## Fixes\n- a fix\n"
local PT = "# Semana\nDate: 2026-10-08\n\nIntro.\n\n## Novidades\n- **Grande.** coisa\n  - sub\n- simples\n\n## Correções\n- uma correção\n"
local en = PN.parse(EN, "2026-10-08")
local pt = PN.parse(PT, "2026-10-08")
eq(pt.sections[1].kind, "new", "pt-BR Novidades is New")
eq(pt.sections[2].kind, "fixes", "pt-BR Correções is Fixes")
eq(PN.parse("## Mudanças\n- x\n## Balanceamento\n- y", "a").sections[1].kind, "changes", "Mudanças")
eq(PN.parse("## Mudanças\n- x\n## Balanceamento\n- y", "a").sections[2].kind, "balance", "Balanceamento")
eq(PN.compare(en, pt), nil, "same shape")
local bad = PN.parse(PT:gsub("%- simples\n", ""), "x")
check = PN.compare(en, bad)
assert(check and check:find("items"), "a missing bullet is found: " .. tostring(check))
assert(PN.compare(en, PN.parse(PT .. "## Balanceamento\n- x\n", "x")), "an extra section is found")
assert(PN.compare(en, PN.parse(PT:gsub("Intro%.", "Intro.\n\nTwo."), "x")), "an extra intro line is found")

eq(PN.localize(en, "pt-BR"), en, "no twin: English")
en.tr = {["pt-BR"] = pt}
local loc = PN.localize(en, "pt-BR")
eq(loc.title, "Semana", "twin title")
eq(loc.sections[1].name, "Novidades", "twin sections")
eq(loc.id, "2026-10-08", "id from the English note")
eq(PN.localize(en, "en"), en, "English player gets English")
eq(PN.localize(en, nil), en, "no language: English")
eq(PN.summary({en}, nil, nil, "pt-BR")[1].title, "Semana", "summary title in pt-BR")
eq(PN.summary({en}, nil, nil, "en")[1].title, "Week", "summary title in English")
eq(PN.summary({en}, nil)[1].title, "Week", "summary default English")
eq(#PN.parts(PN.localize(en, "pt-BR"))[1].sections, 2, "parts of the twin")

-- ---------------------------------------------------------------- Discord digest and dedupe
local posts = PN.discordPosts(en, "en")
eq(#posts, 1, "one short message")
eq(posts[1].title, "Patch notes 2026-10-08: Week", "English title")
assert(posts[1].text:find("**New**", 1, true), "section heading")
assert(posts[1].text:find("- **Big.** thing", 1, true), "bullet with its lead")
assert(not posts[1].text:find("sub", 1, true), "sub-bullets are left out")
local pposts = PN.discordPosts(PN.localize(en, "pt-BR"), "pt-BR")
eq(pposts[1].title, "Notas de atualização 2026-10-08: Semana", "pt-BR title")
assert(pposts[1].text:find("**Novidades**", 1, true), "pt-BR heading")

local big = {id = "x", date = "2026-11-01", title = "Big", intro = {"Hello."}, sections = {{name = "New", kind = "new", items = {}}}}
for i = 1, 80 do
	big.sections[1].items[i] = {lead = "Lead " .. i .. ".", text = string.rep("word ", 60), level = 1}
end
local many = PN.discordPosts(big, "en")
eq(#many, PN.discordDefaults.maxParts, "capped at maxParts")
for i, p in ipairs(many) do
	assert(#p.text <= 2000, "message " .. i .. " fits Discord's 2000 characters: " .. #p.text)
	assert(#p.title <= 250, "title length")
	assert(p.title:find("(" .. i .. "/" .. #many .. ")", 1, true), "part number in the title")
end
assert(many[#many].text:find("More in game", 1, true), "the last message points to the game")
local one = PN.discordPosts(big, "en", {maxParts = 2, maxChars = 900})
eq(#one, 2, "options apply")
for _, p in ipairs(one) do
	assert(#p.text <= 900, "custom size")
end
-- no half UTF-8 character at a cut
local u = PN.discordPosts({id = "u", date = "2026-11-01", title = "U", intro = {}, sections = {{name = "Novidades", kind = "new",
	items = {{text = string.rep("ação ", 80), level = 1}}}}}, "pt-BR", {bulletChars = 33})
assert(not u[1].text:find("[\194-\244]%.%.%."), "cut keeps UTF-8 whole")

local n1 = {id = "a", date = "2026-10-08"}
local n2 = {id = "b", date = "2026-10-20"}
local n3 = {id = "c", date = "2026-10-31"}
local sorted = {n3, n2, n1}
eq(PN.dueForDiscord(sorted, "", "2026-10-27").id, "b", "newest note dated today or earlier")
eq(PN.dueForDiscord(sorted, nil, "2026-10-31").id, "c", "a note waits for its day, then posts")
eq(PN.dueForDiscord(sorted, PN.key(n2), "2026-10-27"), nil, "already posted")
eq(PN.dueForDiscord(sorted, PN.key(n2), "2026-10-31").id, "c", "a newer one after it")
eq(PN.dueForDiscord(sorted, PN.key(n3), "2026-12-01"), nil, "nothing newer")
eq(PN.dueForDiscord({}, "", "2026-10-27"), nil, "no notes")
eq(PN.dueForDiscord(sorted, "", nil).id, "c", "no date check without a date")

local function runEnv(notes, posted, opts)
	local env = {saved = nil, queued = {}, logs = {}}
	env.notes, env.postedKey, env.today, env.opts = notes, posted, "2026-10-27", opts or {enabled = true}
	env.event = function(title, text) return {kind = "patchnotes", title = title, text = text} end
	env.queue = function(ev) env.queued[#env.queued + 1] = ev return true end
	env.save = function(key) env.saved = key end
	env.log = function(t) env.logs[#env.logs + 1] = t end
	return env
end
local withTwin = {id = "b", date = "2026-10-20", title = "Week", intro = {}, sections = en.sections, tr = {["pt-BR"] = pt}}
local env = runEnv({withTwin}, "")
eq(PN.discordRun(env), 2, "English and pt-BR queued")
eq(env.saved, "2026-10-20|b", "key saved")
assert(env.queued[1].title:find("Patch notes", 1, true), "English first")
assert(env.queued[2].title:find("Notas de atualização", 1, true), "pt-BR second")
-- a second run with the saved key posts nothing
local env2 = runEnv({withTwin}, env.saved)
eq(PN.discordRun(env2), 0, "idempotent")
eq(env2.saved, nil, "nothing saved again")
-- no twin: English only
local env3 = runEnv({{id = "b", date = "2026-10-20", title = "Week", intro = {}, sections = en.sections}}, "")
eq(PN.discordRun(env3), 1, "English only without a twin")
-- switched off
local env4 = runEnv({withTwin}, "", {enabled = false})
eq(PN.discordRun(env4), 0, "off")
eq(env4.saved, nil, "off saves nothing")
-- a failed queue still saves the key (at most once)
local env5 = runEnv({withTwin}, "")
env5.queue = function() return false end
eq(PN.discordRun(env5), 0, "nothing queued")
eq(env5.saved, "2026-10-20|b", "key saved before queueing")

-- ---------------------------------------------------------------- the real files
local ls = io.popen and io.popen('ls -1 data/patchnotes 2>/dev/null')
local listing = ls and ls:read("*a") or ""
if ls then
	ls:close()
end
local real = 0
local twins = PN.twinNames(listing)
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
	-- every English note has a pt-BR twin with the same sections and bullets
	local id = name:sub(1, -4)
	assert(twins[id], name .. ": no pt-BR twin (" .. id .. ".pt-br.md)")
	local tf = assert(io.open("data/patchnotes/" .. twins[id], "rb"))
	local tbody = tf:read("*a")
	tf:close()
	local tnote = PN.parse(tbody, id)
	assert(tnote.date == note.date, twins[id] .. ": the Date line differs from " .. name)
	assert(tnote.title ~= note.title, twins[id] .. ": the title is not translated")
	local why = PN.compare(note, tnote)
	assert(not why, twins[id] .. " does not match " .. name .. ": " .. tostring(why))
	for _, sec in ipairs(tnote.sections) do
		assert(sec.kind ~= "other", twins[id] .. ": unknown section " .. sec.name)
		for _, it in ipairs(sec.items) do
			assert(#it.text < PN.limits.text, twins[id] .. ": a bullet was cut: " .. it.text:sub(1, 40))
		end
	end
	assert(not tbody:find("\226\128\148", 1, true), twins[id] .. ": em dash")
	for _, p in ipairs(PN.parts(tnote)) do
		local size = 0
		for _, sec in ipairs(p.sections) do
			for _, it in ipairs(sec.items) do
				size = size + #it.text + #(it.lead or "") + 40
			end
		end
		assert(size <= PN.partBudget, twins[id] .. ": a part is too big")
	end
	twins[id] = nil
	real = real + 1
end
assert(real >= 1, "no notes files found in data/patchnotes")
for id in pairs(twins) do
	error("pt-BR twin without an English note: " .. id)
end

print("patchnotes_test: OK (" .. real .. " notes file(s))")

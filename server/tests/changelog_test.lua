-- Run from the server/ folder: luajit tests/changelog_test.lua (and lua5.3; CI runs both)
-- The Changelog tab of the Patch Notes window: changelog_core.lua (the file from server/tools/gen_changelog.py is never
-- trusted: size, JSON, types, lengths, tags) and the serving in patchnotes.lua against a mocked engine (the file read
-- again only after rescanSeconds, a bad file keeping the last good one, the answer chunked over 8192 bytes, the
-- per-player cooldown).
dofile("data/scripts/chaos/changelog_core.lua")
local CL = ChaosChangelog

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- entries
local good = {id = "0123456789ab", date = "2026-10-21", ts = 1791000000, pr = 52, text = "Bank: deposits work",
	tags = {"client", "server", "server", "bogus"}, client = 55, pending = false}
local e = CL.entry(good)
eq(e.text, "Bank: deposits work", "text")
eq(#e.tags, 2, "duplicate and unknown tags dropped")
eq(e.tags[1], "server", "tags in a fixed order")
eq(e.tags[2], "client", "client second")
eq(e.client, 55, "client version")
eq(e.pending, false, "published")
eq(e.pr, 52, "pr")
eq(CL.entry({date = "2026-10-21", text = "x", tags = {"server"}}).client, nil, "no client field without the tag")
local p = CL.entry({date = "2026-10-21", text = "x", tags = {"client"}})
eq(p.client, nil, "no version")
eq(p.pending, true, "no version: pending")
eq(p.id, "", "missing id")
eq(CL.entry({date = "2026-10-21", text = "x", tags = {"client"}, client = 1.5}).client, nil, "fractional version dropped")
eq(CL.entry({date = "2026-10-21", text = "x", tags = {"client"}, client = 1e12}).client, nil, "huge version dropped")
eq(CL.entry({date = "2026-10-21", text = "x", tags = {"server"}, id = "../../etc"}).id, "", "odd id dropped")
eq(CL.entry({date = "2026-10-21", text = "x", tags = {"server"}, pr = -1}).pr, nil, "negative pr dropped")
eq(CL.entry({date = "21/10/2026", text = "x", tags = {"server"}}), nil, "bad date: entry dropped")
eq(CL.entry({date = "2026-10-21", text = "   ", tags = {"server"}}), nil, "empty text: dropped")
eq(CL.entry({date = "2026-10-21", text = 5, tags = {"server"}}), nil, "text not a string")
eq(CL.entry({date = "2026-10-21", text = "x", tags = {"nope"}}), nil, "no known tag: dropped")
eq(CL.entry({date = "2026-10-21", text = "x", tags = "server"}), nil, "tags not a list")
eq(CL.entry("x"), nil, "not a table")
eq(CL.entry({date = "2026-10-21", text = "a\0b\n\tc\27[31m", tags = {"server"}}).text, "a b c [31m", "control chars out")
local long = CL.entry({date = "2026-10-21", text = string.rep("a", 500), tags = {"server"}}).text
eq(#long, CL.limits.text, "long text cut")
eq(long:sub(-3), "...", "cut marked")
-- a cut never splits a UTF-8 character ("ã" is two bytes)
local utf = CL.text(string.rep("a", 196) .. string.rep("\195\163", 10), 200)
eq(utf, string.rep("a", 196) .. "...", "UTF-8 cut backs off a continuation byte")
local utf2 = CL.text(string.rep("a", 195) .. string.rep("\195\163", 10), 200)
eq(utf2, string.rep("a", 195) .. "\195\163" .. "...", "a whole character kept")

-- ---------------------------------------------------------------- the file
local many = {}
for i = 1, 400 do
	many[i] = {date = "2026-10-21", text = "change " .. i, tags = {"server"}}
end
local v = CL.validate({server = {date = "2026-10-21", ts = 5}, published = 55, entries = many})
eq(#v.entries, CL.limits.entries, "entries capped")
eq(v.server.date, "2026-10-21", "server date")
eq(v.published, 55, "published")
eq(CL.validate({server = {date = "bad"}, published = "55", entries = {}}).server.date, "", "bad server date")
eq(CL.validate({entries = {}}).published, nil, "published must be a number")
eq(CL.validate({}), nil, "no entries: refused")
eq(CL.validate("x"), nil, "not an object")
local JSON = {}
local function dec(s)
	local val = JSON[s]
	if val == nil then
		error("bad json")
	end
	return val
end
JSON["ok"] = {entries = {good}}
eq(#CL.decode("ok", dec).entries, 1, "decode")
eq(CL.decode("garbage", dec), nil, "bad JSON refused")
eq(select(2, CL.decode("garbage", dec)), "bad JSON", "reason")
eq(CL.decode(string.rep(" ", CL.limits.fileBytes + 1), dec), nil, "oversize refused before decoding")
eq(CL.decode("", dec), nil, "empty")
eq(CL.decode("ok", nil), nil, "no decoder")
eq(CL.payload(nil).available, false, "no file: not available")
eq(#CL.payload(nil).entries, 0, "no file: no entries")
eq(CL.payload(v).available, true, "available")

-- ---------------------------------------------------------------- patchnotes.lua serving (mocked engine)
local tmp = os.tmpname()
local events, sent = {}, {}
local clock = 1000
local realTime = os.time
os.time = function(t)
	if t then
		return realTime(t)
	end
	return clock
end
function CreatureEvent(name)
	local o = {name = name}
	function o:type() end
	function o:register()
		events[name] = o
	end
	return o
end
function GlobalEvent(name)
	return CreatureEvent(name)
end
function TalkAction()
	local o = {}
	function o:separator() end
	function o:register() end
	return o
end
db = {query = function() return true end, storeQuery = function() return false end, escapeString = function(s)
	return "'" .. s .. "'"
end}
json = {decode = dec, encode = function(t)
	-- a stand-in: as long as the real encoding of the entries would be about
	local n = 40
	if type(t) == "table" and type(t.data) == "table" and type(t.data.entries) == "table" then
		n = n + 150 * #t.data.entries
	end
	return "{" .. string.rep("x", n - 2) .. "}"
end}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.limited = nil
local PN = ChaosPatchNotes
dofile("data/scripts/chaos/patchnotes.lua")
PN = ChaosPatchNotes
PN.config.changelogFile = tmp

local function player(id)
	return {getId = function() return id end, sendExtendedOpcode = function(_, op, buf)
		sent[#sent + 1] = {id = id, op = op, buf = buf}
		return true
	end}
end
local function write(text)
	local f = assert(io.open(tmp, "wb"))
	f:write(text)
	f:close()
end
local function ask(pl)
	sent = {}
	events.ChaosPatchNotesExtended.onExtendedOpcode(pl, ChaosOpcodes.patchnotes, "req")
	return sent
end
JSON["req"] = {action = "changelog"}

-- no file yet: an empty answer, not an error
os.remove(tmp)
PN.loadChangelog(true)
local a = ask(player(1))
eq(#a, 1, "no file: one message")
eq(a[1].op, ChaosOpcodes.patchnotes, "on opcode 244")

-- a file of 100 entries: about 15 KB, sent in parts
local list = {}
for i = 1, 100 do
	list[i] = {date = "2026-10-21", text = "change " .. i, tags = {"server"}}
end
JSON["file1"] = {server = {date = "2026-10-21"}, entries = list}
write("file1")
clock = clock + 100 -- after rescanSeconds
a = ask(player(2))
eq(#a, 2, "15 KB answer: two parts")
eq(a[1].buf:sub(1, 1), "S", "start part")
eq(a[2].buf:sub(1, 1), "E", "end part")
eq(#a[1].buf <= 8192, true, "each part fits")

-- the per-player cooldown
eq(#ask(player(2)), 0, "asked again at once: nothing")
clock = clock + PN.config.changelogCooldown
eq(#ask(player(2)), 2, "after the cooldown")

-- a broken file keeps the last good one
write("garbage")
clock = clock + 100
eq(#ask(player(3)), 2, "bad file: the last good answer")
-- an oversize file too
write(string.rep(" ", CL.limits.fileBytes + 10))
clock = clock + 100
eq(#ask(player(4)), 2, "oversize file: the last good answer")
-- a small good file replaces it
JSON["file2"] = {entries = {good}}
write("file2")
eq(#ask(player(5)), 2, "within rescanSeconds: the cached answer")
clock = clock + 100
eq(#ask(player(6)), 1, "new file read after rescanSeconds: small, one message")
-- logout forgets the cooldown
events.ChaosPatchNotesLogout.onLogout(player(6))
eq(#ask(player(6)), 1, "after a logout: asked again")

os.remove(tmp)
os.time = realTime
print("changelog_test: OK")

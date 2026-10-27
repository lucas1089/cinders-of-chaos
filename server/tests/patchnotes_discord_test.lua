-- Run from the server/ folder: luajit tests/patchnotes_discord_test.lua (and lua5.3; CI runs both)
-- The automatic Discord post of a new patch note (patchnotes.lua PN.postDiscord, patchnotes_core.lua PN.discordRun,
-- discord_core.lua D.patchnotes) against a mocked engine and the real files of data/patchnotes/: English and pt-BR rows
-- for the ANNOUNCE channel, posted once (the key kept in server_config, also over a restart), a note dated in the
-- future waits for its day, the config switches, and the pt-BR note a pt-BR player gets (fallback English).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/discord_config.lua")
dofile("data/scripts/chaos/discord_core.lua")
local D, cfg = ChaosDiscordCore, ChaosDiscordConfig

-- ------------------------------------------------------------------ the event
local ev = D.patchnotes(cfg, "Patch notes 2026-10-20: Week", string.rep("x", 3000))
eq(ev.kind, "patchnotes", "kind")
eq(ev.channel, "announce", "the ANNOUNCE channel")
eq(#ev.text, 2000, "text clipped to Discord's 2000")
check(D.enabled(cfg, "patchnotes"), "on by default")
check(not D.enabled({enabled = true, events = {patchnotes = false}}, "patchnotes"), "event switch")
check(cfg.patchnotes and cfg.patchnotes.enabled == true, "config switch on by default")
check(cfg.patchnotes.maxChars <= 2000, "message size within the content limit")
local rowLen = D.insertSql(cfg.table, ev, 1, function(s) return "'" .. s .. "'" end, function() return "[]" end)
check(rowLen:find("'patchnotes'", 1, true) and rowLen:find("'announce'", 1, true), "the queue row")
-- the worker knows the kind (website discord_lib.php KINDS), so the row is posted and not rejected
local f = assert(io.open("../website/overlay/plugins/chaos/discord_lib.php", "rb"))
local php = f:read("*a")
f:close()
check(php:find("'patchnotes'", 1, true) ~= nil, "the worker lists the patchnotes kind")
check(php:find("'patchnotes' =>", 1, true) ~= nil, "and gives it a colour")

-- ------------------------------------------------------------------ patchnotes.lua against a mocked engine
local configRows, queries = {}, {}
local function esc(s)
	return "'" .. tostring(s):gsub("'", "''") .. "'"
end
db = {
	escapeString = esc,
	query = function(s)
		queries[#queries + 1] = s
		local key, v = s:match("VALUES %('([^']+)', '([^']+)'%)")
		if key and s:find("server_config", 1, true) then
			configRows[key] = v
		end
		return true
	end,
	storeQuery = function(s)
		local key = s:match("`config` = '([^']+)'")
		if key and configRows[key] then
			return key
		end
		return false
	end
}
result = {getString = function(id) return configRows[id] end, free = function() end}
json = {encode = function() return "{}" end, decode = function() return nil end}
local globals, added = {}, {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type() end
	function e:register() end
	return e
end
function GlobalEvent(name)
	local e = {name = name}
	function e:interval(ms) self.ms = ms end
	function e:register() globals[name] = self end
	return e
end
function TalkAction()
	local e = {}
	function e:separator() end
	function e:register() end
	return e
end
function addEvent(fn, ms) added[#added + 1] = {fn = fn, ms = ms} end
Player = function() return nil end

local today = "2026-10-27"
local realDate = os.date
os.date = function(fmt, t)
	if fmt == "%Y-%m-%d" then
		return today
	end
	return realDate(fmt, t)
end

local queued = {}
ChaosDiscord = {queue = function(e) queued[#queued + 1] = e return true end}

dofile("data/scripts/chaos/patchnotes.lua")
local PN = ChaosPatchNotes
check(globals.ChaosPatchNotesDiscord ~= nil, "an hourly check is registered")
eq(globals.ChaosPatchNotesDiscord.ms, 3600 * 1000, "checked every hour")

PN.scan(true)
eq(PN.notes[1].id, "2026-10-31", "the newest real note")
check(PN.notes[1].tr and PN.notes[1].tr["pt-BR"], "paired with its pt-BR twin")
for _, n in ipairs(PN.notes) do
	check(n.tr and n.tr["pt-BR"], n.id .. " has a twin")
end

-- startup: scans and schedules the first post after the delay
globals.ChaosPatchNotesStartup.onStartup()
check(#added >= 1 and added[#added].ms == cfg.patchnotes.startDelaySeconds * 1000, "startup schedules the post")

-- 27 October: the 31 October note waits; 22 October is the newest due note
local n = PN.postDiscord()
local rows = #queued
check(n >= 2, "English and pt-BR queued: " .. n)
eq(configRows[cfg.patchnotes.postedKey], "2026-10-22|2026-10-22", "the key of the note posted")
check(queued[1].title:find("Patch notes 2026-10-22: Wings, crowns and capes", 1, true), "English first: " .. queued[1].title)
check(queued[1].kind == "patchnotes" and queued[1].channel == "announce", "ANNOUNCE channel")
local sawPt = false
for i, e in ipairs(queued) do
	check(#e.text <= 2000, "row " .. i .. " within 2000 characters")
	if e.title:find("Notas de atualização 2026-10-22: Asas, coroas e capas", 1, true) then
		sawPt = true
		check(i > 1, "pt-BR after the English rows")
	end
	check(not e.text:find("http", 1, true) and not e.text:find("webhook", 1, true), "no URL or webhook in a row")
end
check(sawPt, "a pt-BR row")
eq(n, rows, "returned the number queued")

-- again (the hourly check): nothing
eq(PN.postDiscord(), 0, "not posted twice")
eq(#queued, rows, "no new rows")

-- a restart (the script loads again, the key is in server_config)
dofile("data/scripts/chaos/patchnotes.lua")
eq(ChaosPatchNotes.postDiscord(), 0, "a restart does not post again")
eq(#queued, rows, "still no new rows")

-- the 31st arrives: the beta note goes out, once
today = "2026-10-31"
local n2 = ChaosPatchNotes.postDiscord()
check(n2 >= 2, "the new note posts on its day")
eq(configRows[cfg.patchnotes.postedKey], "2026-10-31|2026-10-31", "key moved")
check(queued[rows + 1].title:find("Open Beta: the ash is falling", 1, true), "English beta note")
eq(ChaosPatchNotes.postDiscord(), 0, "and not again")

-- switches
configRows[cfg.patchnotes.postedKey] = nil
local before = #queued
cfg.patchnotes.enabled = false
eq(ChaosPatchNotes.postDiscord(), 0, "patchnotes.enabled = false: nothing")
eq(configRows[cfg.patchnotes.postedKey], nil, "and nothing remembered")
cfg.patchnotes.enabled = true
cfg.events.patchnotes = false
eq(ChaosPatchNotes.postDiscord(), 0, "events.patchnotes = false: nothing")
cfg.events.patchnotes = true
cfg.enabled = false
eq(ChaosPatchNotes.postDiscord(), 0, "discord disabled: nothing")
cfg.enabled = true
eq(#queued, before, "no rows while off")
local savedQueue = ChaosDiscord
ChaosDiscord = nil
eq(ChaosPatchNotes.postDiscord(), 0, "discord.lua not loaded: nothing, not remembered")
eq(configRows[cfg.patchnotes.postedKey], nil, "not remembered")
ChaosDiscord = savedQueue
check(ChaosPatchNotes.postDiscord() >= 2, "back on: posts the newest due note")

-- a queue table failure must not break the check
ChaosDiscord = {queue = function() error("db down") end}
configRows[cfg.patchnotes.postedKey] = nil
check(pcall(ChaosPatchNotes.tryPost), "a failing queue is caught by the hourly check")
ChaosDiscord = savedQueue

-- ------------------------------------------------------------------ what a player sees
local function player(lang)
	local p = {}
	function p:getAccountId() return 1 end
	function p:getId() return 1 end
	return p, lang
end
local sent = {}
Chaos.lang = function(p) return p.lang end
Chaos.send = function(p, op, action, data) sent[#sent + 1] = {action = action, data = data} end
Chaos.select = function() return {} end
local pt = {lang = "pt-BR", getAccountId = function() return 1 end}
local en = {lang = "en", getAccountId = function() return 1 end}
ChaosPatchNotes.scan(true)
ChaosPatchNotes.sendList(pt, {})
eq(sent[#sent].data.weeks[1].title, "Open Beta: as cinzas estão caindo", "pt-BR week list")
ChaosPatchNotes.sendList(en, {})
eq(sent[#sent].data.weeks[1].title, "Open Beta: the ash is falling", "English week list")
sent = {}
check(ChaosPatchNotes.sendNote(pt, "2026-10-09"), "send a note")
eq(sent[1].data.title, "Orbs com vontade própria", "pt-BR note title")
eq(sent[1].data.sections[1].name, "Novidades", "pt-BR section heading")
sent = {}
ChaosPatchNotes.sendNote(en, "2026-10-09")
eq(sent[1].data.title, "Orbs with a will of their own", "English note")
-- no twin: English for everyone
local byId = ChaosPatchNotes.byId["2026-10-09"]
local saved = byId.tr
byId.tr = nil
sent = {}
ChaosPatchNotes.sendNote(pt, "2026-10-09")
eq(sent[1].data.title, "Orbs with a will of their own", "no twin: a pt-BR player gets English")
byId.tr = saved

os.date = realDate
print(string.format("patchnotes_discord_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

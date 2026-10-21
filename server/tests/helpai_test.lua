-- Run from the server/ folder: luajit tests/helpai_test.lua (or lua5.3; CI runs both)
-- Ember, the Help channel assistant: helpai_core.lua (triggers, limits, the queue and answer lines, chat lines, the
-- channel's audience) and helpai.lua against a mocked engine (no sidecar: nothing queued; a question queued; the answer
-- posted to the channel or to the asker; refusals and limits told to the asker only).
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/helpai_core.lua")
local H = ChaosHelpAICore
local cfg = dofile("data/scripts/chaos/helpai_config.lua")

-- ================================================================== triggers
local q, explicit = H.detect("?how do I ascend my warrior", cfg, false)
eq(q, "how do I ascend my warrior", "? trigger: the question after it")
eq(explicit, true, "? is explicit")
q, explicit = H.detect("Ember, where is the rift?", cfg, false)
eq(q, "where is the rift?", "the bot's name and a comma")
eq(explicit, true, "the name is explicit")
q = H.detect("ember: como faço a ascensão", cfg, false)
eq(q, "como faço a ascensão", "the name is case blind, a colon works")
q = H.detect("@Ember what are orbs for", cfg, false)
eq(q, "what are orbs for", "@name works")
q, explicit = H.detect("  how do I get to the arena?  ", cfg, false)
eq(q, "how do I get to the arena?", "a plain question ending in ? (trimmed)")
eq(explicit, false, "is automatic")
eq((H.detect("how do I get to the arena?", cfg, true)), nil, "staff lines are never automatic")
q = H.detect("?how do I get to the arena", cfg, true)
eq(q, "how do I get to the arena", "staff may still ask explicitly")
eq((H.detect("anyone?", cfg, false)), nil, "too few words for an automatic question")
eq((H.detect("hello everyone", cfg, false)), nil, "not a question")
eq((H.detect("Ember is great, right?", cfg, false)), "Ember is great, right?", "the name without , or : is a plain line")
eq((H.detect("!mute Bob, spam?", cfg, false)), nil, "commands are not questions")
local none, why, ex = H.detect("?hi", cfg, false)
eq(none, nil, "too short")
eq(why, "short", "reason short")
eq(ex, true, "and it was meant for Ember")
none, why = H.detect("?" .. string.rep("a", 201), cfg, false)
eq(why, "long", "too long")
q = H.detect("?what\1is\9this", cfg, false)
eq(q, "what is this", "control characters become spaces")
eq((H.detect("", cfg, false)), nil, "empty")
eq((H.detect(nil, cfg, false)), nil, "not text")
local noAuto = {autoQuestions = false, botName = "Ember"}
eq((H.detect("how do I get to the arena?", noAuto, false)), nil, "autoQuestions off")

-- ================================================================== limits
local st = H.newState()
local c = {cooldownSeconds = 20, perDay = 3, globalPerMinute = 4, pendingSeconds = 90}
check(H.allow(st, c, 1, 1000, "d1"), "first question allowed")
local id1 = H.record(st, 1, "Alice", "en", true, 1000)
local ok, reason = H.allow(st, c, 1, 1005, "d1")
eq(ok, false, "a pending question blocks the next")
eq(reason, "pending", "reason pending")
eq(H.claim(st, c, id1, 1006).name, "Alice", "the answer claims the pending question")
eq(H.claim(st, c, id1, 1006), nil, "only once")
local wait
ok, reason, wait = H.allow(st, c, 1, 1010, "d1")
eq(reason, "cooldown", "cooldown after an answer")
eq(wait, 10, "seconds left")
check(H.allow(st, c, 1, 1020, "d1"), "allowed after the cooldown")
H.claim(st, c, H.record(st, 1, "Alice", "en", true, 1020), 1021)
H.claim(st, c, H.record(st, 1, "Alice", "en", true, 1040), 1041)
ok, reason = H.allow(st, c, 1, 1100, "d1")
eq(reason, "day", "the daily cap")
check(H.allow(st, c, 1, 1100, "d2"), "a new day starts again")
check(H.allow(st, c, 2, 1100, "d2"), "another player is free")
-- global: 4 in the last minute (3 at 1020/1040 are older than a minute at 1100)
local st2 = H.newState()
for g = 1, 4 do
	H.claim(st2, c, H.record(st2, g, "P" .. g, "en", false, 2000), 2000)
end
ok, reason = H.allow(st2, c, 9, 2010, "d")
eq(reason, "busy", "the server's limit per minute")
check(H.allow(st2, c, 9, 2061, "d"), "free again a minute later")
-- an unanswered question is forgotten after pendingSeconds
local st3 = H.newState()
local lost = H.record(st3, 5, "E", "en", true, 100)
check(H.allow(st3, c, 5, 100 + 91, "d"), "a lost question does not block forever")
eq(H.claim(st3, c, lost, 200), nil, "and is dropped")

-- ================================================================== lines
local line = H.queueLine("1-1", 42, "pt-BR", 'quote " back \\ tab\9 é', 1234)
eq(line, '{"guid":42,"id":"1-1","lang":"pt-BR","t":1234,"text":"quote \\" back \\\\ tab\\t é"}', "queue line, sorted keys")
local back = H.decode(line)
eq(back.text, 'quote " back \\ tab\9 é', "round trip")
eq(back.guid, 42, "numbers")
eq(H.queueLine("x", 1, "de", "q", 1):match('"lang":"(%a+)"'), "en", "an unknown language is sent as en")
eq(H.decode(H.queueLine("x", 1, "pt-BR", "ascens\227o", 1)).text, "ascensão", "Latin-1 from the client becomes UTF-8")
eq(H.toUtf8("ascensão"), "ascensão", "UTF-8 is kept")
check(H.isUtf8("plain") and not H.isUtf8("\195") and not H.isUtf8("\237"), "UTF-8 check")
local d = H.decode('{"a": "\\u00e9\\u00e7", "b": true, "c": false, "n": -1.5e2, "s": "\\ud83d\\ude00", "z": null}')
eq(d and d.a, "éç", "\\u escapes to UTF-8")
eq(d and d.b, true, "true")
eq(d and d.c, false, "false")
eq(d and d.n, -150, "exponent")
eq(d and d.s, "\240\159\152\128", "surrogate pair")
for _, bad in ipairs({"", "[]", "{", '{"a":}', '{"a" 1}', '{"a":[1]}', '{"a":{"b":1}}', '{"a":"x"', '{"a":1,}', "nope"}) do
	eq(H.decode(bad), nil, "bad JSON refused: " .. bad)
end
check(H.decode("{}") ~= nil, "empty object")
local answers = H.parseAnswers(
	'{"id":"1-1","guid":42,"status":"ok","text":"Use the Oracle."}\n' ..
	'garbage\n' ..
	'{"id":"1-2","guid":43,"status":"weird","text":"x"}\n' ..
	'{"id":"1-3","guid":44,"status":"busy","text":""}\n')
eq(#answers, 2, "two good answers, bad lines skipped")
eq(answers[1].text, "Use the Oracle.", "the text")
eq(answers[2].status, "busy", "a status without text")
eq(#H.parseAnswers(nil), 0, "no file, no answers")

eq(H.aliveState('{"t":1000,"state":"on"}', 1010, 30), "on", "fresh heartbeat")
eq(H.aliveState('{"t":1000,"state":"budget"}', 1010, 30), "budget", "budget spent")
eq(H.aliveState('{"t":1000,"state":"on"}', 1031, 30), nil, "stale heartbeat")
eq(H.aliveState(nil, 1000, 30), nil, "no file")
eq(H.aliveState('{"t":1000,"state":"party"}', 1000, 30), nil, "unknown state")

-- ================================================================== chat lines
local split = H.split("short answer", 240, 4)
eq(#split, 1, "a short answer is one line")
local long = string.rep("word ", 120) -- 600 bytes
split = H.split(long, 100, 4)
eq(#split, 4, "at most maxLines")
for i, l in ipairs(split) do
	check(#l <= 100, "line " .. i .. " fits (" .. #l .. ")")
end
check(split[4]:sub(-3) == "...", "cut text ends in ...")
check(not split[1]:find("wor$"), "cut between words")
split = H.split(string.rep("ã", 100), 51, 2) -- 200 bytes, one long word
check(#split[1] <= 51, "a long word is cut")
check(#split[1] % 2 == 0, "never inside a UTF-8 character")
split = H.split("a b", 240, 4)
eq(split[1], "a b", "plain")
eq(#H.split("", 240, 4), 0, "empty answer, no lines")

local st4 = H.newState()
local cAud = {publicPerMinute = 2}
eq(H.audience(st4, cAud, 10), "public", "first answer public")
eq(H.audience(st4, cAud, 11), "public", "second public")
eq(H.audience(st4, cAud, 12), "private", "a busy channel: to the asker only")
eq(H.audience(st4, cAud, 71), "public", "public again after a minute")

eq(H.text(cfg, "pt-BR", "busy"):sub(1, 5), "Ember", "pt-BR text")
eq(H.text(cfg, "xx", "busy"), cfg.texts.en.busy, "unknown language: English")
check(H.text(cfg, "en", "cooldown", 20, 7):find("7 s", 1, true) ~= nil, "formatted text")
for lang, t in pairs(cfg.texts) do
	for key in pairs(cfg.texts.en) do
		check(type(t[key]) == "string", lang .. " has " .. key)
	end
end

-- ================================================================== the engine file, mocked engine
Chaos = {lang = function(p)
	return p.lang
end}
ACCOUNT_TYPE_TUTOR = 2
TALKTYPE_CHANNEL_O = 8
local registered = {}
function GlobalEvent(name)
	local ev = {name = name}
	function ev:interval(ms)
		self.ms = ms
	end
	function ev:register()
		registered[self.name] = self
	end
	return ev
end
local channel = {}
function sendChannelMessage(cid, tt, text)
	channel[#channel + 1] = {cid = cid, tt = tt, text = text}
end
local players = {}
local function newPlayer(name, guid, lang, accountType)
	local p = {name = name, guid = guid, lang = lang, at = accountType or 1, got = {}}
	function p:getName()
		return self.name
	end
	function p:getGuid()
		return self.guid
	end
	function p:getAccountType()
		return self.at
	end
	function p:sendChannelMessage(author, text, tt, cid)
		self.got[#self.got + 1] = {author = author, text = text, tt = tt, cid = cid}
	end
	players[name] = p
	return p
end
function Player(name)
	return players[name]
end

local files = {}
local clock = 5000
ChaosHelpAI = {fs = {
	read = function(name)
		-- "NOW" in the heartbeat stands for the current time (a running sidecar keeps it fresh)
		return files[name] and (files[name]:gsub("NOW", tostring(clock)))
	end,
	append = function(name, text)
		files[name] = (files[name] or "") .. text
		return true
	end,
	remove = function(name)
		files[name] = nil
		return true
	end
}}
ChaosHelpAI.now = function()
	return clock
end
dofile("data/scripts/chaos/helpai.lua")
local HA = ChaosHelpAI
check(registered.ChaosHelpAI ~= nil, "the poll is registered")
eq(registered.ChaosHelpAI.ms, 1000, "once a second")

local alice = newPlayer("Alice", 101, "pt-BR")
local tutor = newPlayer("Tutor Tom", 102, "en", 2)

-- no sidecar: nothing is queued, nothing said
HA.onHelpSpeak(alice, 7, "?how do I ascend my warrior")
eq(files["helpai.queue"], nil, "no sidecar: nothing queued")
eq(#alice.got, 0, "and nothing said")

-- the sidecar is on
files["helpai.alive"] = '{"t":NOW,"state":"on"}'
HA.aliveAt = nil
HA.onHelpSpeak(alice, 7, "?how do I ascend my warrior")
local queued = H.decode((files["helpai.queue"] or ""):match("[^\n]+"))
check(queued ~= nil, "the question is queued")
eq(queued and queued.text, "how do I ascend my warrior", "the question text")
eq(queued and queued.lang, "pt-BR", "the player's language")
eq(queued and queued.guid, 101, "the guid")
eq(queued and queued.name, nil, "the name never leaves the server")
HA.onHelpSpeak(tutor, 7, "how do I ascend my warrior?")
eq(select(2, (files["helpai.queue"] or ""):gsub("\n", "")), 1, "a tutor's plain question is not queued")

-- the answer comes back
files["helpai.queue"] = nil
files["helpai.answers"] = H.encode({id = queued.id, guid = 101, status = "ok",
	text = "Fale com o Oráculo Ascendente no templo ao chegar ao nível 100."}) .. "\n"
clock = clock + 3
eq(HA.poll(), 1, "one answer delivered")
eq(files["helpai.answers"], nil, "the answer file is taken")
eq(#channel, 1, "posted in the channel")
eq(channel[1].cid, 7, "the Help channel")
eq(channel[1].tt, 8, "orange, like tutors")
eq(channel[1].text, "[Ember] @Alice: Fale com o Oráculo Ascendente no templo ao chegar ao nível 100.", "named and addressed")

-- cooldown: told to the asker only (no addEvent in the mock: at once)
HA.onHelpSpeak(alice, 7, "?and what about the ranger")
eq(files["helpai.queue"], nil, "cooldown: not queued")
check(alice.got[#alice.got] and alice.got[#alice.got].text:find("Tente de novo", 1, true) ~= nil, "cooldown told in pt-BR")
eq(alice.got[#alice.got].author, "[Ember]", "from Ember")

-- an automatic question that the sidecar refuses: nothing said; an explicit one: told
clock = clock + 30
HA.onHelpSpeak(alice, 7, "what is the meaning of life?")
local q2 = H.decode(files["helpai.queue"]:match("[^\n]+"))
files["helpai.queue"] = nil
local before = #alice.got
files["helpai.answers"] = H.encode({id = q2.id, guid = 101, status = "refused", text = ""}) .. "\n"
HA.poll()
eq(#alice.got, before, "an automatic question that is refused stays silent")
clock = clock + 30
HA.onHelpSpeak(alice, 7, "?tell me a joke please")
local q3 = H.decode(files["helpai.queue"]:match("[^\n]+"))
files["helpai.queue"] = nil
files["helpai.answers"] = H.encode({id = q3.id, guid = 101, status = "busy", text = ""}) .. "\n"
HA.poll()
eq(#alice.got, before + 1, "an explicit question gets the reason")

-- an answer for somebody else's id or a wrong guid is dropped
clock = clock + 30
HA.onHelpSpeak(alice, 7, "?where is the arena")
local q4 = H.decode(files["helpai.queue"]:match("[^\n]+"))
files["helpai.queue"] = nil
local posted = #channel
files["helpai.answers"] = H.encode({id = q4.id, guid = 999, status = "ok", text = "spoof"}) .. "\n"
eq(HA.poll(), 0, "a wrong guid is not delivered")
eq(#channel, posted, "nothing posted")

-- a busy channel: the answer goes to the asker only
local st5 = HA.state
st5.public = {}
for i = 1, cfg.publicPerMinute do
	st5.public[i] = clock
end
clock = clock + 30
HA.onHelpSpeak(alice, 7, "?where is the arena now")
local q5 = H.decode(files["helpai.queue"]:match("[^\n]+"))
files["helpai.queue"] = nil
before = #alice.got
files["helpai.answers"] = H.encode({id = q5.id, guid = 101, status = "ok", text = "North of the temple."}) .. "\n"
HA.poll()
eq(#channel, posted, "busy channel: not public")
eq(alice.got[#alice.got].text, "North of the temple.", "private answer")
eq(#alice.got, before + 1, "one line")

-- the budget is spent: an explicit question is told, nothing queued
files["helpai.alive"] = '{"t":NOW,"state":"budget"}'
HA.aliveAt = nil
clock = clock + 30
before = #alice.got
HA.onHelpSpeak(alice, 7, "?where is the arena again")
eq(files["helpai.queue"], nil, "budget spent: not queued")
eq(#alice.got, before + 1, "told that Ember rests")

-- startup removes leftovers
files["helpai.queue"], files["helpai.answers"] = "old\n", "old\n"
registered.ChaosHelpAIStartup.onStartup()
eq(files["helpai.queue"], nil, "a leftover queue is removed")
eq(files["helpai.answers"], nil, "a leftover answer file is removed")

-- switched off: the hook does nothing
cfg.enabled = false
Chaos.helpAIConfig.enabled = false
files["helpai.alive"] = '{"t":NOW,"state":"on"}'
HA.aliveAt = nil
clock = clock + 30
HA.onHelpSpeak(alice, 7, "?where is the arena again")
eq(files["helpai.queue"], nil, "enabled = false: nothing queued")

print(string.format("helpai_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end

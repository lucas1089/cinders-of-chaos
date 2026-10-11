-- Run from the server/ folder: luajit tests/mentor_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Mentor system (mentor_core.lua + mentor_config.lua): config and the store fairness rule, the opcode and storages,
-- who may mentor, who may pick a mentor, every refusal of linkCheck (the referral program's household rules), the
-- bonus and the over-level rule (no power-levelling), shared hunting marks with the daily and monthly caps, the
-- milestones (before / unearned / paid / capped) and the graduation, the shop, the mentor list filters, the Party
-- Finder tag, the client view; then mentor.lua against a mocked engine (events, the bonus on experience and damage,
-- the shared minute, the leaderboard hook).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local refCfg = dofile("data/scripts/chaos/referral_config.lua")
dofile("data/scripts/chaos/referral_core.lua")
local cfg = dofile("data/scripts/chaos/mentor_config.lua")
dofile("data/scripts/chaos/mentor_core.lua")
local K = ChaosMentorCore

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = copy(v)
	end
	return c
end

-- ------------------------------------------------------------------ config, fairness, opcode, storages
do
	local cosmetics = dofile("data/scripts/chaos/cosmetics_config.lua")
	local problems = K.validate(cfg, {cosmetics = cosmetics})
	for _, p in ipairs(problems) do
		print("problem: " .. p)
	end
	eq(#problems, 0, "shipped config validates")
	-- the store's fairness rule: titles, cosmetics and supplies only, supplies are potions
	local function broken(change)
		local c = copy(cfg)
		change(c)
		return table.concat(K.validate(c, {cosmetics = cosmetics}), "\n")
	end
	ok(broken(function(c) c.shop[#c.shop + 1] = {key = "orbs", kind = "item", cost = 5, item = 29857, count = 1, weekly = 1,
		name = "Orb", desc = "x"} end):find("not a supply", 1, true), "an orb is refused")
	ok(broken(function(c) c.supplyIds[#c.supplyIds + 1] = 29856 end):find("is an orb", 1, true), "an orb as a supply is refused")
	ok(broken(function(c) c.shop[1].kind = "gear" end):find("not sold for marks", 1, true), "gear is refused")
	ok(broken(function(c) c.shop[1].damage = 5 end):find("is power", 1, true), "a power field is refused")
	ok(broken(function(c) c.shop[4].cosmetic = "no_such" end):find("does not exist", 1, true), "an unknown cosmetic is refused")
	ok(broken(function(c) c.shop[7].weekly = nil end):find("weekly limit", 1, true), "supplies without a weekly limit refused")
	ok(broken(function(c) c.bonus.exp = 0.5 end):find("small one", 1, true), "a big bonus is refused")
	ok(broken(function(c) c.apprentice.maxLevel = 250 end):find("below the graduation", 1, true), "join level below graduation")
	ok(broken(function(c) c.milestones[2].level = 10 end):find("ascending", 1, true), "milestone levels ascending")
	for _, o in ipairs(cfg.shop) do
		ok(o.kind ~= "item" or o.item == 7618 or o.item == 7620, "shop item is a potion: " .. o.key)
	end
	-- the opcode: free in the reference server's list and in Chaos (server/README.md "Opcode collision check")
	eq(ChaosOpcodes.mentor, 194, "opcode 194")
	local seen = {}
	for name, v in pairs(ChaosOpcodes) do
		ok(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
		seen[v] = name
	end
	for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
		ok(v ~= ChaosOpcodes.mentor, "not a base opcode " .. v)
	end
	eq(Chaos.storage.mentor, cfg.storage.seeking, "storage in chaos_constants.lua")
	ok(cfg.storage.seeking >= 7100360 and cfg.storage.seeking <= 7100369, "storage in the reserved block")
	eq(Chaos.tables.mentors, cfg.tables.mentors, "table name")
	-- the mentor achievements feed titles (achievements_data.lua)
	local ach = dofile("data/scripts/chaos/achievements_data.lua")
	local found = {}
	for _, a in ipairs(ach.list) do
		if a.stat == "mentor_graduates" or a.stat == "mentor_fledged" then
			found[a.id] = a
			ok(a.title ~= nil and #a.title <= 24, "mentor achievement has a title: " .. a.id)
		end
	end
	ok(found.mentor_1 and found.mentor_5 and found.mentor_15 and found.mentor_fledged, "mentor tiers and the apprentice's")
end

-- ------------------------------------------------------------------ texts
eq(K.cleanText("  Português <b>EU</b>   evenings ", 24), "Portugus bEU/b evenings", "clean text")
eq(#K.cleanText(string.rep("a", 100), 24), 24, "cut to max")
eq(K.cleanText(nil), "", "nil text")
eq(K.leftText(3 * 86400 + 5), "3 days", "days")
eq(K.leftText(3600), "1 hour", "hour")
eq(K.leftText(90), "1 minute", "minute")
eq(K.leftText(0), "now", "now")
eq(K.say(cfg, "apprenticeLevel"), "Only characters up to level 79 can pick a mentor.", "say with number")
eq(K.say(cfg, "cooldown", 7200), "You can pick another mentor in 2 hours.", "say cooldown")
eq(K.say(cfg, "full"), cfg.messages.full, "say plain")
eq(K.lineOf(cfg, 8, Chaos.classes.baseOf), "warrior", "Juggernaut is the Warrior line")
eq(K.lineOf(cfg, 25, Chaos.classes.baseOf), "templar", "Sentinel is the Templar line")
eq(K.lineOf(cfg, 999, Chaos.classes.baseOf), nil, "unknown vocation")

-- ------------------------------------------------------------------ who may mentor
local function vet(over)
	local t = {accountLevel = 200, onlineHours = 150, accountDays = 90, level = 40}
	for k, v in pairs(over or {}) do
		t[k] = v
	end
	return t
end
eq((K.mentorCheck(vet(), cfg)), true, "a veteran may mentor with a level 40 character")
eq(select(2, K.mentorCheck(vet({staff = true}), cfg)), "staff", "staff")
eq(select(2, K.mentorCheck(vet({banned = true}), cfg)), "banned", "banned")
eq(select(2, K.mentorCheck(vet({registered = true}), cfg)), "registered", "registered already")
eq(select(2, K.mentorCheck(vet({isApprentice = true}), cfg)), "isApprentice", "an apprentice cannot mentor")
eq(select(2, K.mentorCheck(vet({accountLevel = 149}), cfg)), "mentorLevel", "account level")
eq(select(2, K.mentorCheck(vet({onlineHours = 99}), cfg)), "mentorHours", "play time")
eq(select(2, K.mentorCheck(vet({accountDays = 29}), cfg)), "mentorAge", "account age")
eq(select(2, K.mentorCheck(vet({level = 19}), cfg)), "mentorCharLevel", "character level")
do
	local c = copy(cfg)
	c.enabled = false
	eq(select(2, K.mentorCheck(vet(), c)), "disabled", "off")
end

-- ------------------------------------------------------------------ who may pick a mentor
local function newbie(over)
	local t = {accountId = 2, level = 12, accountDays = 3, mentors = 0, cooldownLeft = 0, ips = {"10.0.0.2"}, email = "a@gmail.com"}
	for k, v in pairs(over or {}) do
		t[k] = v
	end
	return t
end
eq((K.apprenticeCheck(newbie(), cfg)), true, "a new character may pick")
eq(select(2, K.apprenticeCheck(newbie({staff = true}), cfg)), "staff", "staff apprentice")
eq(select(2, K.apprenticeCheck(newbie({banned = true}), cfg)), "banned", "banned apprentice")
eq(select(2, K.apprenticeCheck(newbie({isMentor = true}), cfg)), "isMentor", "a mentor cannot pick")
eq(select(2, K.apprenticeCheck(newbie({graduated = true}), cfg)), "graduated", "graduated already")
eq(select(2, K.apprenticeCheck(newbie({hasMentor = true}), cfg)), "hasMentor", "one mentor at a time")
eq(select(2, K.apprenticeCheck(newbie({level = 80}), cfg)), "apprenticeLevel", "too high")
eq((K.apprenticeCheck(newbie({level = 79}), cfg)), true, "level 79 still may")
eq(select(2, K.apprenticeCheck(newbie({accountDays = 61}), cfg)), "apprenticeAge", "old account")
eq(select(2, K.apprenticeCheck(newbie({accountDays = false}), cfg)), "apprenticeAge", "no creation date")
eq(select(2, K.apprenticeCheck(newbie({mentors = 3}), cfg)), "maxMentors", "mentor hopping")
eq(select(2, K.apprenticeCheck(newbie({cooldownLeft = 60}), cfg)), "cooldown", "cooldown after a dismiss")

-- ------------------------------------------------------------------ linking: the household rules, caps, sources
local function mentorSide(over)
	local t = {exists = true, registered = true, accepting = true, accountId = 1, ips = {"10.0.0.1"}, email = "m@gmail.com",
		active = 0, linksThisMonth = 0}
	for k, v in pairs(over or {}) do
		t[k] = v
	end
	return t
end
local function link(me, him, source, extra)
	local info = {apprentice = newbie(me), mentor = mentorSide(him), source = source or "list"}
	for k, v in pairs(extra or {}) do
		info[k] = v
	end
	return K.linkCheck(info, cfg, refCfg)
end
eq((link()), true, "a clean link")
eq(select(2, link({level = 90})), "apprenticeLevel", "the apprentice rules first")
eq(select(2, link(nil, {exists = false})), "noMentor", "mentor gone")
eq(select(2, link(nil, {registered = false})), "noMentor", "retired mentor")
eq(select(2, link({accountId = 1})), "sameAccount", "own account")
eq(select(2, link(nil, {staff = true})), "mentorStaff", "staff mentor")
eq(select(2, link(nil, {banned = true})), "mentorBanned", "banned mentor")
eq(select(2, link(nil, nil, "list", {pairBefore = true})), "pairBefore", "never the same pair twice")
eq(select(2, link(nil, {accepting = false})), "notAccepting", "not accepting: no pick from the list")
eq((link(nil, {accepting = false}, "invite")), true, "an invitation does not need accepting")
eq((link(nil, {accepting = false}, "referral")), true, "nor the referral pick")
eq(select(2, link(nil, {active = 3})), "full", "three apprentices at most")
eq(select(2, link(nil, {active = 3}, "invite")), "full", "full for an invitation too")
eq(select(2, link(nil, {linksThisMonth = 6})), "monthlyLinks", "monthly new apprentices")
eq(select(2, link({ips = {"10.0.0.9", "192.168.1.5"}}, {ips = {"192.168.1.5"}})), "sameIp", "shared IP (the referral's rule)")
eq((link({ips = {"0.0.0.0"}}, {ips = {"0.0.0.0"}})), true, "an empty IP is no match")
eq(select(2, link({email = "a@clan-house.net"}, {email = "b@clan-house.net"})), "sameEmail", "same private e-mail domain")
eq((link({email = "a@gmail.com"}, {email = "b@gmail.com"})), true, "a public e-mail domain is fine")
eq((link({email = "a@GMAIL.com"}, {email = "b@gmail.com"})), true, "public domains ignore case")

-- ------------------------------------------------------------------ the bonus and power-levelling
eq(K.estimateLevel(1000, 1000), 51, "estimate from experience")
eq(K.estimateLevel(0, 0), 2, "estimate floor")
ok(K.overLevelOk(80, 40, 30, cfg), "mentor 80 with an apprentice at 40: fine (40 x 1.5 + 20 = 80)")
ok(not K.overLevelOk(81, 40, 30, cfg), "mentor 81: over")
ok(K.overLevelOk(110, 40, 60, cfg), "harder monsters raise the content (60 x 1.5 + 20 = 110)")
ok(not K.overLevelOk(400, 40, 45, cfg), "a level 400 mentor on level 45 monsters: power-levelling")
local function ctx(over)
	local t = {mentorOnline = true, sameParty = true, distance = 5, sameIpNow = false, mentorLevel = 60, apprenticeLevel = 35,
		monsterLevel = 30}
	for k, v in pairs(over or {}) do
		t[k] = v
	end
	return t
end
eq((K.bonusActive(ctx(), cfg)), true, "hunting together")
eq(select(2, K.bonusActive(ctx({mentorOnline = false}), cfg)), "offline", "mentor offline")
eq(select(2, K.bonusActive(ctx({sameParty = false}), cfg)), "party", "not in the party")
eq(select(2, K.bonusActive(ctx({distance = 31}), cfg)), "range", "too far")
eq(select(2, K.bonusActive(ctx({distance = false}), cfg)), "range", "another floor")
eq(select(2, K.bonusActive(ctx({sameIpNow = true}), cfg)), "sameIp", "same connection now")
eq(select(2, K.bonusActive(ctx({mentorLevel = 500}), cfg)), "overLevel", "over-levelled mentor")
eq((K.bonusActive(ctx({monsterLevel = nil}), cfg)), true, "no monster: the apprentice's level")
for reason in pairs({offline = 1, party = 1, range = 1, sameIp = 1, overLevel = 1}) do
	ok(K.BONUS_TEXT[reason] ~= nil, "bonus text " .. reason)
end

-- ------------------------------------------------------------------ marks: hunting, daily and monthly caps
do
	local day1 = os.time({year = 2026, month = 10, day = 10, hour = 12})
	local m = {}
	local got = 0
	for i = 1, 29 do
		got = got + K.huntMinute(m, day1 + i * 60, cfg, 0)
	end
	eq(got, 0, "29 minutes: nothing yet")
	got = got + K.huntMinute(m, day1 + 30 * 60, cfg, 0)
	eq(got, 1, "30 minutes: one mark")
	for i = 31, 300 do
		got = got + K.huntMinute(m, day1 + i * 60, cfg, 0)
	end
	eq(got, 4, "five hours: the daily cap of 4")
	eq(m.dayMarks, 4, "day marks")
	eq(m.dayMinutes, 300, "day minutes")
	local day2 = day1 + 86400
	local g2 = 0
	for i = 1, 30 do
		g2 = g2 + K.huntMinute(m, day2 + i * 60, cfg, 0)
	end
	eq(g2, 1, "a new day starts over")
	eq(m.dayMinutes, 30, "minutes reset")
	local full = {}
	for i = 1, 30 do
		g2 = K.huntMinute(full, day1 + i * 60, cfg, cfg.marks.monthlyCap)
	end
	eq(g2, 0, "the monthly cap stops hunting marks")
	eq(full.dayMarks, 0, "a capped mark is not counted")
	eq(select(1, K.pay(10, 295, cfg)), 5, "the rest of the month only")
	eq(select(2, K.pay(10, 300, cfg)), "capped", "capped")
	eq(select(2, K.pay(10, 0, cfg)), "paid", "paid")
	eq((K.pay(0, 0, cfg)), 0, "nothing to pay")
end

-- ------------------------------------------------------------------ milestones and graduation
do
	local r = K.reachedNow({level = 52, dungeon = true}, cfg)
	ok(r.l25 and r.l50 and not r.l100 and r.dungeon and not r.rift, "reached at level 52 with a dungeon")
	local due = K.due({level = 52, dungeon = true}, {l25 = {state = "before"}}, cfg)
	eq(#due, 2, "l50 and the dungeon are due, l25 was before the link")
	eq(due[1].key, "l50", "in config order")
	eq(K.milestone(cfg, "rift").event, "rift", "milestone lookup")
	local m = K.milestone(cfg, "l50")
	eq((K.decideMilestone(m, {shared = 10, monthMarks = 0}, cfg)), "unearned", "not enough time together")
	local st, marks = K.decideMilestone(m, {shared = 30, monthMarks = 0}, cfg)
	eq(st, "paid", "paid") eq(marks, 10, "10 marks")
	st, marks = K.decideMilestone(m, {shared = 30, monthMarks = 296}, cfg)
	eq(st, "paid", "partly paid") eq(marks, 4, "up to the cap")
	st, marks = K.decideMilestone(m, {shared = 30, monthMarks = 300}, cfg)
	eq(st, "capped", "capped") eq(marks, 0, "no marks")
	local earned, gm = K.decideGraduation({shared = 119, monthMarks = 0}, cfg)
	eq(earned, false, "graduation needs 120 minutes") eq(gm, 0, "no marks")
	earned, gm = K.decideGraduation({shared = 120, monthMarks = 0}, cfg)
	eq(earned, true, "graduation earned") eq(gm, 50, "50 marks")
	earned, gm = K.decideGraduation({shared = 500, monthMarks = 300}, cfg)
	eq(earned, true, "the graduation still counts at the cap") eq(gm, 0, "but no marks")
	eq(K.graduationText(cfg), "100 health potions, 100 mana potions", "graduation gift text")
	local rows = K.milestoneRows({l25 = {state = "paid", marks = 5}, graduation = {state = "unearned", marks = 0}}, cfg)
	eq(#rows, #cfg.milestones + 1, "every milestone and the graduation")
	eq(rows[1].state, "paid", "paid row") eq(rows[2].state, "open", "open row")
	eq(rows[#rows].key, "graduation", "graduation last") eq(rows[#rows].state, "unearned", "graduation state")
end

-- ------------------------------------------------------------------ shop
do
	local title = K.offer(cfg, "title_lantern")
	eq((K.shopCheck(title, {marks = 40}, cfg)), true, "can buy a title")
	eq(select(2, K.shopCheck(title, {marks = 39}, cfg)), "notEnough", "not enough marks")
	eq(select(2, K.shopCheck(title, {marks = 999, owned = true}, cfg)), "owned", "a title once")
	eq(select(2, K.shopCheck(nil, {marks = 999}, cfg)), "unknownOffer", "unknown offer")
	local pot = K.offer(cfg, "sup_health")
	eq((K.shopCheck(pot, {marks = 6, weeklyUsed = 2}, cfg)), true, "third potion pack this week")
	eq(select(2, K.shopCheck(pot, {marks = 60, weeklyUsed = 3}, cfg)), "weekly", "weekly limit")
	eq((K.shopCheck(pot, {marks = 60, owned = true}, cfg)), true, "supplies are never 'owned'")
	local cos = K.offer(cfg, "cos_chat_cinder")
	eq(select(2, K.shopCheck(cos, {marks = 999, cosmetics = false}, cfg)), "cosmeticOff", "cosmetics not loaded")
	eq(select(2, K.shopCheck(cos, {marks = 999, owned = true}, cfg)), "owned", "cosmetic owned by the account")
	local t = K.titles({title_lantern = 100, sup_health = 50}, cfg)
	eq(#t, 1, "only titles are titles")
	eq(t[1].key, "mentor:title_lantern", "title key") eq(t[1].text, "Lanternbearer", "title text") eq(t[1].at, 100, "title time")
	eq(#K.titles(nil, cfg), 0, "no titles")
end

-- ------------------------------------------------------------------ the mentor list
do
	local now = os.time({year = 2026, month = 10, day = 10, hour = 12})
	local rows = {
		{guid = 1, accountId = 10, name = "Brannoc", line = "warrior", lang = "English, EU evenings", online = true, accepting = true,
			active = 1, graduates = 2, lastLogin = now},
		{guid = 2, accountId = 11, name = "Seris", line = "mystic", lang = "Portuguese (BR)", online = false, accepting = true,
			active = 0, graduates = 9, lastLogin = now - 2 * 86400},
		{guid = 3, accountId = 12, name = "Kael", line = "ranger", lang = "English", online = false, accepting = true, active = 0,
			graduates = 1, lastLogin = now - 30 * 86400},
		{guid = 4, accountId = 13, name = "Full", line = "warrior", lang = "English", online = true, accepting = true, active = 3,
			graduates = 50, lastLogin = now},
		{guid = 5, accountId = 14, name = "Closed", line = "warrior", lang = "English", online = true, accepting = false, active = 0,
			graduates = 50, lastLogin = now},
		{guid = 6, accountId = 99, name = "Mine", line = "warrior", lang = "English", online = true, accepting = true, active = 0,
			graduates = 50, lastLogin = now}
	}
	local v = {accountId = 99, now = now}
	local out = K.filterMentors(rows, {}, cfg, v)
	eq(#out, 3, "full, closed and the own account are left out")
	eq(out[1].name, "Brannoc", "online first")
	eq(out[2].name, "Seris", "then the most graduates")
	eq(#K.filterMentors(rows, {line = "warrior"}, cfg, v), 1, "class filter")
	eq(#K.filterMentors(rows, {lang = "english"}, cfg, v), 2, "language filter ignores case")
	eq(#K.filterMentors(rows, {lang = "br"}, cfg, v), 1, "language part")
	eq(#K.filterMentors(rows, {online = "now"}, cfg, v), 1, "online now")
	eq(#K.filterMentors(rows, {online = "week"}, cfg, v), 2, "seen this week")
	local many = {}
	for i = 1, 60 do
		many[i] = {guid = i, accountId = i, name = "M" .. i, line = "warrior", lang = "", accepting = true, active = 0, graduates = 0}
	end
	eq(#K.filterMentors(many, {}, cfg, {accountId = 0, now = now}), cfg.listMax, "at most listMax")
	eq(K.tagOf({mentor = true}), "mentor", "mentor tag")
	eq(K.tagOf({seeking = true}), "seeking", "seeking tag")
	eq(K.tagOf({}), nil, "no tag")
end

-- ------------------------------------------------------------------ the client view
do
	local now = os.time({year = 2026, month = 10, day = 10, hour = 12})
	local v = K.view({me = {name = "Ash", level = 30, voc = "Warrior"}, mentorOk = false, mentorReason = "mentorLevel",
		apprenticeOk = true, seeking = true,
		apprentice = {guid = 7, name = "Brannoc", level = 60, voc = "Juggernaut", online = true, linkedAt = now - 3600, shared = 45,
			source = "invite", states = {l25 = {state = "before", marks = 0}}, bonus = false, bonusReason = "overLevel"},
		invites = {{guid = 8, name = "Seris", level = 70, voc = "Illusionist", lang = "EN", at = now - 120}},
		owned = {title_lantern = true}, weekly = {sup_health = 1}, top = {{name = "Seris", graduates = 9}}}, cfg, now)
	eq(v.enabled, true, "enabled")
	eq(v.canMentor, false, "cannot mentor") eq(v.mentorNote, "To mentor, a character of your account must have reached level 150.", "why")
	eq(v.canPick, true, "may pick")
	eq(v.rules.exp, 10, "rules: +10% exp") eq(v.rules.dmg, 5, "rules: 5% damage") eq(v.rules.gradLevel, 200, "graduation level")
	eq(v.apprentice.name, "Brannoc", "apprentice view: mentor name")
	eq(v.apprentice.milestones[1].state, "before", "before the link")
	eq(v.apprentice.bonusText, K.BONUS_TEXT.overLevel, "why no bonus")
	eq(v.invites[1].left, cfg.inviteMinutes * 60 - 120, "invitation time left")
	eq(#v.lines, #cfg.lines, "class lines for the filter")
	local shopOwned, weekly
	for _, s in ipairs(v.shop) do
		if s.key == "title_lantern" then shopOwned = s.owned end
		if s.key == "sup_health" then weekly = s.weeklyLeft end
	end
	eq(shopOwned, true, "owned title") eq(weekly, 2, "weekly left")
	eq(v.top[1].rank, 1, "top rank") eq(v.top[1].graduates, 9, "top graduates")
	local mv = K.view({mentorOk = true, mentor = {marks = 30, earned = 80, graduates = 1, dayKey = K.dayKey(now), dayMinutes = 75,
		dayMarks = 2, apprentices = {{guid = 9, name = "Kael", level = 33, states = {}}}}}, cfg, now)
	eq(mv.mentor.marks, 30, "marks") eq(mv.mentor.dayMarks, 2, "today's marks")
	eq(#mv.mentor.apprentices, 1, "one apprentice") eq(#mv.mentor.apprentices[1].milestones, #cfg.milestones + 1, "its milestones")
	local stale = K.view({mentor = {dayKey = 20200101, dayMarks = 4, dayMinutes = 200}}, cfg, now)
	eq(stale.mentor.dayMarks, 0, "yesterday's marks are not today's")
	local cool = K.view({apprenticeOk = false, apprenticeReason = "cooldown", cooldownLeft = 5 * 3600}, cfg, now)
	eq(cool.pickNote, "You can pick another mentor in 5 hours.", "cooldown note")
end

-- ------------------------------------------------------------------ mentor.lua against a mocked engine
do
	local registry, globals, callbacks, talks = {}, {}, {}, {}
	function CreatureEvent(name)
		local e = {name = name, type = function() end, register = function() end}
		registry[name] = e
		return e
	end
	function GlobalEvent(name)
		local e = {name = name, interval = function() end, register = function() end}
		globals[name] = e
		return e
	end
	EventCallback = setmetatable({}, {__newindex = function(t, k, v) callbacks[k] = v end, __index = {register = function() end}})
	function TalkAction(words)
		local e = {separator = function() end, register = function() end}
		talks[words] = e
		return e
	end
	function addEvent() end
	local queries = {}
	db = {query = function(s) queries[#queries + 1] = s return true end, asyncQuery = function(s) queries[#queries + 1] = s end,
		escapeString = function(s) return "'" .. tostring(s) .. "'" end, storeQuery = function() return false end}
	result = {free = function() end}
	json = {encode = function(t) return t end, decode = function() return nil end}
	local players = {}
	local P = {}
	P.__index = P
	local function mk(guid, name, level, pos, ip)
		local p = setmetatable({guid = guid, cid = 1000 + guid, name = name, level = level, pos = pos, ip = ip or guid, msgs = {},
			events = {}, storage = {}}, P)
		players[p.cid] = p
		return p
	end
	function P:getGuid() return self.guid end
	function P:getId() return self.cid end
	function P:getName() return self.name end
	function P:getLevel() return self.level end
	function P:getPosition() return self.pos end
	function P:getIp() return self.ip end
	function P:getParty() return self.party end
	function P:getPlayer() return self end
	function P:isMonster() return false end
	function P:getAccountId() return self.guid * 10 end
	function P:getStorageValue(k) return self.storage[k] or -1 end
	function P:setStorageValue(k, v) self.storage[k] = v end
	function P:registerEvent(e) self.events[e] = true end
	function P:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function Player(cid) return players[cid] end
	local monster = {getName = function() return "Rat" end, isMonster = function() return true end,
		getType = function() return nil end}
	local party = {getLeader = function(self) return self.leader end}

	dofile("data/scripts/chaos/mentor.lua")
	local M = ChaosMentor
	ok(registry.ChaosMentorExtended and registry.ChaosMentorHealth and registry.ChaosMentorMana and registry.ChaosMentorAdvance,
		"events registered")
	ok(registry.ChaosMentorLogin and registry.ChaosMentorLogout, "login and logout")
	ok(globals.ChaosMentorTick and globals.ChaosMentorStartup, "tick and startup")
	ok(callbacks.onGainExperience ~= nil, "experience callback")
	ok(talks["/mentor"] ~= nil, "staff command")

	local mentor = mk(1, "Brannoc", 26, {x = 100, y = 100, z = 7}, 111)
	local appr = mk(2, "Ash", 10, {x = 103, y = 100, z = 7}, 222)
	M.online[1], M.online[2] = mentor.cid, appr.cid
	local link = {id = 5, mentor_id = 1, apprentice_id = 2, shared_minutes = 0, lastBonusAt = 0}
	M.links[2] = link
	-- no party: no bonus
	eq(callbacks.onGainExperience(appr, monster, 100, 100), 100, "no party, no bonus")
	local pt = setmetatable({leader = mentor}, {__index = party})
	mentor.party, appr.party = pt, pt
	-- the Rat is level 4 in bounty_pool.lua: content = max(10, 4) x 1.5 + 20 = 35 >= 26
	eq(callbacks.onGainExperience(appr, monster, 100, 100), 110, "+10% experience while hunting together")
	ok(link.lastBonusAt > 0, "the minute is marked")
	COMBAT_HEALING = 1024
	local p1, _, s1 = registry.ChaosMentorHealth.onHealthChange(appr, monster, -100, 1, -20, 2, 0)
	eq(p1, -95, "5% less damage") eq(s1, -19, "secondary too")
	local h = registry.ChaosMentorHealth.onHealthChange(appr, mentor, -100, 1, 0, 2, 0)
	eq(h, -100, "a player hit is not reduced")
	eq(callbacks.onGainExperience(mentor, monster, 100, 100), 100, "the mentor gets no bonus")
	mentor.level = 400
	eq(callbacks.onGainExperience(appr, monster, 100, 100), 100, "an over-levelled mentor: no bonus")
	mentor.level = 26
	appr.ip = mentor.ip
	eq(callbacks.onGainExperience(appr, monster, 100, 100), 100, "same connection: no bonus")
	appr.ip = 222
	appr.pos = {x = 100, y = 100, z = 8}
	eq(callbacks.onGainExperience(appr, monster, 100, 100), 100, "another floor: no bonus")
	appr.pos = {x = 103, y = 100, z = 7}
	-- the Party Finder tag
	M.mentors[1] = {accepting = 1, apprentices = {2}}
	eq(M.tagOf(mentor), "mentor", "mentor tag")
	M.mentors[1].apprentices = {2, 3, 4}
	eq(M.tagOf(mentor), nil, "a full mentor has no tag")
	local seeker = mk(3, "Kael", 15, {x = 1, y = 1, z = 7})
	seeker:setStorageValue(cfg.storage.seeking, 1)
	eq(M.tagOf(seeker), "seeking", "looking for a mentor")
	eq(M.tagOf(appr), nil, "an apprentice with a mentor does not seek")
	-- the leaderboard hook: a rift record of the apprentice checks its milestones with the event
	local seen
	local real = M.checkApprentice
	M.checkApprentice = function(p, extra) seen = {p, extra} end
	M.onRecord("rift", appr, 3)
	ok(seen and seen[1] == appr and seen[2].rift, "rift record -> first rift milestone")
	seen = nil
	M.onRecord("arena1v1", appr, 3)
	eq(seen, nil, "other boards do nothing")
	M.onRecord("bounty", {guid = 2, name = "Ash"}, 1)
	ok(seen and seen[2].bounty, "bounty record by guid table")
	M.checkApprentice = real
	-- logout forgets the character
	registry.ChaosMentorLogout.onLogout(appr)
	eq(M.links[2], nil, "logout clears the link cache")
	eq(M.online[2], nil, "logout clears online")
end

print(string.format("mentor_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

-- Run from the server/ folder: luajit tests/referral_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Referral program rules (referral_core.lua + referral_config.lua): codes, IP and e-mail facts, the entry window,
-- every refusal of linkCheck, milestones, the reward decision (pay / wait / void), titles and the client view.
local cfg = dofile("data/scripts/chaos/referral_config.lua")
dofile("data/scripts/chaos/referral_core.lua")
local R = ChaosReferralCore

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

-- ------------------------------------------------------------------ config sanity
do
	ok(cfg.enabled ~= nil and cfg.entryDays > 0, "enabled flag and entry window")
	ok(#cfg.code.alphabet >= 20 and not cfg.code.alphabet:find("[01OIL]"), "alphabet without look-alikes")
	local keys, titles = {}, {}
	local last = 0
	for _, m in ipairs(cfg.milestones) do
		ok(not keys[m.key], "milestone key unique " .. m.key)
		keys[m.key] = true
		ok(m.level > last, "milestones ordered by level")
		last = m.level
		ok((m.coins or 0) <= 100, "a few coins only (" .. m.key .. ")")
		if m.title then
			ok(#m.title.text <= 24 and m.title.key:find("^referral:") ~= nil, "milestone title fits the name plate")
			ok(not titles[m.title.key], "title key unique")
			titles[m.title.key] = true
		end
		for k in pairs(m) do
			ok(k == "key" or k == "level" or k == "coins" or k == "title", "milestone gives no power (" .. tostring(k) .. ")")
		end
	end
	eq(cfg.milestones[1].level, 50, "first milestone level 50")
	eq(cfg.milestones[2].level, 250, "second milestone level 250")
	for _, it in ipairs(cfg.starterGift.items) do
		ok(it.id == 7618 or it.id == 7620, "gift is plain potions only")
	end
	ok(#cfg.starterGift.title.text <= 24, "gift title fits")
	for _, key in ipairs({"badCode", "unknownCode", "ownCode", "alreadyLinked", "tooOld", "noCreation", "staff", "referrerStaff",
			"referrerBanned", "sameIp", "sameEmail", "cycle", "monthlyLinks", "noCodeYet", "disabled"}) do
		ok(type(cfg.messages[key]) == "string", "message " .. key)
	end
	for _, t in pairs(cfg.tables) do
		ok(t:find("^chaos_referral") ~= nil, "chaos_referral* table " .. t)
	end
end

-- ------------------------------------------------------------------ codes
do
	local seq = {1, 2, 3, 4, 5, 6, 7, 8}
	local i = 0
	local code = R.make(function(n) i = i + 1 return seq[i] end, cfg)
	eq(code, "ABCDEFGH", "made from the alphabet")
	eq(R.format(code, cfg), "ABCD-EFGH", "shown in groups")
	eq(R.normalize("abcd-efgh", cfg), "ABCDEFGH", "lower case and dash")
	eq(R.normalize(" ABCD EFGH ", cfg), "ABCDEFGH", "spaces")
	eq(R.normalize("ABCDEFG", cfg), nil, "too short")
	eq(R.normalize("ABCDEFGO", cfg), nil, "letter outside the alphabet")
	eq(R.normalize(nil, cfg), nil, "nil")
	eq(R.normalize(string.rep("A", 50), cfg), nil, "far too long")
	local rnd = 0
	local seen = {}
	for _ = 1, 200 do
		local c = R.make(function(n) rnd = (rnd * 1103515245 + 12345) % 2147483648 return rnd % n + 1 end, cfg)
		ok(R.normalize(c, cfg) == c, "random code is valid")
		seen[c] = true
	end
end

-- ------------------------------------------------------------------ facts
do
	eq(R.ipString(16777343), "127.0.0.1", "engine IP (network order)")
	eq(R.ipString(0), nil, "no IP")
	eq(R.ipFromLong(2130706433), "127.0.0.1", "PHP ip2long")
	eq(R.ipString(3232235777 % 4294967296), "1.1.168.192", "byte order of the engine")
	eq(R.emailDomain("Foo.Bar@Example.COM"), "example.com", "domain lower case")
	eq(R.emailDomain("nobody"), nil, "no @")
	eq(R.emailDomain(""), nil, "empty")
	eq(R.emailDomain("a@localhost"), nil, "no dot")
	eq(R.monthKey(os.time({year = 2026, month = 10, day = 10, hour = 12})), 202610, "month key")
	ok(R.shareIp({"1.2.3.4", "5.6.7.8"}, {"9.9.9.9", "5.6.7.8"}), "shared IP")
	ok(not R.shareIp({"1.2.3.4"}, {"4.3.2.1"}), "different IPs")
	ok(not R.shareIp({"0.0.0.0"}, {"0.0.0.0"}), "no address never matches")
	-- IPv6 counts by its /64 (one home connection), IPv4 exactly
	eq(R.netKey("2001:DB8:aa:1::5"), "2001:db8:aa:1", "IPv6 /64")
	eq(R.netKey("::ffff:10.1.2.3"), "10.1.2.3", "IPv4-mapped")
	ok(R.shareIp({"2001:db8:aa:1::5"}, {"2001:db8:aa:1:9:9:9:9"}), "same /64 shared")
	ok(not R.shareIp({"2001:db8:aa:1::5"}, {"2001:db8:aa:2::5"}), "another /64")
	ok(R.sharePayer({"h1", "h2"}, {"h3", "h2"}), "shared payer")
	ok(not R.sharePayer({"h1"}, {""}), "empty payer never matches")
end

-- ------------------------------------------------------------------ entry window and code holders
local NOW = os.time({year = 2026, month = 10, day = 10, hour = 12})
do
	eq(R.entryLeft(0, NOW, cfg), nil, "no creation date")
	ok(R.entryLeft(NOW - 86400, NOW, cfg) == 6 * 86400, "six days left")
	ok(R.entryLeft(NOW - 8 * 86400, NOW, cfg) < 0, "too late")
	local okc, why = R.codeHolder({staff = false, maxLevel = 5}, cfg)
	eq(okc, nil, "low level: no code") eq(why, "noCodeYet", "reason")
	okc, why = R.codeHolder({staff = true, maxLevel = 500}, cfg)
	eq(why, "referrerStaff", "staff have no code")
	ok(R.codeHolder({staff = false, maxLevel = cfg.minReferrerLevel}, cfg) == true, "level reached: code")
end

-- ------------------------------------------------------------------ linkCheck
local function info(over)
	local i = {
		now = NOW,
		referee = {accountId = 2, created = NOW - 3600, staff = false, link = nil, ips = {"10.0.0.2"}, email = "new@corp.example"},
		referrer = {accountId = 1, staff = false, banned = false, ips = {"10.0.0.1"}, email = "old@gmail.com", linksThisMonth = 0}
	}
	for k, v in pairs(over or {}) do
		if k == "referee" or k == "referrer" then
			for kk, vv in pairs(v) do
				i[k][kk] = vv
			end
		else
			i[k] = v
		end
	end
	return i
end
local function reason(i, c)
	local okc, why = R.linkCheck(i, c or cfg)
	return okc and "ok" or why
end
do
	eq(reason(info()), "ok", "a clean link")
	local i = info()
	i.referrer = nil
	eq(reason(i), "unknownCode", "no such code")
	eq(reason(info({referrer = {accountId = 2}})), "ownCode", "own code")
	eq(reason(info({referee = {link = {status = "active"}}})), "alreadyLinked", "one referrer per account")
	eq(reason(info({referee = {link = {status = "pending"}}})), "alreadyLinked", "pending counts too")
	eq(reason(info({referee = {link = {status = "rejected"}}})), "ok", "a rejected link may be replaced")
	eq(reason(info({referee = {staff = true}})), "staff", "staff referee")
	eq(reason(info({referee = {created = 0}})), "noCreation", "no creation date")
	eq(reason(info({referee = {created = NOW - 8 * 86400}})), "tooOld", "older than the window")
	eq(reason(info({referee = {created = NOW - 8 * 86400}, ignoreWindow = true})), "ok", "website: at creation")
	eq(reason(info({referrer = {staff = true}})), "referrerStaff", "staff referrer")
	eq(reason(info({referrer = {banned = true}})), "referrerBanned", "banned referrer")
	eq(reason(info({referrer = {referredBy = 2}})), "cycle", "no referring back")
	eq(reason(info({referrer = {ips = {"10.0.0.9", "10.0.0.2"}}})), "sameIp", "same IP")
	local noIp = {}
	for k, v in pairs(cfg) do noIp[k] = v end
	noIp.antiAbuse = {}
	for k, v in pairs(cfg.antiAbuse) do noIp.antiAbuse[k] = v end
	noIp.antiAbuse.sameIp = false
	eq(reason(info({referrer = {ips = {"10.0.0.2"}}}), noIp), "ok", "IP check off")
	eq(reason(info({referrer = {email = "boss@corp.example"}})), "sameEmail", "same private domain")
	eq(reason(info({referee = {email = "a@gmail.com"}, referrer = {email = "b@GMAIL.com"}})), "ok", "same public domain is fine")
	noIp.antiAbuse.sameEmailDomain = false
	eq(reason(info({referrer = {email = "boss@corp.example"}}), noIp), "ok", "e-mail check off")
	eq(reason(info({referee = {email = ""}, referrer = {email = ""}})), "ok", "no e-mails")
	eq(reason(info({referrer = {linksThisMonth = cfg.antiAbuse.monthlyLinks}})), "monthlyLinks", "monthly link cap")
	eq(reason(info({referrer = {linksThisMonth = cfg.antiAbuse.monthlyLinks - 1}})), "ok", "under the cap")
	local off = {}
	for k, v in pairs(cfg) do off[k] = v end
	off.enabled = false
	eq(reason(info(), off), "disabled", "program off")
end

-- ------------------------------------------------------------------ milestones and rewards
do
	eq(#R.due(49, {}, cfg), 0, "level 49: nothing")
	eq(#R.due(50, {}, cfg), 1, "level 50: one")
	eq(R.due(50, {}, cfg)[1].key, "l50", "the level 50 one")
	eq(#R.due(300, {}, cfg), 2, "both at once (late login)")
	eq(#R.due(300, {l50 = true}, cfg), 1, "the one not reached yet")
	eq(#R.due(300, {l50 = true, l250 = true}, cfg), 0, "all done")
	eq(R.milestone(cfg, "l250").level, 250, "lookup")
	eq(R.decide({}, cfg), "pay", "pay")
	eq(R.decide({referredBanned = true}, cfg), "void", "banned friend: void")
	eq(R.decide({referredBanned = true, referrerBanned = true}, cfg), "void", "void wins")
	eq(R.decide({referrerBanned = true}, cfg), "wait", "banned referrer: wait")
	eq(R.decide({paidThisMonth = cfg.antiAbuse.monthlyRewards}, cfg), "wait", "monthly reward cap: wait")
	eq(R.decide({paidThisMonth = cfg.antiAbuse.monthlyRewards - 1}, cfg), "pay", "under the cap")
	-- owner rules 2026-10-13: the friend's account at least 7 days old (waits), one person on both sides (void)
	eq(cfg.antiAbuse.minReferredAccountDays, 7, "7 days")
	eq(R.decide({referredAgeDays = 3}, cfg), "wait", "young account: wait")
	eq(R.decide({referredAgeDays = 7}, cfg), "pay", "7 days old: pay")
	eq(R.decide({referredAgeDays = nil}, cfg), "pay", "unknown age is not checked here (linkCheck needs a creation date)")
	eq(R.decide({sameIp = true}, cfg), "void", "shared connection by payout: void")
	eq(R.decide({samePayer = true}, cfg), "void", "shared payer: void")
	eq(R.decide({samePayer = true, referrerBanned = true}, cfg), "void", "void before wait")
	-- the main reward at level 250 (decided 2026-10-14) is a cosmetic (a title) and the tiers at 3, 5, 10 friends
	ok(R.milestone(cfg, cfg.qualify).title ~= nil, "the qualifying milestone gives a title")
	eq(#cfg.tiers, 3, "three tiers")
	eq(cfg.tiers[1].count .. "," .. cfg.tiers[2].count .. "," .. cfg.tiers[3].count, "3,5,10", "at 3, 5 and 10 friends")
	for _, t in ipairs(cfg.tiers) do
		ok(t.title and t.title.text ~= "", "tier " .. t.key .. " gives a title")
		ok((t.coins or 0) <= 200, "a few coins only (" .. t.key .. ")")
		for k in pairs(t) do
			ok(k == "key" or k == "count" or k == "coins" or k == "title", "tier gives no power (" .. tostring(k) .. ")")
		end
	end
	eq(#R.tiersDue(2, {}, cfg), 0, "two friends: no tier")
	eq(#R.tiersDue(5, {}, cfg), 2, "five friends: 3 and 5")
	eq(#R.tiersDue(11, {t3 = true, t5 = true}, cfg), 1, "the 10 tier left")
	eq(R.tier(cfg, "t10").count, 10, "tier lookup")
	eq(R.rewardText({title = {text = "Torchbearer"}, coins = 25}), "the title Torchbearer and 25 Chaos Coins", "reward text")
	eq(R.rewardText({coins = 5}), "5 Chaos Coins", "coins only")
	eq(R.giftText(cfg), "50 health potions, 50 mana potions", "gift text")
end

-- ------------------------------------------------------------------ titles
do
	eq(#R.titles({gift = false, paid = {}}, cfg), 0, "nothing earned")
	local t = R.titles({gift = true, giftAt = 5, paid = {l50 = 7}}, cfg)
	eq(#t, 2, "gift and one milestone")
	eq(t[1].text, cfg.starterGift.title.text, "gift title") eq(t[1].at, 5, "gift time")
	eq(t[2].text, cfg.milestones[1].title.text, "milestone title") eq(t[2].at, 7, "paid time")
	t = R.titles({gift = false, paid = {}, tiers = {t3 = 9}}, cfg)
	eq(#t, 1, "a tier title") eq(t[1].text, cfg.tiers[1].title.text, "tier 3 title") eq(t[1].at, 9, "tier time")
end

-- ------------------------------------------------------------------ the client view
do
	local v = R.view({code = "ABCDEFGH", created = NOW - 3600, linksThisMonth = 2, paidThisMonth = 1, coinsEarned = 25,
		friends = {{name = "Ash", level = 77, linkedAt = NOW, status = "active", rewards = {l50 = {state = "paid"}}}}}, cfg, NOW)
	eq(v.code, "ABCD-EFGH", "code shown") eq(v.codeNote, "", "no note")
	eq(v.canEnter, true, "new account may enter a code") ok(v.enterLeft > 0, "time left")
	eq(#v.friends, 1, "one friend") eq(v.friends[1].steps[1].state, "paid", "50 paid") eq(v.friends[1].steps[2].state, "open", "250 open")
	eq(#v.milestones, 2, "milestones listed") eq(v.linksThisMonth, 2, "links") eq(v.coinsEarned, 25, "coins")
	eq(#v.tiers, 3, "tiers listed") eq(v.tiers[1].reached, false, "tier 3 not reached") eq(v.qualifyLevel, 250, "qualify level")
	v = R.view({holderReason = "noCodeYet", created = NOW - 30 * 86400}, cfg, NOW)
	eq(v.code, "", "no code yet") ok(v.codeNote:find(tostring(cfg.minReferrerLevel), 1, true) ~= nil, "says the level")
	eq(v.canEnter, false, "old account") ok(v.enterNote:find("7", 1, true) ~= nil, "says the window")
	v = R.view({code = "ABCDEFGH", created = NOW, link = {status = "active", referrerName = "Old Friend", gift = true}}, cfg, NOW)
	eq(v.canEnter, false, "already linked") eq(v.referrer, "Old Friend", "referrer shown") eq(v.giftGiven, true, "gift given")
	v = R.view({created = NOW, link = {status = "rejected", reason = "same connection"}}, cfg, NOW)
	eq(v.canEnter, true, "rejected: may try another code") eq(v.rejected, "same connection", "why it was rejected")
	v = R.view({created = NOW, staff = true}, cfg, NOW)
	eq(v.canEnter, false, "staff cannot enter") eq(v.enterNote, cfg.messages.staff, "staff note")
end

print(string.format("referral tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end

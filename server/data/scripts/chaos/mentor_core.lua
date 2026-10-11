-- Mentor system: pure logic (no engine calls), shared by mentor.lua and server/tests/mentor_test.lua.
--   texts       cleanText(text, max) -> printable text; say(cfg, reason) -> the message of a refusal; leftText(seconds)
--   classes     lineOf(cfg, vocId, baseOf) -> line key of cfg.lines or nil
--   time        dayKey(t), monthKey(t)
--   rules       mentorCheck(info, cfg), apprenticeCheck(info, cfg), linkCheck(info, cfg, refCfg) -> true or nil, reason
--               (refCfg = referral_config.lua: its antiAbuse.publicDomains; the IP and e-mail rules are the referral's,
--               ChaosReferralCore.shareIp / emailDomain)
--   bonus       estimateLevel(exp, health); overLevelOk(mentorLv, apprenticeLv, monsterLv, cfg);
--               bonusActive(ctx, cfg) -> true or false, reason
--   marks       huntMinute(m, now, cfg, monthMarks) -> marks earned this minute (0 / 1), m = {dayKey, dayMinutes, dayMarks};
--               pay(marks, monthMarks, cfg) -> paid, state ("paid" | "capped")
--   milestones  reachedNow(facts, cfg) -> {[key] = true}; due(facts, states, cfg) -> milestones to record now;
--               decideMilestone(m, ctx, cfg) -> state, marks; decideGraduation(ctx, cfg) -> earned, marks
--   shop        offer(cfg, key); shopCheck(offer, ctx, cfg) -> true or nil, reason; titles(owned, cfg)
--   lists       filterMentors(rows, f, cfg, viewer) -> rows to show; tagOf(info) -> "mentor" | "seeking" | nil
--   view        milestoneRows(states, cfg); view(state, cfg, now) -> what the client window shows
--   checks      validate(cfg, opts) -> problems (the store's fairness rule among them)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosMentorCore = ChaosMentorCore or {}
local K = ChaosMentorCore

local floor = math.floor

local function num(v)
	return tonumber(v) or 0
end

-- ---------------------------------------------------------------- texts
function K.cleanText(text, max)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("[^%w%s%-%.,:/+'!?()&]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if max and #text > max then
		text = text:sub(1, max):gsub("%s+$", "")
	end
	return text
end

function K.leftText(seconds)
	seconds = floor(num(seconds))
	if seconds <= 0 then
		return "now"
	end
	if seconds >= 86400 then
		local d = floor(seconds / 86400)
		return d .. (d == 1 and " day" or " days")
	end
	if seconds >= 3600 then
		local h = floor(seconds / 3600)
		return h .. (h == 1 and " hour" or " hours")
	end
	local m = math.max(1, floor(seconds / 60))
	return m .. (m == 1 and " minute" or " minutes")
end

-- the message of a refusal reason, with its number filled in
function K.say(cfg, reason, extra)
	local msg = cfg.messages[reason] or tostring(reason)
	if not msg:find("%", 1, true) then
		return msg
	end
	local arg = ({
		mentorLevel = cfg.mentor.minAccountLevel, mentorHours = cfg.mentor.minOnlineHours,
		mentorAge = cfg.mentor.minAccountDays, mentorCharLevel = cfg.mentor.minCharacterLevel,
		apprenticeLevel = cfg.apprentice.maxLevel, apprenticeAge = cfg.apprentice.maxAccountDays,
		maxMentors = cfg.apprentice.maxMentors, cooldown = K.leftText(extra)
	})[reason]
	if arg == nil then
		return msg
	end
	return string.format(msg, arg)
end

-- ---------------------------------------------------------------- classes and time
function K.lineOf(cfg, vocId, baseOf)
	local base = baseOf and baseOf[num(vocId)] or num(vocId)
	for _, l in ipairs(cfg.lines) do
		if l.base == base then
			return l.key
		end
	end
	return nil
end

function K.dayKey(t)
	return tonumber(os.date("%Y%m%d", t))
end

function K.monthKey(t)
	return tonumber(os.date("%Y%m", t))
end

-- ---------------------------------------------------------------- rules
-- may this character register as a mentor? info = {staff, banned, accountLevel (best character), onlineHours (the
-- account's), accountDays, level (this character), isApprentice (has an active mentor), registered}
function K.mentorCheck(info, cfg)
	local m = cfg.mentor
	if not cfg.enabled then
		return nil, "disabled"
	end
	if info.staff then
		return nil, "staff"
	end
	if info.banned then
		return nil, "banned"
	end
	if info.registered then
		return nil, "registered"
	end
	if info.isApprentice then
		return nil, "isApprentice"
	end
	if num(info.accountLevel) < m.minAccountLevel then
		return nil, "mentorLevel"
	end
	if num(info.onlineHours) < m.minOnlineHours then
		return nil, "mentorHours"
	end
	if num(info.accountDays) < m.minAccountDays then
		return nil, "mentorAge"
	end
	if num(info.level) < m.minCharacterLevel then
		return nil, "mentorCharLevel"
	end
	return true
end

-- may this character pick a mentor? info = {staff, banned, level, accountDays (nil = unknown creation date), hasMentor,
-- isMentor, graduated, mentors (how many it ever had), cooldownLeft (seconds)}
function K.apprenticeCheck(info, cfg)
	local a = cfg.apprentice
	if not cfg.enabled then
		return nil, "disabled"
	end
	if info.staff then
		return nil, "staff"
	end
	if info.banned then
		return nil, "banned"
	end
	if info.isMentor then
		return nil, "isMentor"
	end
	if info.graduated then
		return nil, "graduated"
	end
	if info.hasMentor then
		return nil, "hasMentor"
	end
	if num(info.level) > a.maxLevel then
		return nil, "apprenticeLevel"
	end
	if type(info.accountDays) ~= "number" or info.accountDays > a.maxAccountDays then
		return nil, "apprenticeAge"
	end
	if num(info.mentors) >= a.maxMentors then
		return nil, "maxMentors"
	end
	if num(info.cooldownLeft) > 0 then
		return nil, "cooldown"
	end
	return true
end

local function lookup(list)
	local set = {}
	for _, v in ipairs(list or {}) do
		set[tostring(v):lower()] = true
	end
	return set
end

local function shareIp(a, b)
	if ChaosReferralCore and ChaosReferralCore.shareIp then
		return ChaosReferralCore.shareIp(a, b)
	end
	local set = {}
	for _, ip in ipairs(a or {}) do
		if ip and ip ~= "" and ip ~= "0.0.0.0" then
			set[ip] = true
		end
	end
	for _, ip in ipairs(b or {}) do
		if ip and set[ip] then
			return true
		end
	end
	return false
end
K.shareIp = shareIp

local function emailDomain(email)
	if ChaosReferralCore and ChaosReferralCore.emailDomain then
		return ChaosReferralCore.emailDomain(email)
	end
	return nil
end

-- the same household: a shared IP (any login IP of either account, the website registration IP) or the same private
-- e-mail domain (the referral program's rules and public domain list)
function K.household(a, b, refCfg)
	if shareIp(a.ips, b.ips) then
		return "sameIp"
	end
	local d1, d2 = emailDomain(a.email), emailDomain(b.email)
	local publicDomains = refCfg and refCfg.antiAbuse and refCfg.antiAbuse.publicDomains or {}
	if d1 and d1 == d2 and not lookup(publicDomains)[d1] then
		return "sameEmail"
	end
	return nil
end

-- can `info.apprentice` take `info.mentor`? info = {
--   apprentice = {accountId, ips, email, + the apprenticeCheck fields},
--   mentor     = {exists, registered, accepting, accountId, ips, email, staff, banned, active (apprentices now),
--                 linksThisMonth},
--   source     "list" | "invite" | "referral" (an invite and the referral pick ignore `accepting`, not the free place),
--   pairBefore (this apprentice character had this mentor before)}
function K.linkCheck(info, cfg, refCfg)
	local me, him = info.apprentice or {}, info.mentor
	local ok, reason = K.apprenticeCheck(me, cfg)
	if not ok then
		return nil, reason
	end
	if not him or not him.exists or not him.registered then
		return nil, "noMentor"
	end
	if me.accountId and me.accountId == him.accountId then
		return nil, "sameAccount"
	end
	if him.staff then
		return nil, "mentorStaff"
	end
	if him.banned then
		return nil, "mentorBanned"
	end
	if info.pairBefore then
		return nil, "pairBefore"
	end
	if info.source == "list" and not him.accepting then
		return nil, "notAccepting"
	end
	if num(him.active) >= cfg.mentor.maxApprentices then
		return nil, "full"
	end
	if num(him.linksThisMonth) >= cfg.mentor.monthlyLinks then
		return nil, "monthlyLinks"
	end
	local same = K.household(me, him, refCfg)
	if same then
		return nil, same
	end
	return true
end

-- ---------------------------------------------------------------- the bonus
-- a monster's hunting level from its experience and health when bounty_pool.lua does not know it (the same estimate
-- as tools/gen_bounty_pool.py and ascension_quest_core.lua)
function K.estimateLevel(experience, health)
	local byExp = 1.6 * math.sqrt(math.max(num(experience), 1))
	local byHp = num(health) / 60
	local lvl = math.max(byExp, math.min(byHp, byExp * 1.5))
	return math.max(1, floor(lvl + 0.5))
end

-- not power-levelling: the mentor is not far over the content (the apprentice's level or the monster's)
function K.overLevelOk(mentorLevel, apprenticeLevel, monsterLevel, cfg)
	local o = cfg.overLevel
	local content = math.max(num(apprenticeLevel), num(monsterLevel))
	return num(mentorLevel) <= floor(content * o.ratio + o.flat)
end

-- ctx = {sameParty, mentorOnline, distance (nil: another floor or unknown), sameIpNow, mentorLevel, apprenticeLevel,
-- monsterLevel (nil: no monster, e.g. the window's "bonus now" line uses the apprentice's level only)}
function K.bonusActive(ctx, cfg)
	if not cfg.enabled then
		return false, "disabled"
	end
	if not ctx.mentorOnline then
		return false, "offline"
	end
	if not ctx.sameParty then
		return false, "party"
	end
	if type(ctx.distance) ~= "number" or ctx.distance > cfg.bonus.range then
		return false, "range"
	end
	if ctx.sameIpNow then
		return false, "sameIp"
	end
	if not K.overLevelOk(ctx.mentorLevel, ctx.apprenticeLevel, ctx.monsterLevel, cfg) then
		return false, "overLevel"
	end
	return true
end

K.BONUS_TEXT = {
	disabled = "The mentor system is off.",
	offline = "Your mentor is offline.",
	party = "Join a party with your mentor for the bonus.",
	range = "Stay close to your mentor for the bonus.",
	sameIp = "No bonus while you share a connection.",
	overLevel = "Your mentor is too high for these monsters: no bonus (no power-levelling)."
}

-- ---------------------------------------------------------------- marks
-- marks that may still be paid this month: paid, state
function K.pay(marks, monthMarks, cfg)
	local room = cfg.marks.monthlyCap - num(monthMarks)
	marks = num(marks)
	if marks <= 0 then
		return 0, "paid"
	end
	if room <= 0 then
		return 0, "capped"
	end
	if marks > room then
		return room, "paid"
	end
	return marks, "paid"
end

-- one shared hunting minute of a mentor (any apprentice): m = {dayKey, dayMinutes, dayMarks} (changed here); returns
-- the marks earned by it (0 or 1)
function K.huntMinute(m, now, cfg, monthMarks)
	local day = K.dayKey(now)
	if m.dayKey ~= day then
		m.dayKey, m.dayMinutes, m.dayMarks = day, 0, 0
	end
	m.dayMinutes = num(m.dayMinutes) + 1
	if m.dayMinutes % cfg.marks.huntMinutes ~= 0 or num(m.dayMarks) >= cfg.marks.dailyHuntMarks then
		return 0
	end
	local paid = K.pay(1, monthMarks, cfg)
	if paid > 0 then
		m.dayMarks = num(m.dayMarks) + 1
	end
	return paid
end

-- ---------------------------------------------------------------- milestones
-- facts = {level, rift, dungeon, bounty, worldboss (true once done)} -> {[milestone key] = true} of what is reached
function K.reachedNow(facts, cfg)
	local out = {}
	for _, m in ipairs(cfg.milestones) do
		if m.kind == "level" and num(facts.level) >= m.level then
			out[m.key] = true
		elseif m.kind == "event" and facts[m.event] then
			out[m.key] = true
		end
	end
	return out
end

-- the milestones reached by `facts` that have no row yet (states = {[key] = state})
function K.due(facts, states, cfg)
	local out, reached = {}, K.reachedNow(facts, cfg)
	for _, m in ipairs(cfg.milestones) do
		if reached[m.key] and not (states or {})[m.key] then
			out[#out + 1] = m
		end
	end
	return out
end

function K.milestone(cfg, key)
	for _, m in ipairs(cfg.milestones) do
		if m.key == key then
			return m
		end
	end
	return nil
end

-- ctx = {shared (minutes hunted together on this link), monthMarks (the mentor's this month)} -> state, marks
function K.decideMilestone(m, ctx, cfg)
	if num(ctx.shared) < cfg.marks.milestoneMinShared then
		return "unearned", 0
	end
	local paid, state = K.pay(m.marks, ctx.monthMarks, cfg)
	return state, paid
end

-- ctx = {shared, monthMarks} -> earned (both rewards), marks for the mentor
function K.decideGraduation(ctx, cfg)
	if num(ctx.shared) < cfg.marks.graduationMinShared then
		return false, 0
	end
	local paid = K.pay(cfg.graduation.marks, ctx.monthMarks, cfg)
	return true, paid
end

function K.graduationText(cfg)
	local parts = {}
	for _, it in ipairs(cfg.graduation.items or {}) do
		parts[#parts + 1] = it.count .. " " .. (it.name or ("x" .. it.id))
	end
	return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------- shop
function K.offer(cfg, key)
	for _, o in ipairs(cfg.shop) do
		if o.key == key then
			return o
		end
	end
	return nil
end

-- ctx = {marks, owned (title of this character / cosmetic of the account), weeklyUsed, cosmetics (false: off)}
function K.shopCheck(o, ctx, cfg)
	if not cfg.enabled then
		return nil, "disabled"
	end
	if not o then
		return nil, "unknownOffer"
	end
	if o.kind == "cosmetic" and ctx.cosmetics == false then
		return nil, "cosmeticOff"
	end
	if (o.kind == "title" or o.kind == "cosmetic") and ctx.owned then
		return nil, "owned"
	end
	if o.weekly and num(ctx.weeklyUsed) >= o.weekly then
		return nil, "weekly"
	end
	if num(ctx.marks) < o.cost then
		return nil, "notEnough"
	end
	return true
end

-- the shop titles a character owns ({[offer key] = os.time}) -> name plate titles
function K.titles(owned, cfg)
	local out = {}
	for _, o in ipairs(cfg.shop) do
		local at = owned and owned[o.key]
		if at and o.kind == "title" then
			out[#out + 1] = {key = "mentor:" .. o.key, text = o.name, color = o.color, at = at}
		end
	end
	return out
end

-- ---------------------------------------------------------------- lists
-- rows = {{guid, accountId, name, level, voc, line, lang, hours, note, online, lastLogin, graduates, active,
--          accepting}}; f = {line = key or "", lang = text or "", online = "now" | "week" | "any"};
-- viewer = {accountId, now}. Leaves out the viewer's account, mentors not accepting and full ones; online first,
-- then the most graduates, then the name. At most cfg.listMax.
function K.filterMentors(rows, f, cfg, viewer)
	f = f or {}
	viewer = viewer or {}
	local lang = K.cleanText(f.lang or "", 24):lower()
	local now = num(viewer.now)
	local out = {}
	for _, r in ipairs(rows or {}) do
		local keep = r.accepting and num(r.active) < cfg.mentor.maxApprentices and r.accountId ~= viewer.accountId
		if keep and f.line and f.line ~= "" and r.line ~= f.line then
			keep = false
		end
		if keep and lang ~= "" and not tostring(r.lang or ""):lower():find(lang, 1, true) then
			keep = false
		end
		if keep and f.online == "now" and not r.online then
			keep = false
		end
		if keep and f.online == "week" and not r.online and now - num(r.lastLogin) > 7 * 86400 then
			keep = false
		end
		if keep then
			out[#out + 1] = r
		end
	end
	table.sort(out, function(a, b)
		if (a.online and true or false) ~= (b.online and true or false) then
			return a.online and true or false
		end
		if num(a.graduates) ~= num(b.graduates) then
			return num(a.graduates) > num(b.graduates)
		end
		return tostring(a.name) < tostring(b.name)
	end)
	while #out > cfg.listMax do
		out[#out] = nil
	end
	return out
end

-- the Party Finder tag of a character: info = {mentor (registered, accepting, a free place), seeking (the flag set and
-- may pick a mentor now)}
function K.tagOf(info)
	if info.mentor then
		return "mentor"
	end
	if info.seeking then
		return "seeking"
	end
	return nil
end

-- ---------------------------------------------------------------- the client window
-- states = {[key] = {state, marks}} -> rows of every milestone and the graduation, in order
function K.milestoneRows(states, cfg)
	local out = {}
	states = states or {}
	for _, m in ipairs(cfg.milestones) do
		local s = states[m.key]
		out[#out + 1] = {key = m.key, name = m.name, marks = m.marks, state = s and s.state or "open", got = s and s.marks or 0}
	end
	local g = states.graduation
	out[#out + 1] = {key = "graduation", name = "Level " .. cfg.graduationLevel .. ": graduation", marks = cfg.graduation.marks,
		state = g and g.state or "open", got = g and g.marks or 0}
	return out
end

local function linkRow(l, cfg)
	return {guid = l.guid, name = l.name or "?", level = num(l.level), voc = l.voc or "", online = l.online and true or false,
		linkedAt = num(l.linkedAt), shared = num(l.shared), source = l.source or "list",
		milestones = K.milestoneRows(l.states, cfg)}
end

-- state = {me = {name, level, voc}, mentorOk, mentorReason, apprenticeOk, apprenticeReason, cooldownLeft,
--          mentor = {lang, hours, note, accepting, public, marks, earned, graduates, dayKey, dayMinutes, dayMarks,
--                    monthMarks, linksThisMonth, apprentices = {{guid, name, level, voc, online, linkedAt, shared, source,
--                    states}}} or nil,
--          apprentice = {guid, name, level, voc, online, linkedAt, shared, source, states, bonus, bonusReason} or nil,
--          invites = {{guid, name, level, voc, lang, at}}, seeking, referrer = {guid, name} or nil,
--          owned = {[offer key] = true}, weekly = {[offer key] = n}, top = {{name, graduates}}, graduated}
function K.view(state, cfg, now)
	local v = {
		enabled = cfg.enabled == true,
		me = state.me or {},
		rules = {exp = floor(cfg.bonus.exp * 100 + 0.5), dmg = floor(cfg.bonus.damageTaken * 100 + 0.5),
			maxApprentices = cfg.mentor.maxApprentices, maxLevel = cfg.apprentice.maxLevel, gradLevel = cfg.graduationLevel,
			accountDays = cfg.apprentice.maxAccountDays, huntMinutes = cfg.marks.huntMinutes,
			dailyHuntMarks = cfg.marks.dailyHuntMarks, monthlyCap = cfg.marks.monthlyCap,
			minShared = cfg.marks.milestoneMinShared, gradShared = cfg.marks.graduationMinShared,
			mentorLevel = cfg.mentor.minAccountLevel, mentorHours = cfg.mentor.minOnlineHours,
			mentorDays = cfg.mentor.minAccountDays, gradReward = K.graduationText(cfg), gradMarks = cfg.graduation.marks},
		canMentor = state.mentorOk and true or false,
		mentorNote = state.mentorOk and "" or K.say(cfg, state.mentorReason or "disabled"),
		canPick = state.apprenticeOk and true or false,
		pickNote = state.apprenticeOk and "" or K.say(cfg, state.apprenticeReason or "disabled", state.cooldownLeft),
		seeking = state.seeking and true or false,
		graduated = state.graduated and true or false,
		lines = {},
		invites = {},
		shop = {},
		top = {}
	}
	for _, l in ipairs(cfg.lines) do
		v.lines[#v.lines + 1] = {key = l.key, name = l.name}
	end
	local m = state.mentor
	if m then
		local today = K.dayKey(now)
		v.mentor = {lang = m.lang or "", hours = m.hours or "", note = m.note or "", accepting = m.accepting and true or false,
			public = m.public and true or false, marks = num(m.marks), earned = num(m.earned), graduates = num(m.graduates),
			dayMarks = m.dayKey == today and num(m.dayMarks) or 0, dayMinutes = m.dayKey == today and num(m.dayMinutes) or 0,
			monthMarks = num(m.monthMarks), linksThisMonth = num(m.linksThisMonth), monthlyLinks = cfg.mentor.monthlyLinks,
			apprentices = {}}
		for _, l in ipairs(m.apprentices or {}) do
			v.mentor.apprentices[#v.mentor.apprentices + 1] = linkRow(l, cfg)
		end
	end
	local a = state.apprentice
	if a then
		v.apprentice = linkRow(a, cfg)
		v.apprentice.bonus = a.bonus and true or false
		v.apprentice.bonusText = a.bonus and string.format("Bonus active: +%d%% experience, %d%% less damage taken.",
			v.rules.exp, v.rules.dmg) or (K.BONUS_TEXT[a.bonusReason or "party"] or "")
	end
	for _, i in ipairs(state.invites or {}) do
		v.invites[#v.invites + 1] = {guid = i.guid, name = i.name, level = num(i.level), voc = i.voc or "", lang = i.lang or "",
			left = math.max(0, num(i.at) + cfg.inviteMinutes * 60 - now)}
	end
	if state.referrer then
		v.referrer = {guid = state.referrer.guid, name = state.referrer.name}
	end
	for _, o in ipairs(cfg.shop) do
		local row = {key = o.key, kind = o.kind, name = o.name, desc = o.desc, cost = o.cost, color = o.color,
			owned = (state.owned or {})[o.key] and true or false}
		if o.weekly then
			row.weeklyLeft = math.max(0, o.weekly - num((state.weekly or {})[o.key]))
		end
		v.shop[#v.shop + 1] = row
	end
	for i, t in ipairs(state.top or {}) do
		v.top[#v.top + 1] = {rank = i, name = t.name, graduates = num(t.graduates), level = num(t.level), voc = t.voc or ""}
	end
	return v
end

-- ---------------------------------------------------------------- checks
local ORB_IDS = {[29855] = true, [29856] = true, [29857] = true}
K.SHOP_KINDS = {title = true, cosmetic = true, item = true}

-- opts = {cosmetics = cosmetics_config.lua table (optional)}
function K.validate(cfg, opts)
	opts = opts or {}
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	local supply = {}
	for _, id in ipairs(cfg.supplyIds or {}) do
		supply[id] = true
		if ORB_IDS[id] then
			bad("supply id %d is an orb", id)
		end
	end
	local keys = {}
	for i, o in ipairs(cfg.shop or {}) do
		local w = tostring(o.key or ("#" .. i))
		if type(o.key) ~= "string" or not o.key:match("^[%w_]+$") or keys[o.key] then
			bad("%s: key missing, not plain or used twice", w)
		end
		keys[o.key or "?"] = true
		if not K.SHOP_KINDS[o.kind] then
			bad("%s: kind %s is not sold for marks (titles, cosmetics and supplies only)", w, tostring(o.kind))
		end
		if type(o.cost) ~= "number" or o.cost <= 0 or o.cost ~= floor(o.cost) then
			bad("%s: cost must be a positive whole number", w)
		end
		if type(o.name) ~= "string" or o.name == "" or type(o.desc) ~= "string" then
			bad("%s: name and desc needed", w)
		end
		if o.kind == "title" and (#tostring(o.name) > 24 or not tostring(o.color or ""):match("^#%x%x%x%x%x%x$")) then
			bad("%s: a title is at most 24 characters with a #RRGGBB colour", w)
		end
		if o.kind == "item" then
			if not supply[o.item] then
				bad("%s: item %s is not a supply of supplyIds", w, tostring(o.item))
			end
			if type(o.count) ~= "number" or o.count < 1 or o.count > 100 then
				bad("%s: count 1-100", w)
			end
			if type(o.weekly) ~= "number" or o.weekly < 1 then
				bad("%s: supplies need a weekly limit", w)
			end
		end
		if o.kind == "cosmetic" then
			if type(o.cosmetic) ~= "string" then
				bad("%s: cosmetic key missing", w)
			elseif opts.cosmetics then
				local found
				for _, c in ipairs(opts.cosmetics.cosmetics or {}) do
					if c.key == o.cosmetic then
						found = c
					end
				end
				if not found then
					bad("%s: cosmetic %s does not exist", w, o.cosmetic)
				end
			end
		end
		for k in pairs(o) do
			if k == "damage" or k == "stats" or k == "bonus" or k == "exp" or k == "orb" or k == "gear" or k == "skill" then
				bad("%s: field %s is power", w, k)
			end
		end
	end
	local mk, last = {}, 0
	for _, m in ipairs(cfg.milestones or {}) do
		if mk[m.key] or m.key == "graduation" then
			bad("milestone %s: key used twice or reserved", tostring(m.key))
		end
		mk[m.key or "?"] = true
		if m.kind == "level" then
			if m.level <= last or m.level >= cfg.graduationLevel then
				bad("milestone %s: levels ascending and below the graduation", m.key)
			end
			last = m.level
		elseif m.kind ~= "event" or type(m.event) ~= "string" then
			bad("milestone %s: kind level or event", tostring(m.key))
		end
		if type(m.marks) ~= "number" or m.marks < 0 or m.marks > 50 then
			bad("milestone %s: 0-50 marks", tostring(m.key))
		end
	end
	for _, it in ipairs(cfg.graduation and cfg.graduation.items or {}) do
		if not supply[it.id] then
			bad("graduation item %s is not a supply", tostring(it.id))
		end
	end
	if cfg.apprentice.maxLevel >= cfg.graduationLevel then
		bad("apprentices must join below the graduation level")
	end
	if cfg.bonus.exp > 0.25 or cfg.bonus.damageTaken > 0.15 then
		bad("the apprentice bonus is a small one (at most +25%% experience, 15%% less damage taken)")
	end
	return problems
end

return K

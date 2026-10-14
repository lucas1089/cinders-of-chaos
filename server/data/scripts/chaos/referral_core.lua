-- Referral program: pure logic (no engine calls), shared by referral.lua and server/tests/referral_test.lua.
--   codes      ChaosReferralCore.normalize(text, cfg) -> "ABCD2345" or nil; format(code, cfg) -> "ABCD-2345";
--              make(rng, cfg) -> a new code (rng(n) -> 1..n)
--   facts      ipString(n) (engine / players.lastip: network order uint32) -> "a.b.c.d"; ipFromLong(n) (PHP ip2long,
--              host order) -> "a.b.c.d"; emailDomain(email) -> "example.com" or nil; monthKey(t) -> 202610
--   rules      entryLeft(created, now, cfg) -> seconds left to enter a code (nil = never had a creation date, <= 0 =
--              too late); codeHolder(info, cfg) -> true or nil, reason; linkCheck(info, cfg) -> true or nil, reason
--              (a reason is a key of cfg.messages; see linkCheck for `info`)
--   milestones due(level, reached, cfg) -> milestones of cfg.milestones reached at `level` and not yet in `reached`;
--              tiersDue(qualified, reached, cfg) -> tiers of cfg.tiers reached with `qualified` friends; tier(cfg, key)
--   networks   netKey(ip) -> "a.b.c.d" or an IPv6 /64; shareIp(a, b); sharePayer(a, b)
--   rewards    decide(reward, facts, cfg) -> "pay" | "wait" | "void"; rewardText(milestone) -> "the title X and 25
--              Chaos Coins"; giftText(cfg) -> "50 health potions, 50 mana potions"
--   titles     titles(state, cfg) -> name plate titles of an account (the gift's, the paid milestones')
--   view       view(state, cfg, now) -> what the client window shows
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosReferralCore = ChaosReferralCore or {}
local R = ChaosReferralCore

local floor = math.floor

-- ---------------------------------------------------------------- codes
function R.normalize(text, cfg)
	if type(text) ~= "string" or #text > 40 then
		return nil
	end
	local code = text:upper():gsub("[%s%-]", "")
	local c = cfg.code
	if #code ~= c.length then
		return nil
	end
	for i = 1, #code do
		if not c.alphabet:find(code:sub(i, i), 1, true) then
			return nil
		end
	end
	return code
end

function R.format(code, cfg)
	if type(code) ~= "string" or code == "" then
		return ""
	end
	local g = cfg.code.group or 0
	if g <= 0 or #code <= g then
		return code
	end
	local parts = {}
	for i = 1, #code, g do
		parts[#parts + 1] = code:sub(i, i + g - 1)
	end
	return table.concat(parts, "-")
end

function R.make(rng, cfg)
	local c = cfg.code
	local out = {}
	for i = 1, c.length do
		local k = rng(#c.alphabet)
		out[i] = c.alphabet:sub(k, k)
	end
	return table.concat(out)
end

-- ---------------------------------------------------------------- facts
-- the engine's IP (Player:getIp(), players.lastip): the first octet is the lowest byte
function R.ipString(n)
	n = tonumber(n)
	if not n or n <= 0 then
		return nil
	end
	n = floor(n)
	local a = n % 256
	local b = floor(n / 256) % 256
	local c = floor(n / 65536) % 256
	local d = floor(n / 16777216) % 256
	return string.format("%d.%d.%d.%d", a, b, c, d)
end

-- PHP ip2long (znote_accounts.ip): the first octet is the highest byte
function R.ipFromLong(n)
	n = tonumber(n)
	if not n or n <= 0 then
		return nil
	end
	n = floor(n)
	return string.format("%d.%d.%d.%d", floor(n / 16777216) % 256, floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
end

function R.emailDomain(email)
	if type(email) ~= "string" then
		return nil
	end
	local domain = email:lower():match("^[^@%s]+@([%w%.%-]+)%s*$")
	if not domain or not domain:find(".", 1, true) then
		return nil
	end
	return domain
end

function R.monthKey(t)
	return tonumber(os.date("%Y%m", t))
end

-- ---------------------------------------------------------------- rules
function R.entryLeft(created, now, cfg)
	created = tonumber(created) or 0
	if created <= 0 then
		return nil
	end
	return created + cfg.entryDays * 86400 - now
end

-- may this account have (and share) a code? info = {staff, banned, maxLevel}
function R.codeHolder(info, cfg)
	if not cfg.enabled then
		return nil, "disabled"
	end
	if info.staff then
		return nil, "referrerStaff"
	end
	if (tonumber(info.maxLevel) or 0) < (cfg.minReferrerLevel or 0) then
		return nil, "noCodeYet"
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

-- the key two addresses share when they count as one connection: an IPv4 address as it is, an IPv6 address by its
-- /64 (its first four groups, what one home connection gets); nil for an empty or unknown address
function R.netKey(ip)
	if type(ip) ~= "string" or ip == "" or ip == "0.0.0.0" then
		return nil
	end
	ip = ip:lower()
	if not ip:find(":", 1, true) then
		return ip:match("^%d+%.%d+%.%d+%.%d+$")
	end
	local v4 = ip:match("^::ffff:(%d+%.%d+%.%d+%.%d+)$")
	if v4 then
		return v4
	end
	local groups = {}
	local head, tail = ip:match("^(.-)::(.*)$")
	if head then
		local h, t = {}, {}
		for g in head:gmatch("[^:]+") do
			h[#h + 1] = g
		end
		for g in tail:gmatch("[^:]+") do
			t[#t + 1] = g
		end
		for _, g in ipairs(h) do
			groups[#groups + 1] = g
		end
		for _ = 1, 8 - #h - #t do
			groups[#groups + 1] = "0"
		end
		for _, g in ipairs(t) do
			groups[#groups + 1] = g
		end
	else
		for g in ip:gmatch("[^:]+") do
			groups[#groups + 1] = g
		end
	end
	if #groups ~= 8 then
		return nil
	end
	local out = {}
	for i = 1, 4 do
		local v = tonumber(groups[i], 16)
		if not v then
			return nil
		end
		out[i] = string.format("%x", v)
	end
	return table.concat(out, ":")
end

local function shareIp(a, b)
	local set = {}
	for _, ip in ipairs(a or {}) do
		local k = R.netKey(ip)
		if k then
			set[k] = true
		end
	end
	for _, ip in ipairs(b or {}) do
		local k = R.netKey(ip)
		if k and set[k] then
			return true
		end
	end
	return false
end
R.shareIp = shareIp

-- true when the two lists of payer hashes (chaos_pay_payers) share one
function R.sharePayer(a, b)
	local set = {}
	for _, p in ipairs(a or {}) do
		if type(p) == "string" and p ~= "" then
			set[p] = true
		end
	end
	for _, p in ipairs(b or {}) do
		if type(p) == "string" and p ~= "" and set[p] then
			return true
		end
	end
	return false
end

-- can `info.referee` take `info.referrer`'s code? info = {
--   now,
--   referee  = {accountId, created, staff, link (existing link row {status} or nil), ips = {"a.b.c.d"...}, email},
--   referrer = {accountId, staff, banned, ips, email, linksThisMonth, referredBy (account id or nil)},
--   ignoreWindow (website, at creation: the account is new)}
-- An existing link that was rejected may be replaced; an active or pending one may not.
function R.linkCheck(info, cfg)
	local me, him = info.referee, info.referrer
	local ab = cfg.antiAbuse or {}
	if not cfg.enabled then
		return nil, "disabled"
	end
	if not him then
		return nil, "unknownCode"
	end
	if me.accountId == him.accountId then
		return nil, "ownCode"
	end
	if me.link and me.link.status ~= "rejected" then
		return nil, "alreadyLinked"
	end
	if me.staff then
		return nil, "staff"
	end
	if not info.ignoreWindow then
		local left = R.entryLeft(me.created, info.now, cfg)
		if not left then
			return nil, "noCreation"
		end
		if left <= 0 then
			return nil, "tooOld"
		end
	end
	if him.staff then
		return nil, "referrerStaff"
	end
	if him.banned then
		return nil, "referrerBanned"
	end
	if him.referredBy and him.referredBy == me.accountId then
		return nil, "cycle"
	end
	if ab.sameIp and shareIp(me.ips, him.ips) then
		return nil, "sameIp"
	end
	if ab.sameEmailDomain then
		local d1, d2 = R.emailDomain(me.email), R.emailDomain(him.email)
		if d1 and d1 == d2 and not lookup(ab.publicDomains)[d1] then
			return nil, "sameEmail"
		end
	end
	if ab.monthlyLinks and (tonumber(him.linksThisMonth) or 0) >= ab.monthlyLinks then
		return nil, "monthlyLinks"
	end
	return true
end

-- ---------------------------------------------------------------- milestones and rewards
function R.due(level, reached, cfg)
	local out = {}
	reached = reached or {}
	for _, m in ipairs(cfg.milestones) do
		if (tonumber(level) or 0) >= m.level and not reached[m.key] then
			out[#out + 1] = m
		end
	end
	return out
end

function R.milestone(cfg, key)
	for _, m in ipairs(cfg.milestones) do
		if m.key == key then
			return m
		end
	end
	return nil
end

-- facts = {referredBanned, referrerBanned, paidThisMonth, referredAgeDays (nil = unknown, not checked), sameIp,
--          samePayer}. Void: a banned friend, a shared connection or payer by now (one person on both sides). Wait: a
-- banned referrer, a friend's account younger than minReferredAccountDays, the monthly cap.
function R.decide(facts, cfg)
	local ab = cfg.antiAbuse or {}
	if facts.referredBanned then
		return "void"
	end
	if ab.sameIpAtPayout and facts.sameIp then
		return "void"
	end
	if ab.samePayer and facts.samePayer then
		return "void"
	end
	if facts.referrerBanned then
		return "wait"
	end
	if ab.minReferredAccountDays and facts.referredAgeDays ~= nil and facts.referredAgeDays < ab.minReferredAccountDays then
		return "wait"
	end
	local cap = cfg.antiAbuse and cfg.antiAbuse.monthlyRewards
	if cap and (tonumber(facts.paidThisMonth) or 0) >= cap then
		return "wait"
	end
	return "pay"
end

function R.rewardText(m)
	local parts = {}
	if m.title then
		parts[#parts + 1] = "the title " .. m.title.text
	end
	if (tonumber(m.coins) or 0) > 0 then
		parts[#parts + 1] = m.coins .. " Chaos Coins"
	end
	if #parts == 0 then
		return "nothing"
	end
	return table.concat(parts, " and ")
end

-- the tiers newly reached with `qualified` friends (referred accounts whose cfg.qualify milestone was paid);
-- reached = {[tier key] = true}
function R.tiersDue(qualified, reached, cfg)
	local out = {}
	reached = reached or {}
	for _, t in ipairs(cfg.tiers or {}) do
		if (tonumber(qualified) or 0) >= t.count and not reached[t.key] then
			out[#out + 1] = t
		end
	end
	return out
end

function R.tier(cfg, key)
	for _, t in ipairs(cfg.tiers or {}) do
		if t.key == key then
			return t
		end
	end
	return nil
end

function R.giftText(cfg)
	local parts = {}
	for _, it in ipairs(cfg.starterGift.items or {}) do
		parts[#parts + 1] = it.count .. " " .. (it.name or ("x" .. it.id))
	end
	return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------- titles
-- state = {gift = bool (this account got the friend's gift), paid = {[milestone key] = os.time}, giftAt,
--          tiers = {[tier key] = os.time}}
function R.titles(state, cfg)
	local out = {}
	if state.gift and cfg.starterGift.title then
		local t = cfg.starterGift.title
		out[#out + 1] = {key = t.key, text = t.text, color = t.color, at = state.giftAt}
	end
	for _, m in ipairs(cfg.milestones) do
		local at = state.paid and state.paid[m.key]
		if at and m.title then
			out[#out + 1] = {key = m.title.key, text = m.title.text, color = m.title.color, at = at}
		end
	end
	for _, t in ipairs(cfg.tiers or {}) do
		local at = state.tiers and state.tiers[t.key]
		if at and t.title then
			out[#out + 1] = {key = t.title.key, text = t.title.text, color = t.title.color, at = at}
		end
	end
	return out
end

-- ---------------------------------------------------------------- the client window
-- state = {code, holder (bool), holderReason, entryLeft (seconds or nil), link = {status, referrerName, reason, gift},
--          friends = {{name, level, linkedAt, status, rewards = {[key] = {state, at}}}}, linksThisMonth,
--          paidThisMonth, coinsEarned}
function R.view(state, cfg, now)
	local ab = cfg.antiAbuse or {}
	local msg = cfg.messages
	local v = {
		enabled = cfg.enabled == true,
		code = state.code and R.format(state.code, cfg) or "",
		shareUrl = (state.code and cfg.shareUrl and cfg.shareUrl ~= "") and (cfg.shareUrl .. state.code) or "",
		codeNote = "",
		canEnter = false,
		enterNote = "",
		monthlyLinks = ab.monthlyLinks or 0,
		monthlyRewards = ab.monthlyRewards or 0,
		linksThisMonth = state.linksThisMonth or 0,
		paidThisMonth = state.paidThisMonth or 0,
		coinsEarned = state.coinsEarned or 0,
		gift = R.giftText(cfg),
		giftTitle = cfg.starterGift.title and cfg.starterGift.title.text or "",
		milestones = {},
		tiers = {},
		qualified = state.qualified or 0,
		friends = {}
	}
	local qm = R.milestone(cfg, cfg.qualify or "")
	v.qualifyLevel = qm and qm.level or 0
	for _, t in ipairs(cfg.tiers or {}) do
		v.tiers[#v.tiers + 1] = {key = t.key, count = t.count, reward = R.rewardText(t),
			reached = (state.tiers and state.tiers[t.key]) ~= nil}
	end
	if not state.code then
		local reason = state.holderReason or "noCodeYet"
		v.codeNote = string.format(msg[reason] or reason, cfg.minReferrerLevel or 0)
	end
	for _, m in ipairs(cfg.milestones) do
		v.milestones[#v.milestones + 1] = {key = m.key, level = m.level, reward = R.rewardText(m)}
	end
	local link = state.link
	if link and link.status ~= "rejected" then
		v.referrer = link.referrerName or ""
		v.linkStatus = link.status
		v.giftGiven = link.gift == true
	else
		local left = R.entryLeft(state.created, now, cfg)
		if state.staff then
			v.enterNote = msg.staff
		elseif not left then
			v.enterNote = msg.noCreation
		elseif left <= 0 then
			v.enterNote = string.format(msg.tooOld, cfg.entryDays)
		else
			v.canEnter = cfg.enabled == true
			v.enterLeft = left
		end
		if link and link.status == "rejected" then
			v.rejected = link.reason or ""
		end
	end
	for _, f in ipairs(state.friends or {}) do
		local row = {name = f.name or "?", level = f.level or 0, linkedAt = f.linkedAt or 0, status = f.status, steps = {}}
		for _, m in ipairs(cfg.milestones) do
			local r = f.rewards and f.rewards[m.key]
			row.steps[#row.steps + 1] = {level = m.level, state = r and r.state or "open"}
		end
		v.friends[#v.friends + 1] = row
	end
	return v
end

return R

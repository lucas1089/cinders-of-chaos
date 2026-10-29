-- Creator codes: pure logic (no engine calls), shared by creator_codes.lua and server/tests/creator_codes_test.lua.
--   codes      C.normalize(text, cfg) -> "ASHEN" or nil
--   shares     C.share(coins, pct, cfg) -> coins the creator earns for a donation of `coins` (floor, at most orderCap);
--              C.pctOf(codeRow, cfg, at) -> the code's own %, the launch window % or cfg.sharePct
--   support    C.supportCovers(support, orderCreated) -> true when the donor's pick covers a donation made then
--   networks   C.netKey(ip) -> "a.b.c.d" (IPv4) or the /64 of an IPv6 address ("2001:db8:0:1"); C.sameNet(a, b);
--              C.shareIp(listA, listB) -> true when any address of A is in a network of B
--   decision   C.decide(use, facts, cfg, now) -> "pay" | "wait" | "void", reason key (cfg.messages), amount
--   months     C.monthKey(t) -> 202610
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosCreatorCore = ChaosCreatorCore or {}
local C = ChaosCreatorCore

local floor = math.floor

-- ---------------------------------------------------------------- codes
function C.normalize(text, cfg)
	if type(text) ~= "string" or #text > 40 then
		return nil
	end
	local code = text:upper():gsub("[%s%-]", "")
	local lim = cfg.code or {min = 3, max = 16}
	if #code < lim.min or #code > lim.max or code:find("[^A-Z0-9]") then
		return nil
	end
	return code
end

-- ---------------------------------------------------------------- shares
-- the launch window: launchBonusStart ("YYYY-MM-DD HH:MM", server local time) for launchBonusDays days.
-- Returns the window's first and last unix second, or nil when the bonus is not set up.
function C.bonusWindow(cfg)
	local y, mo, d, h, mi = tostring(cfg.launchBonusStart or ""):match("^(%d+)-(%d+)-(%d+) (%d+):(%d+)$")
	local days = tonumber(cfg.launchBonusDays) or 0
	if not y or days <= 0 or (tonumber(cfg.launchBonusPct) or 0) <= 0 then
		return nil
	end
	local first = os.time({year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0})
	return first, first + days * 86400 - 1
end

-- the % a donation earns: the code's own % wins; else launchBonusPct for a donation credited inside the launch
-- window (`at`, unix time, nil = no window check); else sharePct
function C.pctOf(codeRow, cfg, at)
	local own = codeRow and tonumber(codeRow.pct) or 0
	if own and own > 0 then
		return own
	end
	local first, last = C.bonusWindow(cfg)
	at = tonumber(at)
	if first and at and at >= first and at <= last then
		return tonumber(cfg.launchBonusPct)
	end
	return tonumber(cfg.sharePct) or 0
end

function C.share(coins, pct, cfg)
	coins = math.max(0, floor(tonumber(coins) or 0))
	pct = math.max(0, math.min(100, tonumber(pct) or 0))
	local s = floor(coins * pct / 100)
	if cfg.orderCap and cfg.orderCap > 0 then
		s = math.min(s, cfg.orderCap)
	end
	return s
end

-- ---------------------------------------------------------------- support window
-- support = {set_at, expires_at}; the donation's order row was created at `created`
function C.supportCovers(support, created)
	if not support then
		return false
	end
	created = tonumber(created) or 0
	return created >= (tonumber(support.set_at) or 0) and created <= (tonumber(support.expires_at) or 0)
end

-- ---------------------------------------------------------------- networks
-- the key two addresses share when they count as one connection: an IPv4 address as it is, an IPv6 address by its
-- first four groups (the /64 a home connection gets). nil for empty / unknown
function C.netKey(ip)
	if type(ip) ~= "string" or ip == "" or ip == "0.0.0.0" then
		return nil
	end
	ip = ip:lower()
	if not ip:find(":", 1, true) then
		return ip:match("^%d+%.%d+%.%d+%.%d+$")
	end
	if ip:find(".", 1, true) then -- ::ffff:a.b.c.d (an IPv4 address written as IPv6)
		local v4 = ip:match("(%d+%.%d+%.%d+%.%d+)$")
		if v4 and ip:match("^::ffff:") then
			return v4
		end
	end
	local head, tail = ip:match("^(.-)::(.*)$")
	local groups = {}
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
		local n = tonumber(groups[i], 16)
		if not n then
			return nil
		end
		out[i] = string.format("%x", n)
	end
	return table.concat(out, ":")
end

function C.sameNet(a, b)
	local ka, kb = C.netKey(a), C.netKey(b)
	return ka ~= nil and ka == kb
end

function C.shareIp(a, b)
	local set = {}
	for _, ip in ipairs(a or {}) do
		local k = C.netKey(ip)
		if k then
			set[k] = true
		end
	end
	for _, ip in ipairs(b or {}) do
		local k = C.netKey(ip)
		if k and set[k] then
			return true
		end
	end
	return false
end

local function sharePayer(a, b)
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
C.sharePayer = sharePayer

-- ---------------------------------------------------------------- decision
-- use   = {buyer (account id), creator (account id), share (coins), credited (unix time the donation was credited)}
-- facts = {codeExists, codeActive, creatorBanned, reversed (refund / chargeback of the donation), buyerIps, creatorIps,
--          buyerPayers, creatorPayers (payer hashes), paidThisMonth (coins already paid to the creator this month)}
-- Returns "pay" | "wait" | "void", the reason (a key of cfg.messages, or "hold" / "cap" / "zero"), the coins to pay.
function C.decide(use, facts, cfg, now)
	local ab = cfg.antiAbuse or {}
	if not facts.codeExists then
		return "void", "nocode", 0
	end
	if ab.selfUse ~= false and use.buyer == use.creator then
		return "void", "self", 0
	end
	if facts.reversed then
		return "void", "reversed", 0
	end
	if not facts.codeActive then
		return "void", "inactive", 0
	end
	if ab.sameIp ~= false and C.shareIp(facts.buyerIps, facts.creatorIps) then
		return "void", "sameIp", 0
	end
	if ab.samePayer ~= false and sharePayer(facts.buyerPayers, facts.creatorPayers) then
		return "void", "samePayer", 0
	end
	local share = math.max(0, floor(tonumber(use.share) or 0))
	if share <= 0 then
		return "void", "zero", 0
	end
	if (tonumber(now) or 0) < (tonumber(use.credited) or 0) + (cfg.holdDays or 0) * 86400 then
		return "wait", "hold", 0
	end
	if facts.creatorBanned then
		return "wait", "banned", 0
	end
	if cfg.monthlyCap and cfg.monthlyCap > 0 and (tonumber(facts.paidThisMonth) or 0) + share > cfg.monthlyCap then
		return "wait", "cap", 0
	end
	return "pay", "ok", share
end

function C.monthKey(t)
	return tonumber(os.date("%Y%m", t))
end

return C

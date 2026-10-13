-- Run from the server/ folder: luajit tests/creator_codes_test.lua (and lua5.3; CI runs both)
-- Creator codes, pure logic (creator_codes_core.lua) with the real creator_codes_config.lua: code format, the share and
-- its caps, the donor's pick window, IPv4 and IPv6 /64 networks, and every decision (own account, same connection,
-- same payer, refund / chargeback, code off, hold, banned creator, monthly cap). The engine file and the SQL file are
-- checked to agree on the tables.
dofile("data/scripts/chaos/creator_codes_core.lua")
local C = ChaosCreatorCore
local cfg = dofile("data/scripts/chaos/creator_codes_config.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config
eq(cfg.enabled, true, "on")
eq(cfg.sharePct > 0 and cfg.sharePct <= 20, true, "share is a small placeholder %")
eq(cfg.holdDays >= 7, true, "a hold long enough for most chargebacks")
eq(cfg.adminGroup, 5, "codes are an administrator action (group 5+)")
eq(cfg.antiAbuse.selfUse and cfg.antiAbuse.sameIp and cfg.antiAbuse.samePayer, true, "every anti-abuse rule on")
for _, key in ipairs({"self", "sameIp", "samePayer", "reversed", "inactive", "banned", "nocode", "paid"}) do
	eq(type(cfg.messages[key]), "string", "message " .. key)
end

-- ---------------------------------------------------------------- codes
eq(C.normalize("ashen", cfg), "ASHEN", "upper case")
eq(C.normalize(" Ash-En 2 ", cfg), "ASHEN2", "spaces and dashes dropped")
eq(C.normalize("ab", cfg), nil, "too short")
eq(C.normalize(string.rep("A", 17), cfg), nil, "too long")
eq(C.normalize("ASH!", cfg), nil, "letters and digits only")
eq(C.normalize("'; DROP", cfg), nil, "no quotes")
eq(C.normalize(nil, cfg), nil, "nil")

-- ---------------------------------------------------------------- shares
eq(C.share(1000, 5, cfg), 50, "5% of 1000")
eq(C.share(199, 5, cfg), 9, "rounded down")
eq(C.share(100000, 5, cfg), cfg.orderCap, "capped per donation")
eq(C.share(-5, 5, cfg), 0, "never negative")
eq(C.pctOf({pct = 0}, cfg), cfg.sharePct, "default %")
eq(C.pctOf({pct = 8}, cfg), 8, "the code's own %")

-- ---------------------------------------------------------------- the donor's pick window
local sup = {set_at = 1000, expires_at = 1000 + cfg.supportDays * 86400}
eq(C.supportCovers(sup, 1500), true, "inside")
eq(C.supportCovers(sup, 999), false, "a donation before the pick")
eq(C.supportCovers(sup, sup.expires_at + 1), false, "after it ran out")
eq(C.supportCovers(nil, 1500), false, "no pick")

-- ---------------------------------------------------------------- networks
eq(C.netKey("10.0.0.1"), "10.0.0.1", "IPv4 as is")
eq(C.netKey("2001:db8:aa:1:1111:2222:3333:4444"), "2001:db8:aa:1", "IPv6 /64")
eq(C.netKey("2001:DB8:AA:1::5"), "2001:db8:aa:1", "IPv6 compressed, upper case")
eq(C.netKey("2001:db8::1"), "2001:db8:0:0", "IPv6 :: in the prefix")
eq(C.netKey("::ffff:10.0.0.1"), "10.0.0.1", "IPv4-mapped")
eq(C.netKey(""), nil, "empty")
eq(C.netKey("0.0.0.0"), nil, "no address")
eq(C.sameNet("2001:db8:aa:1::5", "2001:db8:aa:1:ffff::9"), true, "one /64")
eq(C.sameNet("2001:db8:aa:1::5", "2001:db8:aa:2::5"), false, "two /64s")
eq(C.shareIp({"1.2.3.4", "2001:db8:aa:1::5"}, {"5.6.7.8", "2001:db8:aa:1::77"}), true, "lists share a /64")
eq(C.shareIp({"1.2.3.4"}, {"1.2.3.5"}), false, "IPv4 compared exactly")

-- ---------------------------------------------------------------- decisions
local now = 10000000
local use = {buyer = 10, creator = 20, share = 50, credited = now - (cfg.holdDays + 1) * 86400}
local function facts(over)
	local f = {codeExists = true, codeActive = true, creatorBanned = false, reversed = false, buyerIps = {"1.1.1.1"},
		creatorIps = {"2.2.2.2"}, buyerPayers = {"aa"}, creatorPayers = {"bb"}, paidThisMonth = 0}
	for k, v in pairs(over or {}) do
		f[k] = v
	end
	return f
end
local function decide(u, f)
	local s, r, a = C.decide(u, f, cfg, now)
	return s .. ":" .. r .. ":" .. a
end
eq(decide(use, facts()), "pay:ok:50", "paid after the hold")
eq(decide({buyer = 20, creator = 20, share = 50, credited = use.credited}, facts()), "void:self:0", "no self-use")
eq(decide(use, facts({buyerIps = {"2.2.2.2"}})), "void:sameIp:0", "same connection")
eq(decide(use, facts({buyerIps = {"2001:db8::1"}, creatorIps = {"2001:db8:0:0:9::1"}})), "void:sameIp:0", "same /64")
eq(decide(use, facts({buyerPayers = {"bb"}})), "void:samePayer:0", "same payer")
eq(decide(use, facts({reversed = true})), "void:reversed:0", "refund or chargeback")
eq(decide(use, facts({codeActive = false})), "void:inactive:0", "code switched off")
eq(decide(use, facts({codeExists = false})), "void:nocode:0", "code deleted")
eq(decide({buyer = 10, creator = 20, share = 0, credited = use.credited}, facts()), "void:zero:0", "nothing to pay")
eq(decide({buyer = 10, creator = 20, share = 50, credited = now - 86400}, facts()), "wait:hold:0", "inside the hold")
eq(decide(use, facts({creatorBanned = true})), "wait:banned:0", "banned creator waits")
eq(decide(use, facts({paidThisMonth = cfg.monthlyCap - 49})), "wait:cap:0", "over the month's cap: waits, never cut")
eq(decide(use, facts({paidThisMonth = cfg.monthlyCap - 50})), "pay:ok:50", "exactly at the cap")
-- the order matters: a refunded donation is void even inside the hold
eq(decide({buyer = 10, creator = 20, share = 50, credited = now}, facts({reversed = true})), "void:reversed:0", "void before hold")

-- ---------------------------------------------------------------- tables: engine, SQL file and config agree
local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end
local engine = read("data/scripts/chaos/creator_codes.lua")
local sql = read("sql/chaos_creator_codes.sql")
for _, t in pairs(cfg.tables) do
	eq(engine:find("CREATE TABLE IF NOT EXISTS `" .. t .. "`", 1, true) ~= nil, true, "engine creates " .. t)
	eq(sql:find("CREATE TABLE IF NOT EXISTS `" .. t .. "`", 1, true) ~= nil, true, "sql file creates " .. t)
end
eq(engine:find("chaos_shop_coins", 1, true) ~= nil, true, "paid into the store balance table")
eq(engine:find("shop_config", 1, true), nil, "the store's files are not touched")

print("creator_codes_test: " .. n .. " checks OK")

-- Run from the server/ folder: luajit tests/founder_test.lua (and lua5.3; CI runs both)
-- The Founder Pack (O322): founder_config.lua (the dates, two tiers, the store category), founder_core.lua (the window, the
-- titles, the checks), the exclusives it gives (source founder), the plate frame, the title source of founder.lua, and
-- the store's window and one-per-account rules in shop_test.lua. Nothing here is power: cosmetics, a title and Pact days.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/nameplate_core.lua")
dofile("data/scripts/chaos/exclusives_core.lua")
dofile("data/scripts/chaos/founder_core.lua")
local K, F = ChaosShopCore, ChaosFounderCore
local cfg = dofile("data/scripts/chaos/founder_config.lua")
local excl = dofile("data/scripts/chaos/exclusives_config.lua")
local limits = dofile("data/scripts/chaos/store_balance_config.lua").founder
local pact = dofile("data/scripts/chaos/pact_config.lua")

-- ---------------------------------------------------------------- the dates
local T0, T1 = K.parseTime(cfg.start), K.parseTime(cfg["end"])
eq(cfg.start, "2026-11-20 15:00", "launch: 20/11/2026 15:00 server time")
eq(cfg["end"], "2026-12-18 15:00", "four weeks later")
eq((T1 - T0) / 86400, 28, "28 days")
eq(F.state(cfg, T0 - 1), "early", "before") eq(F.state(cfg, T0), "open", "launch") eq(F.state(cfg, T1 - 1), "open", "last second")
eq(F.state(cfg, T1), "late", "ended") eq(F.state(cfg, T1 + 10 * 365 * 86400), "late", "never again")

-- ---------------------------------------------------------------- the tiers
eq(#cfg.tiers, 2, "two tiers")
local one, grand = F.tier(cfg, "founder:pack"), F.tier(cfg, "founder:grand")
eq(F.tier(cfg, "founder:nope"), nil, "unknown tier")
eq(one.cost, 499, "about R$ 50 (one coin is about R$ 0,10)") eq(grand.cost, 999, "about R$ 100")
eq(one.cost, limits.anchors["founder:pack"], "the model's anchor, first") eq(grand.cost, limits.anchors["founder:grand"], "the model's anchor, grand")
eq(#grand.exclusives > #one.exclusives, true, "the grand pack gives more pieces")
local problems = F.validate(cfg, {exclusives = excl, limits = limits, pactPrice = pact.store.pact.offers[1].cost})
eq(#problems, 0, "the config validates: " .. table.concat(problems, "; "))
eq(#ChaosExclusivesCore.validate(excl, {founder = cfg}), 0, "the exclusives validate against the tiers: " ..
	table.concat(ChaosExclusivesCore.validate(excl, {founder = cfg}), "; "))

-- every piece is a founder exclusive of a cosmetic kind, given by exactly one tier, and nobody drops or sells it
local byKey = {}
for _, e in ipairs(excl.exclusives) do byKey[e.key] = e end
local given = {}
for _, t in ipairs(cfg.tiers) do
	for _, key in ipairs(t.exclusives) do
		local e = byKey[key]
		eq(e ~= nil, true, key .. " exists")
		eq(e.source, "founder", key .. ": source founder")
		eq(F.COSMETIC_KINDS[e.kind], true, key .. ": a cosmetic (" .. e.kind .. ")")
		given[key] = (given[key] or 0) + 1
	end
end
for key, count in pairs(given) do eq(count, 1, key .. " is in one tier") end
for _, e in ipairs(excl.exclusives) do
	if e.source == "founder" then
		eq(given[e.key], 1, e.key .. " is given by a tier")
		for _, b in ipairs(excl.bosses) do
			for _, r in ipairs(b.rewards) do eq(r ~= e.key, true, e.key .. " is no boss drop") end
		end
	end
end
eq(excl.founderHow, cfg.how, "the Collection tab text comes from the config")
eq(ChaosExclusivesCore.how(excl, byKey.wings_gold_peacock), cfg.how, "how: the Founder Pack")
-- no power, nothing finished: the exclusives of a founder pack are looks
for _, e in ipairs(excl.exclusives) do
	eq(e.damage == nil and e.bonus == nil and e.stats == nil and e.price == nil, true, e.key .. ": no power, no price")
end

-- the frame of the grand pack: a store slot, the client's picture, never sold as an offer
eq(byKey.frame_founder.frame, "founder", "the grand pack's frame")
eq(ChaosNameplate.FRAMES.founder, true, "the client has the plate")
eq(K.frameIndex("founder"), 17, "the 17th frame slot (never reorder)")
eq(K.FRAMES[16], "infernal", "the frames before it stay where they are")
local f = io.open("../client/overlay/modules/game_nameplate/images/plate_founder.png", "rb")
eq(f ~= nil, true, "the plate picture exists (client/tools/gen_nameplate_art.py)")
if f then f:close() end
local lua = io.open("../client/overlay/modules/game_nameplate/nameplatemath.lua", "rb"):read("*a")
eq(lua:find("founder = true", 1, true) ~= nil, true, "the client's frame list names it")

-- ---------------------------------------------------------------- the store category
local pack = cfg.store.pack
eq(#pack.offers, 2, "two offers")
for i, o in ipairs(pack.offers) do
	local t = cfg.tiers[i]
	eq(o.key, t.key, "offer key") eq(o.cost, t.cost, "offer price") eq(o.kind, "bundle", "a bundle")
	eq(o.oncePerAccount, true, "one per account and tier") eq(o.gift, false, "not giftable") eq(o.maxLevel, nil, "no level gate")
	eq(o.availableFrom, cfg.start, "window start") eq(o.availableUntil, cfg["end"], "window end")
	eq(#o.parts, #t.exclusives + 1, "the pieces and the Pact days")
	local pactPart = o.parts[#o.parts]
	eq(pactPart.kind, "pact", "Pact days last") eq(pactPart.days, t.pactDays, "days") eq(pactPart.required, true, "needs the Pact system")
	eq(math.abs(pactPart.cost - pact.store.pact.offers[1].cost / 30 * t.pactDays) <= 1, true, "listed at the Pact's own price")
	for j, key in ipairs(t.exclusives) do
		eq(o.parts[j].kind, "exclusive", "a piece") eq(o.parts[j].exclusive, key, "piece " .. key)
		eq(K.offerKey(o.parts[j]), "exclusive:" .. key, "a part key")
	end
	eq(o.description:find("never sold again", 1, true) ~= nil, true, "the text says it does not return")
end
eq(pack.offers[1].description:find("Founder title", 1, true) ~= nil, true, "the first pack names its title")
local starter = dofile("data/scripts/chaos/shop_config.lua").categories
eq(starter[1].name, "Starter", "the Starter packs stay first") eq(starter[2].name, "Founder Pack", "the Founder Pack is second")
-- it does not clash with the Starter packs: they are for young characters and hold supplies, these hold looks
for _, o in ipairs(starter[1].offers) do
	eq(o.key:match("^founder:"), nil, "no shared key")
end

-- ---------------------------------------------------------------- titles
local owned = {}
local function owns(key) return owned[key] == true end
eq(#F.titles(cfg, owns), 0, "no title without the pack")
owned.wings_gold_peacock = true
local t = F.titles(cfg, owns)
eq(#t, 1, "one title") eq(t[1].text, "Founder", "the Founder title") eq(t[1].key, "founder", "its key") eq(t[1].color, "#e8b04a", "its colour")
owned.wings_pyre_seraph = true
t = F.titles(cfg, owns)
eq(#t, 2, "both packs, both titles") eq(t[2].text, "Grand Founder", "the Grand Founder title")
for _, x in ipairs(t) do eq(#x.text <= ChaosNameplate.MAX_TITLE, true, x.text .. " fits a plate") end
-- only the pack gives the first piece, so a title never needs its own table
owned = {head_royal_coronet = true}
eq(#F.titles(cfg, owns), 0, "a single other piece is not the pack")

-- the engine file: the source is put into the titles registry and reads the exclusives of the account
local sources, granted = {}, {}
CreatureEvent = function() return {register = function() end} end
GlobalEvent = function() return {register = function() end} end
db = {query = function() return true end, escapeString = function(x) return "'" .. tostring(x) .. "'" end}
ChaosTitles = {register = function(name, fn) sources[name] = fn end}
ChaosExclusives = {owns = function(acc, key) return (granted[acc] or {})[key] == true end}
dofile("data/scripts/chaos/founder.lua")
eq(type(sources.founder), "function", "the title source is registered")
local player = {getAccountId = function() return 41 end}
eq(sources.founder(player), nil, "no title without the pieces")
granted[41] = {wings_gold_peacock = true}
local titles = sources.founder(player)
eq(titles[1].text, "Founder", "the source answers for the account")
granted[41].wings_pyre_seraph = true
eq(#sources.founder(player), 2, "and for both packs")

-- ---------------------------------------------------------------- a reversed donation takes the pack back
do
	local order = {id = 9, created = 1000}
	local function tiers(list) local o = {} for i, t in ipairs(list) do o[i] = t.key end return table.concat(o, ",") end
	local buys = {{id = 1, key = "founder:pack", created = 1500, gift = 0}, {id = 2, key = "founder:grand", created = 2000, gift = 0}}
	eq(tiers(F.revokeTargets(cfg, order, 0, buys, {})), "", "the balance covered the reversal: nothing is taken back")
	eq(tiers(F.revokeTargets(cfg, order, 999, buys, {})), "founder:grand,founder:pack", "both packs after the donation, dearest first")
	eq(tiers(F.revokeTargets(cfg, order, 500, buys, {})), "founder:grand,founder:pack", "500 of 999 is half: the grand pack goes too")
	eq(tiers(F.revokeTargets(cfg, order, 499, buys, {})), "founder:pack", "499 is under half of 999: only the first pack")
	eq(tiers(F.revokeTargets(cfg, order, 249, buys, {})), "", "249 is under half of 499: a small refund keeps the pack")
	eq(tiers(F.revokeTargets(cfg, order, 250, buys, {})), "founder:pack", "250 is half of 499")
	eq(tiers(F.revokeTargets(cfg, order, 999, buys, {["founder:grand"] = true})), "founder:pack", "a tier taken back before is not taken again")
	eq(tiers(F.revokeTargets(cfg, {id = 9, created = 1800}, 999, buys, {})), "founder:grand", "a pack bought before the donation was not paid by it")
	eq(tiers(F.revokeTargets(cfg, order, 999, {{id = 1, key = "founder:pack", created = 1500, gift = 7}}, {})), "", "a gift is not the account's pack")
	eq(tiers(F.revokeTargets(cfg, order, 999, {{id = 1, key = "service:pact:30", created = 1500, gift = 0}}, {})), "", "other offers are not touched")
	eq(tiers(F.revokeTargets(cfg, order, nil, buys, nil)), "", "no shortfall given")
end

-- the engine side: the pieces, the Pact days and the record; once per account and tier
do
	local rows, queries, said, exclusive, pactLeft = {}, {}, {}, {}, {[41] = 44}
	for _, k in ipairs({"wings_pyre_seraph", "cape_phoenix_plume_cape", "head_double_halo", "frame_founder", "wings_gold_peacock", "head_royal_coronet"}) do
		exclusive[k] = true
	end
	local realSelect, realQuery = Chaos.select, db and db.query
	db = {escapeString = function(x) return "'" .. tostring(x) .. "'" end,
		query = function(q)
			queries[#queries + 1] = q
			local acc, tier = q:match("^INSERT INTO `chaos_founder_revokes`.- VALUES %((%d+), '([^']*)'")
			if acc then rows[#rows + 1] = {account = tonumber(acc), tier = tier} end
			return true
		end}
	Chaos.select = function(q, cols)
		if q:find("FROM `chaos_founder_revokes`", 1, true) then
			local out = {}
			for _, r in ipairs(rows) do if q:find("`account_id` = " .. r.account, 1, true) then out[#out + 1] = {tier = r.tier} end end
			return out
		elseif q:find("FROM `chaos_shop_purchases`", 1, true) then
			return {{id = 1, offer_key = "founder:grand", created = 2000, gift_player = 0}}
		end
		return {}
	end
	Chaos.t = function(_, text, ...) return string.format(text, ...) end
	Chaos.storage = Chaos.storage or {}
	local online = {getAccountId = function() return 41 end, sendTextMessage = function(_, _, text) said[#said + 1] = text end,
		setStorageValue = function() end, getStorageValue = function() return 0 end}
	Game = {getPlayers = function() return {online} end}
	MESSAGE_EVENT_ADVANCE = 1
	ChaosExclusives.revoke = function(acc, key) exclusive[key] = nil; return true end
	ChaosExclusives.owns = function(acc, key) return exclusive[key] == true end
	local pactCalls = {}
	ChaosPact = {revokeDays = function(acc, days, why) pactCalls[#pactCalls + 1] = {acc, days, why}; return days end}
	ChaosShopCore.frameIndex = ChaosShopCore.frameIndex
	dofile("data/scripts/chaos/founder.lua")
	local ok, line = ChaosFounder.revoke(41, "founder:grand", {orderId = 9, purchaseId = 1, reason = "donation 9 reversed"})
	eq(ok, true, "taken back: " .. tostring(line))
	eq(exclusive.wings_pyre_seraph, nil, "the wings are gone") eq(exclusive.frame_founder, nil, "the frame is gone")
	eq(exclusive.head_double_halo, nil, "the halo is gone") eq(exclusive.cape_phoenix_plume_cape, nil, "the cape is gone")
	eq(exclusive.wings_gold_peacock, true, "the other pack stays")
	eq(#pactCalls, 1, "the Pact days") eq(pactCalls[1][2], 30, "30 days of the Grand Founder Pack") eq(pactCalls[1][1], 41, "of the account")
	eq(#rows, 1, "one record") eq(rows[1].tier, "founder:grand", "of the tier")
	eq(line:find("30 Pact days", 1, true) ~= nil and line:find("4 pieces", 1, true) ~= nil, true, "the line says what was taken: " .. line)
	eq(#said, 1, "the player is told") eq(said[1]:find("Grand Founder Pack was taken back", 1, true) ~= nil, true, "in words")
	ok2, why = ChaosFounder.revoke(41, "founder:grand", {})
	eq(ok2, false, "a second time") eq(why:find("already", 1, true) ~= nil, true, "refused: " .. tostring(why))
	eq(#pactCalls, 1, "no second Pact revoke")
	eq(ChaosFounder.revoke(41, "founder:nope", {}), false, "an unknown tier")
	-- the reversal hook: a purchase of the tier after the donation, a shortfall of 600
	rows = {}
	exclusive.wings_pyre_seraph = true
	local lines = ChaosFounder.onReversal(41, {id = 9, created = 1000}, 600)
	eq(#lines, 1, "one tier taken back by the reversal") eq(rows[1].tier, "founder:grand", "the grand pack")
	lines = ChaosFounder.onReversal(41, {id = 10, created = 1000}, 600)
	eq(#lines, 0, "and not twice")
	lines = ChaosFounder.onReversal(41, {id = 11, created = 1000}, 100)
	eq(#lines, 0, "a small shortfall keeps it")
	Chaos.select = realSelect
end

-- ---------------------------------------------------------------- rules that fail when broken
local function broken(change)
	local copy = dofile("data/scripts/chaos/founder_config.lua")
	change(copy)
	return table.concat(F.validate(copy, {exclusives = excl, limits = limits, pactPrice = 299}), "\n")
end
eq(broken(function(c) c.revoke.minShortfallPct = 0 end):find("minShortfallPct", 1, true) ~= nil, true, "a revoke rule of zero")
eq(broken(function(c) c.revoke.table = "players" end):find("chaos_*", 1, true) ~= nil, true, "a revoke table that is not ours")
eq(broken(function(c) c["end"] = c.start end):find("ends before it starts", 1, true) ~= nil, true, "an empty window")
eq(broken(function(c) c["end"] = "2026-11-21 15:00" end):find("days (", 1, true) ~= nil, true, "a window of one day")
eq(broken(function(c) c["end"] = "2027-06-01 15:00" end):find("days (", 1, true) ~= nil, true, "a window of months")
eq(broken(function(c) c.start = "soon" end):find("YYYY-MM-DD", 1, true) ~= nil, true, "a bad date")
eq(broken(function(c) c.tiers[1].exclusives = {"mount_tuskhide"} end):find("source founder", 1, true) ~= nil, true,
	"an achievement exclusive in a pack")
eq(broken(function(c) c.tiers[1].exclusives = {"wings_nobody"} end):find("does not exist", 1, true) ~= nil, true, "a missing piece")
eq(broken(function(c) c.tiers[1].exclusives = {} end):find("at least one exclusive", 1, true) ~= nil, true, "an empty pack")
eq(broken(function(c) c.tiers[1].pactDays = 60 end):find("Pact days", 1, true) ~= nil, true, "too many Pact days")
eq(broken(function(c) c.tiers[1].title.text = string.rep("x", 25) end):find("title", 1, true) ~= nil, true, "a title too long for a plate")
eq(broken(function(c) c.tiers[2].key = "founder:pack" end):find("used twice", 1, true) ~= nil, true, "a key used twice")
eq(broken(function(c) c.tiers[2].title.key = "founder" end):find("title key used twice", 1, true) ~= nil, true, "a title key used twice")
-- an exclusive of source founder that no tier gives
do
	local c = {exclusives = {}, kinds = excl.kinds, bosses = {}}
	for i, e in ipairs(excl.exclusives) do c.exclusives[i] = e end
	local extra = {key = "wings_extra", kind = "wings", id = 99, look = 1, icon = 2160, source = "founder", name = "Extra", desc = "x"}
	c.exclusives[#c.exclusives + 1] = extra
	local p = table.concat(ChaosExclusivesCore.validate(c, {founder = cfg}), "\n")
	eq(p:find("wings_extra: needs exactly one Founder Pack tier", 1, true) ~= nil, true, "a founder exclusive nobody gives")
end

print(string.format("founder_test: %d checks OK", checks))

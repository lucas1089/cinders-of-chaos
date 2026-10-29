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

-- ---------------------------------------------------------------- rules that fail when broken
local function broken(change)
	local copy = dofile("data/scripts/chaos/founder_config.lua")
	change(copy)
	return table.concat(F.validate(copy, {exclusives = excl, limits = limits, pactPrice = 299}), "\n")
end
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

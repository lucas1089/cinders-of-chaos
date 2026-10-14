-- Run from the server/ folder: luajit tests/seasonpass_test.lua (and lua5.3; CI runs both)
-- Pure logic of the season pass (seasonpass_core.lua) with the real seasonpass_config.lua: the shipped config (reward
-- kinds, no power items, 50 tiers, cosmetics claimed nowhere else), the tier curve and tier skips, the experience
-- units and the daily caps, the challenge rotation, claims (tier, premium, double claims, the season's end), pack
-- prices and upgrades, pack grants, the account's cosmetics, the store category and the season Town Portal styles.
dofile("data/scripts/chaos/seasonpass_core.lua")
local P = ChaosSeasonPassCore
local cfg = dofile("data/scripts/chaos/seasonpass_config.lua")
local seasonCfg = dofile("data/scripts/chaos/season_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function t(y, mo, d, hh, mi)
	return os.time({year = y, month = mo, day = d, hour = hh or 0, min = mi or 0, sec = 0})
end

-- ---------------------------------------------------------------- shipped config
local problems = P.validate(cfg)
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
eq(#problems, 0, "shipped config validates")
eq(cfg.maxTier, 50, "50 tiers")
for id in pairs(cfg.passes) do
	local found = false
	for _, s in ipairs(seasonCfg.seasons) do
		found = found or s.id == id
	end
	eq(found, true, "pass " .. id .. " belongs to a season of season_config.lua")
end
local pass = cfg.passes[1]
eq(#pass.tiers, 50, "season 1 has 50 tiers")
-- premium is cosmetics and convenience: coins back, never power; a few coins back, less than the pass costs
local coinsBack = 0
for tier, row in ipairs(pass.tiers) do
	for track = 1, 2 do
		local r = row[track]
		eq(r.kind ~= "tierskips" and r.kind ~= "premium", true, "no pack-only reward on the track, tier " .. tier)
		if r.kind == "coins" then
			coinsBack = coinsBack + r.amount
		end
		if r.kind == "item" then
			eq(cfg.allowedItems[r.id], true, "only gold and potions, tier " .. tier)
		end
	end
end
eq(coinsBack, 320, "320 Chaos Coins back on the premium track")
-- the paid track: cosmetics and coins only (owner rule: never gold, potions, experience or gear power)
for tier, row in ipairs(pass.tiers) do
	eq(P.PREMIUM_KINDS[row[2].kind], true, "premium tier " .. tier .. " is a cosmetic or coins, not " .. tostring(row[2].kind))
end
do -- the validator refuses gold and a potion on the premium track (they stay fine on the free track)
	for _, bad in ipairs({{kind = "item", id = 2152, count = 20}, {kind = "item", id = 7590, count = 25}}) do
		local copy = {}
		for k, v in pairs(cfg) do
			copy[k] = v
		end
		local tiers = {}
		for i, row in ipairs(pass.tiers) do
			tiers[i] = row
		end
		tiers[3] = {pass.tiers[3][1], bad}
		copy.passes = {[1] = {name = pass.name, premium = pass.premium, packs = pass.packs, tiers = tiers}}
		eq(#P.validate(copy) > 0, true, "premium item " .. bad.id .. " refused")
		tiers[3] = {bad, pass.tiers[3][2]}
		eq(#P.validate(copy), 0, "free item " .. bad.id .. " allowed")
	end
end
-- the season's own shaders and frame are on the premium track and in the cosmetics list
local seen = {}
for _, row in ipairs(pass.tiers) do
	seen[row[2].kind] = (seen[row[2].kind] or 0) + 1
end
eq(seen.shader, 2, "two outfit shaders on the premium track")
eq(seen.frame, 1, "one name plate frame on the premium track")
eq(seen.title >= 8, true, "titles on the premium track")
eq(coinsBack < pass.premium.price, true, "the coins back pay part of the next pass, not all of it")
-- the validator refuses power: an orb, an experience potion, a stamina item, an unknown kind
for _, bad in ipairs({
	{kind = "item", id = 29856, count = 1}, -- Orb of Upheaval
	{kind = "item", id = 28095, count = 1}, -- Double Experience Potion
	{kind = "item", id = 27990, count = 1}, -- Stamina Extension
	{kind = "xpboost", hours = 1},
	{kind = "tierskips", count = 5} -- on the track (packs only)
}) do
	local copy = {}
	for k, v in pairs(cfg) do
		copy[k] = v
	end
	local tiers = {}
	for i, row in ipairs(pass.tiers) do
		tiers[i] = row
	end
	tiers[7] = {bad, pass.tiers[7][2]}
	copy.passes = {[1] = {name = pass.name, premium = pass.premium, packs = pass.packs, tiers = tiers}}
	eq(#P.validate(copy) > 0, true, "refused: " .. tostring(bad.kind) .. " " .. tostring(bad.id))
end
-- packs: three, prices up, the two higher with the premium pass, coins and tier skips only in the top one
eq(#pass.packs, 3, "three packs")
eq(P.packIncludesPremium(pass.packs[1]), false, "Ember has no pass")
eq(P.packIncludesPremium(pass.packs[2]), true, "Blaze has the pass")
eq(P.hasPremium(pass, false, 3), true, "Inferno holds the pass (it holds Blaze)")
eq(P.packPrice(pass, 3, 1, 1000), 1600, "Ember + pass -> Inferno: both count")
for _, pk in ipairs(pass.packs) do
	for _, r in ipairs(pk.rewards) do
		if r.kind == "coins" or r.kind == "tierskips" then
			eq(pk.id, 3, "coins and tier skips only in the top pack")
		end
	end
end

-- ---------------------------------------------------------------- cosmetics claimed nowhere else
local function addLooks(set, t2, seen)
	if type(t2) ~= "table" or seen[t2] then
		return
	end
	seen[t2] = true
	for k, v in pairs(t2) do
		if (k == "male" or k == "female" or k == "looktype" or k == "lookfemale") and type(v) == "number" then
			set.looks[v] = true
		end
		addLooks(set, v, seen)
	end
end
-- achievements and the season track: never the same outfit or mount
local others = {looks = {}, mounts = {}}
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
addLooks(others, achievements, {})
addLooks(others, seasonCfg.track, {})
for _, a in ipairs(achievements.list or {}) do
	if type(a.reward) == "table" and type(a.reward.mount) == "table" then
		others.mounts[a.reward.mount.id] = true
	end
end
for _, m in ipairs(seasonCfg.track) do
	if m.reward.kind == "mount" then
		others.mounts[m.reward.id] = true
	end
end
local ok, classLooks = pcall(dofile, "data/scripts/chaos/class_looks_core.lua")
if ok and type(ChaosClassLooks) == "table" then
	addLooks(others, ChaosClassLooks.looks, {})
	addLooks(others, ChaosClassLooks.retired or {}, {})
end
local mine = {looks = {}, mounts = {}, portals = {}, titles = {}}
for _, c in ipairs(cfg.cosmetics) do
	local r = c.reward
	if r.kind == "outfit" then
		eq(others.looks[r.male] or others.looks[r.female], nil, "outfit " .. r.name .. " is given elsewhere")
		mine.looks[r.male], mine.looks[r.female] = r.name, r.name
	elseif r.kind == "mount" then
		eq(others.mounts[r.id], nil, "mount " .. r.name .. " is given elsewhere")
		mine.mounts[r.id] = r.name
	elseif r.kind == "portal" then
		mine.portals[r.key] = r.name
	elseif r.kind == "title" then
		mine.titles[r.title] = true
	end
end
-- the store: the season pass category is in shop_config.lua (the hunk), and the store sells none of the season looks.
-- The store's own exclusion list is the store's: a look it still sells is printed as a warning for its owner.
local shop = dofile("data/scripts/chaos/shop_config.lua")
local category
for _, cat in ipairs(shop.categories) do
	if cat.name == "Season Pass" then
		category = cat
	end
	for _, o in ipairs(cat.offers or {}) do
		if (o.kind == "outfit" or o.kind == "addons") and (mine.looks[o.looktype] or mine.looks[o.lookfemale or -1]) then
			print("WARNING: the store sells season pass outfit " .. tostring(mine.looks[o.looktype] or mine.looks[o.lookfemale]) ..
				" (" .. tostring(o.key or o.looktype) .. "): the store's exclusions should read seasonpass_config.lua cosmetics")
		elseif o.kind == "mount" and mine.mounts[o.id] then
			print("WARNING: the store sells season pass mount " .. mine.mounts[o.id] .. " (mount " .. o.id .. ")")
		end
	end
end
eq(category ~= nil, true, "shop_config.lua has the Season Pass category")
eq(#category.offers, 4, "premium pass and three packs in the store")
local unlocks = {}
for _, o in ipairs(category.offers) do
	eq(o.kind, "unlock", "store offers are unlocks")
	eq(o.noSale, true, "no sale on season pass offers")
	unlocks[o.unlock] = o.cost
end
eq(unlocks[pass.premium.unlock], pass.premium.price, "store price of the premium pass")
for _, pk in ipairs(pass.packs) do
	eq(unlocks[pk.unlock], pk.price, "store price of " .. pk.name)
end
-- Town Portal: every season style is a season pass reward and the other way round; none is sold
dofile("data/scripts/chaos/townportal_core.lua")
local tp = dofile("data/scripts/chaos/townportal_config.lua")
local seasonStyles = 0
for _, s in ipairs(tp.styles) do
	if s.route == "season" then
		seasonStyles = seasonStyles + 1
		eq(mine.portals[s.key] ~= nil, true, "season style " .. s.key .. " is a season pass reward")
		eq(unlocks["portal_" .. s.key], nil, "season style not sold")
	end
end
for key in pairs(mine.portals) do
	local s = ChaosTownPortalCore.styleByKey(tp, key)
	eq(s and s.route, "season", "season pass portal " .. key .. " is a season style")
end
eq(seasonStyles, 2, "two season styles")

-- ---------------------------------------------------------------- tiers
eq(P.tierCost(cfg, 1), 1000, "tier 1 cost")
eq(P.tierCost(cfg, 50), 2225, "tier 50 cost")
eq(P.xpForTier(cfg, 0), 0, "tier 0")
eq(P.xpForTier(cfg, 2), 2025, "tier 2 total")
eq(P.maxXp(cfg), 80625, "all 50 tiers")
local tier, into, need = P.tierOf(cfg, 0)
eq(tier, 0, "no xp")
eq(need, 1000, "first tier needs 1000")
tier, into, need = P.tierOf(cfg, 1999)
eq(tier, 1, "1999 xp: tier 1")
eq(into, 999, "999 into tier 2")
eq(need, 1025, "tier 2 costs 1025")
eq((P.tierOf(cfg, 2025)), 2, "exactly tier 2")
tier, into, need = P.tierOf(cfg, 10 ^ 9)
eq(tier, 50, "capped at 50")
eq(need, 0, "nothing more at the top")
eq(P.skip(cfg, 500, 1), 1500, "one skip keeps the progress inside the tier")
eq(P.skip(cfg, 2525, 1), 2525 + 1050, "from tier 2: the cost of tier 3")
eq((P.tierOf(cfg, P.skip(cfg, 500, 10))), 10, "ten skips: ten tiers")
eq(P.skip(cfg, P.maxXp(cfg) - 10, 10), P.maxXp(cfg), "skips stop at the top")

-- ---------------------------------------------------------------- experience and caps
eq(P.expForLevel(1), 0, "level 1")
eq(P.expForLevel(2), 100, "level 2")
eq(P.expForLevel(8), 4200, "level 8")
local span = P.expForLevel(101) - P.expForLevel(100)
eq(math.floor(P.expUnits(span / 10, 10, 100) + 0.5), 100, "a whole level at stage 10: 100 units")
eq(P.expUnits(100, 0, 100), 0, "stage 0")
eq(P.expUnits(-5, 1, 100), 0, "negative experience")
-- stage-only: the same monster gives the same units whatever bonus the character has (bonuses are not passed in)
eq(P.expUnits(1000, 13, 800), P.expUnits(1000, 13, 800), "deterministic")
local g = P.sourceGain(cfg, "exp", 50, 0)
eq(g, 50, "50 units -> 50 pass xp")
eq((P.sourceGain(cfg, "exp", 50, 280)), 20, "exp capped at 300 a day")
eq((P.sourceGain(cfg, "exp", 50, 300)), 0, "exp cap reached")
eq((P.sourceGain(cfg, "rift", 10, 0)), 120, "rift tier 10: 40 + 8 x 10")
eq((P.sourceGain(cfg, "bounty", nil, 590)), 10, "bounty cap")
eq((P.sourceGain(cfg, "boss", nil, 0)), 150, "boss")
eq((P.sourceGain(cfg, "nothing", nil, 0)), 0, "unknown source")
-- every source the engine file sends is configured
for _, s in ipairs({"exp", "boss", "bounty", "rift", "goblin", "invasion"}) do
	eq(cfg.sources[s] ~= nil, true, "source " .. s)
end

-- ---------------------------------------------------------------- periods
eq(P.dayKey(t(2026, 11, 4, 15)), 20261104, "day key")
eq(P.weekKey(t(2026, 11, 4, 15)), 20261102, "Wednesday -> Monday")
eq(P.weekKey(t(2026, 11, 2, 0, 1)), 20261102, "Monday itself")
eq(P.weekKey(t(2026, 11, 8, 23, 59)), 20261102, "Sunday belongs to the week before")
eq(P.weekKey(t(2027, 1, 1, 10)), 20261228, "across the new year")
eq(P.nextDay(t(2026, 11, 4, 15)), t(2026, 11, 5), "next midnight")
eq(P.nextWeek(t(2026, 11, 4, 15)), t(2026, 11, 9), "next Monday")
eq(P.nextWeek(t(2026, 11, 9, 0, 0)), t(2026, 11, 16), "on a Monday: the one after")

-- ---------------------------------------------------------------- challenges
local d1 = P.challenges(cfg, 1, "daily", 20261104)
eq(#d1, 3, "three dailies")
-- pinned: LuaJIT (the server) and Lua 5.3 must pick the same challenges
eq(d1[1].key .. " " .. d1[2].key .. " " .. d1[3].key, "d_exp30 d_bounty3 d_rift2", "pinned pick of 2026-11-04")
eq(#P.challenges(cfg, 1, "weekly", 20261102), 3, "three weeklies")
local d1b = P.challenges(cfg, 1, "daily", 20261104)
for i = 1, 3 do
	eq(d1[i].key, d1b[i].key, "same day, same challenges")
end
local differs = false
for day = 20261105, 20261120 do
	local d = P.challenges(cfg, 1, "daily", day)
	for i = 1, 3 do
		differs = differs or d[i].key ~= d1[i].key
	end
end
eq(differs, true, "the dailies rotate")
local keys = {}
for _, kind in ipairs({"daily", "weekly"}) do
	for _, slot in ipairs(cfg.challenges[kind]) do
		for _, c in ipairs(slot) do
			eq(keys[c.key], nil, "challenge key unique " .. c.key)
			keys[c.key] = true
			eq(#("done:" .. c.key) <= 40, true, "period key fits the column")
		end
	end
end
eq(P.statsOf("rift", 9).rift8, 1, "tier 9 rift counts for rift8")
eq(P.statsOf("rift", 7).rift8, nil, "tier 7 does not")
eq(P.statsOf("kill").kill, 1, "a kill")

-- ---------------------------------------------------------------- claims
local function view(tier2, premium, claimed, open)
	return {tier = tier2, premium = premium, claimed = claimed or {[0] = {}, [1] = {}}, open = open ~= false}
end
local r, why = P.claimCheck(pass, view(5, false), 3, P.FREE)
eq(r ~= nil, true, "free tier 3 at tier 5")
r, why = P.claimCheck(pass, view(5, false), 6, P.FREE)
eq(r, nil, "tier 6 not reached")
eq(why, "Reach tier 6 first.", "reason")
r, why = P.claimCheck(pass, view(5, false), 3, P.PREMIUM)
eq(why, "This reward is on the premium track.", "premium needed")
eq(P.claimCheck(pass, view(5, true), 3, P.PREMIUM) ~= nil, true, "premium claim")
r, why = P.claimCheck(pass, view(5, true, {[0] = {[3] = true}, [1] = {}}), 3, P.FREE)
eq(why, "Already claimed.", "no double claim")
r, why = P.claimCheck(pass, view(5, true, nil, false), 3, P.FREE)
eq(r, nil, "closed after the grace")
eq(P.claimCheck(pass, view(5, true), 0, P.FREE), nil, "tier 0")
eq(P.claimCheck(pass, view(5, true), 51, P.FREE), nil, "tier 51")
eq(P.claimCheck(pass, view(5, true), 1, 2), nil, "unknown track")
eq(#P.claimable(pass, view(5, false)), 5, "five free")
eq(#P.claimable(pass, view(5, true)), 10, "five free and five premium")
-- a late buyer: tier 12 reached with the free rewards claimed, then the premium track bought -> all 12 premium at once
do
	local free = {}
	for i = 1, 12 do
		free[i] = true
	end
	eq(#P.premiumBacklog(pass, view(12, false, {[0] = free, [1] = {}})), 0, "no premium, no backlog")
	local back = P.premiumBacklog(pass, view(12, true, {[0] = free, [1] = {[3] = true}}))
	eq(#back, 11, "eleven premium rewards waiting (tier 3 claimed)")
	eq(back[1].tier, 1, "from tier 1")
	eq(back[#back].tier, 12, "to the tier reached")
	for _, c in ipairs(back) do
		eq(c.track, P.PREMIUM, "backlog is premium only")
	end
	eq(#P.premiumBacklog(pass, view(12, true, {[0] = free, [1] = {}}, false)), 0, "closed pass: nothing")
end
eq(#P.claimable(pass, view(5, true, {[0] = {[1] = true, [2] = true}, [1] = {[1] = true}})), 7, "minus the claimed")
eq(P.claimedString({[1] = true, [3] = true}, 4), "1010", "claimed string")

-- ---------------------------------------------------------------- packs
eq(P.packPrice(pass, 1, 0, 0), 600, "Ember fresh")
eq(P.packPrice(pass, 3, 0, 0), 3200, "Inferno fresh")
eq(P.packPrice(pass, 3, 1, 0), 2600, "Ember -> Inferno pays the difference")
eq(P.packPrice(pass, 3, 2, 0), 1400, "Blaze -> Inferno")
eq(P.packPrice(pass, 2, 0, 1000), 800, "pass bought alone counts for Blaze")
eq(P.packPrice(pass, 2, 1, 1000), 200, "Ember + pass -> Blaze")
eq(P.packPrice(pass, 3, 2, 1000), 1400, "the pass counts once (Blaze already holds it)")
eq(P.packPrice(pass, 1, 0, 1000), 600, "the pass does not count for Ember (no pass in it)")
local price, reason = P.packPrice(pass, 1, 1, 0)
eq(price, nil, "owned")
eq(reason ~= nil, true, "owned reason")
eq((P.packPrice(pass, 1, 3, 0)), nil, "a lower pack than the one owned")
eq((P.packPrice(pass, 9, 0, 0)), nil, "unknown pack")
eq(P.hasPremium(pass, false, 1), false, "Ember: no premium")
eq(P.hasPremium(pass, false, 2), true, "Blaze: premium")
eq(P.hasPremium(pass, true, 0), true, "bought premium")
eq(P.ownedPack({1, 3}), 3, "highest pack of the rows")
eq(P.ownedPack({}), 0, "no pack")
local grants = P.packGrants(pass, 1, 3)
local coins, skips = 0, 0
for _, x in ipairs(grants) do
	coins = coins + (x.kind == "coins" and x.amount or 0)
	skips = skips + (x.kind == "tierskips" and x.count or 0)
end
eq(coins, 500, "Ember -> Inferno gives Inferno's coins once")
eq(skips, 10, "and its tier skips")
eq(#P.packGrants(pass, 3, 3), 0, "nothing when nothing new")
eq(#P.packGrants(pass, 0, 2), 0, "Ember and Blaze have no one-time grants")

-- ---------------------------------------------------------------- cosmetics of an account
local function count(list, kind)
	local n = 0
	for _, x in ipairs(list) do
		n = n + (x.kind == kind and 1 or 0)
	end
	return n
end
local ents = P.entitlements(pass, {[0] = {[15] = true}, [1] = {[15] = true, [25] = true, [50] = true}}, 0)
eq(count(ents, "title"), 1, "free 15 title")
eq(count(ents, "outfit"), 1, "premium 15 outfit")
eq(count(ents, "portal"), 1, "premium 25 portal")
eq(count(ents, "mount"), 1, "premium 50 mount")
local ents3 = P.entitlements(pass, {[0] = {}, [1] = {}}, 3)
eq(count(ents3, "outfit"), 3, "Inferno: the outfits of the three packs")
eq(count(ents3, "mount"), 3, "Inferno: three mounts")
eq(count(ents3, "coins"), 0, "coins are not cosmetics")
eq(#P.entitlements(pass, {[0] = {[2] = true}, [1] = {}}, 0), 0, "a potion is no cosmetic")

-- the season transmog set (transmog_config.lua source "season"): every pack owner owns it (Ember holds it)
eq(count(P.entitlements(pass, {[0] = {}, [1] = {}}, 1), "transmog"), 1, "Ember: the Arboreal transmog set")
eq(count(P.entitlements(pass, {[0] = {}, [1] = {}}, 3), "transmog"), 1, "Inferno holds it too")
eq(count(P.entitlements(pass, {[0] = {}, [1] = {}}, 0), "transmog"), 0, "no pack, no set")
local tm = dofile("data/scripts/chaos/transmog_config.lua")
local seasonSets = {}
for _, s in ipairs(tm.sets) do
	if s.source == "season" then
		seasonSets[s.key] = true
	end
end
for _, c in ipairs(cfg.cosmetics) do
	if c.reward.kind == "transmog" then
		eq(seasonSets[c.reward.key], true, "season pass transmog " .. c.reward.key .. " is a season set")
		seasonSets[c.reward.key] = nil
	end
end
eq(next(seasonSets), nil, "every season transmog set has a season pass source")
do
	local f = io.open("data/scripts/chaos/seasonpass.lua", "r")
	local text = f:read("*a")
	f:close()
	eq(text:find("function SP.ownsTransmog(player, key)", 1, true) ~= nil, true, "transmog.lua's season hook exists")
	-- coins can leave the balance from the website meanwhile: the spend must read ROW_COUNT, not trust db.query
	local spend = text:match("local function spendCoins%(account, amount%)(.-)\nend\n")
	eq((spend and spend:find("Shop.spend(account, amount)", 1, true) and spend:find("ROW_COUNT()", 1, true)) and true or false, true,
		"spendCoins counts only an UPDATE that changed the row")
end

print(string.format("seasonpass_test: OK (%d tiers, %d packs, %d cosmetics, %d XP to the top)", #pass.tiers, #pass.packs,
	#cfg.cosmetics, P.maxXp(cfg)))

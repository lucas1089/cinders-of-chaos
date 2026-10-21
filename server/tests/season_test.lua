-- Run from the server/ folder: luajit tests/season_test.lua (and lua5.3; CI runs both)
-- Pure logic of the seasons (season_core.lua) with the real season_config.lua: the date math, join eligibility,
-- the trade / move / party / mail isolation decisions, milestone detection and the reward track, the end-of-season
-- migration decisions and the season unique rule.
dofile("data/scripts/chaos/season_core.lua")
local S = ChaosSeason
local cfg = dofile("data/scripts/chaos/season_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function t(y, mo, d, hh, mi)
	return os.time({year = y, month = mo, day = d, hour = hh or 0, min = mi or 0, sec = 0})
end

-- a test season list, independent of the shipped dates
local seasons = {
	{id = 1, name = "Season of Ash", tag = "[S1]", start = 20261101, finish = 20270131, hour = 12,
		modifier = {name = "Ashfall", expMult = 1.1}},
	{id = 2, name = "Season of Frost", tag = "[S2]", start = 20270301, finish = 20270531, hour = 12}
}
local C = {seasons = seasons, join = cfg.join, track = cfg.track}

-- ---------------------------------------------------------------- shipped config sanity
eq(type(cfg.seasons), "table", "config seasons")
for _, s in ipairs(cfg.seasons) do
	local a, b = S.times(s)
	eq(a ~= nil and b ~= nil and b > a, true, "shipped season " .. s.id .. " has valid dates")
end
local keys = {}
for _, m in ipairs(cfg.track) do
	eq(keys[m.key], nil, "track keys unique: " .. m.key)
	keys[m.key] = true
	eq(m.stat == "level" or cfg.stats[m.stat] ~= nil, true, "track stat known: " .. m.key)
	local r = m.reward
	eq(r.kind == "title" or r.kind == "outfit" or r.kind == "addon" or r.kind == "mount", true, "reward kind " .. m.key)
	if r.kind == "outfit" or r.kind == "addon" then
		eq(type(r.male) == "number" and type(r.female) == "number", true, "outfit looks " .. m.key)
	end
end

-- ---------------------------------------------------------------- date math
eq(S.toUnix(20261101, 12), t(2026, 11, 1, 12), "YYYYMMDD at the hour")
eq(S.toUnix("2026-11-01", 0), t(2026, 11, 1, 0), "YYYY-MM-DD")
eq(S.toUnix(1790000000), 1790000000, "unix time passes through")
eq(S.toUnix(20261301, 0), nil, "month 13 invalid")
eq(S.toUnix(-5), nil, "negative invalid")
eq(S.toUnix("soon"), nil, "text invalid")
local s1 = seasons[1]
local a, b = S.times(s1)
eq(a, t(2026, 11, 1, 12), "start")
eq(b, t(2027, 1, 31, 12), "finish")
eq(S.status(s1, t(2026, 11, 1, 11, 59)), "upcoming", "a minute before the start")
eq(S.status(s1, t(2026, 11, 1, 12)), "active", "at the start")
eq(S.status(s1, t(2027, 1, 31, 11, 59)), "active", "a minute before the end")
eq(S.status(s1, t(2027, 1, 31, 12)), "ended", "at the end")
eq(S.status({id = 9, start = 20270101, finish = 20261201}, t(2026, 12, 15)), "ended", "finish before start never runs")
-- overrides (/season start|end)
local ov = {[1] = {start = t(2026, 10, 8, 9)}}
eq(S.status(s1, t(2026, 10, 9), ov), "active", "started early by /season start")
ov = {[1] = {finish = t(2026, 12, 1)}}
eq(S.status(s1, t(2026, 12, 2), ov), "ended", "ended early by /season end")
eq(S.active(seasons, t(2026, 12, 1)).id, 1, "active season")
eq(S.active(seasons, t(2027, 2, 15)), nil, "between seasons")
eq(S.upcoming(seasons, t(2027, 2, 15)).id, 2, "next season")
eq(S.upcoming(seasons, t(2026, 10, 1)).id, 1, "earliest upcoming")
eq(S.upcoming(seasons, t(2027, 6, 1)), nil, "nothing upcoming")
eq(S.formatDuration(93784), "1d 2h", "duration days")
eq(S.formatDuration(7500), "2h 5m", "duration hours")
eq(S.formatDuration(300), "5m", "duration minutes")
eq(S.formatDuration(20), "under a minute", "duration seconds")
eq(S.formatDuration(-1), "under a minute", "negative duration")
-- over a year end and a DST change: whole calendar days
eq(S.toUnix(20270101, 12) - S.toUnix(20261231, 12) >= 82800, true, "next day")

-- ---------------------------------------------------------------- realms
local during, after = t(2026, 12, 1), t(2027, 2, 15)
eq(S.realm(nil, during, seasons), 0, "standard character")
eq(S.realm({season = 1, migrated = 0}, during, seasons), 1, "season character")
eq(S.realm({season = 1, migrated = 12345}, during, seasons), 0, "migrated")
eq(S.realm({season = 1, migrated = 0}, after, seasons), 0, "season over: standard even before the migration")
eq(S.realm({season = 7, migrated = 0}, during, seasons), 0, "unknown season")
eq(S.tagRealm(nil, during, seasons), nil, "untagged item")
eq(S.tagRealm(0, during, seasons), 0, "standard tag")
eq(S.tagRealm(1, during, seasons), 1, "season tag")
eq(S.tagRealm(1, after, seasons), 0, "season tag after the season")

-- ---------------------------------------------------------------- join eligibility
local function join(info, when, o)
	return S.joinCheck(info, C, when or during, o)
end
local ok, why = join({level = 1, items = 0})
eq(ok and ok.id, 1, "fresh character joins")
ok, why = join({level = 7, items = 0})
eq(ok and ok.id, 1, "level 7 joins")
ok, why = join({level = 8, items = 0})
eq(ok, nil, "level 8 refused")
eq(why:find("level 7 or lower", 1, true) ~= nil, true, "level reason")
ok, why = join({level = 1, items = 3})
eq(ok, nil, "items in the depot refused")
eq(why:find("depot", 1, true) ~= nil, true, "depot reason")
ok, why = join({level = 1, items = 0, party = true})
eq(ok, nil, "in a party refused")
ok, why = join({level = 1, items = 0, house = true})
eq(ok, nil, "house owner refused")
ok, why = join({level = 1, items = 0, row = {season = 1, migrated = 0}})
eq(ok, nil, "already joined")
eq(why:find("already a", 1, true) ~= nil, true, "already reason")
ok, why = join({level = 1, items = 0, row = {season = 1, migrated = 99}})
eq(ok, nil, "a migrated character cannot join again")
ok, why = join({level = 1, items = 0}, t(2026, 10, 1))
eq(ok, nil, "before the season")
eq(why:find("starts in", 1, true) ~= nil, true, "upcoming reason")
ok, why = join({level = 1, items = 0}, t(2027, 7, 1))
eq(why, "No season is running.", "no season")
ok = join({level = 1, items = 0}, t(2026, 10, 1), {[1] = {start = t(2026, 9, 30)}})
eq(ok and ok.id, 1, "joins after /season start")
ok = join({level = 1, items = 0}, t(2027, 3, 10))
eq(ok and ok.id, 2, "second season")

-- the stored items are counted only when joinCheck reads them (counting opens the depots, which the engine then
-- rewrites at every save): the same verdict with items left at 0 whenever joinNeedsItems says no
eq(S.joinNeedsItems({level = 1}, C), true, "fresh character: items needed")
eq(S.joinNeedsItems({level = 7}, C), true, "level 7: items needed")
eq(S.joinNeedsItems({level = 8}, C), false, "level 8: not needed")
eq(S.joinNeedsItems({level = 500}, C), false, "high level: not needed")
eq(S.joinNeedsItems({level = 1, row = {season = 1, migrated = 0}}, C), false, "season row: not needed")
eq(S.joinNeedsItems({level = 1}, {join = {maxLevel = 7, requireEmptyDepot = false}}), false, "rule off: not needed")
for _, when in ipairs({during, after, t(2026, 10, 1), t(2027, 3, 10)}) do
	for _, level in ipairs({1, 7, 8, 300}) do
		for _, row in ipairs({false, {season = 1, migrated = 0}, {season = 1, migrated = 99}}) do
			for _, items in ipairs({0, 5}) do
				for _, party in ipairs({false, true}) do
					local full = {level = level, row = row or nil, items = items, party = party}
					local lazy = {level = level, row = row or nil, items = 0, party = party}
					if S.joinNeedsItems(lazy, C) then
						lazy.items = items
					end
					local a, ra = join(full, when)
					local b, rb = join(lazy, when)
					eq(a and a.id, b and b.id, "lazy items: same season")
					eq(ra, rb, "lazy items: same reason")
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- isolation decisions
eq(S.tradeAllowed(1, 1), true, "same season trades")
eq(S.tradeAllowed(0, 0), true, "standard trades")
eq(S.tradeAllowed(1, 0), false, "season -> standard refused")
eq(S.tradeAllowed(0, 1), false, "standard -> season refused")
eq(S.tradeAllowed(1, 2), false, "different seasons refused")
eq(S.tradeAllowed(1, 0, false, true), true, "staff exempt")
eq(S.partyAllowed(1, 0), false, "party across realms refused")
eq(S.partyAllowed(1, 1), true, "party same season")
local okm, key = S.moveCheck({mover = 1, tags = {}})
eq(okm, true, "untagged item")
okm, key = S.moveCheck({mover = 1, tags = {1, 1}})
eq(okm, true, "own realm tags")
okm, key = S.moveCheck({mover = 1, tags = {0}})
eq(okm, false, "season character takes a standard drop")
eq(key, "move", "move reason")
okm, key = S.moveCheck({mover = 0, tags = {0, 1}})
eq(okm, false, "standard loots inside a season corpse")
okm, key = S.moveCheck({mover = 1, mail = 0})
eq(okm, false, "mail to a standard character")
eq(key, "mail", "mail reason")
okm = S.moveCheck({mover = 1, mail = 1})
eq(okm, true, "mail within the season")
okm, key = S.moveCheck({mover = 1, houseFrom = 0})
eq(okm, false, "taking from a standard house")
eq(key, "house", "house reason")
okm, key = S.moveCheck({mover = 0, houseTo = 1})
eq(okm, false, "dropping into a season house")
okm = S.moveCheck({mover = 0, houseTo = 0, houseFrom = 0, tags = {0}})
eq(okm, true, "standard in a standard house")
okm = S.moveCheck({mover = 1, exempt = true, tags = {0}, mail = 0})
eq(okm, true, "staff never blocked")
eq(S.mailReceiver("Kael Vorn\nhello"), "Kael Vorn", "receiver first line")
eq(S.mailReceiver("  Kael Vorn  \r\nTown"), "Kael Vorn", "trimmed, CRLF")
eq(S.mailReceiver(""), nil, "empty label")
eq(S.mailReceiver(nil), nil, "no text")

-- ---------------------------------------------------------------- milestones and the reward track
eq(S.mergeStat("add", 3, 1), 4, "add")
eq(S.mergeStat("add", nil, 5), 5, "add from nothing")
eq(S.mergeStat("max", 7, 5), 7, "max keeps")
eq(S.mergeStat("max", 7, 9), 9, "max raises")
eq(S.mergeStat("count", 2, 1234567), 3, "count ignores the value")
local track = {
	{key = "l100", stat = "level", value = 100, name = "L100", reward = {kind = "title", title = "Ashborn"}},
	{key = "l300", stat = "level", value = 300, name = "L300", reward = {kind = "outfit", male = 667, female = 666, name = "DH"}},
	{key = "b25", stat = "bounty", value = 25, name = "B25", reward = {kind = "mount", id = 105, name = "Doom Skull"}},
	{key = "r10", stat = "rift", value = 10, name = "R10", requires = "ChaosRift", reward = {kind = "title", title = "Rw"}}
}
local function keysOf(list)
	local out = {}
	for _, m in ipairs(list) do
		out[#out + 1] = m.key
	end
	return table.concat(out, ",")
end
local noRift = function(name) return name ~= "ChaosRift" end
local withRift = function() return true end
eq(keysOf(S.milestonesDue(track, {level = 99}, {}, noRift)), "", "level 99: nothing")
eq(keysOf(S.milestonesDue(track, {level = 100}, {}, noRift)), "l100", "level 100")
eq(keysOf(S.milestonesDue(track, {level = 350, bounty = 25}, {}, noRift)), "l100,l300,b25", "several at once")
eq(keysOf(S.milestonesDue(track, {level = 350, bounty = 25}, {l100 = true, b25 = true}, noRift)), "l300", "already reached skipped")
eq(keysOf(S.milestonesDue(track, {level = 1, rift = 12}, {}, noRift)), "", "rift milestone hidden without rifts")
eq(keysOf(S.milestonesDue(track, {level = 1, rift = 12}, {}, withRift)), "r10", "rift milestone with rifts")
local view = S.trackView(track, {level = 150, bounty = 30}, {l100 = {by = "Kael", at = 5}}, noRift)
eq(#view, 3, "view hides the rift milestone without rifts")
eq(view[1].unlocked, true, "unlocked")
eq(view[1].by, "Kael", "unlocked by")
eq(view[1].reward, "Title: Ashborn", "title reward text")
eq(view[2].progress, 150, "progress")
eq(view[2].unlocked, false, "not unlocked")
eq(view[3].progress, 25, "progress capped at the goal")
eq(view[3].reward, "Doom Skull", "named reward text")
local look, addons = S.rewardLook(track[2].reward, true)
eq(look, 666, "female look")
eq(addons, 0, "outfit without addons")
look, addons = S.rewardLook({kind = "addon", male = 667, female = 666, addons = 3}, false)
eq(look, 667, "male look")
eq(addons, 3, "addons")
eq(S.rewardLook(track[3].reward, false), nil, "mount is not an outfit")
-- the shipped track: level 1000 reaches every level milestone
local due = S.milestonesDue(cfg.track, {level = 1000}, {}, noRift)
eq(#due >= 4, true, "shipped level milestones")

-- ---------------------------------------------------------------- end of season (migration)
eq(S.migrationDue({season = 1, migrated = 0}, during, seasons), false, "not during the season")
eq(S.migrationDue({season = 1, migrated = 0}, after, seasons), true, "after the end")
eq(S.migrationDue({season = 1, migrated = 777}, after, seasons), false, "never twice (idempotent)")
eq(S.migrationDue({season = 1, migrated = 0}, t(2026, 12, 2), {[1] = {finish = t(2026, 12, 1)}}), true,
	"after /season end")
eq(S.migrationDue({season = 42, migrated = 0}, during, seasons), true, "season removed from the config")
eq(S.migrationDue(nil, after, seasons), false, "standard character")
local plan = S.migrationPlan({{season = 1, migrated = 0}, {season = 1, migrated = 5}, {season = 2, migrated = 0}},
	t(2027, 3, 10), seasons)
eq(#plan, 1, "only the ended season's unmigrated characters")
eq(plan[1].season, 1, "plan row")
plan = S.migrationPlan(plan, t(2027, 3, 10), seasons)
eq(#plan, 1, "plan is pure (the DB update marks the row)")
plan[1].migrated = 99
eq(#S.migrationPlan(plan, t(2027, 3, 10), seasons), 0, "a migrated row is not planned again")

-- ---------------------------------------------------------------- season uniques
eq(S.uniqueAllowed(nil, 0, during, seasons), true, "normal unique")
eq(S.uniqueAllowed(1, 1, during, seasons), true, "season unique for a season character")
eq(S.uniqueAllowed(1, 0, during, seasons), false, "season unique not for a standard character")
eq(S.uniqueAllowed(1, nil, during, seasons), false, "season unique not without an owner during the season")
eq(S.uniqueAllowed(1, 0, t(2026, 10, 1), seasons), false, "before the season: for nobody")
eq(S.uniqueAllowed(1, 1, t(2026, 10, 1), seasons), false, "before the season: for nobody (season realm)")
eq(S.uniqueAllowed(1, 0, after, seasons), true, "after the season: for everyone")
eq(S.uniqueAllowed(1, nil, after, seasons), true, "after the season: also without an owner")
eq(S.uniqueAllowed(true, 1, during, seasons), true, "season = true means season 1")
eq(S.uniqueAllowed(2, 1, t(2027, 3, 10), seasons), false, "season 1 character during season 2: no season 2 unique")

-- ---------------------------------------------------------------- store coins (account-wide): every real offer
-- the rule: cosmetics and account services yes; items, boosts, gameplay unlocks and anything holding them no
local rules = cfg.store
eq(type(rules), "table", "season_config.lua store rules")
dofile("data/scripts/chaos/shop_core.lua")
local K = ChaosShopCore
local shop = dofile("data/scripts/chaos/shop_config.lua")
local byKey, offers = {}, {}
for _, cat in ipairs(shop.categories) do
	for _, o in ipairs(cat.offers) do
		o.key = K.offerKey(o)
		o.category = cat.name
		byKey[o.key] = byKey[o.key] or o
		offers[#offers + 1] = o
	end
end
for _, o in ipairs(offers) do
	if o.kind == "bundle" then
		o.resolved = {}
		for _, p in ipairs(o.parts) do
			o.resolved[#o.resolved + 1] = type(p) == "string" and byKey[p] or p
			eq(type(o.resolved[#o.resolved]), "table", "bundle part resolves: " .. tostring(p))
		end
	end
end
-- whole categories, decided once (a new category must be added here: the test fails on an unknown one)
local CATEGORY = {
	["Outfits"] = true, ["Outfit Addons"] = true, ["Mounts"] = true, ["Wings"] = true, ["Auras"] = true,
	["Outfit Shaders"] = true, ["Name Plates"] = true, ["Portal Styles"] = true, ["Bundles"] = true, -- "Classes" no longer sold (2026-10-15)
	["Chaos Pact"] = true, ["Storage & Slots"] = true, ["Season Pass"] = true, ["Premium Time"] = true,
	["Spell Effects"] = true, ["Kill Effects"] = true, ["Loot Labels"] = true, ["Chat Colours"] = true, ["Appearances"] = true,
	["Footprints"] = true, ["Outlines"] = true, -- cosmetics.lua: looks only
	["Hideout Decorations"] = true, -- hideout_store.lua: looks only
	["Depot Tabs"] = true, -- depot_config.lua: account room (service pactExtra, as Storage & Slots), while sold
	["Themed Sets"] = true, -- chaos_theme_art.lua appearance sets (weekly rotation only): looks only
	-- the Chaos shaders are in Outfit Shaders since 2026-10-21; Supplies is Potions, Boosts is XP Boosts and Blessings
	["Starter"] = false, ["Crafting"] = false, ["Potions"] = false, ["XP Boosts"] = false, ["Blessings"] = false,
	["World Buffs"] = false,
	["Convenience"] = false, ["Training"] = false, ["Pets"] = false, ["Services"] = "mixed",
	["Runes"] = false -- the rune packs: items
}
local SERVICES = {["service:nameToken"] = true, ["service:sexChange"] = true, ["service:vocationToken"] = false,
	["service:skullRemover"] = false, ["service:passiveReset"] = false}
local seen = {}
for _, o in ipairs(offers) do
	local want = CATEGORY[o.category]
	eq(want ~= nil, true, "store category decided for seasons: " .. o.category)
	if want == "mixed" then
		want = SERVICES[o.key]
		eq(want ~= nil, true, "service decided for seasons: " .. o.key)
	end
	eq(S.storeRefusal(o, rules) == nil, want, "season character and " .. o.key .. " (" .. o.category .. ")")
	seen[o.category] = true
	-- nothing that holds an item ever reaches a season character
	for _, p in ipairs(o.resolved or {o}) do
		if p.kind == "item" then
			eq(S.storeRefusal(o, rules) ~= nil, true, "an item offer is refused: " .. o.key)
		end
	end
end
for name, want in pairs(CATEGORY) do
	-- Season Pass: built from seasonpass_config.lua, may be empty between passes; Depot Tabs: only while the depot
	-- takes items (shop_config.lua, stash_config.lua depot.withdrawOnly)
	if name ~= "Season Pass" and name ~= "Depot Tabs" then
		eq(seen[name], true, "category still sold: " .. name)
	end
end
-- the starter packs and the bundles: the part that is refused
eq(S.storeRefusal(byKey["starter:novice"], rules).kind, "item", "novice pack: its potions")
eq(S.storeRefusal(byKey["starter:champion"], rules).kind ~= nil, true, "champion pack refused")
eq(S.storeRefusal(byKey["bundle:infernal"], rules), nil, "cosmetic bundle allowed")
eq(S.storeRefusal({kind = "bundle", parts = {"aura:1"}}, rules) ~= nil, true, "an unresolved bundle part: refused")
eq(S.storeRefusal({kind = "bundle", resolved = {}}, rules) ~= nil, true, "an empty bundle: refused")
-- default deny and the flags
eq(S.storeRefusal({kind = "newthing"}, rules) ~= nil, true, "an unknown kind is refused until decided")
eq(S.storeRefusal({kind = "unlock", unlock = "petAnything"}, rules) ~= nil, true, "pets refused")
eq(S.storeRefusal({kind = "unlock", unlock = "autoSeller"}, rules) ~= nil, true, "Auto Seller refused")
eq(S.storeRefusal({kind = "unlock", unlock = "transmog_arboreal"}, rules), nil, "transmog sets are looks")
eq(S.storeRefusal({kind = "unlock", unlock = "cosmetic_kill_soulspark"}, rules), nil, "cosmetics are looks")
eq(S.storeRefusal({kind = "unlock", unlock = "seasonPassPremium"}, rules), nil, "the premium pass (account-wide)")
eq(S.storeRefusal({kind = "unlock", unlock = ""}, rules) ~= nil, true, "an empty unlock key")
eq(S.storeRefusal({kind = "aura", id = 1, seasonBlocked = true}, rules) ~= nil, true, "seasonBlocked still refuses")
eq(S.storeRefusal({kind = "service", service = "worldBuff", buff = "loot"}, rules) ~= nil, true, "world buffs refused")
eq(S.storeRefusal({kind = "service", service = "pouch", pouch = "loot"}, rules) ~= nil, true, "pouches refused")
eq(S.storeRefusal({kind = "service", service = "pact"}, rules), nil, "the Chaos Pact (account comfort)")
-- texts
eq(S.storeText(0, byKey["item:7590x100"], rules), nil, "standard characters: no text")
eq(S.storeText(1, byKey["wings:1"], rules), nil, "season character, cosmetic: no text")
local text = S.storeText(1, byKey["item:7590x100"], rules)
eq(text ~= nil and text:find("100 Great Mana Potions", 1, true) ~= nil, true, "refusal names the offer: " .. tostring(text))
text = S.storeText(1, byKey["item:7590x100"], rules, true, "Ashling")
eq(text ~= nil and text:find("Ashling is a season character", 1, true) == 1, true, "gift refusal names the receiver")

-- season pass claims: items only by standard characters while the season runs; coins and looks by everybody
eq(S.passClaimAllowed({kind = "item", id = 2152, count = 5}, 0, cfg.passItems), true, "standard character: items")
eq(S.passClaimAllowed({kind = "item", id = 2152, count = 5}, 1, cfg.passItems), false, "season character: no items")
eq(S.passClaimAllowed({kind = "coins", amount = 50}, 1, cfg.passItems), true, "season character: coins (account)")
eq(S.passClaimAllowed({kind = "outfit", male = 974}, 1, cfg.passItems), true, "season character: looks")
eq(S.passClaimAllowed({kind = "item"}, 1, {seasonCharacters = true}), true, "the rule is configurable")
local passCfg = dofile("data/scripts/chaos/seasonpass_config.lua")
local itemTiers = 0
for _, p in pairs(passCfg.passes) do
	for _, tier in ipairs(p.tiers or {}) do
		for _, r in ipairs(tier) do
			if r.kind == "item" then
				itemTiers = itemTiers + 1
				eq(S.passClaimAllowed(r, 1, cfg.passItems), false, "pass item reward kept from season characters")
				eq(S.passClaimAllowed(r, 0, cfg.passItems), true, "pass item reward for standard characters")
			else
				eq(S.passClaimAllowed(r, 1, cfg.passItems), true, "pass " .. tostring(r.kind) .. " reward for season characters")
			end
		end
	end
end
eq(itemTiers > 0, true, "the shipped pass has item rewards to keep out")

-- the season markets: gold only
eq(S.marketCurrencyAllowed(0, "coins", cfg.market), true, "standard market: coins")
eq(S.marketCurrencyAllowed(1, "coins", cfg.market), false, "season market: no coins")
eq(S.marketCurrencyAllowed(1, "gold", cfg.market), true, "season market: gold")
eq(S.marketCurrencyAllowed(1, "coins", {coins = true}), true, "configurable")

-- ---------------------------------------------------------------- look text
eq(S.lookLine({season = 1, migrated = 0}, during, seasons, nil, "She"), "She is a Season of Ash character [S1].", "look")
eq(S.lookLine({season = 1, migrated = 0}, during, seasons, nil, "You"), "You are a Season of Ash character [S1].", "own look")
eq(S.lookLine({season = 1, migrated = 5}, after, seasons, nil, "He"), "He is a veteran of Season of Ash.", "veteran")
eq(S.lookLine(nil, during, seasons), nil, "standard: no line")

-- ---------------------------------------------------------------- a join chosen at character creation (website)
local req = {season = 1, mode = "hcssf"}
local js, jwhy = join({level = 1, items = 0})
eq(S.requestOutcome(req, js, jwhy), "join", "request: the running season, a fresh character joins at its first login")
js, jwhy = join({level = 1, items = 0}, after)
local outcome, text = S.requestOutcome(req, js, jwhy)
eq(outcome, "drop", "request: the season ended before the first login")
eq(text:find("could not be joined: Season of Frost has not started yet", 1, true) ~= nil, true, "request: told why")
js, jwhy = join({level = 1, items = 3})
outcome, text = S.requestOutcome(req, js, jwhy)
eq(outcome, "drop", "request: depot not empty (starter depot boxes on)")
eq(S.requestOutcome({season = 9, mode = "standard"}, seasons[1], nil), "drop", "request: another season than the running one")
eq(S.requestOutcome(nil, seasons[1], nil), nil, "no request")

print("season_test: OK")

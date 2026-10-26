-- Run from the server/ folder: luajit tests/retention_loot_test.lua (and lua5.3; mock engine API, CI runs it)
-- O260: an early power spike (the first unique at the 150th kill), pity (a due kill raises one gear drop), the server drop
-- feed (kinds, client option, rate limits, the line) and the personal drop records. The rules of retention_loot_core.lua
-- with the real retention_loot_config.lua, then retention_loot.lua on a mocked engine.
local checks, failures = 0, 0
local function check(v, m)
	checks = checks + 1
	if not v then
		failures = failures + 1
		print("FAIL " .. tostring(m))
	end
end
local function eq(a, b, m) check(a == b, tostring(m) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local C = dofile("data/scripts/chaos/retention_loot_core.lua")
local cfg = dofile("data/scripts/chaos/retention_loot_config.lua")
dofile("data/lib/chaos_rarity.lua")

-- ---------------------------------------------------------------- the numbers
eq(cfg.firstUnique.kills, 150, "the 150th kill")
eq(cfg.firstUnique.maxLevel, 60, "up to level 60")
eq(cfg.firstUnique.storage, 7103010, "first unique storage")
eq(cfg.pity.storage, 7103011, "pity storage")
eq(cfg.pity.threshold, 400, "pity at 400")
eq(cfg.feed.perCharSeconds, 60, "one line per character per minute")
check(cfg.feed.maxPerMinute > 0, "a server-wide limit")
check(cfg.feed.channelId ~= 3 and cfg.feed.channelId > 10, "a channel id clear of the stock ones")

-- ---------------------------------------------------------------- 1. the first unique
eq(C.countRead(-1), 0, "unset counts 0")
eq(C.countRead(nil), 0, "nil counts 0")
eq(C.countRead(12.7), 12, "whole kills")
do
	local raw, gave, at = -1, false, 0
	for kill = 1, 200 do
		local action, new = C.firstUniqueStep(cfg, raw, 30, false)
		if action == "give" and not gave then
			gave, at = true, kill
		end
		if action ~= "skip" then
			raw = new
		end
	end
	eq(at, 150, "given on the 150th kill")
	eq(raw, cfg.firstUnique.doneValue, "the done value is stored")
	local a = C.firstUniqueStep(cfg, raw, 30, false)
	eq(a, "skip", "never again")
end
eq((C.firstUniqueStep(cfg, 10, 61, false)), "skip", "above level 60: nothing")
eq((C.firstUniqueStep(cfg, 10, 60, false)), "count", "level 60 still counts")
eq((C.firstUniqueStep(cfg, 10, 30, true)), "skip", "a tester gets nothing")
do
	local off = {enabled = false, firstUnique = cfg.firstUnique}
	eq((C.firstUniqueStep(off, 10, 30, false)), "skip", "off")
	local off2 = {firstUnique = {enabled = false}}
	eq((C.firstUniqueStep(off2, 10, 30, false)), "skip", "first unique off")
end
eq(select(2, C.firstUniqueStep(cfg, 148, 30, false)), 149, "149 kills stored")
eq(select(2, C.firstUniqueStep(cfg, 149, 30, false)), cfg.firstUnique.doneValue, "the 150th stores done")

-- candidates: every class and ascension has some
local classes = {"Warrior", "Ranger", "Mystic", "Thief", "Necromancer", "Monk", "Templar", "Juggernaut", "Berserker", "Deadeye",
	"Beastmaster", "Elementalist", "Illusionist", "Ninja", "Samurai", "Lich", "Bone Lord", "Shadowfist", "Iron Sage",
	"Inquisitor", "Sentinel", "Brand New Class"}
for _, name in ipairs(classes) do
	check(#C.candidatesOf(cfg, name) >= 1, "candidates for " .. name)
end
eq(C.candidatesOf(cfg, "Berserker")[1], cfg.firstUnique.byClass.Warrior[1], "an ascension uses its line")
eq(C.candidatesOf(cfg, "Brand New Class")[1], cfg.firstUnique.default[1], "an unknown class: the default")
-- every candidate is a real unique of the repo (data/lib/chaos_unique_items.lua) at level 10-40
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE, ITEM_ATTRIBUTE_ARMOR = 1, 2, 3, 4
ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ARTICLE, ITEM_ATTRIBUTE_DESCRIPTION = 5, 6, 7, 8
ITEM_ATTRIBUTE_SHOOTRANGE, ITEM_ATTRIBUTE_ATTACK_SPEED = 9, 10
dofile("data/lib/chaos_unique_items.lua")
local seen = 0
for cls, list in pairs(cfg.firstUnique.byClass) do
	for _, name in ipairs(list) do
		local e = ChaosUniqueByName[name]
		check(e ~= nil, "unique exists: " .. name .. " (" .. cls .. ")")
		if e then
			seen = seen + 1
			check(e.level >= 1 and e.level <= 60, "a leveling unique: " .. name .. " level " .. tostring(e.level))
		end
	end
end
check(seen >= 10, "candidates checked")
check(ChaosUniqueByName[cfg.firstUnique.default[1]] ~= nil, "the default exists")
do
	local by = {A = {name = "A", id = 1, level = 10}, B = {name = "B", id = 2, level = 30}, C = {name = "C", id = 3, level = 50}}
	local c2 = {firstUnique = {byClass = {X = {"A", "B", "C", "Missing"}}, default = {}}}
	eq(C.pickUnique(c2, "X", 35, by).name, "B", "the highest requirement the level meets")
	eq(C.pickUnique(c2, "X", 5, by).name, "A", "none met: the lowest")
	eq(C.pickUnique(c2, "X", 99, by).name, "C", "all met: the highest")
	eq(C.pickUnique(c2, "Y", 35, by), nil, "no candidates: nil")
end

-- ---------------------------------------------------------------- 2. pity
eq(C.pityRead(-1), 0, "pity unset")
eq(C.pityRead(399), 399, "pity read")
check(not C.pityDue(cfg, 399), "399 is not due")
check(C.pityDue(cfg, 400), "400 is due")
check(C.pityDue(cfg, 900), "above is due")
check(not C.pityDue({enabled = false, pity = cfg.pity}, 500), "off")
eq(C.pityBoost(cfg, 2), nil, "Uncommon stays")
eq(C.pityBoost(cfg, 3), 4, "Magic -> Rare")
eq(C.pityBoost(cfg, 4), 5, "Rare -> Legendary")
eq(C.pityBoost(cfg, 5), nil, "Legendary stays (max)")
eq(C.pityBoost(cfg, 6), nil, "Divine stays")
eq(C.pityFinish(cfg, 10, true, false, 2), 11, "a hunting kill without a Rare counts")
eq(C.pityFinish(cfg, 10, true, false, 4), 0, "a Rare resets")
eq(C.pityFinish(cfg, 10, true, false, 7), 0, "a unique resets")
eq(C.pityFinish(cfg, 10, true, false, 3), 11, "a Magic does not")
eq(C.pityFinish(cfg, 400, true, true, 4), 0, "the boosted kill resets")
eq(C.pityFinish(cfg, 10, false, false, 0), 10, "a boss or rift kill leaves it")
eq(C.pityFinish(cfg, 10, false, false, 7), 10, "even with a unique")
do -- a long dry streak: the pity ends it at exactly the threshold
	local n, kills = 0, 0
	repeat
		n, kills = C.pityFinish(cfg, n, true, false, 1), kills + 1
	until C.pityDue(cfg, n)
	eq(kills, 400, "400 dry kills")
end

-- ---------------------------------------------------------------- 3. the drop feed
eq(C.feedKind(cfg, 4, false), nil, "Rare does not post")
eq(C.feedKind(cfg, 5, false), "legendary", "Legendary posts")
eq(C.feedKind(cfg, 6, false), "divine", "Divine posts")
eq(C.feedKind(cfg, 7, true), "unique", "a unique posts")
eq(C.feedKind(cfg, 0, true), "unique", "a unique by marker")
eq(C.feedKind(cfg, 1, false), nil, "Common does not")
check(C.feedRank(cfg, "unique") > C.feedRank(cfg, "legendary"), "unique above legendary")
eq(C.feedRank(cfg, "nothing"), 0, "unknown kind")
eq(C.optionRank(cfg, "off"), 0, "off")
eq(C.optionRank(cfg, nil), 0, "no option is off")
eq(C.optionRank(cfg, "bogus"), 0, "unknown option is off")
check(C.shown(cfg, "legendary", "legendary"), "legendary option shows legendary")
check(C.shown(cfg, "unique", "legendary"), "legendary option shows unique")
check(not C.shown(cfg, "legendary", "unique"), "unique option hides legendary")
check(C.shown(cfg, "unique", "unique"), "unique option shows unique")
check(C.shown(cfg, "divine", "unique"), "unique option shows divine")
check(not C.shown(cfg, "unique", "off"), "off hides all")
do
	local st = C.feedNew()
	check(C.feedAllow(st, cfg, 1, 1000), "first line passes")
	check(not C.feedAllow(st, cfg, 1, 1030), "same character within 60 s: dropped")
	check(C.feedAllow(st, cfg, 1, 1061), "after 60 s again")
	eq(st.dropped, 1, "one dropped")
	-- the server-wide limit
	local st2 = C.feedNew()
	local passed = 0
	for g = 1, 30 do
		if C.feedAllow(st2, cfg, g, 5000) then
			passed = passed + 1
		end
	end
	eq(passed, cfg.feed.maxPerMinute, "maxPerMinute lines in one minute")
	check(C.feedAllow(st2, cfg, 99, 5060), "the next minute opens again")
	-- the table stays small
	local st3 = C.feedNew()
	for g = 1, 1000 do
		C.feedAllow(st3, cfg, g, 100000 + g * 61)
	end
	local n = 0
	for _ in pairs(st3.chars) do
		n = n + 1
	end
	check(n < 200, "old characters are forgotten (" .. n .. ")")
end
eq(C.cleanName("Ann[1]{2}\n"), "Ann12", "brackets and controls out")
eq(#C.cleanName(string.rep("x", 90)), 30, "cut to 30")
eq(C.feedLine(cfg, "Ann", 42, "[Blade]{512}"), "Ann (Lv 42) found [Blade]{512}!", "the English line")
eq(C.feedLine(cfg, "Ann", 42, "[Lamina]{512}", "%s (Nv %d) achou %s!"), "Ann (Nv 42) achou [Lamina]{512}!", "a translated pattern")
eq(C.feedLine(cfg, "A]{x", 7, "L"), "Ax (Lv 7) found L!", "a hostile name cannot end the link")

-- ---------------------------------------------------------------- 4. the personal drop boards
do
	local r, v = C.dropBest({{rank = 3, value = 100}, {rank = 5, value = 50}, {rank = 4, value = 900}})
	eq(r, 5, "best rank")
	eq(v, 900, "best value")
	r, v = C.dropBest({})
	eq(r + v, 0, "empty kill")
	r, v = C.dropBest(nil)
	eq(r + v, 0, "nil kill")
end

-- ---------------------------------------------------------------- the engine file on a mocked engine
Chaos = {
	t = function(_, key, ...)
		if select("#", ...) > 0 then
			return string.format(key, ...)
		end
		return key
	end,
	isTester = function(p) return p.tester == true end
}
Chaos.recordsConfig = dofile("data/scripts/chaos/records_config.lua")
dofile("data/scripts/chaos/records_core.lua")
local players = {}
Game = {getPlayers = function() return players end}
local nextId = 100
local function newPlayer(name, level, voc)
	nextId = nextId + 1
	local p = {name = name, level = level, id = nextId, store = {}, texts = {}, channel = {}, voc = voc or "Warrior", access = false}
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:getId() return self.id end
	function p:getGuid() return self.id + 5000 end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:setStorageValue(k, v) self.store[k] = v end
	function p:getVocation() local v = self.voc return {getName = function() return v end} end
	function p:getGroup() local a = self.access return {getAccess = function() return a end} end
	function p:sendTextMessage(t, text) self.texts[#self.texts + 1] = {t, text} end
	function p:sendChannelMessage(a, text, t, id) self.channel[#self.channel + 1] = {text, id} end
	return p
end
CreatureEvent = function() return {type = function() end, register = function() end} end
ChaosCrafting = {
	isUnique = function(i) return i.unique == true end,
	rarityOf = function(i) return i.rarity or 0 end
}
ChaosItemPrices = {sellPrice = function(i) return i.price or 0 end}
local submitted, bests = {}, {}
ChaosRecords = {
	personalBests = function(guid) bests[guid] = bests[guid] or {} return bests[guid] end,
	submit = function(run) submitted[#submitted + 1] = run return true end
}
local linkArgs
ChaosItemLink = {linkFor = function(owner, item)
	linkArgs = item
	return "[" .. item.name .. "]{9" .. item.id .. "}", item.name
end}
local discord = {}
ChaosDiscord = {drop = function(...) discord[#discord + 1] = {...} end}
MESSAGE_EVENT_ADVANCE = 19
ChaosMakeUnique = function(i) i.unique = true end
local made = {}
local function item(id, name, rarity, extra)
	local i = {id = id, name = name, rarity = rarity, price = 0}
	for k, v in pairs(extra or {}) do i[k] = v end
	function i:isItem() return true end
	function i:getName() return self.name end
	return i
end
local function corpseOf(items)
	local c = {items = items}
	function c:getSize() return #self.items end
	function c:getItem(s) return self.items[s + 1] end
	return c
end
local L = {addToCorpse = function(corpse, id, n)
	local e = ChaosUniqueByName and ChaosUniqueById[id]
	local i = item(id, e and e.name or "x", 0)
	corpse.items[#corpse.items + 1] = i
	made[#made + 1] = i
	return i
end}
local pos = {sendMagicEffect = function(self, e) self.effect = e end}
local monster = {getMaster = function() return nil end}

dofile("data/scripts/chaos/retention_loot.lua")
local RL = ChaosRetentionLoot
check(RL ~= nil and RL.begin and RL.adjustRarity and RL.finish and RL.channelJoin and RL.channelLeave, "the engine api")

-- a normal kill: counts toward the first unique and the pity
do
	local ann = newPlayer("Ann", 20)
	players = {ann}
	local st = RL.begin(monster, ann, "normal")
	check(st ~= nil and st.hunting and not st.pityDue, "a hunting kill, not due")
	RL.finish(st, monster, ann, corpseOf({}), pos, L, {})
	eq(ann.store[7103010], 1, "first unique counter 1")
	eq(ann.store[7103011], 1, "pity counter 1")
	-- a boss kill: the first unique counts, the pity does not
	local boss = RL.begin(monster, ann, "boss")
	check(boss and not boss.hunting, "a boss kill is not hunting")
	RL.finish(boss, monster, ann, corpseOf({}), pos, L, {})
	eq(ann.store[7103010], 2, "the boss counts for the first unique")
	eq(ann.store[7103011], 1, "the boss leaves the pity")
	-- a summon is not a hunting kill
	local summon = {getMaster = function() return {} end}
	local st2 = RL.begin(summon, ann, "normal")
	check(not st2.hunting, "a summon is not hunting")
	-- a Rare drop resets the pity
	ann.store[7103011] = 77
	local st3 = RL.begin(monster, ann, "normal")
	RL.finish(st3, monster, ann, corpseOf({item(1, "Rare Axe", 4)}), pos, L, {})
	eq(ann.store[7103011], 0, "a Rare resets the pity")
end

-- the 150th kill gives the unique
do
	local bo = newPlayer("Bo", 25, "Ranger")
	players = {bo}
	bo.store[7103010] = 149
	local corpse, bonus = corpseOf({}), {}
	local st = RL.begin(monster, bo, "normal")
	RL.finish(st, monster, bo, corpse, pos, L, bonus)
	eq(bo.store[7103010], cfg.firstUnique.doneValue, "done stored")
	eq(#corpse.items, 1, "the unique is in the corpse")
	check(corpse.items[1].unique == true, "made a unique")
	check(ChaosUniqueById[corpse.items[1].id] ~= nil, "a real unique id")
	eq(#bonus, 1, "named in the loot line")
	check(bonus[1]:sub(1, 1) == "{", "flagged as notable")
	check(pos.effect ~= nil, "the beam effect")
	eq(#bo.texts >= 1 and bo.texts[#bo.texts][1] or 0, 19, "the message")
	-- no second one
	local c2 = corpseOf({})
	RL.finish(RL.begin(monster, bo, "normal"), monster, bo, c2, pos, L, {})
	eq(#c2.items, 0, "only once")
	-- a high level character never gets it
	local hi = newPlayer("Hi", 100)
	hi.store[7103010] = 149
	local c3 = corpseOf({})
	RL.finish(RL.begin(monster, hi, "normal"), monster, hi, c3, pos, L, {})
	eq(#c3.items, 0, "level 100: nothing")
	-- a tester neither, and a tester feeds nothing
	local bot = newPlayer("Bot", 20)
	bot.tester = true
	bot.store[7103010] = 149
	local c4 = corpseOf({})
	RL.finish(RL.begin(monster, bot, "normal"), monster, bot, c4, pos, L, {})
	eq(#c4.items, 0, "a tester: nothing")
end

-- pity: the due kill raises the first magic or better drop by one
do
	local cy = newPlayer("Cy", 300)
	players = {cy}
	cy.store[7103011] = 400
	local st = RL.begin(monster, cy, "normal")
	check(st.pityDue, "due at 400")
	eq(RL.adjustRarity(st, 0, 1), 1, "a Common stays")
	check(not st.boosted, "not boosted yet")
	eq(RL.adjustRarity(st, 0, 3), ChaosRarity.idOfRank(4), "Magic -> Rare")
	check(st.boosted, "boosted")
	eq(RL.adjustRarity(st, 0, 3), 3, "only one drop per kill")
	RL.finish(st, monster, cy, corpseOf({item(2, "Rare Hat", 4)}), pos, L, {})
	eq(cy.store[7103011], 0, "the counter starts again")
	-- not due: untouched
	local st2 = RL.begin(monster, cy, "normal")
	eq(RL.adjustRarity(st2, 0, 3), 3, "not due: no change")
	-- a due boss kill is not raised
	cy.store[7103011] = 400
	local sb = RL.begin(monster, cy, "boss")
	eq(RL.adjustRarity(sb, 0, 3), 3, "a boss kill is never raised")
	eq(cy.store[7103011], 400, "and keeps the counter")
	-- a Legendary target stays
	local sl = RL.begin(monster, cy, "normal")
	eq(RL.adjustRarity(sl, 0, ChaosRarity.idOfRank(5)), ChaosRarity.idOfRank(5), "Legendary stays")
	check(not sl.boosted, "no boost on Legendary")
	-- the current rarity counts when it is higher than the target
	local sc = RL.begin(monster, cy, "normal")
	eq(RL.adjustRarity(sc, ChaosRarity.idOfRank(4), 0), ChaosRarity.idOfRank(5), "current Rare -> Legendary")
end

-- the feed
do
	local dee = newPlayer("Dee", 150)
	local eve = newPlayer("Eve", 80)
	local fay = newPlayer("Fay", 80)
	players = {dee, eve, fay}
	RL.channelJoin(eve)
	local leg = item(7, "Fire Blade", ChaosRarity.idOfRank(5))
	RL.finish(RL.begin(monster, dee, "normal"), monster, dee, corpseOf({leg}), pos, L, {})
	eq(#eve.texts, 1, "Eve got the Default line")
	eq(#fay.texts, 1, "Fay got the Default line")
	eq(#eve.channel, 1, "Eve got the channel line")
	eq(#fay.channel, 0, "Fay is not in the channel")
	eq(eve.channel[1][2], cfg.feed.channelId, "the channel id")
	eq(eve.texts[1][2], "Dee (Lv 150) found [Fire Blade]{97}!", "the line with the item link")
	eq(eve.texts[1][1], 19, "message type")
	eq(#discord, 1, "one Discord line")
	eq(discord[1][3], "Fire Blade", "Discord item")
	eq(discord[1][4], "legendary", "Discord kind")
	-- the same character again within a minute: silent
	RL.finish(RL.begin(monster, dee, "normal"), monster, dee, corpseOf({leg}), pos, L, {})
	eq(#eve.texts, 1, "rate limited")
	-- a Rare does not post
	local gus = newPlayer("Gus", 90)
	players = {gus, eve}
	RL.finish(RL.begin(monster, gus, "normal"), monster, gus, corpseOf({item(8, "Rare Cap", 4)}), pos, L, {})
	eq(#eve.texts, 1, "a Rare is silent")
	-- a unique posts as unique, and beats the legendary of the same kill
	local hal = newPlayer("Hal", 90)
	players = {hal, eve}
	local uq = item(9, "Doomplate", 0, {unique = true})
	RL.finish(RL.begin(monster, hal, "normal"), monster, hal, corpseOf({leg, uq}), pos, L, {})
	eq(#eve.texts, 2, "the unique line")
	check(eve.texts[2][2]:find("Doomplate", 1, true) ~= nil, "the best find is named")
	eq(discord[#discord][4], "unique", "Discord kind unique")
	-- leaving the channel
	RL.channelLeave(eve)
	local ivy = newPlayer("Ivy", 90)
	players = {ivy, eve}
	RL.finish(RL.begin(monster, ivy, "normal"), monster, ivy, corpseOf({leg}), pos, L, {})
	eq(#eve.channel, 2, "no channel line after leaving")
	-- staff and testers post nothing
	local gm = newPlayer("Gm", 90)
	gm.access = true
	players = {gm, eve}
	local before = #eve.texts
	RL.finish(RL.begin(monster, gm, "normal"), monster, gm, corpseOf({leg}), pos, L, {})
	eq(#eve.texts, before, "staff posts nothing")
	local bot = newPlayer("Bot2", 90)
	bot.tester = true
	players = {bot, eve}
	RL.finish(RL.begin(monster, bot, "normal"), monster, bot, corpseOf({leg}), pos, L, {})
	eq(#eve.texts, before, "a tester posts nothing")
end

-- the client option "Drop Feed"
do
	local lu = newPlayer("Lu", 200)
	local mo = newPlayer("Mo", 80)
	local ned = newPlayer("Ned", 80)
	local oli = newPlayer("Oli", 80)
	players = {lu, mo, ned, oli}
	check(RL.setOption(mo, "off"), "off accepted")
	check(RL.setOption(ned, "unique"), "unique accepted")
	check(not RL.setOption(oli, "bogus"), "a bad mode is refused")
	check(not RL.setOption(oli, nil), "nil is refused")
	local leg = item(30, "Ice Spear", ChaosRarity.idOfRank(5))
	RL.finish(RL.begin(monster, lu, "normal"), monster, lu, corpseOf({leg}), pos, L, {})
	eq(#mo.texts, 0, "off: nothing")
	eq(#ned.texts, 0, "unique only: no legendary line")
	eq(#oli.texts, 1, "no valid option: the default shows it")
	eq(#lu.texts, 1, "the finder gets the default too")
	local pe = newPlayer("Pe", 200)
	players = {pe, mo, ned, oli}
	local uq = item(31, "Doomplate", 0, {unique = true})
	RL.finish(RL.begin(monster, pe, "normal"), monster, pe, corpseOf({uq}), pos, L, {})
	eq(#mo.texts, 0, "off: still nothing")
	eq(#ned.texts, 1, "unique only: the unique line")
	eq(#oli.texts, 2, "the default shows it")
	local di = newPlayer("Di", 200)
	players = {di, ned}
	RL.finish(RL.begin(monster, di, "normal"), monster, di, corpseOf({item(32, "Halo", ChaosRarity.idOfRank(6))}), pos, L, {})
	eq(#ned.texts, 2, "unique only: a divine line too")
end

-- personal records
do
	submitted = {}
	local jo = newPlayer("Jo", 120)
	players = {jo}
	local i1 = item(11, "Gem Ring", ChaosRarity.idOfRank(5), {price = 4000})
	local i2 = item(12, "Cheap Cap", 2, {price = 10})
	RL.finish(RL.begin(monster, jo, "normal"), monster, jo, corpseOf({i1, i2}), pos, L, {})
	eq(#submitted, 2, "rarity and value submitted")
	eq(submitted[1].board, "drop_rarity", "rarity board")
	eq(submitted[1].value, 5, "rank 5")
	eq(submitted[2].board, "drop_value", "value board")
	eq(submitted[2].value, 4000, "value 4000")
	eq(submitted[1].size, 1, "solo")
	-- a lower drop than the stored best submits nothing
	submitted = {}
	local slotR = ChaosRecordsCore.slot("drop_rarity", nil, nil)
	local slotV = ChaosRecordsCore.slot("drop_value", nil, nil)
	bests[jo:getGuid()] = {[slotR] = 6, [slotV] = 9000}
	RL.finish(RL.begin(monster, jo, "normal"), monster, jo, corpseOf({i1}), pos, L, {})
	eq(#submitted, 0, "no new best, no submit")
	-- a drop with no rarity submits nothing
	RL.finish(RL.begin(monster, jo, "normal"), monster, jo, corpseOf({item(13, "Plain", 0)}), pos, L, {})
	eq(#submitted, 0, "no rarity item, no submit")
	-- a tester submits nothing
	local bot = newPlayer("Bot3", 50)
	bot.tester = true
	RL.finish(RL.begin(monster, bot, "normal"), monster, bot, corpseOf({i1}), pos, L, {})
	eq(#submitted, 0, "a tester submits nothing")
end

-- a layer that fails does not break the kill
do
	ChaosRecords.personalBests = function() error("db down") end
	local kay = newPlayer("Kay", 30)
	players = {kay}
	local ok = pcall(RL.finish, RL.begin(monster, kay, "normal"), monster, kay, corpseOf({item(20, "Ring", 5)}), pos, L, {})
	check(ok, "a failing records layer is contained")
	eq(kay.store[7103010], 1, "the first unique counter is still written")
end
check(RL.begin(monster, nil, "normal") == nil, "no owner, no state")
RL.finish(nil, monster, nil, nil, nil, L, {})

print(string.format("retention_loot_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)

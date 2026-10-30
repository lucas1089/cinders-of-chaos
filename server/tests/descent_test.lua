-- Run from the server/ folder: luajit tests/descent_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The Ember Descent (data/scripts/chaos/descent_core.lua, numbers in descent_config.lua): the seeded generator and its
-- fixed values (the same in both interpreters, so a weekly descent is the same run on every server build), the room
-- chains of thousands of seeds (8-12 rooms, combat first, merchant then boss last, no special room twice in a row, no
-- elite before its depth, never the same floor twice), escalation by depth, waves, the boon offers (three different
-- boons, never one at its maximum, one brand at a time, curses from their depth), picks, stacks and curses, the hit
-- maths, embers, prices, rewards by depth, the uniques, titles, free runs and payment; then the wiring into the other
-- systems: opcode, storages, action ids, unique specs, leaderboard board, Boss Spawns row, buff registry and icons.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/descent_core.lua")
local D = ChaosDescentCore
local cfg = dofile("data/scripts/chaos/descent_config.lua")

-- ====================================================================== config
eq(#D.validate(cfg), 0, "the config is valid: " .. table.concat(D.validate(cfg), "; "))
ok(cfg.storage >= 7100410 and cfg.storage + 1 <= 7100419, "storages in the reserved range 7100410-7100419")
ok(cfg.tables.players:match("^chaos_descent") and cfg.tables.runs:match("^chaos_descent"), "table names chaos_descent*")
ok(cfg.rooms.min >= 8 and cfg.rooms.max <= 12, "8-12 rooms")
ok(cfg.maxPlayers == 4, "parties of up to 4")
ok(#cfg.boons >= 12 and #cfg.curses >= 4, "enough boons and curses")

-- ====================================================================== the generator: fixed values
-- computed once; both interpreters must give exactly these (integer maths only)
eq(D.hash("abc"), 193485963, "hash")
eq(D.weekSeed(20261005), 1965164180, "week seed")
local r = D.rng(12345)
eq(r:next(), 1558181227, "first draw")
eq(r:next(), 1498755989, "second draw")
eq(r:int(1, 100), 84, "int")
local plan = D.generate(cfg, 777, 4)
local kinds = {}
for _, x in ipairs(plan.rooms) do
	kinds[#kinds + 1] = x.type:sub(1, 2) .. x.theme
end
eq(plan.count, 9, "rooms of seed 777")
eq(table.concat(kinds, ","), "co2,co3,co2,co4,co1,co4,co1,me2,bo3", "the chain of seed 777")
local o = D.rollOffer(cfg, D.roomRng(777, 3, "offer:1:1"), D.newState(), 3, {curse = true})
eq(table.concat(o.cards, ","), "stoneskin,keen_eye,soul_harvest", "the offer of seed 777, room 3, slot 1")
eq(o.curse, "swarm", "and its curse")

-- determinism and range
local a, b = D.rng(99), D.rng(99)
local same = true
for _ = 1, 1000 do
	if a:next() ~= b:next() then
		same = false
	end
end
ok(same, "one seed, one sequence")
ok(D.rng(1):next() ~= D.rng(2):next(), "close seeds part ways")
local lo, hi, hits = 99, 0, {}
r = D.rng(5)
for _ = 1, 6000 do
	local v = r:int(1, 6)
	lo, hi = math.min(lo, v), math.max(hi, v)
	hits[v] = (hits[v] or 0) + 1
end
ok(lo == 1 and hi == 6, "int stays in its range")
for v = 1, 6 do
	ok(hits[v] > 850 and hits[v] < 1150, "int is even: " .. v .. " " .. hits[v])
end
local yes = 0
for _ = 1, 10000 do
	if r:chance(30) then
		yes = yes + 1
	end
end
ok(yes > 2800 and yes < 3200, "chance 30%: " .. yes)
ok(not r:chance(0), "chance 0")
eq(D.rng(0):next() > 0, true, "seed 0 works")
eq(D.rng(-5):next() > 0, true, "negative seed works")
eq(r:weighted({}), nil, "nothing to weigh")

-- ====================================================================== room chains
local typeSeen, counts = {}, {}
for seed = 1, 3000 do
	local p = D.generate(cfg, seed, 4)
	local p2 = D.generate(cfg, seed, 4)
	ok(p.count == p2.count and p.rooms[p.count - 2].type == p2.rooms[p.count - 2].type, "generate is deterministic " .. seed)
	ok(p.count >= cfg.rooms.min and p.count <= cfg.rooms.max, "room count " .. p.count)
	counts[p.count] = true
	eq(p.rooms[1].type, "combat", "the first room fights")
	eq(p.rooms[p.count].type, "boss", "the last room is the boss")
	eq(p.rooms[p.count - 1].type, "merchant", "the merchant waits before the boss")
	for i, room in ipairs(p.rooms) do
		typeSeen[room.type] = true
		ok(room.theme >= 1 and room.theme <= 4, "theme in range")
		if i > 1 then
			ok(room.theme ~= p.rooms[i - 1].theme, "never the same floor twice " .. seed)
			local prev = p.rooms[i - 1].type
			if room.type == prev then
				ok(room.type == "combat" or room.type == "elite", "special rooms never twice in a row " .. seed .. " " .. room.type)
			end
		end
		if room.type == "elite" then
			ok(i >= cfg.eliteFrom, "no elite before depth " .. cfg.eliteFrom)
		end
	end
end
for _, k in ipairs({"combat", "elite", "treasure", "shrine", "merchant", "boss"}) do
	ok(typeSeen[k], "every room type appears: " .. k)
end
for n = cfg.rooms.min, cfg.rooms.max do
	ok(counts[n], "every length appears: " .. n)
end
eq(D.generate(cfg, 5, 1).rooms[2].theme, 1, "one theme: always it")

-- weekly seeds
local t = os.time({year = 2026, month = 10, day = 7, hour = 12})
local w = D.weekKey(t, 6)
eq(w, 20261005, "the week of Wednesday 7 October 2026 starts Monday 5")
eq(D.weekKey(os.time({year = 2026, month = 10, day = 11, hour = 23}), 6), w, "Sunday: the same week")
eq(D.weekKey(os.time({year = 2026, month = 10, day = 12, hour = 5}), 6), w, "Monday before the reset hour: the same week")
ok(D.weekKey(os.time({year = 2026, month = 10, day = 12, hour = 7}), 6) ~= w, "Monday after the reset: a new week")
ok(D.weekSeed(20261005) ~= D.weekSeed(20261012), "every week its own seed")
ok(D.runSeed(1, 100, 1) ~= D.runSeed(1, 100, 2), "every run its own seed")

-- ====================================================================== escalation and waves
local prev
for depth = 1, 12 do
	local e = D.escalation(cfg, depth, 400)
	ok(e.window[1] < e.window[2], "a window")
	ok(e.tiers.magic + e.tiers.rare + e.tiers.legendary < 100, "tier mix below 100%")
	if prev then
		ok(e.window[1] >= prev.window[1] and e.window[2] > prev.window[2], "deeper: stronger monsters " .. depth)
		ok(e.health > prev.health and e.damage > prev.damage, "deeper: more health and damage " .. depth)
		ok(e.tiers.rare > prev.tiers.rare and e.tiers.legendary >= prev.tiers.legendary, "deeper: more elites " .. depth)
	end
	prev = e
end
local e1 = D.escalation(cfg, 1, 400)
eq(e1.window[1], 240, "level 400, depth 1: from 240")
eq(e1.window[2], 340, "to 340")
eq(e1.health, 1, "depth 1: base health")
eq(e1.tiers.legendary, 0, "no legendary at depth 1")
local e12 = D.escalation(cfg, 12, 400)
eq(e12.health, 1.88, "depth 12 health")
eq(e12.damage, 1.66, "depth 12 damage")
eq(D.escalation(cfg, 1, 10).window[1], cfg.escalation.minLevel, "a low level is clamped")
ok(D.escalation(cfg, 12, 5000).window[2] <= cfg.escalation.maxLevel, "a high level is clamped")
-- tiers drawn: about the mix
local e8 = D.escalation(cfg, 8, 400)
local tierHits = {}
r = D.rng(8)
for _ = 1, 20000 do
	local k = D.rollTier(e8, r) or "normal"
	tierHits[k] = (tierHits[k] or 0) + 1
end
ok(math.abs(tierHits.magic / 200 - e8.tiers.magic) < 1.5, "magic share " .. tierHits.magic)
ok(math.abs(tierHits.rare / 200 - e8.tiers.rare) < 1, "rare share " .. tierHits.rare)
ok(math.abs((tierHits.legendary or 0) / 200 - e8.tiers.legendary) < 0.8, "legendary share")

local c1 = D.roomPlan(cfg, "combat", 1, 1, 0)
eq(c1.waves, 2, "depth 1: two waves")
eq(c1.size, 4, "of four")
local c9 = D.roomPlan(cfg, "combat", 9, 4, 0)
eq(c9.waves, 4, "depth 9: four waves")
eq(c9.size, 13, "of 4 + 3 + 6")
eq(D.roomPlan(cfg, "combat", 12, 4, 0).waves, cfg.waves.max, "waves capped")
ok(D.roomPlan(cfg, "combat", 12, 4, 0).size <= cfg.size.max, "size capped")
ok(D.roomPlan(cfg, "combat", 4, 2, 30).size > D.roomPlan(cfg, "combat", 4, 2, 0).size, "Swarm adds monsters")
local el = D.roomPlan(cfg, "elite", 5, 1, 0)
ok(el.elite and el.waves == 1 and el.size == 3, "elite room: one wave of 3")
eq(D.roomPlan(cfg, "treasure", 3, 2, 0).size, 4, "treasure guards")
eq(D.roomPlan(cfg, "boss", 10, 4, 0).boss, true, "boss room")
eq(D.roomPlan(cfg, "shrine", 3, 1, 0).waves, 0, "a shrine has no monsters")
eq(D.bossHealth(cfg, 1), 6, "boss health alone")
eq(D.bossHealth(cfg, 4), 12, "boss health for four")
local legend = 0
r = D.rng(3)
for _ = 1, 2000 do
	if D.eliteTier(cfg, 10, r) == "legendary" then
		legend = legend + 1
	end
end
ok(legend > 1400 and legend < 1600, "elite room at depth 10: 75% legendary " .. legend)

-- ====================================================================== offers and picks
for seed = 1, 400 do
	local st = D.newState()
	for depth = 1, 12 do
		local off = D.rollOffer(cfg, D.roomRng(seed, depth, "offer"), st, depth, {curse = true})
		local seen = {}
		for _, key in ipairs(off.cards) do
			ok(not seen[key], "three different boons")
			seen[key] = true
			local def = D.boonDef(cfg, key)
			ok(def and (st.boons[key] or 0) < def.max, "never a boon at its maximum")
		end
		ok(#off.cards == 3, "three cards while enough boons are left")
		if depth < cfg.curseFrom then
			eq(off.curse, nil, "no curse before depth " .. cfg.curseFrom)
		end
		if off.curse then
			for _, k in ipairs(st.curses) do
				ok(k ~= off.curse, "a held curse is not offered again")
			end
		end
		local pick = (seed + depth) % 3 + 1
		local done, key, curse = D.applyPick(cfg, st, off, pick, depth % 2 == 0)
		ok(done and key == off.cards[pick], "the pick")
		if depth % 2 == 0 then
			eq(curse, off.curse, "the curse comes with the pick")
		end
	end
	local brands = 0
	for _, b in ipairs(cfg.boons) do
		if b.kind == "convert" and (st.boons[b.key] or 0) > 0 then
			brands = brands + 1
		end
	end
	ok(brands <= 1, "one brand at a time")
end
eq(#D.rollOffer(cfg, D.rng(1), D.newState(), 1, {}).cards, 3, "a first offer")
eq(D.rollOffer(cfg, D.rng(1), D.newState(), 8, {curse = false}).curse, nil, "no curse unless asked")
local off1 = D.rollOffer(cfg, D.roomRng(4242, 5, "offer:2:3"), D.newState(), 5, {curse = true})
local off2 = D.rollOffer(cfg, D.roomRng(4242, 5, "offer:2:3"), D.newState(), 5, {curse = true})
eq(table.concat(off1.cards, ","), table.concat(off2.cards, ","), "the weekly run offers the same cards to the same slot")
eq(off1.curse, off2.curse, "and the same curse")
-- every boon at max: nothing left to offer
local full = D.newState()
for _, b in ipairs(cfg.boons) do
	full.boons[b.key] = b.max
end
eq(#D.rollOffer(cfg, D.rng(1), full, 5, {}).cards, 0, "nothing at max is offered")

local st = D.newState()
local offer = {cards = {"ember_edge", "keen_eye", "stoneskin"}, curse = "frailty"}
ok(D.applyPick(cfg, st, offer, 1, true), "pick 1 with the curse")
eq(st.boons.ember_edge, 1, "one stack")
eq(st.rewardPct, 25, "Frailty pays 25%")
eq(st.embers, 30, "and 30 embers")
eq(st.curses[1], "frailty", "the curse is held")
D.applyPick(cfg, st, offer, 1, false)
D.applyPick(cfg, st, offer, 1, false)
D.applyPick(cfg, st, offer, 1, false)
eq(st.boons.ember_edge, 3, "stacks stop at the maximum")
eq(#st.order, 1, "a boon is listed once")
ok(not D.applyPick(cfg, st, offer, 4, false), "no 4th card")
ok(not D.applyPick(cfg, st, nil, 1, false), "no offer")
eq(D.cleanse(cfg, st), "frailty", "the cleanse takes the newest curse")
eq(st.rewardPct, 0, "with its reward")
eq(D.cleanse(cfg, st), nil, "nothing left to cleanse")

-- ====================================================================== effects and hits
local s2 = D.newState()
s2.boons = {ember_edge = 2, searing_brand = 1, keen_eye = 1, executioner = 1, stoneskin = 2, ember_ward = 1,
	blood_drinker = 1, quickstep = 2, ember_tithe = 1, phoenix_ember = 1, echo_strike = 1, pyre_burst = 2}
s2.curses = {"frailty", "ashen_purse", "withering"}
local fx = D.effects(cfg, s2)
eq(fx.damage, 24, "Ember Edge x2")
eq(fx.convert.element, "fire", "Searing Brand")
eq(fx.reduce, 20, "Stoneskin x2")
eq(fx.taken, 20, "Frailty")
eq(fx.speed, 80, "Quickstep x2")
eq(fx.ward, 10, "Ember Ward")
eq(fx.wardEvery, 20, "renews every 20 s")
eq(fx.phoenix, 40, "Phoenix Ember")
eq(fx.burst, 40, "Pyre Burst x2")
eq(fx.healing, 30, "Withering")
local plain = D.effects(cfg, D.newState())
local h = D.hitOut(plain, 1000, true, 100, nil)
eq(h.amount, 1000, "no boon: the hit as it was")
eq(h.converted, 0, "nothing converted")
h = D.hitOut(fx, 1000, true, 100, nil)
eq(h.amount, 1240 + 93, "Ember Edge +24%, the brand's 50% part +15%")
eq(h.converted, 620 + 93, "half of it fire")
eq(h.leech, math.floor(1333 * 5 / 100), "Blood Drinker")
h = D.hitOut(fx, 1000, false, 20, nil)
eq(h.amount, 1590, "Executioner below 30%: +35%, no brand on a magic hit")
eq(h.converted, 0, "a magic hit is not converted")
local crits, echoes = 0, 0
r = D.rng(77)
for _ = 1, 4000 do
	local x = D.hitOut(fx, 100, false, 100, r)
	if x.crit then
		crits = crits + 1
		eq(x.amount, 184, "a crit: +24% +60%")
	end
	if x.echo > 0 then
		echoes = echoes + 1
	end
end
ok(crits > 300 and crits < 500, "Keen Eye: about 10% " .. crits)
ok(echoes > 680 and echoes < 920, "Echo Strike: about 20% " .. echoes)
local after, absorbed, left = D.hitIn(fx, 1000, 300)
eq(absorbed, 300, "the ward takes its part")
eq(after, 700, "Stoneskin -20%, Frailty +20%, ward 300")
eq(left, 0, "the ward is spent")
after, absorbed, left = D.hitIn(plain, 100, 500)
ok(after == 0 and absorbed == 100 and left == 400, "a big ward holds")
eq(D.healIn(fx, 100), 70, "Withering: 30% less healing")
eq(D.healIn(plain, 100), 100, "healing as it was")
eq(D.embers(fx, 100), 110, "Ember Tithe +50%, Ashen Purse -40%")
eq(D.embers(plain, 15), 15, "embers as they were")
local maxed = D.newState()
maxed.boons = {stoneskin = 3, keen_eye = 3}
ok(D.effects(cfg, maxed).reduce <= 60, "Stoneskin stays below 60%")
local party = D.partyEffects(cfg, {{curses = {"swarm"}}, {curses = {"swarm", "frenzy"}}, {curses = {}}})
eq(party.swarm, 60, "two Swarms")
eq(party.frenzy, 60, "Frenzied Foes")

-- texts
eq(D.boonText(D.boonDef(cfg, "ember_edge"), 2), "+24% damage to Descent monsters.", "boon text with stacks")
eq(D.boonText(D.boonDef(cfg, "searing_brand"), 1), "50% of your physical damage becomes fire, and that part hits 15% harder.",
	"brand text")
eq(D.curseText(D.curseDef(cfg, "frailty")), "You take 20% more damage.", "curse text")
for _, b in ipairs(cfg.boons) do
	ok(not D.boonText(b, 1):find("%%", 1, true) and not D.boonText(b, 1):find("%d", 1, true), "boon text formats: " .. b.key)
end

-- prices
local mend = D.ware(cfg, "mend")
eq(D.price(cfg, mend, 8), 44, "Ember Draught at depth 8")
eq(D.ware(cfg, "nope"), nil, "unknown ware")

-- ====================================================================== rewards
local last
for depth = 0, 12 do
	local rw = D.reward(cfg, depth, false, 300, 0)
	if last then
		ok(rw.gold > last.gold, "deeper: more gold " .. depth)
		ok(rw.uniqueChance >= last.uniqueChance, "deeper: a better unique chance " .. depth)
	end
	last = rw
end
local r0 = D.reward(cfg, 0, false, 300, 0)
eq(r0.gold, 0, "depth 0: nothing")
eq(#r0.items, 0, "no orbs")
local r5 = D.reward(cfg, 5, false, 400, 0)
eq(r5.gold, math.floor((3000 * 5 + 400 * 25) * 2), "depth 5 gold at level 400")
eq(r5.uniqueChance, 0, "no unique before depth 6")
eq(#r5.items, 2, "Upheaval and Fate at depth 5")
local r10 = D.reward(cfg, 10, false, 400, 0)
local r10c = D.reward(cfg, 10, true, 400, 0)
eq(r10c.gold, math.floor(r10.gold * 1.5), "a full clear: x1.5 gold")
eq(r10.uniqueChance, 750, "depth 10: 7.5%")
eq(r10c.uniqueChance, 1550, "and 15.5% with the boss")
eq(D.reward(cfg, 12, true, 400, 100).uniqueChance, cfg.rewards.unique.max, "the unique chance is capped")
local cursed = D.reward(cfg, 8, false, 400, 50)
ok(cursed.gold > D.reward(cfg, 8, false, 400, 0).gold, "curses pay")
eq(D.pickUnique(cfg, 5, D.rng(1)), nil, "no unique before its depth")
local picked = {}
r = D.rng(11)
for _ = 1, 500 do
	local u = D.pickUnique(cfg, 12, r)
	picked[u.id] = true
	ok(12 >= u.minDepth, "a unique the depth opened")
end
for _, u in ipairs(cfg.rewards.uniques) do
	ok(picked[u.id], "every unique can come at depth 12: " .. u.name)
	ok(D.pickUnique(cfg, u.minDepth - 1, D.rng(u.id)) == nil or D.pickUnique(cfg, u.minDepth - 1, D.rng(u.id)).id ~= u.id
		or u.minDepth - 1 >= u.minDepth, "not before its depth: " .. u.name)
end

-- titles
eq(#D.titles(cfg, 0, false), 0, "no title")
eq(D.titles(cfg, 5, false)[1].text, "Ashwalker", "depth 5")
eq(#D.titles(cfg, 9, false), 2, "depth 9: two")
eq(#D.titles(cfg, 12, true), 3, "a full clear: all three")

-- free runs and payment
local now = os.time({year = 2026, month = 10, day = 7, hour = 15})
local fs = D.freeState(cfg, {}, now)
ok(fs.daily and fs.weekly, "a new character: both free runs")
eq(fs.day, 20261007, "the day key")
fs = D.freeState(cfg, {freeDay = 20261007, freeWeek = 20261005}, now)
ok(not fs.daily and not fs.weekly, "both used")
ok(fs.nextDaily > now and fs.nextDaily - now <= 86400, "the next free run tomorrow")
eq(D.payment(fs, false, 0), nil, "no free run, no sigil")
eq(D.payment(fs, true, 2), "sigil", "a sigil pays")
eq(D.payment(D.freeState(cfg, {freeDay = 20261006}, now), false, 3), "free", "a new day: free first")
eq(D.payment(D.freeState(cfg, {freeWeek = 20260928}, now), true, 0), "free", "a new week: the weekly is free")
-- unused daily free runs bank (freeBankDays)
eq(cfg.freeBankDays, 3, "three free runs bank at most")
eq(D.freeState(cfg, {}, now).dailyCount, 3, "a new character: a full bank")
eq(D.freeState(cfg, {freeDay = 20261006}, now).dailyCount, 1, "used yesterday: one (the old meaning)")
eq(D.freeState(cfg, {freeDay = 20261004}, now).dailyCount, 3, "three days: three")
eq(D.freeState(cfg, {freeDay = 20260901}, now).dailyCount, 3, "a month away: still three")
local row = {freeDay = 20260901}
row.freeDay = D.spendDaily(cfg, row, now)
eq(row.freeDay, 20261005, "spend one of three: the clock starts three days back")
eq(D.freeState(cfg, row, now).dailyCount, 2, "two left")
row.freeDay = D.spendDaily(cfg, row, now)
row.freeDay = D.spendDaily(cfg, row, now)
eq(row.freeDay, 20261007, "all three spent: the clock is today")
ok(not D.freeState(cfg, row, now).daily, "nothing left today")
eq(D.spendDaily(cfg, {}, now), 20261005, "a new character spends from a full bank")

-- ====================================================================== monster types and spawning (beta report 2026-10-24)
-- A room whose window lies above the monster pool had no type and counted as cleared at once ("a room bonus right after
-- entering"). The bounty pool ended at level 980 then and the window of a level 1500+ party is 900-1800 and more. O337: the pool
-- lists the monsters of the planned hunts now (829 monsters up to level 2000) and escalation.maxLevel is 2000, the top of it, so
-- the real pool holds a window everywhere; the old situation is kept as a test on the pool cut at level 980.
do
	local pool = dofile("data/scripts/chaos/bounty_pool.lua").hunt
	local top = 0
	for _, m in ipairs(pool) do
		top = math.max(top, m.level)
	end
	eq(top, cfg.escalation.maxLevel, "the strongest monster of the pool is the ceiling of the window (escalation.maxLevel)")
	local short = {}
	for _, m in ipairs(pool) do
		if m.level <= 980 then
			short[#short + 1] = m
		end
	end
	ok(#pool > 800 and #pool - #short >= 50, "the pool holds the planned hunts' monsters above 980: " .. #pool .. " against " .. #short)
	local anyKnown = function() return true end
	-- the old pick (widen the window five times, nothing else) as the reproduction
	local function oldPick(pool, window)
		local e = cfg.escalation
		local w = {window[1], window[2]}
		local function count()
			local n = 0
			for _, m in ipairs(pool) do
				if m.level >= w[1] and m.level <= w[2] and m.health >= e.minPoolHealth then
					n = n + 1
				end
			end
			return n
		end
		local n, widen = count(), 0
		while n < cfg.types and widen < 5 do
			widen = widen + 1
			w = {w[1] - e.widen, w[2] + e.widen}
			n = count()
		end
		return n
	end
	local seen, shortTop = 0, 0
	for _, m in ipairs(short) do
		shortTop = math.max(shortTop, m.level)
	end
	for _, level in ipairs({100, 300, 800, 1000, 1500, 2000, 2200}) do
		for depth = 1, 12 do
			local esc = D.escalation(cfg, depth, level)
			-- the real pool: a full set of types, inside the window or the widened one
			local types = D.pickTypes(cfg, pool, esc.window, anyKnown, D.roomRng(7, depth, "types"))
			ok(#types == cfg.types, string.format("level %d depth %d: %d monster types (window %d-%d)", level, depth, #types,
				esc.window[1], esc.window[2]))
			ok(oldPick(pool, esc.window) >= cfg.types, string.format("level %d depth %d: the real pool needs no fallback (window %d-%d)",
				level, depth, esc.window[1], esc.window[2]))
			for _, m in ipairs(types) do
				ok(m.health >= cfg.escalation.minPoolHealth, "a fallback type is no weakling: " .. m.name)
			end
			-- the pool cut at 980 (the pool of the beta report): the fallback fills the room
			local cut = D.pickTypes(cfg, short, esc.window, anyKnown, D.roomRng(7, depth, "types"))
			ok(#cut == cfg.types, string.format("the short pool, level %d depth %d: %d monster types", level, depth, #cut))
			if oldPick(short, esc.window) == 0 then
				seen = seen + 1
				ok(#cut > 0, "the old pick found nothing at level " .. level .. " depth " .. depth .. ", the new one does")
			end
		end
	end
	ok(seen > 0, "the old pick really left rooms empty on the short pool (it tops at " .. shortTop .. ")")
	-- the fallback takes the nearest levels: above the pool that is the strongest monsters
	for _, p in ipairs({{short, shortTop}, {pool, top}}) do
		local hi = D.pickTypes(cfg, p[1], {p[2] + 520, p[2] + 820}, anyKnown, D.roomRng(7, 12, "types"))
		eq(#hi, cfg.types, "above the pool: a full set of types")
		for _, m in ipairs(hi) do
			ok(m.level >= p[2] - 150, "above the pool: the strongest, got " .. m.name .. " level " .. m.level)
		end
	end
	-- a level 2200 party never gets a window above the pool: the clamp keeps it on the strongest monsters
	for depth = 1, 12 do
		ok(D.escalation(cfg, depth, 2200).window[2] <= top + 10, "level 2200, depth " .. depth .. ": the window ends at the pool's top")
	end
	-- same draws as before when the window holds enough
	local esc = D.escalation(cfg, 3, 400)
	local a1 = D.pickTypes(cfg, pool, esc.window, anyKnown, D.roomRng(5, 3, "types"))
	local a2 = D.pickTypes(cfg, pool, esc.window, anyKnown, D.roomRng(5, 3, "types"))
	eq(#a1, cfg.types, "a normal window gives all types")
	for i = 1, #a1 do
		eq(a1[i].name, a2[i].name, "one seed, one pick")
		ok(a1[i].level >= esc.window[1] and a1[i].level <= esc.window[2], "inside the window: " .. a1[i].name)
	end
	-- a pool without one valid monster: no types (the engine file ends the run, it never clears the room)
	eq(#D.pickTypes(cfg, pool, esc.window, function() return false end, D.roomRng(5, 3, "types")), 0, "nothing known, nothing picked")
	eq(#D.pickTypes(cfg, {}, esc.window, anyKnown, D.roomRng(5, 3, "types")), 0, "an empty pool")
end

do
	local types = {{name = "Alpha", level = 10}, {name = "Beta", level = 20}, {name = "Gamma", level = 30}}
	-- a mocked engine that cannot create one name
	local made = {}
	local n, failed = D.spawnSet(types, 6, function(t, k)
		if t.name == "Beta" then
			return nil
		end
		made[#made + 1] = t.name
		return {k = k}
	end)
	eq(n, 6, "a failing type gives way: every monster is made")
	eq(#failed, 1, "one failed name in the report")
	eq(failed[1], "Beta", "the failed name")
	for _, name in ipairs(made) do
		ok(name ~= "Beta", "no Beta was made")
	end
	-- the engine creates nothing at all: 0 made, never a clearable wave
	local calls = 0
	n, failed = D.spawnSet(types, 4, function() calls = calls + 1 return nil end)
	eq(n, 0, "nothing could be created: 0 made")
	eq(#failed, 3, "all three names reported once")
	eq(calls, 12, "every monster tried every type")
	-- no types at all
	n = D.spawnSet({}, 4, function() return {} end)
	eq(n, 0, "no types: 0 made")
	-- everything works
	n, failed = D.spawnSet(types, 5, function() return {} end)
	eq(n, 5, "all made")
	eq(#failed, 0, "nothing failed")
end

eq(#D.validate(cfg), 0, "the config still validates")
do
	local bad = {}
	for k, v in pairs(cfg) do
		bad[k] = v
	end
	bad.spawn = nil
	ok(#D.validate(bad) > 0, "a config without the spawn retry numbers is refused")
end

-- ====================================================================== wiring
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.descent, 205, "opcode 205")
local used = {}
for k, v in pairs(ChaosOpcodes) do
	ok(not used[v], "opcode " .. v .. " used twice (" .. k .. ", " .. tostring(used[v]) .. ")")
	used[v] = k
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	ok(used[v] == nil, "no collision with the reference server's opcode " .. v)
end
eq(Chaos.storage.descent, cfg.storage, "the storage base")

-- action ids and storages: nobody else uses ours
local function readAll(path)
	local f = io.open(path, "rb")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	return s
end
local others = io.popen and io.popen('ls data/scripts/chaos/*.lua 2>/dev/null')
if others then
	for path in others:lines() do
		if not path:find("descent", 1, true) and not path:find("chaos_constants", 1, true) then
			local text = readAll(path)
			for _, aid in pairs(cfg.aid) do
				ok(not text:find(tostring(aid), 1, true), "action id " .. aid .. " is ours alone (" .. path .. ")")
			end
			ok(not text:find(tostring(cfg.sigil.actionId), 1, true), "the sigil's action id is ours alone (" .. path .. ")")
			for s = cfg.storage, cfg.storage + 9 do
				ok(not text:find(tostring(s), 1, true) or path:find("bossspawns_config", 1, true),
					"storage " .. s .. " is ours alone (" .. path .. ")")
			end
		end
	end
	others:close()
end

-- the uniques: specs generated, not in the drop pool of any monster
for _, k in ipairs({"ATTACK", "DEFENSE", "EXTRADEFENSE", "ARMOR", "HITCHANCE", "SHOOTRANGE"}) do
	_G["ITEM_ATTRIBUTE_" .. k] = _G["ITEM_ATTRIBUTE_" .. k] or k:lower()
end
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
for _, u in ipairs(cfg.rewards.uniques) do
	local spec = ChaosUniqueSpecs[u.id]
	ok(spec ~= nil, "a unique spec for " .. u.name)
	eq(spec and spec.name, u.name, "its name")
	ok(ChaosUniqueById[u.id] == nil, "never a monster drop: " .. u.name)
end

-- the leaderboard board, the Boss Spawns row, the buff registry
local lb = dofile("data/scripts/chaos/leaderboard_config.lua")
local board
for _, bd in ipairs(lb.boards) do
	if bd.key == cfg.board then
		board = bd
	end
end
ok(board and board.mode == "max", "the weekly board keeps the deepest run")
local bs = dofile("data/scripts/chaos/bossspawns_config.lua")
local row, cat
for _, e in ipairs(bs.bosses or {}) do
	if e.key == "descent_boss" then
		row = e
	end
end
for _, c in ipairs(bs.categories) do
	if c.key == "descent" then
		cat = c
	end
end
ok(row and cat and row.category == cat.key, "the Boss Spawns row and its category")
eq(row and row.rule.type, "ondemand", "on demand")
eq(row and row.rule.cooldown, cfg.storage + 1, "its cooldown is the free run storage")
dofile("data/lib/chaos_buffs.lua")
ok(ChaosBuffs.byKey.descent_boon and ChaosBuffs.byKey.descent_curse, "the buff registry lists the boons and curses")
eq(ChaosBuffs.byKey.descent_curse.kind, "debuff", "curses are debuffs")
ok(ChaosBuffs.sources.descent ~= nil, "the buff source")
-- the source asks descent.lua
ChaosDescent = {buffItems = function(_, kind)
	return {{key = "descent_b_x", name = string.rep("n", 80), desc = "d", icon = "buff:descent_b_x", kind = kind, prio = 26}}
end}
local items = ChaosBuffs.sources.descent({}, 0, ChaosBuffs.byKey.descent_boon)
eq(#items, 1, "the source gives the boons")
eq(#items[1].name, ChaosBuffs.cfg.maxName, "and cuts long names")
ChaosDescent = nil

-- every boon and curse has its icon at the buff bar's size
local function pngSize(path)
	local s = readAll(path)
	if #s < 24 then
		return nil
	end
	local function u32(i)
		local b1, b2, b3, b4 = s:byte(i, i + 3)
		return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
	end
	return u32(17), u32(21)
end
local ICONS = "../client/overlay/data/images/game/buffs/"
for _, b in ipairs(cfg.boons) do
	local w, hh = pngSize(ICONS .. "descent_b_" .. b.key .. ".png")
	ok(w == 26 and hh == 26, "icon of the boon " .. b.key)
end
for _, c in ipairs(cfg.curses) do
	local w, hh = pngSize(ICONS .. "descent_c_" .. c.key .. ".png")
	ok(w == 26 and hh == 26, "icon of the curse " .. c.key)
end

if fails > 0 then
	print(string.format("descent_test: %d of %d checks FAILED", fails, checks))
	os.exit(1)
end
print(string.format("descent_test: %d checks, 0 failures", checks))

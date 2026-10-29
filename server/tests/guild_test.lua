-- Run from the server/ folder: luajit tests/guild_test.lua (and lua5.3; CI runs both)
-- Pure logic of guild levels and guild halls (guild_core.lua) with the real guild_config.lua: the XP curve and the
-- caps, perks per level, hall purchase and upgrade prerequisites and costs, rent, hall slots and layout, the depot
-- rules, attribute encoding and log lines, the weekly board.
dofile("data/scripts/chaos/guild_core.lua")
local C = ChaosGuildCore
local cfg = dofile("data/scripts/chaos/guild_config.lua")

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end

-- ---------------------------------------------------------------- curve
eq(C.levelNeed(1, cfg), 300, "level 1 -> 2")
eq(C.levelNeed(5, cfg), 3350, "level 5 -> 6")
eq(C.levelNeed(19, cfg), 24850, "level 19 -> 20")
eq(C.levelNeed(20, cfg), nil, "no level after the max")
eq(C.levelNeed(0, cfg), nil, "no level 0")
eq(C.totalFor(1, cfg), 0, "level 1 is free")
eq(C.totalFor(5, cfg), 5110, "total to 5")
eq(C.totalFor(20, cfg), 201410, "total to 20")
local prev = 0
for l = 1, 19 do
	local n = C.levelNeed(l, cfg)
	ok(n > prev, "curve rises at " .. l)
	eq(n % 10, 0, "rounded at " .. l)
	prev = n
end
local lvl, into, need, pct = C.levelOf(0, cfg)
eq(lvl, 1, "0 xp is level 1")
eq(need, 300, "needs 300")
eq(pct, 0, "0%")
lvl, into, need, pct = C.levelOf(450, cfg)
eq(lvl, 2, "450 -> level 2")
eq(into, 150, "150 into level 2")
eq(need, 850, "level 2 needs 850")
eq(pct, 17, "17%")
eq((C.levelOf(C.totalFor(10, cfg), cfg)), 10, "exactly the total of 10 is level 10")
eq((C.levelOf(C.totalFor(10, cfg) - 1, cfg)), 9, "one short is level 9")
lvl, into, need, pct = C.levelOf(10 ^ 9, cfg)
eq(lvl, 20, "capped at 20")
eq(need, 0, "nothing needed at the max")
eq(pct, 100, "100% at the max")
eq((C.levelOf(-5, cfg)), 1, "negative xp is level 1")

-- ---------------------------------------------------------------- experience share and caps
eq(C.expForLevel(1), 0, "exp of level 1")
eq(C.expForLevel(2), 100, "exp of level 2")
eq(C.expForLevel(100), 15694800, "exp of level 100")
local levelExp = C.expForLevel(101) - C.expForLevel(100)
local g, carry, capped = C.expShare(levelExp, 100, 0, 0, cfg)
eq(g, 10, "a full level's worth gives 10 GXP")
eq(capped, false, "not capped")
g, carry = C.expShare(levelExp / 4, 100, 0, 0, cfg)
eq(g, 2, "a quarter level: 2 GXP")
ok(math.abs(carry - 0.5) < 1e-9, "and a carry of 0.5")
g, carry = C.expShare(levelExp / 4, 100, carry, 0, cfg)
eq(g, 3, "the carry adds up")
ok(math.abs(carry) < 1e-9, "carry used")
-- the same kill is worth less to a higher level
local g1 = C.expShare(100000, 50, 0, 0, cfg)
local g2 = C.expShare(100000, 200, 0, 0, cfg)
ok(g1 > g2, "share is relative to the member's level")
-- daily cap
local cap = cfg.sources.exp.dailyCap
g, carry, capped = C.expShare(levelExp * 100, 100, 0, 0, cfg)
eq(g, cap, "cut at the daily cap")
eq(capped, true, "capped flag")
g, carry, capped = C.expShare(levelExp, 100, 0.9, cap - 3, cfg)
eq(g, 3, "only what is left under the cap")
eq(capped, true, "capped at the edge")
eq(carry, 0, "no carry when capped")
g, carry, capped = C.expShare(levelExp, 100, 0, cap, cfg)
eq(g, 0, "nothing past the cap")
eq(capped, true, "capped")
eq((C.expShare(0, 100, 0, 0, cfg)), 0, "no exp, no GXP")
eq((C.expShare(-50, 100, 0, 0, cfg)), 0, "negative exp, no GXP")

-- boards
eq(C.boardAmount("bounty", 1, cfg), 15, "bounty contract")
eq(C.boardAmount("rift", 7, cfg), 24, "rift tier 7")
eq(C.boardAmount("rift", 15, cfg), 40, "rift tier 15 capped")
eq(C.boardAmount("worldboss", 18000000, cfg), 40, "world boss participation is flat")
eq(C.boardAmount("siege", 500, cfg), 20, "siege 500 points")
eq(C.boardAmount("siege", 100000, cfg), 40, "siege capped")
eq(C.boardAmount("goblin", 1, cfg), 5, "goblin")
eq(C.boardAmount("invasion", 3, cfg), 20, "invasion")
eq(C.boardAmount("defender", 5000, cfg), 20, "invasion defender (invasion.lua)")
eq(C.boardDef("defender", cfg).stat, "invasion", "defender counts as an invasion trophy")
eq(C.boardAmount("invasionWave", 3, cfg), 20, "invasion boards by prefix")
eq(C.boardAmount("arena1v1", 1200, cfg), nil, "arena gives no guild XP")
eq(C.boardAmount(nil, 1, cfg), nil, "no board")
eq(C.capAmount(50, 380, cfg.sources.dailyCapAll), 20, "all-sources cap")
eq(C.capAmount(50, 400, cfg.sources.dailyCapAll), 0, "all-sources cap reached")
eq(C.capAmount(50, 0, nil), 50, "no cap")

-- ---------------------------------------------------------------- perks
local p1 = C.perksAt(1, cfg)
eq(p1.xp, 0, "level 1: no xp")
eq(p1.hall, false, "level 1: no hall")
eq(p1.scroll, false, "level 1: no scroll")
local p2 = C.perksAt(2, cfg)
eq(p2.xp, 1, "level 2: +1% xp")
eq(C.perksAt(3, cfg).scroll, true, "level 3: scroll")
eq(C.perksAt(4, cfg).loot, 2, "level 4: +2% loot")
eq(C.perksAt(5, cfg).hall, true, "level 5: hall")
eq(C.perksAt(7, cfg).respec, 10, "level 7: respec -10%")
eq(C.perksAt(8, cfg).depotSlots, 20, "level 8: +20 depot slots")
local p10 = C.perksAt(10, cfg)
eq(p10.xp, 3, "level 10: +3% xp")
eq(p10.aura, true, "level 10: aura")
eq(p10.loot, 4, "level 10: +4% loot")
local p20 = C.perksAt(20, cfg)
eq(p20.xp, 5, "level 20: +5% xp")
eq(p20.loot, 5, "level 20: +5% loot")
eq(p20.respec, 20, "level 20: respec -20%")
eq(p20.depotSlots, 60, "level 20: +60 slots")
-- every number perk stays within its cap and never falls with the level
local last = C.perksAt(1, cfg)
for l = 2, 20 do
	local p = C.perksAt(l, cfg)
	for _, k in ipairs({"xp", "loot", "respec", "depotSlots"}) do
		ok(p[k] >= last[k], k .. " never falls at " .. l)
		ok(p[k] <= cfg.caps[k], k .. " capped at " .. l)
	end
	last = p
end
-- caps clamp a config that adds too much
local big = {perks = {{level = 1, xp = 50}, {level = 2, xp = 50}}, caps = {xp = 5}}
eq(C.perksAt(2, big).xp, 5, "clamped by caps")
eq(C.perkText({xp = 1, scroll = true}), "+1% experience, a guild hall scroll every day", "perk text")
local list = C.perkList(4, cfg)
eq(#list, #cfg.perks, "every perk listed")
eq(list[1].active, true, "level 2 perk active at 4")
eq(list[4].active, false, "level 5 perk not active at 4")
eq(C.depotCapacity(1, cfg), 30, "depot base capacity")
eq(C.depotCapacity(13, cfg), 70, "depot capacity at 13")

-- ---------------------------------------------------------------- hall purchase
local function buy(over)
	local info = {guildId = 7, rank = 3, level = 5, hasHall = false, from = "bank", bank = 6000000, money = 0}
	for k, v in pairs(over or {}) do
		info[k] = v
	end
	return C.hallBuyError(info, cfg)
end
eq(buy(), nil, "the leader at level 5 with the bank")
ok(buy({guildId = false}):find("not in a guild"), "no guild")
ok(buy({rank = 2}):find("Only the guild leader"), "vice cannot buy")
ok(buy({level = 4}):find("guild level 5"), "level 5 needed")
ok(buy({hasHall = true}):find("already owns"), "one hall per guild")
ok(buy({bank = 4999999}):find("guild bank holds 4,999,999"), "bank short")
eq(buy({from = "self", money = 5000000}), nil, "own gold")
ok(buy({from = "self", money = 10}):find("You have 10"), "own gold short")
ok(buy({from = "other"}):find("Pay from"), "unknown source")

-- ---------------------------------------------------------------- upgrades
local function up(key, over)
	local info = {rank = 2, level = 20, hasHall = true, upgrades = {}, rentState = "paid", bank = 100000000}
	for k, v in pairs(over or {}) do
		info[k] = v
	end
	return C.upgradeError(key, info, cfg)
end
local err, tier, no = up("hub")
eq(err, nil, "hub buyable")
eq(tier.cost, 2000000, "hub cost")
eq(no, 1, "hub tier 1")
ok(up("hub", {level = 5}):find("guild level 6"), "hub needs level 6")
ok(up("hub", {rank = 1}):find("leader or a vice"), "members cannot buy")
ok(up("hub", {hasHall = false}):find("no guild hall"), "needs the hall")
ok(up("hub", {upgrades = {hub = 1}}):find("highest tier"), "hub has one tier")
ok(up("hub", {rentState = "locked"}):find("rent"), "locked by rent")
eq((up("hub", {rentState = "grace"})), nil, "grace time still allows upgrades")
ok(up("hub", {bank = 1999999}):find("2,000,000"), "bank short")
ok(up("nothing"):find("Unknown"), "unknown upgrade")
ok(up("trophy"):find("Teleport Hub first"), "trophy needs the hub")
eq((up("trophy", {upgrades = {hub = 1}})), nil, "trophy after the hub")
ok(up("decor", {upgrades = {hub = 1}}):find("Trophy Room first"), "decor needs the trophy room")
err, tier, no = up("decor", {upgrades = {hub = 1, trophy = 1}})
eq(err, nil, "decor 1")
eq(tier.cost, 1500000, "decor 1 cost")
err, tier, no = up("decor", {upgrades = {hub = 1, trophy = 1, decor = 1}})
eq(no, 2, "decor tier 2")
eq(tier.cost, 3000000, "decor 2 cost")
ok(up("decor", {level = 15, upgrades = {hub = 1, trophy = 1, decor = 1}}):find("guild level 16"), "decor 2 needs 16")
ok(up("decor", {upgrades = {decor = 3}}):find("highest"), "decor max 3")
eq((up("depot", {level = 9})), nil, "depot at 9")
ok(up("depot", {level = 8}):find("level 9"), "depot needs 9")
local view = C.upgradeView({rank = 2, level = 9, hasHall = true, upgrades = {hub = 1}, rentState = "paid", bank = 3000000}, cfg)
eq(#view, #cfg.hall.upgrades, "every upgrade in the view")
eq(view[1].tier, 1, "hub owned")
eq(view[1].canBuy, false, "hub maxed")
eq(view[4].key, "depot", "depot row")
eq(view[4].canBuy, true, "depot buyable")
eq(view[5].canBuy, false, "trophy needs level 10")

-- ---------------------------------------------------------------- rent
eq(C.rentAmount({}, cfg), 300000, "rent of a bare hall")
eq(C.rentAmount({hub = 1, depot = 1, decor = 2}, cfg), 700000, "rent with 4 tiers")
eq(C.tierCount({hub = 1, decor = 3}), 4, "tier count")
local t0 = 1700000000
eq((C.rentState(t0 + 10, t0, cfg)), "paid", "paid")
eq((C.rentState(t0, t0, cfg)), "grace", "due now: grace")
eq((C.rentState(t0 - 23 * 3600, t0, cfg)), "grace", "23 h late: grace")
eq((C.rentState(t0 - 24 * 3600, t0, cfg)), "locked", "24 h late: locked")
local _, left = C.rentState(t0 + 3600, t0, cfg)
eq(left, 3600, "seconds until due")
local week = 7 * 86400
eq(C.rentPaidUntil(t0 + 100, t0, cfg), t0 + 100 + week, "paying ahead extends the period")
eq(C.rentPaidUntil(t0 - 3600, t0, cfg), t0 - 3600 + week, "paying in the grace time keeps the period")
eq(C.rentPaidUntil(t0 - 3 * 86400, t0, cfg), t0 + week, "a locked hall starts a new week now (no back rent)")
local act = C.activeUpgrades({hub = 1, depot = 1, decor = 0}, "paid")
eq(act.hub, 1, "hub active")
eq(act.decor, nil, "tier 0 is not active")
eq(next(C.activeUpgrades({hub = 1, depot = 1}, "locked")), nil, "nothing works while locked")
eq(C.activeUpgrades({hub = 1}, "grace").hub, 1, "grace keeps them working")

-- ---------------------------------------------------------------- slots
eq(C.allocSlot({}, {}, 64), 1, "first slot")
eq(C.allocSlot({[1] = true, [2] = true}, {}, 64), 3, "next free")
eq(C.allocSlot({[1] = true}, {[2] = true}, 64), 3, "unusable slots skipped")
eq(C.allocSlot({[1] = true, [3] = true}, {}, 64), 2, "a freed slot is reused")
local full = {}
for i = 1, 4 do
	full[i] = true
end
eq(C.allocSlot(full, {}, 4), nil, "all taken")
local o1, o9 = C.slotOrigin(1, cfg), C.slotOrigin(9, cfg)
eq(o1.x, cfg.hall.origin.x, "slot 1 x")
eq(o9.x, cfg.hall.origin.x, "slot 9 starts the second row")
eq(o9.y, cfg.hall.origin.y + cfg.hall.stride, "slot 9 y")
eq(C.slotOrigin(2, cfg).x, cfg.hall.origin.x + cfg.hall.stride, "slot 2 x")
for slot = 1, cfg.hall.maxSlots do
	local L = C.layout(slot, cfg)
	eq(C.slotAt(L.arrival, cfg), slot, "arrival inside slot " .. slot)
	eq(C.slotAt(L.exit, cfg), slot, "exit inside slot " .. slot)
	ok(L.box.x2 - L.box.x1 < cfg.hall.stride, "slots do not overlap " .. slot)
end
local L = C.layout(1, cfg)
eq(C.slotAt({x = L.box.x2 + 1, y = L.box.y1, z = 7}, cfg), nil, "between slots is no slot")
eq(C.slotAt({x = L.box.x1, y = L.box.y1, z = 6}, cfg), nil, "other floor")
eq(C.slotAt({x = 100, y = 100, z = 7}, cfg), nil, "far away")
eq(#C.footprint(1, cfg), (cfg.hall.inner.w + 2) * (cfg.hall.inner.h + 2), "footprint size")
-- every fixture stands on a floor tile (not a wall) and no two share a tile
local seen = {}
local function place(p, what)
	ok(p.x > L.box.x1 and p.x < L.box.x2 and p.y > L.box.y1 and p.y < L.box.y2, what .. " inside the walls")
	local key = p.x .. "," .. p.y
	eq(seen[key], nil, what .. " shares a tile with " .. tostring(seen[key]))
	seen[key] = what
end
place(L.exit, "exit")
place(L.arrival, "arrival")
place(L.bench, "bench")
place(L.depot, "depot")
place(L.dummyMonster, "dummy monster")
for i, p in ipairs(L.hub) do
	place(p, "hub " .. i)
end
for i, p in ipairs(L.dummies) do
	place(p, "dummy " .. i)
end
for i, p in ipairs(L.trophies) do
	place(p, "trophy " .. i)
end
for i, p in ipairs(L.basins) do
	place(p, "basin " .. i)
end
for i, p in ipairs(L.flags) do
	place(p, "flag " .. i)
end
eq(#L.hub, 4, "four hub portals")
ok(#cfg.hall.hub <= #L.hub, "no more destinations than portals")

-- ---------------------------------------------------------------- depot
local function put(over)
	local info = {member = true, active = true, used = 0, capacity = 30, container = false, pickupable = true, count = 1}
	for k, v in pairs(over or {}) do
		info[k] = v
	end
	return C.depotPutError(info, cfg)
end
eq(put(), nil, "a plain item")
ok(put({member = false}):find("Only members"), "non-member")
ok(put({active = false}):find("locked"), "locked depot")
ok(put({container = true}):find("Containers"), "no containers")
ok(put({pickupable = false}):find("cannot"), "not pickupable")
ok(put({count = 101}):find("too large"), "stack too large")
-- the depot returns a plain copy: store, store-bound, locked, quest and decaying items would come out tradable
ok(put({store = true}):find("cannot go into the Guild Stash"), "no store items")
ok(put({storeBound = true}):find("cannot go into the Guild Stash"), "no store-bound items (pouches, Everfull Ration, Nemesis items)")
ok(put({locked = true}):find("locked"), "no locked items")
ok(put({uniqueId = 5000}):find("cannot"), "no quest items")
ok(put({decaying = true}):find("cannot"), "no decaying items")
ok(put({used = 30}):find("full %(30 / 30%)"), "full")
local function take(over)
	local info = {member = true, active = true, rank = 1, takenToday = 0, exists = true}
	for k, v in pairs(over or {}) do
		info[k] = v
	end
	return C.depotTakeError(info, cfg)
end
eq(take(), nil, "member takes")
ok(take({exists = false}):find("no longer"), "already taken (second click)")
ok(take({takenToday = 20}):find("today"), "member daily limit")
eq(take({takenToday = 20, rank = 2}), nil, "vice-leaders have no daily limit")
ok(take({active = false}):find("locked"), "locked")
ok(take({member = false}):find("Only members"), "non-member")
-- attributes
local attrs = {{"@ITEM_ATTRIBUTE_DESCRIPTION", "Level: 53, Holy +3%; a=b:c"}, {"rarity", 5}, {"rarity_fireAbsorb", 3},
	{"chaos_unique", "Widowmaker"}, {"neg", -7}, {"frac", 1.5}}
local text = C.encodeAttrs(attrs)
local back = C.decodeAttrs(text)
eq(#back, #attrs, "round trip count")
for i, a in ipairs(attrs) do
	eq(back[i][1], a[1], "key " .. i)
	eq(back[i][2], a[2], "value " .. i)
end
eq(type(back[2][2]), "number", "numbers stay numbers")
eq(#C.decodeAttrs(""), 0, "empty")
eq(#C.decodeAttrs(nil), 0, "nil")
eq(#C.decodeAttrs("garbage;n:x"), 0, "garbage ignored")
-- log lines
local at = os.time({year = 2026, month = 10, day = 8, hour = 14, min = 5})
eq(C.logLine({at = at, name = "Tester", action = "put", count = 5, item = "Orb of Upheaval"}), "08.10 14:05 Tester put in 5 x Orb of Upheaval", "put line")
eq(C.logLine({at = at, name = "Tester", action = "take", count = 1, item = "dragon robe"}), "08.10 14:05 Tester took out 1 x dragon robe", "take line")
eq(C.logLine({at = at, name = "Ann", action = "deposit", amount = 2500000}), "08.10 14:05 Ann deposited 2,500,000 gold", "deposit line")
eq(C.logLine({at = at, name = "Ann", action = "withdraw", amount = 1000}), "08.10 14:05 Ann withdrew 1,000 gold", "withdraw line")
eq(C.logLine({at = at, name = "Guild", action = "rent", text = "rent paid"}), "08.10 14:05 Guild: rent paid", "other line")
-- the same rows told in pt-BR at display time (the stored text is English): templates with the numbers taken out
dofile("data/scripts/chaos/i18n_core.lua")
local function tpt(key, ...) return ChaosI18n.text("pt-BR", key, ...) end
eq(C.logLine({at = at, name = "Tester", action = "put", count = 5, item = "Orb of Upheaval"}, tpt), "08.10 14:05 Tester colocou 5 x Orb of Upheaval", "put line pt")
eq(C.logLine({at = at, name = "Tester", action = "take", count = 1, item = "dragon robe"}, tpt), "08.10 14:05 Tester retirou 1 x dragon robe", "take line pt")
eq(C.logLine({at = at, name = "Ann", action = "deposit", amount = 2500000}, tpt), "08.10 14:05 Ann depositou 2,500,000 de ouro", "deposit line pt")
eq(C.logLine({at = at, name = "Ann", action = "withdraw", amount = 1000}, tpt), "08.10 14:05 Ann sacou 1,000 de ouro", "withdraw line pt")
eq(C.logLine({at = at, name = "Guild bank", action = "rent", text = "rent paid until 12.11.2026 10:00"}, tpt),
	"08.10 14:05 Banco da guild: aluguel pago até 12.11.2026 10:00", "rent line pt")
eq(C.logLine({at = at, name = "Guild", action = "level", text = "level 3 -> 4"}, tpt), "08.10 14:05 Guild: nível 3 -> 4", "level line pt")
eq(C.logLine({at = at, name = "Ann", action = "hall", text = "bought the guild hall (slot 2, own gold)"}, tpt),
	"08.10 14:05 Ann: comprou o hall da guild (vaga 2, ouro próprio)", "hall line pt")
eq(C.logLine({at = at, name = "Ann", action = "upgrade", text = "Crafting bench tier 2"}, tpt), "08.10 14:05 Ann: Crafting bench nível 2", "upgrade line pt")
eq(C.logLine({at = at, name = "Ann", action = "boss", text = "fed the Summoning Stone 3 x Ember (9 embers)"}, tpt),
	"08.10 14:05 Ann: alimentou a Summoning Stone com 3 x Ember (9 embers)", "boss line pt")
eq(C.logLine({at = at, name = "Guild", action = "war", text = "war stake returned (offer declined)"}, tpt),
	"08.10 14:05 Guild: aposta da guerra devolvida (oferta recusada)", "war line pt")
eq(C.logLine({at = at, name = "Ann", action = "staff", text = "staff credit"}, tpt), "08.10 14:05 Ann: staff credit", "unknown text stays")
eq(C.logLine({at = at, name = "Guild", action = "level", text = "level 3 -> 4"}), "08.10 14:05 Guild: level 3 -> 4", "no translator: English")
-- every stored text the writers use has a rule
for _, w in ipairs(C.LOG_WORDS) do
	assert(ChaosI18n.strings["pt-BR"][w], "pt-BR for " .. w)
end
for _, rule in ipairs(C.LOG_TEXTS) do
	assert(ChaosI18n.strings["pt-BR"][rule[2]], "pt-BR for " .. rule[2])
end

-- ---------------------------------------------------------------- weekly board
local thu = os.time({year = 2026, month = 10, day = 8, hour = 10})
eq(C.weekKey(thu, 6), 20261005, "Thursday -> Monday 5 October")
eq(C.weekKey(os.time({year = 2026, month = 10, day = 5, hour = 5}), 6), 20260928, "Monday before 06:00 is last week")
eq(C.weekKey(os.time({year = 2026, month = 10, day = 5, hour = 7}), 6), 20261005, "Monday after 06:00")
eq(C.weekKey(os.time({year = 2026, month = 10, day = 11, hour = 23}), 6), 20261005, "Sunday night")
local s, f = C.weekBounds(20261005, 6)
eq(os.date("%Y%m%d %H", s), "20261005 06", "week start")
eq(f - s, 7 * 86400, "a week long")
local ranked = C.rankGuilds({{id = 1, points = 50, level = 3}, {id = 2, points = 80, level = 1}, {id = 3, points = 50, level = 5},
	{id = 4, points = 50, level = 5}})
eq(ranked[1].id, 2, "most points first")
eq(ranked[2].id, 3, "then the higher level")
eq(ranked[3].id, 4, "then the lower id")
eq(ranked[4].rank, 4, "ranks numbered")

-- ---------------------------------------------------------------- texts
eq(C.money(0), "0", "money 0")
eq(C.money(999), "999", "money 999")
eq(C.money(1000), "1,000", "money 1000")
eq(C.money(5000000), "5,000,000", "money 5M")
eq(C.money(-1500), "-1,500", "money negative")
eq(C.durationText(90061), "1d 1h", "duration days")
eq(C.durationText(3720), "1h 2m", "duration hours")
eq(C.durationText(-5), "0m", "duration negative")

-- ---------------------------------------------------------------- teleport hub
-- the level a portal announces ("Teleport to X (level N+)") is enforced when stepping in (2026-10-20: it was not)
local hubDest = cfg.hall.hub[1]
ok(hubDest.level and hubDest.level > 0, "every hub destination has a level")
eq(C.hubGate(hubDest, hubDest.level), nil, "the announced level may enter")
eq(C.hubGate(hubDest, hubDest.level + 100), nil, "a higher level may enter")
local why = C.hubGate(hubDest, hubDest.level - 1)
ok(why and why:find(tostring(hubDest.level), 1, true), "one level short is refused and the text names the level")
ok(C.hubGate(hubDest, 1), "level 1 is refused")
eq(C.hubGate({name = "Anywhere", pos = hubDest.pos}, 1), nil, "a destination without a level is open")
eq(C.hubGate(nil, 500), "nowhere", "no destination")
for i, d in ipairs(cfg.hall.hub) do
	ok(C.hubGate(d, d.level - 1), "destination " .. i .. " is gated by its own level")
end
-- landing: the nearest free tile within 3, scanning outwards; nil when there is none
local free = {}
local function isFree(x, y, z)
	return free[x .. "," .. y .. "," .. z] == true
end
eq(C.landingSpot({x = 10, y = 10, z = 7}, isFree), nil, "no free tile, no landing")
free["12,13,7"] = true
local lp = C.landingSpot({x = 10, y = 10, z = 7}, isFree)
ok(lp and lp.x == 12 and lp.y == 13 and lp.z == 7, "finds a free tile 3 away")
free["10,10,7"] = true
lp = C.landingSpot({x = 10, y = 10, z = 7}, isFree)
ok(lp and lp.x == 10 and lp.y == 10, "the exact tile first")
free = {["14,10,7"] = true}
eq(C.landingSpot({x = 10, y = 10, z = 7}, isFree), nil, "4 tiles away is out of reach")
-- the hub check: which destinations would answer "leads nowhere"
local bad = C.hubDeadEnds(cfg.hall.hub, function(x, y, z) return x == cfg.hall.hub[2].pos.x and y == cfg.hall.hub[2].pos.y end)
eq(#bad, 3, "three of four have no landing")
eq(bad[1], 1, "the first is a dead end")
eq(#C.hubDeadEnds(cfg.hall.hub, function() return true end), 0, "all land when everything is free")

print(string.format("guild tests OK (%d checks)", checks))

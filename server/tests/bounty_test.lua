-- Run from the server/ folder: luajit tests/bounty_test.lua (and lua5.3; CI runs both)
-- Pure logic of the bounty board (bounty_core.lua): seeded daily roll, bands, kill matching, party credit,
-- progress, rewards, the accept rules and expiry. Uses the real bounty_config.lua and bounty_pool.lua.
dofile("data/scripts/chaos/bounty_core.lua")
local B = ChaosBounty
local cfg = dofile("data/scripts/chaos/bounty_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- generator
local r1, r2 = B.rng(12345), B.rng(12345)
for _ = 1, 100 do
	eq(r1(), r2(), "same seed, same sequence")
end
local r3 = B.rng(1)
for _ = 1, 1000 do
	local v = r3(3, 7)
	assert(v >= 3 and v <= 7 and v == math.floor(v), "range")
end
-- known first values (pins the algorithm: a change here changes every board)
local g = B.rng(42)
local first = {g(), g(), g()}
local h = B.rng(42)
eq(h(), first[1], "pinned 1")

-- ---------------------------------------------------------------- days, rolls and weeks
local function t(y, mo, d, hh, mi)
	return os.time({year = y, month = mo, day = d, hour = hh, min = mi or 0, sec = 0})
end
eq(B.day(t(2026, 10, 8, 5, 59), cfg), 20261007, "before 06:00 is still the previous bounty day")
eq(B.day(t(2026, 10, 8, 6, 0), cfg), 20261008, "06:00 starts the new day")
eq(B.nextRoll(t(2026, 10, 8, 5, 0), cfg), t(2026, 10, 8, 6, 0), "next roll today")
eq(B.nextRoll(t(2026, 10, 8, 7, 0), cfg), t(2026, 10, 9, 6, 0), "next roll tomorrow")
eq(B.nextRoll(t(2026, 12, 31, 23, 0), cfg), t(2027, 1, 1, 6, 0), "over the year end")
-- 2026-10-05 is a Monday
eq(B.week(t(2026, 10, 8, 12), cfg), 20261005, "Thursday -> Monday")
eq(B.week(t(2026, 10, 5, 6, 0), cfg), 20261005, "Monday 06:00 starts the week")
eq(B.week(t(2026, 10, 5, 5, 0), cfg), 20260928, "Monday 05:00 is still last week (Sunday's bounty day)")
eq(B.week(t(2026, 10, 11, 23), cfg), 20261005, "Sunday")

-- ---------------------------------------------------------------- bands
eq(B.bandOf(1, cfg), 1, "below 8 -> first band")
eq(B.bandOf(49, cfg), 1)
eq(B.bandOf(50, cfg), 2)
eq(B.bandOf(299, cfg), 3)
eq(B.bandOf(800, cfg), 6)
eq(B.bandOf(5000, cfg), 6)
local vis, own = B.visibleBands(1000, cfg)
eq(own, 6); eq(#vis, 2, "top band sees itself and the one below"); eq(vis[1], 5)
vis, own = B.visibleBands(200, cfg)
eq(#vis, 3); eq(vis[1], 2); eq(vis[3], 4)
vis = B.visibleBands(10, cfg)
eq(#vis, 2); eq(vis[1], 1)
eq(B.bandLabel(cfg.bands[2]), "Level 50-149")
eq(B.bandLabel(cfg.bands[6]), "Level 800+")

-- ---------------------------------------------------------------- the roll
local day = 20261008
local a = B.roll(day, cfg, pool)
local b = B.roll(day, cfg, pool)
local other = B.roll(20261009, cfg, pool)
local differs = false
for i = 1, #cfg.bands do
	local ca, cb = a.bands[i].contracts, b.bands[i].contracts
	assert(#ca >= 3 and #ca <= #cfg.slots, "3 to 4 contracts in band " .. i)
	eq(#ca, #cb, "same count")
	local names = {}
	for j, c in ipairs(ca) do
		eq(c.name, cb[j].name, "same day, same monster")
		eq(c.count, cb[j].count, "same day, same count")
		eq(c.key, i .. "-" .. c.slot, "key")
		assert(not names[c.name], "monsters differ inside a band")
		names[c.name] = true
		local band = cfg.bands[i]
		assert(c.level >= band.pick[1] and c.level <= band.pick[2], "monster level in the band window")
		assert(c.count >= 1, "count")
		if c.type == "elite" then
			assert(c.tier == "magic" or c.tier == "rare", "elite tier")
		end
		if (other.bands[i].contracts[j] or {}).name ~= c.name then
			differs = true
		end
	end
	-- the fourth slot is a boss when a boss fits the band
	local bosses = 0
	for _, e in ipairs(pool.bosses) do
		if e.level >= cfg.bands[i].pick[1] and e.level <= cfg.bands[i].pick[2] then
			bosses = bosses + 1
		end
	end
	eq(ca[4].type, bosses > 0 and "boss" or "hunt", "slot 4 in band " .. i)
	eq(ca[3].type, "elite", "slot 3 elite in band " .. i)
end
assert(differs, "another day gives another board")
assert(a.byKey["2-1"] and a.byName[a.byKey["2-1"].name:lower()], "indexes")

-- a small fixed pool: exact behaviour of the slots and the kill counts
local small = {
	hunt = {
		{name = "Rat", level = 10, spawns = 100, look = 21},
		{name = "Wolf", level = 12, spawns = 10, look = 27},
		{name = "Troll", level = 15, spawns = 30, look = 15}
	},
	bosses = {}
}
local sb = B.roll(day, cfg, small)
local c1 = sb.bands[1].contracts
eq(#c1, 3, "three distinct monsters only: the boss slot falls back to hunt and finds none left")
for _, c in ipairs(c1) do
	if c.type == "hunt" and c.name == "Wolf" then
		eq(c.count % 5, 0, "few spawns: multiple of 5")
		assert(c.count <= math.ceil(cfg.bands[1].kills[2] * cfg.fewSpawnsMult), "few spawns: fewer kills")
	elseif c.type == "hunt" then
		eq(c.count % 10, 0, "multiple of 10")
		assert(c.count >= cfg.bands[1].kills[1] and c.count <= cfg.bands[1].kills[2], "kills in range")
	else
		eq(c.type, "elite")
		assert(c.name ~= "Wolf", "elite needs eliteMinSpawns")
	end
end

-- pack combat (pace): cfg.goalMult multiplies the kill counts (the same roll, x the monster's factor)
do
	cfg.goalMult = function(mon) return mon.name == "Troll" and 5 or 1 end
	local pb = B.roll(day, cfg, small)
	cfg.goalMult = nil
	for i, c in ipairs(pb.bands[1].contracts) do
		local plain = c1[i]
		eq(c.name, plain.name, "pace: the same monsters")
		if c.name == "Troll" and c.type == "hunt" then
			eq(c.count % 10, 0, "pace: hunt kills a multiple of 10")
			assert(math.abs(c.count - plain.count * 5) <= 25, "pace: hunt kills x5 (" .. c.count .. ")")
		elseif c.name == "Troll" then
			eq(c.count, plain.count * 5, "pace: elite kills x5")
		else
			eq(c.count, plain.count, "pace: factor 1 unchanged")
		end
	end
	-- the real curves: a level 15 pool monster (hunting level 30) and a level 980 level-scaled one
	dofile("data/scripts/chaos/pace_core.lua")
	local pc = dofile("data/scripts/chaos/pace_config.lua")
	local g1 = ChaosPaceCore.goalOfEntry(pc, {level = 6, exp = 12, health = 30})
	eq(g1, 1, "pace: a level 12 hunt keeps its goals")
	local g2 = ChaosPaceCore.goalOfEntry(pc, {level = 980, exp = 13900, health = 22000})
	assert(g2 > 20, "pace: a level-scaled late-game monster needs 20x+ the kills")
end
eq(#sb.bands[2].contracts, 0, "nothing fits band 2")

-- ---------------------------------------------------------------- kills
local hunt = {key = "1-1", band = 1, type = "hunt", name = "Dragon", count = 10}
local elite = {key = "1-3", band = 1, type = "elite", name = "Dragon", tier = "rare", count = 2}
assert(B.matches(hunt, "dragon", "normal"), "name match is case-insensitive")
assert(not B.matches(hunt, "Dragon Lord", "normal"), "other monster")
assert(not B.matches(elite, "Dragon", "magic"), "magic is below rare")
assert(B.matches(elite, "Dragon", "rare"), "rare")
assert(B.matches(elite, "Dragon", "legendary"), "legendary counts for rare")
assert(not B.matches(elite, "Dragon", "boss"), "boss tier is not an elite")
assert(not B.matches(elite, "Dragon", nil), "normal")

-- party credit
local function P(id, x, y, z, party)
	return {id = id, pos = {x = x, y = y, z = z}, party = party}
end
local party = {}
local k = P(1, 100, 100, 7, party)
local near = P(2, 110, 120, 7, party)
local far = P(3, 100, 170, 7, party)
local below = P(4, 100, 100, 8, party)
party[1], party[2], party[3], party[4] = k, near, far, below
local loner = P(5, 100, 101, 7, nil)
local loner2 = P(6, 101, 171, 7, nil)
local function membersOf(p) return p.party end
local function posOf(p) return p.pos end
local function idOf(p) return p.id end
local got = B.credit({k}, membersOf, posOf, cfg.partyRange, idOf)
local ids = {}
for _, p in ipairs(got) do ids[p.id] = (ids[p.id] or 0) + 1 end
eq(ids[1], 1, "killer once"); eq(ids[2], 1, "party member in range")
eq(ids[3], nil, "party member out of range"); eq(ids[4], nil, "party member on another floor")
eq(ids[5], nil, "a stranger next to the killer gets nothing")
got = B.credit({loner}, membersOf, posOf, cfg.partyRange, idOf)
eq(#got, 1, "no party: only the killer")
got = B.credit({k, near}, membersOf, posOf, cfg.partyRange, idOf)
eq(#got, 2, "last hit and most damage in the same party: each once")
got = B.credit({far, loner2}, membersOf, posOf, cfg.partyRange, idOf)
ids = {}
for _, p in ipairs(got) do ids[p.id] = true end
assert(ids[3] and ids[6] and not ids[1] and not ids[2], "range is measured from each killer")

-- progress and milestones
local e = {progress = 0, required = 8, status = 0}
local seen = {}
local doneAt
for i = 1, 10 do
	local crossed, done = B.addKill(e, cfg.progressNotices)
	if crossed then
		for _, pct in ipairs(crossed) do seen[#seen + 1] = pct .. "@" .. i end
	end
	if done then doneAt = i end
end
eq(table.concat(seen, ","), "25@2,50@4,75@6", "milestones")
eq(doneAt, 8, "completed at the required count")
eq(e.progress, 8, "never above required")
eq(e.status, 1, "completed")
eq(B.addKill(e, cfg.progressNotices), nil, "no progress after completion")
local one = {progress = 0, required = 1, status = 0}
local crossed, done = B.addKill(one, cfg.progressNotices)
eq(#crossed, 0, "a single kill contract has no milestones"); eq(done, true)

-- ---------------------------------------------------------------- rewards
local r = B.reward({band = 1, type = "hunt", count = 0}, cfg, 30)
eq(r.gold, cfg.bands[1].reward.gold); eq(r.chaos, 1); eq(r.divine, 0)
r = B.reward({band = 6, type = "elite", count = 0}, cfg, 1000)
eq(r.gold, math.floor(cfg.bands[6].reward.gold * cfg.typeMult.elite)); eq(r.chaos, 9); eq(r.divine, 3)
r = B.reward({band = 5, type = "boss", count = 1}, cfg, 600)
eq(r.divine, 2, "divine rounded up")
eq(B.expForLevel(1), 100); eq(B.expForLevel(100), 495100); eq(B.expForLevel(8), 2900)

-- experience (2026-10-22): expShare percent of the base experience of the contract's kills at the player's stage,
-- between expFloor and expCap percent of a level (L = min(player level, band max))
local kc = {}
for k, v in pairs(cfg) do kc[k] = v end
kc.killBase = nil -- the pool experience, no pace
kc.expShare = {hunt = 40, elite = 50, boss = 100}
kc.expFloor = {hunt = 10, elite = 10, boss = 50}
kc.expCap = {hunt = 2000, elite = 2000, boss = 2000}
kc.tierXp = {magic = 2, rare = 4}
kc.eliteSearch = {magic = 12, rare = 50}
local gazer = {band = 1, type = "hunt", name = "Gazer", count = 90, exp = 90}
eq(B.contractKillExp(gazer, kc, 10), 81000, "count x exp x stage")
eq(B.reward(gazer, kc, 8, 10).exp, 32400, "40% of the kills at level 8, stage 10 (was 87)")
eq(B.reward(gazer, kc, 8, 1).exp, 3240, "the stage counts")
eq(B.reward(gazer, kc, 8).exp, 3240, "no stage: 1")
-- elite: each counted kill x its tier, plus the kills of the type made while looking for the tier
local el = {band = 1, type = "elite", tier = "magic", name = "Gazer", count = 5, exp = 90}
eq(B.contractKillExp(el, kc, 10), 5 * (2 + 11) * 90 * 10, "elite kills")
el.tier = "rare"
eq(B.contractKillExp(el, kc, 10), 5 * (4 + 49) * 90 * 10, "rare elite kills")
eq(B.reward(el, kc, 30, 50).exp, math.floor(5 * 53 * 90 * 50 * 50 / 100), "elite share")
-- floor: a monster with little experience still pays expFloor percent of a level
local tiny = {band = 1, type = "hunt", name = "Rat", count = 10, exp = 5}
eq(B.reward(tiny, kc, 30, 50).exp, math.floor(B.expForLevel(30) * 10 / 100), "floor")
local boss = {band = 1, type = "boss", name = "Grimebeard", count = 1, exp = 375}
eq(B.reward(boss, kc, 8, 10).exp, 3750, "boss: its kill")
eq(B.reward(boss, kc, 40, 50).exp, math.floor(B.expForLevel(40) / 2), "boss floor half a level")
-- cap: a low character finishing a contract of the band above pays at most expCap percent of its own level
local big = {band = 2, type = "hunt", name = "Behemoth", count = 400, exp = 2500}
eq(B.reward(big, kc, 30, 50).exp, B.expForLevel(30) * 20, "capped at 20 levels of level 30")
-- a high character on a lower band: floor and cap at the band's max level, the kills at the player's own stage
eq(B.reward(tiny, kc, 400, 33).exp, math.floor(B.expForLevel(49) * 10 / 100), "floor at the band max")
eq(B.reward(big, kc, 1000, 13).exp, math.floor(400 * 2500 * 13 * 40 / 100), "kills at the player's stage")
-- no experience in the entry (a rerolled contract whose monster left the pool): the floor
eq(B.reward({band = 3, type = "hunt", name = "?", count = 100}, kc, 200, 41).exp, math.floor(B.expForLevel(200) / 10))
-- the hook: the pace curve x the pool experience; bosses are never paced
local fakeP = {entryLevel = function(_, e) return e.level * 2, false end,
	factors = function(_, lvl) return {xp = lvl >= 100 and 0.5 or 1} end}
eq(B.monsterKillBase({type = "hunt", exp = 1000, level = 60}, fakeP, {}), 500, "paced")
eq(B.monsterKillBase({type = "boss", exp = 1000, level = 60}, fakeP, {}), 1000, "boss unpaced")
eq(B.monsterKillBase({type = "hunt", level = 60}, fakeP, {}), 0, "no experience")
eq(B.monsterKillBase({type = "hunt", exp = 1000, level = 60}), 1000, "no pace")
-- a level-scaled monster: x the engine's 0.03 L (above 1 only), then the pace curve; a boss only the level factor
local scaledP = {entryLevel = function(_, e) return e.level, true end, factors = function() return {xp = 0.5} end}
eq(B.monsterKillBase({type = "hunt", exp = 1000, level = 700}, scaledP, {}), 1000 * 21 * 0.5, "level factor x pace")
eq(B.monsterKillBase({type = "boss", exp = 1000, level = 700}, scaledP, {}), 1000 * 21, "boss: level factor only")
eq(B.monsterKillBase({type = "hunt", exp = 1000, level = 20}, scaledP, {}), 500, "factor below 1 is not applied")
-- elite and boss contracts pay at least the mean hunt reward of their band (B.huntMean), still at most the cap
local h1 = {band = 1, type = "hunt", count = 100, exp = 100}
local h2 = {band = 1, type = "hunt", count = 100, exp = 300}
local hm = B.huntMean(boss, kc, 30, 50, {h1, h2, boss})
eq(hm, (B.expReward(h1, kc, 30, 50) + B.expReward(h2, kc, 30, 50)) / 2, "mean of the band's hunts")
eq(B.huntMean(h1, kc, 30, 50, {h1, h2}), nil, "a hunt has none")
eq(B.reward(boss, kc, 30, 50, hm).exp, math.floor(hm), "boss lifted to the hunt mean")
eq(B.reward(el, kc, 30, 50, hm).exp, B.reward(el, kc, 30, 50).exp, "an elite above the mean keeps its own")
eq(B.reward(boss, kc, 8, 10, 1e12).exp, B.expForLevel(8) * 20, "the cap still holds")
-- no hunt on the board for the band: the band's pool median at the middle kill count
local hp = B.huntMean(boss, kc, 30, 50, {}, pool)
assert(hp and hp > 0, "pool median")
eq(B.huntPoolMedian(1, kc, pool), B.huntPoolMedian(1, kc, pool), "cached")
eq(B.huntMean(boss, kc, 30, 50, {}), nil, "no board and no pool")
-- with the real config and pace: every board contract of 30 days pays between the floor and the cap, at every level
ChaosPaceCore = nil
local P = dofile("data/scripts/chaos/pace_core.lua") or ChaosPaceCore
local pcfg = dofile("data/scripts/chaos/pace_config.lua")
local rc = {}
for k, v in pairs(cfg) do rc[k] = v end
rc.goalMult = function(m) return P.goalOfEntry(pcfg, m) end
rc.killBase = function(c) return B.monsterKillBase(c, P, pcfg) end
for d = 1, 30 do
	local bd = B.roll(20261000 + d, rc, pool)
	for _, lvl in ipairs({8, 30, 100, 250, 400, 650, 900}) do
		for _, bi in ipairs(B.visibleBands(lvl, rc)) do
			local band = rc.bands[bi]
			local L = math.max(1, math.min(lvl, band.max))
			local cs = bd.bands[bi].contracts
			for _, c in ipairs(cs) do
				assert(c.exp and c.exp > 0, "contracts carry the pool experience")
				local mean = B.huntMean(c, rc, lvl, 20, cs, pool)
				local e = B.reward(c, rc, lvl, 20, mean).exp
				if mean then
					assert(e >= math.floor(mean), "elite and boss never below the band's hunt mean " .. c.name)
				end
				assert(e >= math.floor(B.expForLevel(L) * rc.expFloor[c.type] / 100), "floor " .. c.name)
				assert(e <= B.expForLevel(L) * rc.expCap[c.type] / 100, "cap " .. c.name)
			end
		end
	end
end
-- party credit: a member below the contract band's min level gets no credit for others' kills
assert(B.partyCounts({band = 2}, cfg, cfg.bands[2].min), "at the band min")
assert(not B.partyCounts({band = 2}, cfg, cfg.bands[2].min - 1), "below the band min")
assert(B.partyCounts({band = 1}, cfg, 8))
local w = B.weeklyReward(6, cfg)
eq(w.chaos, cfg.bands[6].weekly.chaos); eq(w.divine, cfg.bands[6].weekly.divine)
eq(B.weeklyReward(99, cfg).chaos, cfg.bands[6].weekly.chaos, "clamped")
for i = 2, #cfg.bands do
	assert(cfg.bands[i].reward.gold > cfg.bands[i - 1].reward.gold, "gold grows with the band")
	assert(cfg.bands[i].reward.chaos >= cfg.bands[i - 1].reward.chaos, "orbs grow with the band")
end

-- ---------------------------------------------------------------- accepting, limit and expiry
local board = B.roll(day, cfg, pool)
local entries = {}
local visible = B.visibleBands(200, cfg) -- bands 2, 3, 4
local okKeys = {}
for _, i in ipairs(visible) do
	for _, c in ipairs(board.bands[i].contracts) do okKeys[#okKeys + 1] = c.key end
end
local ok, why = B.canAccept(board, entries, "9-1", visible, cfg)
assert(not ok and why:find("not on today"), "unknown key")
ok, why = B.canAccept(board, entries, "6-1", visible, cfg)
assert(not ok and why:find("level"), "band not visible")
for i = 1, cfg.maxActive do
	ok = B.canAccept(board, entries, okKeys[i], visible, cfg)
	assert(ok, "accept " .. i)
	entries[okKeys[i]] = {status = 0, day = day}
end
ok, why = B.canAccept(board, entries, okKeys[1], visible, cfg)
assert(not ok and why:find("already accepted"), "no duplicate")
ok, why = B.canAccept(board, entries, okKeys[cfg.maxActive + 1], visible, cfg)
assert(not ok and why:find("at most " .. cfg.maxActive), "limit of " .. cfg.maxActive)
-- completing one frees a slot, but the completed one cannot be taken again today
entries[okKeys[1]].status = 1
eq(B.activeCount(entries, day), cfg.maxActive - 1)
ok = B.canAccept(board, entries, okKeys[cfg.maxActive + 1], visible, cfg)
assert(ok, "slot freed by a completion")
ok, why = B.canAccept(board, entries, okKeys[1], visible, cfg)
assert(not ok and why:find("completed"), "completed today")
-- the next roll: everything of the old day expires
local nextBoard = B.roll(day + 1, cfg, pool)
eq(B.activeCount(entries, nextBoard.day), 0, "old contracts do not count against the limit")
eq(B.expire(entries, nextBoard.day), cfg.maxActive, "all expired")
eq(next(entries), nil, "nothing left")

-- ---------------------------------------------------------------- rerolls (Candlemarks)
eq(cfg.rerollStorage, 7102403, "reroll charges storage")
do
	local b = B.roll(day, cfg, pool)
	for _, band in ipairs(b.bands) do
		local avoid = {}
		for _, c in ipairs(band.contracts) do avoid[c.name:lower()] = true end
		for _, c in ipairs(band.contracts) do
			local nc = B.rerollContract(c, cfg, pool, avoid, B.rng(1234 + band.index))
			if nc then
				eq(nc.key, c.key, "same key " .. c.key)
				eq(nc.type, c.type, "same type " .. c.key)
				eq(nc.tier, c.tier, "same elite tier " .. c.key)
				assert(not avoid[nc.name:lower()], "a monster off the band's board: " .. nc.name)
				assert(nc.count and nc.count > 0, "a count " .. c.key)
				local inBand = false
				for _, e in ipairs(c.type == "boss" and pool.bosses or pool.hunt) do
					if e.name == nc.name and e.level >= cfg.bands[c.band].pick[1] and e.level <= cfg.bands[c.band].pick[2] then
						inBand = true
					end
				end
				assert(inBand, "from the band's window: " .. nc.name)
				-- the player's override: the entry names the new monster
				local e = {monster = nc.name, required = nc.count, status = 0}
				local own = B.overrideOf(c, e, function() return nil end)
				eq(own.name, nc.name, "override name"); eq(own.count, nc.count, "override count")
				assert(own.rerolled, "marked as rerolled")
				assert(B.matches(own, nc.name, "legendary"), "kills of the new monster count")
				assert(not B.matches(own, c.name, "legendary"), "the old monster no longer counts")
			end
		end
	end
	local c = b.bands[1].contracts[1]
	eq(B.overrideOf(c, {monster = c.name, required = 5}), c, "not rerolled: the board's contract")
	eq(B.overrideOf(c, nil), c, "no entry: the board's contract")
	eq(B.rerollContract({band = 99, name = "x", type = "hunt"}, cfg, pool, {}, B.rng(1)), nil, "unknown band: none")
	local everything = {}
	for _, e in ipairs(pool.hunt) do everything[e.name:lower()] = true end
	local hunt
	for _, bc in ipairs(b.bands[1].contracts) do if bc.type == "hunt" then hunt = bc end end
	eq(B.rerollContract(hunt, cfg, pool, everything, B.rng(1)), nil, "nothing else fits: none")
end

print("bounty: all asserts passed")

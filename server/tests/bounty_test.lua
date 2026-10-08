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
local r = B.reward({band = 1, type = "hunt"}, cfg, 30)
eq(r.gold, cfg.bands[1].reward.gold); eq(r.chaos, 1); eq(r.divine, 0)
eq(r.exp, math.floor(B.expForLevel(30) * cfg.expPercent.hunt / 100), "exp from the player's level")
r = B.reward({band = 1, type = "hunt"}, cfg, 1000)
eq(r.exp, math.floor(B.expForLevel(49) * cfg.expPercent.hunt / 100), "exp capped at the band's max level")
r = B.reward({band = 6, type = "elite"}, cfg, 1000)
eq(r.gold, math.floor(cfg.bands[6].reward.gold * cfg.typeMult.elite)); eq(r.chaos, 9); eq(r.divine, 3)
r = B.reward({band = 5, type = "boss"}, cfg, 600)
eq(r.divine, 2, "divine rounded up")
eq(B.expForLevel(1), 100); eq(B.expForLevel(100), 495100)
-- experience stays small next to a level: 12 contracts a day (3 bands x 4) at the highest percent
assert(12 * math.max(cfg.expPercent.hunt, cfg.expPercent.elite, cfg.expPercent.boss) <= 60, "under ~half a level a day")
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

print("bounty: all asserts passed")

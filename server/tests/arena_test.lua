-- Run from the server/ folder: luajit tests/arena_test.lua (pure part of the arena; CI runs it with LuaJIT and Lua 5.3)
local cfg = dofile("data/scripts/chaos/arena_config.lua")
dofile("data/scripts/chaos/arena_core.lua")
local A = ChaosArenaCore

local fails, count = 0, 0
local function check(cond, name)
  count = count + 1
  if not cond then
    fails = fails + 1
    print("FAIL: " .. name)
  end
end
local function eq(a, b, name)
  check(a == b, name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function near(a, b, eps, name)
  check(math.abs(a - b) <= (eps or 1e-9), name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- rating maths
near(A.expected(1000, 1000), 0.5, 1e-12, "equal ratings expect 0.5")
near(A.expected(1400, 1000), 1 / (1 + 10 ^ -1), 1e-12, "400 above expects 10:1")
near(A.expected(1000, 1400) + A.expected(1400, 1000), 1, 1e-12, "expectations sum to 1")
eq(A.kFactor(cfg, 0), 40, "provisional K")
eq(A.kFactor(cfg, 9), 40, "provisional K up to 9 matches")
eq(A.kFactor(cfg, 10), 24, "settled K")

local new, d = A.rate(cfg, 1000, 1000, 1, 0)
eq(new, 1020, "new player beats equal: +20")
eq(d, 20, "delta +20")
new, d = A.rate(cfg, 1000, 1000, 0, 0)
eq(new, 980, "new player loses to equal: -20")
new, d = A.rate(cfg, 1000, 1000, 0.5, 20)
eq(d, 0, "draw between equals: 0")
new, d = A.rate(cfg, 1200, 1000, 1, 20)
eq(d, 6, "favourite wins: +6 (24 x 0.24)")
new, d = A.rate(cfg, 1000, 1200, 1, 20)
eq(d, 18, "underdog wins: +18")
new, d = A.rate(cfg, 105, 300, 0, 20)
eq(new, 100, "rating floor 100 (105 - 6 would be 99)")
eq(d, -5, "delta reports what was really lost at the floor")

-- 1v1 match
local teams = A.rateMatch(cfg, {{{rating = 1000, matches = 0}}, {{rating = 1000, matches = 30}}}, 1)
eq(teams[1][1].after, 1020, "1v1 winner (provisional)")
eq(teams[2][1].after, 988, "1v1 loser (settled K 24)")
eq(teams[1][1].score, 1, "winner score 1")
eq(teams[2][1].delta, -12, "loser delta")

-- draw
teams = A.rateMatch(cfg, {{{rating = 1100, matches = 20}}, {{rating = 1000, matches = 20}}}, 0)
eq(teams[1][1].delta, -3, "draw: favourite loses a little")
eq(teams[2][1].delta, 3, "draw: underdog gains a little")

-- 2v2: every player against the other team's average; a leaver scores 0 even when the team wins
teams = A.rateMatch(cfg, {
  {{rating = 1200, matches = 20}, {rating = 1000, matches = 20, left = true}},
  {{rating = 1100, matches = 20}, {rating = 1100, matches = 20}}}, 1)
eq(teams[1][1].delta, 9, "2v2 winner 1200 vs avg 1100: +9")
eq(teams[1][2].score, 0, "2v2 leaver scores 0")
eq(teams[1][2].delta, -9, "2v2 leaver 1000 vs avg 1100 loses 9")
eq(teams[2][1].delta, -12, "2v2 loser 1100 vs avg 1100: -12")
eq(teams[2][2].before, 1100, "before kept")

-- ---------------------------------------------------------------- matchmaking window
eq(A.window(cfg, 0), 100, "window at 0 s")
eq(A.window(cfg, 9), 100, "window at 9 s")
eq(A.window(cfg, 10), 150, "window at 10 s")
eq(A.window(cfg, 45), 300, "window at 45 s")
eq(A.window(cfg, 3600), 600, "window capped")

local now = 1000
local function entry(id, rating, joined, levels, mode)
  return {id = id, mode = mode or "1v1", rating = rating, joined = joined, levels = levels or {500}, parties = {}, ips = {}}
end
check(A.canPair(cfg, entry(1, 1000, now), entry(2, 1090, now), now), "90 apart pairs at once")
check(not A.canPair(cfg, entry(1, 1000, now), entry(2, 1200, now), now), "200 apart does not pair at once")
check(A.canPair(cfg, entry(1, 1000, now - 20), entry(2, 1200, now), now), "200 apart pairs after 20 s (the older entry's window)")
check(not A.canPair(cfg, entry(1, 1000, now), entry(2, 1000, now, nil, "2v2"), now), "different modes never pair")
local pa, pb = entry(1, 1000, now), entry(2, 1000, now)
pa.parties[7], pb.parties[7] = true, true
check(not A.canPair(cfg, pa, pb, now), "same party never pairs in 1v1")
pa, pb = entry(1, 1000, now), entry(2, 1000, now)
pa.ips[123], pb.ips[123] = true, true
check(not A.canPair(cfg, pa, pb, now), "same connection never pairs")

-- greedy pairing: oldest first, closest rating
local list = {entry(1, 1000, now - 30), entry(2, 1300, now - 5), entry(3, 1150, now - 10), entry(4, 1250, now)}
local pairs_ = A.findMatches(cfg, list, now)
eq(#pairs_, 2, "two pairs")
eq(pairs_[1][1].id, 1, "oldest picks first")
eq(pairs_[1][2].id, 3, "oldest takes the closest it may (1150)")
eq(pairs_[2][1].id, 2, "second pair")
eq(pairs_[2][2].id, 4, "second pair partner")
pairs_ = A.findMatches(cfg, {entry(1, 1000, now), entry(2, 1500, now)}, now)
eq(#pairs_, 0, "too far apart: nobody pairs")
pairs_ = A.findMatches(cfg, {entry(1, 1000, now - 80), entry(2, 1500, now)}, now)
eq(#pairs_, 1, "after 80 s the window reaches 500")

-- ---------------------------------------------------------------- level rule
check(A.levelsOk(cfg, {800, 1000}), "800 vs 1000 fights (80%)")
check(not A.levelsOk(cfg, {799, 1000}), "799 vs 1000 does not")
check(not A.levelsOk(cfg, {300, 1000}), "300 vs 1000 never")
check(A.levelsOk(cfg, {50, 70}), "low levels within 20 levels")
check(not A.levelsOk(cfg, {50, 71}), "50 vs 71: 21 levels and below 80%")
check(A.levelsOk(cfg, {400, 450, 500, 420}), "2v2 every level within 80% of the highest")
check(not A.levelsOk(cfg, {300, 450, 500, 420}), "2v2 one low player blocks the match")
check(not A.canPair(cfg, entry(1, 1000, now, {300}), entry(2, 1000, now, {1000}), now), "level rule in canPair")
local lo, hi = A.levelRange(cfg, 1000)
eq(lo, 800, "range low")
eq(hi, 1250, "range high")
lo, hi = A.levelRange(cfg, 60)
eq(lo, 40, "range low uses the slack")
eq(hi, 80, "range high uses the slack")

-- ---------------------------------------------------------------- death catch
local p, s, caught = A.catchDamage(500, 200, 100)
check(p == 200 and s == 100 and not caught, "a hit below health passes")
p, s, caught = A.catchDamage(500, 450, 100)
check(caught, "a lethal hit is caught")
eq(p + s, 499, "the caught hit leaves 1 health")
eq(p, 450, "primary kept first")
eq(s, 49, "secondary cut")
p, s, caught = A.catchDamage(500, 500, 0)
check(caught and p == 499 and s == 0, "exactly lethal is caught")
p, s, caught = A.catchDamage(1, 30, 30)
check(caught and p == 0 and s == 0, "at 1 health nothing more is taken")
p, s, caught = A.catchDamage(300, 5000, 0)
check(caught and p == 299, "overkill is caught")

-- who may hit whom
local t1, t2 = {team = 1}, {team = 2}
check(not A.canHit("countdown", t1, t2, false), "no hits in the countdown")
check(not A.canHit("countdown", nil, t2, false), "no damage at all in the countdown")
check(A.canHit("fight", t1, t2, false), "opponents in the fight")
check(not A.canHit("fight", t1, {team = 1}, false), "no team damage")
check(not A.canHit("fight", t1, {team = 2, defeated = true}, false), "the defeated cannot be hit")
check(not A.canHit("fight", {team = 1, defeated = true}, t2, false), "the defeated cannot hit")
check(A.canHit("fight", t1, t1, true), "own damage in the fight")
check(A.canHit("fight", nil, t2, false), "damage without a player behind it in the fight")
check(not A.canHit("done", t1, t2, false), "no hits after the end")
check(A.canHit("countdown", t1, nil, false), "not a fighter: not our business")

-- ---------------------------------------------------------------- timeout decision and result
local w, a, b = A.timeoutWinner({{{health = 600, maxHealth = 1000}}, {{health = 3000, maxHealth = 10000}}})
eq(w, 1, "timeout: the higher share wins, not the higher health")
near(a, 0.6, 1e-12, "share side 1")
near(b, 0.3, 1e-12, "share side 2")
w = A.timeoutWinner({{{health = 500, maxHealth = 1000}}, {{health = 1000, maxHealth = 2000}}})
eq(w, 0, "equal share: draw")
w = A.timeoutWinner({
  {{health = 900, maxHealth = 1000}, {health = 1000, maxHealth = 1000, defeated = true}},
  {{health = 600, maxHealth = 1000}, {health = 600, maxHealth = 1000}}})
eq(w, 2, "2v2 timeout: a defeated player counts 0 (0.45 vs 0.6)")
eq(A.decided({{{defeated = false}}, {{defeated = false}}}), nil, "both standing: running")
eq(A.decided({{{defeated = false}}, {{defeated = true}}}), 1, "side 2 down: side 1 wins")
eq(A.decided({{{defeated = true}, {defeated = false}}, {{defeated = true}, {defeated = true}}}), 1, "2v2: one standing is enough")
eq(A.decided({{{defeated = true}}, {{defeated = true}}}), 0, "both down: draw")

-- ---------------------------------------------------------------- rewards
local items, first, st = A.reward(cfg, 20261008, {firstWinDay = -1, winsDay = -1, winsCount = 0})
check(first, "first win of the day")
eq(#items, 3, "win + first win items")
eq(st.winsCount, 1, "count 1")
items, first, st = A.reward(cfg, 20261008, {firstWinDay = 20261008, winsDay = 20261008, winsCount = 3})
check(not first and #items == 1 and items[1].id == 29856, "later win: one Orb of Upheaval")
items = A.reward(cfg, 20261008, {firstWinDay = 20261008, winsDay = 20261008, winsCount = 10})
eq(#items, 0, "nothing past the daily cap")
items, first, st = A.reward(cfg, 20261009, {firstWinDay = 20261008, winsDay = 20261008, winsCount = 10})
check(first and #items == 3 and st.winsCount == 1, "a new day resets the cap and the first win")

-- ---------------------------------------------------------------- instance layout
local L = A.layout(cfg, 0)
eq(L.arena.x1, 6000, "slot 0 origin")
eq(L.arena.x2 - L.arena.x1 - 1, cfg.room.innerW, "inner width")
eq(L.gallery.y1, L.arena.y2, "gallery shares the south wall")
local L5 = A.layout(cfg, 5)
eq(L5.arena.x1, 6000 + 24, "slot 5 column 1")
eq(L5.arena.y1, 6000 + 24, "slot 5 row 1")
local foot, seen, walls = A.footprint(L), {}, 0
for _, t in ipairs(foot) do
  local k = t.x .. "," .. t.y
  check(not seen[k], "footprint tile once " .. k)
  seen[k] = true
  if t.wall then walls = walls + 1 end
end
eq(#foot, 13 * 14, "footprint size")
for side = 1, 2 do
  for _, sp in ipairs(L.spawns[side]) do
    check(A.inArena(L, sp) and sp.x > L.arena.x1 and sp.x < L.arena.x2 and sp.y > L.arena.y1 and sp.y < L.arena.y2,
      "spawn inside the walls")
  end
  for _, sp in ipairs(L.galleryspots[side]) do
    check(sp.y > L.arena.y2 and sp.y < L.gallery.y2 and sp.x > L.gallery.x1 and sp.x < L.gallery.x2, "gallery spot inside")
  end
end
check(L.spawns[1][1].x < L.center.x and L.spawns[2][1].x > L.center.x, "teams start on opposite sides")
eq(A.slotOfPos(cfg, {x = 6030, y = 6030, z = 7}), 5, "slotOfPos")
eq(A.slotOfPos(cfg, {x = 6020, y = 6000, z = 7}), nil, "the gap between slots is no slot")
eq(A.allocSlot(cfg, {[0] = true}, {[1] = "bad"}), 2, "allocSlot skips busy and bad")
eq(A.parseMode(cfg, "2V2"), "2v2", "parseMode")
eq(A.parseMode(cfg, "1"), "1v1", "parseMode short")
eq(A.parseMode(cfg, "3v3"), "3v3", "parseMode 3v3")
eq(A.parseMode(cfg, "trio"), "3v3", "parseMode trio")
eq(A.parseMode(cfg, "4v4"), nil, "parseMode unknown")
check(A.levelsOk(cfg, {800, 850, 900, 950, 990, 1000}), "3v3: every level within 80% of the highest")
eq(cfg.modes["3v3"].size, 3, "3v3 is three a side")
eq(#L.spawns[1], 3, "three spawns a side for 3v3")
eq(#L.galleryspots[2], 3, "three gallery spots a side for 3v3")

-- the slots stay clear of the other runtime areas (tower 2000-2660, world boss 5000-5048, rifts 8192-8448)
local last = A.layout(cfg, cfg.grid.slots - 1)
check(last.gallery.y2 < 8192 and L.arena.x1 > 5048, "grid between the world boss and the rifts")

print(string.format("arena_test: %d checks, %d failed", count, fails))
if fails > 0 then
  os.exit(1)
end

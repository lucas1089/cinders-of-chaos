-- Run from the server/ folder: luajit tests/battleground_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The pure part of the battleground and the PvP seasons (battleground_core.lua): Glicko-lite ratings and their
-- convergence, soft reset, decay, placement, tiers and season rewards; matchmaking (realm and bracket groups, parties
-- kept whole, role and rating balance, fairness over random queues), the estimated wait; normalisation, capture,
-- score, waves, AFK, honor, deserter, vendor; the Ember Wells map (symmetry, paths, enclosed graveyards, no overlap).
local cfg = dofile("data/scripts/chaos/battleground_config.lua")
local pf = dofile("data/scripts/chaos/party_finder_config.lua")
dofile("data/scripts/chaos/battleground_core.lua")
local K = ChaosBattlegroundCore

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
  check(math.abs(a - b) <= eps, name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- deterministic random numbers (same in LuaJIT and Lua 5.3)
local seed = 12345
local function rnd()
  seed = (seed * 16807) % 2147483647 -- exact in doubles and in 64-bit integers
  return seed / 2147483647
end
local function rint(a, b)
  return a + math.floor(rnd() * (b - a + 1))
end

-- ====================================================================== the opcode
eq(cfg.opcode, 200, "opcode 200")
for _, used in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
  check(cfg.opcode ~= used, "not an opcode of the reference server: " .. used)
end
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.battleground, 200, "ChaosOpcodes.battleground")
local seen = {}
for name, op in pairs(ChaosOpcodes) do
  if op == 200 then seen[#seen + 1] = name end
end
eq(#seen, 1, "200 is used once in ChaosOpcodes")

-- ====================================================================== season dates
local epoch = K.epoch(cfg)
local len = K.seasonLength(cfg)
eq(len, 8 * 7 * 86400, "8 weeks")
local id, s1, e1 = K.seasonOf(cfg, epoch + 5)
eq(id, 1, "season 1 at the epoch")
eq(s1, epoch, "season 1 starts at the epoch")
eq(e1, epoch + len, "season 1 ends after 8 weeks")
eq((K.seasonOf(cfg, epoch + len)), 2, "season 2 at the end of season 1")
eq((K.seasonOf(cfg, epoch + 3 * len + 100)), 4, "season 4")
eq((K.seasonOf(cfg, epoch - 86400)), 1, "before the epoch: season 1 (not started)")

-- ====================================================================== Glicko-lite
local S = cfg.season
near(K.expected(1500, 1500, 100), 0.5, 1e-12, "equal ratings expect 0.5")
check(K.expected(1700, 1500, 50) > K.expected(1700, 1500, 300), "an uncertain opponent pulls the expectation to 0.5")
near(K.g(0), 1, 1e-12, "g(0) = 1")
-- a new player (rd 350) moves a lot, a settled one (rd at the floor) about +/-20
local r, rd, d = K.glicko(cfg, 1500, 350, 1500, 350, 1)
check(d > 100 and d < 200, "placement win moves 100-200 (" .. d .. ")")
check(rd < 350 and rd >= S.rdMin, "rd shrinks after a match")
r, rd, d = K.glicko(cfg, 1500, S.rdMin, 1500, S.rdMin, 1)
check(d >= 13 and d <= 18, "settled win between equals +13..18 (" .. d .. ")")
eq(rd, S.rdMin, "rd never below rdMin")
local _, _, dl = K.glicko(cfg, 1500, S.rdMin, 1500, S.rdMin, 0)
eq(dl, -d, "a loss mirrors a win between equals")
local _, _, dd = K.glicko(cfg, 1500, S.rdMin, 1500, S.rdMin, 0.5)
eq(dd, 0, "a draw between equals: 0")
local _, _, up = K.glicko(cfg, 1400, S.rdMin, 1700, S.rdMin, 1)
local _, _, fav = K.glicko(cfg, 1700, S.rdMin, 1400, S.rdMin, 1)
check(up > fav, "the underdog's win counts more")
r = K.glicko(cfg, 110, S.rdMin, 110, S.rdMin, 0)
eq(r, S.floor, "rating floor (110 - 15 stops at 100)")
near(K.inflate(cfg, S.rdMin, 0), S.rdMin, 1e-9, "no idle time: rd kept")
check(K.inflate(cfg, S.rdMin, 4 * 7 * 86400) > 80, "rd grows with idle weeks")
eq(K.inflate(cfg, 300, 1000 * 7 * 86400), S.rdMax, "rd capped")

-- team matches: rated against the other team's average; a leaver scores 0 whatever the team did
local teams = {
  {{rating = 1600, rd = 80}, {rating = 1400, rd = 80, left = true}},
  {{rating = 1500, rd = 80}, {rating = 1500, rd = 80}}}
K.rateTeams(cfg, teams, 1)
eq(teams[1][1].score, 1, "winner scores 1")
eq(teams[1][2].score, 0, "a leaver scores 0 even when the team wins")
check(teams[1][2].delta < 0, "the leaver loses rating")
check(teams[2][1].delta < 0 and teams[2][1].delta == teams[2][2].delta, "both losers lose the same")
eq(teams[2][1].before, 1500, "before kept")

-- convergence: 40 players with a hidden skill play random opponents inside the matchmaking window (400); the ratings
-- end in the right order and near the skills. (Always pairing rating neighbours stretches any Elo ladder, so the test
-- does what the queue does: anyone close enough.)
local players = {}
for i = 1, 40 do
  players[i] = {skill = 1100 + i * 20, rating = S.start, rd = S.rdStart}
end
for round = 1, 300 do
  for i = #players, 2, -1 do
    local j = rint(1, i)
    players[i], players[j] = players[j], players[i]
  end
  local used = {}
  for i, a in ipairs(players) do
    for j = i + 1, #players do
      local b = players[j]
      if not used[i] and not used[j] and math.abs(a.rating - b.rating) <= 400 then
        used[i], used[j] = true, true
        local pa = 1 / (1 + 10 ^ ((b.skill - a.skill) / 400))
        local win = rnd() < pa and 1 or 2
        local t = K.rateTeams(cfg, {{{rating = a.rating, rd = a.rd}}, {{rating = b.rating, rd = b.rd}}}, win)
        a.rating, a.rd = t[1][1].after, t[1][1].rdAfter
        b.rating, b.rd = t[2][1].after, t[2][1].rdAfter
      end
    end
  end
end
local function spearman(list)
  local bySkill, byRating = {}, {}
  for i, p in ipairs(list) do bySkill[i], byRating[i] = p, p end
  table.sort(bySkill, function(a, b) return a.skill < b.skill end)
  table.sort(byRating, function(a, b) return a.rating < b.rating end)
  local rs, rr = {}, {}
  for i, p in ipairs(bySkill) do rs[p] = i end
  for i, p in ipairs(byRating) do rr[p] = i end
  local sum, n = 0, #list
  for _, p in ipairs(list) do sum = sum + (rs[p] - rr[p]) ^ 2 end
  return 1 - 6 * sum / (n * (n * n - 1))
end
local rho = spearman(players)
check(rho > 0.9, string.format("ratings converge to the skill order (rank correlation %.3f)", rho))
local meanSkill, meanRating, err = 0, 0, 0
for _, p in ipairs(players) do meanSkill = meanSkill + p.skill / #players; meanRating = meanRating + p.rating / #players end
for _, p in ipairs(players) do err = err + math.abs((p.rating - meanRating) - (p.skill - meanSkill)) / #players end
check(err < 120, string.format("mean error after centring under 120 (%.1f)", err))
local spreadSkill, spreadRating = players[1].skill, 0
local lo, hi = math.huge, -math.huge
for _, p in ipairs(players) do lo = math.min(lo, p.rating); hi = math.max(hi, p.rating) end
check(hi - lo > 600 and hi - lo < 1100, "the rating spread follows the skill spread of 780 (" .. (hi - lo) .. ")")

-- ====================================================================== soft reset, decay, placement, tiers
local nr, nrd = K.softReset(cfg, 2300, 65)
eq(nr, 1900, "soft reset halves the distance to 1500")
eq(nrd, S.rdReset, "rd back to rdReset")
eq((K.softReset(cfg, 1100, 300)), 1300, "a low rating comes up as much")
eq(select(2, K.softReset(cfg, 1100, 300)), 300, "a larger rd is kept")
local day, week = 86400, 7 * 86400
local now = epoch + 30 * day
eq((K.decay(cfg, 2200, now - 10 * day, now)), 2200, "no decay inside the grace")
eq((K.decay(cfg, 2200, now - 20 * day, now)), 2200, "grace + 6 days: no full week yet")
eq((K.decay(cfg, 2200, now - 21 * day, now)), 2170, "grace + 1 week: -30")
eq((K.decay(cfg, 2200, now - (14 + 35) * day, now)), 2050, "grace + 5 weeks: -150")
eq((K.decay(cfg, 2200, now - 300 * day, now)), 2000, "never below the decay threshold")
eq((K.decay(cfg, 1900, now - 300 * day, now)), 1900, "no decay below the top tiers")
eq((K.decay(cfg, 2200, 0, now)), 2200, "no match yet: no decay")
eq((K.tierOf(cfg, 1399)), 1, "1399 Ashen")
eq((K.tierOf(cfg, 1400)), 2, "1400 Smouldering")
eq(select(2, K.tierOf(cfg, 2250)).name, "Cinder Sovereign", "2250 Cinder Sovereign")
for i = 2, #S.tiers do check(S.tiers[i].min > S.tiers[i - 1].min, "tier thresholds rise " .. i) end
check(S.tiers[5].min == S.decay.from, "decay starts at the Infernal tier")
local row = K.newRow(cfg)
check(not K.placed(cfg, row), "a new row is not placed")
row.matches = 5
check(K.placed(cfg, row), "placed after 5 matches")
local v = K.view(cfg, {rating = 2100, rd = 65, matches = 3, wins = 3, losses = 0, draws = 0, last = now - 22 * day}, now)
eq(v.rating, 2070, "the view decays")
eq(v.placementLeft, 2, "2 placement matches left")
check(not v.placed, "not placed yet")
check(v.rd > 65, "the view's rd grew while idle")
check(v.decayIn and v.decayIn > 0 and v.decayIn <= week, "time to the next decay step")
-- the season's end: the best placed bracket decides
local tier, bracket, rating = K.bestTier(cfg, {
  ["1v1"] = {rating = 2250, matches = 4, last = now},
  ["2v2"] = {rating = 1850, matches = 12, last = now},
  bg = {rating = 1700, matches = 30, last = now}}, now)
eq(tier, 4, "unplaced 1v1 does not count: Blazing from 2v2")
eq(bracket, "2v2", "best bracket")
eq(rating, 1850, "its rating")
eq(K.bestTier(cfg, {bg = {rating = 1700, matches = 2, last = now}}, now), nil, "nothing placed: no reward")
tier = K.bestTier(cfg, {bg = {rating = 2250, matches = 9, last = now - 200 * day}}, now)
eq(tier, 5, "decayed at the end: Infernal, not Sovereign")
local rw = K.seasonReward(cfg, 6, 3)
eq(rw.title, "Cinder Sovereign (S3)", "title with the season")
check(#rw.title <= 24, "the title fits a name plate")
eq(rw.frame, "violet", "plate frame")
eq(#rw.cosmetics, 3, "three cosmetics at the top")
eq(K.seasonReward(cfg, 1, 3).title, nil, "no title for Ashen")
eq(#K.rewardPreview(cfg), #S.tiers, "a preview row per tier")
-- every reward cosmetic and vendor cosmetic exists in cosmetics_config.lua with source "pvp"
local cos = dofile("data/scripts/chaos/cosmetics_config.lua")
local byKey = {}
for _, c in ipairs(cos.cosmetics) do byKey[c.key] = c end
for _, t in ipairs(S.tiers) do
  for _, k in ipairs(t.cosmetics or {}) do
    check(byKey[k] and byKey[k].source == "pvp", "season cosmetic " .. k .. " exists with source pvp")
  end
  check(#(t.title or "") + 6 <= 24, "title of " .. t.key .. " fits with the season")
end
for _, o in ipairs(cfg.vendor) do
  if o.kind == "cosmetic" then
    check(byKey[o.cosmetic] and byKey[o.cosmetic].source == "pvp", "vendor cosmetic " .. o.cosmetic .. " exists with source pvp")
  end
end
dofile("data/scripts/chaos/nameplate_core.lua")
for _, t in ipairs(S.tiers) do
  check(not t.frame or ChaosNameplate.FRAMES[t.frame], "frame of " .. t.key .. " is a plate frame")
end

-- ====================================================================== brackets, normalisation, roles
eq(K.bracketOf(cfg, 99), nil, "below the minimum level: no bracket")
eq(K.bracketOf(cfg, 100).key, "b1", "100 b1")
eq(K.bracketOf(cfg, 299).key, "b1", "299 b1")
eq(K.bracketOf(cfg, 300).key, "b2", "300 b2")
eq(K.bracketOf(cfg, 2000).key, "b4", "2000 b4")
local last = 99
for _, b in ipairs(cfg.brackets) do
  eq(b.min, last + 1, "brackets follow each other " .. b.key)
  check(b.ref >= b.min and (not b.max or b.ref <= b.max), "reference level inside the bracket " .. b.key)
  last = b.max or last
end
near(K.normFactor(cfg, 450, 450, 450), 1, 1e-12, "same level as the reference: x1")
near(K.normFactor(cfg, 300, 300, 450), 1, 1e-12, "same level hits same level: x1 (the factors cancel)")
check(K.normFactor(cfg, 599, 300, 450) < 1, "a high level hitting a low level is scaled down")
check(K.normFactor(cfg, 300, 599, 450) > 1, "a low level hitting a high level is scaled up")
near(K.normFactor(cfg, 599, 300, 450) * K.normFactor(cfg, 300, 599, 450), 1, 1e-9, "the two directions are inverse")
-- with damage ~ level and health ~ level, the share of health a hit takes is level-free with exponent 1, and
-- the edge shrinks with exponent 0.8
local raw = 599 / 300 -- a 599 hits about twice as hard as a 300 and has twice the health
local share599 = raw * K.normFactor(cfg, 599, 300, 450) -- the 599's hit on the 300, in 300-health units
local share300 = (1 / raw) * K.normFactor(cfg, 300, 599, 450) -- the 300's hit on the 599, in 599-health units
check(share599 / share300 < raw * raw / 2, "the level edge shrinks (" .. string.format("%.2f", share599 / share300) .. "x left of " .. string.format("%.2f", raw * raw) .. "x)")
eq(K.normFactor(cfg, 100, 5000, 1000), cfg.normalise.maxFactor * cfg.normalise.maxFactor, "clamped")
eq(K.window(cfg, 0), 250, "window at once")
eq(K.window(cfg, 60), 450, "window after 60 s")
eq(K.window(cfg, 99999), 1200, "window capped")
eq(K.pickRole(pf, 25, "healer"), "healer", "Sentinel may heal")
eq(K.pickRole(pf, 25, "dps"), "tank", "Sentinel cannot DPS: its main role")
eq(K.pickRole(pf, 5, nil), "dps", "Elementalist: dps")
eq(K.pickRole(pf, 999, "tank"), "dps", "unknown vocation: the default role")
eq(K.parseRole("Healer"), "healer", "parseRole")
eq(K.parseRole("boss"), nil, "parseRole refuses")

-- ====================================================================== matchmaking
local nid = 0
local function entry(members, joined, group)
  nid = nid + 1
  local sum = 0
  for _, m in ipairs(members) do sum = sum + m.rating end
  return {id = nid, joined = joined or 0, group = group or "0:b2", rating = sum / #members, members = members}
end
local function mem(role, rating)
  return {role = role, rating = rating or 1500}
end
local function solo(role, rating, joined, group)
  return entry({mem(role, rating)}, joined, group)
end
local function roles(team)
  local _, avg, rc = K.teamStats(team)
  return rc, avg
end
local function players_(team)
  local n = 0
  for _, e in ipairs(team) do n = n + #e.members end
  return n
end

-- 20 solos at once: a full 10v10 starts without waiting
local list = {}
for i = 1, 20 do
  list[i] = solo(i <= 2 and "tank" or (i <= 4 and "healer" or "dps"), 1400 + i * 10, 100 + i)
end
local found = K.findMatches(cfg, list, 125)
eq(#found, 1, "one match from 20 solos")
eq(found[1].size, 10, "10v10")
local rc1, a1 = roles(found[1].teams[1])
local rc2, a2 = roles(found[1].teams[2])
eq(rc1.tank, 1, "one tank each (team 1)")
eq(rc2.tank, 1, "one tank each (team 2)")
eq(rc1.healer, 1, "one healer each (team 1)")
eq(rc2.healer, 1, "one healer each (team 2)")
check(math.abs(a1 - a2) <= 20, "team ratings close (" .. a1 .. " / " .. a2 .. ")")
-- 12 solos: 6v6 only after fillSeconds
list = {}
for i = 1, 12 do list[i] = solo("dps", 1500, 1000) end
eq(#K.findMatches(cfg, list, 1010), 0, "6v6 waits for fuller teams")
found = K.findMatches(cfg, list, 1000 + cfg.fillSeconds)
eq(#found, 1, "6v6 after the fill time")
eq(found[1].size, 6, "6v6")
-- 9 players: never below 5v5
list = {}
for i = 1, 9 do list[i] = solo("dps", 1500, 0) end
eq(#K.findMatches(cfg, list, 9999), 0, "9 players: no match")
-- realms and brackets never mix
list = {}
for i = 1, 6 do list[#list + 1] = solo("dps", 1500, 0, "0:b2") end
for i = 1, 6 do list[#list + 1] = solo("dps", 1500, 0, "7:b2") end
eq(#K.findMatches(cfg, list, 9999), 0, "6 + 6 of two realms do not make a 6v6")
for i = 1, 4 do list[#list + 1] = solo("dps", 1500, 0, "7:b2") end
found = K.findMatches(cfg, list, 9999)
eq(#found, 1, "10 of one realm make a match")
eq(found[1].group, "7:b2", "in its own group")
-- the rating window: a far-off entry waits
list = {}
for i = 1, 10 do list[i] = solo("dps", 1500, 0) end
list[11] = solo("dps", 2600, 0)
found = K.findMatches(cfg, list, 60)
eq(#found, 1, "match without the far-off player")
local far = false
for _, t in ipairs(found[1].teams) do for _, e in ipairs(t) do if e.rating == 2600 then far = true end end end
check(not far, "2600 is not pulled into a 1500 match")
-- parties stay whole, teams exact
list = {entry({mem("tank"), mem("healer"), mem("dps"), mem("dps"), mem("dps")}, 0),
  entry({mem("dps"), mem("dps"), mem("dps")}, 1), entry({mem("dps"), mem("healer")}, 2)}
for i = 1, 10 do list[#list + 1] = solo(i == 1 and "tank" or "dps", 1500, 3 + i) end
found = K.findMatches(cfg, list, 100)
eq(#found, 1, "a match with parties")
eq(players_(found[1].teams[1]), 10, "team 1 exactly 10")
eq(players_(found[1].teams[2]), 10, "team 2 exactly 10")
local whereFive
for side, t in ipairs(found[1].teams) do for _, e in ipairs(t) do if #e.members == 5 then whereFive = side end end end
check(whereFive ~= nil, "the party of five plays together")
rc1, rc2 = roles(found[1].teams[1]), roles(found[1].teams[2])
eq(rc1.tank, 1, "a tank on each side (the party's and a solo)")
eq(rc2.tank, 1, "a tank on each side")
eq(rc1.healer, 1, "a healer on each side")
-- a party that cannot fit is skipped, a smaller entry fills
eq(K.split(cfg, {entry({mem("dps"), mem("dps"), mem("dps")}, 0), entry({mem("dps"), mem("dps"), mem("dps")}, 0)}, 3) ~= nil, true,
  "3 + 3 split into 3v3")
eq(K.split(cfg, {entry({mem("dps"), mem("dps"), mem("dps"), mem("dps")}, 0), solo("dps"), solo("dps")}, 3), nil,
  "4 + 1 + 1 cannot make 3v3")
-- fairness over random queues. Solo queues: tanks and healers always split evenly (an odd count differs by one) and
-- the team averages within 50. With 20% parties (2-4 players, random roles): every split is checked against the
-- exhaustive optimum (all subsets of entries) and may cost at most 10 more (a tank or healer off is 120).
local function randomQueue(partyRate)
  local q, n, t = {}, rint(10, 24), 0
  while #q < n do
    local size = rnd() < partyRate and rint(2, 4) or 1
    local ms = {}
    for i = 1, size do
      local x = rnd()
      ms[i] = mem(x < 0.15 and "tank" or (x < 0.32 and "healer" or "dps"), rint(1200, 1800))
    end
    t = t + 1
    q[#q + 1] = entry(ms, t)
  end
  return q
end
local function optimum(f)
  local es = {}
  for _, tm in ipairs(f.teams) do for _, e in ipairs(tm) do es[#es + 1] = e end end
  local best, m = math.huge, #es
  for mask = 0, 2 ^ (m - 1) - 1 do
    local x, y, size = {}, {}, 0
    for i = 1, m do
      if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then x[#x + 1] = es[i]; size = size + #es[i].members else y[#y + 1] = es[i] end
    end
    if size == f.size then best = math.min(best, K.cost(cfg, x, y)) end
  end
  return best, m
end
local soloMatches, soloRole, soloRating, exact = 0, 0, 0, true
for trial = 1, 200 do
  for _, f in ipairs(K.findMatches(cfg, randomQueue(0), 1000)) do
    soloMatches = soloMatches + 1
    local r1, x1 = roles(f.teams[1])
    local r2, x2 = roles(f.teams[2])
    if players_(f.teams[1]) ~= f.size or players_(f.teams[2]) ~= f.size then exact = false end
    soloRole = math.max(soloRole, math.abs(r1.tank - r2.tank) - ((r1.tank + r2.tank) % 2) + math.abs(r1.healer - r2.healer) - ((r1.healer + r2.healer) % 2))
    soloRating = math.max(soloRating, math.abs(x1 - x2))
  end
end
check(soloMatches > 150 and exact, "solo queues: matches with exact team sizes (" .. soloMatches .. ")")
eq(soloRole, 0, "solo queues: tanks and healers always split evenly")
check(soloRating <= 50, string.format("solo queues: team averages within 50 (worst %.1f)", soloRating))
local partyMatches, worstExcess = 0, 0
for trial = 1, 50 do
  for _, f in ipairs(K.findMatches(cfg, randomQueue(0.2), 1000)) do
    local best, m = optimum(f)
    if m <= 15 then
      partyMatches = partyMatches + 1
      check(players_(f.teams[1]) == f.size and players_(f.teams[2]) == f.size, "party queues: exact team sizes")
      worstExcess = math.max(worstExcess, f.cost - best)
    end
  end
end
check(partyMatches >= 30, "party queues checked against the optimum (" .. partyMatches .. ")")
check(worstExcess <= 10, string.format("party queues: at most 10 above the exhaustive optimum (worst %.1f)", worstExcess))

-- the estimated wait
eq(K.estimateWait(cfg, {}, 20, 0), cfg.matchmakeSeconds, "a full queue: at once")
eq(K.estimateWait(cfg, nil, 3, 0), cfg.defaultWaitSeconds, "nothing known: the default")
eq(K.estimateWait(cfg, {60, 120, 180}, 3, 30), 90, "average minus the time waited")
check(K.estimateWait(cfg, {600}, 12, 0) <= cfg.fillSeconds, "enough for 6v6: at most the fill time")
local samples = {}
for i = 1, 15 do K.addSample(cfg, samples, i) end
eq(#samples, cfg.waitSamples, "samples capped")
eq(samples[1], 6, "oldest samples dropped")

-- ====================================================================== the match
local a, t2 = {team = 1}, {team = 2}
check(not K.canHit("prep", a, t2, false), "no hits in the preparation")
check(K.canHit("fight", a, t2, false), "opponents in the fight")
check(not K.canHit("fight", a, {team = 1}, false), "no team damage")
check(not K.canHit("fight", a, {team = 2, down = true}, false), "the downed cannot be hit")
check(not K.canHit("fight", {team = 1, down = true}, t2, false), "the downed cannot hit")
check(K.canHit("fight", nil, t2, false), "a field hits in the fight")
local p, s, caught = K.catchDamage(500, 450, 100)
check(caught and p + s == 499, "the death catch leaves 1 health")
-- capture: 8 s alone from neutral, 16 s from the enemy, faster with more, contested holds
local b = {progress = 0, owner = 0}
local ev
for i = 1, 7 do ev = K.captureStep(cfg, b, {1, 0}, 1) end
eq(ev, nil, "7 s: not yet")
eq(b.owner, 0, "still neutral")
ev = K.captureStep(cfg, b, {1, 0}, 1)
eq(ev, "captured", "8 s: captured")
eq(b.owner, 1, "team 1 owns it")
eq(b.progress, 100, "full")
ev = K.captureStep(cfg, b, {1, 1}, 1)
check(ev == nil and b.contested and b.progress == 100, "contested: nothing moves")
local events = {}
for i = 1, 16 do
  local e2, who = K.captureStep(cfg, b, {0, 1}, 1)
  if e2 then events[#events + 1] = e2 .. who end
end
eq(events[1], "lost1", "team 1 loses it at the half")
eq(events[2], "captured2", "team 2 takes it after 16 s")
eq(b.owner, 2, "team 2 owns it")
b = {progress = 0, owner = 0}
for i = 1, 4 do ev = K.captureStep(cfg, b, {0, 5}, 1) end
eq(ev, "captured", "five players (x2 rate cap): 4 s")
b = {progress = 0, owner = 0}
for i = 1, 6 do ev = K.captureStep(cfg, b, {0, 3}, 1) end
eq(ev, "captured", "three players (x1.5): 6 s")
-- points
local pa, pb = K.tickPoints(cfg, {{owner = 1}, {owner = 1}, {owner = 2}})
eq(pa, 10, "two braziers: 10 a tick")
eq(pb, 4, "one brazier: 4 a tick")
pa = K.tickPoints(cfg, {{owner = 1}, {owner = 1}, {owner = 1}})
eq(pa, 20, "three braziers: 20 a tick")
eq(cfg.winScore / pa * cfg.tickSeconds, 100, "holding all three wins in 100 s")
eq(cfg.winScore / 4 * cfg.tickSeconds, 500, "holding one: 500 s")
eq(K.winner(cfg, {990, 400}, false), nil, "running")
eq(K.winner(cfg, {1004, 400}, false), 1, "1000 reached")
eq(K.winner(cfg, {1010, 1010}, false), 0, "both at once, equal: draw")
eq(K.winner(cfg, {500, 600}, true), 2, "time: the higher score")
eq(select(2, K.winner(cfg, {500, 600}, true)), "time", "reason time")
eq(K.winner(cfg, {500, 500}, true), 0, "time and equal: draw")
eq(K.nextWave(cfg, 1000, 990), 1000, "first wave at the start")
eq(K.nextWave(cfg, 1000, 1000), 1015, "next wave")
eq(K.nextWave(cfg, 1000, 1029), 1030, "waves every 15 s")
eq(K.afk(cfg, 30), nil, "active")
eq(K.afk(cfg, 60), "warn", "AFK warning")
eq(K.afk(cfg, 120), "kick", "AFK removal")
local rows = K.scoreboard({{name = "b", team = 2, kills = 9}, {name = "a", team = 1, kills = 1, captures = 2},
  {name = "c", team = 1, kills = 4}})
eq(rows[1].name, "a", "scoreboard: team 1 first, kills + 2 x captures (5 before 4)")
eq(rows[3].name, "b", "team 2 after")

-- ====================================================================== rewards, deserter, vendor
local h = cfg.honor
local gained, first = K.honorFor(cfg, {result = "win", kills = 3, captures = 2}, {earned = 0, firstWinDone = false})
eq(gained, h.win + 3 * h.perKill + 2 * h.perCapture + h.weeklyFirstWin, "win + kills + captures + the weekly first win")
check(first, "first win of the week")
gained, first = K.honorFor(cfg, {result = "win", kills = 99, captures = 99}, {earned = 0, firstWinDone = true})
eq(gained, h.win + h.killCap + h.captureCap, "kill and capture caps")
gained = K.honorFor(cfg, {result = "loss"}, {earned = h.weeklyCap - 10, firstWinDone = true})
eq(gained, 10, "the weekly cap")
gained = K.honorFor(cfg, {result = "win"}, {earned = h.weeklyCap, firstWinDone = false})
eq(gained, h.weeklyFirstWin, "the first win bonus is not capped")
eq(K.honorFor(cfg, {result = "win", deserter = true}, {earned = 0}), 0, "a deserter gets nothing")
eq(K.honorFor(cfg, {result = "win", presence = 0.2}, {earned = 0}), 0, "too short in the match: nothing")
local mins, hist = K.deserter(cfg, {}, 100000)
eq(mins, 15, "first desertion 15 min")
mins, hist = K.deserter(cfg, hist, 101000)
eq(mins, 30, "second 30 min")
mins, hist = K.deserter(cfg, hist, 102000)
eq(mins, 60, "third 60 min")
mins, hist = K.deserter(cfg, hist, 103000)
eq(mins, 120, "fourth 120 min")
mins, hist = K.deserter(cfg, hist, 104000)
eq(mins, 120, "capped at the last step")
mins, hist = K.deserter(cfg, hist, 104000 + 25 * 3600)
eq(mins, 15, "a day later: forgiven")
eq(#hist, 1, "old desertions dropped")
local offer, why = K.vendorCheck(cfg, "ghp", 59)
eq(offer, nil, "not enough honor")
check(why:find("60") ~= nil, "the price in the reason")
eq(K.vendorCheck(cfg, "ghp", 60).id, 7591, "great health potions")
eq(K.vendorCheck(cfg, "c_kill", 9999, function() return true end), nil, "an owned cosmetic is not sold twice")
eq(K.vendorCheck(cfg, "nope", 9999), nil, "unknown offer")
for _, o in ipairs(cfg.vendor) do
  check(o.kind == "item" or o.kind == "cosmetic", "vendor offers only items and cosmetics: " .. o.key)
  check(o.cost > 0 and #o.key <= 16, "offer key and cost " .. o.key)
end
-- week keys: Monday 06:00
local mon = os.time({year = 2026, month = 10, day = 12, hour = 7})
eq(K.weekKey(mon, 6), 20261012, "Monday 07:00 starts the week")
eq(K.weekKey(mon - 2 * 3600, 6), 20261005, "Monday 05:00 is still the last week")
eq(K.weekKey(mon + 6 * day, 6), 20261012, "Sunday is the same week")

-- ====================================================================== the map
local L = K.layout(cfg, 0)
eq(L.x1, 11264, "slot 0 origin x")
eq(L.x2 - L.x1 - 1, cfg.field.innerW, "inner width")
eq(L.y2 - L.y1 - 1, cfg.field.innerH, "inner height")
local function turn(pos) return {x = L.x1 + L.x2 - pos.x, y = L.y1 + L.y2 - pos.y, z = pos.z} end
local function key(pos) return pos.x .. "," .. pos.y end
local foot = K.footprint(cfg, L)
local tile = {}
for _, t in ipairs(foot) do
  check(not tile[key(t)], "footprint tile once " .. key(t))
  tile[key(t)] = t
end
eq(#foot, (cfg.field.innerW + 2) * (cfg.field.innerH + 2), "footprint size")
-- the 180-degree symmetry: walls, ground kinds, items
local symmetric = true
for _, t in ipairs(foot) do
  local o = tile[key(turn(t))]
  if not o or o.wall ~= t.wall or o.ground ~= t.ground then symmetric = false end
end
check(symmetric, "walls and grounds are symmetric (180 degrees)")
local blocked = {}
for _, q in ipairs(L.pillars) do blocked[key(q)] = true end
for _, q in ipairs(L.flags) do blocked[key(q)] = true end
for _, q in ipairs(L.braziers) do blocked[key(q)] = true end
local function itemsSym(lst)
  local set = {}
  for _, q in ipairs(lst) do set[key(q)] = true end
  for _, q in ipairs(lst) do if not set[key(turn(q))] then return false end end
  return true
end
check(itemsSym(L.pillars) and itemsSym(L.flags) and itemsSym(L.braziers), "pillars, flags and braziers are symmetric")
eq(#L.braziers, 3, "three braziers")
check(L.braziers[1].x < L.braziers[2].x and L.braziers[2].x < L.braziers[3].x, "west, heart, east")
eq(L.braziers[2].x, L.center.x, "the heart well in the centre")
eq(L.braziers[2].name, "Heart Well", "names")
for i, br in ipairs(L.braziers) do
  check(not tile[key(br)].wall, "brazier " .. i .. " not on a wall")
  eq(K.brazierAt(cfg, L, {x = br.x + 2, y = br.y - 2, z = br.z}), i, "circle corner of brazier " .. i)
  eq(K.brazierAt(cfg, L, {x = br.x + 3, y = br.y, z = br.z}), nil, "outside the circle " .. i)
  for dx = -2, 2 do for dy = -2, 2 do
    local q = {x = br.x + dx, y = br.y + dy, z = br.z}
    check(not tile[key(q)].wall and (dx == 0 and dy == 0 or not blocked[key(q)]), "circle tile free " .. key(q))
  end end
end
local nearest = {}
for team = 1, 2 do
  for _, sp in ipairs(L.spawns[team]) do
    eq(K.baseOf(L, sp), team, "spawn in the own base " .. key(sp))
    check(not tile[key(sp)].wall and not blocked[key(sp)], "spawn tile free " .. key(sp))
  end
  check(#L.spawns[team] >= cfg.teamMax, "a spawn tile per player")
  for _, g in ipairs(L.graveSpots[team]) do
    eq(K.graveOf(L, g), team, "grave spot in the own graveyard")
    check(not tile[key(g)].wall, "grave spot free")
  end
end
check(L.bases[1].x2 < L.center.x and L.bases[2].x1 > L.center.x, "bases west and east")
-- paths: from a spawn every brazier circle and the other base's gate are reachable; the graveyards are closed
local function walk(from)
  local seenT, queue, head = {[key(from)] = true}, {from}, 1
  while head <= #queue do
    local q = queue[head]; head = head + 1
    for _, dxy in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
      local n = {x = q.x + dxy[1], y = q.y + dxy[2], z = q.z}
      local t = tile[key(n)]
      if t and not t.wall and not blocked[key(n)] and not seenT[key(n)] then
        seenT[key(n)] = true
        queue[#queue + 1] = n
      end
    end
  end
  return seenT
end
for team = 1, 2 do
  local reach = walk(L.spawns[team][1])
  for i, br in ipairs(L.braziers) do
    check(reach[key({x = br.x + 1, y = br.y})], "team " .. team .. " reaches brazier " .. i)
  end
  check(reach[key(L.spawns[3 - team][1])], "team " .. team .. " can walk to the other base")
  check(not reach[key(L.graveSpots[team][1])], "team " .. team .. "'s graveyard is closed")
  local inside = walk(L.graveSpots[team][1])
  local out = false
  for k in pairs(inside) do
    local x, y = k:match("(%-?%d+),(%-?%d+)")
    if K.graveOf(L, {x = tonumber(x), y = tonumber(y), z = L.z}) ~= team then out = true end
  end
  check(not out, "nobody walks out of graveyard " .. team)
end
-- the slots: inside the reserved area, apart, and away from the other runtime areas
local areas = {
  {"Infinity Tower", 2000, 2000, 2660, 2660}, {"world boss", 5000, 5000, 5048, 5048}, {"siege", 5100, 5000, 5400, 5300},
  {"arena", 6000, 6000, 6100, 6100}, {"Ascended", 7600, 7600, 7700, 7700}, {"rifts", 8192, 8192, 8447, 8447},
  {"trials", 9000, 9000, 9160, 9080}, {"guild halls", 9216, 9216, 9536, 9536},
  {"Ember Descent", 10000, 10000, 10255, 10127}, {"raid", 10400, 10000, 10911, 10511}}
local rects = {}
for slot = 0, cfg.grid.slots - 1 do
  local Ls = K.layout(cfg, slot)
  check(Ls.x1 >= 11264 and Ls.x2 <= 11455 and Ls.y1 >= 11264 and Ls.y2 <= 11455, "slot " .. slot .. " in 11264-11455")
  for _, ar in ipairs(areas) do
    check(Ls.x2 < ar[2] or Ls.x1 > ar[4] or Ls.y2 < ar[3] or Ls.y1 > ar[5], "slot " .. slot .. " clear of the " .. ar[1])
  end
  for _, o in ipairs(rects) do
    check(Ls.x2 < o.x1 or Ls.x1 > o.x2 or Ls.y2 < o.y1 or Ls.y1 > o.y2, "slots do not overlap " .. slot)
  end
  rects[#rects + 1] = Ls
  eq(K.slotOfPos(cfg, Ls.center), slot, "slotOfPos " .. slot)
end
eq(K.slotOfPos(cfg, {x = 11264 + 80, y = 11264, z = 7}), nil, "the gap between slots")
eq(K.allocSlot(cfg, {[0] = true}, {[1] = "bad"}), 2, "allocSlot skips busy and bad")

print(string.format("battleground_test: %d checks, %d failed", count, fails))
if fails > 0 then
  os.exit(1)
end

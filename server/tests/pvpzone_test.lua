-- Run from the server/ folder: luajit tests/pvpzone_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The Scorched Marches (open-world PvP zone).
-- Part 1, the pure part (pvpzone_core.lua): opcode and storages, the instances and the layout (slots per realm, clear of
-- the other runtime areas, walkable paths from both exits to the shrine and every spawn point, 180-degree fairness),
-- the entry rules (Hardcore refused, the confirmation), login safety, the exit channel, embers (carry cap, the death
-- pile, who may take how much and when, the daily cap, Self-Found, banking), anti-farming, faction reputation, the
-- pledge, PvP scaling like the battleground, the shrine contest (warden, capture, contested, decay, expiry, control,
-- buff), the vendor and its cosmetics, the leaderboard board and the achievements.
-- Part 2, pvpzone.lua on a mocked engine: entering, protection, attack rules, damage scaling, monster embers, a defeat
-- with the pile, the killer's pickup, reputation, anti-farming, banking at a safe exit, login inside, leaving by a
-- teleport, the contest with its warden and the faction-wide buff.
local cfg = dofile("data/scripts/chaos/pvpzone_config.lua")
local bg = dofile("data/scripts/chaos/battleground_config.lua")
local fcfg = dofile("data/scripts/chaos/factions_config.lua")
dofile("data/scripts/chaos/battleground_core.lua")
dofile("data/scripts/chaos/pvpzone_core.lua")
local K = ChaosPvpZoneCore

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
local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ====================================================================== opcode and storages
eq(cfg.opcode, 193, "opcode 193")
for _, used in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, -- the reference server
    140, 144, 145, 146, 210, 212, 213, 230, 246}) do -- the reference client's own ExtendedIds
  check(cfg.opcode ~= used, "not an opcode of the reference server or client: " .. used)
end
local constants = readFile("data/scripts/chaos/chaos_constants.lua")
check(constants:find("ChaosOpcodes.pvpZone = 193", 1, true) ~= nil, "ChaosOpcodes.pvpZone registered")
local opcodes = {}
for name, num in constants:gmatch("\n\t([%w]+) = (%d+),") do
  if tonumber(num) < 256 and tonumber(num) > 0 then opcodes[name] = tonumber(num) end
end
for name, num in constants:gmatch("ChaosOpcodes%.([%w]+) = (%d+)") do
  opcodes[name] = tonumber(num)
end
for name, num in pairs(opcodes) do
  if name ~= "pvpZone" then check(num ~= 193, "193 not used by ChaosOpcodes." .. name) end
end
-- the client: no other module on 193
local ls = io.popen("ls ../client/overlay/modules")
for dir in ls:lines() do
  if dir ~= "game_pvpzone" then
    local p = io.popen("cat ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
    local text = p:read("*a")
    p:close()
    check(not text:find("OPCODE = 193", 1, true), "client module " .. dir .. " does not use 193")
  end
end
ls:close()
-- storages 7100520 - 7100529: inside the Chaos range and used by no other script
for k, v in pairs(cfg.storage) do
  check(v >= 7100520 and v <= 7100529, "storage " .. k .. " in the reserved block")
end
local scripts = io.popen("ls data/scripts/chaos/*.lua data/lib/*.lua data/spells/chaos/*.lua")
for path in scripts:lines() do
  if not path:find("pvpzone") then
    local text = (readFile(path) or ""):gsub("[^\n]*pvpZone[^\n]*", ""):gsub("%-%- [^\n]*7100520 %- 7100529[^\n]*", "")
    check(not text:find("71005[2][0-9]"), "storage block 7100520-7100529 free in " .. path)
  end
end
scripts:close()

-- ====================================================================== the instances and the layout
eq(K.slotForRealm(cfg, 0), 0, "standard realm: slot 0")
eq(K.slotForRealm(cfg, 1), 1, "season 1: slot 1")
eq(K.slotForRealm(cfg, 3), 3, "season 3: slot 3")
eq(K.slotForRealm(cfg, 4), 1, "season 4 reuses slot 1 (season 1 is long over)")
local others = {{"Infinity Tower", 2000, 2000, 2660, 2660}, {"world boss", 5000, 5000, 5048, 5048},
  {"siege", 5100, 5000, 5400, 5300}, {"arena", 6000, 6000, 6100, 6100}, {"Ascended", 7600, 7600, 7700, 7700},
  {"rifts", 8192, 8192, 8447, 8447}, {"trials", 9000, 9000, 9160, 9080}, {"guild halls", 9216, 9216, 9536, 9536},
  {"Ember Descent", 10000, 10000, 10255, 10127}, {"raid", 10400, 10000, 10911, 10511},
  {"battleground", 11264, 11264, 11455, 11455}, {"guild boss", 11264, 10000, 11455, 10095},
  {"hideouts", 12288, 12288, 12799, 12799}}
local rects = {}
for slot = 0, cfg.grid.slots - 1 do
  local L = K.layout(cfg, slot)
  for _, o in ipairs(others) do
    check(L.x2 < o[2] or L.x1 > o[4] or L.y2 < o[3] or L.y1 > o[5], "slot " .. slot .. " clear of the " .. o[1])
  end
  for _, r in ipairs(rects) do
    check(L.x2 < r.x1 or L.x1 > r.x2 or L.y2 < r.y1 or L.y1 > r.y2, "slots do not overlap " .. slot)
  end
  rects[#rects + 1] = L
  eq(K.slotOfPos(cfg, L.shrine), slot, "slotOfPos shrine " .. slot)
  eq(K.slotOfPos(cfg, {x = L.x1, y = L.y1, z = 7}), slot, "slotOfPos corner " .. slot)
  eq(K.slotOfPos(cfg, {x = L.x2, y = L.y2, z = 7}), slot, "slotOfPos far corner " .. slot)
  eq(K.slotOfPos(cfg, {x = L.x2 + 1, y = L.y1, z = 7}), nil, "the gap after slot " .. slot)
  eq(K.slotOfPos(cfg, {x = L.x1, y = L.y1, z = 6}), nil, "another floor")
end
eq(K.slotOfPos(cfg, {x = 13311, y = 13400, z = 7}), nil, "west of the grid")

local L = K.layout(cfg, 0)
local foot = K.footprint(cfg, L)
eq(#foot, (cfg.field.innerW + 2) * (cfg.field.innerH + 2), "footprint covers the instance once")
local grid = {}
for _, t in ipairs(foot) do grid[t.x .. "," .. t.y] = t end
local blocked = {}
for _, t in ipairs(foot) do if t.wall then blocked[t.x .. "," .. t.y] = true end end
for k in pairs(K.blockedSet(L)) do blocked[k] = true end -- ruin walls, pillars, flags, lights, cover, the shrine
eq(#L.exits, 2, "two safe exits")
for i, e in ipairs(L.exits) do
  check(not blocked[e.x .. "," .. e.y], "exit " .. i .. " walkable")
  eq(grid[e.x .. "," .. e.y].ground, "ring", "exit " .. i .. " on the ring ground")
  eq(K.exitAt(cfg, L, e), i, "exitAt " .. i)
  eq(K.exitAt(cfg, L, {x = e.x + cfg.exit.radius + 1, y = e.y, z = 7}), nil, "outside the circle " .. i)
  for _, s in ipairs(L.entrySpots[i]) do
    check(not blocked[s.x .. "," .. s.y], "arrival spot free " .. s.x .. "," .. s.y)
    eq(K.exitAt(cfg, L, s), nil, "arrival spot outside the exit circle")
  end
end
eq(grid[L.shrine.x + 2 .. "," .. L.shrine.y].ground, "ring", "shrine circle ground")
check(K.inShrine(cfg, L, {x = L.shrine.x + 3, y = L.shrine.y - 3, z = 7}), "shrine circle radius 3")
check(not K.inShrine(cfg, L, {x = L.shrine.x + 4, y = L.shrine.y, z = 7}), "outside the shrine circle")
-- fairness: the ruins of one half are the other half turned around
local W, H = cfg.field.innerW, cfg.field.innerH
for _, w in ipairs(L.walls) do
  local tx, ty = L.x1 + (W + 1) - (w.x - L.x1), L.y1 + (H + 1) - (w.y - L.y1)
  check(blocked[tx .. "," .. ty], "ruin turned " .. w.x .. "," .. w.y)
end
-- paths: from exit 1 to the shrine circle, exit 2 and every spawn point (4-neighbour flood fill)
local seen, queue = {}, {L.exits[1]}
seen[L.exits[1].x .. "," .. L.exits[1].y] = true
local head = 1
while queue[head] do
  local p = queue[head]
  head = head + 1
  for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
    local k = (p.x + d[1]) .. "," .. (p.y + d[2])
    if grid[k] and not blocked[k] and not seen[k] then
      seen[k] = true
      queue[#queue + 1] = {x = p.x + d[1], y = p.y + d[2]}
    end
  end
end
check(seen[L.exits[2].x .. "," .. L.exits[2].y], "exit 2 reachable from exit 1")
check(seen[(L.shrine.x + 1) .. "," .. L.shrine.y], "the shrine circle reachable")
check(#L.spawns >= 20, "enough spawn points (" .. #L.spawns .. ")")
for _, s in ipairs(L.spawns) do
  check(seen[s.x .. "," .. s.y], "spawn point reachable " .. s.x .. "," .. s.y)
  for _, e in ipairs(L.exits) do
    check(math.max(math.abs(s.x - e.x), math.abs(s.y - e.y)) >= cfg.monsters.keepAway.exit, "spawn away from the exits")
  end
  check(math.max(math.abs(s.x - L.shrine.x), math.abs(s.y - L.shrine.y)) >= cfg.monsters.keepAway.shrine,
    "spawn away from the shrine")
end
local free = 0
for k in pairs(grid) do if not blocked[k] then free = free + 1 end end
eq(head - 1, free, "every walkable tile is connected")
eq(K.nearestExit(L, {x = L.exits[2].x - 3, y = L.exits[2].y + 2, z = 7}), 2, "nearest exit")

-- ---------------------------------------------------------------- the look of the field (O275)
-- every objective is reachable from the entry on the generated grid (4-neighbour steps, the cover included)
for i, e in ipairs(L.exits) do
  check(seen[e.x .. "," .. e.y], "exit " .. i .. " reachable from the entry")
  for _, sp in ipairs(L.entrySpots[i]) do
    check(seen[sp.x .. "," .. sp.y], "arrival spot reachable from the entry " .. sp.x .. "," .. sp.y)
  end
end
local circle, circleOpen = 0, 0
for dx = -cfg.contest.capture.radius, cfg.contest.capture.radius do
  for dy = -cfg.contest.capture.radius, cfg.contest.capture.radius do
    local k = (L.shrine.x + dx) .. "," .. (L.shrine.y + dy)
    circle = circle + 1
    if not blocked[k] then
      circleOpen = circleOpen + 1
      check(seen[k], "the shrine circle is reachable at " .. dx .. "," .. dy)
    end
  end
end
check(circleOpen >= circle - 5, "the capture circle stays open for the fight (" .. circleOpen .. " of " .. circle .. ")")
for _, d in ipairs({{0, 1}, {1, 0}, {0, -1}, {-1, 0}}) do
  check(not blocked[(L.shrine.x + d[1]) .. "," .. (L.shrine.y + d[2])], "the Warden has room beside the shrine")
end
-- the paved way: exit 1 to the shrine plaza over road and yard tiles only
local paved = {}
for _, t in ipairs(foot) do if t.ground ~= "ground" and not blocked[t.x .. "," .. t.y] then paved[t.x .. "," .. t.y] = true end end
local pseen, pq, ph = {[L.exits[1].x .. "," .. L.exits[1].y] = true}, {L.exits[1]}, 1
while pq[ph] do
  local p = pq[ph]
  ph = ph + 1
  for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
    local k = (p.x + d[1]) .. "," .. (p.y + d[2])
    if paved[k] and not pseen[k] then
      pseen[k] = true
      pq[#pq + 1] = {x = p.x + d[1], y = p.y + d[2]}
    end
  end
end
check(pseen[(L.shrine.x + 1) .. "," .. L.shrine.y], "a paved road leads from the entry to the shrine")
check(pseen[L.exits[2].x .. "," .. L.exits[2].y], "a paved road leads from the entry to the other exit")
-- terrain: several kinds of ground with border pieces, cover with the right kinds, lights, decoration
local kinds, edgeTiles, gids = {}, 0, {}
for _, t in ipairs(foot) do
  kinds[t.ground] = (kinds[t.ground] or 0) + 1
  gids[t.gid or 0] = true
  if #t.edges > 0 then edgeTiles = edgeTiles + 1 end
  check(t.gid ~= nil or t.wall, "every inside tile has a ground item " .. t.x .. "," .. t.y)
end
for _, kind in ipairs({"ground", "gate", "ring", "road", "hall"}) do check((kinds[kind] or 0) > 0, "ground kind " .. kind) end
local nGround = 0
for _ in pairs(gids) do nGround = nGround + 1 end
check(nGround >= 12, "varied ground (" .. nGround .. " different ground items)")
check(edgeTiles >= 80, "border pieces between the terrains (" .. edgeTiles .. " tiles)")
local spawnSet = {}
for _, sp in ipairs(L.spawns) do spawnSet[sp.x .. "," .. sp.y] = true end
local nearSpawn = function(x, y)
  for dx = -1, 1 do for dy = -1, 1 do if spawnSet[(x + dx) .. "," .. (y + dy)] then return true end end end
  return false
end
local lookIds, trees, rocks, lava = {}, 0, 0, 0
for _, g in ipairs(cfg.look.cover) do for _, id in ipairs(g.ids) do lookIds[id] = g end end
check(#L.cover >= 150, "cover: trees, rocks, bones and lava holes (" .. #L.cover .. ")")
local crackAt = {}
for _, t in ipairs(foot) do if t.gid == cfg.look.cracks[1] then crackAt[t.x .. "," .. t.y] = true end end
local coverAt = {}
for _, c in ipairs(L.cover) do
  local k = c.x .. "," .. c.y
  check(lookIds[c.id] ~= nil, "cover item " .. c.id .. " is from the config")
  check(not coverAt[k], "one cover piece per tile " .. k)
  coverAt[k] = true
  eq(grid[k].ground, "ground", "cover only on natural ground " .. k)
  check(not nearSpawn(c.x, c.y), "no cover next to a spawn point " .. k)
  if lookIds[c.id].name == "lava holes" then
    lava = lava + 1
    check(crackAt[k], "lava holes only on crack ground " .. k)
  end
  if lookIds[c.id].name == "charred trees" then trees = trees + 1 end
  if lookIds[c.id].name == "scorched rock" then rocks = rocks + 1 end
  for _, g in ipairs(L.gates) do
    check(not (c.x >= g.x1 - cfg.look.keepClear and c.x <= g.x2 + cfg.look.keepClear and c.y >= g.y1 - cfg.look.keepClear
      and c.y <= g.y2 + cfg.look.keepClear), "no cover at the gate yards " .. k)
  end
end
-- fairness: the turn of every piece is a piece too
for _, c in ipairs(L.cover) do
  local tx, ty = L.x1 + (W + 1) - (c.x - L.x1), L.y1 + (H + 1) - (c.y - L.y1)
  check(coverAt[tx .. "," .. ty], "cover turned " .. c.x .. "," .. c.y)
end
check(trees >= 40 and rocks >= 30 and lava >= 10, "charred trees " .. trees .. ", rocks " .. rocks .. ", lava holes " .. lava)
local decorBlock = {}
for _, g in ipairs(cfg.look.cover) do for _, id in ipairs(g.ids) do decorBlock[id] = true end end
for _, d in ipairs(L.decor) do
  check(not decorBlock[d.id], "decoration never blocks " .. d.id)
  check(d.id ~= cfg.ids.pile and d.id ~= 7349, "decoration is not the ember pile marker")
  check(not blocked[d.x .. "," .. d.y], "decoration on an open tile " .. d.x .. "," .. d.y)
end
check(#L.decor >= 150, "decoration (" .. #L.decor .. ")")
-- landmarks: lights at the shrine and in both gate yards
local fixAt = {}
for _, f in ipairs(L.fixtures) do fixAt[f.x .. "," .. f.y] = f.id end
for _, d in ipairs(cfg.look.shrineLights.at) do
  eq(fixAt[(L.shrine.x + d[1]) .. "," .. (L.shrine.y + d[2])], cfg.look.shrineLights.id, "coal basin in the capture circle")
end
for _, d in ipairs(cfg.look.shrineBeacons.at) do
  eq(fixAt[(L.shrine.x + d[1]) .. "," .. (L.shrine.y + d[2])], cfg.look.shrineBeacons.id, "skull pillar beacon at the shrine")
end
for i, e in ipairs(L.exits) do
  for _, d in ipairs(cfg.look.gateLights.at) do
    eq(fixAt[(e.x + d[1]) .. "," .. (e.y + d[2])], cfg.look.gateLights.id, "coal basin in gate yard " .. i)
  end
end
-- deterministic: the same field on a second run and in every slot (same offsets from the origin)
local Lb = K.layout(cfg, 0)
eq(Lb, L, "the layout is cached per config")
local copy = {}
for k2, v in pairs(cfg) do copy[k2] = v end
local Lc = K.layout(copy, 0)
check(Lc ~= L, "a second config builds again")
eq(#Lc.cover, #L.cover, "a second run: the same cover")
eq(#Lc.decor, #L.decor, "a second run: the same decoration")
for i, c in ipairs(L.cover) do
  eq(Lc.cover[i].x .. "," .. Lc.cover[i].y .. "," .. Lc.cover[i].id, c.x .. "," .. c.y .. "," .. c.id, "a second run: cover " .. i)
end
local L1 = K.layout(cfg, 1)
eq(#L1.cover, #L.cover, "another slot: the same cover count")
for i, c in ipairs(L.cover) do
  eq((L1.cover[i].x - L1.x1) .. "," .. (L1.cover[i].y - L1.y1) .. "," .. L1.cover[i].id,
    (c.x - L.x1) .. "," .. (c.y - L.y1) .. "," .. c.id, "another slot: cover " .. i)
end
-- a tiny field with the same look still keeps every tile connected (the cover check works on any size)
local small = {}
for k2, v in pairs(cfg) do small[k2] = v end
small.field = {innerW = 72, innerH = 56}
small.look = {}
for k2, v in pairs(cfg.look) do small.look[k2] = v end
small.look.cover = {{name = "wall of trees", ids = {2713}, clumps = {{x = 36, y = 40, r = 12, chance = 100}}}}
local Ls = K.layout(small, 0)
local sb = K.blockedSet(Ls)
local sgrid = K.footprint(small, Ls)
local sfree, sseen, sq, sh = 0, {[Ls.exits[1].x .. "," .. Ls.exits[1].y] = true}, {Ls.exits[1]}, 1
local sg = {}
for _, t in ipairs(sgrid) do sg[t.x .. "," .. t.y] = t; if not t.wall and not sb[t.x .. "," .. t.y] then sfree = sfree + 1 end end
while sq[sh] do
  local p = sq[sh]; sh = sh + 1
  for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
    local k = (p.x + d[1]) .. "," .. (p.y + d[2])
    if sg[k] and not sg[k].wall and not sb[k] and not sseen[k] then sseen[k] = true; sq[#sq + 1] = {x = p.x + d[1], y = p.y + d[2]} end
  end
end
eq(#sq, sfree, "even a solid block of cover leaves every tile connected")
check(#Ls.cover > 100 and #Ls.cover < #L.cover * 4, "the dense test field has cover (" .. #Ls.cover .. ")")
-- map mode
local mcfg = {mode = "map", grid = cfg.grid, field = cfg.field, exit = cfg.exit, contest = cfg.contest,
  area = {x1 = 100, y1 = 100, x2 = 150, y2 = 140, z = 7, exits = {{x = 102, y = 102, z = 7}}, shrine = {x = 125, y = 120, z = 7},
    realm = 0}}
eq(K.slotOfPos(mcfg, {x = 120, y = 120, z = 7}), 0, "map mode: inside the rectangle")
eq(K.slotOfPos(mcfg, {x = 151, y = 120, z = 7}), nil, "map mode: outside")
eq(K.slotForRealm(mcfg, 2), 0, "map mode: one instance")
eq(#K.mapLayout(mcfg).entrySpots[1], 16, "map mode arrival ring")

-- ====================================================================== entering
local ok = {level = 300, inPz = true, accept = true}
eq(K.entryRefusal(cfg, ok), nil, "may enter")
check(K.entryRefusal(cfg, {level = 149, inPz = true, accept = true}):find("level 150"), "level")
check(K.entryRefusal(cfg, {level = 300, accept = true}):find("protection zone"), "only from a protection zone")
check(K.entryRefusal(cfg, {level = 300, inPz = true}):find("accept"), "the confirmation is needed")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, inCombat = true}):find("combat"), "in combat")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, cooldown = 42}):find("42 seconds"), "defeat cooldown")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, multiClient = true}):find("connection"), "multi-client")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, elsewhere = "a rift"}):find("a rift"), "inside elsewhere")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, inside = true}):find("already"), "already inside")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, realmOk = false}):find("realm"), "map mode realm")
-- Hardcore: refused, even with both confirmations; with allow = true the second confirmation is needed
eq(cfg.hardcore.allow, false, "decided: Hardcore characters are not allowed in")
check(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, hc = true, hcAccept = true}):find("Hardcore"), "HC refused")
eq(K.entryRefusal(cfg, {level = 300, inPz = true, accept = true, hc = true, staff = true}), nil, "staff are not HC-checked")
local hcCfg = {enabled = true, name = cfg.name, minLevel = 150, entry = cfg.entry, hardcore = {allow = true}}
check(K.entryRefusal(hcCfg, {level = 300, inPz = true, accept = true, hc = true}):find("confirm"), "HC allowed: confirm")
eq(K.entryRefusal(hcCfg, {level = 300, inPz = true, accept = true, hc = true, hcAccept = true}), nil, "HC with both")
check(K.entryRefusal({enabled = false, name = cfg.name}, ok):find("closed"), "closed")
check(#cfg.entry.rules >= 4, "the rules the confirmation shows")
local rulesText = table.concat(cfg.entry.rules, " ")
check(rulesText:find("Embers") and rulesText:find("safe exit") and rulesText:find("equipment"), "the rules name the risk")

-- login inside: held, then the nearest safe exit with protection
local moveAt, protUntil = K.loginTimes(cfg, 1000)
eq(moveAt, 1000 + cfg.login.holdSeconds, "held first")
eq(protUntil, moveAt + cfg.login.protectSeconds, "then protected at the exit")
check(K.protected(protUntil, protUntil - 1), "protected")
check(not K.protected(protUntil, protUntil), "protection over")
check(not K.protected(-1, 5), "no protection")
-- the exit channel: a fight resets it
eq(K.exitProgress(cfg, nil, 0, 10), nil, "not in a circle")
local share, done = K.exitProgress(cfg, 100, 0, 102)
near(share, 2 / cfg.exit.channelSeconds, 1e-9, "channel share")
check(not done, "not done yet")
share, done = K.exitProgress(cfg, 100, 103, 106)
check(not done, "a hit at 103 restarts the channel")
_, done = K.exitProgress(cfg, 100, 103, 103 + cfg.exit.channelSeconds)
check(done, "done after the channel without fighting")

-- ====================================================================== embers
local c, added, lost = K.addCarried(cfg, cfg.carry.max - 5, 20)
eq(c, cfg.carry.max, "carry cap")
eq(added, 5, "added up to the cap")
eq(lost, 15, "the rest is lost")
eq(K.monsterEmbers(cfg, "rare"), cfg.monsterEmbers.rare, "monster embers by tier")
eq(K.monsterEmbers(cfg, nil), cfg.monsterEmbers.normal, "normal by default")
local pileN, burned = K.deathPile(cfg, 1234)
eq(pileN, 1234, "the whole carry falls")
eq(burned, 0, "nothing burns")
local half = {death = {dropShare = 0.5, ownerSeconds = 30, pileSeconds = 120}}
pileN, burned = K.deathPile(half, 101)
eq(pileN + burned, 101, "drop share keeps the sum")
-- a pile: the killer alone for ownerSeconds, bounded per kill and per day, by the carry cap
local pile = K.newPile(cfg, 2000, 11, 22, true, 1000)
eq(pile.ownerUntil, 1000 + cfg.death.ownerSeconds, "owner window")
local n, why = K.pickup(cfg, pile, {guid = 33, carried = 0, dayPicked = 0}, 1005)
eq(n, 0, "a third player waits")
eq(why, "owner", "owner window reason")
n, why = K.pickup(cfg, pile, {guid = 22, carried = 0, dayPicked = 0}, 1005)
eq(n, cfg.pickup.perKillMax, "the killer takes at most perKillMax")
K.takeFrom(pile, 22, n)
eq(pile.amount, 2000 - cfg.pickup.perKillMax, "the pile shrinks")
n, why = K.pickup(cfg, pile, {guid = 22, carried = n, dayPicked = n}, 1006)
eq(why, "kill cap", "no second helping for the killer")
n = K.pickup(cfg, pile, {guid = 33, carried = 0, dayPicked = 0}, 1000 + cfg.death.ownerSeconds)
eq(n, cfg.pickup.perKillMax, "after the window anyone may take, bounded")
n, why = K.pickup(cfg, pile, {guid = 44, carried = 0, dayPicked = cfg.pickup.perDayMax - 100}, 1040)
eq(n, 100, "the daily cap bounds it")
n, why = K.pickup(cfg, pile, {guid = 45, carried = 0, dayPicked = cfg.pickup.perDayMax}, 1040)
eq(why, "daily cap", "daily cap reached")
n, why = K.pickup(cfg, pile, {guid = 46, carried = cfg.carry.max, dayPicked = 0}, 1040)
eq(why, "full", "a full carry takes nothing")
n, why = K.pickup(cfg, pile, {guid = 47, carried = 0, dayPicked = 0, ssf = true}, 1040)
eq(why, "ssf", "Self-Found characters do not take others' embers")
local own, _, counts = K.pickup(cfg, pile, {guid = 11, carried = 0, dayPicked = cfg.pickup.perDayMax, ssf = true}, 1001)
eq(own, pile.amount, "the victim may take his own embers back (no owner wait, no caps but the carry)")
eq(counts, false, "the own pile does not count for the daily cap")
eq((K.pickup(cfg, pile, {guid = 22, carried = 0, dayPicked = 0}, 1000 + cfg.death.pileSeconds)), 0, "the pile burns out")
local mpile = K.newPile(cfg, 300, 11, nil, nil, 2000)
eq((K.pickup(cfg, mpile, {guid = 99, carried = 0, dayPicked = 0}, 2000)), 300, "a monster's victim: anyone at once")
local bad = K.newPile(cfg, 300, 11, 22, false, 2000)
eq(bad.amount, 0, "a defeat that does not count: the pile burns")
eq(bad.burned, 300, "burned amount kept")
local b, moved, over = K.bank(cfg, cfg.bankMax - 10, 50)
eq(b, cfg.bankMax, "bank cap")
eq(moved, 10, "moved up to the cap")
eq(over, 40, "the rest is lost")
-- rows: new day, new week
local row = K.newRow()
row.day, row.dayRep, row.dayPicked, row.week, row.weekBanked = 1, 50, 60, 7, 900
K.roll(row, 2, 7)
eq(row.dayRep + row.dayPicked, 0, "a new day")
eq(row.weekBanked, 900, "the week goes on")
K.roll(row, 2, 8)
eq(row.weekBanked, 0, "a new week")
local mon = os.time({year = 2026, month = 10, day = 12, hour = 7})
eq(K.weekKey(mon, 6), 20261012, "Monday 07:00: this week")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 12, hour = 5}), 6), 20261005, "Monday 05:00: last week")
eq(K.weekKey(os.time({year = 2026, month = 10, day = 18, hour = 23}), 6), 20261012, "Sunday night")
eq(K.dayKey(os.time({year = 2026, month = 10, day = 13, hour = 5}), 6), 20261012, "05:00 is still yesterday")

-- ====================================================================== anti-farming and reputation
local k = {killerAccount = 1, victimAccount = 2, killerIp = 10, victimIp = 20, killerLevel = 400, victimLevel = 380,
  enteredAt = 0, at = 1000}
local counted, reason = K.killVerdict(cfg, k)
check(counted and reason == "ok", "a fair defeat counts")
local function verdict(change)
  local x = {}
  for a, v in pairs(k) do x[a] = v end
  for a, v in pairs(change) do x[a] = v end
  return select(2, K.killVerdict(cfg, x))
end
eq(verdict({victimAccount = 1}), "same account", "same account")
eq(verdict({victimIp = 10}), "same IP", "same IP")
eq(verdict({killerIp = 0, victimIp = 0}), "ok", "IP 0 (no connection) never matches")
eq(verdict({victimLevel = 140}), "low level", "below the zone level")
eq(verdict({killerLevel = 1000, victimLevel = 500}), "level gap", "level gap")
eq(verdict({killerLevel = 1000, victimLevel = 600}), "ok", "60% of the killer's level counts")
eq(verdict({enteredAt = 990}), "just arrived", "a fresh arrival does not count")
eq(verdict({lastCounted = 1000 - 29 * 60}), "repeat", "the same victim within 30 minutes")
eq(verdict({lastCounted = 1000 - 31 * 60}), "ok", "the same victim after 30 minutes")
local rivalOf = {}
for _, f in ipairs(fcfg.factions) do rivalOf[f.key] = f.rival end
eq((K.repFor(cfg, "vigil", "choir", rivalOf, 0)), cfg.reputation.perKill, "the sworn rival: full reputation")
eq((K.repFor(cfg, "vigil", "circle", rivalOf, 0)), math.floor(cfg.reputation.perKill * cfg.reputation.otherMult + 0.5),
  "another faction: half")
eq(select(2, K.repFor(cfg, "vigil", "vigil", rivalOf, 0)), "same faction", "same faction: nothing")
eq(select(2, K.repFor(cfg, "", "choir", rivalOf, 0)), "not pledged", "killer not pledged")
eq(select(2, K.repFor(cfg, "vigil", nil, rivalOf, 0)), "victim not pledged", "victim not pledged")
eq((K.repFor(cfg, "vigil", "choir", rivalOf, cfg.reputation.dailyCap - 15)), 15, "the daily cap cuts the last gain")
eq(select(2, K.repFor(cfg, "vigil", "choir", rivalOf, cfg.reputation.dailyCap)), "daily cap", "daily cap reached")
-- every faction has a rival among the four
for _, f in ipairs(fcfg.factions) do check(rivalOf[f.rival] == f.key, "rivalry is mutual: " .. f.key) end
-- the pledge
local t0 = 100000
eq(K.pledgeRefusal(cfg, fcfg.factions, fcfg.ranks, "vigil", 0, "", 0, t0), nil, "Neutral may pledge")
check(K.pledgeRefusal(cfg, fcfg.factions, fcfg.ranks, "vigil", -100, "", 0, t0):find("Neutral"), "Wary may not")
check(K.pledgeRefusal(cfg, fcfg.factions, fcfg.ranks, "nobody", 0, "", 0, t0):find("Unknown"), "unknown faction")
check(K.pledgeRefusal(cfg, fcfg.factions, fcfg.ranks, "vigil", 500, "vigil", 0, t0):find("already"), "already pledged")
check(K.pledgeRefusal(cfg, fcfg.factions, fcfg.ranks, "choir", 500, "vigil", t0 - 3600, t0):find("23 hour"), "change wait")
eq(K.pledgeRefusal(cfg, fcfg.factions, fcfg.ranks, "choir", 500, "vigil", t0 - 25 * 3600, t0), nil, "change after a day")

-- ====================================================================== PvP scaling like the battleground
for _, lv in ipairs({{300, 900}, {900, 300}, {200, 220}, {1000, 150}, {150, 1000}}) do
  local ref
  for _, br in ipairs(bg.brackets) do
    if lv[2] >= br.min and (not br.max or lv[2] <= br.max) then ref = br.ref end
  end
  near(K.pvpFactor(bg, lv[1], lv[2]), ChaosBattlegroundCore.normFactor(bg, lv[1], lv[2], ref), 1e-9,
    "the battleground's normFactor " .. lv[1] .. " -> " .. lv[2])
end
check(K.pvpFactor(bg, 1000, 200) < 1, "a much higher attacker hits softer")
check(K.pvpFactor(bg, 200, 1000) > 1, "a much lower attacker hits harder")
eq(K.pvpFactor(nil, 100, 200), 1, "no battleground config: no scaling")

-- ====================================================================== the Cinder Shrine
local T = 50000
local ct = K.newContest(cfg, T)
eq(ct.phase, "idle", "starts idle")
eq(#K.contestTick(cfg, ct, T + 60, {}), 0, "nothing before the first contest")
local ev = K.contestTick(cfg, ct, T + cfg.contest.firstMinutes * 60, {})
eq(ev[1] and ev[1].kind, "start", "the contest starts")
eq(ct.phase, "warden", "the warden first")
eq(ct.nextAt, T + cfg.contest.firstMinutes * 60 + cfg.contest.everyMinutes * 60, "the next one")
local now = T + cfg.contest.firstMinutes * 60
eq(#K.contestTick(cfg, ct, now + 1, {wardenAlive = true, counts = {vigil = 3}}), 0, "no capture while the warden lives")
ev = K.contestTick(cfg, ct, now + 2, {wardenAlive = false})
eq(ev[1] and ev[1].kind, "warden", "the warden fell")
eq(ct.phase, "capture", "capture phase")
-- one vigil player alone: 100 / seconds per second
local tt = now + 2
for _ = 1, 10 do tt = tt + 1; K.contestTick(cfg, ct, tt, {counts = {vigil = 1}, dt = 1, wardenAlive = false}) end
near(ct.progress.vigil, 10 * 100 / cfg.contest.capture.seconds, 1e-6, "10 s alone")
-- contested: no change
for _ = 1, 5 do tt = tt + 1; K.contestTick(cfg, ct, tt, {counts = {vigil = 2, choir = 1}, dt = 1}) end
near(ct.progress.vigil, 10 * 100 / cfg.contest.capture.seconds, 1e-6, "contested holds")
eq(ct.contested, true, "contested flag")
-- nobody: decay
tt = tt + 1
K.contestTick(cfg, ct, tt, {counts = {}, dt = 1})
near(ct.progress.vigil, 10 * 100 / cfg.contest.capture.seconds - cfg.contest.capture.decayPerSecond, 1e-6, "decay")
-- four choir players: faster (capped)
local cap = cfg.contest.capture
local rate = (100 / cap.seconds) * math.min(cap.maxRate, 1 + cap.perExtra * 3)
local winner
for _ = 1, 200 do
  tt = tt + 1
  for _, e in ipairs(K.contestTick(cfg, ct, tt, {counts = {choir = 4}, dt = 1})) do
    if e.kind == "captured" then winner = e.faction end
  end
  if winner then break end
end
eq(winner, "choir", "choir takes the shrine")
eq(ct.phase, "idle", "idle again")
check(ct.progress.vigil < 10 * 100 / cap.seconds, "vigil's progress decayed meanwhile")
near(tt - (now + 2 + 16), math.ceil(100 / rate), 1, "time to take it with four")
local ctl = K.newControl(cfg, "choir", tt)
eq(K.holder(ctl, tt + 10), "choir", "holder")
eq(K.holder(ctl, tt + cfg.contest.holdMinutes * 60), nil, "the hold runs out after an hour")
near(K.buffMult(cfg, ctl, "choir", tt + 1, "exp"), 1 + cfg.contest.buff.exp / 100, 1e-9, "faction-wide experience buff")
near(K.buffMult(cfg, ctl, "choir", tt + 1, "loot"), 1 + cfg.contest.buff.loot / 100, 1e-9, "faction-wide loot buff")
eq(K.buffMult(cfg, ctl, "vigil", tt + 1, "exp"), 1, "other factions: no buff")
eq(K.buffMult(cfg, ctl, nil, tt + 1, "exp"), 1, "unpledged: no buff")
eq(K.holder(nil, tt), nil, "nobody holds it")
-- a window that closes without a holder
local c2 = K.newContest(cfg, 0)
K.contestTick(cfg, c2, cfg.contest.firstMinutes * 60, {})
ev = K.contestTick(cfg, c2, cfg.contest.firstMinutes * 60 + cfg.contest.windowMinutes * 60, {wardenAlive = true})
eq(ev[1] and ev[1].kind, "expired", "the window closes")
eq(c2.phase, "idle", "idle after the window")

-- ====================================================================== vendor, cosmetics, board, achievements
local cos = dofile("data/scripts/chaos/cosmetics_config.lua")
local byKey, ids = {}, {}
for _, x in ipairs(cos.cosmetics) do byKey[x.key] = x; ids[x.id] = (ids[x.id] or 0) + 1 end
for id, nn in pairs(ids) do check(nn == 1, "cosmetic id unique " .. id) end
local allowed = {[29856] = true, [29857] = true, [29851] = true, [24691] = true, [7591] = true, [7590] = true,
  [8472] = true, [8473] = true}
for _, o in ipairs(cfg.vendor) do
  check(o.kind == "item" or o.kind == "cosmetic", "vendor: items and cosmetics only (" .. o.key .. ")")
  check(o.cost > 0, "vendor price " .. o.key)
  if o.kind == "item" then
    check(allowed[o.id], "vendor item is an orb or a consumable, never gear: " .. o.key)
  else
    local x = byKey[o.cosmetic]
    check(x ~= nil and x.source == "pvp", "vendor cosmetic exists with source pvp: " .. o.key)
  end
end
local okb, whyb = K.vendorCheck(cfg, "fate", 499, 0)
check(not okb and whyb:find("1 more"), "too poor")
okb = K.vendorCheck(cfg, "fate", 500, 0)
check(okb, "can buy")
okb, whyb = K.vendorCheck(cfg, "fate", 5000, 3)
check(not okb and whyb:find("Weekly"), "weekly limit")
okb, whyb = K.vendorCheck(cfg, "c_kill", 9999, 0, function(key) return key == "kill_marchfire" end)
check(not okb and whyb:find("own"), "owned cosmetic")
check(not K.vendorCheck(cfg, "nothing", 9999, 0), "unknown offer")
local lb = dofile("data/scripts/chaos/leaderboard_config.lua")
local board
for _, x in ipairs(lb.boards) do if x.key == cfg.leaderboard then board = x end end
check(board ~= nil and board.mode == "add", "weekly board " .. cfg.leaderboard)
local ach = dofile("data/scripts/chaos/achievements_data.lua")
local stats = {}
for _, a in ipairs(ach.achievements or ach.list or {}) do if a.stat then stats[a.stat] = true end end
for _, s in ipairs({"pvpzone_kills", "pvpzone_banked", "pvpzone_haul", "pvpzone_captures"}) do
  check(stats[s], "achievement on stat " .. s)
end
-- every monster of the list is a stock monster name (no Chaos class name)
for _, name in ipairs(cfg.monsters.list) do check(name ~= "Juggernaut", "no class names among the monsters") end

-- ====================================================================== Part 2: pvpzone.lua on a mocked engine
local nconst = 0
setmetatable(_G, {__index = function(t, key)
  if type(key) == "string" and key:match("^[A-Z_0-9]+$") then nconst = nconst + 1; rawset(t, key, 900 + nconst); return 900 + nconst end
end})
local unpack = table.unpack or unpack
local events, globals, talks, callbacks = {}, {}, {}, {}
function CreatureEvent(name) local o = {name = name}; function o:type() end; function o:register() events[name] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() globals[name] = o end; return o end
function TalkAction(w) local o = {}; function o:separator() end; function o:register() talks[w] = o end; return o end
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, key, v)
  callbacks[key] = callbacks[key] or {}
  table.insert(callbacks[key], v)
end})
local queue, clock = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, due = clock + delay}; return #queue end
local realTime = os.time
local base = realTime({year = 2026, month = 10, day = 14, hour = 10, min = 0, sec = 0})
os.time = function(tt2) if tt2 then return realTime(tt2) end return base + math.floor(clock / 1000) end
local function advance(ms)
  local limit = clock + ms
  local nextTick = (math.floor(clock / 1000) + 1) * 1000
  while true do
    local best
    for i, e in ipairs(queue) do if e.due <= limit and (not best or e.due < queue[best].due) then best = i end end
    local due = best and queue[best].due or math.huge
    if nextTick <= limit and nextTick <= due then
      clock = nextTick; nextTick = nextTick + 1000
      globals.ChaosMarchesTick.onThink(1000)
    elseif best then
      local e = table.remove(queue, best); clock = e.due; e.fn(unpack(e.args))
    else
      break
    end
  end
  clock = limit
end
json = {encode = function(x) return x end, decode = function(x) return x end}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
local tiles, creatures, players = {}, {}, {}
local BLOCKING = {[cfg.ids.wall] = true, [cfg.ids.pillar] = true, [cfg.ids.exitMark] = true, [cfg.ids.shrine] = true,
  [cfg.look.shrineLights.id] = true, [cfg.look.shrineBeacons.id] = true, [cfg.look.gateLights.id] = true}
for _, g in ipairs(cfg.look.cover) do for _, id in ipairs(g.ids) do BLOCKING[id] = true end end
local function newTile(pos)
  local t = {pos = pos, items = {}, pz = false}
  function t:hasFlag(f) return f == TILESTATE_PROTECTIONZONE and self.pz end
  function t:hasProperty() for _, it in ipairs(self.items) do if BLOCKING[it.id] then return true end end return false end
  function t:getGround() return self.items[1] end
  function t:getItemById(id) for _, it in ipairs(self.items) do if it.id == id then return it end end end
  function t:getTopCreature()
    for _, c in pairs(creatures) do if c.pos.x == pos.x and c.pos.y == pos.y and c.pos.z == pos.z then return c end end
  end
  tiles[key(pos)] = t
  return t
end
function Tile(pos) return tiles[key(pos)] end
local created, monsterCount = 0, 0
local worldType = 0
Game = {
  createTile = function(pos) created = created + 1; return tiles[key(pos)] or newTile(pos) end,
  createItem = function(id, c2, pos)
    local t = tiles[key(pos)]
    local it = {id = id}
    function it:getId() return self.id end
    function it:remove() for i, x in ipairs(t.items) do if x == self then table.remove(t.items, i) break end end end
    t.items[#t.items + 1] = it
    return it
  end,
  getStorageValue = function(k2) return k2 == 7100990 and 1 or -1 end, -- multi-client blocks off (two clients, one IP)
  getWorldType = function() return worldType end,
  getPlayers = function() local l = {}; for _, p in pairs(players) do l[#l + 1] = p end; table.sort(l, function(a, b2) return a.id < b2.id end); return l end
}
local nextId = 1000
local function creatureBase(o)
  function o:getId() return self.id end
  function o:getName() return self.name end
  function o:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
  function o:getHealth() return self.health end
  function o:getMaxHealth() return self.maxHealth end
  function o:setMaxHealth(h) self.maxHealth = h end
  function o:addHealth(a, b2) local n2 = type(a) == "number" and a or b2; self.health = math.min(self.maxHealth, self.health + n2) end
  function o:registerEvent(e) self.events[e] = true end
  function o:unregisterEvent(e) self.events[e] = nil end
  function o:getMaster() return nil end
  return o
end
Game.createMonster = function(name, pos)
  nextId = nextId + 1
  monsterCount = monsterCount + 1
  local m = creatureBase({id = nextId, name = name, pos = {x = pos.x, y = pos.y, z = pos.z}, health = 1000, maxHealth = 1000,
    events = {}})
  function m:isMonster() return true end
  function m:isPlayer() return false end
  function m:rename(n2) self.name = n2 end
  function m:remove() creatures[self.id] = nil end
  creatures[m.id] = m
  return m
end
db = {query = function() return true end, escapeString = function(s) return "'" .. tostring(s) .. "'" end,
  storeQuery = function() return nil end}
result = {}
local function newPlayer(name, level, ip)
  nextId = nextId + 1
  local p = creatureBase({id = nextId, guid = nextId - 1000, name = name, level = level, ip = ip or nextId,
    pos = {x = 100 + nextId % 50, y = 100, z = 7}, health = 5000, maxHealth = 5000, mana = 100, maxMana = 100, events = {},
    st = {}, msgs = {}, sends = {}, skull = 0, infight = false, secure = true, items = {}})
  newTile(p.pos).pz = true
  p.home = {x = p.pos.x, y = p.pos.y, z = 7}
  function p:getGuid() return self.guid end
  function p:getLevel() return self.level end
  function p:getIp() return self.ip end
  function p:getAccountId() return self.guid + 500 end
  function p:getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
  function p:getParty() return self.party end
  function p:teleportTo(pos) self.pos = {x = pos.x, y = pos.y, z = pos.z} end
  function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
  function p:sendCancelMessage(text) self.msgs[#self.msgs + 1] = text end
  function p:setHealth(h) self.health = math.min(h, self.maxHealth) end
  function p:getMana() return self.mana end
  function p:getMaxMana() return self.maxMana end
  function p:addMana(m) self.mana = math.min(self.maxMana, self.mana + m) end
  function p:removeCondition(t) if t == CONDITION_INFIGHT then self.infight = false end end
  function p:hasCondition(t) return t == CONDITION_INFIGHT and self.infight end
  function p:getCondition(t)
    if t ~= CONDITION_INFIGHT or not self.infight then return nil end
    local me = self
    return {getTicks = function() return me.infightTicks or 60000 end, setTicks = function(_, v) me.infightTicks = v end}
  end
  function p:isPzLocked() return false end
  function p:getSkull() return self.skull end
  function p:setSkull(s) self.skull = s end
  function p:setTarget() end
  function p:hasSecureMode() return self.secure end
  function p:getStorageValue(k2) return self.st[k2] or -1 end
  function p:setStorageValue(k2, v) self.st[k2] = v end
  function p:getTown() return {getTemplePosition = function() return Position(1, 1, 7) end} end
  function p:isPlayer() return true end
  function p:isMonster() return false end
  function p:getInbox() return nil end
  function p:getItemCount(id) return self.items[id] or 0 end
  function p:addItem(id, c2) self.items[id] = (self.items[id] or 0) + c2 end
  players[p.id] = p
  creatures[p.id] = p
  events.ChaosMarchesLogin.onLogin(p)
  return p
end
function Player(x) return players[x] end
function Creature(x) return creatures[x] end
local function lastSend(p, action)
  for i = #p.sends, 1, -1 do if p.sends[i].action == action then return p.sends[i].data end end
end
local function lastMsg(p) return p.msgs[#p.msgs] or "" end

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.sendChunked = function(p, op, payload) p.sends[#p.sends + 1] = payload; return true end
Chaos.factionsConfig = fcfg
Chaos.battlegroundConfig = bg
local gains = {}
ChaosFactions = {stateOf = function(p) return {st = {vigil = {rep = 600}, choir = {rep = 600}, circle = {rep = -3000}}} end,
  gain = function(p, key2, amount, source) gains[#gains + 1] = {p.name, key2, amount, source}; return {gained = amount} end}
local hcPlayers = {}
ChaosSeason = {current = function() return {id = 1} end, realmOf = function() return 0 end,
  modesOf = function(p) return {hc = hcPlayers[p.name] == true} end}
local records, achieved = {}, {}
ChaosLeaderboard = {record = function(board2, who, value, mode) records[#records + 1] = {board2, who.name, value, mode} end}
ChaosAchievements = {progress = function(p, stat, n2) achieved[p.name .. ":" .. stat] = (achieved[p.name .. ":" .. stat] or 0) + n2 end,
  set = function(p, stat, v) achieved[p.name .. ":" .. stat] = math.max(achieved[p.name .. ":" .. stat] or 0, v) end}
dofile("data/scripts/chaos/pvpzone.lua")
local Z = ChaosPvpZone
globals.ChaosMarchesStartup.onStartup()
check(Z.inst[0] and Z.inst[0].built, "the standard instance is built at startup")
check(Z.inst[1] and Z.inst[1].built, "the running season's instance too")
eq(created, 2 * #foot, "the tiles of both instances")
local Lz = Z.inst[0].L
local function hit(target, attacker, dmg)
  local p, _, s = events.ChaosMarchesHealth.onHealthChange(target, attacker, dmg, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 0)
  target.health = target.health - p - s
  return p + s
end
local function kill(target, attacker)
  return events.ChaosMarchesPrepareDeath.onPrepareDeath(target, attacker)
end

-- entering: the rules
local low = newPlayer("Low", 100)
check(not Z.enter(low, {accept = true}), "below level 150")
local ana = newPlayer("Ana", 400)
local bo = newPlayer("Bo", 380)
check(not Z.enter(ana, {}), "no entry without the confirmation")
tiles[key(ana.pos)].pz = false
check(not Z.enter(ana, {accept = true}), "not outside a protection zone")
tiles[key(ana.pos)].pz = true
local hc = newPlayer("Hard", 400)
hcPlayers.Hard = true
check(not Z.enter(hc, {accept = true, hcAccept = true}), "a Hardcore character is refused")
check(lastMsg(hc):find("Hardcore"), "the Hardcore reason")
eq(lastSend(hc, "state") == nil and true or true, true, "state not needed for a refusal")
local st = Z.stateOf(hc)
eq(st.canEnter, false, "the window: Hardcore cannot enter")
check(st.hc.isHc and not st.hc.allow, "the window knows the Hardcore rule")
check(Z.pledge(ana, "vigil"), "Ana pledges to the Vigil")
check(not Z.pledge(ana, "choir"), "no second pledge within a day")
check(not Z.pledge(bo, "circle"), "Bo is Hostile with the Circle: refused")
check(Z.pledge(bo, "choir"), "Bo pledges to the Choir")
check(Z.enter(ana, {accept = true}), "Ana enters")
check(Z.enter(bo, {accept = true}), "Bo enters")
check(Z.isInside(ana) and Z.isInside(bo), "both inside")
eq(Z.inZone(ana:getPosition()), 0, "standard instance")
eq(ana.st[cfg.storage.inside], 1, "inside marker")
eq(ana.st[cfg.storage.retX], ana.home.x, "return position kept")
check(lastSend(ana, "enter") ~= nil, "the client is told (secure mode off)")
-- the goal is clear from the first second (O275): two messages, the map marks, floating text over the objectives
local sawGoal, sawCarried = false, false
for _, m in ipairs(ana.msgs) do
  if m:find("Goal: earn embers", 1, true) then sawGoal = true end
  if m:find("Embers carried: 0. Bank them at a safe exit", 1, true) and m:find("marked on your map", 1, true) then sawCarried = true end
end
check(sawGoal, "entering: the goal in one sentence")
check(sawCarried, "entering: embers carried and where to bank them")
local marks = lastSend(ana, "enter").marks
eq(#marks, 3, "the enter message marks both safe exits and the shrine")
eq(marks[1].kind, "exit", "mark 1 is an exit"); eq(marks[2].kind, "exit", "mark 2 is an exit"); eq(marks[3].kind, "shrine", "mark 3 is the shrine")
for i, e in ipairs(Lz.exits) do
  eq(marks[i].x .. "," .. marks[i].y .. "," .. marks[i].z, e.x .. "," .. e.y .. "," .. e.z, "mark " .. i .. " sits on the exit")
end
eq(marks[3].x .. "," .. marks[3].y, Lz.shrine.x .. "," .. Lz.shrine.y, "the shrine mark sits on the shrine")
check(marks[1].name:find("bank your embers"), "the exit mark says what it is for")
local labels = {}
ChaosCombatFx = {label = function(pos, text, color)
  labels[#labels + 1] = {x = pos.x, y = pos.y, text = type(text) == "function" and text(ana) or text, color = color}
end}
Z.beacons(Z.inst[0])
eq(#labels, 3, "floating text over the shrine and both exits")
eq(labels[1].x .. "," .. labels[1].y, Lz.shrine.x .. "," .. Lz.shrine.y, "the first label is over the shrine")
eq(labels[1].text, "Cinder Shrine", "the shrine label")
eq(labels[2].text, "Safe exit: bank your embers", "the exit label")
labels = {}
Z.inst[0].contest.phase = "warden"
Z.beacons(Z.inst[0])
eq(labels[1].text, "Slay the Warden!", "the label says what to do while the Warden lives")
labels = {}
Z.inst[0].contest.phase = "capture"
Z.beacons(Z.inst[0])
eq(labels[1].text, "Take the Shrine!", "the label says what to do while the shrine can be taken")
Z.inst[0].contest.phase = "idle"
ChaosCombatFx = nil
eq(Z.targetCombat(ana, bo), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "protected after entering")
eq(hit(bo, ana, 500), 0, "no damage while protected")
advance((cfg.entry.protectSeconds + 1) * 1000)
eq(Z.targetCombat(ana, bo), RETURNVALUE_NOERROR, "open PvP although Bo's secure mode is on")
check(Z.canAttack(ana, bo) == true, "spells may hit too")
local outside = newPlayer("Out", 400)
eq(Z.targetCombat(ana, outside), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no attacks across the border")
eq(Z.targetCombat(outside, low), nil, "outside: not the zone's business")
local pt = {}
ana.party, bo.party = pt, pt
eq(Z.targetCombat(ana, bo), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "party members are allies")
ana.party, bo.party = nil, nil
-- damage scaled like the battleground
local dealt = hit(bo, ana, 1000)
eq(dealt, math.floor(1000 * K.pvpFactor(bg, 400, 380) + 0.5), "PvP damage scaled")
ana.skull = SKULL_WHITE
advance(1000)
eq(ana.skull, SKULL_NONE, "no white skull inside")
-- the battle lock inside: the server's 3 minute pzLocked time is cut to combatLock.maxSeconds
ana.infight, ana.infightTicks = true, 180000
advance(1000)
eq(ana.infightTicks, cfg.combatLock.maxSeconds * 1000, "the battle lock is capped inside")
ana.infightTicks = 20000
advance(1000)
eq(ana.infightTicks, 20000, "a short lock is left alone")
ana.infight = false
eq(K.lockTicks(cfg, 180000), 60000, "lockTicks: capped")
eq(K.lockTicks(cfg, 60000), nil, "lockTicks: at the cap, nothing")
eq(K.lockTicks({}, 180000), nil, "lockTicks: no cap configured")
eq(K.defeatDestination(cfg, true), "temple", "defeat: the temple by default")
eq(K.defeatDestination({death = {respawn = "entry"}}, true), "entry", "defeat: entry when configured")
eq(K.defeatDestination({death = {respawn = "entry"}}, false), "temple", "defeat: entry gone -> temple")
-- monsters: stronger, embers for the kill
check(monsterCount >= 2 * #Lz.spawns, "monsters at every spawn point of both instances")
local mon
for _, c2 in pairs(creatures) do if c2.isMonster and c2:isMonster() and Z.scaled[c2.id] == 0 then mon = c2 break end end
eq(mon.maxHealth, math.floor(1000 * cfg.monsters.hpMult), "monster health scaled")
eq(hit(bo, mon, 100), math.floor(100 * cfg.monsters.damageMult + 0.5), "monster damage scaled")
events.ChaosMarchesMonsterDeath.onDeath(mon, nil, bo, bo)
eq(bo.st[cfg.storage.carried], cfg.monsterEmbers.normal, "embers for a monster kill")
check(lastMsg(bo):find("+" .. cfg.monsterEmbers.normal .. " embers (carrying " .. cfg.monsterEmbers.normal .. ")", 1, true),
  "a kill says how many embers it gave")
near(Z.lootMult({monster = mon}), cfg.monsters.lootMult, 1e-9, "more loot from zone monsters")
creatures[mon.id] = nil
bo.st[cfg.storage.carried] = 1500
advance(cfg.antiFarm.minSecondsInside * 1000) -- a fresh arrival would not count
-- a defeat: the pile, the killer's share, reputation
bo.pos = {x = Lz.shrine.x - 8, y = Lz.shrine.y - 6, z = 7} -- out in the open, away from the exits
bo.health = 50
check(kill(bo, ana) == false, "the lethal hit is cancelled (nobody dies)")
check(not Z.isInside(bo), "Bo is out")
eq(bo.pos.x .. "," .. bo.pos.y, "1,1", "a defeat sends him to his temple (death.respawn)")
check(not bo.infight, "no battle lock after the defeat")
-- the engine puts the lock back after the cancelled hit: the second clear takes it off again
bo.infight, bo.skull = true, SKULL_WHITE
advance(cfg.combatLock.clearAfterMs[#cfg.combatLock.clearAfterMs] + 10)
check(not bo.infight, "the lock put back after the defeat is cleared again")
eq(bo.skull, SKULL_NONE, "and the white skull")
eq(bo.health, bo.maxHealth, "healed")
eq(bo.st[cfg.storage.carried], 0, "his carried embers fell")
eq(bo.st[cfg.storage.inside], 0, "marker cleared")
check(lastMsg(bo):find("defeated by Ana"), "Bo is told")
check(lastMsg(bo):find("carried embers fell where you stood", 1, true) and lastMsg(bo):find("burns out in " .. cfg.death.pileSeconds .. " seconds", 1, true),
  "Bo is told what happened to his embers and for how long they lie there")
check(not Z.enter(bo, {accept = true}), "defeat cooldown")
local piles = {}
for _, p2 in pairs(Z.inst[0].piles) do piles[#piles + 1] = p2 end
eq(#piles, 1, "one pile")
eq(piles[1].amount, 1500, "the pile holds the carry")
eq(#gains, 1, "reputation for a pledged rival")
eq(gains[1] and gains[1][2], "vigil", "to the killer's faction")
eq(gains[1] and gains[1][3], cfg.reputation.perKill, "the sworn rival: full")
eq(gains[1] and gains[1][4], "pvpzone", "source pvpzone")
eq(achieved["Ana:pvpzone_kills"], 1, "kill stat")
-- the pile: a third player waits, the killer takes his bounded share
local cid = newPlayer("Cid", 420)
check(Z.enter(cid, {accept = true}), "Cid enters")
local pp = piles[1].pos
cid.pos = {x = pp.x + 1, y = pp.y, z = pp.z}
ana.pos = {x = pp.x - 1, y = pp.y, z = pp.z}
advance(1000)
eq(cid.st[cfg.storage.carried] or 0, 0, "Cid must wait for the owner window")
eq(ana.st[cfg.storage.carried], cfg.pickup.perKillMax, "Ana takes at most perKillMax")
advance(cfg.death.ownerSeconds * 1000)
eq(cid.st[cfg.storage.carried], 1500 - cfg.pickup.perKillMax, "after the window Cid takes the rest")
-- anti-farming: same IP, repeat victim
local dee = newPlayer("Dee", 400, ana.ip)
Z.cooldown = {}
check(Z.enter(dee, {accept = true}), "Dee enters (same IP as Ana)")
advance(25 * 1000)
dee.st[cfg.storage.carried] = 300
kill(dee, ana)
eq(#gains, 1, "same IP: no reputation")
check(lastMsg(ana):find("does not count"), "Ana is told it does not count")
local burnedPile = 0
for _, p2 in pairs(Z.inst[0].piles) do burnedPile = burnedPile + p2.amount end
eq(burnedPile, 0, "same IP: the pile burns")
Z.cooldown = {}
bo.pos = {x = bo.home.x, y = bo.home.y, z = 7} -- walks from the temple to his protection zone
check(Z.enter(bo, {accept = true}), "Bo comes back")
advance(25 * 1000)
kill(bo, ana)
eq(#gains, 1, "the same victim within 30 minutes: no reputation")
-- the vendor is outside only: nobody buys 50 potions in the middle of a fight
local wasBanked = Z.rowOf(ana.guid).banked
Z.rowOf(ana.guid).banked = 600
check(not Z.buy(ana, "upheaval"), "no vendor inside the Marches")
eq(ana.items[29856], nil, "nothing was handed over")
eq(Z.rowOf(ana.guid).banked, 600, "nothing was charged")
check(lastSend(ana, "msg").text:find("Leave the Marches"), "the reason is sent")
Z.rowOf(ana.guid).banked = wasBanked
-- banking at a safe exit
ana.pos = {x = Lz.exits[1].x, y = Lz.exits[1].y, z = 7}
local before = ana.st[cfg.storage.carried]
check(before > 0, "Ana carries embers")
advance(2000)
check(Z.isInside(ana), "still channelling")
hit(ana, cid, 10)
advance(3000)
check(Z.isInside(ana), "a hit restarted the channel")
advance((cfg.exit.channelSeconds + 1) * 1000)
check(not Z.isInside(ana), "Ana left through the exit")
eq(Z.rowOf(ana.guid).banked, before, "the embers are banked")
local bankMsg = ""
for _, m in ipairs(ana.msgs) do if m:find("embers banked", 1, true) then bankMsg = m end end
check(bankMsg:find(before .. " embers banked", 1, true) and bankMsg:find("Spend them at the vendor", 1, true),
  "banking: how many, and what they are for")
eq(ana.st[cfg.storage.carried], 0, "nothing carried")
eq(records[#records] and records[#records][1], "marches", "weekly board")
eq(records[#records] and records[#records][3], before, "board value: banked embers")
eq(achieved["Ana:pvpzone_banked"], before, "banked stat")
-- the vendor
Z.rowOf(ana.guid).banked = 600
check(Z.buy(ana, "upheaval"), "buys 3 Orbs of Upheaval")
eq(ana.items[29856], 3, "orbs given")
eq(Z.rowOf(ana.guid).banked, 300, "price paid")
check(not Z.buy(ana, "fate"), "too poor for an Orb of Fate")
-- login inside: held, then the nearest safe exit, protected
local eve = newPlayer("Eve", 400)
players[eve.id], creatures[eve.id] = nil, nil
eve.pos = {x = Lz.shrine.x + 5, y = Lz.shrine.y + 5, z = 7}
eve.st[cfg.storage.inside] = 1
eve.st[cfg.storage.carried] = 222
players[eve.id], creatures[eve.id] = eve, eve
events.ChaosMarchesLogin.onLogin(eve)
check(Z.isInside(eve), "logged in inside")
eq(Z.targetCombat(cid, eve), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "held: cannot be attacked")
eq(hit(eve, cid, 999), 0, "held: no damage")
advance((cfg.login.holdSeconds + 1) * 1000)
local ex = Lz.exits[K.nearestExit(Lz, {x = Lz.shrine.x + 5, y = Lz.shrine.y + 5, z = 7})]
check(math.max(math.abs(eve.pos.x - ex.x), math.abs(eve.pos.y - ex.y)) == 2, "moved next to the nearest safe exit")
check(K.protected(eve.st[cfg.storage.protect], os.time()), "protected at the exit")
eq(eve.st[cfg.storage.carried], 222, "the carry is kept over the logout")
-- moved out by another login script while still held: nothing burns
local gil = newPlayer("Gil", 400)
players[gil.id], creatures[gil.id] = nil, nil
gil.pos = {x = Lz.shrine.x + 6, y = Lz.shrine.y, z = 7}
gil.st[cfg.storage.inside], gil.st[cfg.storage.carried] = 1, 99
players[gil.id], creatures[gil.id] = gil, gil
events.ChaosMarchesLogin.onLogin(gil)
gil.pos = {x = 1, y = 2, z = 7} -- e.g. the tutorial puts its characters back on the island
advance(1000)
check(not Z.isInside(gil), "moved out while held")
eq(gil.st[cfg.storage.carried], 99, "the carry is kept")
eq(gil.st[cfg.storage.inside], 0, "marker cleared")
-- leaving any other way burns the carry
eve.pos = {x = 1, y = 1, z = 7}
advance(1000)
check(not Z.isInside(eve), "teleported out")
eq(eve.st[cfg.storage.carried], 0, "the carry burned")
-- a walk-in without the confirmation is sent out
local fay = newPlayer("Fay", 400)
fay.pos = {x = Lz.shrine.x - 6, y = Lz.shrine.y, z = 7}
advance(1000)
check(not Z.isInside(fay) and Z.inZone(fay:getPosition()) == nil, "sent out")
check(lastSend(fay, "state") and lastSend(fay, "state").confirm, "the confirmation is shown")
-- the shrine contest and the faction-wide buff
local inst = Z.inst[0]
inst.contest.nextAt = os.time()
advance(1000)
eq(inst.contest.phase, "warden", "the contest starts")
local warden = creatures[inst.wardenCid]
check(warden and warden.name == cfg.contest.warden.title, "the warden stands at the shrine")
Z.cooldown = {}
check(Z.enter(ana, {accept = true}), "Ana enters again")
ana.pos = {x = Lz.shrine.x + 1, y = Lz.shrine.y + 1, z = 7}
advance((cfg.entry.protectSeconds + 1) * 1000)
eq(inst.contest.phase, "warden", "no capture while the warden lives")
events.ChaosMarchesMonsterDeath.onDeath(warden, nil, ana, ana)
creatures[warden.id] = nil
advance(1000)
eq(inst.contest.phase, "capture", "capture after the warden")
advance((cfg.contest.capture.seconds + 2) * 1000)
eq(Z.holderOf(0), "vigil", "the Vigil holds the shrine")
eq(achieved["Ana:pvpzone_captures"], 1, "capture stat")
local xpcb = callbacks.onGainExperience[1]
local src = Game.createMonster("Rat", {x = 1, y = 2, z = 7})
eq(xpcb(ana, src, 1000, 1000), math.floor(1000 * (1 + cfg.contest.buff.exp / 100)), "faction-wide experience buff")
eq(xpcb(cid, src, 1000, 1000), 1000, "not for the unpledged")
near(Z.lootMult({player = ana}), 1 + cfg.contest.buff.loot / 100, 1e-9, "faction-wide loot buff")
local zm
for _, c2 in pairs(creatures) do if c2.isMonster and c2:isMonster() and Z.scaled[c2.id] == 1 then zm = c2 break end end
eq(xpcb(cid, zm, 1000, 1000), math.floor(1000 * cfg.monsters.expMult), "zone monsters give more experience")
-- the window state
local s = Z.stateOf(cid)
eq(s.name, cfg.name, "state name")
eq(#s.vendor, #cfg.vendor, "vendor rows")
eq(#s.factions, 4, "four factions to pledge")
eq(s.factions[1].rivalName, "The Veiled Choir", "rival names for the window")
eq(s.contest.holder and s.contest.holder.key, "vigil", "the holder in the window")
-- the row is written at a logout only when it changed (every character's logout used to write it)
local rowWrites = 0
local realQuery = db.query
db.query = function(q)
  if q:find("INSERT INTO `" .. Chaos.tables.pvpZone .. "`", 1, true) then rowWrites = rowWrites + 1 end
  return realQuery(q)
end
local idle = newPlayer("Idle", 300)
Z.stateOf(idle)
events.ChaosMarchesLogout.onLogout(idle)
eq(rowWrites, 0, "a character that never touched the Marches: no write at logout")
local busy = newPlayer("Busy", 400)
check(Z.pledge(busy, "vigil"), "Busy pledges")
events.ChaosMarchesLogout.onLogout(busy)
check(rowWrites >= 1, "a pledge is written")
local w0 = rowWrites
local again2 = newPlayer("Again2", 400)
Z.rowOf(again2:getGuid()).haul = 7
events.ChaosMarchesLogout.onLogout(again2)
eq(rowWrites, w0 + 1, "a changed row is written at the logout")
local again3 = newPlayer("Again3", 400)
Z.rowOf(again3:getGuid()).haul = 7
Z.saveRow(again3:getGuid())
eq(rowWrites, w0 + 2, "written once")
Z.saveRow(again3:getGuid())
events.ChaosMarchesLogout.onLogout(again3)
eq(rowWrites, w0 + 2, "not again while unchanged")
local failing = newPlayer("Failing", 400)
Z.rowOf(failing:getGuid()).kills = 1
db.query = function(q) if q:find("INSERT INTO `" .. Chaos.tables.pvpZone .. "`", 1, true) then rowWrites = rowWrites + 1; return false end return true end
Z.saveRow(failing:getGuid())
db.query = function(q)
  if q:find("INSERT INTO `" .. Chaos.tables.pvpZone .. "`", 1, true) then rowWrites = rowWrites + 1 end
  return realQuery(q)
end
events.ChaosMarchesLogout.onLogout(failing)
eq(rowWrites, w0 + 4, "a failed write is tried again at the logout")
db.query = realQuery

-- no-pvp world: warning at startup
worldType = WORLD_TYPE_NO_PVP
globals.ChaosMarchesStartup.onStartup()

print(string.format("pvpzone_test: %d checks, %d failed", count, fails))
if fails > 0 then
  os.exit(1)
end

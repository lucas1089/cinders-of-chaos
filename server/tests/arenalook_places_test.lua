-- Run from the server/ folder: luajit tests/arenalook_places_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- O276, second part: the Ember Descent hall and the Vocation Trial chamber wear the shared arena look (arenalook_core.lua),
-- and the engine glue of the look (dressTiles, dress, freeSpot) runs against a small mocked engine. The battleground and the
-- raid are checked inside their flow tests (battleground_flow_test.lua, raid_test.lua), which run the real scripts.
-- The Descent hall is built in descent.lua (an engine file); its layout is repeated here from X.layout (a square of
-- 2 x (half - 1) + 1 tiles around the slot centre, start two tiles above the south edge, exit one below the north edge,
-- a basin in each corner) and the options of its paint() are repeated from descent_config.lua `look`.
dofile("data/scripts/chaos/rift_core.lua")
dofile("data/scripts/chaos/arenalook_core.lua")
dofile("data/scripts/chaos/trials_core.lua")
local AL, R, T = ChaosArenaLook, ChaosRiftCore, ChaosTrialsCore
local fails, count = 0, 0
local function check(c, n) count = count + 1; if not c then fails = fails + 1; print("FAIL: " .. n) end end

-- ---------------------------------------------------------------- a small mocked engine
local tiles = {}
local function tkey(p) return p.x .. "," .. p.y .. "," .. p.z end
function Position(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  return {x = x, y = y, z = z}
end
local Tl = {}
Tl.__index = Tl
local function newItem(id, tile)
  local it = {id = id, tile = tile}
  function it:getId() return self.id end
  function it:remove()
    local t = self.tile
    if t.ground == self then t.ground = nil return true end
    for i, x in ipairs(t.items) do if x == self then table.remove(t.items, i) return true end end
  end
  return it
end
function Tile(p) return tiles[tkey(p)] end
function Tl:getGround() return self.ground end
function Tl:getItems() local o = {} for i, it in ipairs(self.items) do o[i] = it end return o end
Game = {}
function Game.createTile(p) local t = setmetatable({items = {}}, Tl); tiles[tkey(p)] = t; return t end
-- the first item of a tile without a ground is its ground (the painter always lays the ground first)
function Game.createItem(id, _, pos)
  local t = tiles[tkey(pos)]
  if not t then return nil end
  local it = newItem(id, t)
  if not t.ground then t.ground = it else t.items[#t.items + 1] = it end
  return it
end

local WALL = 5648
local function reset() tiles = {} end
-- a walled hall: floor x1..x2, y1..y2, ground `base` (the plain one of the build), a wall ring
local function build(rect, z, base)
  for x = rect.x1 - 1, rect.x2 + 1 do
    for y = rect.y1 - 1, rect.y2 + 1 do
      local t = Game.createTile({x = x, y = y, z = z})
      Game.createItem(base, 1, {x = x, y = y, z = z})
      if x < rect.x1 or x > rect.x2 or y < rect.y1 or y > rect.y2 then Game.createItem(WALL, 1, {x = x, y = y, z = z}) end
    end
  end
end

local function localKey(room, p) return AL.key(p.x - room.ox, p.y - room.oy) end
local function solidAbs(room)
  local out = {}
  for k in pairs(room.look.blocked) do
    local x, y = k:match("(-?%d+),(-?%d+)")
    out[AL.key(tonumber(x) + room.ox, tonumber(y) + room.oy)] = true
  end
  return out
end

-- the rect-room checks shared by the hall and the chamber: open spots, a lane, nothing on the wall ring, the look's own
-- pieces only
local function checkRoom(label, roomKey, rect, z, keeps, from, to)
  local room = AL.rooms[roomKey]
  check(room ~= nil, label .. ": the room is recorded")
  if not room then return end
  local solid = solidAbs(room)
  local floor = {}
  for x = rect.x1, rect.x2 do for y = rect.y1, rect.y2 do floor[AL.key(x, y)] = {x = x, y = y} end end
  for k in pairs(solid) do check(floor[k], label .. ": solid pieces stand on the floor") end
  for _, p in ipairs(keeps) do check(not solid[AL.key(p.x, p.y)], label .. ": a key spot is open") end
  local reach = AL.reachable(floor, solid, from)
  for _, p in ipairs(keeps) do check(reach[AL.key(p.x, p.y)], label .. ": a key spot is reachable") end
  local lane = true
  local x, y = from.x, from.y
  while x ~= to.x do x = x + (to.x > x and 1 or -1); if solid[AL.key(x, y)] then lane = false end end
  while y ~= to.y do y = y + (to.y > y and 1 or -1); if solid[AL.key(x, y)] then lane = false end end
  check(lane, label .. ": the lane is free")
  check(room.look.covers > 0 and room.look.lights > 0, label .. ": cover and lights")
  -- no piece touches another (a diagonal either)
  for k in pairs(solid) do
    local sx, sy = k:match("(-?%d+),(-?%d+)")
    sx, sy = tonumber(sx), tonumber(sy)
    for dx = -1, 1 do for dy = -1, 1 do
      if (dx ~= 0 or dy ~= 0) and solid[AL.key(sx + dx, sy + dy)] then check(false, label .. ": two pieces touch at " .. k) end
    end end
  end
  for x2 = rect.x1 - 1, rect.x2 + 1 do
    for y2 = rect.y1 - 1, rect.y2 + 1 do
      if not floor[AL.key(x2, y2)] then
        local tl = Tile({x = x2, y = y2, z = z})
        check(#tl:getItems() == 1, label .. ": a wall tile carries only its wall")
      end
    end
  end
  return room, solid
end

-- ---------------------------------------------------------------- the Ember Descent hall
local dcfg = dofile("data/scripts/chaos/descent_config.lua")
local rcfg = dofile("data/scripts/chaos/rift_config.lua")
check(#dcfg.look.themes == #rcfg.themes, "descent: a look theme for every rift theme")
for _, n in ipairs(dcfg.look.themes) do
  check(n == "dark" or AL.THEMES[n] ~= nil, "descent: " .. n .. " is a theme")
end
local function descentHall(slot)
  local c = R.slotCenter(dcfg, slot)
  local h = dcfg.room.half - 1
  local L = {center = c, z = c.z, rect = {x1 = c.x - h, y1 = c.y - h, x2 = c.x + h, y2 = c.y + h}}
  L.start = {x = c.x, y = L.rect.y2 - 2, z = c.z}
  L.exit = {x = c.x, y = L.rect.y1 + 1, z = c.z}
  L.basins = {{x = L.rect.x1, y = L.rect.y1, z = c.z}, {x = L.rect.x2, y = L.rect.y1, z = c.z},
    {x = L.rect.x1, y = L.rect.y2, z = c.z}, {x = L.rect.x2, y = L.rect.y2, z = c.z}}
  return L
end
local function descentPaint(L, themeIndex, depth, wall)
  local lk = dcfg.look
  local keep = {{x = L.start.x, y = L.start.y, r = 3}, {x = L.exit.x, y = L.exit.y, r = 2}, {x = L.center.x, y = L.center.y, r = 2}}
  for _, b in ipairs(L.basins) do keep[#keep + 1] = {x = b.x, y = b.y, r = 1} end
  return AL.dress("descent" .. L.center.x .. "," .. L.center.y, L.rect, L.z, lk.themes[themeIndex], {keep = keep,
    roads = {{from = L.start, to = L.exit}}, seed = lk.seed + depth % lk.variants, mirror = false, cover = lk.cover,
    lights = lk.lights, wallSize = AL.wallSizeOf(wall), groundIds = {[407] = true}, fallbackGround = 407})
end
do
  for _, slot in ipairs({0, 5}) do
    reset(); AL.painted = {}; AL.rooms = {}
    local L = descentHall(slot)
    build(L.rect, L.z, 407)
    local keeps = {L.start, L.exit, L.center, L.basins[1], L.basins[2], L.basins[3], L.basins[4]}
    local first
    for depth = 1, 6 do
      for ti = 1, #rcfg.themes do
        local _, painted = descentPaint(L, ti, depth, WALL)
        local again, repainted = descentPaint(L, ti, depth, WALL)
        check(repainted == false, "descent: the same room is not painted twice")
        local label = "descent slot " .. slot .. " room " .. depth .. " theme " .. ti
        checkRoom(label, "descent" .. L.center.x .. "," .. L.center.y, L.rect, L.z, keeps, L.start, L.exit)
        if depth == 1 and ti == 1 then first = painted end
      end
    end
    check(first == true, "descent: the first paint paints")
  end
  -- a new theme removes the old pieces: ember-only cover ids are gone after the crypt
  reset(); AL.painted = {}; AL.rooms = {}
  local L = descentHall(0)
  build(L.rect, L.z, 407)
  descentPaint(L, 2, 1, WALL) -- ember
  descentPaint(L, 3, 1, WALL) -- crypt
  local emberOnly = {22110, 22111, 22112, 22113, 24943, 24944, 17625, 17626, 17627, 17628, 5815}
  local gone = true
  for _, tl in pairs(tiles) do
    for _, id in ipairs(emberOnly) do
      if tl.ground and tl.ground.id == id then gone = false end
      for _, it in ipairs(tl.items) do if it.id == id then gone = false end end
    end
  end
  check(gone, "descent: a new theme removes the pieces of the old one")
  -- the seed varies the room: two depths of one theme differ
  local function snapshot()
    local o = {}
    for k, tl in pairs(tiles) do
      local ids = {tl.ground and tl.ground.id or 0}
      for _, it in ipairs(tl.items) do ids[#ids + 1] = it.id end
      o[#o + 1] = k .. ":" .. table.concat(ids, ",")
    end
    table.sort(o)
    return table.concat(o, "|")
  end
  descentPaint(L, 3, 1, WALL); local a = snapshot()
  descentPaint(L, 3, 2, WALL); local b = snapshot()
  descentPaint(L, 3, 1, WALL); local c = snapshot()
  check(a ~= b, "descent: two rooms of a theme differ")
  check(a == c, "descent: the same room paints the same")
  -- freeSpot: a monster made on a cover piece steps to an open tile
  local room = AL.rooms["descent" .. L.center.x .. "," .. L.center.y]
  local solid = solidAbs(room)
  local n = 0
  for k in pairs(solid) do
    local x, y = k:match("(-?%d+),(-?%d+)")
    x, y = tonumber(x), tonumber(y)
    local at = AL.freeSpot("descent" .. L.center.x .. "," .. L.center.y, {x = x, y = y, z = L.z})
    check(not solid[AL.key(at.x, at.y)] and at.z == L.z and math.max(math.abs(at.x - x), math.abs(at.y - y)) <= 3,
      "descent: freeSpot leaves a cover piece")
    n = n + 1
  end
  check(n > 0, "descent: there is cover to test")
  local open = {x = L.center.x, y = L.center.y, z = L.z}
  check(AL.freeSpot("descent" .. L.center.x .. "," .. L.center.y, open) == open, "descent: an open tile stays")
  check(AL.freeSpot("nowhere", open) == open, "descent: an unknown room leaves the position")
  -- the obsidian wall is 2x2: no light or decoration on the row and column in front of it
  reset(); AL.painted = {}; AL.rooms = {}
  build(L.rect, L.z, 407)
  ChaosDarkTiles = {ids = {}, id = function(name) return name == "obsidian_wall" and 31999 or nil end}
  check(AL.wallSizeOf(31999) == 2, "descent: wallSizeOf knows the obsidian wall")
  descentPaint(L, 2, 1, 31999)
  ChaosDarkTiles = nil
  local r2 = AL.rooms["descent" .. L.center.x .. "," .. L.center.y]
  for k, t in pairs(r2.look.tiles) do
    local x, y = k:match("(-?%d+),(-?%d+)")
    x, y = tonumber(x), tonumber(y)
    if x == L.rect.x2 - r2.ox or y == L.rect.y2 - r2.oy then
      check(t.light == nil and t.decor == nil, "descent: nothing hidden behind a 2x2 wall " .. k .. " " .. tostring(t.light) .. " " .. tostring(t.decor))
    end
  end
end

-- ---------------------------------------------------------------- the Vocation Trials chamber
local tcfg = T.cfg().room
local lk = tcfg.look
check(#lk.themes >= 3, "trials: a theme per tier")
for _, n in ipairs(lk.themes) do check(n == "dark" or AL.THEMES[n] ~= nil, "trials: " .. n .. " is a theme") end
local function trialPaint(L, tier, voc)
  local keep = {{x = L.playerStart.x, y = L.playerStart.y, r = 3}, {x = L.bossStart.x, y = L.bossStart.y, r = 2},
    {x = L.center.x, y = L.center.y, r = 2}}
  for _, s in ipairs(L.seals) do keep[#keep + 1] = {x = s.x, y = s.y, r = 1} end
  for _, b in ipairs(L.basins) do keep[#keep + 1] = {x = b.x, y = b.y, r = 1} end
  return AL.dress("trial" .. L.slot, {x1 = L.x1, y1 = L.y1, x2 = L.x2, y2 = L.y2}, L.z, lk.themes[(tier - 1) % #lk.themes + 1],
    {keep = keep, roads = {{from = L.playerStart, to = L.bossStart}}, seed = lk.seed + voc % lk.variants, mirror = false,
    cover = lk.cover, lights = lk.lights, wallSize = AL.wallSizeOf(tcfg.wallId), groundIds = {[tcfg.groundId] = true},
    fallbackGround = tcfg.groundId})
end
for _, slot in ipairs({1, 8}) do
  reset(); AL.painted = {}; AL.rooms = {}
  local L = T.layout(slot)
  build({x1 = L.x1, y1 = L.y1, x2 = L.x2, y2 = L.y2}, L.z, tcfg.groundId)
  local keeps = {L.playerStart, L.bossStart, L.center, L.seals[1], L.seals[2], L.seals[3], L.seals[4], L.basins[1], L.basins[2],
    L.basins[3], L.basins[4]}
  for tier = 1, 3 do
    for voc = 1, 8 do
      trialPaint(L, tier, voc)
      local label = "trials slot " .. slot .. " tier " .. tier .. " vocation " .. voc
      local room = checkRoom(label, "trial" .. L.slot, {x1 = L.x1, y1 = L.y1, x2 = L.x2, y2 = L.y2}, L.z, keeps, L.playerStart,
        L.bossStart)
      check(room and room.look.theme == (AL.theme(lk.themes[tier], AL.darkIds).name), label .. ": the theme of the tier")
    end
  end
  -- the player's start sees the guardian: the lane between them is open (checked above); the seals have free neighbours
  local room = AL.rooms["trial" .. L.slot]
  local solid = solidAbs(room)
  for _, s in ipairs(L.seals) do
    local free = 0
    for dx = -1, 1 do for dy = -1, 1 do if not solid[AL.key(s.x + dx, s.y + dy)] then free = free + 1 end end end
    check(free == 9, "trials: the seal at " .. s.x .. "," .. s.y .. " has open ground around it")
  end
end

-- ---------------------------------------------------------------- dressTiles on an irregular shape
do
  reset(); AL.painted = {}; AL.rooms = {}
  -- an L-shaped floor with a plain 3x3 block that keeps its own ground
  local list, set = {}, {}
  for x = 1, 20 do for y = 1, 6 do list[#list + 1] = {x = 100 + x, y = 200 + y}; set[(100 + x) .. "," .. (200 + y)] = true end end
  for x = 1, 6 do for y = 7, 16 do list[#list + 1] = {x = 100 + x, y = 200 + y}; set[(100 + x) .. "," .. (200 + y)] = true end end
  for _, t in ipairs(list) do
    Game.createTile({x = t.x, y = t.y, z = 7})
    Game.createItem(407, 1, {x = t.x, y = t.y, z = 7})
  end
  local plain = {}
  for x = 103, 105 do for y = 202, 204 do plain[#plain + 1] = {x = x, y = y}; tiles[tkey({x = x, y = y, z = 7})].ground.id = 406 end end
  local look, painted = AL.dressTiles("shape", list, 7, "stone", {keep = {{x = 101, y = 201, r = 1}, {x = 104, y = 203, r = 1}}, plain = plain, mirror = false,
    seed = 4, cover = 6, lights = 3, roads = {{from = {x = 101, y = 201}, to = {x = 103, y = 215}}}})
  check(painted == true and look.covers > 0, "shape: painted with cover")
  local _, again = AL.dressTiles("shape", list, 7, "stone", {keep = {{x = 101, y = 201, r = 1}, {x = 104, y = 203, r = 1}}, plain = plain, mirror = false,
    seed = 4, cover = 6, lights = 3, roads = {{from = {x = 101, y = 201}, to = {x = 103, y = 215}}}})
  check(again == false, "shape: not painted twice")
  for _, p in ipairs(plain) do
    local tl = tiles[tkey({x = p.x, y = p.y, z = 7})]
    check(tl.ground.id == 406, "shape: a plain tile keeps its ground")
    check(#tl.items == 0, "shape: a plain tile carries no border piece or decoration")
  end
  local room = AL.rooms["shape"]
  local solid = solidAbs(room)
  for k in pairs(solid) do check(set[k], "shape: solid pieces stand on the floor") end
  local floorSet = {}
  for _, t in ipairs(list) do floorSet[AL.key(t.x, t.y)] = t end
  local reach = AL.reachable(floorSet, solid, {x = 101, y = 201})
  local free = 0
  for k in pairs(floorSet) do if not solid[k] then free = free + 1 end end
  local n = 0
  for _ in pairs(reach) do n = n + 1 end
  check(n == free, "shape: the floor stays one field")
end

-- ---------------------------------------------------------------- the files that use the look
local function readFile(path) local f = io.open(path, "r"); if not f then return "" end local s = f:read("*a"); f:close(); return s end
for file, needles in pairs({
  ["data/scripts/chaos/battleground.lua"] = {"ChaosArenaLook.dressTiles", "ChaosArenaLook.isOwned"},
  ["data/scripts/chaos/descent.lua"] = {"ChaosArenaLook.dress(", "ChaosArenaLook.isOwned", "ChaosArenaLook.freeSpot"},
  ["data/scripts/chaos/trials.lua"] = {"ChaosArenaLook.dress(", "ChaosArenaLook.isOwned", "ChaosArenaLook.freeSpot"},
  ["data/scripts/chaos/raid.lua"] = {"ChaosArenaLook.dressTiles", "ChaosArenaLook.isOwned", "ChaosArenaLook.freeSpot"}}) do
  local src = readFile(file)
  for _, nd in ipairs(needles) do check(src:find(nd, 1, true) ~= nil, file .. " uses " .. nd) end
  check(not src:find("ChaosDarkPaint.apply", 1, true), file .. " has no dark paint of its own any more")
end

if fails > 0 then print(fails .. " of " .. count .. " checks failed") os.exit(1) end
print("arenalook places: " .. count .. " checks passed")

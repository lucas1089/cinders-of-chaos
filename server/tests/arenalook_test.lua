-- Run from the server/ folder: luajit tests/arenalook_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- arenalook_core.lua (O276): the shared look of the runtime-built arenas. Deterministic, stock ids only, the floor stays
-- one connected field, keep points and roads stay free, solid pieces never touch, mirrored where asked.
dofile("data/scripts/chaos/arenalook_core.lua")
local A = ChaosArenaLook

local fails, count = 0, 0
local function check(cond, name)
  count = count + 1
  if not cond then fails = fails + 1; print("FAIL: " .. name) end
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local s = f:read("*a"); f:close(); return s
end

-- stock ids: every number of the files the generated areas and the Marches take theirs from
local stock = {}
for _, f in ipairs({"data/scripts/chaos/areagen_config.lua", "data/scripts/chaos/pvpzone_config.lua",
  "data/scripts/chaos/pocketboss_config.lua", "data/scripts/chaos/worldboss.lua", "data/scripts/chaos/arena_config.lua",
  "data/scripts/chaos/rift_config.lua"}) do
  for n in readFile(f):gmatch("%d+") do stock[tonumber(n)] = true end
end
local function allIds(t)
  local out = {}
  local function add(id) out[#out + 1] = id end
  for _, e in ipairs(t.base) do add(e[1]) end
  for _, p in ipairs(t.patches) do
    for _, e in ipairs(p.grounds) do add(e[1]) end
    for _, id in pairs(p.edge or {}) do add(id) end
  end
  for _, id in ipairs(t.rim) do add(id) end
  for _, e in ipairs(t.road) do add(e[1]) end
  for _, id in ipairs(t.cover.ids) do add(id) end
  for _, id in ipairs(t.light) do add(id) end
  for _, id in ipairs(t.decor.ids) do add(id) end
  for _, id in ipairs(t.wallDecor.ids) do add(id) end
  if t.wall then add(t.wall) end
  for _, rows in pairs(A.wallSetOf(t) or {}) do
    if type(rows) == "table" then for _, e in ipairs(rows) do add(e[1]) end end
  end
  return out
end
for name, t in pairs(A.THEMES) do
  for _, id in ipairs(allIds(t)) do
    check(stock[id], "theme " .. name .. ": id " .. id .. " is a stock id the generated areas already use")
  end
end

local function sig(look)
  local parts = {}
  for _, k in ipairs(look.order) do
    local t = look.tiles[k]
    parts[#parts + 1] = k .. ":" .. t.gid .. ":" .. table.concat(t.edges, "+") .. ":" .. tostring(t.decor) .. ":" ..
      tostring(t.cover) .. ":" .. tostring(t.light)
  end
  return table.concat(parts, "|")
end

local function floorSet(tiles)
  local f = {}
  for _, t in ipairs(tiles) do f[A.key(t.x, t.y)] = {x = t.x, y = t.y} end
  return f
end

local function verify(label, spec)
  local look = A.generate(spec)
  local again = A.generate(spec)
  check(sig(look) == sig(again), label .. ": deterministic")
  local floor = floorSet(spec.tiles)
  -- connected
  local n = 0
  for _ in pairs(floor) do n = n + 1 end
  local from
  for _, kp in ipairs(spec.keep or {}) do from = from or kp end
  from = from or spec.tiles[1]
  local seen = A.reachable(floor, look.blocked, from)
  local free, c = 0, 0
  for k in pairs(floor) do if not look.blocked[k] then free = free + 1 end end
  for _ in pairs(seen) do c = c + 1 end
  check(c == free, label .. ": every free tile reachable (" .. c .. "/" .. free .. ")")
  -- keep points free and reachable, nothing solid near them
  for _, kp in ipairs(spec.keep or {}) do
    check(seen[A.key(kp.x, kp.y)], label .. ": keep point reachable")
    for k in pairs(look.blocked) do
      local x, y = k:match("(-?%d+),(-?%d+)")
      x, y = tonumber(x), tonumber(y)
      check(math.max(math.abs(x - kp.x), math.abs(y - kp.y)) > (kp.r or 1), label .. ": nothing solid in a keep zone")
    end
  end
  -- roads free
  for k, t in pairs(look.tiles) do
    if t.road then check(not look.blocked[k] and seen[k], label .. ": road tile free") end
  end
  -- a sunken patch ground (lava cracks) never touches a road, so its border is whole
  local sunken = {}
  for _, pt in ipairs(spec.theme.patches or {}) do
    if pt.lower then for _, g in ipairs(pt.grounds) do sunken[g[1]] = true end end
  end
  for _, t in pairs(look.tiles) do
    if sunken[t.gid] then
      for dx = -1, 1 do for dy = -1, 1 do
        local n = look.tiles[A.key(t.x + dx, t.y + dy)]
        check(not (n and n.road), label .. ": sunken patch off the road")
      end end
    end
  end
  -- solid pieces never touch, not even on a diagonal
  for k in pairs(look.blocked) do
    local x, y = k:match("(-?%d+),(-?%d+)")
    x, y = tonumber(x), tonumber(y)
    for dx = -1, 1 do for dy = -1, 1 do
      if (dx ~= 0 or dy ~= 0) then check(not look.blocked[A.key(x + dx, y + dy)], label .. ": solid pieces do not touch") end
    end end
  end
  -- mirrored
  if spec.mirror then
    for k in pairs(look.blocked) do
      local x, y = k:match("(-?%d+),(-?%d+)")
      local mx, my = look.maxx - (tonumber(x) - look.minx), look.maxy - (tonumber(y) - look.miny)
      check(look.blocked[A.key(mx, my)], label .. ": every solid piece has its mirror image")
    end
  end
  -- ground everywhere
  for k in pairs(floor) do check(look.tiles[k] and look.tiles[k].gid, label .. ": ground on every tile") end
  return look
end

local darkAll = function(name) return 30000 + #name end -- every dark piece "installed"
local darkSample = A.theme("dark", darkAll)
check(darkSample.dark == true, "the dark theme is used when its pieces are installed")
check(A.theme("dark", function() return nil end).name == "ember", "the dark theme falls back to ember without the set")
check(A.theme("dark").name == "ember", "the dark theme falls back to ember without a lookup")
check(A.theme("nonsense").name == "ember", "an unknown theme is ember")

local names = {"ember", "stone", "crypt"}
for _, shape in ipairs({
  {"square 25", A.rectTiles(1, 1, 25, 25), {x = 13, y = 13}},
  {"square 23", A.rectTiles(1, 1, 23, 23), {x = 12, y = 12}},
  {"hall 11x9", A.rectTiles(1, 1, 11, 9), {x = 6, y = 5}},
  {"wide 40x20", A.rectTiles(1, 1, 40, 20), {x = 20, y = 10}}}) do
  for _, tn in ipairs({"ember", "stone", "crypt", "dark"}) do
    for seed = 1, 4 do
      local th = A.theme(tn, darkAll)
      local mid = shape[3]
      local look = verify(shape[1] .. " " .. tn .. " " .. seed, {tiles = shape[2], theme = th, seed = seed, mirror = true,
        keep = {{x = mid.x, y = mid.y, r = 3}}, roads = {{from = {x = mid.x, y = 1 + (#shape[2] > 100 and 0 or 0)}, to = {x = mid.x, y = mid.y - 4}}}})
      if shape[1] == "square 25" then
        check(look.covers > 0 and look.lights > 0, "a 25 room has cover and lights (" .. tn .. " " .. seed .. ")")
      end
    end
  end
end

-- unmirrored, an L shaped room and two keep points
do
  local tiles = {}
  for _, t in ipairs(A.rectTiles(1, 1, 20, 8)) do tiles[#tiles + 1] = t end
  for _, t in ipairs(A.rectTiles(1, 9, 8, 20)) do tiles[#tiles + 1] = t end
  verify("L room", {tiles = tiles, theme = A.theme("stone"), seed = 9, keep = {{x = 2, y = 19, r = 1}, {x = 19, y = 2, r = 1}},
    roads = {{from = {x = 2, y = 19}, to = {x = 2, y = 2}}, {from = {x = 2, y = 2}, to = {x = 19, y = 2}}}})
end

-- ember with a road through the middle: the lava cracks keep off it (owner report 2026-11-06)
for seed = 1, 12 do
  verify("ember road " .. seed, {tiles = A.rectTiles(1, 1, 21, 21), theme = A.theme("ember"), seed = seed,
    keep = {{x = 11, y = 20, r = 1}}, roads = {{from = {x = 11, y = 20}, to = {x = 11, y = 2}}}})
end

-- theme choice: keywords, else a hash; always a theme name
check(A.themeFor("Fire Elemental") == "ember", "fire is ember")
check(A.themeFor("Lich King") == "crypt", "lich is crypt")
check(A.themeFor("Abyss Lord") == "dark", "abyss is dark")
check(A.THEMES[A.themeFor("Zzzz")], "an unknown boss still gets a stock theme")

-- apply: ground only where there is none, then the items
do
  local look = A.generate({tiles = A.rectTiles(1, 1, 9, 9), theme = A.theme("ember"), seed = 2, mirror = true,
    keep = {{x = 5, y = 5, r = 1}}})
  local made, hasG = {}, {}
  local io = {hasGround = function(x, y) return hasG[A.key(x, y)] end,
    createItem = function(id, x, y) made[#made + 1] = id; hasG[A.key(x, y)] = true; return true end}
  local n = A.apply(look, io)
  check(n == #made and n >= 81, "apply creates a ground for every tile")
  local before = n
  made = {}
  A.apply(look, io)
  check(#made < before, "a second apply keeps the ground that is there")
end

-- built walls: the stock themes use a wall set (not the cave rock piece 5648), the same ids as the wall brush of the
-- generated areas, and a rectangle gets rows, columns, a pole in the north-west and the corner piece in the south-east
do
  local AG = dofile("data/scripts/chaos/areagen_config.lua")
  -- the guild hall tiers' sets have no areagen brush: their pieces were picked from client renders (white stone wall
  -- 1111-1116, stone wall 1049-1054, brick wall 1025-1030)
  local ownSets = {marble = {1111, 1116}, greystone = {1049, 1054}, brick = {1025, 1030}}
  check(AG.walls.darkstone ~= nil and A.WALL_SETS.darkstone ~= nil, "darkstone is a wall brush of areagen_config.lua")
  for name, set in pairs(A.WALL_SETS) do
    local brush = AG.walls[name]
    check(brush ~= nil or ownSets[name] ~= nil, "wall set " .. name .. ": an areagen brush or a known stock family")
    check(set.size == 2, "wall set " .. name .. ": 2x2 sprites")
    for _, piece in ipairs({"horizontal", "vertical", "corner", "pole"}) do
      local a, b = {}, {}
      for _, e in ipairs(set[piece] or {}) do
        a[#a + 1] = e[1] .. "x" .. (e[2] or 1)
        if ownSets[name] then
          check(e[1] >= ownSets[name][1] and e[1] <= ownSets[name][2], "wall set " .. name .. ": " .. e[1] .. " in its family")
        end
      end
      for _, e in ipairs(brush and brush[piece] or {}) do b[#b + 1] = e[1] .. "x" .. (e[2] or 1) end
      check(#a > 0, "wall set " .. name .. ": has " .. piece)
      if brush then
        check(table.concat(a, ",") == table.concat(b, ","), "wall set " .. name .. ": " .. piece .. " as in areagen_config.lua")
      end
    end
  end
  for name, t in pairs(A.THEMES) do
    check(t.wall ~= 5648, "theme " .. name .. ": not the cave rock piece 5648 as a wall")
    check(A.wallSetOf(t) ~= nil or t.wall ~= nil, "theme " .. name .. ": has a wall")
    local look = A.generate({tiles = A.rectTiles(1, 1, 5, 5), theme = A.theme(name), seed = 1})
    check(look.walls == A.wallSetOf(t), "theme " .. name .. ": the look carries the wall set")
  end
  local set = A.WALL_SETS.darkstone
  local function isWall(x, y) return x >= 0 and y >= 0 and x <= 6 and y <= 6 and (x == 0 or y == 0 or x == 6 or y == 6) end
  local function inSet(rows, id) for _, e in ipairs(rows) do if e[1] == id then return true end end return false end
  check(inSet(set.pole, A.wallPieceId(set, isWall, 0, 0)), "frame: pole in the north-west corner")
  check(inSet(set.corner, A.wallPieceId(set, isWall, 6, 6)), "frame: corner piece in the south-east corner")
  check(inSet(set.horizontal, A.wallPieceId(set, isWall, 6, 0)), "frame: north-east corner is a row end")
  check(inSet(set.vertical, A.wallPieceId(set, isWall, 0, 6)), "frame: south-west corner is a column end")
  for i = 1, 5 do
    check(inSet(set.horizontal, A.wallPieceId(set, isWall, i, 0)) and inSet(set.horizontal, A.wallPieceId(set, isWall, i, 6)), "frame: rows " .. i)
    check(inSet(set.vertical, A.wallPieceId(set, isWall, 0, i)) and inSet(set.vertical, A.wallPieceId(set, isWall, 6, i)), "frame: columns " .. i)
  end
  check(A.wallPieceId(set, isWall, 3, 0) == A.wallPieceId(set, isWall, 3, 0), "frame: the same piece every time")
  -- wall values of the builders' configs: a set name or one id
  local frame = {}
  for x = 0, 6 do for y = 0, 6 do if isWall(x, y) then frame[#frame + 1] = {x = x, y = y} end end end
  local at = A.wallPlacer("darkstone", frame)
  check(at(0, 0) == A.wallPieceId(set, isWall, 0, 0) and at(6, 6) == A.wallPieceId(set, isWall, 6, 6), "wallPlacer: the frame's pieces")
  check(A.wallPlacer(5648, frame)(3, 0) == 5648, "wallPlacer: a plain id stays that id (the dark set's walls)")
  check(A.wallPlacer("nope", frame)(3, 0) == nil, "wallPlacer: an unknown set places nothing")
  local ids = A.wallIds("darkstone", {[1] = true})
  check(ids[1] and ids[25200] and ids[25201] and ids[25202] and ids[25203] and ids[25204] and ids[25205], "wallIds: every piece, added")
  check(A.wallIds(1049)[1049] == true and A.wallIds("darkstone")["darkstone"] == nil, "wallIds: a plain id; never the name")
  check(A.wallSizeOf("darkstone") == 2 and A.wallSizeOf(25204) == 2 and A.wallSizeOf(5648) == 1, "wallSizeOf: sets and pieces are 2x2")
  -- a fixture next to the south / east wall of a 2x2 wall moves one tile in; elsewhere it stays
  local function same(p, x, y) return p.x == x and p.y == y end
  check(same(A.clearOfWall({x = 5, y = 5}, isWall, 2), 4, 4), "clearOfWall: south-east corner one tile in")
  check(same(A.clearOfWall({x = 3, y = 5}, isWall, 2), 3, 4), "clearOfWall: south wall one row up")
  check(same(A.clearOfWall({x = 5, y = 3}, isWall, 2), 4, 3), "clearOfWall: east wall one column left")
  check(same(A.clearOfWall({x = 1, y = 1}, isWall, 2), 1, 1), "clearOfWall: north-west corner stays")
  check(same(A.clearOfWall({x = 5, y = 5}, isWall, 1), 5, 5), "clearOfWall: a 1x1 wall moves nothing")
  -- no config of a runtime room uses the cave rock piece 5648 as its wall any more
  for _, f in ipairs({"uber_config", "guildboss_config", "pocketboss_config", "trials_config", "ascension_quest_config",
    "siege_config", "descent_config", "raid_config", "arena_config", "rift_config", "battleground_config", "pvpzone_config",
    "guild_config", "chaos_constants"}) do
    local src = readFile("data/scripts/chaos/" .. f .. ".lua")
    check(src ~= "" and not src:find("wallI?d? = 5648") and not src:find("wall = 5648"), f .. ": no wall 5648")
  end
end

if fails > 0 then
  print(fails .. " of " .. count .. " arenalook checks failed")
  os.exit(1)
end
print("arenalook: " .. count .. " checks passed")

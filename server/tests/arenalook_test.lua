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
  add(t.wall)
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

if fails > 0 then
  print(fails .. " of " .. count .. " arenalook checks failed")
  os.exit(1)
end
print("arenalook: " .. count .. " checks passed")

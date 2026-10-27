-- Run from the server/ folder: luajit tests/arenalook_arenas_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- O276: the look of the Ascended, guild boss and pocket boss arenas (uber_core.lua layout + arenalook_core.lua): for every
-- theme and slot the arrival, the starts, the boss spot and the way out are open and reachable, the boss sees the entry
-- (a free lane), nothing solid touches, and every slot looks the same (a pure function of the config).
dofile("data/scripts/chaos/uber_core.lua")
dofile("data/scripts/chaos/arenalook_core.lua")
local U, AL = ChaosUberCore, ChaosArenaLook
local fails, count = 0, 0
local function check(c, n) count = count + 1; if not c then fails = fails + 1; print("FAIL: " .. n) end end

local cfgs = {
  ascended = dofile("data/scripts/chaos/uber_config.lua"),
  guild = dofile("data/scripts/chaos/guildboss_config.lua"),
  pocket = dofile("data/scripts/chaos/pocketboss_config.lua")}
local keys = {"bloodmoon", "hollow", "storm", "cinder", "guildboss", "Fire Dragon", "Lich King", "Abyss Lord", "Ferumbras",
  "world_1", "raid_moloveth"}
local function sig(look)
  local out = {}
  for _, k in ipairs(look.order) do
    local t = look.tiles[k]
    out[#out + 1] = k .. t.gid .. table.concat(t.edges, "+") .. tostring(t.decor) .. tostring(t.cover) .. tostring(t.light)
  end
  return table.concat(out, "|")
end

for name, cfg in pairs(cfgs) do
  for _, key in ipairs(keys) do
    local base
    for _, slot in ipairs({1, 2, 5}) do
      local L = U.layout(cfg, slot)
      local gate = {x = L.entry.x + 2, y = L.entry.y - 1} -- where the pocket's own gate lands: next to the arrival
      local themeName, o = AL.bossArenaSpec(L, cfg, key, gate)
      local th = AL.theme(themeName, function(n) return 30000 + #n end)
      local spec = {tiles = {}, theme = th, seed = o.seed, mirror = true, cover = o.cover, lights = o.lights, keep = {}, roads = {}}
      local r = L.rect
      local function loc(p) return {x = p.x - r.x1 + 1, y = p.y - r.y1 + 1} end
      for _, t in ipairs(AL.rectTiles(1, 1, r.x2 - r.x1 + 1, r.y2 - r.y1 + 1)) do spec.tiles[#spec.tiles + 1] = t end
      for _, k in ipairs(o.keep) do local q = loc(k); q.r = k.r; spec.keep[#spec.keep + 1] = q end
      for _, rd in ipairs(o.roads) do spec.roads[#spec.roads + 1] = {from = loc(rd.from), to = loc(rd.to)} end
      local look = AL.generate(spec)
      local floor = {}
      for _, t in ipairs(spec.tiles) do floor[AL.key(t.x, t.y)] = t end
      local reach = AL.reachable(floor, look.blocked, loc(L.entry))
      local label = name .. " " .. key .. " slot " .. slot
      local free = 0
      for k in pairs(floor) do if not look.blocked[k] then free = free + 1 end end
      local n = 0
      for _ in pairs(reach) do n = n + 1 end
      check(n == free, label .. ": the arena stays one field")
      for _, p in ipairs(L.starts) do
        local q = loc(p); check(reach[AL.key(q.x, q.y)], label .. ": a start tile is open")
      end
      for _, p in ipairs({L.bossSpawn, L.entry, L.center, gate}) do
        local q = loc(p); check(reach[AL.key(q.x, q.y)], label .. ": a key spot is open")
      end
      for _, b in ipairs(L.basins) do
        local q = loc(b); check(not look.blocked[AL.key(q.x, q.y)], label .. ": a corner basin has its tile")
      end
      for y = L.bossSpawn.y, L.entry.y do
        local q = loc({x = L.bossSpawn.x, y = y}); check(not look.blocked[AL.key(q.x, q.y)], label .. ": the boss sees the entry")
      end
      check(look.covers > 0 and look.lights > 0, label .. ": cover and lights")
      -- kiting room: the open ring of 5 tiles around the middle is entirely free
      local c = loc(L.center)
      local ring = true
      for dx = -3, 3 do for dy = -3, 3 do if look.blocked[AL.key(c.x + dx, c.y + dy)] then ring = false end end end
      check(ring, label .. ": the middle is open")
      local s = sig(look)
      if base then check(s == base, label .. ": every slot looks the same") else base = s end
    end
  end
end

-- the ranked PvP arena (arena_core.lua layout): both teams' spawns and the centre line open, the cover the same for both
dofile("data/scripts/chaos/arena_core.lua")
do
  local acfg = dofile("data/scripts/chaos/arena_config.lua")
  for slot = 0, acfg.grid.slots - 1 do
    local L = ChaosArenaCore.layout(acfg, slot)
    local ar = L.arena
    local w, h = ar.x2 - ar.x1 - 1, ar.y2 - ar.y1 - 1
    local function loc(p) return {x = p.x - ar.x1, y = p.y - ar.y1} end
    local th = AL.theme(acfg.look.themes[slot % #acfg.look.themes + 1])
    local keep = {}
    for team = 1, 2 do for _, t in ipairs(L.spawns[team]) do local q = loc(t); q.r = 0; keep[#keep + 1] = q end end
    for _, t in ipairs(L.pillars) do local q = loc(t); q.r = 0; keep[#keep + 1] = q end
    for _, t in ipairs(L.basins) do if t.y <= ar.y2 then local q = loc(t); q.r = 0; keep[#keep + 1] = q end end
    local look = AL.generate({tiles = AL.rectTiles(1, 1, w, h), theme = th, seed = acfg.look.seed, mirror = true, keep = keep,
      cover = acfg.look.cover, lights = acfg.look.lights, roads = {{from = loc(L.spawns[1][1]), to = loc(L.spawns[2][1])}}})
    local floor = {}
    for _, t in ipairs(AL.rectTiles(1, 1, w, h)) do floor[AL.key(t.x, t.y)] = t end
    local reach = AL.reachable(floor, look.blocked, loc(L.spawns[1][1]))
    for team = 1, 2 do
      for _, p in ipairs(L.spawns[team]) do
        local q = loc(p); check(reach[AL.key(q.x, q.y)], "pvp slot " .. slot .. ": team " .. team .. " spawn reachable")
      end
    end
    for _, p in ipairs(L.pillars) do
      local q = loc(p); check(not look.blocked[AL.key(q.x, q.y)], "pvp slot " .. slot .. ": the pillar's tile is free of cover")
    end
    for k in pairs(look.blocked) do
      local x, y = k:match("(-?%d+),(-?%d+)")
      check(look.blocked[AL.key(w + 1 - tonumber(x), h + 1 - tonumber(y))], "pvp slot " .. slot .. ": cover is the same for both teams")
    end
    check(look.covers > 0, "pvp slot " .. slot .. ": cover " .. #keep .. " " .. w .. "x" .. h .. " " .. tostring(look.covers))
  end
end

if fails > 0 then print(fails .. " of " .. count .. " checks failed") os.exit(1) end
print("arenalook arenas: " .. count .. " checks passed")

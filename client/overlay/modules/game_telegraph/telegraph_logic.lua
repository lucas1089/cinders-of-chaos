-- Floor telegraphs (O549): the rules without client API (tested by telegraph_test.lua with luajit and lua5.3).
-- A boss attack marks its tiles on the floor: every tile of the area gets a flat translucent fill, and the outline of the whole
-- area (the outer edges of the union of the tiles, not the edges between two marked tiles) a bright line a couple of pixels wide,
-- under the creatures. The mark heats up as the hit nears: it fades in, turns from orange to red, throbs faster and faster, flares
-- in the last 0.4 s and bursts at the hit (a short bright flash that fades out in BURST_MS); it is gone after that, at the server's
-- clear, and at a safety expiry.
-- The server (telegraph.lua) sends on the monster bar's opcode 125 (forwarded by game_monsterbar):
--   floor      {id, z, x0, y0, t = [[dx, dy]], c = colour key, ms = ms to the hit}   the area, whole (again when a follow circle moves)
--   floorclear {id}                                                                  one mark gone (no id: all)
-- and this client says {action = 'floorhello', data = {v = 1}} on the same opcode once: from then on the server leaves the
-- per-tile sprite pulses of the telegraphs to the players who did not say it.

TelegraphLogic = {}
local L = TelegraphLogic

L.OPCODE = 125            -- server ChaosOpcodes.monsterbar (client -> server floorhello, server -> client floor / floorclear)
L.VERSION = 1

-- ---------------------------------------------------------------- limits (the server sends at most 300 tiles a mark)
L.MAX_TILES = 300         -- tiles of one mark: more is refused whole (a half drawn danger area would lie)
L.MAX_AREAS = 24          -- marks alive at once: the oldest goes
L.MAX_TOTAL = 900         -- tiles of all the marks together: the oldest marks go until it fits
L.MAX_ID = 64
L.MIN_MS = 50             -- time to the hit
L.MAX_MS = 12000
L.EXPIRY_SLACK_MS = 1500  -- a mark whose hit time is older than this plus its length is dropped whatever the clock says

-- ---------------------------------------------------------------- the look
L.FADE_IN_MS = 150        -- a new mark fades in
L.BRIGHT_MS = 400         -- the flare: the last 0.4 s before the hit
L.BURST_MS = 180          -- the burst: a flash at the hit that fades out (the server clears 300 ms after the hit, so it is seen)
L.FILL_ALPHA = 0.32       -- the fill of a fresh mark
L.FILL_HOT = 0.46         -- the fill when the heat reaches 1, before the flare
L.FILL_BRIGHT = 0.62      -- and at the hit
L.FILL_BURST = 0.80       -- the burst flash
L.THROB = 0.06            -- the throb's depth at full heat (none on a cold mark)
L.THROB_SCALE = 60        -- the throb's phase is sqrt(ms left / THROB_SCALE) turns: about 700 ms a beat 2 s out, 220 ms at 0.2 s
L.HEAT_POW = 1.6          -- heat = progress ^ HEAT_POW: orange for most of the wait, red at the end
L.HEAT_STEPS = 32         -- the colour is set in steps of 1 / 32 of the heat too
L.LINE_PX = 2             -- the line, in screen pixels (the engine draws a widget in map pixels, the line follows the zoom: lineWidth)
L.ALPHA_STEPS = 32        -- the fill's alpha is set in steps of 1 / 32 so a widget is touched only when the picture changes

-- colour key -> {fill, line, hot fill, hot line} as 'rrggbb': the mark goes from the first pair to the hot pair as it heats up.
-- A boss attack is orange and ends red.
L.COLORS = {
  orange = { 'ff7a1e', 'ff8c28', 'e8180c', 'ff2a14' },
  red = { 'ff3a24', 'ff5a3c', 'b80808', 'ff1e10' },
  green = { '3cd264', '66e68a', '20a040', '8cffa8' },
  violet = { 'a050ff', 'b878ff', '7a1ee0', 'd2a0ff' },
  blue = { '3c8cff', '64aaff', '1450e0', '9cc8ff' },
}
L.BURST_COLOR = { 'ffb45a', 'fff0c8' } -- the burst flash: fill, line (white hot)
L.DEFAULT_COLOR = 'orange'

function L.colorKey(key)
  if type(key) == 'string' and L.COLORS[key] then return key end
  return L.DEFAULT_COLOR
end

local function hex2(v)
  v = math.max(0, math.min(255, math.floor(v + 0.5)))
  return string.format('%02x', v)
end

local function clamp01(v)
  if v ~= v or v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- 'rrggbb' between two 'rrggbb' at k 0..1
function L.mix(a, b, k)
  k = clamp01(k)
  local out = {}
  for i = 1, 5, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    out[#out + 1] = hex2(x + (y - x) * k)
  end
  return table.concat(out)
end

-- 'rrggbb' of the fill / line at a heat 0..1, and burst 0..1 (white hot at the hit)
local function rgb(key, which, heat, burst)
  local c = L.COLORS[L.colorKey(key)]
  local v = L.mix(c[which], c[which + 2], heat or 0)
  if burst and burst > 0 then v = L.mix(v, L.BURST_COLOR[which], burst) end
  return v
end

-- '#rrggbbaa' of the fill at an alpha 0..1, a heat 0..1 and a burst 0..1
function L.fillColor(key, alpha, heat, burst)
  return '#' .. rgb(key, 1, heat, burst) .. hex2((alpha or L.FILL_ALPHA) * 255)
end

-- '#rrggbbaa' of the line: full alpha (only the burst fades it)
function L.lineColor(key, heat, burst, alpha)
  return '#' .. rgb(key, 2, heat, burst) .. hex2((alpha or 1) * 255)
end

-- ---------------------------------------------------------------- the message
local function int(v)
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
end

function L.tileKey(x, y)
  return x .. ',' .. y
end

-- a `floor` message -> an area {id, z, tiles = [{x, y}], set, color, hitAt, born, ms}, or nil and the reason. Every field is checked: a
-- server that sends junk (or more than MAX_TILES) draws nothing.
function L.parse(data, now)
  if type(data) ~= 'table' then return nil, 'no data' end
  local id = data.id
  if type(id) ~= 'string' or id == '' or #id > L.MAX_ID then return nil, 'bad id' end
  local z, x0, y0, ms = int(data.z), int(data.x0), int(data.y0), int(data.ms)
  if not z or z < 0 or z > 15 then return nil, 'bad floor' end
  if not x0 or not y0 or x0 < 0 or y0 < 0 or x0 > 65535 or y0 > 65535 then return nil, 'bad origin' end
  if not ms then return nil, 'bad time' end
  ms = math.max(L.MIN_MS, math.min(L.MAX_MS, ms))
  local t = data.t
  if type(t) ~= 'table' then return nil, 'no tiles' end
  local tiles, set = {}, {}
  for i = 1, #t do
    local p = t[i]
    if i > L.MAX_TILES then return nil, 'too many tiles' end
    if type(p) ~= 'table' then return nil, 'bad tile' end
    local dx, dy = int(p[1]), int(p[2])
    if not dx or not dy or dx < 0 or dy < 0 or dx > 255 or dy > 255 then return nil, 'bad tile' end
    local x, y = x0 + dx, y0 + dy
    local k = L.tileKey(x, y)
    if not set[k] then
      set[k] = true
      tiles[#tiles + 1] = { x = x, y = y }
    end
  end
  if #tiles == 0 then return nil, 'no tiles' end
  return { id = id, z = z, tiles = tiles, set = set, color = L.colorKey(data.c), hitAt = now + ms, born = now, ms = ms }
end

-- a `floorclear` message -> the id, 'all' for none, nil for junk
function L.parseClear(data)
  if data == nil then return 'all' end
  if type(data) ~= 'table' then return nil end
  if data.id == nil then return 'all' end
  if type(data.id) == 'string' and data.id ~= '' and #data.id <= L.MAX_ID then return data.id end
  return nil
end

function L.hello()
  return { action = 'floorhello', data = { v = L.VERSION } }
end

-- ---------------------------------------------------------------- the outline
-- sides that border an unmarked tile: bit 1 up, 2 right, 4 down, 8 left (a tile inside the area: 0)
function L.edgeMask(set, x, y)
  local m = 0
  if not set[L.tileKey(x, y - 1)] then m = m + 1 end
  if not set[L.tileKey(x + 1, y)] then m = m + 2 end
  if not set[L.tileKey(x, y + 1)] then m = m + 4 end
  if not set[L.tileKey(x - 1, y)] then m = m + 8 end
  return m
end

-- a mask -> up, right, down, left as booleans (no bit library: Lua 5.3 and LuaJIT both read this)
function L.sides(mask)
  mask = mask or 0
  return mask % 2 >= 1, math.floor(mask / 2) % 2 >= 1, math.floor(mask / 4) % 2 >= 1, math.floor(mask / 8) % 2 >= 1
end

-- ---------------------------------------------------------------- the state: the marks alive
function L.newState()
  return { areas = {}, order = {} }
end

local function total(st)
  local n = 0
  for _, a in pairs(st.areas) do n = n + #a.tiles end
  return n
end

local function drop(st, id)
  if not st.areas[id] then return false end
  st.areas[id] = nil
  for i, v in ipairs(st.order) do
    if v == id then
      table.remove(st.order, i)
      break
    end
  end
  return true
end

-- a mark in (the same id replaces the mark); the oldest go while there are too many marks or tiles. Returns the ids that went.
function L.add(st, area)
  local gone = {}
  if st.areas[area.id] then
    drop(st, area.id)
  end
  st.areas[area.id] = area
  st.order[#st.order + 1] = area.id
  while #st.order > L.MAX_AREAS or (total(st) > L.MAX_TOTAL and #st.order > 1) do
    local old = st.order[1]
    drop(st, old)
    gone[#gone + 1] = old
  end
  return gone
end

-- a clear: the ids that went
function L.clear(st, id)
  local gone = {}
  if id == 'all' then
    for _, v in ipairs(st.order) do gone[#gone + 1] = v end
    st.areas, st.order = {}, {}
  elseif drop(st, id) then
    gone[1] = id
  end
  return gone
end

function L.expired(area, now)
  return now >= area.hitAt + L.BURST_MS or now >= area.born + area.ms + L.EXPIRY_SLACK_MS
end

-- the marks past their hit go; returns their ids
function L.step(st, now)
  local gone = {}
  local ids = {}
  for _, id in ipairs(st.order) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    if L.expired(st.areas[id], now) then
      drop(st, id)
      gone[#gone + 1] = id
    end
  end
  return gone
end

function L.count(st)
  return #st.order
end

-- ---------------------------------------------------------------- the mark over time
-- the heat 0..1 at `now` of a mark born at `born` that hits at `hitAt`: progress ^ HEAT_POW
function L.heat(born, hitAt, now)
  local len = hitAt - born
  if len <= 0 then return 1 end
  return clamp01((now - born) / len) ^ L.HEAT_POW
end

-- the look at `now`: fill alpha, heat, burst (0 before the hit, 1 at it, falling to 0 over BURST_MS) and line alpha.
-- Before the hit: fade in, alpha FILL_ALPHA -> FILL_HOT with the heat, a throb that quickens as the hit nears and deepens with the
-- heat, and over the last BRIGHT_MS a flare to FILL_BRIGHT. At the hit: FILL_BURST, white hot, fading out.
function L.look(born, hitAt, now)
  local left = hitAt - now
  if left <= 0 then
    local k = clamp01(-left / L.BURST_MS)
    local fade = 1 - k
    return L.FILL_BURST * fade, 1, fade, fade
  end
  local heat = L.heat(born, hitAt, now)
  local alpha = L.FILL_ALPHA + (L.FILL_HOT - L.FILL_ALPHA) * heat
  alpha = alpha + L.THROB * heat * math.sin(2 * math.pi * math.sqrt(left / L.THROB_SCALE))
  if left < L.BRIGHT_MS then
    local k = 1 - left / L.BRIGHT_MS
    alpha = alpha + (L.FILL_BRIGHT - alpha) * k * k
  end
  local age = now - born
  if age < L.FADE_IN_MS then alpha = alpha * clamp01(age / L.FADE_IN_MS) end
  return clamp01(alpha), heat, 0, 1
end

-- the fill alpha alone (kept for callers of before)
function L.fillAlpha(born, hitAt, now)
  return (L.look(born, hitAt, now))
end

-- the alpha rounded to a step
function L.alphaStep(alpha)
  return math.floor(alpha * L.ALPHA_STEPS + 0.5)
end

-- one number for the picture of a tile: the widget is touched only when it changes
function L.lookStep(alpha, heat, burst)
  return (L.alphaStep(alpha) * 64 + math.floor(heat * L.HEAT_STEPS + 0.5)) * 64 + math.floor(burst * L.HEAT_STEPS + 0.5)
end

-- ---------------------------------------------------------------- the picture on the floor
-- the tiles of the marks on floor z, merged: one cell per tile with its edge mask from the UNION of all the marks, the colour and the hit
-- of the mark that hits first (the most urgent), sorted by row and column. A mark of another floor draws nothing.
function L.layout(st, z)
  local set = {}
  local cells = {}
  local ids = {}
  for _, id in ipairs(st.order) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    local x, y = st.areas[a], st.areas[b]
    if x.hitAt ~= y.hitAt then return x.hitAt < y.hitAt end
    return a < b
  end)
  for _, id in ipairs(ids) do
    local a = st.areas[id]
    if a.z == z then
      for _, t in ipairs(a.tiles) do
        local k = L.tileKey(t.x, t.y)
        set[k] = true
        if not cells[k] then
          cells[k] = { x = t.x, y = t.y, color = a.color, hitAt = a.hitAt, born = a.born }
        end
      end
    end
  end
  local list = {}
  for _, c in pairs(cells) do
    c.mask = L.edgeMask(set, c.x, c.y)
    list[#list + 1] = c
  end
  table.sort(list, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return list
end

-- ---------------------------------------------------------------- the widget's size and line
-- A floor widget is drawn in the map's own pixels (one tile is `spriteSize` of them whatever it measures on the screen); the engine puts
-- its centre at the tile's top left + margin + one sprite size, so the margin that lays a one tile widget over its tile is minus half a
-- sprite (the same as game_combatdecals).
function L.box(spriteSize)
  local spr = spriteSize or 32
  local m = math.floor(spr * -0.5 + 0.5)
  return spr, m, m
end

-- the line's width in map pixels so that it measures about LINE_PX on the screen: a tile of tilePx screen pixels is spriteSize map
-- pixels. At least one map pixel (a thinner line cannot be drawn), at most 3.
function L.lineWidth(tilePx, spriteSize)
  local spr = spriteSize or 32
  if type(tilePx) ~= 'number' or tilePx ~= tilePx or tilePx <= 0 then return L.LINE_PX end
  local scale = tilePx / spr
  return math.max(1, math.min(3, math.floor(L.LINE_PX / scale + 0.5)))
end

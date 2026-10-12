-- Tile overlays, the pure part (no client API; tileoverlayslogic_test.lua runs it with plain Lua 5.1 / LuaJIT / 5.3).
-- Two things drawn over map tiles by tileoverlays.lua:
--   field timers  the seconds left over magic walls, wild growth and other timed fields (table fielddata.lua, made by
--                 client/tools/gen_field_timers.py). The start is only known when the client saw the field appear on a
--                 tile it already had in view; a field that came into view with the tile (walking, a floor change, the
--                 login) shows "~".
--   server bars   labelled progress bars the server puts over positions (extended opcode 156, server
--                 data/scripts/chaos/tilebars.lua): a progress 0..1 or a countdown the client counts down itself.
TileOverlaysLogic = TileOverlaysLogic or {}
local TL = TileOverlaysLogic

TL.OPCODE = 156
TL.OPTION = 'fieldTimers'      -- Options > Interface (client base patch 0041)
TL.GRACE_MS = 250              -- a field removed and put back on its tile within this long keeps its timer
TL.MOVE_WINDOW_MS = 250        -- things added this soon after the player moved are judged from where the player was
TL.UNKNOWN = '~'
TL.DEFAULT_COLOR = '#d8b45a'
TL.BAR = { w = 66, h = 20, gap = 2, inner = 64 }

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

function TL.posKey(p)
  return p.x .. ',' .. p.y .. ',' .. p.z
end

local function validPos(p)
  return type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number'
    and p.x < 65535 and p.y < 65535 and p.z >= 0 and p.z <= 15
end
TL.validPos = validPos

-- seconds as the text over a tile: "9", "45", "1:05", "12:00"
function TL.formatSeconds(s)
  s = max(0, floor(s))
  if s < 60 then return tostring(s) end
  return string.format('%d:%02d', floor(s / 60), s % 60)
end

-- ms left -> whole seconds shown (rounded up: "1" until the very end, never "0" while time is left)
function TL.secondsLeft(ms)
  if ms <= 0 then return 0 end
  return floor((ms + 999) / 1000)
end

-- --------------------------------------------------------------- field timers
-- the client's view around the player: g_map.getAwareRange() is a size (18 x 14); the player stands at (8, 6) in it
function TL.rangeFromSize(w, h)
  w, h = tonumber(w) or 18, tonumber(h) or 14
  local left, top = floor((w - 1) / 2), floor((h - 1) / 2)
  return { left = left, right = w - 1 - left, top = top, bottom = h - 1 - top }
end

function TL.inRange(pos, ref, range)
  if not validPos(pos) or not validPos(ref) or pos.z ~= ref.z then return false end
  local dx, dy = pos.x - ref.x, pos.y - ref.y
  return dx >= -range.left and dx <= range.right and dy >= -range.top and dy <= range.bottom
end

-- where the player stood for things added now: just after a step the new row of tiles comes in the same packet as the
-- step, so a tile is judged by the place before the step (lastMove = {at, old})
function TL.refPos(current, lastMove, nowMs, window)
  if lastMove and lastMove.at and nowMs - lastMove.at <= (window or TL.MOVE_WINDOW_MS) then
    return lastMove.old
  end
  return current
end

-- a field seen appearing on a tile that was in view before: its start is now
function TL.isKnown(pos, ref, range)
  return TL.inRange(pos, ref, range)
end

function TL.newFields()
  return { recs = {}, ghosts = {} }
end

function TL.recKey(pos, id)
  return TL.posKey(pos) .. '#' .. id
end

-- a field item added on a tile. Returns the record (new or kept) or nil when the id is not a timed field.
-- rec = {key, pos, id, total, start (ms, nil = unknown), name}
function TL.fieldAdd(st, pos, id, nowMs, known, fields)
  local def = fields and fields[id]
  if not def or not validPos(pos) then return nil end
  local key = TL.recKey(pos, id)
  local cur = st.recs[key]
  if cur then return cur end -- the same field twice on one tile counts once
  local ghost = st.ghosts[key]
  st.ghosts[key] = nil
  local rec
  if ghost and nowMs - ghost.at <= TL.GRACE_MS and known then
    rec = ghost.rec -- the tile was rebuilt (the server sent it again): same field, same timer
  else
    rec = { key = key, pos = { x = pos.x, y = pos.y, z = pos.z }, id = id, total = def.t, name = def.n,
      start = known and nowMs or nil }
  end
  st.recs[key] = rec
  return rec
end

-- a field item left its tile: the record is kept as a ghost for GRACE_MS. Returns the record or nil.
function TL.fieldRemove(st, pos, id, nowMs)
  if not validPos(pos) then return nil end
  local key = TL.recKey(pos, id)
  local rec = st.recs[key]
  if not rec then return nil end
  st.recs[key] = nil
  st.ghosts[key] = { rec = rec, at = nowMs }
  return rec
end

-- drop old ghosts and the records that left the player's view (their tile is no longer kept up to date by the
-- server, so the timer could be wrong when it comes back: it comes back as "~"). Returns the dropped records.
function TL.fieldSweep(st, nowMs, playerPos, range)
  for key, g in pairs(st.ghosts) do
    if nowMs - g.at > TL.GRACE_MS then st.ghosts[key] = nil end
  end
  local dropped = {}
  for key, rec in pairs(st.recs) do
    if not TL.inRange(rec.pos, playerPos, range) then
      dropped[#dropped + 1] = rec
      st.recs[key] = nil
    end
  end
  table.sort(dropped, function(a, b) return a.key < b.key end)
  return dropped
end

-- ms left of a record (nil: unknown)
function TL.fieldLeft(rec, nowMs)
  if not rec.start then return nil end
  return rec.start + rec.total - nowMs
end

-- the text over the field: seconds left, or "~" when the start is unknown or the field outlived its time by more
-- than 2 s (server lag, or a lasting field that shares the look)
function TL.fieldText(rec, nowMs)
  local left = TL.fieldLeft(rec, nowMs)
  if not left or left < -2000 then return TL.UNKNOWN end
  return TL.formatSeconds(TL.secondsLeft(left))
end

-- colour of the timer: white, orange in the last 5 s, grey when unknown
function TL.fieldColor(rec, nowMs)
  local left = TL.fieldLeft(rec, nowMs)
  if not left or left < -2000 then return '#bfb6a6' end
  if left <= 5000 then return '#ffa040' end
  return '#ffffff'
end

-- --------------------------------------------------------------- server bars
function TL.color(c)
  if type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') then return c:lower() end
  return TL.DEFAULT_COLOR
end

-- one wire bar {i, p = [x, y, z], n, c, v | l + t} -> bar, or nil when it is junk
function TL.parseBar(w, nowMs)
  if type(w) ~= 'table' or type(w.i) ~= 'string' or w.i == '' or type(w.p) ~= 'table' then return nil end
  local pos = { x = tonumber(w.p[1]), y = tonumber(w.p[2]), z = tonumber(w.p[3]) }
  if not pos.x or not pos.y or not pos.z then return nil end
  pos = { x = floor(pos.x), y = floor(pos.y), z = floor(pos.z) }
  if not validPos(pos) then return nil end
  local bar = { id = w.i, pos = pos, label = type(w.n) == 'string' and w.n or '', color = TL.color(w.c) }
  local l, t = tonumber(w.l), tonumber(w.t)
  if l then
    bar.endMs = nowMs + max(0, l)
    bar.totalMs = max(1, t or l)
  else
    bar.v = min(1, max(0, tonumber(w.v) or 0))
  end
  return bar
end

-- a "bars" message into the store (id -> bar). Returns the ids set and the ids dropped (each sorted).
function TL.applyBars(store, data, nowMs)
  local set, del = {}, {}
  if type(data) ~= 'table' then return set, del end
  for _, id in ipairs(type(data.d) == 'table' and data.d or {}) do
    if type(id) == 'string' and store[id] then
      store[id] = nil
      del[#del + 1] = id
    end
  end
  for _, w in ipairs(type(data.s) == 'table' and data.s or {}) do
    local bar = TL.parseBar(w, nowMs)
    if bar then
      store[bar.id] = bar
      set[#set + 1] = bar.id
    end
  end
  table.sort(set)
  table.sort(del)
  return set, del
end

-- 0..1 drawn: the progress, or the part of a countdown still left
function TL.barProgress(bar, nowMs)
  if bar.endMs then
    return min(1, max(0, (bar.endMs - nowMs) / bar.totalMs))
  end
  return bar.v or 0
end

-- the label line: the label, and the time left of a countdown
function TL.barText(bar, nowMs)
  if bar.endMs then
    local t = TL.formatSeconds(TL.secondsLeft(bar.endMs - nowMs))
    return bar.label ~= '' and (bar.label .. ' ' .. t) or t
  end
  return bar.label
end

-- countdowns that ended more than graceMs ago (the server drops them too): their ids, sorted
function TL.expiredBars(store, nowMs, graceMs)
  local out = {}
  for id, bar in pairs(store) do
    if bar.endMs and nowMs > bar.endMs + (graceMs or 1500) then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

-- width of the coloured part of a bar inside `inner` pixels
function TL.fillWidth(progress, inner)
  inner = inner or TL.BAR.inner
  return min(inner, max(0, floor(progress * inner + 0.5)))
end

-- The engine centres a tile widget on (tile corner + 32 px), which is the tile's centre only at 64 px tiles: the margins
-- that put a widget's centre on the centre of a tile of tw x th px (the zoomed size on screen)
function TL.centre(tw, th)
  return floor((tw or 64) / 2 - 32 + 0.5), floor((th or 64) / 2 - 32 + 0.5)
end

-- a bar's width: at least BAR.w, wide enough for its text (the countdown's digits measured as the widest ones)
function TL.barWidth(textWidth)
  return max(TL.BAR.w, floor((textWidth or 0) + 12))
end

-- the lift of a tile's bar number i (1 = lowest) above the tile centre: the lowest one sits just over the tile (bars
-- mark objects: a brazier, a vein, a target point), the next ones above it
function TL.barLift(th, i)
  th = th or 64
  return floor(th / 2 + TL.BAR.h / 2 + 4) + ((i or 1) - 1) * (TL.BAR.h + TL.BAR.gap)
end

-- the bars of one tile in drawing order (by id) and each one's place among them (1 = the lowest)
function TL.stack(store, pos)
  local list = {}
  for _, bar in pairs(store) do
    if bar.pos.x == pos.x and bar.pos.y == pos.y and bar.pos.z == pos.z then list[#list + 1] = bar end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  local out = {}
  for i, bar in ipairs(list) do
    out[i] = { id = bar.id, index = i }
  end
  return out
end

-- the client asks for everything again (a new game, the module reloaded)
function TL.hello()
  return { action = 'hello' }
end

-- the options value -> on (anything but false is on: no settings module or no option = on)
function TL.isOn(value)
  return value ~= false and value ~= 0 and value ~= 'false'
end

return TL

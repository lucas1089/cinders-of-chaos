-- Ground loot labels: the rules without client API (tested by groundlabels_test.lua with luajit and lua5.3).
-- Which ground item or corpse gets a label (the loot filter's rules, the "Rare+" setting, Alt held), its text, colour
-- and despawn timer, which labels win when there are too many, and where each label goes so that none overlaps.
-- The filter rules are game_lootfilter's LootFilterLogic, handed in with GL.setFilterLogic.
-- Server rows (server/data/scripts/chaos/groundloot.lua):
--   item   {s, id, c, nm, r, u, o, pw, g, t, il, e}       corpse {s, id, k = 1, n, i = [{c, nm, r, u, o, pw, g, t}], e}

local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
GroundLabelsLogic = {}
local GL = GroundLabelsLogic
local LF

function GL.setFilterLogic(logic)
  LF = logic
end

GL.MAX_LABELS = 40
GL.RARE = 3 -- "Magic+" = rarity 3 (Magic) or better, uniques, orbs and legendary powers (the setting key stays rarePlus)
GL.TEXT_COLOR = '#d8cfbf' -- items without a rarity colour
GL.DIM_COLOR = '#8c8478'
GL.HIGHLIGHT_BACKGROUND = '#100c0ef0'
GL.PLAIN_BACKGROUND = '#0c0a0cd8'
-- the loot label accent cosmetic (game_cosmetics, server cosmetics.lua): the background of the labels the loot filter
-- makes glow (the player's own loot highlights). Text and border keep the rarity colour, so the rarity never changes.
GL.accent = nil

function GL.setAccent(color)
  if type(color) == 'string' and (color:match('^#%x%x%x%x%x%x$') or color:match('^#%x%x%x%x%x%x%x%x$')) then
    GL.accent = color
  else
    GL.accent = nil
  end
  return GL.accent
end

-- {text, border, background} of a label: d = the decision (GL.decide), color = GL.color(row, d)
function GL.style(d, color)
  if d.highlight then
    return { text = color, border = color, background = GL.accent or GL.HIGHLIGHT_BACKGROUND }
  end
  return { text = color, border = '#3a3230', background = GL.PLAIN_BACKGROUND }
end
GL.SIZES = {
  small = { font = 'verdana-9px-rounded', pad = 3 },
  normal = { font = 'verdana-11px-rounded', pad = 4 },
  large = { font = 'Verdana Bold-13px', pad = 5 },
}
GL.SIZE_ORDER = { 'small', 'normal', 'large' }

local function flag(v)
  return v == true or v == 1 or v == '1'
end

local function bool(v, default)
  if v == nil then return default end
  return v == true or v == 1 or v == '1' or v == 'true'
end

-- ---------------------------------------------------------------- settings (g_settings node "groundLabels")
-- enabled   labels at all
-- rarePlus  Rare+ items always get a label (else only the items the loot filter makes glow)
-- altAll    holding Alt shows every item on the ground, the ones the filter hides too (dimmed)
-- corpses   "Corpse: 2 items" over a corpse you may loot that holds items the filter makes glow
-- timers    the time until a label's item or corpse decays
-- size      small | normal | large
function GL.defaults()
  return { enabled = true, rarePlus = true, altAll = true, corpses = true, timers = true, size = 'normal' }
end

function GL.normalize(t)
  local d = GL.defaults()
  if type(t) ~= 'table' then return d end
  local out = {}
  for _, k in ipairs({ 'enabled', 'rarePlus', 'altAll', 'corpses', 'timers' }) do
    out[k] = bool(t[k], d[k])
  end
  out.size = GL.SIZES[t.size] and t.size or d.size
  return out
end

-- ---------------------------------------------------------------- what is on a tile
function GL.posKey(pos)
  return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

-- A number for a position: the scan looks at 200+ tiles every 60-400 ms, and a string key per tile made it the biggest
-- source of Lua garbage while walking (the garbage collector's pauses then land in the walking callbacks).
function GL.numKey(x, y, z)
  return z * 4294967296 + y * 65536 + x
end

-- The scan reads a tile's items (ids and counts, the costly part) only when the tile's thing count changed, or when its
-- last full look is older than VERIFY_MS (a stack that grew by one, an item swapped for another: the count stays).
-- The next full look of a tile is staggered by its key, so they do not all fall into one scan.
GL.VERIFY_MS = 1000
function GL.needsLook(c, count, nowMs)
  return c == nil or c.cnt ~= count or nowMs >= c.verifyAt
end

function GL.nextLook(nowMs, nkey)
  return nowMs + GL.VERIFY_MS + (nkey % 10) * 40
end

-- f = {ground, border, bottom, top, pickupable, container, corpse}: the things the labels are about
function GL.isCandidate(f)
  if f.ground or f.border or f.bottom then return false end
  if f.container and f.corpse then return true end
  return f.pickupable == true and not f.top
end

-- the tile's candidate items as a string; the server is asked again when it changes
function GL.signature(list)
  local parts = {}
  for i, x in ipairs(list) do
    parts[i] = (x.id or 0) .. 'x' .. (x.c or 1)
  end
  return table.concat(parts, ';')
end

-- ---------------------------------------------------------------- what gets a label
local function isRarePlus(info)
  return flag(info.u) or flag(info.o) or flag(info.pw) or (tonumber(info.r) or 0) >= GL.RARE
end
GL.isRarePlus = isRarePlus

local function filterState(info, filter)
  if flag(info.pw) then return 'highlight' end -- a legendary power always glows (as on the server)
  return LF.classify(info, filter)
end

-- items of a corpse the label counts: the ones the filter makes glow, and Rare+ ones the filter does not hide
local function corpseMatches(row, s, filter)
  local n, best, bestRank = 0, nil, -1
  for _, info in ipairs(type(row.i) == 'table' and row.i or {}) do
    local st = filterState(info, filter)
    if st == 'highlight' or (s.rarePlus and st ~= 'dim' and isRarePlus(info)) then
      n = n + 1 -- a stack counts once
      local rank = flag(info.u) and 100 or (tonumber(info.r) or 0)
      if rank > bestRank then best, bestRank = info, rank end
    end
  end
  return n, best
end

-- row = a server row; s = GL settings; filter = loot filter settings; alt = Alt held.
-- Returns nil (no label) or {kind = 'item' | 'corpse', dim = bool, highlight = bool, matches = n (corpse), best (corpse)}
function GL.decide(row, s, filter, alt)
  if not s.enabled or type(row) ~= 'table' then return nil end
  local showAll = alt and s.altAll
  if flag(row.k) then
    if not s.corpses then return nil end
    local n, best = corpseMatches(row, s, filter)
    if n > 0 then return { kind = 'corpse', matches = n, best = best, highlight = true, dim = false } end
    if showAll and (tonumber(row.n) or 0) > 0 then
      return { kind = 'corpse', matches = 0, dim = true, highlight = false }
    end
    return nil
  end
  local st = filterState(row, filter)
  if st == 'highlight' then return { kind = 'item', highlight = true, dim = false } end
  if st ~= 'dim' and s.rarePlus and isRarePlus(row) then return { kind = 'item', highlight = false, dim = false } end
  if showAll then return { kind = 'item', highlight = false, dim = st == 'dim' } end
  return nil
end

-- ---------------------------------------------------------------- text and colour
function GL.titleCase(name)
  name = tostring(name or 'item')
  return (name:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- seconds -> "1:42", "0:07", "1:02:03"
function GL.timerText(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%d:%02d', m, s)
end

-- seconds left of a row at time now (the row's e was received at row.at), or nil when it does not decay
function GL.secondsLeft(row, now)
  local e = tonumber(row.e)
  if not e then return nil end
  return math.max(0, e - (now - (tonumber(row.at) or now)))
end

-- the timer is shown for what is worth it: corpses with loot, items that glow or are Rare+
function GL.showTimer(row, d, s)
  if not s.timers or tonumber(row.e) == nil then return false end
  return d.kind == 'corpse' or d.highlight or isRarePlus(row)
end

function GL.itemText(row)
  local count = tonumber(row.c) or 1
  local name = GL.titleCase(row.nm)
  local r = (not flag(row.u)) and LF.rarityName(row.r) or nil
  return (count > 1 and (count .. 'x ') or '') .. (r and (r .. ' ') or '') .. name
end

function GL.corpseText(row, d)
  local n = d.matches > 0 and d.matches or (tonumber(row.n) or 0)
  return 'Corpse: ' .. n .. (n == 1 and ' item' or ' items')
end

function GL.text(row, d, s, now)
  local text = d.kind == 'corpse' and GL.corpseText(row, d) or GL.itemText(row)
  if GL.showTimer(row, d, s) then
    text = text .. '  ' .. GL.timerText(GL.secondsLeft(row, now))
  end
  return text
end

function GL.color(row, d)
  if d.dim then return GL.DIM_COLOR end
  local info = d.kind == 'corpse' and d.best or row
  return (info and LF.color(info)) or GL.TEXT_COLOR
end

-- corpse label tooltip: what it holds (the summary the server sent)
function GL.corpseTooltip(row)
  local lines = {}
  for _, info in ipairs(type(row.i) == 'table' and row.i or {}) do
    local c = tonumber(info.c) or 1
    lines[#lines + 1] = (c > 1 and (c .. 'x ') or '') .. LF.label({ u = info.u, r = info.r, nm = GL.titleCase(info.nm) })
  end
  local n = tonumber(row.n) or #lines
  if n > #lines then lines[#lines + 1] = tr('... and %d more', n - #lines) end
  lines[#lines + 1] = tr('Click: open the corpse')
  return table.concat(lines, '\n')
end

-- ---------------------------------------------------------------- which labels
-- higher first: uniques, then rarity, highlighted before plain, corpses with loot, then the nearest
function GL.priority(row, d)
  local p = 0
  if d.kind == 'corpse' then
    p = 300 + (d.best and (flag(d.best.u) and 100 or (tonumber(d.best.r) or 0) * 5) or 0)
  else
    p = (flag(row.u) and 600 or 0) + (tonumber(row.r) or 0) * 20 + (flag(row.o) and 40 or 0)
    if d.highlight then p = p + 200 end
  end
  if d.dim then p = p - 1000 end
  return p
end

-- entries = {{prio, dist, ...}}; keeps the best `max` (default MAX_LABELS), best first
function GL.select(entries, max)
  max = max or GL.MAX_LABELS
  table.sort(entries, function(a, b)
    if a.prio ~= b.prio then return a.prio > b.prio end
    if a.dist ~= b.dist then return a.dist < b.dist end
    return (a.order or 0) < (b.order or 0)
  end)
  local out = {}
  for i = 1, math.min(max, #entries) do out[i] = entries[i] end
  return out
end

-- ---------------------------------------------------------------- layout
local function overlaps(a, x, y, w, h, gap)
  return x < a.x + a.w + gap and a.x < x + w + gap and y < a.y + a.h + gap and a.y < y + h + gap
end

local function firstHit(placed, x, y, w, h, gap)
  for _, a in ipairs(placed) do
    if overlaps(a, x, y, w, h, gap) then return a end
  end
  return nil
end

-- groups = {{key, ax, ay, w, h}, ...} in priority order: one block of labels per tile, anchored at the tile (ax, ay in
-- pixels, any origin). Each block wants to sit centred over its anchor, its bottom `lift` pixels above it; a block that
-- would overlap one placed before moves up past it (then, if that is more than maxShift, down instead), so blocks of
-- the same and neighbouring tiles stack instead of covering each other.
-- Returns {[key] = {x, y, w, h}}: the block's top-left relative to its anchor.
function GL.layout(groups, o)
  o = o or {}
  local gap, lift, maxShift = o.gap or 2, o.lift or 0, o.maxShift or 200
  local placed, out = {}, {}
  for _, g in ipairs(groups) do
    local x = g.ax - math.floor(g.w / 2)
    local want = g.ay - lift - g.h
    local y, hit, n = want, nil, 0
    repeat
      hit = firstHit(placed, x, y, g.w, g.h, gap)
      if hit then y = hit.y - gap - g.h end
      n = n + 1
    until not hit or n > 64 or want - y > maxShift
    if hit or want - y > maxShift then
      local down = want
      n = 0
      repeat
        hit = firstHit(placed, x, down, g.w, g.h, gap)
        if hit then down = hit.y + hit.h + gap end
        n = n + 1
      until not hit or n > 64 or down - want > maxShift
      y = (not hit and down - want <= maxShift) and down or want
    end
    placed[#placed + 1] = { x = x, y = y, w = g.w, h = g.h }
    out[g.key] = { x = x - g.ax, y = y - g.ay, w = g.w, h = g.h }
  end
  return out
end

-- The engine draws a tile's widget centred on the tile; a block at (bx, by, w, h) relative to that centre needs a
-- widget of this size with the block at (cx, cy) inside it.
function GL.widgetBox(b)
  local W = 2 * math.max(math.abs(b.x), math.abs(b.x + b.w))
  local H = 2 * math.max(math.abs(b.y), math.abs(b.y + b.h))
  return { w = W, h = H, cx = math.floor(W / 2 + b.x), cy = math.floor(H / 2 + b.y) }
end

-- A press on a label is a click only when the mouse stays put; the engine starts a drag after 4 pixels
-- (UIManager::inputEvent), so a press that moved that far is a drag of the item and never a click on the label.
GL.DRAG_PIXELS = 4
function GL.isDrag(down, up)
  if type(down) ~= 'table' or type(up) ~= 'table' then return false end
  local dx, dy = (up.x or 0) - (down.x or 0), (up.y or 0) - (down.y or 0)
  return math.sqrt(dx * dx + dy * dy) >= GL.DRAG_PIXELS
end

-- the client's settings fingerprint of the loot filter (labels are rebuilt when it changes)
function GL.filterKey(f)
  if type(f) ~= 'table' then return '' end
  local show = type(f.show) == 'table' and f.show or {}
  return table.concat({ tostring(f.highlight), tostring(f.dim), tostring(f.tier), tostring(show.equipment),
    tostring(show.currency), tostring(show.supplies), tostring(show.other) }, ':')
end

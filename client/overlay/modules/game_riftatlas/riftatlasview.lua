-- Pure helpers of the Rift Atlas window (no client API), tested by riftatlasview_test.lua.
-- The tree and the state come from the server (server/data/scripts/chaos/atlas_core.lua A.treePayload / A.statePayload):
--   tree  {nodes = [{i, n, k = start|small|notable|keystone, b = theme, x, y, c = cost, l = links, t = lines, g = glyph}],
--          branches = [{k, n, th, d, c}], start, keystoneMax, grid = {themes, tiers, omens = [{k, n, b}], points, swift,
--          swiftTiers = [seconds per tier]}, max}
--   state {earned, spent, points, max, alloc = [ids], done = [cell keys], refund = {gold, orbs}, reset = {gold, orbs},
--          orb, totals = [lines], msg}
-- The allocate / refund rules mirror atlas_core.lua (the server checks again; this only greys the buttons).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
RiftAtlasView = {}
local V = RiftAtlasView

-- the cells of the icon sheets (client/tools/gen_riftatlas_art.py GLYPHS, same order)
V.GLYPHS = { 'density', 'elite', 'time', 'reward', 'gold', 'key', 'upgrade', 'fragment', 'orb', 'rolls', 'goblin', 'coffer',
  'life', 'theme_abyss', 'theme_hall', 'theme_crypt', 'theme_sanctum', 'ks_ember', 'ks_crown', 'ks_ascent', 'ks_hourglass' }
V.CELL = 64
V.ZOOMS = { 0.3, 0.4, 0.5, 0.65, 0.8, 1.0 }
V.DEFAULT_ZOOM = 2
-- node size at zoom 1 (the passive tree's: small 27, notable 38, keystone 60) and the frame around it
V.SIZES = { start = 100, small = 27, notable = 38, keystone = 60 }
V.MARGIN = 140 -- world units of map around the outermost nodes

local GLYPH_INDEX = {}
for i, g in ipairs(V.GLYPHS) do GLYPH_INDEX[g] = i - 1 end

local function num(v) return tonumber(v) or 0 end

-- ---------------------------------------------------------------- index
-- {byId, adj (symmetric), list, pairs (each link once), setOf (theme -> sheet key), branchByTheme}
function V.index(tree)
  local ix = { byId = {}, adj = {}, list = {}, pairs = {}, setOf = {}, branchByTheme = {}, start = num(tree and tree.start) }
  if type(tree) ~= 'table' then return ix end
  for _, b in ipairs(tree.branches or {}) do
    ix.setOf[b.th] = b.k
    ix.branchByTheme[b.th] = b
  end
  for _, n in ipairs(tree.nodes or {}) do
    ix.byId[n.i] = n
    ix.adj[n.i] = ix.adj[n.i] or {}
    ix.list[#ix.list + 1] = n
  end
  local seen = {}
  for _, n in ipairs(ix.list) do
    for _, l in ipairs(n.l or {}) do
      if ix.byId[l] and l ~= n.i then
        ix.adj[n.i][l] = true
        ix.adj[l][n.i] = true
        local a, b = math.min(n.i, l), math.max(n.i, l)
        local key = a .. '-' .. b
        if not seen[key] then
          seen[key] = true
          ix.pairs[#ix.pairs + 1] = { a, b }
        end
      end
    end
  end
  return ix
end

function V.allocSet(state)
  local s = {}
  for _, id in ipairs(type(state) == 'table' and state.alloc or {}) do s[num(id)] = true end
  return s
end

function V.doneSet(state)
  local s = {}
  for _, k in ipairs(type(state) == 'table' and state.done or {}) do s[tostring(k)] = true end
  return s
end

local function held(ix, alloc, id)
  return id == ix.start or alloc[id] == true
end

local function keystones(ix, alloc)
  local n = 0
  for id in pairs(alloc) do
    local node = ix.byId[id]
    if node and node.k == 'keystone' then n = n + 1 end
  end
  return n
end

function V.connected(ix, alloc)
  local seen, queue, i = { [ix.start] = true }, { ix.start }, 1
  while queue[i] do
    local id = queue[i]
    i = i + 1
    for o in pairs(ix.adj[id] or {}) do
      if alloc[o] and not seen[o] then
        seen[o] = true
        queue[#queue + 1] = o
      end
    end
  end
  for id, v in pairs(alloc) do
    if v and id ~= ix.start and not seen[id] then return false end
  end
  return true
end

-- true, or false and a reason: unknown | held | points | keystone | path
function V.canAllocate(ix, alloc, id, points, keystoneMax)
  local node = ix.byId[id]
  if not node or node.k == 'start' then return false, 'unknown' end
  if alloc[id] then return false, 'held' end
  if num(node.c) > num(points) then return false, 'points' end
  if node.k == 'keystone' and keystones(ix, alloc) >= num(keystoneMax) then return false, 'keystone' end
  for o in pairs(ix.adj[id] or {}) do
    if held(ix, alloc, o) then return true end
  end
  return false, 'path'
end

function V.canRefund(ix, alloc, id)
  if not alloc[id] then return false, 'not held' end
  alloc[id] = nil
  local ok = V.connected(ix, alloc)
  alloc[id] = true
  if not ok then return false, 'path' end
  return true
end

-- start | alloc | avail (can be taken now) | reach (connected, but no points / keystone limit) | locked
function V.status(ix, alloc, id, points, keystoneMax)
  local node = ix.byId[id]
  if not node then return 'locked' end
  if node.k == 'start' then return 'start' end
  if alloc[id] then return 'alloc' end
  local ok, why = V.canAllocate(ix, alloc, id, points, keystoneMax)
  if ok then return 'avail' end
  if why == 'points' or why == 'keystone' then
    for o in pairs(ix.adj[id] or {}) do
      if held(ix, alloc, o) then return 'reach' end
    end
  end
  return 'locked'
end

-- the look of a link: Active (both ends held), Intermediate (one end), Normal
function V.linkState(ix, alloc, a, b)
  local ha, hb = held(ix, alloc, a), held(ix, alloc, b)
  if ha and hb then return 'Active' end
  if ha or hb then return 'Intermediate' end
  return 'Normal'
end

-- ---------------------------------------------------------------- art
function V.iconSet(ix, node)
  return (node and ix.setOf[node.b]) or 'core'
end

-- the glyph of a node ("theme" becomes the branch's own emblem)
function V.glyphOf(ix, node)
  local g = node and node.g or 'density'
  if g == 'theme' then return 'theme_' .. V.iconSet(ix, node) end
  return g
end

-- "x y w h" of the glyph's cell in its sheet (an unknown glyph: the first cell)
function V.iconClip(glyph)
  local i = GLYPH_INDEX[glyph] or 0
  return string.format('%d 0 %d %d', i * V.CELL, V.CELL, V.CELL)
end

-- the frame image of a node kind in a state (the passive tree's frames)
local FRAMES = {
  small = { alloc = 'common_active', avail = 'commont_canallocate', other = 'common_notallocated', size = { 56, 56 } },
  notable = { alloc = 'NotableFrameAllocated', avail = 'NotableFrameCanAllocate', other = 'NotableFrameUnallocated', size = { 95, 95 } },
  keystone = { alloc = 'KeystoneFrameAllocated', avail = 'KeystoneFrameCanAllocate', other = 'KeystoneFrameUnallocated', size = { 143, 149 } },
}
-- {source, w, h} of the frame at node size `s` (nil for the start)
function V.frame(kind, status, s)
  local f = FRAMES[kind]
  if not f then return nil end
  local base = V.SIZES[kind]
  local key = (status == 'alloc' and 'alloc') or (status == 'avail' and 'avail') or 'other'
  local scale = s / base
  return { source = '/images/passivetree/' .. f[key], w = math.floor(f.size[1] * scale + 0.5), h = math.floor(f.size[2] * scale + 0.5) }
end

-- ---------------------------------------------------------------- view
-- the node size on screen: shrinks slower than the map, so the icons stay readable when zoomed out
function V.nodeSize(kind, zoom)
  local s = V.SIZES[kind] or V.SIZES.small
  return math.max(8, math.floor(s * (0.45 + 0.55 * num(zoom)) + 0.5))
end

function V.bounds(ix)
  local b = { minX = 0, maxX = 0, minY = 0, maxY = 0 }
  for _, n in ipairs(ix.list) do
    b.minX, b.maxX = math.min(b.minX, num(n.x)), math.max(b.maxX, num(n.x))
    b.minY, b.maxY = math.min(b.minY, num(n.y)), math.max(b.maxY, num(n.y))
  end
  b.minX, b.minY = b.minX - V.MARGIN, b.minY - V.MARGIN
  b.maxX, b.maxY = b.maxX + V.MARGIN, b.maxY + V.MARGIN
  return b
end

-- the map's world centre and size {cx, cy, w, h}
function V.world(ix)
  local b = V.bounds(ix)
  return { cx = (b.minX + b.maxX) / 2, cy = (b.minY + b.maxY) / 2, w = b.maxX - b.minX, h = b.maxY - b.minY }
end

-- the pan (offset of the map centre from the view centre, in pixels) kept so the map covers the whole view (a map
-- smaller than the view stays centred)
function V.clampPan(px, py, zoom, world, viewW, viewH)
  local hw = math.max(0, world.w * zoom / 2 - viewW / 2)
  local hh = math.max(0, world.h * zoom / 2 - viewH / 2)
  return math.max(-hw, math.min(hw, num(px))), math.max(-hh, math.min(hh, num(py)))
end

-- the next zoom index (dir +1 in, -1 out), clamped
function V.zoomStep(i, dir)
  return math.max(1, math.min(#V.ZOOMS, num(i) + (dir > 0 and 1 or -1)))
end

-- pixel offset of a node from the canvas centre
function V.place(world, node, zoom)
  return math.floor((num(node.x) - world.cx) * zoom + 0.5), math.floor((num(node.y) - world.cy) * zoom + 0.5)
end

-- a link drawn as a rotated bar: centre offset, length, angle (degrees)
function V.linkGeometry(world, a, b, zoom)
  local ax, ay = V.place(world, a, zoom)
  local bx, by = V.place(world, b, zoom)
  local dx, dy = bx - ax, by - ay
  return { x = math.floor((ax + bx) / 2 + 0.5), y = math.floor((ay + by) / 2 + 0.5),
    len = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5), angle = (math.atan2 or math.atan)(dy, dx) * 180 / math.pi }
end

-- the pan that puts a node in the middle of the view
function V.panTo(world, node, zoom)
  local x, y = V.place(world, node, zoom)
  return -x, -y
end

-- ---------------------------------------------------------------- text
local KIND = { start = 'Start', small = 'Node', notable = 'Notable', keystone = 'Keystone' }
local REASON = {
  unknown = 'Unknown node.', held = 'Allocated.', points = 'Not enough points: seal new rifts to earn more.',
  keystone = 'You hold a keystone already: refund it first.', path = 'Not connected to your atlas yet.',
  ['not held'] = 'Not allocated.',
}
function V.reasonText(why) return REASON[why] or tostring(why or '') end

function V.kindLine(node)
  if not node then return '' end
  if node.k == 'start' then return tr('Start of the atlas') end
  local c = num(node.c)
  return string.format('%s, %d point%s', KIND[node.k] or 'Node', c, c == 1 and '' or 's')
end

function V.tooltip(node, status)
  if not node then return '' end
  local lines = { tostring(node.n or '?'), V.kindLine(node) }
  for _, t in ipairs(node.t or {}) do lines[#lines + 1] = tostring(t) end
  if status == 'alloc' then
    lines[#lines + 1] = 'Allocated.'
  elseif status == 'avail' then
    lines[#lines + 1] = 'Click, then Allocate.'
  end
  return table.concat(lines, '\n')
end

-- 1500000 -> "1.5M", 250000 -> "250k", 900 -> "900"
function V.short(n)
  n = num(n)
  if n >= 1000000 then
    local s = string.format('%.1f', n / 1000000):gsub('%.0$', '')
    return s .. 'M'
  elseif n >= 1000 then
    local s = string.format('%.1f', n / 1000):gsub('%.0$', '')
    return s .. 'k'
  end
  return tostring(math.floor(n))
end

function V.pointsLine(state)
  if type(state) ~= 'table' then return '' end
  return string.format('%d', num(state.points))
end

function V.earnedLine(state)
  if type(state) ~= 'table' then return '' end
  return string.format('Earned %d / %d, spent %d', num(state.earned), num(state.max), num(state.spent))
end

function V.refundLabels(state)
  local r = type(state) == 'table' and state.refund or {}
  return string.format('Refund %s', V.short(r.gold)),
    string.format('Refund %d orb%s', num(r.orbs), num(r.orbs) == 1 and '' or 's')
end

-- ---------------------------------------------------------------- the completion grid
-- the Swift time of a tier in whole seconds: the server's per-tier time (grid.swiftTiers, it grows with the rift's
-- map size and tier), else the one time of an older server (grid.swift)
function V.swiftSeconds(g, tier)
  local per = type(g) == 'table' and type(g.swiftTiers) == 'table' and tonumber(g.swiftTiers[tier]) or nil
  return math.max(0, math.floor(per or num(type(g) == 'table' and g.swift or 0)))
end

-- rows {label, color, kind, cells = {{key, done, tip}}} for the theme x tier rows, flawless, swift; then the omens
local SHORT = { ['Abyssal Rift'] = 'Abyss', ['Obsidian Hall'] = 'Hall', ['Ashen Crypt'] = 'Crypt', ['Forsaken Sanctum'] = 'Sanctum' }
function V.gridRows(tree, done)
  local rows = {}
  local g = type(tree) == 'table' and tree.grid or nil
  if not g then return rows end
  if type(g.rows) == 'table' then return V.listRows(g.rows, done) end
  local ix = V.index(tree)
  local P = g.points or {}
  local tiers = num(g.tiers)
  for ti, name in ipairs(g.themes or {}) do
    local b = ix.branchByTheme[name]
    local row = { label = SHORT[name] or name, color = b and b.c or '#d6c9ae', kind = 'cell', cells = {} }
    for t = 1, tiers do
      local key = 'c' .. ti .. '.' .. t
      row.cells[t] = { key = key, done = done[key] == true,
        tip = string.format('%s tier %d: %s (+%d)', name, t, done[key] and 'sealed' or tr('not yet'), num(P.cell)) }
    end
    rows[#rows + 1] = row
  end
  local flaw = { label = 'Flawless', color = '#9fd89f', kind = 'flawless', cells = {} }
  local swift = { label = 'Swift', color = '#7fb8e8', kind = 'swift', cells = {} }
  for t = 1, tiers do
    flaw.cells[t] = { key = 'f' .. t, done = done['f' .. t] == true,
      tip = tr('Flawless tier %d (no death): %s (+%d)', t, done['f' .. t] and 'done' or tr('not yet'), num(P.flawless)) }
    local secs = V.swiftSeconds(g, t)
    swift.cells[t] = { key = 's' .. t, done = done['s' .. t] == true,
      tip = tr('Swift tier %d (sealed within %d:%02d): %s (+%d)', t, math.floor(secs / 60), secs % 60,
        done['s' .. t] and 'done' or tr('not yet'), num(P.swift)) }
  end
  rows[#rows + 1] = flaw
  rows[#rows + 1] = swift
  local omen = { label = 'Omens', color = '#e05a3a', kind = 'omen', cells = {} }
  for i, o in ipairs(g.omens or {}) do
    local key = 'o' .. tostring(o.k)
    omen.cells[i] = { key = key, done = done[key] == true, name = tostring(o.n),
      tip = string.format('%s: %s (+%d)', tostring(o.b or o.n), done[key] and 'slain' or 'not yet', num(P.omen)) }
  end
  rows[#rows + 1] = omen
  return rows
end

-- a grid the server sends as rows (the Waystone Atlas: {label, color, cells {k, n, c = column, p = points, co = colour}})
function V.listRows(list, done)
  local rows = {}
  for _, r in ipairs(list) do
    local row = { label = tostring(r.label or ''), color = r.color or '#d6c9ae', kind = 'cell', cells = {} }
    for _, c in ipairs(type(r.cells) == 'table' and r.cells or {}) do
      local key = tostring(c.k)
      row.cells[#row.cells + 1] = { key = key, done = done[key] == true, col = num(c.c), color = c.co,
        tip = string.format('%s: %s (+%d)', tostring(c.n or key), done[key] and tr('done') or tr('not yet'), num(c.p)) }
    end
    rows[#rows + 1] = row
  end
  return rows
end

-- done / total cells of the grid
function V.gridCount(rows)
  local d, t = 0, 0
  for _, r in ipairs(rows) do
    for _, c in ipairs(r.cells) do
      t = t + 1
      if c.done then d = d + 1 end
    end
  end
  return d, t
end

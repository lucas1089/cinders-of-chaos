-- Charms window texts and rules (pure, no UI calls): shared by charms.lua and charmsview_test.lua.
-- `s` is the server's state (server data/scripts/chaos/charms.lua CH.state): cols, rows, cells = {{x, y, open, why}},
-- placed = {{id, x, y, w, h, name, rarity, color, ilvl, mods = {{k, v, t}}, signature, icon, active}}, bag (the charms in
-- the backpack: {ref, sid, iid, w, h, ...}), groups = {{text, open, cells}}, totals = {{k, v, cap, t}}, level, shards.
-- The grid rules here mirror the server's (charms_core.lua placeRefusal) for the drag preview; the server decides.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

CharmsView = CharmsView or {}
local V = CharmsView

V.CELL = 44 -- pixels per grid cell
V.GAP = 2
V.LOCK_IMAGE = '/images/game/depot/lock' -- the padlock of a locked cell (our depot art, 10x12, drawn at 2x)

-- The look of each charm in the window: an item sprite of the live pair (client id), drawn with a UIItem. The key is
-- the charm's `icon` from the server (its unique key, else the key of its first modifier). Every key has its own
-- trinket, none shared (charmsview_test.lua checks it against server charms_config.lua). A key without an entry
-- shows the charm item's own look (`item`, the client id the server sends), else the small charm's.
V.LOOKS = {
  dmg_dragons = 3085, -- dragon necklace
  dmg_demons = 9041, -- vampiric crest
  dmg_undead = 22191, -- skull fetish
  dmg_humans = 9222, -- royal medal
  dmg_humanoids = 10198, -- tribal crest
  dmg_beasts = 3102, -- paw amulet
  dmg_elementals = 16113, -- prismatic necklace
  dmg_vermin = 3018, -- scarab amulet
  res_fire = 817, -- magma amulet
  res_ice = 815, -- glacier amulet
  res_energy = 816, -- lightning pendant
  res_earth = 814, -- terra amulet
  res_death = 22195, -- onyx pendant
  res_holy = 6561, -- ceremonial ankh
  lifeonkill = 10341, -- phoenix charm
  goldfind = 21974, -- golden lotus brooch
  orbfind = 8822, -- ghost charm (a glowing orb)
  oocspeed = 3254, -- roc feather
  reputation = 5785, -- medal of honour
  rifttime = 9660, -- mystical hourglass
  gravewarden = 22184, -- shamanic talisman (unique: Gravewarden's Seal)
  compass = 10302, -- compass (unique: Wanderer's Compass)
  hoard = 22707, -- opticompass sphere (unique: Eye of the Hoard)
  tally = 17856, -- basalt fetish (unique: Ashen Tally)
}
V.DEFAULT_LOOK = 9219 -- arcane insignia, the small charm item's look
-- rarities drawn with a glow behind the frame (Faint: the frame only)
V.GLOW = { Glowing = true, Radiant = true, Unique = true }
V.COLORS = { gold = '#e8b84a', text = '#d8ccb4', dim = '#8c8070', good = '#8fd16a', bad = '#e07060', warn = '#e0a050',
  open = '#ffffff', locked = '#4a403c', ok = '#5fb04a', no = '#c0463c', select = '#fff0c0' }

local function num(v) return tonumber(v) or 0 end

-- the client id a charm is drawn with
function V.lookOf(c)
  if not c then return V.DEFAULT_LOOK end
  return V.LOOKS[c.icon or ''] or (num(c.item) > 0 and num(c.item)) or V.DEFAULT_LOOK
end

-- the drawn size of a charm's sprite: 32 px, or 64 px (twice, whole pixels) when the charm covers 2 x 2 cells or more
function V.lookSide(w, h)
  return math.min(num(w), num(h)) >= 2 and 64 or 32
end

-- the slot image of a charm tile w x h cells (drawn at its exact size), nil for a shape without one
V.SLOTS = { ['1x1'] = true, ['2x1'] = true, ['1x2'] = true, ['2x2'] = true }
function V.slotImage(w, h)
  local k = string.format('%dx%d', num(w), num(h))
  return V.SLOTS[k] and ('/images/chaos/charmslot_' .. k) or nil
end

function V.glows(c)
  return c ~= nil and V.GLOW[c.rarity or ''] == true
end

function V.key(x, y) return x .. ',' .. y end

-- the cell under a point relative to the grid's top-left corner (nil outside)
function V.cellAt(s, px, py)
  if not s then return nil end
  local step = V.CELL + V.GAP
  local x, y = math.floor(px / step) + 1, math.floor(py / step) + 1
  if px < 0 or py < 0 or x > num(s.cols) or y > num(s.rows) then return nil end
  return x, y
end

-- the top-left cell for a dragged charm of w x h drawn centred on the point (the ghost follows the mouse that way);
-- nil when the point itself is outside the grid
function V.anchor(s, px, py, w, h)
  if not V.cellAt(s, px, py) then return nil end
  local step = V.CELL + V.GAP
  local x = math.floor((px - (num(w) - 1) * step / 2) / step) + 1
  local y = math.floor((py - (num(h) - 1) * step / 2) / step) + 1
  return x, y
end

-- pixel rectangle of a charm (or a cell) inside the grid
function V.rect(x, y, w, h)
  local step = V.CELL + V.GAP
  return { x = (x - 1) * step, y = (y - 1) * step, width = w * step - V.GAP, height = h * step - V.GAP }
end

function V.footprint(w, h, x, y)
  local out = {}
  for dy = 0, num(h) - 1 do
    for dx = 0, num(w) - 1 do
      out[#out + 1] = { x + dx, y + dy }
    end
  end
  return out
end

local function cellIndex(s)
  local idx = {}
  for _, c in ipairs(s and s.cells or {}) do
    idx[V.key(c.x, c.y)] = c
  end
  return idx
end

function V.occupancy(s, ignoreId)
  local occ = {}
  for _, p in ipairs(s and s.placed or {}) do
    if p.id ~= ignoreId then
      for _, c in ipairs(V.footprint(p.w, p.h, p.x, p.y)) do
        occ[V.key(c[1], c[2])] = p.id
      end
    end
  end
  return occ
end

-- ok, reason for a charm of w x h at x, y (ignoreId: the charm being moved)
function V.check(s, w, h, x, y, ignoreId)
  if not s or not x or not y then return false, tr('Drop it on the grid.') end
  local cells, occ = cellIndex(s), V.occupancy(s, ignoreId)
  for _, c in ipairs(V.footprint(w, h, x, y)) do
    local cell = cells[V.key(c[1], c[2])]
    if not cell then return false, tr('The charm does not fit inside the grid there.') end
    if not cell.open then return false, tr('That cell is locked: %s', tostring(cell.why or '')) end
    if occ[V.key(c[1], c[2])] then return false, tr('Another charm is in the way.') end
  end
  if not ignoreId and #(s.placed or {}) >= num(s.max ~= nil and s.max or 20) then
    return false, tr('Your charm grid is full.')
  end
  return true
end

-- the preview while dragging: the cells the charm would cover (inside the grid) and whether it fits
function V.preview(s, drag, px, py)
  if not s or not drag then return nil end
  local x, y = V.anchor(s, px, py, drag.w, drag.h)
  if not x then return nil end
  local ok, why = V.check(s, drag.w, drag.h, x, y, drag.id)
  local cells = {}
  for _, c in ipairs(V.footprint(drag.w, drag.h, x, y)) do
    if c[1] >= 1 and c[2] >= 1 and c[1] <= num(s.cols) and c[2] <= num(s.rows) then
      cells[#cells + 1] = c
    end
  end
  return { x = x, y = y, ok = ok, why = why, cells = cells }
end

-- what a drop does: {action = 'place' | 'move' | 'take', data} or nil, reason
function V.dropAction(s, drag, target, px, py)
  if not drag then return nil end
  if target == 'bag' then
    if drag.kind == 'placed' then return { action = 'take', data = { id = drag.id } } end
    return nil
  end
  if target ~= 'grid' then return nil end
  local p = V.preview(s, drag, px, py)
  if not p then return nil, tr('Drop it on the grid.') end
  if not p.ok then return nil, p.why end
  if drag.kind == 'placed' then
    if p.x == drag.x and p.y == drag.y then return nil end
    return { action = 'move', data = { id = drag.id, x = p.x, y = p.y } }
  end
  return { action = 'place', data = { ref = drag.ref, pos = drag.pos, sid = drag.sid, iid = drag.iid, x = p.x, y = p.y } }
end

-- the tooltip of a charm
function V.tooltip(c, placed)
  if not c then return '' end
  local lines = { c.name or 'Charm' }
  lines[#lines + 1] = tr('%s, item level %d, %dx%d', c.rarity or '?', num(c.ilvl), num(c.w), num(c.h))
  for _, m in ipairs(c.mods or {}) do
    lines[#lines + 1] = '  ' .. (m.t or (tostring(m.k) .. ' ' .. tostring(m.v)))
  end
  if c.signature then lines[#lines + 1] = c.signature end
  if placed and c.active == false then
    lines[#lines + 1] = tr('Inactive: it covers a cell that is locked again.')
  end
  if placed then
    lines[#lines + 1] = tr('Drag it to move it; drag it onto your charms list to take it out.')
  else
    lines[#lines + 1] = tr('Drag it onto the grid to place it.')
    local tail = {}
    if c.salvage then tail[#tail + 1] = tr('salvage: %d shards', num(c.salvage)) end
    if c.reforge then tail[#tail + 1] = tr('reforge: %d shards', num(c.reforge)) end
    if #tail > 0 then lines[#lines + 1] = table.concat(tail, ', ') end
  end
  return table.concat(lines, '\n')
end

-- the totals summary lines {text, color}
function V.totalsLines(s)
  local out = {}
  for _, r in ipairs(s and s.totals or {}) do
    local capped = num(r.cap) > 0 and num(r.v) >= num(r.cap)
    out[#out + 1] = { text = (r.t or '') .. (capped and ('  ' .. tr('(cap)')) or ''), color = capped and V.COLORS.warn or V.COLORS.text }
  end
  if #out == 0 then
    out[1] = { text = tr('No charm placed yet.'), color = V.COLORS.dim }
  end
  return out
end

-- the unlock list lines {text, color}
function V.unlockLines(s)
  local out = {}
  for _, g in ipairs(s and s.groups or {}) do
    out[#out + 1] = { text = tr('%s %s: %d cells', g.open and '[open]' or '[locked]', g.text or '', num(g.cells)),
      color = g.open and V.COLORS.good or V.COLORS.dim }
  end
  return out
end

-- the header line: open cells, placed charms, shards
function V.header(s)
  if not s then return '' end
  local open = 0
  for _, c in ipairs(s.cells or {}) do
    if c.open then open = open + 1 end
  end
  return tr('%d of %d cells open  -  %d charms placed  -  %d charm shards', open, num(s.cols) * num(s.rows),
    #(s.placed or {}), num(s.shards))
end

-- the bag entry, by its ref
function V.bagEntry(s, ref)
  for _, b in ipairs(s and s.bag or {}) do
    if b.ref == ref then return b end
  end
end

function V.placedEntry(s, id)
  for _, p in ipairs(s and s.placed or {}) do
    if p.id == id then return p end
  end
end

-- Rich item tooltips, the view logic without client API (tested by tooltiplogic_test.lua): cache keys, what is
-- asked from the server, the lines a tooltip shows and the differences of the Ctrl compare view.
-- The tooltip itself comes from the server (extended opcode 242, server/data/scripts/chaos/item_tooltip_core.lua):
--   {key, id, name, count, kind, slot, rarity, rarityName, level, maxTier, sides = {p, s, max},
--    unique = {name, set = {name, have, total}}, base = [{k, l, v, fmt}],
--    quality = {q, cap} (item quality in percent), ruined (an Orb of Ruin ruined it),
--    mods = [{k, l, t, v, g, lo, hi, tr, sd, bd, pw}] (prefixes first; tr = tier 1..8, sd = 'p' / 's', bd = bound,
--    pw = a legendary power),
--    sockets = {count, max, list = [{name, text, color}]},
--    req = {level, magic, voc}, weight, desc, locked, store, collects (a store pouch), stats = [{k, l, v, fmt, low}], cmp = [slot, ...]}

ItemTooltipLogic = {}
local L = ItemTooltipLogic

L.INVENTORY_X = 0xFFFF
L.MAX_CACHE = 400
L.PLAIN_TTL = 30 -- seconds a tooltip of an item without client attributes is kept
L.WRAP = 44 -- characters per line of the flavour text

L.COLORS = {
  text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', mod = '#9ab8ff', chaos = '#e080d0', element = '#ffa060',
  gem = '#c8e8ff', empty = '#6b6258', power = '#ff9a3c', bound = '#e8b84a', quality = '#7fe0a0', better = '#5ccf5c', worse = '#e03a1e', unique = '#e07b24', red = '#e03a1e',
  normal = '#e4d8c0'
}
-- modifier tiers T1 (lowest) .. T8 (highest)
L.TIER_COLORS = { '#8c8070', '#a89c88', '#c8c8c8', '#5ccf5c', '#4a90ff', '#a35cf0', '#ffd040', '#ff8a40' }
L.RARITY_COLORS = { '#c8c8c8', '#5ccf5c', '#4a90ff', '#a35cf0', '#ffd040', '#f5b13a', '#ff5a5a', '#e02424', '#ff8a70',
  '#c8e8ff', '#9ad8ff', '#e4f2ff', '#b878ff', '#9a4ce0', '#e070ff' }

-- ---------------------------------------------------------------- keys and requests
-- attrs = {id = per-item id, ver = version} from the item's custom attributes (0 when missing)
function L.cacheKey(attrs, clientId, count, pos)
  local id, ver = tonumber(attrs and attrs.id) or 0, tonumber(attrs and attrs.ver) or 0
  if id > 0 then
    return string.format('%.0f:%.0f', id, ver), false
  end
  pos = pos or {}
  return string.format('p:%d:%d:%d:%d:%d', tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0,
    tonumber(clientId) or 0, tonumber(count) or 1), true
end

-- only items in the inventory or an open container are asked about (the server checks again)
function L.askable(pos)
  return type(pos) == 'table' and tonumber(pos.x) == L.INVENTORY_X
end

function L.inventoryPos(slot)
  return { x = L.INVENTORY_X, y = slot, z = 0 }
end

-- iid: a number or the decimal string sent to the server (JSON would round a number past 14 digits)
function L.iidText(iid)
  if type(iid) == 'string' and iid:match('^%d+$') then return iid end
  return string.format('%.0f', tonumber(iid) or 0)
end

function L.posKey(pos, iid)
  pos = pos or {}
  return string.format('%d,%d,%d,%d,%s', tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0,
    tonumber(pos.s) or 0, L.iidText(iid))
end

-- a small cache with an age limit for plain entries and a size limit
function L.newCache()
  return { entries = {}, order = {} }
end

function L.cacheGet(cache, key, now)
  local e = cache.entries[key]
  if not e then return nil end
  if e.expires and now and now > e.expires then
    cache.entries[key] = nil
    return nil
  end
  return e.tip
end

function L.cachePut(cache, key, tip, plain, now)
  if not cache.entries[key] then
    cache.order[#cache.order + 1] = key
  end
  cache.entries[key] = { tip = tip, expires = plain and ((now or 0) + L.PLAIN_TTL) or nil }
  while #cache.order > L.MAX_CACHE do
    cache.entries[table.remove(cache.order, 1)] = nil
  end
end

-- ---------------------------------------------------------------- formatting
local function trim(n)
  if n == math.floor(n) then
    return string.format('%d', n)
  end
  return (string.format('%.2f', n):gsub('0+$', ''):gsub('%.$', ''))
end

function L.formatValue(v, fmt, signed)
  v = tonumber(v) or 0
  local s
  if fmt == 'sec' then
    s = trim(v) .. 's'
  elseif fmt == 'pct' then
    s = trim(v) .. '%'
  else
    s = trim(v)
  end
  if signed and v > 0 and fmt ~= 'sec' then
    s = '+' .. s
  end
  return s
end

-- split a text into lines of at most n characters at spaces
function L.wrap(text, n)
  n = n or L.WRAP
  local lines, line = {}, ''
  for word in tostring(text or ''):gmatch('%S+') do
    if line == '' then
      line = word
    elseif #line + 1 + #word <= n then
      line = line .. ' ' .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= '' then lines[#lines + 1] = line end
  return lines
end

-- item names come lower case from the item types ("magic sword"): the title starts with a capital
function L.title(name)
  name = tostring(name or '')
  return (name:gsub('^%l', string.upper))
end

function L.rarityColor(r)
  return L.RARITY_COLORS[tonumber(r) or 0]
end

function L.tierColor(t)
  return L.TIER_COLORS[tonumber(t) or 0] or L.COLORS.dim
end

function L.titleColor(tip)
  if tip.unique then return L.COLORS.unique end
  return L.rarityColor(tip.rarity) or L.COLORS.normal
end

-- the lines of a tooltip: {text, color, sep (a gap before), parts = {text, color, text, color, ...}}
-- ctx = {level = the player's level}
function L.lines(tip, ctx)
  ctx = ctx or {}
  local C = L.COLORS
  local out = {}
  local function add(text, color, sep, parts)
    out[#out + 1] = { text = text, color = color or C.text, sep = sep or false, parts = parts }
  end
  local sub = {}
  if tip.unique then
    sub[#sub + 1] = 'Unique'
  elseif tip.rarityName then
    sub[#sub + 1] = tip.rarityName
  end
  if tip.slot then sub[#sub + 1] = tip.slot end
  if #sub > 0 then add(table.concat(sub, ' '), L.titleColor(tip)) end
  if tip.level then
    add(string.format('Item Level %d', tip.level) .. (tip.maxTier and string.format('  (up to T%d)', tip.maxTier) or ''),
      C.dim)
  end

  if tip.quality and (tonumber(tip.quality.q) or 0) > 0 then
    add(string.format('Quality +%d%%  (up to %d%%)', tip.quality.q, tip.quality.cap or 20), C.quality)
  end
  if tip.ruined then
    add('Ruined: no orb can change this item', C.red)
  end

  local first = true
  for _, b in ipairs(tip.base or {}) do
    add(string.format('%s: %s', b.l, L.formatValue(b.v, b.fmt, b.fmt == 'pct' and b.k:find('^protect') ~= nil)),
      C.text, first)
    first = false
  end

  first = true
  local side
  for _, m in ipairs(tip.mods or {}) do
    if m.sd and m.sd ~= side then
      side = m.sd
      local sides = tip.sides
      local head = side == 'p' and 'Prefixes' or 'Suffixes'
      if sides and sides.max then
        local limit = (side == 'p' and sides.mp or sides.ms) or sides.max
        head = string.format('%s %d/%d', head, side == 'p' and (sides.p or 0) or (sides.s or 0), limit)
      end
      add(head, C.dim, first)
      first = false
    end
    local color = (m.pw and C.power) or (m.g == 'chaos' and C.chaos) or (m.g == 'element' and C.element) or C.mod
    local range = ''
    if m.lo and m.hi then
      range = m.lo == m.hi and string.format(' [%d]', m.lo) or string.format(' [%d-%d]', m.lo, m.hi)
    end
    local parts
    if m.tr then
      local tag = string.format('T%d ', m.tr)
      local bound = m.bd and ' [bound]' or ''
      parts = { tag, L.tierColor(m.tr), m.t, color, range, C.dim }
      if m.bd then
        parts[#parts + 1] = bound
        parts[#parts + 1] = C.bound
      end
      add(tag .. m.t .. range .. bound, color, first, parts)
    else
      parts = range ~= '' and { m.t, color, range, C.dim } or nil
      add(m.t .. range, color, first, parts)
    end
    first = false
  end

  local s = tip.sockets
  if s and (tonumber(s.count) or 0) > 0 then
    local filled = 0
    for i = 1, s.count do
      if s.list and s.list[i] and s.list[i].name then filled = filled + 1 end
    end
    add(string.format('Sockets %d/%d', filled, s.count), C.gold, true)
    for i = 1, s.count do
      local g = s.list and s.list[i] or {}
      if g.name then
        add('  ' .. g.name .. (g.text ~= '' and (': ' .. g.text) or ''), g.color or C.gem, false,
          { '  ' .. g.name, g.color or C.gem, (g.text ~= '' and (': ' .. g.text) or ''), C.gem })
      else
        add('  empty socket', C.empty)
      end
    end
  end

  if tip.unique and tip.unique.set then
    local set = tip.unique.set
    add(string.format('Set: %s (%d/%d)', set.name, set.have or 0, set.total or 0), C.unique, true)
  end

  local req = tip.req
  if req then
    local sep = true
    if req.level then
      local low = (tonumber(ctx.level) or 0) < req.level
      add(string.format('Requires level %d', req.level), low and C.red or C.dim, sep)
      sep = false
    end
    if req.magic then
      add(string.format('Requires magic level %d', req.magic), C.dim, sep)
      sep = false
    end
    if req.voc then
      for i, line in ipairs(L.wrap('For ' .. req.voc, L.WRAP)) do
        add(line, C.dim, sep and i == 1)
      end
    end
  end

  if tip.desc then
    for i, line in ipairs(L.wrap(tip.desc, L.WRAP)) do
      add(line, C.dim, i == 1)
    end
  end
  if tip.locked then add('Locked', C.gold, true) end
  -- a store pouch (server pouches.lua): what it is and what it collects
  if tip.store then add(tip.store, C.gold, true) end
  if tip.collects then
    for _, line in ipairs(L.wrap(tip.collects, L.WRAP)) do add(line, C.dim) end
  end
  if tip.weight then
    add(string.format('Weight %s oz', trim(tip.weight)), C.dim, not tip.locked and not tip.store)
  end
  return out
end

-- ---------------------------------------------------------------- compare
-- equipped tooltips to compare with: the ones in the slots the tooltip names, of the same kind (a weapon is not
-- compared with a shield in the other hand), never the hovered item itself
function L.compareWith(tip, equippedBySlot, hoveredKey)
  local out = {}
  if not tip or not tip.cmp then return out end
  for _, slot in ipairs(tip.cmp) do
    local e = equippedBySlot[slot]
    if e and e.kind == tip.kind and (not hoveredKey or e.key ~= hoveredKey) then
      out[#out + 1] = e
    end
  end
  return out
end

-- differences hovered - equipped per number: [{k, l, d, fmt, better}] (d ~= 0), in the hovered item's order, then
-- what only the equipped one has
function L.diff(a, b)
  local rows, seen = {}, {}
  local bv = {}
  for _, s in ipairs((b and b.stats) or {}) do bv[s.k] = s end
  local function push(k, l, d, fmt, low)
    if d ~= 0 then
      local better = (low and d < 0) or (not low and d > 0)
      rows[#rows + 1] = { k = k, l = l, d = d, fmt = fmt, better = better }
    end
  end
  for _, s in ipairs((a and a.stats) or {}) do
    seen[s.k] = true
    local o = bv[s.k]
    push(s.k, s.l, (tonumber(s.v) or 0) - (o and tonumber(o.v) or 0), s.fmt, s.low)
  end
  for _, s in ipairs((b and b.stats) or {}) do
    if not seen[s.k] then
      push(s.k, s.l, -(tonumber(s.v) or 0), s.fmt, s.low)
    end
  end
  return rows
end

function L.diffText(row)
  local d = row.d
  local v = math.abs(d)
  local sign = d > 0 and '+' or '-'
  return string.format('%s%s %s', sign, L.formatValue(v, row.fmt, false), row.l)
end

return L

-- Rich item tooltips, the view logic without client API (tested by tooltiplogic_test.lua): cache keys, what is
-- asked from the server, the lines a tooltip shows and the differences of the Ctrl compare view.
-- The tooltip itself comes from the server (extended opcode 242, server/data/scripts/chaos/item_tooltip_core.lua):
--   {key, id, name, count, kind, slot, rarity, rarityName, level, maxTier, sides = {p, s, max},
--    unique = {name, set = {key, name, have, total, pieces = [{n, eq, low, lv, h}], bonuses = [{n, t, on}]}},
--    base = [{k, l, v, fmt}],
--    quality = {q, cap} (item quality in percent), ruined (an Orb of Ruin ruined it), corrupted (a Void Orb corrupted it),
--    mods = [{k, l, t, v, g, lo, hi, tr, sd, bd, pw}] (a corrupted implicit first, then prefixes; tr = tier 1..8,
--    sd = 'i' (the Void Orb's implicit) / 'p' / 's', bd = bound, pw = a legendary power),
--    sockets = {count, max, list = [{name, text, color}]},
--    veil = {s = 'veiled'} | {s = 'open', n, t, tr, tn, lo, hi, h} (the veiled slot: name, text, veiled tier, range, hook),
--    req = {level, magic, voc}, weight, desc, note, locked, store, collects (a store pouch), stats = [{k, l, v, fmt, low, sc}], cmp = [slot, ...],
--    ds (display scale: the factor of the item's level requirement; flat health / mana / damage / heal numbers are
--    already x ds, and the stats rows marked sc carry them: server display_scale_core.lua DS.itemTip)}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

ItemTooltipLogic = {}
local L = ItemTooltipLogic

L.INVENTORY_X = 0xFFFF
L.MAX_CACHE = 400
L.PLAIN_TTL = 30 -- seconds a tooltip of an item without client attributes is kept
L.WRAP = 44 -- characters per line of the flavour text

L.COLORS = {
  text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', mod = '#9ab8ff', chaos = '#e080d0', element = '#ffa060',
  gem = '#c8e8ff', empty = '#6b6258', power = '#ff9a3c', bound = '#e8b84a', quality = '#7fe0a0', better = '#5ccf5c', worse = '#e03a1e', unique = '#e07b24', red = '#e03a1e',
  corrupted = '#d04040',
  normal = '#e4d8c0',
  -- item sets: the title of a piece, the pieces worn and the bonuses active (dim when not)
  set = '#58c878', setOn = '#7fe0a0', setLow = '#c0805a'
}
-- modifier tiers T1 (lowest) .. T8 (highest)
L.TIER_COLORS = { '#8c8070', '#a89c88', '#c8c8c8', '#5ccf5c', '#4a90ff', '#a35cf0', '#ffd040', '#ff8a40' }
L.RARITY_COLORS = { '#c8c8c8', '#5ccf5c', '#4a90ff', '#a35cf0', '#ffd040', '#ffd040', '#ffd040', '#ffd040', '#ffd040',
  '#c8e8ff', '#c8e8ff', '#c8e8ff', '#c8e8ff', '#c8e8ff', '#c8e8ff' } -- by rarity id: 1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary, 10 Divine (6 .. 9 and 11 .. 15: an old item, the rarity it became)

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

-- an answer is kept only for the item that was asked for. A plain item is named by its slot alone and a container's
-- slots shift when an item goes in at the front, so the server could answer for the neighbour, which was then kept
-- under the hovered item (live test winpkg-35: a Rope showed "Cheese 62", a Training Wand "Gold coin 100").
-- asked = {cid, n} (n: the count of a stackable, else nil); tip = the server's tooltip ({id = client id, count}).
function L.tipMatches(asked, tip)
  if type(asked) ~= 'table' or type(tip) ~= 'table' then return false end
  local cid = tonumber(asked.cid)
  if cid and cid > 0 and tonumber(tip.id) ~= cid then return false end
  local n = tonumber(asked.n)
  if n and n > 0 and (tonumber(tip.count) or 1) ~= n then return false end
  return true
end

-- what a request names besides the position: the client id and, for a stackable, the count (the server matches them)
function L.identity(clientId, count, stackable)
  return { cid = tonumber(clientId) or 0, n = stackable and (tonumber(count) or 1) or nil }
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

-- forget one entry (the next hover or ask fetches it again); true when there was one
function L.cacheDrop(cache, key)
  if not cache.entries[key] then return false end
  cache.entries[key] = nil
  for i, k in ipairs(cache.order) do
    if k == key then
      table.remove(cache.order, i)
      break
    end
  end
  return true
end

-- a tooltip whose numbers change while the item looks the same: counted charges (an exercise weapon in training loses
-- one per hit; the server sends the item again, server/tools/patch_base_events.py step 20, but its key stays the same,
-- and protocol 10.98 carries no charges in the item). Such a tip is asked for again when its slot gets the item again.
function L.liveTip(tip)
  return type(tip) == 'table' and type(tip.charges) == 'table' and not tip.charges.unlimited
    and tonumber(tip.charges.n) ~= nil
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
  elseif fmt == 'est' then
    s = '~' .. L.int(v) -- an estimate (server weapon_dps_core.lua "Estimated DPS")
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
  if tip.unique and tip.unique.set then return L.COLORS.set end
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
  if tip.unique and tip.unique.set then
    sub[#sub + 1] = 'Set'
  elseif tip.unique then
    sub[#sub + 1] = tr('Unique')
  elseif tip.rarityName then
    sub[#sub + 1] = tr(tip.rarityName)
  end
  -- a slot of the form 'Where: What' (the server's quiver: 'Off-hand: Quiver'): the title names what, a line of its
  -- own says where it is worn
  local slotWhat, slotLine = tip.slot, nil
  if type(tip.slot) == 'string' and tip.slot:find(': ', 1, true) then
    slotWhat, slotLine = tip.slot:match(': (.+)$'), tip.slot
  end
  if slotWhat then sub[#sub + 1] = slotWhat end
  if #sub > 0 then add(table.concat(sub, ' '), L.titleColor(tip)) end
  if slotLine then add(slotLine, C.dim) end
  if tip.level then
    add(tr('Item Level %d', tip.level) .. (tip.maxTier and tr('  (up to T%d)', tip.maxTier) or ''),
      C.dim)
  end

  if tip.quality and (tonumber(tip.quality.q) or 0) > 0 then
    add(tr('Quality +%d%%  (up to %d%%)', tip.quality.q, tip.quality.cap or 20), C.quality)
  end
  if tip.ruined then
    add(tr('Ruined: no orb can change this item'), C.red)
  end
  if tip.corrupted then
    add(tr('Corrupted: no orb can change this item'), C.corrupted)
  end

  local first = true
  for _, b in ipairs(tip.base or {}) do
    -- imp: a quiver base's implicit modifier (server chaos_archery_config.lua), signed and in the modifier colour
    add(string.format('%s: %s', b.l, L.formatValue(b.v, b.fmt, b.imp or (b.fmt == 'pct' and b.k:find('^protect') ~= nil))),
      b.imp and C.chaos or C.text, first)
    first = false
  end

  first = true
  local side
  for _, m in ipairs(tip.mods or {}) do
    if m.sd and m.sd ~= side then
      side = m.sd
      local sides = tip.sides
      local head = side == 'p' and 'Prefixes' or 'Suffixes'
      if side == 'i' then
        head = tr('Corrupted implicit')
      elseif sides and sides.max then
        local limit = (side == 'p' and sides.mp or sides.ms) or sides.max
        head = string.format('%s %d/%d', head, side == 'p' and (sides.p or 0) or (sides.s or 0), limit)
      end
      add(head, C.dim, first)
      first = false
    end
    local color = (m.sd == 'i' and C.corrupted) or (m.pw and C.power) or (m.g == 'chaos' and C.chaos)
      or (m.g == 'element' and C.element) or C.mod
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

  -- the veiled slot (server data/lib/chaos_veiled.lua): its own colour, outside the prefixes and suffixes
  for _, row in ipairs(L.veilLines(tip.veil)) do
    add(row.text, row.color, row.sep, row.parts)
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
        add(tr('  empty socket'), C.empty)
      end
    end
  end

  local setBlock = (tip.unique and tip.unique.set) or tip.set -- tip.set: a plain piece of an open set (pair 28)
  if setBlock then
    for _, row in ipairs(L.setLines(setBlock)) do
      add(row.text, row.color, row.sep)
    end
  end

  local req = tip.req
  if req then
    local sep = true
    if req.level then
      local low = (tonumber(ctx.level) or 0) < req.level
      add(tr('Requires level %d', req.level), low and C.red or C.dim, sep)
      sep = false
    end
    if req.magic then
      add(tr('Requires magic level %d', req.magic), C.dim, sep)
      sep = false
    end
    if req.voc then
      for i, line in ipairs(L.wrap('For ' .. req.voc, L.WRAP)) do
        add(line, C.dim, sep and i == 1)
      end
    end
  end

  -- note: a line of its own (a quiver works only while a bow or crossbow is held)
  if tip.note then
    for i, line in ipairs(L.wrap(tip.note, L.WRAP)) do
      add(line, C.gold, i == 1)
    end
  end
  if tip.desc then
    for i, line in ipairs(L.wrap(tip.desc, L.WRAP)) do
      add(line, C.dim, i == 1)
    end
  end
  if tip.locked then add('Locked', C.gold, true) end
  -- a transmog look (server transmog.lua): appearance only, the stats above are the item's own
  if type(tip.look) == 'table' and tip.look.name then add('Appearance: ' .. tostring(tip.look.name), C.mod, not tip.locked) end
  -- a store pouch (server pouches.lua): what it is and what it collects
  if tip.store then add(tip.store, C.gold, true) end
  if tip.collects then
    for _, line in ipairs(L.wrap(tip.collects, L.WRAP)) do add(line, C.dim) end
  end
  -- charges (server item_tooltip_core.lua T.chargeInfo): exercise and training weapons, charged rings and runes
  local chargeText = L.chargesText(tip.charges)
  if chargeText then add(chargeText, C.text, true) end
  -- where it comes from (server itemfinder.lua F.brief): the first sources, the expected effort, a token price
  local srcLines = L.sourceLines(tip.src)
  for i, line in ipairs(srcLines) do
    add(line.text, line.color, i == 1)
  end
  if tip.weight then
    add(string.format('Weight %s oz', trim(tip.weight)), C.dim, #srcLines == 0 and not tip.locked and not tip.store)
  end
  return out
end

-- 1 / p, rounded as a player reads it (1-20 exact, then 5s, 10s, 50s, 100s); the same as the server's
-- goals_core.lua K.oneIn
function L.oneIn(p)
  p = tonumber(p) or 0
  if p <= 0 then return nil end
  local n = 1 / p
  if n < 1.5 then return 1 end
  local step = n < 20 and 1 or n < 200 and 5 or n < 1000 and 10 or n < 10000 and 50 or 100
  return math.max(1, math.floor(n / step + 0.5) * step)
end

-- 12345 -> '12,345'
function L.int(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
end

-- the charges line: {n, max} -> 'Charges: 1,200 of 14,400' / 'Charges: 14,400'; {unlimited} -> 'Charges: unlimited'
-- (live test winpkg-35: a Lasting Exercise Wand showed only its name and weight)
function L.chargesText(ch)
  if type(ch) ~= 'table' then return nil end
  if ch.unlimited then return tr('Charges: unlimited') end
  local n = tonumber(ch.n)
  if not n then return nil end
  local max = tonumber(ch.max)
  if max and max > n then return tr('Charges: %s of %s', L.int(n), L.int(max)) end
  return tr('Charges: %s', L.int(n))
end

-- the sources block of a tooltip: src = {s = [{k, n, v}], e = {p, w, m}, t = token price}; rows {text, color}
function L.sourceLines(src)
  local out = {}
  if type(src) ~= 'table' then return out end
  local C = L.COLORS
  local parts, seen = {}, {}
  for _, s in ipairs(type(src.s) == 'table' and src.s or {}) do
    -- one entry per name ("Drops from: Abyssal Crab (100%), Abyssal Crab (100%)", live test winpkg-35)
    if type(s) == 'table' and s.n and not seen[tostring(s.n)] then
      seen[tostring(s.n)] = true
      parts[#parts + 1] = tostring(s.n) .. (s.v and (' (' .. tostring(s.v) .. ')') or '')
    end
  end
  if #parts > 0 then
    local drop = src.s[1].k == 'monster' or src.s[1].k == 'drop'
    local text = drop and tr('Drops from: %s', table.concat(parts, ', ')) or tr('Sources: %s', table.concat(parts, ', '))
    for _, line in ipairs(L.wrap(text, L.WRAP)) do
      out[#out + 1] = { text = line, color = C.dim }
    end
  end
  local effort
  local e = type(src.e) == 'table' and src.e or nil
  local n = e and L.oneIn(e.p)
  if n then
    local count = L.int(n)
    if e.w == 'legendary' then
      effort = tr('~1 in %s legendary kills', count)
    elseif e.w == 'boss' then
      effort = tr('~1 in %s boss kills', count)
    elseif e.m then
      effort = tr('~1 in %s kills of %s', count, tostring(e.m))
    else
      effort = tr('~1 in %s kills', count)
    end
  end
  local price = tonumber(src.t)
  if effort and price then
    effort = effort .. tr(', or %s Conquest Tokens', L.int(price))
  elseif price then
    effort = tr('Conquest vendor: %s tokens', L.int(price))
  end
  if effort then
    for _, line in ipairs(L.wrap(effort, L.WRAP)) do
      out[#out + 1] = { text = line, color = C.gold }
    end
  end
  return out
end

-- the set block of a set piece (server data/lib/chaos_item_sets.lua S.tooltip): the set and how many of its pieces
-- count now, every piece (worn: bright; worn below its level: rust with the level; not worn: dim), every bonus
-- (active: bright, else dim) with its text wrapped. Rows {text, color, sep}; a server without the lists sends only the
-- name and the counts, which gives the header alone.
function L.setLines(set)
  local C = L.COLORS
  local out = {}
  if type(set) ~= 'table' then return out end
  out[#out + 1] = { text = string.format('Set: %s (%d/%d)', tostring(set.name or '?'), tonumber(set.have) or 0,
    tonumber(set.total) or 0), color = C.set, sep = true }
  if tonumber(set.tiers) then
    out[#out + 1] = { text = tr('Active tier: %d of %d', tonumber(set.tier) or 0, tonumber(set.tiers) or 0),
      color = (tonumber(set.tier) or 0) > 0 and C.setOn or C.dim }
  end
  for _, p in ipairs(type(set.pieces) == 'table' and set.pieces or {}) do
    local text = '  ' .. tostring(p.n or '?')
    if (tonumber(p.h) or 1) > 1 then text = text .. string.format(' (counts %d)', p.h) end
    local color = C.empty
    if p.eq then
      color = C.setOn
    elseif p.low then
      text = text .. string.format(' (level %d)', tonumber(p.lv) or 0)
      color = C.setLow
    end
    out[#out + 1] = { text = text, color = color }
  end
  for i, b in ipairs(type(set.bonuses) == 'table' and set.bonuses or {}) do
    local color = b.on and C.setOn or C.dim
    for j, line in ipairs(L.wrap(string.format('(%d) %s', tonumber(b.n) or 0, tostring(b.t or '')), L.WRAP)) do
      out[#out + 1] = { text = (j > 1 and '    ' or '') .. line, color = color, sep = i == 1 and j == 1 }
    end
  end
  return out
end

-- a piece's tooltip says which pieces the player wears: forget every cached set piece when the equipment changes
-- (the next hover asks again). Returns how many were dropped.
function L.dropSetTips(cache)
  local n = 0
  for key, e in pairs(cache.entries) do
    if type(e.tip) == 'table' and ((type(e.tip.unique) == 'table' and e.tip.unique.set) or type(e.tip.set) == 'table') then
      cache.entries[key] = nil
      n = n + 1
    end
  end
  if n > 0 then
    local order = {}
    for _, key in ipairs(cache.order) do
      if cache.entries[key] then order[#order + 1] = key end
    end
    cache.order = order
  end
  return n
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

-- a stat of the other item in this item's display scale (server display_scale_core.lua DS.itemTip): a row marked sc
-- carries a flat health / mana / damage / heal value x its item's factor ds (the factor of its level requirement), so
-- it is brought to the hovered item's factor before the two are compared. Unmarked rows and tooltips without ds as
-- they are.
function L.toScale(v, from, to)
  v = tonumber(v) or 0
  from, to = tonumber(from) or 1, tonumber(to) or 1
  if from == to or from <= 0 then return v end
  return math.floor(v / from * to + 0.5)
end

-- differences hovered - equipped per number: [{k, l, d, fmt, better}] (d ~= 0), in the hovered item's order, then
-- what only the equipped one has; scaled rows compared in the hovered item's display scale (L.toScale)
function L.diff(a, b)
  local rows, seen = {}, {}
  local bv = {}
  local ads, bds = a and a.ds, b and b.ds
  for _, s in ipairs((b and b.stats) or {}) do
    if s.sc then
      bv[s.k] = { k = s.k, l = s.l, v = L.toScale(s.v, bds, ads), fmt = s.fmt, low = s.low, sc = s.sc }
    else
      bv[s.k] = s
    end
  end
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
      push(s.k, s.l, -(tonumber(bv[s.k].v) or 0), s.fmt, s.low)
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

-- ---------------------------------------------------------------- veiled modifiers
L.COLORS.veiled = '#b48cff'
L.COLORS.veiledText = '#d9c8ff'
-- veiled tiers V1 .. V4
L.VEIL_TIER_COLORS = { '#9a8cc0', '#a98cff', '#c070ff', '#ff70e0' }

-- the rows of a tooltip's veil block: {text, color, sep, parts}
function L.veilLines(veil)
  local C = L.COLORS
  local out = {}
  if type(veil) ~= 'table' then return out end
  if veil.s == 'veiled' then
    out[#out + 1] = { text = 'Veiled modifier', color = C.veiled, sep = true }
    out[#out + 1] = { text = '  Reveal it with an Orb of Unveiling', color = C.dim }
    return out
  end
  if veil.s ~= 'open' then return out end
  out[#out + 1] = { text = 'Veiled', color = C.veiled, sep = true }
  local tag = tostring(veil.tn or ('V' .. tostring(veil.tr or 1))) .. ' '
  local name = tostring(veil.n or '?')
  local range = ''
  if veil.lo and veil.hi then
    range = veil.lo == veil.hi and string.format(' [%d]', veil.lo) or string.format(' [%d-%d]', veil.lo, veil.hi)
  end
  local tierColor = L.VEIL_TIER_COLORS[tonumber(veil.tr) or 0] or C.veiled
  out[#out + 1] = { text = tag .. name .. range, color = C.veiled, parts = { tag, tierColor, name, C.veiled, range, C.dim } }
  for _, line in ipairs(L.wrap(veil.t, L.WRAP)) do
    out[#out + 1] = { text = '  ' .. line, color = C.veiledText }
  end
  return out
end

return L

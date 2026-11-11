-- Rich item tooltips, the view logic without client API (tested by tooltiplogic_test.lua): cache keys, what is
-- asked from the server, the lines a tooltip shows and the differences of the Ctrl compare view.
-- The tooltip itself comes from the server (extended opcode 242, server/data/scripts/chaos/item_tooltip_core.lua):
--   {key, id, name, count, kind, slot, rarity, rarityName, level, maxTier, sides = {p, s, max},
--    unique = {name, set = {key, name, have, total, pieces = [{n, eq, low, lv, h}], bonuses = [{n, t, on}]}},
--    base = [{k, l, v, fmt}],
--    quality = {q, cap} (item quality in percent), ruined (an Orb of Ruin ruined it), corrupted (a Void Orb corrupted it),
--    mods = [{k, l, t, v, g, lo, hi, tr, sd, bd, pw}] (a corrupted implicit first, then prefixes; tr = tier 1..8,
--    sd = 'i' (the Void Orb's implicit) / 'p' / 's', bd = bound, pw = a legendary power),
--    sockets = {count, max, list = [{name, text, color, l, v, l2, v2}]} (l / v: the effect name and its number apart, O479),
--    gem = {rows = [{place, label, value, label2, value2, text}], combine} (a gem item, O479; a client without it shows desc),
--    veil = {s = 'veiled'} | {s = 'open', n, t, tr, tn, lo, hi, h} (the veiled slot: name, text, veiled tier, range, hook),
--    req = {level, magic, voc}, weight, desc, note, locked, store, collects (a store pouch), stats = [{k, l, v, fmt, low, sc}], cmp = [slot, ...],
--    ds (display scale: the factor of the item's level requirement; flat health / mana / damage / heal numbers are
--    already x ds, and the stats rows marked sc carry them: server display_scale_core.lua DS.itemTip)}
-- i18n (client_chaos_locale). The locale module serves the global tr from _G's metatable, where rawget(_G, 'tr') is nil: ask
-- ChaosLocale.tr then, or every row of this module stayed English in pt-BR (O479; the unit tests set a global tr or none).
-- Every module that reads tr with rawget does the same (tools/ci/check_locales.py holds them to it).
local function tr(s, ...)
  local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr)
  if g then return g(s, ...) end
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end

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
  set = '#58c878', setOn = '#7fe0a0', setLow = '#c0805a',
  -- a unique's passive (server T.splitPassive): its name and its rule stand out from the flavour text
  passive = '#ffb340', passiveText = '#f2e6cc',
  -- the Alt help lines (itemhelp.lua, O372)
  help = '#b8b0a0',
  -- the gem block of a gem item (O479, owner 2026-11-11, colour option 3): the header, the place labels (each its own colour),
  -- the effect name, the number, the two hint rows. Only these entries move when the colours change.
  gemHead = '#8c8070', gemWeapon = '#ff9a5c', gemArmour = '#6fb0ff', gemJewel = '#c890ff',
  gemEffect = '#d6c9ae', gemValue = '#7fe0a0', gemHint = '#8c8070'
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

-- a base row's value: a range row ("Attack" of a wand or rod, server item_tooltip_core.lua wandRows, O353) shows its lo-hi
function L.baseValue(b, signed)
  if b.fmt == 'range' and tonumber(b.lo) and tonumber(b.hi) then
    return b.lo == b.hi and L.int(b.lo) or (L.int(b.lo) .. '-' .. L.int(b.hi))
  end
  return L.formatValue(b.v, b.fmt, signed, true)
end

function L.formatValue(v, fmt, signed, rate)
  v = tonumber(v) or 0
  local s
  if fmt == 'sec' then
    s = trim(v) .. 's'
    -- under a second the swings per second say more than the interval does (the cap is 3 per second, server/README.md
    -- "Attack speed cap"): 0.33s (3/s)
    if rate and v > 0 and v < 1 then
      s = s .. ' (' .. trim(math.floor(10 / v + 0.5) / 10) .. '/s)'
    end
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

-- O471: the character cap of a modifier (server item_tooltip_core.lua T.capOf: critical chance 45, critical damage 150,
-- penetration 20): m.cap, and m.over when the wearer's total is above it. '' for a modifier without one
function L.capText(m)
  local cap = tonumber(m and m.cap)
  if not cap then
    return ''
  end
  if m.over then
    return ' ' .. string.format(tr('(over the character cap of %d)'), cap)
  end
  return ' ' .. string.format(tr('(character cap %d)'), cap)
end

function L.tierColor(t)
  return L.TIER_COLORS[tonumber(t) or 0] or L.COLORS.dim
end

function L.titleColor(tip)
  if tip.unique and tip.unique.set then return L.COLORS.set end
  if tip.unique then return L.COLORS.unique end
  return L.rarityColor(tip.rarity) or L.COLORS.normal
end

-- the class row of the server ('Mystic, Necromancer' or 'all classes') in the client's language: the words 'all classes'
-- are translated, the class names stay as they are (O467)
function L.classText(voc)
  if voc == 'all classes' then return tr('all classes') end
  return voc
end

-- the Codex page id of a tip ('unique:8209' or 'set:key', the server's tip.codex), nil when the tip has none or an id of
-- another shape (O467)
function L.codexId(tip)
  local id = type(tip) == 'table' and tip.codex or nil
  if type(id) ~= 'string' then return nil end
  if id:match('^unique:%d+$') or id:match('^set:[%w_%-]+$') then return id end
  return nil
end

-- the kind line of a tooltip: 'Legendary Wand' / 'Unique Quiver' / 'Set Ring' (nil when nothing is known) and the slot
-- line when the slot reads 'Where: What' (the server's quiver: 'Off-hand: Quiver'; the kind line names what, the slot
-- line says where it is worn)
function L.kindText(tip)
  local sub = {}
  if tip.unique and tip.unique.set then
    sub[#sub + 1] = tr('Set')
  elseif tip.unique then
    sub[#sub + 1] = tr('Unique')
  elseif tip.rarityName then
    sub[#sub + 1] = tr(tip.rarityName)
  end
  local slotWhat, slotLine = tip.slot, nil
  if type(tip.slot) == 'string' and tip.slot:find(': ', 1, true) then
    slotWhat, slotLine = tip.slot:match(': (.+)$'), tip.slot
  end
  if slotWhat then sub[#sub + 1] = tr(slotWhat) end -- 'Two-handed sword', 'Dagger' ... (pt-BR in client_chaos_locale)
  return #sub > 0 and table.concat(sub, ' ') or nil, slotLine
end

-- the effect of a socketed gem in the client's language: the server sends the name and the number apart (l, v; a pair adds
-- l2, v2), an older server only the English text
function L.socketText(g)
  if type(g.l) == 'string' and g.l ~= '' and type(g.v) == 'string' then
    local text = tr(g.l) .. ' ' .. g.v
    if type(g.l2) == 'string' and g.l2 ~= '' and type(g.v2) == 'string' then text = text .. ', ' .. tr(g.l2) .. ' ' .. g.v2 end
    return text
  end
  return g.text or ''
end

-- the gem block of a gem item (O479; the server's tip.gem, item_tooltip_core.lua T.gemInfo), instead of the long description:
--   {head = 'SOCKETED IN', rows = [{label, labelColor, text, parts}], hints = [text]}
-- One row per place: the place label in its own colour, the effect name in the text colour, the number in the value colour
-- (parts = {text, color, ...}). A pair effect takes a second row without a label, so the effect texts stay in one column and
-- fit the card. The two hints (a free socket, the combine rule) come after the rows, a Perfect gem has no combine hint.
-- nil for an item without tip.gem (an older server): the description is shown as before.
L.GEM_PLACES = { weapon = { 'Weapon:', 'gemWeapon' }, armour = { 'Armour:', 'gemArmour' }, jewel = { 'Jewellery:', 'gemJewel' } }
function L.gemBlock(tip)
  local g = type(tip) == 'table' and tip.gem or nil
  if type(g) ~= 'table' or type(g.rows) ~= 'table' then return nil end
  local C = L.COLORS
  local rows = {}
  for _, r in ipairs(g.rows) do
    local place = type(r) == 'table' and L.GEM_PLACES[r.place] or nil
    if place and type(r.label) == 'string' and type(r.value) == 'string' then
      local label = tr(place[1])
      local function effect(name, value)
        local n = tr(name) .. ' '
        return { text = n .. value, parts = { n, C.gemEffect, value, C.gemValue } }
      end
      local first = effect(r.label, r.value)
      rows[#rows + 1] = { label = label, labelColor = C[place[2]], text = first.text, parts = first.parts, color = C.gemEffect }
      if type(r.label2) == 'string' and type(r.value2) == 'string' then
        local second = effect(r.label2, r.value2)
        rows[#rows + 1] = { label = '', labelColor = C[place[2]], text = second.text, parts = second.parts, color = C.gemEffect,
          cont = true }
      end
    end
  end
  if #rows == 0 then return nil end
  local hints = { tr('Use it on gear with a free socket.') }
  if g.combine then hints[#hints + 1] = tr('Three of the same make one of the next quality: use the stack, then left-click it.') end
  return { head = L.caps(tr('Socketed in')), rows = rows, hints = hints }
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
  local kindText, slotLine = L.kindText(tip)
  if kindText then add(kindText, L.titleColor(tip)) end
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
    add(string.format('%s: %s', b.l, L.baseValue(b, b.imp or (b.fmt == 'pct' and b.k:find('^protect') ~= nil))),
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
    -- O471: a modifier with a character cap (critical chance and damage, penetration): the cap, and "over" when the wearer's
    -- total is above it (the server sends cap / over; see ChaosItemMods.config.crit and .penetration)
    local capText = L.capText(m)
    local parts
    if m.tr then
      local tag = string.format('T%d ', m.tr)
      local bound = m.bd and ' [bound]' or ''
      parts = { tag, L.tierColor(m.tr), m.t, color, range, C.dim }
      if capText ~= '' then
        parts[#parts + 1] = capText
        parts[#parts + 1] = m.over and C.red or C.dim
      end
      if m.bd then
        parts[#parts + 1] = bound
        parts[#parts + 1] = C.bound
      end
      add(tag .. m.t .. range .. capText .. bound, color, first, parts)
    else
      parts = (range ~= '' or capText ~= '') and { m.t, color, range, C.dim } or nil
      if parts and capText ~= '' then
        parts[#parts + 1] = capText
        parts[#parts + 1] = m.over and C.red or C.dim
      end
      add(m.t .. range .. capText, color, first, parts)
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
    add(tr('Sockets %d/%d', filled, s.count), C.gold, true)
    for i = 1, s.count do
      local g = s.list and s.list[i] or {}
      if g.name then
        local effect = L.socketText(g)
        add('  ' .. g.name .. (effect ~= '' and (': ' .. effect) or ''), g.color or C.gem, false,
          { '  ' .. g.name, g.color or C.gem, (effect ~= '' and (': ' .. effect) or ''), C.gem })
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
      for i, line in ipairs(L.wrap(tr('For %s', L.classText(req.voc)), L.WRAP)) do
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
  -- a unique's passive (owner 2026-11-01, "deixe esse texto especial mais em evidência"): the server sends it as a
  -- block of its own (tip.passive); the flavour text stays dim, the passive's name and rule get lines of their own
  local passive = type(tip.passive) == 'table' and type(tip.passive.name) == 'string' and type(tip.passive.text) == 'string'
    and tip.passive or nil
  local desc = passive and passive.flavor or tip.desc
  local gemBlock = L.gemBlock(tip)
  if gemBlock then
    -- a gem item: its effects one row per place, not the description (no double information)
    add(gemBlock.head, C.gemHead, true)
    for _, row in ipairs(gemBlock.rows) do
      local label = row.label ~= '' and (row.label .. ' ') or ''
      local parts = { label, row.labelColor }
      for _, p in ipairs(row.parts) do parts[#parts + 1] = p end
      add(label .. row.text, row.color, false, parts)
    end
    for _, hint in ipairs(gemBlock.hints) do
      for _, line in ipairs(L.wrap(hint, L.WRAP)) do add(line, C.gemHint) end
    end
  elseif type(desc) == 'string' and desc ~= '' then
    for i, line in ipairs(L.wrap(desc, L.WRAP)) do
      add(line, C.dim, i == 1)
    end
  end
  if passive then
    add(passive.name, C.passive, true)
    for _, line in ipairs(L.wrap(passive.text, L.WRAP)) do
      add(line, C.passiveText)
    end
    -- does the power work for the viewer (server item_tooltip.lua, O467): normal text, or the warning colour when it sleeps
    if type(passive.fit) == 'string' and passive.fit ~= '' then
      for _, line in ipairs(L.wrap(passive.fit, L.WRAP)) do
        add(line, passive.warn and C.red or C.text)
      end
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
    add(tr('Weight %s oz', trim(tip.weight)), C.dim, #srcLines == 0 and not tip.locked and not tip.store)
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

-- the sources block of a tooltip: src = {s = [{k, n, v}], e = {p, w, m}, t = token price, u = used in}; rows
-- {text, color}
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
  local used = L.usedInText(src.u)
  if used then
    for _, line in ipairs(L.wrap(used, L.WRAP)) do
      out[#out + 1] = { text = line, color = C.dim }
    end
  end
  return out
end

-- what a material is for (server itemfinder_core.lua K.brief u = {n = {product names}, m = how many more}):
-- 'Used in: Seraphic Emblem, Seraphic Bleeder +8 more'; nil without products (an older server sends no u)
function L.usedInText(u)
  if type(u) ~= 'table' or type(u.n) ~= 'table' then return nil end
  local names = {}
  for _, n in ipairs(u.n) do
    if type(n) == 'string' and n ~= '' then names[#names + 1] = n end
  end
  if #names == 0 then return nil end
  local list = table.concat(names, ', ')
  local more = math.floor(tonumber(u.m) or 0)
  if more > 0 then list = tr('%s +%d more', list, more) end
  return tr('Used in: %s', list)
end

-- the set block of a set piece (server data/lib/chaos_item_sets.lua S.tooltip): the set and how many of its pieces
-- count now, every piece (worn: bright; worn below its level: rust with the level; not worn: dim), every bonus
-- (active: bright, else dim) with its text wrapped. Rows {text, color, sep}; a server without the lists sends only the
-- name and the counts, which gives the header alone.
function L.setLines(set)
  local C = L.COLORS
  local out = {}
  if type(set) ~= 'table' then return out end
  out[#out + 1] = { text = tr('Set: %s (%d/%d)', tostring(set.name or '?'), tonumber(set.have) or 0,
    tonumber(set.total) or 0), color = C.set, sep = true }
  if tonumber(set.tiers) then
    out[#out + 1] = { text = tr('Active tier: %d of %d', tonumber(set.tier) or 0, tonumber(set.tiers) or 0),
      color = (tonumber(set.tier) or 0) > 0 and C.setOn or C.dim }
  end
  for _, p in ipairs(type(set.pieces) == 'table' and set.pieces or {}) do
    local text = '  ' .. tostring(p.n or '?')
    if (tonumber(p.h) or 1) > 1 then text = text .. tr(' (counts %d)', p.h) end
    local color = C.empty
    if p.eq then
      color = C.setOn
    elseif p.low then
      text = text .. tr(' (level %d)', tonumber(p.lv) or 0)
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
    if type(e.tip) == 'table' and ((type(e.tip.unique) == 'table' and e.tip.unique.set) or type(e.tip.set) == 'table'
        or (type(e.tip.passive) == 'table' and e.tip.passive.fit)) then -- a unique's power line names the worn uniques (O467)
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
    out[#out + 1] = { text = tr('Veiled modifier'), color = C.veiled, sep = true }
    out[#out + 1] = { text = tr('  Reveal it with an Orb of Unveiling'), color = C.dim }
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

-- ---------------------------------------------------------------- the card layout (O422)
-- The tooltip as a card (item_tooltip.lua draws it): head (name, kind, item level, flags), stat tiles and one line of
-- the other base stats, modifier groups (prefixes, suffixes, the veiled slot), extra groups (sockets, set, notes,
-- passive, charges), requirement chips with the source and weight lines. Pure: no widgets, no sizes.
L.SEP = ' - ' -- between the items of the extra stat line and the foot
L.TILE_MAX = 4
L.EXTRA_LINE = 44 -- characters of one extra stat line
L.FOOT_LINE = 50 -- characters of the foot line that may take the weight

-- capitals for the captions (ASCII only: the bytes of an accent stay as they are)
function L.caps(text)
  return (tostring(text or ''):upper())
end

-- which base rows become tiles, in this order: the damage and speed of a weapon, then the protection of the rest
L.TILE_ORDER = { 'dps', 'attack', 'speed', 'range', 'armor', 'defense', 'extradefense', 'hitchance' }

local function tileCaption(key)
  if key == 'dps' then return tr('DPS') end
  if key == 'attack' then return tr('Attack') end
  if key == 'speed' then return tr('Speed') end
  if key == 'range' then return tr('Range') end
  if key == 'armor' then return tr('Armour') end
  if key == 'defense' then return tr('Defense') end
  if key == 'extradefense' then return tr('Extra Defense') end
  if key == 'hitchance' then return tr('Hit Chance') end
  return key
end

L.UNSIGNED = { attack = true, defense = true, extradefense = true, armor = true, range = true, hitchance = true,
  attackspeed = true, yourinterval = true, dps = true } -- plain numbers; the other rows are bonuses and show a sign

-- the base rows split into tiles ({key, caption, value, hero}, at most L.TILE_MAX, DPS the hero) and the rest
-- ({label, value, imp}); returns tiles, rest
function L.statTiles(base)
  local list = type(base) == 'table' and base or {}
  local byKey = {}
  for _, b in ipairs(list) do
    if type(b) == 'table' and b.k and byKey[b.k] == nil then byKey[b.k] = b end
  end
  local speed = byKey.yourinterval or byKey.attackspeed
  local tiles, used = {}, {}
  for _, key in ipairs(L.TILE_ORDER) do
    local b = key == 'speed' and speed or byKey[key]
    if b and #tiles < L.TILE_MAX then
      tiles[#tiles + 1] = { key = key, caption = tileCaption(key), value = L.baseValue(b), hero = key == 'dps' }
      used[b] = true
    end
  end
  local rest = {}
  for _, b in ipairs(list) do
    if type(b) == 'table' and not used[b] then
      local signed = b.imp or not L.UNSIGNED[b.k]
      rest[#rest + 1] = { label = tostring(b.l or b.k or '?'), value = L.baseValue(b, signed), imp = b.imp or false }
    end
  end
  return tiles, rest
end

-- the rest of the base rows as centred lines: each line is parts {text, color, text, color, ...} (labels in the text
-- colour, values green, separators dim), at most L.EXTRA_LINE characters
function L.extraLines(rest)
  local C = L.COLORS
  local lines, parts, len = {}, {}, 0
  for _, r in ipairs(rest or {}) do
    local label, value = r.label .. ' ', r.value
    local need = #label + #value + (len > 0 and #L.SEP or 0)
    if len > 0 and len + need > L.EXTRA_LINE then
      lines[#lines + 1] = parts
      parts, len, need = {}, 0, #label + #value
    end
    if len > 0 then
      parts[#parts + 1] = L.SEP
      parts[#parts + 1] = C.dim
    end
    parts[#parts + 1] = label
    parts[#parts + 1] = C.text
    parts[#parts + 1] = value
    parts[#parts + 1] = C.better
    len = len + need
  end
  if #parts > 0 then lines[#lines + 1] = parts end
  return lines
end

local function rangeText(lo, hi)
  if not lo or not hi then return nil end
  return lo == hi and trim(lo) or (trim(lo) .. '-' .. trim(hi))
end

-- the modifier groups: [{caption, capColor, rows}], rows {kind = 'mod', tag, top, tagColor, text, color, range, parts}
-- (top: the best tier of the item level, the green tag; parts: the text with a gold [bound] after it)
function L.modGroups(tip)
  local C = L.COLORS
  local groups, group, side = {}, nil, nil
  for _, m in ipairs(tip.mods or {}) do
    if not group or m.sd ~= side then
      side = m.sd
      local caption
      if side == 'i' then
        caption = L.caps(tr('Corrupted implicit'))
      elseif side then
        local head = L.caps(side == 'p' and tr('Prefixes') or tr('Suffixes'))
        local sides = tip.sides
        if sides and sides.max then
          local limit = (side == 'p' and sides.mp or sides.ms) or sides.max
          head = string.format('%s %d/%d', head, side == 'p' and (sides.p or 0) or (sides.s or 0), limit)
        end
        caption = head
      end
      group = { caption = caption, rows = {} }
      groups[#groups + 1] = group
    end
    local color = (m.sd == 'i' and C.corrupted) or (m.pw and C.power) or (m.g == 'chaos' and C.chaos)
      or (m.g == 'element' and C.element) or C.mod
    local row = { kind = 'mod', text = tostring(m.t or ''), color = color, range = rangeText(m.lo, m.hi) }
    local capText = L.capText(m)
    if capText ~= '' then
      -- the cap rides after the text in its own colour (red when the wearer is over it)
      row.parts = { row.text, color, capText, m.over and C.red or C.dim }
    end
    if m.tr then
      row.tag = 'T' .. trim(m.tr)
      row.top = tonumber(tip.maxTier) ~= nil and tonumber(m.tr) == tonumber(tip.maxTier)
    end
    if m.bd then
      row.parts = row.parts or { row.text, color }
      row.parts[#row.parts + 1] = ' [bound]'
      row.parts[#row.parts + 1] = C.bound
    end
    group.rows[#group.rows + 1] = row
  end
  -- the veiled slot (server data/lib/chaos_veiled.lua): its own group, in its colour
  local veil = tip.veil
  if type(veil) == 'table' then
    if veil.s == 'veiled' then
      groups[#groups + 1] = { caption = L.caps(tr('Veiled modifier')), capColor = C.veiled, rows = {
        { kind = 'text', text = (tr('  Reveal it with an Orb of Unveiling'):gsub('^%s+', '')), color = C.dim } } }
    elseif veil.s == 'open' then
      local rows = { { kind = 'mod', tag = tostring(veil.tn or ('V' .. tostring(veil.tr or 1))),
        tagColor = L.VEIL_TIER_COLORS[tonumber(veil.tr) or 0] or C.veiled, text = tostring(veil.n or '?'),
        color = C.veiled, range = rangeText(veil.lo, veil.hi) } }
      for _, line in ipairs(L.wrap(veil.t, L.WRAP)) do
        rows[#rows + 1] = { kind = 'text', text = line, color = C.veiledText }
      end
      groups[#groups + 1] = { caption = L.caps(tr('Veiled')), capColor = C.veiled, rows = rows }
    end
  end
  return groups
end

local function textRows(lines, color)
  local rows = {}
  for _, line in ipairs(lines) do rows[#rows + 1] = { kind = 'text', text = line, color = color } end
  return rows
end

-- the extra groups: sockets, the set, the note, the flavour, a unique's passive, then locked / appearance / store /
-- charges; [{caption, capColor, rows}]
function L.extraGroups(tip)
  local C = L.COLORS
  local groups = {}
  local function add(caption, capColor, rows)
    if #rows > 0 or caption then groups[#groups + 1] = { caption = caption, capColor = capColor, rows = rows } end
  end
  -- a gem item: the framed box (header and one row per place), then the two hints outside it (O479)
  local gemBlock = L.gemBlock(tip)
  if gemBlock then
    groups[#groups + 1] = { kind = 'gembox', head = gemBlock.head, headColor = C.gemHead, rows = gemBlock.rows }
    local hintRows = {}
    for _, hint in ipairs(gemBlock.hints) do
      for _, row in ipairs(textRows(L.wrap(hint, L.WRAP), C.gemHint)) do hintRows[#hintRows + 1] = row end
    end
    add(nil, nil, hintRows)
  end
  local s = tip.sockets
  if s and (tonumber(s.count) or 0) > 0 then
    local filled, rows = 0, {}
    for i = 1, s.count do
      local g = s.list and s.list[i] or {}
      if g.name then
        filled = filled + 1
        local effect = L.socketText(g)
        local extra = effect ~= '' and (': ' .. effect) or ''
        rows[#rows + 1] = { kind = 'text', text = g.name .. extra, color = g.color or C.gem,
          parts = { g.name, g.color or C.gem, extra, C.gem } }
      else
        rows[#rows + 1] = { kind = 'text', text = (tr('  empty socket'):gsub('^%s+', '')), color = C.empty }
      end
    end
    add(L.caps(tr('Sockets %d/%d', filled, s.count)), C.gold, rows)
  end
  local setBlock = (tip.unique and tip.unique.set) or tip.set -- tip.set: a plain piece of an open set (pair 28)
  if setBlock then
    local setRows = L.setLines(setBlock)
    local rows = {}
    for i = 2, #setRows do
      rows[#rows + 1] = { kind = 'text', text = (setRows[i].text:gsub('^%s+', '')), color = setRows[i].color }
    end
    add(setRows[1].text, C.set, rows)
  end
  if tip.note then add(nil, nil, textRows(L.wrap(tip.note, L.WRAP), C.gold)) end
  local passive = type(tip.passive) == 'table' and type(tip.passive.name) == 'string' and type(tip.passive.text) == 'string'
    and tip.passive or nil
  local desc = passive and passive.flavor or tip.desc
  if type(desc) == 'string' and desc ~= '' and not L.supportInfo(desc) and not gemBlock then
    add(nil, nil, textRows(L.wrap(desc, L.WRAP), C.dim))
  end
  if passive then
    local rows = textRows(L.wrap(passive.text, L.WRAP), C.passiveText)
    if type(passive.fit) == 'string' and passive.fit ~= '' then -- works for the viewer or sleeps (O467)
      for _, row in ipairs(textRows(L.wrap(passive.fit, L.WRAP), passive.warn and C.red or C.text)) do rows[#rows + 1] = row end
    end
    add(passive.name, C.passive, rows)
  end
  local misc = {}
  if tip.locked then misc[#misc + 1] = { kind = 'text', text = 'Locked', color = C.gold } end
  if type(tip.look) == 'table' and tip.look.name then
    misc[#misc + 1] = { kind = 'text', text = 'Appearance: ' .. tostring(tip.look.name), color = C.mod }
  end
  if tip.store then misc[#misc + 1] = { kind = 'text', text = tostring(tip.store), color = C.gold } end
  if tip.collects then
    for _, row in ipairs(textRows(L.wrap(tip.collects, L.WRAP), C.dim)) do misc[#misc + 1] = row end
  end
  local chargeText = L.chargesText(tip.charges)
  if chargeText then misc[#misc + 1] = { kind = 'text', text = chargeText, color = C.text } end
  add(nil, nil, misc)
  return groups
end

-- the requirement chips: [{text, color, low}] (level in rust red while the player is below it, magic level, one chip
-- per class)
function L.reqChips(req, ctx)
  local C = L.COLORS
  local chips = {}
  if type(req) ~= 'table' then return chips end
  if req.level then
    local low = (tonumber((ctx or {}).level) or 0) < req.level
    chips[#chips + 1] = { text = tr('Level %d', req.level), color = low and C.red or C.text, low = low }
  end
  if req.magic then chips[#chips + 1] = { text = tr('Magic level %d', req.magic), color = C.text } end
  if type(req.voc) == 'string' then
    for name in req.voc:gmatch('[^,]+') do
      name = name:gsub('^%s+', ''):gsub('%s+$', '')
      if name ~= '' then chips[#chips + 1] = { text = L.classText(name), color = C.text } end
    end
  end
  return chips
end

-- the foot: the sources lines (dim, the effort in gold) and the weight; the weight joins the last dim line when it
-- fits ("Drops from: Axebringer Fiend - 24.9 oz"); rows {text, color}
function L.footLines(tip, hints)
  local C = L.COLORS
  local rows = {}
  for _, h in ipairs(hints or {}) do rows[#rows + 1] = { text = h, color = C.dim } end
  for _, line in ipairs(L.sourceLines(tip.src)) do rows[#rows + 1] = { text = line.text, color = line.color } end
  if tip.weight then
    local w = tr('Weight %s oz', trim(tip.weight))
    local last = rows[#rows]
    if last and last.color == C.dim and #last.text + #L.SEP + #w <= L.FOOT_LINE then
      last.text = last.text .. L.SEP .. w
    else
      rows[#rows + 1] = { text = w, color = C.dim }
    end
  end
  return rows
end

-- a spell support rune (server data/lib/chaos_supports.lua S.description): "A support rune for a spell socket: mana cost
-- -9%, refunded after the cast. Fits single target, area, healing, buff / utility spells. Three of them combine into
-- one of the next level: ... (!supports)". Returns {effect, fits = [kinds], combine, command} or nil for any other text
-- (also a translated one: the card then shows the description as it is).
function L.supportInfo(desc)
  if type(desc) ~= 'string' then return nil end
  local effect, fits, rest = desc:match('^A support rune for a spell socket: (.-)%.%s+Fits (.-) spells%.(.*)$')
  if not effect then return nil end
  local kinds = {}
  for k in fits:gmatch('[^,]+') do
    k = k:gsub('^%s+', ''):gsub('%s+$', '')
    if k ~= '' then kinds[#kinds + 1] = k end
  end
  return { effect = L.title(effect), fits = kinds, combine = rest:find('combine', 1, true) ~= nil,
    command = rest:find('!supports', 1, true) ~= nil }
end

-- Ctrl compares only wearable gear: an item the server marks as equipment (cmp slots) that has numbers to compare (base
-- stats or modifiers). A rune, potion, gem or material never shows "Hold Ctrl to compare".
function L.comparable(tip)
  return type(tip) == 'table' and type(tip.cmp) == 'table' and #tip.cmp > 0 and tip.kind ~= nil
    and type(tip.stats) == 'table' and #tip.stats > 0
end

-- the whole card of a tip. ctx = {level = the player's level}
-- {title, titleColor, kind (caps), kindColor, level (the dim line), slotLine, flags = [{text, color}],
--  stats = {tiles, extra = [parts]} | nil, mods = [group] | nil, extras = [group] | nil, chips = [chip], foot = [row]}
function L.card(tip, ctx)
  local C = L.COLORS
  local card = { title = L.title(tip.name), titleColor = L.titleColor(tip), flags = {}, chips = {}, foot = {} }
  local kindText, slotLine = L.kindText(tip)
  card.kind = kindText and L.caps(kindText) or nil
  if L.supportInfo(tip.desc) then
    card.kind = L.caps((kindText and (kindText .. ' ') or '') .. tr('Support rune'))
  end
  card.kindColor = card.titleColor
  card.slotLine = slotLine
  if tip.level then
    card.level = tr('Item Level %d', tip.level) .. (tip.maxTier and (L.SEP .. tr('up to T%d', tip.maxTier)) or '')
  end
  if tip.quality and (tonumber(tip.quality.q) or 0) > 0 then
    card.flags[#card.flags + 1] = { text = tr('Quality +%d%%  (up to %d%%)', tip.quality.q, tip.quality.cap or 20),
      color = C.quality }
  end
  if tip.ruined then card.flags[#card.flags + 1] = { text = tr('Ruined: no orb can change this item'), color = C.red } end
  if tip.corrupted then
    card.flags[#card.flags + 1] = { text = tr('Corrupted: no orb can change this item'), color = C.corrupted }
  end
  local tiles, rest = L.statTiles(tip.base)
  local extra = L.extraLines(rest)
  if #tiles > 0 or #extra > 0 then card.stats = { tiles = tiles, extra = extra } end
  local mods = L.modGroups(tip)
  if #mods > 0 then card.mods = mods end
  local extras = L.extraGroups(tip)
  if #extras > 0 then card.extras = extras end
  card.chips = L.reqChips(tip.req, ctx)
  local rune = L.supportInfo(tip.desc)
  local hints
  if rune then
    -- a spell support rune: the effect stands out as a wide tile, the spell kinds are chips, the rules are dim lines
    card.stats = card.stats or { tiles = {}, extra = {} }
    card.stats.effect = { text = rune.effect, color = C.gold }
    card.fitCaption = L.caps(tr('Fits spells'))
    card.fitChips = {}
    for _, f in ipairs(rune.fits) do card.fitChips[#card.fitChips + 1] = { text = f, color = C.text } end
    hints = {}
    if rune.combine then hints[#hints + 1] = tr('Three combine into one of the next level.') end
    if rune.command then hints[#hints + 1] = tr('Open the spell supports with !supports.') end
  end
  card.foot = L.footLines(tip, hints)
  card.comparable = L.comparable(tip)
  return card
end

-- pixel-measured wrap: words of text into lines no wider than maxw; measure(text) -> pixels (the view passes a label)
function L.wrapPx(text, maxw, measure)
  local lines, line = {}, ''
  for word in tostring(text or ''):gmatch('%S+') do
    local try = line == '' and word or (line .. ' ' .. word)
    if line ~= '' and measure(try) > maxw then
      lines[#lines + 1] = line
      line = word
    else
      line = try
    end
  end
  if line ~= '' then lines[#lines + 1] = line end
  return lines
end

-- chips laid out in rows: widths[i] = the pixel width of chip i; returns [[index, ...], ...] (rows of at most maxw)
function L.chipRows(widths, gap, maxw)
  local rows, row, x = {}, {}, 0
  for i, w in ipairs(widths) do
    if #row > 0 and x + gap + w > maxw then
      rows[#rows + 1] = row
      row, x = {}, 0
    end
    x = x + (#row > 0 and gap or 0) + w
    row[#row + 1] = i
  end
  if #row > 0 then rows[#rows + 1] = row end
  return rows
end


return L

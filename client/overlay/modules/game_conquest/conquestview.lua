-- The Conquest vendor window texts and rules (pure, no UI calls): shared by conquest.lua and conquestview_test.lua.
-- `s` is the server's state (server data/scripts/chaos/conquest.lua X.state):
--   bal, level, pz, band                      tokens, the character's level, in a protection zone (or at the vendor),
--                                             the level band (items up to level + band are on sale)
--   offers = {{k, id, c, n, g, l, p, s, set, ok, why}}  key, server id, client id, name, group, level, price, slot, set
--                                             name, on sale for this character, why not
--   groups = {{g, n}}                         the offer groups and their names
--   pity = {{g, n, m, x}}                     bad-luck protection per group: misses in a row, the chance multiplier
--   today = {{k, n, got, cap}}                tokens earned today per source and its daily limit
--   cinder = {omenKey, attune, shard, convert = {shards, relics, fee}, omens = {{k, n}}, ascended = {{k, n}},
--             shards = {[kind] = n}, relics = {[kind] = n}, hasKey}
--   refine = {{slot, n, c, r, rn, to, p, ok, why}}, refineMax
-- The rules here mirror the server's for the buttons only; the server decides.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

ConquestView = ConquestView or {}
local V = ConquestView

V.COLORS = { gold = '#e8b84a', text = '#d8ccb4', dim = '#8c8070', good = '#8fd16a', bad = '#e07060', locked = '#6a6058',
  unique = '#ff9a40', set = '#58c878' }

-- the tabs: offers of these groups, or a page of its own
V.TABS = {
  { id = 'uniques', text = 'Uniques', groups = { monster = true, boss = true } },
  { id = 'sets', text = 'Set Pieces', groups = { set = true } },
  { id = 'chase', text = 'Raid & Ascended', tip = 'Raid and Ascended', groups = { raid = true, ascended = true } },
  { id = 'cinder', text = 'Cinderheart' },
  { id = 'refine', text = 'Refine' },
  { id = 'progress', text = 'Progress' },
}

local function num(v) local n = tonumber(v) if not n or n ~= n then return 0 end return n end
local function list(v) return type(v) == 'table' and v or {} end

function V.clientId(v)
  v = tonumber(v)
  if not v or v ~= v or v < 1 or v > 65535 or v ~= math.floor(v) then return 0 end
  return v
end

function V.fmtNum(n)
  n = math.floor(num(n))
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. out
end

function V.tab(id)
  for _, t in ipairs(V.TABS) do
    if t.id == id then return t end
  end
  return V.TABS[1]
end

function V.header(s)
  if type(s) ~= 'table' then return tr('Loading...') end
  return tr('Conquest Tokens: %s. Items up to level %d (your level + %d) and every item you have seen are on sale.',
    V.fmtNum(s.bal), num(s.level) + num(s.band), num(s.band))
end

function V.placeText(s)
  if type(s) ~= 'table' then return '', V.COLORS.dim end
  if s.pz then return tr('You may buy here.'), V.COLORS.good end
  return tr('Buy from a protection zone or next to Iselde Varrow.'), V.COLORS.bad
end

local function groupName(s, g)
  for _, e in ipairs(list(s.groups)) do
    if type(e) == 'table' and e.g == g then return tostring(e.n or g) end
  end
  return tostring(g or '')
end

-- one generic row: {key, clientId, name, sub, priceText, priceColor, canBuy, buyText, tip, color}
local function row(s, key, clientId, name, sub, price, ok, why, color)
  local afford = num(s.bal) >= num(price)
  local can = ok == true and afford and s.pz == true
  local tip = why and tostring(why) or (not afford and price and tr('You need %s Conquest Tokens.', V.fmtNum(price)))
    or (not s.pz and tr('Buy from a protection zone or next to Iselde Varrow.')) or ''
  return { key = key, clientId = V.clientId(clientId), name = tostring(name or ''), sub = sub or '',
    priceText = price and tr('%s tokens', V.fmtNum(price)) or '', priceColor = (ok and afford) and V.COLORS.gold or V.COLORS.bad,
    canBuy = can, buyText = tr('Buy'), tip = tip, color = color or V.COLORS.text, locked = ok ~= true }
end

-- the rows of a tab
function V.rows(s, tabId)
  local out = {}
  if type(s) ~= 'table' then return out end
  local t = V.tab(tabId)
  if t.groups then
    for _, o in ipairs(list(s.offers)) do
      if type(o) == 'table' and t.groups[o.g] then
        local sub = tr('%s, level %d', groupName(s, o.g), num(o.l))
        if o.set then sub = sub .. ' - ' .. tostring(o.set) end
        out[#out + 1] = row(s, o.k, o.c, o.n, sub, num(o.p), o.ok == true, o.why,
          o.ok == true and (o.g == 'set' and V.COLORS.set or V.COLORS.unique) or V.COLORS.locked)
      end
    end
  elseif t.id == 'cinder' then
    local c = type(s.cinder) == 'table' and s.cinder or {}
    for _, k in ipairs(list(c.omens)) do
      if type(k) == 'table' then
        out[#out + 1] = row(s, 'omen:' .. tostring(k.k), 0, tr('Omen Key: %s', tostring(k.n)), tr('An Omen Key of this kind'),
          num(c.omenKey), true, nil, V.COLORS.unique)
        out[#out + 1] = row(s, 'attune:' .. tostring(k.k), 0, tr('Attune your Omen Key: %s', tostring(k.n)),
          tr('The Omen Key you carry takes this kind'), num(c.attune), c.hasKey == true,
          c.hasKey ~= true and tr('Carry an Omen Key to attune it.') or nil, V.COLORS.text)
      end
    end
    local conv = type(c.convert) == 'table' and c.convert or {}
    local shards, relics = type(c.shards) == 'table' and c.shards or {}, type(c.relics) == 'table' and c.relics or {}
    for _, k in ipairs(list(c.ascended)) do
      if type(k) == 'table' then
        out[#out + 1] = row(s, 'shard:' .. tostring(k.k), 0, tr('Ascended Shard: %s', tostring(k.n)),
          tr('You carry %d', num(shards[k.k])), num(c.shard), true, nil, V.COLORS.unique)
      end
    end
    for _, from in ipairs(list(c.ascended)) do
      for _, to in ipairs(list(c.ascended)) do
        if type(from) == 'table' and type(to) == 'table' and from.k ~= to.k then
          local ns, nr = num(conv.shards), num(conv.relics)
          out[#out + 1] = row(s, 'conv:shards:' .. tostring(from.k) .. ':' .. tostring(to.k), 0,
            tr('%d %s shards into 1 %s shard', ns, tostring(from.n), tostring(to.n)),
            tr('You carry %d', num(shards[from.k])), num(conv.fee), num(shards[from.k]) >= ns and ns > 0,
            num(shards[from.k]) < ns and tr('You do not carry enough of that kind to convert.') or nil, V.COLORS.text)
          out[#out + 1] = row(s, 'conv:relics:' .. tostring(from.k) .. ':' .. tostring(to.k), 0,
            tr('%d %s relics into 1 %s relic', nr, tostring(from.n), tostring(to.n)),
            tr('You carry %d', num(relics[from.k])), num(conv.fee), num(relics[from.k]) >= nr and nr > 0,
            num(relics[from.k]) < nr and tr('You do not carry enough of that kind to convert.') or nil, V.COLORS.text)
        end
      end
    end
  elseif t.id == 'refine' then
    for _, r in ipairs(list(s.refine)) do
      if type(r) == 'table' then
        out[#out + 1] = row(s, 'refine:' .. math.floor(num(r.slot)), r.c, r.n,
          tr('%s to %s: keeps every modifier, adds one', tostring(r.rn or ''), tostring(r.to or '')),
          r.p and num(r.p) or nil, r.ok == true, r.why, V.COLORS.text)
      end
    end
  end
  return out
end

-- the Progress page: lines of text
function V.progressLines(s)
  local out = {}
  if type(s) ~= 'table' then return out end
  out[#out + 1] = tr('Bad-luck protection: every miss raises your next chance; a drop starts the count again.')
  for _, p in ipairs(list(s.pity)) do
    if type(p) == 'table' then
      out[#out + 1] = tr('%s: %d misses in a row, chance x%.2f', tostring(p.n or p.g), num(p.m), num(p.x))
    end
  end
  out[#out + 1] = ''
  out[#out + 1] = tr('Tokens earned today (the limit resets at midnight):')
  for _, t in ipairs(list(s.today)) do
    if type(t) == 'table' then
      out[#out + 1] = tr('%s: %d of %d', tostring(t.n or t.k), num(t.got), num(t.cap))
    end
  end
  return out
end

function V.emptyText(tabId)
  if tabId == 'refine' then
    return tr('Wear an item with a rarity to refine it (it rises one rarity, keeps its modifiers and gains one).')
  end
  return tr('Nothing here yet.')
end

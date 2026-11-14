-- Pure helpers of the store's new layout (O556): the side rail, the chips of a group, the home page, the offer card
-- states, the details pane plan and the filter of the search results. No client API; shopview_test.lua runs it under
-- LuaJIT and Lua 5.3. The server's protocol is unchanged: the categories (with `parent`, `size`, `endsIn`), the groups
-- and the pages are what shop.lua of the server sends; everything here is read from them.
ShopView = {}
local V = ShopView

V.HOME = 'home' -- the key of the rail entry of the home page

-- ---------------------------------------------------------------- the side rail
-- The rail has one entry per top node of the tree (ShopTree.build): a parent (Cosmetics, Consumables ...) is one entry,
-- its subcategories become the chips inside the page; a top category is an entry of its own. `Home` stands first when
-- the home page has something to show (V.homeSections).
-- -> {{key, kind = 'home' | 'group' | 'leaf', name, size, data, index (leaf), endsIn (leaf)}}
function V.rail(nodes, withHome)
  local out = {}
  if withHome then out[#out + 1] = { key = V.HOME, kind = 'home', name = 'Home' } end
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'group' then
      out[#out + 1] = { key = 'g:' .. n.name, kind = 'group', name = n.name, size = n.size, data = n.data }
    else
      out[#out + 1] = { key = 'c:' .. tostring(n.index), kind = 'leaf', name = n.name, size = n.size, data = n.data,
        index = n.index, endsIn = tonumber(n.data and n.data.endsIn) }
    end
  end
  return out
end

-- the key of the rail entry that holds category `index` (its group's, or its own); nil when unknown
function V.railKeyOf(nodes, index)
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'leaf' and n.index == index then return 'c:' .. tostring(index) end
    for _, c in ipairs(n.children or {}) do
      if c.index == index then return 'g:' .. n.name end
    end
  end
  return nil
end

-- the entry of a rail key, or nil
function V.entry(rail, key)
  for _, e in ipairs(rail or {}) do
    if e.key == key then return e end
  end
  return nil
end

-- the category a rail entry opens: a leaf's own, a group's first subcategory (or `keep` when it is inside the group)
function V.indexFor(nodes, entry, keep)
  if not entry then return nil end
  if entry.kind == 'leaf' then return entry.index end
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'group' and n.name == entry.name then
      for _, c in ipairs(n.children) do
        if c.index == keep then return keep end
      end
      return n.children[1] and n.children[1].index or nil
    end
  end
  return nil
end

-- ---------------------------------------------------------------- the chips of a group
-- the subcategories of a group as chips: {index, name, size, text}; a top category has none. `maxChars` is what fits
-- a chip: "Wings (21)", the name alone clipped when too long
function V.chips(nodes, groupName, maxChars)
  local out = {}
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'group' and n.name == groupName then
      for _, c in ipairs(n.children) do
        out[#out + 1] = { index = c.index, name = c.name, size = c.size, text = V.chipText(c.name, c.size, maxChars) }
      end
    end
  end
  return out
end

-- "Wings (21)", or the name alone clipped to maxChars when the count does not fit
function V.chipText(name, size, maxChars)
  name = tostring(name or '')
  local text = tonumber(size) and string.format('%s (%d)', name, tonumber(size)) or name
  if not maxChars or #text <= maxChars then return text end
  return V.clip(name, maxChars)
end

-- a text cut to `max` characters with "..." (never longer than max); the text itself when it fits
function V.clip(text, max)
  text = tostring(text or '')
  max = tonumber(max) or 0
  if #text <= max then return text end
  if max <= 3 then return text:sub(1, math.max(0, max)) end
  -- never cut inside a UTF-8 sequence
  local cut = max - 3
  while cut > 0 do
    local b = text:byte(cut + 1)
    if not b or b < 0x80 or b >= 0xC0 then break end
    cut = cut - 1
  end
  return (text:sub(1, cut):gsub('%s+$', '')) .. '...'
end

-- ---------------------------------------------------------------- the home page
-- Which categories the home page shows, in this order: the weekly rotation (the category the server gives `endsIn`:
-- the highlighted strip with the timer), the starter packs (while one is for sale), the bundles. Each is
-- {key = 'weekly' | 'starter' | 'bundles', index, name, size, endsIn}. Only top categories count. No server data says
-- what is popular, so the home page is these three and nothing guessed.
function V.homeSections(nodes)
  local found = {}
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'leaf' then
      local lname = n.name:lower()
      local ends = tonumber(n.data and n.data.endsIn)
      if ends and not found.weekly then
        found.weekly = n
      elseif lname == 'starter' and not found.starter then
        found.starter = n
      elseif lname == 'bundles' and not found.bundles then
        found.bundles = n
      end
    end
  end
  local out = {}
  for _, key in ipairs({ 'weekly', 'starter', 'bundles' }) do
    local n = found[key]
    if n then
      out[#out + 1] = { key = key, index = n.index, name = n.name, size = n.size, endsIn = tonumber(n.data and n.data.endsIn) }
    end
  end
  return out
end

-- how many cards a home section shows: the weekly strip all (up to 2 rows), the others one row
function V.homeLimit(key, columns)
  columns = math.max(1, tonumber(columns) or 1)
  if key == 'weekly' then return columns * 2 end
  return columns
end

-- the cards of a section: the first `limit` offers of its page, and how many more the category holds
-- -> offers, more (the count of the rest, 0 when none; the category size when it is known)
function V.homePick(offers, limit, size)
  local out = {}
  for i, o in ipairs(offers or {}) do
    if i > limit then break end
    out[#out + 1] = o
  end
  local total = tonumber(size) or #(offers or {})
  return out, math.max(0, total - #out)
end

-- columns of a grid of cells `cell` wide with `gap` between, in `width` pixels (at least 1)
function V.columns(width, cell, gap)
  width, cell, gap = tonumber(width) or 0, tonumber(cell) or 1, tonumber(gap) or 0
  return math.max(1, math.floor((width + gap) / (cell + gap)))
end

-- the height of a grid of `count` cards in `columns` columns
function V.gridHeight(count, columns, cellH, gap)
  if count <= 0 then return 0 end
  local rows = math.ceil(count / math.max(1, columns))
  return rows * cellH + (rows - 1) * gap
end

-- ---------------------------------------------------------------- the offer cards
-- the kind of a tag the server sends: 'new', 'sale' ("Sale -20%", "Launch sale -20%"), 'featured' or 'other'
function V.tagKind(tag)
  local t = tostring(tag or ''):lower()
  if t == 'new' then return 'new' end
  if t == 'featured' then return 'featured' end
  if t:find('%-%d+%%') or t:find('sale', 1, true) then return 'sale' end
  return 'other'
end

-- the percentage of a sale tag ("Sale -20%" -> 20), nil without one
function V.salePercent(tags)
  for _, t in ipairs(type(tags) == 'table' and tags or {}) do
    if V.tagKind(t) == 'sale' then
      local p = tostring(t):match('%-(%d+)%%')
      if p then return tonumber(p) end
    end
  end
  return nil
end

-- a tag as it is read: New, Featured, "Launch sale -20%" (the name through `translate`, the percentage kept), or any
-- other tag through `translate`
function V.tagLabel(tag, translate)
  translate = translate or function(k) return k end
  local kind = V.tagKind(tag)
  if kind == 'new' then return translate('New') end
  if kind == 'featured' then return translate('Featured') end
  local name, pct = tostring(tag or ''):match('^(.-)%s*%-(%d+)%%$')
  if name then
    if name == '' then name = 'Sale' end
    return translate(name) .. ' -' .. pct .. '%'
  end
  return translate(tostring(tag or ''))
end

-- what a card shows of an offer and the balance:
--   owned       the server says so (the card is dimmed, Buy off)
--   affordable  the balance covers the price (unknown balance counts as yes)
--   missing     coins short (0 when affordable)
--   badge       the chip: 'owned' | 'sale' | 'new' | 'featured' | 'other' | nil, badgeText for sale ("-20%") and other
--   priceKind   'owned' | 'poor' | 'sale' | 'normal'
function V.cardState(data, points)
  data = type(data) == 'table' and data or {}
  local cost = tonumber(data.cost)
  local balance = tonumber(points)
  local owned = data.owned == true
  local affordable = true
  local missing = 0
  if cost and balance and cost > balance then affordable = false; missing = cost - balance end
  local kinds, other = {}, nil
  for _, t in ipairs(type(data.tags) == 'table' and data.tags or {}) do
    if type(t) == 'string' then
      local k = V.tagKind(t)
      kinds[k] = true
      if k == 'other' and not other then other = t end
    end
  end
  local oldCost = tonumber(data.oldCost)
  local onSale = oldCost ~= nil and cost ~= nil and oldCost > cost
  local pct = V.salePercent(data.tags)
  if not pct and onSale and oldCost > 0 then pct = math.floor((oldCost - cost) * 100 / oldCost + 0.5) end
  local badge, badgeText
  if owned then badge = 'owned'
  elseif onSale or kinds.sale then
    badge = 'sale'
    badgeText = pct and ('-' .. pct .. '%') or nil
  elseif kinds.new then badge = 'new'
  elseif kinds.featured then badge = 'featured'
  elseif other then badge, badgeText = 'other', other end
  local priceKind = 'normal'
  if owned then priceKind = 'owned'
  elseif not affordable then priceKind = 'poor'
  elseif onSale then priceKind = 'sale' end
  return { owned = owned, affordable = affordable, missing = missing, badge = badge, badgeText = badgeText,
    priceKind = priceKind, onSale = onSale }
end

-- the sub line of a card: "x100" for a pack of items, else nothing
function V.subLine(data)
  local n = tonumber(type(data) == 'table' and data.count)
  if n and n > 1 and data.type == 'item' then return 'x' .. math.floor(n) end
  return ''
end

-- the date of a history line ("Bought on 2026-11-14 12:30 for 40 Chaos Coins." -> "2026-11-14 12:30"), nil without one
function V.historyDate(description)
  return tostring(description or ''):match('(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d)')
end

-- ---------------------------------------------------------------- the details pane
-- What the pane offers for a picked card.
--   sel         where the server has the offer (nil: a history line, no buttons)
--   hasLook     the look preview shows it (the preview column opens)
--   tryPlan     TryOn.plan(...) of the offer ({show = bool}); nil without one
-- -> {buy = bool (enabled), showBuy, gift = bool (shown), giftEnabled, try = bool (shown), note = key, missing}
--   note: nil | 'owned' | 'poor' | 'history'
function V.detailPlan(data, points, sel, hasLook, tryPlan)
  local st = V.cardState(data, points)
  local plan = { showBuy = sel ~= nil, buy = false, gift = false, giftEnabled = false, try = false, note = nil,
    missing = st.missing, hasLook = hasLook == true, state = st }
  if not sel then
    plan.note = 'history'
    return plan
  end
  plan.buy = not st.owned and st.affordable
  plan.gift = type(data) == 'table' and data.gift == true
  plan.giftEnabled = plan.gift and st.affordable
  plan.try = type(tryPlan) == 'table' and tryPlan.show == true
  if st.owned then plan.note = 'owned'
  elseif not st.affordable then plan.note = 'poor' end
  return plan
end

-- ---------------------------------------------------------------- the search results
-- the top group of a result: its path's first name ("Cosmetics" of {"Cosmetics", "Wings"}), the category itself for a top one
local function groupOf(offer)
  local path = type(offer) == 'table' and offer.path
  if type(path) == 'table' and type(path[1]) == 'string' then return path[1] end
  return ''
end
V.resultGroup = groupOf

-- the filter chips of a result list: {{name = nil (all) | group, count}}, All first, then the groups in the order they
-- first appear; empty when everything is in one group (nothing to filter)
function V.resultGroups(offers)
  local order, counts = {}, {}
  for _, o in ipairs(offers or {}) do
    local g = groupOf(o)
    if not counts[g] then counts[g] = 0; order[#order + 1] = g end
    counts[g] = counts[g] + 1
  end
  if #order < 2 then return {} end
  local out = { { name = nil, count = #(offers or {}) } }
  for _, g in ipairs(order) do out[#out + 1] = { name = g, count = counts[g] } end
  return out
end

-- the results of one group (all when group is nil)
function V.filterResults(offers, group)
  if group == nil then return offers or {} end
  local out = {}
  for _, o in ipairs(offers or {}) do
    if groupOf(o) == group then out[#out + 1] = o end
  end
  return out
end

-- ---------------------------------------------------------------- paging
-- "2 / 5" (nothing for one page)
function V.pageText(page, pages)
  pages = tonumber(pages) or 1
  if pages <= 1 then return '' end
  return string.format('%d / %d', math.max(1, math.min(tonumber(page) or 1, pages)), pages)
end

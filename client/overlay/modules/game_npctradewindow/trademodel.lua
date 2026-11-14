-- NPC trade window (O571): the data side without client API, tested by trademodel_test.lua with luajit and lua5.3.
-- The cards (proper-case name, price, weight, owned count, category), the search / category / sort rules, how many
-- of an item the player can buy or sell and why not more, the total and what is left after, the "Sell all" preview, the
-- ignore list of the quick sale, the sale queue (one packet of at most 100 at a time, the next one only after the
-- server's player goods say the last one went through) and the session that owns the delayed work of one shop.
TradeModel = {}
local M = TradeModel

M.BUY, M.SELL = 1, 2
M.MAX_AMOUNT = 100        -- the shop packet carries one byte: at most 100 of an item per click
M.BAG_FEE = 20            -- "buy in shopping bags": 20 gold for a stack, 20 for every 20 single items
M.PLAYER_GOODS_CAP = 255  -- the 10.98 player goods packet cannot report more than this per item

-- ---------------------------------------------------------------- names
local SMALL = { of = true, the = true, ['and'] = true, ['in'] = true, on = true, ['for'] = true, to = true, a = true,
  an = true, with = true, from = true }

-- "sword of valor" -> "Sword of Valor": every word capital but the small ones in the middle
function M.properName(name)
  name = tostring(name or '')
  local first = true
  local out = name:gsub('(%a[%w\']*)', function(word)
    local low = word:lower()
    if not first and SMALL[low] then return low end
    first = false
    return low:sub(1, 1):upper() .. low:sub(2)
  end)
  return out
end

-- ---------------------------------------------------------------- categories
-- Derived from what the client knows about an item: the market category of the dat (the 10.98 market categories),
-- the slot it is worn in, and, for the items the dat gives no market data (the Chaos items), its name. `facts` =
-- {market = number|nil, clothSlot = number|nil, name = string}.
M.CATEGORIES = {
  { id = 'potions',  label = 'Potions',    market = { 10 }, words = { 'potion', 'vial', 'elixir', 'tonic' } },
  { id = 'runes',    label = 'Runes',      market = { 12 }, words = { 'rune' } },
  { id = 'ammo',     label = 'Ammunition', market = { 16, 25 }, words = { 'arrow', 'bolt', 'bullet', 'quiver' } },
  { id = 'weapons',  label = 'Weapons',    market = { 17, 18, 19, 20, 21, 27 },
    words = { 'sword', 'axe', 'club', 'mace', 'hammer', 'bow', 'crossbow', 'wand', 'rod', 'spear', 'dagger', 'blade',
      'staff', 'scythe', 'lance', 'flail' } },
  { id = 'armor',    label = 'Armor',      market = { 1, 3, 7, 8, 13 },
    words = { 'armor', 'helmet', 'legs', 'boots', 'shield', 'hat', 'cap', 'robe', 'plate', 'greaves', 'coat' } },
  { id = 'jewelry',  label = 'Jewelry',    market = { 2, 11 }, words = { 'ring', 'amulet', 'necklace', 'pendant' } },
  { id = 'tools',    label = 'Tools',      market = { 14 }, words = { 'rope', 'shovel', 'pick', 'machete', 'scythe' } },
  { id = 'food',     label = 'Food',       market = { 6 }, words = { 'bread', 'meat', 'ham', 'cheese', 'fish', 'apple' } },
  { id = 'containers', label = 'Containers', market = { 4 }, words = { 'backpack', 'bag', 'pouch', 'chest' } },
  { id = 'loot',     label = 'Loot',       market = { 15, 24, 26 }, words = { 'gem', 'pearl', 'ore', 'essence', 'dust', 'fur' } },
  { id = 'other',    label = 'Other',      market = {} },
}
M.OTHER = 'other'

local BY_MARKET = {}
for _, c in ipairs(M.CATEGORIES) do for _, m in ipairs(c.market) do BY_MARKET[m] = c.id end end

-- the cloth slots (the engine's ClothSlot): 1 head, 2 necklace, 4 armor, 5 and 6 the hands, 7 legs, 8 feet, 9 ring, 10 ammo
local BY_SLOT = { [1] = 'armor', [2] = 'jewelry', [4] = 'armor', [5] = 'weapons', [6] = 'weapons', [7] = 'armor',
  [8] = 'armor', [9] = 'jewelry', [10] = 'ammo' }

local function hasWord(name, word)
  return (' ' .. name:lower():gsub('[^%w]+', ' ') .. ' '):find(' ' .. word .. ' ', 1, true) ~= nil
end

function M.category(facts)
  facts = facts or {}
  local byMarket = BY_MARKET[tonumber(facts.market) or 0]
  if byMarket then return byMarket end
  local name = tostring(facts.name or '')
  for _, c in ipairs(M.CATEGORIES) do
    for _, w in ipairs(c.words or {}) do
      if hasWord(name, w) then return c.id end
    end
  end
  return BY_SLOT[tonumber(facts.clothSlot) or 0] or M.OTHER
end

function M.categoryLabel(id)
  for _, c in ipairs(M.CATEGORIES) do if c.id == id then return c.label end end
  return M.CATEGORIES[#M.CATEGORIES].label
end

-- ---------------------------------------------------------------- sorting and searching
M.SORTS = { 'name', 'price', 'weight' }

function M.nextSort(sort)
  for i, s in ipairs(M.SORTS) do
    if s == sort then return M.SORTS[i % #M.SORTS + 1] end
  end
  return M.SORTS[1]
end

local function lessBy(sort)
  return function(a, b)
    if sort == 'price' and a.price ~= b.price then return a.price < b.price end
    if sort == 'weight' and a.weight ~= b.weight then return a.weight < b.weight end
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then return na < nb end
    return a.index < b.index
  end
end

-- plain text search: no pattern characters
local function contains(hay, needle)
  if needle == '' then return true end
  return hay:lower():find(needle:lower(), 1, true) ~= nil
end

-- ---------------------------------------------------------------- prices and amounts
-- the price of n of an item: the shopping bag fee when the player buys into bags (gold only: `ctx.bags`)
function M.total(ctx, item, n)
  n = math.max(0, math.floor(tonumber(n) or 0))
  local sum = (tonumber(item.price) or 0) * n
  if ctx.type == M.BUY and ctx.bags and n > 0 then
    if item.stackable then
      sum = sum + M.BAG_FEE
    else
      sum = sum + math.ceil(n / 20) * M.BAG_FEE
    end
  end
  return sum
end

-- How many of `item` the player can trade now, and why it is not more. Returns max, reason; the reason is 'gold'
-- (the next one costs more than the balance), 'capacity' (the next one is too heavy), 'owned' (all the player has),
-- 'cap' (the 100 of one click) or nil when the item is not tradable at all.
-- ctx = {type, money, freeCapacity, ignoreCapacity, bags, owned = function(item) -> number}
function M.limit(ctx, item)
  if ctx.type == M.SELL then
    local have = math.max(0, math.floor(ctx.owned and ctx.owned(item) or 0))
    if have <= 0 then return 0, 'owned' end
    if have > M.MAX_AMOUNT then return M.MAX_AMOUNT, 'cap' end
    return have, 'owned'
  end
  local weight = tonumber(item.weight) or 0
  local capMax = M.MAX_AMOUNT
  if not ctx.ignoreCapacity and weight > 0 then
    capMax = math.min(capMax, math.floor((tonumber(ctx.freeCapacity) or 0) / weight + 1e-9))
  end
  local best = 0
  local money = tonumber(ctx.money) or 0
  for n = capMax, 1, -1 do
    if M.total(ctx, item, n) <= money then best = n break end
  end
  if best >= M.MAX_AMOUNT then return best, 'cap' end
  if best >= capMax and capMax < M.MAX_AMOUNT then return best, 'capacity' end
  if capMax > best and M.total(ctx, item, best + 1) > money then return best, 'gold' end
  return best, 'capacity'
end

function M.clampAmount(value, min, max)
  value = math.floor(tonumber(value) or 0)
  max = math.max(0, math.floor(tonumber(max) or 0))
  min = max > 0 and math.max(1, math.floor(tonumber(min) or 1)) or 0
  return math.max(min, math.min(max, value))
end

-- ---------------------------------------------------------------- the cards
-- ctx adds: items (the shop's list of this tab: {ptr, name, weight, price, stackable}), search, category, sort,
-- factsOf(item) -> facts, tradable(item) -> boolean. Returns the visible cards in order, and all cards (for the widgets).
function M.cards(ctx)
  local all = {}
  for index, item in ipairs(ctx.items or {}) do
    local facts = ctx.factsOf and ctx.factsOf(item) or { name = item.name }
    facts.name = facts.name or item.name
    local can = ctx.tradable == nil or ctx.tradable(item) and true or false
    local owned = ctx.owned and ctx.owned(item) or nil
    all[#all + 1] = {
      item = item, index = index, key = index, name = M.properName(item.name), rawName = item.name,
      price = tonumber(item.price) or 0, weight = tonumber(item.weight) or 0, owned = owned,
      can = can, category = M.category(facts), stackable = item.stackable == true,
    }
  end
  local visible = {}
  for _, card in ipairs(all) do
    local shown = (ctx.type ~= M.SELL or card.can) and contains(card.rawName, ctx.search or '')
    card.shown = shown
    if shown then visible[#visible + 1] = card end
  end
  table.sort(visible, lessBy(ctx.sort or 'name'))
  return visible, all
end

-- The category chips: "All" and every category some card (that matches the search) belongs to, in the order of
-- M.CATEGORIES, each with its count. `cards` is the first result of M.cards run with category = nil.
function M.chips(cards)
  local counts, order = {}, {}
  for _, c in ipairs(cards) do counts[c.category] = (counts[c.category] or 0) + 1 end
  local out = { { id = 'all', label = 'All', count = #cards } }
  for _, cat in ipairs(M.CATEGORIES) do
    if counts[cat.id] then out[#out + 1] = { id = cat.id, label = cat.label, count = counts[cat.id] } end
  end
  return out
end

function M.filterCategory(cards, category)
  if not category or category == 'all' then return cards end
  local out = {}
  for _, c in ipairs(cards) do if c.category == category then out[#out + 1] = c end end
  return out
end

-- the chips in rows: widths -> {x, y} per chip, and the height of the block
function M.flow(widths, maxWidth, chipHeight, gapX, gapY)
  gapX, gapY = gapX or 4, gapY or 4
  local out, x, y = {}, 0, 0
  for i, w in ipairs(widths) do
    w = math.min(w, maxWidth)
    if x > 0 and x + w > maxWidth then x, y = 0, y + chipHeight + gapY end
    out[i] = { x = x, y = y, width = w }
    x = x + w + gapX
  end
  return out, (#widths > 0) and (y + chipHeight) or 0
end

-- the card after `key` (dir 1) or before it (dir -1) in the visible list; the first one when none is selected
function M.step(cards, key, dir)
  if #cards == 0 then return nil end
  local at
  for i, c in ipairs(cards) do if c.key == key then at = i break end end
  if not at then return cards[dir < 0 and #cards or 1].key end
  return cards[math.max(1, math.min(#cards, at + dir))].key
end

-- ---------------------------------------------------------------- the detail panel
-- What the right side shows for a selected card and an amount: totals, what is left, the warnings. Numbers only.
function M.detail(ctx, card, amount)
  if not card then return { empty = true, max = 0, amount = 0 } end
  local item = card.item
  local max, reason = M.limit(ctx, item)
  amount = M.clampAmount(amount, 1, max)
  local total = M.total(ctx, item, amount)
  local d = {
    empty = false, max = max, reason = reason, amount = amount, total = total,
    unit = M.total(ctx, item, 1), weightEach = card.weight, weightTotal = card.weight * amount,
    owned = card.owned, canTrade = max > 0,
  }
  if ctx.type == M.BUY then
    d.after = (tonumber(ctx.money) or 0) - total
    d.capacityAfter = (tonumber(ctx.freeCapacity) or 0) - d.weightTotal
    d.tooHeavy = not ctx.ignoreCapacity and card.weight > 0 and d.capacityAfter < -1e-9
    d.warn = max == 0 and (reason == 'gold' and 'gold' or 'capacity') or nil
    if max > 0 and amount >= max and (reason == 'capacity' or reason == 'gold') then d.hint = reason end
  else
    d.after = (tonumber(ctx.money) or 0) + total
    d.capacityAfter = (tonumber(ctx.freeCapacity) or 0) + d.weightTotal
  end
  return d
end

-- ---------------------------------------------------------------- Sell all
-- The rows of the "Sell all" preview: every sellable item the player carries that the ignore list does not hold,
-- two entries of one id and subtype once. ctx = {items (the sell list), owned(item), ignored = {[id] = true},
-- idOf(item), subtypeOf(item), bulkOk(item), marketValue(item) -> number|nil}. Items whose sale needs the player to pick the
-- exact copy (charges, fluids) come back with `manual = true` and are never part of the sale.
function M.sellAllRows(ctx)
  local rows, seen = {}, {}
  for index, item in ipairs(ctx.items or {}) do
    local id = ctx.idOf and ctx.idOf(item) or item.id
    local key = tostring(id) .. ':' .. tostring(ctx.subtypeOf and ctx.subtypeOf(item) or 0)
    local qty = math.floor(ctx.owned and ctx.owned(item) or 0)
    if not seen[key] and qty > 0 then
      seen[key] = true
      local value = ctx.marketValue and ctx.marketValue(item) or nil
      rows[#rows + 1] = {
        item = item, index = index, id = id, key = key, name = M.properName(item.name), qty = qty,
        price = tonumber(item.price) or 0, subtotal = (tonumber(item.price) or 0) * qty,
        ignored = ctx.ignored and ctx.ignored[id] == true or false,
        manual = ctx.bulkOk and not ctx.bulkOk(item) or false,
        belowMarket = value ~= nil and value > 0 and (tonumber(item.price) or 0) < value,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.subtotal ~= b.subtotal then return a.subtotal > b.subtotal end
    return a.key < b.key
  end)
  return rows
end

-- the totals of the rows the player left ticked: items, pieces, gold, rows below the market value, and `ok` rows
-- (the ones sold: ticked, not ignored, not manual)
function M.sellAllTotals(rows, unticked)
  local t = { rows = 0, pieces = 0, gold = 0, below = 0, ok = {} }
  for _, r in ipairs(rows) do
    if not r.ignored and not r.manual and not (unticked and unticked[r.key]) then
      t.rows = t.rows + 1
      t.pieces = t.pieces + r.qty
      t.gold = t.gold + r.subtotal
      if r.belowMarket then t.below = t.below + 1 end
      t.ok[#t.ok + 1] = r
    end
  end
  return t
end

-- ---------------------------------------------------------------- the ignore list
-- What the saved file holds, cleaned: whole client ids from 1 to 65535, each once.
function M.cleanIgnoreList(data)
  local out, seen = {}, {}
  if type(data) ~= 'table' then return out end
  for _, id in pairs(data) do
    if type(id) == 'number' and id > 0 and id <= 65535 and id == math.floor(id) and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

function M.ignoreSet(list)
  local set = {}
  for _, id in ipairs(list or {}) do set[id] = true end
  return set
end

-- ---------------------------------------------------------------- the session and the sale queue
-- Owns the delayed work of one shop: a callback scheduled for shop A never touches shop B.
function M.newSession(schedule, cancel)
  local s = { generation = 0, open = false, events = {} }
  function s:finish()
    self.open = false
    self.generation = self.generation + 1
    if self.queue then
      self.queue:cancel()
      self.queue = nil
    end
    for event in pairs(self.events) do cancel(event) end
    self.events = {}
  end
  function s:begin()
    self:finish()
    self.open = true
  end
  function s:schedule(callback, delay)
    local generation = self.generation
    local event
    event = schedule(function()
      self.events[event] = nil
      if self.open and self.generation == generation then callback() end
    end, delay or 0)
    self.events[event] = true
    return event
  end
  return s
end

-- Sells the entries one packet at a time. The player goods the server sends after a sale are the only
-- acknowledgment; the timer is a failure timeout, never permission to send more. options = {isValid, quantity(entry),
-- money(), sell(entry, amount), schedule(fn, ms), cancel(event), onFinish(sold, proceeds), onError(message),
-- capped(entry)}.
M.QUEUE_TIMEOUT = 5000
M.QUEUE_MAX_PACKETS = 1000

function M.newQueue(options)
  local q = { options = options, entries = {}, index = 1, sold = 0, proceeds = 0, packets = 0 }
  function q:cancel()
    self.active = false
    if self.timeout then
      self.options.cancel(self.timeout)
      self.timeout = nil
    end
    self.pending = nil
    self.entries = {}
  end
  function q:fail(message)
    self:cancel()
    self.options.onError(message)
  end
  function q:start(entries)
    self.entries = entries
    self.active = true
    self:advance()
  end
  function q:advance()
    if not self.active or not self.options.isValid() then
      self:cancel()
      return
    end
    local entry = self.entries[self.index]
    while entry and self.options.quantity(entry) <= 0 do
      self.index = self.index + 1
      entry = self.entries[self.index]
    end
    if not entry then
      local sold, proceeds = self.sold, self.proceeds
      self:cancel()
      self.options.onFinish(sold, proceeds)
      return
    end
    if self.packets >= M.QUEUE_MAX_PACKETS then
      self:fail('Sale stopped: too many chunks. Please refresh the shop.')
      return
    end
    local quantity = self.options.quantity(entry)
    local amount = math.min(M.MAX_AMOUNT, quantity)
    self.pending = { entry = entry, quantity = quantity, amount = amount, money = self.options.money(),
      capped = self.options.capped and self.options.capped(entry) }
    self.packets = self.packets + 1
    self.timeout = self.options.schedule(function()
      self.timeout = nil
      if self.active and self.pending then
        self:fail('Sale stopped: the server did not confirm the sale. Please refresh the shop.')
      end
    end, M.QUEUE_TIMEOUT)
    self.options.sell(entry, amount)
  end
  function q:onGoods()
    local pending = self.pending
    if not self.active or not pending or not self.options.isValid() then return end
    local quantity = self.options.quantity(pending.entry)
    local proceeds = self.options.money() - pending.money
    -- the packet caps an item's count at 255: a sale can leave the capped count as it was, but the price is credited
    local countMatches = quantity == pending.quantity - pending.amount or
      (pending.capped and quantity >= pending.quantity - pending.amount)
    if proceeds ~= pending.entry.price * pending.amount or not countMatches then
      return -- an unrelated inventory or money update is no acknowledgment
    end
    self.options.cancel(self.timeout)
    self.timeout = nil
    self.pending = nil
    self.sold = self.sold + pending.amount
    self.proceeds = self.proceeds + proceeds
    self.options.schedule(function() self:advance() end, 0)
  end
  return q
end

return M

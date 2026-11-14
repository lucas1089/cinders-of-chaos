-- Pure helpers of the Deck of Cards window (no UI calls): the rows, the filters, the sort, the texts. Tested by
-- carddecklogic_test.lua (luajit / lua5.3). Server: server/data/scripts/chaos/cards.lua, extended opcode 173 (JSON {action, data}).
--   cards  (once per sync, in the player's language)  {cards = [{i, c, n, t, r, l, e, k, s, x, cl}], max, needSet}
--            i server id, c client id (the item the window draws), n name, t tier 1-4 (5 = legendary), r rarity word, l the
--            spell of the line (legendary: the class), e element, k kind, s the set element, x what it gives, cl classes
--   state  {unlocked, own = [[id, copies]], new = [id], on = [id], distinct, copies, max, class, set, quest}
-- The window asks: sync | toggle {id} | seen {ids} or {all = true} | open.
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
CardDeckLogic = {}
local L = CardDeckLogic

L.OPCODE = 173
L.MAX_ON = 5
L.SETS = { 'Fire', 'Earth', 'Death', 'Holy', 'Energy' } -- the elements with a card set bonus (server cards_config.lua sets.order)
L.ELEMENTS = { 'Fire', 'Earth', 'Ice', 'Death', 'Holy', 'Energy', 'Drown' }
L.RARITIES = { 'Common', 'Rare', 'Epic', 'Mythic', 'Legendary' }
L.SORTS = { 'number', 'name', 'rarity', 'copies', 'new', 'element' }
L.RARITY_COLOR = { Common = '#b8b0a0', Rare = '#6fa8ff', Epic = '#c487ff', Mythic = '#ff9a3c', Legendary = '#ffd24a' }
L.ON_COLOR = '#5fd16a'
L.NEW_COLOR = '#ff5a4a'

local function list(v)
  local out = {}
  if type(v) == 'table' then for _, x in ipairs(v) do out[#out + 1] = x end end
  return out
end
local function num(x) return tonumber(x) or 0 end
local function str(x) return type(x) == 'string' and x or '' end

-- the number of slots, from the server's `max`: a whole number from 1 to 10, five when it is anything else (opcode_fuzz_test.lua)
function L.maxOn(state)
  local m = type(state) == 'table' and tonumber(state.max) or nil
  if not m or m ~= m or m < 1 or m > 10 then return L.MAX_ON end
  return math.floor(m)
end

L.MAX_CARDS = 200

-- the server's static list, a row that is not a table with an id left out, at most MAX_CARDS rows (opcode_fuzz_test.lua)
function L.cleanCards(data)
  local out = {}
  for _, c in ipairs(list(type(data) == 'table' and data.cards)) do
    if #out >= L.MAX_CARDS then break end
    if type(c) == 'table' and tonumber(c.i) then
      out[#out + 1] = {
        id = num(c.i), cid = num(c.c), name = str(c.n), tier = num(c.t), rarity = str(c.r), line = str(c.l),
        element = str(c.e), kind = str(c.k), set = str(c.s), text = str(c.x), classes = type(c.cl) == 'table' and list(c.cl) or nil,
      }
    end
  end
  return out
end

-- the rows of the window: the static cards with the player's copies, the on mark and the "new" mark
function L.rows(cards, state)
  local own, on, new = {}, {}, {}
  state = type(state) == 'table' and state or {}
  for _, r in ipairs(list(state.own)) do
    if type(r) == 'table' and tonumber(r[1]) then own[num(r[1])] = num(r[2]) end
  end
  for _, id in ipairs(list(state.on)) do on[num(id)] = true end
  for _, id in ipairs(list(state.new)) do new[num(id)] = true end
  local out = {}
  for i, c in ipairs(cards or {}) do
    out[#out + 1] = {
      id = c.id, cid = c.cid, name = c.name, tier = c.tier, rarity = c.rarity, line = c.line, element = c.element, kind = c.kind,
      set = c.set, text = c.text, classes = c.classes, order = i, count = math.floor(own[c.id] or 0), owned = (own[c.id] or 0) > 0,
      on = on[c.id] == true, new = new[c.id] == true and (own[c.id] or 0) > 0,
    }
  end
  return out
end

-- can this class use the card (a card with no class list is for everyone)
function L.usable(row, className)
  if not row.classes or not className or className == '' then return true end
  for _, n in ipairs(row.classes) do
    if n == className then return true end
  end
  return false
end

local function contains(hay, needle)
  return hay:lower():find(needle:lower(), 1, true) ~= nil
end

-- filter f = {set = 'Fire' | 'none' | nil, rarity = word | nil, element = word | 'none' | nil, owned = 'owned' | 'missing' | nil,
-- mine = bool, search = text}
function L.matches(row, f, className)
  f = f or {}
  if f.set then
    if f.set == 'none' then
      if row.set ~= '' then return false end
    elseif row.set ~= f.set then
      return false
    end
  end
  if f.rarity and row.rarity ~= f.rarity then return false end
  if f.element then
    if f.element == 'none' then
      if row.element ~= '' then return false end
    elseif row.element ~= f.element then
      return false
    end
  end
  if f.owned == 'owned' and not row.owned then return false end
  if f.owned == 'missing' and row.owned then return false end
  if f.mine and not L.usable(row, className) then return false end
  local s = str(f.search):gsub('^%s+', ''):gsub('%s+$', '')
  if s ~= '' then
    if not (contains(row.name, s) or contains(row.line, s) or contains(row.element, s) or contains(row.text, s)
        or contains(row.rarity, s) or contains(row.set, s)) then
      return false
    end
  end
  return true
end

function L.filter(rows, f, className)
  local out = {}
  for _, r in ipairs(rows) do
    if L.matches(r, f, className) then out[#out + 1] = r end
  end
  return out
end

-- sort modes: number (the server order), name, rarity (best first), copies (most first), new (new first), element
function L.sort(rows, mode)
  local out = {}
  for _, r in ipairs(rows) do out[#out + 1] = r end
  local function byOrder(a, b) return a.order < b.order end
  local cmp
  if mode == 'name' then
    cmp = function(a, b)
      if a.name ~= b.name then return a.name:lower() < b.name:lower() end
      return byOrder(a, b)
    end
  elseif mode == 'rarity' then
    cmp = function(a, b)
      if a.tier ~= b.tier then return a.tier > b.tier end
      return byOrder(a, b)
    end
  elseif mode == 'copies' then
    cmp = function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return byOrder(a, b)
    end
  elseif mode == 'new' then
    cmp = function(a, b)
      if a.new ~= b.new then return a.new end
      return byOrder(a, b)
    end
  elseif mode == 'element' then
    cmp = function(a, b)
      if a.element ~= b.element then return a.element < b.element end
      return byOrder(a, b)
    end
  else
    cmp = byOrder
  end
  table.sort(out, cmp)
  return out
end

-- the numbers of the summary line
function L.counts(rows)
  local c = { total = #rows, owned = 0, copies = 0, on = 0, new = 0 }
  -- copies are summed as whole numbers (a server value that is no integer is floored)
  for _, r in ipairs(rows) do
    if r.owned then c.owned = c.owned + 1 end
    c.copies = c.copies + math.floor(r.count)
    if r.on then c.on = c.on + 1 end
    if r.new then c.new = c.new + 1 end
  end
  return c
end

function L.summary(rows, max)
  local c = L.counts(rows)
  return tr('Cards: %d of %d  -  copies: %d  -  on: %d of %d', c.owned, c.total, math.floor(c.copies), c.on, L.maxOn({ max = max }))
end

-- the number the hub menu card shows: cards looted and not seen yet
function L.newCount(state)
  if type(state) ~= 'table' then return 0 end
  return #list(state.new)
end

-- the cards that are on, by number (the panel of the active cards)
function L.activeRows(rows)
  local out = {}
  for _, r in ipairs(rows) do
    if r.on then out[#out + 1] = r end
  end
  table.sort(out, function(a, b) return a.order < b.order end)
  return out
end

-- the tooltip and the detail text of a card
function L.detail(row)
  local lines = { row.name }
  local sub = row.rarity
  if row.line ~= '' then sub = sub .. '  -  ' .. row.line end
  if row.element ~= '' then sub = sub .. '  -  ' .. tr(row.element) end
  lines[#lines + 1] = sub
  if row.set ~= '' then lines[#lines + 1] = tr('Card set: %s', tr(row.set)) end
  lines[#lines + 1] = row.text
  lines[#lines + 1] = row.owned and tr('Copies: %d', row.count) or tr('Not owned yet')
  return table.concat(lines, '\n')
end

-- the button of the detail panel: label and whether it can be pressed, and why not
function L.toggleButton(row, state)
  state = type(state) == 'table' and state or {}
  if not row then return { label = tr('Turn on'), enabled = false } end
  if state.unlocked ~= true then return { label = tr('Locked'), enabled = false, why = str(state.quest) } end
  if row.on then return { label = tr('Turn off'), enabled = true } end
  if not row.owned then return { label = tr('Turn on'), enabled = false, why = tr('You have no copy of this card.') } end
  if #list(state.on) >= L.maxOn(state) then
    return { label = tr('Turn on'), enabled = false, why = tr('Five cards are on. Turn one off first.') }
  end
  return { label = tr('Turn on'), enabled = true }
end

-- the options of a filter box: {value, label}; value nil = no filter
function L.options(kind)
  local out = {}
  if kind == 'set' then
    out[1] = { nil, tr('All sets') }
    for _, e in ipairs(L.SETS) do out[#out + 1] = { e, tr(e) } end
    out[#out + 1] = { 'none', tr('No set') }
  elseif kind == 'rarity' then
    out[1] = { nil, tr('All rarities') }
    for _, r in ipairs(L.RARITIES) do out[#out + 1] = { r, tr(r) } end
  elseif kind == 'element' then
    out[1] = { nil, tr('All elements') }
    for _, e in ipairs(L.ELEMENTS) do out[#out + 1] = { e, tr(e) } end
    out[#out + 1] = { 'none', tr('No element') }
  elseif kind == 'owned' then
    out = { { nil, tr('Owned and missing') }, { 'owned', tr('Owned') }, { 'missing', tr('Missing') } }
  elseif kind == 'class' then
    out = { { false, tr('Every class') }, { true, tr('My class') } }
  elseif kind == 'sort' then
    local names = { number = tr('By number'), name = tr('By name'), rarity = tr('By rarity'), copies = tr('By copies'),
      new = tr('New first'), element = tr('By element') }
    for _, s in ipairs(L.SORTS) do out[#out + 1] = { s, names[s] } end
  end
  return out
end

-- the value behind a label of an options list (nil when the label is the "all" one or unknown)
function L.valueOf(options, label)
  for _, o in ipairs(options) do
    if o[2] == label then return o[1] end
  end
  return nil
end

-- the border colour of a card cell: green when on, the rarity colour when owned, dim when not owned
function L.borderColor(row)
  if row.on then return L.ON_COLOR end
  if not row.owned then return '#3a3228' end
  return L.RARITY_COLOR[row.rarity] or '#b8b0a0'
end

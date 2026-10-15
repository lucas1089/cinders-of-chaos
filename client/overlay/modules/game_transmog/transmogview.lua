-- Transmog window: logic without client API (game_transmog/transmog.lua uses it; transmogview_test.lua tests it).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
TransmogView = {}
local V = TransmogView

V.SOURCE_COLORS = { store = '#e8b84a', achievement = '#5cc8c0', season = '#c06cff', exclusive = '#ff7a5c' }

-- '12 / 231 (5%)'
function V.progressText(unlocked, total)
  unlocked, total = tonumber(unlocked) or 0, tonumber(total) or 0
  local pct = total > 0 and math.floor(unlocked * 100 / total) or 0
  return string.format('%d / %d (%d%%)', unlocked, total, pct)
end

function V.percent(unlocked, total)
  unlocked, total = tonumber(unlocked) or 0, tonumber(total) or 0
  if total <= 0 then return 0 end
  return math.max(0, math.min(100, unlocked * 100 / total))
end

-- 1234567 -> '1,234,567'
function V.gold(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local sign, digits = s:match('^(%-?)(%d+)$')
  if not digits then return s end
  digits = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return sign .. digits
end

-- the line under an equipment slot
function V.slotSub(row)
  local item = row and row.item
  if not item then return 'Empty' end
  if not item.kind then return tr('Cannot change its look') end
  if item.look then return 'Look: ' .. tostring(item.look.name) end
  return tr('%s, own look', (item.kindName or item.kind))
end

-- the slot to select: the wanted one if it has an item, else the first slot whose item can change its look
function V.pickSlot(slots, wanted)
  local first
  for _, s in ipairs(slots or {}) do
    if s.slot == wanted and s.item then return s.slot end
    if not first and s.item and s.item.kind then first = s.slot end
  end
  return first
end

function V.slotRow(slots, slot)
  for _, s in ipairs(slots or {}) do
    if s.slot == slot then return s end
  end
  return nil
end

-- looks whose name contains the search text (case-insensitive, plain); nil / '' = all
function V.filter(rows, text)
  text = type(text) == 'string' and text:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
  if text == '' then return rows or {} end
  local out = {}
  for _, r in ipairs(rows or {}) do
    if tostring(r.name or ''):lower():find(text, 1, true) then out[#out + 1] = r end
  end
  return out
end

-- buttons and text of the detail panel. row = the selected slot row, look = the selected wardrobe row (or nil),
-- money = gold the character can pay
function V.detail(row, look, money)
  local d = { apply = false, remove = false, fee = '', hint = '' }
  local item = row and row.item
  if not item then
    d.hint = 'Equip an item in this slot to change its look.'
    return d
  end
  if not item.kind then
    d.hint = 'This item cannot change its look.'
    return d
  end
  money = tonumber(money) or 0
  local applyFee = tonumber(item.applyFee) or 0
  d.fee = 'Fee: ' .. V.gold(applyFee) .. ' gold'
  if item.look then
    d.remove = true
    local removeFee = tonumber(item.removeFee) or 0
    d.fee = d.fee .. (removeFee > 0 and ('  -  remove: ' .. V.gold(removeFee) .. ' gold') or tr('  -  remove: free'))
  end
  if not look then
    d.hint = 'Pick an appearance on the right to preview it.'
  elseif look.id == item.id then
    d.hint = 'That is the item\'s own look.'
  elseif item.look and item.look.id == look.id then
    d.hint = 'The item already has this look.'
  elseif money < applyFee then
    d.hint = 'Not enough gold (backpack and bank).'
  else
    d.apply = true
    d.hint = 'Appearance only: stats and tooltip stay the item\'s own.'
  end
  return d
end

-- set rows of the collection page: owned first, then by name
function V.sortSets(sets)
  local out = {}
  for _, s in ipairs(sets or {}) do out[#out + 1] = s end
  table.sort(out, function(a, b)
    if (a.owned and true or false) ~= (b.owned and true or false) then return a.owned and true or false end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

function V.setLine(set)
  if set.owned then return 'Owned' end
  return tostring(set.how or '')
end

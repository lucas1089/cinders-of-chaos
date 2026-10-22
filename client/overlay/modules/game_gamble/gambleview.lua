-- The Gambler window texts and rules (pure, no UI calls): shared by gamble.lua and gambleview_test.lua.
-- `s` is the server's state (server data/scripts/chaos/gamble_core.lua K.payload):
--   w                                       the window number the stock belongs to (sent back with buy / reroll)
--   items = {{i, id, c, n, s, sn, l, p, sold}}   per crate: slot index, server id, client id, name, slot key, slot name,
--                                           item level, price, sold
--   level, gate                             the level the stock was made for and its item level gate
--   near, money                             at the Gambler; gold carried plus the bank
--   left, hours, at, tz                     seconds to the next stock, its period, its clock time, the time zone text
--   reroll, rerolls, rerollMax              the price of an early refresh (nil: none left), used, allowed per window
--   odds = {{r, n, p}}                      rarity place (1 Common .. 6 Divine), name, percent
--   npc, last = {r, rn, id, c, n, l, s, i}  the Gambler's name; the last piece bought (the reveal)
-- The purchase rules here mirror the server's (gamble_core.lua K.checkBuy) for the buttons only; the server decides.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

GambleView = GambleView or {}
local V = GambleView

V.COLORS = { gold = '#e8b84a', text = '#d8ccb4', dim = '#8c8070', good = '#8fd16a', bad = '#e07060', warn = '#e0a050',
  sold = '#6a6058' }
-- the rarity colours of game_itemrarity (frames and names), by rarity id: 1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary,
-- 10 Divine (6 .. 9 and 11 .. 15 only on items saved before the seven rarities: the rarity they became)
V.RARITY = {
  [1] = '#c8c8c8', [2] = '#5ccf5c', [3] = '#4a90ff', [4] = '#a35cf0', [5] = '#ffd040', [6] = '#ffd040', [7] = '#ffd040',
  [8] = '#ffd040', [9] = '#ffd040', [10] = '#c8e8ff', [11] = '#c8e8ff', [12] = '#c8e8ff', [13] = '#c8e8ff', [14] = '#c8e8ff',
  [15] = '#c8e8ff'
}

local function num(v) return tonumber(v) or 0 end

-- a client item id the window may hand to UIItem:setItemId: a whole number 1..65535 (the engine keeps item looks in a
-- 16-bit table and checks a larger id after cutting it to 16 bits, so 70000 would show another look), else 0
function V.clientId(v)
  v = tonumber(v)
  if not v or v ~= v or v < 1 or v > 65535 or v ~= math.floor(v) then return 0 end
  return v
end

-- 1234567 -> "1,234,567"
function V.fmtNum(n)
  n = math.floor(num(n))
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. out
end

-- 1500000 -> "1.5M", 97000 -> "97k", 950 -> "950"
function V.short(n)
  n = num(n)
  if n >= 1000000 then
    local s = string.format('%.2f', n / 1000000):gsub('0+$', ''):gsub('%.$', '')
    return s .. 'M'
  end
  if n >= 10000 then
    return string.format('%dk', math.floor(n / 1000))
  end
  return V.fmtNum(n)
end

-- a countdown: "3h 05m", "12m 09s", "45s"
function V.countdown(sec)
  sec = math.max(0, math.floor(num(sec)))
  local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
  if h > 0 then return string.format('%dh %02dm', h, m) end
  if m > 0 then return string.format('%dm %02ds', m, s) end
  return string.format('%ds', s)
end

-- seconds left now, `elapsed` seconds after the state came
function V.left(s, elapsed)
  return math.max(0, num(s and s.left) - math.max(0, num(elapsed)))
end

function V.refreshText(s, elapsed)
  if not s then return '' end
  return tr('New crates at %s (%s), in %s', s.at or '?', s.tz or tr('server time'), V.countdown(V.left(s, elapsed)))
end

function V.canBuy(s, it)
  return s ~= nil and s.near == true and not it.sold and num(s.money) >= num(it.p)
end

-- one cell per crate, in the server's order: {i, id, clientId, name, slotText, levelText, priceText, priceColor, sold,
-- canBuy, buyText, tip}
function V.cells(s)
  local out = {}
  local items = type(s) == 'table' and type(s.items) == 'table' and s.items or {}
  for _, it in ipairs(items) do
    if type(it) ~= 'table' then it = { sold = true } end
    local can = V.canBuy(s, it)
    local afford = num(s.money) >= num(it.p)
    local why
    if it.sold then
      why = 'Sold. New crates come with the next stock.'
    elseif not s.near then
      why = tr('Buy from %s in person (in the market of the teleport room).', (s.npc or tr('the Gambler')))
    elseif not afford then
      why = tr('You need %s gold (backpack and bank).', V.fmtNum(it.p))
    else
      why = tr('Pay %s gold and break the seal.', V.fmtNum(it.p))
    end
    out[#out + 1] = {
      i = num(it.i), id = num(it.id), clientId = V.clientId(it.c), name = (tostring(it.n or ''):gsub('^%l', string.upper)),
      slotText = it.sn or it.s or '', levelText = 'iLvl ' .. num(it.l), level = num(it.l),
      priceText = V.fmtNum(it.p) .. ' gold', priceColor = it.sold and V.COLORS.sold or (afford and V.COLORS.gold or V.COLORS.bad),
      sold = it.sold == true, canBuy = can, buyText = it.sold and 'Sold' or ('Buy ' .. V.short(it.p)),
      tip = tr('%s\n%s, item level %d\nRarity: sealed until bought\nPrice: %s gold\n%s',
        (tostring(it.n or ''):gsub('^%l', string.upper)), it.sn or it.s or '', num(it.l), V.fmtNum(it.p), why)
    }
  end
  return out
end

function V.soldCount(s)
  local n = 0
  for _, it in ipairs(type(s) == 'table' and type(s.items) == 'table' and s.items or {}) do
    if type(it) == 'table' and it.sold then n = n + 1 end
  end
  return n
end

function V.header(s)
  if not s then return '' end
  return tr('Sealed crates for level %d (item level up to %d): %d of %d sold. Your gold: %s',
    num(s.level), num(s.gate), V.soldCount(s), #(s.items or {}), V.fmtNum(s.money))
end

function V.nearText(s)
  if not s then return '', V.COLORS.dim end
  if s.near then
    return tr('You stand before %s: pick a crate.', (s.npc or tr('the Gambler'))), V.COLORS.good
  end
  return tr('Look from anywhere; buy from %s in the market of the teleport room.', (s.npc or tr('the Gambler'))), V.COLORS.warn
end

-- the early refresh button: text, enabled, tooltip
function V.reroll(s)
  if not s or num(s.rerollMax) <= 0 then
    return tr('Fresh Crates'), false, tr('Not offered.')
  end
  if s.reroll == nil then
    return tr('Fresh Crates'), false, tr('Used %d of %d in this stock. New crates at %s.', num(s.rerolls),
      num(s.rerollMax), s.at or '?')
  end
  local ok = s.near == true and num(s.money) >= num(s.reroll)
  return tr('Fresh Crates (%s)', V.short(s.reroll)), ok,
    tr('A new stock now for %s gold (%d of %d used). The sold marks go too; each crate is still paid in full.',
      V.fmtNum(s.reroll), num(s.rerolls), num(s.rerollMax))
end

-- "Common 61.9% - Uncommon 11.6% - ..."
function V.oddsText(s)
  local parts = {}
  for _, o in ipairs(s and s.odds or {}) do
    local p = num(o.p)
    parts[#parts + 1] = string.format(p >= 1 and '%s %.1f%%' or '%s %.2f%%', o.n, p)
  end
  if #parts == 0 then return '' end
  return tr('Odds per crate: %s', table.concat(parts, ', '))
end

-- the odds of Legendary (place 5) or better (Divine is place 6)
function V.legendaryOrBetter(s)
  local t = 0
  for _, o in ipairs(s and s.odds or {}) do
    if num(o.r) >= 5 then t = t + num(o.p) end
  end
  return t
end

-- the reveal after a purchase: text, colour
function V.reveal(last)
  if type(last) ~= 'table' or not last.r then return '', V.COLORS.dim end
  local name = (tostring(last.n or ''):gsub('^%l', string.upper))
  return tr('The seal breaks: %s %s (item level %d)', last.rn or ('Rarity ' .. num(last.r)), name, num(last.l)),
    V.RARITY[num(last.r)] or V.COLORS.text
end

-- the look of the reveal: a client id (0: none)
function V.revealItem(last)
  if type(last) ~= 'table' or not last.r then return 0 end
  return V.clientId(last.c)
end

-- the same crates in the same order (only their texts and sold marks changed): the grid keeps its cells
function V.sameCells(a, b)
  if #a ~= #b then return false end
  for k = 1, #a do
    if a[k].i ~= b[k].i or a[k].id ~= b[k].id then return false end
  end
  return true
end

return V

-- NPC trade window: the geometry without client API (tested by tradewindowlogic_test.lua with luajit and lua5.3).
TradeWindowLogic = {}
local L = TradeWindowLogic

L.WIDTH = 420
L.HEIGHT = 520
L.MIN_WIDTH = 300
L.MIN_HEIGHT = 300
L.MARGIN = 24

-- The window size and position for a game view of rootW x rootH: the preferred size, smaller when the view is, and
-- centred; `top` keeps it under the top menu bar. Returns {x, y, w, h}.
function L.geometry(rootW, rootH, top)
  rootW, rootH, top = tonumber(rootW) or 0, tonumber(rootH) or 0, tonumber(top) or 0
  local w = math.max(L.MIN_WIDTH, math.min(L.WIDTH, rootW - 2 * L.MARGIN))
  local h = math.max(L.MIN_HEIGHT, math.min(L.HEIGHT, rootH - top - 2 * L.MARGIN))
  local x = math.max(0, math.floor((rootW - w) / 2))
  local y = math.max(top, top + math.floor((rootH - top - h) / 2))
  return { x = x, y = y, w = w, h = h }
end

-- Should the trade window be lifted out of its side panel? Only a window that is shown and not already floating
-- (parent = the game view's root panel, which the base dialog uses too).
function L.needsFloat(visible, parentIsRoot)
  return visible == true and parentIsRoot ~= true
end

-- ---------------------------------------------------------------------------------------------------------------
-- A currency other than gold (owner beta 2026-10-24: the azure NPC's window said "Currency: Gold Coin" and priced its
-- sets "30" next to the player's gold). The 10.98 shop packet carries no currency, so the server says it first on
-- extended opcode 113: {"action": "currency", "data": {code, name, item?, amount, again?}} (data/lib/chaos_npc_currency.lua).
-- The packet before the shop is the currency of the shop that opens next ("pending"); the module takes it when the
-- window is shown ("active") and drops it when the window closes; a packet marked `again` is the balance after a
-- purchase or a sale, and only means something while its window is open.
-- ---------------------------------------------------------------------------------------------------------------
L.CURRENCY_TTL = 15      -- seconds a pending currency waits for its window
L.NAME_MAX = 24          -- the longest currency name shown in the header
L.ROW_NAME_MAX = 36      -- the longest item name in a list row
L.ROW_INFO_MAX = 44      -- the longest "Price 30, 85.00 oz" line

-- "hallowfall coins" -> "Hallowfall Coins"
function L.titleCase(s)
  s = tostring(s or '')
  return (s:gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end))
end

-- the text cut to n characters, "..." in the last three when it was longer
function L.clip(s, n)
  s = tostring(s or '')
  if #s <= n then return s end
  return s:sub(1, math.max(1, n - 3)) .. '...'
end

-- A payload of opcode 113 -> {code, name, fullName, item, amount, again} or nil. `decode` is json.decode (a function
-- that raises or returns nil on bad text is fine).
function L.parseCurrency(buffer, decode)
  if type(buffer) ~= 'string' or type(decode) ~= 'function' then return nil end
  local ok, msg = pcall(decode, buffer)
  if not ok or type(msg) ~= 'table' or msg.action ~= 'currency' or type(msg.data) ~= 'table' then return nil end
  local d = msg.data
  local name = type(d.name) == 'string' and d.name or ''
  if name == '' then return nil end
  local amount = tonumber(d.amount)
  if not amount then return nil end
  local item = tonumber(d.item)
  return {
    code = type(d.code) == 'string' and d.code or '',
    name = L.clip(L.titleCase(name), L.NAME_MAX),
    fullName = L.titleCase(name),
    item = item and item > 0 and math.floor(item) or nil,
    amount = math.max(0, math.floor(amount)),
    again = d.again == true,
  }
end

function L.newState()
  return { pending = nil, active = nil }
end

-- A parsed currency arrived at time `now`. Returns 'update' (the open window's balance changed), 'pending' (the
-- shop that opens next) or 'ignored' (nothing, or a balance for a window that is not open).
function L.receive(state, spec, now)
  if not spec then return 'ignored' end
  if state.active then
    state.active.amount = spec.amount
    return 'update'
  end
  if spec.again then return 'ignored' end
  state.pending = { spec = spec, at = tonumber(now) or 0 }
  return 'pending'
end

-- The window is shown: its currency, or nil (gold). A pending currency older than the time to live is dropped.
function L.take(state, now)
  local p = state.pending
  state.pending = nil
  if p and (tonumber(now) or 0) - p.at <= L.CURRENCY_TTL then
    state.active = p.spec
  end
  return state.active
end

-- The window closed (or opens again): back to gold.
function L.release(state)
  state.active = nil
end

-- The item's name in a list row, whole when it fits.
function L.rowName(name)
  return L.clip(name, L.ROW_NAME_MAX)
end

-- "Price 30, 85.00 oz": `priceLabel` is the translated, formatted "Price 30"; `weight` a number of ounces (0 or nil
-- for none).
function L.rowInfo(priceLabel, weight, unit)
  local text = tostring(priceLabel or '')
  weight = tonumber(weight) or 0
  if weight > 0 then
    text = text .. ', ' .. string.format('%.2f', weight) .. ' ' .. tostring(unit or 'oz')
  end
  return L.clip(text, L.ROW_INFO_MAX)
end

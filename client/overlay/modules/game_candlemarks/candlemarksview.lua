-- Candlemarks window and counter: pure parts (no client API), so candlemarksview_test.lua runs under plain Lua.
-- The server (data/scripts/chaos/candlemarks.lua) sends
--   hud   {b = balance, p = progress (s), n = block (s), e = earning, w = why not ("ip" | "staff" | "level")}
--   state {balance, progress, block, earning, why, today, cap, level, weekEnds, near (Osric in range: Buy works),
--         offers = {{k, n, b, d, p, w, u, l, c, kind, own}}} (offer names and texts already in the player's language)
-- A text the window shows is {pattern, args...}: the module passes it to tr(pattern, args...), so every pattern is a
-- key of the client's pt-BR table (client_chaos_locale); '%s' alone is a value, not a key.

CandlemarksView = {}
local V = CandlemarksView

V.MAX_TEXT = 96
V.MAX_OFFERS = 80
-- the server's own refusal text too (candlemarks_config.lua messages.npc)
V.VISIT = 'Visit Osric the Chandler to buy (in the Hall of Services, or next to the temple).'
V.COLORS = { gold = '#e8b84a', text = '#d6c9ae', dim = '#8c8070', bad = '#e05040', good = '#70d070' }

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
  if v >= 0 then return math.floor(v) end
  return -math.floor(-v)
end
V.int = int

local function str(v, fallback)
  if type(v) ~= 'string' or v == '' then return fallback end
  if #v > V.MAX_TEXT then return v:sub(1, V.MAX_TEXT) end
  return v
end

function V.plain(t)
  if type(t) ~= 'table' then return tostring(t or '') end
  if #t <= 1 then return tostring(t[1] or '') end
  local ok, s = pcall(string.format, t[1], (table.unpack or unpack)(t, 2))
  return ok and s or tostring(t[1])
end

-- the counter's numbers from a hud (or a state) and the seconds since it came: {balance, left (s to the next coin),
-- earning, why}; while earning the client counts down by itself
function V.counter(h, since)
  h = type(h) == 'table' and h or {}
  local balance = math.max(0, int(h.b or h.balance))
  local block = math.max(60, int(h.n or h.block))
  local progress = math.max(0, int(h.p or h.progress))
  local earning = (h.e == true) or (h.earning == true)
  local left = block - progress
  if earning then left = left - math.max(0, int(since)) end
  left = math.max(0, math.min(block, left))
  return { balance = balance, left = left, earning = earning, why = type(h.w or h.why) == 'string' and (h.w or h.why) or nil }
end

-- minutes, rounded up (a coin due in 30 s shows 1 min)
function V.minutes(seconds)
  seconds = math.max(0, int(seconds))
  return math.floor((seconds + 59) / 60)
end

-- the counter's text and tooltip
function V.counterText(c)
  if not c.earning then
    return { '%d Candlemarks (paused)', c.balance }
  end
  return { '%d Candlemarks, next in %d min', c.balance, V.minutes(c.left) }
end

local WHY = {
  ip = 'Two other characters of your connection are earning. You keep your progress and earn again when one logs out.',
  staff = 'Staff characters do not earn Candlemarks.',
  level = 'Your character is below the level that earns Candlemarks.',
}
function V.counterTooltip(c)
  if not c.earning then
    return { WHY[c.why] or 'Not earning right now. Your progress is kept.' }
  end
  return { 'One Candlemark for every 30 minutes online, for your account. Click to open the shop.' }
end

-- the window's offers, checked: {key, name, boss, desc, price, weekly, used, level, cid, kind, canBuy, why}
function V.offers(state)
  local out = {}
  state = type(state) == 'table' and state or {}
  local list = type(state.offers) == 'table' and state.offers or {}
  local balance, level = int(state.balance), int(state.level)
  for _, o in ipairs(list) do
    if type(o) == 'table' and type(o.k) == 'string' and o.k ~= '' and #o.k <= 80 then
      local r = { key = o.k, name = str(o.n, o.k), boss = str(o.b, nil), desc = str(o.d, ''), price = math.max(0, int(o.p)),
        weekly = math.max(0, int(o.w)), used = math.max(0, int(o.u)), level = math.max(0, int(o.l)),
        kind = type(o.kind) == 'string' and o.kind or 'item' }
      local cid = int(o.c)
      r.cid = (cid >= 1 and cid <= 65535) and cid or 0
      r.owned = o.own == true
      if r.owned then
        r.why = { 'Owned' }
      elseif r.weekly > 0 and r.used >= r.weekly then
        r.why = { 'Weekly limit reached' }
      elseif level < r.level then
        r.why = { 'Level %d', r.level }
      elseif balance < r.price then
        r.why = { 'Not enough Candlemarks' }
      end
      if not r.why and state.near == false then
        r.why = { V.VISIT }
      end
      r.canBuy = r.why == nil
      out[#out + 1] = r
      if #out >= V.MAX_OFFERS then break end
    end
  end
  return out
end

-- one offer's lines: title (plain), price {pattern}, limit {pattern}
function V.offerLines(r)
  local title = r.boss and (r.name .. ': ' .. r.boss) or r.name
  return {
    title = { '%s', title },
    price = { '%d Candlemarks', r.price },
    limit = r.weekly > 0 and { 'This week: %d of %d', r.used, r.weekly } or { '' },
  }
end

-- the header lines of the window
function V.header(state, since)
  local c = V.counter(state, since)
  local days = math.floor(math.max(0, int(type(state) == 'table' and state.weekEnds or 0) - math.max(0, int(since))) / 86400)
  return {
    balance = { 'Your account has %d Candlemarks', c.balance },
    next = c.earning and { 'Next Candlemark in %d min', V.minutes(c.left) } or V.counterTooltip(c),
    week = days >= 1 and { 'Weekly limits reset in %d days', days } or { 'Weekly limits reset within a day' },
    shop = (type(state) == 'table' and state.near == false) and { V.VISIT } or { 'Osric the Chandler is here: you can buy.' },
  }
end

-- every pattern this file gives to tr() (the pt-BR table must have each; candlemarksview_test.lua checks them)
V.PATTERNS = { '%d Candlemarks (paused)', '%d Candlemarks, next in %d min', WHY.ip, WHY.staff, WHY.level,
  'Not earning right now. Your progress is kept.',
  'One Candlemark for every 30 minutes online, for your account. Click to open the shop.',
  'Weekly limit reached', 'Level %d', 'Not enough Candlemarks', '%d Candlemarks', 'This week: %d of %d',
  'Your account has %d Candlemarks', 'Next Candlemark in %d min', 'Weekly limits reset in %d days',
  'Weekly limits reset within a day', 'Owned', V.VISIT, 'Osric the Chandler is here: you can buy.' }

return V

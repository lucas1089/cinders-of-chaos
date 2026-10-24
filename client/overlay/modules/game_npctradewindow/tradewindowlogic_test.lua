-- luajit tradewindowlogic_test.lua && lua5.3 tradewindowlogic_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tradewindowlogic.lua')
local L = TradeWindowLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local g = L.geometry(1920, 1080, 0)
eq(g.w, 420, 'full width on a big view'); eq(g.h, 520, 'full height on a big view')
eq(g.x, 750, 'centred x'); eq(g.y, 280, 'centred y')
g = L.geometry(1920, 1080, 40)
eq(g.y, 40 + math.floor((1080 - 40 - 520) / 2), 'centred under the menu bar')
g = L.geometry(800, 600, 0)
eq(g.w, 420, 'width fits'); eq(g.h, 520, 'height fits')
g = L.geometry(400, 400, 30)
eq(g.w, 352, 'narrow view: width less the margins'); eq(g.h, 322, 'short view: height less the margins')
eq(g.x >= 0, true, 'x never negative'); eq(g.y >= 30, true, 'y never above the bar')
g = L.geometry(200, 200, 0)
eq(g.w, 300, 'tiny view: minimum width'); eq(g.h, 300, 'tiny view: minimum height'); eq(g.x, 0, 'x clamped at 0')
g = L.geometry(nil, nil, nil)
eq(g.w, 300, 'bad input: minimum'); eq(g.x, 0, 'bad input x')
eq(L.needsFloat(true, false), true, 'shown in a side panel: float')
eq(L.needsFloat(true, true), false, 'already floating')
eq(L.needsFloat(false, false), false, 'hidden: nothing to do')

-- ---------------------------------------------------------------- a currency other than gold
local JSON = {
  azure = { action = 'currency', data = { code = 'AZ', name = 'Azure Coin', item = 26780, amount = 42 } },
  storage = { action = 'currency', data = { code = 'H', name = 'hallowfall coins', amount = 17.9 } },
  again = { action = 'currency', data = { code = 'AZ', name = 'Azure Coin', item = 26780, amount = 12, again = true } },
  long = { action = 'currency', data = { code = 'X', name = 'a very long currency name of the old world', amount = 1 } },
  noname = { action = 'currency', data = { code = 'AZ', amount = 1 } },
  noamount = { action = 'currency', data = { code = 'AZ', name = 'x' } },
  other = { action = 'balance', data = { name = 'x', amount = 1 } },
  negative = { action = 'currency', data = { name = 'x', amount = -5, item = -1 } },
  broken = 'error',
}
local function decode(text)  -- a tiny stand-in for json.decode: the tests hand it tables through a lookup
  local t = JSON[text]
  if t == 'error' then error('bad json') end
  return t
end
local P = function(text) return L.parseCurrency(text, decode) end

local az = P('azure')
eq(az.name, 'Azure Coin', 'item currency: name'); eq(az.item, 26780, 'item currency: item'); eq(az.amount, 42, 'amount')
eq(az.again, false, 'a first packet is not an update'); eq(az.code, 'AZ', 'code')
local st = P('storage')
eq(st.name, 'Hallowfall Coins', 'storage currency: title case'); eq(st.item, nil, 'storage currency: no icon')
eq(st.amount, 17, 'amount is a whole number')
local lg = P('long')
eq(#lg.name <= L.NAME_MAX, true, 'a long name is clipped'); eq(lg.name:sub(-3), '...', 'with dots')
eq(lg.fullName, 'A Very Long Currency Name Of The Old World', 'the whole name stays for the tooltip')
eq(P('again').again, true, 'an update says so')
eq(P('noname'), nil, 'no name: nothing'); eq(P('noamount'), nil, 'no amount: nothing')
eq(P('other'), nil, 'another action: nothing'); eq(P('broken'), nil, 'bad json: nothing')
eq(P('missing'), nil, 'no table: nothing'); eq(L.parseCurrency(nil, decode), nil, 'no text: nothing')
eq(L.parseCurrency('azure', nil), nil, 'no decoder: nothing')
local neg = P('negative'); eq(neg.amount, 0, 'a negative amount is 0'); eq(neg.item, nil, 'a negative item is none')
eq(L.titleCase("dark chocolate coin"), 'Dark Chocolate Coin', 'title case'); eq(L.titleCase("Azure Coin"), 'Azure Coin', 'title case keeps capitals')

-- the pending / active / released life of a currency
local S = L.newState()
eq(L.take(S, 100), nil, 'a gold shop: no currency')
eq(L.receive(S, P('again'), 100), 'ignored', 'a balance without an open window is ignored')
eq(L.take(S, 100), nil, 'and leaves nothing pending')
eq(L.receive(S, nil, 100), 'ignored', 'nothing parsed: ignored')
eq(L.receive(S, P('azure'), 100), 'pending', 'the packet before the shop is pending')
eq(L.take(S, 101).item, 26780, 'the shown window takes it')
eq(L.take(S, 102) == S.active, true, 'a window shown again keeps it')
eq(L.receive(S, P('again'), 110), 'update', 'a balance while the window is open updates it')
eq(S.active.amount, 12, 'the new balance')
L.release(S)
eq(L.take(S, 120), nil, 'a closed window: gold again')
eq(L.receive(S, P('again'), 130), 'ignored', 'a late balance after the close is ignored')
L.receive(S, P('azure'), 200)
eq(L.take(S, 200 + L.CURRENCY_TTL + 1), nil, 'a pending currency that waited too long is dropped')
eq(S.pending, nil, 'and gone')
L.receive(S, P('azure'), 300)
eq(L.take(S, 300 + L.CURRENCY_TTL).amount, 42, 'one still in time is taken')
L.release(S)
L.receive(S, P('azure'), 400)
L.receive(S, P('storage'), 401)
eq(L.take(S, 402).name, 'Hallowfall Coins', 'the last pending packet wins')

-- list rows: whole names and one readable second line
eq(L.rowName('blightwoven armor'), 'blightwoven armor', 'a name that fits stays whole')
eq(L.rowInfo('Price 30', 85, 'oz'), 'Price 30, 85.00 oz', 'price and weight')
eq(L.rowInfo('Price 30', 0, 'oz'), 'Price 30', 'no weight: the price only')
eq(L.rowInfo('Price 15.3k', 110.5, 'oz'), 'Price 15.3k, 110.50 oz', 'a short gold price')
eq(#L.rowName(string.rep('x', 60)) <= L.ROW_NAME_MAX, true, 'a huge name is clipped')
eq(#L.rowInfo('Price ' .. string.rep('9', 60), 1, 'oz') <= L.ROW_INFO_MAX, true, 'a huge line is clipped')
-- the rows of the azure NPC (the stock item names and weights): every one fits whole
for _, row in ipairs({ { 'blightwoven armor', 30, 110 }, { 'blightwoven boots', 30, 11.75 }, { 'ironwrath helmet', 30, 46 },
                       { 'blightwoven sword', 50, 62.5 }, { 'ashborne armor', 30, 85 }, { 'exowing bow', 50, 36.5 } }) do
  eq(L.rowName(row[1]), row[1], 'row name whole: ' .. row[1])
  local info = L.rowInfo('Price ' .. row[2], row[3], 'oz')
  eq(info:sub(-3) ~= '...', true, 'row info whole: ' .. info)
end
-- the Portuguese label is longer than the English one: the line still fits its limit
eq(#L.rowInfo('Preço 50', 110.5, 'oz') <= L.ROW_INFO_MAX, true, 'pt-BR price line fits')

print('npctradewindow tests OK (' .. checks .. ' checks)')
if fails > 0 then os.exit(1) end

-- luajit bank_core_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'bank_core.lua')
local B = BankCore
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

eq(B.OPCODE, 60, 'opcode')

-- typed text
eq(B.digits('3,848'), '3848', 'commas dropped')
eq(B.digits('12a-3 4'), '1234', 'only digits')
eq(B.digits(nil), '', 'nil')
eq(#B.digits(string.rep('9', 30)), B.MAX_DIGITS, 'cut')
eq(B.parse('3848', 5000), 3848, 'parsed')
eq(B.parse('9999', 3848), 3848, 'clamped to the limit')
eq(B.parse('', 3848), 0, 'empty')
eq(B.parse('-5', 3848), 5, 'a minus is not a digit')
eq(B.parse('100', -1), 0, 'a broken limit is 0')
eq(B.parse('100', 0 / 0), 0, 'NaN limit')

-- quick buttons
eq(B.quick(3848, 25), 962, '25%')
eq(B.quick(3848, 50), 1924, '50%')
eq(B.quick(3848, 100), 3848, 'all')
eq(B.quick(3, 25), 0, 'rounded down')
eq(B.quick(2000000000, 50), 1000000000, 'big')
eq(B.quick(nil, 50), 0, 'no limit')

-- limits from the server state {goldCarried, goldBank, starBank, starCarried}
local data = { 3848, 200, 5000, 7 }
eq(B.limit(data, 'gold', 'deposit'), 3848, 'gold deposit: carried')
eq(B.limit(data, 'gold', 'withdraw'), 200, 'gold withdraw: bank')
eq(B.limit(data, 'gold', 'transfer'), 200, 'gold transfer: bank')
eq(B.limit(data, 'star', 'deposit'), 7, 'star deposit: carried')
eq(B.limit(data, 'star', 'withdraw'), 1000, 'star withdraw capped')
eq(B.limit(nil, 'gold', 'deposit'), 0, 'no state')
eq(B.limit({ 'x' }, 'gold', 'deposit'), 0, 'bad state')

-- requests
local a, d = B.request('deposit', 'gold', 962)
eq(a, 'deposit', 'deposit action')
eq(d[1], 'gold', 'currency')
eq(d[2], 962, 'amount')
eq(B.request('withdraw', 'gold', 0), nil, 'zero is not sent')
a, d = B.request('depositAll', 'gold')
eq(a, 'depositAll', 'deposit all: one click, no amount')
eq(#d, 1, 'the server counts the coins')
a, d = B.request('withdrawAll', 'gold')
eq(a, 'withdrawAll', 'withdraw all')
a, d = B.request('transfer', 'gold', 50, '  Cara  ')
eq(a, 'transfer', 'transfer')
eq(d[2], 'Cara', 'name trimmed')
eq(d[3], 50, 'transfer amount')
eq(B.request('transfer', 'gold', 50, ' '), nil, 'no name')
eq(B.request('nonsense', 'gold', 50), nil, 'unknown mode')

eq(B.HEIGHT.transfer > B.HEIGHT.amount, true, 'the transfer dialog is taller')

print(('bank_core_test: %d checks passed'):format(n))

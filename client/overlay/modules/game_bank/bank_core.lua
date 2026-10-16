-- Bank window: the logic without client API (tested by bank_core_test.lua; bank.lua draws).
-- The server (data/scripts/chaos/bank.lua, extended opcode 60) does the maths and checks every amount; this file only
-- keeps the amount dialog's input, slider and quick buttons in step and builds the requests.
BankCore = {}
local B = BankCore

B.OPCODE = 60
B.STAR_WITHDRAW_MAX = 1000 -- Chaos.bank.starWithdrawMax
B.MAX_DIGITS = 10          -- Chaos.bank.maxAmount is 2,000,000,000
B.QUICK = { 25, 50, 100 }  -- the quick buttons, percent of the limit
-- the amount dialog's height: the transfer dialog has the recipient row too (bank.otui BankAmountWindow)
B.HEIGHT = { amount = 186, transfer = 218 }

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then
    return 0
  end
  return math.max(0, math.floor(v))
end

-- the digits of a typed text, at most MAX_DIGITS
function B.digits(text)
  local d = tostring(text or ''):gsub('%D', '')
  return d:sub(1, B.MAX_DIGITS)
end

-- the typed amount, clamped to 0..max
function B.parse(text, max)
  local n = tonumber(B.digits(text)) or 0
  return math.min(n, int(max))
end

-- a quick button's amount: pct of max, rounded down; 100 is all of it
function B.quick(max, pct)
  max = int(max)
  if int(pct) >= 100 then
    return max
  end
  return math.floor(max * int(pct) / 100)
end

-- what the dialog may ask for, from the server's state {goldCarried, goldBank, starBank, starCarried}
-- mode: 'deposit' | 'withdraw' | 'transfer'
function B.limit(data, currency, mode)
  data = type(data) == 'table' and data or {}
  if currency == 'star' then
    if mode == 'deposit' then
      return int(data[4])
    elseif mode == 'withdraw' then
      return math.min(int(data[3]), B.STAR_WITHDRAW_MAX)
    end
    return int(data[3])
  end
  if mode == 'deposit' then
    return int(data[1])
  end
  return int(data[2])
end

-- action, data of the request, or nil when there is nothing to send
function B.request(mode, currency, amount, name)
  amount = int(amount)
  if mode == 'depositAll' or mode == 'withdrawAll' then
    return mode, { currency }
  end
  if amount < 1 then
    return nil
  end
  if mode == 'deposit' or mode == 'withdraw' then
    return mode, { currency, amount }
  end
  if mode == 'transfer' then
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if #name < 2 then
      return nil
    end
    return 'transfer', { currency, name, amount }
  end
  return nil
end

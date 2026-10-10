-- luajit payview_test.lua && lua5.3 payview_test.lua (from the repo root or this folder)
-- The donation window's logic: the voluntary donation notice (English and Portuguese, the same text the server sends,
-- in cp1252), the thank-you after the donation, "Donate" on the buttons, countdown, the Pix code from hex, the QR layout.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'payview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(v, what) if not v then print('FAIL ' .. what); fails = fails + 1 end end
local V = PayView

-- UTF-8 -> cp1252 for the Latin-1 range (what base patch 0028 does to server text)
local function toCp1252(s)
  return (s:gsub('[\194-\195][\128-\191]', function(c)
    local a, b = c:byte(1, 2)
    return string.char((a - 192) * 64 + (b - 128))
  end))
end

-- the notice: present, ASCII source with cp1252 accents, same as the server's
ok(V.NOTICE_EN:find('Voluntary donation', 1, true) and V.NOTICE_EN:find('Nobody is required to donate', 1, true)
  and V.NOTICE_EN:find('fully playable for free', 1, true), 'English notice')
ok(V.NOTICE_PT:find('Doa\231\227o volunt\225ria', 1, true) and V.NOTICE_PT:find('Ningu\233m \233 obrigado a doar', 1, true)
  and V.NOTICE_PT:find('jog\225vel de gra\231a', 1, true), 'Portuguese notice')
local f = io.open(dir .. '../../../../server/data/scripts/chaos/shop_payments_core.lua', 'r')
if f then
  f:close()
  dofile(dir .. '../../../../server/data/scripts/chaos/shop_payments_core.lua')
  eq(V.NOTICE_EN, ChaosPayCore.NOTICE_EN, 'English notice = server')
  eq(V.NOTICE_PT, toCp1252(ChaosPayCore.NOTICE_PT), 'Portuguese notice = server in cp1252')
  local en, pt = ChaosPayCore.thanks(825)
  local cen, cpt = V.thanks(825)
  eq(cen, en, 'thanks = server'); eq(cpt, toCp1252(pt), 'thanks pt = server in cp1252')
else
  print('note: server folder not found, notice compared to the server skipped')
end
for _, s in ipairs({ V.NOTICE_PT, V.NOTICE_EN, (select(2, V.thanks(1))) }) do
  ok(not s:find('[\128-\159]'), 'only Latin-1 letters (cp1252 safe): ' .. s)
end

-- after the donation
local en, pt = V.toast({ coins = 975 })
eq(en, 'Thank you for your voluntary donation! You received 975 Chaos Coins as a thank-you.', 'toast en')
eq(pt, 'Obrigado pela sua doa\231\227o volunt\225ria! Voc\234 recebeu 975 Chaos Coins como agradecimento.', 'toast pt')
eq(V.statusText({ status = 'credited', coins = 975 }), en, 'window success state')
eq(V.statusText({ status = 'expired' }), V.STATUS_TEXT.expired, 'expired text')
eq(V.statusText({ status = 'open', text = 'x' }), 'x', 'server text first')

-- wording
eq(V.donateLabel('R$ 24,95'), 'Donate R$ 24,95', 'Donate button')
ok(not V.donateLabel('x'):lower():find('buy', 1, true), 'no Buy on the button')
eq(V.METHOD_LABEL.paypal, 'PayPal (USD)', 'PayPal label'); eq(V.METHOD_LABEL.pix, 'Pix (BRL)', 'Pix label')
eq(V.packLine({ total = 975, coins = 750, bonus = 75, firstBonus = 150 }), '975 Chaos Coins (750 + 225 bonus)', 'pack line')
eq(V.packLine({ total = 250, coins = 250, bonus = 0, firstBonus = 0 }), '250 Chaos Coins', 'pack line no bonus')
eq(V.packLine({ total = 500, coins = 250, bonus = 250, firstBonus = 0, once = true }), '500 Chaos Coins (250 + 250 bonus), once per account', 'starter line')

-- countdown
eq(V.countdown(1800), '30:00', '30 min'); eq(V.countdown(59), '00:59', 'seconds'); eq(V.countdown(-4), '00:00', 'never negative')
eq(V.countdown(3725), '1:02:05', 'hours')
eq(V.remaining({ remaining = 100 }, 50, 80), 70, 'remaining after 30 s'); eq(V.remaining({ remaining = 10 }, 0, 99), 0, 'not below 0')
eq(V.remaining({}, 0, 0), nil, 'no expiry')

-- Pix code from hex, the QR text
eq(V.fromHex('303030323031'), '000201', 'hex'); eq(V.fromHex('3x'), nil, 'bad hex'); eq(V.fromHex('303'), nil, 'odd hex')
eq(V.qrText({ method = 'pix', qrHex = '414243' }), 'ABC', 'Pix QR text')
eq(V.qrText({ method = 'paypal', url = 'https://example.invalid/a' }), 'https://example.invalid/a', 'PayPal QR text')
ok(V.WAITING.open and V.WAITING.paid and not V.WAITING.credited, 'which statuses are polled')

-- layout
local px, off = V.qrLayout(57, 220)
eq(px, 3, 'module size'); eq(off, 24, 'centred')
px = V.qrLayout(177, 100); eq(px, 1, 'at least one pixel')

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('payview_test: ok')

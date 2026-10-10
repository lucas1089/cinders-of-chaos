-- payview.lua: pure logic of the donation window (pay.lua): texts, countdown, the QR layout, what an order view means.
-- No client API here; tested by payview_test.lua (luajit / lua5.3 from the repo root).
-- Text in this file is ASCII: the Portuguese accents are cp1252 byte escapes (the client draws cp1252; patch 0028
-- converts only server text). The server sends the same notice (shop_payments_core.lua); the test checks they match.

PayView = {}
local V = PayView

-- "Doação voluntária: ajuda a manter o servidor. Ninguém é obrigado a doar; o jogo é totalmente jogável de graça."
V.NOTICE_PT = "Doa\231\227o volunt\225ria: ajuda a manter o servidor. Ningu\233m \233 obrigado a doar; o jogo \233 totalmente jog\225vel de gra\231a."
V.NOTICE_EN = "Voluntary donation: it helps keep the server running. Nobody is required to donate; the game is fully playable for free."
V.THANKS_NOTE = "Chaos Coins are our thank-you for your donation."

function V.thanks(coins)
  coins = tonumber(coins) or 0
  return string.format("Thank you for your voluntary donation! You received %d Chaos Coins as a thank-you.", coins),
    string.format("Obrigado pela sua doa\231\227o volunt\225ria! Voc\234 recebeu %d Chaos Coins como agradecimento.", coins)
end

V.METHOD_LABEL = { pix = "Pix (BRL)", paypal = "PayPal (USD)" }

V.STATUS_TEXT = {
  pending = "Preparing your donation...",
  open = "Waiting for your donation.",
  paid = "Donation received. Your Chaos Coins arrive in a few seconds.",
  credited = "Thank you for your donation!",
  expired = "This donation expired before it was paid. Nothing was charged.",
  cancelled = "This donation was cancelled. Nothing was charged.",
  failed = "The payment service is not available right now. Nothing was charged; try again later.",
  refunded = "This donation was refunded.",
  rejected = "This order could not be credited. Please contact staff."
}

-- statuses the window keeps asking the server about
V.WAITING = { pending = true, open = true, paid = true }

function V.donateLabel(priceText)
  return "Donate " .. tostring(priceText or "")
end

function V.packLine(p)
  local s = string.format("%d Chaos Coins", tonumber(p.total) or 0)
  local extra = (tonumber(p.bonus) or 0) + (tonumber(p.firstBonus) or 0)
  if extra > 0 then
    s = s .. string.format(" (%d + %d bonus)", tonumber(p.coins) or 0, extra)
  end
  if p.once then s = s .. ", once per account" end
  return s
end

function V.countdown(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local h = math.floor(seconds / 3600)
  local m = math.floor(seconds % 3600 / 60)
  local s = seconds % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%02d:%02d", m, s)
end

-- seconds left now, given the view's remaining time and the local clock when it arrived
function V.remaining(view, receivedAt, now)
  if not view or not view.remaining then return nil end
  return math.max(0, view.remaining - math.max(0, (now or receivedAt) - receivedAt))
end

function V.fromHex(hex)
  if type(hex) ~= "string" or #hex % 2 ~= 0 or hex:find("[^0-9a-fA-F]") then return nil end
  return (hex:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
end

-- what the QR code holds: the Pix copy-and-paste code, or the PayPal approval link
function V.qrText(view)
  if not view then return nil end
  if view.method == "pix" then return V.fromHex(view.qrHex) end
  return view.url
end

-- pixel size of one module and the offset that centres the code with a 4-module quiet zone inside `box` pixels
function V.qrLayout(size, box)
  local px = math.max(1, math.floor(box / (size + 8)))
  local used = px * size
  return px, math.floor((box - used) / 2)
end

function V.statusText(view)
  if not view then return "" end
  if view.status == "credited" then
    return (V.thanks(view.coins))
  end
  return view.text or V.STATUS_TEXT[view.status] or ""
end

-- the toast after the server credited a donation
function V.toast(data)
  local en, pt = V.thanks(data and data.coins)
  return en, pt
end

return V

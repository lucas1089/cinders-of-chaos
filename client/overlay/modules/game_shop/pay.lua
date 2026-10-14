-- pay.lua: the donation window of the store (Pix / PayPal). The server (data/scripts/chaos/shop_payments.lua, opcode
-- 218 actions pay_*) decides packs, prices and limits; this window shows them, asks for an order, draws its QR code
-- (qrcode.lua) and waits for the automatic confirmation: it asks pay_status every few seconds while the order is open
-- and the server pushes pay_paid when the coins are credited (toast + balance, no relog). Texts: payview.lua.

local payWindow = nil
local payData = nil          -- the last pay_packs answer
local payMethod = 'pix'
local payOrder = nil         -- the order view on the second page
local payOrderAt = 0         -- g_clock.seconds() when it arrived
local payPollEvent = nil
local payTickEvent = nil
local openedUrlFor = nil
local toastWidget = nil
local toastEvent = nil

local function sendPay(action, data)
  if not g_game.isOnline() then return end
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedJSONOpcode(218, { action = action, data = data or {} })
  end
end

local function stopTimers()
  if payPollEvent then removeEvent(payPollEvent); payPollEvent = nil end
  if payTickEvent then removeEvent(payTickEvent); payTickEvent = nil end
end

-- the refund sentence under the notice: "before" while picking or paying, "after" once paid or credited
local function setTerms(status)
  local en, pt = PayView.terms(status)
  payWindow.termsNote:setText(en)
  payWindow.termsNotePt:setText(pt)
end

local function createPay()
  if payWindow then return end
  payWindow = g_ui.displayUI('pay')
  payWindow:hide()
  payWindow.notice:setText(PayView.NOTICE_EN)
  payWindow.noticePt:setText(PayView.NOTICE_PT)
  payWindow.thanksNote:setText(PayView.THANKS_NOTE)
  setTerms()
end

function showPay()
  createPay()
  payWindow:show()
  payWindow:raise()
  payWindow:focus()
  if not payOrder or not PayView.WAITING[payOrder.status] then
    showPayPacks()
  end
  sendPay('pay_packs')
end

function hidePay()
  stopTimers()
  if payWindow then payWindow:hide() end
end

function destroyPay()
  stopTimers()
  if toastEvent then removeEvent(toastEvent); toastEvent = nil end
  if toastWidget then toastWidget:destroy(); toastWidget = nil end
  if payWindow then payWindow:destroy(); payWindow = nil end
  payData, payOrder, openedUrlFor = nil, nil, nil
end

function showPayPacks()
  if not payWindow then return end
  stopTimers()
  payWindow.orderPage:hide()
  setTerms()
  payWindow.packsPage:show()
  renderPacks()
  if not payData then sendPay('pay_packs') end
end

function selectPayMethod(method)
  payMethod = method
  renderPacks()
end

function renderPacks()
  if not payWindow then return end
  local page = payWindow.packsPage
  page.packList:destroyChildren()
  -- the chosen method is marked > like this <
  page.methodPix:setText(payMethod == 'pix' and '> Pix (BRL) <' or 'Pix (BRL)')
  page.methodPaypal:setText(payMethod == 'paypal' and '> PayPal (USD) <' or 'PayPal (USD)')
  if not payData then
    page.firstBonus:setText(tr('Loading...'))
    return
  end
  local enabled = {}
  for _, m in ipairs(payData.methods or {}) do enabled[m.key] = m end
  page.methodPix:setVisible(enabled.pix ~= nil)
  page.methodPaypal:setVisible(enabled.paypal ~= nil)
  if not enabled[payMethod] then
    local first = (payData.methods or {})[1]
    if not first then
      page.firstBonus:setText(tr('Donations are not open right now.'))
      return
    end
    payMethod = first.key
  end
  if payData.firstOpen and (payData.firstBonusPct or 0) > 0 then
    local cap = tonumber(payData.firstBonusMax) or 0
    page.firstBonus:setText(PayView.firstBonusText(payData.firstBonusPct, cap))
  else
    page.firstBonus:setText('')
  end
  for _, p in ipairs(payData.packs or {}) do
    local price = p.prices and p.prices[payMethod]
    if price then
      local row = g_ui.createWidget('PayPackRow', page.packList)
      row.name:setText(p.name)
      row.line:setText(PayView.packLine(p))
      row.donate:setText(PayView.donateLabel(price.text))
      row.donate:setEnabled(p.available ~= false)
      if p.available == false then row.donate:setTooltip(tr('Already received on this account.')) end
      local key = p.key
      row.donate.onClick = function()
        row.donate:setEnabled(false)
        local code = page.creatorCode and page.creatorCode:getText() or ''
        sendPay('pay_create', { pack = key, method = payMethod, creator = code ~= '' and code or nil })
      end
    end
  end
end

-- ------------------------------------------------------------------ the order page
local function drawQr(text)
  local box = payWindow.orderPage.qrBox
  box:destroyChildren()
  if not text or text == '' then return end
  local qr = ChaosQR.encode(text)
  if not qr then return end
  local px, off = PayView.qrLayout(qr.size, box:getWidth())
  for _, r in ipairs(ChaosQR.runs(qr)) do
    local w = g_ui.createWidget('UIWidget', box)
    w:setPhantom(true)
    w:setBackgroundColor('#000000')
    w:addAnchor(AnchorTop, 'parent', AnchorTop)
    w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    w:setMarginTop(off + (r[1] - 1) * px)
    w:setMarginLeft(off + (r[2] - 1) * px)
    w:setSize({ width = r[3] * px, height = px })
  end
end

local function tick()
  payTickEvent = nil
  if not payWindow or not payOrder then return end
  local left = PayView.remaining(payOrder, payOrderAt, g_clock.seconds())
  local page = payWindow.orderPage
  if payOrder.status == 'open' and left then
    page.countdown:setText(tr('Expires in') .. ' ' .. PayView.countdown(left))
    if left > 0 then payTickEvent = scheduleEvent(tick, 1000) end
  else
    page.countdown:setText('')
  end
end

local function poll()
  payPollEvent = nil
  if not payWindow or not payWindow:isVisible() or not payOrder then return end
  if PayView.WAITING[payOrder.status] then
    sendPay('pay_status', { id = payOrder.id })
    payPollEvent = scheduleEvent(poll, 3000)
  end
end

function showPayOrder(view)
  createPay()
  payOrder = view
  payOrderAt = g_clock.seconds()
  if not payWindow:isVisible() then return end
  payWindow.packsPage:hide()
  local page = payWindow.orderPage
  page:show()
  page.orderTitle:setText(string.format('%s - %d Chaos Coins', view.name or '', tonumber(view.coins) or 0))
  page.orderAmount:setText(string.format('%s: %s', PayView.METHOD_LABEL[view.method] or '', view.price or ''))
  local en, pt = PayView.statusText(view), ''
  if view.status == 'credited' then en, pt = PayView.thanks(view.coins) end
  page.orderStatus:setText(en)
  page.orderStatusPt:setText(pt)
  setTerms(view.status)
  local qrText = view.status == 'open' and PayView.qrText(view) or nil
  drawQr(qrText)
  page.qrBox:setVisible(qrText ~= nil)
  page.code:setText(qrText or '')
  page.code:setVisible(qrText ~= nil)
  page.codeLabel:setVisible(qrText ~= nil)
  page.copyButton:setVisible(qrText ~= nil)
  page.codeLabel:setText(view.method == 'pix' and tr('Pix copy and paste:') or tr('PayPal link:'))
  page.copyButton:setEnabled(qrText ~= nil)
  page.openButton:setVisible(view.method == 'paypal' and view.url ~= nil and view.status == 'open')
  page.cancelOrder:setVisible(view.status == 'pending' or view.status == 'open')
  page.backButton:setVisible(not PayView.WAITING[view.status])
  if view.status == 'open' then
    page.howTo:setText(view.method == 'pix' and
      tr('Scan the code with your bank app, or copy the code into Pix copy and paste. This window updates by itself.') or
      tr('PayPal opened in your browser. You can also scan the code with your phone. This window updates by itself.'))
  else
    page.howTo:setText('')
  end
  -- PayPal: open the approval page in the browser once per order
  if view.method == 'paypal' and view.url and view.status == 'open' and openedUrlFor ~= view.id then
    openedUrlFor = view.id
    scheduleEvent(function() g_platform.openUrl(view.url) end, 50)
  end
  stopTimers()
  tick()
  if PayView.WAITING[view.status] then payPollEvent = scheduleEvent(poll, 3000) end
end

function copyPayCode()
  if not payWindow then return end
  local text = payWindow.orderPage.code:getText()
  if text ~= '' then
    g_window.setClipboardText(text)
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(tr('Copied to the clipboard.'))
    end
  end
end

function openPayUrl()
  if payOrder and payOrder.url then g_platform.openUrl(payOrder.url) end
end

function cancelPayOrder()
  if payOrder then sendPay('pay_cancel', { id = payOrder.id }) end
end

-- ------------------------------------------------------------------ toast after the donation
function showPayToast(data)
  local en, pt = PayView.toast(data)
  if toastEvent then removeEvent(toastEvent); toastEvent = nil end
  if toastWidget then toastWidget:destroy() end
  toastWidget = g_ui.createWidget('PayToast', rootWidget)
  toastWidget.en:setText(en)
  toastWidget.pt:setText(pt)
  toastWidget:setHeight(92)
  toastWidget:addAnchor(AnchorTop, 'parent', AnchorTop)
  toastWidget:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  toastWidget:setMarginTop(90)
  toastWidget:raise()
  toastEvent = scheduleEvent(function()
    toastEvent = nil
    if toastWidget then toastWidget:destroy(); toastWidget = nil end
  end, 9000)
  if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
    modules.game_textmessage.displayGameMessage(en)
  end
end

-- ------------------------------------------------------------------ opcode answers (called by shop.lua)
function onPayAction(action, data)
  createPay()
  if action == 'pay_packs' then
    payData = data
    if data.open and payWindow:isVisible() and not (payOrder and payOrder.id == data.open.id) then
      showPayOrder(data.open)
    elseif payWindow.packsPage:isVisible() then
      renderPacks()
    end
  elseif action == 'pay_order' then
    showPayOrder(data)
  elseif action == 'pay_error' then
    renderPacks()
    if data.order then showPayOrder(data.order) end
    displayInfoBox(tr('Donation'), data.msg or '')
  elseif action == 'pay_paid' then
    showPayToast(data)
    if payOrder and payOrder.id == data.id then
      payOrder.status = 'credited'
      payOrder.coins = data.coins
      showPayOrder(payOrder)
    end
    payData = nil
  elseif action == 'pay_reversal' then
    if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
      modules.game_textmessage.displayGameMessage(data.text or '')
    end
  end
end

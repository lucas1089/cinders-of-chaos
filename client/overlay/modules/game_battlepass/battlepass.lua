-- Season Pass window: the account's season pass (tier, pass XP, free and premium track with Claim buttons), the
-- daily and weekly challenges with the day's pass XP per source, and the Packs page (the premium pass and the season
-- packs: buy, upgrade for the difference, gift to another character). Pure helpers: passview.lua.
-- Server: server/data/scripts/chaos/seasonpass.lua, extended opcode 227 (JSON {action, data}).
--   server -> client  state {open, season = {id, name, tag, status, pass, endsIn, startsIn, claimEndsIn}, tier, maxTier,
--                            xp, into, need, premium, claimed = {free "0101..", premium "..."}, coins,
--                            daily / weekly = {resetIn, list = [{key, text, progress, target, done, xp}]},
--                            sources = [{key, name, today, cap}],
--                            offers = [{what, name, price, why, owned, full, look, contents, text}], frame = {name, on}}
--                     tiers {season, first, last, total, rows = [{tier, cost, free, premium}]}
--                            a reward: {kind, text, item, count, look, addons, color}
--                     giftPrice {what, name, price}     notice {text}
--   client -> server  open | tiers {season} | claim {tier, track} | claimAll | buy {what, price, gift?}
--                     giftPrice {what, gift} | frame {on}
-- The top menu (Adventure > Season Pass) calls toggle(). Tier-up toasts come through game_chaosnotify ("seasonpass").

local OPCODE = 227

local window
local state            -- last state received
local stateAt = 0      -- g_clock.seconds() when it arrived
local tiers            -- PassView.mergeTiers cache
local tiersAsked       -- season id the tiers were asked for
local page = 'rewards'
local tabs = {}
local tickEvent
local box              -- open confirm / input box
local builtSeason      -- season id the tier rows were built for
local rows = {}        -- tier -> row widget
local pendingGift      -- {what, offer} while the server prices a gift

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function closeBox()
  if box then box:destroy() box = nil end
end

local function list(v)
  return type(v) == 'table' and v or {}
end

-- ---------------------------------------------------------------- header
local function updateTimer()
  if not window or not state then return end
  local s = type(state.season) == 'table' and state.season or nil
  local passed = g_clock.seconds() - stateAt
  if not s then
    window.timerLabel:setText('')
  elseif s.status == 'active' then
    window.timerLabel:setText(tr('Season ends in %s', PassView.formatTime(PassView.left(s.endsIn, 0, passed))))
  elseif s.status == 'grace' then
    window.timerLabel:setText(tr('Season over: claim within %s', PassView.formatTime(PassView.left(s.claimEndsIn, 0, passed))))
  elseif s.status == 'upcoming' then
    window.timerLabel:setText(tr('Starts in %s', PassView.formatTime(PassView.left(s.startsIn, 0, passed))))
  else
    window.timerLabel:setText('')
  end
  if state.daily then
    window.challengesPage.dailyTitle:setText(tr('Daily challenges (new in %s)',
      PassView.formatTime(PassView.left(state.daily.resetIn, 0, passed))))
  end
  if state.weekly then
    window.challengesPage.weeklyTitle:setText(tr('Weekly challenges (new in %s)',
      PassView.formatTime(PassView.left(state.weekly.resetIn, 0, passed))))
  end
end

local function tick()
  tickEvent = nil
  if not window or not window:isVisible() then return end
  updateTimer()
  tickEvent = scheduleEvent(tick, 1000)
end

local function showHeader()
  local s = type(state.season) == 'table' and state.season or nil
  local tp = window.tierPanel
  if not s then
    window.nameLabel:setText(tr('Season Pass'))
    tp.tierLabel:setText(tr('No season'))
    tp.trackLabel:setText('')
    tp.xpBar:setPercent(0)
    tp.xpBar:setText(tr('No season pass is running.'))
    tp.claimAllButton:setEnabled(false)
    return
  end
  window.nameLabel:setText(string.format('%s - %s %s', s.pass or '?', s.name or '?', s.tag or ''))
  tp.tierLabel:setText(tr('Tier %d / %d', tonumber(state.tier) or 0, tonumber(state.maxTier) or 0))
  tp.trackLabel:setText(state.premium and tr('Premium track') or tr('Free track'))
  tp.trackLabel:setColor(state.premium and '#ff9a3c' or '#8c8070')
  local pct, text = PassView.progress(state)
  tp.xpBar:setPercent(pct)
  tp.xpBar:setText(text)
  local n = PassView.claimableCount(state)
  tp.claimAllButton:setText(n > 0 and tr('Claim all (%d)', n) or tr('Claim all'))
  tp.claimAllButton:setEnabled(n > 0)
  updateTimer()
end

-- ---------------------------------------------------------------- rewards page
local CELL_TEXT = { claimed = '#6b8f5a', claimable = '#f6cf72', premium = '#8c8070', locked = '#8c8070', closed = '#6b6258' }

local function fillCell(cell, reward, tier, track)
  cell.item:setVisible(false)
  cell.look:setVisible(false)
  cell.badge:setVisible(false)
  if type(reward) ~= 'table' then
    cell.text:setText('')
    cell.claim:setVisible(false)
    return
  end
  if reward.item and tonumber(reward.item) and tonumber(reward.item) > 0 then
    cell.item:setItemId(tonumber(reward.item))
    cell.item:setItemCount(tonumber(reward.count) or 1)
    cell.item:setVisible(true)
  elseif reward.look then
    cell.look:setOutfit({ type = tonumber(reward.look) or 0, head = 78, body = 94, legs = 114, feet = 0,
      addons = tonumber(reward.addons) or 0 })
    cell.look:setVisible(true)
  else
    local glyph = { title = 'T', portal = 'P', frame = 'F', shader = 'S' }
    cell.badge:setText(glyph[reward.kind] or '?')
    if reward.color then cell.badge:setColor(reward.color) end
    cell.badge:setVisible(true)
  end
  cell.text:setText(reward.text or '')
  cell.claim.onClick = function() send('claim', { tier = tier, track = track }) end
end

local function paintRow(row, tier)
  for _, track in ipairs({ PassView.FREE, PassView.PREMIUM }) do
    local cell = track == PassView.FREE and row.free or row.premium
    local st = PassView.cellState(state, tier, track)
    cell.text:setColor(CELL_TEXT[st] or '#d6c9ae')
    cell.claim:setVisible(st == 'claimable' or st == 'claimed')
    cell.claim:setEnabled(st == 'claimable')
    cell.claim:setText(st == 'claimed' and tr('Got it') or tr('Claim'))
    local tip = ({ premium = tr('Premium track: unlock it on the Packs page.'), locked = tr('Reach tier %d first.', tier),
      closed = tr('The claim window of this season is over.') })[st]
    cell:setTooltip(tip or '')
    cell.text:setOpacity(st == 'locked' and 0.6 or 1)
  end
  local reached = tier <= (tonumber(state.tier) or 0)
  row.tier:setColor(reached and '#f6cf72' or '#8c8070')
end

local function buildRows()
  local tp = window.rewardsPage
  if not tiers or not state or not state.season or tiers.season ~= state.season.id then return end
  if builtSeason ~= tiers.season then
    tp.tierList:destroyChildren()
    rows = {}
    for t = 1, tiers.total do
      local r = tiers.rows[t]
      local row = g_ui.createWidget('PassTierRow', tp.tierList)
      row.tier:setText(tostring(t))
      fillCell(row.free, r and r.free, t, PassView.FREE)
      fillCell(row.premium, r and r.premium, t, PassView.PREMIUM)
      rows[t] = row
    end
    builtSeason = tiers.season
    tp.loadingText:setVisible(false)
  end
  for t, row in pairs(rows) do
    paintRow(row, t)
  end
end

local function scrollToCurrent()
  local row = rows[math.max(1, math.min(#rows, (tonumber(state and state.tier) or 0) + 1))]
  if row then window.rewardsPage.tierList:ensureChildVisible(row) end
end

-- ---------------------------------------------------------------- challenges page
local function fillChallenges(listWidget, data)
  listWidget:destroyChildren()
  for _, c in ipairs(list(data and data.list)) do
    local row = g_ui.createWidget('PassChallengeRow', listWidget)
    local text, ptext, pct = PassView.challenge(c)
    row.text:setText(text)
    row.progress:setPercent(pct)
    row.progress:setText(ptext)
    row.reward:setText(tr('+%d XP', tonumber(c.xp) or 0))
    if c.done then row.text:setColor('#6b8f5a') end
  end
end

local function showChallenges()
  local cp = window.challengesPage
  local running = state.daily ~= nil
  cp.closedText:setVisible(not running)
  for _, w in ipairs({ cp.dailyTitle, cp.dailyList, cp.weeklyTitle, cp.weeklyList, cp.sourcesTitle, cp.sourcesLabel }) do
    w:setVisible(running)
  end
  if not running then return end
  fillChallenges(cp.dailyList, state.daily)
  fillChallenges(cp.weeklyList, state.weekly)
  local parts = {}
  for _, s in ipairs(list(state.sources)) do parts[#parts + 1] = PassView.sourceLine(s) end
  cp.sourcesLabel:setText(table.concat(parts, '    '))
end

-- ---------------------------------------------------------------- packs page
local function confirmBuy(offer, price, gift)
  closeBox()
  local what = offer.what
  local text
  if gift then
    text = tr('Give %s to %s for %d Chaos Coins?', offer.name, gift, price)
  elseif price < (tonumber(offer.full) or price) then
    text = tr('Upgrade to %s for %d Chaos Coins (the difference to what your account owns)?', offer.name, price)
  else
    text = tr('Buy %s for %d Chaos Coins?', offer.name, price)
  end
  local function yes()
    closeBox()
    send('buy', { what = what, price = price, gift = gift })
  end
  box = displayGeneralBox(tr('Season Pass'), text, { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = closeBox },
    anchor = AnchorHorizontalCenter }, yes, closeBox)
end

local function askGift(offer)
  closeBox()
  if not displayTextInputBox then return end
  box = displayTextInputBox(tr('Gift %s', offer.name), tr('Character name:'), function(name)
    box = nil
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name ~= '' then
      pendingGift = { what = offer.what, offer = offer }
      send('giftPrice', { what = offer.what, gift = name })
    end
  end, function() box = nil end)
end

local function showPacks()
  local pp = window.packsPage
  pp.coinsLabel:setText(tr('Your Chaos Coins: %d', tonumber(state.coins) or 0))
  local f = state.frame
  pp.frameBox:setVisible(type(f) == 'table')
  if type(f) == 'table' then
    pp.frameBox:setText(tr('Show %s', f.name or ''))
    pp.frameBox.onCheckChange = nil
    pp.frameBox:setChecked(f.on and true or false)
    pp.frameBox.onCheckChange = function(_, on) send('frame', { on = on }) end
  end
  pp.offerList:destroyChildren()
  for _, offer in ipairs(list(state.offers)) do
    local row = g_ui.createWidget('PassOfferRow', pp.offerList)
    row.name:setText(offer.name or '?')
    if offer.look then
      row.look:setOutfit({ type = tonumber(offer.look) or 0, head = 78, body = 94, legs = 114, feet = 0, addons = 3 })
      row.look:setVisible(true)
    elseif tonumber(offer.item) then
      row.item:setItemId(tonumber(offer.item))
      row.item:setVisible(true)
    end
    local contents = offer.text or table.concat(list(offer.contents), ', ')
    if not offer.owned and offer.why and offer.why ~= 'Owned.' then
      contents = contents .. '\n' .. offer.why
    end
    row.contents:setText(contents)
    local text, enabled = PassView.offerButton(offer)
    row.buy:setText(text)
    row.buy:setEnabled(enabled)
    row.buy.onClick = function() confirmBuy(offer, tonumber(offer.price) or 0) end
    local season = type(state.season) == 'table' and state.season or {}
    row.gift:setEnabled(season.status == 'active')
    row.gift.onClick = function() askGift(offer) end
  end
end

-- ---------------------------------------------------------------- pages
local function showPage(name)
  page = name
  for key, tab in pairs(tabs) do tab:setChecked(key == name) end
  window.rewardsPage:setVisible(name == 'rewards')
  window.challengesPage:setVisible(name == 'challenges')
  window.packsPage:setVisible(name == 'packs')
end

local function showState()
  if not window or not state then return end
  showHeader()
  if state.season then
    if not tiers or tiers.season ~= state.season.id then
      if tiersAsked ~= state.season.id then
        tiersAsked = state.season.id
        send('tiers', { season = state.season.id })
      end
    else
      buildRows()
    end
    showChallenges()
    showPacks()
  end
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[season pass] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    local first = state == nil
    -- the parts the window indexes must be tables (game_chaosguard/opcode_fuzz_test.lua)
    for _, k in ipairs({ 'season', 'daily', 'weekly' }) do
      if type(data[k]) ~= 'table' then data[k] = nil end
    end
    state = data
    stateAt = g_clock.seconds()
    showState()
    if data.open then
      show()
      if first or page == 'rewards' then scheduleEvent(scrollToCurrent, 50) end
    end
  elseif msg.action == 'tiers' then
    local complete
    tiers, complete = PassView.mergeTiers(tiers, data)
    if complete then
      builtSeason = nil
      buildRows()
      scheduleEvent(scrollToCurrent, 50)
    end
  elseif msg.action == 'giftPrice' then
    local p = pendingGift
    pendingGift = nil
    if p and p.what == data.what then
      confirmBuy(p.offer, tonumber(data.price) or 0, data.name)
    end
  elseif msg.action == 'notice' then
    if data.text and window and window:isVisible() then
      if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
        modules.game_textmessage.displayFailureMessage(tostring(data.text))
      end
      local hint = window.hintLabel
      hint.defaultText = hint.defaultText or hint:getText()
      hint:setText(tostring(data.text))
      hint:setColor('#f6cf72')
      scheduleEvent(function()
        if window and hint:getText() == tostring(data.text) then
          hint:setText(hint.defaultText)
          hint:setColor('#8c8070')
        end
      end, 6000)
    end
  end
end

-- ---------------------------------------------------------------- window
function claimAll()
  send('claimAll')
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if not tickEvent then tick() end
end

function hide()
  if window then window:hide() end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  closeBox()
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with the state (open), which shows the window
end

function openPage(name)
  showPage(name or 'rewards')
  if not window:isVisible() then send('open') end
end

local function onGameEnd()
  hide()
  state, tiers, tiersAsked, builtSeason, rows = nil, nil, nil, nil, {}
  if window then window.rewardsPage.tierList:destroyChildren() end
end

function init()
  window = g_ui.displayUI('battlepass')
  window:hide()
  local names = { { 'rewards', tr('Rewards') }, { 'challenges', tr('Challenges') }, { 'packs', tr('Packs') } }
  for _, n in ipairs(names) do
    local tab = g_ui.createWidget('PassTab', window.tabs)
    tab:setText(n[2])
    tab.onClick = function() showPage(n[1]) end
    tabs[n[1]] = tab
  end
  showPage('rewards')
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  hide()
  if window then
    window:destroy()
    window = nil
  end
  state, tiers = nil, nil
end

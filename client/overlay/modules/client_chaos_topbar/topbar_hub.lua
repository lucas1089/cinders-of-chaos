-- The top menu as hubs (O550), the widget side: the badges on the bar and the hub window (tabs and cards). The model (which
-- hub, tab and card exist and what state each is in) comes from topbarhublogic.lua; the styles are in topbar_hub.otui;
-- chaos_topbar.lua gives this file the usable entries (host.items) and runs the one a card names (host.run). Any error in
-- here is caught, reported to host.failed and the bar goes back to the text menu (client/MANIFEST.md "Menu hubs").
--
-- host = {
--   parent = function() -> the widget the bar sits on (the window opens on it),
--   items = function() -> the usable entries (see topbarhublogic.lua), admin = function() -> bool,
--   run = function(text) -> true when the entry ran, locked = function(text) (says when a locked one opens),
--   character = function() -> the character name or '', failed = function(err),
--   relayout = function() (the bar's badges changed: the host measures the bar again, topbar_hub.lua asks after a pin),
-- }

ChaosTopBarHub = {}
local Hub = ChaosTopBarHub
local H = ChaosTopBarHubLogic

local host
local model
local win, shade
local openHubId, openTab
local barPanel
local barBadges = {}          -- hub id -> widget
local pinBadges = {}          -- widgets of the pinned entries and the divider (destroyed on a rebuild)
local barSig, winSig
local hintEvent
local pins = {}
local pinsFor

-- ---------------------------------------------------------------- helpers
local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function get(w, id)
  return w and w:recursiveGetChildById(id)
end

local function isPhone()
  return g_app.isMobile and g_app.isMobile() or false
end

local function tx(text)
  local ok, v = pcall(tr, text)
  return ok and type(v) == 'string' and v or text
end

local function palette()
  return ChaosTheme and ChaosTheme.palette or {}
end

local function color(name, fallback)
  return palette()[name] or fallback
end

local function charName()
  local ok, name = pcall(function()
    if g_game and g_game.isOnline and g_game.isOnline() then return g_game.getCharacterName() end
    return ''
  end)
  return ok and type(name) == 'string' and name or ''
end

local function getSetting(key)
  local ok, v = pcall(g_settings.getString, key)
  return ok and type(v) == 'string' and v or ''
end

local function setSetting(key, value)
  pcall(g_settings.set, key, value)
end

local function guard(name, fn)
  return function(...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
      g_logger.warning('[chaos_menu] hubs ' .. name .. ': ' .. tostring(a))
      if host and host.failed then pcall(host.failed, tostring(a)) end
      return nil
    end
    return a, b, c
  end
end

-- the glyph picture: the white cell of the atlas, tinted with the palette (or the given colour)
local function setGlyph(widget, kind, name, tint)
  local atlas = ChaosTopBarGlyphs and ChaosTopBarGlyphs[kind]
  if not atlas or not widget then return end
  local cell = atlas.slots[name] or atlas.slots[ChaosTopBarCards.FALLBACK_GLYPH]
  if not cell then return end
  widget:setWidth(atlas.cell)       -- the glyph widget is as big as the cell it draws (the glyph fills most of the badge)
  widget:setHeight(atlas.cell)
  widget:setImageClip(string.format('%d %d %d %d', cell[1], cell[2], atlas.cell, atlas.cell))
  widget:setImageColor(tint or color('accent2', '#f6cf72'))
end

local function hubName(hub)
  return H.shown(tr, H.hubKey(hub.id), hub.name)
end

local function tabName(hub, tab)
  return H.shown(tr, H.tabKey(hub.id, tab.id), tab.name)
end

local function loadPins()
  pins = H.pinsOrDefault(getSetting(H.pinsSettingKey(charName())))
end

local function savePins()
  setSetting(H.pinsSettingKey(charName()), H.serializePins(pins))
end

-- ---------------------------------------------------------------- the model
local function rebuildModel()
  model = H.build(ChaosTopBarTree, ChaosTopBarCards, host.items(), { admin = host.admin and host.admin() })
  return model
end

local function cardSig(c)
  return table.concat({ c.text, tostring(c.locked), tostring(c.new), tostring(c.count), tostring(c.points), tostring(c.key) }, ',')
end

local function modelSig()
  local parts = { isPhone() and 'p' or 'd', color('accent2', '') }
  for _, hub in ipairs(model.hubs) do
    parts[#parts + 1] = hub.id .. ':' .. tostring(hub.new) .. ':' .. hub.count
  end
  parts[#parts + 1] = '|' .. table.concat(pins, '+')
  for _, c in ipairs(H.pinnedCards(model, pins)) do parts[#parts + 1] = cardSig(c) end
  return table.concat(parts, ';')
end

-- ---------------------------------------------------------------- the hub window
local function windowAlive()
  return alive(win)
end

local function hideHint()
  if hintEvent then removeEvent(hintEvent) hintEvent = nil end
end

local function defaultHint()
  return isPhone() and tx('Tap a card to open it. Press and hold to pin it to the bar.')
    or tx('Click a card to open it. Right-click to pin it to the bar.')
end

local function setHint(text, seconds)
  if not windowAlive() then return end
  local hint = get(win, 'hint')
  if not hint then return end
  hideHint()
  hint:setText(text)
  if seconds then
    hintEvent = scheduleEvent(function()
      hintEvent = nil
      if windowAlive() then get(win, 'hint'):setText(defaultHint()) end
    end, seconds * 1000)
  end
end

local closeHub

local function pinCard(card)
  local list, changed, why = H.togglePin(pins, card.text)
  if not changed then
    setHint(why == 'full' and tx('The bar is full. Unpin one first.') or tx('Could not pin this card.'), 4)
    return
  end
  local added = #list > #pins
  pins = list
  savePins()
  barSig = nil
  -- the bar changed its badges: the host sets the bar's width again (a bar left at its old width squeezes or clips the new
  -- badge), then the bar and the open window follow
  if host.relayout then host.relayout() end
  Hub.refresh()
  setHint(added and tx('Pinned to the bar.') or tx('Removed from the bar.'), 3)
end

local function clickCard(card, keepOpen)
  if card.locked then
    if host.locked then host.locked(card.shown) end
    return
  end
  if not keepOpen then closeHub() end
  host.run(card.shown)
end

-- one card of the tab: the hex badge with the glyph, the name, the line, the chips
local function buildCard(parent, card, index, cardH)
  local w = g_ui.createWidget('ChaosHubCard', parent)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  local x, y = H.cardPos(index, cardH)
  w:setMarginLeft(x)
  w:setMarginTop(y)
  local locked = card.locked ~= nil
  local badge = get(w, 'badge')
  local nameLabel = get(w, 'name')
  local desc = get(w, 'desc')
  local tint = locked and color('menuLocked', '#7a7466') or (card.new and color('menuNew', '#ffd24a') or color('accent2', '#f6cf72'))
  setGlyph(get(w, 'glyph'), 'card', card.glyph, tint)
  if locked then badge:setOpacity(0.45) end

  local shown = tx(card.text)
  local label = tx(card.desc ~= '' and card.desc or '')
  nameLabel:setText(shown)
  nameLabel:setText(H.fit(shown, 114, function(t) nameLabel:setText(t) return nameLabel:getTextSize().width end))
  nameLabel:setColor(locked and color('menuLocked', '#7a7466') or color('menuNormal', '#d6c9ae'))
  desc:setText(label)
  desc:setColor(locked and color('textDisabled', '#6b6258') or color('textDim', '#8c8070'))

  local keyW = get(w, 'key')
  local hasKey = card.key and not locked
  if hasKey then
    keyW:setText(card.key)
    keyW:setWidth(math.max(34, keyW:getTextSize().width + 12))
    keyW:setVisible(true)
  end
  local newW = get(w, 'newChip')
  if card.new and not locked then
    newW:setText(tx('NEW'))
    newW:setColor(color('menuNew', '#ffd24a'))
    newW:setMarginRight(8 + (hasKey and (keyW:getWidth() + 4) or 0))
    newW:setVisible(true)
  end
  if locked then
    get(w, 'lockIcon'):setVisible(true)
    local lockText = get(w, 'lockText')
    lockText:setText(ChaosTopBarUnlocksLogic.unlocksAt(card.locked, tx))
    lockText:setVisible(true)
  end
  -- the red square on the corner of the glyph badge: the applications waiting (Party Finder) or the unspent passive points
  local function shown(v)
    if type(v) == 'string' then return v ~= '' and v or nil end
    return v and v > 0 and v or nil
  end
  local n = shown(card.count) or shown(card.points)
  if n then
    local c = get(w, 'count')
    c:setText(type(n) == 'string' and n or (n > 99 and '99+' or tostring(n)))
    c:setWidth(math.max(16, c:getTextSize().width + 8))
    c:setVisible(true)
  end
  -- the pin mark, from the saved pins (so it is right after a reload)
  if H.isPinned(pins, card.text) then
    local mark = get(w, 'pinMark')
    setGlyph(mark, 'mark', 'pin', color('menuNew', '#ffd24a'))
    mark:setVisible(true)
  end

  local function hoverBadge(hovered)
    if alive(badge) then badge:setImageClip(hovered and '0 24 64 24' or '0 0 64 24') end
  end
  w.onHoverChange = function(_, hovered) hoverBadge(hovered) end
  w.onMouseRelease = function(self, pos, button)
    if not self:containsPoint(pos) then return false end
    if button == MouseRightButton then
      guard('pin', pinCard)(card)
      return true
    end
    if button == MouseLeftButton then
      local shift = g_keyboard and g_keyboard.isShiftPressed and g_keyboard.isShiftPressed()
      guard('card', clickCard)(card, shift and true or false)
      return true
    end
    return false
  end
  return w
end

local function selectTab(hub, tabIndex)
  openTab = tabIndex
  setSetting(H.tabSettingKey(hub.id, charName()), hub.tabs[tabIndex].id)
  winSig = nil
  Hub.refresh()
end

local function fillWindow()
  if not windowAlive() then return end
  local hub = H.findHub(model, openHubId)
  if not hub then closeHub() return end
  if not openTab or not hub.tabs[openTab] then
    openTab = H.pickTab(hub, getSetting(H.tabSettingKey(hub.id, charName())))
  end
  local sigParts = { hub.id, tostring(openTab), isPhone() and 'p' or 'd', table.concat(pins, '+') }
  for _, tab in ipairs(hub.tabs) do
    sigParts[#sigParts + 1] = tab.id .. ':' .. tostring(tab.new) .. ':' .. tab.count
  end
  for _, c in ipairs(hub.tabs[openTab].cards) do sigParts[#sigParts + 1] = cardSig(c) end
  local sig = table.concat(sigParts, ';')
  if sig == winSig then return end
  winSig = sig

  win:setText(hubName(hub))
  local tabsPanel = get(win, 'tabs')
  tabsPanel:destroyChildren()
  local x = 0
  for i, tab in ipairs(hub.tabs) do
    local b = g_ui.createWidget('ChaosHubTab', tabsPanel)
    local name = tabName(hub, tab)
    b:setText(name)
    b:setWidth(math.max(70, b:getTextSize().width + 28))
    b:addAnchor(AnchorTop, 'parent', AnchorTop)
    b:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    b:setMarginLeft(x)
    x = x + b:getWidth() + 2
    b:setChecked(i == openTab)
    if tab.new and i ~= openTab then b:setColor(color('menuNew', '#ffd24a')) end
    b.onClick = function() guard('tab', selectTab)(hub, i) end
  end
  local cardsPanel = get(win, 'cards')
  cardsPanel:destroyChildren()
  local cardH = isPhone() and 76 or H.CARD_H
  for i, card in ipairs(hub.tabs[openTab].cards) do
    buildCard(cardsPanel, card, i, cardH)
  end
  setHint(defaultHint())
end

local function markOpen()
  for id, w in pairs(barBadges) do
    if alive(w) then w:setOn(id == openHubId) end
  end
end

closeHub = function()
  hideHint()
  if alive(shade) then shade:destroy() end
  shade = nil
  if windowAlive() then win:hide() end
  openHubId, openTab, winSig = nil, nil, nil
  markOpen()
end

local function ensureWindow()
  local parent = host.parent()
  if windowAlive() and win:getParent() ~= parent then
    win:destroy()
    win = nil
  end
  if not windowAlive() then
    win = g_ui.createWidget('ChaosHubWindow', parent)
    win.chaosNoMirror = true   -- the cards are made in Lua (glyph pictures, chips): the RmlUi window mirror leaves it in OTUI
    win:hide()
    win.onEscape = function() closeHub() return true end
  end
  return win
end

local function openHub(hubId)
  if host.opened then pcall(host.opened) end   -- the host may ask a module for a fresh count (answered later)
  rebuildModel()
  local hub = H.findHub(model, hubId)
  if not hub then return false end
  if alive(shade) then shade:destroy() end
  shade = nil
  ensureWindow()
  if isPhone() then
    shade = g_ui.createWidget('ChaosHubShade', host.parent())
    shade.onMousePress = function() closeHub() return true end
  end
  openHubId, openTab, winSig = hubId, nil, nil
  fillWindow()
  if shade then shade:raise() end
  win:show()
  win:raise()
  win:focus()
  markOpen()
  return true
end

-- ---------------------------------------------------------------- the bar
local function addBadge(panel, id, glyph, tooltip, tint, onClick)
  local b = g_ui.createWidget('ChaosHubBadge', panel)
  b:setId(id)
  -- a phone badge is 44 px: it draws the card atlas (cells of 40), a desktop one the bar atlas (cells of 32)
  setGlyph(get(b, 'glyph'), isPhone() and 'card' or 'bar', glyph, tint)
  b:setTooltip(tooltip)
  b.onClick = onClick
  return b
end

local function addDot(badge, count)
  if not count or count <= 0 then return end
  local d = g_ui.createWidget('ChaosHubDot', badge)
  d:setText(tostring(math.min(count, 99)))
end

local function buildBar()
  for _, w in pairs(barBadges) do if alive(w) then w:destroy() end end
  for _, w in ipairs(pinBadges) do if alive(w) then w:destroy() end end
  barBadges, pinBadges = {}, {}
  local pinCards = H.pinnedCards(model, pins)
  local pinNo = 0
  for _, it in ipairs(H.barItems(model, pinCards)) do
    if it.kind == 'hub' then
      local hub = it.hub
      local tint = hub.new and color('menuNew', '#ffd24a') or nil
      local b = addBadge(barPanel, 'chaosHub_' .. hub.id, hub.glyph, hubName(hub), tint, function()
        guard('toggle', Hub.toggle)(hub.id)
      end)
      addDot(b, hub.count)
      barBadges[hub.id] = b
    elseif it.kind == 'divider' then
      pinBadges[#pinBadges + 1] = g_ui.createWidget('ChaosHubDivider', barPanel)
    else
      local card = it.card
      pinNo = pinNo + 1
      local locked = card.locked ~= nil
      local tip = tx(card.text) .. (card.key and ('  (' .. card.key .. ')') or '')
      if locked then tip = ChaosTopBarUnlocksLogic.unlocksAt(card.locked, tx) end
      local tint = locked and color('menuLocked', '#7a7466') or color('menuNew', '#ffd24a')
      local b = addBadge(barPanel, 'chaosPin_' .. pinNo, card.glyph, tip, tint, function()
        guard('pin', function()
          closeHub()
          if locked then if host.locked then host.locked(card.shown) end else host.run(card.shown) end
        end)()
      end)
      pinBadges[#pinBadges + 1] = b
    end
  end
  markOpen()
end

-- ---------------------------------------------------------------- the calls chaos_topbar.lua makes
function Hub.init(h)
  host = h
  openHubId, openTab, barSig, winSig, pinsFor = nil, nil, nil, nil, nil
end

-- puts the badges into the bar's panel; returns the bar width the badges need (nil when nothing is to show)
function Hub.layoutBar(panel)
  return guard('layoutBar', function(p)
    barPanel = p
    local who = charName()
    if who ~= pinsFor then
      pinsFor = who
      loadPins()
      barSig = nil
    end
    rebuildModel()
    local sig = modelSig()
    if sig ~= barSig or (next(barBadges) == nil and #model.hubs > 0) then
      buildBar()
      barSig = sig
    end
    if openHubId then fillWindow() end    -- a count changed (unspent points, applications): the open hub follows
    return H.barWidth(H.barItems(model, H.pinnedCards(model, pins)), isPhone() and 44 or 32)
  end)(panel)
end

-- the entries changed (unlocks, a count, a window): the open hub follows
function Hub.refresh()
  guard('refresh', function()
    if not host or not barPanel then return end
    rebuildModel()
    local sig = modelSig()
    if sig ~= barSig then
      buildBar()
      barSig = sig
    end
    if openHubId then
      if H.findHub(model, openHubId) then fillWindow() else closeHub() end
    end
  end)()
end

function Hub.open(hubId)
  return guard('open', openHub)(hubId) == true
end

function Hub.close()
  guard('close', closeHub)()
end

function Hub.toggle(hubId)
  if openHubId == hubId and windowAlive() and win:isVisible() then
    closeHub()
    return false
  end
  return openHub(hubId)
end

-- takes the badges off the bar (the text menu is on, or the hubs failed)
function Hub.clearBar()
  for _, w in pairs(barBadges) do if alive(w) then w:destroy() end end
  for _, w in ipairs(pinBadges) do if alive(w) then w:destroy() end end
  barBadges, pinBadges, barSig = {}, {}, nil
end

function Hub.isOpen()
  return openHubId ~= nil
end

function Hub.openId()
  return openHubId
end

-- the hub that holds an entry text (for a check or a screenshot)
function Hub.hubOf(text)
  if not model then return nil end
  local _, hub = H.findCard(model, text)
  return hub and hub.id or nil
end

function Hub.terminate()
  hideHint()
  if alive(shade) then shade:destroy() end
  if windowAlive() then win:destroy() end
  for _, w in pairs(barBadges) do if alive(w) then w:destroy() end end
  for _, w in ipairs(pinBadges) do if alive(w) then w:destroy() end end
  win, shade, barBadges, pinBadges, barPanel, model, host = nil, nil, {}, {}, nil, nil, nil
  openHubId, openTab, barSig, winSig, pinsFor = nil, nil, nil, nil, nil
end

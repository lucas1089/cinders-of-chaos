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
local F = ChaosTopBarFindLogic

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
local favs = {}               -- the favourite card texts of this character (O718)
local favsFor
local searchWin               -- the search window (O718)
local searchQuery = ''
local searchFirst             -- the card Enter opens
local keyHandler

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

local function loadFavs()
  favs = F.parseFavs(getSetting(F.favsSettingKey(charName())))
end

local function saveFavs()
  setSetting(F.favsSettingKey(charName()), F.serializeFavs(favs))
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

local function searchAlive()
  return alive(searchWin)
end

-- the window a hint is written to: the search window while it is open, else the hub window
local function hintWindow()
  if openHubId == F.SEARCH_HUB and searchAlive() then return searchWin end
  if windowAlive() then return win end
  return nil
end

local function hideHint()
  if hintEvent then removeEvent(hintEvent) hintEvent = nil end
end

local function defaultHint()
  return isPhone() and tx('Tap a card to open it. Press and hold to pin it to the bar.')
    or tx('Click a card to open it. Right-click to pin it to the bar.')
end

local searchHint

local function setHint(text, seconds)
  local w = hintWindow()
  if not w then return end
  local hint = get(w, 'hint')
  if not hint then return end
  hideHint()
  hint:setText(text)
  if seconds then
    hintEvent = scheduleEvent(function()
      hintEvent = nil
      local again = hintWindow()
      if again then get(again, 'hint'):setText(openHubId == F.SEARCH_HUB and searchHint() or defaultHint()) end
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

local fillSearch

-- redraws what is open after a favourite changed
local function redrawOpen()
  winSig = nil
  if openHubId == F.SEARCH_HUB then
    if fillSearch then fillSearch() end
  elseif openHubId then
    Hub.refresh()
  end
end

local function toggleFav(card)
  local list, changed = F.toggleFav(favs, card.text)
  if not changed then
    setHint(tx('Favourites are full. Remove one first.'), 4)
    return
  end
  local added = #list > #favs
  favs = list
  saveFavs()
  redrawOpen()
  setHint(added and tx('Added to favourites.') or tx('Removed from favourites.'), 3)
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

  -- the favourite star: filled and gold when it is one, an outline when not; a click toggles it
  local star = get(w, 'favStar')
  local isFav = F.isFav(favs, card.text)
  setGlyph(star, 'mark', isFav and 'starsolid' or 'starline', isFav and color('menuNew', '#ffd24a') or color('textDisabled', '#6b6258'))
  star:setTooltip(isFav and tx('Remove from favourites') or tx('Add to favourites'))
  star.onMouseRelease = function(self, pos, button)
    if button ~= MouseLeftButton or not self:containsPoint(pos) then return false end
    guard('favourite', toggleFav)(card)
    return true
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

-- the text of page p of the Favourites tabs: its own name when one page is enough
local function pageName(p, pages)
  if pages <= 1 then return tx('Favourites') end
  local ok, v = pcall(tr, 'Page %d / %d', p, pages)
  return ok and type(v) == 'string' and v or tostring(p)
end

-- the hub the window shows: a hub of the model, or the Favourites as a virtual hub (its tabs are pages of 8 cards)
local function currentHub()
  if openHubId == F.FAV_HUB then return F.favHub(model, favs, tx('Favourites'), pageName) end
  return H.findHub(model, openHubId)
end

local function selectTab(hub, tabIndex)
  openTab = tabIndex
  setSetting(H.tabSettingKey(hub.id, charName()), hub.tabs[tabIndex].id)
  winSig = nil
  Hub.refresh()
end

local function fillWindow()
  if not windowAlive() then return end
  local hub = currentHub()
  if not hub then closeHub() return end
  if not openTab or not hub.tabs[openTab] then
    openTab = H.pickTab(hub, getSetting(H.tabSettingKey(hub.id, charName())))
  end
  local shownTab = hub.tabs[openTab]       -- nil for an empty Favourites
  local sigParts = { hub.id, tostring(openTab), isPhone() and 'p' or 'd', table.concat(pins, '+'), '|' .. table.concat(favs, '+') }
  for _, tab in ipairs(hub.tabs) do
    sigParts[#sigParts + 1] = tab.id .. ':' .. tostring(tab.new) .. ':' .. tab.count
  end
  for _, c in ipairs(shownTab and shownTab.cards or {}) do sigParts[#sigParts + 1] = cardSig(c) end
  local sig = table.concat(sigParts, ';')
  if sig == winSig then return end
  winSig = sig

  win:setText(openHubId == F.FAV_HUB and hub.name or hubName(hub))
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
  for i, card in ipairs(shownTab and shownTab.cards or {}) do
    buildCard(cardsPanel, card, i, cardH)
  end
  if not shownTab then
    -- an empty Favourites: one line saying how to fill it
    local empty = g_ui.createWidget('ChaosHubCardText', cardsPanel)
    empty:addAnchor(AnchorTop, 'parent', AnchorTop)
    empty:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    empty:addAnchor(AnchorRight, 'parent', AnchorRight)
    empty:setMarginTop(24)
    empty:setTextAlign(AlignCenter)
    empty:setTextWrap(true)
    empty:setHeight(40)
    empty:setText(tx('No favourites yet. Click the star on a card to add it here.'))
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
  if searchAlive() then searchWin:hide() end
  searchQuery, searchFirst = '', nil
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
  if hubId ~= F.FAV_HUB and not H.findHub(model, hubId) then return false end
  if alive(shade) then shade:destroy() end
  shade = nil
  if searchAlive() then searchWin:hide() end
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

-- ---------------------------------------------------------------- the search window (O718)
searchHint = function()
  return tx('Enter opens the first result.')
end

local function searchContext()
  return { tr = tr, keywords = ChaosTopBarKeywords and ChaosTopBarKeywords.WORDS or {}, cards = ChaosTopBarCards }
end

-- draws the cards that match the query (all hubs and tabs of the model), the first one marked as the one Enter opens
fillSearch = function()
  if not searchAlive() or not model then return end
  local results = get(searchWin, 'results')
  results:destroyChildren()
  searchFirst = nil
  local list, total = F.search(model, searchQuery, searchContext(), F.MAX_RESULTS)
  local cardH = isPhone() and 76 or H.CARD_H
  for i, r in ipairs(list) do
    local w = buildCard(results, r.card, i, cardH)
    if i == 1 then
      searchFirst = r.card
      local badge = get(w, 'badge')
      if alive(badge) then badge:setImageClip('0 24 64 24') end
    end
  end
  local hint = get(searchWin, 'hint')
  hideHint()
  if #F.words(searchQuery) == 0 then
    hint:setText(tx('Type a name, a word or a hotkey. Enter opens the first result.'))
  elseif #list == 0 then
    hint:setText(tx('Nothing found. Try another word.'))
  elseif total > #list then
    hint:setText(tx('These are the best results. Type more to narrow it.'))
  else
    hint:setText(searchHint())
  end
end

local function openFirstResult()
  local card = searchFirst
  if card then clickCard(card, false) end
end

local function ensureSearchWindow()
  local parent = host.parent()
  if searchAlive() and searchWin:getParent() ~= parent then
    searchWin:destroy()
    searchWin = nil
  end
  if not searchAlive() then
    searchWin = g_ui.createWidget('ChaosHubSearchWindow', parent)
    searchWin.chaosNoMirror = true   -- the cards are made in Lua: the RmlUi window mirror leaves it in OTUI
    searchWin:hide()
    searchWin:setText(tx('Search'))
    searchWin.onEscape = function() closeHub() return true end
    local query = get(searchWin, 'query')
    query.onTextChange = function(_, text)
      searchQuery = type(text) == 'string' and text or ''
      guard('search', fillSearch)()
    end
    if g_keyboard and g_keyboard.bindKeyDown then
      pcall(g_keyboard.bindKeyDown, 'Enter', function() guard('enter', openFirstResult)() return true end, query)
    end
  end
  return searchWin
end

local function openSearch()
  if host.opened then pcall(host.opened) end
  rebuildModel()
  if alive(shade) then shade:destroy() end
  shade = nil
  if windowAlive() then win:hide() end
  ensureSearchWindow()
  if isPhone() then
    shade = g_ui.createWidget('ChaosHubShade', host.parent())
    shade.onMousePress = function() closeHub() return true end
  end
  openHubId, openTab, winSig = F.SEARCH_HUB, nil, nil
  searchQuery = ''
  local query = get(searchWin, 'query')
  query:setText('')
  fillSearch()
  if shade then shade:raise() end
  searchWin:show()
  searchWin:raise()
  searchWin:focus()
  query:focus()
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

local TOOL_IDS = { F.FAV_HUB, F.SEARCH_HUB }   -- the badges after the pins: Favourites, Search

-- the tools show once there is more than the System hub to look through (not on the login screen)
local function barTools()
  return #model.hubs > 1 and TOOL_IDS or {}
end

local function buildBar()
  for _, w in pairs(barBadges) do if alive(w) then w:destroy() end end
  for _, w in ipairs(pinBadges) do if alive(w) then w:destroy() end end
  barBadges, pinBadges = {}, {}
  local pinCards = H.pinnedCards(model, pins)
  local pinNo = 0
  for _, it in ipairs(H.barItems(model, pinCards, barTools())) do
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
    elseif it.kind == 'tool' then
      local isSearch = it.id == F.SEARCH_HUB
      local tip = isSearch and (tx('Search windows and functions') .. '  (' .. F.HOTKEY .. ')') or tx('Favourites')
      local toolId = it.id
      local b = addBadge(barPanel, 'chaosTool_' .. toolId, isSearch and 'magnifier' or 'starsolid', tip, nil, function()
        guard('tool', Hub.toggleTool)(toolId)
      end)
      barBadges[toolId] = b
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

-- the hotkey (F.HOTKEY): only while the hub bar is on screen
local function bindKey()
  if keyHandler or not (g_keyboard and g_keyboard.bindKeyDown) then return end
  keyHandler = function()
    if not host or not barPanel or next(barBadges) == nil then return false end
    guard('hotkey', Hub.toggleTool)(F.SEARCH_HUB)
    return true
  end
  pcall(g_keyboard.bindKeyDown, F.HOTKEY, keyHandler)
end

local function unbindKey()
  if keyHandler and g_keyboard and g_keyboard.unbindKeyDown then pcall(g_keyboard.unbindKeyDown, F.HOTKEY, keyHandler) end
  keyHandler = nil
end

-- ---------------------------------------------------------------- the calls chaos_topbar.lua makes
function Hub.init(h)
  host = h
  openHubId, openTab, barSig, winSig, pinsFor, favsFor = nil, nil, nil, nil, nil, nil
  bindKey()
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
    if who ~= favsFor then
      favsFor = who
      loadFavs()
      winSig = nil
    end
    rebuildModel()
    local sig = modelSig()
    if sig ~= barSig or (next(barBadges) == nil and #model.hubs > 0) then
      buildBar()
      barSig = sig
    end
    if openHubId == F.SEARCH_HUB then
      fillSearch()                        -- a count or an unlock changed: the results follow
    elseif openHubId then
      fillWindow()                        -- a count changed (unspent points, applications): the open hub follows
    end
    return H.barWidth(H.barItems(model, H.pinnedCards(model, pins), barTools()), isPhone() and 44 or 32)
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
    if openHubId == F.SEARCH_HUB then
      fillSearch()
    elseif openHubId then
      if openHubId == F.FAV_HUB or H.findHub(model, openHubId) then fillWindow() else closeHub() end
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

-- Favourites and Search are toggled like a hub (the same badge turns on while one is open)
function Hub.toggleTool(id)
  if openHubId == id and (windowAlive() and win:isVisible() or searchAlive() and searchWin:isVisible()) then
    closeHub()
    return false
  end
  if id == F.SEARCH_HUB then return openSearch() end
  return openHub(id)
end

function Hub.openSearch()
  return guard('openSearch', openSearch)() == true
end

function Hub.openFavourites()
  return guard('openFavourites', openHub)(F.FAV_HUB) == true
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
  if searchAlive() then searchWin:destroy() end
  unbindKey()
  for _, w in pairs(barBadges) do if alive(w) then w:destroy() end end
  for _, w in ipairs(pinBadges) do if alive(w) then w:destroy() end end
  win, shade, searchWin, barBadges, pinBadges, barPanel, model, host = nil, nil, nil, {}, {}, nil, nil, nil
  searchQuery, searchFirst = '', nil
  openHubId, openTab, barSig, winSig, pinsFor, favsFor = nil, nil, nil, nil, nil, nil
end

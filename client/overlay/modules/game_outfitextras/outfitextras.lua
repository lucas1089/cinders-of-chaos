-- Customise Character (O421; owner 2026-11-06). One window in place of the base Outfit window (game_outfit), which this
-- module retires: its handler of the server's outfit window packet is disconnected and this module's takes the packet.
--   Left   the large look preview (game_lookpreview) with a checkbox per layer (outfit, mount, wings, aura, shader,
--          outline, pet), the colour palette (tabs Head / Primary / Secondary / Detail) and the Addon 1 / Addon 2 boxes
--   Right  a search box over the card grid of one category; the card in use is marked, a card under the mouse is
--          previewed, a click picks it (a locked card is shown on the character for a few seconds instead)
--   Bottom the Equipped now strip: one card per slot with the current choice and its picture; a click shows its category
-- Outfit, mount, aura and shader come from the packet and the wardrobe catalogue (game_unlocks); wings, outline,
-- footprints, kill effect, loot label, chat colour, spell effect, plate frame and pet from the modules that already
-- hold them (game_cosmetics 225, game_pets 254, game_chaosinfo 237). The outfit goes out through g_game.changeOutfit
-- with Ok, the cosmetics through the same calls the other windows use (selectCosmetic, usePlateFrame, summonSpecies /
-- dismiss). No protocol change. The rules are customisecore.lua (customisecore_test.lua) and outfitextrascore.lua.
-- Not here: health bar, mana bar, ornament and title (nothing in the client or the server backs them), outfit presets
-- and the random mount of the base window.
-- API (modules.game_outfitextras):
--   accept() / cancel()   the Ok and Cancel buttons
--   clearSearch()         the x beside the search box
--   onData(source)        a source ('cosmetics' | 'pets' | 'services' | 'wardrobe') has a new state

local C = CustomiseCore
local E = OutfitExtrasCore

local FX_ICONS = '/modules/game_cosmetics/images/fx'
local PRINTS = '/modules/game_cosmeticfx/images/prints/'
local GOLD, IRON = '#e8b84a', '#3a3339'
local BATCH = 24 -- cards made per tick (an outfit list can hold hundreds)

local window, preview
local packet            -- the outfit window packet: {outfit, outfits, mounts, wings, auras, shaders}
local temp, original    -- the outfit being edited, as it was
local chosen, layers, touched = {}, {}, {}
local category, searchText, colorTab = 'outfit', '', 'head'
local lists, src, rows = {}, {}, {}  -- the display lists, the extras' sources and rows, as last read
local cardList = {}     -- grid: {widget, key, card}
local stripCards = {}   -- slot key -> strip card widget
local palette, tabButtons, layerBoxes = {}, {}, {}
local selectedCell
local cardToken, searchEvent, redrawEvent = 0, nil, nil
local syncing, muteSearch = false, false
local mobile = false
local retired = false
local pickCard -- forward: a card's click handler

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function warn(where, err)
  g_logger.warning('[outfitextras] ' .. where .. ': ' .. tostring(err))
end

local function child(id)
  return alive(window) and window:recursiveGetChildById(id) or nil
end

local function unlocks()
  local m = modules.game_unlocks
  return m and m.UnlocksCore and m or nil
end

local function shaderLogic()
  local m = modules.game_chaosshaders
  return m and m.OutfitShaderList or nil
end

local function lookModule()
  local m = modules.game_lookpreview
  return m and m.LookPreviewCore and m or nil
end

-- ---------------------------------------------------------------- the base window
-- game_outfit connects its create() to the packet; this window takes over, so that handler goes. It is looked for again
-- at every open and game start (the module order is not known at load), and a base window that was built first is
-- destroyed.
local function baseWindowOpen()
  for _, w in ipairs(g_ui.getRootWidget():getChildren()) do
    if w.appearance and w.ScrollBar and w.preview and w.preview.previewoutfit then return true end
  end
  return false
end

local function retireBase(destroyOpen)
  local o = modules.game_outfit
  if not o or type(o.create) ~= 'function' then return end
  if not retired then
    local ok = pcall(disconnect, g_game, { onOpenOutfitWindow = o.create })
    retired = ok
  end
  if destroyOpen and type(o.destroy) == 'function' and baseWindowOpen() then
    pcall(o.destroy)
    pcall(g_client.setInputLockWidget)
  end
end

-- ---------------------------------------------------------------- the packet
local function listOf(v) return type(v) == 'table' and v or {} end

-- the 10.98 packet gives each aura as {clientId, name}; the lists here read {id, category, clientId, name}
local function auraEntries(list)
  local out = {}
  for i, a in ipairs(listOf(list)) do
    if type(a) == 'table' then
      if a[3] == nil and type(a[2]) == 'string' then a = { a[1], 0, a[1], a[2] } end
      out[#out + 1] = a
    end
  end
  return out
end

-- (currentOutfit, outfitList, mountList, familiarList, wingList, auraList, shaderList, ...): the shaders are the
-- first list from the seventh value on that holds named entries
local function readPacket(...)
  local n = select('#', ...)
  local a = { ... }
  if type(a[1]) ~= 'table' then return nil end
  local OSL = shaderLogic()
  local shaders = {}
  if OSL then
    for i = 7, n do
      local entries = OSL.entries(a[i])
      if #entries > 0 then shaders = entries break end
    end
  end
  return { outfit = a[1], outfits = listOf(a[2]), mounts = listOf(a[3]), wings = listOf(a[5]), auras = auraEntries(a[6]),
    shaders = shaders }
end

local function readOutfit(o)
  local t = C.copy(o)
  for _, k in ipairs({ 'type', 'head', 'body', 'legs', 'feet', 'addons', 'mount', 'wings', 'aura' }) do
    t[k] = tonumber(t[k]) or 0
  end
  t.shader = type(t.shader) == 'string' and t.shader or ''
  return t
end

-- ---------------------------------------------------------------- data
local function sources()
  local s = {}
  local c = modules.game_cosmetics
  if c and type(c.getState) == 'function' then s.cosmetics = c.getState() end
  local p = modules.game_pets
  if p and type(p.getState) == 'function' then s.pets = p.getState() end
  local i = modules.game_chaosinfo
  if i and type(i.getServices) == 'function' then s.services = i.getServices() end
  local u = unlocks()
  local wardrobe = u and type(u.wardrobe) == 'function' and u.wardrobe() or nil
  s.wings = { stock = packet and packet.wings, wardrobe = wardrobe and wardrobe.wings or nil, current = temp and temp.wings }
  return s
end

-- the stock lists plus the catalogue's locked entries (the rule of every list: game_unlocks)
local function displayLists()
  local u = unlocks()
  local OSL = shaderLogic()
  local function full(kind, stock)
    if not u then return stock end
    local w = type(u.wardrobe) == 'function' and u.wardrobe() or nil
    return u.UnlocksCore.display(kind, stock, w and w[kind] or nil, kind == 'shader' and OSL and OSL.label or nil)
  end
  return { outfit = full('outfit', packet.outfits), mount = full('mount', packet.mounts), aura = full('aura', packet.auras),
    shader = full('shader', packet.shaders) }
end

local function readData()
  lists, src = displayLists(), sources()
  rows = E.rows(src)
  -- the layers of the extras start from what the character wears, once their data is there and until touched
  local d = C.layerDefaults(original, rows)
  for _, k in ipairs({ 'outline', 'pet' }) do
    if not touched[k] then layers[k] = d[k] end
  end
end

local function values() return C.values(temp, rows, chosen, layers) end

local function onlyMine()
  local u = unlocks()
  return u and type(u.onlyMine) == 'function' and u.onlyMine(category) == true or false
end

local function ask()
  local c = modules.game_cosmetics
  if c and type(c.requestState) == 'function' then c.requestState() end
  local p = modules.game_pets
  if p and type(p.requestState) == 'function' then p.requestState() end
  local i = modules.game_chaosinfo
  if i and type(i.requestServices) == 'function' then i.requestServices() end
end

-- ---------------------------------------------------------------- pictures
-- spec = {kind = 'outfit', outfit} | {kind = 'play', row} | {kind = 'print', art} | nil, on a card's creature / icon
local function paint(w, spec, boxW, boxH, iconSize)
  local box = w:getChildById('pic') or w
  local cr, ic = box:getChildById('creature'), box:getChildById('icon')
  if not cr or not ic then return end
  cr:setVisible(false)
  ic:setVisible(false)
  pcall(ic.destroyChildren, ic)
  pcall(ic.setImageSource, ic, '')
  if type(spec) ~= 'table' then return end
  if spec.kind == 'outfit' then
    local ok = pcall(cr.setOutfit, cr, spec.outfit)
    if not ok then return end
    local lp = lookModule()
    if lp and type(lp.fitCard) == 'function' then lp.fitCard(cr, spec.outfit, boxW, boxH) end
    cr:setVisible(true)
  elseif spec.kind == 'play' then
    local lp = lookModule()
    local effect = lp and type(spec.row) == 'table' and type(spec.row.play) == 'table' and lp.LookPreviewCore.mainEffect(spec.row.play)
    if effect and lp.effectIcon(ic, effect, iconSize, FX_ICONS) then ic:setVisible(true) end
  elseif spec.kind == 'print' and type(spec.art) == 'string' and spec.art:match('^[%w_]+$') then
    ic:setImageSource(PRINTS .. spec.art)
    ic:setVisible(true)
  end
end

local function specOf(key, card)
  local look = C.cardLook(key, card, temp)
  if look then return { kind = 'outfit', outfit = look } end
  if card.row and (key == 'spellskin' or key == 'killfx') then return { kind = 'play', row = card.row } end
  if card.row and key == 'footprint' and not card.none and type(card.row.art) == 'string' then
    return { kind = 'print', art = card.row.art }
  end
  return nil
end

-- ---------------------------------------------------------------- preview
local function outlineNow()
  return C.outlineOption(rows, values(), layers)
end

local function updatePreview()
  if not preview then return end
  local ok, err = pcall(function()
    preview:setOwnOutfit(C.shown(temp, layers))
    preview:setOption(outlineNow())
  end)
  if not ok then warn('preview', err) end
end

-- the pet stands beside the character while its layer is on (the shared panel draws one creature)
local function updatePet()
  local view = child('petView')
  if not view then return end
  local look = 0
  local v = values()
  for _, r in ipairs(rows) do
    if r.key == 'pet' then
      for _, o in ipairs(r.options) do
        if o.value == v.pet then look = tonumber(o.look) or 0 end
      end
    end
  end
  if layers.pet and look > 0 then
    pcall(view.setOutfit, view, { type = look })
    view:setVisible(true)
  else
    view:setVisible(false)
  end
end

local function onCardHover(key, card, hovered)
  if not preview then return end
  if hovered then
    local opt = C.hoverOption(temp, layers, key, card, outlineNow())
    if opt then preview:setHover(opt) else preview:clearHover() end
  else
    preview:clearHover()
  end
end

-- ---------------------------------------------------------------- strip, layers, colours, addons
local function updateStrip()
  local list = C.stripRows({ temp = temp, lists = lists, src = src, rows = rows, chosen = chosen, layers = layers })
  for _, r in ipairs(list) do
    local w = stripCards[r.key]
    if alive(w) then
      w:getChildById('slot'):setText(r.label)
      w:getChildById('name'):setText(r.name)
      w:setTooltip(r.name == '-' and r.label or (r.label .. ': ' .. r.name))
      if mobile then paint(w, nil, 0, 0, 0) else paint(w, r.icon, 44, 40, 32) end
      w:setBorderColor(r.key == category and GOLD or IRON)
      w:setBorderWidth(r.key == category and 2 or 1)
    end
  end
end

local function updateLayers()
  syncing = true
  for key, box in pairs(layerBoxes) do
    if alive(box) then box:setChecked(layers[key] == true) end
  end
  syncing = false
end

local function updateColors()
  if alive(selectedCell) then
    selectedCell:setBorderColor('#00000080')
    selectedCell:setBorderWidth(1)
  end
  local field = C.fieldOf(colorTab)
  local cell = field and palette[tonumber(temp[field]) or 0] or nil
  if alive(cell) then
    cell:setBorderColor('#ffffff')
    cell:setBorderWidth(2)
    selectedCell = cell
  end
  for key, b in pairs(tabButtons) do
    if alive(b) then b:setChecked(key == colorTab) end
  end
end

-- the addon boxes follow the addons the character owns for the outfit worn
local function updateAddons()
  local bits = 0
  for _, c in ipairs(C.lookCards('outfit', lists.outfit)) do
    if c.value == temp.type and not c.locked then bits = c.addons or 0 end
  end
  syncing = true
  for _, a in ipairs({ 1, 2 }) do
    local box = child('addon' .. a)
    if alive(box) then
      local owned = C.addonOwned(bits, a)
      box:setEnabled(owned)
      box:setChecked(owned and C.addonOwned(temp.addons, a))
    end
  end
  syncing = false
end

local function markCurrent()
  local v = values()
  for _, e in ipairs(cardList) do
    if alive(e.widget) then
      local cur = C.isCurrent(e.key, e.card, v)
      e.widget:setBorderColor(cur and GOLD or IRON)
      e.widget:setBorderWidth(cur and 2 or 1)
    end
  end
end

local function refreshView()
  if not alive(window) then return end
  updateAddons()
  updateLayers()
  updateColors()
  updatePreview()
  updateStrip()
  updatePet()
  markCurrent()
end

-- ---------------------------------------------------------------- the grid
local function makeCard(grid, key, card)
  local w = g_ui.createWidget('CustomiseCard', grid)
  w:getChildById('name'):setText(card.text)
  paint(w, specOf(key, card), 116, 64, 48)
  local u = unlocks()
  if card.locked and u and type(u.styleEntry) == 'function' then
    u.styleEntry(w, { card.text, locked = true, how = card.how })
  else
    w:setTooltip(card.text)
  end
  w.onClick = function() pickCard(key, card) end
  w.onHoverChange = function(_, hovered) onCardHover(key, card, hovered) end
  cardList[#cardList + 1] = { widget = w, key = key, card = card }
end

local function rebuildGrid()
  if not alive(window) then return end
  cardToken = cardToken + 1
  local token = cardToken
  local grid = child('grid')
  local title = child('titleLabel')
  if not grid then return end
  grid:destroyChildren()
  cardList = {}
  local cards = C.cards(category, { lists = lists, src = src, onlyMine = onlyMine(), search = searchText })
  if not cards then
    title:setText(C.label(category) .. ' - ' .. tr('Loading...'))
    return
  end
  local have, all = C.count(cards)
  title:setText(tr('%s (%d of %d)', C.label(category), have, all))
  local made, key = 0, category
  local function step()
    if token ~= cardToken or not alive(window) then return end
    local last = math.min(made + BATCH, #cards)
    for i = made + 1, last do makeCard(grid, key, cards[i]) end
    made = last
    if made < #cards then scheduleEvent(step, 10) else markCurrent() end
  end
  step()
end

local function syncOnlyMine()
  local box = child('onlyMineBox')
  if not alive(box) then return end
  local u = unlocks()
  syncing = true
  box:setEnabled(u ~= nil)
  box:setChecked(onlyMine())
  syncing = false
end

local function setCategory(key)
  category = key
  searchText = ''
  local edit = child('searchEdit')
  if alive(edit) and edit:getText() ~= '' then
    muteSearch = true
    edit:setText('')
    muteSearch = false
  end
  syncOnlyMine()
  rebuildGrid()
  updateStrip()
end

-- a click on a card: pick it (its layer turns on, "none" turns it off), or look at it when it is locked
pickCard = function(key, card)
  if not alive(window) then return end
  if card.locked then
    local opt = C.hoverOption(temp, layers, key, card, outlineNow())
    if opt and preview then preview:setTry(opt, 8000) end
    return
  end
  if C.LOOK_KEYS[key] then
    temp = C.applyCard(temp, key, card)
  else
    chosen[key] = card.value
  end
  if C.LAYER_SET[key] and key ~= 'outfit' then
    touched[key] = true
    layers = C.pickLayers(layers, key, card)
  end
  refreshView()
end

-- ---------------------------------------------------------------- building the window (once)
local function buildStrip()
  local slots = child('slots')
  local cellH = mobile and 34 or 52
  pcall(function() slots:getLayout():setCellSize({ width = 116, height = cellH }) end)
  for _, key in ipairs(C.SLOTS) do
    local w = g_ui.createWidget('CustomiseStripCard', slots)
    w:setHeight(cellH)
    stripCards[key] = w
    w.onClick = function() setCategory(key) end
  end
end

local function buildLayers()
  local panel = child('layers')
  for _, key in ipairs(C.LAYERS) do
    local box = g_ui.createWidget('CustomiseLayerCheck', panel)
    box:setId('layer_' .. key)
    box:setText(C.label(key))
    box:setTooltip(key == 'outfit' and tr('Show the outfit in the preview') or tr('Wear it. Off: none of it is applied.'))
    box.onCheckChange = function(_, checked)
      if syncing then return end
      layers[key] = checked
      touched[key] = true
      -- a layer switched on with nothing picked: show the list to pick from
      if checked and key ~= 'outfit' then
        local v = values()
        if v[key] == C.defaultValue(key) then
          refreshView()
          setCategory(key)
          return
        end
      end
      refreshView()
    end
    layerBoxes[key] = box
  end
end

local function buildColors()
  local tabs = child('tabs')
  for _, t in ipairs(C.TABS) do
    local b = g_ui.createWidget('ChaosTabButton', tabs)
    b:setText(C.tabLabel(t.key))
    b:setWidth(mobile and 76 or 78)
    b:setHeight(22)
    local key = t.key
    b.onClick = function()
      colorTab = key
      updateColors()
    end
    tabButtons[key] = b
  end
  local pal = child('palette')
  local cell = mobile and 11 or 14
  pal:setWidth(cell * C.COLUMNS)
  pal:setHeight(cell * (C.COLORS / C.COLUMNS))
  pcall(function() pal:getLayout():setCellSize({ width = cell, height = cell }) end)
  for i = 0, C.COLORS - 1 do
    local w = g_ui.createWidget('CustomiseColorCell', pal)
    w:setSize({ width = cell, height = cell })
    w:setBackgroundColor(C.colorHex(i))
    local index = i
    w.onClick = function()
      temp = C.setColor(temp, colorTab, index)
      refreshView()
      if category == 'outfit' or category == 'wings' or category == 'aura' or category == 'shader' then rebuildGrid() end
    end
    palette[i] = w
  end
end

local function onSearch(text)
  if muteSearch then return end
  searchText = text or ''
  if searchEvent then removeEvent(searchEvent) end
  searchEvent = scheduleEvent(function()
    searchEvent = nil
    rebuildGrid()
  end, 200)
end

local function buildWindow()
  window = g_ui.displayUI('outfitextras')
  window:hide()
  buildStrip()
  buildLayers()
  buildColors()
  local lp = modules.game_lookpreview
  preview = lp and type(lp.create) == 'function' and lp.create(child('previewHost')) or nil
  if preview and mobile then
    -- the phone has no room for the panel's own boxes: the turn buttons stay
    local c = preview.widget and preview.widget.controls
    if c then
      for _, id in ipairs({ 'autoTurn', 'walk', 'simple', 'compare' }) do
        local b = c:getChildById(id)
        if b then b:setVisible(false) end
      end
      c:setHeight(30)
    end
  end
  child('searchEdit').onTextChange = function(_, text) onSearch(text) end
  child('onlyMineBox').onCheckChange = function(_, checked)
    if syncing then return end
    local u = unlocks()
    if u and type(u.setOnlyMine) == 'function' then u.setOnlyMine(category, checked) end
    rebuildGrid()
  end
  for _, a in ipairs({ 1, 2 }) do
    child('addon' .. a).onCheckChange = function(_, checked)
      if syncing then return end
      temp = C.setAddon(temp, a, checked)
      refreshView()
      if category == 'outfit' then rebuildGrid() end
    end
  end
end

-- ---------------------------------------------------------------- opening
local function open(...)
  local p = readPacket(...)
  if not p then error('the outfit window packet has no current outfit') end
  packet = p
  temp = readOutfit(p.outfit)
  original = C.copy(temp)
  chosen, touched = {}, {}
  layers = C.layerDefaults(original, nil)
  category, searchText, colorTab = 'outfit', '', 'head'
  readData()
  local edit = child('searchEdit')
  muteSearch = true
  edit:setText('')
  muteSearch = false
  window:show()
  window:raise()
  window:focus()
  syncOnlyMine()
  rebuildGrid()
  refreshView()
  ask()
end

local function onOpenOutfitWindow(...)
  retireBase(true)
  if not alive(window) then return end
  local ok, err = pcall(open, ...)
  if not ok then
    warn('open', err)
    -- the base window is the way back
    local o = modules.game_outfit
    if o and type(o.create) == 'function' then pcall(o.create, ...) end
    return
  end
  -- a base window built before this handler ran
  scheduleEvent(function() retireBase(true) end, 50)
end

local function closeWindow()
  if preview then pcall(preview.clearTry, preview) end
  if alive(window) then window:hide() end
  cardToken = cardToken + 1
  packet = nil
end

function cancel()
  closeWindow()
end

function clearSearch()
  local edit = child('searchEdit')
  if alive(edit) then edit:setText('') end
end

-- Ok: the cosmetics go to their modules, then the outfit through the base protocol
function accept()
  if not alive(window) or not packet then return end
  local OSL = shaderLogic()
  local outgoing = OSL and function(name) return OSL.outgoing(packet.shaders, name) end or nil
  local out = C.outfitToSend(temp, layers, outgoing)
  for _, a in ipairs(E.plan(rows, C.effective(rows, chosen, layers))) do
    local ok, err = pcall(function()
      if a.act == 'cosmetic' then
        local c = modules.game_cosmetics
        if c and c.selectCosmetic then c.selectCosmetic(a.kind, a.id, a.line) end
      elseif a.act == 'frame' then
        local i = modules.game_chaosinfo
        if i and i.usePlateFrame then i.usePlateFrame(a.value) end
      elseif a.act == 'pet' then
        local p = modules.game_pets
        if p then
          if a.value == '' then p.dismiss() else p.summonSpecies(a.value) end
        end
      end
    end)
    if not ok then warn('apply ' .. tostring(a.act), err) end
  end
  g_game.changeOutfit(out, false)
  closeWindow()
end

-- a source has new data (cosmetics, pets, services, the wardrobe catalogue): read it again, redraw once
function onData(source)
  if not alive(window) or not window:isVisible() or not packet then return end
  if redrawEvent then return end
  redrawEvent = scheduleEvent(function()
    redrawEvent = nil
    if not alive(window) or not packet then return end
    local ok, err = pcall(function()
      readData()
      rebuildGrid()
      refreshView()
    end)
    if not ok then warn('onData ' .. tostring(source), err) end
  end, 80)
end

-- ---------------------------------------------------------------- module
local function onGameStart()
  retireBase(false)
end

local function onGameEnd()
  closeWindow()
end

function init()
  mobile = g_app and type(g_app.isMobile) == 'function' and g_app.isMobile() == true or false
  local ok, err = pcall(buildWindow)
  if not ok then warn('build', err) end
  connect(g_game, { onOpenOutfitWindow = onOpenOutfitWindow, onGameStart = onGameStart, onGameEnd = onGameEnd })
  retireBase(false)
end

function terminate()
  disconnect(g_game, { onOpenOutfitWindow = onOpenOutfitWindow, onGameStart = onGameStart, onGameEnd = onGameEnd })
  if searchEvent then removeEvent(searchEvent) end
  if redrawEvent then removeEvent(redrawEvent) end
  searchEvent, redrawEvent = nil, nil
  cardToken = cardToken + 1
  -- give the packet back to the base window
  local o = modules.game_outfit
  if retired and o and type(o.create) == 'function' then pcall(connect, g_game, { onOpenOutfitWindow = o.create }) end
  retired = false
  if preview then pcall(preview.destroy, preview) end
  preview = nil
  if alive(window) then window:destroy() end
  window = nil
  packet = nil
  cardList, stripCards, palette, tabButtons, layerBoxes = {}, {}, {}, {}, {}
end

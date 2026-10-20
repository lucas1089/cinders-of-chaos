-- Cosmetics (server: server/data/scripts/chaos/cosmetics.lua, extended opcode 225, JSON {action, data}).
--   client -> server  open | select {kind, id, line} | preview {id} | hello (once in the game) | close
--   server -> client  state {open, line, lineName, rows, collection}   style {accent}   colors {names, full}
--                     looks {names, full}   tryfx {kind, art, pulse}   result {ok, text}
-- The window (Character > Cosmetics): spell effect skins of the character's class line, kill effects, loot label
-- accents, chat name colours, footprints and outlines; unlocks are account-wide, the choice per character. Preview
-- plays the effects for this player only (the server sends them); colours show a sample here; footprints and outlines
-- show on the character for a few seconds (game_cosmeticfx). The Collection tab lists the exclusives of every visual
-- kind (server exclusives.lua): never sold, earned from an achievement or a rare boss drop, and where each is chosen.
-- Two things this module draws itself:
--   * chat name colours: the stock console (game_console) Message:updateLabel is wrapped; in a player's line only the
--     speaker's name gets the colour the server sent (item link colours of game_chatlinks stay: this module loads after
--     it and reads the parts it drew);
--   * the loot label accent: handed to game_groundlabels (setAccent), which keeps the rarity colours.
-- Footprints and outlines are drawn by game_cosmeticfx: "looks" and "tryfx" are handed to it (setLooks, showPreview).
-- The shared preview beside the detail (game_lookpreview) plays a row's effects in a loop (the row's `play`: spell
-- skins and kill effects, the default effects too with "Compare with default"), walks the character over a
-- footprint's prints and draws an outline on it. List icons: a generated picture of the row's main effect
-- (images/fx/<name>.png, client/tools/sprites/gen_cosmetic_fx_icons.py), else its best frame from the sprites.
-- Every tab follows game_unlocks (one rule for every appearance list): rows not owned are greyed out with their source
-- in the tooltip, cannot be used, and "Only mine" (kept per character and tab) hides them.
-- The server's "wardrobe" answer (wardrobe.lua, the full outfit catalogue) comes on this opcode and goes to
-- game_unlocks for the Customise Character window.

local OPCODE = 225
local CL = CosmeticsLogic

local window
local state
local currentTab = 'spellskin'
local selectedId
local rowWidgets = {}
local tabButtons = {}
local names = {} -- chat name colours: character name -> '#rrggbb'
local settingBox = false -- the window sets the checkbox itself (not the player)
local accent -- the character's own label accent
local original = {}
local preview -- the shared look preview (game_lookpreview), nil without that module

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported then
        reported = true
        g_logger.warning('[cosmetics] ' .. name .. ': ' .. tostring(res))
      end
      return false
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function unlocks()
  local m = modules.game_unlocks
  return m and m.UnlocksCore and m or nil
end

local function tabRows()
  local rows
  if currentTab == 'collection' then
    rows = CL.collectionRows(state and state.collection or {})
  else
    rows = CL.tabRows(state and state.rows or {}, currentTab, state and state.line, state and state.lineName)
  end
  local u = unlocks()
  if u then rows = u.UnlocksCore.filter(rows, u.onlyMine(currentTab)) end
  return rows
end

local function lp()
  local m = modules.game_lookpreview
  return m and m.LookPreviewCore and m or nil
end

local FX_ICONS = '/modules/game_cosmetics/images/fx'

-- the picture of a row: its main effect (spell skins, kill effects), a footprint's print; nil = the item icon
local function drawIcon(widget, r, size)
  widget:destroyChildren()
  widget:setImageSource('')
  local m = lp()
  if m and type(r.play) == 'table' then
    local spec = m.LookPreviewCore.mainEffect(r.play)
    if spec and m.effectIcon(widget, spec, size, FX_ICONS) then return true end
  end
  if r.kind == 'footprint' and type(r.art) == 'string' and r.id ~= 0 then
    widget:setImageSource('/modules/game_cosmeticfx/images/prints/' .. r.art)
    return true
  end
  return false
end

local function fx()
  local m = modules.game_cosmeticfx
  return m and type(m.showPreview) == 'function' and m or nil
end

local function rowOf(id)
  for _, r in ipairs(tabRows()) do
    if r.id == id then return r end
  end
  return nil
end

-- ---------------------------------------------------------------- the sample under the detail
local function showSample(r)
  local box = window.detail.sample
  box:destroyChildren()
  local kind = r and r.kind or currentTab
  if kind == 'chatcolor' then
    local me = g_game.getLocalPlayer()
    local name = me and me:getName() or 'You'
    local level = me and me:getLevel() or 1
    local text = tr('%s %s [%s]: Hail, ash-walkers!', os.date('%H:%M'), name, level)
    local parts = { text, '#f0f000' }
    local colored = r and CL.validColor(r.color) and CL.colorLine(parts, text, { name = name, level = level },
      { [name] = r.color }) or parts
    local l = g_ui.createWidget('UILabel', box)
    l:setFont('verdana-11px-rounded')
    l:setTextAutoResize(true)
    l:setColoredText(colored)
    box:setBackgroundColor('#1c1a18')
  elseif CL.DRAWN[kind] then
    -- the outline is drawn on the character in the shared preview beside the detail; a footprint's print is the
    -- picture the map puts on the ground (the Preview button shows the real thing in the map)
    box:setBackgroundColor('#1c1a18')
    local holder = g_ui.createWidget('UIWidget', box)
    holder:setHeight(56)
    holder:setPhantom(true)
    local art = r and r.id ~= 0 and r.art or nil
    if kind == 'footprint' and art then
      for i, off in ipairs({ -70, 70 }) do
        local p = g_ui.createWidget('UIWidget', holder)
        p:setImageSource('/modules/game_cosmeticfx/images/prints/' .. art)
        p:setSize({ width = 40, height = 40 })
        p:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        p:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        p:setMarginLeft(off > 0 and off or 0)
        p:setMarginRight(off < 0 and -off or 0)
        -- no setRotation: inside a list a widget's rotation spills onto the rows drawn after it (the store's
        -- Footprints page drew turned, beta 2026-10-20)
        p:setPhantom(true)
      end
    end
  elseif kind == 'lootbeam' then
    box:setBackgroundColor('#2a2622')
    local bg = r and CL.validColor(r.accent) and r.accent or '#100c0ef0'
    for _, s in ipairs(CL.SAMPLE_RARITY) do
      local l = g_ui.createWidget('CosmeticSampleLabel', box)
      l:setText(tr('%s Ashen Blade', tr(s.name)))
      l:setColor(s.color)
      l:setBorderColor(s.color)
      l:setBackgroundColor(bg)
    end
  else
    box:setBackgroundColor('#1c1a18')
    local l = g_ui.createWidget('UILabel', box)
    l:setFont('verdana-11px-antialised')
    l:setTextWrap(true)
    l:setTextAutoResize(true)
    l:setColor('#a89c86')
    local text = tr('Everyone near you sees the chosen effects.')
    if r and r.id ~= 0 then
      text = type(r.play) == 'table' and #r.play > 0 and
        tr('The picture beside plays these effects. Preview plays them in the game around your character (only you see them).') or
        tr('Preview shows the effects around your character (only you see it).')
    end
    l:setText(text)
  end
end

-- the row's look on the character in the shared preview: outlines, footprints (a note) and the Collection's
-- outfits, mounts, wings, auras and shaders (LookPreviewCore.fromCosmeticRow); other rows: the character as worn
local function optionOf(r)
  local LP = LookPreviewCore or (modules.game_lookpreview and modules.game_lookpreview.LookPreviewCore)
  if not LP then return nil end
  return (LP.fromPlayRow and LP.fromPlayRow(r)) or LP.fromCosmeticRow(r)
end

local function showLook(d, r)
  if preview then preview:setOption(optionOf(r)) end
  if r.collection and optionOf(r) then d.item:setVisible(false) end
  -- the main effect or the print, large, in place of the item (an effect's item was a gem a few pixels big)
  local drawn = not r.collection and drawIcon(d.fxIcon, r, 64)
  d.fxIcon:setVisible(drawn == true)
  if drawn then d.item:setVisible(false) end
end

local function showDetail()
  if not window then return end
  local d = window.detail
  local r = rowOf(selectedId)
  d:setVisible(r ~= nil)
  if not r then return end
  d.item:setVisible(r.item ~= nil)
  if r.item then d.item:setItemId(r.item) end
  showLook(d, r)
  d.nameLabel:setText(r.name .. (r.selected and ('  (' .. tr('in use') .. ')') or ''))
  d.descLabel:setText((r.desc or '') .. (r.collection and r.use and ('\n' .. r.use) or ''))
  local how = r.how or ''
  if r.id == 0 then
    how = ''
  elseif r.owned then
    how = r.source == 'store' and tr('Unlocked for your account') or (tr('Unlocked') .. ' - ' .. how)
  end
  d.howLabel:setText(how)
  d.useButton:setVisible(not r.collection)
  local u = unlocks()
  d.useButton:setEnabled(CL.canUse(r) and (not u or u.UnlocksCore.canUse(r)))
  d.previewButton:setVisible(r.preview == true and not r.collection)
  d.storeButton:setVisible(r.source == 'store' and not r.owned)
  showSample(r)
  d.sample:setVisible(not r.collection and r.kind ~= 'outline')
end

local function pick(id)
  selectedId = id
  for k, w in pairs(rowWidgets) do
    if k == id then w:focus() end
  end
  showDetail()
end

local function showList()
  if not window or not state then return end
  for key, b in pairs(tabButtons) do b:setChecked(key == currentTab) end
  window.list:destroyChildren()
  rowWidgets = {}
  local rows = tabRows()
  local inUse
  for _, r in ipairs(rows) do
    local row = g_ui.createWidget('CosmeticRow', window.list)
    if r.item then
      row.item:setItemId(r.item)
    else
      row.item:setVisible(false)
    end
    if drawIcon(row.fx, r, 32) then
      row.item:setVisible(false)
      row.fx:setVisible(true)
    end
    local swatch = r.color or r.accent
    if swatch and CL.validColor(swatch) then
      row.item:setVisible(false)
      row.swatch:setVisible(true)
      row.swatch:setBackgroundColor(swatch)
    end
    row.name:setText(r.name .. (r.selected and '  *' or ''))
    row.sub:setText(CL.subText(r))
    if not r.owned or r.otherLine then
      row.name:setColor('#8c8070')
    end
    local u = unlocks()
    if u then
      u.styleEntry(row, r) -- greyed when locked, the source in the tooltip
    elseif not r.owned then
      row:setOpacity(0.45)
    end
    if r.otherLine then row.item:setOpacity(0.45) row.fx:setOpacity(0.45) end
    if r.selected then inUse = r.id end
    local id = r.id
    row.onClick = function() pick(id) end
    row.onHoverChange = function(_, hovered)
      if not preview then return end
      if hovered then preview:setHover(optionOf(r)) else preview:clearHover() end
    end
    rowWidgets[id] = row
  end
  local status = currentTab == 'spellskin' and (type(state.lineName) == 'string' and (tr('Your class line: ') .. state.lineName) or
    tr('Your class has no spell skins yet.')) or tr('Unlocks are for your whole account; each character chooses.')
  if CL.DRAWN[currentTab] then
    status = tr('Account-wide; each character chooses.') -- room for the checkbox beside it
  elseif currentTab == 'collection' then
    local have, all = CL.collectionCount(state.collection)
    -- (tr() formats its text: no % in it)
    status = tr('Earned') .. ' ' .. have .. ' / ' .. all .. ' ' .. tr('(never sold)')
  end
  window.statusLabel:setText(status)
  local u = unlocks()
  window.onlyMineBox:setVisible(u ~= nil)
  if u then
    u.bindOnlyMine(window.onlyMineBox, currentTab, function() showList() end)
  end
  -- footprints and outlines: hide other players' ones (this client only)
  local box = window.othersBox
  local m = fx()
  box:setVisible(CL.DRAWN[currentTab] == true and m ~= nil)
  if CL.DRAWN[currentTab] and m then
    local st = m.getSettings()
    box:setText(currentTab == 'footprint' and tr("Show other players' footprints") or tr("Show other players' outlines"))
    settingBox = true -- the onCheckChange below is ours, not the player's
    box:setChecked(currentTab == 'footprint' and st.othersFootprints or (currentTab == 'outline' and st.othersOutlines))
    settingBox = false
  end
  pick(rowOf(selectedId) and selectedId or inUse or 0)
end

function selectTab(key)
  currentTab = key
  selectedId = nil
  showList()
end

function show()
  if not window then return end
  if preview then preview:refresh() end -- the character may have changed its outfit
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
  elseif g_game.isOnline() then
    send('open')
  end
end

-- ---------------------------------------------------------------- for the Customise Character window (game_outfitextras)
-- That window lists the same choices as dropdowns: it reads the rows the server sent, asks for them without opening
-- this window (action "state"), and sends a choice the way Use does. It is told when a new state arrives.
function getState()
  return state
end

function requestState()
  if g_game.isOnline() then send('state') end
end

function selectCosmetic(kind, id, line)
  send('select', { kind = kind, id = id, line = line })
end

local function notifyExtras()
  local m = modules.game_outfitextras
  if m and type(m.onData) == 'function' then
    local ok, err = pcall(m.onData, 'cosmetics')
    if not ok then g_logger.warning('[cosmetics] outfit extras: ' .. tostring(err)) end
  end
end

function useCurrent()
  local r = rowOf(selectedId)
  if r and CL.canUse(r) then
    send('select', { kind = r.kind, id = r.id, line = r.line or (state and state.line) })
  end
end

function previewCurrent()
  local r = rowOf(selectedId)
  if not r or not r.preview then return end
  local m = fx()
  if CL.DRAWN[r.kind] and m then
    m.showPreview(r.kind, r.art, r.pulse) -- drawn here, no server round trip
  else
    send('preview', { id = r.id })
  end
end

function onOthersChanged(checked)
  local m = fx()
  if settingBox or not m then return end
  m.setSetting(currentTab == 'footprint' and 'othersFootprints' or 'othersOutlines', checked)
end

function openStore()
  local shop = modules.game_shop
  if shop and type(shop.toggle) == 'function' then shop.toggle() end
end

-- ---------------------------------------------------------------- loot label accent (game_groundlabels)
local function pushAccent()
  local gl = modules.game_groundlabels
  if gl and type(gl.setAccent) == 'function' then pcall(gl.setAccent, accent) end
end

-- ---------------------------------------------------------------- chat name colours (game_console)
local function console()
  return modules.game_console
end

local function wrappedUpdateLabel(self, label, tab)
  original.updateLabel(self, label, tab)
  if type(self.text) ~= 'string' or not self.name or self.name == '' or not names[self.name] then return end
  local types = MessageTypes or (console() and console().MessageTypes)
  local mt = types and types[self.mode]
  if not mt or mt.npcChat then return end
  local parts = label.chatParts or { self:format(), mt.color or 'white' }
  local t = {}
  for i = 1, #parts - 1, 2 do t[#t + 1] = parts[i] end
  local colored = CL.colorLine(parts, table.concat(t), { name = self.name, level = self.level }, names)
  if colored then label:setColoredText(colored) end
end

local function hookConsole()
  local c = console()
  if not c or not c.Message or original.updateLabel then return end
  original.updateLabel = c.Message.updateLabel
  c.Message.updateLabel = function(self, label, tab)
    local ok, err = pcall(wrappedUpdateLabel, self, label, tab)
    if not ok then
      g_logger.warning('[cosmetics] updateLabel: ' .. tostring(err))
      if not label.message then original.updateLabel(self, label, tab) end
    end
  end
end

local function unhookConsole()
  local c = console()
  if c and c.Message and original.updateLabel then
    c.Message.updateLabel = original.updateLabel
  end
  original.updateLabel = nil
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    showList()
    if data.open then show() end
    notifyExtras()
  elseif msg.action == 'style' then
    accent = CL.validColor(data.accent) and data.accent or nil
    pushAccent()
  elseif msg.action == 'colors' then
    names = CL.mergeColors(names, data)
  elseif msg.action == 'looks' then
    local m = fx()
    if m then m.setLooks(data) end
  elseif msg.action == 'tryfx' then
    local m = fx()
    if m and (data.kind == 'footprint' or data.kind == 'outline') then m.showPreview(data.kind, data.art, data.p or data.pulse) end
  elseif msg.action == 'wardrobe' then
    -- the full appearance catalogue (server wardrobe.lua) for the Customise Character window
    local u = unlocks()
    if u then u.setWardrobe(data) end
  elseif msg.action == 'result' then
    if window and data.text then
      window.statusLabel:setText(tostring(data.text))
      window.statusLabel:setColor(data.ok and '#8cd08c' or '#e07060')
      scheduleEvent(function()
        if window then window.statusLabel:setColor('#a89c86') end
      end, 4000)
    end
  end
end

-- once in the game: ask for the full style, colours and looks (what the server sends from its login event can reach
-- the client before it is in the game and is dropped, and a reconnect into a character still online runs no login
-- event: nobody's outline, footprints or chat colour showed until someone changed theirs)
local function onGameStart()
  scheduleEvent(function()
    if g_game.isOnline() then send('hello') end
  end, 500)
end

local function onGameEnd()
  hide()
  state, selectedId, rowWidgets = nil, nil, {}
  names, accent = {}, nil
  pushAccent()
end

function init()
  window = g_ui.displayUI('cosmetics')
  window:hide()
  local lp = modules.game_lookpreview
  preview = lp and type(lp.create) == 'function' and lp.create(window.lookPreview) or nil
  for _, k in ipairs(CL.KINDS) do
    local b = g_ui.createWidget('ChaosTabButton', window.tabs)
    b:setText(tr(k.name))
    b:setWidth(96)
    local key = k.key
    b.onClick = function() selectTab(key) end
    tabButtons[key] = b
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  hookConsole()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  unhookConsole()
  accent = nil
  pushAccent()
  if preview then preview:destroy() end
  preview = nil
  if window then window:destroy() end
  window = nil
end

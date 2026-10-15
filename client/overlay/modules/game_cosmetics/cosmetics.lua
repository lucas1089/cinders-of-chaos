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

local function tabRows()
  if currentTab == 'collection' then
    return CL.collectionRows(state and state.collection or {})
  end
  return CL.tabRows(state and state.rows or {}, currentTab, state and state.line, state and state.lineName)
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
    -- the character with its outline (the engine line; the glow picture behind it on an engine without one) / a
    -- print beside it (the Preview button shows the real thing in the map)
    box:setBackgroundColor('#1c1a18')
    local holder = g_ui.createWidget('UIWidget', box)
    holder:setHeight(56)
    holder:setPhantom(true)
    local me = g_game.getLocalPlayer()
    local art = r and r.id ~= 0 and r.art or nil
    local c
    if me then
      c = g_ui.createWidget('UICreature', holder)
      c:setSize({ width = 56, height = 56 })
      c:setOutfit(me:getOutfit())
      c:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
      c:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      c:setPhantom(true)
    end
    local lined = false
    if kind == 'outline' and art and c and fx() and type(fx().applyOutline) == 'function' then
      lined = fx().applyOutline(c:getCreature(), art, r.pulse) == true
    end
    if kind == 'outline' and art and not lined then
      local glow = g_ui.createWidget('UIWidget', holder)
      glow:setImageSource('/modules/game_cosmeticfx/images/glows/' .. art)
      glow:setSize({ width = 64, height = 64 })
      glow:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
      glow:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      glow:setPhantom(true)
      if c then holder:lowerChild(glow) end -- behind the character
    end
    if kind == 'footprint' and art then
      for i, off in ipairs({ -70, 70 }) do
        local p = g_ui.createWidget('UIWidget', holder)
        p:setImageSource('/modules/game_cosmeticfx/images/prints/' .. art)
        p:setSize({ width = 40, height = 40 })
        p:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        p:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        p:setMarginLeft(off > 0 and off or 0)
        p:setMarginRight(off < 0 and -off or 0)
        p:setRotation(i == 1 and 90 or 270)
        p:setPhantom(true)
      end
    end
  elseif kind == 'lootbeam' then
    box:setBackgroundColor('#2a2622')
    local bg = r and CL.validColor(r.accent) and r.accent or '#100c0ef0'
    for _, s in ipairs(CL.SAMPLE_RARITY) do
      local l = g_ui.createWidget('CosmeticSampleLabel', box)
      l:setText(tr('%s Ashen Blade', s.name))
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
    l:setText(r and r.id ~= 0 and tr('Preview shows the effects around your character (only you see it).') or
      tr('Everyone near you sees the chosen effects.'))
  end
end

-- a Collection row: the look on the character (outfits, mounts, wings, auras, shaders) or the item picture
local function showLook(d, r)
  local me = g_game.getLocalPlayer()
  local outfit
  if r.collection and me and (r.look or r.with) then
    outfit = me:getOutfit()
    if r.kind == 'outfit' or r.kind == 'addons' then
      outfit.type, outfit.addons = r.look, r.addons or 3
    elseif r.kind == 'mount' then
      outfit = { type = r.look }
    elseif r.kind == 'wings' then
      outfit.wings = r.look
    elseif r.kind == 'aura' then
      outfit.aura = r.look
    elseif r.kind == 'shader' then
      outfit.shader = r.shader
    end
  end
  d.creature:setVisible(outfit ~= nil)
  if outfit then
    d.creature:setOutfit(outfit)
    d.item:setVisible(false)
  end
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
  d.useButton:setEnabled(CL.canUse(r))
  d.previewButton:setVisible(r.preview == true and not r.collection)
  d.storeButton:setVisible(r.source == 'store' and not r.owned)
  showSample(r)
  d.sample:setVisible(not r.collection)
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
      row.item:setOpacity(0.45)
    end
    if r.selected then inUse = r.id end
    local id = r.id
    row.onClick = function() pick(id) end
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
  if window then window:destroy() end
  window = nil
end

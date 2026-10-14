-- Town Portal (server: server/data/scripts/chaos/townportal.lua, extended opcode 239, JSON {action, data}).
--   client -> server  open | get | select {id} | cast
--   server -> client  state {open, selected, cooldown, cooldownTotal, styles = [{id, name, desc, route, how, owned,
--                     selected, clientItem}]}     cast {ms}     castEnd {result}
-- The menu (Character -> Town Portal / Portal Style) calls cast and toggle; the action bar uses the spell
-- "Town Portal" (game_chaosspells) and lands in the same server code. While the portal opens a cast bar fills
-- over the character (game_castbar, the bar of the cast-time spells; without that module: above the bottom of the map).

local OPCODE = 239

local window
local state
local selectedId
local rowWidgets = {}
local castBar
local castEvent
local castStart, castMs
local refreshEvent

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function styleOf(id)
  for _, s in ipairs(state and state.styles or {}) do
    if s.id == id then return s end
  end
  return nil
end

local function routeText(s)
  if s.route == 'store' then return s.owned and tr('Store - owned') or (tr('Store') .. (s.price and (' - ' .. s.price .. ' coins') or ''))
  elseif s.route == 'achievement' then return s.owned and tr('Achievement - unlocked') or tr('Achievement - locked')
  elseif s.route == 'season' then return s.owned and tr('Season pass - unlocked') or tr('Season pass - locked')
  end
  return tr('Every character')
end

-- ---------------------------------------------------------------- window
local function showDetail()
  if not window then return end
  local d = window.detail
  local s = styleOf(selectedId)
  d:setVisible(s ~= nil)
  if not s then return end
  if s.clientItem then d.item:setItemId(s.clientItem) end
  d.nameLabel:setText(s.name .. (s.selected and ('  (' .. tr('in use') .. ')') or ''))
  d.descLabel:setText(s.desc or '')
  d.howLabel:setText(s.how or '')
  d.selectButton:setEnabled(s.owned and not s.selected)
  d.storeButton:setVisible(s.route == 'store' and not s.owned)
end

local function pick(id)
  selectedId = id
  for k, w in pairs(rowWidgets) do
    if k == id then w:focus() end
  end
  showDetail()
end

local function statusText()
  local left = state and tonumber(state.cooldown) or 0
  if left > 0 then
    return tr('Town Portal ready in %d s.', left)
  end
  return tr('Town Portal ready.')
end

local function showList()
  if not window or not state then return end
  window.styleList:destroyChildren()
  rowWidgets = {}
  for _, s in ipairs(state.styles or {}) do
    local row = g_ui.createWidget('PortalStyleRow', window.styleList)
    if s.clientItem then row.item:setItemId(s.clientItem) end
    row.name:setText(s.name .. (s.selected and '  *' or ''))
    row.sub:setText(routeText(s))
    if not s.owned then
      row.name:setColor('#8c8070')
      row.item:setOpacity(0.45)
    end
    local id = s.id
    row.onClick = function() pick(id) end
    rowWidgets[id] = row
  end
  window.statusLabel:setText(statusText())
  window.castButton:setEnabled((tonumber(state.cooldown) or 0) <= 0)
  pick(styleOf(selectedId) and selectedId or state.selected)
end

local function scheduleRefresh()
  if refreshEvent then removeEvent(refreshEvent) end
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    if window and window:isVisible() then
      if state and (tonumber(state.cooldown) or 0) > 0 then
        state.cooldown = state.cooldown - 1
        window.statusLabel:setText(statusText())
        window.castButton:setEnabled(state.cooldown <= 0)
      end
      scheduleRefresh()
    end
  end, 1000)
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  scheduleRefresh()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
  else
    send('open')
  end
end

function selectCurrent()
  if selectedId then send('select', { id = selectedId }) end
end

function openStore()
  local shop = modules.game_shop
  if shop and type(shop.toggle) == 'function' then shop.toggle() end
end

-- the menu entry and the window button; the action bar uses the spell
function cast()
  if g_game.isOnline() then send('cast') end
end

-- ---------------------------------------------------------------- cast bar
local function stopCastBar()
  if castEvent then removeEvent(castEvent) end
  castEvent = nil
  if castBar then castBar:hide() end
end

local function tickCastBar()
  castEvent = nil
  if not castBar or not castStart then return end
  local pct = math.min(100, (g_clock.millis() - castStart) * 100 / castMs)
  castBar:setPercent(pct)
  if pct < 100 then castEvent = scheduleEvent(tickCastBar, 50) end
end

-- the map panel runs under the console and the action bars (extended view): how much of its bottom they cover
local function coveredBottom(map)
  local gi = modules.game_interface
  local bottom = map:getY() + map:getHeight()
  local covered = 0
  for _, name in ipairs({ 'getBottomPanel', 'getBottomActionPanel' }) do
    local ok, w = pcall(function() return gi[name] and gi[name]() end)
    if ok and w and w:isVisible() and w:getHeight() > 0 and w:getY() < bottom then
      covered = math.max(covered, bottom - w:getY())
    end
  end
  return covered
end

local function startCastBar(ms)
  local map = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not castBar then
    if not map then return end
    castBar = g_ui.createWidget('TownPortalCastBar', map)
    castBar:setId('townPortalCastBar')
    castBar:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    castBar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  end
  -- 60 px above the bottom of the part of the map that is not covered (re-read on every cast: the layout can change)
  castBar:setMarginBottom(60 + (map and coveredBottom(map) or 0))
  castStart, castMs = g_clock.millis(), math.max(1, tonumber(ms) or 3000)
  castBar:setText(tr('Town Portal'))
  castBar:setPercent(0)
  if castEvent then removeEvent(castEvent) end
  castEvent = nil
  castBar:show()
  castBar:raise()
  tickCastBar()
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    -- the styles: tables with a name; anything else is left out (game_chaosguard/opcode_fuzz_test.lua)
    local styles = {}
    for _, s in ipairs(type(data.styles) == 'table' and data.styles or {}) do
      if type(s) == 'table' and s.id ~= nil then
        s.name = tostring(s.name or '?')
        styles[#styles + 1] = s
      end
    end
    data.styles = styles
    state = data
    showList()
    if data.open then show() end
  elseif msg.action == 'cast' then
    -- one cast bar for everything: game_castbar draws it over the character when it is loaded
    local cb = modules.game_castbar
    if cb and cb.startLocal then
      cb.startLocal(tr('Town Portal'), tonumber(data.ms) or 3000, 'portal')
    else
      startCastBar(data.ms)
    end
  elseif msg.action == 'castEnd' then
    local cb = modules.game_castbar
    if cb and cb.endLocal then cb.endLocal(tostring(data.result or 'done'), nil, 'portal') end
    stopCastBar()
  end
end

local function onGameEnd()
  hide()
  stopCastBar()
  state, selectedId, rowWidgets = nil, nil, {}
end

function init()
  window = g_ui.displayUI('townportal')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if refreshEvent then removeEvent(refreshEvent) end
  stopCastBar()
  if castBar then castBar:destroy() end
  castBar = nil
  if window then window:destroy() end
  window = nil
end

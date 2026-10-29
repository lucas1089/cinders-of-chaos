-- Chaos Pact window (server data/scripts/chaos/pact.lua, extended opcode 222, JSON {action, data}).
--   client -> server  open | sync | claim | marksBuy {key} | buildSave {slot?, name} | buildRename {slot, name} | buildDelete {slot} |
--                     buildLoad {slot}
--   server -> client  status {...} (open = true: show the window) | buildCode {slot, code} | message {text, error}
-- Menu: Character > Chaos Pact (added to client_chaos_topbar with ChaosTopBar.addEntry). Loading a saved build opens
-- the passive tree and asks the server for the preview of its code (game_passivetree build panel); Apply Build there.

local OPCODE = 222
local V = PactView
local COLS = { 186, 48, 96, 70, 60 } -- perk, free, Pact, bought, yours

local window
local status
local handlers = {}
local reported = {}
local armedDelete -- slot whose Delete was clicked once
local armedEvent

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[pact] ' .. name .. ': ' .. tostring(res))
      end
      return nil
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

local function note(text, color)
  if window then
    window.wallet:setText(text or '')
    window.wallet:setColor(color or '#8c8070')
  end
end

local function walletText()
  if not status then return '' end
  return tr('Chaos Coins: %d   Premium days: %d   Pact Marks claimed so far: %d',
    tonumber(status.coins) or 0, tonumber(status.premiumDays) or 0, tonumber(status.claimedTotal) or 0)
end

local function cell(parent, text, width, color, align)
  local c = g_ui.createWidget('PactCell', parent)
  c:setText(text)
  c:setWidth(width)
  if color then c:setColor(color) end
  if align then c:setTextAlign(align) end
  return c
end

local function fillLimits()
  local head = window.limitsHead
  head:destroyChildren()
  local titles = { tr('Perk'), tr('Free'), tr('Chaos Pact'), tr('Bought'), tr('Yours') }
  for i, t in ipairs(titles) do
    cell(head, t, COLS[i], '#e8b84a', i == 1 and AlignLeft or nil)
  end
  local list = window.limits
  list:destroyChildren()
  for _, r in ipairs(V.limitRows(status)) do
    local row = g_ui.createWidget('PactLimitRow', list)
    for i, t in ipairs(r) do
      local color = nil
      if i == 3 then color = t:find('off', 1, true) and '#6b6258' or (t ~= '-' and '#e07a4a' or nil) end
      if i == 5 then color = '#f6cf72' end
      cell(row, t, COLS[i], color, i == 1 and AlignLeft or nil)
    end
  end
end

local function fillMarks()
  window.marksLine:setText(V.marksLine(status))
  window.monthLine:setText(V.monthLine(status))
  local list = window.shelf
  list:destroyChildren()
  for _, r in ipairs(V.shelfRows(status)) do
    local w = g_ui.createWidget('PactShelfRow', list)
    w.name:setText(r.name)
    w.price:setText(r.price)
    w.name:setColor(r.owned and '#6b6258' or '#e8b84a')
    w.buyButton:setText(r.button)
    w.buyButton:setEnabled(r.canBuy)
    local key = r.key
    w.buyButton.onClick = safe('marksBuy', function() send('marksBuy', { key = key }) end)
  end
end

local function disarm()
  armedDelete = nil
  if armedEvent then removeEvent(armedEvent) armedEvent = nil end
end

local function fillBuilds()
  local list = window.builds
  list:destroyChildren()
  window.buildsPlate.buildsTitle:setText(V.buildHeader(status))
  local anyFree = false
  for _, r in ipairs(V.buildRows(status)) do
    local w = g_ui.createWidget('PactBuildRow', list)
    w.name:setText(string.format('%d. %s', r.slot, r.name))
    w.sub:setText(r.sub)
    if not r.saved then w.name:setColor('#8c8070') end
    if not r.editable then w:setOpacity(0.75) end
    anyFree = anyFree or (r.editable and not r.saved)
    w.loadButton:setVisible(r.saved)
    w.deleteButton:setVisible(r.saved)
    w.saveButton:setVisible(r.editable)
    w.saveButton:setText(r.saved and tr('Overwrite') or tr('Save here'))
    local slot = r.slot
    w.loadButton.onClick = safe('load', function() send('buildLoad', { slot = slot }) end)
    w.saveButton.onClick = safe('save', function()
      send('buildSave', { slot = slot, name = (r.saved and window.buildName:getText() == '') and r.name or window.buildName:getText() })
    end)
    w.deleteButton.onClick = safe('delete', function(self)
      if armedDelete == slot then
        disarm()
        send('buildDelete', { slot = slot })
        return
      end
      disarm()
      armedDelete = slot
      self:setText(tr('Sure?'))
      armedEvent = scheduleEvent(function()
        armedEvent = nil
        armedDelete = nil
        if not self:isDestroyed() then self:setText(tr('Delete')) end
      end, 3000)
    end)
  end
  window.saveNewButton:setEnabled(anyFree)
end

local function refresh()
  if not window or not status then return end
  local head, line = V.status(status)
  window.header.headline:setText(head)
  window.header.headline:setColor(status.active and '#e07a4a' or '#e8b84a')
  window.header.statusLine:setText(line)
  local text, enabled = V.claim(status)
  window.header.claimButton:setText(text)
  window.header.claimButton:setEnabled(enabled)
  window.header.storeButton:setText(status.active and tr('Extend in Store') or tr('Get it in Store'))
  note(walletText())
  fillLimits()
  fillMarks()
  window.special:setText(V.specialText(status))
  fillBuilds()
end

-- a saved build: open the passive tree and ask the server for its preview (Apply Build there takes it)
local function loadBuild(data)
  local pt = modules.game_passivetree
  if not pt or type(data) ~= 'table' or type(data.code) ~= 'string' then
    note(tr('The passive tree is not available.'), '#e07060')
    return
  end
  if not (pt.isVisible and pt.isVisible()) and pt.show then pt.show() end
  if pt.openBuildShare then pt.openBuildShare() end
  local tree = pt.getTreeWindow and pt.getTreeWindow()
  local edit = tree and tree:recursiveGetChildById('codeEdit')
  if edit then edit:setText(data.code) end
  if pt.sendAction then pt.sendAction('buildPreview', { code = data.code }) end
  note(tr('Build %d loaded into the passive tree: check the preview, then Apply Build.', tonumber(data.slot) or 0), '#80c070')
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  local d = msg.data
  if msg.action == 'status' then
    status = d
    disarm()
    refresh()
    if d.open and window then
      window:show()
      window:raise()
      window:focus()
    end
  elseif msg.action == 'buildCode' then
    loadBuild(d)
  elseif msg.action == 'message' then
    note(d.text or '', d.error and '#e07060' or '#80c070')
  end
end

function show()
  send('open')
end

function hide()
  disarm()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

function claim()
  send('claim')
end

function buyMarks(key)
  send('marksBuy', { key = key })
end

function saveBuild()
  if not window then return end
  send('buildSave', { name = window.buildName:getText() })
  window.buildName:setText('')
end

function openStore()
  local shop = modules.game_shop
  if shop and shop.toggle then shop.toggle() end
end

-- for other modules and tests
function getState()
  return { status = status, visible = window and window:isVisible() or false }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'character',
      { text = 'Chaos Pact', icon = 'daily', modules = { 'game_pact' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  status = nil
  addMenu()
  send('sync')
end

local function onGameEnd()
  hide()
  status = nil
end

function init()
  g_ui.importStyle('pact')
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local ok, ui = pcall(g_ui.createWidget, 'PactWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[pact] window not loaded: ' .. tostring(ui))
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disarm()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if window then window:destroy() window = nil end
  handlers = {}
end

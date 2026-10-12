-- Info & Services window: the player commands of the server, reached from the menu instead of the chat (character
-- info, store services, auto seller, house, rift keys, events, ancestral store, server info). Pages and texts:
-- chaosinfoview.lua. The top menu opens a page with openPage(id).
-- Server: server/data/scripts/chaos/commands_ui.lua, extended opcode 237 (JSON {action, data}).
--   client -> server  catalog                         which commands the server offers
--                     run {page, ids = {...}, params = {...}}
--   server -> client  catalog {ids, store = [{param, label, group}], vocations = "a|b|..."}
--                     result {page, parts = [{id, text}]}

local OPCODE = 237
local V = ChaosInfoView

local window
local catalog          -- last catalog (nil until the server answered)
local offered = {}     -- command id -> true
local current          -- id of the page shown
local fields = {}      -- field id -> widget of the page shown
local pageButtons = {}

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    local payload = data or {}
    payload.action = action
    protocol:sendExtendedOpcode(OPCODE, json.encode(payload))
  end
end

local function setOutput(text)
  if not window then return end
  window.output:setText(text or '')
  window.output:setCursorPos(0)
end

local function runIds(ids, params)
  if #ids == 0 then return end
  send('run', { page = current, ids = ids, params = params or {} })
end

local function fieldText(id)
  local w = fields[id]
  if not w then return '' end
  if w.getCurrentOption then
    local opt = w:getCurrentOption()
    return opt and (opt.data or opt.text) or ''
  end
  return w:getText()
end

-- a button: its command (then the page's auto commands again, to show the new state) or a client action
local function press(page, row, button)
  if button.fn == 'calendar' then
    local m = modules.game_schedule
    if m and m.toggle then m.toggle() end
    return
  elseif button.fn == 'invasions' then
    local m = modules.game_invasion
    if m and m.toggle then m.toggle() end
    return
  end
  local field = row.edit or row.combo
  local param = V.param(button.param, field and fieldText(field) or nil)
  if not param then
    setOutput(tr('Fill in "%s" first.', row.label or ''))
    return
  end
  local ids, params = { button.id }, { param }
  for _, id in ipairs(V.autoIds(page, offered)) do
    ids[#ids + 1] = id
    params[#params + 1] = ''
  end
  runIds(ids, params)
end

local function fillCombo(combo, options)
  combo:clearOptions()
  for _, o in ipairs(options) do
    combo:addOption(o.text, o.value)
  end
end

local function buildRows(page)
  local rows = window.rows
  rows:destroyChildren()
  fields = {}
  local height = 0
  for _, row in ipairs(page.rows or {}) do
    local visible = {}
    for _, b in ipairs(row.buttons or {}) do
      if V.buttonShown(b, offered) then visible[#visible + 1] = b end
    end
    if #visible > 0 then
      local line = g_ui.createWidget('ChaosInfoRow', rows)
      if row.label then
        local l = g_ui.createWidget('ChaosInfoRowLabel', line)
        l:setText(tr(row.label))
      end
      if row.edit then
        local e = g_ui.createWidget('ChaosTextEdit', line)
        e:setWidth(150)
        e:setHeight(24)
        e:setMaxLength(60)
        fields[row.edit] = e
      elseif row.combo then
        local c = g_ui.createWidget('ChaosComboBox', line)
        c:setWidth(150)
        c:setHeight(24)
        if row.combo == 'vocations' then
          fillCombo(c, V.vocationOptions(catalog and catalog.vocations))
        elseif row.combo == 'store' then
          fillCombo(c, V.storeOptions(catalog and catalog.store))
        end
        fields[row.combo] = c
      end
      for _, b in ipairs(visible) do
        local btn = g_ui.createWidget('ChaosInfoRowButton', line)
        btn:setText(tr(b.text))
        btn:setWidth(math.max(70, btn:getTextSize().width + 22))
        btn.onClick = function() press(page, row, b) end
      end
      height = height + 30
    end
  end
  rows:setHeight(height)
end

local function showPage(id)
  local page = V.page(id)
  if not page or not window then return end
  current = id
  for pid, b in pairs(pageButtons) do b:setChecked(pid == id) end
  window.pageTitle:setText(tr(page.title))
  window.pageText:setText(tr(page.text or ''))
  buildRows(page)
  local auto = V.autoIds(page, offered)
  if #auto > 0 then
    setOutput(tr('Loading...'))
    runIds(auto)
  else
    setOutput('')
  end
end

local function buildPageList()
  if not window then return end
  window.pageList:destroyChildren()
  pageButtons = {}
  for _, page in ipairs(V.PAGES) do
    if not catalog or V.pageShown(page, offered) then
      local b = g_ui.createWidget('ChaosInfoPageButton', window.pageList)
      b:setText(tr(page.title))
      b.onClick = function() showPage(page.id) end
      pageButtons[page.id] = b
    end
  end
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
  if window and window:isVisible() then hide() else openPage(current or 'character') end
end

function refresh()
  if current then showPage(current) end
end

-- the top menu: opens the window on a page
function openPage(id)
  if not window then return end
  if not catalog then send('catalog') end
  show()
  showPage(id)
end

-- true when the server offers this page (unknown before the catalog arrives: true)
function isPageOffered(id)
  if not catalog then return true end
  return V.pageShown(V.page(id), offered)
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'catalog' then
    catalog = d
    offered = V.idSet(d.ids)
    buildPageList()
    if window and window:isVisible() and current then
      for pid, b in pairs(pageButtons) do b:setChecked(pid == current) end
      buildRows(V.page(current))
    end
  elseif msg.action == 'result' then
    if window and (d.page == current or d.page == '') then
      local text = V.resultText(d.parts)
      setOutput(text ~= '' and text or tr('Nothing to show.'))
    end
  end
end

local function onGameStart()
  catalog, offered = nil, {}
  buildPageList()
  scheduleEvent(function() if g_game.isOnline() then send('catalog') end end, 1500)
end

local function onGameEnd()
  hide()
  catalog, offered, current = nil, {}, nil
end

function init()
  window = g_ui.displayUI('chaosinfo')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  buildPageList()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() window = nil end
  pageButtons, fields = {}, {}
end

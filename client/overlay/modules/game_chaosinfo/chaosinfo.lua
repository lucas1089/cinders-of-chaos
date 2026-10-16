-- Info & Services window: the player commands of the server, reached from the menu instead of the chat (character
-- info, store services, house, rift keys, events, ancestral store, server info). Pages and texts:
-- chaosinfoview.lua. The top menu opens a page with openPage(id).
-- Server: server/data/scripts/chaos/commands_ui.lua, extended opcode 237 (JSON {action, data}).
--   client -> server  catalog                         which commands the server offers
--                     run {page, ids = {...}, params = {...}}
--                     services                        the Services page state (tokens, free switch, frames, ...)
--                     store                           the Ancestral Store (entries, prices, the player's points)
--                     buy {id, count}                 buy one store entry (the server checks price and points)
--   server -> client  catalog {ids, vocations = "a|b|..."}
--                     result {page, parts = [{id, text}]}
--                     services {nameTokens, vocationTokens, freeSwitch, inTutorial, familiarReady, familiarLevel,
--                               webshopOrders, frames, activeFrame}
--                     store {points, entries = [{id, kind, name, item, price}], maxCount, message}

local OPCODE = 237
local V = ChaosInfoView
local ROW_SPACING = 6
local MIN_BUTTON = 70

local window
local catalog          -- last catalog (nil until the server answered)
local offered = {}     -- command id -> true
local current          -- id of the page shown
local fields = {}      -- field id -> widget of the page shown
local pageButtons = {}
local stateButtons = {} -- {widget, button} of the page shown that depend on the Services state
local services         -- last Services state (nil until the server answered)
local lastResult = ''  -- last command answer on the Services page
local storeData        -- last Ancestral Store answer

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

-- ---------------------------------------------------------------- Services status
local function servicesText(s)
  local lines = {}
  lines[#lines + 1] = tr('Name Change tokens: %d', s.nameTokens or 0)
  lines[#lines + 1] = tr('Vocation Change tokens: %d', s.vocationTokens or 0)
  if s.freeSwitch and s.freeSwitch ~= '' then
    lines[#lines + 1] = tr('Free switch: available (to %s)', s.freeSwitch)
  else
    lines[#lines + 1] = tr('Free switch: none')
  end
  if s.familiarReady then
    lines[#lines + 1] = tr('Familiar: available')
  else
    lines[#lines + 1] = tr('Familiar: from level %d', s.familiarLevel or 200)
  end
  if s.inTutorial then lines[#lines + 1] = tr('Tutorial: you are on the tutorial island') end
  if (s.webshopOrders or -1) >= 0 then
    lines[#lines + 1] = tr('Web shop items to claim: %d', s.webshopOrders)
  end
  local frames = V.frameOptions(s.frames)
  if #frames > 0 then
    local names = {}
    for _, f in ipairs(frames) do names[#names + 1] = f.text end
    lines[#lines + 1] = tr('Your frames: %s', table.concat(names, ', '))
  else
    lines[#lines + 1] = tr('Your frames: none (Store > Name Plates)')
  end
  if s.activeFrame and s.activeFrame ~= '' then
    lines[#lines + 1] = tr('Frame shown: %s', s.activeFrame:sub(1, 1):upper() .. s.activeFrame:sub(2))
  end
  return '[ ' .. tr('Status') .. ' ]\n' .. table.concat(lines, '\n')
end

local function showServices()
  if current ~= 'services' then return end
  local text = services and servicesText(services) or tr('Loading...')
  if lastResult ~= '' then
    text = '[ ' .. tr('Last action') .. ' ]\n' .. lastResult .. '\n\n' .. text
  end
  setOutput(text)
end

local function fillCombo(combo, options, empty)
  combo:clearOptions()
  for _, o in ipairs(options) do
    combo:addOption(o.text, o.value)
  end
  if #options == 0 and empty then combo:addOption(empty, '') end
end

-- enable / disable the buttons of the page by the Services state, with the reason as tooltip
local function applyState()
  for _, sb in ipairs(stateButtons) do
    local met = V.needMet(sb.button.need, services)
    sb.widget:setEnabled(met)
    if met then
      sb.widget:setTooltip(sb.button.hint and tr(sb.button.hint) or '')
    else
      sb.widget:setTooltip(tr(sb.button.why or sb.button.hint or ''))
    end
  end
  if fields.frames and services then
    fillCombo(fields.frames, V.frameOptions(services.frames), tr('No frames yet'))
  end
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
    setOutput(tr('Fill in "%s" first.', tr(row.label or '')))
    return
  end
  local ids, params = { button.id }, { param }
  for _, id in ipairs(V.autoIds(page, offered)) do
    ids[#ids + 1] = id
    params[#params + 1] = ''
  end
  runIds(ids, params)
end

-- ---------------------------------------------------------------- rows (every page: buttons wrap, none sticks out)
local function newLine(rows, indent)
  local line = g_ui.createWidget('ChaosInfoRow', rows)
  if indent > 0 then
    local spacer = g_ui.createWidget('UIWidget', line)
    spacer:setWidth(indent)
    spacer:setHeight(24)
    spacer:setPhantom(true)
  end
  return line
end

local function buildRows(page)
  local rows = window.rows
  rows:destroyChildren()
  fields = {}
  stateButtons = {}
  local avail = rows:getWidth()
  if avail < 200 then avail = window:getWidth() - 32 - 150 end
  local lines = 0
  for _, row in ipairs(page.rows or {}) do
    local visible = {}
    for _, b in ipairs(row.buttons or {}) do
      if V.buttonShown(b, offered) then visible[#visible + 1] = b end
    end
    if #visible > 0 then
      local line = g_ui.createWidget('ChaosInfoRow', rows)
      lines = lines + 1
      local used = 0
      if row.label then
        local l = g_ui.createWidget('ChaosInfoRowLabel', line)
        l:setText(tr(row.label))
        if row.hint then l:setTooltip(tr(row.hint)) end
        used = l:getWidth()
      end
      local indent = used
      if row.edit then
        local e = g_ui.createWidget('ChaosTextEdit', line)
        e:setWidth(150)
        e:setHeight(24)
        e:setMaxLength(60)
        if row.hint then e:setTooltip(tr(row.hint)) end
        if e.setPlaceholder and row.hint then e:setPlaceholder(tr(row.hint)) end
        fields[row.edit] = e
        used = used + (used > 0 and ROW_SPACING or 0) + 150
      elseif row.combo then
        local c = g_ui.createWidget('ChaosComboBox', line)
        c:setWidth(150)
        c:setHeight(24)
        if row.hint then c:setTooltip(tr(row.hint)) end
        if row.combo == 'vocations' then
          fillCombo(c, V.vocationOptions(catalog and catalog.vocations))
        elseif row.combo == 'frames' then
          fillCombo(c, V.frameOptions(services and services.frames), tr('No frames yet'))
        end
        fields[row.combo] = c
        used = used + (used > 0 and ROW_SPACING or 0) + 150
      end
      -- create the buttons on the first line to measure them, then move the ones that do not fit
      local widgets, widths = {}, {}
      for i, b in ipairs(visible) do
        local btn = g_ui.createWidget('ChaosInfoRowButton', line)
        btn:setText(tr(b.text))
        local w = math.max(MIN_BUTTON, btn:getTextSize().width + 22)
        btn:setWidth(w)
        if b.hint then btn:setTooltip(tr(b.hint)) end
        btn.onClick = function() press(page, row, b) end
        if b.need then stateButtons[#stateButtons + 1] = { widget = btn, button = b } end
        widgets[i], widths[i] = btn, w
      end
      local layout = V.wrapRow(used, widths, avail, indent, ROW_SPACING)
      for n = 2, #layout do
        local nextLine = newLine(rows, indent)
        lines = lines + 1
        for _, i in ipairs(layout[n]) do widgets[i]:setParent(nextLine) end
      end
    end
  end
  rows:setHeight(lines * 30)
  applyState()
end

-- ---------------------------------------------------------------- Ancestral Store
local function showStore()
  if not window or current ~= 'ancestral' then return end
  local list = window.storePanel.storeList
  list:destroyChildren()
  local rowsData, points = V.storeRows(storeData)
  if storeData then
    window.storePanel.storePoints:setText(tr('Your Ancestral Points: %d', points))
  else
    window.storePanel.storePoints:setText(tr('Loading...'))
  end
  local msg = storeData and type(storeData.message) == 'string' and storeData.message or ''
  window.storePanel.storeMessage:setText(msg)
  if storeData and #rowsData == 0 then
    local empty = g_ui.createWidget('ChaosLabelDim', list)
    empty:setText(tr('The store has nothing for sale.'))
    return
  end
  for _, r in ipairs(rowsData) do
    local row = g_ui.createWidget('ChaosStoreRow', list)
    if r.item > 0 then row.item:setItemId(r.item) end
    row.name:setText(r.name)
    row.kind:setText(tr(r.kind))
    row.price:setText(tr('%d points', r.price))
    row.buy:setText(tr('Buy'))
    if r.afford then
      row.buy:setTooltip(tr('Buy %s for %d Ancestral Points.', r.name, r.price))
      row.buy.onClick = function()
        row.buy:setEnabled(false)
        window.storePanel.storeMessage:setText(tr('Buying...'))
        send('buy', { id = r.id, count = 1 })
      end
    else
      row:setOpacity(0.5)
      row.buy:setEnabled(false)
      row.buy:setTooltip(tr('You need %d more Ancestral Points.', r.missing))
      row.price:setColor('#8c8070')
    end
  end
end

local function setStoreMode(on)
  window.storePanel:setVisible(on)
  window.outputFrame:setVisible(not on)
  window.output:setVisible(not on)
  window.outputScroll:setVisible(not on)
end

-- ---------------------------------------------------------------- pages
local function showPage(id)
  local page = V.page(id)
  if not page or not window then return end
  current = id
  for pid, b in pairs(pageButtons) do b:setChecked(pid == id) end
  window.pageTitle:setText(tr(page.title))
  window.pageText:setText(tr(page.text or ''))
  setStoreMode(page.store == true)
  buildRows(page)
  if page.store then
    showStore()
    send('store')
    return
  end
  if page.state == 'services' then
    lastResult = ''
    showServices()
    send('services')
    return
  end
  local auto = V.autoIds(page, offered)
  if #auto > 0 then
    setOutput(tr('Loading...'))
    runIds(auto)
  else
    setOutput(tr(page.idle or V.IDLE))
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
      local page = V.page(current)
      local text = V.resultText(d.parts, page and page.headings, tr)
      if page and page.state == 'services' then
        lastResult = text
        showServices()
        send('services') -- the tokens and frames may have changed
      else
        setOutput(text ~= '' and text or tr('Nothing to show.'))
      end
    end
  elseif msg.action == 'services' then
    services = d
    if window and current == 'services' then
      applyState()
      showServices()
    end
  elseif msg.action == 'store' then
    storeData = d
    showStore()
  end
end

local function onGameStart()
  catalog, offered, services, storeData = nil, {}, nil, nil
  buildPageList()
  scheduleEvent(function() if g_game.isOnline() then send('catalog') end end, 1500)
end

local function onGameEnd()
  hide()
  catalog, offered, current, services, storeData = nil, {}, nil, nil, nil
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
  pageButtons, fields, stateButtons = {}, {}, {}
end

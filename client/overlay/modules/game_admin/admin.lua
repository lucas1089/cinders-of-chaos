-- Chaos admin panel (client). Everything shown here is built from the "catalog" message the server
-- sends over extended opcode 120; the server re-checks permission on every action.

local OPCODE = 120
local MAX_RESULT_LINES = 300
local CONFIRM_MS = 4000

local window = nil
local windowButton = nil
local hotkeyBound = false

local catalog = nil          -- {categories = {{id,label,actions={...}}}}
local selectedCategory = "*" -- "*" = all
local selectedAction = nil
local paramWidgets = {}      -- ordered {spec = ..., widget = ...}
local nextRid = 1
local pendingRids = {}       -- rid -> action name
local confirmEvent = nil
local confirmArmed = false
local unlockEvent = nil
local resultLines = 0

local COLOR_OK = "#8fd18f"
local COLOR_FAIL = "#ee5a4a"
local COLOR_INFO = "#c9b7a6"

------------------------------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------------------------------
function init()
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
  -- JSON variant: the server splits the catalog (about 60 KB for the highest group, over the 8192 bytes one extended
  -- opcode message can carry) into S/P/E parts, which the base ProtocolGame joins and decodes before calling
  -- onExtendedOpcode
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onExtendedOpcode)

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
  ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
  destroy()
end

function onGameStart()
  -- Ask for the catalog shortly after login. Non-admins never receive an answer, so the panel never appears for them.
  scheduleEvent(function()
    if g_game.isOnline() then
      sendRequest("catalog")
    end
  end, 600)
end

function onGameEnd()
  destroy()
end

local function themeAvailable()
  local m = g_modules.getModule("client_chaos_theme")
  return m ~= nil and m:isLoaded()
end

function create()
  if window then return true end
  if not themeAvailable() then
    g_ui.importStyle("admin_fallback")
  end
  local ok, ui = pcall(g_ui.displayUI, "admin")
  if not ok or not ui then
    g_logger.error("[game_admin] could not load admin.otui: " .. tostring(ui))
    return false
  end
  window = ui
  window:hide()

  window:recursiveGetChildById("filterEdit").onTextChange = function() buildActionList() end
  window:recursiveGetChildById("runButton").onClick = onRunClicked

  local okB, btn = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton("adminButton", tr("Admin Panel"), "/images/topbuttons/logout", toggle)
  end)
  if okB then
    windowButton = btn
    windowButton:setOn(false)
    pcall(function() windowButton:setText(tr("ADM")) end)
  end

  if not hotkeyBound and modules.game_interface and modules.game_interface.getRootPanel then
    pcall(function()
      g_keyboard.bindKeyDown("Ctrl+Shift+F12", toggle, modules.game_interface.getRootPanel())
      hotkeyBound = true
    end)
  end
  return true
end

function destroy()
  if confirmEvent then removeEvent(confirmEvent); confirmEvent = nil end
  if unlockEvent then removeEvent(unlockEvent); unlockEvent = nil end
  if hotkeyBound then
    pcall(function() g_keyboard.unbindKeyDown("Ctrl+Shift+F12", modules.game_interface.getRootPanel()) end)
    hotkeyBound = false
  end
  if windowButton then windowButton:destroy(); windowButton = nil end
  if window then window:destroy(); window = nil end
  catalog = nil
  selectedCategory = "*"
  selectedAction = nil
  paramWidgets = {}
  pendingRids = {}
  confirmArmed = false
  resultLines = 0
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
  else
    show()
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if windowButton then windowButton:setOn(true) end
  refresh() -- always re-validate against the server when opening
end

function hide()
  if not window then return end
  window:hide()
  if windowButton then windowButton:setOn(false) end
end

function refresh()
  sendRequest("catalog")
end

------------------------------------------------------------------------------------------------
-- protocol
------------------------------------------------------------------------------------------------
function sendRequest(action, data)
  local protocol = g_game.getProtocolGame()
  if not protocol then return false end
  protocol:sendExtendedOpcode(OPCODE, json.encode({action = action, data = data}))
  return true
end

function onExtendedOpcode(protocol, code, msg)
  if not g_game.isOnline() then return end
  if type(msg) ~= "table" then return end

  if msg.action == "catalog" then
    onCatalog(msg.data)
  elseif msg.action == "result" then
    onResult(msg.data)
  end
end

-- the catalog as the window reads it: categories and actions that are tables with an id (anything else is left out,
-- so a bad entry cannot stop the list half built; game_chaosguard/opcode_fuzz_test.lua)
local function cleanCatalog(data)
  local categories = {}
  for _, c in ipairs(data.categories) do
    if type(c) == "table" and c.id ~= nil then
      local actions = {}
      for _, a in ipairs(type(c.actions) == "table" and c.actions or {}) do
        if type(a) == "table" and a.id ~= nil then
          a.id, a.name = tostring(a.id), tostring(a.name or a.id)
          if a.description ~= nil then a.description = tostring(a.description) end
          actions[#actions + 1] = a
        end
      end
      c.actions = actions
      categories[#categories + 1] = c
    end
  end
  data.categories = categories
  return data
end

function onCatalog(data)
  if type(data) ~= "table" or type(data.categories) ~= "table" then return end
  catalog = cleanCatalog(data)
  if not create() then return end

  -- keep selection if it still exists
  local found = false
  for _, c in ipairs(catalog.categories) do
    if c.id == selectedCategory then found = true end
  end
  if selectedCategory ~= "*" and not found then selectedCategory = "*" end
  if selectedAction then
    local still = findAction(selectedAction.id)
    selectedAction = still
  end
  buildSidebar()
  buildActionList()
  showAction(selectedAction)
end

function onResult(data)
  if type(data) ~= "table" or not window then return end
  local name = pendingRids[data.rid] or data.id or "?"
  pendingRids[data.rid] = nil
  unlockRun()
  addResultLine(string.format("[%s] %s", name, tostring(data.message or "")), data.ok and COLOR_OK or COLOR_FAIL)
  if type(data.lines) == "table" then
    for _, line in ipairs(data.lines) do
      addResultLine("  " .. tostring(line), COLOR_INFO)
    end
  end
end

------------------------------------------------------------------------------------------------
-- catalog helpers
------------------------------------------------------------------------------------------------
function findAction(id)
  if not catalog then return nil end
  for _, c in ipairs(catalog.categories) do
    for _, a in ipairs(c.actions) do
      if a.id == id then return a end
    end
  end
  return nil
end

------------------------------------------------------------------------------------------------
-- sidebar / list / form
------------------------------------------------------------------------------------------------
function buildSidebar()
  local list = window:recursiveGetChildById("categoryList")
  list:destroyChildren()

  local function add(id, label)
    local b = g_ui.createWidget("AdminCategoryButton", list)
    b:setText(label)
    b:setTooltip(label) -- a long server label ("Chaos: Guilds & Market") may not fit the sidebar
    b:setOn(selectedCategory == id)
    b.onClick = function()
      selectedCategory = id
      buildSidebar()
      buildActionList()
    end
  end

  add("*", tr("All actions"))
  for _, c in ipairs(catalog.categories) do
    add(c.id, c.label)
  end
end

function buildActionList()
  if not window or not catalog then return end
  local list = window:recursiveGetChildById("actionList")
  list:destroyChildren()
  local filter = window:recursiveGetChildById("filterEdit"):getText():lower()

  for _, c in ipairs(catalog.categories) do
    if selectedCategory == "*" or selectedCategory == c.id then
      for _, a in ipairs(c.actions) do
        local hay = (a.name .. " " .. a.id .. " " .. (a.description or "")):lower()
        if filter == "" or hay:find(filter, 1, true) then
          local b = g_ui.createWidget("AdminActionRow", list)
          b:setText(a.name)
          b:setTooltip(a.description or "")
          b:setOn(selectedAction ~= nil and selectedAction.id == a.id)
          b.onClick = function()
            showAction(a)
            buildActionList()
          end
        end
      end
    end
  end
end

local function addParamWidget(container, spec)
  local label = g_ui.createWidget("AdminParamLabel", container)
  label:setText(spec.label .. (spec.required and " *" or ""))

  local widget
  if spec.type == "bool" then
    label:setVisible(false)
    label:setHeight(0)
    widget = g_ui.createWidget("AdminParamCheck", container)
    widget:setText(spec.label)
    widget:setChecked(spec.default == true)
  elseif spec.type == "select" then
    widget = g_ui.createWidget("AdminParamCombo", container)
    for _, o in ipairs(spec.options or {}) do
      if type(o) == "table" then
        widget:addOption(o.label or tostring(o.value), o.value)
      else
        widget:addOption(tostring(o), o)
      end
    end
    if spec.default ~= nil then
      for i, o in ipairs(spec.options or {}) do
        local v = type(o) == "table" and o.value or o
        if tostring(v) == tostring(spec.default) then widget:setCurrentIndex(i) end
      end
    end
  else
    widget = g_ui.createWidget("AdminParamEdit", container)
    if spec.default ~= nil then widget:setText(tostring(spec.default)) end
    if spec.hint then widget:setTooltip(spec.hint) end
  end
  paramWidgets[#paramWidgets + 1] = {spec = spec, widget = widget}
end

function showAction(action)
  if not window then return end
  selectedAction = action
  paramWidgets = {}
  disarmConfirm()
  local container = window:recursiveGetChildById("paramList")
  container:destroyChildren()
  local title = window:recursiveGetChildById("actionTitle")
  local desc = window:recursiveGetChildById("actionDesc")
  local run = window:recursiveGetChildById("runButton")

  if not action then
    title:setText(tr("Select an action"))
    desc:setText("")
    run:setEnabled(false)
    run:setText(tr("Run"))
    return
  end

  title:setText(action.name .. (action.dangerous and tr("  (dangerous)") or ""))
  desc:setText(action.description or "")
  for _, spec in ipairs(action.params or {}) do
    addParamWidget(container, spec)
  end
  run:setEnabled(true)
  run:setText(tr("Run"))
end

local function collectParams()
  local params = {}
  for _, pw in ipairs(paramWidgets) do
    local spec, w = pw.spec, pw.widget
    local value
    if spec.type == "bool" then
      value = w:isChecked()
    elseif spec.type == "select" then
      local opt = w:getCurrentOption()
      value = opt and opt.data or nil
    else
      value = w:getText()
      if spec.type == "int" and value ~= "" and tonumber(value) then value = tonumber(value) end
    end
    if spec.required and (value == nil or value == "") then
      return nil, spec.label
    end
    params[spec.name] = value
  end
  return params
end

function disarmConfirm()
  confirmArmed = false
  if confirmEvent then removeEvent(confirmEvent); confirmEvent = nil end
  if window and selectedAction then
    window:recursiveGetChildById("runButton"):setText(tr("Run"))
  end
end

function unlockRun()
  if unlockEvent then removeEvent(unlockEvent); unlockEvent = nil end
  if window and selectedAction then
    window:recursiveGetChildById("runButton"):setEnabled(true)
  end
end

function onRunClicked()
  if not selectedAction or not window then return end
  local params, missing = collectParams()
  if not params then
    addResultLine(string.format("[%s] %s: %s", selectedAction.name, tr("missing required field"), missing), COLOR_FAIL)
    return
  end

  local run = window:recursiveGetChildById("runButton")
  if selectedAction.confirm and not confirmArmed then
    confirmArmed = true
    run:setText(tr("Click again to confirm"))
    confirmEvent = scheduleEvent(disarmConfirm, CONFIRM_MS)
    return
  end
  disarmConfirm()

  local rid = nextRid
  nextRid = nextRid + 1
  pendingRids[rid] = selectedAction.name
  if sendRequest("run", {rid = rid, id = selectedAction.id, params = params}) then
    run:setEnabled(false)
    unlockEvent = scheduleEvent(function() unlockEvent = nil; unlockRun() end, 3000)
    addResultLine("> " .. selectedAction.name, "#7f6a5f")
  end
end

------------------------------------------------------------------------------------------------
-- result area
------------------------------------------------------------------------------------------------
function addResultLine(text, color)
  if not window then return end
  local list = window:recursiveGetChildById("resultList")
  local label = g_ui.createWidget("AdminResultLine", list)
  label:setText(text)
  label:setColor(color or COLOR_INFO)
  resultLines = resultLines + 1
  if resultLines > MAX_RESULT_LINES then
    local first = list:getFirstChild()
    if first then first:destroy(); resultLines = resultLines - 1 end
  end
  scheduleEvent(function()
    if window then
      local bar = window:recursiveGetChildById("resultScroll")
      bar:setValue(bar:getMaximum())
    end
  end, 20)
end

function clearResults()
  if not window then return end
  window:recursiveGetChildById("resultList"):destroyChildren()
  resultLines = 0
end
